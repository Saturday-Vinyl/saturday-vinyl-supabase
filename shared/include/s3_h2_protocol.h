/**
 * @file s3_h2_protocol.h
 * @brief UART Protocol Definitions for S3-H2 Inter-processor Communication
 *
 * This header defines the binary protocol used for communication between
 * the ESP32-S3 master and ESP32-H2 Thread co-processor over UART.
 *
 * Frame Format:
 * ┌────────┬──────┬────────┬────────────┬──────────┬─────┐
 * │ Header │ Type │ Length │  Payload   │ Checksum │ End │
 * │  0xAA  │  1B  │   2B   │  Variable  │    2B    │0x55 │
 * └────────┴──────┴────────┴────────────┴──────────┴─────┘
 *
 * - Header: Always 0xAA
 * - Type: Message type (command, response, or event)
 * - Length: Payload length (little-endian, max 1024)
 * - Payload: Type-specific data
 * - Checksum: CRC-16/CCITT of Type + Length + Payload
 * - End: Always 0x55
 */

#ifndef S3_H2_PROTOCOL_H
#define S3_H2_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Frame Constants
 ******************************************************************************/

#define S3H2_FRAME_HEADER           0xAA
#define S3H2_FRAME_END              0x55
#define S3H2_MAX_PAYLOAD_LEN        1024
#define S3H2_FRAME_OVERHEAD         6       /* Header(1) + Type(1) + Len(2) + CRC(2) + End(1) - 1 */

/*******************************************************************************
 * Message Types - Commands (S3 -> H2)
 ******************************************************************************/

typedef enum {
    /* Basic Commands */
    S3H2_CMD_PING               = 0x01,     /**< Ping request */
    S3H2_CMD_GET_STATUS         = 0x02,     /**< Request Thread BR status */
    S3H2_CMD_GET_CREDENTIALS    = 0x03,     /**< Request Thread network credentials */
    S3H2_CMD_GET_DEVICES        = 0x04,     /**< Request list of Thread devices */

    /* Thread Control Commands */
    S3H2_CMD_START_THREAD       = 0x05,     /**< Start Thread network */
    S3H2_CMD_STOP_THREAD        = 0x06,     /**< Stop Thread network */
    S3H2_CMD_ENABLE_JOINING     = 0x07,     /**< Enable device joining */
    S3H2_CMD_DISABLE_JOINING    = 0x08,     /**< Disable device joining */
    S3H2_CMD_RESET_CREDENTIALS  = 0x09,     /**< Generate new network credentials (legacy, unused in cloud-canonical model) */
    S3H2_CMD_SET_CREDENTIALS    = 0x0A,     /**< Set Thread credentials from S3 (payload: s3h2_credentials_payload_t). Persists to NVS and (re)starts Thread stack. */
    S3H2_CMD_CLEAR_CREDENTIALS  = 0x0B,     /**< Clear Thread credentials and stop Thread stack. Empty payload. */

    /* System Commands */
    S3H2_CMD_ENTER_BOOTLOADER   = 0x10,     /**< Enter bootloader for firmware update */
    S3H2_CMD_RESET              = 0x11,     /**< Software reset */
    S3H2_CMD_GET_VERSION        = 0x12,     /**< Request firmware version */

    /* Crate OTA Commands (Phase 4) */
    S3H2_CMD_OTA_START_CRATE    = 0x20,     /**< Start OTA to a Thread crate */
    S3H2_CMD_OTA_DATA_CRATE     = 0x21,     /**< Send OTA data chunk to crate */
    S3H2_CMD_OTA_VERIFY_CRATE   = 0x22,     /**< Verify and apply crate OTA */
    S3H2_CMD_OTA_ABORT_CRATE    = 0x23,     /**< Abort crate OTA in progress */
    S3H2_CMD_PING_CRATE         = 0x24,     /**< Ping crate to check if reachable */

    /* CoAP Mesh Protocol Commands */
    S3H2_CMD_RELAY_CMD          = 0x25,     /**< Relay command to mesh node via CoAP */
} s3h2_cmd_t;

