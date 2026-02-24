/**
 * @file s3_comm.h
 * @brief S3 Communication Interface for ESP32-H2
 *
 * Handles UART protocol communication between the ESP32-H2 (slave) and
 * ESP32-S3 (master). Implements the binary framing protocol defined in
 * s3_h2_protocol.h.
 *
 * Features:
 * - UART RX task for receiving commands from S3
 * - Command handler dispatch
 * - Response and event transmission
 * - CRC-16 checksum validation
 *
 * Phase H2-3: S3 Communication
 */

#ifndef S3_COMM_H
#define S3_COMM_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"
#include "s3_h2_protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Configuration
 ******************************************************************************/

/** UART configuration for S3 communication
 *
 * Uses UART1 to avoid conflict with USB-CDC (UART0) used for monitoring/debug.
 * GPIO 23/24 are the physical connections to S3 on the carrier board.
 */
#define S3_COMM_UART_NUM            UART_NUM_1
#define S3_COMM_UART_BAUD           115200
#define S3_COMM_UART_TX_PIN         24  /* H2 TX -> S3 RX */
#define S3_COMM_UART_RX_PIN         23  /* H2 RX <- S3 TX */

/** Receive buffer and timeout settings */
#define S3_COMM_RX_BUF_SIZE         2048
#define S3_COMM_TX_BUF_SIZE         1024
#define S3_COMM_RX_TIMEOUT_MS       100

/** Task configuration */
#define S3_COMM_TASK_STACK_SIZE     4096
#define S3_COMM_TASK_PRIORITY       5

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief S3 Communication event base
 */
ESP_EVENT_DECLARE_BASE(S3_COMM_EVENTS);

/**
 * @brief S3 Communication events (posted to default event loop)
 */
typedef enum {
    S3_COMM_EVENT_CONNECTED,        /**< S3 is communicating (PING received) */
    S3_COMM_EVENT_DISCONNECTED,     /**< S3 communication lost */
    S3_COMM_EVENT_CMD_RECEIVED,     /**< Command received from S3 */
    S3_COMM_EVENT_ERROR,            /**< Communication error */
} s3_comm_event_t;

/**
 * @brief Command received event data
 */
typedef struct {
    uint8_t cmd_type;               /**< Command type from s3h2_cmd_t */
    uint16_t payload_len;           /**< Payload length */
    uint8_t payload[256];           /**< Payload data (truncated if larger) */
} s3_comm_cmd_event_t;

/*******************************************************************************
 * Initialization
 ******************************************************************************/

/**
 * @brief Initialize S3 communication
 *
 * Sets up UART, creates RX task, and registers command handlers.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t s3_comm_init(void);

/**
 * @brief Deinitialize S3 communication
 *
 * Stops RX task and releases UART resources.
 *
 * @return ESP_OK on success
 */
esp_err_t s3_comm_deinit(void);

/**
 * @brief Check if S3 communication is initialized
 *
 * @return true if initialized
 */
bool s3_comm_is_initialized(void);

/*******************************************************************************
 * Response Functions
 ******************************************************************************/

/**
 * @brief Send PONG response
 *
 * Response to PING command.
 *
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_pong(void);

/**
 * @brief Send STATUS response
 *
 * Sends current Thread BR status to S3.
 *
 * @param status Status payload
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_status(const s3h2_status_payload_t *status);

/**
 * @brief Send CREDENTIALS response
 *
 * Sends Thread network credentials to S3.
 *
 * @param creds Credentials payload
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_credentials(const s3h2_credentials_payload_t *creds);

/**
 * @brief Send VERSION response
 *
 * Sends firmware version to S3.
 *
 * @param version Version payload
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_version(const s3h2_version_payload_t *version);

/**
 * @brief Send ACK response
 *
 * Acknowledges successful command execution.
 *
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_ack(void);

/**
 * @brief Send NAK response
 *
 * Indicates command failure.
 *
 * @param error_code Error code from s3h2_error_t
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_nak(s3h2_error_t error_code);

/*******************************************************************************
 * Event Functions (Unsolicited H2 -> S3)
 ******************************************************************************/

