# Saturday Capability Schema Specification

**Version:** 1.4.0
**Last Updated:** 2026-02-20
**Audience:** Saturday Admin App developers, Firmware engineers

---

## Overview

Capabilities define the configurable features of Saturday devices. Each capability specifies **manifests** that inform consuming apps and firmware what data they should expect, require, and implement.

### Schema Naming Convention

Schemas follow the pattern `{phase}_{direction}_schema`:
- **phase**: `factory` or `consumer` (the provisioning phase)
- **direction**: `input` (sent TO device) or `output` (returned FROM device)

### Schema Types

| Schema | Purpose | Used By |
|--------|---------|---------|
| **factory_input_schema** | Data sent TO device during factory provisioning | Factory app (UART/WebSocket) |
| **factory_output_schema** | Data returned FROM device after factory provisioning | Factory app, Cloud |
| **consumer_input_schema** | Data sent TO device during consumer provisioning | Consumer app (BLE) |
| **consumer_output_schema** | Data returned FROM device after consumer provisioning | Consumer app, Cloud |
| **heartbeat_schema** | Telemetry data in periodic heartbeats | Cloud |
| **commands** | Capability commands with parameter/result schemas | Factory app, Admin app |

### Key Distinctions

**Factory vs Consumer:**
- **Factory provisioning** uses UART (Service Mode) or WebSocket - attributes persist through consumer reset
- **Consumer provisioning** uses BLE - attributes are wiped on consumer reset
- Consumer schemas drive **BLE service/characteristic generation** in firmware

**Input vs Output:**
- **Input** = data the app can send TO the device
- **Output** = data the device returns AFTER provisioning completes

### Important Notes

1. **Schemas are manifests**, not storage structure - they inform apps what to collect and firmware what to implement
2. **Protocol payloads are flat** - all attributes at top level, no nesting (see [Device Command Protocol](../protocols/device_command_protocol.md))
3. **Cloud storage is flat** - `devices.provision_data` stores a flat snapshot, firmware tracks factory vs consumer in NVS

---

## Capability Definition Schema

A capability is stored in the `capabilities` table with JSON schemas for each category.

### Database Schema

