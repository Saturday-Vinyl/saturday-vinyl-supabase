-- ============================================================================
-- Migration: 20260622150000_admin_led_pixel_command.sql
-- Project: saturday-admin-app
-- Description: Add a `pixel` command to the existing `led` capability so an
--              individual addressable LED can be set to an RGB color. The drawer
--              "locate" feature lights a drawer's mapped pixel(s) via this command
--              instead of a bespoke led-locator capability.
-- Date: 2026-06-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- The `led` capability already exists (seeded in 20260125000000) with a `pattern`
-- command. Its command list lives in the `commands` JSONB column (renamed from
-- `tests` in 20260227203621). Add (or refresh) the `pixel` command without
-- clobbering `pattern` or any other commands: strip any existing `pixel` entry,
-- then append the canonical definition.
UPDATE capabilities
SET commands = (
  SELECT COALESCE(jsonb_agg(cmd), '[]'::jsonb)
  FROM jsonb_array_elements(COALESCE(commands, '[]'::jsonb)) AS cmd
  WHERE cmd->>'name' <> 'pixel'
) || jsonb_build_array(
  jsonb_build_object(
    'name', 'pixel',
    'display_name', 'Set Pixel Color',
    'description', 'Set a single addressable LED pixel to an RGB color. Set r/g/b all to 0 to turn the pixel off.',
    'parameters_schema', jsonb_build_object(
      'type', 'object',
      'properties', jsonb_build_object(
        'index', jsonb_build_object(
          'type', 'integer', 'minimum', 0,
          'description', 'Zero-based pixel index on the strip'),
        'r', jsonb_build_object(
          'type', 'integer', 'minimum', 0, 'maximum', 255,
          'description', 'Red (0-255)'),
        'g', jsonb_build_object(
          'type', 'integer', 'minimum', 0, 'maximum', 255,
          'description', 'Green (0-255)'),
        'b', jsonb_build_object(
          'type', 'integer', 'minimum', 0, 'maximum', 255,
          'description', 'Blue (0-255)')
      ),
      'required', jsonb_build_array('index', 'r', 'g', 'b')
    ),
    'result_schema', jsonb_build_object('type', 'object', 'properties', jsonb_build_object())
  )
)
WHERE name = 'led';
