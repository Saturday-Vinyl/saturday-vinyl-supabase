/**
 * @file serial_prov.c
 * @brief Service Mode for factory provisioning and servicing via Saturday Admin app
 *
 * Implements the Saturday Service Mode Protocol for factory provisioning, testing,
 * and device servicing. Uses USB serial for communication with the Admin desktop app.
 *
 * Service Mode Protocol v2.1 - Commands supported:
 * - enter_service_mode: Enter service mode (during boot window)
 * - exit_service_mode: Exit service mode and continue to normal operation
 * - get_status: Get current device status and configuration
 * - get_manifest: Get device capabilities manifest
 * - provision: Store unit_id and cloud credentials
 * - test_wifi: Test Wi-Fi connectivity
 * - test_rfid: Scan for RFID tags
 * - test_cloud: Test cloud API connectivity
 * - test_all: Run all supported tests
 * - customer_reset: Clear user data, preserve provisioning
 * - factory_reset: Full wipe including unit_id
 * - reboot: Reboot the device
 *
 * Phase 6: Service Mode
 */

#include "serial_prov.h"
#include "config_store.h"
#include "supabase_client.h"
#include "wifi_manager.h"
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
#include "driver/uart.h"
#include "driver/usb_serial_jtag.h"
#include "cJSON.h"

#include <string.h>
#include <stdio.h>

static const char *TAG = "SERIAL_PROV";

/*******************************************************************************
 * Configuration
 ******************************************************************************/

#define UART_NUM                UART_NUM_0
#define UART_BAUD_RATE          115200
#define UART_RX_BUF_SIZE        2048
#define UART_TX_BUF_SIZE        0       /* No TX buffer needed for blocking writes */

#define TASK_STACK_SIZE         8192
#define TASK_PRIORITY           5

#define STATUS_SEND_INTERVAL_MS 2000
#define WIFI_CONNECT_TIMEOUT_MS 15000
#define RFID_SCAN_TIMEOUT_MS    5000

/*******************************************************************************
 * Module State
 ******************************************************************************/

static struct {
    bool initialized;
    bool active;
    bool sequence_complete;  /* Set when factory_reset received - signals main to exit prov mode */
    serial_prov_state_t state;
    TaskHandle_t task_handle;
    esp_timer_handle_t status_timer;
    SemaphoreHandle_t mutex;
    serial_prov_state_callback_t callback;
    void *callback_user_data;
    serial_prov_test_result_t test_results;
    bool has_test_results;
    char rx_buffer[SERIAL_PROV_MAX_MSG_LEN];
    size_t rx_len;
} s_prov = {0};

/*******************************************************************************
 * Embedded Manifest (generated from service_manifest.json at compile time)
 ******************************************************************************/

extern const uint8_t service_manifest_start[] asm("_binary_service_manifest_json_start");
extern const uint8_t service_manifest_end[] asm("_binary_service_manifest_json_end");

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void serial_prov_task(void *arg);
static void status_timer_callback(void *arg);
static void process_command(const char *json_str);
static void handle_get_status(cJSON *params);
static void handle_get_manifest(cJSON *params);
static void handle_enter_service_mode(cJSON *params);
static void handle_exit_service_mode(cJSON *params);
static void handle_provision(cJSON *params);
static void handle_test_wifi(cJSON *params);
static void handle_test_rfid(cJSON *params);
static void handle_test_cloud(cJSON *params);
static void handle_test_all(cJSON *params);
static void handle_customer_reset(cJSON *params);
static void handle_factory_reset(cJSON *params);
static void handle_reboot(cJSON *params);
static void set_state(serial_prov_state_t new_state);
static void send_response(const char *status, const char *message, cJSON *data);
static void send_error(const char *error_code, const char *message);

/*******************************************************************************
 * Public API Implementation
 ******************************************************************************/

