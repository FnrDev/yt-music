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

### `searchResults`

```json
{
  "type": "searchResults",
  "requestId": 7,
  "query": "balthazar",
  "results": [
    {
      "id": "UC…",
      "kind": "artist | album | playlist | song | video | podcast | episode | page",
      "title": "Balthazar",
      "subtitle": "Artist • 160K monthly audience",
      "thumbnailURL": "https://…",
      "videoId": null,
      "playlistId": null,
      "browseId": "UC…",
      "pageType": "MUSIC_PAGE_TYPE_ARTIST"
    }
  ],
  "error": "only present when the search failed"
}
```

Reply to a `search` command. The first result is YT Music's top result when it
has one. Hosts should drop replies whose `requestId` isn't the latest.

### `windowDrag` / `windowZoom`

```json
{ "type": "windowDrag" }
```

Sent on a mouse-down (`windowDrag`) or double-click (`windowZoom`) on an empty
part of YT Music's top bar. Hosts that draw the page under their title bar
treat these like title-bar clicks: start a window move, or zoom/minimise per
the system setting. Other hosts ignore them.

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
| `setVolume`   | 0–100 (num)    | set volume (YT Music's slider scale; persisted by the site) |
| `like`        | —              | toggle thumbs-up                |
| `dislike`     | —              | toggle thumbs-down              |
| `focusSearch` | —              | focus the search box            |
| `search`      | `{query, requestId}` | search; replies with `searchResults` |
| `playItem`    | `{videoId, playlistId?}` | play a result (in-app navigation) |
| `openItem`    | `{browseId, pageType?}` | open an artist/album/playlist page |
| `openSearch`  | query (string) | show the full search results page |

## Themes

Optional stylesheets live in [`themes/`](themes/). Hosts inject the selected one
as a single `<style id="ytm-host-theme">` element, appended last so it wins
over the site's styles, at document start (re-appended on `DOMContentLoaded`).
To switch live, replace that element's text, or remove it for the stock look.

Theme CSS must not hide `ytmusic-browse-response .background-gradient`
(`display: none` collapses all page content); clear its background instead.

## Bumping the protocol

Breaking changes bump `BRIDGE_VERSION` in the script. Hosts log a warning on an
unknown version but keep going; additive fields don't need a bump.
