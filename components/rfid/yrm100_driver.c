/**
 * @file yrm100_driver.c
 * @brief YRM100 UHF RFID module driver implementation
 *
 * Provides low-level UART communication with the YRM100 RFID module.
 * The YRM100 uses a binary frame protocol at 115200 baud.
 *
 * Hardware Notes:
 * - UART1: GPIO5 (TX to module RX), GPIO4 (RX from module TX)
 * - GPIO6: Module enable pin (active high)
 * - Baud rate: 115200, 8N1
 *
 * Frame Format:
 * [Header:0xBB] [Type:1B] [Command:1B] [PL_MSB:1B] [PL_LSB:1B] [Params:N] [Checksum:1B] [End:0x7E]
 *
 * Phase 2 additions:
 * - Tag data parsing with EPC, RSSI extraction
 * - Continuous polling with callback support
 * - Background polling FreeRTOS task
 */

#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "YRM100";

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/* Pin definitions - should match app_config.h */
#define RFID_UART_NUM           UART_NUM_1
#define RFID_TX_PIN             5   /* ESP32 TX -> YRM100 RX (GPIO5 = LP_UART_TXD) */
#define RFID_RX_PIN             4   /* ESP32 RX <- YRM100 TX (GPIO4 = LP_UART_RXD) */
#define RFID_EN_PIN             6   /* Enable pin (active high) */

/* UART configuration */
#define RFID_BAUD_RATE          115200
#define RFID_UART_BUF_SIZE      256
#define RFID_RX_TIMEOUT_MS      500

/* Frame protocol constants */
#define FRAME_HEADER            0xBB
#define FRAME_END               0x7E
#define FRAME_TYPE_COMMAND      0x00
#define FRAME_TYPE_RESPONSE     0x01
#define FRAME_TYPE_NOTICE       0x02

/* YRM100 Commands */
#define CMD_GET_FIRMWARE_VER    0x03
#define CMD_SINGLE_POLL         0x22
#define CMD_MULTIPLE_POLL       0x27
#define CMD_STOP_MULTIPLE_POLL  0x28
#define CMD_SET_RF_POWER        0xB6
#define CMD_GET_RF_POWER        0xB7

/* Maximum frame sizes */
#define MAX_FRAME_SIZE          128
#define MAX_PARAMS_SIZE         100

/* Polling task configuration */
#define POLLING_TASK_STACK_SIZE     4096
#define POLLING_TASK_PRIORITY       5
#define POLLING_TASK_NAME           "rfid_poll"

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    bool initialized;
    bool enabled;
    SemaphoreHandle_t uart_mutex;
    uint8_t tx_buf[MAX_FRAME_SIZE];
    uint8_t rx_buf[MAX_FRAME_SIZE];

    /* Polling task state (Phase 2) */
    TaskHandle_t poll_task_handle;
    bool poll_task_running;
    yrm100_poll_config_t poll_config;
    yrm100_tag_callback_t tag_callback;
    void *callback_user_data;

    /* Poll complete callback (Phase 3) */
    yrm100_poll_complete_callback_t poll_complete_callback;
    void *poll_complete_user_data;

    /* Statistics */
    uint32_t stat_total_polls;
    uint32_t stat_tags_detected;
    uint32_t stat_saturday_tags;
} yrm100_state_t;

static yrm100_state_t s_rfid = {
    .initialized = false,
    .enabled = false,
    .uart_mutex = NULL,
    .poll_task_handle = NULL,
    .poll_task_running = false,
    .tag_callback = NULL,
    .callback_user_data = NULL,
    .stat_total_polls = 0,
    .stat_tags_detected = 0,
    .stat_saturday_tags = 0,
};

/*******************************************************************************
 * Frame Protocol Functions
 ******************************************************************************/

/**
 * @brief Calculate checksum for frame
 * @param type Frame type byte
 * @param cmd Command byte
 * @param params Parameter bytes
 * @param param_len Number of parameter bytes
 * @return Checksum byte (low byte of sum)
 */
