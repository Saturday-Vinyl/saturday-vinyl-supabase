/**
 * @file rfid_protocol.c
 * @brief YRM100 frame protocol codec implementation
 *
 * Implements frame building, parsing, and tag data extraction for the
 * YRM100 UHF RFID module. The module uses a binary protocol over UART
 * with framed messages.
 *
 * Frame Format:
 * [Header:0xBB] [Type:1B] [Command:1B] [PL_MSB:1B] [PL_LSB:1B] [Params:N] [Checksum:1B] [End:0x7E]
 *
 * Tag Notice Format (params for MultiplePoll notices):
 * [RSSI:1] [PC:2] [EPC:N] [CRC:2]
 *
 * Where:
 * - RSSI: Signal strength (raw value, use rfid_rssi_to_dbm for conversion)
 * - PC: Protocol Control word (bits 15-11 = EPC length in words)
 * - EPC: Electronic Product Code (typically 12 bytes for 96-bit EPCs)
 * - CRC: Tag CRC (16-bit, can be ignored for detection purposes)
 */

#include "rfid_protocol.h"
#include "esp_log.h"
#include <string.h>
#include <stdio.h>

static const char *TAG = "RFID_PROTO";

/*******************************************************************************
 * Checksum Calculation
 ******************************************************************************/

uint8_t rfid_calculate_checksum(uint8_t type, uint8_t cmd,
                                 const uint8_t *params, uint16_t param_len)
{
    uint32_t sum = type + cmd;
    sum += (param_len >> 8) & 0xFF;  /* PL MSB */
    sum += param_len & 0xFF;          /* PL LSB */

    if (params != NULL) {
        for (uint16_t i = 0; i < param_len; i++) {
            sum += params[i];
        }
    }

    return (uint8_t)(sum & 0xFF);
}

/*******************************************************************************
 * Frame Building
 ******************************************************************************/

size_t rfid_build_frame(uint8_t cmd, const uint8_t *params, uint16_t param_len,
                        uint8_t *out_buf, size_t out_buf_size)
{
    size_t required_size = RFID_MIN_FRAME_SIZE + param_len;

    if (out_buf == NULL || out_buf_size < required_size) {
        ESP_LOGE(TAG, "Buffer too small: need %d, have %d",
                 required_size, out_buf_size);
        return 0;
    }

    size_t idx = 0;

    out_buf[idx++] = RFID_FRAME_HEADER;
    out_buf[idx++] = RFID_FRAME_TYPE_COMMAND;
    out_buf[idx++] = cmd;
    out_buf[idx++] = (param_len >> 8) & 0xFF;  /* PL MSB */
    out_buf[idx++] = param_len & 0xFF;          /* PL LSB */

    if (params != NULL && param_len > 0) {
        memcpy(&out_buf[idx], params, param_len);
        idx += param_len;
    }

    out_buf[idx++] = rfid_calculate_checksum(RFID_FRAME_TYPE_COMMAND, cmd,
                                              params, param_len);
    out_buf[idx++] = RFID_FRAME_END;

    return idx;
}

/*******************************************************************************
 * Frame Parsing
 ******************************************************************************/

