/**
 * @file ota_manager.c
 * @brief Over-The-Air (OTA) firmware update manager implementation
 *
 * Phase PROD-1: OTA Updates
 */

#include "ota_manager.h"
#include "app_config.h"
#include "supabase_client.h"
#include "http_client.h"

#include <string.h>
#include <stdlib.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_https_ota.h"
#include "esp_http_client.h"
#include "esp_partition.h"
#include "esp_app_format.h"
#include "esp_timer.h"
#include "esp_crt_bundle.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "cJSON.h"

static const char *TAG = "ota_manager";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/
ESP_EVENT_DEFINE_BASE(OTA_EVENTS);

/*******************************************************************************
 * NVS Keys
 ******************************************************************************/
#define NVS_NAMESPACE           "sv_ota"
#define NVS_KEY_H2_PENDING      "h2_pending"
#define NVS_KEY_H2_VER_MAJOR    "h2_ver_maj"
#define NVS_KEY_H2_VER_MINOR    "h2_ver_min"
#define NVS_KEY_H2_VER_PATCH    "h2_ver_pat"
#define NVS_KEY_UPDATES_OK      "updates_ok"
#define NVS_KEY_UPDATES_FAIL    "updates_fail"
#define NVS_KEY_ROLLBACKS       "rollbacks"

/*******************************************************************************
 * Constants
 ******************************************************************************/
#define OTA_TASK_STACK_SIZE     8192
#define OTA_TASK_PRIORITY       5
#define OTA_BUFFER_SIZE         4096
#define FIRMWARE_INFO_ENDPOINT  "/rest/v1/firmware_versions?select=*&device_type=eq.hub&order=created_at.desc&limit=1"
#define H2_FW_PARTITION_LABEL   "h2_fw"

/*******************************************************************************
 * Module State
 ******************************************************************************/

typedef struct {
    bool initialized;
    ota_config_t config;
    SemaphoreHandle_t mutex;

    // Boot status
    ota_boot_status_t boot_status;
    bool boot_validated;

    // Update state
    bool update_in_progress;
    bool abort_requested;
    ota_firmware_type_t updating_firmware;
    uint8_t progress;

    // Cached update info
    ota_update_info_t update_info;
    bool update_info_valid;

    // Statistics (persisted to NVS)
    uint32_t updates_applied;
    uint32_t updates_failed;
    uint32_t rollbacks;

    // Timestamps
    int64_t last_check_time;

    // Task handle
    TaskHandle_t task_handle;
} ota_state_t;

