# Saturday Data Model

**Version:** 1.0.0
**Last Updated:** 2026-02-06
**Audience:** All Saturday developers, AI coding agents, Database architects

---

## Table of Contents

1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Entity Relationships](#entity-relationships)
4. [Catalog vs Instance Entities](#catalog-vs-instance-entities)
5. [The Unit-Device Relationship](#the-unit-device-relationship)
6. [Firmware Architecture](#firmware-architecture)
7. [Data Flow Examples](#data-flow-examples)
8. [Database Schema Summary](#database-schema-summary)
9. [Common Misconceptions](#common-misconceptions)
10. [Version History](#version-history)

---

## Overview

This document defines the core data model for Saturday's ecosystem. Understanding these relationships is critical for any work involving database migrations, API design, or cross-team feature development.

### The Two-Layer Architecture

Saturday separates **what the consumer sees** from **what the electronics do**:

| Layer | Consumer Perspective | Admin/Engineering Perspective |
|-------|---------------------|------------------------------|
| **Instance** | Unit (the physical product they own) | Device (the embedded electronics) |
| **Catalog** | Product (what they bought) | Device Type (what firmware runs on) |

This separation exists because:
1. A single Unit may contain multiple Devices (e.g., a Crate has a main SoC and an RFID reader)
2. Consumers care about their "Crate" not about "ESP32-S3 with MAC AA:BB:CC:DD:EE:FF"
3. Engineering needs device-level granularity for provisioning, debugging, and firmware management

---

## Core Concepts

### Unit

**Table:** `units`

A Unit is the primary object in the Saturday ecosystem from the consumer's perspective. It represents the physical product the customer owns and interacts with.

| Aspect | Description |
|--------|-------------|
| **What it represents** | The thing the consumer cares about (their Crate, their Hub) |
| **Identified by** | Serial number (e.g., `SV-CRT-000001`) |
| **Contains** | One or more Devices |
| **Consumer-visible** | Yes - appears in consumer app, receives notifications |
| **Key attributes** | Serial number, name, owner, online/offline state, aggregated telemetry |

**Example:** A customer's "Saturday Crate" with serial number `SV-CRT-000001`

### Device

**Table:** `devices`

A Device is the embedded electronic component that provides communication and sensing capabilities. Devices are abstracted away from consumers but are central to admin operations.

| Aspect | Description |
|--------|-------------|
| **What it represents** | An embedded electronic module (SoC, radio, sensor) |
| **Identified by** | MAC address (hardware identifier) |
| **Belongs to** | One Unit |
| **Consumer-visible** | No - hidden from consumer, visible in admin apps |
| **Key attributes** | MAC address, firmware version, provision_data, last_seen_at |

**Example:** The ESP32-S3 module inside a Crate with MAC `AA:BB:CC:DD:EE:FF`

### Product

**Table:** `products`

A Product is the catalog definition of what a Unit can be. It's not a physical object but a template that defines the characteristics of Units.

| Aspect | Description |
|--------|-------------|
| **What it represents** | A product definition (SKU/model) |
| **Contains** | Multiple Device Types (via `product_device_types`) |
| **Consumer-visible** | Yes - product name, description, images |
| **Key attributes** | Name, slug, description, image assets |

**Example:** "Saturday Crate" - the product definition, not any specific physical unit

### Device Type

**Table:** `device_types`

A Device Type is the catalog definition of what a Device can be. It defines the hardware platform, capabilities, and firmware compatibility for devices of that type.

| Aspect | Description |
|--------|-------------|
| **What it represents** | A hardware platform definition |
| **Contains** | Multiple Capabilities (via `device_type_capabilities`) |
| **Defines** | What firmware can run, what tests to run, what data to expect |
| **Key attributes** | Name, slug, capabilities, firmware versions |

**Example:** "crate-main-v1" - the ESP32-S3-based main controller for Crate units

### Capability

**Table:** `capabilities`

A Capability defines a specific function that a Device Type can perform. Capabilities define the data contracts for provisioning and telemetry.

| Aspect | Description |
|--------|-------------|
| **What it represents** | A feature or function (WiFi, Thread, RFID, etc.) |
| **Defines** | Input/output schemas for factory and consumer provisioning |
| **Used by** | Firmware generation, admin app validation, test definitions |
| **Key attributes** | Name, schemas (factory_input, factory_output, consumer_input, consumer_output, heartbeat) |

**Example:** "wifi" capability - defines SSID/password inputs, connection status outputs

See [Capability Schema Specification](../schemas/capability_schema.md) for full schema documentation.

### Firmware

**Table:** `firmwares`

A Firmware is a versioned software package that can be installed on Devices of a specific Device Type.

| Aspect | Description |
|--------|-------------|
| **What it represents** | A version of device software |
| **Associated with** | One Device Type |
| **May contain** | Multiple binary files (for multi-SoC boards) |
| **Key attributes** | Version, device_type_id, binary files, release notes |

**Example:** Firmware v1.2.0 for the "crate-main-v1" Device Type

---

## Entity Relationships

### Visual Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CATALOG LAYER                                      │
│                    (Definitions, not physical objects)                       │
│                                                                              │
│   ┌──────────────┐         ┌──────────────────┐        ┌──────────────┐    │
│   │   Product    │────────►│ product_device_  │◄───────│ Device Type  │    │
│   │              │   M:N   │     types        │   M:N  │              │    │
│   │ - name       │         └──────────────────┘        │ - name       │    │
│   │ - slug       │                                      │ - slug       │    │
│   │ - description│                                      │              │    │
│   └──────────────┘                                      └──────┬───────┘    │
│         │                                                      │            │
│         │ 1:N                                              1:N │            │
│         ▼                                                      ▼            │
│   ┌─────────────────────────────────┐          ┌───────────────────────┐   │
│   │     (Units are instances of)    │          │ device_type_          │   │
│   └─────────────────────────────────┘          │    capabilities       │   │
│                                                 │         M:N           │   │
│                                                 └───────────┬───────────┘   │
│                                                              │              │
│                                                              ▼              │
│                                      ┌────────────┐    ┌────────────┐      │
│                                      │ Capability │    │  Firmware  │      │
│                                      │            │    │            │      │
│                                      │ - name     │    │ - version  │      │
│                                      │ - schemas  │    │ - binaries │      │
│                                      └────────────┘    └────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          INSTANCE LAYER                                      │
│                    (Physical objects, owned by users)                        │
│                                                                              │
│   ┌──────────────┐                              ┌──────────────┐            │
│   │     Unit     │ ◄──────────────────────────► │    Device    │            │
│   │              │          1:N                 │              │            │
│   │ - serial_num │    (a Unit has Devices)      │ - mac_address│            │
│   │ - owner      │                              │ - provision_ │            │
│   │ - online     │                              │     data     │            │
│   └──────────────┘                              │ - last_seen  │            │
│                                                  └──────────────┘            │
│                                                                              │
│   Consumer sees this ◄────────────────────────► Admin/firmware works here   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Relationship Summary

| Relationship | Type | Description |
|--------------|------|-------------|
| Product → Device Type | Many-to-Many | A Product contains multiple Device Types (via `product_device_types`) |
| Product → Unit | One-to-Many | All Units are instances of exactly one Product |
| Device Type → Capability | Many-to-Many | A Device Type has multiple Capabilities (via `device_type_capabilities`) |
| Device Type → Firmware | One-to-Many | Firmware versions are specific to a Device Type |
| Device Type → Device | One-to-Many | All Devices are instances of exactly one Device Type |
| Unit → Device | One-to-Many | A Unit contains one or more Devices |

---

## Catalog vs Instance Entities

Understanding the distinction between catalog and instance entities is crucial:

### Catalog Entities (Templates)

| Entity | Purpose | Example |
|--------|---------|---------|
| **Product** | Defines what can be sold | "Saturday Crate" |
| **Device Type** | Defines hardware platforms | "crate-main-v1" (ESP32-S3 board) |
| **Capability** | Defines features | "wifi", "thread", "rfid" |
| **Firmware** | Defines software versions | "v1.2.0 for crate-main-v1" |

These are created once and referenced by many instances. Changing a catalog entity affects all instances that reference it.

### Instance Entities (Physical Objects)

| Entity | Purpose | Example |
|--------|---------|---------|
| **Unit** | A specific product owned by someone | Serial `SV-CRT-000001` owned by John |
| **Device** | A specific electronic module | MAC `AA:BB:CC:DD:EE:FF` in that Crate |

These are created during manufacturing/provisioning. Each instance has unique identifiers and its own state.

---

## The Unit-Device Relationship

### Why Units Have Multiple Devices

Many Saturday products contain multiple embedded electronic modules:

**Example: Saturday Crate**
```
┌─────────────────────────────────────────────────────┐
│                    Unit: SV-CRT-000001              │
│                    (Saturday Crate)                 │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Device 1: Main Controller                  │   │
│  │  - MAC: AA:BB:CC:DD:EE:01                   │   │
│  │  - Device Type: crate-main-v1               │   │
│  │  - Capabilities: wifi, cloud, led           │   │
│  │  - Role: Master SoC, cloud communication    │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  Device 2: RFID Reader                      │   │
│  │  - MAC: AA:BB:CC:DD:EE:02                   │   │
│  │  - Device Type: rfid-reader-v1              │   │
│  │  - Capabilities: rfid                       │   │
│  │  - Role: Scans vinyl records               │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Data Aggregation: Device → Unit

Devices report telemetry via heartbeats. A database trigger (`sync_heartbeat_to_device_and_unit`) automatically aggregates selected fields to the `units` table on each heartbeat:

| Device Reports (heartbeat) | Unit Column Updated | Consumer Sees |
|----------------------------|--------------------|----|
| Device 1: `wifi_rssi: -55` | `units.wifi_rssi`, `units.is_online = true` | "Online", signal strength |
| Device 1: `battery_level: 85` | `units.battery_level`, `units.is_charging` | Battery indicator |
| Device 1: `temperature_c: 22.5` | `units.temperature_c` | Temperature reading |
| Device 2: `rfid_tag_count: 3` | (not a unit-level column) | (via separate mechanism) |
| Device 1: `free_heap: 245760` | `devices.latest_telemetry` only | (not shown to consumer) |

**Key principles:**
- Consumer-facing telemetry lives as typed columns on the `units` table
- The heartbeat trigger uses `COALESCE` so multi-device units work correctly (an RFID reader heartbeat won't null out battery data set by the main controller)
- `units.last_seen_at` uses `GREATEST(existing, new)` so the most recent heartbeat from ANY device in the unit wins
- `units.is_online` is set `true` by the trigger and `false` by a 1-minute cron job when `last_seen_at` exceeds the offline threshold
- Apps subscribe to `units` via Supabase Realtime to get telemetry updates

### Serial Number Assignment

- The **Unit** receives the serial number (e.g., `SV-CRT-000001`)
- Devices are identified by their MAC addresses
- During provisioning, Devices are associated with their parent Unit
- The `factory_provision` command assigns the serial number to the master Device, which stores it in NVS

---

## Firmware Architecture

### Single-SoC vs Multi-SoC Devices

Some Device Types define PCBs with multiple System-on-Chips:

**Single-SoC Example:**
```
Device Type: "crate-rfid-v1"
└── Firmware v1.0.0
    └── rfid_reader_v1.0.0.bin  (single binary)
```

**Multi-SoC Example:**
```
Device Type: "hub-v1" (ESP32-S3 + ESP32-H2 on same PCB)
└── Firmware v1.2.0
    ├── hub_main_v1.2.0.bin     (ESP32-S3 - master)
    └── hub_thread_v1.2.0.bin   (ESP32-H2 - co-processor)
```

### Firmware Update Flow (Multi-SoC)

1. OTA command targets the master SoC
2. Master downloads all firmware binaries
3. Master flashes itself (primary partition)
4. Master flashes co-processors via UART
5. System reboots with new firmware

---

## Data Flow Examples

### Factory Provisioning Flow

```
Admin App                  Device                     Cloud (Supabase)
    │                         │                            │
    │  factory_provision      │                            │
    │  {serial, name, ...}    │                            │
    │ ───────────────────────►│                            │
    │                         │  (stores in NVS)           │
    │                         │                            │
    │     Response            │                            │
    │  {mac, thread_creds}    │                            │
    │ ◄───────────────────────│                            │
    │                         │                            │
    │                         │                            │
    │  INSERT INTO units      │                            │
    │  ─────────────────────────────────────────────────────►
    │                         │                            │
    │  INSERT INTO devices    │                            │
    │  (mac, unit_id, provision_data)                      │
    │  ─────────────────────────────────────────────────────►
```

### Heartbeat Data Flow

```
Device                          Cloud (Supabase)               Consumer App
   │                              │                                  │
   │  INSERT device_heartbeats    │                                  │
   │  {mac, unit_id, telemetry}   │                                  │
   │ ─────────────────────────────►                                  │
   │                              │                                  │
   │                     ┌────────┴────────┐                         │
   │                     │ Trigger fires:  │                         │
   │                     │ sync_heartbeat_ │                         │
   │                     │ to_device_and_  │                         │
   │                     │ unit()          │                         │
   │                     ├─────────────────┤                         │
   │                     │ 1. UPDATE       │                         │
   │                     │    devices      │                         │
   │                     │    (telemetry,  │                         │
   │                     │     last_seen)  │                         │
   │                     │ 2. UPDATE       │                         │
   │                     │    units        │                         │
   │                     │    (battery,    │                         │
   │                     │     is_online,  │                         │
   │                     │     wifi_rssi,  │                         │
   │                     │     temp, etc.) │                         │
   │                     └────────┬────────┘                         │
   │                              │                                  │
   │                              │  Realtime: units table change    │
   │                              │ ──────────────────────────────────►
   │                              │                                  │
   │                              │            (shows battery, online │
   │                              │             status, temp, etc.)  │
```

---

## Database Schema Summary

### Core Tables

```sql
-- Catalog Layer
products (id, name, slug, description, ...)
device_types (id, name, slug, ...)
capabilities (id, name, factory_input_schema, factory_output_schema, ...)
firmwares (id, device_type_id, version, ...)

-- Join Tables
product_device_types (product_id, device_type_id)
device_type_capabilities (device_type_id, capability_id, configuration)

-- Instance Layer
units (id, serial_number, product_id, consumer_user_id, status,
       -- Consumer-facing telemetry (updated by heartbeat trigger):
       last_seen_at, is_online, battery_level, is_charging,
       wifi_rssi, temperature_c, humidity_pct, firmware_version, ...)
devices (id, mac_address, device_type_slug, unit_id, provision_data,
         last_seen_at, latest_telemetry, ...)

-- Telemetry
device_heartbeats (id, mac_address, unit_id, device_type, type,
                   command_id, telemetry, created_at)
```

### Key Foreign Keys

| Table | Column | References | Constraint |
|-------|--------|------------|------------|
| `units` | `product_id` | `products.id` | Every Unit is an instance of a Product |
| `devices` | `device_type_id` | `device_types.id` | Every Device is an instance of a Device Type |
| `devices` | `unit_id` | `units.id` | Every Device belongs to a Unit |
| `firmwares` | `device_type_id` | `device_types.id` | Firmware is specific to a Device Type |

---

## Common Misconceptions

### ❌ "Unit and Device are the same thing"

**Correct:** A Unit is the consumer-facing product that may contain multiple Devices. The Unit is what appears in the consumer app; Devices are internal implementation details.

### ❌ "Serial number belongs to the Device"

**Correct:** Serial numbers are assigned to Units. Devices are identified by MAC address. During provisioning, the serial number is sent to the Device for storage (so it can report its unit_id in heartbeats), but the authoritative record is the Unit.

### ❌ "Device Type is the same as Product"

**Correct:** A Product may contain multiple Device Types. Product = "Saturday Crate" (what you sell). Device Type = "crate-main-v1" (a specific PCB/SoC platform inside it).

### ❌ "Heartbeat data goes directly to the consumer app"

**Correct:** Heartbeats are Device-level telemetry stored in `device_heartbeats` as JSONB. A database trigger automatically aggregates selected fields to typed columns on the `units` table (`battery_level`, `is_online`, `wifi_rssi`, `temperature_c`, `humidity_pct`). Consumer apps subscribe to `units` via Supabase Realtime - they never read `device_heartbeats` or `devices` directly. Not all device telemetry is consumer-relevant (e.g., `free_heap`, `min_free_heap` stay on `devices.latest_telemetry` only).

### ❌ "Consumer apps need to subscribe to the devices table"

**Correct:** Consumer apps subscribe to the `units` table only. All consumer-facing telemetry is promoted to typed columns on `units` by the heartbeat trigger. The `devices` table is for admin/engineering use.

### ❌ "Each Device Type has one firmware file"

**Correct:** A Firmware version may include multiple binary files when the Device Type defines a multi-SoC board. The master SoC handles distribution to co-processors.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-06 | Initial data model documentation |
| 1.1.0 | 2026-02-16 | Added unit-level telemetry columns, heartbeat JSONB storage, updated data flow diagram |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
