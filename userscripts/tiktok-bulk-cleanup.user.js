// ==UserScript==
// @name         TikTok Bulk Cleanup (Unlike + Unfollow)
// @namespace    local.tiktok.bulk-cleanup
// @version      1.0.0
// @description  Bulk-remove your own TikTok likes (authenticated web API) and unfollow accounts (UI automation). For your own logged-in account only.
// @author       local
// @match        https://www.tiktok.com/*
// @grant        none
// @run-at       document-idle
// @noframes
// ==/UserScript==

/*
 * HOW IT WORKS
 * ------------
 * Likes    : calls the same authenticated web API the site uses
 *            (GET  /api/favorite/item_list/  -> list your liked videos)
 *            (POST /api/commit/item/digg/    -> remove a like)
 * Following: drives the real "Following" buttons in the Following modal.
 *            TikTok's follow/unfollow endpoint requires request signing
 *            (X-Bogus), so UI automation is the reliable path.
 *
 * BEFORE STARTING
 * ---------------
 *   - Be logged in at https://www.tiktok.com
 *   - Likes mode    : open your own profile once (https://www.tiktok.com/@you)
 *                     so the script can read your secUid, then reload.
 *   - Following mode: open your Following list (profile -> Following count)
 *                     so the rows are on screen. Leave the modal open.
 *
 * WARNING: bulk actions can trip TikTok's rate limiting and may violate its
 * terms of service. Nothing changes unless you press Start. Keep the tab
 * focused, keep the cap low on the first run, and stop if you see a captcha.
 */

