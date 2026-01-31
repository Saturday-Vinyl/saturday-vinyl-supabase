/**
 * @file serial_prov.c
 * @brief Service Mode for factory provisioning and servicing via Saturday Admin app
 *
 * Implements the Saturday Service Mode Protocol for factory provisioning, testing,
 * and device servicing. Uses USB serial for communication with the Admin desktop app.
 *
 * Service Mode Protocol v2.2 - Commands supported:
 * - enter_service_mode: Enter service mode (during boot window)
 * - exit_service_mode: Exit service mode and continue to normal operation
 * - get_status: Get current device status and configuration (includes Thread credentials)
 * - get_manifest: Get device capabilities manifest
 * - provision: Store unit_id and cloud credentials
 * - test_wifi: Test Wi-Fi connectivity
 * - test_rfid: Scan for RFID tags
 * - test_cloud: Test cloud API connectivity
 * - test_thread: Test Thread Border Router (generates creds if needed, starts BR)
 * - test_all: Run all supported tests
 * - customer_reset: Clear user data, preserve provisioning
 * - factory_reset: Full wipe including unit_id
 * - reboot: Reboot the device
 *
 * Phase 6: Service Mode
 * Phase 8: Thread Border Router integration
 */

#include "sdkconfig.h"

#include "serial_prov.h"
#include "app_config.h"
#include "config_store.h"
#include "supabase_client.h"
#include "wifi_manager.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "led_manager.h"
#include "ota_manager.h"
#include "esp_heap_caps.h"

/* 2-SoC Architecture: Thread is handled by H2 co-processor.
 * Thread credentials will be retrieved via UART from H2.
 * TODO: Implement H2 communication in Phase S3-6.
 * For now, Thread-related functions are stubbed. */
#define THREAD_NOT_AVAILABLE_ON_S3 1

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
    /* Background listener state (always-listening mode) */
    bool background_listener_active;
    TaskHandle_t background_task_handle;
    char bg_rx_buffer[SERIAL_PROV_MAX_MSG_LEN];
    size_t bg_rx_len;
    /* Current command ID for response correlation (Device Command Protocol v1.3) */
    char current_cmd_id[64];
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
static void background_listener_task(void *arg);
static void status_timer_callback(void *arg);
static void process_command(const char *json_str);
static void process_background_command(const char *json_str);
/* Core commands (Device Command Protocol v1.3) */
static void handle_get_status(cJSON *params);
static void handle_get_capabilities(cJSON *params);
static void handle_reboot(cJSON *params);
static void handle_consumer_reset(cJSON *params);
static void handle_factory_reset(cJSON *params);
/* Provisioning commands */
static void handle_factory_provision(cJSON *params);
static void handle_set_provision_data(cJSON *params);
static void handle_get_provision_data(cJSON *params);
/* Testing commands */
static void handle_run_test(cJSON *root);  /* Takes root to access capability/test_name */
/* OTA commands */
static void handle_ota_update(cJSON *params);
static void handle_check_ota(cJSON *params);
static void handle_get_ota_status(cJSON *params);
/* Legacy commands (backwards compatibility) */
static void handle_get_manifest(cJSON *params);
static void handle_enter_service_mode(cJSON *params);
static void handle_exit_service_mode(cJSON *params);
static void handle_provision(cJSON *params);
static void handle_test_wifi(cJSON *params);
static void handle_test_rfid(cJSON *params);
static void handle_test_cloud(cJSON *params);
static void handle_test_thread(cJSON *params);
static void handle_test_all(cJSON *params);
static void handle_customer_reset(cJSON *params);
static void handle_start_ota(cJSON *params);
/* Internal helpers */
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
     * On ESP32-S3 DevKitC, the USB port is connected to the USB Serial/JTAG
     * controller, not a regular UART. We need this driver to read input.
     * Note: CONFIG_ESP_CONSOLE_NONE must be set to avoid conflicts with VFS. */
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

