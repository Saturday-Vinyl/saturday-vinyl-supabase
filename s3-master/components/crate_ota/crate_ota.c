/**
 * @file crate_ota.c
 * @brief Crate OTA Relay Implementation
 *
 * Downloads firmware from Supabase and relays to Thread crates via H2.
 *
 * Phase 4: Crate OTA Relay
 */

#include "crate_ota.h"
#include "h2_comm.h"
#include "supabase_client.h"
#include "realtime_client.h"
#include "s3_h2_protocol.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "esp_timer.h"
#include "mbedtls/sha256.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"
#include <string.h>
#include <stdlib.h>

static const char *TAG = "CRATE_OTA";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/

ESP_EVENT_DEFINE_BASE(CRATE_OTA_EVENTS);

/*******************************************************************************
 * Module State
 ******************************************************************************/

/** Event bits for synchronization */
#define EVT_PING_RESPONSE   BIT0
#define EVT_CHUNK_ACK       BIT1
#define EVT_OTA_COMPLETE    BIT2
#define EVT_ABORT           BIT3

typedef struct {
    bool initialized;
    crate_ota_config_t config;
    crate_ota_status_t status;

    /* Synchronization */
    SemaphoreHandle_t mutex;
    EventGroupHandle_t events;
    TaskHandle_t task;

    /* OTA session data */
    uint8_t *firmware_buf;          /**< Firmware download buffer */
    uint32_t firmware_downloaded;   /**< Bytes downloaded so far */
    uint8_t expected_sha256[32];    /**< Expected hash (binary) */
    bool has_expected_hash;         /**< Whether hash was provided */

    /* Ping response data */
    bool ping_result;
    int8_t ping_rssi;

    /* H2 response tracking */
    uint8_t last_error_code;
} crate_ota_ctx_t;

static crate_ota_ctx_t s_ota = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/

