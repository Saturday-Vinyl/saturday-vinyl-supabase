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
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

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

/*
 * HTTP timeout increased for WiFi+Thread radio coexistence.
 * TLS handshake requires multiple round-trips, and with the radio being
 * time-shared between WiFi and 802.15.4, this can take significantly longer.
 * See docs/radio_coexistence_guide.md for details.
 */
#define DEFAULT_TIMEOUT_MS      30000
#define MAX_RESPONSE_SIZE       4096
#define MAX_URL_SIZE            256

/*
 * Retry configuration for TLS handshake failures.
 * The ESP32-C6's single radio with WiFi+Thread coexistence can cause
 * sporadic TLS handshake timeouts due to packet loss during radio arbitration.
 * Retrying with shorter individual timeouts is more effective than one long timeout.
 *
 * With ~5-10% success rate per attempt, 5 retries gives ~40-50% overall success.
 * The event reporter will retry again on the next heartbeat interval if needed.
 */
#define MAX_RETRIES             5       /* Number of retry attempts */
#define RETRY_TIMEOUT_MS        10000   /* 10s timeout per attempt */
#define RETRY_DELAY_MS          500     /* 500ms delay between retries */

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
 * Persistent HTTP Client
 *
 * Keeps a single esp_http_client handle alive across requests. The TLS
 * connection stays open via HTTP keep-alive, eliminating the repeated
 * alloc/free cycle of ~40KB mbedtls buffers that causes heap fragmentation
 * over hours of operation.
 ******************************************************************************/

static esp_http_client_handle_t s_persistent_client = NULL;

/*
 * Mutex protecting the persistent client handle.
 *
 * supabase_post() is called from multiple FreeRTOS task contexts:
 *   - sync_task          (hub heartbeats, now_playing events)
 *   - crate_telemetry_worker (crate telemetry via CBOR → JSON → POST)
 *   - default event loop (inventory updates, crate heartbeats)
 *
 * Without serialization, concurrent esp_http_client_perform() calls on
 * the shared handle corrupt internal state (post-field pointer, TLS
 * buffers) and crash in memcpy with a LoadProhibited exception.
 */
static SemaphoreHandle_t s_client_mutex = NULL;

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

    /* Create mutex for persistent client access */
    if (s_client_mutex == NULL) {
        s_client_mutex = xSemaphoreCreateMutex();
        if (s_client_mutex == NULL) {
            ESP_LOGE(TAG, "Failed to create client mutex");
            return ESP_ERR_NO_MEM;
        }
    }

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

/* Internal: close persistent client without taking the mutex (caller must hold it) */
static void close_connection_locked(void)
{
    if (s_persistent_client != NULL) {
        esp_http_client_cleanup(s_persistent_client);
        s_persistent_client = NULL;
        ESP_LOGI(TAG, "Persistent connection closed");
    }
}

void supabase_close_connection(void)
{
    if (s_client_mutex != NULL) {
        xSemaphoreTake(s_client_mutex, portMAX_DELAY);
    }
    close_connection_locked();
    if (s_client_mutex != NULL) {
        xSemaphoreGive(s_client_mutex);
    }
}

