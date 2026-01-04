# Saturday Vinyl Hub - Wiring Reference

**Document Version:** 1.6.0
**Hardware Revision:** Dev Kit (ESP32-C6-DevKitC-1 + YRM100)
**Last Updated:** 2025-01-XX

> **Note:** This document provides a quick wiring reference for test harness assembly.
> For the authoritative schematic, see `hub_schematic.sch` (Fusion/EAGLE format).

---

## Overview

The Saturday Hub test harness connects an ESP32-C6 development board to:
- **YRM100** - UHF RFID module for "Now Playing" detection
- **RGB LED** - Status indication (onboard WS2812 addressable LED)
- **Button** - User input (factory reset, provisioning mode)
- **USB-C** - Power and debug console

---

## System Block Diagram

```
                              ┌─────────────────────────────────────┐
                              │         Saturday Vinyl Hub          │
                              │           (ESP32-C6)                │
┌─────────────┐               │                                     │
│   USB-C     │───── 5V ──┬──►│ Power (via onboard regulator)       │
│  Connector  │           │   │                                     │
│             │◄──── D+/D-┼──►│ GPIO12/13 (USB)                     │
└─────────────┘           │   │                                     │
                          │   │                                     │
┌─────────────┐           │   │                                     │
│   YRM100    │◄── 5V ────┘   │                                     │
│    RFID     │◄──── TX ─────►│ GPIO4 (UART1_RX)                    │
│   Module    │◄──── RX ─────►│ GPIO5 (UART1_TX)                    │
│             │◄──── EN ─────►│ GPIO6 (Enable)                      │
└─────────────┘               │                                     │
                              │                                     │
┌─────────────┐               │                                     │
│  WS2812     │◄── Data ─────►│ GPIO8 (RMT)  [Onboard LED]          │
│  RGB LED    │               │                                     │
└─────────────┘               │                                     │
                              │                                     │
┌─────────────┐               │                                     │
│   Button    │◄─────────────►│ GPIO18 (Input, internal pull-up)    │
└─────────────┘               │                                     │
                              └─────────────────────────────────────┘
```

> **Important:** The YRM100 is powered from the USB 5V rail directly, NOT from the
> ESP32-C6's 3.3V regulator. This ensures adequate current for RF transmission
> (up to 260mA peak) and meets the module's 3.5V minimum voltage requirement.

> **LED Note:** The ESP32-C6-DevKitC-1 includes an onboard WS2812 addressable RGB LED
> connected to GPIO8. No external LED wiring is required for the dev kit.

---

## ESP32-C6 Pin Assignments

| GPIO | Function     | Direction | Connect To              | Notes                          |
|------|--------------|-----------|-------------------------|--------------------------------|
| 0    | UART0_TX     | Output    | USB-C (debug)           | Debug console TX               |
| 1    | UART0_RX     | Input     | USB-C (debug)           | Debug console RX               |
| 4    | UART1_RX     | Input     | YRM100 Pin 4 (TXD)      | Hub receives from RFID module  |
| 5    | UART1_TX     | Output    | YRM100 Pin 3 (RXD)      | Hub transmits to RFID module   |
| 6    | RFID_EN      | Output    | YRM100 Pin 2 (EN)       | Active HIGH to enable module   |
| 8    | RMT_DATA     | Output    | Onboard WS2812          | Addressable RGB LED data line  |
| 12   | USB_D-       | Bidir     | USB-C connector         | USB data minus                 |
| 13   | USB_D+       | Bidir     | USB-C connector         | USB data plus                  |
| 18   | BUTTON       | Input     | Momentary switch to GND | Active LOW, internal pull-up   |

> **Note:** GPIO8 is a strapping pin but the DevKit's onboard circuit handles this.
> GPIO9 and GPIO10 are now available for future expansion.

---

## YRM100 RFID Module Wiring

The YRM100 is a UHF RFID module using the M100 protocol. Two compatible module variants
are supported, with different wire color schemes.

### Pinout

```
        ┌─────────────────────────────────────┐
        │           YRM100 Module             │
        │             (Top View)              │
        │                                     │
        │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐     │
        │  │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │     │
        │  └───┘ └───┘ └───┘ └───┘ └───┘     │
        │  GND   EN    RXD   TXD   VCC       │
        └─────────────────────────────────────┘
```

### Module Variants

