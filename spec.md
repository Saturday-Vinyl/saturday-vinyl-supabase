# Saturday! Admin App - Product Specification

## Executive Summary

Saturday! is building a cross-platform (desktop macOS and mobile iOS/Android) administration application to manage production pipelines for their audio-related furniture business with embedded technologies. This Flutter-based app will integrate with Shopify for e-commerce data and use Supabase as a managed backend for production tracking, firmware management, and employee authentication.

## Business Context

- **Company**: Saturday! (Saturday Vinyl)
- **Product Line**: Audio-related furniture with embedded electronics
- **Business Model**: Shopify-powered e-commerce with custom production management
- **Initial Scope**: Internal administration tools (consumer apps to follow later)
- **Primary Users**: Production floor workers, managers, and administrators

## Product Vision

### Core Objectives
1. Track individual product units through configurable production workflows
2. Manage firmware library and provisioning for embedded devices
3. Integrate with Shopify for product catalog and order data
4. Support both build-to-order and build-to-stock production models
5. Enable QR code-based tracking throughout production lifecycle

### Key Principles
- Start simple, iterate based on production maturity
- Leverage managed services (Shopify, Supabase) to minimize custom backend development
- Always-online architecture (reliable facility WiFi assumed)
- Mobile for flexibility, desktop for workstation-specific tasks with hardware peripherals

## Technical Architecture

### Technology Stack

#### Frontend
- **Framework**: Flutter (cross-platform)
- **Platforms**:
  - macOS desktop (primary workstations)
  - iOS mobile
  - Android mobile
  - Web (minimal - QR code landing pages only for v1)

#### Backend
- **Managed Backend**: Supabase
  - PostgreSQL database
  - Authentication (Google Workspace OAuth)
  - File storage (production files, firmware binaries)
  - Real-time subscriptions (for future notifications)

- **E-commerce Platform**: Shopify
  - Product catalog and variants
  - Customer accounts
  - Order management
  - Inventory levels

#### Authentication
- **Employee Users**: Google Workspace OAuth (@saturdayvinyl.com domain)
  - MFA enforced at Google Workspace organization level
  - Session duration: 1 week
  - Multiple concurrent sessions allowed
- **Consumer Users**: Deferred to future consumer app (will use app-level auth)

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Client Applications                      │
├──────────────┬──────────────┬──────────────┬────────────────┤
│   macOS      │   macOS      │   iOS/       │   Web          │
│   Desktop    │   Desktop    │   Android    │   (minimal)    │
│   (Workst. 1)│   (Workst. N)│   Mobile     │                │
└──────┬───────┴──────┬───────┴──────┬───────┴────────┬───────┘
       │              │              │                │
       └──────────────┴──────────────┴────────────────┘
                          │
       ┌──────────────────┴──────────────────┐
       │                                     │
       ▼                                     ▼
┌─────────────────┐                 ┌─────────────────┐
│   Supabase      │                 │    Shopify      │
│   (Backend)     │                 │   (E-commerce)  │
├─────────────────┤                 ├─────────────────┤
│ • Auth          │                 │ • Products      │
│ • Database      │◄────sync────────┤ • Variants      │
│ • Storage       │                 │ • Orders        │
│ • Real-time     │                 │ • Customers     │
└─────────────────┘                 └─────────────────┘
```

### Data Architecture

#### Data Ownership Model

**Shopify (Source of Truth)**
- Product catalog (name, description, images, SKUs)
- Product variants (wood species, liner color, etc.)
- Customer accounts (name, email, addresses)
- Orders (customer, products, shipping, fulfillment)
- Inventory levels (synced from Supabase)

**Supabase (Source of Truth)**
- Employee users and permissions
- Production units (in-progress and completed)
- Production step tracking and completion history
- Device types (embedded hardware catalog)
- Firmware versions and binary files
- Production step files (gcode, designs, etc.)
- Unit-to-customer ownership mappings
- Unit-to-order associations

#### Database Schema (Supabase PostgreSQL)

```sql
-- Employee Users
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  google_id VARCHAR UNIQUE NOT NULL,
  email VARCHAR UNIQUE NOT NULL,
  full_name VARCHAR,
  is_admin BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  last_login TIMESTAMP
);

-- Permissions
CREATE TABLE permissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR UNIQUE NOT NULL,
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Initial permissions: 'manage_products', 'manage_firmware', 'manage_production'

-- User Permissions (many-to-many)
CREATE TABLE user_permissions (
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  permission_id UUID REFERENCES permissions(id) ON DELETE CASCADE,
  granted_at TIMESTAMP DEFAULT NOW(),
  granted_by UUID REFERENCES users(id),
  PRIMARY KEY (user_id, permission_id)
);

-- Products (synced from Shopify)
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shopify_product_id VARCHAR UNIQUE NOT NULL,
  shopify_product_handle VARCHAR,
  name VARCHAR NOT NULL,
  product_code VARCHAR UNIQUE NOT NULL, -- e.g., "PROD1" for unit ID generation
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  last_synced_at TIMESTAMP
);

-- Product Variants (synced from Shopify)
CREATE TABLE product_variants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  shopify_variant_id VARCHAR UNIQUE NOT NULL,
  sku VARCHAR,
  name VARCHAR NOT NULL, -- e.g., "Walnut / Black Liner"
  option1_name VARCHAR, -- e.g., "Wood Species"
  option1_value VARCHAR, -- e.g., "Walnut"
  option2_name VARCHAR, -- e.g., "Liner Color"
  option2_value VARCHAR, -- e.g., "Black"
  option3_name VARCHAR,
  option3_value VARCHAR,
  price DECIMAL(10,2),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Production Steps (configured per product)
CREATE TABLE production_steps (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  name VARCHAR NOT NULL, -- e.g., "CNC Machining", "Laser Engraving"
  description TEXT, -- free-form instructions
  step_order INTEGER NOT NULL, -- for UI display ordering
  file_url VARCHAR, -- Supabase storage URL for associated file
  file_name VARCHAR,
  file_type VARCHAR,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE (product_id, step_order)
);

-- Device Types (embedded hardware catalog)
CREATE TABLE device_types (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR UNIQUE NOT NULL,
  description TEXT,
  capabilities VARCHAR[], -- e.g., ['BLE', 'WiFi', 'Thread', 'RFID']
  spec_url VARCHAR, -- link to datasheets, documentation
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Product Device Types (which devices are used in which products)
CREATE TABLE product_device_types (
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  device_type_id UUID REFERENCES device_types(id) ON DELETE CASCADE,
  quantity INTEGER DEFAULT 1, -- how many of this device per unit
  created_at TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (product_id, device_type_id)
);

-- Firmware Versions
CREATE TABLE firmware_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  device_type_id UUID REFERENCES device_types(id) ON DELETE CASCADE,
  version VARCHAR NOT NULL, -- semantic versioning: "1.2.3"
  release_notes TEXT,
  binary_url VARCHAR NOT NULL, -- Supabase storage URL
  binary_filename VARCHAR NOT NULL,
  binary_size BIGINT,
  is_production_ready BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  created_by UUID REFERENCES users(id),
  UNIQUE (device_type_id, version)
);

