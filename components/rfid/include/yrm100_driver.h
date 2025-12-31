/**
 * @file yrm100_driver.h
 * @brief YRM100 UHF RFID module driver interface
 *
 * Provides low-level communication with the YRM100 RFID module
 * for tag detection and configuration.
 */

#ifndef YRM100_DRIVER_H
#define YRM100_DRIVER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize the YRM100 RFID module
 *
 * Configures UART and enables the module.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_init(void);

/**
 * @brief Enable or disable the RFID module
 *
 * @param enable true to enable, false to disable
 */
void yrm100_enable(bool enable);

/**
 * @brief Get module firmware version
 *
 * @param version Buffer to store version string
 * @param max_len Maximum buffer length
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_get_firmware_version(char *version, size_t max_len);

/**
 * @brief Set RF output power
 *
 * @param power_dbm Power level in dBm (0-30)
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_set_rf_power(uint8_t power_dbm);

/**
 * @brief Get current RF output power
 *
 * @param power_dbm Pointer to store power level
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_get_rf_power(uint8_t *power_dbm);

/**
 * @brief Start continuous tag polling
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_start_polling(void);

/**
 * @brief Stop continuous tag polling
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t yrm100_stop_polling(void);

/**
 * @brief Perform single tag poll
 *
 * @return ESP_OK if tag found, ESP_ERR_NOT_FOUND if no tag
 */
esp_err_t yrm100_single_poll(void);

#ifdef __cplusplus
}
#endif

#endif /* YRM100_DRIVER_H */
