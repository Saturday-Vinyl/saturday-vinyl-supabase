-- Migration: Fix consumer_provisioned_by foreign key
-- The FK should reference public.users(id), not auth.users(id)

-- 1. Drop the incorrect foreign key constraint
ALTER TABLE devices DROP CONSTRAINT IF EXISTS devices_consumer_provisioned_by_fkey;

-- 2. Add the correct foreign key constraint referencing public.users
ALTER TABLE devices
  ADD CONSTRAINT devices_consumer_provisioned_by_fkey
  FOREIGN KEY (consumer_provisioned_by) REFERENCES users(id);

-- 3. Fix RLS policies on units table
-- consumer_user_id stores users.id, not auth.users.id
-- We need to look up the user by their auth_user_id
DROP POLICY IF EXISTS "Users can view their own units" ON units;
DROP POLICY IF EXISTS "Users can update their own units" ON units;

-- Create policies that join through the users table
CREATE POLICY "Users can view their own units" ON units
  FOR SELECT USING (
    consumer_user_id IN (
      SELECT id FROM users WHERE auth_user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their own units" ON units
  FOR UPDATE USING (
    consumer_user_id IN (
      SELECT id FROM users WHERE auth_user_id = auth.uid()
    )
  );
