/**
 * @file ota_manager.h
 * @brief Over-The-Air (OTA) firmware update manager
 *
 * Manages firmware updates for the Saturday Vinyl Hub. Downloads firmware
 * from Supabase storage, applies updates using ESP-IDF's OTA mechanism,
 * and handles rollback on boot failure.
 *
 * Supports updating both S3 master firmware and H2 co-processor firmware.
 *
 * Phase PROD-1: OTA Updates
 */

#ifndef OTA_MANAGER_H
#define OTA_MANAGER_H

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
 * @brief OTA manager event base for ESP-IDF event loop
 */
ESP_EVENT_DECLARE_BASE(OTA_EVENTS);

/**
 * @brief OTA event types
 */
typedef enum {
    OTA_EVENT_CHECK_START,          /**< Started checking for updates */
    OTA_EVENT_CHECK_COMPLETE,       /**< Finished checking for updates */
    OTA_EVENT_UPDATE_AVAILABLE,     /**< New firmware version available */
    OTA_EVENT_UPDATE_START,         /**< Started downloading/applying update */
    OTA_EVENT_UPDATE_PROGRESS,      /**< Update progress (percentage) */
    OTA_EVENT_UPDATE_COMPLETE,      /**< Update applied, pending reboot */
    OTA_EVENT_UPDATE_FAILED,        /**< Update failed */
    OTA_EVENT_ROLLBACK_TRIGGERED,   /**< Rollback to previous firmware */
    OTA_EVENT_BOOT_VALIDATED,       /**< Boot marked as valid */
} ota_event_type_t;

/**
 * @brief Firmware type for OTA updates
 */
typedef enum {
    OTA_FIRMWARE_S3,        /**< ESP32-S3 master firmware */
    OTA_FIRMWARE_H2,        /**< ESP32-H2 co-processor firmware */
} ota_firmware_type_t;

/**
 * @brief OTA update progress event data
 */
typedef struct {
    ota_firmware_type_t firmware;   /**< Which firmware is being updated */
    uint8_t percentage;             /**< Download/apply progress (0-100) */
    uint32_t bytes_written;         /**< Bytes written so far */
    uint32_t total_bytes;           /**< Total firmware size */
} ota_progress_data_t;

/**
 * @brief OTA update result event data
 */
typedef struct {
    ota_firmware_type_t firmware;   /**< Which firmware was updated */
    esp_err_t error;                /**< Error code if failed */
    char version[16];               /**< New version string (if successful) */
} ota_result_data_t;

/*******************************************************************************
 * Version Information
 ******************************************************************************/

/**
 * @brief Firmware version structure
 */
typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t patch;
    char string[16];        /**< Version as string (e.g., "1.2.3") */
} ota_version_t;

/**
 * @brief Update availability information
 */
typedef struct {
    bool s3_update_available;       /**< S3 firmware update available */
    bool h2_update_available;       /**< H2 firmware update available */
    ota_version_t s3_current;       /**< Current S3 firmware version */
    ota_version_t s3_available;     /**< Available S3 firmware version */
    ota_version_t h2_current;       /**< Current H2 firmware version */
    ota_version_t h2_available;     /**< Available H2 firmware version */
    char s3_url[256];               /**< URL to download S3 firmware */
    char h2_url[256];               /**< URL to download H2 firmware */
} ota_update_info_t;

/*******************************************************************************
 * Status
 ******************************************************************************/

/**
 * @brief OTA boot status (diagnostic info)
 */
typedef enum {
    OTA_BOOT_NORMAL,            /**< Normal boot from validated firmware */
    OTA_BOOT_PENDING_VERIFY,    /**< First boot after OTA, awaiting validation */
    OTA_BOOT_ROLLBACK,          /**< Rolled back from failed OTA */
} ota_boot_status_t;

/**
 * @brief OTA manager status
 */
typedef struct {
    bool initialized;               /**< Manager is initialized */
    ota_boot_status_t boot_status;  /**< Current boot status */
    bool update_in_progress;        /**< Update is currently in progress */
    ota_firmware_type_t updating;   /**< Which firmware is being updated */
    uint8_t progress;               /**< Current progress (0-100) */
    ota_version_t running_version;  /**< Currently running S3 firmware version */
    ota_version_t h2_version;       /**< Current H2 firmware version */
    uint32_t updates_applied;       /**< Total successful updates */
    uint32_t updates_failed;        /**< Total failed updates */
    uint32_t rollbacks;             /**< Total rollbacks */
    int64_t last_check_time;        /**< Last update check timestamp (us) */
} ota_status_t;

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief OTA manager configuration
 */
