# Parts Inventory Management

## Overview

Parts Inventory Management enables Saturday to define Bills of Materials (BOMs) for each product, track inventory of parts and raw materials, manage suppliers, and integrate inventory consumption into the production workflow. The system supports barcode scanning for receiving shipments and QR code label printing for organizing storage.

## Goals

1. **Define robust BOMs** for each product, with variant-level overrides for material differences (e.g., walnut vs. oak)
2. **Track inventory levels** with full lifecycle: receive shipments, consume during production, adjust for waste
3. **Auto-deduct inventory** as production steps are completed for a unit
4. **Print parts labels** with QR codes for storage bins and materials (new label format)
5. **Scan supplier barcodes** on incoming packages to auto-match and receive parts into inventory
6. **Import PCB BOMs** from EagleCAD/Fusion exports to reconcile electronic component lists

## Product Context

Saturday builds a few products (e.g., the Crate), each with roughly 10-30 unique parts/materials. Parts span categories like:

- **Wood & raw materials**: board lumber, felt, dowels (measured in board-feet, linear feet, etc.)
- **Electronics**: PCBs, connectors, wiring, components (measured in each/units)
- **Hardware**: screws, fasteners, brackets (measured in each)
- **Batteries & power**: cells, cables (measured in each)

Products are synced from Shopify and have variants (e.g., wood species). Production is tracked through ordered production steps (CNC milling, laser cutting, firmware provisioning, general assembly).

---

## Data Model

### Parts (`parts`)

A part represents a unique material, component, sub-assembly, or supply used in production.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `name` | text | Human-readable name (e.g., "Walnut Board 4/4", "Crate Main PCB") |
| `part_number` | text | Internal Saturday part number (unique) |
| `description` | text | Optional description |
| `part_type` | enum | `raw_material`, `component`, `sub_assembly` (see below) |
| `category` | enum | `wood`, `electronics`, `hardware`, `fastener`, `battery`, `packaging`, `other` |
| `unit_of_measure` | enum | `each`, `board_feet`, `linear_feet`, `meters`, `inches`, `square_feet`, `grams`, `milliliters` |
| `reorder_threshold` | numeric | Low-stock alert threshold (nullable, future use) |
| `is_active` | boolean | Soft delete / archive flag |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**Part types:**
- **`raw_material`** — purchased materials consumed directly in product assembly (lumber, felt, dowels)
- **`component`** — purchased items consumed into sub-assemblies (resistors, capacitors, connectors)
- **`sub_assembly`** — assembled from components, then consumed as a single part in product assembly (PCBs, wiring harnesses). A sub-assembly has its own BOM defined via `sub_assembly_lines`.

### Suppliers (`suppliers`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `name` | text | Supplier name (e.g., "JLCPCB", "Digikey", "Local Lumber Co") |
| `website` | text | Optional URL |
| `notes` | text | Contact info, account numbers, etc. |
| `is_active` | boolean | |
| `created_at` | timestamptz | |

### Supplier Parts (`supplier_parts`)

Maps a part to one or more suppliers with their SKU/part numbers. This is the lookup table for barcode auto-matching.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `part_id` | UUID | FK to `parts` |
| `supplier_id` | UUID | FK to `suppliers` |
| `supplier_sku` | text | Supplier's part number / SKU |
| `barcode_value` | text | Raw barcode string as printed on supplier packaging (nullable) |
| `barcode_format` | text | Barcode symbology if known (e.g., `CODE128`, `DATAMATRIX`, `QR`) |
| `unit_cost` | numeric | Cost per unit-of-measure (nullable, future use) |
| `cost_currency` | text | Currency code, default `USD` |
| `is_preferred` | boolean | Preferred supplier flag |
| `url` | text | Direct link to supplier product page |
| `notes` | text | |

**Unique constraint**: `(part_id, supplier_id, supplier_sku)`

### BOM Lines (`bom_lines`)

Defines the quantity of a part needed to build one unit of a product. Parts are linked at the product level and optionally tagged to a production step.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `product_id` | UUID | FK to `products` |
| `part_id` | UUID | FK to `parts` |
| `production_step_id` | UUID | FK to `production_steps` (nullable — if null, part is product-level) |
| `quantity` | numeric | Quantity needed per unit |
| `notes` | text | Assembly notes, e.g., "cut to 14 inches" |

**Unique constraint**: `(product_id, part_id, production_step_id)` where null step_id is treated as distinct

### BOM Variant Overrides (`bom_variant_overrides`)

