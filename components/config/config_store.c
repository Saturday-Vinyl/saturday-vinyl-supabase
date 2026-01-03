/**
 * @file config_store.c
 * @brief NVS configuration storage implementation
 *
 * Provides persistent storage for device configuration using ESP-IDF NVS.
 * Implements RFID configuration storage for Phase 3.
 */

#include "config_store.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <string.h>

static const char *TAG = "CONFIG";

/* NVS namespace for Saturday Vinyl configuration */
#define NVS_NAMESPACE_CONFIG    "sv_config"
#define NVS_NAMESPACE_RFID      "sv_rfid"

/* NVS keys for RFID configuration */
#define NVS_KEY_POLL_INTERVAL   "poll_int"
#define NVS_KEY_RF_POWER        "rf_power"
#define NVS_KEY_DEB_PRESENT     "deb_pres"
#define NVS_KEY_DEB_ABSENT      "deb_abs"

/* Default values */
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            10
#define DEFAULT_DEBOUNCE_PRESENT_MS     1000
#define DEFAULT_DEBOUNCE_ABSENT_MS      2000

/* Module state */
static bool s_initialized = false;

esp_err_t config_init(void)
{
    if (s_initialized) {
        return ESP_OK;
    }

    /* Verify NVS is available by opening and closing a handle */
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_RFID, NVS_READONLY, &handle);
    if (err == ESP_OK) {
        nvs_close(handle);
    } else if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* Namespace doesn't exist yet - that's fine, it will be created on first write */
        err = ESP_OK;
    } else {
        ESP_LOGE(TAG, "Failed to verify NVS access: %s", esp_err_to_name(err));
        return err;
    }

    s_initialized = true;
    ESP_LOGI(TAG, "Configuration store initialized");
    return ESP_OK;
}

bool config_is_provisioned(void)
{
    /* TODO: Check NVS for provisioned flag in Phase 6 */
    return false;
}

bool config_has_wifi(void)
{
    /* TODO: Check NVS for WiFi credentials in Phase 4 */
    return false;
}

esp_err_t config_get_wifi(char *ssid, size_t ssid_len,
                          char *password, size_t pass_len)
{
    /* TODO: Implement in Phase 4 */
    return ESP_ERR_NOT_FOUND;
}

esp_err_t config_set_wifi(const char *ssid, const char *password)
{
    /* TODO: Implement in Phase 4 */
    return ESP_ERR_NOT_SUPPORTED;
}

esp_err_t config_get_rfid(rfid_config_t *config)
{
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Start with defaults */
    config->poll_interval_ms = DEFAULT_POLL_INTERVAL_MS;
    config->rf_power_dbm = DEFAULT_RF_POWER_DBM;
    config->debounce_present_ms = DEFAULT_DEBOUNCE_PRESENT_MS;
    config->debounce_absent_ms = DEFAULT_DEBOUNCE_ABSENT_MS;

    /* Try to read from NVS, keep defaults if not found */
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_RFID, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* Namespace doesn't exist - use defaults */
        ESP_LOGD(TAG, "RFID config not in NVS, using defaults");
        return ESP_OK;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for RFID config: %s", esp_err_to_name(err));
        return err;
    }

    /* Read each value, keeping default if not found */
    uint16_t u16_val;
    uint8_t u8_val;

    if (nvs_get_u16(handle, NVS_KEY_POLL_INTERVAL, &u16_val) == ESP_OK) {
        config->poll_interval_ms = u16_val;
    }
    if (nvs_get_u8(handle, NVS_KEY_RF_POWER, &u8_val) == ESP_OK) {
        config->rf_power_dbm = u8_val;
    }
    if (nvs_get_u16(handle, NVS_KEY_DEB_PRESENT, &u16_val) == ESP_OK) {
        config->debounce_present_ms = u16_val;
    }
    if (nvs_get_u16(handle, NVS_KEY_DEB_ABSENT, &u16_val) == ESP_OK) {
        config->debounce_absent_ms = u16_val;
    }

    nvs_close(handle);

    ESP_LOGD(TAG, "RFID config loaded: poll=%dms, power=%ddBm, deb_present=%dms, deb_absent=%dms",
             config->poll_interval_ms, config->rf_power_dbm,
             config->debounce_present_ms, config->debounce_absent_ms);

    return ESP_OK;
}

esp_err_t config_set_rfid(const rfid_config_t *config)
{
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Validate configuration values */
    if (config->poll_interval_ms < 100 || config->poll_interval_ms > 5000) {
        ESP_LOGE(TAG, "Invalid poll_interval_ms: %d (must be 100-5000)", config->poll_interval_ms);
        return ESP_ERR_INVALID_ARG;
    }
    if (config->rf_power_dbm > 30) {
        ESP_LOGE(TAG, "Invalid rf_power_dbm: %d (must be 0-30)", config->rf_power_dbm);
        return ESP_ERR_INVALID_ARG;
    }
    if (config->debounce_present_ms > 5000) {
        ESP_LOGE(TAG, "Invalid debounce_present_ms: %d (must be 0-5000)", config->debounce_present_ms);
        return ESP_ERR_INVALID_ARG;
    }
    if (config->debounce_absent_ms > 10000) {
        ESP_LOGE(TAG, "Invalid debounce_absent_ms: %d (must be 0-10000)", config->debounce_absent_ms);
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_RFID, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for writing: %s", esp_err_to_name(err));
        return err;
    }

    /* Write all values */
    err = nvs_set_u16(handle, NVS_KEY_POLL_INTERVAL, config->poll_interval_ms);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_u8(handle, NVS_KEY_RF_POWER, config->rf_power_dbm);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_u16(handle, NVS_KEY_DEB_PRESENT, config->debounce_present_ms);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_u16(handle, NVS_KEY_DEB_ABSENT, config->debounce_absent_ms);
    if (err != ESP_OK) goto cleanup;

    /* Commit changes to flash */
    err = nvs_commit(handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS changes: %s", esp_err_to_name(err));
        goto cleanup;
    }

    ESP_LOGI(TAG, "RFID config saved: poll=%dms, power=%ddBm, deb_present=%dms, deb_absent=%dms",
             config->poll_interval_ms, config->rf_power_dbm,
             config->debounce_present_ms, config->debounce_absent_ms);

cleanup:
    nvs_close(handle);
    return err;
}

esp_err_t config_get_hub_id(char *hub_id, size_t max_len)
{
    /* TODO: Implement in Phase 6 */
    return ESP_ERR_NOT_FOUND;
}

esp_err_t config_factory_reset(void)
{
    ESP_LOGW(TAG, "Factory reset requested - erasing all NVS data");

    /* Erase the entire NVS partition */
    esp_err_t err = nvs_flash_erase();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to erase NVS: %s", esp_err_to_name(err));
        return err;
    }

    /* Re-initialize NVS after erase */
    err = nvs_flash_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to re-init NVS after erase: %s", esp_err_to_name(err));
        return err;
    }

    s_initialized = false;
    ESP_LOGI(TAG, "Factory reset complete");
    return ESP_OK;
}
