/**
 * @file s3_comm.c
 * @brief S3 Communication Implementation for ESP32-H2
 *
 * Implements UART-based communication protocol between H2 (slave) and S3 (master).
 * Handles command reception, response transmission, and event notifications.
 *
 * Phase H2-3: S3 Communication
 */

#include "s3_comm.h"
#include "thread_br.h"
#include "h2_version.h"
#include "coap_ota.h"
#include "coap_cmd_client.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "S3_COMM";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(S3_COMM_EVENTS);

/*******************************************************************************
 * Module State
 ******************************************************************************/

static bool s_initialized = false;
static TaskHandle_t s_rx_task_handle = NULL;
static SemaphoreHandle_t s_tx_mutex = NULL;

/* Statistics */
static s3_comm_stats_t s_stats = {0};

/* Frame parser state */
typedef enum {
    PARSE_STATE_HEADER,
    PARSE_STATE_TYPE,
    PARSE_STATE_LENGTH_LOW,
    PARSE_STATE_LENGTH_HIGH,
    PARSE_STATE_PAYLOAD,
    PARSE_STATE_CRC_LOW,
    PARSE_STATE_CRC_HIGH,
    PARSE_STATE_END,
} parse_state_t;

static parse_state_t s_parse_state = PARSE_STATE_HEADER;
static s3h2_frame_t s_rx_frame;
static uint16_t s_rx_payload_idx = 0;
static uint16_t s_rx_crc_received = 0;

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void rx_task(void *arg);
static void process_byte(uint8_t byte);
static void process_frame(void);
static void handle_command(uint8_t cmd_type, const uint8_t *payload, uint16_t len);
static esp_err_t send_frame(uint8_t type, const void *payload, uint16_t len);

/* Command handlers */
static void handle_ping(void);
static void handle_get_status(void);
static void handle_get_credentials(void);
static void handle_get_version(void);
static void handle_start_thread(void);
static void handle_stop_thread(void);
static void handle_enable_joining(const uint8_t *payload, uint16_t len);
static void handle_disable_joining(void);
static void handle_reset_credentials(void);
static void handle_enter_bootloader(void);
static void handle_reset(void);

/* Phase 4: OTA command handlers */
static void handle_ota_start_crate(const uint8_t *payload, uint16_t len);
static void handle_ota_data_crate(const uint8_t *payload, uint16_t len);
static void handle_ota_verify_crate(const uint8_t *payload, uint16_t len);
static void handle_ota_abort_crate(const uint8_t *payload, uint16_t len);
static void handle_ping_crate(const uint8_t *payload, uint16_t len);

