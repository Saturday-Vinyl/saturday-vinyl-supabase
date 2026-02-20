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
#include "s3_h2_protocol.h"
#include "thread_br.h"
#include "esp_log.h"
#include "esp_event.h"
#include "esp_timer.h"
#include <string.h>

/* OpenThread includes */
#include "esp_openthread.h"
#include "esp_openthread_lock.h"
#include "openthread/coap.h"
#include "openthread/instance.h"
#include "openthread/message.h"
#include "openthread/thread.h"
#include "openthread/ip6.h"

/* CBOR */
#include "cbor.h"

/* CoAP command client (for re-register nudge) */
#include "coap_cmd_client.h"

/* FreeRTOS (for nudge task + queue) */
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

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
static otCoapResource s_register_resource;

/*******************************************************************************
 * Device Registration Cache
 ******************************************************************************/

#define MAX_REGISTERED_DEVICES  20
#define CACHE_EXPIRY_MS         (5 * 60 * 1000)  /* 5 minutes */

typedef struct {
    otIp6Address ip6_addr;          /**< Key: sender mesh-local IPv6 */
    bool valid;
    uint8_t ext_addr[8];           /**< Extended address (IID from IPv6) */
    char mac[18];                   /**< "AA:BB:CC:DD:EE:FF" */
    char unit_id[24];
    char device_type[20];
    char fw_version[16];
    uint32_t last_seen_ms;
} device_cache_entry_t;

static device_cache_entry_t s_device_cache[MAX_REGISTERED_DEVICES];

/*******************************************************************************
 * Re-register Nudge Infrastructure
 ******************************************************************************/

#define NUDGE_QUEUE_DEPTH       4
#define NUDGE_COOLDOWN_MS       (60 * 1000)  /* 1 minute per device */
#define NUDGE_MAX_TRACKED       8
#define NUDGE_TASK_STACK        3072
#define NUDGE_TASK_PRIORITY     5

typedef struct {
    uint8_t ext_addr[8];
    uint32_t last_nudge_ms;
} nudge_tracking_t;

static QueueHandle_t s_nudge_queue = NULL;
static TaskHandle_t s_nudge_task = NULL;
static nudge_tracking_t s_nudge_tracking[NUDGE_MAX_TRACKED];

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void inventory_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info);
static void heartbeat_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info);
static void config_handler(void *context, otMessage *message,
                           const otMessageInfo *message_info);
static void register_handler(void *context, otMessage *message,
                             const otMessageInfo *message_info);
static void default_handler(void *context, otMessage *message,
                            const otMessageInfo *message_info);
static void send_coap_response(otMessage *request,
                               const otMessageInfo *request_info,
                               otCoapCode code,
                               const void *payload, uint16_t payload_len);
static void send_coap_response_cbor(otMessage *request,
                                     const otMessageInfo *request_info,
                                     otCoapCode code,
                                     const void *cbor_payload, uint16_t cbor_len);
static void log_unicast_addresses(otInstance *instance);

/* Registration cache helpers */
static device_cache_entry_t *cache_lookup(const otIp6Address *addr);
static device_cache_entry_t *cache_upsert(const otIp6Address *addr,
                                           const uint8_t *ext_addr);
static void cache_evict_stale(void);

