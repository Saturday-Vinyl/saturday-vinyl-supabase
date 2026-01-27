/**
 * @file main.c
 * @brief Saturday Vinyl Hub firmware entry point
 *
 * This is the main entry point for the Saturday Hub firmware.
 * It initializes all subsystems and manages the device lifecycle.
 *
 * Phase 1: Hardware Bring-Up
 * - RGB LED with PWM patterns
 * - Button with debounced press detection
 * - RFID module UART communication
 *
 * Phase 2: RFID Detection
 * - Tag detection with EPC extraction
 * - Saturday tag validation (0x5356 prefix)
 * - Background polling task with callbacks
 *
 * Phase 3: Now Playing Logic
 * - Debounced state machine for tag presence detection
 * - ESP-IDF event loop integration
 * - LED feedback for Now Playing state
 * - Configurable debounce timing via NVS
 *
 * Phase 4: Wi-Fi Connectivity
 * - Wi-Fi station mode with auto-reconnect
 * - HTTPS client with TLS certificate bundle
 * - LED feedback for connection state
 *
 * Phase 5: Supabase Integration
 * - Now Playing events sent to Supabase
 * - Event queue with offline support
 * - Periodic hub heartbeat
 *
 * Phase 6: Service Mode
 * - Saturday Service Mode Protocol for factory provisioning and servicing
 * - Fresh devices (no unit_id): Auto-enter service mode
 * - Provisioned devices: 10-second boot window for enter_service_mode command
 * - Commands: get_status, get_manifest, provision, test_wifi, test_rfid, test_cloud,
 *             customer_reset, factory_reset, exit_service_mode, reboot
 *
 * Phase 7: BLE Provisioning
 * - Consumer Wi-Fi provisioning via BLE using Saturday mobile app
 * - Long press (3-5s) enters BLE provisioning mode
 * - BLE GATT service for credential exchange
 * - Auto-starts for factory-provisioned devices without Wi-Fi
 *
 * Phase 8: Thread Border Router + Radio Coexistence
 * - Thread mesh network for crate communication
 * - Auto-generates network credentials on first boot
 * - Credentials stored in NVS for persistence
 * - WiFi + Thread coexistence via esp_coexist module
 * - BLE and WiFi+Thread are mutually exclusive modes
 * - See docs/radio_coexistence_guide.md for architecture details
 */

#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_chip_info.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "driver/usb_serial_jtag.h"

#include "app_config.h"
#include "led_manager.h"
#include "button_handler.h"
#include "yrm100_driver.h"
#include "rfid_protocol.h"
#include "now_playing.h"
#include "config_store.h"
#include "wifi_manager.h"
#include "http_client.h"
#include "supabase_client.h"
#include "event_reporter.h"
#include "serial_prov.h"
#include "device_protocol.h"
#include "ble_prov.h"
#include "thread_br.h"  /* Conditionally enabled in sdkconfig */
#include "esp_vfs_eventfd.h"
#include "esp_netif.h"

/* Radio coexistence for WiFi + Thread simultaneous operation */
#if defined(CONFIG_ESP_COEX_SW_COEXIST_ENABLE) && CONFIG_ESP_COEX_SW_COEXIST_ENABLE
#include "esp_coexist.h"
#endif

static const char *TAG = "SV_HUB";

/* Track Wi-Fi connection state for LED updates */
static bool s_wifi_connected = false;

/* Flag to trigger connectivity test from main loop (avoid stack overflow in event handler) */
static bool s_test_connectivity_pending = false;

/* Track if a Saturday tag was detected in the current poll cycle */
static bool s_saturday_tag_detected_this_poll = false;

/* Track if BLE provisioning mode was requested via button */
static bool s_ble_prov_requested = false;

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
/* Track Thread BR state for LED updates */
static bool s_thread_running = false;
#endif

/*******************************************************************************
 * Button Callback
 ******************************************************************************/

/**
 * @brief Callback for button press events
 *
 * Demonstrates LED feedback for different button press types.
 */
static void on_button_press(button_press_t press_type)
{
    switch (press_type) {
        case BUTTON_PRESS_SHORT:
            ESP_LOGI(TAG, "Short press detected - changing LED color");
            /* Cycle through colors on short press */
            static int color_index = 0;
            led_color_preset_t colors[] = {
                LED_COLOR_RED, LED_COLOR_GREEN, LED_COLOR_BLUE,
                LED_COLOR_YELLOW, LED_COLOR_CYAN, LED_COLOR_MAGENTA
            };
            color_index = (color_index + 1) % 6;
            led_set_state(colors[color_index], LED_PATTERN_SOLID, 0);
            break;

        case BUTTON_PRESS_LONG:
            ESP_LOGI(TAG, "Long press detected - requesting BLE provisioning mode");
            /* Set flag to trigger BLE provisioning from main loop */
            s_ble_prov_requested = true;
            break;

        case BUTTON_PRESS_FACTORY:
            ESP_LOGI(TAG, "Factory reset requested - red fast blink (demo)");
            /* Red fast blink indicates factory reset */
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_FAST, 500);
            break;
    }
}

