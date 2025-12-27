# QR Code Generation Features

## Overview

This document details the existing QR code generation and handling capabilities in the Saturday! Admin App. The app has a comprehensive QR code system used for production unit tracking, including generation, storage, display, scanning, and printing.

## Libraries and Dependencies

### QR Code Generation
- **qr_flutter** (v4.1.0) - Primary library for QR code generation with embedded branding

### QR Code Scanning
- **mobile_scanner** (v3.5.0) - Camera-based QR code scanning for mobile platforms

## Core Services

### QR Service (`lib/services/qr_service.dart`)

The primary service for QR code generation.

**Key Features:**
- Generates QR codes with embedded Saturday! logo (white circular background)
- Uses high error correction (QrErrorCorrectLevel.H - 30% redundancy) to accommodate the logo
- Default output: 512x512 PNG image as `Uint8List`
- Logo asset: `assets/images/saturday-icon-qr-100x100.png`

**Methods:**

```dart
/// Generates a QR code as a PNG image
Future<Uint8List> generateQRCode(
  String uuid, {
  double size = 512,
  bool embedLogo = true,
})

/// Parses a scanned QR code URL and extracts the UUID
String? parseQRCode(String scannedText)

/// Validates UUID format
bool _isValidUUID(String uuid)
```

**URL Format:**
```
{APP_BASE_URL}/unit/{uuid}
```

Example: `https://admin.saturdayvinyl.com/unit/a1b2c3d4-e5f6-7890-abcd-ef1234567890`

### QR Code Fetch Service (`lib/services/qr_code_fetch_service.dart`)

Handles retrieval of QR code images from cloud storage.

**Features:**
- Fetches QR code PNG images from Supabase storage (private bucket)
- Generates signed URLs for private bucket access (5-minute expiration)
- Supports multiple URL format variations

### QR Scanner Service (`lib/services/qr_scanner_service.dart`)

Processes scanned QR codes from both desktop and mobile.

**Features:**
- Strips prefix characters (§) from USB scanner input
- Validates QR codes match expected format
- Extracts UUID from parsed QR code URL

## Storage Configuration

**Supabase Storage:**
- **Bucket:** `qr-codes` (private)
- **Path Format:** `qr-codes/{uuid}.png`
- **Upload:** Via `StorageService.uploadQRCode()`
- **Retrieval:** Via `QRCodeFetchService.fetchQRCodeImage()`

**Constants (from `lib/config/constants.dart`):**
```dart
static const String qrCodeUrlScheme = 'https';
static const String qrCodePathPrefix = '/unit/';
static const String qrCodesBucket = 'qr-codes';
```

**Environment Variables:**
- `APP_BASE_URL` - Base URL used in QR code generation

## UI Widgets

### QR Code Display (`lib/widgets/production/qr_code_display.dart`)

Displays a QR code from a URL with caching.

**Features:**
- Cached network image loading
- Displays unit ID and instructional text
- Optional regenerate button
- Customizable size (default 200x200)
- Error handling with fallback icon

### Desktop Scanner (`lib/widgets/production/qr_scanner_desktop.dart`)

USB barcode/QR scanner integration for desktop.

**Features:**
- Auto-focused text input field for scanner input
- Visual status indicators (Ready/Processing/Error)
- Manual entry fallback
- Prefix stripping for USB scanner input

### Mobile Scanner (`lib/widgets/production/qr_scanner_mobile.dart`)

Camera-based QR code scanning for mobile devices.

**Features:**
- Full-screen camera view using `mobile_scanner` package
- Scanning frame overlay with green border
- Flash/torch toggle button
- Close button for exiting
- Error messages and processing indicator

### Label Layout (`lib/widgets/production/label_layout.dart`)

1" x 1" thermal label preview containing QR code.

**Contents:**
- QR code
- Unit ID
- Product + variant name
- Customer name
- Order number

**Features:**
- Scalable for different preview sizes (default scale 1.0)

## Printing

### Printer Service (`lib/services/printer_service.dart`)

Handles QR code label printing to thermal printers.

**Label Types:**