esp_err_t serial_prov_init(void)
{
    if (s_prov.initialized) {
        return ESP_OK;
    }

    /* Create mutex */
    s_prov.mutex = xSemaphoreCreateMutex();
    if (s_prov.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Install USB Serial JTAG driver for receiving data.
     * On ESP32-C6 DevKitC, the USB port is connected to the USB Serial/JTAG
     * controller, not a regular UART. We need this driver to read input. */
    usb_serial_jtag_driver_config_t usb_serial_config = {
        .rx_buffer_size = UART_RX_BUF_SIZE,
        .tx_buffer_size = UART_RX_BUF_SIZE,
    };

    esp_err_t err = usb_serial_jtag_driver_install(&usb_serial_config);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        /* ESP_ERR_INVALID_STATE means driver already installed, which is OK */
        ESP_LOGE(TAG, "Failed to install USB Serial JTAG driver: %s", esp_err_to_name(err));
        vSemaphoreDelete(s_prov.mutex);
        return err;
    }
    ESP_LOGI(TAG, "USB Serial JTAG driver installed for provisioning input");

    /* Create status timer */
    esp_timer_create_args_t timer_args = {
        .callback = status_timer_callback,
        .arg = NULL,
        .name = "prov_status",
    };
    err = esp_timer_create(&timer_args, &s_prov.status_timer);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create status timer: %s", esp_err_to_name(err));
        vSemaphoreDelete(s_prov.mutex);
        return err;
    }

    s_prov.state = SERIAL_PROV_STATE_IDLE;
    s_prov.initialized = true;

    ESP_LOGI(TAG, "Serial provisioning initialized");
    return ESP_OK;
}

esp_err_t serial_prov_deinit(void)
{
    if (!s_prov.initialized) {
        return ESP_OK;
    }

    serial_prov_stop();

    if (s_prov.status_timer) {
        esp_timer_delete(s_prov.status_timer);
        s_prov.status_timer = NULL;
    }

    if (s_prov.mutex) {
        vSemaphoreDelete(s_prov.mutex);
        s_prov.mutex = NULL;
    }

    s_prov.initialized = false;
    ESP_LOGI(TAG, "Serial provisioning deinitialized");
    return ESP_OK;
}

esp_err_t serial_prov_start(void)
{
    if (!s_prov.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_prov.active) {
        return ESP_OK;  /* Already active */
    }

    xSemaphoreTake(s_prov.mutex, portMAX_DELAY);

    /* Create provisioning task */
    BaseType_t ret = xTaskCreate(
        serial_prov_task,
        "serial_prov",
        TASK_STACK_SIZE,
        NULL,
        TASK_PRIORITY,
        &s_prov.task_handle
    );

    if (ret != pdPASS) {
        xSemaphoreGive(s_prov.mutex);
        ESP_LOGE(TAG, "Failed to create provisioning task");
        return ESP_ERR_NO_MEM;
    }

    s_prov.active = true;
    set_state(SERIAL_PROV_STATE_AWAITING);

    /* Start status timer to send periodic status messages */
    esp_timer_start_periodic(s_prov.status_timer, STATUS_SEND_INTERVAL_MS * 1000);

    /* Set LED to white pulse for provisioning mode */
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);

    xSemaphoreGive(s_prov.mutex);

    ESP_LOGI(TAG, "Serial provisioning started - awaiting commands");
    return ESP_OK;
}

esp_err_t serial_prov_stop(void)
{
    if (!s_prov.active) {
        return ESP_OK;
    }

    xSemaphoreTake(s_prov.mutex, portMAX_DELAY);

    /* Stop status timer */
    esp_timer_stop(s_prov.status_timer);

    /* Stop task */
    if (s_prov.task_handle) {
        vTaskDelete(s_prov.task_handle);
        s_prov.task_handle = NULL;
    }

    s_prov.active = false;
    set_state(SERIAL_PROV_STATE_IDLE);

    xSemaphoreGive(s_prov.mutex);

    ESP_LOGI(TAG, "Serial provisioning stopped");
    return ESP_OK;
}

bool serial_prov_is_active(void)
{
    return s_prov.active;
}

serial_prov_state_t serial_prov_get_state(void)
{
    return s_prov.state;
}

esp_err_t serial_prov_register_callback(serial_prov_state_callback_t callback, void *user_data)
{
    xSemaphoreTake(s_prov.mutex, portMAX_DELAY);
    s_prov.callback = callback;
    s_prov.callback_user_data = user_data;
    xSemaphoreGive(s_prov.mutex);
    return ESP_OK;
}

esp_err_t serial_prov_get_test_results(serial_prov_test_result_t *result)
{
    if (result == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_prov.mutex, portMAX_DELAY);
    if (!s_prov.has_test_results) {
        xSemaphoreGive(s_prov.mutex);
        return ESP_ERR_NOT_FOUND;
    }
    memcpy(result, &s_prov.test_results, sizeof(serial_prov_test_result_t));
    xSemaphoreGive(s_prov.mutex);

    return ESP_OK;
}