| Variant | Manufacturer | Antenna Gain | Notes |
|---------|--------------|--------------|-------|
| **YRM100 (SBComponents)** | SBComponents | 3 dBi | Larger antenna, original module |
| **YRM100 (Generic)** | AliExpress generic | 2 dBi | Smaller antenna, compact form factor |

Both modules share identical electrical specifications and protocol:
- Working voltage: DC 3.5V - 5V
- Output power range: 15-26 dBm (**minimum 15 dBm**)
- Baud rate: 115200 BPS (default)
- Air interface: EPCglobal UHF Class 1 Gen 2 / ISO 18000-6C
- Working spectrum: 840-960 MHz

### Connection Tables

#### YRM100 (SBComponents) - 3 dBi Antenna

| YRM100 Pin | Name | Connect To        | Wire Color |
|------------|------|-------------------|------------|
| 1          | GND  | Common GND        | Black      |
| 2          | EN   | ESP32-C6 GPIO6    | Green      |
| 3          | RXD  | ESP32-C6 GPIO5    | Orange     |
| 4          | TXD  | ESP32-C6 GPIO4    | Yellow     |
| 5          | VCC  | USB 5V rail       | Red        |

#### YRM100 (Generic/AliExpress) - 2 dBi Antenna

| YRM100 Pin | Name | Connect To        | Wire Color |
|------------|------|-------------------|------------|
| 1          | GND  | Common GND        | Blue       |
| 2          | EN   | ESP32-C6 GPIO6    | Green      |
| 3          | RXD  | ESP32-C6 GPIO5    | Yellow     |
| 4          | TXD  | ESP32-C6 GPIO4    | Black      |
| 5          | VCC  | USB 5V rail       | Red        |

> **Note:** The YRM100 VCC (Pin 5) must be connected to the 5V rail (from USB), not the
> ESP32-C6's 3V3 output. The module requires 3.5-5V and draws up to 260mA
> peak during RF transmission. EN (Pin 2) requires >1.5V to enable the module.
>
> **Important:** The minimum RF power for YRM100 modules is **15 dBm**. Setting lower values
> will be accepted but the module silently uses 15 dBm.

### UART Configuration

| Parameter  | Value   |
|------------|---------|
| Baud Rate  | 115200  |
| Data Bits  | 8       |
| Parity     | None    |
| Stop Bits  | 1       |

---

## RGB LED (Onboard WS2812)

The ESP32-C6-DevKitC-1 includes an onboard WS2812 (NeoPixel-compatible) addressable RGB LED.
**No external wiring is required** for the development kit.

### Specifications

| Parameter       | Value                                    |
|-----------------|------------------------------------------|
| Type            | WS2812 (addressable RGB)                 |
| GPIO            | 8                                        |
| Protocol        | Single-wire, 800 kHz                     |
| Driver          | ESP-IDF RMT peripheral + `led_strip`     |
| LED Count       | 1                                        |
| Package         | 5050 (5mm x 5mm)                         |

### Schematic (Onboard - DevKit Reference)

```
                    3.3V
                      │
              ┌───────┴───────┐
              │    WS2812     │
              │   ┌───────┐   │
              │   │ LED   │   │
              │   │ Die   │   │
              │   └───────┘   │
              │               │
              │  VDD  DIN DOUT│
              └───┬────┬────┬─┘
                  │    │    │
                 3.3V  │    NC (not connected on single LED)
                       │
    ESP32-C6 GPIO8 ────┘
         (RMT)

    Note: DevKit includes required pull resistors on GPIO8 for strapping
```

### Firmware Usage

```c
#include "led_strip.h"

// Initialize
led_strip_handle_t led_strip;
led_strip_config_t strip_config = {
    .strip_gpio_num = 8,
    .max_leds = 1,
};
led_strip_rmt_config_t rmt_config = {
    .resolution_hz = 10 * 1000 * 1000,  // 10 MHz
};
led_strip_new_rmt_device(&strip_config, &rmt_config, &led_strip);

// Set color (R, G, B values 0-255)
led_strip_set_pixel(led_strip, 0, 255, 0, 0);  // Red
led_strip_refresh(led_strip);

// Turn off
led_strip_clear(led_strip);
```

### Production Considerations

