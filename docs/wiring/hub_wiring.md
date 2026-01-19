# Saturday Vinyl Hub - Wiring Reference

**Document Version:** 2.0.0
**Hardware Revision:** Dev Kit (ESP32-S3-DevKitC-1 + ESP32-H2-DevKitM-1 + YRM100)
**Last Updated:** 2026-01-16

> **Note:** This document provides a quick wiring reference for test harness assembly.
> For the authoritative schematic, see `hub_schematic.sch` (Fusion/EAGLE format).

---

## Overview

The Saturday Hub uses a **dual-SoC architecture** to solve WiFi/Thread radio coexistence:

| SoC | Role | Responsibilities |
|-----|------|------------------|
| **ESP32-S3** | Master MCU | WiFi, BLE provisioning, RFID, cloud sync, USB service mode, UI |
| **ESP32-H2** | Thread Co-processor | Thread Border Router, CoAP server for crate communication |

The two SoCs communicate via UART. The S3 controls the H2's power and boot mode.

---

## System Block Diagram

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                  Saturday Vinyl Hub                      │
                                    │                                                          │
┌─────────────┐                     │  ┌───────────────────────────────────────────────────┐  │
│   USB-C     │───── 5V ──────┬────►│  │              ESP32-S3 (Master)                    │  │
│  Connector  │               │     │  │                                                   │  │
│   (S3)      │◄──── USB ────►│     │  │  WiFi 2.4GHz │ BLE 5.0 │ USB Service Mode        │  │
└─────────────┘               │     │  │                                                   │  │
                              │     │  │  GPIO0  ◄──── BOOT Button (active low)            │  │
┌─────────────┐               │     │  │  GPIO5  ────► RFID Enable (active high)           │  │
│   YRM100    │◄──── 5V ──────┘     │  │  GPIO6  ────► H2 Enable/Reset (active low)        │  │
│    RFID     │◄──── TX ───────────►│  │  GPIO7  ────► H2 Boot Mode                        │  │
│   Module    │◄──── RX ───────────►│  │  GPIO15 ────► H2 RX (UART2 TX)                    │  │
│             │◄──── EN ───────────►│  │  GPIO16 ◄──── H2 TX (UART2 RX)                    │  │
└─────────────┘                     │  │  GPIO17 ────► RFID RX (UART1 TX)                  │  │
                                    │  │  GPIO18 ◄──── RFID TX (UART1 RX)                  │  │
┌─────────────┐                     │  │  GPIO48 ────► WS2812 RGB LED (onboard)            │  │
│  WS2812     │◄── Onboard ────────►│  │                                                   │  │
│  RGB LED    │     (GPIO48)        │  └───────────────────────────────────────────────────┘  │
└─────────────┘                     │                            │                            │
                                    │                      UART  │                            │
                                    │                            ▼                            │
                                    │  ┌───────────────────────────────────────────────────┐  │
                                    │  │              ESP32-H2 (Thread BR)                  │  │
                                    │  │                                                   │  │
                                    │  │  Thread 802.15.4 │ CoAP Server                    │  │
                                    │  │                                                   │  │
                                    │  │  GPIO23 ◄──── S3 TX (UART0 RX)                    │  │
                                    │  │  GPIO24 ────► S3 RX (UART0 TX)                    │  │
                                    │  │  GPIO4  ◄──── Boot Mode (from S3 GPIO7)           │  │
                                    │  │  EN     ◄──── Reset (from S3 GPIO6)               │  │
                                    │  │                                                   │  │
                                    │  └───────────────────────────────────────────────────┘  │
                                    │                                                          │
                                    └──────────────────────────────────────────────────────────┘