/*******************************************************************************
 * NVS Initialization
 ******************************************************************************/

static esp_err_t nvs_init(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition was truncated, erasing...");
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    return ret;
}

/*******************************************************************************
 * Now Playing Event Handler (Phase 3)
 ******************************************************************************/

/**
 * @brief Handler for Now Playing events (TAG_PLACED / TAG_REMOVED)
 *
 * Updates LED to reflect Now Playing state.
 */
static void on_now_playing_event(void *handler_args, esp_event_base_t base,
                                  int32_t event_id, void *event_data)
{
    const now_playing_event_t *event = (const now_playing_event_t *)event_data;
    char epc_str[25];
    rfid_epc_to_hex_string(event->epc, event->epc_len, epc_str, sizeof(epc_str));

    switch (event_id) {
        case NOW_PLAYING_EVENT_TAG_PLACED:
            ESP_LOGI(TAG, ">>> NOW PLAYING: %s (RSSI: %d dBm)", epc_str, event->rssi);
            /* Flash green to indicate tag confirmed, then show dim green solid */
            led_flash(LED_COLOR_GREEN, 300);
            /* After flash, set to dim green solid to indicate Now Playing */
            vTaskDelay(pdMS_TO_TICKS(350));
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(64);
            break;

        case NOW_PLAYING_EVENT_TAG_REMOVED:
            ESP_LOGI(TAG, "<<< STOPPED PLAYING: %s (duration: %lu ms)",
                     epc_str, (unsigned long)event->duration_ms);
            /* Flash briefly, then return to idle state (very dim green) */
            led_flash(LED_COLOR_CYAN, 200);
            vTaskDelay(pdMS_TO_TICKS(250));
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(16);  /* Very dim for idle */
            break;

        default:
            ESP_LOGW(TAG, "Unknown Now Playing event: %ld", (long)event_id);
            break;
    }
}

/*******************************************************************************
 * RFID Tag Callback (Phase 2 + Phase 3 Integration)
 ******************************************************************************/

/**
 * @brief Callback invoked when a tag is detected by the polling task
 *
 * This callback runs in the context of the RFID polling task, so it
 * should be quick and non-blocking.
 *
 * Phase 3: Now feeds tags into the Now Playing state machine.
 */