```sql
CREATE TABLE capabilities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(100) UNIQUE NOT NULL,              -- e.g., "wifi", "thread", "rfid"
  display_name VARCHAR(100) NOT NULL,             -- e.g., "Wi-Fi", "Thread", "RFID"
  description TEXT,
  factory_input_schema JSONB DEFAULT '{}',        -- Data sent TO device (factory)
  factory_output_schema JSONB DEFAULT '{}',       -- Data returned FROM device (factory)
  consumer_input_schema JSONB DEFAULT '{}',       -- Data sent TO device (consumer/BLE)
  consumer_output_schema JSONB DEFAULT '{}',      -- Data returned FROM device (consumer)
  heartbeat_schema JSONB DEFAULT '{}',            -- Telemetry data
  tests JSONB DEFAULT '[]',                          -- NOTE: column remains "tests" for backwards compat; conceptually "commands"
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Attribute Schema Format

Attribute schemas use JSON Schema (Draft 7) format for validation and documentation.

```json
{
  "type": "object",
  "properties": {
    "field_name": {
      "type": "string|number|boolean|object|array",
      "description": "Field description",
      "default": "optional default value"
    }
  },
  "required": ["field_name"]
}
```

---

## Standard Capabilities

### wifi

Wi-Fi connectivity for network-enabled devices.

**factory_input_schema:** (factory provisioning only - persists through reset)
```json
{
  "type": "object",
  "properties": {
    "wifi_ssid": {
      "type": "string",
      "maxLength": 32,
      "description": "Wi-Fi network name"
    },
    "wifi_password": {
      "type": "string",
      "maxLength": 64,
      "description": "Wi-Fi password"
    }
  }
}
```

**consumer_input_schema:** (consumer provisioning via BLE - wiped on reset)
```json
{
  "type": "object",
  "properties": {
    "wifi_ssid": {
      "type": "string",
      "maxLength": 32,
      "description": "Wi-Fi network name"
    },
    "wifi_password": {
      "type": "string",
      "maxLength": 64,
      "description": "Wi-Fi password"
    }
  }
}
```

**factory_output_schema:**
```json
{
  "type": "object",
  "properties": {
    "wifi_mac": {
      "type": "string",
      "description": "Wi-Fi MAC address"
    }
  }
}
```

**heartbeat_schema:**
```json
{
  "type": "object",
  "properties": {
    "wifi_connected": {
      "type": "boolean",
      "description": "Currently connected to Wi-Fi"
    },
    "wifi_ssid": {
      "type": "string",
      "description": "Connected network name"
    },
    "wifi_rssi": {
      "type": "integer",
      "minimum": -100,
      "maximum": 0,
      "description": "Signal strength in dBm"
    },
    "wifi_ip": {
      "type": "string",
      "format": "ipv4",
      "description": "Assigned IP address"
    }
  }
}
```

**commands:**
```json
[
  {
    "name": "connect",
    "display_name": "Connect to Wi-Fi",
    "description": "Test Wi-Fi connection with provided or stored credentials",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "ssid": {"type": "string", "description": "Network to connect to (optional, uses stored if omitted)"},
        "password": {"type": "string", "description": "Network password"},
        "timeout_ms": {"type": "integer", "default": 30000, "description": "Connection timeout"}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "connected": {"type": "boolean"},
        "ssid": {"type": "string"},
        "ip": {"type": "string"},
        "rssi": {"type": "integer"},
        "duration_ms": {"type": "integer"}
      }
    }
  },
  {
    "name": "scan",
    "display_name": "Scan Networks",
    "description": "Scan for available Wi-Fi networks",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "timeout_ms": {"type": "integer", "default": 10000}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "networks": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "ssid": {"type": "string"},
              "rssi": {"type": "integer"},
              "secure": {"type": "boolean"}
            }
          }
        }
      }
    }
  }
]
```

---

### thread

Thread mesh networking for low-power devices. Thread is typically factory-provisioned only (not BLE).

**factory_input_schema:** (factory provisioning only - Thread credentials are usually set at factory)
```json
{
  "type": "object",
  "properties": {
    "thread_network_name": {
      "type": "string",
      "maxLength": 16,
      "description": "Thread network name"
    },
    "thread_pan_id": {
      "type": "integer",
      "minimum": 0,
      "maximum": 65535,
      "description": "16-bit PAN ID"
    },
    "thread_channel": {
      "type": "integer",
      "minimum": 11,
      "maximum": 26,
      "description": "Radio channel"
    },
    "thread_network_key": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{32}$",
      "description": "128-bit network key (32 hex chars)"
    },
    "thread_extended_pan_id": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{16}$",
      "description": "64-bit extended PAN ID (16 hex chars)"
    },
    "thread_mesh_local_prefix": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{16}$",
      "description": "64-bit mesh-local prefix (16 hex chars)"
    },
    "thread_pskc": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{32}$",
      "description": "Pre-Shared Key for Commissioner (32 hex chars)"
    }
  }
}
```

**consumer_input_schema:** (empty - Thread credentials are written via the Thread Dataset BLE characteristic 0x0020)
```json
{}
```

**consumer_output_schema:** (returned after successful BLE provisioning)
```json
{
  "type": "object",
  "properties": {
    "thread_network_name": {
      "type": "string",
      "description": "Name of the joined Thread network"
    }
  }
}
```

**factory_output_schema:**

For devices that act as Thread Border Routers, they generate network credentials on first boot:

```json
{
  "type": "object",
  "properties": {
    "thread_network_name": {"type": "string"},
    "thread_pan_id": {"type": "integer"},
    "thread_channel": {"type": "integer"},
    "thread_network_key": {"type": "string"},
    "thread_extended_pan_id": {"type": "string"},
    "thread_mesh_local_prefix": {"type": "string"},
    "thread_pskc": {"type": "string"}
  },
  "description": "Thread credentials generated by Border Router during provisioning"
}
```

**heartbeat_schema:**
```json
{
  "type": "object",
  "properties": {
    "thread_connected": {"type": "boolean"},
    "thread_role": {
      "type": "string",
      "enum": ["disabled", "detached", "child", "router", "leader"]
    },
    "thread_partition_id": {"type": "integer"},
    "thread_rloc16": {"type": "string"}
  }
}
```

**commands:**
```json
[
  {
    "name": "join",
    "display_name": "Join Thread Network",
    "description": "Join Thread network with provided or stored credentials",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "network_name": {"type": "string"},
        "network_key": {"type": "string"},
        "timeout_ms": {"type": "integer", "default": 60000}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "connected": {"type": "boolean"},
        "role": {"type": "string"},
        "duration_ms": {"type": "integer"}
      }
    }
  },
  {
    "name": "get_dataset",
    "display_name": "Get Thread Dataset",
    "description": "Returns the full active Thread operational dataset for credential comparison between devices. Use this to diagnose join failures by comparing all credential fields between the Border Router and a node stuck in detached state.",
    "parameters_schema": {
      "type": "object",
      "properties": {}
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "network_name": {"type": "string", "description": "Thread network name"},
        "pan_id": {"type": "integer", "description": "16-bit PAN ID"},
        "channel": {"type": "integer", "description": "Radio channel (11-26)"},
        "network_key": {"type": "string", "description": "128-bit network key (32 hex chars)"},
        "extended_pan_id": {"type": "string", "description": "64-bit extended PAN ID (16 hex chars)"},
        "mesh_local_prefix": {"type": "string", "description": "64-bit mesh-local prefix (16 hex chars)"},
        "attached": {"type": "boolean", "description": "Whether device is attached to a Thread network"},
        "role": {"type": "string", "enum": ["disabled", "detached", "attaching", "child", "router", "leader"]},
        "rloc16": {"type": "integer", "description": "16-bit Router Locator address"},
        "device_count": {"type": "integer", "description": "Number of devices on the network"}
      }
    }
  },
  {
    "name": "register",
    "display_name": "Re-register with Hub",
    "description": "Hub-initiated command sent when a node's heartbeat arrives but the node is not in the Hub's registration cache (e.g., after Hub restart). The node should respond by sending POST /register to re-establish its identity.",
    "parameters_schema": {
      "type": "object",
      "properties": {}
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "registered": {"type": "boolean", "description": "Whether re-registration succeeded"}
      }
    }
  }
]
```

---

### cloud

Cloud backend connectivity. Cloud credentials are factory-provisioned only.

**factory_input_schema:** (factory provisioning only - cloud credentials are sensitive)
```json
{
  "type": "object",
  "properties": {
    "cloud_url": {
      "type": "string",
      "format": "uri",
      "description": "Supabase project URL"
    },
    "cloud_anon_key": {
      "type": "string",
      "description": "Supabase anonymous key"
    },
    "cloud_device_secret": {
      "type": "string",
      "description": "Device-specific authentication secret"
    }
  },
  "required": ["cloud_url", "cloud_anon_key"]
}
```

**consumer_input_schema:** (empty - cloud credentials not set via BLE)
```json
{}
```

**heartbeat_schema:**
```json
{
  "type": "object",
  "properties": {
    "cloud_connected": {"type": "boolean"},
    "cloud_latency_ms": {"type": "integer"},
    "cloud_last_sync_at": {"type": "string", "format": "date-time"}
  }
}
```

**commands:**
```json
[
  {
    "name": "ping",
    "display_name": "Test Cloud Connection",
    "description": "Verify cloud API connectivity",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "timeout_ms": {"type": "integer", "default": 15000}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "connected": {"type": "boolean"},
        "status_code": {"type": "integer"},
        "latency_ms": {"type": "integer"}
      }
    }
  }
]
```

---

### rfid

UHF RFID tag reading capability. RFID settings are factory-provisioned.

**factory_input_schema:** (factory provisioning only)
```json
{
  "type": "object",
  "properties": {
    "rfid_power_dbm": {
      "type": "integer",
      "minimum": 0,
      "maximum": 30,
      "default": 20,
      "description": "Transmit power in dBm"
    },
    "rfid_frequency_region": {
      "type": "string",
      "enum": ["US", "EU", "CN"],
      "default": "US",
      "description": "Frequency region for regulatory compliance"
    }
  }
}
```

**consumer_input_schema:** (empty - RFID settings not set via BLE)
```json
{}
```

**heartbeat_schema:**
```json
{
  "type": "object",
  "properties": {
    "rfid_module_firmware": {"type": "string"},
    "rfid_last_scan_count": {"type": "integer"},
    "rfid_antenna_connected": {"type": "boolean"}
  }
}
```

**commands:**
```json
[
  {
    "name": "scan",
    "display_name": "Scan for Tags",
    "description": "Scan for RFID tags in range",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "duration_ms": {"type": "integer", "default": 5000},
        "power_dbm": {"type": "integer", "default": 20}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "module_firmware": {"type": "string"},
        "tags_found": {"type": "integer"},
        "tags": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "epc": {"type": "string"},
              "rssi": {"type": "integer"}
            }
          }
        }
      }
    }
  }
]
```

---

### led

Addressable LED strip control. LED hardware config is factory-set, brightness can be consumer-adjusted.

**factory_input_schema:** (factory provisioning - hardware configuration)
```json
{
  "type": "object",
  "properties": {
    "led_count": {
      "type": "integer",
      "minimum": 1,
      "description": "Number of LEDs in the strip"
    },
    "led_type": {
      "type": "string",
      "enum": ["SK6812", "WS2812B", "APA102"],
      "description": "LED chip type"
    }
  }
}
```

**consumer_input_schema:** (consumer provisioning via BLE - user preferences)
```json
{
  "type": "object",
  "properties": {
    "led_brightness_max": {
      "type": "integer",
      "minimum": 0,
      "maximum": 255,
      "default": 255,
      "description": "Maximum brightness limit"
    }
  }
}
```

**commands:**
```json
[
  {
    "name": "pattern",
    "display_name": "Test LED Pattern",
    "description": "Display test pattern on LED strip",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "pattern": {
          "type": "string",
          "enum": ["rainbow", "solid", "chase", "fade"],
          "default": "rainbow"
        },
        "color": {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"},
        "duration_ms": {"type": "integer", "default": 3000}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "led_count": {"type": "integer"},
        "led_type": {"type": "string"}
      }
    }
  }
]
```

---

### environment

Temperature and humidity sensing.

**heartbeat_schema:**
```json
{
  "type": "object",
  "properties": {
    "temperature_c": {"type": "number"},
    "humidity_pct": {"type": "number"},
    "in_safe_range": {"type": "boolean"}
  }
}
```

**commands:**
```json
[
  {
    "name": "read",
    "display_name": "Read Environment",
    "description": "Read current temperature and humidity",
    "parameters_schema": {"type": "object", "properties": {}},
    "result_schema": {
      "type": "object",
      "properties": {
        "sensor_type": {"type": "string"},
        "temperature_c": {"type": "number"},
        "temperature_f": {"type": "number"},
        "humidity_pct": {"type": "number"},
        "in_safe_range": {"type": "boolean"}
      }
    }
  }
]
```

---

### motion

Accelerometer/motion detection.

**commands:**
```json
[
  {
    "name": "detect",
    "display_name": "Detect Motion",
    "description": "Wait for motion to be detected",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "timeout_ms": {"type": "integer", "default": 30000},
        "sensitivity": {"type": "string", "enum": ["low", "medium", "high"], "default": "medium"}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "sensor_type": {"type": "string"},
        "detected": {"type": "boolean"},
        "wait_time_ms": {"type": "integer"}
      }
    }
  }
]
```

---

### button

Physical button input.

**commands:**
```json
[
  {
    "name": "press",
    "display_name": "Wait for Button Press",
    "description": "Wait for button to be pressed",
    "parameters_schema": {
      "type": "object",
      "properties": {
        "timeout_ms": {"type": "integer", "default": 30000},
        "button_id": {"type": "string", "default": "main"}
      }
    },
    "result_schema": {
      "type": "object",
      "properties": {
        "button_id": {"type": "string"},
        "pressed": {"type": "boolean"},
        "press_duration_ms": {"type": "integer"}
      }
    }
  }
]
```

---

## Device Type Capability Configuration

Capabilities are linked to device types via the `device_type_capabilities` junction table:

```sql
CREATE TABLE device_type_capabilities (
  id UUID PRIMARY KEY,
  device_type_id UUID REFERENCES device_types(id),
  capability_id UUID REFERENCES capabilities(id),
  configuration JSONB DEFAULT '{}',
  UNIQUE(device_type_id, capability_id)
);
```

The `configuration` field allows per-device-type customization of the capability:

```json
{
  "required_for_provisioning": true,
  "included_in_heartbeat": true,
  "command_order": 1,
  "custom_defaults": {
    "power_dbm": 15
  }
}
```

---

## Firmware Integration

### Embedding Capability Schemas

Firmware can embed capability schemas at compile time or fetch them from the cloud. The recommended approach is to use the `get_capabilities` command (see the [Device Command Protocol](../protocols/device_command_protocol.md)) to return capability information.

### Validating Provisioning Data

When receiving provisioning data, firmware should:

1. Parse the flat `params` JSON from the command
2. Determine if this is factory (UART/WebSocket) or consumer (BLE) provisioning
3. Validate field names and types against appropriate schema:
   - Factory: `factory_input_schema`
   - Consumer: `consumer_input_schema`
4. Store valid attributes in NVS (mark as factory or consumer for reset behavior)
5. Return error for invalid attributes

### BLE Service Generation

Firmware uses `consumer_input_schema` to generate BLE services:

1. Each field in `consumer_input_schema` becomes a BLE characteristic
2. Field types map to BLE data types (string -> UTF-8, integer -> uint32, etc.)
3. Required fields have write permission, optional fields have read+write
4. Factory attributes are NOT exposed via BLE

### Consumer Reset Behavior

On consumer reset:
1. Attributes from `consumer_input_schema` are wiped from NVS
2. Attributes from `factory_input_schema` are preserved
3. Device returns to factory-provisioned state

### Generating Heartbeat Data

Firmware should:

1. Collect data for each capability's `heartbeat_schema`
2. Combine all fields at the top level (no nesting)
3. POST to `device_heartbeats` table

---

## Admin App Integration

### Capability Editor UI

The admin app provides a visual editor for capability schemas:

1. Create/edit capabilities with display name and description
2. Build input/output schemas for factory and consumer phases using form builders
3. Define commands with parameter and result schemas
4. Link capabilities to device types
5. Configure per-device-type settings

### Schema Validation

The admin app validates:

- Factory provisioning data against `factory_input_schema`
- Consumer provisioning data against `consumer_input_schema`
- Factory provision responses against `factory_output_schema`
- Consumer provision responses against `consumer_output_schema`
- Heartbeat data against `heartbeat_schema`
- Command parameters against command `parameters_schema`
- Command results against command `result_schema`

---

## Command Categories

Capability commands fall into three categories:

| Category | Purpose | Examples |
|----------|---------|---------|
| **Tests** | Validate hardware or connectivity | `connect`, `join`, `ping` |
| **Queries** | Read device state without side effects | `get_dataset`, `read` |
| **Actions** | Trigger behavior or state change | `pattern`, `register`, `scan` |

The category is informational — it helps the admin app present commands appropriately (e.g., "Run Test" vs "Query" vs "Action" buttons). Firmware dispatch does not distinguish between categories; all are flat `cmd` values.

---

## Command Uniqueness

Command names are flat strings with no namespace prefix (e.g., `get_dataset`, not `thread.get_dataset` or `thread_get_dataset`).

**Uniqueness is enforced by the admin app per device type.** The admin app defines which capabilities a device type has, and each capability defines its commands. If two capabilities assigned to the same device type define the same command name, the admin app must catch this conflict when configuring device type capabilities.

In practice, the current command set has no conflicts across capabilities, and with a small number of capabilities per device type, collisions are unlikely.

---

## Database Migration Note

- The database column remains `tests` (JSONB) for backwards compatibility
- The firmware JSON schema key output by the admin app remains `tests` until an admin app migration renames it
- Firmware accepts `run_test` as a deprecated alias that extracts `test_name` and re-dispatches as a flat command
- Documentation uses `commands` to reflect the conceptual rename

---

## Adding a New Command (Process Guide)

When adding a new capability command to the Saturday ecosystem:

1. **Define the command contract** — Choose which capability it belongs to, pick a unique command name, define parameter schema and result schema. Classify as test/query/action. Ensure the name doesn't conflict with other commands on the same device type.

2. **Update capability schema documentation** — Add the command to the relevant capability's `commands` array in this document (`shared-docs/schemas/capability_schema.md`).

3. **Update protocol documentation** — If the command introduces new protocol behavior (like `register` being hub-initiated), document it in `device_command_protocol.md` and/or `coap_mesh_protocol.md`.

4. **Update admin app** — Add the command to the capability's `tests` array (column rename pending) in the admin app's capability editor. This makes it available in firmware JSON schemas.

5. **Implement in firmware** — Add a `strcmp` entry for the command name in the firmware's flat command dispatch table (see `serial_prov.c`). The command name on the wire is just the flat name (e.g., `"register"`, `"get_dataset"`).

6. **Test the full loop** — Send via admin app → WebSocket/UART → device executes → result flows back via heartbeat.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.4.0 | 2026-02-20 | Renamed `tests` → `commands` throughout; added `register` command to thread capability; added Command Categories, Command Uniqueness, Database Migration Note, and Process Guide sections |
| 1.3.0 | 2026-01-26 | Renamed schemas to `{phase}_{direction}_schema` pattern for clarity |
| 1.2.0 | 2026-01-25 | Clarified purpose of 4 schema types; added BLE service generation and consumer reset behavior documentation |
| 1.1.0 | 2026-01-25 | Added capability prefixes to field names for flat protocol |
| 1.0.0 | 2026-01-24 | Initial capability schema specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
