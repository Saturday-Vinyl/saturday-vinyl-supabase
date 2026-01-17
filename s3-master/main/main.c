/**
 * @file main.c
 * @brief Saturday Vinyl Hub - ESP32-S3 Master Entry Point
 *
 * This is the master MCU firmware handling WiFi, BLE, RFID, and H2 management.
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
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
#include "ble_prov.h"
#include "serial_prov.h"

static const char *TAG = "main";

/* Track WiFi state for LED management */
static bool s_wifi_connected = false;

/* Track if we're in service mode */
static bool s_service_mode_active = false;

/* Track if we're in BLE provisioning mode */
static bool s_ble_prov_active = false;

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
            /* Notify event reporter of WiFi state */
            event_reporter_set_wifi_state(true);
            /* Flash cyan to indicate WiFi connected, then return to green pulse */
            if (!s_ble_prov_active && !s_service_mode_active) {
                led_flash(LED_COLOR_CYAN, 500);
                vTaskDelay(pdMS_TO_TICKS(500));
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_PULSE, 3000);
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
            ESP_LOGE(TAG, "WiFi connection failed");
            s_wifi_connected = false;
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
            /* Start BLE provisioning if not already active */
            if (!ble_prov_is_active() && !s_service_mode_active) {
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

    /* Create default event loop (required for now_playing events) */
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
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

    /* TODO: Phase S3-7 - Initialize H2 communication interface */

    /* Phase S3-8: Initialize service mode handler */
    ret = serial_prov_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Service mode init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Service mode initialized");
        serial_prov_register_callback(on_service_mode_state_change, NULL);
    }

    /* Check if device needs factory provisioning or consumer WiFi setup */
    if (!config_has_unit_id()) {
        /* No unit_id = fresh from factory, needs service mode provisioning */
        ESP_LOGW(TAG, "Device not provisioned (no unit_id) - entering service mode");
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        ret = serial_prov_start();
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to start service mode: %s", esp_err_to_name(ret));
        }
    } else if (!config_has_wifi()) {
        /* Has unit_id but no WiFi = factory provisioned, needs consumer WiFi setup */
        char unit_id[32];
        config_get_unit_id(unit_id, sizeof(unit_id));
        ESP_LOGI(TAG, "Device provisioned (%s) but no WiFi - starting BLE provisioning", unit_id);
        s_ble_prov_active = true;  /* Set flag before starting to prevent yellow LED race */
        ret = ble_prov_start();
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to start BLE provisioning: %s", esp_err_to_name(ret));
            s_ble_prov_active = false;
        }
    } else {
        char unit_id[32];
        config_get_unit_id(unit_id, sizeof(unit_id));
        ESP_LOGI(TAG, "Device provisioned: %s", unit_id);
    }

    ESP_LOGI(TAG, "Initialization complete - system running");

    /* Main loop placeholder */
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
