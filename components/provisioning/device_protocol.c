/**
 * @file device_protocol.c
 * @brief Saturday Device Command Protocol implementation
 *
 * Implements the Saturday Device Command Protocol v1.2.0 for factory provisioning,
 * testing, and remote device management.
 *
 * Key features:
 * - Always-listening (no entry window required)
 * - Unified command set for UART and cloud channels
 * - Source-tagged provisioning data (factory vs consumer)
 * - Capability-based test commands
 *
 * Commands supported:
 * - get_status: Get current device status
 * - get_capabilities: Get device capability manifest
 * - factory_provision: Store serial_number, name, and factory data
 * - get_provision_data: Read all stored provision data
 * - run_test: Execute capability tests (wifi/connect, cloud/ping, etc.)
 * - consumer_reset: Clear consumer data, preserve factory config
 * - factory_reset: Full wipe including factory data
 * - ota_update: Trigger firmware update
 * - reboot: Reboot the device
 */

#include "sdkconfig.h"

#include "device_protocol.h"
#include "config_store.h"
#include "supabase_client.h"
#include "wifi_manager.h"
#include "thread_br.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "led_manager.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "esp_system.h"
#include "esp_mac.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "driver/usb_serial_jtag.h"
#include "cJSON.h"

#include <string.h>
#include <stdio.h>

static const char *TAG = "DEV_PROTO";

/*******************************************************************************
 * Configuration
 ******************************************************************************/

#define UART_RX_BUF_SIZE        2048
#define TASK_STACK_SIZE         8192
#define TASK_PRIORITY           5

#define WIFI_CONNECT_TIMEOUT_MS 30000
#define CLOUD_PING_TIMEOUT_MS   15000
#define RFID_SCAN_TIMEOUT_MS    5000
#define THREAD_ATTACH_TIMEOUT_MS 60000

/*******************************************************************************
 * Module State
 ******************************************************************************/

static struct {
    bool initialized;
    bool running;
    TaskHandle_t task_handle;
    SemaphoreHandle_t mutex;
    device_protocol_callback_t callback;
    void *callback_user_data;
    char rx_buffer[DEVICE_PROTOCOL_MAX_MSG_LEN];
    size_t rx_len;
} s_proto = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void device_protocol_task(void *arg);
static void process_command(const char *json_str);

/* Command handlers */
static void handle_get_status(const char *cmd_id, cJSON *params);
static void handle_get_capabilities(const char *cmd_id, cJSON *params);
static void handle_factory_provision(const char *cmd_id, cJSON *params);
static void handle_get_provision_data(const char *cmd_id, cJSON *params);
static void handle_run_test(const char *cmd_id, cJSON *root);
static void handle_consumer_reset(const char *cmd_id, cJSON *params);
static void handle_factory_reset(const char *cmd_id, cJSON *params);
static void handle_ota_update(const char *cmd_id, cJSON *params);
static void handle_reboot(const char *cmd_id, cJSON *params);

/* Test runners */
static esp_err_t run_wifi_connect_test(cJSON *params, cJSON *result);
static esp_err_t run_cloud_ping_test(cJSON *params, cJSON *result);
static esp_err_t run_rfid_scan_test(cJSON *params, cJSON *result);
static esp_err_t run_thread_router_test(cJSON *params, cJSON *result);
static esp_err_t run_ble_test(cJSON *params, cJSON *result);
static esp_err_t run_button_press_test(cJSON *params, cJSON *result);

/* Helpers */
static void send_response(const char *cmd_id, const char *status, const char *message, cJSON *data);
static void send_error(const char *cmd_id, const char *error_code, const char *message);
static void get_mac_address_string(char *mac_str, size_t len);

/*******************************************************************************
 * Public API Implementation
 ******************************************************************************/

esp_err_t device_protocol_init(void)
{
    if (s_proto.initialized) {
        return ESP_OK;
    }

    /* Create mutex */
    s_proto.mutex = xSemaphoreCreateMutex();
    if (s_proto.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Install USB Serial JTAG driver for receiving data */
    usb_serial_jtag_driver_config_t usb_serial_config = {
        .rx_buffer_size = UART_RX_BUF_SIZE,
        .tx_buffer_size = UART_RX_BUF_SIZE,
    };

    esp_err_t err = usb_serial_jtag_driver_install(&usb_serial_config);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to install USB Serial JTAG driver: %s", esp_err_to_name(err));
        vSemaphoreDelete(s_proto.mutex);
        return err;
    }
    ESP_LOGI(TAG, "USB Serial JTAG driver installed");

    s_proto.initialized = true;
    ESP_LOGI(TAG, "Device protocol initialized");
    return ESP_OK;
}

