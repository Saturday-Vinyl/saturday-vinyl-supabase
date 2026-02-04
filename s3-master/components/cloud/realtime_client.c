/**
 * @file realtime_client.c
 * @brief Supabase Realtime WebSocket client implementation
 *
 * Connects to Supabase Realtime using Phoenix channel protocol over WebSocket.
 * Receives push notifications for OTA updates and device commands.
 *
 * OTA Push Protocol Implementation (Phase 2)
 */

#include "realtime_client.h"
#include "supabase_client.h"
#include "ota_manager.h"
#include "crate_ota.h"
#include "app_config.h"
#include "wifi_manager.h"
#include "esp_log.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "esp_websocket_client.h"
#include "esp_crt_bundle.h"
#include "esp_mac.h"
#include "esp_heap_caps.h"
#include "cJSON.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "REALTIME";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(REALTIME_EVENTS);

/*******************************************************************************
 * Constants
 ******************************************************************************/

#define REALTIME_TASK_STACK_SIZE    8192
#define REALTIME_TASK_PRIORITY      5
#define MAX_MESSAGE_SIZE            4096
#define WEBSOCKET_BUFFER_SIZE       4096
#define MAX_URL_SIZE                512  /* Must fit: wss://host/realtime/v1/websocket?apikey={256-char JWT}&vsn=1.0.0 */
#define RECONNECT_MAX_DELAY_MS      60000
#define HEARTBEAT_TIMEOUT_MS        45000

/* Phoenix channel protocol events */
#define PHX_EVENT_JOIN              "phx_join"
#define PHX_EVENT_REPLY             "phx_reply"
#define PHX_EVENT_HEARTBEAT         "heartbeat"
#define PHX_EVENT_CLOSE             "phx_close"
#define PHX_EVENT_ERROR             "phx_error"
#define PHX_EVENT_BROADCAST         "broadcast"
#define PHX_EVENT_POSTGRES_CHANGES  "postgres_changes"

/* Custom event types from server */
#define EVENT_UPDATE_AVAILABLE      "update_available"
#define EVENT_COMMAND               "command"
#define EVENT_CONFIG_UPDATE         "config_update"

/* Command acknowledgement heartbeat buffer size
 * Must fit all standard heartbeat fields plus command-specific fields */
#define MAX_CMD_HEARTBEAT_SIZE      1024

/*******************************************************************************
 * Module State
 ******************************************************************************/

typedef enum {
    RT_STATE_IDLE,
    RT_STATE_CONNECTING,
    RT_STATE_CONNECTED,
    RT_STATE_SUBSCRIBING,
    RT_STATE_SUBSCRIBED,
    RT_STATE_DISCONNECTING,
} realtime_state_t;

typedef struct {
    bool initialized;
    realtime_config_t config;
    realtime_state_t state;
    esp_websocket_client_handle_t ws_client;
    char channel_topic[128];        /* "realtime:public:device_commands" */
    char device_mac[18];            /* MAC address with dashes for filtering */
    uint32_t msg_ref;               /* Phoenix message reference counter */
    char join_ref[16];              /* Join reference for channel */

    /* Statistics */
    realtime_status_t stats;

    /* Reconnection handling */
    uint32_t reconnect_delay_ms;
    esp_timer_handle_t reconnect_timer;

    /* Heartbeat handling */
    esp_timer_handle_t heartbeat_timer;
    int64_t last_pong_time;

    /* Synchronization */
    SemaphoreHandle_t mutex;
} realtime_state_struct_t;

static realtime_state_struct_t s_rt = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void websocket_event_handler(void *handler_args, esp_event_base_t base,
                                    int32_t event_id, void *event_data);
static void handle_websocket_data(const char *data, int len);
static void handle_phoenix_message(cJSON *msg);
static void handle_postgres_changes(const cJSON *payload);
static void handle_update_available(const cJSON *payload, const char *request_id);
static void handle_command(const cJSON *payload);
static void handle_config_update(const cJSON *payload);
static void send_phoenix_join(void);
static void send_phoenix_heartbeat(void *arg);
static void reconnect_timer_callback(void *arg);
static esp_err_t build_websocket_url(char *url, size_t max_len);
static void get_mac_address_dashed(char *mac_str, size_t len);
static void get_mac_address_colon(char *mac_str, size_t len);
static esp_err_t send_command_ack_heartbeat(const char *command_id);
static esp_err_t send_command_result_heartbeat(const char *command_id, bool success,
                                                const cJSON *result, const char *error_message);

/*******************************************************************************
 * MAC Address Helper
 ******************************************************************************/

/**
 * @brief Get MAC address formatted with dashes for channel subscription
 *
 * Per Device Command Protocol, devices subscribe to channel "device:{mac_address}"
 * where mac_address has colons replaced with dashes (e.g., "AA-BB-CC-DD-EE-FF").
 */
static void get_mac_address_dashed(char *mac_str, size_t len)
{
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK && len >= 18) {
        snprintf(mac_str, len, "%02X-%02X-%02X-%02X-%02X-%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    } else {
        strncpy(mac_str, "00-00-00-00-00-00", len);
    }
}

/**
 * @brief Get MAC address formatted with colons for heartbeat payloads
 *
 * Per Device Command Protocol v1.2.4, heartbeats use mac_address with colons
 * (e.g., "AA:BB:CC:DD:EE:FF") as the primary device identifier.
 */
static void get_mac_address_colon(char *mac_str, size_t len)
{
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK && len >= 18) {
        snprintf(mac_str, len, "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    } else {
        strncpy(mac_str, "00:00:00:00:00:00", len);
    }
}

/*******************************************************************************
 * Command Acknowledgement Protocol (v1.2.4)
 *
 * Per Device Command Protocol v1.2.4, command acknowledgements are sent as
 * heartbeats to the device_heartbeats table with special type fields:
 * - type: "command_ack" - Immediately on command receipt
 * - type: "command_result" - After command execution completes
 *
 * A database trigger automatically updates device_commands.status based on
 * these heartbeat types.
 ******************************************************************************/

/**
 * @brief Build standard heartbeat fields into a cJSON object
 *
 * Adds all required fields per Device Command Protocol v1.2.4:
 * - mac_address, unit_id, device_type, firmware_version
 * - uptime_sec, free_heap, min_free_heap, largest_free_block
 * - wifi_rssi (capability field)
 */