bool serial_prov_wait_for_entry(uint32_t timeout_ms)
{
    if (!s_prov.initialized) {
        ESP_LOGE(TAG, "serial_prov not initialized");
        return false;
    }

    ESP_LOGI(TAG, "Listening for service mode entry command (%lu ms window)...",
             (unsigned long)timeout_ms);

    /* Buffer for reading serial data */
    char rx_buffer[256];
    size_t rx_len = 0;
    uint8_t byte;

    int64_t start_time = esp_timer_get_time();
    int64_t timeout_us = (int64_t)timeout_ms * 1000;

    while ((esp_timer_get_time() - start_time) < timeout_us) {
        /* Read from USB Serial JTAG driver with short timeout */
        int len = usb_serial_jtag_read_bytes(&byte, 1, pdMS_TO_TICKS(50));

        if (len > 0) {
            if (byte == '\n' || byte == '\r') {
                /* End of message - check if it's enter_service_mode */
                if (rx_len > 0) {
                    rx_buffer[rx_len] = '\0';
                    ESP_LOGI(TAG, "Received during boot window: %s", rx_buffer);

                    /* Parse JSON and check for enter_service_mode command */
                    cJSON *root = cJSON_Parse(rx_buffer);
                    if (root != NULL) {
                        cJSON *cmd = cJSON_GetObjectItem(root, "cmd");
                        if (cJSON_IsString(cmd) &&
                            strcmp(cmd->valuestring, "enter_service_mode") == 0) {
                            cJSON_Delete(root);

                            ESP_LOGI(TAG, "Service mode entry command received - entering service mode");

                            /* Start service mode */
                            esp_err_t err = serial_prov_start();
                            if (err == ESP_OK) {
                                /* Send acknowledgment */
                                cJSON *resp = cJSON_CreateObject();
                                cJSON_AddStringToObject(resp, "status", "ok");
                                cJSON_AddStringToObject(resp, "message", "Entered service mode");
                                char *json = cJSON_PrintUnformatted(resp);
                                if (json) {
                                    serial_prov_send_json(json);
                                    cJSON_free(json);
                                }
                                cJSON_Delete(resp);
                                return true;
                            } else {
                                ESP_LOGE(TAG, "Failed to start service mode: %s",
                                         esp_err_to_name(err));
                            }
                        }
                        cJSON_Delete(root);
                    }
                    rx_len = 0;
                }
            } else if (rx_len < sizeof(rx_buffer) - 1) {
                /* Add byte to buffer */
                rx_buffer[rx_len++] = (char)byte;
            } else {
                /* Buffer overflow - discard */
                rx_len = 0;
            }
        }

        /* Allow other tasks to run */
        vTaskDelay(pdMS_TO_TICKS(5));
    }

    ESP_LOGI(TAG, "Service mode entry window expired - proceeding to standard mode");
    return false;
}

