# Saturday Consumer App - Developer's Guide

## Overview

The Saturday Consumer App is a mobile companion application for Saturday's line of vinyl record furniture. It enables vinyl enthusiasts to manage their record collections, track what's currently playing, locate albums in their physical storage, and manage their Saturday devices.

### Product Vision

Saturday creates premium, handcrafted furniture for vinyl enthusiasts. The consumer app extends this physical experience into the digital realm - it should feel like an extension of the furniture, not a separate tech product. The app helps users:

1. **Experience their vinyl** - See what's playing, track progress, know when to flip
2. **Manage their collection** - Build and browse their library with rich metadata
3. **Find their records** - Locate any album in their Saturday storage furniture
4. **Maintain their ecosystem** - Set up and monitor Saturday devices

### Target Platforms

- **iOS** - Phone and tablet
- **Android** - Phone and tablet
- **Tablet layouts** - Landscape mode with dual-pane Now Playing + Library view

---

## Technical Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SATURDAY ECOSYSTEM                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                  │
│   │   Storage   │     │   Storage   │     │   Storage   │                  │
│   │   Crate A   │     │   Crate B   │     │   Crate C   │                  │
│   │  (Battery)  │     │  (Battery)  │     │  (Battery)  │                  │
│   └──────┬──────┘     └──────┬──────┘     └──────┬──────┘                  │
│          │                   │                   │                          │
│          └───────────────────┼───────────────────┘                          │
│                              │ Thread Mesh                                  │
│                              ▼                                              │
│                    ┌─────────────────┐                                      │
│                    │   Saturday Hub  │                                      │
│                    │  (Now Playing   │                                      │
│                    │    Sensor)      │                                      │
│                    │   [Powered]     │                                      │
│                    └────────┬────────┘                                      │
│                             │ WiFi                                          │
│                             ▼                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                           CLOUD (Supabase)                                  │
│   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│   │    Auth     │   │  Database   │   │   Storage   │   │  Realtime   │   │
│   │             │   │ (PostgreSQL)│   │   (Files)   │   │  (Webhooks) │   │
│   └─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                             │ Internet                                      │
│                             ▼                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                      Consumer Mobile App                             │  │
│   │   ┌───────────┐   ┌───────────┐   ┌───────────────────────────┐    │  │
│   │   │    Now    │   │  Library  │   │   Account & Devices       │    │  │
│   │   │  Playing  │   │           │   │                           │    │  │
│   │   └───────────┘   └───────────┘   └───────────────────────────┘    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                             │ BLE (Setup only)                              │
│                             ▼                                               │
│                    ┌─────────────────┐                                      │
│                    │  Device Setup   │                                      │
│                    │  & Provisioning │                                      │
│                    └─────────────────┘                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Connectivity Architecture

| Connection | Protocol | Purpose |
|------------|----------|---------|
| Furniture ↔ Hub | Thread | Low-power mesh network for EPC reporting |
| Hub ↔ Cloud | WiFi | Real-time state sync, EPC resolution |
| App ↔ Cloud | HTTPS | Library, user data, device status |
| App ↔ Devices | BLE | Initial device setup and provisioning |

### Thread Network

Saturday furniture uses Thread for device communication:

- **Border Router**: The Saturday Hub serves as the Thread border router
- **Sleepy End Devices**: Battery-powered crates operate as Thread SEDs
- **Mesh Topology**: Devices relay messages, extending range across rooms
- **Power Efficiency**: Thread enables weeks of battery life on furniture

### Communication Flow

**Now Playing Detection:**
```
Record placed on hub → Hub reads RFID tag → EPC sent to cloud →
Cloud resolves EPC to album → App receives "Now Playing" update
```

**Crate Inventory:**
```
Record placed in crate → Crate reads RFID tag → EPC sent via Thread to hub →
Hub relays to cloud → Cloud updates album location → App shows updated location
```

**Device Provisioning (BLE):**
```
User initiates setup → App scans for device via BLE →
BLE pairing → App sends Thread credentials → Device joins mesh →
Device registers with cloud
```

