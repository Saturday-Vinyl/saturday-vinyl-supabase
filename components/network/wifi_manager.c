/**
 * @file wifi_manager.c
 * @brief Wi-Fi connection management implementation
 *
 * Implements Wi-Fi station mode with automatic reconnection using
 * exponential backoff. Uses ESP-IDF event loop for state notifications.
 *
 * Phase 4: Wi-Fi Connectivity
 */

#include "wifi_manager.h"
#include "config_store.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "lwip/ip4_addr.h"
#include <string.h>

static const char *TAG = "WIFI_MGR";

/* Event base definition */
ESP_EVENT_DEFINE_BASE(WIFI_MANAGER_EVENTS);

/* Reconnection timing constants */
#define RECONNECT_INITIAL_DELAY_MS      1000
#define RECONNECT_MAX_DELAY_MS          60000
#define RECONNECT_BACKOFF_MULTIPLIER    2

/* Maximum connection attempts before giving up (0 = infinite) */
#define MAX_CONNECTION_ATTEMPTS         0

/* DHCP timeout - disconnect and retry if no IP received within this time */
#define DHCP_TIMEOUT_MS                 15000

/* Module state */
static struct {
    bool initialized;
    bool auto_reconnect;
    wifi_state_t state;
    char ssid[33];
    char password[65];
    uint32_t ip_addr;
    uint32_t gateway;
    uint32_t netmask;
    int8_t rssi;
    uint32_t connect_attempts;
    uint32_t disconnect_count;
    int64_t connected_time_us;
    uint32_t reconnect_delay_ms;
    esp_timer_handle_t reconnect_timer;
    esp_timer_handle_t dhcp_timeout_timer;
    esp_netif_t *netif;
} s_wifi = {
    .initialized = false,
    .auto_reconnect = true,
    .state = WIFI_STATE_DISCONNECTED,
    .reconnect_delay_ms = RECONNECT_INITIAL_DELAY_MS,
};

/* Forward declarations */
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data);
static void ip_event_handler(void *arg, esp_event_base_t event_base,
                             int32_t event_id, void *event_data);
static void reconnect_timer_callback(void *arg);
static void start_reconnect_timer(void);
static void stop_reconnect_timer(void);
static void reset_reconnect_delay(void);
static void dhcp_timeout_callback(void *arg);
static void start_dhcp_timeout_timer(void);
static void stop_dhcp_timeout_timer(void);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t wifi_init(void)
{
    if (s_wifi.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing Wi-Fi manager...");

    /* Initialize TCP/IP stack */
    esp_err_t ret = esp_netif_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init netif: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Create default Wi-Fi station netif */
    s_wifi.netif = esp_netif_create_default_wifi_sta();
    if (s_wifi.netif == NULL) {
        ESP_LOGE(TAG, "Failed to create netif");
        return ESP_FAIL;
    }

    /* Initialize Wi-Fi with default config */
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ret = esp_wifi_init(&cfg);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init Wi-Fi: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Register event handlers */
    ret = esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                               wifi_event_handler, NULL, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Wi-Fi event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               ip_event_handler, NULL, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register IP event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    ret = esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_LOST_IP,
                                               ip_event_handler, NULL, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register IP lost handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Create reconnect timer */
    esp_timer_create_args_t timer_args = {
        .callback = reconnect_timer_callback,
        .arg = NULL,
        .name = "wifi_reconnect",
    };
    ret = esp_timer_create(&timer_args, &s_wifi.reconnect_timer);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create reconnect timer: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Create DHCP timeout timer */
    esp_timer_create_args_t dhcp_timer_args = {
        .callback = dhcp_timeout_callback,
        .arg = NULL,
        .name = "dhcp_timeout",
    };
    ret = esp_timer_create(&dhcp_timer_args, &s_wifi.dhcp_timeout_timer);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to create DHCP timeout timer: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Set Wi-Fi mode to station */
    ret = esp_wifi_set_mode(WIFI_MODE_STA);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set Wi-Fi mode: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start Wi-Fi */
    ret = esp_wifi_start();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start Wi-Fi: %s", esp_err_to_name(ret));
        return ret;
    }

    s_wifi.initialized = true;
    ESP_LOGI(TAG, "Wi-Fi manager initialized successfully");
    return ESP_OK;
}

esp_err_t wifi_manager_deinit(void)
{
    if (!s_wifi.initialized) {
        return ESP_OK;
    }

    stop_reconnect_timer();
    stop_dhcp_timeout_timer();
    esp_timer_delete(s_wifi.reconnect_timer);
    esp_timer_delete(s_wifi.dhcp_timeout_timer);
    esp_wifi_disconnect();
    esp_wifi_stop();
    esp_wifi_deinit();
    esp_netif_destroy_default_wifi(s_wifi.netif);

    s_wifi.initialized = false;
    s_wifi.state = WIFI_STATE_DISCONNECTED;

    ESP_LOGI(TAG, "Wi-Fi manager deinitialized");
    return ESP_OK;
}