static ota_state_t s_state = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/
static void ota_task(void *pvParameters);
static esp_err_t check_firmware_versions(ota_update_info_t *info);
static esp_err_t perform_s3_update(const char *url);
static esp_err_t perform_h2_update(const char *url);
static void load_stats_from_nvs(void);
static void save_stats_to_nvs(void);
static esp_err_t http_event_handler(esp_http_client_event_t *evt);
static int compare_versions(const ota_version_t *a, const ota_version_t *b);
static void parse_version_string(const char *str, ota_version_t *version);
static void post_event(ota_event_type_t event, void *data, size_t data_size);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t ota_manager_init(const ota_config_t *config)
{
    if (s_state.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing OTA manager");

    // Apply configuration
    if (config != NULL) {
        s_state.config = *config;
    } else {
        ota_config_t defaults = OTA_CONFIG_DEFAULT();
        s_state.config = defaults;
    }

    // Create mutex
    s_state.mutex = xSemaphoreCreateMutex();
    if (s_state.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    // Load statistics from NVS
    load_stats_from_nvs();

    // Check boot status
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;

    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
        switch (ota_state) {
            case ESP_OTA_IMG_NEW:
            case ESP_OTA_IMG_PENDING_VERIFY:
                ESP_LOGW(TAG, "First boot after OTA update - awaiting validation");
                s_state.boot_status = OTA_BOOT_PENDING_VERIFY;
                break;

            case ESP_OTA_IMG_VALID:
                s_state.boot_status = OTA_BOOT_NORMAL;
                break;

            case ESP_OTA_IMG_ABORTED:
                ESP_LOGW(TAG, "Previous OTA was aborted - rolled back");
                s_state.boot_status = OTA_BOOT_ROLLBACK;
                s_state.rollbacks++;
                save_stats_to_nvs();
                post_event(OTA_EVENT_ROLLBACK_TRIGGERED, NULL, 0);
                break;

            default:
                s_state.boot_status = OTA_BOOT_NORMAL;
                break;
        }
    } else {
        // Factory partition doesn't have OTA state
        s_state.boot_status = OTA_BOOT_NORMAL;
    }

    // Get running version
    s_state.update_info.s3_current.major = FW_VERSION_MAJOR;
    s_state.update_info.s3_current.minor = FW_VERSION_MINOR;
    s_state.update_info.s3_current.patch = FW_VERSION_PATCH;
    snprintf(s_state.update_info.s3_current.string,
             sizeof(s_state.update_info.s3_current.string),
             "%d.%d.%d", FW_VERSION_MAJOR, FW_VERSION_MINOR, FW_VERSION_PATCH);

    ESP_LOGI(TAG, "Running firmware version: %s", s_state.update_info.s3_current.string);
    ESP_LOGI(TAG, "Running from partition: %s (0x%lx)",
             running->label, (unsigned long)running->address);
    ESP_LOGI(TAG, "Boot status: %s",
             s_state.boot_status == OTA_BOOT_NORMAL ? "normal" :
             s_state.boot_status == OTA_BOOT_PENDING_VERIFY ? "pending verify" : "rollback");

    s_state.initialized = true;
    return ESP_OK;
}

esp_err_t ota_manager_deinit(void)
{
    if (!s_state.initialized) {
        return ESP_OK;
    }

    // Stop task if running
    if (s_state.task_handle != NULL) {
        s_state.abort_requested = true;
        // Wait for task to finish
        vTaskDelay(pdMS_TO_TICKS(1000));
        s_state.task_handle = NULL;
    }

    if (s_state.mutex != NULL) {
        vSemaphoreDelete(s_state.mutex);
        s_state.mutex = NULL;
    }

    s_state.initialized = false;
    return ESP_OK;
}

/*******************************************************************************
 * Boot Validation
 ******************************************************************************/

esp_err_t ota_manager_validate_boot(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.boot_status != OTA_BOOT_PENDING_VERIFY) {
        ESP_LOGD(TAG, "Boot already validated or not pending");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Validating boot - marking OTA partition as valid");

    esp_err_t ret = esp_ota_mark_app_valid_cancel_rollback();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to mark app valid: %s", esp_err_to_name(ret));
        return ret;
    }

    s_state.boot_status = OTA_BOOT_NORMAL;
    s_state.boot_validated = true;
    s_state.updates_applied++;
    save_stats_to_nvs();

    post_event(OTA_EVENT_BOOT_VALIDATED, NULL, 0);

    ESP_LOGI(TAG, "Boot validated successfully");
    return ESP_OK;
}

ota_boot_status_t ota_manager_get_boot_status(void)
{
    return s_state.boot_status;
}

/*******************************************************************************
 * Update Checking
 ******************************************************************************/

esp_err_t ota_manager_check_update(ota_update_info_t *info)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.update_in_progress) {
        ESP_LOGW(TAG, "Update already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Checking for firmware updates...");
    post_event(OTA_EVENT_CHECK_START, NULL, 0);

    esp_err_t ret = check_firmware_versions(&s_state.update_info);

    s_state.last_check_time = esp_timer_get_time();
    s_state.update_info_valid = (ret == ESP_OK);

    post_event(OTA_EVENT_CHECK_COMPLETE, NULL, 0);

    if (ret == ESP_OK) {
        if (s_state.update_info.s3_update_available ||
            s_state.update_info.h2_update_available) {

            ESP_LOGI(TAG, "Updates available - S3: %s, H2: %s",
                     s_state.update_info.s3_update_available ? "yes" : "no",
                     s_state.update_info.h2_update_available ? "yes" : "no");

            post_event(OTA_EVENT_UPDATE_AVAILABLE, &s_state.update_info,
                      sizeof(ota_update_info_t));
        } else {
            ESP_LOGI(TAG, "Firmware is up to date");
        }

        if (info != NULL) {
            *info = s_state.update_info;
        }
    }

    return ret;
}