bool rfid_parse_frame(const uint8_t *buf, size_t len, rfid_frame_t *frame)
{
    if (buf == NULL || frame == NULL) {
        return false;
    }

    if (len < RFID_MIN_FRAME_SIZE) {
        ESP_LOGD(TAG, "Frame too short: %d bytes (min %d)", len, RFID_MIN_FRAME_SIZE);
        return false;
    }

    /* Check header */
    if (buf[0] != RFID_FRAME_HEADER) {
        ESP_LOGD(TAG, "Invalid header: 0x%02X (expected 0x%02X)",
                 buf[0], RFID_FRAME_HEADER);
        return false;
    }

    /* Check end marker */
    if (buf[len - 1] != RFID_FRAME_END) {
        ESP_LOGD(TAG, "Invalid end marker: 0x%02X (expected 0x%02X)",
                 buf[len - 1], RFID_FRAME_END);
        return false;
    }

    uint8_t type = buf[1];
    uint8_t cmd = buf[2];
    uint16_t param_len = ((uint16_t)buf[3] << 8) | buf[4];

    /* Validate length */
    size_t expected_len = RFID_MIN_FRAME_SIZE + param_len;
    if (len != expected_len) {
        ESP_LOGD(TAG, "Length mismatch: got %d, expected %d", len, expected_len);
        return false;
    }

    /* Validate checksum */
    const uint8_t *params = (param_len > 0) ? &buf[5] : NULL;
    uint8_t expected_checksum = rfid_calculate_checksum(type, cmd, params, param_len);
    uint8_t received_checksum = buf[len - 2];

    if (received_checksum != expected_checksum) {
        ESP_LOGW(TAG, "Checksum mismatch: got 0x%02X, expected 0x%02X",
                 received_checksum, expected_checksum);
        return false;
    }

    /* Validate type */
    if (type != RFID_FRAME_TYPE_COMMAND &&
        type != RFID_FRAME_TYPE_RESPONSE &&
        type != RFID_FRAME_TYPE_NOTICE) {
        ESP_LOGW(TAG, "Unknown frame type: 0x%02X", type);
        return false;
    }

    /* Fill output structure */
    frame->type = type;
    frame->command = cmd;
    frame->params = params;
    frame->param_len = param_len;

    return true;
}

bool rfid_find_frame(const uint8_t *buf, size_t buf_len,
                     size_t *frame_start, size_t *frame_len)
{
    if (buf == NULL || frame_start == NULL || frame_len == NULL) {
        return false;
    }

    /* Find header byte */
    size_t start = 0;
    while (start < buf_len && buf[start] != RFID_FRAME_HEADER) {
        start++;
    }

    if (start >= buf_len) {
        return false;  /* No header found */
    }

    /* Check if we have enough bytes for minimum frame */
    if (buf_len - start < RFID_MIN_FRAME_SIZE) {
        return false;  /* Not enough data yet */
    }

    /* Extract payload length */
    uint16_t param_len = ((uint16_t)buf[start + 3] << 8) | buf[start + 4];
    size_t expected_len = RFID_MIN_FRAME_SIZE + param_len;

    /* Check if complete frame is available */
    if (buf_len - start < expected_len) {
        return false;  /* Frame incomplete */
    }

    /* Verify end marker */
    if (buf[start + expected_len - 1] != RFID_FRAME_END) {
        /* Invalid frame - skip this header and try again */
        if (start + 1 < buf_len) {
            size_t next_start, next_len;
            if (rfid_find_frame(&buf[start + 1], buf_len - start - 1,
                                &next_start, &next_len)) {
                *frame_start = start + 1 + next_start;
                *frame_len = next_len;
                return true;
            }
        }
        return false;
    }

    *frame_start = start;
    *frame_len = expected_len;
    return true;
}

/*******************************************************************************
 * Tag Parsing
 ******************************************************************************/

uint8_t rfid_get_epc_len_from_pc(uint16_t pc)
{
    /*
     * PC word bits 15-11 contain the number of 16-bit words in the EPC.
     * Multiply by 2 to get bytes.
     */
    uint8_t word_count = (pc >> 11) & 0x1F;
    return word_count * 2;
}

bool rfid_is_saturday_tag(const uint8_t *epc, uint8_t epc_len)
{
    if (epc == NULL || epc_len < 2) {
        return false;
    }

    /* Saturday tags are 96-bit (12 bytes) with prefix 0x5356 ("SV") */
    if (epc_len != RFID_EPC_MAX_LEN) {
        return false;
    }

    return (epc[0] == RFID_SATURDAY_PREFIX_0 &&
            epc[1] == RFID_SATURDAY_PREFIX_1);
}