esp_err_t supabase_deinit(void)
{
    supabase_close_connection();
    if (s_client_mutex != NULL) {
        vSemaphoreDelete(s_client_mutex);
        s_client_mutex = NULL;
    }
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

    uint32_t per_attempt_timeout = (timeout_ms > 0) ? timeout_ms : RETRY_TIMEOUT_MS;

    ESP_LOGI(TAG, "POST %s (timeout=%lums)", url, (unsigned long)per_attempt_timeout);

    /* Build Authorization header once (reused across retries) */
    char auth_header[SUPABASE_ANON_KEY_MAX_LEN + 8];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_state.config.anon_key);

    /* Record overall start time */
    int64_t overall_start = esp_timer_get_time();
    esp_err_t err = ESP_FAIL;

    /* Serialize access to the shared persistent HTTP client handle.
     * Multiple tasks (sync_task, crate_telemetry_worker, event loop)
     * may call supabase_post() concurrently. */
    if (s_client_mutex == NULL) {
        ESP_LOGE(TAG, "Client mutex not initialized");
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreTake(s_client_mutex, portMAX_DELAY);

    /* Retry loop — on the first attempt we try to reuse the persistent
     * connection.  If that fails (server closed idle connection, etc.)
     * we tear it down and create a fresh one for subsequent attempts. */
    for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {

        /* Allocate a per-request response buffer (small, doesn't fragment) */
        response_buffer_t resp_buf = {
            .buffer = malloc(MAX_RESPONSE_SIZE),
            .buffer_size = MAX_RESPONSE_SIZE,
            .data_len = 0,
        };
        if (resp_buf.buffer == NULL) {
            ESP_LOGE(TAG, "Failed to allocate response buffer");
            xSemaphoreGive(s_client_mutex);
            return ESP_ERR_NO_MEM;
        }
        resp_buf.buffer[0] = '\0';

        /* Lazy-init or reuse persistent client */
        if (s_persistent_client == NULL) {
            esp_http_client_config_t http_config = {
                .url = url,
                .event_handler = http_event_handler,
                .user_data = &resp_buf,
                .timeout_ms = per_attempt_timeout,
                .cert_pem = supabase_ca_pem_start,
                .buffer_size = 2048,
                .buffer_size_tx = 1024,
                .keep_alive_enable = true,
            };

            s_persistent_client = esp_http_client_init(&http_config);
            if (s_persistent_client == NULL) {
                ESP_LOGE(TAG, "Failed to initialize HTTP client");
                free(resp_buf.buffer);
                xSemaphoreGive(s_client_mutex);
                return ESP_FAIL;
            }
            ESP_LOGI(TAG, "Created persistent HTTP client");
        } else {
            /* Reuse existing client — update per-request fields */
            esp_http_client_set_url(s_persistent_client, url);
            esp_http_client_set_timeout_ms(s_persistent_client, per_attempt_timeout);
        }

        /* Update user_data to point to this request's response buffer */
        esp_http_client_set_user_data(s_persistent_client, &resp_buf);

        /* Set headers and body (safe to call every time) */
        esp_http_client_set_method(s_persistent_client, HTTP_METHOD_POST);
        esp_http_client_set_header(s_persistent_client, "Content-Type", "application/json");
        esp_http_client_set_header(s_persistent_client, "apikey", s_state.config.anon_key);
        esp_http_client_set_header(s_persistent_client, "Authorization", auth_header);
        esp_http_client_set_header(s_persistent_client, "Prefer", "return=minimal");
        esp_http_client_set_post_field(s_persistent_client, json_body, strlen(json_body));

        if (attempt > 1) {
            ESP_LOGI(TAG, "Retry attempt %d/%d...", attempt, MAX_RETRIES);
        }

        err = esp_http_client_perform(s_persistent_client);

        if (err == ESP_OK) {
            response->request_time_ms = (esp_timer_get_time() - overall_start) / 1000;
            response->status_code = esp_http_client_get_status_code(s_persistent_client);
            response->body = resp_buf.buffer;  /* Transfer ownership */
            response->body_len = resp_buf.data_len;

            if (response->status_code >= 200 && response->status_code < 300) {
                ESP_LOGI(TAG, "POST %s: %d (%lldms, attempt %d)",
                         table, response->status_code, response->request_time_ms, attempt);
            } else {
                ESP_LOGW(TAG, "POST %s: %d (%lldms) - %s",
                         table, response->status_code, response->request_time_ms,
                         response->body ? response->body : "(no body)");
            }
            xSemaphoreGive(s_client_mutex);
            return ESP_OK;
        }

        /* Request failed — tear down the persistent client so the next
         * attempt creates a fresh TLS session. */
        free(resp_buf.buffer);
        close_connection_locked();

        if (attempt < MAX_RETRIES) {
            ESP_LOGW(TAG, "Attempt %d failed (%s), retrying in %dms...",
                     attempt, esp_err_to_name(err), RETRY_DELAY_MS);
            vTaskDelay(pdMS_TO_TICKS(RETRY_DELAY_MS));
        } else {
            ESP_LOGE(TAG, "All %d attempts failed, last error: %s",
                     MAX_RETRIES, esp_err_to_name(err));
        }
    }

    /* All retries exhausted */
    xSemaphoreGive(s_client_mutex);
    response->request_time_ms = (esp_timer_get_time() - overall_start) / 1000;
    return err;
}

esp_err_t supabase_get(const char *path, supabase_response_t *response,
                       uint32_t timeout_ms)
{
    if (path == NULL || response == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!supabase_is_configured()) {
        ESP_LOGE(TAG, "Supabase not configured");
        return ESP_ERR_INVALID_STATE;
    }

    memset(response, 0, sizeof(supabase_response_t));

    char url[MAX_URL_SIZE];
    int url_len = snprintf(url, sizeof(url), "%s/rest/v1/%s",
                           s_state.config.url, path);
    if (url_len >= sizeof(url)) {
        ESP_LOGE(TAG, "URL too long");
        return ESP_ERR_INVALID_SIZE;
    }

    uint32_t per_attempt_timeout = (timeout_ms > 0) ? timeout_ms : RETRY_TIMEOUT_MS;

    char auth_header[SUPABASE_ANON_KEY_MAX_LEN + 8];
    snprintf(auth_header, sizeof(auth_header), "Bearer %s", s_state.config.anon_key);

    response_buffer_t resp_buf = {
        .buffer = malloc(MAX_RESPONSE_SIZE),
        .buffer_size = MAX_RESPONSE_SIZE,
        .data_len = 0,
    };
    if (resp_buf.buffer == NULL) {
        return ESP_ERR_NO_MEM;
    }
    resp_buf.buffer[0] = '\0';

    esp_http_client_config_t http_config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = per_attempt_timeout,
        .cert_pem = supabase_ca_pem_start,
        .buffer_size = 2048,
        .buffer_size_tx = 1024,
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_config);
    if (client == NULL) {
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    esp_http_client_set_method(client, HTTP_METHOD_GET);
    esp_http_client_set_header(client, "apikey", s_state.config.anon_key);
    esp_http_client_set_header(client, "Authorization", auth_header);
    esp_http_client_set_header(client, "Accept", "application/json");

    int64_t start = esp_timer_get_time();
    esp_err_t err = esp_http_client_perform(client);
    response->request_time_ms = (esp_timer_get_time() - start) / 1000;

    if (err == ESP_OK) {
        response->status_code = esp_http_client_get_status_code(client);
        response->body = resp_buf.buffer;
        response->body_len = resp_buf.data_len;
        ESP_LOGI(TAG, "GET %s: %d (%lldms)",
                 path, response->status_code, response->request_time_ms);
    } else {
        ESP_LOGE(TAG, "GET %s failed: %s", path, esp_err_to_name(err));
        free(resp_buf.buffer);
    }

    esp_http_client_cleanup(client);
    return err;
}