/*******************************************************************************
 * Message Types - Responses (H2 -> S3)
 ******************************************************************************/

typedef enum {
    S3H2_RSP_PONG               = 0x81,     /**< Pong response to PING */
    S3H2_RSP_STATUS             = 0x82,     /**< Thread BR status */
    S3H2_RSP_CREDENTIALS        = 0x83,     /**< Thread network credentials */
    S3H2_RSP_ACK                = 0x84,     /**< Command acknowledged/success */
    S3H2_RSP_NAK                = 0x85,     /**< Command failed */
    S3H2_RSP_DEVICES            = 0x86,     /**< Device list */
    S3H2_RSP_VERSION            = 0x87,     /**< Firmware version */
} s3h2_rsp_t;

/*******************************************************************************
 * Message Types - Events (H2 -> S3, unsolicited)
 ******************************************************************************/

typedef enum {
    S3H2_EVT_CRATE_JOINED       = 0xE0,     /**< Crate joined Thread network */
    S3H2_EVT_CRATE_LEFT         = 0xE1,     /**< Crate left Thread network */
    S3H2_EVT_INVENTORY_UPDATE   = 0xE2,     /**< Crate inventory changed */
    S3H2_EVT_CRATE_HEARTBEAT    = 0xE3,     /**< Crate heartbeat received */
    S3H2_EVT_THREAD_STATE       = 0xE4,     /**< Thread state changed */
    S3H2_EVT_OTA_PROGRESS       = 0xE5,     /**< Crate OTA progress update */
    S3H2_EVT_OTA_COMPLETE       = 0xE6,     /**< Crate OTA completed (success/fail) */
    S3H2_EVT_CRATE_PING_RESULT  = 0xE7,     /**< Crate ping result */

    /* CoAP Mesh Protocol Events */
    S3H2_EVT_CRATE_TELEMETRY   = 0xE8,     /**< CBOR telemetry from mesh node */
    S3H2_EVT_CRATE_REGISTERED  = 0xE9,     /**< Mesh node registered via CoAP */
    S3H2_EVT_MESH_CMD_RESULT   = 0xEA,     /**< Mesh command result (H2-initiated) */

    S3H2_EVT_ERROR              = 0xEF,     /**< Error occurred */
} s3h2_evt_t;

/*******************************************************************************
 * NAK Error Codes
 ******************************************************************************/

typedef enum {
    S3H2_ERR_NONE               = 0x00,     /**< No error */
    S3H2_ERR_INVALID_CMD        = 0x01,     /**< Unknown command */
    S3H2_ERR_INVALID_PARAM      = 0x02,     /**< Invalid parameter */
    S3H2_ERR_NOT_READY          = 0x03,     /**< Thread BR not ready */
    S3H2_ERR_BUSY               = 0x04,     /**< Operation in progress */
    S3H2_ERR_TIMEOUT            = 0x05,     /**< Operation timed out */
    S3H2_ERR_NO_CREDENTIALS     = 0x06,     /**< No Thread credentials */
    S3H2_ERR_NOT_ATTACHED       = 0x07,     /**< Not attached to Thread network */
    /* OTA-specific errors (Phase 4) */
    S3H2_ERR_CRATE_UNREACHABLE  = 0x10,     /**< Crate not responding to CoAP */
    S3H2_ERR_OTA_IN_PROGRESS    = 0x11,     /**< OTA already in progress */
    S3H2_ERR_OTA_CHECKSUM       = 0x12,     /**< OTA checksum verification failed */
    S3H2_ERR_OTA_FLASH          = 0x13,     /**< OTA flash write failed */
    S3H2_ERR_OTA_NO_SESSION     = 0x14,     /**< No active OTA session */
    S3H2_ERR_OTA_SEQUENCE       = 0x15,     /**< Invalid OTA chunk sequence */
    S3H2_ERR_CRATE_REJECTED     = 0x16,     /**< Crate responded with CoAP error (4.xx/5.xx) */
    S3H2_ERR_INTERNAL           = 0xFF,     /**< Internal error */
} s3h2_error_t;

