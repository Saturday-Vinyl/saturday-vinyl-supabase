/**
 * @file http_client.h
 * @brief Simple HTTP/HTTPS client for Saturday Vinyl Hub
 *
 * Provides basic HTTP functionality for testing connectivity and
 * making simple API requests. Uses ESP-IDF's esp_http_client.
 *
 * Phase 4: Wi-Fi Connectivity
 */

#ifndef HTTP_CLIENT_H
#define HTTP_CLIENT_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief HTTP response structure
 */
typedef struct {
    int status_code;            /**< HTTP status code (e.g., 200, 404) */
    char *body;                 /**< Response body (caller must free if not NULL) */
    size_t body_len;            /**< Length of response body */
    int64_t request_time_ms;    /**< Time taken for request in ms */
} http_response_t;

/**
 * @brief Initialize HTTP client
 *
 * Must be called before using other HTTP functions.
 * Requires Wi-Fi to be initialized.
 *
 * @return ESP_OK on success
 */
esp_err_t http_client_init(void);

/**
 * @brief Perform a simple HTTP GET request
 *
 * Fetches content from the specified URL.
 *
 * @param url Full URL to fetch (http:// or https://)
 * @param response Pointer to response structure (caller must free body if not NULL)
 * @param timeout_ms Request timeout in milliseconds (0 for default 10s)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t http_get(const char *url, http_response_t *response, uint32_t timeout_ms);

/**
 * @brief Perform HTTP POST request with JSON body
 *
 * @param url Full URL to post to
 * @param json_body JSON string to send
 * @param response Pointer to response structure
 * @param timeout_ms Request timeout in milliseconds (0 for default 10s)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t http_post_json(const char *url, const char *json_body,
                          http_response_t *response, uint32_t timeout_ms);

/**
 * @brief Free response body memory
 *
 * Call this after processing a response to free the body buffer.
 *
 * @param response Pointer to response structure
 */
void http_response_free(http_response_t *response);

/**
 * @brief Test internet connectivity
 *
 * Makes a simple HTTPS request to verify internet access.
 * Uses a reliable public endpoint (Cloudflare's 1.1.1.1 or Google).
 *
 * @return ESP_OK if internet is reachable, error code otherwise
 */
esp_err_t http_test_connectivity(void);

/**
 * @brief Deinitialize HTTP client
 *
 * @return ESP_OK on success
 */
esp_err_t http_client_deinit(void);

#ifdef __cplusplus
}
#endif

#endif /* HTTP_CLIENT_H */
