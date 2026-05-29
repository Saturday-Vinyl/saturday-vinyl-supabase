-- Add board-assembled flag to sub_assembly_lines
-- Components assembled by the board maker (e.g., SMD pick-and-place)
-- don't need to be tracked in our inventory.
ALTER TABLE sub_assembly_lines
  ADD COLUMN IF NOT EXISTS is_board_assembled BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN sub_assembly_lines.is_board_assembled IS
  'True if this component is assembled by the PCB board maker and does not need to be in our inventory';