---

## Hardware Integration

### RFID System

Saturday uses UHF RFID for record identification:

| Component | Specification |
|-----------|---------------|
| Frequency | UHF (860-960 MHz) |
| Protocol | ISO 18000-6C / EPC Gen2 |
| Tag Size | 96-bit EPC |
| Reader Module | YRM100-based |

### EPC Format

Saturday tags use a specific EPC format:

```
┌─────────────┬─────────────────────────────────────────┐
│   Prefix    │              Random Data                │
│  (2 bytes)  │              (10 bytes)                 │
├─────────────┼─────────────────────────────────────────┤
│    5356     │    XXXX XXXX XXXX XXXX XXXX             │
│   ("SV")    │    (80 random bits)                     │
└─────────────┴─────────────────────────────────────────┘
        Total: 96 bits (12 bytes, 24 hex characters)
```

**Validation:**
```dart
bool isValidSaturdayEpc(String epc) {
  if (epc.length != 24) return false;
  if (!epc.toUpperCase().startsWith('5356')) return false;
  return RegExp(r'^[0-9A-Fa-f]{24}$').hasMatch(epc);
}
```

### QR Codes

Each RFID tag includes a printed QR code for phone-based scanning:

**URL Format:** `https://saturdayvinyl.com/tags/{epc}`

**Deep Link Handling:**
- App registers for `saturdayvinyl.com/tags/*` URLs
- Scanning QR opens app directly to tag association flow
- EPC extracted from URL path

### Saturday Devices

**Phase 1 Products:**

| Device | Power | Connectivity | Function |
|--------|-------|--------------|----------|
| Saturday Hub | Wall power | WiFi + Thread (border router) | Now Playing sensor, holds record jacket |
| Storage Crate | Battery | Thread (SED) | Tracks which records are stored inside |

**Future Products:**
- Console tables
- Speakers
- Additional furniture variants

---

## Data Architecture

### Entity Relationship Overview

```
┌─────────────┐       ┌─────────────────┐       ┌─────────────┐
│    Users    │──────▶│ LibraryMembers  │◀──────│  Libraries  │
│             │       │ (owner/editor/  │       │             │
│             │       │  viewer)        │       │             │
└─────────────┘       └─────────────────┘       └──────┬──────┘
      │                                                │
      │                                                │
      ▼                                                ▼
┌─────────────┐                                ┌─────────────┐
│   Devices   │                                │LibraryAlbums│
│             │                                │             │
└─────────────┘                                └──────┬──────┘
                                                     │
                              ┌──────────────────────┼──────────────────────┐
                              │                      │                      │
                              ▼                      ▼                      ▼
                       ┌─────────────┐        ┌─────────────┐        ┌─────────────┐
                       │    Tags     │        │   Albums    │        │  Locations  │
                       │   (EPCs)    │        │ (canonical) │        │  (crates)   │
                       └─────────────┘        └─────────────┘        └─────────────┘
                                                     │
                                                     ▼
                                              ┌─────────────┐
                                              │   Discogs   │
                                              │  Metadata   │
                                              └─────────────┘
```

### Core Entities

#### Users
```
Users
├── id (UUID)
├── email
├── full_name
├── avatar_url
├── created_at
├── last_login
└── preferences (JSON)
```

#### Libraries
```
Libraries
├── id (UUID)
├── name
├── description
├── created_at
├── updated_at
└── created_by (user_id)
```

#### Library Memberships
```
LibraryMembers
├── id (UUID)
├── library_id
├── user_id
├── role (owner | editor | viewer)
├── joined_at
└── invited_by (user_id)
```

**Roles:**
| Role | View | Add Albums | Edit Albums | Remove Albums | Manage Members | Delete Library |
|------|------|------------|-------------|---------------|----------------|----------------|
| Owner | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Editor | ✓ | ✓ | ✓ | ✓ | - | - |
| Viewer | ✓ | - | - | - | - | - |