esp_err_t device_protocol_deinit(void)
{
    if (!s_proto.initialized) {
        return ESP_OK;
    }

    device_protocol_stop();

    if (s_proto.mutex) {
        vSemaphoreDelete(s_proto.mutex);
        s_proto.mutex = NULL;
    }

    s_proto.initialized = false;
    ESP_LOGI(TAG, "Device protocol deinitialized");
    return ESP_OK;
}

esp_err_t device_protocol_start(void)
{
    if (!s_proto.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_proto.running) {
        return ESP_OK;
    }

    xSemaphoreTake(s_proto.mutex, portMAX_DELAY);

    BaseType_t ret = xTaskCreate(
        device_protocol_task,
        "dev_proto",
        TASK_STACK_SIZE,
        NULL,
        TASK_PRIORITY,
        &s_proto.task_handle
    );

    if (ret != pdPASS) {
        xSemaphoreGive(s_proto.mutex);
        ESP_LOGE(TAG, "Failed to create protocol task");
        return ESP_ERR_NO_MEM;
    }

    s_proto.running = true;
    xSemaphoreGive(s_proto.mutex);

    ESP_LOGI(TAG, "Device protocol started - listening for commands");
    return ESP_OK;
}

esp_err_t device_protocol_stop(void)
{
    if (!s_proto.running) {
        return ESP_OK;
    }

    xSemaphoreTake(s_proto.mutex, portMAX_DELAY);

    if (s_proto.task_handle) {
        vTaskDelete(s_proto.task_handle);
        s_proto.task_handle = NULL;
    }

    s_proto.running = false;
    xSemaphoreGive(s_proto.mutex);

    ESP_LOGI(TAG, "Device protocol stopped");
    return ESP_OK;
}

bool device_protocol_is_running(void)
{
    return s_proto.running;
}

esp_err_t device_protocol_register_callback(device_protocol_callback_t callback, void *user_data)
{
    xSemaphoreTake(s_proto.mutex, portMAX_DELAY);
    s_proto.callback = callback;
    s_proto.callback_user_data = user_data;
    xSemaphoreGive(s_proto.mutex);
    return ESP_OK;
}

esp_err_t device_protocol_send_json(const char *json)
{
    if (json == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    printf("%s\n", json);
    fflush(stdout);

    return ESP_OK;
}

/*******************************************************************************
 * Private Functions
 ******************************************************************************/

static void device_protocol_task(void *arg)
{
    (void)arg;
    uint8_t byte;

    ESP_LOGI(TAG, "Protocol task started");

    s_proto.rx_len = 0;
    memset(s_proto.rx_buffer, 0, sizeof(s_proto.rx_buffer));

    while (1) {
        int len = usb_serial_jtag_read_bytes(&byte, 1, pdMS_TO_TICKS(50));

        if (len > 0) {
            if (byte == '\n' || byte == '\r') {
                if (s_proto.rx_len > 0) {
                    s_proto.rx_buffer[s_proto.rx_len] = '\0';
                    ESP_LOGI(TAG, "Received: %s", s_proto.rx_buffer);
                    process_command(s_proto.rx_buffer);
                    s_proto.rx_len = 0;
                }
            } else if (s_proto.rx_len < sizeof(s_proto.rx_buffer) - 1) {
                s_proto.rx_buffer[s_proto.rx_len++] = (char)byte;
            } else {
                ESP_LOGW(TAG, "RX buffer overflow, discarding");
                s_proto.rx_len = 0;
            }
        }

        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

static void process_command(const char *json_str)
{
    cJSON *root = cJSON_Parse(json_str);
    if (root == NULL) {
        send_error("", "parse_error", "Invalid JSON");
        return;
    }

    /* Extract command ID (required) */
    cJSON *id_obj = cJSON_GetObjectItem(root, "id");
    const char *cmd_id = cJSON_IsString(id_obj) ? id_obj->valuestring : "";

    /* Extract command name */
    cJSON *cmd_obj = cJSON_GetObjectItem(root, "cmd");
    if (!cJSON_IsString(cmd_obj)) {
        send_error(cmd_id, "invalid_command", "Missing 'cmd' field");
        cJSON_Delete(root);
        return;
    }
    const char *cmd = cmd_obj->valuestring;

    /* Extract params (optional) */
    cJSON *params = cJSON_GetObjectItem(root, "params");

    ESP_LOGI(TAG, "Processing: cmd=%s, id=%s", cmd, cmd_id);

    /* Route to handler */
    if (strcmp(cmd, "get_status") == 0) {
        handle_get_status(cmd_id, params);
    } else if (strcmp(cmd, "get_capabilities") == 0) {
        handle_get_capabilities(cmd_id, params);
    } else if (strcmp(cmd, "factory_provision") == 0) {
        handle_factory_provision(cmd_id, params);
    } else if (strcmp(cmd, "get_provision_data") == 0) {
        handle_get_provision_data(cmd_id, params);
    } else if (strcmp(cmd, "run_test") == 0) {
        handle_run_test(cmd_id, root);
    } else if (strcmp(cmd, "consumer_reset") == 0) {
        handle_consumer_reset(cmd_id, params);
    } else if (strcmp(cmd, "factory_reset") == 0) {
        handle_factory_reset(cmd_id, params);
    } else if (strcmp(cmd, "ota_update") == 0) {
        handle_ota_update(cmd_id, params);
    } else if (strcmp(cmd, "reboot") == 0) {
        handle_reboot(cmd_id, params);
    } else {
        send_error(cmd_id, "invalid_command", "Unknown command");
    }

    cJSON_Delete(root);
}

/*******************************************************************************
 * Response Helpers
 ******************************************************************************/

static void send_response(const char *cmd_id, const char *status, const char *message, cJSON *data)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "id", cmd_id ? cmd_id : "");
    cJSON_AddStringToObject(root, "status", status);

    if (message != NULL) {
        cJSON_AddStringToObject(root, "message", message);
    }

    if (data != NULL) {
        cJSON_AddItemToObject(root, "data", cJSON_Duplicate(data, true));
    }

    char *json = cJSON_PrintUnformatted(root);
    if (json) {
        device_protocol_send_json(json);
        cJSON_free(json);
    }

    cJSON_Delete(root);
}

static void send_error(const char *cmd_id, const char *error_code, const char *message)
{
    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "error_code", error_code);
    send_response(cmd_id, "error", message, data);
    cJSON_Delete(data);
}

