/**
 * @file ble_prov.c
 * @brief BLE provisioning for consumer Wi-Fi setup
 *
 * Implements BLE-based provisioning using NimBLE stack.
 *
 * Phase 7: BLE Provisioning
 */

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "nvs_flash.h"

/* NimBLE includes */
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "ble_prov.h"
#include "config_store.h"
#include "wifi_manager.h"
#include "led_manager.h"

static const char *TAG = "BLE_PROV";

/*******************************************************************************
 * Constants
 ******************************************************************************/

#define TASK_STACK_SIZE         4096
#define TASK_PRIORITY           5

/* Wi-Fi connection timeout in milliseconds */
#define WIFI_CONNECT_TIMEOUT_MS 15000

/*
 * Full 128-bit UUIDs for Saturday Provisioning Service
 *
 * Base UUID: 5356XXXX-0001-1000-8000-00805f9b34fb
 * Where 5356 = "SV" (Saturday Vinyl) in ASCII
 *
 * UUID byte order is little-endian in BLE_UUID128_INIT:
 * For UUID 53560000-0001-1000-8000-00805f9b34fb:
 *   bytes[0-3]   = 00805f9b (reversed: 9b, 5f, 80, 00)
 *   bytes[4-5]   = 34fb     (reversed: fb, 34)
 *   bytes[6-7]   = 8000     (reversed: 00, 80)
 *   bytes[8-9]   = 1000     (reversed: 00, 10)
 *   bytes[10-11] = 0001     (reversed: 01, 00)
 *   bytes[12-15] = 53560000 (reversed: 00, 00, 56, 53)
 *
 * See docs/ble_provisioning_protocol.md for full specification.
 */

/* Service UUID: 53560000-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_svc_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x00, 0x00, 0x56, 0x53);

/* Device Info (0x0001): 53560001-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_device_info_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x01, 0x00, 0x56, 0x53);

/* Status (0x0002): 53560002-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_status_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x02, 0x00, 0x56, 0x53);

/* Command (0x0003): 53560003-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_command_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x03, 0x00, 0x56, 0x53);

/* Response (0x0004): 53560004-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_response_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x04, 0x00, 0x56, 0x53);

/* Wi-Fi SSID (0x0010): 53560010-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_wifi_ssid_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x10, 0x00, 0x56, 0x53);

/* Wi-Fi Password (0x0011): 53560011-0001-1000-8000-00805f9b34fb */
static const ble_uuid128_t gatt_svr_chr_wifi_pass_uuid =
    BLE_UUID128_INIT(0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80,
                     0x00, 0x10, 0x01, 0x00, 0x11, 0x00, 0x56, 0x53);

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static int gatt_svr_chr_access(uint16_t conn_handle, uint16_t attr_handle,
                                struct ble_gatt_access_ctxt *ctxt, void *arg);
static void ble_prov_on_sync(void);
static void ble_prov_on_reset(int reason);
static int ble_gap_event(struct ble_gap_event *event, void *arg);

/*******************************************************************************
 * GATT Service Definition
 ******************************************************************************/

static uint16_t s_status_chr_val_handle;
static uint16_t s_response_chr_val_handle;

static const struct ble_gatt_svc_def gatt_svr_svcs[] = {
    {
        /* Saturday Provisioning Service */
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &gatt_svr_svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                /* Device Info (0x0001) - Read */
                .uuid = &gatt_svr_chr_device_info_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_READ,
            },
            {
                /* Status (0x0002) - Read/Notify */
                .uuid = &gatt_svr_chr_status_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_status_chr_val_handle,
            },
            {
                /* Command (0x0003) - Write */
                .uuid = &gatt_svr_chr_command_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                /* Response (0x0004) - Read/Notify */
                .uuid = &gatt_svr_chr_response_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_response_chr_val_handle,
            },
            {
                /* Wi-Fi SSID (0x0010) - Write */
                .uuid = &gatt_svr_chr_wifi_ssid_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                /* Wi-Fi Password (0x0011) - Write */
                .uuid = &gatt_svr_chr_wifi_pass_uuid.u,
                .access_cb = gatt_svr_chr_access,
                .flags = BLE_GATT_CHR_F_WRITE,
            },
            {
                0, /* Terminator */
            },
        },
    },
    {
        0, /* Terminator */
    },
};

