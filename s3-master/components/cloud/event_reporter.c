/**
 * @file event_reporter.c
 * @brief Event queue and cloud reporting implementation
 *
 * Manages event queuing and reporting to Supabase for the Saturday Vinyl Hub.
 * Implements a ring buffer for offline support and a background task for
 * cloud synchronization.
 *
 * Phase 5: Supabase Integration
 */

#include "event_reporter.h"
#include "supabase_client.h"
#include "now_playing.h"
#include "wifi_manager.h"
#include "rfid_protocol.h"
#include "app_config.h"

/* Note: In 2-SoC architecture, S3 doesn't have OpenThread.
 * Thread management is handled by H2 co-processor.
 * The ifdef guards in send_event/heartbeat will compile to no-ops. */
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <sys/time.h>

static const char *TAG = "EVENT_RPT";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(EVENT_REPORTER_EVENTS);

/*******************************************************************************
 * Constants
 ******************************************************************************/

#define SYNC_TASK_STACK_SIZE    12288  /* Needs room for TLS/HTTPS operations */
#define SYNC_TASK_PRIORITY      5
#define SYNC_INTERVAL_MS        1000    /* Check queue every second */
#define MAX_JSON_SIZE           512

/*******************************************************************************
 * Queued Event Structure
 ******************************************************************************/

typedef enum {
    QUEUED_EVENT_NOW_PLAYING_PLACED,
    QUEUED_EVENT_NOW_PLAYING_REMOVED,
} queued_event_type_t;

typedef struct {
    queued_event_type_t type;
    uint8_t epc[RFID_EPC_MAX_LEN];
    uint8_t epc_len;
    int8_t rssi;
    int64_t timestamp;          /* Microseconds since boot */
    uint32_t duration_ms;       /* For removal events */
} queued_event_t;

/*******************************************************************************
 * Ring Buffer
 ******************************************************************************/

typedef struct {
    queued_event_t *events;
    uint16_t capacity;
    uint16_t head;              /* Next write position */
    uint16_t tail;              /* Next read position */
    uint16_t count;             /* Current count */
} ring_buffer_t;

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    bool initialized;
    bool running;
    bool wifi_connected;
    event_reporter_config_t config;

    /* Ring buffer */
    ring_buffer_t queue;
    SemaphoreHandle_t queue_mutex;

    /* Background task */
    TaskHandle_t sync_task;
    bool sync_task_stop;

    /* Heartbeat timer */
    esp_timer_handle_t heartbeat_timer;
    int64_t last_heartbeat_time;
    volatile bool heartbeat_pending;  /* Flag for sync task to send heartbeat */

    /* Statistics */
    uint32_t events_sent;
    uint32_t events_failed;
    uint32_t events_dropped;
    uint32_t heartbeats_sent;
    int64_t last_sync_time;

    /* Memory monitoring (PROD-2.3) */
    uint32_t min_free_heap;           /* Minimum heap seen since boot */
    uint32_t low_heap_warnings;       /* Count of low heap warnings */
} event_reporter_state_t;

static event_reporter_state_t s_state = {0};

/*******************************************************************************
 * Ring Buffer Operations
 ******************************************************************************/

static bool ring_buffer_init(ring_buffer_t *rb, uint16_t capacity)
{
    rb->events = malloc(capacity * sizeof(queued_event_t));
    if (rb->events == NULL) {
        return false;
    }
    rb->capacity = capacity;
    rb->head = 0;
    rb->tail = 0;
    rb->count = 0;
    return true;
}

static void ring_buffer_deinit(ring_buffer_t *rb)
{
    if (rb->events != NULL) {
        free(rb->events);
        rb->events = NULL;
    }
    rb->capacity = 0;
    rb->head = 0;
    rb->tail = 0;
    rb->count = 0;
}

static bool ring_buffer_push(ring_buffer_t *rb, const queued_event_t *event, bool *dropped_oldest)
{
    *dropped_oldest = false;

    if (rb->count >= rb->capacity) {
        /* Buffer full - drop oldest event */
        rb->tail = (rb->tail + 1) % rb->capacity;
        rb->count--;
        *dropped_oldest = true;
    }

    memcpy(&rb->events[rb->head], event, sizeof(queued_event_t));
    rb->head = (rb->head + 1) % rb->capacity;
    rb->count++;
    return true;
}

