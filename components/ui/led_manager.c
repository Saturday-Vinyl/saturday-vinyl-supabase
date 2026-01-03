/**
 * @file led_manager.c
 * @brief RGB LED control implementation using WS2812 addressable LED
 *
 * Uses the ESP32-C6 RMT peripheral via the led_strip driver to control
 * the onboard WS2812 addressable RGB LED on the DevKitC-1 board.
 *
 * Hardware Notes:
 * - ESP32-C6-DevKitC-1 has onboard WS2812 on GPIO8
 * - Single addressable LED, controlled via RMT peripheral
 * - Protocol: 800kHz single-wire (NeoPixel compatible)
 */

#include "led_manager.h"
#include "led_strip.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "LED_MGR";

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/* WS2812 LED on GPIO8 (onboard DevKitC-1) */
#define LED_STRIP_GPIO          8
#define LED_STRIP_NUM_LEDS      1
#define LED_STRIP_RMT_RES_HZ    (10 * 1000 * 1000)  /* 10 MHz resolution */

/* Pattern task configuration */
#define LED_TASK_STACK_SIZE     2048
#define LED_TASK_PRIORITY       2
#define LED_PATTERN_TICK_MS     20  /* Update interval for smooth patterns */

/*******************************************************************************
 * Color Preset Definitions (RGB values 0-255)
 ******************************************************************************/

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb_t;

static const rgb_t COLOR_PRESETS[] = {
    [LED_COLOR_OFF]     = {0, 0, 0},
    [LED_COLOR_RED]     = {255, 0, 0},
    [LED_COLOR_GREEN]   = {0, 255, 0},
    [LED_COLOR_BLUE]    = {0, 0, 255},
    [LED_COLOR_YELLOW]  = {255, 255, 0},
    [LED_COLOR_CYAN]    = {0, 255, 255},
    [LED_COLOR_MAGENTA] = {255, 0, 255},
    [LED_COLOR_WHITE]   = {255, 255, 255},
    [LED_COLOR_ORANGE]  = {255, 128, 0},
};

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    /* LED strip handle */
    led_strip_handle_t strip;

    /* Current color and brightness */
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t brightness;  /* 0-255, applied as multiplier */

    /* Pattern state */
    led_pattern_t pattern;
    uint16_t period_ms;

    /* Pattern task */
    TaskHandle_t pattern_task_handle;
    volatile bool task_running;
    SemaphoreHandle_t mutex;

    /* Initialized flag */
    bool initialized;
} led_state_t;

static led_state_t s_led = {
    .strip = NULL,
    .r = 0,
    .g = 0,
    .b = 0,
    .brightness = 255,
    .pattern = LED_PATTERN_SOLID,
    .period_ms = 1000,
    .pattern_task_handle = NULL,
    .task_running = false,
    .mutex = NULL,
    .initialized = false,
};

/*******************************************************************************
 * Internal Functions
 ******************************************************************************/

/* Mutex for RMT access - prevents concurrent led_strip_refresh calls */
static SemaphoreHandle_t s_rmt_mutex = NULL;

/**
 * @brief Apply brightness scaling and set the WS2812 LED color
 *
 * Thread-safe: Uses mutex to prevent concurrent RMT access which can
 * cause "channel not in init state" errors.
 */
