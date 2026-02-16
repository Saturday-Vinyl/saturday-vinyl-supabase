# Saturday Vinyl Shared Documentation

Central repository for Saturday Vinyl technical documentation shared across all projects.

## Contents

### Concepts
- **[Data Model](concepts/data_model.md)** - Core entity relationships (Units, Devices, Products, Device Types, Capabilities, Firmware)

### Protocols
- **[BLE Provisioning Protocol](protocols/ble_provisioning_protocol.md)** - BLE GATT interface for mobile app device provisioning
- **[Device Command Protocol](protocols/device_command_protocol.md)** - Unified command interface for device communication
- **[Service Mode Protocol](protocols/service_mode_protocol.md)** - USB serial interface for factory provisioning and diagnostics

### Schemas
- **[Capability Schema](schemas/capability_schema.md)** - Capability definition and attribute schema specification

### Templates
- **[Claude Command Templates](templates/claude-commands/)** - Slash command wrappers for Claude Code integration

## Usage

### Adding to a New Project

**Step 1:** Clone this repo locally (one-time, anywhere on your machine):
```bash
git clone https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git ~/saturday-vinyl-shared-docs
chmod +x ~/saturday-vinyl-shared-docs/scripts/setup-shared-docs.sh
```

**Step 2:** Run the setup script from your project root:
```bash
# From your project directory (e.g., ~/projects/my-saturday-app)
~/saturday-vinyl-shared-docs/scripts/setup-shared-docs.sh
```

**Alternative: Manual setup**
```bash
git remote add shared-docs https://github.com/Saturday-Vinyl/saturday-vinyl-shared-docs.git
git subtree add --prefix=shared-docs shared-docs main --squash
mkdir -p ./.claude/commands
cp ./shared-docs/templates/claude-commands/*.md ./.claude/commands/
```

### Pulling Updates

When the central docs are updated, pull changes into your project:

```bash
git subtree pull --prefix=shared-docs shared-docs main --squash -m "Merge shared-docs updates"
```

### Contributing Changes

Edit docs locally in the `./shared-docs/` directory, commit as usual, then push upstream:

```bash
# 1. Edit the doc
vim ./shared-docs/protocols/ble_provisioning_protocol.md

# 2. Commit locally
git add ./shared-docs/
git commit -m "Update BLE protocol: add new characteristic"

# 3. Push to central repo
git subtree push --prefix=shared-docs shared-docs main
```

## Claude Code Integration

After setup, these slash commands are available:

| Command | Description |
|---------|-------------|
| `/ble-provisioning` | Load BLE Provisioning Protocol into context |
| `/service-mode` | Load Service Mode Protocol into context |

You can also reference docs directly in prompts:
```
Read @./shared-docs/protocols/ble_provisioning_protocol.md and implement the Status characteristic handler.
```

## Directory Structure

```
saturday-vinyl-shared-docs/
├── README.md                    # This file
├── concepts/                    # Architectural concepts
│   └── data_model.md            # Core entity relationships
├── protocols/                   # Protocol specifications
│   ├── ble_provisioning_protocol.md
│   ├── device_command_protocol.md
│   ├── led_status_protocol.md
│   └── service_mode_protocol.md
├── schemas/                     # Schema specifications
│   └── capability_schema.md
├── templates/
│   └── claude-commands/         # Claude Code command templates
│       ├── ble-provisioning.md
│       └── service-mode.md
└── scripts/
    └── setup-shared-docs.sh     # Project setup script
```

## Projects Using This

- **sv-hub-firmware** - Saturday Vinyl Hub (ESP32-S3 + ESP32-H2)
- **saturday-mobile-app** - Consumer mobile app (Flutter)
- **saturday-admin-app** - Factory/technician desktop app (Flutter)
- (Future firmware projects)

---

*This repository is proprietary to Saturday Vinyl. Do not distribute externally.*
