/**
 * @file h2_flasher.h
 * @brief ESP32-H2 firmware flasher via esp-serial-flasher
 *
 * Provides functionality to flash ESP32-H2 co-processor firmware from the
 * h2_fw partition using the esp-serial-flasher library over UART.
 *
 * The H2 is controlled via:
 * - GPIO6 (H2_EN): Reset control (active low)
 * - GPIO7 (H2_BOOT): Boot mode select (low = download mode, high = normal)
 *
 * Phase PROD-1.2: H2 OTA via S3
 */

#ifndef H2_FLASHER_H
#define H2_FLASHER_H

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
 * @brief H2 flasher event base for ESP-IDF event loop
 */
ESP_EVENT_DECLARE_BASE(H2_FLASHER_EVENTS);

/**
 * @brief H2 flasher event types
 */
typedef enum {
    H2_FLASHER_EVENT_START,         /**< Flash operation starting */
    H2_FLASHER_EVENT_PROGRESS,      /**< Flash progress update */
    H2_FLASHER_EVENT_COMPLETE,      /**< Flash completed successfully */
    H2_FLASHER_EVENT_FAILED,        /**< Flash operation failed */
} h2_flasher_event_type_t;

/**
 * @brief Flash progress event data
 */
typedef struct {
    uint8_t percentage;         /**< Progress percentage (0-100) */
    uint32_t bytes_written;     /**< Bytes written so far */
    uint32_t total_bytes;       /**< Total firmware size */
} h2_flasher_progress_t;

/**
 * @brief Flash result event data
 */
typedef struct {
    esp_err_t error;            /**< Error code if failed */
    uint32_t flash_time_ms;     /**< Time taken to flash in ms */
} h2_flasher_result_t;

/*******************************************************************************
 * Status
 ******************************************************************************/

/**
 * @brief H2 flasher status
 */
typedef struct {
    bool initialized;           /**< Flasher is initialized */
    bool flash_in_progress;     /**< Flash operation in progress */
    uint8_t progress;           /**< Current progress (0-100) */
    uint32_t flashes_completed; /**< Total successful flashes */
    uint32_t flashes_failed;    /**< Total failed flashes */
} h2_flasher_status_t;

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the H2 flasher
 *
 * Sets up GPIO control for H2 boot mode selection.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t h2_flasher_init(void);

/**
 * @brief Deinitialize the H2 flasher
 *
 * @return ESP_OK on success
 */
esp_err_t h2_flasher_deinit(void);

/**
 * @brief Check if H2 firmware is staged for flashing
 *
 * @return true if firmware is available in h2_fw partition
 */
bool h2_flasher_firmware_available(void);

/**
 * @brief Get the size of staged H2 firmware
 *
 * @param size Output size in bytes
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if no firmware staged
 */
esp_err_t h2_flasher_get_firmware_size(size_t *size);

/**
 * @brief Flash the H2 with firmware from h2_fw partition
 *
 * This is a blocking operation that:
 * 1. Puts H2 into download mode (GPIO7 low, reset via GPIO6)
 * 2. Uses esp-serial-flasher to flash via UART
 * 3. Resets H2 into normal mode (GPIO7 high, reset via GPIO6)
 *
 * Progress is reported via H2_FLASHER_EVENTS.
 *
 * @param timeout_ms Maximum time to wait for flash operation (0 = default 60s)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t h2_flasher_flash(uint32_t timeout_ms);

/**
 * @brief Abort an in-progress flash operation
 *
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if no flash in progress
 */
esp_err_t h2_flasher_abort(void);

/**
 * @brief Put H2 into bootloader/download mode
 *
 * Used for manual control or debugging.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_flasher_enter_bootloader(void);

/**
 * @brief Reset H2 to normal operation mode
 *
 * @return ESP_OK on success
 */
esp_err_t h2_flasher_reset_normal(void);

/**
 * @brief Get current flasher status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t h2_flasher_get_status(h2_flasher_status_t *status);

/**
 * @brief Verify H2 firmware after flashing
 *
 * Computes checksum of flash contents and compares with expected.
 *
 * @return ESP_OK if verified, ESP_ERR_INVALID_CRC on mismatch
 */
esp_err_t h2_flasher_verify(void);

#ifdef __cplusplus
}
#endif

#endif /* H2_FLASHER_H */