static uint8_t calculate_checksum(uint8_t type, uint8_t cmd, const uint8_t *params, uint16_t param_len)
{
    uint32_t sum = type + cmd;
    sum += (param_len >> 8) & 0xFF;  /* PL MSB */
    sum += param_len & 0xFF;          /* PL LSB */

    for (uint16_t i = 0; i < param_len; i++) {
        sum += params[i];
    }

    return (uint8_t)(sum & 0xFF);
}

/**
 * @brief Build a command frame
 * @param cmd Command code
 * @param params Parameter bytes (can be NULL if param_len is 0)
 * @param param_len Number of parameter bytes
 * @param out_buf Output buffer for frame
 * @return Total frame length
 */
static size_t build_frame(uint8_t cmd, const uint8_t *params, uint16_t param_len, uint8_t *out_buf)
{
    size_t idx = 0;

    out_buf[idx++] = FRAME_HEADER;
    out_buf[idx++] = FRAME_TYPE_COMMAND;
    out_buf[idx++] = cmd;
    out_buf[idx++] = (param_len >> 8) & 0xFF;  /* PL MSB */
    out_buf[idx++] = param_len & 0xFF;          /* PL LSB */

    if (params != NULL && param_len > 0) {
        memcpy(&out_buf[idx], params, param_len);
        idx += param_len;
    }

    out_buf[idx++] = calculate_checksum(FRAME_TYPE_COMMAND, cmd, params, param_len);
    out_buf[idx++] = FRAME_END;

    return idx;
}

/**
 * @brief Parse a response frame
 * @param buf Input buffer containing frame
 * @param len Length of input buffer
 * @param out_type Output: frame type
 * @param out_cmd Output: command code
 * @param out_params Output: pointer to params within buf
 * @param out_param_len Output: parameter length
 * @return true if valid frame, false otherwise
 */
static bool parse_frame(const uint8_t *buf, size_t len,
                        uint8_t *out_type, uint8_t *out_cmd,
                        const uint8_t **out_params, uint16_t *out_param_len)
{
    if (len < 7) {
        ESP_LOGD(TAG, "Frame too short: %d bytes", len);
        return false;
    }

    if (buf[0] != FRAME_HEADER) {
        ESP_LOGD(TAG, "Invalid header: 0x%02X", buf[0]);
        return false;
    }

    if (buf[len - 1] != FRAME_END) {
        ESP_LOGD(TAG, "Invalid end marker: 0x%02X", buf[len - 1]);
        return false;
    }

    uint8_t type = buf[1];
    uint8_t cmd = buf[2];
    uint16_t param_len = ((uint16_t)buf[3] << 8) | buf[4];

    /* Validate length */
    size_t expected_len = 7 + param_len;  /* Header(1) + Type(1) + Cmd(1) + PL(2) + Params(N) + Checksum(1) + End(1) */
    if (len != expected_len) {
        ESP_LOGD(TAG, "Length mismatch: got %d, expected %d", len, expected_len);
        return false;
    }

    /* Validate checksum */
    const uint8_t *params = (param_len > 0) ? &buf[5] : NULL;
    uint8_t expected_checksum = calculate_checksum(type, cmd, params, param_len);
    uint8_t received_checksum = buf[len - 2];

    if (received_checksum != expected_checksum) {
        ESP_LOGW(TAG, "Checksum mismatch: got 0x%02X, expected 0x%02X",
                 received_checksum, expected_checksum);
        return false;
    }

    *out_type = type;
    *out_cmd = cmd;
    *out_params = params;
    *out_param_len = param_len;

    return true;
}

/*******************************************************************************
 * UART Communication Functions
 ******************************************************************************/

/**
 * @brief Send a command and wait for response
 * @param cmd Command code
 * @param params Parameters (can be NULL)
 * @param param_len Parameter length
 * @param response Buffer for response frame
 * @param response_max_len Maximum response buffer size
 * @param response_len Output: actual response length
 * @param timeout_ms Timeout in milliseconds
 * @return ESP_OK on success
 */