bool serial_prov_is_complete(void)
{
    return s_prov.sequence_complete;
}

esp_err_t serial_prov_send_json(const char *json)
{
    if (json == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Send JSON followed by newline via stdout (console).
     * On ESP32-C6 with USB-Serial/JTAG, this goes through the USB interface.
     * Using printf ensures output goes to the same stream as ESP_LOG. */
    printf("%s\n", json);
    fflush(stdout);

    return ESP_OK;
}

/*******************************************************************************
 * Private Functions
 ******************************************************************************/

static void set_state(serial_prov_state_t new_state)
{
    serial_prov_state_t old_state = s_prov.state;
    s_prov.state = new_state;

    if (old_state != new_state) {
        ESP_LOGI(TAG, "State: %d -> %d", old_state, new_state);

        if (s_prov.callback) {
            s_prov.callback(new_state, s_prov.callback_user_data);
        }
    }
}

static void status_timer_callback(void *arg)
{
    (void)arg;

    /* Send status beacon periodically when in service mode */
    if (s_prov.state == SERIAL_PROV_STATE_AWAITING) {
        cJSON *data = cJSON_CreateObject();

        cJSON_AddStringToObject(data, "device_type", "hub");
        cJSON_AddStringToObject(data, "firmware_id", FIRMWARE_ID);
        cJSON_AddStringToObject(data, "firmware_version", FIRMWARE_VERSION);

        /* Include MAC address for device identification */
        uint8_t mac[6];
        if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
            char mac_str[18];
            snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                     mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
            cJSON_AddStringToObject(data, "mac_address", mac_str);
        }

        /* Unit ID (core provisioning identifier) */
        char unit_id[32] = {0};
        if (config_get_unit_id(unit_id, sizeof(unit_id)) == ESP_OK) {
            cJSON_AddStringToObject(data, "unit_id", unit_id);
        } else {
            cJSON_AddNullToObject(data, "unit_id");
        }

        cJSON_AddBoolToObject(data, "cloud_configured", supabase_is_configured());
        cJSON_AddNumberToObject(data, "free_heap", esp_get_free_heap_size());

        send_response("service_mode", NULL, data);
        cJSON_Delete(data);
    }
}

