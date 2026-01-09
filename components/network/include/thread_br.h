/**
 * @file thread_br.h
 * @brief Thread Border Router functionality for Saturday Vinyl Hub
 *
 * Provides Thread mesh network management with Border Router capabilities.
 * The hub acts as a Thread Border Router, bridging Thread devices (crates)
 * to the IP network (Wi-Fi) and cloud (Supabase).
 *
 * Phase 8: Thread Border Router
 *
 * @note This module requires CONFIG_OPENTHREAD_ENABLED=y in sdkconfig
 */

#ifndef THREAD_BR_H
#define THREAD_BR_H

#include "sdkconfig.h"

/* Thread BR is only available when OpenThread is enabled */
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/** Thread network key length in bytes */
#define THREAD_NETWORK_KEY_LEN      16

/** Thread Extended PAN ID length in bytes */
#define THREAD_EXTPANID_LEN         8

/** Thread mesh-local prefix length in bytes */
#define THREAD_MESH_LOCAL_PREFIX_LEN 8

/** Maximum network name length */
#define THREAD_NETWORK_NAME_MAX_LEN  16

/** Default Thread network parameters */
#define THREAD_DEFAULT_NETWORK_NAME  "SaturdayVinyl"
#define THREAD_DEFAULT_PAN_ID        0x5356
#define THREAD_DEFAULT_CHANNEL       15

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Thread Border Router states
 */
typedef enum {
    THREAD_BR_STATE_DISABLED,       /**< Thread BR not initialized */
    THREAD_BR_STATE_DETACHED,       /**< Initialized but not attached to network */
    THREAD_BR_STATE_ATTACHING,      /**< Attempting to attach to network */
    THREAD_BR_STATE_CHILD,          /**< Attached as child (rarely used for BR) */
    THREAD_BR_STATE_ROUTER,         /**< Operating as router */
    THREAD_BR_STATE_LEADER,         /**< Operating as network leader */
} thread_br_state_t;

/**
 * @brief Thread Border Router event base
 */
ESP_EVENT_DECLARE_BASE(THREAD_BR_EVENTS);

/**
 * @brief Thread Border Router events (posted to default event loop)
 */
typedef enum {
    THREAD_BR_EVENT_STARTED,        /**< Thread BR started successfully */
    THREAD_BR_EVENT_STOPPED,        /**< Thread BR stopped */
    THREAD_BR_EVENT_ATTACHED,       /**< Attached to Thread network */
    THREAD_BR_EVENT_DETACHED,       /**< Detached from Thread network */
    THREAD_BR_EVENT_ROLE_CHANGED,   /**< Device role changed (router/leader) */
    THREAD_BR_EVENT_DEVICE_JOINED,  /**< A device joined the network */
    THREAD_BR_EVENT_DEVICE_LEFT,    /**< A device left the network */
} thread_br_event_t;

/**
 * @brief Thread network credentials
 *
 * These credentials define a Thread network. They are generated on first boot
 * and stored in NVS for persistence. The mobile app can retrieve these via
 * the cloud to provision new crates.
 */
typedef struct {
    char network_name[THREAD_NETWORK_NAME_MAX_LEN + 1];  /**< Network name */
    uint16_t pan_id;                                     /**< PAN ID */
    uint8_t channel;                                     /**< Radio channel (11-26) */
    uint8_t network_key[THREAD_NETWORK_KEY_LEN];         /**< Network master key */
    uint8_t extended_pan_id[THREAD_EXTPANID_LEN];        /**< Extended PAN ID */
    uint8_t mesh_local_prefix[THREAD_MESH_LOCAL_PREFIX_LEN]; /**< Mesh-local prefix */
    uint32_t pskc[4];                                    /**< Pre-Shared Key for Commissioner */
} thread_network_credentials_t;

/**
 * @brief Thread Border Router status
 */
typedef struct {
    thread_br_state_t state;        /**< Current BR state */
    uint16_t pan_id;                /**< Current PAN ID */
    uint8_t channel;                /**< Current channel */
    char network_name[THREAD_NETWORK_NAME_MAX_LEN + 1]; /**< Current network name */
    uint16_t rloc16;                /**< Router Locator (16-bit address) */
    uint8_t device_count;           /**< Number of devices on network */
    bool border_routing_enabled;    /**< Whether border routing is active */
    int64_t attached_time_us;       /**< Time when attached (esp_timer_get_time) */
} thread_br_status_t;

/**
 * @brief Thread device info (for join/leave events)
 */
