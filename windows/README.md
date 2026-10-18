# YT Music for Windows

Early version of the Windows app. It mirrors the macOS app's architecture and
reuses its page-side code unchanged.

## Stack

- **C# / .NET 10, WPF** for the window, tray and settings
- **WebView2** (Microsoft Edge, Chromium) hosting `https://music.youtube.com`
- The shared [`ytm-bridge.js`](../shared/bridge/ytm-bridge.js) and
  [`themes/`](../shared/themes/) are embedded straight from `shared/`

## What works

- YouTube Music in WebView2 with a persistent profile (stays signed in) and a
  black title bar that blends into the Spotify-style theme
- Themes: Spotify-style (default) or stock YouTube Music, switchable live in Settings
- Tray icon: left-click shows/hides the window; right-click for play/pause,
  next/previous, like/dislike, shuffle, repeat, settings and quit
- Track-change notifications (shown as Windows toasts) while the window isn't focused
- Media keys and the Windows media flyout: provided by WebView2, which publishes
  YouTube Music's media session to Windows itself
- Volume remembered across launches; window size and position remembered
- Closing the window keeps the music playing in the tray (setting)
- Single instance: launching again brings the running window forward
- Keyboard shortcuts:

  | Action            | Shortcut           |
  |-------------------|--------------------|
  | Next / Previous   | Ctrl+→ / Ctrl+←    |
  | Volume            | Ctrl+↑ / Ctrl+↓    |
  | Like              | Ctrl+L             |
  | Shuffle / Repeat  | Ctrl+S / Ctrl+R    |
  | Search            | Ctrl+F             |
  | Back / Forward    | Alt+← / Alt+→      |
  | Reload            | F5                 |

## Next

- Tray flyout mini-player with search, library, Up Next and lyrics (the bridge
  already supports them; see [`shared/PROTOCOL.md`](../shared/PROTOCOL.md))
- Unified title bar like macOS (window buttons drawn by the page; the bridge
  already reports top-bar drags as `windowDrag`)
- Installer / auto-update

## Build

Requires the .NET 10 SDK. On Windows:

```bash
dotnet run --project windows/YTMusic
```

A self-contained single-file build (what CI produces):

```bash
dotnet publish windows/YTMusic/YTMusic.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o publish
```

The project also compiles on macOS and Linux (`EnableWindowsTargeting`), which
is handy for checking changes, but the app only runs on Windows.

## macOS → Windows mapping

| macOS (`macos/YTMusic/…`)                       | Windows (`windows/YTMusic/…`)                                   |
|-------------------------------------------------|-----------------------------------------------------------------|
| `WKUserScript` + `WKScriptMessageHandler`       | `AddScriptToExecuteOnDocumentCreatedAsync` + `WebMessageReceived` (`Bridge/WebBridge.cs`) |
| `PlayerModel` / `PlayerState`                   | `Player/PlayerModel.cs` / `Player/PlayerState.cs`               |
| `ThemeController`                               | `Shell/ThemeController.cs` (adds a frame guard; WebView2 injects into child frames too) |
| `VolumeKeeper` (UserDefaults)                   | `Player/VolumeKeeper.cs` (`%APPDATA%\YTMusic\settings.json`)    |
| `NowPlayingController` (MPNowPlayingInfoCenter) | WebView2's built-in media session integration                   |
| `StatusItemController` (menu bar)               | `Shell/TrayController.cs` (notification area)                   |
| `TrackNotifier`                                 | Tray balloon → Windows toast                                    |
| `WebNavigationHandler`                          | `Shell/NavigationPolicy.cs`                                     |
| Hide on close                                   | Hide to tray on close                                           |
