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
#define EVENT_QUEUE_DEFAULT_SIZE    32

/**
 * @brief Default heartbeat interval in seconds
 */
#define HEARTBEAT_DEFAULT_INTERVAL_SEC  30   /* 30 seconds for testing */

/**
 * @brief Event reporter configuration
 */
typedef struct {
    uint16_t queue_size;            /**< Maximum events in queue (default: 32) */
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
    uint32_t min_free_heap;     /**< Minimum free heap seen (PROD-2.3) */
    uint32_t low_heap_warnings; /**< Low heap warning count (PROD-2.3) */
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

/*******************************************************************************
 * H2/Crate Event Reporting (INT-2: Full Pipeline)
 ******************************************************************************/

/**
 * @brief Queue a crate inventory update event
 *
 * Called when H2 forwards inventory update from a crate.
 *
 * @param crate_ext_addr Extended MAC address of crate (8 bytes)
 * @param epcs Array of EPC values (12 bytes each)
 * @param epc_count Number of EPCs in array (max 75)
 * @return ESP_OK on success
 */
esp_err_t event_reporter_queue_inventory(const uint8_t *crate_ext_addr,
                                          const uint8_t (*epcs)[12],
                                          uint8_t epc_count);

/**
 * @brief Queue a crate heartbeat event
 *
 * Called when H2 forwards heartbeat from a crate.
 *
 * @param crate_ext_addr Extended MAC address of crate (8 bytes)
 * @param battery_percent Battery level (0-100)
 * @param rssi Signal strength (dBm)
 * @return ESP_OK on success
 */
esp_err_t event_reporter_queue_crate_heartbeat(const uint8_t *crate_ext_addr,
                                                uint8_t battery_percent,
                                                int8_t rssi);

/**
 * @brief Update H2 connection state
 *
 * Called when H2 connection state changes. Included in heartbeats.
 *
 * @param connected true if H2 is responding
 * @param thread_state Current Thread BR state (if connected)
 */
void event_reporter_set_h2_state(bool connected, uint8_t thread_state);

/*******************************************************************************
 * CoAP Mesh Protocol — Telemetry and Identity Cache
 ******************************************************************************/

/**
 * @brief Queue CBOR telemetry from a mesh node
 *
 * Decodes CBOR, resolves device identity from cache, and posts
 * to device_heartbeats with relay fields.
 *
 * @param crate_ext_addr Node extended MAC address (8 bytes)
 * @param hb_type Heartbeat type (S3H2_HB_TYPE_*)
 * @param cbor_data Raw CBOR payload
 * @param cbor_len CBOR payload length
 * @return ESP_OK on success
 */
esp_err_t event_reporter_queue_crate_telemetry(const uint8_t *crate_ext_addr,
                                                uint8_t hb_type,
                                                const uint8_t *cbor_data,
                                                uint16_t cbor_len);

/**
 * @brief Cache crate identity from registration event
 *
 * Called when H2 forwards a CoAP /register event. Stores the mapping
 * from ext_addr to device identity (mac, unit_id, device_type, fw_version).
 *
 * @param ext_addr Node extended MAC address (8 bytes)
 * @param mac WiFi MAC string
 * @param unit_id Supabase unit UUID
 * @param device_type Device type slug
 * @param fw_version Firmware version string
 */
void event_reporter_cache_crate_identity(const uint8_t *ext_addr,
                                          const char *mac,
                                          const char *unit_id,
                                          const char *device_type,
                                          const char *fw_version);

/**
 * @brief Look up crate extended address by MAC
 *
 * Searches the crate identity cache for a device with matching MAC address.
 *
 * @param mac MAC address string (e.g., "AA:BB:CC:DD:EE:FF")
 * @param ext_addr_out Output: 8-byte extended address
 * @return true if found, false if not in cache
 */
bool event_reporter_lookup_crate_ext_addr(const char *mac, uint8_t *ext_addr_out);

/**
 * @brief Look up crate identity fields by MAC
 *
 * Searches the crate identity cache and copies unit_id, device_type,
 * and fw_version into caller-provided buffers.
 *
 * @param mac MAC address string (e.g., "AA:BB:CC:DD:EE:FF")
 * @param unit_id Output buffer for unit ID (may be NULL to skip)
 * @param unit_id_len Size of unit_id buffer
 * @param device_type Output buffer for device type (may be NULL to skip)
 * @param device_type_len Size of device_type buffer
 * @param fw_version Output buffer for firmware version (may be NULL to skip)
 * @param fw_version_len Size of fw_version buffer
 * @return true if found, false if not in cache
 */
bool event_reporter_lookup_crate_identity(const char *mac,
                                           char *unit_id, size_t unit_id_len,
                                           char *device_type, size_t device_type_len,
                                           char *fw_version, size_t fw_version_len);

#ifdef __cplusplus
}
#endif

#endif /* EVENT_REPORTER_H */