static bool ring_buffer_pop(ring_buffer_t *rb, queued_event_t *event)
{
    if (rb->count == 0) {
        return false;
    }

    memcpy(event, &rb->events[rb->tail], sizeof(queued_event_t));
    rb->tail = (rb->tail + 1) % rb->capacity;
    rb->count--;
    return true;
}

static bool ring_buffer_peek(ring_buffer_t *rb, queued_event_t *event)
{
    if (rb->count == 0) {
        return false;
    }
    memcpy(event, &rb->events[rb->tail], sizeof(queued_event_t));
    return true;
}

static void ring_buffer_clear(ring_buffer_t *rb)
{
    rb->head = 0;
    rb->tail = 0;
    rb->count = 0;
}

/*******************************************************************************
 * JSON Formatting
 ******************************************************************************/

/**
 * @brief Format timestamp as ISO 8601 string
 *
 * Note: ESP32 doesn't have real-time clock by default, so we use
 * uptime for now. In production, this should use SNTP-synced time.
 */
static void format_timestamp(int64_t timestamp_us, char *buf, size_t buf_len)
{
    /* For now, use boot-relative timestamp as ISO string */
    /* In production, use time() with SNTP sync */
    time_t now;
    time(&now);
    struct tm timeinfo;
    gmtime_r(&now, &timeinfo);

    strftime(buf, buf_len, "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
}

/**
 * @brief Format Now Playing event as JSON
 */
static int format_now_playing_json(const queued_event_t *event, char *buf, size_t buf_len)
{
    char unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "UNIT-UNKNOWN";
    supabase_get_unit_id(unit_id, sizeof(unit_id));

    char epc_str[25];
    rfid_epc_to_hex_string(event->epc, event->epc_len, epc_str, sizeof(epc_str));

    char timestamp[32];
    format_timestamp(event->timestamp, timestamp, sizeof(timestamp));

    const char *event_type = (event->type == QUEUED_EVENT_NOW_PLAYING_PLACED) ? "placed" : "removed";

    int len;
    if (event->type == QUEUED_EVENT_NOW_PLAYING_REMOVED) {
        len = snprintf(buf, buf_len,
            "{\"unit_id\":\"%s\",\"epc\":\"%s\",\"event_type\":\"%s\","
            "\"rssi\":%d,\"duration_ms\":%lu,\"timestamp\":\"%s\"}",
            unit_id, epc_str, event_type, event->rssi,
            (unsigned long)event->duration_ms, timestamp);
    } else {
        len = snprintf(buf, buf_len,
            "{\"unit_id\":\"%s\",\"epc\":\"%s\",\"event_type\":\"%s\","
            "\"rssi\":%d,\"timestamp\":\"%s\"}",
            unit_id, epc_str, event_type, event->rssi, timestamp);
    }

    return len;
}

/**
 * @brief Format heartbeat as JSON
 *
 * Uses new device_heartbeats schema:
 * - device_serial (was unit_id)
 * - device_type: 'hub'
 * - device_timestamp (was timestamp)
 *
 * PROD-2.3: Added min_free_heap for memory leak detection
 */
static int format_heartbeat_json(char *buf, size_t buf_len)
{
    char device_serial[SUPABASE_UNIT_ID_MAX_LEN] = "UNIT-UNKNOWN";
    supabase_get_unit_id(device_serial, sizeof(device_serial));

    char timestamp[32];
    format_timestamp(esp_timer_get_time(), timestamp, sizeof(timestamp));

    /* Get Wi-Fi RSSI if connected */
    int8_t wifi_rssi = 0;
    if (s_state.wifi_connected) {
        wifi_manager_status_t wifi_status;
        if (wifi_get_status(&wifi_status) == ESP_OK) {
            wifi_rssi = wifi_status.rssi;
        }
    }

    /* Calculate uptime in seconds */
    uint32_t uptime_sec = (uint32_t)(esp_timer_get_time() / 1000000);

    /* Get current and minimum heap (PROD-2.3) */
    uint32_t free_heap = (uint32_t)esp_get_free_heap_size();
    if (free_heap < s_state.min_free_heap) {
        s_state.min_free_heap = free_heap;
    }

    int len = snprintf(buf, buf_len,
        "{\"device_serial\":\"%s\",\"device_type\":\"hub\","
        "\"firmware_version\":\"%s\","
        "\"wifi_rssi\":%d,\"uptime_sec\":%lu,\"free_heap\":%lu,"
        "\"min_free_heap\":%lu,\"events_queued\":%u,\"device_timestamp\":\"%s\"}",
        device_serial, FW_VERSION_STRING, wifi_rssi, (unsigned long)uptime_sec,
        (unsigned long)free_heap,
        (unsigned long)s_state.min_free_heap,
        s_state.queue.count, timestamp);

    return len;
}

/*******************************************************************************
 * Event Sending
 ******************************************************************************/

/**
 * @brief Send a single event to Supabase
 *
 * Suspends Thread radio during the HTTP request for reliable TLS.
 */
static esp_err_t send_event(const queued_event_t *event)
{
    char json[MAX_JSON_SIZE];
    int len = format_now_playing_json(event, json, sizeof(json));
    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    /* Completely shutdown Thread to give WiFi exclusive radio access.
     * The suspend approach wasn't reliable enough - full shutdown ensures
     * no 802.15.4 radio activity during TLS handshake. */
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    thread_br_shutdown_for_wifi();
#endif

    supabase_response_t response;
    esp_err_t err = supabase_post("now_playing_events", json, &response, 0);

    /* Restart Thread after WiFi operation */
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    thread_br_restart_after_wifi();
#endif

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Event POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    }
    supabase_response_free(&response);
    return err;
}

