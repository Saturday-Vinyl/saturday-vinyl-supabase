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
#include "realtime_client.h"

/* Thread networking is managed by the H2 co-processor via UART protocol. */
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "esp_mac.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <sys/time.h>

#include "cbor.h"
#include "s3_h2_protocol.h"

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

/* H2 state tracking for heartbeats */
static bool s_h2_connected = false;
static uint8_t s_h2_thread_state = 0;

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
 * @brief Format heartbeat as JSON (Device Command Protocol v1.2.2)
 *
 * Standard fields (required per protocol):
 * - mac_address: Primary device identifier
 * - unit_id: Serial number from provisioning
 * - device_type: From firmware JSON schema (DEVICE_TYPE)
 * - firmware_version: Compile-time constant
 * - uptime_sec: Seconds since boot
 * - free_heap: Current free heap
 * - min_free_heap: Minimum free heap since boot (memory leak detection)
 * - largest_free_block: Largest contiguous block (fragmentation detection)
 *
 * WiFi capability heartbeat fields (from firmware JSON schema):
 * - wifi_rssi: Signal strength (only field in wifi.heartbeat schema)
 */
static int format_heartbeat_json(char *buf, size_t buf_len)
{
    /* Get MAC address as primary identifier */
    uint8_t mac[6];
    char mac_str[18] = "00:00:00:00:00:00";
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
        snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    }

    /* Get unit_id (serial number) from Supabase config */
    char unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "";
    supabase_get_unit_id(unit_id, sizeof(unit_id));

    /* WiFi capability heartbeat field (only wifi_rssi per schema) */
    int8_t wifi_rssi = 0;
    if (s_state.wifi_connected) {
        wifi_manager_status_t wifi_status;
        if (wifi_get_status(&wifi_status) == ESP_OK) {
            wifi_rssi = wifi_status.rssi;
        }
    }

    /* Standard system info (protocol v1.2.2 required fields) */
    uint32_t uptime_sec = (uint32_t)(esp_timer_get_time() / 1000000);
    uint32_t total_heap = (uint32_t)heap_caps_get_total_size(MALLOC_CAP_8BIT);
    uint32_t free_heap = (uint32_t)esp_get_free_heap_size();
    uint32_t min_free_heap = (uint32_t)esp_get_minimum_free_heap_size();
    uint32_t largest_free_block = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);

    /* WebSocket capability heartbeat field (websocket_connected per schema) */
    bool ws_connected = realtime_client_is_connected();

    int len = snprintf(buf, buf_len,
        "{\"mac_address\":\"%s\","
        "\"unit_id\":\"%s\","
        "\"device_type\":\"%s\","
        "\"firmware_version\":\"%s\","
        "\"telemetry\":{"
        "\"uptime_sec\":%lu,"
        "\"total_heap\":%lu,"
        "\"free_heap\":%lu,"
        "\"min_free_heap\":%lu,"
        "\"largest_free_block\":%lu,"
        "\"wifi_rssi\":%d,"
        "\"h2_connected\":%s,"
        "\"h2_thread_state\":%d,"
        "\"websocket_connected\":%s}}",
        mac_str,
        unit_id,
        DEVICE_TYPE,
        FW_VERSION_STRING,
        (unsigned long)uptime_sec,
        (unsigned long)total_heap,
        (unsigned long)free_heap,
        (unsigned long)min_free_heap,
        (unsigned long)largest_free_block,
        wifi_rssi,
        s_h2_connected ? "true" : "false",
        s_h2_thread_state,
        ws_connected ? "true" : "false");

    return len;
}

/*******************************************************************************
 * Event Sending
 ******************************************************************************/

/**
 * @brief Send a single event to Supabase
 */
