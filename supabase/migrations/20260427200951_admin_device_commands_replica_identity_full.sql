-- ============================================================================
-- Migration: 20260427200951_admin_device_commands_replica_identity_full.sql
-- Project: saturday-admin-app
-- Description: Set REPLICA IDENTITY FULL on device_commands so Postgres Changes
--              UPDATE events include all columns in the OLD record. Without this,
--              filtered subscriptions (e.g. by mac_address) never receive UPDATE
--              events because the OLD row only contains the primary key.
-- Date: 2026-04-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

ALTER TABLE device_commands REPLICA IDENTITY FULL;
