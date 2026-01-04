/**
 * @file yrm100_driver.h
 * @brief YRM100 UHF RFID module driver interface
 *
 * Provides low-level communication with the YRM100 RFID module
 * for tag detection and configuration. Supports both single-shot
 * polling and continuous background polling with callbacks.
 *
 * Phase 2 additions:
 * - Tag data structure with EPC, RSSI, and Saturday tag detection
 * - Callback-based continuous polling
 * - Background polling task
 */

#ifndef YRM100_DRIVER_H
#define YRM100_DRIVER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "rfid_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Callback function for tag detection events
 *
 * Called from the polling task when a tag is detected. The callback
 * should be quick to avoid blocking the polling loop.
 *
 * @param tag Pointer to detected tag data (valid only during callback)
 * @param user_data User data passed to yrm100_register_tag_callback
 */
typedef void (*yrm100_tag_callback_t)(const rfid_tag_t *tag, void *user_data);

/**
 * @brief Callback function for poll cycle completion
 *
 * Called from the polling task after each poll cycle completes.
 * Useful for tracking when no tag was detected in a poll.
 *
 * @param tag_detected True if a tag was detected this cycle, false otherwise
 * @param user_data User data passed to yrm100_register_poll_complete_callback
 */
typedef void (*yrm100_poll_complete_callback_t)(bool tag_detected, void *user_data);

/**
 * @brief Polling task configuration
 */
typedef struct {
    uint16_t poll_interval_ms;  /**< Interval between polls (default: 500ms) */
    uint8_t rf_power_dbm;       /**< RF power level 0-30 dBm (default: 10) */
    bool filter_saturday_only;  /**< Only report Saturday tags (default: false) */
} yrm100_poll_config_t;

/**
 * @brief Default polling configuration
 */
#define YRM100_POLL_CONFIG_DEFAULT() { \
    .poll_interval_ms = 500, \
    .rf_power_dbm = 15, /* YRM100 minimum is 15 dBm */ \
    .filter_saturday_only = false, \
}

/*******************************************************************************
 * Initialization and Control
 ******************************************************************************/

/**
 * @brief Initialize the YRM100 RFID module
 *
 * Configures UART and GPIO but does not enable the module.
 * Call yrm100_enable(true) to power on the module.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_init(void);

/**
 * @brief Enable or disable the RFID module
 *
 * Controls the enable pin. Allow ~100ms after enabling before
 * sending commands.
 *
 * @param enable true to enable, false to disable
 */
void yrm100_enable(bool enable);

/**
 * @brief Check if the module is enabled
 *
 * @return true if enabled, false otherwise
 */
bool yrm100_is_enabled(void);

/*******************************************************************************
 * Configuration Commands
 ******************************************************************************/

/**
 * @brief Get module firmware version
 *
 * @param version Buffer to store version string
 * @param max_len Maximum buffer length
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_get_firmware_version(char *version, size_t max_len);

/**
 * @brief Set RF output power
 *
 * Higher power = longer range but more interference and power consumption.
 * Typical values: 10 dBm for close range, 20-26 dBm for longer range.
 *
 * @param power_dbm Power level in dBm (0-30)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_set_rf_power(uint8_t power_dbm);

/**
 * @brief Get current RF output power
 *
 * @param power_dbm Pointer to store power level
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_get_rf_power(uint8_t *power_dbm);

/*******************************************************************************
 * Single-Shot Polling
 ******************************************************************************/

/**
 * @brief Perform single tag poll (basic - no tag data returned)
 *
 * @return ESP_OK if tag found, ESP_ERR_NOT_FOUND if no tag
 */
esp_err_t yrm100_single_poll(void);

/**
 * @brief Perform single tag poll with tag data
 *
 * @param tag Output structure for tag data (can be NULL to just check presence)
 * @return ESP_OK if tag found and parsed, ESP_ERR_NOT_FOUND if no tag
 */
esp_err_t yrm100_single_poll_with_data(rfid_tag_t *tag);

/*******************************************************************************
 * Continuous Polling
 ******************************************************************************/

/**
 * @brief Start continuous tag polling (raw command)
 *
 * Sends the MultiplePoll command to the module. Use yrm100_read_tag_notice()
 * to read incoming tag notices, or use the higher-level polling task.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_start_polling(void);

/**
 * @brief Stop continuous tag polling
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_stop_polling(void);

/**
 * @brief Read a tag notice from an ongoing continuous poll
 *
 * Call this in a loop after yrm100_start_polling() to receive
 * tag detection notices. Blocks until data is received or timeout.
 *
 * @param tag Output structure for tag data
 * @param timeout_ms Timeout in milliseconds
 * @return ESP_OK if tag notice received, ESP_ERR_TIMEOUT if no data
 */
esp_err_t yrm100_read_tag_notice(rfid_tag_t *tag, uint32_t timeout_ms);

/*******************************************************************************
 * Background Polling Task
 ******************************************************************************/

/**
 * @brief Register callback for tag detection events
 *
 * The callback will be invoked from the polling task whenever a tag
 * is detected. Only one callback can be registered at a time.
 *
 * @param callback Function to call when tag detected (NULL to unregister)
 * @param user_data User data to pass to callback
 */
void yrm100_register_tag_callback(yrm100_tag_callback_t callback, void *user_data);

/**
 * @brief Register callback for poll cycle completion
 *
 * The callback will be invoked from the polling task after each poll
 * cycle completes. Useful for Now Playing state machine to detect
 * when no tag was found.
 *
 * @param callback Function to call after each poll (NULL to unregister)
 * @param user_data User data to pass to callback
 */
void yrm100_register_poll_complete_callback(yrm100_poll_complete_callback_t callback, void *user_data);

/**
 * @brief Start the background polling task
 *
 * Creates a FreeRTOS task that continuously polls for tags and
 * invokes the registered callback when tags are detected.
 *
 * @param config Polling configuration (NULL for defaults)
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if already running
 */
esp_err_t yrm100_start_polling_task(const yrm100_poll_config_t *config);

/**
 * @brief Stop the background polling task
 *
 * Stops polling and deletes the task.
 *
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if not running
 */
esp_err_t yrm100_stop_polling_task(void);

/**
 * @brief Check if polling task is running
 *
 * @return true if task is running, false otherwise
 */
bool yrm100_is_polling_task_running(void);

/**
 * @brief Get statistics from the polling task
 *
 * @param total_polls Output: total number of poll cycles
 * @param tags_detected Output: total number of tag detections
 * @param saturday_tags Output: number of Saturday tag detections
 */
void yrm100_get_poll_stats(uint32_t *total_polls, uint32_t *tags_detected,
                            uint32_t *saturday_tags);

/*******************************************************************************
 * Low-Level Functions (for debugging)
 ******************************************************************************/

/**
 * @brief Send raw bytes to RFID module (for testing/debugging)
 *
 * @param data Data to send
 * @param len Length of data
 * @return ESP_OK on success
 */
esp_err_t yrm100_send_raw(const uint8_t *data, size_t len);

/**
 * @brief Receive raw bytes from RFID module (for testing/debugging)
 *
 * @param buf Buffer to store received data
 * @param max_len Maximum buffer size
 * @param timeout_ms Timeout in milliseconds
 * @return Number of bytes received, or -1 on error
 */
int yrm100_receive_raw(uint8_t *buf, size_t max_len, uint32_t timeout_ms);

#ifdef __cplusplus
}
#endif

#endif /* YRM100_DRIVER_H */
