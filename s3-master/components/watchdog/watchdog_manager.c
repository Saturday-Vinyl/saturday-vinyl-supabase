/**
 * @file watchdog_manager.c
 * @brief Task watchdog manager implementation
 *
 * Phase PROD-2.1: Watchdogs
 */

#include "watchdog_manager.h"

#include <string.h>

#include "esp_log.h"
#include "esp_task_wdt.h"
#include "esp_system.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static const char *TAG = "watchdog";

/*******************************************************************************
 * Module State
 ******************************************************************************/

typedef struct {
    TaskHandle_t handle;
    const char *name;
    bool registered;
    bool enabled;
    uint32_t timeout_sec;
    TickType_t last_feed_tick;
    uint32_t feed_count;
    uint32_t timeout_count;
} task_entry_t;

static struct {
    bool initialized;
    bool enabled;
    uint32_t global_timeout_sec;
    SemaphoreHandle_t mutex;
    task_entry_t tasks[WATCHDOG_MAX_TASKS];
    watchdog_timeout_cb_t timeout_callback;
} s_wdt = {0};

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t watchdog_manager_init(uint32_t timeout_sec)
{
    if (s_wdt.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing watchdog manager");

    /* Create mutex */
    s_wdt.mutex = xSemaphoreCreateMutex();
    if (s_wdt.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Set timeout */
    s_wdt.global_timeout_sec = (timeout_sec > 0) ? timeout_sec : WATCHDOG_DEFAULT_TIMEOUT_SEC;

    /* Initialize task watchdog with configured timeout
     * Note: ESP-IDF task watchdog is already initialized by default via sdkconfig.
     * We just need to ensure it's configured correctly. */
    esp_task_wdt_config_t wdt_config = {
        .timeout_ms = s_wdt.global_timeout_sec * 1000,
        .idle_core_mask = 0,  /* Don't watch idle tasks by default */
        .trigger_panic = true,  /* Panic on timeout for debug */
    };

    esp_err_t ret = esp_task_wdt_reconfigure(&wdt_config);
    if (ret != ESP_OK) {
        /* Try to initialize if not already */
        ret = esp_task_wdt_init(&wdt_config);
        if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
            ESP_LOGE(TAG, "Failed to configure task WDT: %s", esp_err_to_name(ret));
            vSemaphoreDelete(s_wdt.mutex);
            return ret;
        }
    }

    /* Clear task entries */
    memset(s_wdt.tasks, 0, sizeof(s_wdt.tasks));

    s_wdt.enabled = true;
    s_wdt.initialized = true;

    ESP_LOGI(TAG, "Watchdog manager initialized (timeout=%lus)",
             (unsigned long)s_wdt.global_timeout_sec);

    /* Check if last reset was due to watchdog */
    if (watchdog_was_reset_by_watchdog()) {
        ESP_LOGW(TAG, "Last reset was caused by watchdog timeout!");
    }

    return ESP_OK;
}

esp_err_t watchdog_manager_deinit(void)
{
    if (!s_wdt.initialized) {
        return ESP_OK;
    }

    /* Unregister all tasks */
    for (int i = 0; i < WATCHDOG_MAX_TASKS; i++) {
        if (s_wdt.tasks[i].registered && s_wdt.tasks[i].handle != NULL) {
            esp_task_wdt_delete(s_wdt.tasks[i].handle);
        }
    }

    if (s_wdt.mutex != NULL) {
        vSemaphoreDelete(s_wdt.mutex);
        s_wdt.mutex = NULL;
    }

    s_wdt.initialized = false;
    ESP_LOGI(TAG, "Watchdog manager deinitialized");

    return ESP_OK;
}

/*******************************************************************************
 * Task Registration
 ******************************************************************************/

esp_err_t watchdog_register_task(watchdog_task_id_t task_id,
                                  TaskHandle_t task_handle,
                                  const char *name)
{
    if (!s_wdt.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (task_id >= WATCHDOG_MAX_TASKS) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Use current task if handle not provided */
    if (task_handle == NULL) {
        task_handle = xTaskGetCurrentTaskHandle();
    }

    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    if (s_wdt.tasks[task_id].registered) {
        ESP_LOGW(TAG, "Task %d already registered, re-registering", task_id);
        /* Unregister first */
        if (s_wdt.tasks[task_id].handle != NULL) {
            esp_task_wdt_delete(s_wdt.tasks[task_id].handle);
        }
    }

    /* Add task to ESP-IDF task watchdog */
    esp_err_t ret = esp_task_wdt_add(task_handle);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to add task to WDT: %s", esp_err_to_name(ret));
        xSemaphoreGive(s_wdt.mutex);
        return ret;
    }

    /* Store task info */
    s_wdt.tasks[task_id].handle = task_handle;
    s_wdt.tasks[task_id].name = name ? name : "unnamed";
    s_wdt.tasks[task_id].registered = true;
    s_wdt.tasks[task_id].enabled = true;
    s_wdt.tasks[task_id].timeout_sec = s_wdt.global_timeout_sec;
    s_wdt.tasks[task_id].last_feed_tick = xTaskGetTickCount();
    s_wdt.tasks[task_id].feed_count = 0;
    s_wdt.tasks[task_id].timeout_count = 0;

    xSemaphoreGive(s_wdt.mutex);

    ESP_LOGI(TAG, "Registered task '%s' (id=%d) for watchdog monitoring",
             s_wdt.tasks[task_id].name, task_id);

    return ESP_OK;
}

esp_err_t watchdog_unregister_task(watchdog_task_id_t task_id)
{
    if (!s_wdt.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (task_id >= WATCHDOG_MAX_TASKS) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    if (!s_wdt.tasks[task_id].registered) {
        xSemaphoreGive(s_wdt.mutex);
        return ESP_ERR_NOT_FOUND;
    }

    /* Remove from ESP-IDF task watchdog */
    if (s_wdt.tasks[task_id].handle != NULL) {
        esp_task_wdt_delete(s_wdt.tasks[task_id].handle);
    }

    ESP_LOGI(TAG, "Unregistered task '%s' (id=%d) from watchdog",
             s_wdt.tasks[task_id].name, task_id);

    s_wdt.tasks[task_id].registered = false;
    s_wdt.tasks[task_id].handle = NULL;

    xSemaphoreGive(s_wdt.mutex);

    return ESP_OK;
}

/*******************************************************************************
 * Watchdog Feeding
 ******************************************************************************/

esp_err_t watchdog_feed(void)
{
    if (!s_wdt.initialized || !s_wdt.enabled) {
        return ESP_OK;
    }

    TaskHandle_t current = xTaskGetCurrentTaskHandle();

    /* Find task in our registry */
    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    for (int i = 0; i < WATCHDOG_MAX_TASKS; i++) {
        if (s_wdt.tasks[i].registered && s_wdt.tasks[i].handle == current) {
            if (s_wdt.tasks[i].enabled) {
                esp_task_wdt_reset();
                s_wdt.tasks[i].last_feed_tick = xTaskGetTickCount();
                s_wdt.tasks[i].feed_count++;
            }
            xSemaphoreGive(s_wdt.mutex);
            return ESP_OK;
        }
    }

    xSemaphoreGive(s_wdt.mutex);

    /* Task not in registry - try to feed anyway (might be registered elsewhere) */
    return esp_task_wdt_reset();
}

esp_err_t watchdog_feed_task(watchdog_task_id_t task_id)
{
    if (!s_wdt.initialized || !s_wdt.enabled) {
        return ESP_OK;
    }

    if (task_id >= WATCHDOG_MAX_TASKS) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    if (!s_wdt.tasks[task_id].registered) {
        xSemaphoreGive(s_wdt.mutex);
        return ESP_ERR_NOT_FOUND;
    }

    if (s_wdt.tasks[task_id].enabled && s_wdt.tasks[task_id].handle != NULL) {
        esp_task_wdt_reset();
        s_wdt.tasks[task_id].last_feed_tick = xTaskGetTickCount();
        s_wdt.tasks[task_id].feed_count++;
    }

    xSemaphoreGive(s_wdt.mutex);

    return ESP_OK;
}

/*******************************************************************************
 * Control
 ******************************************************************************/

esp_err_t watchdog_set_task_enabled(watchdog_task_id_t task_id, bool enabled)
{
    if (!s_wdt.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (task_id >= WATCHDOG_MAX_TASKS) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    if (!s_wdt.tasks[task_id].registered) {
        xSemaphoreGive(s_wdt.mutex);
        return ESP_ERR_NOT_FOUND;
    }

    s_wdt.tasks[task_id].enabled = enabled;

    xSemaphoreGive(s_wdt.mutex);

    ESP_LOGI(TAG, "Task '%s' watchdog %s",
             s_wdt.tasks[task_id].name, enabled ? "enabled" : "disabled");

    return ESP_OK;
}

esp_err_t watchdog_set_enabled(bool enabled)
{
    if (!s_wdt.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    s_wdt.enabled = enabled;
    ESP_LOGI(TAG, "Global watchdog %s", enabled ? "enabled" : "disabled");

    return ESP_OK;
}

bool watchdog_is_enabled(void)
{
    return s_wdt.initialized && s_wdt.enabled;
}

/*******************************************************************************
 * Status
 ******************************************************************************/

esp_err_t watchdog_get_status(watchdog_status_t *status)
{
    if (!s_wdt.initialized || status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_wdt.mutex, portMAX_DELAY);

    status->initialized = s_wdt.initialized;
    status->enabled = s_wdt.enabled;
    status->registered_count = 0;
    status->total_timeouts = 0;

    for (int i = 0; i < WATCHDOG_MAX_TASKS; i++) {
        status->tasks[i].name = s_wdt.tasks[i].name;
        status->tasks[i].registered = s_wdt.tasks[i].registered;
        status->tasks[i].enabled = s_wdt.tasks[i].enabled;
        status->tasks[i].timeout_sec = s_wdt.tasks[i].timeout_sec;
        status->tasks[i].last_feed_time = s_wdt.tasks[i].last_feed_tick;
        status->tasks[i].feed_count = s_wdt.tasks[i].feed_count;
        status->tasks[i].timeout_count = s_wdt.tasks[i].timeout_count;

        if (s_wdt.tasks[i].registered) {
            status->registered_count++;
            status->total_timeouts += s_wdt.tasks[i].timeout_count;
        }
    }

    xSemaphoreGive(s_wdt.mutex);

    return ESP_OK;
}

esp_err_t watchdog_set_timeout_callback(watchdog_timeout_cb_t callback)
{
    if (!s_wdt.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    s_wdt.timeout_callback = callback;
    return ESP_OK;
}

/*******************************************************************************
 * Reset Handling
 ******************************************************************************/

void watchdog_trigger_reset(void)
{
    ESP_LOGW(TAG, "Manual watchdog reset triggered");

    /* Trigger panic via infinite loop without feeding */
    while (1) {
        /* Don't feed the watchdog - will cause reset */
    }
}

bool watchdog_was_reset_by_watchdog(void)
{
    esp_reset_reason_t reason = esp_reset_reason();

    return (reason == ESP_RST_TASK_WDT ||
            reason == ESP_RST_INT_WDT ||
            reason == ESP_RST_WDT);
}

/*******************************************************************************
 * Heap Monitoring (PROD-2.3)
 ******************************************************************************/

static struct {
    bool initialized;
    uint32_t low_threshold;
    uint32_t critical_threshold;
    uint32_t min_free_heap;
    uint32_t low_warning_count;
    bool was_low;
} s_heap = {0};

esp_err_t heap_monitor_init(uint32_t low_threshold, uint32_t critical_threshold)
{
    s_heap.low_threshold = (low_threshold > 0) ? low_threshold : HEAP_LOW_THRESHOLD_DEFAULT;
    s_heap.critical_threshold = (critical_threshold > 0) ? critical_threshold : HEAP_CRITICAL_THRESHOLD_DEFAULT;
    s_heap.min_free_heap = esp_get_free_heap_size();
    s_heap.low_warning_count = 0;
    s_heap.was_low = false;
    s_heap.initialized = true;

    ESP_LOGI(TAG, "Heap monitor initialized: low=%luKB, critical=%luKB, current=%luKB",
             (unsigned long)(s_heap.low_threshold / 1024),
             (unsigned long)(s_heap.critical_threshold / 1024),
             (unsigned long)(s_heap.min_free_heap / 1024));

    return ESP_OK;
}

esp_err_t heap_monitor_check(heap_status_t *status)
{
    if (!s_heap.initialized) {
        /* Auto-initialize with defaults */
        heap_monitor_init(0, 0);
    }

    uint32_t free_heap = esp_get_free_heap_size();
    uint32_t largest_block = heap_caps_get_largest_free_block(MALLOC_CAP_DEFAULT);

    /* Update watermark */
    if (free_heap < s_heap.min_free_heap) {
        s_heap.min_free_heap = free_heap;
        ESP_LOGD(TAG, "New minimum heap: %lu bytes", (unsigned long)free_heap);
    }

    /* Check thresholds */
    bool is_low = (free_heap < s_heap.low_threshold);
    bool is_critical = (free_heap < s_heap.critical_threshold);

    /* Track when we transition into low state */
    if (is_low && !s_heap.was_low) {
        s_heap.low_warning_count++;
        ESP_LOGW(TAG, "LOW MEMORY WARNING: free=%luKB, min=%luKB (warning #%lu)",
                 (unsigned long)(free_heap / 1024),
                 (unsigned long)(s_heap.min_free_heap / 1024),
                 (unsigned long)s_heap.low_warning_count);
    }
    s_heap.was_low = is_low;

    if (is_critical) {
        ESP_LOGE(TAG, "CRITICAL MEMORY: free=%lu bytes, largest_block=%lu bytes",
                 (unsigned long)free_heap, (unsigned long)largest_block);
    }

    /* Fill status if requested */
    if (status != NULL) {
        status->free_heap = free_heap;
        status->min_free_heap = s_heap.min_free_heap;
        status->largest_free_block = largest_block;
        status->low_threshold = s_heap.low_threshold;
        status->critical_threshold = s_heap.critical_threshold;
        status->is_low = is_low;
        status->is_critical = is_critical;
        status->low_warning_count = s_heap.low_warning_count;
    }

    return is_critical ? ESP_ERR_NO_MEM : ESP_OK;
}

esp_err_t heap_monitor_get_status(heap_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    return heap_monitor_check(status);
}

uint32_t heap_monitor_get_min_free(void)
{
    if (!s_heap.initialized) {
        return esp_get_free_heap_size();
    }
    return s_heap.min_free_heap;
}

esp_err_t heap_monitor_reset_watermark(void)
{
    s_heap.min_free_heap = esp_get_free_heap_size();
    ESP_LOGI(TAG, "Heap watermark reset to %lu bytes", (unsigned long)s_heap.min_free_heap);
    return ESP_OK;
}