static void led_apply_color(uint8_t r, uint8_t g, uint8_t b)
{
    if (s_led.strip == NULL) {
        return;
    }

    /* Apply brightness scaling */
    uint32_t br = (r * s_led.brightness) / 255;
    uint32_t bg = (g * s_led.brightness) / 255;
    uint32_t bb = (b * s_led.brightness) / 255;

    /* Protect RMT access with mutex to prevent concurrent refresh calls */
    if (s_rmt_mutex != NULL && xSemaphoreTake(s_rmt_mutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        led_strip_set_pixel(s_led.strip, 0, br, bg, bb);
        led_strip_refresh(s_led.strip);
        xSemaphoreGive(s_rmt_mutex);
    }
}

/**
 * @brief Calculate pulse brightness using sine-like curve
 * @param phase 0-255 representing 0-360 degrees
 * @return brightness multiplier 0-255
 */
static uint8_t led_pulse_curve(uint8_t phase)
{
    /* Simple raised cosine approximation for smooth pulsing */
    int32_t x = phase;
    if (x > 128) {
        x = 256 - x;
    }
    /* Quadratic approximation of sine for 0-90 degrees */
    int32_t result = (x * x * 255) / (128 * 128);
    return (uint8_t)result;
}

/**
 * @brief Pattern generation task
 */
static void led_pattern_task(void *arg)
{
    uint32_t tick = 0;

    while (s_led.task_running) {
        if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
            uint16_t period = s_led.period_ms;
            led_pattern_t pattern = s_led.pattern;
            uint8_t r = s_led.r;
            uint8_t g = s_led.g;
            uint8_t b = s_led.b;
            xSemaphoreGive(s_led.mutex);

            switch (pattern) {
                case LED_PATTERN_SOLID:
                    led_apply_color(r, g, b);
                    vTaskDelay(pdMS_TO_TICKS(100));  /* Low update rate for solid */
                    break;

                case LED_PATTERN_BLINK_SLOW:
                case LED_PATTERN_BLINK_FAST: {
                    /* Calculate on/off based on tick */
                    uint32_t half_period = period / 2;
                    uint32_t phase = tick % period;
                    if (phase < half_period) {
                        led_apply_color(r, g, b);
                    } else {
                        led_apply_color(0, 0, 0);
                    }
                    vTaskDelay(pdMS_TO_TICKS(LED_PATTERN_TICK_MS));
                    tick += LED_PATTERN_TICK_MS;
                    break;
                }

                case LED_PATTERN_PULSE: {
                    /* Calculate phase within period (0-255) */
                    uint32_t phase = (tick * 256) / period;
                    phase = phase & 0xFF;
                    uint8_t intensity = led_pulse_curve((uint8_t)phase);

                    /* Apply intensity to color */
                    uint8_t pr = (r * intensity) / 255;
                    uint8_t pg = (g * intensity) / 255;
                    uint8_t pb = (b * intensity) / 255;
                    led_apply_color(pr, pg, pb);

                    vTaskDelay(pdMS_TO_TICKS(LED_PATTERN_TICK_MS));
                    tick += LED_PATTERN_TICK_MS;
                    if (tick >= period) tick = 0;
                    break;
                }

                case LED_PATTERN_FLASH:
                    /* Flash is handled by led_flash(), not the pattern task */
                    led_apply_color(0, 0, 0);
                    vTaskDelay(pdMS_TO_TICKS(100));
                    break;

                default:
                    vTaskDelay(pdMS_TO_TICKS(100));
                    break;
            }
        } else {
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }

    vTaskDelete(NULL);
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t led_init(void)
{
    if (s_led.initialized) {
        ESP_LOGW(TAG, "LED manager already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing LED manager (WS2812 on GPIO%d)", LED_STRIP_GPIO);

    /* Create mutex for thread-safe access */
    s_led.mutex = xSemaphoreCreateMutex();
    if (s_led.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Create mutex for RMT access (prevents concurrent led_strip_refresh) */
    s_rmt_mutex = xSemaphoreCreateMutex();
    if (s_rmt_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create RMT mutex");
        vSemaphoreDelete(s_led.mutex);
        s_led.mutex = NULL;
        return ESP_ERR_NO_MEM;
    }

    /* Configure LED strip */
    led_strip_config_t strip_config = {
        .strip_gpio_num = LED_STRIP_GPIO,
        .max_leds = LED_STRIP_NUM_LEDS,
        .led_model = LED_MODEL_WS2812,
        .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_GRB,
        .flags = {
            .invert_out = false,
        },
    };

    led_strip_rmt_config_t rmt_config = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .resolution_hz = LED_STRIP_RMT_RES_HZ,
        .mem_block_symbols = 64,
        .flags = {
            .with_dma = false,
        },
    };

    esp_err_t ret = led_strip_new_rmt_device(&strip_config, &rmt_config, &s_led.strip);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create LED strip: %s", esp_err_to_name(ret));
        vSemaphoreDelete(s_led.mutex);
        s_led.mutex = NULL;
        return ret;
    }

    /* Clear LED initially */
    led_strip_clear(s_led.strip);

    /* Start pattern task */
    s_led.task_running = true;
    BaseType_t task_ret = xTaskCreate(
        led_pattern_task,
        "led_pattern",
        LED_TASK_STACK_SIZE,
        NULL,
        LED_TASK_PRIORITY,
        &s_led.pattern_task_handle
    );
    if (task_ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create pattern task");
        s_led.task_running = false;
        led_strip_del(s_led.strip);
        s_led.strip = NULL;
        vSemaphoreDelete(s_led.mutex);
        s_led.mutex = NULL;
        return ESP_ERR_NO_MEM;
    }

    s_led.initialized = true;
    ESP_LOGI(TAG, "LED manager initialized successfully");

    return ESP_OK;
}

void led_set_color(uint8_t r, uint8_t g, uint8_t b)
{
    if (!s_led.initialized) {
        ESP_LOGW(TAG, "LED manager not initialized");
        return;
    }

    if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        s_led.r = r;
        s_led.g = g;
        s_led.b = b;

        /* If solid pattern, apply immediately */
        if (s_led.pattern == LED_PATTERN_SOLID) {
            led_apply_color(r, g, b);
        }
        xSemaphoreGive(s_led.mutex);
    }

    ESP_LOGD(TAG, "Set color: R=%d G=%d B=%d", r, g, b);
}

void led_set_color_preset(led_color_preset_t color)
{
    if (color >= sizeof(COLOR_PRESETS) / sizeof(COLOR_PRESETS[0])) {
        ESP_LOGW(TAG, "Invalid color preset: %d", color);
        return;
    }

    const rgb_t *preset = &COLOR_PRESETS[color];
    led_set_color(preset->r, preset->g, preset->b);
}

void led_set_brightness(uint8_t brightness)
{
    if (!s_led.initialized) {
        ESP_LOGW(TAG, "LED manager not initialized");
        return;
    }

    if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        s_led.brightness = brightness;

        /* If solid pattern, apply immediately */
        if (s_led.pattern == LED_PATTERN_SOLID) {
            led_apply_color(s_led.r, s_led.g, s_led.b);
        }
        xSemaphoreGive(s_led.mutex);
    }

    ESP_LOGD(TAG, "Set brightness: %d", brightness);
}