/*******************************************************************************
 * Module State
 ******************************************************************************/

static struct {
    bool initialized;
    bool active;
    bool provisioning_complete;
    ble_prov_state_t state;
    uint16_t conn_handle;

    /* Received credentials */
    char wifi_ssid[BLE_PROV_MAX_SSID_LEN + 1];
    char wifi_pass[BLE_PROV_MAX_PASS_LEN + 1];
    bool ssid_received;
    bool pass_received;

    /* Status and response values */
    uint8_t status_value;
    char response_msg[BLE_PROV_MAX_RESPONSE_LEN];

    /* Configuration */
    uint16_t adv_timeout_sec;
    bool require_pairing;

    /* Callbacks */
    ble_prov_state_callback_t state_cb;
    ble_prov_complete_callback_t complete_cb;
    void *user_data;

    /* Timing */
    int64_t adv_start_time;

    /* Device name */
    char device_name[32];

    /* Synchronization */
    SemaphoreHandle_t mutex;

    /* Timeout timer */
    esp_timer_handle_t timeout_timer;
} s_ble = {0};

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static void set_state(ble_prov_state_t new_state)
{
    if (s_ble.state == new_state) {
        return;
    }

    ESP_LOGI(TAG, "State: %s -> %s",
             ble_prov_state_to_string(s_ble.state),
             ble_prov_state_to_string(new_state));

    s_ble.state = new_state;

    /* Invoke callback if registered */
    if (s_ble.state_cb) {
        s_ble.state_cb(new_state, s_ble.user_data);
    }
}

static void update_status(ble_prov_status_code_t status)
{
    s_ble.status_value = (uint8_t)status;

    /* Notify connected client if any */
    if (s_ble.conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(&s_ble.status_value, 1);
        if (om) {
            ble_gatts_notify_custom(s_ble.conn_handle, s_status_chr_val_handle, om);
        }
    }
}

static void send_response(const char *msg)
{
    strncpy(s_ble.response_msg, msg, sizeof(s_ble.response_msg) - 1);
    s_ble.response_msg[sizeof(s_ble.response_msg) - 1] = '\0';

    /* Notify connected client if any */
    if (s_ble.conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(s_ble.response_msg,
                                                    strlen(s_ble.response_msg));
        if (om) {
            ble_gatts_notify_custom(s_ble.conn_handle, s_response_chr_val_handle, om);
        }
    }
}

static void generate_device_name(void)
{
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_BT);

    /* Check if we have a unit_id to use */
    char unit_id[32] = {0};
    if (config_has_unit_id() && config_get_unit_id(unit_id, sizeof(unit_id)) == ESP_OK) {
        /* Use last 4 characters of unit_id (or full id if shorter) */
        size_t len = strlen(unit_id);
        const char *suffix = (len >= 4) ? (unit_id + len - 4) : unit_id;
        snprintf(s_ble.device_name, sizeof(s_ble.device_name),
                 "Saturday Hub %.4s", suffix);
    } else {
        /* Use last 2 bytes of MAC address */
        snprintf(s_ble.device_name, sizeof(s_ble.device_name),
                 "Saturday Hub %02X%02X", mac[4], mac[5]);
    }

    ESP_LOGI(TAG, "BLE device name: %s", s_ble.device_name);
}

/**
 * @brief Generate device info JSON for the Device Info characteristic
 *
 * Returns a JSON string with device metadata per the BLE provisioning protocol.
 */
static int generate_device_info_json(char *buf, size_t buf_len)
{
    char unit_id[32] = {0};
    if (config_has_unit_id()) {
        config_get_unit_id(unit_id, sizeof(unit_id));
    }

    bool has_wifi = config_has_wifi();
    bool needs_prov = !has_wifi;

    return snprintf(buf, buf_len,
        "{"
        "\"device_type\":\"hub\","
        "\"unit_id\":\"%s\","
        "\"firmware_version\":\"%s\","
        "\"protocol_version\":\"1.0\","
        "\"capabilities\":[\"wifi\",\"thread_br\",\"rfid\"],"
        "\"needs_provisioning\":%s,"
        "\"has_wifi\":%s,"
        "\"has_thread\":false"
        "}",
        unit_id,
        FIRMWARE_VERSION,
        needs_prov ? "true" : "false",
        has_wifi ? "true" : "false"
    );
}

