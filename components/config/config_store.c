/**
 * @file config_store.c
 * @brief NVS configuration storage implementation
 *
 * TODO: Full implementation in Phase 3
 */

#include "config_store.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"

static const char *TAG = "CONFIG";

/* NVS namespace for Saturday Vinyl configuration */
#define NVS_NAMESPACE_CONFIG    "sv_config"
#define NVS_NAMESPACE_RFID      "sv_rfid"

/* Default values */
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            10
#define DEFAULT_DEBOUNCE_PRESENT_MS     1000
#define DEFAULT_DEBOUNCE_ABSENT_MS      2000

esp_err_t config_init(void)
{
    ESP_LOGI(TAG, "Configuration store initialized");
    return ESP_OK;
}

bool config_is_provisioned(void)
{
    /* TODO: Check NVS for provisioned flag */
    return false;
}

bool config_has_wifi(void)
{
    /* TODO: Check NVS for WiFi credentials */
    return false;
}

esp_err_t config_get_wifi(char *ssid, size_t ssid_len,
                          char *password, size_t pass_len)
{
    return ESP_ERR_NOT_FOUND;
}

esp_err_t config_set_wifi(const char *ssid, const char *password)
{
    return ESP_ERR_NOT_SUPPORTED;
}

esp_err_t config_get_rfid(rfid_config_t *config)
{
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Return defaults for now */
    config->poll_interval_ms = DEFAULT_POLL_INTERVAL_MS;
    config->rf_power_dbm = DEFAULT_RF_POWER_DBM;
    config->debounce_present_ms = DEFAULT_DEBOUNCE_PRESENT_MS;
    config->debounce_absent_ms = DEFAULT_DEBOUNCE_ABSENT_MS;

    return ESP_OK;
}

esp_err_t config_set_rfid(const rfid_config_t *config)
{
    return ESP_ERR_NOT_SUPPORTED;
}

esp_err_t config_get_hub_id(char *hub_id, size_t max_len)
{
    return ESP_ERR_NOT_FOUND;
}

esp_err_t config_factory_reset(void)
{
    ESP_LOGW(TAG, "Factory reset requested");
    return nvs_flash_erase();
}
