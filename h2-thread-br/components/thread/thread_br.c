/**
 * @file thread_br.c
 * @brief Thread Border Router implementation for Saturday Vinyl Hub
 *
 * Implements Thread mesh network management with Border Router capabilities.
 * Uses ESP-IDF's OpenThread integration with native 802.15.4 radio support.
 *
 * Phase 8: Thread Border Router
 */

#include "thread_br.h"
/* Note: H2 doesn't have WiFi - it's a dedicated Thread co-processor.
 * Border routing (IP bridging) happens at application level via UART to S3. */
#include "esp_log.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "nvs_flash.h"
#include "nvs.h"
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

/* OpenThread includes */
#include "esp_openthread.h"
#include "esp_openthread_types.h"
#include "esp_openthread_netif_glue.h"
#include "esp_openthread_border_router.h"
#include "esp_openthread_lock.h"
#include "esp_netif.h"
#include "esp_netif_types.h"
#include "esp_vfs_eventfd.h"
#include "openthread/instance.h"
#include "openthread/thread.h"
#include "openthread/dataset.h"
#include "openthread/dataset_ftd.h"
#include "openthread/border_router.h"
#include "openthread/netdata.h"
#include "openthread/commissioner.h"
#include "openthread/ip6.h"

static const char *TAG = "THREAD_BR";

/*******************************************************************************
 * NVS Configuration
 ******************************************************************************/

#define NVS_NAMESPACE_THREAD    "sv_thread"
#define NVS_KEY_NETWORK_NAME    "net_name"
#define NVS_KEY_PAN_ID          "pan_id"
#define NVS_KEY_CHANNEL         "channel"
#define NVS_KEY_NETWORK_KEY     "net_key"
#define NVS_KEY_EXTPANID        "extpanid"
#define NVS_KEY_MESH_PREFIX     "mesh_pfx"
#define NVS_KEY_PSKC            "pskc"
#define NVS_KEY_CREDENTIALS_SET "creds_set"

/*******************************************************************************
 * Module State
 ******************************************************************************/

/* Event base definition */
ESP_EVENT_DEFINE_BASE(THREAD_BR_EVENTS);

/* Module state */
static bool s_initialized = false;
static bool s_started = false;
static bool s_suspended = false;  /* Thread radio suspended for WiFi-exclusive operations */
static bool s_shutdown_for_wifi = false;  /* Thread completely shutdown for WiFi */
static thread_br_state_t s_state = THREAD_BR_STATE_DISABLED;
static int64_t s_attached_time_us = 0;
static bool s_joining_enabled = false;

/* OpenThread instance */
static otInstance *s_ot_instance = NULL;

/* Network interfaces */
static esp_netif_t *s_openthread_netif = NULL;

/* Mutex for thread-safe access */
static SemaphoreHandle_t s_mutex = NULL;

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void ot_state_changed_callback(otChangedFlags flags, void *context);
static esp_err_t load_credentials_from_nvs(thread_network_credentials_t *creds);
static esp_err_t save_credentials_to_nvs(const thread_network_credentials_t *creds);
static esp_err_t apply_credentials_to_dataset(const thread_network_credentials_t *creds);
static thread_br_state_t convert_ot_role(otDeviceRole role);

/*******************************************************************************
 * Initialization and Lifecycle
 ******************************************************************************/

