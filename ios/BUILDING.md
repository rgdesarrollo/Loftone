# Building Loftone for iPhone

The iOS runner has been generated with Flutter 3.47.1 / Dart 3.13.1.
It targets iOS 15 or later. This is project preparation, not a validated
iPhone release: no iOS compilation or device testing has been performed.

## On a Mac

Install Flutter, Xcode with iOS platform support, and CocoaPods if required
by the plugins. Then, from the project root:

```sh
flutter pub get
flutter test
open ios/Runner.xcworkspace
```

In Xcode, select Runner → Signing & Capabilities. Select your Apple team,
enable automatic signing, and replace `com.example.loftone` with your own
unique bundle identifier. Update the RunnerTests identifier to match.
Keep the Runner.entitlements setting in all three build configurations;
it configures the keychain used for NAS credentials.

Connect your iPhone, trust the Mac, enable Developer Mode when prompted,
and select the phone as the run destination. Run from Xcode, or use:

```sh
flutter devices
flutter run -d <iphone-device-id>
```

For a signed distribution archive after configuring signing:

```sh
flutter build ipa --release
```

The archive is written to `build/ios/archive` and the exported IPA to
`build/ios/ipa`. TestFlight/App Store distribution requires Apple Developer
Program enrollment and an App Store Connect app record.

A cloud Mac can execute the same build, but requires a configured project,
Apple signing credentials, and a build-service account. No cloud service
has been connected and no signing credentials are included in this project.

## Before distributing

- Adapt and test the desktop-oriented navigation, library, dialogs, and
  playback bar at iPhone portrait and landscape sizes, including safe areas.
- Test Files imports and persistence after restarting. Keep copied imports
  inside the app's storage; desktop folder-reference workflows need review
  for iOS sandbox restrictions.
- Test the SQLite native asset, audio plugins, and NAS credential storage
  on an actual device.
- Test NAS streaming over Wi-Fi, grant the local-network permission when
  prompted, and retain HTTPS certificate validation.
- Test complete tracks, automatic next-track playback, seeking, calls,
  Bluetooth routes, and headphone disconnection.
- Background/lock-screen audio is not configured by this preparation.
  It needs an appropriate audio session, background audio capability,
  interruption handling, and device testing.
- Replace the generated Flutter app icons before distribution.

Official instructions: https://docs.flutter.dev/deployment/ios
