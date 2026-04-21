# Parts Inventory — Implementation Plan

> Reference: [docs/parts_inventory.md](./parts_inventory.md) for full feature spec.

This plan breaks the feature into phases and tasks. Tasks within a phase that can run in parallel are grouped and marked. Each task is scoped for a single agent.

---

## Phase 1: Foundation — Data Model & Parts Catalog

**Goal:** Stand up the database schema and basic CRUD for parts and suppliers on both desktop and mobile.

### Task 1A: Database Migrations & RLS (agent: db-migration)

**Can run in parallel with:** nothing — other Phase 1 tasks depend on this completing first.

Create a single migration file in `shared-supabase/supabase/migrations/` following the `admin_` prefix convention.

**Migration contents:**

1. **Enums:**
   - `part_type`: `raw_material`, `component`, `sub_assembly`
   - `part_category`: `wood`, `electronics`, `hardware`, `fastener`, `battery`, `packaging`, `other`
   - `unit_of_measure`: `each`, `board_feet`, `linear_feet`, `meters`, `inches`, `square_feet`, `grams`, `milliliters`
   - `inventory_transaction_type`: `receive`, `consume`, `build`, `adjust`, `return`

2. **Tables** (with all columns, constraints, indexes as defined in spec):
   - `parts`
   - `suppliers`
   - `supplier_parts` (unique constraint on `part_id, supplier_id, supplier_sku`)
   - `sub_assembly_lines` (unique constraint on `parent_part_id, child_part_id, reference_designator`)
   - `bom_lines` (unique constraint on `product_id, part_id, production_step_id` with COALESCE for null)
   - `bom_variant_overrides` (unique constraint on `bom_line_id, variant_id`)
   - `inventory_transactions`

3. **Views:**
   - `inventory_levels`: `SELECT part_id, SUM(quantity) AS quantity_on_hand FROM inventory_transactions GROUP BY part_id`

4. **RLS Policies:**
   - All tables: authenticated users can SELECT
   - All tables: authenticated users can INSERT, UPDATE, DELETE (admin app is trusted)
   - Follow patterns in `shared-supabase/CLAUDE.md`

5. **Indexes:**
   - `parts.part_number` (unique index)
   - `supplier_parts.barcode_value` (for barcode lookup)
   - `inventory_transactions.part_id` (for stock calculations)
   - `bom_lines.product_id` (for BOM lookups)
   - `sub_assembly_lines.parent_part_id` (for sub-assembly BOM lookups)

**Deliverables:** One idempotent migration file, tested with `supabase db push --workdir shared-supabase --dry-run`.

---

### Task 1B: Dart Models & Providers (agent: flutter-models)

**Can run in parallel with:** Task 1C (navigation) after Task 1A completes.

Create Dart models, repository classes, and Riverpod providers for the new tables.

**Models** (in `lib/models/`):
- `part.dart` — `Part` model with `PartType`, `PartCategory`, `UnitOfMeasure` enums
- `supplier.dart` — `Supplier` model
- `supplier_part.dart` — `SupplierPart` model
- `sub_assembly_line.dart` — `SubAssemblyLine` model
- `bom_line.dart` — `BomLine` model
- `bom_variant_override.dart` — `BomVariantOverride` model
- `inventory_transaction.dart` — `InventoryTransaction` model with `TransactionType` enum

All models should:
- Extend `Equatable`
- Have `fromJson` / `toJson` factory methods matching Supabase column names
- Have `copyWith` methods

**Repositories** (in `lib/repositories/`):
- `parts_repository.dart` — CRUD for parts, with search/filter by category and type
- `suppliers_repository.dart` — CRUD for suppliers
- `supplier_parts_repository.dart` — link/unlink supplier SKUs to parts
- `bom_repository.dart` — CRUD for bom_lines and variant overrides
- `sub_assembly_repository.dart` — CRUD for sub_assembly_lines
- `inventory_repository.dart` — create transactions, fetch inventory levels, fetch transaction history

**Providers** (in `lib/providers/`):
- `parts_provider.dart` — `partsListProvider`, `partDetailProvider(id)`, `partSearchProvider(query)`
- `suppliers_provider.dart` — `suppliersListProvider`, `supplierDetailProvider(id)`
- `bom_provider.dart` — `productBomProvider(productId)`, `resolvedBomProvider(productId, variantId)`
- `sub_assembly_provider.dart` — `subAssemblyLinesProvider(partId)`
- `inventory_provider.dart` — `inventoryLevelProvider(partId)`, `inventoryLevelsProvider`, `transactionHistoryProvider(partId)`

