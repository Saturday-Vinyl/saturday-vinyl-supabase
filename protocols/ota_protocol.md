# Saturday Vinyl OTA Push Protocol Specification

This document defines the Over-The-Air (OTA) update protocol for Saturday Vinyl devices, enabling remote firmware updates triggered by admin tools, consumer apps, or automated systems.

## Overview

| Property | Value |
|----------|-------|
| Transport | Supabase Realtime (WebSocket) |
| Database | Supabase PostgreSQL |
| Firmware Storage | Supabase Storage |
| Push Latency | < 5 seconds typical |

### Key Features

- **Push Updates**: Apps can trigger device updates without local access
- **Dual-SoC Support**: Single request can update multiple processors (Hub S3 + H2)
- **Thread Relay**: Hub relays OTA to Thread-only devices (Crate)
- **Progress Tracking**: Real-time status updates visible to apps
- **Auto-Apply**: Devices automatically install updates on receipt

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CLOUD LAYER                                │
├─────────────────────────────────────────────────────────────────────┤
│  Supabase                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ firmware_releases│  │ device_commands  │  │ update_requests  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │             │
│           └─────────────────────┼─────────────────────┘             │
│                                 │                                    │
│                    ┌────────────▼────────────┐                      │
│                    │   Supabase Realtime     │                      │
│                    │   (WebSocket Channel)   │                      │
│                    └────────────┬────────────┘                      │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ WebSocket
                    ┌─────────────▼─────────────┐
                    │         HUB (S3)          │
                    │  ┌─────────────────────┐  │
                    │  │ realtime_client.c   │  │
                    │  │ - Subscribe to cmds │  │
                    │  │ - Process updates   │  │
                    │  │ - Report status     │  │
                    │  └─────────┬───────────┘  │
                    │            │ UART         │
                    │  ┌─────────▼───────────┐  │
                    │  │       H2 (Thread)   │  │
                    │  │  - Border Router    │  │
                    │  │  - CoAP relay       │  │
                    │  └─────────┬───────────┘  │
                    └────────────┼──────────────┘
                                 │ Thread/CoAP
                    ┌────────────▼──────────────┐
                    │         CRATE             │
                    │  - Receives OTA via CoAP  │
                    │  - Self-updates flash     │
                    └───────────────────────────┘
```

---

## Device Types

| Device Type | Connectivity | OTA Method | Components |
|-------------|--------------|------------|------------|
| `hub` | WiFi → Supabase | Direct WebSocket | S3 + H2 (dual-SoC) |
| `hub_s3` | WiFi → Supabase | Direct WebSocket | S3 only |
| `hub_h2` | WiFi → Supabase | Direct WebSocket | H2 only (via S3) |
| `crate` | Thread → Hub | CoAP relay | Single SoC |

### Dual-SoC Device Handling

The Hub contains two processors that can be updated independently or together:

**Update Request Types:**
- `device_type = 'hub'` → Update **both** S3 and H2 (if newer versions exist)
- `device_type = 'hub_s3'` → Update **only** the S3 processor
- `device_type = 'hub_h2'` → Update **only** the H2 processor

---

## Database Schema

### firmware_releases

Stores available firmware versions.

```sql
CREATE TABLE firmware_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_type TEXT NOT NULL,           -- 'hub_s3', 'hub_h2', 'crate'
    version TEXT NOT NULL,               -- Semantic version "1.2.3"
    version_major INTEGER NOT NULL,
    version_minor INTEGER NOT NULL,
    version_patch INTEGER NOT NULL,
    firmware_url TEXT NOT NULL,          -- Supabase Storage URL
    firmware_size INTEGER NOT NULL,      -- Bytes
    firmware_sha256 TEXT NOT NULL,       -- SHA-256 hash (hex)
    release_notes TEXT,
    min_required_version TEXT,           -- Minimum version that can upgrade
    is_critical BOOLEAN DEFAULT FALSE,   -- Security/stability critical
    created_at TIMESTAMPTZ DEFAULT NOW(),
    released_at TIMESTAMPTZ,             -- NULL = draft, set = published
    UNIQUE(device_type, version)
);
```

**Notes:**
- `device_type` uses `hub_s3`/`hub_h2` (not `hub`) since firmware is per-processor
- `released_at = NULL` means draft/testing; set to publish
- `is_critical = true` triggers priority update behavior

### update_requests

Pending and historical update requests from apps.

```sql
CREATE TABLE update_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_serial TEXT NOT NULL,
    device_type TEXT NOT NULL,           -- 'hub', 'hub_s3', 'hub_h2', 'crate'
    target_version TEXT,                 -- NULL = latest available
    requested_by TEXT NOT NULL,          -- 'admin:email', 'consumer:user_id', 'system'
    request_source TEXT NOT NULL,        -- 'admin_app', 'consumer_app', 'scheduled'
    priority TEXT DEFAULT 'normal',      -- 'low', 'normal', 'high', 'critical'
    status TEXT DEFAULT 'pending',       -- See lifecycle states below
    component_status JSONB DEFAULT '{}', -- Per-component: {"hub_s3": "complete", "hub_h2": "downloading"}
    created_at TIMESTAMPTZ DEFAULT NOW(),
    notified_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0
);