typedef struct {
    uint16_t rloc16;                /**< Router Locator */
    uint8_t ext_addr[8];            /**< Extended MAC address */
    bool is_child;                  /**< True if child, false if router */
} thread_device_info_t;

/*******************************************************************************
 * Initialization and Lifecycle
 ******************************************************************************/

/**
 * @brief Initialize the Thread Border Router
 *
 * Initializes the OpenThread stack and configures the Border Router.
 * Does not start the network - call thread_br_start() for that.
 * Requires NVS to be initialized for credential storage.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_init(void);

/**
 * @brief Start the Thread Border Router
 *
 * Forms or joins the Thread network using stored credentials.
 * If no credentials exist, generates new network credentials.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_start(void);

/**
 * @brief Stop the Thread Border Router
 *
 * Detaches from the Thread network and stops the BR.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_stop(void);

/**
 * @brief Deinitialize the Thread Border Router
 *
 * Stops the BR and releases all resources.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_deinit(void);

/*******************************************************************************
 * Status and Information
 ******************************************************************************/

/**
 * @brief Check if Thread BR is running
 *
 * @return true if running and attached to network, false otherwise
 */
bool thread_br_is_running(void);

/**
 * @brief Get current Thread BR state
 *
 * @return Current thread_br_state_t value
 */
thread_br_state_t thread_br_get_state(void);

/**
 * @brief Get state as human-readable string
 *
 * @param state State to convert
 * @return String representation of state
 */
const char *thread_br_state_to_string(thread_br_state_t state);

/**
 * @brief Get full status information
 *
 * @param status Pointer to status structure to fill
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_get_status(thread_br_status_t *status);

/**
 * @brief Get number of devices on the Thread network
 *
 * @return Number of devices (including self), or 0 if not running
 */
uint8_t thread_br_get_device_count(void);

/*******************************************************************************
 * Network Credentials
 ******************************************************************************/

/**
 * @brief Check if Thread network credentials are stored
 *
 * @return true if credentials exist in NVS, false otherwise
 */
bool thread_br_has_credentials(void);

/**
 * @brief Get Thread network credentials
 *
 * Returns the current network credentials. These are generated on first boot
 * if they don't exist.
 *
 * @param creds Pointer to credentials structure to fill
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if no credentials
 */
esp_err_t thread_br_get_credentials(thread_network_credentials_t *creds);

/**
 * @brief Ensure Thread credentials exist (generate if needed)
 *
 * Checks if credentials exist in NVS. If not, generates new random credentials.
 * This function does NOT require the Thread stack to be initialized.
 * Used by service mode to ensure credentials are available for get_status
 * before the full Thread BR is started.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_ensure_credentials(void);

/**
 * @brief Get network key as hex string (for cloud sync)
 *
 * @param hex_str Buffer for hex string (min 33 bytes)
 * @param max_len Buffer size
 * @return ESP_OK on success
 */
esp_err_t thread_br_get_network_key_hex(char *hex_str, size_t max_len);

/**
 * @brief Get extended PAN ID as hex string (for cloud sync)
 *
 * @param hex_str Buffer for hex string (min 17 bytes)
 * @param max_len Buffer size
 * @return ESP_OK on success
 */
esp_err_t thread_br_get_extpanid_hex(char *hex_str, size_t max_len);

/**
 * @brief Generate new network credentials
 *
 * Generates new random network credentials and stores them in NVS.
 * Used for factory reset or initial setup.
 * WARNING: This will require all existing devices to be re-commissioned!
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_generate_credentials(void);

/**
 * @brief Clear stored credentials
 *
 * Removes credentials from NVS. Next start will generate new ones.
 *
 * @return ESP_OK on success
 */
esp_err_t thread_br_clear_credentials(void);

/*******************************************************************************
 * Commissioning
 ******************************************************************************/

/**
 * @brief Enable commissioner mode for joining new devices
 *
 * Enables the Thread Commissioner role, allowing new devices to join
 * the network for a specified duration.
 *
 * @param duration_sec How long to allow joining (0 = indefinite until disabled)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_enable_joining(uint32_t duration_sec);

/**
 * @brief Disable commissioner mode
 *
 * Stops accepting new device joins.
 *
 * @return ESP_OK on success
 */
esp_err_t thread_br_disable_joining(void);

/**
 * @brief Check if commissioner mode is enabled
 *
 * @return true if accepting new device joins
 */
bool thread_br_is_joining_enabled(void);

#ifdef __cplusplus
}
#endif

#endif /* CONFIG_OPENTHREAD_ENABLED */

#endif /* THREAD_BR_H */
