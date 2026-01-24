/**
 * @file coap_ota.h
 * @brief CoAP OTA Client for Thread Device Firmware Updates
 *
 * Implements CoAP-based OTA updates to Thread devices (Crates) using
 * OpenThread's built-in CoAP implementation with block transfer.
 *
 * OTA Flow:
 * 1. S3 sends OTA_START_CRATE command with firmware metadata
 * 2. H2 initiates CoAP session to crate's /ota/start endpoint
 * 3. S3 sends OTA_DATA_CRATE chunks
 * 4. H2 relays chunks via CoAP POST to /ota/data with Block1 option
 * 5. S3 sends OTA_VERIFY_CRATE
 * 6. H2 sends CoAP POST to /ota/verify
 * 7. Crate verifies and applies update, responds with success/failure
 *
 * Phase 4: Crate OTA Relay - H2 CoAP Client
 */

#ifndef COAP_OTA_H
#define COAP_OTA_H

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

/** CoAP block size for OTA transfer (must be power of 2, max 1024) */
#define COAP_OTA_BLOCK_SIZE         512

/** Timeout for CoAP responses (ms) */
#define COAP_OTA_RESPONSE_TIMEOUT   10000

/** Maximum retries per block */
#define COAP_OTA_MAX_RETRIES        3

/** Maximum concurrent OTA sessions (typically 1) */
#define COAP_OTA_MAX_SESSIONS       1

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief CoAP OTA event base
 */
ESP_EVENT_DECLARE_BASE(COAP_OTA_EVENTS);

/**
 * @brief CoAP OTA events
 */
typedef enum {
    COAP_OTA_EVENT_SESSION_START,   /**< OTA session started */
    COAP_OTA_EVENT_PROGRESS,        /**< Transfer progress */
    COAP_OTA_EVENT_COMPLETE,        /**< OTA completed */
    COAP_OTA_EVENT_FAILED,          /**< OTA failed */
} coap_ota_event_type_t;

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief OTA session state
 */
typedef enum {
    COAP_OTA_STATE_IDLE,            /**< No active session */
    COAP_OTA_STATE_STARTING,        /**< Sending start request */
    COAP_OTA_STATE_TRANSFERRING,    /**< Sending data blocks */
    COAP_OTA_STATE_VERIFYING,       /**< Waiting for verify response */
    COAP_OTA_STATE_COMPLETE,        /**< Transfer complete */
    COAP_OTA_STATE_FAILED,          /**< Transfer failed */
} coap_ota_state_t;

/**
 * @brief OTA session status
 */
typedef struct {
    coap_ota_state_t state;         /**< Current state */
    uint8_t target_addr[8];         /**< Target device extended address */
    uint32_t firmware_size;         /**< Total firmware size */
    uint32_t bytes_sent;            /**< Bytes successfully sent */
    uint32_t bytes_acked;           /**< Bytes acknowledged by target */
    uint8_t percent;                /**< Progress percentage */
    uint8_t retries;                /**< Current retry count */
    uint32_t start_time_ms;         /**< Session start timestamp */
    uint8_t last_error;             /**< Last error code */
} coap_ota_status_t;

/*******************************************************************************
 * Initialization
 ******************************************************************************/

/**
 * @brief Initialize CoAP OTA client
 *
 * Must be called after OpenThread is initialized.
 *
 * @return ESP_OK on success
 */
esp_err_t coap_ota_init(void);

/**
 * @brief Deinitialize CoAP OTA client
 *
 * @return ESP_OK on success
 */
esp_err_t coap_ota_deinit(void);

/**
 * @brief Check if CoAP OTA is initialized
 *
 * @return true if initialized
 */
bool coap_ota_is_initialized(void);

/*******************************************************************************
 * Session Management
 ******************************************************************************/

/**
 * @brief Start OTA session to a crate
 *
 * Initiates an OTA session by sending a start request to the target
 * device's /ota/start endpoint.
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @param firmware_size Total firmware size in bytes
 * @param sha256 Expected SHA-256 hash (32 bytes)
 * @param version_major Major version number
 * @param version_minor Minor version number
 * @param version_patch Patch version number
 * @return ESP_OK if session started, error code otherwise
 */
esp_err_t coap_ota_start_session(const uint8_t *target_ext_addr,
                                  uint32_t firmware_size,
                                  const uint8_t *sha256,
                                  uint8_t version_major,
                                  uint8_t version_minor,
                                  uint8_t version_patch);

/**
 * @brief Send a data chunk to the target
 *
 * Sends a firmware chunk via CoAP Block1 transfer.
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @param offset Byte offset in firmware image
 * @param data Chunk data
 * @param length Chunk length
 * @return ESP_OK if chunk queued, error code otherwise
 */
esp_err_t coap_ota_send_chunk(const uint8_t *target_ext_addr,
                               uint32_t offset,
                               const uint8_t *data,
                               uint16_t length);

/**
 * @brief Request firmware verification and apply
 *
 * Sends verify request to target's /ota/verify endpoint.
 * Target will verify the firmware hash and apply the update.
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @return ESP_OK if request sent, error code otherwise
 */
esp_err_t coap_ota_verify(const uint8_t *target_ext_addr);

/**
 * @brief Abort an OTA session
 *
 * Sends abort request and cleans up session state.
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @return ESP_OK if aborted
 */
esp_err_t coap_ota_abort(const uint8_t *target_ext_addr);

/**
 * @brief Get current session status
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @param status Output status structure
 * @return ESP_OK if session found, ESP_ERR_NOT_FOUND otherwise
 */
esp_err_t coap_ota_get_status(const uint8_t *target_ext_addr,
                               coap_ota_status_t *status);

/**
 * @brief Check if an OTA session is active
 *
 * @return true if any session is in progress
 */
bool coap_ota_is_busy(void);

/*******************************************************************************
 * Utility Functions
 ******************************************************************************/

/**
 * @brief Ping a device to check reachability
 *
 * Sends a CoAP GET to /ping endpoint.
 *
 * @param target_ext_addr Target device extended MAC address (8 bytes)
 * @param timeout_ms Timeout in milliseconds
 * @param rssi Output RSSI if reachable (can be NULL)
 * @return ESP_OK if device responded, ESP_ERR_TIMEOUT if not
 */
esp_err_t coap_ota_ping_device(const uint8_t *target_ext_addr,
                                uint32_t timeout_ms,
                                int8_t *rssi);

/**
 * @brief Convert extended address to IPv6 mesh-local address
 *
 * Builds a mesh-local IPv6 address from extended MAC address.
 *
 * @param ext_addr Extended MAC address (8 bytes)
 * @param ip6_addr Output IPv6 address string (must be >= 40 bytes)
 * @return ESP_OK on success
 */
esp_err_t coap_ota_ext_addr_to_ip6(const uint8_t *ext_addr, char *ip6_addr);

#ifdef __cplusplus
}
#endif

#endif /* COAP_OTA_H */
