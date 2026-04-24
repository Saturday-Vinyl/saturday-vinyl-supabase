# Firmware Image Generation Guide for Saturday Admin App

This document describes how to build ESP-IDF firmware projects and produce the correct `.bin` files for upload to the Saturday Admin App. It applies to all Saturday firmware projects (Hub, Crate, Speaker, etc.).

---

## Single-SoC Projects

For projects with one SoC (e.g., a standalone ESP32-S3 or ESP32-C6):

1. **Build** from the project root:
   ```bash
   idf.py build
   ```

2. **Generate the merged factory binary:**
   `idf.py build` produces an app-only binary. You need a merged binary (bootloader + partition table + app) for factory flashing. Use `esptool.py merge_bin`:
   ```bash
   esptool.py --chip <chip> merge_bin \
     -o build/<project-name>-merged.bin \
     --flash_mode dio --flash_size <size> --flash_freq 80m \
     0x0 build/bootloader/bootloader.bin \
     0x8000 build/partition_table/partition-table.bin \
     0xf000 build/ota_data_initial.bin \
     0x20000 build/<project-name>.bin
   ```
   Replace `<chip>` (e.g., `esp32s3`), `<size>` (e.g., `8MB`), and `<project-name>` with your project values.

3. **Flash offset:** `0x0` (merged binaries always start at offset zero).

4. **Upload to admin app:**

   | Field | Value |
   |-------|-------|
   | Binary file | `build/<project-name>-merged.bin` |
   | SoC type | Match the chip (e.g., `esp32s3`, `esp32c6`, `esp32h2`) |
   | Is master | `true` (only one SoC) |
   | Flash offset | `0` |

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

### Generate Merged Binaries

`idf.py build` produces app-only binaries. For factory flashing (and for the secondary SoC staging), you need merged binaries containing bootloader + partition table + app.

**Master SoC (ESP32-S3 example):**
```bash
cd s3-master
esptool.py --chip esp32s3 merge_bin \
  -o build/sv-hub-s3-master-merged.bin \
  --flash_mode dio --flash_size 8MB --flash_freq 80m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0xf000 build/ota_data_initial.bin \
  0x20000 build/sv-hub-s3-master.bin
```

**Secondary SoC (ESP32-H2 example):**
```bash
cd h2-thread-br
esptool.py --chip esp32h2 merge_bin \
  -o build/sv-hub-h2-thread-br-merged.bin \
  --flash_mode dio --flash_size 4MB --flash_freq 48m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0x10000 build/sv-hub-h2-thread-br.bin
```

### Output Binaries

After build + merge, each SoC directory contains two binaries:

| File | Contents | Used for |
|------|----------|----------|
| `build/<name>.bin` | App only | OTA updates (master SoC only) |
| `build/<name>-merged.bin` | Bootloader + partition table + app | Factory flashing, secondary SoC staging |

### Upload to Admin App

**Master SoC binary:**
- SoC type: `esp32s3` (or whichever chip the master uses)
- Is master: `true`
- Flash offset: `0`
- Binary: the **merged** binary (`*-merged.bin`) for factory flashing

**Secondary SoC binary:**
- SoC type: `esp32h2` (or whichever chip the secondary uses)
- Is master: `false`
- Flash offset: the master's staging partition offset (see below)
- Binary: the **merged** binary (`*-merged.bin`) — the secondary is always flashed from scratch by the master, including bootloader and partition table

### Finding the Secondary Flash Offset

The secondary binary is NOT flashed directly to the secondary SoC by the admin app. Instead, it is written to a **staging partition on the master SoC's flash**. On boot, the master firmware detects the staged binary and flashes it to the secondary SoC over UART.

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
esptool.py --chip esp32s3 --port PORT -b 460800 \
  --before default_reset --after no_reset \
  write_flash --force \
  0x0 s3-master-merged.bin \
  0x400000 h2-thread-br-merged.bin
