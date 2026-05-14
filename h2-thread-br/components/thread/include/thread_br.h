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
    THREAD_BR_STATE_UNPROVISIONED,  /**< Initialized, NVS empty, idling - waiting for S3 to push credentials via CMD_SET_CREDENTIALS */
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
 * These credentials define a Thread network. They are issued by the cloud
 * `adopt_device` edge function (once per user account, on first Hub adoption),
 * fetched by S3 over HTTPS, and pushed to the H2 via CMD_SET_CREDENTIALS.
 *
 * H2 never generates these locally - the H2 stays in UNPROVISIONED state until
 * S3 hands it credentials. See .context/thread-credential-architecture.md.
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
    uint32_t partition_id;          /**< Thread partition ID (0 if not attached) */
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
 * If credentials exist in NVS, forms/joins the Thread network using them.
 * If NVS is empty, transitions to THREAD_BR_STATE_UNPROVISIONED and returns
 * ESP_OK without starting OpenThread - the H2 idles waiting for S3 to push
 * credentials via thread_br_set_credentials() / CMD_SET_CREDENTIALS.
 *
 * @return ESP_OK on success (including the unprovisioned-idle case),
 *         error code on real failures
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

/**
 * @brief Suspend Thread radio for WiFi-exclusive operations
 *
 * Temporarily disables Thread radio to give WiFi exclusive access to the
 * shared radio. This is useful during cloud sync operations where reliable
 * TLS connections require uninterrupted WiFi access.
 *
 * The Thread stack remains initialized but the radio is disabled. Call
 * thread_br_resume() to re-enable Thread after the WiFi operation completes.
 *
 * @note Must be paired with thread_br_resume(). Do not call stop() while suspended.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_suspend(void);

/**
 * @brief Resume Thread radio after suspension
 *
 * Re-enables Thread radio after a suspend operation. Thread will automatically
 * re-attach to the network.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_resume(void);

/**
 * @brief Check if Thread is currently suspended
 *
 * @return true if suspended, false if running normally
 */
bool thread_br_is_suspended(void);

/**
 * @brief Completely shutdown Thread for WiFi-exclusive cloud sync
 *
 * Performs a full OpenThread stack shutdown, completely releasing the 802.15.4
 * radio for WiFi-exclusive operation. This is more aggressive than suspend()
 * and should be used when suspend() doesn't provide reliable WiFi connectivity.
 *
 * The Thread credentials are preserved in NVS. Call thread_br_restart_after_wifi()
 * after the WiFi operation completes to reinitialize Thread.
 *
 * @note This takes longer than suspend/resume (~1-2 seconds each way) but provides
 *       guaranteed WiFi-exclusive radio access.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_shutdown_for_wifi(void);

/**
 * @brief Restart Thread after WiFi-exclusive operation
 *
 * Reinitializes the OpenThread stack after a shutdown_for_wifi() call.
 * Reloads credentials from NVS and re-attaches to the Thread network.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_restart_after_wifi(void);

/**
 * @brief Check if Thread is shutdown for WiFi
 *
 * @return true if Thread is completely shutdown for WiFi operation
 */
bool thread_br_is_shutdown_for_wifi(void);

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
 * @brief Check whether Thread credentials exist in NVS
 *
 * In the cloud-canonical architecture, credentials are pushed by the S3 via
 * CMD_SET_CREDENTIALS - they are never generated locally. This function is a
 * thin existence check.
 *
 * @return ESP_OK if credentials are present, ESP_ERR_NOT_FOUND otherwise
 */
esp_err_t thread_br_ensure_credentials(void);

/**
 * @brief Set Thread credentials and (re)start the Thread network
 *
 * Persists the supplied credentials to NVS and starts the Thread stack with
 * them. If Thread is already running, the stack is restarted with the new
 * dataset. Called when S3 receives credentials from the cloud `adopt_device`
 * or `get_thread_credentials` edge function and pushes them via UART.
 *
 * @param creds Pointer to the credentials to install
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_set_credentials(const thread_network_credentials_t *creds);

/**
 * @brief Clear Thread credentials and stop the Thread network
 *
 * Stops the Thread stack and erases the sv_thread NVS namespace. After this
 * the H2 returns to UNPROVISIONED state. Called on consumer reset and when
 * the device is unadopted.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t thread_br_clear_credentials_and_stop(void);

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
 * @brief Generate new network credentials (legacy / diagnostic only)
 *
 * Generates new random network credentials and stores them in NVS. In the
 * cloud-canonical architecture this is NOT called on the boot path - the H2
 * idles in UNPROVISIONED until S3 pushes creds from the cloud. Kept available
 * for diagnostic / test paths only; do not invoke from new code.
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