/**
 * @brief Send heartbeat to Supabase
 *
 * Completely shuts down Thread during the HTTP request to ensure reliable TLS.
 * With WiFi+Thread coexistence on a single radio, even suspend wasn't enough
 * to prevent packet loss during TLS handshakes. Full shutdown gives WiFi
 * exclusive radio access for reliable cloud connectivity.
 */
static esp_err_t send_heartbeat_internal(void)
{
    char json[MAX_JSON_SIZE];
    int len = format_heartbeat_json(json, sizeof(json));
    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "Heartbeat JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    /* Completely shutdown Thread to give WiFi exclusive radio access.
     * The suspend approach wasn't reliable enough - full shutdown ensures
     * no 802.15.4 radio activity during TLS handshake. */
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    thread_br_shutdown_for_wifi();
#endif

    supabase_response_t response;
    esp_err_t err = supabase_post("device_heartbeats", json, &response, 0);

    /* Restart Thread after WiFi operation */
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    thread_br_restart_after_wifi();
#endif

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        s_state.heartbeats_sent++;
        s_state.last_heartbeat_time = esp_timer_get_time();
        ESP_LOGI(TAG, "Heartbeat sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Heartbeat POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    }
    supabase_response_free(&response);
    return err;
}

/*******************************************************************************
 * Event Handlers
 ******************************************************************************/

/**
 * @brief Handler for Now Playing events
 */
static void on_now_playing_event(void *handler_args, esp_event_base_t base,
                                  int32_t event_id, void *event_data)
{
    if (!s_state.initialized) {
        return;
    }

    const now_playing_event_t *np_event = (const now_playing_event_t *)event_data;

    /* Create queued event */
    queued_event_t queued = {
        .type = (event_id == NOW_PLAYING_EVENT_TAG_PLACED) ?
                QUEUED_EVENT_NOW_PLAYING_PLACED : QUEUED_EVENT_NOW_PLAYING_REMOVED,
        .epc_len = np_event->epc_len,
        .rssi = np_event->rssi,
        .timestamp = np_event->timestamp,
        .duration_ms = np_event->duration_ms,
    };
    memcpy(queued.epc, np_event->epc, np_event->epc_len);

    /* Add to queue */
    xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
    bool dropped = false;
    ring_buffer_push(&s_state.queue, &queued, &dropped);
    if (dropped) {
        s_state.events_dropped++;
        ESP_LOGW(TAG, "Event queue full - dropped oldest event");

        /* Post queue full event */
        esp_event_post(EVENT_REPORTER_EVENTS, EVENT_REPORTER_EVENT_QUEUE_FULL,
                       NULL, 0, 0);
    }
    xSemaphoreGive(s_state.queue_mutex);

    char epc_str[25];
    rfid_epc_to_hex_string(np_event->epc, np_event->epc_len, epc_str, sizeof(epc_str));
    ESP_LOGD(TAG, "Queued %s event for %s (queue size: %u)",
             (event_id == NOW_PLAYING_EVENT_TAG_PLACED) ? "PLACED" : "REMOVED",
             epc_str, s_state.queue.count);
}

/*******************************************************************************
 * Background Sync Task
 ******************************************************************************/

/**
 * @brief Process queued events
 */
static void process_queue(void)
{
    if (!s_state.wifi_connected || !supabase_is_configured()) {
        return;
    }

    /* Wait for SNTP time sync before attempting HTTPS (TLS requires valid time) */
    if (!wifi_is_time_synced()) {
        static int wait_count = 0;
        if (++wait_count % 5 == 1) {  /* Log every 5 seconds */
            ESP_LOGI(TAG, "Waiting for SNTP time sync before cloud sync...");
        }
        return;
    }

    xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
    uint16_t count = s_state.queue.count;
    xSemaphoreGive(s_state.queue_mutex);

    if (count == 0) {
        return;
    }

    ESP_LOGI(TAG, "Syncing %u queued events (time synced)...", count);

    /* Post sync start event */
    esp_event_post(EVENT_REPORTER_EVENTS, EVENT_REPORTER_EVENT_SYNC_START,
                   NULL, 0, 0);

    uint32_t synced = 0;
    uint32_t failed = 0;

    while (true) {
        /* Peek at next event */
        queued_event_t event;
        xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
        bool has_event = ring_buffer_peek(&s_state.queue, &event);
        xSemaphoreGive(s_state.queue_mutex);

        if (!has_event) {
            break;
        }

        /* Try to send */
        esp_err_t err = send_event(&event);

        if (err == ESP_OK) {
            /* Success - remove from queue */
            xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
            ring_buffer_pop(&s_state.queue, &event);
            xSemaphoreGive(s_state.queue_mutex);

            s_state.events_sent++;
            synced++;
        } else {
            /* Failed - stop syncing for now */
            s_state.events_failed++;
            failed++;
            ESP_LOGW(TAG, "Failed to send event, will retry later");
            break;
        }

        /* Brief yield to avoid starving other tasks */
        vTaskDelay(pdMS_TO_TICKS(10));
    }

    s_state.last_sync_time = esp_timer_get_time();

    /* Post sync complete/failed event */
    event_reporter_sync_data_t sync_data = {
        .events_synced = synced,
        .events_failed = failed,
        .events_queued = s_state.queue.count,
    };

    if (failed > 0) {
        esp_event_post(EVENT_REPORTER_EVENTS, EVENT_REPORTER_EVENT_SYNC_FAILED,
                       &sync_data, sizeof(sync_data), 0);
    } else {
        esp_event_post(EVENT_REPORTER_EVENTS, EVENT_REPORTER_EVENT_SYNC_COMPLETE,
                       &sync_data, sizeof(sync_data), 0);
    }

    ESP_LOGI(TAG, "Sync complete: %lu sent, %lu failed, %u queued",
             (unsigned long)synced, (unsigned long)failed, s_state.queue.count);
}

/**
 * @brief Background sync task
 */
static void sync_task(void *arg)
{
    ESP_LOGI(TAG, "Sync task started");

    while (!s_state.sync_task_stop) {
        /* Check if heartbeat timer triggered (runs in sync_task for adequate stack) */
        if (s_state.heartbeat_pending) {
            s_state.heartbeat_pending = false;
            send_heartbeat_internal();
        }

        /* Process queued events */
        process_queue();

        /* Wait before next check */
        vTaskDelay(pdMS_TO_TICKS(SYNC_INTERVAL_MS));
    }

    ESP_LOGI(TAG, "Sync task stopped");
    s_state.sync_task = NULL;
    vTaskDelete(NULL);
}

/*******************************************************************************
 * Heartbeat Timer
 ******************************************************************************/

static void heartbeat_timer_callback(void *arg)
{
    /* Don't call send_heartbeat_internal() directly - esp_timer task has limited stack.
     * Instead, set a flag that the sync_task (with adequate stack) will handle. */
    if (s_state.wifi_connected && supabase_is_configured() && wifi_is_time_synced()) {
        s_state.heartbeat_pending = true;
    }
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t event_reporter_init(const event_reporter_config_t *config)
{
    if (s_state.initialized) {
        return ESP_OK;
    }

    memset(&s_state, 0, sizeof(s_state));

    /* Initialize minimum heap to current value (PROD-2.3) */
    s_state.min_free_heap = (uint32_t)esp_get_free_heap_size();

    /* Use provided config or defaults */
    if (config != NULL) {
        s_state.config = *config;
    } else {
        s_state.config = (event_reporter_config_t)EVENT_REPORTER_CONFIG_DEFAULT();
    }

    /* Initialize ring buffer */
    if (!ring_buffer_init(&s_state.queue, s_state.config.queue_size)) {
        ESP_LOGE(TAG, "Failed to allocate event queue");
        return ESP_ERR_NO_MEM;
    }

    /* Create mutex */
    s_state.queue_mutex = xSemaphoreCreateMutex();
    if (s_state.queue_mutex == NULL) {
        ring_buffer_deinit(&s_state.queue);
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Register for Now Playing events */
    esp_err_t err = esp_event_handler_register(NOW_PLAYING_EVENTS, ESP_EVENT_ANY_ID,
                                                on_now_playing_event, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Now Playing handler: %s", esp_err_to_name(err));
        vSemaphoreDelete(s_state.queue_mutex);
        ring_buffer_deinit(&s_state.queue);
        return err;
    }

    /* Create heartbeat timer */
    if (s_state.config.enable_heartbeat) {
        esp_timer_create_args_t timer_args = {
            .callback = heartbeat_timer_callback,
            .name = "heartbeat",
        };
        err = esp_timer_create(&timer_args, &s_state.heartbeat_timer);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Failed to create heartbeat timer: %s", esp_err_to_name(err));
            /* Continue without heartbeat */
        }
    }

    s_state.initialized = true;
    ESP_LOGI(TAG, "Event reporter initialized (queue_size=%u, heartbeat=%s)",
             s_state.config.queue_size,
             s_state.config.enable_heartbeat ? "enabled" : "disabled");

    return ESP_OK;
}

esp_err_t event_reporter_deinit(void)
{
    if (!s_state.initialized) {
        return ESP_OK;
    }

    /* Stop task */
    event_reporter_stop();

    /* Stop heartbeat timer */
    if (s_state.heartbeat_timer != NULL) {
        esp_timer_stop(s_state.heartbeat_timer);
        esp_timer_delete(s_state.heartbeat_timer);
        s_state.heartbeat_timer = NULL;
    }

    /* Unregister event handler */
    esp_event_handler_unregister(NOW_PLAYING_EVENTS, ESP_EVENT_ANY_ID,
                                  on_now_playing_event);

    /* Free resources */
    vSemaphoreDelete(s_state.queue_mutex);
    ring_buffer_deinit(&s_state.queue);

    memset(&s_state, 0, sizeof(s_state));
    ESP_LOGI(TAG, "Event reporter deinitialized");
    return ESP_OK;
}

esp_err_t event_reporter_start(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.running) {
        return ESP_OK;
    }

    s_state.sync_task_stop = false;

    /* Create sync task */
    BaseType_t ret = xTaskCreate(sync_task, "event_sync",
                                  SYNC_TASK_STACK_SIZE, NULL,
                                  SYNC_TASK_PRIORITY, &s_state.sync_task);
    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create sync task");
        return ESP_ERR_NO_MEM;
    }

    /* Start heartbeat timer */
    if (s_state.heartbeat_timer != NULL) {
        uint64_t interval_us = (uint64_t)s_state.config.heartbeat_interval_sec * 1000000;
        esp_timer_start_periodic(s_state.heartbeat_timer, interval_us);
    }

    s_state.running = true;
    ESP_LOGI(TAG, "Event reporter started");
    return ESP_OK;
}