esp_err_t serial_prov_send_json(const char *json)
{
    if (json == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    /* Send JSON followed by newline via USB Serial JTAG driver.
     * We use the driver directly (not printf/stdout) because:
     * 1. CONFIG_ESP_CONSOLE_NONE disables console VFS ownership of the USB Serial JTAG
     * 2. This ensures reliable TX alongside our usb_serial_jtag_read_bytes() RX
     * 3. ESP_LOG output still works via ROM functions that write directly to hardware FIFO */
    size_t len = strlen(json);
    int written = usb_serial_jtag_write_bytes((const uint8_t *)json, len, pdMS_TO_TICKS(100));
    usb_serial_jtag_write_bytes((const uint8_t *)"\n", 1, pdMS_TO_TICKS(100));

    return (written == (int)len) ? ESP_OK : ESP_FAIL;
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

    /* Extract command ID for response correlation (Device Command Protocol v1.3) */
    cJSON *id = cJSON_GetObjectItem(root, "id");
    if (cJSON_IsString(id) && id->valuestring) {
        strncpy(s_prov.current_cmd_id, id->valuestring, sizeof(s_prov.current_cmd_id) - 1);
        s_prov.current_cmd_id[sizeof(s_prov.current_cmd_id) - 1] = '\0';
    } else {
        s_prov.current_cmd_id[0] = '\0';  /* No ID provided */
    }

    cJSON *cmd = cJSON_GetObjectItem(root, "cmd");
    if (!cJSON_IsString(cmd)) {
        send_error("invalid_command", "Missing 'cmd' field");
        cJSON_Delete(root);
        return;
    }

    /* Support both "params" (Device Command Protocol v1.3) and "data" (legacy) */
    cJSON *params = cJSON_GetObjectItem(root, "params");
    if (params == NULL) {
        params = cJSON_GetObjectItem(root, "data");  /* Fallback for legacy */
    }

    const char *cmd_str = cmd->valuestring;
    ESP_LOGI(TAG, "Processing command: %s", cmd_str);

    /***************************************************************************
     * Device Command Protocol v1.3 - Core Commands
     **************************************************************************/
    if (strcmp(cmd_str, "get_status") == 0) {
        handle_get_status(params);
    } else if (strcmp(cmd_str, "get_capabilities") == 0) {
        handle_get_capabilities(params);
    } else if (strcmp(cmd_str, "reboot") == 0) {
        handle_reboot(params);
    } else if (strcmp(cmd_str, "consumer_reset") == 0) {
        handle_consumer_reset(params);
    } else if (strcmp(cmd_str, "factory_reset") == 0) {
        handle_factory_reset(params);
    }
    /***************************************************************************
     * Device Command Protocol v1.3 - Provisioning Commands
     **************************************************************************/
    else if (strcmp(cmd_str, "factory_provision") == 0) {
        handle_factory_provision(params);
    } else if (strcmp(cmd_str, "set_provision_data") == 0) {
        handle_set_provision_data(params);
    } else if (strcmp(cmd_str, "get_provision_data") == 0) {
        handle_get_provision_data(params);
    }
    /***************************************************************************
     * Device Command Protocol v1.3 - Testing Commands
     **************************************************************************/
    else if (strcmp(cmd_str, "run_test") == 0) {
        handle_run_test(root);  /* Pass root to access capability/test_name */
    }
    /***************************************************************************
     * Device Command Protocol v1.3 - OTA Commands
     **************************************************************************/
    else if (strcmp(cmd_str, "ota_update") == 0) {
        handle_ota_update(params);
    }
    /***************************************************************************
     * Legacy Commands (backwards compatibility with Service Mode Protocol)
     **************************************************************************/
    else if (strcmp(cmd_str, "get_manifest") == 0) {
        handle_get_manifest(params);  /* Alias: get_capabilities */
    } else if (strcmp(cmd_str, "enter_service_mode") == 0) {
        handle_enter_service_mode(params);  /* No-op in always-listening mode */
    } else if (strcmp(cmd_str, "exit_service_mode") == 0) {
        handle_exit_service_mode(params);  /* No-op in always-listening mode */
    } else if (strcmp(cmd_str, "provision") == 0) {
        handle_provision(params);  /* Legacy: use factory_provision */
    } else if (strcmp(cmd_str, "test_wifi") == 0) {
        handle_test_wifi(params);  /* Legacy: use run_test */
    } else if (strcmp(cmd_str, "test_rfid") == 0) {
        handle_test_rfid(params);  /* Legacy: use run_test */
    } else if (strcmp(cmd_str, "test_cloud") == 0) {
        handle_test_cloud(params);  /* Legacy: use run_test */
    } else if (strcmp(cmd_str, "test_thread") == 0) {
        handle_test_thread(params);  /* Legacy: use run_test */
    } else if (strcmp(cmd_str, "test_all") == 0) {
        handle_test_all(params);  /* Legacy: use run_test */
    } else if (strcmp(cmd_str, "customer_reset") == 0) {
        handle_customer_reset(params);  /* Legacy: use consumer_reset */
    } else if (strcmp(cmd_str, "check_ota") == 0) {
        handle_check_ota(params);
    } else if (strcmp(cmd_str, "start_ota") == 0) {
        handle_start_ota(params);  /* Legacy: use ota_update */
    } else if (strcmp(cmd_str, "get_ota_status") == 0) {
        handle_get_ota_status(params);
    } else {
        send_error("invalid_command", "Unknown command");
    }

    cJSON_Delete(root);
}

static void send_response(const char *status, const char *message, cJSON *data)
{
    cJSON *root = cJSON_CreateObject();

    /* Include command ID for response correlation (Device Command Protocol v1.3) */
    if (s_prov.current_cmd_id[0] != '\0') {
        cJSON_AddStringToObject(root, "id", s_prov.current_cmd_id);
    }

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

    /* Device info - use values from firmware JSON schema (app_config.h) */
    cJSON_AddStringToObject(data, "device_type", DEVICE_TYPE);
    cJSON_AddStringToObject(data, "firmware_version", FW_VERSION_STRING);

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

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    /* Thread Border Router credentials (Phase 8)
     * These are generated on first boot and must be captured during factory
     * provisioning for upload to Supabase. The mobile app retrieves them from
     * the cloud when provisioning crates to join this hub's Thread network.
     *
     * Ensure credentials exist (generate if needed) before trying to read them.
     * This allows get_status to work during service mode before Thread BR starts. */
    thread_br_ensure_credentials();

    thread_network_credentials_t thread_creds;
    if (thread_br_get_credentials(&thread_creds) == ESP_OK) {
        cJSON *thread = cJSON_CreateObject();

        cJSON_AddStringToObject(thread, "network_name", thread_creds.network_name);
        cJSON_AddNumberToObject(thread, "pan_id", thread_creds.pan_id);
        cJSON_AddNumberToObject(thread, "channel", thread_creds.channel);

        /* Network key as hex string (32 chars) */
        char network_key_hex[33];
        thread_br_get_network_key_hex(network_key_hex, sizeof(network_key_hex));
        cJSON_AddStringToObject(thread, "network_key", network_key_hex);

        /* Extended PAN ID as hex string (16 chars) */
        char extpanid_hex[17];
        thread_br_get_extpanid_hex(extpanid_hex, sizeof(extpanid_hex));
        cJSON_AddStringToObject(thread, "extended_pan_id", extpanid_hex);

        /* Mesh-local prefix as hex string (16 chars) */
        char mesh_local_hex[17];
        for (int i = 0; i < THREAD_MESH_LOCAL_PREFIX_LEN; i++) {
            snprintf(&mesh_local_hex[i * 2], 3, "%02x",
                     thread_creds.mesh_local_prefix[i]);
        }
        cJSON_AddStringToObject(thread, "mesh_local_prefix", mesh_local_hex);

        /* PSKc as hex string (32 chars) - used for commissioner authentication */
        char pskc_hex[33];
        uint8_t *pskc_bytes = (uint8_t *)thread_creds.pskc;
        for (int i = 0; i < 16; i++) {
            snprintf(&pskc_hex[i * 2], 3, "%02x", pskc_bytes[i]);
        }
        cJSON_AddStringToObject(thread, "pskc", pskc_hex);

        cJSON_AddItemToObject(data, "thread", thread);
    } else {
        /* Thread not initialized yet - include null to indicate it's expected */
        cJSON_AddNullToObject(data, "thread");
    }
#endif /* CONFIG_OPENTHREAD_ENABLED */

    /* System info - match heartbeat format per Device Command Protocol v1.3 */
    cJSON_AddNumberToObject(data, "free_heap", esp_get_free_heap_size());
    cJSON_AddNumberToObject(data, "min_free_heap", esp_get_minimum_free_heap_size());
    cJSON_AddNumberToObject(data, "largest_free_block", heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
    cJSON_AddNumberToObject(data, "uptime_sec", (uint32_t)(esp_timer_get_time() / 1000000));

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

/*******************************************************************************
 * Device Command Protocol v1.3 - Core Commands
 ******************************************************************************/

static void handle_get_capabilities(cJSON *params)
{
    /* Alias for get_manifest - returns device capability manifest */
    handle_get_manifest(params);
}

static void handle_consumer_reset(cJSON *params)
{
    /* Alias for customer_reset - clears consumer data, preserves factory config */
    handle_customer_reset(params);
}

/*******************************************************************************
 * Device Command Protocol v1.3 - Provisioning Commands
 ******************************************************************************/

static void handle_factory_provision(cJSON *params)
{
    if (params == NULL) {
        send_error("missing_params", "Parameters required");
        return;
    }

    /* Accept both "serial_number" (protocol) and "unit_id" (legacy) */
    cJSON *serial_number = cJSON_GetObjectItem(params, "serial_number");
    if (serial_number == NULL) {
        serial_number = cJSON_GetObjectItem(params, "unit_id");  /* Legacy fallback */
    }

    cJSON *name = cJSON_GetObjectItem(params, "name");
    cJSON *cloud_url = cJSON_GetObjectItem(params, "cloud_url");
    cJSON *cloud_anon_key = cJSON_GetObjectItem(params, "cloud_anon_key");

    if (!cJSON_IsString(serial_number)) {
        send_error("missing_params", "Required: serial_number");
        return;
    }

    if (!cJSON_IsString(cloud_url) || !cJSON_IsString(cloud_anon_key)) {
        send_error("missing_params", "Required: cloud_url, cloud_anon_key");
        return;
    }

    /* Extract optional fields */
    cJSON *wifi_ssid = cJSON_GetObjectItem(params, "wifi_ssid");
    cJSON *wifi_password = cJSON_GetObjectItem(params, "wifi_password");

    esp_err_t err;

    /* Store serial_number as the core provisioning identifier (unit_id in NVS) */
    err = config_set_unit_id(serial_number->valuestring);
    if (err != ESP_OK) {
        send_error("internal_error", "Failed to store serial_number");
        return;
    }
    ESP_LOGI(TAG, "Serial number stored: %s", serial_number->valuestring);

    /* Store cloud (Supabase) configuration */
    supabase_config_t sb_config = {0};
    strncpy(sb_config.unit_id, serial_number->valuestring, sizeof(sb_config.unit_id) - 1);
    strncpy(sb_config.url, cloud_url->valuestring, sizeof(sb_config.url) - 1);
    strncpy(sb_config.anon_key, cloud_anon_key->valuestring, sizeof(sb_config.anon_key) - 1);

    err = supabase_set_config(&sb_config);
    if (err != ESP_OK) {
        send_error("internal_error", "Failed to store cloud config");
        return;
    }
    ESP_LOGI(TAG, "Cloud config stored for: %s", cloud_url->valuestring);

    /* Store Wi-Fi credentials if provided */
    if (cJSON_IsString(wifi_ssid)) {
        const char *password = cJSON_IsString(wifi_password) ? wifi_password->valuestring : "";
        err = config_set_wifi(wifi_ssid->valuestring, password);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "Failed to store Wi-Fi credentials: %s", esp_err_to_name(err));
        } else {
            ESP_LOGI(TAG, "Wi-Fi credentials stored for: %s", wifi_ssid->valuestring);
        }
    }

    /* Mark as factory provisioned */
    err = config_set_provisioned(true);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "Failed to set provisioned flag: %s", esp_err_to_name(err));
    }

    /* Build response with device info */
    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "serial_number", serial_number->valuestring);
    if (cJSON_IsString(name)) {
        cJSON_AddStringToObject(data, "name", name->valuestring);
    }

    /* Add MAC address */
    uint8_t mac[6];
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) {
        char mac_str[18];
        snprintf(mac_str, sizeof(mac_str), "%02X:%02X:%02X:%02X:%02X:%02X",
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        cJSON_AddStringToObject(data, "mac_address", mac_str);
    }

    send_response("ok", "Device provisioned successfully", data);
    cJSON_Delete(data);
}

