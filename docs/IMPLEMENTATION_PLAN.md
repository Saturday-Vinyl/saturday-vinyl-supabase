# Saturday Consumer App - Implementation Plan

## Overview

This document provides a step-by-step implementation plan for building the Saturday Consumer App MVP. Each phase contains discrete tasks that can be assigned to developers or AI agents independently.

### How to Use This Document

Each task includes:
- **Objective**: What needs to be accomplished
- **Context**: Background information and dependencies
- **Requirements**: Specific deliverables
- **Acceptance Criteria**: How to verify completion
- **Reference Files**: Relevant documentation or existing code

Tasks are ordered by dependency - complete them sequentially within each phase, though some phases can run in parallel.

---

## Phase 1: Project Foundation

### Task 1.1: Flutter Project Initialization

**Objective**: Create the Flutter project with proper configuration for iOS and Android.

**Context**: We're building a consumer mobile app for Saturday's vinyl furniture ecosystem. The app needs to support iOS and Android, with tablet layouts.

**Requirements**:
1. Create new Flutter project named `saturday_consumer_app`
2. Configure minimum SDK versions:
   - iOS: 14.0
   - Android: API 24 (Android 7.0)
3. Set up app identifiers:
   - iOS Bundle ID: `com.saturdayvinyl.consumer`
   - Android Package: `com.saturdayvinyl.consumer`
