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

**Phase 0: Project Setup** - Complete

The project structure is in place with:
- ESP-IDF project skeleton
- Component placeholders
- LED blink test in main.c
- OTA-capable partition table

### Phase Checklist

- [x] Phase 0: Project Setup
- [ ] Phase 1: Hardware Bring-Up
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
