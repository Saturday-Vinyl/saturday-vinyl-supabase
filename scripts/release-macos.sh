#!/usr/bin/env bash
#
# Build, sign, notarize, and package a macOS release of Saturday Admin.
#
# Usage:
#   scripts/release-macos.sh             # Build .app + .dmg, both notarized
#   scripts/release-macos.sh --release   # Above, then create the GitHub release
#
# Version comes from pubspec.yaml (e.g. `version: 1.0.1+2`). Bump that before running.
#
# Prerequisites:
#   - "Developer ID Application" certificate in your login keychain
#   - notarytool keychain profile (defaults to "saturday-notary"; override via NOTARY_PROFILE)
#       xcrun notarytool store-credentials saturday-notary \
#         --apple-id <email> --team-id 6WQAHJU2PD --password <app-specific-password>
#   - create-dmg installed: brew install create-dmg
#   - gh CLI authenticated (only for --release)

set -euo pipefail

# --- Config ------------------------------------------------------------------

NOTARY_PROFILE="${NOTARY_PROFILE:-saturday-notary}"
APP_NAME="Saturday! Admin"
APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
RELEASE=false

for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=true ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Must be run from the repo root.
[ -f pubspec.yaml ] || { echo "Run from repo root (no pubspec.yaml here)" >&2; exit 1; }

# Parse version: `1.0.1+2` -> SEMVER=1.0.1, BUILD=2. Build number is optional.
VERSION_LINE=$(awk '/^version:/ {print $2; exit}' pubspec.yaml)
if [[ "$VERSION_LINE" == *+* ]]; then
  SEMVER="${VERSION_LINE%%+*}"
  BUILD="${VERSION_LINE##*+}"
else
  SEMVER="$VERSION_LINE"
  BUILD="1"
fi
TAG="v${SEMVER}"
DMG_NAME="SaturdayAdmin-${SEMVER}.dmg"
ZIP_NAME="SaturdayAdmin-${SEMVER}.zip"

echo "==> Releasing ${TAG} (build ${BUILD})"

# --- Pre-flight --------------------------------------------------------------

command -v create-dmg >/dev/null || {
  echo "Missing create-dmg. Install: brew install create-dmg" >&2; exit 1;
}
security find-identity -v -p codesigning | grep -q "Developer ID Application" || {
  echo "No 'Developer ID Application' certificate in keychain." >&2
  echo "Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1;
}
if $RELEASE; then
  command -v gh >/dev/null || { echo "Missing gh CLI" >&2; exit 1; }
  if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release ${TAG} already exists. Bump pubspec.yaml version." >&2
    exit 1
  fi
fi

# --- Clean -------------------------------------------------------------------

echo "==> Cleaning previous artifacts"
pkill -f "${APP_NAME}" 2>/dev/null || true
sleep 1
rm -rf "$APP_PATH" "$DMG_NAME" "$ZIP_NAME" rw.*.dmg

# --- Build -------------------------------------------------------------------

echo "==> flutter build macos --release"
flutter build macos --release

AUTH=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep "Authority=Developer ID Application" | head -1 || true)
[ -n "$AUTH" ] || { echo "App is not signed with Developer ID Application" >&2; exit 1; }
echo "    $AUTH"

# --- Notarize .app -----------------------------------------------------------

echo "==> Notarizing .app"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"
xcrun notarytool submit "$ZIP_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
rm -f "$ZIP_NAME"

# --- Build .dmg --------------------------------------------------------------

echo "==> Building DMG"
create-dmg \
  --volname "Saturday Admin" \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 140 190 \
  --app-drop-link 400 190 \
  "$DMG_NAME" \
  "$APP_PATH"

# --- Notarize .dmg -----------------------------------------------------------

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_NAME"
xcrun stapler validate "$DMG_NAME"

echo "==> Build complete: $DMG_NAME"

# --- GitHub release ----------------------------------------------------------

if $RELEASE; then
  echo "==> Creating GitHub release ${TAG}"
  gh release create "$TAG" "$DMG_NAME" \
    --target main \
    --title "${TAG}" \
    --latest \
    --notes "Saturday Admin ${TAG}

Download \`${DMG_NAME}\` below, open it, and drag **${APP_NAME}** to your Applications folder.

Signed and notarized — opens cleanly with no Gatekeeper override.

Requires macOS 10.15+ and a \`@saturdayvinyl.com\` Google account."
fi

echo "Done."
