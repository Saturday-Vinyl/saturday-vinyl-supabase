/**
 * @file app_config.h
 * @brief Compile-time configuration for Saturday Vinyl Hub ESP32-H2 Thread BR
 *
 * This is the dedicated Thread co-processor handling:
 * - Thread Border Router functionality
 * - CoAP server for crate communication
 * - UART communication with S3 master
 */

#ifndef APP_CONFIG_H
#define APP_CONFIG_H

/*******************************************************************************
 * Firmware Version
 ******************************************************************************/
#define FW_VERSION_MAJOR    0
#define FW_VERSION_MINOR    5
#define FW_VERSION_PATCH    2
#define FW_VERSION_STRING   "0.5.2"

/*******************************************************************************
 * Hardware Pin Definitions - ESP32-H2
 ******************************************************************************/

/* UART0: S3 Communication */
#define PIN_S3_RX               23  /* H2 RX <- S3 TX */
#define PIN_S3_TX               24  /* H2 TX -> S3 RX */
#define S3_UART_NUM             UART_NUM_0
#define S3_UART_BAUD            115200

/* Boot Mode Selection (directly controlled by S3) */
#define PIN_BOOT_MODE           4   /* Boot mode select (controlled by S3) */

/*******************************************************************************
 * Thread Network Configuration Defaults
 ******************************************************************************/
#define DEFAULT_THREAD_NETWORK_NAME     "SaturdayVinyl"
#define DEFAULT_THREAD_PAN_ID           0x5356
#define DEFAULT_THREAD_CHANNEL          15

/*******************************************************************************
 * CoAP Server Configuration
 ******************************************************************************/
#define COAP_SERVER_PORT                5683

/*******************************************************************************
 * S3 Communication Timeouts
 ******************************************************************************/
#define S3_COMMAND_TIMEOUT_MS           500     /* Max wait for command processing */
#define S3_HEARTBEAT_INTERVAL_MS        5000    /* Heartbeat to S3 if idle */

#endif /* APP_CONFIG_H */