static void on_tag_detected(const rfid_tag_t *tag, void *user_data)
{
    char epc_str[25];
    rfid_epc_to_hex_string(tag->epc, tag->epc_len, epc_str, sizeof(epc_str));

    if (tag->is_saturday_tag) {
        ESP_LOGD(TAG, "Saturday tag: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));

        /* Mark that we saw a Saturday tag this poll cycle */
        s_saturday_tag_detected_this_poll = true;

        /* Feed to Now Playing state machine */
        now_playing_on_tag_detected(tag);
    } else {
        ESP_LOGD(TAG, "Non-Saturday tag: %s (RSSI: %d dBm)",
                 epc_str, rfid_rssi_to_dbm(tag->rssi));
        /* Non-Saturday tags don't affect Now Playing state */
    }
}

/**
 * @brief Callback invoked after each poll cycle completes
 *
 * Used to inform the Now Playing state machine when no Saturday tag was seen.
 */
static void on_poll_cycle_complete(bool tag_detected, void *user_data)
{
    (void)tag_detected;  /* We track Saturday tags specifically */

    if (!s_saturday_tag_detected_this_poll) {
        /* No Saturday tag was seen this poll - notify state machine */
        now_playing_on_poll_complete_no_tag();
    }
    /* Reset for next poll cycle */
    s_saturday_tag_detected_this_poll = false;
}

/*******************************************************************************
 * RFID and Now Playing Initialization (Phase 2 + Phase 3)
 ******************************************************************************/

/**
 * @brief Initialize and start RFID polling with Now Playing integration
 *
 * Validates communication with the RFID module, initializes the Now Playing
 * state machine, and starts the background polling task.
 */
static esp_err_t start_rfid_polling(void)
{
    ESP_LOGI(TAG, "Initializing RFID subsystem...");

    /* Load RFID configuration from NVS */
    rfid_config_t rfid_cfg;
    esp_err_t ret = config_get_rfid(&rfid_cfg);
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to load RFID config, using defaults");
        rfid_cfg.poll_interval_ms = DEFAULT_POLL_INTERVAL_MS;
        rfid_cfg.rf_power_dbm = DEFAULT_RF_POWER_DBM;
        rfid_cfg.debounce_present_ms = DEFAULT_DEBOUNCE_PRESENT_MS;
        rfid_cfg.debounce_absent_ms = DEFAULT_DEBOUNCE_ABSENT_MS;
    }

    ESP_LOGI(TAG, "RFID config: poll=%dms, power=%ddBm, deb_present=%dms, deb_absent=%dms",
             rfid_cfg.poll_interval_ms, rfid_cfg.rf_power_dbm,
             rfid_cfg.debounce_present_ms, rfid_cfg.debounce_absent_ms);

    /* Initialize Now Playing state machine with config from NVS */
    now_playing_config_t np_config = {
        .debounce_present_ms = rfid_cfg.debounce_present_ms,
        .debounce_absent_ms = rfid_cfg.debounce_absent_ms,
    };
    ret = now_playing_init(&np_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to initialize Now Playing: %s", esp_err_to_name(ret));
        return ret;
    }
    ESP_LOGI(TAG, "Now Playing state machine initialized");

    /* Register for Now Playing events */
    ret = esp_event_handler_register(NOW_PLAYING_EVENTS, ESP_EVENT_ANY_ID,
                                      on_now_playing_event, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Now Playing event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Enable the RFID module */
    yrm100_enable(true);
    vTaskDelay(pdMS_TO_TICKS(500));  /* Extra settling time */

    /* Try to get firmware version to verify communication */
    char version[32] = {0};
    ret = yrm100_get_firmware_version(version, sizeof(version));

    if (ret == ESP_OK) {
        ESP_LOGI(TAG, "RFID module firmware: %s", version);
        led_flash(LED_COLOR_GREEN, 200);
    } else if (ret == ESP_ERR_TIMEOUT) {
        ESP_LOGW(TAG, "RFID module not responding (timeout) - check wiring");
        led_flash(LED_COLOR_ORANGE, 200);
        return ret;
    } else {
        ESP_LOGE(TAG, "RFID communication error: %s", esp_err_to_name(ret));
        led_flash(LED_COLOR_RED, 200);
        return ret;
    }

    /* Register callbacks for tag detection and poll completion */
    yrm100_register_tag_callback(on_tag_detected, NULL);
    yrm100_register_poll_complete_callback(on_poll_cycle_complete, NULL);

    /* Configure and start polling task with config from NVS */
    yrm100_poll_config_t poll_config = {
        .poll_interval_ms = rfid_cfg.poll_interval_ms,
        .rf_power_dbm = rfid_cfg.rf_power_dbm,
        .filter_saturday_only = false,  /* Report all tags so non-Saturday still logged */
    };

    ret = yrm100_start_polling_task(&poll_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start polling task: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "RFID polling started (interval=%dms, power=%ddBm)",
             poll_config.poll_interval_ms, poll_config.rf_power_dbm);

    return ESP_OK;
}

/*******************************************************************************
 * Wi-Fi Event Handler (Phase 4)
 ******************************************************************************/

/**
 * @brief Handler for Wi-Fi manager events
 *
 * Updates LED to reflect Wi-Fi connection state.
 */
static void on_wifi_event(void *handler_args, esp_event_base_t base,
                          int32_t event_id, void *event_data)
{
    switch (event_id) {
        case WIFI_MANAGER_EVENT_CONNECTED: {
            wifi_connection_info_t *info = (wifi_connection_info_t *)event_data;
            s_wifi_connected = true;
            ESP_LOGI(TAG, "Wi-Fi connected: %s (RSSI: %d dBm)", info->ssid, info->rssi);

            /* Notify event reporter of Wi-Fi state (Phase 5) */
            event_reporter_set_wifi_state(true);

            /* Flash cyan to indicate connection, then return to normal */
            led_flash(LED_COLOR_CYAN, 500);

            /* Set LED to idle state (dim green) */
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(16);

            /*
             * Schedule connectivity test for main loop.
             * Don't call http_test_connectivity() here - TLS operations
             * require more stack than the event task provides.
             */
            s_test_connectivity_pending = true;
            break;
        }

        case WIFI_MANAGER_EVENT_DISCONNECTED:
            s_wifi_connected = false;
            ESP_LOGW(TAG, "Wi-Fi disconnected - will attempt to reconnect");

            /* Notify event reporter of Wi-Fi state (Phase 5) */
            event_reporter_set_wifi_state(false);

            /* Show orange slow blink to indicate reconnecting */
            led_set_state(LED_COLOR_ORANGE, LED_PATTERN_BLINK_SLOW, 1000);
            break;

        case WIFI_MANAGER_EVENT_CONNECTION_FAILED:
            s_wifi_connected = false;
            ESP_LOGE(TAG, "Wi-Fi connection failed - check credentials");

            /* Notify event reporter of Wi-Fi state (Phase 5) */
            event_reporter_set_wifi_state(false);

            /* Flash red to indicate error */
            led_flash(LED_COLOR_RED, 500);
            vTaskDelay(pdMS_TO_TICKS(550));
            led_set_state(LED_COLOR_RED, LED_PATTERN_BLINK_SLOW, 1000);
            break;

        default:
            break;
    }
}

/**
 * @brief Initialize Wi-Fi and connect
 *
 * Initializes Wi-Fi manager and attempts connection using stored credentials
 * or hardcoded test credentials if none stored.
 */
static esp_err_t start_wifi(void)
{
    ESP_LOGI(TAG, "Initializing Wi-Fi...");

    /* Show yellow pulse while connecting */
    led_set_state(LED_COLOR_YELLOW, LED_PATTERN_PULSE, 1500);

    /* Initialize Wi-Fi manager */
    esp_err_t ret = wifi_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Wi-Fi init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Initialize HTTP client */
    ret = http_client_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "HTTP client init failed: %s", esp_err_to_name(ret));
        /* Continue anyway - HTTP is optional for this phase */
    }

    /* Register for Wi-Fi manager events */
    ret = esp_event_handler_register(WIFI_MANAGER_EVENTS, ESP_EVENT_ANY_ID,
                                      on_wifi_event, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Wi-Fi event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Try to connect using stored credentials */
    if (config_has_wifi()) {
        ESP_LOGI(TAG, "Found stored Wi-Fi credentials");
        ret = wifi_connect_stored();
        if (ret == ESP_OK) {
            return ESP_OK;
        }
        ESP_LOGW(TAG, "Failed to use stored credentials: %s", esp_err_to_name(ret));
    }

    /* No stored credentials - Wi-Fi provisioning will be implemented in a future phase */
    ESP_LOGW(TAG, "No Wi-Fi credentials configured - waiting for provisioning");
    return ESP_ERR_NOT_FOUND;
}

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
/*******************************************************************************
 * Thread Border Router Event Handler (Phase 8)
 ******************************************************************************/