esp_err_t thread_br_init(void)
{
    if (s_initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing Thread Border Router...");

    /* Create mutex */
    s_mutex = xSemaphoreCreateMutex();
    if (s_mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Note: eventfd VFS must already be registered by main() before this is called */

    esp_err_t ret;

    /* OpenThread platform configuration for ESP32-C6 with native radio */
    esp_openthread_platform_config_t platform_config = {
        .radio_config = {
            .radio_mode = RADIO_MODE_NATIVE,
        },
        .host_config = {
            .host_connection_mode = HOST_CONNECTION_MODE_NONE,
        },
        .port_config = {
            .storage_partition_name = "nvs",
            .netif_queue_size = 10,
            .task_queue_size = 10,
        },
    };

    /* OpenThread full configuration including netif */
    esp_openthread_config_t config = {
        .netif_config = ESP_NETIF_DEFAULT_OPENTHREAD(),
        .platform_config = platform_config,
    };

    /* Use the simplified esp_openthread_start() which handles init, netif, and task creation */
    ret = esp_openthread_start(&config);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start OpenThread: %s", esp_err_to_name(ret));
        vSemaphoreDelete(s_mutex);
        s_mutex = NULL;
        return ret;
    }

    /* Get OpenThread instance and netif */
    s_ot_instance = esp_openthread_get_instance();
    if (s_ot_instance == NULL) {
        ESP_LOGE(TAG, "Failed to get OpenThread instance");
        esp_openthread_stop();
        vSemaphoreDelete(s_mutex);
        s_mutex = NULL;
        return ESP_FAIL;
    }

    /* Register state change callback */
    otSetStateChangedCallback(s_ot_instance, ot_state_changed_callback, NULL);

    s_initialized = true;
    s_state = THREAD_BR_STATE_DETACHED;

    ESP_LOGI(TAG, "Thread Border Router initialized");
    return ESP_OK;
}

esp_err_t thread_br_start(void)
{
    if (!s_initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_started) {
        ESP_LOGW(TAG, "Already started");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Starting Thread Border Router...");

    /* Load or generate network credentials */
    thread_network_credentials_t creds;
    esp_err_t ret = load_credentials_from_nvs(&creds);

    if (ret == ESP_ERR_NOT_FOUND) {
        ESP_LOGI(TAG, "No stored credentials - generating new network");
        ret = thread_br_generate_credentials();
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to generate credentials: %s", esp_err_to_name(ret));
            return ret;
        }
        ret = load_credentials_from_nvs(&creds);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to load generated credentials: %s", esp_err_to_name(ret));
            return ret;
        }
    } else if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to load credentials: %s", esp_err_to_name(ret));
        return ret;
    }

    ESP_LOGI(TAG, "Network: %s, PAN ID: 0x%04X, Channel: %d",
             creds.network_name, creds.pan_id, creds.channel);

    /* Apply credentials to OpenThread dataset */
    ret = apply_credentials_to_dataset(&creds);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to apply dataset: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Acquire OpenThread lock for all API calls from this task */
    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Note: H2 is a dedicated Thread co-processor without WiFi.
     * In the 2-SoC architecture, border routing (IP bridging) happens at
     * the application level via UART communication with the S3 master.
     * H2 handles the Thread mesh networking only. */
    ESP_LOGI(TAG, "H2 Thread co-processor mode - no WiFi backbone");

    /* Enable Thread interface */
    otError error = otIp6SetEnabled(s_ot_instance, true);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to enable IPv6: %d", error);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Start Thread protocol */
    error = otThreadSetEnabled(s_ot_instance, true);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to enable Thread: %d", error);
        esp_openthread_lock_release();
        return ESP_FAIL;
    }

    /* Release lock after all OpenThread API calls */
    esp_openthread_lock_release();

    s_started = true;
    s_state = THREAD_BR_STATE_ATTACHING;

    /* Post started event */
    esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_STARTED, NULL, 0, pdMS_TO_TICKS(100));

    ESP_LOGI(TAG, "Thread Border Router started - attaching to network...");
    return ESP_OK;
}

