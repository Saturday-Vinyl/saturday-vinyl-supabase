# Roll-Based RFID Tag Writing & Printing

## Overview

This document describes a new workflow for writing RFID tags and printing QR code labels in a single, streamlined process. Tags come from the manufacturer on rolls, and this workflow tracks tags by their position on the roll to enable batch printing after all tags are written.

## Problem Statement

Currently, bulk writing RFID tags and printing QR labels are separate processes:
- Bulk write scans all tags in range and writes EPCs
- QR printing is done individually from the tag detail screen

We want to:
1. Write tags one at a time in sequence (to track roll position)
2. Use RSSI (signal strength) to identify the "active" tag closest to the reader
3. Print all QR labels in batch after writing, in the correct order

## Key Concepts

### RSSI-Based Tag Identification

The UHF RFID module returns signal strength (RSSI) for each detected tag. By using low RF power and monitoring RSSI:
- **Strongest signal** = tag currently on/closest to the reader
- **Weaker signals** = tags further away on the roll
- **Fading signals** = tags that have moved past the reader

This allows us to identify a single "active" tag even when multiple tags are in range.

### Roll Position Tracking

Tags on a roll have a physical order. By writing tags one at a time as they pass over the reader, we record each tag's position (1, 2, 3, ...). This position maps directly to the label order for printing.

---

## Data Model

### New Table: `rfid_tag_rolls`

| Column | Type | Description |
|--------|------|-------------|
| id | UUID | Primary key |
| label_width_mm | numeric | Physical label width in millimeters |
| label_height_mm | numeric | Physical label height in millimeters |
| label_count | integer | Total labels on the physical roll |
| status | varchar | One of: `writing`, `ready_to_print`, `printing`, `completed` |
| last_printed_position | integer | Tracks print progress (default 0) |
| manufacturer_url | varchar | Optional link to manufacturer's product listing |
| created_at | timestamp | When the roll was registered |
| created_by | UUID | FK to users table |

### Updates to `rfid_tags` Table

| Column | Type | Description |
|--------|------|-------------|
| roll_id | UUID (nullable) | FK to rfid_tag_rolls |
| roll_position | integer (nullable) | Position on the roll (1-indexed) |

### Roll Status Lifecycle

```
writing → ready_to_print → printing → completed
                              ↓
                          (pause keeps it in 'printing',
                           last_printed_position tracks progress)
```

---

## Write Phase Workflow

### User Flow

1. **Create Roll** - User enters:
   - Label dimensions (width/height in mm)
   - Total label count on roll
   - Optional manufacturer URL

2. **Start Writing** - System:
   - Connects to RFID reader with low RF power
   - Begins continuous polling
   - Displays RSSI visualization

3. **RSSI Visualization** - UI shows:
   - Tags ordered by signal strength (strongest at top)
   - Visual indicator for the "active" tag
   - Already-written Saturday tags distinguished from blank tags

4. **Write Active Tag** - For the strongest-signal blank tag:
   - Generate new EPC with Saturday prefix
   - Write EPC to physical tag
   - Save to database with roll_id and roll_position
   - Display success confirmation

5. **Handle Failures** - If write fails:
   - Show error message
   - Prompt user to retry (button)
   - Do not advance position until successful

6. **Advance Roll** - User manually advances the roll:
   - Previous tag's signal fades
   - New tag becomes strongest signal
   - Repeat write process

7. **Complete Roll** - When all visible tags have Saturday EPCs:
   - System prompts: "All visible tags written. Finish roll?"
   - User confirms
   - Roll status → `ready_to_print`

### Technical Details

- **RF Power**: Reduce to minimum effective level (experiment to find optimal)
- **RSSI Threshold**: May need minimum RSSI to consider a tag "active"
- **Polling Rate**: Continuous polling with ~150ms interval
- **Write Verification**: Poll after write to confirm EPC was written

---

## Print Phase Workflow

### User Flow

1. **Load Roll** - User physically loads the written roll into the Niimbot printer

2. **Start Printing** - System:
   - Connects to Niimbot printer via serial
   - Queries tags for this roll ordered by position
   - Begins sending labels

3. **Print Controls**:
   - **Start** - Begin from position 1 (or last_printed_position + 1)
   - **Pause** - Stop after current label completes
   - **Resume** - Continue from next position
   - **Stop** - Cancel print job entirely
   - **Start from N** - Begin/resume from specific position

4. **Progress Display**:
   - Current label: "Printing 47 of 100"
   - Progress bar visualization
   - Estimated time remaining (optional)

5. **Completion**:
   - All labels printed
   - Roll status → `completed`

### Technical Details

- **Printer Connection**: Use existing `NiimbotPrinter` service
- **Print Method**: Call `printImage()` for each label with delay between
- **Delay**: Configurable (start with ~500ms, adjust based on testing)
- **Image Generation**: Use existing `QRService` to generate QR code images
- **Label Content**: QR code with Saturday branding, EPC identifier below

### Error Recovery

- Track `last_printed_position` after each successful print
- On pause/stop, position is preserved
- On resume, start from `last_printed_position + 1`
- Single label reprints handled via existing tag detail screen

---

## Implementation Plan

### Phase 1: Database & Models

1. Create Supabase migration for `rfid_tag_rolls` table
2. Update `rfid_tags` table with roll_id and roll_position columns
3. Create `RfidTagRoll` model class
4. Create `RfidTagRollRepository` with CRUD operations
5. Add roll-related providers

### Phase 2: Write Workflow

1. Create roll registration UI (form for dimensions, count, URL)
2. Add RSSI visualization component
3. Modify RF power setting (may need lower than current minimum)
4. Create `RollWriteProvider` state management
5. Build roll writing screen with:
   - RSSI tag list
   - Active tag indicator
   - Write button
   - Retry on failure
   - Position counter
   - Complete roll button