-- Customers (minimal cache from Shopify)
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shopify_customer_id VARCHAR UNIQUE NOT NULL,
  email VARCHAR,
  first_name VARCHAR,
  last_name VARCHAR,
  created_at TIMESTAMP DEFAULT NOW(),
  last_synced_at TIMESTAMP
);

-- Orders (minimal cache from Shopify)
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  shopify_order_id VARCHAR UNIQUE NOT NULL,
  shopify_order_number VARCHAR,
  customer_id UUID REFERENCES customers(id),
  order_date TIMESTAMP,
  status VARCHAR,
  created_at TIMESTAMP DEFAULT NOW(),
  last_synced_at TIMESTAMP
);

-- Production Units (individual physical products being built)
CREATE TABLE production_units (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uuid UUID UNIQUE DEFAULT uuid_generate_v4(), -- for secure public URLs
  unit_id VARCHAR UNIQUE NOT NULL, -- human-readable: "SV-PROD1-00001"
  product_id UUID REFERENCES products(id) NOT NULL,
  variant_id UUID REFERENCES product_variants(id) NOT NULL,
  order_id UUID REFERENCES orders(id), -- NULL if build-to-stock
  current_owner_id UUID REFERENCES customers(id), -- NULL until registered
  qr_code_url VARCHAR, -- generated QR code image URL
  production_started_at TIMESTAMP DEFAULT NOW(),
  production_completed_at TIMESTAMP,
  is_completed BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  created_by UUID REFERENCES users(id)
);

-- Production Unit Step Completion (tracking progress)
CREATE TABLE unit_step_completions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID REFERENCES production_units(id) ON DELETE CASCADE,
  step_id UUID REFERENCES production_steps(id) ON DELETE CASCADE,
  completed_at TIMESTAMP DEFAULT NOW(),
  completed_by UUID REFERENCES users(id),
  notes TEXT, -- optional worker notes
  UNIQUE (unit_id, step_id)
);

-- Unit Firmware History (what firmware was installed when)
CREATE TABLE unit_firmware_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID REFERENCES production_units(id) ON DELETE CASCADE,
  device_type_id UUID REFERENCES device_types(id) ON DELETE CASCADE,
  firmware_version_id UUID REFERENCES firmware_versions(id),
  installed_at TIMESTAMP DEFAULT NOW(),
  installed_by UUID REFERENCES users(id),
  installation_method VARCHAR -- 'production' or 'field_update'
);

-- Unit Ownership History (track ownership transfers)
CREATE TABLE unit_ownership_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID REFERENCES production_units(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES customers(id),
  registered_at TIMESTAMP DEFAULT NOW(),
  registration_method VARCHAR -- 'order' or 'manual_registration'
);

-- Indexes for performance
CREATE INDEX idx_production_units_product ON production_units(product_id);
CREATE INDEX idx_production_units_order ON production_units(order_id);
CREATE INDEX idx_production_units_completed ON production_units(is_completed);
CREATE INDEX idx_unit_step_completions_unit ON unit_step_completions(unit_id);
CREATE INDEX idx_firmware_versions_device ON firmware_versions(device_type_id);
```

#### Shopify Integration

**GraphQL Admin API**
- **Product Sync**: Periodic polling or webhook-triggered sync of products and variants
- **Order Sync**: Real-time or periodic sync of new orders (read-only for admin app)
- **Customer Sync**: Minimal customer data cached for production UI
- **Inventory Updates**: Manual process (not automated in v1)

**Deep Linking**
- Admin app should provide clickable links to Shopify admin for orders
- Format: `https://admin.shopify.com/store/{store_name}/orders/{order_id}`

**Error Handling**
- Graceful degradation when Shopify API unavailable
- Block critical flows that require Shopify data (e.g., creating unit from order)
- Show clear error messages with retry options
- Cache recently-synced data for short-term offline tolerance

### File Storage (Supabase Storage)

**Buckets**
1. **production-files**: gcode, laser designs, production step files
2. **firmware-binaries**: firmware .bin files for device types
3. **qr-codes**: generated QR code images for units
4. **assets**: company logos, branding assets

**Access Control**
- Production files: Authenticated users only
- Firmware binaries: Authenticated users only
- QR codes: Public read (for customer scanning)
- Assets: Public read

## Feature Requirements

### MVP Features (Phase 1)

#### 1. Employee Authentication & Authorization

**Requirements**
- Google Workspace OAuth integration (@saturdayvinyl.com domain only)
- Auto-provision users on first login with default "viewer" permissions
- Two roles: Admin and User
- Three initial permissions: `manage_products`, `manage_firmware`, `manage_production`
- Only Admin role can assign/revoke permissions
- Session duration: 1 week with automatic refresh
- Multiple concurrent sessions allowed per user
- MFA enforced at Google Workspace organization level

**User Stories**
- As an employee, I can log in using my @saturdayvinyl.com Google account
- As an admin, I can view all users and assign/revoke permissions
- As a user, I can view my current permissions
- As the system, I automatically deactivate sessions after 1 week of inactivity

**Initial Setup**
- Seed first admin user by email address in deployment configuration
- Email: (to be provided at deployment time)

#### 2. Product Management

**Requirements**
- Sync products and variants from Shopify via GraphQL Admin API
- Display product catalog with variants in admin app
- Configure production steps per product (not per variant)
- Each production step includes:
  - Name
  - Description (free-form text instructions)
  - Display order (for UI sequencing)
  - Optional file attachment (single file per step)
- Product code assignment for unit ID generation (e.g., "PROD1")
- Link to device type(s) used in product (for firmware tracking)

**User Stories**
- As an admin with `manage_products` permission, I can view all products synced from Shopify
- As an admin, I can configure production steps for a product
- As an admin, I can upload files (gcode, designs) to production steps
- As an admin, I can reorder production steps for UI display
- As an admin, I can assign a product code to each product
- As an admin, I can specify which device types are used in a product
- As a user, I can view product details and production step configurations (read-only)

**Shopify Sync**
- Initial sync: Manual trigger or automatic on first app launch
- Ongoing sync: Configurable interval (e.g., hourly) or manual refresh
- Sync product name, description, handle, variants, SKUs
- Cache synced data in Supabase for offline tolerance