esp_err_t event_reporter_stop(void)
{
    if (!s_state.initialized || !s_state.running) {
        return ESP_OK;
    }

    /* Signal task to stop */
    s_state.sync_task_stop = true;

    /* Stop heartbeat timer */
    if (s_state.heartbeat_timer != NULL) {
        esp_timer_stop(s_state.heartbeat_timer);
    }

    /* Wait for task to finish */
    int timeout = 50;  /* 5 seconds */
    while (s_state.sync_task != NULL && timeout > 0) {
        vTaskDelay(pdMS_TO_TICKS(100));
        timeout--;
    }

    s_state.running = false;
    ESP_LOGI(TAG, "Event reporter stopped");
    return ESP_OK;
}

esp_err_t event_reporter_get_status(event_reporter_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    status->initialized = s_state.initialized;
    status->running = s_state.running;
    status->wifi_connected = s_state.wifi_connected;
    status->supabase_configured = supabase_is_configured();

    xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
    status->events_queued = s_state.queue.count;
    xSemaphoreGive(s_state.queue_mutex);

    status->events_sent = s_state.events_sent;
    status->events_failed = s_state.events_failed;
    status->events_dropped = s_state.events_dropped;
    status->heartbeats_sent = s_state.heartbeats_sent;
    status->last_sync_time = s_state.last_sync_time;
    status->last_heartbeat_time = s_state.last_heartbeat_time;

    /* PROD-2.3: Memory monitoring */
    status->min_free_heap = s_state.min_free_heap;
    status->low_heap_warnings = s_state.low_heap_warnings;

    return ESP_OK;
}