static esp_err_t check_firmware_versions(ota_update_info_t *info)
{
    if (!supabase_is_configured()) {
        ESP_LOGW(TAG, "Supabase not configured - cannot check updates");
        return ESP_ERR_INVALID_STATE;
    }

    supabase_config_t sb_config;
    esp_err_t ret = supabase_get_config(&sb_config);
    if (ret != ESP_OK) {
        return ret;
    }

    // Build URL for firmware versions endpoint
    char url[384];
    snprintf(url, sizeof(url), "%s%s", sb_config.url, FIRMWARE_INFO_ENDPOINT);

    http_response_t response = {0};
    ret = http_get(url, &response, 10000);

    if (ret != ESP_OK || response.status_code != 200) {
        ESP_LOGE(TAG, "Failed to fetch firmware info: %s (status=%d)",
                 esp_err_to_name(ret), response.status_code);
        http_response_free(&response);
        return ret != ESP_OK ? ret : ESP_FAIL;
    }

    // Parse JSON response
    cJSON *root = cJSON_Parse(response.body);
    http_response_free(&response);

    if (root == NULL) {
        ESP_LOGE(TAG, "Failed to parse firmware info JSON");
        return ESP_FAIL;
    }

    // Response is an array, get first element
    cJSON *item = cJSON_GetArrayItem(root, 0);
    if (item == NULL) {
        ESP_LOGW(TAG, "No firmware versions found in response");
        cJSON_Delete(root);
        return ESP_OK;  // Not an error, just no updates
    }

    // Extract S3 firmware info
    cJSON *s3_version = cJSON_GetObjectItem(item, "s3_version");
    cJSON *s3_url = cJSON_GetObjectItem(item, "s3_url");
    cJSON *h2_version = cJSON_GetObjectItem(item, "h2_version");
    cJSON *h2_url = cJSON_GetObjectItem(item, "h2_url");

    if (s3_version && cJSON_IsString(s3_version)) {
        parse_version_string(s3_version->valuestring, &info->s3_available);

        // Compare versions
        if (compare_versions(&info->s3_available, &info->s3_current) > 0) {
            info->s3_update_available = true;
            ESP_LOGI(TAG, "S3 update available: %s -> %s",
                     info->s3_current.string, info->s3_available.string);

            if (s3_url && cJSON_IsString(s3_url)) {
                strncpy(info->s3_url, s3_url->valuestring, sizeof(info->s3_url) - 1);
            }
        }
    }

    if (h2_version && cJSON_IsString(h2_version)) {
        parse_version_string(h2_version->valuestring, &info->h2_available);

        if (compare_versions(&info->h2_available, &info->h2_current) > 0) {
            info->h2_update_available = true;
            ESP_LOGI(TAG, "H2 update available: %s -> %s",
                     info->h2_current.string, info->h2_available.string);

            if (h2_url && cJSON_IsString(h2_url)) {
                strncpy(info->h2_url, h2_url->valuestring, sizeof(info->h2_url) - 1);
            }
        }
    }

    cJSON_Delete(root);
    return ESP_OK;
}

/*******************************************************************************
 * S3 Update
 ******************************************************************************/

