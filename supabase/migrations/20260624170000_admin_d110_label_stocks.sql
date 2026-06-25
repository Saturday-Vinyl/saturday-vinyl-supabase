-- ============================================================================
-- Migration: 20260624170000_admin_d110_label_stocks.sql
-- Project: saturday-admin-app
-- Description: Seed the compact direct-thermal label stocks for the NIIMBOT D110
--   (a second BLE printer for small drawer/shelf labels). Dimensions are stored
--   in *reading* (landscape) orientation, matching how the template lays the
--   label out and how tt_50x30 is stored; the print path rotates 90° for the
--   D110's "left" print head. The D110 head prints ~12 mm across, so the
--   printable height is capped at 12 mm even on 14 mm media (the extra ~1 mm
--   per edge is unprintable liner margin).
-- Date: 2026-06-24
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

INSERT INTO label_stocks
  (code, name, width_mm, height_mm, printable_width_mm, printable_height_mm,
   printable_offset_x_mm, printable_offset_y_mm, material, sensing)
VALUES
  -- 14 × 40 mm media, printed landscape; 12 mm printable across the head.
  ('dt_40x14', '14 × 40 mm · D110', 40, 14, 40, 12, 0, 1, 'direct_thermal', 'gap'),
  -- 14 × 30 mm media.
  ('dt_30x14', '14 × 30 mm · D110', 30, 14, 30, 12, 0, 1, 'direct_thermal', 'gap'),
  -- 12 × 40 mm media — full 12 mm prints, no liner margin.
  ('dt_40x12', '12 × 40 mm · D110', 40, 12, 40, 12, 0, 0, 'direct_thermal', 'gap')
ON CONFLICT (code) DO NOTHING;