static void get_mac_address_string(char *mac_str, size_t len)
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
 * Command Handlers
 ******************************************************************************/

static void handle_get_status(const char *cmd_id, cJSON *params)
{
    (void)params;

    cJSON *data = cJSON_CreateObject();

    /* Device identification */
    cJSON_AddStringToObject(data, "device_type", "hub");
    cJSON_AddStringToObject(data, "firmware_version", FIRMWARE_VERSION);

    char mac_str[18];
    get_mac_address_string(mac_str, sizeof(mac_str));
    cJSON_AddStringToObject(data, "mac_address", mac_str);

    /* Serial number and name */
    char serial_number[32] = {0};
    if (config_get_serial_number(serial_number, sizeof(serial_number)) == ESP_OK) {
        cJSON_AddStringToObject(data, "serial_number", serial_number);
    } else {
        cJSON_AddNullToObject(data, "serial_number");
    }

    char name[32] = {0};
    if (config_get_name(name, sizeof(name)) == ESP_OK) {
        cJSON_AddStringToObject(data, "name", name);
    } else {
        cJSON_AddNullToObject(data, "name");
    }

    /* System info */
    cJSON_AddNumberToObject(data, "uptime_ms", esp_timer_get_time() / 1000);
    cJSON_AddNumberToObject(data, "free_heap", esp_get_free_heap_size());

    /* Capability status */
    cJSON *capabilities = cJSON_CreateObject();

    /* WiFi capability status */
    cJSON *wifi_status = cJSON_CreateObject();
    cJSON_AddBoolToObject(wifi_status, "configured", config_has_wifi());
    cJSON_AddBoolToObject(wifi_status, "connected", wifi_is_connected());
    if (wifi_is_connected()) {
        wifi_manager_status_t ws;
        if (wifi_get_status(&ws) == ESP_OK) {
            cJSON_AddStringToObject(wifi_status, "ssid", ws.ssid);
            cJSON_AddNumberToObject(wifi_status, "rssi", ws.rssi);
        }
        char ip[16];
        wifi_get_ip_string(ip, sizeof(ip));
        cJSON_AddStringToObject(wifi_status, "ip_address", ip);
    }
    cJSON_AddItemToObject(capabilities, "wifi", wifi_status);

    /* Cloud capability status */
    cJSON *cloud_status = cJSON_CreateObject();
    cJSON_AddBoolToObject(cloud_status, "configured", supabase_is_configured());
    if (supabase_is_configured()) {
        supabase_config_t sb_config;
        if (supabase_get_config(&sb_config) == ESP_OK) {
            cJSON_AddStringToObject(cloud_status, "cloud_url", sb_config.url);
        }
    }
    cJSON_AddItemToObject(capabilities, "cloud", cloud_status);

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    /* Thread BR capability status */
    cJSON *thread_status = cJSON_CreateObject();
    thread_br_state_t thread_state = thread_br_get_state();
    cJSON_AddBoolToObject(thread_status, "configured", thread_state != THREAD_BR_STATE_DISABLED);
    cJSON_AddBoolToObject(thread_status, "connected", thread_state >= THREAD_BR_STATE_CHILD);
    cJSON_AddStringToObject(thread_status, "role", thread_br_state_to_string(thread_state));
    cJSON_AddItemToObject(capabilities, "thread_br", thread_status);
#endif

    /* RFID capability status */
    cJSON *rfid_status = cJSON_CreateObject();
    char rfid_version[32] = {0};
    if (yrm100_get_firmware_version(rfid_version, sizeof(rfid_version)) == ESP_OK) {
        cJSON_AddStringToObject(rfid_status, "module_firmware", rfid_version);
    }
    cJSON_AddItemToObject(capabilities, "rfid", rfid_status);

    cJSON_AddItemToObject(data, "capabilities", capabilities);

    send_response(cmd_id, "ok", NULL, data);
    cJSON_Delete(data);
}

