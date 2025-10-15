# Prompt Plan: Machine Control Enhancements

## Overview
This document outlines the implementation plan for enhancing the machine control interface with macros, unit details display, and gcode visualization features. These enhancements build upon the existing machine control system implemented in Prompts 36-41.

**Related Documentation:**
- [Machine Control Feature](docs/MACHINE_CONTROL_FEATURE.md)
- [Production Steps Implementation](prompt_plan_production_steps.md)

---

## Prompt 42: Macro System - Database Schema & Models

**Objective:** Create the database schema and data models for machine-specific gcode macros.

**Tasks:**
1. Create database migration `011_machine_macros.sql`:
   - Create `machine_macros` table with columns:
     - `id` (UUID, primary key)
     - `name` (TEXT, required) - Display name for the macro
     - `description` (TEXT, nullable) - Tooltip text shown on hover
     - `machine_type` (TEXT, required) - 'cnc' or 'laser'
     - `icon_name` (TEXT, required) - Material Icon name (e.g., 'home', 'play_arrow')
     - `gcode_commands` (TEXT, required) - Multi-line gcode commands to execute
     - `execution_order` (INTEGER, default 1) - Display order in the UI
     - `is_active` (BOOLEAN, default true) - Whether macro is enabled
     - `created_at` (TIMESTAMP WITH TIME ZONE)
     - `updated_at` (TIMESTAMP WITH TIME ZONE)
   - Add constraint to validate machine_type is 'cnc' or 'laser'
   - Add constraint for positive execution_order
   - Create index on `machine_type` and `is_active` for efficient queries
   - Add RLS policies for authenticated users

2. Create `lib/models/machine_macro.dart`:
   - Define `MachineMacro` class extending Equatable
   - Include all fields from database schema
   - Add `fromJson()` and `toJson()` methods
   - Add `copyWith()` method
   - Add validation method to ensure gcode_commands is not empty
   - Add `getIconData()` helper method to convert icon_name string to IconData

3. Test the migration:
   - Apply migration to local Supabase instance
   - Insert sample macros for both CNC and Laser types
   - Verify constraints and RLS policies work correctly

**Expected Outcome:**
- Database table created and tested
- Model class ready for use in repositories and providers
- Sample macros available for testing

---

## Prompt 43: Macro System - Repository & Provider

**Objective:** Implement data access layer and state management for machine macros.

**Tasks:**
1. Create `lib/repositories/machine_macro_repository.dart`:
   - Implement `MachineMacroRepository` class
   - Add methods:
     - `Future<List<MachineMacro>> getMacrosByMachineType(String machineType)` - Fetch active macros for a machine type, ordered by execution_order
     - `Future<List<MachineMacro>> getAllMacros()` - Fetch all macros (for settings screen)
     - `Future<MachineMacro> getMacroById(String id)` - Fetch single macro
     - `Future<MachineMacro> createMacro(MachineMacro macro)` - Create new macro
     - `Future<MachineMacro> updateMacro(MachineMacro macro)` - Update existing macro
     - `Future<void> deleteMacro(String id)` - Delete macro
     - `Future<void> reorderMacros(String machineType, List<String> macroIds)` - Update execution_order for multiple macros
   - Use Supabase client for all database operations
   - Include proper error handling

2. Create `lib/providers/machine_macro_provider.dart`:
   - Create `macroRepositoryProvider` - Provider for MachineMacroRepository
   - Create `cncMacrosProvider` - FutureProvider for CNC macros
   - Create `laserMacrosProvider` - FutureProvider for Laser macros
   - Create `allMacrosProvider` - FutureProvider for all macros (settings screen)
   - All providers should handle loading states and errors appropriately

3. Add seed data (optional script or manual SQL):
   - Create sample macros for CNC:
     - "Spindle On" - M3 S12000
     - "Spindle Off" - M5
     - "Coolant On" - M8
     - "Coolant Off" - M9
   - Create sample macros for Laser:
     - "Laser Test Fire" - M3 S10 (10% power) / G4 P0.5 (pause 0.5s) / M5
     - "Air Assist On" - M7
     - "Air Assist Off" - M9

**Expected Outcome:**
- Repository and providers ready to use in UI
- Sample macros available for testing the UI implementation

