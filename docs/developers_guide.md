# Saturday Vinyl Hub Firmware - Developer Guide

**Project:** sv-hub-firmware
**Version:** 0.1.0
**Status:** Pre-development
**Audience:** Internal Saturday Vinyl engineers and AI agents

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Hardware Platform](#hardware-platform)
4. [Development Environment](#development-environment)
5. [Firmware Architecture](#firmware-architecture)
6. [Thread Border Router](#thread-border-router)
7. [CoAP Protocol (Crate Communication)](#coap-protocol-crate-communication)
8. [UHF RFID Module (Now Playing)](#uhf-rfid-module-now-playing)
9. [Cloud Integration (Supabase)](#cloud-integration-supabase)
10. [Provisioning](#provisioning)
11. [User Interface (LED & Button)](#user-interface-led--button)
12. [Configuration & Storage](#configuration--storage)
13. [Error Handling](#error-handling)
14. [Testing](#testing)
15. [Versioning & Releases](#versioning--releases)
16. [Reference](#reference)

---

## Overview

### What is the Saturday Vinyl Hub?

The Saturday Vinyl Hub is an embedded device that serves as the central connectivity point for Saturday Vinyl's record tracking ecosystem. It performs two primary functions:

1. **Thread Border Router** - Bridges the Thread mesh network (connecting battery-powered RFID crates) to the IP network (Wi-Fi) and ultimately to the Saturday cloud (Supabase).

2. **Now Playing Detection** - Uses an integrated UHF RFID reader to detect which record is currently on the user's turntable and reports this to the cloud for "Now Playing" experiences in the Saturday mobile app.

### Product Context

Saturday Vinyl manufactures furniture with embedded technology for vinyl record enthusiasts:

- **RFID Crates** - Battery-powered record storage crates with built-in UHF RFID readers that track up to 75 records each. These communicate over Thread to minimize power consumption.
- **RFID Tags** - Applied to record sleeves, each containing a unique 96-bit EPC identifier with the Saturday Vinyl prefix (`5356` = "SV" in ASCII).
- **Saturday Mobile App** - Consumer-facing Flutter app for iOS and Android that displays the user's collection, now playing status, and listening history.
- **Saturday Admin App** - Internal Flutter desktop app for tag provisioning, device configuration, and diagnostics.

### Data Flow

```
┌─────────────────┐     Thread/CoAP      ┌─────────────────┐
│   RFID Crate    │◄────────────────────►│                 │
│  (up to 75 tags)│                      │                 │
└─────────────────┘                      │                 │
                                         │   Saturday Hub  │
┌─────────────────┐     Thread/CoAP      │   (this device) │
│   RFID Crate    │◄────────────────────►│                 │
│  (up to 75 tags)│                      │                 │     Wi-Fi/HTTPS
└─────────────────┘                      │                 │◄─────────────────►  Supabase
                                         │                 │
        ...                              │                 │
                                         │                 │
┌─────────────────┐                      │                 │
│    Turntable    │     UHF RFID         │                 │
│  (record + tag) │◄────────────────────►│                 │
└─────────────────┘     (local reader)   └─────────────────┘
```

---

## System Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Saturday Hub Firmware                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Network   │  │    RFID     │  │   Cloud     │  │    Provisioning     │ │
│  │   Manager   │  │   Manager   │  │   Client    │  │      Manager        │ │
│  │             │  │             │  │             │  │                     │ │
│  │ - Wi-Fi     │  │ - YRM100    │  │ - Supabase  │  │ - BLE (consumer)    │ │
│  │ - Thread BR │  │ - Polling   │  │ - REST API  │  │ - Serial (factory)  │ │
│  │ - CoAP      │  │ - Detection │  │ - Events    │  │ - Config storage    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                │                     │           │
│  ┌──────┴────────────────┴────────────────┴─────────────────────┴─────────┐ │
│  │                          Event Bus / Message Queue                      │ │
│  └──────┬────────────────────────────────────────────────────────┬────────┘ │
│         │                                                        │          │
│  ┌──────┴──────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┴────────┐ │
│  │     UI      │  │   Config    │  │     OTA     │  │    Diagnostics     │ │
│  │   Manager   │  │   Store     │  │   Manager   │  │      & Logging     │ │
│  │             │  │             │  │             │  │                    │ │
│  │ - RGB LED   │  │ - NVS       │  │ - Firmware  │  │ - Health checks    │ │
│  │ - Button    │  │ - Defaults  │  │ - Rollback  │  │ - Error reporting  │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────────────────┘ │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                              ESP-IDF / FreeRTOS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                               ESP32-C6 Hardware                              │
│            (Wi-Fi 6 | Thread/802.15.4 | BLE 5.0 | UART | GPIO)              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Task/Thread Model

The firmware uses FreeRTOS tasks for concurrent operations:

| Task | Priority | Stack Size | Description |
|------|----------|------------|-------------|
| `network_task` | High | 8KB | Wi-Fi connection, Thread BR management |
| `coap_task` | High | 4KB | CoAP server for crate communication |
| `rfid_task` | Medium | 4KB | RFID polling and tag detection |
| `cloud_task` | Medium | 8KB | Supabase API communication |
| `ui_task` | Low | 2KB | LED patterns and button handling |
| `main_task` | Medium | 4KB | Coordination and state machine |

---

## Hardware Platform

### ESP32-C6 Microcontroller

The ESP32-C6 was selected for its native support of all required wireless protocols on a single chip.

| Feature | Specification |
|---------|---------------|
| CPU | 32-bit RISC-V, 160 MHz |
| RAM | 512 KB SRAM |
| Flash | 4 MB (typical module) |
| Wi-Fi | 802.11ax (Wi-Fi 6), 2.4 GHz |
| Thread | 802.15.4 radio, OpenThread stack |
| Bluetooth | BLE 5.0 |
| UART | 2x UART controllers |
| GPIO | 22 programmable GPIOs |
| ADC | 12-bit SAR ADC |
| Operating Voltage | 3.3V |

### Pin Assignments

| GPIO | Function | Description |
|------|----------|-------------|
| GPIO0 | UART0_TX | Debug console TX |
| GPIO1 | UART0_RX | Debug console RX |
| GPIO4 | UART1_TX | RFID module RX (hub transmits) |
| GPIO5 | UART1_RX | RFID module TX (hub receives) |
| GPIO6 | RFID_EN | RFID module enable (active high) |
| GPIO8 | LED_R | RGB LED - Red (PWM) |
| GPIO9 | LED_G | RGB LED - Green (PWM) |
| GPIO10 | LED_B | RGB LED - Blue (PWM) |
| GPIO18 | BUTTON | Multi-purpose button (active low, internal pull-up) |
| GPIO19 | USB_D- | USB-C data minus |
| GPIO20 | USB_D+ | USB-C data plus |

*Note: Pin assignments are preliminary and subject to change during hardware design.*

### YRM100 UHF RFID Module

The YRM100 module handles all RFID operations for "Now Playing" detection.

| Parameter | Value |
|-----------|-------|
| Module | YRM100 |
| Frequency | UHF 860-960 MHz |
| Protocol | ISO 18000-6C / EPC Gen2 |
| Interface | UART (3.3V TTL) |
| Baud Rate | 115200 (8N1) |
| RF Power | 0-30 dBm (configurable) |
| Default Power | 20 dBm |
| Supply Voltage | 3.3V - 5V |
| Enable Pin | Active high (min 1.5V) |

#### YRM100 Pinout

```
┌─────────────────────────────────────┐
│           YRM100 Module             │
│                                     │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐     │
│  │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │     │
│  └───┘ └───┘ └───┘ └───┘ └───┘     │
│  GND   VCC   TX    RX    EN        │
└─────────────────────────────────────┘
```

| Pin | Name | Connection |
|-----|------|------------|
| 1 | GND | Ground |
| 2 | VCC | 3.3V |
| 3 | TX | ESP32-C6 GPIO5 (UART1_RX) |
| 4 | RX | ESP32-C6 GPIO4 (UART1_TX) |
| 5 | EN | ESP32-C6 GPIO6 |

### Power

| Parameter | Value |
|-----------|-------|
| Input | USB-C |
| Voltage | 5V |
| Estimated Current | 500mA max (during RF transmission) |

### Peripherals Summary

| Component | Interface | Purpose |
|-----------|-----------|---------|
| YRM100 RFID | UART1 | Now Playing detection |
| RGB LED | GPIO (PWM) | Status indication |
| Button | GPIO (input) | User interaction |
| USB-C | USB | Power + serial console |

---

## Development Environment

### Prerequisites

- **ESP-IDF v5.2+** (latest stable recommended)
- **Python 3.8+**
- **Git**
- **USB-C cable** for flashing and debugging

### Setup

```bash
# Clone ESP-IDF
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
git checkout v5.2  # or latest stable
./install.sh esp32c6
source export.sh

# Clone firmware repository
git clone <repository-url> sv-hub-firmware
cd sv-hub-firmware

# Configure and build
idf.py set-target esp32c6
idf.py menuconfig  # Configure options
idf.py build

# Flash to device
idf.py -p /dev/ttyUSB0 flash monitor
```

### Project Structure

```
sv-hub-firmware/
├── CMakeLists.txt
├── sdkconfig.defaults          # Default SDK configuration
├── partitions.csv              # Partition table (OTA support)
├── docs/
│   └── developers_guide.md     # This document
├── main/
│   ├── CMakeLists.txt
│   ├── main.c                  # Entry point
│   ├── app_config.h            # Compile-time configuration
│   └── Kconfig.projbuild       # Menuconfig options
├── components/
│   ├── network/                # Wi-Fi, Thread BR, CoAP
│   │   ├── wifi_manager.c
│   │   ├── thread_br.c
│   │   └── coap_server.c
│   ├── rfid/                   # YRM100 driver and detection logic
│   │   ├── yrm100_driver.c
│   │   ├── rfid_protocol.c
│   │   └── now_playing.c
│   ├── cloud/                  # Supabase client
│   │   ├── supabase_client.c
│   │   └── event_reporter.c
│   ├── provisioning/           # BLE and serial provisioning
│   │   ├── ble_prov.c
│   │   └── serial_prov.c
│   ├── ui/                     # LED and button handling
│   │   ├── led_manager.c
│   │   └── button_handler.c
│   └── config/                 # NVS configuration storage
│       └── config_store.c
└── test/                       # Unit tests
```

### Build Configurations

| Configuration | Description |
|---------------|-------------|
| `debug` | Full logging, assertions enabled, no optimization |
| `release` | Minimal logging, optimized for size and performance |
| `factory` | Includes serial provisioning, used for manufacturing |

---

## Firmware Architecture

### State Machine

The hub operates as a state machine with the following states:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│    ┌──────────┐     ┌──────────────┐     ┌─────────────────┐   │
│    │  BOOT    │────►│ UNPROVISIONED│────►│   PROVISIONING  │   │
│    └──────────┘     └──────────────┘     └────────┬────────┘   │
│                            ▲                      │             │
│                            │                      ▼             │
│    ┌──────────┐     ┌──────┴───────┐     ┌─────────────────┐   │
│    │  ERROR   │◄────│   RUNNING    │◄────│   CONNECTING    │   │
│    └──────────┘     └──────────────┘     └─────────────────┘   │
│         │                  │                                    │
│         │                  ▼                                    │
│         │           ┌──────────────┐                            │
│         └──────────►│FACTORY_RESET │                            │
│                     └──────────────┘                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

| State | Description |
|-------|-------------|
| `BOOT` | Hardware initialization, load config from NVS |
| `UNPROVISIONED` | No Wi-Fi credentials, awaiting provisioning |
| `PROVISIONING` | BLE or serial provisioning in progress |
| `CONNECTING` | Connecting to Wi-Fi, forming Thread network |
| `RUNNING` | Normal operation - all systems active |
| `ERROR` | Recoverable error state, attempting recovery |
| `FACTORY_RESET` | Clearing all config, returning to factory state |

### Event System

Components communicate via an event bus using ESP-IDF's event loop library:

```c
// Event base definitions
ESP_EVENT_DECLARE_BASE(NETWORK_EVENTS);
ESP_EVENT_DECLARE_BASE(RFID_EVENTS);
ESP_EVENT_DECLARE_BASE(CLOUD_EVENTS);
ESP_EVENT_DECLARE_BASE(CRATE_EVENTS);
ESP_EVENT_DECLARE_BASE(UI_EVENTS);

// Example events
typedef enum {
    NETWORK_EVENT_WIFI_CONNECTED,
    NETWORK_EVENT_WIFI_DISCONNECTED,
    NETWORK_EVENT_THREAD_STARTED,
    NETWORK_EVENT_THREAD_DEVICE_JOINED,
    NETWORK_EVENT_THREAD_DEVICE_LEFT,
} network_event_t;

typedef enum {
    RFID_EVENT_TAG_DETECTED,
    RFID_EVENT_TAG_REMOVED,
} rfid_event_t;

typedef enum {
    CRATE_EVENT_INVENTORY_UPDATE,
} crate_event_t;
```

---

## Thread Border Router

### Overview

The hub acts as a Thread Border Router, connecting the Thread mesh network to the IP network. This enables the battery-powered RFID crates to communicate with the cloud through the hub.

### OpenThread Configuration

ESP-IDF includes OpenThread support. Key configuration options:

```
# sdkconfig
CONFIG_OPENTHREAD_ENABLED=y
CONFIG_OPENTHREAD_BORDER_ROUTER=y
CONFIG_OPENTHREAD_RADIO_NATIVE=y
CONFIG_OPENTHREAD_NETWORK_NAME="SaturdayVinyl"
CONFIG_OPENTHREAD_NETWORK_CHANNEL=15
CONFIG_OPENTHREAD_NETWORK_PANID=0x5356
```

### Thread Network Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Network Name | "SaturdayVinyl" | May be configurable per-installation |
| PAN ID | 0x5356 | "SV" in hex |
| Channel | 15 | Default, may auto-select |
| Network Key | Generated | Stored in NVS, generated during provisioning |

### Border Router Responsibilities

1. **Route Advertisement** - Advertise the Thread network prefix to enable IP routing
2. **NAT64** - Translate between Thread (IPv6) and Wi-Fi (IPv4) if needed
3. **DNS-SD** - Service discovery for crates to find the hub
4. **Commissioner** - Allow new crates to join the network (during setup)

### Crate Joining Process

```
1. User initiates "Add Crate" in Saturday mobile app
2. App sends command to hub via Supabase
3. Hub enters Commissioner mode (time-limited)
4. Crate powers on, discovers network via MLE
5. Hub commissions crate with network credentials
6. Crate joins network, announces via CoAP
7. Hub reports new crate to Supabase
8. App shows crate as connected
```

---

## CoAP Protocol (Crate Communication)

### Overview

Crates communicate with the hub using CoAP (Constrained Application Protocol) over Thread. CoAP is a lightweight REST-like protocol designed for constrained IoT devices.

### Why CoAP?

- **Low overhead** - Minimal packet size, essential for battery-powered devices
- **UDP-based** - No connection state to maintain
- **Observe pattern** - Crates can push updates when inventory changes
- **Request/response** - Hub can query crates when needed

### CoAP Endpoints (Hub as Server)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/inventory` | Crate reports current inventory (list of EPCs) |
| POST | `/heartbeat` | Crate periodic health check |
| GET | `/config` | Crate requests its configuration |
| POST | `/event` | Crate reports an event (error, low battery, etc.) |

### Message Formats

#### Inventory Update (Crate → Hub)

```json
{
  "crate_id": "CRATE-001",
  "timestamp": 1704067200,
  "epcs": [
    "5356A1B2C3D4E5F67890ABCD",
    "535612345678901234567890",
    "5356FEDCBA9876543210FEDC"
  ],
  "delta": {
    "added": ["5356A1B2C3D4E5F67890ABCD"],
    "removed": ["5356OLDRECORD123456789A"]
  }
}
```

#### Heartbeat (Crate → Hub)

```json
{
  "crate_id": "CRATE-001",
  "battery_pct": 85,
  "tag_count": 42,
  "rssi": -65,
  "uptime_sec": 86400
}
```

### CoAP Observe

Crates use CoAP Observe to push inventory updates immediately when records are added or removed, rather than polling. The hub subscribes to each crate's inventory resource.

---

## UHF RFID Module (Now Playing)

### YRM100 Communication Protocol

The hub communicates with the YRM100 module using a binary frame protocol over UART.

#### Frame Format

```
┌────────┬──────┬─────────┬────────┬────────┬────────────┬──────────┬─────┐
│ Header │ Type │ Command │ PL MSB │ PL LSB │ Parameters │ Checksum │ End │
│  0xBB  │ 1B   │   1B    │   1B   │   1B   │  Variable  │    1B    │0x7E │
└────────┴──────┴─────────┴────────┴────────┴────────────┴──────────┴─────┘
```

| Field | Size | Description |
|-------|------|-------------|
| Header | 1 byte | `0xBB` |
| Type | 1 byte | `0x00`=Command, `0x01`=Response, `0x02`=Notice |
| Command | 1 byte | Command code |
| PL MSB | 1 byte | Payload length high byte |
| PL LSB | 1 byte | Payload length low byte |
| Parameters | Variable | Command-specific data |
| Checksum | 1 byte | Sum of Type+Command+PL+Params (low byte) |
| End | 1 byte | `0x7E` |

#### Key Commands

| Command | Code | Description |
|---------|------|-------------|
| GetFirmwareVersion | `0x03` | Get module firmware version |
| SinglePoll | `0x22` | Poll for one tag |
| MultiplePoll | `0x27` | Start continuous polling |
| StopMultiplePoll | `0x28` | Stop continuous polling |
| SetRfPower | `0xB6` | Set RF power level (0-30 dBm) |
| GetRfPower | `0xB7` | Get current RF power |

#### Checksum Calculation

```c
uint8_t calculate_checksum(uint8_t type, uint8_t cmd, uint8_t *params, uint16_t len) {
    uint32_t sum = type + cmd;
    sum += (len >> 8) & 0xFF;  // PL MSB
    sum += len & 0xFF;          // PL LSB
    for (int i = 0; i < len; i++) {
        sum += params[i];
    }
    return sum & 0xFF;
}
```

### EPC Format

Saturday Vinyl tags use a 96-bit EPC with a specific prefix:

```
┌─────────────┬─────────────────────────────────────────┐
│   Prefix    │              Random Data                │
│  (2 bytes)  │              (10 bytes)                 │
├─────────────┼─────────────────────────────────────────┤
│    5356     │    XXXX XXXX XXXX XXXX XXXX             │
│   ("SV")    │    (80 random bits)                     │
└─────────────┴─────────────────────────────────────────┘
```

| Component | Size | Description |
|-----------|------|-------------|
| Prefix | 2 bytes | `0x5356` (ASCII "SV") |
| Random | 10 bytes | Unique identifier |
| **Total** | 12 bytes | 24 hex characters |

#### Validation

```c
bool is_saturday_tag(const uint8_t *epc, size_t len) {
    if (len != 12) return false;
    return (epc[0] == 0x53 && epc[1] == 0x56);  // "SV"
}
```

### Now Playing Detection Logic

#### Detection Parameters (Configurable)

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `poll_interval_ms` | 500 | 100-5000 | Time between RFID polls |
| `rf_power_dbm` | 10 | 0-30 | RF output power |
| `debounce_present_ms` | 1000 | 0-5000 | Time tag must be present to confirm |
| `debounce_absent_ms` | 2000 | 0-10000 | Time tag must be absent to confirm removal |

#### State Machine

```
┌─────────────┐      Tag detected       ┌─────────────────┐
│   IDLE      │────────────────────────►│ TAG_CONFIRMING  │
│ (no tag)    │                         │  (debouncing)   │
└─────────────┘                         └────────┬────────┘
      ▲                                          │
      │          Tag not confirmed               │ Tag confirmed
      │◄─────────────────────────────────────────┤
      │                                          ▼
      │                                 ┌─────────────────┐
      │         Tag removed             │  TAG_PRESENT    │
      │◄────────────────────────────────│ (now playing)   │
      │         (after debounce)        └─────────────────┘
```

#### Events Generated

| Event | Trigger | Data |
|-------|---------|------|
| `TAG_DETECTED` | Tag confirmed present | EPC, RSSI, timestamp |
| `TAG_REMOVED` | Tag confirmed absent | EPC, duration, timestamp |

---

## Cloud Integration (Supabase)

### Overview

The hub communicates with Supabase using the REST API over HTTPS. All data is sent as JSON.

### Authentication

The hub authenticates using a device-specific API key or JWT token provisioned during setup:

```c
// HTTP headers for Supabase requests
"apikey: <SUPABASE_ANON_KEY>"
"Authorization: Bearer <DEVICE_JWT>"
"Content-Type: application/json"
```

### Endpoints

#### Report Now Playing Event

```
POST /rest/v1/now_playing_events
```

```json
{
  "hub_id": "HUB-XXXX",
  "user_id": "uuid",
  "epc": "5356A1B2C3D4E5F67890ABCD",
  "event_type": "placed",
  "rssi": -45,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

#### Report Crate Inventory

```
POST /rest/v1/crate_inventory_events
```

```json
{
  "hub_id": "HUB-XXXX",
  "crate_id": "CRATE-001",
  "epcs": ["5356...", "5356...", "5356..."],
  "added": ["5356..."],
  "removed": ["5356..."],
  "timestamp": "2025-01-15T10:30:00Z"
}
```

#### Hub Heartbeat

```
POST /rest/v1/hub_heartbeats
```

```json
{
  "hub_id": "HUB-XXXX",
  "firmware_version": "1.0.0",
  "wifi_rssi": -55,
  "thread_devices": 3,
  "uptime_sec": 86400,
  "free_heap": 128000,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Offline Handling

If Wi-Fi is unavailable:

1. Events are queued in RAM (limited buffer, ~100 events)
2. Hub continues local operation (Thread BR, RFID detection)
3. When Wi-Fi reconnects, queued events are sent in order
4. If buffer overflows, oldest events are dropped (log warning)

---

## Provisioning

### Overview

The hub supports two provisioning methods:

1. **Factory Provisioning (Serial)** - Used during manufacturing with the Saturday Admin desktop app
2. **Consumer Provisioning (BLE)** - Used by end users with the Saturday mobile app

### Factory Provisioning (Serial)

#### Protocol

Serial provisioning uses a simple JSON-over-UART protocol at 115200 baud.

```
Hub → Host: {"status": "awaiting_provisioning"}
Host → Hub: {"cmd": "provision", "data": {...}}
Hub → Host: {"status": "provisioned", "hub_id": "HUB-XXXX"}
```

#### Provisioning Data

```json
{
  "cmd": "provision",
  "data": {
    "hub_id": "HUB-XXXX",
    "supabase_url": "https://xxx.supabase.co",
    "supabase_anon_key": "eyJ...",
    "device_secret": "xxx"
  }
}
```

#### Factory Provisioning Flow

```
1. Connect hub to computer via USB-C
2. Open Saturday Admin app
3. App detects hub on serial port
4. App generates hub_id and device credentials
5. App registers hub in Supabase
6. App sends provisioning data to hub
7. Hub stores data in NVS
8. Hub reboots into UNPROVISIONED state (awaiting Wi-Fi)
```

### Consumer Provisioning (BLE)

#### BLE Service

| Service | UUID |
|---------|------|
| Saturday Provisioning | `5356xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

| Characteristic | UUID | Properties | Description |
|----------------|------|------------|-------------|
| Status | `...0001` | Read, Notify | Current provisioning state |
| WiFi SSID | `...0002` | Write | Wi-Fi network name |
| WiFi Password | `...0003` | Write | Wi-Fi password |
| User Token | `...0004` | Write | User authentication token |
| Command | `...0005` | Write | Control commands |

#### Consumer Provisioning Flow

```
1. User opens Saturday app, selects "Add Hub"
2. App scans for BLE devices with Saturday service
3. User selects their hub
4. App connects via BLE
5. App sends Wi-Fi credentials
6. App sends user authentication token
7. Hub attempts Wi-Fi connection
8. Hub reports success/failure via BLE
9. Hub registers itself to user's account via Supabase
10. App shows hub as connected
```

---

## User Interface (LED & Button)

### RGB LED States

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| Booting | White | Pulsing | Hardware initialization |
| Unprovisioned | Blue | Slow blink (1Hz) | Awaiting BLE provisioning |
| Provisioning | Blue | Fast blink (2Hz) | BLE provisioning in progress |
| Connecting | Yellow | Pulsing | Connecting to Wi-Fi |
| Thread Forming | Cyan | Pulsing | Thread network starting |
| Running (Idle) | Green | Solid dim | Normal operation, no tag |
| Tag Detected | Green | Brief flash | Record placed on turntable |
| Wi-Fi Lost | Orange | Slow blink | Wi-Fi disconnected, reconnecting |
| Error | Red | Slow blink | Recoverable error |
| Factory Reset | Red | Fast blink | Clearing configuration |
| Firmware Update | Magenta | Pulsing | OTA update in progress |

### LED Implementation

The LED uses PWM for smooth transitions and brightness control:

```c
typedef struct {
    uint8_t r, g, b;      // Color (0-255)
    uint8_t brightness;    // Overall brightness (0-255)
    led_pattern_t pattern; // Solid, blink, pulse
    uint16_t period_ms;    // Pattern period
} led_state_t;
```

### Button Actions

| Action | Duration | Function |
|--------|----------|----------|
| Short press | <500ms | Reserved for future use |
| Long press | 3-5 seconds | Enter BLE provisioning mode |
| Very long press | >10 seconds | Factory reset |

### Button Implementation

```c
typedef enum {
    BUTTON_EVENT_SHORT_PRESS,
    BUTTON_EVENT_LONG_PRESS,
    BUTTON_EVENT_FACTORY_RESET,
} button_event_t;
```

The button uses a state machine with debouncing (50ms) and timing thresholds.

---

## Configuration & Storage

### NVS (Non-Volatile Storage)

Configuration is stored in the ESP32's NVS (Non-Volatile Storage) flash partition.

#### Namespace: `sv_config`

| Key | Type | Description |
|-----|------|-------------|
| `hub_id` | string | Unique hub identifier |
| `provisioned` | bool | Whether factory provisioning is complete |
| `wifi_ssid` | string | Wi-Fi network name |
| `wifi_pass` | string | Wi-Fi password (encrypted) |
| `user_id` | string | Associated user's Supabase UUID |
| `supabase_url` | string | Supabase project URL |
| `supabase_key` | string | Supabase anon key |
| `device_secret` | string | Device authentication secret |

#### Namespace: `sv_thread`

| Key | Type | Description |
|-----|------|-------------|
| `network_key` | blob | Thread network master key |
| `network_name` | string | Thread network name |
| `pan_id` | uint16 | Thread PAN ID |
| `channel` | uint8 | Thread radio channel |

#### Namespace: `sv_rfid`

| Key | Type | Description |
|-----|------|-------------|
| `poll_interval` | uint16 | Polling interval in ms |
| `rf_power` | uint8 | RF power in dBm |
| `debounce_present` | uint16 | Present debounce time in ms |
| `debounce_absent` | uint16 | Absent debounce time in ms |

### Default Values

```c
#define DEFAULT_POLL_INTERVAL_MS    500
#define DEFAULT_RF_POWER_DBM        10
#define DEFAULT_DEBOUNCE_PRESENT_MS 1000
#define DEFAULT_DEBOUNCE_ABSENT_MS  2000
```

---

## Error Handling

### Error Categories

| Category | Examples | Recovery |
|----------|----------|----------|
| Network | Wi-Fi disconnect, DNS failure | Auto-retry with backoff |
| RFID | Module not responding, CRC error | Reset module, continue |
| Cloud | API timeout, auth failure | Queue events, retry |
| Thread | Network partition, device loss | Auto-reform network |
| Hardware | NVS corruption, low memory | Log, attempt recovery |

### Logging

The firmware uses ESP-IDF's logging system with component-specific tags:

```c
ESP_LOGI("WIFI", "Connected to %s", ssid);
ESP_LOGW("RFID", "Tag CRC mismatch, retrying");
ESP_LOGE("CLOUD", "Supabase request failed: %d", status);
```

Log levels:
- `ESP_LOGE` - Errors (always logged)
- `ESP_LOGW` - Warnings
- `ESP_LOGI` - Info (default level)
- `ESP_LOGD` - Debug (disabled in release)
- `ESP_LOGV` - Verbose (disabled in release)

### Watchdog

A task watchdog monitors critical tasks and reboots if they become unresponsive:

```c
esp_task_wdt_config_t wdt_config = {
    .timeout_ms = 30000,  // 30 second timeout
    .trigger_panic = true,
};
```

---

## Testing

### Unit Tests

Unit tests are located in `test/` and use the Unity framework (included with ESP-IDF).

```bash
# Run tests on host (where possible)
idf.py -T test build
```

### Hardware-in-the-Loop Testing

For testing with actual hardware:

1. **RFID Testing** - Use test tags with known EPCs
2. **Thread Testing** - Use Thread development boards as mock crates
3. **Wi-Fi Testing** - Test with various network conditions
4. **Provisioning Testing** - Test both BLE and serial flows

### Test Tags

| EPC | Purpose |
|-----|---------|
| `535600000000000000000001` | Test tag 1 |
| `535600000000000000000002` | Test tag 2 |
| `E20000000000000000000001` | Non-Saturday tag (for filtering tests) |

---

## Versioning & Releases

### Semantic Versioning

The project follows [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH

- MAJOR: Incompatible API/protocol changes
- MINOR: New functionality, backwards compatible
- PATCH: Bug fixes, backwards compatible
```

### Version Location

```c
// main/version.h
#define FIRMWARE_VERSION_MAJOR 0
#define FIRMWARE_VERSION_MINOR 1
#define FIRMWARE_VERSION_PATCH 0
#define FIRMWARE_VERSION "0.1.0"
```

### Release Process

1. Update version in `version.h`
2. Update CHANGELOG.md
3. Tag release in git: `git tag v0.1.0`
4. Build release firmware: `idf.py build`
5. Generate OTA image
6. Upload to Supabase storage for OTA distribution

---

## Reference

### Quick Reference: RFID Commands

| Action | Frame (hex) |
|--------|-------------|
| Start polling | `BB 00 27 00 03 22 00 00 4C 7E` |
| Stop polling | `BB 00 28 00 00 28 7E` |
| Get RF power | `BB 00 B7 00 00 B7 7E` |
| Set RF power (10 dBm) | `BB 00 B6 00 02 05 0A BD 7E` |

### Quick Reference: Error Codes

| Code | Name | Description |
|------|------|-------------|
| `0x00` | Success | Operation completed |
| `0x15` | TagNotFound | No tag in field |
| `0x16` | ReadFailed | Read operation failed |
| `0x17` | WriteFailed | Write operation failed |

### External Resources

- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/latest/)
- [ESP32-C6 Technical Reference](https://www.espressif.com/sites/default/files/documentation/esp32-c6_technical_reference_manual_en.pdf)
- [OpenThread Border Router](https://openthread.io/guides/border-router)
- [CoAP RFC 7252](https://datatracker.ietf.org/doc/html/rfc7252)
- [Supabase Documentation](https://supabase.com/docs)

### Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2025-01-XX | Initial | Initial draft |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