/**
 * @brief Handler for Thread BR events
 *
 * Updates LED to reflect Thread network state.
 */
static void on_thread_br_event(void *handler_args, esp_event_base_t base,
                                int32_t event_id, void *event_data)
{
    switch (event_id) {
        case THREAD_BR_EVENT_STARTED:
            ESP_LOGI(TAG, "Thread Border Router started");
            /* Show cyan pulse while forming network */
            led_set_state(LED_COLOR_CYAN, LED_PATTERN_PULSE, 1500);
            break;

        case THREAD_BR_EVENT_ATTACHED:
            s_thread_running = true;
            ESP_LOGI(TAG, "Thread network attached");
            /* Flash cyan to indicate success */
            led_flash(LED_COLOR_CYAN, 300);
            /* Return to normal state */
            if (s_wifi_connected) {
                led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
                led_set_brightness(16);
            }
            break;

        case THREAD_BR_EVENT_DETACHED:
            s_thread_running = false;
            ESP_LOGW(TAG, "Thread network detached");
            break;

        case THREAD_BR_EVENT_ROLE_CHANGED: {
            thread_br_state_t *state = (thread_br_state_t *)event_data;
            ESP_LOGI(TAG, "Thread role: %s", thread_br_state_to_string(*state));
            break;
        }

        case THREAD_BR_EVENT_DEVICE_JOINED:
            ESP_LOGI(TAG, "Thread device joined the network");
            led_flash(LED_COLOR_CYAN, 200);
            break;

        case THREAD_BR_EVENT_DEVICE_LEFT:
            ESP_LOGI(TAG, "Thread device left the network");
            break;

        case THREAD_BR_EVENT_STOPPED:
            s_thread_running = false;
            ESP_LOGI(TAG, "Thread Border Router stopped");
            break;

        default:
            break;
    }
}

/**
 * @brief Initialize and start Thread Border Router
 *
 * Initializes OpenThread stack and starts the border router.
 * Network credentials are generated on first boot if not present.
 */
static esp_err_t start_thread_br(void)
{
    ESP_LOGI(TAG, "Initializing Thread Border Router...");

    /* Show cyan pulse while starting */
    led_set_state(LED_COLOR_CYAN, LED_PATTERN_PULSE, 1500);

    /* Initialize Thread BR */
    esp_err_t ret = thread_br_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Thread BR init failed: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Register for Thread BR events */
    ret = esp_event_handler_register(THREAD_BR_EVENTS, ESP_EVENT_ANY_ID,
                                      on_thread_br_event, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Thread event handler: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start Thread BR */
    ret = thread_br_start();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Thread BR start failed: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "Thread Border Router started successfully");
    return ESP_OK;
}
#endif /* CONFIG_OPENTHREAD_ENABLED */

/*******************************************************************************
 * Main Application
 ******************************************************************************/

