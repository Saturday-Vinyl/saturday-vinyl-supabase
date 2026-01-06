# Saturday Vinyl Hub Firmware - Implementation Plan

**Project:** sv-hub-firmware
**Document Version:** 0.2.0
**Last Updated:** 2026-01-03

---

## Overview

This document breaks down the hub firmware development into iterative phases. Each phase builds on the previous one and produces testable functionality as early as possible.

### Guiding Principles

1. **Test early, test often** - Get code running on hardware from day one
2. **Vertical slices** - Each phase delivers end-to-end functionality
3. **Incremental complexity** - Start simple, add features progressively
4. **Hardware first** - Validate hardware interfaces before building abstractions

### Phase Summary

| Phase | Name | Outcome |
|-------|------|---------|
| 0 | Project Setup | Build system works, LED blinks on device |
| 1 | Hardware Bring-Up | All peripherals functional (LED, button, RFID, UART) |
| 2 | RFID Detection | Tags detected and logged to console |
| 3 | Now Playing Logic | Debounced detection with state machine |
| 4 | Wi-Fi Connectivity | Connect to network, basic HTTP request |
| 5 | Supabase Integration | Now Playing events sent to cloud |
| 6 | Serial Provisioning | Factory provisioning via desktop app |
| 7 | BLE Provisioning | Consumer provisioning via mobile app |
| 8 | Thread Border Router | Thread network operational |
| 9 | CoAP Server | Receive messages from mock crate |
| 10 | Crate Integration | Full crate → hub → cloud pipeline |
| 11 | OTA Updates | Firmware updates from cloud |
| 12 | Hardening | Error handling, watchdogs, edge cases |
| 13 | Production Ready | Final testing, documentation, release |

---

## Phase 0: Project Setup

**Goal:** Establish the development environment and verify basic firmware runs on hardware.

### Tasks

#### 0.1 Development Environment Setup
- [x] Install ESP-IDF v5.2+ following official documentation
- [x] Verify toolchain with `idf.py --version`
- [x] Install VS Code with ESP-IDF extension (optional but recommended)
- [x] Set up git repository with `.gitignore` for ESP-IDF projects

#### 0.2 Create Project Structure
- [x] Initialize project with `idf.py create-project sv-hub-firmware`
- [x] Set target to ESP32-C6: `idf.py set-target esp32c6`
- [x] Create directory structure:
  ```
  sv-hub-firmware/
  ├── CMakeLists.txt
  ├── sdkconfig.defaults
  ├── main/
  │   ├── CMakeLists.txt
  │   ├── main.c
  │   └── Kconfig.projbuild
  ├── components/
  └── docs/
  ```
- [x] Configure partition table for OTA support (`partitions.csv`)
- [x] Create `sdkconfig.defaults` with baseline configuration

#### 0.3 Hello World Build
- [x] Write minimal `main.c` that logs "Saturday Hub starting..."
- [ ] Build: `idf.py build`
- [ ] Flash to device: `idf.py -p <PORT> flash`
- [ ] Verify output: `idf.py -p <PORT> monitor`

#### 0.4 LED Blink Test
- [x] Configure GPIO for one LED channel (e.g., GPIO8 for red)
- [x] Implement simple blink loop (500ms on/off)
- [ ] Verify LED toggles on physical hardware

### Deliverables
- Working build system
- Firmware that boots and blinks LED
- Serial console output visible

### Testing
- Visual: LED blinks at expected rate
- Console: Boot messages appear in monitor

---

## Phase 1: Hardware Bring-Up

**Goal:** Validate all hardware peripherals work independently.

**Status:** Complete

### Tasks

#### 1.1 RGB LED Driver
- [x] Create `components/ui/led_manager.c`
- [x] Configure WS2812 addressable LED on GPIO8 (DevKitC-1 onboard LED)
- [x] Implement basic functions:
  ```c
  void led_init(void);
  void led_set_color(uint8_t r, uint8_t g, uint8_t b);
  void led_set_brightness(uint8_t brightness);
  ```
- [x] Test: Cycle through colors (red → green → blue → white)

**Implementation Notes:**
- Uses ESP-IDF led_strip component (espressif/led_strip managed component)
- WS2812 protocol via RMT peripheral at 10MHz resolution
- Pattern support: SOLID, BLINK_SLOW, BLINK_FAST, PULSE, FLASH
- Background FreeRTOS task handles pattern generation
- Thread-safe with mutex protection
- GPIO8 is the onboard WS2812 on ESP32-C6-DevKitC-1

#### 1.2 Button Input
- [x] Create `components/ui/button_handler.c`
- [x] Configure GPIO18 as input with internal pull-up
- [x] Implement debounced button reading (50ms debounce)
- [x] Implement press duration detection:
  ```c
  typedef enum {
      BUTTON_PRESS_SHORT,    // < 500ms
      BUTTON_PRESS_LONG,     // 3-5 seconds
      BUTTON_PRESS_FACTORY,  // > 10 seconds
  } button_press_t;
  ```
