/**
 * @file coap_ota.c
 * @brief CoAP OTA Client Implementation
 *
 * Uses OpenThread's CoAP API to send firmware updates to Thread devices.
 *
 * Phase 4: Crate OTA Relay - H2 CoAP Client
 */

#include "coap_ota.h"
#include "s3_comm.h"
#include "thread_br.h"
#include "s3_h2_protocol.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"
#include <string.h>

/* OpenThread includes */
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "openthread/coap.h"
#include "openthread/instance.h"
#include "openthread/message.h"
#include "openthread/thread.h"
#include "openthread/ip6.h"

/* CoAP code extraction macros (removed in newer OpenThread versions) */
#ifndef OT_COAP_CODE_CLASS
#define OT_COAP_CODE_CLASS(code)  (((code) >> 5) & 0x7)
#endif
#ifndef OT_COAP_CODE_DETAIL
#define OT_COAP_CODE_DETAIL(code) ((code) & 0x1f)
#endif

static const char *TAG = "COAP_OTA";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(COAP_OTA_EVENTS);

/*******************************************************************************
 * Constants
 ******************************************************************************/

/* CoAP endpoints on the Crate */
#define OTA_URI_START       "ota/start"
#define OTA_URI_DATA        "ota/data"
#define OTA_URI_VERIFY      "ota/verify"
#define OTA_URI_ABORT       "ota/abort"
#define OTA_URI_PING        "ping"

/* Event bits */
#define EVT_RESPONSE_RECEIVED   BIT0
#define EVT_TIMEOUT             BIT1

/*******************************************************************************
 * OTA Session Structure
 ******************************************************************************/

typedef struct {
    bool active;
    uint8_t target_addr[8];             /**< Target extended address */
    otIp6Address target_ip6;            /**< Target IPv6 address */
    uint32_t firmware_size;             /**< Total firmware size */
    uint8_t sha256[32];                 /**< Expected hash */
    uint8_t version_major;
    uint8_t version_minor;
    uint8_t version_patch;

    /* Transfer state */
    coap_ota_state_t state;
    uint32_t bytes_sent;                /**< Bytes sent to crate */
    uint32_t bytes_acked;               /**< Bytes acknowledged */
    uint8_t retries;
    uint32_t start_time_ms;
    uint8_t last_error;

    /* Response handling */
    EventGroupHandle_t events;
    bool response_success;
    uint8_t response_code;
} ota_session_t;

/*******************************************************************************
 * Module State
 ******************************************************************************/

static bool s_initialized = false;
static SemaphoreHandle_t s_mutex = NULL;
static ota_session_t s_session = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void coap_response_handler(void *context, otMessage *message,
                                  const otMessageInfo *message_info,
                                  otError result);
static esp_err_t send_coap_request(const otIp6Address *dest_addr,
                                    const char *uri_path,
                                    otCoapType type,
                                    otCoapCode code,
                                    const void *payload,
                                    uint16_t payload_len,
                                    uint32_t timeout_ms);
