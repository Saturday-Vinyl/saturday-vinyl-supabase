/**
 * @file main.c
 * @brief Saturday Vinyl Hub firmware entry point
 *
 * This is the main entry point for the Saturday Hub firmware.
 * It initializes all subsystems and demonstrates hardware functionality.
 *
 * Phase 1: Hardware Bring-Up
 * - RGB LED with PWM patterns
 * - Button with debounced press detection
 * - RFID module UART communication
 *
 * Phase 2: RFID Detection
 * - Tag detection with EPC extraction
 * - Saturday tag validation (0x5356 prefix)
 * - Background polling task with callbacks
 *
 * Phase 3: Now Playing Logic
 * - Debounced state machine for tag presence detection
 * - ESP-IDF event loop integration
 * - LED feedback for Now Playing state
 * - Configurable debounce timing via NVS
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_chip_info.h"
#include "esp_event.h"
#include "nvs_flash.h"

#include "app_config.h"
#include "led_manager.h"
#include "button_handler.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "now_playing.h"
#include "config_store.h"

static const char *TAG = "SV_HUB";

/* Track if a Saturday tag was detected in the current poll cycle */
static bool s_saturday_tag_detected_this_poll = false;

/*******************************************************************************
 * Button Callback
 ******************************************************************************/

/**
 * @brief Callback for button press events
 *
 * Demonstrates LED feedback for different button press types.
 */
static void on_button_press(button_press_t press_type)
{
    switch (press_type) {
        case BUTTON_PRESS_SHORT:
            ESP_LOGI(TAG, "Short press detected - changing LED color");
            /* Cycle through colors on short press */
            static int color_index = 0;
            led_color_preset_t colors[] = {
                LED_COLOR_RED, LED_COLOR_GREEN, LED_COLOR_BLUE,
                LED_COLOR_YELLOW, LED_COLOR_CYAN, LED_COLOR_MAGENTA
            };
            color_index = (color_index + 1) % 6;
            led_set_state(colors[color_index], LED_PATTERN_SOLID, 0);
            break;

        case BUTTON_PRESS_LONG:
            ESP_LOGI(TAG, "Long press detected - entering provisioning mode (demo)");
            /* Blue slow blink indicates provisioning mode */
            led_set_state(LED_COLOR_BLUE, LED_PATTERN_BLINK_SLOW, 1000);
            break;

        case BUTTON_PRESS_FACTORY:
            ESP_LOGI(TAG, "Factory reset requested - red fast blink (demo)");
            /* Red fast blink indicates factory reset */
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 500);
            break;
    }
}

/*******************************************************************************
 * NVS Initialization
 ******************************************************************************/

static esp_err_t nvs_init(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition was truncated, erasing...");
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    return ret;
}

/*******************************************************************************
 * Now Playing Event Handler (Phase 3)
 ******************************************************************************/

/**
 * @brief Handler for Now Playing events (TAG_PLACED / TAG_REMOVED)
 *
 * Updates LED to reflect Now Playing state.
 */
static void on_now_playing_event(void *handler_args, esp_event_base_t base,
                                  int32_t event_id, void *event_data)
{
    const now_playing_event_t *event = (const now_playing_event_t *)event_data;
    char epc_str[25];
    rfid_epc_to_hex_string(event->epc, event->epc_len, epc_str, sizeof(epc_str));

    switch (event_id) {
        case NOW_PLAYING_EVENT_TAG_PLACED:
            ESP_LOGI(TAG, ">>> NOW PLAYING: %s (RSSI: %d dBm)", epc_str, event->rssi);
            /* Flash green to indicate tag confirmed, then show dim green solid */
            led_flash(LED_COLOR_GREEN, 300);
            /* After flash, set to dim green solid to indicate Now Playing */
            vTaskDelay(pdMS_TO_TICKS(350));
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(64);
            break;

        case NOW_PLAYING_EVENT_TAG_REMOVED:
            ESP_LOGI(TAG, "<<< STOPPED PLAYING: %s (duration: %lu ms)",
                     epc_str, (unsigned long)event->duration_ms);
            /* Flash briefly, then return to idle state (very dim green) */
            led_flash(LED_COLOR_CYAN, 200);
            vTaskDelay(pdMS_TO_TICKS(250));
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(16);  /* Very dim for idle */
            break;

        default:
            ESP_LOGW(TAG, "Unknown Now Playing event: %ld", (long)event_id);
            break;
    }
}

/*******************************************************************************
 * RFID Tag Callback (Phase 2 + Phase 3 Integration)
 ******************************************************************************/

