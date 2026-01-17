/**
 * @file button_handler.c
 * @brief Button input handling with debouncing and press duration detection
 *
 * Uses GPIO interrupt for edge detection with software debouncing.
 * Detects short press, long press (3-5s), and factory reset (>10s).
 *
 * Hardware Notes:
 * - ESP32-S3: GPIO0 (BOOT button) with internal pull-up
 * - Active low (pressed = 0)
 * - Debounce time: 50ms
 */

#include "button_handler.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "app_config.h"

static const char *TAG = "BUTTON";

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/* Pin definition from app_config.h */
#define BUTTON_GPIO             PIN_BUTTON

/* Timing thresholds in milliseconds */
#define BUTTON_DEBOUNCE_MS      50
#define BUTTON_SHORT_MAX_MS     500
#define BUTTON_LONG_MIN_MS      3000
#define BUTTON_LONG_MAX_MS      5000
#define BUTTON_FACTORY_MIN_MS   10000

/* Task configuration */
#define BUTTON_TASK_STACK_SIZE  4096  /* Needs room for BLE init in callback */
#define BUTTON_TASK_PRIORITY    3

/* Polling interval while button is held (for duration feedback) */
#define BUTTON_POLL_INTERVAL_MS 100

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef enum {
    BUTTON_STATE_IDLE,
    BUTTON_STATE_DEBOUNCING,
    BUTTON_STATE_PRESSED,
    BUTTON_STATE_RELEASED,
} button_internal_state_t;

typedef struct {
    /* State machine */
    button_internal_state_t state;
    int64_t press_start_time;
    int64_t debounce_start_time;

    /* Callback */
    button_callback_t callback;

    /* Task */
    TaskHandle_t task_handle;
    volatile bool task_running;

    /* ISR event queue */
    QueueHandle_t event_queue;

    /* Initialized flag */
    bool initialized;
} button_state_t;

static button_state_t s_button = {
    .state = BUTTON_STATE_IDLE,
    .press_start_time = 0,
    .debounce_start_time = 0,
    .callback = NULL,
    .task_handle = NULL,
    .task_running = false,
    .event_queue = NULL,
    .initialized = false,
};

/* Event types for ISR to task communication */
typedef enum {
    BUTTON_ISR_EVENT_PRESSED,
    BUTTON_ISR_EVENT_RELEASED,
} button_isr_event_t;

/*******************************************************************************
 * Internal Functions
 ******************************************************************************/

/**
 * @brief Get current time in milliseconds
 */
static inline int64_t get_time_ms(void)
{
    return esp_timer_get_time() / 1000;
}

/**
 * @brief Read button GPIO state (returns true if pressed)
 */
static inline bool button_read_gpio(void)
{
    return gpio_get_level(BUTTON_GPIO) == 0;  /* Active low */
}

/**
 * @brief Classify press duration into press type
 */
static button_press_t classify_press_duration(uint32_t duration_ms)
{
    if (duration_ms >= BUTTON_FACTORY_MIN_MS) {
        return BUTTON_PRESS_FACTORY;
    } else if (duration_ms >= BUTTON_LONG_MIN_MS) {
        return BUTTON_PRESS_LONG;
    } else {
        return BUTTON_PRESS_SHORT;
    }
}

/**
 * @brief GPIO ISR handler
 */
static void IRAM_ATTR button_isr_handler(void *arg)
{
    button_isr_event_t event;

    if (gpio_get_level(BUTTON_GPIO) == 0) {
        event = BUTTON_ISR_EVENT_PRESSED;
    } else {
        event = BUTTON_ISR_EVENT_RELEASED;
    }

    xQueueSendFromISR(s_button.event_queue, &event, NULL);
}

/**
 * @brief Button processing task
 */