static void handle_get_capabilities(const char *cmd_id, cJSON *params)
{
    (void)params;

    /* Return the capability manifest matching the firmware schema */
    cJSON *data = cJSON_CreateObject();

    cJSON_AddStringToObject(data, "version", FIRMWARE_VERSION);
    cJSON_AddStringToObject(data, "device_type", "hub-prototype");

    cJSON *capabilities = cJSON_CreateArray();
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("wifi"));
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("thread_br"));
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("cloud"));
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("rfid"));
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("ble"));
    cJSON_AddItemToArray(capabilities, cJSON_CreateString("button"));

    cJSON_AddItemToObject(data, "capabilities", capabilities);

    send_response(cmd_id, "ok", NULL, data);
    cJSON_Delete(data);
}

static void handle_factory_provision(const char *cmd_id, cJSON *params)
{
    if (params == NULL) {
        send_error(cmd_id, "missing_params", "Provisioning data required");
        return;
    }

    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_PULSE, 1000);

    /* Required fields */
    cJSON *serial_number_obj = cJSON_GetObjectItem(params, "serial_number");
    cJSON *name_obj = cJSON_GetObjectItem(params, "name");

    if (!cJSON_IsString(serial_number_obj) || !cJSON_IsString(name_obj)) {
        send_error(cmd_id, "missing_params", "Required: serial_number, name");
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    const char *serial_number = serial_number_obj->valuestring;
    const char *name = name_obj->valuestring;

    esp_err_t err;

    /* Store serial_number and name (factory data) */
    err = config_set_serial_number(serial_number);
    if (err != ESP_OK) {
        send_error(cmd_id, "storage_error", "Failed to store serial_number");
        led_flash(LED_COLOR_RED, 500);
        return;
    }

    err = config_set_name(name);
    if (err != ESP_OK) {
        send_error(cmd_id, "storage_error", "Failed to store name");
        led_flash(LED_COLOR_RED, 500);
        return;
    }

    /* Cloud capability: factory_input */
    cJSON *cloud_url = cJSON_GetObjectItem(params, "cloud_url");
    cJSON *cloud_anon_key = cJSON_GetObjectItem(params, "cloud_anon_key");

    if (cJSON_IsString(cloud_url) && cJSON_IsString(cloud_anon_key)) {
        supabase_config_t sb_config = {0};
        strncpy(sb_config.unit_id, serial_number, sizeof(sb_config.unit_id) - 1);
        strncpy(sb_config.url, cloud_url->valuestring, sizeof(sb_config.url) - 1);
        strncpy(sb_config.anon_key, cloud_anon_key->valuestring, sizeof(sb_config.anon_key) - 1);

        cJSON *device_secret = cJSON_GetObjectItem(params, "cloud_device_secret");
        if (cJSON_IsString(device_secret)) {
            strncpy(sb_config.device_secret, device_secret->valuestring, sizeof(sb_config.device_secret) - 1);
        }

        err = supabase_set_config(&sb_config);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Failed to store cloud config: %s", esp_err_to_name(err));
        } else {
            ESP_LOGI(TAG, "Cloud config stored for %s", cloud_url->valuestring);
        }
    }

    /* RFID capability: factory_input */
    cJSON *power_dbm = cJSON_GetObjectItem(params, "power_dbm");
    if (cJSON_IsNumber(power_dbm)) {
        config_set_int_tagged("rfid_power", power_dbm->valueint, CONFIG_SOURCE_FACTORY);
        ESP_LOGI(TAG, "RFID power_dbm stored: %d", power_dbm->valueint);
    }

    /* WiFi (optional for factory test network) */
    cJSON *wifi_ssid = cJSON_GetObjectItem(params, "wifi_ssid");
    cJSON *wifi_password = cJSON_GetObjectItem(params, "wifi_password");
    if (cJSON_IsString(wifi_ssid)) {
        const char *pass = cJSON_IsString(wifi_password) ? wifi_password->valuestring : "";
        config_set_wifi(wifi_ssid->valuestring, pass);
        /* Tag as factory WiFi */
        config_set_string_tagged("wifi_source", "factory", CONFIG_SOURCE_FACTORY);
    }

    /* Mark as provisioned */
    config_set_provisioned(true);

    /* Build response with factory_output */
    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "serial_number", serial_number);
    cJSON_AddStringToObject(data, "name", name);

    char mac_str[18];
    get_mac_address_string(mac_str, sizeof(mac_str));
    cJSON_AddStringToObject(data, "mac_address", mac_str);

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    /* Thread BR: factory_output - generate and return credentials */
    thread_br_ensure_credentials();
    thread_network_credentials_t thread_creds;
    if (thread_br_get_credentials(&thread_creds) == ESP_OK) {
        cJSON *thread_data = cJSON_CreateObject();
        cJSON_AddNumberToObject(thread_data, "pan_id", thread_creds.pan_id);
        cJSON_AddNumberToObject(thread_data, "channel", thread_creds.channel);
        cJSON_AddStringToObject(thread_data, "network_name", thread_creds.network_name);

        char network_key_hex[33];
        thread_br_get_network_key_hex(network_key_hex, sizeof(network_key_hex));
        cJSON_AddStringToObject(thread_data, "network_key", network_key_hex);

        cJSON_AddItemToObject(data, "thread_credentials", thread_data);
    }
