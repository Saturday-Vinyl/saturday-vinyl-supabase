# Saturday Vinyl Hub Firmware - Implementation Plan

**Project:** sv-hub-firmware (2-SoC Architecture)
**Document Version:** 1.1.0
**Last Updated:** 2026-01-13

---

## Overview

This document breaks down the hub firmware development into iterative phases for a **dual-SoC architecture**:
- **ESP32-S3** (Master) - WiFi, BLE, RFID, Cloud, USB interface
- **ESP32-H2** (Slave) - Thread Border Router, CoAP server

### Why Two SoCs?

Single-chip solutions (ESP32-C6) suffer from WiFi/Thread radio contention in the 2.4 GHz band, causing:
- TLS handshake failures during cloud sync
- Thread mesh instability during WiFi operations
- Unreliable connectivity requiring complex retry logic

The dual-SoC approach provides dedicated radios, eliminating these issues.

### Guiding Principles

1. **Test early, test often** - Get code running on hardware from day one
2. **Vertical slices** - Each phase delivers end-to-end functionality
3. **Parallel development** - S3 and H2 firmware can be developed in parallel after protocol definition
4. **Hardware first** - Validate hardware interfaces before building abstractions
5. **Protocol-driven** - Define S3↔H2 UART protocol early, then implement both sides

### Phase Summary

| Phase | Name | Outcome |
|-------|------|---------|
| **S3 Phases** |||
| S3-0 | Project Setup | S3 build system works, LED blinks |
| S3-1 | Hardware Bring-Up | S3 peripherals functional (LED, button, RFID) |
| S3-2 | RFID Detection | Tags detected and logged |
| S3-3 | Now Playing Logic | Debounced detection with state machine |
| S3-4 | WiFi Connectivity | Connect to network, HTTPS works |
| S3-5 | Supabase Integration | Now Playing events sent to cloud |
| S3-6 | BLE Provisioning | Consumer WiFi setup via mobile app |
| S3-7 | H2 Communication | UART protocol to H2 implemented |
| S3-8 | Service Mode | Factory provisioning via USB serial |
| **H2 Phases** |||
| H2-0 | Project Setup | H2 build system works |
| H2-1 | Thread Border Router | Thread network forms and runs |
| H2-2 | CoAP Server | Receive messages from mock crate |
| H2-3 | S3 Communication | UART protocol to S3 implemented |
| **Integration Phases** |||
| INT-1 | S3↔H2 Integration | Both chips communicate reliably |
| INT-2 | Full Pipeline | Crate → H2 → S3 → Cloud |
| INT-3 | H2 Firmware Update | S3 can flash H2 via esp-serial-flasher |
| **Production Phases** |||
| PROD-1 | OTA Updates | Firmware updates from cloud |
| PROD-2 | Hardening | Error handling, watchdogs |
| PROD-3 | Production Ready | Final testing, documentation |

---

## Repository Setup

Before starting development, set up the repository structure:

```
sv-hub-firmware/
├── s3-master/                      # ESP32-S3 master firmware
│   ├── CMakeLists.txt
│   ├── sdkconfig.defaults
│   ├── partitions.csv
│   ├── main/
│   └── components/
│
├── h2-thread-br/                   # ESP32-H2 slave firmware
│   ├── CMakeLists.txt
│   ├── sdkconfig.defaults
│   ├── partitions.csv
│   ├── main/
│   └── components/
│
├── shared/                         # Shared definitions
│   ├── protocol/
│   │   └── s3_h2_protocol.h        # UART protocol definitions
│   └── common/
│
├── tools/
│   ├── flash_both.py
│   └── flash_h2_via_s3.py
│
└── docs/
    ├── developers_guide.md
    └── implementation_plan.md
```

---

## S3 Phases (ESP32-S3 Master Firmware)

### Phase S3-0: Project Setup

**Goal:** Establish S3 development environment and verify basic firmware runs.

#### Tasks

##### S3-0.1 Development Environment
- [ ] Install ESP-IDF v5.2+ with ESP32-S3 support
- [ ] Verify toolchain: `idf.py --version`
- [ ] Set up git repository with dual-project structure

