// YT Music host bridge.
//
// Injected into music.youtube.com by every native host (macOS WKWebView today,
// Windows WebView2 later). It observes the page's player and reports state to
// the host, and exposes `window.__ytmBridge.command(name, arg)` so the host can
// drive playback. See shared/PROTOCOL.md for the message format.
//
// Keep this file host-agnostic: no platform-specific code beyond `post()`.
(() => {
  'use strict';
  if (window.__ytmBridge || window.top !== window) return;

  const BRIDGE_VERSION = 1;

  // ---- Transport ---------------------------------------------------------

  const post = (message) => {
    const json = JSON.stringify(message);
    try {
      if (window.webkit?.messageHandlers?.ytm) {
        window.webkit.messageHandlers.ytm.postMessage(json); // macOS / WKWebView
      } else if (window.chrome?.webview) {
        window.chrome.webview.postMessage(json); // Windows / WebView2
      }
    } catch (_) {
      // Host went away; nothing useful to do.
    }
  };

  // ---- DOM helpers -------------------------------------------------------
  //
  // YouTube Music serves two player bars depending on browser and rollout:
  //   - classic: <ytmusic-player-bar> with Polymer controls
  //   - newer:   <ytmusic-miniplayer> with <ytmusic-wiz-player-controls>
  // Every lookup below lists the classic selector first, then the newer one.
  // Selectors rely on structure and class names, never on (localized) labels.

  const $ = (selector) => document.querySelector(selector);
  const firstOf = (...selectors) => {
    for (const selector of selectors) {
      const el = $(selector);
      if (el) return el;
    }
    return null;
  };
  const playerBar = () => firstOf('ytmusic-player-bar', 'ytmusic-miniplayer');
  const moviePlayer = () => $('#movie_player');
  const video = () => $('video.html5-main-video') || $('video');

  const clickFirst = (...selectors) => {
    const el = firstOf(...selectors);
    el?.click();
    return Boolean(el);
  };

  const textOf = (...selectors) => (firstOf(...selectors)?.textContent || '').trim();

  const SELECTORS = {
    playPause: [
      'ytmusic-player-bar #play-pause-button',
      'ytmusic-miniplayer .ytmusicPlayerControlsPlayPauseButton button',
    ],
    next: [
      'ytmusic-player-bar .next-button',
      'ytmusic-miniplayer .ytmusicPlayerControlsNextButton button',
    ],
    previous: [
      'ytmusic-player-bar .previous-button',
      'ytmusic-miniplayer .ytmusicPlayerControlsPreviousButton button',
    ],
    like: [
      'ytmusic-player-bar ytmusic-like-button-renderer #button-shape-like button',
      'ytmusic-miniplayer like-button-view-model button',
    ],
    dislike: [
      'ytmusic-player-bar ytmusic-like-button-renderer #button-shape-dislike button',
      'ytmusic-miniplayer dislike-button-view-model button',
    ],
    artwork: [
      'ytmusic-player-bar img.image',
      'ytmusic-miniplayer img',
    ],
    title: [
      'ytmusic-player-bar .title',
    ],
    byline: [
      'ytmusic-player-bar .byline',
    ],
  };

  // ---- State -------------------------------------------------------------

  const artworkSize = (art) => {
    const match = /(\d+)x(\d+)/.exec(art.sizes || '');
    return match ? Number(match[1]) * Number(match[2]) : 0;
  };

  const upscaleArtwork = (url) => {
    if (!url) return null;
    // Video thumbnails: hqdefault/sddefault have black letterbox bars baked in.
    // hq720 is a clean 1280×720 frame (hosts fall back to mqdefault if missing).
    const video = /^https?:\/\/i\d*\.ytimg\.com\/vi(?:_webp)?\/([^/]+)\//.exec(url);
    if (video) return `https://i.ytimg.com/vi/${video[1]}/hq720.jpg`;
    // googleusercontent thumbnails encode their size in the URL; ask for a big one.
    return url.replace(/=w\d+-h\d+[^&?#]*/, '=w544-h544-l90-rj');
  };

  const currentArtwork = () => {
    // Read the attribute: `.src` on an empty <img> resolves to the page URL.
    const barSrc = firstOf(...SELECTORS.artwork)?.getAttribute('src');
    const barArt = barSrc && /^https?:/.test(barSrc) ? barSrc : null;
    // Songs have square album art on googleusercontent; prefer it over the
    // 16:9 video thumbnail Media Session tends to report.
    if (barArt && barArt.includes('googleusercontent.com')) return upscaleArtwork(barArt);

    const artwork = navigator.mediaSession?.metadata?.artwork;
    if (artwork && artwork.length) {
      const best = [...artwork].sort((a, b) => artworkSize(b) - artworkSize(a))[0];
      return upscaleArtwork(best.src);
    }
    return upscaleArtwork(barArt);
  };

  const likeStatus = () => {
    // Classic player: a single attribute on the renderer.
    const status = $('ytmusic-player-bar ytmusic-like-button-renderer')?.getAttribute('like-status');
    if (status === 'LIKE') return 'like';
    if (status === 'DISLIKE') return 'dislike';
    if (status) return 'indifferent';
    // Newer player: toggle buttons with aria-pressed.
    if ($(SELECTORS.like[1])?.getAttribute('aria-pressed') === 'true') return 'like';
    if ($(SELECTORS.dislike[1])?.getAttribute('aria-pressed') === 'true') return 'dislike';
    return 'indifferent';
  };

  // Volume goes through YT Music's own slider, never the player API directly.
  // The slider is on a perceptual 0–100 scale (55 ≈ player volume 24), and
  // only changes made through it are saved by the site (in its PREF cookie)
  // and shown in its UI. Setting the player directly desyncs both.
  //
  // Classic player: <tp-yt-paper-slider> (a second one is used in narrow
  // windows; YT Music keeps the two in sync). Newer player: a range <input>.
  const volumeControl = () => {
    const paper = $('ytmusic-player-bar #volume-slider');
    if (paper) {
      return {
        get: () => Number(paper.value),
        set: (value) => {
          paper.value = value;
          paper.dispatchEvent(new CustomEvent('change', { bubbles: true }));
        },
      };
    }
    const input = firstOf(
      'ytmusic-miniplayer .ytMusicMiniPlayerVolumeWrapper input[type="range"]',
      'ytmusic-miniplayer input[type="range"]:not(.ytMusicMiniPlayerProgressBar)',
    );
    if (input) {
      return {
        get: () => Number(input.value),
        set: (value) => {
          // Use the native setter so the page's listeners see a real change.
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(input, String(value));
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        },
      };
    }
    return null;
  };

  const currentVolume = () => {
    const value = volumeControl()?.get();
    if (Number.isFinite(value)) return Math.round(value);
    const player = moviePlayer();
    if (player?.getVolume) return Math.round(player.getVolume());
    const v = video();
    return v ? Math.round(v.volume * 100) : 100;
  };

  const snapshot = () => {
    const v = video();
    const meta = navigator.mediaSession?.metadata;
    const title = meta?.title || textOf(...SELECTORS.title);
    const byline = textOf(...SELECTORS.byline);
    const videoData = moviePlayer()?.getVideoData?.();
    const duration = v && Number.isFinite(v.duration) ? v.duration : 0;

    return {
      hasTrack: Boolean(title && v && v.currentSrc),
      isAd: Boolean(moviePlayer()?.classList.contains('ad-showing')),
      videoId: videoData?.video_id || null,
      title: title || '',
      artist: meta?.artist || byline.split('•')[0]?.trim() || '',
      album: meta?.album || '',
      artworkURL: currentArtwork(),
      isPlaying: Boolean(v && !v.paused && !v.ended),
      position: v ? v.currentTime || 0 : 0,
      duration,
      likeStatus: likeStatus(),
      volume: currentVolume(),
    };
  };

  let lastKey = '';
  const report = (force = false) => {
    const state = snapshot();
    // Position is included in the key at 1 s granularity so hosts get a steady
    // heartbeat while playing without being spammed by `timeupdate`.
    const key = JSON.stringify({ ...state, position: Math.floor(state.position) });
    if (!force && key === lastKey) return;
    lastKey = key;
    post({ type: 'state', state });
  };

  // ---- Search ------------------------------------------------------------
  //
  // Runs the same request YT Music's own search box makes, in the signed-in
  // page, and reduces the response to simple result records for the host.

  const runsText = (text) =>
    (text?.runs || []).map((run) => run.text).join('') || text?.simpleText || '';

  const thumbnailOf = (renderer) => {
    const list = renderer?.musicThumbnailRenderer?.thumbnail?.thumbnails
      || renderer?.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails
      || renderer?.thumbnails || [];
    return list.length ? list[list.length - 1].url : null;
  };

  const KIND_BY_PAGE_TYPE = {
    MUSIC_PAGE_TYPE_ARTIST: 'artist',
    MUSIC_PAGE_TYPE_USER_CHANNEL: 'artist',
    MUSIC_PAGE_TYPE_ALBUM: 'album',
    MUSIC_PAGE_TYPE_AUDIOBOOK: 'album',
    MUSIC_PAGE_TYPE_PLAYLIST: 'playlist',
    MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE: 'podcast',
    MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE: 'episode',
  };

  const resultFrom = ({ title, subtitle, thumbnail, watch, browse }) => {
    if (!title || (!watch?.videoId && !browse?.browseId)) return null;
    const pageType = browse?.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType;
    const videoType = watch?.watchEndpointMusicSupportedConfigs?.watchEndpointMusicConfig?.musicVideoType;
    const kind = browse?.browseId
      ? (KIND_BY_PAGE_TYPE[pageType] || 'page')
      : (videoType === 'MUSIC_VIDEO_TYPE_ATV' ? 'song' : 'video');
    return {
      id: browse?.browseId || watch.videoId,
      kind,
      title,
      subtitle: subtitle || '',
      thumbnailURL: thumbnail,
      videoId: watch?.videoId || null,
      playlistId: watch?.playlistId || null,
      browseId: browse?.browseId || null,
      pageType: pageType || null,
    };
  };

  const fromListItem = (item) => {
    const columns = (item.flexColumns || []).map((c) => c.musicResponsiveListItemFlexColumnRenderer?.text);
    const titleRun = columns[0]?.runs?.[0];
    return resultFrom({
      title: runsText(columns[0]),
      subtitle: columns.slice(1).map(runsText).filter(Boolean).join(' • '),
      thumbnail: thumbnailOf(item.thumbnail),
      watch: item.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer
        ?.playNavigationEndpoint?.watchEndpoint
        || titleRun?.navigationEndpoint?.watchEndpoint
        || (item.playlistItemData?.videoId ? { videoId: item.playlistItemData.videoId } : null),
      browse: item.navigationEndpoint?.browseEndpoint || titleRun?.navigationEndpoint?.browseEndpoint,
    });
  };

  const fromCard = (card) => {
    const endpoint = card.title?.runs?.[0]?.navigationEndpoint || card.onTap || {};
    return resultFrom({
      title: runsText(card.title),
      subtitle: runsText(card.subtitle),
      thumbnail: thumbnailOf(card.thumbnail),
      watch: endpoint.watchEndpoint,
      browse: endpoint.browseEndpoint,
    });
  };

  // Walks the response for result renderers, in document order, so the shape
  // of the surrounding shelves can change without breaking this.
  const collectResults = (response) => {
    const results = [];
    const seen = new Set();
    const add = (result) => {
      if (result && !seen.has(result.id)) {
        seen.add(result.id);
        results.push(result);
      }
    };
    const walk = (node, depth) => {
      if (!node || typeof node !== 'object' || depth > 40) return;
      if (node.musicCardShelfRenderer) add(fromCard(node.musicCardShelfRenderer));
      if (node.musicResponsiveListItemRenderer) {
        add(fromListItem(node.musicResponsiveListItemRenderer));
        return;
      }
      for (const value of Object.values(node)) walk(value, depth + 1);
    };
    walk(response, 0);
    return results;
  };

  const innertube = async (endpoint, body) => {
    const cfg = window.ytcfg;
    const context = cfg?.get?.('INNERTUBE_CONTEXT');
    if (!context) throw new Error('YT Music is still loading');
    const key = cfg.get('INNERTUBE_API_KEY');
    const response = await fetch(`/youtubei/v1/${endpoint}?prettyPrint=false${key ? `&key=${key}` : ''}`, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
        'X-Youtube-Client-Name': String(cfg.get('INNERTUBE_CONTEXT_CLIENT_NAME') ?? 67),
        'X-Youtube-Client-Version': String(cfg.get('INNERTUBE_CLIENT_VERSION') ?? ''),
      },
      body: JSON.stringify({ context, ...body }),
    });
    if (!response.ok) throw new Error(`Search failed (${response.status})`);
    return response.json();
  };

  const search = async ({ query, requestId }) => {
    try {
      const results = collectResults(await innertube('search', { query })).slice(0, 30);
      post({ type: 'searchResults', requestId, query, results });
    } catch (error) {
      post({ type: 'searchResults', requestId, query, results: [], error: String(error.message || error) });
    }
  };

  // In-app navigation through YT Music's own router (no page reload).
  const navigate = (endpoint, fallbackPath) => {
    const app = $('ytmusic-app');
    if (app) {
      app.dispatchEvent(new CustomEvent('yt-navigate', { bubbles: true, composed: true, detail: { endpoint } }));
    } else {
      location.assign(fallbackPath);
    }
  };

  // ---- Commands ----------------------------------------------------------

  const isPlaying = () => {
    const v = video();
    return Boolean(v && !v.paused && !v.ended);
  };

  const togglePlayback = () =>
    clickFirst(...SELECTORS.playPause)
      || (isPlaying() ? video()?.pause() : video()?.play());

  const commands = {
    playPause: togglePlayback,
    play: () => { if (!isPlaying()) togglePlayback(); },
    pause: () => { if (isPlaying()) togglePlayback(); },
    next: () => clickFirst(...SELECTORS.next),
    previous: () => clickFirst(...SELECTORS.previous),
    seek: (seconds) => {
      const v = video();
      if (v && Number.isFinite(seconds)) v.currentTime = Math.max(0, seconds);
    },
    setVolume: (volume) => {
      const clamped = Math.max(0, Math.min(100, Math.round(volume)));
      const control = volumeControl();
      if (control) {
        control.set(clamped);
        return;
      }
      // Last resort when no slider is on the page; not saved by the site.
      const player = moviePlayer();
      if (player?.setVolume) {
        player.setVolume(clamped);
        if (clamped > 0) player.unMute?.();
      } else if (video()) {
        video().volume = clamped / 100;
      }
    },
    like: () => clickFirst(...SELECTORS.like),
    dislike: () => clickFirst(...SELECTORS.dislike),
    search,
    playItem: ({ videoId, playlistId }) => navigate(
      { watchEndpoint: { videoId, ...(playlistId ? { playlistId } : {}) } },
      `/watch?v=${encodeURIComponent(videoId)}${playlistId ? `&list=${encodeURIComponent(playlistId)}` : ''}`,
    ),
    openItem: ({ browseId, pageType }) => navigate(
      {
        browseEndpoint: {
          browseId,
          ...(pageType ? { browseEndpointContextSupportedConfigs: { browseEndpointContextMusicConfig: { pageType } } } : {}),
        },
      },
      `/browse/${encodeURIComponent(browseId)}`,
    ),
    openSearch: (query) => navigate({ searchEndpoint: { query } }, `/search?q=${encodeURIComponent(query)}`),
    focusSearch: () => {
      clickFirst('ytmusic-search-box #placeholder', 'ytmusic-search-box');
      const input = $('ytmusic-search-box input');
      input?.focus();
      input?.select?.();
    },
  };

  const command = (name, arg) => {
    const fn = commands[name];
    if (!fn) return false;
    try {
      fn(arg);
    } finally {
      // Let the page react, then push fresh state rather than waiting for the tick.
      setTimeout(() => report(true), 150);
    }
    return true;
  };

  // ---- Wiring ------------------------------------------------------------

  // Media events don't bubble, but capture-phase listeners on document see them.
  for (const event of ['play', 'pause', 'playing', 'seeked', 'durationchange',
    'loadedmetadata', 'ended', 'volumechange', 'emptied']) {
    document.addEventListener(event, () => report(true), true);
  }
  // The newer player's volume input changes before the media element does.
  document.addEventListener('input', (event) => {
    if (event.target?.closest?.('ytmusic-miniplayer, ytmusic-player-bar')) report();
  }, true);

  // Like status and metadata live in the player bar's DOM attributes.
  const observeBar = () => {
    const bar = playerBar();
    if (!bar) return false;
    new MutationObserver(() => report()).observe(bar, {
      subtree: true,
      attributes: true,
      attributeFilter: ['like-status', 'aria-pressed', 'title', 'src'],
    });
    return true;
  };
  if (!observeBar()) {
    const waitForBar = setInterval(() => { if (observeBar()) clearInterval(waitForBar); }, 1000);
  }

  // ---- Window chrome -----------------------------------------------------
  //
  // Hosts that draw the page under their title bar (the macOS Spotify-style
  // theme) let empty parts of YT Music's top bar act as a title bar. Hosts
  // that don't need this ignore the messages.
  const DRAG_SURFACES = 'ytmusic-nav-bar, #nav-bar-background';
  const INTERACTIVE = 'a, button, input, [role="button"], yt-icon-button, '
    + 'tp-yt-paper-icon-button, ytmusic-search-box, ytmusic-settings-button, ytmusic-logo';
  const isDragSurface = (target) =>
    target instanceof Element && target.closest(DRAG_SURFACES) && !target.closest(INTERACTIVE);
  document.addEventListener('mousedown', (event) => {
    if (event.button === 0 && event.detail === 1 && isDragSurface(event.target)) post({ type: 'windowDrag' });
  }, true);
  document.addEventListener('dblclick', (event) => {
    if (isDragSurface(event.target)) post({ type: 'windowZoom' });
  }, true);

  setInterval(report, 1000);

  window.__ytmBridge = Object.freeze({ version: BRIDGE_VERSION, command, snapshot });
  post({ type: 'ready', version: BRIDGE_VERSION });
  report(true);
})();
