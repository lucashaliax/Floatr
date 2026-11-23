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
  // Videos inside web components (open shadow roots) need a walk over the whole page.
  // Automatic scans reuse the last walk for 2 s; commands and clicks always walk again.
  let shadowVideos = [], shadowWalkAt = -Infinity;
  function allVideos(opts) {
    const out = Array.from(document.getElementsByTagName('video'));
    if (!document.body || out.length > 0) return out;
    const now = performance.now();
    if (opts && opts.cached && now - shadowWalkAt < 2000) return shadowVideos.filter(v => v.isConnected);
    const found = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    let n = walker.nextNode();
    let budget = 20000;
    while (n && budget-- > 0) {
      if (n.shadowRoot) found.push(...n.shadowRoot.querySelectorAll('video'));
      n = walker.nextNode();
    }
    shadowVideos = found;
    shadowWalkAt = now;
    return found;
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

  /** Playing with sound: what the user hears. (Test pages can mark muted videos as audible,
   *  because Safari won't autoplay with sound without a click.) */
  function audible(v) {
    // Test pages only: Safari pauses muted autoplay videos in background tabs and won't play
    // with sound without a click, so a marked page counts its videos as audible.
    if (document.documentElement.hasAttribute('data-floatr-test-audible')) return v.readyState > 0;
    return !v.paused && !v.ended && v.readyState > 2 && !v.muted && v.volume > 0;
  }

  /** What this frame has, for the extension's tab probe. */
  function localState() {
    const vids = allVideos();
    const b = bestLocal();
    return {
      score: b ? b.score : -1,
      playing: vids.some(v => !v.paused && !v.ended),
      audible: vids.some(audible),
    };
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
    const results = [Object.assign(localState(), { source: null })];
    const children = frameWindows(window);
    if (children.length === 0) return Promise.resolve(results);
    const id = Math.random().toString(36).slice(2);
    return new Promise(resolve => {
      let done = false;
      const finish = () => {
        if (done) return;
        done = true;
        pendingCollections.delete(id);
        resolve(results);
      };
      // Finish as soon as every direct child answered: background tabs throttle timers to ≥1 s,
      // so the timeout is only a safety net for frames that never answer.
      results.expected = children.length + 1;
      results.finish = finish;
      pendingCollections.set(id, results);
      for (const w of children) {
        try { w.postMessage({ [MARK]: 'collect', id }, '*'); } catch (e) { /* gone */ }
      }
      setTimeout(finish, 160);
    });
  }

  window.addEventListener('message', ev => {
    const d = ev.data;
    if (!d || typeof d !== 'object' || !d[MARK]) return;
    switch (d[MARK]) {
      case 'collect': {
        // Answer the top frame directly and pass the request down to nested frames.
        const st = localState();
        try { window.top.postMessage({ [MARK]: 'score', id: d.id, score: st.score, playing: st.playing, audible: st.audible }, '*'); } catch (e) { /* noop */ }
        for (const w of frameWindows(window)) {
          try { w.postMessage({ [MARK]: 'collect', id: d.id }, '*'); } catch (e) { /* noop */ }
        }
        break;
      }
      case 'score': {
        const list = isTop && pendingCollections.get(d.id);
        if (list) {
          list.push({ score: Number(d.score), playing: !!d.playing, audible: !!d.audible, source: ev.source });
          if (list.length >= list.expected && list.finish) list.finish();
        }
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
      if (ev.name === 'probe') {
        // The extension asks every tab what it has, to pick a background tab playing audio.
        collect().then(results => send('probeResult', {
          id: info.id,
          score: Math.max(...results.map(x => x.score)),
          playing: results.some(x => x.playing),
          audible: results.some(x => x.audible),
        }));
        return;
      }
      // Answer at once so the extension knows this page is alive (dead or script-less pages never answer).
      if (info.id) send('ack', { id: info.id });
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
    const localFound = knownVideos.length > 0; // the scan that calls this just refreshed the list
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
    { id: 'youtube', hosts: /(^|\.)youtube(-nocookie)?\.com$/, bar: '.ytp-right-controls', cls: 'ytp-button', before: '.ytp-fullscreen-button', size: '48px' },
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

  /**
   * A button sized like its neighbour in the player's control bar (`ref`), with a fixed-size
   * icon. Relying on the site's CSS to size it collapsed it into a dot when YouTube changed
   * its controls, so nothing here depends on percentages or the site's button styles.
   */
  function makeButton(player, ref) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = ('floatr-btn ' + (player.cls || '')).trim();
    b.title = 'Picture in Picture (Floatr)';
    b.setAttribute('aria-label', 'Picture in Picture');
    const rr = ref && ref.getBoundingClientRect();
    const w = rr && rr.width >= 16 ? Math.round(rr.width) : null;
    const h = rr && rr.height >= 16 ? Math.round(rr.height) : null;
    const box = w && h ? `width:${w}px;height:${h}px;` : (player.size ? `width:${player.size};height:${player.size};` : 'width:36px;height:36px;');
    const icon = h ? Math.max(16, Math.min(28, Math.round(Math.min(w, h) * 0.55))) : 22;
    b.innerHTML = ICON.replace('width="100%" height="100%"', `width="${icon}" height="${icon}"`);
    b.style.cssText = 'background:transparent;border:0;margin:0;padding:0;cursor:pointer;opacity:.92;flex:none;' +
      'display:inline-flex;align-items:center;justify-content:center;vertical-align:middle;box-sizing:border-box;' + box;
    b.firstElementChild.style.cssText = `display:block;width:${icon}px;height:${icon}px;flex:none;pointer-events:none`;
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
        if (bar.querySelector('.floatr-btn')) continue;
        // Go next to the reference control (usually fullscreen) wherever it sits: players
        // like YouTube nest their buttons in groups inside the bar.
        let before = null;
        if (p.before) { try { before = bar.querySelector(p.before); } catch (e) { before = null; } }
        const container = before ? before.parentElement : bar;
        const neighbour = before || [...bar.querySelectorAll('button')].find(x => x.getBoundingClientRect().width >= 16) || null;
        container.insertBefore(makeButton(p, neighbour), before);
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
    // A pill with icon and label: a bare 30 px icon read as a dot over busy video.
    root.innerHTML = '<style>' +
      'button{all:initial;position:fixed;display:flex;align-items:center;gap:7px;height:36px;padding:0 14px 0 11px;' +
      'box-sizing:border-box;border-radius:18px;background:rgba(18,18,18,.72);border:1px solid rgba(255,255,255,.28);' +
      '-webkit-backdrop-filter:blur(14px) saturate(1.4);box-shadow:0 4px 14px rgba(0,0,0,.35);cursor:pointer;' +
      'color:#fff;font:600 13px/1 -apple-system,system-ui,sans-serif;letter-spacing:.2px;' +
      'opacity:0;pointer-events:none;transition:opacity .15s,background .15s}' +
      'button.on{opacity:1;pointer-events:auto}button:hover{background:rgba(18,18,18,.9)}' +
      'svg{display:block;width:20px;height:20px;flex:none}</style>' +
      '<button title="Picture in Picture (Floatr)">' + ICON + '<span>PiP</span></button>';
    hoverBtn = root.querySelector('button');
    hoverBtn.addEventListener('click', ev => {
      ev.preventDefault(); ev.stopPropagation();
      if (!hoverVideo) return;
      if (isInPiP(hoverVideo)) exitPiP(hoverVideo); else enterPiP(hoverVideo, { trusted: true });
    });
    hoverBtn.addEventListener('mouseenter', () => { clearTimeout(hoverHide); hoverHide = 0; });
    document.documentElement.appendChild(hoverHost);
  }
  // The mousemove handler only records the pointer; the work runs at most once per frame
  // and uses the video list from the last DOM scan instead of searching the page each time.
  let hoverX = 0, hoverY = 0, hoverFrame = 0;
  function onMouseMove(ev) {
    if (!settings.hoverButton) return;
    hoverX = ev.clientX;
    hoverY = ev.clientY;
    if (!hoverFrame) hoverFrame = requestAnimationFrame(updateHover);
  }
  function updateHover() {
    hoverFrame = 0;
    if (!settings.hoverButton || !buttonsEnabled()) return;
    const v = knownVideos.find(x => {
      if (!x.isConnected) return false;
      const r = x.getBoundingClientRect();
      return r.width >= 200 && r.height >= 112 &&
        hoverX >= r.left && hoverX <= r.right && hoverY >= r.top && hoverY <= r.bottom;
    });
    if (!v) {
      if (hoverBtn && hoverBtn.classList.contains('on') && !hoverHide) {
        hoverHide = setTimeout(() => { hoverHide = 0; hoverBtn.classList.remove('on'); }, 400);
      }
      return;
    }
    ensureHover();
    clearTimeout(hoverHide);
    hoverHide = 0;
    hoverVideo = v;
    const r = v.getBoundingClientRect();
    const w = hoverBtn.offsetWidth || 80;
    hoverBtn.style.top = Math.max(8, r.top + 12) + 'px';
    hoverBtn.style.left = Math.max(8, Math.min(innerWidth - w - 12, r.right - w - 12)) + 'px';
    hoverBtn.classList.add('on');
  }
  document.addEventListener('mousemove', onMouseMove, { passive: true, capture: true });

  /** Applies new settings at once: removes buttons of players that were turned off and the
   *  floating button if it was turned off. */
  function refreshButtons() {
    removePlayerButtons();
    if (buttonsEnabled()) injectPlayerButtons();
    if ((!settings.hoverButton || !buttonsEnabled()) && hoverHost) {
      hoverHost.remove();
      hoverHost = hoverBtn = hoverVideo = null;
    }
  }

  // ---------------------------------------------------------------- DOM watching (throttled)

  let scheduled = false;
  let knownVideos = []; // refreshed by each DOM scan; used by the hover button
  function scheduleScan() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      knownVideos = allVideos({ cached: true });
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
  if (!ext) window.__floatr = {
    route, execLocal, bestLocal, allVideos, score,
    setSettings: s => Object.assign(settings, s),
    // Same path as the extension's "settings" message.
    applySettings: s => { Object.assign(settings, s); refreshButtons(); },
    // One automatic DOM scan, as scheduleScan runs it (for timing on bench pages).
    scanNow: () => { knownVideos = allVideos({ cached: true }); reportVideoPresence(); if (buttonsEnabled()) injectPlayerButtons(); },
  };
})();