esp_err_t event_reporter_flush(uint32_t timeout_ms)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_state.wifi_connected) {
        return ESP_ERR_NOT_FOUND;
    }

    int64_t start = esp_timer_get_time();
    int64_t timeout_us = (int64_t)timeout_ms * 1000;

    while (s_state.queue.count > 0) {
        process_queue();

        if (timeout_ms > 0) {
            int64_t elapsed = esp_timer_get_time() - start;
            if (elapsed >= timeout_us) {
                ESP_LOGW(TAG, "Flush timeout with %u events remaining", s_state.queue.count);
                return ESP_ERR_TIMEOUT;
            }
        }

        if (s_state.queue.count > 0) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
    }

    return ESP_OK;
}

esp_err_t event_reporter_send_heartbeat(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_state.wifi_connected || !supabase_is_configured()) {
        return ESP_ERR_NOT_FOUND;
    }

    return send_heartbeat_internal();
}

esp_err_t event_reporter_clear_queue(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    xSemaphoreTake(s_state.queue_mutex, portMAX_DELAY);
    uint16_t dropped = s_state.queue.count;
    ring_buffer_clear(&s_state.queue);
    xSemaphoreGive(s_state.queue_mutex);

    if (dropped > 0) {
        ESP_LOGI(TAG, "Cleared %u events from queue", dropped);
    }

    return ESP_OK;
}

