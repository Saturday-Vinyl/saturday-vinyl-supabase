/**
 * @file main.c
 * @brief Saturday Vinyl Hub firmware entry point
 *
 * This is the main entry point for the Saturday Hub firmware.
 * It initializes all subsystems and starts the main application loop.
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include "esp_system.h"
#include "nvs_flash.h"

#include "app_config.h"

static const char *TAG = "SV_HUB";

/*******************************************************************************
 * LED Control (Phase 0 - Basic Blink Test)
 ******************************************************************************/

/**
 * @brief Initialize a single LED GPIO for basic blink test
 */
static void led_gpio_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << PIN_LED_R) | (1ULL << PIN_LED_G) | (1ULL << PIN_LED_B),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&io_conf);

    /* Start with LED off (assuming common anode - high = off) */
    gpio_set_level(PIN_LED_R, 1);
    gpio_set_level(PIN_LED_G, 1);
    gpio_set_level(PIN_LED_B, 1);
}

/**
 * @brief Set LED color using basic GPIO (no PWM yet)
 * @param r Red on/off (0 or 1)
 * @param g Green on/off (0 or 1)
 * @param b Blue on/off (0 or 1)
 */
static void led_set_rgb(int r, int g, int b)
{
    /* Assuming common anode LED: 0 = on, 1 = off */
    gpio_set_level(PIN_LED_R, !r);
    gpio_set_level(PIN_LED_G, !g);
    gpio_set_level(PIN_LED_B, !b);
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
 * Main Application
 ******************************************************************************/

void app_main(void)
{
    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Saturday Vinyl Hub Firmware v%s", FIRMWARE_VERSION);
    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "Starting initialization...");

    /* Initialize NVS - required for Wi-Fi and config storage */
    ESP_LOGI(TAG, "Initializing NVS...");
    ESP_ERROR_CHECK(nvs_init());
    ESP_LOGI(TAG, "NVS initialized successfully");

    /* Initialize LED GPIO for blink test */
    ESP_LOGI(TAG, "Initializing LED GPIO...");
    led_gpio_init();
    ESP_LOGI(TAG, "LED GPIO initialized");

    /* Log chip info */
    esp_chip_info_t chip_info;
    esp_chip_info(&chip_info);
    ESP_LOGI(TAG, "ESP32-C6 with %d CPU core(s), WiFi%s%s%s, ",
             chip_info.cores,
             (chip_info.features & CHIP_FEATURE_BT) ? "/BT" : "",
             (chip_info.features & CHIP_FEATURE_BLE) ? "/BLE" : "",
             (chip_info.features & CHIP_FEATURE_IEEE802154) ? "/802.15.4" : "");
    ESP_LOGI(TAG, "Silicon revision %d", chip_info.revision);

    ESP_LOGI(TAG, "Initialization complete. Starting LED blink test...");
    ESP_LOGI(TAG, "LED will cycle: RED -> GREEN -> BLUE -> WHITE -> OFF");

    /* Simple LED blink loop to verify hardware */
    int cycle = 0;
    while (1) {
        cycle++;
        ESP_LOGI(TAG, "Blink cycle %d", cycle);

        /* Red */
        ESP_LOGD(TAG, "LED: Red");
        led_set_rgb(1, 0, 0);
        vTaskDelay(pdMS_TO_TICKS(500));

        /* Green */
        ESP_LOGD(TAG, "LED: Green");
        led_set_rgb(0, 1, 0);
        vTaskDelay(pdMS_TO_TICKS(500));

        /* Blue */
        ESP_LOGD(TAG, "LED: Blue");
        led_set_rgb(0, 0, 1);
        vTaskDelay(pdMS_TO_TICKS(500));

        /* White (all on) */
        ESP_LOGD(TAG, "LED: White");
        led_set_rgb(1, 1, 1);
        vTaskDelay(pdMS_TO_TICKS(500));

        /* Off */
        ESP_LOGD(TAG, "LED: Off");
        led_set_rgb(0, 0, 0);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}