4. Configure app display name: "Saturday"
5. Add app icons using the Saturday brand icon (placeholder for now)
6. Configure launch screen with Saturday brand colors (Primary Dark: #3F3A34, Light: #E2DAD0)
7. Enable internet permission for Android
8. Set up basic folder structure per the developer's guide

**Acceptance Criteria**:
- [ ] `flutter run` successfully launches on iOS simulator
- [ ] `flutter run` successfully launches on Android emulator
- [ ] App displays "Saturday" as the app name
- [ ] Folder structure matches developer's guide specification
- [ ] `.gitignore` properly configured for Flutter

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Project Structure section

---

### Task 1.2: Dependencies and Environment Configuration

**Objective**: Add all required dependencies and set up environment configuration.

**Context**: The app uses Riverpod for state management, Supabase for backend, and various packages for camera scanning, BLE, etc.

**Requirements**:
1. Add dependencies to `pubspec.yaml`:
   ```yaml
   dependencies:
     flutter_riverpod: ^2.4.0
     supabase_flutter: ^2.3.4
     mobile_scanner: ^3.5.0
     cached_network_image: ^3.3.0
     flutter_dotenv: ^5.1.0
     equatable: ^2.0.5
     go_router: ^12.0.0
     flutter_blue_plus: ^1.29.0
     google_fonts: ^6.1.0
     shared_preferences: ^2.2.0
     json_annotation: ^4.8.1

   dev_dependencies:
     build_runner: ^2.4.0
     json_serializable: ^6.7.0
     flutter_lints: ^3.0.0
   ```
2. Create `lib/config/env_config.dart` with environment variable loader
3. Create `.env.example` with required variables:
   ```
   SUPABASE_URL=
   SUPABASE_ANON_KEY=
   APP_BASE_URL=
   DISCOGS_API_KEY=
   DISCOGS_API_SECRET=
   ```
4. Add `.env` to `.gitignore`
5. Create `lib/config/constants.dart` with app constants

**Acceptance Criteria**:
- [ ] All dependencies resolve without conflicts
- [ ] `EnvConfig.load()` validates required environment variables
- [ ] Missing env vars throw descriptive error
- [ ] Constants file contains app-wide configuration values
- [ ] `.env.example` documents all required variables

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Dependencies and Environment sections

---

### Task 1.3: Theme and Design System

**Objective**: Implement the Saturday brand design system as a Flutter theme.

**Context**: Saturday has a warm, retro aesthetic with specific brand colors and typography. The app should feel like an extension of their handcrafted furniture.

**Requirements**:
1. Create `lib/config/theme.dart` with:
   - Color scheme using Saturday brand colors:
     - Primary Dark: #3F3A34
     - Success: #30AA47
     - Error: #F35345
     - Info: #6AC5F4
     - Secondary: #B2AAA3
     - Light/Background: #E2DAD0
   - Typography using Bevan for headlines (via google_fonts)
   - System default sans-serif for body text
   - Component themes:
     - Cards with large border radius (16px), light background
     - Buttons with brand styling
     - AppBar with brand colors
     - Bottom navigation bar styling
     - Input decoration theme
2. Create `lib/config/styles.dart` with reusable style constants:
   - Spacing values (4, 8, 12, 16, 24, 32, 48)
   - Border radius values
   - Shadow definitions
3. Support light theme only for MVP (dark theme future consideration)

**Acceptance Criteria**:
- [ ] Theme applies correctly to MaterialApp
- [ ] Bevan font loads and displays for headlines
- [ ] Brand colors are used consistently
- [ ] Cards, buttons, and inputs match Saturday aesthetic
- [ ] Large corner radius applied to appropriate components

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Design System section

---

### Task 1.4: Navigation Structure

**Objective**: Set up the app's navigation using go_router with bottom tab navigation.

**Context**: The app has three main sections (Now Playing, Library, Account) accessed via bottom tabs, plus a global search and various detail screens.

**Requirements**:
1. Create `lib/config/routes.dart` with go_router configuration
2. Implement bottom navigation shell with three tabs:
   - Now Playing (home icon)
   - Library (album/grid icon)
   - Account (person icon)
3. Create placeholder screens for each tab:
   - `lib/screens/now_playing/now_playing_screen.dart`
   - `lib/screens/library/library_screen.dart`
   - `lib/screens/account/account_screen.dart`
4. Set up nested navigation for each tab (preserves tab state)
5. Create route constants for type-safe navigation
6. Add global search route (modal/overlay)
7. Create `lib/widgets/common/saturday_app_bar.dart` with:
   - Library switcher dropdown (placeholder)
   - Search icon button
8. Create `lib/widgets/common/saturday_bottom_nav.dart`

**Acceptance Criteria**:
- [ ] Bottom navigation displays three tabs
- [ ] Tapping tabs switches content
- [ ] Tab state is preserved when switching
- [ ] App bar displays on all screens
- [ ] Search icon is visible and tappable
- [ ] Deep links can be parsed (basic structure)

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Navigation Structure section

---

## Phase 2: Core Infrastructure

### Task 2.1: Supabase Service Layer

**Objective**: Create the Supabase service singleton for database and auth access.

**Context**: Following patterns from the admin app, we use a singleton service for centralized Supabase client access.

**Requirements**:
1. Create `lib/services/supabase_service.dart`:
   - Singleton pattern with static instance
   - `initialize()` static method called at app startup
   - Expose `client` getter for Supabase operations
   - Expose `currentUser` getter
   - Expose `authStateChanges` stream
   - `signOut()` method
2. Update `lib/main.dart` to:
   - Load environment config
   - Initialize Supabase service
   - Wrap app in ProviderScope
   - Handle initialization errors gracefully
3. Create `lib/providers/supabase_provider.dart`:
   - Provider for SupabaseService instance

**Acceptance Criteria**:
- [ ] App initializes Supabase on startup
- [ ] SupabaseService.instance returns singleton
- [ ] Client is accessible after initialization
- [ ] Error shown if Supabase fails to initialize
- [ ] Auth state changes stream emits events

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Supabase Integration section
- Admin app authentication guide (provided in conversation)

---

### Task 2.2: Data Models

**Objective**: Create all core data models with JSON serialization.

**Context**: Models follow the Equatable pattern with fromJson/toJson and copyWith methods, matching admin app conventions.

**Requirements**:
1. Create model files in `lib/models/`:

   **user.dart**:
   - id, email, fullName, avatarUrl, createdAt, lastLogin, preferences

   **library.dart**:
   - id, name, description, createdAt, updatedAt, createdBy

   **library_member.dart**:
   - id, libraryId, userId, role (enum: owner, editor, viewer), joinedAt, invitedBy

   **album.dart** (canonical):
   - id, discogsId, title, artist, year, genres, styles, label, coverImageUrl, tracks (list), createdAt, updatedAt

   **library_album.dart**:
   - id, libraryId, albumId, addedAt, addedBy, notes, isFavorite
   - Include nested album object for joined queries

   **tag.dart**:
   - id, epcIdentifier, libraryAlbumId, status (enum: active, retired), associatedAt, associatedBy, createdAt, lastSeenAt

   **device.dart**:
   - id, userId, deviceType (enum: hub, crate), name, serialNumber, firmwareVersion, status (enum: online, offline, setup_required), batteryLevel, lastSeenAt, createdAt, settings

   **listening_history.dart**:
   - id, userId, libraryAlbumId, playedAt, playDurationSeconds, completedSide (enum: A, B, null), deviceId

   **album_location.dart**:
   - id, libraryAlbumId, deviceId, detectedAt, removedAt

   **track.dart** (for album tracks):
   - position, title, duration

2. All models must:
   - Extend Equatable
   - Have const constructor
   - Include fromJson factory
   - Include toJson method
   - Include copyWith method
   - Use json_serializable annotations

**Acceptance Criteria**:
- [ ] All models compile without errors
- [ ] fromJson/toJson round-trip preserves data
- [ ] Equatable equality works correctly
- [ ] copyWith creates new instance with updated fields
- [ ] Enums serialize to/from strings correctly

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Data Architecture section

---

### Task 2.3: Repository Layer

**Objective**: Create repository classes for database operations.

**Context**: Repositories abstract Supabase queries from the rest of the app, following the pattern from the admin app.

**Requirements**:
1. Create `lib/repositories/user_repository.dart`:
   - `getUser(String userId)`
   - `getOrCreateUser(SupabaseUser)` - creates user record on first login
   - `updateUser(User)`
   - `updateLastLogin(String userId)`

2. Create `lib/repositories/library_repository.dart`:
   - `getUserLibraries(String userId)` - returns libraries with membership role
   - `getLibrary(String libraryId)`
   - `createLibrary(String name, String userId)`
   - `updateLibrary(Library)`
   - `deleteLibrary(String libraryId)`
   - `getLibraryMembers(String libraryId)`
   - `addLibraryMember(String libraryId, String email, LibraryRole role)`
   - `updateMemberRole(String memberId, LibraryRole role)`
   - `removeMember(String memberId)`

3. Create `lib/repositories/album_repository.dart`:
   - `getAlbum(String albumId)`
   - `getAlbumByDiscogsId(String discogsId)`
   - `createAlbum(Album)` - creates canonical album record
   - `searchAlbums(String query)` - search canonical albums
   - `getLibraryAlbums(String libraryId, {filters, sort, pagination})`
   - `getLibraryAlbum(String libraryAlbumId)`
   - `addAlbumToLibrary(String libraryId, String albumId, String userId)`
   - `removeAlbumFromLibrary(String libraryAlbumId)`
   - `updateLibraryAlbum(LibraryAlbum)`

4. Create `lib/repositories/tag_repository.dart`:
   - `getTag(String tagId)`
   - `getTagByEpc(String epc)`
   - `associateTag(String epc, String libraryAlbumId, String userId)`
   - `disassociateTag(String tagId)`
   - `getTagsForLibraryAlbum(String libraryAlbumId)`

5. Create `lib/repositories/device_repository.dart`:
   - `getUserDevices(String userId)`
   - `getDevice(String deviceId)`
   - `createDevice(Device)`
   - `updateDevice(Device)`
   - `updateDeviceStatus(String deviceId, DeviceStatus)`
   - `deleteDevice(String deviceId)`

6. Create `lib/repositories/listening_history_repository.dart`:
   - `recordPlay(String userId, String libraryAlbumId, String deviceId)`
   - `updatePlayDuration(String historyId, int seconds, Side? completedSide)`
   - `getUserHistory(String userId, {limit, offset})`
   - `getAlbumPlayCount(String libraryAlbumId)`

**Acceptance Criteria**:
- [ ] All repository methods handle Supabase errors gracefully
- [ ] Queries use proper Supabase select syntax with joins
- [ ] Pagination works correctly for list queries
- [ ] Repository methods are testable (Supabase can be mocked)

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Data Architecture section
- Admin app patterns (user_repository example in conversation)

---

### Task 2.4: Core Providers

**Objective**: Create Riverpod providers for core app state.

**Context**: Providers connect repositories to UI, managing async state and caching.

**Requirements**:
1. Create `lib/providers/auth_provider.dart`:
   - `authStateProvider` - StreamProvider for auth state changes
   - `currentSupabaseUserProvider` - current Supabase auth user
   - `currentUserProvider` - FutureProvider for User model from database
   - `isSignedInProvider` - bool provider

2. Create `lib/providers/library_provider.dart`:
   - `userLibrariesProvider` - FutureProvider for user's libraries
   - `currentLibraryProvider` - StateProvider for selected library
   - `currentLibraryIdProvider` - derived provider for just the ID
   - `libraryByIdProvider` - FutureProvider.family

3. Create `lib/providers/album_provider.dart`:
   - `libraryAlbumsProvider` - FutureProvider for current library's albums
   - `albumByIdProvider` - FutureProvider.family
   - `libraryAlbumByIdProvider` - FutureProvider.family

4. Create `lib/providers/device_provider.dart`:
   - `userDevicesProvider` - FutureProvider for user's devices
   - `deviceByIdProvider` - FutureProvider.family

5. Create `lib/providers/repository_providers.dart`:
   - Provider for each repository (for dependency injection)

**Acceptance Criteria**:
- [ ] Auth state updates trigger UI rebuilds
- [ ] Library switching updates currentLibraryProvider
- [ ] Album queries filter by current library
- [ ] Providers can be invalidated to refresh data
- [ ] Loading and error states handled via AsyncValue

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - State Management section
- Admin app state management guide (provided in conversation)

---

## Phase 3: Authentication

### Task 3.1: Auth Service

**Objective**: Create authentication service for consumer sign-in flows.

**Context**: Unlike the admin app (Google OAuth with domain restriction), the consumer app supports email/password and social auth.

**Requirements**:
1. Create `lib/services/auth_service.dart`:
   - Singleton pattern matching SupabaseService
   - `signUpWithEmail(String email, String password)`
   - `signInWithEmail(String email, String password)`
   - `signInWithApple()` - Apple Sign In
   - `signInWithGoogle()` - Google Sign In
   - `signOut()`
   - `resetPassword(String email)`
   - `getCurrentUser()`
   - `isSessionValid()`
   - `refreshSession()`

2. Configure platform-specific auth:
   - iOS: Add Apple Sign In capability, configure Google Sign In
   - Android: Configure Google Sign In

3. Update `lib/providers/auth_provider.dart`:
   - Add `authServiceProvider`
   - Add sign in/out action providers

**Acceptance Criteria**:
- [ ] Email sign up creates account and sends confirmation
- [ ] Email sign in authenticates and creates session
- [ ] Social sign in works on iOS (Apple)
- [ ] Social sign in works on Android (Google)
- [ ] Sign out clears session
- [ ] Password reset sends email

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Authentication section
- Admin app auth service (provided in conversation) - adapt for consumer

---

### Task 3.2: Auth Screens

**Objective**: Build authentication UI screens.

**Context**: Clean, branded screens for sign in/up with Saturday's warm aesthetic.

**Requirements**:
1. Create `lib/screens/auth/login_screen.dart`:
   - Saturday logo/branding at top
   - Email input field
   - Password input field
   - "Sign In" button
   - "Forgot Password?" link
   - Divider with "or"
   - Social sign in buttons (Apple, Google)
   - "Don't have an account? Sign Up" link
   - Loading state during authentication
   - Error message display

2. Create `lib/screens/auth/signup_screen.dart`:
   - Saturday logo/branding
   - Full name input
   - Email input
   - Password input (with requirements hint)
   - "Create Account" button
   - Social sign up buttons
   - "Already have an account? Sign In" link
   - Loading and error states

3. Create `lib/screens/auth/forgot_password_screen.dart`:
   - Email input
   - "Send Reset Link" button
   - Success confirmation message
   - Back to sign in link

4. Create `lib/widgets/auth/social_sign_in_button.dart`:
   - Reusable button for Apple/Google sign in
   - Platform-appropriate styling

5. Update router to handle auth flow:
   - Redirect to login if not authenticated
   - Redirect to main app after authentication

**Acceptance Criteria**:
- [ ] Login screen matches Saturday brand aesthetic
- [ ] Form validation shows appropriate errors
- [ ] Loading states prevent double-submission
- [ ] Social buttons display correctly per platform
- [ ] Navigation between auth screens works
- [ ] Successful auth navigates to main app

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Design System and Authentication sections

---

## Phase 4: Library Feature

### Task 4.1: Library Screen - Basic List/Grid

**Objective**: Build the main library screen with album display.

**Context**: The library is the user's collection of vinyl records. It should prominently display album artwork.

**Requirements**:
1. Update `lib/screens/library/library_screen.dart`:
   - Consume `libraryAlbumsProvider`
   - Toggle between grid and list views
   - Display loading state
   - Display empty state ("No albums yet")
   - Display error state with retry
   - Pull-to-refresh functionality

2. Create `lib/widgets/library/album_grid.dart`:
   - Responsive grid (2 columns phone, 3-4 tablet)
   - Album art with rounded corners
   - Artist and title below image
   - Tap to open album detail

3. Create `lib/widgets/library/album_list.dart`:
   - Album art thumbnail (square, left side)
   - Title, artist, year on right
   - Tap to open album detail

4. Create `lib/widgets/library/album_card.dart`:
   - Shared album display component
   - Cached network image for artwork
   - Placeholder for missing artwork
   - Saturday brand styling

5. Create `lib/widgets/library/view_toggle.dart`:
   - Grid/List toggle button in app bar

**Acceptance Criteria**:
- [ ] Albums load and display from Supabase
- [ ] Grid view shows album art prominently
- [ ] List view shows art with metadata
- [ ] View toggle persists preference
- [ ] Pull-to-refresh reloads data
- [ ] Empty state displays when no albums
- [ ] Images load with placeholder/shimmer

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Library feature section

---

### Task 4.2: Library Filtering and Sorting

**Objective**: Add filtering and sorting capabilities to the library.

**Context**: Users need to find albums quickly in large collections.

**Requirements**:
1. Create `lib/providers/library_filter_provider.dart`:
   - StateNotifier for filter/sort state
   - Sort options: artist, title, dateAdded, recentlyPlayed, year
   - Filter options: genre, decade, location (crate)
   - Computed `filteredAlbumsProvider` that applies filters

2. Create `lib/widgets/library/sort_dropdown.dart`:
   - Dropdown button in app bar
   - Sort direction toggle (A-Z / Z-A)
   - Visual indicator of current sort

3. Create `lib/widgets/library/filter_bar.dart`:
   - Horizontal scrolling filter chips
   - Genre filter (multi-select)
   - Decade filter (multi-select)
   - Location/crate filter
   - "Clear filters" option
   - Active filter count badge

4. Create `lib/widgets/library/filter_bottom_sheet.dart`:
   - Full filter options in bottom sheet
   - Launched from filter icon in app bar
   - Apply/Clear buttons

5. Update library screen to use filtered provider

**Acceptance Criteria**:
- [ ] Sorting changes album order immediately
- [ ] Multiple filters can be applied together
- [ ] Filter chips show active filters
- [ ] Clear filters resets to default
- [ ] Sort preference persists
- [ ] Empty state when filters match nothing

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Library feature section

---

### Task 4.3: Album Detail Screen

**Objective**: Build the album detail view with full metadata.

**Context**: Shows complete album information including tracks, location, and associated tags.

**Requirements**:
1. Create `lib/screens/library/album_detail_screen.dart`:
   - Large album art hero image
   - Album title and artist (Bevan font)
   - Year, label, genres as chips
   - Track listing with durations
   - Side A / Side B separation (if applicable)
   - Total duration
   - "Set as Now Playing" button
   - Location info (which crate, or "Unknown")
   - "Associate Tag" button
   - Notes field (editable for editors/owners)
   - Favorite toggle

2. Create `lib/widgets/library/track_list.dart`:
   - Track number, title, duration
   - Side headers (Side A, Side B)
   - Total side duration

3. Create `lib/widgets/library/album_location_badge.dart`:
   - Shows crate name or "Unknown location"
   - Last seen timestamp if not currently detected

4. Update navigation to handle album detail route
5. Implement "Set as Now Playing" action

**Acceptance Criteria**:
- [ ] Album art displays prominently
- [ ] All metadata renders correctly
- [ ] Track list shows durations formatted (M:SS)
- [ ] Side A/B separation works for double albums
- [ ] Location shows crate name if known
- [ ] Set as Now Playing updates state
- [ ] Edit notes works for editors/owners

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Library feature section

---

### Task 4.4: Add Album Flow

**Objective**: Implement adding albums to the library via multiple methods.

**Context**: Users can add albums by scanning barcode, photographing cover, or searching Discogs.

**Requirements**:
1. Create `lib/services/discogs_service.dart`:
   - Search albums by query
   - Search by barcode
   - Get album details by Discogs ID
   - Parse response into Album model
   - Handle API rate limiting

2. Create `lib/screens/library/add_album_screen.dart`:
   - Three method options:
     - Scan Barcode
     - Photo of Cover (placeholder for Phase 2)
     - Search Discogs
   - Method selection UI

3. Create `lib/screens/library/barcode_scanner_screen.dart`:
   - Camera viewfinder using mobile_scanner
   - Barcode detection
   - Auto-lookup on scan
   - Manual entry fallback
   - Flash toggle

4. Create `lib/screens/library/discogs_search_screen.dart`:
   - Search input field
   - Search results list
   - Album art, title, artist, year in results
   - Tap to select
   - Pagination/load more

5. Create `lib/screens/library/confirm_album_screen.dart`:
   - Preview album details before adding
   - Edit opportunity (if wrong match)
   - "Add to Library" button
   - Option to associate tag immediately

6. Create `lib/providers/add_album_provider.dart`:
   - StateNotifier for add album flow
   - Selected album state
   - Add album action (creates canonical + library_album)

**Acceptance Criteria**:
- [ ] Barcode scan finds albums in Discogs
- [ ] Manual search returns relevant results
- [ ] Album details display before confirming
- [ ] Adding creates records in database
- [ ] Duplicate albums reuse canonical record
- [ ] User returns to library after adding
- [ ] New album appears in library list

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Library feature section

---

### Task 4.5: Tag Association

**Objective**: Implement QR code scanning to associate RFID tags with albums.

**Context**: Saturday tags have QR codes that encode the EPC. Scanning links the physical tag to a digital album record.

**Requirements**:
1. Create `lib/services/qr_scanner_service.dart`:
   - Parse Saturday QR code URLs
   - Extract EPC from `/tags/{epc}` path
   - Validate EPC format (24 hex chars, 5356 prefix)

2. Create `lib/screens/library/tag_association_screen.dart`:
   - Camera viewfinder for QR scanning
   - Instructions text
   - Cancel button
   - Success/error feedback

3. Create `lib/widgets/scanner/qr_scanner.dart`:
   - Reusable QR scanner component
   - Scanning frame overlay
   - Flash toggle
   - Detection callback

4. Create `lib/utils/epc_validator.dart`:
   - `isValidSaturdayEpc(String epc)`
   - `formatEpcForDisplay(String epc)` - adds dashes for readability

5. Update album detail screen:
   - Show associated tag(s) if any
   - "Associate Tag" button triggers scanner
   - Confirmation after successful association

6. Create `lib/providers/tag_provider.dart`:
   - `tagsForAlbumProvider` - FutureProvider.family
   - Associate tag action

**Acceptance Criteria**:
- [ ] QR scanner opens from album detail
- [ ] Saturday QR codes are recognized
- [ ] Non-Saturday QR codes show error
- [ ] Valid EPC creates tag association
- [ ] Already-associated tags show warning
- [ ] Associated tag displays on album detail

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Hardware Integration section
- QR code generation docs (provided in conversation)
- RFID technical guide (provided in conversation)

---

### Task 4.6: Library Switcher

**Objective**: Implement the library switcher dropdown in the header.

**Context**: Users can have multiple libraries and need to switch between them.

**Requirements**:
1. Update `lib/widgets/common/saturday_app_bar.dart`:
   - Display current library name
   - Dropdown arrow indicator
   - Tap opens library switcher

2. Create `lib/widgets/common/library_switcher.dart`:
   - Bottom sheet or dropdown menu
   - List of user's libraries
   - Role badge (owner/editor/viewer)
   - Current library highlighted
   - "Create New Library" option
   - Tap to switch library

3. Create `lib/screens/library/create_library_screen.dart`:
   - Library name input
   - Optional description
   - "Create" button

4. Update `lib/providers/library_provider.dart`:
   - Persist selected library in SharedPreferences
   - Default to first library on app start
   - Handle library deletion (switch to another)

**Acceptance Criteria**:
- [ ] Current library name shows in header
- [ ] Tapping opens library list
- [ ] Switching library updates album display
- [ ] Selected library persists across app restarts
- [ ] Can create new library from switcher
- [ ] Shared libraries show role badge

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Navigation section

---

## Phase 5: Now Playing Feature

### Task 5.1: Now Playing Screen - Basic Display

**Objective**: Build the Now Playing screen showing current album.

**Context**: The primary experience when a record is on the turntable. Should be visually striking with album art as hero.

**Requirements**:
1. Create `lib/providers/now_playing_provider.dart`:
   - StateNotifier for now playing state
   - Current album
   - Started at timestamp
   - Current side (A/B)
   - Set from manual selection
   - Clear now playing

2. Update `lib/screens/now_playing/now_playing_screen.dart`:
   - Large album art (hero, ~60% of screen)
   - Album title and artist below
   - "Nothing playing" empty state
   - Tap album art for full-screen view

3. Create `lib/widgets/now_playing/album_art_hero.dart`:
   - Full-width album art
   - Rounded corners matching brand
   - Shadow/elevation
   - Placeholder for no image

4. Create `lib/widgets/now_playing/now_playing_info.dart`:
   - Album title (Bevan font)
   - Artist name
   - Year and label

5. Create empty state widget:
   - Friendly message
   - "Choose an album" CTA
   - Links to library

**Acceptance Criteria**:
- [ ] Now Playing tab shows current album
- [ ] Album art displays large and prominently
- [ ] Empty state shows when nothing playing
- [ ] Setting album from library updates Now Playing
- [ ] Tab badge could indicate something is playing (optional)

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Now Playing section

---

### Task 5.2: Track List and Flip Timer

**Objective**: Add track listing and flip timer to Now Playing.

**Context**: Users need to see tracks and know when to flip the record.

**Requirements**:
1. Update Now Playing screen to include:
   - Collapsible track list
   - Current side indicator (A/B toggle)
   - Time elapsed on current side
   - Time remaining on current side
   - Flip reminder indicator

2. Create `lib/widgets/now_playing/track_list.dart`:
   - Side A / Side B headers
   - Track list for current side highlighted
   - Track durations
   - Total side duration

3. Create `lib/widgets/now_playing/flip_timer.dart`:
   - Elapsed time display
   - Remaining time display
   - Progress bar/indicator
   - Side A/B toggle buttons
   - Visual urgency when flip time approaches

4. Create `lib/widgets/now_playing/side_selector.dart`:
   - A / B toggle buttons
   - Updates current side in provider
   - Resets timer when switching

5. Update `lib/providers/now_playing_provider.dart`:
   - Add side tracking
   - Add elapsed time calculation
   - Calculate flip time from track durations

**Acceptance Criteria**:
- [ ] Track list shows all tracks
- [ ] Current side is highlighted
- [ ] Timer counts elapsed time
- [ ] Remaining time calculated from tracks
- [ ] Switching sides resets timer
- [ ] Visual indication when nearing flip time

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Now Playing section

---

### Task 5.3: Up Next Recommendations

**Objective**: Show album recommendations on Now Playing screen.

**Context**: Suggest what to play next based on the current album.

**Requirements**:
1. Create `lib/services/recommendation_service.dart`:
   - `getRecommendations(LibraryAlbum current, {limit})`:
     - Filter to same library
     - Score by genre/style match
     - Boost recently played together
     - Exclude currently playing

2. Create `lib/providers/recommendations_provider.dart`:
   - FutureProvider dependent on now playing
   - Returns list of recommended LibraryAlbums
   - Invalidates when now playing changes

3. Create `lib/widgets/now_playing/up_next_carousel.dart`:
   - Horizontal scrolling list
   - Album art thumbnails
   - Title and artist below
   - Tap to view detail or set as now playing
   - "Play Next" quick action

4. Update Now Playing screen:
   - "Up Next" section below main content
   - Carousel of recommendations
   - Section hidden if no recommendations

**Acceptance Criteria**:
- [ ] Recommendations appear based on current album
- [ ] Genre/style matching produces relevant results
- [ ] Carousel scrolls horizontally
- [ ] Tapping opens album detail
- [ ] "Play Next" sets as now playing
- [ ] Section hidden when library is empty

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Recommendations Engine section

---

### Task 5.4: Now Playing - Manual Input Methods

**Objective**: Allow users to set Now Playing via camera scan.

**Context**: Users without hardware can still use Now Playing by scanning barcode or selecting from library.

**Requirements**:
1. Create `lib/screens/now_playing/set_now_playing_screen.dart`:
   - Method selection:
     - Choose from Library
     - Scan Barcode
     - Photo of Cover (placeholder)
   - Recent albums quick selection

2. Update barcode scanner to work for Now Playing:
   - Scan barcode
   - Find album in library (or add if not found)
   - Set as now playing

3. Create `lib/widgets/now_playing/recent_albums.dart`:
   - Grid of recently played albums
   - Quick tap to set as now playing
   - Limited to 6-8 items

4. Add "Set as Now Playing" action from:
   - Album detail screen (already done)
   - Library album long-press menu
   - Search results

5. Update Now Playing empty state:
   - Clear CTAs for each input method
   - Quick access to recent albums

**Acceptance Criteria**:
- [ ] Can set Now Playing from library selection
- [ ] Can set via barcode scan
- [ ] Recent albums appear for quick selection
- [ ] Multiple entry points all work
- [ ] Now Playing updates immediately

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Now Playing section

---

## Phase 6: Account & Devices

### Task 6.1: Account Screen

**Objective**: Build the account/settings screen.

**Context**: User profile, preferences, and access to device management.

**Requirements**:
1. Update `lib/screens/account/account_screen.dart`:
   - User profile section:
     - Avatar (or initials)
     - Name
     - Email
     - "Edit Profile" button
   - Libraries section:
     - List of owned libraries
     - "Create Library" button
     - "Manage" button per library
   - Settings section:
     - Notification preferences
     - App preferences
   - Device section:
     - "Manage Devices" button
     - Device count badge
   - Sign out button
   - App version at bottom

2. Create `lib/screens/account/edit_profile_screen.dart`:
   - Name input
   - Avatar picker (future: image upload)
   - Save button

3. Create `lib/screens/account/notification_settings_screen.dart`:
   - Toggle for each notification type:
     - Flip reminders
     - Battery low alerts
     - Device offline alerts
     - Crate activity (verbose)
   - Flip reminder threshold slider
   - Quiet hours configuration

4. Create `lib/screens/account/library_settings_screen.dart`:
   - Library name (editable)
   - Description (editable)
   - Members list
   - Invite member button
   - Remove library (with confirmation)

**Acceptance Criteria**:
- [ ] Profile displays user info
- [ ] Can edit name
- [ ] Notification toggles persist
- [ ] Library settings accessible
- [ ] Sign out clears session and returns to login
- [ ] App version displays correctly

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Account section

---

### Task 6.2: Device List and Status

**Objective**: Show user's Saturday devices with status.

**Context**: Users need to see their hub and crates, and their current status.

**Requirements**:
1. Create `lib/screens/account/device_list_screen.dart`:
   - List of user's devices
   - Empty state with "Add Device" CTA
   - Pull to refresh

2. Create `lib/widgets/devices/device_card.dart`:
   - Device icon (hub vs crate)
   - Device name
   - Status badge (online/offline)
   - Battery level (for crates)
   - Last seen timestamp
   - Tap for detail

3. Create `lib/widgets/devices/battery_indicator.dart`:
   - Battery icon with level
   - Color coding (green/yellow/red)
   - Percentage text

4. Create `lib/widgets/devices/status_badge.dart`:
   - Online: green dot
   - Offline: gray dot
   - Setup Required: yellow dot

5. Create `lib/providers/device_provider.dart` (extend):
   - Real-time device status updates
   - Polling or Supabase realtime subscription

**Acceptance Criteria**:
- [ ] Devices list shows all user devices
- [ ] Status indicators are accurate
- [ ] Battery level displays for crates
- [ ] Pull to refresh updates status
- [ ] Empty state encourages adding device
- [ ] Tap navigates to detail

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Device Management section

---

### Task 6.3: Device Detail Screen

**Objective**: Show detailed device information.

**Context**: View device details and status, prepare for future management features.

**Requirements**:
1. Create `lib/screens/account/device_detail_screen.dart`:
   - Device name (editable)
   - Device type
   - Serial number
   - Firmware version
   - Status with timestamp
   - Battery level and history (crates)
   - For Hub: WiFi network name
   - For Crate: Contents summary (albums inside)
   - "Remove Device" button (with confirmation)

2. Create `lib/widgets/devices/device_info_row.dart`:
   - Label and value display
   - Consistent styling

3. Create `lib/widgets/devices/crate_contents.dart`:
   - List of albums currently in crate
   - Album art thumbnails
   - Tap to view album detail

4. Update device repository:
   - Get device with related data
   - Update device name

**Acceptance Criteria**:
- [ ] All device info displays
- [ ] Can rename device
- [ ] Crate shows contained albums
- [ ] Can remove device (with confirmation)
- [ ] Hub shows network info

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Device Management section

---

### Task 6.4: Device Provisioning - BLE Setup

**Objective**: Implement BLE-based device provisioning flow.

**Context**: New devices are set up via BLE from the phone. Hub needs WiFi credentials, crates need Thread credentials from the hub.

**Requirements**:
1. Create `lib/services/ble_service.dart`:
   - Scan for Saturday devices
   - Filter by service UUID
   - Connect to device
   - Write characteristics (WiFi creds, Thread creds)
   - Read device info
   - Disconnect

2. Create `lib/screens/account/device_setup_screen.dart`:
   - Step 1: Select device type (Hub/Crate)
   - Step 2: Scanning for devices
   - Step 3: Select device from list
   - Step 4: Configuration (WiFi for hub, Thread for crate)
   - Step 5: Confirmation/success

3. Create `lib/widgets/devices/ble_device_list.dart`:
   - Scanned devices list
   - Signal strength indicator
   - Device type icon
   - Tap to select

4. Create `lib/screens/account/wifi_setup_screen.dart`:
   - Network name input (or scan available)
   - Password input
   - Connect button
   - Progress indicator

5. Create `lib/providers/ble_provider.dart`:
   - StateNotifier for BLE state
   - Scanning state
   - Connected device
   - Setup progress

6. Handle BLE permissions:
   - Request Bluetooth permission
   - Request location permission (Android)
   - Handle permission denied states

**Acceptance Criteria**:
- [ ] BLE permissions requested appropriately
- [ ] Scanning finds Saturday devices
- [ ] Can connect to device via BLE
- [ ] Hub setup accepts WiFi credentials
- [ ] Device registers in database after setup
- [ ] User sees success confirmation
- [ ] Errors handled gracefully

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Device Provisioning section

---

## Phase 7: Search and Polish

### Task 7.1: Global Search

**Objective**: Implement global search across library and Discogs.

**Context**: Search is accessible from any tab via header icon.

**Requirements**:
1. Create `lib/screens/search/search_screen.dart`:
   - Search input field (auto-focused)
   - Results sections:
     - "In Your Library" - local matches
     - "Add from Discogs" - external matches
   - Recent searches (optional)
   - Cancel/close button

2. Create `lib/providers/search_provider.dart`:
   - StateNotifier for search state
   - Query debouncing (300ms)
   - Parallel search: library + Discogs
   - Combined results state

3. Create `lib/widgets/search/search_result_item.dart`:
   - Album art thumbnail
   - Title and artist
   - Source indicator (library vs Discogs)
   - "Add" button for Discogs results

4. Create `lib/widgets/search/search_section.dart`:
   - Section header
   - Results list
   - "See more" if truncated

5. Update router:
   - Search as modal/overlay route
   - Accessible from all tabs

**Acceptance Criteria**:
- [ ] Search opens from header icon
- [ ] Typing searches both sources
- [ ] Results grouped by source
- [ ] Can add Discogs results to library
- [ ] Tapping library result opens detail
- [ ] Empty state for no results
- [ ] Can close search and return

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Search section

---

### Task 7.2: Tablet Layout

**Objective**: Implement adaptive layouts for tablets.

**Context**: Tablets in landscape should show Now Playing and Library side-by-side.

**Requirements**:
1. Create `lib/widgets/common/adaptive_layout.dart`:
   - Detects phone vs tablet
   - Detects portrait vs landscape
   - Provides appropriate layout

2. Create `lib/screens/tablet/tablet_home_screen.dart`:
   - Two-column layout in landscape:
     - Left: Now Playing
     - Right: Library
   - Album detail opens as panel, not full screen
   - Single column in portrait (like phone)

3. Update navigation for tablet:
   - Bottom tabs may become side rail (optional)
   - Album detail as slide-over panel
   - Maintain context when viewing detail

4. Create `lib/widgets/library/album_detail_panel.dart`:
   - Condensed album detail for panel view
   - Same info, different layout
   - Close button to dismiss

5. Test on various screen sizes:
   - Phone portrait
   - Phone landscape (optional support)
   - Tablet portrait
   - Tablet landscape

**Acceptance Criteria**:
- [ ] Tablet landscape shows dual-pane
- [ ] Now Playing visible while browsing
- [ ] Album detail opens in panel
- [ ] Portrait mode works like phone
- [ ] Navigation adapts appropriately
- [ ] No layout overflow issues

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Tablet Layout section

---

### Task 7.3: Notifications

**Objective**: Implement local notifications for flip reminders and device alerts.

**Context**: Users need timely reminders to flip records and alerts about device status.

**Requirements**:
1. Create `lib/services/notification_service.dart`:
   - Initialize notification channels (Android)
   - Request permissions
   - Schedule notification
   - Cancel notification
   - Handle notification tap

2. Implement flip reminder:
   - Calculate time until flip needed
   - Schedule notification when Now Playing set
   - Cancel when Now Playing cleared
   - Update when side changed

3. Implement device alerts:
   - Listen for device status changes
   - Battery low notification
   - Device offline notification

4. Create `lib/providers/notification_provider.dart`:
   - Notification permission state
   - User preferences integration

5. Deep link from notification:
   - Flip reminder → Now Playing screen
   - Device alert → Device detail screen

**Acceptance Criteria**:
- [ ] Flip reminder fires at correct time
- [ ] Notification preferences respected
- [ ] Battery low alert works
- [ ] Tapping notification opens correct screen
- [ ] Can dismiss/clear notifications
- [ ] Quiet hours respected (if implemented)

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Notifications section

---

### Task 7.4: Deep Linking

**Objective**: Handle deep links into the app.

**Context**: QR codes and shared links should open directly in the app.

**Requirements**:
1. Create `lib/utils/deep_link_handler.dart`:
   - Parse incoming URLs
   - Route to appropriate screen
   - Handle app not running case

2. Configure platform deep links:
   - iOS: Universal Links for saturdayvinyl.com
   - Android: App Links for saturdayvinyl.com

3. Handle URL patterns:
   - `/tags/{epc}` → Tag association screen
   - `/albums/{id}` → Album detail screen
   - `/invite/{code}` → Library invitation acceptance

4. Update router to handle deep link routes

5. Test scenarios:
   - App running, link opened
   - App not running, link opened
   - Invalid links handled gracefully

**Acceptance Criteria**:
- [ ] QR code scan opens tag association
- [ ] Album links open album detail
- [ ] Invite links process invitation
- [ ] Invalid links show error
- [ ] Works when app is backgrounded
- [ ] Works when app is closed

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Deep Linking section

---

### Task 7.5: Offline Support and Caching

**Objective**: Ensure app works gracefully when offline.

**Context**: Users should be able to browse their library offline with cached data.

**Requirements**:
1. Create `lib/services/cache_service.dart`:
   - Cache library albums locally
   - Cache album artwork
   - Cache user preferences
   - Cache last known device status

2. Update repositories for offline:
   - Try network first, fall back to cache
   - Queue mutations when offline
   - Sync when connectivity restored

3. Create `lib/providers/connectivity_provider.dart`:
   - Monitor network connectivity
   - Expose online/offline state
   - Trigger sync on reconnection

4. Update UI for offline mode:
   - Indicator when offline
   - Disable actions that require network
   - Show cached data with "last updated" timestamp

5. Implement image caching:
   - cached_network_image handles this
   - Ensure placeholder for uncached images

**Acceptance Criteria**:
- [ ] Library browsable when offline
- [ ] Album details viewable when offline
- [ ] Offline indicator displays
- [ ] Actions gracefully disabled
- [ ] Data syncs when back online
- [ ] Cached images display

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Offline Behavior section

---

### Task 7.6: Error Handling and Loading States

**Objective**: Implement consistent error handling and loading states throughout the app.

**Context**: Professional UX requires graceful handling of errors and clear loading feedback.

**Requirements**:
1. Create `lib/widgets/common/loading_indicator.dart`:
   - Saturday branded loading spinner
   - Optional message text
   - Consistent styling

2. Create `lib/widgets/common/error_display.dart`:
   - Error message display
   - Retry button
   - Optional "Contact Support" link
   - Different variants (full screen, inline, snackbar)

3. Create `lib/widgets/common/empty_state.dart`:
   - Illustration or icon
   - Title and message
   - Optional CTA button
   - Different variants per context

4. Update all screens to use consistent:
   - Loading states during data fetch
   - Error states with retry
   - Empty states with guidance

5. Implement global error handling:
   - Catch unhandled exceptions
   - Show user-friendly error
   - Log for debugging

**Acceptance Criteria**:
- [ ] Loading states are consistent
- [ ] Errors show actionable message
- [ ] Retry buttons work
- [ ] Empty states guide users
- [ ] No raw error messages shown to users
- [ ] Critical errors logged

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Design System section

---

## Phase 8: Real-Time Features

### Task 8.1: Real-Time Now Playing Updates

**Objective**: Receive real-time Now Playing updates from the hub.

**Context**: When a record is placed on the hub, the app should update automatically.

**Requirements**:
1. Create database table/structure for Now Playing state:
   - User ID
   - Current EPC (from hub)
   - Detected at timestamp
   - Hub device ID

2. Create `lib/providers/realtime_now_playing_provider.dart`:
   - Subscribe to Supabase Realtime
   - Filter by user's hub(s)
   - Update Now Playing state on change

3. Update Now Playing provider:
   - Merge manual and automatic sources
   - Auto-detected takes priority
   - Clear when record removed

4. Handle EPC resolution:
   - Lookup EPC → Tag → LibraryAlbum
   - Update Now Playing with resolved album
   - Handle unknown EPC (not in library)

5. Update UI:
   - Indicator for auto-detected vs manual
   - "Detected by [Hub Name]" subtitle

**Acceptance Criteria**:
- [ ] Real-time subscription connects
- [ ] Hub detection updates Now Playing
- [ ] EPC resolved to album
- [ ] Unknown EPC handled gracefully
- [ ] Manual selection still works
- [ ] Updates are near-instantaneous

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Communication Flow section

---

### Task 8.2: Real-Time Device Status

**Objective**: Receive real-time device status updates.

**Context**: Device online/offline status and battery levels should update in real-time.

**Requirements**:
1. Create `lib/providers/realtime_device_provider.dart`:
   - Subscribe to Supabase Realtime for devices table
   - Filter by user's devices
   - Update device status on change

2. Handle status change events:
   - Device comes online
   - Device goes offline
   - Battery level changes

3. Trigger notifications for:
   - Device offline (if enabled)
   - Battery low (if enabled)

4. Update device list UI:
   - Real-time status badges
   - No need to pull-to-refresh

5. Optimize subscription:
   - Single subscription for all user's devices
   - Unsubscribe when not viewing devices

**Acceptance Criteria**:
- [ ] Device status updates in real-time
- [ ] Battery level updates in real-time
- [ ] Notifications trigger appropriately
- [ ] No excessive battery drain from subscriptions
- [ ] Clean up on logout

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Device Management section

---

### Task 8.3: Real-Time Album Locations

**Objective**: Track album locations in crates in real-time.

**Context**: When albums are added/removed from crates, locations should update.

**Requirements**:
1. Create `lib/providers/realtime_location_provider.dart`:
   - Subscribe to album_locations table changes
   - Filter by user's library albums
   - Update location state on change

2. Update album detail:
   - Real-time location display
   - History of locations (optional)

3. Add location filter to library:
   - Filter by crate
   - "Unknown location" filter

4. Create location summary view:
   - Which albums are in which crates
   - Missing albums (not in any crate)

**Acceptance Criteria**:
- [ ] Album location updates in real-time
- [ ] Album detail shows current location
- [ ] Can filter library by location
- [ ] Location changes reflected immediately

**Reference Files**:
- `docs/DEVELOPERS_GUIDE.md` - Crate Location section

---

### Task 8.4: Dynamic Island & Live Activities (iOS)

**Objective**: Display flip timer in iOS Dynamic Island and Lock Screen using Live Activities.

**Context**: Users should see the flip timer countdown without opening the app. Live Activities show real-time updates on the Lock Screen and Dynamic Island (iPhone 14 Pro+).

**Requirements**:
1. Add `live_activities` Flutter plugin to dependencies

2. Create iOS Widget Extension in Xcode:
   - Add new Widget Extension target
   - Enable `NSSupportsLiveActivities` in Info.plist
   - Set minimum deployment to iOS 16.1

3. Create SwiftUI views for Live Activity:
   - **Lock Screen widget**: Album art, title, artist, progress bar, elapsed/remaining time
   - **Dynamic Island compact**: Album art thumbnail + remaining time
   - **Dynamic Island expanded**: Full timer with album info and flip warning

4. Create `lib/services/live_activity_service.dart`:
   - `startFlipTimerActivity(album, startedAt, totalDuration)`
   - `updateFlipTimerActivity(elapsed, remaining, isNearFlip)`
   - `stopFlipTimerActivity()`
   - Platform check (iOS 16.1+ only)

5. Integrate with Now Playing provider:
   - Start Live Activity when album is set as Now Playing
   - Update activity periodically (every 30 seconds or on state change)
   - End activity when Now Playing is cleared
   - Update when side is switched

6. Create ActivityAttributes model (Swift):
   - Static: albumTitle, artist, albumArtUrl, totalDuration
   - Dynamic: elapsedSeconds, isNearFlip, isOvertime

7. Handle edge cases:
   - App killed while activity running (activity persists)
   - Multiple activities not allowed (end previous before starting new)
   - Graceful degradation on older iOS versions

**Acceptance Criteria**:
- [ ] Live Activity appears on Lock Screen when Now Playing is set
- [ ] Dynamic Island shows timer on supported devices
- [ ] Timer updates reflect actual elapsed time
- [ ] "Flip Soon" warning displays when approaching flip time
- [ ] Activity ends when Now Playing is cleared
- [ ] Side switch restarts activity with new duration
- [ ] No crashes on iOS versions without Live Activity support
- [ ] Works when app is backgrounded or killed

**Reference Files**:
- [live_activities Flutter plugin](https://pub.dev/packages/live_activities)
- [Flutter Live Activities GitHub](https://github.com/istornz/flutter_live_activities)
- `lib/providers/now_playing_provider.dart`
- `lib/widgets/now_playing/flip_timer.dart`

---

## Phase 9: Testing and Quality

### Task 9.1: Unit Tests - Models and Utils

**Objective**: Write unit tests for models and utility functions.

**Requirements**:
1. Test all model fromJson/toJson:
   - Round-trip serialization
   - Handle null fields
   - Handle missing fields

2. Test EPC validator:
   - Valid Saturday EPCs
   - Invalid prefix
   - Invalid length
   - Non-hex characters

3. Test recommendation scoring:
   - Genre matching
   - Style matching
   - Edge cases

4. Test duration formatting utilities

**Acceptance Criteria**:
- [ ] All models have serialization tests
- [ ] EPC validator has comprehensive tests
- [ ] Utilities have tests
- [ ] Tests pass in CI

---

### Task 9.2: Unit Tests - Providers and Repositories

**Objective**: Write unit tests for business logic.

**Requirements**:
1. Create mock Supabase client
2. Test repository methods:
   - Successful queries
   - Error handling
   - Edge cases

3. Test StateNotifiers:
   - State transitions
   - Error states
   - Loading states

**Acceptance Criteria**:
- [ ] Repositories have tests with mocked Supabase
- [ ] StateNotifiers have state transition tests
- [ ] Error handling tested

---

### Task 9.3: Widget Tests

**Objective**: Write widget tests for key UI components.

**Requirements**:
1. Test album card rendering
2. Test library grid/list
3. Test Now Playing display
4. Test form validation on auth screens
5. Test navigation flows

**Acceptance Criteria**:
- [ ] Key widgets have tests
- [ ] User interactions tested
- [ ] Loading/error states tested

---

### Task 9.4: Integration Tests

**Objective**: Write integration tests for critical user flows.

**Requirements**:
1. Auth flow: Sign up → Sign in → Sign out
2. Add album flow: Search → Select → Add
3. Tag association flow: Scan → Associate
4. Now Playing flow: Select → Display → Timer

**Acceptance Criteria**:
- [ ] Critical flows have integration tests
- [ ] Tests run on CI
- [ ] Tests use test database/environment

---

## Appendix: Task Dependencies

```
Phase 1 (Foundation)
├── 1.1 Project Init
├── 1.2 Dependencies ────────────────┐
├── 1.3 Theme ───────────────────────┤
└── 1.4 Navigation ──────────────────┤
                                     │
Phase 2 (Infrastructure)             │
├── 2.1 Supabase Service ◄───────────┘
├── 2.2 Data Models
├── 2.3 Repositories ────────────────┐
└── 2.4 Core Providers ◄─────────────┤
                                     │
Phase 3 (Auth)                       │
├── 3.1 Auth Service ◄───────────────┘
└── 3.2 Auth Screens

Phase 4 (Library) - Can start after Phase 3
├── 4.1 Library Screen
├── 4.2 Filtering/Sorting
├── 4.3 Album Detail
├── 4.4 Add Album
├── 4.5 Tag Association
└── 4.6 Library Switcher

Phase 5 (Now Playing) - Can start after Phase 4.1
├── 5.1 Basic Display
├── 5.2 Track List/Timer
├── 5.3 Recommendations
└── 5.4 Manual Input

Phase 6 (Account/Devices) - Can start after Phase 3
├── 6.1 Account Screen
├── 6.2 Device List
├── 6.3 Device Detail
└── 6.4 Device Provisioning (BLE)

Phase 7 (Polish) - After Phases 4-6
├── 7.1 Global Search
├── 7.2 Tablet Layout
├── 7.3 Notifications
├── 7.4 Deep Linking
├── 7.5 Offline Support
└── 7.6 Error Handling

Phase 8 (Real-Time) - After Phase 7
├── 8.1 Real-Time Now Playing
├── 8.2 Real-Time Device Status
├── 8.3 Real-Time Locations
└── 8.4 Dynamic Island/Live Activities (iOS)

Phase 9 (Testing) - Ongoing, finalize after Phase 8
├── 9.1 Model/Util Tests
├── 9.2 Provider/Repo Tests
├── 9.3 Widget Tests
└── 9.4 Integration Tests
```

---

## Estimated Scope

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1: Foundation | 4 | Low |
| Phase 2: Infrastructure | 4 | Medium |
| Phase 3: Auth | 2 | Medium |
| Phase 4: Library | 6 | High |
| Phase 5: Now Playing | 4 | Medium |
| Phase 6: Account/Devices | 4 | High |
| Phase 7: Polish | 6 | Medium |
| Phase 8: Real-Time | 4 | Medium |
| Phase 9: Testing | 4 | Medium |
| **Total** | **38** | |

---

## Success Criteria for MVP

The MVP is complete when:

1. **Authentication**: Users can sign up, sign in, and sign out
2. **Library Management**: Users can add albums, browse library, filter/sort
3. **Tag Association**: Users can scan QR codes to associate tags
4. **Now Playing**: Users can set and view now playing with track list
5. **Device Management**: Users can view device status (provisioning is bonus)
6. **Multi-Library**: Users can create and switch between libraries
7. **Search**: Users can search library and Discogs
8. **Polish**: Loading states, error handling, and offline support work
9. **Platform**: Works on iOS and Android phones and tablets