##### S3-0.2 Create S3 Project
- [ ] Create `s3-master/` directory structure
- [ ] Set target: `idf.py set-target esp32s3`
- [ ] Configure partition table for OTA support
- [ ] Create `sdkconfig.defaults`:
  ```
  CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y
  CONFIG_PARTITION_TABLE_CUSTOM=y
  CONFIG_ESP_SYSTEM_PANIC_PRINT_HALT=y
  ```

##### S3-0.3 Hello World Build
- [ ] Write minimal `main.c` that logs "Saturday Hub S3 starting..."
- [ ] Build: `idf.py build`
- [ ] Flash: `idf.py -p <PORT> flash monitor`

##### S3-0.4 LED Blink Test
- [ ] Configure GPIO48 for WS2812 LED (ESP32-S3 native)
- [ ] Implement simple blink loop
- [ ] Verify LED toggles on hardware

#### Deliverables
- Working S3 build system
- S3 firmware boots and blinks LED
- Serial console output visible

---

### Phase S3-1: Hardware Bring-Up

**Goal:** Validate all S3 peripherals work independently.

#### Tasks

##### S3-1.1 RGB LED Driver
- [ ] Create `components/ui/led_manager.c`
- [ ] Configure WS2812 on GPIO48 using RMT
- [ ] Implement patterns: SOLID, BLINK_SLOW, BLINK_FAST, PULSE

##### S3-1.2 Button Input
- [ ] Create `components/ui/button_handler.c`
- [ ] Configure GPIO0 as input with internal pull-up
- [ ] Implement debounced button with duration detection:
  - SHORT (<500ms)
  - LONG (3-5s) → Enter BLE provisioning
  - FACTORY (>10s) → Factory reset

##### S3-1.3 UART1 for RFID Module
- [ ] Configure UART1 at 115200 baud:
  - GPIO17 = TX → YRM100 RXD
  - GPIO18 = RX ← YRM100 TXD
- [ ] Configure GPIO5 as RFID enable (active high)
- [ ] Implement basic send/receive functions
- [ ] Test: Send GetRfPower command, verify response

##### S3-1.4 UART2 for H2 Communication
- [ ] Configure UART2 at 115200 baud:
  - GPIO15 = TX → H2 RX
  - GPIO16 = RX ← H2 TX
- [ ] Configure GPIO6 as H2_EN (reset control)
- [ ] Configure GPIO7 as H2_BOOT (boot mode)
- [ ] Test: Send bytes, verify loopback (with H2 not connected)

##### S3-1.5 USB Console
- [ ] Verify USB-CDC works for debug output
- [ ] Test ESP_LOG output at various levels

#### Deliverables
- LED shows any color/pattern
- Button presses detected with duration
- RFID UART communication working
- H2 UART ready for protocol
- Debug console functional

---

### Phase S3-2: RFID Detection

**Goal:** Detect RFID tags and extract EPC data.

*Note: Same as original Phase 2 - YRM100 driver and polling.*

#### Tasks

##### S3-2.1 YRM100 Frame Codec
- [ ] Create `components/rfid/rfid_protocol.c`
- [ ] Implement frame builder and parser
- [ ] Implement checksum calculation

##### S3-2.2 YRM100 Driver
- [ ] Create `components/rfid/yrm100_driver.c`
- [ ] Implement: init, get_firmware, set/get_rf_power, polling

##### S3-2.3 Tag Polling
- [ ] Parse tag notice frames (RSSI, PC, EPC)
- [ ] Validate Saturday tags (0x5356 prefix)

##### S3-2.4 Continuous Polling Task
- [ ] Background task for RFID polling
- [ ] Callback-based tag notifications

#### Deliverables
- Tags detected with EPC and RSSI
- Saturday vs non-Saturday tags distinguished
- Continuous polling runs in background

---

### Phase S3-3: Now Playing Logic

**Goal:** Implement debounced "Now Playing" detection.

*Note: Same as original Phase 3.*

#### Tasks

##### S3-3.1 Configuration Storage
- [ ] Create `components/config/config_store.c`
- [ ] NVS-based config for RFID parameters