**Deliverables:** All model, repository, and provider files. Must pass `flutter analyze`.

---

### Task 1C: Navigation & Screen Shells (agent: flutter-nav)

**Can run in parallel with:** Task 1B after Task 1A completes.

Wire up navigation for both desktop and mobile. Create placeholder screens that will be filled in by subsequent tasks.

**Desktop sidebar** (`lib/widgets/navigation/sidebar_nav.dart`):
- Add "Parts & Inventory" nav item with route `/parts-inventory` and icon `Icons.widgets`
- Position it after "Tag Rolls" in the sidebar list

**Desktop routing** (`lib/screens/main_scaffold.dart`):
- Add `case '/parts-inventory':` to `_getCurrentScreen()` returning the new `PartsInventoryShell` screen

**Mobile bottom nav** (`lib/screens/main_scaffold.dart`):
- Add Parts tab (index 2) to `BottomNavigationBar` items: icon `Icons.widgets`, label "Parts"
- Shift Profile tab from index 2 to index 3
- Add `MobilePartsScreen` to `IndexedStack` children at index 2
- Update `_mobileTabIndex` references for the shifted Profile tab

**Placeholder screens** (in `lib/screens/parts/`):
- `parts_inventory_shell.dart` — desktop shell with tab bar or sub-navigation for Parts List, Suppliers, Receive, Overview
- `parts_list_screen.dart` — placeholder
- `part_detail_screen.dart` — placeholder
- `part_form_screen.dart` — placeholder (create/edit)
- `suppliers_list_screen.dart` — placeholder
- `supplier_detail_screen.dart` — placeholder
- `supplier_form_screen.dart` — placeholder
- `mobile_parts_screen.dart` — mobile Parts tab placeholder with quick-action cards layout

**Deliverables:** Working navigation on both mobile and desktop. Tapping "Parts & Inventory" shows the shell. Must pass `flutter analyze`.

---

### Task 1D: Parts CRUD UI (agent: flutter-parts-ui)

**Depends on:** Tasks 1B and 1C both complete.

**Cannot run in parallel** with other UI tasks — builds on the shells from 1C and providers from 1B.

Implement full parts catalog UI:

**Parts List Screen** (`parts_list_screen.dart`):
- Searchable list with filter chips for `part_type` and `category`
- Each row shows: name, part number, category icon, part type badge, current stock (from `inventory_levels`)
- Tap to navigate to detail; FAB to create new

**Part Detail Screen** (`part_detail_screen.dart`):
- Header: name, part number, type badge, category
- Stock level card (quantity on hand with unit of measure)
- Suppliers tab: list of linked supplier parts with SKU, preferred flag
- History tab: recent inventory transactions
- Actions: Edit, Print Label (placeholder), Delete (soft — set `is_active = false`)

**Part Form Screen** (`part_form_screen.dart`):
- Create and edit mode
- Fields: name, part number (auto-generate suggestion), description, part type dropdown, category dropdown, unit of measure dropdown
- Validation: name required, part number unique

**Suppliers List & Detail** (`suppliers_list_screen.dart`, `supplier_detail_screen.dart`, `supplier_form_screen.dart`):
- Simple CRUD — name, website, notes
- Supplier detail shows all parts sourced from this supplier

**Supplier-Part Linking** (on part detail screen):
- "Add Supplier" button → dialog to select supplier, enter SKU, barcode value, URL
- Edit/remove existing supplier links

**Mobile Parts Screen** (`mobile_parts_screen.dart`):
- Quick action cards: "Receive", "Look Up", "Build" (Build placeholder for Phase 3)
- "Look Up" opens a search-first parts list optimized for mobile
- Parts list reuses same provider, but with a mobile-optimized layout (larger tap targets, less detail per row)

**Deliverables:** Fully functional parts and suppliers CRUD on desktop and mobile. Must pass `flutter analyze`.

---

## Phase 2: BOM Management

**Goal:** Define what parts are needed to build each product and sub-assembly.

### Task 2A: Product BOM UI (agent: flutter-bom)

**Can run in parallel with:** Task 2B.

Add a BOM tab to the existing product detail screen.

