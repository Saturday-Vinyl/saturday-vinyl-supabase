-- RFID Tags Table
-- Stores UHF RFID tags for vinyl record tracking

-- ============================================================================
-- RFID_TAGS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.rfid_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    epc_identifier VARCHAR(24) NOT NULL UNIQUE, -- 96-bit EPC as 24 hex characters
    tid VARCHAR(48), -- Factory TID if captured (variable length, up to 96 bits)
    status VARCHAR(20) NOT NULL DEFAULT 'generated',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    written_at TIMESTAMPTZ, -- When EPC was written to physical tag
    locked_at TIMESTAMPTZ, -- When tag was locked
    created_by UUID REFERENCES public.users(id),

    CONSTRAINT valid_status CHECK (status IN ('generated', 'written', 'locked', 'failed', 'retired'))
);

-- Primary lookup index (most queries will be by EPC)
CREATE INDEX IF NOT EXISTS idx_rfid_tags_epc ON public.rfid_tags(epc_identifier);

-- Status filtering
CREATE INDEX IF NOT EXISTS idx_rfid_tags_status ON public.rfid_tags(status);

-- Timestamp queries (newest first)
CREATE INDEX IF NOT EXISTS idx_rfid_tags_created ON public.rfid_tags(created_at DESC);

-- Enable Row Level Security
ALTER TABLE public.rfid_tags ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- Allow authenticated users to read all tags
CREATE POLICY "Authenticated users can read rfid_tags"
    ON public.rfid_tags
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow authenticated users to insert tags (permission check done in app)
CREATE POLICY "Authenticated users can insert rfid_tags"
    ON public.rfid_tags
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Allow authenticated users to update tags (permission check done in app)
CREATE POLICY "Authenticated users can update rfid_tags"
    ON public.rfid_tags
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger for updated_at timestamp
DROP TRIGGER IF EXISTS update_rfid_tags_updated_at ON public.rfid_tags;
CREATE TRIGGER update_rfid_tags_updated_at
    BEFORE UPDATE ON public.rfid_tags
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- PERMISSIONS
-- ============================================================================

-- Add manage_tags permission
INSERT INTO public.permissions (name, description) VALUES
    ('manage_tags', 'Create, write, and manage RFID tags')
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE ON public.rfid_tags TO authenticated;
