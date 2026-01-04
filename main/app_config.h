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
#define PIN_RFID_TX             5   /* ESP32 TX -> YRM100 RX (GPIO5 = LP_UART_TXD) */
#define PIN_RFID_RX             4   /* ESP32 RX <- YRM100 TX (GPIO4 = LP_UART_RXD) */
#define PIN_RFID_EN             6   /* RFID module enable (active high) */

/* RGB LED (WS2812 addressable LED on DevKitC-1) */
#define PIN_LED_WS2812          8   /* Onboard addressable RGB LED */

/* Button (active low, internal pull-up) */
#define PIN_BUTTON              18

/*******************************************************************************
 * RFID Configuration Defaults
 ******************************************************************************/
#define DEFAULT_RFID_BAUD_RATE          115200
#define DEFAULT_POLL_INTERVAL_MS        500
#define DEFAULT_RF_POWER_DBM            5       /* Lower = shorter range (0-30 dBm) */
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
 * Test Credentials (Phase 5 Testing)
 *
 * These are used for development/testing only. In production, credentials
 * will be provisioned via BLE or Serial (Phase 6+).
 *
 * To enable: set USE_TEST_CREDENTIALS to 1 and fill in your values.
 ******************************************************************************/
#define USE_TEST_CREDENTIALS            1       /* Set to 1 to enable */

#if USE_TEST_CREDENTIALS
/* Wi-Fi Configuration */
#define TEST_WIFI_SSID                  "Margarita IoT"
#define TEST_WIFI_PASSWORD              "Omen371!"

/* Supabase Configuration */
#define TEST_SUPABASE_URL               "https://ddhcmhbwppiqrqmefynv.supabase.co"
#define TEST_SUPABASE_ANON_KEY          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRkaGNtaGJ3cHBpcXJxbWVmeW52Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk5NTAwOTEsImV4cCI6MjA3NTUyNjA5MX0.NbS1ftfFlGOTtZZ76HIwgW5NZieZN9oOlMAOuAoLdD4"
#define TEST_HUB_ID                     "SV-HUB-000001"
#endif

/*******************************************************************************
 * Saturday Vinyl EPC Prefix
 ******************************************************************************/
#define SV_EPC_PREFIX_BYTE0             0x53    /* 'S' */
#define SV_EPC_PREFIX_BYTE1             0x56    /* 'V' */
#define SV_EPC_LENGTH                   12      /* 96 bits = 12 bytes */

#endif /* APP_CONFIG_H */