##### S3-3.2 Now Playing State Machine
- [ ] States: IDLE, TAG_CONFIRMING, TAG_PRESENT, TAG_REMOVING
- [ ] Debounce timers for place/remove

##### S3-3.3 Event Generation
- [ ] TAG_PLACED and TAG_REMOVED events
- [ ] ESP-IDF event loop integration

##### S3-3.4 LED Feedback
- [ ] Green flash on tag place
- [ ] Dim green when tag present

#### Deliverables
- Debounced tag detection
- Events for place/remove
- LED indicates state

---

### Phase S3-4: WiFi Connectivity

**Goal:** Connect to WiFi and make HTTPS requests.

*Note: Same as original Phase 4, but simpler without Thread contention.*

#### Tasks

##### S3-4.1 WiFi Manager
- [ ] Create `components/network/wifi_manager.c`
- [ ] Station mode with auto-reconnect
- [ ] Exponential backoff for retries

##### S3-4.2 WiFi Credential Storage
- [ ] NVS storage for SSID/password

##### S3-4.3 HTTP Client
- [ ] Create `components/network/http_client.c`
- [ ] HTTPS with TLS certificate bundle
- [ ] Basic GET/POST functions

#### Deliverables
- WiFi connects on boot
- Auto-reconnect on disconnect
- HTTPS requests work reliably

---

### Phase S3-5: Supabase Integration

**Goal:** Send events to Supabase cloud.

*Note: Same as original Phase 5.*

#### Tasks

##### S3-5.1 Supabase Client
- [ ] Create `components/cloud/supabase_client.c`
- [ ] Authenticated REST API calls

##### S3-5.2 Event Reporter
- [ ] Create `components/cloud/event_reporter.c`
- [ ] Forward Now Playing events to Supabase

##### S3-5.3 Event Queue
- [ ] In-memory queue for offline support
- [ ] Flush on WiFi reconnect

##### S3-5.4 Hub Heartbeat
- [ ] Periodic heartbeat (5 minutes)
- [ ] Include: version, WiFi RSSI, H2 status, free heap

#### Deliverables
- Now Playing events in Supabase
- Offline queuing works
- Hub heartbeats for monitoring

---

### Phase S3-6: BLE Provisioning

**Goal:** Consumer WiFi setup via BLE.

*Note: Same as original Phase 7.*

#### Tasks

##### S3-6.1 BLE Stack Setup
- [ ] Enable NimBLE
- [ ] Device name: "Saturday Hub XXXX"

##### S3-6.2 Provisioning Service
- [ ] GATT service with Saturday UUIDs
- [ ] Characteristics: Device Info, Status, Command, WiFi SSID/Password

##### S3-6.3 Provisioning Flow
- [ ] State machine: IDLE → ADVERTISING → CONNECTED → CONNECTING_WIFI → SUCCESS

##### S3-6.4 Button Trigger
- [ ] Long press (3-5s) enters BLE mode
- [ ] LED shows blue blink when advertising

#### Deliverables
- BLE provisioning works with mobile app
- Button triggers provisioning mode
- Status feedback via LED

---

### Phase S3-7: H2 Communication

**Goal:** Implement UART protocol to communicate with H2.

#### Tasks

##### S3-7.1 Protocol Definition
- [ ] Create `shared/protocol/s3_h2_protocol.h`
- [ ] Define frame format:
  ```c
  #define PROTO_HEADER        0xAA
  #define PROTO_END           0x55

  // S3 → H2 Commands
  #define CMD_PING            0x01
  #define CMD_GET_STATUS      0x02
  #define CMD_GET_CREDENTIALS 0x03
  #define CMD_START_THREAD    0x05
  #define CMD_STOP_THREAD     0x06
  #define CMD_ENABLE_JOINING  0x07
  #define CMD_ENTER_BOOTLOADER 0x10

  // H2 → S3 Responses
  #define RSP_PONG            0x81
  #define RSP_STATUS          0x82
  #define RSP_CREDENTIALS     0x83
  #define RSP_ACK             0x84
  #define RSP_NAK             0x85

  // H2 → S3 Events (async)
  #define EVT_CRATE_JOINED    0xE0
  #define EVT_CRATE_LEFT      0xE1
  #define EVT_INVENTORY_UPDATE 0xE2
  #define EVT_CRATE_HEARTBEAT 0xE3
  ```