bool rfid_parse_tag(const rfid_frame_t *frame, rfid_tag_t *tag)
{
    if (frame == NULL || tag == NULL) {
        return false;
    }

    /*
     * Tag notice/response format:
     * [RSSI:1] [PC:2] [EPC:N] [CRC:2]
     *
     * Minimum length: 1 + 2 + 2 + 2 = 7 bytes (for 2-byte EPC, which is unusual)
     * Typical length: 1 + 2 + 12 + 2 = 17 bytes (for 96-bit EPC)
     */
    const uint8_t *params = frame->params;
    uint16_t param_len = frame->param_len;

    if (params == NULL || param_len < 7) {
        ESP_LOGD(TAG, "Tag params too short: %d bytes", param_len);
        return false;
    }

    /* Extract RSSI */
    tag->rssi = params[0];

    /* Extract PC word (big-endian) */
    tag->pc = ((uint16_t)params[1] << 8) | params[2];

    /* Calculate EPC length from PC */
    uint8_t epc_len = rfid_get_epc_len_from_pc(tag->pc);

    /* Validate we have enough data: RSSI(1) + PC(2) + EPC(N) + CRC(2) */
    if (param_len < (size_t)(1 + 2 + epc_len + 2)) {
        ESP_LOGD(TAG, "Not enough data for EPC: need %d, have %d",
                 1 + 2 + epc_len + 2, param_len);
        return false;
    }

    /* Clamp EPC length to maximum */
    if (epc_len > RFID_EPC_MAX_LEN) {
        ESP_LOGW(TAG, "EPC length %d exceeds max %d, clamping",
                 epc_len, RFID_EPC_MAX_LEN);
        epc_len = RFID_EPC_MAX_LEN;
    }

    /* Copy EPC */
    tag->epc_len = epc_len;
    memset(tag->epc, 0, sizeof(tag->epc));
    memcpy(tag->epc, &params[3], epc_len);

    /* Check if Saturday tag */
    tag->is_saturday_tag = rfid_is_saturday_tag(tag->epc, tag->epc_len);

    ESP_LOGD(TAG, "Parsed tag: RSSI=%d, PC=0x%04X, EPC_LEN=%d, Saturday=%d",
             tag->rssi, tag->pc, tag->epc_len, tag->is_saturday_tag);

    return true;
}

/*******************************************************************************
 * Utility Functions
 ******************************************************************************/

void rfid_epc_to_hex_string(const uint8_t *epc, uint8_t epc_len,
                            char *out_str, size_t out_str_size)
{
    if (epc == NULL || out_str == NULL || out_str_size < 1) {
        if (out_str != NULL && out_str_size > 0) {
            out_str[0] = '\0';
        }
        return;
    }

    size_t required = (epc_len * 2) + 1;
    if (out_str_size < required) {
        epc_len = (out_str_size - 1) / 2;  /* Truncate if necessary */
    }

    for (uint8_t i = 0; i < epc_len; i++) {
        snprintf(&out_str[i * 2], 3, "%02X", epc[i]);
    }

    out_str[epc_len * 2] = '\0';
}

int8_t rfid_rssi_to_dbm(uint8_t rssi_raw)
{
    /*
     * The YRM100 RSSI is typically in a raw format where higher values
     * mean stronger signals. Based on common UHF RFID module conventions:
     *
     * - The raw value is often an unsigned representation
     * - Typical range is around 0-255 mapping to roughly -90 to -20 dBm
     *
     * This is an approximation - calibration may be needed for accuracy.
     * Formula: dBm ≈ -90 + (rssi_raw * 70 / 255)
     *
     * Some modules use: dBm = rssi_raw - 129 (if rssi is signed byte)
     *
     * We'll use a simple linear approximation for now.
     */
    if (rssi_raw >= 129) {
        /* Treat as signed: values 129-255 map to -127 to -1 dBm */
        return (int8_t)(rssi_raw - 256);
    } else {
        /* Values 0-128 - this would be unusual for RFID */
        return (int8_t)(-90 + (rssi_raw * 70 / 128));
    }
}