void event_reporter_set_wifi_state(bool connected)
{
    bool was_connected = s_state.wifi_connected;
    s_state.wifi_connected = connected;

    if (connected && !was_connected) {
        ESP_LOGI(TAG, "Wi-Fi connected - will sync queued events");
        /*
         * Don't call process_queue() here - we're in an event handler context
         * with limited stack. The background sync task will pick up the events
         * on its next iteration (within SYNC_INTERVAL_MS = 1 second).
         */
    } else if (!connected && was_connected) {
        ESP_LOGI(TAG, "Wi-Fi disconnected - events will be queued");
    }
}

/*******************************************************************************
 * H2/Crate Event Reporting (INT-2: Full Pipeline)
 ******************************************************************************/

/* H2 state tracking for heartbeats */
static bool s_h2_connected = false;
static uint8_t s_h2_thread_state = 0;

void event_reporter_set_h2_state(bool connected, uint8_t thread_state)
{
    s_h2_connected = connected;
    s_h2_thread_state = thread_state;
    ESP_LOGD(TAG, "H2 state updated: connected=%d, thread_state=%d", connected, thread_state);
}

/**
 * @brief Format extended MAC address as hex string
 */
static void format_ext_addr(const uint8_t *ext_addr, char *buf, size_t buf_len)
{
    snprintf(buf, buf_len, "%02X%02X%02X%02X%02X%02X%02X%02X",
             ext_addr[0], ext_addr[1], ext_addr[2], ext_addr[3],
             ext_addr[4], ext_addr[5], ext_addr[6], ext_addr[7]);
}

