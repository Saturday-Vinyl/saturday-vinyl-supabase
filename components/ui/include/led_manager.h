/**
 * @file led_manager.h
 * @brief RGB LED control interface for Saturday Vinyl Hub
 *
 * Provides functions for controlling the RGB status LED including
 * color setting, brightness control, and pattern generation.
 */

#ifndef LED_MANAGER_H
#define LED_MANAGER_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief LED pattern types
 */
typedef enum {
    LED_PATTERN_SOLID,      /**< Solid color, no blinking */
    LED_PATTERN_BLINK_SLOW, /**< Slow blink (1Hz) */
    LED_PATTERN_BLINK_FAST, /**< Fast blink (2Hz) */
    LED_PATTERN_PULSE,      /**< Smooth pulsing effect */
    LED_PATTERN_FLASH,      /**< Brief flash then off */
} led_pattern_t;

/**
 * @brief Predefined LED colors for common states
 */
typedef enum {
    LED_COLOR_OFF,
    LED_COLOR_RED,
    LED_COLOR_GREEN,
    LED_COLOR_BLUE,
    LED_COLOR_YELLOW,
    LED_COLOR_CYAN,
    LED_COLOR_MAGENTA,
    LED_COLOR_WHITE,
    LED_COLOR_ORANGE,
} led_color_preset_t;

/**
 * @brief Initialize the LED manager
 *
 * Configures PWM channels for RGB LED control.
 * Must be called before any other LED functions.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t led_init(void);

/**
 * @brief Set LED color using RGB values
 *
 * @param r Red component (0-255)
 * @param g Green component (0-255)
 * @param b Blue component (0-255)
 */
void led_set_color(uint8_t r, uint8_t g, uint8_t b);

/**
 * @brief Set LED using a color preset
 *
 * @param color Predefined color from led_color_preset_t
 */
void led_set_color_preset(led_color_preset_t color);

/**
 * @brief Set overall LED brightness
 *
 * @param brightness Brightness level (0-255)
 */
void led_set_brightness(uint8_t brightness);

/**
 * @brief Set LED pattern
 *
 * @param pattern Pattern type from led_pattern_t
 * @param period_ms Pattern period in milliseconds (for blink/pulse)
 */
void led_set_pattern(led_pattern_t pattern, uint16_t period_ms);

/**
 * @brief Convenience function to set color, pattern, and start
 *
 * @param color Color preset
 * @param pattern Pattern type
 * @param period_ms Pattern period
 */
void led_set_state(led_color_preset_t color, led_pattern_t pattern, uint16_t period_ms);

/**
 * @brief Turn off the LED
 */
void led_off(void);

/**
 * @brief Flash the LED briefly (for notifications)
 *
 * @param color Color preset to flash
 * @param duration_ms How long to flash
 */
void led_flash(led_color_preset_t color, uint16_t duration_ms);

#ifdef __cplusplus
}
#endif

#endif /* LED_MANAGER_H */