CREATE INDEX idx_update_requests_device ON update_requests(device_serial, status);
```

### device_commands

General command queue (not OTA-specific).

```sql
CREATE TABLE device_commands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_serial TEXT NOT NULL,
    command TEXT NOT NULL,               -- 'check_update', 'reboot', 'factory_reset', etc.
    parameters JSONB DEFAULT '{}',
    priority INTEGER DEFAULT 0,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by TEXT,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
    sent_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    result JSONB
);

CREATE INDEX idx_device_commands_device ON device_commands(device_serial, status);
```

---

## Update Request Lifecycle

```
┌─────────┐    ┌──────────┐    ┌─────────────┐    ┌──────────┐    ┌──────────┐
│ pending │───►│ notified │───►│ downloading │───►│ applying │───►│ complete │
└─────────┘    └──────────┘    └─────────────┘    └──────────┘    └──────────┘
     │              │                │                  │
     │              │                │                  │
     └──────────────┴────────────────┴──────────────────┴────────►┌────────┐
                                                                  │ failed │
                                                                  └────────┘
```

| State | Description |
|-------|-------------|
| `pending` | Request created, device not yet notified |
| `notified` | Device received push notification |
| `downloading` | Device is downloading firmware |
| `applying` | Device is flashing/rebooting |
| `complete` | Update successfully applied |
| `failed` | Update failed (see `error_message`) |

### Component Status (Dual-SoC)

For `device_type = 'hub'`, the `component_status` JSONB tracks each processor:

```json
{
  "hub_s3": "complete",
  "hub_h2": "applying"
}
```

Overall `status` is derived:
- `complete` when all components are `complete`
- `failed` if any component is `failed`
- Otherwise, the earliest active state

---

## Supabase Realtime Protocol

### Channel Subscription

Devices subscribe to their dedicated channel after WiFi connection:

```
Channel: device:{unit_id}
Example: device:SV-HUB-A1B2C3
```

### Event Types

| Event | Direction | Description |
|-------|-----------|-------------|
| `update_available` | Cloud → Device | New firmware ready |
| `command` | Cloud → Device | General command (reboot, etc.) |
| `config_update` | Cloud → Device | Configuration change |

### update_available Event

Sent when a new update request is created.

**Single Component (hub_s3, hub_h2, or crate):**

```json
{
  "event": "update_available",
  "payload": {
    "request_id": "550e8400-e29b-41d4-a716-446655440000",
    "device_type": "hub_s3",
    "version": "1.2.0",
    "download_url": "https://xyz.supabase.co/storage/v1/object/firmware/hub_s3_1.2.0.bin",
    "firmware_size": 1048576,
    "sha256": "a1b2c3d4e5f6...",
    "is_critical": false
  }
}
```

**Multi-Component (hub = S3 + H2):**

```json
{
  "event": "update_available",
  "payload": {
    "request_id": "550e8400-e29b-41d4-a716-446655440000",
    "device_type": "hub",
    "components": [
      {
        "type": "hub_s3",
        "version": "1.2.0",
        "download_url": "https://xyz.supabase.co/storage/v1/object/firmware/hub_s3_1.2.0.bin",
        "firmware_size": 1048576,
        "sha256": "a1b2c3d4..."
      },
      {
        "type": "hub_h2",
        "version": "1.1.0",
        "download_url": "https://xyz.supabase.co/storage/v1/object/firmware/hub_h2_1.1.0.bin",
        "firmware_size": 262144,
        "sha256": "e5f6a7b8..."
      }
    ],
    "is_critical": false
  }
}
```

### Status Reporting

Devices update status by calling Supabase REST API:

```http
PATCH /rest/v1/update_requests?id=eq.{request_id}
Content-Type: application/json
Authorization: Bearer {device_token}