/**
 * @brief Callback invoked when a tag is detected by the polling task
 *
 * This callback runs in the context of the RFID polling task, so it
 * should be quick and non-blocking.
 *
 * Phase 3: Now feeds tags into the Now Playing state machine.
 */
static void on_tag_detected(const rfid_tag_t *tag, void *user_data)
{
    char epc_str[25];
    rfid_epc_to_hex_string(tag->epc, tag->epc_len, epc_str, sizeof(epc_str));

    if (tag->is_saturday_tag) {
        ESP_LOGD(TAG, "Saturday tag: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));

        /* Mark that we saw a Saturday tag this poll cycle */
        s_saturday_tag_detected_this_poll = true;

        /* Feed to Now Playing state machine */
        now_playing_on_tag_detected(tag);
    } else {
        ESP_LOGD(TAG, "Non-Saturday tag: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));
        /* Non-Saturday tags don't affect Now Playing state */
    }
}

/**
 * @brief Callback invoked after each poll cycle completes
 *
 * Used to inform the Now Playing state machine when no Saturday tag was seen.
 */
static void on_poll_cycle_complete(bool tag_detected, void *user_data)
{
    (void)tag_detected;  /* We track Saturday tags specifically */

    if (!s_saturday_tag_detected_this_poll) {
        /* No Saturday tag was seen this poll - notify state machine */
        now_playing_on_poll_complete_no_tag();
    }
    /* Reset for next poll cycle */
    s_saturday_tag_detected_this_poll = false;
}

/*******************************************************************************
 * RFID and Now Playing Initialization (Phase 2 + Phase 3)
 ******************************************************************************/

/**
 * @brief Initialize and start RFID polling with Now Playing integration
 *
 * Validates communication with the RFID module, initializes the Now Playing
 * state machine, and starts the background polling task.
 */
static esp_err_t start_rfid_polling(void)
{
    ESP_LOGI(TAG, "Initializing RFID subsystem...");

    /* Load RFID configuration from NVS */
    rfid_config_t rfid_cfg;
    esp_err_t ret = config_get_rfid(&rfid_cfg);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to load RFID config, using defaults");
        rfid_cfg.poll_interval_ms = DEFAULT_POLL_INTERVAL_MS;
        rfid_cfg.rf_power_dbm = DEFAULT_RF_POWER_DBM;
        rfid_cfg.debounce_present_ms = DEFAULT_DEBOUNCE_PRESENT_MS;
        rfid_cfg.debounce_absent_ms = DEFAULT_DEBOUNCE_ABSENT_MS;
    }

    ESP_LOGI(TAG, "RFID config: poll=%dms, power=%ddBm, deb_present=%dms, deb_absent=%dms",
             rfid_cfg.poll_interval_ms, rfid_cfg.rf_power_dbm,
             rfid_cfg.debounce_present_ms, rfid_cfg.debounce_absent_ms);

    /* Initialize Now Playing state machine with config from NVS */
    now_playing_config_t np_config = {
        .debounce_present_ms = rfid_cfg.debounce_present_ms,
        .debounce_absent_ms = rfid_cfg.debounce_absent_ms,
    };
    ret = now_playing_init(&np_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize Now Playing: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "Now Playing state machine initialized");

    /* Register for Now Playing events */
    ret = esp_event_handler_register(NOW_PLAYING_EVENTS, ESP_EVENT_ANY_ID,
                                      on_now_playing_event, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Now Playing event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Enable the RFID module */
    yrm100_enable(true);
    vTaskDelay(pdMS_TO_TICKS(500));  /* Extra settling time */

    /* Try to get firmware version to verify communication */
    char version[32] = {0};
    ret = yrm100_get_firmware_version(version, sizeof(version));

    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "RFID module firmware: %s", version);
        led_flash(LED_COLOR_GREEN, 200);
    } else if (ret == ESP_ERR_TIMEOUT) {
        ESP_LOGW(TAG, "RFID module not responding (timeout) - check wiring");
        led_flash(LED_COLOR_ORANGE, 200);
        return ret;
    } else {
        ESP_LOGE(TAG, "RFID communication error: %s", esp_err_to_name(ret));
        led_flash(LED_COLOR_RED, 200);
        return ret;
    }

    /* Register callbacks for tag detection and poll completion */
    yrm100_register_tag_callback(on_tag_detected, NULL);
    yrm100_register_poll_complete_callback(on_poll_cycle_complete, NULL);

    /* Configure and start polling task with config from NVS */
    yrm100_poll_config_t poll_config = {
        .poll_interval_ms = rfid_cfg.poll_interval_ms,
        .rf_power_dbm = rfid_cfg.rf_power_dbm,
        .filter_saturday_only = false,  /* Report all tags so non-Saturday still logged */
    };

    ret = yrm100_start_polling_task(&poll_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start polling task: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "RFID polling started (interval=%dms, power=%ddBm)",
             poll_config.poll_interval_ms, poll_config.rf_power_dbm);

    return ESP_OK;
}

