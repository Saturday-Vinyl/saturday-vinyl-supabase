# Build IPA for TestFlight

Prepare and build the iOS app for TestFlight deployment.

## Steps

1. **Determine if a clean build is needed**
   - Check the git diff to see what files have changed since the last commit
   - A clean build is required if any of the following changed:
     - `pubspec.yaml` or `pubspec.lock` (dependencies)
     - `ios/Podfile` or `ios/Podfile.lock`
     - Any files in `ios/Runner/` (native iOS code, assets, or configuration)
     - Any files in `ios/Runner.xcodeproj/` or `ios/Runner.xcworkspace/`
   - If a clean build is needed, run:
     ```bash
     cd ios && rm -rf Pods Podfile.lock && pod install && cd ..
     flutter clean
     ```

2. **Build the IPA**
   - Run `flutter build ipa`
   - If the build fails, diagnose and fix the issue before proceeding

3. **Write TestFlight release notes**
   - Find the most recent TestFlight tag to determine the range of changes:
     ```bash
     git describe --tags --match 'testflight/*' --abbrev=0
     ```
   - If a previous tag exists, gather all commits since that tag:
     ```bash
     git log $(git describe --tags --match 'testflight/*' --abbrev=0)..HEAD --oneline
     ```
   - If no previous tag exists (first build), use the full recent git log instead
   - Write a concise synopsis of ALL changes since the last tagged build for TestFlight users
   - Format requirements:
     - Plain text only (no markdown)
     - No emojis
     - Keep it user-friendly (focus on features and fixes, not technical details)
     - Include testing notes if there are new features to test

4. **Help the user upload to TestFlight**
   - Display the TestFlight release notes text for the user to copy
   - Launch the Transporter app: `open /Applications/Transporter.app`
   - Open the IPA folder in Finder: `open ./build/ios/ipa`
   - Remind the user to drag `Saturday.ipa` into the Transporter app to upload

5. **Tag the build and optionally create a GitHub release**
   - Read the current version from `pubspec.yaml` (the `version:` field, e.g. `1.2.3+42`)
   - Construct the tag name: `testflight/v{version}` (e.g. `testflight/v1.2.3+42`)
   - Tag the current commit:
     ```bash
     git tag -a testflight/v{version} -m "TestFlight build {version}"
     git push origin testflight/v{version}
     ```
   - Ask the user if they want to create a GitHub release for this build
   - If yes, create the release using the TestFlight release notes:
     ```bash
     gh release create testflight/v{version} --title "TestFlight v{version}" --notes "{release_notes}"
     ```
   - If no, skip the GitHub release (the git tag is still pushed as a marker)
