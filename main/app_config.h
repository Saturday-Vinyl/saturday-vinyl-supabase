/**
 * @file app_config.h
 * @brief Compile-time configuration for Saturday Vinyl Hub firmware
 */

#ifndef APP_CONFIG_H
#define APP_CONFIG_H

/*******************************************************************************
 * Firmware Version
 ******************************************************************************/
#define FIRMWARE_VERSION_MAJOR  0
#define FIRMWARE_VERSION_MINOR  1
#define FIRMWARE_VERSION_PATCH  0
#define FIRMWARE_VERSION        "0.1.0"

/*******************************************************************************
 * Hardware Pin Definitions
 ******************************************************************************/

/* Debug UART (UART0) - directly connected via USB */
#define PIN_UART0_TX            0
#define PIN_UART0_RX            1

/* RFID Module UART (UART1) */
#define PIN_RFID_TX             4   /* ESP32 TX -> YRM100 RX */
#define PIN_RFID_RX             5   /* ESP32 RX <- YRM100 TX */
#define PIN_RFID_EN             6   /* RFID module enable (active high) */

/* RGB LED (active low, PWM capable) */
#define PIN_LED_R               8
#define PIN_LED_G               9
#define PIN_LED_B               10

/* Button (active low, internal pull-up) */
#define PIN_BUTTON              18

/*******************************************************************************
 * RFID Configuration Defaults
 ******************************************************************************/
#define DEFAULT_RFID_BAUD_RATE          115200
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            10
#define DEFAULT_DEBOUNCE_PRESENT_MS     1000
#define DEFAULT_DEBOUNCE_ABSENT_MS      2000

/*******************************************************************************
 * Network Configuration
 ******************************************************************************/
#define DEFAULT_THREAD_NETWORK_NAME     "SaturdayVinyl"
#define DEFAULT_THREAD_PAN_ID           0x5356
#define DEFAULT_THREAD_CHANNEL          15

/*******************************************************************************
 * Cloud Configuration
 ******************************************************************************/
#define HEARTBEAT_INTERVAL_SEC          300     /* 5 minutes */
#define EVENT_QUEUE_SIZE                100

/*******************************************************************************
 * Saturday Vinyl EPC Prefix
 ******************************************************************************/
#define SV_EPC_PREFIX_BYTE0             0x53    /* 'S' */
#define SV_EPC_PREFIX_BYTE1             0x56    /* 'V' */
#define SV_EPC_LENGTH                   12      /* 96 bits = 12 bytes */

#endif /* APP_CONFIG_H */
