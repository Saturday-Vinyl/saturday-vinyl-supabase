-- Add flash_offset to firmware_files for multi-SoC esptool flashing
-- The flash_offset specifies where to write this binary in the master SoC's flash
-- For master SoC: offset 0 (default)
-- For secondary SoCs: offset of the staging partition (e.g., 0x400000 for h2_fw)

ALTER TABLE firmware_files ADD COLUMN IF NOT EXISTS flash_offset INTEGER NOT NULL DEFAULT 0;

COMMENT ON COLUMN firmware_files.flash_offset IS 'Flash memory offset for esptool write_flash (e.g., 0 for master, 4194304 for h2_fw partition at 0x400000)';