/* CoAP Mesh Protocol command handler */
static void handle_relay_cmd(const uint8_t *payload, uint16_t len);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t s3_comm_init(void)
{
    if (s_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing S3 communication...");

    /* Create TX mutex */
    s_tx_mutex = xSemaphoreCreateMutex();
    if (s_tx_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create TX mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Configure UART */
    uart_config_t uart_config = {
        .baud_rate = S3_COMM_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t ret = uart_driver_install(S3_COMM_UART_NUM,
                                         S3_COMM_RX_BUF_SIZE,
                                         S3_COMM_TX_BUF_SIZE,
                                         0, NULL, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install UART driver: %s", esp_err_to_name(ret));
        vSemaphoreDelete(s_tx_mutex);
        return ret;
    }

    ret = uart_param_config(S3_COMM_UART_NUM, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure UART: %s", esp_err_to_name(ret));
        uart_driver_delete(S3_COMM_UART_NUM);
        vSemaphoreDelete(s_tx_mutex);
        return ret;
    }

    ret = uart_set_pin(S3_COMM_UART_NUM,
                       S3_COMM_UART_TX_PIN,
                       S3_COMM_UART_RX_PIN,
                       UART_PIN_NO_CHANGE,
                       UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set UART pins: %s", esp_err_to_name(ret));
        uart_driver_delete(S3_COMM_UART_NUM);
        vSemaphoreDelete(s_tx_mutex);
        return ret;
    }

    /* Reset parser state */
    s_parse_state = PARSE_STATE_HEADER;
    memset(&s_rx_frame, 0, sizeof(s_rx_frame));
    memset(&s_stats, 0, sizeof(s_stats));

    /* Create RX task */
    BaseType_t xret = xTaskCreate(rx_task, "s3_comm_rx",
                                   S3_COMM_TASK_STACK_SIZE,
                                   NULL,
                                   S3_COMM_TASK_PRIORITY,
                                   &s_rx_task_handle);
    if (xret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create RX task");
        uart_driver_delete(S3_COMM_UART_NUM);
        vSemaphoreDelete(s_tx_mutex);
        return ESP_ERR_NO_MEM;
    }

    s_initialized = true;
    ESP_LOGI(TAG, "S3 communication initialized (UART%d, %d baud)",
             S3_COMM_UART_NUM, S3_COMM_UART_BAUD);
    return ESP_OK;
}

esp_err_t s3_comm_deinit(void)
{
    if (!s_initialized) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Deinitializing S3 communication...");

    /* Stop RX task */
    if (s_rx_task_handle != NULL) {
        vTaskDelete(s_rx_task_handle);
        s_rx_task_handle = NULL;
    }

    /* Uninstall UART driver */
    uart_driver_delete(S3_COMM_UART_NUM);

    /* Delete mutex */
    if (s_tx_mutex != NULL) {
        vSemaphoreDelete(s_tx_mutex);
        s_tx_mutex = NULL;
    }

    s_initialized = false;
    ESP_LOGI(TAG, "S3 communication deinitialized");
    return ESP_OK;
}

bool s3_comm_is_initialized(void)
{
    return s_initialized;
}

/*******************************************************************************
 * RX Task and Frame Parser
 ******************************************************************************/

static void rx_task(void *arg)
{
    uint8_t rx_buf[128];

    ESP_LOGI(TAG, "RX task started");

    while (1) {
        int len = uart_read_bytes(S3_COMM_UART_NUM, rx_buf, sizeof(rx_buf),
                                  pdMS_TO_TICKS(S3_COMM_RX_TIMEOUT_MS));
        if (len > 0) {
            for (int i = 0; i < len; i++) {
                process_byte(rx_buf[i]);
            }
        }
    }
}

static void process_byte(uint8_t byte)
{
    switch (s_parse_state) {
        case PARSE_STATE_HEADER:
            if (byte == S3H2_FRAME_HEADER) {
                memset(&s_rx_frame, 0, sizeof(s_rx_frame));
                s_rx_payload_idx = 0;
                s_parse_state = PARSE_STATE_TYPE;
            }
            break;

        case PARSE_STATE_TYPE:
            s_rx_frame.type = byte;
            s_parse_state = PARSE_STATE_LENGTH_LOW;
            break;

        case PARSE_STATE_LENGTH_LOW:
            s_rx_frame.length = byte;
            s_parse_state = PARSE_STATE_LENGTH_HIGH;
            break;

        case PARSE_STATE_LENGTH_HIGH:
            s_rx_frame.length |= ((uint16_t)byte << 8);
            if (s_rx_frame.length > S3H2_MAX_PAYLOAD_LEN) {
                ESP_LOGW(TAG, "Payload too long: %d", s_rx_frame.length);
                s_stats.rx_errors++;
                s_parse_state = PARSE_STATE_HEADER;
            } else if (s_rx_frame.length == 0) {
                s_parse_state = PARSE_STATE_CRC_LOW;
            } else {
                s_parse_state = PARSE_STATE_PAYLOAD;
            }
            break;

        case PARSE_STATE_PAYLOAD:
            if (s_rx_payload_idx < s_rx_frame.length) {
                s_rx_frame.payload[s_rx_payload_idx++] = byte;
            }
            if (s_rx_payload_idx >= s_rx_frame.length) {
                s_parse_state = PARSE_STATE_CRC_LOW;
            }
            break;

        case PARSE_STATE_CRC_LOW:
            s_rx_crc_received = byte;
            s_parse_state = PARSE_STATE_CRC_HIGH;
            break;

        case PARSE_STATE_CRC_HIGH:
            s_rx_crc_received |= ((uint16_t)byte << 8);
            s_parse_state = PARSE_STATE_END;
            break;

        case PARSE_STATE_END:
            s_parse_state = PARSE_STATE_HEADER;
            if (byte == S3H2_FRAME_END) {
                /* Verify CRC */
                uint8_t crc_data[3 + S3H2_MAX_PAYLOAD_LEN];
                crc_data[0] = s_rx_frame.type;
                crc_data[1] = s_rx_frame.length & 0xFF;
                crc_data[2] = (s_rx_frame.length >> 8) & 0xFF;
                memcpy(&crc_data[3], s_rx_frame.payload, s_rx_frame.length);

                uint16_t calc_crc = s3h2_crc16(crc_data, 3 + s_rx_frame.length);
                if (calc_crc == s_rx_crc_received) {
                    s_stats.rx_frames++;
                    s_stats.last_rx_time_ms = esp_timer_get_time() / 1000;
                    process_frame();
                } else {
                    ESP_LOGW(TAG, "CRC mismatch: calc=0x%04X recv=0x%04X",
                             calc_crc, s_rx_crc_received);
                    s_stats.rx_errors++;
                }
            } else {
                ESP_LOGW(TAG, "Invalid frame end: 0x%02X", byte);
                s_stats.rx_errors++;
            }
            break;

        default:
            s_parse_state = PARSE_STATE_HEADER;
            break;
    }
}

static void process_frame(void)
{
    ESP_LOGD(TAG, "Frame received: type=0x%02X len=%d",
             s_rx_frame.type, s_rx_frame.length);

    handle_command(s_rx_frame.type, s_rx_frame.payload, s_rx_frame.length);
}

/*******************************************************************************
 * Command Handler Dispatch
 ******************************************************************************/

static void handle_command(uint8_t cmd_type, const uint8_t *payload, uint16_t len)
{
    s_stats.commands_processed++;

    switch (cmd_type) {
        case S3H2_CMD_PING:
            handle_ping();
            break;

        case S3H2_CMD_GET_STATUS:
            handle_get_status();
            break;

        case S3H2_CMD_GET_CREDENTIALS:
            handle_get_credentials();
            break;

        case S3H2_CMD_GET_VERSION:
            handle_get_version();
            break;

        case S3H2_CMD_START_THREAD:
            handle_start_thread();
            break;

        case S3H2_CMD_STOP_THREAD:
            handle_stop_thread();
            break;

        case S3H2_CMD_ENABLE_JOINING:
            handle_enable_joining(payload, len);
            break;

        case S3H2_CMD_DISABLE_JOINING:
            handle_disable_joining();
            break;

        case S3H2_CMD_RESET_CREDENTIALS:
            handle_reset_credentials();
            break;

        case S3H2_CMD_ENTER_BOOTLOADER:
            handle_enter_bootloader();
            break;

        case S3H2_CMD_RESET:
            handle_reset();
            break;

        /* Phase 4: Crate OTA Commands */
        case S3H2_CMD_OTA_START_CRATE:
            handle_ota_start_crate(payload, len);
            break;

        case S3H2_CMD_OTA_DATA_CRATE:
            handle_ota_data_crate(payload, len);
            break;

        case S3H2_CMD_OTA_VERIFY_CRATE:
            handle_ota_verify_crate(payload, len);
            break;

        case S3H2_CMD_OTA_ABORT_CRATE:
            handle_ota_abort_crate(payload, len);
            break;

        case S3H2_CMD_PING_CRATE:
            handle_ping_crate(payload, len);
            break;

        /* CoAP Mesh Protocol */
        case S3H2_CMD_RELAY_CMD:
            handle_relay_cmd(payload, len);
            break;

        default:
            ESP_LOGW(TAG, "Unknown command: 0x%02X", cmd_type);
            s3_comm_send_nak(S3H2_ERR_INVALID_CMD);
            break;
    }
}

/*******************************************************************************
 * Command Handlers
 ******************************************************************************/

static void handle_ping(void)
{
    ESP_LOGD(TAG, "PING received");
    s3_comm_send_pong();

    /* Post connected event */
    esp_event_post(S3_COMM_EVENTS, S3_COMM_EVENT_CONNECTED, NULL, 0,
                   pdMS_TO_TICKS(100));
}

static void handle_get_status(void)
{
    ESP_LOGD(TAG, "GET_STATUS received");

    s3h2_status_payload_t status = {0};

    thread_br_state_t state = thread_br_get_state();

    /* Map thread_br_state_t to s3h2_thread_state_t */
    switch (state) {
        case THREAD_BR_STATE_DISABLED:
            status.thread_state = S3H2_THREAD_STATE_DISABLED;
            break;
        case THREAD_BR_STATE_DETACHED:
            status.thread_state = S3H2_THREAD_STATE_DETACHED;
            break;
        case THREAD_BR_STATE_ATTACHING:
            status.thread_state = S3H2_THREAD_STATE_ATTACHING;
            break;
        case THREAD_BR_STATE_CHILD:
            status.thread_state = S3H2_THREAD_STATE_CHILD;
            break;
        case THREAD_BR_STATE_ROUTER:
            status.thread_state = S3H2_THREAD_STATE_ROUTER;
            break;
        case THREAD_BR_STATE_LEADER:
            status.thread_state = S3H2_THREAD_STATE_LEADER;
            break;
        default:
            status.thread_state = S3H2_THREAD_STATE_DISABLED;
            break;
    }

    thread_br_status_t br_status;
    if (thread_br_get_status(&br_status) == ESP_OK) {
        status.pan_id = br_status.pan_id;
        status.channel = br_status.channel;
        status.rloc16 = br_status.rloc16;
        status.device_count = br_status.device_count;
    }

    status.joining_enabled = thread_br_is_joining_enabled() ? 1 : 0;

    s3_comm_send_status(&status);
}

static void handle_get_credentials(void)
{
    ESP_LOGD(TAG, "GET_CREDENTIALS received");

    /* Ensure credentials exist */
    esp_err_t ret = thread_br_ensure_credentials();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to ensure credentials: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_NO_CREDENTIALS);
        return;
    }

    thread_network_credentials_t creds;
    ret = thread_br_get_credentials(&creds);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to get credentials: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_NO_CREDENTIALS);
        return;
    }

    s3h2_credentials_payload_t payload = {0};
    strncpy(payload.network_name, creds.network_name, sizeof(payload.network_name) - 1);
    payload.pan_id = creds.pan_id;
    payload.channel = creds.channel;
    memcpy(payload.network_key, creds.network_key, sizeof(payload.network_key));
    memcpy(payload.extended_pan_id, creds.extended_pan_id, sizeof(payload.extended_pan_id));
    memcpy(payload.mesh_local_prefix, creds.mesh_local_prefix, sizeof(payload.mesh_local_prefix));

    s3_comm_send_credentials(&payload);
}

