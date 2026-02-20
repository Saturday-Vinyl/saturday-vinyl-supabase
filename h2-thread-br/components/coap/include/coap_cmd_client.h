/**
 * @file coap_cmd_client.h
 * @brief CoAP Command Client for Thread Device Communication
 *
 * Sends CBOR-encoded commands to mesh nodes via CoAP POST /cmd.
 * Used by the CMD_RELAY_CMD handler in s3_comm to forward commands
 * from the S3 master to Thread mesh devices.
 *
 * CoAP Mesh Protocol: Section 8 - POST /cmd
 */

#ifndef COAP_CMD_CLIENT_H
#define COAP_CMD_CLIENT_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the CoAP command client
 *
 * @return ESP_OK on success
 */
esp_err_t coap_cmd_client_init(void);

/**
 * @brief Send a CBOR command to a mesh node via CoAP POST /cmd
 *
 * Builds a CoAP CON POST to the target node's mesh-local address,
 * URI-Path "cmd", Content-Format 60 (CBOR), with the provided payload.
 *
 * @param target_ext_addr Target node extended MAC address (8 bytes, IID form)
 * @param cbor_data CBOR-encoded command payload
 * @param cbor_len CBOR payload length
 * @return ESP_OK if 2.xx response received, error code otherwise
 */
esp_err_t coap_cmd_client_send(const uint8_t *target_ext_addr,
                                const uint8_t *cbor_data,
                                uint16_t cbor_len);

#ifdef __cplusplus
}
#endif

#endif /* COAP_CMD_CLIENT_H */