#### 3. Production Unit Creation & QR Code Generation

**Requirements**
- Create new production units manually via admin app
- Unit ID format: `SV-{PRODUCT_CODE}-{AUTO_INCREMENT}` (e.g., "SV-PROD1-00001")
- Each unit also has a UUID for secure public URL access
- Associate unit with:
  - Product and variant (required)
  - Order (optional - for build-to-order)
  - Customer (auto-populated from order if applicable)
- Generate QR code on unit creation
  - QR code content: URL format `https://yourapp.com/unit/{uuid}`
  - Embed Saturday! square logo (saturday-icon.svg) in QR code center
  - Store generated QR code image in Supabase storage (public bucket)
- Display list of pending Shopify orders as "recommended units to produce"
- Allow creating units without associated orders (build-to-stock)

**User Stories**
- As a user with `manage_production` permission, I can view pending orders from Shopify
- As a user, I can create a new production unit for a specific order
- As a user, I can create a new production unit for inventory (no order)
- As a user, I see the auto-generated unit ID immediately after creation
- As the system, I generate a QR code with embedded logo for each new unit
- As a user, I can view the generated QR code for printing

**QR Code Specification**
- Format: URL-based `https://app.saturdayvinyl.com/unit/{uuid}` (example domain)
- Embed: saturday-icon.svg logo in center of QR code
- Error correction: High (to accommodate logo embedding)
- Storage: Supabase public storage bucket

#### 4. QR Code Scanning & Context Switching

**Requirements**
- Desktop: USB QR code scanners (keyboard wedge mode - no special drivers)
- Mobile: Device camera for QR scanning
- Scanning a QR code switches app context to that unit's detail view
- No validation - any valid unit QR code switches context
- Show unit details: ID, product/variant, customer (if any), order (if any)
- Display all production steps with completion status

**User Stories**
- As a production worker on desktop, I can scan a QR code using the USB scanner
- As a production worker on mobile, I can scan a QR code using my phone's camera
- As a worker, scanning a QR code immediately shows me that unit's details and progress
- As a worker, I can see which production steps are complete and which are pending

**Implementation Notes**
- Desktop: Listen for keyboard input (QR scanners output text + enter)
- Mobile: Use Flutter camera plugin with QR detection
- Parse scanned URL to extract unit UUID
- Query Supabase for unit details by UUID
- Handle invalid/unknown QR codes gracefully (show error message)

#### 5. Production Step Completion Tracking

**Requirements**
- Mark production steps as complete via QR code scan workflow
- Steps can be completed in any order (no sequential enforcement)
- Steps displayed in configured order for UI clarity
- Captured data on step completion:
  - Timestamp (automatic)
  - Employee who completed it (automatic from auth)
  - Optional notes (free-form text field)
- View unit's current production status (which steps complete/pending)
- Mark unit as fully completed when all steps done

**User Stories**
- As a production worker, I scan a unit's QR code to open its details
- As a worker, I can mark a specific production step as complete
- As a worker, I can optionally add notes when completing a step
- As a worker, I can see who completed each step and when
- As a manager, I can view all units currently in production and their step progress

**UI/UX**
- Unit detail view shows all steps in configured order
- Completed steps: Green checkmark, timestamp, worker name
- Pending steps: Gray/incomplete state
- Tap/click step to mark complete (if user has `manage_production` permission)
- Confirmation dialog with optional notes field
- Auto-refresh after marking complete

#### 6. Production Status View

**Requirements**
- Dashboard showing all units currently in production (not fully completed)
- Display for each unit:
  - Unit ID
  - Product and variant name
  - Current step (most recently completed, or "Not started")
  - Associated order/customer (if any)
  - Production start date
- No filtering or sorting for v1 (simple list view)
- Tap/click unit to view full details
- Real-time updates (or manual refresh button)

**User Stories**
- As a production manager, I can see all units currently being built
- As a manager, I can quickly identify which units are at which production stage
- As a manager, I can tap a unit to see full details and mark steps complete
- As a worker, I can check the status of all active production units

#### 7. Thermal Label Printing (QR Codes)

**Requirements**
- Print 1" x 1" thermal labels via USB thermal printer (desktop only)
- Label content:
  - QR code (with embedded logo)
  - Product name and variant
  - Unit ID (human-readable)
  - Customer name and order date (if unit is for an order)
  - All text sized appropriately for 1" x 1" format
- Print from unit detail view (button: "Print QR Label")
- Support standard thermal label printers (e.g., Dymo, Brother, Zebra)

**User Stories**
- As a production worker on desktop, I can print a QR label for a newly created unit
- As a worker, I can reprint a label if it's damaged or lost
- As a worker, the printed label includes all necessary identification info

**Implementation Notes**
- Use Flutter printing plugin or direct printer communication
- Generate label layout programmatically (QR code + text fields)
- Test with specific printer models used in production (specify models)
- Handle printer errors gracefully (out of paper, disconnected, etc.)

**Printer Models** (to be confirmed)
- CNC workstation: TBD
- Shipping workstation: TBD

#### 8. File Launching for Production Steps

**Requirements**
- Production steps can have associated files (gcode, laser designs, etc.)
- Desktop: Launch file in appropriate external application
  - CNC gcode → open in gSender (or system default for .gcode/.nc files)
  - Laser designs → open in laser software (or system default for file type)
  - Firmware binaries → open in terminal/flashing tool
- Mobile: Download file for manual handling (no direct launch)
- File stored in Supabase storage, downloaded on-demand
- Desktop: Attempt direct launch via system file association
  - If launch fails, download to temp directory and notify user

**User Stories**
- As a CNC operator on desktop, I scan a unit QR code, view the CNC step, and click to open the gcode file in gSender
- As a laser operator, I open the laser design file directly from the app into my laser software
- As an operator, if the file won't open automatically, I can download it and open manually
- As a mobile user, I can download production files but don't expect them to launch directly

**Implementation Notes**
- Use Flutter `url_launcher` plugin or similar for file launching on desktop
- Store file MIME types or extensions in database for proper handling
- Fallback: Download to user's Downloads folder with notification
- Test with actual production software (gSender, laser tools)

#### 9. Basic Firmware Library

**Requirements**
- Upload firmware binary files via admin app (desktop only for v1)
- Associate firmware with device type
- Semantic versioning (e.g., "1.2.3")
- Release notes (free-form text)
- Mark firmware as "production ready" vs. "testing"
- View list of all firmware versions per device type
- Download firmware binary for manual flashing (launch external flashing tool)