```

> **Architecture Note:** The dual-SoC design was chosen because ESP32-C6 cannot run WiFi
> and Thread 802.15.4 simultaneously (shared radio). The S3 handles WiFi/BLE while the
> H2 provides dedicated Thread support.

---

## ESP32-S3 Pin Assignments (Master)

| GPIO | Function      | Direction | Connect To              | Notes                          |
|------|---------------|-----------|-------------------------|--------------------------------|
| 0    | BUTTON        | Input     | BOOT button             | Active LOW, internal pull-up   |
| 5    | RFID_EN       | Output    | YRM100 Pin 2 (EN)       | Active HIGH to enable module   |
| 6    | H2_EN         | Output    | H2 EN pin               | Active LOW reset               |
| 7    | H2_BOOT       | Output    | H2 GPIO4                | Boot mode select               |
| 15   | UART2_TX      | Output    | H2 GPIO23 (RX)          | S3 → H2 commands               |
| 16   | UART2_RX      | Input     | H2 GPIO24 (TX)          | H2 → S3 responses              |
| 17   | UART1_TX      | Output    | YRM100 Pin 3 (RXD)      | RFID commands                  |
| 18   | UART1_RX      | Input     | YRM100 Pin 4 (TXD)      | RFID responses                 |
| 19   | USB_D-        | Bidir     | USB-C connector         | Native USB data minus          |
| 20   | USB_D+        | Bidir     | USB-C connector         | Native USB data plus           |
| 48   | LED_DATA      | Output    | Onboard WS2812          | Addressable RGB LED            |

> **Note:** GPIO48 on ESP32-S3-DevKitC-1 has an onboard WS2812 RGB LED.
> The BOOT button is on GPIO0.

---

## ESP32-H2 Pin Assignments (Thread Co-processor)

| GPIO | Function      | Direction | Connect To              | Notes                          |
|------|---------------|-----------|-------------------------|--------------------------------|
| 4    | BOOT_MODE     | Input     | S3 GPIO7                | Boot mode select (from S3)     |
| 23   | UART0_RX      | Input     | S3 GPIO15 (TX)          | Commands from S3               |
| 24   | UART0_TX      | Output    | S3 GPIO16 (RX)          | Responses to S3                |
| EN/RST | CHIP_EN     | Input     | S3 GPIO6                | Active LOW reset (labeled "RST" on DevKitM-1) |

> **Note:** The H2's UART0 is used for S3 communication. USB is available for
> debugging/flashing during development but not used in production.
>
> **Pin naming:** The ESP32-H2-DevKitM-1 labels the chip enable pin as "RST" (Reset).
> This is the same signal that Espressif schematics call "EN" (Chip Enable). Both names
> refer to the active-low reset line. Connect S3 GPIO6 to the H2's RST pin.

---

## S3 ↔ H2 Interconnect

```
    ESP32-S3                                ESP32-H2
    ────────                                ────────
    GPIO6  (H2_EN)    ──────────────────►   EN/RST (Chip Enable, labeled "RST" on DevKitM-1)
    GPIO7  (H2_BOOT)  ──────────────────►   GPIO4 (Boot Mode)
    GPIO15 (UART2_TX) ──────────────────►   GPIO23 (UART0_RX)
    GPIO16 (UART2_RX) ◄──────────────────   GPIO24 (UART0_TX)
    GND               ──────────────────    GND
    3V3               ──────────────────►   3V3 (or from separate regulator)