static void build_standard_heartbeat_fields(cJSON *heartbeat)
{
    /* MAC address as primary identifier */
    char mac_str[18];
    get_mac_address_colon(mac_str, sizeof(mac_str));
    cJSON_AddStringToObject(heartbeat, "mac_address", mac_str);

    /* Unit ID (serial number) from Supabase config */
    char unit_id[SUPABASE_UNIT_ID_MAX_LEN] = "";
    supabase_get_unit_id(unit_id, sizeof(unit_id));
    cJSON_AddStringToObject(heartbeat, "unit_id", unit_id);

    /* Device type and firmware version from compile-time constants */
    cJSON_AddStringToObject(heartbeat, "device_type", DEVICE_TYPE);
    cJSON_AddStringToObject(heartbeat, "firmware_version", FW_VERSION_STRING);

    /* System metrics */
    uint32_t uptime_sec = (uint32_t)(esp_timer_get_time() / 1000000);
    uint32_t free_heap = (uint32_t)esp_get_free_heap_size();
    uint32_t min_free_heap = (uint32_t)esp_get_minimum_free_heap_size();
    uint32_t largest_free_block = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);

    cJSON_AddNumberToObject(heartbeat, "uptime_sec", uptime_sec);
    cJSON_AddNumberToObject(heartbeat, "free_heap", free_heap);
    cJSON_AddNumberToObject(heartbeat, "min_free_heap", min_free_heap);
    cJSON_AddNumberToObject(heartbeat, "largest_free_block", largest_free_block);

    /* WiFi capability heartbeat field */
    int8_t wifi_rssi = 0;
    wifi_manager_status_t wifi_status;
    if (wifi_get_status(&wifi_status) == ESP_OK) {
        wifi_rssi = wifi_status.rssi;
    }
    cJSON_AddNumberToObject(heartbeat, "wifi_rssi", wifi_rssi);
}

/**
 * @brief Send command acknowledgement heartbeat
 *
 * Per Device Command Protocol v1.2.4, devices must immediately send a
 * command_ack heartbeat when they receive a command via WebSocket.
 * This heartbeat includes all standard fields plus:
 * - type: "command_ack"
 * - command_id: UUID of the received command
 *
 * @param command_id UUID of the command being acknowledged
 * @return ESP_OK on success, error code otherwise
 */