static esp_err_t send_command(uint8_t cmd, const uint8_t *params, uint16_t param_len,
                              uint8_t *response, size_t response_max_len,
                              size_t *response_len, uint32_t timeout_ms)
{
    if (!s_rfid.initialized || !s_rfid.enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    if (xSemaphoreTake(s_rfid.uart_mutex, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        ESP_LOGW(TAG, "Failed to acquire UART mutex");
        return ESP_ERR_TIMEOUT;
    }

    /* Build and send frame */
    size_t frame_len = build_frame(cmd, params, param_len, s_rfid.tx_buf);

    ESP_LOGI(TAG, "Sending command 0x%02X (%d bytes)", cmd, frame_len);
    ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_rfid.tx_buf, frame_len, ESP_LOG_INFO);

    /* Clear RX buffer */
    uart_flush_input(RFID_UART_NUM);

    /* Send frame */
    int written = uart_write_bytes(RFID_UART_NUM, s_rfid.tx_buf, frame_len);
    if (written != frame_len) {
        ESP_LOGE(TAG, "UART write failed: wrote %d of %d bytes", written, frame_len);
        xSemaphoreGive(s_rfid.uart_mutex);
        return ESP_ERR_INVALID_SIZE;
    }

    /* Wait for response */
    int rx_len = uart_read_bytes(RFID_UART_NUM, s_rfid.rx_buf, response_max_len,
                                  pdMS_TO_TICKS(timeout_ms));

    if (rx_len <= 0) {
        ESP_LOGW(TAG, "No response received (timeout after %d ms)", timeout_ms);
        xSemaphoreGive(s_rfid.uart_mutex);
        return ESP_ERR_TIMEOUT;
    }

    ESP_LOGI(TAG, "Received %d bytes", rx_len);
    ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_rfid.rx_buf, rx_len, ESP_LOG_INFO);

    /* Copy response */
    if (response != NULL && response_max_len > 0) {
        size_t copy_len = (rx_len < response_max_len) ? rx_len : response_max_len;
        memcpy(response, s_rfid.rx_buf, copy_len);
        if (response_len != NULL) {
            *response_len = copy_len;
        }
    }

    xSemaphoreGive(s_rfid.uart_mutex);
    return ESP_OK;
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t yrm100_init(void)
{
    if (s_rfid.initialized) {
        ESP_LOGW(TAG, "YRM100 driver already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing YRM100 RFID driver");

    /* Create mutex */
    s_rfid.uart_mutex = xSemaphoreCreateMutex();
    if (s_rfid.uart_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Configure enable pin with pull-up to help drive the line */
    ESP_LOGI(TAG, "Configuring EN pin GPIO%d as output with pull-up", RFID_EN_PIN);
    gpio_config_t en_conf = {
        .pin_bit_mask = (1ULL << RFID_EN_PIN),
        .mode = GPIO_MODE_INPUT_OUTPUT,  /* Input/output so we can read back */
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t ret = gpio_config(&en_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure enable pin: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "EN pin configured successfully");

    /* Start with module disabled */
    gpio_set_level(RFID_EN_PIN, 0);
    s_rfid.enabled = false;
    ESP_LOGI(TAG, "EN pin set to 0 (disabled), readback=%d", gpio_get_level(RFID_EN_PIN));

    /* Configure UART */
    uart_config_t uart_config = {
        .baud_rate = RFID_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    ret = uart_driver_install(RFID_UART_NUM, RFID_UART_BUF_SIZE * 2, 0, 0, NULL, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install UART driver: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = uart_param_config(RFID_UART_NUM, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure UART: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = uart_set_pin(RFID_UART_NUM, RFID_TX_PIN, RFID_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set UART pins: %s", esp_err_to_name(ret));
        return ret;
    }

    s_rfid.initialized = true;
    ESP_LOGI(TAG, "YRM100 driver initialized successfully");

    return ESP_OK;
}

void yrm100_enable(bool enable)
{
    if (!s_rfid.initialized) {
        ESP_LOGW(TAG, "YRM100 not initialized");
        return;
    }

    if (enable == s_rfid.enabled) {
        return;
    }

    ESP_LOGI(TAG, "Setting EN pin GPIO%d to %d", RFID_EN_PIN, enable ? 1 : 0);
    esp_err_t ret = gpio_set_level(RFID_EN_PIN, enable ? 1 : 0);
    ESP_LOGI(TAG, "gpio_set_level returned: %s", esp_err_to_name(ret));
    s_rfid.enabled = enable;

    if (enable) {
        /* Give module time to power up - YRM100 needs ~500ms after enable */
        ESP_LOGI(TAG, "Waiting for YRM100 to initialize...");
        vTaskDelay(pdMS_TO_TICKS(500));
        int level = gpio_get_level(RFID_EN_PIN);
        ESP_LOGI(TAG, "YRM100 module enabled (GPIO%d level=%d after 500ms)", RFID_EN_PIN, level);
    } else {
        ESP_LOGI(TAG, "YRM100 module disabled");
    }
}

esp_err_t yrm100_get_firmware_version(char *version, size_t max_len)
{
    if (version == NULL || max_len == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t response[32];
    size_t response_len = 0;

    /* Per M100 protocol: parameter 0x00 = hardware version info */
    uint8_t params[] = {0x00};
    esp_err_t ret = send_command(CMD_GET_FIRMWARE_VER, params, sizeof(params),
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    /* Parse response */
    uint8_t type, cmd;
    const uint8_t *resp_params;
    uint16_t param_len;

    if (!parse_frame(response, response_len, &type, &cmd, &resp_params, &param_len)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    if (type != FRAME_TYPE_RESPONSE || cmd != CMD_GET_FIRMWARE_VER) {
        ESP_LOGW(TAG, "Unexpected response: type=0x%02X, cmd=0x%02X", type, cmd);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Copy version string (resp_params contain version info) */
    size_t copy_len = (param_len < max_len - 1) ? param_len : max_len - 1;
    if (resp_params != NULL && copy_len > 0) {
        memcpy(version, resp_params, copy_len);
    }
    version[copy_len] = '\0';

    ESP_LOGI(TAG, "Firmware version: %s", version);
    return ESP_OK;
}

esp_err_t yrm100_set_rf_power(uint8_t power_dbm)
{
    if (power_dbm > 30) {
        ESP_LOGW(TAG, "RF power capped to 30 dBm (requested %d)", power_dbm);
        power_dbm = 30;
    }

    /* SetRfPower parameters: [Reserved:0x05] [Power:1B] */
    uint8_t params[] = {0x05, power_dbm};
    uint8_t response[16];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_SET_RF_POWER, params, sizeof(params),
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    /* Parse response */
    uint8_t type, cmd;
    const uint8_t *resp_params;
    uint16_t param_len;

    if (!parse_frame(response, response_len, &type, &cmd, &resp_params, &param_len)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    if (type != FRAME_TYPE_RESPONSE || cmd != CMD_SET_RF_POWER) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    ESP_LOGI(TAG, "RF power set to %d dBm", power_dbm);
    return ESP_OK;
}

esp_err_t yrm100_get_rf_power(uint8_t *power_dbm)
{
    if (power_dbm == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t response[16];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_GET_RF_POWER, NULL, 0,
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    /* Parse response */
    uint8_t type, cmd;
    const uint8_t *params;
    uint16_t param_len;

    if (!parse_frame(response, response_len, &type, &cmd, &params, &param_len)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    if (type != FRAME_TYPE_RESPONSE || cmd != CMD_GET_RF_POWER) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Response params: [Reserved:0x05] [Power:1B] */
    if (param_len >= 2 && params != NULL) {
        *power_dbm = params[1];
        ESP_LOGI(TAG, "Current RF power: %d dBm", *power_dbm);
    } else {
        return ESP_ERR_INVALID_RESPONSE;
    }

    return ESP_OK;
}

esp_err_t yrm100_start_polling(void)
{
    /* MultiplePoll parameters: [Reserved:0x22] [RepeatCount_MSB] [RepeatCount_LSB]
     * RepeatCount = 0x0000 means continuous polling until stopped */
    uint8_t params[] = {0x22, 0x00, 0x00};
    uint8_t response[16];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_MULTIPLE_POLL, params, sizeof(params),
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    ESP_LOGI(TAG, "Continuous polling started");
    return ESP_OK;
}

esp_err_t yrm100_stop_polling(void)
{
    uint8_t response[16];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_STOP_MULTIPLE_POLL, NULL, 0,
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    ESP_LOGI(TAG, "Polling stopped");
    return ESP_OK;
}

bool yrm100_is_enabled(void)
{
    return s_rfid.initialized && s_rfid.enabled;
}

esp_err_t yrm100_single_poll(void)
{
    return yrm100_single_poll_with_data(NULL);
}

esp_err_t yrm100_single_poll_with_data(rfid_tag_t *tag)
{
    uint8_t response[64];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_SINGLE_POLL, NULL, 0,
                                  response, sizeof(response), &response_len,
                                  RFID_RX_TIMEOUT_MS);
    if (ret != ESP_OK) {
        return ret;
    }

    /* Parse response frame */
    rfid_frame_t frame;
    if (!rfid_parse_frame(response, response_len, &frame)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Accept both RESPONSE and NOTICE frames for tag data:
     * - RESPONSE (0x01) with command 0xFF = error/no-tag response
     * - NOTICE (0x02) with command 0x22 = tag detected
     */
    if (frame.type == RFID_FRAME_TYPE_RESPONSE) {
        /* Error response - check for "no tag found" (0x15) */
        if (frame.command == 0xFF && frame.param_len >= 1 && frame.params != NULL) {
            if (frame.params[0] == RFID_RESP_TAG_NOT_FOUND) {
                return ESP_ERR_NOT_FOUND;
            }
            ESP_LOGD(TAG, "Response error code: 0x%02X", frame.params[0]);
            return ESP_ERR_NOT_FOUND;
        }
    } else if (frame.type != RFID_FRAME_TYPE_NOTICE) {
        ESP_LOGD(TAG, "Unexpected frame type: 0x%02X", frame.type);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Tag found - parse if requested */
    if (tag != NULL) {
        if (!rfid_parse_tag(&frame, tag)) {
            ESP_LOGW(TAG, "Failed to parse tag data");
            return ESP_ERR_INVALID_RESPONSE;
        }

        char epc_str[25];
        rfid_epc_to_hex_string(tag->epc, tag->epc_len, epc_str, sizeof(epc_str));
        ESP_LOGI(TAG, "Tag detected: EPC=%s, RSSI=%d dBm, Saturday=%s",
                 epc_str, rfid_rssi_to_dbm(tag->rssi),
                 tag->is_saturday_tag ? "yes" : "no");
    } else {
        ESP_LOGI(TAG, "Tag detected");
    }

    return ESP_OK;
}

esp_err_t yrm100_read_tag_notice(rfid_tag_t *tag, uint32_t timeout_ms)
{
    if (tag == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!s_rfid.initialized || !s_rfid.enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    if (xSemaphoreTake(s_rfid.uart_mutex, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }

    /* Read data from UART */
    int rx_len = uart_read_bytes(RFID_UART_NUM, s_rfid.rx_buf, MAX_FRAME_SIZE,
                                  pdMS_TO_TICKS(timeout_ms));

    if (rx_len <= 0) {
        xSemaphoreGive(s_rfid.uart_mutex);
        return ESP_ERR_TIMEOUT;
    }

    ESP_LOGD(TAG, "Received %d bytes", rx_len);
    ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_rfid.rx_buf, rx_len, ESP_LOG_DEBUG);

    xSemaphoreGive(s_rfid.uart_mutex);

    /* Find and parse frame */
    size_t frame_start, frame_len;
    if (!rfid_find_frame(s_rfid.rx_buf, rx_len, &frame_start, &frame_len)) {
        ESP_LOGD(TAG, "No valid frame found in received data");
        return ESP_ERR_INVALID_RESPONSE;
    }

    rfid_frame_t frame;
    if (!rfid_parse_frame(&s_rfid.rx_buf[frame_start], frame_len, &frame)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Check if this is a tag notice */
    if (frame.type != RFID_FRAME_TYPE_NOTICE) {
        ESP_LOGD(TAG, "Frame is not a notice (type=0x%02X)", frame.type);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Parse tag data */
    if (!rfid_parse_tag(&frame, tag)) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    return ESP_OK;
}

/*******************************************************************************
 * Additional Functions for Testing (Phase 1)
 ******************************************************************************/

/**
 * @brief Send raw bytes to RFID module (for testing/debugging)
 */
esp_err_t yrm100_send_raw(const uint8_t *data, size_t len)
{
    if (!s_rfid.initialized || !s_rfid.enabled) {
        return ESP_ERR_INVALID_STATE;
    }

    if (xSemaphoreTake(s_rfid.uart_mutex, pdMS_TO_TICKS(1000)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }

    int written = uart_write_bytes(RFID_UART_NUM, data, len);
    xSemaphoreGive(s_rfid.uart_mutex);

    return (written == len) ? ESP_OK : ESP_ERR_INVALID_SIZE;
}

/**
 * @brief Receive raw bytes from RFID module (for testing/debugging)
 */
int yrm100_receive_raw(uint8_t *buf, size_t max_len, uint32_t timeout_ms)
{
    if (!s_rfid.initialized || !s_rfid.enabled) {
        return -1;
    }

    if (xSemaphoreTake(s_rfid.uart_mutex, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        return -1;
    }

    int rx_len = uart_read_bytes(RFID_UART_NUM, buf, max_len, pdMS_TO_TICKS(timeout_ms));
    xSemaphoreGive(s_rfid.uart_mutex);

    return rx_len;
}

/*******************************************************************************
 * Background Polling Task (Phase 2)
 ******************************************************************************/

/**
 * @brief Background task that continuously polls for RFID tags
 *
 * Uses single polls with intervals rather than continuous polling mode
 * for better control and cleaner code.
 */
static void rfid_polling_task(void *arg)
{
    ESP_LOGI(TAG, "RFID polling task started (interval=%dms, power=%ddBm)",
             s_rfid.poll_config.poll_interval_ms,
             s_rfid.poll_config.rf_power_dbm);

    /* Configure RF power */
    esp_err_t ret = yrm100_set_rf_power(s_rfid.poll_config.rf_power_dbm);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to set RF power: %s", esp_err_to_name(ret));
    }

    rfid_tag_t tag;
    char epc_str[25];

    while (s_rfid.poll_task_running) {
        /* Perform single poll with tag data */
        ret = yrm100_single_poll_with_data(&tag);
        s_rfid.stat_total_polls++;

        bool tag_detected = false;

        if (ret == ESP_OK) {
            /* Tag detected */
            tag_detected = true;
            s_rfid.stat_tags_detected++;

            if (tag.is_saturday_tag) {
                s_rfid.stat_saturday_tags++;
            }

            /* Apply filter if configured */
            bool should_report = true;
            if (s_rfid.poll_config.filter_saturday_only && !tag.is_saturday_tag) {
                should_report = false;
                ESP_LOGD(TAG, "Filtered non-Saturday tag");
            }

            /* Invoke callback if registered */
            if (should_report && s_rfid.tag_callback != NULL) {
                rfid_epc_to_hex_string(tag.epc, tag.epc_len, epc_str, sizeof(epc_str));
                ESP_LOGD(TAG, "Invoking callback for tag: %s", epc_str);
                s_rfid.tag_callback(&tag, s_rfid.callback_user_data);
            }
        } else if (ret == ESP_ERR_NOT_FOUND) {
            /* No tag - this is normal */
            ESP_LOGD(TAG, "No tag in field");
        } else if (ret == ESP_ERR_TIMEOUT) {
            /* Module not responding - log occasionally */
            if (s_rfid.stat_total_polls % 20 == 0) {
                ESP_LOGW(TAG, "RFID module timeout (poll #%lu)",
                         (unsigned long)s_rfid.stat_total_polls);
            }
        } else {
            ESP_LOGD(TAG, "Poll error: %s", esp_err_to_name(ret));
        }

        /* Invoke poll complete callback if registered (Phase 3) */
        if (s_rfid.poll_complete_callback != NULL) {
            s_rfid.poll_complete_callback(tag_detected, s_rfid.poll_complete_user_data);
        }

        /* Wait for next poll interval */
        vTaskDelay(pdMS_TO_TICKS(s_rfid.poll_config.poll_interval_ms));
    }

    ESP_LOGI(TAG, "RFID polling task stopped");
    s_rfid.poll_task_handle = NULL;
    vTaskDelete(NULL);
}

void yrm100_register_tag_callback(yrm100_tag_callback_t callback, void *user_data)
{
    s_rfid.tag_callback = callback;
    s_rfid.callback_user_data = user_data;

    if (callback != NULL) {
        ESP_LOGI(TAG, "Tag callback registered");
    } else {
        ESP_LOGI(TAG, "Tag callback unregistered");
    }
}

void yrm100_register_poll_complete_callback(yrm100_poll_complete_callback_t callback, void *user_data)
{
    s_rfid.poll_complete_callback = callback;
    s_rfid.poll_complete_user_data = user_data;

    if (callback != NULL) {
        ESP_LOGI(TAG, "Poll complete callback registered");
    } else {
        ESP_LOGI(TAG, "Poll complete callback unregistered");
    }
}

esp_err_t yrm100_start_polling_task(const yrm100_poll_config_t *config)
{
    if (!s_rfid.initialized) {
        ESP_LOGE(TAG, "YRM100 not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_rfid.poll_task_running) {
        ESP_LOGW(TAG, "Polling task already running");
        return ESP_ERR_INVALID_STATE;
    }

    /* Apply configuration */
    if (config != NULL) {
        s_rfid.poll_config = *config;
    } else {
        yrm100_poll_config_t default_config = YRM100_POLL_CONFIG_DEFAULT();
        s_rfid.poll_config = default_config;
    }

    /* Reset statistics */
    s_rfid.stat_total_polls = 0;
    s_rfid.stat_tags_detected = 0;
    s_rfid.stat_saturday_tags = 0;

    /* Enable the module if not already enabled */
    if (!s_rfid.enabled) {
        yrm100_enable(true);
    }

    /* Start the task */
    s_rfid.poll_task_running = true;
    BaseType_t result = xTaskCreate(
        rfid_polling_task,
        POLLING_TASK_NAME,
        POLLING_TASK_STACK_SIZE,
        NULL,
        POLLING_TASK_PRIORITY,
        &s_rfid.poll_task_handle
    );

    if (result != pdPASS) {
        ESP_LOGE(TAG, "Failed to create polling task");
        s_rfid.poll_task_running = false;
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGI(TAG, "Polling task started");
    return ESP_OK;
}

esp_err_t yrm100_stop_polling_task(void)
{
    if (!s_rfid.poll_task_running) {
        ESP_LOGW(TAG, "Polling task not running");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Stopping polling task...");

    /* Signal task to stop */
    s_rfid.poll_task_running = false;

    /* Wait for task to finish (up to 2 seconds) */
    for (int i = 0; i < 20 && s_rfid.poll_task_handle != NULL; i++) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    if (s_rfid.poll_task_handle != NULL) {
        ESP_LOGW(TAG, "Polling task did not stop gracefully, forcing delete");
        vTaskDelete(s_rfid.poll_task_handle);
        s_rfid.poll_task_handle = NULL;
    }

    ESP_LOGI(TAG, "Polling task stopped (polls=%lu, tags=%lu, saturday=%lu)",
             (unsigned long)s_rfid.stat_total_polls,
             (unsigned long)s_rfid.stat_tags_detected,
             (unsigned long)s_rfid.stat_saturday_tags);

    return ESP_OK;
}

bool yrm100_is_polling_task_running(void)
{
    return s_rfid.poll_task_running;
}

void yrm100_get_poll_stats(uint32_t *total_polls, uint32_t *tags_detected,
                            uint32_t *saturday_tags)
{
    if (total_polls != NULL) {
        *total_polls = s_rfid.stat_total_polls;
    }
    if (tags_detected != NULL) {
        *tags_detected = s_rfid.stat_tags_detected;
    }
    if (saturday_tags != NULL) {
        *saturday_tags = s_rfid.stat_saturday_tags;
    }
}