static void timeout_callback(void *arg)
{
    (void)arg;
    ESP_LOGW(TAG, "Advertising timeout");

    set_state(BLE_PROV_STATE_TIMEOUT);
    update_status(BLE_PROV_STATUS_ERROR_TIMEOUT);

    /* Stop advertising */
    ble_gap_adv_stop();
    s_ble.active = false;

    /* Return LED to idle state */
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
    led_set_brightness(16);
}

/*******************************************************************************
 * Wi-Fi Connection Handler
 ******************************************************************************/

static void wifi_connect_task(void *arg)
{
    (void)arg;
    char response[BLE_PROV_MAX_RESPONSE_LEN];

    ESP_LOGI(TAG, "Attempting Wi-Fi connection to '%s'...", s_ble.wifi_ssid);

    set_state(BLE_PROV_STATE_CONNECTING_WIFI);
    update_status(BLE_PROV_STATUS_CONNECTING);
    snprintf(response, sizeof(response),
             "{\"type\":\"progress\",\"code\":\"CONNECTING\",\"message\":\"Connecting to %s...\"}",
             s_ble.wifi_ssid);
    send_response(response);

    /* Update LED to show connecting */
    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_PULSE, 1500);

    /* Store credentials in config */
    esp_err_t ret = config_set_wifi(s_ble.wifi_ssid, s_ble.wifi_pass);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to store Wi-Fi credentials: %s", esp_err_to_name(ret));
        set_state(BLE_PROV_STATE_FAILED);
        update_status(BLE_PROV_STATUS_ERROR_UNKNOWN);
        send_response("{\"type\":\"error\",\"code\":\"STORAGE_ERROR\",\"message\":\"Failed to store credentials\"}");
        led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);
        vTaskDelete(NULL);
        return;
    }

    /* Attempt connection */
    ret = wifi_connect(s_ble.wifi_ssid, s_ble.wifi_pass);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Wi-Fi connect failed: %s", esp_err_to_name(ret));
        set_state(BLE_PROV_STATE_FAILED);
        update_status(BLE_PROV_STATUS_ERROR_WIFI);
        send_response("{\"type\":\"error\",\"code\":\"WIFI_FAILED\",\"message\":\"Connection failed - check password\"}");
        led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);

        /* Clear the bad credentials */
        config_clear_wifi();

        vTaskDelete(NULL);
        return;
    }

    /* Wait for connection with timeout */
    int64_t start = esp_timer_get_time();
    while ((esp_timer_get_time() - start) < (WIFI_CONNECT_TIMEOUT_MS * 1000)) {
        if (wifi_is_connected()) {
            ESP_LOGI(TAG, "Wi-Fi connected successfully!");

            set_state(BLE_PROV_STATE_SUCCESS);
            update_status(BLE_PROV_STATUS_SUCCESS);
            snprintf(response, sizeof(response),
                     "{\"type\":\"message\",\"code\":\"SUCCESS\",\"message\":\"Connected to %s\"}",
                     s_ble.wifi_ssid);
            send_response(response);

            /* Mark provisioning as complete */
            s_ble.provisioning_complete = true;

            /* Flash green to indicate success */
            led_flash(LED_COLOR_GREEN, 500);
            vTaskDelay(pdMS_TO_TICKS(600));
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(64);

            /* Invoke completion callback */
            if (s_ble.complete_cb) {
                s_ble.complete_cb(true, s_ble.wifi_ssid, s_ble.user_data);
            }

            /* Stop BLE advertising/connection after short delay */
            vTaskDelay(pdMS_TO_TICKS(2000));
            ble_prov_stop();

            vTaskDelete(NULL);
            return;
        }
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    /* Timeout waiting for connection */
    ESP_LOGE(TAG, "Wi-Fi connection timeout");
    set_state(BLE_PROV_STATE_FAILED);
    update_status(BLE_PROV_STATUS_ERROR_TIMEOUT);
    send_response("{\"type\":\"error\",\"code\":\"TIMEOUT\",\"message\":\"Connection timed out\"}");
    led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);

    /* Clear the bad credentials */
    config_clear_wifi();

    /* Invoke completion callback with failure */
    if (s_ble.complete_cb) {
        s_ble.complete_cb(false, s_ble.wifi_ssid, s_ble.user_data);
    }

    vTaskDelete(NULL);
}

