# Saturday Vinyl Hub Firmware - Developer Guide

**Project:** sv-hub-firmware
**Version:** 0.4.0
**Status:** Pre-development
**Audience:** Internal Saturday Vinyl engineers and AI agents

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Hardware Platform](#hardware-platform)
4. [Development Environment](#development-environment)
5. [Inter-Processor Communication](#inter-processor-communication)
6. [Firmware Architecture (S3 Master)](#firmware-architecture-s3-master)
7. [Thread Border Router (H2 Slave)](#thread-border-router-h2-slave)
8. [CoAP Protocol (Crate Communication)](#coap-protocol-crate-communication)
9. [UHF RFID Module (Now Playing)](#uhf-rfid-module-now-playing)
10. [Cloud Integration (Supabase)](#cloud-integration-supabase)
11. [Provisioning](#provisioning)
12. [User Interface (LED & Button)](#user-interface-led--button)
13. [Configuration & Storage](#configuration--storage)
14. [Error Handling](#error-handling)
15. [Testing](#testing)
16. [Versioning & Releases](#versioning--releases)
17. [Reference](#reference)

---

## Overview

### What is the Saturday Vinyl Hub?

The Saturday Vinyl Hub is an embedded device that serves as the central connectivity point for Saturday Vinyl's record tracking ecosystem. It performs two primary functions:

1. **Thread Border Router** - Bridges the Thread mesh network (connecting battery-powered RFID crates) to the IP network (Wi-Fi) and ultimately to the Saturday cloud (Supabase).

2. **Now Playing Detection** - Uses an integrated UHF RFID reader to detect which record is currently on the user's turntable and reports this to the cloud for "Now Playing" experiences in the Saturday mobile app.

### Two-SoC Architecture

The hub uses a **dual-processor architecture** to achieve reliable WiFi and Thread coexistence:

| SoC | Role | Responsibilities |
|-----|------|------------------|
| **ESP32-S3** | Master | WiFi, BLE provisioning, RFID, Cloud sync, USB, H2 management |
| **ESP32-H2** | Slave | Thread Border Router, CoAP server for crates |

**Why Two Chips?**

WiFi and Thread (802.15.4) operate in overlapping 2.4 GHz spectrum. Single-chip solutions like the ESP32-C6 use time-division multiplexing between radios, which causes:
- TLS handshake failures during cloud sync (packet loss from radio switching)
- Thread mesh instability during WiFi operations
- Unreliable connectivity requiring complex retry logic

The dual-SoC approach provides **dedicated radios** - WiFi operates uninterrupted on the S3 while Thread runs continuously on the H2. The chips communicate via a simple UART protocol, avoiding all radio contention issues.

### Product Context

Saturday Vinyl manufactures furniture with embedded technology for vinyl record enthusiasts:

- **RFID Crates** - Battery-powered record storage crates with built-in UHF RFID readers that track up to 75 records each. These communicate over Thread to minimize power consumption.
- **RFID Tags** - Applied to record sleeves, each containing a unique 96-bit EPC identifier with the Saturday Vinyl prefix (`5356` = "SV" in ASCII).
- **Saturday Mobile App** - Consumer-facing Flutter app for iOS and Android that displays the user's collection, now playing status, and listening history.
- **Saturday Admin App** - Internal Flutter desktop app for tag provisioning, device configuration, and diagnostics.

### Data Flow

```
┌─────────────────┐     Thread/CoAP      ┌───────────────┐
│   RFID Crate    │◄────────────────────►│               │
│  (up to 75 tags)│                      │   ESP32-H2    │
└─────────────────┘                      │  (Thread BR)  │
                                         │               │
┌─────────────────┐     Thread/CoAP      │               │
│   RFID Crate    │◄────────────────────►│               │
│  (up to 75 tags)│                      └───────┬───────┘
└─────────────────┘                              │
                                            UART │ Protocol
        ...                                      │
                                         ┌───────┴───────┐
┌─────────────────┐                      │               │
│    Turntable    │     UHF RFID         │   ESP32-S3    │     Wi-Fi/HTTPS
│  (record + tag) │◄────────────────────►│   (Master)    │◄─────────────────►  Supabase
└─────────────────┘     (local reader)   │               │
                                         │               │
                                         └───────────────┘
```

---

## System Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Saturday Hub - Dual SoC Architecture                    │
├────────────────────────────────────────┬────────────────────────────────────────┤
│           ESP32-S3 (Master)            │           ESP32-H2 (Slave)             │
│                                        │                                        │
│  ┌─────────────┐  ┌─────────────────┐  │  ┌─────────────┐  ┌─────────────────┐  │
│  │    WiFi     │  │   Provisioning  │  │  │  OpenThread │  │    CoAP Server  │  │
│  │   Manager   │  │     Manager     │  │  │   Border    │  │   (for crates)  │  │
│  │             │  │                 │  │  │   Router    │  │                 │  │
│  │ - STA mode  │  │ - BLE (consumer)│  │  │             │  │ - /inventory    │  │
│  │ - HTTP/TLS  │  │ - Serial (factory) │  │ - Forming   │  │ - /heartbeat    │  │
│  │ - DNS       │  │ - Config store  │  │  │ - Routing   │  │ - /event        │  │
│  └──────┬──────┘  └──────┬──────────┘  │  │ - Commission│  └────────┬────────┘  │
│         │                │             │  └──────┬──────┘           │           │
│  ┌──────┴────────────────┴──────────┐  │         │                  │           │
│  │        Cloud Client (Supabase)   │  │  ┌──────┴──────────────────┴─────────┐ │
│  │  - REST API  - Events  - OTA     │  │  │         Event Queue (to S3)       │ │
│  └──────┬───────────────────────────┘  │  │  - Inventory updates              │ │
│         │                              │  │  - Crate heartbeats               │ │
│  ┌──────┴──────┐  ┌─────────────────┐  │  │  - Device join/leave              │ │
│  │    RFID     │  │       UI        │  │  └────────────────┬──────────────────┘ │
│  │   Manager   │  │    Manager      │  │                   │                    │
│  │  (YRM100)   │  │  (LED/Button)   │  │                   │                    │
│  └─────────────┘  └─────────────────┘  │                   │                    │
│                                        │                   │                    │
├──────────────────┬─────────────────────┼───────────────────┴────────────────────┤
│      UART TX     │      UART RX        │                  UART                  │
│     (to H2)      │    (from H2)        │              (to/from S3)              │
├──────────────────┴─────────────────────┼────────────────────────────────────────┤
│              ESP-IDF / FreeRTOS        │           ESP-IDF / FreeRTOS           │
├────────────────────────────────────────┼────────────────────────────────────────┤
│  ESP32-S3 Hardware                     │  ESP32-H2 Hardware                     │
│  (Wi-Fi 4 | BLE 5.0 | USB | UART)      │  (Thread/802.15.4 | UART)              │
└────────────────────────────────────────┴────────────────────────────────────────┘
```

### Task Model (ESP32-S3 Master)

| Task | Priority | Stack Size | Description |
|------|----------|------------|-------------|
| `wifi_task` | High | 6KB | WiFi connection management |
| `cloud_task` | High | 8KB | Supabase API communication |
| `h2_comm_task` | High | 4KB | UART communication with H2 |
| `rfid_task` | Medium | 4KB | RFID polling and tag detection |
| `ble_prov_task` | Medium | 4KB | BLE provisioning (when active) |
| `ui_task` | Low | 2KB | LED patterns and button handling |
| `main_task` | Medium | 4KB | Coordination and state machine |

### Task Model (ESP32-H2 Slave)

| Task | Priority | Stack Size | Description |
|------|----------|------------|-------------|
| `ot_task` | High | 6KB | OpenThread stack |
| `coap_task` | High | 4KB | CoAP server for crate communication |
| `s3_comm_task` | Medium | 4KB | UART communication with S3 |

---

## Hardware Platform

### ESP32-S3 (Master) Microcontroller

The ESP32-S3 handles all WiFi, BLE, and peripheral management.

| Feature | Specification |
|---------|---------------|
| CPU | Dual-core Xtensa LX7, 240 MHz |
| RAM | 512 KB SRAM + 8MB PSRAM (module) |
| Flash | 8 MB (typical module) |
| Wi-Fi | 802.11 b/g/n (Wi-Fi 4), 2.4 GHz |
| Bluetooth | BLE 5.0 |
| USB | USB OTG (native USB) |
| UART | 3x UART controllers |
| GPIO | 45 programmable GPIOs |
| Operating Voltage | 3.3V |

### ESP32-H2 (Slave) Microcontroller

The ESP32-H2 provides dedicated Thread/802.15.4 radio operation.

| Feature | Specification |
|---------|---------------|
| CPU | 32-bit RISC-V, 96 MHz |
| RAM | 320 KB SRAM |
| Flash | 4 MB (typical module) |
| Thread | 802.15.4 radio, OpenThread stack |
| Bluetooth | BLE 5.0 (unused) |
| UART | 2x UART controllers |
| GPIO | 22 programmable GPIOs |
| Operating Voltage | 3.3V |

### Pin Assignments (ESP32-S3)

| GPIO | Function | Description |
|------|----------|-------------|
| GPIO43 | UART0_TX | Debug console TX (USB-CDC) |
| GPIO44 | UART0_RX | Debug console RX (USB-CDC) |
| GPIO17 | UART1_TX | RFID module RX (hub transmits) |
| GPIO18 | UART1_RX | RFID module TX (hub receives) |
| GPIO15 | UART2_TX | H2 RX (S3 transmits to H2) |
| GPIO16 | UART2_RX | H2 TX (S3 receives from H2) |
| GPIO5 | RFID_EN | RFID module enable (active high) |
| GPIO6 | H2_EN | H2 enable/reset (active high) |
| GPIO7 | H2_BOOT | H2 boot mode select (high=normal, low=download) |
| GPIO48 | WS2812_DATA | Addressable RGB LED (RMT) |
| GPIO0 | BUTTON | Multi-purpose button (active low, internal pull-up) |
| GPIO19 | USB_D- | USB-C data minus (native) |
| GPIO20 | USB_D+ | USB-C data plus (native) |

### Pin Assignments (ESP32-H2)

| GPIO | Function | Description |
|------|----------|-------------|
| GPIO24 | UART0_TX | S3 RX (H2 transmits to S3) |
| GPIO23 | UART0_RX | S3 TX (H2 receives from S3) |
| GPIO4 | BOOT_MODE | Boot mode (active low for download) |
| GPIO5 | STATUS_LED | Optional status LED (active high) |

### Inter-Processor Connection

```
┌──────────────────┐                    ┌──────────────────┐
│    ESP32-S3      │                    │    ESP32-H2      │
│                  │                    │                  │
│  GPIO15 (TX) ────┼────────────────────┼──► GPIO23 (RX)   │
│  GPIO16 (RX) ◄───┼────────────────────┼──── GPIO24 (TX)  │
│                  │                    │                  │
│  GPIO6 (H2_EN) ──┼────────────────────┼──► EN (reset)    │
│  GPIO7 (H2_BOOT)─┼────────────────────┼──► GPIO4 (boot)  │
│                  │                    │                  │
│  3.3V ───────────┼────────────────────┼──► 3.3V          │
│  GND ────────────┼────────────────────┼──► GND           │
└──────────────────┘                    └──────────────────┘
```

### YRM100 UHF RFID Module

The YRM100 module handles all RFID operations for "Now Playing" detection. Connected to ESP32-S3.

#### Module Variants

| Variant | Manufacturer | Antenna Gain | Notes |
|---------|--------------|--------------|-------|
| **YRM100 (SBComponents)** | SBComponents | 3 dBi | Larger antenna, original module |
| **YRM100 (Generic)** | AliExpress generic | 2 dBi | Smaller antenna, compact form factor |

#### Common Specifications

| Parameter | Value |
|-----------|-------|
| Frequency | UHF 840-960 MHz |
| Protocol | ISO 18000-6C / EPC Gen2 |
| Interface | UART (3.3V TTL) |
| Baud Rate | 115200 (8N1) |
| RF Power | **15-26 dBm** (minimum 15 dBm) |
| Default Power | 15 dBm |
| Supply Voltage | 3.5V - 5V |
| Enable Pin | Active high (min 1.5V) |
| Working Current | 180mA @ 3.5V (26 dBm), 110mA @ 3.5V (18 dBm) |

### Power

| Parameter | Value |
|-----------|-------|
| Input | USB-C |
| Voltage | 5V |
| Estimated Current | 600mA max (S3 + H2 + RFID during transmission) |

### Peripherals Summary

| Component | Interface | Connected To | Purpose |
|-----------|-----------|--------------|---------|
| YRM100 RFID | UART1 | ESP32-S3 | Now Playing detection |
| ESP32-H2 | UART2 | ESP32-S3 | Thread BR communication |
| WS2812 RGB LED | GPIO48 (RMT) | ESP32-S3 | Status indication |
| Button | GPIO0 (input) | ESP32-S3 | User interaction |
| USB-C | USB OTG | ESP32-S3 | Power + serial console + flashing |

---

## Development Environment

### Prerequisites

- **ESP-IDF v5.2+** (latest stable recommended)
- **Python 3.8+**
- **Git**
- **USB-C cable** for flashing and debugging

### Repository Structure

The hub firmware is organized as two separate ESP-IDF projects:

```
sv-hub-firmware/
├── s3-master/                      # ESP32-S3 master firmware
│   ├── CMakeLists.txt
│   ├── sdkconfig.defaults
│   ├── partitions.csv
│   ├── main/
│   │   ├── main.c
│   │   ├── app_config.h
│   │   └── Kconfig.projbuild
│   └── components/
│       ├── network/                # WiFi management
│       ├── rfid/                   # YRM100 driver
│       ├── cloud/                  # Supabase client
│       ├── h2_comm/                # H2 UART protocol
│       ├── h2_flasher/             # H2 firmware update
│       ├── provisioning/           # BLE provisioning
│       ├── ui/                     # LED and button
│       └── config/                 # NVS configuration
│
├── h2-thread-br/                   # ESP32-H2 slave firmware
│   ├── CMakeLists.txt
│   ├── sdkconfig.defaults
│   ├── partitions.csv
│   ├── main/
│   │   ├── main.c
│   │   └── app_config.h
│   └── components/
│       ├── thread_br/              # OpenThread Border Router
│       ├── coap_server/            # CoAP server for crates
│       └── s3_comm/                # S3 UART protocol
│
├── shared/                         # Shared definitions
│   ├── protocol/                   # UART protocol definitions
│   │   └── s3_h2_protocol.h
│   └── common/                     # Common types
│
├── tools/
│   └── flash_both.py               # Script to flash both chips
│
└── docs/
    ├── developers_guide.md         # This document
    └── implementation_plan.md      # Implementation roadmap
```

### Setup

```bash
# Clone ESP-IDF
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf
git checkout v5.2  # or latest stable
./install.sh esp32s3 esp32h2
source export.sh

# Clone firmware repository
git clone <repository-url> sv-hub-firmware
cd sv-hub-firmware

# Build S3 Master firmware
cd s3-master
idf.py set-target esp32s3
idf.py build

# Build H2 Slave firmware
cd ../h2-thread-br
idf.py set-target esp32h2
idf.py build
```

### Flashing

#### Single USB Flashing (via S3)

The S3 master can flash the H2 slave using `esp-serial-flasher`. Connect USB to the S3:

```bash
# Flash S3 directly
cd s3-master
idf.py -p /dev/ttyUSB0 flash

# Flash H2 via S3 (uses esp-serial-flasher)
# S3 puts H2 into download mode (GPIO7 low, GPIO6 toggle)
# S3 forwards flash data from USB to H2 via UART2
cd ../h2-thread-br
python ../tools/flash_h2_via_s3.py -p /dev/ttyUSB0 build/h2-thread-br.bin
```

#### Direct Flashing (Development)

For development, you can flash each chip directly:

```bash
# Flash S3 (connect USB to S3)
cd s3-master
idf.py -p /dev/ttyUSB0 flash monitor

# Flash H2 (connect USB to H2 directly)
cd h2-thread-br
idf.py -p /dev/ttyUSB1 flash monitor
```

### Build Configurations

| Configuration | Description |
|---------------|-------------|
| `debug` | Full logging, assertions enabled, no optimization |
| `release` | Minimal logging, optimized for size and performance |
| `factory` | Includes serial provisioning, used for manufacturing |

---

## Inter-Processor Communication

### Overview

The ESP32-S3 and ESP32-H2 communicate via a simple UART protocol. The S3 is the master - it initiates most requests. The H2 pushes events (crate joins, inventory updates) asynchronously.

### Physical Layer

| Parameter | Value |
|-----------|-------|
| Baud Rate | 115200 |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Flow Control | None |

### Frame Format

```
┌────────┬──────┬────────┬────────────┬──────────┬─────┐
│ Header │ Type │ Length │  Payload   │ Checksum │ End │
│  0xAA  │  1B  │   2B   │  Variable  │    2B    │0x55 │
└────────┴──────┴────────┴────────────┴──────────┴─────┘
```

| Field | Size | Description |
|-------|------|-------------|
| Header | 1 byte | `0xAA` start marker |
| Type | 1 byte | Message type (see below) |
| Length | 2 bytes | Payload length (big-endian) |
| Payload | Variable | Message-specific data (JSON or binary) |
| Checksum | 2 bytes | CRC-16 of Type+Length+Payload |
| End | 1 byte | `0x55` end marker |

### Message Types

#### S3 → H2 (Commands)

| Type | Name | Description |
|------|------|-------------|
| `0x01` | PING | Health check |
| `0x02` | GET_STATUS | Request Thread BR status |
| `0x03` | GET_CREDENTIALS | Request Thread network credentials |
| `0x04` | SET_CREDENTIALS | Set Thread network credentials |
| `0x05` | START_THREAD | Start Thread BR |
| `0x06` | STOP_THREAD | Stop Thread BR |
| `0x07` | ENABLE_JOINING | Enable commissioner mode |
| `0x08` | DISABLE_JOINING | Disable commissioner mode |
| `0x10` | ENTER_BOOTLOADER | Enter bootloader for firmware update |

#### H2 → S3 (Responses)

| Type | Name | Description |
|------|------|-------------|
| `0x81` | PONG | Response to PING |
| `0x82` | STATUS | Thread BR status response |
| `0x83` | CREDENTIALS | Thread network credentials |
| `0x84` | ACK | Command acknowledged |
| `0x85` | NAK | Command failed |

#### H2 → S3 (Events - Async)

| Type | Name | Description |
|------|------|-------------|
| `0xE0` | CRATE_JOINED | A crate joined the Thread network |
| `0xE1` | CRATE_LEFT | A crate left the Thread network |
| `0xE2` | INVENTORY_UPDATE | Crate reported inventory change |
| `0xE3` | CRATE_HEARTBEAT | Crate periodic heartbeat |
| `0xE4` | THREAD_STATE_CHANGE | Thread BR state changed |

### Payload Formats

#### GET_STATUS Response (0x82)

```json
{
  "state": "leader",
  "pan_id": 21334,
  "channel": 15,
  "network_name": "SaturdayVinyl",
  "device_count": 3,
  "rloc16": 1024
}
```

#### CREDENTIALS Response (0x83)

```json
{
  "network_name": "SaturdayVinyl",
  "pan_id": 21334,
  "channel": 15,
  "network_key": "0123456789abcdef0123456789abcdef",
  "extended_pan_id": "0123456789abcdef"
}
```

#### INVENTORY_UPDATE Event (0xE2)

```json
{
  "crate_id": "CRATE-001",
  "rloc16": 2048,
  "timestamp": 1704067200,
  "epcs": ["5356...", "5356..."],
  "added": ["5356..."],
  "removed": ["5356..."]
}
```

#### CRATE_HEARTBEAT Event (0xE3)

```json
{
  "crate_id": "CRATE-001",
  "rloc16": 2048,
  "battery_pct": 85,
  "tag_count": 42,
  "rssi": -65
}
```

### Flow Control

- S3 waits for response/ACK before sending next command (timeout: 1s)
- H2 can send events at any time (async)
- S3 must handle events even while waiting for command response

---

## Firmware Architecture (S3 Master)

### State Machine

The S3 master operates as a state machine:

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
| `BOOT` | Hardware init, check H2, load config from NVS |
| `UNPROVISIONED` | No Wi-Fi credentials, awaiting provisioning |
| `PROVISIONING` | BLE or serial provisioning in progress |
| `CONNECTING` | Connecting to Wi-Fi, verifying H2 Thread network |
| `RUNNING` | Normal operation - all systems active |
| `ERROR` | Recoverable error state, attempting recovery |
| `FACTORY_RESET` | Clearing all config, returning to factory state |

### Boot Sequence

```
1. ESP32-S3 boots
2. Initialize peripherals (UART, GPIO, LED)
3. Assert H2_EN to start ESP32-H2
4. Wait for H2 PONG (health check)
5. Load config from NVS
6. If provisioned:
   a. Connect to Wi-Fi
   b. Verify H2 Thread network running
   c. Enter RUNNING state
7. If not provisioned:
   a. Start BLE advertising
   b. Enter UNPROVISIONED state
```

### Event System

Components communicate via ESP-IDF's event loop:

```c
// Event base definitions
ESP_EVENT_DECLARE_BASE(WIFI_EVENTS);
ESP_EVENT_DECLARE_BASE(RFID_EVENTS);
ESP_EVENT_DECLARE_BASE(CLOUD_EVENTS);
ESP_EVENT_DECLARE_BASE(H2_EVENTS);      // Events from H2
ESP_EVENT_DECLARE_BASE(UI_EVENTS);

// H2 events (received via UART)
typedef enum {
    H2_EVENT_CONNECTED,           // H2 responding to PING
    H2_EVENT_DISCONNECTED,        // H2 not responding
    H2_EVENT_THREAD_STARTED,      // Thread BR started
    H2_EVENT_CRATE_JOINED,        // Crate joined network
    H2_EVENT_CRATE_LEFT,          // Crate left network
    H2_EVENT_INVENTORY_UPDATE,    // Crate inventory changed
    H2_EVENT_CRATE_HEARTBEAT,     // Crate periodic heartbeat
} h2_event_t;
```

---

## Thread Border Router (H2 Slave)

### Overview

The ESP32-H2 runs a dedicated OpenThread Border Router. It operates autonomously, receiving commands from the S3 master via UART and pushing events asynchronously.

### OpenThread Configuration

```
# sdkconfig (h2-thread-br)
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
| Network Key | Generated | Stored in H2 NVS, shared with S3 |

### H2 State Machine

```
┌─────────────┐     UART connected     ┌─────────────────┐
│   BOOT      │───────────────────────►│    IDLE         │
│             │                        │ (waiting cmds)  │
└─────────────┘                        └────────┬────────┘
                                                │
                               START_THREAD cmd │
                                                ▼
                                       ┌─────────────────┐
                                       │   ATTACHING     │
                                       │ (forming net)   │
                                       └────────┬────────┘
                                                │
                                     Attached   │
                                                ▼
                                       ┌─────────────────┐
                                       │    RUNNING      │
                                       │ (BR active)     │
                                       └─────────────────┘
```

### Border Router Responsibilities

1. **Network Formation** - Form or join Thread network on START_THREAD
2. **Route Advertisement** - Advertise Thread prefix for IP routing
3. **CoAP Server** - Handle crate communication (inventory, heartbeats)
4. **Event Forwarding** - Push crate events to S3 via UART
5. **Commissioner** - Allow new crates to join when ENABLE_JOINING received

### Crate Joining Process

```
1. User initiates "Add Crate" in Saturday mobile app
2. App sends command to hub via Supabase
3. S3 receives command, sends ENABLE_JOINING to H2
4. H2 enters Commissioner mode (time-limited)
5. Crate powers on, discovers network via MLE
6. H2 commissions crate with network credentials
7. Crate joins network, announces via CoAP to H2
8. H2 sends CRATE_JOINED event to S3 via UART
9. S3 reports new crate to Supabase
10. App shows crate as connected
```

---

## CoAP Protocol (Crate Communication)

### Overview

Crates communicate with the H2 (Thread BR) using CoAP over Thread. The H2 forwards relevant events to the S3 master via UART.

### Why CoAP?

- **Low overhead** - Minimal packet size, essential for battery-powered devices
- **UDP-based** - No connection state to maintain
- **Observe pattern** - Crates can push updates when inventory changes

### CoAP Endpoints (H2 as Server)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/inventory` | Crate reports current inventory (list of EPCs) |
| POST | `/heartbeat` | Crate periodic health check |
| GET | `/config` | Crate requests its configuration |
| POST | `/event` | Crate reports an event (error, low battery, etc.) |

### Message Flow

```
┌─────────┐    CoAP/Thread    ┌─────────┐    UART    ┌─────────┐    WiFi/HTTPS    ┌──────────┐
│  Crate  │ ─────────────────►│  H2     │ ──────────►│  S3     │ ─────────────────►│ Supabase │
│         │  POST /inventory  │         │  INV_UPD  │         │  POST /events     │          │
└─────────┘                   └─────────┘            └─────────┘                   └──────────┘
```

---

## UHF RFID Module (Now Playing)

### Overview

The RFID module is connected directly to the ESP32-S3 master. Operation is unchanged from the single-SoC design - the S3 handles all RFID polling and detection.

### YRM100 Communication Protocol

The S3 communicates with the YRM100 module using a binary frame protocol over UART1.

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
| SetRfPower | `0xB6` | Set RF power level (15-26 dBm) |
| GetRfPower | `0xB7` | Get current RF power |

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

### Now Playing Detection Logic

Same as before - handled entirely by S3. Events are reported to Supabase via WiFi (no Thread involvement).

---

## Cloud Integration (Supabase)

### Overview

The S3 master communicates with Supabase using the REST API over HTTPS/WiFi. With dedicated WiFi radio (no Thread contention), connections are reliable without retry logic.

### Event Sources

| Event | Source | Path to Cloud |
|-------|--------|---------------|
| Now Playing | S3 (RFID) | S3 → WiFi → Supabase |
| Crate Inventory | H2 (Thread) | Crate → H2 → UART → S3 → WiFi → Supabase |
| Crate Heartbeat | H2 (Thread) | Crate → H2 → UART → S3 → WiFi → Supabase |
| Hub Heartbeat | S3 | S3 → WiFi → Supabase |

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
  "h2_status": "running",
  "thread_devices": 3,
  "uptime_sec": 86400,
  "free_heap": 128000,
  "timestamp": "2025-01-15T10:30:00Z"
}
```

### Offline Handling

If WiFi is unavailable:

1. Events are queued in S3 RAM (limited buffer, ~100 events)
2. H2 continues Thread BR operation (crates still work)
3. S3 continues RFID operation (Now Playing queued)
4. When WiFi reconnects, queued events are sent in order

---

## Provisioning

### Overview

The hub supports two provisioning methods, both handled by the S3 master:

1. **Service Mode (Factory Provisioning)** - Used during manufacturing with Saturday Admin app
2. **Consumer Provisioning (BLE)** - Used by end users with Saturday mobile app

### Service Mode (Factory Provisioning)

Service Mode provides a standardized USB serial interface for factory provisioning, device testing, diagnostics, and servicing. It is used with the Saturday Admin desktop app.

**Full Protocol Specification:** See [service_mode_protocol.md](service_mode_protocol.md)

#### Service Mode Entry

| Device State | Entry Method |
|--------------|--------------|
| Fresh (no unit_id) | Auto-enters service mode on boot |
| Provisioned | 10-second window at boot to receive `enter_service_mode` command |

#### Key Commands

| Command | Description |
|---------|-------------|
| `get_status` | Device status including Thread credentials from H2 |
| `get_manifest` | Device capabilities for Admin app UI |
| `provision` | Store unit_id and cloud credentials |
| `test_wifi` | Test WiFi connectivity |
| `test_rfid` | Test RFID module |
| `test_thread` | Query H2 for Thread network status |
| `test_cloud` | Test Supabase connectivity |
| `test_all` | Run all supported tests |
| `customer_reset` | Clear user data, preserve factory config |
| `factory_reset` | Full wipe, returns to fresh state |

#### Thread Credential Retrieval

Service Mode retrieves Thread credentials from the H2 via the S3↔H2 UART protocol. These credentials are included in `get_status` response and must be uploaded to Supabase during factory provisioning so the mobile app can provision crates to join the Thread network.

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

### Consumer Provisioning (BLE)

The S3 handles all BLE provisioning. Thread credentials are forwarded to the H2 after WiFi setup.

#### Provisioning Flow

```
1. User long-presses button (3-5s) OR device boots without WiFi
2. S3 starts BLE advertising as "Saturday Hub XXXX"
3. User opens Saturday app, selects "Add Hub"
4. App scans for BLE devices with Saturday service UUID
5. User selects hub, app connects via BLE
6. App writes WiFi SSID and Password
7. S3 connects to WiFi
8. On success:
   a. S3 sends GET_CREDENTIALS to H2
   b. H2 returns Thread credentials (or generates if first time)
   c. S3 stores WiFi + Thread credentials in NVS
   d. S3 reports credentials to Supabase (for mobile app to provision crates)
9. S3 exits provisioning mode
10. App shows hub as connected
```

### H2 Firmware Update

The S3 can update the H2 firmware using esp-serial-flasher:

```
1. S3 receives OTA update (includes S3 + H2 firmware)
2. S3 updates itself first (standard OTA)
3. After reboot, S3 checks H2 firmware version
4. If H2 needs update:
   a. S3 sends ENTER_BOOTLOADER to H2
   b. H2 resets into download mode
   c. S3 flashes H2 via UART2
   d. S3 resets H2 into normal mode
```

---

## User Interface (LED & Button)

### RGB LED States

Connected to ESP32-S3 GPIO48.

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| Booting | White | Pulsing | Hardware initialization |
| Service Mode | White | Pulsing | Awaiting service mode commands |
| Service Testing | Yellow | Fast blink | Running service mode tests |
| Unprovisioned | Blue | Slow blink (1Hz) | Awaiting BLE provisioning |
| Provisioning | Blue | Fast blink (2Hz) | BLE provisioning in progress |
| Connecting | Yellow | Pulsing | Connecting to WiFi |
| H2 Starting | Cyan | Pulsing | Waiting for H2 Thread BR |
| Running (Idle) | Green | Solid dim | Normal operation, no tag |
| Tag Detected | Green | Brief flash | Record placed on turntable |
| WiFi Lost | Orange | Slow blink | WiFi disconnected, reconnecting |
| H2 Error | Red/Cyan | Alternating | H2 not responding |
| Error | Red | Slow blink | Recoverable error |
| Factory Reset | Red | Fast blink | Clearing configuration |
| Firmware Update | Magenta | Pulsing | OTA update in progress |

### Button Actions

| Action | Duration | Function |
|--------|----------|----------|
| Short press | <500ms | Reserved for future use |
| Long press | 3-5 seconds | Enter BLE provisioning mode |
| Very long press | >10 seconds | Factory reset |

---

## Configuration & Storage

### NVS (ESP32-S3)

#### Namespace: `sv_config`

| Key | Type | Description |
|-----|------|-------------|
| `hub_id` | string | Unique hub identifier |
| `provisioned` | bool | Whether factory provisioning is complete |
| `wifi_ssid` | string | WiFi network name |
| `wifi_pass` | string | WiFi password (encrypted) |
| `user_id` | string | Associated user's Supabase UUID |
| `supabase_url` | string | Supabase project URL |
| `supabase_key` | string | Supabase anon key |
| `device_secret` | string | Device authentication secret |
| `h2_fw_version` | string | Last known H2 firmware version |

### NVS (ESP32-H2)

#### Namespace: `sv_thread`

| Key | Type | Description |
|-----|------|-------------|
| `network_key` | blob | Thread network master key |
| `network_name` | string | Thread network name |
| `pan_id` | uint16 | Thread PAN ID |
| `channel` | uint8 | Thread radio channel |
| `extended_pan_id` | blob | Extended PAN ID |

---

## Error Handling

### Error Categories

| Category | Examples | Recovery |
|----------|----------|----------|
| WiFi | Disconnect, DNS failure | Auto-retry with backoff (S3) |
| RFID | Module not responding | Reset module (S3) |
| Cloud | API timeout, auth failure | Queue events, retry (S3) |
| H2 Comm | UART timeout, NAK | Retry command, reset H2 if needed |
| Thread | Network partition | Auto-reform (H2) |

### H2 Health Monitoring

The S3 periodically PINGs the H2:

```c
#define H2_PING_INTERVAL_MS     5000    // Every 5 seconds
#define H2_PING_TIMEOUT_MS      1000    // 1 second timeout
#define H2_MAX_FAILURES         3       // Reset after 3 failures
```

If H2 fails to respond:
1. S3 toggles H2_EN (reset)
2. Wait for H2 boot
3. Re-send START_THREAD
4. If still failing, report error to cloud

### Logging

Both chips use ESP-IDF logging with component tags:

```c
// S3 logs
ESP_LOGI("WIFI", "Connected to %s", ssid);
ESP_LOGI("H2_COMM", "Received inventory update from H2");
ESP_LOGE("H2_COMM", "H2 not responding, resetting");

// H2 logs
ESP_LOGI("THREAD", "Attached as router");
ESP_LOGI("COAP", "Inventory from crate %s", crate_id);
```

---

## Testing

### Unit Tests

Each firmware project has its own tests:

```bash
# S3 tests
cd s3-master
idf.py -T test build

# H2 tests
cd h2-thread-br
idf.py -T test build
```

### Integration Testing

1. **UART Protocol** - Test S3↔H2 communication with mock endpoints
2. **End-to-End** - Test crate → H2 → S3 → Supabase flow

### Hardware-in-the-Loop

| Test | Setup |
|------|-------|
| WiFi + Thread | S3+H2 boards, Thread dev kit as mock crate |
| RFID | YRM100 module, test tags |
| Provisioning | BLE app, serial terminal |

---

## Versioning & Releases

### Version Locations

```c
// s3-master/main/version.h
#define S3_FIRMWARE_VERSION_MAJOR 1
#define S3_FIRMWARE_VERSION_MINOR 0
#define S3_FIRMWARE_VERSION_PATCH 0
#define S3_FIRMWARE_VERSION "1.0.0"

// h2-thread-br/main/version.h
#define H2_FIRMWARE_VERSION_MAJOR 1
#define H2_FIRMWARE_VERSION_MINOR 0
#define H2_FIRMWARE_VERSION_PATCH 0
#define H2_FIRMWARE_VERSION "1.0.0"
```

### Release Process

1. Update versions in both projects
2. Update CHANGELOG.md
3. Tag release: `git tag v1.0.0`
4. Build both firmwares
5. Upload to Supabase storage for OTA

---

## Reference

### Quick Reference: S3↔H2 Protocol

| Direction | Type | Name |
|-----------|------|------|
| S3→H2 | `0x01` | PING |
| S3→H2 | `0x02` | GET_STATUS |
| S3→H2 | `0x05` | START_THREAD |
| H2→S3 | `0x81` | PONG |
| H2→S3 | `0x82` | STATUS |
| H2→S3 | `0xE2` | INVENTORY_UPDATE |

### External Resources

- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/latest/)
- [ESP32-S3 Technical Reference](https://www.espressif.com/documentation/esp32-s3_technical_reference_manual_en.pdf)
- [ESP32-H2 Technical Reference](https://www.espressif.com/documentation/esp32-h2_technical_reference_manual_en.pdf)
- [OpenThread Border Router](https://openthread.io/guides/border-router)
- [esp-serial-flasher](https://github.com/espressif/esp-serial-flasher)
- [CoAP RFC 7252](https://datatracker.ietf.org/doc/html/rfc7252)
- [Supabase Documentation](https://supabase.com/docs)

### Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2025-01-XX | Initial | Initial draft (ESP32-C6 single-SoC) |
| 0.2.0 | 2026-01-XX | - | Added YRM100 module variants |
| 0.3.0 | 2026-01-13 | - | Rewrite for 2-SoC architecture (ESP32-S3 + ESP32-H2) |
| 0.4.0 | 2026-01-13 | - | Added Service Mode documentation |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
