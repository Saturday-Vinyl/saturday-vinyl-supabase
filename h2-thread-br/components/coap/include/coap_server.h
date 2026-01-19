/**
 * @file coap_server.h
 * @brief CoAP Server for Thread Device Communication
 *
 * Implements a CoAP server on the Thread interface to receive messages
 * from RFID crates. Uses OpenThread's built-in CoAP implementation.
 *
 * Endpoints:
 * - POST /inventory - Crate reports current record inventory
 * - POST /heartbeat - Crate periodic health check
 * - GET  /config    - Crate requests configuration
 *
 * Phase H2-2: CoAP Server
 */

#ifndef COAP_SERVER_H
#define COAP_SERVER_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "esp_event.h"

#ifdef __cplusplus
extern "C" {
#endif

/*******************************************************************************
 * Constants
 ******************************************************************************/

/** Maximum EPCs per inventory update */
#define COAP_MAX_EPCS_PER_UPDATE    75

/** EPC length in bytes */
#define COAP_EPC_LENGTH             12

/** CoAP port */
#define COAP_DEFAULT_PORT           5683

/*******************************************************************************
 * Event Definitions
 ******************************************************************************/

/**
 * @brief CoAP Server event base
 */
ESP_EVENT_DECLARE_BASE(COAP_SERVER_EVENTS);

/**
 * @brief CoAP Server events
 */
typedef enum {
    COAP_SERVER_EVENT_INVENTORY_UPDATE,     /**< Inventory update received */
    COAP_SERVER_EVENT_HEARTBEAT,            /**< Heartbeat received */
    COAP_SERVER_EVENT_ERROR,                /**< Error occurred */
} coap_server_event_t;

/**
 * @brief Inventory update event data
 */
typedef struct {
    uint8_t crate_ext_addr[8];              /**< Crate extended MAC address */
    uint16_t crate_rloc16;                  /**< Crate RLOC16 */
    uint8_t epc_count;                      /**< Number of EPCs */
    uint8_t epcs[COAP_MAX_EPCS_PER_UPDATE][COAP_EPC_LENGTH];  /**< EPC data */
} coap_inventory_event_t;

/**
 * @brief Heartbeat event data
 */
typedef struct {
    uint8_t crate_ext_addr[8];              /**< Crate extended MAC address */
    uint16_t crate_rloc16;                  /**< Crate RLOC16 */
    uint8_t battery_percent;                /**< Battery level (0-100) */
    int8_t rssi;                            /**< Signal strength (dBm) */
    uint8_t tag_count;                      /**< Number of tags in crate */
} coap_heartbeat_event_t;

/*******************************************************************************
 * Initialization
 ******************************************************************************/

/**
 * @brief Initialize the CoAP server
 *
 * Sets up CoAP resources on the Thread interface. Must be called after
 * Thread BR is initialized but can be called before Thread is started.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t coap_server_init(void);

/**
 * @brief Start the CoAP server
 *
 * Begins listening for CoAP requests. Thread must be attached.
 *
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t coap_server_start(void);

/**
 * @brief Stop the CoAP server
 *
 * Stops listening for requests but keeps resources registered.
 *
 * @return ESP_OK on success
 */
esp_err_t coap_server_stop(void);

/**
 * @brief Deinitialize the CoAP server
 *
 * Releases all resources.
 *
 * @return ESP_OK on success
 */
esp_err_t coap_server_deinit(void);

/**
 * @brief Check if CoAP server is running
 *
 * @return true if running and accepting requests
 */
bool coap_server_is_running(void);

/*******************************************************************************
 * Statistics
 ******************************************************************************/

/**
 * @brief CoAP server statistics
 */
typedef struct {
    uint32_t inventory_requests;            /**< Total inventory POSTs received */
    uint32_t heartbeat_requests;            /**< Total heartbeat POSTs received */
    uint32_t config_requests;               /**< Total config GETs received */
    uint32_t errors;                        /**< Total errors */
} coap_server_stats_t;

/**
 * @brief Get CoAP server statistics
 *
 * @param stats Pointer to stats structure to fill
 * @return ESP_OK on success
 */
esp_err_t coap_server_get_stats(coap_server_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif /* COAP_SERVER_H */
