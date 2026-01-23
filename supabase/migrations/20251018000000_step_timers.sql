-- ============================================================================
-- Migration: 014_step_timers.sql
-- Description: Add timer support for production steps
-- Date: 2025-10-17
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- Step Timers Table (Configuration)
-- ============================================================================

-- Create step_timers table for configurable timers per production step (if not exists)
CREATE TABLE IF NOT EXISTS public.step_timers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  timer_name TEXT NOT NULL,
  duration_minutes INTEGER NOT NULL,
  timer_order INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT positive_duration CHECK (duration_minutes > 0),
  CONSTRAINT positive_timer_order CHECK (timer_order > 0)
);

-- Add comments to explain the columns
COMMENT ON TABLE public.step_timers IS
  'Configurable timers for production steps. Each step can have multiple timers (e.g., "Cure Time - 15 min", "Cool Down - 30 min").';

COMMENT ON COLUMN public.step_timers.step_id IS
  'Foreign key to the production step';

COMMENT ON COLUMN public.step_timers.timer_name IS
  'Descriptive name for the timer (e.g., "Cure Time", "Cool Down Period")';

COMMENT ON COLUMN public.step_timers.duration_minutes IS
  'Timer duration in minutes';

COMMENT ON COLUMN public.step_timers.timer_order IS
  'Display order of the timer';

-- Create indexes for efficient queries (if not exists)
CREATE INDEX IF NOT EXISTS idx_step_timers_step_id ON public.step_timers(step_id);
CREATE INDEX IF NOT EXISTS idx_step_timers_order ON public.step_timers(step_id, timer_order);

-- Add trigger for updated_at timestamp (drop and recreate for idempotency)
DROP TRIGGER IF EXISTS update_step_timers_updated_at ON public.step_timers;
CREATE TRIGGER update_step_timers_updated_at
  BEFORE UPDATE ON public.step_timers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Unit Timers Table (Active Timer Instances)
-- ============================================================================

-- Create unit_timers table to track active timers for production units
CREATE TABLE IF NOT EXISTS public.unit_timers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id UUID NOT NULL REFERENCES public.production_units(id) ON DELETE CASCADE,
  step_timer_id UUID NOT NULL REFERENCES public.step_timers(id) ON DELETE CASCADE,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT valid_status CHECK (status IN ('active', 'completed', 'cancelled'))
);

-- Add comments to explain the columns
COMMENT ON TABLE public.unit_timers IS
  'Active timer instances for production units. Tracks when timers are started and their current status.';

COMMENT ON COLUMN public.unit_timers.unit_id IS
  'Foreign key to the production unit';

COMMENT ON COLUMN public.unit_timers.step_timer_id IS
  'Foreign key to the step timer configuration';

COMMENT ON COLUMN public.unit_timers.started_at IS
  'When the timer was started';

COMMENT ON COLUMN public.unit_timers.expires_at IS
  'When the timer should expire (started_at + duration)';

COMMENT ON COLUMN public.unit_timers.completed_at IS
  'When the timer was marked as completed (null if still active)';

COMMENT ON COLUMN public.unit_timers.status IS
  'Current status: active (running), completed (acknowledged), cancelled (dismissed)';

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_unit_timers_unit_id ON public.unit_timers(unit_id);
CREATE INDEX IF NOT EXISTS idx_unit_timers_step_timer_id ON public.unit_timers(step_timer_id);
CREATE INDEX IF NOT EXISTS idx_unit_timers_status ON public.unit_timers(status);
CREATE INDEX IF NOT EXISTS idx_unit_timers_expires_at ON public.unit_timers(expires_at) WHERE status = 'active';

-- Add trigger for updated_at timestamp
DROP TRIGGER IF EXISTS update_unit_timers_updated_at ON public.unit_timers;
CREATE TRIGGER update_unit_timers_updated_at
  BEFORE UPDATE ON public.unit_timers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Row Level Security (RLS) Policies - Step Timers
-- ============================================================================

-- Enable RLS
ALTER TABLE public.step_timers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Allow authenticated users to read step timers" ON public.step_timers;
DROP POLICY IF EXISTS "Authenticated users can insert step timers" ON public.step_timers;
DROP POLICY IF EXISTS "Authenticated users can update step timers" ON public.step_timers;
DROP POLICY IF EXISTS "Authenticated users can delete step timers" ON public.step_timers;

-- Policy: Allow authenticated users to read step timers
CREATE POLICY "Allow authenticated users to read step timers"
  ON public.step_timers
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to insert step timers
CREATE POLICY "Authenticated users can insert step timers"
  ON public.step_timers
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Allow authenticated users to update step timers
CREATE POLICY "Authenticated users can update step timers"
  ON public.step_timers
  FOR UPDATE
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to delete step timers
CREATE POLICY "Authenticated users can delete step timers"
  ON public.step_timers
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Row Level Security (RLS) Policies - Unit Timers
-- ============================================================================

-- Enable RLS
ALTER TABLE public.unit_timers ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for idempotency)
DROP POLICY IF EXISTS "Allow authenticated users to read unit timers" ON public.unit_timers;
DROP POLICY IF EXISTS "Authenticated users can insert unit timers" ON public.unit_timers;
DROP POLICY IF EXISTS "Authenticated users can update unit timers" ON public.unit_timers;
DROP POLICY IF EXISTS "Authenticated users can delete unit timers" ON public.unit_timers;

-- Policy: Allow authenticated users to read unit timers
CREATE POLICY "Allow authenticated users to read unit timers"
  ON public.unit_timers
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to insert unit timers
CREATE POLICY "Authenticated users can insert unit timers"
  ON public.unit_timers
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Allow authenticated users to update unit timers
CREATE POLICY "Authenticated users can update unit timers"
  ON public.unit_timers
  FOR UPDATE
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to delete unit timers
CREATE POLICY "Authenticated users can delete unit timers"
  ON public.unit_timers
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Example queries for testing
-- ============================================================================

-- Add timers to a production step:
-- INSERT INTO public.step_timers (step_id, timer_name, duration_minutes, timer_order) VALUES
--   ('<step_id>', 'Cure Time', 15, 1),
--   ('<step_id>', 'Cool Down', 30, 2);

-- Get all timers for a production step (in order):
-- SELECT id, timer_name, duration_minutes, timer_order
-- FROM public.step_timers
-- WHERE step_id = '<step_id>'
-- ORDER BY timer_order;

-- Start a timer for a production unit:
-- INSERT INTO public.unit_timers (unit_id, step_timer_id, started_at, expires_at, status)
-- VALUES (
--   '<unit_id>',
--   '<step_timer_id>',
--   now(),
--   now() + interval '15 minutes',
--   'active'
-- );

-- Get all active timers for a production unit:
-- SELECT ut.*, st.timer_name, st.duration_minutes
-- FROM public.unit_timers ut
-- JOIN public.step_timers st ON st.id = ut.step_timer_id
-- WHERE ut.unit_id = '<unit_id>' AND ut.status = 'active'
-- ORDER BY ut.expires_at;

-- Get all expired timers:
-- SELECT ut.*, st.timer_name
-- FROM public.unit_timers ut
-- JOIN public.step_timers st ON st.id = ut.step_timer_id
-- WHERE ut.status = 'active' AND ut.expires_at < now();

-- Mark a timer as completed:
-- UPDATE public.unit_timers
-- SET status = 'completed', completed_at = now()
-- WHERE id = '<unit_timer_id>';