static void button_task(void *arg)
{
    button_isr_event_t event;
    int64_t current_time;
    uint32_t duration_ms;

    while (s_button.task_running) {
        /* Check for ISR events with timeout */
        if (xQueueReceive(s_button.event_queue, &event, pdMS_TO_TICKS(BUTTON_POLL_INTERVAL_MS)) == pdTRUE) {
            current_time = get_time_ms();

            switch (event) {
                case BUTTON_ISR_EVENT_PRESSED:
                    if (s_button.state == BUTTON_STATE_IDLE) {
                        /* Start debounce */
                        s_button.state = BUTTON_STATE_DEBOUNCING;
                        s_button.debounce_start_time = current_time;
                        ESP_LOGD(TAG, "Button press detected, debouncing...");
                    }
                    break;

                case BUTTON_ISR_EVENT_RELEASED:
                    if (s_button.state == BUTTON_STATE_PRESSED) {
                        /* Calculate press duration */
                        duration_ms = (uint32_t)(current_time - s_button.press_start_time);
                        button_press_t press_type = classify_press_duration(duration_ms);

                        ESP_LOGI(TAG, "Button released after %lu ms (type: %d)",
                                 (unsigned long)duration_ms, press_type);

                        /* Call callback if registered */
                        if (s_button.callback != NULL) {
                            s_button.callback(press_type);
                        }

                        s_button.state = BUTTON_STATE_IDLE;
                    } else if (s_button.state == BUTTON_STATE_DEBOUNCING) {
                        /* Released during debounce - ignore (noise) */
                        s_button.state = BUTTON_STATE_IDLE;
                        ESP_LOGD(TAG, "Press cancelled during debounce");
                    }
                    break;
            }
        }

        /* Handle debounce completion */
        current_time = get_time_ms();
        if (s_button.state == BUTTON_STATE_DEBOUNCING) {
            if ((current_time - s_button.debounce_start_time) >= BUTTON_DEBOUNCE_MS) {
                /* Verify button is still pressed */
                if (button_read_gpio()) {
                    s_button.state = BUTTON_STATE_PRESSED;
                    s_button.press_start_time = s_button.debounce_start_time;
                    ESP_LOGI(TAG, "Button press confirmed");
                } else {
                    /* Button was released during debounce - noise */
                    s_button.state = BUTTON_STATE_IDLE;
                    ESP_LOGD(TAG, "Debounce failed - button not held");
                }
            }
        }

        /* While button is held, provide duration feedback at thresholds */
        if (s_button.state == BUTTON_STATE_PRESSED) {
            duration_ms = (uint32_t)(current_time - s_button.press_start_time);

            /* Log at threshold crossings for debugging */
            static uint32_t last_logged_threshold = 0;
            if (duration_ms >= BUTTON_FACTORY_MIN_MS && last_logged_threshold < BUTTON_FACTORY_MIN_MS) {
                ESP_LOGI(TAG, "Factory reset threshold reached (>%d ms)", BUTTON_FACTORY_MIN_MS);
                last_logged_threshold = BUTTON_FACTORY_MIN_MS;
            } else if (duration_ms >= BUTTON_LONG_MIN_MS && last_logged_threshold < BUTTON_LONG_MIN_MS) {
                ESP_LOGI(TAG, "Long press threshold reached (>%d ms)", BUTTON_LONG_MIN_MS);
                last_logged_threshold = BUTTON_LONG_MIN_MS;
            }

            /* Reset threshold tracking when button is released */
            if (!button_read_gpio()) {
                last_logged_threshold = 0;
            }
        }
    }

    vTaskDelete(NULL);
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t button_init(void)
{
    if (s_button.initialized) {
        ESP_LOGW(TAG, "Button handler already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing button handler");

    /* Create event queue for ISR */
    s_button.event_queue = xQueueCreate(10, sizeof(button_isr_event_t));
    if (s_button.event_queue == NULL) {
        ESP_LOGE(TAG, "Failed to create event queue");
        return ESP_ERR_NO_MEM;
    }

    /* Configure GPIO */
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << BUTTON_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_ANYEDGE,  /* Trigger on both press and release */
    };
    esp_err_t ret = gpio_config(&io_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure GPIO: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Install GPIO ISR service if not already installed */
    ret = gpio_install_isr_service(0);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        /* ESP_ERR_INVALID_STATE means ISR service already installed - that's OK */
        ESP_LOGE(TAG, "Failed to install ISR service: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Add ISR handler for button GPIO */
    ret = gpio_isr_handler_add(BUTTON_GPIO, button_isr_handler, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to add ISR handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start button task */
    s_button.task_running = true;
    BaseType_t task_ret = xTaskCreate(
        button_task,
        "button_task",
        BUTTON_TASK_STACK_SIZE,
        NULL,
        BUTTON_TASK_PRIORITY,
        &s_button.task_handle
    );
    if (task_ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create button task");
        s_button.task_running = false;
        return ESP_ERR_NO_MEM;
    }

    s_button.initialized = true;
    ESP_LOGI(TAG, "Button handler initialized successfully");

    return ESP_OK;
}

void button_register_callback(button_callback_t callback)
{
    s_button.callback = callback;
    ESP_LOGI(TAG, "Button callback %s", callback ? "registered" : "unregistered");
}

bool button_is_pressed(void)
{
    if (!s_button.initialized) {
        return false;
    }
    return button_read_gpio();
}

uint32_t button_get_press_duration(void)
{
    if (!s_button.initialized) {
        return 0;
    }

    if (s_button.state == BUTTON_STATE_PRESSED) {
        int64_t current_time = get_time_ms();
        return (uint32_t)(current_time - s_button.press_start_time);
    }

    return 0;
}