**User Stories**
- As an admin with `manage_firmware` permission, I can upload a new firmware binary
- As an admin, I specify the device type, version number, and release notes
- As an admin, I can mark firmware as production-ready
- As a firmware technician, I can view all available firmware for a device type
- As a technician, I can download a firmware binary and launch external flashing tools
- As a technician, I manually confirm firmware flash completion in the app

**Firmware Flashing Workflow (v1)**
1. Technician scans unit QR code
2. App shows firmware provisioning step
3. Technician taps "Flash Firmware" button
4. App displays list of production-ready firmware for this unit's device type
5. Technician selects firmware version
6. App downloads binary and attempts to launch external tool (e.g., esptool) with file path
7. Technician manually flashes device using external tool
8. Technician returns to app and marks step complete (manually confirms success)
9. App records firmware version in unit's firmware history

**External Flashing Tools**
- ESP32 devices: esptool (Python-based)
- Embedded Linux devices: custom flashing scripts (TBD)
- App should support launching command-line tools with parameters

**Implementation Notes**
- Use Flutter `process` package to launch CLI tools on desktop
- Provide user instructions for installing flashing tools (esptool, etc.)
- No automatic verification of flash success in v1 (manual confirmation only)

### Deferred Features (Phase 2 and Beyond)

The following features are explicitly out of scope for MVP but should be considered in the system architecture for future development:

#### Advanced Firmware Management
- Automatic firmware update notifications to consumer app
- Over-the-air (OTA) firmware updates via BLE
- Firmware version tracking across all fielded units
- Automatic flagging of units needing updates

#### Enhanced Production Tracking
- Historical production data and analytics
- Time tracking per step (how long each step takes)
- Worker productivity metrics
- Bottleneck identification
- Production velocity reporting
- Search and filtering in production status view

#### Advanced Step Completion
- Pass/fail QC checklist items
- Photo uploads for QC documentation
- Reject and rework workflows (send unit back to previous step)
- Required vs. optional steps
- Conditional step logic

#### Notifications & Alerts
- Push notifications for new orders
- Alerts for delayed/stuck units
- Firmware update available notifications
- Shopify sync error alerts

#### Customer Features (Consumer App)
- Customer product registration via QR code
- Ownership transfer management
- Warranty tracking
- Firmware update prompts to end users
- Product manuals and support docs

#### Web Interface
- Full web-based admin interface (no app required)
- Public unit lookup by QR code
- Customer-facing web portal

## User Interface Design

### Branding & Style Guide

**Brand Name**
- Primary: "Saturday!"
- Secondary context: "Saturday Vinyl" (when needed)
- Consistent across admin and consumer apps

**Logo Assets**
- Full logo: `/assets/images/saturday-logo.svg`
- Icon/square logo: `/assets/images/saturday-icon.svg`

**Color Palette**
```
Primary Dark:    #3F3A34
Success/Green:   #30AA47
Error/Orange:    #F35345
Info/Blue:       #6AC5F4
Secondary/Grey:  #B2AAA3
Light:           #E2DAD0
```

**Typography**
- Titles/Headings: Bevan (Google Fonts serif) - https://fonts.google.com/specimen/Bevan
- Body Text: System sans-serif default
- Monospace (for unit IDs, codes): System monospace default

**Design Principles**
- Clean, functional UI optimized for production floor use
- High contrast for visibility in various lighting conditions
- Large touch targets for mobile (minimum 44x44 points)
- Minimal text entry (prefer scanning, tapping, selecting)
- Clear visual feedback for all actions

### Screen Mockups & User Flows

#### Desktop Layout (macOS)

**Primary Navigation**
- Sidebar navigation (left side, collapsible)
  - Dashboard (production status)
  - Products
  - Production Units
  - Firmware
  - Users (admin only)
  - Settings
- Top bar: User profile, notifications (future), logout

**Dashboard View**
```
┌─────────────────────────────────────────────────────────┐
│  Saturday!                     [Username ▼]  [Logout]   │
├──────────┬──────────────────────────────────────────────┤
│          │  Units in Production                         │
│ • Dash   │  ┌──────────────────────────────────────┐   │
│ • Prods  │  │ SV-PROD1-00001                       │   │
│ • Units  │  │ Walnut Speaker / Black Liner         │   │
│ • Firm   │  │ Step: CNC Machining                  │   │
│ • Users  │  │ Order: #1234 (John Doe)              │   │
│          │  │ Started: Oct 8, 2025                 │   │
│          │  └──────────────────────────────────────┘   │
│          │  ┌──────────────────────────────────────┐   │
│          │  │ SV-PROD1-00002                       │   │
│          │  │ Maple Speaker / Red Liner            │   │
│          │  │ Step: Laser Engraving                │   │
│          │  │ Inventory (no order)                 │   │
│          │  │ Started: Oct 7, 2025                 │   │
│          │  └──────────────────────────────────────┘   │
│          │  [+ New Production Unit]                    │
└──────────┴──────────────────────────────────────────────┘
```

**QR Code Scanning (Desktop)**
- Focus input field captures QR scanner keyboard input
- Alternatively: Manual "Scan QR" button activates input listener
- On scan: Immediate navigation to unit detail view

**Unit Detail View**
```
┌─────────────────────────────────────────────────────────┐
│  ← Back to Dashboard        [Print Label]  [Scan Next]  │
├─────────────────────────────────────────────────────────┤
│  SV-PROD1-00001                                         │
│  Walnut Speaker / Black Liner                           │
│  Order #1234 - John Doe (Oct 5, 2025)                   │
│                                                          │
│  [QR Code Image]                                        │
│                                                          │
│  Production Steps:                                      │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ✓ 1. Glue Up                                       │ │
│  │   Completed by Alice (Oct 7, 10:30 AM)             │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ✓ 2. CNC Machining       [Open gcode file]        │ │
│  │   Completed by Bob (Oct 7, 2:15 PM)               │ │
│  │   Notes: Used bit #3, no issues                    │ │
│  └───────────────────────────────────────────���────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ○ 3. Laser Engraving     [Open design file]       │ │
│  │   [Mark Complete]                                  │ │
│  └────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────┐ │
│  │ ○ 4. Assembly                                      │ │
│  │   [Mark Complete]                                  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Create Production Unit Flow**
```
Step 1: Select Product
┌─────────────────────────────────────────┐
│ Create New Production Unit              │
├─────────────────────────────────────────┤
│ Select Product:                         │
│ ○ Walnut Speaker                        │
│ ○ Maple Speaker                         │
│                                         │
│            [Cancel]  [Next]             │
└─────────────────────────────────────────┘

Step 2: Select Variant
┌─────────────────────────────────────────┐
│ Create New Production Unit              │
│ Product: Walnut Speaker                 │
├─────────────────────────────────────────┤
│ Select Variant:                         │
│ ○ Black Liner                           │
│ ○ Red Liner                             │
│ ○ Natural Liner                         │
│                                         │
│            [Back]  [Next]               │
└─────────────────────────────────────────┘

