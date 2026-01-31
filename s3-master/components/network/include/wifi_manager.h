/**
 * @file wifi_manager.h
 * @brief Wi-Fi connection management for Saturday Vinyl Hub
 *
 * Provides Wi-Fi station mode functionality with automatic reconnection,
 * exponential backoff, and event-based state notifications.
 *
 * Phase 4: Wi-Fi Connectivity
 */

#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Wi-Fi connection states
 */
typedef enum {
    WIFI_STATE_DISCONNECTED,    /**< Not connected to any network */
    WIFI_STATE_CONNECTING,      /**< Connection attempt in progress */
    WIFI_STATE_CONNECTED,       /**< Connected and has IP address */
    WIFI_STATE_RECONNECTING,    /**< Lost connection, attempting to reconnect */
} wifi_state_t;

/**
 * @brief Wi-Fi event base for application events
 */
ESP_EVENT_DECLARE_BASE(WIFI_MANAGER_EVENTS);

/**
 * @brief Wi-Fi manager events (posted to default event loop)
 */
typedef enum {
    WIFI_MANAGER_EVENT_CONNECTED,       /**< Successfully connected with IP */
    WIFI_MANAGER_EVENT_DISCONNECTED,    /**< Disconnected from network */
    WIFI_MANAGER_EVENT_CONNECTION_FAILED, /**< Failed to connect (bad credentials, etc.) */
} wifi_manager_event_t;

/**
 * @brief Wi-Fi connection info (included with CONNECTED event)
 */
typedef struct {
    char ssid[33];          /**< Connected SSID */
    int8_t rssi;            /**< Signal strength in dBm */
    uint32_t ip_addr;       /**< IP address (network byte order) */
    uint32_t gateway;       /**< Gateway address */
    uint32_t netmask;       /**< Netmask */
} wifi_connection_info_t;

/**
 * @brief Wi-Fi connection failure info (included with CONNECTION_FAILED event)
 *
 * Contains the underlying WiFi disconnect reason code to help consumers
 * distinguish between auth failures, network not found, and other errors.
 */
typedef struct {
    uint8_t reason;         /**< WiFi disconnect reason (wifi_err_reason_t) */
} wifi_connection_failed_info_t;

/**
 * @brief Wi-Fi manager status
 */
typedef struct {
    wifi_state_t state;         /**< Current connection state */
    char ssid[33];              /**< Current or last SSID */
    int8_t rssi;                /**< Current RSSI (if connected) */
    uint32_t ip_addr;           /**< IP address (if connected) */
    uint32_t connect_attempts;  /**< Total connection attempts */
    uint32_t disconnect_count;  /**< Number of disconnects */
    int64_t connected_time_us;  /**< Time when connected (esp_timer_get_time) */
} wifi_manager_status_t;

/**
 * @brief Initialize the Wi-Fi manager
 *
 * Initializes the Wi-Fi driver, netif, and event handlers.
 * Must be called before any other Wi-Fi functions.
 * Requires NVS and default event loop to be initialized.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t wifi_init(void);

/**
 * @brief Connect to a Wi-Fi network
 *
 * Starts connection attempt to the specified network.
 * Connection result is reported via WIFI_MANAGER_EVENTS.
 * If already connected, disconnects first.
 *
 * @param ssid Network SSID (max 32 chars)
 * @param password Network password (max 64 chars, NULL for open networks)
 * @return ESP_OK if connection started, error code otherwise
 */
esp_err_t wifi_connect(const char *ssid, const char *password);

/**
 * @brief Connect using stored credentials
 *
 * Attempts to connect using credentials stored in NVS.
 *
 * @return ESP_OK if connection started, ESP_ERR_NOT_FOUND if no credentials
 */
esp_err_t wifi_connect_stored(void);

/**
 * @brief Disconnect from current network
 *
 * Stops any reconnection attempts and disconnects.
 *
 * @return ESP_OK on success
 */
esp_err_t wifi_disconnect(void);

/**
 * @brief Check if Wi-Fi is connected
 *
 * @return true if connected with valid IP, false otherwise
 */
bool wifi_is_connected(void);

/**
 * @brief Get current Wi-Fi state
 *
 * @return Current wifi_state_t value
 */
wifi_state_t wifi_get_state(void);

/**
 * @brief Get current RSSI (signal strength)
 *
 * @return RSSI in dBm, or 0 if not connected
 */
int8_t wifi_get_rssi(void);

/**
 * @brief Get full status information
 *
 * @param status Pointer to status structure to fill
 * @return ESP_OK on success
 */
esp_err_t wifi_get_status(wifi_manager_status_t *status);

/**
 * @brief Get IP address as string
 *
 * @param ip_str Buffer for IP string (min 16 bytes)
 * @param max_len Buffer size
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if not connected
 */
esp_err_t wifi_get_ip_string(char *ip_str, size_t max_len);

/**
 * @brief Enable or disable auto-reconnect
 *
 * Auto-reconnect is enabled by default. When enabled, the manager
 * will automatically attempt to reconnect with exponential backoff
 * (1s, 2s, 4s, ... up to 60s) when connection is lost.
 *
 * @param enable true to enable, false to disable
 */
void wifi_set_auto_reconnect(bool enable);

/**
 * @brief Check if system time has been synchronized via SNTP
 *
 * Time synchronization is required for TLS certificate validation.
 * SNTP sync starts automatically after Wi-Fi connects.
 *
 * @return true if time is synchronized, false otherwise
 */
bool wifi_is_time_synced(void);

/**
 * @brief Deinitialize the Wi-Fi manager
 *
 * Disconnects and frees all resources.
 *
 * @return ESP_OK on success
 */
esp_err_t wifi_manager_deinit(void);

/**
 * @brief Get the Wi-Fi station netif
 *
 * Returns the esp_netif_t handle for the Wi-Fi station interface.
 * Used by Thread Border Router to set up backbone interface.
 *
 * @return esp_netif_t pointer, or NULL if not initialized
 */
struct esp_netif_obj *wifi_get_netif(void);

#ifdef __cplusplus
}
#endif

#endif /* WIFI_MANAGER_H */