#### Albums (Canonical)
Shared across all libraries to avoid duplicate metadata:
```
Albums
├── id (UUID)
├── discogs_id
├── title
├── artist
├── year
├── genres (array)
├── styles (array)
├── label
├── cover_image_url
├── tracks (JSON)
├── created_at
└── updated_at
```

#### Library Albums (Association)
Links albums to libraries with library-specific data:
```
LibraryAlbums
├── id (UUID)
├── library_id
├── album_id
├── added_at
├── added_by (user_id)
├── notes
└── is_favorite
```

#### Tags
```
Tags
├── id (UUID)
├── epc_identifier (24 hex chars, unique)
├── library_album_id (nullable - unassociated if null)
├── status (active | retired)
├── associated_at
├── associated_by (user_id)
├── created_at
└── last_seen_at
```

#### Devices
```
Devices
├── id (UUID)
├── user_id (owner)
├── device_type (hub | crate)
├── name (user-assigned)
├── serial_number
├── firmware_version
├── status (online | offline | setup_required)
├── battery_level (nullable, for battery devices)
├── last_seen_at
├── created_at
└── settings (JSON)
```

#### Listening History
User-specific play history for recommendations:
```
ListeningHistory
├── id (UUID)
├── user_id
├── library_album_id
├── played_at
├── play_duration_seconds (nullable)
├── completed_side (A | B | null)
└── device_id (which hub detected it)
```

#### Album Locations
Tracks physical location of albums in crates:
```
AlbumLocations
├── id (UUID)
├── library_album_id
├── device_id (crate)
├── detected_at
└── removed_at (nullable - null means currently present)
```

### Data Flow Principles

1. **Albums are canonical** - Metadata stored once, referenced by many libraries
2. **Libraries are user-created** - Users can have multiple libraries (home, vacation house, etc.)
3. **Tags belong to library albums** - A tag associates an EPC with an album in a specific library
4. **Listening history is personal** - Even in shared libraries, each user has their own history
5. **Devices belong to users** - Users own devices; libraries are separate from device ownership

---

## Core Features

### 1. Now Playing

The primary experience when a record is on the turntable.

**Features:**
- Album art (hero display)
- Artist and album title
- Track listing with durations
- Current side indicator (A/B)
- Estimated time to flip
- Flip reminder notifications
- "Up Next" recommendations

**Now Playing Sources:**
| Method | Hardware Required | Effort |
|--------|-------------------|--------|
| Auto-detect (hub reads jacket tag) | Yes (hub) | Automatic |
| Manual selection from library | No | Few taps |
| Camera scan (barcode/album cover) | No | Physical action |

**Flip Timer Logic:**
- Calculate total side duration from track metadata
- Track elapsed time from "Now Playing" start
- Send notification at configurable threshold (e.g., 2 minutes before end)

**Recommendations Engine:**
Uses three signals:
1. **Discogs metadata** - Genre, style, label, year, artist relationships
2. **Listening behavior** - Play frequency, time of day patterns
3. **Play patterns** - Albums commonly played in sequence

### 2. Library

The user's collection of vinyl records.

**Features:**
- Grid and list view toggle
- Sorting (artist, title, date added, recently played, genre)
- Filtering (genre, decade, location/crate)
- Album detail view (artwork, tracks, metadata, location)
- Add albums (barcode scan, cover photo, Discogs search)
- Tag association (QR scan)
- Library switcher (header dropdown)

**Adding Albums Flow:**
```
1. User initiates "Add Album"
2. Choose method:
   a. Scan barcode → lookup in Discogs
   b. Photo of cover → image recognition → Discogs match
   c. Manual search → Discogs search
3. Confirm album details
4. Album added to current library
5. Prompt to associate a tag (optional)
```

**Tag Association Flow:**
```
1. User selects album in library
2. Taps "Associate Tag"
3. Scans QR code on Saturday tag
4. App extracts EPC from QR URL
5. EPC linked to library album in database
6. Confirmation shown
```

**Album Location:**
- Shows which crate contains the album (if detected)
- "Last seen: Crate A, 2 hours ago" if removed
- "Unknown location" if never detected in a crate

### 3. Account & Device Management

