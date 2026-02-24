/**
 * @file h2_comm.h
 * @brief H2 Communication Interface for ESP32-S3 Master
 *
 * Handles UART protocol communication between the ESP32-S3 (master) and
 * ESP32-H2 (slave) Thread co-processor. Implements the binary framing
 * protocol defined in s3_h2_protocol.h.
 *
 * Features:
 * - UART communication with H2 via UART2
 * - GPIO control for H2 reset and boot mode
 * - Command/response with configurable timeout
 * - Async event reception from H2
 * - Health monitoring via periodic PING
 * - Automatic H2 reset on communication failure
 *
 * Phase S3-7 and INT-1: S3↔H2 Integration
 */

#ifndef H2_COMM_H
#define H2_COMM_H

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

/** UART configuration for H2 communication */
#define H2_COMM_UART_NUM            UART_NUM_2
#define H2_COMM_UART_BAUD           115200
#define H2_COMM_UART_TX_PIN         15  /* S3 TX -> H2 RX */
#define H2_COMM_UART_RX_PIN         16  /* S3 RX <- H2 TX */

/** GPIO for H2 control */
#define H2_COMM_EN_PIN              6   /* H2 enable/reset (active high) */
#define H2_COMM_BOOT_PIN            7   /* H2 boot mode (high=normal, low=download) */

/** Buffer and timeout settings */
#define H2_COMM_RX_BUF_SIZE         2048
#define H2_COMM_TX_BUF_SIZE         1024
#define H2_COMM_RX_TIMEOUT_MS       100
#define H2_COMM_CMD_TIMEOUT_MS      1000    /* Command response timeout */
#define H2_COMM_BOOT_DELAY_MS       500     /* Delay after H2 reset */

/** Health monitoring */
#define H2_COMM_PING_INTERVAL_MS    5000    /* Health check every 5 seconds */
#define H2_COMM_MAX_PING_FAILURES   3       /* Reset H2 after 3 failures */

/** Task configuration */
#define H2_COMM_TASK_STACK_SIZE     5120
#define H2_COMM_TASK_PRIORITY       5

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief H2 Communication event base
 */
ESP_EVENT_DECLARE_BASE(H2_COMM_EVENTS);

/**
 * @brief H2 Communication events (posted to default event loop)
 */
typedef enum {
    H2_COMM_EVENT_CONNECTED,            /**< H2 is responding to PING */
    H2_COMM_EVENT_DISCONNECTED,         /**< H2 stopped responding */
    H2_COMM_EVENT_THREAD_STATE_CHANGED, /**< Thread BR state changed */
    H2_COMM_EVENT_CRATE_JOINED,         /**< Crate joined Thread network */
    H2_COMM_EVENT_CRATE_LEFT,           /**< Crate left Thread network */
    H2_COMM_EVENT_INVENTORY_UPDATE,     /**< Crate inventory changed */
    H2_COMM_EVENT_CRATE_HEARTBEAT,      /**< Crate heartbeat received */
    H2_COMM_EVENT_CRATE_TELEMETRY,      /**< CBOR telemetry from mesh node */
    H2_COMM_EVENT_CRATE_REGISTERED,     /**< Mesh node registered via CoAP */
    H2_COMM_EVENT_MESH_CMD_RESULT,      /**< Mesh command result from H2 */
    H2_COMM_EVENT_H2_RESET,             /**< H2 was reset due to failure */
    H2_COMM_EVENT_ERROR,                /**< Communication error */
} h2_comm_event_t;

/**
 * @brief Thread state change event data
 */
typedef struct {
    s3h2_thread_state_t old_state;      /**< Previous state */
    s3h2_thread_state_t new_state;      /**< New state */
} h2_comm_thread_state_event_t;

/**
 * @brief Crate joined event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Crate extended MAC address */
    uint16_t rloc16;                    /**< Router Locator */
} h2_comm_crate_joined_event_t;

