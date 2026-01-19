/**
 * @file coap_server.c
 * @brief CoAP Server Implementation for Thread Device Communication
 *
 * Implements CoAP endpoints for receiving messages from RFID crates
 * using OpenThread's built-in CoAP implementation.
 *
 * Phase H2-2: CoAP Server
 */

#include "coap_server.h"
#include "s3_comm.h"
#include "thread_br.h"
#include "esp_log.h"
#include "esp_event.h"
#include <string.h>

/* OpenThread includes */
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "openthread/coap.h"
#include "openthread/instance.h"
#include "openthread/message.h"
#include "openthread/thread.h"
#include "openthread/ip6.h"

static const char *TAG = "COAP_SRV";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(COAP_SERVER_EVENTS);

/*******************************************************************************
 * Module State
 ******************************************************************************/

static bool s_initialized = false;
static bool s_running = false;
static coap_server_stats_t s_stats = {0};

/* CoAP resources */
static otCoapResource s_inventory_resource;
static otCoapResource s_heartbeat_resource;
static otCoapResource s_config_resource;

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void inventory_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info);
static void heartbeat_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info);
static void config_handler(void *context, otMessage *message,
                           const otMessageInfo *message_info);
static void send_coap_response(otMessage *request,
                               const otMessageInfo *request_info,
                               otCoapCode code,
                               const void *payload, uint16_t payload_len);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t coap_server_init(void)
{
    if (s_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing CoAP server...");

    /* Reset statistics */
    memset(&s_stats, 0, sizeof(s_stats));

    /* Initialize resource structures */
    memset(&s_inventory_resource, 0, sizeof(s_inventory_resource));
    memset(&s_heartbeat_resource, 0, sizeof(s_heartbeat_resource));
    memset(&s_config_resource, 0, sizeof(s_config_resource));

    /* Configure inventory resource */
    s_inventory_resource.mUriPath = "inventory";
    s_inventory_resource.mHandler = inventory_handler;
    s_inventory_resource.mContext = NULL;

    /* Configure heartbeat resource */
    s_heartbeat_resource.mUriPath = "heartbeat";
    s_heartbeat_resource.mHandler = heartbeat_handler;
    s_heartbeat_resource.mContext = NULL;

    /* Configure config resource */
    s_config_resource.mUriPath = "config";
    s_config_resource.mHandler = config_handler;
    s_config_resource.mContext = NULL;

    s_initialized = true;
    ESP_LOGI(TAG, "CoAP server initialized");
    return ESP_OK;
}

esp_err_t coap_server_start(void)
{
    if (!s_initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_running) {
        ESP_LOGW(TAG, "Already running");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting CoAP server...");

    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        ESP_LOGE(TAG, "OpenThread instance not available");
        return ESP_ERR_INVALID_STATE;
    }

    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Start CoAP */
    otError error = otCoapStart(instance, COAP_DEFAULT_PORT);
    if (error != OT_ERROR_NONE && error != OT_ERROR_ALREADY) {
        ESP_LOGE(TAG, "Failed to start CoAP: %d", error);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Add resources */
    otCoapAddResource(instance, &s_inventory_resource);
    otCoapAddResource(instance, &s_heartbeat_resource);
    otCoapAddResource(instance, &s_config_resource);

    esp_openthread_lock_release();

    s_running = true;
    ESP_LOGI(TAG, "CoAP server started on port %d", COAP_DEFAULT_PORT);
    ESP_LOGI(TAG, "  - POST /inventory");
    ESP_LOGI(TAG, "  - POST /heartbeat");
    ESP_LOGI(TAG, "  - GET  /config");

    return ESP_OK;
}

esp_err_t coap_server_stop(void)
{
    if (!s_running) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping CoAP server...");

    otInstance *instance = esp_openthread_get_instance();
    if (instance != NULL) {
        esp_openthread_lock_acquire(portMAX_DELAY);

        /* Remove resources */
        otCoapRemoveResource(instance, &s_inventory_resource);
        otCoapRemoveResource(instance, &s_heartbeat_resource);
        otCoapRemoveResource(instance, &s_config_resource);

        /* Stop CoAP */
        otCoapStop(instance);

        esp_openthread_lock_release();
    }

    s_running = false;
    ESP_LOGI(TAG, "CoAP server stopped");
    return ESP_OK;
}

esp_err_t coap_server_deinit(void)
{
    if (!s_initialized) {
        return ESP_OK;
    }

    /* Stop if running */
    if (s_running) {
        coap_server_stop();
    }

    s_initialized = false;
    ESP_LOGI(TAG, "CoAP server deinitialized");
    return ESP_OK;
}

bool coap_server_is_running(void)
{
    return s_running;
}

/*******************************************************************************
 * Resource Handlers
 ******************************************************************************/

/**
 * @brief Extract sender information from message
 */
static void get_sender_info(const otMessageInfo *message_info,
                            uint8_t *ext_addr_out,
                            uint16_t *rloc16_out)
{
    /* The peer address is in message_info->mPeerAddr */
    /* For Thread devices, we can get RLOC16 from the address */
    memset(ext_addr_out, 0, 8);
    *rloc16_out = 0;

    /* Check if it's a RLOC address (mesh-local, starts with fd::/8) */
    const otIp6Address *peer = &message_info->mPeerAddr;
    if (peer->mFields.m8[0] == 0xfd) {
        /* Last 2 bytes of mesh-local address contain RLOC16 */
        *rloc16_out = ((uint16_t)peer->mFields.m8[14] << 8) |
                      peer->mFields.m8[15];
    }

    /* Note: To get actual extended address, we'd need to look up the device
     * in the neighbor table. For now, we use a placeholder. */
    memcpy(ext_addr_out, peer->mFields.m8 + 8, 8);
}

/**
 * @brief Handle POST /inventory
 *
 * Payload format (simple binary):
 * - 1 byte: count of EPCs
 * - N * 12 bytes: EPC data
 */
static void inventory_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info)
{
    ESP_LOGI(TAG, "Inventory request received");
    s_stats.inventory_requests++;

    otCoapCode code = otCoapMessageGetCode(message);
    if (code != OT_COAP_CODE_POST) {
        ESP_LOGW(TAG, "Inventory: expected POST, got %d", code);
        send_coap_response(message, message_info, OT_COAP_CODE_METHOD_NOT_ALLOWED,
                           NULL, 0);
        return;
    }

    /* Get sender info */
    uint8_t ext_addr[8];
    uint16_t rloc16;
    get_sender_info(message_info, ext_addr, &rloc16);

    /* Read payload */
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;

    if (length < 1) {
        ESP_LOGW(TAG, "Inventory: payload too short");
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    uint8_t payload[1 + COAP_MAX_EPCS_PER_UPDATE * COAP_EPC_LENGTH];
    if (length > sizeof(payload)) {
        length = sizeof(payload);
    }

    if (otMessageRead(message, offset, payload, length) != length) {
        ESP_LOGW(TAG, "Inventory: failed to read payload");
        send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    uint8_t epc_count = payload[0];
    if (epc_count > COAP_MAX_EPCS_PER_UPDATE) {
        epc_count = COAP_MAX_EPCS_PER_UPDATE;
    }

    uint16_t expected_len = 1 + (epc_count * COAP_EPC_LENGTH);
    if (length < expected_len) {
        ESP_LOGW(TAG, "Inventory: payload incomplete, expected %d got %d",
                 expected_len, length);
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    ESP_LOGI(TAG, "Inventory from rloc16=0x%04X: %d EPCs", rloc16, epc_count);

    /* Forward to S3 via UART */
    if (epc_count > 0) {
        const uint8_t (*epcs)[12] = (const uint8_t (*)[12])&payload[1];
        esp_err_t ret = s3_comm_send_inventory_update(ext_addr, epcs, epc_count);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to forward inventory to S3: %s",
                     esp_err_to_name(ret));
        }
    } else {
        /* Empty inventory */
        esp_err_t ret = s3_comm_send_inventory_update(ext_addr, NULL, 0);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to forward empty inventory to S3: %s",
                     esp_err_to_name(ret));
        }
    }

    /* Post event for local handling */
    coap_inventory_event_t event = {
        .crate_rloc16 = rloc16,
        .epc_count = epc_count,
    };
    memcpy(event.crate_ext_addr, ext_addr, 8);
    if (epc_count > 0) {
        memcpy(event.epcs, &payload[1], epc_count * COAP_EPC_LENGTH);
    }
    esp_event_post(COAP_SERVER_EVENTS, COAP_SERVER_EVENT_INVENTORY_UPDATE,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /* Send success response */
    send_coap_response(message, message_info, OT_COAP_CODE_CHANGED, NULL, 0);
}

/**
 * @brief Handle POST /heartbeat
 *
 * Payload format (simple binary):
 * - 1 byte: battery percent (0-100)
 * - 1 byte: RSSI (signed, dBm)
 * - 1 byte: tag count
 */
static void heartbeat_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info)
{
    ESP_LOGD(TAG, "Heartbeat request received");
    s_stats.heartbeat_requests++;

    otCoapCode code = otCoapMessageGetCode(message);
    if (code != OT_COAP_CODE_POST) {
        ESP_LOGW(TAG, "Heartbeat: expected POST, got %d", code);
        send_coap_response(message, message_info, OT_COAP_CODE_METHOD_NOT_ALLOWED,
                           NULL, 0);
        return;
    }

    /* Get sender info */
    uint8_t ext_addr[8];
    uint16_t rloc16;
    get_sender_info(message_info, ext_addr, &rloc16);

    /* Read payload */
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;

    uint8_t battery_percent = 0;
    int8_t rssi = 0;
    uint8_t tag_count = 0;

    if (length >= 3) {
        uint8_t payload[3];
        if (otMessageRead(message, offset, payload, 3) == 3) {
            battery_percent = payload[0];
            rssi = (int8_t)payload[1];
            tag_count = payload[2];
        }
    }

    ESP_LOGD(TAG, "Heartbeat from rloc16=0x%04X: batt=%d%%, rssi=%ddBm, tags=%d",
             rloc16, battery_percent, rssi, tag_count);

    /* Forward to S3 via UART */
    esp_err_t ret = s3_comm_send_crate_heartbeat(ext_addr, battery_percent, rssi);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to forward heartbeat to S3: %s",
                 esp_err_to_name(ret));
    }

    /* Post event for local handling */
    coap_heartbeat_event_t event = {
        .crate_rloc16 = rloc16,
        .battery_percent = battery_percent,
        .rssi = rssi,
        .tag_count = tag_count,
    };
    memcpy(event.crate_ext_addr, ext_addr, 8);
    esp_event_post(COAP_SERVER_EVENTS, COAP_SERVER_EVENT_HEARTBEAT,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /* Send success response */
    send_coap_response(message, message_info, OT_COAP_CODE_CHANGED, NULL, 0);
}

