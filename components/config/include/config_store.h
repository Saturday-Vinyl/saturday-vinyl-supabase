/**
 * @file config_store.h
 * @brief NVS configuration storage interface
 *
 * Provides persistent storage for device configuration using ESP-IDF NVS.
 */

#ifndef CONFIG_STORE_H
#define CONFIG_STORE_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Firmware Identification
 ******************************************************************************/
#define FIRMWARE_VERSION_MAJOR  0
#define FIRMWARE_VERSION_MINOR  8
#define FIRMWARE_VERSION_PATCH  0
#define FIRMWARE_VERSION        "0.8.0"

/** UUID matching the firmware_versions table in the backend database */
#define FIRMWARE_ID             "550e8400-e29b-41d4-a716-446655440000"

/**
 * @brief RFID configuration structure
 */
typedef struct {
    uint16_t poll_interval_ms;
    uint8_t rf_power_dbm;
    uint16_t debounce_present_ms;
    uint16_t debounce_absent_ms;
} rfid_config_t;

/**
 * @brief Initialize the configuration store
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_init(void);

/**
 * @brief Check if device has been factory provisioned
 *
 * @return true if provisioned, false otherwise
 */
bool config_is_provisioned(void);

/**
 * @brief Set the factory provisioned flag
 *
 * @param provisioned true to mark as provisioned, false to clear
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_provisioned(bool provisioned);

/**
 * @brief Check if Wi-Fi credentials are stored
 *
 * @return true if credentials exist, false otherwise
 */
bool config_has_wifi(void);

/**
 * @brief Get stored Wi-Fi credentials
 *
 * @param ssid Buffer for SSID
 * @param ssid_len SSID buffer length
 * @param password Buffer for password
 * @param pass_len Password buffer length
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_get_wifi(char *ssid, size_t ssid_len,
                          char *password, size_t pass_len);

/**
 * @brief Store Wi-Fi credentials
 *
 * @param ssid Wi-Fi SSID (max 32 chars)
 * @param password Wi-Fi password (max 64 chars, NULL for open networks)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_wifi(const char *ssid, const char *password);

/**
 * @brief Clear stored Wi-Fi credentials
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_clear_wifi(void);

/**
 * @brief Get RFID configuration
 *
 * @param config Pointer to configuration structure
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_get_rfid(rfid_config_t *config);

/**
 * @brief Set RFID configuration
 *
 * @param config Pointer to configuration structure
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_rfid(const rfid_config_t *config);

/**
 * @brief Check if unit ID (serial number) is stored
 *
 * The unit_id is the core provisioning identifier. A device is considered
 * "provisioned" if it has a unit_id stored.
 *
 * @return true if unit_id exists, false otherwise
 */
bool config_has_unit_id(void);

/**
 * @brief Get unit ID (serial number)
 *
 * @param unit_id Buffer for unit ID
 * @param max_len Buffer length
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not set
 */
esp_err_t config_get_unit_id(char *unit_id, size_t max_len);

/**
 * @brief Set unit ID (serial number)
 *
 * This is the primary provisioning identifier. Once set, the device
 * is considered provisioned.
 *
 * @param unit_id Unit serial number (e.g., "SV-HUB-000001")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_unit_id(const char *unit_id);

/*******************************************************************************
 * Serial Number and Name (Device Command Protocol)
 ******************************************************************************/

/**
 * @brief Check if serial number is stored
 *
 * @return true if serial_number exists, false otherwise
 */
bool config_has_serial_number(void);

/**
 * @brief Get device serial number
 *
 * @param serial_number Buffer for serial number
 * @param max_len Buffer length
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not set
 */
esp_err_t config_get_serial_number(char *serial_number, size_t max_len);

/**
 * @brief Set device serial number
 *
 * @param serial_number Device serial number (e.g., "SV-HUB-000001")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_serial_number(const char *serial_number);

/**
 * @brief Get device name (human-friendly product name)
 *
 * @param name Buffer for name
 * @param max_len Buffer length
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not set
 */
esp_err_t config_get_name(char *name, size_t max_len);

/**
 * @brief Set device name (human-friendly product name)
 *
 * @param name Product name (e.g., "Hub", "Crate")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_name(const char *name);

/*******************************************************************************
 * Source-Tagged Provisioning Data (Device Command Protocol)
 ******************************************************************************/

/** Source tag for factory-provisioned data (persists through consumer reset) */
#define CONFIG_SOURCE_FACTORY   "factory"

/** Source tag for consumer-provisioned data (cleared on consumer reset) */
#define CONFIG_SOURCE_CONSUMER  "consumer"

/**
 * @brief Store a string value with source tag
 *
 * @param key NVS key name
 * @param value String value to store
 * @param source Source tag ("factory" or "consumer")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_string_tagged(const char *key, const char *value, const char *source);

/**
 * @brief Get a string value and its source tag
 *
 * @param key NVS key name
 * @param value Buffer for value
 * @param max_len Value buffer length
 * @param source Buffer for source tag (optional, can be NULL)
 * @param source_len Source buffer length
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not set
 */
esp_err_t config_get_string_tagged(const char *key, char *value, size_t max_len, char *source, size_t source_len);

/**
 * @brief Store an integer value with source tag
 *
 * @param key NVS key name
 * @param value Integer value to store
 * @param source Source tag ("factory" or "consumer")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_set_int_tagged(const char *key, int32_t value, const char *source);

/**
 * @brief Get an integer value and its source tag
 *
 * @param key NVS key name
 * @param value Pointer to store value
 * @param source Buffer for source tag (optional, can be NULL)
 * @param source_len Source buffer length
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not set
 */
esp_err_t config_get_int_tagged(const char *key, int32_t *value, char *source, size_t source_len);

/**
 * @brief Get the source tag for a key
 *
 * @param key NVS key name
 * @param source Buffer for source tag
 * @param source_len Buffer length (min 8)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_get_source(const char *key, char *source, size_t source_len);

/**
 * @brief Clear all data with a specific source tag
 *
 * @param source Source tag to clear ("factory" or "consumer")
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_clear_by_source(const char *source);

/**
 * @brief Erase all configuration (full factory reset)
 *
 * Clears ALL NVS data including Supabase configuration.
 * Device will need to be completely re-provisioned.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_factory_reset(void);

/**
 * @brief Soft reset for customer handoff (legacy name)
 *
 * @deprecated Use config_consumer_reset() instead
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_customer_reset(void);

/**
 * @brief Consumer reset - clear consumer data, preserve factory data
 *
 * Clears all data tagged with source="consumer" (e.g., BLE-provisioned WiFi)
 * while preserving factory data (serial_number, name, cloud config, Thread creds).
 * This prepares the device for re-provisioning via BLE.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_consumer_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* CONFIG_STORE_H */
