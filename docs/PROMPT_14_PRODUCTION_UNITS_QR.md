# Prompt 14: Production Unit Models and QR Code Generation - Implementation Summary

## Overview
Implemented models and services for production unit tracking with QR code generation capabilities.

## Implementation Date
2025-10-09

## Database Schema

### production_units Table
```sql
CREATE TABLE production_units (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
  unit_id VARCHAR(100) UNIQUE NOT NULL,
  product_id UUID NOT NULL REFERENCES products(id),
  variant_id UUID NOT NULL REFERENCES product_variants(id),
  order_id UUID REFERENCES orders(id),
  current_owner_id UUID REFERENCES users(id),
  qr_code_url TEXT NOT NULL,
  production_started_at TIMESTAMP WITH TIME ZONE,
  production_completed_at TIMESTAMP WITH TIME ZONE,
  is_completed BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES users(id)
);
```

### unit_step_completions Table
```sql
CREATE TABLE unit_step_completions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID NOT NULL REFERENCES production_units(id),
  step_id UUID NOT NULL REFERENCES production_steps(id),
  completed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_by UUID NOT NULL REFERENCES users(id),
  notes TEXT,
  UNIQUE(unit_id, step_id)
);
```

## Files Created

### Models
- **lib/models/production_unit.dart**
  - ProductionUnit model with full JSON serialization
  - `getFormattedUnitId()` - returns the human-readable ID
  - `isInProgress()` - checks if unit is started but not complete
  - `validateUnitIdFormat()` - validates ID format (SV-{CODE}-{NUMBER})
  - Equatable for value comparison

- **lib/models/unit_step_completion.dart**
  - UnitStepCompletion model for tracking completed steps
  - Links unit, production step, user, and timestamp
  - Optional notes field for worker comments
  - Equatable implementation

### Services
- **lib/services/qr_service.dart**
  - `generateQRCode(uuid, size, embedLogo)` - creates QR code with Saturday logo
  - Uses high error correction level (QrErrorCorrectLevel.H) to accommodate logo
  - Returns QR code as Uint8List PNG image data
  - `parseQRCode(scannedText)` - extracts UUID from scanned URL
  - Validates URL format matches APP_BASE_URL/unit/{uuid}
  - UUID validation with regex pattern

- **lib/services/storage_service.dart** (updated)
  - Already had `uploadQRCode(imageData, uuid)` method
  - Uploads to 'qr-codes' private bucket
  - Returns file path (not signed URL)
  - `getSignedUrl()` generates temporary access URLs for private files

### Utilities
- **lib/utils/id_generator.dart**
  - `generateUnitId(productCode, sequenceNumber)` - formats as SV-{CODE}-{SEQ}
  - Zero-pads sequence to 5 digits (e.g., SV-TURNTABLE-00001)
  - `getNextSequenceNumber(productCode)` - queries database for next sequence
  - `extractProductCode(unitId)` - parses product code from unit ID
  - `extractSequenceNumber(unitId)` - parses sequence number
  - `validateUnitId(unitId)` - regex validation of format

### Database
- **supabase/migrations/005_production_units.sql**
  - Creates production_units table with all required fields
  - Creates unit_step_completions table for tracking progress
  - Comprehensive indexes for performance
  - RLS policies for authenticated access
  - Foreign key constraints and cascading deletes
  - Documentation comments on all columns

## Key Features

### Unit ID Format
- Format: `SV-{PRODUCT_CODE}-{SEQUENCE}`
- Example: `SV-TURNTABLE-00001`
- Sequence numbers are zero-padded to 5 digits
- Automatically increments per product code
- Validated with regex pattern

### QR Code Generation
- Embeds Saturday! logo in center of QR code
- Uses high error correction level (30% redundancy)
- Generates 512x512 PNG images by default
- QR code URL format: `{APP_BASE_URL}/unit/{uuid}`
- Stores in private 'qr-codes' Supabase bucket

### UUID System
- Each unit has unique UUID for QR code scanning
- UUID is separate from database ID for security
- Enables scannable tracking without exposing database IDs
- URL format allows web-based unit lookup

### Production Tracking
- `production_started_at` - set when first step completed
- `production_completed_at` - set when all steps done
- `is_completed` boolean for quick filtering
- `current_owner_id` tracks who's working on unit
- Optional `order_id` links to customer order

### Step Completion
- Tracks which steps are done for each unit
- Records completion timestamp and user
- Optional notes field for worker feedback
- Unique constraint prevents duplicate completions
- Cascade delete when unit is deleted

## Storage Buckets Required

### qr-codes (Private)
```sql
-- Create bucket in Supabase dashboard
-- Bucket name: qr-codes
-- Public: false (private - requires authentication)

-- RLS policy for reads
CREATE POLICY "Allow authenticated reads"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'qr-codes');

-- RLS policy for uploads
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'qr-codes');
```

