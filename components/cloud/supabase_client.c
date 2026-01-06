/**
 * @file supabase_client.c
 * @brief Supabase REST API client implementation
 *
 * Provides authenticated HTTP requests to Supabase for the Saturday Vinyl Hub.
 * Uses ESP-IDF's esp_http_client with TLS certificate bundle.
 *
 * Phase 5: Supabase Integration
 */

#include "supabase_client.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "esp_crt_bundle.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "SUPABASE";

/*******************************************************************************
 * Embedded CA Certificate for Supabase (Google Trust Services)
 ******************************************************************************/
extern const char supabase_ca_pem_start[] asm("_binary_supabase_ca_pem_start");
extern const char supabase_ca_pem_end[] asm("_binary_supabase_ca_pem_end");

/*******************************************************************************
 * NVS Configuration
 ******************************************************************************/

#define NVS_NAMESPACE_SUPABASE  "sv_supabase"
#define NVS_KEY_URL             "url"
#define NVS_KEY_ANON_KEY        "anon_key"
#define NVS_KEY_DEVICE_SECRET   "dev_secret"
#define NVS_KEY_UNIT_ID         "unit_id"

/*******************************************************************************
 * Constants
 ******************************************************************************/

#define DEFAULT_TIMEOUT_MS      10000
#define MAX_RESPONSE_SIZE       4096
#define MAX_URL_SIZE            256

/*******************************************************************************
 * Internal State
 ******************************************************************************/

typedef struct {
    bool initialized;
    bool configured;
    supabase_config_t config;
} supabase_state_t;

static supabase_state_t s_state = {0};

/*******************************************************************************
 * HTTP Response Buffer
 ******************************************************************************/

typedef struct {
    char *buffer;
    size_t buffer_size;
    size_t data_len;
} response_buffer_t;

/**
 * @brief HTTP event handler for response collection
 */
static esp_err_t http_event_handler(esp_http_client_event_t *evt)
{
    response_buffer_t *resp_buf = (response_buffer_t *)evt->user_data;

    switch (evt->event_id) {
        case HTTP_EVENT_ERROR:
            ESP_LOGD(TAG, "HTTP_EVENT_ERROR");
            break;

        case HTTP_EVENT_ON_CONNECTED:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_CONNECTED");
            break;

        case HTTP_EVENT_ON_DATA:
            if (resp_buf != NULL && resp_buf->buffer != NULL) {
                size_t space_left = resp_buf->buffer_size - resp_buf->data_len - 1;
                size_t copy_len = (evt->data_len < space_left) ? evt->data_len : space_left;
                if (copy_len > 0) {
                    memcpy(resp_buf->buffer + resp_buf->data_len, evt->data, copy_len);
                    resp_buf->data_len += copy_len;
                    resp_buf->buffer[resp_buf->data_len] = '\0';
                }
                if (evt->data_len > space_left) {
                    ESP_LOGW(TAG, "Response truncated (buffer full)");
                }
            }
            break;

        case HTTP_EVENT_ON_FINISH:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_FINISH");
            break;

        case HTTP_EVENT_DISCONNECTED:
            ESP_LOGD(TAG, "HTTP_EVENT_DISCONNECTED");
            break;

        default:
            break;
    }
    return ESP_OK;
}

/*******************************************************************************
 * NVS Operations
 ******************************************************************************/

/**
 * @brief Load configuration from NVS
 */
static esp_err_t load_config_from_nvs(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_SUPABASE, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        ESP_LOGD(TAG, "Supabase config not found in NVS");
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(err));
        return err;
    }

    /* Read URL */
    size_t len = sizeof(s_state.config.url);
    err = nvs_get_str(handle, NVS_KEY_URL, s_state.config.url, &len);
    if (err != ESP_OK) {
        nvs_close(handle);
        return ESP_ERR_NOT_FOUND;
    }

    /* Read anon key */
    len = sizeof(s_state.config.anon_key);
    err = nvs_get_str(handle, NVS_KEY_ANON_KEY, s_state.config.anon_key, &len);
    if (err != ESP_OK) {
        nvs_close(handle);
        memset(&s_state.config, 0, sizeof(s_state.config));
        return ESP_ERR_NOT_FOUND;
    }

    /* Read device secret (optional) */
    len = sizeof(s_state.config.device_secret);
    if (nvs_get_str(handle, NVS_KEY_DEVICE_SECRET, s_state.config.device_secret, &len) != ESP_OK) {
        s_state.config.device_secret[0] = '\0';
    }

    /* Read unit ID (optional) */
    len = sizeof(s_state.config.unit_id);
    if (nvs_get_str(handle, NVS_KEY_UNIT_ID, s_state.config.unit_id, &len) != ESP_OK) {
        s_state.config.unit_id[0] = '\0';
    }

    nvs_close(handle);

    s_state.configured = true;
    ESP_LOGI(TAG, "Loaded config from NVS (unit_id=%s)",
             s_state.config.unit_id[0] ? s_state.config.unit_id : "not set");
    return ESP_OK;
}