static void serial_prov_task(void *arg)
{
    (void)arg;
    uint8_t byte;

    ESP_LOGI(TAG, "Provisioning task started");

    s_prov.rx_len = 0;
    memset(s_prov.rx_buffer, 0, sizeof(s_prov.rx_buffer));

    while (1) {
        /* Read from USB Serial JTAG driver with timeout.
         * This is the proper way to receive data on ESP32-C6 USB interface. */
        int len = usb_serial_jtag_read_bytes(&byte, 1, pdMS_TO_TICKS(50));

        if (len > 0) {
            if (byte == '\n' || byte == '\r') {
                /* End of message - process if we have content */
                if (s_prov.rx_len > 0) {
                    s_prov.rx_buffer[s_prov.rx_len] = '\0';
                    ESP_LOGI(TAG, "Received command: %s", s_prov.rx_buffer);
                    process_command(s_prov.rx_buffer);
                    s_prov.rx_len = 0;
                }
            } else if (s_prov.rx_len < sizeof(s_prov.rx_buffer) - 1) {
                /* Add byte to buffer */
                s_prov.rx_buffer[s_prov.rx_len++] = (char)byte;
            } else {
                /* Buffer overflow - discard */
                ESP_LOGW(TAG, "RX buffer overflow, discarding");
                s_prov.rx_len = 0;
            }
        }

        /* Small delay to allow IDLE task to run and feed watchdog */
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

static void process_command(const char *json_str)
{
    cJSON *root = cJSON_Parse(json_str);
    if (root == NULL) {
        send_error("parse_error", "Invalid JSON");
        return;
    }

    cJSON *cmd = cJSON_GetObjectItem(root, "cmd");
    if (!cJSON_IsString(cmd)) {
        send_error("invalid_command", "Missing 'cmd' field");
        cJSON_Delete(root);
        return;
    }

    cJSON *params = cJSON_GetObjectItem(root, "data");

    const char *cmd_str = cmd->valuestring;
    ESP_LOGI(TAG, "Processing command: %s", cmd_str);

    if (strcmp(cmd_str, "get_status") == 0) {
        handle_get_status(params);
    } else if (strcmp(cmd_str, "get_manifest") == 0) {
        handle_get_manifest(params);
    } else if (strcmp(cmd_str, "enter_service_mode") == 0) {
        handle_enter_service_mode(params);
    } else if (strcmp(cmd_str, "exit_service_mode") == 0) {
        handle_exit_service_mode(params);
    } else if (strcmp(cmd_str, "provision") == 0) {
        handle_provision(params);
    } else if (strcmp(cmd_str, "test_wifi") == 0) {
        handle_test_wifi(params);
    } else if (strcmp(cmd_str, "test_rfid") == 0) {
        handle_test_rfid(params);
    } else if (strcmp(cmd_str, "test_cloud") == 0) {
        handle_test_cloud(params);
    } else if (strcmp(cmd_str, "test_all") == 0) {
        handle_test_all(params);
    } else if (strcmp(cmd_str, "customer_reset") == 0) {
        handle_customer_reset(params);
    } else if (strcmp(cmd_str, "factory_reset") == 0) {
        handle_factory_reset(params);
    } else if (strcmp(cmd_str, "reboot") == 0) {
        handle_reboot(params);
    } else {
        send_error("unknown_command", "Unknown command");
    }

    cJSON_Delete(root);
}

static void send_response(const char *status, const char *message, cJSON *data)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "status", status);

    if (message != NULL) {
        cJSON_AddStringToObject(root, "message", message);
    }

    if (data != NULL) {
        cJSON_AddItemToObject(root, "data", cJSON_Duplicate(data, true));
    }

    char *json = cJSON_PrintUnformatted(root);
    if (json) {
        serial_prov_send_json(json);
        cJSON_free(json);
    }

    cJSON_Delete(root);
}

static void send_error(const char *error_code, const char *message)
{
    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "error_code", error_code);
    send_response("error", message, data);
    cJSON_Delete(data);
}

/*******************************************************************************
 * Command Handlers
 ******************************************************************************/

static void handle_get_status(cJSON *params)
{
    (void)params;

    cJSON *data = cJSON_CreateObject();

    /* Device info */
    cJSON_AddStringToObject(data, "device_type", "hub");
    cJSON_AddStringToObject(data, "firmware_version", FIRMWARE_VERSION);

    /* MAC address (unique hardware identifier) */
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
        char mac_str[18];
        snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        cJSON_AddStringToObject(data, "mac_address", mac_str);
    }

    /* Unit ID (core provisioning identifier - stored in config) */
    char unit_id[32] = {0};
    if (config_get_unit_id(unit_id, sizeof(unit_id)) == ESP_OK) {
        cJSON_AddStringToObject(data, "unit_id", unit_id);
    } else {
        cJSON_AddNullToObject(data, "unit_id");
    }

    /* Cloud configuration status */
    cJSON_AddBoolToObject(data, "cloud_configured", supabase_is_configured());
    if (supabase_is_configured()) {
        supabase_config_t sb_config;
        if (supabase_get_config(&sb_config) == ESP_OK) {
            cJSON_AddStringToObject(data, "cloud_url", sb_config.url);
        }
    }

    /* Wi-Fi status */
    cJSON_AddBoolToObject(data, "wifi_configured", config_has_wifi());
    cJSON_AddBoolToObject(data, "wifi_connected", wifi_is_connected());
    if (wifi_is_connected()) {
        char ip[16];
        wifi_get_ip_string(ip, sizeof(ip));
        cJSON_AddStringToObject(data, "ip_address", ip);

        wifi_manager_status_t wifi_status;
        if (wifi_get_status(&wifi_status) == ESP_OK) {
            cJSON_AddStringToObject(data, "wifi_ssid", wifi_status.ssid);
            cJSON_AddNumberToObject(data, "wifi_rssi", wifi_status.rssi);
        }
    }

    /* System info */
    cJSON_AddNumberToObject(data, "free_heap", esp_get_free_heap_size());
    cJSON_AddNumberToObject(data, "uptime_ms", esp_timer_get_time() / 1000);

    /* Test results if available */
    if (s_prov.has_test_results) {
        cJSON *tests = cJSON_CreateObject();
        cJSON_AddBoolToObject(tests, "wifi_ok", s_prov.test_results.wifi_ok);
        cJSON_AddBoolToObject(tests, "rfid_ok", s_prov.test_results.rfid_ok);
        cJSON_AddBoolToObject(tests, "cloud_ok", s_prov.test_results.cloud_ok);
        cJSON_AddItemToObject(data, "last_tests", tests);
    }

    send_response("ok", NULL, data);
    cJSON_Delete(data);
}