Allows a product variant to substitute a different part for a base BOM line. For example, the Walnut variant uses a walnut board while the Oak variant uses an oak board.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `bom_line_id` | UUID | FK to `bom_lines` (the base line being overridden) |
| `variant_id` | UUID | FK to `product_variants` |
| `part_id` | UUID | FK to `parts` (the substitute part) |
| `quantity` | numeric | Override quantity (nullable — if null, use base quantity) |

**Unique constraint**: `(bom_line_id, variant_id)`

### Sub-Assembly Lines (`sub_assembly_lines`)

Defines the components needed to build one unit of a sub-assembly part (e.g., the components on a PCB). This is the sub-assembly's own BOM — distinct from the product-level `bom_lines`.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `parent_part_id` | UUID | FK to `parts` (must be `part_type = sub_assembly`) |
| `child_part_id` | UUID | FK to `parts` (typically a `component`, but could be another `sub_assembly`) |
| `quantity` | numeric | Quantity of child part per one sub-assembly |
| `reference_designator` | text | PCB reference designator, e.g., "R1", "C3", "U2" (nullable, primarily for electronics) |
| `notes` | text | Placement notes, alternatives, etc. |

**Unique constraint**: `(parent_part_id, child_part_id, reference_designator)`

### Inventory Transactions (`inventory_transactions`)

Ledger-style table tracking every change to inventory levels. The current stock for a part is the sum of all its transactions.

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `part_id` | UUID | FK to `parts` |
| `transaction_type` | enum | `receive`, `consume`, `build`, `adjust`, `return` |
| `quantity` | numeric | Positive for additions, negative for consumption |
| `unit_id` | UUID | FK to `units` (nullable — set when consumed during unit production) |
| `step_completion_id` | UUID | FK to `unit_step_completions` (nullable — links to the step that triggered consumption) |
| `supplier_id` | UUID | FK to `suppliers` (nullable — set for receives) |
| `build_batch_id` | UUID | Shared ID linking all transactions in a sub-assembly build batch (nullable) |
| `reference` | text | PO number, packing slip, or note |
| `performed_by` | UUID | FK to auth.users |
| `performed_at` | timestamptz | |

### Inventory View (`inventory_levels` — database view)

A computed view for quick stock lookups:

```sql
SELECT part_id, SUM(quantity) AS quantity_on_hand
FROM inventory_transactions
GROUP BY part_id
```

---

## Key Workflows

### 1. BOM Management

- **View/edit BOM** from the product detail screen — shows all parts needed with quantities
- **Add parts** to BOM: search existing parts or create new ones inline
- **Tag parts to steps**: optionally assign a BOM line to a production step
- **Variant overrides**: on the variant detail, show inherited BOM and allow part substitutions
- **BOM cost estimate**: (future) sum up preferred-supplier unit costs for total BOM cost

### 2. Parts Catalog

- **Parts list screen**: browse/search all parts, filter by category
- **Part detail screen**: name, part number, category, unit of measure, current stock level, suppliers, BOM usage
- **Create/edit parts**: form with all fields
- **Supplier management**: add/edit suppliers, link supplier SKUs to parts

### 3. Receiving Inventory

**Via barcode scan:**
1. User taps "Receive Shipment" and scans the barcode on a supplier package
2. App decodes the barcode and searches `supplier_parts.barcode_value` for a match
3. If matched: shows the part name, supplier, and prompts for quantity received
4. If not matched: shows decoded value, lets user search/select a part and saves the barcode mapping for future scans
5. Transaction recorded as `receive` type