/* Re-register nudge */
static void queue_reregister_nudge(const uint8_t *ext_addr);
static void reregister_nudge_task(void *arg);

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
    memset(&s_register_resource, 0, sizeof(s_register_resource));

    /* Clear registration cache */
    memset(s_device_cache, 0, sizeof(s_device_cache));

    /* Initialize re-register nudge infrastructure */
    memset(s_nudge_tracking, 0, sizeof(s_nudge_tracking));
    if (s_nudge_queue == NULL) {
        s_nudge_queue = xQueueCreate(NUDGE_QUEUE_DEPTH, 8);  /* 8 bytes per ext_addr */
    }
    if (s_nudge_task == NULL) {
        coap_cmd_client_init();
        xTaskCreate(reregister_nudge_task, "nudge", NUDGE_TASK_STACK,
                    NULL, NUDGE_TASK_PRIORITY, &s_nudge_task);
    }

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

    /* Configure register resource */
    s_register_resource.mUriPath = "register";
    s_register_resource.mHandler = register_handler;
    s_register_resource.mContext = NULL;

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
    otCoapAddResource(instance, &s_register_resource);

    /* Set default handler for unmatched URIs (diagnostic) */
    otCoapSetDefaultHandler(instance, default_handler, NULL);

    /* Log addresses for debugging */
    log_unicast_addresses(instance);

    esp_openthread_lock_release();

    s_running = true;
    ESP_LOGI(TAG, "CoAP server started on port %d", COAP_DEFAULT_PORT);
    ESP_LOGI(TAG, "  - POST /inventory");
    ESP_LOGI(TAG, "  - POST /heartbeat");
    ESP_LOGI(TAG, "  - POST /register");
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
        otCoapRemoveResource(instance, &s_register_resource);

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

    /* Clean up nudge infrastructure */
    if (s_nudge_task != NULL) {
        vTaskDelete(s_nudge_task);
        s_nudge_task = NULL;
    }
    if (s_nudge_queue != NULL) {
        vQueueDelete(s_nudge_queue);
        s_nudge_queue = NULL;
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
 * Re-register Nudge Implementation
 ******************************************************************************/

/* Forward declaration — defined in Registration Cache section below */
static uint32_t get_uptime_ms(void);

/**
 * @brief Queue a re-register nudge for an unregistered device
 *
 * Rate-limited to one nudge per device per NUDGE_COOLDOWN_MS.
 * Non-blocking — drops silently if queue is full.
 */
static void queue_reregister_nudge(const uint8_t *ext_addr)
{
    if (s_nudge_queue == NULL) return;

    uint32_t now = get_uptime_ms();

    /* Check cooldown — skip if we nudged this device recently */
    for (int i = 0; i < NUDGE_MAX_TRACKED; i++) {
        if (memcmp(s_nudge_tracking[i].ext_addr, ext_addr, 8) == 0) {
            if ((now - s_nudge_tracking[i].last_nudge_ms) < NUDGE_COOLDOWN_MS) {
                return;  /* Still in cooldown */
            }
            /* Update timestamp and enqueue */
            s_nudge_tracking[i].last_nudge_ms = now;
            xQueueSend(s_nudge_queue, ext_addr, 0);
            return;
        }
    }

    /* Not tracked yet — find empty or oldest slot */
    int slot = 0;
    uint32_t oldest = UINT32_MAX;
    for (int i = 0; i < NUDGE_MAX_TRACKED; i++) {
        if (s_nudge_tracking[i].last_nudge_ms == 0) {
            slot = i;
            break;
        }
        if (s_nudge_tracking[i].last_nudge_ms < oldest) {
            oldest = s_nudge_tracking[i].last_nudge_ms;
            slot = i;
        }
    }

    memcpy(s_nudge_tracking[slot].ext_addr, ext_addr, 8);
    s_nudge_tracking[slot].last_nudge_ms = now;
    xQueueSend(s_nudge_queue, ext_addr, 0);
}

/**
 * @brief FreeRTOS task that sends re-register nudges via CoAP POST /cmd
 *
 * Dequeues ext_addr items and sends {"id":"...","cmd":"register"} via
 * coap_cmd_client_send(). This runs on a separate task because the send
 * blocks for up to 5 seconds waiting for a CoAP response.
 */
static void reregister_nudge_task(void *arg)
{
    uint8_t ext_addr[8];

    while (true) {
        if (xQueueReceive(s_nudge_queue, ext_addr, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        ESP_LOGI(TAG, "Sending re-register nudge to %02X%02X%02X%02X%02X%02X%02X%02X",
                 ext_addr[0], ext_addr[1], ext_addr[2], ext_addr[3],
                 ext_addr[4], ext_addr[5], ext_addr[6], ext_addr[7]);

        /* CBOR-encode: {"id":"00000000-0000-0000-0000-000000000000","cmd":"register"} */
        uint8_t cbor_buf[80];
        CborEncoder encoder, map_enc;
        cbor_encoder_init(&encoder, cbor_buf, sizeof(cbor_buf), 0);
        cbor_encoder_create_map(&encoder, &map_enc, 2);

        cbor_encode_text_stringz(&map_enc, "id");
        cbor_encode_text_stringz(&map_enc, "00000000-0000-0000-0000-000000000000");

        cbor_encode_text_stringz(&map_enc, "cmd");
        cbor_encode_text_stringz(&map_enc, "register");

        cbor_encoder_close_container(&encoder, &map_enc);
        size_t cbor_len = cbor_encoder_get_buffer_size(&encoder, cbor_buf);

        esp_err_t err = coap_cmd_client_send(ext_addr, cbor_buf, (uint16_t)cbor_len);
        if (err == ESP_OK) {
            ESP_LOGI(TAG, "Re-register nudge acknowledged");
        } else if (err == ESP_ERR_TIMEOUT) {
            ESP_LOGW(TAG, "Re-register nudge timed out (node may not support it yet)");
        } else {
            ESP_LOGW(TAG, "Re-register nudge failed: %s", esp_err_to_name(err));
        }
    }
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

/*******************************************************************************
 * Registration Cache Implementation
 ******************************************************************************/

static uint32_t get_uptime_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static device_cache_entry_t *cache_lookup(const otIp6Address *addr)
{
    uint32_t now = get_uptime_ms();
    for (int i = 0; i < MAX_REGISTERED_DEVICES; i++) {
        if (!s_device_cache[i].valid) continue;
        if (memcmp(&s_device_cache[i].ip6_addr, addr, sizeof(otIp6Address)) == 0) {
            /* Check expiry */
            if ((now - s_device_cache[i].last_seen_ms) > CACHE_EXPIRY_MS) {
                s_device_cache[i].valid = false;
                return NULL;
            }
            return &s_device_cache[i];
        }
    }
    return NULL;
}

static device_cache_entry_t *cache_upsert(const otIp6Address *addr,
                                           const uint8_t *ext_addr)
{
    /* Check for existing entry */
    for (int i = 0; i < MAX_REGISTERED_DEVICES; i++) {
        if (s_device_cache[i].valid &&
            memcmp(&s_device_cache[i].ip6_addr, addr, sizeof(otIp6Address)) == 0) {
            s_device_cache[i].last_seen_ms = get_uptime_ms();
            return &s_device_cache[i];
        }
    }

    /* Evict stale entries first */
    cache_evict_stale();

    /* Find empty slot */
    for (int i = 0; i < MAX_REGISTERED_DEVICES; i++) {
        if (!s_device_cache[i].valid) {
            memset(&s_device_cache[i], 0, sizeof(device_cache_entry_t));
            s_device_cache[i].valid = true;
            memcpy(&s_device_cache[i].ip6_addr, addr, sizeof(otIp6Address));
            memcpy(s_device_cache[i].ext_addr, ext_addr, 8);
            s_device_cache[i].last_seen_ms = get_uptime_ms();
            return &s_device_cache[i];
        }
    }

    /* Cache full — evict oldest */
    int oldest_idx = 0;
    uint32_t oldest_time = UINT32_MAX;
    for (int i = 0; i < MAX_REGISTERED_DEVICES; i++) {
        if (s_device_cache[i].last_seen_ms < oldest_time) {
            oldest_time = s_device_cache[i].last_seen_ms;
            oldest_idx = i;
        }
    }

    ESP_LOGW(TAG, "Registration cache full, evicting oldest entry");
    memset(&s_device_cache[oldest_idx], 0, sizeof(device_cache_entry_t));
    s_device_cache[oldest_idx].valid = true;
    memcpy(&s_device_cache[oldest_idx].ip6_addr, addr, sizeof(otIp6Address));
    memcpy(s_device_cache[oldest_idx].ext_addr, ext_addr, 8);
    s_device_cache[oldest_idx].last_seen_ms = get_uptime_ms();
    return &s_device_cache[oldest_idx];
}

static void cache_evict_stale(void)
{
    uint32_t now = get_uptime_ms();
    for (int i = 0; i < MAX_REGISTERED_DEVICES; i++) {
        if (s_device_cache[i].valid &&
            (now - s_device_cache[i].last_seen_ms) > CACHE_EXPIRY_MS) {
            ESP_LOGD(TAG, "Evicting stale cache entry %d", i);
            s_device_cache[i].valid = false;
        }
    }
}

/*******************************************************************************
 * CBOR Helper: extract text string from map by key
 ******************************************************************************/

/**
 * @brief Find a text string value in a CBOR map by key name.
 * @return true if found and copied, false otherwise.
 */
static bool cbor_map_find_text(CborValue *map, const char *key,
                                char *out, size_t out_size)
{
    CborValue element;
    CborError err = cbor_value_map_find_value(map, key, &element);
    if (err != CborNoError || !cbor_value_is_text_string(&element)) {
        return false;
    }
    size_t len = out_size - 1;
    err = cbor_value_copy_text_string(&element, out, &len, NULL);
    if (err != CborNoError) {
        return false;
    }
    out[len] = '\0';
    return true;
}

/*******************************************************************************
 * Register Handler
 ******************************************************************************/

/**
 * @brief Handle POST /register
 *
 * CBOR payload:
 *   { "v": uint, "mac": tstr, "unit_id": tstr, "type": tstr, "fw": tstr }
 *
 * Response: 2.01 Created (new) or 2.04 Changed (existing)
 */
static void register_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info)
{
    ESP_LOGI(TAG, "Register request received");

    otCoapCode code = otCoapMessageGetCode(message);
    if (code != OT_COAP_CODE_POST) {
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

    if (length < 5 || length > 512) {
        ESP_LOGW(TAG, "Register: invalid payload length %d", length);
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        return;
    }

    uint8_t payload[512];
    if (otMessageRead(message, offset, payload, length) != length) {
        ESP_LOGW(TAG, "Register: failed to read payload");
        send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                           NULL, 0);
        return;
    }

    /* Parse CBOR */
    CborParser parser;
    CborValue root;
    CborError err = cbor_parser_init(payload, length, 0, &parser, &root);
    if (err != CborNoError || !cbor_value_is_map(&root)) {
        ESP_LOGW(TAG, "Register: invalid CBOR (not a map)");
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        return;
    }

    /* Extract required fields */
    char mac[18] = {0};
    char unit_id[24] = {0};
    char device_type[20] = {0};
    char fw_version[16] = {0};

    if (!cbor_map_find_text(&root, "mac", mac, sizeof(mac)) ||
        !cbor_map_find_text(&root, "unit_id", unit_id, sizeof(unit_id)) ||
        !cbor_map_find_text(&root, "type", device_type, sizeof(device_type)) ||
        !cbor_map_find_text(&root, "fw", fw_version, sizeof(fw_version))) {
        ESP_LOGW(TAG, "Register: missing required fields");
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        return;
    }

    /* Check if already registered (for response code) */
    bool is_new = (cache_lookup(&message_info->mPeerAddr) == NULL);

    /* Upsert into cache */
    device_cache_entry_t *entry = cache_upsert(&message_info->mPeerAddr, ext_addr);
    if (entry == NULL) {
        ESP_LOGE(TAG, "Register: cache upsert failed");
        send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                           NULL, 0);
        return;
    }

    strncpy(entry->mac, mac, sizeof(entry->mac) - 1);
    strncpy(entry->unit_id, unit_id, sizeof(entry->unit_id) - 1);
    strncpy(entry->device_type, device_type, sizeof(entry->device_type) - 1);
    strncpy(entry->fw_version, fw_version, sizeof(entry->fw_version) - 1);

    ESP_LOGI(TAG, "Device %s: mac=%s, unit=%s, type=%s, fw=%s",
             is_new ? "registered" : "updated",
             mac, unit_id, device_type, fw_version);

    /* Post event for local handling and S3 forwarding */
    coap_register_event_t event = {0};
    memcpy(event.crate_ext_addr, ext_addr, 8);
    strncpy(event.mac, mac, sizeof(event.mac) - 1);
    strncpy(event.unit_id, unit_id, sizeof(event.unit_id) - 1);
    strncpy(event.device_type, device_type, sizeof(event.device_type) - 1);
    strncpy(event.fw_version, fw_version, sizeof(event.fw_version) - 1);
    esp_event_post(COAP_SERVER_EVENTS, COAP_SERVER_EVENT_REGISTER,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /* Build CBOR response: {"status": "ok"} */
    uint8_t rsp_buf[32];
    CborEncoder encoder, map_encoder;
    cbor_encoder_init(&encoder, rsp_buf, sizeof(rsp_buf), 0);
    cbor_encoder_create_map(&encoder, &map_encoder, 1);
    cbor_encode_text_stringz(&map_encoder, "status");
    cbor_encode_text_stringz(&map_encoder, "ok");
    cbor_encoder_close_container(&encoder, &map_encoder);
    size_t rsp_len = cbor_encoder_get_buffer_size(&encoder, rsp_buf);

    /* 2.01 Created for new, 2.04 Changed for existing — with Content-Format: CBOR */
    otCoapCode rsp_code = is_new ? OT_COAP_CODE_CREATED : OT_COAP_CODE_CHANGED;
    send_coap_response_cbor(message, message_info, rsp_code, rsp_buf, rsp_len);
}

/*******************************************************************************
 * Inventory Handler
 ******************************************************************************/

/**
 * @brief Handle POST /inventory
 *
 * Supports two formats:
 * - CBOR: {"epcs": [bstr .size 12, ...]}
 * - Legacy binary: [count][N×12B EPCs] — detected by first byte looking like
 *   a valid count and total length matching [1 + count*12]
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

    uint8_t payload[1024];
    if (length > sizeof(payload)) {
        ESP_LOGW(TAG, "Inventory: payload too large (%d bytes)", length);
        send_coap_response(message, message_info, OT_COAP_CODE_REQUEST_TOO_LARGE,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    if (otMessageRead(message, offset, payload, length) != length) {
        ESP_LOGW(TAG, "Inventory: failed to read payload");
        send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    /* Determine format: legacy binary vs CBOR */
    uint8_t epc_count = 0;
    uint8_t epcs[COAP_MAX_EPCS_PER_UPDATE][COAP_EPC_LENGTH];
    memset(epcs, 0, sizeof(epcs));

    /* Legacy detection: first byte is count, total = 1 + count*12 */
    bool is_legacy = false;
    if (length >= 1) {
        uint8_t candidate_count = payload[0];
        uint16_t expected_len = 1 + (uint16_t)candidate_count * COAP_EPC_LENGTH;
        if (candidate_count <= COAP_MAX_EPCS_PER_UPDATE && length == expected_len) {
            is_legacy = true;
        }
    }

    if (is_legacy) {
        /* Legacy binary path */
        epc_count = payload[0];
        if (epc_count > COAP_MAX_EPCS_PER_UPDATE) {
            epc_count = COAP_MAX_EPCS_PER_UPDATE;
        }
        if (epc_count > 0) {
            memcpy(epcs, &payload[1], epc_count * COAP_EPC_LENGTH);
        }
        ESP_LOGI(TAG, "Inventory (legacy) from rloc16=0x%04X: %d EPCs", rloc16, epc_count);
    } else {
        /* CBOR path: {"epcs": [bstr, ...]} */
        CborParser parser;
        CborValue root;
        CborError err = cbor_parser_init(payload, length, 0, &parser, &root);
        if (err != CborNoError || !cbor_value_is_map(&root)) {
            ESP_LOGW(TAG, "Inventory: invalid CBOR (not a map)");
            send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                               NULL, 0);
            s_stats.errors++;
            return;
        }

        /* Find "epcs" array */
        CborValue epcs_val;
        err = cbor_value_map_find_value(&root, "epcs", &epcs_val);
        if (err != CborNoError || !cbor_value_is_array(&epcs_val)) {
            ESP_LOGW(TAG, "Inventory: missing or invalid 'epcs' array");
            send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                               NULL, 0);
            s_stats.errors++;
            return;
        }

        /* Iterate bstr array */
        CborValue arr_iter;
        err = cbor_value_enter_container(&epcs_val, &arr_iter);
        if (err != CborNoError) {
            ESP_LOGW(TAG, "Inventory: failed to enter epcs array");
            send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                               NULL, 0);
            s_stats.errors++;
            return;
        }

        while (!cbor_value_at_end(&arr_iter) && epc_count < COAP_MAX_EPCS_PER_UPDATE) {
            if (!cbor_value_is_byte_string(&arr_iter)) {
                cbor_value_advance(&arr_iter);
                continue;
            }
            size_t bstr_len = COAP_EPC_LENGTH;
            err = cbor_value_copy_byte_string(&arr_iter, epcs[epc_count],
                                               &bstr_len, NULL);
            if (err == CborNoError && bstr_len == COAP_EPC_LENGTH) {
                epc_count++;
            }
            cbor_value_advance(&arr_iter);
        }

        ESP_LOGI(TAG, "Inventory (CBOR) from rloc16=0x%04X: %d EPCs", rloc16, epc_count);
    }

    /* Forward to S3 via UART */
    const uint8_t (*epcs_ptr)[12] = epc_count > 0 ? (const uint8_t (*)[12])epcs : NULL;
    esp_err_t ret = s3_comm_send_inventory_update(ext_addr, epcs_ptr, epc_count);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to forward inventory to S3: %s",
                 esp_err_to_name(ret));
    }

    /* Post event for local handling */
    coap_inventory_event_t event = {
        .crate_rloc16 = rloc16,
        .epc_count = epc_count,
    };
    memcpy(event.crate_ext_addr, ext_addr, 8);
    if (epc_count > 0) {
        memcpy(event.epcs, epcs, epc_count * COAP_EPC_LENGTH);
    }
    esp_event_post(COAP_SERVER_EVENTS, COAP_SERVER_EVENT_INVENTORY_UPDATE,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /* Send success response */
    send_coap_response(message, message_info, OT_COAP_CODE_CHANGED, NULL, 0);
}

