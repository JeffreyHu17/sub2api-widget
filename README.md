# Sub2API Widget

macOS local monitor and WidgetKit widgets for a Sub2API gateway.

This project is independent from `sub2api/`. It consumes existing read-only
Sub2API monitor endpoints and stores only local app state, snapshots, and tokens.

## Targets

- `Sub2APIWidget`: SwiftUI macOS app for login, polling, diagnostics, and widget setup.
- `Sub2APIWidgetExtension`: WidgetKit extension with Activity and Server widgets in small, medium, and large families.
- `Shared`: Codable models, API client, snapshot store, Keychain wrapper, and AppIntent configuration.

## Notes

- WidgetKit rendering frequency is controlled by macOS. The app polls at the selected 5s/15s/30s interval and requests widget reloads after writing snapshots.
- Tokens are stored in Keychain. The shared App Group contains only snapshots and non-secret widget configuration.
- The widget extension never writes to the Sub2API backend.

## Local Run

1. Open `Sub2APIWidget/Sub2APIWidget.xcodeproj` in Xcode.
2. Select the `Sub2APIWidget` scheme and run on `My Mac`.
3. Click `打开登录页`, complete the Sub2API login/TOTP/Cloudflare flow, then start polling.
4. Add the `Sub2API 状态` widget from macOS widgets and choose the desired content, platform, time range, and refresh interval.

For command-line verification:

```sh
xcodebuild -project Sub2APIWidget/Sub2APIWidget.xcodeproj -scheme Sub2APIWidget -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/Sub2APIWidget-DerivedData build CODE_SIGNING_ALLOWED=NO
```
