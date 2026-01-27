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
#define NVS_NAMESPACE_PROV      "sv_prov"   /* Provisioning data with source tags */

/* Source tag suffix for NVS keys */
#define NVS_SOURCE_TAG_SUFFIX   "_src"
#define NVS_SOURCE_FACTORY      "factory"
#define NVS_SOURCE_CONSUMER     "consumer"

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
 * Serial Number and Name (Device Command Protocol)
 ******************************************************************************/

bool config_has_serial_number(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    size_t len = 0;
    err = nvs_get_str(handle, "serial_num", NULL, &len);
    nvs_close(handle);

    return (err == ESP_OK && len > 1);
}

esp_err_t config_get_serial_number(char *serial_number, size_t max_len)
{
    if (serial_number == NULL || max_len < 2) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for serial_number: %s", esp_err_to_name(err));
        return err;
    }

    size_t len = max_len;
    err = nvs_get_str(handle, "serial_num", serial_number, &len);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read serial_number: %s", esp_err_to_name(err));
        return err;
    }

    return ESP_OK;
}

esp_err_t config_set_serial_number(const char *serial_number)
{
    if (serial_number == NULL || serial_number[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for serial_number: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_str(handle, "serial_num", serial_number);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write serial_number: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Serial number stored: %s", serial_number);
    }

    return err;
}

esp_err_t config_get_name(char *name, size_t max_len)
{
    if (name == NULL || max_len < 2) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for name: %s", esp_err_to_name(err));
        return err;
    }

    size_t len = max_len;
    err = nvs_get_str(handle, "name", name, &len);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read name: %s", esp_err_to_name(err));
        return err;
    }

    return ESP_OK;
}

esp_err_t config_set_name(const char *name)
{
    if (name == NULL || name[0] == '\0') {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_CONFIG, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for name: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_str(handle, "name", name);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write name: %s", esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Name stored: %s", name);
    }

    return err;
}

/*******************************************************************************
 * Source-Tagged Provisioning Data (Device Command Protocol)
 *
 * All provisioning data is stored with a source tag indicating whether it
 * came from factory provisioning (UART) or consumer provisioning (BLE).
 * Consumer data is cleared on consumer_reset while factory data persists.
 ******************************************************************************/

esp_err_t config_set_string_tagged(const char *key, const char *value, const char *source)
{
    if (key == NULL || value == NULL || source == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Validate source */
    if (strcmp(source, NVS_SOURCE_FACTORY) != 0 &&
        strcmp(source, NVS_SOURCE_CONSUMER) != 0) {
        ESP_LOGE(TAG, "Invalid source: %s (must be 'factory' or 'consumer')", source);
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for tagged write: %s", esp_err_to_name(err));
        return err;
    }

    /* Write the value */
    err = nvs_set_str(handle, key, value);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write key '%s': %s", key, esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    /* Write the source tag */
    char src_key[NVS_KEY_NAME_MAX_SIZE];
    snprintf(src_key, sizeof(src_key), "%s%s", key, NVS_SOURCE_TAG_SUFFIX);
    err = nvs_set_str(handle, src_key, source);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write source tag for '%s': %s", key, esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGD(TAG, "Stored '%s' with source='%s'", key, source);
    }

    return err;
}

esp_err_t config_get_string_tagged(const char *key, char *value, size_t max_len, char *source, size_t source_len)
{
    if (key == NULL || value == NULL || max_len < 2) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for tagged read: %s", esp_err_to_name(err));
        return err;
    }

    /* Read the value */
    size_t len = max_len;
    err = nvs_get_str(handle, key, value, &len);
    if (err != ESP_OK) {
        nvs_close(handle);
        if (err == ESP_ERR_NVS_NOT_FOUND) {
            return ESP_ERR_NOT_FOUND;
        }
        ESP_LOGE(TAG, "Failed to read key '%s': %s", key, esp_err_to_name(err));
        return err;
    }

    /* Read the source tag if requested */
    if (source != NULL && source_len > 0) {
        char src_key[NVS_KEY_NAME_MAX_SIZE];
        snprintf(src_key, sizeof(src_key), "%s%s", key, NVS_SOURCE_TAG_SUFFIX);
        len = source_len;
        err = nvs_get_str(handle, src_key, source, &len);
        if (err != ESP_OK) {
            /* Default to factory if no source tag found */
            strncpy(source, NVS_SOURCE_FACTORY, source_len - 1);
            source[source_len - 1] = '\0';
        }
    }

    nvs_close(handle);
    return ESP_OK;
}

esp_err_t config_set_int_tagged(const char *key, int32_t value, const char *source)
{
    if (key == NULL || source == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Validate source */
    if (strcmp(source, NVS_SOURCE_FACTORY) != 0 &&
        strcmp(source, NVS_SOURCE_CONSUMER) != 0) {
        ESP_LOGE(TAG, "Invalid source: %s (must be 'factory' or 'consumer')", source);
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for tagged write: %s", esp_err_to_name(err));
        return err;
    }

    /* Write the value */
    err = nvs_set_i32(handle, key, value);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write key '%s': %s", key, esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    /* Write the source tag */
    char src_key[NVS_KEY_NAME_MAX_SIZE];
    snprintf(src_key, sizeof(src_key), "%s%s", key, NVS_SOURCE_TAG_SUFFIX);
    err = nvs_set_str(handle, src_key, source);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to write source tag for '%s': %s", key, esp_err_to_name(err));
        nvs_close(handle);
        return err;
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGD(TAG, "Stored '%s'=%d with source='%s'", key, (int)value, source);
    }

    return err;
}

