/**
 * @file main.c
 * @brief Saturday Vinyl Hub - ESP32-S3 Master Entry Point
 *
 * This is the master MCU firmware handling WiFi, BLE, RFID, and H2 management.
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "esp_event.h"

#include "app_config.h"
#include "led_manager.h"
#include "button_handler.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "now_playing.h"
#include "config_store.h"
#include "wifi_manager.h"
#include "supabase_client.h"
#include "event_reporter.h"
#include "realtime_client.h"
#include "ble_prov.h"
#include "serial_prov.h"
#include "h2_comm.h"
#include "ota_manager.h"
#include "cbor.h"
#include "cJSON.h"
#include "h2_flasher.h"
#include "watchdog_manager.h"

static const char *TAG = "main";

/* Track WiFi state for LED management */
static bool s_wifi_connected = false;

/* Track if we're in service mode */
static bool s_service_mode_active = false;

/* Track if we're in BLE provisioning mode */
static bool s_ble_prov_active = false;

/* Track if BLE has been deinitialized (requires reboot to re-provision) */
static bool s_ble_deinitialized = false;

/* Track H2 connection state */
static bool s_h2_connected = false;

/* Track OTA boot validation */
static bool s_boot_validated = false;

/* PROD-2.4: Error tracking for graceful degradation */
static uint32_t s_h2_error_count = 0;
static uint32_t s_wifi_error_count = 0;
#define MAX_SUBSYSTEM_ERRORS 10  /* After this many errors, log warning */

/* Mutex to serialize crate telemetry HTTP posts (prevents heap corruption
 * when two crate_telemetry_task instances call supabase_post() concurrently) */
static SemaphoreHandle_t s_telem_mutex = NULL;

/* Rate-limit S3-initiated re-register nudges after S3 reboot.
 * When S3 reboots (but H2 doesn't), the identity cache is cleared.
 * We send "register" via H2→CoAP to trigger re-registration. */
#define NUDGE_COOLDOWN_MS   60000
#define MAX_NUDGE_DEVICES   8
static struct {
    uint8_t ext_addr[8];
    TickType_t last_tick;
} s_nudge_cooldown[MAX_NUDGE_DEVICES];

/**
 * @brief Now Playing event handler - LED feedback for tag place/remove
 */
static void on_now_playing_event(void *handler_args, esp_event_base_t base,
                                  int32_t id, void *event_data)
{
    now_playing_event_t *event = (now_playing_event_t *)event_data;
    char epc_str[25];
    rfid_epc_to_hex_string(event->epc, event->epc_len, epc_str, sizeof(epc_str));

    switch (id) {
        case NOW_PLAYING_EVENT_TAG_PLACED:
            ESP_LOGI(TAG, ">>> NOW PLAYING: %s (RSSI: %d dBm)", epc_str, event->rssi);
            /* Solid green when tag is present */
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            break;

        case NOW_PLAYING_EVENT_TAG_REMOVED:
            ESP_LOGI(TAG, "<<< STOPPED: %s (played for %lu ms)",
                     epc_str, (unsigned long)event->duration_ms);
            /* Return to slow pulse when idle */
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
            break;
    }
}

/**
 * @brief RFID tag detection callback - feeds into now_playing state machine
 */
static void on_tag_detected(const rfid_tag_t *tag, void *user_data)
{
    /* Pass tag to now_playing state machine for debounced detection */
    now_playing_on_tag_detected(tag);
}

/**
 * @brief RFID poll complete callback - notify now_playing when no tag found
 */
static void on_poll_complete(bool tag_detected, void *user_data)
{
    if (!tag_detected) {
        now_playing_on_poll_complete_no_tag();
    }
}

/**
 * @brief WiFi manager event handler - LED feedback for connection state
 */
static void on_wifi_event(void *handler_args, esp_event_base_t base,
                          int32_t id, void *event_data)
{
    switch (id) {
        case WIFI_MANAGER_EVENT_CONNECTED: {
            wifi_connection_info_t *info = (wifi_connection_info_t *)event_data;
            ESP_LOGI(TAG, "WiFi connected to '%s' (RSSI: %d dBm)", info->ssid, info->rssi);
            s_wifi_connected = true;
            /* PROD-2.4: Reset error counter on successful connection */
            if (s_wifi_error_count > 0) {
                ESP_LOGI(TAG, "WiFi recovered after %lu failed attempts",
                         (unsigned long)s_wifi_error_count);
                s_wifi_error_count = 0;
            }
            /* Notify event reporter of WiFi state */
            event_reporter_set_wifi_state(true);
            /* Flash cyan to indicate WiFi connected, then return to green pulse */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_CYAN, 500);
                vTaskDelay(pdMS_TO_TICKS(500));
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
            }
            /* Validate OTA boot after WiFi connects successfully
             * This confirms the new firmware is working properly */
            if (!s_boot_validated && ota_manager_get_boot_status() == OTA_BOOT_PENDING_VERIFY) {
                ESP_LOGI(TAG, "WiFi connected after OTA - validating boot");
                esp_err_t ota_ret = ota_manager_validate_boot();
                if (ota_ret == ESP_OK) {
                    s_boot_validated = true;
                }
            }
            /* Release BLE stack memory after successful WiFi connection.
             * NimBLE stays resident after provisioning otherwise (~30KB).
             * A device reboot is required to re-provision WiFi via BLE. */
            if (!s_ble_deinitialized) {
                ESP_LOGI(TAG, "WiFi connected - deinitializing BLE to free memory");
                ble_prov_deinit();
                s_ble_deinitialized = true;
            }

            /* Connect to Supabase Realtime for push notifications */
            if (supabase_is_configured()) {
                esp_err_t rt_ret = realtime_client_connect();
                if (rt_ret != ESP_OK) {
                    ESP_LOGW(TAG, "Failed to connect realtime client: %s", esp_err_to_name(rt_ret));
                }
            }
            break;
        }

        case WIFI_MANAGER_EVENT_DISCONNECTED:
            ESP_LOGW(TAG, "WiFi disconnected");
            s_wifi_connected = false;
            /* Notify event reporter of WiFi state */
            event_reporter_set_wifi_state(false);
            /* Yellow slow blink indicates no WiFi (if not in special mode) */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
            break;

        case WIFI_MANAGER_EVENT_CONNECTION_FAILED:
            s_wifi_error_count++;
            ESP_LOGE(TAG, "WiFi connection failed (error count: %lu)",
                     (unsigned long)s_wifi_error_count);
            s_wifi_connected = false;
            /* PROD-2.4: Log persistent WiFi failures */
            if (s_wifi_error_count >= MAX_SUBSYSTEM_ERRORS) {
                ESP_LOGW(TAG, "Persistent WiFi failures - device operating in offline mode");
            }
            /* Red flash then yellow blink (if not in special mode) */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_RED, 500);
                vTaskDelay(pdMS_TO_TICKS(500));
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
            break;
    }
}