- [x] Test: Press button, log detected press type, change LED color

**Implementation Notes:**
- GPIO interrupt-driven (ANYEDGE) with event queue to task
- Duration thresholds logged when crossed (for user feedback)
- Callback registration for application handling

#### 1.3 UART for RFID Module
- [x] Configure UART1 at 115200 baud:
  - GPIO5 = ESP32 TX → YRM100 RXD (Yellow wire)
  - GPIO4 = ESP32 RX ← YRM100 TXD (Green wire)
- [x] Configure GPIO6 as RFID enable pin (active HIGH, with pull-up)
- [x] Implement basic send/receive functions:
  ```c
  void rfid_uart_init(void);
  void rfid_enable(bool enable);
  int rfid_send(const uint8_t *data, size_t len);
  int rfid_receive(uint8_t *buf, size_t max_len, uint32_t timeout_ms);
  ```
- [x] Test: Send `GetRfPower` command, verify response received

**Implementation Notes:**
- Full frame protocol implemented (build, parse, checksum)
- Commands: GetFirmwareVersion (with 0x00 param), Get/SetRfPower, Single/MultiplePoll
- Raw send/receive functions available for debugging
- Thread-safe UART access with mutex
- EN pin requires GPIO_MODE_INPUT_OUTPUT with pull-up for reliable operation
- 500ms delay after enabling module before sending commands

**YRM100 Wiring Reference:**

Two YRM100 module variants are supported with different wire colors:

*YRM100 (SBComponents) - 3 dBi Antenna:*
| YRM100 Pin | Wire Color | ESP32 GPIO |
|------------|------------|------------|
| 1 (GND) | Black | GND |
| 2 (EN) | Green | GPIO6 |
| 3 (RXD) | Orange | GPIO5 |
| 4 (TXD) | Yellow | GPIO4 |
| 5 (VCC) | Red | 5V (USB rail) |

*YRM100 (Generic/AliExpress) - 2 dBi Antenna:*
| YRM100 Pin | Wire Color | ESP32 GPIO |
|------------|------------|------------|
| 1 (GND) | Blue | GND |
| 2 (EN) | Green | GPIO6 |
| 3 (RXD) | Yellow | GPIO5 |
| 4 (TXD) | Black | GPIO4 |
| 5 (VCC) | Red | 5V (USB rail) |

> **Note:** Both modules require 5V power and have a minimum RF power of 15 dBm.

#### 1.4 USB Serial Console
- [x] Verify UART0 works for debug output (should work by default)
- [x] Test printf/ESP_LOG output at various log levels

### Deliverables
- LED shows any color via function call
- Button presses detected with duration classification
- RFID UART communication working (raw bytes)
- Debug console functional

### Testing
- LED: Visual inspection of color accuracy
- Button: Console logs press types correctly
- RFID: Hex dump shows valid response frames (starts with 0xBB)

---

## Phase 2: RFID Detection

**Goal:** Detect RFID tags and extract EPC data.

**Status:** Complete

### Tasks

#### 2.1 YRM100 Frame Codec
- [x] Create `components/rfid/rfid_protocol.c`
- [x] Implement frame builder:
  ```c
  size_t rfid_build_frame(uint8_t cmd, const uint8_t *params,
                          size_t param_len, uint8_t *out_buf);
  ```
- [x] Implement frame parser:
  ```c
  typedef struct {
      uint8_t type;      // 0x00=cmd, 0x01=response, 0x02=notice
      uint8_t command;
      uint8_t *params;
      uint16_t param_len;
  } rfid_frame_t;

  bool rfid_parse_frame(const uint8_t *buf, size_t len, rfid_frame_t *frame);
  ```
- [x] Implement checksum calculation and validation
- [x] Test: Build and parse known frames from documentation

**Implementation Notes:**
- Header file: `components/rfid/include/rfid_protocol.h`
- Frame finding function `rfid_find_frame()` for extracting frames from streams
- Utility functions: `rfid_epc_to_hex_string()`, `rfid_rssi_to_dbm()`

#### 2.2 YRM100 Driver
- [x] Create `components/rfid/yrm100_driver.c`
- [x] Implement command functions:
  ```c
  bool yrm100_init(void);
  bool yrm100_get_firmware_version(char *version, size_t max_len);
  bool yrm100_set_rf_power(uint8_t power_dbm);
  bool yrm100_get_rf_power(uint8_t *power_dbm);
  bool yrm100_start_polling(void);
  bool yrm100_stop_polling(void);
  ```
- [x] Implement response handling with timeout
- [x] Test: Get firmware version, set/get RF power

