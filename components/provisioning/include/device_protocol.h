/**
 * @file device_protocol.h
 * @brief Saturday Device Command Protocol interface
 *
 * Implements the Saturday Device Command Protocol v1.2.0 for factory provisioning,
 * testing, and remote device management.
 *
 * Key features:
 * - Always-listening (no entry window required)
 * - Unified command set for UART and cloud channels
 * - Source-tagged provisioning data (factory vs consumer)
 * - Capability-based test commands
 */

#ifndef DEVICE_PROTOCOL_H
#define DEVICE_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/** Maximum length of a protocol message (JSON) */
#define DEVICE_PROTOCOL_MAX_MSG_LEN     4096

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Protocol event types
 */
typedef enum {
    DEVICE_PROTOCOL_EVENT_PROVISIONED,  /**< Device has been factory provisioned */
    DEVICE_PROTOCOL_EVENT_RESET,        /**< Device reset requested */
    DEVICE_PROTOCOL_EVENT_OTA_START,    /**< OTA update starting */
} device_protocol_event_t;

/**
 * @brief Callback for protocol events
 *
 * @param event Event type
 * @param user_data User data passed during registration
 */
typedef void (*device_protocol_callback_t)(device_protocol_event_t event, void *user_data);

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the device protocol handler
 *
 * Sets up USB Serial JTAG driver for command reception.
 * Does not start listening - call device_protocol_start() to begin.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_init(void);

/**
 * @brief Deinitialize the device protocol handler
 *
 * Stops the protocol task if running and frees resources.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_deinit(void);

/**
 * @brief Start listening for commands
 *
 * Starts the protocol task that listens for JSON commands on USB serial.
 * Commands are processed and responses sent back.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_start(void);

/**
 * @brief Stop listening for commands
 *
 * Stops the protocol task. Call device_protocol_start() to resume.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_stop(void);

/**
 * @brief Check if protocol handler is running
 *
 * @return true if running, false otherwise
 */
bool device_protocol_is_running(void);

/**
 * @brief Register callback for protocol events
 *
 * @param callback Event callback function
 * @param user_data User data to pass to callback
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_register_callback(device_protocol_callback_t callback, void *user_data);

/**
 * @brief Send a JSON message (low-level)
 *
 * Sends raw JSON string to the USB serial output.
 * Normally you don't need to call this - the protocol handler
 * sends responses automatically.
 *
 * @param json JSON string to send (null-terminated)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t device_protocol_send_json(const char *json);

#ifdef __cplusplus
}
#endif

#endif /* DEVICE_PROTOCOL_H */
