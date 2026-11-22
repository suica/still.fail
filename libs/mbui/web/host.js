// Browser host for the MoonBit UI prototype: a WebGL2 canvas drawing the
// same instances as the Metal renderer, canvas-2D text rasterized into an
// atlas, and a hidden textarea that receives the system input method.
(() => {
  const FAMILY = 'system-ui, -apple-system, "PingFang SC", "Noto Sans CJK SC", "Segoe UI", sans-serif';
  // the code face (style bit 2), its Han from the system's sans
  // the serif face (style bit 4): a reader's 宋体
  const SERIF = '"Songti SC", "Noto Serif CJK SC", "Source Han Serif SC", SimSun, serif';
  const MONO = 'ui-monospace, "SF Mono", Menlo, Consolas, "JetBrains Mono", "PingFang SC", "Noto Sans CJK SC", monospace';
  const ATLAS = 4096;
  const hostScriptSrc = (typeof document !== 'undefined' && document.currentScript && document.currentScript.src) || location.href;
  const params = new URLSearchParams(location.search);
  const H = {};
  // (H.loadedTitle's: read as this host loads, before H.run gives the page its run's title)
  const loadedTitle = typeof document !== 'undefined' ? String(document.title || '').trim() : '';
  // The page's query parameter `n` for the program (host_js.mbt's env): the address as it is now, else as it was when
  // this host loaded, so what the page's own start took off the address with history.replaceState before the program's
  // first frame read it (a drive's script, a sign-in's answer) is still given; "" when neither has it.
  H.env = (n) => {
    const cur = typeof location !== 'undefined' && location.search ? new URLSearchParams(location.search).get(n) : null;
    return cur ?? params.get(n) ?? '';
  };
  let cb = null;
  let modifiersSaid = 0;
  const MB_KIND_LIQUID_SINGLE = 13;
  const MB_KINDS = 14;
  const GLASS_SLOTS = 32;
  function makeGlassSlots() {
    return Array.from({ length: GLASS_SLOTS }, () => ({
      bt: null, bfb: null, bw: 0, bh: 0, bf: 0,
      under: null, underN: 0, whole: 0, picked: 0, grab: null, key: null, valid: false, used: 0,
    }));
  }
  let canvas, gl, vs, prog, progs = new Array(MB_KINDS + 1).fill(null), progFlat, ufVp, progGen = 0, progNow = null, post, vao, instBuf, atlasTex, ta;
  let U = {}, PU = {};
  let cssW = 0, cssH = 0, dpr = 1;
  let rectLeft = 0, rectTop = 0, rectValid = false;
  // the document and window of the window drawn or handled now (winUse: the page's own, but while a window opened beside
  // it is in place)
  let doc = typeof document !== 'undefined' ? document : null, hostWin = window;
  // The windows of the run (H.windows, ---- windows ---- below): 0 the page, 1..15 windows opened beside it; winActive
  // the one whose frame or input is handled now; winsOpen how many beside the page are open.
  const MB_WINS = 16;
  const wins = new Array(MB_WINS).fill(null);
  let winActive = 0, winsOpen = 0;
  let sizeDirty = true, sizeObserver = null;
  // the numbers of an instance (src/ui/scene.mbt)
  const INST = 60;
  let f32 = new Float32Array(INST * 4096);
  let pending = false, pendingRaf = 0;
  window.__logs = [];
  // (what H.log keeps: all of it where a test drives the page, which reads it whole and by its lines' places; else the
  // last LOGS_MOST lines, a page left open logging on for days not growing without end)
  const LOGS_MOST = typeof navigator !== 'undefined' && navigator.webdriver ? Infinity : 2000;

  // ---- frames ----
  // A picture at a declared moment (?shot_at=MS, scripts/web-shot.mjs): the run's frames are on a clock of their own,
  // 1/60 s a frame from 0, as a stable run's on macOS (mac_app.m), and drawn one a display frame whether the app asks
  // for them or not, until that clock reaches MS; that frame drawn, no other, and the page says so (window.__shot:
  // its frame and time, "SHOT n t" on the log). The clock stands still while the app awaits the host (an image
  // decoding: what its last frame said), so the picture is of the app at MS on its own clock, however fast the
  // machine is. The app's timers and its reads of the clock are on that clock too.
  // Never "once the app is at rest": that is settling by another name (a moment is declared, or a drive waits for the
  // page's own named event); shot_at that is no moment in ms fails at once (window.__shot.fail, "SHOT FAIL").
  const shotParam = params.get('shot_at');
  const shotAt = shotParam === null ? -1 : /^[0-9]+(\.[0-9]+)?$/.test(shotParam) ? Number(shotParam) : -2;
  let clock = 0;
  let frames = 0, inFrame = false, lastRafTs = -1;
  function tick(rafTs) {
    pending = false;
    pendingRaf = 0;
    if (typeof rafTs === 'number' && rafTs >= 0) {
      if (lastRafTs >= 0) {
        const dt = rafTs - lastRafTs;
        if (dt >= 3 && dt <= 25) displayFrame = displayFrame * 0.8 + dt * 0.2;
      }
      lastRafTs = rafTs;
    } else {
      lastRafTs = -1;
    }
    resize();
    inFrame = true;
    const t = shotAt >= 0 ? clock : performance.now();
    // (what it waits for said again by the frame, if it still does: H.wakeAfter, from its time)
    wakes0.at = -1;
    buildingFor = t;
    // the soft keyboard over the canvas's foot: the app laid out above it, the canvas keeping its size (as the phones'
    // apps keep their drawables', ios_app.m's drawFor)
    cb.frame(cssW, Math.max(1, cssH - keyboardOver()), dpr, t);
    buildingFor = -1;
    inFrame = false;
    frames++;
    if (shotAt === -2) {
      const fail = 'shot_at is a moment in ms on the run\'s clock, not ' + JSON.stringify(shotParam);
      window.__shot = { frame: frames, t, fail };
      H.log('SHOT FAIL: ' + fail);
      return;
    }
    if (shotAt < 0) return;
    if (awaiting > 0) return;  // the clock stands still; the host's answer asks for the next frame
    if (t >= shotAt) {
      window.__shot = { frame: frames, t };
      H.log(`SHOT ${frames} ${t}`);
      return;
    }
    clock = frames * (1000 / 60);
    H.requestFrame();
  }
  // (no frame before the host knows what it decodes: H.run)
  let known = false;
  // (and one of each window open beside the page, at that window's own display frame: tickSlot)
  H.requestFrame = () => {
    if (!cb || !known || window.__done !== undefined || window.__shot !== undefined) return;
    if (!pending) {
      pending = true;
      pendingRaf = requestAnimationFrame(tick);
    }
    if (winsOpen) slotFrames();
  };
  // The frame a touch asked for, drawn while the browser still handles that touch rather than at the display's next:
  // iOS brings its soft keyboard up for a field focused (setIme's focus) only while a person's gesture is handled, and
  // a requestAnimationFrame later is out of it, so a field tapped took the focus with no keyboard, which came up only on
  // a second tap (its pointerdown's focus, setupInput). The display's frame asked for is called off: drawn once.
  function frameInGesture() {
    if (!pending || !pendingRaf || shotAt >= 0 || winActive !== 0) return;
    cancelAnimationFrame(pendingRaf);
    tick();
  }
  // A frame asked for what moves on by the clock that needs only `hz` a second (@hostapi.frames_paced: a slow fill, a
  // spinner): on high-refresh displays where 1000/hz exceeds 1.5 display frames, pace via H.wakeAfter instead of
  // waking every rAF.
  H.framesPaced = (hz) => {
    if (shotAt >= 0 || !(hz > 0) || 1000 / hz <= displayFrame * 1.5) H.requestFrame();
    else H.wakeAfter(Math.max(1, 1000 / hz - 0.5 * displayFrame));
  };
  // (a run to a declared moment draws every frame to it: its timers are on its clock, due at the frame they fall in)
  // The frame `ms` after the one being built (its time), else after now: drawn at the first of the display's frames at
  // or past it, the ones before drawing nothing (not the one after a timer happens to fire: a step a frame or two
  // late by as much as that falls, a resident cycle's steps unevenly apart), the timer two frames before it.
  // Each window waits for its own (the page's wakes0, one beside it its slot's wake: the window H.wakeAfter is said in),
  // drawn at its own display's frame.
  const wakes0 = { at: -1 };
  let buildingFor = -1;
  // the display's frame (ms), as two of its frames come apart while a wait is due (60 a second until one has)
  let displayFrame = 1000 / 60, lastDue = -1;
  H.wakeAfter = (ms) => {
    if (shotAt >= 0) return;
    const wid = winActive, slot = wid === 0 ? null : wins[wid];
    const wake = slot ? slot.wake : wakes0;
    const raf = slot ? (f) => { if (!slot.closed) slot.win.requestAnimationFrame(f); } : requestAnimationFrame;
    const at = (buildingFor >= 0 ? buildingFor : performance.now()) + ms;
    if (wake.at >= 0 && wake.at <= at) return;
    wake.at = at;
    const due = (ts) => {
      if (lastDue >= 0 && ts - lastDue > 0 && ts - lastDue < 100) displayFrame = ts - lastDue;
      lastDue = ts;
      if (wake.at !== at) return;
      if (performance.now() < at - 0.5) {
        raf(due);
        return;
      }
      wake.at = -1;
      lastDue = -1;
      if (!cb || !known || window.__done !== undefined || window.__shot !== undefined) return;
      if (slot) {
        if (!slot.closed && !slot.pending) tickSlot(slot);
      } else if (!pending) {
        pending = true;
        tick();
      }
    };
    const lead = Math.max(0, at - performance.now() - 2 * displayFrame);
    setTimeout(() => raf(due), lead);
  };
  H.now = () => (shotAt >= 0 ? clock : performance.now());
  H.ownClock = () => shotAt >= 0;
  // the time of day (@hostapi.wall_ms): a run to a declared moment's from a fixed day (@ui.tester_wall's), on with its
  // clock, so what it shows of it is the same each run
  H.wallMs = () => (shotAt >= 0 ? 1790000000000 + clock : Date.now());
  // its zone (@hostapi.utc_offset_min): a run to a declared moment's UTC, as its day is its own
  H.utcOffsetMin = (ms) => (shotAt >= 0 ? 0 : -new Date(ms).getTimezoneOffset());

  // ---- files picked (src/hostapi/pick.mbt): the page's file input, its answer told as outside kind 3 ----
  // H.pickStart(kind): 1 photos, 2 files, 3 a photo taken now (the camera, where the browser has one), 16 more: one
  // too big to read whole held here instead (its File, H.heldFile: what the page's core reads it from as it goes up).
  // Opened from the press that asked (the browser lets a page open its picker only so: a frame after it is still in
  // that press's grace). Called off: none picked.
  const OUTSIDE_PICK = 3, HOLD_OVER = 16 * 1024 * 1024;
  const picks = new Map(), heldFiles = new Map();
  let nextPick = 1, nextHeld = 1;
  H.pickStart = (kind) => {
    const id = nextPick++;
    const k = kind & 15, hold = (kind & 16) !== 0;
    const input = document.createElement('input');
    input.type = 'file';
    input.multiple = k !== 3;
    if (k === 1) input.accept = 'image/*,video/*';
    if (k === 3) { input.accept = 'image/*'; input.capture = 'environment'; }
    const pick = { state: 0, files: [] };
    picks.set(id, pick);
    const done = (files) => {
      if (pick.state !== 0) return;
      pick.files = files;
      pick.state = 1;
      tell(OUTSIDE_PICK, id, 1);
      H.requestFrame();
    };
    input.addEventListener('cancel', () => done([]));
    input.addEventListener('change', async () => {
      const out = [];
      for (const f of input.files || []) {
        if (hold && f.size > HOLD_OVER) {
          const h = nextHeld++;
          heldFiles.set(h, f);
          out.push({ name: f.name, bytes: new Uint8Array(0), info: `${h}\t${f.size}\t` });
        } else {
          try { out.push({ name: f.name, bytes: new Uint8Array(await f.arrayBuffer()), info: `0\t${f.size}\t` }); } catch (e) { /* unreadable: left out */ }
        }
      }
      done(out);
    });
    input.click();
    return id;
  };
  H.pickState = (id) => { const p = picks.get(id); return p ? p.state : -1; };
  H.pickCount = (id) => picks.get(id)?.files.length || 0;
  H.pickName = (id, i) => picks.get(id)?.files[i]?.name || '';
  H.pickBytes = (id, i) => picks.get(id)?.files[i]?.bytes || new Uint8Array(0);
  H.pickInfo = (id, i) => picks.get(id)?.files[i]?.info || '';
  H.pickEnd = (id) => { picks.delete(id); };
  // a file held (Picked.held) taken by whoever sends it up: its File, let go here
  H.heldFile = (h) => { const f = heldFiles.get(h); heldFiles.delete(h); return f || null; };

  // ---- files kept on the device (src/hostapi/keep.mbt): the browser's download ----
  // All three ways (1 Downloads, 2 Choose, 3 Photos) are the browser's download: where it goes, and whether it asks,
  // is the browser's. Each part appended is a Blob of its own at once, which copies its bytes (what is given may be a
  // view of the app's memory, used again after the call), so the browser holds them, not this page's heap; `finish`
  // makes one Blob of them all and clicks an <a download> on its URL. Kept (1) once that click is made, where being the
  // file's name: the browser tells a page neither where it put it nor whether it numbered the name. The URL is revoked
  // as a later keep finishes a minute or more after its click (keptUrlMs), or as the page goes: never sooner (a
  // download whose URL goes before the browser has read it is cancelled: FileSaver.js waits 40 s for Safari's sake;
  // several files chosen finish frames apart), and on no timer (detlint's host-delay); till then the browser holds
  // what was kept last. States: 0 keeping, 1 kept, 2 called off, 3 failed.
  const keeps = new Map(), keptUrls = [], keptUrlMs = 60000;
  let nextKeep = 1;
  const revokeKept = (all) => {
    for (let i = keptUrls.length - 1; i >= 0; i--) {
      if (!all && performance.now() - keptUrls[i].at < keptUrlMs) continue;
      try { URL.revokeObjectURL(keptUrls[i].url); } catch (e) { /* gone already */ }
      keptUrls.splice(i, 1);
    }
  };
  window.addEventListener('pagehide', () => revokeKept(true));
  // (as the `download` attribute takes it: no folder, nothing unprintable, never empty)
  const keepName = (name) => String(name || '').replace(/[\/\\]/g, '_').replace(/[\u0000-\u001f\u007f]/g, '').trim() || 'download';
  H.keepBegin = (name, mime, way) => {
    const id = nextKeep++;
    keeps.set(id, { name: keepName(name), mime: String(mime || ''), way, parts: [], state: 0 });
    return id;
  };
  H.keepAppend = (id, bytes) => {
    const k = keeps.get(id);
    if (!k || k.state !== 0 || k.finished) return 0;
    try {
      k.parts.push(new Blob([bytes]));
      return 1;
    } catch (e) {
      k.state = 3;
      k.parts = [];
      H.requestFrame();
      return 0;
    }
  };
  H.keepFinish = (id) => {
    const k = keeps.get(id);
    if (!k || k.state !== 0 || k.finished) return;
    k.finished = true;
    revokeKept(false);
    try {
      const url = URL.createObjectURL(new Blob(k.parts, { type: k.mime || 'application/octet-stream' }));
      keptUrls.push({ url, at: performance.now() });
      const a = document.createElement('a');
      a.href = url;
      a.download = k.name;
      a.rel = 'noopener';
      a.style.display = 'none';
      // (in the document as it is clicked: an older Firefox clicked none that was not)
      document.body.appendChild(a);
      a.click();
      a.remove();
      k.state = 1;
    } catch (e) {
      H.log('keep ' + k.name + ': ' + e);
      k.state = 3;
    }
    k.parts = [];
    H.requestFrame();
  };
  H.keepState = (id) => { const k = keeps.get(id); return k ? k.state : 3; };
  H.keepWhere = (id) => { const k = keeps.get(id); return k && k.state === 1 ? k.name : ''; };
  // forgotten; one not finished called off, its parts let go
  H.keepEnd = (id) => { keeps.delete(id); };

  // ---- the page shown and in front (host_native.mbt set_app_state): 1 its tab shown, | 2 it has the focus ----
  H.setAppState = (f) => {
    let was = -1;
    const tellState = () => {
      const now = (document.visibilityState === 'visible' ? 1 : 0) | (document.hasFocus() ? 2 : 0);
      if (now === was) return;
      was = now;
      f(now);
      H.requestFrame();
    };
    document.addEventListener('visibilitychange', tellState);
    window.addEventListener('focus', tellState);
    window.addEventListener('blur', tellState);
    window.addEventListener('pageshow', tellState);
    queueMicrotask(tellState);
  };

  // ---- notifications (src/hostapi/notify.mbt): the browser's, while the page is open ----
  // One per tag (the browser replaces one of the same tag); a click brings the page to the front and gives `opens` to
  // the app (noticeText(0), once). Asked only from a press, as the browser lets a page ask. Pushes while no page is
  // open are the page's own (its service worker): it says its subscription as H.pushToken and its kind as
  // H.pushService (noticeText(1), (2)), and a push's notification clicked as H.noticeTapped(opens).
  const notices = new Map();
  let noticeOpened = '', noticeAnswer = -1;
  H.pushToken = '';
  H.pushService = '';
  H.noticeTapped = (opens) => { noticeOpened = String(opens); H.requestFrame(); };
  const canNotify = () => typeof Notification !== 'undefined';
  H.noticeShow = (channel, tag, title, body, opens) => {
    if (!canNotify() || Notification.permission !== 'granted') { H.log('NOTICE ' + tag + '\t' + title + '\t' + body); return; }
    try {
      const n = new Notification(title, { body, tag: tag || undefined });
      n.onclick = () => { window.focus(); n.close(); H.noticeTapped(opens); };
      if (tag) { notices.get(tag)?.close(); notices.set(tag, n); }
    } catch (e) { H.log('NOTICE ' + tag + '\t' + title + '\t' + body); }
  };
  H.noticeCancel = (tag) => { notices.get(tag)?.close(); notices.delete(tag); };
  // 0 what the browser lets the page show (1 granted, 2 denied, 4 default: never answered, and its prompt shown each
  // time it is asked, a prompt put away leaving it so: hostapi's "default", never "ask", which the app must remember
  // having asked); 1 ask (1: asked); 2 the answer (1 yes, 0 no or put away, -1 none yet); 3 its settings (none a page
  // opens); 4 a badge on the app's icon (none)
  H.noticeState = (what) => {
    if (!canNotify()) return what === 2 ? -1 : 0;
    if (what === 0) return Notification.permission === 'granted' ? 1 : Notification.permission === 'denied' ? 2 : 4;
    if (what === 1) {
      if (Notification.permission !== 'default') return 0;
      noticeAnswer = -1;
      Notification.requestPermission().then((p) => { noticeAnswer = p === 'granted' ? 1 : 0; H.requestFrame(); }, () => { noticeAnswer = 0; H.requestFrame(); });
      return 1;
    }
    if (what === 2) { const a = noticeAnswer; if (a !== -1) noticeAnswer = -1; return a; }
    return 0;
  };
  H.noticeText = (what) => {
    if (what === 1) return H.pushToken;
    if (what === 2) return H.pushToken ? H.pushService : '';
    if (what !== 0) return '';
    const o = noticeOpened;
    noticeOpened = '';
    return o;
  };

  // ---- messages from outside the frames (src/ui/messages.mbt; mbui's mb_post on the native hosts) ----
  // H.post(channel, json, bytes?): kept, the app told from the event loop, between frames (outside(OUTSIDE_POSTED):
  // ui's messages_between, as the Mac's host tells it), which takes all that came in their order, what changes only
  // signals then, and asks for a frame only where something is left for one. Never taken as a frame begins: there the
  // frame has read what it does again before what came is taken, and a change only the window's tree reads went
  // unseen till something else built the frame whole (2026-11-11).
  const posted = [];
  let postTaken = [], postCur = null;
  H.post = (channel, json, bytes) => {
    if (!channel) return;
    const first = posted.length === 0;
    posted.push([String(channel), String(json), bytes ? new Uint8Array(bytes) : new Uint8Array(0)]);
    if (!first) return;
    if (outside) queueMicrotask(() => outside(OUTSIDE_POSTED, 0, 0));
    else H.requestFrame();
  };
  H.postTake = () => {
    postTaken = postTaken.concat(posted.splice(0));
    return postTaken.length;
  };
  H.postNext = () => {
    postCur = postTaken.shift() || null;
    return postCur ? postCur[0] : '';
  };
  H.postJson = () => (postCur ? postCur[1] : '');
  H.postBytes = () => (postCur ? postCur[2] : new Uint8Array(0));
  H.autoLaunch = () => false;
  H.setAutoLaunch = () => false;
  H.hotkeySet = () => false;
  H.hotkeyClear = () => {};

  // ---- what the app awaits of the host (effect.mb's outside: src/ui/hostcall.mbt) ----
  // The app is told (outside(kind, id, state)) as the work it asked for is done: kind 1 an image decoded (id: the
  // image), 2 a native view ready (a page loaded, a video's first frame showable); state 1 done, -1 failed, once an
  // item; and (a view, 0) each time it waits on the app instead (a player's read asked of it): not the host's work
  // until the app answers. Always from the event loop, never inside a call of the app's (a frame, a read answered).
  // Each frame says at its end how many of its asks the host has not answered and what they are: a run to a declared
  // moment (shot_at) keeps its clock still while any is.
  // its kinds, named as src/ui/hostcall.mbt's outside_* (this host has no picker, gallery, marks or update; a frame
  // grab asked of a video fails at once, told so)
  const OUTSIDE_IMAGE = 1, OUTSIDE_VIEW = 2, OUTSIDE_GRAB = 6, OUTSIDE_CLIP = 9, OUTSIDE_POSTED = 11, OUTSIDE_STOOD = 13;
  let outside = null, awaiting = 0, why = '';
  const told = new Set();
  H.setOutside = (f) => { outside = f; return true; };
  H.frameAwaiting = (n, what) => { awaiting = n; why = what; };
  function tell(kind, id, state) {
    if (!outside) return;
    if (state !== 0) {
      const k = kind + ':' + id;
      if (told.has(k)) return;
      told.add(k);
    }
    queueMicrotask(() => outside(kind, id, state));
  }
  function resize() {
    resizeOnly();
    // (what text keeps forgotten between frames, never in one: textSweep)
    textSweep();
  }
  function resizeOnly() {
    const scale = hostWin.devicePixelRatio || 1;
    if (scale !== dpr) {
      dpr = scale;
      // Glyph pictures in the atlas were rasterized at the old scale. The UI keeps their boxes and atlas places until
      // the generation changes, so it must draw and place them again before presenting a frame at the new scale.
      textChanged();
      sizeDirty = true;
    }
    // The observer marks the size dirty only when it changes. On older browsers without one, measure each frame as
    // before. A fractional CSS size matters at browser zoom: clientWidth/clientHeight round it too early.
    if (!sizeDirty && sizeObserver) return;
    sizeDirty = false;
    const rect = canvas.getBoundingClientRect();
    rectLeft = rect.left;
    rectTop = rect.top;
    rectValid = true;
    cssW = rect.width;
    cssH = rect.height;
    const w = Math.round(cssW * dpr), h = Math.round(cssH * dpr);
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    // (the system's bars as the page's size changes: a phone turned, a window moved)
    if (barsSetUp && winActive === 0) barsNow();
  }

  // ---- WebGL2 renderer ----
  const VS = `#version 300 es
  layout(location=0) in vec4 a_rect;
  layout(location=1) in vec4 a_p;
  layout(location=2) in vec4 a_color;
  layout(location=3) in vec4 a_c2;
  layout(location=4) in vec4 a_clip;
  layout(location=5) in vec4 a_pad;
  layout(location=6) in vec4 a_rc;
  layout(location=7) in vec4 a_rs;
  layout(location=8) in vec4 a_rot;
  layout(location=9) in vec4 a_rr;
  layout(location=10) in vec4 a_oclip;
  layout(location=11) in vec4 a_orc;
  layout(location=12) in vec4 a_ors;
  layout(location=13) in vec4 a_fade;
  layout(location=14) in vec4 a_fadex;
  uniform vec2 u_vp;
  uniform vec2 u_origin;
  uniform vec4 u_gb;
  out vec2 v_pos; out vec2 v_cpos;
  flat out vec4 v_rect; flat out vec4 v_p; flat out vec4 v_color; flat out vec4 v_c2; flat out vec4 v_clip; flat out vec4 v_pad;
  flat out vec4 v_rc; flat out vec4 v_rs; flat out vec4 v_rr; flat out vec4 v_oclip; flat out vec4 v_orc; flat out vec4 v_ors;
  // how far each pixel is into its fades (scene.mbt 52-59: from its left, top, right, foot; 1 and past: whole), worked
  // out where it is drawn at its corners and taken across it as it goes straight
  out vec4 v_ramp;
  void main() {
    int vid = gl_VertexID;
    vec2 corner = vec2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0, (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);
    int kind = int(a_p.y + 0.5);
    bool merged_liquid = kind == 6 && a_pad.w > 0.0;
    float grow = kind == 2 ? a_p.w * 3.0 + 2.0 : (kind == 6 && a_pad.w <= 0.0) ? 2.0 : ((kind == 0 || kind == 4 || kind == 5 || kind == 8) ? 1.0 : 0.0);
    vec2 pos = a_rect.xy - grow + corner * (a_rect.zw + 2.0 * grow);
    if (merged_liquid) pos = mix(u_gb.xy, u_gb.zw, corner);
    // the pieces of shapes (kind 12): nothing drawn
    if (kind == 12) pos = vec2(0.0);
    // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (v_pos), its clip there
    // too or (35: one from outside what turned) where it is drawn (v_cpos)
    vec2 at = pos;
    if (a_rot.x != 0.0) { vec2 d = pos - a_rot.yz; float c = cos(a_rot.x), s = sin(a_rot.x); at = a_rot.yz + vec2(c * d.x - s * d.y, s * d.x + c * d.y); }
    vec2 rel = at - u_origin;
    gl_Position = vec4(rel.x / u_vp.x * 2.0 - 1.0, 1.0 - rel.y / u_vp.y * 2.0, 0.0, 1.0);
    v_pos = pos; v_cpos = a_rot.w > 0.5 ? at : pos; v_rect = a_rect; v_p = a_p; v_color = a_color; v_c2 = a_c2; v_clip = a_clip; v_pad = a_pad; v_rc = a_rc; v_rs = a_rs; v_rr = a_rr;
    // (a glyph's p.x, which it has no use for: how it is turned, for its texels taken whole where it is not)
    if (kind == 1 || kind == 3 || kind == 7) v_p.x = a_rot.x;
    if (kind == 4 && a_pad.z > 0.5) v_pad.x = a_rot.w;
    v_oclip = a_oclip; v_orc = a_orc; v_ors = a_ors;
    vec2 cq = a_rot.w > 0.5 ? at : pos;
    v_ramp = vec4(a_fadex.y > 0.0 ? (cq.x - a_fadex.x) / a_fadex.y : 2.0, a_fade.y > 0.0 ? (cq.y - a_fade.x) / a_fade.y : 2.0,
      a_fadex.w > 0.0 ? (a_fadex.z - cq.x) / a_fadex.w : 2.0, a_fade.w > 0.0 ? (a_fade.z - cq.y) / a_fade.w : 2.0);
  }`;
  const CORNERS = `
  // corner.sl begin (scripts/chk corner-sl: not edited here)
  #define float2 vec2
  #define float4 vec4
  // smooth.mbt's corners for the renderers; scripts/chk corner-sl makes corner_sl.h and web/host.js from it.
  //
  // How smooth a corner of radius r is where room is half its box's shorter side: 0 a circle's or a capsule's end, 1
  // superellipse(1.5) over r a quarter longer; between, as far as the room goes.
  float mb_smoothness(float r, float room) {
    return r <= 0.0 ? 0.0 : clamp((room - r) / (0.25 * r), 0.0, 1.0);
  }
  // How much of its curve a capsule's end has room for along a side of half ha.
  float mb_capsule_room(float ha, float rr) {
    return min((ha - rr) / (0.4 * rr), 1.0);
  }
  // A capsule's end as Apple draws one (smooth.mbt capsule_ease): how much further in than the circle it lies, in r, u r
  // from the tip, k the share of the room the curve takes along the edge the box has (mb_capsule_room); an octic from the circle's height and
  // first three rates of change at 1 - 0.675 k to the edge's at 1 + 0.4 k, with k^2.5 t^4 (1 - t)^4: how much it bends
  // never jumps or turns at once.
  float mb_capsule_ease(float u, float k) {
    float u0 = 1.0 - 0.675 * k;
    float u1 = 1.0 + 0.4 * k;
    if (k <= 0.0 || u <= u0 || u >= u1) return 0.0;
    float h = u1 - u0;
    float t = (u - u0) / h;
    float t2 = t * t;
    float t3 = t2 * t;
    float t4 = t3 * t;
    float m = 1.0 - t;
    float m2 = m * m;
    float s = sqrt(u0 * (2.0 - u0));
    float v = 1.0 - u0;
    float s3 = s * s * s;
    float c0 = 1.0 - s;
    float c1 = -v / s * h;
    float c2 = h * h / s3;
    float c3 = -3.0 * v * h * h * h / (s3 * s * s);
    float w0 = 1.0 - t4 * (35.0 - 84.0 * t + 70.0 * t2 - 20.0 * t3);
    float w1 = t - t4 * (20.0 - 45.0 * t + 36.0 * t2 - 10.0 * t3);
    float w2 = (t2 - t4 * (10.0 - 20.0 * t + 15.0 * t2 - 4.0 * t3)) / 2.0;
    float w3 = (t3 - t4 * (4.0 - 6.0 * t + 4.0 * t2 - t3)) / 6.0;
    float eased = c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3 + k * k * sqrt(k) * t4 * m2 * m2;
    float circ = u < 1.0 ? 1.0 - sqrt(u * (2.0 - u)) : 0.0;
    return eased - circ;
  }
  #ifndef MB_CORNER_SCALARS
  // The signed distance of p (from a box's middle) from that box, hs its half sides, its corners r (at most the shorter
  // half) s smooth: |x|^n + |y|^n = R^n about each corner's centre, n from 2 to 2^1.5 and R from r to 1.25 r as s goes
  // from 0 to 1. 0 on the curve; off it, the curve's value over how fast it grows there (along its normal, to first
  // order). At s = 0 a round corner's, as before. Only within band of the curve is it worked out (two powers a pixel):
  // the curve lies between the circle of R and that of R 2^(1/2 - 1/n) (under 1.107 R), and further than band inside
  // the one or outside the other the round distance has its sign and is as far, which is all a cover, an edge band
  // wide or a shadow that blurred says of it. (mb_sd_corner below: this and a capsule's end easing into its edges.)
  float mb_corner_shape(float2 p, float2 hs, float r, float s, float band) {
    float R = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));
    float2 q = abs(p) - hs + R;
    float2 m = max(q, 0.0);
    float l = length(m);
    if (s <= 0.0 || min(m.x, m.y) <= 0.0 || l <= R - band || l >= 1.107 * R + band) return l + min(max(q.x, q.y), 0.0) - R;
    float hi = max(m.x, m.y);
    float t = min(m.x, m.y) / hi;
    if (s >= 1.0) {
      // wholly smooth (nearly every corner): the two factors below as polynomials in t, no power (smooth.mbt
      // smooth_a, smooth_b: within 2e-5 of them, a hundredth of a pixel over a radius of 200)
      float A = 1.0000098 + t * (-0.00106380035 + t * (0.0390446602 + t * (1.21491043 + t * (-1.49650831 + t * (1.90947795 + t * (-2.77580972 + t * (2.11536546 + t * -0.591224537)))))));
      float B = 1.00001404 + t * (-0.00136262193 + t * (0.039570688 + t * (0.648050719 + t * (-0.725922772 + t * (0.327888394 + t * (-0.914717465 + t * (1.13728689 + t * -0.403984265)))))));
      return hi * A - R * B;
    }
    float n = 2.0 + 0.8284271247461903 * s;
    float tn1 = pow(t, n - 1.0);
    float tn = tn1 * t;
    float u = pow(1.0 + tn, 1.0 / n);
    return (hi * u - R) * (1.0 + tn) / (u * sqrt(1.0 + tn1 * tn1));
  }
  // How much further out than the round corner's (rr) a point is once the corner eases into one of its box's edges:
  // along the point's coordinate that way and ha that half side, across and hc the other's (from the box's middle,
  // positive); as far as the corner has no room across, moved along the round corner's normal
  // (smooth.mbt capsule_tail).
  float mb_capsule_tail(float along, float across, float ha, float hc, float rr) {
    float k = mb_capsule_room(ha, rr);
    float tight = 1.0 - mb_smoothness(rr, hc);
    if (k <= 0.0 || tight <= 0.0) return 0.0;
    float e = mb_capsule_ease((ha - along) / rr, k);
    if (e == 0.0) return 0.0;
    float qa = along - ha + rr;
    float qc = across - hc + rr;
    float ma = max(qa, 0.0);
    float mc = max(qc, 0.0);
    float l = sqrt(ma * ma + mc * mc);
    float n = l > 0.0 ? mc / l : (qc >= qa ? 1.0 : 0.0);
    return tight * e * rr * n;
  }
  // The signed distance of p (from a box's middle) from that box (mb_corner_shape's), a capsule's end easing into its
  // long edges.
  float mb_sd_corner(float2 p, float2 hs, float r, float s, float band) {
    float d = mb_corner_shape(p, hs, r, s, band);
    float rr = min(r * (1.0 + 0.25 * s), min(hs.x, hs.y));
    if (s >= 1.0 || rr <= 0.0) return d;
    float2 a = abs(p);
    return d + (1.0 - s) * (mb_capsule_tail(a.x, a.y, hs.x, hs.y, rr) + mb_capsule_tail(a.y, a.x, hs.y, hs.x, rr));
  }
  // Which of a box's corners' radii r (top left, top right, bottom right, bottom left: scene.mbt 36-39) p (from its
  // middle) is drawn by: the one of its quarter's corner.
  float mb_corner_of(float2 p, float4 r) {
    return p.x < 0.0 ? (p.y < 0.0 ? r.x : r.w) : (p.y < 0.0 ? r.y : r.z);
  }
  // The signed distance of p from a clip (scene.mbt 16-19 and 24-31, or its outer's 40-51): c its rect (x0 y0 x1 y1), r
  // its corners (top left, then clockwise; 0 square), s how smooth each is. A corner is the curve of the box whose corner
  // it is, where that box has it (its radius as that box drew it): drawn there whatever the clip's own size, so a band a
  // few points high sharing a frame's corner is cut by the frame's very curve, not by one flattened to its half height.
  // Each corner against its own corner point; the rect's edges straight.
  float mb_clip_corner(float2 p, float2 k, float2 inward, float2 hs, float r, float s, float band) {
    float R = r * (1.0 + 0.25 * s);
    float2 hv = max(hs, float2(R, R));
    return mb_sd_corner(max(hv - (p - k) * inward, float2(0.0, 0.0)), hv, r, s, band);
  }
  float mb_sd_clip(float2 p, float4 c, float4 r, float4 s, float band) {
    float2 hs = max((c.zw - c.xy) * 0.5, float2(0.0, 0.0));
    float2 q = abs(p - (c.xy + hs)) - hs;
    float d = length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
    if (r.x > 0.0) d = max(d, mb_clip_corner(p, c.xy, float2(1.0, 1.0), hs, r.x, s.x, band));
    if (r.y > 0.0) d = max(d, mb_clip_corner(p, c.zy, float2(-1.0, 1.0), hs, r.y, s.y, band));
    if (r.z > 0.0) d = max(d, mb_clip_corner(p, c.zw, float2(-1.0, -1.0), hs, r.z, s.z, band));
    if (r.w > 0.0) d = max(d, mb_clip_corner(p, c.xw, float2(1.0, -1.0), hs, r.w, s.w, band));
    return d;
  }
  // A box's own corners: r at most its shorter half, as smooth as its size has room for (band: mb_sd_corner's).
  float mb_sd_box(float2 p, float2 hs, float r, float band) {
    float room = min(hs.x, hs.y);
    float rr = min(r, room);
    return mb_sd_corner(p, hs, rr, mb_smoothness(rr, room), band);
  }
  // A contained blur extends the picture at its actual curved boundary, rather than cropping all four straight edges
  // to a corner's inset. Points already in the picture stay where they are. Near a curve, keep a little inside its
  // antialiased edge so the bilinear sample itself cannot bring in the background outside the clip.
  #ifndef MB_CONTAINED_LOOP
  #define MB_CONTAINED_LOOP
  #endif
  float mb_max4(float4 v) { return max(max(v.x, v.y), max(v.z, v.w)); }
  float mb_contained_rect_dist(float2 p, float4 c) {
    float2 hs = (c.zw - c.xy) * 0.5;
    float2 q = abs(p - c.xy - hs) - hs;
    return length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
  }
  // The same clip as mb_sd_clip, traversed so a runtime shader compiler need only compile one corner's calculation.
  float mb_contained_clip_dist(float2 p, float4 c, float4 r, float4 s) {
    float2 hs = max((c.zw - c.xy) * 0.5, float2(0.0, 0.0));
    float2 q = abs(p - (c.xy + hs)) - hs;
    float d = length(max(q, float2(0.0, 0.0))) + min(max(q.x, q.y), 0.0);
    MB_CONTAINED_LOOP for (int i = 0; i < 4; i++) {
      if (r[i] > 0.0) {
        float2 inward = float2(i == 0 || i == 3 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
        float2 corner = float2(inward.x > 0.0 ? c.x : c.z, inward.y > 0.0 ? c.y : c.w);
        d = max(d, mb_clip_corner(p, corner, inward, hs, r[i], s[i], 1e9));
      }
    }
    return d;
  }
  float mb_contained_dist(float2 p, float4 box, float4 rr, float4 clip, float4 rc, float4 rs,
                          float4 outer, float4 orc, float4 ors) {
    float2 hs = (box.zw - box.xy) * 0.5;
    float2 q = p - box.xy - hs;
    float d = max(mb_sd_box(q, hs, mb_corner_of(q, rr), 1e9), mb_contained_clip_dist(p, clip, rc, rs));
    if (mb_max4(orc) > 0.0) d = max(d, mb_contained_clip_dist(p, outer, orc, ors));
    return d;
  }
  // Skip the distance and search entirely along the straight parts of the edges and in the middle of the picture.
  bool mb_contained_corner(float2 p, float4 c, float4 r, float pad) {
    // A capsule's easing can reach two radii along its long edge.
    float4 R = r * 2.5 + float4(pad, pad, pad, pad);
    return (r.x > 0.0 && p.x < c.x + R.x && p.y < c.y + R.x) ||
           (r.y > 0.0 && p.x > c.z - R.y && p.y < c.y + R.y) ||
           (r.z > 0.0 && p.x > c.z - R.z && p.y > c.w - R.z) ||
           (r.w > 0.0 && p.x < c.x + R.w && p.y > c.w - R.w);
  }
  float2 mb_contained_point(float2 p, float4 box, float4 rr, float4 clip, float4 rc, float4 rs,
                            float4 outer, float4 orc, float4 ors, float pixel) {
    float pad = 1.5 * pixel;
    if (!mb_contained_corner(p, box, rr, pad) && !mb_contained_corner(p, clip, rc, pad) &&
        !mb_contained_corner(p, outer, orc, pad)) return p;
    float2 lo = max(box.xy, clip.xy), hi = min(box.zw, clip.zw);
    if (mb_max4(orc) > 0.0) { lo = max(lo, outer.xy); hi = min(hi, outer.zw); }
    float2 inside = (lo + hi) * 0.5;
    float2 outside = p;
    float id = 0.0, inset = 0.0;
    // One distance evaluation in the shader: check p, find an interior point, then bisect towards the edge twelve times.
    // A clip can leave only a corner of the box visible, so try each shape's centre clamped to the intersection too.
    MB_CONTAINED_LOOP for (int i = 0; i < 17; i++) {
      float2 probe = p;
      if (i == 1) probe = (lo + hi) * 0.5;
      else if (i == 2) probe = clamp((clip.xy + clip.zw) * 0.5, lo, hi);
      else if (i == 3) probe = clamp((box.xy + box.zw) * 0.5, lo, hi);
      else if (i == 4) probe = mb_max4(orc) > 0.0 ? clamp((outer.xy + outer.zw) * 0.5, lo, hi) : inside;
      else if (i > 4) probe = (outside + inside) * 0.5;
      float d = mb_contained_dist(probe, box, rr, clip, rc, rs, outer, orc, ors);
      if (i == 0) {
        if (d <= -pad) return p;
        // Near a straight edge, the original pixel is already picture even in the antialiasing band.
        float straight = max(mb_contained_rect_dist(p, box), mb_contained_rect_dist(p, clip));
        if (mb_max4(orc) > 0.0) straight = max(straight, mb_contained_rect_dist(p, outer));
        if (d <= straight + 0.001 * pixel) return p;
      } else if (i <= 4) {
        if (i == 1 || d < id) { inside = probe; id = d; }
        if (i == 4) {
          if (id >= 0.0) return p;
          inset = min(pad, -id * 0.5);
        }
      } else if (d > -inset) outside = probe;
      else inside = probe;
    }
    return inside;
  }
  // A shadow as Core Animation draws one (CALayer shadowRadius: a Gaussian blur of the shape, sigma its radius): the box
  // of half sides hs about p, its corners r, blurred by sigma; how much of it covers p, 0 … 1. The blur across worked
  // out whole (erf); along, four samples of the Gaussian over where it is not nothing (Evan Wallace's rounded box shadow).
  float mb_erf(float x) {
    float s = sign(x);
    float a = abs(x);
    float t = 1.0 + (0.278393 + (0.230389 + 0.078108 * (a * a)) * a) * a;
    t = t * t;
    return s - s / (t * t);
  }
  float mb_shadow_row(float x, float y, float sigma, float r, float2 hs) {
    float delta = min(hs.y - r - abs(y), 0.0);
    float curved = hs.x - r + sqrt(max(0.0, r * r - delta * delta));
    float k = 0.7071067811865476 / sigma;
    return 0.5 * (mb_erf((x + curved) * k) - mb_erf((x - curved) * k));
  }
  float mb_shadow(float2 p, float2 hs, float r, float sigma) {
    float rr = min(r, min(hs.x, hs.y));
    float lo = clamp(-3.0 * sigma, p.y - hs.y, p.y + hs.y);
    float hi = clamp(3.0 * sigma, p.y - hs.y, p.y + hs.y);
    float st = (hi - lo) / 4.0;
    float y = lo + st * 0.5;
    float v = 0.0;
    for (int i = 0; i < 4; i++) {
      float g = exp(-(y * y) / (2.0 * sigma * sigma)) / (2.5066282746310002 * sigma);
      v += mb_shadow_row(p.x, p.y - y, sigma, rr, hs) * g * st;
      y += st;
    }
    return v;
  }
  // A shape (src/ui/shape.mbt, scene.mbt's kind 11): its pieces s (x0 y0 x1 y1 as shares of its band's rect r) worked
  // into the pixel about p, scale its pixels a point. A fill's: each piece's crossings of 4 rows across the pixel, each
  // counted by how much of the row lies left of it (+ going down, - going up); their sums over every piece, the rows'
  // winding numbers across the pixel, make its cover (even_odd 1: by the even-odd rule, else the nonzero one).
  // (mb4: v in all four; Direct3D's float4 takes no single number)
  float4 mb4(float v) {
    return float4(v, v, v, v);
  }
  float4 mb_path_rows(float4 s, float4 r, float2 p, float scale) {
    float2 a = r.xy + s.xy * r.zw;
    float2 b = r.xy + s.zw * r.zw;
    if (a.y == b.y) return mb4(0.0);
    float dir = b.y > a.y ? 1.0 : -1.0;
    float4 ys = mb4(p.y) + float4(-0.375, -0.125, 0.125, 0.375) / scale;
    float4 in_ = step(mb4(min(a.y, b.y)), ys) * (mb4(1.0) - step(mb4(max(a.y, b.y)), ys));
    float4 xs = mb4(a.x) + (ys - mb4(a.y)) * ((b.x - a.x) / (b.y - a.y));
    return in_ * dir * clamp((xs - mb4(p.x)) * scale + mb4(0.5), mb4(0.0), mb4(1.0));
  }
  float mb_path_cover(float4 w, float even_odd) {
    float4 a = abs(w);
    float4 f = a - floor(a * 0.5) * 2.0;
    float4 c = even_odd > 0.5 ? mb4(1.0) - abs(mb4(1.0) - f) : min(a, mb4(1.0));
    return dot(c, mb4(0.25));
  }
  // A stroke's: how far p is from a piece (its ends round).
  float mb_seg_dist(float4 s, float4 r, float2 p) {
    float2 a = r.xy + s.xy * r.zw;
    float2 ab = r.xy + s.zw * r.zw - a;
    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
    return length(p - a - ab * h);
  }
  // Which of a data instance's (kind 12) fours piece i is in: 0, 2, 3, 4, 6, 7 (shape.mbt seg_slots), six to an instance.
  int mb_seg_slot(int i) {
    int s = i - (i / 6) * 6;
    return s + (s >= 1 ? 1 : 0) + (s >= 4 ? 1 : 0);
  }
  // How far to move a smooth ground (glass's frost) at the pixel px (in pixels) before it is written to 8 bits a
  // channel, in steps of 1/255: Skia's ordered dither (GrDitherEffect, an 8x8 Bayer matrix by the pixel's place), never
  // half a step either way. Without it a slope of a few steps across a wide frost is written as flat bands, an edge where
  // each step is (contour lines); with it each pixel is the step above or below as often as the slope is near it, and
  // a value already on a step stays it.
  float mb_dither(float2 px) {
    int x = int(floor(px.x)) & 7;
    int y = (int(floor(px.y)) & 7) ^ x;
    int m = ((y & 1) << 5) | ((x & 1) << 4) | ((y & 2) << 2) | ((x & 2) << 1) | ((y & 4) >> 1) | ((x & 4) >> 2);
    return float(m) / 64.0 - 63.0 / 128.0;
  }
  #endif
  // corner.sl end
  `;
  const FS = `#version 300 es
  precision highp float;
  precision highp int;
  in vec2 v_pos; in vec2 v_cpos;
  flat in vec4 v_rect; flat in vec4 v_p; flat in vec4 v_color; flat in vec4 v_c2; flat in vec4 v_clip; flat in vec4 v_pad;
  flat in vec4 v_rc; flat in vec4 v_rs; flat in vec4 v_rr; flat in vec4 v_oclip; flat in vec4 v_orc; flat in vec4 v_ors;
  in vec4 v_ramp;
  uniform float u_scale;
  uniform sampler2D u_atlas;
  uniform sampler2D u_img;
  // glass (src/ui/glass.mbt): the blurred copy under it and where a point is in it (uv = p * u_map.xy + u_map.zw, kept
  // in u_uvc), a liquid group's shapes and corners, how many
  uniform highp sampler2D u_bd;
  uniform vec4 u_map;
  uniform vec4 u_uvc;
  // a liquid group's bounds (as the vertex shader has them)
  uniform vec4 u_gb;
  uniform vec4 u_shape[8];
  uniform vec4 u_rad[8];
  uniform int u_n;
  uniform vec2 u_glight;
  uniform highp sampler2D u_ad;
  uniform vec4 u_ad_box[16];
  uniform int u_ad_n;
  // the pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), 2040 fours
  // (136 instances) a row
  uniform highp sampler2D u_segs;
  out vec4 o;
  ${CORNERS}
  float sd_rr(vec2 p, vec4 r, vec4 rad) {
    vec2 hs = r.zw * 0.5;
    return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);
  }
  // a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its
  // radius), met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle
  float notch_cut(float d, vec2 p, vec4 r, vec4 pad) {
    if (pad.z <= 0.0) return d;
    float b = pad.z - length(p - vec2(r.x + r.z * 0.5, r.y + pad.y));
    float f = max(pad.w, 0.0);
    vec2 u = max(vec2(f + d, f + b), 0.0);
    return min(-f, max(d, b)) + length(u);
  }
  float smin_k(float a, float b, float k) {
    if (k <= 0.0) return min(a, b);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
  }
  float sd_group(vec2 p, float k) {
    float d = 1e9;
    for (int i = 0; i < 8; i++) {
      if (i >= u_n) break;
      d = smin_k(d, sd_rr(p, u_shape[i], u_rad[i]), k);
    }
    return d;
  }
  // Integral of linear ramp from 0 to w (contourOffset = 0, width w in device px)
  float mb_contour_int(float t, float w) {
    float u = clamp(t, 0.0, w);
    return u - u * u / (2.0 * w);
  }
  vec3 backdrop(vec2 p) {
    return texture(u_bd, clamp(p * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw)).rgb;
  }
  float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
  float mb_backdrop_luma_rect(vec2 c, vec2 h) {
    float sum = 0.0;
    float mx1 = -1.0, mx2 = -1.0;
    float mn1 = 2.0, mn2 = 2.0;
    for (int iy = -1; iy <= 1; iy++) {
      float py = c.y + float(iy) * (h.y * 0.60);
      for (int ix = -2; ix <= 2; ix++) {
        float px = c.x + float(ix) * (h.x * 0.38);
        float y = luma(backdrop(vec2(px, py)));
        sum += y;
        if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }
        if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }
      }
    }
    return (sum - mx1 - mx2 - mn1 - mn2) / 11.0;
  }
  float mb_unpack16(vec2 rg) {
    float hi = floor(clamp(rg.x, 0.0, 1.0) * 255.0 + 0.5);
    float lo = floor(clamp(rg.y, 0.0, 1.0) * 255.0 + 0.5);
    return (hi * 256.0 + lo) / 65535.0;
  }
  float ad_sample(vec2 ac, float fallback_r, bool is_dark_glass) {
    if (u_ad_n > 0) {
      int best = -1;
      float best_d = 1e9;
      for (int i = 0; i < 16; i++) {
        if (i >= u_ad_n) break;
        float d = length(ac - u_ad_box[i].xy);
        if (d <= 2.0 && d < best_d) { best = i; best_d = d; }
      }
      if (best < 0) {
        best_d = 1e9;
        for (int i = 0; i < 16; i++) {
          if (i >= u_ad_n) break;
          vec2 diff = abs(ac - u_ad_box[i].xy);
          if (diff.x <= u_ad_box[i].z + 2.0 && diff.y <= u_ad_box[i].w + 2.0) {
            float d = length(diff);
            if (d < best_d) { best = i; best_d = d; }
          }
        }
      }
      if (best >= 0) {
        return mb_unpack16(texelFetch(u_ad, ivec2(best, 0), 0).rg);
      }
    }
    float bgL = mb_backdrop_luma_rect(ac, vec2(max(fallback_r, 1.0)));
    return is_dark_glass ? smoothstep(0.35, 0.85, bgL) : (1.0 - smoothstep(0.30, 0.42, bgL));
  }
  vec3 mb_adaptive_ink(vec3 rgb, float darkT) {
    float ch = max(max(rgb.r, rgb.g), rgb.b) - min(min(rgb.r, rgb.g), rgb.b);
    if (ch <= 0.08) {
      float origL = luma(rgb);
      if (origL < 0.5) {
        float inkT = smoothstep(0.0, 1.0, darkT);
        float lightL = clamp(1.06 - origL, 0.68, 0.98);
        rgb = mix(rgb, vec3(lightL), inkT);
      }
    }
    return rgb;
  }
  // how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth
  // each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it
  float clip_cover(vec2 p, vec4 c, vec4 r, vec4 s, float scale) {
    float d = mb_sd_clip(p, c, r, s, 1.0 + 2.0 / scale);
    return clamp(0.5 - d * scale, 0.0, 1.0);
  }
  // what it shows at p, as if uncut
  void shade(vec2 p, float fade_r) {
    #ifndef ONE_KIND
    #define ONE_KIND -1
    #endif
    int kind = ONE_KIND == 13 ? 6 : (ONE_KIND >= 0 ? ONE_KIND : int(v_p.y + 0.5));
    #if ONE_KIND < 0
    if (kind == 9) { vec2 hh = v_rect.zw * 0.5; float rr = min(mb_corner_of(p - v_rect.xy - hh, v_rr), min(hh.x, hh.y)); vec2 q = abs(p - v_rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; o = vec4(0.0); return; }
    #endif
    vec4 col = v_color;
    #if ONE_KIND < 0 || ONE_KIND == 11
    if (kind == 11) {
      // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x; p.x half its stroke's width (0: a fill,
      // c2.z 1 by the even-odd rule)
      int first = int(v_c2.x + 0.5), n = int(v_c2.y + 0.5);
      float a;
      if (v_p.x > 0.0) {
        float d = 1e9;
        for (int i = first; i < first + n; i++) { int t = (i / 6) * 15 + mb_seg_slot(i); d = min(d, mb_seg_dist(texelFetch(u_segs, ivec2(t % 2040, t / 2040), 0), v_rect, p)); }
        a = clamp(0.5 - (d - v_p.x) * u_scale, 0.0, 1.0);
      } else {
        vec4 w = vec4(0.0);
        for (int i = first; i < first + n; i++) { int t = (i / 6) * 15 + mb_seg_slot(i); w += mb_path_rows(texelFetch(u_segs, ivec2(t % 2040, t / 2040), 0), v_rect, p, u_scale); }
        a = mb_path_cover(w, v_c2.z);
      }
      if (v_pad.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(v_pad.yz, v_pad.w * 0.5, false));
      o = vec4(col.rgb, 1.0) * col.a * a;
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 10
    if (kind == 10) {
      // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round
      vec2 a = v_rect.xy + v_c2.xy * v_rect.zw, ab = v_rect.xy + v_c2.zw * v_rect.zw - a;
      float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
      float d = length(p - a - ab * h) - v_p.x;
      if (v_pad.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(v_pad.yz, v_pad.w * 0.5, false));
      o = vec4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u_scale, 0.0, 1.0);
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 1 || ONE_KIND == 3
    if (kind == 1 || kind == 3 || kind == 7) {
      // within its own cell (c2: where in the atlas, in texels), however its rect is stretched or turned: a sample
      // past the cell's edge texels would blend in what lies beside it (another glyph, one left from before the
      // atlas started over). One drawn as big as its picture, not turned, its corner on a pixel: each pixel its
      // texel's centre, as win_render.cpp takes it (worked out of where it is across the rect, a float's division
      // took a texel's neighbour in where its rounding fell, at 3, 2.625 and 1.5 pixels a point and far across)
      vec2 off = abs(v_rect.zw * u_scale - v_c2.zw);
      vec2 r0 = v_rect.xy * u_scale, r0i = floor(r0 + 0.5);
      bool exact = v_p.x == 0.0 && max(off.x, off.y) <= 0.5 && max(abs(r0.x - r0i.x), abs(r0.y - r0i.y)) <= 0.05;
      vec2 tex = exact ? floor(p * u_scale - r0i) + 0.5 : (p - v_rect.xy) / v_rect.zw * v_c2.zw;
      vec2 uv = clamp(v_c2.xy + tex, v_c2.xy + 0.5, v_c2.xy + v_c2.zw - 0.5) / ${ATLAS}.0;
      vec4 t = texture(u_atlas, uv);
      #if ONE_KIND < 0
      if (kind == 7) {
        // inked by how light what is under its glass is, looked at round the glass's middle
        float darkT = ad_sample(v_pad.yz, v_pad.w * 0.5, false);
        vec3 ink = mb_adaptive_ink(col.rgb, darkT);
        o = vec4(ink, 1.0) * (t.a * col.a);
        return;
      }
      #endif
      o = kind == 1 ? vec4(col.rgb, 1.0) * (t.a * col.a) : t * col.a;
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 6 || ONE_KIND == 13
    if (kind == 6) {
      // Copyright 2025, Tim Lehmann for whynotmake.it. Adapted from flutter_liquid_glass
      // liquid_glass_final_render_core.glsl, Apache-2.0.
      float k = v_pad.w;
      vec4 s_rr = max(max(v_rr.x, v_rr.y), max(v_rr.z, v_rr.w)) > 0.0 ? v_rr : vec4(v_p.x);
      float d;
      float halfMinor = 1e9;
      #if ONE_KIND == 13
      d = sd_rr(p, v_rect, s_rr);
      halfMinor = min(v_rect.z, v_rect.w) * 0.5;
      #else
      if (k <= 0.0) {
        d = sd_rr(p, v_rect, s_rr);
        halfMinor = min(v_rect.z, v_rect.w) * 0.5;
      } else {
        d = 1e9;
        for (int i = 0; i < 8; i++) {
          if (i >= u_n) break;
          float di = sd_rr(p, u_shape[i], u_rad[i]);
          float hi = min(u_shape[i].z, u_shape[i].w) * 0.5;
          if (i == 0) {
            d = di;
            halfMinor = hi;
          } else {
            float h = max(k - abs(d - di), 0.0) / k;
            float w = d < di ? 0.5 * h : 1.0 - 0.5 * h;
            d = min(d, di) - h * h * k * 0.25;
            halfMinor = mix(halfMinor, hi, w);
          }
        }
      }
      #endif
      halfMinor = max(halfMinor, 1.0);
      float sd_px = -d * u_scale;
      float materialAlpha = clamp(sd_px + 0.5, 0.0, 1.0);
      float edgeW = 0.75 * u_scale;
      float outward = -sd_px;
      float ext_cov = mb_contour_int(max(outward + 0.5, 0.0), edgeW)
                    - mb_contour_int(max(outward - 0.5, 0.0), edgeW);
      if (materialAlpha < 0.01 && ext_cov < 0.01) discard;
      float regMix = smoothstep(0.105, 0.305, col.a);
      bool is_clear = (regMix <= 0.0);
      bool is_adaptive = v_c2.z < -0.5;
      float spot_raw = is_adaptive ? (-v_c2.z - 1.0) : v_c2.z;
      bool is_dark = (!is_clear && luma(col.rgb) < 0.35);
      float inward = max(-d, 0.0);
      float rawBevel = max(v_c2.y, 0.0);
      float rawAmount = max(v_pad.y, 0.0);
      float lensScale = min(1.0, halfMinor / max(rawBevel, 0.001));
      float clearBevel = rawBevel * lensScale;
      float clearAmount = rawAmount * lensScale;
      float regBevel = min(rawBevel, 0.5 * halfMinor);
      float regAmount = min(rawAmount, halfMinor);
      float bevel = mix(clearBevel, regBevel, regMix);
      float amount = mix(clearAmount, regAmount, regMix);
      vec2 surfaceNormal = vec2(0.0, 0.0);
      float shortening = 0.0;
      vec2 disp = vec2(0.0, 0.0);
      bool need_grad = (inward < max(bevel, 23.0)) || (ext_cov > 0.0);
      if (need_grad) {
        float e = 0.5;
        #if ONE_KIND == 13
        vec2 grad = vec2(
            sd_rr(p + vec2(e, 0.0), v_rect, s_rr) - sd_rr(p - vec2(e, 0.0), v_rect, s_rr),
            sd_rr(p + vec2(0.0, e), v_rect, s_rr) - sd_rr(p - vec2(0.0, e), v_rect, s_rr)
          ) / (2.0 * e);
        #else
        vec2 grad = k <= 0.0
          ? vec2(
              sd_rr(p + vec2(e, 0.0), v_rect, s_rr) - sd_rr(p - vec2(e, 0.0), v_rect, s_rr),
              sd_rr(p + vec2(0.0, e), v_rect, s_rr) - sd_rr(p - vec2(0.0, e), v_rect, s_rr)
            ) / (2.0 * e)
          : vec2(
              sd_group(p + vec2(e, 0.0), k) - sd_group(p - vec2(e, 0.0), k),
              sd_group(p + vec2(0.0, e), k) - sd_group(p - vec2(0.0, e), k)
            ) / (2.0 * e);
        #endif
        float gradLen = length(grad);
        surfaceNormal = gradLen > 0.0001 ? grad / gradLen : vec2(0.0, 0.0);
        shortening = sqrt(clamp(gradLen, 0.0, 1.0));
        if (inward < bevel && bevel > 0.001 && amount > 0.0) {
          float bevelX = 1.0 - clamp(inward / bevel, 0.0, 1.0);
          float mag = amount * (1.0 - sqrt(max(1.0 - bevelX * bevelX, 0.0))) * shortening;
          disp = surfaceNormal * (-mag);
        }
      }
      float lensZoom = (v_p.w < 0.0) ? clamp(1.0 - v_p.w, 1.0, 3.0) : 1.0;
      vec2 sampleBase = p;
      if (lensZoom > 1.0001) {
        #if ONE_KIND == 13
        vec2 zoomC = v_rect.xy + v_rect.zw * 0.5;
        #else
        vec2 zoomC = (k <= 0.0) ? (v_rect.xy + v_rect.zw * 0.5) : ((u_gb.xy + u_gb.zw) * 0.5);
        #endif
        sampleBase = zoomC + (p - zoomC) / lensZoom;
      }
      vec3 refractColor;
      if (inward >= bevel || abs(v_pad.z) * amount * u_scale <= 0.25) {
        refractColor = backdrop(sampleBase + disp);
      } else {
        float ds = v_pad.z * 0.5;
        refractColor = vec3(
          backdrop(sampleBase + disp * (1.0 + ds)).r,
          backdrop(sampleBase + disp).g,
          backdrop(sampleBase + disp * (1.0 - ds)).b
        );
      }
      vec3 emission;
      float transmittance;
      float lift;
      float chromaGain;
      float contourStr;
      float contourDirAmt;
      float bevelShadowStr;
      float glintLum;
      float glintFaceGain;
      float glintVib;
      float fogT = 0.0;
      if (is_clear) {
        // iOS 27 clear liquid glass: col.a == 0.0 keeps crystal-clear zero-veil optical lens
        // (lifted tab-bar / toggle / slider thumb & loupe), while Glass::clear() (col.a ~ 0.102)
        // blends smoothly into the +0.126 translucent micro-veil over media.
        float clearVeil = smoothstep(0.005, 0.102, col.a);
        emission = vec3(1.0, 1.0, 1.0) * (0.126 * clearVeil);
        transmittance = mix(1.0, 0.90, clearVeil);
        lift = mix(0.0, 0.10, clearVeil);
        chromaGain = mix(1.06, 1.0, clearVeil);
        contourStr = mix(0.24, 0.25, clearVeil);
        contourDirAmt = mix(0.85, 0.77, clearVeil);
        bevelShadowStr = mix(0.045, 0.04, clearVeil);
        glintLum = mix(1.6, 1.2, clearVeil);
        glintFaceGain = mix(0.0, 0.25, clearVeil);
        glintVib = mix(2.85, 1.5, clearVeil);
      } else if (is_adaptive) {
        #if ONE_KIND == 13
        vec2 ac = v_rect.xy + v_rect.zw * 0.5;
        float ar = max(min(v_rect.z, v_rect.w) * 0.5, 1.0) * 0.5;
        #else
        vec2 ac = (k <= 0.0) ? (v_rect.xy + v_rect.zw * 0.5) : ((u_gb.xy + u_gb.zw) * 0.5);
        float ar = ((k <= 0.0) ? max(min(v_rect.z, v_rect.w) * 0.5, 1.0) : max(min(u_gb.z - u_gb.x, u_gb.w - u_gb.y) * 0.5, 1.0)) * 0.5;
        #endif
        float val = ad_sample(ac, ar, is_dark);
        float baseDens = (col.a > 0.41) ? col.a : 0.30;
        if (is_dark) {
          float brightT = val;
          fogT = brightT;
          float dens = max(baseDens, mix(baseDens, 0.64, brightT));
          float extra = clamp((dens - 0.30) / (1.0 - 0.30), 0.0, 1.0);
          emission = mix(vec3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), vec3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);
          transmittance = mix(0.54, 0.0, extra);
          lift = mix(0.36, 0.0, extra);
          chromaGain = mix(0.92, 0.0, extra);
          contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;
          glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;
        } else {
          float darkMix = val;
          fogT = darkMix;
          float extra = clamp((baseDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);
          float darkDens = max(baseDens, mix(baseDens, 0.52, darkMix));
          float darkExtra = clamp((darkDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);
          vec3 lightEm = vec3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * baseDens;
          vec3 darkEm = mix(vec3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), vec3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), darkExtra);
          emission = mix(lightEm, darkEm, darkMix);
          transmittance = mix(mix(0.70, 0.0, extra), mix(0.54, 0.0, darkExtra), darkMix);
          lift = mix(mix(0.16, 0.0, extra), mix(0.36, 0.0, darkExtra), darkMix);
          chromaGain = mix(mix(1.18, 0.0, extra), mix(0.92, 0.0, darkExtra), darkMix);
          contourStr = mix(0.43, 0.88, darkMix);
          contourDirAmt = mix(0.77, 1.0, darkMix);
          bevelShadowStr = 0.036;
          glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;
        }
      } else if (is_dark) {
        float darkDens = (col.a > 0.41) ? col.a : 0.30;
        float extra = clamp((darkDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);
        emission = mix(vec3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), vec3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);
        transmittance = mix(0.54, 0.0, extra);
        lift = mix(0.36, 0.0, extra);
        chromaGain = mix(0.92, 0.0, extra);
        contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;
        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;
      } else {
        float lightDens = (col.a > 0.41) ? col.a : 0.30;
        float extra = clamp((lightDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);
        emission = vec3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * lightDens;
        transmittance = mix(0.70, 0.0, extra);
        lift = mix(0.16, 0.0, extra);
        chromaGain = mix(1.18, 0.0, extra);
        contourStr = 0.43; contourDirAmt = 0.77; bevelShadowStr = 0.036;
        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;
      }
      if (regMix > 0.0 && regMix < 1.0) {
        emission = mix(vec3(0.126, 0.126, 0.126), emission, regMix);
        transmittance = mix(0.90, transmittance, regMix);
        lift = mix(0.10, lift, regMix);
        chromaGain = mix(1.0, chromaGain, regMix);
        contourStr = mix(0.25, contourStr, regMix);
        contourDirAmt = mix(0.77, contourDirAmt, regMix);
        bevelShadowStr = mix(0.04, bevelShadowStr, regMix);
        glintLum = mix(1.2, glintLum, regMix);
        glintFaceGain = mix(0.25, glintFaceGain, regMix);
        glintVib = mix(1.5, glintVib, regMix);
      }
      if (fogT > 0.001) {
        float r1 = fogT * 2.6;
        float r2 = fogT * 3.6;
        vec2 fc = sampleBase + disp;
        vec3 fBlur = (refractColor * 2.0
          + (backdrop(fc + vec2(r1, 0.0)) + backdrop(fc - vec2(r1, 0.0))
           + backdrop(fc + vec2(0.0, r1)) + backdrop(fc - vec2(0.0, r1))) * 1.5
          + (backdrop(fc + vec2(r2, r2)) + backdrop(fc + vec2(-r2, r2))
           + backdrop(fc + vec2(r2, -r2)) + backdrop(fc + vec2(-r2, -r2)))) * (1.0 / 12.0);
        refractColor = mix(refractColor, fBlur, fogT);
      }
      float Y = luma(refractColor);
      float transLum = clamp(Y * (1.0 + lift * (1.0 - Y)), 0.0, 1.0);
      vec3 transmittedColor = vec3(transLum * transmittance) + (refractColor - vec3(Y)) * (chromaGain * v_p.z);
      vec3 baseColor = clamp(emission + transmittedColor, 0.0, 1.0);
      // Honor explicit chromatic tints (non-neutral) if a caller requests colored liquid glass
      float colChroma = max(max(col.r, col.g), col.b) - min(min(col.r, col.g), col.b);
      if (colChroma > 0.08 && col.a > 0.001) {
        baseColor = mix(baseColor, col.rgb, col.a * 0.5);
      }
      float spot = 0.0;
      if (spot_raw > 0.5) {
        float q = spot_raw - 1.0;
        float qx = floor(q * 0.000244140625);
        float qy = q - qx * 4096.0;
        vec2 gp = v_rect.xy + vec2(qx * 0.5 - 256.0, qy * 0.5 - 256.0);
        float gr = max(min(v_rect.z, v_rect.w) * 1.5, 64.0);
        spot = 1.0 - smoothstep(gr * 0.1, gr, length(p - gp));
        baseColor = clamp(baseColor + vec3(0.08 * spot), 0.0, 1.0);
      }
      vec2 rn = vec2(0.0, 0.0);
      float tangency = 0.0;
      if (need_grad) {
        vec2 la = u_glight;
        rn = vec2(
          surfaceNormal.x * la.x + surfaceNormal.y * la.y,
          -surfaceNormal.x * la.y + surfaceNormal.y * la.x
        );
        tangency = abs(rn.x);
      }
      vec3 result = baseColor;
      // (a) Inner bevel shadow (subtracts only transmittedColor; lightFacing = -rn.y)
      if (bevelShadowStr >= 0.001 && inward < 23.0) {
        float lightFacing = -rn.y;
        float shadowShift = 6.0 * lightFacing;
        float penumbra = 2.0 * shadowShift;
        float bevelLeading = penumbra > 0.001 ? smoothstep(0.0, penumbra, inward) : 1.0;
        float bevelFalloff = 1.0 - smoothstep(0.0, 16.0, inward - shadowShift);
        float wrappedFacing = smoothstep(0.0, 1.0, lightFacing * 0.5 + 0.5);
        float bevelDir = mix(1.0, wrappedFacing, 0.5);
        float bevelShadow = clamp(bevelLeading * bevelFalloff * bevelDir * bevelShadowStr, 0.0, 1.0);
        result = max(result - transmittedColor * bevelShadow, vec3(0.0));
      }
      // (b) Glint (1.2pt ramp + 0.21 * 4.8pt bleed, both top & bottom walls, recolors face)
      if (v_c2.x > 0.01 && inward < 4.8) {
        float glintProfile = clamp(1.0 - inward / 1.2, 0.0, 1.0)
                           + 0.21 * clamp(1.0 - inward / 4.8, 0.0, 1.0);
        float lobe = max(1.0 - tangency, 0.0);
        float glint = clamp(v_c2.x * 0.252 * lobe * glintProfile + spot * 0.08 * glintProfile, 0.0, 1.0);
        float resLum = luma(result);
        vec3 glintTarget = vec3(glintLum) + result * glintFaceGain + (result - vec3(resLum)) * glintVib;
        result = clamp(mix(result, glintTarget, glint), 0.0, 1.0);
      }
      result = clamp(result + mb_dither(p * u_scale) / 255.0, 0.0, 1.0);
      // (c) External 0.75pt dark contour (concentrated perpendicular to light axis where glint fades)
      float contourDir = mix(1.0, tangency, contourDirAmt);
      float extA = ext_cov * contourStr * contourDir * v_c2.w;
      float visA = materialAlpha * v_c2.w;
      o = vec4(result * visA, clamp(visA + extA, 0.0, 1.0));
      return;
    }
    #endif
    #if ONE_KIND < 0
    if (kind == 8) {
      vec4 s_rr = max(max(v_rr.x, v_rr.y), max(v_rr.z, v_rr.w)) > 0.0 ? v_rr : vec4(v_p.x);
      float d = sd_rr(p, v_rect, s_rr);
      float materialAlpha = clamp(0.5 - d * u_scale, 0.0, 1.0);
      if (materialAlpha < 0.005) discard;
      float halfMinor = max(min(v_rect.z, v_rect.w) * 0.5, 1.0);
      float inward = max(-d, 0.0);
      float rawBevel = max(v_c2.y, 0.0);
      float rawAmount = max(v_c2.z, 0.0);
      float lensScale = min(1.0, halfMinor / max(rawBevel, 0.001));
      float bevel = rawBevel * lensScale;
      float amount = rawAmount * lensScale;
      vec2 disp = vec2(0.0, 0.0);
      if (inward < bevel && bevel > 0.001 && amount > 0.001) {
        float e = 0.5;
        vec2 grad = vec2(
          sd_rr(p + vec2(e, 0.0), v_rect, s_rr) - sd_rr(p - vec2(e, 0.0), v_rect, s_rr),
          sd_rr(p + vec2(0.0, e), v_rect, s_rr) - sd_rr(p - vec2(0.0, e), v_rect, s_rr)
        ) / (2.0 * e);
        float gradLen = length(grad);
        vec2 surfaceNormal = gradLen > 0.0001 ? grad / gradLen : vec2(0.0, 0.0);
        float shortening = sqrt(clamp(gradLen, 0.0, 1.0));
        float bevelX = 1.0 - clamp(inward / bevel, 0.0, 1.0);
        float mag = amount * (1.0 - sqrt(max(1.0 - bevelX * bevelX, 0.0))) * shortening;
        disp = surfaceNormal * (-mag);
      }
      vec2 uv = (p + disp) * u_map.xy + u_map.zw;
      vec4 fg = vec4(0.0);
      if (uv.x >= u_uvc.x && uv.x <= u_uvc.z && uv.y >= u_uvc.y && uv.y <= u_uvc.w) {
        fg = texture(u_bd, uv);
      }
      o = fg * (materialAlpha * col.a);
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 0 || ONE_KIND == 2 || ONE_KIND == 4 || ONE_KIND == 5
    vec2 hs = v_rect.zw * 0.5;
    vec2 c = v_rect.xy + hs;
    // worked out as near the curve as its cover, its edge or its blur reaches
    float band = 1.0 + 2.0 / u_scale + (kind == 2 ? max(v_p.w, 0.5) : max(v_p.z, 0.0));
    // (its corner by p: v_rr, each its own)
    float rad = mb_corner_of(p - c, v_rr);
    float d = mb_sd_box(p - c, hs, rad, band);
    #if ONE_KIND < 0 || ONE_KIND == 0 || ONE_KIND == 5
    if (kind == 0 || kind == 5) d = notch_cut(d, p, v_rect, v_pad);
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 4
    if (kind == 4) {
      vec2 uv = v_c2.xy + clamp((p - v_rect.xy) / v_rect.zw, 0.0, 1.0) * v_c2.zw;
      vec4 pic = texture(u_img, clamp(uv, 0.0, 1.0));
      float edge = clamp(0.5 - d * u_scale, 0.0, 1.0);
      if (v_pad.z > 0.5) {
        // Only picture edges inside the frame cut it; the frame's clip covers shared edges once.
        vec2 size = v_rect.zw / v_c2.zw, lo = v_rect.xy - v_c2.xy * size, hi = lo + size;
        vec2 a = lo - p, b = p - hi;
        if (v_c2.x >= 0.0) a.x = -1e9; if (v_c2.y >= 0.0) a.y = -1e9;
        if (v_c2.x + v_c2.z <= 1.0) b.x = -1e9; if (v_c2.y + v_c2.w <= 1.0) b.y = -1e9;
        vec2 q = max(a, b);
        float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
        pic *= v_pad.w * clamp(0.5 - pd * u_scale, 0.0, 1.0);
        pic += vec4(col.rgb * v_pad.y, v_pad.y) * (1.0 - pic.a);
        if (v_pad.x < 0.5 && max(max(v_rr.x, v_rr.y), max(v_rr.z, v_rr.w)) <= 0.0 &&
            max(max(v_rc.x, v_rc.y), max(v_rc.z, v_rc.w)) > 0.0 &&
            all(greaterThanEqual(v_clip.xy, v_rect.xy)) && all(lessThanEqual(v_clip.zw, v_rect.xy + v_rect.zw))) edge = 1.0;
      }
      o = pic * (col.a * edge);
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 2
    if (kind == 2) {
      // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)
      float a = mb_shadow(p - c, hs, rad, max(v_p.w, 0.25));
      // glass's: only outside its box (c2.y above it)
      if (v_c2.x > 0.5) {
        vec2 q = p - c + vec2(0.0, v_c2.y);
        float db = mb_sd_box(q, hs, mb_corner_of(q, v_rr), band);
        a *= clamp(0.5 + db * u_scale, 0.0, 1.0);
      }
      o = vec4(col.rgb, 1.0) * col.a * a;
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 0 || ONE_KIND == 5
    float a = clamp(0.5 - d * u_scale, 0.0, 1.0);
    #if ONE_KIND < 0 || ONE_KIND == 5
    if (kind == 5) {
      // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,
      // the foot and right less), 0.5 wide
      bool prog_glass = (v_pad.z < -0.5);
      vec3 g3 = backdrop(p);
      float ps = prog_glass ? fade_r : 1.0;
      float ts = prog_glass ? (fade_r <= 0.0 ? 0.0 : pow(fade_r, 1.25)) : 1.0;
      float sat = prog_glass ? mix(1.0, v_p.z, ps) : v_p.z;
      float bg_diff = prog_glass ? smoothstep(0.22, 0.72, abs(luma(col.rgb) - luma(g3))) : 0.0;
      float base_a = prog_glass ? mix(col.a, min(0.86, col.a + 0.34), bg_diff) : col.a;
      float ta = prog_glass ? (base_a * ts) : col.a;
      g3 = max(mix(vec3(luma(g3)), g3, sat), 0.0);
      g3 = g3 * (1.0 - ta) + col.rgb * ta;
      if (v_c2.x + v_c2.y + v_c2.z > 0.0) {
        float edge = clamp(0.5 + (d + 0.5) * u_scale, 0.0, 1.0);
        float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, v_rect, v_rr), p - 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);
        float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, v_rect, v_rr), p + 0.5, v_rect, v_pad) * u_scale, 0.0, 1.0);
        g3 = mix(g3, vec3(1.0), v_c2.x * edge);
        g3 = mix(g3, vec3(1.0), v_c2.y * lit);
        g3 = mix(g3, vec3(1.0), v_c2.z * back);
      }
      // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)
      g3 += mb_dither(p * u_scale) * ps / 255.0;
      float edge_a = prog_glass ? smoothstep(0.0, 0.04, fade_r) : 1.0;
      o = vec4(g3, 1.0) * (a * v_c2.w * edge_a);
      return;
    }
    #endif
    #if ONE_KIND < 0 || ONE_KIND == 0
    vec4 fill = vec4(col.rgb, 1.0) * col.a;
    if (v_p.z > 0.0) {
      float inner = clamp(0.5 - (d + v_p.z) * u_scale, 0.0, 1.0);
      vec4 bc = vec4(v_c2.rgb, 1.0) * v_c2.a;
      fill = mix(bc, fill, inner);
    }
    o = fill * a;
    #endif
    #endif
    #endif
  }
  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are
  void main() {
    vec2 p = v_pos, cp = v_cpos;
    float cover = 1.0;
    if (max(max(v_rc.x, v_rc.y), max(v_rc.z, v_rc.w)) > 0.0) {
      cover = clip_cover(cp, v_clip, v_rc, v_rs, u_scale);
      if (cover <= 0.0) discard;
    } else if (cp.x < v_clip.x || cp.y < v_clip.y || cp.x > v_clip.z || cp.y > v_clip.w) discard;
    // and by the clip outside it, where it has one (scene.mbt 40-51: a pane round an image's frame in its corner)
    if (max(max(v_orc.x, v_orc.y), max(v_orc.z, v_orc.w)) > 0.0) {
      cover *= clip_cover(cp, v_oclip, v_orc, v_ors, u_scale);
      if (cover <= 0.0) discard;
    }
    // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)
    int kind = ONE_KIND >= 0 ? ONE_KIND : int(v_p.y + 0.5);
    bool prog_glass = (kind == 5 && v_pad.z < -0.5);
    vec4 ramp = clamp(v_ramp, 0.0, 1.0);
    float fade_r = ramp.x * ramp.y * ramp.z * ramp.w;
    if (fade_r <= 0.0) discard;
    if (!prog_glass) {
      cover *= fade_r;
      if (cover <= 0.0) discard;
    }
    shade(p, fade_r);
    o *= cover;
  }`;
  // the flat pipeline: a ground's colour where it is covered whole, cut by straight clips alone (bands.h mb_pieces)
  const FS_FLAT = `#version 300 es
  precision highp float;
  precision highp int;
  flat in vec4 v_color;
  out vec4 o;
  void main() { o = vec4(v_color.rgb, 1.0) * v_color.a; }`;
  // glass's passes over its copy of what is under it
  const PVS = `#version 300 es
  void main() {
    gl_Position = vec4(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0, 0.0, 1.0);
  }`;
  const PFS = `#version 300 es
  precision highp float;
  precision highp int;
  ${CORNERS}
  // The backdrop's passes: u_a.xy the source's texel, u_a.z 1 halving (dual Kawase's down), 2 a Gaussian along u_b.zw
  // of deviation u_a.w (texels); u_b.xy the last texel's centre of what the source holds
  uniform highp sampler2D u_src;
  uniform highp sampler2D u_lv1;
  uniform highp sampler2D u_lv2;
  uniform highp sampler2D u_lv3;
  uniform vec4 u_a;
  uniform vec4 u_b;
  uniform vec4 u_c[9];
  out vec4 o;
  void main() {
    vec2 ts = u_a.xy;
    vec2 lo = ts * 0.5, hi = u_b.xy;
    if (u_a.z > 3.5) {
      vec2 p = u_c[0].xy + gl_FragCoord.xy * u_c[0].zw;
      float ramp = 1.0;
      if (u_c[1].y > 0.0) ramp *= clamp((p.y - u_c[1].x) / u_c[1].y, 0.0, 1.0);
      if (u_c[1].w > 0.0) ramp *= clamp((u_c[1].z - p.y) / u_c[1].w, 0.0, 1.0);
      if (u_c[2].y > 0.0) ramp *= clamp((p.x - u_c[2].x) / u_c[2].y, 0.0, 1.0);
      if (u_c[2].w > 0.0) ramp *= clamp((u_c[2].z - p.x) / u_c[2].w, 0.0, 1.0);
      float sp = max(u_c[3].x, 1.0);
      float kf = u_c[3].y;
      vec4 m0 = u_c[4], m1 = u_c[5], m2 = u_c[6], m3 = u_c[7];
      if (kf < 0.5) { o = texture(u_src, clamp(gl_FragCoord.xy * m0.xy, m0.xy * 0.5, m0.zw)); return; }
      float r = clamp(ramp, 0.0, 1.0);
      if (r <= 0.0) { o = texture(u_src, clamp(gl_FragCoord.xy * m0.xy, m0.xy * 0.5, m0.zw)); return; }
      if (r >= 1.0) {
        int ki = int(kf + 0.5);
        if (ki <= 1) o = texture(u_lv1, clamp(gl_FragCoord.xy * m1.xy, m1.xy * 1.0, m1.zw));
        else if (ki == 2) o = texture(u_lv2, clamp(gl_FragCoord.xy * m2.xy, m2.xy * 2.0, m2.zw));
        else o = texture(u_lv3, clamp(gl_FragCoord.xy * m3.xy, m3.xy * 4.0, m3.zw));
        return;
      }
      float sig1 = pow(sp, 1.0 / kf);
      float target_px = sp * pow(r, 1.15);
      if (target_px <= sig1 || kf <= 1.05) {
        vec2 uv0_min = m0.xy * 0.5, uv0_max = m0.zw;
        vec2 c_uv = gl_FragCoord.xy * m0.xy;
        vec4 g_small;
        if (target_px <= 0.01) {
          g_small = texture(u_src, clamp(c_uv, uv0_min, uv0_max));
        } else if (target_px <= 0.55) {
          // Exact separable 3x3 Gaussian via 2x2 bilinear taps (center weight 0.5 split across +-o1)
          float inv2 = -0.5 / (target_px * target_px);
          float w1 = exp(inv2);
          float o1 = w1 / (0.5 + w1);
          vec2 ox = vec2(o1, 0.0) * m0.xy;
          vec2 oy = vec2(0.0, o1) * m0.xy;
          g_small = (texture(u_src, clamp(c_uv - ox - oy, uv0_min, uv0_max)) +
                     texture(u_src, clamp(c_uv + ox - oy, uv0_min, uv0_max)) +
                     texture(u_src, clamp(c_uv - ox + oy, uv0_min, uv0_max)) +
                     texture(u_src, clamp(c_uv + ox + oy, uv0_min, uv0_max))) * 0.25;
        } else {
          // Exact separable 7x7 Gaussian via 4x4 bilinear taps (zero gaps, zero comb ghosting)
          float inv2 = -0.5 / (target_px * target_px);
          float w1 = exp(inv2);
          float w2 = exp(4.0 * inv2);
          float w3 = exp(9.0 * inv2);
          float W1 = 0.5 + w1;
          float W2 = w2 + w3;
          float o1 = w1 / W1;
          float o2 = (2.0 * w2 + 3.0 * w3) / max(W2, 1e-6);
          float inv_sum = 0.5 / (W1 + W2);
          float p1 = W1 * inv_sum;
          float p2 = W2 * inv_sum;
          float ox[4] = float[4](-o2, -o1, o1, o2);
          float pw[4] = float[4](p2, p1, p1, p2);
          g_small = vec4(0.0);
          for (int iy = 0; iy < 4; iy++) {
            vec4 row = vec4(0.0);
            float uy = clamp(c_uv.y + ox[iy] * m0.y, uv0_min.y, uv0_max.y);
            for (int ix = 0; ix < 4; ix++) {
              float ux = clamp(c_uv.x + ox[ix] * m0.x, uv0_min.x, uv0_max.x);
              row += texture(u_src, vec2(ux, uy)) * pw[ix];
            }
            g_small += row * pw[iy];
          }
        }
        float blend_lo = min(1.1, sig1 * 0.45);
        float bt = clamp((target_px - blend_lo) / max(sig1 - blend_lo, 1e-4), 0.0, 1.0);
        float blend1 = bt > 0.0 ? pow(bt, 1.8) : 0.0;
        if (blend1 > 0.0) {
          vec4 c_lv1 = texture(u_lv1, clamp(gl_FragCoord.xy * m1.xy, m1.xy * 1.0, m1.zw));
          o = mix(g_small, c_lv1, blend1);
        } else {
          o = g_small;
        }
        return;
      }
      float lv_u = clamp(1.0 + (kf - 1.0) * log(target_px / sig1) / max(log(sp / sig1), 1e-4), 1.0, kf);
      int idx = min(int(floor(lv_u)), int(kf + 0.5) - 1);
      if (idx < 0) idx = 0;
      float f = lv_u - float(idx);
      vec4 c0, c1;
      if (idx == 0) {
        c0 = texture(u_src, clamp(gl_FragCoord.xy * m0.xy, m0.xy * 0.5, m0.zw));
        c1 = texture(u_lv1, clamp(gl_FragCoord.xy * m1.xy, m1.xy * 1.0, m1.zw));
      } else if (idx == 1) {
        c0 = texture(u_lv1, clamp(gl_FragCoord.xy * m1.xy, m1.xy * 1.0, m1.zw));
        c1 = texture(u_lv2, clamp(gl_FragCoord.xy * m2.xy, m2.xy * 2.0, m2.zw));
      } else {
        c0 = texture(u_lv2, clamp(gl_FragCoord.xy * m2.xy, m2.xy * 2.0, m2.zw));
        c1 = texture(u_lv3, clamp(gl_FragCoord.xy * m3.xy, m3.xy * 4.0, m3.zw));
      }
      o = mix(c0, c1, f);
      return;
    }
    if (u_a.z > 2.5) {
      vec2 p = u_c[0].xy + gl_FragCoord.xy * u_c[0].zw;
      p = mb_contained_point(p, u_c[1], u_c[2], u_c[3], u_c[4], u_c[5], u_c[6], u_c[7], u_c[8], u_c[0].z);
      o = texture(u_src, clamp((p - u_c[0].xy) / u_c[0].zw * ts, lo, hi));
      return;
    }
    if (u_a.z < 1.5) {
      vec2 uv = gl_FragCoord.xy * 2.0 * ts;
      vec4 s = texture(u_src, clamp(uv, lo, hi)) * 4.0;
      s += texture(u_src, clamp(uv - ts, lo, hi));
      s += texture(u_src, clamp(uv + ts, lo, hi));
      s += texture(u_src, clamp(uv + vec2(ts.x, -ts.y), lo, hi));
      s += texture(u_src, clamp(uv + vec2(-ts.x, ts.y), lo, hi));
      o = s / 8.0;
      return;
    }
    vec2 uv = gl_FragCoord.xy * ts;
    vec2 dir = u_b.zw * ts;
    float sg = u_a.w;
    float k = -0.5 / (sg * sg);
    vec4 s = texture(u_src, clamp(uv, lo, hi));
    float wsum = 1.0;
    int n = int(ceil(sg * 3.0));
    for (int i = 1; i <= 64; i += 2) {
      if (i > n) break;
      float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);
      float w = w1 + w2;
      float off = (float(i) * w1 + float(i + 1) * w2) / w;
      s += (texture(u_src, clamp(uv + dir * off, lo, hi)) + texture(u_src, clamp(uv - dir * off, lo, hi))) * w;
      wsum += 2.0 * w;
    }
    o = s / wsum;
  }`;

  const AD_FS = `#version 300 es
  precision highp float;
  precision highp int;
  uniform highp sampler2D u_bd;
  uniform highp sampler2D u_prev;
  uniform vec4 u_map;
  uniform vec4 u_uvc;
  uniform vec4 u_box;
  uniform vec4 u_param;
  out vec4 o;
  float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
  float mb_unpack16(vec2 rg) {
    float hi = floor(clamp(rg.x, 0.0, 1.0) * 255.0 + 0.5);
    float lo = floor(clamp(rg.y, 0.0, 1.0) * 255.0 + 0.5);
    return (hi * 256.0 + lo) / 65535.0;
  }
  vec2 mb_pack16(float v) {
    float q = floor(clamp(v, 0.0, 1.0) * 65535.0 + 0.5);
    float hi = floor(q / 256.0);
    float lo = q - hi * 256.0;
    return vec2(hi / 255.0, lo / 255.0);
  }
  void main() {
    vec2 c = u_box.xy, h = u_box.zw;
    float sum = 0.0, mx1 = -1.0, mx2 = -1.0, mn1 = 2.0, mn2 = 2.0;
    for (int iy = -1; iy <= 1; iy++) {
      float py = c.y + float(iy) * (h.y * 0.60);
      for (int ix = -2; ix <= 2; ix++) {
        float px = c.x + float(ix) * (h.x * 0.38);
        vec2 uv = clamp(vec2(px, py) * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw);
        float y = luma(texture(u_bd, uv).rgb);
        sum += y;
        if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }
        if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }
      }
    }
    float bgL = (sum - mx1 - mx2 - mn1 - mn2) / 11.0;
    int sid = int(u_param.w + 0.5);
    vec4 prev = texelFetch(u_prev, ivec2(sid, 0), 0);
    float prevT = mb_unpack16(prev.rg);
    float is_dark = u_param.x, is_new = u_param.y, dt = u_param.z;
    float latch, target;
    if (is_dark > 0.5) {
      target = smoothstep(0.35, 0.85, bgL);
      latch = target;
    } else {
      if (is_new > 0.5) latch = (bgL < 0.36) ? 1.0 : 0.0;
      else if (prev.b > 0.5) latch = (bgL > 0.46) ? 0.0 : 1.0;
      else latch = (bgL < 0.36) ? 1.0 : 0.0;
      target = latch;
    }
    float nextT;
    if (is_new > 0.5 || dt >= 1.0) nextT = target;
    else if (dt <= 0.0) nextT = prevT;
    else {
      nextT = mix(prevT, target, 1.0 - exp(-dt / 0.070));
      if (abs(nextT - target) < 0.003) nextT = target;
    }
    o = vec4(mb_pack16(nextT), latch, clamp(bgL, 0.0, 1.0));
  }`;

  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }

  const hasOwnProg = (kind) => (kind >= 0 && kind <= 6) || kind === 10 || kind === 11 || kind === MB_KIND_LIQUID_SINGLE;

  function makeProg(vsShader, kind) {
    const src = `#version 300 es\n#define ONE_KIND ${kind}\n` + FS.slice('#version 300 es\n'.length);
    const fs = compile(gl.FRAGMENT_SHADER, src);
    const p = gl.createProgram();
    gl.attachShader(p, vsShader);
    gl.attachShader(p, fs);
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    gl.deleteShader(fs);
    const u = {};
    for (const n of ['u_vp', 'u_origin', 'u_scale', 'u_atlas', 'u_img', 'u_bd', 'u_map', 'u_uvc', 'u_gb', 'u_shape', 'u_rad', 'u_n', 'u_glight', 'u_segs', 'u_ad', 'u_ad_box', 'u_ad_n']) {
      u[n] = gl.getUniformLocation(p, n);
    }
    gl.useProgram(p);
    if (u.u_atlas) gl.uniform1i(u.u_atlas, 0);
    if (u.u_img) gl.uniform1i(u.u_img, 1);
    if (u.u_bd) gl.uniform1i(u.u_bd, 2);
    if (u.u_segs) gl.uniform1i(u.u_segs, 3);
    if (u.u_ad) gl.uniform1i(u.u_ad, 4);
    return { p, u, gen: 0 };
  }

  function getProg(kind) {
    const idx = kind >= 0 && hasOwnProg(kind) ? kind : MB_KINDS;
    let k = progs[idx];
    if (!k) k = progs[idx] = makeProg(vs, idx === MB_KINDS ? -1 : idx);
    return k;
  }

  function useProg(kind) {
    const k = getProg(kind);
    progNow = k.p;
    gl.useProgram(k.p);
    if (k.gen === progGen) return;
    k.gen = progGen;
    const u = k.u;
    // The framebuffer's rounded size may not be exactly cssW*dpr. Mapping to cssW would stretch its pixels by that
    // remainder, sampling glyphs between atlas texels. A point must cover exactly dpr pixels, including at 125% zoom.
    if (u.u_vp) gl.uniform2f(u.u_vp, lensVpW > 0 ? lensVpW : canvas.width / dpr, lensVpH > 0 ? lensVpH : canvas.height / dpr);
    if (u.u_origin) gl.uniform2f(u.u_origin, lensOx, lensOy);
    if (u.u_scale) gl.uniform1f(u.u_scale, dpr);
    if (u.u_map) gl.uniform4fv(u.u_map, gmap);
    if (u.u_uvc) gl.uniform4fv(u.u_uvc, guvc);
    if (u.u_gb) gl.uniform4fv(u.u_gb, ggb);
    if (u.u_shape) gl.uniform4fv(u.u_shape, gshape);
    if (u.u_rad) gl.uniform4fv(u.u_rad, grad);
    if (u.u_n) gl.uniform1i(u.u_n, gn);
    if (u.u_glight) gl.uniform2f(u.u_glight, Math.cos(glassLightAngle), Math.sin(glassLightAngle));
    if (u.u_ad_box) gl.uniform4fv(u.u_ad_box, gadBox);
    if (u.u_ad_n) gl.uniform1i(u.u_ad_n, gadN);
  }

  function setupGL() {
    // with alpha: native views (below) show through the holes the app paints (kind 9), and default-FB glass blits to RGBA8
    gl = canvas.getContext('webgl2', { premultipliedAlpha: true, antialias: false, alpha: true });
    cv = null;
    cvOk = false;
    vs = compile(gl.VERTEX_SHADER, VS);
    progs = new Array(MB_KINDS + 1).fill(null);
    progs[MB_KINDS] = makeProg(vs, -1);
    prog = progs[MB_KINDS].p;
    U = progs[MB_KINDS].u;
    const fsFlat = compile(gl.FRAGMENT_SHADER, FS_FLAT);
    progFlat = gl.createProgram();
    gl.attachShader(progFlat, vs);
    gl.attachShader(progFlat, fsFlat);
    gl.linkProgram(progFlat);
    if (!gl.getProgramParameter(progFlat, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(progFlat));
    gl.deleteShader(fsFlat);
    ufVp = gl.getUniformLocation(progFlat, 'u_vp');
    progGen++;
    progNow = null;
    const pvs = compile(gl.VERTEX_SHADER, PVS);
    post = gl.createProgram();
    gl.attachShader(post, pvs);
    gl.attachShader(post, compile(gl.FRAGMENT_SHADER, PFS));
    gl.linkProgram(post);
    if (!gl.getProgramParameter(post, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(post));
    for (const n of ['u_src', 'u_lv1', 'u_lv2', 'u_lv3', 'u_a', 'u_b', 'u_c']) PU[n] = gl.getUniformLocation(post, n);
    adProg = gl.createProgram();
    gl.attachShader(adProg, pvs);
    gl.attachShader(adProg, compile(gl.FRAGMENT_SHADER, AD_FS));
    gl.linkProgram(adProg);
    if (!gl.getProgramParameter(adProg, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(adProg));
    ADU = {};
    for (const n of ['u_bd', 'u_prev', 'u_map', 'u_uvc', 'u_box', 'u_param']) ADU[n] = gl.getUniformLocation(adProg, n);
    glassLost();
    vao = gl.createVertexArray();
    gl.bindVertexArray(vao);
    instBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    for (let i = 0; i < INST / 4; i++) {
      const loc = i;
      // instance layout: rect, p, color, c2, clip, pad, the clip's corners' radii, how smooth, how it is turned, a box's
      // corners' radii, the outer clip's rect, corners' radii and how smooth (vec4 each)
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 4, gl.FLOAT, false, INST * 4, i * 16);
      gl.vertexAttribDivisor(loc, 1);
    }
    atlasTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, ATLAS, ATLAS);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
  }

  // ---- glass (src/ui/glass.mbt) ----
  // When the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far under it
  // (its rects with room for the blur round them) is copied out of the target, halved down to where the blur is a
  // few texels wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left,
  // and kept in an LRU slot (GLASS_SLOTS) so frames with unchanged content under the glass reuse the blur with zero passes.
  let lv = null, lvW = 0, lvH = 0, bdTex = null;
  let lensLv = null, lensW = 0, lensH = 0, lensOx = 0, lensOy = 0, lensVpW = 0, lensVpH = 0;
  let glassSlots = makeGlassSlots(), glassSlotsClock = 0;
  let underNow = new Float32Array(INST * 256), underNowN = 0, underWhole = 0, underPicked = 0;
  const gmap = new Float32Array(4), guvc = new Float32Array(4), ggb = new Float32Array(4);
  const gshape = new Float32Array(32), grad = new Float32Array(32);
  let gn = 0;
  function levelTex(format, w, h) {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texStorage2D(gl.TEXTURE_2D, 1, format, Math.max(1, w), Math.max(1, h));
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    return { t, fb, w: Math.max(1, w), h: Math.max(1, h), format };
  }
  const GLASS_IDLE = 180;
  const AD_MAX = 16, AD_SETTLE_SEC = 0.42, AD_MATCH_DIST = 64.0;
  function makeAdSlots() {
    const arr = [];
    for (let i = 0; i < AD_MAX; i++) arr.push({ active: false, cx: 0, cy: 0, hx: 0, hy: 0, isDark: 0, settleLeft: 0, updatedSerial: 0, seenSerial: 0 });
    return arr;
  }
  let adProg = null, ADU = {};
  let adTex = [null, null], adFb = [null, null], adCur = 0;
  let adSlots = makeAdSlots(), adLastTime = 0, adFrameSerial = 0, adSettling = false, adRaf = 0;
  let adCurDt = 0, adMode = 1;
  let lastN = 0, lastR = 0, lastG = 0, lastB = 0, lastF32 = null;
  const gadBox = new Float32Array(AD_MAX * 4);
  let gadN = 0;
  let glassIdle = 0, glassDrawn = false;
  function adForget() {
    for (let i = 0; i < AD_MAX; i++) {
      const s = adSlots[i];
      s.active = false; s.settleLeft = 0; s.updatedSerial = 0; s.seenSerial = 0;
    }
    adLastTime = 0; adSettling = false; gadN = 0;
  }
  function ensureAdTex() {
    if (adTex[0]) return;
    for (let i = 0; i < 2; i++) {
      const t = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, t);
      gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, AD_MAX, 1);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      const fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
      adTex[i] = t; adFb[i] = fb;
    }
    adCur = 0;
  }
  function adFillUniforms() {
    if (adMode < 0) { gadN = 0; return; }
    let maxA = 0;
    for (let i = 0; i < AD_MAX; i++) {
      const s = adSlots[i];
      if (s.active) {
        gadBox[i * 4] = s.cx; gadBox[i * 4 + 1] = s.cy; gadBox[i * 4 + 2] = s.hx; gadBox[i * 4 + 3] = s.hy;
        maxA = i + 1;
      } else {
        gadBox[i * 4] = -1e9; gadBox[i * 4 + 1] = -1e9; gadBox[i * 4 + 2] = -1e9; gadBox[i * 4 + 3] = -1e9;
      }
    }
    gadN = maxA;
  }
  function adCollectAndMatch(start, count, m, backdropChanged, dt, serial) {
    if (adMode <= 0 || dt < 0) return [];
    const a = start * INST;
    const kind = Math.round(f32[a + 5]);
    if (kind !== 6) return [];
    const mergedLiquid = f32[a + 23] > 0;
    const items = [];
    if (mergedLiquid) {
      const isClear = f32[a + 7] <= 0.1 && f32[a + 11] < 0.12;
      const isAdaptive = f32[a + 14] < -0.5;
      if (isAdaptive && !isClear) {
        const lum = 0.2126 * f32[a + 8] + 0.7152 * f32[a + 9] + 0.0722 * f32[a + 10];
        items.push({
          cx: (m.gb[0] + m.gb[2]) * 0.5, cy: (m.gb[1] + m.gb[3]) * 0.5,
          hx: Math.max((m.gb[2] - m.gb[0]) * 0.5, 1.0), hy: Math.max((m.gb[3] - m.gb[1]) * 0.5, 1.0),
          isDark: (f32[a + 11] >= 0.05 && lum < 0.35) ? 1 : 0,
        });
      }
    } else {
      const tid = f32[a + 20];
      for (let i = start; i < count && items.length < AD_MAX; i++) {
        const b = i * INST;
        if (f32[b + 20] !== tid) continue;
        if (Math.round(f32[b + 5]) !== 6 || f32[b + 23] > 0) continue;
        const isClear = f32[b + 7] <= 0.1 && f32[b + 11] < 0.12;
        const isAdaptive = f32[b + 14] < -0.5;
        if (!isAdaptive || isClear) continue;
        const lum = 0.2126 * f32[b + 8] + 0.7152 * f32[b + 9] + 0.0722 * f32[b + 10];
        items.push({
          cx: f32[b] + f32[b + 2] * 0.5, cy: f32[b + 1] + f32[b + 3] * 0.5,
          hx: Math.max(f32[b + 2] * 0.5, 1.0), hy: Math.max(f32[b + 3] * 0.5, 1.0),
          isDark: (f32[b + 11] >= 0.05 && lum < 0.35) ? 1 : 0,
        });
      }
    }
    const pend = [];
    for (const it of items) {
      let sid = -1, isNew = 0;
      for (let i = 0; i < AD_MAX; i++) {
        const s = adSlots[i];
        if (s.active && s.seenSerial === serial && s.isDark === it.isDark && Math.hypot(it.cx - s.cx, it.cy - s.cy) <= 2.0) {
          sid = i; break;
        }
      }
      if (sid < 0) {
        let bestD = AD_MATCH_DIST + 1e-3;
        for (let i = 0; i < AD_MAX; i++) {
          const s = adSlots[i];
          if (!s.active || s.seenSerial === serial || s.isDark !== it.isDark) continue;
          const d = Math.hypot(it.cx - s.cx, it.cy - s.cy);
          if (d <= bestD) { bestD = d; sid = i; }
        }
        if (sid < 0) {
          for (let i = 0; i < AD_MAX; i++) if (!adSlots[i].active) { sid = i; break; }
          if (sid < 0) {
            let oldest = Infinity;
            for (let i = 0; i < AD_MAX; i++) {
              if (adSlots[i].seenSerial !== serial && adSlots[i].seenSerial < oldest) {
                oldest = adSlots[i].seenSerial; sid = i;
              }
            }
            if (sid < 0) sid = 0;
          }
          isNew = 1;
          const s = adSlots[sid];
          s.active = true; s.isDark = it.isDark; s.settleLeft = 0; s.updatedSerial = 0;
        }
        const s = adSlots[sid];
        s.cx = it.cx; s.cy = it.cy; s.hx = it.hx; s.hy = it.hy; s.seenSerial = serial;
      }
      const s = adSlots[sid];
      if (s.updatedSerial === serial) continue;
      if (isNew || backdropChanged || s.settleLeft > 0) {
        if (isNew) s.settleLeft = 0;
        else if (backdropChanged) s.settleLeft = AD_SETTLE_SEC;
        else s.settleLeft = Math.max(0, s.settleLeft - dt);
        s.updatedSerial = serial;
        pend.push({ sid, isNew, isDark: s.isDark, cx: s.cx, cy: s.cy, hx: s.hx, hy: s.hy });
      }
    }
    return pend;
  }
  function adRunUpdates(pend, dt) {
    if (!pend.length || !bdTex || !adProg) return;
    ensureAdTex();
    const cur = adCur, nxt = 1 - cur;
    gl.disable(gl.BLEND);
    gl.disable(gl.SCISSOR_TEST);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, adFb[cur]);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, adFb[nxt]);
    gl.blitFramebuffer(0, 0, AD_MAX, 1, 0, 0, AD_MAX, 1, gl.COLOR_BUFFER_BIT, gl.NEAREST);
    gl.bindFramebuffer(gl.FRAMEBUFFER, adFb[nxt]);
    gl.viewport(0, 0, AD_MAX, 1);
    gl.enable(gl.SCISSOR_TEST);
    gl.useProgram(adProg);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, bdTex);
    gl.uniform1i(ADU.u_bd, 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, adTex[cur]);
    gl.uniform1i(ADU.u_prev, 1);
    gl.uniform4fv(ADU.u_map, gmap);
    gl.uniform4fv(ADU.u_uvc, guvc);
    for (const p of pend) {
      gl.scissor(p.sid, 0, 1, 1);
      gl.uniform4f(ADU.u_box, p.cx, p.cy, p.hx, p.hy);
      gl.uniform4f(ADU.u_param, p.isDark, p.isNew, dt, p.sid);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
    adCur = nxt;
  }
  function adNextDt() {
    if (shotAt >= 0) return 1 / 60;
    const now = performance.now() / 1000;
    const dt = adLastTime > 0 ? Math.min(Math.max(now - adLastTime, 0), 0.1) : (1 / 60);
    adLastTime = now;
    return dt;
  }
  function scheduleAdRaf(wid) {
    if (adRaf || shotAt >= 0) return;
    const raf = wid === 0 ? requestAnimationFrame : (f) => { if (wins[wid] && !wins[wid].closed) wins[wid].win.requestAnimationFrame(f); };
    adRaf = raf(() => {
      inWin(wid, () => {
        adRaf = 0;
        if (!adSettling || lastN <= 0) return;
        if (wid === 0 ? pending : wins[wid]?.pending) {
          scheduleAdRaf(wid);
          return;
        }
        dirtyTold = true; dirtyWhole = false; dirty = [];
        presentCached(true);
      });
    });
  }
  function adFinalizeFrame(wholeFrame, serial) {
    let settling = false;
    for (let i = 0; i < AD_MAX; i++) {
      const s = adSlots[i];
      if (!s.active) continue;
      if (wholeFrame && s.seenSerial !== serial) {
        s.active = false; s.settleLeft = 0; continue;
      }
      if (s.settleLeft > 0) settling = true;
    }
    adSettling = settling;
    if (settling) scheduleAdRaf(winActive);
  }
  function slotsInvalidate() {
    for (let i = 0; i < GLASS_SLOTS; i++) glassSlots[i].valid = false;
  }
  function glassForget() {
    slotsInvalidate();
    adForget();
  }
  function glassLost() {
    lv = null; lvW = 0; lvH = 0; bdTex = null;
    lensLv = null; lensW = 0; lensH = 0;
    for (let i = 0; i < GLASS_SLOTS; i++) {
      const s = glassSlots[i];
      s.bt = null; s.bfb = null; s.bw = 0; s.bh = 0; s.bf = 0; s.valid = false;
    }
    adTex = [null, null]; adFb = [null, null]; adCur = 0;
    glassForget();
  }
  function glassFree() {
    if (lv && gl) for (const l of lv) { gl.deleteTexture(l.t); gl.deleteFramebuffer(l.fb); }
    if (lensLv && gl) for (const l of lensLv) { gl.deleteTexture(l.t); gl.deleteFramebuffer(l.fb); }
    if (gl) {
      for (let i = 0; i < GLASS_SLOTS; i++) {
        const s = glassSlots[i];
        if (s.bt) { gl.deleteFramebuffer(s.bfb); gl.deleteTexture(s.bt); }
        s.under = null; s.underN = 0;
      }
      for (let i = 0; i < 2; i++) {
        if (adFb[i]) gl.deleteFramebuffer(adFb[i]);
        if (adTex[i]) gl.deleteTexture(adTex[i]);
      }
    }
    glassLost();
  }
  function glassIdleTick() {
    if (glassDrawn) glassIdle = 0;
    else if (glassIdle < GLASS_IDLE && ++glassIdle === GLASS_IDLE && (lv || glassSlots.some((s) => s.bt))) glassFree();
    glassDrawn = false;
  }
  // every open window's glass and partial-redraw canvas given back (the page hidden), the one in place as it was after
  function trimRender() {
    for (let i = 0; i < MB_WINS; i++) {
      const s = wins[i];
      if (!s || (i !== 0 && s.closed)) continue;
      inWin(i, () => {
        glassFree();
        glassIdle = 0;
        if (cv && gl) { gl.deleteTexture(cv.t); gl.deleteFramebuffer(cv.fb); }
        cv = null; cvOk = false;
      });
    }
  }
  document.addEventListener('visibilitychange', () => { if (document.hidden) trimRender(); });
  function ensureLevels(w, h) {
    if (lv && lvW >= w && lvH >= h) return;
    if (lv) for (const l of lv) { gl.deleteTexture(l.t); gl.deleteFramebuffer(l.fb); }
    lvW = Math.max(w, lvW); lvH = Math.max(h, lvH);
    slotsInvalidate();
    lv = [];
    for (let j = 0; j < 4; j++) lv.push(levelTex(j === 0 ? gl.RGBA8 : gl.RGB10_A2, (lvW + (1 << j) - 1) >> j, (lvH + (1 << j) - 1) >> j));
    lv.push(levelTex(gl.RGB10_A2, lvW, lvH));
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }
  function ensureLensLevels(w, h) {
    if (lensLv && lensW >= w && lensH >= h) return;
    if (lensLv) for (const l of lensLv) { gl.deleteTexture(l.t); gl.deleteFramebuffer(l.fb); }
    lensW = Math.max(w, lensW); lensH = Math.max(h, lensH);
    lensLv = [levelTex(gl.RGBA8, lensW, lensH), levelTex(gl.RGBA8, lensW, lensH)];
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }
  function postPass(src, sw, sh, dst, w, h, mode, sg, dx, dy) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, dst.fb);
    if (gl.invalidateFramebuffer) gl.invalidateFramebuffer(gl.FRAMEBUFFER, [gl.COLOR_ATTACHMENT0]);
    gl.viewport(0, 0, w, h);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, src.t);
    gl.uniform1i(PU.u_src, 0);
    gl.uniform4f(PU.u_a, 1 / src.w, 1 / src.h, mode, sg);
    gl.uniform4f(PU.u_b, (sw - 0.5) / src.w, (sh - 0.5) / src.h, dx, dy);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  // ---- partial redraw ----
  // Whole-screen frames draw straight into the default framebuffer (null) without allocating or blitting cv.
  // Once the app reports partial dirty rects (H.renderDirty), we allocate cv, draw a baseline if !cvOk, and
  // scissor-redraw only dirty rects into cv before blitting to null (matching gles_render.h:1526-1542).
  let cv = null, cvOk = false, target = null;
  let dirty = [], dirtyWhole = false, dirtyTold = false, missing = false, drewMissing = false, cutOn = false;
  const cut = [0, 0, 0, 0];
  let glassLightAngle = 0;
  H.glassLightAngle = (rad) => {
    glassLightAngle = Number.isFinite(rad) ? rad : 0;
    progGen++;
  };
  H.renderDirty = (x, y, w, h) => {
    dirtyTold = true;
    if (w < 0 || h < 0) dirtyWhole = true;
    else if (w > 0 && h > 0) dirty.push([x, y, w, h]);
  };
  // the parts of the frame the next one draws, from what was said of them (taken: a frame nothing was said for is
  // drawn whole), each as `cut` is; null: all of it. `kept`: cv holds the frame before
  function takeParts(kept) {
    const told = dirtyTold, whole = dirtyWhole, said = dirty;
    dirtyTold = false;
    dirtyWhole = false;
    dirty = [];
    if (!told || whole || !kept || missing) return null;
    const W = canvas.width, Hh = canvas.height, out = [];
    for (const [x, y, w, h] of said) {
      // (whole pixels round it, and one more)
      const x0 = Math.max(0, Math.floor(x * dpr) - 1), y0 = Math.max(0, Math.floor(y * dpr) - 1);
      const x1 = Math.min(W, Math.ceil((x + w) * dpr) + 1), y1 = Math.min(Hh, Math.ceil((y + h) * dpr) + 1);
      if (x1 > x0 && y1 > y0) out.push([x0, Hh - y1, x1 - x0, y1 - y0]);
    }
    return out;
  }
  // cv the canvas's size: made again at another, what it held lost
  function ensureCanvas() {
    const W = canvas.width, Hh = canvas.height;
    if (cv && cv.w === W && cv.h === Hh) return;
    if (cv) { gl.deleteTexture(cv.t); gl.deleteFramebuffer(cv.fb); }
    cv = null;
    cvOk = false;
    if (W <= 0 || Hh <= 0) return;
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA8, W, Hh);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    cv = { t, fb, w: W, h: Hh };
  }

  function grabOf(start, end, count) {
    const a = start * INST;
    // For frosted glass (kind 5), negative slot 7 is contained; for liquid glass (kind 6), negative slot 7 encodes clear-lens zoom.
    const kind = Math.round(f32[a + 5]);
    const isContained = kind === 5 && f32[a + 7] < 0;
    const isProgressive = kind === 5 && f32[a + 22] < -0.5;
    const blur = (kind === 6 && f32[a + 7] < 0) ? 0 : Math.abs(f32[a + 7]);
    const mergedLiquid = kind === 6 && f32[a + 23] > 0;
    const unmergedLiquid = kind === 6 && !mergedLiquid;
    let margin = isContained ? 0 : 3 * blur + (kind === 6 ? f32[a + 21] * (1 + Math.abs(f32[a + 22])) + Math.max(f32[a + 23], 0) : 0) + 2;
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    let mN = 0;
    const mShape = new Float32Array(32), mRad = new Float32Array(32);
    for (let i = start; i < end; i++) {
      const b = i * INST;
      let bx0 = Math.max(f32[b], f32[b + 16]), by0 = Math.max(f32[b + 1], f32[b + 17]);
      let bx1 = Math.min(f32[b] + f32[b + 2], f32[b + 18]), by1 = Math.min(f32[b + 1] + f32[b + 3], f32[b + 19]);
      if (kind === 6) {
        const m = Math.max(unmergedLiquid ? f32[b + 23] : f32[a + 23], 0);
        bx0 = f32[b] - m; by0 = f32[b + 1] - m; bx1 = f32[b] + f32[b + 2] + m; by1 = f32[b + 1] + f32[b + 3] + m;
        if (mergedLiquid && mN < 8) {
          for (let k = 0; k < 4; k++) mShape[mN * 4 + k] = f32[b + k];
          if (Math.max(f32[b + 36], f32[b + 37], f32[b + 38], f32[b + 39]) > 0) {
            for (let k = 0; k < 4; k++) mRad[mN * 4 + k] = f32[b + 36 + k];
          } else {
            for (let k = 0; k < 4; k++) mRad[mN * 4 + k] = f32[b + 4];
          }
          mN++;
        }
        if (unmergedLiquid) {
          const bm = 3 * blur + f32[b + 21] * (1 + Math.abs(f32[b + 22])) + m + 2;
          if (bm > margin) margin = bm;
        }
      }
      x0 = Math.min(x0, bx0); y0 = Math.min(y0, by0); x1 = Math.max(x1, bx1); y1 = Math.max(y1, by1);
    }
    for (let i = end; (kind === 5 || unmergedLiquid) && i < count; i++) {
      const b = i * INST;
      if (f32[b + 20] !== f32[a + 20]) continue;
      if (unmergedLiquid) {
        const m = Math.max(f32[b + 23], 0);
        x0 = Math.min(x0, f32[b] - m); y0 = Math.min(y0, f32[b + 1] - m);
        x1 = Math.max(x1, f32[b] + f32[b + 2] + m); y1 = Math.max(y1, f32[b + 1] + f32[b + 3] + m);
        {
          const bm = 3 * blur + f32[b + 21] * (1 + Math.abs(f32[b + 22])) + m + 2;
          if (bm > margin) margin = bm;
        }
      } else {
        x0 = Math.min(x0, Math.max(f32[b], f32[b + 16])); y0 = Math.min(y0, Math.max(f32[b + 1], f32[b + 17]));
        x1 = Math.max(x1, Math.min(f32[b] + f32[b + 2], f32[b + 18])); y1 = Math.max(y1, Math.min(f32[b + 1] + f32[b + 3], f32[b + 19]));
      }
    }
    const W = canvas.width, Hh = canvas.height, sc = dpr;
    // in the canvas's pixels, from its foot (GL's way up)
    const px0 = Math.max(0, Math.floor((x0 - margin) * sc)), px1 = Math.min(W, Math.ceil((x1 + margin) * sc));
    const pb0 = Math.max(0, Hh - Math.ceil((y1 + margin) * sc)), pb1 = Math.min(Hh, Hh - Math.floor((y0 - margin) * sc));
    if (px1 <= px0 || pb1 <= pb0 || x1 <= x0 || y1 <= y0) return null;
    // (a capture outside the part drawn: neither copied nor drawn. One that meets it is in it whole: @damage)
    if (cutOn && (px1 <= cut[0] || cut[0] + cut[2] <= px0 || pb1 <= cut[1] || cut[1] + cut[3] <= pb0)) return null;
    const w = px1 - px0, h = pb1 - pb0;
    const contained = isContained && (f32[a + 4] > 0 ||
      [24, 25, 26, 27, 44, 45, 46, 47].some((i) => f32[a + i] > 0));
    let edge = null;
    if (contained) {
      edge = new Float32Array(36);
      edge.set([px0 / sc, (Hh - pb0) / sc, 1 / sc, -1 / sc], 0);
      edge.set([f32[a], f32[a + 1], f32[a] + f32[a + 2], f32[a + 1] + f32[a + 3]], 4);
      for (let i = 0; i < 4; i++) {
        edge[8 + i] = f32[a + 36 + i]; edge[12 + i] = f32[a + 16 + i];
        edge[16 + i] = f32[a + 24 + i]; edge[20 + i] = f32[a + 28 + i];
        edge[24 + i] = f32[a + 40 + i]; edge[28 + i] = f32[a + 44 + i]; edge[32 + i] = f32[a + 48 + i];
      }
    }
    const sp = blur * sc;
    let k = 0;
    while (k < 3 && sp / (1 << (k + 1)) >= 2) k++;
    if (isProgressive && k === 0 && sp > 0.5) k = 1;
    const sk = sp / (1 << k);
    const pre = k > 0 ? 0.75 * (1 - Math.pow(0.25, k)) / 3 + 1 / 6 : 0;
    const sg = Math.sqrt(Math.max(sk * sk - pre, 0));
    const fade = isProgressive ? [f32[a + 52], f32[a + 53], f32[a + 54], f32[a + 55]] : null;
    const fadex = isProgressive ? [f32[a + 56], f32[a + 57], f32[a + 58], f32[a + 59]] : null;
    return {
      px0, pb0, w, h, top: Hh, k, contained, progressive: isProgressive, n: mN, sg, sp, fade, fadex,
      gb: [x0 - 2, y0 - 2, x1 + 2, y1 + 2],
      shape: mShape, rad: mRad, edge,
    };
  }

  // Host-added adaptive settle regions must include every capture they touch, including other captures they then reach.
  function closeAdaptiveParts(parts, count) {
    const grabs = [], wasCut = cutOn;
    cutOn = false;
    for (let start = 0; start < count;) {
      const tid = f32[start * INST + 20];
      let end = start + 1;
      while (end < count && f32[end * INST + 20] === tid) end++;
      if (tid < 0) {
        const m = grabOf(start, end, count);
        if (m) grabs.push([Math.max(0, m.px0 - 1), Math.max(0, m.pb0 - 1),
          Math.min(canvas.width, m.px0 + m.w + 1), Math.min(canvas.height, m.pb0 + m.h + 1)]);
      }
      start = end;
    }
    cutOn = wasCut;
    let changed;
    do {
      changed = false;
      for (const p of parts) {
        let x0 = p[0], y0 = p[1], x1 = x0 + p[2], y1 = y0 + p[3];
        for (const g of grabs) {
          if (x0 >= g[2] || x1 <= g[0] || y0 >= g[3] || y1 <= g[1]) continue;
          if (x0 > g[0] || y0 > g[1] || x1 < g[2] || y1 < g[3]) {
            x0 = Math.min(x0, g[0]); y0 = Math.min(y0, g[1]);
            x1 = Math.max(x1, g[2]); y1 = Math.max(y1, g[3]);
            changed = true;
          }
        }
        p[0] = x0; p[1] = y0; p[2] = x1 - x0; p[3] = y1 - y0;
      }
      for (let i = 0; i < parts.length; i++) {
        const a = parts[i];
        let ax0 = a[0], ay0 = a[1], ax1 = ax0 + a[2], ay1 = ay0 + a[3];
        for (let j = i + 1; j < parts.length;) {
          const b = parts[j];
          const bx0 = b[0], by0 = b[1], bx1 = bx0 + b[2], by1 = by0 + b[3];
          if (ax0 <= bx1 && bx0 <= ax1 && ay0 <= by1 && by0 <= ay1) {
            ax0 = Math.min(ax0, bx0); ay0 = Math.min(ay0, by0);
            ax1 = Math.max(ax1, bx1); ay1 = Math.max(ay1, by1);
            a[0] = ax0; a[1] = ay0; a[2] = ax1 - ax0; a[3] = ay1 - ay0;
            parts.splice(j, 1);
            changed = true;
          } else {
            j++;
          }
        }
      }
    } while (changed);
  }

  function grabLevels(m) {
    const lw = [m.w], lh = [m.h];
    for (let j = 1; j <= 3; j++) {
      lw[j] = (lw[j - 1] + 1) >> 1;
      lh[j] = (lh[j - 1] + 1) >> 1;
    }
    return [lw, lh];
  }

  function grabBlurred(m) {
    return (m.progressive || (m.contained && m.k === 0)) ? lv[4] : lv[m.k];
  }

  function showBlur(m, bt, bw, bh) {
    const [lw, lh] = grabLevels(m);
    const sk = m.progressive ? 0 : m.k, d = 1 << sk, sc = dpr;
    for (let i = 0; i < 4; i++) ggb[i] = m.gb[i];
    gshape.set(m.shape);
    grad.set(m.rad);
    gn = m.n;
    bdTex = bt;
    gmap[0] = sc / d / bw; gmap[1] = -sc / d / bh;
    gmap[2] = -m.px0 / d / bw; gmap[3] = (m.top - m.pb0) / d / bh;
    guvc[0] = 0.5 / bw; guvc[1] = 0.5 / bh; guvc[2] = (lw[sk] - 0.5) / bw; guvc[3] = (lh[sk] - 0.5) / bh;
  }

  function blurGlass(m) {
    const w = m.w, h = m.h, k = m.k, contained = m.contained;
    ensureLevels(w, h);
    gl.disable(gl.BLEND);
    // (the copy and the passes whole, not cut to the part: a blit is cut by the scissor too)
    gl.disable(gl.SCISSOR_TEST);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, target);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, lv[0].fb);
    if (gl.invalidateFramebuffer) gl.invalidateFramebuffer(gl.DRAW_FRAMEBUFFER, [gl.COLOR_ATTACHMENT0]);
    gl.blitFramebuffer(m.px0, m.pb0, m.px0 + w, m.pb0 + h, 0, 0, w, h, gl.COLOR_BUFFER_BIT, gl.NEAREST);
    gl.useProgram(post);
    const [lw, lh] = grabLevels(m);
    if (m.progressive) {
      let prevVar = 0;
      for (let j = 1; j <= k; j++) {
        postPass(lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0);
        const targetPx = Math.pow(Math.max(m.sp, 1), j / k);
        const haveVar = prevVar + 0.75 * (1 << (2 * j - 2));
        const needVar = Math.max(targetPx * targetPx - haveVar, 0);
        const sgJ = Math.sqrt(needVar) / (1 << j);
        if (sgJ > 0.3) {
          postPass(lv[j], lw[j], lh[j], lv[4], lw[j], lh[j], 2, sgJ, 1, 0);
          postPass(lv[4], lw[j], lh[j], lv[j], lw[j], lh[j], 2, sgJ, 0, 1);
        }
        prevVar = Math.max(haveVar, targetPx * targetPx);
      }
      const sc = dpr;
      const prog = new Float32Array(36);
      prog[0] = m.px0 / sc; prog[1] = (m.top - m.pb0) / sc;
      prog[2] = 1 / sc; prog[3] = -1 / sc;
      for (let i = 0; i < 4; i++) { prog[4 + i] = m.fade[i]; prog[8 + i] = m.fadex[i]; }
      prog[12] = m.sp; prog[13] = k;
      for (let j = 0; j < 4; j++) {
        const dj = 1 << j, tw = lv[j].w, th = lv[j].h;
        prog[16 + j * 4 + 0] = 1 / (dj * tw);
        prog[16 + j * 4 + 1] = 1 / (dj * th);
        prog[16 + j * 4 + 2] = (lw[j] - 0.5) / tw;
        prog[16 + j * 4 + 3] = (lh[j] - 0.5) / th;
      }
      gl.uniform4fv(PU.u_c, prog);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, lv[1].t); gl.uniform1i(PU.u_lv1, 1);
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, lv[2].t); gl.uniform1i(PU.u_lv2, 2);
      gl.activeTexture(gl.TEXTURE3); gl.bindTexture(gl.TEXTURE_2D, lv[3].t); gl.uniform1i(PU.u_lv3, 3);
      postPass(lv[0], w, h, lv[4], w, h, 4, 0, 0, 0);
      gl.activeTexture(gl.TEXTURE0);
      return;
    }
    if (contained) {
      gl.uniform4fv(PU.u_c, m.edge);
      postPass(lv[0], w, h, lv[4], w, h, 3, 0, 0, 0);
    }
    for (let j = 1; j <= k; j++) {
      postPass(j === 1 && contained ? lv[4] : lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0);
    }
    if (m.sg > 0.3) {
      const from = grabBlurred(m), tmp = contained && k === 0 ? lv[0] : lv[4];
      postPass(from, lw[k], lh[k], tmp, lw[k], lh[k], 2, m.sg, 1, 0);
      postPass(tmp, lw[k], lh[k], from, lw[k], lh[k], 2, m.sg, 0, 1);
    }
  }

  function reaches(i, run, g) {
    const b = i * INST;
    if (f32[b + 32] !== 0) return true;
    const kind = Math.round(f32[b + 5]);
    let e = kind === 2 ? Math.abs(f32[b + 7]) * 3 + 2 : 1;
    if (kind === 6) e = Math.max(f32[b + 23], f32[run * INST + 23], 0) + 2;
    e += 1;
    const x0 = Math.min(f32[b], f32[b] + f32[b + 2]) - e;
    const x1 = Math.max(f32[b], f32[b] + f32[b + 2]) + e;
    const y0 = Math.min(f32[b + 1], f32[b + 1] + f32[b + 3]) - e;
    const y1 = Math.max(f32[b + 1], f32[b + 1] + f32[b + 3]) + e;
    return x1 > g[0] && x0 < g[2] && y1 > g[1] && y0 < g[3];
  }

  function unstableUnder(i) {
    const tid = f32[i * INST + 20] | 0;
    if (tid > STREAM_TEX) return true;
    if (tid > 0 && Math.round(f32[i * INST + 5]) !== 9) {
      const im = images.get(tid);
      if (!im || !im.tex) return true;
    }
    return false;
  }

  function underTake(start, count, pieces, m) {
    const sc = dpr;
    const g = [m.px0 / sc - 1, (m.top - (m.pb0 + m.h)) / sc - 1, (m.px0 + m.w) / sc + 1, (m.top - m.pb0) / sc + 1];
    let whole = 0, run = 0;
    for (let i = 0; i < start; i++) {
      const tid = f32[i * INST + 20];
      if (i > 0 && tid !== f32[(i - 1) * INST + 20]) run = i;
      const k = Math.round(f32[i * INST + 5]);
      const sees = tid < 0 || k === 7 || ((k === 10 || k === 11) && f32[i * INST + 23] > 0);
      if (sees && reaches(i, run, g)) whole = i + 1;
    }
    const maxNeed = (start + (count - pieces)) * INST;
    if (underNow.length < maxNeed) underNow = new Float32Array(Math.max(maxNeed, underNow.length * 2));
    for (let i = 0; i < whole; i++) if (unstableUnder(i)) return false;
    let off = whole * INST;
    if (off > 0) underNow.set(f32.subarray(0, off), 0);
    let picked = 0;
    for (let i = whole; i < start; i++) {
      if (!reaches(i, i, g)) continue;
      if (unstableUnder(i)) return false;
      underNow.set(f32.subarray(i * INST, (i + 1) * INST), off);
      off += INST;
      picked++;
    }
    const pLen = (count - pieces) * INST;
    if (pLen > 0) {
      underNow.set(f32.subarray(pieces * INST, count * INST), off);
      off += pLen;
    }
    underNowN = off;
    underWhole = whole;
    underPicked = picked;
    return true;
  }

  function grabSame(a, b) {
    if (a.px0 !== b.px0 || a.pb0 !== b.pb0 || a.w !== b.w || a.h !== b.h || a.top !== b.top ||
        a.k !== b.k || a.contained !== b.contained || a.progressive !== b.progressive || a.n !== b.n ||
        a.sg !== b.sg || a.sp !== b.sp) return false;
    for (let i = 0; i < 4; i++) if (a.gb[i] !== b.gb[i]) return false;
    for (let i = 0; i < a.n * 4; i++) if (a.shape[i] !== b.shape[i]) return false;
    for (let i = 0; i < a.n * 4; i++) if (a.rad[i] !== b.rad[i]) return false;
    if (a.contained) {
      for (let i = 0; i < 36; i++) if (a.edge[i] !== b.edge[i]) return false;
    }
    if (a.progressive) {
      for (let i = 0; i < 4; i++) if (a.fade[i] !== b.fade[i] || a.fadex[i] !== b.fadex[i]) return false;
    }
    return true;
  }

  function slotSame(m, key) {
    for (let i = 0; i < GLASS_SLOTS; i++) {
      const s = glassSlots[i];
      if (!s.valid || s.underN !== underNowN || s.whole !== underWhole || s.picked !== underPicked) continue;
      let eq = true;
      for (let j = 0; j < 6; j++) if (s.key[j] !== key[j]) { eq = false; break; }
      if (!eq || !grabSame(s.grab, m)) continue;
      for (let j = 0; j < underNowN; j++) if (s.under[j] !== underNow[j]) { eq = false; break; }
      if (eq) return s;
    }
    return null;
  }

  function slotFill(m, frameClock) {
    const L = grabBlurred(m);
    let t0 = -1, t1 = -1, t2 = -1, t3 = -1, t4 = -1, fallback = 0;
    for (let i = 0; i < GLASS_SLOTS; i++) {
      const s = glassSlots[i];
      if (s.used < glassSlots[fallback].used) fallback = i;
      if (s.used > frameClock) continue;
      const hasBt = s.bt !== null;
      const sameTex = hasBt && s.bw === L.w && s.bh === L.h && s.bf === L.format;
      if (!s.valid) {
        if (sameTex) { if (t0 < 0) t0 = i; }
        else if (!hasBt) { if (t1 < 0) t1 = i; }
        else { if (t3 < 0) t3 = i; }
      } else if (sameTex) {
        if (t2 < 0 || s.used < glassSlots[t2].used) t2 = i;
      }
      if (t4 < 0 || s.used < glassSlots[t4].used) t4 = i;
    }
    const idx = t0 >= 0 ? t0 : t1 >= 0 ? t1 : t2 >= 0 ? t2 : t3 >= 0 ? t3 : t4 >= 0 ? t4 : fallback;
    const s = glassSlots[idx];
    s.valid = false;
    if (s.bt && s.bw === L.w && s.bh === L.h && s.bf === L.format) {
      const tmpT = s.bt, tmpFb = s.bfb;
      s.bt = L.t; s.bfb = L.fb;
      L.t = tmpT; L.fb = tmpFb;
    } else {
      if (s.bt) { gl.deleteFramebuffer(s.bfb); gl.deleteTexture(s.bt); }
      s.bt = L.t; s.bfb = L.fb; s.bw = L.w; s.bh = L.h; s.bf = L.format;
      const made = levelTex(s.bf, s.bw, s.bh);
      L.t = made.t; L.fb = made.fb;
    }
    return s;
  }

  function slotShow(m, s) {
    s.used = ++glassSlotsClock;
    showBlur(m, s.bt, s.bw, s.bh);
  }

  function slotKeep(s, m, key) {
    if (!s.under || s.under.length < underNowN) s.under = new Float32Array(Math.max(underNowN, INST));
    if (underNowN > 0) s.under.set(underNow.subarray(0, underNowN), 0);
    s.underN = underNowN;
    s.whole = underWhole;
    s.picked = underPicked;
    s.grab = m;
    s.key = key;
    s.valid = true;
  }

  // what the run [start, end) of glass sees, frosted glass of the same capture further on (glass.mbt
  // shares_capture) too; false when none of it shows. Leaves mainState in place when true.
  function capture(start, end, count, pieces, r, g, b, frameClock) {
    const m = grabOf(start, end, count);
    if (!m) return false;
    const key = [canvas.width, canvas.height, dpr, r, g, b];
    const known = underTake(start, count, pieces, m);
    let s = known ? slotSame(m, key) : null;
    let reblurred = false;
    if (!s) {
      reblurred = true;
      blurGlass(m);
      s = slotFill(m, frameClock);
      const canKeep = !cutOn || (m.px0 >= cut[0] && m.px0 + m.w <= cut[0] + cut[2] && m.pb0 >= cut[1] && m.pb0 + m.h <= cut[1] + cut[3]);
      if (known && !drewMissing && canKeep) slotKeep(s, m, key);
    }
    slotShow(m, s);
    const adPend = adCollectAndMatch(start, count, m, reblurred, adCurDt, adFrameSerial);
    if (adPend.length) adRunUpdates(adPend, adCurDt);
    adFillUniforms();
    mainState();
    return true;
  }
  // the main programs' state, after the passes
  function mainState() {
    gl.bindFramebuffer(gl.FRAMEBUFFER, target);
    gl.viewport(0, 0, canvas.width, canvas.height);
    if (cutOn) {
      gl.enable(gl.SCISSOR_TEST);
      gl.scissor(cut[0], cut[1], cut[2], cut[3]);
    } else {
      gl.disable(gl.SCISSOR_TEST);
    }
    gl.enable(gl.BLEND);
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, bdTex || atlasTex);
    gl.activeTexture(gl.TEXTURE3);
    gl.bindTexture(gl.TEXTURE_2D, segsTex || atlasTex);
    gl.activeTexture(gl.TEXTURE4);
    gl.bindTexture(gl.TEXTURE_2D, adTex[adCur] || atlasTex);
    progGen++;
    useProg(-1);
  }

  // The pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), for the
  // shader to read (u_segs): a float texture of SEGS_ROW fours a row (136 instances' 15), as many rows as they take.
  const SEGS_ROW = 2040;
  let segsTex = null, segsRows = 0, segsHad = null, segsHadRows = 0;
  function segsUpload(n) {
    let d = n;
    while (d > 0 && Math.round(f32[(d - 1) * INST + 5]) === 12) d--;
    if (d === n) return;
    const rows = Math.ceil((n - d) * (INST / 4) / SEGS_ROW);
    gl.activeTexture(gl.TEXTURE3);
    if (!segsTex || rows > segsRows) {
      if (segsTex) gl.deleteTexture(segsTex);
      segsTex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, segsTex);
      segsRows = rows * 2;
      segsHad = null;
      gl.texStorage2D(gl.TEXTURE_2D, 1, gl.RGBA32F, SEGS_ROW, segsRows);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    }
    gl.bindTexture(gl.TEXTURE_2D, segsTex);
    const from = d * INST, need = rows * SEGS_ROW * 4;
    // (the same pieces as the texture holds, as a list scrolled has them, its bands moved and not their shares:
    // nothing to upload, as the GLES host's segs_upload)
    const pieces = f32.subarray(from, n * INST);
    if (segsHad && segsHad.length === pieces.length && segsHadRows === rows) {
      let same = true;
      for (let i = 0; i < pieces.length; i++) if (pieces[i] !== segsHad[i]) { same = false; break; }
      if (same) return;
    }
    segsHad = pieces.slice();
    segsHadRows = rows;
    let data = f32.subarray(from, from + need);
    if (data.length < need) {
      data = new Float32Array(need);
      data.set(pieces);
    }
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, SEGS_ROW, rows, gl.RGBA, gl.FLOAT, data);
  }

  // ---- banded scissor strips (src/host/bands.h) ----
  const MB_BAND_COST = 4096, MB_PIECE_COST = 16384, MB_BAND_MARGIN = 2, MB_BAND_ROWS = 8, MB_STRIPS = 140;
  const bandOut = new Int32Array(MB_STRIPS * 5);
  const bandTry = new Int32Array(MB_STRIPS * 5);
  const bandHole = { x0: 0, y0: 0, x1: 0, y1: 0, r0: 0, r1: 0, r2: 0, r3: 0 };
  const bandWhole = { x0: 0, y0: 0, x1: 0, y1: 0 };
  const bandR = new Float32Array(4);
  const bandSpan = [0, 0];
  const bandPiecesX0 = new Int32Array(11), bandPiecesY0 = new Int32Array(11);
  const bandPiecesX1 = new Int32Array(11), bandPiecesY1 = new Int32Array(11);

  function mbRoundSpan(s, y, t, outIdx) {
    const x0 = s.x0 + t, y0 = s.y0 + t, x1 = s.x1 - t, y1 = s.y1 - t;
    if (y < y0 || y > y1 || x1 <= x0) return false;
    const top = y < (s.y0 + s.y1) * 0.5;
    const left = top ? s.r0 : s.r3, right = top ? s.r1 : s.r2;
    const dy = top ? y - y0 : y1 - y;
    let inL = 0, inR = 0;
    const rhoL = left - t;
    if (rhoL > 0 && dy < rhoL) {
      const d = rhoL - dy;
      inL = rhoL - Math.sqrt(Math.max(rhoL * rhoL - d * d, 0));
    }
    const rhoR = right - t;
    if (rhoR > 0 && dy < rhoR) {
      const d = rhoR - dy;
      inR = rhoR - Math.sqrt(Math.max(rhoR * rhoR - d * d, 0));
    }
    const l = x0 + inL, r = x1 - inR;
    bandSpan[outIdx] = l;
    bandSpan[outIdx + 1] = r;
    return l < r;
  }

  function mbRoundNarrowest(s, y0, y1, t) {
    const a = mbRoundSpan(s, y0, t, 0);
    const l0 = bandSpan[0], r0 = bandSpan[1];
    const b = mbRoundSpan(s, y1, t, 0);
    const l1 = bandSpan[0], r1 = bandSpan[1];
    const l = Math.max(l0, l1), r = Math.min(r0, r1);
    bandSpan[0] = l;
    bandSpan[1] = r;
    return a && b && l < r;
  }

  function mbInside(a, up, inset, scale, o) {
    const hw = f32[a + 2] * 0.5, hh = f32[a + 3] * 0.5;
    const room = Math.min(hw, hh);
    if (room <= inset) return false;
    for (let i = 0; i < 4; i++) {
      const rr = Math.min(f32[a + 36 + i], room);
      if (rr <= 0) { bandR[i] = 0; continue; }
      if (room - rr < 0.25 * rr) return false;
      bandR[i] = Math.min(rr * 1.25, room) * scale;
    }
    const t = inset * scale;
    o.x0 = f32[a] * scale + t;
    o.y0 = (f32[a + 1] - up) * scale + t;
    o.x1 = (f32[a] + f32[a + 2]) * scale - t;
    o.y1 = (f32[a + 1] - up + f32[a + 3]) * scale - t;
    o.r0 = Math.max(bandR[0] - t, 0);
    o.r1 = Math.max(bandR[1] - t, 0);
    o.r2 = Math.max(bandR[2] - t, 0);
    o.r3 = Math.max(bandR[3] - t, 0);
    return o.x0 < o.x1 && o.y0 < o.y1;
  }

  function mbCutAlike(a, b) {
    for (let k = 16; k < 60; k++) {
      if ((k >= 20 && k < 24) || (k >= 36 && k < 40)) continue;
      if (f32[a + k] !== f32[b + k]) return false;
    }
    return true;
  }

  function mbWhole(a, kind, scale, toX0, toY0, toX1, toY1) {
    const grow = kind === 2 ? f32[a + 7] * 3 + 2 : 1;
    let x0 = Math.floor((f32[a] - grow) * scale);
    let y0 = Math.floor((f32[a + 1] - grow) * scale);
    let x1 = Math.ceil((f32[a] + f32[a + 2] + grow) * scale);
    let y1 = Math.ceil((f32[a + 1] + f32[a + 3] + grow) * scale);
    if (f32[a + 35] < 0.5) {
      x0 = Math.max(x0, Math.floor(Math.max(f32[a + 16] * scale, -1e8)));
      y0 = Math.max(y0, Math.floor(Math.max(f32[a + 17] * scale, -1e8)));
      x1 = Math.min(x1, Math.ceil(Math.min(f32[a + 18] * scale, 1e8)));
      y1 = Math.min(y1, Math.ceil(Math.min(f32[a + 19] * scale, 1e8)));
    }
    bandWhole.x0 = Math.max(x0, toX0);
    bandWhole.y0 = Math.max(y0, toY0);
    bandWhole.x1 = Math.min(x1, toX1);
    bandWhole.y1 = Math.min(y1, toY1);
  }

  function mbPieces(a, scale, toX0, toY0, toX1, toY1, out) {
    for (let k = 0; k < 4; k++) if (f32[a + 24 + k] > 0 || f32[a + 44 + k] > 0) return -1;
    if (f32[a + 53] > 0 || f32[a + 55] > 0 || f32[a + 57] > 0 || f32[a + 59] > 0 || f32[a + 35] > 0.5) return -1;
    mbWhole(a, 0, scale, toX0, toY0, toX1, toY1);
    const hw = f32[a + 2] * 0.5, hh = f32[a + 3] * 0.5, room = Math.min(hw, hh);
    for (let i = 0; i < 4; i++) {
      const rr = Math.min(f32[a + 36 + i], room);
      if (rr <= 0) { bandR[i] = 0; continue; }
      if (room - rr < 0.25 * rr) return -1;
      bandR[i] = Math.min(rr * 1.25, room) * scale;
    }
    const m = MB_BAND_MARGIN;
    const x0 = f32[a] * scale, y0 = f32[a + 1] * scale, x1 = (f32[a] + f32[a + 2]) * scale, y1 = (f32[a + 1] + f32[a + 3]) * scale;
    const inX0 = Math.max(Math.ceil(f32[a + 16] * scale) + 1, toX0);
    const inY0 = Math.max(Math.ceil(f32[a + 17] * scale) + 1, toY0);
    const inX1 = Math.min(Math.floor(f32[a + 18] * scale) - 1, toX1);
    const inY1 = Math.min(Math.floor(f32[a + 19] * scale) - 1, toY1);
    const c0 = bandWhole.x0, c5 = bandWhole.x1, r0 = bandWhole.y0, r5 = bandWhole.y1;
    let c1 = Math.ceil(x0 + m), c4 = Math.floor(x1 - m), r1 = Math.ceil(y0 + m), r4 = Math.floor(y1 - m);
    if (c1 < inX0) c1 = inX0;
    if (c4 > inX1) c4 = inX1;
    if (r1 < inY0) r1 = inY0;
    if (r4 > inY1) r4 = inY1;
    if (c1 < c0 || r1 < r0 || c4 > c5 || r4 > r5 || c1 >= c4 || r1 >= r4) return -1;
    let c2 = Math.ceil(x0 + Math.max(bandR[0], bandR[3])), c3 = Math.floor(x1 - Math.max(bandR[1], bandR[2]));
    let r2 = Math.ceil(y0 + Math.max(bandR[0], bandR[1])), r3 = Math.floor(y1 - Math.max(bandR[3], bandR[2]));
    if (c2 < c1) c2 = c1;
    if (c3 > c4) c3 = c4;
    if (r2 < r1) r2 = r1;
    if (r3 > r4) r3 = r4;
    if (c2 > c3) { const mid = ((c2 + c3) / 2) | 0; c2 = c3 = mid < c1 ? c1 : mid > c4 ? c4 : mid; }
    if (r2 > r3) { const mid = ((r2 + r3) / 2) | 0; r2 = r3 = mid < r1 ? r1 : mid > r4 ? r4 : mid; }
    bandPiecesX0[0] = c2; bandPiecesY0[0] = r1; bandPiecesX1[0] = c3; bandPiecesY1[0] = r2;
    bandPiecesX0[1] = c1; bandPiecesY0[1] = r2; bandPiecesX1[1] = c4; bandPiecesY1[1] = r3;
    bandPiecesX0[2] = c2; bandPiecesY0[2] = r3; bandPiecesX1[2] = c3; bandPiecesY1[2] = r4;
    bandPiecesX0[3] = c0; bandPiecesY0[3] = r0; bandPiecesX1[3] = c5; bandPiecesY1[3] = r1;
    bandPiecesX0[4] = c0; bandPiecesY0[4] = r1; bandPiecesX1[4] = c2; bandPiecesY1[4] = r2;
    bandPiecesX0[5] = c3; bandPiecesY0[5] = r1; bandPiecesX1[5] = c5; bandPiecesY1[5] = r2;
    bandPiecesX0[6] = c0; bandPiecesY0[6] = r2; bandPiecesX1[6] = c1; bandPiecesY1[6] = r3;
    bandPiecesX0[7] = c4; bandPiecesY0[7] = r2; bandPiecesX1[7] = c5; bandPiecesY1[7] = r3;
    bandPiecesX0[8] = c0; bandPiecesY0[8] = r3; bandPiecesX1[8] = c2; bandPiecesY1[8] = r4;
    bandPiecesX0[9] = c3; bandPiecesY0[9] = r3; bandPiecesX1[9] = c5; bandPiecesY1[9] = r4;
    bandPiecesX0[10] = c0; bandPiecesY0[10] = r4; bandPiecesX1[10] = c5; bandPiecesY1[10] = r5;
    let flat = 0, n = 0;
    for (let k = 0; k < 11; k++) {
      const px0 = bandPiecesX0[k], py0 = bandPiecesY0[k], px1 = bandPiecesX1[k], py1 = bandPiecesY1[k];
      if (px1 <= px0 || py1 <= py0) continue;
      const o = n * 5;
      out[o] = px0; out[o + 1] = py0; out[o + 2] = px1; out[o + 3] = py1; out[o + 4] = k < 3 ? 1 : 0;
      if (k < 3) flat += (px1 - px0) * (py1 - py0);
      n++;
    }
    if (flat < n * MB_PIECE_COST) return -1;
    return n;
  }

  function mbBandKind(i) {
    const kind = Math.round(f32[i * INST + 5]);
    return kind === 0 || kind === 2;
  }

  function mbBands(i, count, scale, toX0, toY0, toX1, toY1, out) {
    if (H.env('MBUI_STRIPS') === '0') return -1;
    const a = i * INST;
    const kind = Math.round(f32[a + 5]);
    if (f32[a + 32] !== 0 || f32[a + 20] !== 0) return -1;
    if (kind === 2) {
      if (f32[a + 12] > 0.5) {
        if (!mbInside(a, f32[a + 13], 0, scale, bandHole)) return -1;
      } else {
        if (i + 1 >= count) return -1;
        const b = a + INST;
        if (Math.round(f32[b + 5]) !== 0 || f32[b + 20] !== 0 || f32[b + 11] !== 1 || f32[b + 22] > 0) return -1;
        if (f32[b + 6] > 0 && f32[b + 15] !== 1) return -1;
        if (!mbCutAlike(a, b)) return -1;
        for (let k = 0; k < 4; k++) if (f32[b + 24 + k] > 0 || f32[b + 44 + k] > 0) return -1;
        if (f32[b + 53] > 0 || f32[b + 55] > 0 || f32[b + 57] > 0 || f32[b + 59] > 0) return -1;
        if (!mbInside(b, 0, 0, scale, bandHole)) return -1;
      }
    } else if (kind === 0) {
      if (f32[a + 22] > 0) return -1;
      if (f32[a + 11] > 0 && f32[a + 6] <= 0) return mbPieces(a, scale, toX0, toY0, toX1, toY1, out);
      if (f32[a + 11] !== 0 || f32[a + 6] <= 0) return -1;
      if (!mbInside(a, 0, f32[a + 6], scale, bandHole)) return -1;
    } else {
      return -1;
    }
    mbWhole(a, kind, scale, toX0, toY0, toX1, toY1);
    const wx0 = bandWhole.x0, wy0 = bandWhole.y0, wx1 = bandWhole.x1, wy1 = bandWhole.y1;
    const wholeArea = wx1 > wx0 && wy1 > wy0 ? (wx1 - wx0) * (wy1 - wy0) : 0;
    if (wholeArea <= MB_BAND_COST) return -1;
    const m = MB_BAND_MARGIN;
    const top = wy0, bottom = wy1;
    let hTop = Math.ceil(bandHole.y0 + m), hBottom = Math.floor(bandHole.y1 - m);
    const rTop = Math.max(bandHole.r0, bandHole.r1), rBottom = Math.max(bandHole.r2, bandHole.r3);
    const hrx0 = Math.max(wx0, Math.ceil(bandHole.x0 + m)), hry0 = Math.max(wy0, hTop);
    const hrx1 = Math.min(wx1, Math.floor(bandHole.x1 - m)), hry1 = Math.min(wy1, hBottom);
    const hrArea = hrx1 > hrx0 && hry1 > hry0 ? (hrx1 - hrx0) * (hry1 - hry0) : 0;
    if (hrArea <= 2 * MB_BAND_COST) return -1;
    let mTop = hTop + Math.ceil(rTop), mBottom = hBottom - Math.ceil(rBottom);
    if (mTop > mBottom) mTop = mBottom = ((mTop + mBottom) / 2) | 0;
    const clampY = (y) => (y < top ? top : y > bottom ? bottom : y);
    hTop = clampY(hTop); hBottom = clampY(hBottom); mTop = clampY(mTop); mBottom = clampY(mBottom);
    let best = wholeArea + MB_BAND_COST, last = -1, found = -1;
    const rows = Math.max(mTop - hTop, hBottom - mBottom);
    for (let k = 1; k <= 32 && (k === 1 || ((rows / k) | 0) >= MB_BAND_ROWS); k *= 2) {
      let n = 0, cost = 0;
      for (let s = 0; s < 2 * k + 3; s++) {
        let y0, y1;
        if (hTop >= hBottom) {
          if (s > 0) break;
          y0 = top; y1 = bottom;
        } else if (s === 0) {
          y0 = top; y1 = hTop;
        } else if (s <= k) {
          y0 = hTop + (((mTop - hTop) * (s - 1)) / k | 0);
          y1 = hTop + (((mTop - hTop) * s) / k | 0);
        } else if (s === k + 1) {
          y0 = mTop; y1 = mBottom;
        } else if (s <= 2 * k + 1) {
          const j = s - k - 2;
          y0 = mBottom + (((hBottom - mBottom) * j) / k | 0);
          y1 = mBottom + (((hBottom - mBottom) * (j + 1)) / k | 0);
        } else {
          y0 = hBottom; y1 = bottom;
        }
        if (y0 >= y1) continue;
        let hl = 0, hrr = 0;
        if (y0 >= hTop && y1 <= hBottom && mbRoundNarrowest(bandHole, y0, y1, m)) {
          hl = Math.max(wx0, Math.ceil(bandSpan[0]));
          hrr = Math.min(wx1, Math.floor(bandSpan[1]));
        }
        if (hl >= hrr) {
          if (wx1 > wx0) {
            const o = n * 5;
            bandTry[o] = wx0; bandTry[o + 1] = y0; bandTry[o + 2] = wx1; bandTry[o + 3] = y1; bandTry[o + 4] = 0;
            n++;
            cost += (wx1 - wx0) * (y1 - y0) + MB_BAND_COST;
          }
        } else {
          if (hl > wx0) {
            const o = n * 5;
            bandTry[o] = wx0; bandTry[o + 1] = y0; bandTry[o + 2] = hl; bandTry[o + 3] = y1; bandTry[o + 4] = 0;
            n++;
            cost += (hl - wx0) * (y1 - y0) + MB_BAND_COST;
          }
          if (wx1 > hrr) {
            const o = n * 5;
            bandTry[o] = hrr; bandTry[o + 1] = y0; bandTry[o + 2] = wx1; bandTry[o + 3] = y1; bandTry[o + 4] = 0;
            n++;
            cost += (wx1 - hrr) * (y1 - y0) + MB_BAND_COST;
          }
        }
      }
      if (cost < best) {
        best = cost;
        found = n;
        out.set(bandTry.subarray(0, n * 5), 0);
      }
      if (last >= 0 && cost >= last) break;
      last = cost;
    }
    return found;
  }

  function drawRun(first, count) {
    for (let i = 0; i < INST / 4; i++) gl.vertexAttribPointer(i, 4, gl.FLOAT, false, INST * 4, first * INST * 4 + i * 16);
    gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, count);
  }

  function drawBanded(start, end, count) {
    const W = canvas.width, Hh = canvas.height;
    const toX0 = cutOn ? cut[0] : 0;
    const toY0 = cutOn ? Hh - (cut[1] + cut[3]) : 0;
    const toX1 = cutOn ? cut[0] + cut[2] : W;
    const toY1 = cutOn ? Hh - cut[1] : Hh;
    let s = start;
    for (let i = start; i < end; i++) {
      if (!mbBandKind(i)) continue;
      const n = mbBands(i, count, dpr, toX0, toY0, toX1, toY1, bandOut);
      if (n < 0) continue;
      if (i > s) drawRun(s, i - s);
      gl.enable(gl.SCISSOR_TEST);
      for (let k = 0; k < n; k++) {
        const o = k * 5;
        const flat = bandOut[o + 4];
        if (k === 0 || flat !== bandOut[o - 1]) {
          gl.useProgram(flat ? progFlat : progNow);
          if (flat) gl.uniform2f(ufVp, W / dpr, Hh / dpr);
        }
        gl.scissor(bandOut[o], Hh - bandOut[o + 3], bandOut[o + 2] - bandOut[o], bandOut[o + 3] - bandOut[o + 1]);
        drawRun(i, 1);
      }
      if (n > 0 && bandOut[(n - 1) * 5 + 4]) gl.useProgram(progNow);
      if (cutOn) gl.scissor(cut[0], cut[1], cut[2], cut[3]);
      else gl.disable(gl.SCISSOR_TEST);
      s = i + 1;
    }
    if (end > s) drawRun(s, end - s);
  }

  function presentCached(fromCache = false) {
    const n = lastN, r = lastR, g = lastG, b = lastB;
    if (fromCache) {
      const need = n * INST + INST;
      if (!lastF32 || lastF32.length < need) return;
      if (f32.length < need) f32 = new Float32Array(need);
      f32.set(lastF32.subarray(0, need), 0);
    }
    adMode = 1;
    adCurDt = adNextDt();
    adFrameSerial++;
    const whole = !dirtyTold || dirtyWhole || missing;
    const adaptiveDamage = !whole && adSettling;
    if (adaptiveDamage) {
      for (let i = 0; i < AD_MAX; i++) {
        const s = adSlots[i];
        if (s.active && s.settleLeft > 0) dirty.push([s.cx - s.hx - 4, s.cy - s.hy - 4, s.hx * 2 + 8, s.hy * 2 + 8]);
      }
    }
    if (whole) {
      dirtyTold = false;
      dirtyWhole = false;
      dirty = [];
      cvOk = false;
      target = null;
      frameUpload(n);
      glassDrawn = false;
      drawFrame(n, r, g, b, false);
      missing = drewMissing;
      adFinalizeFrame(true, adFrameSerial);
      glassIdleTick();
      return;
    }
    ensureCanvas();
    if (!cv) {
      dirtyTold = false;
      dirtyWhole = false;
      dirty = [];
      cvOk = false;
      target = null;
      frameUpload(n);
      glassDrawn = false;
      drawFrame(n, r, g, b, false);
      missing = drewMissing;
      adFinalizeFrame(true, adFrameSerial);
      glassIdleTick();
      return;
    }
    const parts = takeParts(cvOk);
    if (parts && adaptiveDamage) closeAdaptiveParts(parts, n);
    target = cv.fb;
    // the frame's instances and its shapes' pieces uploaded once, whether drawn whole or a part at a time (each part
    // uploaded them all again: a list scrolled spent a fifth of its frames in bufferData)
    frameUpload(n);
    glassDrawn = false;
    if (!parts) {
      drawFrame(n, r, g, b, false);
      missing = drewMissing;
    } else if (parts.length) {
      let any = false;
      for (const p of parts) {
        for (let i = 0; i < 4; i++) cut[i] = p[i];
        drawFrame(n, r, g, b, true);
        any = any || drewMissing;
      }
      missing = any;
    }
    adFinalizeFrame(!parts, adFrameSerial);
    glassIdleTick();
    cvOk = !missing;
    target = null;
    gl.disable(gl.SCISSOR_TEST);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, cv.fb);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
    // (cleared first: a drawing buffer shown is cleared as it is next drawn to, and Chromium does not count a blit
    // as that: a frame that drew nothing new, only the blit, read back as cleared)
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.blitFramebuffer(0, 0, cv.w, cv.h, 0, 0, cv.w, cv.h, gl.COLOR_BUFFER_BIT, gl.NEAREST);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  // A frame presented: whole-screen frames straight onto the default framebuffer (null); once the app reports partial
  // dirty rects, into cv (building a baseline if !cvOk, then scissor-updating dirty rects) and blitted onto null.
  H.present = (buf, n, r, g, b) => {
    const len = n * INST;
    // (and the frame's ground after it: a rect over all the window, opaque, a part drawn again first)
    if (f32.length < len + INST) f32 = new Float32Array(len * 2 + INST);
    if (typeof buf.subarray === 'function') f32.set(buf.subarray(0, len), 0);
    else for (let i = 0; i < len; i++) f32[i] = buf[i];
    f32.fill(0, len, len + INST);
    f32[len] = -16; f32[len + 1] = -16; f32[len + 2] = cssW + 32; f32[len + 3] = cssH + 32;
    f32[len + 8] = r; f32[len + 9] = g; f32[len + 10] = b; f32[len + 11] = 1;
    f32[len + 16] = -1e9; f32[len + 17] = -1e9; f32[len + 18] = 1e9; f32[len + 19] = 1e9;
    lastN = n; lastR = r; lastG = g; lastB = b;
    const need = len + INST;
    if (!lastF32 || lastF32.length < need) lastF32 = new Float32Array(need);
    lastF32.set(f32.subarray(0, need), 0);
    presentCached(false);
  };

  // The frame's `n` instances (in f32, its ground after them) and its shapes' pieces into the GPU's buffer and texture:
  // once a frame (H.present), each part drawn from them.
  let uploadedFor = -1;
  function frameUpload(n) {
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    gl.bufferData(gl.ARRAY_BUFFER, f32.subarray(0, n * INST + INST), gl.STREAM_DRAW);
    segsUpload(n);
    uploadedFor = n;
  }

  // The frame's `n` instances (in f32, its ground after them) drawn into `target`: `part`, only into `cut` over what
  // it holds, else all of it, cleared to the ground.
  function drawFrame(n, r, g, b, part) {
    const len = n * INST;
    drewMissing = false;
    cutOn = part;
    gl.bindFramebuffer(gl.FRAMEBUFFER, target);
    gl.viewport(0, 0, canvas.width, canvas.height);
    if (!part) {
      gl.disable(gl.SCISSOR_TEST);
      gl.clearColor(r, g, b, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      if (n === 0) return;
    }
    bdTex = null;
    gmap.fill(0); guvc.fill(0); ggb.fill(0); gn = 0;
    adFillUniforms();
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, instBuf);
    if (uploadedFor !== n) frameUpload(n);
    mainState();
    if (part) {
      gl.disable(gl.BLEND);
      drawRun(n, 1);
      gl.enable(gl.BLEND);
    }
    let pieces = n;
    while (pieces > 0 && Math.round(f32[(pieces - 1) * INST + 5]) === 12) pieces--;
    // one draw per run of instances showing the same image (slot 20) of one kind (its program: useProg), or sharing
    // one capture of glass (negative); WebGL has no base instance, so the attributes start at the run instead
    // (and per run of holes, kind 9: written transparent with no blending, where a native view shows)
    let start = 0, bound = 0, shows = false, levelsSized = false;
    const frameGlassClock = glassSlotsClock;
    while (start < n) {
      const tid = f32[start * INST + 20] | 0;
      const kind = Math.round(f32[start * INST + 5]);
      if (kind === 8) {
        let childN = Math.round(f32[start * INST + 12]);
        if (childN < 0) childN = 0;
        if (start + 1 + childN > n) childN = n - start - 1;
        const hb = start * INST;
        if (childN <= 0 || f32[hb + 11] <= 0.001 || f32[hb + 2] <= 0 || f32[hb + 3] <= 0) {
          start += 1 + childN;
          continue;
        }
        glassDrawn = true;
        const scF = dpr;
        const blurPt = Math.max(f32[hb + 7], 0);
        const refrPt = Math.max(f32[hb + 14], 0);
        const margin = blurPt * 3 + refrPt + 4;
        let x0 = f32[hb], y0 = f32[hb + 1], x1 = f32[hb] + f32[hb + 2], y1 = f32[hb + 1] + f32[hb + 3];
        for (let ci = start + 1; ci < start + 1 + childN; ci++) {
          const cb = ci * INST;
          const ck = Math.round(f32[cb + 5]);
          if (ck === 12 || f32[cb + 2] <= 0 || f32[cb + 3] <= 0) continue;
          if (f32[cb] < x0) x0 = f32[cb];
          if (f32[cb + 1] < y0) y0 = f32[cb + 1];
          if (f32[cb] + f32[cb + 2] > x1) x1 = f32[cb] + f32[cb + 2];
          if (f32[cb + 1] + f32[cb + 3] > y1) y1 = f32[cb + 1] + f32[cb + 3];
        }
        const ox = Math.floor((x0 - margin) * scF) / scF;
        const oy = Math.floor((y0 - margin) * scF) / scF;
        const pw = Math.min(Math.max(1, Math.ceil(((x1 + margin) - ox) * scF)), Math.max(canvas.width, 2048));
        const ph = Math.min(Math.max(1, Math.ceil(((y1 + margin) - oy) * scF)), Math.max(canvas.height, 2048));
        ensureLensLevels(pw, ph);
        // Pass 1: render children into lensLv[0]
        gl.bindFramebuffer(gl.FRAMEBUFFER, lensLv[0].fb);
        gl.viewport(0, 0, pw, ph);
        gl.disable(gl.SCISSOR_TEST);
        gl.clearColor(0, 0, 0, 0);
        gl.clear(gl.COLOR_BUFFER_BIT);
        gl.enable(gl.BLEND);
        lensOx = ox; lensOy = oy; lensVpW = pw / scF; lensVpH = ph / scF;
        progGen++;
        let cs = start + 1, cendAll = start + 1 + childN;
        while (cs < cendAll) {
          const ctid = f32[cs * INST + 20] | 0;
          const ck = Math.round(f32[cs * INST + 5]);
          if (ck === 5 || ck === 6 || ck === 8 || ck === 9 || ck === 12 || ctid < 0) {
            cs++;
            continue;
          }
          const cown = hasOwnProg(ck);
          let ce = cs + 1;
          while (ce < cendAll && (f32[ce * INST + 20] | 0) === ctid) {
            const kk = Math.round(f32[ce * INST + 5]);
            if (kk === 5 || kk === 6 || kk === 8 || kk === 9 || kk === 12) break;
            if (cown ? kk !== ck : hasOwnProg(kk)) break;
            ce++;
          }
          let ct = atlasTex;
          if (ctid > STREAM_TEX) {
            const st = streams.get(ctid - STREAM_TEX);
            if (!st || !st.tex) { cs = ce; continue; }
            ct = st.tex;
          } else if (ctid > 0) {
            const im = images.get(ctid);
            if (im && im.tex) ct = im.tex;
            else drewMissing = true;
          }
          gl.activeTexture(gl.TEXTURE1);
          gl.bindTexture(gl.TEXTURE_2D, ct);
          useProg(cown ? ck : -1);
          drawRun(cs, ce - cs);
          cs = ce;
        }
        // Pass 2: separable Gaussian blur in RGBA8
        const sp = blurPt * scF;
        if (sp > 0.25) {
          gl.disable(gl.BLEND);
          gl.useProgram(post);
          postPass(lensLv[0], pw, ph, lensLv[1], pw, ph, 2, sp, 1, 0);
          postPass(lensLv[1], pw, ph, lensLv[0], pw, ph, 2, sp, 0, 1);
        }
        // Pass 3: composite refracted & SDF-clipped foreground lens onto target
        lensOx = 0; lensOy = 0; lensVpW = 0; lensVpH = 0;
        bdTex = lensLv[0].t;
        const W = lensLv[0].w, H = lensLv[0].h;
        gmap[0] = scF / W; gmap[1] = -scF / H;
        gmap[2] = -(ox * scF) / W; gmap[3] = (ph + oy * scF) / H;
        guvc[0] = 0.5 / W; guvc[1] = 0.5 / H;
        guvc[2] = (pw - 0.5) / W; guvc[3] = (ph - 0.5) / H;
        mainState();
        useProg(-1);
        drawRun(start, 1);
        bound = 0;
        start += 1 + childN;
        continue;
      }
      const h = kind === 9;
      const own = tid >= 0 && !h && hasOwnProg(kind);
      let end = start + 1;
      while (end < n && (f32[end * INST + 20] | 0) === tid) {
        const k = Math.round(f32[end * INST + 5]);
        if (k === 8 || (k === 9) !== h) break;
        if (own ? k !== kind : (tid >= 0 && !h && hasOwnProg(k))) break;
        end++;
      }
      if (tid < 0) {
        glassDrawn = true;
        if (!levelsSized) {
          levelsSized = true;
          let maxW = 0, maxH = 0, scanBound = 0;
          for (let s0 = start; s0 < n; ) {
            const stid = f32[s0 * INST + 20] | 0;
            let e0 = s0 + 1;
            if (stid < 0) {
              while (e0 < n && (f32[e0 * INST + 20] | 0) === stid) e0++;
              if (stid !== scanBound) {
                scanBound = stid;
                const gm = grabOf(s0, e0, n);
                if (gm) {
                  if (gm.w > maxW) maxW = gm.w;
                  if (gm.h > maxH) maxH = gm.h;
                }
              }
            }
            s0 = e0;
          }
          if (maxW > lvW || maxH > lvH) {
            ensureLevels(maxW, maxH);
            mainState();
          }
        }
        if (tid !== bound) {
          shows = capture(start, end, n, pieces, r, g, b, frameGlassClock);
          bound = tid;
        }
        if (shows) {
          // merged liquid (merge > 0): the group as one shape, drawn once; unmerged liquid and frosted: each instance
          const mergedLiquid = kind === 6 && f32[start * INST + 23] > 0;
          const gkind = kind === 5 ? 5 : (kind === 6 ? (mergedLiquid ? 6 : MB_KIND_LIQUID_SINGLE) : -1);
          useProg(gkind);
          drawRun(start, mergedLiquid ? 1 : end - start);
        }
        start = end;
        continue;
      }
      useProg(own ? kind : -1);
      // a stream's picture (STREAM_TEX + its id): nothing until a frame of its own shows; a hole's image is its
      // view's (src/hostapi/host.mbt view_tex_base + its id), the element under the canvas here
      // (in a window beside the page, its own texture of each: slotTex)
      const im = h ? null : tid > STREAM_TEX ? streams.get(tid - STREAM_TEX) : tid ? images.get(tid) : null;
      const tex = !im || !im.tex ? null : winActive === 0 ? im.tex : slotTex(wins[winActive], tid, im);
      if (!h && tid > STREAM_TEX && !tex) {
        start = end;
        continue;
      }
      if (!h && tid > 0 && tid <= STREAM_TEX && !tex) drewMissing = true;
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, tex || atlasTex);
      if (h) {
        gl.disable(gl.BLEND);
        drawRun(start, end - start);
        gl.enable(gl.BLEND);
      } else if (tid === 0) {
        drawBanded(start, end, n);
      } else {
        drawRun(start, end - start);
      }
      start = end;
    }
    if (part) gl.disable(gl.SCISSOR_TEST);
    cutOn = false;
  }

  // ---- native views over the canvas (src/ui/native.mbt) ----
  // DOM elements in a layer under the canvas, shown through its holes: a <video> whose bytes come through the app
  // (read in parts, then played from a Blob), a sandboxed <iframe> (scripts only) for a page of HTML, the frame of
  // H.siteFrame for a site where the page has one (a host of its own, whose service worker hands every request of the
  // site's page here over a port: still.fail's cloud/src/preview.ts says the messages).
  const views = new Map();
  let nextZ = 0;  // the z-index the next view raised takes (view_tell 5); one opened goes over those before it
  let nextView = 0, viewLayer = null;
  function layer() {
    if (!viewLayer) {
      viewLayer = doc.createElement('div');
      // over the page's own ground, under the canvas (both positioned: the body's ground would cover a layer below 0)
      viewLayer.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:0';
      doc.body.insertBefore(viewLayer, doc.body.firstChild);
      canvas.style.zIndex = '1';
    }
    return viewLayer;
  }
  const info = (v) => v.info || (v.info = [-1, 0, 0, 0, 0, 0, 0, 0]);
  // first in a page's frame: mbuiHost.post to this window, and the scripts this window sends run
  const PAGE_BRIDGE = '<script>window.mbuiHost={post:function(t){parent.postMessage({mbuiSaid:String(t)},"*")}};' +
    'addEventListener("message",function(e){if(e.source===parent&&e.data&&typeof e.data.mbuiScript==="string")(0,eval)(e.data.mbuiScript)});</script>';
  const runScripts = (v) => {
    if (!v.there || !v.el.contentWindow) return;
    for (const js of v.scripts) v.el.contentWindow.postMessage({ mbuiScript: js }, '*');
    v.scripts = [];
  };
  // what a page's frame says, from that frame only (no other window may speak for it); heard on the page and on each
  // window beside it, whose frames say it to their own (slotPage)
  const pageSaid = (e) => {
    if (!e.data || typeof e.data.mbuiSaid !== 'string') return;
    for (const v of views.values()) {
      if (v.kind !== 2 || e.source !== v.el.contentWindow) continue;
      v.said.push(JSON.stringify({ said: e.data.mbuiSaid }));
      v.there = true;
      runScripts(v);
      H.requestFrame();
    }
  };
  window.addEventListener('message', pageSaid);
  // ---- a site's frame ----
  // (the messages a site's frame and this host trade: `<the app's site name>-preview-…`, @hostapi.set_site_name)
  const preview = (name) => `${H.siteName || 'mbui'}-preview-${name}`;
  const fromFrame = (type) => type.startsWith(preview(''));
  const siteSay = (v, said) => { v.said.push(JSON.stringify(said)); H.requestFrame(); };
  const siteSays = (v, words) => siteSay(v, { said: JSON.stringify(words) });
  const toBase64 = (b) => { let s = ''; for (let i = 0; i < b.length; i += 8192) s += String.fromCharCode.apply(null, b.subarray(i, i + 8192)); return btoa(s); };
  const fromBase64 = (t) => Uint8Array.from(atob(t), (c) => c.charCodeAt(0));
  // What the frame's port says: a request of the site's page, one it gave up, its WebSockets. A socket is the app's as
  // a page's own script would say it (mbuiHost.post); no request is `page`: the frame's service worker puts what a page
  // needs first in it, the app has nothing to add. A request waits for its head as a browser's does (no `late`, no
  // `slow`: this host keeps nothing of an answer to read too slowly).
  const siteAsked = (v, m) => {
    if (m.type === 'cancel') { v.bodies.delete(m.id); siteSay(v, { gone: m.id }); }
    else if (m.type === 'socket') siteSays(v, { p: 'open', sid: m.sid, path: m.path, protocols: [].concat(m.protocols ?? []).join(', ') });
    else if (m.type === 'socket-send') {
      if (m.close) siteSays(v, { p: 'close', sid: m.sid, code: m.close[0], reason: m.close[1] || '' });
      else if (typeof m.text === 'string') siteSays(v, { p: 'send', sid: m.sid, text: m.text });
      else if (m.binary) siteSays(v, { p: 'sendBinary', sid: m.sid, b64: toBase64(new Uint8Array(m.binary)) });
    } else if (typeof m.id === 'number') {
      if (m.body) v.bodies.set(m.id, m.body);
      siteSay(v, { req: m.id, method: m.method, path: m.path, headers: m.headers || [], page: false });
    }
  };
  const sitePost = (v, m, transfer) => { if (v.port) v.port.postMessage(m, transfer || []); };
  const siteNav = (v, action, path) => { if (v.el.contentWindow) v.el.contentWindow.postMessage({ type: preview('nav'), action, path }, v.origin); };
  const siteSaid = (e) => {
    if (typeof e.data?.type !== 'string' || !fromFrame(e.data.type)) return;
    for (const v of views.values()) {
      if (v.kind !== 3 || e.source !== v.el.contentWindow || e.origin !== v.origin || e.data.nonce !== v.nonce) continue;
      const name = e.data.type.slice(preview('').length);
      if (name === 'ready' && !v.port) {
        const { port1, port2 } = new MessageChannel();
        v.port = port1;
        port1.onmessage = (m) => siteAsked(v, m.data);
        e.source.postMessage({ type: preview('port'), streams: true }, v.origin, [port2]);
      } else if (name === 'at') {
        Object.assign(v.at, { path: e.data.path, back: !!e.data.back, forward: !!e.data.forward, loading: false });
        v.at = { ...v.at };
        H.requestFrame();
      }
    }
  };
  window.addEventListener('message', siteSaid);
  // Where a press goes: the canvas lies over every view, so while a site is seen it takes none: they go to what is under
  // it (`under`, behind the views: every press where no view takes it, and every press's capture, as it stays) and,
  // over it, to one box for each rect the app says takes a press over a site (view_tell 4). Not by the canvas cut away
  // (clip-path) where a site is: a press goes through that, Chromium's scrolling does not (a finger or a wheel on the
  // site moves nothing); `pointer-events` both go by.
  // (each window's own, of the sites it shows: winSave; placeSitePresses for the window in place, siteFor another's)
  let under = null;
  let coverBoxes = [];
  const siteTakes = (v) => v.kind === 3 && v.seen && v.touch !== 'through';
  const placeSitePresses = () => {
    const sites = [...views.values()].filter((v) => (v.wid || 0) === winActive && siteTakes(v));
    canvas.style.pointerEvents = sites.length ? 'none' : '';
    if (sites.length && !under) {
      under = doc.createElement('div');
      under.style.cssText = 'position:fixed;inset:0;z-index:0;touch-action:none';
      doc.body.insertBefore(under, layer());
      takePresses(under);
    }
    const covers = sites.flatMap((v) => v.covers);
    while (coverBoxes.length > covers.length) coverBoxes.pop().remove();
    covers.forEach(([x0, y0, x1, y1], i) => {
      if (!coverBoxes[i]) {
        coverBoxes[i] = doc.createElement('div');
        coverBoxes[i].style.cssText = 'position:fixed;z-index:2;touch-action:none';
        doc.body.appendChild(coverBoxes[i]);
        takePresses(coverBoxes[i]);
      }
      Object.assign(coverBoxes[i].style, { left: x0 + 'px', top: y0 + 'px', width: x1 - x0 + 'px', height: y1 - y0 + 'px' });
    });
  };
  // the presses round the sites of window `wid` placed again (where it is open)
  const siteFor = (wid) => { if (wid === 0 || liveSlot(wid)) inWin(wid, placeSitePresses); };
  H.viewSiteNext = (id) => {
    const v = views.get(id);
    return v && v.said && v.said.length ? v.said.shift() : '';
  };
  H.viewSiteBody = (id, req) => {
    const v = views.get(id);
    const body = v && v.bodies && v.bodies.get(req);
    if (body) v.bodies.delete(req);
    return body || new Uint8Array(0);
  };
  H.viewSiteHead = (id, req, status, headers) => {
    const v = views.get(id);
    if (!v || v.kind !== 3) return;
    sitePost(v, { id: req, head: { status, headers: JSON.parse(headers) } });
  };
  H.viewSiteChunk = (id, req, data) => {
    const v = views.get(id);
    if (!v || v.kind !== 3) return;
    const chunk = new Uint8Array(data);
    sitePost(v, { id: req, chunk }, [chunk.buffer]);
  };
  H.viewSiteEnd = (id, req, error) => {
    const v = views.get(id);
    if (!v || v.kind !== 3) return;
    sitePost(v, error ? { id: req, error } : { id: req, end: true });
  };
  // how a site stands, once as it changes
  H.viewSiteState = (id) => {
    const v = views.get(id);
    if (!v || v.kind !== 3 || v.atSaid === v.at) return '';
    v.atSaid = v.at;
    return JSON.stringify(v.at);
  };
  H.viewSiteLoad = (id, path) => {
    const v = views.get(id);
    if (v && v.kind === 3) siteNav(v, 'go', path);
  };
  H.viewTell = (id, what, text) => {
    const v = views.get(id);
    // raised over all the others (the app paints it after them): by z-index, as moving an iframe in the page loads it
    // again
    if (v && what === 5) { v.clip.style.zIndex = String(++nextZ); return; }
    if (v && v.kind === 3) {
      if (what === 2) {
        v.touch = text.split(' ')[0];
        v.el.style.pointerEvents = v.touch === 'through' ? 'none' : 'auto';
        siteFor(v.wid || 0);
      }
      else if (what === 4) {
        const n = text ? text.split(' ').map(Number) : [];
        v.covers = [];
        for (let i = 0; i + 3 < n.length; i += 4) v.covers.push(n.slice(i, i + 4));
        siteFor(v.wid || 0);
      } else if (what === 7) {
        // what a socket did, on to the frame (NativeView::tell_frame): [sid, what, …]
        const [sid, kind, a, b, c] = JSON.parse(text);
        if (kind === 'open') sitePost(v, { type: 'socket-open', sid, protocol: a });
        else if (kind === 'text') sitePost(v, { type: 'socket-message', sid, text: a });
        else if (kind === 'binary') { const binary = fromBase64(a); sitePost(v, { type: 'socket-message', sid, binary }, [binary.buffer]); }
        else if (kind === 'close') sitePost(v, { type: 'socket-close', sid, code: a, reason: b, failed: c });
      }
      return;
    }
    if (!v || v.kind !== 2) return;
    if (what === 1) { v.scripts.push(text); runScripts(v); }
  };
  // a view ready (or failed) told to the app, once; not once it is closed (the app let it go)
  const ready = (id, v, state) => {
    if (v.ready || !views.has(id)) return;
    v.ready = true;
    tell(OUTSIDE_VIEW, id, state);
  };
  H.viewOpen = (kind, arg) => {
    if (kind !== 1 && kind !== 2 && !(kind === 3 && H.siteFrame)) return 0;
    const id = ++nextView;
    // (in the window in place: its own document's, under its canvas)
    const mk = (tag) => (doc || document).createElement(tag);
    const clip = mk('div');
    clip.style.cssText = 'position:absolute;overflow:hidden;display:none;background:' + (kind === 1 ? '#000' : '#fff');
    const v = { kind, clip, wid: winActive, state: 0, reads: [], waiting: new Map(), nextRead: 0, parts: [], have: 0, total: -1 };
    info(v);
    if (kind === 1) {
      const el = mk('video');
      el.playsInline = true;
      el.style.cssText = 'position:absolute;object-fit:fill';
      el.addEventListener('loadedmetadata', () => {
        v.state = 1;
        v.info[0] = el.duration * 1000;
        v.info[3] = el.videoWidth;
        v.info[4] = el.videoHeight;
        stood(id);
      });
      // its first frame can be shown: ready for the app
      el.addEventListener('loadeddata', () => { v.info[6] = 1; ready(id, v, 1); stood(id); });
      el.addEventListener('error', () => {
        if (v.state < 0) return; // a failed read was already reported, before the media element heard of it
        // A source or decode error can mean either an unsupported format or a damaged file.
        v.state = el.error?.code === 4 || el.error?.code === 3 ? -4 : -1;
        ready(id, v, -1);
        stood(id);
      });
      // how it stands told as it changes: as it plays, waits, stops, jumps, has more; and each frame of its picture
      // shown as it plays (a sound's: each of the page's frames)
      for (const e of ['play', 'playing', 'waiting', 'pause', 'stalled', 'canplay', 'ended', 'seeking',
        'progress', 'durationchange', 'ratechange']) el.addEventListener(e, () => stood(id));
      el.addEventListener('seeked', () => {
        if (v.pendingSeek !== null) {
          const p = v.pendingSeek;
          v.pendingSeek = null;
          const t = Math.max(0, p.ms / 1000);
          if (p.near && typeof el.fastSeek === 'function') el.fastSeek(t);
          else el.currentTime = t;
        }
        stood(id);
      });
      let going = false;
      const frame = () => {
        stood(id);
        if (!el.paused && !el.ended && views.has(id)) go();
        else going = false;
      };
      const go = () => (el.videoWidth && el.requestVideoFrameCallback ? el.requestVideoFrameCallback(frame)
        : requestAnimationFrame(frame));
      el.addEventListener('playing', () => { if (!going) { going = true; go(); } });
      v.el = el;
      v.type = arg;
      v.scrubbing = false;
      v.pendingSeek = null;
      // the whole file read through the app, a part at a time, then played
      // (the player waits on the app's bytes now: not the host's work until they come)
      v.ask = (offset) => {
        const r = { id: ++v.nextRead, offset, length: 4 << 20 };
        v.reads.push(r);
        v.waiting.set(r.id, r);
        if (!v.ready) tell(OUTSIDE_VIEW, id, 0);
        H.requestFrame();
      };
      v.ask(0);
    } else if (kind === 3) {
      const el = mk('iframe');
      el.style.cssText = 'position:absolute;border:0;background:#fff;pointer-events:auto;transform-origin:0 0';
      const frame = new URL(H.siteFrame, location.href);
      v.origin = frame.origin;
      v.nonce = crypto.randomUUID();
      v.said = [];
      v.bodies = new Map();
      v.covers = [];
      v.scale = 1;
      v.at = { path: arg, back: false, forward: false, loading: true, title: '', cookies: false, frame: true };
      frame.searchParams.set('n', v.nonce);
      frame.searchParams.set('path', arg);
      el.src = frame.href;
      el.addEventListener('load', () => { v.state = 1; v.info[6] = 1; ready(id, v, 1); stood(id); });
      el.addEventListener('error', () => { v.state = -1; ready(id, v, -1); stood(id); });
      v.el = el;
    } else {
      const el = mk('iframe');
      el.setAttribute('sandbox', 'allow-scripts');
      el.style.cssText = 'position:absolute;border:0;background:#fff';
      // loaded: what a screenshot shows of it is the page itself (in the page's own picture)
      el.addEventListener('load', () => { v.state = 1; v.info[6] = 1; ready(id, v, 1); v.there = true; runScripts(v); stood(id); });
      el.addEventListener('error', () => { v.state = -1; ready(id, v, -1); stood(id); });
      // its way to the app (mbuiHost.post, as the other hosts' pages have it) and the app's scripts run in it: messages
      // between this window and the frame's own, each side taking only the other's
      v.said = [];
      v.scripts = [];
      v.there = false;
      el.srcdoc = PAGE_BRIDGE + arg;
      v.info[5] = new TextEncoder().encode(arg).length;
      v.el = el;
    }
    clip.appendChild(v.el);
    clip.style.zIndex = String(++nextZ);
    // (the layer and document it is in: viewPlace moves it where another window places it)
    v.layer = layer();
    v.doc = doc;
    v.layer.appendChild(clip);
    views.set(id, v);
    return id;
  };
  H.viewPlace = (id, x, y, w, h, cx0, cy0, cx1, cy1, shown, r0 = 0, r1 = 0, r2 = 0, r3 = 0) => {
    const v = views.get(id);
    if (!v) return;
    // Placed in another window than it was (a view the app keeps, taken from one window to another: ui's native.mbt):
    // moved to this one's layer. Into another document its frame loads again: a site's from where it was (its port
    // made again as it says it is ready), a page's scripts run again once it is there.
    const here = layer();
    if (v.layer !== here) {
      const from = v.wid || 0;
      v.wid = winActive;
      v.layer = here;
      if (v.doc !== doc) {
        v.doc = doc;
        if (v.kind === 3) {
          if (v.port) { v.port.close(); v.port = null; }
          try {
            const u = new URL(v.el.src, location.href);
            u.searchParams.set('path', (v.at && v.at.path) || '/');
            v.el.src = u.href;
          } catch (e) { /* its address as it was */ }
        } else if (v.kind === 2) v.there = false;
      }
      here.appendChild(v.clip);
      if (from !== winActive) siteFor(from);
    }
    Object.assign(v.clip.style, { left: cx0 + 'px', top: cy0 + 'px', width: Math.max(0, cx1 - cx0) + 'px',
      height: Math.max(0, cy1 - cy0) + 'px', display: shown ? 'block' : 'none' });
    // (its corners round, each its own (top left, then round it), as the hole the app paints for it: the element cut
    // to them, what it shows with it)
    const rs = [r0, r1, r2, r3].map((k) => Math.max(0, k)), round = rs.some((k) => k > 0);
    // (a site laid out at its rect over its scale and drawn at it: view_control 8)
    const k = v.scale || 1;
    Object.assign(v.el.style, { left: x - cx0 + 'px', top: y - cy0 + 'px', width: w / k + 'px', height: h / k + 'px',
      borderRadius: round ? rs.map((r) => r / k + 'px').join(' ') : '', overflow: round ? 'hidden' : '' });
    if (v.kind === 3) {
      v.el.style.transform = k === 1 ? '' : `scale(${k})`;
      v.seen = shown && cx1 > cx0 && cy1 > cy0 ? [cx0, cy0, cx1, cy1] : null;
      v.placed = [x, y, w, h, cx0, cy0, cx1, cy1, shown, r0, r1, r2, r3];
      placeSitePresses();
    }
    // where it is now, in device pixels, as the page laid it out (scripts/host_contract.sh web views: against VIEWTOLD)
    if (shown && H.log) {
      const d = dpr || 1, r = v.el.getBoundingClientRect(), k = v.clip.getBoundingClientRect();
      const cv = canvas || (doc || document).querySelector('canvas');
      const o = cv ? cv.getBoundingClientRect() : { left: 0, top: 0 };
      const f = (n) => n.toFixed(4);
      // (its corners as the page has them, each)
      const cs = (hostWin.getComputedStyle ? hostWin : window).getComputedStyle(v.el);
      const said = ['borderTopLeftRadius', 'borderTopRightRadius', 'borderBottomRightRadius', 'borderBottomLeftRadius']
        .map((k) => parseFloat(cs[k]) || 0);
      H.log(`VIEWAT ${id} ${f((r.left - o.left) * d)} ${f((r.top - o.top) * d)} ${f(r.width * d)} ${f(r.height * d)} ` +
        `${f((k.left - o.left) * d)} ${f((k.top - o.top) * d)} ${f((k.right - o.left) * d)} ${f((k.bottom - o.top) * d)} ` +
        `${f(Math.max(...said) * d)} ${said.map((k) => f(k * d)).join(' ')}`);
    }
  };
  H.viewClose = (id) => {
    const v = views.get(id);
    if (!v) return;
    views.delete(id);
    if (v.kind === 1) { v.el.pause(); if (v.url) URL.revokeObjectURL(v.url); }
    if (v.kind === 3 && v.port) v.port.close();
    v.clip.remove();
    siteFor(v.wid || 0);
  };
  H.viewControl = (id, op, value) => {
    const v = views.get(id);
    if (v && v.kind === 3) {
      if (op === 5) siteNav(v, 'back');
      else if (op === 6) siteNav(v, 'forward');
      else if (op === 7) siteNav(v, 'reload');
      else if (op === 8 && value > 0 && value !== v.scale) {
        v.scale = value;
        if (v.placed) H.viewPlace(id, ...v.placed);
      }
      return;
    }
    if (!v || v.kind !== 1) return;
    const doSeek = (ms, near) => {
      const t = Math.max(0, ms / 1000);
      if (near && typeof v.el.fastSeek === 'function') v.el.fastSeek(t);
      else v.el.currentTime = t;
    };
    if (op === 1) { v.pendingSeek = null; v.el.play().catch(() => {}); }
    else if (op === 2) { v.pendingSeek = null; v.el.pause(); }
    else if (op === 9) {
      v.scrubbing = value > 0;
      if (!v.scrubbing && v.pendingSeek !== null && !v.el.seeking) {
        const p = v.pendingSeek;
        v.pendingSeek = null;
        doSeek(p.ms, p.near);
      }
    }
    else if (op === 3 || op === 11) {
      const near = op === 11;
      // while a finger is on it every seek waits for the one going, the last asked taken up once it is there: one
      // asked while another is going restarts the browser's from its key frame, and a finger never still would show
      // none (#7875 sent a finger's seeks exact)
      if (v.scrubbing && v.el.seeking) {
        v.pendingSeek = { ms: value, near };
      } else {
        v.pendingSeek = null;
        doSeek(value, near);
      }
    }
    else if (op === 4) v.el.playbackRate = value;
    // how loud, 0 to 1 (NativeView::volume)
    else if (op === 10) v.el.volume = Math.max(0, Math.min(1, value));
    // a frame grabbed (op 21, or the one shown: 22): this host grabs none; failed, said so (viewText's 2: "-1", once)
    else if (op === 21 || op === 22) {
      v.grab = '-1';
      tell(OUTSIDE_GRAB, id, -1);
    }
  };
  H.viewText = (id, what) => {
    const v = views.get(id);
    if (!v || what !== 2 || v.grab === undefined) return '';
    const g = v.grab;
    v.grab = undefined;
    return g;
  };
  H.viewInfo = (id, out) => {
    const v = views.get(id);
    if (!v) return -1;
    if (v.kind === 1) {
      v.info[1] = v.el.currentTime * 1000;
      v.info[2] = v.el.paused || v.el.ended ? 0 : 1;
      // waiting for what it needs to go on playing
      v.info[7] = v.info[2] && v.el.readyState < 3 ? 1 : 0;
      // how far on it has what it needs: the end of the buffered range the playhead is in; whether it played to its end
      const b = v.el.buffered, t = v.el.currentTime;
      v.info[8] = 0;
      for (let i = 0; i < b.length; i++) if (b.start(i) <= t + 0.001) v.info[8] = Math.max(v.info[8], b.end(i) * 1000);
      v.info[9] = v.el.ended ? 1 : 0;
    }
    for (let i = 0; i < 10; i++) out[i] = v.info[i] || 0;
    return v.state;
  };
  // How view `id` stands (viewInfo) may have changed: the app told where it did (OUTSIDE_STOOD, src/ui/hostcall.mbt's
  // outside_stood), which reads it then, not each frame. Told only where something did.
  const stoodNow = new Float64Array(10);
  function stood(id) {
    const v = views.get(id);
    if (!v) return;
    const st = H.viewInfo(id, stoodNow);
    if (v.stoodSaid && st === v.stoodState && v.stoodSaid.every((x, i) => x === stoodNow[i])) return;
    v.stoodState = st;
    v.stoodSaid = Array.from(stoodNow);
    tell(OUTSIDE_STOOD, id, 0);
  }
  H.viewReadNext = (id, out) => {
    const v = views.get(id);
    const r = v && v.reads.shift();
    if (!r) return 0;
    out[0] = r.offset;
    out[1] = r.length;
    return r.id;
  };
  // a read's bytes as they come (more: more of it comes), the next read asked after its last answer
  H.viewReadAnswer = (id, req, data, total, more) => {
    const v = views.get(id);
    const r = v && v.waiting.get(req);
    if (!r) return;
    if (!more || total === -2) v.waiting.delete(req);
    if (total === -2) { v.state = -1; ready(id, v, -1); stood(id); return; }
    const part = new Uint8Array(data);
    v.parts.push(part);
    v.have += part.length;
    r.got = (r.got || 0) + part.length;
    v.info[5] = v.have;
    stood(id);
    if (total >= 0) v.total = total;
    if (more) return;
    if (r.got > 0 && (v.total < 0 || v.have < v.total)) return v.ask(v.have);
    v.url = URL.createObjectURL(new Blob(v.parts, { type: v.type }));
    // (the Blob holds the bytes now: the parts let go of, not kept twice)
    v.parts.length = 0;
    v.el.src = v.url;
  };

  // ---- images ----
  // Decoded by the browser off the main thread (createImageBitmap, which
  // also applies the EXIF orientation), scaled to the size asked for, kept
  // as premultiplied textures.
  const images = new Map();
  let nextImage = 0;
  async function decodeImage(id, blob, maxPx) {
    const im = images.get(id);
    try {
      let bmp = await createImageBitmap(blob);
      const ow = bmp.width, oh = bmp.height;
      const k = Math.min(1, maxPx / Math.max(ow, oh));
      if (k < 1) {
        const small = await createImageBitmap(bmp, {
          resizeWidth: Math.max(1, Math.round(ow * k)),
          resizeHeight: Math.max(1, Math.round(oh * k)),
          resizeQuality: 'high',
        });
        bmp.close();
        bmp = small;
      }
      if (!images.has(id)) return bmp.close();
      // (the page's canvas's: a window beside it takes a copy of its own as it first draws it, slotTex)
      const gl = mainGl();
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, bmp);
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      Object.assign(im, { state: 1, tex, w: bmp.width, h: bmp.height, ow, oh, blob, maxPx });
      bmp.close();
    } catch (e) {
      if (!images.has(id)) return;
      im.state = -1;
    }
    tell(OUTSIDE_IMAGE, id, im.state);
    H.requestFrame();
  }
  H.imageLoad = (src, maxPx) => {
    const id = ++nextImage;
    images.set(id, { state: 0 });
    fetch(src).then((r) => (r.ok ? r.blob() : Promise.reject(r.status)))
      .then((b) => decodeImage(id, b, maxPx))
      .catch(() => {
        const im = images.get(id);
        if (!im || im.state !== 0) return;
        im.state = -1;
        tell(OUTSIDE_IMAGE, id, -1);
        H.requestFrame();
      });
    return id;
  };
  H.imageLoadBytes = (bytes, maxPx) => {
    const id = ++nextImage;
    images.set(id, { state: 0 });
    decodeImage(id, new Blob([bytes]), maxPx);
    return id;
  };
  H.imageInfo = (id, out) => {
    const im = images.get(id);
    if (!im) return -1;
    if (im.state === 1) {
      out[0] = im.w; out[1] = im.h; out[2] = im.ow; out[3] = im.oh;
    }
    return im.state;
  };
  // a ready image's pixels read back from its texture through a framebuffer of its own (premultiplied RGBA, rows from
  // the top as it was uploaded)
  H.imagePixels = (id, out) => {
    const im = images.get(id);
    if (!im || im.state !== 1 || !im.tex || out.length < im.w * im.h * 4) return 0;
    const gl = mainGl();
    const was = gl.getParameter(gl.FRAMEBUFFER_BINDING);
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, im.tex, 0);
    let ok = gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE;
    if (ok) {
      const px = new Uint8Array(im.w * im.h * 4);
      gl.readPixels(0, 0, im.w, im.h, gl.RGBA, gl.UNSIGNED_BYTE, px);
      for (let i = 0; i < px.length; i++) out[i] = px[i];
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, was);
    gl.deleteFramebuffer(fb);
    return ok ? 1 : 0;
  };
  H.imageFree = (id) => {
    const im = images.get(id);
    if (im && im.tex) mainGl().deleteTexture(im.tex);
    images.delete(id);
    slotsForget(id);
  };

  // ---- streams (src/hostapi/stream.mbt) ----
  // A picture decoded frame by frame: H.264 by WebCodecs' VideoDecoder where the browser has one (AVCC as it is, the
  // avcC its description), JPEG by createImageBitmap. Each frame decoded is kept until the app shows it ("f TS W H",
  // then streamShow: uploaded into the stream's texture), or a later one; frames let go ("d TS": no decoder or not past
  // a key frame, the older of two it holds, those inside as it starts anew, a JPEG that does not decode) and the
  // decoder broken ("b": an error) told the same way, each asking for a frame.
  const STREAM_TEX = 4194304;
  // Adaptive jitter-absorbing presentation clock and four-state catch-up pacer for H.264 streams.
  const CLOCK_WINDOW_MS = 5000;
  const JITTER_WINDOW_MS = 2000;
  const JITTER_QUANTILE = 0.95;
  const MAX_HOLD_MS = 100;
  const HOLD_DECAY = 0.05;
  const CLOCK_JUMP_MS = 500;
  const streams = new Map();
  let nextStream = 0;
  // (a VideoDecoder that takes no H.264, as Chromium's own build has: asked once as the page loads, the app's first
  // frame held until it is answered, so that h264_here is the same from the app's start). Asked of what a station
  // sends: High (its helper's VideoToolbox and Windows' Media Foundation ask for it first, AutoLevel: ScreenView.swift,
  // encode.rs), so that a browser whose decoder takes Baseline alone shows no stream it cannot decode, at a 1920 × 1080
  // view's level, 4.2 (a viewer's maxWidth, Android's ScreenSession).
  let hasVideoDecoder = false;
  const h264Asked = typeof VideoDecoder === 'undefined'
    ? Promise.resolve()
    : VideoDecoder.isConfigSupported({ codec: 'avc1.64002A', codedWidth: 1920, codedHeight: 1080, optimizeForLatency: true })
      .then((r) => { hasVideoDecoder = !!r.supported; }, () => {});
  H.h264Here = () => (hasVideoDecoder ? 1 : 0);
  const num = (v) => String(v);
  function say(s, e) {
    if (s.closed) return;
    s.events.push(e);
    H.requestFrame();
  }
  function observeArrival(s, ts, arrivedMs) {
    const offset = arrivedMs - ts / 1000;
    const last = s.samples.length ? s.samples[s.samples.length - 1] : null;
    if (last && Math.abs(offset - last.offset) > CLOCK_JUMP_MS) {
      s.samples = [];
      s.lows = [];
      s.holdMs = 0;
    }
    const previous = s.samples.length ? s.samples[s.samples.length - 1].time : arrivedMs;
    const sample = { time: arrivedMs, offset, late: 0 };
    s.samples.push(sample);
    while (s.lows.length && s.lows[s.lows.length - 1].offset >= offset) s.lows.pop();
    s.lows.push(sample);
    while (s.samples[0].time < arrivedMs - CLOCK_WINDOW_MS) {
      if (s.lows[0] === s.samples[0]) s.lows.shift();
      s.samples.shift();
    }
    const base = s.lows[0].offset;
    sample.late = offset - base;
    const recent = [];
    for (let i = s.samples.length - 1; i >= 0 && s.samples[i].time >= arrivedMs - JITTER_WINDOW_MS; i--) {
      recent.push(s.samples[i].late);
    }
    recent.sort((a, b) => a - b);
    const target = Math.min(MAX_HOLD_MS, recent[Math.floor(JITTER_QUANTILE * (recent.length - 1))]);
    s.holdMs = target >= s.holdMs ? target : Math.max(target, s.holdMs - (arrivedMs - previous) * HOLD_DECAY);
    return base;
  }
  function isDue(s, item, now) {
    return item.ts / 1000 + item.base + s.holdMs <= now + 1e-6;
  }
  function dueCount(s, now) {
    let count = 0;
    while (count < s.paced.length && isDue(s, s.paced[count], now)) count++;
    return count;
  }
  function waitUsOf(item, now) {
    const ms = now - item.arrived;
    return ms > 0 ? Math.min(0xffff_ffff, Math.round(ms * 1000)) : 0;
  }
  function presenterPhase(due, draws, backlogMs, sinceCatchUpMs, headOverstayMs) {
    if (due <= 2) return 'idle';
    if (due > 12 || headOverstayMs > 200) return 'overrun';
    if (due - draws <= 2) return 'idle';
    return backlogMs < 500 || sinceCatchUpMs < 250 ? 'backlog' : 'catchUp';
  }
  function trimDecoded(s, now, draws = 0) {
    let due = dueCount(s, now);
    const phase = presenterPhase(
      due, draws, now - (s.backlogSince ?? now), now - s.lastCatchUp,
      s.paced.length ? now - s.paced[0].arrived - s.holdMs : 0,
    );
    if (phase === 'idle') {
      s.backlogSince = null;
      return;
    }
    if (s.backlogSince === null) s.backlogSince = now;
    if (phase === 'backlog') return;
    do {
      const dropped = s.paced.shift();
      dropped.frame.close();
      due--;
      const waitUs = waitUsOf(dropped, now);
      say(s, waitUs > 0 ? `d ${num(dropped.ts)} ${waitUs}` : `d ${num(dropped.ts)}`);
    } while (phase === 'overrun' && due > 2);
    if (due <= 2) s.backlogSince = null;
    if (phase === 'catchUp') s.lastCatchUp = now;
  }
  function emitFrame(s, item, now) {
    s.decoded.push({ ts: item.ts, frame: item.frame, w: item.w, h: item.h });
    s.drawnThisFrame = true;
    const waitUs = waitUsOf(item, now);
    say(s, waitUs > 0 ? `f ${num(item.ts)} ${item.w} ${item.h} ${waitUs}` : `f ${num(item.ts)} ${item.w} ${item.h}`);
  }
  function schedulePresent(s) {
    if (!s.paceRaf && !s.closed) s.paceRaf = requestAnimationFrame(() => present(s));
  }
  function present(s) {
    s.paceRaf = 0;
    if (s.closed) return;
    s.drawnThisFrame = false;
    const now = performance.now();
    trimDecoded(s, now, 1);
    let drew = false;
    if (s.paced.length && isDue(s, s.paced[0], now)) {
      emitFrame(s, s.paced.shift(), now);
      drew = true;
    }
    if (drew || s.paced.length) schedulePresent(s);
  }
  function presentDecoded(s, item) {
    const now = performance.now();
    const immediate = !s.paced.length && !s.drawnThisFrame;
    s.paced.push(item);
    trimDecoded(s, now);
    if (immediate && s.paced.length && isDue(s, s.paced[0], now)) emitFrame(s, s.paced.shift(), now);
    if (s.paced.length || s.drawnThisFrame) schedulePresent(s);
  }
  function resetPace(s) {
    if (s.paceRaf && typeof cancelAnimationFrame === 'function') cancelAnimationFrame(s.paceRaf);
    s.paceRaf = 0;
    s.drawnThisFrame = false;
    s.backlogSince = null;
    s.lastCatchUp = -Infinity;
    s.samples = [];
    s.lows = [];
    s.holdMs = 0;
    s.arrivals.clear();
    for (const f of s.paced) f.frame.close();
    s.paced = [];
  }
  // the decoder for the config there is (none without one): whether there is one now
  function startDecoder(s) {
    stopDecoder(s);
    if (!s.config || s.closed || !hasVideoDecoder) return false;
    const gen = ++s.gen;
    try {
      const d = new VideoDecoder({
        output: (frame) => {
          if (gen !== s.gen || s.closed) return frame.close();
          const ts = frame.timestamp;
          while (s.inside.length && s.inside[0] <= ts) s.inside.shift();
          const meta = s.arrivals.get(ts);
          if (meta) s.arrivals.delete(ts);
          for (const k of s.arrivals.keys()) {
            if (k < ts) s.arrivals.delete(k);
            else break;
          }
          const now = performance.now();
          presentDecoded(s, {
            ts,
            frame,
            w: frame.displayWidth,
            h: frame.displayHeight,
            arrived: meta ? meta.arrived : now,
            base: meta ? meta.base : now - ts / 1000,
          });
        },
        error: (e) => {
          if (gen !== s.gen) return;
          console.warn('stream ' + s.id + ': the H.264 decoder failed', e);
          // anew, from the next key frame
          if (startDecoder(s)) say(s, 'b');
        },
      });
      d.configure(s.config);
      s.decoder = d;
      s.needKey = true;
      return true;
    } catch (e) {
      console.warn('stream ' + s.id + ': no H.264 decoder', e);
      return false;
    }
  }
  function stopDecoder(s) {
    if (s.decoder) {
      try { s.decoder.close(); } catch (e) {}
      s.decoder = null;
    }
    s.gen++;
    let maxDropped = -Infinity;
    for (const t of s.inside) if (t > maxDropped) maxDropped = t;
    for (const f of s.paced) if (f.ts > maxDropped) maxDropped = f.ts;
    if (maxDropped > -Infinity) say(s, 'd ' + num(maxDropped));
    s.inside = [];
    resetPace(s);
    s.needKey = true;
  }
  H.streamOpen = () => {
    const id = ++nextStream;
    streams.set(id, { id, events: [], decoded: [], inside: [], paced: [], arrivals: new Map(), samples: [], lows: [],
      holdMs: 0, backlogSince: null, lastCatchUp: -Infinity, paceRaf: 0, drawnThisFrame: false, gen: 0, needKey: true,
      decoder: null, config: null, tex: null, shown: null, closed: false, jpegs: Promise.resolve() });
    return id;
  };
  H.streamH264 = (id, avcc, w, h) => {
    const s = streams.get(id);
    if (!s) return;
    const a = new Uint8Array(avcc);
    const hex = (b) => b.toString(16).padStart(2, '0');
    s.config = a.length >= 4 && a[0] === 1
      ? { codec: 'avc1.' + hex(a[1]) + hex(a[2]) + hex(a[3]), description: a.slice(), codedWidth: w, codedHeight: h,
          optimizeForLatency: true }
      : null;
    // the sender's next frame after a config is a key frame
    if (!s.config) stopDecoder(s);
    else startDecoder(s);
  };
  H.streamFrame = (id, data, key, ts) => {
    const s = streams.get(id);
    if (!s) return;
    if (!s.decoder || (s.needKey && !key)) return say(s, 'd ' + num(ts));
    s.needKey = false;
    const arrived = performance.now();
    const base = observeArrival(s, ts, arrived);
    s.arrivals.set(ts, { arrived, base });
    try {
      s.inside.push(ts);
      s.decoder.decode(new EncodedVideoChunk({ type: key ? 'key' : 'delta', timestamp: ts, data: new Uint8Array(data) }));
    } catch (e) {
      // not a frame it takes: the next key frame asked for
      s.inside = s.inside.filter((t) => t !== ts);
      s.arrivals.delete(ts);
      say(s, 'd ' + num(ts));
      if (startDecoder(s)) say(s, 'b');
      return;
    }
    // a decoder that holds frames back would wait for more while the sender waits: with two inside, the older taken
    if (s.inside.length >= 2) say(s, 'd ' + num(s.inside.shift()));
  };
  H.streamJpeg = (id, data, ts) => {
    const s = streams.get(id);
    if (!s) return;
    const blob = new Blob([new Uint8Array(data)], { type: 'image/jpeg' });
    // (in the order they came, each decoded off the page's thread)
    s.jpegs = s.jpegs.then(() => createImageBitmap(blob).then((bmp) => {
      if (s.closed) return bmp.close();
      s.decoded.push({ ts, frame: bmp, w: bmp.width, h: bmp.height });
      say(s, `f ${num(ts)} ${bmp.width} ${bmp.height}`);
    }, () => say(s, 'd ' + num(ts))));
  };
  H.streamNext = (id) => {
    const s = streams.get(id);
    return s && s.events.length ? s.events.shift() : '';
  };
  // The last shown frame stays until replaced or closed, so a lost GL texture can be made again even if the sender
  // has stopped sending frames. This is one ImageBitmap or VideoFrame per open stream.
  function uploadStream(s) {
    const gl = mainGl();
    if (!s.shown || gl.isContextLost()) return;
    if (!s.tex) {
      s.tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, s.tex);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    gl.bindTexture(gl.TEXTURE_2D, s.tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, s.shown);
  }
  H.streamShow = (id, ts) => {
    const s = streams.get(id);
    if (!s) return;
    const at = s.decoded.findIndex((f) => f.ts === ts);
    if (at < 0) return;
    const f = s.decoded[at];
    // it, and those decoded before it passed over
    s.decoded = s.decoded.filter((g) => {
      if (g.ts > ts) return true;
      if (g !== f) g.frame.close();
      return false;
    });
    if (s.shown) s.shown.close();
    s.shown = f.frame;
    // (what a window beside the page holds of it uploaded again as it next draws it: slotTex)
    s.shownGen = (s.shownGen || 0) + 1;
    uploadStream(s);
  };
  H.streamClose = (id) => {
    const s = streams.get(id);
    if (!s) return;
    stopDecoder(s);
    s.closed = true;
    for (const f of s.decoded) f.frame.close();
    s.decoded = [];
    if (s.shown) s.shown.close();
    if (s.tex) mainGl().deleteTexture(s.tex);
    streams.delete(id);
    slotsForget(STREAM_TEX + id);
  };

  // ---- text ----
  const seg = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  const mctx = document.createElement('canvas').getContext('2d');
  // widths the canvas measured (width), at most ADV_MOST of them: past it forgotten all at once and measured again
  const ADV_MOST = 16384;
  const advCache = new Map();
  const keys = new Map();
  const entries = [];
  let generation = 0;
  // the glyph drawn last (H.glyph), its picture until it is put in the atlas (H.glyphPut)
  let held = null;
  // where a glyph is drawn to be read back: one canvas, grown and never shrunk, each glyph drawn in its top left
  // corner and only that much of it cleared and read. Sizing it to each glyph (as till 2026-11-17) gave the canvas a
  // new backing store per glyph: on a phone's CPU an issue's page of Han opened in one 300 ms frame, two thirds of it
  // that (clearRect 138 ms, getImageData 36 ms of a 4x slowed Chrome).
  const rc = document.createElement('canvas');
  const rctx = rc.getContext('2d', { willReadFrequently: true });
  rc.width = rc.height = 0;
  // a canvas's font set only as it changes: the setter parses the CSS font each time, set or not (mctxFont, rctxFont:
  // what each was last set to; forgotten as a face comes or goes, so the new one is found)
  let mctxFont = '', rctxFont = '';
  const setMFont = (f) => { if (f !== mctxFont) { mctx.font = f; mctxFont = f; } };
  // the faces given (faceAdd, style.mbt), loaded: each a family of its own ahead of the place's own
  const faces = new Set();
  // the face a style is set in: the one it names; else code's (style bit 2), what people wrote's (bit 16), the app's
  // words' (not the serif face's); 0 none
  const faceOf = (style) => {
    const f = (style >> 8) & 15;
    if (f) return faces.has(f) ? f : 0;
    if (style & 2) return faces.has(3) ? 3 : 0;
    if (style & 16 && faces.has(2)) return 2;
    if (style & 4) return 0;
    return faces.has(1) ? 1 : 0;
  };
  // style: 1 slanted, 2 the code face; 64 a CJK face's marks narrow among Latin letters (style.mbt
  // style_proportional): the face loaded again with pwid (a canvas has no font-feature-settings), once asked for
  const font = (size, weight, style) => {
    const own = style & 2 ? MONO : style & 4 ? SERIF : FAMILY;
    const f = faceOf(style);
    const narrow = f && style & 64 && narrowFace(f) ? `"mbface${f}n", ` : '';
    return `${style & 1 ? 'italic ' : ''}${weight} ${size}px ${f ? `${narrow}"mbface${f}", ${own}` : own}`;
  };
  // each face's files as given (a URL or bytes, its weight), and which faces are loaded with pwid (true) or being
  const faceFiles = new Map();
  const narrowFaces = new Map();
  const narrowFace = (face) => {
    const had = narrowFaces.get(face);
    if (had !== undefined) return had;
    narrowFaces.set(face, false);
    const cjk = cjkFiles.get(face);
    const files = [...(faceFiles.get(face) || []), ...(cjk || [])];
    Promise.all(files.map(([src, weight, desc]) => {
      const d = desc ? { ...desc } : faceDescriptors(face, weight);
      d.featureSettings = d.featureSettings ? `${d.featureSettings}, "pwid" 1` : '"pwid" 1';
      const ff = new FontFace(`mbface${face}n`, src, d);
      // (a CJK companion's (setCjkFace) kept with it, gone as it goes; one of its files the system has not: the rest
      // narrow as they are)
      return ff.load().then(() => {
        if (desc) {
          if (cjkFiles.get(face) !== cjk) return;
          cjkLoaded.get(face).push(ff);
        }
        document.fonts.add(ff);
      }, () => {});
    })).then(() => {
      if (narrowFaces.get(face) !== false) return;
      narrowFaces.set(face, true);
      textChanged();
      H.requestFrame();
    }, () => {});
    return false;
  };
  const faceFile = (face, src, weight) => {
    if (!faceFiles.has(face)) faceFiles.set(face, []);
    faceFiles.get(face).push([src, weight]);
  };
  // what was shaped and drawn before a face or the scale changed, forgotten (MoonBit drops its glyphs as the
  // generation moves on)
  // (and the glyphs' keys with what they were of, as MoonBit drops what it shaped by them: not here, which a face going
  // can reach in a frame whose text still holds keys, but before the next frame starts, textSweep)
  let keysStale = false;
  // (whether the generation was read since it last moved on: MoonBit may have shaped by the keys under it, textSweep)
  let generationRead = false;
  const textChanged = () => {
    mctxFont = rctxFont = '';
    advCache.clear();
    held = null;
    generation++;
    generationRead = false;
    keysStale = true;
  };
  // Between frames (each window's frame starts with it, resize): the glyphs' keys forgotten as text changed, or as
  // there came to be more than KEYS_MOST of them (each a glyph of a size, weight and style ever shaped: a page left
  // open on changing text grows them without end), the generation moved on so MoonBit shapes what it shows again
  // (text.mbt text_arrive: the generation read as each frame starts). It moves on again as the keys are forgotten where
  // it was read since it moved on as the text changed: a face cleared in a frame (faceClear) moves it on there, MoonBit
  // reads it at once (faces.mbt words_forgotten) and shapes again by the keys still here, which would be kept with that
  // generation and drawn next frame as other glyphs; unread (the scale changed as the frame starts), once is enough.
  const KEYS_MOST = 65536;
  function textSweep() {
    if (inFrame) return;
    if (!keysStale && entries.length <= KEYS_MOST) return;
    if (!keysStale || generationRead) textChanged();
    keys.clear();
    entries.length = 0;
    keysStale = false;
  }
  // a face's descriptors: its weight (0: variable, all of them); the words' faces (1, 2) with Inter's single-storey a and
  // open digits, as the Mac's host sets them (apple_text.m face_font: cv11, ss01; a face without them is as it is)
  const faceDescriptors = (face, weight) => ({
    weight: weight ? String(weight) : '1 1000',
    ...(face === 1 || face === 2 ? { featureSettings: '"cv11" 1, "ss01" 1' } : {}),
  });
  // a face's file (a URL), for a weight (0: variable, all of them): drawn in once the page has loaded it
  H.faceAdd = (face, url, weight) => {
    if (!(face > 0 && face < 16) || typeof FontFace !== 'function') return false;
    const ff = new FontFace(`mbface${face}`, `url(${JSON.stringify(url)})`, faceDescriptors(face, weight));
    faceFile(face, `url(${JSON.stringify(url)})`, weight);
    ff.load().then(() => {
      document.fonts.add(ff);
      faces.add(face);
      textChanged();
      H.requestFrame();
    }, () => {});
    return true;
  };
  // the same, the file's bytes given
  H.faceAddBytes = (face, data, weight) => {
    if (!(face > 0 && face < 16) || typeof FontFace !== 'function') return false;
    const ff = new FontFace(`mbface${face}`, data, faceDescriptors(face, weight));
    faceFile(face, data, weight);
    ff.load().then(() => {
      document.fonts.add(ff);
      faces.add(face);
      textChanged();
      H.requestFrame();
    }, () => {});
    return true;
  };
  // A face's CJK companion (@webpage.set_cjk_face): the system's CJK faces drawn, within the face's family, for the
  // CJK marks alone (its unicode-range: Han, kana, bopomofo, CJK punctuation, full-width forms; the Latin quotes and
  // dashes left to the face itself), each of the nine weights set in the one `step` heavier (a Latin face's 400 beside
  // a CJK face's 400 reads thin and grey), clamped to 100..900, by the families given (local names, the first the
  // system has) or else PingFang SC, Noto Sans CJK SC, Source Han Sans SC. With no face of the app's own given (faceAdd)
  // the face is taken for its CJK alone once any of them is there, the rest of the words in the page's own as before;
  // where none is, nothing changes. Asked again, what it set before goes first.
  const CJK_RANGE = 'U+2E80-2FDF, U+3000-303F, U+3040-30FF, U+3100-312F, U+3190-31FF, U+3400-4DBF, U+4E00-9FFF, ' +
    'U+F900-FAFF, U+FE30-FE4F, U+FF00-FFEF, U+20000-2FA1F';
  const CJK_FAMILIES = ['PingFang SC', 'Noto Sans CJK SC', 'Source Han Sans SC'];
  // each weight's names in the families' own files, the nearest first
  const CJK_WEIGHT_NAMES = {
    100: ['Thin', 'Ultralight', 'ExtraLight'], 200: ['ExtraLight', 'Ultralight', 'Thin'], 300: ['Light', 'DemiLight'],
    400: ['Regular', 'Normal'], 500: ['Medium'], 600: ['Semibold', 'SemiBold', 'Bold'], 700: ['Bold', 'Semibold'],
    800: ['Heavy', 'ExtraBold', 'Black'], 900: ['Black', 'Heavy'],
  };
  const cjkSrc = (families, weight) => {
    const out = [];
    for (const fam of families) {
      for (const name of CJK_WEIGHT_NAMES[weight]) {
        out.push(`local(${JSON.stringify(`${fam} ${name}`)})`);
        out.push(`local(${JSON.stringify(`${fam.replace(/ /g, '')}-${name}`)})`);
      }
      if (weight === 400) out.push(`local(${JSON.stringify(fam)})`);
    }
    return out.join(', ');
  };
  // each face's CJK files ([src, weight, descriptors], as faceFiles' for narrowFace) and the FontFaces put in the page
  const cjkFiles = new Map();
  const cjkLoaded = new Map();
  const cjkForget = (face) => {
    cjkFiles.delete(face);
    for (const ff of cjkLoaded.get(face) || []) document.fonts.delete(ff);
    cjkLoaded.delete(face);
  };
  H.setCjkFace = (face, weightStep, families) => {
    if (!(face > 0 && face < 16) || typeof FontFace !== 'function') return false;
    const step = Number.isFinite(weightStep) ? Math.round(weightStep / 100) * 100 : 100;
    const fams = Array.isArray(families) && families.length ? families.map(String) : CJK_FAMILIES;
    cjkForget(face);
    const files = [];
    for (let w = 100; w <= 900; w += 100) {
      const drawn = Math.min(900, Math.max(100, w + step));
      files.push([cjkSrc(fams, drawn), w, { weight: String(w), unicodeRange: CJK_RANGE }]);
    }
    cjkFiles.set(face, files);
    const loaded = [];
    cjkLoaded.set(face, loaded);
    // (narrow already asked of the face: its CJK narrow too)
    const narrow = narrowFaces.has(face);
    const load = (family, [src, , desc], more) => {
      const ff = new FontFace(family, src, { ...desc, ...more });
      return ff.load().then(() => {
        if (cjkFiles.get(face) !== files) return false;
        document.fonts.add(ff);
        loaded.push(ff);
        return true;
      }, () => false);
    };
    Promise.all([
      ...files.map((f) => load(`mbface${face}`, f, {})),
      ...(narrow ? files.map((f) => load(`mbface${face}n`, f, { featureSettings: '"pwid" 1' })) : []),
    ]).then((took) => {
      if (cjkFiles.get(face) !== files || !took.some((t) => t)) return;
      faces.add(face);
      textChanged();
      H.requestFrame();
    });
    return true;
  };
  H.faceClear = (face) => {
    faceFiles.delete(face);
    cjkForget(face);
    narrowFaces.delete(face);
    if (!faces.delete(face)) return;
    for (const ff of [...document.fonts]) {
      const fam = ff.family.replace(/"/g, '');
      if (fam === `mbface${face}` || fam === `mbface${face}n`) document.fonts.delete(ff);
    }
    textChanged();
  };

  H.fontMetrics = (size, weight, style, out) => {
    setMFont(font(size, weight, style));
    const m = mctx.measureText('Hg国');
    out[0] = m.fontBoundingBoxAscent;
    out[1] = m.fontBoundingBoxDescent;
    out[2] = Math.round(size * 1.42);
    // the Han font's: a canvas tells only the first face's box, so the font's own
    out[3] = out[0];
    out[4] = out[1];
    // lines as asked, not on whole pixels
    out[5] = 0;
  };

  const textKey = (c, size, weight, style) => {
    const kk = c + '\x01' + size + '\x01' + weight + '\x01' + style;
    let key = keys.get(kk);
    if (key === undefined) {
      key = entries.length;
      entries.push({ c, size, weight, style });
      keys.set(kk, key);
    }
    return key;
  };
  H.textKey = textKey;
  // a width the canvas measures, kept
  const width = (f, s) => {
    const ak = f + '\x01' + s;
    let w = advCache.get(ak);
    if (w === undefined) {
      w = mctx.measureText(s).width;
      if (advCache.size >= ADV_MOST) advCache.clear();
      advCache.set(ak, w);
    }
    return w;
  };

  // digits all one width (style & 32, style.mbt style_tabular): a canvas has no font-variant-numeric, so each digit
  // advances as the widest of the ten and is drawn centred in it (rasterize)
  const isDigit = (c) => c.length === 1 && c >= '0' && c <= '9';
  const tabWidth = (f) => Math.max(...'0123456789'.split('').map((d) => width(f, d)));
  // a cluster that is a CJK unified ideograph (its first code point: the basic block and extension A, the
  // compatibility ideographs, the supplementary planes' extensions)
  const han = (c) => {
    const cp = c.codePointAt(0);
    return (cp >= 0x3400 && cp <= 0x9FFF) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0x20000 && cp <= 0x323AF);
  };

  H.shape = (text, size, weight, style, out) => {
    const f = font(size, weight, style);
    setMFont(f);
    const cap = out.length / 4;
    const segs = [...seg.segment(text)];
    // the canvas says no more of a cluster than its width alone; within a word, a cluster starts where the word up
    // to and with it ends, less its own width: kerning moves it as the browser does, the spacing the browser trims
    // between CJK punctuation is trimmed, and the word ends where the canvas ends it (letters that join)
    const blank = (c) => /^\s+$/.test(c);
    // no ligatures (style & 8, words with letter spacing): a canvas has no font-variant-ligatures, so the word is
    // measured with a zero width non-joiner between its clusters, which keeps the browser from making one
    const upTo = style & 8
      ? (w, i) => segs.slice(w, i + 1).map((s) => s.segment).join('\u200C')
      : (w, i) => text.slice(segs[w].index, segs[i].index + segs[i].segment.length);
    // A Han character after a Han character starts a word of its own: no kerning pair joins two of them, so it
    // advances by its own width, and a paragraph with no spaces is measured cluster by cluster, not as a prefix
    // growing to its end at each (500 characters were 125,000 measured, a frame of 70-110 ms). Punctuation beside Han
    // stays in its word, the spacing the browser trims there trimmed as before.
    const starts = new Uint8Array(segs.length);
    for (let i = 0; i < segs.length; i++) {
      const c = segs[i].segment;
      starts[i] = i === 0 || blank(segs[i - 1].segment) || (han(c) && han(segs[i - 1].segment)) ? 1 : 0;
    }
    const xs = new Array(segs.length);
    let word = 0;
    for (let i = 0; i < segs.length; i++) {
      const c = segs[i].segment;
      if (blank(c)) continue;
      if (starts[i]) word = i;
      xs[i] = width(f, upTo(word, i)) - width(f, c);
    }
    let k = 0;
    word = 0;
    for (let i = 0; i < segs.length && k < cap; i++) {
      const s = segs[i];
      const c = s.segment;
      let adv;
      if (blank(c)) {
        adv = width(f, c);
      } else {
        if (starts[i]) word = i;
        const last = i + 1 >= segs.length || blank(segs[i + 1].segment) || starts[i + 1];
        const end = last ? width(f, upTo(word, i)) : xs[i + 1];
        adv = Math.max(0, end - xs[i]);
      }
      if (style & 32 && isDigit(c)) adv = tabWidth(f);
      let key = -1;
      if (c === '\n') adv = 0;
      else if (c !== ' ' && c !== '\t') key = textKey(c, size, weight, style);
      out[k * 4] = s.index;
      out[k * 4 + 1] = c.length;
      out[k * 4 + 2] = adv;
      out[k * 4 + 3] = key;
      k++;
    }
    return k;
  };

  H.atlasGeneration = () => {
    generationRead = true;
    return generation;
  };
  // (one atlas: colour glyphs in it with the others)
  H.atlasSize = (colour) => colour ? 0 : ATLAS;

  // A glyph key's horizontal quarter-pixel phase (bits 26..27: text.mbt glyph_col_sub), in pixels: how far right of
  // the whole pixel column its quad is put on a glyph at it is drawn (win_text.cpp's sub_dx, the same).
  const subDx = (sub) => sub === 1 ? 0.25 : sub === 2 ? -0.5 : sub === 3 ? -0.25 : 0;

  // `e` drawn in black, a pixel round its bounds: its box (in `e`) and its picture, held for H.glyphPut (where it
  // goes in the atlas is MoonBit's: hostapi's atlas.mbt). Its ink drawn moved right by its phase (`fullKey`'s), and a
  // digit of words whose digits are one width (style & 32) by as much again as centres it in the widest's room; the
  // picture's edges on whole pixels round the ink so moved, so where it lands is never a pixel's rounding of its place
  // added to that.
  function rasterize(e, fullKey) {
    held = null;
    const sc = dpr;
    const sub = (fullKey >>> 26) & 7;
    setMFont(font(e.size, e.weight, e.style));
    const m = mctx.measureText(e.c);
    const left = m.actualBoundingBoxLeft, right = m.actualBoundingBoxRight;
    const asc = m.actualBoundingBoxAscent, desc = m.actualBoundingBoxDescent;
    let tabShift = 0;
    if (e.style & 32 && isDigit(e.c)) {
      const f = font(e.size, e.weight, e.style);
      tabShift = (tabWidth(f) - width(f, e.c)) / 2;
    }
    const shiftPx = tabShift * sc + (sub < 4 ? subDx(sub) : 0);
    // whole pixels each way from the baseline, so every glyph's baseline is
    // on a pixel row of its bitmap and glyphs on one line line up
    const pad = 1;
    const x0 = Math.floor(-left * sc + shiftPx) - pad, x1 = Math.ceil(right * sc + shiftPx) + pad;
    const a = Math.ceil(asc * sc), d = Math.ceil(desc * sc);
    const pw = x1 - x0, ph = a + d + 2 * pad;
    e.w = 0;
    if (pw <= 2 || ph <= 2 || pw > 512 || ph > 512) return;
    if (pw > rc.width || ph > rc.height) {
      // (grown by 64 px steps, to the largest glyph yet: a canvas sized anew forgets its state, set again here)
      rc.width = Math.max(rc.width, Math.ceil(pw / 64) * 64);
      rc.height = Math.max(rc.height, Math.ceil(ph / 64) * 64);
      rctxFont = '';
      // drawn in black, as words are mostly dark on light: a canvas makes light words on nothing heavier (its text's
      // contrast and gamma for light ink), and words drawn from a white glyph were a sixth bolder than the Mac's app
      // draws them (Han and Latin alike: 328580 against 282186 of ink, white and black, at 24 px)
      rctx.fillStyle = '#000';
      rctx.textBaseline = 'alphabetic';
    }
    rctx.clearRect(0, 0, pw, ph);
    const rf = font(e.size * sc, e.weight, e.style);
    if (rf !== rctxFont) { rctx.font = rf; rctxFont = rf; }
    rctx.fillText(e.c, -x0 + shiftPx, pad + a);
    const img = rctx.getImageData(0, 0, pw, ph);
    // drawn in black: a cluster with colours of its own (grey ones too: any pixel of some opacity not black) is an
    // emoji's
    let color = 0;
    for (let i = 0; i < img.data.length && !color; i += 4) {
      if (img.data[i + 3] > 64 && Math.max(img.data[i], img.data[i + 1], img.data[i + 2]) > 32) color = 1;
    }
    held = { key: fullKey, img, pw, ph };
    e.w = pw / sc;
    e.h = ph / sc;
    e.ox = x0 / sc;
    e.oy = -(a + pad) / sc;
    e.color = color;
  }

  H.glyph = (key, out) => {
    const e = key >= 0 ? entries[key & 0x03FFFFFF] : undefined;
    if (!e) { for (let i = 0; i < 8; i++) out[i] = 0; return; }
    rasterize(e, key);
    out[0] = 0; out[1] = 0; out[2] = e.w || 0; out[3] = e.h || 0;
    out[4] = e.ox || 0; out[5] = e.oy || 0; out[6] = e.color || 0;
  };

  // the glyph drawn last put in the atlas, its top left at x, y
  // (the atlas is the run's, one for every window: put in each open window's texture of it, and how far it is filled
  // kept, for a window opened later to copy that much of the page's: slotAtlas)
  let atlasUsedW = 0, atlasUsedH = 0;
  const putGlyph = (g, tex, x, y) => {
    g.bindTexture(g.TEXTURE_2D, tex);
    g.pixelStorei(g.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
    g.texSubImage2D(g.TEXTURE_2D, 0, x, y, held.pw, held.ph, g.RGBA, g.UNSIGNED_BYTE, held.img);
    // (back as every other upload takes it: left on, it premultiplies the shapes' pieces too, segsUpload's floats
    // each times its four's last, and every icon after the first glyph drawn came out torn)
    g.pixelStorei(g.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  };
  H.glyphPut = (key, x, y) => {
    if (!held || held.key !== key) return;
    putGlyph(gl, atlasTex, x, y);
    if (winsOpen) {
      for (let i = 0; i < MB_WINS; i++) {
        const s = wins[i];
        if (i !== winActive && s && !s.closed && s.gl) putGlyph(s.gl, s.atlasTex, x, y);
      }
    }
    atlasUsedW = Math.min(ATLAS, Math.max(atlasUsedW, x + held.pw));
    atlasUsedH = Math.min(ATLAS, Math.max(atlasUsedH, y + held.ph));
    held = null;
  };

  // ---- the platform's own text drawing (textref_js.mbt, src/textdiff) ----
  // A 2D canvas drawn with fillText at the places mbui draws the same words, and the window's own picture read back
  // as it is drawn; both kept as PNG data URLs in window.__mbref for whoever drives the page (scripts/textdiff-web.mjs).
  window.__mbref = {};
  let refCanvas = null, refCtx = null, refFrameName = null;
  const hex = (c) => '#' + (c & 0xffffff).toString(16).padStart(6, '0');
  H.refBegin = (w, h, s, bg) => {
    refCanvas = document.createElement('canvas');
    refCanvas.width = Math.round(w * s);
    refCanvas.height = Math.round(h * s);
    refCtx = refCanvas.getContext('2d');
    refCtx.fillStyle = hex(bg);
    refCtx.fillRect(0, 0, refCanvas.width, refCanvas.height);
    refCtx.scale(s, s);
  };
  H.refText = (text, size, weight, style, x, base, color, out) => {
    for (let i = 0; i < 5; i++) out[i] = 0;
    if (!refCtx) return;
    refCtx.font = font(size, weight, style);
    refCtx.fillStyle = hex(color);
    refCtx.textBaseline = 'alphabetic';
    refCtx.fillText(text, x, base);
    const m = refCtx.measureText(text);
    out[0] = m.width;
    out[1] = -m.actualBoundingBoxLeft;
    out[2] = -m.actualBoundingBoxAscent;
    out[3] = m.actualBoundingBoxRight;
    out[4] = m.actualBoundingBoxDescent;
  };
  H.refEnd = (name) => {
    if (!refCanvas) return false;
    window.__mbref[name] = refCanvas.toDataURL('image/png');
    refCanvas = refCtx = null;
    return true;
  };
  // the next frame drawn, read back before the browser shows it (a WebGL canvas keeps nothing after)
  H.refFrame = (name) => { refFrameName = name; return true; };
  const presentFrame = H.present;
  H.present = (buf, n, r, g, b) => {
    presentFrame(buf, n, r, g, b);
    if (refFrameName === null) return;
    const w = canvas.width, h = canvas.height;
    const px = new Uint8Array(w * h * 4);
    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    const c2 = document.createElement('canvas');
    c2.width = w;
    c2.height = h;
    const x2 = c2.getContext('2d');
    const img = x2.createImageData(w, h);
    for (let y = 0; y < h; y++) img.data.set(px.subarray((h - 1 - y) * w * 4, (h - y) * w * 4), y * w * 4);
    x2.putImageData(img, 0, 0);
    window.__mbref[refFrameName] = c2.toDataURL('image/png');
    refFrameName = null;
  };

  // ---- input ----
  let imeActive = false, composing = false;
  // what the textarea held after the last edit of it (setIme's, or one the input event below has told the app of)
  let taHad = '';
  H.setIme = (active, x, y, w, h, text, s, e) => {
    imeActive = active;
    ta.style.left = `${x}px`;
    ta.style.top = `${y}px`;
    ta.style.height = `${h}px`;
    // the field's words and selection in the input method's own field, as the other hosts give theirs (the Mac's
    // NSTextInputClient, Android's InputConnection): an input method reads what is before the caret (WeChat's puts a
    // space between Chinese and Latin by it); left alone while it composes
    if (active && !composing) {
      if (ta.value !== text) ta.value = text;
      if (ta.selectionStart !== s || ta.selectionEnd !== e) ta.setSelectionRange(s, e);
      taHad = text;
    }
    if (active && doc.activeElement !== ta) ta.focus({ preventScroll: true });
    if (!active && doc.activeElement === ta) ta.blur();
  };

  // The input method's keyboard for the field about to type (@hostapi.ime_action, said before setIme: 0 none, 1 a
  // search's, 2 an address's, 3 a number's, 4 a secret's, 5 an email address's, 6 words taken as typed), as the phones'
  // hosts ask theirs (ios_app.m's keyboardType, MBView's EditorInfo): the textarea's inputmode, its Enter key's word,
  // whether the keyboard corrects, spells or capitalises. A keyboard up for another field takes them only as it comes up
  // again, so the textarea focused is let go and focused again by setIme after (the tap that moved the field still
  // handled, frameInGesture: iOS keeps its keyboard up).
  const imeKinds = [
    {},
    { inputmode: 'search', enterkeyhint: 'search' },
    { inputmode: 'url', enterkeyhint: 'go', autocorrect: 'off' },
    { inputmode: 'numeric', enterkeyhint: 'done', autocorrect: 'off' },
    { autocorrect: 'off' },
    { inputmode: 'email', autocorrect: 'off' },
    { autocorrect: 'off' },
  ];
  let imeKind = 0, imeRefocus = false;
  H.imeAction = (k) => {
    const kind = imeKinds[k] ? k : 0;
    if (kind === imeKind) return;
    imeKind = kind;
    const want = imeKinds[kind];
    for (const name of ['inputmode', 'enterkeyhint', 'autocorrect']) {
      if (want[name]) ta.setAttribute(name, want[name]);
      else ta.removeAttribute(name);
    }
    if (doc.activeElement === ta) {
      imeRefocus = true;
      ta.blur();
      imeRefocus = false;
    }
  };

  // What an edit changed of the textarea's words `was`, to `now` with the caret at `caret`: [from, to, put], the words
  // of `was` from `from` to `to` replaced by `put`. What is after the caret is what it left alone, where `was` ends so
  // (an "a" put in before "aa" is put in there, though "aaa" could be read as it after them); the halves of a surrogate
  // pair stay together.
  function taEdit(was, now, caret) {
    const most = Math.min(was.length, now.length);
    let tail = now.length - caret;
    if (tail > was.length || !was.endsWith(now.slice(caret))) {
      tail = 0;
      while (tail < most && was[was.length - 1 - tail] === now[now.length - 1 - tail]) tail++;
    }
    let from = 0;
    while (from < most - tail && was[from] === now[from]) from++;
    if (from > 0 && (now.charCodeAt(from - 1) & 0xfc00) === 0xd800) from--;
    if (tail > 0 && (now.charCodeAt(now.length - tail) & 0xfc00) === 0xdc00) tail--;
    return [from, was.length - tail, now.slice(from, now.length - tail)];
  }

  function pos(e) {
    if (!rectValid) {
      const r = canvas.getBoundingClientRect();
      rectLeft = r.left;
      rectTop = r.top;
      rectValid = true;
    }
    return [e.clientX - rectLeft, e.clientY - rectTop];
  }

  // a pointer event, with its own time (performance.now's clock) while MoonBit handles it
  let evT = -1;
  function ptr(kind, e, button, fallbackTs) {
    const [x, y] = pos(e);
    evT = e.timeStamp > 0 ? e.timeStamp : (fallbackTs !== undefined ? fallbackTs : e.timeStamp);
    try { cb.pointer(kind, x, y, button); } finally { evT = -1; }
  }

  const isIOS = () => {
    const nav = hostWin.navigator || navigator;
    const p = (nav.userAgentData && nav.userAgentData.platform) || nav.platform || '';
    const ua = nav.userAgent || '';
    return /iphone|ipad|ipod/i.test(p) || /iphone|ipad|ipod/i.test(ua) || (/mac/i.test(p) && nav.maxTouchPoints > 1);
  };

  let takePresses = null;
  // The input of a window (the page's, or one opened beside it: `win`, its id `wid`, its canvas and textarea in place
  // as it is set up): each event handled as that window's (inWin).
  function setupInput(win = window, wid = 0) {
    const on = (target, name, f, opts) => target.addEventListener(name, (e) => inWin(wid, () => f(e)), opts);
    // (a touch screen's fingers each by its pointerId, as they come: kinds 10 down, 11 moved, 12 up, 13 called off, what
    // they come to the app's to work out, touches.mbt)
    const touch = (e) => e.pointerType === 'touch';
    const modsOf = (e) => (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
    const tellModifiers = (mods, force = false) => {
      if (force || mods !== modifiersSaid) cb.key(0, mods);
    };
    // (the canvas's, and what takes them in its place while a site is seen)
    const presses = (el) => {
      const btnOf = (e) => (e.button === 2 ? 2 : e.button === 1 ? 3 : 0);
      on(el, 'pointerdown', (e) => {
        e.preventDefault();
        // A key may have been held before the browser gained focus.
        tellModifiers(modsOf(e));
        // (a box over a site goes as the app says, the press going on: `under` stays; when the canvas takes the
        // press, it stays too and can capture it itself)
        (el === canvas ? canvas : under || el).setPointerCapture(e.pointerId);
        if (touch(e)) { ptr(10, e, e.pointerId); if (isIOS()) frameInGesture(); }
        else if (e.button === 0 || e.button === 1 || e.button === 2) ptr(0, e, btnOf(e));
        // keep the keyboard on the textarea while an editor has focus
        if (imeActive) ta.focus({ preventScroll: true });
      });
      on(el, 'pointermove', (e) => {
        if (touch(e)) {
          const list = typeof e.getCoalescedEvents === 'function' ? e.getCoalescedEvents() : null;
          if (list && list.length > 0) {
            for (const ce of list) ptr(11, ce, e.pointerId, e.timeStamp);
          } else {
            ptr(11, e, e.pointerId);
          }
        } else {
          ptr(1, e, 0);
        }
      });
      on(el, 'pointerup', (e) => {
        if (touch(e)) { ptr(12, e, e.pointerId); if (isIOS()) frameInGesture(); }
        else if (e.button === 0 || e.button === 1 || e.button === 2) ptr(2, e, btnOf(e));
      });
      on(el, 'pointercancel', (e) => (touch(e) ? ptr(13, e, e.pointerId) : ptr(3, e, 0)));
      // A move or a capture transfer between the app's own input layers is not leaving the window. Leaving them for
      // a site or the outside is: nothing of the app is hovered there.
      on(el, 'pointerleave', (e) => {
        const to = e.relatedTarget;
        const appInput = to === canvas || (to != null && (to === under || coverBoxes.includes(to)));
        if (e.pointerType === 'mouse' && !appInput) cb.pointer(7, -1, -1, 0);
      });
      on(el, 'contextmenu', (e) => e.preventDefault());
      on(el, 'auxclick', (e) => { if (e.button === 1) e.preventDefault(); });
      on(el, 'wheel', (e) => {
        const k = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? cssH : 1;
        const [x, y] = pos(e);
        // lines (a mouse wheel's notches, as Firefox says them): eased in by the app (phase 4)
        // what is held with it, above the phase (ui's wheel_mod_*: a trackpad's pinch comes as ctrl and the wheel, and
        // ctrl with a mouse's wheel is the browser's zoom too: both a pinch, no list scrolls by it)
        const mods = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 | 16 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
        H.wheelKept = true;
        cb.wheel(x, y, e.deltaX * k, e.deltaY * k, (e.deltaMode === 1 ? 4 : 0) | (mods << 4));
        // a pinch the app zoomed nothing by (@hostapi.wheel_kept: a picture, a remote screen) zooms the page
        if (!e.ctrlKey || H.wheelKept) e.preventDefault();
      }, { passive: false });
    };
    takePresses = presses;
    presses(canvas);
    const keymap = { Backspace: 1, Delete: 2, ArrowLeft: 3, ArrowRight: 4, ArrowUp: 5, ArrowDown: 6, Enter: 7, Home: 8, End: 9, PageUp: 15, PageDown: 16, Escape: 17, Tab: 18 };
    // the browser's own shortcuts left to it (reload, close, a new tab or window, the address bar, quit, zoom)
    const browsers = new Set(['r', 'w', 't', 'n', 'l', 'q', 'v']);
    // Modifier-only keys are input too. Other keys keep their normal path, including browser shortcuts.
    const modifiers = new Set(['Shift', 'Control', 'Alt', 'Meta', 'OS']);
    const modifierKey = (e) => { if (modifiers.has(e.key)) tellModifiers(modsOf(e), true); };
    on(win, 'keydown', modifierKey, true);
    on(win, 'keyup', modifierKey, true);
    on(win, 'blur', () => tellModifiers(0, true));
    const command = (e) => keysCmd() === 8 ? e.metaKey : e.ctrlKey;
    const browserKey = (e, c) => command(e) && (browsers.has(c) ||
      (!e.altKey && !(e.ctrlKey && e.metaKey) && ['+', '=', '-', '0'].includes(c)));
    // Cocoa translates these Control keys to editing commands in a field (mac_app.m's doCommandBySelector).
    // The browser's hidden IME field cannot move the app's caret itself, so send the same commands to the editor.
    const macEdit = (e) => {
      if (keysCmd() !== 8 || !e.ctrlKey || e.metaKey) return 0;
      const c = /^[a-z]$/i.test(e.key) ? e.key.toLowerCase() : /^Key[A-Z]$/.test(e.code) ? e.code.slice(3).toLowerCase() : e.key;
      if (e.altKey) return ({ b: 20, f: 21 })[c] || 0;
      if (e.shiftKey && !['a', 'b', 'e', 'f', 'n', 'p', 'v', 'ArrowLeft', 'ArrowRight'].includes(c)) return 0;
      return ({ a: 24, b: 3, d: 2, e: 25, f: 4, h: 1, k: 35, n: 6, p: 5, v: 16,
        ArrowLeft: 22, ArrowRight: 23, ArrowUp: 15, ArrowDown: 16 })[c] || 0;
    };
    on(ta, 'keydown', (e) => {
      if (e.isComposing || e.keyCode === 229) return;
      const mods = modsOf(e);
      // a key catcher's focus (device, below): Alt too makes a shortcut; select all, copy, cut are its keys
      if (catching && (e.metaKey || e.ctrlKey || e.altKey) && !keymap[e.key]) {
        const c = e.key.length === 1 ? e.key.toLowerCase() : '';
        if (c && !browserKey(e, c)) { cb.key(1000 + c.charCodeAt(0), mods); e.preventDefault(); }
        return;
      }
      // Cocoa's Control-O inserts a newline and leaves the caret before it (two text commands).
      if (!catching && keysCmd() === 8 && e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey && e.key.toLowerCase() === 'o') {
        cb.key(7, 1); cb.key(3, 0); e.preventDefault(); return;
      }
      const edit = !catching && macEdit(e);
      if (edit) { cb.key(edit, e.shiftKey ? 1 : 0); e.preventDefault(); return; }
      if ((e.metaKey || e.ctrlKey) && !keymap[e.key]) {
        const c = e.key.toLowerCase();
        const own = command(e) ? { a: 12, c: 13, x: 14 }[c] : undefined;
        if (own) { cb.key(own, mods); e.preventDefault(); }
        else if (c.length === 1 && !browserKey(e, c)) { cb.key(1000 + c.charCodeAt(0), mods); e.preventDefault(); }
        return; // paste arrives as a paste event
      }
      const code = keymap[e.key];
      if (code) { cb.key(code, mods); e.preventDefault(); }
    });
    // with no field focused, the keys are the app's (its shortcuts, Escape, the arrows; a character as 1000 + it)
    on(win, 'keydown', (e) => {
      if (e.defaultPrevented || e.target === ta || imeActive || e.isComposing || e.keyCode === 229) return;
      if (e.target?.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(e.target?.tagName)) return;
      if (!catching && e.altKey && !e.shiftKey && !e.ctrlKey && !e.metaKey && e.key === 'ArrowLeft') {
        goBack(e);
        return;
      }
      const mods = modsOf(e);
      const code = keymap[e.key];
      if (code) { cb.key(code, mods); e.preventDefault(); return; }
      const c = e.key.length === 1 ? e.key.toLowerCase() : '';
      if (!c) return;
      if (browserKey(e, c)) return;
      // select all, copy (the words picked with the pointer), cut: the editor's codes
      const own = command(e) ? { a: 12, c: 13, x: 14 }[c] : undefined;
      cb.key(own ?? 1000 + c.charCodeAt(0), mods);
      e.preventDefault();
    });
    on(win, 'mouseup', (e) => { if (e.button === 3) goBack(e); });
    // What an input method did to its field goes to the app's as what it changed there, not as what it says it put in:
    // voice input writes a guess and replaces it as it hears more (iOS's dictation selects its last guess and inserts
    // the next over it; another's keyboard may delete it key by key and type the next), corrections and suggestions
    // replace a word, each an event whose data is only the new words. (The textarea is given the field's words again
    // as the app says them, setIme.)
    on(ta, 'input', (e) => {
      if (e.isComposing || composing) return;
      const was = taHad, now = ta.value;
      taHad = now;
      const [from, to, put] = taEdit(was, now, ta.selectionStart);
      // (a line's end typed by a keyboard that does not send the key: as the key, ios_app.m's insertText)
      if (from === to && put === '\n') { cb.key(7, 0); return; }
      if (to > from) cb.text(3, '', from, to);
      if (to > from || put) cb.text(0, put, 0, 0);
    });
    // The keyboard put away by the person (Safari's Done over it), not by the app: the field lets go of the focus, as
    // the phones' apps' do (or setIme would take the focus back and the keyboard come up again). (The page sent behind
    // blurs the textarea too, and leaves it the focused element.)
    on(ta, 'blur', () => {
      if (!imeRefocus && imeActive && keyboardOver() > 0 && doc.activeElement !== ta) {
        cb.text(7, '', 0, 0);
        H.requestFrame();
      }
    });
    // ⌘V (the browser's paste): files on the clipboard (copied in Finder, a screenshot's picture) are the app's ⌘V
    // (1000 + v), which reads the clipboard for them (H.clipRead: this paste's, as the page may not read files off the
    // clipboard itself), as the Mac's host's paste_now; else its words, put in as typed
    const pasted = (e) => {
      const files = [...(e.clipboardData?.files || [])];
      if (files.length) {
        pasteHeld = { files, text: e.clipboardData.getData('text/plain') || '' };
        cb.key(1000 + 'v'.charCodeAt(0), keysCmd());
      } else {
        const t = e.clipboardData?.getData('text/plain') || '';
        if (t && e.target === ta) cb.text(0, t, 0, 0);
        else if (t) return;
      }
      e.preventDefault();
    };
    on(ta, 'paste', pasted);
    // (with no field focused, what is pasted goes to the page: a chat's ⌘V of a picture with the composer not focused)
    on(win, 'paste', (e) => { if (e.target !== ta) pasted(e); });
    on(ta, 'compositionstart', () => { composing = true; });
    on(ta, 'compositionupdate', (e) => cb.text(1, e.data || '', (e.data || '').length, 0));
    on(ta, 'compositionend', (e) => {
      composing = false;
      taHad = ta.value;
      cb.text(1, '', 0, 0);
      if (e.data) cb.text(0, e.data, 0, 0);
    });
    const sizeChanged = () => inWin(wid, () => { sizeDirty = true; rectValid = false; H.requestFrame(); });
    on(win, 'resize', sizeChanged);
    on(win, 'scroll', () => { rectValid = false; });
    // (the soft keyboard coming or going changes no size of the page's: keyboardOver)
    if (win.visualViewport) {
      on(win.visualViewport, 'resize', () => { rectValid = false; H.requestFrame(); });
      on(win.visualViewport, 'scroll', () => { rectValid = false; H.requestFrame(); });
    }
    const Observer = win.ResizeObserver || (typeof ResizeObserver !== 'undefined' ? ResizeObserver : undefined);
    if (Observer) {
      sizeObserver = new Observer(sizeChanged);
      sizeObserver.observe(canvas);
    }
    // A window can move between displays with different scales without changing its CSS size (and so without a
    // resize event). Watch the current resolution, then subscribe to the new one when it changes.
    if (win.matchMedia) {
      let resolution;
      const watch = () => {
        if (resolution) resolution.removeEventListener('change', changed);
        resolution = win.matchMedia(`(resolution: ${win.devicePixelRatio || 1}dppx)`);
        resolution.addEventListener('change', changed);
      };
      const changed = () => {
        watch();
        H.requestFrame();
      };
      watch();
    }
  }

  // the pointer's shape (@hostapi.set_cursor)
  const cursors = ['default', 'pointer', 'text', 'ew-resize', 'ns-resize', 'grab', 'grabbing', 'crosshair', 'not-allowed', 'nwse-resize', 'nesw-resize'];
  // (the page's, which all that takes presses inherits)
  H.setCursor = (k) => { doc.body.style.cursor = cursors[k] || 'default'; };
  H.clipboardSet = (s) => { navigator.clipboard?.writeText(s).catch(() => {}); };
  // The floating text menu over words picked by a finger (@hostapi.text_menu: a field's, or the page's words a finger
  // held, as Android's ActionMode and iOS's edit menu): a small bar of the page's own over the rectangle given (under
  // it where there is no room over it), offering what `can` says (1 cut, 2 copy, 4 paste, 8 select all), each done as
  // the native hosts' menus do (the field's keys 14, 13, 12; the clipboard's words put in as typed), in the
  // browser's language; put away when not shown, and as one of it is pressed.
  let menuEl = null;
  // the words of the app's own items, a line each in their order (@hostapi.text_menu_own), offered where `can` says 64,
  // after the others; the k-th chosen, the key 60 + k (8 at most)
  let menuOwn = [];
  H.textMenuOwn = (s) => { menuOwn = s ? s.split('\n').slice(0, 8) : []; };
  H.textMenu = (shown, x, y, w, h, can) => {
    if (!shown) {
      if (menuEl) { menuEl.remove(); menuEl = null; }
      return;
    }
    if (!menuEl) {
      menuEl = document.createElement('div');
      menuEl.style.cssText = 'position:fixed;z-index:10;display:flex;gap:2px;padding:4px;border-radius:999px;' +
        'background:#2c2c2e;box-shadow:0 4px 16px rgba(0,0,0,.25);font:500 14px system-ui,sans-serif;' +
        'transform:translate(-50%,0);touch-action:none;user-select:none;-webkit-user-select:none';
      for (const ev of ['pointerdown', 'pointerup', 'touchstart', 'touchend', 'mousedown', 'mouseup']) {
        menuEl.addEventListener(ev, (e) => e.stopPropagation());
      }
      document.body.append(menuEl);
    }
    const zh = (navigator.language || '').toLowerCase().startsWith('zh');
    const items = [
      [1, zh ? '剪切' : 'Cut', () => cb.key(14, 0)],
      [2, zh ? '复制' : 'Copy', () => cb.key(13, 0)],
      [4, zh ? '粘贴' : 'Paste', () => navigator.clipboard?.readText().then((t) => { if (t) { cb.text(0, t, 0, 0); H.requestFrame(); } }).catch(() => {})],
      [8, zh ? '全选' : 'Select all', () => cb.key(12, 0)],
      ...menuOwn.map((label, k) => [64, label, () => cb.key(60 + k, 0)]),
    ];
    menuEl.replaceChildren();
    for (const [bit, label, act] of items) {
      if (!(can & bit) || !label) continue;
      const b = document.createElement('button');
      b.textContent = label;
      b.style.cssText = 'border:0;background:none;color:#fff;font:inherit;padding:6px 12px;border-radius:999px;cursor:pointer';
      b.addEventListener('click', (e) => {
        e.stopPropagation();
        if (menuEl) { menuEl.remove(); menuEl = null; }
        act();
        H.requestFrame();
      });
      menuEl.append(b);
    }
    const r = canvas.getBoundingClientRect();
    const above = y - 48;
    menuEl.style.left = (r.left + x + w / 2) + 'px';
    menuEl.style.top = (r.top + (above >= 8 ? above : y + h + 12)) + 'px';
  };
  // the word around a UTF-16 offset as the browser finds words (Intl.Segmenter: a dictionary's in Chinese), start × 2³²
  // + end; -1 without one
  const words = typeof Intl !== 'undefined' && Intl.Segmenter ? new Intl.Segmenter(undefined, { granularity: 'word' }) : null;
  H.wordAt = (t, o) => {
    if (!words) return -1;
    const seg = words.segment(t).containing(o);
    return seg ? seg.index * 4294967296 + seg.index + seg.segment.length : -1;
  };
  // a URL handed to the browser: a tab of its own (noopener: the page cannot reach this one; window.open then answers
  // null whether or not it opened, so it is taken as handed over)
  H.openUrl = (u) => {
    window.__opened = (window.__opened || []).concat([u]);
    window.open(u, '_blank', 'noopener');
    return true;
  };
  H.log = (s) => {
    console.log(s);
    const l = window.__logs;
    l.push(s);
    if (l.length > LOGS_MOST) l.splice(0, l.length - LOGS_MOST);
  };
  H.benchMode = () => Number(params.get('bench') || 0);
  // the app's end: no frame after it (a page cannot close itself; whoever drives it reads __done)
  H.exit = (code) => { window.__done = code; document.title = 'DONE ' + code; };
  H.eventTime = () => evT;
  H.reduceTransparency = () => !!(window.matchMedia && matchMedia('(prefers-reduced-transparency: reduce)').matches);
  H.gpuMs = () => -1;
  H.memBytes = () => (performance.memory ? performance.memory.usedJSHeapSize : 0);

  // ---- back ----
  // No system back gesture here (the page's own edge swipe is MoonBit's): Alt+Left and a mouse's back button go
  // back, when the app takes it.
  let back = null, backOn = false;
  H.setBack = (b) => { back = b; };
  H.backEnabled = (on) => { backOn = on; };
  const goBack = (e) => { if (back && backOn) { e.preventDefault(); back(2, 0, 1, 0); } };

  // A context lost (the GPU's process gone; a phone's browser takes it from a page sent behind): without
  // preventDefault the browser never gives it back, and paints the canvas white with its broken-canvas mark, over the
  // whole app. Given back, it holds nothing: all of it made again, the glyphs drawn again by MoonBit as the generation
  // moves on, each picture decoded again and told again as it is uploaded (what draws it drawn again then).
  let contextLoser = null, contextAnew = false;
  const contextLost = (e) => {
    e.preventDefault();
    // (one lost by H.drive gives itself back; not within this event: allowed only once preventDefault has been seen)
    if (contextLoser) requestAnimationFrame(() => contextLoser.restoreContext());
  };
  const contextRestored = () => {
    setupGL();
    glassLost();
    segsTex = null; segsRows = 0; segsHad = null; segsHadRows = 0;
    uploadedFor = -1;
    textChanged();
    for (const s of streams.values()) { s.tex = null; uploadStream(s); }
    for (const [id, im] of images) {
      if (im.state !== 1) continue;
      Object.assign(im, { state: 0, tex: null });
      told.delete(OUTSIDE_IMAGE + ':' + id);
      decodeImage(id, im.blob, im.maxPx);
    }
    contextLoser = null;
    contextAnew = true;
    H.requestFrame();
  };
  // (@hostapi.drive: 10 the context lost as a browser loses it, and given back; 11 whether it has been)
  H.drive = (kind) => {
    if (kind === 11) return contextAnew;
    if (kind !== 10) return false;
    contextLoser = gl.getExtension('WEBGL_lose_context');
    if (!contextLoser) return false;
    contextAnew = false;
    contextLoser.loseContext();
    return true;
  };

  // ---- terminals (src/hostapi/terminal.mbt, ghostty-vt.wasm) ----
  let vt = null, vtScratch = 0, vtWideLsb = 42;
  const terms = new Map();
  let nextTermId = 1;
  const utf8Dec = typeof TextDecoder !== 'undefined' ? new TextDecoder() : null;
  const utf8Decode = (bytes) => {
    if (utf8Dec) return utf8Dec.decode(bytes);
    let s = '';
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return decodeURIComponent(escape(s));
  };
  const termAsked = (globalThis.__mbrender || typeof WebAssembly === 'undefined' || typeof fetch === 'undefined' || typeof URL === 'undefined')
    ? null
    : (() => {
        try {
          const u = new URL('ghostty-vt.wasm', hostScriptSrc);
          const q = new URL(hostScriptSrc, location.href).search;
          if (q) u.search = q;
          return fetch(u)
            .then((r) => (r.ok && !(r.headers.get('content-type') || '').includes('text/html') ? r.arrayBuffer() : null))
            .then((b) => {
              if (!b || b.byteLength < 8) return null;
              const hdr = new Uint8Array(b, 0, 4);
              if (hdr[0] !== 0 || hdr[1] !== 0x61 || hdr[2] !== 0x73 || hdr[3] !== 0x6d) return null;
              return WebAssembly.instantiate(b, {});
            })
            .then((res) => {
              if (!res) return;
              const x = res.instance.exports;
              const s = x.ghostty_alloc(0, 4096);
              if (!s) return;
              vt = x;
              vtScratch = s;
              try {
                const p = x.ghostty_type_json();
                const m = new Uint8Array(x.memory.buffer);
                let e = p;
                while (m[e] !== 0) e++;
                const tj = JSON.parse(utf8Decode(m.subarray(p, e)));
                const lsb = tj?.types?.GhosttyCell?.bits?.wide?.lsb;
                if (typeof lsb === 'number') vtWideLsb = lsb;
              } catch (_) {}
            })
            .catch(() => {});
        } catch (_) {
          return null;
        }
      })();

  function vtModes(t) {
    const dv = new DataView(vt.memory.buffer);
    const m8 = new Uint8Array(vt.memory.buffer);
    const mc = vtScratch + 440;
    const askMode = (code) => {
      dv.setUint16(mc, code, true);
      m8[mc + 2] = 0;
      return vt.ghostty_terminal_get(t.term, 30, mc) === 0 && m8[mc + 2] !== 0;
    };
    let m = 0;
    if (askMode(1)) m |= 1;
    if (askMode(2004)) m |= 2;
    m8[vtScratch] = 0;
    if (vt.ghostty_terminal_get(t.term, 11, vtScratch) === 0 && m8[vtScratch] !== 0) m |= 4;
    dv.setInt32(vtScratch, 0, true);
    if (vt.ghostty_terminal_get(t.term, 6, vtScratch) === 0 && dv.getInt32(vtScratch, true) === 1) m |= 8;
    if (askMode(1007)) m |= 16;
    if (askMode(1004)) m |= 32;
    if (vt.ghostty_terminal_get(t.term, 31, vtScratch + 112) === 0) m |= 64;
    m8[vtScratch] = 1;
    if (vt.ghostty_terminal_get(t.term, 32, vtScratch) !== 0 || m8[vtScratch] !== 0) m |= 128;
    return m;
  }

  H.termOpen = (cols, rows) => {
    if (!vt) return 0;
    const c = cols > 0 ? cols : 1;
    const r = rows > 0 ? rows : 1;
    if (vt.ghostty_terminal_new(0, vtScratch, c, r) !== 0) return 0;
    const term = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    if (vt.ghostty_render_state_new(0, vtScratch) !== 0) {
      vt.ghostty_terminal_free(term);
      return 0;
    }
    const render = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    if (vt.ghostty_render_state_row_iterator_new(0, vtScratch) !== 0) {
      vt.ghostty_render_state_free(render);
      vt.ghostty_terminal_free(term);
      return 0;
    }
    const rowIt = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    if (vt.ghostty_render_state_row_cells_new(0, vtScratch) !== 0) {
      vt.ghostty_render_state_row_iterator_free(rowIt);
      vt.ghostty_render_state_free(render);
      vt.ghostty_terminal_free(term);
      return 0;
    }
    const cells = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    new DataView(vt.memory.buffer).setUint32(vtScratch, 16 * 1024 * 1024, true);
    vt.ghostty_terminal_set(term, 28, vtScratch);
    let mouse = 0, mouseEv = 0;
    if (vt.ghostty_mouse_encoder_new(0, vtScratch) === 0) {
      mouse = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
      new Uint8Array(vt.memory.buffer)[vtScratch] = 1;
      vt.ghostty_mouse_encoder_set(mouse, 5, vtScratch);
    }
    if (vt.ghostty_mouse_event_new(0, vtScratch) === 0) {
      mouseEv = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    }
    const id = nextTermId++;
    terms.set(id, {
      term, render, rowIt, cells, mouse, mouseEv,
      dragActive: false, dragX0: 0, dragY0: 0, dragScreenX0: 0, dragScreenY0: 0,
      mouseSynced: false, mouseButtons: 0,
      buf: new Uint8Array(8192),
    });
    return id;
  };

  H.termWrite = (id, data) => {
    const t = terms.get(id);
    if (!t || !vt || !data || !data.length) return;
    const n = data.length;
    if (n <= 2816) {
      new Uint8Array(vt.memory.buffer).set(data, vtScratch + 1280);
      vt.ghostty_terminal_vt_write(t.term, vtScratch + 1280, n);
    } else {
      const p = vt.ghostty_alloc(0, n);
      if (!p) return;
      new Uint8Array(vt.memory.buffer).set(data, p);
      vt.ghostty_terminal_vt_write(t.term, p, n);
      vt.ghostty_free(0, p, n);
    }
    t.mouseSynced = false;
  };

  H.termResize = (id, cols, rows, cw, ch) => {
    const t = terms.get(id);
    if (!t || !vt) return;
    vt.ghostty_terminal_resize(t.term, cols > 0 ? cols : 1, rows > 0 ? rows : 1, cw > 0 ? cw : 8, ch > 0 ? ch : 16);
    t.mouseSynced = false;
  };

  H.termModes = (id) => {
    const t = terms.get(id);
    return t && vt ? vtModes(t) : 0;
  };

  H.termFrame = (id, flags) => {
    const t = terms.get(id);
    if (!t || !vt || vt.ghostty_render_state_update(t.render, t.term) !== 0) return new Uint8Array(0);
    let dv = new DataView(vt.memory.buffer);
    let m8 = new Uint8Array(vt.memory.buffer);
    if (flags & 1) {
      dv.setInt32(vtScratch, 2, true);
      vt.ghostty_render_state_set(t.render, 1, vtScratch);
    }
    vt.ghostty_render_state_get(t.render, 1, vtScratch);
    const cols = dv.getUint16(vtScratch, true);
    vt.ghostty_render_state_get(t.render, 2, vtScratch);
    const rows = dv.getUint16(vtScratch, true);
    vt.ghostty_render_state_get(t.render, 3, vtScratch);
    const dirty = dv.getInt32(vtScratch, true);

    m8[vtScratch] = 0;
    vt.ghostty_render_state_get(t.render, 11, vtScratch);
    const curVis = m8[vtScratch] !== 0;
    m8[vtScratch] = 0;
    vt.ghostty_render_state_get(t.render, 14, vtScratch);
    const curAt = m8[vtScratch] !== 0;
    m8[vtScratch] = 0;
    vt.ghostty_render_state_get(t.render, 12, vtScratch);
    const curBlink = m8[vtScratch] !== 0;
    dv.setInt32(vtScratch, 1, true);
    vt.ghostty_render_state_get(t.render, 10, vtScratch);
    const curStyle = dv.getInt32(vtScratch, true);
    let cx = 0, cy = 0, curWide = false;
    if (curAt) {
      vt.ghostty_render_state_get(t.render, 15, vtScratch);
      cx = dv.getUint16(vtScratch, true);
      vt.ghostty_render_state_get(t.render, 16, vtScratch);
      cy = dv.getUint16(vtScratch, true);
      m8[vtScratch] = 0;
      vt.ghostty_render_state_get(t.render, 17, vtScratch);
      curWide = m8[vtScratch] !== 0;
    }

    const hasFg = vt.ghostty_terminal_get(t.term, 18, vtScratch) === 0;
    const fgR = hasFg ? m8[vtScratch] : 0, fgG = hasFg ? m8[vtScratch + 1] : 0, fgB = hasFg ? m8[vtScratch + 2] : 0;
    const hasBg = vt.ghostty_terminal_get(t.term, 19, vtScratch) === 0;
    const bgR = hasBg ? m8[vtScratch] : 0, bgG = hasBg ? m8[vtScratch + 1] : 0, bgB = hasBg ? m8[vtScratch + 2] : 0;
    const hasCur = vt.ghostty_terminal_get(t.term, 20, vtScratch) === 0;
    const crR = hasCur ? m8[vtScratch] : 0, crG = hasCur ? m8[vtScratch + 1] : 0, crB = hasCur ? m8[vtScratch + 2] : 0;

    let curFlags = 0;
    if (curVis && curAt) curFlags |= 1;
    if (curBlink) curFlags |= 2;
    if (curWide) curFlags |= 4;
    if (hasCur) curFlags |= 8;
    if (hasFg) curFlags |= 16;
    if (hasBg) curFlags |= 32;

    const modes = vtModes(t);
    dv = new DataView(vt.memory.buffer);
    m8 = new Uint8Array(vt.memory.buffer);
    const sbAt = vtScratch + 16;
    dv.setBigUint64(sbAt, 0n, true);
    dv.setBigUint64(sbAt + 8, 0n, true);
    dv.setBigUint64(sbAt + 16, 0n, true);
    vt.ghostty_terminal_get(t.term, 9, sbAt);
    const sbTotal = Number(dv.getBigUint64(sbAt, true) & 0xffffffffn) >>> 0;
    const sbOffset = Number(dv.getBigUint64(sbAt + 8, true) & 0xffffffffn) >>> 0;
    const sbLen = Number(dv.getBigUint64(sbAt + 16, true) & 0xffffffffn) >>> 0;

    let out = t.buf;
    let at = 0;
    const need = (n) => {
      if (at + n <= out.length) return;
      let cap = out.length * 2;
      while (cap < at + n) cap *= 2;
      const nb = new Uint8Array(cap);
      nb.set(out.subarray(0, at));
      out = t.buf = nb;
    };
    const u8 = (v) => { need(1); out[at++] = v & 0xff; };
    const u16 = (v) => { need(2); out[at++] = v & 0xff; out[at++] = (v >>> 8) & 0xff; };
    const u32 = (v) => {
      need(4);
      out[at++] = v & 0xff;
      out[at++] = (v >>> 8) & 0xff;
      out[at++] = (v >>> 16) & 0xff;
      out[at++] = (v >>> 24) & 0xff;
    };

    u8(1);
    u8(dirty === 2 ? 2 : dirty === 1 ? 1 : 0);
    u16(cols);
    u16(rows);
    u16(cx);
    u16(cy);
    u8(curStyle >= 0 && curStyle <= 3 ? curStyle : 1);
    u8(curFlags);
    u16(modes);
    u8(fgR); u8(fgG); u8(fgB);
    u8(bgR); u8(bgG); u8(bgB);
    u8(crR); u8(crG); u8(crB);
    u8(0);
    u32(sbTotal);
    u32(sbOffset);
    u32(sbLen);
    const rowCountAt = at;
    u16(0);
    u32(0);

    let rowCount = 0;
    let havePalette = false;
    const palAt = vtScratch + 512;
    const rselAt = vtScratch + 256;
    const styleAt = vtScratch + 160;
    const gbufAt = vtScratch + 176;
    const utf8At = vtScratch + 192;
    const wideShift = BigInt(vtWideLsb);

    if (dirty !== 0) {
      dv.setUint32(vtScratch, t.rowIt, true);
      if (vt.ghostty_render_state_get(t.render, 4, vtScratch) === 0) {
        while (vt.ghostty_render_state_row_iterator_next_dirty(t.rowIt, vtScratch)) {
          dv = new DataView(vt.memory.buffer);
          m8 = new Uint8Array(vt.memory.buffer);
          const y = dv.getUint16(vtScratch, true);
          dv.setUint32(rselAt, 8, true);
          let selStart = 0xffff, selEnd = 0xffff;
          if (vt.ghostty_render_state_row_get(t.rowIt, 4, rselAt) === 0) {
            selStart = dv.getUint16(rselAt + 4, true);
            selEnd = dv.getUint16(rselAt + 6, true);
          }
          u16(y);
          u16(selStart);
          u16(selEnd);
          const cellCountAt = at;
          u16(0);
          let cellCount = 0;

          dv.setUint32(vtScratch, t.cells, true);
          if (vt.ghostty_render_state_row_get(t.rowIt, 3, vtScratch) === 0) {
            let col = 0;
            while (vt.ghostty_render_state_row_cells_next(t.cells)) {
              const cellX = col++;
              let wide = 0;
              if (vt.ghostty_render_state_row_cells_get(t.cells, 1, vtScratch) === 0) {
                const raw = dv.getBigUint64(vtScratch, true);
                wide = Number((raw >> wideShift) & 3n);
              }
              if (wide === 2 || wide === 3) continue;

              dv.setUint32(gbufAt, utf8At, true);
              dv.setUint32(gbufAt + 4, 64, true);
              dv.setUint32(gbufAt + 8, 0, true);
              let glen = vt.ghostty_render_state_row_cells_get(t.cells, 9, gbufAt) === 0 ? dv.getUint32(gbufAt + 8, true) : 0;
              if (glen === 1 && m8[utf8At] === 0x20) glen = 0;
              if (glen > 64) glen = 64;

              m8.fill(0, styleAt, styleAt + 16);
              vt.ghostty_render_state_row_cells_get(t.cells, 2, styleAt);
              const sflagsBase = dv.getUint16(styleAt + 12, true) & 0x07ff;

              const cellFg = vt.ghostty_render_state_row_cells_get(t.cells, 6, vtScratch) === 0;
              const cfR = cellFg ? m8[vtScratch] : 0, cfG = cellFg ? m8[vtScratch + 1] : 0, cfB = cellFg ? m8[vtScratch + 2] : 0;
              const cellBg = vt.ghostty_render_state_row_cells_get(t.cells, 5, vtScratch) === 0;
              const cbR = cellBg ? m8[vtScratch] : 0, cbG = cellBg ? m8[vtScratch + 1] : 0, cbB = cellBg ? m8[vtScratch + 2] : 0;

              let cellUl = false, cuR = 0, cuG = 0, cuB = 0;
              const ulTag = m8[styleAt + 8];
              if (ulTag === 2) {
                cuR = m8[styleAt + 9]; cuG = m8[styleAt + 10]; cuB = m8[styleAt + 11];
                cellUl = true;
              } else if (ulTag === 1) {
                if (!havePalette) havePalette = vt.ghostty_render_state_get(t.render, 9, palAt) === 0;
                if (havePalette) {
                  const idx = m8[styleAt + 9] * 3;
                  cuR = m8[palAt + idx]; cuG = m8[palAt + idx + 1]; cuB = m8[palAt + idx + 2];
                  cellUl = true;
                }
              }

              if (glen === 0 && !cellBg && (sflagsBase & (16 | 64 | 128 | 0x0700)) === 0) continue;
              let sflags = sflagsBase;
              if (cellFg) sflags |= 2048;
              if (cellBg) sflags |= 4096;
              if (cellUl) sflags |= 8192;

              u16(cellX);
              u8(wide === 1 ? 2 : 1);
              u8(glen);
              u16(sflags);
              if (cellFg) { u8(cfR); u8(cfG); u8(cfB); }
              if (cellBg) { u8(cbR); u8(cbG); u8(cbB); }
              if (cellUl) { u8(cuR); u8(cuG); u8(cuB); }
              if (glen > 0) {
                need(glen);
                out.set(m8.subarray(utf8At, utf8At + glen), at);
                at += glen;
              }
              cellCount++;
            }
          }
          out[cellCountAt] = cellCount & 0xff;
          out[cellCountAt + 1] = (cellCount >>> 8) & 0xff;
          rowCount++;
        }
      }
    }

    vt.ghostty_render_state_clean(t.render);
    out[rowCountAt] = rowCount & 0xff;
    out[rowCountAt + 1] = (rowCount >>> 8) & 0xff;
    return out.slice(0, at);
  };

  H.termScroll = (id, kind, value) => {
    const t = terms.get(id);
    if (!t || !vt) return;
    const svAt = vtScratch + 88;
    const dv = new DataView(vt.memory.buffer);
    new Uint8Array(vt.memory.buffer).fill(0, svAt, svAt + 24);
    if (kind === 0) {
      dv.setInt32(svAt, 2, true);
      dv.setInt32(svAt + 8, value | 0, true);
    } else if (kind === 1) {
      dv.setInt32(svAt, 0, true);
    } else if (kind === 2) {
      dv.setInt32(svAt, 1, true);
    } else if (kind === 3) {
      dv.setInt32(svAt, 3, true);
      dv.setUint32(svAt + 8, value > 0 ? value >>> 0 : 0, true);
    } else {
      return;
    }
    vt.ghostty_terminal_scroll_viewport(t.term, svAt);
  };

  H.termSelect = (id, kind, x0, y0, x1, y1) => {
    const t = terms.get(id);
    if (!t || !vt) return 0;
    const selAt = vtScratch + 112;
    if (kind === 0) {
      t.dragActive = false;
      vt.ghostty_terminal_set(t.term, 22, 0);
      return 0;
    }
    if (kind === 4) {
      t.dragActive = false;
      new Uint8Array(vt.memory.buffer).fill(0, selAt, selAt + 20);
      return vt.ghostty_terminal_select_all(t.term, selAt) === 0 && vt.ghostty_terminal_set(t.term, 22, selAt) === 0 ? 1 : 0;
    }
    const dv = new DataView(vt.memory.buffer);
    const m8 = new Uint8Array(vt.memory.buffer);
    vt.ghostty_terminal_get(t.term, 1, vtScratch);
    const cols = Math.max(1, dv.getUint16(vtScratch, true));
    vt.ghostty_terminal_get(t.term, 2, vtScratch);
    const rows = Math.max(1, dv.getUint16(vtScratch, true));
    const clamp = (v, lim) => (v <= 0 ? 0 : v >= lim ? lim - 1 : v | 0);
    const cx0 = clamp(x0, cols), cy0 = clamp(y0, rows);
    const cx1 = clamp(x1, cols), cy1 = clamp(y1, rows);

    const p0At = vtScratch + 40;
    const p1At = vtScratch + 64;
    const optAt = vtScratch + 136;
    m8.fill(0, p0At, p0At + 48);
    dv.setInt32(p0At, 1, true);
    dv.setUint16(p0At + 8, cx0, true);
    dv.setUint32(p0At + 12, cy0, true);

    if (kind === 2 || kind === 3) {
      t.dragActive = false;
      m8.fill(0, optAt, optAt + 24);
      if (vt.ghostty_terminal_grid_ref(t.term, p0At, optAt + 4) !== 0) return 0;
      dv.setUint32(optAt, kind === 2 ? 20 : 24, true);
      m8.fill(0, selAt, selAt + 20);
      const rc = kind === 2
        ? vt.ghostty_terminal_select_word(t.term, optAt, selAt)
        : vt.ghostty_terminal_select_line(t.term, optAt, selAt);
      return rc === 0 && vt.ghostty_terminal_set(t.term, 22, selAt) === 0 ? 1 : 0;
    }

    if (kind === 1) {
      if (!t.dragActive || t.dragX0 !== x0 || t.dragY0 !== y0) {
        const sbAt = vtScratch + 16;
        dv.setBigUint64(sbAt + 8, 0n, true);
        vt.ghostty_terminal_get(t.term, 9, sbAt);
        const sbOff = Number(dv.getBigUint64(sbAt + 8, true) & 0xffffffffn) >>> 0;
        t.dragX0 = x0;
        t.dragY0 = y0;
        t.dragScreenX0 = cx0;
        t.dragScreenY0 = sbOff + cy0;
        t.dragActive = true;
      }
      m8.fill(0, p0At, p0At + 48);
      dv.setInt32(p0At, 2, true);
      dv.setUint16(p0At + 8, t.dragScreenX0, true);
      dv.setUint32(p0At + 12, t.dragScreenY0 >>> 0, true);
      dv.setInt32(p1At, 1, true);
      dv.setUint16(p1At + 8, cx1, true);
      dv.setUint32(p1At + 12, cy1, true);
      m8.fill(0, selAt, selAt + 20);
      if (vt.ghostty_terminal_grid_ref(t.term, p0At, selAt) !== 0) return 0;
      if (vt.ghostty_terminal_grid_ref(t.term, p1At, selAt + 8) !== 0) return 0;
      return vt.ghostty_terminal_set(t.term, 22, selAt) === 0 ? 1 : 0;
    }
    return 0;
  };

  function vtReadRenderText(t, selOnly) {
    if (vt.ghostty_render_state_update(t.render, t.term) !== 0) return '';
    let dv = new DataView(vt.memory.buffer);
    let m8 = new Uint8Array(vt.memory.buffer);
    dv.setUint32(vtScratch, t.rowIt, true);
    if (vt.ghostty_render_state_get(t.render, 4, vtScratch) !== 0) return '';
    const rselAt = vtScratch + 256;
    const gbufAt = vtScratch + 176;
    const utf8At = vtScratch + 192;
    const wideShift = BigInt(vtWideLsb);
    const lines = [];
    while (vt.ghostty_render_state_row_iterator_next(t.rowIt)) {
      dv = new DataView(vt.memory.buffer);
      m8 = new Uint8Array(vt.memory.buffer);
      let s0 = 0, s1 = 0xfffe;
      if (selOnly) {
        dv.setUint32(rselAt, 8, true);
        if (vt.ghostty_render_state_row_get(t.rowIt, 4, rselAt) !== 0) continue;
        s0 = dv.getUint16(rselAt + 4, true);
        s1 = dv.getUint16(rselAt + 6, true);
      }
      dv.setUint32(vtScratch, t.cells, true);
      if (vt.ghostty_render_state_row_get(t.rowIt, 3, vtScratch) !== 0) continue;
      let col = 0;
      let line = '';
      while (vt.ghostty_render_state_row_cells_next(t.cells)) {
        const cx = col++;
        if (cx < s0 || cx > s1) continue;
        if (vt.ghostty_render_state_row_cells_get(t.cells, 1, vtScratch) === 0) {
          const wide = Number((dv.getBigUint64(vtScratch, true) >> wideShift) & 3n);
          if (wide === 2 || wide === 3) continue;
        }
        dv.setUint32(gbufAt, utf8At, true);
        dv.setUint32(gbufAt + 4, 64, true);
        dv.setUint32(gbufAt + 8, 0, true);
        const glen = vt.ghostty_render_state_row_cells_get(t.cells, 9, gbufAt) === 0 ? dv.getUint32(gbufAt + 8, true) : 0;
        line += glen > 0 ? utf8Decode(m8.subarray(utf8At, utf8At + Math.min(glen, 64))) : ' ';
      }
      lines.push(line.replace(/ +$/, ''));
    }
    while (!selOnly && lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
    return lines.join('\n');
  }

  H.termText = (id, sel) => {
    const t = terms.get(id);
    if (!t || !vt) return '';
    const selAt = vtScratch + 112;
    if (sel !== 0 && vt.ghostty_terminal_get(t.term, 31, selAt) !== 0) return '';
    // Use formatter for selections if compiled into Wasm; for sel===0 (current viewport) or prebuilt wasm32 without
    // formatter, read viewport rows cleanly from render state so scrollback history is not dumped into "Copy Screen".
    if (sel !== 0 && vt.ghostty_formatter_terminal_new && vt.ghostty_formatter_terminal_new(0, vtScratch, t.term) === 0) {
      let dv = new DataView(vt.memory.buffer);
      let m8 = new Uint8Array(vt.memory.buffer);
      const fmt = dv.getUint32(vtScratch, true);
      m8[vtScratch] = 1;
      vt.ghostty_formatter_set(fmt, 3, vtScratch);
      vt.ghostty_formatter_set(fmt, 2, vtScratch);
      vt.ghostty_formatter_set(fmt, 4, selAt);
      let s = '';
      if (vt.ghostty_formatter_format_alloc(fmt, 0, vtScratch, vtScratch + 4) === 0) {
        dv = new DataView(vt.memory.buffer);
        m8 = new Uint8Array(vt.memory.buffer);
        const ptr = dv.getUint32(vtScratch, true);
        const len = dv.getUint32(vtScratch + 4, true);
        if (ptr && len) s = utf8Decode(m8.subarray(ptr, ptr + len));
        vt.ghostty_free(0, ptr, len);
      }
      vt.ghostty_formatter_free(fmt);
      return s;
    }
    return vtReadRenderText(t, sel !== 0);
  };

  H.termMouse = (id, action, button, mods, x, y, w, h, cw, ch) => {
    const t = terms.get(id);
    if (!t || !vt || !t.mouse || !t.mouseEv) return new Uint8Array(0);
    if (action !== 2 || !t.mouseSynced) {
      vt.ghostty_mouse_encoder_set_from_terminal(t.mouse, t.term);
      t.mouseSynced = true;
    }
    if (button >= 1 && button <= 3) {
      if (action === 0) t.mouseButtons |= 1 << button;
      else if (action === 1) t.mouseButtons &= ~(1 << button);
    }
    const dv = new DataView(vt.memory.buffer);
    const m8 = new Uint8Array(vt.memory.buffer);
    m8[vtScratch] = t.mouseButtons !== 0 ? 1 : 0;
    vt.ghostty_mouse_encoder_set(t.mouse, 4, vtScratch);

    const szAt = vtScratch + 264;
    m8.fill(0, szAt, szAt + 36);
    dv.setUint32(szAt, 36, true);
    dv.setUint32(szAt + 4, w > 0 ? w : 1, true);
    dv.setUint32(szAt + 8, h > 0 ? h : 1, true);
    dv.setUint32(szAt + 12, cw > 0 ? cw : 1, true);
    dv.setUint32(szAt + 16, ch > 0 ? ch : 1, true);
    vt.ghostty_mouse_encoder_set(t.mouse, 3, szAt);

    vt.ghostty_mouse_event_set_action(t.mouseEv, action === 1 ? 1 : action === 2 ? 2 : 0);
    if (button >= 1 && button <= 11) vt.ghostty_mouse_event_set_button(t.mouseEv, button);
    else vt.ghostty_mouse_event_clear_button(t.mouseEv);
    vt.ghostty_mouse_event_set_mods(t.mouseEv, mods & 0x0f);
    const posAt = vtScratch + 432;
    dv.setFloat32(posAt, x < 0 ? 0 : x, true);
    dv.setFloat32(posAt + 4, y < 0 ? 0 : y, true);
    vt.ghostty_mouse_event_set_position(t.mouseEv, posAt);

    const outAt = vtScratch + 304;
    dv.setUint32(vtScratch, 0, true);
    if (vt.ghostty_mouse_encoder_encode(t.mouse, t.mouseEv, outAt, 128, vtScratch) !== 0) return new Uint8Array(0);
    const written = new DataView(vt.memory.buffer).getUint32(vtScratch, true);
    if (!written) return new Uint8Array(0);
    return new Uint8Array(vt.memory.buffer).slice(outAt, outAt + written);
  };

  H.termClose = (id) => {
    const t = terms.get(id);
    if (!t || !vt) return;
    if (t.mouseEv) vt.ghostty_mouse_event_free(t.mouseEv);
    if (t.mouse) vt.ghostty_mouse_encoder_free(t.mouse);
    vt.ghostty_render_state_row_cells_free(t.cells);
    vt.ghostty_render_state_row_iterator_free(t.rowIt);
    vt.ghostty_render_state_free(t.render);
    vt.ghostty_terminal_free(t.term);
    terms.delete(id);
  };

  H.run = (title, frame, pointer, wheel, key, text) => {
    document.title = title;
    canvas = document.getElementById('c');
    ta = document.getElementById('ime');
    canvas.addEventListener('webglcontextlost', contextLost);
    canvas.addEventListener('webglcontextrestored', () => inWin(0, contextRestored));
    setupGL();
    setupInput();
    setupPage();
    // (the page's window, 0: what it keeps is put here as another's frame or input is handled, winUse)
    wins[0] = { wid: 0, win: window, closed: false, closing: false, wake: wakes0, texs: new Map(), under: null,
      coverBoxes: [], takePresses: null };
    // the windows opened beside the page go with it
    window.addEventListener('pagehide', () => {
      for (let i = 1; i < MB_WINS; i++) {
        const s = wins[i];
        if (s && !s.closed) { slotGone(s, false); try { s.win.close(); } catch (e) { /* gone already */ } }
      }
    });
    // Remember what every key told the app, including one received with a modifier already held.
    modifiersSaid = 0;
    cb = { frame, pointer, wheel, key: (code, mods) => { modifiersSaid = mods; key(code, mods); }, text };
    window.__mb = cb;
    resize();
    // (the app's first frame once the host knows what it decodes and whether its terminal Wasm is beside it)
    (termAsked ? Promise.all([h264Asked, termAsked]) : h264Asked).then(() => {
      known = true;
      H.requestFrame();
    });
  };

  // ---- windows (@hostapi.windows_in_process, window_open_id …; host_js.mbt's windows) ----
  // A window of the run beside the page is a popup of the same origin, opened by the page itself (window.open of
  // about:blank), so it is the same program, core and memory as the page: its own canvas, WebGL 2 context, textarea and
  // input, drawn and handled as the page is, each frame and event of it handed to the app with it in place (winUse:
  // the globals of the drawing and the input above are that window's while it is, the page's put back after;
  // H.windows(4) says which, as window_slots.mbt's in_host_window reads it). A WebGL texture is its context's alone:
  // the glyph atlas, the run's, is put in every window's texture of it as a glyph is drawn (H.glyphPut), and a window
  // opened later copies as much of the page's as is filled; a picture decoded or a stream's frame shown is the page's
  // texture, copied into a window's own as that window first draws it (slotTex). A window the person closes (its
  // pagehide) is let go of and the app told (outside OUTSIDE_WINDOW, -1), between its events; one the app closes
  // (H.windows(3)) is not told again. Its id is not given to another till that is told.
  // Ops: 0 whether windows open here (1, or 0: a run to a declared moment, one rendering, a page that cannot open one),
  // 1 open one (`what`: JSON {role, title, w, h, minW, minH}, each optional; its id, 0 if none opened), 2 bring `wid` to
  // the front (1, 0 gone), 3 close `wid`, 4 the window handled now, 5 set `wid`'s title (-1: the window handled now).
  const OUTSIDE_WINDOW = 17;
  // (where a window of a role was as it last closed, in this run: the next of that role opens there)
  const rolesKept = new Map();
  function winSave(s) {
    Object.assign(s, {
      canvas, gl, vs, prog, progs, progFlat, ufVp, progGen, progNow, post, adProg, vao, instBuf, atlasTex, ta, U, PU, ADU,
      cssW, cssH, dpr, rectLeft, rectTop, rectValid, sizeDirty, sizeObserver,
      lv, lvW, lvH, bdTex, glassSlots, glassSlotsClock, adTex, adFb, adCur, adSlots, adLastTime, adFrameSerial, adSettling, adRaf, lastN, lastR, lastG, lastB, lastF32,
      cv, cvOk, target, dirty, dirtyWhole, dirtyTold, missing, drewMissing, cutOn,
      segsTex, segsRows, segsHad, segsHadRows, uploadedFor, imeActive, composing, taHad, imeKind, viewLayer,
      under, coverBoxes, takePresses, doc, hostWin, glassIdle,
    });
  }
  function winLoad(s) {
    ({
      canvas, gl, vs, prog, progs, progFlat, ufVp, progGen, progNow, post, adProg, vao, instBuf, atlasTex, ta, U, PU, ADU,
      cssW, cssH, dpr, rectLeft, rectTop, rectValid, sizeDirty, sizeObserver,
      lv, lvW, lvH, bdTex, glassSlots, glassSlotsClock, adTex, adFb, adCur, adSlots, adLastTime, adFrameSerial, adSettling, adRaf, lastN, lastR, lastG, lastB, lastF32,
      cv, cvOk, target, dirty, dirtyWhole, dirtyTold, missing, drewMissing, cutOn,
      segsTex, segsRows, segsHad, segsHadRows, uploadedFor, imeActive, composing, taHad, imeKind, viewLayer,
      under, coverBoxes, takePresses, doc, hostWin, glassIdle,
    } = s);
  }
  // window `wid` put in place; false where it is gone (nothing of it is handled)
  function winUse(wid) {
    if (wid === winActive) return true;
    const to = wins[wid], from = wins[winActive];
    if (!to || !from || (wid !== 0 && to.closed)) return false;
    winSave(from);
    winLoad(to);
    winActive = wid;
    return true;
  }
  // `f` done as window `wid`, the one in place before put back after
  function inWin(wid, f) {
    if (wid === winActive) return f();
    const back = winActive;
    if (!winUse(wid)) return undefined;
    try { return f(); } finally { winUse(back); }
  }
  const mainGl = () => (winActive === 0 || !wins[0] ? gl : wins[0].gl);
  const liveSlot = (wid) => {
    const s = wid > 0 && wid < MB_WINS ? wins[wid] : null;
    return s && !s.closed && !s.closing ? s : null;
  };
  const windowsHere = () => shotAt < 0 && !globalThis.__mbrender && typeof window !== 'undefined' &&
    typeof window.open === 'function';

  // A texture of `g`'s read back (premultiplied RGBA, its first row first), or null.
  function texPixels(g, tex, w, h) {
    if (!g || !tex || w <= 0 || h <= 0 || g.isContextLost()) return null;
    const was = g.getParameter(g.FRAMEBUFFER_BINDING);
    const fb = g.createFramebuffer();
    g.bindFramebuffer(g.FRAMEBUFFER, fb);
    g.framebufferTexture2D(g.FRAMEBUFFER, g.COLOR_ATTACHMENT0, g.TEXTURE_2D, tex, 0);
    let px = null;
    if (g.checkFramebufferStatus(g.FRAMEBUFFER) === g.FRAMEBUFFER_COMPLETE) {
      px = new Uint8Array(w * h * 4);
      g.readPixels(0, 0, w, h, g.RGBA, g.UNSIGNED_BYTE, px);
    }
    g.bindFramebuffer(g.FRAMEBUFFER, was);
    g.deleteFramebuffer(fb);
    return px;
  }
  function newTex() {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }
  // The texture of picture or stream `tid` (`im`: images' or streams' entry, its page's texture ready) in window `s`,
  // in place now: made of the page's as it first draws it, a stream's again at each frame shown since. (On texture
  // unit 1, which drawFrame binds it to next: the others hold the atlas, the capture and the shapes' pieces.)
  function slotTex(s, tid, im) {
    if (!s || !gl) return null;
    let e = s.texs.get(tid);
    if (tid > STREAM_TEX) {
      if (!im.shown) return null;
      const gen = im.shownGen || 0;
      if (e && e.gen === gen) return e.tex;
      gl.activeTexture(gl.TEXTURE1);
      if (!e) { e = { tex: newTex(), gen: -1 }; s.texs.set(tid, e); }
      gl.bindTexture(gl.TEXTURE_2D, e.tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, im.shown);
      e.gen = gen;
      return e.tex;
    }
    if (e) return e.tex;
    const px = texPixels(wins[0].gl, im.tex, im.w, im.h);
    if (!px) return null;
    gl.activeTexture(gl.TEXTURE1);
    const tex = newTex();
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, im.w, im.h, 0, gl.RGBA, gl.UNSIGNED_BYTE, px);
    s.texs.set(tid, { tex, gen: 0 });
    return tex;
  }
  // a picture or stream let go: each window's texture of it too
  function slotsForget(tid) {
    if (!winsOpen) return;
    for (let i = 1; i < MB_WINS; i++) {
      const s = wins[i], e = s && s.texs.get(tid);
      if (!e) continue;
      s.texs.delete(tid);
      try { (i === winActive ? gl : s.gl).deleteTexture(e.tex); } catch (err) { /* its context gone */ }
    }
  }
  // The atlas of the window in place (just made, or given back after its context was lost) made what the page's
  // holds: as much of it as is filled copied.
  function slotAtlas() {
    if (!atlasUsedW || !atlasUsedH || !wins[0]) return;
    const px = texPixels(wins[0].gl, wins[0].atlasTex, atlasUsedW, atlasUsedH);
    if (!px) return;
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, atlasTex);
    gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, atlasUsedW, atlasUsedH, gl.RGBA, gl.UNSIGNED_BYTE, px);
  }

  // window `s` let go of (the person closed it, or the app, or the page goes), the page in place; told to the app
  // (`tell`) between events, its id kept from another window till then
  function slotGone(s, tellApp) {
    if (s.closed) return;
    if (winActive === s.wid) winUse(0);
    s.closed = true;
    winsOpen--;
    try {
      const w = s.win.innerWidth, h = s.win.innerHeight;
      if (s.role && w > 0 && h > 0) rolesKept.set(s.role, { w, h, left: s.win.screenX, top: s.win.screenY });
    } catch (e) { /* gone already */ }
    try { if (s.raf) s.win.cancelAnimationFrame(s.raf); } catch (e) { /* gone already */ }
    s.raf = 0;
    try { if (s.sizeObserver) s.sizeObserver.disconnect(); } catch (e) { /* gone already */ }
    for (const e of s.texs.values()) { try { s.gl.deleteTexture(e.tex); } catch (err) { /* its context gone */ } }
    s.texs.clear();
    // (all else its context holds, then the context itself: a closed popup's is not let go of while the page holds it)
    const sg = s.gl;
    if (sg) {
      try {
        for (const t of [s.atlasTex, s.segsTex]) if (t) sg.deleteTexture(t);
        for (const l of s.lv || []) { sg.deleteTexture(l.t); sg.deleteFramebuffer(l.fb); }
        for (const gs of s.glassSlots || []) {
          if (gs.bt) { sg.deleteFramebuffer(gs.bfb); sg.deleteTexture(gs.bt); }
        }
        if (s.cv) { sg.deleteTexture(s.cv.t); sg.deleteFramebuffer(s.cv.fb); }
        if (s.instBuf) sg.deleteBuffer(s.instBuf);
        if (s.vao) sg.deleteVertexArray(s.vao);
        for (const kp of s.progs || []) if (kp && kp.p) sg.deleteProgram(kp.p);
        if (s.progFlat) sg.deleteProgram(s.progFlat);
        if (s.post) sg.deleteProgram(s.post);
        if (s.vs) sg.deleteShader(s.vs);
        const loser = sg.getExtension('WEBGL_lose_context');
        if (loser) loser.loseContext();
      } catch (err) { /* its context gone */ }
    }
    Object.assign(s, {
      gl: null, vs: null, prog: null, progs: new Array(MB_KINDS + 1).fill(null), progFlat: null, ufVp: null,
      progGen: 0, progNow: null, post: null, vao: null, instBuf: null, atlasTex: null, segsTex: null, segsHad: null,
      lv: null, lvW: 0, lvH: 0, bdTex: null, glassSlots: makeGlassSlots(), glassSlotsClock: 0,
      adProg: null, ADU: {}, adTex: [null, null], adFb: [null, null], adCur: 0, adSlots: makeAdSlots(),
      adLastTime: 0, adFrameSerial: 0, adSettling: false, adRaf: 0, lastN: 0, lastR: 0, lastG: 0, lastB: 0, lastF32: null,
      cv: null, cvOk: false, target: null,
    });
    // (the views it showed, the app's still where it keeps them: out of its document, placed again where it next shows
    // one, H.viewPlace)
    for (const v of views.values()) {
      if (v.wid !== s.wid) continue;
      v.clip.remove();
      v.layer = null;
      v.seen = null;
      if (v.kind === 3 && v.port) { v.port.close(); v.port = null; }
    }
    if (!tellApp) {
      if (wins[s.wid] === s) wins[s.wid] = null;
      return;
    }
    queueMicrotask(() => {
      if (wins[s.wid] === s) wins[s.wid] = null;
      if (outside) outside(OUTSIDE_WINDOW, s.wid, -1);
      H.requestFrame();
    });
  }

  // a frame of each window beside the page that has none asked for yet, at its own display's next
  function slotFrames() {
    for (let i = 1; i < MB_WINS; i++) {
      const s = wins[i];
      if (!s || s.closed || s.closing || s.pending) continue;
      if (s.win.closed) { slotGone(s, true); continue; }
      s.pending = true;
      s.raf = s.win.requestAnimationFrame(() => tickSlot(s));
    }
  }
  function tickSlot(s) {
    s.pending = false;
    s.raf = 0;
    if (s.closed || s.closing) return;
    if (s.win.closed) { slotGone(s, true); return; }
    if (!cb || window.__done !== undefined) return;
    inWin(s.wid, () => {
      resize();
      inFrame = true;
      const t = performance.now();
      s.wake.at = -1;
      buildingFor = t;
      try {
        cb.frame(cssW, Math.max(1, cssH), dpr, t);
      } finally {
        buildingFor = -1;
        inFrame = false;
      }
    });
  }

  // A window opened beside the page for `what` (op 1): its id, 0 where the browser opened none (its popups blocked),
  // gave one of another origin or no WebGL 2 there.
  function windowOpen(what) {
    if (!windowsHere() || !wins[0] || !cb) return 0;
    let wid = 1;
    while (wid < MB_WINS && wins[wid]) wid++;
    if (wid >= MB_WINS) return 0;
    let spec = {};
    if (what.startsWith('{')) {
      try {
        const v = JSON.parse(what);
        if (v && typeof v === 'object') spec = v;
      } catch (e) { /* not JSON: what it shows, said to the app alone */ }
    }
    const num = (v) => (typeof v === 'number' && v > 0 && Number.isFinite(v) ? Math.round(v) : 0);
    const role = typeof spec.role === 'string' ? spec.role : '';
    const kept = role ? rolesKept.get(role) : null;
    const w = kept ? kept.w : num(spec.w) || Math.round(cssW || 900);
    const h = kept ? kept.h : num(spec.h) || Math.round(cssH || 700);
    const minW = num(spec.minW), minH = num(spec.minH);
    let left = kept ? kept.left : null, top = kept ? kept.top : null;
    // (one of the same role open: the new one a step down and right of it)
    for (let i = 1; i < MB_WINS; i++) {
      const s = liveSlot(i);
      if (!s || !role || s.role !== role) continue;
      try { left = s.win.screenX + 28; top = s.win.screenY + 28; } catch (e) { /* gone already */ }
    }
    const place = left === null || top === null ? '' : `,left=${Math.round(left)},top=${Math.round(top)}`;
    let child = null;
    try { child = window.open('about:blank', '', `popup=yes,width=${w},height=${h}${place}`); } catch (e) { child = null; }
    if (!child) return 0;
    let cdoc = null;
    try { cdoc = child.document; } catch (e) { cdoc = null; }
    if (!cdoc || !cdoc.body) {
      try { child.close(); } catch (e) { /* gone already */ }
      return 0;
    }
    // the page as the app's own page is (web/index.html): its ground, a canvas over all of it, the textarea at the caret
    const page = wins[0], pageDoc = document;
    let ground = '';
    try { ground = window.getComputedStyle(pageDoc.body).backgroundColor || ''; } catch (e) { ground = ''; }
    cdoc.title = String(spec.title || pageDoc.title || '');
    const style = cdoc.createElement('style');
    style.textContent = `html,body{margin:0;height:100%;overflow:hidden;overscroll-behavior:none;background:${ground || '#F5F5F7'}}` +
      'canvas{position:fixed;inset:0;width:100%;height:100%;touch-action:none;display:block;user-select:none;' +
      '-webkit-user-select:none;-webkit-touch-callout:none;z-index:1}' +
      'textarea{position:fixed;left:0;top:0;width:2px;height:20px;opacity:0;padding:0;border:0;resize:none;' +
      'overflow:hidden;font-size:16px;caret-color:transparent;color:transparent;background:transparent;outline:none}';
    (cdoc.head || cdoc.documentElement).appendChild(style);
    const ccanvas = cdoc.createElement('canvas'), cta = cdoc.createElement('textarea');
    const pageTa = winActive === 0 ? ta : page.ta;
    for (const a of pageTa && pageTa.attributes ? [...pageTa.attributes] : []) {
      if (a.name !== 'id' && a.name !== 'style') cta.setAttribute(a.name, a.value);
    }
    cdoc.body.appendChild(ccanvas);
    cdoc.body.appendChild(cta);
    const s = {
      wid, win: child, role, minW, minH, closed: false, closing: false, pending: false, raf: 0, wake: { at: -1 },
      texs: new Map(),
      canvas: ccanvas, gl: null, vs: null, prog: null, progs: new Array(MB_KINDS + 1).fill(null), progFlat: null,
      ufVp: null, progGen: 0, progNow: null, post: null, vao: null, instBuf: null, atlasTex: null, ta: cta,
      U: {}, PU: {}, cssW: 0, cssH: 0, dpr: child.devicePixelRatio || 1, rectLeft: 0, rectTop: 0, rectValid: false,
      sizeDirty: true, sizeObserver: null,
      lv: null, lvW: 0, lvH: 0, bdTex: null, glassSlots: makeGlassSlots(), glassSlotsClock: 0,
      adProg: null, ADU: {}, adTex: [null, null], adFb: [null, null], adCur: 0, adSlots: makeAdSlots(),
      adLastTime: 0, adFrameSerial: 0, adSettling: false, adRaf: 0, lastN: 0, lastR: 0, lastG: 0, lastB: 0, lastF32: null,
      cv: null, cvOk: false, target: null, dirty: [],
      dirtyWhole: false, dirtyTold: false, missing: false, drewMissing: false, cutOn: false, segsTex: null,
      segsRows: 0, segsHad: null, segsHadRows: 0, uploadedFor: -1, imeActive: false, composing: false, taHad: '',
      imeKind: 0, viewLayer: null, under: null, coverBoxes: [], takePresses: null, doc: cdoc, hostWin: child,
      glassIdle: 0,
    };
    wins[wid] = s;
    winsOpen++;
    let made = false;
    inWin(wid, () => {
      try {
        setupGL();
        slotAtlas();
        setupInput(child, wid);
        slotPage(s);
        made = true;
      } catch (e) {
        H.log('window ' + wid + ': ' + e);
      }
    });
    if (!made) {
      slotGone(s, false);
      try { child.close(); } catch (e) { /* gone already */ }
      return 0;
    }
    H.requestFrame();
    return wid;
  }
  // What a window beside the page answers of its own: the keys held, Escape kept from the browser, its least size, its
  // context lost and given back, its closing.
  function slotPage(s) {
    const win = s.win, wid = s.wid;
    const held = (e) => { modsNow = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0); };
    for (const name of ['pointerdown', 'pointermove', 'pointerup', 'keydown', 'keyup', 'wheel']) {
      win.addEventListener(name, held, { capture: true, passive: true });
    }
    win.addEventListener('blur', () => { modsNow = 0; });
    win.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !e.isComposing && e.keyCode !== 229) e.preventDefault();
    }, { capture: true });
    // (no smaller than the app said: a popup the page opened is one it may size)
    if (s.minW || s.minH) {
      win.addEventListener('resize', () => {
        const dw = Math.max(0, s.minW - win.innerWidth), dh = Math.max(0, s.minH - win.innerHeight);
        if (dw || dh) { try { win.resizeBy(dw, dh); } catch (e) { /* the browser's to refuse */ } }
      });
    }
    s.canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); });
    s.canvas.addEventListener('webglcontextrestored', () => inWin(wid, () => {
      setupGL();
      glassLost();
      segsTex = null; segsRows = 0; segsHad = null; segsHadRows = 0;
      uploadedFor = -1;
      s.texs.clear();
      slotAtlas();
      H.requestFrame();
    }));
    // (what the frames in it say goes to it, their parent)
    win.addEventListener('message', pageSaid);
    win.addEventListener('message', siteSaid);
    const gone = () => { if (!s.closed) slotGone(s, true); };
    win.addEventListener('pagehide', gone);
    win.addEventListener('unload', gone);
  }

  H.windows = (op, wid, what) => {
    if (op === 0) return windowsHere() ? 1 : 0;
    if (op === 1) return windowOpen(String(what || ''));
    if (op === 2) {
      if (wid === 0) { try { window.focus(); } catch (e) { /* the browser's to refuse */ } return 1; }
      const s = liveSlot(wid);
      if (!s) return 0;
      if (s.win.closed) { slotGone(s, true); return 0; }
      try { s.win.focus(); } catch (e) { /* the browser's to refuse */ }
      return 1;
    }
    if (op === 3) {
      const s = liveSlot(wid);
      if (!s) return 0;
      // (not in the middle of what is handled now, which may be that window's own frame: once it is over)
      s.closing = true;
      queueMicrotask(() => {
        slotGone(s, false);
        try { s.win.close(); } catch (e) { /* gone already */ }
      });
      return 1;
    }
    if (op === 4) return winActive;
    if (op === 5) {
      const to = wid < 0 ? winActive : wid;
      const title = String(what || '');
      if (to === 0) { document.title = title; return 1; }
      const s = liveSlot(to);
      if (!s) return 0;
      try { s.doc.title = title; } catch (e) { return 0; }
      return 1;
    }
    return 0;
  };

  // ---- the page round the app: the keys held, the system's bars, its title and colour, its history ----
  // The keys held down that change what a press does (@hostapi.mods_held: shift 1, control 2, alt 4, command 8, as a
  // key's own are told), as the last input the window had says them; none once it is left (blurred, hidden), where its
  // keys' going up is never seen.
  let modsNow = 0;
  H.modsHeld = () => modsNow;
  // How far the system reaches in over the canvas (a phone's notch, its home indicator: the page laid out under them,
  // index.html's viewport-fit=cover), as CSS's env(safe-area-inset-*) says, read off a probe padded by them; said on
  // the system's channel (@hostapi.system_said's `bars`) as it changes, none said while it is none. The soft keyboard
  // up, the app is laid out above it already (keyboardOver): nothing under it is the system's. (Said as it is found:
  // as the page's size is measured for a frame, resize, the app takes it between that frame and the next.)
  let barsProbe = null, barsSaid = '0,0,0,0', barsSetUp = false;
  function barsNow() {
    if (!barsProbe && document.body && document.body.appendChild) {
      barsProbe = document.createElement('div');
      const st = barsProbe.style;
      st.position = 'fixed';
      st.left = st.top = '0';
      st.width = st.height = '0';
      st.visibility = 'hidden';
      st.pointerEvents = 'none';
      st.paddingTop = 'env(safe-area-inset-top, 0px)';
      st.paddingRight = 'env(safe-area-inset-right, 0px)';
      st.paddingBottom = 'env(safe-area-inset-bottom, 0px)';
      st.paddingLeft = 'env(safe-area-inset-left, 0px)';
      document.body.appendChild(barsProbe);
    }
    if (!barsProbe || !window.getComputedStyle) return;
    const cs = window.getComputedStyle(barsProbe);
    const px = (v) => { const n = parseFloat(v); return n > 0 ? n : 0; };
    const top = px(cs.paddingTop), right = px(cs.paddingRight), left = px(cs.paddingLeft);
    const bottom = keyboardOver() > 0 ? 0 : px(cs.paddingBottom);
    const now = [top, bottom, left, right].join(',');
    if (now === barsSaid) return;
    barsSaid = now;
    H.post('system', JSON.stringify({ bars: { top, bottom, left, right } }));
  }
  H.barsNow = barsNow;
  // The page's history (@webpage.location, history_*: the app's calls `mbui.page.*`, host_js.mbt): where it is (its
  // path, query and fragment), a place put on or in place of the one it is at, and back; a place the browser went to
  // itself (its back and forward, a person's swipe) said on @webpage.history_channel as `{"location": …}`.
  const where = () => location.pathname + location.search + location.hash;
  H.historyLocation = where;
  H.historyPush = (to) => { history.pushState(null, '', to); };
  H.historyReplace = (to) => { history.replaceState(null, '', to); };
  H.historyBack = () => { history.back(); };
  // The page's title and the colour of what the browser draws round it (its bar, what shows past the page's edges):
  // @webpage.set_title, set_theme_color (a CSS colour; "" the page's own again).
  H.setPageTitle = (t) => { document.title = t; };
  // The page's own title as it loaded (its <title>, which the site names itself in: @webpage.loaded_title), kept from
  // before the run gave the page one.
  H.loadedTitle = () => loadedTitle;
  H.setThemeColor = (c) => {
    const meta = document.querySelector && document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', c);
    document.documentElement.style.backgroundColor = c;
    if (document.body) document.body.style.backgroundColor = c;
  };
  function setupPage() {
    const held = (e) => { modsNow = (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0); };
    for (const name of ['pointerdown', 'pointermove', 'pointerup', 'keydown', 'keyup', 'wheel']) {
      window.addEventListener(name, held, { capture: true, passive: true });
    }
    const none = () => { modsNow = 0; };
    window.addEventListener('blur', none);
    document.addEventListener('visibilitychange', none);
    // Escape is the app's (a layer closed): kept from the browser, which would take it for its own (leaving its full
    // screen, its focus), but not from an input method composing, whose Escape calls its words off. The app is still
    // told it (setupInput's keydown).
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !e.isComposing && e.keyCode !== 229) e.preventDefault();
    }, { capture: true });
    // (and as the page's size is measured again: resize)
    const barsChanged = () => { barsNow(); };
    window.addEventListener('orientationchange', barsChanged);
    window.visualViewport?.addEventListener('resize', barsChanged);
    window.addEventListener('popstate', () => { H.post('history', JSON.stringify({ location: where() })); });
    barsSetUp = true;
    barsNow();
  }

  // ---- mbui-render (src/render, scripts/render_web.mjs): no frames, no input ----
  // The canvas the size a window's would be, its text at the list's scale; a frame is drawn into it as any
  // (H.present) and read back at once (the drawing buffer is not kept past the task), top row first.
  H.renderInit = (w, h, scale) => {
    canvas = document.getElementById('c');
    cssW = w;
    cssH = h;
    dpr = scale;
    canvas.width = Math.round(w * scale);
    canvas.height = Math.round(h * scale);
    canvas.style.width = w + 'px';
    canvas.style.height = h + 'px';
    setupGL();
  };
  H.renderPixels = () => {
    const w = canvas.width, h = canvas.height, row = w * 4;
    const px = new Uint8Array(row * h), out = new Uint8Array(row * h);
    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    for (let y = 0; y < h; y++) out.set(px.subarray((h - 1 - y) * row, (h - y) * row), y * row);
    return { w, h, px: out };
  };
  H.renderInfo = () => {
    const x = gl.getExtension('WEBGL_debug_renderer_info');
    return x ? gl.getParameter(x.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  };

  // ---- the device beyond the window (src/hostapi/device.mbt) ----
  // A key catcher's focus (keyCatch: the textarea's keys, above); the soft keyboard's height (keyboardOver); the
  // clipboard read and written where the page may (navigator.clipboard: a picture of another kind made a PNG through a
  // canvas; refused or absent, read as empty); the screen kept on (a wake lock); no haptics.
  let catching = false;
  H.keyCatch = (on) => { catching = !!on; };
  // How far the soft keyboard reaches over the canvas's foot, in points. A phone's browser puts it over the page and
  // leaves the page's size alone (Safari always, Chrome since 108): only the visual viewport ends above it. None while
  // the page is pinched in (less of it shown, with no keyboard), nor for less than a point (a browser zoomed to a
  // fraction rounds the two apart).
  function keyboardOver() {
    // (a window beside the page is a desktop's: no soft keyboard over it)
    if (winActive !== 0) return 0;
    const v = window.visualViewport;
    if (!v || Math.abs(v.scale - 1) > 0.001) return 0;
    const over = cssH - v.height - v.offsetTop;
    return over >= 1 ? over : 0;
  }
  H.imeInset = keyboardOver;
  // A clipboard picture is an attachment, as a copied file is. Transports check their own bounds when sending it.
  const PNG_MAX = 1 << 30, SOURCE_MAX = 32 << 20, PIXELS_MAX = 16 * 1024 * 1024;
  const clips = new Map();
  let clipNext = 1;
  // what the browser's last paste had of files, for the app's read of the clipboard it set off (setupInput's `pasted`)
  let pasteHeld = null;
  // the command key of the system the page is on, as the app's ⌘V is said (@hostapi.keys_platform: ⌘ on Apple's)
  const keysCmd = () => (/mac|iphone|ipad|ipod/i.test((navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || '') ? 8 : 2);
  async function asPng(blob) {
    if (blob.type === 'image/png') return blob.size <= PNG_MAX ? [1, new Uint8Array(await blob.arrayBuffer())] : [2, null];
    if (blob.size > SOURCE_MAX) return [2, null];
    const bmp = await createImageBitmap(blob);
    const c = document.createElement('canvas');
    try {
      if (bmp.width * bmp.height > PIXELS_MAX) return [2, null];
      c.width = bmp.width;
      c.height = bmp.height;
      c.getContext('2d').drawImage(bmp, 0, 0);
    } finally {
      bmp.close();
    }
    const png = await new Promise((r) => c.toBlob(r, 'image/png'));
    if (!png) return [3, null];
    return png.size <= PNG_MAX ? [1, new Uint8Array(await png.arrayBuffer())] : [2, null];
  }
  H.clipRead = () => {
    const id = clipNext++;
    const r = { state: 0, text: '', picture: 0, png: new Uint8Array(0), files: [] };
    clips.set(id, r);
    const held = pasteHeld;
    pasteHeld = null;
    (async () => {
      const cl = navigator.clipboard;
      try {
        if (held) {
          // the paste's own files (the browser's paste event: H's `pasted`), read whole up to the most a file is read
          // (@hostapi.clip_file_max); its words beside them
          r.text = held.text;
          for (const f of held.files) {
            if (f.size > 1024 * 1024 * 1024) continue;
            r.files.push([f.name || (f.type.startsWith('image/') ? 'image.png' : 'file'), new Uint8Array(await f.arrayBuffer())]);
          }
        } else if (cl && cl.read) {
          for (const item of await cl.read()) {
            if (item.types.includes('text/plain')) r.text = await (await item.getType('text/plain')).text();
            const t = item.types.find((x) => x.startsWith('image/'));
            if (t) {
              try {
                const [k, b] = await asPng(await item.getType(t));
                r.picture = k;
                if (b) r.png = b;
              } catch (e) {
                r.picture = 3;
              }
            }
            break;
          }
        } else if (cl && cl.readText) {
          r.text = await cl.readText();
        }
      } catch (e) {
        // not allowed (no permission, the page not focused): read as empty
      }
      r.state = 1;
      tell(OUTSIDE_CLIP, id, 1);
      H.requestFrame();
    })();
    return id;
  };
  H.clipState = (id) => (clips.has(id) ? clips.get(id).state : -1);
  H.clipPicture = (id) => (clips.get(id) || {}).picture || 0;
  H.clipText = (id) => (clips.get(id) || {}).text || '';
  H.clipPng = (id) => (clips.get(id) || {}).png || new Uint8Array(0);
  // (a page reads files off the clipboard only in a paste: the browser's paste event has them, not navigator.clipboard)
  H.clipFiles = (id) => (clips.get(id) || {}).files?.length || 0;
  H.clipFileName = (id, i) => (clips.get(id) || {}).files?.[i]?.[0] || '';
  H.clipFile = (id, i) => (clips.get(id) || {}).files?.[i]?.[1] || new Uint8Array(0);
  H.clipEnd = (id) => { clips.delete(id); };
  H.clipSet = (text, png, label) => {
    const cl = navigator.clipboard;
    if (!cl) return;
    if (png && png.length && typeof ClipboardItem !== 'undefined') {
      cl.write([new ClipboardItem({ 'image/png': new Blob([png], { type: 'image/png' }) })]).catch(() => {});
    } else {
      cl.writeText(text).catch(() => {});
    }
  };
  let wake = null, wakeWanted = false;
  H.keepAwake = (on) => {
    wakeWanted = !!on;
    if (on && !wake && navigator.wakeLock) {
      navigator.wakeLock.request('screen').then((w) => {
        if (!wakeWanted) { w.release(); return; }
        wake = w;
        w.addEventListener('release', () => { if (wake === w) wake = null; });
      }).catch(() => {});
    } else if (!on && wake) {
      wake.release().catch(() => {});
      wake = null;
    }
  };
  // (a page lets its wake lock go when hidden: taken again as it is shown)
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && wakeWanted && !wake) H.keepAwake(true);
  });
  H.haptic = () => {};

  globalThis.__mbhost = H;
})();