User settings and Saturday ecosystem management.

**Account Features:**
- Profile management
- Notification preferences
- Library management (create, rename, delete)
- Shared library invitations
- Sign out

**Device Management (Phase 1):**
- Device list with status indicators
- Add new device (BLE provisioning)
- Device details (name, firmware version, battery level)
- Online/offline status

**Device Management (Future):**
- Firmware updates
- Device settings (LED brightness, etc.)
- Diagnostics and troubleshooting

**Device Provisioning Flow:**
```
1. User initiates "Add Device"
2. Select device type (Hub or Crate)
3. App scans for BLE devices
4. User selects their device
5. BLE pairing established
6. For Hub: Enter WiFi credentials
7. For Crate: Hub provides Thread credentials
8. Device joins network
9. Device registers with cloud
10. Confirmation shown
```

### 4. Global Search

Accessible from any tab via header icon.

**Search Results:**
- **In Your Library** - Albums matching query in current library
- **Add from Discogs** - Albums from Discogs that can be added
- **Other Libraries** - Albums in user's other libraries (if multiple)

---

## Navigation Structure

### Phone Layout

```
┌─────────────────────────────────────┐
│  [Library ▼]            [Search]   │  ← Header with library switcher
├─────────────────────────────────────┤
│                                     │
│                                     │
│         Active Tab Content          │
│                                     │
│                                     │
├─────────────────────────────────────┤
│  Now Playing  │  Library  │ Account │  ← Bottom tab bar
└─────────────────────────────────────┘
```

### Tablet Landscape Layout

```
┌──────────────────────────────────────────────────────────────┐
│  [Library ▼]                                      [Search]   │
├────────────────────────┬─────────────────────────────────────┤
│                        │                                     │
│      Now Playing       │            Library                  │
│                        │                                     │
│    ┌────────────┐      │    ┌─────┐ ┌─────┐ ┌─────┐         │
│    │            │      │    │     │ │     │ │     │         │
│    │  Album     │      │    └─────┘ └─────┘ └─────┘         │
│    │   Art      │      │    ┌─────┐ ┌─────┐ ┌─────┐         │
│    │            │      │    │     │ │     │ │     │         │
│    └────────────┘      │    └─────┘ └─────┘ └─────┘         │
│                        │                                     │
│    Track List...       │    Album detail opens in           │
│                        │    panel (not full screen)         │
│                        │                                     │
├────────────────────────┴─────────────────────────────────────┤
│              Bottom tabs (may be adjusted for tablet)        │
└──────────────────────────────────────────────────────────────┘
```

### Library Switcher

Header dropdown showing:
- Current library name (displayed in header)
- List of user's libraries (owned and shared)
- Role indicator for shared libraries
- "Create New Library" option

---

## Notifications

### Notification Types

| Type | Trigger | Urgency | User Configurable |
|------|---------|---------|-------------------|
| Flip reminder | Side duration elapsed | Time-sensitive | Timing threshold |
| Battery low | Device reports < 20% | Important | On/off |
| Device offline | Device not seen for threshold | Important | On/off |
| Crate activity | Record added/removed from crate | Informational | On/off (verbose) |
| Firmware available | New version detected | Low | On/off |
| Library invitation | User invited to shared library | Informational | On/off |

### Notification Preferences

Users can configure:
- Enable/disable each notification type
- Flip reminder threshold (minutes before side ends)
- Quiet hours (no notifications during specified times)

---

## Design System

### Brand Identity

Saturday's brand aesthetic is warm, premium, and slightly retro - reflecting the handcrafted nature of the furniture and the intentionality of vinyl listening.

### Color Palette

| Name | Hex | Usage |
|------|-----|-------|
| Primary Dark | `#3F3A34` | Main brand color, text, icons |
| Success | `#30AA47` | Success states, confirmations |
| Error | `#F35345` | Errors, destructive actions |
| Info | `#6AC5F4` | Informational states |
| Secondary | `#B2AAA3` | Secondary text, borders |
| Light | `#E2DAD0` | Backgrounds, cards |

