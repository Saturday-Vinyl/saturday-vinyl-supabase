# Supabase Storage Setup Guide

This guide explains how to set up storage buckets in Supabase for the Saturday! admin app.

## Required Storage Buckets

The app uses three storage buckets:

1. **production-files** - For production step instruction files (PDFs, images, videos) - **PRIVATE**
2. **qr-codes** - For generated QR code images - **PRIVATE**
3. **firmware-binaries** - For device firmware files - **PUBLIC**

**Important Security Note:**
- `production-files` contains company IP and should be **PRIVATE** (authenticated access only)
- `qr-codes` contains customer names and should be **PRIVATE** (authenticated access only)
- `firmware-binaries` can be **PUBLIC** as devices need to download firmware without authentication

## Setup Instructions

### 1. Navigate to Supabase Storage

1. Log in to your Supabase project dashboard at https://supabase.com
2. Select your project (Saturday!)
3. Click on "Storage" in the left sidebar

### 2. Create the Storage Buckets

For each bucket, follow these steps:

#### A. Create "production-files" Bucket (PRIVATE)

1. Click "New bucket"
2. Enter bucket name: `production-files`
3. Set to **Private bucket** (UNCHECKED) - contains company IP, requires authentication
4. Click "Create bucket"

**Configure policies:**

1. Click on the `production-files` bucket
2. Go to "Policies" tab
3. Add the following policies:

**Policy 1: Allow authenticated users to upload**
```sql
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'production-files');
```

**Policy 2: Allow authenticated users to update**
```sql
CREATE POLICY "Allow authenticated updates"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'production-files');
```

**Policy 3: Allow authenticated users to delete**
```sql
CREATE POLICY "Allow authenticated deletes"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'production-files');
```

**Policy 4: Allow authenticated users to read/download**
```sql
CREATE POLICY "Allow authenticated reads"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'production-files');
```

#### B. Create "qr-codes" Bucket (PRIVATE)

1. Click "New bucket"
2. Enter bucket name: `qr-codes`
3. Set to **Private bucket** (UNCHECKED) - contains customer names, requires authentication
4. Click "Create bucket"

**Configure policies:**

```sql
-- Allow authenticated users to upload
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'qr-codes');

-- Allow authenticated users to delete
CREATE POLICY "Allow authenticated deletes"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'qr-codes');

-- Allow authenticated users to read/download
CREATE POLICY "Allow authenticated reads"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'qr-codes');
```

#### C. Create "firmware-binaries" Bucket (PUBLIC)

1. Click "New bucket"
2. Enter bucket name: `firmware-binaries`
3. Set to **Public bucket** (CHECKED) - allows devices to download firmware without authentication
4. Click "Create bucket"

**Configure policies:**

```sql
-- Allow authenticated users to upload
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'firmware-binaries');

-- Allow authenticated users to update
CREATE POLICY "Allow authenticated updates"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'firmware-binaries');

-- Allow authenticated users to delete
CREATE POLICY "Allow authenticated deletes"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'firmware-binaries');

-- Allow public read access
CREATE POLICY "Allow public reads"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'firmware-binaries');
```

### 3. Configure File Size Limits (Optional)

By default, Supabase allows files up to 50MB. To change this:

1. Go to Project Settings → Storage
2. Adjust the "Maximum file size" setting if needed

### 4. Verify Setup

Run this SQL query in the Supabase SQL Editor to verify all buckets exist:

```sql
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE name IN ('production-files', 'qr-codes', 'firmware-binaries');
```

You should see:
- `production-files` with `public = false`
- `qr-codes` with `public = false`
- `firmware-binaries` with `public = true`

### 5. Test Upload (Optional)

You can test uploading directly from the Supabase dashboard:

1. Click on a bucket
2. Click "Upload file"
3. Select a test file
4. Verify the file appears in the bucket
5. Try accessing the public URL

## Folder Structure

The app organizes files within buckets as follows:

### production-files
```
production-files/
  ├── {product_id}/
  │   ├── {step_id}-{timestamp}.pdf
  │   ├── {step_id}-{timestamp}.jpg
  │   └── {step_id}-{timestamp}.mp4
```

### qr-codes
```
qr-codes/
  └── qr-codes/
      ├── {uuid}.png
      └── {uuid}.png
```

### firmware-binaries
```
firmware-binaries/
  ├── {device_type_id}-{version}-{timestamp}.bin
  └── {device_type_id}-{version}-{timestamp}.hex
```

## Security Considerations

1. **Authentication Required for Writes**: All upload, update, and delete operations require authentication
2. **Private Buckets for Sensitive Data**:
   - `production-files` is **PRIVATE** (contains company IP - production instructions, processes)
   - `qr-codes` is **PRIVATE** (contains customer names and PII)
   - Only authenticated users can read/download from these buckets
3. **Public Bucket for Firmware**: `firmware-binaries` is **PUBLIC** to allow devices to download firmware without authentication
4. **Row Level Security**: Database records control which users can manage which files
5. **File Size Limits**: 50MB maximum file size (configurable)
6. **No Directory Listing**: Even in public buckets, users cannot list all files - they must know the exact URL
7. **Signed URLs for Private Files**: When accessing private files (production-files, qr-codes), use Supabase signed URLs with expiration times

## Troubleshooting

### Files Not Uploading

1. Check that you're authenticated (logged in)
2. Verify the bucket exists
3. Check file size doesn't exceed 50MB
4. Verify RLS policies are correctly configured

### Can't Access Files

**For production-files and qr-codes (private buckets):**
1. Ensure you're authenticated when accessing
2. Use signed URLs from Supabase (not public URLs)
3. Verify the "Allow authenticated reads" policy exists

**For firmware-binaries (public bucket):**
1. Ensure bucket is set to "Public"
2. Verify the "Allow public reads" policy exists
3. Check that the file was actually uploaded successfully

### Permission Errors

1. Go to Storage → Policies
2. Verify all four policies exist for each bucket
3. Check that policies target the correct bucket_id
4. Ensure policies use correct roles (authenticated, public)

## Next Steps

After setting up the storage buckets:

1. Test file upload from the admin app
2. Verify files are accessible via public URLs
3. Test file deletion
4. Monitor storage usage in the Supabase dashboard
