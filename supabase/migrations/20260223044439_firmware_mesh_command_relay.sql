-- Mesh Command Relay: Route commands to Thread devices through their Hub
--
-- Thread mesh devices (Crates, etc.) lack direct cloud connectivity.
-- When a command targets a mesh device, the broadcast trigger now detects
-- the device's hub relationship and routes the command to the Hub's
-- WebSocket channel with a target_mac field. The Hub firmware already
-- handles target_mac relay (realtime_client.c:1423-1448).
--
-- Changes:
-- 1. Add hub_mac_address column to devices table
-- 2. Modify sync_heartbeat_to_device_and_unit() to auto-populate hub_mac_address
-- 3. Modify broadcast_device_command() to route through hub when applicable

-- =============================================================================
-- 1. Add hub_mac_address to devices
-- =============================================================================

ALTER TABLE devices ADD COLUMN IF NOT EXISTS hub_mac_address VARCHAR(17);

COMMENT ON COLUMN devices.hub_mac_address IS
  'MAC address of the Hub that provides cloud connectivity for this device. '
  'NULL for devices with direct cloud access (WiFi). '
  'Auto-populated from relayed heartbeat relay_instance_id.';

CREATE INDEX IF NOT EXISTS idx_devices_hub_mac
  ON devices (hub_mac_address)
  WHERE hub_mac_address IS NOT NULL;

-- =============================================================================
-- 2. Modify sync_heartbeat_to_device_and_unit() to set hub_mac_address
-- =============================================================================

CREATE OR REPLACE FUNCTION sync_heartbeat_to_device_and_unit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unit_id UUID;
  v_telemetry JSONB;
  v_battery_level INTEGER;
  v_is_charging BOOLEAN;
  v_wifi_rssi INTEGER;
  v_temperature_c NUMERIC;
  v_humidity_pct NUMERIC;
  v_firmware_version TEXT;
  v_heartbeat_ts TIMESTAMPTZ;
  v_hub_mac VARCHAR(17);