Step 3: Associate Order (Optional)
┌─────────────────────────────────────────┐
│ Create New Production Unit              │
│ Product: Walnut Speaker / Black Liner   │
├─────────────────────────────────────────┤
│ Recommended Orders:                     │
│ ┌─────────────────────────────────────┐ │
│ │ Order #1234 - John Doe              │ │
│ │ Oct 5, 2025                         │ │
│ │ [Select This Order]                 │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ Order #1235 - Jane Smith            │ │
│ │ Oct 6, 2025                         │ │
│ │ [Select This Order]                 │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ [Build for Inventory (No Order)]       │
│                                         │
│            [Back]  [Create Unit]        │
└─────────────────────────────────────────┘

Step 4: Confirmation
┌─────────────────────────────────────────┐
│ Production Unit Created!                │
├─────────────────────────────────────────┤
│ Unit ID: SV-PROD1-00003                 │
│                                         │
│ [QR Code Image]                         │
│                                         │
│ [Print Label]  [View Unit]  [Create Another] │
└─────────────────────────────────────────┘
```

#### Mobile Layout (iOS/Android)

**Bottom Navigation Bar**
- Dashboard (production status)
- Scan QR
- Units (list view)
- More (settings, profile, etc.)

**Dashboard View (Mobile)**
```
┌───────────────────────────┐
│  Saturday!         👤     │
├───────────────────────────┤
│                           │
│  Units in Production      │
│                           │
│  ┌─────────────────────┐  │
│  │ SV-PROD1-00001      │  │
│  │ Walnut / Black      │  │
│  │ Step: CNC Machining │  │
│  │ John Doe - #1234    │  │
│  └─────────────────────┘  │
│                           │
│  ┌─────────────────────┐  │
│  │ SV-PROD1-00002      │  │
│  │ Maple / Red         │  │
│  │ Step: Laser Engrave │  │
│  │ Inventory           │  │
│  └─────────────────────┘  │
│                           │
│  [+ New Unit]             │
│                           │
├───────────────────────────┤
│ [Dash] [Scan] [Units] [...] │
└───────────────────────────┘
```

**QR Scan View (Mobile)**
```
┌───────────────────────────┐
│  Scan QR Code      [✕]    │
├───────────────────────────┤
│                           │
│    ┌───────────────┐      │
│    │               │      │
│    │  [Camera      │      │
│    │   Viewfinder] │      │
│    │               │      │
│    └───────────────┘      │
│                           │
│  Position QR code in      │
│  the center to scan       │
│                           │
│                           │
│  [Enter Unit ID Manually] │
│                           │
├───────────────────────────┤
│ [Dash] [Scan] [Units] [...] │
└───────────────────────────┘
```

**Unit Detail View (Mobile)**
```
┌───────────────────────────┐
│  ← SV-PROD1-00001         │
├───────────────────────────┤
│  Walnut Speaker           │
│  Black Liner              │
│  Order #1234 - John Doe   │
│                           │
│  [QR Code]                │
│                           │
│  Production Steps         │
│                           │
│  ✓ Glue Up                │
│    Alice - Oct 7, 10:30a  │
│                           │
│  ✓ CNC Machining          │
│    Bob - Oct 7, 2:15p     │
│    📎 cnc-file.gcode      │
│    💬 "Used bit #3"       │
│                           │
│  ○ Laser Engraving        │
│    📎 laser-design.svg    │
│    [Mark Complete]        │
│                           │
│  ○ Assembly               │
│    [Mark Complete]        │
│                           │
├───────────────────────────┤
│ [Dash] [Scan] [Units] [...] │
└───────────────────────────┘
```

**Mark Step Complete Modal (Mobile)**
```
┌───────────────────────────┐
│  Complete Step            │
│                      [✕]  │
├───────────────────────────┤
│                           │
│  Laser Engraving          │
│  SV-PROD1-00001           │
│                           │
│  Notes (optional):        │
│  ┌─────────────────────┐  │
│  │                     │  │
│  │                     │  │
│  └─────────────────────┘  │
│                           │
│  [Cancel]  [✓ Complete]   │
│                           │
└───────────────────────────┘
```

### Accessibility & Usability

**Production Floor Considerations**
- Large fonts for visibility from standing position
- High contrast colors (especially on QR labels)
- Minimize text entry (use QR scanning, dropdowns, buttons)
- Clear confirmation messages after actions
- Error messages in plain language with suggested fixes

**Accessibility Features**
- Support for system font scaling
- VoiceOver/TalkBack compatibility (for visually impaired users)
- Keyboard navigation support on desktop
- Color contrast ratios meeting WCAG AA standards

## Hardware & Infrastructure Requirements

### Desktop Workstations (macOS)

**Workstation 1: CNC Station**
- macOS device (MacBook Pro or iMac)
- USB thermal label printer (1" x 1" labels)
- USB QR code scanner (keyboard wedge mode)
- gSender software installed (for CNC control)
- Saturday! Admin App installed

**Workstation 2: Laser Station**
- macOS device
- USB QR code scanner
- Laser engraving software installed (specify software name)
- Saturday! Admin App installed

**Workstation 3: Shipping Station**
- macOS device
- USB thermal label printer (shipping labels)
- USB QR code scanner
- Access to Shopify admin (web browser)
- Saturday! Admin App installed

**Workstation 4: Firmware/Electronics Station**
- macOS device
- USB QR code scanner
- esp-idf tools installed (for ESP32 flashing)
- Embedded Linux flashing tools (TBD)
- Saturday! Admin App installed

**Network Requirements**
- Reliable WiFi or Ethernet connection at all workstations
- Internet access for Shopify API and Supabase sync
- Minimum bandwidth: 10 Mbps down / 5 Mbps up (recommended)

### Mobile Devices

**iOS Devices**
- iPhone or iPad running iOS 14.0 or later
- Camera for QR code scanning
- Saturday! Admin App installed (TestFlight initially, then enterprise distribution)

**Android Devices**
- Android phone or tablet running Android 8.0 (Oreo) or later
- Camera for QR code scanning
- Saturday! Admin App installed (internal testing track initially, then enterprise distribution)

**Network Requirements**
- WiFi connectivity throughout production facility
- Mobile data fallback (optional, for outdoor/remote areas)

### Peripherals

**USB QR Code Scanners**
- Must operate in keyboard wedge mode (no special drivers required)
- Recommended models (TBD - specify after testing)
- Configuration: Auto-enter after scan (simulates pressing Enter key)

**Thermal Label Printers**
- 1" x 1" label size support
- USB connectivity
- macOS driver support
- Recommended models (TBD - specify models used in production)

### Backend Infrastructure

**Supabase Project**
- PostgreSQL database (Supabase managed)
- Storage buckets for files and QR codes
- Authentication configured for Google OAuth
- Project URL: (to be created)
- API keys: (to be generated)

**Shopify Store**
- Shopify plan: (specify tier - needs API access)
- GraphQL Admin API access enabled
- API credentials: (to be generated)
- Store URL: (specify store name)

**Domain & Hosting**
- Domain for QR code URLs: e.g., `app.saturdayvinyl.com`
- SSL certificate (required for HTTPS)
- Web hosting for minimal landing page (can use Shopify, Supabase hosting, or separate)

## Development Guidelines

### Project Structure

```
saturday_app/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── app.dart                  # Root app widget
│   ├── config/
│   │   ├── theme.dart            # Brand colors, fonts, theme data
│   │   ├── constants.dart        # App constants (URLs, etc.)
│   │   └── routes.dart           # Route definitions
│   ├── models/
│   │   ├── user.dart
│   │   ├── product.dart
│   │   ├── production_unit.dart
│   │   ├── production_step.dart
│   │   ├── firmware_version.dart
│   │   ├── device_type.dart
│   │   ├── customer.dart
│   │   └── order.dart
│   ├── services/
│   │   ├── auth_service.dart     # Google OAuth, session management
│   │   ├── supabase_service.dart # Supabase client wrapper
│   │   ├── shopify_service.dart  # Shopify GraphQL API client
│   │   ├── qr_service.dart       # QR generation, scanning
│   │   ├── storage_service.dart  # Supabase storage operations
│   │   ├── printer_service.dart  # Thermal label printing
│   │   └── file_launcher_service.dart # Open files in external apps
│   ├── repositories/
│   │   ├── user_repository.dart
│   │   ├── product_repository.dart
│   │   ├── production_repository.dart
│   │   ├── firmware_repository.dart
│   │   └── order_repository.dart
│   ├── providers/              # State management (Riverpod recommended)
│   │   ├── auth_provider.dart
│   │   ├── production_provider.dart
│   │   ├── product_provider.dart
│   │   └── firmware_provider.dart
│   ├── screens/
│   │   ├── auth/
│   │   │   └── login_screen.dart
│   │   ├── dashboard/
│   │   │   └── dashboard_screen.dart
│   │   ├── production/
│   │   │   ├── production_list_screen.dart
│   │   │   ├── unit_detail_screen.dart
│   │   │   └── create_unit_screen.dart
│   │   ├── products/
│   │   │   ├── product_list_screen.dart
│   │   │   └── product_detail_screen.dart
│   │   ├── firmware/
│   │   │   ├── firmware_list_screen.dart
│   │   │   └── firmware_upload_screen.dart
│   │   ├── users/
│   │   │   └── user_management_screen.dart
│   │   └── qr_scan/
│   │       └── qr_scan_screen.dart
│   ├── widgets/
│   │   ├── common/
│   │   │   ├── app_button.dart
│   │   │   ├── app_text_field.dart
│   │   │   └── loading_indicator.dart
│   │   ├── production/
│   │   │   ├── unit_card.dart
│   │   │   ├── step_list_item.dart
│   │   │   └── qr_code_display.dart
│   │   └── navigation/
│   │       ├── sidebar_nav.dart    # Desktop
│   │       └── bottom_nav.dart     # Mobile
│   └── utils/
│       ├── validators.dart
│       ├── formatters.dart
│       └── extensions.dart
├── assets/
│   ├── images/
│   │   ├── saturday-logo.svg
│   │   └── saturday-icon.svg
│   └── fonts/                    # Bevan font files if not using Google Fonts
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
├── pubspec.yaml
└── README.md
```

### State Management

**Recommended: Riverpod**
- Provider-based state management
- Compile-time safety
- Good for both Flutter web and mobile
- Easy testing

**Alternative: Bloc**
- Event-driven architecture
- Clear separation of business logic
- More boilerplate but very structured

**Not Recommended: setState only**
- Too simplistic for this app's complexity

### Key Flutter Packages

**Core Functionality**
- `supabase_flutter: ^2.0.0` - Supabase client
- `google_sign_in: ^6.1.0` - Google OAuth
- `flutter_riverpod: ^2.4.0` - State management (or `flutter_bloc` if preferred)
- `graphql_flutter: ^5.1.0` - Shopify GraphQL client
- `qr_flutter: ^4.1.0` - QR code generation
- `mobile_scanner: ^3.5.0` - QR code scanning (mobile)
- `url_launcher: ^6.2.0` - Launch external apps/files
- `file_picker: ^6.1.0` - File selection for uploads

**Desktop-Specific**
- `window_manager: ^0.3.0` - Desktop window controls
- `printing: ^5.11.0` - Thermal label printing

**UI/UX**
- `google_fonts: ^6.1.0` - Bevan font
- `flutter_svg: ^2.0.0` - SVG logo rendering
- `cached_network_image: ^3.3.0` - Image caching
- `intl: ^0.18.0` - Date/time formatting, localization

**Utilities**
- `uuid: ^4.2.0` - UUID generation
- `dio: ^5.4.0` - HTTP client (for Shopify API)
- `logger: ^2.0.0` - Logging
- `shared_preferences: ^2.2.0` - Local storage

### Code Style & Standards

**Dart Style**
- Follow official Dart style guide: https://dart.dev/guides/language/effective-dart/style
- Use `dart format` for automatic formatting
- Enable linting: Add `flutter_lints: ^3.0.0` to dev_dependencies

**Naming Conventions**
- Classes: PascalCase (`ProductionUnit`, `QRService`)
- Functions/variables: camelCase (`createProductionUnit`, `currentUser`)
- Constants: lowerCamelCase with `k` prefix (`kPrimaryColor`, `kApiTimeout`)
- Private members: prefix with `_` (`_internalMethod`, `_privateVariable`)

**Documentation**
- Document all public APIs with `///` doc comments
- Include usage examples for complex services
- Keep comments up-to-date with code changes

