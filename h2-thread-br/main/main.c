/**
 * @file main.c
 * @brief Saturday Vinyl Hub - ESP32-H2 Thread Border Router Entry Point
 *
 * This is the dedicated Thread co-processor firmware.
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "nvs_flash.h"

#include "app_config.h"

static const char *TAG = "main";

void app_main(void)
{
    ESP_LOGI(TAG, "Saturday Vinyl Hub - H2 Thread BR v%s", FW_VERSION_STRING);
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

    /* TODO: Phase H2-1 - Initialize S3 UART communication interface */

    /* TODO: Phase H2-2 - Initialize Thread Border Router */

    /* TODO: Phase H2-3 - Initialize CoAP server */

    ESP_LOGI(TAG, "Initialization complete - waiting for S3 commands");

    /* Main loop - process S3 commands */
    while (1) {
        /* TODO: Process incoming UART commands from S3 */
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