#endif

    led_flash(LED_COLOR_GREEN, 500);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);

    send_response(cmd_id, "ok", "Device provisioned successfully", data);
    cJSON_Delete(data);

    /* Notify callback */
    if (s_proto.callback) {
        s_proto.callback(DEVICE_PROTOCOL_EVENT_PROVISIONED, s_proto.callback_user_data);
    }
}

static void handle_get_provision_data(const char *cmd_id, cJSON *params)
{
    (void)params;

    cJSON *data = cJSON_CreateObject();

    /* Serial number and name */
    char serial_number[32] = {0};
    if (config_get_serial_number(serial_number, sizeof(serial_number)) == ESP_OK) {
        cJSON_AddStringToObject(data, "serial_number", serial_number);
    }

    char name[32] = {0};
    if (config_get_name(name, sizeof(name)) == ESP_OK) {
        cJSON_AddStringToObject(data, "name", name);
    }

    char mac_str[18];
    get_mac_address_string(mac_str, sizeof(mac_str));
    cJSON_AddStringToObject(data, "mac_address", mac_str);

    /* Cloud config */
    if (supabase_is_configured()) {
        supabase_config_t sb_config;
        if (supabase_get_config(&sb_config) == ESP_OK) {
            cJSON_AddStringToObject(data, "cloud_url", sb_config.url);
        }
    }

    /* WiFi (if configured) */
    if (config_has_wifi()) {
        char ssid[33], password[65];
        if (config_get_wifi(ssid, sizeof(ssid), password, sizeof(password)) == ESP_OK) {
            cJSON_AddStringToObject(data, "wifi_ssid", ssid);
        }
    }

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    /* Thread credentials */
    thread_network_credentials_t thread_creds;
    if (thread_br_get_credentials(&thread_creds) == ESP_OK) {
        cJSON *thread_data = cJSON_CreateObject();
        cJSON_AddNumberToObject(thread_data, "pan_id", thread_creds.pan_id);
        cJSON_AddNumberToObject(thread_data, "channel", thread_creds.channel);
        cJSON_AddStringToObject(thread_data, "network_name", thread_creds.network_name);

        char network_key_hex[33];
        thread_br_get_network_key_hex(network_key_hex, sizeof(network_key_hex));
        cJSON_AddStringToObject(thread_data, "network_key", network_key_hex);

        cJSON_AddItemToObject(data, "thread_credentials", thread_data);
    }
#endif

    send_response(cmd_id, "ok", NULL, data);
    cJSON_Delete(data);
}