/**
 * @brief Crate left event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Crate extended MAC address */
} h2_comm_crate_left_event_t;

/**
 * @brief Crate heartbeat event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Crate extended MAC address */
    uint8_t battery_percent;            /**< Battery level (0-100) */
    int8_t rssi;                        /**< Signal strength (dBm) */
} h2_comm_crate_heartbeat_event_t;

/**
 * @brief Inventory update event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Crate extended MAC address */
    uint8_t epc_count;                  /**< Number of EPCs */
    uint8_t epcs[75][12];               /**< EPC values (max 75 per crate) */
} h2_comm_inventory_event_t;

/**
 * @brief CBOR telemetry event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Node extended MAC address */
    uint8_t hb_type;                    /**< Heartbeat type (S3H2_HB_TYPE_*) */
    uint16_t cbor_len;                  /**< CBOR payload length */
    uint8_t cbor_data[512];             /**< CBOR payload (max reasonable size) */
} h2_comm_crate_telemetry_event_t;

/**
 * @brief Device registration event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Node extended MAC address */
    char mac[18];                       /**< WiFi MAC "AA:BB:CC:DD:EE:FF" */
    char unit_id[24];                   /**< Supabase unit UUID */
    char device_type[20];               /**< Device type slug */
    char fw_version[16];                /**< Firmware version */
} h2_comm_crate_registered_event_t;

/**
 * @brief Mesh command result event data
 */
typedef struct {
    uint8_t ext_addr[8];                /**< Target node extended address */
    uint8_t result;                     /**< S3H2_CMD_RESULT_OK/TIMEOUT/ERROR */
    char cmd[16];                       /**< Command name (e.g. "register") */
} h2_comm_mesh_cmd_result_event_t;

/*******************************************************************************
 * Initialization
 ******************************************************************************/

/**
 * @brief Initialize H2 communication
 *
 * Sets up UART2 for H2 communication, configures GPIO for H2 control,
 * and creates background tasks for RX and health monitoring.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t h2_comm_init(void);

/**
 * @brief Deinitialize H2 communication
 *
 * Stops tasks, releases UART and GPIO resources.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_deinit(void);

/**
 * @brief Check if H2 communication is initialized
 *
 * @return true if initialized
 */
bool h2_comm_is_initialized(void);

/**
 * @brief Check if H2 is connected (responding to PINGs)
 *
 * @return true if H2 is responding
 */
bool h2_comm_is_connected(void);

/*******************************************************************************
 * H2 Control Functions
 ******************************************************************************/

/**
 * @brief Reset the H2 co-processor
 *
 * Toggles the H2_EN pin to perform a hardware reset.
 * Waits for H2 to boot before returning.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_reset(void);

/**
 * @brief Put H2 into bootloader mode for firmware update
 *
 * Sets BOOT pin low, then resets H2 to enter download mode.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_enter_bootloader(void);

/**
 * @brief Exit bootloader and boot H2 normally
 *
 * Sets BOOT pin high, then resets H2 to boot normally.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_exit_bootloader(void);

/*******************************************************************************
 * Command Functions (S3 -> H2)
 ******************************************************************************/

/**
 * @brief Send PING and wait for PONG
 *
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if PONG received, ESP_ERR_TIMEOUT if no response
 */
esp_err_t h2_comm_ping(uint32_t timeout_ms);

/**
 * @brief Get H2/Thread BR status
 *
 * @param status Pointer to receive status
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK on success
 */
esp_err_t h2_comm_get_status(s3h2_status_payload_t *status, uint32_t timeout_ms);

/**
 * @brief Get Thread network credentials
 *
 * @param creds Pointer to receive credentials
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK on success
 */
esp_err_t h2_comm_get_credentials(s3h2_credentials_payload_t *creds, uint32_t timeout_ms);

/**
 * @brief Get H2 firmware version
 *
 * @param version Pointer to receive version
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK on success
 */