**Error Handling**
- Use try-catch for async operations
- Provide user-friendly error messages
- Log errors for debugging (use `logger` package)
- Never expose technical error details to end users

### Testing Strategy

**Unit Tests**
- Test all service methods (auth, Supabase, Shopify, QR generation)
- Test repository data transformations
- Test business logic in providers
- Coverage goal: >70%

**Widget Tests**
- Test key UI components (buttons, forms, step completion)
- Test navigation flows
- Test state changes in UI
- Coverage goal: >50%

**Integration Tests**
- End-to-end flows: Login → Create Unit → Mark Steps Complete
- QR code scanning workflow
- Shopify sync operations
- File upload and download

**Manual Testing Checklist**
- [ ] Google OAuth login on all platforms (desktop, iOS, Android)
- [ ] QR code generation with logo embedding
- [ ] USB QR scanner input on desktop
- [ ] Camera QR scanning on mobile
- [ ] Thermal label printing (test with actual printer)
- [ ] File launching (gcode in gSender, laser files in laser software)
- [ ] Firmware binary download and external tool launch
- [ ] Shopify product sync (create product in Shopify, verify sync to app)
- [ ] Order sync from Shopify
- [ ] Permission enforcement (try accessing admin features as regular user)
- [ ] Session expiry (wait 1 week or manually expire token)
- [ ] Cross-platform compatibility (macOS, iOS, Android, web)