esp_err_t thread_br_stop(void)
{
    if (!s_started) {
        ESP_LOGW(TAG, "Not started");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Stopping Thread Border Router...");

    /* Disable commissioner if enabled */
    if (s_joining_enabled) {
        thread_br_disable_joining();
    }

    /* Must hold lock for OpenThread API calls */
    esp_openthread_lock_acquire(portMAX_DELAY);

    /* Disable Thread protocol */
    if (s_ot_instance != NULL) {
        otThreadSetEnabled(s_ot_instance, false);
        otIp6SetEnabled(s_ot_instance, false);
    }

    esp_openthread_lock_release();

    /* Note: Border router cleanup is handled by esp_openthread_stop() in thread_br_deinit() */

    s_started = false;
    s_state = THREAD_BR_STATE_DETACHED;
    s_attached_time_us = 0;

    /* Post stopped event */
    esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_STOPPED, NULL, 0, pdMS_TO_TICKS(100));

    ESP_LOGI(TAG, "Thread Border Router stopped");
    return ESP_OK;
}

esp_err_t thread_br_suspend(void)
{
    if (!s_started) {
        ESP_LOGW(TAG, "Cannot suspend - Thread not started");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_suspended) {
        ESP_LOGD(TAG, "Already suspended");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Suspending Thread radio for WiFi operation...");

    /* Disable Thread interface - this stops radio activity but keeps stack running */
    if (s_ot_instance != NULL) {
        esp_openthread_lock_acquire(portMAX_DELAY);
        otThreadSetEnabled(s_ot_instance, false);
        esp_openthread_lock_release();
    }

    /* Wait for radio coexistence to fully transition to WiFi-only mode.
     * The 802.15.4 radio may still have pending operations after otThreadSetEnabled(false).
     * This delay ensures the radio arbitrator gives WiFi full priority before we
     * attempt TLS handshakes which are sensitive to packet loss. */
    vTaskDelay(pdMS_TO_TICKS(500));

    s_suspended = true;
    ESP_LOGI(TAG, "Thread radio suspended");
    return ESP_OK;
}

esp_err_t thread_br_resume(void)
{
    if (!s_started) {
        ESP_LOGW(TAG, "Cannot resume - Thread not started");
        return ESP_ERR_INVALID_STATE;
    }

    if (!s_suspended) {
        ESP_LOGD(TAG, "Not suspended");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Resuming Thread radio...");

    /* Re-enable Thread interface */
    if (s_ot_instance != NULL) {
        esp_openthread_lock_acquire(portMAX_DELAY);
        otThreadSetEnabled(s_ot_instance, true);
        esp_openthread_lock_release();
    }

    s_suspended = false;
    ESP_LOGI(TAG, "Thread radio resumed - will re-attach to network");
    return ESP_OK;
}

bool thread_br_is_suspended(void)
{
    return s_suspended;
}

esp_err_t thread_br_shutdown_for_wifi(void)
{
    if (s_shutdown_for_wifi) {
        ESP_LOGD(TAG, "Already shutdown for WiFi");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "=== THREAD SHUTDOWN for WiFi-exclusive mode ===");

    /* If suspended, clear that state first */
    s_suspended = false;

    /* Full deinit - this completely stops OpenThread and releases the 802.15.4 radio */
    esp_err_t ret = thread_br_deinit();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to deinit Thread: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Wait for radio hardware to fully release */
    vTaskDelay(pdMS_TO_TICKS(1000));

    s_shutdown_for_wifi = true;
    ESP_LOGI(TAG, "=== Thread completely stopped - WiFi has exclusive radio access ===");
    return ESP_OK;
}

esp_err_t thread_br_restart_after_wifi(void)
{
    if (!s_shutdown_for_wifi) {
        ESP_LOGW(TAG, "Thread not shutdown for WiFi");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "=== THREAD RESTART after WiFi operation ===");

    /* Reinitialize Thread */
    esp_err_t ret = thread_br_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to reinit Thread: %s", esp_err_to_name(ret));
        return ret;
    }

    /* Start Thread (will reload credentials from NVS) */
    ret = thread_br_start();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to restart Thread: %s", esp_err_to_name(ret));
        return ret;
    }

    s_shutdown_for_wifi = false;
    ESP_LOGI(TAG, "=== Thread restarted - will re-attach to network ===");
    return ESP_OK;
}

bool thread_br_is_shutdown_for_wifi(void)
{
    return s_shutdown_for_wifi;
}