/**
 * @brief BLE provisioning state change callback
 */
static void on_ble_prov_state_change(ble_prov_state_t state, void *user_data)
{
    ESP_LOGI(TAG, "BLE provisioning state: %s", ble_prov_state_to_string(state));

    switch (state) {
        case BLE_PROV_STATE_ADVERTISING:
            s_ble_prov_active = true;
            led_set_state(LED_COLOR_BLUE, LED_PATTERN_BLINK_SLOW, 1000);
            break;

        case BLE_PROV_STATE_CONNECTED:
            led_set_state(LED_COLOR_BLUE, LED_PATTERN_SOLID, 0);
            break;

        case BLE_PROV_STATE_CONNECTING_WIFI:
            led_set_state(LED_COLOR_BLUE, LED_PATTERN_BLINK_FAST, 250);
            break;

        case BLE_PROV_STATE_SUCCESS:
            led_flash(LED_COLOR_GREEN, 1000);
            break;

        case BLE_PROV_STATE_FAILED:
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 250);
            break;

        case BLE_PROV_STATE_TIMEOUT:
        case BLE_PROV_STATE_IDLE:
            s_ble_prov_active = false;
            /* Return to appropriate state based on WiFi */
            if (s_wifi_connected) {
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
            } else {
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
            break;

        default:
            break;
    }
}

/**
 * @brief BLE provisioning completion callback
 */
static void on_ble_prov_complete(bool success, const char *ssid, void *user_data)
{
    if (success) {
        ESP_LOGI(TAG, "BLE provisioning successful for '%s'", ssid);
        s_ble_prov_active = false;
        /* WiFi will connect automatically and trigger on_wifi_event */
    } else {
        ESP_LOGW(TAG, "BLE provisioning failed for '%s'", ssid ? ssid : "(null)");
    }
}

/**
 * @brief Service mode state change callback
 */
static void on_service_mode_state_change(serial_prov_state_t state, void *user_data)
{
    ESP_LOGI(TAG, "Service mode state: %d", state);

    switch (state) {
        case SERIAL_PROV_STATE_AWAITING:
            s_service_mode_active = true;
            led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
            break;

        case SERIAL_PROV_STATE_PROVISIONING:
            led_set_state(LED_COLOR_WHITE, LED_PATTERN_BLINK_FAST, 250);
            break;

        case SERIAL_PROV_STATE_TESTING:
            led_set_state(LED_COLOR_CYAN, LED_PATTERN_BLINK_FAST, 250);
            break;

        case SERIAL_PROV_STATE_COMPLETE:
            led_flash(LED_COLOR_GREEN, 2000);
            break;

        case SERIAL_PROV_STATE_ERROR:
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 100);
            break;

        case SERIAL_PROV_STATE_IDLE:
            s_service_mode_active = false;
            break;
    }
}

/**
 * @brief Check if nudge cooldown has elapsed for a device
 *
 * Returns true if the device hasn't been nudged within NUDGE_COOLDOWN_MS,
 * and records the current time as the last nudge time.
 */
static bool nudge_cooldown_ok(const uint8_t *ext_addr)
{
    TickType_t now = xTaskGetTickCount();
    int oldest_idx = 0;
    TickType_t oldest_time = portMAX_DELAY;

    for (int i = 0; i < MAX_NUDGE_DEVICES; i++) {
        if (memcmp(s_nudge_cooldown[i].ext_addr, ext_addr, 8) == 0) {
            if ((now - s_nudge_cooldown[i].last_tick) < pdMS_TO_TICKS(NUDGE_COOLDOWN_MS)) {
                return false;  /* Still in cooldown */
            }
            s_nudge_cooldown[i].last_tick = now;
            return true;
        }
        if (s_nudge_cooldown[i].last_tick < oldest_time) {
            oldest_time = s_nudge_cooldown[i].last_tick;
            oldest_idx = i;
        }
    }

    /* New device — evict oldest slot */
    memcpy(s_nudge_cooldown[oldest_idx].ext_addr, ext_addr, 8);
    s_nudge_cooldown[oldest_idx].last_tick = now;
    return true;
}

/**
 * @brief Request a mesh node to re-register (S3-initiated nudge)
 *
 * When the S3 reboots but H2 doesn't, the S3's identity cache is cleared
 * while H2 still considers the crate registered (responds 2.04, not 4.01).
 * This sends a "register" command via H2 → CoAP to trigger re-registration.
 */
static void request_crate_reregister(const uint8_t *ext_addr)
{
    uint8_t cbor_buf[80];
    CborEncoder encoder, map_enc;
    cbor_encoder_init(&encoder, cbor_buf, sizeof(cbor_buf), 0);
    cbor_encoder_create_map(&encoder, &map_enc, 2);
    cbor_encode_text_stringz(&map_enc, "id");
    cbor_encode_text_stringz(&map_enc, "00000000-0000-0000-0000-000000000000");
    cbor_encode_text_stringz(&map_enc, "cmd");
    cbor_encode_text_stringz(&map_enc, "register");
    cbor_encoder_close_container(&encoder, &map_enc);
    uint16_t cbor_len = (uint16_t)cbor_encoder_get_buffer_size(&encoder, cbor_buf);

    ESP_LOGI(TAG, "Requesting re-register for unidentified crate "
             "%02X%02X%02X%02X%02X%02X%02X%02X",
             ext_addr[0], ext_addr[1], ext_addr[2], ext_addr[3],
             ext_addr[4], ext_addr[5], ext_addr[6], ext_addr[7]);

    h2_comm_relay_command(ext_addr, cbor_buf, cbor_len, 2000);
}