**Implementation Notes:**
- Added `yrm100_single_poll_with_data()` for full tag data extraction
- Added `yrm100_read_tag_notice()` for continuous polling mode
- Thread-safe with mutex protection on UART access

#### 2.3 Tag Polling
- [x] Implement tag notice frame parsing:
  ```c
  typedef struct {
      uint8_t rssi;
      uint16_t pc;
      uint8_t epc[12];
      uint8_t epc_len;
  } rfid_tag_t;

  bool rfid_parse_tag_notice(const rfid_frame_t *frame, rfid_tag_t *tag);
  ```
- [x] Extract EPC length from PC word (bits 15-11)
- [x] Implement Saturday tag validation (prefix check)
- [x] Test: Place tag near antenna, verify EPC logged correctly

**Implementation Notes:**
- `rfid_tag_t` structure includes `is_saturday_tag` boolean
- Saturday prefix: 0x5356 ("SV" in ASCII)
- EPC length extracted from PC word bits 15-11 (word count * 2)

#### 2.4 Continuous Polling Task
- [x] Create FreeRTOS task for RFID polling
- [x] Read incoming frames in a loop
- [x] Parse tag notices and log detected tags
- [x] Test: Multiple tags, tags entering/leaving field

**Implementation Notes:**
- Background task: `yrm100_start_polling_task()` / `yrm100_stop_polling_task()`
- Callback-based: `yrm100_register_tag_callback()`
- Configurable: poll interval, RF power, Saturday-only filter
- Statistics: `yrm100_get_poll_stats()` for monitoring
- Uses single polls with intervals (cleaner than continuous mode)

### Deliverables
- YRM100 commands work reliably
- Tags detected with EPC and RSSI
- Saturday vs non-Saturday tags distinguished
- Continuous polling runs in background

### Testing
- Place known test tag, verify logged EPC matches
- Remove tag, verify no more detections
- Test with non-Saturday tag, verify it's flagged differently

---

## Phase 3: Now Playing Logic

**Goal:** Implement debounced "Now Playing" detection with state machine.

**Status:** Complete

### Tasks

#### 3.1 Configuration Storage (Basic)
- [x] Create `components/config/config_store.c`
- [x] Initialize NVS:
  ```c
  esp_err_t config_init(void);
  ```
- [x] Implement RFID config read/write:
  ```c
  typedef struct {
      uint16_t poll_interval_ms;
      uint8_t rf_power_dbm;
      uint16_t debounce_present_ms;
      uint16_t debounce_absent_ms;
  } rfid_config_t;

  esp_err_t config_get_rfid(rfid_config_t *config);
  esp_err_t config_set_rfid(const rfid_config_t *config);
  ```
- [x] Use sensible defaults if not configured
- [ ] Test: Set config, reboot, verify config persists

**Implementation Notes:**
- NVS namespace: `sv_rfid`
- Keys: `poll_int`, `rf_power`, `deb_pres`, `deb_abs`
- Validation on set: poll_interval 100-5000ms, rf_power 0-30dBm, debounce 0-5000/10000ms
- Graceful fallback to defaults if NVS not found

#### 3.2 Now Playing State Machine
- [x] Create `components/rfid/now_playing.c`
- [x] Implement state machine:
  ```c
  typedef enum {
      NOW_PLAYING_STATE_IDLE,
      NOW_PLAYING_STATE_TAG_CONFIRMING,
      NOW_PLAYING_STATE_TAG_PRESENT,
      NOW_PLAYING_STATE_TAG_REMOVING,
  } now_playing_state_t;
  ```
- [x] Track current tag EPC and timestamps
- [x] Implement state transitions with debounce timers
- [ ] Test: Place tag, observe state transitions in logs

**Implementation Notes:**
- Mutex-protected state for thread safety
- Separate pending/current tag tracking
- Time-based debouncing using esp_timer_get_time()
- Statistics tracking (total placed/removed events)

#### 3.3 Event Generation
- [x] Define events:
  ```c
  typedef enum {
      NOW_PLAYING_EVENT_TAG_PLACED,
      NOW_PLAYING_EVENT_TAG_REMOVED,
  } now_playing_event_type_t;

  typedef struct {
      now_playing_event_type_t type;
      uint8_t epc[12];
      int8_t rssi;
      int64_t timestamp;
      uint32_t duration_ms;  // For removal events
  } now_playing_event_t;
  ```
- [x] Integrate with ESP-IDF event loop
- [ ] Test: Subscribe to events, log when received

**Implementation Notes:**
- Event base: `NOW_PLAYING_EVENTS` (ESP_EVENT_DEFINE_BASE)
- Events posted to default event loop
- Duration calculated automatically for removal events