esp_err_t thread_br_deinit(void)
{
    if (!s_initialized) {
        return ESP_OK;
    }

    /* Stop if running */
    if (s_started) {
        thread_br_stop();
    }

    ESP_LOGI(TAG, "Deinitializing Thread Border Router...");

    /* Clear state callback */
    if (s_ot_instance != NULL) {
        otRemoveStateChangeCallback(s_ot_instance, ot_state_changed_callback, NULL);
    }

    /* Stop OpenThread (handles deinit and task cleanup) */
    esp_openthread_stop();

    /* Delete mutex */
    if (s_mutex != NULL) {
        vSemaphoreDelete(s_mutex);
        s_mutex = NULL;
    }

    s_ot_instance = NULL;
    s_openthread_netif = NULL;
    s_initialized = false;
    s_state = THREAD_BR_STATE_DISABLED;

    ESP_LOGI(TAG, "Thread Border Router deinitialized");
    return ESP_OK;
}

/*******************************************************************************
 * Thread Task (Note: esp_openthread_start() creates its own internal task)
 ******************************************************************************/

/*******************************************************************************
 * OpenThread Callbacks
 ******************************************************************************/

static void ot_state_changed_callback(otChangedFlags flags, void *context)
{
    if (flags & OT_CHANGED_THREAD_ROLE) {
        otDeviceRole role = otThreadGetDeviceRole(s_ot_instance);
        thread_br_state_t new_state = convert_ot_role(role);

        ESP_LOGI(TAG, "Thread role changed: %s -> %s",
                 thread_br_state_to_string(s_state),
                 thread_br_state_to_string(new_state));

        bool was_attached = (s_state >= THREAD_BR_STATE_CHILD);
        bool is_attached = (new_state >= THREAD_BR_STATE_CHILD);

        s_state = new_state;

        /* Track attachment time */
        if (!was_attached && is_attached) {
            s_attached_time_us = esp_timer_get_time();
            esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_ATTACHED, NULL, 0, pdMS_TO_TICKS(100));
            ESP_LOGI(TAG, "Attached to Thread network as %s",
                     (new_state == THREAD_BR_STATE_LEADER) ? "leader" : "router");
        } else if (was_attached && !is_attached) {
            s_attached_time_us = 0;
            esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_DETACHED, NULL, 0, pdMS_TO_TICKS(100));
            ESP_LOGW(TAG, "Detached from Thread network");
        }

        /* Post role changed event */
        esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_ROLE_CHANGED, &new_state,
                       sizeof(new_state), pdMS_TO_TICKS(100));
    }

    if (flags & OT_CHANGED_THREAD_CHILD_ADDED) {
        /* Find the newest child by iterating the neighbor table */
        thread_device_info_t info = {0};
        otNeighborInfoIterator iter = OT_NEIGHBOR_INFO_ITERATOR_INIT;
        otNeighborInfo neighbor;
        while (otThreadGetNextNeighborInfo(s_ot_instance, &iter, &neighbor) == OT_ERROR_NONE) {
            if (neighbor.mIsChild) {
                info.rloc16 = neighbor.mRloc16;
                memcpy(info.ext_addr, neighbor.mExtAddress.m8, 8);
                info.is_child = true;
            }
        }

        /* Guard: skip if no child was actually found in neighbor table
         * (can happen during init when OT restores stale ChildInfo from flash) */
        uint8_t zeros[8] = {0};
        if (memcmp(info.ext_addr, zeros, 8) == 0) {
            ESP_LOGD(TAG, "CHILD_ADDED fired but no child in neighbor table (stale restore?)");
        } else {
            ESP_LOGI(TAG, "Device joined: rloc16=0x%04X, ext_addr=%02x%02x%02x%02x%02x%02x%02x%02x",
                     info.rloc16, info.ext_addr[0], info.ext_addr[1], info.ext_addr[2], info.ext_addr[3],
                     info.ext_addr[4], info.ext_addr[5], info.ext_addr[6], info.ext_addr[7]);
            esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_DEVICE_JOINED, &info, sizeof(info), pdMS_TO_TICKS(100));
        }
    }

    if (flags & OT_CHANGED_THREAD_CHILD_REMOVED) {
        ESP_LOGI(TAG, "Device left the network (device_count=%d)", thread_br_get_device_count());
        esp_event_post(THREAD_BR_EVENTS, THREAD_BR_EVENT_DEVICE_LEFT, NULL, 0, pdMS_TO_TICKS(100));
    }

    if (flags & OT_CHANGED_THREAD_NETDATA) {
        ESP_LOGD(TAG, "Network data changed");
    }
}