static void ota_task(void *arg);
static esp_err_t download_firmware(const char *url);
static esp_err_t verify_firmware_hash(void);
static esp_err_t send_to_crate(void);
static void report_status_to_cloud(const char *status, const char *error_msg);

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t crate_ota_init(const crate_ota_config_t *config)
{
    if (s_ota.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing Crate OTA module...");

    memset(&s_ota, 0, sizeof(s_ota));

    /* Apply configuration */
    if (config != NULL) {
        s_ota.config = *config;
    } else {
        crate_ota_config_t defaults = CRATE_OTA_CONFIG_DEFAULT();
        s_ota.config = defaults;
    }

    /* Create synchronization primitives */
    s_ota.mutex = xSemaphoreCreateMutex();
    if (s_ota.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    s_ota.events = xEventGroupCreate();
    if (s_ota.events == NULL) {
        ESP_LOGE(TAG, "Failed to create event group");
        vSemaphoreDelete(s_ota.mutex);
        return ESP_ERR_NO_MEM;
    }

    s_ota.status.state = CRATE_OTA_STATE_IDLE;
    s_ota.initialized = true;

    ESP_LOGI(TAG, "Crate OTA module initialized");
    return ESP_OK;
}

esp_err_t crate_ota_deinit(void)
{
    if (!s_ota.initialized) {
        return ESP_OK;
    }

    /* Abort any in-progress OTA */
    crate_ota_abort();

    /* Free resources */
    if (s_ota.firmware_buf != NULL) {
        free(s_ota.firmware_buf);
        s_ota.firmware_buf = NULL;
    }

    if (s_ota.events != NULL) {
        vEventGroupDelete(s_ota.events);
    }
    if (s_ota.mutex != NULL) {
        vSemaphoreDelete(s_ota.mutex);
    }

    memset(&s_ota, 0, sizeof(s_ota));
    ESP_LOGI(TAG, "Crate OTA module deinitialized");
    return ESP_OK;
}

/*******************************************************************************
 * Public API
 ******************************************************************************/

esp_err_t crate_ota_start(const uint8_t *crate_ext_addr,
                          const char *firmware_url,
                          uint32_t firmware_size,
                          const char *sha256_hex,
                          const char *version,
                          const char *request_id)
{
    if (!s_ota.initialized) {
        ESP_LOGE(TAG, "Not initialized");
        return ESP_ERR_INVALID_STATE;
    }

    if (crate_ext_addr == NULL || firmware_url == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (firmware_size > CRATE_OTA_MAX_FIRMWARE_SIZE) {
        ESP_LOGE(TAG, "Firmware too large: %lu > %d",
                 (unsigned long)firmware_size, CRATE_OTA_MAX_FIRMWARE_SIZE);
        return ESP_ERR_INVALID_SIZE;
    }

    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);

    if (s_ota.status.state != CRATE_OTA_STATE_IDLE) {
        xSemaphoreGive(s_ota.mutex);
        ESP_LOGE(TAG, "OTA already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    /* Initialize session */
    memset(&s_ota.status, 0, sizeof(s_ota.status));
    memcpy(s_ota.status.target_crate, crate_ext_addr, 8);
    s_ota.status.firmware_size = firmware_size;
    s_ota.status.start_time_ms = esp_timer_get_time() / 1000;

    if (version != NULL) {
        strncpy(s_ota.status.version, version, sizeof(s_ota.status.version) - 1);
    }
    if (request_id != NULL) {
        strncpy(s_ota.status.request_id, request_id, sizeof(s_ota.status.request_id) - 1);
    }

    /* Parse SHA256 hex string */
    s_ota.has_expected_hash = false;
    if (sha256_hex != NULL && strlen(sha256_hex) == 64) {
        for (int i = 0; i < 32; i++) {
            unsigned int byte;
            if (sscanf(&sha256_hex[i * 2], "%02x", &byte) == 1) {
                s_ota.expected_sha256[i] = (uint8_t)byte;
            }
        }
        s_ota.has_expected_hash = true;
    }

    /* Allocate firmware buffer */
    if (s_ota.firmware_buf != NULL) {
        free(s_ota.firmware_buf);
    }
    s_ota.firmware_buf = malloc(firmware_size);
    if (s_ota.firmware_buf == NULL) {
        xSemaphoreGive(s_ota.mutex);
        ESP_LOGE(TAG, "Failed to allocate firmware buffer (%lu bytes)",
                 (unsigned long)firmware_size);
        return ESP_ERR_NO_MEM;
    }

    s_ota.firmware_downloaded = 0;
    s_ota.status.state = CRATE_OTA_STATE_PINGING;
    xEventGroupClearBits(s_ota.events, 0xFF);

    xSemaphoreGive(s_ota.mutex);

    /* Log target crate */
    ESP_LOGI(TAG, "Starting OTA to crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             crate_ext_addr[0], crate_ext_addr[1], crate_ext_addr[2], crate_ext_addr[3],
             crate_ext_addr[4], crate_ext_addr[5], crate_ext_addr[6], crate_ext_addr[7]);
    ESP_LOGI(TAG, "  Version: %s, Size: %lu bytes", version, (unsigned long)firmware_size);
    ESP_LOGI(TAG, "  URL: %s", firmware_url);

    /* Start OTA task */
    /* Store URL in a static buffer for task (simplified - real impl would use dynamic alloc) */
    static char s_firmware_url[256];
    strncpy(s_firmware_url, firmware_url, sizeof(s_firmware_url) - 1);

    BaseType_t ret = xTaskCreate(ota_task, "crate_ota", 8192, s_firmware_url, 5, &s_ota.task);
    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create OTA task");
        free(s_ota.firmware_buf);
        s_ota.firmware_buf = NULL;
        s_ota.status.state = CRATE_OTA_STATE_IDLE;
        return ESP_FAIL;
    }

    /* Post start event */
    esp_event_post(CRATE_OTA_EVENTS, CRATE_OTA_EVENT_START, NULL, 0, 0);

    return ESP_OK;
}

esp_err_t crate_ota_abort(void)
{
    if (!s_ota.initialized) {
        return ESP_OK;
    }

    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);

    if (s_ota.status.state == CRATE_OTA_STATE_IDLE) {
        xSemaphoreGive(s_ota.mutex);
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGW(TAG, "Aborting OTA");

    /* Signal abort to task */
    xEventGroupSetBits(s_ota.events, EVT_ABORT);

    /* Send abort command to H2 if we're in transfer phase */
    if (s_ota.status.state == CRATE_OTA_STATE_TRANSFERRING ||
        s_ota.status.state == CRATE_OTA_STATE_VERIFYING) {
        s3h2_ota_abort_crate_payload_t abort_payload;
        memcpy(abort_payload.crate_ext_addr, s_ota.status.target_crate, 8);
        /* Note: Would need h2_comm_send_command() function - simplified here */
    }

    xSemaphoreGive(s_ota.mutex);

    /* Wait for task to finish */
    if (s_ota.task != NULL) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    return ESP_OK;
}

esp_err_t crate_ota_get_status(crate_ota_status_t *status)
{
    if (status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    memcpy(status, &s_ota.status, sizeof(crate_ota_status_t));
    status->elapsed_ms = (esp_timer_get_time() / 1000) - s_ota.status.start_time_ms;
    xSemaphoreGive(s_ota.mutex);

    return ESP_OK;
}

bool crate_ota_is_busy(void)
{
    return s_ota.status.state != CRATE_OTA_STATE_IDLE &&
           s_ota.status.state != CRATE_OTA_STATE_COMPLETE &&
           s_ota.status.state != CRATE_OTA_STATE_FAILED;
}

esp_err_t crate_ota_ping(const uint8_t *crate_ext_addr,
                         uint32_t timeout_ms,
                         int8_t *rssi)
{
    if (!s_ota.initialized || crate_ext_addr == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!h2_comm_is_connected()) {
        ESP_LOGE(TAG, "H2 not connected");
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGI(TAG, "Pinging crate %02X:%02X:%02X:%02X:%02X:%02X:%02X:%02X",
             crate_ext_addr[0], crate_ext_addr[1], crate_ext_addr[2], crate_ext_addr[3],
             crate_ext_addr[4], crate_ext_addr[5], crate_ext_addr[6], crate_ext_addr[7]);

    /* Clear ping result */
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.ping_result = false;
    s_ota.ping_rssi = 0;
    xEventGroupClearBits(s_ota.events, EVT_PING_RESPONSE);
    xSemaphoreGive(s_ota.mutex);

    /* Send ping command to H2 */
    /* Note: This requires extending h2_comm with a generic send function
     * For now, we'll use a placeholder that would call h2_comm_send_raw() */
    s3h2_ping_crate_payload_t ping_payload;
    memcpy(ping_payload.crate_ext_addr, crate_ext_addr, 8);

    /* TODO: Actually send to H2 - requires h2_comm extension */
    /* esp_err_t err = h2_comm_send_command(S3H2_CMD_PING_CRATE,
     *                                      &ping_payload, sizeof(ping_payload),
     *                                      timeout_ms); */

    /* Wait for response */
    EventBits_t bits = xEventGroupWaitBits(s_ota.events, EVT_PING_RESPONSE,
                                           pdTRUE, pdFALSE,
                                           pdMS_TO_TICKS(timeout_ms));

    if (bits & EVT_PING_RESPONSE) {
        xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
        bool reachable = s_ota.ping_result;
        if (rssi != NULL) {
            *rssi = s_ota.ping_rssi;
        }
        xSemaphoreGive(s_ota.mutex);

        if (reachable) {
            ESP_LOGI(TAG, "Crate is reachable (RSSI: %d dBm)", s_ota.ping_rssi);
            return ESP_OK;
        } else {
            ESP_LOGW(TAG, "Crate not reachable");
            return ESP_ERR_NOT_FOUND;
        }
    }

    ESP_LOGW(TAG, "Crate ping timeout");
    return ESP_ERR_TIMEOUT;
}

/*******************************************************************************
 * H2 Event Handler
 ******************************************************************************/

void crate_ota_handle_h2_event(uint8_t event_type,
                               const uint8_t *payload,
                               uint16_t payload_len)
{
    if (!s_ota.initialized) {
        return;
    }

    switch (event_type) {
        case S3H2_EVT_CRATE_PING_RESULT: {
            if (payload_len >= sizeof(s3h2_ping_result_payload_t)) {
                const s3h2_ping_result_payload_t *ping =
                    (const s3h2_ping_result_payload_t *)payload;

                xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
                s_ota.ping_result = ping->reachable;
                s_ota.ping_rssi = ping->rssi;
                xSemaphoreGive(s_ota.mutex);

                xEventGroupSetBits(s_ota.events, EVT_PING_RESPONSE);
            }
            break;
        }

        case S3H2_EVT_OTA_PROGRESS: {
            if (payload_len >= sizeof(s3h2_ota_progress_payload_t)) {
                const s3h2_ota_progress_payload_t *progress =
                    (const s3h2_ota_progress_payload_t *)payload;

                xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
                s_ota.status.bytes_acked = progress->bytes_sent;
                s_ota.status.percent = progress->percent;
                xSemaphoreGive(s_ota.mutex);

                /* Signal chunk ACK for flow control */
                xEventGroupSetBits(s_ota.events, EVT_CHUNK_ACK);

                /* Post progress event */
                crate_ota_progress_event_t event;
                memcpy(event.crate_ext_addr, progress->crate_ext_addr, 8);
                event.percent = progress->percent;
                event.bytes_sent = progress->bytes_sent;
                event.total_bytes = progress->total_bytes;
                esp_event_post(CRATE_OTA_EVENTS, CRATE_OTA_EVENT_PROGRESS,
                               &event, sizeof(event), 0);

                ESP_LOGI(TAG, "OTA progress: %d%% (%lu/%lu bytes)",
                         progress->percent,
                         (unsigned long)progress->bytes_sent,
                         (unsigned long)progress->total_bytes);
            }
            break;
        }

        case S3H2_EVT_OTA_COMPLETE: {
            if (payload_len >= sizeof(s3h2_ota_complete_payload_t)) {
                const s3h2_ota_complete_payload_t *complete =
                    (const s3h2_ota_complete_payload_t *)payload;

                xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
                s_ota.last_error_code = complete->error_code;
                if (complete->success) {
                    s_ota.status.state = CRATE_OTA_STATE_COMPLETE;
                    s_ota.status.percent = 100;
                } else {
                    s_ota.status.state = CRATE_OTA_STATE_FAILED;
                }
                xSemaphoreGive(s_ota.mutex);

                xEventGroupSetBits(s_ota.events, EVT_OTA_COMPLETE);

                if (complete->success) {
                    ESP_LOGI(TAG, "Crate OTA completed successfully");
                } else {
                    ESP_LOGE(TAG, "Crate OTA failed: error=%d", complete->error_code);
                }
            }
            break;
        }

        default:
            break;
    }
}

/*******************************************************************************
 * OTA Task
 ******************************************************************************/

static void ota_task(void *arg)
{
    const char *firmware_url = (const char *)arg;
    esp_err_t err;
    crate_ota_result_event_t result_event = {0};

    memcpy(result_event.crate_ext_addr, s_ota.status.target_crate, 8);

    /* Report starting to cloud */
    report_status_to_cloud("downloading", NULL);

    /* Step 1: Ping crate to verify reachability */
    ESP_LOGI(TAG, "Step 1: Checking crate reachability...");
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_PINGING;
    xSemaphoreGive(s_ota.mutex);

    err = crate_ota_ping(s_ota.status.target_crate, s_ota.config.ping_timeout_ms, NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Crate not reachable - aborting OTA");
        result_event.success = false;
        result_event.error = ESP_ERR_NOT_FOUND;
        strncpy(result_event.error_message, "device_unreachable",
                sizeof(result_event.error_message) - 1);
        goto fail;
    }

    /* Check for abort */
    if (xEventGroupGetBits(s_ota.events) & EVT_ABORT) {
        goto aborted;
    }

    /* Step 2: Download firmware */
    ESP_LOGI(TAG, "Step 2: Downloading firmware...");
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_DOWNLOADING;
    xSemaphoreGive(s_ota.mutex);

    err = download_firmware(firmware_url);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Firmware download failed: %s", esp_err_to_name(err));
        result_event.success = false;
        result_event.error = err;
        strncpy(result_event.error_message, "download_failed",
                sizeof(result_event.error_message) - 1);
        goto fail;
    }

    /* Check for abort */
    if (xEventGroupGetBits(s_ota.events) & EVT_ABORT) {
        goto aborted;
    }

    /* Step 3: Verify hash if provided */
    if (s_ota.has_expected_hash && s_ota.config.verify_sha256) {
        ESP_LOGI(TAG, "Step 3: Verifying firmware hash...");
        err = verify_firmware_hash();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Firmware hash verification failed");
            result_event.success = false;
            result_event.error = err;
            strncpy(result_event.error_message, "checksum_mismatch",
                    sizeof(result_event.error_message) - 1);
            goto fail;
        }
    }

    /* Step 4: Transfer to crate via H2 */
    ESP_LOGI(TAG, "Step 4: Transferring to crate via H2...");
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_TRANSFERRING;
    xSemaphoreGive(s_ota.mutex);

    report_status_to_cloud("applying", NULL);

    err = send_to_crate();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Transfer to crate failed: %s", esp_err_to_name(err));
        result_event.success = false;
        result_event.error = err;
        strncpy(result_event.error_message, "transfer_failed",
                sizeof(result_event.error_message) - 1);
        goto fail;
    }

    /* Wait for OTA completion from H2 */
    ESP_LOGI(TAG, "Step 5: Waiting for crate to apply update...");
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_VERIFYING;
    xSemaphoreGive(s_ota.mutex);

    EventBits_t bits = xEventGroupWaitBits(s_ota.events,
                                           EVT_OTA_COMPLETE | EVT_ABORT,
                                           pdTRUE, pdFALSE,
                                           pdMS_TO_TICKS(60000));  /* 60s timeout */

    if (bits & EVT_ABORT) {
        goto aborted;
    }

    if (!(bits & EVT_OTA_COMPLETE)) {
        ESP_LOGE(TAG, "OTA completion timeout");
        result_event.success = false;
        result_event.error = ESP_ERR_TIMEOUT;
        strncpy(result_event.error_message, "timeout",
                sizeof(result_event.error_message) - 1);
        goto fail;
    }

    /* Check final status */
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    bool success = (s_ota.status.state == CRATE_OTA_STATE_COMPLETE);
    xSemaphoreGive(s_ota.mutex);

    if (success) {
        ESP_LOGI(TAG, "Crate OTA completed successfully!");
        result_event.success = true;
        result_event.error = ESP_OK;

        /* Report success to cloud */
        report_status_to_cloud("complete", NULL);

        /* Post success event */
        esp_event_post(CRATE_OTA_EVENTS, CRATE_OTA_EVENT_COMPLETE,
                       &result_event, sizeof(result_event), 0);
    } else {
        result_event.success = false;
        result_event.error = ESP_FAIL;
        snprintf(result_event.error_message, sizeof(result_event.error_message),
                 "crate_error_%d", s_ota.last_error_code);
        goto fail;
    }

    /* Cleanup */
    goto cleanup;

fail:
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_FAILED;
    xSemaphoreGive(s_ota.mutex);

    /* Report failure to cloud */
    report_status_to_cloud("failed", result_event.error_message);

    /* Post failure event */
    esp_event_post(CRATE_OTA_EVENTS, CRATE_OTA_EVENT_FAILED,
                   &result_event, sizeof(result_event), 0);
    goto cleanup;

aborted:
    ESP_LOGW(TAG, "OTA aborted");
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    s_ota.status.state = CRATE_OTA_STATE_FAILED;
    xSemaphoreGive(s_ota.mutex);

    result_event.success = false;
    result_event.error = ESP_ERR_INVALID_STATE;
    strncpy(result_event.error_message, "aborted", sizeof(result_event.error_message) - 1);

    report_status_to_cloud("failed", "aborted");
    esp_event_post(CRATE_OTA_EVENTS, CRATE_OTA_EVENT_FAILED,
                   &result_event, sizeof(result_event), 0);

cleanup:
    /* Free firmware buffer */
    xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
    if (s_ota.firmware_buf != NULL) {
        free(s_ota.firmware_buf);
        s_ota.firmware_buf = NULL;
    }
    s_ota.task = NULL;

    /* Reset to idle if complete/failed */
    if (s_ota.status.state == CRATE_OTA_STATE_COMPLETE ||
        s_ota.status.state == CRATE_OTA_STATE_FAILED) {
        /* Keep state for status query, but mark as done */
    }
    xSemaphoreGive(s_ota.mutex);

    vTaskDelete(NULL);
}

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static esp_err_t download_firmware(const char *url)
{
    ESP_LOGI(TAG, "Downloading from: %s", url);

    esp_http_client_config_t http_cfg = {
        .url = url,
        .timeout_ms = 30000,
        .buffer_size = CRATE_OTA_DOWNLOAD_CHUNK_SIZE,
    };

    esp_http_client_handle_t client = esp_http_client_init(&http_cfg);
    if (client == NULL) {
        ESP_LOGE(TAG, "Failed to init HTTP client");
        return ESP_FAIL;
    }

    esp_err_t err = esp_http_client_open(client, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "HTTP open failed: %s", esp_err_to_name(err));
        esp_http_client_cleanup(client);
        return err;
    }

    int content_length = esp_http_client_fetch_headers(client);
    if (content_length < 0) {
        ESP_LOGE(TAG, "Failed to fetch headers");
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return ESP_FAIL;
    }

    int status = esp_http_client_get_status_code(client);
    if (status != 200) {
        ESP_LOGE(TAG, "HTTP status %d", status);
        esp_http_client_close(client);
        esp_http_client_cleanup(client);
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Content-Length: %d", content_length);

    /* Verify size matches */
    if (content_length > 0 && (uint32_t)content_length != s_ota.status.firmware_size) {
        ESP_LOGW(TAG, "Size mismatch: expected %lu, got %d",
                 (unsigned long)s_ota.status.firmware_size, content_length);
    }

    /* Download in chunks */
    s_ota.firmware_downloaded = 0;
    int read_len;
    uint8_t *buf_ptr = s_ota.firmware_buf;
    uint32_t remaining = s_ota.status.firmware_size;

    while (remaining > 0) {
        /* Check for abort */
        if (xEventGroupGetBits(s_ota.events) & EVT_ABORT) {
            esp_http_client_close(client);
            esp_http_client_cleanup(client);
            return ESP_ERR_INVALID_STATE;
        }

        uint32_t to_read = (remaining > CRATE_OTA_DOWNLOAD_CHUNK_SIZE) ?
                           CRATE_OTA_DOWNLOAD_CHUNK_SIZE : remaining;

        read_len = esp_http_client_read(client, (char *)buf_ptr, to_read);
        if (read_len < 0) {
            ESP_LOGE(TAG, "Read error");
            esp_http_client_close(client);
            esp_http_client_cleanup(client);
            return ESP_FAIL;
        } else if (read_len == 0) {
            break;  /* EOF */
        }

        buf_ptr += read_len;
        remaining -= read_len;
        s_ota.firmware_downloaded += read_len;

        /* Update progress */
        uint8_t percent = (s_ota.firmware_downloaded * 50) / s_ota.status.firmware_size;
        xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
        s_ota.status.percent = percent;  /* 0-50% for download phase */
        xSemaphoreGive(s_ota.mutex);

        ESP_LOGD(TAG, "Downloaded %lu/%lu bytes (%d%%)",
                 (unsigned long)s_ota.firmware_downloaded,
                 (unsigned long)s_ota.status.firmware_size,
                 percent);
    }

    esp_http_client_close(client);
    esp_http_client_cleanup(client);

    if (s_ota.firmware_downloaded != s_ota.status.firmware_size) {
        ESP_LOGE(TAG, "Download incomplete: %lu/%lu",
                 (unsigned long)s_ota.firmware_downloaded,
                 (unsigned long)s_ota.status.firmware_size);
        return ESP_ERR_INVALID_SIZE;
    }

    ESP_LOGI(TAG, "Download complete: %lu bytes", (unsigned long)s_ota.firmware_downloaded);
    return ESP_OK;
}

static esp_err_t verify_firmware_hash(void)
{
    ESP_LOGI(TAG, "Computing SHA-256...");

    uint8_t computed_hash[32];
    mbedtls_sha256_context ctx;

    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);  /* 0 = SHA-256, not SHA-224 */
    mbedtls_sha256_update(&ctx, s_ota.firmware_buf, s_ota.firmware_downloaded);
    mbedtls_sha256_finish(&ctx, computed_hash);
    mbedtls_sha256_free(&ctx);

    /* Compare with expected */
    if (memcmp(computed_hash, s_ota.expected_sha256, 32) != 0) {
        ESP_LOGE(TAG, "SHA-256 mismatch!");
        ESP_LOG_BUFFER_HEX_LEVEL(TAG, computed_hash, 32, ESP_LOG_ERROR);
        ESP_LOG_BUFFER_HEX_LEVEL(TAG, s_ota.expected_sha256, 32, ESP_LOG_ERROR);
        return ESP_ERR_INVALID_CRC;
    }

    ESP_LOGI(TAG, "SHA-256 verified");
    return ESP_OK;
}

static esp_err_t send_to_crate(void)
{
    /* Send OTA_START command to H2 */
    ESP_LOGI(TAG, "Sending OTA_START to H2...");

    s3h2_ota_start_crate_payload_t start_payload = {0};
    memcpy(start_payload.crate_ext_addr, s_ota.status.target_crate, 8);
    start_payload.firmware_size = s_ota.status.firmware_size;
    memcpy(start_payload.sha256, s_ota.expected_sha256, 32);

    /* Parse version string */
    int major = 0, minor = 0, patch = 0;
    sscanf(s_ota.status.version, "%d.%d.%d", &major, &minor, &patch);
    start_payload.version_major = (uint8_t)major;
    start_payload.version_minor = (uint8_t)minor;
    start_payload.version_patch = (uint8_t)patch;

    /* TODO: Send via h2_comm - requires extension
     * esp_err_t err = h2_comm_send_command(S3H2_CMD_OTA_START_CRATE,
     *                                      &start_payload, sizeof(start_payload),
     *                                      5000);
     */

    /* For now, simulate sending - actual impl needs h2_comm extensions */
    ESP_LOGW(TAG, "NOTE: h2_comm OTA command sending not yet implemented");

    /* Send firmware data in chunks */
    uint32_t offset = 0;
    const uint32_t chunk_size = S3H2_OTA_MAX_CHUNK_SIZE;

    while (offset < s_ota.firmware_downloaded) {
        /* Check for abort */
        if (xEventGroupGetBits(s_ota.events) & EVT_ABORT) {
            return ESP_ERR_INVALID_STATE;
        }

        uint32_t remaining = s_ota.firmware_downloaded - offset;
        uint32_t this_chunk = (remaining > chunk_size) ? chunk_size : remaining;

        /* Build data payload */
        /* Note: Need to send header + data as one frame */
        s3h2_ota_data_crate_payload_t data_header = {0};
        memcpy(data_header.crate_ext_addr, s_ota.status.target_crate, 8);
        data_header.offset = offset;
        data_header.length = (uint16_t)this_chunk;

        /* TODO: Send via h2_comm with data following header */

        /* Update progress (50-95% for transfer phase) */
        uint8_t percent = 50 + ((offset * 45) / s_ota.firmware_downloaded);
        xSemaphoreTake(s_ota.mutex, portMAX_DELAY);
        s_ota.status.bytes_sent = offset + this_chunk;
        s_ota.status.percent = percent;
        xSemaphoreGive(s_ota.mutex);

        offset += this_chunk;

        /* Brief delay for flow control */
        vTaskDelay(pdMS_TO_TICKS(10));
    }

    /* Send verify command */
    ESP_LOGI(TAG, "Sending OTA_VERIFY to H2...");
    s3h2_ota_verify_crate_payload_t verify_payload = {0};
    memcpy(verify_payload.crate_ext_addr, s_ota.status.target_crate, 8);

    /* TODO: Send via h2_comm */

    return ESP_OK;
}

static void report_status_to_cloud(const char *status, const char *error_msg)
{
    if (s_ota.status.request_id[0] == '\0') {
        return;  /* No request ID to report against */
    }

    ESP_LOGI(TAG, "Reporting to cloud: status=%s", status);

    /* Use realtime_client to report status */
    realtime_client_ack_update(s_ota.status.request_id, status, "crate", error_msg);
}
