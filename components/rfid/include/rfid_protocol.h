/**
 * @file rfid_protocol.h
 * @brief YRM100 frame protocol codec interface
 *
 * Provides frame building and parsing for the YRM100 UHF RFID module's
 * binary protocol. The protocol uses framed messages with header (0xBB),
 * type, command, length-prefixed parameters, checksum, and end marker (0x7E).
 *
 * Frame Format:
 * [Header:0xBB] [Type:1B] [Command:1B] [PL_MSB:1B] [PL_LSB:1B] [Params:N] [Checksum:1B] [End:0x7E]
 *
 * Types:
 * - 0x00: Command (host to module)
 * - 0x01: Response (module to host, in response to command)
 * - 0x02: Notice (module to host, unsolicited - e.g., tag detected)
 */

#ifndef RFID_PROTOCOL_H
#define RFID_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/* Frame markers */
#define RFID_FRAME_HEADER           0xBB
#define RFID_FRAME_END              0x7E

/* Frame types */
#define RFID_FRAME_TYPE_COMMAND     0x00
#define RFID_FRAME_TYPE_RESPONSE    0x01
#define RFID_FRAME_TYPE_NOTICE      0x02

/* YRM100 Commands */
#define RFID_CMD_GET_FIRMWARE_VER   0x03
#define RFID_CMD_SINGLE_POLL        0x22
#define RFID_CMD_MULTIPLE_POLL      0x27
#define RFID_CMD_STOP_MULTIPLE_POLL 0x28
#define RFID_CMD_SET_RF_POWER       0xB6
#define RFID_CMD_GET_RF_POWER       0xB7

/* Response/Error codes (found in params[0] for error responses) */
#define RFID_RESP_SUCCESS           0x00
#define RFID_RESP_TAG_NOT_FOUND     0x15
#define RFID_RESP_READ_FAILED       0x16
#define RFID_RESP_WRITE_FAILED      0x17

/* Maximum sizes */
#define RFID_MAX_FRAME_SIZE         128
#define RFID_MAX_PARAMS_SIZE        100
#define RFID_MIN_FRAME_SIZE         7    /* Header + Type + Cmd + PL(2) + Checksum + End */

/* EPC constants */
#define RFID_EPC_MAX_LEN            12   /* 96 bits = 12 bytes */
#define RFID_SATURDAY_PREFIX_0      0x53 /* 'S' */
#define RFID_SATURDAY_PREFIX_1      0x56 /* 'V' */

/*******************************************************************************
 * Types
 ******************************************************************************/

/**
 * @brief Parsed RFID frame structure
 */
typedef struct {
    uint8_t type;           /**< Frame type (command/response/notice) */
    uint8_t command;        /**< Command code */
    const uint8_t *params;  /**< Pointer to parameters within original buffer */
    uint16_t param_len;     /**< Number of parameter bytes */
} rfid_frame_t;

/**
 * @brief Parsed tag data from a notice or response
 */
typedef struct {
    uint8_t rssi;           /**< Received signal strength (raw value) */
    uint16_t pc;            /**< Protocol Control word */
    uint8_t epc[RFID_EPC_MAX_LEN]; /**< EPC data */
    uint8_t epc_len;        /**< Actual EPC length in bytes */
    bool is_saturday_tag;   /**< True if EPC has Saturday prefix (0x5356) */
} rfid_tag_t;

/*******************************************************************************
 * Frame Building Functions
 ******************************************************************************/

/**
 * @brief Calculate checksum for frame data
 *
 * Checksum is the low byte of the sum of: type + command + PL_MSB + PL_LSB + all params.
 *
 * @param type Frame type byte
 * @param cmd Command byte
 * @param params Parameter bytes (can be NULL if param_len is 0)
 * @param param_len Number of parameter bytes
 * @return Checksum byte
 */
uint8_t rfid_calculate_checksum(uint8_t type, uint8_t cmd,
                                 const uint8_t *params, uint16_t param_len);