static esp_err_t send_event(const queued_event_t *event)
{
    char json[MAX_JSON_SIZE];
    int len = format_now_playing_json(event, json, sizeof(json));
    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    supabase_response_t response;
    esp_err_t err = supabase_post("now_playing_events", json, &response, 0);

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
 */
static esp_err_t send_heartbeat_internal(void)
{
    char json[MAX_JSON_SIZE];
    int len = format_heartbeat_json(json, sizeof(json));
    if (len >= sizeof(json)) {
        ESP_LOGE(TAG, "Heartbeat JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    /* Log complete heartbeat payload to serial monitor for debugging.
     * Use printf to avoid ESP_LOG truncation on long messages. */
    printf("[EVENT_RPT] Heartbeat payload (%d bytes): %s\n", len, json);

    supabase_response_t response;
    esp_err_t err = supabase_post("device_heartbeats", json, &response, 0);

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
        /* Close persistent Supabase connection — the TLS session is dead
         * and holding stale buffers wastes heap. */
        supabase_close_connection();
    }
}

/*******************************************************************************
 * H2/Crate Event Reporting (INT-2: Full Pipeline)
 ******************************************************************************/

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

/*******************************************************************************
 * CoAP Mesh Protocol — Crate Identity Cache
 ******************************************************************************/

#define MAX_CACHED_CRATES  20

typedef struct {
    bool valid;
    uint8_t ext_addr[8];
    char mac[18];
    char unit_id[24];
    char device_type[20];
    char fw_version[16];
} crate_identity_t;

static crate_identity_t s_crate_cache[MAX_CACHED_CRATES];

void event_reporter_cache_crate_identity(const uint8_t *ext_addr,
                                          const char *mac,
                                          const char *unit_id,
                                          const char *device_type,
                                          const char *fw_version)
{
    if (ext_addr == NULL) return;

    /* Look for existing entry */
    int free_slot = -1;
    for (int i = 0; i < MAX_CACHED_CRATES; i++) {
        if (s_crate_cache[i].valid &&
            memcmp(s_crate_cache[i].ext_addr, ext_addr, 8) == 0) {
            /* Update existing */
            if (mac) strncpy(s_crate_cache[i].mac, mac, sizeof(s_crate_cache[i].mac) - 1);
            if (unit_id) strncpy(s_crate_cache[i].unit_id, unit_id, sizeof(s_crate_cache[i].unit_id) - 1);
            if (device_type) strncpy(s_crate_cache[i].device_type, device_type, sizeof(s_crate_cache[i].device_type) - 1);
            if (fw_version) strncpy(s_crate_cache[i].fw_version, fw_version, sizeof(s_crate_cache[i].fw_version) - 1);
            ESP_LOGI(TAG, "Updated crate identity cache: mac=%s", s_crate_cache[i].mac);
            return;
        }
        if (!s_crate_cache[i].valid && free_slot < 0) {
            free_slot = i;
        }
    }

    /* New entry */
    if (free_slot < 0) {
        ESP_LOGW(TAG, "Crate identity cache full, overwriting slot 0");
        free_slot = 0;
    }

    memset(&s_crate_cache[free_slot], 0, sizeof(crate_identity_t));
    s_crate_cache[free_slot].valid = true;
    memcpy(s_crate_cache[free_slot].ext_addr, ext_addr, 8);
    if (mac) strncpy(s_crate_cache[free_slot].mac, mac, sizeof(s_crate_cache[free_slot].mac) - 1);
    if (unit_id) strncpy(s_crate_cache[free_slot].unit_id, unit_id, sizeof(s_crate_cache[free_slot].unit_id) - 1);
    if (device_type) strncpy(s_crate_cache[free_slot].device_type, device_type, sizeof(s_crate_cache[free_slot].device_type) - 1);
    if (fw_version) strncpy(s_crate_cache[free_slot].fw_version, fw_version, sizeof(s_crate_cache[free_slot].fw_version) - 1);
    ESP_LOGI(TAG, "Cached new crate identity: mac=%s, type=%s", mac ? mac : "?", device_type ? device_type : "?");
}

bool event_reporter_lookup_crate_ext_addr(const char *mac, uint8_t *ext_addr_out)
{
    if (mac == NULL || ext_addr_out == NULL) return false;

    for (int i = 0; i < MAX_CACHED_CRATES; i++) {
        if (s_crate_cache[i].valid && strcmp(s_crate_cache[i].mac, mac) == 0) {
            memcpy(ext_addr_out, s_crate_cache[i].ext_addr, 8);
            return true;
        }
    }
    return false;
}

static const crate_identity_t *crate_identity_lookup(const uint8_t *ext_addr)
{
    for (int i = 0; i < MAX_CACHED_CRATES; i++) {
        if (s_crate_cache[i].valid &&
            memcmp(s_crate_cache[i].ext_addr, ext_addr, 8) == 0) {
            return &s_crate_cache[i];
        }
    }
    return NULL;
}

/*******************************************************************************
 * CoAP Mesh Protocol — CBOR Telemetry Decode and Cloud Posting
 ******************************************************************************/

esp_err_t event_reporter_queue_crate_telemetry(const uint8_t *crate_ext_addr,
                                                uint8_t hb_type,
                                                const uint8_t *cbor_data,
                                                uint16_t cbor_len)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_state.wifi_connected || !supabase_is_configured()) {
        ESP_LOGD(TAG, "Cannot send crate telemetry - WiFi or Supabase not ready");
        return ESP_ERR_NOT_FOUND;
    }

    if (!wifi_is_time_synced()) {
        ESP_LOGD(TAG, "Cannot send crate telemetry - time not synced");
        return ESP_ERR_NOT_FINISHED;
    }

    /* Look up device identity */
    const crate_identity_t *identity = crate_identity_lookup(crate_ext_addr);
    if (identity == NULL) {
        char addr_str[20];
        format_ext_addr(crate_ext_addr, addr_str, sizeof(addr_str));
        ESP_LOGW(TAG, "No identity cached for crate %s, dropping telemetry", addr_str);
        return ESP_ERR_NOT_FOUND;
    }

    /* Determine heartbeat type string */
    const char *type_str = "status";
    if (hb_type == S3H2_HB_TYPE_COMMAND_ACK) {
        type_str = "command_ack";
    } else if (hb_type == S3H2_HB_TYPE_COMMAND_RESULT) {
        type_str = "command_result";
    }

    /*
     * Decode CBOR into JSON telemetry object.
     *
     * Special handling for command ack/result heartbeats:
     * - "cmd_id" → extracted to command_id_str (becomes top-level column)
     * - "result" map → flattened: status/error→telemetry top-level, data→"result"
     *
     * This produces the same telemetry structure as send_command_result_heartbeat()
     * in realtime_client.c, which the update_command_on_ack() trigger expects.
     */
    CborParser cbor_parser;
    CborValue cbor_root;
    CborError cbor_err = cbor_parser_init(cbor_data, cbor_len, 0, &cbor_parser, &cbor_root);
    if (cbor_err != CborNoError || !cbor_value_is_map(&cbor_root)) {
        ESP_LOGW(TAG, "Invalid CBOR telemetry payload");
        return ESP_ERR_INVALID_ARG;
    }

    /* Build telemetry JSON by iterating CBOR map */
    char telemetry_json[768] = "{";
    size_t tpos = 1;
    bool first = true;
    char command_id_str[40] = {0};

    CborValue map_iter;
    cbor_err = cbor_value_enter_container(&cbor_root, &map_iter);
    if (cbor_err != CborNoError) {
        ESP_LOGW(TAG, "Failed to enter CBOR map");
        return ESP_ERR_INVALID_ARG;
    }

    while (!cbor_value_at_end(&map_iter)) {
        /* Read key */
        if (!cbor_value_is_text_string(&map_iter)) {
            cbor_value_advance(&map_iter);
            if (!cbor_value_at_end(&map_iter)) cbor_value_advance(&map_iter);
            continue;
        }

        char key[32] = {0};
        size_t key_len = sizeof(key) - 1;
        cbor_value_copy_text_string(&map_iter, key, &key_len, NULL);
        key[key_len] = '\0';
        cbor_value_advance(&map_iter);

        if (cbor_value_at_end(&map_iter)) break;

        /*
         * cmd_id → extract to command_id_str for top-level column.
         * Maps CBOR "cmd_id" to device_heartbeats.command_id column
         * which the update_command_on_ack() trigger uses.
         */
        if (strcmp(key, "cmd_id") == 0 && cbor_value_is_text_string(&map_iter)) {
            size_t val_len = sizeof(command_id_str) - 1;
            cbor_value_copy_text_string(&map_iter, command_id_str, &val_len, NULL);
            command_id_str[val_len] = '\0';
            /* Clear nil UUID — S3-initiated nudges use a synthetic command_id
             * that doesn't exist in device_commands, so omit the FK reference */
            if (strcmp(command_id_str, "00000000-0000-0000-0000-000000000000") == 0) {
                command_id_str[0] = '\0';
            }
            cbor_value_advance(&map_iter);
            continue;
        }

        /*
         * result map → flatten into telemetry fields.
         * CBOR: "result": {"status":"completed","data":{...},"error":"msg"}
         * JSON: telemetry.status, telemetry.result (from data), telemetry.error_message
         */
        if (strcmp(key, "result") == 0 && cbor_value_is_map(&map_iter)) {
            CborValue result_iter;
            if (cbor_value_enter_container(&map_iter, &result_iter) == CborNoError) {
                while (!cbor_value_at_end(&result_iter)) {
                    if (!cbor_value_is_text_string(&result_iter)) {
                        cbor_value_advance(&result_iter);
                        if (!cbor_value_at_end(&result_iter)) cbor_value_advance(&result_iter);
                        continue;
                    }

                    char rkey[32] = {0};
                    size_t rkey_len = sizeof(rkey) - 1;
                    cbor_value_copy_text_string(&result_iter, rkey, &rkey_len, NULL);
                    rkey[rkey_len] = '\0';
                    cbor_value_advance(&result_iter);
                    if (cbor_value_at_end(&result_iter)) break;

                    if (strcmp(rkey, "status") == 0 && cbor_value_is_text_string(&result_iter)) {
                        char val[32] = {0};
                        size_t val_len = sizeof(val) - 1;
                        cbor_value_copy_text_string(&result_iter, val, &val_len, NULL);
                        val[val_len] = '\0';
                        if (!first && tpos < sizeof(telemetry_json) - 2) telemetry_json[tpos++] = ',';
                        first = false;
                        tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                                         "\"status\":\"%s\"", val);
                    } else if (strcmp(rkey, "error") == 0 && cbor_value_is_text_string(&result_iter)) {
                        char val[128] = {0};
                        size_t val_len = sizeof(val) - 1;
                        cbor_value_copy_text_string(&result_iter, val, &val_len, NULL);
                        val[val_len] = '\0';
                        if (!first && tpos < sizeof(telemetry_json) - 2) telemetry_json[tpos++] = ',';
                        first = false;
                        tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                                         "\"error_message\":\"%s\"", val);
                    } else if (strcmp(rkey, "data") == 0 && cbor_value_is_map(&result_iter)) {
                        /* Encode data sub-map as "result" in telemetry */
                        if (!first && tpos < sizeof(telemetry_json) - 2) telemetry_json[tpos++] = ',';
                        first = false;
                        tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                                         "\"result\":{");

                        CborValue data_iter;
                        bool data_first = true;
                        if (cbor_value_enter_container(&result_iter, &data_iter) == CborNoError) {
                            while (!cbor_value_at_end(&data_iter)) {
                                if (!cbor_value_is_text_string(&data_iter)) {
                                    cbor_value_advance(&data_iter);
                                    if (!cbor_value_at_end(&data_iter)) cbor_value_advance(&data_iter);
                                    continue;
                                }

                                char dkey[32] = {0};
                                size_t dkey_len = sizeof(dkey) - 1;
                                cbor_value_copy_text_string(&data_iter, dkey, &dkey_len, NULL);
                                dkey[dkey_len] = '\0';
                                cbor_value_advance(&data_iter);
                                if (cbor_value_at_end(&data_iter)) break;

                                if (!data_first && tpos < sizeof(telemetry_json) - 2)
                                    telemetry_json[tpos++] = ',';
                                data_first = false;

                                if (cbor_value_is_integer(&data_iter)) {
                                    int64_t val;
                                    cbor_value_get_int64(&data_iter, &val);
                                    tpos += snprintf(&telemetry_json[tpos],
                                                     sizeof(telemetry_json) - tpos,
                                                     "\"%s\":%lld", dkey, (long long)val);
                                } else if (cbor_value_is_text_string(&data_iter)) {
                                    char val[64] = {0};
                                    size_t val_len = sizeof(val) - 1;
                                    cbor_value_copy_text_string(&data_iter, val, &val_len, NULL);
                                    val[val_len] = '\0';
                                    tpos += snprintf(&telemetry_json[tpos],
                                                     sizeof(telemetry_json) - tpos,
                                                     "\"%s\":\"%s\"", dkey, val);
                                } else if (cbor_value_is_boolean(&data_iter)) {
                                    bool val;
                                    cbor_value_get_boolean(&data_iter, &val);
                                    tpos += snprintf(&telemetry_json[tpos],
                                                     sizeof(telemetry_json) - tpos,
                                                     "\"%s\":%s", dkey, val ? "true" : "false");
                                }

                                cbor_value_advance(&data_iter);
                            }
                            cbor_value_leave_container(&result_iter, &data_iter);
                        }

                        if (tpos < sizeof(telemetry_json) - 2) {
                            telemetry_json[tpos++] = '}';
                        }
                        /* leave_container already advanced result_iter past the map */
                        continue;
                    }

                    cbor_value_advance(&result_iter);
                }
                cbor_value_leave_container(&map_iter, &result_iter);
            }
            continue;
        }

        /* Normal flat key-value: add to telemetry JSON */
        if (!first && tpos < sizeof(telemetry_json) - 2) {
            telemetry_json[tpos++] = ',';
        }
        first = false;

        if (cbor_value_is_integer(&map_iter)) {
            int64_t val;
            cbor_value_get_int64(&map_iter, &val);
            tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                             "\"%s\":%lld", key, (long long)val);
        } else if (cbor_value_is_text_string(&map_iter)) {
            char val[64] = {0};
            size_t val_len = sizeof(val) - 1;
            cbor_value_copy_text_string(&map_iter, val, &val_len, NULL);
            val[val_len] = '\0';
            tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                             "\"%s\":\"%s\"", key, val);
        } else if (cbor_value_is_boolean(&map_iter)) {
            bool val;
            cbor_value_get_boolean(&map_iter, &val);
            tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                             "\"%s\":%s", key, val ? "true" : "false");
        } else if (cbor_value_is_float(&map_iter) || cbor_value_is_double(&map_iter)) {
            double val;
            if (cbor_value_is_float(&map_iter)) {
                float fval;
                cbor_value_get_float(&map_iter, &fval);
                val = fval;
            } else {
                cbor_value_get_double(&map_iter, &val);
            }
            tpos += snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos,
                             "\"%s\":%.2f", key, val);
        }

        cbor_value_advance(&map_iter);
    }

    snprintf(&telemetry_json[tpos], sizeof(telemetry_json) - tpos, "}");

    /* Get hub identity for relay fields */
    char hub_unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "UNIT-UNKNOWN";
    supabase_get_unit_id(hub_unit_id, sizeof(hub_unit_id));

    /*
     * Build device_heartbeats JSON (created_at defaults to now() server-side).
     * Include command_id as a top-level column when present (for command ack/result).
     */
    char json[1280];
    int json_len;
    if (command_id_str[0] != '\0') {
        json_len = snprintf(json, sizeof(json),
            "{\"mac_address\":\"%s\",\"unit_id\":\"%s\",\"device_type\":\"%s\","
            "\"firmware_version\":\"%s\",\"type\":\"%s\","
            "\"command_id\":\"%s\","
            "\"telemetry\":%s,"
            "\"relay_device_type\":\"hub\",\"relay_instance_id\":\"%s\"}",
            identity->mac, identity->unit_id, identity->device_type,
            identity->fw_version, type_str,
            command_id_str,
            telemetry_json,
            hub_unit_id);
    } else {
        json_len = snprintf(json, sizeof(json),
            "{\"mac_address\":\"%s\",\"unit_id\":\"%s\",\"device_type\":\"%s\","
            "\"firmware_version\":\"%s\",\"type\":\"%s\","
            "\"telemetry\":%s,"
            "\"relay_device_type\":\"hub\",\"relay_instance_id\":\"%s\"}",
            identity->mac, identity->unit_id, identity->device_type,
            identity->fw_version, type_str,
            telemetry_json,
            hub_unit_id);
    }

    if (json_len >= (int)sizeof(json)) {
        ESP_LOGE(TAG, "Crate telemetry JSON too long");
        return ESP_ERR_INVALID_SIZE;
    }

    ESP_LOGI(TAG, "Sending crate telemetry: mac=%s, type=%s", identity->mac, type_str);

    supabase_response_t response;
    esp_err_t ret = supabase_post("device_heartbeats", json, &response, 0);

    if (ret == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGI(TAG, "Crate telemetry sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (ret == ESP_OK) {
        ESP_LOGW(TAG, "Crate telemetry POST failed with status %d", response.status_code);
        ret = ESP_FAIL;
    }
    supabase_response_free(&response);
    return ret;
}
