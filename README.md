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
| 4 | UART1_RX | RFID module TXD (ESP32 receives from YRM100) |
| 5 | UART1_TX | RFID module RXD (ESP32 transmits to YRM100) |
| 6 | RFID_EN | RFID module enable (active HIGH, needs pull-up) |
| 8 | LED_WS2812 | Onboard WS2812 addressable RGB LED |
| 18 | BUTTON | Multi-purpose button |

### YRM100 RFID Module Wiring

| YRM100 Pin | Wire Color | ESP32-C6 GPIO | Description |
|------------|------------|---------------|-------------|
| 1 (GND) | Red | GND | Ground |
| 2 (EN) | Black | GPIO6 | Enable (HIGH = active) |
| 3 (RXD) | Yellow | GPIO5 | Module receives from ESP32 |
| 4 (TXD) | Green | GPIO4 | Module transmits to ESP32 |
| 5 (VCC) | Blue | 3.3V | Power (3-5V) |

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

**Phase 4: Wi-Fi Connectivity** - Complete

All Wi-Fi connectivity functionality has been implemented:
- Wi-Fi station mode with event-based connection management
- Auto-reconnect with exponential backoff (1s to 60s max)
- Wi-Fi credential storage in NVS
- HTTPS client with TLS certificate bundle
- LED feedback for connection states
- Internet connectivity testing

### Phase Checklist

- [x] Phase 0: Project Setup
- [x] Phase 1: Hardware Bring-Up
- [x] Phase 2: RFID Detection
- [x] Phase 3: Now Playing Logic
- [x] Phase 4: Wi-Fi Connectivity
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

WS2812 addressable RGB LED control with pattern support.

**Features:**
- WS2812 (NeoPixel) protocol via RMT peripheral
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
- ESP32-C6-DevKitC-1 has onboard WS2812 on GPIO8
- Uses ESP-IDF led_strip component (espressif/led_strip managed component)
- Single addressable LED, controlled via RMT peripheral at 10MHz

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
  - Single poll for tags (with or without tag data)
  - Start/Stop continuous polling
- **Phase 2 additions:**
  - Tag data parsing (EPC, RSSI, PC word)
  - Saturday tag detection (0x5356 prefix)
  - Background polling task with callbacks
  - Polling statistics

**Basic Usage:**
```c
#include "yrm100_driver.h"

yrm100_init();
yrm100_enable(true);

char version[32];
yrm100_get_firmware_version(version, sizeof(version));

yrm100_set_rf_power(10);  // 10 dBm

// Simple poll (tag presence only)
esp_err_t ret = yrm100_single_poll();
if (ret == ESP_OK) {
    // Tag detected
}

// Poll with tag data (Phase 2)
rfid_tag_t tag;
ret = yrm100_single_poll_with_data(&tag);
if (ret == ESP_OK) {
    // tag.epc, tag.rssi, tag.is_saturday_tag available
}
```

**Background Polling (Phase 2):**
```c
#include "yrm100_driver.h"

// Callback invoked on tag detection
void on_tag_detected(const rfid_tag_t *tag, void *user_data) {
    if (tag->is_saturday_tag) {
        // Handle Saturday tag
        char epc_str[25];
        rfid_epc_to_hex_string(tag->epc, tag->epc_len, epc_str, sizeof(epc_str));
        ESP_LOGI("APP", "Saturday tag: %s", epc_str);
    }
}

// Register callback and start polling
yrm100_register_tag_callback(on_tag_detected, NULL);

yrm100_poll_config_t config = {
    .poll_interval_ms = 500,
    .rf_power_dbm = 10,
    .filter_saturday_only = true,  // Only report Saturday tags
};
yrm100_start_polling_task(&config);

// Later: get statistics
uint32_t polls, tags, saturday;
yrm100_get_poll_stats(&polls, &tags, &saturday);

// Stop polling when done
yrm100_stop_polling_task();
```

**Hardware Notes:**
- UART1: GPIO5 (TX to YRM100 RXD), GPIO4 (RX from YRM100 TXD), 115200 baud 8N1
- GPIO6: Enable pin (active HIGH, configure with internal pull-up)
- Allow 500ms after enabling before sending commands (YRM100 boot time)

