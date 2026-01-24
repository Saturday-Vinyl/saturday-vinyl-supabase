/**
 * @file watchdog_manager.h
 * @brief Task watchdog manager for production reliability
 *
 * Provides centralized management of task watchdogs to detect hung tasks
 * and enable graceful recovery or system reset.
 *
 * Phase PROD-2.1: Watchdogs
 */

#ifndef WATCHDOG_MANAGER_H
#define WATCHDOG_MANAGER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief Maximum number of tasks that can be monitored
 */
#define WATCHDOG_MAX_TASKS      8

/**
 * @brief Default watchdog timeout in seconds
 */
#define WATCHDOG_DEFAULT_TIMEOUT_SEC    30

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Watchdog task IDs for registered critical tasks
 */
typedef enum {
    WATCHDOG_TASK_MAIN = 0,         /**< Main application task */
    WATCHDOG_TASK_RFID,             /**< RFID polling task */
    WATCHDOG_TASK_CLOUD,            /**< Cloud sync/event reporter task */
    WATCHDOG_TASK_H2_COMM,          /**< H2 communication task */
    WATCHDOG_TASK_WIFI,             /**< WiFi manager task */
    WATCHDOG_TASK_SERVICE_MODE,     /**< Service mode task */
    WATCHDOG_TASK_OTA,              /**< OTA update task */
    WATCHDOG_TASK_USER,             /**< User-defined task */
} watchdog_task_id_t;

/**
 * @brief Task watchdog status
 */
typedef struct {
    const char *name;           /**< Task name */
    bool registered;            /**< Task is registered */
    bool enabled;               /**< Watchdog is enabled for this task */
    uint32_t timeout_sec;       /**< Timeout in seconds */
    uint32_t last_feed_time;    /**< Last time watchdog was fed (tick count) */
    uint32_t feed_count;        /**< Total feed count */
    uint32_t timeout_count;     /**< Number of timeouts detected */
} watchdog_task_status_t;

/**
 * @brief Watchdog manager status
 */
typedef struct {
    bool initialized;                           /**< Manager is initialized */
    bool enabled;                               /**< Global watchdog enabled */
    uint32_t registered_count;                  /**< Number of registered tasks */
    uint32_t total_timeouts;                    /**< Total timeouts across all tasks */
    uint32_t last_reset_reason;                 /**< Last reset reason (if available) */
    watchdog_task_status_t tasks[WATCHDOG_MAX_TASKS];
} watchdog_status_t;

/**
 * @brief Callback for task timeout (before reset)
 */
typedef void (*watchdog_timeout_cb_t)(watchdog_task_id_t task_id, const char *task_name);

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the watchdog manager
 *
 * Sets up the ESP-IDF task watchdog and prepares for task registration.
 *
 * @param timeout_sec Global watchdog timeout in seconds (0 for default)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t watchdog_manager_init(uint32_t timeout_sec);

/**
 * @brief Deinitialize the watchdog manager
 *
 * @return ESP_OK on success
 */
esp_err_t watchdog_manager_deinit(void);

/**
 * @brief Register a task for watchdog monitoring
 *
 * The task must call watchdog_feed() periodically to prevent timeout.
 *
 * @param task_id Task identifier
 * @param task_handle FreeRTOS task handle (NULL to use current task)
 * @param name Task name for logging
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t watchdog_register_task(watchdog_task_id_t task_id,
                                  TaskHandle_t task_handle,
                                  const char *name);

/**
 * @brief Unregister a task from watchdog monitoring
 *
 * @param task_id Task identifier
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t watchdog_unregister_task(watchdog_task_id_t task_id);

/**
 * @brief Feed the watchdog for the current task
 *
 * Must be called periodically by registered tasks to prevent timeout.
 * Call from the task that was registered.
 *
 * @return ESP_OK on success
 */
esp_err_t watchdog_feed(void);

/**
 * @brief Feed the watchdog for a specific task
 *
 * @param task_id Task identifier
 * @return ESP_OK on success
 */
esp_err_t watchdog_feed_task(watchdog_task_id_t task_id);

/**
 * @brief Enable watchdog for a specific task
 *
 * @param task_id Task identifier
 * @param enabled true to enable, false to disable
 * @return ESP_OK on success
 */
esp_err_t watchdog_set_task_enabled(watchdog_task_id_t task_id, bool enabled);

/**
 * @brief Enable or disable the global watchdog
 *
 * @param enabled true to enable, false to disable
 * @return ESP_OK on success
 */
esp_err_t watchdog_set_enabled(bool enabled);

/**
 * @brief Check if watchdog is enabled
 *
 * @return true if global watchdog is enabled
 */
bool watchdog_is_enabled(void);

/**
 * @brief Get watchdog status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t watchdog_get_status(watchdog_status_t *status);

/**
 * @brief Set timeout callback
 *
 * Called when a task timeout is detected (before system reset).
 * Use for logging or cleanup.
 *
 * @param callback Callback function (NULL to disable)
 * @return ESP_OK on success
 */
esp_err_t watchdog_set_timeout_callback(watchdog_timeout_cb_t callback);

/**
 * @brief Trigger a watchdog reset manually
 *
 * Forces a system reset via the watchdog.
 */
void watchdog_trigger_reset(void);

/**
 * @brief Check if last boot was due to watchdog reset
 *
 * @return true if last reset was watchdog-triggered
 */
bool watchdog_was_reset_by_watchdog(void);

/*******************************************************************************
 * Heap Monitoring (PROD-2.3)
 ******************************************************************************/

/**
 * @brief Default low memory threshold in bytes (32KB)
 */
#define HEAP_LOW_THRESHOLD_DEFAULT      (32 * 1024)

/**
 * @brief Critical memory threshold in bytes (16KB)
 */
#define HEAP_CRITICAL_THRESHOLD_DEFAULT (16 * 1024)

/**
 * @brief Heap status structure
 */
typedef struct {
    uint32_t free_heap;         /**< Current free heap in bytes */
    uint32_t min_free_heap;     /**< Minimum free heap since boot */
    uint32_t largest_free_block;/**< Largest contiguous free block */
    uint32_t low_threshold;     /**< Low memory threshold */
    uint32_t critical_threshold;/**< Critical memory threshold */
    bool is_low;                /**< True if below low threshold */
    bool is_critical;           /**< True if below critical threshold */
    uint32_t low_warning_count; /**< Times heap dropped below low threshold */
} heap_status_t;

/**
 * @brief Initialize heap monitoring
 *
 * @param low_threshold Low memory warning threshold (0 for default)
 * @param critical_threshold Critical memory threshold (0 for default)
 * @return ESP_OK on success
 */
esp_err_t heap_monitor_init(uint32_t low_threshold, uint32_t critical_threshold);

/**
 * @brief Check heap status and update watermarks
 *
 * Call periodically (e.g., from main loop) to track heap usage.
 *
 * @param status Output heap status (can be NULL)
 * @return ESP_OK on success, ESP_ERR_NO_MEM if critically low
 */
esp_err_t heap_monitor_check(heap_status_t *status);

/**
 * @brief Get current heap status
 *
 * @param status Output heap status
 * @return ESP_OK on success
 */
esp_err_t heap_monitor_get_status(heap_status_t *status);

/**
 * @brief Get minimum free heap seen since boot
 *
 * @return Minimum free heap in bytes
 */
uint32_t heap_monitor_get_min_free(void);

/**
 * @brief Reset minimum heap watermark to current value
 *
 * @return ESP_OK on success
 */
esp_err_t heap_monitor_reset_watermark(void);

#ifdef __cplusplus
}
#endif

#endif /* WATCHDOG_MANAGER_H */