##### S3-7.2 Protocol Codec
- [ ] Create `components/h2_comm/h2_protocol.c`
- [ ] Frame builder with CRC-16
- [ ] Frame parser with validation

##### S3-7.3 H2 Communication Task
- [ ] Create `components/h2_comm/h2_comm.c`
- [ ] Background task for UART RX
- [ ] Command/response with 1s timeout
- [ ] Async event handling

##### S3-7.4 H2 Control Functions
- [ ] `h2_ping()` - Health check
- [ ] `h2_get_status()` - Get Thread BR status
- [ ] `h2_start_thread()` - Start Thread network
- [ ] `h2_enable_joining()` - Enable commissioner

##### S3-7.5 H2 Health Monitoring
- [ ] Periodic PING every 5 seconds
- [ ] Reset H2 after 3 failures (GPIO6 toggle)
- [ ] LED shows H2 error state

##### S3-7.6 Event Forwarding
- [ ] Forward INVENTORY_UPDATE to Supabase
- [ ] Forward CRATE_HEARTBEAT to Supabase
- [ ] Queue if WiFi unavailable

#### Deliverables
- UART protocol fully defined
- S3 can send commands to H2
- S3 receives events from H2
- H2 health monitoring works

---

### Phase S3-8: Service Mode

**Goal:** Implement Service Mode for factory provisioning and technician access via USB serial.

Service Mode provides a standardized serial interface for factory provisioning, device testing, diagnostics, and servicing. See `docs/service_mode_protocol.md` for the full protocol specification.

#### Tasks

##### S3-8.1 Service Mode Component
- [ ] Create `components/service_mode/service_mode.c`
- [ ] Create `components/service_mode/service_manifest.json`
- [ ] Embed manifest at compile time using `EMBED_TXTFILES`

##### S3-8.2 Service Mode Entry
- [ ] Fresh device (no `unit_id`) → auto-enter service mode on boot
- [ ] Provisioned device → 10-second window to receive `enter_service_mode`
- [ ] LED shows white pulse when in service mode

##### S3-8.3 Status Beacon
- [ ] Send status beacon every 2 seconds while in service mode:
  ```json
  {
    "status": "service_mode",
    "data": {
      "device_type": "hub",
      "firmware_version": "1.0.0",
      "mac_address": "AA:BB:CC:DD:EE:FF",
      "unit_id": "SV-HUB-000001",
      "cloud_configured": true
    }
  }
  ```

##### S3-8.4 Core Commands
- [ ] `enter_service_mode` - Enter service mode (boot window only)
- [ ] `exit_service_mode` - Exit to standard operation
- [ ] `get_status` - Return device status including H2/Thread info
- [ ] `get_manifest` - Return Service Mode Manifest
- [ ] `provision` - Store `unit_id` and cloud credentials
- [ ] `reboot` - Reboot device

##### S3-8.5 Test Commands
- [ ] `test_wifi` - Test WiFi connectivity (with optional credentials)
- [ ] `test_rfid` - Test RFID module (scan for tags)
- [ ] `test_cloud` - Test Supabase connectivity (send heartbeat)
- [ ] `test_thread` - Query H2 for Thread network status
- [ ] `test_all` - Run all supported tests in sequence

##### S3-8.6 Reset Commands
- [ ] `customer_reset` - Clear user data, preserve unit_id and cloud config
- [ ] `factory_reset` - Full wipe including unit_id (returns to fresh state)

##### S3-8.7 Thread Credential Retrieval
- [ ] Query H2 for Thread credentials via `h2_get_credentials()`
- [ ] Include Thread credentials in `get_status` response:
  ```json
  {
    "thread": {
      "network_name": "SaturdayVinyl",
      "pan_id": 21334,
      "channel": 15,
      "network_key": "0123456789abcdef...",
      "extended_pan_id": "0123456789abcdef"
    }
  }
  ```