For production PCBs using the ESP32-C6-WROOM module:
- Add a WS2812B-V5 or SK6812 LED connected to GPIO8
- Follow Espressif's reference design for GPIO8 strapping resistors (R6: 3.3kΩ, R29: 10kΩ)
- Consider light pipe routing for enclosure visibility

---

## Button Wiring

### Schematic

```
                           3.3V
                             │
                        ┌────┴────┐
                        │  10kΩ   │  (Optional - ESP32-C6 has internal pull-up)
                        └────┬────┘
                             │
                             ├──────────────────► ESP32-C6 GPIO18 (BUTTON)
                             │
                          ┌──┴──┐
                          │     │
                          │ BTN │  Momentary, Normally Open
                          │     │
                          └──┬──┘
                             │
                            GND
```

### Configuration

| Parameter       | Value                    |
|-----------------|--------------------------|
| GPIO Mode       | Input                    |
| Pull-up         | Internal (enabled)       |
| Active State    | LOW (pressed = 0)        |
| Debounce Time   | 50ms (software)          |

### Button Actions (Firmware)

| Press Duration | Action                |
|----------------|-----------------------|
| < 500ms        | Short press (future)  |
| 3-5 seconds    | Enter BLE provisioning|
| > 10 seconds   | Factory reset         |

---

## Power

### Power Distribution

```
                                    USB-C 5V Input
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                          ▼               ▼               │
                    ┌───────────┐   ┌───────────┐        │
                    │  ESP32-C6 │   │  YRM100   │        │
                    │  Onboard  │   │  (direct) │        │
                    │    LDO    │   │           │        │
                    └─────┬─────┘   └───────────┘        │
                          │                              │
                          ▼                              │
                    ┌───────────┐                        │
                    │   3.3V    │                        │
                    │   Rail    │                        │
                    └─────┬─────┘                        │
                          │                              │
          ┌───────────────┼───────────────┐              │
          │               │               │              │
          ▼               ▼               ▼              │
    ┌───────────┐   ┌───────────┐   ┌───────────┐       │
    │  ESP32-C6 │   │  WS2812   │   │  Button   │       │
    │   (MCU)   │   │ (onboard) │   │ (pullup)  │       │
    └───────────┘   └───────────┘   └───────────┘       │
                                                         │
                                    Common GND ◄─────────┘
```

### Requirements

| Rail        | Voltage | Current (typical) | Current (max) | Source            |
|-------------|---------|-------------------|---------------|-------------------|
| USB Input   | 5V      | 350mA             | 500mA         | USB-C connector   |
| System (3V3)| 3.3V    | 100mA             | 200mA         | ESP32-C6 onboard LDO |

### Power Budget

| Component     | Rail | Current (typical) | Current (peak) | Notes                    |
|---------------|------|-------------------|----------------|--------------------------|
| ESP32-C6      | 3.3V | 80mA              | 150mA          | Via onboard LDO          |
| YRM100 (idle) | 5V   | 30mA              | 30mA           | Direct from USB 5V       |
| YRM100 (TX)   | 5V   | 200mA             | 260mA          | At 26 dBm output         |
| WS2812 LED    | 3.3V | 1mA               | 60mA           | Onboard, max ~20mA/color |
| **Total 3.3V**|      | **~81mA**         | **~210mA**     | Well within LDO capacity |
| **Total 5V**  |      | **~310mA**        | **~420mA**     | Within USB 500mA limit   |

> **Note:** A quality USB-C cable and 500mA+ source is required. The YRM100 draws
> significant current during RF transmission.

---

## Test Points

For debugging and validation, expose these signals:

| Test Point | Signal      | Purpose                      |
|------------|-------------|------------------------------|
| TP1        | UART1_TX    | Scope RFID commands          |
| TP2        | UART1_RX    | Scope RFID responses         |
| TP3        | RFID_EN     | Verify enable signal         |
| TP4        | 5V          | Verify USB power rail        |
| TP5        | 3V3         | Verify regulated rail        |
| TP6        | GND         | Ground reference             |

---

## Breadboard Layout (Suggested)

