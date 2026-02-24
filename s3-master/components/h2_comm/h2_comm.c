/**
 * @file h2_comm.c
 * @brief H2 Communication Implementation for ESP32-S3 Master
 *
 * Implements UART-based communication protocol between S3 (master) and H2 (slave).
 * Handles command transmission, response reception, and async event processing.
 *
 * Phase S3-7 and INT-1: S3↔H2 Integration
 */

#include "h2_comm.h"
#include "driver/uart.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"
#include <string.h>

static const char *TAG = "H2_COMM";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(H2_COMM_EVENTS);

/*******************************************************************************
 * Constants
 ******************************************************************************/

/* Event bits for command/response synchronization */
#define EVT_RESPONSE_RECEIVED   BIT0
#define EVT_NAK_RECEIVED        BIT1
#define EVT_TIMEOUT             BIT2

/*******************************************************************************
 * Module State
 ******************************************************************************/

static bool s_initialized = false;
static bool s_h2_connected = false;
static TaskHandle_t s_rx_task_handle = NULL;
static TaskHandle_t s_health_task_handle = NULL;
static SemaphoreHandle_t s_tx_mutex = NULL;
static SemaphoreHandle_t s_cmd_mutex = NULL;  /* Only one command at a time */
static EventGroupHandle_t s_response_events = NULL;

/* Pending response storage */
static uint8_t s_pending_rsp_type = 0;
static s3h2_frame_t s_pending_response;
static s3h2_error_t s_last_nak_error = S3H2_ERR_NONE;

/* Statistics */
static h2_comm_stats_t s_stats = {0};

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
static void health_monitor_task(void *arg);
static void process_byte(uint8_t byte);
static void process_frame(void);
static void handle_response(uint8_t rsp_type, const uint8_t *payload, uint16_t len);
static void handle_event(uint8_t evt_type, const uint8_t *payload, uint16_t len);
static esp_err_t send_frame(uint8_t type, const void *payload, uint16_t len);
static esp_err_t send_command_wait_response(uint8_t cmd_type, const void *payload,
                                             uint16_t payload_len, uint8_t expected_rsp,
                                             void *response_out, uint16_t response_size,
                                             uint32_t timeout_ms);

/*******************************************************************************
 * GPIO Control
 ******************************************************************************/

static esp_err_t gpio_init_h2_control(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << H2_COMM_EN_PIN) | (1ULL << H2_COMM_BOOT_PIN),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    esp_err_t ret = gpio_config(&io_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure H2 control GPIOs: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Set default states: H2 enabled, normal boot mode */
    gpio_set_level(H2_COMM_EN_PIN, 1);   /* H2 enabled */
    gpio_set_level(H2_COMM_BOOT_PIN, 1); /* Normal boot mode */

    return ESP_OK;
}