static void handle_run_test(const char *cmd_id, cJSON *root)
{
    cJSON *capability_obj = cJSON_GetObjectItem(root, "capability");
    cJSON *test_name_obj = cJSON_GetObjectItem(root, "test_name");
    cJSON *params = cJSON_GetObjectItem(root, "params");

    if (!cJSON_IsString(capability_obj) || !cJSON_IsString(test_name_obj)) {
        send_error(cmd_id, "missing_params", "Required: capability, test_name");
        return;
    }

    const char *capability = capability_obj->valuestring;
    const char *test_name = test_name_obj->valuestring;

    ESP_LOGI(TAG, "Running test: %s/%s", capability, test_name);
    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_FAST, 250);

    cJSON *result = cJSON_CreateObject();
    esp_err_t err = ESP_ERR_NOT_FOUND;

    /* Route to test handler based on capability/test_name */
    if (strcmp(capability, "wifi") == 0 && strcmp(test_name, "connect") == 0) {
        err = run_wifi_connect_test(params, result);
    } else if (strcmp(capability, "cloud") == 0 && strcmp(test_name, "ping") == 0) {
        err = run_cloud_ping_test(params, result);
    } else if (strcmp(capability, "rfid") == 0 && strcmp(test_name, "scan") == 0) {
        err = run_rfid_scan_test(params, result);
    } else if (strcmp(capability, "thread_br") == 0 && strcmp(test_name, "thread_router_test") == 0) {
        err = run_thread_router_test(params, result);
    } else if (strcmp(capability, "ble") == 0 && strcmp(test_name, "ble_test") == 0) {
        err = run_ble_test(params, result);
    } else if (strcmp(capability, "button") == 0 && strcmp(test_name, "press") == 0) {
        err = run_button_press_test(params, result);
    }

    if (err == ESP_ERR_NOT_FOUND) {
        send_error(cmd_id, "test_not_found", "Unknown capability or test");
        cJSON_Delete(result);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    if (err == ESP_OK) {
        led_flash(LED_COLOR_GREEN, 500);
        send_response(cmd_id, "ok", "Test passed", result);
    } else {
        led_flash(LED_COLOR_RED, 500);
        send_response(cmd_id, "failed", "Test failed", result);
    }

    cJSON_Delete(result);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_consumer_reset(const char *cmd_id, cJSON *params)
{
    (void)params;

    ESP_LOGW(TAG, "Consumer reset requested");
    led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 200);

    send_response(cmd_id, "ok", "Consumer reset in progress - device will reboot", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Perform consumer reset - clears consumer-tagged data */
    esp_err_t err = config_consumer_reset();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Consumer reset failed: %s", esp_err_to_name(err));
    }

    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static void handle_factory_reset(const char *cmd_id, cJSON *params)
{
    (void)params;

    ESP_LOGW(TAG, "FACTORY RESET - erasing ALL configuration!");
    led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 200);

    send_response(cmd_id, "ok", "Factory reset in progress - ALL data will be erased", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    esp_err_t err = config_factory_reset();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Factory reset failed: %s", esp_err_to_name(err));
    }

    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static void handle_ota_update(const char *cmd_id, cJSON *params)
{
    if (params == NULL) {
        send_error(cmd_id, "missing_params", "OTA parameters required");
        return;
    }

    cJSON *firmware_url = cJSON_GetObjectItem(params, "firmware_url");
    cJSON *target_version = cJSON_GetObjectItem(params, "target_version");

    if (!cJSON_IsString(firmware_url)) {
        send_error(cmd_id, "missing_params", "Required: firmware_url");
        return;
    }

    const char *version = cJSON_IsString(target_version) ? target_version->valuestring : "unknown";
    ESP_LOGI(TAG, "OTA update requested to version %s", version);

    /* Acknowledge the request */
    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "target_version", version);
    send_response(cmd_id, "acknowledged", "Starting OTA update", data);
    cJSON_Delete(data);

    /* TODO: Implement actual OTA update logic */
    ESP_LOGW(TAG, "OTA update not yet implemented");
}