/*******************************************************************************
 * Connection Control
 ******************************************************************************/

esp_err_t wifi_connect(const char *ssid, const char *password)
{
    if (!s_wifi.initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (ssid == NULL || strlen(ssid) == 0) {
        ESP_LOGE(TAG, "SSID is required");
        return ESP_ERR_INVALID_ARG;
    }

    if (strlen(ssid) > 32) {
        ESP_LOGE(TAG, "SSID too long (max 32 chars)");
        return ESP_ERR_INVALID_ARG;
    }

    if (password != NULL && strlen(password) > 64) {
        ESP_LOGE(TAG, "Password too long (max 64 chars)");
        return ESP_ERR_INVALID_ARG;
    }

    /* Stop any pending reconnect */
    stop_reconnect_timer();
    reset_reconnect_delay();

    /* If already connected, disconnect first */
    if (s_wifi.state == WIFI_STATE_CONNECTED || s_wifi.state == WIFI_STATE_CONNECTING) {
        ESP_LOGI(TAG, "Disconnecting from current network...");
        esp_wifi_disconnect();
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    /* Store credentials */
    strlcpy(s_wifi.ssid, ssid, sizeof(s_wifi.ssid));
    if (password != NULL) {
        strlcpy(s_wifi.password, password, sizeof(s_wifi.password));
    } else {
        s_wifi.password[0] = '\0';
    }

    /* Configure Wi-Fi */
    wifi_config_t wifi_config = {0};
    strlcpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    if (password != NULL && strlen(password) > 0) {
        strlcpy((char *)wifi_config.sta.password, password, sizeof(wifi_config.sta.password));
        wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    } else {
        wifi_config.sta.threshold.authmode = WIFI_AUTH_OPEN;
    }
    wifi_config.sta.pmf_cfg.capable = true;
    wifi_config.sta.pmf_cfg.required = false;

    esp_err_t ret = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to set Wi-Fi config: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start connection */
    s_wifi.state = WIFI_STATE_CONNECTING;
    s_wifi.connect_attempts++;

    ESP_LOGI(TAG, "Connecting to '%s'... (attempt %lu)",
             ssid, (unsigned long)s_wifi.connect_attempts);

    ret = esp_wifi_connect();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start connection: %s", esp_err_to_name(ret));
        s_wifi.state = WIFI_STATE_DISCONNECTED;
        return ret;
    }

    return ESP_OK;
}

esp_err_t wifi_connect_stored(void)
{
    if (!s_wifi.initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    char ssid[33];
    char password[65];

    esp_err_t ret = config_get_wifi(ssid, sizeof(ssid), password, sizeof(password));
    if (ret == ESP_ERR_NOT_FOUND) {
        ESP_LOGI(TAG, "No stored Wi-Fi credentials");
        return ESP_ERR_NOT_FOUND;
    } else if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to get stored credentials: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "Using stored credentials for '%s'", ssid);
    return wifi_connect(ssid, password);
}

esp_err_t wifi_disconnect(void)
{
    if (!s_wifi.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    stop_reconnect_timer();
    s_wifi.auto_reconnect = false;  /* Prevent auto-reconnect on explicit disconnect */

    esp_err_t ret = esp_wifi_disconnect();
    if (ret != ESP_OK && ret != ESP_ERR_WIFI_NOT_CONNECT) {
        ESP_LOGE(TAG, "Failed to disconnect: %s", esp_err_to_name(ret));
        return ret;
    }

    s_wifi.state = WIFI_STATE_DISCONNECTED;
    ESP_LOGI(TAG, "Disconnected from Wi-Fi");
    return ESP_OK;
}

/*******************************************************************************
 * Status Queries
 ******************************************************************************/

bool wifi_is_connected(void)
{
    return s_wifi.state == WIFI_STATE_CONNECTED;
}

wifi_state_t wifi_get_state(void)
{
    return s_wifi.state;
}

int8_t wifi_get_rssi(void)
{
    if (s_wifi.state != WIFI_STATE_CONNECTED) {
        return 0;
    }

    wifi_ap_record_t ap_info;
    if (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK) {
        s_wifi.rssi = ap_info.rssi;
    }
    return s_wifi.rssi;
}

esp_err_t wifi_get_status(wifi_manager_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    status->state = s_wifi.state;
    strlcpy(status->ssid, s_wifi.ssid, sizeof(status->ssid));
    status->rssi = wifi_get_rssi();
    status->ip_addr = s_wifi.ip_addr;
    status->connect_attempts = s_wifi.connect_attempts;
    status->disconnect_count = s_wifi.disconnect_count;
    status->connected_time_us = s_wifi.connected_time_us;

    return ESP_OK;
}

esp_err_t wifi_get_ip_string(char *ip_str, size_t max_len)
{
    if (ip_str == NULL || max_len < 16) {
        return ESP_ERR_INVALID_ARG;
    }

    if (s_wifi.state != WIFI_STATE_CONNECTED || s_wifi.ip_addr == 0) {
        return ESP_ERR_INVALID_STATE;
    }

    esp_ip4_addr_t addr = { .addr = s_wifi.ip_addr };
    snprintf(ip_str, max_len, IPSTR, IP2STR(&addr));
    return ESP_OK;
}

void wifi_set_auto_reconnect(bool enable)
{
    s_wifi.auto_reconnect = enable;
    ESP_LOGI(TAG, "Auto-reconnect %s", enable ? "enabled" : "disabled");
}

/*******************************************************************************
 * Event Handlers
 ******************************************************************************/

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    switch (event_id) {
        case WIFI_EVENT_STA_START:
            ESP_LOGD(TAG, "STA started");
            break;

        case WIFI_EVENT_STA_CONNECTED:
            ESP_LOGI(TAG, "Connected to AP, waiting for IP...");
            /* Start DHCP timeout - if we don't get IP within timeout, disconnect and retry */
            start_dhcp_timeout_timer();
            /* Don't update state yet - wait for IP */
            break;

        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *event = (wifi_event_sta_disconnected_t *)event_data;
            s_wifi.disconnect_count++;

            /* Stop DHCP timeout timer if running */
            stop_dhcp_timeout_timer();

            const char *reason_str;
            switch (event->reason) {
                case WIFI_REASON_AUTH_EXPIRE:
                case WIFI_REASON_AUTH_FAIL:
                case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
                case WIFI_REASON_HANDSHAKE_TIMEOUT:
                    reason_str = "authentication failed";
                    break;
                case WIFI_REASON_NO_AP_FOUND:
                    reason_str = "network not found";
                    break;
                case WIFI_REASON_ASSOC_LEAVE:
                    reason_str = "disconnected by user";
                    break;
                case WIFI_REASON_BEACON_TIMEOUT:
                    reason_str = "beacon timeout";
                    break;
                default:
                    reason_str = "unknown";
                    break;
            }

            ESP_LOGW(TAG, "Disconnected (reason %d: %s)", event->reason, reason_str);

            /* Clear connection info */
            s_wifi.ip_addr = 0;
            s_wifi.gateway = 0;
            s_wifi.netmask = 0;
            s_wifi.rssi = 0;

            bool was_connected = (s_wifi.state == WIFI_STATE_CONNECTED);

            /* Check if this was an auth failure on first attempt */
            if (s_wifi.state == WIFI_STATE_CONNECTING &&
                (event->reason == WIFI_REASON_AUTH_FAIL ||
                 event->reason == WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT ||
                 event->reason == WIFI_REASON_HANDSHAKE_TIMEOUT)) {
                ESP_LOGE(TAG, "Connection failed - bad password or network rejected");
                s_wifi.state = WIFI_STATE_DISCONNECTED;

                /* Post connection failed event */
                esp_event_post(WIFI_MANAGER_EVENTS, WIFI_MANAGER_EVENT_CONNECTION_FAILED,
                               NULL, 0, portMAX_DELAY);
                break;
            }

            /* Check if network not found */
            if (s_wifi.state == WIFI_STATE_CONNECTING &&
                event->reason == WIFI_REASON_NO_AP_FOUND) {
                ESP_LOGE(TAG, "Network '%s' not found", s_wifi.ssid);
                s_wifi.state = WIFI_STATE_DISCONNECTED;

                /* Post connection failed event */
                esp_event_post(WIFI_MANAGER_EVENTS, WIFI_MANAGER_EVENT_CONNECTION_FAILED,
                               NULL, 0, portMAX_DELAY);
                break;
            }

            /* Post disconnected event if we were connected */
            if (was_connected) {
                esp_event_post(WIFI_MANAGER_EVENTS, WIFI_MANAGER_EVENT_DISCONNECTED,
                               NULL, 0, portMAX_DELAY);
            }

            /* Auto-reconnect if enabled */
            if (s_wifi.auto_reconnect && strlen(s_wifi.ssid) > 0) {
                s_wifi.state = WIFI_STATE_RECONNECTING;
                start_reconnect_timer();
            } else {
                s_wifi.state = WIFI_STATE_DISCONNECTED;
            }
            break;
        }

        default:
            ESP_LOGD(TAG, "Unhandled Wi-Fi event: %ld", (long)event_id);
            break;
    }
}