static void handle_set_provision_data(cJSON *params)
{
    if (params == NULL) {
        send_error("missing_params", "Parameters required");
        return;
    }

    /* Update individual provisioning fields without full re-provision */
    esp_err_t err;
    bool any_updated = false;

    /* Cloud URL */
    cJSON *cloud_url = cJSON_GetObjectItem(params, "cloud_url");
    cJSON *cloud_anon_key = cJSON_GetObjectItem(params, "cloud_anon_key");
    if (cJSON_IsString(cloud_url) && cJSON_IsString(cloud_anon_key)) {
        supabase_config_t sb_config;
        supabase_get_config(&sb_config);
        strncpy(sb_config.url, cloud_url->valuestring, sizeof(sb_config.url) - 1);
        strncpy(sb_config.anon_key, cloud_anon_key->valuestring, sizeof(sb_config.anon_key) - 1);
        err = supabase_set_config(&sb_config);
        if (err == ESP_OK) {
            any_updated = true;
            ESP_LOGI(TAG, "Cloud config updated");
        }
    }

    /* Wi-Fi credentials */
    cJSON *wifi_ssid = cJSON_GetObjectItem(params, "wifi_ssid");
    cJSON *wifi_password = cJSON_GetObjectItem(params, "wifi_password");
    if (cJSON_IsString(wifi_ssid)) {
        const char *password = cJSON_IsString(wifi_password) ? wifi_password->valuestring : "";
        err = config_set_wifi(wifi_ssid->valuestring, password);
        if (err == ESP_OK) {
            any_updated = true;
            ESP_LOGI(TAG, "Wi-Fi credentials updated");
        }
    }

    if (any_updated) {
        send_response("ok", "Provision data updated", NULL);
    } else {
        send_error("invalid_params", "No valid fields to update");
    }
}

