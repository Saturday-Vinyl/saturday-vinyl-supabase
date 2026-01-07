/**
 * @file ble_prov.h
 * @brief BLE provisioning for consumer Wi-Fi setup
 *
 * Implements BLE-based provisioning allowing consumers to configure their
 * Saturday Hub's Wi-Fi credentials using the Saturday mobile app.
 *
 * BLE Service Structure:
 *   Service: Saturday Provisioning (UUID: 5356xxxx-0001-1000-8000-00805f9b34fb)
 *   ├── Status     (Read, Notify)  - Current provisioning state
 *   ├── WiFi SSID  (Write)         - Wi-Fi network name
 *   ├── WiFi Pass  (Write)         - Wi-Fi password
 *   ├── Command    (Write)         - Control commands (connect, reset)
 *   └── Response   (Read, Notify)  - Command responses and errors
 *
 * Provisioning Flow:
 *   1. User long-presses button (3-5s) OR device boots unprovisioned
 *   2. Hub starts BLE advertising as "Saturday Hub XXXX"
 *   3. Saturday app scans and connects via BLE
 *   4. App writes Wi-Fi SSID and password characteristics
 *   5. App writes "connect" command
 *   6. Hub attempts Wi-Fi connection, notifies status
 *   7. On success, hub saves credentials and exits provisioning
 *   8. On failure, hub notifies error and waits for retry
 *
 * Security:
 *   - BLE pairing required for write characteristics
 *   - 5-minute advertising timeout
 *   - Only available when device needs provisioning or button triggered
 *
 * Phase 7: BLE Provisioning
 */

#ifndef BLE_PROV_H
#define BLE_PROV_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/**
 * @brief Saturday Provisioning Service UUID
 * Base: 53560000-0001-1000-8000-00805f9b34fb
 * "5356" = "SV" (Saturday Vinyl) in ASCII
 *
 * See docs/ble_provisioning_protocol.md for full protocol specification.
 */
#define BLE_PROV_SERVICE_UUID           0x0000  /**< Service UUID (short form) */

/**
 * @brief Characteristic UUIDs (16-bit short form, added to base UUID)
 *
 * UUID Ranges:
 *   0x0001-0x000F: Core characteristics (all devices)
 *   0x0010-0x001F: Wi-Fi provisioning
 *   0x0020-0x002F: Thread provisioning
 *   0x0030-0x003F: User/account linking
 */
#define BLE_PROV_CHAR_DEVICE_INFO_UUID  0x0001  /**< Read: Device info (JSON) */
#define BLE_PROV_CHAR_STATUS_UUID       0x0002  /**< Read/Notify: Provisioning status */
#define BLE_PROV_CHAR_COMMAND_UUID      0x0003  /**< Write: Commands */
#define BLE_PROV_CHAR_RESPONSE_UUID     0x0004  /**< Read/Notify: Response (JSON) */
#define BLE_PROV_CHAR_WIFI_SSID_UUID    0x0010  /**< Write: Wi-Fi SSID */
#define BLE_PROV_CHAR_WIFI_PASS_UUID    0x0011  /**< Write: Wi-Fi password */
#define BLE_PROV_CHAR_THREAD_DATASET_UUID 0x0020 /**< Write: Thread dataset */
#define BLE_PROV_CHAR_USER_TOKEN_UUID   0x0030  /**< Write: User auth token */

/**
 * @brief Advertising timeout in seconds (default 5 minutes)
 */
#define BLE_PROV_ADV_TIMEOUT_SEC        300

/**
 * @brief Maximum Wi-Fi credential lengths
 */
#define BLE_PROV_MAX_SSID_LEN           32
#define BLE_PROV_MAX_PASS_LEN           64

/**
 * @brief Maximum response message length
 */
#define BLE_PROV_MAX_RESPONSE_LEN       128

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief BLE provisioning states
 */
typedef enum {
    BLE_PROV_STATE_IDLE,            /**< BLE not active */
    BLE_PROV_STATE_ADVERTISING,     /**< Advertising, waiting for connection */
    BLE_PROV_STATE_CONNECTED,       /**< Connected, awaiting credentials */
    BLE_PROV_STATE_CREDENTIALS_SET, /**< Credentials received, ready to connect */
    BLE_PROV_STATE_CONNECTING_WIFI, /**< Attempting Wi-Fi connection */
    BLE_PROV_STATE_SUCCESS,         /**< Wi-Fi connected, provisioning complete */
    BLE_PROV_STATE_FAILED,          /**< Provisioning failed (bad credentials, etc.) */
    BLE_PROV_STATE_TIMEOUT,         /**< Advertising timed out */
} ble_prov_state_t;

/**
 * @brief BLE provisioning status codes (sent via Status characteristic)
 *
 * See docs/ble_provisioning_protocol.md for full status code reference.
 */
typedef enum {
    /* Normal states (0x00-0x0F) */
    BLE_PROV_STATUS_IDLE = 0x00,            /**< Not in provisioning mode */
    BLE_PROV_STATUS_READY = 0x01,           /**< Ready to receive credentials */
    BLE_PROV_STATUS_CREDENTIALS_OK = 0x02,  /**< Credentials received */
    BLE_PROV_STATUS_CONNECTING = 0x03,      /**< Connecting to network */
    BLE_PROV_STATUS_VERIFYING = 0x04,       /**< Verifying cloud connectivity */
    BLE_PROV_STATUS_SUCCESS = 0x05,         /**< Provisioning complete */

    /* Error states (0x10-0x1F) */
    BLE_PROV_STATUS_ERROR_SSID = 0x10,      /**< Invalid SSID */
    BLE_PROV_STATUS_ERROR_PASS = 0x11,      /**< Invalid password */
    BLE_PROV_STATUS_ERROR_WIFI = 0x12,      /**< Wi-Fi connection failed */
    BLE_PROV_STATUS_ERROR_TIMEOUT = 0x13,   /**< Connection timeout */
    BLE_PROV_STATUS_ERROR_THREAD = 0x14,    /**< Thread join failed */
    BLE_PROV_STATUS_ERROR_CLOUD = 0x15,     /**< Cloud verification failed */
    BLE_PROV_STATUS_ERROR_BUSY = 0x1E,      /**< Device busy */
    BLE_PROV_STATUS_ERROR_UNKNOWN = 0x1F,   /**< Unknown error */
} ble_prov_status_code_t;