esp_err_t ota_manager_update_s3(const char *url)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.update_in_progress) {
        ESP_LOGW(TAG, "Update already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    const char *download_url = url;
    if (download_url == NULL) {
        if (!s_state.update_info_valid || strlen(s_state.update_info.s3_url) == 0) {
            ESP_LOGE(TAG, "No S3 firmware URL available - run check_update first");
            return ESP_ERR_INVALID_ARG;
        }
        download_url = s_state.update_info.s3_url;
    }

    ESP_LOGI(TAG, "Starting S3 firmware update from: %s", download_url);

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.update_in_progress = true;
    s_state.abort_requested = false;
    s_state.updating_firmware = OTA_FIRMWARE_S3;
    s_state.progress = 0;
    xSemaphoreGive(s_state.mutex);

    post_event(OTA_EVENT_UPDATE_START, NULL, 0);

    esp_err_t ret = perform_s3_update(download_url);

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.update_in_progress = false;
    xSemaphoreGive(s_state.mutex);

    ota_result_data_t result = {
        .firmware = OTA_FIRMWARE_S3,
        .error = ret,
    };

    if (ret == ESP_OK) {
        strncpy(result.version, s_state.update_info.s3_available.string,
                sizeof(result.version) - 1);
        post_event(OTA_EVENT_UPDATE_COMPLETE, &result, sizeof(result));
        ESP_LOGI(TAG, "S3 update complete - reboot required");
    } else {
        s_state.updates_failed++;
        save_stats_to_nvs();
        post_event(OTA_EVENT_UPDATE_FAILED, &result, sizeof(result));
        ESP_LOGE(TAG, "S3 update failed: %s", esp_err_to_name(ret));
    }

    return ret;
}

static esp_err_t perform_s3_update(const char *url)
{
    esp_http_client_config_t http_config = {
        .url = url,
        .timeout_ms = s_state.config.download_timeout_sec * 1000,
        .event_handler = http_event_handler,
        .keep_alive_enable = true,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };

    esp_https_ota_config_t ota_config = {
        .http_config = &http_config,
    };

    esp_https_ota_handle_t https_ota_handle = NULL;
    esp_err_t ret = esp_https_ota_begin(&ota_config, &https_ota_handle);

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "OTA begin failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Get image size
    int image_size = esp_https_ota_get_image_size(https_ota_handle);
    ESP_LOGI(TAG, "Firmware image size: %d bytes", image_size);

    // Download and flash
    int bytes_written = 0;
    while (1) {
        if (s_state.abort_requested) {
            ESP_LOGW(TAG, "Update aborted by user");
            esp_https_ota_abort(https_ota_handle);
            return ESP_ERR_INVALID_STATE;
        }

        ret = esp_https_ota_perform(https_ota_handle);

        if (ret != ESP_ERR_HTTPS_OTA_IN_PROGRESS) {
            break;
        }

        // Update progress
        bytes_written = esp_https_ota_get_image_len_read(https_ota_handle);

        xSemaphoreTake(s_state.mutex, portMAX_DELAY);
        if (image_size > 0) {
            s_state.progress = (bytes_written * 100) / image_size;
        }
        xSemaphoreGive(s_state.mutex);

        ota_progress_data_t progress = {
            .firmware = OTA_FIRMWARE_S3,
            .percentage = s_state.progress,
            .bytes_written = bytes_written,
            .total_bytes = image_size,
        };
        post_event(OTA_EVENT_UPDATE_PROGRESS, &progress, sizeof(progress));

        // Yield to other tasks
        vTaskDelay(pdMS_TO_TICKS(10));
    }

    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "OTA perform failed: %s", esp_err_to_name(ret));
        esp_https_ota_abort(https_ota_handle);
        return ret;
    }

    // Verify image
    if (!esp_https_ota_is_complete_data_received(https_ota_handle)) {
        ESP_LOGE(TAG, "Incomplete firmware image received");
        esp_https_ota_abort(https_ota_handle);
        return ESP_FAIL;
    }

    // Finish OTA
    ret = esp_https_ota_finish(https_ota_handle);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "OTA finish failed: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "S3 OTA update written successfully");
    return ESP_OK;
}

/*******************************************************************************
 * H2 Update (Staging)
 ******************************************************************************/