**Product Detail — BOM Tab:**
- Add a new tab to `ProductDetailScreen` (or a new section below existing content)
- Lists all `bom_lines` for this product: part name, quantity, unit of measure, tagged step (if any)
- "Add Part to BOM" button → search/select a part, enter quantity, optionally select a production step
- Edit quantity / step assignment inline or via dialog
- Remove BOM line with confirmation
- Variant overrides section: for each variant, show inherited BOM and allow part substitutions
  - "Override" button on a BOM line → select substitute part and/or override quantity
  - Visual indicator on lines that have variant overrides

**BOM Availability Check:**
- "Check Availability" button shows a modal/card: for each BOM line, current stock vs. needed quantity
- Green/red indicators for sufficient/insufficient stock
- This is a read-only view — just informational

**Deliverables:** BOM management UI on product detail screen. Desktop-focused (product editing is a desktop task).

---

### Task 2B: Sub-Assembly BOM UI (agent: flutter-subassembly)

**Can run in parallel with:** Task 2A.

Extend the part detail screen for sub-assembly type parts.

**Sub-Assembly Detail (when `part_type == sub_assembly`):**
- Show a "Components" section/tab listing all `sub_assembly_lines`
- Each row: child part name, quantity, reference designator (if set)
- "Add Component" → search/select a part, enter quantity and optional reference designator
- Edit/remove component lines
- Summary card: total unique components, total component count

**Resolved BOM View** (on product detail BOM tab):
- When a BOM line references a sub-assembly part, show an expand/collapse to reveal its components
- Read-only — just for visibility into what's actually consumed at the component level

**Deliverables:** Sub-assembly component management on part detail, resolved BOM expansion on product detail.

---

## Phase 3: Inventory Tracking & Sub-Assembly Builds

**Goal:** Track stock levels, receive parts, consume during production, build sub-assemblies.

### Task 3A: Inventory Receive & Adjust (agent: flutter-inventory-receive)

**Can run in parallel with:** Task 3B.

