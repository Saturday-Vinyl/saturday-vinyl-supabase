/**
 * @file crate_ota.h
 * @brief Crate OTA Relay - Updates Thread devices via Hub
 *
 * Manages OTA updates for Thread-connected Crate devices. The Hub downloads
 * firmware from Supabase and relays it to Crates via the H2 co-processor
 * using CoAP over Thread.
 *
 * Flow:
 * 1. Cloud sends update_available event (device_type='crate')
 * 2. S3 pings crate via H2 to verify reachability
 * 3. S3 downloads crate firmware to RAM buffer
 * 4. S3 sends OTA_START_CRATE to H2
 * 5. S3 sends firmware chunks via OTA_DATA_CRATE
 * 6. S3 sends OTA_VERIFY_CRATE to complete
 * 7. H2 reports progress/completion via events
 *
 * Phase 4: Crate OTA Relay
 */

#ifndef CRATE_OTA_H
#define CRATE_OTA_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/** Maximum crate firmware size (256KB typical for Thread device) */
#define CRATE_OTA_MAX_FIRMWARE_SIZE     (256 * 1024)

/** Download buffer size (download in streaming chunks) */
#define CRATE_OTA_DOWNLOAD_CHUNK_SIZE   4096

/** Timeout for crate ping response (ms) */
#define CRATE_OTA_PING_TIMEOUT_MS       10000

/** Timeout for each OTA chunk ACK from H2 (ms) */
#define CRATE_OTA_CHUNK_TIMEOUT_MS      5000

/** Maximum retry attempts per chunk */
#define CRATE_OTA_MAX_CHUNK_RETRIES     3

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief Crate OTA event base
 */
ESP_EVENT_DECLARE_BASE(CRATE_OTA_EVENTS);

/**
 * @brief Crate OTA events
 */
typedef enum {
    CRATE_OTA_EVENT_START,          /**< OTA started */
    CRATE_OTA_EVENT_PROGRESS,       /**< Progress update */
    CRATE_OTA_EVENT_COMPLETE,       /**< OTA completed successfully */
    CRATE_OTA_EVENT_FAILED,         /**< OTA failed */
} crate_ota_event_type_t;

/**
 * @brief OTA progress event data
 */
typedef struct {
    uint8_t crate_ext_addr[8];      /**< Target crate */
    uint8_t percent;                /**< Progress (0-100) */
    uint32_t bytes_sent;            /**< Bytes sent to crate */
    uint32_t total_bytes;           /**< Total firmware size */
} crate_ota_progress_event_t;

/**
 * @brief OTA result event data
 */
typedef struct {
    uint8_t crate_ext_addr[8];      /**< Target crate */
    bool success;                   /**< true if successful */
    esp_err_t error;                /**< Error code if failed */
    char error_message[64];         /**< Human-readable error */
} crate_ota_result_event_t;

/*******************************************************************************
 * Status
 ******************************************************************************/

/**
 * @brief Crate OTA session state
 */
typedef enum {
    CRATE_OTA_STATE_IDLE,           /**< No OTA in progress */
    CRATE_OTA_STATE_PINGING,        /**< Checking crate reachability */
    CRATE_OTA_STATE_DOWNLOADING,    /**< Downloading firmware from cloud */
    CRATE_OTA_STATE_TRANSFERRING,   /**< Sending to crate via H2 */
    CRATE_OTA_STATE_VERIFYING,      /**< Crate verifying firmware */
    CRATE_OTA_STATE_COMPLETE,       /**< OTA complete (success) */
    CRATE_OTA_STATE_FAILED,         /**< OTA failed */
} crate_ota_state_t;

/**
 * @brief Crate OTA status
 */
