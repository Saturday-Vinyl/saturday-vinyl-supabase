# Saturday Device LED Status Protocol

**Version:** 1.0.0
**Last Updated:** 2026-02-01
**Audience:** Saturday firmware engineers, Admin App developers, Consumer App developers

---

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [Color Definitions](#color-definitions)
4. [Pattern Definitions](#pattern-definitions)
5. [Device States](#device-states)
   - [Boot States](#boot-states)
   - [Provisioning States](#provisioning-states)
   - [Network States](#network-states)
   - [Operational States](#operational-states)
   - [Error States](#error-states)
   - [User Interaction States](#user-interaction-states)
6. [LED Configuration Matrix](#led-configuration-matrix)
7. [Hardware Considerations](#hardware-considerations)
8. [Implementation Guide](#implementation-guide)
9. [Version History](#version-history)

---

## Overview

This document defines the standard LED status indicators for all Saturday devices. Consistent LED behavior across devices helps users understand device state at a glance, reduces support calls, and provides a unified brand experience.

### Scope

This protocol applies to:
- **Saturday Hub** - RGB LED strip (SK6812/WS2812B)
- **Saturday Crate** - RGB LED strip
- **Future devices** - Any device with user-facing LED indicators

### Key Concepts

- **Color** - The hue displayed (white, green, yellow, red, blue, etc.)
- **Pattern** - How the LED changes over time (solid, pulse, blink, flash)
- **State** - The device condition being communicated (booting, ready, error, etc.)

---

## Design Principles

1. **Consistency** - Same color/pattern means the same thing across all devices
2. **Intuitiveness** - Colors follow common conventions (green = good, red = bad, yellow = busy)
3. **Non-intrusive** - LED patterns should be visible but not annoying
4. **Accessibility** - Use both color AND pattern to convey meaning (for color-blind users)
5. **Energy efficient** - Dim LEDs when possible, especially for battery devices
6. **Silent by default** - LEDs should be off or minimal during normal operation

---

## Color Definitions

### Standard Colors

| Color | RGB Value | Hex Code | Semantic Meaning |
|-------|-----------|----------|------------------|
| White | (255, 255, 255) | `#FFFFFF` | Neutral/Waiting/Ready |
| Green | (0, 255, 0) | `#00FF00` | Success/Connected/Good |
| Yellow | (255, 200, 0) | `#FFC800` | Processing/Warning/Busy |
| Red | (255, 0, 0) | `#FF0000` | Error/Critical/Reset |
| Blue | (0, 0, 255) | `#0000FF` | Bluetooth/Pairing Mode |
| Cyan | (0, 255, 255) | `#00FFFF` | Thread/Network Activity |
| Purple | (128, 0, 255) | `#8000FF` | Firmware Update |
| Orange | (255, 100, 0) | `#FF6400` | Battery Low Warning |

### Color Priority

When multiple states apply, use this priority order:
1. **Red** - Error states always override
2. **Purple** - Firmware updates in progress
3. **Yellow** - Processing/Busy states
4. **Blue/Cyan** - Network activity
5. **Green** - Success confirmations
6. **White** - Idle/Ready states

### Brightness Guidelines

| Context | Brightness | Notes |
|---------|------------|-------|
| Active interaction | 100% | User is actively working with device |
| Status indication | 50% | Passive status display |
| Idle/Standby | 20% or OFF | Minimize ambient light pollution |
| Night mode (if supported) | 10% | Optional feature for home devices |

---

## Pattern Definitions

### Standard Patterns

| Pattern | Description | Timing | Use Case |
|---------|-------------|--------|----------|
| `solid` | Constant on | N/A | Idle states, waiting for input |
| `pulse` | Smooth fade in/out | 2s cycle (1s in, 1s out) | Ready states, breathing effect |
| `blink` | On/off cycle | 1s on, 1s off | Status indication |
| `blink_fast` | Rapid on/off | 250ms on, 250ms off | Test in progress, urgent attention |
| `flash` | Brief on, then off | 200ms on, 800ms off | Confirmation feedback |
| `flash_double` | Two quick flashes | 100ms on, 100ms off, 100ms on, 700ms off | Button press acknowledgment |
| `wave` | Sequential LED animation | 100ms per LED | Network activity, data transfer |
| `chase` | Single LED moving | 50ms per LED | Boot sequence, loading |
| `rainbow` | Color cycling | 5s full cycle | Party mode, special events |

### Pattern Visual Reference

```
solid:       ████████████████████████████████████████
             ON...

pulse:       ░▒▓█████████▓▒░░▒▓█████████▓▒░░▒▓█████
             ↑ fade in  ↑ fade out

blink:       ████████░░░░░░░░████████░░░░░░░░████████
             1s on    1s off   1s on

blink_fast:  ██░░██░░██░░██░░██░░██░░██░░██░░██░░██░░
             250ms cycles

flash:       ██░░░░░░░░░░██░░░░░░░░░░██░░░░░░░░░░██
             200ms on, 800ms off

flash_double: ██░██░░░░░░░░░░██░██░░░░░░░░░░██░██
              100/100/100/700ms
```

---

## Device States

### Boot States

| State | Color | Pattern | Duration | Description |
|-------|-------|---------|----------|-------------|
| Power On | White | `chase` | ~1s | Initial power-on animation |
| Bootloader | Purple | `blink` | Until complete | Bootloader active |
| Firmware Init | White | `pulse` | Until complete | Firmware initializing |
| Ready (Fresh) | White | `pulse` | Ongoing | Fresh device, awaiting provisioning |
| Ready (Provisioned) | Green | `flash` | 1s then off | Boot complete, entering normal mode |

### Provisioning States

#### Factory Provisioning (Serial/USB)

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| Service Mode Entry | White | `pulse` | Awaiting factory provisioning commands |
| Processing Command | Yellow | `pulse` | Command received, processing |
| Test Running | Yellow | `blink_fast` | Hardware test in progress |
| Test Passed | Green | `flash` x3 | Individual test passed |
| Test Failed | Red | `flash` x3 | Individual test failed |
| Provisioning Complete | Green | `solid` 2s | All provisioning successful |
| Resetting | Red | `blink_fast` | Factory reset in progress |

#### Consumer Provisioning (BLE)

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| BLE Advertising | Blue | `pulse` | Device discoverable via Bluetooth |
| BLE Connected | Blue | `solid` | App connected to device |
| Credentials Received | Blue | `blink` | WiFi/Thread credentials written |
| Network Connecting | Cyan | `blink_fast` | Connecting to WiFi/Thread |
| Cloud Verifying | Cyan | `pulse` | Verifying cloud connectivity |
| Setup Complete | Green | `flash` x3 | Provisioning successful |
| Setup Failed | Red | `blink` | Provisioning failed (see error) |

### Network States

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| WiFi Connecting | Cyan | `blink_fast` | Connecting to WiFi network |
| WiFi Connected | Cyan | `flash` | WiFi connection established |
| WiFi Disconnected | Yellow | `blink` | WiFi connection lost |
| Thread Joining | Cyan | `blink_fast` | Joining Thread network |
| Thread Connected | Cyan | `flash` | Thread network joined |
| Thread Disconnected | Yellow | `blink` | Thread connection lost |
| Cloud Connected | Green | `flash` | Cloud backend reachable |
| Cloud Disconnected | Yellow | `blink` | Cloud backend unreachable |

### Operational States

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| Idle | OFF | N/A | Normal operation, no LED needed |
| RFID Scanning | Cyan | `wave` | Actively scanning for RFID tags |
| Tag Detected | Green | `flash` | RFID tag successfully read |
| Data Syncing | Cyan | `pulse` | Syncing data with cloud |
| Sync Complete | Green | `flash` | Sync successful |

### Error States

| State | Color | Pattern | Duration | Description |
|-------|-------|---------|----------|-------------|
| General Error | Red | `blink` | 5s | Recoverable error occurred |
| Critical Error | Red | `blink_fast` | Ongoing | Critical system error |
| Hardware Fault | Red | `solid` | Ongoing | Hardware component failure |
| WiFi Auth Failed | Red | `flash` x2 | 3s | Incorrect WiFi password |
| Network Not Found | Red | `flash` x3 | 3s | SSID not found |
| Cloud Unreachable | Orange | `blink` | 5s | Cannot reach cloud backend |
| Low Battery | Orange | `pulse` | Ongoing | Battery below 20% |
| Critical Battery | Red | `blink` | Ongoing | Battery below 10% |

### User Interaction States

| State | Color | Pattern | Description |
|-------|-------|---------|-------------|
| Button Press Ack | White | `flash_double` | Button press acknowledged |
| Long Press Active | Yellow | `pulse` | Long press in progress |
| Long Press Complete | Green | `flash` | Long press action triggered |
| Volume Change | White | `wave` | Volume adjustment (proportional) |
| Mode Change | Blue | `flash_double` | Device mode changed |

---

## LED Configuration Matrix

### State-to-LED Mapping Table

This table provides the complete mapping for firmware implementation:

| State ID | State Name | Color RGB | Pattern | Duration | Priority |
|----------|------------|-----------|---------|----------|----------|
| 0x00 | OFF | (0,0,0) | solid | - | 0 |
| 0x01 | BOOT | (255,255,255) | chase | 1s | 100 |
| 0x02 | BOOT_COMPLETE | (0,255,0) | flash | 1s | 90 |
| 0x10 | SERVICE_MODE | (255,255,255) | pulse | ongoing | 80 |
| 0x11 | PROCESSING | (255,200,0) | pulse | ongoing | 85 |
| 0x12 | TESTING | (255,200,0) | blink_fast | ongoing | 85 |
| 0x13 | TEST_PASS | (0,255,0) | flash | 1s | 70 |
| 0x14 | TEST_FAIL | (255,0,0) | flash | 1s | 95 |
| 0x15 | PROVISIONED | (0,255,0) | solid | 2s | 70 |
| 0x16 | RESETTING | (255,0,0) | blink_fast | ongoing | 95 |
| 0x20 | BLE_ADVERTISING | (0,0,255) | pulse | ongoing | 60 |
| 0x21 | BLE_CONNECTED | (0,0,255) | solid | ongoing | 60 |
| 0x22 | BLE_CREDS_RX | (0,0,255) | blink | ongoing | 65 |
| 0x30 | NET_CONNECTING | (0,255,255) | blink_fast | ongoing | 70 |
| 0x31 | NET_CONNECTED | (0,255,255) | flash | 1s | 65 |
| 0x32 | NET_DISCONNECTED | (255,200,0) | blink | 5s | 75 |
| 0x40 | CLOUD_CONNECTED | (0,255,0) | flash | 1s | 65 |
| 0x41 | CLOUD_DISCONNECTED | (255,200,0) | blink | 5s | 75 |
| 0x50 | RFID_SCANNING | (0,255,255) | wave | ongoing | 50 |
| 0x51 | RFID_TAG_FOUND | (0,255,0) | flash | 500ms | 55 |
| 0x60 | SYNCING | (0,255,255) | pulse | ongoing | 60 |
| 0x61 | SYNC_COMPLETE | (0,255,0) | flash | 1s | 55 |
| 0x70 | OTA_UPDATE | (128,0,255) | pulse | ongoing | 90 |
| 0x71 | OTA_PROGRESS | (128,0,255) | wave | ongoing | 90 |
| 0x72 | OTA_COMPLETE | (0,255,0) | solid | 2s | 85 |
| 0xE0 | ERROR | (255,0,0) | blink | 5s | 95 |
| 0xE1 | ERROR_CRITICAL | (255,0,0) | blink_fast | ongoing | 100 |
| 0xE2 | ERROR_HARDWARE | (255,0,0) | solid | ongoing | 100 |
| 0xE3 | ERROR_WIFI_AUTH | (255,0,0) | flash | 3s | 90 |
| 0xE4 | ERROR_NET_NOTFOUND | (255,0,0) | flash | 3s | 90 |
| 0xF0 | BATTERY_LOW | (255,100,0) | pulse | ongoing | 80 |
| 0xF1 | BATTERY_CRITICAL | (255,0,0) | blink | ongoing | 85 |
| 0xFF | USER_ACK | (255,255,255) | flash_double | 500ms | 40 |

---

## Hardware Considerations

### LED Types

| LED Type | Characteristics | Devices |
|----------|-----------------|---------|
| SK6812 (RGBW) | 4-channel with dedicated white | Hub, Crate |
| WS2812B (RGB) | 3-channel addressable | Legacy devices |
| Single LED (GPIO) | Simple on/off with PWM | Low-cost sensors |

### LED Count Variations

Devices may have different LED counts. Patterns should scale appropriately:

| LED Count | Pattern Adaptation |
|-----------|-------------------|
| 1 LED | Use color and pattern only |
| 2-4 LEDs | Mirror pattern from center |
| 5+ LEDs | Full wave/chase animations |

### Power Considerations

| Mode | Current Draw | Notes |
|------|--------------|-------|
| Full brightness | ~60mA per LED | Limit for battery devices |
| 50% brightness | ~30mA per LED | Standard status indication |
| 20% brightness | ~12mA per LED | Idle/standby mode |
| Off | ~0.5mA | Sleep mode leakage |

---

## Implementation Guide

### Firmware Data Structures

```c
// LED state definition
typedef struct {
    uint8_t state_id;       // State identifier (0x00-0xFF)
    uint8_t r, g, b;        // Color values
    uint8_t pattern;        // Pattern type
    uint16_t duration_ms;   // Duration (0 = ongoing)
    uint8_t priority;       // Higher number = higher priority
} led_state_t;

// Pattern types
typedef enum {
    LED_PATTERN_SOLID = 0,
    LED_PATTERN_PULSE = 1,
    LED_PATTERN_BLINK = 2,
    LED_PATTERN_BLINK_FAST = 3,
    LED_PATTERN_FLASH = 4,
    LED_PATTERN_FLASH_DOUBLE = 5,
    LED_PATTERN_WAVE = 6,
    LED_PATTERN_CHASE = 7,
    LED_PATTERN_RAINBOW = 8,
} led_pattern_t;

// State identifiers
#define LED_STATE_OFF               0x00
#define LED_STATE_BOOT              0x01
#define LED_STATE_BOOT_COMPLETE     0x02
#define LED_STATE_SERVICE_MODE      0x10
#define LED_STATE_PROCESSING        0x11
#define LED_STATE_TESTING           0x12
#define LED_STATE_TEST_PASS         0x13
#define LED_STATE_TEST_FAIL         0x14
#define LED_STATE_PROVISIONED       0x15
#define LED_STATE_RESETTING         0x16
#define LED_STATE_BLE_ADVERTISING   0x20
#define LED_STATE_BLE_CONNECTED     0x21
#define LED_STATE_NET_CONNECTING    0x30
#define LED_STATE_NET_CONNECTED     0x31
#define LED_STATE_NET_DISCONNECTED  0x32
#define LED_STATE_ERROR             0xE0
#define LED_STATE_ERROR_CRITICAL    0xE1
```

### Example Implementation

```c
#include "led_controller.h"

// Initialize LED controller
void led_init(void) {
    // Configure LED GPIO/strip
    configure_led_strip(LED_PIN, LED_COUNT, LED_TYPE_SK6812);

    // Set initial state
    led_set_state(LED_STATE_BOOT);
}

// Set LED state with priority handling
void led_set_state(uint8_t state_id) {
    led_state_t new_state = get_state_config(state_id);
    led_state_t current = get_current_state();

    // Only update if new state has higher or equal priority
    if (new_state.priority >= current.priority) {
        apply_led_state(&new_state);
    }
}

// Timed state - automatically reverts to previous state
void led_set_state_timed(uint8_t state_id, uint16_t duration_ms) {
    led_state_t previous = get_current_state();
    led_set_state(state_id);

    // Schedule reversion
    schedule_state_change(previous.state_id, duration_ms);
}

// Example: Flash success then return to idle
void indicate_success(void) {
    led_set_state_timed(LED_STATE_TEST_PASS, 1000);
}
```

### Integration with Service Mode Manifest

The LED patterns can be included in the Service Mode Manifest for dynamic configuration:

```json
{
  "led_patterns": {
    "service_awaiting": {
      "color": "white",
      "rgb": [255, 255, 255],
      "pattern": "pulse",
      "priority": 80
    },
    "processing": {
      "color": "yellow",
      "rgb": [255, 200, 0],
      "pattern": "pulse",
      "priority": 85
    },
    "testing": {
      "color": "yellow",
      "rgb": [255, 200, 0],
      "pattern": "blink_fast",
      "priority": 85
    },
    "success": {
      "color": "green",
      "rgb": [0, 255, 0],
      "pattern": "flash",
      "priority": 70
    },
    "error": {
      "color": "red",
      "rgb": [255, 0, 0],
      "pattern": "flash",
      "priority": 95
    }
  }
}
```

### Testing LED Behavior

Use the `test_led` command to verify LED functionality:

```json
{"cmd": "test_led"}
```

The device should cycle through all primary colors (red, green, blue, white) to verify LED hardware functionality.

For specific pattern testing, use the extended command:

```json
{
  "cmd": "test_led",
  "params": {
    "color": [255, 0, 0],
    "pattern": "pulse",
    "duration_ms": 5000
  }
}
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-01 | Initial protocol specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