static void ip_event_handler(void *arg, esp_event_base_t event_base,
                             int32_t event_id, void *event_data)
{
    if (event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;

        /* Stop DHCP timeout timer - we got an IP! */
        stop_dhcp_timeout_timer();

        s_wifi.ip_addr = event->ip_info.ip.addr;
        s_wifi.gateway = event->ip_info.gw.addr;
        s_wifi.netmask = event->ip_info.netmask.addr;
        s_wifi.connected_time_us = esp_timer_get_time();
        s_wifi.state = WIFI_STATE_CONNECTED;

        /* Reset reconnect delay on successful connection */
        reset_reconnect_delay();
        stop_reconnect_timer();

        /* Re-enable auto-reconnect (may have been disabled by explicit disconnect) */
        s_wifi.auto_reconnect = true;

        /* Get RSSI */
        wifi_get_rssi();

        ESP_LOGI(TAG, "Connected to '%s' - IP: " IPSTR " (RSSI: %d dBm)",
                 s_wifi.ssid, IP2STR(&event->ip_info.ip), s_wifi.rssi);

        /* Post connected event with connection info */
        wifi_connection_info_t info;
        strlcpy(info.ssid, s_wifi.ssid, sizeof(info.ssid));
        info.rssi = s_wifi.rssi;
        info.ip_addr = s_wifi.ip_addr;
        info.gateway = s_wifi.gateway;
        info.netmask = s_wifi.netmask;

        esp_event_post(WIFI_MANAGER_EVENTS, WIFI_MANAGER_EVENT_CONNECTED,
                       &info, sizeof(info), portMAX_DELAY);

    } else if (event_id == IP_EVENT_STA_LOST_IP) {
        ESP_LOGW(TAG, "Lost IP address");
        s_wifi.ip_addr = 0;
        /* The STA_DISCONNECTED event will handle the rest */
    }
}

