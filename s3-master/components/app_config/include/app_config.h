/**
 * @file app_config.h
 * @brief Compile-time configuration for Saturday Vinyl Hub ESP32-S3 Master
 *
 * This is the master MCU firmware handling:
 * - WiFi connectivity and Supabase cloud sync
 * - BLE provisioning
 * - RFID reader interface (YRM100 via UART1)
 * - H2 Thread co-processor management (via UART2)
 * - USB Service Mode interface
 * - LED and button UI
 */

#ifndef APP_CONFIG_H
#define APP_CONFIG_H

/*******************************************************************************
 * Firmware Identity (from firmware JSON schema)
 * These values must match the firmware JSON schema exported from admin app
 ******************************************************************************/
#define FW_VERSION_MAJOR    0
#define FW_VERSION_MINOR    5
#define FW_VERSION_PATCH    1
#define FW_VERSION_STRING   "0.5.1"          /* From firmware JSON schema */
#define DEVICE_TYPE         "hub-prototype"  /* From firmware JSON schema */

/*******************************************************************************
 * Hardware Pin Definitions - ESP32-S3
 ******************************************************************************/

/* Button (active low, internal pull-up) */
#define PIN_BUTTON              0   /* GPIO0 - BOOT button */

/* RFID Module Enable */
#define PIN_RFID_EN             5   /* RFID module enable (active high) */

/* H2 Co-processor Control */
#define PIN_H2_EN               6   /* H2 enable/reset (active low) */
#define PIN_H2_BOOT             7   /* H2 boot mode select */

/* UART2: H2 Communication */
#define PIN_H2_TX               15  /* S3 TX -> H2 RX */
#define PIN_H2_RX               16  /* S3 RX <- H2 TX */
#define H2_UART_NUM             UART_NUM_2
#define H2_UART_BAUD            115200

/* UART1: RFID Module (YRM100) */
#define PIN_RFID_TX             17  /* S3 TX -> YRM100 RX */
#define PIN_RFID_RX             18  /* S3 RX <- YRM100 TX */
#define RFID_UART_NUM           UART_NUM_1
#define RFID_UART_BAUD          115200

/* External WS2812B LED Strip
 * Note: GPIO38 was the onboard LED on DevKit v1.1; now using external strip on GPIO10. */
#define PIN_LED_STRIP           10  /* External WS2812B LED strip data pin */
#define LED_STRIP_LENGTH        26  /* Number of LEDs on external strip */

/*******************************************************************************
 * RFID Configuration Defaults
 ******************************************************************************/
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            5       /* Lower = shorter range (0-30 dBm) */
#define DEFAULT_DEBOUNCE_PRESENT_MS     1000
#define DEFAULT_DEBOUNCE_ABSENT_MS      2000

/*******************************************************************************
 * Cloud Configuration
 ******************************************************************************/
#define HEARTBEAT_INTERVAL_SEC          30      /* 30 seconds for testing */
#define EVENT_QUEUE_SIZE                100

/*******************************************************************************
 * H2 Communication Timeouts
 ******************************************************************************/
#define H2_RESPONSE_TIMEOUT_MS          1000    /* Max wait for H2 response */
#define H2_BOOT_DELAY_MS                500     /* Delay after H2 reset */
#define H2_FLASH_TIMEOUT_MS             30000   /* Max time for H2 firmware flash */

/*******************************************************************************
 * Service Mode Configuration
 ******************************************************************************/
#define SERVICE_MODE_BAUD               115200
#define SERVICE_MODE_TIMEOUT_SEC        10      /* Entry window after boot */
#define SERVICE_BEACON_INTERVAL_MS      2000    /* Status beacon interval */

/*******************************************************************************
 * Saturday Vinyl EPC Prefix
 ******************************************************************************/
#define SV_EPC_PREFIX_BYTE0             0x53    /* 'S' */
#define SV_EPC_PREFIX_BYTE1             0x56    /* 'V' */
#define SV_EPC_LENGTH                   12      /* 96 bits = 12 bytes */

#endif /* APP_CONFIG_H */