static thread_br_state_t convert_ot_role(otDeviceRole role)
{
    switch (role) {
        case OT_DEVICE_ROLE_DISABLED:
            return THREAD_BR_STATE_DISABLED;
        case OT_DEVICE_ROLE_DETACHED:
            return THREAD_BR_STATE_DETACHED;
        case OT_DEVICE_ROLE_CHILD:
            return THREAD_BR_STATE_CHILD;
        case OT_DEVICE_ROLE_ROUTER:
            return THREAD_BR_STATE_ROUTER;
        case OT_DEVICE_ROLE_LEADER:
            return THREAD_BR_STATE_LEADER;
        default:
            return THREAD_BR_STATE_DISABLED;
    }
}

/*******************************************************************************
 * Status and Information
 ******************************************************************************/

bool thread_br_is_running(void)
{
    return s_started && (s_state >= THREAD_BR_STATE_CHILD);
}

thread_br_state_t thread_br_get_state(void)
{
    return s_state;
}

const char *thread_br_state_to_string(thread_br_state_t state)
{
    switch (state) {
        case THREAD_BR_STATE_DISABLED:  return "disabled";
        case THREAD_BR_STATE_DETACHED:  return "detached";
        case THREAD_BR_STATE_ATTACHING: return "attaching";
        case THREAD_BR_STATE_CHILD:     return "child";
        case THREAD_BR_STATE_ROUTER:    return "router";
        case THREAD_BR_STATE_LEADER:    return "leader";
        default:                        return "unknown";
    }
}

esp_err_t thread_br_get_status(thread_br_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    memset(status, 0, sizeof(thread_br_status_t));
    status->state = s_state;
    status->attached_time_us = s_attached_time_us;

    if (!s_initialized || s_ot_instance == NULL) {
        return ESP_OK;
    }

    /* Get network info from OpenThread */
    status->pan_id = otLinkGetPanId(s_ot_instance);
    status->channel = otLinkGetChannel(s_ot_instance);
    status->rloc16 = otThreadGetRloc16(s_ot_instance);

    const char *net_name = otThreadGetNetworkName(s_ot_instance);
    if (net_name != NULL) {
        strncpy(status->network_name, net_name, THREAD_NETWORK_NAME_MAX_LEN);
    }

    /* Count devices (simplified - just check if we're leader) */
    status->device_count = thread_br_get_device_count();
    status->border_routing_enabled = s_started;

    return ESP_OK;
}

uint8_t thread_br_get_device_count(void)
{
    if (!s_started || s_ot_instance == NULL) {
        return 0;
    }

    /* Count children */
    uint8_t count = 1;  /* Include self */

    otNeighborInfoIterator iterator = OT_NEIGHBOR_INFO_ITERATOR_INIT;
    otNeighborInfo info;

    while (otThreadGetNextNeighborInfo(s_ot_instance, &iterator, &info) == OT_ERROR_NONE) {
        count++;
    }

    return count;
}

/*******************************************************************************
 * NVS Credential Storage
 ******************************************************************************/

bool thread_br_has_credentials(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_THREAD, NVS_READONLY, &handle);
    if (err != ESP_OK) {
        return false;
    }

    uint8_t creds_set = 0;
    err = nvs_get_u8(handle, NVS_KEY_CREDENTIALS_SET, &creds_set);
    nvs_close(handle);

    return (err == ESP_OK && creds_set == 1);
}