/**
 * @brief Handle POST /heartbeat
 *
 * Supports two formats:
 * - Legacy binary (3 bytes): [battery_percent][rssi][tag_count]
 * - CBOR (>3 bytes): Full telemetry map per CoAP Mesh Protocol spec
 *
 * CBOR heartbeats are forwarded as raw blobs to S3 via telemetry event.
 * Legacy heartbeats use the existing fixed-field forwarding.
 */
static void heartbeat_handler(void *context, otMessage *message,
                              const otMessageInfo *message_info)
{
    ESP_LOGI(TAG, "Heartbeat request received");
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

    if (length == 0) {
        ESP_LOGW(TAG, "Heartbeat: empty payload");
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    /* Legacy binary path: exactly 3 bytes */
    if (length == 3) {
        uint8_t payload[3];
        if (otMessageRead(message, offset, payload, 3) != 3) {
            send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                               NULL, 0);
            s_stats.errors++;
            return;
        }

        uint8_t battery_percent = payload[0];
        int8_t rssi = (int8_t)payload[1];
        uint8_t tag_count = payload[2];

        ESP_LOGI(TAG, "Heartbeat (legacy) from rloc16=0x%04X: batt=%d%%, rssi=%ddBm, tags=%d",
                 rloc16, battery_percent, rssi, tag_count);

        /* Forward via legacy path */
        esp_err_t ret = s3_comm_send_crate_heartbeat(ext_addr, battery_percent, rssi);
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to forward heartbeat to S3: %s",
                     esp_err_to_name(ret));
        }

        /* Post local event */
        coap_heartbeat_event_t event = {
            .crate_rloc16 = rloc16,
            .battery_percent = battery_percent,
            .rssi = rssi,
            .tag_count = tag_count,
        };
        memcpy(event.crate_ext_addr, ext_addr, 8);
        esp_event_post(COAP_SERVER_EVENTS, COAP_SERVER_EVENT_HEARTBEAT,
                       &event, sizeof(event), pdMS_TO_TICKS(100));

        send_coap_response(message, message_info, OT_COAP_CODE_CHANGED, NULL, 0);
        return;
    }

    /* CBOR path: >3 bytes */
    uint8_t payload[1024];
    if (length > sizeof(payload)) {
        ESP_LOGW(TAG, "Heartbeat: payload too large (%d bytes)", length);
        send_coap_response(message, message_info, OT_COAP_CODE_REQUEST_TOO_LARGE,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    if (otMessageRead(message, offset, payload, length) != length) {
        send_coap_response(message, message_info, OT_COAP_CODE_INTERNAL_ERROR,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    /* Check registration — update last_seen if registered */
    bool is_unregistered = false;
    device_cache_entry_t *cached = cache_lookup(&message_info->mPeerAddr);
    if (cached != NULL) {
        cached->last_seen_ms = get_uptime_ms();
    } else {
        /* Auto-accept: create partial cache entry so telemetry flows to S3.
         * Still send 4.01 after forwarding so future crate firmware can
         * re-register, and queue a re-register nudge (Part 2). */
        ESP_LOGW(TAG, "Heartbeat from unregistered device rloc16=0x%04X — auto-accepting (partial cache)",
                 rloc16);
        cached = cache_upsert(&message_info->mPeerAddr, ext_addr);
        if (cached != NULL) {
            strncpy(cached->mac, "unknown", sizeof(cached->mac) - 1);
            strncpy(cached->unit_id, "unknown", sizeof(cached->unit_id) - 1);
            strncpy(cached->device_type, "unknown", sizeof(cached->device_type) - 1);
            strncpy(cached->fw_version, "unknown", sizeof(cached->fw_version) - 1);
        }
        is_unregistered = true;
        s_stats.unregistered_heartbeats++;
    }

    /* Parse CBOR to extract heartbeat type */
    CborParser parser;
    CborValue root;
    CborError err = cbor_parser_init(payload, length, 0, &parser, &root);
    if (err != CborNoError || !cbor_value_is_map(&root)) {
        ESP_LOGW(TAG, "Heartbeat: invalid CBOR");
        send_coap_response(message, message_info, OT_COAP_CODE_BAD_REQUEST,
                           NULL, 0);
        s_stats.errors++;
        return;
    }

    /* Extract "type" field to determine heartbeat type */
    char type_str[20] = {0};
    uint8_t hb_type = S3H2_HB_TYPE_STATUS;
    if (cbor_map_find_text(&root, "type", type_str, sizeof(type_str))) {
        if (strcmp(type_str, "command_ack") == 0) {
            hb_type = S3H2_HB_TYPE_COMMAND_ACK;
        } else if (strcmp(type_str, "command_result") == 0) {
            hb_type = S3H2_HB_TYPE_COMMAND_RESULT;
        }
    }

    ESP_LOGI(TAG, "Heartbeat (CBOR) from rloc16=0x%04X: type=%s, %d bytes",
             rloc16, type_str[0] ? type_str : "status", length);

    /* Forward raw CBOR blob to S3 via telemetry event */
    esp_err_t ret = s3_comm_send_crate_telemetry(ext_addr, hb_type, payload, length);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to forward telemetry to S3: %s",
                 esp_err_to_name(ret));
    }

    /* Send 4.01 for unregistered devices (signals "re-register required"),
     * 2.04 for registered devices */
    if (is_unregistered) {
        send_coap_response(message, message_info, OT_COAP_CODE_UNAUTHORIZED, NULL, 0);
        queue_reregister_nudge(ext_addr);
    } else {
        send_coap_response(message, message_info, OT_COAP_CODE_CHANGED, NULL, 0);
    }
}

/**
 * @brief Handle GET /config (DEPRECATED)
 *
 * Returns crate configuration as simple JSON.
 * This endpoint is deprecated — nodes should use /register + heartbeat
 * telemetry for config negotiation. Kept for backward compatibility.
 */
static void config_handler(void *context, otMessage *message,
                           const otMessageInfo *message_info)
{
    ESP_LOGW(TAG, "Config request received (DEPRECATED endpoint)");
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

/**
 * @brief Send CoAP response with Content-Format: 60 (CBOR)
 */
#define COAP_CONTENT_FORMAT_CBOR  60

static void send_coap_response_cbor(otMessage *request,
                                     const otMessageInfo *request_info,
                                     otCoapCode code,
                                     const void *cbor_payload, uint16_t cbor_len)
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

    if (cbor_payload != NULL && cbor_len > 0) {
        /* Add Content-Format: 60 (application/cbor) */
        error = otCoapMessageAppendContentFormatOption(response, COAP_CONTENT_FORMAT_CBOR);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to append Content-Format: %d", error);
            otMessageFree(response);
            return;
        }

        error = otCoapMessageSetPayloadMarker(response);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to set payload marker: %d", error);
            otMessageFree(response);
            return;
        }

        error = otMessageAppend(response, cbor_payload, cbor_len);
        if (error != OT_ERROR_NONE) {
            ESP_LOGE(TAG, "Failed to append CBOR payload: %d", error);
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
 * Default Handler (diagnostic)
 ******************************************************************************/

/**
 * @brief Default handler for unmatched CoAP URIs
 *
 * Catches any CoAP request that doesn't match a registered resource.
 * Logs the URI path and sender info for debugging.
 */
static void default_handler(void *context, otMessage *message,
                            const otMessageInfo *message_info)
{
    otCoapCode code = otCoapMessageGetCode(message);
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;

    /* Log peer address */
    char addr_str[40];
    otIp6AddressToString(&message_info->mPeerAddr, addr_str, sizeof(addr_str));

    ESP_LOGW(TAG, "Unmatched CoAP request: code=%d.%02d, payload_len=%d, from=[%s]:%d",
             (code >> 5) & 0x7, code & 0x1f, length,
             addr_str, message_info->mPeerPort);

    /* Extract URI-Path options using iterator */
    otCoapOptionIterator iter;
    if (otCoapOptionIteratorInit(&iter, message) == OT_ERROR_NONE) {
        const otCoapOption *option = otCoapOptionIteratorGetFirstOptionMatching(
            &iter, OT_COAP_OPTION_URI_PATH);
        while (option != NULL) {
            char uri_segment[64];
            if (option->mLength < sizeof(uri_segment)) {
                if (otCoapOptionIteratorGetOptionValue(&iter, uri_segment) == OT_ERROR_NONE) {
                    uri_segment[option->mLength] = '\0';
                    ESP_LOGW(TAG, "  URI-Path segment: '%s'", uri_segment);
                }
            }
            option = otCoapOptionIteratorGetNextOptionMatching(&iter, OT_COAP_OPTION_URI_PATH);
        }
    }

    /* Send 4.04 Not Found */
    send_coap_response(message, message_info, OT_COAP_CODE_NOT_FOUND, NULL, 0);
}

/**
 * @brief Log all unicast addresses on the OpenThread interface
 *
 * Must be called with the OpenThread lock held.
 */
static void log_unicast_addresses(otInstance *instance)
{
    ESP_LOGI(TAG, "H2 unicast addresses:");
    const otNetifAddress *addr = otIp6GetUnicastAddresses(instance);
    while (addr != NULL) {
        char addr_str[40];
        otIp6AddressToString(&addr->mAddress, addr_str, sizeof(addr_str));
        ESP_LOGI(TAG, "  %s/%d%s", addr_str, addr->mPrefixLength,
                 addr->mRloc ? " (RLOC)" : "");
        addr = addr->mNext;
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