#### 3.4 LED Feedback
- [x] Flash LED green briefly when tag confirmed
- [x] Show dim green (brightness 64) when tag present
- [x] Return to very dim green (brightness 16) when tag removed
- [x] Flash cyan briefly on tag removal
- [ ] Test: Visual confirmation of state changes

**Implementation Notes:**
- Event handler registered in main.c
- LED brightness: 16 (idle), 64 (now playing)
- Flash duration: 300ms placed, 200ms removed

### Deliverables
- Debounced tag detection (no false triggers)
- Events generated for place/remove
- LED indicates current state
- Configurable timing parameters

### Testing
- Quickly wave tag past antenna - should NOT trigger event
- Place tag and hold - should trigger "placed" after debounce
- Remove tag - should trigger "removed" after debounce
- Adjust debounce config, verify behavior changes

---

## Phase 4: Wi-Fi Connectivity

**Goal:** Connect to Wi-Fi network and make basic HTTP requests.

**Status:** Complete

### Tasks

#### 4.1 Wi-Fi Manager
- [x] Create `components/network/wifi_manager.c`
- [x] Implement Wi-Fi station mode initialization
- [x] Implement connection with stored credentials:
  ```c
  esp_err_t wifi_init(void);
  esp_err_t wifi_connect(const char *ssid, const char *password);
  esp_err_t wifi_disconnect(void);
  bool wifi_is_connected(void);
  ```
- [x] Handle Wi-Fi events (connected, disconnected, got IP)
- [ ] Test: Hardcode credentials, verify connection

**Implementation Notes:**
- Event-based architecture using ESP-IDF event loop
- Posts WIFI_MANAGER_EVENTS for application integration
- Tracks connection statistics (attempts, disconnects, RSSI)
- Thread-safe state management

#### 4.2 Wi-Fi Credential Storage
- [x] Add to config store:
  ```c
  esp_err_t config_get_wifi(char *ssid, size_t ssid_len,
                            char *password, size_t pass_len);
  esp_err_t config_set_wifi(const char *ssid, const char *password);
  bool config_has_wifi(void);
  ```
- [x] Added config_clear_wifi() for credential removal
- [ ] Encrypt password in NVS (optional, can use NVS encryption)
- [ ] Test: Store credentials, reboot, auto-connect

**Implementation Notes:**
- NVS namespace: `sv_wifi`
- Keys: `ssid`, `password`
- Validation: SSID max 32 chars, password max 64 chars
- Empty password supported for open networks

#### 4.3 Connection State Machine
- [x] Implement auto-reconnect on disconnect
- [x] Exponential backoff for retry (1s, 2s, 4s, ... max 60s)
- [x] Update LED state based on connection status
- [ ] Test: Disconnect router, verify reconnect behavior

**Implementation Notes:**
- States: DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING
- Auto-reconnect enabled by default, uses esp_timer for backoff
- LED feedback: Yellow pulse (connecting), Cyan flash (connected),
  Orange blink (reconnecting), Red blink (failed)

#### 4.4 Basic HTTP Client
- [x] Create `components/network/http_client.c`
- [x] Implement http_get() and http_post_json() functions
- [x] Configure TLS certificates using ESP certificate bundle
- [x] Implement http_test_connectivity() using Cloudflare endpoint
- [ ] Test: Verify response received and parsed

**Implementation Notes:**
- Uses esp_http_client with esp_crt_bundle for HTTPS
- Response buffering up to 4KB
- Request timing measurement included
- Connectivity test uses https://1.1.1.1/cdn-cgi/trace

### Deliverables
- Wi-Fi connects automatically on boot (if configured)
- Reconnects automatically on disconnect
- LED indicates connection state
- HTTPS requests work

### Testing
- Boot with valid credentials - should connect
- Boot with invalid credentials - should show error state
- Disconnect router - should attempt reconnect
- Make HTTPS request - should succeed

---

## Phase 5: Supabase Integration

**Goal:** Send Now Playing events to Supabase.

**Status:** Complete

### Tasks

#### 5.1 Supabase Client
- [x] Create `components/cloud/supabase_client.c`
- [x] Store Supabase config:
  ```c
  typedef struct {
      char url[128];
      char anon_key[256];
      char device_secret[64];
  } supabase_config_t;
  ```
- [x] Implement authenticated POST request:
  ```c
  esp_err_t supabase_post(const char *table, const char *json_body);
  ```
- [x] Handle HTTP response codes (200, 401, 500, etc.)
- [x] Test: POST to test table, verify row created in Supabase dashboard

**Implementation Notes:**
- NVS namespace: `sv_supabase`
- Keys: `url`, `anon_key`, `dev_secret`, `hub_id`
- Uses esp_http_client with esp_crt_bundle for HTTPS
- Response buffering up to 4KB
- Automatic headers: apikey, Authorization (Bearer), Content-Type