static esp_err_t send_command_ack_heartbeat(const char *command_id)
{
    if (command_id == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "Sending command_ack heartbeat for %s", command_id);

    cJSON *heartbeat = cJSON_CreateObject();
    if (heartbeat == NULL) {
        return ESP_ERR_NO_MEM;
    }

    /* Add all standard heartbeat fields */
    build_standard_heartbeat_fields(heartbeat);

    /* Add command acknowledgement fields */
    cJSON_AddStringToObject(heartbeat, "type", "command_ack");
    cJSON_AddStringToObject(heartbeat, "command_id", command_id);

    char *json_str = cJSON_PrintUnformatted(heartbeat);
    cJSON_Delete(heartbeat);

    if (json_str == NULL) {
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGD(TAG, "command_ack payload: %s", json_str);

    supabase_response_t response;
    esp_err_t err = supabase_post("device_heartbeats", json_str, &response, 10000);
    free(json_str);

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGI(TAG, "command_ack heartbeat sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "command_ack POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    } else {
        ESP_LOGW(TAG, "command_ack POST failed: %s", esp_err_to_name(err));
    }
    supabase_response_free(&response);
    return err;
}

/**
 * @brief Send command result heartbeat
 *
 * Per Device Command Protocol v1.2.4, devices must send a command_result
 * heartbeat after command execution completes. This heartbeat includes
 * all standard fields plus:
 * - type: "command_result"
 * - command_id: UUID of the command
 * - heartbeat_data: Object containing:
 *   - status: "completed" or "failed"
 *   - result: Command result data (for successful commands)
 *   - error_message: Error description (for failed commands)
 *
 * @param command_id UUID of the command
 * @param success true if command completed successfully
 * @param result Optional result data (cJSON object, only for success)
 * @param error_message Optional error message (only for failure)
 * @return ESP_OK on success, error code otherwise
 */
static esp_err_t send_command_result_heartbeat(const char *command_id, bool success,
                                                const cJSON *result, const char *error_message)
{
    if (command_id == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "Sending command_result heartbeat for %s: %s",
             command_id, success ? "completed" : "failed");

    cJSON *heartbeat = cJSON_CreateObject();
    if (heartbeat == NULL) {
        return ESP_ERR_NO_MEM;
    }

    /* Add all standard heartbeat fields */
    build_standard_heartbeat_fields(heartbeat);

    /* Add command result fields */
    cJSON_AddStringToObject(heartbeat, "type", "command_result");
    cJSON_AddStringToObject(heartbeat, "command_id", command_id);

    /* Build heartbeat_data object */
    cJSON *heartbeat_data = cJSON_AddObjectToObject(heartbeat, "heartbeat_data");
    cJSON_AddStringToObject(heartbeat_data, "status", success ? "completed" : "failed");

    if (success && result != NULL) {
        cJSON *result_copy = cJSON_Duplicate(result, true);
        if (result_copy != NULL) {
            cJSON_AddItemToObject(heartbeat_data, "result", result_copy);
        }
    }

    if (!success && error_message != NULL) {
        cJSON_AddStringToObject(heartbeat_data, "error_message", error_message);
    }

    char *json_str = cJSON_PrintUnformatted(heartbeat);
    cJSON_Delete(heartbeat);

    if (json_str == NULL) {
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGD(TAG, "command_result payload: %s", json_str);

    supabase_response_t response;
    esp_err_t err = supabase_post("device_heartbeats", json_str, &response, 10000);
    free(json_str);

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGI(TAG, "command_result heartbeat sent successfully");
        supabase_response_free(&response);
        return ESP_OK;
    }

    if (err == ESP_OK) {
        ESP_LOGW(TAG, "command_result POST failed with status %d", response.status_code);
        err = ESP_FAIL;
    } else {
        ESP_LOGW(TAG, "command_result POST failed: %s", esp_err_to_name(err));
    }
    supabase_response_free(&response);
    return err;
}

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t realtime_client_init(const realtime_config_t *config)
{
    if (s_rt.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing Realtime client...");

    memset(&s_rt, 0, sizeof(s_rt));

    /* Apply configuration */
    if (config != NULL) {
        s_rt.config = *config;
    } else {
        realtime_config_t defaults = REALTIME_CONFIG_DEFAULT();
        s_rt.config = defaults;
    }

    /* Create mutex */
    s_rt.mutex = xSemaphoreCreateMutex();
    if (s_rt.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Create reconnect timer */
    esp_timer_create_args_t reconnect_args = {
        .callback = reconnect_timer_callback,
        .name = "rt_reconnect",
    };
    esp_err_t err = esp_timer_create(&reconnect_args, &s_rt.reconnect_timer);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create reconnect timer");
        vSemaphoreDelete(s_rt.mutex);
        return err;
    }

    /* Create heartbeat timer */
    esp_timer_create_args_t heartbeat_args = {
        .callback = send_phoenix_heartbeat,
        .name = "rt_heartbeat",
    };
    err = esp_timer_create(&heartbeat_args, &s_rt.heartbeat_timer);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create heartbeat timer");
        esp_timer_delete(s_rt.reconnect_timer);
        vSemaphoreDelete(s_rt.mutex);
        return err;
    }

    s_rt.state = RT_STATE_IDLE;
    s_rt.reconnect_delay_ms = s_rt.config.reconnect_delay_ms;
    s_rt.initialized = true;
    s_rt.stats.initialized = true;

    ESP_LOGI(TAG, "Realtime client initialized");
    return ESP_OK;
}

esp_err_t realtime_client_deinit(void)
{
    if (!s_rt.initialized) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Deinitializing Realtime client...");

    /* Disconnect if connected */
    realtime_client_disconnect();

    /* Stop and delete timers */
    if (s_rt.heartbeat_timer) {
        esp_timer_stop(s_rt.heartbeat_timer);
        esp_timer_delete(s_rt.heartbeat_timer);
    }
    if (s_rt.reconnect_timer) {
        esp_timer_stop(s_rt.reconnect_timer);
        esp_timer_delete(s_rt.reconnect_timer);
    }

    /* Delete mutex */
    if (s_rt.mutex) {
        vSemaphoreDelete(s_rt.mutex);
    }

    memset(&s_rt, 0, sizeof(s_rt));
    ESP_LOGI(TAG, "Realtime client deinitialized");
    return ESP_OK;
}

/*******************************************************************************
 * Connection Management
 ******************************************************************************/

esp_err_t realtime_client_connect(void)
{
    if (!s_rt.initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_rt.state != RT_STATE_IDLE) {
        ESP_LOGW(TAG, "Already connecting or connected");
        return ESP_OK;
    }

    /* Check Supabase configuration */
    if (!supabase_is_configured()) {
        ESP_LOGE(TAG, "Supabase not configured");
        return ESP_ERR_INVALID_STATE;
    }

    /* Get MAC address for Postgres Changes filter (Device Command Protocol) */
    get_mac_address_dashed(s_rt.device_mac, sizeof(s_rt.device_mac));

    /* Build channel topic for Postgres Changes subscription
     * Format: realtime:{schema}:{table}
     * The filter is specified in the join payload, not the topic
     */
    snprintf(s_rt.channel_topic, sizeof(s_rt.channel_topic),
             "realtime:public:device_commands");
    ESP_LOGI(TAG, "Channel topic: %s (filter: device_mac=%s)",
             s_rt.channel_topic, s_rt.device_mac);

    /* Build WebSocket URL */
    char ws_url[MAX_URL_SIZE];
    esp_err_t err = build_websocket_url(ws_url, sizeof(ws_url));
    if (err != ESP_OK) {
        return err;
    }

    ESP_LOGI(TAG, "Connecting to: %s", ws_url);

    /* Configure WebSocket client */
    esp_websocket_client_config_t ws_cfg = {
        .uri = ws_url,
        .buffer_size = WEBSOCKET_BUFFER_SIZE,
        .task_stack = REALTIME_TASK_STACK_SIZE,
        .task_prio = REALTIME_TASK_PRIORITY,
        .reconnect_timeout_ms = 0,  /* We handle reconnection manually */
        .network_timeout_ms = 30000,
        .ping_interval_sec = 0,     /* We use Phoenix heartbeat instead */
        .crt_bundle_attach = esp_crt_bundle_attach,  /* Use cert bundle for wss:// */
    };

    s_rt.ws_client = esp_websocket_client_init(&ws_cfg);
    if (s_rt.ws_client == NULL) {
        ESP_LOGE(TAG, "Failed to initialize WebSocket client");
        return ESP_FAIL;
    }

    /* Register event handler */
    err = esp_websocket_register_events(s_rt.ws_client, WEBSOCKET_EVENT_ANY,
                                         websocket_event_handler, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register WebSocket events");
        esp_websocket_client_destroy(s_rt.ws_client);
        s_rt.ws_client = NULL;
        return err;
    }

    /* Start connection */
    s_rt.state = RT_STATE_CONNECTING;
    err = esp_websocket_client_start(s_rt.ws_client);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start WebSocket client: %s", esp_err_to_name(err));
        esp_websocket_client_destroy(s_rt.ws_client);
        s_rt.ws_client = NULL;
        s_rt.state = RT_STATE_IDLE;
        return err;
    }

    return ESP_OK;
}

esp_err_t realtime_client_disconnect(void)
{
    if (!s_rt.initialized) {
        return ESP_OK;
    }

    if (s_rt.state == RT_STATE_IDLE) {
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Disconnecting...");

    /* Stop timers */
    esp_timer_stop(s_rt.heartbeat_timer);
    esp_timer_stop(s_rt.reconnect_timer);

    s_rt.state = RT_STATE_DISCONNECTING;

    if (s_rt.ws_client != NULL) {
        esp_websocket_client_stop(s_rt.ws_client);
        esp_websocket_client_destroy(s_rt.ws_client);
        s_rt.ws_client = NULL;
    }

    s_rt.state = RT_STATE_IDLE;
    s_rt.stats.connected = false;
    s_rt.stats.subscribed = false;

    ESP_LOGI(TAG, "Disconnected");
    return ESP_OK;
}

bool realtime_client_is_connected(void)
{
    return s_rt.state == RT_STATE_SUBSCRIBED;
}

esp_err_t realtime_client_get_status(realtime_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_rt.mutex, portMAX_DELAY);
    memcpy(status, &s_rt.stats, sizeof(realtime_status_t));
    xSemaphoreGive(s_rt.mutex);

    return ESP_OK;
}