### Typography

| Usage | Font | Notes |
|-------|------|-------|
| Headlines/Titles | Bevan (Google Fonts) | Blocky serif, retro feel |
| Body text | System default sans-serif | Platform native for readability |

### Design Principles

1. **Album art as hero** - Let the record artwork be the visual star
2. **Warm and tactile** - Feel like an extension of physical furniture
3. **Minimal chrome** - Reduce UI elements, maximize content
4. **Large radius corners** - Soft, friendly, matches brand aesthetic
5. **Generous whitespace** - Let content breathe

### Component Patterns

- **Cards**: Light background (`#E2DAD0`), large corner radius, subtle shadow
- **Buttons**: Primary Dark fill for primary actions, outlined for secondary
- **Navigation**: Bottom tabs with Saturday brand icons
- **Images**: Large corner radius on album art, match card styling

---

## State Management

### Riverpod Architecture

The app uses Flutter Riverpod for state management, following patterns established in the admin app.

```
┌─────────────┐    ┌─────────────┐    ┌──────────────────┐
│   Widgets   │───▶│  Providers  │───▶│    Services      │
│ (Consumer)  │    │ (Riverpod)  │    │                  │
└─────────────┘    └─────────────┘    └──────────────────┘
      │                  │                    │
      ▼                  ▼                    ▼
┌─────────────┐    ┌─────────────┐    ┌──────────────────┐
│     UI      │◀───│    State    │◀───│  Repositories    │
│  (Rebuild)  │    │  Notifiers  │    │  (Data Access)   │
└─────────────┘    └─────────────┘    └──────────────────┘
```

### Provider Types

| Type | Use Case |
|------|----------|
| `Provider` | Singleton services, repositories |
| `FutureProvider` | One-time async data fetch |
| `FutureProvider.family` | Parameterized async fetch (by ID) |
| `StreamProvider` | Real-time data streams |
| `StateNotifierProvider` | Complex mutable state with logic |

### State Class Pattern

```dart
class NowPlayingState {
  final bool isLoading;
  final LibraryAlbum? currentAlbum;
  final DateTime? startedAt;
  final String? error;

  const NowPlayingState({
    this.isLoading = false,
    this.currentAlbum,
    this.startedAt,
    this.error,
  });

  NowPlayingState copyWith({
    bool? isLoading,
    LibraryAlbum? currentAlbum,
    DateTime? startedAt,
    String? error,
  }) {
    return NowPlayingState(
      isLoading: isLoading ?? this.isLoading,
      currentAlbum: currentAlbum ?? this.currentAlbum,
      startedAt: startedAt ?? this.startedAt,
      error: error,
    );
  }
}
```

### Widget Integration

```dart
class NowPlayingScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlayingState = ref.watch(nowPlayingProvider);

    return nowPlayingState.when(
      data: (state) => NowPlayingContent(state: state),
      loading: () => const LoadingIndicator(),
      error: (error, stack) => ErrorDisplay(error: error),
    );
  }
}
```

### Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Provider | `{name}Provider` | `nowPlayingProvider` |
| StateNotifier | `{Name}Notifier` | `NowPlayingNotifier` |
| State class | `{Name}State` | `NowPlayingState` |
| Family provider | `{name}ByIdProvider` | `albumByIdProvider` |
| Repository | `{Name}Repository` | `LibraryRepository` |

---

## Authentication

### Consumer App Authentication

Unlike the admin app (Google OAuth with domain restriction), the consumer app uses standard consumer authentication:

**Supported Methods:**
- Email/password
- Social auth (Apple, Google)
- Magic link (passwordless email)

### Auth Flow

```
App Launch
    │
    ▼
Check Session ──▶ Valid ──▶ Main App
    │
    ▼
  Expired/None
    │
    ▼
Login Screen ──▶ Auth Method ──▶ Supabase Auth ──▶ Session Created
    │
    ▼
Get/Create User Record ──▶ Main App
```

### Session Management

- Sessions managed by Supabase Auth
- Automatic token refresh
- Secure token storage (platform keychain)
- Session state exposed via `StreamProvider`

