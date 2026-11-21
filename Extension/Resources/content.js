// Floatr content script. Runs in every frame of every page.
//
// The top frame coordinates: it receives commands from the extension, asks every frame
// (including cross-origin iframes) for its best video, and tells the winning frame to act.
(() => {
  'use strict';
  if (window.__floatrLoaded) return;
  window.__floatrLoaded = true;

  const isTop = window === window.top;
  const ext = (typeof safari !== 'undefined' && safari.extension) ? safari.extension : null;
  const MARK = '__floatr';
  const host = location.hostname;
  const frameToken = Math.random().toString(36).slice(2);

  let settings = {
    unblockPiP: true, autoPiP: false, seekSeconds: 10, rateStep: 0.25,
    playerButtons: true, hoverButton: false,
    players: ['youtube', 'twitch', 'vimeo', 'netflix', 'prime', 'disney', 'max', 'videojs', 'jwplayer', 'plyr', 'wistia'],
    siteRules: [],
  };

  function send(name, info) {
    try {
      if (ext) ext.dispatchMessage(name, info || {});
      else console.info('[floatr]', location.host, name, JSON.stringify(info || {})); // test pages only
    } catch (e) { /* page unloading */ }
  }

  // ---------------------------------------------------------------- settings / site rules

  function siteRule() {
    const h = host.toLowerCase();
    return (settings.siteRules || []).find(r => {
      const rh = String(r.host || '').toLowerCase().trim();
      return rh && (h === rh || h.endsWith('.' + rh));
    }) || null;
  }
  function resolve(flag, global) {
    const r = siteRule();
    if (r && r[flag] === 'on') return true;
    if (r && r[flag] === 'off') return false;
    return !!global;
  }
  const buttonsEnabled = () => resolve('buttons', settings.playerButtons);
  const autoPiPEnabled = () => resolve('autoPiP', settings.autoPiP);

  // ---------------------------------------------------------------- finding videos

  /** All <video> elements in this frame, including ones inside open shadow roots. */
  function allVideos() {
    const out = Array.from(document.getElementsByTagName('video'));
    if (document.body && out.length === 0) {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
      let n = walker.nextNode();
      let budget = 20000;
      while (n && budget-- > 0) {
        if (n.shadowRoot) out.push(...n.shadowRoot.querySelectorAll('video'));
        n = walker.nextNode();
      }
    }
    return out;
  }

  function isInPiP(v) {
    return !!v && (document.pictureInPictureElement === v || v.webkitPresentationMode === 'picture-in-picture');
  }
  function pipVideo() {
    return allVideos().find(isInPiP) || null;
  }

  let contextVideo = null;
  let contextAt = 0;

  /** Higher is better: in PiP > right-clicked > playing > large and visible > has sound. */
  function score(v) {
    if (!v.currentSrc && !v.src && v.readyState === 0) return -1;
    const r = v.getBoundingClientRect();
    const visW = Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0));
    const visH = Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0));
    let s = Math.min(visW * visH, 9e6);
    if (isInPiP(v)) s += 8e9;
    if (v === contextVideo && Date.now() - contextAt < 15000) s += 4e9;
    if (!v.paused && !v.ended) s += 2e9;
    if (!v.muted && v.volume > 0) s += 1e7;
    if (r.width < 48 || r.height < 48) s -= 1e9; // tracking pixels, hidden previews
    return s;
  }

  function bestLocal() {
    let best = null, bestScore = -Infinity;
    for (const v of allVideos()) {
      const s = score(v);
      if (s > bestScore) { best = v; bestScore = s; }
    }
    return best && bestScore >= 0 ? { video: best, score: bestScore } : null;
  }

  // ---------------------------------------------------------------- picture in picture

  function unblock(v) {
    if (!settings.unblockPiP) return;
    if (v.hasAttribute('disablepictureinpicture')) v.removeAttribute('disablepictureinpicture');
    try { v.disablePictureInPicture = false; } catch (e) { /* read-only on some builds */ }
  }

  function waitFor(cond, ms) {
    return new Promise(resolve => {
      const t0 = performance.now();
      (function tick() {
        if (cond()) return resolve(true);
        if (performance.now() - t0 > ms) return resolve(false);
        setTimeout(tick, 50);
      })();
    });
  }

  function report(event, detail) {
    send('result', detail ? { event, detail: String(detail) } : { event });
  }

  async function enterPiP(v, opts) {
    opts = opts || {};
    unblock(v);
    let threw = false;
    try {
      if (typeof v.webkitSetPresentationMode === 'function' &&
          (!v.webkitSupportsPresentationMode || v.webkitSupportsPresentationMode('picture-in-picture'))) {
        v.webkitSetPresentationMode('picture-in-picture');
      } else if (typeof v.requestPictureInPicture === 'function') {
        await v.requestPictureInPicture();
      } else {
        threw = true;
      }
    } catch (e) {
      threw = true;
    }
    const ok = !threw && await waitFor(() => isInPiP(v), 700);
    if (ok) return true;
    if (opts.silent) return false;
    if (!opts.trusted) {
      // No user gesture reached the page. Ask the app to click our toolbar button,
      // which arrives here again with trusted = true.
      send('needsGesture', {});
    } else {
      report('blocked');
    }
    return false;
  }

  async function exitPiP(v) {
    try {
      if (document.pictureInPictureElement === v && document.exitPictureInPicture) {
        await document.exitPictureInPicture();
      } else if (typeof v.webkitSetPresentationMode === 'function') {
        v.webkitSetPresentationMode('inline');
      }
    } catch (e) { /* already inline */ }
  }

  // ---------------------------------------------------------------- commands (run in the frame that owns the video)

  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
  const fmtRate = r => (Math.round(r * 100) / 100).toString().replace('.', ',') + '×';

  async function execLocal(cmd, opts) {
    const target = pipVideo() || (bestLocal() || {}).video;
    if (!target) { report('noVideo'); return; }
    switch (cmd) {
      case 'toggle':
        if (isInPiP(target)) await exitPiP(target);
        else await enterPiP(target, opts);
        break;
      case 'exit':
        await exitPiP(target);
        break;
      case 'nextVideo': {
        const vids = allVideos().filter(v => score(v) >= 0);
        if (vids.length < 2) { report('noVideo'); return; }
        const i = vids.indexOf(target);
        const next = vids[(i + 1) % vids.length];
        if (isInPiP(target)) await exitPiP(target);
        await enterPiP(next, opts);
        break;
      }
      case 'playPause':
        if (target.paused) { try { await target.play(); } catch (e) { /* autoplay policy */ } report('playing'); }
        else { target.pause(); report('paused'); }
        break;
      case 'seekBack':
      case 'seekForward': {
        const d = (cmd === 'seekBack' ? -1 : 1) * (settings.seekSeconds || 10);
        const max = isFinite(target.duration) ? target.duration : Infinity;
        target.currentTime = clamp(target.currentTime + d, 0, max);
        report('seek', (d > 0 ? '+' : '−') + Math.abs(d) + ' s');
        break;
      }
      case 'slower':
      case 'faster': {
        const step = settings.rateStep || 0.25;
        const r = clamp(Math.round((target.playbackRate + (cmd === 'slower' ? -step : step)) * 100) / 100, 0.25, 4);
        target.playbackRate = r;
        report('rate', fmtRate(r));
        break;
      }
      case 'mute':
        target.muted = !target.muted;
        report(target.muted ? 'muted' : 'unmuted');
        break;
    }
  }

  // ---------------------------------------------------------------- cross-frame coordination

  const pendingCollections = new Map();

  function frameWindows(win) {
    const out = [];
    try { for (let i = 0; i < win.frames.length; i++) out.push(win.frames[i]); } catch (e) { /* detached */ }
    return out;
  }

  /** Top frame: gathers the best video of every frame. Resolves to [{score, source|null}]. */
  function collect() {
    const local = bestLocal();
    const results = [{ score: local ? local.score : -1, source: null }];
    const children = frameWindows(window);
    if (children.length === 0) return Promise.resolve(results);
    const id = Math.random().toString(36).slice(2);
    pendingCollections.set(id, results);
    for (const w of children) {
      try { w.postMessage({ [MARK]: 'collect', id }, '*'); } catch (e) { /* gone */ }
    }
    return new Promise(resolve => setTimeout(() => {
      pendingCollections.delete(id);
      resolve(results);
    }, 160));
  }

  window.addEventListener('message', ev => {
    const d = ev.data;
    if (!d || typeof d !== 'object' || !d[MARK]) return;
    switch (d[MARK]) {
      case 'collect': {
        // Answer the top frame directly and pass the request down to nested frames.
        const b = bestLocal();
        try { window.top.postMessage({ [MARK]: 'score', id: d.id, score: b ? b.score : -1 }, '*'); } catch (e) { /* noop */ }
        for (const w of frameWindows(window)) {
          try { w.postMessage({ [MARK]: 'collect', id: d.id }, '*'); } catch (e) { /* noop */ }
        }
        break;
      }
      case 'score': {
        const list = isTop && pendingCollections.get(d.id);
        if (list) list.push({ score: Number(d.score), source: ev.source });
        break;
      }
      case 'exec':
        execLocal(d.cmd, { trusted: !!d.trusted, silent: !!d.silent });
        break;
      case 'has':
        if (isTop) { childHasVideo.set(ev.source, !!d.found); reportVideoPresence(); }
        break;
    }
  });

  /** Top frame: route a command to the frame whose video should receive it. */
  async function route(cmd, opts) {
    const local = bestLocal();
    // Fast path keeps the user gesture: act right away when no iframe could do better.
    if (frameWindows(window).length === 0 || (local && local.score >= 2e9)) {
      return execLocal(cmd, opts);
    }
    const results = await collect();
    results.sort((a, b) => b.score - a.score);
    const win = results[0];
    if (!win || win.score < 0) { report('noVideo'); return; }
    if (!win.source) return execLocal(cmd, opts);
    try { win.source.postMessage({ [MARK]: 'exec', cmd, trusted: !!opts.trusted, silent: !!opts.silent }, '*'); } catch (e) { /* gone */ }
  }

  // ---------------------------------------------------------------- messages from the extension

  if (ext && safari.self && safari.self.addEventListener) {
    safari.self.addEventListener('message', ev => {
      const info = ev.message || {};
      if (ev.name === 'settings') {
        settings = Object.assign(settings, info);
        refreshButtons();
        return;
      }
      if (!isTop) return; // the top frame coordinates; iframes act on its postMessage
      route(ev.name, { trusted: !!info.viaToolbar });
    });
  }

  // ---------------------------------------------------------------- state reporting

  let lastPip = false;
  function pipChanged() {
    const v = pipVideo();
    if (!!v === lastPip) return; // presentation-mode events also fire for fullscreen
    lastPip = !!v;
    if (v) {
      send('pipState', { active: true, title: document.title || host, host });
      report('pipOn', document.title || host);
    } else {
      send('pipState', { active: false });
      report('pipOff');
    }
  }
  document.addEventListener('enterpictureinpicture', pipChanged, true);
  document.addEventListener('leavepictureinpicture', pipChanged, true);
  document.addEventListener('webkitpresentationmodechanged', pipChanged, true);

  const childHasVideo = new Map();
  let lastPresence = null;
  function reportVideoPresence() {
    const localFound = allVideos().length > 0;
    if (!isTop) {
      try { window.top.postMessage({ [MARK]: 'has', found: localFound }, '*'); } catch (e) { /* noop */ }
      return;
    }
    let found = localFound;
    for (const v of childHasVideo.values()) found = found || v;
    if (found !== lastPresence) {
      lastPresence = found;
      send('videoCheck', { found });
    }
  }

  // Per-site default speed, applied the first time each video plays.
  const rateApplied = new WeakSet();
  document.addEventListener('play', ev => {
    const v = ev.target;
    if (!(v instanceof HTMLVideoElement) || rateApplied.has(v)) return;
    rateApplied.add(v);
    const r = siteRule();
    if (r && typeof r.defaultRate === 'number') v.playbackRate = r.defaultRate;
  }, true);

  // ---------------------------------------------------------------- auto PiP on tab switch

  let autoEntered = null;
  document.addEventListener('visibilitychange', async () => {
    if (!autoPiPEnabled()) return;
    if (document.hidden) {
      const b = bestLocal();
      if (b && !b.video.paused && !isInPiP(b.video)) {
        if (await enterPiP(b.video, { silent: true })) autoEntered = b.video;
      }
    } else if (autoEntered) {
      if (isInPiP(autoEntered)) await exitPiP(autoEntered);
      autoEntered = null;
    }
  });

  // ---------------------------------------------------------------- context menu

  document.addEventListener('contextmenu', ev => {
    let v = ev.target && ev.target.closest ? ev.target.closest('video') : null;
    if (!v && document.elementsFromPoint) {
      v = document.elementsFromPoint(ev.clientX, ev.clientY).find(el => el instanceof HTMLVideoElement) || null;
    }
    if (!v) { // overlays: pick the video whose box contains the click
      v = allVideos().find(x => {
        const r = x.getBoundingClientRect();
        return ev.clientX >= r.left && ev.clientX <= r.right && ev.clientY >= r.top && ev.clientY <= r.bottom;
      }) || null;
    }
    contextVideo = v;
    contextAt = Date.now();
    try { if (ext && ext.setContextMenuEventUserInfo) ext.setContextMenuEventUserInfo(ev, { hasVideo: !!v }); } catch (e) { /* noop */ }
  }, true);

  // ---------------------------------------------------------------- buttons inside players

  const ICON = '<svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round">' +
    '<rect x="2.5" y="4.5" width="19" height="15" rx="2.5"/><rect x="12" y="11.5" width="7.5" height="6" rx="1.2" fill="#fff"/></svg>';

  // Each entry: where the site's control bar is, which class makes our button blend in,
  // and which existing control we go in front of. Sites change their markup over time;
  // the hover button covers anything these selectors miss.
  const PLAYERS = [
    { id: 'youtube', hosts: /(^|\.)youtube(-nocookie)?\.com$/, bar: '.ytp-right-controls', cls: 'ytp-button', before: '.ytp-fullscreen-button', pad: '10px' },
    { id: 'twitch', hosts: /(^|\.)twitch\.tv$/, bar: '.player-controls__right-control-group', cls: '', before: '[data-a-target="player-fullscreen-button"]', size: '30px' },
    { id: 'vimeo', hosts: /(^|\.)vimeo\.com$/, bar: '.vp-controls .vp-controls-wrapper, [class*="ControlBar_module_controlBarWrapper"] [class*="ControlBar_module_right"]', cls: '', before: '.fullscreen, [data-fullscreen-button]', size: '28px' },
    { id: 'netflix', hosts: /(^|\.)netflix\.com$/, bar: '[data-uia="controls-standard"] div:has(> button[data-uia="control-fullscreen-enter"])', cls: '', before: 'button[data-uia="control-fullscreen-enter"]', size: '40px' },
    { id: 'prime', hosts: /(^|\.)(primevideo|amazon)\.[a-z.]+$/, bar: '.atvwebplayersdk-hideabletopbuttons-container', cls: '', before: '.atvwebplayersdk-fullscreen-button', size: '32px' },
    { id: 'disney', hosts: /(^|\.)disneyplus\.com$/, bar: '.controls__right', cls: '', before: 'toggle-fullscreen', size: '36px' },
    { id: 'max', hosts: /(^|\.)(max|hbomax)\.com$/, bar: '[data-testid="player-ux-controls-right"], [class*="ControlsFooterBottomRight"]', cls: '', before: '[data-testid="player-ux-fullscreen-button"]', size: '36px' },
    { id: 'videojs', bar: '.vjs-control-bar', cls: 'vjs-control vjs-button', before: '.vjs-fullscreen-control', size: '3em' },
    { id: 'jwplayer', bar: '.jw-button-container', cls: 'jw-icon jw-icon-inline jw-button-color jw-reset', before: '.jw-icon-fullscreen', size: '44px' },
    { id: 'plyr', bar: '.plyr__controls', cls: 'plyr__controls__item plyr__control', before: '[data-plyr="fullscreen"]', size: '32px' },
    { id: 'wistia', bar: '.w-control-bar__region--airplay, .w-bottom-bar-right', cls: 'w-control', before: null, size: '34px' },
  ];

  function videoNear(el) {
    let node = el;
    for (let i = 0; node && i < 12; i++, node = node.parentElement) {
      const v = node.querySelector && node.querySelector('video');
      if (v) return v;
    }
    return (bestLocal() || {}).video || null;
  }

  function makeButton(player) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = ('floatr-btn ' + (player.cls || '')).trim();
    b.title = 'Picture in Picture (Floatr)';
    b.setAttribute('aria-label', 'Picture in Picture');
    b.innerHTML = ICON;
    b.style.cssText = 'background:transparent;border:0;cursor:pointer;opacity:.92;display:inline-flex;align-items:center;justify-content:center;' +
      (player.size ? `width:${player.size};height:${player.size};` : '') + (player.pad ? `padding:${player.pad};` : 'padding:4px;');
    b.addEventListener('click', ev => {
      ev.preventDefault();
      ev.stopPropagation();
      const v = videoNear(b);
      if (!v) return;
      if (isInPiP(v)) exitPiP(v); else enterPiP(v, { trusted: true });
    }, true);
    return b;
  }

  function injectPlayerButtons() {
    if (!buttonsEnabled()) return;
    const enabled = new Set(settings.players || []);
    for (const p of PLAYERS) {
      if (!enabled.has(p.id)) continue;
      if (p.hosts && !p.hosts.test(host) && p.id !== 'youtube') continue;
      let bars;
      try { bars = document.querySelectorAll(p.bar); } catch (e) { continue; } // :has() unsupported
      for (const bar of bars) {
        if (bar.querySelector(':scope > .floatr-btn')) continue;
        const btn = makeButton(p);
        let before = null;
        if (p.before) { try { before = bar.querySelector(':scope > ' + p.before) || null; } catch (e) { before = null; } }
        bar.insertBefore(btn, before);
      }
    }
  }

  function removePlayerButtons() {
    document.querySelectorAll('.floatr-btn').forEach(b => b.remove());
  }

  // Floating button shown over any video on hover (optional, for players we don't know).
  let hoverHost = null, hoverBtn = null, hoverVideo = null, hoverHide = 0;
  function ensureHover() {
    if (hoverHost) return;
    hoverHost = document.createElement('div');
    hoverHost.style.cssText = 'position:fixed;z-index:2147483647;top:0;left:0;width:0;height:0;';
    const root = hoverHost.attachShadow({ mode: 'closed' });
    root.innerHTML = '<style>button{all:initial;position:fixed;width:30px;height:30px;padding:6px;box-sizing:border-box;border-radius:8px;' +
      'background:rgba(20,20,20,.62);-webkit-backdrop-filter:blur(12px);cursor:pointer;opacity:0;transition:opacity .15s}' +
      'button.on{opacity:1}button:hover{background:rgba(20,20,20,.82)}</style><button title="Picture in Picture (Floatr)">' + ICON + '</button>';
    hoverBtn = root.querySelector('button');
    hoverBtn.addEventListener('click', ev => {
      ev.preventDefault(); ev.stopPropagation();
      if (!hoverVideo) return;
      if (isInPiP(hoverVideo)) exitPiP(hoverVideo); else enterPiP(hoverVideo, { trusted: true });
    });
    hoverBtn.addEventListener('mouseenter', () => clearTimeout(hoverHide));
    document.documentElement.appendChild(hoverHost);
  }
  function onMouseMove(ev) {
    if (!settings.hoverButton || !buttonsEnabled()) return;
    const v = allVideos().find(x => {
      const r = x.getBoundingClientRect();
      return r.width >= 200 && r.height >= 112 &&
        ev.clientX >= r.left && ev.clientX <= r.right && ev.clientY >= r.top && ev.clientY <= r.bottom;
    });
    if (!v) {
      clearTimeout(hoverHide);
      hoverHide = setTimeout(() => hoverBtn && hoverBtn.classList.remove('on'), 400);
      return;
    }
    ensureHover();
    clearTimeout(hoverHide);
    hoverVideo = v;
    const r = v.getBoundingClientRect();
    hoverBtn.style.top = Math.max(8, r.top + 10) + 'px';
    hoverBtn.style.left = Math.min(innerWidth - 40, r.right - 40) + 'px';
    hoverBtn.classList.add('on');
  }
  document.addEventListener('mousemove', onMouseMove, { passive: true, capture: true });

  function refreshButtons() {
    if (buttonsEnabled()) injectPlayerButtons(); else removePlayerButtons();
    if (!settings.hoverButton && hoverBtn) hoverBtn.classList.remove('on');
  }

  // ---------------------------------------------------------------- DOM watching (throttled)

  let scheduled = false;
  function scheduleScan() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      reportVideoPresence();
      if (buttonsEnabled()) injectPlayerButtons();
      if (settings.unblockPiP) document.querySelectorAll('video[disablepictureinpicture]').forEach(unblock);
    }, 400);
  }
  new MutationObserver(scheduleScan).observe(document, { subtree: true, childList: true });

  window.addEventListener('focus', () => {
    lastPresence = null;
    send('hello', {});
    scheduleScan();
  });

  send('hello', {});
  scheduleScan();

  // Test hook (only used by Tests/pages when no Safari extension is present).
  if (!ext) window.__floatr = { route, execLocal, bestLocal, allVideos, score, setSettings: s => Object.assign(settings, s) };
})();
