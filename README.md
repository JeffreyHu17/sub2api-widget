# Sub2API Widget

macOS local monitor and WidgetKit widgets for a Sub2API gateway.

This project is independent from `sub2api/`. It consumes existing read-only
Sub2API monitor endpoints and stores only local app state, snapshots, and tokens.

## Targets

- `Sub2APIWidget`: SwiftUI macOS app for login, polling, diagnostics, and widget setup.
- `Sub2APIWidgetExtension`: WidgetKit extension with Activity, Server, and Account widgets in small, medium, and large families.
- `Shared`: Codable models, API client, snapshot store, Keychain wrapper, and AppIntent configuration.

## Notes

- WidgetKit rendering frequency is controlled by macOS. The app polls at the selected 5s/15s/30s interval and requests widget reloads after writing snapshots.
- Tokens are stored in Keychain. The shared App Group contains only snapshots and non-secret widget configuration.
- The widget extension never writes to the Sub2API backend.
- Account widgets monitor all schedulable accounts by default, or a manually selected account set. Realtime concurrency stays on the selected poll interval; account metadata and local quota fields use a 30-second cache.

## Local Run

1. Open `Sub2APIWidget/Sub2APIWidget.xcodeproj` in Xcode.
2. Select the `Sub2APIWidget` scheme and run on `My Mac`.
3. Click `打开登录页`, complete the Sub2API login/TOTP/Cloudflare flow, then start polling.
4. Add the desired platform, server, or account widget from macOS widgets and choose its instance, account when applicable, and refresh interval.

For command-line verification:

```sh
xcodebuild -project Sub2APIWidget/Sub2APIWidget.xcodeproj -scheme Sub2APIWidget -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/Sub2APIWidget-DerivedData build CODE_SIGNING_ALLOWED=NO
```

Core model tests:

```sh
swift test
```

## Signed Releases

A push to `main` whose head commit contains `Vx.x.x` triggers the ARM64 release workflow. The workflow refuses to publish unsigned builds because App Group sharing requires valid entitlements.

Configure these GitHub Actions secrets before creating a version commit:

- `APPLE_TEAM_ID`
- `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`
- `APP_PROVISION_PROFILE_BASE64`, `WIDGET_PROVISION_PROFILE_BASE64`
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_P8_BASE64`
