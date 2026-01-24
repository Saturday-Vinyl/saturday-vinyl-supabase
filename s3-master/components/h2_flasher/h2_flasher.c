/**
 * @file h2_flasher.c
 * @brief ESP32-H2 firmware flasher implementation using esp-serial-flasher
 *
 * Phase PROD-1.2: H2 OTA via S3
 */

#include "h2_flasher.h"
#include "app_config.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "esp_partition.h"
#include "driver/gpio.h"
#include "driver/uart.h"

#include "esp_loader.h"
#include "esp_loader_io.h"
#include "esp32_port.h"

static const char *TAG = "h2_flasher";

/*******************************************************************************
 * Event Base Definition
 ******************************************************************************/
ESP_EVENT_DEFINE_BASE(H2_FLASHER_EVENTS);

/*******************************************************************************
 * Constants
 ******************************************************************************/
#define H2_FW_PARTITION_LABEL   "h2_fw"
#define H2_FLASH_TIMEOUT_MS     60000
#define H2_BAUDRATE_FLASH       921600  /* Higher baud for faster flashing */
#define H2_BAUDRATE_NORMAL      115200
#define H2_RESET_DELAY_MS       100
#define H2_BOOT_HOLD_MS         50

/* H2 flash layout */
#define H2_BOOTLOADER_OFFSET    0x0
#define H2_PARTITION_OFFSET     0x8000
#define H2_APP_OFFSET           0x10000

/*******************************************************************************
 * Module State
 ******************************************************************************/

typedef struct {
    bool initialized;
    SemaphoreHandle_t mutex;

    bool flash_in_progress;
    bool abort_requested;
    uint8_t progress;

    uint32_t flashes_completed;
    uint32_t flashes_failed;
} h2_flasher_state_t;

static h2_flasher_state_t s_state = {0};

/*******************************************************************************
 * Forward Declarations
 ******************************************************************************/
static void enter_bootloader_mode(void);
static void exit_bootloader_mode(void);
static esp_err_t flash_firmware(const esp_partition_t *partition, size_t fw_size);
static void post_event(h2_flasher_event_type_t event, void *data, size_t data_size);

/*******************************************************************************
 * esp-serial-flasher Port Helper
 ******************************************************************************/

static esp_loader_error_t init_serial_flasher_port(uint32_t baud_rate, bool reinit)
{
    /* If reinitializing, deinit first */
    if (reinit) {
        loader_port_esp32_deinit();
    }

    loader_esp32_config_t config = {
        .baud_rate = baud_rate,
        .uart_port = H2_UART_NUM,
        .uart_rx_pin = PIN_H2_RX,
        .uart_tx_pin = PIN_H2_TX,
        .reset_trigger_pin = PIN_H2_EN,
        .gpio0_trigger_pin = PIN_H2_BOOT,
        .rx_buffer_size = 0,  /* Use default */
        .tx_buffer_size = 0,  /* Use default */
        .queue_size = 0,      /* Use default */
        .uart_queue = NULL,
        .dont_initialize_peripheral = false,
    };

    return loader_port_esp32_init(&config);
}

/*******************************************************************************
 * Initialization
 ******************************************************************************/

esp_err_t h2_flasher_init(void)
{
    if (s_state.initialized) {
        ESP_LOGW(TAG, "Already initialized");
        return ESP_OK;
    }

    ESP_LOGI(TAG, "Initializing H2 flasher");

    /* Create mutex */
    s_state.mutex = xSemaphoreCreateMutex();
    if (s_state.mutex == NULL) {
        ESP_LOGE(TAG, "Failed to create mutex");
        return ESP_ERR_NO_MEM;
    }

    /* Configure GPIO for H2 control */
    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << PIN_H2_EN) | (1ULL << PIN_H2_BOOT),
        .pull_down_en = 0,
        .pull_up_en = 0,
    };
    esp_err_t ret = gpio_config(&io_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to configure GPIO: %s", esp_err_to_name(ret));
        vSemaphoreDelete(s_state.mutex);
        return ret;
    }

    /* Set default states: H2 enabled, normal boot */
    gpio_set_level(PIN_H2_EN, 1);   /* Not in reset */
    gpio_set_level(PIN_H2_BOOT, 1); /* Normal boot mode */

    s_state.initialized = true;
    ESP_LOGI(TAG, "H2 flasher initialized");

    return ESP_OK;
}

