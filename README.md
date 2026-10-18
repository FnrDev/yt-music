# YT Music — native desktop clients

Unofficial native desktop apps for [YouTube Music](https://music.youtube.com).
Not affiliated with Google or YouTube.

| Platform | Status  | Stack                                   | Folder                 |
|----------|---------|-----------------------------------------|------------------------|
| macOS    | working | Swift 6, AppKit + SwiftUI, WKWebView    | [`macos/`](macos/)     |
| Windows  | planned | C#/.NET, WinUI 3, WebView2              | [`windows/`](windows/) |

## How it works

YouTube Music has no public playback API, and its audio streams are signed per
session, so a "fully native" player would have to scrape private endpoints that
break often and violate the terms of service. Each app instead hosts the real
web player in the **system web view** and puts native features around it:

```
┌──────────── native host (Swift / C#) ────────────┐
│  window · menus · media keys · Now Playing / SMTC │
│  tray / menu bar mini-player · notifications      │
│                     ▲      │                      │
│      state (JSON)   │      │  commands (JS call)  │
│                     │      ▼                      │
│  ┌─────────── system web view ─────────────────┐  │
│  │ music.youtube.com  +  shared/bridge/*.js     │  │
│  └─────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

The page-side code lives in [`shared/`](shared/) and is the same for every
platform:

- [`shared/bridge/ytm-bridge.js`](shared/bridge/ytm-bridge.js): injected script
  that reports player state and runs commands (play, next, seek, like, volume…)
- [`shared/PROTOCOL.md`](shared/PROTOCOL.md): the message format both hosts implement

When YouTube Music changes its DOM, the fix usually goes in `ytm-bridge.js`
alone, and every platform picks it up.

## macOS

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd macos && scripts/build.sh
```

```bash
open "macos/build/YT Music.app"
```

To work in Xcode, run `xcodegen generate` in `macos/` and open
`YTMusic.xcodeproj`. The project file is generated, so edit `project.yml`
rather than the `.xcodeproj`.

### Features

- Google sign-in persists across launches; non-YouTube links open in your browser
- **Menu bar controls**:
  - Left-click: mini-player with artwork, a seekable progress bar, play/pause,
    previous/next, like/dislike and volume
  - Right-click: quick controls menu
  - Optional: current track title next to the icon (Settings)
- Media keys, AirPods, Control Center and the Lock Screen through Now Playing
- Dock menu with playback controls
- Track-change notifications (only while the app is in the background; ads skipped)
- Closing the window keeps the music playing; click the Dock icon to bring it back
- Keyboard shortcuts:

  | Action             | Shortcut |
  |--------------------|----------|
  | Play/Pause         | ⌘↩       |
  | Next / Previous    | ⌘→ / ⌘←  |
  | Skip ±10 s         | ⌥⌘→ / ⌥⌘← |
  | Volume             | ⌘↑ / ⌘↓  |
  | Like / Dislike     | ⌘L / ⇧⌘L |
  | Search             | ⌘F       |
  | Back / Forward     | ⌘[ / ⌘]  |
  | Home               | ⇧⌘H      |

Debug builds enable the Safari Web Inspector: Safari → Develop → *your Mac* → YT Music.

### Layout

```
macos/
  project.yml                 XcodeGen spec (sandboxed, hardened runtime)
  scripts/build.sh            CLI build → build/YT Music.app
  scripts/make-icon.swift     renders the app icon
  YTMusic/
    App/        entry point, app delegate, main menu, shared menu actions
    Window/     main window + WKWebView, navigation policy
    Player/     PlayerModel (state), WebBridge, Now Playing, notifications, artwork
    MenuBar/    status item + SwiftUI mini-player popover
    Settings/   preferences
```

## Windows (planned)

See [`windows/README.md`](windows/README.md).