typedef struct {
    uint32_t check_interval_sec;    /**< Auto-check interval (0 = disabled) */
    bool auto_apply;                /**< Auto-apply updates when found */
    bool auto_reboot;               /**< Auto-reboot after update applied */
    uint32_t download_timeout_sec;  /**< Download timeout in seconds */
} ota_config_t;

/**
 * @brief Default configuration
 */
#define OTA_CONFIG_DEFAULT() { \
    .check_interval_sec = 3600,     /* Check every hour */ \
    .auto_apply = false,            /* Manual apply by default */ \
    .auto_reboot = false,           /* Manual reboot by default */ \
    .download_timeout_sec = 300,    /* 5 minute download timeout */ \
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the OTA manager
 *
 * Sets up OTA partition handling and registers event handlers.
 * Call early in boot sequence before validating boot.
 *
 * @param config Configuration (NULL for defaults)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t ota_manager_init(const ota_config_t *config);

/**
 * @brief Deinitialize the OTA manager
 *
 * @return ESP_OK on success
 */
esp_err_t ota_manager_deinit(void);

/**
 * @brief Validate the current boot
 *
 * Call this after confirming the system is working correctly after
 * an OTA update. Marks the current partition as valid, preventing
 * rollback on next boot.
 *
 * Should be called after:
 * - Wi-Fi successfully connects
 * - Cloud connection verified
 * - Critical peripherals working
 *
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if not pending
 */
esp_err_t ota_manager_validate_boot(void);

/**
 * @brief Get current boot status
 *
 * @return Boot status enum
 */
ota_boot_status_t ota_manager_get_boot_status(void);

/**
 * @brief Check for available firmware updates
 *
 * Queries Supabase for the latest firmware versions and compares
 * against currently running versions.
 *
 * Fires OTA_EVENT_CHECK_START, OTA_EVENT_CHECK_COMPLETE, and
 * OTA_EVENT_UPDATE_AVAILABLE events.
 *
 * @param info Output update information (NULL to just check, no info)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t ota_manager_check_update(ota_update_info_t *info);

/**
 * @brief Start S3 firmware update
 *
 * Downloads and applies S3 master firmware from the provided URL.
 * This is an asynchronous operation - use events to track progress.
 *
 * After completion, the device must be rebooted to run the new firmware.
 *
 * @param url Firmware download URL (NULL to use URL from last check)
 * @return ESP_OK if update started, error code otherwise
 */
esp_err_t ota_manager_update_s3(const char *url);

/**
 * @brief Start H2 firmware update
 *
 * Downloads H2 firmware and stores it in the h2_fw partition.
 * The actual flashing to H2 happens after reboot (via esp-serial-flasher).
 *
 * @param url Firmware download URL (NULL to use URL from last check)
 * @return ESP_OK if update started, error code otherwise
 */
esp_err_t ota_manager_update_h2(const char *url);

/**
 * @brief Update both S3 and H2 firmware
 *
 * Convenience function to update both processors.
 * S3 is updated first, then H2 staging area is prepared.
 *
 * @return ESP_OK if updates started, error code otherwise
 */
esp_err_t ota_manager_update_all(void);

/**
 * @brief Abort an in-progress update
 *
 * Cancels the current download/update operation.
 *
 * @return ESP_OK on success, ESP_ERR_INVALID_STATE if no update in progress
 */
esp_err_t ota_manager_abort(void);

/**
 * @brief Get current OTA status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t ota_manager_get_status(ota_status_t *status);

/**
 * @brief Trigger a reboot to apply pending update
 *
 * Call after ota_manager_update_s3() completes successfully.
 * System will reboot and run the new firmware.
 *
 * @param delay_ms Delay before reboot in ms (0 for immediate)
 */
void ota_manager_reboot(uint32_t delay_ms);

/**
 * @brief Check if H2 firmware update is pending
 *
 * After downloading H2 firmware to the staging area, this returns true
 * until the H2 is flashed (done by main app after reboot).
 *
 * @return true if H2 update is staged and pending flash
 */
bool ota_manager_h2_update_pending(void);

/**
 * @brief Mark H2 update as complete
 *
 * Call after successfully flashing H2 via esp-serial-flasher.
 *
 * @param success true if H2 flash succeeded, false if failed
 * @return ESP_OK on success
 */
esp_err_t ota_manager_h2_update_complete(bool success);

/**
 * @brief Get the staged H2 firmware version
 *
 * @param version Output version structure
 * @return ESP_OK if H2 update is pending, ESP_ERR_NOT_FOUND otherwise
 */
esp_err_t ota_manager_get_staged_h2_version(ota_version_t *version);

#ifdef __cplusplus
}
#endif

#endif /* OTA_MANAGER_H */
