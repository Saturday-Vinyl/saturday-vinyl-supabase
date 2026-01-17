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

## Configuration Requirements

### Required Kconfig Options

```
# Enable software coexistence (REQUIRED for multi-protocol)
CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y

# Enable IEEE 802.15.4 radio
CONFIG_IEEE802154_ENABLED=y

# Enable OpenThread (if using Thread)
CONFIG_OPENTHREAD_ENABLED=y
CONFIG_OPENTHREAD_BORDER_ROUTER=y
CONFIG_OPENTHREAD_RADIO_NATIVE=y
```

### Critical API Call

After initializing both Wi-Fi and 802.15.4 stacks, you **must** call:

```c
#include "esp_coexist.h"

// Call AFTER both stacks are initialized
esp_coex_wifi_i154_enable();
```

This enables the coexistence arbitration between Wi-Fi and 802.15.4.

## Correct Initialization Sequence

Based on the official ESP-IDF `ot_br` (OpenThread Border Router) example:

```c
// 1. Basic system initialization
esp_vfs_eventfd_register(&eventfd_config);
nvs_flash_init();
esp_netif_init();
esp_event_loop_create_default();

// 2. Initialize OpenThread FIRST
esp_openthread_start(&config);

// 3. Start border router (connects Wi-Fi internally)
esp_openthread_border_router_start();

// 4. Enable coexistence AFTER both stacks are up
#if CONFIG_ESP_COEX_SW_COEXIST_ENABLE
esp_coex_wifi_i154_enable();
#endif
```

**Key insight**: OpenThread should be initialized BEFORE Wi-Fi connects. The border router example runs Wi-Fi connection in a separate task after OpenThread is running.

## Saturday Vinyl Hub: Chosen Architecture

After analyzing the requirements, we've chosen **Option B: Full Coexistence** for WiFi + Thread simultaneous operation.

### Operating Modes

The Hub operates in two mutually exclusive modes:

1. **Provisioning Mode** (BLE only)
   - Active when device has no WiFi credentials configured
   - BLE advertising for Saturday mobile app
   - WiFi and Thread disabled
   - Entered via: fresh device boot, or 3-5 second button press

2. **Normal Mode** (WiFi + Thread coexistence)
   - WiFi connected for cloud communication
   - Thread Border Router for crate communication
   - BLE disabled
   - Software coexistence manages radio sharing

### Initialization Sequence (Normal Mode)

```c
// 1. Basic system initialization
nvs_flash_init();
esp_netif_init();
esp_event_loop_create_default();
esp_vfs_eventfd_register();  // Required for OpenThread

// 2. Initialize OpenThread/Thread BR FIRST
thread_br_init();
thread_br_start();

// 3. Initialize Wi-Fi SECOND
wifi_init();
wifi_connect();

// 4. Enable coexistence AFTER both stacks are up
#if CONFIG_ESP_COEX_SW_COEXIST_ENABLE
esp_coex_wifi_i154_enable();
#endif

// 5. Start RFID polling (wired, no radio contention)
start_rfid_polling();
```

### Why Full Coexistence

1. **Continuous Thread listening** - Crates can send updates anytime
2. **Always-on cloud connectivity** - Real-time event uploads
3. **Simpler application logic** - No mode switching during operation
4. **Acceptable packet loss** - 5-20% Thread loss is tolerable for inventory updates

### Trade-offs

- Some Thread packet loss during heavy WiFi traffic
- Slightly higher power consumption than mode-switching
- Requires careful initialization order

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
- Each radio can operate at full capacity

**Cons:**
- Higher BOM cost (~$3-5 additional)
- More complex PCB design
- Two chips to program/maintain

**When to choose:** Production devices where reliability is critical.

### Option B: Single ESP32-C6 with Full Coexistence (CHOSEN)

**Architecture:**
- All protocols on single ESP32-C6
- Software coexistence enabled
- Accept some packet loss during high traffic

**Pros:**
- Single chip, lower cost
- Simpler hardware design
- All features available

**Cons:**
- Thread mesh reliability reduced during Wi-Fi activity
- Potential packet loss (5-20% depending on traffic)
- More complex software timing

**When to choose:** Development/prototyping, or when Thread traffic is light/bursty.

### Option C: Mode Switching

**Architecture:**
- Only one radio mode active at a time
- Switch modes based on operational state

**Pros:**
- Most reliable - no RF contention
- Simplest to debug
- Predictable behavior

**Cons:**
- Can't do Wi-Fi and Thread simultaneously
- Cloud connectivity paused during Thread operations
- Requires careful state management

### Option D: Wi-Fi Primary with Thread Bursts

**Architecture:**
- Wi-Fi always connected
- Thread enabled only during brief scan windows

**Pros:**
- Cloud always connected
- Predictable Thread windows

**Cons:**
- Crate responses may be missed
- Thread mesh doesn't maintain persistent routes

## Known Issues and Workarounds

### Issue: `esp_wifi_connect()` Hangs

**Symptom:** Calling `esp_wifi_connect()` from main task causes system to freeze.

**Cause:** Potential deadlock between main task and Wi-Fi driver internal tasks.

**Workaround:** Call `esp_wifi_connect()` from a separate task or timer callback.

### Issue: Wi-Fi Events Not Delivered

**Symptom:** `esp_wifi_connect()` returns OK but no CONNECTED/DISCONNECTED events.

**Cause:** Event handlers may not be registered, or event loop task stack overflow.

**Workaround:**
1. Increase `CONFIG_ESP_SYSTEM_EVENT_TASK_STACK_SIZE` to 6144+
2. Ensure event handlers are registered BEFORE calling connect
3. Verify `CONFIG_ESP_COEX_SW_COEXIST_ENABLE` matches your use case

### Issue: USB Serial Drops During Wi-Fi Init

**Symptom:** Serial monitor disconnects when Wi-Fi PHY initializes.

**Cause:** Hardware-level PHY interference between Wi-Fi and USB on ESP32-C6.

**Workaround:**
- Use JTAG for debugging instead of USB serial
- Or accept brief reconnection during boot

## References

- [ESP-IDF RF Coexistence Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/api-guides/coexist.html)
- [ESP-IDF OpenThread Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32c6/api-guides/openthread.html)
- [OpenThread Border Router on ESP](https://openthread.io/guides/border-router/espressif-esp32)
- [ESP-IDF ot_br Example](https://github.com/espressif/esp-idf/tree/master/examples/openthread/ot_br)
- [ESP32-C6 Product Page](https://www.espressif.com/en/products/socs/esp32-c6)
