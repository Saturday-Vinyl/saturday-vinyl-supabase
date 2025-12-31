/**
 * @file button_handler.c
 * @brief Button input handling implementation
 *
 * TODO: Implement in Phase 1
 * This is a placeholder that will be replaced with full GPIO interrupt implementation.
 */

#include "button_handler.h"
#include "esp_log.h"

static const char *TAG = "BUTTON";

static button_callback_t s_callback = NULL;

esp_err_t button_init(void)
{
    ESP_LOGI(TAG, "Button handler initialized (placeholder)");
    return ESP_OK;
}

void button_register_callback(button_callback_t callback)
{
    s_callback = callback;
    ESP_LOGI(TAG, "Button callback registered");
}

bool button_is_pressed(void)
{
    return false;
}

uint32_t button_get_press_duration(void)
{
    return 0;
}
