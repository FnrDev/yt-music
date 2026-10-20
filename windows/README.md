# YT Music for Windows

The Windows app works great on Windows 10 and 11. It mirrors the macOS app's
architecture and reuses its page-side code unchanged.

## Install

Download `YTMusic-Setup-<version>-x64.exe` from the latest
[release](https://github.com/FnrDev/yt-music/releases/latest) and run it. It
installs per-user into `%LOCALAPPDATA%\Programs\YT Music` (no admin prompt),
adds Start menu and desktop shortcuts, and shows up in Settings → Apps for
uninstalling. Uninstalling keeps your settings and sign-in.

Prefer no installer? `YTMusic-<version>-x64-portable.exe` from the same release
runs as-is. Both need the WebView2 runtime, which ships with Windows 10/11.

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
- Auto-update (check GitHub releases on launch)

## Build

Requires the .NET 10 SDK. On Windows:

```bash
dotnet run --project windows/YTMusic
```

A self-contained single-file build (what CI produces):

```bash
dotnet publish windows/YTMusic/YTMusic.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o publish
```

The installer wraps that `publish\YTMusic.exe` with
[Inno Setup 6](https://jrsoftware.org/isinfo.php)
([`installer/YTMusic.iss`](installer/YTMusic.iss)) and lands in `dist\`:

```bash
iscc /DAppVersion=0.1.0 /DSourceDir=..\..\publish /DOutputDir=..\..\dist windows/installer/YTMusic.iss
```

The project also compiles on macOS and Linux (`EnableWindowsTargeting`), which
is handy for checking changes, but the app only runs on Windows.

## Releasing

Every push to `main` builds the portable exe and the installer on GitHub
Actions (as run artifacts). Pushing a version tag publishes a GitHub release
with both attached; the tag sets the app and installer version:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

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