##### S3-8.8 Service Mode Manifest
- [ ] Define manifest for Saturday Hub:
  ```json
  {
    "manifest_version": "1.0",
    "device_type": "hub",
    "device_name": "Saturday Vinyl Hub",
    "capabilities": {
      "wifi": true,
      "bluetooth": true,
      "thread": true,
      "cloud": true,
      "rfid": true,
      "audio": false,
      "display": false,
      "battery": false,
      "button": true
    },
    "supported_tests": ["wifi", "cloud", "rfid", "thread"],
    "provisioning_fields": {
      "required": ["unit_id", "cloud_url", "cloud_anon_key"],
      "optional": ["cloud_device_secret"]
    }
  }
  ```

#### Deliverables
- Factory provisioning via USB serial works
- All test commands functional
- Thread credentials retrievable via service mode
- Manifest accurately describes device capabilities
- Customer and factory reset work correctly

#### Testing
- Connect fresh device, verify auto-enters service mode
- Send `provision`, verify credentials stored
- Run `test_all`, verify all tests pass
- Run `factory_reset`, verify device returns to fresh state
- Connect provisioned device, verify 10-second entry window

---

## H2 Phases (ESP32-H2 Slave Firmware)

### Phase H2-0: Project Setup

**Goal:** Establish H2 development environment.

#### Tasks

##### H2-0.1 Create H2 Project
- [ ] Create `h2-thread-br/` directory structure
- [ ] Set target: `idf.py set-target esp32h2`
- [ ] Configure sdkconfig.defaults:
  ```
  CONFIG_OPENTHREAD_ENABLED=y
  CONFIG_OPENTHREAD_BORDER_ROUTER=y
  CONFIG_OPENTHREAD_RADIO_NATIVE=y
  CONFIG_IEEE802154_ENABLED=y
  ```

##### H2-0.2 Hello World Build
- [ ] Write minimal main.c
- [ ] Build and flash via direct connection
- [ ] Verify serial output

#### Deliverables
- Working H2 build system
- H2 firmware boots

---

### Phase H2-1: Thread Border Router

**Goal:** Thread network forms and operates as Border Router.

#### Tasks

##### H2-1.1 OpenThread Setup
- [ ] Create `components/thread_br/thread_br.c`
- [ ] Initialize OpenThread stack
- [ ] Configure as Border Router

##### H2-1.2 Thread Network Formation
- [ ] Generate or load network credentials
- [ ] Form network as Leader
- [ ] Store credentials in NVS

##### H2-1.3 Border Router Configuration
- [ ] Configure NAT64
- [ ] Advertise OMR prefix
- [ ] Enable DNS-SD

##### H2-1.4 Network Status Tracking
- [ ] Track state: DISABLED, DETACHED, ROUTER, LEADER
- [ ] Track device count
- [ ] Track device join/leave events

#### Deliverables
- Thread network forms on boot
- Border router bridges Thread to IP
- Network credentials persist

---

### Phase H2-2: CoAP Server

**Goal:** Receive messages from crates via CoAP.

#### Tasks

##### H2-2.1 CoAP Stack Setup
- [ ] Create `components/coap_server/coap_server.c`
- [ ] Initialize libcoap on Thread interface

##### H2-2.2 Inventory Endpoint
- [ ] POST `/inventory` handler
- [ ] Parse JSON/CBOR payload
- [ ] Queue for S3 forwarding

##### H2-2.3 Heartbeat Endpoint
- [ ] POST `/heartbeat` handler
- [ ] Track last heartbeat per crate

##### H2-2.4 Config Endpoint
- [ ] GET `/config` handler
- [ ] Return crate configuration

#### Deliverables
- CoAP server accepts inventory updates
- CoAP server accepts heartbeats
- Data queued for S3

---

### Phase H2-3: S3 Communication

**Goal:** Implement UART protocol to communicate with S3.

#### Tasks

##### H2-3.1 Include Shared Protocol
- [ ] Reference `shared/protocol/s3_h2_protocol.h`
- [ ] Or copy definitions to H2 project