esp_err_t supabase_function_call(const char *function_name,
                                 const char *method,
                                 const char *json_body,
                                 const char *bearer_override,
                                 supabase_response_t *response,
                                 uint32_t timeout_ms)
{
    if (function_name == NULL || method == NULL || response == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!supabase_is_configured()) {
        ESP_LOGE(TAG, "Supabase not configured");
        return ESP_ERR_INVALID_STATE;
    }

    bool is_post = (strcasecmp(method, "POST") == 0);
    bool is_get  = (strcasecmp(method, "GET")  == 0);
    if (!is_post && !is_get) {
        return ESP_ERR_INVALID_ARG;
    }

    memset(response, 0, sizeof(supabase_response_t));

    /* URL: {base}/functions/v1/{function_name} */
    char url[MAX_URL_SIZE];
    int url_len = snprintf(url, sizeof(url), "%s/functions/v1/%s",
                           s_state.config.url, function_name);
    if (url_len >= (int)sizeof(url)) {
        ESP_LOGE(TAG, "URL too long");
        return ESP_ERR_INVALID_SIZE;
    }

    uint32_t per_attempt_timeout = (timeout_ms > 0) ? timeout_ms : RETRY_TIMEOUT_MS;

    /* Build Authorization header. */
    const char *bearer_value = (bearer_override != NULL) ? bearer_override
                                                         : s_state.config.anon_key;
    /* Supabase JWTs and device session tokens can be ~700-1200 bytes. */
    size_t auth_buf_len = strlen(bearer_value) + 16;
    char *auth_header = malloc(auth_buf_len);
    if (auth_header == NULL) return ESP_ERR_NO_MEM;
    snprintf(auth_header, auth_buf_len, "Bearer %s", bearer_value);

    response_buffer_t resp_buf = {
        .buffer = malloc(MAX_RESPONSE_SIZE),
        .buffer_size = MAX_RESPONSE_SIZE,
        .data_len = 0,
    };
    if (resp_buf.buffer == NULL) {
        free(auth_header);
        return ESP_ERR_NO_MEM;
    }
    resp_buf.buffer[0] = '\0';

    /* TX buffer must fit all request headers. Authorization with a Supabase
     * user JWT (~1.4KB) plus apikey (anon key JWT, ~250B) plus Host /
     * Content-Type / Content-Length / etc. easily exceeds the default 1024.
     * 4KB gives comfortable margin for any token shape we'd send. */
    esp_http_client_config_t http_config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = per_attempt_timeout,
        .cert_pem = supabase_ca_pem_start,
        .buffer_size = 2048,
        .buffer_size_tx = 4096,
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_config);
    if (client == NULL) {
        free(auth_header);
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    esp_http_client_set_method(client, is_post ? HTTP_METHOD_POST : HTTP_METHOD_GET);
    esp_http_client_set_header(client, "apikey", s_state.config.anon_key);
    esp_http_client_set_header(client, "Authorization", auth_header);
    esp_http_client_set_header(client, "Accept", "application/json");
    if (is_post) {
        esp_http_client_set_header(client, "Content-Type", "application/json");
        if (json_body != NULL) {
            esp_http_client_set_post_field(client, json_body, strlen(json_body));
        }
    }

    int64_t start = esp_timer_get_time();
    esp_err_t err = esp_http_client_perform(client);
    response->request_time_ms = (esp_timer_get_time() - start) / 1000;

    if (err == ESP_OK) {
        response->status_code = esp_http_client_get_status_code(client);
        response->body = resp_buf.buffer;  /* transfer ownership */
        response->body_len = resp_buf.data_len;
        ESP_LOGI(TAG, "%s /functions/v1/%s -> %d (%lldms)",
                 method, function_name, response->status_code,
                 response->request_time_ms);
    } else {
        ESP_LOGE(TAG, "%s /functions/v1/%s failed: %s",
                 method, function_name, esp_err_to_name(err));
        free(resp_buf.buffer);
    }

    esp_http_client_cleanup(client);
    free(auth_header);
    return err;
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