**Via manual entry:**
1. User selects a part from the catalog
2. Enters quantity received, optionally selects supplier and enters reference (PO#)
3. Transaction recorded

### 4. Production Consumption

When an operator completes a production step for a unit:

1. System looks up BOM lines tagged to that step (and untagged lines on the first step)
2. Resolves variant overrides if the unit has a variant
3. Creates `consume` transactions for each part, linked to the unit and step completion
4. If a part is below its reorder threshold after consumption, flags a low-stock warning (v2)

**Pre-production check:**
- Before starting production on a unit, show a BOM availability summary: each part needed, quantity on hand, and whether sufficient stock exists
- Warn (don't block) if any parts are insufficient

### 5. Sub-Assembly Builds

Sub-assemblies (e.g., PCBs) are assembled from components in batches, independent of unit production.

**Build workflow:**
1. User navigates to a sub-assembly part (e.g., "Crate Main PCB") and taps "Build Batch"
2. Enters quantity to build (e.g., 10 PCBs)
3. App shows a pre-build check: lists all child components, quantity needed (per-unit x batch size), and current stock
4. If stock is sufficient, user confirms the build
5. App creates inventory transactions in a single batch (shared `build_batch_id`):
   - One `consume` transaction per child component (negative quantity)
   - One `build` transaction for the sub-assembly itself (positive quantity)
6. The sub-assembly part now has increased stock and is available for consumption in unit production

**Key points:**
- Sub-assembly inventory is tracked the same as any other part — it's just a row in `inventory_levels`
- The product BOM references the sub-assembly part (e.g., "1x Crate Main PCB"), not its individual components
- When a unit production step consumes the sub-assembly, it deducts from the sub-assembly's stock — the child components were already consumed during the build
- Build history is traceable via `build_batch_id` on the transactions

### 6. Label Printing

**Parts label format** (new, distinct from production unit labels):
- QR code encoding: internal part ID (UUID) or a `saturday://part/{part_number}` URI
- Human-readable text: part name, part number, category
- Sized for bin labels (likely larger than production step labels)

**Workflow:**
- From part detail screen, tap "Print Label"
- Select quantity of labels to print
- Labels sent to connected label printer

### 7. EagleCAD BOM Import

Imports a PCB design's BOM into a **sub-assembly part's** component list (`sub_assembly_lines`), not directly into a product BOM.

**Input format:** CSV or XML exported from Autodesk Fusion/EagleCAD containing:
- Part reference designators (R1, C3, U2, etc.)
- Values (10kΩ, 100nF, etc.)
- Package/footprint
- Supplier-specific attributes: `LCSC_PART`, `DIGIKEY_PART`, etc.

**Import workflow:**
1. User navigates to a sub-assembly part (e.g., "Crate Main PCB") and taps "Import EagleCAD BOM"
2. Uploads a BOM file exported from Fusion/EagleCAD
3. App parses the file and presents a reconciliation table:
   - Components that match existing parts (by supplier SKU from `LCSC_PART`, `DIGIKEY_PART` attributes)
   - Components that are new and need to be created as `component` type parts
   - Components where quantities or reference designators changed from last import
4. User confirms, and the app:
   - Creates new `component` parts as needed
   - Creates `supplier_parts` links from the BOM attributes (LCSC, Digikey, etc.)
   - Updates `sub_assembly_lines` for this sub-assembly part
5. Each import is idempotent — re-importing the same BOM results in no changes

### 8. Barcode Scanning

The app needs to handle two scanning scenarios:

**USB barcode scanner (desktop/tablet):**
- Acts as a keyboard wedge — types the barcode value followed by Enter
- App needs a "scan listener" mode on receiving screens that captures this input
- Works with 1D barcodes (Code128, Code39) and 2D (DataMatrix, QR) depending on scanner

**Camera scanning (mobile app):**
- Uses device camera to decode barcodes
- Supports common symbologies: Code128, Code39, EAN-13, UPC-A, DataMatrix, QR
- Supplier-specific formats:
  - **Digikey**: 2D DataMatrix with structured data (part number, quantity, PO)
  - **JLCPCB/LCSC**: typically Code128 or DataMatrix with LCSC part number
  - **Amazon/general**: UPC/EAN barcodes
- App decodes the raw value and searches `supplier_parts` for a match

---

## Units of Measure Reference

| Enum Value | Display | Use Case |
|------------|---------|----------|
| `each` | ea | Discrete items: PCBs, screws, batteries |
| `board_feet` | bd ft | Lumber stock |
| `linear_feet` | lin ft | Trim, felt rolls, wire |
| `meters` | m | Wire, cable |
| `inches` | in | Cut-to-length materials |
| `square_feet` | sq ft | Sheet goods, felt |
| `grams` | g | Solder, adhesive |
| `milliliters` | mL | Finish, glue |

---

## Screen Map

### Desktop (Sidebar Navigation)

The desktop app uses a sidebar (`SidebarNav`) with route-based navigation. A new "Parts & Inventory" section is added to the sidebar.

```
Existing sidebar items:
  Dashboard, Products, Device Types, Capabilities, Units,
  Production Units, Device Communication, Files, Tags, Tag Rolls, ...

New sidebar item: "Parts & Inventory" (route: /parts-inventory)

Parts & Inventory (new top-level nav section)
├── Parts List (default view, with tabs or filters for part_type)
│   ├── Part Detail
│   │   ├── Edit Part
│   │   ├── Supplier Links
│   │   ├── Stock History (transaction log)
│   │   └── Print Label
│   ├── Sub-Assembly Detail (for part_type = sub_assembly)
│   │   ├── Component List (sub_assembly_lines)
│   │   ├── EagleCAD BOM Import
│   │   ├── Build Batch
│   │   └── Build History
│   └── Create Part
├── Suppliers List
│   ├── Supplier Detail / Edit
│   └── Create Supplier
├── Receive Inventory
│   ├── Scan Mode (USB barcode scanner — keyboard wedge listener)
│   └── Manual Entry
└── Inventory Overview (stock levels dashboard)

Product Detail (existing, extended)
├── BOM Tab (new)
│   ├── BOM Line Editor (parts include sub-assemblies like PCBs)
│   └── Resolved BOM View (expands sub-assemblies to show full component tree)
└── Variant Detail (existing, extended)
    └── BOM Overrides
```

### Mobile (Bottom Navigation)

The mobile app uses a `BottomNavigationBar` with an `IndexedStack`. Currently has 3 tabs: **Units** (index 0), **Scan** (index 1, live camera QR scanner), **Profile** (index 2).

The mobile experience is optimized for factory floor use — quick lookups, scanning, and receiving.

**Updated mobile bottom navigation (4 tabs):**

| Index | Icon | Label | Screen | Notes |
|-------|------|-------|--------|-------|
| 0 | `inventory_2` | Units | `ProductionUnitsScreen` | Existing — unchanged |
| 1 | `qr_code_scanner` | Scan | `MobileQRScanTab` | Existing — extended to recognize parts QR codes in addition to unit QR codes |
| 2 | `widgets` | Parts | `MobilePartsScreen` | **New** — mobile-optimized parts & inventory hub |
| 3 | `person` | Profile | `DashboardScreen` | Existing — shifted from index 2 to 3 |

**Mobile Parts screen (`MobilePartsScreen`):**

A mobile-optimized screen with quick-action cards and streamlined views:

```
MobilePartsScreen
├── Quick Actions Bar
│   ├── "Receive" (opens camera barcode scanner for receiving shipments)
│   ├── "Look Up" (search parts by name/number, view stock)
│   └── "Build" (quick-access to sub-assembly build workflow)
├── Low Stock Alerts (if any parts below threshold — v2)
├── Recent Transactions (last few receives/consumes)
└── Navigation to full parts list, suppliers, etc.
```

**Mobile scan tab updates:**
- The existing `MobileQRScanTab` currently scans QR codes to look up units
- Extended to also recognize `saturday://part/{part_number}` QR codes from parts labels
- When a parts QR is scanned: navigate to a mobile part detail view showing stock level, suppliers, and quick-receive action
- When a supplier barcode is scanned (from receiving flow): auto-match and prompt for quantity

**Key files to modify:**
- `lib/screens/main_scaffold.dart` — add Parts tab to mobile `BottomNavigationBar` and `IndexedStack`
- `lib/widgets/navigation/sidebar_nav.dart` — add Parts & Inventory route to desktop sidebar
- `lib/widgets/navigation/mobile_qr_scan_tab.dart` — extend QR decode to handle parts URIs

---

## Implementation Phases

### Phase 1: Data Model & Parts Catalog
- Database migrations for all new tables (`parts`, `suppliers`, `supplier_parts`, `sub_assembly_lines`, `bom_lines`, `bom_variant_overrides`, `inventory_transactions`) and enums (`part_type`, `part_category`, `unit_of_measure`, `transaction_type`)
- `inventory_levels` database view
- RLS policies for all new tables
- Parts CRUD (list, detail, create, edit) with part type support
- Suppliers CRUD
- Supplier-part linking UI

### Phase 2: BOM Management
- Product BOM: `bom_lines` CRUD on product detail screen
- Production step tagging for BOM lines
- Variant override UI (`bom_variant_overrides`)
- Sub-assembly BOM: `sub_assembly_lines` CRUD on sub-assembly part detail
- BOM availability check view (pre-production readiness)
- Resolved BOM view (expands sub-assemblies to show full component tree)

### Phase 3: Inventory Tracking & Sub-Assembly Builds
- Manual receive flow (select part, enter quantity, optional supplier)
- Stock level display on parts list and part detail
- Sub-assembly build batch workflow (check components, confirm, create linked transactions)
- Build history view per sub-assembly
- Production consumption: auto-deduct on step completion (including sub-assembly parts)
- Inventory adjustment and return transactions

### Phase 4: Barcode Scanning & Receiving
- Camera-based barcode scanning (mobile)
- USB barcode scanner input handling (desktop/tablet)
- Barcode auto-match to `supplier_parts`
- Unknown barcode → create mapping flow
- Receive-via-scan workflow

### Phase 5: Labels & Import
- Parts label format design and printing (new label size/layout)
- QR code generation for parts
- EagleCAD BOM file parser (CSV + XML)
- Import reconciliation UI targeting sub-assembly parts
- Idempotent BOM sync from imported files

### Phase 6: Polish & Alerts (v2)
- Low-stock alerts with configurable thresholds
- Inventory dashboard with at-a-glance stock status
- Cost tracking per supplier part
- BOM cost estimation (product-level and sub-assembly-level)
- Reporting / export