static void handle_get_version(void)
{
    ESP_LOGD(TAG, "GET_VERSION received");

    s3h2_version_payload_t version = {
        .major = H2_FW_VERSION_MAJOR,
        .minor = H2_FW_VERSION_MINOR,
        .patch = H2_FW_VERSION_PATCH,
    };

    s3_comm_send_version(&version);
}

static void handle_start_thread(void)
{
    ESP_LOGI(TAG, "START_THREAD received");

    esp_err_t ret = thread_br_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to init Thread BR: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    ret = thread_br_start();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start Thread BR: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    s3_comm_send_ack();
}

static void handle_stop_thread(void)
{
    ESP_LOGI(TAG, "STOP_THREAD received");

    esp_err_t ret = thread_br_stop();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to stop Thread BR: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    s3_comm_send_ack();
}

static void handle_enable_joining(const uint8_t *payload, uint16_t len)
{
    ESP_LOGI(TAG, "ENABLE_JOINING received");

    uint32_t duration_sec = 120;  /* Default 2 minutes */

    if (len >= sizeof(s3h2_enable_joining_payload_t)) {
        const s3h2_enable_joining_payload_t *p = (const s3h2_enable_joining_payload_t *)payload;
        duration_sec = p->duration_sec;
    }

    ESP_LOGI(TAG, "Enabling joining for %lu seconds", (unsigned long)duration_sec);

    esp_err_t ret = thread_br_enable_joining(duration_sec);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to enable joining: %s", esp_err_to_name(ret));
        if (ret == ESP_ERR_INVALID_STATE) {
            s3_comm_send_nak(S3H2_ERR_NOT_ATTACHED);
        } else {
            s3_comm_send_nak(S3H2_ERR_INTERNAL);
        }
        return;
    }

    s3_comm_send_ack();
}

