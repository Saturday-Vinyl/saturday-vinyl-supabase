/**
 * @file http_client.c
 * @brief Simple HTTP/HTTPS client implementation
 *
 * Uses ESP-IDF's esp_http_client for HTTP operations.
 * Supports both HTTP and HTTPS with certificate bundle.
 *
 * Phase 4: Wi-Fi Connectivity
 */

#include "http_client.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "esp_timer.h"
#include "esp_tls.h"
#include "esp_crt_bundle.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "HTTP";

/* Default timeout */
#define DEFAULT_TIMEOUT_MS      10000

/* Maximum response body size to buffer */
#define MAX_RESPONSE_SIZE       4096

/* Connectivity test URL (Cloudflare's DNS-over-HTTPS endpoint returns JSON) */
#define CONNECTIVITY_TEST_URL   "https://1.1.1.1/cdn-cgi/trace"

/* Module state */
static bool s_initialized = false;

/* Response buffer for event handler */
typedef struct {
    char *buffer;
    size_t buffer_size;
    size_t data_len;
} response_buffer_t;

/*******************************************************************************
 * HTTP Event Handler
 ******************************************************************************/

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

        case HTTP_EVENT_HEADER_SENT:
            ESP_LOGD(TAG, "HTTP_EVENT_HEADER_SENT");
            break;

        case HTTP_EVENT_ON_HEADER:
            ESP_LOGD(TAG, "Header: %s: %s", evt->header_key, evt->header_value);
            break;

        case HTTP_EVENT_ON_HEADERS_COMPLETE:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_HEADERS_COMPLETE");
            break;

        case HTTP_EVENT_ON_STATUS_CODE:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_STATUS_CODE");
            break;

        case HTTP_EVENT_ON_DATA:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_DATA, len=%d", evt->data_len);
            if (resp_buf != NULL && resp_buf->buffer != NULL) {
                /* Append data to buffer if there's room */
                size_t space_left = resp_buf->buffer_size - resp_buf->data_len - 1;
                size_t copy_len = (evt->data_len < space_left) ? evt->data_len : space_left;
                if (copy_len > 0) {
                    memcpy(resp_buf->buffer + resp_buf->data_len, evt->data, copy_len);
                    resp_buf->data_len += copy_len;
                    resp_buf->buffer[resp_buf->data_len] = '\0';
                }
            }
            break;

        case HTTP_EVENT_ON_FINISH:
            ESP_LOGD(TAG, "HTTP_EVENT_ON_FINISH");
            break;

        case HTTP_EVENT_DISCONNECTED:
            ESP_LOGD(TAG, "HTTP_EVENT_DISCONNECTED");
            break;

        case HTTP_EVENT_REDIRECT:
            ESP_LOGD(TAG, "HTTP_EVENT_REDIRECT");
            break;
    }
    return ESP_OK;
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t http_client_init(void)
{
    if (s_initialized) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "HTTP client initialized");
    s_initialized = true;
    return ESP_OK;
}

esp_err_t http_client_deinit(void)
{
    s_initialized = false;
    ESP_LOGI(TAG, "HTTP client deinitialized");
    return ESP_OK;
}

esp_err_t http_get(const char *url, http_response_t *response, uint32_t timeout_ms)
{
    if (url == NULL || response == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Initialize response */
    memset(response, 0, sizeof(http_response_t));

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

    /* Configure HTTP client */
    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = (timeout_ms > 0) ? timeout_ms : DEFAULT_TIMEOUT_MS,
        .crt_bundle_attach = esp_crt_bundle_attach,  /* Use certificate bundle for HTTPS */
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (client == NULL) {
        ESP_LOGE(TAG, "Failed to init HTTP client");
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    /* Record start time */
    int64_t start_time = esp_timer_get_time();

    /* Perform request */
    esp_err_t err = esp_http_client_perform(client);

    /* Record end time */
    response->request_time_ms = (esp_timer_get_time() - start_time) / 1000;

    if (err == ESP_OK) {
        response->status_code = esp_http_client_get_status_code(client);
        response->body_len = resp_buf.data_len;
        response->body = resp_buf.buffer;  /* Transfer ownership */

        ESP_LOGI(TAG, "GET %s -> %d (%zu bytes, %lld ms)",
                 url, response->status_code, response->body_len,
                 (long long)response->request_time_ms);
    } else {
        ESP_LOGE(TAG, "GET %s failed: %s", url, esp_err_to_name(err));
        free(resp_buf.buffer);
    }

    esp_http_client_cleanup(client);
    return err;
}

esp_err_t http_post_json(const char *url, const char *json_body,
                          http_response_t *response, uint32_t timeout_ms)
{
    if (url == NULL || json_body == NULL || response == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Initialize response */
    memset(response, 0, sizeof(http_response_t));

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

    /* Configure HTTP client */
    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = &resp_buf,
        .timeout_ms = (timeout_ms > 0) ? timeout_ms : DEFAULT_TIMEOUT_MS,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .method = HTTP_METHOD_POST,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (client == NULL) {
        ESP_LOGE(TAG, "Failed to init HTTP client");
        free(resp_buf.buffer);
        return ESP_FAIL;
    }

    /* Set headers and body */
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_post_field(client, json_body, strlen(json_body));

    /* Record start time */
    int64_t start_time = esp_timer_get_time();

    /* Perform request */
    esp_err_t err = esp_http_client_perform(client);

    /* Record end time */
    response->request_time_ms = (esp_timer_get_time() - start_time) / 1000;

    if (err == ESP_OK) {
        response->status_code = esp_http_client_get_status_code(client);
        response->body_len = resp_buf.data_len;
        response->body = resp_buf.buffer;

        ESP_LOGI(TAG, "POST %s -> %d (%zu bytes, %lld ms)",
                 url, response->status_code, response->body_len,
                 (long long)response->request_time_ms);
    } else {
        ESP_LOGE(TAG, "POST %s failed: %s", url, esp_err_to_name(err));
        free(resp_buf.buffer);
    }

    esp_http_client_cleanup(client);
    return err;
}

void http_response_free(http_response_t *response)
{
    if (response != NULL && response->body != NULL) {
        free(response->body);
        response->body = NULL;
        response->body_len = 0;
    }
}

esp_err_t http_test_connectivity(void)
{
    ESP_LOGI(TAG, "Testing internet connectivity...");

    http_response_t response;
    esp_err_t err = http_get(CONNECTIVITY_TEST_URL, &response, 5000);

    if (err == ESP_OK) {
        if (response.status_code == 200) {
            ESP_LOGI(TAG, "Internet connectivity OK (response in %lld ms)",
                     (long long)response.request_time_ms);
            /* Log first 100 chars of response for debugging */
            if (response.body != NULL && response.body_len > 0) {
                size_t log_len = (response.body_len < 100) ? response.body_len : 100;
                ESP_LOGD(TAG, "Response: %.*s%s", (int)log_len, response.body,
                         (response.body_len > 100) ? "..." : "");
            }
            http_response_free(&response);
            return ESP_OK;
        } else {
            ESP_LOGW(TAG, "Unexpected status code: %d", response.status_code);
            http_response_free(&response);
            return ESP_FAIL;
        }
    }

    ESP_LOGE(TAG, "Internet connectivity test failed");
    return err;
}