```

### UART Configuration (S3 ↔ H2)

| Parameter  | Value   |
|------------|---------|
| Baud Rate  | 115200  |
| Data Bits  | 8       |
| Parity     | None    |
| Stop Bits  | 1       |
| Flow Ctrl  | None    |

### H2 Boot Control

| S3 GPIO6 (EN) | S3 GPIO7 (BOOT) | H2 Mode           |
|---------------|-----------------|-------------------|
| LOW           | X               | Reset (held)      |
| HIGH          | LOW             | Normal boot       |
| HIGH          | HIGH            | Download mode     |

---

## YRM100 RFID Module Wiring

The YRM100 is a UHF RFID module using the M100 protocol.

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

Both modules share identical electrical specifications:
- Working voltage: DC 3.5V - 5V
- Output power range: 15-26 dBm (**minimum 15 dBm**)
- Baud rate: 115200 BPS (default)
- Air interface: EPCglobal UHF Class 1 Gen 2 / ISO 18000-6C

### Connection Table (ESP32-S3)

| YRM100 Pin | Name | Connect To        | Wire Color (SBC) | Wire Color (Generic) |
|------------|------|-------------------|------------------|----------------------|
| 1          | GND  | Common GND        | Black            | Blue                 |
| 2          | EN   | ESP32-S3 GPIO5    | Green            | Green                |
| 3          | RXD  | ESP32-S3 GPIO17   | Orange           | Yellow               |
| 4          | TXD  | ESP32-S3 GPIO18   | Yellow           | Black                |
| 5          | VCC  | USB 5V rail       | Red              | Red                  |

> **Important:** The YRM100 VCC must be connected to **5V** (from USB), not 3.3V.
> The module requires 3.5-5V and draws up to 260mA peak during RF transmission.

### UART Configuration (RFID)

| Parameter  | Value   |
|------------|---------|
| Baud Rate  | 115200  |
| Data Bits  | 8       |
| Parity     | None    |
| Stop Bits  | 1       |

---

## RGB LED (Onboard WS2812)

The ESP32-S3-DevKitC-1 includes an onboard WS2812 addressable RGB LED on **GPIO48**.
**No external wiring is required.**

### Specifications

| Parameter       | Value                                    |
|-----------------|------------------------------------------|
| Type            | WS2812 (addressable RGB)                 |
| GPIO            | 48                                       |
| Protocol        | Single-wire, 800 kHz                     |
| Driver          | ESP-IDF RMT peripheral + `led_strip`     |
| LED Count       | 1                                        |

### LED Status Indicators

| Color | Pattern | Meaning |
|-------|---------|---------|
| White | Pulse | Service mode (awaiting provisioning) |
| Blue | Slow blink | BLE advertising |
| Blue | Solid | BLE connected |
| Blue | Fast blink | Connecting to WiFi |
| Cyan | Flash | WiFi connected |
| Green | Pulse | Normal operation (WiFi connected) |
| Yellow | Slow blink | WiFi disconnected |
| Red | Fast blink | Error / Factory reset |

---

## Button Wiring

The ESP32-S3-DevKitC-1 has a **BOOT button on GPIO0**. For production, an external
button can be wired the same way.

### Schematic

```
                           3.3V
                             │
                        ┌────┴────┐
                        │  10kΩ   │  (Optional - ESP32-S3 has internal pull-up)
                        └────┬────┘
                             │
                             ├──────────────────► ESP32-S3 GPIO0 (BUTTON)
                             │
                          ┌──┴──┐
                          │     │
                          │ BTN │  Momentary, Normally Open
                          │     │
                          └──┬──┘
                             │
                            GND
```

### Button Actions

| Press Duration | Action                |
|----------------|-----------------------|
| < 500ms        | Short press (confirm) |
| 3-5 seconds    | Enter BLE provisioning|
| > 10 seconds   | Factory reset         |

---

## Power Distribution

```
                                    USB-C 5V Input (S3 DevKit)
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                          ▼               ▼               │
                    ┌───────────┐   ┌───────────┐        │
                    │  ESP32-S3 │   │  YRM100   │        │
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
    │  ESP32-S3 │   │  WS2812   │   │  ESP32-H2 │       │
    │   (MCU)   │   │ (onboard) │   │  (3V3 in) │       │
    └───────────┘   └───────────┘   └───────────┘       │
                                                         │
                                    Common GND ◄─────────┘
```

### Power Budget

| Component       | Rail | Current (typical) | Current (peak) | Notes                    |
|-----------------|------|-------------------|----------------|--------------------------|
| ESP32-S3        | 3.3V | 100mA             | 350mA          | WiFi + BLE active        |
| ESP32-H2        | 3.3V | 25mA              | 80mA           | Thread active            |
| YRM100 (idle)   | 5V   | 30mA              | 30mA           | Direct from USB 5V       |
| YRM100 (TX)     | 5V   | 200mA             | 260mA          | At 26 dBm output         |
| WS2812 LED      | 3.3V | 1mA               | 60mA           | Onboard, max ~20mA/color |
| **Total 3.3V**  |      | **~126mA**        | **~490mA**     | Within LDO capacity      |
| **Total 5V**    |      | **~330mA**        | **~650mA**     | Need good USB source     |

> **Note:** A quality USB-C cable and 1A+ source is recommended. For development with
> both DevKits, each can be powered from separate USB ports.

---

## Development Wiring (Two DevKits)

For development, use two separate DevKits connected via jumper wires:

```
    ESP32-S3-DevKitC-1                    ESP32-H2-DevKitM-1
    ══════════════════                    ══════════════════

    USB-C ◄─── Power + Flash/Monitor      USB-C ◄─── Power + Flash/Monitor

    GPIO6  ─────────────────────────────► RST pin (labeled "EN" in schematics)
    GPIO7  ─────────────────────────────► GPIO4
    GPIO15 ─────────────────────────────► GPIO23
    GPIO16 ◄───────────────────────────── GPIO24
    GND    ─────────────────────────────► GND


    GPIO5  ──────┐
    GPIO17 ──────┼───────────► YRM100 Module
    GPIO18 ◄─────┤              (5V from S3 DevKit 5V pin)
    5V     ──────┤
    GND    ──────┘