---

## Supabase Integration

### Services Architecture

```dart
// Singleton Supabase client access
class SupabaseService {
  static SupabaseService get instance => _instance;
  SupabaseClient get client => _client;

  // Auth helpers
  User? get currentUser;
  Stream<AuthState> get authStateChanges;
}
```

### Repository Pattern

```dart
class LibraryRepository {
  final SupabaseService _supabase;

  Future<List<Library>> getUserLibraries(String userId) async {
    final response = await _supabase.client
        .from('library_members')
        .select('libraries(*), role')
        .eq('user_id', userId);

    return response.map((r) => Library.fromJson(r)).toList();
  }

  Future<void> addAlbumToLibrary(String libraryId, String albumId) async {
    await _supabase.client.from('library_albums').insert({
      'library_id': libraryId,
      'album_id': albumId,
      'added_at': DateTime.now().toIso8601String(),
    });
  }
}
```

### Real-time Subscriptions

For Now Playing and device status updates:

```dart
final nowPlayingStreamProvider = StreamProvider<NowPlayingUpdate>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);

  return supabase.client
      .from('now_playing')
      .stream(primaryKey: ['id'])
      .eq('user_id', currentUserId)
      .map((data) => NowPlayingUpdate.fromJson(data.first));
});
```

### Row Level Security

All tables use RLS policies:
- Users can only read/write their own data
- Library access controlled by membership role
- Devices tied to owner user_id

---

## External Integrations

### Discogs API

Primary source for album metadata.

**Usage:**
- Album search (by barcode, title, artist)
- Metadata retrieval (tracks, artwork, genres, styles)
- Cover image URLs

**Caching Strategy:**
- Album metadata cached in `albums` table after first fetch
- Artwork URLs stored; images cached on device
- Periodic refresh for updated metadata (low priority)

### Image Recognition (Future)

For album cover photo identification:
- Capture photo of album cover
- Send to recognition service
- Return potential Discogs matches
- User confirms correct album

---

## Offline Behavior

### Always Available
- Library browsing (cached data)
- Album details (cached metadata and artwork)
- Last known "Now Playing" state
- Last known device status
- Last known album locations

### Requires Connectivity
- Real-time "Now Playing" updates
- Adding new albums
- Tag association
- Device provisioning
- Library sync with other users

### Sync Strategy
- Local-first for read operations
- Queue mutations when offline
- Sync when connectivity restored
- Conflict resolution: server wins (with user notification)

---

## Project Structure

```
lib/
├── main.dart
├── app.dart
│
├── config/
│   ├── constants.dart
│   ├── env_config.dart
│   ├── routes.dart
│   └── theme.dart
│
├── models/
│   ├── user.dart
│   ├── library.dart
│   ├── album.dart
│   ├── library_album.dart
│   ├── tag.dart
│   ├── device.dart
│   └── listening_history.dart
│
├── services/
│   ├── supabase_service.dart
│   ├── auth_service.dart
│   ├── discogs_service.dart
│   ├── ble_service.dart
│   ├── notification_service.dart
│   └── qr_scanner_service.dart
│
├── repositories/
│   ├── user_repository.dart
│   ├── library_repository.dart
│   ├── album_repository.dart
│   ├── tag_repository.dart
│   ├── device_repository.dart
│   └── listening_history_repository.dart
│
├── providers/
│   ├── auth_provider.dart
│   ├── library_provider.dart
│   ├── now_playing_provider.dart
│   ├── album_provider.dart
│   ├── device_provider.dart
│   ├── recommendations_provider.dart
│   └── search_provider.dart
│
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   │
│   ├── now_playing/
│   │   ├── now_playing_screen.dart
│   │   └── flip_reminder_sheet.dart
│   │
│   ├── library/
│   │   ├── library_screen.dart
│   │   ├── album_detail_screen.dart
│   │   ├── add_album_screen.dart
│   │   └── tag_association_screen.dart
│   │
│   ├── account/
│   │   ├── account_screen.dart
│   │   ├── device_list_screen.dart
│   │   ├── device_detail_screen.dart
│   │   ├── device_setup_screen.dart
│   │   └── library_settings_screen.dart
│   │
│   └── search/
│       └── search_screen.dart
│
├── widgets/
│   ├── common/
│   │   ├── saturday_app_bar.dart
│   │   ├── loading_indicator.dart
│   │   ├── error_display.dart
│   │   └── library_switcher.dart
│   │
│   ├── now_playing/
│   │   ├── album_art_hero.dart
│   │   ├── track_list.dart
│   │   ├── flip_timer.dart
│   │   └── up_next_carousel.dart
│   │
│   ├── library/
│   │   ├── album_grid.dart
│   │   ├── album_list.dart
│   │   ├── album_card.dart
│   │   ├── filter_bar.dart
│   │   └── sort_dropdown.dart
│   │
│   ├── devices/
│   │   ├── device_card.dart
│   │   ├── battery_indicator.dart
│   │   └── status_badge.dart
│   │
│   └── scanner/
│       ├── qr_scanner.dart
│       └── barcode_scanner.dart
│
└── utils/
    ├── epc_validator.dart
    ├── duration_formatter.dart
    └── deep_link_handler.dart
```

