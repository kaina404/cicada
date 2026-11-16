'use strict';
(() => {
  // Safari may ignore viewport scale limits; block its native pinch gestures too.
  for (const name of ['gesturestart', 'gesturechange', 'gestureend']) {
    document.addEventListener(name, event => { event.preventDefault(); finish(true); }, {passive: false});
  }
  document.addEventListener('touchstart', event => {
    if (event.touches.length > 1) { event.preventDefault(); finish(true); }
  }, {passive: false});
  document.addEventListener('dblclick', event => event.preventDefault(), {passive: false});
  const $ = id => document.getElementById(id);
  const en = !navigator.language.toLowerCase().startsWith('zh');
  const t = (zh, english) => en ? english : zh;
  document.documentElement.lang = en ? 'en' : 'zh-CN';
  $('title').textContent = t('悬浮回答', 'Floating Answer');
  $('previous').textContent = t('↑ 上一句', '↑ Previous');
  $('next').textContent = t('↓ 下一句', '↓ Next');
  $('disconnect').textContent = t('断开', 'Disconnect');
  $('hint').textContent = t('声音从 Mac 耳机输出', 'Audio plays through Mac headphones');
  $('script').ariaLabel = t('回答稿件', 'Answer script');
  $('preview').alt = t('Mac 主屏幕实时画面', 'Live Mac main display');
  // Fragment credentials never travel in the HTTP URL, referrer, or browser storage.
  let token = new URLSearchParams(location.hash.slice(1)).get('token');
  history.replaceState(null, '', location.pathname);
  if (!/^[a-f0-9]{64}$/.test(token || '')) token = null;
  let refreshing = false;
  let state = {}, connected = false, stopped = !token, screenMode = false;
  let pollTimer, screenTimer, screenAbort, imageURL, queue = [], sending = false, active = null;
  let session = crypto.getRandomValues(new Uint32Array(1))[0] || 1, sequence = 0, gesture = 0, epoch = 0;
  let rendered = '', activeIndex = -1, lastScroll = '';
  const playback = {
    off: t('请在 Mac 开启陪读', 'Enable Read along on Mac'),
    headphones: t('请在 Mac 连接耳机', 'Connect headphones to Mac'),
    preparing: t('正在准备音频', 'Preparing audio'), guiding: t('Mac 耳机播放中', 'Playing through Mac headphones'),
    failed: t('松手后重试', 'Release and try again'), ended: t('已读完', 'Finished'), waiting: ''
  };
  function status(text) { $('connection').textContent = text; }
  function updateControls() {
    $('refresh').disabled = refreshing || !connected || !state.windowID || state.canRefreshAnswer !== true;
    $('refresh').textContent = refreshing ? t('正在请求…', 'Requesting…') : t('重新生成', 'Regenerate');
    const enabled = connected && state.windowID && state.canSelectSentence && !screenMode;
    $('previous').disabled = !enabled || !(state.currentSentence > 0);
    $('next').disabled = !enabled || !(state.currentSentence < state.sentences.length - 1);
    $('hold').disabled = !enabled || state.playback === 'headphones';
    $('hold').textContent = active?.playing ? t('松手暂停', 'Release to pause') : t('按住播放', 'Hold to play');
    $('hold').classList.toggle('holding', !!active?.playing);
    $('playback').textContent = connected ? (playback[state.playback] || '') : '';
    $('screenToggle').textContent = screenMode ? t('悬浮回答', 'Answer') : t('Mac 屏幕', 'Mac screen');
    $('screenToggle').disabled = !connected;
  }
  function showMessage(text) {
    $('message').textContent = text; $('message').hidden = false;
    $('workspace').hidden = true; $('screen').hidden = true;
  }
  function layout() {
    if (!connected) return;
    $('message').hidden = true;
    $('workspace').hidden = screenMode || !state.windowID;
    $('screen').hidden = !screenMode;
    if (!screenMode && !state.windowID) showMessage(t('请在 Mac 打开悬浮回答', 'Open Floating Answer on Mac'));
  }
  async function request(path, options = {}) {
    return fetch('/' + path, {...options, cache: 'no-store', redirect: 'error',
      headers: {'X-Cicada-Phone-Token': token, ...options.headers}});
  }
  function requestID() {
    // randomUUID requires HTTPS; getRandomValues also works on LAN HTTP pages.
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
    const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  }
  function resetInput() {
    if (active) { clearTimeout(active.delay); clearInterval(active.heartbeat); }
    active = null; updateControls();
  }
  function forget(text) {
    finish(true); stopped = true; connected = false; epoch++; queue = [];
    token = null; state = {}; $('refreshStatus').textContent = ''; clearTimeout(pollTimer); stopScreen();
    $('sentences').replaceChildren(); rendered = ''; updateControls(); showMessage(text); status(t('未连接', 'Disconnected'));
  }
  function offline() {
    resetInput(); epoch++; queue = []; connected = false; state = {};
    $('sentences').replaceChildren(); rendered = ''; stopScreen(); updateControls();
    $('refreshStatus').textContent = '';
    status(t('正在重新连接 Mac', 'Reconnecting to Mac'));
    showMessage(t('请确认手机和 Mac 在同一 Wi-Fi 下。', 'Keep your phone and Mac on the same Wi-Fi.'));
  }
  function packet(kind, x = 0, y = 0) {
    const bytes = new ArrayBuffer(19), view = new DataView(bytes);
    view.setUint8(0, kind); view.setUint32(1, session, true); view.setUint32(5, sequence = (sequence + 1) >>> 0, true);
    view.setUint16(9, gesture, true); view.setFloat32(11, x, true); view.setFloat32(15, y, true);
    return {bytes, kind, window: state.windowID, epoch};
  }
  function enqueue(kind, x = 0, y = 0) {
    if (!token || !state.windowID) return;
    const next = packet(kind, x, y), previous = queue.at(-1);
    if ((kind === 0x21 || kind === 0x22) && previous?.kind === kind) queue[queue.length - 1] = next;
    else queue.push(next);
    drain();
  }
  async function drain() {
    if (sending) return;
    sending = true;
    try {
      while (queue.length && token) {
        const next = queue.shift();
        if (next.epoch !== epoch) continue;
        try {
          const response = await request('floating-control', {method:'POST', body:next.bytes,
            headers:{'X-Cicada-Window':next.window}, signal:AbortSignal.timeout(1200), keepalive:true});
          if (next.epoch !== epoch || stopped) continue;
          if (response.status === 403) { forget(t('配对已失效，请在 Mac 重新扫码。', 'Pairing expired. Scan a new code on Mac.')); break; }
          if (response.status === 409) { resetInput(); epoch++; queue = []; continue; }
          if (response.status !== 204) throw new Error('control');
        } catch { if (next.epoch === epoch && !stopped) { offline(); break; } }
      }
    } finally { sending = false; }
  }
  function begin(kind) {
    if (!connected || !state.windowID || active || document.hidden) return false;
    gesture = (gesture + 1) & 65535;
    active = {kind, window:state.windowID}; enqueue(0x20); return true;
  }
  function finish(cancel = false, x = 0, y = 0) {
    if (!active) return;
    queue = queue.filter(p => p.kind !== 0x21 && p.kind !== 0x22);
    enqueue(cancel ? 0x25 : 0x23, x, y); resetInput();
  }
  function select(delta) {
    if (!state.canSelectSentence || !begin('sentence')) return;
    enqueue(0x26, 0, delta); finish();
  }
  $('refresh').onclick = async () => {
    if ($('refresh').disabled) return;
    finish(true);
    const windowID = state.windowID, credential = token;
    refreshing = true; updateControls();
    $('refreshStatus').textContent = '';
    // Separate from the gesture queue: a stuck audio/control request cannot block fallback.
    try {
      const response = await request('floating-refresh', {method: 'POST',
        headers: {'X-Cicada-Window': windowID, 'X-Cicada-Request': requestID()},
        signal: AbortSignal.timeout(2500)});
      if (stopped || token !== credential || state.windowID !== windowID) return;
      if (response.status === 403) { forget(t('配对已失效，请重新扫码。', 'Pairing expired. Scan again.')); return; }
      $('refreshStatus').textContent = response.status === 204
        ? t('已请求最新答案', 'New answer requested')
        : response.status === 409 ? t('暂无可回答的问题，请确认 Mac 正在听取问题。', 'No question available. Check listening on Mac.')
        : t('请求失败，请重试或更新 Mac。', 'Request failed. Retry or update Mac.');
    } catch {
      if (!stopped && token === credential && state.windowID === windowID)
        $('refreshStatus').textContent = t('请求超时，请重试', 'Request timed out. Try again');
    } finally { refreshing = false; updateControls(); }
  };
  $('previous').onclick = () => select(-1);
  $('next').onclick = () => select(1);
  function startHold() {
    if ($('hold').disabled || !begin('hold')) return;
    active.delay = setTimeout(() => {
      if (active?.kind !== 'hold') return;
      active.playing = true; enqueue(0x22);
      active.heartbeat = setInterval(() => {
        if (!document.hidden && active?.playing) enqueue(0x22);
        else finish(true);
      }, 100); updateControls();
    }, 400);
  }
  function pointerSurface(element, down, move, up) {
    element.addEventListener('pointerdown', event => {
      if (event.button !== 0 || !event.isPrimary || active) return;
      down(event);
      if (active) { active.pointer = event.pointerId; element.setPointerCapture(event.pointerId); event.preventDefault(); }
    });
    element.addEventListener('pointermove', event => { if (active?.pointer === event.pointerId) move(event); });
    element.addEventListener('pointerup', event => { if (active?.pointer === event.pointerId) up(event); });
    for (const name of ['pointercancel', 'lostpointercapture']) element.addEventListener(name, event => {
      if (active?.pointer === event.pointerId) finish(true);
    });
    element.addEventListener('contextmenu', event => event.preventDefault());
  }
  pointerSurface($('hold'), startHold, () => {}, () => finish());
  $('hold').addEventListener('keydown', event => {
    if ((event.code === 'Space' || event.code === 'Enter') && !event.repeat) { event.preventDefault(); startHold(); }
  });
  $('hold').addEventListener('keyup', event => { if (event.code === 'Space' || event.code === 'Enter') { event.preventDefault(); finish(); } });
  $('hold').addEventListener('blur', () => finish(true));
  window.addEventListener('blur', () => finish(true));
  window.addEventListener('pagehide', () => { finish(true); stopScreen(); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { finish(true); stopScreen(); }
    else if (!stopped) { clearTimeout(pollTimer); poll(); }
  });
  // Rebuild text only on content changes. UTF-16 offsets match the Mac's NSRange.
  function render() {
    const signature = JSON.stringify([state.answerID, state.sentences]);
    if (signature !== rendered) {
      rendered = signature; activeIndex = -1; lastScroll = '';
      $('sentences').replaceChildren(...(state.sentences || []).map(text => {
        const row = document.createElement('div'); row.className = 'sentence'; row.textContent = text; return row;
      }));
      if (!state.sentences?.length) $('sentences').textContent = t('正在等待回答', 'Waiting for an answer');
    }
    const rows = $('sentences').children, index = state.currentSentence;
    if (index !== activeIndex) {
      if (rows[activeIndex]) rows[activeIndex].textContent = state.sentences[activeIndex];
      activeIndex = index;
    }
    Array.from(rows).forEach((row, n) => { row.classList.toggle('active', n === index); row.classList.toggle('read', n < index); });
    const row = rows[index]; if (!row) return;
    const text = state.sentences[index], word = state.word;
    let target = row;
    if (word && Number.isInteger(word.location) && Number.isInteger(word.length) && word.location >= 0 && word.length > 0 && word.location + word.length <= text.length) {
      const prefix = document.createElement('span'), current = document.createElement('span');
      prefix.textContent = text.slice(0, word.location); prefix.className = word.fillsPrefix ? 'filled' : '';
      current.textContent = text.slice(word.location, word.location + word.length); current.className = 'word';
      current.style.setProperty('--progress', `${Math.max(0, Math.min(1, word.progress || 0)) * 100}%`);
      row.replaceChildren(prefix, current, document.createTextNode(text.slice(word.location + word.length))); target = current;
    } else row.textContent = text;
    const top = target.getBoundingClientRect().top - $('script').getBoundingClientRect().top + $('script').scrollTop - 18;
    const scrollKey = `${index}:${Math.round(top)}`;
    if (lastScroll !== scrollKey && !$('workspace').hidden) {
      lastScroll = scrollKey; $('script').scrollTo({top: Math.max(0, top), behavior:matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
    }
  }
  let polling = false;
  async function poll() {
    if (stopped || document.hidden || polling) return;
    polling = true;
    try {
      const response = await request('floating-answer', {signal:AbortSignal.timeout(1800)});
      if (stopped || document.hidden) return;
      if (response.status === 403) { forget(t('配对已失效，请在 Mac 重新扫码。', 'Pairing expired. Scan a new code on Mac.')); return; }
      if (!response.ok) throw new Error('state');
      const next = await response.json();
      if (stopped || document.hidden) return;
      if (next.windowID !== state.windowID || next.answerID !== state.answerID) { finish(true); epoch++; queue = []; }
      state = next; connected = true; status(t('Mac 已连接', 'Mac connected'));
      updateControls(); layout(); render(); if (screenMode) startScreen();
    } catch { if (!stopped && !document.hidden) offline(); }
    finally {
      polling = false;
      if (!stopped) pollTimer = setTimeout(poll, connected ? (state.playback === 'guiding' ? 50 : 150) : 1000);
    }
  }
  function clearImage() { $('preview').removeAttribute('src'); if (imageURL) URL.revokeObjectURL(imageURL); imageURL = null; }
  function stopScreen() { clearTimeout(screenTimer); screenTimer = null; screenAbort?.abort(); screenAbort = null; clearImage(); }
  function startScreen() { if (!screenTimer && !screenAbort && screenMode && connected && !document.hidden) loadScreen(); }
  async function loadScreen() {
    screenTimer = null;
    const controller = new AbortController(); screenAbort = controller;
    const timeout = setTimeout(() => controller.abort(), 2500);
    try {
      const response = await request('mac-screen', {signal:controller.signal});
      if (!screenMode || document.hidden || stopped || controller.signal.aborted) return;
      if (response.status === 403) { forget(t('配对已失效，请在 Mac 重新扫码。', 'Pairing expired. Scan a new code on Mac.')); return; }
      if (response.status === 200) {
        const blob = await response.blob();
        if (controller.signal.aborted || !screenMode || stopped) return;
        const old = imageURL; imageURL = URL.createObjectURL(blob); $('preview').src = imageURL;
        if (old) URL.revokeObjectURL(old); $('screenStatus').textContent = '';
      } else if (response.status !== 204) {
        clearImage(); $('screenStatus').textContent = response.status === 409 || response.status === 404
          ? t('请在 Mac 悬浮回答的手机菜单开启屏幕共享。', 'Enable screen sharing in the Mac Floating Answer phone menu.')
          : t('无法获取画面，请检查 Mac 屏幕录制权限。', 'Check Screen Recording permission on Mac.');
      }
    } catch { if (!controller.signal.aborted) { clearImage(); $('screenStatus').textContent = t('正在重新获取画面', 'Reconnecting to screen'); } }
    finally {
      clearTimeout(timeout);
      if (screenAbort === controller) {
        screenAbort = null;
        if (screenMode && connected && !stopped && !document.hidden) screenTimer = setTimeout(loadScreen, imageURL ? 125 : 500);
      }
    }
  }
  $('screenToggle').onclick = () => {
    finish(true); screenMode = !screenMode; stopScreen(); lastScroll = '';
    $('screenStatus').textContent = t('正在获取 Mac 画面', 'Loading Mac screen');
    updateControls(); layout(); if (screenMode) startScreen(); else render();
  };
  $('disconnect').onclick = () => forget(t('已断开。请扫描 Mac 上的配对码重新连接。', 'Disconnected. Scan the pairing code on Mac to reconnect.'));
  window.addEventListener('resize', () => { lastScroll = ''; if (connected) render(); });
  updateControls();
  if (!token) showMessage(t('请在 Mac 悬浮回答底部点手机图标，用系统相机扫描配对码。', 'Click the phone icon in Mac Floating Answer, then scan the code with your phone camera.'));
  else { showMessage(t('正在连接 Mac', 'Connecting to Mac')); poll(); }
})();