/**
 * @brief Crate telemetry task — executes on a dedicated stack to avoid sys_evt overflow
 *
 * CBOR decoding + JSON serialization + Supabase POST need ~2KB of stack buffers.
 * The sys_evt task only has 4KB, so we offload to a one-shot task.
 *
 * A mutex serializes concurrent instances to prevent heap corruption from
 * concurrent access to the shared persistent HTTP client in supabase_post().
 */
static void crate_telemetry_task(void *arg)
{
    h2_comm_crate_telemetry_event_t *evt = (h2_comm_crate_telemetry_event_t *)arg;

    if (xSemaphoreTake(s_telem_mutex, pdMS_TO_TICKS(10000)) == pdTRUE) {
        esp_err_t ret = event_reporter_queue_crate_telemetry(evt->ext_addr, evt->hb_type,
                                                              evt->cbor_data, evt->cbor_len);

        /* If the identity wasn't cached (ESP_ERR_NOT_FOUND while WiFi is up),
         * request re-registration via H2 → CoAP. This handles the case where
         * S3 rebooted (clearing its cache) but H2 didn't (still has the crate
         * registered, so no 4.01 Unauthorized → no H2-initiated nudge). */
        if (ret == ESP_ERR_NOT_FOUND && s_wifi_connected &&
            nudge_cooldown_ok(evt->ext_addr)) {
            request_crate_reregister(evt->ext_addr);
        }

        xSemaphoreGive(s_telem_mutex);
    } else {
        ESP_LOGW(TAG, "Telemetry mutex timeout — dropping crate telemetry");
    }

    free(evt);
    vTaskDelete(NULL);
}

/**
 * @brief H2 communication event handler - handles Thread/crate events from H2
 */
static void on_h2_event(void *handler_args, esp_event_base_t base,
                        int32_t id, void *event_data)
{
    switch (id) {
        case H2_COMM_EVENT_CONNECTED:
            ESP_LOGI(TAG, "H2 connected");
            s_h2_connected = true;
            /* Start Thread BR on (re)connect — initial boot may miss this if H2 is slow */
            if (h2_comm_start_thread(2000) == ESP_OK) {
                ESP_LOGI(TAG, "Thread BR started");
            } else {
                ESP_LOGW(TAG, "Failed to start Thread BR after H2 connect");
            }
            /* PROD-2.4: Reset error counter on successful connection */
            if (s_h2_error_count > 0) {
                ESP_LOGI(TAG, "H2 recovered after %lu disconnections",
                         (unsigned long)s_h2_error_count);
                s_h2_error_count = 0;
            }
            /* Update event reporter with H2 state */
            event_reporter_set_h2_state(true, 0);
            break;

        case H2_COMM_EVENT_DISCONNECTED:
            s_h2_error_count++;
            ESP_LOGW(TAG, "H2 disconnected (error count: %lu)",
                     (unsigned long)s_h2_error_count);
            s_h2_connected = false;
            event_reporter_set_h2_state(false, 0);
            /* PROD-2.4: Log persistent H2 failures */
            if (s_h2_error_count >= MAX_SUBSYSTEM_ERRORS) {
                ESP_LOGE(TAG, "Persistent H2 communication failures - Thread network unavailable");
            }
            /* Show H2 error state on LED */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);
            }
            break;

        case H2_COMM_EVENT_THREAD_STATE_CHANGED: {
            h2_comm_thread_state_event_t *evt = (h2_comm_thread_state_event_t *)event_data;
            ESP_LOGI(TAG, "Thread state: %s -> %s",
                     h2_comm_thread_state_str(evt->old_state),
                     h2_comm_thread_state_str(evt->new_state));
            event_reporter_set_h2_state(true, evt->new_state);

            /* Brief cyan flash when Thread becomes leader/router */
            if (evt->new_state == S3H2_THREAD_STATE_LEADER ||
                evt->new_state == S3H2_THREAD_STATE_ROUTER) {
                if (!s_ble_prov_active && !s_service_mode_active) {
                    led_flash(LED_COLOR_CYAN, 500);
                }
            }
            break;
        }

        case H2_COMM_EVENT_CRATE_JOINED: {
            h2_comm_crate_joined_event_t *evt = (h2_comm_crate_joined_event_t *)event_data;
            ESP_LOGI(TAG, "Crate joined: rloc16=0x%04X", evt->rloc16);
            /* Brief magenta flash to indicate new crate */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_MAGENTA, 500);
            }
            break;
        }

        case H2_COMM_EVENT_CRATE_LEFT: {
            ESP_LOGI(TAG, "Crate left network");
            break;
        }

        case H2_COMM_EVENT_INVENTORY_UPDATE: {
            h2_comm_inventory_event_t *evt = (h2_comm_inventory_event_t *)event_data;
            ESP_LOGI(TAG, "Inventory update: %d EPCs from crate", evt->epc_count);
            /* Forward to cloud via event_reporter */
            event_reporter_queue_inventory(evt->ext_addr,
                                            (const uint8_t (*)[12])evt->epcs,
                                            evt->epc_count);
            break;
        }

        case H2_COMM_EVENT_CRATE_HEARTBEAT: {
            h2_comm_crate_heartbeat_event_t *evt = (h2_comm_crate_heartbeat_event_t *)event_data;
            ESP_LOGD(TAG, "Crate heartbeat: batt=%d%%, rssi=%d",
                     evt->battery_percent, evt->rssi);
            /* Forward to cloud via event_reporter */
            event_reporter_queue_crate_heartbeat(evt->ext_addr,
                                                  evt->battery_percent,
                                                  evt->rssi);
            break;
        }

        case H2_COMM_EVENT_CRATE_TELEMETRY: {
            h2_comm_crate_telemetry_event_t *evt = (h2_comm_crate_telemetry_event_t *)event_data;
            ESP_LOGI(TAG, "Crate telemetry: type=%d, cbor_len=%d",
                     evt->hb_type, evt->cbor_len);
            /* Offload to dedicated task — CBOR+JSON+HTTP needs more stack than sys_evt has */
            h2_comm_crate_telemetry_event_t *evt_copy = malloc(sizeof(*evt_copy));
            if (evt_copy != NULL) {
                memcpy(evt_copy, evt, sizeof(*evt_copy));
                if (xTaskCreate(crate_telemetry_task, "crate_telem", 6144,
                                evt_copy, 5, NULL) != pdPASS) {
                    ESP_LOGE(TAG, "Failed to create crate_telem task");
                    free(evt_copy);
                }
            }
            break;
        }

        case H2_COMM_EVENT_CRATE_REGISTERED: {
            h2_comm_crate_registered_event_t *evt = (h2_comm_crate_registered_event_t *)event_data;
            ESP_LOGI(TAG, "Crate registered: mac=%s, type=%s",
                     evt->mac, evt->device_type);
            event_reporter_cache_crate_identity(evt->ext_addr, evt->mac,
                                                 evt->unit_id, evt->device_type,
                                                 evt->fw_version);
            break;
        }

        case H2_COMM_EVENT_MESH_CMD_RESULT: {
            h2_comm_mesh_cmd_result_event_t *evt = (h2_comm_mesh_cmd_result_event_t *)event_data;
            if (evt->result == S3H2_CMD_RESULT_OK) {
                ESP_LOGI(TAG, "Mesh cmd %02X%02X%02X%02X%02X%02X%02X%02X \"%s\": acknowledged",
                         evt->ext_addr[0], evt->ext_addr[1], evt->ext_addr[2], evt->ext_addr[3],
                         evt->ext_addr[4], evt->ext_addr[5], evt->ext_addr[6], evt->ext_addr[7],
                         evt->cmd);
            } else if (evt->result == S3H2_CMD_RESULT_TIMEOUT) {
                ESP_LOGW(TAG, "Mesh cmd %02X%02X%02X%02X%02X%02X%02X%02X \"%s\": timeout",
                         evt->ext_addr[0], evt->ext_addr[1], evt->ext_addr[2], evt->ext_addr[3],
                         evt->ext_addr[4], evt->ext_addr[5], evt->ext_addr[6], evt->ext_addr[7],
                         evt->cmd);
            } else {
                ESP_LOGE(TAG, "Mesh cmd %02X%02X%02X%02X%02X%02X%02X%02X \"%s\": error",
                         evt->ext_addr[0], evt->ext_addr[1], evt->ext_addr[2], evt->ext_addr[3],
                         evt->ext_addr[4], evt->ext_addr[5], evt->ext_addr[6], evt->ext_addr[7],
                         evt->cmd);
            }
            break;
        }

        case H2_COMM_EVENT_H2_RESET:
            ESP_LOGW(TAG, "H2 was reset");
            break;

        case H2_COMM_EVENT_ERROR:
            ESP_LOGE(TAG, "H2 error event received");
            break;

        default:
            break;
    }
}