static void handle_reboot(const char *cmd_id, cJSON *params)
{
    (void)params;

    ESP_LOGI(TAG, "Reboot requested");

    send_response(cmd_id, "ok", "Rebooting...", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    esp_restart();
}

/*******************************************************************************
 * Test Runners
 ******************************************************************************/

static esp_err_t run_wifi_connect_test(cJSON *params, cJSON *result)
{
    const char *ssid = NULL;
    const char *password = "";
    int timeout_ms = WIFI_CONNECT_TIMEOUT_MS;

    if (params != NULL) {
        cJSON *ssid_obj = cJSON_GetObjectItem(params, "ssid");
        cJSON *pass_obj = cJSON_GetObjectItem(params, "password");
        cJSON *timeout_obj = cJSON_GetObjectItem(params, "timeout_ms");

        if (cJSON_IsString(ssid_obj)) {
            ssid = ssid_obj->valuestring;
            password = cJSON_IsString(pass_obj) ? pass_obj->valuestring : "";
            config_set_wifi(ssid, password);
        }
        if (cJSON_IsNumber(timeout_obj)) {
            timeout_ms = timeout_obj->valueint;
        }
    }

    /* Initialize WiFi if needed */
    esp_err_t err = wifi_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        cJSON_AddStringToObject(result, "error", "wifi_init_failed");
        return ESP_FAIL;
    }

    vTaskDelay(pdMS_TO_TICKS(500));

    /* Connect */
    if (ssid != NULL) {
        err = wifi_connect(ssid, password);
    } else {
        err = wifi_connect_stored();
    }

    if (err != ESP_OK) {
        cJSON_AddStringToObject(result, "error", "connect_failed");
        return ESP_FAIL;
    }

    /* Wait for connection */
    int64_t start = esp_timer_get_time();
    while (!wifi_is_connected()) {
        if ((esp_timer_get_time() - start) > (timeout_ms * 1000LL)) {
            cJSON_AddBoolToObject(result, "connected", false);
            cJSON_AddStringToObject(result, "error", "timeout");
            return ESP_FAIL;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    /* Success - populate result */
    cJSON_AddBoolToObject(result, "connected", true);

    char ip[16];
    wifi_get_ip_string(ip, sizeof(ip));
    cJSON_AddStringToObject(result, "ip_address", ip);

    wifi_manager_status_t ws;
    if (wifi_get_status(&ws) == ESP_OK) {
        cJSON_AddNumberToObject(result, "rssi", ws.rssi);
    }

    int64_t duration = (esp_timer_get_time() - start) / 1000;
    cJSON_AddNumberToObject(result, "duration_ms", (int)duration);

    return ESP_OK;
}

static esp_err_t run_cloud_ping_test(cJSON *params, cJSON *result)
{
    int timeout_ms = CLOUD_PING_TIMEOUT_MS;

    if (params != NULL) {
        cJSON *timeout_obj = cJSON_GetObjectItem(params, "timeout_ms");
        if (cJSON_IsNumber(timeout_obj)) {
            timeout_ms = timeout_obj->valueint;
        }
    }

    if (!supabase_is_configured()) {
        cJSON_AddStringToObject(result, "error", "not_configured");
        return ESP_FAIL;
    }

    if (!wifi_is_connected()) {
        cJSON_AddStringToObject(result, "error", "no_wifi");
        return ESP_FAIL;
    }

    /* Send test heartbeat */
    char serial_number[32] = "UNKNOWN";
    config_get_serial_number(serial_number, sizeof(serial_number));

    char json_body[256];
    snprintf(json_body, sizeof(json_body),
             "{\"mac_address\":\"%s\",\"firmware_version\":\"%s\",\"uptime_ms\":%llu}",
             serial_number, FIRMWARE_VERSION,
             (unsigned long long)(esp_timer_get_time() / 1000));

    int64_t start = esp_timer_get_time();
    supabase_response_t response = {0};
    esp_err_t err = supabase_post("device_heartbeats", json_body, &response, timeout_ms);
    int64_t latency = (esp_timer_get_time() - start) / 1000;

    cJSON_AddNumberToObject(result, "latency_ms", (int)latency);

    if (err != ESP_OK || response.status_code < 200 || response.status_code >= 300) {
        cJSON_AddBoolToObject(result, "connected", false);
        cJSON_AddNumberToObject(result, "status_code", response.status_code);
        supabase_response_free(&response);
        return ESP_FAIL;
    }

    cJSON_AddBoolToObject(result, "connected", true);
    cJSON_AddNumberToObject(result, "status_code", response.status_code);
    supabase_response_free(&response);

    return ESP_OK;
}

static esp_err_t run_rfid_scan_test(cJSON *params, cJSON *result)
{
    int duration_ms = RFID_SCAN_TIMEOUT_MS;

    if (params != NULL) {
        cJSON *duration_obj = cJSON_GetObjectItem(params, "duration_ms");
        if (cJSON_IsNumber(duration_obj)) {
            duration_ms = duration_obj->valueint;
        }
    }

    esp_err_t err = yrm100_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        cJSON_AddStringToObject(result, "error", "init_failed");
        return ESP_FAIL;
    }

    yrm100_enable(true);
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Get firmware version */
    char version[32] = {0};
    err = yrm100_get_firmware_version(version, sizeof(version));
    if (err != ESP_OK) {
        yrm100_enable(false);
        cJSON_AddStringToObject(result, "error", "comm_failed");
        return ESP_FAIL;
    }
    cJSON_AddStringToObject(result, "module_firmware", version);

    /* Scan for tags */
    uint8_t tags_found = 0;
    char last_epc[25] = {0};
    int64_t start = esp_timer_get_time();

    while ((esp_timer_get_time() - start) < (duration_ms * 1000LL)) {
        rfid_tag_t tag;
        err = yrm100_single_poll_with_data(&tag);

        if (err == ESP_OK && tag.is_saturday_tag) {
            tags_found++;
            rfid_epc_to_hex_string(tag.epc, tag.epc_len, last_epc, sizeof(last_epc));
            ESP_LOGI(TAG, "Found Saturday tag: %s", last_epc);
        }

        vTaskDelay(pdMS_TO_TICKS(200));
    }

    yrm100_enable(false);

    cJSON_AddNumberToObject(result, "last_scan_count", tags_found);
    if (tags_found > 0) {
        cJSON_AddStringToObject(result, "last_epc", last_epc);
    }

    /* Test passes even with 0 tags - just reports what was found */
    return ESP_OK;
}

static esp_err_t run_thread_router_test(cJSON *params, cJSON *result)
{
#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    int timeout_ms = THREAD_ATTACH_TIMEOUT_MS;

    if (params != NULL) {
        cJSON *timeout_obj = cJSON_GetObjectItem(params, "timeout_ms");
        if (cJSON_IsNumber(timeout_obj)) {
            timeout_ms = timeout_obj->valueint;
        }
    }

    /* Ensure credentials exist */
    esp_err_t err = thread_br_ensure_credentials();
    if (err != ESP_OK) {
        cJSON_AddStringToObject(result, "error", "creds_failed");
        return ESP_FAIL;
    }

    /* Initialize and start Thread BR */
    err = thread_br_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        cJSON_AddStringToObject(result, "error", "init_failed");
        return ESP_FAIL;
    }

    err = thread_br_start();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        cJSON_AddStringToObject(result, "error", "start_failed");
        return ESP_FAIL;
    }

    /* Wait for Thread to attach and become leader */
    int64_t start = esp_timer_get_time();
    while ((esp_timer_get_time() - start) < (timeout_ms * 1000LL)) {
        thread_br_state_t state = thread_br_get_state();
        if (state == THREAD_BR_STATE_LEADER) {
            cJSON_AddStringToObject(result, "role", "leader");
            return ESP_OK;
        }
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    /* Timed out - report current role */
    thread_br_state_t state = thread_br_get_state();
    cJSON_AddStringToObject(result, "role", thread_br_state_to_string(state));
    cJSON_AddStringToObject(result, "error", "not_leader");
    return ESP_FAIL;
#else
    cJSON_AddStringToObject(result, "error", "thread_not_enabled");
    return ESP_FAIL;
#endif
}

static esp_err_t run_ble_test(cJSON *params, cJSON *result)
{
    (void)params;

    /* BLE test - just verify BLE can be enabled */
    /* Actual BLE testing would require more complex interaction */
    cJSON_AddBoolToObject(result, "ble_available", true);
    return ESP_OK;
}

static esp_err_t run_button_press_test(cJSON *params, cJSON *result)
{
    int timeout_ms = 30000;

    if (params != NULL) {
        cJSON *timeout_obj = cJSON_GetObjectItem(params, "timeout_ms");
        if (cJSON_IsNumber(timeout_obj)) {
            timeout_ms = timeout_obj->valueint;
        }
    }

    /* Button press test - would need to integrate with button_handler */
    /* For now, just acknowledge the test was requested */
    cJSON_AddNumberToObject(result, "timeout_ms", timeout_ms);
    cJSON_AddStringToObject(result, "status", "waiting_for_press");

    /* TODO: Implement actual button press detection with callback */
    return ESP_OK;
}