**Manual Receive Flow:**
- "Receive Inventory" screen accessible from Parts & Inventory nav
- Select a part (search), enter quantity, optionally select supplier, enter reference (PO#, packing slip)
- Creates an `inventory_transactions` record with type `receive`
- Confirmation with updated stock level shown

**Inventory Adjustments:**
- On part detail screen, "Adjust Stock" action
- Enter adjustment quantity (positive or negative) with a reason/reference note
- Creates `adjust` type transaction

**Stock Display:**
- Parts list shows current stock level per part (from `inventory_levels` view)
- Part detail shows prominent stock card
- Color coding: green (above reorder threshold), yellow (at/near threshold), red (zero/below)

**Transaction History:**
- On part detail, "History" tab shows all transactions for that part
- Each row: date, type badge, quantity (+/-), reference, who performed it
- Sortable by date

**Deliverables:** Manual receive, adjust, stock display, and history. Desktop and mobile (mobile receive is the "Receive" quick action on `MobilePartsScreen`).

---

### Task 3B: Sub-Assembly Build Workflow (agent: flutter-build)

**Can run in parallel with:** Task 3A.

**Build Batch Screen** (from sub-assembly part detail → "Build Batch"):
1. Enter quantity to build
2. App calculates required components: `sub_assembly_lines.quantity * build_qty` for each child part
3. Pre-build check table: component name, needed qty, on-hand qty, sufficient (yes/no)
4. If any component insufficient: warning but don't block (allow building partial if user confirms)
5. "Confirm Build" creates transactions in a single batch:
   - One `consume` transaction per child component (negative quantity, shared `build_batch_id`)
   - One `build` transaction for the sub-assembly (positive quantity, same `build_batch_id`)
6. Success screen with updated sub-assembly stock level

**Build History:**
- On sub-assembly detail, "Build History" section
- Groups transactions by `build_batch_id`
- Each build shows: date, quantity built, who performed it

**Mobile Build:**
- The "Build" quick action on `MobilePartsScreen` → select a sub-assembly → build batch flow
- Same workflow, mobile-optimized layout

**Deliverables:** Sub-assembly build workflow on desktop and mobile.

---

### Task 3C: Production Consumption Integration (agent: flutter-consumption)

**Depends on:** Tasks 3A and 3B complete (needs inventory transaction infrastructure).

**Cannot run in parallel** — modifies existing production step completion flow.

**Auto-deduct on step completion:**
- Modify the existing step completion flow (in `complete_step_screen.dart` or related)
- When a step is completed for a unit:
  1. Look up `bom_lines` where `production_step_id` matches the completed step
  2. For the first step of a product, also include `bom_lines` with null `production_step_id`
  3. Resolve variant overrides if the unit has a `variant_id`
  4. Create `consume` transactions for each resolved BOM line, linked to the `unit_id` and `step_completion_id`
- Show a consumption summary after step completion: what parts were deducted
- If any part has insufficient stock: warn but don't block step completion

**Pre-production check on unit creation:**
- When creating a new unit (or starting production), show BOM availability summary
- Expand sub-assembly parts to check their stock too
- Warning-only — don't block unit creation

**Deliverables:** Automated inventory consumption tied to production steps.

---

## Phase 4: Barcode Scanning & Receiving

**Goal:** Scan supplier barcodes to quickly receive inventory.

### Task 4A: Barcode Scanning Infrastructure (agent: flutter-barcode)

**Can run in parallel with:** nothing in Phase 4 — Tasks 4B depends on this.

**Camera barcode scanner widget:**
- Create a reusable `BarcodeScannerWidget` that can decode multiple symbologies
- Use an existing Flutter barcode scanning package (e.g., `mobile_scanner` or `flutter_barcode_scanner`)
- Support: Code128, Code39, EAN-13, UPC-A, DataMatrix, QR
- Return decoded value and detected format

**USB barcode scanner input handler:**
- Create a `KeyboardWedgeListener` widget that captures rapid keyboard input ending with Enter
- Distinguishes scanner input from normal typing by timing (scanner inputs arrive in rapid succession)
- Wraps a screen and calls an `onScan(String value)` callback

**Supplier barcode matching service** (`lib/services/barcode_matcher_service.dart`):
- Takes a raw barcode string
- Searches `supplier_parts.barcode_value` for exact match
- If no exact match, tries parsing structured formats:
  - Digikey DataMatrix: parse to extract Digikey part number, search `supplier_parts.supplier_sku`
  - LCSC: extract LCSC part number pattern (`C\d+`), search
- Returns: matched `SupplierPart` + `Part`, or null if no match

**Deliverables:** Reusable scanner widgets and matching service.

---

### Task 4B: Receive-via-Scan Workflow (agent: flutter-scan-receive)

**Depends on:** Task 4A complete.

**Scan Receive Screen:**
- Accessible from "Receive Inventory" → "Scan Mode" (desktop) or "Receive" quick action (mobile)
- Desktop: shows `KeyboardWedgeListener` with a "Ready to scan..." prompt
- Mobile: shows camera viewfinder via `BarcodeScannerWidget`
- On scan:
  1. Run barcode through `BarcodeMatcherService`
  2. If matched: show part name, supplier, current stock → prompt for quantity → create `receive` transaction
  3. If not matched: show raw barcode value → let user search/select a part → save new `supplier_parts` record with the barcode → then proceed with receive
- Support continuous scanning: after one receive completes, ready for next scan immediately
- Running total of items received in this session

**Mobile QR scan tab extension** (`mobile_qr_scan_tab.dart`):
- Currently only handles unit QR codes
- Extend to detect `saturday://part/{part_number}` URI scheme
- When parts QR detected: navigate to mobile part detail with stock info and quick-receive action

**Deliverables:** Scan-to-receive workflow on desktop and mobile, extended QR tab.

---

## Phase 5: Labels & EagleCAD Import

**Goal:** Print parts labels and import PCB BOMs.

### Task 5A: Parts Label Printing (agent: flutter-labels)

**Can run in parallel with:** Task 5B.

**Label format design:**
- New label template distinct from production unit labels
- Content: QR code (`saturday://part/{part_number}`), part name, part number, category
- Determine label size based on available label stock (coordinate with existing label printing infrastructure)

**Print workflow:**
- Part detail screen → "Print Label" action
- Dialog: select quantity of labels
- Generate QR code image, compose label layout
- Send to connected label printer (follow patterns from existing `label_printing.md`)

**Mobile print support:**
- Same flow accessible from mobile part detail

**Deliverables:** Parts label printing on desktop and mobile.

---

### Task 5B: EagleCAD BOM Import (agent: flutter-import)

**Can run in parallel with:** Task 5A.

**BOM File Parser** (`lib/services/eaglecad_bom_parser.dart`):
- Parse CSV format (most common EagleCAD export): columns for Part, Value, Package, reference designators, and custom attributes
- Parse XML format (EagleCAD native): extract `<part>` elements with attributes
- Extract supplier-specific attributes: `LCSC_PART`, `DIGIKEY_PART`, etc.
- Output: list of `ParsedBomEntry` objects with: reference designator, value, package, supplier parts map, quantity

**Import Reconciliation UI** (on sub-assembly part detail → "Import EagleCAD BOM"):
1. File upload (or paste CSV content)
2. Parse and display reconciliation table:
   - **Matched**: component found in inventory by supplier SKU → show match, quantity delta
   - **New**: component not found → will be created as `component` type part
   - **Changed**: quantity or designator changed from existing `sub_assembly_lines`
   - **Removed**: existing lines not in new BOM → will be removed
3. User reviews and confirms
4. App executes:
   - Creates new `parts` (type `component`) as needed
   - Creates `supplier_parts` links from BOM attributes
   - Upserts `sub_assembly_lines` for the sub-assembly
   - Removes lines no longer in the BOM
5. Idempotent: re-importing same file results in "no changes" state

**Deliverables:** BOM parser and import reconciliation UI on sub-assembly part detail (desktop).

---

## Phase 6: Polish & Alerts (v2)

**Goal:** Quality-of-life improvements and operational alerts.

### Task 6A: Low Stock Alerts & Dashboard (agent: flutter-alerts)

**Can run in parallel with:** Task 6B.

- Inventory overview dashboard on Parts & Inventory landing screen
- At-a-glance: total parts count, low-stock count, recent transactions
- Low-stock alerts: parts where `quantity_on_hand <= reorder_threshold`
- Alert badges on Parts nav item (desktop sidebar and mobile tab)
- Mobile: low-stock section on `MobilePartsScreen` home

### Task 6B: Cost Tracking & Reporting (agent: flutter-costs)

**Can run in parallel with:** Task 6A.

- `unit_cost` and `cost_currency` fields on `supplier_parts` become editable
- BOM cost calculation: sum of `quantity * preferred_supplier.unit_cost` for all lines
- Sub-assembly cost: sum of component costs
- Product total cost: sum of all BOM line costs (including sub-assemblies)
- Cost display on product BOM tab and sub-assembly detail
- Basic export: CSV download of parts list with stock levels and costs

---

## Parallelism Summary

```
Phase 1:
  1A (db migration) ──────────────────┐
                                      ├──→ 1B (models/providers) ──┐
                                      ├──→ 1C (navigation/shells) ─┤
                                      │                            └──→ 1D (parts CRUD UI)
                                      │
Phase 2 (after 1D):
  2A (product BOM UI) ─────────────── parallel ── 2B (sub-assembly BOM UI)

Phase 3 (after 2A + 2B):
  3A (receive & adjust) ────────────── parallel ── 3B (sub-assembly builds)
                                      │
                                      └──→ 3C (production consumption)

Phase 4 (after 3C):
  4A (barcode infrastructure) ────────→ 4B (scan-receive workflow)

Phase 5 (after Phase 3, parallel with Phase 4):
  5A (label printing) ─────────────── parallel ── 5B (EagleCAD import)

Phase 6 (after all above):
  6A (alerts & dashboard) ──────────── parallel ── 6B (cost tracking)
```

**Maximum parallel agents at any point:** 2 (during 1B+1C, 2A+2B, 3A+3B, 5A+5B, 6A+6B)

---

## Key Integration Points

These are places where new code touches existing code — agents working on these tasks should be aware of the existing patterns:

| Existing File | Modification | Phase |
|---------------|-------------|-------|
| `lib/screens/main_scaffold.dart` | Add mobile Parts tab, desktop route | 1C |
| `lib/widgets/navigation/sidebar_nav.dart` | Add Parts & Inventory nav item | 1C |
| `lib/widgets/navigation/mobile_qr_scan_tab.dart` | Handle parts QR URI scheme | 4B |
| `lib/screens/products/product_detail_screen.dart` | Add BOM tab | 2A |
| `lib/screens/production/complete_step_screen.dart` | Auto-deduct inventory on step completion | 3C |
| `lib/screens/production/create_unit_screen.dart` | Pre-production BOM availability check | 3C |