void app_main(void)
{
    esp_err_t ret;

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Saturday Vinyl Hub Firmware v%s", FIRMWARE_VERSION);
    ESP_LOGI(TAG, "  Phase 8: Thread BR + Radio Coexistence");
    ESP_LOGI(TAG, "===========================================");

    /* Log chip info */
    esp_chip_info_t chip_info;
    esp_chip_info(&chip_info);
    ESP_LOGI(TAG, "ESP32-C6 with %d CPU core(s), WiFi%s%s%s",
             chip_info.cores,
             (chip_info.features & CHIP_FEATURE_BT) ? "/BT" : "",
             (chip_info.features & CHIP_FEATURE_BLE) ? "/BLE" : "",
             (chip_info.features & CHIP_FEATURE_IEEE802154) ? "/802.15.4" : "");
    ESP_LOGI(TAG, "Silicon revision %d", chip_info.revision);

    /*
     * Initialize NVS - required for Wi-Fi and config storage
     */
    ESP_LOGI(TAG, "Initializing NVS...");
    ESP_ERROR_CHECK(nvs_init());
    ESP_LOGI(TAG, "NVS initialized");

    /*
     * Create default event loop - required for Now Playing events (Phase 3)
     */
    ESP_LOGI(TAG, "Creating default event loop...");
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        /* ESP_ERR_INVALID_STATE means it's already created, which is fine */
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Event loop ready");
    }

    /*
     * Initialize Network Interface layer - MUST be called before Thread or WiFi
     * This initializes LwIP TCP/IP stack which both Thread and WiFi depend on.
     * Required for radio coexistence mode where Thread starts before WiFi.
     */
    ESP_LOGI(TAG, "Initializing network interface layer...");
    ret = esp_netif_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init netif: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Network interface layer initialized");
    }

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
    /*
     * Register eventfd VFS early - required for OpenThread task queue
     * This must be done before any async networking starts
     */
    ESP_LOGI(TAG, "Registering eventfd VFS for OpenThread...");
    esp_vfs_eventfd_config_t eventfd_config = {
        .max_fds = 5,  /* netif + task_queue + border_router + radio */
    };
    ret = esp_vfs_eventfd_register(&eventfd_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register eventfd VFS: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "eventfd VFS registered");
    }
#endif

    /*
     * Initialize Configuration Store (Phase 3)
     */
    ESP_LOGI(TAG, "Initializing config store...");
    ret = config_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Config init warning: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Config store initialized");
    }

    /*
     * Initialize LED Manager (Task 1.1)
     * PWM-based RGB LED control with patterns
     */
    ESP_LOGI(TAG, "Initializing LED manager...");
    ret = led_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "LED init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "LED manager initialized");
        /* Start with white pulse to indicate booting */
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);
    }

    /*
     * Initialize Button Handler (Task 1.2)
     * Debounced button with press duration detection
     */
    ESP_LOGI(TAG, "Initializing button handler...");
    ret = button_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Button init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Button handler initialized");
        button_register_callback(on_button_press);
    }

    /*
     * Initialize RFID Driver (Task 1.3)
     * UART communication with YRM100 module
     */
    ESP_LOGI(TAG, "Initializing RFID driver...");
    ret = yrm100_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "RFID init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "RFID driver initialized");
    }

    /* Short delay before starting main operation */
    vTaskDelay(pdMS_TO_TICKS(1000));

    /* Switch to dim green solid to indicate idle (ready, no tag) */
    led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
    led_set_brightness(16);  /* Very dim for idle state */

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  Hardware initialization complete!");
    ESP_LOGI(TAG, "===========================================");

    /*
     * Initialize Supabase Client (Phase 5)
     * Must be before serial provisioning check so we can check if configured.
     */
    ESP_LOGI(TAG, "Initializing Supabase client...");
    ret = supabase_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Supabase init failed: %s", esp_err_to_name(ret));
    } else {
        if (supabase_is_configured()) {
            ESP_LOGI(TAG, "Supabase client initialized with stored config");
        } else {
            ESP_LOGI(TAG, "Supabase client initialized (awaiting configuration)");
        }
    }

    /*
     * Initialize Device Protocol (Device Command Protocol v1.2.0)
     * Always-listening protocol - no entry window required.
     * Commands are accepted via USB serial at all times.
     */
    ESP_LOGI(TAG, "Initializing device protocol...");
    ret = device_protocol_init();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Device protocol init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Device protocol initialized");
    }

    /*
     * Start device protocol listener (always-on).
     * Commands can be received at any time via USB serial.
     */
    ret = device_protocol_start();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Device protocol start failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Device protocol started - listening for commands");
    }

    /*
     * Check if device has been factory provisioned.
     * Fresh device (no serial_number): Wait for factory_provision command.
     * Provisioned device: Continue with normal operation.
     */
    if (!config_has_serial_number()) {
        ESP_LOGW(TAG, "Device not provisioned - awaiting factory_provision command");
        ESP_LOGI(TAG, "===========================================");
        ESP_LOGI(TAG, "  AWAITING FACTORY PROVISIONING");
        ESP_LOGI(TAG, "  Connect Saturday Admin app via USB");
        ESP_LOGI(TAG, "  Send factory_provision command to begin");
        ESP_LOGI(TAG, "===========================================");

        /* Set LED to white pulse to indicate awaiting provisioning */
        led_set_state(LED_COLOR_WHITE, LED_PATTERN_PULSE, 2000);

        /* Wait for serial_number to be set (factory_provision command) */
        while (!config_has_serial_number()) {
            vTaskDelay(pdMS_TO_TICKS(1000));
        }

        ESP_LOGI(TAG, "Device provisioned - continuing with startup");
    } else {
        char serial_number[32] = {0};
        config_get_serial_number(serial_number, sizeof(serial_number));
        ESP_LOGI(TAG, "Device provisioned: %s", serial_number);
    }