{
  "status": "downloading",
  "started_at": "2024-01-15T10:30:00Z"
}
```

For dual-SoC updates:

```json
{
  "status": "applying",
  "component_status": {
    "hub_s3": "complete",
    "hub_h2": "applying"
  }
}
```

---

## Hub OTA Flow (WiFi Devices)

### Single-Component Update (S3 or H2)

```
1. App inserts update_requests row
2. Database trigger broadcasts to Realtime channel
3. Hub receives update_available event
4. Hub ACKs receipt (status → 'notified')
5. Hub downloads firmware (status → 'downloading')
6. Hub applies update (status → 'applying')
7. Hub reboots and verifies
8. Hub reports completion (status → 'complete')
```

### Dual-Component Update (S3 + H2)

When `device_type = 'hub'`:

```
1. Cloud sends update_available with components array
2. Hub acknowledges (status → 'notified')

3. PHASE 1: Update S3
   a. Download S3 firmware to OTA partition
   b. component_status: {"hub_s3": "downloading", "hub_h2": "pending"}
   c. Download H2 firmware to h2_fw staging partition
   d. component_status: {"hub_s3": "applying", "hub_h2": "pending"}
   e. Set NVS flag: "pending_h2_update = true"
   f. Reboot to apply S3 update

4. PHASE 2: Update H2 (after S3 reboot)
   a. S3 boots, detects "pending_h2_update" flag
   b. component_status: {"hub_s3": "complete", "hub_h2": "applying"}
   c. Flash H2 via esp-serial-flasher
   d. Clear NVS flag
   e. component_status: {"hub_s3": "complete", "hub_h2": "complete"}
   f. status → 'complete'
```

**Why S3 First?**
- S3 is the master controller; H2 depends on it
- H2 firmware is staged in S3's flash before reboot
- If H2 update fails, S3 can retry without re-downloading

---

## Crate OTA Flow (Thread Devices)

Thread devices cannot connect directly to Supabase. The Hub acts as a relay:

```
┌─────────┐        ┌──────────────────┐        ┌─────────────┐
│  Cloud  │───────►│       Hub        │───────►│    Crate    │
│         │        │  S3 ←─UART─► H2  │        │  (Thread)   │
└─────────┘        └──────────────────┘        └─────────────┘
     │                     │                         │
     │ 1. update_available │                         │
     │    (device_type=    │                         │
     │    'crate')         │                         │
     │────────────────────►│                         │
     │                     │ 2. Check crate online   │
     │                     │    (ping via H2)        │
     │                     │────────────────────────►│
     │                     │◄────────────────────────│
     │                     │                         │
     │                     │ 3. Download crate FW    │
     │                     │    to staging           │
     │                     │                         │
     │                     │ 4. S3H2_CMD_OTA_START   │
     │                     │────► H2                 │
     │                     │                         │
     │                     │ 5. CoAP OTA to Crate    │
     │                     │      H2 ───────────────►│
     │                     │      (block transfer)   │
     │                     │                         │
     │                     │ 6. EVT_OTA_PROGRESS     │
     │                     │◄──── H2                 │
     │                     │                         │
     │                     │ 7. Crate reboots        │
     │                     │                    ┌────┤
     │                     │                    │    │
     │                     │                    └───►│
     │                     │                         │
     │ 8. status=complete  │                         │
     │◄────────────────────│                         │