static void h2_hw_reset(bool enter_bootloader)
{
    ESP_LOGI(TAG, "Resetting H2 (bootloader=%d)", enter_bootloader);

    /* Set boot mode pin before reset */
    gpio_set_level(H2_COMM_BOOT_PIN, enter_bootloader ? 0 : 1);

    /* Toggle EN pin: disable -> delay -> enable */
    gpio_set_level(H2_COMM_EN_PIN, 0);
    vTaskDelay(pdMS_TO_TICKS(100));
    gpio_set_level(H2_COMM_EN_PIN, 1);

    /* Wait for H2 to boot */
    vTaskDelay(pdMS_TO_TICKS(H2_COMM_BOOT_DELAY_MS));
}

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t h2_comm_init(void)
{
    if (s_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing H2 communication...");

    /* Initialize GPIO for H2 control */
    esp_err_t ret = gpio_init_h2_control();
    if (ret != ESP_OK) {
        return ret;
    }

    /* Create synchronization primitives */
    s_tx_mutex = xSemaphoreCreateMutex();
    s_cmd_mutex = xSemaphoreCreateMutex();
    s_response_events = xEventGroupCreate();

    if (s_tx_mutex == NULL || s_cmd_mutex == NULL || s_response_events == NULL) {
        ESP_LOGE(TAG, "Failed to create synchronization primitives");
        if (s_tx_mutex) vSemaphoreDelete(s_tx_mutex);
        if (s_cmd_mutex) vSemaphoreDelete(s_cmd_mutex);
        if (s_response_events) vEventGroupDelete(s_response_events);
        return ESP_ERR_NO_MEM;
    }

    /* Configure UART */
    uart_config_t uart_config = {
        .baud_rate = H2_COMM_UART_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    ret = uart_driver_install(H2_COMM_UART_NUM,
                               H2_COMM_RX_BUF_SIZE,
                               H2_COMM_TX_BUF_SIZE,
                               0, NULL, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to install UART driver: %s", esp_err_to_name(ret));
        goto cleanup;
    }

    ret = uart_param_config(H2_COMM_UART_NUM, &uart_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure UART: %s", esp_err_to_name(ret));
        uart_driver_delete(H2_COMM_UART_NUM);
        goto cleanup;
    }

    ret = uart_set_pin(H2_COMM_UART_NUM,
                        H2_COMM_UART_TX_PIN,
                        H2_COMM_UART_RX_PIN,
                        UART_PIN_NO_CHANGE,
                        UART_PIN_NO_CHANGE);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set UART pins: %s", esp_err_to_name(ret));
        uart_driver_delete(H2_COMM_UART_NUM);
        goto cleanup;
    }

    /* Reset parser state and statistics */
    s_parse_state = PARSE_STATE_HEADER;
    memset(&s_rx_frame, 0, sizeof(s_rx_frame));
    memset(&s_stats, 0, sizeof(s_stats));

    /* Create RX task */
    BaseType_t xret = xTaskCreate(rx_task, "h2_comm_rx",
                                   H2_COMM_TASK_STACK_SIZE,
                                   NULL,
                                   H2_COMM_TASK_PRIORITY,
                                   &s_rx_task_handle);
    if (xret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create RX task");
        uart_driver_delete(H2_COMM_UART_NUM);
        goto cleanup;
    }

    s_initialized = true;
    ESP_LOGI(TAG, "H2 communication initialized (UART%d, %d baud, TX=%d, RX=%d)",
             H2_COMM_UART_NUM, H2_COMM_UART_BAUD,
             H2_COMM_UART_TX_PIN, H2_COMM_UART_RX_PIN);
    return ESP_OK;

cleanup:
    if (s_tx_mutex) {
        vSemaphoreDelete(s_tx_mutex);
        s_tx_mutex = NULL;
    }
    if (s_cmd_mutex) {
        vSemaphoreDelete(s_cmd_mutex);
        s_cmd_mutex = NULL;
    }
    if (s_response_events) {
        vEventGroupDelete(s_response_events);
        s_response_events = NULL;
    }
    return ret;
}

esp_err_t h2_comm_deinit(void)
{
    if (!s_initialized) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Deinitializing H2 communication...");

    /* Stop health monitor */
    h2_comm_stop_health_monitor();

    /* Stop RX task */
    if (s_rx_task_handle != NULL) {
        vTaskDelete(s_rx_task_handle);
        s_rx_task_handle = NULL;
    }

    /* Uninstall UART driver */
    uart_driver_delete(H2_COMM_UART_NUM);

    /* Delete synchronization primitives */
    if (s_tx_mutex) {
        vSemaphoreDelete(s_tx_mutex);
        s_tx_mutex = NULL;
    }
    if (s_cmd_mutex) {
        vSemaphoreDelete(s_cmd_mutex);
        s_cmd_mutex = NULL;
    }
    if (s_response_events) {
        vEventGroupDelete(s_response_events);
        s_response_events = NULL;
    }

    s_initialized = false;
    s_h2_connected = false;
    ESP_LOGI(TAG, "H2 communication deinitialized");
    return ESP_OK;
}

bool h2_comm_is_initialized(void)
{
    return s_initialized;
}

bool h2_comm_is_connected(void)
{
    return s_h2_connected;
}

/*******************************************************************************
 * H2 Control Functions
 ******************************************************************************/

esp_err_t h2_comm_reset(void)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Resetting H2...");
    s_stats.h2_resets++;

    /* Flush UART buffers */
    uart_flush(H2_COMM_UART_NUM);

    /* Reset parser state */
    s_parse_state = PARSE_STATE_HEADER;

    /* Hardware reset */
    h2_hw_reset(false);

    /* Mark as disconnected until PING succeeds */
    s_h2_connected = false;

    /* Post reset event */
    esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_H2_RESET, NULL, 0,
                   pdMS_TO_TICKS(100));

    return ESP_OK;
}