esp_err_t h2_flasher_deinit(void)
{
    if (!s_state.initialized) {
        return ESP_OK;
    }

    if (s_state.flash_in_progress) {
        h2_flasher_abort();
        vTaskDelay(pdMS_TO_TICKS(1000));
    }

    if (s_state.mutex != NULL) {
        vSemaphoreDelete(s_state.mutex);
        s_state.mutex = NULL;
    }

    s_state.initialized = false;
    return ESP_OK;
}

/*******************************************************************************
 * Firmware Information
 ******************************************************************************/

bool h2_flasher_firmware_available(void)
{
    const esp_partition_t *partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, 0x40, H2_FW_PARTITION_LABEL);

    if (partition == NULL) {
        return false;
    }

    /* Check if partition has valid data (magic number check) */
    uint8_t magic[4];
    esp_err_t ret = esp_partition_read(partition, 0, magic, sizeof(magic));
    if (ret != ESP_OK) {
        return false;
    }

    /* ESP32 bootloader magic: E9 (app) or E7 (bootloader) */
    return (magic[0] == 0xE9 || magic[0] == 0xE7);
}

esp_err_t h2_flasher_get_firmware_size(size_t *size)
{
    if (size == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    if (!h2_flasher_firmware_available()) {
        return ESP_ERR_NOT_FOUND;
    }

    const esp_partition_t *partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, 0x40, H2_FW_PARTITION_LABEL);

    if (partition == NULL) {
        return ESP_ERR_NOT_FOUND;
    }

    /* Read app header to get actual size */
    /* For simplicity, use partition size as upper bound */
    *size = partition->size;

    return ESP_OK;
}

/*******************************************************************************
 * Flash Operation
 ******************************************************************************/

esp_err_t h2_flasher_flash(uint32_t timeout_ms)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    if (s_state.flash_in_progress) {
        ESP_LOGW(TAG, "Flash already in progress");
        return ESP_ERR_INVALID_STATE;
    }

    if (!h2_flasher_firmware_available()) {
        ESP_LOGE(TAG, "No H2 firmware available");
        return ESP_ERR_NOT_FOUND;
    }

    const esp_partition_t *partition = esp_partition_find_first(
        ESP_PARTITION_TYPE_DATA, 0x40, H2_FW_PARTITION_LABEL);

    if (partition == NULL) {
        return ESP_ERR_NOT_FOUND;
    }

    if (timeout_ms == 0) {
        timeout_ms = H2_FLASH_TIMEOUT_MS;
    }

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.flash_in_progress = true;
    s_state.abort_requested = false;
    s_state.progress = 0;
    xSemaphoreGive(s_state.mutex);

    ESP_LOGI(TAG, "Starting H2 flash operation");
    int64_t start_time = esp_timer_get_time();

    post_event(H2_FLASHER_EVENT_START, NULL, 0);

    /* Initialize esp-serial-flasher port with flashing baud rate */
    esp_loader_error_t port_err = init_serial_flasher_port(H2_BAUDRATE_FLASH, false);
    if (port_err != ESP_LOADER_SUCCESS) {
        ESP_LOGE(TAG, "Failed to init serial flasher port: %d", port_err);
        xSemaphoreTake(s_state.mutex, portMAX_DELAY);
        s_state.flash_in_progress = false;
        xSemaphoreGive(s_state.mutex);
        return ESP_FAIL;
    }

    /* Enter bootloader mode (uses library's port functions) */
    loader_port_enter_bootloader();

    /* Connect to bootloader */
    esp_loader_connect_args_t connect_args = ESP_LOADER_CONNECT_DEFAULT();
    esp_loader_error_t loader_err = esp_loader_connect(&connect_args);

    esp_err_t ret = ESP_OK;
    if (loader_err != ESP_LOADER_SUCCESS) {
        ESP_LOGE(TAG, "Failed to connect to H2 bootloader: %d", loader_err);
        ret = ESP_FAIL;
    } else {
        ESP_LOGI(TAG, "Connected to H2 bootloader");

        /* Get firmware size */
        size_t fw_size;
        if (h2_flasher_get_firmware_size(&fw_size) == ESP_OK) {
            ret = flash_firmware(partition, fw_size);
        } else {
            ret = ESP_FAIL;
        }
    }

    /* Reset target to normal operation (uses library's port functions) */
    loader_port_reset_target();

    /* Deinit serial flasher port */
    loader_port_esp32_deinit();

    int64_t elapsed_ms = (esp_timer_get_time() - start_time) / 1000;

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);
    s_state.flash_in_progress = false;
    xSemaphoreGive(s_state.mutex);

    h2_flasher_result_t result = {
        .error = ret,
        .flash_time_ms = (uint32_t)elapsed_ms,
    };

    if (ret == ESP_OK) {
        s_state.flashes_completed++;
        ESP_LOGI(TAG, "H2 flash completed successfully in %lu ms", (unsigned long)elapsed_ms);
        post_event(H2_FLASHER_EVENT_COMPLETE, &result, sizeof(result));
    } else {
        s_state.flashes_failed++;
        ESP_LOGE(TAG, "H2 flash failed: %s", esp_err_to_name(ret));
        post_event(H2_FLASHER_EVENT_FAILED, &result, sizeof(result));
    }

    return ret;
}