/**
 * @brief BLE provisioning commands (received via Command characteristic)
 *
 * See docs/ble_provisioning_protocol.md for full command reference.
 */
typedef enum {
    BLE_PROV_CMD_CONNECT = 0x01,       /**< Attempt connection with stored credentials */
    BLE_PROV_CMD_RESET = 0x02,         /**< Clear credentials and restart */
    BLE_PROV_CMD_GET_STATUS = 0x03,    /**< Request current status */
    BLE_PROV_CMD_SCAN_WIFI = 0x04,     /**< Scan for Wi-Fi networks */
    BLE_PROV_CMD_ABORT = 0x05,         /**< Abort current operation */
    BLE_PROV_CMD_FACTORY_RESET = 0xFF, /**< Factory reset (requires confirmation) */
} ble_prov_command_t;

/**
 * @brief Callback for provisioning state changes
 */
typedef void (*ble_prov_state_callback_t)(ble_prov_state_t state, void *user_data);

/**
 * @brief Callback for provisioning completion
 * @param success true if Wi-Fi configured successfully
 * @param ssid The SSID that was configured (or attempted)
 */
typedef void (*ble_prov_complete_callback_t)(bool success, const char *ssid, void *user_data);

/**
 * @brief BLE provisioning configuration
 */
typedef struct {
    uint16_t adv_timeout_sec;               /**< Advertising timeout (0 = no timeout) */
    bool require_pairing;                   /**< Require BLE pairing for writes */
    ble_prov_state_callback_t state_cb;     /**< State change callback */
    ble_prov_complete_callback_t complete_cb; /**< Completion callback */
    void *user_data;                        /**< User data for callbacks */
} ble_prov_config_t;

/**
 * @brief BLE provisioning status structure
 */
typedef struct {
    ble_prov_state_t state;         /**< Current state */
    bool is_connected;              /**< BLE connection active */
    bool credentials_received;      /**< Wi-Fi credentials have been written */
    char ssid[BLE_PROV_MAX_SSID_LEN + 1]; /**< Received SSID (if any) */
    uint32_t adv_start_time;        /**< When advertising started (for timeout) */
    uint16_t conn_handle;           /**< BLE connection handle */
} ble_prov_status_t;

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize BLE provisioning module
 *
 * Initializes the NimBLE stack and registers the provisioning GATT service.
 * Does not start advertising - call ble_prov_start() for that.
 *
 * @param config Configuration (NULL for defaults)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t ble_prov_init(const ble_prov_config_t *config);

/**
 * @brief Deinitialize BLE provisioning module
 *
 * Stops advertising, disconnects any clients, and cleans up resources.
 *
 * @return ESP_OK on success
 */
esp_err_t ble_prov_deinit(void);

/**
 * @brief Start BLE provisioning (begin advertising)
 *
 * Starts BLE advertising with the Saturday Provisioning service.
 * The device will be discoverable as "Saturday Hub XXXX" where XXXX
 * is derived from the unit ID or MAC address.
 *
 * LED will show blue slow blink to indicate provisioning mode.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t ble_prov_start(void);

/**
 * @brief Stop BLE provisioning
 *
 * Stops advertising and disconnects any connected clients.
 *
 * @return ESP_OK on success
 */
esp_err_t ble_prov_stop(void);

/**
 * @brief Check if BLE provisioning is active
 *
 * @return true if advertising or connected
 */
bool ble_prov_is_active(void);

/**
 * @brief Get current provisioning state
 *
 * @return Current state
 */
ble_prov_state_t ble_prov_get_state(void);

/**
 * @brief Get detailed provisioning status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t ble_prov_get_status(ble_prov_status_t *status);

/**
 * @brief Register callback for state changes
 *
 * @param callback Function to call on state change
 * @param user_data User data passed to callback
 * @return ESP_OK on success
 */
esp_err_t ble_prov_register_state_callback(ble_prov_state_callback_t callback,
                                            void *user_data);

/**
 * @brief Register callback for provisioning completion
 *
 * @param callback Function to call when provisioning completes
 * @param user_data User data passed to callback
 * @return ESP_OK on success
 */
esp_err_t ble_prov_register_complete_callback(ble_prov_complete_callback_t callback,
                                               void *user_data);

/**
 * @brief Check if provisioning completed successfully
 *
 * Returns true after Wi-Fi credentials have been successfully configured
 * and the Wi-Fi connection verified. Use this to know when to exit
 * provisioning mode and continue with normal operation.
 *
 * @return true if provisioning completed successfully
 */
bool ble_prov_is_complete(void);

/**
 * @brief Get the BLE device name
 *
 * Returns the device name used for BLE advertising (e.g., "Saturday Hub A1B2").
 *
 * @param name Buffer for device name
 * @param max_len Buffer length
 * @return ESP_OK on success
 */
esp_err_t ble_prov_get_device_name(char *name, size_t max_len);

/**
 * @brief Convert state to string (for logging)
 *
 * @param state State to convert
 * @return State name string
 */
const char *ble_prov_state_to_string(ble_prov_state_t state);

#ifdef __cplusplus
}
#endif

#endif /* BLE_PROV_H */