**Frame Format:**
```
[0xBB] [Type] [Cmd] [PL_MSB] [PL_LSB] [Params...] [Checksum] [0x7E]

Type values:
  0x00 = Command (host to module)
  0x01 = Response (module to host)
  0x02 = Notice (unsolicited from module, e.g., tag detected)

Checksum = (Type + Cmd + PL_MSB + PL_LSB + Params[0..n]) & 0xFF

Common commands:
  0x03 = Get Firmware Version (send param 0x00 for hardware info)
  0x22 = Single Poll (inventory one tag)
  0xB0 = Set RF Power
  0xB1 = Get RF Power
  0x27 = Start Multiple Poll
  0x28 = Stop Multiple Poll
```

**Common Error Codes (returned as 0xFF response):**
| Code | Meaning |
|------|---------|
| 0x15 | No tag in RF field |
| 0x16 | Tag read error |
| 0x09 | Parameter error |

### RFID Protocol Codec (`components/rfid/rfid_protocol.c`)

Low-level frame building and parsing for the YRM100 module. Added in Phase 2.

**Features:**
- Frame building with automatic checksum
- Frame parsing with validation
- Tag data extraction from poll responses
- Saturday tag prefix validation
- EPC to hex string conversion
- RSSI to dBm conversion

**Usage:**
```c
#include "rfid_protocol.h"

// Build a command frame
uint8_t frame[32];
size_t len = rfid_build_frame(RFID_CMD_SINGLE_POLL, NULL, 0, frame, sizeof(frame));

// Parse a received frame
rfid_frame_t parsed;
if (rfid_parse_frame(rx_buf, rx_len, &parsed)) {
    if (parsed.type == RFID_FRAME_TYPE_NOTICE) {
        // Tag notice received
        rfid_tag_t tag;
        if (rfid_parse_tag(&parsed, &tag)) {
            // Use tag.epc, tag.rssi, tag.is_saturday_tag
        }
    }
}

// Convert EPC to string
char epc_str[25];
rfid_epc_to_hex_string(tag.epc, tag.epc_len, epc_str, sizeof(epc_str));

// Convert RSSI to dBm
int8_t rssi_dbm = rfid_rssi_to_dbm(tag.rssi);
```

**Saturday Tag Format:**
```
┌─────────────┬─────────────────────────────────────────┐
│   Prefix    │              Random Data                │
│  (2 bytes)  │              (10 bytes)                 │
├─────────────┼─────────────────────────────────────────┤
│    5356     │    XXXX XXXX XXXX XXXX XXXX             │
│   ("SV")    │    (80 random bits)                     │
└─────────────┴─────────────────────────────────────────┘
Example: 5356A1B2C3D4E5F67890ABCD
```

### Wi-Fi Manager (`components/network/wifi_manager.c`)

Wi-Fi station mode connection management with auto-reconnect. Added in Phase 4.

**Features:**
- Station mode initialization and connection
- Event-based state notifications via WIFI_MANAGER_EVENTS
- Auto-reconnect with exponential backoff (1s, 2s, 4s, ... max 60s)
- Connection statistics tracking (attempts, disconnects, RSSI)
- Credential storage integration with config_store

**Usage:**
```c
#include "wifi_manager.h"
#include "config_store.h"

// Store credentials (typically done during provisioning)
config_set_wifi("MyNetwork", "MyPassword");

// Initialize Wi-Fi and connect
wifi_init();
wifi_connect_stored();  // Uses stored credentials

// Or connect directly
wifi_connect("MyNetwork", "MyPassword");

// Check connection status
if (wifi_is_connected()) {
    char ip[16];
    wifi_get_ip_string(ip, sizeof(ip));
    printf("Connected with IP: %s\n", ip);
}

// Get detailed status
wifi_manager_status_t status;
wifi_get_status(&status);
printf("RSSI: %d dBm, Attempts: %lu\n", status.rssi, status.connect_attempts);
```

**Event Handling:**
```c
static void on_wifi_event(void *arg, esp_event_base_t base,
                          int32_t event_id, void *event_data) {
    switch (event_id) {
        case WIFI_MANAGER_EVENT_CONNECTED:
            // Connected with IP
            break;
        case WIFI_MANAGER_EVENT_DISCONNECTED:
            // Lost connection, auto-reconnecting
            break;
        case WIFI_MANAGER_EVENT_CONNECTION_FAILED:
            // Bad credentials or network not found
            break;
    }
}

esp_event_handler_register(WIFI_MANAGER_EVENTS, ESP_EVENT_ANY_ID,
                           on_wifi_event, NULL);
```

**LED States:**
| State | LED Pattern | Description |
|-------|------------|-------------|
| Connecting | Yellow pulse | Attempting to connect |
| Connected | Cyan flash, then dim green | Successfully connected |
| Reconnecting | Orange slow blink | Lost connection, retrying |
| Failed | Red slow blink | Bad credentials or network not found |