```
    USB-C
      │
      │ 5V ─────────────────────────────────────┐
      │                                         │
┌─────┴─────┐                                   │
│           │                                   │
│  ESP32-C6 │                                   │
│  DevKit   │                                   │
│           │                                   │
│  [  ] [ ] │◄─── GPIO4 (UART1_RX) ──────────►  │  YRM100 TX
│  [  ] [ ] │◄─── GPIO5 (UART1_TX) ──────────►  │  YRM100 RX
│  [  ] [ ] │◄─── GPIO6 (RFID_EN) ───────────►  │  YRM100 EN
│  [  ] [ ] │                                   │
│  [  ] [ ] │     GPIO8 ──► Onboard WS2812 LED (no wiring needed)
│  [  ] [ ] │                                   │
│  [  ] [ ] │◄─── GPIO18 (BUTTON) ───────────► Button ──► GND
│  [  ] [ ] │                                   │
│  5V   GND │──┬────────────────────────────────┘
│  3V3      │  │                          ┌───────────────┐
│           │  │                          │    YRM100     │
└───────────┘  │                          │ 1  2  3  4  5 │
               │                          │GND EN RX TX VCC│
               │                          └─┬──────────┬─┘
               │                            │          │
               └── GND ─────────────────────┘          │
                   5V ─────────────────────────────────┘
```

> **Wiring Notes:**
> - YRM100 VCC (Pin 5) connects to the **5V pin** on the ESP32-C6 DevKit
> - YRM100 GND (Pin 1) connects to **common GND**
> - YRM100 EN (Pin 2) connects to GPIO6 (active HIGH, >1.5V to enable)
> - All signal lines (RXD, TXD, EN) are 3.3V logic and connect directly to ESP32-C6 GPIOs
> - **RGB LED uses onboard WS2812** - no external LED wiring required

---

## Bill of Materials (Test Harness)

| Qty | Component              | Part Number / Value      | Notes                     |
|-----|------------------------|--------------------------|---------------------------|
| 1   | ESP32-C6 Dev Board     | ESP32-C6-DevKitC-1       | Includes onboard WS2812   |
| 1   | YRM100 RFID Module     | YRM100 (SBComponents 3dBi or Generic 2dBi) | With antenna |
| 1   | Momentary Push Button  | 6mm tactile switch       | Normally open             |
| 1   | Breadboard             | Half-size or full-size   | For prototyping           |
| 1   | USB-C Cable            | Data-capable             | Power and programming     |
| 6   | Jumper Wires           | Male-to-male             | Various colors            |
| 1   | RFID Test Tag          | UHF EPC Gen2             | Saturday prefix: 5356...  |

> **Note:** No external RGB LED or resistors needed - using the onboard WS2812.

---

## Troubleshooting

### No Serial Output
- Check USB cable supports data (not charge-only)
- Verify correct COM port selected
- Try different USB port

### RFID Not Responding
- Verify RFID_EN (GPIO6) is HIGH
- Check UART wiring (TX↔RX crossover)
- Confirm 5V power to YRM100 (not 3.3V!)
- Check baud rate is 115200
- Measure current draw - should be ~30mA idle, ~200mA during TX

### LED Not Working (Onboard WS2812)
- Verify using correct GPIO (GPIO8)
- Check that `led_strip` component is enabled in menuconfig
- Ensure RMT peripheral is not conflicting with other uses
- Try basic test: set full red (255, 0, 0) and call `led_strip_refresh()`
- Check DevKit board revision (WS2812 circuit varies slightly)

### Button Not Detected
- Verify internal pull-up is enabled in code
- Check button connects GPIO18 to GND when pressed
- Test with multimeter in continuity mode

---

## Document History

| Version | Date       | Author | Changes                                      |
|---------|------------|--------|----------------------------------------------|
| 1.0.0   | 2025-01-XX | -      | Initial version                              |
| 1.1.0   | 2025-01-XX | -      | Changed YRM100 power from 3.3V to 5V rail    |
| 1.2.0   | 2025-01-XX | -      | Switched to onboard WS2812 LED (GPIO8)       |
| 1.3.0   | 2025-01-XX | -      | Fixed UART pin assignments (GPIO4=RX, GPIO5=TX) |
| 1.4.0   | 2025-01-XX | -      | Fixed USB pin assignments (GPIO12=D-, GPIO13=D+) |
| 1.5.0   | 2025-01-XX | -      | Fixed YRM100 pinout per manufacturer specs       |
| 1.6.0   | 2026-01-XX | -      | Added support for two YRM100 module variants (SBComponents 3dBi, Generic 2dBi) |

---

*This document is for Saturday Vinyl internal use.*