/**
 * @brief Handle GET /config
 *
 * Returns crate configuration as simple JSON
 */
static void config_handler(void *context, otMessage *message,
                           const otMessageInfo *message_info)
{
    ESP_LOGD(TAG, "Config request received");
    s_stats.config_requests++;

    otCoapCode code = otCoapMessageGetCode(message);
    if (code != OT_COAP_CODE_GET) {
        ESP_LOGW(TAG, "Config: expected GET, got %d", code);
        send_coap_response(message, message_info, OT_COAP_CODE_METHOD_NOT_ALLOWED,
                           NULL, 0);
        return;
    }

    /* Build config response */
    /* For now, return simple static config */
    const char *config_json = "{\"version\":1,\"poll_interval\":30,"
                              "\"report_on_change\":true}";

    send_coap_response(message, message_info, OT_COAP_CODE_CONTENT,
                       config_json, strlen(config_json));
}

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static void send_coap_response(otMessage *request,
                               const otMessageInfo *request_info,
                               otCoapCode code,
                               const void *payload, uint16_t payload_len)
{
    otInstance *instance = esp_openthread_get_instance();
    if (instance == NULL) {
        return;
    }

    otMessage *response = otCoapNewMessage(instance, NULL);
    if (response == NULL) {
        ESP_LOGE(TAG, "Failed to allocate CoAP response");
        return;
    }

    otError error = otCoapMessageInitResponse(response, request,
                                              OT_COAP_TYPE_ACKNOWLEDGMENT,
                                              code);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to init CoAP response: %d", error);
        otMessageFree(response);
        return;
    }

    if (payload != NULL && payload_len > 0) {
        error = otCoapMessageSetPayloadMarker(response);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to set payload marker: %d", error);
            otMessageFree(response);
            return;
        }

        error = otMessageAppend(response, payload, payload_len);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to append payload: %d", error);
            otMessageFree(response);
            return;
        }
    }

    error = otCoapSendResponse(instance, response, request_info);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to send CoAP response: %d", error);
        otMessageFree(response);
    }
}

/*******************************************************************************
 * Statistics
 ******************************************************************************/

esp_err_t coap_server_get_stats(coap_server_stats_t *stats)
{
    if (stats == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memcpy(stats, &s_stats, sizeof(s_stats));
    return ESP_OK;
}