---

## Deep Linking

### URL Schemes

| URL Pattern | Action |
|-------------|--------|
| `saturdayvinyl.com/tags/{epc}` | Open tag association for EPC |
| `saturdayvinyl.com/albums/{id}` | Open album detail |
| `saturdayvinyl.com/invite/{code}` | Accept library invitation |

### Implementation

- Register URL schemes in platform configurations
- Handle incoming URLs in app initialization
- Route to appropriate screen with parameters
- Handle app-not-installed case (web fallback)

---

## Testing Strategy

### Unit Tests
- Model serialization (fromJson/toJson)
- EPC validation logic
- Business logic in StateNotifiers
- Repository methods (with mocked Supabase)

### Widget Tests
- Individual widget rendering
- User interaction flows
- State management integration

### Integration Tests
- Full user flows (add album, associate tag, etc.)
- Navigation flows
- Deep link handling

---

## Security Considerations

1. **Authentication**: All API calls require valid Supabase session
2. **Row Level Security**: Database enforces access control
3. **Secure Storage**: Tokens stored in platform keychain
4. **Input Validation**: Validate EPCs, UUIDs before database operations
5. **Deep Link Validation**: Verify URL parameters before processing

---

## Performance Considerations

1. **Image Caching**: Cache album artwork aggressively
2. **Pagination**: Library queries paginated for large collections
3. **Lazy Loading**: Load album details on demand
4. **Background Sync**: Sync operations don't block UI
5. **Efficient Rebuilds**: Use `select` on providers to minimize rebuilds

---

## Future Considerations

### Phase 2 Features
- Firmware updates via app
- Device settings and diagnostics
- Furniture-based tag association (place record on hub to pair)
- Advanced recommendation tuning

### Phase 3 Features
- Social features (share what you're playing)
- Discogs collection sync
- Statistics and listening insights
- Smart home integrations (Matter)

---

## Appendix

### Environment Variables

```env
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key

# App
APP_BASE_URL=https://saturdayvinyl.com

# Discogs
DISCOGS_API_KEY=your-discogs-key
DISCOGS_API_SECRET=your-discogs-secret
```

### Dependencies (Expected)

```yaml
dependencies:
  flutter_riverpod: ^2.4.0
  supabase_flutter: ^2.3.4
  mobile_scanner: ^3.5.0
  cached_network_image: ^3.3.0
  flutter_dotenv: ^5.1.0
  equatable: ^2.0.5
  go_router: ^12.0.0
  flutter_blue_plus: ^1.29.0  # For BLE
```

### Brand Assets

- Logo SVG: `assets/images/saturday-logo.svg`
- App Icon SVG: `assets/images/saturday-icon.svg`
- QR Logo: `assets/images/saturday-icon-qr-100x100.png`
- Font: Bevan (Google Fonts, loaded at runtime)