/**
 * @brief OTA manager event handler - LED feedback for OTA operations
 */
static void on_ota_event(void *handler_args, esp_event_base_t base,
                         int32_t id, void *event_data)
{
    switch (id) {
        case OTA_EVENT_CHECK_START:
            ESP_LOGI(TAG, "Checking for firmware updates...");
            break;

        case OTA_EVENT_CHECK_COMPLETE:
            ESP_LOGI(TAG, "Update check complete");
            break;

        case OTA_EVENT_UPDATE_AVAILABLE: {
            ota_update_info_t *info = (ota_update_info_t *)event_data;
            if (info->s3_update_available) {
                ESP_LOGI(TAG, "S3 update available: %s -> %s",
                         info->s3_current.string, info->s3_available.string);
            }
            if (info->h2_update_available) {
                ESP_LOGI(TAG, "H2 update available: %s -> %s",
                         info->h2_current.string, info->h2_available.string);
            }
            /* Brief magenta flash to indicate update available */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_MAGENTA, 500);
            }
            break;
        }

        case OTA_EVENT_UPDATE_START:
            ESP_LOGI(TAG, "OTA update starting...");
            /* Magenta pulse during update */
            led_set_state(LED_COLOR_MAGENTA, LED_PATTERN_PULSE, 1000);
            break;

        case OTA_EVENT_UPDATE_PROGRESS: {
            ota_progress_data_t *progress = (ota_progress_data_t *)event_data;
            ESP_LOGI(TAG, "OTA progress: %d%% (%lu/%lu bytes)",
                     progress->percentage,
                     (unsigned long)progress->bytes_written,
                     (unsigned long)progress->total_bytes);
            break;
        }

        case OTA_EVENT_UPDATE_COMPLETE: {
            ota_result_data_t *result = (ota_result_data_t *)event_data;
            ESP_LOGI(TAG, "OTA update complete: %s firmware v%s",
                     result->firmware == OTA_FIRMWARE_S3 ? "S3" : "H2",
                     result->version);
            led_flash(LED_COLOR_GREEN, 2000);
            break;
        }

        case OTA_EVENT_UPDATE_FAILED: {
            ota_result_data_t *result = (ota_result_data_t *)event_data;
            ESP_LOGE(TAG, "OTA update failed: %s", esp_err_to_name(result->error));
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 250);
            vTaskDelay(pdMS_TO_TICKS(2000));
            /* Return to normal state */
            if (s_wifi_connected) {
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
            } else {
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
            break;
        }

        case OTA_EVENT_ROLLBACK_TRIGGERED:
            ESP_LOGW(TAG, "OTA rollback triggered - previous firmware restored");
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);
            vTaskDelay(pdMS_TO_TICKS(3000));
            break;

        case OTA_EVENT_BOOT_VALIDATED:
            ESP_LOGI(TAG, "OTA boot validated successfully");
            s_boot_validated = true;
            break;

        default:
            break;
    }
}

