-- ============================================================================
-- Migration: 20260514003402_firmware_multihub_command_relay.sql
-- Project: sv-hub-firmware
-- Description: Account-wide fan-out for relay-required device commands.
--              Replaces single-Hub routing in broadcast_device_command()
--              with broadcast to every Hub on the target device's user
--              account. Each Hub independently decides whether to relay
--              based on its local Crate cache.
-- Date: 2026-05-13
-- Idempotent: Yes - CREATE OR REPLACE FUNCTION; safe to run multiple times.
-- ============================================================================
--
-- Background:
-- Firmware v0.6.0 introduced cloud-canonical, account-scoped Thread mesh
-- credentials. A user may now adopt multiple Hubs under one account that
-- share a single Thread network. A Crate is routed by the mesh to
-- whichever Border Router gives it the best path; it does not pair to a
-- specific Hub. The prior trigger picked a single Hub (the one whose MAC
-- happened to be stored in devices.hub_mac_address, set by the last
-- relayed heartbeat). With mesh dynamics that cache lags reality and
-- commands routed to the wrong Hub.
--
-- This migration rewrites the trigger so that for any device whose
-- hub_mac_address is non-NULL (i.e. a relay-required device like a
-- Crate), the command is broadcast to every Hub on the same user account.
-- The Hub whose local s_crate_cache contains the target relays via CoAP;
-- the others silently ignore (see firmware change to realtime_client.c).
--
-- devices.hub_mac_address is preserved as informational "last reachable
-- via" telemetry; the heartbeat sync trigger keeps updating it.
--
-- ---------------------------------------------------------------------------
-- Schema sanity note — what this migration leaves behind and why
-- ---------------------------------------------------------------------------
-- Kept, still load-bearing:
--   - devices.hub_mac_address              Now informational only ("last
--                                          Hub that relayed a heartbeat for
--                                          this device"), no longer the
--                                          routing key. Still populated by
--                                          sync_heartbeat_to_device_and_unit().
--                                          Used by this trigger as an
--                                          IS NOT NULL flag to detect
--                                          relay-required devices; useful
--                                          for admin UIs and debugging.
--   - sync_heartbeat_to_device_and_unit()  Unchanged. Continues to set/clear
--                                          hub_mac_address from relay info.
--   - thread_networks (v0.6.0)             Cloud-canonical Thread credentials,
--                                          unrelated to command routing.
--   - device_commands / device_heartbeats  Unchanged. command_ack/result flow
--                                          back from the Crate through
--                                          whichever Hub successfully relayed.
--
-- Becomes routing-irrelevant (kept for telemetry / admin queries):
--   - idx_devices_hub_mac (partial index on hub_mac_address)
--                                          Created with the original column
--                                          to speed up "which Hub owns this
--                                          device" lookups. The new trigger
--                                          no longer filters by
--                                          hub_mac_address, so the index no
--                                          longer accelerates the routing
--                                          path. It may still help admin
--                                          queries like "list every device
--                                          parented to Hub X." Left in place;
--                                          drop in a follow-up if no such
--                                          query exists in admin/mobile code.
--
-- Nothing is dropped by this migration. All cleanup, if any, is deferred to
-- a follow-up after confirming no app-side consumers rely on the indexes /
-- columns above.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION broadcast_device_command()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hub_mac VARCHAR(17);
  v_user_id UUID;
  v_payload JSONB;
  v_relay_payload JSONB;
  r RECORD;
  v_fanout_count INTEGER := 0;
BEGIN
  -- Base command payload sent to every channel.
  v_payload := jsonb_build_object(
    'id', NEW.id,
    'command', NEW.command,
    'capability', NEW.capability,
    'test_name', NEW.test_name,
    'parameters', NEW.parameters
  );

  -- Determine whether the target device requires Hub relay (Crate, etc.)
  -- and, if so, which user account owns it.
  SELECT d.hub_mac_address, u.consumer_user_id
    INTO v_hub_mac, v_user_id
  FROM devices d
  LEFT JOIN units u ON u.id = d.unit_id
  WHERE d.mac_address = NEW.mac_address;

  IF v_hub_mac IS NOT NULL AND v_user_id IS NOT NULL THEN
    -- Fan out to every Hub on the user's account. The Hub whose local
    -- mesh cache contains target_mac will relay; others ignore silently.
    v_relay_payload := v_payload || jsonb_build_object('target_mac', NEW.mac_address);

    FOR r IN
      SELECT d.mac_address
      FROM devices d
      JOIN units u ON u.id = d.unit_id
      WHERE u.consumer_user_id = v_user_id
        AND d.device_type_slug LIKE 'hub%'
        AND d.mac_address IS NOT NULL
    LOOP
      PERFORM realtime.send(
        v_relay_payload,
        'command',
        'device:' || REPLACE(r.mac_address, ':', '-'),
        false
      );
      v_fanout_count := v_fanout_count + 1;
    END LOOP;

    IF v_fanout_count = 0 THEN
      -- Owner has no Hub on the account (shouldn't normally happen for a
      -- relay-required device); fall back to direct route so the command
      -- isn't silently dropped.
      RAISE LOG 'broadcast_device_command: no Hubs found for user % (target %); falling back to direct route',
        v_user_id, NEW.mac_address;
      PERFORM realtime.send(
        v_payload,
        'command',
        'device:' || REPLACE(NEW.mac_address, ':', '-'),
        false
      );
    END IF;
  ELSE
    -- Direct route: Hubs themselves, devices with direct cloud access,
    -- or devices that aren't yet bound to a unit/account.
    PERFORM realtime.send(
      v_payload,
      'command',
      'device:' || REPLACE(NEW.mac_address, ':', '-'),
      false
    );
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION broadcast_device_command() IS
  'Trigger function: broadcasts a device_commands row to the appropriate '
  'Supabase Realtime channel(s). For devices that connect via a Hub '
  '(hub_mac_address IS NOT NULL), fans the command out to every Hub on '
  'the owning user account; each Hub decides locally whether it can '
  'relay to the target Crate via the Thread mesh. For devices with '
  'direct cloud connectivity, sends to the device''s own channel.';