```

Key flags:
- `--after no_reset`: prevents reset between writing the two binaries
- `--force`: required because the H2 staging partition at `0x400000` is outside the S3's normal partition table range

This writes:
1. The master merged binary at offset `0x0` (bootloader + partition table + app)
2. The secondary merged binary at offset `0x400000` (the staging partition on the master's flash)

On first boot, the master firmware:
1. Detects valid firmware in the staging partition (magic byte check)
2. Puts the secondary SoC into bootloader mode via GPIO
3. Flashes the secondary merged binary over UART using `esp-serial-flasher`
4. Resets the secondary SoC to normal operation
5. Erases the staging partition header to prevent re-flashing on next boot

Subsequent OTA updates follow the same staging flow: the master downloads the new secondary firmware to the staging partition, then flashes it on the next boot.

---

## Summary Table

| SoC Role | Binary | Upload as | Flash Offset | Used for |
|----------|--------|-----------|-------------|----------|
| Master (or single-SoC) | `*-merged.bin` | `is_master: true` | `0` | Factory flash |
| Master OTA | `*.bin` (app only) | `is_master: true` | `0` | OTA update |
| Secondary | `*-merged.bin` | `is_master: false` | From master's `partitions.csv` | Factory flash + OTA staging |

---

## Versioning and Releases

Firmware uses a single version number for the entire package (all SoCs ship together as one unit). The admin app uses this version to determine when devices need OTA updates.

### Version Sources

The version must match in all of these files:

| File | Fields | Used by |
|------|--------|---------|
| `s3-master/components/app_config/include/app_config.h` | `FW_VERSION_MAJOR/MINOR/PATCH/STRING` | S3 firmware (heartbeats, `get_status`) |
| `h2-thread-br/main/app_config.h` | `FW_VERSION_MAJOR/MINOR/PATCH/STRING` | H2 boot log |
| `shared/include/h2_version.h` | `H2_FW_VERSION_MAJOR/MINOR/PATCH/STRING` | S3 querying H2 version over UART |
| `s3-master/components/provisioning/firmware_schema.json` | `"version"` | Admin app firmware record |

### Before You Start

**Ask the user** whether this build is for:

1. **Local testing** — build and flash only, no version change needed
2. **Release** — bump the version, tag, build, create GitHub release, upload to admin app

Do not assume a version bump is needed. Many builds are for local iteration and testing. Only follow the release workflow below if the user confirms they want to cut a release.

### Release Workflow

```bash
# 1. Bump version in all 4 files above
#    (update MAJOR.MINOR.PATCH and the string)

# 2. Commit the version bump
git add -A && git commit -m "Release v0.6.0"

# 3. Tag the release
git tag v0.6.0

# 4. Build both SoCs
cd s3-master && idf.py build && cd ..
cd h2-thread-br && idf.py build && cd ..

# 5. Generate merged binaries
cd s3-master
esptool.py --chip esp32s3 merge_bin \
  -o build/sv-hub-s3-master-merged.bin \
  --flash_mode dio --flash_size 8MB --flash_freq 80m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0xf000 build/ota_data_initial.bin \
  0x20000 build/sv-hub-s3-master.bin
cd ..

cd h2-thread-br
esptool.py --chip esp32h2 merge_bin \
  -o build/sv-hub-h2-thread-br-merged.bin \
  --flash_mode dio --flash_size 4MB --flash_freq 48m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0x10000 build/sv-hub-h2-thread-br.bin
cd ..

# 6. Generate release notes from commits since last tag
#    Review the commit log between the previous tag and HEAD:
git log $(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline

#    Write release notes summarizing the changes. Group by category:
#    - **Features**: new functionality
#    - **Fixes**: bug fixes
#    - **Hardware**: PCB workarounds, pin changes, wiring notes
#    - **Breaking**: anything that changes behavior or requires migration
#
#    Keep it concise — one line per change, written for someone who uses
#    the device, not someone reading the diff.

# 7. Push tag and create GitHub release with binaries and notes
git push origin v0.6.0
gh release create v0.6.0 \
  s3-master/build/sv-hub-s3-master-merged.bin \
  h2-thread-br/build/sv-hub-h2-thread-br-merged.bin \
  --title "v0.6.0" \
  --notes "$(cat <<'EOF'
## Release Notes

### Features
- ...

### Fixes
- ...
EOF
)"

# 7. Upload binaries to the Saturday Admin App
#    - S3 merged binary: is_master=true, offset=0
#    - H2 merged binary: is_master=false, offset=0x400000
```

### Version Bumping Rules

- **PATCH** (0.5.0 → 0.5.1): Bug fixes, pin remapping, config changes
- **MINOR** (0.5.1 → 0.6.0): New features, protocol changes, new capabilities
- **MAJOR** (0.6.0 → 1.0.0): Breaking changes, production release

---

## Notes

- Always use the **merged binary** (`*-merged.bin`) for factory flashing and secondary SoC staging
- For master SoC OTA updates, the app-only binary (`*.bin`) is sufficient — the bootloader doesn't change
- For secondary SoC updates (both factory and OTA), always use the merged binary — the master flashes bootloader + partition table + app to the secondary from scratch
- The merged binary is NOT generated automatically by `idf.py build` — you must run `esptool.py merge_bin` as a separate step
- The secondary flash offset is relative to the **master SoC's flash address space**, not the secondary's
- The secondary SoC's own partition layout is irrelevant for the admin app upload — the master firmware handles the internal flashing