void led_set_pattern(led_pattern_t pattern, uint16_t period_ms)
{
    if (!s_led.initialized) {
        ESP_LOGW(TAG, "LED manager not initialized");
        return;
    }

    /* Validate period */
    if (period_ms == 0) {
        period_ms = 1000;  /* Default to 1 second */
    }

    /* Set appropriate period for preset patterns */
    if (pattern == LED_PATTERN_BLINK_SLOW && period_ms == 1000) {
        period_ms = 1000;  /* 1Hz = 1s period */
    } else if (pattern == LED_PATTERN_BLINK_FAST && period_ms == 1000) {
        period_ms = 500;   /* 2Hz = 0.5s period */
    }

    if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        s_led.pattern = pattern;
        s_led.period_ms = period_ms;
        xSemaphoreGive(s_led.mutex);
    }

    ESP_LOGD(TAG, "Set pattern: %d, period: %d ms", pattern, period_ms);
}

void led_set_state(led_color_preset_t color, led_pattern_t pattern, uint16_t period_ms)
{
    led_set_color_preset(color);
    led_set_pattern(pattern, period_ms);
}

void led_off(void)
{
    led_set_color(0, 0, 0);
    led_set_pattern(LED_PATTERN_SOLID, 0);
}

void led_flash(led_color_preset_t color, uint16_t duration_ms)
{
    if (!s_led.initialized) {
        ESP_LOGW(TAG, "LED manager not initialized");
        return;
    }

    ESP_LOGD(TAG, "Flash color %d for %d ms", color, duration_ms);

    const rgb_t *preset = &COLOR_PRESETS[color];

    /* Save current state */
    uint8_t saved_r, saved_g, saved_b;
    led_pattern_t saved_pattern;

    if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        saved_r = s_led.r;
        saved_g = s_led.g;
        saved_b = s_led.b;
        saved_pattern = s_led.pattern;

        /* Flash the color */
        s_led.pattern = LED_PATTERN_SOLID;
        xSemaphoreGive(s_led.mutex);
    } else {
        return;
    }

    led_apply_color(preset->r, preset->g, preset->b);
    vTaskDelay(pdMS_TO_TICKS(duration_ms));

    /* Restore previous state */
    if (xSemaphoreTake(s_led.mutex, pdMS_TO_TICKS(100)) == pdTRUE) {
        s_led.r = saved_r;
        s_led.g = saved_g;
        s_led.b = saved_b;
        s_led.pattern = saved_pattern;

        if (saved_pattern == LED_PATTERN_SOLID) {
            led_apply_color(saved_r, saved_g, saved_b);
        }
        xSemaphoreGive(s_led.mutex);
    }
}
