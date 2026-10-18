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

  const $ = (selector) => document.querySelector(selector);
  const playerBar = () => $('ytmusic-player-bar');
  const moviePlayer = () => $('#movie_player');
  const video = () => $('video.html5-main-video') || $('video');

  const clickFirst = (...selectors) => {
    for (const selector of selectors) {
      const el = $(selector);
      if (el) {
        el.click();
        return true;
      }
    }
    return false;
  };

  const textOf = (selector) => ($(selector)?.textContent || '').trim();

  // ---- State -------------------------------------------------------------

  const artworkSize = (art) => {
    const match = /(\d+)x(\d+)/.exec(art.sizes || '');
    return match ? Number(match[1]) * Number(match[2]) : 0;
  };

  const upscaleArtwork = (url) => {
    if (!url) return null;
    // googleusercontent thumbnails encode their size in the URL; ask for a big one.
    return url.replace(/=w\d+-h\d+[^&?#]*/, '=w544-h544-l90-rj');
  };

  const currentArtwork = () => {
    // Read the attribute: `.src` on an empty <img> resolves to the page URL.
    const barSrc = playerBar()?.querySelector('img.image')?.getAttribute('src');
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
    const status = playerBar()
      ?.querySelector('ytmusic-like-button-renderer')
      ?.getAttribute('like-status');
    switch (status) {
      case 'LIKE': return 'like';
      case 'DISLIKE': return 'dislike';
      default: return 'indifferent';
    }
  };

  const currentVolume = () => {
    const player = moviePlayer();
    if (player?.getVolume) return Math.round(player.getVolume());
    const v = video();
    return v ? Math.round(v.volume * 100) : 100;
  };

  const snapshot = () => {
    const v = video();
    const meta = navigator.mediaSession?.metadata;
    const title = meta?.title || textOf('ytmusic-player-bar .title');
    const byline = textOf('ytmusic-player-bar .byline');
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

  // ---- Commands ----------------------------------------------------------

  const isPlaying = () => {
    const v = video();
    return Boolean(v && !v.paused && !v.ended);
  };

  const togglePlayback = () =>
    clickFirst('ytmusic-player-bar #play-pause-button', 'ytmusic-player-bar .play-pause-button')
      || (isPlaying() ? video()?.pause() : video()?.play());

  const commands = {
    playPause: togglePlayback,
    play: () => { if (!isPlaying()) togglePlayback(); },
    pause: () => { if (isPlaying()) togglePlayback(); },
    next: () => clickFirst('ytmusic-player-bar .next-button', 'ytmusic-player-bar [aria-label="Next"]'),
    previous: () => clickFirst('ytmusic-player-bar .previous-button', 'ytmusic-player-bar [aria-label="Previous"]'),
    seek: (seconds) => {
      const v = video();
      if (v && Number.isFinite(seconds)) v.currentTime = Math.max(0, seconds);
    },
    setVolume: (volume) => {
      const clamped = Math.max(0, Math.min(100, Math.round(volume)));
      const player = moviePlayer();
      if (player?.setVolume) {
        player.setVolume(clamped);
        if (clamped > 0) player.unMute?.();
      } else if (video()) {
        video().volume = clamped / 100;
      }
    },
    like: () => clickFirst(
      'ytmusic-player-bar ytmusic-like-button-renderer #button-shape-like button',
      'ytmusic-player-bar ytmusic-like-button-renderer .like',
    ),
    dislike: () => clickFirst(
      'ytmusic-player-bar ytmusic-like-button-renderer #button-shape-dislike button',
      'ytmusic-player-bar ytmusic-like-button-renderer .dislike',
    ),
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

  // Like status and metadata live in the player bar's DOM attributes.
  const observeBar = () => {
    const bar = playerBar();
    if (!bar) return false;
    new MutationObserver(() => report()).observe(bar, {
      subtree: true,
      attributes: true,
      attributeFilter: ['like-status', 'title', 'src'],
    });
    return true;
  };
  if (!observeBar()) {
    const waitForBar = setInterval(() => { if (observeBar()) clearInterval(waitForBar); }, 1000);
  }

  setInterval(report, 1000);

  window.__ytmBridge = Object.freeze({ version: BRIDGE_VERSION, command, snapshot });
  post({ type: 'ready', version: BRIDGE_VERSION });
  report(true);
})();
