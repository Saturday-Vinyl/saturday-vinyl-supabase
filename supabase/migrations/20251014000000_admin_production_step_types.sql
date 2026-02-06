-- ============================================================================
-- Migration: 010_production_step_types.sql
-- Description: Add step types and machine integration support
-- Date: 2025-10-12
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- Step Type Enum
-- ============================================================================

-- Create step_type enum for discriminating step functionality
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'step_type') THEN
    CREATE TYPE public.step_type AS ENUM ('general', 'cnc_milling', 'laser_cutting');
  END IF;
END $$;

COMMENT ON TYPE public.step_type IS
  'Type of production step: general (manual work), cnc_milling (CNC machine), or laser_cutting (laser machine)';

-- ============================================================================
-- Modify Production Steps Table
-- ============================================================================

-- Add step_type column (default to 'general' for existing steps)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'step_type') THEN
    ALTER TABLE public.production_steps ADD COLUMN step_type public.step_type NOT NULL DEFAULT 'general';
  END IF;
END $$;

-- Add QR engraving parameters for laser cutting steps
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'engrave_qr') THEN
    ALTER TABLE public.production_steps ADD COLUMN engrave_qr BOOLEAN NOT NULL DEFAULT false;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'qr_x_offset') THEN
    ALTER TABLE public.production_steps ADD COLUMN qr_x_offset NUMERIC(10, 3);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'qr_y_offset') THEN
    ALTER TABLE public.production_steps ADD COLUMN qr_y_offset NUMERIC(10, 3);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'qr_size') THEN
    ALTER TABLE public.production_steps ADD COLUMN qr_size NUMERIC(10, 3);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'qr_power_percent') THEN
    ALTER TABLE public.production_steps ADD COLUMN qr_power_percent INTEGER;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'production_steps' AND column_name = 'qr_speed_mm_min') THEN
    ALTER TABLE public.production_steps ADD COLUMN qr_speed_mm_min INTEGER;
  END IF;
END $$;

-- Add constraints for QR parameters
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'qr_power_range') THEN
    ALTER TABLE public.production_steps ADD CONSTRAINT qr_power_range CHECK (qr_power_percent IS NULL OR (qr_power_percent >= 0 AND qr_power_percent <= 100));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'qr_speed_positive') THEN
    ALTER TABLE public.production_steps ADD CONSTRAINT qr_speed_positive CHECK (qr_speed_mm_min IS NULL OR qr_speed_mm_min > 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'qr_size_positive') THEN
    ALTER TABLE public.production_steps ADD CONSTRAINT qr_size_positive CHECK (qr_size IS NULL OR qr_size > 0);
  END IF;
END $$;

-- Add comments
COMMENT ON COLUMN public.production_steps.step_type IS
  'Type of step: general, cnc_milling, or laser_cutting';

COMMENT ON COLUMN public.production_steps.engrave_qr IS
  'Whether to engrave the unit QR code (laser cutting steps only)';

COMMENT ON COLUMN public.production_steps.qr_x_offset IS
  'X-axis offset for QR code engraving (mm from origin)';

COMMENT ON COLUMN public.production_steps.qr_y_offset IS
  'Y-axis offset for QR code engraving (mm from origin)';

COMMENT ON COLUMN public.production_steps.qr_size IS
  'Size of QR code to engrave (mm)';

COMMENT ON COLUMN public.production_steps.qr_power_percent IS
  'Laser power percentage for QR engraving (0-100)';

COMMENT ON COLUMN public.production_steps.qr_speed_mm_min IS
  'Laser speed for QR engraving (mm/min)';

-- Create index for step_type queries
CREATE INDEX IF NOT EXISTS idx_production_steps_step_type ON public.production_steps(step_type);

-- ============================================================================
-- gCode Files Table
-- ============================================================================

-- Create table for gCode files from GitHub repository
CREATE TABLE IF NOT EXISTS public.gcode_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  github_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL,
  description TEXT,
  machine_type TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add comments
COMMENT ON TABLE public.gcode_files IS
  'gCode files from GitHub repository for CNC and laser machine operations';

COMMENT ON COLUMN public.gcode_files.github_path IS
  'Full path in GitHub repository (e.g., cnc/drill-holes.gcode)';

COMMENT ON COLUMN public.gcode_files.file_name IS
  'Display name of the file';

COMMENT ON COLUMN public.gcode_files.description IS
  'H1 heading from the gCode file README';

COMMENT ON COLUMN public.gcode_files.machine_type IS
  'Type of machine: cnc or laser';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_gcode_files_machine_type ON public.gcode_files(machine_type);
CREATE INDEX IF NOT EXISTS idx_gcode_files_github_path ON public.gcode_files(github_path);

-- Add trigger for updated_at timestamp
DROP TRIGGER IF EXISTS update_gcode_files_updated_at ON public.gcode_files;
CREATE TRIGGER update_gcode_files_updated_at
  BEFORE UPDATE ON public.gcode_files
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Step gCode Files Junction Table
-- ============================================================================