static void handle_disable_joining(void)
{
    ESP_LOGI(TAG, "DISABLE_JOINING received");

    esp_err_t ret = thread_br_disable_joining();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to disable joining: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    s3_comm_send_ack();
}

static void handle_reset_credentials(void)
{
    ESP_LOGI(TAG, "RESET_CREDENTIALS received");

    /* Must stop Thread first */
    thread_br_stop();
    thread_br_deinit();

    esp_err_t ret = thread_br_clear_credentials();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to clear credentials: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    ret = thread_br_generate_credentials();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to generate credentials: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
        return;
    }

    s3_comm_send_ack();
}

static void handle_enter_bootloader(void)
{
    ESP_LOGI(TAG, "ENTER_BOOTLOADER received - resetting to download mode");

    /* Send ACK before reset */
    s3_comm_send_ack();

    /* Small delay to ensure ACK is transmitted */
    vTaskDelay(pdMS_TO_TICKS(100));

    /* Set GPIO4 low for download mode, then reset */
    gpio_reset_pin(GPIO_NUM_4);
    gpio_set_direction(GPIO_NUM_4, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_NUM_4, 0);

    /* Trigger software reset */
    esp_restart();
}

static void handle_reset(void)
{
    ESP_LOGI(TAG, "RESET received");

    /* Send ACK before reset */
    s3_comm_send_ack();

    /* Small delay to ensure ACK is transmitted */
    vTaskDelay(pdMS_TO_TICKS(100));

    esp_restart();
}

/*******************************************************************************
 * Frame Transmission
 ******************************************************************************/

static esp_err_t send_frame(uint8_t type, const void *payload, uint16_t len)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (len > S3H2_MAX_PAYLOAD_LEN) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Build frame buffer */
    uint8_t frame_buf[7 + S3H2_MAX_PAYLOAD_LEN];
    size_t frame_len = 0;

    /* Header */
    frame_buf[frame_len++] = S3H2_FRAME_HEADER;

    /* Type */
    frame_buf[frame_len++] = type;

    /* Length (little-endian) */
    frame_buf[frame_len++] = len & 0xFF;
    frame_buf[frame_len++] = (len >> 8) & 0xFF;

    /* Payload */
    if (len > 0 && payload != NULL) {
        memcpy(&frame_buf[frame_len], payload, len);
        frame_len += len;
    }

    /* Calculate CRC (over type + length + payload) */
    uint16_t crc = s3h2_crc16(&frame_buf[1], 3 + len);
    frame_buf[frame_len++] = crc & 0xFF;
    frame_buf[frame_len++] = (crc >> 8) & 0xFF;

    /* End marker */
    frame_buf[frame_len++] = S3H2_FRAME_END;

    /* Send with mutex protection */
    xSemaphoreTake(s_tx_mutex, portMAX_DELAY);

    int written = uart_write_bytes(S3_COMM_UART_NUM, frame_buf, frame_len);

    xSemaphoreGive(s_tx_mutex);

    if (written != frame_len) {
        ESP_LOGE(TAG, "UART write failed: %d/%d", written, (int)frame_len);
        s_stats.tx_errors++;
        return ESP_FAIL;
    }

    s_stats.tx_frames++;
    ESP_LOGD(TAG, "Frame sent: type=0x%02X len=%d", type, len);
    return ESP_OK;
}

