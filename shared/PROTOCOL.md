# Host ⇄ page bridge protocol

Every native host (macOS today, Windows later) loads `https://music.youtube.com`
in a system web view and injects [`bridge/ytm-bridge.js`](bridge/ytm-bridge.js)
into the main frame at document end, in the **page** JS world (it needs the page's
own `#movie_player` API and `navigator.mediaSession`).

## Page → host

Messages are JSON **strings** posted via:

| Host    | Channel                                           | Read with                         |
|---------|---------------------------------------------------|-----------------------------------|
| macOS   | `window.webkit.messageHandlers.ytm.postMessage()` | `WKScriptMessage.body as? String` |
| Windows | `window.chrome.webview.postMessage()`             | `TryGetWebMessageAsString()`      |

### `ready`

```json
{ "type": "ready", "version": 1 }
```

Sent once per page load. Hosts should treat the page as reloaded (reset state).

### `state`

```json
{
  "type": "state",
  "state": {
    "hasTrack": true,
    "isAd": false,
    "videoId": "dQw4w9WgXcQ",
    "title": "Song",
    "artist": "Artist",
    "album": "Album",
    "artworkURL": "https://lh3.googleusercontent.com/...=w544-h544-l90-rj",
    "isPlaying": true,
    "position": 42.3,
    "duration": 213.0,
    "likeStatus": "like | dislike | indifferent",
    "volume": 80
  }
}
```

Sent whenever anything changes, and about once a second while playing.
Hosts should extrapolate position between messages rather than relying on them.

## Host → page

Evaluate `window.__ytmBridge?.command(name, arg)`:

| name          | arg            | effect                          |
|---------------|----------------|---------------------------------|
| `playPause`   | —              | toggle playback                 |
| `play`        | —              | play if paused                  |
| `pause`       | —              | pause if playing                |
| `next`        | —              | next track in queue             |
| `previous`    | —              | previous track / restart        |
| `seek`        | seconds (num)  | jump to position                |
| `setVolume`   | 0–100 (num)    | set volume                      |
| `like`        | —              | toggle thumbs-up                |
| `dislike`     | —              | toggle thumbs-down              |
| `focusSearch` | —              | focus the search box            |

## Bumping the protocol

Breaking changes bump `BRIDGE_VERSION` in the script. Hosts log a warning on an
unknown version but keep going; additive fields don't need a bump.