/*******************************************************************************
 * Main Application
 ******************************************************************************/

void app_main(void)
{
    esp_err_t ret;

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Saturday Vinyl Hub Firmware v%s", FIRMWARE_VERSION);
    ESP_LOGI(TAG, "  Phase 3: Now Playing Logic");
    ESP_LOGI(TAG, "===========================================");

    /* Log chip info */
    esp_chip_info_t chip_info;
    esp_chip_info(&chip_info);
    ESP_LOGI(TAG, "ESP32-C6 with %d CPU core(s), WiFi%s%s%s",
             chip_info.cores,
             (chip_info.features & CHIP_FEATURE_BT) ? "/BT" : "",
             (chip_info.features & CHIP_FEATURE_BLE) ? "/BLE" : "",
             (chip_info.features & CHIP_FEATURE_IEEE802154) ? "/802.15.4" : "");
    ESP_LOGI(TAG, "Silicon revision %d", chip_info.revision);

    /*
     * Initialize NVS - required for Wi-Fi and config storage
     */
    ESP_LOGI(TAG, "Initializing NVS...");
    ESP_ERROR_CHECK(nvs_init());
    ESP_LOGI(TAG, "NVS initialized");

    /*
     * Create default event loop - required for Now Playing events (Phase 3)
     */
    ESP_LOGI(TAG, "Creating default event loop...");
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        /* ESP_ERR_INVALID_STATE means it's already created, which is fine */
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Event loop ready");
    }

    /*
     * Initialize Configuration Store (Phase 3)
     */
    ESP_LOGI(TAG, "Initializing config store...");
    ret = config_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Config init warning: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Config store initialized");
    }

    /*
     * Initialize LED Manager (Task 1.1)
     * PWM-based RGB LED control with patterns
     */
    ESP_LOGI(TAG, "Initializing LED manager...");
    ret = led_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "LED init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "LED manager initialized");
        /* Start with white pulse to indicate booting */
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
    }

    /*
     * Initialize Button Handler (Task 1.2)
     * Debounced button with press duration detection
     */
    ESP_LOGI(TAG, "Initializing button handler...");
    ret = button_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Button init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Button handler initialized");
        button_register_callback(on_button_press);
    }

    /*
     * Initialize RFID Driver (Task 1.3)
     * UART communication with YRM100 module
     */
    ESP_LOGI(TAG, "Initializing RFID driver...");
    ret = yrm100_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "RFID init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "RFID driver initialized");
    }

    /* Short delay before starting main operation */
    vTaskDelay(pdMS_TO_TICKS(1000));

    /* Switch to dim green solid to indicate idle (ready, no tag) */
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
    led_set_brightness(16);  /* Very dim for idle state */

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Initialization complete!");
    ESP_LOGI(TAG, "  - Place record on turntable for Now Playing");
    ESP_LOGI(TAG, "  - Press button to change LED color");
    ESP_LOGI(TAG, "  - Hold 3-5s for long press demo");
    ESP_LOGI(TAG, "  - Hold >10s for factory reset demo");
    ESP_LOGI(TAG, "===========================================");

    /* Start RFID polling with Now Playing integration (Phase 2 + 3) */
    ret = start_rfid_polling();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "RFID/Now Playing not started - continuing without RFID");
    }

    /* Main loop - periodic health check and stats */
    uint32_t loop_count = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(10000));
        loop_count++;

        /* Periodic health check */
        ESP_LOGI(TAG, "Health: heap=%lu bytes, uptime=%lus",
                 (unsigned long)esp_get_free_heap_size(),
                 (unsigned long)(loop_count * 10));

        /* RFID and Now Playing stats every minute */
        if (loop_count % 6 == 0 && yrm100_is_polling_task_running()) {
            uint32_t polls, tags, saturday;
            yrm100_get_poll_stats(&polls, &tags, &saturday);
            ESP_LOGI(TAG, "RFID stats: polls=%lu, tags=%lu, saturday=%lu",
                     (unsigned long)polls, (unsigned long)tags,
                     (unsigned long)saturday);

            /* Now Playing status */
            now_playing_status_t np_status;
            if (now_playing_get_status(&np_status) == ESP_OK) {
                ESP_LOGI(TAG, "Now Playing: state=%s, placed=%lu, removed=%lu",
                         now_playing_state_to_string(np_status.state),
                         (unsigned long)np_status.total_placed_events,
                         (unsigned long)np_status.total_removed_events);
            }
        }
    }
}
