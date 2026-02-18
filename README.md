# Saturday Vinyl Hub Firmware

Dual-SoC firmware for the Saturday Vinyl Hub — a Thread Border Router and "Now Playing" detector for vinyl record enthusiasts.

## Overview

The Saturday Vinyl Hub performs two primary functions:

1. **Thread Border Router** — Bridges the Thread mesh network (connecting battery-powered RFID crates) to Wi-Fi and the Saturday cloud (Supabase)
2. **Now Playing Detection** — Uses an integrated UHF RFID reader (YRM100) to detect which record is currently on the turntable

### Architecture

The hub uses a **dual-SoC design** to avoid WiFi/Thread radio contention:

| SoC | Role | Responsibilities |
|-----|------|------------------|
| **ESP32-S3** | Master | WiFi, BLE provisioning, RFID, cloud sync, USB service mode, UI |
| **ESP32-H2** | Slave | Thread Border Router, CoAP server for crate communication |

The two chips communicate via a binary UART protocol. See [Developer's Guide](docs/developers_guide.md) for the full architecture.

## Hardware

- **ESP32-S3** — Master MCU (WiFi 4, BLE 5.0, USB OTG)
- **ESP32-H2** — Thread co-processor (802.15.4)
- **YRM100** — UHF RFID module (ISO 18000-6C / EPC Gen2)
- **Interface** — USB-C for power and serial console

For pin assignments and wiring, see [Hub Wiring Reference](docs/wiring/hub_wiring.md).

## Project Structure

```
sv-hub-firmware/
├── s3-master/                  # ESP32-S3 master firmware (active)
│   ├── main/                   #   Application entry point
│   ├── components/             #   WiFi, RFID, cloud, BLE, H2 comm, UI
│   ├── sdkconfig.defaults      #   Default SDK configuration
│   └── partitions.csv          #   Partition table (dual OTA + H2 staging)
│
├── h2-thread-br/               # ESP32-H2 Thread BR firmware (active)
│   ├── main/                   #   Thread BR entry point
│   ├── components/             #   OpenThread, CoAP server, S3 comm
│   └── sdkconfig.defaults      #   SDK configuration
│
├── shared/                     # Shared code between S3 and H2
│   └── include/                #   S3↔H2 binary protocol definitions
│
├── shared-docs/                # Cross-project protocols and concepts (git subtree)
├── shared-supabase/            # Database migrations and edge functions (git subtree)
├── docs/                       # Developer guides, wiring references
│
├── components/                 # [DEPRECATED] Old single-SoC ESP32-C6 code
├── main/                       # [DEPRECATED] Old single-SoC entry point
└── CMakeLists.txt (root)       # [DEPRECATED] Old single-SoC build
```

> **Note:** The root-level `components/`, `main/`, `CMakeLists.txt`, `sdkconfig.defaults`, and `partitions.csv` are from the original ESP32-C6 prototype. Do not modify them. All active development is in `s3-master/` and `h2-thread-br/`.

## Building

### Prerequisites

- **ESP-IDF v5.2+** (latest stable recommended)
- **Python 3.8+**
- **USB-C cable** (data-capable)

### Build Commands

```bash
# Activate ESP-IDF environment
get_idf  # or: source ~/esp/esp-idf/export.sh

# Build S3 master firmware
cd s3-master
idf.py set-target esp32s3  # only needed once
idf.py build

# Build H2 Thread BR firmware
cd ../h2-thread-br
idf.py set-target esp32h2  # only needed once
idf.py build
```

### Flashing

```bash
# Flash S3 (connect USB to S3 DevKit)
cd s3-master
idf.py -p /dev/cu.usbmodem* flash monitor

# Flash H2 directly (connect USB to H2 DevKit — development only)
cd h2-thread-br
idf.py -p /dev/cu.usbmodem* flash monitor

# In production, H2 is flashed via S3 using esp-serial-flasher over UART
```

## LED States

The onboard WS2812 RGB LED (GPIO48) indicates device state:

| State | Color | Pattern | Meaning |
|-------|-------|---------|---------|
| Booting | White | Pulsing | Hardware initialization |
| Service Mode | White | Pulsing | Awaiting service mode commands |
| Unprovisioned | Blue | Slow blink | Awaiting BLE provisioning |
| Connecting | Yellow | Pulsing | Connecting to WiFi |
| H2 Starting | Cyan | Pulsing | Waiting for H2 Thread BR |
| Running (Idle) | Green | Solid dim | Normal operation |
| Tag Detected | Green | Brief flash | Record placed on turntable |
| WiFi Lost | Orange | Slow blink | WiFi disconnected, reconnecting |
| H2 Error | Red/Cyan | Alternating | H2 not responding |
| Error | Red | Slow blink | Recoverable error |
| Factory Reset | Red | Fast blink | Clearing configuration |
| OTA Update | Magenta | Pulsing | Firmware update in progress |

## Button Actions

| Duration | Action |
|----------|--------|
| < 500ms | Short press (reserved) |
| 3–5 seconds | Enter BLE provisioning mode |
| > 10 seconds | Factory reset |

## Documentation

- [Developer's Guide](docs/developers_guide.md) — Full technical specification and architecture
- [Hub Wiring Reference](docs/wiring/hub_wiring.md) — Pin assignments and wiring diagrams
- [Hub Provisioning Guide](docs/hub_provisioning_guide.md) — Factory provisioning procedures
- [Service Mode Protocol](shared-docs/protocols/service_mode_protocol.md) — USB serial protocol reference
- [Database Schema](shared-supabase/schema/SCHEMA.md) — Supabase schema reference

## License

Proprietary — Saturday Vinyl, Inc.