### Security Best Practices

**Authentication & Authorization**
- Never store passwords (use OAuth only)
- Validate user permissions on every sensitive action
- Use Supabase Row Level Security (RLS) policies
- Implement CSRF protection for web
- Rotate API keys periodically

**Data Protection**
- Use HTTPS for all API calls
- Encrypt sensitive data in transit and at rest (Supabase handles this)
- Validate all user inputs
- Sanitize data before displaying (prevent XSS)
- Use UUIDs for public URLs (not sequential IDs)

**API Security**
- Store API keys in environment variables (not in code)
- Use Supabase anon key for client, service role key only on secure backend (if needed)
- Rate limit API calls to prevent abuse
- Implement proper CORS policies

**File Handling**
- Validate file types and sizes before upload
- Scan uploaded files for malware (if possible)
- Use signed URLs for temporary file access
- Set appropriate file permissions in Supabase storage

### Performance Optimization

**Mobile Performance**
- Lazy load images with `cached_network_image`
- Paginate long lists (production units, firmware versions)
- Debounce search inputs
- Minimize app size (tree-shake unused packages)

**Desktop Performance**
- Optimize for larger screens (responsive layout)
- Cache Shopify data locally (reduce API calls)
- Use isolates for heavy computations (QR generation, file processing)

**Network Optimization**
- Cache Shopify product/order data for offline tolerance
- Retry failed API calls with exponential backoff
- Use GraphQL field selection to minimize payload size
- Compress images before upload

**Database Optimization**
- Create indexes on frequently queried fields (see schema above)
- Use Supabase real-time subscriptions sparingly (only for critical updates)
- Batch database writes when possible

## Deployment & Distribution

### Environment Configuration

**Development Environment**
- Supabase project: `saturday-dev`
- Shopify store: `saturday-dev.myshopify.com` (or test store)
- Domain: `dev.saturdayvinyl.com`

**Production Environment**
- Supabase project: `saturday-prod`
- Shopify store: `saturdayvinyl.myshopify.com` (actual store)
- Domain: `app.saturdayvinyl.com`

