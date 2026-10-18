// Spotify-style theme: behaviour that CSS alone can't provide.
//
// Elapsed and total time flanking the progress bar. YT Music only has a single
// combined "0:45 / 3:29" readout (hidden in most layouts), so the theme draws
// its own two labels and keeps them in sync with the media element.
//
// Injected by the host together with spotify-style.css. It must register
// window.__ytmThemeCleanup so the host can remove it when the theme changes.
(() => {
  const ELEMENT_ATTR = 'data-ytm-theme-element';

  const format = (seconds) => {
    const total = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = String(total % 60).padStart(2, '0');
    return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
  };

  const video = () => document.querySelector('video.html5-main-video') || document.querySelector('video');
  const progressWrapper = () => document.querySelector('ytmusic-miniplayer .ytMusicMiniPlayerProgressBarWrapper');

  let elapsed = null;
  let total = null;

  const ensureLabels = () => {
    const wrapper = progressWrapper();
    if (!wrapper) return false;
    if (elapsed?.isConnected && elapsed.parentElement === wrapper) return true;
    elapsed?.remove();
    total?.remove();
    elapsed = document.createElement('span');
    total = document.createElement('span');
    elapsed.className = 'sp-time sp-time-elapsed';
    total.className = 'sp-time sp-time-total';
    for (const label of [elapsed, total]) {
      label.setAttribute(ELEMENT_ATTR, '');
      label.setAttribute('aria-hidden', 'true');
      wrapper.appendChild(label);
    }
    return true;
  };

  const update = () => {
    if (!ensureLabels()) return;
    const v = video();
    elapsed.textContent = format(v?.currentTime);
    total.textContent = format(v?.duration);
  };

  const onMediaEvent = () => update();
  const MEDIA_EVENTS = ['timeupdate', 'durationchange', 'seeked', 'loadedmetadata', 'emptied'];
  for (const event of MEDIA_EVENTS) document.addEventListener(event, onMediaEvent, true);
  // The player bar is re-rendered on some navigations; re-attach if needed.
  const timer = setInterval(update, 1000);
  update();

  window.__ytmThemeCleanup = () => {
    clearInterval(timer);
    for (const event of MEDIA_EVENTS) document.removeEventListener(event, onMediaEvent, true);
    document.querySelectorAll(`[${ELEMENT_ATTR}]`).forEach((el) => el.remove());
    delete window.__ytmThemeCleanup;
  };
})();