esp_err_t ota_manager_update_h2(const char *url)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.update_in_progress) {
        ESP_LOGW(TAG, "Update already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    const char *download_url = url;
    if (download_url == NULL) {
        if (!s_state.update_info_valid || strlen(s_state.update_info.h2_url) == 0) {
            ESP_LOGE(TAG, "No H2 firmware URL available - run check_update first");
            return ESP_ERR_INVALID_ARG;
        }
        download_url = s_state.update_info.h2_url;
    }

    ESP_LOGI(TAG, "Starting H2 firmware download from: %s", download_url);

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.update_in_progress = true;
    s_state.abort_requested = false;
    s_state.updating_firmware = OTA_FIRMWARE_H2;
    s_state.progress = 0;
    xSemaphoreGive(s_state.mutex);

    post_event(OTA_EVENT_UPDATE_START, NULL, 0);

    esp_err_t ret = perform_h2_update(download_url);

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.update_in_progress = false;
    xSemaphoreGive(s_state.mutex);

    ota_result_data_t result = {
        .firmware = OTA_FIRMWARE_H2,
        .error = ret,
    };

    if (ret == ESP_OK) {
        strncpy(result.version, s_state.update_info.h2_available.string,
                sizeof(result.version) - 1);
        post_event(OTA_EVENT_UPDATE_COMPLETE, &result, sizeof(result));
        ESP_LOGI(TAG, "H2 firmware staged successfully");
    } else {
        s_state.updates_failed++;
        save_stats_to_nvs();
        post_event(OTA_EVENT_UPDATE_FAILED, &result, sizeof(result));
        ESP_LOGE(TAG, "H2 update failed: %s", esp_err_to_name(ret));
    }

    return ret;
}

static esp_err_t perform_h2_update(const char *url)
{
    // Find H2 firmware partition
    const esp_partition_t *h2_partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, 0x40, H2_FW_PARTITION_LABEL);

    if (h2_partition == NULL) {
        ESP_LOGE(TAG, "H2 firmware partition not found");
        return ESP_ERR_NOT_FOUND;
    }

    ESP_LOGI(TAG, "H2 partition: label=%s, addr=0x%lx, size=%lu",
             h2_partition->label,
             (unsigned long)h2_partition->address,
             (unsigned long)h2_partition->size);

    // Erase partition
    ESP_LOGI(TAG, "Erasing H2 firmware partition...");
    esp_err_t ret = esp_partition_erase_range(h2_partition, 0, h2_partition->size);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to erase H2 partition: %s", esp_err_to_name(ret));
        return ret;
    }

    // Download firmware via HTTP
    esp_http_client_config_t http_config = {
        .url = url,
        .timeout_ms = s_state.config.download_timeout_sec * 1000,
        .crt_bundle_attach = esp_crt_bundle_attach,
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_config);
    if (client == NULL) {
        ESP_LOGE(TAG, "Failed to initialize HTTP client");
        return ESP_FAIL;
    }

    ret = esp_http_client_open(client, 0);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open HTTP connection: %s", esp_err_to_name(ret));
        esp_http_client_cleanup(client);
        return ret;
    }

    int content_length = esp_http_client_fetch_headers(client);
    if (content_length <= 0) {
        ESP_LOGE(TAG, "Failed to get content length");
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return ESP_FAIL;
    }

    if ((size_t)content_length > h2_partition->size) {
        ESP_LOGE(TAG, "Firmware too large: %d > %lu",
                 content_length, (unsigned long)h2_partition->size);
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return ESP_ERR_INVALID_SIZE;
    }

    ESP_LOGI(TAG, "H2 firmware size: %d bytes", content_length);

    // Download and write to partition
    uint8_t *buffer = malloc(OTA_BUFFER_SIZE);
    if (buffer == NULL) {
        ESP_LOGE(TAG, "Failed to allocate download buffer");
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return ESP_ERR_NO_MEM;
    }

    size_t total_written = 0;
    while (total_written < (size_t)content_length) {
        if (s_state.abort_requested) {
            ESP_LOGW(TAG, "Update aborted by user");
            ret = ESP_ERR_INVALID_STATE;
            break;
        }

        int read_len = esp_http_client_read(client, (char *)buffer, OTA_BUFFER_SIZE);
        if (read_len < 0) {
            ESP_LOGE(TAG, "HTTP read error");
            ret = ESP_FAIL;
            break;
        }
        if (read_len == 0) {
            break;  // End of stream
        }

        ret = esp_partition_write(h2_partition, total_written, buffer, read_len);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to write to H2 partition: %s", esp_err_to_name(ret));
            break;
        }

        total_written += read_len;

        // Update progress
        xSemaphoreTake(s_state.mutex, portMAX_DELAY);
        s_state.progress = (total_written * 100) / content_length;
        xSemaphoreGive(s_state.mutex);

        ota_progress_data_t progress = {
            .firmware = OTA_FIRMWARE_H2,
            .percentage = s_state.progress,
            .bytes_written = total_written,
            .total_bytes = content_length,
        };
        post_event(OTA_EVENT_UPDATE_PROGRESS, &progress, sizeof(progress));
    }

    free(buffer);
    esp_http_client_close(client);
    esp_http_client_cleanup(client);

    if (ret != ESP_OK || total_written != (size_t)content_length) {
        ESP_LOGE(TAG, "H2 download incomplete: %zu / %d bytes",
                 total_written, content_length);
        return ret != ESP_OK ? ret : ESP_FAIL;
    }

    // Mark H2 update as pending in NVS
    nvs_handle_t nvs;
    ret = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs);
    if (ret == ESP_OK) {
        nvs_set_u8(nvs, NVS_KEY_H2_PENDING, 1);
        nvs_set_u8(nvs, NVS_KEY_H2_VER_MAJOR, s_state.update_info.h2_available.major);
        nvs_set_u8(nvs, NVS_KEY_H2_VER_MINOR, s_state.update_info.h2_available.minor);
        nvs_set_u8(nvs, NVS_KEY_H2_VER_PATCH, s_state.update_info.h2_available.patch);
        nvs_commit(nvs);
        nvs_close(nvs);
    }

    ESP_LOGI(TAG, "H2 firmware written to staging partition: %zu bytes", total_written);
    return ESP_OK;
}

