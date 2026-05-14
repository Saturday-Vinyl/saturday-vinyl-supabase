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
#define NVS_NAMESPACE_WIFI      "sv_wifi"
#define NVS_NAMESPACE_ADOPT     "sv_adopt"

/* NVS keys for adoption namespace. ESP-IDF NVS key limit is 15 chars. */
#define NVS_KEY_ADOPT_STATE     "state"
#define NVS_KEY_ACCESS_TOKEN    "access_token"
#define NVS_KEY_REFRESH_TOKEN   "refresh_token"
#define NVS_KEY_TOKEN_EXPIRES   "tok_exp_ms"
#define NVS_KEY_THREAD_CREDS    "thr_creds"

/* NVS keys for RFID configuration */
#define NVS_KEY_POLL_INTERVAL   "poll_int"
#define NVS_KEY_RF_POWER        "rf_power"
#define NVS_KEY_DEB_PRESENT     "deb_pres"
#define NVS_KEY_DEB_ABSENT      "deb_abs"

/* NVS keys for Wi-Fi configuration */
#define NVS_KEY_WIFI_SSID       "ssid"
#define NVS_KEY_WIFI_PASSWORD   "password"

/* NVS keys for provisioning state */
#define NVS_KEY_PROVISIONED     "provisioned"

/* Default values */
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            15  /* YRM100 minimum is 15 dBm */
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
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    uint8_t provisioned = 0;
    err = nvs_get_u8(handle, NVS_KEY_PROVISIONED, &provisioned);
    nvs_close(handle);

    return (err == ESP_OK && provisioned == 1);
}

esp_err_t config_set_provisioned(bool provisioned)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for provisioned flag: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_u8(handle, NVS_KEY_PROVISIONED, provisioned ? 1 : 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set provisioned flag: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit provisioned flag: %s", esp_err_to_name(err));
        return err;
    }

    ESP_LOGI(TAG, "Device marked as %s", provisioned ? "provisioned" : "unprovisioned");
    return ESP_OK;
}

bool config_has_wifi(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_WIFI, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    /* Check if SSID exists */
    size_t required_size = 0;
    err = nvs_get_str(handle, NVS_KEY_WIFI_SSID, NULL, &required_size);
    nvs_close(handle);

    return (err == ESP_OK && required_size > 1);  /* > 1 because NVS includes null terminator */
}

esp_err_t config_get_wifi(char *ssid, size_t ssid_len,
                          char *password, size_t pass_len)
{
    if (ssid == NULL || password == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (ssid_len < 33 || pass_len < 65) {
        ESP_LOGE(TAG, "Buffer too small (need ssid>=33, pass>=65)");
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_WIFI, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGD(TAG, "Wi-Fi credentials not found in NVS");
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for Wi-Fi: %s", esp_err_to_name(err));
        return err;
    }

    /* Read SSID */
    size_t len = ssid_len;
    err = nvs_get_str(handle, NVS_KEY_WIFI_SSID, ssid, &len);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        nvs_close(handle);
        ESP_LOGD(TAG, "Wi-Fi SSID not found");
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        nvs_close(handle);
        ESP_LOGE(TAG, "Failed to read Wi-Fi SSID: %s", esp_err_to_name(err));
        return err;
    }

    /* Read password (may be empty for open networks) */
    len = pass_len;
    err = nvs_get_str(handle, NVS_KEY_WIFI_PASSWORD, password, &len);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* No password stored - assume open network */
        password[0] = '\0';
    } else if (err != ESP_OK) {
        nvs_close(handle);
        ESP_LOGE(TAG, "Failed to read Wi-Fi password: %s", esp_err_to_name(err));
        return err;
    }

    nvs_close(handle);
    ESP_LOGD(TAG, "Wi-Fi credentials loaded for '%s'", ssid);
    return ESP_OK;
}