/**
 * @brief Run test task — executes on a dedicated stack to avoid sys_evt overflow
 *
 * The system event loop task has a small stack (~3.5KB). H2 UART communication
 * and cJSON serialization need more room, so the event handler spawns this
 * one-shot task with 4KB of stack.
 */
static void run_test_task(void *arg)
{
    realtime_command_event_t *event = (realtime_command_event_t *)arg;

    cJSON *params = cJSON_Parse(event->parameters);
    if (params == NULL) {
        realtime_client_ack_command(event->command_id, "failed",
            "{\"error\":\"invalid_params\",\"message\":\"Failed to parse parameters\"}");
        goto done;
    }

    const cJSON *cap_json = cJSON_GetObjectItem(params, "capability");
    const cJSON *test_json = cJSON_GetObjectItem(params, "test_name");
    const char *cap = cJSON_IsString(cap_json) ? cap_json->valuestring : "";
    const char *test = cJSON_IsString(test_json) ? test_json->valuestring : "";

    if (strcmp(cap, "thread_br") == 0 &&
        (strcmp(test, "connect") == 0 || strcmp(test, "start") == 0
         || strcmp(test, "get_dataset") == 0)) {

        /* Get Thread status and credentials from H2 */
        s3h2_status_payload_t h2_status;
        esp_err_t ret = h2_comm_get_status(&h2_status, 3000);
        if (ret != ESP_OK) {
            realtime_client_ack_command(event->command_id, "failed",
                "{\"error\":\"h2_status_failed\",\"message\":\"Failed to get Thread BR status from H2\"}");
            goto cleanup;
        }

        s3h2_credentials_payload_t h2_creds;
        ret = h2_comm_get_credentials(&h2_creds, 3000);
        if (ret != ESP_OK) {
            realtime_client_ack_command(event->command_id, "failed",
                "{\"error\":\"thread_creds_failed\",\"message\":\"Failed to get Thread credentials from H2\"}");
            goto cleanup;
        }

        /* Build result JSON */
        cJSON *result = cJSON_CreateObject();
        cJSON_AddStringToObject(result, "network_name", h2_creds.network_name);
        cJSON_AddNumberToObject(result, "pan_id", h2_creds.pan_id);
        cJSON_AddNumberToObject(result, "channel", h2_creds.channel);

        char network_key_hex[33];
        for (int i = 0; i < 16; i++) {
            snprintf(&network_key_hex[i * 2], 3, "%02x", h2_creds.network_key[i]);
        }
        cJSON_AddStringToObject(result, "network_key", network_key_hex);

        char extpanid_hex[17];
        for (int i = 0; i < 8; i++) {
            snprintf(&extpanid_hex[i * 2], 3, "%02x", h2_creds.extended_pan_id[i]);
        }
        cJSON_AddStringToObject(result, "extended_pan_id", extpanid_hex);

        char mesh_prefix_hex[17];
        for (int i = 0; i < 8; i++) {
            snprintf(&mesh_prefix_hex[i * 2], 3, "%02x", h2_creds.mesh_local_prefix[i]);
        }
        cJSON_AddStringToObject(result, "mesh_local_prefix", mesh_prefix_hex);

        bool attached = (h2_status.thread_state >= S3H2_THREAD_STATE_CHILD);
        cJSON_AddBoolToObject(result, "attached", attached);
        cJSON_AddStringToObject(result, "role",
            h2_comm_thread_state_str((s3h2_thread_state_t)h2_status.thread_state));
        cJSON_AddNumberToObject(result, "rloc16", h2_status.rloc16);
        cJSON_AddNumberToObject(result, "device_count", h2_status.device_count);

        char *result_str = cJSON_PrintUnformatted(result);
        realtime_client_ack_command(event->command_id, "completed", result_str);
        free(result_str);
        cJSON_Delete(result);

    } else {
        char err_msg[128];
        snprintf(err_msg, sizeof(err_msg),
            "{\"error\":\"test_not_found\",\"message\":\"Unknown test: %s/%s\"}", cap, test);
        realtime_client_ack_command(event->command_id, "failed", err_msg);
    }

cleanup:
    cJSON_Delete(params);
done:
    free(event);
    vTaskDelete(NULL);
}

/**
 * @brief Realtime client event handler - handles push notifications from cloud
 */
static void on_realtime_event(void *handler_args, esp_event_base_t base,
                               int32_t id, void *event_data)
{
    switch (id) {
        case REALTIME_EVENT_CONNECTED:
            ESP_LOGI(TAG, "Realtime client connected");
            break;

        case REALTIME_EVENT_DISCONNECTED:
            ESP_LOGW(TAG, "Realtime client disconnected");
            break;

        case REALTIME_EVENT_UPDATE_AVAILABLE: {
            realtime_update_event_t *event = (realtime_update_event_t *)event_data;
            ESP_LOGI(TAG, "Push update received: type=%s, components=%d, critical=%d",
                     event->device_type, event->component_count, event->is_critical);
            /* OTA is auto-applied by realtime_client if configured */
            /* Flash magenta to indicate update being processed */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_MAGENTA, 500);
            }
            break;
        }

        case REALTIME_EVENT_COMMAND: {
            realtime_command_event_t *event = (realtime_command_event_t *)event_data;
            ESP_LOGI(TAG, "Remote command received: %s", event->command);
            /* Built-in commands (reboot, check_update, get_status) are handled by realtime_client */
            if (strcmp(event->command, "run_test") == 0) {
                /* Spawn on a dedicated task — H2 comm + cJSON need more stack than sys_evt provides */
                realtime_command_event_t *event_copy = malloc(sizeof(*event_copy));
                if (event_copy != NULL) {
                    memcpy(event_copy, event, sizeof(*event_copy));
                    if (xTaskCreate(run_test_task, "run_test", 8192, event_copy, 5, NULL) != pdPASS) {
                        ESP_LOGE(TAG, "Failed to create run_test task");
                        realtime_client_ack_command(event->command_id, "failed",
                            "{\"error\":\"task_failed\",\"message\":\"Could not create test task\"}");
                        free(event_copy);
                    }
                }
            }
            break;
        }

        case REALTIME_EVENT_CONFIG_UPDATE:
            ESP_LOGI(TAG, "Config update notification received");
            /* Could reload configuration from cloud here */
            break;

        case REALTIME_EVENT_ERROR:
            ESP_LOGE(TAG, "Realtime client error");
            break;

        default:
            break;
    }
}

