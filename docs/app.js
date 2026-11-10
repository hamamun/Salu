(() => {
  'use strict';

  const SHARE_URL = 'https://hamamun.github.io/Salu/';

  // ── Media Queue Sample Items ────────────────────────────────────────────
  const QUEUE = [
    {
      title: 'Night City Timelapse — 4K HDR.mkv',
      sub: 'mpv · d3d11va · 10-band Movie EQ · OpenSubtitles ready',
      caption: '“Chrome only when you move. Everything else is cinema.”',
      duration: 2290, // 38:10
      position: 868,  // 14:28
      isLive: false,
    },
    {
      title: 'Midnight Echoes (24-bit FLAC).flac',
      sub: 'Audio Mode · ID3 cover art · .lrc synced lyrics active',
      caption: '[01:42.10] ♪ Neon rain drifts across the glass ♪',
      duration: 264,  // 04:24
      position: 102,
      isLive: false,
    },
    {
      title: 'World News HD · Live IPTV',
      sub: 'M3U8 Stream · Group: News · Inferred Country: US',
      caption: 'Live stream · timeline stays quiet with no buffering pulse',
      duration: 0,
      position: 0,
      isLive: true,
    },
  ];

  // Exact EQ curves from lib/core/tune/tune_presets.dart
  const EQ_PRESETS = [
    { key: 'movie', label: 'Movie (Video)', gains: [4, 3, 1, 0, 1, 2, 3, 4, 3, 2] },
    { key: 'flat', label: 'Flat', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
    { key: 'pop', label: 'Pop', gains: [1, 2, 3, 5, 3, 1, -1, -2, -1, 0] },
    { key: 'rock', label: 'Rock', gains: [5, 4, 3, 1, -2, -1, 2, 3, 4, 5] },
    { key: 'jazz', label: 'Jazz', gains: [4, 3, 1, 0, -2, -2, 0, 1, 2, 3] },
    { key: 'bass', label: 'Bass', gains: [10, 8, 6, 3, 0, -1, -2, -2, -1, 0] },
    { key: 'vocal', label: 'Vocal', gains: [-2, -3, -4, -2, 0, 3, 5, 4, 2, 0] },
    { key: 'vshape', label: 'V-Shape', gains: [8, 6, 3, 1, -2, -2, 1, 4, 7, 9] },
    { key: 'live', label: 'Live', gains: [3, 2, 1, 0, 2, 3, 4, 5, 6, 7] },
  ];

  // Exact bindings from lib/core/shortcuts/shortcut_registry.dart
  const SHORTCUTS = {
    player: [
      { action: 'Play / Pause', keys: 'Space' },
      { action: 'Stop (parks queue)', keys: 'S' },
      { action: 'Seek ±5 s (hold ramps)', keys: '← / →' },
      { action: 'Volume ±5 %', keys: '↑ / ↓' },
      { action: 'Mute / Unmute', keys: 'M' },
      { action: 'Toggle Mini Bar', keys: 'Ctrl+M' },
      { action: 'Toggle Playlist', keys: 'Ctrl+L' },
      { action: 'Toggle Tune / EQ', keys: 'Ctrl+E' },
      { action: 'Search Subtitles', keys: 'Ctrl+Shift+F' },
      { action: 'Subtitle Sync ±100 ms', keys: 'Z / X' },
      { action: 'Switch Player ⇄ Web', keys: 'Alt+W' },
      { action: 'Fullscreen', keys: 'F / F11' },
    ],
    mini: [
      { action: 'Exit Mini Bar', keys: 'Esc / Ctrl+M' },
      { action: 'Play / Pause', keys: 'Space' },
      { action: 'Stop (parks queue)', keys: 'S' },
      { action: 'Mute / Unmute', keys: 'M' },
      { action: 'Seek ±5 s', keys: '← / →' },
      { action: 'Volume ±5 %', keys: '↑ / ↓' },
      { action: 'Previous / Next', keys: 'PgUp / PgDn' },
      { action: 'Subtitle Sync ±100 ms', keys: 'Z / X' },
      { action: 'Subtitle Sync ±1 s', keys: 'Shift+Z / X' },
    ],
    web: [
      { action: 'New / Close Tab', keys: 'Ctrl+T / Ctrl+W' },
      { action: 'Focus Address Bar', keys: 'Ctrl+L / Alt+D' },
      { action: 'Back / Forward', keys: 'Alt+← / Alt+→' },
      { action: 'Reload / Hard Reload', keys: 'F5 / Ctrl+F5' },
      { action: 'History / Downloads', keys: 'Ctrl+H / Ctrl+J' },
      { action: 'Add Favourite / Hub', keys: 'Ctrl+D / Ctrl+Shift+O' },
      { action: 'Find in Page', keys: 'Ctrl+F' },
      { action: 'Zoom In / Out / Reset', keys: 'Ctrl+= / - / 0' },
      { action: 'Return to Player', keys: 'Alt+W' },
    ],
  };

  // ── State ───────────────────────────────────────────────────────────────
  const state = {
    index: 0,
    playing: true,
    stopped: false,
    position: QUEUE[0].position,
    volume: 68,
    muted: false,
    playlistOpen: false,
    openPillVisible: false,
    webMode: false,
    miniMode: false,
    osdTimer: null,
    toastTimer: null,
  };

  // ── Helpers ─────────────────────────────────────────────────────────────
  function formatClock(sec) {
    const s = Math.max(0, Math.floor(sec));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    const pad = (n) => String(n).padStart(2, '0');
    return `${pad(h)}:${pad(m)}:${pad(r)}`;
  }

  function flashOsd(text) {
    const osd = document.getElementById('osdCapsule');
    const osdText = document.getElementById('osdText');
    if (!osd || !osdText) return;
    osdText.textContent = text;
    osd.classList.add('is-visible');
    clearTimeout(state.osdTimer);
    state.osdTimer = setTimeout(() => {
      osd.classList.remove('is-visible');
    }, 1250);
  }
  window.__saluFlashOsd = flashOsd;

  function showPageToast(text) {
    const toast = document.getElementById('pageToast');
    const toastText = document.getElementById('pageToastText');
    if (!toast || !toastText) return;
    toastText.textContent = text;
    toast.classList.add('is-visible');
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => {
      toast.classList.remove('is-visible');
    }, 2400);
  }

  async function copyText(text, message) {
    try {
      await navigator.clipboard.writeText(text);
      showPageToast(message);
    } catch {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      showPageToast(message);
    }
  }

  // ── Render Mockup UI ────────────────────────────────────────────────────
  function renderPlayer() {
    const item = QUEUE[state.index];
    const ratio = item.isLive || item.duration === 0
      ? 0
      : Math.min(1, Math.max(0, state.position / item.duration));
    const pct = `${(ratio * 100).toFixed(2)}%`;

    document.getElementById('windowTitleText').textContent = item.title;
    document.getElementById('canvasTitleLine').textContent = state.stopped
      ? `${item.title} · Parked`
      : item.title;
    document.getElementById('canvasSubLine').textContent = state.stopped
      ? `Stop parked the queue at ${formatClock(state.position)} — press Play to resume`
      : item.sub;
    document.getElementById('sampleSubtitle').textContent = item.caption;
    document.getElementById('sampleSubtitle').style.opacity = state.stopped ? '0.2' : '1';
    document.getElementById('canvasScene').classList.toggle('is-stopped', state.stopped);

    document.getElementById('timeElapsed').textContent = item.isLive
      ? 'LIVE'
      : formatClock(state.stopped ? 0 : state.position);
    document.getElementById('timeTotal').textContent = item.isLive
      ? 'M3U8'
      : formatClock(item.duration);

    document.getElementById('seekFill').style.width = item.isLive ? '100%' : pct;
    document.getElementById('seekFill').style.opacity = item.isLive ? '0.28' : '1';
    document.getElementById('seekThumb').style.left = pct;
    document.getElementById('seekThumb').style.display = item.isLive || state.stopped ? 'none' : 'block';

    // Mini Bar sync
    document.getElementById('miniSeekFill').style.width = item.isLive ? '100%' : pct;
    document.getElementById('miniTitleText').textContent = item.title;

    // Play/Pause glyphs
    const pauseMarkup = '<line x1="7" y1="4.8" x2="7" y2="15.2"></line><line x1="13" y1="4.8" x2="13" y2="15.2"></line>';
    const playMarkup = '<polyline points="6.8,4.6 14.2,10 6.8,15.4"></polyline>';
    const isActuallyPlaying = state.playing && !state.stopped;
    document.getElementById('playPauseSvg').innerHTML = isActuallyPlaying ? pauseMarkup : playMarkup;
    document.getElementById('miniPlaySvg').innerHTML = isActuallyPlaying ? pauseMarkup : playMarkup;

    // Volume bar & Mute icon
    const volShown = state.muted ? 0 : state.volume;
    document.getElementById('volumeFill').style.width = `${volShown}%`;
    document.getElementById('volumePct').textContent = state.muted ? 'Muted' : `${state.volume}%`;
    const muteSvg = document.getElementById('muteSvg');
    if (state.muted || state.volume === 0) {
      muteSvg.innerHTML = '<polygon points="2.5,8 5.5,8 9,4.5 9,15.5 5.5,12 2.5,12"></polygon><line x1="12" y1="6.5" x2="17.5" y2="13.5"></line>';
    } else if (state.volume < 50) {
      muteSvg.innerHTML = '<polygon points="2.5,8 5.5,8 9,4.5 9,15.5 5.5,12 2.5,12"></polygon><path d="M12.2 7.2a4.2 4.2 0 0 1 0 5.6"></path>';
    } else {
      muteSvg.innerHTML = '<polygon points="2.5,8 5.5,8 9,4.5 9,15.5 5.5,12 2.5,12"></polygon><path d="M12.2 7.2a4.2 4.2 0 0 1 0 5.6"></path><path d="M14.8 5.2a7 7 0 0 1 0 9.6"></path>';
    }

    // Queue list
    const queueList = document.getElementById('queueList');
    queueList.innerHTML = '';
    QUEUE.forEach((q, idx) => {
      const row = document.createElement('div');
      row.className = `queue-row${idx === state.index ? ' is-playing' : ''}`;
      row.innerHTML = `
        <span style="width:12px; display:inline-flex; justify-content:center; color:${idx === state.index ? 'var(--accent)' : 'var(--text-2)'}">
          ${idx === state.index ? '▶' : '≡'}
        </span>
        <span class="queue-row-name">${q.title}</span>
        <span class="queue-row-dur tabular">${idx === state.index ? (q.isLive ? 'LIVE' : formatClock(q.duration)) : ''}</span>
      `;
      row.addEventListener('click', () => {
        selectTrack(idx);
      });
      queueList.appendChild(row);
    });
  }

  function selectTrack(idx) {
    state.index = idx;
    state.stopped = false;
    state.playing = true;
    state.position = QUEUE[idx].position;
    renderPlayer();
    flashOsd(`Playing · ${QUEUE[idx].title.split('—')[0].trim()}`);
  }

  function togglePlayPause() {
    if (state.stopped) {
      state.stopped = false;
      state.playing = true;
      renderPlayer();
      flashOsd(`Resumed · ${formatClock(state.position)}`);
      return;
    }
    state.playing = !state.playing;
    renderPlayer();
    flashOsd(state.playing ? `Play · ${formatClock(state.position)}` : `Paused · ${formatClock(state.position)}`);
  }

  function stopPlayback() {
    state.stopped = true;
    state.playing = false;
    renderPlayer();
    flashOsd(`Stopped · parked at ${formatClock(state.position)}`);
  }

  function seekDelta(sec) {
    const item = QUEUE[state.index];
    if (item.isLive || state.stopped) return;
    state.position = Math.max(0, Math.min(item.duration, state.position + sec));
    renderPlayer();
    flashOsd(`${sec > 0 ? '>> +' : '<< '}${sec}s · ${formatClock(state.position)}`);
  }

  function setMiniMode(enabled) {
    state.miniMode = enabled;
    const stage = document.getElementById('showcaseStage');
    const fullWin = document.getElementById('saluWindow');
    const miniWin = document.getElementById('miniBarWindow');
    const fullBtn = document.getElementById('shapeFullBtn');
    const miniBtn = document.getElementById('shapeMiniBtn');

    stage.classList.toggle('is-mini', enabled);
    fullWin.style.display = enabled ? 'none' : 'flex';
    miniWin.classList.toggle('is-active', enabled);
    fullBtn.classList.toggle('is-selected', !enabled);
    miniBtn.classList.toggle('is-selected', enabled);
  }

  function setWebMode(enabled) {
    state.webMode = enabled;
    if (enabled && state.playing) {
      state.playing = false; // Web mode pauses playback on entry
      renderPlayer();
    }
    document.getElementById('webSurface').classList.toggle('is-active', enabled);
    document.getElementById('modeWordPlayer').classList.toggle('is-lit', !enabled);
    document.getElementById('modeWordWeb').classList.toggle('is-lit', enabled);
    document.getElementById('enterMiniBtn').style.visibility = enabled ? 'hidden' : 'visible';
  }

  // ── EQ SVG Renderer ─────────────────────────────────────────────────────
  function renderEqCurve(presetKey) {
    const preset = EQ_PRESETS.find((p) => p.key === presetKey) || EQ_PRESETS[0];
    const svg = document.getElementById('eqSvg');
    const w = 600;
    const h = 170;
    const padX = 16;
    const padY = 18;
    const midY = h / 2;
    const stepX = (w - padX * 2) / (preset.gains.length - 1);

    const pts = preset.gains.map((g, i) => ({
      x: padX + i * stepX,
      y: midY - (g / 12) * (midY - padY),
    }));

    // Smooth cubic path
    let d = `M ${pts[0].x.toFixed(1)} ${pts[0].y.toFixed(1)}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[i];
      const p1 = pts[i + 1];
      const cx = (p0.x + p1.x) / 2;
      d += ` C ${cx.toFixed(1)} ${p0.y.toFixed(1)}, ${cx.toFixed(1)} ${p1.y.toFixed(1)}, ${p1.x.toFixed(1)} ${p1.y.toFixed(1)}`;
    }
    const areaD = `${d} L ${pts[pts.length - 1].x.toFixed(1)} ${midY} L ${pts[0].x.toFixed(1)} ${midY} Z`;

    const circles = pts
      .map((p) => `<circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="4" fill="var(--bg)" stroke="var(--accent)" stroke-width="2" />`)
      .join('');

    svg.innerHTML = `
      <defs>
        <linearGradient id="eqFillGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#4C9EEB" stop-opacity="0.28"/>
          <stop offset="100%" stop-color="#4C9EEB" stop-opacity="0.02"/>
        </linearGradient>
      </defs>
      <line x1="${padX}" y1="${midY}" x2="${w - padX}" y2="${midY}" stroke="var(--divider)" stroke-dasharray="4 4" stroke-width="1"/>
      <path d="${areaD}" fill="url(#eqFillGrad)"/>
      <path d="${d}" fill="none" stroke="var(--accent)" stroke-width="2.4" stroke-linecap="round"/>
      ${circles}
    `;

    const peak = preset.gains.reduce((acc, g) => (Math.abs(g) > Math.abs(acc) ? g : acc), 0);
    document.getElementById('eqPresetLabel').textContent = preset.label;
    document.getElementById('eqPeakLabel').textContent =
      `Peak ${peak >= 0 ? '+' : ''}${peak.toFixed(1)} dB · −12 to +12 dB`;
  }

  // ── Shortcuts Renderer ──────────────────────────────────────────────────
  function renderShortcuts(scope) {
    const grid = document.getElementById('shortcutGrid');
    const list = SHORTCUTS[scope] || SHORTCUTS.player;
    grid.innerHTML = list
      .map(
        (item) => `
        <div class="shortcut-item">
          <span>${item.action}</span>
          <kbd>${item.keys}</kbd>
        </div>`
      )
      .join('');
  }

  // ── Wire Events ─────────────────────────────────────────────────────────
  function init() {
    renderPlayer();
    renderEqCurve('movie');
    renderShortcuts('player');

    // Playback loop inside preview
    setInterval(() => {
      const item = QUEUE[state.index];
      if (state.playing && !state.stopped && !item.isLive && item.duration > 0) {
        state.position = (state.position + 1) % item.duration;
        renderPlayer();
      }
    }, 1000);

    // Transport buttons
    document.getElementById('playPauseBtn').addEventListener('click', togglePlayPause);
    document.getElementById('miniPlayBtn').addEventListener('click', togglePlayPause);
    document.getElementById('stopBtn').addEventListener('click', stopPlayback);
    document.getElementById('miniStopBtn').addEventListener('click', stopPlayback);
    document.getElementById('prevBtn').addEventListener('click', () => {
      selectTrack((state.index - 1 + QUEUE.length) % QUEUE.length);
    });
    document.getElementById('miniPrevBtn').addEventListener('click', () => {
      selectTrack((state.index - 1 + QUEUE.length) % QUEUE.length);
    });
    document.getElementById('nextBtn').addEventListener('click', () => {
      selectTrack((state.index + 1) % QUEUE.length);
    });
    document.getElementById('miniNextBtn').addEventListener('click', () => {
      selectTrack((state.index + 1) % QUEUE.length);
    });
    document.getElementById('seekBackBtn').addEventListener('click', () => seekDelta(-5));
    document.getElementById('seekFwdBtn').addEventListener('click', () => seekDelta(5));

    // Mute + Volume bar
    const toggleMute = () => {
      state.muted = !state.muted;
      renderPlayer();
      flashOsd(state.muted ? 'Muted' : `Volume ${state.volume}%`);
    };
    document.getElementById('muteBtn').addEventListener('click', toggleMute);
    document.getElementById('miniMuteBtn').addEventListener('click', toggleMute);

    const volBar = document.getElementById('volumeBar');
    volBar.addEventListener('click', (e) => {
      const rect = volBar.getBoundingClientRect();
      const pct = Math.round(Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)) * 100);
      state.volume = pct;
      state.muted = pct === 0;
      renderPlayer();
    });

    document.getElementById('miniWheel').addEventListener('click', () => {
      state.volume = state.volume >= 95 ? 25 : state.volume + 15;
      state.muted = false;
      renderPlayer();
      document.getElementById('miniTitleText').textContent = `Volume ${state.volume}%`;
      setTimeout(renderPlayer, 1100);
    });

    // Seek track scrub & hover chip
    const seekTrack = document.getElementById('seekTrack');
    const hoverChip = document.getElementById('hoverChip');
    seekTrack.addEventListener('mousemove', (e) => {
      const item = QUEUE[state.index];
      const rect = seekTrack.getBoundingClientRect();
      const frac = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
      hoverChip.style.left = `${(frac * 100).toFixed(1)}%`;
      hoverChip.textContent = item.isLive ? 'LIVE' : formatClock(frac * item.duration);
    });
    seekTrack.addEventListener('click', (e) => {
      const item = QUEUE[state.index];
      if (item.isLive) return;
      const rect = seekTrack.getBoundingClientRect();
      const frac = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
      state.stopped = false;
      state.position = Math.round(frac * item.duration);
      renderPlayer();
      flashOsd(`Seek · ${formatClock(state.position)}`);
    });

    // Open Media + -> x pill
    const openPlusBtn = document.getElementById('openPlusBtn');
    const openPill = document.getElementById('openPill');
    openPlusBtn.addEventListener('click', () => {
      state.openPillVisible = !state.openPillVisible;
      openPlusBtn.classList.toggle('is-open', state.openPillVisible);
      openPill.classList.toggle('is-open', state.openPillVisible);
    });
    openPill.querySelectorAll('[data-open-action]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.openPillVisible = false;
        openPlusBtn.classList.remove('is-open');
        openPill.classList.remove('is-open');
        flashOsd(btn.getAttribute('data-open-action'));
      });
    });

    // Playlist Drawer
    const togglePlaylist = () => {
      state.playlistOpen = !state.playlistOpen;
      document.getElementById('playlistDrawer').classList.toggle('is-open', state.playlistOpen);
      document.getElementById('playlistBtn').classList.toggle('is-active', state.playlistOpen);
    };
    document.getElementById('playlistBtn').addEventListener('click', togglePlaylist);
    document.getElementById('closePlaylistBtn').addEventListener('click', togglePlaylist);

    // Player · Web toggle
    document.getElementById('modeToggleBtn').addEventListener('click', () => {
      setWebMode(!state.webMode);
    });
    document.getElementById('closeWebBtn').addEventListener('click', () => {
      setWebMode(false);
    });

    // Mini Bar transitions
    document.getElementById('enterMiniBtn').addEventListener('click', () => setMiniMode(true));
    document.getElementById('exitMiniBtn').addEventListener('click', () => setMiniMode(false));
    document.getElementById('shapeFullBtn').addEventListener('click', () => setMiniMode(false));
    document.getElementById('shapeMiniBtn').addEventListener('click', () => setMiniMode(true));

    // Settings caption hint
    document.getElementById('settingsHintBtn').addEventListener('click', () => {
      flashOsd('Settings · 8 quiet tabs');
    });

    // Placement pills
    document.querySelectorAll('#placementPills [data-placement]').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('#placementPills .pill-opt').forEach((b) => b.classList.remove('is-selected'));
        btn.classList.add('is-selected');
        document.getElementById('chromeShell').setAttribute('data-placement', btn.getAttribute('data-placement'));
      });
    });

    // Overlay transparency slider (0% -> 40%)
    const slider = document.getElementById('transparencySlider');
    slider.addEventListener('input', () => {
      const pct = Number(slider.value);
      document.getElementById('transparencyVal').textContent = `${pct}%`;
      document.documentElement.style.setProperty('--overlay-keep', String(1 - pct / 100));
    });

    // Theme toggle (Default Dark <-> Light)
    document.getElementById('themeToggleBtn').addEventListener('click', () => {
      const root = document.documentElement;
      const next = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      root.setAttribute('data-theme', next);
      showPageToast(`Theme · ${next === 'light' ? 'Light' : 'Default Dark'}`);
    });

    // Explorer tabs
    document.querySelectorAll('.explorer-tab').forEach((tab) => {
      tab.addEventListener('click', () => {
        const target = tab.getAttribute('data-pane');
        document.querySelectorAll('.explorer-tab').forEach((t) => t.classList.remove('is-active'));
        document.querySelectorAll('.explorer-pane').forEach((p) => p.classList.remove('is-active'));
        tab.classList.add('is-active');
        document.getElementById(target).classList.add('is-active');
      });
    });

    // EQ preset buttons
    const eqWrap = document.getElementById('eqPresetsContainer');
    EQ_PRESETS.forEach((p, idx) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `preset-chip${idx === 0 ? ' is-active' : ''}`;
      btn.textContent = p.label.replace(' (Video)', '');
      btn.addEventListener('click', () => {
        eqWrap.querySelectorAll('.preset-chip').forEach((c) => c.classList.remove('is-active'));
        btn.classList.add('is-active');
        renderEqCurve(p.key);
      });
      eqWrap.appendChild(btn);
    });

    // Shortcut scope pills
    document.querySelectorAll('#shortcutScopePills [data-scope]').forEach((btn) => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('#shortcutScopePills .pill-opt').forEach((b) => b.classList.remove('is-selected'));
        btn.classList.add('is-selected');
        renderShortcuts(btn.getAttribute('data-scope'));
      });
    });

    // Share & copy buttons
    document.getElementById('shareHeaderBtn').addEventListener('click', () => {
      copyText(SHARE_URL, 'Share link copied · ready to invite');
    });
    document.getElementById('shareHeroBtn').addEventListener('click', () => {
      copyText(SHARE_URL, 'Share link copied · hamamun.github.io/Salu');
    });
    document.getElementById('copyShareUrlBtn').addEventListener('click', () => {
      copyText(SHARE_URL, 'Copied · https://hamamun.github.io/Salu/');
    });
    document.getElementById('copyBuildBtn').addEventListener('click', () => {
      const cmd = `git clone https://github.com/hamamun/Salu.git\ncd Salu\nflutter pub get\nflutter run -d windows`;
      copyText(cmd, 'Build commands copied');
    });
  }

  document.addEventListener('DOMContentLoaded', init);
})();
