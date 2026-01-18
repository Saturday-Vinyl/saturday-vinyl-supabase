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
   - Analyze the git log to understand what changed since the last release/tag
   - Write a concise synopsis of the changes for TestFlight users
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
