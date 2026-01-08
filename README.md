# Saturday Consumer App

A mobile companion application for Saturday's line of vinyl record furniture. The app enables vinyl enthusiasts to manage their record collections, track what's currently playing, locate albums in their physical storage, and manage their Saturday devices.

## Getting Started

### Prerequisites

- **Flutter SDK**: Version 3.35.0 or higher
- **Dart SDK**: Version 3.9.0 or higher (included with Flutter)
- **Xcode**: 15.0 or higher (for iOS development)
- **Android Studio**: Latest version with Android SDK (for Android development)
- **CocoaPods**: For iOS dependency management

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd saturday-consumer-app
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up environment variables**

   Copy the example environment file and fill in your values:
   ```bash
   cp .env.example .env
   ```

   Required environment variables:
   - `SUPABASE_URL`: Your Supabase project URL
   - `SUPABASE_ANON_KEY`: Your Supabase anonymous key
   - `APP_BASE_URL`: Base URL for Saturday services (https://saturdayvinyl.com)
   - `DISCOGS_API_KEY`: Your Discogs API key
   - `DISCOGS_API_SECRET`: Your Discogs API secret

4. **Run the app**
   ```bash
   # iOS
   flutter run -d ios

   # Android
   flutter run -d android
   ```

### iOS Setup

1. Navigate to the iOS directory and install CocoaPods:
   ```bash
   cd ios
   pod install
   cd ..
   ```

2. Open `ios/Runner.xcworkspace` in Xcode to configure signing if needed.

### Android Setup

1. Ensure you have the Android SDK installed with API level 24 or higher.
2. Accept Android licenses if prompted:
   ```bash
   flutter doctor --android-licenses
   ```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── app.dart                  # Root widget and MaterialApp configuration
│
├── config/
│   ├── constants.dart        # App-wide constants
│   ├── env_config.dart       # Environment configuration loader
│   ├── routes.dart           # Navigation routes
│   └── theme.dart            # Saturday brand theme
│
├── models/                   # Data models
├── services/                 # External service integrations
├── repositories/             # Data access layer
├── providers/                # Riverpod state management
│
├── screens/
│   ├── auth/                 # Authentication screens
│   ├── now_playing/          # Now Playing feature
│   ├── library/              # Library management
│   ├── account/              # Account & device management
│   └── search/               # Global search
│
├── widgets/
│   ├── common/               # Shared widgets
│   ├── now_playing/          # Now Playing widgets
│   ├── library/              # Library widgets
│   ├── devices/              # Device management widgets
│   └── scanner/              # QR/barcode scanner widgets
│
└── utils/                    # Utility functions
```

## Platform Configuration

| Platform | Minimum Version | Package/Bundle ID |
|----------|-----------------|-------------------|
| iOS | 14.0 | `com.dlatham.saturdayconsumer.dev` (dev) / `com.saturdayvinyl.consumer` (prod) |
| Android | API 24 (Android 7.0) | `com.saturdayvinyl.consumer` |

## Deep Linking Setup

The app supports Universal Links (iOS) and App Links (Android) for the domain `app.saturdayvinyl.com`.

### Supported Deep Link Paths

| Path | Description |
|------|-------------|
| `/tags/{epc}` | Opens tag association flow with scanned EPC |
| `/albums/{id}` | Opens album detail screen |
| `/invite/{code}` | Opens library invitation acceptance |

### Server Configuration

The deep link verification files are located in `deep-link-files/.well-known/` and must be hosted at `https://app.saturdayvinyl.com/.well-known/`:

1. **apple-app-site-association** - iOS Universal Links verification
2. **assetlinks.json** - Android App Links verification

#### Hosting Setup (Netlify recommended)

1. Create a Netlify site and upload the `deep-link-files/.well-known/` contents
2. Add custom domain `app.saturdayvinyl.com` in Netlify
3. Add a CNAME record in DNSimple:
   - **Name:** `app`
   - **Target:** `your-site.netlify.app`

#### Android SHA256 Fingerprint

After building the app, get the debug fingerprint:
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA256
```

For release builds, get the fingerprint from Google Play Console → App signing.

Update `assetlinks.json` with the fingerprint(s).

### Testing Deep Links

**iOS Simulator:**
```bash
xcrun simctl openurl booted "https://app.saturdayvinyl.com/albums/123"
xcrun simctl openurl booted "https://app.saturdayvinyl.com/tags/abc123"
```

**Android Emulator:**
```bash
adb shell am start -a android.intent.action.VIEW -d "https://app.saturdayvinyl.com/albums/123"
```

### Current Development Note

iOS is currently using the development bundle ID `com.dlatham.saturdayconsumer.dev` due to Apple Developer credential issues. When switching to production:

1. Update iOS bundle ID to `com.saturdayvinyl.consumer`
2. Update `apple-app-site-association` to use `6WQAHJU2PD.com.saturdayvinyl.consumer`

## Brand Colors

| Name | Hex | Usage |
|------|-----|-------|
| Primary Dark | `#3F3A34` | Main brand color, text, icons |
| Success | `#30AA47` | Success states, confirmations |
| Error | `#F35345` | Errors, destructive actions |
| Info | `#6AC5F4` | Informational states |
| Secondary | `#B2AAA3` | Secondary text, borders |
| Light | `#E2DAD0` | Backgrounds, cards |

## Development

### Running Tests

```bash
flutter test
```

### Analyzing Code

```bash
flutter analyze
```

### Code Generation

When modifying models or other files that use code generation:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Documentation

- [Developer's Guide](docs/DEVELOPERS_GUIDE.md) - Comprehensive technical documentation
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md) - Phased development roadmap