/**
 * @brief Build a command frame
 *
 * Creates a complete frame ready to send to the YRM100 module.
 *
 * @param cmd Command code
 * @param params Parameter bytes (can be NULL if param_len is 0)
 * @param param_len Number of parameter bytes
 * @param out_buf Output buffer for frame (must be at least param_len + 7 bytes)
 * @param out_buf_size Size of output buffer
 * @return Total frame length, or 0 if buffer too small
 */
size_t rfid_build_frame(uint8_t cmd, const uint8_t *params, uint16_t param_len,
                        uint8_t *out_buf, size_t out_buf_size);

/*******************************************************************************
 * Frame Parsing Functions
 ******************************************************************************/

/**
 * @brief Parse a received frame
 *
 * Validates frame structure, length, and checksum. On success, the frame
 * structure contains pointers into the original buffer.
 *
 * @param buf Input buffer containing frame data
 * @param len Length of input buffer
 * @param frame Output structure for parsed frame data
 * @return true if valid frame, false otherwise
 */
bool rfid_parse_frame(const uint8_t *buf, size_t len, rfid_frame_t *frame);

/**
 * @brief Find the next complete frame in a buffer
 *
 * Scans buffer for a frame starting with 0xBB and ending with 0x7E.
 * Useful for extracting frames from a stream that may contain multiple
 * frames or partial data.
 *
 * @param buf Input buffer to scan
 * @param buf_len Length of input buffer
 * @param frame_start Output: index of frame start (0xBB)
 * @param frame_len Output: total frame length including markers
 * @return true if complete frame found, false otherwise
 */
bool rfid_find_frame(const uint8_t *buf, size_t buf_len,
                     size_t *frame_start, size_t *frame_len);

/*******************************************************************************
 * Tag Parsing Functions
 ******************************************************************************/

/**
 * @brief Parse tag data from a poll response or notice frame
 *
 * Extracts RSSI, PC word, and EPC from the frame parameters.
 * The tag notice format for MultiplePoll is:
 * [RSSI:1] [PC:2] [EPC:N] [CRC:2]
 *
 * @param frame Parsed frame (should be a notice or poll response)
 * @param tag Output structure for tag data
 * @return true if valid tag data parsed, false otherwise
 */
bool rfid_parse_tag(const rfid_frame_t *frame, rfid_tag_t *tag);

/**
 * @brief Check if EPC belongs to a Saturday Vinyl tag
 *
 * Saturday tags have prefix 0x5356 ("SV") and are 12 bytes (96 bits).
 *
 * @param epc EPC data
 * @param epc_len Length of EPC data
 * @return true if Saturday tag, false otherwise
 */
bool rfid_is_saturday_tag(const uint8_t *epc, uint8_t epc_len);

/**
 * @brief Extract EPC length from Protocol Control word
 *
 * PC bits 15-11 contain the EPC length in 16-bit words.
 *
 * @param pc Protocol Control word
 * @return EPC length in bytes
 */
uint8_t rfid_get_epc_len_from_pc(uint16_t pc);

/**
 * @brief Convert EPC bytes to hex string
 *
 * @param epc EPC data
 * @param epc_len Length of EPC data
 * @param out_str Output string buffer (must be at least epc_len*2 + 1)
 * @param out_str_size Size of output buffer
 */
void rfid_epc_to_hex_string(const uint8_t *epc, uint8_t epc_len,
                            char *out_str, size_t out_str_size);

/**
 * @brief Convert RSSI raw value to approximate dBm
 *
 * The YRM100 returns a raw RSSI value that needs conversion.
 * This provides an approximate dBm value.
 *
 * @param rssi_raw Raw RSSI value from module
 * @return Approximate RSSI in dBm (negative value)
 */
int8_t rfid_rssi_to_dbm(uint8_t rssi_raw);

#ifdef __cplusplus
}
#endif

#endif /* RFID_PROTOCOL_H */