esp_err_t config_get_int_tagged(const char *key, int32_t *value, char *source, size_t source_len)
{
    if (key == NULL || value == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for tagged read: %s", esp_err_to_name(err));
        return err;
    }

    /* Read the value */
    err = nvs_get_i32(handle, key, value);
    if (err != ESP_OK) {
        nvs_close(handle);
        if (err == ESP_ERR_NVS_NOT_FOUND) {
            return ESP_ERR_NOT_FOUND;
        }
        ESP_LOGE(TAG, "Failed to read key '%s': %s", key, esp_err_to_name(err));
        return err;
    }

    /* Read the source tag if requested */
    if (source != NULL && source_len > 0) {
        char src_key[NVS_KEY_NAME_MAX_SIZE];
        snprintf(src_key, sizeof(src_key), "%s%s", key, NVS_SOURCE_TAG_SUFFIX);
        size_t len = source_len;
        err = nvs_get_str(handle, src_key, source, &len);
        if (err != ESP_OK) {
            /* Default to factory if no source tag found */
            strncpy(source, NVS_SOURCE_FACTORY, source_len - 1);
            source[source_len - 1] = '\0';
        }
    }

    nvs_close(handle);
    return ESP_OK;
}

esp_err_t config_get_source(const char *key, char *source, size_t source_len)
{
    if (key == NULL || source == NULL || source_len < 8) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        return err;
    }

    char src_key[NVS_KEY_NAME_MAX_SIZE];
    snprintf(src_key, sizeof(src_key), "%s%s", key, NVS_SOURCE_TAG_SUFFIX);
    size_t len = source_len;
    err = nvs_get_str(handle, src_key, source, &len);
    nvs_close(handle);

    if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* Default to factory if no source tag */
        strncpy(source, NVS_SOURCE_FACTORY, source_len - 1);
        source[source_len - 1] = '\0';
        return ESP_OK;
    }

    return err;
}

esp_err_t config_clear_by_source(const char *source)
{
    if (source == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "Clearing all data with source='%s'", source);

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_PROV, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        /* Nothing to clear */
        return ESP_OK;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for clearing: %s", esp_err_to_name(err));
        return err;
    }

    /* Iterate all keys and find source tags matching the given source */
    nvs_iterator_t it = NULL;
    err = nvs_entry_find(NVS_DEFAULT_PART_NAME, NVS_NAMESPACE_PROV, NVS_TYPE_STR, &it);

    /* First pass: collect keys to delete (can't delete while iterating) */
    char keys_to_delete[32][NVS_KEY_NAME_MAX_SIZE];
    int delete_count = 0;

    while (err == ESP_OK && delete_count < 32) {
        nvs_entry_info_t info;
        nvs_entry_info(it, &info);

        /* Check if this is a source tag key */
        const char *suffix = strstr(info.key, NVS_SOURCE_TAG_SUFFIX);
        if (suffix != NULL && strcmp(suffix, NVS_SOURCE_TAG_SUFFIX) == 0) {
            /* Read the source value */
            char src_value[16];
            size_t len = sizeof(src_value);
            if (nvs_get_str(handle, info.key, src_value, &len) == ESP_OK) {
                if (strcmp(src_value, source) == 0) {
                    /* Extract the base key name */
                    size_t base_len = suffix - info.key;
                    if (base_len > 0 && base_len < NVS_KEY_NAME_MAX_SIZE) {
                        strncpy(keys_to_delete[delete_count], info.key, base_len);
                        keys_to_delete[delete_count][base_len] = '\0';
                        delete_count++;
                    }
                }
            }
        }
        err = nvs_entry_next(&it);
    }
    nvs_release_iterator(it);

    /* Second pass: delete the keys and their source tags */
    int deleted = 0;
    for (int i = 0; i < delete_count; i++) {
        /* Buffer for source tag key: base key + "_src" suffix + null terminator */
        char src_key[NVS_KEY_NAME_MAX_SIZE + sizeof(NVS_SOURCE_TAG_SUFFIX)];
        snprintf(src_key, sizeof(src_key), "%s%s", keys_to_delete[i], NVS_SOURCE_TAG_SUFFIX);

        nvs_erase_key(handle, keys_to_delete[i]);
        nvs_erase_key(handle, src_key);
        deleted++;
        ESP_LOGD(TAG, "Deleted '%s' (source=%s)", keys_to_delete[i], source);
    }

    err = nvs_commit(handle);
    nvs_close(handle);

    ESP_LOGI(TAG, "Cleared %d keys with source='%s'", deleted, source);
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
    /* Legacy function - calls consumer_reset for backward compatibility */
    return config_consumer_reset();
}

esp_err_t config_consumer_reset(void)
{
    ESP_LOGI(TAG, "Consumer reset - clearing consumer data, preserving factory config");

    esp_err_t err;

    /* Clear all source-tagged data marked as "consumer" */
    err = config_clear_by_source(NVS_SOURCE_CONSUMER);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to clear consumer-tagged data: %s", esp_err_to_name(err));
    }

    /* Clear Wi-Fi credentials (consumer-provisioned via BLE) */
    err = config_clear_wifi();
    if (err != ESP_OK && err != ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGW(TAG, "Failed to clear Wi-Fi: %s", esp_err_to_name(err));
    }

    /* Clear provisioned flag (will be re-set after BLE provisioning) */
    err = config_set_provisioned(false);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to clear provisioned flag: %s", esp_err_to_name(err));
    }

    /* Note: Factory data (serial_number, name, cloud config, Thread creds) is preserved */

    ESP_LOGI(TAG, "Consumer reset complete - device ready for BLE provisioning");
    return ESP_OK;
}
