-- ============================================================================
-- Migration: 013_file_library.sql
-- Description: Create unified file library system for production steps
-- Date: 2025-10-16
--
-- PURPOSE:
-- Replace GitHub-synced gcode system with a unified file library where users
-- can upload any file type for use in production steps. This simplifies file
-- management and makes the system more flexible.
--
-- ============================================================================

-- ============================================================================
-- Files Table
-- ============================================================================

-- Create table for uploaded files
CREATE TABLE public.files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL UNIQUE,
  description TEXT,
  mime_type TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL,
  uploaded_by_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT file_size_limit CHECK (file_size_bytes > 0 AND file_size_bytes <= 52428800) -- 50MB limit
);

-- Add comments
COMMENT ON TABLE public.files IS
  'Unified file library for production steps - supports any file type';

COMMENT ON COLUMN public.files.storage_path IS
  'Path in Supabase Storage (e.g., files/abc-123.gcode)';

COMMENT ON COLUMN public.files.file_name IS
  'User-visible file name (must be unique)';

COMMENT ON COLUMN public.files.description IS
  'User-editable description of the file';

COMMENT ON COLUMN public.files.mime_type IS
  'MIME type of the file (e.g., text/plain, application/octet-stream)';

COMMENT ON COLUMN public.files.file_size_bytes IS
  'File size in bytes (max 50MB = 52428800 bytes)';

COMMENT ON COLUMN public.files.uploaded_by_name IS
  'Name of user who uploaded (stored as string, not FK - preserves name even if user deleted)';

-- Create indexes
CREATE INDEX idx_files_name ON public.files(file_name);
CREATE INDEX idx_files_mime_type ON public.files(mime_type);
CREATE INDEX idx_files_created_at ON public.files(created_at DESC);

-- Add trigger for updated_at timestamp
CREATE TRIGGER update_files_updated_at
  BEFORE UPDATE ON public.files
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Step Files Junction Table
-- ============================================================================

-- Create junction table for production step file attachments
CREATE TABLE public.step_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  file_id UUID NOT NULL REFERENCES public.files(id) ON DELETE CASCADE,
  execution_order INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_step_file UNIQUE(step_id, file_id),
  CONSTRAINT unique_step_execution_order UNIQUE(step_id, execution_order),
  CONSTRAINT positive_execution_order CHECK (execution_order > 0)
);

-- Add comments
COMMENT ON TABLE public.step_files IS
  'Links production steps to files with execution order for sequencing';

COMMENT ON COLUMN public.step_files.step_id IS
  'Foreign key to production step';

COMMENT ON COLUMN public.step_files.file_id IS
  'Foreign key to file in library';

COMMENT ON COLUMN public.step_files.execution_order IS
  'Order in which files should be used (1, 2, 3, etc.) - important for gcode sequencing';

-- Create indexes
CREATE INDEX idx_step_files_step_id ON public.step_files(step_id);
CREATE INDEX idx_step_files_file_id ON public.step_files(file_id);
CREATE INDEX idx_step_files_execution_order ON public.step_files(step_id, execution_order);

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS on new tables
ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.step_files ENABLE ROW LEVEL SECURITY;

-- Policies for files (all authenticated users can manage files)
CREATE POLICY "Authenticated users can read files"
  ON public.files
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert files"
  ON public.files
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update files"
  ON public.files
  FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can delete files"
  ON public.files
  FOR DELETE
  TO authenticated
  USING (true);

-- Policies for step_files (all authenticated users can manage)
CREATE POLICY "Authenticated users can read step files"
  ON public.step_files
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert step files"
  ON public.step_files
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update step files"
  ON public.step_files
  FOR UPDATE
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can delete step files"
  ON public.step_files
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Deprecate Old File System (DO NOT DROP - for backward compatibility)
-- ============================================================================

-- Add comments to mark old columns as deprecated
COMMENT ON COLUMN public.production_steps.file_url IS
  'DEPRECATED: Use step_files table instead. Single file attachment (replaced by multi-file system)';

COMMENT ON COLUMN public.production_steps.file_name IS
  'DEPRECATED: Use step_files table instead.';

COMMENT ON COLUMN public.production_steps.file_type IS
  'DEPRECATED: Use step_files table instead.';

COMMENT ON TABLE public.gcode_files IS
  'DEPRECATED: GitHub sync system replaced by unified file library. Use files table instead.';

COMMENT ON TABLE public.step_gcode_files IS
  'DEPRECATED: Use step_files table instead. Old gcode-specific junction table.';

-- ============================================================================
-- Example Queries for Testing
-- ============================================================================

-- Upload a file:
-- INSERT INTO public.files (storage_path, file_name, description, mime_type, file_size_bytes, uploaded_by_name)
-- VALUES
--   ('files/abc-123.gcode', 'Turntable Base Mill.gcode', 'CNC milling for turntable base', 'application/octet-stream', 15234, 'John Doe');

-- Attach file to production step:
-- INSERT INTO public.step_files (step_id, file_id, execution_order)
-- VALUES ('<step_id>', '<file_id>', 1);

-- Get all files for a production step (ordered):
-- SELECT
--   f.id,
--   f.file_name,
--   f.description,
--   f.mime_type,
--   f.file_size_bytes,
--   sf.execution_order
-- FROM public.step_files sf
-- INNER JOIN public.files f ON f.id = sf.file_id
-- WHERE sf.step_id = '<step_id>'
-- ORDER BY sf.execution_order;

-- Get all gcode files for a step (filter by extension):
-- SELECT
--   f.*,
--   sf.execution_order
-- FROM public.step_files sf
-- INNER JOIN public.files f ON f.id = sf.file_id
-- WHERE sf.step_id = '<step_id>'
--   AND (f.file_name LIKE '%.gcode' OR f.file_name LIKE '%.nc')
-- ORDER BY sf.execution_order;