/*******************************************************************************
 * Thread BR State (for STATUS response and THREAD_STATE event)
 ******************************************************************************/

typedef enum {
    S3H2_THREAD_STATE_DISABLED      = 0x00, /**< Thread BR disabled */
    S3H2_THREAD_STATE_DETACHED      = 0x01, /**< Initialized but not attached */
    S3H2_THREAD_STATE_ATTACHING     = 0x02, /**< Attempting to attach */
    S3H2_THREAD_STATE_CHILD         = 0x03, /**< Attached as child */
    S3H2_THREAD_STATE_ROUTER        = 0x04, /**< Operating as router */
    S3H2_THREAD_STATE_LEADER        = 0x05, /**< Operating as network leader */
    S3H2_THREAD_STATE_UNPROVISIONED = 0x06, /**< H2 has no credentials and is idling; waiting for S3 to push via SET_CREDENTIALS */
} s3h2_thread_state_t;

/*******************************************************************************
 * Payload Structures
 ******************************************************************************/

/**
 * @brief Status response payload (RSP_STATUS)
 */
typedef struct __attribute__((packed)) {
    uint8_t thread_state;           /**< s3h2_thread_state_t */
    uint16_t pan_id;                /**< Current PAN ID */
    uint8_t channel;                /**< Current channel */
    uint16_t rloc16;                /**< Router Locator (16-bit address) */
    uint8_t device_count;           /**< Number of devices on network (neighbors, excluding self) */
    uint8_t joining_enabled;        /**< 1 if joining enabled, 0 otherwise */
    uint32_t partition_id;          /**< Thread partition ID (0 if not attached). Different values across Hubs in the same account indicate a split mesh. */
} s3h2_status_payload_t;

/**
 * @brief Credentials payload (RSP_CREDENTIALS response, CMD_SET_CREDENTIALS command)
 *
 * INVARIANT: Thread credentials are NEVER generated locally on the H2.
 * They originate from the cloud `adopt_device` / `get_thread_credentials` edge
 * functions, are received by the S3 over HTTPS, and pushed to the H2 via
 * CMD_SET_CREDENTIALS. The H2 only persists what S3 hands it.
 */
typedef struct __attribute__((packed)) {
    char network_name[17];          /**< Network name (null-terminated) */
    uint16_t pan_id;                /**< PAN ID */
    uint8_t channel;                /**< Channel */
    uint8_t network_key[16];        /**< 128-bit Thread network master key */
    uint8_t extended_pan_id[8];     /**< 64-bit Extended PAN ID */
    uint8_t mesh_local_prefix[8];   /**< 64-bit Mesh-local prefix */
    uint8_t pskc[16];               /**< 128-bit Pre-Shared Key for Commissioner */
} s3h2_credentials_payload_t;

/**
 * @brief Enable joining command payload (CMD_ENABLE_JOINING)
 */
typedef struct __attribute__((packed)) {
    uint32_t duration_sec;          /**< Duration in seconds (0 = indefinite) */
} s3h2_enable_joining_payload_t;

/**
 * @brief Crate joined event payload (EVT_CRATE_JOINED)
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Extended MAC address */
    uint16_t rloc16;                /**< Router Locator */
} s3h2_crate_joined_payload_t;

/**
 * @brief Crate left event payload (EVT_CRATE_LEFT)
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Extended MAC address */
} s3h2_crate_left_payload_t;

/**
 * @brief Inventory update event payload (EVT_INVENTORY_UPDATE)
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Crate extended MAC address */
    uint8_t slot_count;             /**< Number of slots in crate */
    /* Followed by slot_count * 12-byte EPC values */
} s3h2_inventory_update_payload_t;

/**
 * @brief Crate heartbeat event payload (EVT_CRATE_HEARTBEAT)
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Crate extended MAC address */
    uint8_t battery_percent;        /**< Battery level (0-100) */
    int8_t rssi;                    /**< Signal strength (dBm) */
} s3h2_crate_heartbeat_payload_t;

