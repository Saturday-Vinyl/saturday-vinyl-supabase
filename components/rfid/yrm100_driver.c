/**
 * @file yrm100_driver.c
 * @brief YRM100 UHF RFID module driver implementation
 *
 * Provides low-level UART communication with the YRM100 RFID module.
 * The YRM100 uses a binary frame protocol at 115200 baud.
 *
 * Hardware Notes:
 * - UART1: GPIO4 (TX to module RX), GPIO5 (RX from module TX)
 * - GPIO6: Module enable pin (active high)
 * - Baud rate: 115200, 8N1
 *
 * Frame Format:
 * [Header:0xBB] [Type:1B] [Command:1B] [PL_MSB:1B] [PL_LSB:1B] [Params:N] [Checksum:1B] [End:0x7E]
 */

#include "yrm100_driver.h"
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
#define RFID_TX_PIN             4   /* ESP32 TX -> YRM100 RX */
#define RFID_RX_PIN             5   /* ESP32 RX <- YRM100 TX */
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

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    bool initialized;
    bool enabled;
    SemaphoreHandle_t uart_mutex;
    uint8_t tx_buf[MAX_FRAME_SIZE];
    uint8_t rx_buf[MAX_FRAME_SIZE];
} yrm100_state_t;

static yrm100_state_t s_rfid = {
    .initialized = false,
    .enabled = false,
    .uart_mutex = NULL,
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

    ESP_LOGD(TAG, "Sending command 0x%02X (%d bytes)", cmd, frame_len);
    ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_rfid.tx_buf, frame_len, ESP_LOG_DEBUG);

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
        ESP_LOGD(TAG, "No response received (timeout)");
        xSemaphoreGive(s_rfid.uart_mutex);
        return ESP_ERR_TIMEOUT;
    }

    ESP_LOGD(TAG, "Received %d bytes", rx_len);
    ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_rfid.rx_buf, rx_len, ESP_LOG_DEBUG);

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

    /* Configure enable pin */
    gpio_config_t en_conf = {
        .pin_bit_mask = (1ULL << RFID_EN_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t ret = gpio_config(&en_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure enable pin: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start with module disabled */
    gpio_set_level(RFID_EN_PIN, 0);
    s_rfid.enabled = false;

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

    gpio_set_level(RFID_EN_PIN, enable ? 1 : 0);
    s_rfid.enabled = enable;

    if (enable) {
        /* Give module time to power up */
        vTaskDelay(pdMS_TO_TICKS(100));
        ESP_LOGI(TAG, "YRM100 module enabled");
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

    esp_err_t ret = send_command(CMD_GET_FIRMWARE_VER, NULL, 0,
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

    if (type != FRAME_TYPE_RESPONSE || cmd != CMD_GET_FIRMWARE_VER) {
        ESP_LOGW(TAG, "Unexpected response: type=0x%02X, cmd=0x%02X", type, cmd);
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Copy version string (params contain version info) */
    size_t copy_len = (param_len < max_len - 1) ? param_len : max_len - 1;
    if (params != NULL && copy_len > 0) {
        memcpy(version, params, copy_len);
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

esp_err_t yrm100_single_poll(void)
{
    uint8_t response[64];
    size_t response_len = 0;

    esp_err_t ret = send_command(CMD_SINGLE_POLL, NULL, 0,
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

    if (type != FRAME_TYPE_RESPONSE) {
        return ESP_ERR_INVALID_RESPONSE;
    }

    /* Check if tag was found (response contains tag data) or not found (error code 0x15) */
    if (param_len >= 1 && params != NULL && params[0] == 0x15) {
        return ESP_ERR_NOT_FOUND;
    }

    /* Tag found - full parsing will be done in Phase 2 */
    ESP_LOGI(TAG, "Tag detected");
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