#### 5.2 Event Reporter
- [x] Create `components/cloud/event_reporter.c`
- [x] Subscribe to Now Playing events
- [x] Format events as JSON:
  ```json
  {
    "hub_id": "HUB-TEST",
    "epc": "5356...",
    "event_type": "placed",
    "rssi": -45,
    "timestamp": "2025-01-15T10:30:00Z"
  }
  ```
- [x] Send to Supabase when event occurs
- [x] Test: Place tag, verify event appears in Supabase

**Implementation Notes:**
- Background FreeRTOS task for cloud sync (8KB stack)
- Automatic Wi-Fi state tracking
- Posts to `now_playing_events` table
- Includes duration_ms for removal events

#### 5.3 Event Queue (Offline Support)
- [x] Implement in-memory event queue (ring buffer)
- [x] Queue events when Wi-Fi disconnected
- [x] Flush queue when Wi-Fi reconnects
- [x] Drop oldest events if queue full (log warning)
- [x] Test: Disconnect Wi-Fi, generate events, reconnect, verify all sent

**Implementation Notes:**
- Ring buffer with configurable size (default: 100 events)
- Thread-safe with mutex protection
- Posts EVENT_REPORTER_EVENTS for sync status
- Automatic flush on Wi-Fi reconnect

#### 5.4 Hub Heartbeat
- [x] Implement periodic heartbeat (every 5 minutes)
- [x] Include device health metrics:
  ```json
  {
    "hub_id": "HUB-TEST",
    "firmware_version": "0.5.0",
    "wifi_rssi": -55,
    "uptime_sec": 3600,
    "free_heap": 128000
  }
  ```
- [x] Test: Verify heartbeats appear in Supabase

**Implementation Notes:**
- Uses esp_timer for periodic callbacks
- Posts to `hub_heartbeats` table
- Includes events_queued count for monitoring
- Configurable interval (default: 300 seconds)

### Deliverables
- Now Playing events in Supabase within seconds
- Events queued during Wi-Fi outage
- Hub heartbeats for monitoring
- Proper error handling for API failures

### Testing
- Place/remove tags, verify events in Supabase
- Check timestamps are accurate
- Simulate Wi-Fi outage, verify events queued and sent on reconnect
- Verify heartbeats arrive at expected interval

---

## Phase 6: Serial Provisioning

**Goal:** Enable factory provisioning via USB serial with Saturday Admin app.

**Status:** Complete

### Tasks

#### 6.1 Serial Protocol
- [x] Create `components/provisioning/serial_prov.c`
- [x] Define JSON protocol:
  ```
  Hub → Host: {"status": "awaiting_provisioning", "version": "0.6.0"}
  Host → Hub: {"cmd": "provision", "data": {...}}
  Hub → Host: {"status": "success", "hub_id": "HUB-XXXX"}
  ```
- [x] Implement JSON parsing (use cJSON library)
- [ ] Test: Send commands via serial terminal

**Implementation Notes:**
- Uses UART0 (USB serial console) for communication
- JSON messages terminated by newline
- Periodic status messages every 2 seconds in provisioning mode
- Commands: get_status, provision, test_wifi, test_rfid, test_supabase, test_all, factory_reset, reboot

#### 6.2 Provisioning Commands
- [x] Implement `provision` command:
  - Receive hub_id, supabase_url, supabase_key, device_secret
  - Store in NVS
  - Mark device as factory-provisioned
- [x] Implement `get_status` command:
  - Return current provisioning state
  - Return firmware version
- [x] Implement `factory_reset` command:
  - Clear all NVS data
  - Reboot device
- [ ] Test: Provision device via serial

**Implementation Notes:**
- Added test commands: test_wifi, test_rfid, test_supabase, test_all
- Wi-Fi test with 15s timeout, RFID scan for 5s
- Supabase test sends heartbeat to verify connectivity

#### 6.3 Provisioning State
- [x] Add provisioning state to device state machine
- [x] On boot, check if factory-provisioned
- [x] If not provisioned, enter serial provisioning mode
- [x] LED shows appropriate state (white pulsing)
- [ ] Test: Boot unprovisioned device, verify state

**Implementation Notes:**
- `config_is_provisioned()` / `config_set_provisioned()` in config_store
- main.c checks provisioning state on boot
- Blocks in provisioning mode until device is provisioned

#### 6.4 Integration with Admin App
- [x] Document serial protocol for Admin app team
- [ ] Test end-to-end with Admin app (or mock script)
- [ ] Verify device registers in Supabase after provisioning

**Implementation Notes:**
- Protocol documented in `docs/service_mode_protocol.md`
- Includes workflow, commands, responses, error codes, and examples

### Deliverables
- Factory provisioning works via USB serial
- Device stores all required credentials
- Clear factory reset capability
- Documentation for Admin app integration