static esp_err_t build_target_ip6(const uint8_t *ext_addr, otIp6Address *ip6_addr);
static void report_progress(void);
static void report_complete(bool success, s3h2_error_t error);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t coap_ota_init(void)
{
    if (s_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing CoAP OTA client...");

    s_mutex = xSemaphoreCreateMutex();
    if (s_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    s_session.events = xEventGroupCreate();
    if (s_session.events == NULL) {
        ESP_LOGE(TAG, "Failed to create event group");
        vSemaphoreDelete(s_mutex);
        return ESP_ERR_NO_MEM;
    }

    memset(&s_session, 0, sizeof(s_session));
    s_session.state = COAP_OTA_STATE_IDLE;

    s_initialized = true;
    ESP_LOGI(TAG, "CoAP OTA client initialized");
    return ESP_OK;
}

esp_err_t coap_ota_deinit(void)
{
    if (!s_initialized) {
        return ESP_OK;
    }

    /* Abort any active session */
    if (s_session.active) {
        coap_ota_abort(s_session.target_addr);
    }

    if (s_session.events != NULL) {
        vEventGroupDelete(s_session.events);
    }
    if (s_mutex != NULL) {
        vSemaphoreDelete(s_mutex);
    }

    s_initialized = false;
    ESP_LOGI(TAG, "CoAP OTA client deinitialized");
    return ESP_OK;
}

bool coap_ota_is_initialized(void)
{
    return s_initialized;
}

/*******************************************************************************
 * Session Management
 ******************************************************************************/

esp_err_t coap_ota_start_session(const uint8_t *target_ext_addr,
                                  uint32_t firmware_size,
                                  const uint8_t *sha256,
                                  uint8_t version_major,
                                  uint8_t version_minor,
                                  uint8_t version_patch)
{
    if (!s_initialized) {
        return ESP_ERR_INVALID_STATE;
    }
    if (target_ext_addr == NULL || sha256 == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (s_session.active) {
        xSemaphoreGive(s_mutex);
        ESP_LOGE(TAG, "Session already active");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Starting OTA session to %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             target_ext_addr[0], target_ext_addr[1], target_ext_addr[2], target_ext_addr[3],
             target_ext_addr[4], target_ext_addr[5], target_ext_addr[6], target_ext_addr[7]);
    ESP_LOGI(TAG, "  Firmware size: %lu bytes, version: %d.%d.%d",
             (unsigned long)firmware_size, version_major, version_minor, version_patch);

    /* Initialize session */
    memset(&s_session, 0, sizeof(s_session));
    memcpy(s_session.target_addr, target_ext_addr, 8);
    s_session.firmware_size = firmware_size;
    memcpy(s_session.sha256, sha256, 32);
    s_session.version_major = version_major;
    s_session.version_minor = version_minor;
    s_session.version_patch = version_patch;
    s_session.state = COAP_OTA_STATE_STARTING;
    s_session.start_time_ms = esp_timer_get_time() / 1000;
    s_session.active = true;

    /* Recreate event group if needed */
    if (s_session.events == NULL) {
        s_session.events = xEventGroupCreate();
    }

    /* Build target IPv6 address */
    esp_err_t err = build_target_ip6(target_ext_addr, &s_session.target_ip6);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to build target IP6 address");
        s_session.active = false;
        s_session.state = COAP_OTA_STATE_IDLE;
        xSemaphoreGive(s_mutex);
        return err;
    }

    xSemaphoreGive(s_mutex);

    /* Build start payload:
     * - 4 bytes: firmware size (little-endian)
     * - 32 bytes: SHA-256 hash
     * - 3 bytes: version (major, minor, patch)
     */
    uint8_t start_payload[39];
    start_payload[0] = firmware_size & 0xFF;
    start_payload[1] = (firmware_size >> 8) & 0xFF;
    start_payload[2] = (firmware_size >> 16) & 0xFF;
    start_payload[3] = (firmware_size >> 24) & 0xFF;
    memcpy(&start_payload[4], sha256, 32);
    start_payload[36] = version_major;
    start_payload[37] = version_minor;
    start_payload[38] = version_patch;

    /* Send CoAP POST to /ota/start */
    err = send_coap_request(&s_session.target_ip6, OTA_URI_START,
                            OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_POST,
                            start_payload, sizeof(start_payload),
                            COAP_OTA_RESPONSE_TIMEOUT);

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (err != ESP_OK || !s_session.response_success) {
        ESP_LOGE(TAG, "OTA start request failed");
        s_session.active = false;
        s_session.state = COAP_OTA_STATE_FAILED;
        s_session.last_error = S3H2_ERR_CRATE_UNREACHABLE;
        xSemaphoreGive(s_mutex);
        report_complete(false, S3H2_ERR_CRATE_UNREACHABLE);
        return ESP_FAIL;
    }

    s_session.state = COAP_OTA_STATE_TRANSFERRING;
    ESP_LOGI(TAG, "OTA session started, ready for data");

    xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t coap_ota_send_chunk(const uint8_t *target_ext_addr,
                               uint32_t offset,
                               const uint8_t *data,
                               uint16_t length)
{
    if (!s_initialized || target_ext_addr == NULL || data == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    /* Verify session is active for this target */
    if (!s_session.active ||
        memcmp(s_session.target_addr, target_ext_addr, 8) != 0) {
        xSemaphoreGive(s_mutex);
        ESP_LOGE(TAG, "No active session for target");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_session.state != COAP_OTA_STATE_TRANSFERRING) {
        xSemaphoreGive(s_mutex);
        ESP_LOGE(TAG, "Session not in transfer state");
        return ESP_ERR_INVALID_STATE;
    }

    xSemaphoreGive(s_mutex);

    /* Build data payload:
     * - 4 bytes: offset (little-endian)
     * - N bytes: data
     */
    uint8_t *payload = malloc(4 + length);
    if (payload == NULL) {
        return ESP_ERR_NO_MEM;
    }

    payload[0] = offset & 0xFF;
    payload[1] = (offset >> 8) & 0xFF;
    payload[2] = (offset >> 16) & 0xFF;
    payload[3] = (offset >> 24) & 0xFF;
    memcpy(&payload[4], data, length);

    ESP_LOGD(TAG, "Sending chunk: offset=%lu, len=%d", (unsigned long)offset, length);

    /* Send CoAP POST to /ota/data */
    esp_err_t err = send_coap_request(&s_session.target_ip6, OTA_URI_DATA,
                                       OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_POST,
                                       payload, 4 + length,
                                       COAP_OTA_RESPONSE_TIMEOUT);
    free(payload);

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (err != ESP_OK || !s_session.response_success) {
        s_session.retries++;
        if (s_session.retries >= COAP_OTA_MAX_RETRIES) {
            ESP_LOGE(TAG, "Max retries exceeded for chunk at offset %lu",
                     (unsigned long)offset);
            s_session.state = COAP_OTA_STATE_FAILED;
            s_session.last_error = S3H2_ERR_TIMEOUT;
            s_session.active = false;
            xSemaphoreGive(s_mutex);
            report_complete(false, S3H2_ERR_TIMEOUT);
            return ESP_ERR_TIMEOUT;
        }
        xSemaphoreGive(s_mutex);
        ESP_LOGW(TAG, "Chunk send failed, retry %d/%d",
                 s_session.retries, COAP_OTA_MAX_RETRIES);
        return ESP_ERR_TIMEOUT;
    }

    /* Update progress */
    s_session.bytes_sent = offset + length;
    s_session.bytes_acked = offset + length;
    s_session.retries = 0;

    uint8_t new_percent = (s_session.bytes_acked * 100) / s_session.firmware_size;
    if (new_percent != (s_session.bytes_acked - length) * 100 / s_session.firmware_size) {
        /* Percent changed - report progress */
        report_progress();
    }

    xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t coap_ota_verify(const uint8_t *target_ext_addr)
{
    if (!s_initialized || target_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (!s_session.active ||
        memcmp(s_session.target_addr, target_ext_addr, 8) != 0) {
        xSemaphoreGive(s_mutex);
        ESP_LOGE(TAG, "No active session for target");
        return ESP_ERR_INVALID_STATE;
    }

    s_session.state = COAP_OTA_STATE_VERIFYING;
    xSemaphoreGive(s_mutex);

    ESP_LOGI(TAG, "Sending verify request...");

    /* Send CoAP POST to /ota/verify (no payload) */
    esp_err_t err = send_coap_request(&s_session.target_ip6, OTA_URI_VERIFY,
                                       OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_POST,
                                       NULL, 0,
                                       30000);  /* 30 second timeout for verify */

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (err != ESP_OK || !s_session.response_success) {
        ESP_LOGE(TAG, "Verify request failed");
        s_session.state = COAP_OTA_STATE_FAILED;
        s_session.last_error = S3H2_ERR_OTA_CHECKSUM;
        s_session.active = false;
        xSemaphoreGive(s_mutex);
        report_complete(false, S3H2_ERR_OTA_CHECKSUM);
        return ESP_FAIL;
    }

    /* Success! */
    s_session.state = COAP_OTA_STATE_COMPLETE;
    s_session.active = false;
    xSemaphoreGive(s_mutex);

    ESP_LOGI(TAG, "OTA completed successfully!");
    report_complete(true, S3H2_ERR_NONE);

    return ESP_OK;
}

esp_err_t coap_ota_abort(const uint8_t *target_ext_addr)
{
    if (!s_initialized || target_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (!s_session.active ||
        memcmp(s_session.target_addr, target_ext_addr, 8) != 0) {
        xSemaphoreGive(s_mutex);
        return ESP_OK;  /* Nothing to abort */
    }

    ESP_LOGW(TAG, "Aborting OTA session");

    s_session.state = COAP_OTA_STATE_FAILED;
    s_session.active = false;

    xSemaphoreGive(s_mutex);

    /* Try to send abort to crate (best effort) */
    send_coap_request(&s_session.target_ip6, OTA_URI_ABORT,
                      OT_COAP_TYPE_NON_CONFIRMABLE, OT_COAP_CODE_POST,
                      NULL, 0, 1000);

    return ESP_OK;
}

esp_err_t coap_ota_get_status(const uint8_t *target_ext_addr,
                               coap_ota_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_mutex, portMAX_DELAY);

    if (target_ext_addr != NULL &&
        (!s_session.active ||
         memcmp(s_session.target_addr, target_ext_addr, 8) != 0)) {
        xSemaphoreGive(s_mutex);
        return ESP_ERR_NOT_FOUND;
    }

    status->state = s_session.state;
    memcpy(status->target_addr, s_session.target_addr, 8);
    status->firmware_size = s_session.firmware_size;
    status->bytes_sent = s_session.bytes_sent;
    status->bytes_acked = s_session.bytes_acked;
    status->percent = s_session.firmware_size > 0 ?
                      (s_session.bytes_acked * 100) / s_session.firmware_size : 0;
    status->retries = s_session.retries;
    status->start_time_ms = s_session.start_time_ms;
    status->last_error = s_session.last_error;

    xSemaphoreGive(s_mutex);
    return ESP_OK;
}

bool coap_ota_is_busy(void)
{
    return s_session.active;
}

/*******************************************************************************
 * Utility Functions
 ******************************************************************************/

esp_err_t coap_ota_ping_device(const uint8_t *target_ext_addr,
                                uint32_t timeout_ms,
                                int8_t *rssi)
{
    if (!s_initialized || target_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "Pinging device %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             target_ext_addr[0], target_ext_addr[1], target_ext_addr[2], target_ext_addr[3],
             target_ext_addr[4], target_ext_addr[5], target_ext_addr[6], target_ext_addr[7]);

    otIp6Address target_ip6;
    esp_err_t err = build_target_ip6(target_ext_addr, &target_ip6);
    if (err != ESP_OK) {
        return err;
    }

    /* Send CoAP GET to /ping */
    err = send_coap_request(&target_ip6, OTA_URI_PING,
                            OT_COAP_TYPE_CONFIRMABLE, OT_COAP_CODE_GET,
                            NULL, 0, timeout_ms);

    if (err == ESP_OK && s_session.response_success) {
        ESP_LOGI(TAG, "Device is reachable");
        if (rssi != NULL) {
            *rssi = -50;  /* Placeholder - actual RSSI would come from response */
        }
        return ESP_OK;
    }

    ESP_LOGW(TAG, "Device not reachable");
    return ESP_ERR_TIMEOUT;
}

esp_err_t coap_ota_ext_addr_to_ip6(const uint8_t *ext_addr, char *ip6_addr)
{
    if (ext_addr == NULL || ip6_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Build mesh-local IID from extended address (EUI-64)
     * Format: fd{mesh-local-prefix}:{iid}
     * IID is derived from extended address with bit flip
     */
    uint8_t iid[8];
    memcpy(iid, ext_addr, 8);
    iid[0] ^= 0x02;  /* Universal/Local bit flip for EUI-64 -> IID */

    /* Get mesh-local prefix from Thread */
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

    snprintf(ip6_addr, 40, "%02x%02x:%02x%02x:%02x%02x:%02x%02x:"
             "%02x%02x:%02x%02x:%02x%02x:%02x%02x",
             mlp->m8[0], mlp->m8[1], mlp->m8[2], mlp->m8[3],
             mlp->m8[4], mlp->m8[5], mlp->m8[6], mlp->m8[7],
             iid[0], iid[1], iid[2], iid[3],
             iid[4], iid[5], iid[6], iid[7]);

    esp_openthread_lock_release();
    return ESP_OK;
}

/*******************************************************************************
 * Internal Functions
 ******************************************************************************/

static esp_err_t build_target_ip6(const uint8_t *ext_addr, otIp6Address *ip6_addr)
{
    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Get mesh-local prefix */
    const otMeshLocalPrefix *mlp = otThreadGetMeshLocalPrefix(instance);
    if (mlp == NULL) {
        esp_openthread_lock_release();
        return ESP_ERR_INVALID_STATE;
    }

    /* Build address: mesh-local prefix + IID from ext_addr */
    memset(ip6_addr, 0, sizeof(otIp6Address));
    memcpy(ip6_addr->mFields.m8, mlp->m8, 8);

    /* IID from extended address with U/L bit flip */
    memcpy(&ip6_addr->mFields.m8[8], ext_addr, 8);
    ip6_addr->mFields.m8[8] ^= 0x02;

    esp_openthread_lock_release();

    /* Log the address */
    char addr_str[40];
    snprintf(addr_str, sizeof(addr_str),
             "%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x:%02x%02x",
             ip6_addr->mFields.m8[0], ip6_addr->mFields.m8[1],
             ip6_addr->mFields.m8[2], ip6_addr->mFields.m8[3],
             ip6_addr->mFields.m8[4], ip6_addr->mFields.m8[5],
             ip6_addr->mFields.m8[6], ip6_addr->mFields.m8[7],
             ip6_addr->mFields.m8[8], ip6_addr->mFields.m8[9],
             ip6_addr->mFields.m8[10], ip6_addr->mFields.m8[11],
             ip6_addr->mFields.m8[12], ip6_addr->mFields.m8[13],
             ip6_addr->mFields.m8[14], ip6_addr->mFields.m8[15]);
    ESP_LOGD(TAG, "Target IP6: %s", addr_str);

    return ESP_OK;
}

static void coap_response_handler(void *context, otMessage *message,
                                  const otMessageInfo *message_info,
                                  otError result)
{
    if (result != OT_ERROR_NONE) {
        ESP_LOGW(TAG, "CoAP request failed: %d", result);
        s_session.response_success = false;
        xEventGroupSetBits(s_session.events, EVT_TIMEOUT);
        return;
    }

    otCoapCode code = otCoapMessageGetCode(message);
    ESP_LOGD(TAG, "CoAP response received: code=%d.%02d",
             OT_COAP_CODE_CLASS(code), OT_COAP_CODE_DETAIL(code));

    /* Check for success codes (2.xx) */
    if (OT_COAP_CODE_CLASS(code) == 2) {
        s_session.response_success = true;
    } else {
        ESP_LOGW(TAG, "CoAP error response: %d.%02d",
                 OT_COAP_CODE_CLASS(code), OT_COAP_CODE_DETAIL(code));
        s_session.response_success = false;
    }

    s_session.response_code = code;
    xEventGroupSetBits(s_session.events, EVT_RESPONSE_RECEIVED);
}

static esp_err_t send_coap_request(const otIp6Address *dest_addr,
                                    const char *uri_path,
                                    otCoapType type,
                                    otCoapCode code,
                                    const void *payload,
                                    uint16_t payload_len,
                                    uint32_t timeout_ms)
{
    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    /* Clear events */
    xEventGroupClearBits(s_session.events, EVT_RESPONSE_RECEIVED | EVT_TIMEOUT);
    s_session.response_success = false;

    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Create CoAP message */
    otMessage *message = otCoapNewMessage(instance, NULL);
    if (message == NULL) {
        ESP_LOGE(TAG, "Failed to allocate CoAP message");
        esp_openthread_lock_release();
        return ESP_ERR_NO_MEM;
    }

    /* Initialize message (returns void in OpenThread v4+) */
    otCoapMessageInit(message, type, code);

    otError error;

    /* Generate message ID and token */
    otCoapMessageGenerateToken(message, OT_COAP_DEFAULT_TOKEN_LENGTH);

    /* Add URI path option */
    error = otCoapMessageAppendUriPathOptions(message, uri_path);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to append URI path: %d", error);
        otMessageFree(message);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Add payload if present */
    if (payload != NULL && payload_len > 0) {
        error = otCoapMessageSetPayloadMarker(message);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to set payload marker: %d", error);
            otMessageFree(message);
            esp_openthread_lock_release();
            return ESP_FAIL;
        }

        error = otMessageAppend(message, payload, payload_len);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to append payload: %d", error);
            otMessageFree(message);
            esp_openthread_lock_release();
            return ESP_FAIL;
        }
    }

    /* Build message info */
    otMessageInfo message_info;
    memset(&message_info, 0, sizeof(message_info));
    memcpy(&message_info.mPeerAddr, dest_addr, sizeof(otIp6Address));
    message_info.mPeerPort = OT_DEFAULT_COAP_PORT;

    /* Send request */
    ESP_LOGD(TAG, "Sending CoAP %s to /%s", code == OT_COAP_CODE_GET ? "GET" : "POST", uri_path);

    if (type == OT_COAP_TYPE_CONFIRMABLE) {
        error = otCoapSendRequest(instance, message, &message_info,
                                  coap_response_handler, NULL);
    } else {
        error = otCoapSendRequest(instance, message, &message_info, NULL, NULL);
    }

    esp_openthread_lock_release();

    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to send CoAP request: %d", error);
        return ESP_FAIL;
    }

    /* For non-confirmable, we're done */
    if (type != OT_COAP_TYPE_CONFIRMABLE) {
        s_session.response_success = true;
        return ESP_OK;
    }

    /* Wait for response */
    EventBits_t bits = xEventGroupWaitBits(s_session.events,
                                           EVT_RESPONSE_RECEIVED | EVT_TIMEOUT,
                                           pdTRUE, pdFALSE,
                                           pdMS_TO_TICKS(timeout_ms));

    if (bits & EVT_RESPONSE_RECEIVED) {
        return s_session.response_success ? ESP_OK : ESP_FAIL;
    }

    ESP_LOGW(TAG, "CoAP request timeout");
    return ESP_ERR_TIMEOUT;
}

static void report_progress(void)
{
    if (!s_session.active) {
        return;
    }

    uint8_t percent = (s_session.bytes_acked * 100) / s_session.firmware_size;

    ESP_LOGI(TAG, "Progress: %d%% (%lu/%lu bytes)",
             percent, (unsigned long)s_session.bytes_acked,
             (unsigned long)s_session.firmware_size);

    /* Report to S3 via UART */
    s3_comm_send_ota_progress(s_session.target_addr, percent,
                              s_session.bytes_acked, s_session.firmware_size);
}

static void report_complete(bool success, s3h2_error_t error)
{
    ESP_LOGI(TAG, "Reporting OTA complete: success=%d, error=%d", success, error);

    /* Report to S3 via UART */
    s3_comm_send_ota_complete(s_session.target_addr, success, error);
}