/**
 * @brief Thread state event payload (EVT_THREAD_STATE)
 */
typedef struct __attribute__((packed)) {
    uint8_t old_state;              /**< Previous state (s3h2_thread_state_t) */
    uint8_t new_state;              /**< New state (s3h2_thread_state_t) */
} s3h2_thread_state_payload_t;

/**
 * @brief NAK response payload (RSP_NAK)
 */
typedef struct __attribute__((packed)) {
    uint8_t error_code;             /**< s3h2_error_t */
} s3h2_nak_payload_t;

/**
 * @brief Version response payload (RSP_VERSION)
 */
typedef struct __attribute__((packed)) {
    uint8_t major;                  /**< Major version */
    uint8_t minor;                  /**< Minor version */
    uint8_t patch;                  /**< Patch version */
} s3h2_version_payload_t;

/*******************************************************************************
 * Crate OTA Payload Structures (Phase 4)
 ******************************************************************************/

/** Maximum OTA data chunk size (fits in max payload with header overhead) */
#define S3H2_OTA_MAX_CHUNK_SIZE     512

/**
 * @brief OTA start command payload (CMD_OTA_START_CRATE)
 *
 * Initiates an OTA session to a specific crate device.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Target crate extended MAC address */
    uint32_t firmware_size;         /**< Total firmware size in bytes */
    uint8_t sha256[32];             /**< Expected SHA-256 hash of firmware */
    uint8_t version_major;          /**< New firmware major version */
    uint8_t version_minor;          /**< New firmware minor version */
    uint8_t version_patch;          /**< New firmware patch version */
} s3h2_ota_start_crate_payload_t;

/**
 * @brief OTA data command payload (CMD_OTA_DATA_CRATE)
 *
 * Sends a chunk of firmware data. Chunks must be sent sequentially.
 * The data follows immediately after this header.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Target crate extended MAC address */
    uint32_t offset;                /**< Byte offset in firmware image */
    uint16_t length;                /**< Chunk length (followed by 'length' bytes) */
    /* uint8_t data[length] follows */
} s3h2_ota_data_crate_payload_t;

/**
 * @brief OTA verify command payload (CMD_OTA_VERIFY_CRATE)
 *
 * Instructs the crate to verify the received firmware and apply the update.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Target crate extended MAC address */
} s3h2_ota_verify_crate_payload_t;

/**
 * @brief OTA abort command payload (CMD_OTA_ABORT_CRATE)
 *
 * Aborts an in-progress OTA session.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Target crate extended MAC address */
} s3h2_ota_abort_crate_payload_t;

/**
 * @brief Ping crate command payload (CMD_PING_CRATE)
 *
 * Pings a crate to check if it's reachable on the Thread network.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Target crate extended MAC address */
} s3h2_ping_crate_payload_t;

/**
 * @brief OTA progress event payload (EVT_OTA_PROGRESS)
 *
 * Periodic progress update during OTA transfer.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Crate being updated */
    uint8_t percent;                /**< Progress percentage (0-100) */
    uint32_t bytes_sent;            /**< Bytes successfully sent to crate */
    uint32_t total_bytes;           /**< Total firmware size */
} s3h2_ota_progress_payload_t;

/**
 * @brief OTA complete event payload (EVT_OTA_COMPLETE)
 *
 * Sent when OTA completes (success or failure).
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Crate that was updated */
    uint8_t success;                /**< 1 = success, 0 = failure */
    uint8_t error_code;             /**< s3h2_error_t if failed */
} s3h2_ota_complete_payload_t;

/**
 * @brief Crate ping result event payload (EVT_CRATE_PING_RESULT)
 *
 * Response to CMD_PING_CRATE indicating if crate is reachable.
 */
typedef struct __attribute__((packed)) {
    uint8_t crate_ext_addr[8];      /**< Crate that was pinged */
    uint8_t reachable;              /**< 1 = reachable, 0 = not reachable */
    int8_t rssi;                    /**< Signal strength if reachable (dBm) */
} s3h2_ping_result_payload_t;