---

## Prompt 44: Macro System - Settings Screen UI

**Objective:** Build the settings screen interface for managing machine macros.

**Tasks:**
1. Update `lib/screens/settings/settings_screen.dart`:
   - Add "Machine Macros" navigation option to the settings menu
   - Create route to the new macro management screen

2. Create `lib/screens/settings/machine_macros_settings_screen.dart`:
   - Build screen with tabs for CNC and Laser macros
   - Display list of macros for selected machine type
   - Show macro cards with:
     - Icon preview
     - Name
     - Description (truncated if long)
     - Edit and Delete buttons
     - Drag handle for reordering
   - Implement reorderable list using `ReorderableListView`
   - Add FAB (Floating Action Button) to create new macro
   - Include empty state message when no macros exist

3. Create `lib/screens/settings/machine_macro_form_screen.dart`:
   - Build form for creating/editing macros
   - Form fields:
     - Name (required, text field)
     - Description (optional, multi-line text field)
     - Machine Type (required, dropdown: CNC or Laser)
     - Icon (required, icon picker widget)
     - Gcode Commands (required, multi-line text field with monospace font)
   - Add form validation
   - Save button to create or update macro
   - Cancel button to go back
   - Delete button (when editing existing macro)

4. Create `lib/widgets/settings/icon_picker_widget.dart`:
   - Build a simple icon picker dialog
   - Display grid of common Material Icons suitable for machine operations:
     - home, play_arrow, pause, stop, power, power_off
     - settings, build, construction, handyman
     - flash_on, flash_off, opacity, air
     - refresh, cached, rotate_right, rotate_left
     - arrow_upward, arrow_downward, arrow_forward, arrow_back
     - add, remove, check, clear
   - Allow user to select one icon
   - Show selected icon name

**Expected Outcome:**
- Complete settings interface for managing macros
- Users can create, edit, delete, and reorder macros
- Icon picker provides intuitive icon selection

---

## Prompt 45: Macro System - Machine Control Integration

**Objective:** Integrate macros into the machine control screen with execution capability.

**Tasks:**
1. Update `lib/screens/production/machine_control_screen.dart`:
   - Add new section "Quick Macros" between "Machine Controls" and "Execution Queue"
   - Fetch macros based on current machine type (CNC or Laser)
   - Display macros as horizontal scrollable row of buttons
   - Each macro button shows:
     - Icon (from macro.icon_name)
     - Name below icon
     - Tooltip on hover with description
   - Buttons only enabled when `_canExecute()` returns true (machine idle, not streaming)
   - Implement `_executeMacro(MachineMacro macro)` method:
     - Parse gcode_commands (split by lines, trim whitespace)
     - Send each command to machine using `_machine.sendCommand()`
     - Show loading indicator during execution
     - Display success/error snackbar after completion
     - Do not use streaming service (these are quick commands)

2. Style the macro buttons:
   - Use elevated buttons or outlined buttons (consistent with existing UI)
   - Use Saturday theme colors
   - Add padding and spacing for visual clarity
   - Ensure icons are clearly visible
   - Show disabled state when machine is not ready

3. Handle edge cases:
   - Empty gcode_commands (should not happen due to validation, but handle gracefully)
   - Commands that fail to execute
   - Machine disconnects during macro execution

**Expected Outcome:**
- Macros appear in machine control screen
- Workers can execute macros with a single click
- Execution feedback is clear and immediate
- System handles errors gracefully

---

## Prompt 46: Jog Controls with Continuous Movement

**Objective:** Add machine jog controls with adjustable step sizes and continuous movement capability.

**Tasks:**
1. Update `lib/screens/production/machine_control_screen.dart` - Add jog controls to Machine Controls section:
   - Add state variable `JogMode _jogMode` with enum values: `rapid` (10mm), `normal` (2mm), `precise` (0.5mm)
   - Create `_buildJogControlsSection()` method or extend existing `_buildMachineControlsSection()`
   - Add jog mode toggle (SegmentedButton or similar):
     - Three options: "Rapid (10mm)", "Normal (2mm)", "Precise (0.5mm)"
     - Display current mode prominently
     - Only enabled when machine is idle

