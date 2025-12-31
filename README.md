# Saturday Vinyl Hub Firmware

ESP32-C6 based firmware for the Saturday Vinyl Hub - a Thread Border Router and "Now Playing" detector for vinyl record enthusiasts.

## Overview

The Saturday Vinyl Hub performs two primary functions:

1. **Thread Border Router** - Bridges the Thread mesh network (connecting battery-powered RFID crates) to the IP network (Wi-Fi) and the Saturday cloud (Supabase)
2. **Now Playing Detection** - Uses an integrated UHF RFID reader (YRM100 module) to detect which record is currently on the user's turntable

## Hardware

- **MCU:** ESP32-C6 (Wi-Fi 6 + Thread/802.15.4 + BLE 5.0)
- **RFID Module:** YRM100 UHF RFID (ISO 18000-6C / EPC Gen2)
- **Interface:** USB-C for power and serial console

### Pin Assignments

| GPIO | Function | Description |
|------|----------|-------------|
| 0 | UART0_TX | Debug console TX |
| 1 | UART0_RX | Debug console RX |
| 4 | UART1_TX | RFID module RX |
| 5 | UART1_RX | RFID module TX |
| 6 | RFID_EN | RFID module enable |
| 8 | LED_R | RGB LED - Red (PWM) |
| 9 | LED_G | RGB LED - Green (PWM) |
| 10 | LED_B | RGB LED - Blue (PWM) |
| 18 | BUTTON | Multi-purpose button |

## Development Environment Setup

### Prerequisites

- **ESP-IDF v5.2 or later** (v5.2+ required for ESP32-C6 Thread support)
- **Python 3.8+**
- **Git**
- **USB-C cable** for flashing and debugging

### Installing ESP-IDF (macOS/Linux)

```bash
# Create a directory for ESP-IDF
mkdir -p ~/esp
cd ~/esp

# Clone ESP-IDF
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf

# Checkout the recommended version
git checkout v5.2.2  # or latest stable v5.2.x

# Install ESP-IDF tools for ESP32-C6
./install.sh esp32c6

# Set up environment variables
# Add this to your ~/.bashrc or ~/.zshrc:
alias get_idf='. $HOME/esp/esp-idf/export.sh'
```

### Installing ESP-IDF (Windows)