##### H2-3.2 Protocol Codec
- [ ] Create `components/s3_comm/s3_protocol.c`
- [ ] Frame builder and parser (same as S3 side)

##### H2-3.3 S3 Communication Task
- [ ] Create `components/s3_comm/s3_comm.c`
- [ ] Background task for UART RX
- [ ] Command handler

##### H2-3.4 Command Handlers
- [ ] PING → PONG
- [ ] GET_STATUS → STATUS (JSON)
- [ ] GET_CREDENTIALS → CREDENTIALS (JSON)
- [ ] START_THREAD → ACK + start
- [ ] ENABLE_JOINING → ACK + commission

##### H2-3.5 Event Sending
- [ ] Send CRATE_JOINED on Thread join
- [ ] Send CRATE_LEFT on Thread leave
- [ ] Send INVENTORY_UPDATE from CoAP
- [ ] Send CRATE_HEARTBEAT from CoAP

##### H2-3.6 Bootloader Command
- [ ] ENTER_BOOTLOADER → reset to download mode
- [ ] Uses GPIO4 boot strapping

#### Deliverables
- H2 responds to S3 commands
- H2 sends events to S3
- Bootloader mode works

---

## Integration Phases

### Phase INT-1: S3↔H2 Integration

**Goal:** Both chips communicate reliably together.

#### Tasks

##### INT-1.1 Physical Connection
- [ ] Wire S3 UART2 to H2 UART0
- [ ] Wire S3 GPIO6 to H2 EN
- [ ] Wire S3 GPIO7 to H2 GPIO4 (boot)

##### INT-1.2 Communication Test
- [ ] S3 sends PING, H2 responds PONG
- [ ] S3 sends GET_STATUS, H2 responds with Thread status
- [ ] H2 sends async events, S3 receives

##### INT-1.3 Thread Control
- [ ] S3 sends START_THREAD, H2 forms network
- [ ] S3 sends ENABLE_JOINING, H2 enables commissioner
- [ ] S3 monitors H2 via periodic PING

##### INT-1.4 Error Recovery
- [ ] S3 detects H2 not responding
- [ ] S3 resets H2 via GPIO6
- [ ] H2 recovers and rejoins Thread network

#### Deliverables
- Reliable S3↔H2 communication
- Thread network controlled by S3
- H2 recovery works

---

### Phase INT-2: Full Pipeline

**Goal:** End-to-end crate → H2 → S3 → Cloud pipeline.

#### Tasks

##### INT-2.1 Mock Crate Testing
- [ ] Use CoAP client to simulate crate
- [ ] Send inventory update to H2
- [ ] Verify reaches S3 via UART
- [ ] Verify reaches Supabase

##### INT-2.2 Thread Commissioning
- [ ] S3 receives "add crate" from cloud
- [ ] S3 sends ENABLE_JOINING to H2
- [ ] Crate joins Thread network
- [ ] H2 sends CRATE_JOINED to S3
- [ ] S3 reports to Supabase

##### INT-2.3 Inventory Flow
- [ ] Crate sends inventory via CoAP to H2
- [ ] H2 forwards via UART to S3
- [ ] S3 sends to Supabase
- [ ] Verify correct data at each hop

##### INT-2.4 Real Crate Integration
- [ ] Test with actual crate hardware
- [ ] Verify join, inventory, heartbeat flows

#### Deliverables
- Full crate → cloud pipeline works
- Commissioning works
- Multiple crates supported

---

### Phase INT-3: H2 Firmware Update

**Goal:** S3 can flash H2 firmware via UART.

#### Tasks

##### INT-3.1 esp-serial-flasher Integration
- [ ] Add esp-serial-flasher component to S3
- [ ] Configure for H2 (ESP32-H2 target)

##### INT-3.2 Bootloader Entry
- [ ] S3 sends ENTER_BOOTLOADER command
- [ ] H2 resets into download mode
- [ ] Verify H2 responds to esptool protocol

