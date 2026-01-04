# Saturday! Admin App

A Flutter-based administration application for Saturday Vinyl, managing production workflows, RFID tag tracking, and firmware provisioning.

## Getting Started

### Prerequisites

- Flutter SDK (stable channel)
- macOS for desktop development
- Supabase project (see `.env.example` for required configuration)

### Setup

1. Copy `.env.example` to `.env` and fill in your credentials
2. Run `flutter pub get`
3. Run migrations against your Supabase project (see `supabase/migrations/`)
4. Run `flutter run -d macos` for desktop

## Architecture

### State Management

This app uses **Riverpod** for state management. Key patterns:

- `Provider` for singletons (repositories, services)
- `FutureProvider` for async data fetching
- `FutureProvider.family` for parameterized queries
- `StateNotifierProvider` for complex state with actions

### Project Structure

```
lib/
├── config/          # Theme, constants, configuration
├── models/          # Data models (Equatable classes with fromJson/toJson)
├── providers/       # Riverpod providers and state notifiers
├── repositories/    # Supabase database operations
├── screens/         # Full-page UI screens
├── services/        # External service integrations (serial, printing, etc.)
├── utils/           # Utilities and helpers
└── widgets/         # Reusable UI components
```

### Key Features

- **Production Tracking**: QR-based unit tracking through production steps
- **RFID Tag Management**: UHF RFID tag writing and tracking
- **Firmware Management**: Upload and flash firmware to embedded devices
- **Label Printing**: Thermal label printing via Niimbot printers

## RFID Tag Rolls

The app supports roll-based RFID tag writing for batch operations. See `prompts/roll_based_rfid_workflow.md` for the full specification.

### Roll Workflow

1. **Create Roll**: Register a new roll with label dimensions and count
2. **Write Phase**: Write EPCs to tags one at a time using RSSI-based identification
3. **Print Phase**: Batch print QR labels in roll order via Niimbot printer

### Database Tables

- `rfid_tag_rolls`: Roll metadata (dimensions, status, print progress)
- `rfid_tags`: Individual tags with optional `roll_id` and `roll_position`

## Hardware Integration

### UHF RFID Module (YRM100)

- Serial connection at 115200 baud
- See `docs/uhf_rfid_technical.md` for protocol details

### Niimbot Thermal Printer

- Direct serial communication (not OS print drivers)
- See `lib/services/niimbot/` for implementation

## Development Notes

### Adding New Providers

Follow the pattern in existing provider files:

```dart
// Repository provider (singleton)
final myRepositoryProvider = Provider<MyRepository>((ref) {
  return MyRepository();
});

// Data provider (auto-refresh on dependencies)
final myDataProvider = FutureProvider<MyData>((ref) async {
  final repo = ref.watch(myRepositoryProvider);
  return await repo.getData();
});

// Management actions (invalidate caches after mutations)
final myManagementProvider = Provider((ref) => MyManagement(ref));
```

### Database Migrations

Migrations are in `supabase/migrations/` with numeric prefixes. Apply them in order to your Supabase project via the SQL editor.

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Riverpod Documentation](https://riverpod.dev/)
- [Supabase Documentation](https://supabase.com/docs)