/*******************************************************************************
 * CoAP Mesh Protocol Payload Structures
 ******************************************************************************/

/** Heartbeat type codes for telemetry event */
#define S3H2_HB_TYPE_STATUS         0   /**< Regular status heartbeat */
#define S3H2_HB_TYPE_COMMAND_ACK    1   /**< Command acknowledgement */
#define S3H2_HB_TYPE_COMMAND_RESULT 2   /**< Command result */

/**
 * @brief CBOR telemetry event header (EVT_CRATE_TELEMETRY)
 *
 * Variable-length event: header followed by cbor_len bytes of CBOR data.
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Sender extended MAC address */
    uint8_t hb_type;                /**< Heartbeat type (S3H2_HB_TYPE_*) */
    uint16_t cbor_len;              /**< CBOR payload length (little-endian) */
    /* uint8_t cbor_data[cbor_len] follows */
} s3h2_crate_telemetry_header_t;

/**
 * @brief Command relay payload (CMD_RELAY_CMD)
 *
 * Variable-length command: header followed by cbor_len bytes of CBOR data.
 */
typedef struct __attribute__((packed)) {
    uint8_t target_ext_addr[8];     /**< Target node extended MAC address */
    uint16_t cbor_len;              /**< CBOR command length (little-endian) */
    /* uint8_t cbor_data[cbor_len] follows */
} s3h2_relay_cmd_header_t;

/**
 * @brief Crate registered event payload (EVT_CRATE_REGISTERED)
 *
 * Variable-length event containing device identity from CoAP /register.
 * String fields are length-prefixed: [len(1)][data(len)].
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Node extended MAC address */
    /* Followed by length-prefixed strings:
     *   uint8_t mac_len;       char mac[mac_len];
     *   uint8_t unit_id_len;   char unit_id[unit_id_len];
     *   uint8_t type_len;      char device_type[type_len];
     *   uint8_t fw_len;        char fw_version[fw_len];
     */
} s3h2_crate_registered_header_t;

/** Mesh command result codes */
#define S3H2_CMD_RESULT_OK          0   /**< Node acknowledged (CoAP 2.xx) */
#define S3H2_CMD_RESULT_TIMEOUT     1   /**< No CoAP response within 5s */
#define S3H2_CMD_RESULT_ERROR       2   /**< CoAP stack or other failure */

/**
 * @brief Mesh command result event payload (EVT_MESH_CMD_RESULT)
 *
 * Sent after the H2 attempts a CoAP POST /cmd to a mesh node
 * (e.g., re-register nudge, cloud-relayed command, etc.).
 */
typedef struct __attribute__((packed)) {
    uint8_t ext_addr[8];            /**< Target node extended address */
    uint8_t result;                 /**< S3H2_CMD_RESULT_* code */
    char cmd[16];                   /**< Command name (null-terminated, e.g. "register") */
} s3h2_mesh_cmd_result_payload_t;

/*******************************************************************************
 * Frame Structure
 ******************************************************************************/

/**
 * @brief Complete frame structure
 */
typedef struct {
    uint8_t type;                   /**< Message type */
    uint16_t length;                /**< Payload length */
    uint8_t payload[S3H2_MAX_PAYLOAD_LEN]; /**< Payload data */
    uint16_t checksum;              /**< CRC-16 checksum */
} s3h2_frame_t;

/*******************************************************************************
 * CRC-16/CCITT Calculation
 ******************************************************************************/

/**
 * @brief Calculate CRC-16/CCITT checksum
 *
 * Polynomial: 0x1021
 * Initial value: 0xFFFF
 *
 * @param data Data buffer
 * @param len Data length
 * @return CRC-16 checksum
 */
static inline uint16_t s3h2_crc16(const uint8_t *data, size_t len)
{
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= ((uint16_t)data[i] << 8);
        for (int j = 0; j < 8; j++) {
            if (crc & 0x8000) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

#ifdef __cplusplus
}
#endif

#endif /* S3_H2_PROTOCOL_H */