/**
 * @brief Send Thread state change event
 *
 * @param old_state Previous Thread state
 * @param new_state New Thread state
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_thread_state_event(s3h2_thread_state_t old_state,
                                          s3h2_thread_state_t new_state);

/**
 * @brief Send crate joined event
 *
 * @param ext_addr Extended MAC address of crate (8 bytes)
 * @param rloc16 Router Locator of crate
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_crate_joined(const uint8_t *ext_addr, uint16_t rloc16);

/**
 * @brief Send crate left event
 *
 * @param ext_addr Extended MAC address of crate (8 bytes)
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_crate_left(const uint8_t *ext_addr);

/**
 * @brief Send crate heartbeat event
 *
 * @param ext_addr Extended MAC address of crate (8 bytes)
 * @param battery_percent Battery level (0-100)
 * @param rssi Signal strength (dBm)
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_crate_heartbeat(const uint8_t *ext_addr,
                                        uint8_t battery_percent,
                                        int8_t rssi);

/**
 * @brief Send inventory update event
 *
 * @param ext_addr Extended MAC address of crate (8 bytes)
 * @param epcs Array of EPC values (12 bytes each)
 * @param epc_count Number of EPCs in array
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_inventory_update(const uint8_t *ext_addr,
                                         const uint8_t (*epcs)[12],
                                         uint8_t epc_count);

/**
 * @brief Send error event
 *
 * @param error_code Error code
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_error_event(s3h2_error_t error_code);

/*******************************************************************************
 * CoAP Mesh Protocol Event Functions
 ******************************************************************************/

/**
 * @brief Send CBOR telemetry event
 *
 * Forwards raw CBOR heartbeat/telemetry data from a mesh node to S3.
 *
 * @param ext_addr Node extended MAC address (8 bytes)
 * @param hb_type Heartbeat type (S3H2_HB_TYPE_*)
 * @param cbor_data Raw CBOR payload
 * @param cbor_len CBOR payload length
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_crate_telemetry(const uint8_t *ext_addr,
                                        uint8_t hb_type,
                                        const uint8_t *cbor_data,
                                        uint16_t cbor_len);

/**
 * @brief Send crate registered event
 *
 * Forwards device registration info from CoAP /register to S3.
 *
 * @param ext_addr Node extended MAC address (8 bytes)
 * @param mac WiFi MAC string (e.g., "AA:BB:CC:DD:EE:FF")
 * @param unit_id Supabase unit UUID string
 * @param device_type Device type slug string
 * @param fw_version Firmware version string
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_crate_registered(const uint8_t *ext_addr,
                                         const char *mac,
                                         const char *unit_id,
                                         const char *device_type,
                                         const char *fw_version);

/*******************************************************************************
 * Phase 4: OTA Event Functions
 ******************************************************************************/

/**
 * @brief Send OTA progress event
 *
 * Reports OTA transfer progress to S3.
 *
 * @param crate_ext_addr Target crate extended address (8 bytes)
 * @param percent Progress percentage (0-100)
 * @param bytes_sent Bytes successfully sent
 * @param total_bytes Total firmware size
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_ota_progress(const uint8_t *crate_ext_addr,
                                    uint8_t percent,
                                    uint32_t bytes_sent,
                                    uint32_t total_bytes);

/**
 * @brief Send OTA complete event
 *
 * Reports OTA completion (success or failure) to S3.
 *
 * @param crate_ext_addr Target crate extended address (8 bytes)
 * @param success true if OTA succeeded
 * @param error_code Error code if failed
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_ota_complete(const uint8_t *crate_ext_addr,
                                    bool success,
                                    s3h2_error_t error_code);

/**
 * @brief Send crate ping result event
 *
 * Reports whether a crate is reachable on the Thread network.
 *
 * @param crate_ext_addr Crate extended address (8 bytes)
 * @param reachable true if crate responded
 * @param rssi Signal strength if reachable (dBm)
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_ping_result(const uint8_t *crate_ext_addr,
                                   bool reachable,
                                   int8_t rssi);

/**
 * @brief Send mesh command result event
 *
 * Reports the outcome of a CoAP POST /cmd to a mesh node back to S3.
 *
 * @param ext_addr Target node extended address (8 bytes)
 * @param result S3H2_CMD_RESULT_OK, S3H2_CMD_RESULT_TIMEOUT, or S3H2_CMD_RESULT_ERROR
 * @param cmd Command name string (e.g., "register"), max 15 chars
 * @return ESP_OK on success
 */
esp_err_t s3_comm_send_mesh_cmd_result(const uint8_t *ext_addr, uint8_t result, const char *cmd);

/*******************************************************************************
 * Statistics and Debug
 ******************************************************************************/

/**
 * @brief Get communication statistics
 */
typedef struct {
    uint32_t rx_frames;             /**< Total frames received */
    uint32_t tx_frames;             /**< Total frames transmitted */
    uint32_t rx_errors;             /**< Receive errors (CRC, framing) */
    uint32_t tx_errors;             /**< Transmit errors */
    uint32_t commands_processed;    /**< Commands successfully processed */
    uint32_t last_rx_time_ms;       /**< Time of last received frame */
} s3_comm_stats_t;

/**
 * @brief Get communication statistics
 *
 * @param stats Pointer to stats structure to fill
 * @return ESP_OK on success
 */
esp_err_t s3_comm_get_stats(s3_comm_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif /* S3_COMM_H */