```

### S3-H2 Protocol Extensions

See [S3-H2 Protocol](../../shared/include/s3_h2_protocol.h) for full frame format.

**OTA Commands (S3 → H2):**

| Command | Value | Description |
|---------|-------|-------------|
| `S3H2_CMD_OTA_START_CRATE` | 0x20 | Initiate OTA to crate |
| `S3H2_CMD_OTA_DATA_CRATE` | 0x21 | Send firmware chunk |
| `S3H2_CMD_OTA_COMPLETE_CRATE` | 0x22 | Finalize OTA |
| `S3H2_CMD_OTA_ABORT_CRATE` | 0x23 | Cancel OTA |

**OTA Events (H2 → S3):**

| Event | Value | Description |
|-------|-------|-------------|
| `S3H2_EVT_OTA_PROGRESS` | 0xE5 | Progress percentage |
| `S3H2_EVT_OTA_COMPLETE` | 0xE6 | OTA result (success/fail) |

### CoAP OTA Endpoints

See [CoAP Protocol](./coap_protocol.md) for transport details.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ota/start` | POST | Begin OTA session |
| `/ota/data` | POST | Transfer data blocks |
| `/ota/verify` | POST | Verify and apply |

### Offline Crate Handling

If Crate is unreachable when update is requested:

1. Hub pings Crate via H2 CoAP
2. If no response within 10 seconds: status → `failed`
3. Error message: `"device_unreachable"`
4. App notifies user to ensure Crate is powered on
5. User can retry when Crate is online

---

## App Integration

### Admin App (Flutter)

```dart
class OtaService {
  final SupabaseClient supabase;

  /// Push update to specific device
  Future<String> pushUpdate({
    required String deviceSerial,
    required String deviceType,  // 'hub', 'hub_s3', 'hub_h2', 'crate'
    String? targetVersion,       // null = latest
    String priority = 'normal',
  }) async {
    final response = await supabase.from('update_requests').insert({
      'device_serial': deviceSerial,
      'device_type': deviceType,
      'target_version': targetVersion,
      'requested_by': 'admin:${currentUser.email}',
      'request_source': 'admin_app',
      'priority': priority,
    }).select('id').single();

    return response['id'];
  }

  /// Monitor update progress
  Stream<Map<String, dynamic>> watchUpdate(String requestId) {
    return supabase
        .from('update_requests')
        .stream(primaryKey: ['id'])
        .eq('id', requestId);
  }
}
```

### Consumer App (Flutter)

```dart
class DeviceUpdateService {
  /// Check for available updates
  Future<List<UpdateInfo>> checkUpdates(List<String> deviceSerials) async {
    // Query firmware_releases for newer versions
    // Compare with device's current version from heartbeats
    // Return list of available updates
  }

  /// Request update (user-initiated)
  Future<String> requestUpdate(String deviceSerial) async {
    final response = await supabase.from('update_requests').insert({
      'device_serial': deviceSerial,
      'device_type': 'hub',  // Determined from device metadata
      'requested_by': 'consumer:${currentUser.id}',
      'request_source': 'consumer_app',
      'priority': 'normal',
    }).select('id').single();

    return response['id'];
  }
}
```

---

## Error Handling

### Error Codes

| Code | Description | Recovery |
|------|-------------|----------|
| `device_unreachable` | Thread device not responding | Retry when online |
| `download_failed` | Failed to download firmware | Automatic retry (3x) |
| `checksum_mismatch` | SHA-256 verification failed | Re-download |
| `flash_failed` | Failed to write to flash | Report to support |
| `boot_failed` | Device failed to boot new firmware | Automatic rollback |
| `timeout` | Operation timed out | Retry |

### Retry Strategy

```
Attempt 1: Immediate
Attempt 2: 30 seconds delay
Attempt 3: 2 minutes delay
Maximum:   3 attempts per request
```

After 3 failures:
- status → `failed`
- App notified via Realtime
- User can create new request

### Rollback

ESP-IDF OTA supports automatic rollback:
1. New firmware marked "pending verification"
2. If boot fails or app doesn't confirm, bootloader reverts
3. Hub reports rollback via status update

---

## Security Considerations

### Firmware Integrity

- All firmware signed with SHA-256 hash
- Device verifies hash before applying
- Supabase Storage provides HTTPS transport

### Authentication

- Devices use JWT for Supabase API calls
- Token scoped to device's own records
- Token refresh handled automatically

### RLS Policies