**Environment Variables** (stored in `.env` files, not committed to git)
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SHOPIFY_STORE_URL=your-store.myshopify.com
SHOPIFY_ACCESS_TOKEN=your-access-token
GOOGLE_CLIENT_ID=your-google-client-id (for OAuth)
APP_BASE_URL=https://app.saturdayvinyl.com
```

### Desktop (macOS) Deployment

**Build Process**
1. Update version in `pubspec.yaml`
2. Run `flutter build macos --release`
3. Code sign app bundle (Apple Developer account required)
4. Create DMG installer or ZIP archive
5. Upload to internal distribution site or shared drive

**Distribution**
- Manual download from internal URL
- Notarize with Apple (optional but recommended)
- No auto-update for v1 (manual reinstall for updates)

**Installation Instructions**
1. Download `SaturdayAdmin-v1.0.0.dmg`
2. Open DMG and drag app to Applications folder
3. First launch: Right-click → Open (to bypass Gatekeeper if not notarized)
4. Log in with @saturdayvinyl.com Google account

### Mobile (iOS) Deployment

**TestFlight (Internal Testing)**
1. Create App Store Connect app record
2. Configure bundle ID: `com.saturdayvinyl.admin`
3. Build IPA: `flutter build ipa --release`
4. Upload to App Store Connect via Xcode or Transporter
5. Add internal testers in TestFlight
6. Distribute via TestFlight invite links

**Enterprise Distribution** (requires Apple Developer Enterprise Program)
1. Create in-house provisioning profile
2. Build IPA with enterprise profile
3. Upload IPA to internal MDM or distribution site
4. Install via MDM push or installation URL

**Minimum iOS Version**: 14.0

### Mobile (Android) Deployment

**Internal Testing Track (Google Play Console)**
1. Create app in Google Play Console
2. Configure package name: `com.saturdayvinyl.admin`
3. Build APK/AAB: `flutter build appbundle --release`
4. Upload to internal testing track
5. Add tester email addresses
6. Distribute via Play Store internal testing link

**Enterprise Distribution** (via MDM or direct APK)
1. Build APK: `flutter build apk --release`
2. Code sign APK
3. Distribute via MDM or internal download URL

**Minimum Android Version**: 8.0 (API level 26)

### Web (Minimal) Deployment

**Build Process**
1. Configure web base URL in `index.html`
2. Run `flutter build web --release`
3. Deploy `build/web/` directory to hosting provider

**Hosting Options**
- Supabase hosting (static site)
- Netlify/Vercel (automatic deployments from git)
- Shopify app proxy (integrate into Shopify admin)

**Web Functionality (v1)**
- QR code landing page: Show unit ID, product name, "Download our app" CTA
- No admin functionality on web for v1

### Database Migrations

**Initial Setup**
1. Create Supabase project
2. Run SQL schema (provided above) in Supabase SQL editor
3. Set up Row Level Security (RLS) policies:
   - Users table: Readable by authenticated users, writable by admins only
   - Production units: Readable by all authenticated, writable by users with `manage_production` permission
   - Firmware: Readable by all authenticated, writable by users with `manage_firmware` permission
   - Products: Readable by all authenticated, writable by users with `manage_products` permission

**Future Migrations**
- Use Supabase migrations feature or versioned SQL scripts
- Test migrations in dev environment first
- Back up production database before applying migrations

### Monitoring & Logging

**Application Logging**
- Use `logger` package for structured logging
- Log levels: debug, info, warning, error
- Include user ID and timestamp in all logs
- Send error logs to monitoring service (optional: Sentry, Firebase Crashlytics)

**Supabase Monitoring**
- Monitor database performance in Supabase dashboard
- Set up alerts for high error rates or slow queries
- Track storage usage (files, firmware binaries)

**Shopify API Monitoring**
- Track API call usage (Shopify has rate limits)
- Monitor sync job success/failure rates
- Alert on repeated sync failures

## Risk Assessment & Mitigation

### Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Shopify API rate limiting during high-volume sync | High | Medium | Implement exponential backoff, cache data locally, batch requests |
| USB printer compatibility issues on macOS | High | Medium | Test with specific printer models early, provide fallback (manual print) |
| QR code scanning unreliable in poor lighting | Medium | Medium | Use high error correction in QR codes, provide manual ID entry fallback |
| File launching fails for unknown file types | Medium | High | Implement fallback download, document required software installations |
| Google OAuth session expiry disrupts production | Medium | Low | Auto-refresh tokens, clear session expiry warnings, allow quick re-login |
| Supabase storage limits exceeded | Medium | Low | Monitor storage usage, implement file retention policies, compress files |
| Flutter desktop stability issues | High | Low | Use stable Flutter channel, test thoroughly on macOS, have rollback plan |

### Business Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Production floor workers resistant to new system | High | Medium | Involve workers in testing, provide training, emphasize time savings |
| Shopify integration breaks after API changes | High | Low | Monitor Shopify API changelog, use versioned API endpoints, test updates in dev |
| Firmware flashing workflow too complex | Medium | Medium | Simplify UI, provide step-by-step instructions, train technicians |
| QR code labels damaged/illegible in production | Medium | Medium | Use durable label material, laser engrave QR on parts as backup |
| Network outage disrupts always-online app | High | Low | Implement graceful degradation, cache critical data, provide offline mode (future) |

### Compliance & Legal

**Data Privacy**
- No sensitive PII stored (only names, emails from Shopify)
- Comply with GDPR/CCPA if applicable (customer data deletion requests)
- Include privacy policy on web landing page

**Intellectual Property**
- Ensure all third-party assets (fonts, icons) are properly licensed
- Saturday! branding assets owned by company

**Security Compliance**
- Regular security audits (especially before production launch)
- Penetration testing (optional for v1, recommended for future)
- Secure storage of API keys and credentials

## Success Metrics

### Key Performance Indicators (KPIs)

**Adoption Metrics**
- Number of active users (daily/weekly)
- Number of production units created per week
- Percentage of production steps completed via app (vs. manual tracking)

**Efficiency Metrics**
- Average time to create a production unit (target: <2 minutes)
- Average time to complete a production step (scan QR + mark complete, target: <30 seconds)
- Reduction in production errors/rework (compared to previous manual system)

**System Health Metrics**
- App crash rate (target: <1% of sessions)
- API error rate (Shopify, Supabase) (target: <2% of requests)
- Average app load time (target: <3 seconds)

**User Satisfaction**
- User feedback scores (post-launch survey)
- Number of support tickets/issues reported
- Feature requests prioritization

### Success Criteria for MVP Launch

- [ ] All employees can log in successfully with Google accounts
- [ ] QR code generation and printing works reliably on all desktop workstations
- [ ] QR code scanning works on mobile devices and desktop USB scanners
- [ ] Production units can be created and tracked through all steps
- [ ] Shopify products and orders sync correctly
- [ ] Firmware library is functional (upload, view, download)
- [ ] File launching works for CNC gcode and laser designs
- [ ] Thermal labels print correctly with all required information
- [ ] No critical bugs or security vulnerabilities
- [ ] User training completed for all production floor workers
- [ ] Documentation complete (user guide, admin guide, developer docs)

## Timeline & Milestones

**Phase 1: MVP Development** (Estimated: 8-12 weeks for solo developer new to Flutter)

| Week | Milestone | Deliverables |
|------|-----------|--------------|
| 1-2 | Project setup & authentication | Flutter project structure, Supabase integration, Google OAuth working |
| 3-4 | Product & Shopify integration | Product sync from Shopify, product detail views, production step configuration |
| 5-6 | Production unit creation & QR codes | Create unit flow, QR generation with logo, UUID-based URLs |
| 7-8 | QR scanning & step completion | Desktop USB scanner input, mobile camera scanning, mark steps complete |
| 9-10 | Firmware & file management | Firmware upload, file storage, file launching on desktop |
| 11 | Thermal label printing & desktop integrations | Label printing, peripheral testing, production workflow testing |
| 12 | Testing, bug fixes, deployment prep | Integration testing, user acceptance testing, deployment to TestFlight/internal |

**Phase 2: Feedback & Iteration** (Estimated: 2-4 weeks post-launch)
- Monitor usage and collect feedback
- Fix critical bugs
- Iterate on UX based on production floor feedback
- Optimize performance based on real-world usage

**Phase 3: Future Enhancements** (Ongoing)
- Implement deferred features (notifications, advanced reporting, etc.)
- Develop consumer app
- Expand firmware update capabilities
- Build web interface

## Appendices

### Glossary

- **Build-to-Order (BTO)**: Production units created for specific customer orders
- **Build-to-Stock (BTS)**: Production units created for inventory (no assigned order)
- **Device Type**: A category of embedded hardware used in products (e.g., "ESP32 Audio Controller")
- **Firmware**: Software embedded in device hardware
- **Production Step**: A stage in the manufacturing workflow (e.g., CNC machining, QC)
- **Production Unit**: An individual physical product being manufactured, tracked by unique ID and QR code
- **QR Code**: Quick Response code, 2D barcode scanned to identify units
- **Unit ID**: Human-readable identifier (e.g., "SV-PROD1-00001")
- **UUID**: Universally Unique Identifier, used in secure public URLs
- **Variant**: A specific configuration of a product (e.g., walnut wood with black liner)

### Reference Links

**Documentation**
- Flutter: https://docs.flutter.dev/
- Supabase: https://supabase.com/docs
- Shopify GraphQL Admin API: https://shopify.dev/api/admin-graphql
- Google Fonts (Bevan): https://fonts.google.com/specimen/Bevan

**Tools & Services**
- gSender (CNC control): https://sienci.com/gsender/
- esptool (ESP32 flashing): https://github.com/espressif/esptool

**Flutter Packages**
- Riverpod: https://riverpod.dev/
- Supabase Flutter: https://pub.dev/packages/supabase_flutter
- GraphQL Flutter: https://pub.dev/packages/graphql_flutter
- QR Flutter: https://pub.dev/packages/qr_flutter
- Mobile Scanner: https://pub.dev/packages/mobile_scanner

### Contact & Support

**Developer**
- Name: (Your name)
- Email: @saturdayvinyl.com

**Project Repository**
- Location: (Git repository URL, if applicable)

**Issue Tracking**
- Tool: (GitHub Issues, Jira, Linear, etc.)

---

**Document Version**: 1.0
**Last Updated**: October 8, 2025
**Author**: Product Specification compiled from stakeholder interviews
**Status**: Ready for Development
