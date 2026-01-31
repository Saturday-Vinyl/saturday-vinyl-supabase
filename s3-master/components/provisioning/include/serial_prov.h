/**
 * @file serial_prov.h
 * @brief Service Mode for factory provisioning and servicing via Saturday Admin app
 *
 * Implements the Saturday Service Mode Protocol for factory provisioning, testing,
 * and device servicing. Uses USB serial for communication with the Admin desktop app.
 *
 * Service Mode Entry:
 * - Fresh devices (no unit_id): Auto-enter service mode on boot
 * - Provisioned devices: Send {"cmd":"enter_service_mode"} during 10-second boot window
 *
 * Protocol:
 * - Transport: USB Serial/JTAG at 115200 baud, 8N1
 * - Messages are JSON objects terminated by newline (\n)
 * - Device sends periodic status beacons in service mode
 * - Host sends commands, device responds with results
 *
 * See docs/service_mode_protocol.md for full protocol specification.
 *
 * Phase 6: Service Mode
 */

#ifndef SERIAL_PROV_H
#define SERIAL_PROV_H

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
 * @brief Maximum length for a serial message (JSON + newline)
 */
#define SERIAL_PROV_MAX_MSG_LEN     2048

/**
 * @brief Interval for sending status messages when awaiting provisioning (ms)
 */
#define SERIAL_PROV_STATUS_INTERVAL_MS  2000

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Serial provisioning states
 */
typedef enum {
    SERIAL_PROV_STATE_IDLE,             /**< Not in provisioning mode */
    SERIAL_PROV_STATE_AWAITING,         /**< Awaiting provisioning commands */
    SERIAL_PROV_STATE_PROVISIONING,     /**< Processing provisioning data */
    SERIAL_PROV_STATE_TESTING,          /**< Running validation tests */
    SERIAL_PROV_STATE_COMPLETE,         /**< Provisioning complete, ready for reset */
    SERIAL_PROV_STATE_ERROR,            /**< Error occurred */
} serial_prov_state_t;

/**
 * @brief Test types that can be run in service mode
 */
typedef enum {
    SERIAL_PROV_TEST_WIFI,              /**< Test Wi-Fi connectivity */
    SERIAL_PROV_TEST_RFID,              /**< Test RFID tag scanning */
    SERIAL_PROV_TEST_CLOUD,             /**< Test cloud API connectivity */
    SERIAL_PROV_TEST_ALL,               /**< Run all tests */
} serial_prov_test_t;

/**
 * @brief Test result structure
 */
typedef struct {
    bool wifi_ok;                       /**< Wi-Fi test passed */
    bool rfid_ok;                       /**< RFID test passed */
    bool cloud_ok;                      /**< Cloud API test passed */
    char wifi_ssid[33];                 /**< Connected Wi-Fi SSID */
    int8_t wifi_rssi;                   /**< Wi-Fi signal strength */
    char wifi_ip[16];                   /**< IP address */
    uint8_t rfid_tags_found;            /**< Number of Saturday tags found */
    char rfid_epc[25];                  /**< Last detected EPC (hex string) */
    int cloud_status;                   /**< Cloud API HTTP response code */
    int64_t cloud_latency_ms;           /**< Cloud API request latency */
} serial_prov_test_result_t;

/**
 * @brief Provisioning data received from Admin app
 */
typedef struct {
    char unit_id[32];                   /**< Unique unit identifier (serial number) */
    char cloud_url[128];                /**< Cloud API URL */
    char cloud_anon_key[256];           /**< Cloud API anonymous/public key */
    char cloud_device_secret[64];       /**< Device-specific secret (optional) */
    char wifi_ssid[33];                 /**< Wi-Fi SSID for testing (optional) */
    char wifi_password[65];             /**< Wi-Fi password for testing (optional) */
} serial_prov_data_t;

/**
 * @brief Callback for provisioning state changes
 */
typedef void (*serial_prov_state_callback_t)(serial_prov_state_t state, void *user_data);

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize serial provisioning module
 *
 * Sets up UART listener for provisioning commands.
 * Does not start provisioning mode - call serial_prov_start() for that.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t serial_prov_init(void);

/**
 * @brief Deinitialize serial provisioning module
 *
 * Stops any active provisioning and cleans up resources.
 *
 * @return ESP_OK on success
 */
esp_err_t serial_prov_deinit(void);

/**
 * @brief Start service mode
 *
 * Begins listening for service mode commands and sends periodic status beacons.
 * LED will show white pulsing to indicate service mode.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t serial_prov_start(void);

/**
 * @brief Stop service mode
 *
 * Stops listening for service mode commands.
 *
 * @return ESP_OK on success
 */
esp_err_t serial_prov_stop(void);

/**
 * @brief Check if service mode is active
 *
 * @return true if in service mode
 */
bool serial_prov_is_active(void);

/**
 * @brief Get current service mode state
 *
 * @return Current state
 */
serial_prov_state_t serial_prov_get_state(void);

/**
 * @brief Register callback for state changes
 *
 * @param callback Function to call on state change
 * @param user_data User data passed to callback
 * @return ESP_OK on success
 */
esp_err_t serial_prov_register_callback(serial_prov_state_callback_t callback, void *user_data);

/**
 * @brief Get last test results
 *
 * @param result Output test results
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if no tests run
 */
esp_err_t serial_prov_get_test_results(serial_prov_test_result_t *result);

/**
 * @brief Check if exit_service_mode was requested
 *
 * Returns true after an exit_service_mode command has been received.
 * This signals that the device should exit service mode and continue
 * to normal operation.
 *
 * @return true if service mode exit was requested
 */
bool serial_prov_is_complete(void);

/**
 * @brief Send a JSON message over serial (for responses)
 *
 * Utility function for sending JSON responses.
 * Automatically appends newline terminator.
 *
 * @param json JSON string to send
 * @return ESP_OK on success
 */
esp_err_t serial_prov_send_json(const char *json);

/**
 * @brief Listen for service mode entry command during boot window
 *
 * For provisioned devices, this function listens for the "enter_service_mode"
 * command for a specified timeout period. This allows technicians to enter
 * service mode on devices returned for repair or diagnostics.
 *
 * Per the Service Mode Protocol:
 * - Fresh devices (no unit_id) should auto-enter service mode
 * - Provisioned devices should call this function at boot
 * - If enter_service_mode is received within the window, service mode starts
 * - If timeout expires, device proceeds to standard operation
 *
 * @param timeout_ms Duration to listen for entry command (typically 10000ms)
 * @return true if service mode was entered, false if timeout expired
 */
bool serial_prov_wait_for_entry(uint32_t timeout_ms);

/**
 * @brief Start background command listener (always-listening mode)
 *
 * Per Device Command Protocol v1.3, the device should always be listening
 * for commands over USB serial, not just during service mode. This function
 * starts a lightweight background task that:
 * - Handles get_status commands at any time
 * - Handles enter_service_mode to transition to full service mode
 * - Does NOT send periodic status beacons (unlike full service mode)
 *
 * This should be called after the boot window expires for provisioned devices,
 * allowing the Saturday Admin app to probe the device at any time.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t serial_prov_start_background_listener(void);

/**
 * @brief Stop background command listener
 *
 * @return ESP_OK on success
 */
esp_err_t serial_prov_stop_background_listener(void);

/**
 * @brief Check if background listener is running
 *
 * @return true if background listener is active
 */
bool serial_prov_is_background_listener_active(void);

#ifdef __cplusplus
}
#endif

#endif /* SERIAL_PROV_H */