2. Implement jog button UI:
   - Create 6 directional jog buttons arranged logically:
     - X-axis: +X (right), -X (left)
     - Y-axis: +Y (forward), -Y (back)
     - Z-axis: +Z (up), -Z (down)
   - Use GestureDetector with `onLongPressStart`, `onLongPressEnd` for continuous jogging
   - Or use InkWell/Material button with appropriate callbacks
   - Display direction labels clearly (e.g., "X+", "X-", "Y+", "Y-", "Z+", "Z-")
   - Style buttons with directional arrows or icons
   - Buttons only enabled when `_canExecute()` returns true

3. Implement continuous jog streaming logic:
   - Create `_startJogging(String axis, bool positive)` method:
     - Calculate jog distance based on current `_jogMode`
     - Generate appropriate gcode command: `G91 G0 X[distance]` (for +X example)
     - Use `G91` for relative positioning mode
     - Use `G0` for rapid moves or `G1` for controlled moves
   - Create `_stopJogging()` method:
     - Stop sending jog commands
     - Send feed hold command (`!`) to grbl if still moving
     - Reset to absolute positioning mode with `G90`

4. Implement continuous command streaming on button hold:
   - When button is pressed (onLongPressStart):
     - Start a Timer that repeatedly sends jog commands
     - Send command every 100-200ms (adjust based on testing)
     - Wait for "ok" response before sending next command
     - Track if machine is responding
   - When button is released (onLongPressEnd):
     - Cancel the Timer
     - Stop jogging immediately
     - Optionally send feed hold to stop motion
   - Handle quick taps (onTap) as single jog increments

5. Safety and error handling:
   - Disable jog controls if machine is not idle
   - Show error if machine doesn't respond to jog commands
   - Implement timeout for jog command acknowledgments
   - Add visual feedback (button highlighting) while jogging
   - Ensure only one jog direction can be active at a time
   - Handle machine disconnection during jogging

6. UI Layout:
   - Arrange jog controls in an intuitive grid:
     ```
     Mode: [Rapid | Normal | Precise]

           Y+
       X-  ⊕  X+
           Y-

       Z+      Z-
     ```
   - Use appropriate spacing and sizing for easy clicking
   - Add labels or tooltips to clarify directions

**Expected Outcome:**
- Workers can jog machine in all three axes
- Jog step size is easily adjustable
- Holding button down continuously jogs the machine
- Jogging stops immediately when button is released
- UI is intuitive and safe to operate

---

## Prompt 47: Unit Details Display Enhancement

**Objective:** Display production unit details and reformat the execution queue display.

**Tasks:**
1. Update `lib/screens/production/machine_control_screen.dart`:
   - Add method to fetch product and variant information:
     - Use existing providers to fetch Product by productId
     - Use existing providers to fetch ProductVariant by variantId
     - Store in local state variables
   - Create `_buildUnitDetailsSection()` method:
     - Create Card widget with "Unit Information" header
     - Display the following information in a clean layout:
       - Unit ID (e.g., "SV-PROD1-00001")
       - Product Name (from Product model)
       - Variant Name (from ProductVariant.getFormattedVariantName())
       - SKU (from ProductVariant model)
       - Order Number (from ProductionUnit.shopifyOrderNumber, if available)
     - Use a two-column layout for labels and values
     - Style with appropriate typography and spacing
   - Add this section after the machine status section, before machine controls

2. Update `_buildGCodeFilesSection()`:
   - Reorder the ListTile content in the execution queue:
     - **title**: Display `file.description` (if available, otherwise file.fileName)
     - **subtitle**: Display `file.fileName` in a smaller, grayed-out font
   - If description is null, show fileName as title with no subtitle
   - Ensure the numbered badge/checkmark still appears on the left
   - Keep "Run" button on the right unchanged

3. Style the unit details section:
   - Use consistent theming with other sections
   - Ensure text is readable and well-spaced
   - Handle cases where order number is null (show "N/A" or hide the row)
   - Add subtle divider or spacing between label/value pairs

**Expected Outcome:**
- Workers can see critical unit information at a glance
- Execution queue prioritizes description over filename
- UI is clean, organized, and follows existing design patterns

---