/**
 * @brief Save configuration to NVS
 */
static esp_err_t save_config_to_nvs(const supabase_config_t *config)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_SUPABASE, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for writing: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_set_str(handle, NVS_KEY_URL, config->url);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_str(handle, NVS_KEY_ANON_KEY, config->anon_key);
    if (err != ESP_OK) goto cleanup;

    if (config->device_secret[0]) {
        err = nvs_set_str(handle, NVS_KEY_DEVICE_SECRET, config->device_secret);
        if (err != ESP_OK) goto cleanup;
    }

    if (config->unit_id[0]) {
        err = nvs_set_str(handle, NVS_KEY_UNIT_ID, config->unit_id);
        if (err != ESP_OK) goto cleanup;
    }

    err = nvs_commit(handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(err));
    }

cleanup:
    nvs_close(handle);
    return err;
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t supabase_init(void)
{
    if (s_state.initialized) {
        return ESP_OK;
    }

    memset(&s_state, 0, sizeof(s_state));

    /* Try to load configuration from NVS */
    esp_err_t err = load_config_from_nvs();
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Supabase client initialized with stored config");
    } else {
        ESP_LOGI(TAG, "Supabase client initialized (no config yet)");
    }

    s_state.initialized = true;
    return ESP_OK;
}

esp_err_t supabase_deinit(void)
{
    memset(&s_state, 0, sizeof(s_state));
    ESP_LOGI(TAG, "Supabase client deinitialized");
    return ESP_OK;
}

bool supabase_is_configured(void)
{
    return s_state.configured &&
           s_state.config.url[0] != '\0' &&
           s_state.config.anon_key[0] != '\0';
}

esp_err_t supabase_get_config(supabase_config_t *config)
{
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!supabase_is_configured()) {
        return ESP_ERR_NOT_FOUND;
    }

    memcpy(config, &s_state.config, sizeof(supabase_config_t));
    return ESP_OK;
}

esp_err_t supabase_set_config(const supabase_config_t *config)
{
    if (config == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (config->url[0] == '\0') {
        ESP_LOGE(TAG, "URL is required");
        return ESP_ERR_INVALID_ARG;
    }

    if (config->anon_key[0] == '\0') {
        ESP_LOGE(TAG, "Anon key is required");
        return ESP_ERR_INVALID_ARG;
    }

    /* Save to NVS */
    esp_err_t err = save_config_to_nvs(config);
    if (err != ESP_OK) {
        return err;
    }

    /* Update runtime config */
    memcpy(&s_state.config, config, sizeof(supabase_config_t));
    s_state.configured = true;

    ESP_LOGI(TAG, "Supabase config saved (unit_id=%s)",
             config->unit_id[0] ? config->unit_id : "not set");
    return ESP_OK;
}

esp_err_t supabase_clear_config(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_SUPABASE, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;  /* Nothing to clear */
    } else if (err != ESP_OK) {
        return err;
    }

    nvs_erase_key(handle, NVS_KEY_URL);
    nvs_erase_key(handle, NVS_KEY_ANON_KEY);
    nvs_erase_key(handle, NVS_KEY_DEVICE_SECRET);
    nvs_erase_key(handle, NVS_KEY_UNIT_ID);

    err = nvs_commit(handle);
    nvs_close(handle);

    memset(&s_state.config, 0, sizeof(s_state.config));
    s_state.configured = false;

    ESP_LOGI(TAG, "Supabase config cleared");
    return err;
}