### HTTP Client (`components/network/http_client.c`)

Simple HTTP/HTTPS client for REST API communication. Added in Phase 4.

**Features:**
- HTTP GET and POST requests
- HTTPS with ESP certificate bundle (no manual cert setup)
- JSON POST support with Content-Type header
- Response buffering up to 4KB
- Request timing measurement
- Connectivity testing

**Usage:**
```c
#include "http_client.h"

http_client_init();

// Simple GET request
http_response_t response;
if (http_get("https://api.example.com/data", &response, 5000) == ESP_OK) {
    printf("Status: %d, Body: %s\n", response.status_code, response.body);
    http_response_free(&response);
}

// POST JSON
const char *json = "{\"key\": \"value\"}";
if (http_post_json("https://api.example.com/data", json, &response, 10000) == ESP_OK) {
    printf("Response: %s\n", response.body);
    http_response_free(&response);
}

// Test internet connectivity
if (http_test_connectivity() == ESP_OK) {
    printf("Internet access confirmed\n");
}
```

**Important Notes:**
- Always call `http_response_free()` after processing a response
- Requires Wi-Fi to be connected before making requests
- Uses Cloudflare's 1.1.1.1 for connectivity testing (HTTPS)
- TLS certificates are included via ESP-IDF's certificate bundle

## Configuring Wi-Fi Credentials

Since provisioning (Phase 6-7) is not yet implemented, you can configure Wi-Fi credentials for testing using one of these methods:

### Method 1: Hardcode in Code (Development Only)

Add this to `main.c` before calling `wifi_connect_stored()`:
```c
// Store test credentials (do this once, they persist in NVS)
config_set_wifi("YourSSID", "YourPassword");
```

### Method 2: Use IDF Monitor Console

You can add a simple console command to set credentials at runtime. This will be replaced by proper provisioning in Phase 6-7.

### Method 3: Flash with Pre-configured NVS

Create a CSV file with credentials and flash to NVS partition using `nvs_partition_gen.py`.

## Testing

### Boot Sequence

When the firmware boots, it:
1. Displays a white pulsing LED during initialization
2. Initializes hardware (LED, button, RFID)
3. Shows yellow pulse while connecting to Wi-Fi (if credentials stored)
4. Flashes cyan when Wi-Fi connected, then starts RFID polling
5. Switches to dim green solid for idle state

### Button Test
- Short press: Cycles through LED colors
- Long press (3-5s): Blue slow blink (provisioning mode - demo)
- Very long press (>10s): Red fast blink (factory reset - demo)

### Wi-Fi Test (Phase 4)
- With valid credentials: Yellow pulse → Cyan flash → Internet test → Dim green
- With invalid credentials: Yellow pulse → Red blink (failed)
- Router disconnect: Orange slow blink (reconnecting)
- After reconnect: Cyan flash → Dim green

### RFID Test
- Firmware version is queried on startup
- Green flash when Saturday tag (0x5356 prefix) detected and confirmed
- Tag removed: Cyan flash, then dim green idle

### Now Playing (Phase 3)
When a Saturday tag is detected and confirmed:
```
I (xxx) SV_HUB: >>> NOW PLAYING: 5356A1B2C3D4E5F67890ABCD (RSSI: -45 dBm)
```
When removed:
```
I (xxx) SV_HUB: <<< STOPPED PLAYING: 5356A1B2C3D4E5F67890ABCD (duration: 180000 ms)
```

### Health Check Output
Every 10 seconds:
```
I (xxx) SV_HUB: Health: heap=280000 bytes, uptime=60s, wifi=connected, ip=192.168.1.100
```

Every 60 seconds (with Wi-Fi connected):
```
I (xxx) SV_HUB: Wi-Fi: ssid=MyNetwork, rssi=-45 dBm, attempts=1, disconnects=0
I (xxx) SV_HUB: RFID stats: polls=120, tags=15, saturday=12
I (xxx) SV_HUB: Now Playing: state=IDLE, placed=5, removed=5
```

