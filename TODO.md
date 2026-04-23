# Saturday Vinyl Hub — Hardware TODO

## Next PCB Revision

- [ ] Route S3 GPIO7 (H2_BOOT) to **H2 GPIO9** (boot strapping pin), not H2 GPIO4
  - Rev 1 bodge: jumper wire from S3 GPIO7 to H2 GPIO9
  - Rev 1 bodge: 10kΩ pull-up resistor from H2 GPIO9 to H2 3V3 (ensures normal boot at power-on)
  - Root cause: H2 GPIO4 (MTDI) has an internal pull-down that drags the shared S3 GPIO7 line LOW,
    causing H2 to enter download mode at power-on before S3 firmware configures GPIO7
  - With correct routing to GPIO9 + pull-up, the bodge wire and resistor are no longer needed
- [ ] Fix boot mode table in `docs/wiring/hub_wiring.md` (LOW = download mode, not HIGH)
- [ ] Add connector/pads for external WS2812B LED strip (GPIO10, 5V, GND)
- [ ] Update LED strip count from 26 to 24 in wiring docs and BOM
- [ ] Replace board connectors with standard JST-PH connectors
- [ ] Fix YRM100 RFID UART routing to match design target: TX=GPIO17, RX=GPIO18 (currently GPIO11/GPIO12)
- [ ] Add GPIO labels to bottom layer silkscreen for easier debugging
- [ ] Add barcode on silkscreen for Saturday part number (scannable by admin app)
- [ ] Fix H2 UART routing: S3 GPIO9/GPIO10 conflict with LED strip — route to GPIO15 (TX) and GPIO16 (RX) per wiring guide

## Production Firmware

When PCB rev 2 arrives with corrected routing, the following temporary changes need to be reverted:

### `s3-master/components/app_config/include/app_config.h`

All lines marked `TEMPORARY` need to revert to design targets:

| Pin define       | Rev 1 (current) | Rev 2 (design target) | Why changed                                         |
|------------------|------------------|-----------------------|------------------------------------------------------|
| `PIN_RFID_EN`    | GPIO5            | GPIO5                 | Matches design target (no change needed for rev 2)   |
| `PIN_RFID_TX`    | GPIO11           | GPIO17                | PCB routes S3 TX to GPIO11 → YRM100 RXD (pin 3)     |
| `PIN_RFID_RX`    | GPIO12           | GPIO18                | PCB routes S3 RX to GPIO12 ← YRM100 TXD (pin 4)     |
| `PIN_H2_TX`      | GPIO9            | GPIO15                | H2 UART shares GPIO10 with LED strip                 |
| `PIN_H2_RX`      | GPIO10           | GPIO16                | Same — conflicts with WS2812B data pin               |
| `PIN_LED_STRIP`  | GPIO21           | GPIO10                | Moved to GPIO21 because GPIO10 is used for H2 UART   |

### `s3-master/sdkconfig.defaults`

- `CONFIG_ESPTOOLPY_FLASHMODE_DIO=y` — Rev 1 WROOM-1 module doesn't support QIO.
  If rev 2 uses a WROVER or QIO-capable flash, this can be changed to QIO for faster reads.

### `s3-master/components/h2_comm/h2_comm.c`

- `gpio_init_h2_control()` pre-sets GPIO levels before `gpio_config()` to avoid glitching
  the H2 into download mode during reconfiguration. This is good practice regardless but was
  added specifically to work around the rev 1 boot strapping issue. Keep it.

### `s3-master/components/h2_flasher/h2_flasher.c`

- `loader_port_reset_target()` after flash relies on the 10kΩ pull-up on H2 GPIO9 to ensure
  H2 boots normally after hardware reset. If rev 2 correctly routes to GPIO9 with a pull-up
  on the PCB, no code changes needed. If rev 2 omits the pull-up, one must be added to the
  schematic or the firmware will need the software-reset workaround again.
