-- ============================================================================
-- Migration: 20260228165909_mobile_consumer_device_commands.sql
-- Project: mobile
-- Description: Allow consumer app users to create device commands for their
--              own devices. Scoped so consumers can only target devices linked
--              to units they own (via consumer_user_id).
-- Date: 2026-02-28
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DROP POLICY IF EXISTS "Consumers can create commands for own devices" ON device_commands;

CREATE POLICY "Consumers can create commands for own devices"
ON device_commands FOR INSERT
TO authenticated
WITH CHECK (
  mac_address IN (
    SELECT d.mac_address FROM devices d
    JOIN units u ON d.unit_id = u.id
    WHERE u.consumer_user_id = auth.uid()
  )
);