##### INT-3.3 Flash via UART
- [ ] S3 receives H2 firmware (from OTA or serial)
- [ ] S3 flashes H2 via UART2
- [ ] S3 resets H2 into normal mode

##### INT-3.4 Version Management
- [ ] S3 stores expected H2 version
- [ ] On boot, S3 checks H2 version
- [ ] Update H2 if version mismatch

#### Deliverables
- S3 can update H2 firmware
- Single USB connection flashes both chips
- Version checking works

---

## Production Phases

### Phase PROD-1: OTA Updates

**Goal:** Over-the-air firmware updates for both S3 and H2.

#### Tasks

##### PROD-1.1 S3 OTA
- [ ] Dual OTA partitions for S3
- [ ] Download from Supabase storage
- [ ] Rollback on boot failure

##### PROD-1.2 H2 OTA via S3
- [ ] OTA package includes both S3 and H2 firmware
- [ ] S3 updates itself first
- [ ] S3 updates H2 after reboot
- [ ] Verify both versions match expected

##### PROD-1.3 Update Check
- [ ] Periodic check for updates
- [ ] Version comparison
- [ ] Download and apply

#### Deliverables
- Both chips updatable via cloud
- Rollback on failure
- Version management

---

### Phase PROD-2: Hardening

**Goal:** Production-ready reliability.

#### Tasks

##### PROD-2.1 Watchdogs
- [ ] Task watchdog on S3 critical tasks
- [ ] H2 monitored by S3 via PING

##### PROD-2.2 Error Recovery
- [ ] WiFi: reconnect with backoff
- [ ] RFID: reset module
- [ ] H2: reset via GPIO
- [ ] Cloud: queue and retry

##### PROD-2.3 Memory Management
- [ ] Audit heap usage on both chips
- [ ] Fix memory leaks
- [ ] Monitor free heap in heartbeats

##### PROD-2.4 Edge Cases
- [ ] Rapid tag swapping
- [ ] H2 crash during cloud sync
- [ ] Large inventory updates
- [ ] Corrupted NVS recovery

#### Deliverables
- Watchdog protection
- Graceful error recovery
- No memory leaks

---

### Phase PROD-3: Production Ready

**Goal:** Final polish and release.

#### Tasks

##### PROD-3.1 Code Cleanup
- [ ] Remove debug code
- [ ] Review logging levels
- [ ] Consistent code style

##### PROD-3.2 Documentation
- [ ] Update developers_guide.md
- [ ] Document configuration options
- [ ] Create troubleshooting guide

##### PROD-3.3 Release Build
- [ ] Create release configurations for both projects
- [ ] Optimize for size
- [ ] Sign firmware (if applicable)

##### PROD-3.4 Final Testing
- [ ] Full system integration
- [ ] All provisioning flows
- [ ] Load testing
- [ ] 24-hour soak test

#### Deliverables
- Production-quality firmware
- Complete documentation
- Release binaries

---

## Development Workflow

### Parallel Development

After completing Phase S3-7 and H2-3 (protocol definition), S3 and H2 development can proceed in parallel:

```
              ┌─────────────┐
              │  Protocol   │
              │ Definition  │
              │   S3-7.1    │
              └──────┬──────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌───────────────┐         ┌───────────────┐
│  S3 Firmware  │         │  H2 Firmware  │
│  Development  │         │  Development  │
│               │         │               │
│ S3-0 → S3-7   │         │ H2-0 → H2-3   │
└───────┬───────┘         └───────┬───────┘
        │                         │
        └────────────┬────────────┘
                     ▼
              ┌─────────────┐
              │ Integration │
              │  INT-1,2,3  │
              └──────┬──────┘
                     ▼
              ┌─────────────┐
              │ Production  │
              │ PROD-1,2,3  │
              └─────────────┘
```

### Testing Strategy

#### Unit Testing
- Each component tested independently
- Mock UART for protocol testing
- Mock WiFi for cloud testing

#### Integration Testing
- S3 + H2 communication
- End-to-end pipeline
- OTA update flow

#### Hardware-in-the-Loop
- Real ESP32-S3 + ESP32-H2 boards
- YRM100 RFID module
- Thread development kit as mock crate
- WiFi router for network testing