/*******************************************************************************
 * Reconnection Logic
 ******************************************************************************/

static void reconnect_timer_callback(void *arg)
{
    if (s_wifi.state != WIFI_STATE_RECONNECTING) {
        return;
    }

    s_wifi.connect_attempts++;
    ESP_LOGI(TAG, "Reconnecting to '%s'... (attempt %lu, next delay %lums)",
             s_wifi.ssid, (unsigned long)s_wifi.connect_attempts,
             (unsigned long)s_wifi.reconnect_delay_ms);

    esp_err_t ret = esp_wifi_connect();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Reconnect failed: %s", esp_err_to_name(ret));
        /* Schedule another attempt with increased delay */
        start_reconnect_timer();
    }

    /* Increase delay for next attempt (exponential backoff) */
    s_wifi.reconnect_delay_ms *= RECONNECT_BACKOFF_MULTIPLIER;
    if (s_wifi.reconnect_delay_ms > RECONNECT_MAX_DELAY_MS) {
        s_wifi.reconnect_delay_ms = RECONNECT_MAX_DELAY_MS;
    }
}

static void start_reconnect_timer(void)
{
    ESP_LOGD(TAG, "Scheduling reconnect in %lums", (unsigned long)s_wifi.reconnect_delay_ms);
    esp_timer_start_once(s_wifi.reconnect_timer, s_wifi.reconnect_delay_ms * 1000);
}

static void stop_reconnect_timer(void)
{
    esp_timer_stop(s_wifi.reconnect_timer);
}

static void reset_reconnect_delay(void)
{
    s_wifi.reconnect_delay_ms = RECONNECT_INITIAL_DELAY_MS;
}

/*******************************************************************************
 * DHCP Timeout Logic
 ******************************************************************************/

static void dhcp_timeout_callback(void *arg)
{
    ESP_LOGW(TAG, "DHCP timeout - no IP received within %d ms, disconnecting to retry",
             DHCP_TIMEOUT_MS);

    /* Disconnect - this will trigger the disconnect event handler which will
     * start the reconnect timer with exponential backoff */
    esp_wifi_disconnect();
}

static void start_dhcp_timeout_timer(void)
{
    ESP_LOGD(TAG, "Starting DHCP timeout timer (%d ms)", DHCP_TIMEOUT_MS);
    esp_timer_start_once(s_wifi.dhcp_timeout_timer, DHCP_TIMEOUT_MS * 1000);
}

static void stop_dhcp_timeout_timer(void)
{
    esp_timer_stop(s_wifi.dhcp_timeout_timer);
}
