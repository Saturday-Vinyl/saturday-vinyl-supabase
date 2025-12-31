/**
 * @file button_handler.h
 * @brief Button input handling for Saturday Vinyl Hub
 *
 * Provides debounced button input with press duration detection.
 */

#ifndef BUTTON_HANDLER_H
#define BUTTON_HANDLER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Button press types based on duration
 */
typedef enum {
    BUTTON_PRESS_SHORT,     /**< < 500ms - Reserved for future use */
    BUTTON_PRESS_LONG,      /**< 3-5 seconds - Enter BLE provisioning */
    BUTTON_PRESS_FACTORY,   /**< > 10 seconds - Factory reset */
} button_press_t;

/**
 * @brief Button event callback function type
 *
 * @param press_type Type of button press detected
 */
typedef void (*button_callback_t)(button_press_t press_type);

/**
 * @brief Initialize button handler
 *
 * Configures GPIO with internal pull-up and sets up debouncing.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t button_init(void);

/**
 * @brief Register a callback for button events
 *
 * @param callback Function to call when button press is detected
 */
void button_register_callback(button_callback_t callback);

/**
 * @brief Check if button is currently pressed
 *
 * @return true if button is pressed, false otherwise
 */
bool button_is_pressed(void);

/**
 * @brief Get duration of current press in milliseconds
 *
 * @return Duration in ms if pressed, 0 if not pressed
 */
uint32_t button_get_press_duration(void);

#ifdef __cplusplus
}
#endif

#endif /* BUTTON_HANDLER_H */