## Prompt 48: GCode Visualization - Library Integration

**Objective:** Integrate the gcode_view library (or alternative) for visualizing gcode tool paths.

**Tasks:**
1. Research and add gcode visualization library:
   - Investigate `gcode_view` package (https://github.com/havenS/gcode_view)
   - Check if package is maintained and compatible with current Flutter version
   - If not suitable, research alternatives:
     - `flutter_3d_obj` for 3D rendering
     - Custom canvas-based solution
     - WebView with JavaScript gcode viewer (e.g., nc-viewer)
   - Add chosen package to `pubspec.yaml`
   - Run `flutter pub get`

2. Create `lib/widgets/production/gcode_viewer_widget.dart`:
   - Build widget that accepts gcode string as input
   - Integrate the visualization library
   - Provide basic controls:
     - Zoom in/out buttons (if library doesn't provide built-in controls)
     - Reset view button
     - Toggle 3D/2D view (if supported)
   - Show loading indicator while parsing gcode
   - Handle errors gracefully (invalid gcode, parsing failures)
   - Display file information (line count, estimated bounds if available)

3. Test the widget with sample gcode:
   - Create a test screen or dialog to preview the widget
   - Test with both simple gcode (basic moves) and complex gcode (real files)
   - Test with QR engraving gcode (generated by ImageToGCodeService)
   - Verify performance with large files (1000+ lines)
   - Ensure widget is responsive and doesn't block UI thread

**Expected Outcome:**
- Gcode visualization library successfully integrated
- Widget can display gcode tool paths visually
- Performance is acceptable for typical gcode files

---

## Prompt 49: GCode Visualization - Machine Control Integration

**Objective:** Integrate gcode preview into machine control screen with split-screen layout.

**Tasks:**
1. Update `lib/screens/production/machine_control_screen.dart`:
   - Change layout from single column to row-based split layout
   - **Left side** (fixed width or 40% of screen):
     - Machine status section
     - Unit details section
     - Machine controls section
     - Quick macros section
     - Execution queue section
     - Navigation buttons
   - **Right side** (flexible or 60% of screen):
     - Initially empty with placeholder text: "Select a gcode file to preview"
     - When file is selected for execution, show gcode preview
   - Wrap left side in `SingleChildScrollView` for scrolling
   - Right side should be a separate scrollable area (or fixed if preview handles its own scrolling)

2. Update execution flow for gcode files:
   - When user clicks "Run" on a gcode file:
     - Fetch gcode content from GitHub (as before)
     - **NEW:** Display gcode preview on right side using `GCodeViewerWidget`
     - Show confirmation dialog: "Ready to execute [filename]?"
       - "Start Execution" button (primary)
       - "Cancel" button
     - If confirmed, begin streaming to machine
     - During streaming, keep preview visible with progress overlay
     - After completion, keep preview visible with "Completed" overlay

3. Update execution flow for QR engraving:
   - When user clicks "Run Engrave":
     - Generate QR gcode (as before)
     - **NEW:** Display QR gcode preview on right side
     - Show confirmation dialog: "Ready to engrave QR code?"
       - "Start Engraving" button (primary)
       - "Cancel" button
     - If confirmed, begin streaming to machine
     - During streaming, show progress overlay on preview
     - After completion, show "Completed" overlay

4. Add state management for preview:
   - Add `String? _currentGCodePreview` state variable
   - Add `String? _currentPreviewFileName` state variable
   - Update state when file/QR is selected
   - Clear state when execution completes or is cancelled

5. Handle responsive layout:
   - Use `LayoutBuilder` to adjust split ratio based on screen width
   - Ensure minimum width for left side (e.g., 400px)
   - On very narrow screens (unlikely for desktop), consider stacking vertically

**Expected Outcome:**
- Machine control screen has split layout
- Workers can preview gcode before execution
- Confirmation dialog prevents accidental execution
- Progress is visible during execution
- UI remains responsive and intuitive

---

## Prompt 50: Testing & Polish

**Objective:** Test all new features, fix bugs, and polish the UI.

**Tasks:**
1. End-to-end testing of macro system:
   - Create macros in settings screen for both CNC and Laser
   - Edit existing macros (change name, icon, gcode)
   - Delete macros
   - Reorder macros
   - Execute macros in machine control screen
   - Verify commands are sent correctly to machine
   - Test with invalid gcode in macros

2. End-to-end testing of unit details display:
   - Open machine control for units with order numbers
   - Open machine control for units without order numbers
   - Verify product and variant names display correctly
   - Test with various product/variant combinations

3. End-to-end testing of gcode visualization:
   - Preview various gcode files before execution
   - Preview QR engraving gcode
   - Test zoom and pan controls (if available)
   - Test with very large gcode files (performance)
   - Test with malformed gcode (error handling)
   - Cancel execution after preview

4. End-to-end testing of jog controls:
   - Test jogging in all three axes and both directions
   - Test mode switching between Rapid, Normal, and Precise
   - Test continuous jogging (hold button down)
   - Test single-step jogging (quick tap)
   - Verify jogging stops immediately on button release
   - Test jogging near machine limits (if applicable)
   - Test with CNC and Laser machines

5. Integration testing:
   - Test complete workflow: connect machine → jog to position → execute macro → preview file → execute file → preview QR → execute QR
   - Test edge cases:
     - Disconnect during macro execution
     - Emergency stop during file execution with preview open
     - Switching between files rapidly
     - No macros configured
     - Jogging while streaming is in progress (should be disabled)
     - Emergency stop during jogging
   - Test with both CNC and Laser machine types

6. UI/UX polish:
   - Ensure consistent spacing and alignment across all new sections
   - Verify color scheme matches existing Saturday theme
   - Check button states (enabled/disabled) in all scenarios
   - Ensure loading indicators appear during async operations
   - Verify all tooltips and descriptions are helpful
   - Test keyboard navigation and accessibility
   - Ensure responsive layout works on different desktop screen sizes

7. Code cleanup:
   - Remove any debug print statements
   - Add code comments for complex logic
   - Ensure consistent code style
   - Update any relevant documentation strings

**Expected Outcome:**
- All features work reliably in production scenarios
- UI is polished and consistent with existing app design
- Edge cases are handled gracefully
- Code is clean and maintainable

---

## Prompt 51: Documentation

**Objective:** Document the new features for future reference.

**Tasks:**
1. Create `docs/MACHINE_CONTROL_MACROS.md`:
   - Overview of macro system
   - Database schema documentation
   - How to create and manage macros
   - Example macros for common operations
   - Troubleshooting guide

2. Update `docs/MACHINE_CONTROL_FEATURE.md`:
   - Add section on macros
   - Add section on unit details display
   - Add section on gcode visualization
   - Update screenshots (if any)
   - Update feature list and capabilities

3. Create example macros documentation:
   - Document 10-15 useful macros for CNC:
     - Spindle control
     - Coolant control
     - Tool change positions
     - Probing sequences
   - Document 10-15 useful macros for Laser:
     - Laser test firing at various powers
     - Air assist control
     - Focus positioning
     - Material test patterns

4. Update this prompt plan:
   - Mark all prompts as completed
   - Add "Completed" section with summary
   - Note any deviations from original plan
   - Add lessons learned

**Expected Outcome:**
- Comprehensive documentation for new features
- Future developers can understand and extend the system
- Example macros help users get started quickly

---

## Summary

This prompt plan enhances the machine control system with three major features:

1. **Macro System** (Prompts 42-45):
   - Database-backed gcode macros
   - Settings interface for macro management
   - One-click execution in machine control screen

2. **Jog Controls** (Prompt 46):
   - Adjustable jog step sizes (Rapid/Normal/Precise)
   - Continuous movement on button hold
   - Intuitive directional controls for X, Y, Z axes

3. **Unit Details Display** (Prompt 47):
   - Product, variant, SKU, and order information
   - Reformatted execution queue with description priority

4. **GCode Visualization** (Prompts 48-49):
   - Visual preview of gcode tool paths
   - Split-screen layout with preview on right
   - Confirmation dialog before execution

Each prompt builds incrementally on the previous work, ensuring the system remains functional throughout development.

---

**Total Prompts:** 10 (Prompts 42-51)
**Estimated Implementation Time:** 4-5 days
**Dependencies:** Machine Control Feature (Prompts 36-41)
