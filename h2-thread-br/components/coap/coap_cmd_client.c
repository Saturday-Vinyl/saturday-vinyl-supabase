/**
 * @file coap_cmd_client.c
 * @brief CoAP Command Client Implementation
 *
 * Sends CBOR-encoded commands to mesh nodes via CoAP POST /cmd.
 * Reuses the address-building pattern from coap_ota.c.
 *
 * CoAP Mesh Protocol: Section 8 - POST /cmd
 */

#include "coap_cmd_client.h"
#include "esp_log.h"
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "openthread/coap.h"
#include "openthread/instance.h"
#include "openthread/message.h"
#include "openthread/thread.h"
#include "openthread/ip6.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include <string.h>

static const char *TAG = "COAP_CMD";

#define CMD_TIMEOUT_MS      5000
#define EVT_RESPONSE        BIT0
#define EVT_TIMEOUT         BIT1

/* Content-Format option number for CBOR */
#define COAP_CONTENT_FORMAT_CBOR  60

static EventGroupHandle_t s_events = NULL;
static bool s_response_ok = false;
static bool s_response_rejected = false;  /* Crate responded with non-2.xx CoAP code */

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t coap_cmd_client_init(void)
{
    if (s_events == NULL) {
        s_events = xEventGroupCreate();
        if (s_events == NULL) {
            ESP_LOGE(TAG, "Failed to create event group");
            return ESP_ERR_NO_MEM;
        }
    }

    ESP_LOGI(TAG, "CoAP command client initialized");
    return ESP_OK;
}

/*******************************************************************************
 * Internal: Build mesh-local IPv6 from extended address
 ******************************************************************************/

static esp_err_t build_target_ip6(const uint8_t *ext_addr, otIp6Address *ip6_addr)
{
    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_openthread_lock_acquire(portMAX_DELAY);

    const otMeshLocalPrefix *mlp = otThreadGetMeshLocalPrefix(instance);
    if (mlp == NULL) {
        esp_openthread_lock_release();
        return ESP_ERR_INVALID_STATE;
    }

    memset(ip6_addr, 0, sizeof(otIp6Address));
    memcpy(ip6_addr->mFields.m8, mlp->m8, 8);

    /* IID from extended address with U/L bit flip */
    memcpy(&ip6_addr->mFields.m8[8], ext_addr, 8);
    ip6_addr->mFields.m8[8] ^= 0x02;

    esp_openthread_lock_release();
    return ESP_OK;
}

/*******************************************************************************
 * Response Handler
 ******************************************************************************/

static void cmd_response_handler(void *context, otMessage *message,
                                  const otMessageInfo *message_info,
                                  otError result)
{
    if (result != OT_ERROR_NONE) {
        ESP_LOGW(TAG, "Command request failed: %d", result);
        s_response_ok = false;
        xEventGroupSetBits(s_events, EVT_TIMEOUT);
        return;
    }

    otCoapCode code = otCoapMessageGetCode(message);
    ESP_LOGI(TAG, "Command response: %d.%02d",
             (code >> 5), (code & 0x1F));

    s_response_ok = ((code >> 5) == 2);
    s_response_rejected = !s_response_ok;  /* Non-2.xx = crate rejected the command */
    xEventGroupSetBits(s_events, EVT_RESPONSE);
}

/*******************************************************************************
 * Send Command
 ******************************************************************************/

esp_err_t coap_cmd_client_send(const uint8_t *target_ext_addr,
                                const uint8_t *cbor_data,
                                uint16_t cbor_len)
{
    if (target_ext_addr == NULL || cbor_data == NULL || cbor_len == 0) {
        return ESP_ERR_INVALID_ARG;
    }

    if (s_events == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    /* Build target IPv6 */
    otIp6Address target_ip6;
    esp_err_t err = build_target_ip6(target_ext_addr, &target_ip6);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to build target IPv6 address");
        return err;
    }

    /* Clear events */
    xEventGroupClearBits(s_events, EVT_RESPONSE | EVT_TIMEOUT);
    s_response_ok = false;
    s_response_rejected = false;

    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Create CoAP message */
    otMessage *message = otCoapNewMessage(instance, NULL);
    if (message == NULL) {
        ESP_LOGE(TAG, "Failed to allocate CoAP message");
        esp_openthread_lock_release();
        return ESP_ERR_NO_MEM;
    }

    /* Initialize as CON POST */
    otCoapMessageInit(message, OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_POST);
    otCoapMessageGenerateToken(message, OT_COAP_DEFAULT_TOKEN_LENGTH);

    /* URI-Path: "cmd" */
    otError ot_err = otCoapMessageAppendUriPathOptions(message, "cmd");
    if (ot_err != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to append URI path: %d", ot_err);
        otMessageFree(message);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Content-Format: 60 (CBOR) */
    ot_err = otCoapMessageAppendContentFormatOption(message, COAP_CONTENT_FORMAT_CBOR);
    if (ot_err != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to append content format: %d", ot_err);
        otMessageFree(message);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Payload marker + CBOR data */
    ot_err = otCoapMessageSetPayloadMarker(message);
    if (ot_err != OT_ERROR_NONE) {
        otMessageFree(message);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    ot_err = otMessageAppend(message, cbor_data, cbor_len);
    if (ot_err != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to append payload: %d", ot_err);
        otMessageFree(message);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Build message info */
    otMessageInfo message_info;
    memset(&message_info, 0, sizeof(message_info));
    memcpy(&message_info.mPeerAddr, &target_ip6, sizeof(otIp6Address));
    message_info.mPeerPort = OT_DEFAULT_COAP_PORT;

    /* Send */
    ESP_LOGI(TAG, "Sending CoAP POST /cmd (%d bytes CBOR)", cbor_len);
    ot_err = otCoapSendRequest(instance, message, &message_info, cmd_response_handler, NULL);

    esp_openthread_lock_release();

    if (ot_err != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to send CoAP request: %d", ot_err);
        return ESP_FAIL;
    }

    /* Wait for response */
    EventBits_t bits = xEventGroupWaitBits(s_events,
                                            EVT_RESPONSE | EVT_TIMEOUT,
                                            pdTRUE, pdFALSE,
                                            pdMS_TO_TICKS(CMD_TIMEOUT_MS));

    if (bits & EVT_RESPONSE) {
        if (s_response_ok) {
            return ESP_OK;
        }
        /* Crate responded but with a non-2.xx code (e.g., 4.04 Not Found) */
        return s_response_rejected ? ESP_ERR_NOT_FOUND : ESP_FAIL;
    }

    ESP_LOGW(TAG, "Command timed out");
    return ESP_ERR_TIMEOUT;
}