esp_err_t h2_comm_enter_bootloader(void)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Entering H2 bootloader mode...");

    /* Send ENTER_BOOTLOADER command first (H2 will set its own GPIO) */
    esp_err_t ret = send_command_wait_response(S3H2_CMD_ENTER_BOOTLOADER,
                                                NULL, 0,
                                                S3H2_RSP_ACK, NULL, 0,
                                                H2_COMM_CMD_TIMEOUT_MS);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "ENTER_BOOTLOADER command failed, forcing hardware reset");
    }

    /* Also do hardware bootloader entry */
    h2_hw_reset(true);

    s_h2_connected = false;
    return ESP_OK;
}

esp_err_t h2_comm_exit_bootloader(void)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Exiting H2 bootloader mode...");

    /* Reset to normal mode */
    h2_hw_reset(false);

    return ESP_OK;
}

/*******************************************************************************
 * RX Task and Frame Parser
 ******************************************************************************/

static void rx_task(void *arg)
{
    uint8_t rx_buf[128];

    ESP_LOGI(TAG, "RX task started");

    while (1) {
        int len = uart_read_bytes(H2_COMM_UART_NUM, rx_buf, sizeof(rx_buf),
                                  pdMS_TO_TICKS(H2_COMM_RX_TIMEOUT_MS));
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
    uint8_t msg_type = s_rx_frame.type;

    ESP_LOGD(TAG, "Frame received: type=0x%02X len=%d", msg_type, s_rx_frame.length);

    /* Determine if this is a response or an event */
    if (msg_type >= 0x80 && msg_type < 0xE0) {
        /* Response (0x80-0xDF) */
        handle_response(msg_type, s_rx_frame.payload, s_rx_frame.length);
    } else if (msg_type >= 0xE0) {
        /* Event (0xE0-0xFF) */
        handle_event(msg_type, s_rx_frame.payload, s_rx_frame.length);
    } else {
        ESP_LOGW(TAG, "Unexpected message type from H2: 0x%02X", msg_type);
    }
}

/*******************************************************************************
 * Response Handler
 ******************************************************************************/

static void handle_response(uint8_t rsp_type, const uint8_t *payload, uint16_t len)
{
    ESP_LOGD(TAG, "Response: type=0x%02X len=%d", rsp_type, len);

    /* Check if this is the response we're waiting for */
    if (s_pending_rsp_type == 0) {
        ESP_LOGW(TAG, "Unexpected response (not waiting): 0x%02X", rsp_type);
        return;
    }

    if (rsp_type == S3H2_RSP_NAK) {
        /* NAK received */
        if (len >= sizeof(s3h2_nak_payload_t)) {
            const s3h2_nak_payload_t *nak = (const s3h2_nak_payload_t *)payload;
            s_last_nak_error = (s3h2_error_t)nak->error_code;
            ESP_LOGW(TAG, "NAK received: error=%d", s_last_nak_error);
        } else {
            s_last_nak_error = S3H2_ERR_INTERNAL;
        }
        xEventGroupSetBits(s_response_events, EVT_NAK_RECEIVED);
    } else if (rsp_type == s_pending_rsp_type) {
        /* Expected response */
        memcpy(&s_pending_response.type, &rsp_type, sizeof(rsp_type));
        s_pending_response.length = len;
        if (len > 0 && len <= S3H2_MAX_PAYLOAD_LEN) {
            memcpy(s_pending_response.payload, payload, len);
        }
        xEventGroupSetBits(s_response_events, EVT_RESPONSE_RECEIVED);
    } else {
        ESP_LOGW(TAG, "Response type mismatch: expected=0x%02X got=0x%02X",
                 s_pending_rsp_type, rsp_type);
    }
}

/*******************************************************************************
 * Event Handler
 ******************************************************************************/

static void handle_event(uint8_t evt_type, const uint8_t *payload, uint16_t len)
{
    s_stats.events_received++;

    switch (evt_type) {
        case S3H2_EVT_THREAD_STATE: {
            if (len >= sizeof(s3h2_thread_state_payload_t)) {
                const s3h2_thread_state_payload_t *p =
                    (const s3h2_thread_state_payload_t *)payload;
                ESP_LOGI(TAG, "Thread state: %s -> %s",
                         h2_comm_thread_state_str((s3h2_thread_state_t)p->old_state),
                         h2_comm_thread_state_str((s3h2_thread_state_t)p->new_state));
                s_stats.thread_state = (s3h2_thread_state_t)p->new_state;

                h2_comm_thread_state_event_t event = {
                    .old_state = (s3h2_thread_state_t)p->old_state,
                    .new_state = (s3h2_thread_state_t)p->new_state,
                };
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_THREAD_STATE_CHANGED,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_CRATE_JOINED: {
            if (len >= sizeof(s3h2_crate_joined_payload_t)) {
                const s3h2_crate_joined_payload_t *p =
                    (const s3h2_crate_joined_payload_t *)payload;
                ESP_LOGI(TAG, "Crate joined: rloc16=0x%04X", p->rloc16);

                h2_comm_crate_joined_event_t event = {
                    .rloc16 = p->rloc16,
                };
                memcpy(event.ext_addr, p->ext_addr, 8);
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CRATE_JOINED,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_CRATE_LEFT: {
            if (len >= sizeof(s3h2_crate_left_payload_t)) {
                const s3h2_crate_left_payload_t *p =
                    (const s3h2_crate_left_payload_t *)payload;
                ESP_LOGI(TAG, "Crate left");

                h2_comm_crate_left_event_t event;
                memcpy(event.ext_addr, p->ext_addr, 8);
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CRATE_LEFT,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_CRATE_HEARTBEAT: {
            if (len >= sizeof(s3h2_crate_heartbeat_payload_t)) {
                const s3h2_crate_heartbeat_payload_t *p =
                    (const s3h2_crate_heartbeat_payload_t *)payload;
                ESP_LOGD(TAG, "Crate heartbeat: batt=%d%%, rssi=%ddBm",
                         p->battery_percent, p->rssi);

                h2_comm_crate_heartbeat_event_t event = {
                    .battery_percent = p->battery_percent,
                    .rssi = p->rssi,
                };
                memcpy(event.ext_addr, p->ext_addr, 8);
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CRATE_HEARTBEAT,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_INVENTORY_UPDATE: {
            if (len >= sizeof(s3h2_inventory_update_payload_t)) {
                const s3h2_inventory_update_payload_t *p =
                    (const s3h2_inventory_update_payload_t *)payload;
                ESP_LOGI(TAG, "Inventory update: %d EPCs", p->slot_count);

                /* Allocate event with EPCs */
                h2_comm_inventory_event_t event = {0};
                memcpy(event.ext_addr, p->ext_addr, 8);
                event.epc_count = p->slot_count;

                /* Copy EPCs (they follow the header) */
                if (p->slot_count > 0 && p->slot_count <= 75) {
                    size_t epc_data_len = p->slot_count * 12;
                    size_t available = len - sizeof(s3h2_inventory_update_payload_t);
                    if (available >= epc_data_len) {
                        memcpy(event.epcs, payload + sizeof(s3h2_inventory_update_payload_t),
                               epc_data_len);
                    }
                }

                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_INVENTORY_UPDATE,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_CRATE_TELEMETRY: {
            if (len >= sizeof(s3h2_crate_telemetry_header_t)) {
                const s3h2_crate_telemetry_header_t *p =
                    (const s3h2_crate_telemetry_header_t *)payload;
                uint16_t cbor_len = p->cbor_len;
                size_t expected = sizeof(s3h2_crate_telemetry_header_t) + cbor_len;

                if (len >= expected && cbor_len <= 512) {
                    ESP_LOGI(TAG, "Crate telemetry: type=%d, cbor_len=%d",
                             p->hb_type, cbor_len);

                    h2_comm_crate_telemetry_event_t event = {
                        .hb_type = p->hb_type,
                        .cbor_len = cbor_len,
                    };
                    memcpy(event.ext_addr, p->ext_addr, 8);
                    memcpy(event.cbor_data,
                           payload + sizeof(s3h2_crate_telemetry_header_t),
                           cbor_len);
                    esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CRATE_TELEMETRY,
                                   &event, sizeof(event), pdMS_TO_TICKS(100));
                } else {
                    ESP_LOGW(TAG, "Telemetry payload truncated or too large");
                }
            }
            break;
        }

        case S3H2_EVT_CRATE_REGISTERED: {
            if (len >= sizeof(s3h2_crate_registered_header_t)) {
                const uint8_t *p = payload;
                h2_comm_crate_registered_event_t event = {0};
                memcpy(event.ext_addr, p, 8);
                size_t pos = 8;

                /* Parse length-prefixed strings: mac, unit_id, device_type, fw_version */
                char *dests[] = { event.mac, event.unit_id, event.device_type, event.fw_version };
                size_t max_lens[] = { sizeof(event.mac) - 1, sizeof(event.unit_id) - 1,
                                      sizeof(event.device_type) - 1, sizeof(event.fw_version) - 1 };
                bool parse_ok = true;

                for (int i = 0; i < 4 && parse_ok; i++) {
                    if (pos >= len) { parse_ok = false; break; }
                    uint8_t slen = p[pos++];
                    if (pos + slen > len || slen > max_lens[i]) { parse_ok = false; break; }
                    memcpy(dests[i], &p[pos], slen);
                    dests[i][slen] = '\0';
                    pos += slen;
                }

                if (parse_ok) {
                    ESP_LOGI(TAG, "Crate registered: mac=%s, type=%s",
                             event.mac, event.device_type);
                    esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CRATE_REGISTERED,
                                   &event, sizeof(event), pdMS_TO_TICKS(100));
                } else {
                    ESP_LOGW(TAG, "Failed to parse CRATE_REGISTERED payload");
                }
            }
            break;
        }

        case S3H2_EVT_MESH_CMD_RESULT: {
            if (len >= sizeof(s3h2_mesh_cmd_result_payload_t)) {
                const s3h2_mesh_cmd_result_payload_t *p =
                    (const s3h2_mesh_cmd_result_payload_t *)payload;
                static const char *result_str[] = {"acknowledged", "timeout", "error"};
                const char *rstr = (p->result <= 2) ? result_str[p->result] : "unknown";
                /* Ensure cmd is null-terminated for logging */
                char cmd_safe[17];
                memcpy(cmd_safe, p->cmd, 16);
                cmd_safe[16] = '\0';
                if (p->result == S3H2_CMD_RESULT_OK) {
                    ESP_LOGI(TAG, "Mesh cmd %02X%02X%02X%02X%02X%02X%02X%02X \"%s\": %s",
                             p->ext_addr[0], p->ext_addr[1], p->ext_addr[2], p->ext_addr[3],
                             p->ext_addr[4], p->ext_addr[5], p->ext_addr[6], p->ext_addr[7],
                             cmd_safe, rstr);
                } else {
                    ESP_LOGW(TAG, "Mesh cmd %02X%02X%02X%02X%02X%02X%02X%02X \"%s\": %s",
                             p->ext_addr[0], p->ext_addr[1], p->ext_addr[2], p->ext_addr[3],
                             p->ext_addr[4], p->ext_addr[5], p->ext_addr[6], p->ext_addr[7],
                             cmd_safe, rstr);
                }
                h2_comm_mesh_cmd_result_event_t event = {
                    .result = p->result,
                };
                memcpy(event.ext_addr, p->ext_addr, 8);
                memcpy(event.cmd, p->cmd, 16);
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_MESH_CMD_RESULT,
                               &event, sizeof(event), pdMS_TO_TICKS(100));
            }
            break;
        }

        case S3H2_EVT_ERROR: {
            if (len >= sizeof(s3h2_nak_payload_t)) {
                const s3h2_nak_payload_t *p = (const s3h2_nak_payload_t *)payload;
                ESP_LOGE(TAG, "H2 error event: code=%d", p->error_code);
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_ERROR,
                               &p->error_code, sizeof(p->error_code),
                               pdMS_TO_TICKS(100));
            }
            break;
        }

        default:
            ESP_LOGW(TAG, "Unknown event type: 0x%02X", evt_type);
            break;
    }
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

    int written = uart_write_bytes(H2_COMM_UART_NUM, frame_buf, frame_len);

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
 * Command/Response Functions
 ******************************************************************************/

static esp_err_t send_command_wait_response(uint8_t cmd_type, const void *payload,
                                             uint16_t payload_len, uint8_t expected_rsp,
                                             void *response_out, uint16_t response_size,
                                             uint32_t timeout_ms)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (timeout_ms == 0) {
        timeout_ms = H2_COMM_CMD_TIMEOUT_MS;
    }

    /* Only one command at a time */
    if (xSemaphoreTake(s_cmd_mutex, pdMS_TO_TICKS(timeout_ms)) != pdTRUE) {
        ESP_LOGW(TAG, "Command mutex timeout");
        return ESP_ERR_TIMEOUT;
    }

    /* Clear pending response state */
    xEventGroupClearBits(s_response_events, EVT_RESPONSE_RECEIVED | EVT_NAK_RECEIVED);
    s_pending_rsp_type = expected_rsp;
    s_last_nak_error = S3H2_ERR_NONE;

    /* Send command */
    esp_err_t ret = send_frame(cmd_type, payload, payload_len);
    if (ret != ESP_OK) {
        s_pending_rsp_type = 0;
        xSemaphoreGive(s_cmd_mutex);
        return ret;
    }

    /* Wait for response */
    EventBits_t bits = xEventGroupWaitBits(s_response_events,
                                            EVT_RESPONSE_RECEIVED | EVT_NAK_RECEIVED,
                                            pdTRUE, pdFALSE,
                                            pdMS_TO_TICKS(timeout_ms));

    s_pending_rsp_type = 0;

    if (bits & EVT_RESPONSE_RECEIVED) {
        /* Success - copy response if requested */
        if (response_out != NULL && response_size > 0) {
            uint16_t copy_len = s_pending_response.length;
            if (copy_len > response_size) {
                copy_len = response_size;
            }
            memcpy(response_out, s_pending_response.payload, copy_len);
        }
        ret = ESP_OK;
    } else if (bits & EVT_NAK_RECEIVED) {
        ESP_LOGW(TAG, "Command 0x%02X NAK'd: error=%d", cmd_type, s_last_nak_error);
        ret = ESP_FAIL;
    } else {
        /* Timeout */
        ESP_LOGW(TAG, "Command 0x%02X timeout", cmd_type);
        s_stats.timeouts++;
        ret = ESP_ERR_TIMEOUT;
    }

    xSemaphoreGive(s_cmd_mutex);
    return ret;
}

/*******************************************************************************
 * Public Command Functions
 ******************************************************************************/

esp_err_t h2_comm_ping(uint32_t timeout_ms)
{
    esp_err_t ret = send_command_wait_response(S3H2_CMD_PING, NULL, 0,
                                                S3H2_RSP_PONG, NULL, 0,
                                                timeout_ms);
    if (ret == ESP_OK) {
        if (!s_h2_connected) {
            s_h2_connected = true;
            s_stats.ping_failures = 0;
            s_stats.last_ping_time_ms = esp_timer_get_time() / 1000;
            esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_CONNECTED, NULL, 0,
                           pdMS_TO_TICKS(100));
            ESP_LOGI(TAG, "H2 connected");
        }
        s_stats.last_ping_time_ms = esp_timer_get_time() / 1000;
    } else {
        s_stats.ping_failures++;
    }
    return ret;
}

esp_err_t h2_comm_get_status(s3h2_status_payload_t *status, uint32_t timeout_ms)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_command_wait_response(S3H2_CMD_GET_STATUS, NULL, 0,
                                       S3H2_RSP_STATUS, status,
                                       sizeof(s3h2_status_payload_t),
                                       timeout_ms);
}

esp_err_t h2_comm_get_credentials(s3h2_credentials_payload_t *creds, uint32_t timeout_ms)
{
    if (creds == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_command_wait_response(S3H2_CMD_GET_CREDENTIALS, NULL, 0,
                                       S3H2_RSP_CREDENTIALS, creds,
                                       sizeof(s3h2_credentials_payload_t),
                                       timeout_ms);
}

esp_err_t h2_comm_get_version(s3h2_version_payload_t *version, uint32_t timeout_ms)
{
    if (version == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    return send_command_wait_response(S3H2_CMD_GET_VERSION, NULL, 0,
                                       S3H2_RSP_VERSION, version,
                                       sizeof(s3h2_version_payload_t),
                                       timeout_ms);
}

esp_err_t h2_comm_start_thread(uint32_t timeout_ms)
{
    return send_command_wait_response(S3H2_CMD_START_THREAD, NULL, 0,
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

esp_err_t h2_comm_stop_thread(uint32_t timeout_ms)
{
    return send_command_wait_response(S3H2_CMD_STOP_THREAD, NULL, 0,
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

esp_err_t h2_comm_enable_joining(uint32_t duration_sec, uint32_t timeout_ms)
{
    s3h2_enable_joining_payload_t payload = {
        .duration_sec = duration_sec,
    };
    return send_command_wait_response(S3H2_CMD_ENABLE_JOINING,
                                       &payload, sizeof(payload),
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

esp_err_t h2_comm_disable_joining(uint32_t timeout_ms)
{
    return send_command_wait_response(S3H2_CMD_DISABLE_JOINING, NULL, 0,
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

esp_err_t h2_comm_reset_credentials(uint32_t timeout_ms)
{
    return send_command_wait_response(S3H2_CMD_RESET_CREDENTIALS, NULL, 0,
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

esp_err_t h2_comm_relay_command(const uint8_t *target_ext_addr,
                                 const uint8_t *cbor_data,
                                 uint16_t cbor_len,
                                 uint32_t timeout_ms)
{
    if (target_ext_addr == NULL || cbor_data == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Build variable-length payload: header + CBOR data */
    size_t header_size = sizeof(s3h2_relay_cmd_header_t);
    size_t total_len = header_size + cbor_len;
    if (total_len > S3H2_MAX_PAYLOAD_LEN) {
        ESP_LOGE(TAG, "Relay command too large: %d bytes", (int)total_len);
        return ESP_ERR_INVALID_SIZE;
    }

    uint8_t payload_buf[S3H2_MAX_PAYLOAD_LEN];
    s3h2_relay_cmd_header_t *header = (s3h2_relay_cmd_header_t *)payload_buf;
    memcpy(header->target_ext_addr, target_ext_addr, 8);
    header->cbor_len = cbor_len;
    memcpy(&payload_buf[header_size], cbor_data, cbor_len);

    ESP_LOGI(TAG, "Relaying command to crate, cbor_len=%d", cbor_len);
    return send_command_wait_response(S3H2_CMD_RELAY_CMD,
                                       payload_buf, total_len,
                                       S3H2_RSP_ACK, NULL, 0,
                                       timeout_ms);
}

/*******************************************************************************
 * Health Monitoring Task
 ******************************************************************************/

static void health_monitor_task(void *arg)
{
    ESP_LOGI(TAG, "Health monitor started (interval=%dms, max_failures=%d)",
             H2_COMM_PING_INTERVAL_MS, H2_COMM_MAX_PING_FAILURES);

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(H2_COMM_PING_INTERVAL_MS));

        esp_err_t ret = h2_comm_ping(H2_COMM_CMD_TIMEOUT_MS);

        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "H2 PING failed (%lu consecutive)",
                     (unsigned long)s_stats.ping_failures);

            if (s_h2_connected) {
                s_h2_connected = false;
                s_stats.h2_connected = false;
                esp_event_post(H2_COMM_EVENTS, H2_COMM_EVENT_DISCONNECTED, NULL, 0,
                               pdMS_TO_TICKS(100));
                ESP_LOGW(TAG, "H2 disconnected");
            }

            if (s_stats.ping_failures >= H2_COMM_MAX_PING_FAILURES) {
                ESP_LOGE(TAG, "H2 not responding - resetting");
                h2_comm_reset();
                /* Give H2 time to boot before next ping */
                vTaskDelay(pdMS_TO_TICKS(H2_COMM_BOOT_DELAY_MS));
            }
        } else {
            s_stats.h2_connected = true;
        }
    }
}

esp_err_t h2_comm_start_health_monitor(void)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_health_task_handle != NULL) {
        ESP_LOGW(TAG, "Health monitor already running");
        return ESP_OK;
    }

    BaseType_t ret = xTaskCreate(health_monitor_task, "h2_health",
                                  3072, NULL,
                                  H2_COMM_TASK_PRIORITY - 1,
                                  &s_health_task_handle);
    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create health monitor task");
        return ESP_ERR_NO_MEM;
    }

    return ESP_OK;
}

esp_err_t h2_comm_stop_health_monitor(void)
{
    if (s_health_task_handle != NULL) {
        vTaskDelete(s_health_task_handle);
        s_health_task_handle = NULL;
        ESP_LOGI(TAG, "Health monitor stopped");
    }
    return ESP_OK;
}

bool h2_comm_is_health_monitor_running(void)
{
    return s_health_task_handle != NULL;
}

/*******************************************************************************
 * Statistics and Debug
 ******************************************************************************/

esp_err_t h2_comm_get_stats(h2_comm_stats_t *stats)
{
    if (stats == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(stats, &s_stats, sizeof(s_stats));
    stats->h2_connected = s_h2_connected;
    return ESP_OK;
}

const char *h2_comm_thread_state_str(s3h2_thread_state_t state)
{
    switch (state) {
        case S3H2_THREAD_STATE_DISABLED:  return "DISABLED";
        case S3H2_THREAD_STATE_DETACHED:  return "DETACHED";
        case S3H2_THREAD_STATE_ATTACHING: return "ATTACHING";
        case S3H2_THREAD_STATE_CHILD:     return "CHILD";
        case S3H2_THREAD_STATE_ROUTER:    return "ROUTER";
        case S3H2_THREAD_STATE_LEADER:    return "LEADER";
        default:                          return "UNKNOWN";
    }
}