static esp_err_t flash_firmware(const esp_partition_t *partition, size_t fw_size)
{
    /* Read firmware header to determine actual size */
    uint8_t header[24];
    esp_err_t ret = esp_partition_read(partition, 0, header, sizeof(header));
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "Failed to read firmware header: %s", esp_err_to_name(ret));
        return ret;
    }

    /* For ESP32-H2, the binary typically starts at offset 0x10000 */
    /* We need to flash: bootloader, partition table, and app */

    /* Calculate actual firmware size from header if available */
    /* For now, use a reasonable maximum or detect end of valid data */
    size_t actual_size = fw_size;

    ESP_LOGI(TAG, "Flashing %zu bytes to H2", actual_size);

    /* Flash in chunks */
    const size_t CHUNK_SIZE = 4096;
    uint8_t *buffer = malloc(CHUNK_SIZE);
    if (buffer == NULL) {
        return ESP_ERR_NO_MEM;
    }

    size_t offset = 0;
    while (offset < actual_size) {
        if (s_state.abort_requested) {
            ESP_LOGW(TAG, "Flash aborted by user");
            free(buffer);
            return ESP_ERR_INVALID_STATE;
        }

        size_t chunk_size = (actual_size - offset) > CHUNK_SIZE ?
                           CHUNK_SIZE : (actual_size - offset);

        ret = esp_partition_read(partition, offset, buffer, chunk_size);
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to read firmware chunk: %s", esp_err_to_name(ret));
            free(buffer);
            return ret;
        }

        /* Check for end of valid firmware (all 0xFF = erased) */
        bool all_ff = true;
        for (size_t i = 0; i < chunk_size; i++) {
            if (buffer[i] != 0xFF) {
                all_ff = false;
                break;
            }
        }
        if (all_ff) {
            ESP_LOGI(TAG, "End of firmware data at offset %zu", offset);
            break;
        }

        /* Determine flash address based on offset */
        uint32_t flash_addr = H2_APP_OFFSET + offset;

        /* Start flash at this address */
        esp_loader_error_t loader_err = esp_loader_flash_start(
            flash_addr, chunk_size, CHUNK_SIZE);
        if (loader_err != ESP_LOADER_SUCCESS) {
            ESP_LOGE(TAG, "Failed to start flash at 0x%lx: %d",
                     (unsigned long)flash_addr, loader_err);
            free(buffer);
            return ESP_FAIL;
        }

        /* Write chunk */
        loader_err = esp_loader_flash_write(buffer, chunk_size);
        if (loader_err != ESP_LOADER_SUCCESS) {
            ESP_LOGE(TAG, "Failed to write flash chunk: %d", loader_err);
            free(buffer);
            return ESP_FAIL;
        }

        offset += chunk_size;

        /* Update progress */
        xSemaphoreTake(s_state.mutex, portMAX_DELAY);
        s_state.progress = (offset * 100) / actual_size;
        xSemaphoreGive(s_state.mutex);

        h2_flasher_progress_t progress = {
            .percentage = s_state.progress,
            .bytes_written = offset,
            .total_bytes = actual_size,
        };
        post_event(H2_FLASHER_EVENT_PROGRESS, &progress, sizeof(progress));
    }

    free(buffer);

    /* Finish flash */
    esp_loader_error_t loader_err = esp_loader_flash_finish(true);
    if (loader_err != ESP_LOADER_SUCCESS) {
        ESP_LOGE(TAG, "Failed to finish flash: %d", loader_err);
        return ESP_FAIL;
    }

    ESP_LOGI(TAG, "Flashed %zu bytes to H2", offset);
    return ESP_OK;
}