bool ota_manager_h2_update_pending(void)
{
    nvs_handle_t nvs;
    uint8_t pending = 0;

    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        nvs_get_u8(nvs, NVS_KEY_H2_PENDING, &pending);
        nvs_close(nvs);
    }

    return pending != 0;
}

esp_err_t ota_manager_h2_update_complete(bool success)
{
    nvs_handle_t nvs;
    esp_err_t ret = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs);

    if (ret != ESP_OK) {
        return ret;
    }

    nvs_set_u8(nvs, NVS_KEY_H2_PENDING, 0);

    if (success) {
        s_state.updates_applied++;
        ESP_LOGI(TAG, "H2 update completed successfully");
    } else {
        s_state.updates_failed++;
        ESP_LOGW(TAG, "H2 update failed");
    }

    nvs_commit(nvs);
    nvs_close(nvs);

    save_stats_to_nvs();
    return ESP_OK;
}

esp_err_t ota_manager_get_staged_h2_version(ota_version_t *version)
{
    if (!ota_manager_h2_update_pending()) {
        return ESP_ERR_NOT_FOUND;
    }

    nvs_handle_t nvs;
    esp_err_t ret = nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs);

    if (ret != ESP_OK) {
        return ret;
    }

    nvs_get_u8(nvs, NVS_KEY_H2_VER_MAJOR, &version->major);
    nvs_get_u8(nvs, NVS_KEY_H2_VER_MINOR, &version->minor);
    nvs_get_u8(nvs, NVS_KEY_H2_VER_PATCH, &version->patch);

    snprintf(version->string, sizeof(version->string), "%d.%d.%d",
             version->major, version->minor, version->patch);

    nvs_close(nvs);
    return ESP_OK;
}

/*******************************************************************************
 * Update All
 ******************************************************************************/

esp_err_t ota_manager_update_all(void)
{
    esp_err_t ret = ESP_OK;

    if (s_state.update_info.s3_update_available) {
        ret = ota_manager_update_s3(NULL);
        if (ret != ESP_OK) {
            return ret;
        }
    }

    if (s_state.update_info.h2_update_available) {
        ret = ota_manager_update_h2(NULL);
        if (ret != ESP_OK) {
            return ret;
        }
    }

    return ret;
}

/*******************************************************************************
 * Control
 ******************************************************************************/

