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
    shuffle: [
      'ytmusic-player-bar .shuffle',
      'ytmusic-miniplayer .ytmusicPlayerControlsShuffleButton button',
    ],
    repeat: [
      'ytmusic-player-bar .repeat',
      'ytmusic-miniplayer .ytmusicPlayerControlsRepeatButton button',
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

  // YT Music's app store (Redux-style); holds the queue, shuffle and repeat.
  const appStore = () => $('ytmusic-player-queue')?.queue?.store || null;
  const queueState = () => {
    try { return appStore()?.getState?.().queue || null; } catch (_) { return null; }
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
      shuffle: Boolean(queueState()?.shuffleEnabled),
      repeatMode: ({ ALL: 'all', ONE: 'one' })[queueState()?.repeatMode] || 'none',
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

  // Queue actions ("Play next" / "Add to queue") for the latest results, kept
  // here by result id; the host refers to them with queueResult({id}).
  const resultMenus = new Map();

  const queueMenuItems = (menu) => {
    const entries = (menu?.menuRenderer?.items || []).map((item) => item.menuServiceItemRenderer).filter(Boolean);
    const at = (position) => entries.find((m) => m.serviceEndpoint?.queueAddEndpoint?.queueInsertPosition === position);
    return { next: at('INSERT_AFTER_CURRENT_VIDEO'), end: at('INSERT_AT_END') };
  };

  const resultFrom = ({ title, subtitle, thumbnail, watch, watchPlaylist, browse, menu }) => {
    if (!title || (!watch?.videoId && !browse?.browseId)) return null;
    const pageType = browse?.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType;
    const videoType = watch?.watchEndpointMusicSupportedConfigs?.watchEndpointMusicConfig?.musicVideoType;
    const kind = browse?.browseId
      ? (KIND_BY_PAGE_TYPE[pageType] || 'page')
      : (videoType === 'MUSIC_VIDEO_TYPE_ATV' ? 'song' : 'video');
    const id = browse?.browseId || watch.videoId;
    const queue = queueMenuItems(menu);
    if (queue.next || queue.end) resultMenus.set(id, queue);
    return {
      id,
      kind,
      title,
      subtitle: subtitle || '',
      thumbnailURL: thumbnail,
      videoId: watch?.videoId || null,
      playlistId: watch?.playlistId || watchPlaylist?.playlistId || null,
      browseId: browse?.browseId || null,
      pageType: pageType || null,
      canQueue: Boolean(queue.next || queue.end),
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
      menu: item.menu,
    });
  };

  // Grid cards (library playlists, albums, mixes).
  const fromTwoRow = (item) => {
    const play = item.thumbnailOverlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint;
    return resultFrom({
      title: runsText(item.title),
      subtitle: runsText(item.subtitle),
      thumbnail: thumbnailOf(item.thumbnailRenderer),
      watch: item.navigationEndpoint?.watchEndpoint || null,
      watchPlaylist: play?.watchPlaylistEndpoint || play?.watchEndpoint,
      browse: item.navigationEndpoint?.browseEndpoint,
      menu: item.menu,
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
      menu: card.menu,
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
      if (node.musicTwoRowItemRenderer) {
        add(fromTwoRow(node.musicTwoRowItemRenderer));
        return;
      }
      for (const value of Object.values(node)) walk(value, depth + 1);
    };
    walk(response, 0);
    return results;
  };

  // Signed-in requests (history, library) must say which session they're
  // for, the way YT Music's own requests do: a SAPISIDHASH derived from the
  // session cookie plus the account index. Public ones (search) work without.
  const sessionCookie = (name) =>
    document.cookie.split('; ').find((c) => c.startsWith(`${name}=`))?.slice(name.length + 1);

  const authHeaders = async () => {
    const sapisid = sessionCookie('SAPISID') || sessionCookie('__Secure-3PAPISID');
    if (!sapisid || !crypto?.subtle) return {};
    const timestamp = Math.floor(Date.now() / 1000);
    const digest = await crypto.subtle.digest(
      'SHA-1', new TextEncoder().encode(`${timestamp} ${sapisid} ${location.origin}`));
    const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    return {
      Authorization: `SAPISIDHASH ${timestamp}_${hash}`,
      'X-Goog-AuthUser': String(window.ytcfg?.get?.('SESSION_INDEX') ?? 0),
      'X-Origin': location.origin,
    };
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
        ...(await authHeaders()),
      },
      body: JSON.stringify({ context, ...body }),
    });
    if (!response.ok) throw new Error(`Search failed (${response.status})`);
    return response.json();
  };

  // Filter chips (Songs, Artists, Albums…) exactly as YT Music offers them.
  const collectFilters = (response) => {
    const filters = [];
    const walk = (node, depth) => {
      if (!node || typeof node !== 'object' || depth > 30) return;
      const chip = node.chipCloudChipRenderer;
      if (chip) {
        const params = chip.navigationEndpoint?.searchEndpoint?.params;
        const title = runsText(chip.text);
        if (title && params) filters.push({ title, params, isSelected: Boolean(chip.isSelected) });
        return;
      }
      for (const value of Object.values(node)) walk(value, depth + 1);
    };
    walk(response, 0);
    return filters;
  };

  const search = async ({ query, params, requestId }) => {
    try {
      const response = await innertube('search', { query, ...(params ? { params } : {}) });
      const results = collectResults(response).slice(0, 40);
      post({ type: 'searchResults', requestId, query, results, filters: collectFilters(response) });
    } catch (error) {
      post({ type: 'searchResults', requestId, query, results: [], filters: [], error: String(error.message || error) });
    }
  };

  // ---- Library, queue and lyrics ----------------------------------------

  const library = async ({ requestId }) => {
    const settle = (promise) => promise.then(collectResults, () => []);
    const [recent, playlists] = await Promise.all([
      settle(innertube('browse', { browseId: 'FEmusic_history' })),
      settle(innertube('browse', { browseId: 'FEmusic_liked_playlists' })),
    ]);
    post({ type: 'library', requestId, recent: recent.slice(0, 12), playlists: playlists.slice(0, 30) });
  };

  // Each queue entry can render twice: its primary version and an alternate
  // "counterpart" (the song/video toggle). Only primaries are in the queue
  // that playback follows.
  const queueItems = () => [...document.querySelectorAll('ytmusic-player-queue ytmusic-player-queue-item')]
    .filter((item) => !item.closest('#counterpart-renderer'));

  const queue = ({ requestId }) => {
    // Guard against more than one element marked selected: only the first
    // is the current track.
    let currentSeen = false;
    const items = queueItems().slice(0, 80).map((item, index) => {
      const data = item.data || {};
      const isCurrent = !currentSeen && item.hasAttribute('selected');
      if (isCurrent) currentSeen = true;
      return data.videoId ? {
        index,
        videoId: data.videoId,
        title: runsText(data.title),
        subtitle: runsText(data.shortBylineText || data.longBylineText),
        duration: runsText(data.lengthText),
        thumbnailURL: thumbnailOf(data.thumbnail),
        isCurrent,
      } : null;
    }).filter(Boolean);
    post({ type: 'queue', requestId, items });
  };

  const findDeep = (node, predicate, depth = 0) => {
    if (!node || typeof node !== 'object' || depth > 40) return null;
    if (predicate(node)) return node;
    for (const value of Object.values(node)) {
      const found = findDeep(value, predicate, depth + 1);
      if (found) return found;
    }
    return null;
  };

  // Plain lyrics from the track's "Lyrics" tab, with YT Music's source credit.
  const lyrics = async ({ requestId }) => {
    const videoId = moviePlayer()?.getVideoData?.().video_id || null;
    try {
      if (!videoId) throw new Error('Nothing is playing');
      const next = await innertube('next', { videoId });
      const tab = findDeep(next, (o) =>
        o.tabRenderer?.endpoint?.browseEndpoint?.browseEndpointContextSupportedConfigs
          ?.browseEndpointContextMusicConfig?.pageType === 'MUSIC_PAGE_TYPE_TRACK_LYRICS')?.tabRenderer;
      const browseId = tab?.endpoint?.browseEndpoint?.browseId;
      let text = null;
      let source = null;
      if (browseId) {
        const shelf = findDeep(await innertube('browse', { browseId }), (o) => o.musicDescriptionShelfRenderer)
          ?.musicDescriptionShelfRenderer;
        text = runsText(shelf?.description) || null;
        source = runsText(shelf?.footer) || null;
      }
      post({ type: 'lyrics', requestId, videoId, text, source });
    } catch (error) {
      post({ type: 'lyrics', requestId, videoId, text: null, source: null, error: String(error.message || error) });
    }
  };

  // Runs a YT Music menu entry (e.g. "Add to queue") through YT Music's own
  // menu-item component, exactly as a click on its menu would.
  const runMenuItem = (data) => {
    const app = $('ytmusic-app');
    if (!app || !data) return false;
    const item = document.createElement('ytmusic-menu-service-item-renderer');
    item.hidden = true;
    item.data = data;
    app.appendChild(item);
    setTimeout(() => {
      item.click();
      setTimeout(() => item.remove(), 1000);
    }, 50);
    return true;
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
    library,
    queue,
    lyrics,
    toggleShuffle: () => clickFirst(...SELECTORS.shuffle),
    cycleRepeat: () => clickFirst(...SELECTORS.repeat),
    queueResult: ({ id, position }) => runMenuItem(resultMenus.get(id)?.[position === 'end' ? 'end' : 'next']),
    playQueueItem: async ({ index, videoId }) => {
      const items = queueItems();
      if (items[index]?.data?.videoId !== videoId) return false; // queue changed; don't jump to the wrong track
      const current = items.findIndex((item) => item.hasAttribute('selected'));
      const playingId = () => moviePlayer()?.getVideoData?.().video_id;
      // Queue rows only render on the player page, and YT Music ignores
      // navigation into the queue it is already playing. Up Next lists only
      // the current track and what follows, so step forward with Next (the
      // one path that reliably follows the queue), checking after each step.
      if (index > current) {
        const maxSteps = Math.min(index - current + 2, 50);
        for (let step = 0; step < maxSteps && playingId() !== videoId; step++) {
          const before = playingId();
          commands.next();
          for (let wait = 0; wait < 20 && playingId() === before; wait++) {
            await new Promise((resolve) => setTimeout(resolve, 150));
          }
        }
      }
      if (playingId() === videoId && !isPlaying()) togglePlayback();
      return playingId() === videoId;
    },
    playPlaylist: ({ playlistId }) => navigate(
      { watchPlaylistEndpoint: { playlistId } },
      `/watch?list=${encodeURIComponent(playlistId)}`,
    ),
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