## Unit ID Sequence Logic

The sequence number is determined by:
1. Query database for units with matching product code
2. Extract sequence from highest unit_id
3. Increment by 1
4. If no existing units, start at 1

Example flow:
- Product code: TURNTABLE
- Existing units: SV-TURNTABLE-00001, SV-TURNTABLE-00002
- Next unit: SV-TURNTABLE-00003

## QR Code URL Format

Generated QR codes encode URLs in this format:
```
{APP_BASE_URL}/unit/{uuid}
```

Example:
```
https://admin.saturdayvinyl.com/unit/a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

When scanned:
1. Parse URL to extract UUID
2. Validate domain matches APP_BASE_URL
3. Validate path format is /unit/{uuid}
4. Validate UUID format
5. Return UUID for database lookup

## Data Flow

### Unit Creation (Future Prompt 15)
1. Get product code from product
2. Generate next sequence number
3. Generate UUID
4. Create unit ID (SV-{CODE}-{SEQ})
5. Generate QR code with UUID
6. Upload QR code to storage
7. Insert unit record with QR URL
8. Transaction ensures all-or-nothing

### Step Completion (Future Prompt 19)
1. Scan QR code → parse UUID
2. Look up unit by UUID
3. Load production steps for product
4. Mark step as complete
5. Record timestamp, user, notes
6. Check if all steps complete
7. If yes, mark unit complete

## Testing Recommendations

### Unit Tests
- [ ] ProductionUnit model serialization/deserialization
- [ ] ProductionUnit.validateUnitIdFormat()
- [ ] ProductionUnit.isInProgress()
- [ ] UnitStepCompletion model serialization
- [ ] QRService.parseQRCode() with valid URLs
- [ ] QRService.parseQRCode() with invalid URLs
- [ ] IDGenerator.generateUnitId() formatting
- [ ] IDGenerator.extractProductCode()
- [ ] IDGenerator.extractSequenceNumber()
- [ ] IDGenerator.validateUnitId()

### Integration Tests
- [ ] Generate QR code → upload → verify in storage
- [ ] Get next sequence number → create unit → verify increment
- [ ] Parse QR code URL → verify correct UUID extraction
- [ ] Invalid QR codes throw appropriate errors

### Manual Testing
- [ ] Generate QR code with logo (check visual appearance)
- [ ] Scan generated QR code with mobile device
- [ ] Verify QR code URL resolves correctly
- [ ] Test unit ID sequence numbering
- [ ] Verify database constraints (unique unit_id, uuid)

## Known Limitations

1. **QR Code Logo**: Requires saturday-icon.png in assets/images/
2. **APP_BASE_URL**: Must be configured in .env file
3. **Sequence Numbers**: Not globally unique, only per product code
4. **QR Code Size**: Fixed 512x512, may need adjustment for different label sizes
5. **UUID Format**: Standard UUID v4, not cryptographically verified

## Security Considerations

- QR codes stored in **private** bucket (not public)
- Requires authentication to access QR code images
- Use signed URLs for temporary access (1 hour default)
- UUIDs in QR codes don't expose database structure
- Unit IDs are predictable but not sensitive

## Future Enhancements

1. **QR Code Customization**
   - Configurable size
   - Different logo options
   - Color schemes

2. **Batch QR Generation**
   - Generate multiple QR codes at once
   - Bulk printing support

3. **QR Code Analytics**
   - Track scan frequency
   - Last scanned location/user
   - Scan history

4. **Advanced Sequencing**
   - Custom sequence patterns
   - Prefix/suffix customization
   - Alphanumeric sequences

5. **UUID Versioning**
   - Support different UUID versions
   - Custom ID generation algorithms

## Related Prompts
- **Prompt 13**: Production Steps - Steps that will be tracked against units
- **Prompt 15**: Production Unit Repository - CRUD operations for units
- **Prompt 16**: Create Production Unit Flow - UI for creating units
- **Prompt 18**: QR Code Scanning - Scanning QR codes to look up units
- **Prompt 19**: Production Step Completion - Marking steps complete

## Database Migration Required
Before using production units, run:
```bash
psql -d your_database -f supabase/migrations/005_production_units.sql
```

Or in Supabase dashboard:
1. Go to SQL Editor
2. Paste contents of 005_production_units.sql
3. Run migration
4. Verify tables created

## Dependencies
- qr_flutter: ^4.1.0 (QR code generation)
- equatable: ^2.0.5 (model equality)
- uuid package (future - for UUID generation)

## Notes
- Production units represent individual items being manufactured
- Each unit tracks a single product variant
- Units can optionally link to customer orders
- QR codes enable mobile scanning on production floor
- Unit IDs are human-readable for manual entry fallback
- Step completions are tracked separately for detailed progress