-- Create junction table for many-to-many relationship
CREATE TABLE IF NOT EXISTS public.step_gcode_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  gcode_file_id UUID NOT NULL REFERENCES public.gcode_files(id) ON DELETE CASCADE,
  execution_order INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT positive_execution_order CHECK (execution_order > 0),
  CONSTRAINT unique_step_gcode UNIQUE (step_id, gcode_file_id),
  CONSTRAINT unique_step_order UNIQUE (step_id, execution_order)
);

-- Add comments
COMMENT ON TABLE public.step_gcode_files IS
  'Junction table linking production steps to gCode files with execution order';

COMMENT ON COLUMN public.step_gcode_files.step_id IS
  'Foreign key to production step';

COMMENT ON COLUMN public.step_gcode_files.gcode_file_id IS
  'Foreign key to gCode file';

COMMENT ON COLUMN public.step_gcode_files.execution_order IS
  'Order in which to execute gCode files (1, 2, 3, etc.)';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_step_gcode_step_id ON public.step_gcode_files(step_id);
CREATE INDEX IF NOT EXISTS idx_step_gcode_file_id ON public.step_gcode_files(gcode_file_id);
CREATE INDEX IF NOT EXISTS idx_step_gcode_execution_order ON public.step_gcode_files(step_id, execution_order);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS on new tables
ALTER TABLE public.gcode_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.step_gcode_files ENABLE ROW LEVEL SECURITY;

-- Policies for gcode_files
DROP POLICY IF EXISTS "Allow authenticated users to read gcode files" ON public.gcode_files;
CREATE POLICY "Allow authenticated users to read gcode files"
  ON public.gcode_files
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert gcode files" ON public.gcode_files;
CREATE POLICY "Authenticated users can insert gcode files"
  ON public.gcode_files
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update gcode files" ON public.gcode_files;
CREATE POLICY "Authenticated users can update gcode files"
  ON public.gcode_files
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete gcode files" ON public.gcode_files;
CREATE POLICY "Authenticated users can delete gcode files"
  ON public.gcode_files
  FOR DELETE
  TO authenticated
  USING (true);

-- Policies for step_gcode_files
DROP POLICY IF EXISTS "Allow authenticated users to read step gcode files" ON public.step_gcode_files;
CREATE POLICY "Allow authenticated users to read step gcode files"
  ON public.step_gcode_files
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert step gcode files" ON public.step_gcode_files;
CREATE POLICY "Authenticated users can insert step gcode files"
  ON public.step_gcode_files
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update step gcode files" ON public.step_gcode_files;
CREATE POLICY "Authenticated users can update step gcode files"
  ON public.step_gcode_files
  FOR UPDATE
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can delete step gcode files" ON public.step_gcode_files;
CREATE POLICY "Authenticated users can delete step gcode files"
  ON public.step_gcode_files
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Example Queries for Testing
-- ============================================================================

-- Create a CNC milling step with gCode files:
-- INSERT INTO public.production_steps (product_id, name, description, step_order, step_type)
-- VALUES ('<product_id>', 'CNC Drill Holes', 'Drill mounting holes', 1, 'cnc_milling');

-- Create a laser cutting step with QR engraving:
-- INSERT INTO public.production_steps (
--   product_id, name, description, step_order, step_type,
--   engrave_qr, qr_x_offset, qr_y_offset, qr_size, qr_power_percent, qr_speed_mm_min
-- ) VALUES (
--   '<product_id>', 'Laser Cut Panel', 'Cut acrylic panel', 2, 'laser_cutting',
--   true, 10.0, 10.0, 20.0, 50, 1000
-- );

-- Add gCode files from repository:
-- INSERT INTO public.gcode_files (github_path, file_name, description, machine_type)
-- VALUES
--   ('cnc/drill-holes.gcode', 'Drill Holes', 'Drill 4x mounting holes', 'cnc'),
--   ('laser/cut-panel.gcode', 'Cut Panel', 'Cut outer perimeter', 'laser');

-- Link gCode files to a step:
-- INSERT INTO public.step_gcode_files (step_id, gcode_file_id, execution_order)
-- VALUES
--   ('<step_id>', '<gcode_file_1_id>', 1),
--   ('<step_id>', '<gcode_file_2_id>', 2);

-- Query step with all gCode files:
-- SELECT
--   ps.id,
--   ps.name,
--   ps.step_type,
--   json_agg(
--     json_build_object(
--       'file_name', gf.file_name,
--       'description', gf.description,
--       'github_path', gf.github_path,
--       'execution_order', sgf.execution_order
--     ) ORDER BY sgf.execution_order
--   ) as gcode_files
-- FROM public.production_steps ps
-- LEFT JOIN public.step_gcode_files sgf ON sgf.step_id = ps.id
-- LEFT JOIN public.gcode_files gf ON gf.id = sgf.gcode_file_id
-- WHERE ps.product_id = '<product_id>'
-- GROUP BY ps.id, ps.name, ps.step_type
-- ORDER BY ps.step_order;