static void handle_get_manifest(cJSON *params)
{
    (void)params;

    /* Parse the embedded manifest JSON */
    size_t manifest_len = service_manifest_end - service_manifest_start;
    cJSON *manifest = cJSON_ParseWithLength((const char *)service_manifest_start, manifest_len);

    if (manifest == NULL) {
        send_error("manifest_error", "Failed to parse embedded manifest");
        return;
    }

    send_response("ok", NULL, manifest);
    cJSON_Delete(manifest);
}

static void handle_enter_service_mode(cJSON *params)
{
    (void)params;

    /* This command is used during the boot window to enter service mode on
     * provisioned devices. If we're already in service mode, just acknowledge. */
    if (s_prov.active) {
        send_response("ok", "Already in service mode", NULL);
        return;
    }

    /* Start service mode */
    esp_err_t err = serial_prov_start();
    if (err != ESP_OK) {
        send_error("start_failed", "Failed to start service mode");
        return;
    }

    ESP_LOGI(TAG, "Entered service mode via command");
    send_response("ok", "Service mode entered", NULL);
}

static void handle_exit_service_mode(cJSON *params)
{
    (void)params;

    if (!s_prov.active) {
        send_error("not_in_service_mode", "Device is not in service mode");
        return;
    }

    ESP_LOGI(TAG, "Exit service mode requested");

    /* Mark sequence as complete - signals main loop to exit service mode */
    s_prov.sequence_complete = true;

    send_response("ok", "Exiting service mode - device will continue to normal operation", NULL);

    /* Give time for response to be sent before stopping */
    vTaskDelay(pdMS_TO_TICKS(200));
}

