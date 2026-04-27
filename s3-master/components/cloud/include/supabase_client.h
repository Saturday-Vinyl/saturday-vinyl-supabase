/**
 * @file supabase_client.h
 * @brief Supabase REST API client interface
 *
 * Provides authenticated HTTP requests to Supabase for the Saturday Vinyl Hub.
 * Handles configuration storage, authentication headers, and response parsing.
 *
 * Phase 5: Supabase Integration
 */

#ifndef SUPABASE_CLIENT_H
#define SUPABASE_CLIENT_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief Maximum length for Supabase URL
 */
#define SUPABASE_URL_MAX_LEN        128

/**
 * @brief Maximum length for Supabase anon key
 */
#define SUPABASE_ANON_KEY_MAX_LEN   256

/**
 * @brief Maximum length for device secret
 */
#define SUPABASE_DEVICE_SECRET_MAX_LEN  64

/**
 * @brief Maximum length for unit ID
 */
#define SUPABASE_UNIT_ID_MAX_LEN    32

/**
 * @brief Supabase configuration structure
 */
typedef struct {
    char url[SUPABASE_URL_MAX_LEN];                     /**< Supabase project URL */
    char anon_key[SUPABASE_ANON_KEY_MAX_LEN];           /**< Supabase anon/public key */
    char device_secret[SUPABASE_DEVICE_SECRET_MAX_LEN]; /**< Device-specific secret */
    char unit_id[SUPABASE_UNIT_ID_MAX_LEN];             /**< Unique unit identifier */
} supabase_config_t;

/**
 * @brief Supabase response structure
 */
typedef struct {
    int status_code;            /**< HTTP status code */
    char *body;                 /**< Response body (caller must free if not NULL) */
    size_t body_len;            /**< Length of response body */
    int64_t request_time_ms;    /**< Time taken for request in ms */
} supabase_response_t;

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the Supabase client
 *
 * Loads configuration from NVS if available.
 * Must be called before making any API requests.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t supabase_init(void);

/**
 * @brief Deinitialize the Supabase client
 *
 * Cleans up resources including persistent connection.
 *
 * @return ESP_OK on success
 */
esp_err_t supabase_deinit(void);

/**
 * @brief Close the persistent HTTP connection
 *
 * Tears down the reusable TLS session. Call when WiFi disconnects
 * or when the connection is known to be stale. The next supabase_post()
 * will transparently create a new connection.
 */
void supabase_close_connection(void);

/**
 * @brief Check if Supabase client is configured
 *
 * @return true if URL and anon key are configured
 */
bool supabase_is_configured(void);

/**
 * @brief Get current Supabase configuration
 *
 * @param config Output configuration structure
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not configured
 */
esp_err_t supabase_get_config(supabase_config_t *config);

/**
 * @brief Set Supabase configuration
 *
 * Stores configuration in NVS for persistence across reboots.
 *
 * @param config Configuration to set
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t supabase_set_config(const supabase_config_t *config);

/**
 * @brief Clear Supabase configuration
 *
 * Removes configuration from NVS.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t supabase_clear_config(void);

/**
 * @brief POST JSON data to a Supabase table
 *
 * Performs an authenticated POST request to the Supabase REST API.
 * Automatically adds required headers (apikey, Authorization, Content-Type).
 *
 * @param table Table name (e.g., "now_playing_events")
 * @param json_body JSON string to send
 * @param response Output response (caller must call supabase_response_free)
 * @param timeout_ms Request timeout in ms (0 for default 10s)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t supabase_post(const char *table, const char *json_body,
                        supabase_response_t *response, uint32_t timeout_ms);

/**
 * @brief GET from a Supabase REST endpoint
 *
 * Performs an authenticated GET request. Path is appended to {base_url}/rest/v1/
 * and may include a PostgREST query string (e.g. "firmware_files?firmware_id=eq.X").
 * Adds apikey + Authorization headers.
 *
 * @param path PostgREST path with optional query (e.g. "firmware_files?id=eq.X")
 * @param response Output response (caller must call supabase_response_free)
 * @param timeout_ms Request timeout in ms (0 for default 10s)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t supabase_get(const char *path, supabase_response_t *response,
                       uint32_t timeout_ms);

/**
 * @brief Free response body memory
 *
 * @param response Response to free
 */
void supabase_response_free(supabase_response_t *response);

/**
 * @brief Get the unit ID
 *
 * @param unit_id Output buffer
 * @param max_len Buffer size
 * @return ESP_OK on success, ESP_ERR_NOT_FOUND if not configured
 */
esp_err_t supabase_get_unit_id(char *unit_id, size_t max_len);

/**
 * @brief Test Supabase connectivity
 *
 * Makes a simple request to verify Supabase is reachable.
 *
 * @return ESP_OK if reachable, error code otherwise
 */
esp_err_t supabase_test_connection(void);

#ifdef __cplusplus
}
#endif

#endif /* SUPABASE_CLIENT_H */