### Build Commands

```bash
# Build S3 firmware
cd s3-master
idf.py set-target esp32s3
idf.py build

# Build H2 firmware
cd h2-thread-br
idf.py set-target esp32h2
idf.py build

# Flash S3 (direct USB)
cd s3-master
idf.py -p /dev/ttyUSB0 flash monitor

# Flash H2 (direct USB, development only)
cd h2-thread-br
idf.py -p /dev/ttyUSB1 flash monitor

# Flash H2 via S3 (production)
python tools/flash_h2_via_s3.py -p /dev/ttyUSB0 h2-thread-br/build/h2-thread-br.bin
```

---

## Dependencies & Milestones

### Critical Path

```
S3-0 → S3-1 → S3-2 → S3-3 → S3-4 → S3-5 → S3-6 → S3-7 → S3-8
                                                          │
H2-0 ─────────────► H2-1 ───────► H2-2 ───────► H2-3 ─────┤
                                                          │
                                                          ▼
                                                     INT-1 → INT-2 → INT-3
                                                                     │
                                                                     ▼
                                                           PROD-1 → PROD-2 → PROD-3
```

### Milestones

| Milestone | Phases | Capability |
|-----------|--------|------------|
| **M1: S3 Hardware** | S3-0, S3-1 | S3 peripherals work |
| **M2: Now Playing** | S3-2, S3-3 | RFID detection works |
| **M3: Cloud Connected** | S3-4, S3-5 | Events reach Supabase |
| **M4: BLE Provisioning** | S3-6 | Consumer setup works |
| **M5: H2 Thread BR** | H2-0, H2-1, H2-2 | Thread network operational |
| **M6: Dual-SoC Integration** | S3-7, H2-3, INT-1 | Both chips communicate |
| **M7: Service Mode** | S3-8 | Factory provisioning works |
| **M8: Full Pipeline** | INT-2 | Crate → Cloud works |
| **M9: Production** | INT-3, PROD-* | Ship ready |

### Hardware Requirements

| Hardware | Required By | Notes |
|----------|-------------|-------|
| ESP32-S3-DevKitC-1 | S3-0 | Master development |
| ESP32-H2-DevKitM-1 | H2-0 | Slave development |
| YRM100 module | S3-1 | RFID testing |
| Thread dev kit | INT-2 | Mock crate |
| WiFi router | S3-4 | Network testing |
| Logic analyzer | INT-1 | UART debugging |

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| UART protocol reliability | High | Checksums, retries, health monitoring |
| H2 firmware update failure | High | Rollback capability, version checking |
| Thread BR instability | Medium | Dedicated chip, no radio contention |
| S3-H2 communication latency | Medium | Keep protocol simple, async events |
| Memory constraints on H2 | Medium | 320KB SRAM, monitor usage |
| Hardware cost increase | Low | H2 adds ~$2-3 BOM cost |

---

## Appendix: Pin Mapping Summary

### ESP32-S3 Pin Assignments

| GPIO | Function | Direction | Notes |
|------|----------|-----------|-------|
| 0 | BUTTON | Input | Internal pull-up |
| 5 | RFID_EN | Output | Active high |
| 6 | H2_EN | Output | Active high, resets H2 |
| 7 | H2_BOOT | Output | High=normal, Low=download |
| 15 | UART2_TX | Output | To H2 RX |
| 16 | UART2_RX | Input | From H2 TX |
| 17 | UART1_TX | Output | To RFID RX |
| 18 | UART1_RX | Input | From RFID TX |
| 19 | USB_D- | Bidirectional | Native USB |
| 20 | USB_D+ | Bidirectional | Native USB |
| 48 | WS2812 | Output | RGB LED |

### ESP32-H2 Pin Assignments

| GPIO | Function | Direction | Notes |
|------|----------|-----------|-------|
| 4 | BOOT_MODE | Input | Boot strapping |
| 5 | STATUS_LED | Output | Optional |
| 23 | UART0_RX | Input | From S3 TX |
| 24 | UART0_TX | Output | To S3 RX |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