/**
 * @brief H2 flasher event handler - LED feedback for H2 flashing
 */
static void on_h2_flasher_event(void *handler_args, esp_event_base_t base,
                                 int32_t id, void *event_data)
{
    switch (id) {
        case H2_FLASHER_EVENT_START:
            ESP_LOGI(TAG, "H2 flash starting...");
            /* Cyan pulse during H2 flash */
            led_set_state(LED_COLOR_CYAN, LED_PATTERN_PULSE, 500);
            break;

        case H2_FLASHER_EVENT_PROGRESS: {
            h2_flasher_progress_t *progress = (h2_flasher_progress_t *)event_data;
            ESP_LOGI(TAG, "H2 flash progress: %d%% (%lu/%lu bytes)",
                     progress->percentage,
                     (unsigned long)progress->bytes_written,
                     (unsigned long)progress->total_bytes);
            break;
        }

        case H2_FLASHER_EVENT_COMPLETE: {
            h2_flasher_result_t *result = (h2_flasher_result_t *)event_data;
            ESP_LOGI(TAG, "H2 flash completed in %lu ms", (unsigned long)result->flash_time_ms);
            led_flash(LED_COLOR_GREEN, 2000);
            break;
        }

        case H2_FLASHER_EVENT_FAILED: {
            h2_flasher_result_t *result = (h2_flasher_result_t *)event_data;
            ESP_LOGE(TAG, "H2 flash failed: %s", esp_err_to_name(result->error));
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 250);
            vTaskDelay(pdMS_TO_TICKS(3000));
            break;
        }

        default:
            break;
    }
}

/**
 * @brief Button press callback
 */
