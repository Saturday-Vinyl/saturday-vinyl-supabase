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
 * @brief Get hub ID
 *
 * @param hub_id Buffer for hub ID
 * @param max_len Buffer length
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_get_hub_id(char *hub_id, size_t max_len);

/**
 * @brief Erase all configuration (factory reset)
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_factory_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* CONFIG_STORE_H */