BEGIN
  v_heartbeat_ts := COALESCE(NEW.created_at, NOW());
  v_firmware_version := NEW.firmware_version;

  -- Build telemetry JSONB: prefer new telemetry column, fall back to individual columns
  IF NEW.telemetry IS NOT NULL THEN
    v_telemetry := NEW.telemetry;
  ELSE
    -- Build from individual columns (backward compatibility with current firmware)
    v_telemetry := jsonb_strip_nulls(jsonb_build_object(
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'uptime_sec', NEW.uptime_sec,
      'free_heap', NEW.free_heap,
      'min_free_heap', NEW.min_free_heap,
      'largest_free_block', NEW.largest_free_block,
      'wifi_rssi', NEW.wifi_rssi,
      'thread_rssi', NEW.thread_rssi,
      'battery_level', NEW.battery_level,
      'battery_charging', NEW.battery_charging
    ));
  END IF;

  -- Extract consumer-facing telemetry values
  -- COALESCE prefers telemetry JSONB, falls back to individual columns
  v_battery_level := COALESCE(
    (v_telemetry->>'battery_level')::INTEGER,
    NEW.battery_level
  );
  v_is_charging := COALESCE(
    (v_telemetry->>'battery_charging')::BOOLEAN,
    NEW.battery_charging
  );
  v_wifi_rssi := COALESCE(
    (v_telemetry->>'wifi_rssi')::INTEGER,
    NEW.wifi_rssi
  );
  v_temperature_c := (v_telemetry->>'temperature_c')::NUMERIC;
  v_humidity_pct := (v_telemetry->>'humidity_pct')::NUMERIC;

  -- Also extract firmware_version from telemetry if not set as column
  IF v_firmware_version IS NULL THEN
    v_firmware_version := v_telemetry->>'firmware_version';
  END IF;

  -- =========================================================================
  -- Resolve hub_mac_address from relay info
  -- =========================================================================
  IF NEW.relay_device_type = 'hub' AND NEW.relay_instance_id IS NOT NULL THEN
    -- Relayed heartbeat: look up the hub's MAC via its serial number
    -- relay_instance_id contains the hub's unit_id (serial number)
    SELECT d2.mac_address INTO v_hub_mac
    FROM devices d2
    JOIN units u ON d2.unit_id = u.id
    WHERE u.serial_number = NEW.relay_instance_id
    LIMIT 1;
  ELSIF NEW.relay_device_type IS NULL THEN
    -- Direct heartbeat (no relay): clear hub association
    v_hub_mac := NULL;
  END IF;
  -- If relay_device_type is something other than 'hub' (e.g. phone relay),
  -- v_hub_mac stays NULL and hub_mac_address is preserved unchanged below.

  -- =========================================================================
  -- Update devices table (by mac_address)
  -- =========================================================================
  UPDATE devices
  SET
    last_seen_at = v_heartbeat_ts,
    firmware_version = COALESCE(v_firmware_version, firmware_version),
    latest_telemetry = v_telemetry,
    status = CASE WHEN status = 'offline' THEN 'online' ELSE status END,
    hub_mac_address = CASE
      WHEN NEW.relay_device_type = 'hub' AND NEW.relay_instance_id IS NOT NULL THEN v_hub_mac
      WHEN NEW.relay_device_type IS NULL THEN NULL
      ELSE hub_mac_address  -- preserve existing for non-hub relays
    END
  WHERE mac_address = NEW.mac_address;

  -- =========================================================================
  -- Update units table (by serial number stored in heartbeats.unit_id)
  -- Only update fields that are present in this heartbeat's telemetry.
  -- This supports multi-device units where different devices report
  -- different capability data (e.g., main controller has wifi, RFID reader
  -- does not). COALESCE preserves existing values when this heartbeat
  -- doesn't include a particular field.
  -- =========================================================================
  IF NEW.unit_id IS NOT NULL THEN
    UPDATE units
    SET
      last_seen_at = GREATEST(last_seen_at, v_heartbeat_ts),
      is_online = true,
      firmware_version = COALESCE(v_firmware_version, firmware_version),
      battery_level = COALESCE(v_battery_level, battery_level),
      is_charging = COALESCE(v_is_charging, is_charging),
      wifi_rssi = COALESCE(v_wifi_rssi, wifi_rssi),
      temperature_c = COALESCE(v_temperature_c, temperature_c),
      humidity_pct = COALESCE(v_humidity_pct, humidity_pct)
    WHERE serial_number = NEW.unit_id
    RETURNING id INTO v_unit_id;

    IF v_unit_id IS NULL THEN
      RAISE LOG 'Heartbeat: no unit found for serial_number=%, mac=%',
        NEW.unit_id, NEW.mac_address;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- 3. Modify broadcast_device_command() to route through hub
-- =============================================================================

CREATE OR REPLACE FUNCTION broadcast_device_command()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hub_mac VARCHAR(17);
  channel_name TEXT;
  payload JSONB;
BEGIN
  -- Check if target device connects through a hub
  SELECT hub_mac_address INTO v_hub_mac
  FROM devices
  WHERE mac_address = NEW.mac_address;

  -- Build base command payload
  payload := jsonb_build_object(
    'id', NEW.id,
    'command', NEW.command,
    'capability', NEW.capability,
    'test_name', NEW.test_name,
    'parameters', NEW.parameters
  );

  IF v_hub_mac IS NOT NULL THEN
    -- Route through hub: broadcast to hub's channel with target_mac
    channel_name := 'device:' || REPLACE(v_hub_mac, ':', '-');
    payload := payload || jsonb_build_object('target_mac', NEW.mac_address);
  ELSE
    -- Direct route: broadcast to device's own channel
    channel_name := 'device:' || REPLACE(NEW.mac_address, ':', '-');
  END IF;

  PERFORM realtime.send(payload, 'command', channel_name, false);

  RETURN NEW;
END;
$$;