static void start_wifi_connection(void)
{
    /* Create task for Wi-Fi connection (needs larger stack for TLS) */
    xTaskCreate(wifi_connect_task, "ble_wifi_conn", 8192, NULL,
                TASK_PRIORITY, NULL);
}

/*******************************************************************************
 * GATT Characteristic Access Handler
 ******************************************************************************/

static int gatt_svr_chr_access(uint16_t conn_handle, uint16_t attr_handle,
                                struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    const ble_uuid_t *uuid = ctxt->chr->uuid;
    int rc;

    /* Device Info Characteristic (0x0001) - Read */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_device_info_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
            char device_info[256];
            int len = generate_device_info_json(device_info, sizeof(device_info));
            if (len < 0 || len >= (int)sizeof(device_info)) {
                return BLE_ATT_ERR_UNLIKELY;
            }
            rc = os_mbuf_append(ctxt->om, device_info, len);
            return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Status Characteristic (0x0002) - Read */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_status_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
            rc = os_mbuf_append(ctxt->om, &s_ble.status_value, 1);
            return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Response Characteristic (0x0004) - Read */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_response_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
            rc = os_mbuf_append(ctxt->om, s_ble.response_msg,
                                strlen(s_ble.response_msg));
            return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Wi-Fi SSID Characteristic (0x0010) - Write */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_wifi_ssid_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
            uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
            if (len == 0 || len > BLE_PROV_MAX_SSID_LEN) {
                ESP_LOGW(TAG, "Invalid SSID length: %d", len);
                update_status(BLE_PROV_STATUS_ERROR_SSID);
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }

            rc = ble_hs_mbuf_to_flat(ctxt->om, s_ble.wifi_ssid, len, NULL);
            if (rc != 0) {
                return BLE_ATT_ERR_UNLIKELY;
            }
            s_ble.wifi_ssid[len] = '\0';
            s_ble.ssid_received = true;

            ESP_LOGI(TAG, "SSID received: '%s'", s_ble.wifi_ssid);

            /* Check if we have both credentials */
            if (s_ble.ssid_received && s_ble.pass_received) {
                set_state(BLE_PROV_STATE_CREDENTIALS_SET);
                update_status(BLE_PROV_STATUS_CREDENTIALS_OK);
                send_response("{\"type\":\"message\",\"code\":\"CREDENTIALS_OK\",\"message\":\"Credentials received\"}");
            }

            return 0;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Wi-Fi Password Characteristic (0x0011) - Write */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_wifi_pass_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
            uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
            if (len > BLE_PROV_MAX_PASS_LEN) {
                ESP_LOGW(TAG, "Invalid password length: %d", len);
                update_status(BLE_PROV_STATUS_ERROR_PASS);
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }

            /* Password can be empty for open networks */
            if (len > 0) {
                rc = ble_hs_mbuf_to_flat(ctxt->om, s_ble.wifi_pass, len, NULL);
                if (rc != 0) {
                    return BLE_ATT_ERR_UNLIKELY;
                }
                s_ble.wifi_pass[len] = '\0';
            } else {
                s_ble.wifi_pass[0] = '\0';
            }
            s_ble.pass_received = true;

            ESP_LOGI(TAG, "Password received (length: %d)", len);

            /* Check if we have both credentials */
            if (s_ble.ssid_received && s_ble.pass_received) {
                set_state(BLE_PROV_STATE_CREDENTIALS_SET);
                update_status(BLE_PROV_STATUS_CREDENTIALS_OK);
                send_response("{\"type\":\"message\",\"code\":\"CREDENTIALS_OK\",\"message\":\"Credentials received\"}");
            }

            return 0;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Command Characteristic (0x0003) - Write */
    if (ble_uuid_cmp(uuid, &gatt_svr_chr_command_uuid.u) == 0) {
        if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
            uint8_t cmd;
            uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
            if (len < 1) {
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }

            rc = ble_hs_mbuf_to_flat(ctxt->om, &cmd, 1, NULL);
            if (rc != 0) {
                return BLE_ATT_ERR_UNLIKELY;
            }

            ESP_LOGI(TAG, "Command received: 0x%02X", cmd);

            switch (cmd) {
                case BLE_PROV_CMD_CONNECT:
                    if (!s_ble.ssid_received || !s_ble.pass_received) {
                        ESP_LOGW(TAG, "Connect requested but credentials not complete");
                        send_response("{\"type\":\"error\",\"code\":\"MISSING_CREDENTIALS\",\"message\":\"SSID and password required\"}");
                        return 0;
                    }
                    /* Start Wi-Fi connection in separate task */
                    start_wifi_connection();
                    break;

                case BLE_PROV_CMD_RESET:
                    ESP_LOGI(TAG, "Reset command - clearing credentials");
                    s_ble.wifi_ssid[0] = '\0';
                    s_ble.wifi_pass[0] = '\0';
                    s_ble.ssid_received = false;
                    s_ble.pass_received = false;
                    set_state(BLE_PROV_STATE_CONNECTED);
                    update_status(BLE_PROV_STATUS_READY);
                    send_response("{\"type\":\"message\",\"code\":\"RESET\",\"message\":\"Credentials cleared\"}");
                    break;

                case BLE_PROV_CMD_GET_STATUS:
                    ESP_LOGI(TAG, "Status request");
                    /* Update the status - client will receive notification */
                    if (s_ble.ssid_received && s_ble.pass_received) {
                        update_status(BLE_PROV_STATUS_CREDENTIALS_OK);
                    } else {
                        update_status(BLE_PROV_STATUS_READY);
                    }
                    break;

                case BLE_PROV_CMD_SCAN_WIFI:
                    ESP_LOGI(TAG, "Wi-Fi scan requested (not implemented)");
                    send_response("{\"type\":\"error\",\"code\":\"NOT_IMPLEMENTED\",\"message\":\"Wi-Fi scan not yet implemented\"}");
                    break;

                case BLE_PROV_CMD_ABORT:
                    ESP_LOGI(TAG, "Abort command received");
                    s_ble.wifi_ssid[0] = '\0';
                    s_ble.wifi_pass[0] = '\0';
                    s_ble.ssid_received = false;
                    s_ble.pass_received = false;
                    set_state(BLE_PROV_STATE_CONNECTED);
                    update_status(BLE_PROV_STATUS_READY);
                    send_response("{\"type\":\"message\",\"code\":\"ABORTED\",\"message\":\"Operation aborted\"}");
                    break;

                default:
                    ESP_LOGW(TAG, "Unknown command: 0x%02X", cmd);
                    send_response("{\"type\":\"error\",\"code\":\"UNKNOWN_COMMAND\",\"message\":\"Unknown command\"}");
                    break;
            }

            return 0;
        }
        return BLE_ATT_ERR_UNLIKELY;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

/*******************************************************************************
 * GAP Event Handler
 ******************************************************************************/

static int ble_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0) {
                ESP_LOGI(TAG, "BLE connected (handle=%d)", event->connect.conn_handle);
                s_ble.conn_handle = event->connect.conn_handle;
                set_state(BLE_PROV_STATE_CONNECTED);
                update_status(BLE_PROV_STATUS_READY);
                send_response("{\"type\":\"message\",\"code\":\"CONNECTED\",\"message\":\"Ready for credentials\"}");

                /* Stop timeout timer - we have a connection */
                if (s_ble.timeout_timer) {
                    esp_timer_stop(s_ble.timeout_timer);
                }

                /* Update LED to indicate connected */
                led_set_state(LED_COLOR_BLUE, LED_PATTERN_SOLID, 0);
                led_set_brightness(64);
            } else {
                ESP_LOGW(TAG, "BLE connection failed: %d", event->connect.status);
                /* Restart advertising */
                ble_prov_start();
            }
            break;

        case BLE_GAP_EVENT_DISCONNECT:
            ESP_LOGI(TAG, "BLE disconnected (reason=0x%02X)",
                     event->disconnect.reason);
            s_ble.conn_handle = BLE_HS_CONN_HANDLE_NONE;

            /* If provisioning not complete, restart advertising */
            if (!s_ble.provisioning_complete && s_ble.active) {
                ESP_LOGI(TAG, "Restarting advertising...");
                set_state(BLE_PROV_STATE_ADVERTISING);

                /* Reset credentials */
                s_ble.wifi_ssid[0] = '\0';
                s_ble.wifi_pass[0] = '\0';
                s_ble.ssid_received = false;
                s_ble.pass_received = false;

                /* Restart advertising */
                ble_prov_start();
            }
            break;

        case BLE_GAP_EVENT_ADV_COMPLETE:
            ESP_LOGI(TAG, "Advertising complete");
            if (!s_ble.provisioning_complete && s_ble.active) {
                /* Restart advertising if not connected */
                if (s_ble.conn_handle == BLE_HS_CONN_HANDLE_NONE) {
                    ble_prov_start();
                }
            }
            break;

        case BLE_GAP_EVENT_MTU:
            ESP_LOGI(TAG, "MTU update: conn_handle=%d, mtu=%d",
                     event->mtu.conn_handle, event->mtu.value);
            break;

        case BLE_GAP_EVENT_SUBSCRIBE:
            ESP_LOGI(TAG, "Subscribe: conn_handle=%d, attr_handle=%d",
                     event->subscribe.conn_handle, event->subscribe.attr_handle);
            break;

        default:
            ESP_LOGD(TAG, "GAP event: %d", event->type);
            break;
    }

    return 0;
}

