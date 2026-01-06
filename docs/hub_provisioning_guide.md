# Saturday Hub Provisioning Guide

**Version:** 1.0.0
**Last Updated:** 2026-01-04
**Device:** Saturday Vinyl Hub (ESP32-C6)

---

## Overview

This guide covers the Hub-specific provisioning procedures for the Saturday Vinyl Hub. For the generic service mode protocol, see [Service Mode Protocol](service_mode_protocol.md).

The Saturday Hub is an ESP32-C6 based device that detects vinyl records via UHF RFID and reports "Now Playing" events to Supabase.

## Hardware Requirements

### Test Station Setup

| Component | Description |
|-----------|-------------|
| Computer | Mac/Windows/Linux with USB-C port |
| USB-C Cable | Data-capable USB-C cable (not charge-only) |
| Saturday Hub | Hub PCB with ESP32-C6 module |
| Test Wi-Fi Network | 2.4GHz Wi-Fi network for testing |
| Saturday Test Tags | 2-3 Saturday-branded RFID tags for RFID test |

### Hub Hardware

| Component | Purpose |
|-----------|---------|
| ESP32-C6 | Main controller with Wi-Fi 6 and BLE 5 |
| YRM100 | UHF RFID module (15-30 dBm) |
| WS2812 | Status LED (RGB) |
| Button | Factory reset / pairing |

## LED States During Provisioning

| State | LED Color | Pattern | Meaning |
|-------|-----------|---------|---------|
| Awaiting Provisioning | White | Pulsing | Waiting for Admin app connection |
| Provisioning | Yellow | Pulsing | Receiving/storing credentials |
| Test Running | Blue | Fast blink | Running validation test |
| Test Passed | Green | Flash 500ms | Individual test passed |
| Test Failed | Red | Flash 500ms | Individual test failed |
| All Tests Passed | Green | Solid | Ready for factory reset |
| Factory Reset | Red | Fast blink | Clearing data, preparing for reboot |
| Normal Operation | Cyan | Pulsing | Connected and operational |

## Hub-Specific Tests

### test_rfid

Test the YRM100 RFID module and scan for Saturday tags.

**Request:**
```json
{"cmd": "test_rfid"}
```

The Hub will:
1. Initialize the YRM100 module
2. Query firmware version
3. Scan for tags for 5 seconds
4. Filter for Saturday tags (EPC prefix 0x5356 "SV")
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

### Hub-Specific Error Codes

| Code | Description |
|------|-------------|
| `rfid_init_failed` | Failed to initialize YRM100 driver |
| `rfid_comm_failed` | RFID module not responding on UART |

## test_all Sequence

For the Saturday Hub, `test_all` runs tests in this order:

1. **Wi-Fi Test** - Connect to the test network
2. **RFID Test** - Scan for Saturday tags
3. **Supabase Test** - Send test heartbeat to cloud

**Response:**
```json
{
  "status": "ok",
  "message": "All tests passed - ready for factory reset",
  "data": {
    "wifi_ok": true,
    "rfid_ok": true,
    "supabase_ok": true,
    "all_passed": true
  }
}
```

## Factory Provisioning Checklist

### Before Starting

- [ ] Hub is assembled and visually inspected
- [ ] Test Wi-Fi credentials are ready
- [ ] Saturday Admin app is installed and logged in
- [ ] 2-3 Saturday test tags are available
- [ ] Hub unit_id is generated in production database

### Provisioning Steps

1. **Connect Hub**
   - Connect Hub to computer via USB-C
   - Hub LED should pulse white (awaiting provisioning)

2. **Open Admin App**
   - Launch Saturday Admin app
   - Select the Hub's serial port
   - Verify connection (get_status returns data)

3. **Provision Device**
   - Enter/scan the unit_id
   - Admin app sends provision command
   - Verify LED flashes green

4. **Run Tests**
   - Click "Run All Tests"
   - Place 1-2 test tags near the RFID antenna during RFID test
   - Verify all three tests pass (Wi-Fi, RFID, Supabase)

5. **Factory Reset**
   - Click "Factory Reset"
   - Hub LED blinks red then reboots
   - After reboot, LED pulses white (ready for customer)

6. **Final Verification**
   - Hub should show as "online" in Supabase dashboard
   - Disconnect Hub and package for shipment

### Troubleshooting

| Issue | Possible Cause | Solution |
|-------|----------------|----------|
| No serial port found | Driver issue or cable | Try different USB-C cable, reinstall drivers |
| Wi-Fi test fails | Wrong credentials | Verify SSID/password, ensure 2.4GHz network |
| RFID test fails (no module) | UART connection issue | Check YRM100 wiring, TX/RX pins |
| RFID test fails (no tags) | Tags not present | Place test tags within 30cm of antenna |
| Supabase test fails | Network/credentials issue | Verify Supabase URL and anon key |

## Customer Reset vs Factory Reset

The Hub supports two types of reset:

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

Each Hub has a unique Wi-Fi MAC address that is included in all status responses. The MAC address:

- Format: `AA:BB:CC:DD:EE:FF` (uppercase, colon-separated)
- Is burned into the ESP32-C6 chip at manufacturing
- Cannot be changed
- Should be stored in the production database alongside the `unit_id`

The Admin app should:
1. Read the MAC address from the device status
2. Store it in the production database when creating the unit record
3. Use it for device identification and inventory tracking

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