/*******************************************************************************
 * Response Functions
 ******************************************************************************/

esp_err_t s3_comm_send_pong(void)
{
    return send_frame(S3H2_RSP_PONG, NULL, 0);
}

esp_err_t s3_comm_send_status(const s3h2_status_payload_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_frame(S3H2_RSP_STATUS, status, sizeof(s3h2_status_payload_t));
}

esp_err_t s3_comm_send_credentials(const s3h2_credentials_payload_t *creds)
{
    if (creds == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_frame(S3H2_RSP_CREDENTIALS, creds, sizeof(s3h2_credentials_payload_t));
}

esp_err_t s3_comm_send_version(const s3h2_version_payload_t *version)
{
    if (version == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_frame(S3H2_RSP_VERSION, version, sizeof(s3h2_version_payload_t));
}

esp_err_t s3_comm_send_ack(void)
{
    return send_frame(S3H2_RSP_ACK, NULL, 0);
}

esp_err_t s3_comm_send_nak(s3h2_error_t error_code)
{
    s3h2_nak_payload_t payload = {
        .error_code = error_code,
    };
    return send_frame(S3H2_RSP_NAK, &payload, sizeof(payload));
}

/*******************************************************************************
 * Event Functions
 ******************************************************************************/

esp_err_t s3_comm_send_thread_state_event(s3h2_thread_state_t old_state,
                                          s3h2_thread_state_t new_state)
{
    s3h2_thread_state_payload_t payload = {
        .old_state = old_state,
        .new_state = new_state,
    };
    return send_frame(S3H2_EVT_THREAD_STATE, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_crate_joined(const uint8_t *ext_addr, uint16_t rloc16)
{
    if (ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_crate_joined_payload_t payload = {
        .rloc16 = rloc16,
    };
    memcpy(payload.ext_addr, ext_addr, 8);

    ESP_LOGI(TAG, "Sending CRATE_JOINED event, rloc16=0x%04X", rloc16);
    return send_frame(S3H2_EVT_CRATE_JOINED, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_crate_left(const uint8_t *ext_addr)
{
    if (ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_crate_left_payload_t payload = {0};
    memcpy(payload.ext_addr, ext_addr, 8);

    ESP_LOGI(TAG, "Sending CRATE_LEFT event");
    return send_frame(S3H2_EVT_CRATE_LEFT, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_crate_heartbeat(const uint8_t *ext_addr,
                                        uint8_t battery_percent,
                                        int8_t rssi)
{
    if (ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_crate_heartbeat_payload_t payload = {
        .battery_percent = battery_percent,
        .rssi = rssi,
    };
    memcpy(payload.ext_addr, ext_addr, 8);

    return send_frame(S3H2_EVT_CRATE_HEARTBEAT, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_inventory_update(const uint8_t *ext_addr,
                                         const uint8_t (*epcs)[12],
                                         uint8_t epc_count)
{
    if (ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Calculate payload size */
    size_t payload_size = sizeof(s3h2_inventory_update_payload_t) + (epc_count * 12);
    if (payload_size > S3H2_MAX_PAYLOAD_LEN) {
        ESP_LOGE(TAG, "Inventory too large: %d EPCs", epc_count);
        return ESP_ERR_INVALID_SIZE;
    }

    /* Build payload */
    uint8_t payload_buf[S3H2_MAX_PAYLOAD_LEN];
    s3h2_inventory_update_payload_t *header = (s3h2_inventory_update_payload_t *)payload_buf;
    memcpy(header->ext_addr, ext_addr, 8);
    header->slot_count = epc_count;

    if (epc_count > 0 && epcs != NULL) {
        memcpy(&payload_buf[sizeof(s3h2_inventory_update_payload_t)], epcs, epc_count * 12);
    }

    ESP_LOGI(TAG, "Sending INVENTORY_UPDATE event, %d EPCs", epc_count);
    return send_frame(S3H2_EVT_INVENTORY_UPDATE, payload_buf, payload_size);
}

esp_err_t s3_comm_send_error_event(s3h2_error_t error_code)
{
    s3h2_nak_payload_t payload = {
        .error_code = error_code,
    };
    return send_frame(S3H2_EVT_ERROR, &payload, sizeof(payload));
}

/*******************************************************************************
 * Phase 4: Crate OTA Command Handlers
 ******************************************************************************/

static void handle_ota_start_crate(const uint8_t *payload, uint16_t len)
{
    ESP_LOGI(TAG, "OTA_START_CRATE received");

    if (len < sizeof(s3h2_ota_start_crate_payload_t)) {
        ESP_LOGE(TAG, "Payload too short for OTA_START");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_ota_start_crate_payload_t *cmd = (const s3h2_ota_start_crate_payload_t *)payload;

    ESP_LOGI(TAG, "OTA target: %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             cmd->crate_ext_addr[0], cmd->crate_ext_addr[1],
             cmd->crate_ext_addr[2], cmd->crate_ext_addr[3],
             cmd->crate_ext_addr[4], cmd->crate_ext_addr[5],
             cmd->crate_ext_addr[6], cmd->crate_ext_addr[7]);
    ESP_LOGI(TAG, "FW size: %lu, version: %d.%d.%d",
             (unsigned long)cmd->firmware_size,
             cmd->version_major, cmd->version_minor, cmd->version_patch);

    /* Initialize CoAP OTA session to crate */
    esp_err_t ret = coap_ota_start_session(cmd->crate_ext_addr,
                                            cmd->firmware_size,
                                            cmd->sha256,
                                            cmd->version_major,
                                            cmd->version_minor,
                                            cmd->version_patch);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start CoAP OTA session: %s", esp_err_to_name(ret));
        if (ret == ESP_ERR_INVALID_STATE) {
            s3_comm_send_nak(S3H2_ERR_OTA_IN_PROGRESS);
        } else {
            s3_comm_send_nak(S3H2_ERR_CRATE_UNREACHABLE);
        }
        return;
    }

    s3_comm_send_ack();
}

static void handle_ota_data_crate(const uint8_t *payload, uint16_t len)
{
    if (len < sizeof(s3h2_ota_data_crate_payload_t)) {
        ESP_LOGE(TAG, "Payload too short for OTA_DATA");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_ota_data_crate_payload_t *cmd = (const s3h2_ota_data_crate_payload_t *)payload;
    const uint8_t *data = payload + sizeof(s3h2_ota_data_crate_payload_t);
    uint16_t data_len = len - sizeof(s3h2_ota_data_crate_payload_t);

    if (data_len != cmd->length) {
        ESP_LOGW(TAG, "Data length mismatch: header=%d, actual=%d", cmd->length, data_len);
    }

    ESP_LOGD(TAG, "OTA_DATA: offset=%lu, len=%d",
             (unsigned long)cmd->offset, cmd->length);

    /* Send data chunk to crate via CoAP */
    esp_err_t ret = coap_ota_send_chunk(cmd->crate_ext_addr,
                                         cmd->offset,
                                         data,
                                         data_len);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to send OTA chunk: %s", esp_err_to_name(ret));
        if (ret == ESP_ERR_INVALID_STATE) {
            s3_comm_send_nak(S3H2_ERR_OTA_NO_SESSION);
        } else if (ret == ESP_ERR_TIMEOUT) {
            s3_comm_send_nak(S3H2_ERR_CRATE_UNREACHABLE);
        } else {
            s3_comm_send_nak(S3H2_ERR_INTERNAL);
        }
        return;
    }

    /* ACK receipt (progress event sent asynchronously by coap_ota) */
    s3_comm_send_ack();
}

static void handle_ota_verify_crate(const uint8_t *payload, uint16_t len)
{
    ESP_LOGI(TAG, "OTA_VERIFY_CRATE received");

    if (len < sizeof(s3h2_ota_verify_crate_payload_t)) {
        ESP_LOGE(TAG, "Payload too short for OTA_VERIFY");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_ota_verify_crate_payload_t *cmd = (const s3h2_ota_verify_crate_payload_t *)payload;

    ESP_LOGI(TAG, "Verifying OTA for crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             cmd->crate_ext_addr[0], cmd->crate_ext_addr[1],
             cmd->crate_ext_addr[2], cmd->crate_ext_addr[3],
             cmd->crate_ext_addr[4], cmd->crate_ext_addr[5],
             cmd->crate_ext_addr[6], cmd->crate_ext_addr[7]);

    /* Send verify command to crate via CoAP */
    esp_err_t ret = coap_ota_verify(cmd->crate_ext_addr);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to verify OTA: %s", esp_err_to_name(ret));
        if (ret == ESP_ERR_INVALID_STATE) {
            s3_comm_send_nak(S3H2_ERR_OTA_NO_SESSION);
        } else if (ret == ESP_ERR_TIMEOUT) {
            s3_comm_send_nak(S3H2_ERR_CRATE_UNREACHABLE);
        } else {
            s3_comm_send_nak(S3H2_ERR_OTA_CHECKSUM);
        }
        return;
    }

    s3_comm_send_ack();
}

static void handle_ota_abort_crate(const uint8_t *payload, uint16_t len)
{
    ESP_LOGW(TAG, "OTA_ABORT_CRATE received");

    if (len < sizeof(s3h2_ota_abort_crate_payload_t)) {
        ESP_LOGE(TAG, "Payload too short for OTA_ABORT");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_ota_abort_crate_payload_t *cmd = (const s3h2_ota_abort_crate_payload_t *)payload;

    ESP_LOGI(TAG, "Aborting OTA for crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             cmd->crate_ext_addr[0], cmd->crate_ext_addr[1],
             cmd->crate_ext_addr[2], cmd->crate_ext_addr[3],
             cmd->crate_ext_addr[4], cmd->crate_ext_addr[5],
             cmd->crate_ext_addr[6], cmd->crate_ext_addr[7]);

    /* Abort CoAP OTA session */
    esp_err_t ret = coap_ota_abort(cmd->crate_ext_addr);
    if (ret != ESP_OK && ret != ESP_ERR_NOT_FOUND) {
        ESP_LOGW(TAG, "Abort returned: %s", esp_err_to_name(ret));
    }

    s3_comm_send_ack();
}

static void handle_ping_crate(const uint8_t *payload, uint16_t len)
{
    ESP_LOGI(TAG, "PING_CRATE received");

    if (len < sizeof(s3h2_ping_crate_payload_t)) {
        ESP_LOGE(TAG, "Payload too short for PING_CRATE");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_ping_crate_payload_t *cmd = (const s3h2_ping_crate_payload_t *)payload;

    ESP_LOGI(TAG, "Pinging crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             cmd->crate_ext_addr[0], cmd->crate_ext_addr[1],
             cmd->crate_ext_addr[2], cmd->crate_ext_addr[3],
             cmd->crate_ext_addr[4], cmd->crate_ext_addr[5],
             cmd->crate_ext_addr[6], cmd->crate_ext_addr[7]);

    /* Send CoAP ping to crate (synchronous) */
    int8_t rssi = 0;
    esp_err_t ret = coap_ota_ping_device(cmd->crate_ext_addr, 5000, &rssi);

    /* Report result back to S3 */
    if (ret == ESP_OK) {
        s3_comm_send_ping_result(cmd->crate_ext_addr, true, rssi);
    } else {
        s3_comm_send_ping_result(cmd->crate_ext_addr, false, 0);
    }
}

/*******************************************************************************
 * CoAP Mesh Protocol Command Handler
 ******************************************************************************/

static void handle_relay_cmd(const uint8_t *payload, uint16_t len)
{
    ESP_LOGI(TAG, "RELAY_CMD received");

    if (len < sizeof(s3h2_relay_cmd_header_t)) {
        ESP_LOGE(TAG, "Payload too short for RELAY_CMD");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    const s3h2_relay_cmd_header_t *cmd = (const s3h2_relay_cmd_header_t *)payload;
    const uint8_t *cbor_data = payload + sizeof(s3h2_relay_cmd_header_t);
    uint16_t cbor_len = cmd->cbor_len;

    /* Validate payload length */
    if (sizeof(s3h2_relay_cmd_header_t) + cbor_len > len) {
        ESP_LOGE(TAG, "RELAY_CMD: CBOR length mismatch");
        s3_comm_send_nak(S3H2_ERR_INVALID_PARAM);
        return;
    }

    ESP_LOGI(TAG, "Relaying command to crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X, cbor_len=%d",
             cmd->target_ext_addr[0], cmd->target_ext_addr[1],
             cmd->target_ext_addr[2], cmd->target_ext_addr[3],
             cmd->target_ext_addr[4], cmd->target_ext_addr[5],
             cmd->target_ext_addr[6], cmd->target_ext_addr[7],
             cbor_len);

    /* Forward via CoAP POST /cmd */
    esp_err_t ret = coap_cmd_client_send(cmd->target_ext_addr, cbor_data, cbor_len);
    if (ret == ESP_OK) {
        s3_comm_send_ack();
    } else if (ret == ESP_ERR_TIMEOUT) {
        ESP_LOGW(TAG, "Crate not reachable for command relay");
        s3_comm_send_nak(S3H2_ERR_CRATE_UNREACHABLE);
    } else {
        ESP_LOGE(TAG, "Command relay failed: %s", esp_err_to_name(ret));
        s3_comm_send_nak(S3H2_ERR_INTERNAL);
    }
}

/*******************************************************************************
 * Phase 4: OTA Event Functions
 ******************************************************************************/

esp_err_t s3_comm_send_ota_progress(const uint8_t *crate_ext_addr,
                                    uint8_t percent,
                                    uint32_t bytes_sent,
                                    uint32_t total_bytes)
{
    if (crate_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_ota_progress_payload_t payload = {
        .percent = percent,
        .bytes_sent = bytes_sent,
        .total_bytes = total_bytes,
    };
    memcpy(payload.crate_ext_addr, crate_ext_addr, 8);

    ESP_LOGI(TAG, "Sending OTA_PROGRESS: %d%% (%lu/%lu)",
             percent, (unsigned long)bytes_sent, (unsigned long)total_bytes);

    return send_frame(S3H2_EVT_OTA_PROGRESS, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_ota_complete(const uint8_t *crate_ext_addr,
                                    bool success,
                                    s3h2_error_t error_code)
{
    if (crate_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_ota_complete_payload_t payload = {
        .success = success ? 1 : 0,
        .error_code = error_code,
    };
    memcpy(payload.crate_ext_addr, crate_ext_addr, 8);

    ESP_LOGI(TAG, "Sending OTA_COMPLETE: success=%d, error=%d", success, error_code);

    return send_frame(S3H2_EVT_OTA_COMPLETE, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_ping_result(const uint8_t *crate_ext_addr,
                                   bool reachable,
                                   int8_t rssi)
{
    if (crate_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_ping_result_payload_t payload = {
        .reachable = reachable ? 1 : 0,
        .rssi = rssi,
    };
    memcpy(payload.crate_ext_addr, crate_ext_addr, 8);

    ESP_LOGI(TAG, "Sending PING_RESULT: reachable=%d, rssi=%d", reachable, rssi);

    return send_frame(S3H2_EVT_CRATE_PING_RESULT, &payload, sizeof(payload));
}

esp_err_t s3_comm_send_mesh_cmd_result(const uint8_t *ext_addr, uint8_t result, const char *cmd)
{
    if (ext_addr == NULL || cmd == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    s3h2_mesh_cmd_result_payload_t payload = {
        .result = result,
    };
    memcpy(payload.ext_addr, ext_addr, 8);
    strncpy(payload.cmd, cmd, sizeof(payload.cmd) - 1);
    payload.cmd[sizeof(payload.cmd) - 1] = '\0';

    ESP_LOGI(TAG, "Sending MESH_CMD_RESULT: %02X%02X%02X%02X%02X%02X%02X%02X cmd=\"%s\" result=%d",
             ext_addr[0], ext_addr[1], ext_addr[2], ext_addr[3],
             ext_addr[4], ext_addr[5], ext_addr[6], ext_addr[7], payload.cmd, result);

    return send_frame(S3H2_EVT_MESH_CMD_RESULT, &payload, sizeof(payload));
}

/*******************************************************************************
 * CoAP Mesh Protocol Event Functions
 ******************************************************************************/

esp_err_t s3_comm_send_crate_telemetry(const uint8_t *ext_addr,
                                        uint8_t hb_type,
                                        const uint8_t *cbor_data,
                                        uint16_t cbor_len)
{
    if (ext_addr == NULL || cbor_data == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Build variable-length payload: header + CBOR data */
    size_t header_size = sizeof(s3h2_crate_telemetry_header_t);
    size_t total_len = header_size + cbor_len;
    if (total_len > S3H2_MAX_PAYLOAD_LEN) {
        ESP_LOGE(TAG, "Telemetry too large: %d bytes", (int)total_len);
        return ESP_ERR_INVALID_SIZE;
    }

    uint8_t payload_buf[S3H2_MAX_PAYLOAD_LEN];
    s3h2_crate_telemetry_header_t *header = (s3h2_crate_telemetry_header_t *)payload_buf;
    memcpy(header->ext_addr, ext_addr, 8);
    header->hb_type = hb_type;
    header->cbor_len = cbor_len;
    memcpy(&payload_buf[header_size], cbor_data, cbor_len);

    ESP_LOGI(TAG, "Sending CRATE_TELEMETRY: type=%d, cbor_len=%d", hb_type, cbor_len);
    return send_frame(S3H2_EVT_CRATE_TELEMETRY, payload_buf, total_len);
}

esp_err_t s3_comm_send_crate_registered(const uint8_t *ext_addr,
                                         const char *mac,
                                         const char *unit_id,
                                         const char *device_type,
                                         const char *fw_version)
{
    if (ext_addr == NULL || mac == NULL || unit_id == NULL ||
        device_type == NULL || fw_version == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Build variable-length payload:
     * ext_addr[8] + len-prefixed strings: mac, unit_id, device_type, fw_version */
    uint8_t payload_buf[256];
    size_t pos = 0;

    /* ext_addr */
    memcpy(&payload_buf[pos], ext_addr, 8);
    pos += 8;

    /* Length-prefixed strings */
    const char *strings[] = { mac, unit_id, device_type, fw_version };
    for (int i = 0; i < 4; i++) {
        uint8_t slen = (uint8_t)strlen(strings[i]);
        if (pos + 1 + slen > sizeof(payload_buf)) {
            ESP_LOGE(TAG, "Registration payload too large");
            return ESP_ERR_INVALID_SIZE;
        }
        payload_buf[pos++] = slen;
        memcpy(&payload_buf[pos], strings[i], slen);
        pos += slen;
    }

    ESP_LOGI(TAG, "Sending CRATE_REGISTERED: mac=%s, unit=%s", mac, unit_id);
    return send_frame(S3H2_EVT_CRATE_REGISTERED, payload_buf, pos);
}

/*******************************************************************************
 * Statistics
 ******************************************************************************/

esp_err_t s3_comm_get_stats(s3_comm_stats_t *stats)
{
    if (stats == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(stats, &s_stats, sizeof(s_stats));
    return ESP_OK;
}