static void on_button_press(button_press_t press_type)
{
    switch (press_type) {
        case BUTTON_PRESS_SHORT:
            ESP_LOGI(TAG, "Short button press detected");
            led_flash(LED_COLOR_GREEN, 200);
            break;
        case BUTTON_PRESS_LONG:
            ESP_LOGI(TAG, "Long button press - BLE provisioning requested");
            if (s_ble_deinitialized) {
                ESP_LOGW(TAG, "BLE has been released to free memory - reboot to re-provision WiFi");
                led_flash(LED_COLOR_RED, 1000);
            } else if (!ble_prov_is_active() && !s_service_mode_active) {
                esp_err_t ret = ble_prov_start();
                if (ret != ESP_OK) {
                    ESP_LOGE(TAG, "Failed to start BLE provisioning: %s", esp_err_to_name(ret));
                    led_flash(LED_COLOR_RED, 500);
                }
            } else {
                ESP_LOGW(TAG, "Cannot start BLE prov - already active or in service mode");
            }
            break;
        case BUTTON_PRESS_FACTORY:
            /* Customer reset: clears WiFi credentials but keeps unit_id/Supabase config.
             * Factory reset (clears everything) is only available via service mode. */
            ESP_LOGW(TAG, "Customer reset requested!");
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 100);
            esp_err_t ret = config_customer_reset();
            if (ret == ESP_OK) {
                ESP_LOGW(TAG, "Customer reset complete - restarting...");
                vTaskDelay(pdMS_TO_TICKS(2000));
                esp_restart();
            } else {
                ESP_LOGE(TAG, "Customer reset failed: %s", esp_err_to_name(ret));
            }
            break;
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "Saturday Vinyl Hub - S3 Master v%s", FW_VERSION_STRING);
    ESP_LOGI(TAG, "Initializing...");

    /* Initialize NVS */
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition needs erase");
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    ESP_LOGI(TAG, "NVS initialized");

    /* Phase PROD-2.1: Initialize watchdog manager early */
    ret = watchdog_manager_init(30);  /* 30 second timeout */
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Watchdog manager init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Watchdog manager initialized");

        /* Check if last reset was watchdog-triggered */
        if (watchdog_was_reset_by_watchdog()) {
            ESP_LOGW(TAG, "*** Last reset was caused by watchdog timeout! ***");
        }

        /* Register main task */
        ret = watchdog_register_task(WATCHDOG_TASK_MAIN, NULL, "main");
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register main task with watchdog: %s", esp_err_to_name(ret));
        }
    }

    /* Phase PROD-2.3: Initialize heap monitoring */
    ret = heap_monitor_init(32 * 1024, 16 * 1024);  /* 32KB low, 16KB critical */
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Heap monitor init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Heap monitor initialized");
    }

    /* Create default event loop (required for now_playing events) */
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
    }

    /* Phase PROD-1: Initialize OTA manager early to handle boot validation */
    ota_config_t ota_config = OTA_CONFIG_DEFAULT();
    ota_config.auto_apply = false;  /* Require explicit trigger for updates */
    ota_config.auto_reboot = false; /* Don't auto-reboot after update */
    ret = ota_manager_init(&ota_config);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "OTA manager init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "OTA manager initialized");

        /* Register OTA event handler for LED feedback */
        ret = esp_event_handler_register(OTA_EVENTS, ESP_EVENT_ANY_ID,
                                          on_ota_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register OTA event handler: %s", esp_err_to_name(ret));
        }

        /* Log boot status */
        ota_boot_status_t boot_status = ota_manager_get_boot_status();
        if (boot_status == OTA_BOOT_PENDING_VERIFY) {
            ESP_LOGW(TAG, "First boot after OTA update - will validate after WiFi connects");
        } else if (boot_status == OTA_BOOT_ROLLBACK) {
            ESP_LOGW(TAG, "Running after OTA rollback - previous firmware restored");
        }
    }

    /* Phase S3-3: Initialize configuration store */
    ret = config_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Config store init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Configuration store initialized");
    }

    /* Load RFID config from NVS (or use defaults) */
    rfid_config_t rfid_cfg;
    config_get_rfid(&rfid_cfg);
    ESP_LOGI(TAG, "RFID config: poll=%dms, power=%ddBm, debounce_present=%dms, debounce_absent=%dms",
             rfid_cfg.poll_interval_ms, rfid_cfg.rf_power_dbm,
             rfid_cfg.debounce_present_ms, rfid_cfg.debounce_absent_ms);

    /* Phase S3-1: Initialize LED manager */
    ret = led_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "LED init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "LED manager initialized");
        /* Show startup indicator */
        led_set_state(LED_COLOR_BLUE, LED_PATTERN_PULSE, 2000);
    }

    /* Phase S3-1: Initialize button handler */
    ret = button_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Button init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Button handler initialized");
        button_register_callback(on_button_press);
    }

    /* Phase S3-3: Initialize now_playing state machine */
    now_playing_config_t np_config = {
        .debounce_present_ms = rfid_cfg.debounce_present_ms,
        .debounce_absent_ms = rfid_cfg.debounce_absent_ms,
    };
    ret = now_playing_init(&np_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Now Playing init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Now Playing state machine initialized");

        /* Register event handler for TAG_PLACED/TAG_REMOVED */
        ret = esp_event_handler_register(NOW_PLAYING_EVENTS, ESP_EVENT_ANY_ID,
                                          on_now_playing_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register now_playing event handler: %s",
                     esp_err_to_name(ret));
        }
    }

    /* Phase S3-2: Initialize RFID driver */
    ret = yrm100_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "RFID init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "YRM100 RFID driver initialized");

        /* Enable the RFID module */
        yrm100_enable(true);

        /* Get firmware version to verify communication */
        char version[32];
        ret = yrm100_get_firmware_version(version, sizeof(version));
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "YRM100 firmware: %s", version);
        } else {
            ESP_LOGW(TAG, "Failed to get YRM100 firmware version: %s", esp_err_to_name(ret));
        }

        /* Register tag callback and poll complete callback */
        yrm100_register_tag_callback(on_tag_detected, NULL);
        yrm100_register_poll_complete_callback(on_poll_complete, NULL);

        /* Use RFID config from NVS */
        yrm100_poll_config_t poll_config = {
            .poll_interval_ms = rfid_cfg.poll_interval_ms,
            .rf_power_dbm = rfid_cfg.rf_power_dbm,
            .filter_saturday_only = true,  /* Only Saturday tags for now_playing */
        };

        ret = yrm100_start_polling_task(&poll_config);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "RFID polling started (interval=%dms, power=%ddBm)",
                     poll_config.poll_interval_ms, poll_config.rf_power_dbm);
            /* Change LED to green pulse to indicate ready */
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
        } else {
            ESP_LOGE(TAG, "Failed to start RFID polling: %s", esp_err_to_name(ret));
        }
    }

    /* Phase S3-4: Initialize WiFi manager */
    ret = wifi_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "WiFi init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "WiFi manager initialized");

        /* Register WiFi event handler for LED feedback */
        ret = esp_event_handler_register(WIFI_MANAGER_EVENTS, ESP_EVENT_ANY_ID,
                                          on_wifi_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register WiFi event handler: %s", esp_err_to_name(ret));
        }

        /* Try to connect using stored credentials */
        if (config_has_wifi()) {
            ESP_LOGI(TAG, "Stored WiFi credentials found, connecting...");
            led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_FAST, 250);
            ret = wifi_connect_stored();
            if (ret != ESP_OK) {
                ESP_LOGW(TAG, "Failed to start WiFi connection: %s", esp_err_to_name(ret));
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
        } else {
            ESP_LOGI(TAG, "No stored WiFi credentials - will start BLE provisioning after init");
            /* Don't set yellow LED here - BLE provisioning will set blue LED shortly */
        }
    }

    /* Phase S3-5: Initialize Supabase client */
    ret = supabase_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Supabase init failed: %s (will configure during provisioning)", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Supabase client initialized");
        if (supabase_is_configured()) {
            ESP_LOGI(TAG, "Supabase credentials found in NVS");
        } else {
            ESP_LOGI(TAG, "Supabase not configured - awaiting service mode provisioning");
        }
    }

    /* Phase S3-5: Initialize event reporter */
    event_reporter_config_t er_config = EVENT_REPORTER_CONFIG_DEFAULT();
    ret = event_reporter_init(&er_config);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Event reporter init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Event reporter initialized");
        /* Start the background reporting task */
        ret = event_reporter_start();
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "Event reporter started (heartbeat=%ds)", er_config.heartbeat_interval_sec);
        }
    }

    /* OTA Push Protocol: Initialize realtime client for push notifications */
    realtime_config_t rt_config = REALTIME_CONFIG_DEFAULT();
    rt_config.auto_apply_updates = true;  /* Auto-apply OTA updates */
    ret = realtime_client_init(&rt_config);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Realtime client init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Realtime client initialized");

        /* Register realtime event handler */
        ret = esp_event_handler_register(REALTIME_EVENTS, ESP_EVENT_ANY_ID,
                                          on_realtime_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register realtime event handler: %s", esp_err_to_name(ret));
        }
    }

    /* Phase S3-6: Initialize BLE provisioning */
    ble_prov_config_t ble_config = {
        .adv_timeout_sec = BLE_PROV_ADV_TIMEOUT_SEC,
        .require_pairing = false,  /* Simplified for consumer ease of use */
        .state_cb = on_ble_prov_state_change,
        .complete_cb = on_ble_prov_complete,
        .user_data = NULL,
    };
    ret = ble_prov_init(&ble_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "BLE provisioning init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "BLE provisioning initialized");
    }

    /* Phase PROD-1.2: Initialize H2 flasher */
    ret = h2_flasher_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "H2 flasher init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "H2 flasher initialized");

        /* Register H2 flasher event handler */
        ret = esp_event_handler_register(H2_FLASHER_EVENTS, ESP_EVENT_ANY_ID,
                                          on_h2_flasher_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register H2 flasher event handler: %s", esp_err_to_name(ret));
        }

        /* Check if H2 update is pending */
        if (ota_manager_h2_update_pending()) {
            ESP_LOGW(TAG, "H2 firmware update pending - flashing H2...");
            led_set_state(LED_COLOR_CYAN, LED_PATTERN_PULSE, 500);

            ota_version_t staged_version;
            if (ota_manager_get_staged_h2_version(&staged_version) == ESP_OK) {
                ESP_LOGI(TAG, "Staging H2 firmware version: %s", staged_version.string);
            }

            /* Flash the H2 */
            ret = h2_flasher_flash(60000);  /* 60 second timeout */
            if (ret == ESP_OK) {
                ESP_LOGI(TAG, "H2 flash successful");
                ota_manager_h2_update_complete(true);
            } else {
                ESP_LOGE(TAG, "H2 flash failed: %s", esp_err_to_name(ret));
                ota_manager_h2_update_complete(false);
                /* Try to reset H2 to normal mode anyway */
                h2_flasher_reset_normal();
            }
        }
    }

    /* Create mutex for serializing crate telemetry HTTP posts */
    s_telem_mutex = xSemaphoreCreateMutex();
    if (s_telem_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create telemetry mutex");
    }

    /* Phase S3-7/INT-1: Initialize H2 communication interface */
    ret = h2_comm_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "H2 communication init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "H2 communication initialized");

        /* Register for H2 events */
        ret = esp_event_handler_register(H2_COMM_EVENTS, ESP_EVENT_ANY_ID,
                                          on_h2_event, NULL);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to register H2 event handler: %s", esp_err_to_name(ret));
        }

        /* Try initial PING to check if H2 is present */
        ret = h2_comm_ping(1000);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "H2 responded to initial PING");
            s_h2_connected = true;

            /* Get H2 version */
            s3h2_version_payload_t h2_version;
            if (h2_comm_get_version(&h2_version, 1000) == ESP_OK) {
                ESP_LOGI(TAG, "H2 firmware version: %d.%d.%d",
                         h2_version.major, h2_version.minor, h2_version.patch);
            }

            /* Start Thread network */
            ret = h2_comm_start_thread(2000);
            if (ret == ESP_OK) {
                ESP_LOGI(TAG, "Thread BR started");
            } else {
                ESP_LOGW(TAG, "Failed to start Thread BR: %s", esp_err_to_name(ret));
            }
        } else {
            ESP_LOGW(TAG, "H2 not responding - will retry via health monitor");
        }

        /* Start H2 health monitoring (periodic PING, auto-reset) */
        ret = h2_comm_start_health_monitor();
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "H2 health monitor started");
        } else {
            ESP_LOGW(TAG, "Failed to start H2 health monitor: %s", esp_err_to_name(ret));
        }
    }

    /* Phase S3-8: Initialize serial command handler (Device Command Protocol v1.3)
     * Per the protocol, devices are "always-listening" - no entry window required. */
    ret = serial_prov_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Serial command handler init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Serial command handler initialized");
        serial_prov_register_callback(on_service_mode_state_change, NULL);

        /* Start always-listening command handler immediately.
         * Per Device Command Protocol v1.3, devices continuously listen for
         * commands when connected - no entry window or service mode required.
         * This handles get_status, factory_provision, run_test, etc. */
        ret = serial_prov_start_background_listener();
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to start command listener: %s", esp_err_to_name(ret));
        } else {
            ESP_LOGI(TAG, "Command listener active (always-listening mode)");
        }
    }

    /* Check provisioning state and set appropriate LED/mode */
    if (!config_has_unit_id()) {
        /* No unit_id = fresh from factory, awaiting provisioning */
        ESP_LOGW(TAG, "Device not provisioned (no unit_id) - awaiting factory_provision command");
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
    } else {
        /* Device is provisioned */
        char unit_id[32];
        config_get_unit_id(unit_id, sizeof(unit_id));
        ESP_LOGI(TAG, "Device provisioned: %s", unit_id);

        if (!config_has_wifi()) {
            /* Has unit_id but no WiFi = factory provisioned, needs consumer WiFi setup */
            ESP_LOGI(TAG, "No WiFi configured - starting BLE provisioning");
            s_ble_prov_active = true;
            ret = ble_prov_start();
            if (ret != ESP_OK) {
                ESP_LOGE(TAG, "Failed to start BLE provisioning: %s", esp_err_to_name(ret));
                s_ble_prov_active = false;
            }
        } else {
            /* Fully provisioned - proceed to normal operation */
            ESP_LOGI(TAG, "Proceeding to standard operation");
            if (s_wifi_connected) {
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
            } else {
                led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_SLOW, 1000);
            }
        }
    }

    ESP_LOGI(TAG, "Initialization complete - system running");

    /* Main loop - feed watchdog and perform periodic tasks */
    uint32_t loop_count = 0;
    while (1) {
        /* Feed the watchdog to indicate main task is alive */
        watchdog_feed();

        /* PROD-2.3: Check heap status every loop iteration */
        heap_status_t heap_status;
        esp_err_t heap_ret = heap_monitor_check(&heap_status);
        if (heap_ret == ESP_ERR_NO_MEM) {
            ESP_LOGE(TAG, "CRITICAL: Memory critically low! Attempting recovery...");
            /* Could trigger graceful degradation here in the future */
        }

        /* Periodic status logging (every 30 seconds) */
        loop_count++;
        if (loop_count % 30 == 0) {
            ESP_LOGI(TAG, "Status: heap=%luKB (min=%luKB), wifi=%s, h2=%s",
                     (unsigned long)(heap_status.free_heap / 1024),
                     (unsigned long)(heap_status.min_free_heap / 1024),
                     s_wifi_connected ? "connected" : "disconnected",
                     s_h2_connected ? "connected" : "disconnected");

            /* Log heap fragmentation indicator */
            if (heap_status.largest_free_block < heap_status.free_heap / 2) {
                ESP_LOGW(TAG, "Heap fragmentation detected: free=%luKB, largest_block=%luKB",
                         (unsigned long)(heap_status.free_heap / 1024),
                         (unsigned long)(heap_status.largest_free_block / 1024));
            }
        }

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
