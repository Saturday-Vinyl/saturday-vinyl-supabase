-- RFID Tag Rolls Table
-- Stores roll metadata for batch RFID tag writing and printing workflows
-- Idempotent: Yes - safe to run multiple times

-- ============================================================================
-- RFID_TAG_ROLLS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.rfid_tag_rolls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    label_width_mm NUMERIC(6,2) NOT NULL,  -- Label width in millimeters
    label_height_mm NUMERIC(6,2) NOT NULL, -- Label height in millimeters
    label_count INTEGER NOT NULL,          -- Total labels on the physical roll
    status VARCHAR(20) NOT NULL DEFAULT 'writing',
    last_printed_position INTEGER NOT NULL DEFAULT 0, -- Tracks print progress
    manufacturer_url TEXT,                 -- Optional link to manufacturer listing
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID REFERENCES public.users(id),

    CONSTRAINT valid_roll_status CHECK (status IN ('writing', 'ready_to_print', 'printing', 'completed')),
    CONSTRAINT positive_dimensions CHECK (label_width_mm > 0 AND label_height_mm > 0),
    CONSTRAINT positive_label_count CHECK (label_count > 0),
    CONSTRAINT valid_printed_position CHECK (last_printed_position >= 0)
);

-- Status filtering
CREATE INDEX IF NOT EXISTS idx_rfid_tag_rolls_status ON public.rfid_tag_rolls(status);

-- Timestamp queries (newest first)
CREATE INDEX IF NOT EXISTS idx_rfid_tag_rolls_created ON public.rfid_tag_rolls(created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.rfid_tag_rolls ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- UPDATE RFID_TAGS TABLE WITH ROLL COLUMNS
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'rfid_tags'
        AND column_name = 'roll_id'
    ) THEN
        ALTER TABLE public.rfid_tags
            ADD COLUMN roll_id UUID REFERENCES public.rfid_tag_rolls(id) ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'rfid_tags'
        AND column_name = 'roll_position'
    ) THEN
        ALTER TABLE public.rfid_tags
            ADD COLUMN roll_position INTEGER;
    END IF;
END $$;

-- Index for efficient roll-based queries
CREATE INDEX IF NOT EXISTS idx_rfid_tags_roll ON public.rfid_tags(roll_id, roll_position);

-- Constraint: roll_position must be positive when set
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'valid_roll_position'
        AND conrelid = 'public.rfid_tags'::regclass
    ) THEN
        ALTER TABLE public.rfid_tags
            ADD CONSTRAINT valid_roll_position CHECK (roll_position IS NULL OR roll_position > 0);
    END IF;
END $$;

-- ============================================================================
-- RLS POLICIES FOR RFID_TAG_ROLLS
-- ============================================================================

-- Allow authenticated users to read all rolls
DROP POLICY IF EXISTS "Authenticated users can read rfid_tag_rolls" ON public.rfid_tag_rolls;
CREATE POLICY "Authenticated users can read rfid_tag_rolls"
    ON public.rfid_tag_rolls
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow authenticated users to insert rolls (permission check done in app)
DROP POLICY IF EXISTS "Authenticated users can insert rfid_tag_rolls" ON public.rfid_tag_rolls;
CREATE POLICY "Authenticated users can insert rfid_tag_rolls"
    ON public.rfid_tag_rolls
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Allow authenticated users to update rolls (permission check done in app)
DROP POLICY IF EXISTS "Authenticated users can update rfid_tag_rolls" ON public.rfid_tag_rolls;
CREATE POLICY "Authenticated users can update rfid_tag_rolls"
    ON public.rfid_tag_rolls
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Allow authenticated users to delete rolls (permission check done in app)
DROP POLICY IF EXISTS "Authenticated users can delete rfid_tag_rolls" ON public.rfid_tag_rolls;
CREATE POLICY "Authenticated users can delete rfid_tag_rolls"
    ON public.rfid_tag_rolls
    FOR DELETE
    TO authenticated
    USING (true);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger for updated_at timestamp
DROP TRIGGER IF EXISTS update_rfid_tag_rolls_updated_at ON public.rfid_tag_rolls;
CREATE TRIGGER update_rfid_tag_rolls_updated_at
    BEFORE UPDATE ON public.rfid_tag_rolls
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.rfid_tag_rolls TO authenticated;
