# Firmware Image Generation Guide for Saturday Admin App

This document describes how to build ESP-IDF firmware projects and produce the correct `.bin` files for upload to the Saturday Admin App. It applies to all Saturday firmware projects (Hub, Crate, Speaker, etc.).

---

## Single-SoC Projects

For projects with one SoC (e.g., a standalone ESP32-S3 or ESP32-C6):

1. **Build** from the project root:
   ```bash
   idf.py build
   ```

2. **Locate the merged factory binary** at:
   ```
   build/<project-name>.bin
   ```
   This is a merged binary containing bootloader + partition table + application. It is the file to upload to the admin app.

3. **Flash offset:** `0x0` (merged binaries always start at offset zero).

4. **Upload to admin app:**
   - SoC type: match the chip (e.g., `esp32s3`, `esp32c6`, `esp32h2`)
   - Is master: `true` (only one SoC)
   - Flash offset: `0`

---

## Multi-SoC Projects

For projects where a single PCB has multiple SoCs (e.g., Hub with ESP32-S3 + ESP32-H2), each SoC's firmware lives in its own subdirectory from the repo root.

### Directory Structure

```
project-root/
  s3-master/          # Master SoC firmware (ESP32-S3)
    CMakeLists.txt
    partitions.csv
    main/
    components/
    build/            # Build output
  h2-thread-br/       # Secondary SoC firmware (ESP32-H2)
    CMakeLists.txt
    partitions.csv
    main/
    components/
    build/            # Build output
  shared/             # Shared code between SoCs
```

### Build Each SoC Independently

```bash
# Master SoC
cd s3-master
idf.py build

# Secondary SoC
cd ../h2-thread-br
idf.py build
```

### Locate the Output Binaries

- **Master:** `s3-master/build/<project-name>.bin` (e.g., `sv-hub-s3-master.bin`)
- **Secondary:** `h2-thread-br/build/<project-name>.bin` (e.g., `sv-hub-h2-thread-br.bin`)

Both are merged factory binaries.

### Upload to Admin App

**Master SoC binary:**
- SoC type: `esp32s3` (or whichever chip the master uses)
- Is master: `true`
- Flash offset: `0`

**Secondary SoC binary:**
- SoC type: `esp32h2` (or whichever chip the secondary uses)
- Is master: `false`
- Flash offset: the master's staging partition offset (see below)

### Finding the Secondary Flash Offset

The secondary binary is NOT flashed directly to the secondary SoC. Instead, it is written to a **staging partition on the master SoC's flash**. On boot, the master firmware detects the staged binary and flashes it to the secondary SoC over UART.

To find the correct offset, look at the **master SoC's** `partitions.csv` for a custom data partition used for co-processor firmware staging:

```csv
# Example from Hub s3-master/partitions.csv:
# Name,    Type, SubType, Offset,     Size
h2_fw,     data, 0x40,    0x400000,   0x100000
```

The **Offset** column is the flash offset for the secondary binary. In this example: `0x400000` (4,194,304 decimal).

Record this value as the `flash_offset` when uploading the secondary firmware file in the admin app.

---

## How Factory Flashing Works for Multi-SoC

The admin app uses esptool to write both binaries in a single flash operation:

```bash
esptool.py --chip esp32s3 --port PORT --baud 460800 \
  write_flash 0x0 s3_merged.bin 0x400000 h2_firmware.bin
```

This writes:
1. The master binary at offset `0x0` (normal location)
2. The secondary binary at offset `0x400000` (the staging partition on the master's flash)

On first boot, the master firmware:
1. Detects a pending co-processor update in the staging partition
2. Puts the secondary SoC into bootloader mode via GPIO
3. Flashes the secondary binary over UART using `esp-serial-flasher`
4. Resets the secondary SoC to normal operation

---

## Summary Table

| SoC Role | Binary Location | Upload as | Flash Offset |
|----------|----------------|-----------|-------------|
| Master (or single-SoC) | `<soc-dir>/build/<name>.bin` | `is_master: true` | `0` |
| Secondary | `<soc-dir>/build/<name>.bin` | `is_master: false` | From master's `partitions.csv` staging partition offset |

---

## Notes

- Always use the **merged binary** (the one at `build/<name>.bin`), not individual partition binaries
- The merged binary includes bootloader, partition table, and application -- flash offset is always `0x0` for the master
- For the secondary, the flash offset is relative to the **master SoC's flash address space**, not the secondary's
- The secondary SoC's own partition layout is irrelevant for the admin app upload -- the master firmware handles the internal flashing