(function () {
  'use strict';

  const CONFIG = {
    // Randomized delay between individual actions (milliseconds).
    minDelayMs: 1200,
    maxDelayMs: 3000,
    // Pause between pages when listing likes (milliseconds).
    pagePauseMs: 4000,
    // Safety cap per run. null = unlimited. Keep a cap, especially at first.
    maxActionsPerRun: 300,
    // Abort after this many consecutive failures.
    maxConsecutiveFailures: 5,
    // Button labels that mean "you currently follow this account".
    followingLabels: ['following', 'friends', '已关注', '正在关注', 'seguindo', 'abonniert'],
    // Labels on the confirmation popover that actually perform the unfollow.
    confirmLabels: ['unfollow', '取消关注', '取消關注', 'dejar de seguir', 'ne plus suivre', 'entfolgen'],
    // How long to wait for a confirmation control to appear (milliseconds).
    confirmTimeoutMs: 2500,
  };

  const state = {
    running: false,
    paused: false,
    mode: 'likes',
    count: 0,
    failed: 0,
    consecutiveFailures: 0,
    status: 'Idle',
    log: [],
  };

  // ---------------------------------------------------------------------------
  // Small utilities
  // ---------------------------------------------------------------------------

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function randomDelay() {
    const { minDelayMs: a, maxDelayMs: b } = CONFIG;
    return a + Math.random() * Math.max(0, b - a);
  }

  function log(message) {
    const line = `[${new Date().toLocaleTimeString()}] ${message}`;
    state.log.push(line);
    if (state.log.length > 250) state.log.splice(0, state.log.length - 250);
    const el = document.getElementById('tbc-log');
    if (el) {
      el.value = state.log.join('\n');
      el.scrollTop = el.scrollHeight;
    }
  }

  function getCookie(name) {
    const parts = ('; ' + (document.cookie || '')).split('; ' + name + '=');
    return parts.length === 2 ? (parts[1].split(';')[0] || '').trim() : '';
  }

  function capReached() {
    return CONFIG.maxActionsPerRun != null && state.count >= CONFIG.maxActionsPerRun;
  }

  async function sleepPausable(ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      if (!state.running) return;
      while (state.paused && state.running) await sleep(200);
      if (!state.running) return;
      await sleep(Math.min(250, Math.max(0, end - Date.now())));
    }
  }

  // ---------------------------------------------------------------------------
  // Resolving the logged-in account
  // ---------------------------------------------------------------------------

  function rehydrationData() {
    try {
      const el = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
      if (!el) return null;
      return JSON.parse(el.textContent || '{}');
    } catch (e) {
      return null;
    }
  }

  function viewerUniqueId() {
    const data = rehydrationData();
    const scope = data && data.__DEFAULT_SCOPE__;
    if (scope) {
      const ctx = scope['webapp.app-context'];
      if (ctx && ctx.user && ctx.user.uniqueId) return ctx.user.uniqueId;
      const ud = scope['webapp.user-detail'];
      if (ud && ud.userInfo && ud.userInfo.user && ud.userInfo.user.uniqueId) {
        return ud.userInfo.user.uniqueId;
      }
    }
    return null;
  }

  async function viewerSecUid() {
    const data = rehydrationData();
    const scope = data && data.__DEFAULT_SCOPE__;
    if (scope) {
      const ud = scope['webapp.user-detail'];
      if (ud && ud.userInfo && ud.userInfo.user && ud.userInfo.user.secUid) {
        return ud.userInfo.user.secUid;
      }
      const ctx = scope['webapp.app-context'];
      if (ctx && ctx.user && ctx.user.secUid) return ctx.user.secUid;
    }
    try {
      const sigi = window.SIGI_STATE;
      const users = sigi && sigi.UserModule && sigi.UserModule.users;
      if (users) {
        const first = users[Object.keys(users)[0]];
        if (first && first.secUid) return first.secUid;
      }
    } catch (e) {
      /* ignore */
    }
    const uniqueId = viewerUniqueId();
    if (uniqueId) {
      try {
        const url = `https://www.tiktok.com/api/user/detail/?uniqueId=${encodeURIComponent(uniqueId)}&aid=1988`;
        const res = await fetch(url, { credentials: 'include' });
        const json = await res.json();
        const user = json && json.userInfo && json.userInfo.user;
        if (user && user.secUid) return user.secUid;
      } catch (e) {
        /* ignore */
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Likes: authenticated web API
  // ---------------------------------------------------------------------------

  async function fetchLikedPage(secUid, cursor) {
    const params = new URLSearchParams({
      aid: '1988',
      count: '30',
      coverFormat: '2',
      cursor: String(cursor),
      needPinnedItemIds: 'true',
      post_item_list_request_type: '0',
      secUid: secUid,
    });
    const res = await fetch(`https://www.tiktok.com/api/favorite/item_list/?${params}`, {
      credentials: 'include',
      headers: { accept: '*/*' },
    });
    if (!res.ok) throw new Error(`list request failed: HTTP ${res.status}`);
    const json = await res.json();
    if (json.status_code !== 0) throw new Error(`list error: ${JSON.stringify(json).slice(0, 200)}`);
    const items = (json.itemList || []).map((e) => ({
      id: e.id,
      author: `@${(e.author && e.author.uniqueId) || ''}`,
      desc: e.desc || '',
    }));
    return {
      items,
      hasMore: !!json.hasMore,
      cursor: json.cursor != null ? String(json.cursor) : null,
    };
  }

  const FINGERPRINT = {
    device_id: String(7000000000000000000n + BigInt(Math.floor(Math.random() * 1e18))),
  };

  async function unlikeItem(awemeId, csrfToken) {
    const verifyFp = getCookie('s_v_web_id');
    const msToken = getCookie('msToken');
    const params = new URLSearchParams({
      aid: '1988',
      app_language: 'en',
      app_name: 'tiktok_web',
      aweme_id: String(awemeId),
      browser_language: 'en',
      browser_name: 'Mozilla',
      browser_online: 'true',
      browser_platform: 'Win32',
      browser_version: navigator.userAgent || '',
      channel: 'tiktok_web',
      cookie_enabled: 'true',
      data_collection_enabled: 'true',
      device_id: FINGERPRINT.device_id,
      device_platform: 'web_pc',
      focus_state: 'true',
      from_page: 'video',
      history_len: '2',
      is_fullscreen: 'false',
      is_page_visible: 'true',
      os: 'windows',
      referer: '',
      region: 'US',
      screen_height: String(window.screen ? window.screen.height : 864),
      screen_width: String(window.screen ? window.screen.width : 1536),
      type: '0',
      tz_name: Intl.DateTimeFormat().resolvedOptions().timeZone,
      user_is_login: 'true',
    });
    if (verifyFp) params.set('verifyFp', verifyFp);
    if (msToken) params.set('msToken', msToken);

    const res = await fetch(`https://www.tiktok.com/api/commit/item/digg/?${params}`, {
      method: 'POST',
      credentials: 'include',
      headers: {
        accept: '*/*',
        'content-type': 'application/x-www-form-urlencoded',
        origin: 'https://www.tiktok.com',
        referer: window.location.href || 'https://www.tiktok.com/',
        'tt-csrf-token': csrfToken,
      },
      body: '',
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const raw = (await res.text()).trim();
    if (!raw) return; // some deployments return an empty 200 on success
    let json;
    try {
      json = JSON.parse(raw);
    } catch (e) {
      throw new Error(`non-JSON response: ${raw.slice(0, 80)}`);
    }
    if (json.status_code !== 0) throw new Error(JSON.stringify(json).slice(0, 200));
  }

  async function unlikeEverything() {
    const secUid = await viewerSecUid();
    if (!secUid) {
      throw new Error('Could not detect your secUid. Open your own profile page, reload, and try again.');
    }
    const csrf = getCookie('tt_csrf_token');
    if (!csrf) {
      throw new Error('Could not read the tt_csrf_token cookie. Make sure you are logged in, then reload the page.');
    }

    let cursor = '0';
    let pageNum = 0;
    for (;;) {
      if (!state.running) return;
      setStatus('Listing liked videos…');
      const page = await fetchLikedPage(secUid, cursor);
      pageNum++;
      if (!page.items.length) {
        log('No liked videos returned — nothing left to remove.');
        break;
      }
      log(`Page ${pageNum}: ${page.items.length} liked videos.`);

      for (const item of page.items) {
        if (!state.running) return;
        while (state.paused && state.running) await sleep(200);
        if (!state.running) return;
        if (capReached()) {
          log(`Reached the ${CONFIG.maxActionsPerRun}-action cap. Stopping.`);
          return;
        }
        try {
          await unlikeItem(item.id, csrf);
          state.count++;
          state.consecutiveFailures = 0;
          setStatus(`Unliked ${state.count}${CONFIG.maxActionsPerRun ? '/' + CONFIG.maxActionsPerRun : ''}`);
          log(`Unliked ${item.author} ${item.id}`);
        } catch (e) {
          state.failed++;
          state.consecutiveFailures++;
          log(`FAILED unlike ${item.id}: ${e.message}`);
          if (state.consecutiveFailures >= CONFIG.maxConsecutiveFailures) {
            log('Too many consecutive failures — stopping. You may be rate limited; wait ~1 hour.');
            return;
          }
        }
        updateStats();
        await sleepPausable(randomDelay());
      }

      if (!page.hasMore || !page.cursor) break;
      cursor = page.cursor;
      log('Pausing before the next page…');
      await sleepPausable(CONFIG.pagePauseMs);
    }
  }

  // ---------------------------------------------------------------------------
  // Following: UI automation against the Following modal
  // ---------------------------------------------------------------------------

  function isVisible(el) {
    return !!(el && el.getClientRects().length > 0);
  }

  function rowFor(button) {
    let el = button;
    for (let i = 0; i < 6 && el; i++) {
      el = el.parentElement;
      if (!el) break;
      if (el.querySelector('a[href*="/@"]')) return el;
    }
    return null;
  }

  function usernameFor(button) {
    const row = rowFor(button);
    if (!row) return null;
    const link = row.querySelector('a[href*="/@"]');
    if (!link) return null;
    const match = link.getAttribute('href').match(/\/@([A-Za-z0-9._]+)/);
    return match ? match[1] : null;
  }

  function isFollowingButton(button) {
    if (!isVisible(button) || !rowFor(button)) return false;
    const text = ((button.innerText || '') + ' ' + (button.getAttribute('aria-label') || ''))
      .trim()
      .toLowerCase();
    if (!text) return false;
    if (/^follow\b/.test(text) && !/following/.test(text)) return false; // "Follow" = not followed
    return CONFIG.followingLabels.some((label) => text === label || text.split(/\s+/).includes(label));
  }

  function findFollowingButtons() {
    const found = [];
    for (const button of document.querySelectorAll('button, [role="button"]')) {
      if (isFollowingButton(button)) found.push(button);
    }
    return found;
  }

  async function clickConfirm(button) {
    const end = Date.now() + CONFIG.confirmTimeoutMs;
    while (Date.now() < end) {
      // Some versions unfollow directly: the row button stops saying "Following".
      if (button && !isFollowingButton(button)) return true;
      for (const el of document.querySelectorAll('button, [role="button"], div[role="menuitem"]')) {
        if (!isVisible(el)) continue;
        const text = (el.innerText || '').trim().toLowerCase();
        if (CONFIG.confirmLabels.some((label) => text === label)) {
          el.click();
          return true;
        }
      }
      await sleep(180);
    }
    return false;
  }

  function scrollListFor(button) {
    let el = button.parentElement;
    while (el && el !== document.body) {
      const style = getComputedStyle(el);
      const scrollable =
        /(auto|scroll)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 20;
      if (scrollable) {
        const before = el.scrollTop;
        el.scrollTop = el.scrollHeight;
        return el.scrollTop !== before;
      }
      el = el.parentElement;
    }
    window.scrollTo(0, document.body.scrollHeight);
    return true;
  }

  async function unfollowEverything() {
    const processed = new Set();
    let idlePasses = 0;

    for (;;) {
      if (!state.running) return;
      while (state.paused && state.running) await sleep(200);
      if (!state.running) return;

      const buttons = findFollowingButtons();
      let actedThisPass = false;

      for (const button of buttons) {
        if (!state.running) return;
        while (state.paused && state.running) await sleep(200);
        if (!state.running) return;
        if (capReached()) {
          log(`Reached the ${CONFIG.maxActionsPerRun}-action cap. Stopping.`);
          return;
        }

        const username = usernameFor(button);
        if (username && processed.has(username)) continue;

        button.scrollIntoView({ block: 'center' });
        await sleep(250);
        if (!isFollowingButton(button)) continue;

        button.click();
        const confirmed = await clickConfirm(button);
        if (username) processed.add(username);

        if (confirmed) {
          state.count++;
          state.consecutiveFailures = 0;
          log(`Unfollowed @${username || 'unknown'}`);
        } else {
          // Button may toggle directly, or a confirm dialog may still be loading.
          state.count++;
          state.consecutiveFailures = 0;
          log(`Clicked @${username || 'unknown'} (no confirmation control seen)`);
        }
        actedThisPass = true;
        updateStats();
        setStatus(`Unfollowed ${state.count}${CONFIG.maxActionsPerRun ? '/' + CONFIG.maxActionsPerRun : ''}`);
        await sleepPausable(randomDelay());
      }

      if (!actedThisPass) {
        idlePasses++;
        const scrolled = buttons.length ? scrollListFor(buttons[0]) : false;
        setStatus('Waiting for Following rows…');
        log(
          scrolled
            ? 'Scrolled the Following list to load more.'
            : 'No Following buttons found. Open your Following list (profile -> Following).'
        );
        if (idlePasses >= 20) {
          log('No progress after repeated passes — stopping.');
          return;
        }
        await sleepPausable(1500);
      } else {
        idlePasses = 0;
        if (buttons.length) scrollListFor(buttons[0]);
        await sleepPausable(600);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Panel UI
  // ---------------------------------------------------------------------------

  function setStatus(text) {
    state.status = text;
    const el = document.getElementById('tbc-status');
    if (el) el.textContent = text;
  }

  function updateStats() {
    const el = document.getElementById('tbc-stats');
    if (el) el.textContent = `Done: ${state.count} · Failed: ${state.failed}`;
  }

  function buildPanel() {
    if (document.getElementById('tbc-panel')) return;

    const style = document.createElement('style');
    style.textContent = `
      #tbc-panel { position: fixed; top: 16px; right: 16px; width: 320px;
        max-width: calc(100vw - 32px); background: #0d0d0d; color: #f2f2f2;
        border: 1px solid #2a2a2a; border-left: 3px solid #00f2ea; border-radius: 12px;
        box-shadow: 0 12px 40px rgba(0,0,0,.55); z-index: 2147483647;
        font: 13px/1.4 system-ui, -apple-system, sans-serif; overflow: hidden; }
      #tbc-panel .tbc-head { display: flex; justify-content: space-between; align-items: center;
        padding: 10px 12px; background: #161616; border-bottom: 1px solid #2a2a2a; cursor: move; }
      #tbc-panel .tbc-title { color: #00f2ea; font-weight: 600; font-size: 13px; }
      #tbc-panel .tbc-x { background: none; border: 0; color: #888; font-size: 18px; cursor: pointer; }
      #tbc-panel .tbc-body { padding: 12px; display: flex; flex-direction: column; gap: 8px; }
      #tbc-panel select { background: #1c1c1c; color: #f2f2f2; border: 1px solid #2a2a2a;
        border-radius: 8px; padding: 7px 8px; font-size: 13px; }
      #tbc-panel .tbc-row { display: flex; gap: 8px; }
      #tbc-panel button.tbc-btn { flex: 1; padding: 9px 10px; border: 0; border-radius: 8px;
        cursor: pointer; font-size: 13px; font-weight: 600; }
      #tbc-panel button.tbc-btn:disabled { opacity: .45; cursor: not-allowed; }
      #tbc-start { background: #ff0050; color: #fff; }
      #tbc-pause { background: #00f2ea; color: #0d0d0d; }
      #tbc-stop { background: #1c1c1c; color: #f2f2f2; border: 1px solid #2a2a2a; }
      #tbc-status { color: #e0e0e0; min-height: 18px; }
      #tbc-stats { color: #888; font-size: 12px; }
      #tbc-log { width: 100%; height: 130px; resize: vertical; background: #101010; color: #b9b9b9;
        border: 1px solid #2a2a2a; border-radius: 8px; font: 11px/1.4 ui-monospace, monospace;
        padding: 6px; box-sizing: border-box; }
      #tbc-note { color: #777; font-size: 11px; }
    `;
    document.head.appendChild(style);

    const panel = document.createElement('div');
    panel.id = 'tbc-panel';
    panel.innerHTML = `
      <div class="tbc-head">
        <span class="tbc-title">TikTok Bulk Cleanup</span>
        <button class="tbc-x" type="button" title="Close">×</button>
      </div>
      <div class="tbc-body">
        <select id="tbc-mode">
          <option value="likes">Remove all likes</option>
          <option value="following">Unfollow everyone</option>
        </select>
        <div class="tbc-row">
          <button id="tbc-start" class="tbc-btn" type="button">Start</button>
          <button id="tbc-pause" class="tbc-btn" type="button" disabled>Pause</button>
          <button id="tbc-stop" class="tbc-btn" type="button" disabled>Stop</button>
        </div>
        <div id="tbc-status">Idle</div>
        <div id="tbc-stats">Done: 0 · Failed: 0</div>
        <textarea id="tbc-log" readonly></textarea>
        <div id="tbc-note">Likes: open your own profile first. Following: open your Following list first.</div>
      </div>
    `;
    document.body.appendChild(panel);

    // Drag by the header.
    const head = panel.querySelector('.tbc-head');
    head.addEventListener('mousedown', (e) => {
      const rect = panel.getBoundingClientRect();
      const startX = e.clientX;
      const startY = e.clientY;
      panel.style.right = 'auto';
      panel.style.left = rect.left + 'px';
      panel.style.top = rect.top + 'px';
      const move = (ev) => {
        panel.style.left = Math.max(0, rect.left + ev.clientX - startX) + 'px';
        panel.style.top = Math.max(0, rect.top + ev.clientY - startY) + 'px';
      };
      const up = () => {
        document.removeEventListener('mousemove', move);
        document.removeEventListener('mouseup', up);
      };
      document.addEventListener('mousemove', move);
      document.addEventListener('mouseup', up);
    });

    panel.querySelector('.tbc-x').addEventListener('click', () => panel.remove());
    document.getElementById('tbc-start').addEventListener('click', start);
    document.getElementById('tbc-pause').addEventListener('click', () => {
      state.paused = !state.paused;
      document.getElementById('tbc-pause').textContent = state.paused ? 'Resume' : 'Pause';
      setStatus(state.paused ? 'Paused' : 'Running…');
    });
    document.getElementById('tbc-stop').addEventListener('click', () => {
      state.running = false;
      state.paused = false;
      setStatus('Stopping…');
    });
  }

  async function start() {
    if (state.running) return;
    const mode = document.getElementById('tbc-mode').value;
    const verb = mode === 'likes' ? 'remove ALL of your likes' : 'unfollow EVERYONE you follow';
    if (!window.confirm(`This will ${verb} in your logged-in TikTok session. Continue?`)) return;

    state.running = true;
    state.paused = false;
    state.mode = mode;
    state.count = 0;
    state.failed = 0;
    state.consecutiveFailures = 0;
    state.log = [];
    log(`Starting: ${mode}`);
    updateStats();
    setStatus('Running…');

    const startBtn = document.getElementById('tbc-start');
    const pauseBtn = document.getElementById('tbc-pause');
    const stopBtn = document.getElementById('tbc-stop');
    const modeSel = document.getElementById('tbc-mode');
    startBtn.disabled = true;
    modeSel.disabled = true;
    pauseBtn.disabled = false;
    stopBtn.disabled = false;
    pauseBtn.textContent = 'Pause';

    try {
      if (mode === 'likes') await unlikeEverything();
      else await unfollowEverything();
      setStatus(`Finished — ${state.count} done, ${state.failed} failed.`);
    } catch (e) {
      log(`Error: ${e.message || e}`);
      setStatus(`Error: ${e.message || e}`);
    } finally {
      state.running = false;
      state.paused = false;
      startBtn.disabled = false;
      modeSel.disabled = false;
      pauseBtn.disabled = true;
      stopBtn.disabled = true;
      updateStats();
    }
  }

  function boot() {
    if (!document.body) {
      setTimeout(boot, 300);
      return;
    }
    buildPanel();
  }

  boot();
})();
