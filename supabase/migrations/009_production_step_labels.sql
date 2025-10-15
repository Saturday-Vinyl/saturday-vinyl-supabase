-- ============================================================================
-- Migration: 009_production_step_labels.sql
-- Description: Add multiple label support for production steps
-- Date: 2025-10-11
-- ============================================================================

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Allow authenticated users to read step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Authenticated users can insert step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Authenticated users can update step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Authenticated users can delete step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Allow manage_products to insert step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Allow manage_products to update step labels" ON public.step_labels;
DROP POLICY IF EXISTS "Allow manage_products to delete step labels" ON public.step_labels;

-- Create step_labels table for multiple labels per production step (if not exists)
CREATE TABLE IF NOT EXISTS public.step_labels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  label_text TEXT NOT NULL,
  label_order INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT positive_label_order CHECK (label_order > 0)
);

-- Add comments to explain the columns
COMMENT ON TABLE public.step_labels IS
  'Labels to print when completing a production step. Each step can have multiple labels (e.g., Left Side, Right Side).';

COMMENT ON COLUMN public.step_labels.step_id IS
  'Foreign key to the production step';

COMMENT ON COLUMN public.step_labels.label_text IS
  'Custom text to include on the label (e.g., "LEFT SIDE", "RIGHT SIDE", "FRAGILE")';

COMMENT ON COLUMN public.step_labels.label_order IS
  'Display order of the label (determines print order)';

-- Create indexes for efficient queries (if not exists)
CREATE INDEX IF NOT EXISTS idx_step_labels_step_id ON public.step_labels(step_id);
CREATE INDEX IF NOT EXISTS idx_step_labels_order ON public.step_labels(step_id, label_order);

-- Add trigger for updated_at timestamp (drop and recreate for idempotency)
DROP TRIGGER IF EXISTS update_step_labels_updated_at ON public.step_labels;
CREATE TRIGGER update_step_labels_updated_at
  BEFORE UPDATE ON public.step_labels
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS
ALTER TABLE public.step_labels ENABLE ROW LEVEL SECURITY;

-- Policy: Allow authenticated users to read step labels
CREATE POLICY "Allow authenticated users to read step labels"
  ON public.step_labels
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to insert step labels
CREATE POLICY "Authenticated users can insert step labels"
  ON public.step_labels
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Allow authenticated users to update step labels
CREATE POLICY "Authenticated users can update step labels"
  ON public.step_labels
  FOR UPDATE
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to delete step labels
CREATE POLICY "Authenticated users can delete step labels"
  ON public.step_labels
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Example queries for testing
-- ============================================================================

-- Add multiple labels to a CNC machining step:
-- INSERT INTO public.step_labels (step_id, label_text, label_order) VALUES
--   ('<step_id>', 'LEFT SIDE', 1),
--   ('<step_id>', 'RIGHT SIDE', 2);

-- Get all labels for a production step (in order):
-- SELECT id, label_text, label_order
-- FROM public.step_labels
-- WHERE step_id = '<step_id>'
-- ORDER BY label_order;

-- Count how many labels a step will generate:
-- SELECT ps.id, ps.name, COUNT(sl.id) as label_count
-- FROM public.production_steps ps
-- LEFT JOIN public.step_labels sl ON sl.step_id = ps.id
-- WHERE ps.product_id = '<product_id>'
-- GROUP BY ps.id, ps.name
-- ORDER BY ps.step_order;

-- Delete all labels for a step (will happen automatically on step delete due to CASCADE):
-- DELETE FROM public.step_labels WHERE step_id = '<step_id>';