#if USE_TEST_CREDENTIALS
    /*
     * Apply test credentials (Phase 5 testing only)
     * These will be stored in NVS and persist across reboots.
     */
    ESP_LOGI(TAG, "Applying test credentials...");

    /* Set Wi-Fi credentials if not already stored */
    if (!config_has_wifi()) {
        ret = config_set_wifi(TEST_WIFI_SSID, TEST_WIFI_PASSWORD);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "Test Wi-Fi credentials stored for '%s'", TEST_WIFI_SSID);
        } else {
            ESP_LOGE(TAG, "Failed to store Wi-Fi credentials: %s", esp_err_to_name(ret));
        }
    }

    /* Set Supabase config if not already stored */
    if (!supabase_is_configured()) {
        supabase_config_t sb_config = {0};
        strncpy(sb_config.url, TEST_SUPABASE_URL, sizeof(sb_config.url) - 1);
        strncpy(sb_config.anon_key, TEST_SUPABASE_ANON_KEY, sizeof(sb_config.anon_key) - 1);
        strncpy(sb_config.unit_id, TEST_UNIT_ID, sizeof(sb_config.unit_id) - 1);

        ret = supabase_set_config(&sb_config);
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "Test Supabase config stored for unit '%s'", TEST_UNIT_ID);
        } else {
            ESP_LOGE(TAG, "Failed to store Supabase config: %s", esp_err_to_name(ret));
        }
    }
#endif

    /*
     * Initialize Event Reporter (Phase 5)
     */
    ESP_LOGI(TAG, "Initializing event reporter...");
    ret = event_reporter_init(NULL);  /* Use defaults */
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Event reporter init failed: %s", esp_err_to_name(ret));
    } else {
        ESP_LOGI(TAG, "Event reporter initialized");
    }

    /*
     * ==========================================================================
     * RADIO MODE DECISION: BLE Provisioning vs WiFi+Thread Coexistence
     * ==========================================================================
     *
     * The ESP32-C6 has a single radio shared between WiFi, BLE, and 802.15.4.
     * We operate in two mutually exclusive modes:
     *
     * 1. PROVISIONING MODE (BLE only):
     *    - When device has no WiFi credentials configured
     *    - BLE advertising for Saturday mobile app
     *    - WiFi and Thread disabled
     *
     * 2. NORMAL MODE (WiFi + Thread coexistence):
     *    - WiFi connected for cloud communication
     *    - Thread Border Router for crate communication
     *    - BLE disabled
     *    - Software coexistence manages radio time-sharing
     *
     * See docs/radio_coexistence_guide.md for architecture details.
     */

    bool needs_provisioning = config_has_serial_number() && !config_has_wifi();

    if (needs_provisioning) {
        /*
         * PROVISIONING MODE: BLE only
         * Device has unit_id (factory provisioned) but needs WiFi credentials.
         * Initialize and start BLE provisioning.
         */
        ESP_LOGI(TAG, "===========================================");
        ESP_LOGI(TAG, "  PROVISIONING MODE (BLE Only)");
        ESP_LOGI(TAG, "  Device needs Wi-Fi configuration");
        ESP_LOGI(TAG, "  Open Saturday app to set up your Hub");
        ESP_LOGI(TAG, "===========================================");

        /* Initialize BLE for provisioning */
        ESP_LOGI(TAG, "Initializing BLE provisioning...");
        ret = ble_prov_init(NULL);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "BLE provisioning init failed: %s", esp_err_to_name(ret));
        } else {
            ESP_LOGI(TAG, "BLE provisioning initialized");

            ret = ble_prov_start();
            if (ret == ESP_OK) {
                /* Wait for provisioning to complete or timeout */
                while (!ble_prov_is_complete() && ble_prov_is_active()) {
                    vTaskDelay(pdMS_TO_TICKS(1000));
                }

                if (ble_prov_is_complete()) {
                    ESP_LOGI(TAG, "BLE provisioning completed successfully");
                    /* Deinit BLE before starting WiFi+Thread */
                    ble_prov_deinit();
                    /* Update flag - we now have WiFi credentials */
                    needs_provisioning = false;
                } else {
                    ESP_LOGW(TAG, "BLE provisioning timed out or was stopped");
                }
            } else {
                ESP_LOGE(TAG, "Failed to start BLE provisioning: %s", esp_err_to_name(ret));
            }
        }
    }

    /*
     * NORMAL MODE: WiFi + Thread Coexistence
     *
     * IMPORTANT: Initialization order matters for coexistence!
     * Per ESP-IDF documentation and ot_br example:
     * 1. Initialize Thread/OpenThread FIRST
     * 2. Initialize WiFi SECOND
     * 3. Enable coexistence AFTER both stacks are up
     *
     * This ensures proper radio arbitration between protocols.
     */
    if (!needs_provisioning || config_has_wifi()) {
        ESP_LOGI(TAG, "===========================================");
        ESP_LOGI(TAG, "  NORMAL MODE (WiFi + Thread Coexistence)");
        ESP_LOGI(TAG, "===========================================");

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
        /*
         * Step 1: Initialize Thread Border Router FIRST
         * Thread must be initialized before WiFi for proper coexistence.
         */
        ret = start_thread_br();
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Thread BR not started - continuing without Thread");
        }