```sql
-- Devices can read their own requests
CREATE POLICY "devices_read_own" ON update_requests
    FOR SELECT USING (device_serial = current_device_serial());

-- Devices can update status only
CREATE POLICY "devices_update_status" ON update_requests
    FOR UPDATE USING (device_serial = current_device_serial())
    WITH CHECK (/* only status fields */);

-- Admin app can create/read all
CREATE POLICY "admin_full_access" ON update_requests
    FOR ALL USING (auth.jwt()->>'role' = 'admin');
```

---

## Deployment Setup

### 1. Run Database Migration

Execute the migration in Supabase SQL Editor:

```
supabase/migrations/20260122_ota_push_tables.sql
```

This creates:
- `firmware_releases` table with RLS policies
- `update_requests` table with Realtime broadcast trigger
- `device_commands` table with command queue
- Views: `latest_firmware`, `pending_updates`, `pending_commands`

### 2. Create Firmware Storage Bucket

In Supabase Dashboard → Storage:

1. **Create bucket**: `firmware`
2. **Settings**:
   - Public bucket: `true` (devices download without auth)
   - File size limit: `10MB` (typical firmware ~1-4MB)
   - Allowed MIME types: `application/octet-stream`

**Bucket Policy (SQL)**:

```sql
-- Allow public read access to firmware files
CREATE POLICY "Public read firmware" ON storage.objects
    FOR SELECT
    TO anon, authenticated
    USING (bucket_id = 'firmware');

-- Only service role can upload firmware
CREATE POLICY "Service role upload firmware" ON storage.objects
    FOR INSERT
    TO service_role
    WITH CHECK (bucket_id = 'firmware');

-- Only service role can delete firmware
CREATE POLICY "Service role delete firmware" ON storage.objects
    FOR DELETE
    TO service_role
    USING (bucket_id = 'firmware');
```

### 3. Upload Firmware Files

**Naming Convention**:
```
{device_type}_{version}.bin

Examples:
  hub_s3_1.0.0.bin
  hub_h2_1.0.0.bin
  crate_1.0.0.bin
```

**Upload via CLI**:
```bash
# Using Supabase CLI
supabase storage cp ./build/hub_s3.bin storage://firmware/hub_s3_1.0.0.bin
```

**Upload via Dashboard**:
1. Go to Storage → firmware bucket
2. Click Upload
3. Select firmware binary
4. Note the public URL

### 4. Register Firmware Release

After uploading, register in database:

```sql
INSERT INTO firmware_releases (
    device_type,
    version,
    version_major,
    version_minor,
    version_patch,
    firmware_url,
    firmware_size,
    firmware_sha256,
    release_notes,
    released_at
) VALUES (
    'hub_s3',
    '1.0.0',
    1, 0, 0,
    'https://YOUR_PROJECT.supabase.co/storage/v1/object/public/firmware/hub_s3_1.0.0.bin',
    1048576,  -- File size in bytes
    'sha256_hash_here',  -- Run: shasum -a 256 hub_s3_1.0.0.bin
    'Initial release',
    NOW()  -- Set to publish immediately, NULL for draft
);
```

**Generate SHA-256 hash**:
```bash
shasum -a 256 hub_s3_1.0.0.bin | cut -d' ' -f1
```

### 5. Verify Setup

**Check firmware is accessible**:
```bash
curl -I https://YOUR_PROJECT.supabase.co/storage/v1/object/public/firmware/hub_s3_1.0.0.bin
# Should return 200 OK
```

**Test Realtime broadcast**:
```sql
-- Insert test update request (triggers broadcast)
INSERT INTO update_requests (
    device_serial,
    device_type,
    requested_by,
    request_source
) VALUES (
    'SV-HUB-TEST123',
    'hub_s3',
    'admin:test@example.com',
    'admin_app'
);
```

Monitor Realtime channel `device:SV-HUB-TEST123` for `update_available` event.

---

## Protocol Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification |

---

## Related Documents

- [CoAP Protocol](./coap_protocol.md) - Thread device communication
- [Service Mode Protocol](./service_mode_protocol.md) - USB serial interface
- [BLE Provisioning Protocol](./ble_provisioning_protocol.md) - Mobile app device setup
- [S3-H2 Protocol](../../shared/include/s3_h2_protocol.h) - Inter-processor communication
