# Firmware Image Generation Guide for Saturday Admin App

This document describes how to build ESP-IDF firmware projects and produce the correct `.bin` files for upload to the Saturday Admin App. It applies to all Saturday firmware projects (Hub, Crate, Speaker, etc.).

---

## Important: App Binary vs Merged Binary

ESP-IDF's `idf.py build` produces an **app-only** binary at `build/<project-name>.bin`. This does NOT include the bootloader or partition table. Flashing an app-only binary at offset `0x0` will corrupt the device.

For the admin app, we need a **merged binary** that combines bootloader + partition table + app into a single file. This must be created explicitly using `esptool merge-bin` after building.

---

## Single-SoC Projects

For projects with one SoC (e.g., a standalone ESP32-S3 or ESP32-C6):

1. **Build** from the project root:
   ```bash
   idf.py build
   ```

2. **Create the merged factory binary** using esptool. The offsets come from the project's `partitions.csv` and the chip's default bootloader offset:
   ```bash
   # Find the app offset from partitions.csv (look for the factory or ota_0 partition)
   # Common bootloader offsets: 0x0 (ESP32-S3/C6/H2), 0x1000 (ESP32)
   # Partition table is typically at 0x8000

   esptool merge-bin \
     --target-offset 0x0 \
     --flash-size 8MB \
     0x0     build/bootloader/bootloader.bin \
     0x8000  build/partition_table/partition-table.bin \
     <APP_OFFSET> build/<project-name>.bin \
     -o build/<project-name>-merged.bin
   ```

   Replace `<APP_OFFSET>` with the offset of the `factory` or `ota_0` partition from your `partitions.csv`.

3. **Flash offset:** `0x0` (merged binaries always start at offset zero).

4. **Upload to admin app:**
   - File: `build/<project-name>-merged.bin` (the merged binary, NOT `build/<project-name>.bin`)
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

### Build Each SoC and Create Merged Binaries

```bash
# Master SoC
cd s3-master
idf.py build

# Create merged binary for master
# Check partitions.csv for the app offset (factory or ota_0 partition)
esptool merge-bin \
  --target-offset 0x0 \
  --flash-size 8MB \
  0x0     build/bootloader/bootloader.bin \
  0x8000  build/partition_table/partition-table.bin \
  <APP_OFFSET> build/<project-name>.bin \
  -o build/<project-name>-merged.bin

# Secondary SoC
cd ../h2-thread-br
idf.py build

# Create merged binary for secondary
esptool merge-bin \
  --target-offset 0x0 \
  --flash-size 4MB \
  0x0     build/bootloader/bootloader.bin \
  0x8000  build/partition_table/partition-table.bin \
  <APP_OFFSET> build/<project-name>.bin \
  -o build/<project-name>-merged.bin
```

Replace `<APP_OFFSET>` with the offset of the `factory` or `ota_0` partition from each project's `partitions.csv`.

### Locate the Output Binaries

- **Master:** `s3-master/build/<project-name>-merged.bin` (e.g., `sv-hub-s3-master-merged.bin`)
- **Secondary:** `h2-thread-br/build/<project-name>-merged.bin` (e.g., `sv-hub-h2-thread-br-merged.bin`)

These are merged factory binaries containing bootloader + partition table + app. Do NOT use the plain `build/<project-name>.bin` files — those are app-only.

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
| Master (or single-SoC) | `<soc-dir>/build/<name>-merged.bin` | `is_master: true` | `0` |
| Secondary | `<soc-dir>/build/<name>-merged.bin` | `is_master: false` | From master's `partitions.csv` staging partition offset |

---

## Notes

- Always use the **merged binary** (`build/<name>-merged.bin` created via `esptool merge-bin`), NOT the app-only binary at `build/<name>.bin`
- The merged binary includes bootloader, partition table, and application -- flash offset is always `0x0` for the master
- For the secondary, the flash offset is relative to the **master SoC's flash address space**, not the secondary's
- The secondary SoC's own partition layout is irrelevant for the admin app upload -- the master firmware handles the internal flashing