esp_err_t h2_flasher_abort(void)
{
    if (!s_state.flash_in_progress) {
        return ESP_ERR_INVALID_STATE;
    }

    ESP_LOGW(TAG, "Aborting flash operation");
    s_state.abort_requested = true;

    return ESP_OK;
}

/*******************************************************************************
 * Boot Mode Control
 ******************************************************************************/

static void enter_bootloader_mode(void)
{
    ESP_LOGI(TAG, "Entering H2 bootloader mode (manual GPIO)");

    /* Set H2_BOOT low for download mode */
    gpio_set_level(PIN_H2_BOOT, 0);
    vTaskDelay(pdMS_TO_TICKS(H2_BOOT_HOLD_MS));

    /* Reset H2 with BOOT held low */
    gpio_set_level(PIN_H2_EN, 0);
    vTaskDelay(pdMS_TO_TICKS(H2_RESET_DELAY_MS));
    gpio_set_level(PIN_H2_EN, 1);
    vTaskDelay(pdMS_TO_TICKS(H2_BOOT_HOLD_MS));

    /* Release BOOT */
    gpio_set_level(PIN_H2_BOOT, 1);
    vTaskDelay(pdMS_TO_TICKS(H2_RESET_DELAY_MS));
}

static void exit_bootloader_mode(void)
{
    ESP_LOGI(TAG, "Exiting H2 bootloader mode (manual GPIO)");

    /* Ensure BOOT pin is high for normal operation */
    gpio_set_level(PIN_H2_BOOT, 1);
    vTaskDelay(pdMS_TO_TICKS(H2_BOOT_HOLD_MS));

    /* Reset H2 */
    gpio_set_level(PIN_H2_EN, 0);
    vTaskDelay(pdMS_TO_TICKS(H2_RESET_DELAY_MS));
    gpio_set_level(PIN_H2_EN, 1);
    vTaskDelay(pdMS_TO_TICKS(H2_RESET_DELAY_MS));
}

esp_err_t h2_flasher_enter_bootloader(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    enter_bootloader_mode();
    return ESP_OK;
}

esp_err_t h2_flasher_reset_normal(void)
{
    if (!s_state.initialized) {
        return ESP_ERR_INVALID_STATE;
    }

    exit_bootloader_mode();
    return ESP_OK;
}

/*******************************************************************************
 * Status
 ******************************************************************************/

esp_err_t h2_flasher_get_status(h2_flasher_status_t *status)
{
    if (!s_state.initialized || status == NULL) {
        return ESP_ERR_INVALID_ARG;
    }

    xSemaphoreTake(s_state.mutex, portMAX_DELAY);

    status->initialized = s_state.initialized;
    status->flash_in_progress = s_state.flash_in_progress;
    status->progress = s_state.progress;
    status->flashes_completed = s_state.flashes_completed;
    status->flashes_failed = s_state.flashes_failed;

    xSemaphoreGive(s_state.mutex);

    return ESP_OK;
}

esp_err_t h2_flasher_verify(void)
{
    /* TODO: Implement verification by reading back from H2 */
    /* For now, rely on esp-serial-flasher's built-in verification */
    ESP_LOGW(TAG, "H2 verification not yet implemented");
    return ESP_OK;
}

/*******************************************************************************
 * Helper Functions
 ******************************************************************************/

static void post_event(h2_flasher_event_type_t event, void *data, size_t data_size)
{
    esp_event_post(H2_FLASHER_EVENTS, event, data, data_size, pdMS_TO_TICKS(100));
}