1. **Production Unit Labels** (`generateQRLabel()`)
   - Contains: QR code (48x48), product + variant text
   - Size: 1" x 1" thermal label
   - Format: PDF

2. **Step Labels** (`generateStepLabel()`)
   - Contains: QR code, product + variant, custom label text
   - Supports custom text (e.g., "LEFT SIDE", "RIGHT SIDE")
   - Size: 1" x 1" thermal label

**Features:**
- Lists available printers
- Supports printer selection/defaults
- Desktop-only (macOS, Windows, Linux)
- Direct print to thermal printer or system print dialog
- Auto-print on unit creation (configurable)

### Print Preview (`lib/widgets/production/print_preview_dialog.dart`)

Preview dialog before printing.

**Features:**
- 3x scaled label preview for visibility
- Printer selection dropdown
- Error handling with fallback
- Print button with progress indicator

## State Management (Providers)

### QR Code Fetch Provider (`lib/providers/qr_code_fetch_provider.dart`)

Riverpod provider for fetching QR codes from storage.

## Production Unit Integration

### Model (`lib/models/production_unit.dart`)

Production units store QR code references:
- `qrCodeUrl` - URL to the QR code in Supabase storage
- `uuid` - The UUID encoded in the QR code
- `unitId` - Human-readable ID (e.g., SV-TURNTABLE-00001)

### Creation Flow (`CreateUnitScreen`)

When a production unit is created:
1. UUID is generated
2. Unit ID is generated (SV-{PRODUCT_CODE}-{NUMBER})
3. QR code is generated with embedded logo
4. QR code is uploaded to Supabase storage
5. Database record is created with `qr_code_url`
6. (Optional) Label is auto-printed

### QR Code Regeneration (`lib/scripts/regenerate_qr_codes.dart`)

Debug utility to regenerate QR codes for existing units:
- Regenerates with current branded logo design
- Overwrites existing QR codes in storage
- Accessible via `RegenerateQRScreen` debug UI

## Platform Support

| Feature | macOS | Windows | Linux | iOS | Android | Web |
|---------|-------|---------|-------|-----|---------|-----|
| QR Generation | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| QR Display | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| USB Scanner | ✓ | ✓ | ✓ | - | - | - |
| Camera Scanner | - | - | - | ✓ | ✓ | Limited |
| Label Printing | ✓ | ✓ | ✓ | - | - | - |

## Summary

The existing QR code system provides:
- **Generation**: Branded QR codes with Saturday! logo, high error correction
- **Storage**: Private Supabase bucket with signed URL access
- **Display**: Cached network images with fallback handling
- **Scanning**: USB scanner (desktop) and camera (mobile) support
- **Printing**: 1" x 1" thermal labels with printer management
- **URL Format**: `{APP_BASE_URL}/unit/{uuid}`

## RFID Tag QR Codes

The QR service has been extended to support on-demand QR code generation for RFID tags.

### Tag QR Code Features

- **URL Format**: `{APP_BASE_URL}/tags/{epc}`
- **On-demand generation**: No cloud storage, generated when needed
- **Same branding**: Uses the same Saturday! logo embedding as production units
- **Multiple sizes**: Configurable output size for different label formats
- **Save to file**: Can be saved to local filesystem with formatted filename

### Usage

```dart
final qrService = QRService();

// Generate tag QR code
final qrBytes = await qrService.generateTagQRCode(
  '5356A1B2C3D4E5F67890ABCD',
  size: 512,        // Optional, default 512
  embedLogo: true,  // Optional, default true
);

// Save to file with formatted filename
final filename = QRService.formatTagFilename('5356A1B2C3D4E5F67890ABCD');
// Result: 'tag-5356-A1B2-C3D4-E5F6-7890-ABCD.png'

final savedPath = await qrService.saveQRCodeToFile(qrBytes, filename);
```

### QRCodeType Enum

The `generateQRCode` method now accepts a `type` parameter:

```dart
enum QRCodeType {
  unit,  // URL: /unit/{uuid} - default
  tag,   // URL: /tags/{epc}
}
```