```

### Breadboard Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            Breadboard                                    │
│                                                                          │
│  ┌──────────────────┐              ┌──────────────────┐                 │
│  │   ESP32-S3       │              │    ESP32-H2      │                 │
│  │   DevKitC-1      │              │    DevKitM-1     │                 │
│  │                  │              │                  │                 │
│  │  USB-C (power)   │              │  USB-C (power)   │                 │
│  │                  │              │                  │                 │
│  │  GPIO6  ─────────┼──────────────┼─► RST            │                 │
│  │  GPIO7  ─────────┼──────────────┼─► GPIO4          │                 │
│  │  GPIO15 ─────────┼──────────────┼─► GPIO23         │                 │
│  │  GPIO16 ◄────────┼──────────────┼── GPIO24         │                 │
│  │  GND    ─────────┼──────────────┼── GND            │                 │
│  │                  │              │                  │                 │
│  │  GPIO5  ───┐     │              └──────────────────┘                 │
│  │  GPIO17 ───┼─────┼──────► YRM100                                     │
│  │  GPIO18 ◄──┤     │        ┌───────────────┐                          │
│  │  5V     ───┼─────┼───────►│ 1  2  3  4  5 │                          │
│  │  GND    ───┴─────┼───────►│GND EN RX TX VCC                          │
│  │                  │        └───────────────┘                          │
│  └──────────────────┘                                                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Bill of Materials (Test Harness)

| Qty | Component              | Part Number / Value           | Notes                     |
|-----|------------------------|-------------------------------|---------------------------|
| 1   | ESP32-S3 Dev Board     | ESP32-S3-DevKitC-1-N8R8       | 8MB Flash, 8MB PSRAM, onboard WS2812 |
| 1   | ESP32-H2 Dev Board     | ESP32-H2-DevKitM-1            | Thread/802.15.4 support   |
| 1   | YRM100 RFID Module     | YRM100 (SBC 3dBi or Generic 2dBi) | With antenna          |
| 1   | Breadboard             | Half-size or full-size        | For prototyping           |
| 2   | USB-C Cables           | Data-capable                  | Power and programming     |
| 10  | Jumper Wires           | Male-to-male                  | Various colors            |
| 1   | RFID Test Tag          | UHF EPC Gen2                  | Saturday prefix: 5356...  |

---

## Troubleshooting

### No Serial Output (S3)
- Check USB cable supports data (not charge-only)
- Verify correct COM port selected
- Try the UART USB port (not the native USB port) for flash/monitor

### No Serial Output (H2)
- Flash via H2's own USB port for initial programming
- After integration, H2 UART is used for S3 communication
- Check S3 GPIO6 is HIGH (H2 not held in reset)

### RFID Not Responding
- Verify RFID_EN (S3 GPIO5) is HIGH
- Check UART wiring (TX↔RX crossover: S3 GPIO17 → YRM100 RXD)
- Confirm 5V power to YRM100 (not 3.3V!)
- Check baud rate is 115200

### H2 Not Responding to S3
- Check UART crossover: S3 GPIO15 → H2 GPIO23, S3 GPIO16 ← H2 GPIO24
- Verify S3 GPIO6 is HIGH (H2 not held in reset)
- Verify S3 GPIO7 is LOW (normal boot, not download mode)
- Check common GND connection

### LED Not Working (S3 Onboard WS2812)
- Verify using correct GPIO (GPIO48)
- Check that `led_strip` component is enabled
- Ensure RMT peripheral is not conflicting

### Button Not Detected
- Verify internal pull-up is enabled in code
- On DevKitC-1, use the BOOT button (GPIO0)
- Test with multimeter in continuity mode

---

## Document History

| Version | Date       | Author | Changes                                      |
|---------|------------|--------|----------------------------------------------|
| 1.0.0   | 2025-01-XX | -      | Initial version (ESP32-C6 single-SoC)        |
| 1.6.0   | 2026-01-XX | -      | Added YRM100 module variants                 |
| 2.0.0   | 2026-01-16 | -      | **Major revision: Dual-SoC architecture (ESP32-S3 + ESP32-H2)** |

---

*This document is for Saturday Vinyl internal use.*