esp_err_t ota_manager_abort(void)
{
    if (!s_state.update_in_progress) {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGW(TAG, "Aborting OTA update");
    s_state.abort_requested = true;

    return ESP_OK;
}

void ota_manager_reboot(uint32_t delay_ms)
{
    if (delay_ms > 0) {
        ESP_LOGI(TAG, "Rebooting in %lu ms...", (unsigned long)delay_ms);
        vTaskDelay(pdMS_TO_TICKS(delay_ms));
    }

    ESP_LOGI(TAG, "Rebooting to apply update...");
    esp_restart();
}

/*******************************************************************************
 * Status
 ******************************************************************************/

esp_err_t ota_manager_get_status(ota_status_t *status)
{
    if (!s_state.initialized || status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);

    status->initialized = s_state.initialized;
    status->boot_status = s_state.boot_status;
    status->update_in_progress = s_state.update_in_progress;
    status->updating = s_state.updating_firmware;
    status->progress = s_state.progress;
    status->running_version = s_state.update_info.s3_current;
    status->h2_version = s_state.update_info.h2_current;
    status->updates_applied = s_state.updates_applied;
    status->updates_failed = s_state.updates_failed;
    status->rollbacks = s_state.rollbacks;
    status->last_check_time = s_state.last_check_time;

    xSemaphoreGive(s_state.mutex);

    return ESP_OK;
}

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static void load_stats_from_nvs(void)
{
    nvs_handle_t nvs;

    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs) == ESP_OK) {
        nvs_get_u32(nvs, NVS_KEY_UPDATES_OK, &s_state.updates_applied);
        nvs_get_u32(nvs, NVS_KEY_UPDATES_FAIL, &s_state.updates_failed);
        nvs_get_u32(nvs, NVS_KEY_ROLLBACKS, &s_state.rollbacks);
        nvs_close(nvs);

        ESP_LOGI(TAG, "OTA stats: applied=%lu, failed=%lu, rollbacks=%lu",
                 (unsigned long)s_state.updates_applied,
                 (unsigned long)s_state.updates_failed,
                 (unsigned long)s_state.rollbacks);
    }
}

static void save_stats_to_nvs(void)
{
    nvs_handle_t nvs;

    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs) == ESP_OK) {
        nvs_set_u32(nvs, NVS_KEY_UPDATES_OK, s_state.updates_applied);
        nvs_set_u32(nvs, NVS_KEY_UPDATES_FAIL, s_state.updates_failed);
        nvs_set_u32(nvs, NVS_KEY_ROLLBACKS, s_state.rollbacks);
        nvs_commit(nvs);
        nvs_close(nvs);
    }
}

static esp_err_t http_event_handler(esp_http_client_event_t *evt)
{
    switch (evt->event_id) {
        case HTTP_EVENT_ERROR:
            ESP_LOGD(TAG, "HTTP_EVENT_ERROR");
            break;
        case HTTP_EVENT_ON_CONNECTED:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_CONNECTED");
            break;
        case HTTP_EVENT_ON_DATA:
            // Data received - progress tracked elsewhere
            break;
        default:
            break;
    }
    return ESP_OK;
}

static int compare_versions(const ota_version_t *a, const ota_version_t *b)
{
    if (a->major != b->major) {
        return a->major - b->major;
    }
    if (a->minor != b->minor) {
        return a->minor - b->minor;
    }
    return a->patch - b->patch;
}

static void parse_version_string(const char *str, ota_version_t *version)
{
    memset(version, 0, sizeof(*version));

    if (str == NULL || strlen(str) == 0) {
        return;
    }

    // Copy string
    strncpy(version->string, str, sizeof(version->string) - 1);

    // Parse major.minor.patch
    int major = 0, minor = 0, patch = 0;
    sscanf(str, "%d.%d.%d", &major, &minor, &patch);

    version->major = (uint8_t)major;
    version->minor = (uint8_t)minor;
    version->patch = (uint8_t)patch;
}

static void post_event(ota_event_type_t event, void *data, size_t data_size)
{
    esp_event_post(OTA_EVENTS, event, data, data_size, pdMS_TO_TICKS(100));
}

/*******************************************************************************
 * Background Task (for auto-check feature)
 ******************************************************************************/

static void ota_task(void *pvParameters)
{
    TickType_t last_check = 0;

    while (1) {
        TickType_t now = xTaskGetTickCount();

        // Auto-check for updates
        if (s_state.config.check_interval_sec > 0) {
            TickType_t interval_ticks = pdMS_TO_TICKS(s_state.config.check_interval_sec * 1000);

            if ((now - last_check) >= interval_ticks) {
                ESP_LOGI(TAG, "Auto-checking for updates...");
                ota_update_info_t info;

                if (ota_manager_check_update(&info) == ESP_OK) {
                    if (s_state.config.auto_apply &&
                        (info.s3_update_available || info.h2_update_available)) {
                        ESP_LOGI(TAG, "Auto-applying available updates");
                        ota_manager_update_all();

                        if (s_state.config.auto_reboot && info.s3_update_available) {
                            ota_manager_reboot(1000);
                        }
                    }
                }

                last_check = now;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(60000));  // Check every minute
    }
}
