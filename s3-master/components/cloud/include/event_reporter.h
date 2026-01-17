/**
 * @file event_reporter.h
 * @brief Event queue and cloud reporting interface
 *
 * Manages event queuing and reporting to Supabase for the Saturday Vinyl Hub.
 * Subscribes to Now Playing events and queues them for cloud synchronization.
 * Provides offline support via an in-memory ring buffer that flushes when
 * Wi-Fi connectivity is restored.
 *
 * Phase 5: Supabase Integration
 */

#ifndef EVENT_REPORTER_H
#define EVENT_REPORTER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief Event reporter event base for ESP-IDF event loop
 */
ESP_EVENT_DECLARE_BASE(EVENT_REPORTER_EVENTS);

/**
 * @brief Event reporter event types
 */
typedef enum {
    EVENT_REPORTER_EVENT_SYNC_START,    /**< Started syncing events to cloud */
    EVENT_REPORTER_EVENT_SYNC_COMPLETE, /**< Finished syncing events to cloud */
    EVENT_REPORTER_EVENT_SYNC_FAILED,   /**< Failed to sync events to cloud */
    EVENT_REPORTER_EVENT_QUEUE_FULL,    /**< Event queue is full, dropping oldest */
} event_reporter_event_type_t;

/**
 * @brief Event reporter sync event data
 */
typedef struct {
    uint32_t events_synced;     /**< Number of events successfully synced */
    uint32_t events_failed;     /**< Number of events that failed to sync */
    uint32_t events_queued;     /**< Number of events remaining in queue */
} event_reporter_sync_data_t;

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief Default event queue size (number of events)
 */
#define EVENT_QUEUE_DEFAULT_SIZE    100

/**
 * @brief Default heartbeat interval in seconds
 */
#define HEARTBEAT_DEFAULT_INTERVAL_SEC  30   /* 30 seconds for testing */

/**
 * @brief Event reporter configuration
 */
typedef struct {
    uint16_t queue_size;            /**< Maximum events in queue (default: 100) */
    uint16_t heartbeat_interval_sec;/**< Heartbeat interval in seconds (default: 300) */
    bool enable_heartbeat;          /**< Enable periodic heartbeat (default: true) */
} event_reporter_config_t;

/**
 * @brief Default configuration
 */
#define EVENT_REPORTER_CONFIG_DEFAULT() { \
    .queue_size = EVENT_QUEUE_DEFAULT_SIZE, \
    .heartbeat_interval_sec = HEARTBEAT_DEFAULT_INTERVAL_SEC, \
    .enable_heartbeat = true, \
}

/*******************************************************************************
 * Status
 ******************************************************************************/

/**
 * @brief Event reporter status
 */
typedef struct {
    bool initialized;           /**< Reporter is initialized */
    bool running;               /**< Background task is running */
    bool wifi_connected;        /**< Wi-Fi is currently connected */
    bool supabase_configured;   /**< Supabase is configured */
    uint32_t events_queued;     /**< Events waiting in queue */
    uint32_t events_sent;       /**< Total events sent successfully */
    uint32_t events_failed;     /**< Total events that failed to send */
    uint32_t events_dropped;    /**< Events dropped due to full queue */
    uint32_t heartbeats_sent;   /**< Total heartbeats sent */
    int64_t last_sync_time;     /**< Last successful sync timestamp (us) */
    int64_t last_heartbeat_time;/**< Last heartbeat timestamp (us) */
} event_reporter_status_t;

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the event reporter
 *
 * Creates event queue and registers for Now Playing and Wi-Fi events.
 * Does not start background sync task (call event_reporter_start).
 *
 * @param config Configuration (NULL for defaults)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t event_reporter_init(const event_reporter_config_t *config);

/**
 * @brief Deinitialize the event reporter
 *
 * Stops background task and frees resources.
 * Queued events will be lost.
 *
 * @return ESP_OK on success
 */
esp_err_t event_reporter_deinit(void);

/**
 * @brief Start the event reporter background task
 *
 * Begins processing queued events and sending to Supabase.
 * Events are only sent when Wi-Fi is connected.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t event_reporter_start(void);

/**
 * @brief Stop the event reporter background task
 *
 * Stops processing events but keeps queue intact.
 *
 * @return ESP_OK on success
 */
esp_err_t event_reporter_stop(void);

/**
 * @brief Get current status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t event_reporter_get_status(event_reporter_status_t *status);

/**
 * @brief Force immediate sync attempt
 *
 * Attempts to send all queued events immediately.
 * Blocks until complete or timeout.
 *
 * @param timeout_ms Maximum time to wait in ms (0 for no timeout)
 * @return ESP_OK if all events sent, error code otherwise
 */
esp_err_t event_reporter_flush(uint32_t timeout_ms);

/**
 * @brief Send heartbeat immediately
 *
 * Sends a hub heartbeat to Supabase right now.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t event_reporter_send_heartbeat(void);

/**
 * @brief Clear the event queue
 *
 * Drops all queued events without sending.
 *
 * @return ESP_OK on success
 */
esp_err_t event_reporter_clear_queue(void);

/**
 * @brief Update Wi-Fi connection state
 *
 * Called by main application when Wi-Fi state changes.
 * Triggers sync when connectivity is restored.
 *
 * @param connected true if Wi-Fi is connected
 */
void event_reporter_set_wifi_state(bool connected);

#ifdef __cplusplus
}
#endif

#endif /* EVENT_REPORTER_H */
