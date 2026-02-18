# Saturday Hub Provisioning Guide

**Version:** 2.0.0
**Last Updated:** 2026-02-17
**Device:** Saturday Vinyl Hub (ESP32-S3 + ESP32-H2)

---

## Overview

This guide covers the factory provisioning procedures for the Saturday Vinyl Hub. For the generic service mode protocol, see [Service Mode Protocol](../shared-docs/protocols/service_mode_protocol.md).

The Saturday Hub uses a dual-SoC architecture: an ESP32-S3 master (WiFi, BLE, RFID, cloud) and an ESP32-H2 co-processor (Thread Border Router, CoAP). Provisioning is performed via USB serial connection to the S3.

## Hardware Requirements

### Test Station Setup

| Component | Description |
|-----------|-------------|
| Computer | Mac/Windows/Linux with USB-C port |
| USB-C Cable | Data-capable USB-C cable (not charge-only) |
| Saturday Hub | Hub with ESP32-S3 + ESP32-H2 + YRM100 module |
| Test Wi-Fi Network | 2.4 GHz Wi-Fi network for testing |
| Saturday Test Tags | 2–3 Saturday-branded RFID tags for RFID test |

### Hub Hardware

| Component | Purpose |
|-----------|---------|
| ESP32-S3 | Master MCU — WiFi, BLE provisioning, RFID, cloud, USB serial |
| ESP32-H2 | Thread co-processor — Border Router, CoAP server for crates |
| YRM100 | UHF RFID module for "Now Playing" detection (15–26 dBm) |
| WS2812 | Status LED (RGB, onboard GPIO48) |
| Button | Factory reset / BLE pairing (GPIO0) |

## LED States During Provisioning

| State | LED Color | Pattern | Meaning |
|-------|-----------|---------|---------|
| Awaiting Provisioning | White | Pulsing | Service mode active, waiting for commands |
| Service Testing | Yellow | Fast blink | Running a validation test |
| Test Passed | Green | Flash 500ms | Individual test passed |
| Test Failed | Red | Flash 500ms | Individual test failed |
| All Tests Passed | Green | Solid | Ready for factory reset |
| Factory Reset | Red | Fast blink | Clearing data, preparing for reboot |
| H2 Error | Red/Cyan | Alternating | H2 co-processor not responding |
| Normal Operation | Green | Solid dim | Connected and operational |

## Hub-Specific Tests

### test_rfid

Tests the YRM100 RFID module and scans for Saturday tags.

**Request:**
```json
{"cmd": "test_rfid"}
```

The Hub will:
1. Initialize the YRM100 module
2. Query firmware version
3. Scan for tags for 5 seconds
4. Filter for Saturday tags (EPC prefix `0x5356` = "SV")
5. Report results

**Response (Tags found):**
```json
{
  "status": "ok",
  "message": "RFID scan complete",
  "data": {
    "firmware": "V2.39",
    "tags_found": 3,
    "last_epc": "5356A1B2C3D4E5F67890ABCD"
  }
}
```

**Response (No tags but module working):**
```json
{
  "status": "ok",
  "message": "RFID working but no Saturday tags found",
  "data": {
    "firmware": "V2.39",
    "tags_found": 0
  }
}
```

**Response (Module error):**
```json
{
  "status": "error",
  "message": "RFID module not responding",
  "data": {
    "error_code": "rfid_comm_failed"
  }
}
```

### test_thread

Tests communication with the ESP32-H2 and queries Thread network status.

**Request:**
```json
{"cmd": "test_thread"}
```

The Hub will:
1. Ping the H2 co-processor via UART
2. Query H2 Thread Border Router status
3. Retrieve Thread network credentials
4. Report results

**Response (H2 connected, Thread running):**
```json
{
  "status": "ok",
  "message": "H2 Thread BR operational",
  "data": {
    "h2_connected": true,
    "thread_state": "leader",
    "network_name": "SaturdayVinyl",
    "channel": 15,
    "pan_id": 21334
  }
}
```

**Response (H2 not responding):**
```json
{
  "status": "error",
  "message": "H2 co-processor not responding",
  "data": {
    "error_code": "h2_comm_failed"
  }
}
```

### Hub-Specific Error Codes

| Code | Description |
|------|-------------|
| `rfid_init_failed` | Failed to initialize YRM100 driver |
| `rfid_comm_failed` | RFID module not responding on UART |
| `h2_comm_failed` | ESP32-H2 not responding to PING |
| `h2_thread_not_started` | H2 connected but Thread BR not running |

## test_all Sequence

For the Saturday Hub, `test_all` runs tests in this order:

1. **Wi-Fi Test** — Connect to the test network
2. **RFID Test** — Scan for Saturday tags
3. **H2/Thread Test** — Ping H2, verify Thread BR status
4. **Supabase Test** — Send test heartbeat to cloud

**Response:**
```json
{
  "status": "ok",
  "message": "All tests passed - ready for factory reset",
  "data": {
    "wifi_ok": true,
    "rfid_ok": true,
    "thread_ok": true,
    "supabase_ok": true,
    "all_passed": true
  }
}
```

## Thread Credential Retrieval

During factory provisioning, Thread network credentials must be retrieved from the H2 and uploaded to Supabase. This allows the mobile app to provision crates to join the hub's Thread network.

The `get_status` command returns Thread credentials from the H2:

```json
{
  "status": "ok",
  "data": {
    "thread": {
      "network_name": "SaturdayVinyl",
      "pan_id": 21334,
      "channel": 15,
      "network_key": "0123456789abcdef0123456789abcdef",
      "extended_pan_id": "0123456789abcdef"
    }
  }
}
```

The Admin app must upload these credentials to the hub's Supabase record during the `factory_provision` step.

## Factory Provisioning Checklist

### Before Starting

- [ ] Hub is assembled and visually inspected
- [ ] S3↔H2 UART wires are connected (GPIO15↔GPIO23, GPIO16↔GPIO24)
- [ ] YRM100 RFID module is wired (EN, TX, RX, 5V, GND)
- [ ] Test Wi-Fi credentials are ready
- [ ] Saturday Admin app is installed and logged in
- [ ] 2–3 Saturday test tags are available
- [ ] Hub unit_id is generated in production database

### Provisioning Steps

1. **Connect Hub**
   - Connect Hub to computer via USB-C (S3 USB port)
   - Hub LED should pulse white (service mode)

2. **Open Admin App**
   - Launch Saturday Admin app
   - Select the Hub's serial port
   - Verify connection (`get_status` returns data including H2/Thread status)

3. **Provision Device**
   - Enter/scan the unit_id
   - Admin app sends `factory_provision` command with Supabase credentials
   - Verify LED flashes green

4. **Run Tests**
   - Click "Run All Tests"
   - Place 1–2 test tags near the RFID antenna during RFID test
   - Verify all four tests pass (Wi-Fi, RFID, H2/Thread, Supabase)

5. **Factory Reset**
   - Click "Factory Reset"
   - Hub LED blinks red then reboots
   - After reboot, LED pulses white (ready for customer)

6. **Final Verification**
   - Hub should show as "online" in Supabase dashboard
   - Thread credentials should be stored in hub's Supabase record
   - Disconnect Hub and package for shipment

### Troubleshooting

| Issue | Possible Cause | Solution |
|-------|----------------|----------|
| No serial port found | Driver issue or cable | Try different USB-C cable, ensure data-capable |
| Wi-Fi test fails | Wrong credentials | Verify SSID/password, ensure 2.4 GHz network |
| RFID test fails (no module) | UART wiring issue | Check YRM100 wiring: S3 GPIO17→RXD, GPIO18←TXD |
| RFID test fails (no tags) | Tags not present | Place test tags within 30 cm of antenna |
| H2/Thread test fails | H2 not connected | Check UART wires (GPIO15↔23, GPIO16↔24), verify H2 power |
| H2 held in reset | GPIO6 wiring | Verify S3 GPIO6 is connected to H2 EN/RST pin |
| Supabase test fails | Network/credentials | Verify Supabase URL and anon key |

## Customer Reset vs Factory Reset

### Factory Reset (via serial)
Called via `{"cmd": "factory_reset"}` during provisioning.

**Clears:**
- Wi-Fi credentials (test network)
- Provisioned flag
- RFID configuration (poll rate, power, debounce)

**Preserves:**
- Supabase URL and anon key
- Unit ID
- Device secret

### Full Factory Reset (button hold)
Hold the button for 10 seconds during operation.

**Clears:**
- Everything including Supabase configuration

This should only be used if a device needs to be completely re-provisioned.

## Unit ID Format

Hub unit IDs follow the format: `SV-HUB-XXXXXX`

Where `XXXXXX` is a sequential 6-digit number assigned from the production database.

Example: `SV-HUB-000001`, `SV-HUB-000042`

## MAC Address

Each Hub has a unique Wi-Fi MAC address (from the ESP32-S3) included in all status responses. The Admin app should:

1. Read the MAC address from the device status
2. Store it in the production database alongside the `unit_id`
3. Use it for device identification and inventory tracking

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
