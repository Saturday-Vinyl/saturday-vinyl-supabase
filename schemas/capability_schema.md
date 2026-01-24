# Saturday Capability Schema Specification

**Version:** 1.0.0
**Last Updated:** 2026-01-24
**Audience:** Saturday Admin App developers, Firmware engineers

---

## Overview

Capabilities define the configurable features of Saturday devices. Each capability specifies:

- **Factory attributes** - Configuration data stored during factory provisioning
- **Factory provision attributes** - Data returned by device after factory provisioning
- **Consumer attributes** - Configuration data stored during consumer provisioning
- **Consumer provision attributes** - Data returned by device after consumer provisioning
- **Heartbeat attributes** - Telemetry data included in periodic heartbeats
- **Tests** - Testable functions with input parameters and expected outputs

Capabilities are defined in the admin app and linked to device types. The firmware uses capability schemas to validate provisioning data and format responses.

---

## Capability Definition Schema

A capability is stored in the `capabilities` table with JSON schemas for each attribute category.

### Database Schema

```sql
CREATE TABLE capabilities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(100) UNIQUE NOT NULL,        -- e.g., "wifi", "thread", "rfid"
  display_name VARCHAR(100) NOT NULL,       -- e.g., "Wi-Fi", "Thread", "RFID"
  description TEXT,
  factory_attributes_schema JSONB DEFAULT '{}',
  factory_provision_attributes_schema JSONB DEFAULT '{}',
  consumer_attributes_schema JSONB DEFAULT '{}',
  consumer_provision_attributes_schema JSONB DEFAULT '{}',
  heartbeat_attributes_schema JSONB DEFAULT '{}',
  tests JSONB DEFAULT '[]',
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

**factory_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "ssid": {
      "type": "string",
      "maxLength": 32,
      "description": "Factory Wi-Fi network name"
    },
    "password": {
      "type": "string",
      "maxLength": 64,
      "description": "Factory Wi-Fi password"
    }
  },
  "required": []
}
```

**consumer_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "ssid": {
      "type": "string",
      "maxLength": 32,
      "description": "Consumer Wi-Fi network name"
    },
    "password": {
      "type": "string",
      "maxLength": 64,
      "description": "Consumer Wi-Fi password"
    }
  },
  "required": ["ssid", "password"]
}
```

**heartbeat_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "connected": {
      "type": "boolean",
      "description": "Currently connected to Wi-Fi"
    },
    "ssid": {
      "type": "string",
      "description": "Connected network name"
    },
    "rssi": {
      "type": "integer",
      "minimum": -100,
      "maximum": 0,
      "description": "Signal strength in dBm"
    },
    "ip_address": {
      "type": "string",
      "format": "ipv4",
      "description": "Assigned IP address"
    }
  }
}
```

**tests:**
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

Thread mesh networking for low-power devices.

**factory_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "network_name": {
      "type": "string",
      "maxLength": 16,
      "description": "Thread network name"
    },
    "pan_id": {
      "type": "integer",
      "minimum": 0,
      "maximum": 65535,
      "description": "16-bit PAN ID"
    },
    "channel": {
      "type": "integer",
      "minimum": 11,
      "maximum": 26,
      "description": "Radio channel"
    },
    "network_key": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{32}$",
      "description": "128-bit network key (32 hex chars)"
    },
    "extended_pan_id": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{16}$",
      "description": "64-bit extended PAN ID (16 hex chars)"
    },
    "mesh_local_prefix": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{16}$",
      "description": "64-bit mesh-local prefix (16 hex chars)"
    },
    "pskc": {
      "type": "string",
      "pattern": "^[0-9a-fA-F]{32}$",
      "description": "Pre-Shared Key for Commissioner (32 hex chars)"
    }
  },
  "required": []
}
```

**factory_provision_attributes_schema:**

For devices that act as Thread Border Routers, they generate network credentials on first boot:

```json
{
  "type": "object",
  "properties": {
    "network_name": {"type": "string"},
    "pan_id": {"type": "integer"},
    "channel": {"type": "integer"},
    "network_key": {"type": "string"},
    "extended_pan_id": {"type": "string"},
    "mesh_local_prefix": {"type": "string"},
    "pskc": {"type": "string"}
  },
  "description": "Thread credentials generated by Border Router during factory provisioning"
}
```

**heartbeat_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "connected": {"type": "boolean"},
    "role": {
      "type": "string",
      "enum": ["disabled", "detached", "child", "router", "leader"]
    },
    "partition_id": {"type": "integer"},
    "rloc16": {"type": "string"}
  }
}
```

**tests:**
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
  }
]
```

---

### cloud

Cloud backend connectivity.

**factory_attributes_schema:**
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

**heartbeat_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "connected": {"type": "boolean"},
    "latency_ms": {"type": "integer"},
    "last_sync_at": {"type": "string", "format": "date-time"}
  }
}
```

**tests:**
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

UHF RFID tag reading capability.

**factory_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "power_dbm": {
      "type": "integer",
      "minimum": 0,
      "maximum": 30,
      "default": 20,
      "description": "Transmit power in dBm"
    },
    "frequency_region": {
      "type": "string",
      "enum": ["US", "EU", "CN"],
      "default": "US",
      "description": "Frequency region for regulatory compliance"
    }
  }
}
```

**heartbeat_attributes_schema:**
```json
{
  "type": "object",
  "properties": {
    "module_firmware": {"type": "string"},
    "last_scan_count": {"type": "integer"},
    "antenna_connected": {"type": "boolean"}
  }
}
```

**tests:**
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

Addressable LED strip control.

**factory_attributes_schema:**
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
    },
    "brightness_max": {
      "type": "integer",
      "minimum": 0,
      "maximum": 255,
      "default": 255,
      "description": "Maximum brightness limit"
    }
  }
}
```

**tests:**
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

**heartbeat_attributes_schema:**
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

**tests:**
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

**tests:**
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

**tests:**
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
  "test_order": 1,
  "custom_defaults": {
    "power_dbm": 15
  }
}
```

---

## Firmware Integration

### Embedding Capability Schemas

Firmware can embed capability schemas at compile time or fetch them from the cloud. The recommended approach is to generate a firmware manifest JSON that includes relevant schema information.

See [Firmware Manifest Schema](firmware_manifest_schema.md) for the manifest format.

### Validating Provisioning Data

When receiving provisioning data, firmware should:

1. Parse the `factory_attributes` or `consumer_attributes` JSON
2. Validate against the embedded schema
3. Store valid attributes in NVS
4. Return error for invalid attributes

### Generating Heartbeat Data

Firmware should:

1. Collect data for each capability's `heartbeat_attributes`
2. Combine into a single `heartbeat_data` JSON object
3. POST to `device_heartbeats` table

---

## Admin App Integration

### Capability Editor UI

The admin app provides a visual editor for capability schemas:

1. Create/edit capabilities with display name and description
2. Build attribute schemas using form builders
3. Define tests with parameter and result schemas
4. Link capabilities to device types
5. Configure per-device-type settings

### Schema Validation

The admin app validates:

- Provisioning data against `factory_attributes_schema` or `consumer_attributes_schema`
- Test parameters against test `parameters_schema`
- Test results against test `result_schema`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-24 | Initial capability schema specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
