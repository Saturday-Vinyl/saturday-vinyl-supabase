/**
 * @file realtime_client.h
 * @brief Supabase Realtime WebSocket client for push notifications
 *
 * Connects to Supabase Realtime to receive push notifications for:
 * - OTA firmware updates
 * - Device commands
 * - Configuration updates
 *
 * This enables remote update triggering from admin/consumer apps.
 *
 * OTA Push Protocol Implementation (Phase 2)
 */

#ifndef REALTIME_CLIENT_H
#define REALTIME_CLIENT_H

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
 * @brief Realtime client event base
 */
ESP_EVENT_DECLARE_BASE(REALTIME_EVENTS);

/**
 * @brief Realtime event types
 */
typedef enum {
    REALTIME_EVENT_CONNECTED,       /**< Connected to Supabase Realtime */
    REALTIME_EVENT_DISCONNECTED,    /**< Disconnected from Supabase Realtime */
    REALTIME_EVENT_UPDATE_AVAILABLE,/**< OTA update notification received */
    REALTIME_EVENT_COMMAND,         /**< Device command received */
    REALTIME_EVENT_CONFIG_UPDATE,   /**< Configuration update received */
    REALTIME_EVENT_ERROR,           /**< Error occurred */
} realtime_event_type_t;

/*******************************************************************************
 * Data Structures
 ******************************************************************************/

/**
 * @brief Component update information (for dual-SoC devices)
 */
typedef struct {
    char type[16];              /**< Component type: "hub_s3", "hub_h2" */
    char version[16];           /**< Firmware version (e.g., "1.2.3") */
    char download_url[256];     /**< URL to download firmware */
    uint32_t firmware_size;     /**< Firmware size in bytes */
    char sha256[65];            /**< SHA-256 hash (hex string) */
} realtime_component_t;

/**
 * @brief OTA update available event data
 */
typedef struct {
    char request_id[40];        /**< Update request UUID */
    char device_type[16];       /**< "hub", "hub_s3", "hub_h2", "crate" */
    bool is_critical;           /**< Critical security/stability update */
    uint8_t component_count;    /**< Number of components (1 or 2 for hub) */
    realtime_component_t components[2];  /**< Component details */
} realtime_update_event_t;

/**
 * @brief Device command event data
 */
typedef struct {
    char command_id[40];        /**< Command UUID */
    char command[32];           /**< Command name (e.g., "reboot", "factory_reset") */
    char parameters[1024];      /**< JSON parameters string (sized for ota_update firmware URLs) */
} realtime_command_event_t;

/**
 * @brief Realtime client status
 */
typedef struct {
    bool initialized;           /**< Client is initialized */
    bool connected;             /**< Currently connected to Realtime */
    bool subscribed;            /**< Subscribed to device channel */
    uint32_t reconnect_count;   /**< Number of reconnections */
    int64_t last_message_time;  /**< Timestamp of last message (us) */
    uint32_t messages_received; /**< Total messages received */
    uint32_t updates_received;  /**< OTA updates received */
    uint32_t commands_received; /**< Commands received */
} realtime_status_t;

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief Realtime client configuration
 */
typedef struct {
    bool auto_connect;          /**< Auto-connect when WiFi is available */
    bool auto_apply_updates;    /**< Auto-apply OTA updates when received */
    uint32_t reconnect_delay_ms;/**< Delay between reconnection attempts */
    uint32_t heartbeat_interval_ms; /**< WebSocket heartbeat interval */
} realtime_config_t;

/**
 * @brief Default configuration
 */
#define REALTIME_CONFIG_DEFAULT() { \
    .auto_connect = true, \
    .auto_apply_updates = true, \
    .reconnect_delay_ms = 5000, \
    .heartbeat_interval_ms = 30000, \
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the Realtime client
 *
 * Sets up WebSocket client and event handlers.
 * Call after supabase_init() and network initialization.
 *
 * @param config Configuration (NULL for defaults)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t realtime_client_init(const realtime_config_t *config);

/**
 * @brief Deinitialize the Realtime client
 *
 * Disconnects and releases all resources.
 *
 * @return ESP_OK on success
 */
esp_err_t realtime_client_deinit(void);

/**
 * @brief Connect to Supabase Realtime
 *
 * Establishes WebSocket connection and subscribes to device channel.
 * Requires Supabase to be configured and WiFi to be connected.
 *
 * @return ESP_OK if connection started, error code otherwise
 */
esp_err_t realtime_client_connect(void);

/**
 * @brief Disconnect from Supabase Realtime
 *
 * Gracefully closes WebSocket connection.
 *
 * @return ESP_OK on success
 */
esp_err_t realtime_client_disconnect(void);

/**
 * @brief Check if connected to Realtime
 *
 * @return true if connected and subscribed
 */
bool realtime_client_is_connected(void);

/**
 * @brief Get client status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t realtime_client_get_status(realtime_status_t *status);

/**
 * @brief Acknowledge an update request
 *
 * Reports status back to cloud for the given update request.
 * Call this as update progresses through states.
 *
 * @param request_id Update request UUID
 * @param status Status string ("notified", "downloading", "applying", "complete", "failed")
 * @param component Optional component type for dual-SoC ("hub_s3", "hub_h2", NULL for single)
 * @param error_message Optional error message (for "failed" status)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t realtime_client_ack_update(const char *request_id, const char *status,
                                      const char *component, const char *error_message);

/**
 * @brief Acknowledge a command
 *
 * Reports command completion back to cloud.
 *
 * @param command_id Command UUID
 * @param status Status string ("acknowledged", "completed", "failed")
 * @param result_json Optional JSON result string
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t realtime_client_ack_command(const char *command_id, const char *status,
                                       const char *result_json);

#ifdef __cplusplus
}
#endif

#endif /* REALTIME_CLIENT_H */