### Phase 3: Print Workflow

1. Create roll print screen
2. Implement batch print logic with delays
3. Add print controls (start, pause, resume, stop, start from N)
4. Progress tracking and display
5. Error handling and recovery

### Phase 4: Integration & Polish

1. Navigation between roll list, write, and print screens
2. Roll status indicators throughout UI
3. Testing with physical hardware
4. Performance optimization
5. Documentation

---

## UI Mockups

### RSSI Visualization (Write Phase)

```
┌─────────────────────────────────────────────────┐
│  Roll: abc123          Position: 7 of 100       │
├─────────────────────────────────────────────────┤
│                                                 │
│  Tags by Signal Strength:                       │
│                                                 │
│  ████████████████████████░░░░  Tag (blank)      │
│  ▲ ACTIVE - Ready to write    RSSI: -25 dBm    │
│                                                 │
│  ████████████░░░░░░░░░░░░░░░  5356-A1B2-C3D4   │
│  Written (position 6)         RSSI: -45 dBm    │
│                                                 │
│  ██████░░░░░░░░░░░░░░░░░░░░░  5356-E5F6-7890   │
│  Written (position 5)         RSSI: -58 dBm    │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │          [Write Tag]                    │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  [Finish Roll]                                  │
└─────────────────────────────────────────────────┘
```

### Print Progress (Print Phase)

```
┌─────────────────────────────────────────────────┐
│  Roll: abc123          Status: Printing         │
├─────────────────────────────────────────────────┤
│                                                 │
│  Printing label 47 of 100                       │
│  ████████████████████░░░░░░░░░░░░░  47%        │
│                                                 │
│  Current: 5356-A1B2-C3D4-E5F6-7890-ABCD        │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │  Pause   │  │   Stop   │  │  From N  │      │
│  └──────────┘  └──────────┘  └──────────┘      │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Implementation Status

### Completed (All Phases)

**Phase 1: Database & Models** ✅
- `20241215_add_rfid_tag_rolls.sql` migration created
- `rfid_tag_rolls` table with status lifecycle, dimensions, position tracking
- `rfid_tags` updated with `roll_id` and `roll_position` columns
- `RfidTagRoll` model with status helpers (`isWriting`, `isReadyToPrint`, etc.)
- `RfidTagRollRepository` with full CRUD operations
- Riverpod providers: `rfidTagRollsProvider`, `rfidTagRollByIdProvider`, `tagCountForRollProvider`

**Phase 2: Write Workflow** ✅
- `RollListScreen` - Lists all rolls with status indicators
- `RollCreateScreen` - Form for new roll registration (dimensions, count, URL)
- `RollWriteScreen` - Full RSSI-based tag writing interface
- `RollWriteProvider` - State management for writing session
- `RssiTagList` widget - Real-time RSSI visualization with signal strength bars
- RF power slider (0-30 dBm) for tag isolation
- Active tag identification (strongest unwritten signal)
- Position tracking with progress visualization
- Write verification and error handling

**Phase 3: Print Workflow** ✅
- `RollPrintScreen` - Batch label printing interface
- `RollPrintProvider` - State management with pause/resume/stop
- Print controls: Start, Pause, Resume, Stop, Start from Position N
- Progress bar and position tracking
- `last_printed_position` persisted for recovery

**Phase 4: Integration & Polish** ✅
- "Tag Rolls" navigation in sidebar
- `/rolls` route in `MainScaffold`
- Status badges on roll list and detail screens
- RF power control exposed in roll write UI
- Status-based action buttons (Continue Writing, Start Printing, etc.)
- Build verified (0 analyzer errors, macOS debug build successful)

### Files Created/Modified

**New Files:**
- `lib/models/rfid_tag_roll.dart`
- `lib/repositories/rfid_tag_roll_repository.dart`
- `lib/providers/rfid_tag_roll_provider.dart`
- `lib/providers/roll_write_provider.dart`
- `lib/providers/roll_print_provider.dart`
- `lib/screens/rolls/roll_list_screen.dart`
- `lib/screens/rolls/roll_create_screen.dart`
- `lib/screens/rolls/roll_detail_screen.dart`
- `lib/screens/rolls/roll_write_screen.dart`
- `lib/screens/rolls/roll_print_screen.dart`
- `lib/widgets/tags/rssi_tag_list.dart`
- `supabase/migrations/20241215_add_rfid_tag_rolls.sql`

**Modified Files:**
- `lib/widgets/navigation/sidebar_nav.dart` - Added Tag Rolls nav item
- `lib/screens/main_scaffold.dart` - Added /rolls route
- `lib/config/rfid_config.dart` - RF power constants

---

## Open Questions

1. **Optimal RF Power** - Configurable via slider (0-30 dBm). Start low (~10 dBm) and increase if no tags detected. Requires testing with physical hardware.

2. **RSSI Thresholds** - Using `RfidConfig.minRssiThreshold` (-70 dBm default). Tags below threshold are filtered out.

3. **Print Delay** - Configurable in settings, defaults to 500ms between labels.

4. **Label Design** - Using existing QR label design from `QRService`.

5. **Partial Rolls** - Users can mark rolls complete at any time. Remaining positions are simply unused.

---

## References

- [UHF RFID Technical Guide](../docs/uhf_rfid_technical.md)
- [Label Printing Documentation](../docs/label_printing.md)
- [Niimbot Printer Service](../lib/services/niimbot/niimbot_printer.dart)
- [Bulk Write Provider](../lib/providers/bulk_write_provider.dart)