esp_err_t config_set_wifi(const char *ssid, const char *password)
{
    if (ssid == NULL || strlen(ssid) == 0) {
        ESP_LOGE(TAG, "SSID is required");
        return ESP_ERR_INVALID_ARG;
    }

    if (strlen(ssid) > 32) {
        ESP_LOGE(TAG, "SSID too long (max 32 chars)");
        return ESP_ERR_INVALID_ARG;
    }

    if (password != NULL && strlen(password) > 64) {
        ESP_LOGE(TAG, "Password too long (max 64 chars)");
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_WIFI, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for writing: %s", esp_err_to_name(err));
        return err;
    }

    /* Write SSID */
    err = nvs_set_str(handle, NVS_KEY_WIFI_SSID, ssid);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write SSID: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    /* Write password (empty string for open networks) */
    const char *pass_to_store = (password != NULL) ? password : "";
    err = nvs_set_str(handle, NVS_KEY_WIFI_PASSWORD, pass_to_store);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write password: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    /* Commit changes */
    err = nvs_commit(handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit Wi-Fi config: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    nvs_close(handle);
    ESP_LOGI(TAG, "Wi-Fi credentials saved for '%s'", ssid);
    return ESP_OK;
}

esp_err_t config_clear_wifi(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_WIFI, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* Nothing to clear */
        return ESP_OK;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for clearing: %s", esp_err_to_name(err));
        return err;
    }

    /* Erase both keys */
    nvs_erase_key(handle, NVS_KEY_WIFI_SSID);
    nvs_erase_key(handle, NVS_KEY_WIFI_PASSWORD);

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit Wi-Fi clear: %s", esp_err_to_name(err));
        return err;
    }

    ESP_LOGI(TAG, "Wi-Fi credentials cleared");
    return ESP_OK;
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

bool config_has_unit_id(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    size_t len = 0;
    err = nvs_get_str(handle, "unit_id", NULL, &len);
    nvs_close(handle);

    return (err == ESP_OK && len > 1);
}

esp_err_t config_get_unit_id(char *unit_id, size_t max_len)
{
    if (unit_id == NULL || max_len < 2) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for unit_id: %s", esp_err_to_name(err));
        return err;
    }

    size_t len = max_len;
    err = nvs_get_str(handle, "unit_id", unit_id, &len);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read unit_id: %s", esp_err_to_name(err));
        return err;
    }

    return ESP_OK;
}

esp_err_t config_set_unit_id(const char *unit_id)
{
    if (unit_id == NULL || unit_id[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for unit_id: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_str(handle, "unit_id", unit_id);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write unit_id: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Unit ID stored: %s", unit_id);
    }

    return err;
}

/*******************************************************************************
 * Adoption + Cloud-Canonical Thread Credentials
 ******************************************************************************/

esp_err_t config_get_adoption_state(adoption_state_t *out_state)
{
    if (out_state == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        *out_state = ADOPTION_STATE_UNPROVISIONED;
        return ESP_OK;
    } else if (err != ESP_OK) {
        return err;
    }

    uint8_t v = ADOPTION_STATE_UNPROVISIONED;
    err = nvs_get_u8(handle, NVS_KEY_ADOPT_STATE, &v);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        *out_state = ADOPTION_STATE_UNPROVISIONED;
        return ESP_OK;
    } else if (err != ESP_OK) {
        return err;
    }

    *out_state = (adoption_state_t)v;
    return ESP_OK;
}

esp_err_t config_set_adoption_state(adoption_state_t state)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "open adopt namespace: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_u8(handle, NVS_KEY_ADOPT_STATE, (uint8_t)state);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }
    nvs_close(handle);
    return err;
}

esp_err_t config_set_device_tokens(const char *access_token,
                                   const char *refresh_token,
                                   int64_t expires_at_ms)
{
    if (access_token == NULL || refresh_token == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
    if (err != ESP_OK) return err;

    err = nvs_set_str(handle, NVS_KEY_ACCESS_TOKEN, access_token);
    if (err != ESP_OK) goto done;

    err = nvs_set_str(handle, NVS_KEY_REFRESH_TOKEN, refresh_token);
    if (err != ESP_OK) goto done;

    err = nvs_set_i64(handle, NVS_KEY_TOKEN_EXPIRES, expires_at_ms);
    if (err != ESP_OK) goto done;

    err = nvs_commit(handle);

done:
    nvs_close(handle);
    return err;
}

esp_err_t config_get_device_tokens(char *access_token, size_t at_size,
                                   char *refresh_token, size_t rt_size,
                                   int64_t *expires_at_ms)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        return err;
    }

    if (access_token != NULL) {
        size_t len = at_size;
        err = nvs_get_str(handle, NVS_KEY_ACCESS_TOKEN, access_token, &len);
        if (err != ESP_OK) goto done;
    }

    if (refresh_token != NULL) {
        size_t len = rt_size;
        err = nvs_get_str(handle, NVS_KEY_REFRESH_TOKEN, refresh_token, &len);
        if (err != ESP_OK) goto done;
    }

    if (expires_at_ms != NULL) {
        err = nvs_get_i64(handle, NVS_KEY_TOKEN_EXPIRES, expires_at_ms);
        if (err != ESP_OK) goto done;
    }