#endif /* CONFIG_OPENTHREAD_ENABLED */

        /*
         * Step 2: Initialize Wi-Fi SECOND
         */
        ret = start_wifi();
        if (ret != ESP_OK && ret != ESP_ERR_NOT_FOUND) {
            ESP_LOGW(TAG, "Wi-Fi initialization issue - continuing without Wi-Fi");
        }

#if defined(CONFIG_ESP_COEX_SW_COEXIST_ENABLE) && CONFIG_ESP_COEX_SW_COEXIST_ENABLE && \
    defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
        /*
         * Step 3: Enable WiFi/802.15.4 coexistence AFTER both stacks are up
         * This enables the coexistence arbitration between WiFi and Thread.
         */
        ESP_LOGI(TAG, "Enabling WiFi/802.15.4 radio coexistence...");
        ret = esp_coex_wifi_i154_enable();
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Failed to enable coexistence: %s", esp_err_to_name(ret));
        } else {
            ESP_LOGI(TAG, "WiFi/Thread coexistence enabled");
        }
#endif

        /*
         * Start Event Reporter (Phase 5)
         * Now that WiFi is initialized, start the cloud sync task.
         */
        ret = event_reporter_start();
        if (ret != ESP_OK) {
            ESP_LOGW(TAG, "Event reporter start failed: %s", esp_err_to_name(ret));
        } else {
            ESP_LOGI(TAG, "Event reporter started");
        }
    }

    /* Start RFID polling with Now Playing integration (Phase 2 + 3) */
    ret = start_rfid_polling();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "RFID/Now Playing not started - continuing without RFID");
    }

    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "  System ready!");
    ESP_LOGI(TAG, "  - Place record on turntable for Now Playing");
    ESP_LOGI(TAG, "  - Press button to change LED color");
    ESP_LOGI(TAG, "  - Hold 3-5s for provisioning mode");
    ESP_LOGI(TAG, "  - Hold >10s for factory reset");
    ESP_LOGI(TAG, "===========================================");

    /* Main loop - periodic health check and stats */
    uint32_t loop_count = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));  /* 1 second loop for responsiveness */
        loop_count++;

        /*
         * Handle pending connectivity test (triggered by Wi-Fi connect event).
         * This runs in the main task which has adequate stack for TLS.
         */
        if (s_test_connectivity_pending) {
            s_test_connectivity_pending = false;
            ESP_LOGI(TAG, "Running connectivity test...");
            esp_err_t ret = http_test_connectivity();
            if (ret == ESP_OK) {
                ESP_LOGI(TAG, "Internet connectivity verified");
                led_flash(LED_COLOR_GREEN, 200);
            } else {
                ESP_LOGW(TAG, "Internet connectivity test failed");
            }
        }

        /*
         * Handle BLE provisioning request (triggered by button long press).
         * This runs in the main task context for safety.
         *
         * IMPORTANT: BLE and WiFi+Thread are mutually exclusive modes.
         * To enter BLE provisioning, we must:
         * 1. Stop WiFi and Thread to release the radio
         * 2. Initialize and start BLE
         * 3. After provisioning completes, restart WiFi+Thread
         */
        if (s_ble_prov_requested) {
            s_ble_prov_requested = false;

            ESP_LOGI(TAG, "===========================================");
            ESP_LOGI(TAG, "  BLE PROVISIONING MODE (Button Triggered)");
            ESP_LOGI(TAG, "  Stopping WiFi and Thread for BLE...");
            ESP_LOGI(TAG, "===========================================");

            /* Step 1: Stop WiFi and Thread to release the radio */
            event_reporter_stop();
            wifi_disconnect();

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
            thread_br_stop();
            s_thread_running = false;
#endif
            s_wifi_connected = false;

            /* Small delay for radio to settle */
            vTaskDelay(pdMS_TO_TICKS(500));

            /* Step 2: Initialize and start BLE provisioning */
            ESP_LOGI(TAG, "Starting BLE provisioning...");
            ret = ble_prov_init(NULL);
            if (ret != ESP_OK) {
                ESP_LOGE(TAG, "BLE provisioning init failed: %s", esp_err_to_name(ret));
                led_flash(LED_COLOR_RED, 500);
            } else {
                ret = ble_prov_start();
                if (ret != ESP_OK) {
                    ESP_LOGE(TAG, "Failed to start BLE provisioning: %s", esp_err_to_name(ret));
                    led_flash(LED_COLOR_RED, 500);
                    ble_prov_deinit();
                } else {
                    /* Wait for provisioning to complete or timeout */
                    ESP_LOGI(TAG, "  Open Saturday app to configure Wi-Fi");
                    while (!ble_prov_is_complete() && ble_prov_is_active()) {
                        vTaskDelay(pdMS_TO_TICKS(1000));
                    }

                    bool prov_success = ble_prov_is_complete();

                    /* Step 3: Stop and deinit BLE */
                    ble_prov_stop();
                    ble_prov_deinit();

                    if (prov_success) {
                        ESP_LOGI(TAG, "BLE provisioning completed - restarting WiFi+Thread");
                    } else {
                        ESP_LOGW(TAG, "BLE provisioning timed out - restarting WiFi+Thread");
                    }
                }
            }

            /* Step 4: Restart WiFi+Thread in proper order */
            ESP_LOGI(TAG, "Restarting normal mode (WiFi + Thread)...");

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
            /* Thread first */
            ret = thread_br_start();
            if (ret == ESP_OK) {
                s_thread_running = true;
            }
#endif

            /* Then WiFi */
            if (config_has_wifi()) {
                wifi_connect_stored();
            }

#if defined(CONFIG_ESP_COEX_SW_COEXIST_ENABLE) && CONFIG_ESP_COEX_SW_COEXIST_ENABLE && \
    defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
            /* Re-enable coexistence */
            esp_coex_wifi_i154_enable();
#endif

            /* Restart event reporter */
            event_reporter_start();

            /* Return to idle LED state */
            led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
            led_set_brightness(16);
        }

        /* Health check every 10 seconds */
        if (loop_count % 10 != 0) {
            continue;
        }

        /* Periodic health check with Wi-Fi status */
        char ip_str[16] = "N/A";
        if (s_wifi_connected) {
            wifi_get_ip_string(ip_str, sizeof(ip_str));
        }
        ESP_LOGI(TAG, "Health: heap=%lu bytes, uptime=%lus, wifi=%s, ip=%s",
                 (unsigned long)esp_get_free_heap_size(),
                 (unsigned long)loop_count,
                 s_wifi_connected ? "connected" : "disconnected",
                 ip_str);

        /* Wi-Fi stats every minute (60 seconds = 60 loop iterations) */
        if (loop_count % 60 == 0 && s_wifi_connected) {
            wifi_manager_status_t wifi_status;
            if (wifi_get_status(&wifi_status) == ESP_OK) {
                ESP_LOGI(TAG, "Wi-Fi: ssid=%s, rssi=%d dBm, attempts=%lu, disconnects=%lu",
                         wifi_status.ssid, wifi_status.rssi,
                         (unsigned long)wifi_status.connect_attempts,
                         (unsigned long)wifi_status.disconnect_count);
            }
        }

        /* RFID and Now Playing stats every minute */
        if (loop_count % 60 == 0 && yrm100_is_polling_task_running()) {
            uint32_t polls, tags, saturday;
            yrm100_get_poll_stats(&polls, &tags, &saturday);
            ESP_LOGI(TAG, "RFID stats: polls=%lu, tags=%lu, saturday=%lu",
                     (unsigned long)polls, (unsigned long)tags,
                     (unsigned long)saturday);

            /* Now Playing status */
            now_playing_status_t np_status;
            if (now_playing_get_status(&np_status) == ESP_OK) {
                ESP_LOGI(TAG, "Now Playing: state=%s, placed=%lu, removed=%lu",
                         now_playing_state_to_string(np_status.state),
                         (unsigned long)np_status.total_placed_events,
                         (unsigned long)np_status.total_removed_events);
            }
        }

        /* Event reporter stats every minute (Phase 5) */
        if (loop_count % 60 == 0) {
            event_reporter_status_t er_status;
            if (event_reporter_get_status(&er_status) == ESP_OK) {
                ESP_LOGI(TAG, "Cloud: queued=%lu, sent=%lu, failed=%lu, heartbeats=%lu",
                         (unsigned long)er_status.events_queued,
                         (unsigned long)er_status.events_sent,
                         (unsigned long)er_status.events_failed,
                         (unsigned long)er_status.heartbeats_sent);
            }
        }

#if defined(CONFIG_OPENTHREAD_ENABLED) && CONFIG_OPENTHREAD_ENABLED
        /* Thread BR stats every minute (Phase 8) */
        if (loop_count % 60 == 0 && s_thread_running) {
            thread_br_status_t thread_status;
            if (thread_br_get_status(&thread_status) == ESP_OK) {
                ESP_LOGI(TAG, "Thread: state=%s, pan=0x%04X, ch=%d, devices=%d",
                         thread_br_state_to_string(thread_status.state),
                         thread_status.pan_id,
                         thread_status.channel,
                         thread_status.device_count);
            }
        }
#endif /* CONFIG_OPENTHREAD_ENABLED */
    }
}
