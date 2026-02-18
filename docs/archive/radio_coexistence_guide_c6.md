> **ARCHIVED**: This document is from the original single-SoC ESP32-C6 prototype era.
> The Saturday Vinyl Hub now uses a **dual-SoC architecture** (ESP32-S3 + ESP32-H2),
> which eliminates the radio coexistence issues described here. Kept for historical reference.
> See `docs/developers_guide.md` for the current architecture.

# ESP32-C6 Radio Coexistence Guide

## Overview

The ESP32-C6 SoC features a **single 2.4 GHz RF module** shared between three wireless protocols:
- **Wi-Fi** (802.11 b/g/n/ax - Wi-Fi 6)
- **Bluetooth Low Energy** (BLE 5.0)
- **IEEE 802.15.4** (Thread/Zigbee)

This shared radio architecture requires careful management when using multiple protocols simultaneously.

## How Coexistence Works

### Time-Division Multiplexing (TDM)

Since only one protocol can use the radio at any given moment, ESP-IDF implements **time-division multiplexing** with priority-based resource allocation:

1. Each protocol requests RF resources from the coexistence module
2. The coexistence module grants access based on priority
3. Protocols take turns using the radio in time slices

### Priority Hierarchy

| Operation | Priority | Notes |
|-----------|----------|-------|
| Wi-Fi TX/RX during active connection | High | Maintains connection stability |
| BLE advertising/scanning | Medium | Can be preempted by Wi-Fi |
| 802.15.4 TX with ACK | Medium-High | Time-critical for mesh reliability |
| 802.15.4 normal RX | Low | Gets remaining time after Wi-Fi/BLE |

### Performance Implications

- **802.15.4 (Thread/Zigbee)**: Routers require continuous signal reception. With a single RF path, increased Wi-Fi or BLE traffic leads to higher packet loss rates for Thread/Zigbee.
- **Wi-Fi**: Generally gets priority, but may experience brief delays during BLE or 802.15.4 critical operations.
- **BLE**: Works well for brief operations (provisioning, beacons) but not recommended for continuous streaming alongside Wi-Fi.

## Espressif's Official Recommendation

From the [ESP-IDF RF Coexistence Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/api-guides/coexist.html):

> "To build a Wi-Fi based Thread Border Router or Zigbee Gateway product, **we recommend using a dual-SoC solution** (e.g., ESP32-S3 + ESP32-H2) with separate antennas."

This recommendation exists because Thread routers must maintain unsynchronized links with neighbors, requiring continuous reception that conflicts with Wi-Fi traffic.

## Architectural Options Reference

### Option A: Dual-SoC Architecture (Recommended for Production)

**Hardware:**
- ESP32-S3 or ESP32-C3: Wi-Fi + BLE + main application
- ESP32-H2: Thread/802.15.4 only (RCP mode)
- Connected via SPI or UART (Spinel protocol)

**Pros:**
- Best reliability and performance
- No radio contention
- Officially recommended by Espressif

**Cons:**
- Higher BOM cost (~$3-5 additional)
- More complex PCB design

**When to choose:** Production devices where reliability is critical.

### Option B: Single ESP32-C6 with Full Coexistence

**Architecture:**
- All protocols on single ESP32-C6
- Software coexistence enabled
- Accept some packet loss during high traffic

**When to choose:** Development/prototyping, or when Thread traffic is light/bursty.

## References

- [ESP-IDF RF Coexistence Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/api-guides/coexist.html)
- [ESP-IDF OpenThread Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/api-guides/openthread.html)
- [OpenThread Border Router on ESP](https://openthread.io/guides/border-router/espressif-esp32)