Download and run the ESP-IDF Tools Installer from [Espressif's website](https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/windows-setup.html).

Select ESP32-C6 as the target during installation.

### VS Code Extension (Recommended)

1. Install the [ESP-IDF Extension](https://marketplace.visualstudio.com/items?itemName=espressif.esp-idf-extension) for VS Code
2. Run `ESP-IDF: Configure ESP-IDF Extension` from the command palette
3. Point it to your ESP-IDF installation

## Building the Firmware

```bash
# Activate ESP-IDF environment
get_idf  # or source ~/esp/esp-idf/export.sh

# Navigate to project directory
cd sv-hub-firmware

# Set target to ESP32-C6 (only needed once)
idf.py set-target esp32c6

# Build the project
idf.py build
```

## Flashing and Monitoring

```bash
# Flash to device (replace PORT with your serial port)
# macOS: /dev/cu.usbserial-* or /dev/cu.usbmodem*
# Linux: /dev/ttyUSB0 or /dev/ttyACM0
# Windows: COM3 (or similar)
idf.py -p PORT flash

# Monitor serial output
idf.py -p PORT monitor

# Flash and monitor in one command
idf.py -p PORT flash monitor

# Exit monitor with Ctrl+]
```

### Finding Your Serial Port

**macOS:**
```bash
ls /dev/cu.usb*
```

**Linux:**
```bash
ls /dev/ttyUSB* /dev/ttyACM*
```

**Windows:**
Check Device Manager under "Ports (COM & LPT)"

### Serial Port Permissions (Linux)

If you get permission errors on Linux:
```bash
sudo usermod -a -G dialout $USER
# Log out and back in for changes to take effect
```

## Project Structure

```
sv-hub-firmware/
├── CMakeLists.txt              # Top-level CMake configuration
├── sdkconfig.defaults          # Default SDK configuration
├── partitions.csv              # Partition table (OTA support)
├── main/
│   ├── CMakeLists.txt
│   ├── main.c                  # Entry point
│   ├── app_config.h            # Compile-time configuration
│   └── Kconfig.projbuild       # Menuconfig options
├── components/
│   ├── network/                # Wi-Fi, Thread BR, CoAP
│   ├── rfid/                   # YRM100 driver, Now Playing logic
│   ├── cloud/                  # Supabase client
│   ├── provisioning/           # BLE and serial provisioning
│   ├── ui/                     # RGB LED and button handling
│   └── config/                 # NVS configuration storage
├── docs/
│   ├── developers_guide.md     # Technical specification
│   └── implementation_plan.md  # Development phases
└── test/                       # Unit tests
```

## Configuration

### Using menuconfig

```bash
idf.py menuconfig
```

Navigate to `Saturday Vinyl Hub Configuration` to adjust:
- RFID polling interval
- RF power level
- Debounce timing
- LED brightness

### Important SDK Config Options

The project uses `sdkconfig.defaults` to set sensible defaults. Key settings:

- **Partition Table:** Custom OTA-capable layout
- **Flash Size:** 4MB
- **OpenThread:** Enabled with Border Router support
- **NimBLE:** Enabled for BLE provisioning
- **Watchdog:** 30-second timeout

## Current Status

**Phase 1: Hardware Bring-Up** - Complete

All hardware peripherals have been validated and are functional:
- RGB LED with PWM control and pattern generation
- Button with debounced input and press duration detection
- RFID module UART communication

### Phase Checklist

- [x] Phase 0: Project Setup
- [x] Phase 1: Hardware Bring-Up
- [ ] Phase 2: RFID Detection
- [ ] Phase 3: Now Playing Logic
- [ ] Phase 4: Wi-Fi Connectivity
- [ ] Phase 5: Supabase Integration
- [ ] Phase 6: Serial Provisioning
- [ ] Phase 7: BLE Provisioning
- [ ] Phase 8: Thread Border Router
- [ ] Phase 9: CoAP Server
- [ ] Phase 10: Crate Integration
- [ ] Phase 11: OTA Updates
- [ ] Phase 12: Hardening
- [ ] Phase 13: Production Ready

## Component API Reference

### LED Manager (`components/ui/led_manager.c`)

PWM-based RGB LED control with pattern support.

**Features:**
- 8-bit PWM resolution at 5kHz (smooth, flicker-free)
- Color presets: OFF, RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA, WHITE, ORANGE
- Patterns: SOLID, BLINK_SLOW (1Hz), BLINK_FAST (2Hz), PULSE, FLASH
- Brightness control (0-255)
- Thread-safe with mutex protection
- Background task for pattern generation

**Usage:**
```c
#include "led_manager.h"

led_init();
led_set_state(LED_COLOR_GREEN, LED_PATTERN_SOLID, 0);
led_set_brightness(128);  // 50% brightness
led_flash(LED_COLOR_BLUE, 200);  // Brief 200ms flash
```

**Hardware Notes:**
- Assumes common-anode RGB LED (active low)
- GPIOs 8 (R), 9 (G), 10 (B)

### Button Handler (`components/ui/button_handler.c`)

Debounced button input with press duration classification.

**Features:**
- 50ms software debounce
- Press duration detection:
  - SHORT: < 500ms
  - LONG: 3-5 seconds (for entering provisioning mode)
  - FACTORY: > 10 seconds (for factory reset)
- GPIO interrupt-driven with event queue
- Callback registration for press events

**Usage:**
```c
#include "button_handler.h"

void my_callback(button_press_t press_type) {
    if (press_type == BUTTON_PRESS_LONG) {
        // Enter provisioning mode
    }
}

button_init();
button_register_callback(my_callback);
```

**Hardware Notes:**
- GPIO18 with internal pull-up enabled
- Active low (pressed = 0)

### YRM100 RFID Driver (`components/rfid/yrm100_driver.c`)

UART communication with the YRM100 UHF RFID module.

**Features:**
- Binary frame protocol with checksum validation
- Module enable/disable control
- Commands implemented:
  - Get firmware version
  - Get/Set RF power (0-30 dBm)
  - Single poll for tags
  - Start/Stop continuous polling
- Thread-safe UART access
- Raw send/receive for debugging

**Usage:**
```c
#include "yrm100_driver.h"

yrm100_init();
yrm100_enable(true);

char version[32];
yrm100_get_firmware_version(version, sizeof(version));

yrm100_set_rf_power(10);  // 10 dBm

esp_err_t ret = yrm100_single_poll();
if (ret == ESP_OK) {
    // Tag detected
}
```

**Hardware Notes:**
- UART1: GPIO4 (TX), GPIO5 (RX), 115200 baud 8N1
- GPIO6: Enable pin (active high)
- Allow 100ms after enabling before sending commands

**Frame Format:**
```
[0xBB] [Type] [Cmd] [PL_MSB] [PL_LSB] [Params...] [Checksum] [0x7E]
```

## Testing Phase 1 Components

When the firmware boots, it:
1. Displays a white pulsing LED during initialization
2. Switches to solid green when ready
3. Starts RFID polling every 2 seconds

**Button Test:**
- Short press: Cycles through LED colors
- Long press (3-5s): Blue slow blink (provisioning demo)
- Very long press (>10s): Red fast blink (factory reset demo)

**RFID Test:**
- Firmware version is queried on startup
- Green flash when tag is detected
- Orange flash if module doesn't respond (check wiring)

**Expected Console Output:**
```
I (xxx) SV_HUB: Saturday Vinyl Hub Firmware v0.1.0
I (xxx) SV_HUB: Phase 1: Hardware Bring-Up
I (xxx) LED_MGR: LED manager initialized successfully
I (xxx) BUTTON: Button handler initialized successfully
I (xxx) YRM100: YRM100 driver initialized successfully
I (xxx) YRM100: YRM100 module enabled
I (xxx) YRM100: Firmware version: ...
```

## Troubleshooting

### Build Fails with "esp32c6: command not found"

Make sure you've sourced the ESP-IDF export script:
```bash
source ~/esp/esp-idf/export.sh
# or use the alias:
get_idf
```

### "Failed to connect to ESP32-C6"

1. Check USB cable is data-capable (not charge-only)
2. Hold BOOT button while pressing RESET, then release both
3. Try a different USB port
4. Check serial port permissions (Linux)

### "No such file or directory: partitions.csv"

Run from the project root directory, not from `main/` or `build/`.

### OpenThread build errors

Ensure you're using ESP-IDF v5.2+ which has improved ESP32-C6 OpenThread support.

## Documentation

- [Developer's Guide](docs/developers_guide.md) - Complete technical specification
- [Implementation Plan](docs/implementation_plan.md) - Phased development checklist
- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/v5.2.2/esp32c6/)
- [ESP32-C6 Datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-c6_datasheet_en.pdf)

## License

Proprietary - Saturday Vinyl, Inc.