static void handle_get_provision_data(cJSON *params)
{
    (void)params;

    cJSON *data = cJSON_CreateObject();

    /* Serial number / unit_id */
    char unit_id[32] = {0};
    if (config_get_unit_id(unit_id, sizeof(unit_id)) == ESP_OK) {
        cJSON_AddStringToObject(data, "serial_number", unit_id);
    } else {
        cJSON_AddNullToObject(data, "serial_number");
    }

    /* Cloud configuration */
    if (supabase_is_configured()) {
        supabase_config_t sb_config;
        if (supabase_get_config(&sb_config) == ESP_OK) {
            cJSON_AddStringToObject(data, "cloud_url", sb_config.url);
            cJSON_AddBoolToObject(data, "cloud_configured", true);
        }
    } else {
        cJSON_AddBoolToObject(data, "cloud_configured", false);
    }

    /* Wi-Fi configuration (don't return password) */
    cJSON_AddBoolToObject(data, "wifi_configured", config_has_wifi());

    send_response("ok", NULL, data);
    cJSON_Delete(data);
}

/*******************************************************************************
 * Device Command Protocol v1.3 - Testing Commands
 ******************************************************************************/

static void handle_run_test(cJSON *root)
{
    /* Extract capability and test_name from root (not params) */
    cJSON *capability = cJSON_GetObjectItem(root, "capability");
    cJSON *test_name = cJSON_GetObjectItem(root, "test_name");
    cJSON *params = cJSON_GetObjectItem(root, "params");
    if (params == NULL) {
        params = cJSON_GetObjectItem(root, "data");  /* Legacy fallback */
    }

    if (!cJSON_IsString(capability) || !cJSON_IsString(test_name)) {
        send_error("missing_params", "Required: capability, test_name");
        return;
    }

    const char *cap = capability->valuestring;
    const char *test = test_name->valuestring;

    ESP_LOGI(TAG, "Running test: capability=%s, test=%s", cap, test);

    /* Route to appropriate test handler based on capability */
    if (strcmp(cap, "wifi") == 0) {
        if (strcmp(test, "connect") == 0) {
            handle_test_wifi(params);
        } else {
            send_error("test_not_found", "Unknown wifi test");
        }
    } else if (strcmp(cap, "cloud") == 0) {
        if (strcmp(test, "connect") == 0 || strcmp(test, "api") == 0) {
            handle_test_cloud(params);
        } else {
            send_error("test_not_found", "Unknown cloud test");
        }
    } else if (strcmp(cap, "rfid") == 0) {
        if (strcmp(test, "scan") == 0) {
            handle_test_rfid(params);
        } else {
            send_error("test_not_found", "Unknown rfid test");
        }
    } else if (strcmp(cap, "thread") == 0) {
        if (strcmp(test, "connect") == 0 || strcmp(test, "start") == 0) {
            handle_test_thread(params);
        } else {
            send_error("test_not_found", "Unknown thread test");
        }
    } else {
        send_error("capability_not_found", "Unknown capability");
    }
}

/*******************************************************************************
 * Device Command Protocol v1.3 - OTA Commands
 ******************************************************************************/

static void handle_ota_update(cJSON *params)
{
    /* Wrapper for start_ota with protocol-compliant parameter names */
    if (params == NULL) {
        send_error("missing_params", "Parameters required");
        return;
    }

    /* Protocol uses firmware_url, target_version, firmware_id */
    cJSON *firmware_url = cJSON_GetObjectItem(params, "firmware_url");
    if (!cJSON_IsString(firmware_url)) {
        /* Try legacy field name */
        firmware_url = cJSON_GetObjectItem(params, "url");
    }

    if (!cJSON_IsString(firmware_url)) {
        send_error("missing_params", "Required: firmware_url");
        return;
    }

    /* Delegate to existing OTA handler */
    handle_start_ota(params);
}

