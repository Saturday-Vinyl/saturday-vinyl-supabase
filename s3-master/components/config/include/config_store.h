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
#include "s3_h2_protocol.h"  /* for s3h2_credentials_payload_t */

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
 * Adoption + Cloud-Canonical Thread Credentials
 *
 * The Hub becomes "adopted" when a user, through the BLE adoption flow, writes
 * their JWT to the User Token characteristic and the Hub calls `adopt_device`
 * on Supabase. The cloud returns Thread credentials (cached locally for offline
 * boot) and device-scoped access/refresh tokens (used for subsequent
 * authenticated cloud calls instead of the shared anon key).
 *
 * All adoption-related NVS lives in the `sv_adopt` namespace and is cleared on
 * consumer_reset. See .context/thread-credential-architecture.md.
 ******************************************************************************/

/**
 * @brief Adoption lifecycle state.
 */
typedef enum {
    ADOPTION_STATE_UNPROVISIONED = 0,  /**< Hub has never been adopted */
    ADOPTION_STATE_ADOPTED       = 1,  /**< Hub is owned by a user account */
    ADOPTION_STATE_UNADOPTING    = 2,  /**< Unadoption in progress (rare) */
} adoption_state_t;

esp_err_t config_get_adoption_state(adoption_state_t *out_state);
esp_err_t config_set_adoption_state(adoption_state_t state);

/**
 * @brief Store the device session tokens returned by adopt_device or
 *        refresh_device_session.
 *
 * @param access_token  Short-lived access token (NUL-terminated)
 * @param refresh_token Long-lived refresh token (NUL-terminated)
 * @param expires_at_ms Unix timestamp in milliseconds for access-token expiry
 */
esp_err_t config_set_device_tokens(const char *access_token,
                                   const char *refresh_token,
                                   int64_t expires_at_ms);

/**
 * @brief Load device session tokens from NVS.
 *
 * @param access_token  Buffer for access token. NULL to skip.
 * @param at_size       Size of access_token buffer.
 * @param refresh_token Buffer for refresh token. NULL to skip.
 * @param rt_size       Size of refresh_token buffer.
 * @param expires_at_ms Out param for expiry timestamp. NULL to skip.
 *
 * @return ESP_OK, ESP_ERR_NOT_FOUND if no tokens stored, other error codes.
 */
esp_err_t config_get_device_tokens(char *access_token, size_t at_size,
                                   char *refresh_token, size_t rt_size,
                                   int64_t *expires_at_ms);

esp_err_t config_clear_device_tokens(void);

/**
 * @brief Cache Thread credentials received from the cloud. Used as the S3-side
 *        offline source-of-truth; pushed to H2 via H2_SET_CREDENTIALS during
 *        boot reconciliation.
 */
esp_err_t config_set_thread_creds_cache(const s3h2_credentials_payload_t *creds);
esp_err_t config_get_thread_creds_cache(s3h2_credentials_payload_t *out_creds);
esp_err_t config_clear_thread_creds_cache(void);

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
 * @brief Soft reset for customer handoff
 *
 * Clears user data (Wi-Fi, provisioned flag) but preserves
 * factory configuration (Supabase URL, anon key, unit ID, device secret).
 * This prepares the device for customer BLE provisioning.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t config_customer_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* CONFIG_STORE_H */
