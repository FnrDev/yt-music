# YT Music for Windows (planned)

Mirrors the macOS app's architecture, so most of the design carries over.

## Proposed stack

- **C# / .NET 8+, WinUI 3** (Windows App SDK) for the window, tray and settings
- **WebView2** hosting `https://music.youtube.com`
- The page side is the existing [`shared/bridge/ytm-bridge.js`](../shared/bridge/ytm-bridge.js);
  it already detects `window.chrome.webview` and posts messages through it

## macOS → Windows mapping

| macOS (`macos/YTMusic/…`)                      | Windows equivalent                                                                 |
|------------------------------------------------|------------------------------------------------------------------------------------|
| `WKUserScript` at document end, page world     | `CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync` (wait for `DOMContentLoaded` inside) |
| `WKScriptMessageHandler` "ytm"                 | `CoreWebView2.WebMessageReceived` → `TryGetWebMessageAsString()`                   |
| `evaluateJavaScript(command.javaScript)`       | `CoreWebView2.ExecuteScriptAsync(...)`, same JS string                             |
| `PlayerModel` / `PlayerState`                  | `PlayerModel` with `INotifyPropertyChanged`, same fields as `shared/PROTOCOL.md`   |
| `NowPlayingController` (MPNowPlayingInfoCenter)| `SystemMediaTransportControls` (media keys, volume flyout, lock screen)           |
| `StatusItemController` + mini-player popover   | Notification-area (tray) icon + flyout window; taskbar thumbnail toolbar buttons |
| `TrackNotifier` (UserNotifications)            | `AppNotificationManager` toast                                                     |
| `ThemeController` (shared/themes/*.css)        | Same JS snippet via `AddScriptToExecuteOnDocumentCreatedAsync` + `ExecuteScriptAsync` |
| `VolumeKeeper` (UserDefaults)                  | `ApplicationData.Current.LocalSettings`                                            |
| `WebNavigationHandler` (allow-list)            | `NavigationStarting` / `NewWindowRequested` → `Launcher.LaunchUriAsync`            |
| `websiteDataStore = .default()`                | WebView2 user data folder under `%LOCALAPPDATA%`                                   |
| Hide on close                                  | Hide to tray on close                                                              |

## Notes for whoever starts this

- `AddScriptToExecuteOnDocumentCreatedAsync` runs *before* the DOM exists, unlike
  macOS's document-end injection. Either wrap the bridge in a `DOMContentLoaded`
  listener on the Windows side or make the bridge tolerate an early start. The
  bridge already polls for the player bar, so it mostly copes.
- Keep platform code out of `ytm-bridge.js` except in `post()`.