esp_err_t supabase_post(const char *table, const char *json_body,
                        supabase_response_t *response, uint32_t timeout_ms)
{
    if (table == NULL || json_body == NULL || response == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!supabase_is_configured()) {
        ESP_LOGE(TAG, "Supabase not configured");
        return ESP_ERR_INVALID_STATE;
    }

    /* Initialize response */
    memset(response, 0, sizeof(supabase_response_t));

    /* Build URL: {base_url}/rest/v1/{table} */
    char url[MAX_URL_SIZE];
    int url_len = snprintf(url, sizeof(url), "%s/rest/v1/%s",
                           s_state.config.url, table);
    if (url_len >= sizeof(url)) {
        ESP_LOGE(TAG, "URL too long");
        return ESP_ERR_INVALID_SIZE;
    }

    /* Allocate response buffer */
    response_buffer_t resp_buf = {
        .buffer = malloc(MAX_RESPONSE_SIZE),
        .buffer_size = MAX_RESPONSE_SIZE,
        .data_len = 0,
    };
    if (resp_buf.buffer == NULL) {
        ESP_LOGE(TAG, "Failed to allocate response buffer");
        return ESP_ERR_NO_MEM;
    }
    resp_buf.buffer[0] = '\0';

    /* Configure HTTP client with embedded Supabase CA certificate */
    esp_http_client_config_t http_config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = (timeout_ms > 0) ? timeout_ms : DEFAULT_TIMEOUT_MS,
        .cert_pem = supabase_ca_pem_start,
        .buffer_size = 2048,        /* Receive buffer */
        .buffer_size_tx = 1024,     /* Transmit buffer - needs room for long auth headers */
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_config);
    if (client == NULL) {
        ESP_LOGE(TAG, "Failed to initialize HTTP client");
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    /* Set headers */
    esp_http_client_set_method(client, HTTP_METHOD_POST);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_header(client, "apikey", s_state.config.anon_key);

    /* Build Authorization header: Bearer {anon_key} */
    char auth_header[SUPABASE_ANON_KEY_MAX_LEN + 8];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_state.config.anon_key);
    esp_http_client_set_header(client, "Authorization", auth_header);

    /* Prefer header to get representation back */
    esp_http_client_set_header(client, "Prefer", "return=minimal");

    /* Set request body */
    esp_http_client_set_post_field(client, json_body, strlen(json_body));

    /* Record start time */
    int64_t start_time = esp_timer_get_time();

    /* Perform request */
    ESP_LOGD(TAG, "POST %s", url);
    esp_err_t err = esp_http_client_perform(client);

    /* Calculate request time */
    response->request_time_ms = (esp_timer_get_time() - start_time) / 1000;

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "HTTP request failed: %s", esp_err_to_name(err));
        esp_http_client_cleanup(client);
        free(resp_buf.buffer);
        return err;
    }

    /* Get response status */
    response->status_code = esp_http_client_get_status_code(client);
    response->body = resp_buf.buffer;
    response->body_len = resp_buf.data_len;

    esp_http_client_cleanup(client);

    /* Log result */
    if (response->status_code >= 200 && response->status_code < 300) {
        ESP_LOGI(TAG, "POST %s: %d (%lldms)",
                 table, response->status_code, response->request_time_ms);
    } else {
        ESP_LOGW(TAG, "POST %s: %d (%lldms) - %s",
                 table, response->status_code, response->request_time_ms,
                 response->body ? response->body : "(no body)");
    }

    return ESP_OK;
}

void supabase_response_free(supabase_response_t *response)
{
    if (response != NULL && response->body != NULL) {
        free(response->body);
        response->body = NULL;
        response->body_len = 0;
    }
}

esp_err_t supabase_get_unit_id(char *unit_id, size_t max_len)
{
    if (unit_id == NULL || max_len == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!s_state.configured || s_state.config.unit_id[0] == '\0') {
        return ESP_ERR_NOT_FOUND;
    }

    strncpy(unit_id, s_state.config.unit_id, max_len - 1);
    unit_id[max_len - 1] = '\0';
    return ESP_OK;
}

esp_err_t supabase_test_connection(void)
{
    if (!supabase_is_configured()) {
        ESP_LOGW(TAG, "Cannot test connection - not configured");
        return ESP_ERR_INVALID_STATE;
    }

    /* Make a simple health check request to the base URL */
    char url[MAX_URL_SIZE];
    snprintf(url, sizeof(url), "%s/rest/v1/", s_state.config.url);

    /* Allocate response buffer */
    response_buffer_t resp_buf = {
        .buffer = malloc(1024),
        .buffer_size = 1024,
        .data_len = 0,
    };
    if (resp_buf.buffer == NULL) {
        return ESP_ERR_NO_MEM;
    }

    esp_http_client_config_t http_config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = 5000,
        .cert_pem = supabase_ca_pem_start,
        .buffer_size = 2048,
        .buffer_size_tx = 1024,
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_config);
    if (client == NULL) {
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    esp_http_client_set_header(client, "apikey", s_state.config.anon_key);

    esp_err_t err = esp_http_client_perform(client);
    int status = esp_http_client_get_status_code(client);

    esp_http_client_cleanup(client);
    free(resp_buf.buffer);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Connection test failed: %s", esp_err_to_name(err));
        return err;
    }

    if (status >= 200 && status < 500) {
        ESP_LOGI(TAG, "Connection test passed (status=%d)", status);
        return ESP_OK;
    }

    ESP_LOGW(TAG, "Connection test returned status %d", status);
    return ESP_FAIL;
}