static void handle_provision(cJSON *params)
{
    if (params == NULL) {
        send_error("missing_data", "Provisioning data required");
        return;
    }

    set_state(SERIAL_PROV_STATE_PROVISIONING);
    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_PULSE, 1000);

    /* Extract required fields (per manifest: unit_id, cloud_url, cloud_anon_key) */
    cJSON *unit_id = cJSON_GetObjectItem(params, "unit_id");
    cJSON *cloud_url = cJSON_GetObjectItem(params, "cloud_url");
    cJSON *cloud_anon_key = cJSON_GetObjectItem(params, "cloud_anon_key");

    if (!cJSON_IsString(unit_id) || !cJSON_IsString(cloud_url) ||
        !cJSON_IsString(cloud_anon_key)) {
        send_error("missing_fields", "Required: unit_id, cloud_url, cloud_anon_key");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Extract optional fields */
    cJSON *cloud_device_secret = cJSON_GetObjectItem(params, "cloud_device_secret");
    cJSON *wifi_ssid = cJSON_GetObjectItem(params, "wifi_ssid");
    cJSON *wifi_password = cJSON_GetObjectItem(params, "wifi_password");

    esp_err_t err;

    /* Store unit_id as the core provisioning identifier */
    err = config_set_unit_id(unit_id->valuestring);
    if (err != ESP_OK) {
        send_error("storage_error", "Failed to store unit_id");
        set_state(SERIAL_PROV_STATE_ERROR);
        led_flash(LED_COLOR_RED, 500);
        return;
    }
    ESP_LOGI(TAG, "Unit ID stored: %s", unit_id->valuestring);

    /* Store cloud (Supabase) configuration */
    supabase_config_t sb_config = {0};
    strncpy(sb_config.unit_id, unit_id->valuestring, sizeof(sb_config.unit_id) - 1);
    strncpy(sb_config.url, cloud_url->valuestring, sizeof(sb_config.url) - 1);
    strncpy(sb_config.anon_key, cloud_anon_key->valuestring, sizeof(sb_config.anon_key) - 1);

    if (cJSON_IsString(cloud_device_secret)) {
        strncpy(sb_config.device_secret, cloud_device_secret->valuestring,
                sizeof(sb_config.device_secret) - 1);
    }

    err = supabase_set_config(&sb_config);
    if (err != ESP_OK) {
        send_error("storage_error", "Failed to store cloud config");
        set_state(SERIAL_PROV_STATE_ERROR);
        led_flash(LED_COLOR_RED, 500);
        return;
    }
    ESP_LOGI(TAG, "Cloud config stored for: %s", cloud_url->valuestring);

    /* Store Wi-Fi credentials if provided */
    if (cJSON_IsString(wifi_ssid)) {
        const char *password = cJSON_IsString(wifi_password) ? wifi_password->valuestring : "";
        err = config_set_wifi(wifi_ssid->valuestring, password);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Failed to store Wi-Fi credentials: %s", esp_err_to_name(err));
            /* Continue anyway - Wi-Fi is optional for provisioning */
        } else {
            ESP_LOGI(TAG, "Wi-Fi credentials stored for: %s", wifi_ssid->valuestring);
        }
    }

    /* Mark as factory provisioned */
    err = config_set_provisioned(true);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to set provisioned flag: %s", esp_err_to_name(err));
    }

    set_state(SERIAL_PROV_STATE_COMPLETE);
    led_flash(LED_COLOR_GREEN, 500);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);

    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "unit_id", unit_id->valuestring);
    cJSON_AddBoolToObject(data, "cloud_stored", true);
    cJSON_AddBoolToObject(data, "wifi_stored", cJSON_IsString(wifi_ssid));

    send_response("provisioned", "Device provisioned successfully", data);
    cJSON_Delete(data);

    /* Return to awaiting state for testing */
    set_state(SERIAL_PROV_STATE_AWAITING);
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_test_wifi(cJSON *params)
{
    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_BLINK_FAST, 250);

    /* Check if credentials provided in params or use stored */
    const char *ssid = NULL;
    const char *password = NULL;

    if (params != NULL) {
        cJSON *j_ssid = cJSON_GetObjectItem(params, "ssid");
        cJSON *j_password = cJSON_GetObjectItem(params, "password");

        if (cJSON_IsString(j_ssid)) {
            ssid = j_ssid->valuestring;
            password = cJSON_IsString(j_password) ? j_password->valuestring : "";

            /* Store if provided */
            config_set_wifi(ssid, password);
        }
    }

    /* Initialize Wi-Fi if needed */
    esp_err_t err = wifi_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        send_error("wifi_init_failed", "Failed to initialize Wi-Fi");
        set_state(SERIAL_PROV_STATE_AWAITING);
        return;
    }

    /* Give Wi-Fi subsystem time to fully initialize after wifi_init() */
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Connect using stored credentials */
    if (ssid != NULL) {
        err = wifi_connect(ssid, password);
    } else {
        err = wifi_connect_stored();
    }

    if (err != ESP_OK) {
        /* Provide specific error message based on error code */
        if (err == ESP_ERR_NOT_FOUND) {
            send_error("no_credentials", "No Wi-Fi credentials stored - provision device first");
        } else if (err == ESP_ERR_INVALID_STATE) {
            send_error("wifi_not_ready", "Wi-Fi subsystem not ready - try again");
        } else if (err == ESP_ERR_INVALID_ARG) {
            send_error("invalid_credentials", "Invalid Wi-Fi credentials format");
        } else {
            char msg[64];
            snprintf(msg, sizeof(msg), "Wi-Fi connect failed: %s", esp_err_to_name(err));
            send_error("connect_failed", msg);
        }
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Wait for connection with timeout */
    int64_t start = esp_timer_get_time();
    while (!wifi_is_connected()) {
        if ((esp_timer_get_time() - start) > (WIFI_CONNECT_TIMEOUT_MS * 1000)) {
            s_prov.test_results.wifi_ok = false;
            s_prov.has_test_results = true;

            send_error("wifi_timeout", "Wi-Fi connection timed out");
            set_state(SERIAL_PROV_STATE_AWAITING);
            led_flash(LED_COLOR_RED, 500);
            vTaskDelay(pdMS_TO_TICKS(550));
            led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
            return;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    /* Connected - get details */
    s_prov.test_results.wifi_ok = true;
    wifi_get_ip_string(s_prov.test_results.wifi_ip, sizeof(s_prov.test_results.wifi_ip));

    wifi_manager_status_t status;
    if (wifi_get_status(&status) == ESP_OK) {
        strncpy(s_prov.test_results.wifi_ssid, status.ssid,
                sizeof(s_prov.test_results.wifi_ssid) - 1);
        s_prov.test_results.wifi_rssi = status.rssi;
    }
    s_prov.has_test_results = true;

    cJSON *data = cJSON_CreateObject();
    cJSON_AddBoolToObject(data, "connected", true);
    cJSON_AddStringToObject(data, "ssid", s_prov.test_results.wifi_ssid);
    cJSON_AddStringToObject(data, "ip", s_prov.test_results.wifi_ip);
    cJSON_AddNumberToObject(data, "rssi", s_prov.test_results.wifi_rssi);

    led_flash(LED_COLOR_GREEN, 500);
    send_response("ok", "Wi-Fi connected", data);
    cJSON_Delete(data);

    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_test_rfid(cJSON *params)
{
    (void)params;

    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_CYAN, LED_PATTERN_BLINK_FAST, 250);

    /* Initialize RFID if needed */
    esp_err_t err = yrm100_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        send_error("rfid_init_failed", "Failed to initialize RFID");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Enable module */
    yrm100_enable(true);
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Get firmware version to verify communication */
    char version[32] = {0};
    err = yrm100_get_firmware_version(version, sizeof(version));
    if (err != ESP_OK) {
        yrm100_enable(false);
        s_prov.test_results.rfid_ok = false;
        s_prov.has_test_results = true;

        send_error("rfid_comm_failed", "RFID module not responding");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    ESP_LOGI(TAG, "RFID module firmware: %s", version);

    /* Scan for tags */
    uint8_t tags_found = 0;
    char last_epc[25] = {0};
    int64_t start = esp_timer_get_time();

    while ((esp_timer_get_time() - start) < (RFID_SCAN_TIMEOUT_MS * 1000)) {
        rfid_tag_t tag;
        err = yrm100_single_poll_with_data(&tag);

        if (err == ESP_OK) {
            if (tag.is_saturday_tag) {
                tags_found++;
                rfid_epc_to_hex_string(tag.epc, tag.epc_len, last_epc, sizeof(last_epc));
                ESP_LOGI(TAG, "Found Saturday tag: %s", last_epc);
                led_flash(LED_COLOR_GREEN, 100);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(200));
    }

    yrm100_enable(false);

    /* Store results */
    s_prov.test_results.rfid_ok = (tags_found > 0);
    s_prov.test_results.rfid_tags_found = tags_found;
    strncpy(s_prov.test_results.rfid_epc, last_epc, sizeof(s_prov.test_results.rfid_epc) - 1);
    s_prov.has_test_results = true;

    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "firmware", version);
    cJSON_AddNumberToObject(data, "tags_found", tags_found);
    if (tags_found > 0) {
        cJSON_AddStringToObject(data, "last_epc", last_epc);
    }

    if (tags_found > 0) {
        led_flash(LED_COLOR_GREEN, 500);
        send_response("ok", "RFID scan complete", data);
    } else {
        led_flash(LED_COLOR_ORANGE, 500);
        send_response("ok", "RFID working but no Saturday tags found", data);
    }

    cJSON_Delete(data);
    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_test_cloud(cJSON *params)
{
    (void)params;

    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_MAGENTA, LED_PATTERN_BLINK_FAST, 250);

    /* Check if cloud is configured */
    if (!supabase_is_configured()) {
        send_error("not_configured", "Cloud not configured - run provision first");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Check Wi-Fi connection */
    if (!wifi_is_connected()) {
        send_error("no_wifi", "Wi-Fi not connected - run test_wifi first");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Get unit ID from config */
    char unit_id[32] = {0};
    config_get_unit_id(unit_id, sizeof(unit_id));

    /* Send test heartbeat - must match hub_heartbeats table schema */
    char json_body[512];
    snprintf(json_body, sizeof(json_body),
             "{\"unit_id\":\"%s\",\"firmware_version\":\"%s\","
             "\"free_heap\":%lu,\"uptime_sec\":%llu}",
             unit_id, FIRMWARE_VERSION,
             (unsigned long)esp_get_free_heap_size(),
             (unsigned long long)(esp_timer_get_time() / 1000000));

    int64_t start = esp_timer_get_time();
    supabase_response_t response = {0};
    esp_err_t err = supabase_post("hub_heartbeats", json_body, &response, 10000);
    int64_t latency = (esp_timer_get_time() - start) / 1000;

    s_prov.test_results.cloud_latency_ms = latency;

    if (err != ESP_OK) {
        s_prov.test_results.cloud_ok = false;
        s_prov.test_results.cloud_status = 0;
        s_prov.has_test_results = true;

        send_error("request_failed", "Cloud API request failed");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    s_prov.test_results.cloud_status = response.status_code;
    s_prov.test_results.cloud_ok = (response.status_code >= 200 && response.status_code < 300);
    s_prov.has_test_results = true;

    cJSON *data = cJSON_CreateObject();
    cJSON_AddNumberToObject(data, "status_code", response.status_code);
    cJSON_AddNumberToObject(data, "latency_ms", latency);
    cJSON_AddStringToObject(data, "unit_id", unit_id);

    supabase_response_free(&response);

    if (s_prov.test_results.cloud_ok) {
        led_flash(LED_COLOR_GREEN, 500);
        send_response("ok", "Cloud API connection successful", data);
    } else {
        led_flash(LED_COLOR_RED, 500);
        send_response("error", "Cloud API returned error status", data);
    }

    cJSON_Delete(data);
    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_test_all(cJSON *params)
{
    ESP_LOGI(TAG, "Running all tests...");

    /* Run Wi-Fi test */
    handle_test_wifi(params);
    vTaskDelay(pdMS_TO_TICKS(1000));

    /* Run RFID test */
    handle_test_rfid(NULL);
    vTaskDelay(pdMS_TO_TICKS(1000));

    /* Run cloud test (only if Wi-Fi connected) */
    if (s_prov.test_results.wifi_ok) {
        handle_test_cloud(NULL);
    }

    /* Send summary */
    vTaskDelay(pdMS_TO_TICKS(500));

    cJSON *data = cJSON_CreateObject();
    cJSON_AddBoolToObject(data, "wifi_ok", s_prov.test_results.wifi_ok);
    cJSON_AddBoolToObject(data, "rfid_ok", s_prov.test_results.rfid_ok);
    cJSON_AddBoolToObject(data, "cloud_ok", s_prov.test_results.cloud_ok);

    bool all_passed = s_prov.test_results.wifi_ok &&
                      s_prov.test_results.rfid_ok &&
                      s_prov.test_results.cloud_ok;

    cJSON_AddBoolToObject(data, "all_passed", all_passed);

    if (all_passed) {
        led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
        send_response("ok", "All tests passed", data);
    } else {
        led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);
        send_response("failed", "Some tests failed", data);
    }

    cJSON_Delete(data);
    set_state(SERIAL_PROV_STATE_AWAITING);
}

static void handle_customer_reset(cJSON *params)
{
    (void)params;

    ESP_LOGW(TAG, "Customer reset requested - clearing user data, preserving factory provisioning");
    led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 200);

    /* Send response before reset */
    send_response("ok", "Customer reset in progress - device will reboot", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Perform customer reset:
     * - Clears Wi-Fi credentials
     * - Clears provisioned flag
     * - PRESERVES unit_id, cloud URL, cloud keys, device secret
     * This prepares device for customer BLE provisioning */
    esp_err_t err = config_customer_reset();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Customer reset failed: %s", esp_err_to_name(err));
    }

    /* Reboot */
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static void handle_factory_reset(cJSON *params)
{
    (void)params;

    ESP_LOGW(TAG, "FACTORY RESET - erasing ALL configuration including unit_id!");
    led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 200);

    /* Send response before reset */
    send_response("ok", "Factory reset in progress - ALL data will be erased, device will reboot", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    /* Perform full factory reset:
     * - Erases ALL NVS data
     * - Clears unit_id, cloud config, Wi-Fi, everything
     * - Device will need to be completely re-provisioned */
    esp_err_t err = config_factory_reset();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Factory reset failed: %s", esp_err_to_name(err));
    }

    /* Reboot */
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static void handle_reboot(cJSON *params)
{
    (void)params;

    ESP_LOGI(TAG, "Reboot requested");

    send_response("ok", "Rebooting...", NULL);
    vTaskDelay(pdMS_TO_TICKS(500));

    esp_restart();
}