/*******************************************************************************
 * NimBLE Host Callbacks
 ******************************************************************************/

static uint8_t ble_addr_type;

static void ble_prov_on_sync(void)
{
    ESP_LOGI(TAG, "NimBLE host synced");

    /* Configure device address */
    int rc = ble_hs_id_infer_auto(0, &ble_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to infer address type: %d", rc);
        return;
    }

    uint8_t addr[6];
    ble_hs_id_copy_addr(ble_addr_type, addr, NULL);
    ESP_LOGI(TAG, "BLE address: %02X:%02X:%02X:%02X:%02X:%02X",
             addr[5], addr[4], addr[3], addr[2], addr[1], addr[0]);
}

static void ble_prov_on_reset(int reason)
{
    ESP_LOGW(TAG, "NimBLE host reset: %d", reason);
}

static void ble_host_task(void *param)
{
    ESP_LOGI(TAG, "NimBLE host task started");
    nimble_port_run();
    nimble_port_freertos_deinit();
}

/*******************************************************************************
 * Public API Implementation
 ******************************************************************************/

esp_err_t ble_prov_init(const ble_prov_config_t *config)
{
    if (s_ble.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing BLE provisioning...");

    /* Create mutex */
    s_ble.mutex = xSemaphoreCreateMutex();
    if (!s_ble.mutex) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Apply configuration */
    if (config) {
        s_ble.adv_timeout_sec = config->adv_timeout_sec;
        s_ble.require_pairing = config->require_pairing;
        s_ble.state_cb = config->state_cb;
        s_ble.complete_cb = config->complete_cb;
        s_ble.user_data = config->user_data;
    } else {
        s_ble.adv_timeout_sec = BLE_PROV_ADV_TIMEOUT_SEC;
        s_ble.require_pairing = false;
    }

    /* Generate device name */
    generate_device_name();

    /* Initialize NimBLE */
    esp_err_t ret = nimble_port_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "nimble_port_init failed: %s", esp_err_to_name(ret));
        vSemaphoreDelete(s_ble.mutex);
        return ret;
    }

    /* Configure NimBLE host */
    ble_hs_cfg.sync_cb = ble_prov_on_sync;
    ble_hs_cfg.reset_cb = ble_prov_on_reset;

    /* Initialize GAP and GATT services */
    ble_svc_gap_init();
    ble_svc_gatt_init();

    /* Register GATT services */
    int rc = ble_gatts_count_cfg(gatt_svr_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_count_cfg failed: %d", rc);
        nimble_port_deinit();
        vSemaphoreDelete(s_ble.mutex);
        return ESP_FAIL;
    }

    rc = ble_gatts_add_svcs(gatt_svr_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_add_svcs failed: %d", rc);
        nimble_port_deinit();
        vSemaphoreDelete(s_ble.mutex);
        return ESP_FAIL;
    }

    /* Set device name */
    rc = ble_svc_gap_device_name_set(s_ble.device_name);
    if (rc != 0) {
        ESP_LOGW(TAG, "Failed to set device name: %d", rc);
    }

    /* Create timeout timer */
    esp_timer_create_args_t timer_args = {
        .callback = timeout_callback,
        .arg = NULL,
        .name = "ble_prov_timeout"
    };
    ret = esp_timer_create(&timer_args, &s_ble.timeout_timer);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to create timeout timer: %s", esp_err_to_name(ret));
        /* Continue without timeout timer */
    }

    /* Start NimBLE host task */
    nimble_port_freertos_init(ble_host_task);

    s_ble.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    s_ble.initialized = true;
    s_ble.state = BLE_PROV_STATE_IDLE;

    ESP_LOGI(TAG, "BLE provisioning initialized");
    return ESP_OK;
}