static esp_err_t load_credentials_from_nvs(thread_network_credentials_t *creds)
{
    if (creds == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_THREAD, NVS_READONLY, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_ERR_NOT_FOUND;
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(err));
        return err;
    }

    /* Check if credentials are set */
    uint8_t creds_set = 0;
    err = nvs_get_u8(handle, NVS_KEY_CREDENTIALS_SET, &creds_set);
    if (err != ESP_OK || creds_set != 1) {
        nvs_close(handle);
        return ESP_ERR_NOT_FOUND;
    }

    memset(creds, 0, sizeof(thread_network_credentials_t));

    /* Load each field */
    size_t len = sizeof(creds->network_name);
    nvs_get_str(handle, NVS_KEY_NETWORK_NAME, creds->network_name, &len);

    nvs_get_u16(handle, NVS_KEY_PAN_ID, &creds->pan_id);

    uint8_t channel = 0;
    nvs_get_u8(handle, NVS_KEY_CHANNEL, &channel);
    creds->channel = channel;

    len = sizeof(creds->network_key);
    nvs_get_blob(handle, NVS_KEY_NETWORK_KEY, creds->network_key, &len);

    len = sizeof(creds->extended_pan_id);
    nvs_get_blob(handle, NVS_KEY_EXTPANID, creds->extended_pan_id, &len);

    len = sizeof(creds->mesh_local_prefix);
    nvs_get_blob(handle, NVS_KEY_MESH_PREFIX, creds->mesh_local_prefix, &len);

    len = sizeof(creds->pskc);
    nvs_get_blob(handle, NVS_KEY_PSKC, creds->pskc, &len);

    nvs_close(handle);

    ESP_LOGI(TAG, "Loaded Thread credentials from NVS");
    return ESP_OK;
}

static esp_err_t save_credentials_to_nvs(const thread_network_credentials_t *creds)
{
    if (creds == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_THREAD, NVS_READWRITE, &handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for writing: %s", esp_err_to_name(err));
        return err;
    }

    /* Save each field */
    err = nvs_set_str(handle, NVS_KEY_NETWORK_NAME, creds->network_name);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_u16(handle, NVS_KEY_PAN_ID, creds->pan_id);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_u8(handle, NVS_KEY_CHANNEL, creds->channel);
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_blob(handle, NVS_KEY_NETWORK_KEY, creds->network_key, sizeof(creds->network_key));
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_blob(handle, NVS_KEY_EXTPANID, creds->extended_pan_id, sizeof(creds->extended_pan_id));
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_blob(handle, NVS_KEY_MESH_PREFIX, creds->mesh_local_prefix, sizeof(creds->mesh_local_prefix));
    if (err != ESP_OK) goto cleanup;

    err = nvs_set_blob(handle, NVS_KEY_PSKC, creds->pskc, sizeof(creds->pskc));
    if (err != ESP_OK) goto cleanup;

    /* Mark credentials as valid */
    err = nvs_set_u8(handle, NVS_KEY_CREDENTIALS_SET, 1);
    if (err != ESP_OK) goto cleanup;

    err = nvs_commit(handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(err));
        goto cleanup;
    }

    ESP_LOGI(TAG, "Saved Thread credentials to NVS");

cleanup:
    nvs_close(handle);
    return err;
}

esp_err_t thread_br_get_credentials(thread_network_credentials_t *creds)
{
    return load_credentials_from_nvs(creds);
}

esp_err_t thread_br_ensure_credentials(void)
{
    /* Check if credentials already exist */
    if (thread_br_has_credentials()) {
        ESP_LOGI(TAG, "Thread credentials already exist in NVS");
        return ESP_OK;
    }

    /* Generate new credentials */
    ESP_LOGI(TAG, "Generating Thread network credentials...");
    return thread_br_generate_credentials();
}