### Expected Console Output (Phase 4)
```
I (xxx) SV_HUB: ===========================================
I (xxx) SV_HUB:   Saturday Vinyl Hub Firmware v0.1.0
I (xxx) SV_HUB:   Phase 4: Wi-Fi Connectivity
I (xxx) SV_HUB: ===========================================
I (xxx) SV_HUB: ESP32-C6 with 1 CPU core(s), WiFi/BT/BLE/802.15.4
I (xxx) SV_HUB: Initializing NVS...
I (xxx) SV_HUB: NVS initialized
I (xxx) SV_HUB: Creating default event loop...
I (xxx) LED_MGR: LED manager initialized successfully
I (xxx) BUTTON: Button handler initialized successfully
I (xxx) YRM100: YRM100 driver initialized successfully
I (xxx) SV_HUB: ===========================================
I (xxx) SV_HUB:   Hardware initialization complete!
I (xxx) SV_HUB: ===========================================
I (xxx) WIFI_MGR: Initializing Wi-Fi manager...
I (xxx) WIFI_MGR: Wi-Fi manager initialized successfully
I (xxx) WIFI_MGR: Connecting to 'MyNetwork'... (attempt 1)
I (xxx) WIFI_MGR: Connected to AP, waiting for IP...
I (xxx) WIFI_MGR: Connected to 'MyNetwork' - IP: 192.168.1.100 (RSSI: -45 dBm)
I (xxx) SV_HUB: Wi-Fi connected: MyNetwork (RSSI: -45 dBm)
I (xxx) HTTP: Testing internet connectivity...
I (xxx) HTTP: GET https://1.1.1.1/cdn-cgi/trace -> 200 (xxx bytes, xxx ms)
I (xxx) HTTP: Internet connectivity OK (response in xxx ms)
I (xxx) SV_HUB: Internet connectivity verified
I (xxx) SV_HUB: ===========================================
I (xxx) SV_HUB:   System ready!
I (xxx) SV_HUB: ===========================================
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

### Wi-Fi connects but no IP address (DHCP timeout)

The ESP32-C6 has a weaker antenna than phones/laptops. If you see:
```
I (xxx) WIFI_MGR: Connected to AP, waiting for IP...
W (xxx) WIFI_MGR: DHCP timeout - no IP received within 15000 ms, disconnecting to retry
```

**Causes:**
- Weak signal (RSSI below -80 dBm) - DHCP packets get lost
- Connected to a mesh extender instead of main router
- Router DHCP server is slow/overloaded

**Solutions:**
1. Move the ESP32-C6 closer to the router
2. Check the RSSI in logs - aim for better than -70 dBm
3. The firmware will auto-retry with exponential backoff (up to 60s)

**Note:** The firmware includes a 15-second DHCP timeout. If no IP is received within this time, it disconnects and retries automatically.

### Wi-Fi signal strength (RSSI) reference

| RSSI (dBm) | Quality | Notes |
|------------|---------|-------|
| -30 to -50 | Excellent | Very close to router |
| -50 to -60 | Good | Reliable operation |
| -60 to -70 | Fair | May see occasional issues |
| -70 to -80 | Weak | DHCP timeouts possible |
| Below -80 | Poor | Unreliable, move closer |

### LED RMT errors ("channel not in init state")

If you see:
```
E (xxx) rmt: rmt_tx_enable(763): channel not in init state
E (xxx) led_strip_rmt: led_strip_rmt_refresh(81): enable RMT channel failed
```

This was a race condition between the LED pattern task and `led_flash()` both trying to update the LED simultaneously. **Fixed in Phase 4** by adding mutex protection around RMT access in `led_apply_color()`.

If you see this error, ensure you have the latest code with the RMT mutex fix.

### ESP-IDF v6.x API changes

When building with ESP-IDF v6.x (development versions), note these changes:

1. **esp-tls component name:** Use `esp-tls` (with hyphen) in CMakeLists.txt PRIV_REQUIRES, not `esp_tls`

2. **HTTP client events:** The switch statement in http_client.c must handle these additional enum values:
   - `HTTP_EVENT_ON_HEADERS_COMPLETE`
   - `HTTP_EVENT_ON_STATUS_CODE`

   Otherwise you'll get `-Werror=switch` compiler errors.

3. **Function naming conflicts:** Avoid using `wifi_deinit()` as a function name - it conflicts with ESP-IDF's internal `wifi_deinit` in `libnet80211.a`. Use `wifi_manager_deinit()` instead.

## Documentation

- [Developer's Guide](docs/developers_guide.md) - Complete technical specification
- [Implementation Plan](docs/implementation_plan.md) - Phased development checklist
- [ESP-IDF Programming Guide](https://docs.espressif.com/projects/esp-idf/en/v5.2.2/esp32c6/)
- [ESP32-C6 Datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-c6_datasheet_en.pdf)

## License

Proprietary - Saturday Vinyl, Inc.