/*******************************************************************************
 * Legacy Command Handlers (backwards compatibility)
 ******************************************************************************/

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

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
static void handle_test_thread(cJSON *params)
{
    (void)params;

    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_CYAN, LED_PATTERN_BLINK_FAST, 250);

    ESP_LOGI(TAG, "Testing Thread Border Router...");

    /* Ensure credentials exist (generate if needed) */
    esp_err_t ret = thread_br_ensure_credentials();
    if (ret != ESP_OK) {
        send_error("thread_creds_failed", "Failed to ensure Thread credentials");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Get credentials to return in response */
    thread_network_credentials_t creds;
    ret = thread_br_get_credentials(&creds);
    if (ret != ESP_OK) {
        send_error("thread_creds_read_failed", "Failed to read Thread credentials");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Initialize Thread BR if not already */
    ret = thread_br_init();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        /* ESP_ERR_INVALID_STATE means already initialized, which is OK */
        send_error("thread_init_failed", "Failed to initialize Thread BR");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Start Thread BR */
    ret = thread_br_start();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        send_error("thread_start_failed", "Failed to start Thread BR");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Wait for Thread to attach (become router or leader) with timeout */
    ESP_LOGI(TAG, "Waiting for Thread network attachment...");
    int64_t start = esp_timer_get_time();
    const int64_t THREAD_ATTACH_TIMEOUT_MS = 30000;  /* 30 seconds */
    bool attached = false;

    while ((esp_timer_get_time() - start) < (THREAD_ATTACH_TIMEOUT_MS * 1000)) {
        thread_br_state_t state = thread_br_get_state();
        if (state >= THREAD_BR_STATE_CHILD) {
            attached = true;
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(500));
    }

    /* Build response */
    cJSON *data = cJSON_CreateObject();

    cJSON_AddStringToObject(data, "network_name", creds.network_name);
    cJSON_AddNumberToObject(data, "pan_id", creds.pan_id);
    cJSON_AddNumberToObject(data, "channel", creds.channel);

    /* Network key as hex string */
    char network_key_hex[33];
    thread_br_get_network_key_hex(network_key_hex, sizeof(network_key_hex));
    cJSON_AddStringToObject(data, "network_key", network_key_hex);

    if (attached) {
        thread_br_status_t status;
        thread_br_get_status(&status);

        cJSON_AddBoolToObject(data, "attached", true);
        cJSON_AddStringToObject(data, "role", thread_br_state_to_string(status.state));
        cJSON_AddNumberToObject(data, "rloc16", status.rloc16);
        cJSON_AddNumberToObject(data, "device_count", status.device_count);

        led_flash(LED_COLOR_GREEN, 500);
        send_response("ok", "Thread BR started and attached to network", data);
    } else {
        cJSON_AddBoolToObject(data, "attached", false);
        cJSON_AddStringToObject(data, "role", thread_br_state_to_string(thread_br_get_state()));

        led_flash(LED_COLOR_ORANGE, 500);
        send_response("ok", "Thread BR started but not yet attached (still forming network)", data);
    }

    cJSON_Delete(data);
    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}
#else
static void handle_test_thread(cJSON *params)
{
    (void)params;
    send_error("thread_not_supported", "Thread is not enabled in this firmware build");
}
#endif /* CONFIG_OPENTHREAD_ENABLED */

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

/*******************************************************************************
 * OTA Command Handlers (PROD-1.3)
 ******************************************************************************/

static void handle_check_ota(cJSON *params)
{
    (void)params;

    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_MAGENTA, LED_PATTERN_BLINK_FAST, 250);

    ESP_LOGI(TAG, "Checking for OTA updates...");

    /* Check if Wi-Fi is connected */
    if (!wifi_is_connected()) {
        send_error("no_wifi", "Wi-Fi not connected - run test_wifi first");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Check for updates */
    ota_update_info_t info;
    esp_err_t err = ota_manager_check_update(&info);

    if (err != ESP_OK) {
        char msg[64];
        snprintf(msg, sizeof(msg), "OTA check failed: %s", esp_err_to_name(err));
        send_error("ota_check_failed", msg);
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_flash(LED_COLOR_RED, 500);
        vTaskDelay(pdMS_TO_TICKS(550));
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Build response */
    cJSON *data = cJSON_CreateObject();

    /* Current versions */
    cJSON *current = cJSON_CreateObject();
    cJSON_AddStringToObject(current, "s3", info.s3_current.string);
    cJSON_AddStringToObject(current, "h2", info.h2_current.string);
    cJSON_AddItemToObject(data, "current", current);

    /* Available updates */
    cJSON_AddBoolToObject(data, "s3_update_available", info.s3_update_available);
    cJSON_AddBoolToObject(data, "h2_update_available", info.h2_update_available);

    if (info.s3_update_available) {
        cJSON_AddStringToObject(data, "s3_available_version", info.s3_available.string);
        cJSON_AddStringToObject(data, "s3_url", info.s3_url);
    }

    if (info.h2_update_available) {
        cJSON_AddStringToObject(data, "h2_available_version", info.h2_available.string);
        cJSON_AddStringToObject(data, "h2_url", info.h2_url);
    }

    if (info.s3_update_available || info.h2_update_available) {
        led_flash(LED_COLOR_MAGENTA, 500);
        send_response("ok", "Updates available", data);
    } else {
        led_flash(LED_COLOR_GREEN, 500);
        send_response("ok", "Firmware is up to date", data);
    }

    cJSON_Delete(data);
    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_start_ota(cJSON *params)
{
    set_state(SERIAL_PROV_STATE_TESTING);
    led_set_state(LED_COLOR_MAGENTA, LED_PATTERN_PULSE, 1000);

    ESP_LOGI(TAG, "Starting OTA update...");

    /* Check if Wi-Fi is connected */
    if (!wifi_is_connected()) {
        send_error("no_wifi", "Wi-Fi not connected - run test_wifi first");
        set_state(SERIAL_PROV_STATE_AWAITING);
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
        return;
    }

    /* Determine what to update */
    bool update_s3 = true;
    bool update_h2 = true;

    if (params != NULL) {
        cJSON *j_s3 = cJSON_GetObjectItem(params, "s3");
        cJSON *j_h2 = cJSON_GetObjectItem(params, "h2");

        if (cJSON_IsBool(j_s3)) {
            update_s3 = cJSON_IsTrue(j_s3);
        }
        if (cJSON_IsBool(j_h2)) {
            update_h2 = cJSON_IsTrue(j_h2);
        }
    }

    /* Check if URL is provided for custom update source */
    const char *s3_url = NULL;
    const char *h2_url = NULL;

    if (params != NULL) {
        cJSON *j_s3_url = cJSON_GetObjectItem(params, "s3_url");
        cJSON *j_h2_url = cJSON_GetObjectItem(params, "h2_url");

        if (cJSON_IsString(j_s3_url)) {
            s3_url = j_s3_url->valuestring;
        }
        if (cJSON_IsString(j_h2_url)) {
            h2_url = j_h2_url->valuestring;
        }
    }

    /* Send initial response - OTA may take a while */
    cJSON *start_data = cJSON_CreateObject();
    cJSON_AddBoolToObject(start_data, "s3_update", update_s3);
    cJSON_AddBoolToObject(start_data, "h2_update", update_h2);
    send_response("started", "OTA update starting", start_data);
    cJSON_Delete(start_data);

    esp_err_t err = ESP_OK;
    bool s3_updated = false;
    bool h2_updated = false;

    /* Update S3 firmware */
    if (update_s3) {
        ESP_LOGI(TAG, "Updating S3 firmware...");
        err = ota_manager_update_s3(s3_url);
        if (err == ESP_OK) {
            s3_updated = true;
            ESP_LOGI(TAG, "S3 update successful");
        } else {
            ESP_LOGE(TAG, "S3 update failed: %s", esp_err_to_name(err));
        }
    }

    /* Update H2 firmware (staging only - flash happens after reboot) */
    if (update_h2 && err == ESP_OK) {
        ESP_LOGI(TAG, "Staging H2 firmware...");
        err = ota_manager_update_h2(h2_url);
        if (err == ESP_OK) {
            h2_updated = true;
            ESP_LOGI(TAG, "H2 firmware staged successfully");
        } else {
            ESP_LOGE(TAG, "H2 staging failed: %s", esp_err_to_name(err));
        }
    }

    /* Send result */
    cJSON *result = cJSON_CreateObject();
    cJSON_AddBoolToObject(result, "s3_updated", s3_updated);
    cJSON_AddBoolToObject(result, "h2_staged", h2_updated);

    if (s3_updated || h2_updated) {
        cJSON_AddBoolToObject(result, "reboot_required", s3_updated);

        led_flash(LED_COLOR_GREEN, 2000);
        send_response("ok", s3_updated ? "OTA complete - reboot required" : "H2 firmware staged",
                      result);

        /* If S3 was updated, offer to reboot */
        if (s3_updated) {
            ESP_LOGI(TAG, "S3 update complete - device should be rebooted");
        }
    } else {
        led_flash(LED_COLOR_RED, 500);
        char msg[64];
        snprintf(msg, sizeof(msg), "OTA failed: %s", esp_err_to_name(err));
        send_response("error", msg, result);
    }

    cJSON_Delete(result);
    set_state(SERIAL_PROV_STATE_AWAITING);
    vTaskDelay(pdMS_TO_TICKS(550));
    led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
}

static void handle_get_ota_status(cJSON *params)
{
    (void)params;

    ota_status_t status;
    esp_err_t err = ota_manager_get_status(&status);

    if (err != ESP_OK) {
        send_error("ota_status_failed", "Failed to get OTA status");
        return;
    }

    cJSON *data = cJSON_CreateObject();

    /* Boot status */
    const char *boot_status_str = "normal";
    if (status.boot_status == OTA_BOOT_PENDING_VERIFY) {
        boot_status_str = "pending_verify";
    } else if (status.boot_status == OTA_BOOT_ROLLBACK) {
        boot_status_str = "rollback";
    }
    cJSON_AddStringToObject(data, "boot_status", boot_status_str);

    /* Running version */
    cJSON_AddStringToObject(data, "running_version", status.running_version.string);

    /* Update status */
    cJSON_AddBoolToObject(data, "update_in_progress", status.update_in_progress);
    if (status.update_in_progress) {
        cJSON_AddStringToObject(data, "updating",
                                status.updating == OTA_FIRMWARE_S3 ? "s3" : "h2");
        cJSON_AddNumberToObject(data, "progress", status.progress);
    }

    /* H2 update pending */
    cJSON_AddBoolToObject(data, "h2_update_pending", ota_manager_h2_update_pending());

    /* Statistics */
    cJSON *stats = cJSON_CreateObject();
    cJSON_AddNumberToObject(stats, "updates_applied", status.updates_applied);
    cJSON_AddNumberToObject(stats, "updates_failed", status.updates_failed);
    cJSON_AddNumberToObject(stats, "rollbacks", status.rollbacks);
    cJSON_AddItemToObject(data, "statistics", stats);

    send_response("ok", NULL, data);
    cJSON_Delete(data);
}

/*******************************************************************************
 * Background Listener (Always-Listening Mode)
 ******************************************************************************/

/**
 * @brief Background listener task - handles commands during normal operation
 *
 * Unlike the full service mode task, this runs with minimal overhead:
 * - No periodic status beacons
 * - Only handles get_status and enter_service_mode commands
 * - Other commands trigger entry into full service mode
 */
static void background_listener_task(void *arg)
{
    (void)arg;
    uint8_t byte;

    ESP_LOGI(TAG, "Background listener started - ready for commands");

    s_prov.bg_rx_len = 0;
    memset(s_prov.bg_rx_buffer, 0, sizeof(s_prov.bg_rx_buffer));

    while (1) {
        /* Read from USB Serial JTAG driver with timeout */
        int len = usb_serial_jtag_read_bytes(&byte, 1, pdMS_TO_TICKS(50));

        if (len > 0) {
            if (byte == '\n' || byte == '\r') {
                /* End of message - process if we have content */
                if (s_prov.bg_rx_len > 0) {
                    s_prov.bg_rx_buffer[s_prov.bg_rx_len] = '\0';
                    ESP_LOGI(TAG, "Background received: %s", s_prov.bg_rx_buffer);
                    process_background_command(s_prov.bg_rx_buffer);
                    s_prov.bg_rx_len = 0;
                }
            } else if (s_prov.bg_rx_len < sizeof(s_prov.bg_rx_buffer) - 1) {
                /* Add byte to buffer */
                s_prov.bg_rx_buffer[s_prov.bg_rx_len++] = (char)byte;
            } else {
                /* Buffer overflow - discard */
                ESP_LOGW(TAG, "Background RX buffer overflow, discarding");
                s_prov.bg_rx_len = 0;
            }
        }

        /* Small delay to allow IDLE task to run and feed watchdog */
        vTaskDelay(pdMS_TO_TICKS(5));
    }
}

/**
 * @brief Process commands received via always-listening mode
 *
 * Per Device Command Protocol v1.3, all commands are handled directly without
 * requiring "service mode" entry. This function routes commands to the same
 * handlers used by the legacy service mode, providing full command support.
 *
 * Legacy commands like enter_service_mode and exit_service_mode are still
 * accepted for backwards compatibility but are essentially no-ops since the
 * device is always listening.
 */
static void process_background_command(const char *json_str)
{
    /* Route to the main command processor - it handles all commands */
    process_command(json_str);
}

esp_err_t serial_prov_start_background_listener(void)
{
    if (!s_prov.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_prov.background_listener_active || s_prov.active) {
        /* Already running background listener or full service mode */
        return ESP_OK;
    }

    /* Create background listener task with smaller stack (no tests/WiFi operations) */
    BaseType_t ret = xTaskCreate(
        background_listener_task,
        "bg_serial",
        4096,  /* Smaller stack than full service mode */
        NULL,
        TASK_PRIORITY - 1,  /* Slightly lower priority than service mode */
        &s_prov.background_task_handle
    );

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create background listener task");
        return ESP_ERR_NO_MEM;
    }

    s_prov.background_listener_active = true;
    ESP_LOGI(TAG, "Background listener started - device commands available");
    return ESP_OK;
}

esp_err_t serial_prov_stop_background_listener(void)
{
    if (!s_prov.background_listener_active) {
        return ESP_OK;
    }

    if (s_prov.background_task_handle) {
        vTaskDelete(s_prov.background_task_handle);
        s_prov.background_task_handle = NULL;
    }

    s_prov.background_listener_active = false;
    ESP_LOGI(TAG, "Background listener stopped");
    return ESP_OK;
}

bool serial_prov_is_background_listener_active(void)
{
    return s_prov.background_listener_active;
}
