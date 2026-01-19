/**
 * @file main.c
 * @brief Saturday Vinyl Hub - ESP32-H2 Thread Border Router Entry Point
 *
 * This is the dedicated Thread co-processor firmware. It handles:
 * - Thread mesh networking (Border Router)
 * - CoAP server for crate communication
 * - UART protocol communication with ESP32-S3 master
 *
 * The H2 operates as a slave to the S3 master. Thread operations are
 * initiated via UART commands from the S3.
 */

#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_vfs_eventfd.h"
#include "nvs_flash.h"

#include "app_config.h"
#include "h2_version.h"
#include "s3_comm.h"
#include "thread_br.h"
#include "coap_server.h"

static const char *TAG = "main";

/*******************************************************************************
 * Thread BR Event Handler
 *
 * Forwards Thread state changes to S3 via UART
 ******************************************************************************/

static s3h2_thread_state_t convert_to_protocol_state(thread_br_state_t state)
{
    switch (state) {
        case THREAD_BR_STATE_DISABLED:
            return S3H2_THREAD_STATE_DISABLED;
        case THREAD_BR_STATE_DETACHED:
            return S3H2_THREAD_STATE_DETACHED;
        case THREAD_BR_STATE_ATTACHING:
            return S3H2_THREAD_STATE_ATTACHING;
        case THREAD_BR_STATE_CHILD:
            return S3H2_THREAD_STATE_CHILD;
        case THREAD_BR_STATE_ROUTER:
            return S3H2_THREAD_STATE_ROUTER;
        case THREAD_BR_STATE_LEADER:
            return S3H2_THREAD_STATE_LEADER;
        default:
            return S3H2_THREAD_STATE_DISABLED;
    }
}

static void thread_br_event_handler(void *arg, esp_event_base_t event_base,
                                    int32_t event_id, void *event_data)
{
    if (event_base != THREAD_BR_EVENTS) {
        return;
    }

    switch (event_id) {
        case THREAD_BR_EVENT_STARTED:
            ESP_LOGI(TAG, "Thread BR started");
            break;

        case THREAD_BR_EVENT_STOPPED:
            ESP_LOGI(TAG, "Thread BR stopped");
            s3_comm_send_thread_state_event(S3H2_THREAD_STATE_ROUTER,
                                            S3H2_THREAD_STATE_DISABLED);
            break;

        case THREAD_BR_EVENT_ATTACHED:
            ESP_LOGI(TAG, "Thread BR attached");
            break;

        case THREAD_BR_EVENT_DETACHED:
            ESP_LOGI(TAG, "Thread BR detached");
            break;

        case THREAD_BR_EVENT_ROLE_CHANGED:
            if (event_data != NULL) {
                thread_br_state_t *new_state = (thread_br_state_t *)event_data;
                ESP_LOGI(TAG, "Thread role changed to %s",
                         thread_br_state_to_string(*new_state));

                /* Get previous state from the state tracker */
                static thread_br_state_t s_last_state = THREAD_BR_STATE_DISABLED;
                s3h2_thread_state_t old_proto = convert_to_protocol_state(s_last_state);
                s3h2_thread_state_t new_proto = convert_to_protocol_state(*new_state);

                if (old_proto != new_proto) {
                    s3_comm_send_thread_state_event(old_proto, new_proto);
                }
                s_last_state = *new_state;
            }
            break;

        case THREAD_BR_EVENT_DEVICE_JOINED:
            ESP_LOGI(TAG, "Device joined Thread network");
            /* Note: For full implementation, we'd get the device's ext_addr
             * from OpenThread and send via s3_comm_send_crate_joined() */
            break;

        case THREAD_BR_EVENT_DEVICE_LEFT:
            ESP_LOGI(TAG, "Device left Thread network");
            /* Note: For full implementation, we'd send via s3_comm_send_crate_left() */
            break;

        default:
            ESP_LOGD(TAG, "Unknown Thread BR event: %ld", (long)event_id);
            break;
    }
}

/*******************************************************************************
 * Main Entry Point
 ******************************************************************************/

void app_main(void)
{
    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "Saturday Vinyl Hub - H2 Thread BR v%s", H2_FW_VERSION_STRING);
    ESP_LOGI(TAG, "===========================================");

    esp_err_t ret;

    /*
     * Initialize NVS
     */
    ESP_LOGI(TAG, "Initializing NVS...");
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS partition needs erase");
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    ESP_LOGI(TAG, "NVS initialized");

    /*
     * Create default event loop
     */
    ESP_LOGI(TAG, "Creating event loop...");
    ret = esp_event_loop_create_default();
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "Failed to create event loop: %s", esp_err_to_name(ret));
        return;
    }

    /*
     * Initialize TCP/IP stack (required for OpenThread netif)
     */
    ESP_LOGI(TAG, "Initializing network interface...");
    ret = esp_netif_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init netif: %s", esp_err_to_name(ret));
        return;
    }

    /*
     * Initialize eventfd for OpenThread
     */
    ESP_LOGI(TAG, "Initializing eventfd VFS...");
    esp_vfs_eventfd_config_t eventfd_config = {
        .max_fds = 3,
    };
    ret = esp_vfs_eventfd_register(&eventfd_config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register eventfd: %s", esp_err_to_name(ret));
        return;
    }

    /*
     * Register Thread BR event handler
     */
    ESP_LOGI(TAG, "Registering Thread BR event handler...");
    ret = esp_event_handler_register(THREAD_BR_EVENTS, ESP_EVENT_ANY_ID,
                                     thread_br_event_handler, NULL);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to register Thread BR handler: %s", esp_err_to_name(ret));
        return;
    }

    /*
     * Initialize S3 Communication (UART)
     * This creates the RX task that handles commands from S3
     */
    ESP_LOGI(TAG, "Initializing S3 communication...");
    ret = s3_comm_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to init S3 comm: %s", esp_err_to_name(ret));
        return;
    }

    /*
     * Ensure Thread credentials exist
     * Generate if this is first boot - but don't start Thread yet
     * S3 will send START_THREAD command when ready
     */
    ESP_LOGI(TAG, "Ensuring Thread credentials...");
    ret = thread_br_ensure_credentials();
    if (ret != ESP_OK) {
        ESP_LOGW(TAG, "Failed to ensure Thread credentials: %s", esp_err_to_name(ret));
        /* Continue anyway - credentials will be generated on first START_THREAD */
    }

    /*
     * Initialization complete
     */
    ESP_LOGI(TAG, "===========================================");
    ESP_LOGI(TAG, "Initialization complete");
    ESP_LOGI(TAG, "Waiting for commands from S3 master...");
    ESP_LOGI(TAG, "===========================================");

    /*
     * Main loop
     * The s3_comm RX task handles incoming commands.
     * This loop is mainly for watchdog and housekeeping.
     */
    uint32_t loop_count = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        loop_count++;

        /* Periodic status log (every 30 seconds) */
        if (loop_count % 30 == 0) {
            s3_comm_stats_t stats;
            if (s3_comm_get_stats(&stats) == ESP_OK) {
                ESP_LOGD(TAG, "S3 comm: rx=%lu tx=%lu errs=%lu cmds=%lu",
                         (unsigned long)stats.rx_frames,
                         (unsigned long)stats.tx_frames,
                         (unsigned long)stats.rx_errors,
                         (unsigned long)stats.commands_processed);
            }

            thread_br_state_t state = thread_br_get_state();
            if (state >= THREAD_BR_STATE_CHILD) {
                ESP_LOGD(TAG, "Thread: %s, devices=%d",
                         thread_br_state_to_string(state),
                         thread_br_get_device_count());
            }
        }
    }
}