/**
 * @brief Send crate inventory event to Supabase directly
 *
 * Note: This is called from main context when H2 event is received.
 * For simplicity, we send immediately rather than queuing.
 */
esp_err_t event_reporter_queue_inventory(const uint8_t *crate_ext_addr,
                                          const uint8_t (*epcs)[12],
                                          uint8_t epc_count)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_state.wifi_connected || !supabase_is_configured()) {
        ESP_LOGW(TAG, "Cannot send inventory - WiFi or Supabase not ready");
        return ESP_ERR_NOT_FOUND;
    }

    if (!wifi_is_time_synced()) {
        ESP_LOGW(TAG, "Cannot send inventory - time not synced");
        return ESP_ERR_NOT_FINISHED;
    }

    char unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "UNIT-UNKNOWN";
    supabase_get_unit_id(unit_id, sizeof(unit_id));

    char crate_id[20];
    format_ext_addr(crate_ext_addr, crate_id, sizeof(crate_id));

    char timestamp[32];
    format_timestamp(esp_timer_get_time(), timestamp, sizeof(timestamp));

    /* Build EPC array JSON */
    char epcs_json[1024] = "[";
    size_t epcs_len = 1;
    for (uint8_t i = 0; i < epc_count && epcs_len < sizeof(epcs_json) - 30; i++) {
        char epc_hex[25];
        for (int j = 0; j < 12; j++) {
            snprintf(&epc_hex[j * 2], 3, "%02X", epcs[i][j]);
        }
        if (i > 0) {
            epcs_len += snprintf(&epcs_json[epcs_len], sizeof(epcs_json) - epcs_len, ",");
        }
        epcs_len += snprintf(&epcs_json[epcs_len], sizeof(epcs_json) - epcs_len, "\"%s\"", epc_hex);
    }
    snprintf(&epcs_json[epcs_len], sizeof(epcs_json) - epcs_len, "]");

    /* Build full JSON */
    char json[1500];
    int len = snprintf(json, sizeof(json),
        "{\"unit_id\":\"%s\",\"crate_id\":\"%s\",\"epcs\":%s,"
        "\"epc_count\":%d,\"timestamp\":\"%s\"}",
        unit_id, crate_id, epcs_json, epc_count, timestamp);

    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "Inventory JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    ESP_LOGI(TAG, "Sending inventory update: crate=%s, epcs=%d", crate_id, epc_count);

    supabase_response_t response;
    esp_err_t err = supabase_post("crate_inventory_events", json, &response, 0);

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGI(TAG, "Inventory update sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Inventory POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    }
    supabase_response_free(&response);
    return err;
}

esp_err_t event_reporter_queue_crate_heartbeat(const uint8_t *crate_ext_addr,
                                                uint8_t battery_percent,
                                                int8_t rssi)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_state.wifi_connected || !supabase_is_configured()) {
        ESP_LOGD(TAG, "Cannot send crate heartbeat - WiFi or Supabase not ready");
        return ESP_ERR_NOT_FOUND;
    }

    if (!wifi_is_time_synced()) {
        ESP_LOGD(TAG, "Cannot send crate heartbeat - time not synced");
        return ESP_ERR_NOT_FINISHED;
    }

    char unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "UNIT-UNKNOWN";
    supabase_get_unit_id(unit_id, sizeof(unit_id));

    char crate_id[20];
    format_ext_addr(crate_ext_addr, crate_id, sizeof(crate_id));

    char timestamp[32];
    format_timestamp(esp_timer_get_time(), timestamp, sizeof(timestamp));

    char json[256];
    int len = snprintf(json, sizeof(json),
        "{\"unit_id\":\"%s\",\"crate_id\":\"%s\",\"battery_percent\":%d,"
        "\"rssi\":%d,\"timestamp\":\"%s\"}",
        unit_id, crate_id, battery_percent, rssi, timestamp);

    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "Crate heartbeat JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    ESP_LOGD(TAG, "Sending crate heartbeat: crate=%s, batt=%d%%, rssi=%d",
             crate_id, battery_percent, rssi);

    supabase_response_t response;
    esp_err_t err = supabase_post("crate_heartbeats", json, &response, 0);

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGD(TAG, "Crate heartbeat sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "Crate heartbeat POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    }
    supabase_response_free(&response);
    return err;
}