typedef struct {
    crate_ota_state_t state;        /**< Current state */
    uint8_t target_crate[8];        /**< Target crate ext addr */
    char version[16];               /**< Target version string */
    uint32_t firmware_size;         /**< Total firmware size */
    uint32_t bytes_sent;            /**< Bytes sent to H2 */
    uint32_t bytes_acked;           /**< Bytes acknowledged by crate */
    uint8_t percent;                /**< Progress percentage */
    uint32_t start_time_ms;         /**< When OTA started */
    uint32_t elapsed_ms;            /**< Elapsed time */
    char request_id[40];            /**< Cloud request ID for status reporting */
} crate_ota_status_t;

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/**
 * @brief Crate OTA configuration
 */
typedef struct {
    uint32_t ping_timeout_ms;       /**< Crate ping timeout */
    uint32_t chunk_timeout_ms;      /**< Per-chunk timeout */
    uint32_t max_retries;           /**< Max retries per chunk */
    bool verify_sha256;             /**< Verify firmware hash before sending */
} crate_ota_config_t;

/**
 * @brief Default configuration
 */
#define CRATE_OTA_CONFIG_DEFAULT() { \
    .ping_timeout_ms = CRATE_OTA_PING_TIMEOUT_MS, \
    .chunk_timeout_ms = CRATE_OTA_CHUNK_TIMEOUT_MS, \
    .max_retries = CRATE_OTA_MAX_CHUNK_RETRIES, \
    .verify_sha256 = true, \
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

/**
 * @brief Initialize the Crate OTA module
 *
 * @param config Configuration (NULL for defaults)
 * @return ESP_OK on success
 */
esp_err_t crate_ota_init(const crate_ota_config_t *config);

/**
 * @brief Deinitialize the Crate OTA module
 *
 * @return ESP_OK on success
 */
esp_err_t crate_ota_deinit(void);

/**
 * @brief Start OTA update to a crate
 *
 * Downloads firmware from the specified URL and transfers it to the
 * target crate via the H2 co-processor.
 *
 * This is an asynchronous operation. Use events or crate_ota_get_status()
 * to track progress.
 *
 * @param crate_ext_addr Target crate extended MAC address (8 bytes)
 * @param firmware_url URL to download firmware from
 * @param firmware_size Expected firmware size in bytes
 * @param sha256_hex Expected SHA-256 hash (64-char hex string, or NULL)
 * @param version Version string (e.g., "1.2.3")
 * @param request_id Cloud request ID for status reporting (or NULL)
 * @return ESP_OK if OTA started, error code otherwise
 */
esp_err_t crate_ota_start(const uint8_t *crate_ext_addr,
                          const char *firmware_url,
                          uint32_t firmware_size,
                          const char *sha256_hex,
                          const char *version,
                          const char *request_id);

/**
 * @brief Abort an in-progress OTA
 *
 * @return ESP_OK if aborted, ESP_ERR_INVALID_STATE if no OTA in progress
 */
esp_err_t crate_ota_abort(void);

/**
 * @brief Get current OTA status
 *
 * @param status Output status structure
 * @return ESP_OK on success
 */
esp_err_t crate_ota_get_status(crate_ota_status_t *status);

/**
 * @brief Check if OTA is in progress
 *
 * @return true if OTA is active
 */
bool crate_ota_is_busy(void);

/**
 * @brief Ping a crate to check if reachable
 *
 * Synchronous ping with timeout. Useful before starting OTA.
 *
 * @param crate_ext_addr Target crate extended MAC address
 * @param timeout_ms Timeout in milliseconds
 * @param rssi Output RSSI if reachable (can be NULL)
 * @return ESP_OK if reachable, ESP_ERR_TIMEOUT if not
 */
esp_err_t crate_ota_ping(const uint8_t *crate_ext_addr,
                         uint32_t timeout_ms,
                         int8_t *rssi);

/**
 * @brief Handle H2 OTA events (called by h2_comm)
 *
 * Internal function called when H2 sends OTA progress/complete events.
 *
 * @param event_type Event type (S3H2_EVT_OTA_PROGRESS, etc.)
 * @param payload Event payload
 * @param payload_len Payload length
 */
void crate_ota_handle_h2_event(uint8_t event_type,
                               const uint8_t *payload,
                               uint16_t payload_len);

#ifdef __cplusplus
}
#endif

#endif /* CRATE_OTA_H */
