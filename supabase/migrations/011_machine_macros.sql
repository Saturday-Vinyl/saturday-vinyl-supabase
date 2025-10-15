-- Migration: Machine Macros
-- Description: Create table for storing machine-specific gcode macros
-- Author: Saturday! Development Team
-- Date: 2025-01-13

-- Create machine_macros table
CREATE TABLE IF NOT EXISTS public.machine_macros (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    machine_type TEXT NOT NULL,
    icon_name TEXT NOT NULL,
    gcode_commands TEXT NOT NULL,
    execution_order INTEGER NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Add constraint to validate machine_type
ALTER TABLE public.machine_macros
ADD CONSTRAINT valid_machine_type CHECK (machine_type IN ('cnc', 'laser'));

-- Add constraint for positive execution_order
ALTER TABLE public.machine_macros
ADD CONSTRAINT positive_execution_order CHECK (execution_order > 0);

-- Add constraint to ensure name is not empty
ALTER TABLE public.machine_macros
ADD CONSTRAINT non_empty_name CHECK (length(trim(name)) > 0);

-- Add constraint to ensure gcode_commands is not empty
ALTER TABLE public.machine_macros
ADD CONSTRAINT non_empty_gcode CHECK (length(trim(gcode_commands)) > 0);

-- Add constraint to ensure icon_name is not empty
ALTER TABLE public.machine_macros
ADD CONSTRAINT non_empty_icon CHECK (length(trim(icon_name)) > 0);

-- Create index on machine_type and is_active for efficient queries
CREATE INDEX idx_machine_macros_machine_type_active
ON public.machine_macros(machine_type, is_active);

-- Create index on execution_order for sorting
CREATE INDEX idx_machine_macros_execution_order
ON public.machine_macros(execution_order);

-- Enable Row Level Security
ALTER TABLE public.machine_macros ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Allow authenticated users to read all macros
CREATE POLICY machine_macros_select_policy ON public.machine_macros
    FOR SELECT
    TO authenticated
    USING (true);

-- RLS Policy: Allow authenticated users to insert macros
CREATE POLICY machine_macros_insert_policy ON public.machine_macros
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- RLS Policy: Allow authenticated users to update macros
CREATE POLICY machine_macros_update_policy ON public.machine_macros
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- RLS Policy: Allow authenticated users to delete macros
CREATE POLICY machine_macros_delete_policy ON public.machine_macros
    FOR DELETE
    TO authenticated
    USING (true);

-- Create function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_machine_macros_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to call the function
CREATE TRIGGER machine_macros_updated_at_trigger
    BEFORE UPDATE ON public.machine_macros
    FOR EACH ROW
    EXECUTE FUNCTION update_machine_macros_updated_at();

-- Insert sample macros for CNC
INSERT INTO public.machine_macros (name, description, machine_type, icon_name, gcode_commands, execution_order) VALUES
    ('Spindle On', 'Start spindle at 12000 RPM', 'cnc', 'power', 'M3 S12000', 1),
    ('Spindle Off', 'Stop spindle rotation', 'cnc', 'power_off', 'M5', 2),
    ('Coolant On', 'Enable coolant flow', 'cnc', 'opacity', 'M8', 3),
    ('Coolant Off', 'Disable coolant flow', 'cnc', 'clear', 'M9', 4);

-- Insert sample macros for Laser
INSERT INTO public.machine_macros (name, description, machine_type, icon_name, gcode_commands, execution_order) VALUES
    ('Laser Test Fire', 'Test fire laser at 10% power for 0.5 seconds', 'laser', 'flash_on', E'M3 S10\nG4 P0.5\nM5', 1),
    ('Air Assist On', 'Enable air assist for laser', 'laser', 'air', 'M7', 2),
    ('Air Assist Off', 'Disable air assist', 'laser', 'clear', 'M9', 3),
    ('Focus Test', 'Run focus test pattern', 'laser', 'visibility', E'G21\nG90\nM3 S20\nG0 X0 Y0\nG1 X10 Y0 F1000\nG1 X10 Y10\nG1 X0 Y10\nG1 X0 Y0\nM5', 4);

-- Add comment to table
COMMENT ON TABLE public.machine_macros IS 'Stores machine-specific gcode macros for quick execution';

-- Add comments to columns
COMMENT ON COLUMN public.machine_macros.name IS 'Display name for the macro';
COMMENT ON COLUMN public.machine_macros.description IS 'Tooltip text shown on hover';
COMMENT ON COLUMN public.machine_macros.machine_type IS 'Type of machine: cnc or laser';
COMMENT ON COLUMN public.machine_macros.icon_name IS 'Material Icon name (e.g., home, play_arrow)';
COMMENT ON COLUMN public.machine_macros.gcode_commands IS 'Multi-line gcode commands to execute (newline separated)';
COMMENT ON COLUMN public.machine_macros.execution_order IS 'Display order in the UI (lower numbers appear first)';
COMMENT ON COLUMN public.machine_macros.is_active IS 'Whether the macro is enabled and should be shown';
