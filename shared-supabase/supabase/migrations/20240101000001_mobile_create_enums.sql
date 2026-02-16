-- Migration: Create custom enum types for Saturday Consumer App
-- This migration is idempotent - safe to run multiple times
--
-- NOTE: This extends the existing Saturday database schema (admin app)
-- Existing tables: users, rfid_tags (will be extended)
-- New tables: libraries, albums, devices (consumer), etc.

-- Library member roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'library_role') THEN
        CREATE TYPE library_role AS ENUM ('owner', 'editor', 'viewer');
    END IF;
END$$;

-- Consumer device type (hub, crate - these are consumer-owned devices, not production units)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'consumer_device_type') THEN
        CREATE TYPE consumer_device_type AS ENUM ('hub', 'crate');
    END IF;
END$$;

-- Consumer device status
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'consumer_device_status') THEN
        CREATE TYPE consumer_device_status AS ENUM ('online', 'offline', 'setup_required');
    END IF;
END$$;

-- Record side (for listening history)
-- Supports multi-disc albums: A, B, C, D, E, F, G, H (up to 4 discs)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'record_side') THEN
        CREATE TYPE record_side AS ENUM ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H');
    END IF;
END$$;
