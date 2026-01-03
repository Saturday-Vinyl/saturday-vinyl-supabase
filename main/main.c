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
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_chip_info.h"
#include "nvs_flash.h"

#include "app_config.h"
#include "led_manager.h"
#include "button_handler.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"

static const char *TAG = "SV_HUB";

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
 * RFID Tag Callback (Phase 2)
 ******************************************************************************/

/**
 * @brief Callback invoked when a tag is detected by the polling task
 *
 * This callback runs in the context of the RFID polling task, so it
 * should be quick and non-blocking.
 */
static void on_tag_detected(const rfid_tag_t *tag, void *user_data)
{
    char epc_str[25];
    rfid_epc_to_hex_string(tag->epc, tag->epc_len, epc_str, sizeof(epc_str));

    if (tag->is_saturday_tag) {
        ESP_LOGI(TAG, "Saturday tag detected: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));
        led_flash(LED_COLOR_GREEN, 150);
    } else {
        ESP_LOGI(TAG, "Non-Saturday tag detected: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));
        led_flash(LED_COLOR_YELLOW, 150);
    }
}

/*******************************************************************************
 * RFID Initialization (Phase 2)
 ******************************************************************************/

/**
 * @brief Initialize and start RFID polling
 *
 * Validates communication with the RFID module, then starts the
 * background polling task which will invoke callbacks on tag detection.
 */
static esp_err_t start_rfid_polling(void)
{
    ESP_LOGI(TAG, "Initializing RFID subsystem...");

    /* Enable the RFID module */
    yrm100_enable(true);
    vTaskDelay(pdMS_TO_TICKS(500));  /* Extra settling time */

    /* Try to get firmware version to verify communication */
    char version[32] = {0};
    esp_err_t ret = yrm100_get_firmware_version(version, sizeof(version));

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

    /* Register callback for tag detection */
    yrm100_register_tag_callback(on_tag_detected, NULL);

    /* Configure and start polling task */
    yrm100_poll_config_t config = {
        .poll_interval_ms = DEFAULT_POLL_INTERVAL_MS,
        .rf_power_dbm = DEFAULT_RF_POWER_DBM,
        .filter_saturday_only = false,  /* Report all tags for debugging */
    };

    ret = yrm100_start_polling_task(&config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start polling task: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "RFID polling started (interval=%dms, power=%ddBm)",
             config.poll_interval_ms, config.rf_power_dbm);

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
    ESP_LOGI(TAG, "  Phase 2: RFID Detection");
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

    /* Switch to green solid to indicate ready */
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
    led_set_brightness(64);  /* Dim to 25% for normal operation */

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Initialization complete!");
    ESP_LOGI(TAG, "  - Press button to change LED color");
    ESP_LOGI(TAG, "  - Hold 3-5s for long press demo");
    ESP_LOGI(TAG, "  - Hold >10s for factory reset demo");
    ESP_LOGI(TAG, "  - RFID polling active");
    ESP_LOGI(TAG, "===========================================");

    /* Start RFID polling (Phase 2) */
    ret = start_rfid_polling();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "RFID polling not started - continuing without RFID");
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

        /* RFID polling stats every minute */
        if (loop_count % 6 == 0 && yrm100_is_polling_task_running()) {
            uint32_t polls, tags, saturday;
            yrm100_get_poll_stats(&polls, &tags, &saturday);
            ESP_LOGI(TAG, "RFID stats: polls=%lu, tags=%lu, saturday=%lu",
                     (unsigned long)polls, (unsigned long)tags,
                     (unsigned long)saturday);
        }
    }
}