done:
    nvs_close(handle);
    return err;
}

esp_err_t config_clear_device_tokens(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;
    } else if (err != ESP_OK) {
        return err;
    }

    nvs_erase_key(handle, NVS_KEY_ACCESS_TOKEN);
    nvs_erase_key(handle, NVS_KEY_REFRESH_TOKEN);
    nvs_erase_key(handle, NVS_KEY_TOKEN_EXPIRES);
    err = nvs_commit(handle);
    nvs_close(handle);
    return err;
}

esp_err_t config_set_thread_creds_cache(const s3h2_credentials_payload_t *creds)
{
    if (creds == NULL) return ESP_ERR_INVALID_ARG;

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
    if (err != ESP_OK) return err;

    err = nvs_set_blob(handle, NVS_KEY_THREAD_CREDS, creds, sizeof(*creds));
    if (err == ESP_OK) err = nvs_commit(handle);
    nvs_close(handle);
    return err;
}

esp_err_t config_get_thread_creds_cache(s3h2_credentials_payload_t *out_creds)
{
    if (out_creds == NULL) return ESP_ERR_INVALID_ARG;

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) return ESP_ERR_NOT_FOUND;
    if (err != ESP_OK) return err;

    size_t len = sizeof(*out_creds);
    err = nvs_get_blob(handle, NVS_KEY_THREAD_CREDS, out_creds, &len);
    nvs_close(handle);

    if (err == ESP_OK && len != sizeof(*out_creds)) {
        ESP_LOGW(TAG, "thread_creds blob size mismatch: %zu vs %zu",
                 len, sizeof(*out_creds));
        return ESP_ERR_INVALID_SIZE;
    }
    return err;
}

esp_err_t config_clear_thread_creds_cache(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) return ESP_OK;
    if (err != ESP_OK) return err;

    nvs_erase_key(handle, NVS_KEY_THREAD_CREDS);
    err = nvs_commit(handle);
    nvs_close(handle);
    return err;
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

esp_err_t config_customer_reset(void)
{
    ESP_LOGI(TAG, "Customer reset - clearing user data, preserving factory config");

    esp_err_t err;

    /* Clear Wi-Fi credentials */
    err = config_clear_wifi();
    if (err != ESP_OK && err != ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGW(TAG, "Failed to clear Wi-Fi: %s", esp_err_to_name(err));
    }

    /* Clear provisioned flag */
    err = config_set_provisioned(false);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to clear provisioned flag: %s", esp_err_to_name(err));
    }

    /* Clear RFID config (return to defaults) */
    nvs_handle_t handle;
    err = nvs_open(NVS_NAMESPACE_RFID, NVS_READWRITE, &handle);
    if (err == ESP_OK) {
        nvs_erase_all(handle);
        nvs_commit(handle);
        nvs_close(handle);
    }

    /* Clear adoption namespace: device tokens, cached creds, adoption state.
     * Thread credentials on H2 are cleared by the caller (consumer_reset
     * handler sends H2_CLEAR_CREDENTIALS over UART). */
    {
        nvs_handle_t handle;
        esp_err_t aerr = nvs_open(NVS_NAMESPACE_ADOPT, NVS_READWRITE, &handle);
        if (aerr == ESP_OK) {
            nvs_erase_all(handle);
            nvs_commit(handle);
            nvs_close(handle);
        }
    }

    /* Note: Supabase config (sv_supabase namespace) is preserved */

    ESP_LOGI(TAG, "Customer reset complete - device ready for BLE provisioning");
    return ESP_OK;
}