esp_err_t thread_br_get_network_key_hex(char *hex_str, size_t max_len)
{
    if (hex_str == NULL || max_len < 33) {
        return ESP_ERR_INVALID_ARG;
    }

    thread_network_credentials_t creds;
    esp_err_t ret = load_credentials_from_nvs(&creds);
    if (ret != ESP_OK) {
        return ret;
    }

    for (int i = 0; i < THREAD_NETWORK_KEY_LEN; i++) {
        snprintf(hex_str + (i * 2), 3, "%02x", creds.network_key[i]);
    }
    hex_str[32] = '\0';

    return ESP_OK;
}

esp_err_t thread_br_get_extpanid_hex(char *hex_str, size_t max_len)
{
    if (hex_str == NULL || max_len < 17) {
        return ESP_ERR_INVALID_ARG;
    }

    thread_network_credentials_t creds;
    esp_err_t ret = load_credentials_from_nvs(&creds);
    if (ret != ESP_OK) {
        return ret;
    }

    for (int i = 0; i < THREAD_EXTPANID_LEN; i++) {
        snprintf(hex_str + (i * 2), 3, "%02x", creds.extended_pan_id[i]);
    }
    hex_str[16] = '\0';

    return ESP_OK;
}

esp_err_t thread_br_generate_credentials(void)
{
    thread_network_credentials_t creds;
    memset(&creds, 0, sizeof(creds));

    /* Set defaults */
    strncpy(creds.network_name, THREAD_DEFAULT_NETWORK_NAME, THREAD_NETWORK_NAME_MAX_LEN);
    creds.pan_id = THREAD_DEFAULT_PAN_ID;
    creds.channel = THREAD_DEFAULT_CHANNEL;

    /* Generate random network key */
    esp_fill_random(creds.network_key, sizeof(creds.network_key));

    /* Generate random extended PAN ID */
    esp_fill_random(creds.extended_pan_id, sizeof(creds.extended_pan_id));

    /* Generate mesh-local prefix (fd00::/64 with random suffix) */
    creds.mesh_local_prefix[0] = 0xfd;
    creds.mesh_local_prefix[1] = 0x00;
    esp_fill_random(&creds.mesh_local_prefix[2], 6);

    /* Generate random PSKc */
    esp_fill_random(creds.pskc, sizeof(creds.pskc));

    ESP_LOGI(TAG, "Generated new Thread network credentials:");
    ESP_LOGI(TAG, "  Network: %s", creds.network_name);
    ESP_LOGI(TAG, "  PAN ID: 0x%04X", creds.pan_id);
    ESP_LOGI(TAG, "  Channel: %d", creds.channel);

    return save_credentials_to_nvs(&creds);
}

esp_err_t thread_br_clear_credentials(void)
{
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE_THREAD, NVS_READWRITE, &handle);
    if (err == ESP_ERR_NVS_NOT_FOUND) {
        return ESP_OK;  /* Nothing to clear */
    } else if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_erase_all(handle);
    if (err == ESP_OK) {
        err = nvs_commit(handle);
    }

    nvs_close(handle);

    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Thread credentials cleared");
    }

    return err;
}

/*******************************************************************************
 * Dataset Configuration
 ******************************************************************************/