/*******************************************************************************
 * Status Reporting
 ******************************************************************************/

esp_err_t realtime_client_ack_update(const char *request_id, const char *status,
                                      const char *component, const char *error_message)
{
    if (request_id == NULL || status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    ESP_LOGI(TAG, "ACK update %s: status=%s, component=%s",
             request_id, status, component ? component : "all");

    /* Build JSON body */
    cJSON *body = cJSON_CreateObject();
    if (body == NULL) {
        return ESP_ERR_NO_MEM;
    }

    cJSON_AddStringToObject(body, "status", status);

    /* Add timestamp based on status */
    if (strcmp(status, "notified") == 0) {
        /* TODO: Add notified_at timestamp */
    } else if (strcmp(status, "downloading") == 0) {
        /* TODO: Add started_at timestamp */
    } else if (strcmp(status, "complete") == 0 || strcmp(status, "failed") == 0) {
        /* TODO: Add completed_at timestamp */
    }

    /* Add component status for dual-SoC */
    if (component != NULL) {
        cJSON *comp_status = cJSON_CreateObject();
        cJSON_AddStringToObject(comp_status, component, status);
        cJSON_AddItemToObject(body, "component_status", comp_status);
    }

    /* Add error message if failed */
    if (error_message != NULL && strcmp(status, "failed") == 0) {
        cJSON_AddStringToObject(body, "error_message", error_message);
    }

    char *json_str = cJSON_PrintUnformatted(body);
    cJSON_Delete(body);

    if (json_str == NULL) {
        return ESP_ERR_NO_MEM;
    }

    /* PATCH update_requests?id=eq.{request_id} */
    /* For now, use POST to a status endpoint - actual implementation
       depends on Supabase setup (RPC function or direct table access) */
    char table[128];
    snprintf(table, sizeof(table), "update_requests?id=eq.%s", request_id);

    supabase_response_t response;
    esp_err_t err = supabase_post(table, json_str, &response, 10000);
    free(json_str);

    if (err == ESP_OK && response.status_code >= 200 && response.status_code < 300) {
        ESP_LOGI(TAG, "Update ACK sent successfully");
    } else {
        ESP_LOGW(TAG, "Failed to send update ACK: %d", response.status_code);
    }

    supabase_response_free(&response);
    return err;
}

esp_err_t realtime_client_ack_command(const char *command_id, const char *status,
                                       const char *result_json)
{
    if (command_id == NULL || status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /*
     * Per Device Command Protocol v1.2.4, command acknowledgements are sent as
     * heartbeats to device_heartbeats table (not PATCH to device_commands).
     *
     * Status mapping:
     * - "acknowledged" -> Send command_ack heartbeat
     * - "completed"    -> Send command_result heartbeat with success
     * - "failed"       -> Send command_result heartbeat with failure
     */
    if (strcmp(status, "acknowledged") == 0) {
        return send_command_ack_heartbeat(command_id);
    } else if (strcmp(status, "completed") == 0) {
        cJSON *result = NULL;
        if (result_json != NULL) {
            result = cJSON_Parse(result_json);
        }
        esp_err_t err = send_command_result_heartbeat(command_id, true, result, NULL);
        if (result != NULL) {
            cJSON_Delete(result);
        }
        return err;
    } else if (strcmp(status, "failed") == 0) {
        /* For failed status, result_json is treated as error message */
        return send_command_result_heartbeat(command_id, false, NULL, result_json);
    } else {
        ESP_LOGW(TAG, "Unknown ack status: %s", status);
        return ESP_ERR_INVALID_ARG;
    }
}

/*******************************************************************************
 * WebSocket Event Handler
 ******************************************************************************/

static void websocket_event_handler(void *handler_args, esp_event_base_t base,
                                    int32_t event_id, void *event_data)
{
    esp_websocket_event_data_t *data = (esp_websocket_event_data_t *)event_data;

    switch (event_id) {
        case WEBSOCKET_EVENT_CONNECTED:
            ESP_LOGI(TAG, "WebSocket connected");
            s_rt.state = RT_STATE_CONNECTED;
            s_rt.stats.connected = true;
            s_rt.reconnect_delay_ms = s_rt.config.reconnect_delay_ms;
            s_rt.last_pong_time = esp_timer_get_time();

            /* Post connected event */
            esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_CONNECTED, NULL, 0, 0);

            /* Join the device channel */
            send_phoenix_join();

            /* Start heartbeat timer */
            esp_timer_start_periodic(s_rt.heartbeat_timer,
                                     s_rt.config.heartbeat_interval_ms * 1000);
            break;

        case WEBSOCKET_EVENT_DISCONNECTED:
            ESP_LOGW(TAG, "WebSocket disconnected");
            s_rt.state = RT_STATE_IDLE;
            s_rt.stats.connected = false;
            s_rt.stats.subscribed = false;

            /* Stop heartbeat timer */
            esp_timer_stop(s_rt.heartbeat_timer);

            /* Post disconnected event */
            esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_DISCONNECTED, NULL, 0, 0);

            /* Schedule reconnection */
            if (s_rt.config.auto_connect && s_rt.ws_client != NULL) {
                ESP_LOGI(TAG, "Scheduling reconnect in %lu ms", s_rt.reconnect_delay_ms);
                esp_timer_start_once(s_rt.reconnect_timer,
                                     s_rt.reconnect_delay_ms * 1000);
                /* Exponential backoff */
                s_rt.reconnect_delay_ms = (s_rt.reconnect_delay_ms * 2 > RECONNECT_MAX_DELAY_MS) ?
                                          RECONNECT_MAX_DELAY_MS : s_rt.reconnect_delay_ms * 2;
            }
            break;

        case WEBSOCKET_EVENT_DATA:
            if (data->data_ptr != NULL && data->data_len > 0) {
                /* Only handle text frames */
                if (data->op_code == 0x01) {
                    handle_websocket_data(data->data_ptr, data->data_len);
                }
            }
            break;

        case WEBSOCKET_EVENT_ERROR:
            ESP_LOGE(TAG, "WebSocket error");
            esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_ERROR, NULL, 0, 0);
            break;

        default:
            break;
    }
}

/*******************************************************************************
 * Phoenix Channel Protocol
 ******************************************************************************/