esp_err_t h2_comm_get_version(s3h2_version_payload_t *version, uint32_t timeout_ms);

/**
 * @brief Start Thread network
 *
 * Instructs H2 to initialize and start the Thread Border Router.
 *
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received
 */
esp_err_t h2_comm_start_thread(uint32_t timeout_ms);

/**
 * @brief Stop Thread network
 *
 * Instructs H2 to stop the Thread Border Router.
 *
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received
 */
esp_err_t h2_comm_stop_thread(uint32_t timeout_ms);

/**
 * @brief Enable device joining
 *
 * Enables commissioner mode to allow new devices to join.
 *
 * @param duration_sec Duration in seconds (0 = indefinite)
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received
 */
esp_err_t h2_comm_enable_joining(uint32_t duration_sec, uint32_t timeout_ms);

/**
 * @brief Disable device joining
 *
 * Disables commissioner mode.
 *
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received
 */
esp_err_t h2_comm_disable_joining(uint32_t timeout_ms);

/**
 * @brief Reset Thread network credentials
 *
 * Generates new Thread network credentials. Requires restarting Thread.
 *
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received
 */
esp_err_t h2_comm_reset_credentials(uint32_t timeout_ms);

/**
 * @brief Relay a CBOR command to a mesh node via H2
 *
 * Sends CMD_RELAY_CMD to H2, which forwards via CoAP POST /cmd.
 *
 * @param target_ext_addr Target node extended MAC address (8 bytes)
 * @param cbor_data CBOR-encoded command payload
 * @param cbor_len CBOR payload length
 * @param timeout_ms Response timeout in milliseconds (0 = default)
 * @return ESP_OK if ACK received from H2
 */
esp_err_t h2_comm_relay_command(const uint8_t *target_ext_addr,
                                 const uint8_t *cbor_data,
                                 uint16_t cbor_len,
                                 uint32_t timeout_ms);

/*******************************************************************************
 * Health Monitoring
 ******************************************************************************/

/**
 * @brief Start health monitoring task
 *
 * Starts periodic PING to H2 and auto-reset on failure.
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_start_health_monitor(void);

/**
 * @brief Stop health monitoring task
 *
 * @return ESP_OK on success
 */
esp_err_t h2_comm_stop_health_monitor(void);

/**
 * @brief Check if health monitoring is running
 *
 * @return true if running
 */
bool h2_comm_is_health_monitor_running(void);

/*******************************************************************************
 * Statistics and Debug
 ******************************************************************************/

/**
 * @brief Communication statistics
 */
typedef struct {
    uint32_t tx_frames;                 /**< Frames sent to H2 */
    uint32_t rx_frames;                 /**< Frames received from H2 */
    uint32_t tx_errors;                 /**< Transmit errors */
    uint32_t rx_errors;                 /**< Receive errors (CRC, framing) */
    uint32_t timeouts;                  /**< Command response timeouts */
    uint32_t h2_resets;                 /**< Number of H2 resets */
    uint32_t ping_failures;             /**< Consecutive PING failures */
    uint32_t events_received;           /**< Async events from H2 */
    uint32_t last_rx_time_ms;           /**< Time of last received frame */
    uint32_t last_ping_time_ms;         /**< Time of last successful PING */
    bool h2_connected;                  /**< Current connection state */
    s3h2_thread_state_t thread_state;   /**< Last known Thread state */
} h2_comm_stats_t;

/**
 * @brief Get communication statistics
 *
 * @param stats Pointer to stats structure to fill
 * @return ESP_OK on success
 */
esp_err_t h2_comm_get_stats(h2_comm_stats_t *stats);

/**
 * @brief Get string representation of Thread state
 *
 * @param state Thread state
 * @return State name string
 */
const char *h2_comm_thread_state_str(s3h2_thread_state_t state);

#ifdef __cplusplus
}
#endif

#endif /* H2_COMM_H */