static esp_err_t apply_credentials_to_dataset(const thread_network_credentials_t *creds)
{
    if (creds == NULL || s_ot_instance == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    otOperationalDataset dataset;
    memset(&dataset, 0, sizeof(dataset));

    /* Network name */
    size_t name_len = strlen(creds->network_name);
    if (name_len > OT_NETWORK_NAME_MAX_SIZE) {
        name_len = OT_NETWORK_NAME_MAX_SIZE;
    }
    memcpy(dataset.mNetworkName.m8, creds->network_name, name_len);
    dataset.mComponents.mIsNetworkNamePresent = true;

    /* PAN ID */
    dataset.mPanId = creds->pan_id;
    dataset.mComponents.mIsPanIdPresent = true;

    /* Channel */
    dataset.mChannel = creds->channel;
    dataset.mComponents.mIsChannelPresent = true;

    /* Network key */
    memcpy(dataset.mNetworkKey.m8, creds->network_key, OT_NETWORK_KEY_SIZE);
    dataset.mComponents.mIsNetworkKeyPresent = true;

    /* Extended PAN ID */
    memcpy(dataset.mExtendedPanId.m8, creds->extended_pan_id, OT_EXT_PAN_ID_SIZE);
    dataset.mComponents.mIsExtendedPanIdPresent = true;

    /* Mesh-local prefix */
    memcpy(dataset.mMeshLocalPrefix.m8, creds->mesh_local_prefix, OT_MESH_LOCAL_PREFIX_SIZE);
    dataset.mComponents.mIsMeshLocalPrefixPresent = true;

    /* PSKc */
    memcpy(dataset.mPskc.m8, creds->pskc, OT_PSKC_MAX_SIZE);
    dataset.mComponents.mIsPskcPresent = true;

    /* Active timestamp (required) */
    dataset.mActiveTimestamp.mSeconds = 1;
    dataset.mActiveTimestamp.mTicks = 0;
    dataset.mActiveTimestamp.mAuthoritative = false;
    dataset.mComponents.mIsActiveTimestampPresent = true;

    /* Security policy */
    dataset.mSecurityPolicy.mRotationTime = 672;  /* 672 hours = 4 weeks */
    dataset.mSecurityPolicy.mObtainNetworkKeyEnabled = true;
    dataset.mSecurityPolicy.mNativeCommissioningEnabled = true;
    dataset.mSecurityPolicy.mRoutersEnabled = true;
    dataset.mSecurityPolicy.mExternalCommissioningEnabled = true;
    dataset.mComponents.mIsSecurityPolicyPresent = true;

    /* Set as active dataset */
    otError error = otDatasetSetActive(s_ot_instance, &dataset);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to set active dataset: %d", error);
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Applied Thread dataset successfully");
    return ESP_OK;
}

/*******************************************************************************
 * Commissioning
 ******************************************************************************/

esp_err_t thread_br_enable_joining(uint32_t duration_sec)
{
    if (!s_started || s_ot_instance == NULL) {
        ESP_LOGE(TAG, "Thread BR not started");
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state < THREAD_BR_STATE_ROUTER) {
        ESP_LOGE(TAG, "Must be router or leader to enable joining");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Enabling device joining for %lu seconds", (unsigned long)duration_sec);

    /* Start commissioner */
    otError error = otCommissionerStart(s_ot_instance, NULL, NULL, NULL);
    if (error != OT_ERROR_NONE && error != OT_ERROR_ALREADY) {
        ESP_LOGE(TAG, "Failed to start commissioner: %d", error);
        return ESP_FAIL;
    }

    /* Allow any joiner with PSKd "SVJOIN" (can be customized) */
    error = otCommissionerAddJoiner(s_ot_instance, NULL, "SVJOIN",
                                     duration_sec > 0 ? duration_sec * 1000 : 0xFFFFFFFF);
    if (error != OT_ERROR_NONE) {
        ESP_LOGE(TAG, "Failed to add joiner: %d", error);
        return ESP_FAIL;
    }

    s_joining_enabled = true;
    ESP_LOGI(TAG, "Device joining enabled (PSKd: SVJOIN)");
    return ESP_OK;
}

esp_err_t thread_br_disable_joining(void)
{
    if (!s_started || s_ot_instance == NULL) {
        return ESP_OK;
    }

    otCommissionerRemoveJoiner(s_ot_instance, NULL);
    otCommissionerStop(s_ot_instance);

    s_joining_enabled = false;
    ESP_LOGI(TAG, "Device joining disabled");
    return ESP_OK;
}

bool thread_br_is_joining_enabled(void)
{
    return s_joining_enabled;
}