esp_err_t ble_prov_deinit(void)
{
    if (!s_ble.initialized) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Deinitializing BLE provisioning...");

    /* Stop advertising and disconnect */
    ble_prov_stop();

    /* Stop timeout timer */
    if (s_ble.timeout_timer) {
        esp_timer_stop(s_ble.timeout_timer);
        esp_timer_delete(s_ble.timeout_timer);
        s_ble.timeout_timer = NULL;
    }

    /* Deinitialize NimBLE */
    int rc = nimble_port_stop();
    if (rc != 0) {
        ESP_LOGW(TAG, "nimble_port_stop failed: %d", rc);
    }

    nimble_port_deinit();

    /* Delete mutex */
    if (s_ble.mutex) {
        vSemaphoreDelete(s_ble.mutex);
        s_ble.mutex = NULL;
    }

    memset(&s_ble, 0, sizeof(s_ble));

    ESP_LOGI(TAG, "BLE provisioning deinitialized");
    return ESP_OK;
}

esp_err_t ble_prov_start(void)
{
    if (!s_ble.initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Starting BLE advertising as '%s'...", s_ble.device_name);

    /* Reset state */
    s_ble.wifi_ssid[0] = '\0';
    s_ble.wifi_pass[0] = '\0';
    s_ble.ssid_received = false;
    s_ble.pass_received = false;
    s_ble.provisioning_complete = false;
    s_ble.response_msg[0] = '\0';
    s_ble.status_value = BLE_PROV_STATUS_READY;

    /* Configure advertising */
    struct ble_gap_adv_params adv_params = {0};
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    adv_params.itvl_min = BLE_GAP_ADV_FAST_INTERVAL1_MIN;
    adv_params.itvl_max = BLE_GAP_ADV_FAST_INTERVAL1_MAX;

    /* Build advertising data */
    struct ble_hs_adv_fields adv_fields = {0};
    adv_fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    adv_fields.name = (uint8_t *)s_ble.device_name;
    adv_fields.name_len = strlen(s_ble.device_name);
    adv_fields.name_is_complete = 1;

    /* Include service UUID in scan response */
    static ble_uuid16_t svc_uuid16 = BLE_UUID16_INIT(BLE_PROV_SERVICE_UUID);
    adv_fields.uuids16 = &svc_uuid16;
    adv_fields.num_uuids16 = 1;
    adv_fields.uuids16_is_complete = 1;

    int rc = ble_gap_adv_set_fields(&adv_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to set advertising fields: %d", rc);
        return ESP_FAIL;
    }

    /* Start advertising */
    rc = ble_gap_adv_start(ble_addr_type, NULL, BLE_HS_FOREVER,
                           &adv_params, ble_gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to start advertising: %d", rc);
        return ESP_FAIL;
    }

    s_ble.active = true;
    s_ble.adv_start_time = esp_timer_get_time();
    set_state(BLE_PROV_STATE_ADVERTISING);

    /* Start timeout timer if configured */
    if (s_ble.timeout_timer && s_ble.adv_timeout_sec > 0) {
        esp_timer_start_once(s_ble.timeout_timer,
                             (uint64_t)s_ble.adv_timeout_sec * 1000000);
    }

    /* Set LED to blue slow blink for provisioning mode */
    led_set_state(LED_COLOR_BLUE, LED_PATTERN_BLINK_SLOW, 1000);

    ESP_LOGI(TAG, "BLE advertising started (timeout: %ds)", s_ble.adv_timeout_sec);
    return ESP_OK;
}

esp_err_t ble_prov_stop(void)
{
    if (!s_ble.initialized || !s_ble.active) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping BLE provisioning...");

    /* Stop timeout timer */
    if (s_ble.timeout_timer) {
        esp_timer_stop(s_ble.timeout_timer);
    }

    /* Stop advertising */
    ble_gap_adv_stop();

    /* Disconnect if connected */
    if (s_ble.conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ble_gap_terminate(s_ble.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
        s_ble.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    }

    s_ble.active = false;
    set_state(BLE_PROV_STATE_IDLE);

    /* Return LED to idle state */
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
    led_set_brightness(16);

    ESP_LOGI(TAG, "BLE provisioning stopped");
    return ESP_OK;
}

bool ble_prov_is_active(void)
{
    return s_ble.active;
}

ble_prov_state_t ble_prov_get_state(void)
{
    return s_ble.state;
}

esp_err_t ble_prov_get_status(ble_prov_status_t *status)
{
    if (!status) {
        return ESP_ERR_INVALID_ARG;
    }

    status->state = s_ble.state;
    status->is_connected = (s_ble.conn_handle != BLE_HS_CONN_HANDLE_NONE);
    status->credentials_received = s_ble.ssid_received && s_ble.pass_received;
    strncpy(status->ssid, s_ble.wifi_ssid, sizeof(status->ssid) - 1);
    status->adv_start_time = (uint32_t)(s_ble.adv_start_time / 1000000);
    status->conn_handle = s_ble.conn_handle;

    return ESP_OK;
}

esp_err_t ble_prov_register_state_callback(ble_prov_state_callback_t callback,
                                            void *user_data)
{
    s_ble.state_cb = callback;
    s_ble.user_data = user_data;
    return ESP_OK;
}

esp_err_t ble_prov_register_complete_callback(ble_prov_complete_callback_t callback,
                                               void *user_data)
{
    s_ble.complete_cb = callback;
    s_ble.user_data = user_data;
    return ESP_OK;
}

bool ble_prov_is_complete(void)
{
    return s_ble.provisioning_complete;
}

esp_err_t ble_prov_get_device_name(char *name, size_t max_len)
{
    if (!name || max_len == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    strncpy(name, s_ble.device_name, max_len - 1);
    name[max_len - 1] = '\0';
    return ESP_OK;
}

const char *ble_prov_state_to_string(ble_prov_state_t state)
{
    switch (state) {
        case BLE_PROV_STATE_IDLE:            return "IDLE";
        case BLE_PROV_STATE_ADVERTISING:     return "ADVERTISING";
        case BLE_PROV_STATE_CONNECTED:       return "CONNECTED";
        case BLE_PROV_STATE_CREDENTIALS_SET: return "CREDENTIALS_SET";
        case BLE_PROV_STATE_CONNECTING_WIFI: return "CONNECTING_WIFI";
        case BLE_PROV_STATE_SUCCESS:         return "SUCCESS";
        case BLE_PROV_STATE_FAILED:          return "FAILED";
        case BLE_PROV_STATE_TIMEOUT:         return "TIMEOUT";
        default:                             return "UNKNOWN";
    }
}