### Testing
- Connect unprovisioned hub, send provision command
- Verify credentials stored correctly
- Reboot, verify device uses stored credentials
- Factory reset, verify device returns to unprovisioned state

---

## Phase 7: BLE Provisioning

**Goal:** Enable consumer provisioning via BLE with Saturday mobile app.

### Tasks

#### 7.1 BLE Stack Setup
- [ ] Enable BLE in sdkconfig
- [ ] Initialize NimBLE stack (ESP-IDF's BLE implementation)
- [ ] Configure device name: "Saturday Hub XXXX" (last 4 of hub_id)
- [ ] Test: Device appears in BLE scanner app

#### 7.2 Provisioning Service
- [ ] Create `components/provisioning/ble_prov.c`
- [ ] Define GATT service and characteristics:
  ```
  Service: Saturday Provisioning (UUID: 5356xxxx-...)
  ├── Status (Read, Notify)
  ├── WiFi SSID (Write)
  ├── WiFi Password (Write)
  ├── User Token (Write)
  └── Command (Write)
  ```
- [ ] Implement characteristic handlers
- [ ] Test: Connect with nRF Connect, read/write characteristics

#### 7.3 Provisioning Flow
- [ ] Implement state machine:
  1. Awaiting connection
  2. Connected, awaiting credentials
  3. Credentials received, attempting Wi-Fi
  4. Wi-Fi connected, linking to user account
  5. Complete
- [ ] Notify status changes via Status characteristic
- [ ] Handle errors (bad password, network not found)
- [ ] Test: Full flow with nRF Connect app

#### 7.4 Security
- [ ] Require bonding/pairing for write characteristics
- [ ] Implement timeout (stop advertising after 5 minutes)
- [ ] Only allow provisioning when in unprovisioned state
- [ ] Test: Verify can't re-provision already provisioned device

#### 7.5 Button Trigger
- [ ] Long press (3-5s) enters BLE provisioning mode
- [ ] LED shows blue slow blink when in provisioning mode
- [ ] Test: Press button, verify BLE advertising starts

### Deliverables
- BLE provisioning works with mobile app
- Secure pairing required
- Button triggers provisioning mode
- Clear status feedback via BLE notifications

### Testing
- Long press button, verify BLE advertising
- Connect with mobile app, send credentials
- Verify Wi-Fi connects and device links to user
- Try to provision already-provisioned device - should fail

---

## Phase 8: Thread Border Router

**Goal:** Establish Thread network and act as border router.

### Tasks

#### 8.1 OpenThread Setup
- [ ] Enable OpenThread in sdkconfig:
  ```
  CONFIG_OPENTHREAD_ENABLED=y
  CONFIG_OPENTHREAD_BORDER_ROUTER=y
  ```
- [ ] Create `components/network/thread_br.c`
- [ ] Initialize OpenThread stack
- [ ] Test: OpenThread CLI responds to commands

#### 8.2 Thread Network Formation
- [ ] Generate or load network credentials:
  - Network name: "SaturdayVinyl"
  - PAN ID: 0x5356
  - Channel: auto-select or default 15
  - Network key: generate random, store in NVS
- [ ] Form network as Leader
- [ ] Test: Thread network visible in OpenThread sniffer

#### 8.3 Border Router Configuration
- [ ] Configure NAT64 for IPv4 connectivity
- [ ] Advertise OMR (Off-Mesh Routable) prefix
- [ ] Configure DNS-SD for service discovery
- [ ] Test: Thread device can ping external IP

#### 8.4 Network Status
- [ ] Track Thread network state:
  - Network formed
  - Number of devices
  - Device join/leave events
- [ ] Update LED based on Thread status
- [ ] Expose network info for heartbeat
- [ ] Test: Verify device count updates

### Deliverables
- Thread network forms on boot
- Border router bridges Thread to Wi-Fi/Internet
- Network credentials stored persistently
- Device count tracked

### Testing
- Boot hub, verify Thread network forms
- Join Thread device, verify it can reach Internet
- Check device count increases
- Reboot hub, verify network reforms with same credentials

---

## Phase 9: CoAP Server

**Goal:** Receive inventory updates from crates via CoAP.

### Tasks

#### 9.1 CoAP Stack Setup
- [ ] Add CoAP library (ESP-IDF includes libcoap)
- [ ] Create `components/network/coap_server.c`
- [ ] Initialize CoAP server on Thread interface
- [ ] Test: CoAP client can reach server

#### 9.2 Inventory Endpoint
- [ ] Implement POST `/inventory` handler:
  ```c
  typedef struct {
      char crate_id[32];
      int64_t timestamp;
      char epcs[75][25];  // Up to 75 EPCs
      size_t epc_count;
      char added[10][25];
      size_t added_count;
      char removed[10][25];
      size_t removed_count;
  } inventory_update_t;
  ```
- [ ] Parse CBOR or JSON payload
- [ ] Validate EPCs (Saturday prefix check)
- [ ] Test: Send test inventory update

#### 9.3 Heartbeat Endpoint
- [ ] Implement POST `/heartbeat` handler:
  ```c
  typedef struct {
      char crate_id[32];
      uint8_t battery_pct;
      uint8_t tag_count;
      int8_t rssi;
      uint32_t uptime_sec;
  } crate_heartbeat_t;
  ```
- [ ] Track last heartbeat time per crate
- [ ] Test: Send test heartbeat

#### 9.4 Event Forwarding
- [ ] Forward inventory updates to cloud (event reporter)
- [ ] Forward crate heartbeats to cloud
- [ ] Queue if Wi-Fi unavailable
- [ ] Test: CoAP message → Supabase row

### Deliverables
- CoAP server accepts inventory updates
- CoAP server accepts heartbeats
- Data forwarded to Supabase
- Offline queuing works

### Testing
- Use CoAP client (coap-cli or similar) to send test messages
- Verify data appears in Supabase
- Simulate Wi-Fi outage, verify messages queued

---

## Phase 10: Crate Integration

**Goal:** Full end-to-end crate → hub → cloud pipeline with real crate hardware.

### Tasks

#### 10.1 Crate Commissioning
- [ ] Implement Thread commissioner role
- [ ] Add "commission crate" command from cloud
- [ ] Generate and share network credentials with crate
- [ ] Test: Commission real crate device

#### 10.2 Crate Discovery
- [ ] Implement mDNS/DNS-SD discovery
- [ ] Track known crates:
  ```c
  typedef struct {
      char crate_id[32];
      uint8_t thread_addr[16];
      int64_t last_seen;
      uint8_t battery_pct;
      uint8_t tag_count;
  } crate_info_t;
  ```
- [ ] Detect crate join/leave
- [ ] Test: Crate joins, appears in hub's crate list

#### 10.3 Integration Testing
- [ ] Test with real RFID crate hardware
- [ ] Add records, verify inventory update reaches cloud
- [ ] Remove records, verify delta reported correctly
- [ ] Test multiple crates simultaneously
- [ ] Test: Full user scenario

#### 10.4 Error Handling
- [ ] Handle crate disconnection gracefully
- [ ] Handle malformed messages
- [ ] Implement retry logic for cloud failures
- [ ] Test: Simulate various failure modes

### Deliverables
- Real crates commission and connect
- Inventory updates flow to cloud
- Multiple crates supported
- Robust error handling

### Testing
- Add crate to network via commissioning
- Add/remove records from crate
- Verify inventory in Supabase matches physical crate
- Stress test with multiple crates

---

## Phase 11: OTA Updates

**Goal:** Enable over-the-air firmware updates from cloud.

### Tasks

#### 11.1 OTA Partition Setup
- [ ] Configure dual OTA partitions in `partitions.csv`
- [ ] Verify partition table correct with `idf.py partition-table`
- [ ] Test: Flash to both partitions manually

#### 11.2 OTA Client
- [ ] Create `components/ota/ota_manager.c`
- [ ] Implement OTA download from HTTPS URL:
  ```c
  esp_err_t ota_start_update(const char *url);
  ota_state_t ota_get_state(void);
  ```
- [ ] Show LED pattern during update (magenta pulsing)
- [ ] Test: Trigger OTA from hardcoded URL

#### 11.3 Update Check
- [ ] Periodically check Supabase for available updates
- [ ] Compare version strings
- [ ] Download and apply if newer version available
- [ ] Test: Upload new firmware to Supabase, verify hub updates

#### 11.4 Rollback
- [ ] Mark OTA partition as valid after successful boot
- [ ] Implement automatic rollback on repeated boot failures
- [ ] Test: Flash bad firmware, verify rollback occurs

### Deliverables
- OTA updates work from cloud
- Automatic update checking
- Rollback on failure
- LED indicates update in progress

### Testing
- Upload new firmware to Supabase storage
- Verify hub detects and installs update
- Flash intentionally broken firmware, verify rollback
- Verify version reported correctly after update

---

## Phase 12: Hardening

**Goal:** Production-ready error handling and reliability.

### Tasks

#### 12.1 Watchdog
- [ ] Enable task watchdog for critical tasks
- [ ] Configure timeout (30 seconds)
- [ ] Test: Block a task, verify watchdog triggers reboot

#### 12.2 Error Recovery
- [ ] Implement recovery for each error type:
  - Wi-Fi failures: reconnect with backoff
  - RFID failures: reset module, continue
  - Cloud failures: queue and retry
  - Thread failures: reform network
- [ ] Log errors to NVS for diagnostics
- [ ] Test: Inject various failures, verify recovery

#### 12.3 Memory Management
- [ ] Audit heap usage
- [ ] Identify and fix memory leaks
- [ ] Set high-water marks for monitoring
- [ ] Test: Long-running soak test (24+ hours)

#### 12.4 Edge Cases
- [ ] Handle rapid tag swapping
- [ ] Handle >75 records in crate update
- [ ] Handle network credentials too long
- [ ] Handle corrupted NVS (recover gracefully)
- [ ] Test: Each edge case

#### 12.5 Security Audit
- [ ] Verify all credentials encrypted in NVS
- [ ] Verify HTTPS certificate validation enabled
- [ ] Verify BLE pairing required for provisioning
- [ ] Review for common vulnerabilities

### Deliverables
- Watchdog protection for all critical paths
- Graceful recovery from all error types
- No memory leaks
- Security review complete

### Testing
- 24-hour soak test with simulated traffic
- Inject each error type, verify recovery
- Run memory analysis tools
- Security penetration testing (if applicable)

---

## Phase 13: Production Ready

**Goal:** Final polish and release preparation.

### Tasks

#### 13.1 Code Cleanup
- [ ] Remove debug code and test endpoints
- [ ] Review and clean up logging levels
- [ ] Ensure consistent code style
- [ ] Remove unused code and dependencies

#### 13.2 Documentation
- [ ] Update developers_guide.md with final details
- [ ] Document all configuration options
- [ ] Create troubleshooting guide
- [ ] Document manufacturing process

#### 13.3 Release Build
- [ ] Create release build configuration
- [ ] Optimize for size (-Os)
- [ ] Strip debug symbols
- [ ] Sign firmware (if applicable)

#### 13.4 Final Testing
- [ ] Full system integration test
- [ ] Test all provisioning flows
- [ ] Test with production Supabase environment
- [ ] Test with production crate hardware
- [ ] Load testing (many crates, many events)

#### 13.5 Release
- [ ] Tag version in git
- [ ] Generate release notes
- [ ] Upload firmware to Supabase storage
- [ ] Update Admin app with new firmware
- [ ] Create rollback plan

### Deliverables
- Production-quality firmware
- Complete documentation
- Release binaries
- Deployment plan

### Testing
- Full end-to-end test with all components
- Sign-off from stakeholders
- Verification in production environment

---

## Dependencies & Milestones

### Critical Path

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
                                              ↓
                                        Phase 6 & 7 (parallel)
                                              ↓
                                        Phase 8 → Phase 9 → Phase 10
                                              ↓
                                        Phase 11 → Phase 12 → Phase 13
```

### Milestones

| Milestone | Phases Complete | Capability |
|-----------|-----------------|------------|
| **M1: Hardware Validated** | 0-1 | All peripherals functional |
| **M2: Now Playing Works** | 2-3 | Tag detection end-to-end |
| **M3: Cloud Connected** | 4-5 | Events reach Supabase |
| **M4: Provisionable** | 6-7 | Factory and consumer setup |
| **M5: Mesh Capable** | 8-10 | Full crate integration |
| **M6: Release Candidate** | 11-12 | OTA + hardening |
| **M7: Production** | 13 | Ship it |

### External Dependencies

| Dependency | Required By | Notes |
|------------|-------------|-------|
| ESP32-C6 dev boards | Phase 0 | For initial development |
| YRM100 module (SBComponents 3dBi or Generic 2dBi) | Phase 1 | For RFID testing |
| Supabase project | Phase 5 | Tables and auth configured |
| Saturday Admin app | Phase 6 | Serial provisioning support |
| Saturday Mobile app | Phase 7 | BLE provisioning support |
| Crate hardware/firmware | Phase 10 | For integration testing |
| Production hardware | Phase 13 | Final hardware revision |

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Thread BR stability issues | High | Test extensively, have fallback mode |
| YRM100 range too large/small | Medium | RF power tuning (15-26 dBm), antenna selection (2-3 dBi) |
| BLE + Thread coexistence | Medium | Test radio switching, timing |
| Memory constraints | Medium | Monitor early, optimize as needed |
| Supabase rate limits | Low | Implement batching and queuing |

---

## Appendix: Test Hardware

### Development Kit Options

| Board | Pros | Cons |
|-------|------|------|
| ESP32-C6-DevKitC-1 | Official, well documented | May need adapters for RFID |
| ESP32-C6-DevKitM-1 | Smaller footprint | Same |
| Custom breakout | Match production design | Requires PCB fabrication |

### Test Equipment

- Logic analyzer (for UART debugging)
- Known-good RFID tags with Saturday EPCs
- Second ESP32-C6 board (for Thread testing)
- Wi-Fi router (for network testing)
- USB isolator (optional, for ground loop issues)

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