static esp_err_t build_websocket_url(char *url, size_t max_len)
{
    supabase_config_t config;
    if (supabase_get_config(&config) != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }

    /* Convert HTTP URL to WebSocket URL
     * https://xyz.supabase.co -> wss://xyz.supabase.co/realtime/v1/websocket
     */
    const char *base = config.url;
    const char *host_start = strstr(base, "://");
    if (host_start == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    host_start += 3;  /* Skip "://" */

    int len = snprintf(url, max_len,
                       "wss://%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0",
                       host_start, config.anon_key);

    if (len >= max_len) {
        ESP_LOGE(TAG, "WebSocket URL too long");
        return ESP_ERR_INVALID_SIZE;
    }

    return ESP_OK;
}

static void send_phoenix_join(void)
{
    ESP_LOGI(TAG, "Joining channel: %s (filter: device_mac=%s)",
             s_rt.channel_topic, s_rt.device_mac);

    s_rt.msg_ref++;
    snprintf(s_rt.join_ref, sizeof(s_rt.join_ref), "%lu", (unsigned long)s_rt.msg_ref);

    cJSON *msg = cJSON_CreateObject();
    cJSON_AddStringToObject(msg, "topic", s_rt.channel_topic);
    cJSON_AddStringToObject(msg, "event", PHX_EVENT_JOIN);

    /* Build Postgres Changes subscription payload
     * This subscribes to INSERT events on device_commands table
     * filtered by device_mac matching this device's MAC address
     */
    cJSON *payload = cJSON_AddObjectToObject(msg, "payload");

    /* Postgres Changes configuration */
    cJSON *config = cJSON_AddObjectToObject(payload, "config");

    /* Configure postgres_changes subscription */
    cJSON *postgres_changes = cJSON_AddArrayToObject(config, "postgres_changes");
    cJSON *change_config = cJSON_CreateObject();
    cJSON_AddStringToObject(change_config, "event", "INSERT");
    cJSON_AddStringToObject(change_config, "schema", "public");
    cJSON_AddStringToObject(change_config, "table", "device_commands");

    /* Filter by device MAC address */
    char filter[64];
    snprintf(filter, sizeof(filter), "device_mac=eq.%s", s_rt.device_mac);
    cJSON_AddStringToObject(change_config, "filter", filter);

    cJSON_AddItemToArray(postgres_changes, change_config);

    cJSON_AddStringToObject(msg, "ref", s_rt.join_ref);

    char *json_str = cJSON_PrintUnformatted(msg);
    cJSON_Delete(msg);

    if (json_str != NULL) {
        ESP_LOGI(TAG, "Join payload: %s", json_str);
        esp_websocket_client_send_text(s_rt.ws_client, json_str, strlen(json_str),
                                        pdMS_TO_TICKS(5000));
        free(json_str);
    }

    s_rt.state = RT_STATE_SUBSCRIBING;
}

static void send_phoenix_heartbeat(void *arg)
{
    if (s_rt.state < RT_STATE_CONNECTED || s_rt.ws_client == NULL) {
        return;
    }

    /* Check for heartbeat timeout */
    int64_t now = esp_timer_get_time();
    if (now - s_rt.last_pong_time > HEARTBEAT_TIMEOUT_MS * 1000) {
        ESP_LOGW(TAG, "Heartbeat timeout - reconnecting");
        realtime_client_disconnect();
        if (s_rt.config.auto_connect) {
            realtime_client_connect();
        }
        return;
    }

    s_rt.msg_ref++;

    cJSON *msg = cJSON_CreateObject();
    cJSON_AddStringToObject(msg, "topic", "phoenix");
    cJSON_AddStringToObject(msg, "event", PHX_EVENT_HEARTBEAT);
    cJSON_AddObjectToObject(msg, "payload");

    char ref[16];
    snprintf(ref, sizeof(ref), "%lu", (unsigned long)s_rt.msg_ref);
    cJSON_AddStringToObject(msg, "ref", ref);

    char *json_str = cJSON_PrintUnformatted(msg);
    cJSON_Delete(msg);

    if (json_str != NULL) {
        ESP_LOGD(TAG, "Heartbeat: %s", json_str);
        esp_websocket_client_send_text(s_rt.ws_client, json_str, strlen(json_str),
                                        pdMS_TO_TICKS(5000));
        free(json_str);
    }
}

static void reconnect_timer_callback(void *arg)
{
    ESP_LOGI(TAG, "Reconnecting...");
    s_rt.stats.reconnect_count++;

    /* Clean up old client */
    if (s_rt.ws_client != NULL) {
        esp_websocket_client_destroy(s_rt.ws_client);
        s_rt.ws_client = NULL;
    }
    s_rt.state = RT_STATE_IDLE;

    /* Reconnect */
    realtime_client_connect();
}

/*******************************************************************************
 * Message Handling
 ******************************************************************************/

static void handle_websocket_data(const char *data, int len)
{
    /* Make a null-terminated copy */
    char *msg_copy = malloc(len + 1);
    if (msg_copy == NULL) {
        ESP_LOGE(TAG, "Failed to allocate message buffer");
        return;
    }
    memcpy(msg_copy, data, len);
    msg_copy[len] = '\0';

    ESP_LOGD(TAG, "Received: %s", msg_copy);

    /* Parse JSON */
    cJSON *msg = cJSON_Parse(msg_copy);
    free(msg_copy);

    if (msg == NULL) {
        ESP_LOGW(TAG, "Failed to parse message as JSON");
        return;
    }

    handle_phoenix_message(msg);
    cJSON_Delete(msg);
}

static void handle_phoenix_message(cJSON *msg)
{
    const cJSON *topic = cJSON_GetObjectItem(msg, "topic");
    const cJSON *event = cJSON_GetObjectItem(msg, "event");
    const cJSON *payload = cJSON_GetObjectItem(msg, "payload");
    const cJSON *ref = cJSON_GetObjectItem(msg, "ref");

    if (!cJSON_IsString(event)) {
        ESP_LOGW(TAG, "Message missing event");
        return;
    }

    const char *event_str = event->valuestring;
    const char *topic_str = cJSON_IsString(topic) ? topic->valuestring : "";

    xSemaphoreTake(s_rt.mutex, portMAX_DELAY);
    s_rt.stats.messages_received++;
    s_rt.stats.last_message_time = esp_timer_get_time();
    xSemaphoreGive(s_rt.mutex);

    /* Handle Phoenix protocol messages */
    if (strcmp(event_str, PHX_EVENT_REPLY) == 0) {
        /* Check if this is a join reply */
        const char *ref_str = cJSON_IsString(ref) ? ref->valuestring : "";
        if (strcmp(ref_str, s_rt.join_ref) == 0) {
            /* This is reply to our join */
            const cJSON *status = cJSON_GetObjectItem(payload, "status");
            if (cJSON_IsString(status) && strcmp(status->valuestring, "ok") == 0) {
                ESP_LOGI(TAG, "Successfully joined channel: %s", s_rt.channel_topic);
                s_rt.state = RT_STATE_SUBSCRIBED;
                s_rt.stats.subscribed = true;
            } else {
                /* Log the actual error response for debugging */
                const char *status_str = cJSON_IsString(status) ? status->valuestring : "null";
                const cJSON *response = cJSON_GetObjectItem(payload, "response");
                const cJSON *reason = response ? cJSON_GetObjectItem(response, "reason") : NULL;
                const char *reason_str = cJSON_IsString(reason) ? reason->valuestring : "unknown";
                ESP_LOGE(TAG, "Failed to join channel '%s': status=%s, reason=%s",
                         s_rt.channel_topic, status_str, reason_str);
                /* Log full payload for debugging */
                char *payload_str = cJSON_Print(payload);
                if (payload_str) {
                    ESP_LOGW(TAG, "Join response payload: %s", payload_str);
                    free(payload_str);
                }
                s_rt.state = RT_STATE_CONNECTED;
            }
        } else {
            /* Heartbeat reply - update pong time */
            s_rt.last_pong_time = esp_timer_get_time();
        }
        return;
    }

    if (strcmp(event_str, PHX_EVENT_HEARTBEAT) == 0) {
        s_rt.last_pong_time = esp_timer_get_time();
        return;
    }

    if (strcmp(event_str, PHX_EVENT_ERROR) == 0) {
        ESP_LOGE(TAG, "Phoenix error on topic: %s", topic_str);
        return;
    }

    if (strcmp(event_str, PHX_EVENT_CLOSE) == 0) {
        ESP_LOGW(TAG, "Channel closed: %s", topic_str);
        s_rt.stats.subscribed = false;
        return;
    }

    /* Handle Postgres Changes events (database INSERT/UPDATE/DELETE) */
    if (strcmp(event_str, PHX_EVENT_POSTGRES_CHANGES) == 0) {
        ESP_LOGI(TAG, "Received postgres_changes event");
        handle_postgres_changes(payload);
        return;
    }

    /* Handle broadcast messages on our channel (legacy support) */
    if (strcmp(event_str, PHX_EVENT_BROADCAST) == 0 ||
        strcmp(topic_str, s_rt.channel_topic) == 0) {

        /* Check the actual event type in payload */
        const cJSON *inner_event = cJSON_GetObjectItem(payload, "event");
        const cJSON *inner_payload = cJSON_GetObjectItem(payload, "payload");

        if (!cJSON_IsString(inner_event)) {
            /* Try treating event_str as the event type directly */
            inner_event = event;
            inner_payload = payload;
        }

        const char *type = cJSON_IsString(inner_event) ? inner_event->valuestring : event_str;

        if (strcmp(type, EVENT_UPDATE_AVAILABLE) == 0) {
            const cJSON *req_id = cJSON_GetObjectItem(
                inner_payload ? inner_payload : payload, "request_id");
            handle_update_available(inner_payload ? inner_payload : payload,
                                    cJSON_IsString(req_id) ? req_id->valuestring : NULL);
        } else if (strcmp(type, EVENT_COMMAND) == 0) {
            handle_command(inner_payload ? inner_payload : payload);
        } else if (strcmp(type, EVENT_CONFIG_UPDATE) == 0) {
            handle_config_update(inner_payload ? inner_payload : payload);
        } else {
            ESP_LOGD(TAG, "Unhandled event type: %s", type);
        }
    }
}

/*******************************************************************************
 * Event Handlers
 ******************************************************************************/

/**
 * @brief Handle Postgres Changes events from Supabase Realtime
 *
 * Postgres Changes events have this structure:
 * {
 *   "data": {
 *     "type": "INSERT",
 *     "table": "device_commands",
 *     "schema": "public",
 *     "record": {
 *       "id": "uuid",
 *       "device_mac": "AA-BB-CC-DD-EE-FF",
 *       "command": "reboot",
 *       "parameters": {...},
 *       ...
 *     },
 *     "old_record": null
 *   },
 *   "ids": [1]
 * }
 */
static void handle_postgres_changes(const cJSON *payload)
{
    /* Extract the data object */
    const cJSON *data = cJSON_GetObjectItem(payload, "data");
    if (!cJSON_IsObject(data)) {
        ESP_LOGW(TAG, "postgres_changes: missing 'data' object");
        /* Log payload for debugging */
        char *payload_str = cJSON_Print(payload);
        if (payload_str) {
            ESP_LOGW(TAG, "Payload: %s", payload_str);
            free(payload_str);
        }
        return;
    }

    /* Get the event type (INSERT, UPDATE, DELETE) */
    const cJSON *type = cJSON_GetObjectItem(data, "type");
    const char *type_str = cJSON_IsString(type) ? type->valuestring : "unknown";
    ESP_LOGI(TAG, "Postgres change: type=%s", type_str);

    /* We only care about INSERT events for new commands */
    if (strcmp(type_str, "INSERT") != 0) {
        ESP_LOGD(TAG, "Ignoring non-INSERT event: %s", type_str);
        return;
    }

    /* Get the inserted record */
    const cJSON *record = cJSON_GetObjectItem(data, "record");
    if (!cJSON_IsObject(record)) {
        ESP_LOGW(TAG, "postgres_changes: missing 'record' object");
        return;
    }

    /* Log the record for debugging */
    char *record_str = cJSON_Print(record);
    if (record_str) {
        ESP_LOGI(TAG, "New command record: %s", record_str);
        free(record_str);
    }

    /* Extract command fields from the record
     * Expected fields: id, device_mac, command, parameters, status, created_at
     */
    const cJSON *cmd_id = cJSON_GetObjectItem(record, "id");
    const cJSON *command = cJSON_GetObjectItem(record, "command");
    const cJSON *parameters = cJSON_GetObjectItem(record, "parameters");

    /* Build a command payload compatible with handle_command() */
    cJSON *command_payload = cJSON_CreateObject();

    if (cJSON_IsString(cmd_id)) {
        cJSON_AddStringToObject(command_payload, "id", cmd_id->valuestring);
    }

    if (cJSON_IsString(command)) {
        cJSON_AddStringToObject(command_payload, "command", command->valuestring);
    }

    /* Parameters could be an object or null */
    if (cJSON_IsObject(parameters)) {
        cJSON *params_copy = cJSON_Duplicate(parameters, true);
        cJSON_AddItemToObject(command_payload, "parameters", params_copy);
    }

    /* Route to the command handler */
    handle_command(command_payload);

    cJSON_Delete(command_payload);
}

static void handle_update_available(const cJSON *payload, const char *request_id)
{
    ESP_LOGI(TAG, "Update available notification received");

    xSemaphoreTake(s_rt.mutex, portMAX_DELAY);
    s_rt.stats.updates_received++;
    xSemaphoreGive(s_rt.mutex);

    /* Parse update information */
    realtime_update_event_t event = {0};

    if (request_id != NULL) {
        strncpy(event.request_id, request_id, sizeof(event.request_id) - 1);
    }

    const cJSON *device_type = cJSON_GetObjectItem(payload, "device_type");
    if (cJSON_IsString(device_type)) {
        strncpy(event.device_type, device_type->valuestring, sizeof(event.device_type) - 1);
    }

    const cJSON *is_critical = cJSON_GetObjectItem(payload, "is_critical");
    event.is_critical = cJSON_IsTrue(is_critical);

    /* Check for multi-component update */
    const cJSON *components = cJSON_GetObjectItem(payload, "components");
    if (cJSON_IsArray(components)) {
        /* Multi-component (dual-SoC) update */
        event.component_count = 0;
        cJSON *comp;
        cJSON_ArrayForEach(comp, components) {
            if (event.component_count >= 2) break;

            realtime_component_t *c = &event.components[event.component_count];

            const cJSON *type = cJSON_GetObjectItem(comp, "type");
            const cJSON *version = cJSON_GetObjectItem(comp, "version");
            const cJSON *url = cJSON_GetObjectItem(comp, "download_url");
            const cJSON *size = cJSON_GetObjectItem(comp, "firmware_size");
            const cJSON *sha = cJSON_GetObjectItem(comp, "sha256");

            if (cJSON_IsString(type)) {
                strncpy(c->type, type->valuestring, sizeof(c->type) - 1);
            }
            if (cJSON_IsString(version)) {
                strncpy(c->version, version->valuestring, sizeof(c->version) - 1);
            }
            if (cJSON_IsString(url)) {
                strncpy(c->download_url, url->valuestring, sizeof(c->download_url) - 1);
            }
            if (cJSON_IsNumber(size)) {
                c->firmware_size = (uint32_t)size->valuedouble;
            }
            if (cJSON_IsString(sha)) {
                strncpy(c->sha256, sha->valuestring, sizeof(c->sha256) - 1);
            }

            event.component_count++;
        }
    } else {
        /* Single-component update */
        event.component_count = 1;
        realtime_component_t *c = &event.components[0];

        strncpy(c->type, event.device_type, sizeof(c->type) - 1);

        const cJSON *version = cJSON_GetObjectItem(payload, "version");
        const cJSON *url = cJSON_GetObjectItem(payload, "download_url");
        const cJSON *size = cJSON_GetObjectItem(payload, "firmware_size");
        const cJSON *sha = cJSON_GetObjectItem(payload, "sha256");

        if (cJSON_IsString(version)) {
            strncpy(c->version, version->valuestring, sizeof(c->version) - 1);
        }
        if (cJSON_IsString(url)) {
            strncpy(c->download_url, url->valuestring, sizeof(c->download_url) - 1);
        }
        if (cJSON_IsNumber(size)) {
            c->firmware_size = (uint32_t)size->valuedouble;
        }
        if (cJSON_IsString(sha)) {
            strncpy(c->sha256, sha->valuestring, sizeof(c->sha256) - 1);
        }
    }

    ESP_LOGI(TAG, "Update: type=%s, components=%d, critical=%d",
             event.device_type, event.component_count, event.is_critical);

    for (int i = 0; i < event.component_count; i++) {
        ESP_LOGI(TAG, "  Component %d: %s v%s (%lu bytes)",
                 i, event.components[i].type, event.components[i].version,
                 (unsigned long)event.components[i].firmware_size);
    }

    /* Post event to event loop */
    esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_UPDATE_AVAILABLE,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /* Acknowledge receipt */
    if (event.request_id[0] != '\0') {
        realtime_client_ack_update(event.request_id, "notified", NULL, NULL);
    }

    /* Auto-apply if configured */
    if (s_rt.config.auto_apply_updates) {
        ESP_LOGI(TAG, "Auto-applying updates...");

        for (int i = 0; i < event.component_count; i++) {
            realtime_component_t *c = &event.components[i];

            if (strcmp(c->type, "hub_s3") == 0) {
                ESP_LOGI(TAG, "Starting S3 update...");
                if (event.request_id[0] != '\0') {
                    realtime_client_ack_update(event.request_id, "downloading", "hub_s3", NULL);
                }
                esp_err_t err = ota_manager_update_s3(c->download_url);
                if (err != ESP_OK) {
                    ESP_LOGE(TAG, "Failed to start S3 update: %s", esp_err_to_name(err));
                    if (event.request_id[0] != '\0') {
                        realtime_client_ack_update(event.request_id, "failed", "hub_s3",
                                                   esp_err_to_name(err));
                    }
                }
            } else if (strcmp(c->type, "hub_h2") == 0) {
                ESP_LOGI(TAG, "Starting H2 update...");
                if (event.request_id[0] != '\0') {
                    realtime_client_ack_update(event.request_id, "downloading", "hub_h2", NULL);
                }
                esp_err_t err = ota_manager_update_h2(c->download_url);
                if (err != ESP_OK) {
                    ESP_LOGE(TAG, "Failed to start H2 update: %s", esp_err_to_name(err));
                    if (event.request_id[0] != '\0') {
                        realtime_client_ack_update(event.request_id, "failed", "hub_h2",
                                                   esp_err_to_name(err));
                    }
                }
            } else if (strcmp(c->type, "crate") == 0) {
                /* Phase 4: Crate OTA via H2 relay */
                ESP_LOGI(TAG, "Starting Crate update...");

                /* Parse crate extended address from device_serial or parameters */
                /* For now, assume crate_ext_addr comes in the update payload */
                /* The crate target info should be in the event context */
                uint8_t crate_addr[8] = {0};  /* TODO: Get from event payload */

                /* Check if crate_ota module is busy */
                if (crate_ota_is_busy()) {
                    ESP_LOGW(TAG, "Crate OTA already in progress");
                    if (event.request_id[0] != '\0') {
                        realtime_client_ack_update(event.request_id, "failed", "crate",
                                                   "ota_in_progress");
                    }
                } else {
                    esp_err_t err = crate_ota_start(
                        crate_addr,
                        c->download_url,
                        c->firmware_size,
                        c->sha256,
                        c->version,
                        event.request_id
                    );
                    if (err != ESP_OK) {
                        ESP_LOGE(TAG, "Failed to start Crate update: %s", esp_err_to_name(err));
                        if (event.request_id[0] != '\0') {
                            realtime_client_ack_update(event.request_id, "failed", "crate",
                                                       esp_err_to_name(err));
                        }
                    }
                    /* crate_ota module handles status reporting from here */
                }
            } else {
                ESP_LOGW(TAG, "Unknown component type: %s", c->type);
            }
        }
    }
}

/**
 * @brief Handle a device command received via WebSocket
 *
 * Per Device Command Protocol v1.2.4, the command flow is:
 * 1. Device receives command via WebSocket (device:{mac_address} channel)
 * 2. Device immediately sends command_ack heartbeat
 * 3. Device executes command
 * 4. Device sends command_result heartbeat with outcome
 *
 * Known commands (handled internally):
 * - reboot: Restarts the device
 * - check_update: Triggers OTA update check
 * - get_status: Returns device status (TODO)
 *
 * Unknown commands are posted to the event loop for application handling.
 */
static void handle_command(const cJSON *payload)
{
    ESP_LOGI(TAG, "Command received via WebSocket");

    xSemaphoreTake(s_rt.mutex, portMAX_DELAY);
    s_rt.stats.commands_received++;
    xSemaphoreGive(s_rt.mutex);

    realtime_command_event_t event = {0};

    const cJSON *id = cJSON_GetObjectItem(payload, "id");
    const cJSON *command = cJSON_GetObjectItem(payload, "command");
    const cJSON *params = cJSON_GetObjectItem(payload, "parameters");

    if (cJSON_IsString(id)) {
        strncpy(event.command_id, id->valuestring, sizeof(event.command_id) - 1);
    }
    if (cJSON_IsString(command)) {
        strncpy(event.command, command->valuestring, sizeof(event.command) - 1);
    }
    if (params != NULL) {
        char *params_str = cJSON_PrintUnformatted(params);
        if (params_str != NULL) {
            strncpy(event.parameters, params_str, sizeof(event.parameters) - 1);
            free(params_str);
        }
    }

    ESP_LOGI(TAG, "Command: %s (id=%s)", event.command, event.command_id);

    /* Post event to event loop for any listeners */
    esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_COMMAND,
                   &event, sizeof(event), pdMS_TO_TICKS(100));

    /*
     * Step 1: Immediately send command_ack heartbeat (per protocol v1.2.4)
     * This acknowledges receipt before we start executing.
     */
    if (event.command_id[0] != '\0') {
        send_command_ack_heartbeat(event.command_id);
    }

    /*
     * Step 2: Execute command and send command_result heartbeat
     * Built-in commands are handled here; unknown commands rely on
     * application event handlers to call realtime_client_ack_command().
     */
    if (strcmp(event.command, "reboot") == 0) {
        ESP_LOGW(TAG, "Reboot command received - rebooting in 2 seconds");

        /* Build result data */
        cJSON *result = cJSON_CreateObject();
        cJSON_AddStringToObject(result, "action", "reboot_scheduled");
        cJSON_AddNumberToObject(result, "delay_ms", 2000);

        if (event.command_id[0] != '\0') {
            send_command_result_heartbeat(event.command_id, true, result, NULL);
        }
        cJSON_Delete(result);

        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_restart();

    } else if (strcmp(event.command, "check_update") == 0) {
        ESP_LOGI(TAG, "Check update command received");

        /* Trigger OTA check - this runs asynchronously */
        ota_manager_check_update(NULL);

        /* Build result data */
        cJSON *result = cJSON_CreateObject();
        cJSON_AddStringToObject(result, "action", "update_check_started");

        if (event.command_id[0] != '\0') {
            send_command_result_heartbeat(event.command_id, true, result, NULL);
        }
        cJSON_Delete(result);

    } else if (strcmp(event.command, "get_status") == 0) {
        ESP_LOGI(TAG, "Get status command received");

        /* Build status result */
        cJSON *result = cJSON_CreateObject();
        cJSON_AddStringToObject(result, "device_type", DEVICE_TYPE);
        cJSON_AddStringToObject(result, "firmware_version", FW_VERSION_STRING);

        char mac_str[18];
        get_mac_address_colon(mac_str, sizeof(mac_str));
        cJSON_AddStringToObject(result, "mac_address", mac_str);

        uint32_t uptime_sec = (uint32_t)(esp_timer_get_time() / 1000000);
        cJSON_AddNumberToObject(result, "uptime_sec", uptime_sec);
        cJSON_AddNumberToObject(result, "free_heap", esp_get_free_heap_size());

        if (event.command_id[0] != '\0') {
            send_command_result_heartbeat(event.command_id, true, result, NULL);
        }
        cJSON_Delete(result);

    } else {
        /*
         * Unknown command - posted to event loop above.
         * Application handlers should call realtime_client_ack_command()
         * with "completed" or "failed" status when done.
         */
        ESP_LOGD(TAG, "Unknown command '%s' - delegated to event handlers", event.command);
    }
}

static void handle_config_update(const cJSON *payload)
{
    ESP_LOGI(TAG, "Config update received");

    /* Post event to event loop for application to handle */
    esp_event_post(REALTIME_EVENTS, REALTIME_EVENT_CONFIG_UPDATE,
                   NULL, 0, pdMS_TO_TICKS(100));
}
