// The live tour: Pulse for macOS (menu bar + panel + tools menu + settings) and
// Pulse for Linux (GNOME top bar + libadwaita window + preferences), both
// clickable, both fed by the same simulated server.
import { brandPath } from '../lib/icons';
import { drawSprite, type Kind } from './sprites';
import { every, fmtRate, sparkPath, type Sample } from './sim';
import { containers, host, logsFor, sites, summary, type Ctr } from './tour-data';

const os = new URLSearchParams(location.search).get('os') === 'linux' ? 'linux' : 'mac';
const app = document.getElementById('app')!;
document.documentElement.dataset.os = os;

const state = {
  sprite: 'server' as Kind | 'none',
  followsLoad: true,
  label: true,
  alerts: true,
  hist: { cpu: [] as number[], temp: [] as number[], mem: [] as number[], rx: [] as number[], tx: [] as number[] },
  s: null as Sample | null,
};

const h = (html: string) => {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild as HTMLElement;
};
const $ = <T extends Element = HTMLElement>(q: string, r: ParentNode = document) => r.querySelector(q) as T;
const $$ = <T extends Element = HTMLElement>(q: string, r: ParentNode = document) => [...r.querySelectorAll(q)] as T[];
const short = (c: Ctr) => c.name;
const dot = (c: Ctr) => (c.health === 'failing' ? 'red' : c.health === 'starting' ? 'amber' : 'green');
const ICON = {
  gear: '<path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm8.6 4.6-.1-2.2 2-1.5-2-3.4-2.3.9-1.8-1.1L16 3.5h-4l-.4 2.3-1.8 1.1-2.3-.9-2 3.4 2 1.5-.1 2.2-2 1.5 2 3.4 2.3-.9 1.8 1.1.4 2.3h4l.4-2.3 1.8-1.1 2.3.9 2-3.4z" fill="none" stroke="currentColor" stroke-width="1.6"/>',
  power: '<path d="M12 3v8M7 6.5a7 7 0 1 0 10 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  term: '<rect x="3" y="5" width="18" height="14" rx="3" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M7 10l3 2-3 2M12 15h5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>',
  box: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
  gauge: '<path d="M4 16a8 8 0 1 1 16 0M12 16l4-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
  cloud: '<path d="M7 18h10a4 4 0 0 0 .5-8 6 6 0 0 0-11.3 1.5A3.3 3.3 0 0 0 7 18z" fill="none" stroke="currentColor" stroke-width="1.6"/>',
};
const svg = (k: keyof typeof ICON, cls = '') => `<svg class="ic ${cls}" viewBox="0 0 24 24" fill="currentColor">${ICON[k]}</svg>`;

// ---------------------------------------------------------------- shared bits

function toast(text: string) {
  const t = h(`<div class="toast">${text}</div>`);
  app.append(t);
  requestAnimationFrame(() => t.classList.add('in'));
  setTimeout(() => {
    t.classList.remove('in');
    setTimeout(() => t.remove(), 400);
  }, 2200);
}

function notify(title: string, body: string) {
  if (!state.alerts) return;
  const n = h(`<div class="notice"><span class="app-ic"></span><div><b>${title}</b><p>${body}</p></div><small>now</small></div>`);
  app.append(n);
  requestAnimationFrame(() => n.classList.add('in'));
  setTimeout(() => {
    n.classList.remove('in');
    setTimeout(() => n.remove(), 500);
  }, 5200);
}

function logsWindow(c: Ctr) {
  $$('.logs').forEach((x) => x.remove());
  const w = h(`<div class="logs" role="dialog" aria-label="${c.name} logs">
      <header><span class="dots"><i data-close></i><i></i><i></i></span><b>${c.project ? c.project + '-' : ''}${c.name}-1</b><button data-close aria-label="Close">✕</button></header>
      <pre>${logsFor(c.name)}</pre></div>`);
  app.append(w);
  $$('[data-close]', w).forEach((b) => b.addEventListener('click', () => w.remove()));
}

function startSprites() {
  const loop = () => {
    const cpu = state.followsLoad ? (state.s?.cpu ?? 6) : 0;
    phase = (phase + 1 / 60 / (1.4 - (1.05 * Math.min(100, cpu)) / 100)) % 1;
    $$<HTMLCanvasElement>('canvas[data-sprite]').forEach((c) => {
      const kind = (c.dataset.fixed as Kind) || (state.sprite === 'none' ? 'server' : state.sprite);
      drawSprite(c.getContext('2d')!, kind, state.sprite === 'none' && !c.dataset.fixed ? 0.25 : phase, c.dataset.ink!, '#34d17a');
    });
    requestAnimationFrame(loop);
  };
  let phase = 0;
  $$<HTMLCanvasElement>('canvas[data-sprite]').forEach((c) => {
    c.width = c.clientWidth * 2;
    c.height = c.clientHeight * 2;
  });
  requestAnimationFrame(loop);
}

function scheduleAlerts() {
  const host_ = host.name;
  const script: [number, string, string][] = [
    [14000, `Container jellyfin needs attention`, 'It stopped, crashed or turned unhealthy.'],
    [26000, `Container jellyfin recovered`, ''],
    [52000, `${host_} is running hot`, 'CPU at 86 °C.'],
    [70000, `${host_} cooled down`, 'CPU temperature is back to normal.'],
  ];
  for (const [ms, t, b] of script) setTimeout(() => notify(t, b), ms);
}

function onSample(fn: (s: Sample) => void) {
  every((s) => {
    state.s = s;
    const H = state.hist;
    H.cpu.push(s.cpu);
    H.temp.push(s.temp);
    H.mem.push(s.mem);
    H.rx.push(s.rx);
    H.tx.push(s.tx);
    for (const k of Object.keys(H) as (keyof typeof H)[]) if (H[k].length > 60) H[k].shift();
    fn(s);
  });
}

const set = (k: string, v: string) => $$(`[data-v="${k}"]`).forEach((e) => (e.textContent = v));
const spark = (k: string, values: number[], top?: number) =>
  $$(`[data-spark="${k}"]`).forEach((el) => {
    const w = 200, hh = 34;
    const d = sparkPath(values.length > 1 ? values : [0, 0], w, hh, top);
    el.innerHTML = `<path class="f" d="${d}L${w},${hh}L0,${hh}Z"/><path class="l" d="${d}"/>`;
  });

// --------------------------------------------------------------------- macOS

function mac() {
  app.innerHTML = `
  <div class="desk mac">
    <div class="menubar">
      <span class="l"><svg class="apple" viewBox="0 0 24 24" fill="#fff"><path d="${brandPath('apple')}"/></svg><strong>Finder</strong><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span></span>
      <span class="r">
        <button class="item" data-item aria-label="Pulse"><canvas data-sprite data-ink="#fff"></canvas><span class="cols"><span><i>TEMP</i><b data-v="temp">53°</b></span><span><i>CPU</i><b data-v="cpu">6%</b></span><span><i>MEM</i><b data-v="mem">8%</b></span></span></button>
        <svg class="glyph" viewBox="0 0 24 24"><path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.3 9.3 0 0 1 12.4 0M9.1 15.8a4.6 4.6 0 0 1 5.8 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="19" r="1.4" fill="currentColor"/></svg><span class="clock">Fri 21:14</span>
      </span>
    </div>
    <p class="coach">Click the server in the menu bar · right-click for tools</p>
  </div>`;
  const item = $('[data-item]');
  item.addEventListener('click', (e) => {
    e.stopPropagation();
    $('.menu')?.remove();
    togglePanel();
  });
  item.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    e.stopPropagation();
    closePanel();
    toolsMenu();
  });
  document.addEventListener('click', (e) => {
    const t = e.target as HTMLElement;
    if (!t.closest('.panel, .menu, .settings, .logs, [data-item]')) {
      closePanel();
      $('.menu')?.remove();
    }
  });
  startSprites();
  onSample(macUpdate);
  setTimeout(() => togglePanel(true), 900);
  scheduleAlerts();
}

function panelHTML() {
  const rows = containers.slice(0, 5).map((c, i) => `
    <button class="crow" data-c="${i}"><i class="d ${dot(c)}"></i><b>${short(c)}</b><span class="pj">${c.project}</span><span class="m">${c.mem} MB</span><span class="cp">${c.cpu.toFixed(1)}</span><span class="more">···</span></button>`).join('');
  return `<div class="panel" role="dialog" aria-label="Pulse panel">
    <header class="ph">${svg('sun', 'sun')}<b class="score">98</b><span class="lbl">Excellent</span><i class="live"></i></header>
    <div class="chips"><span>${host.cpu}</span><span>${host.ram}</span><span>${host.os}</span><span>${host.uptime}</span></div>
    <div class="tiles">
      <div class="tile"><p class="tt"><span>CPU</span><em data-v="temp-chip">51°C</em></p><p class="big"><b data-v="cpu-n">6</b> %</p><svg class="spark blue" data-spark="cpu" viewBox="0 0 200 34" preserveAspectRatio="none"></svg><p class="sub">idle · 8 threads</p></div>
      <div class="tile"><p class="tt"><span>Temp</span><em>Normal</em></p><p class="big"><b data-v="temp-n">51</b> °C</p><svg class="spark orange" data-spark="temp" viewBox="0 0 200 34" preserveAspectRatio="none"></svg><p class="sub">4 cores · max 54°C</p></div>
      <div class="tile"><p class="tt"><span>MEM</span><em>Normal</em></p><p class="big"><b data-v="mem-n">8</b> %</p><svg class="spark purple" data-spark="mem" viewBox="0 0 200 34" preserveAspectRatio="none"></svg><p class="sub">1,3 GB / 16,7 GB</p></div>
      <div class="tile"><p class="tt"><span>Free space</span><em>105 GB</em></p><p class="big"><b>46,0</b> GB</p><div class="bar"><i style="width:54%"></i></div><p class="sub">53,7 GB used · 54%</p></div>
      <div class="tile"><p class="tt"><span>Network</span><em>Ethernet</em></p><p class="big"><b data-v="rx-n">2</b> <span data-v="rx-u">KB/s</span></p><svg class="spark green" data-spark="rx" viewBox="0 0 200 34" preserveAspectRatio="none"></svg><p class="sub">Upload <span data-v="tx">1 KB/s</span></p></div>
      <div class="tile"><p class="tt"><span>Fan</span><em>Speed <span data-v="fanpct">0</span>%</em></p><p class="big"><b data-v="fan">1.996</b> RPM</p><p class="sub2">Managed automatically</p><div class="seg"><button class="on">Auto</button><button>Min</button><button>Max</button></div></div>
    </div>
    <div class="sites">${svg('cloud')}${sites.slice(0, 2).map((s) => `<a href="#" data-site><i class="d green"></i><b>${s.name}</b><span>${s.ms} ms</span></a>`).join('')}</div>
    <div class="ctrs"><p class="ch"><span>Containers</span><span>Memory</span><span>% CPU</span></p>${rows}<p class="cf"><span>9 running · 0 stopped</span><a href="#" data-all>Show all</a></p></div>
    <footer class="pf">
      <div class="btns"><button data-settings aria-label="Settings">${svg('gear')}</button><button data-quit aria-label="Quit">${svg('power')}</button><span></span><button data-ssh>${svg('term')} SSH</button><button data-portainer>${svg('box')} Portainer</button><button data-cockpit aria-label="Cockpit">${svg('gauge')}</button></div>
      <div class="stats"><p><b>9</b>Containers</p><p><b class="amber">5</b>Updates</p><p><b>0</b>Alerts</p></div>
    </footer>
  </div>`;
}

function togglePanel(force?: boolean) {
  const open = $('.panel');
  if (open && force !== true) return closePanel();
  if (open) return;
  const p = h(panelHTML());
  $('.desk').append(p);
  $('[data-item]').classList.add('hl');
  requestAnimationFrame(() => p.classList.add('in'));
  $$('[data-c]', p).forEach((b) => b.addEventListener('click', () => logsWindow(containers[Number(b.dataset.c)])));
  $('[data-settings]', p).addEventListener('click', () => settings());
  $('[data-quit]', p).addEventListener('click', () => toast('It is a demo: Pulse stays.'));
  for (const k of ['ssh', 'portainer', 'cockpit', 'site', 'all']) $$(`[data-${k}]`, p).forEach((b) => b.addEventListener('click', (e) => {
    e.preventDefault();
    toast(k === 'all' ? 'All 9 containers are healthy.' : `Opens ${k === 'site' ? 'the site' : k === 'ssh' ? 'Terminal with ssh' : k[0].toUpperCase() + k.slice(1)} on your Mac.`);
  }));
  $('.coach')?.classList.add('done');
  macUpdate();
}

function closePanel() {
  $('.panel')?.remove();
  $('[data-item]')?.classList.remove('hl');
}

function toolsMenu() {
  const items: [string, string, (() => void) | null][] = [
    ['Open Pulse', '⌃⌥⌘P', () => togglePanel(true)],
    ['Settings…', '⌘,', () => settings()],
    ['-', '', null],
    ['SSH into Server', '', () => toast('Opens Terminal with ssh.')],
    ['Portainer', '', () => toast('Opens Portainer in your browser.')],
    ['Cockpit', '', () => toast('Opens Cockpit in your browser.')],
    ['Container Logs', '›', () => logsWindow(containers[4])],
    ['Open Site', '›', () => toast('Opens perde.kutluhangil.dev.')],
    ['-', '', null],
    ['Copy Status Summary', '', () => copy()],
    ['Reconnect', '', () => toast('Reconnected · live')],
    ['Pause Notifications', '›', () => { state.alerts = false; toast('Notifications paused for 1 hour.'); }],
    ['-', '', null],
    ['Check for Updates…', '', () => toast('Pulse 0.1.0 is up to date.')],
    ['About Pulse', '', () => settings('about')],
    ['-', '', null],
    ['Quit Pulse', '⌘Q', () => toast('It is a demo: Pulse stays.')],
  ];
  const m = h(`<div class="menu" role="menu">${items.map(([t, k], i) => (t === '-' ? '<hr>' : `<button role="menuitem" data-i="${i}"><span>${t}</span><kbd>${k}</kbd></button>`)).join('')}</div>`);
  $('.desk').append(m);
  $$('[data-i]', m).forEach((b) => b.addEventListener('click', () => {
    m.remove();
    items[Number(b.dataset.i)][2]?.();
  }));
}

function copy() {
  const s = state.s;
  navigator.clipboard?.writeText(summary(s?.cpu ?? 6, s?.temp ?? 53, s?.mem ?? 8)).catch(() => {});
  toast('Status summary copied.');
}

function settings(tab = 'menubar') {
  closePanel();
  $('.settings')?.remove();
  const tabs = [['general', 'General'], ['server', 'Server'], ['menubar', 'Menu Bar'], ['alerts', 'Alerts'], ['about', 'About']];
  const w = h(`<div class="settings" role="dialog" aria-label="Pulse settings">
    <header><nav>${tabs.map(([k, t]) => `<button data-tab="${k}">${t}</button>`).join('')}</nav><button class="x" data-close aria-label="Close">✕</button></header>
    <div class="body"></div></div>`);
  $('.desk').append(w);
  const row = (t: string, d: string, ctl: string) => `<div class="row"><div><b>${t}</b><p>${d}</p></div>${ctl}</div>`;
  const tog = (k: string, on: boolean) => `<button class="tog ${on ? 'on' : ''}" data-tog="${k}" aria-pressed="${on}"></button>`;
  const pick = (k: string, opts: string[], cur: string) => `<select data-pick="${k}">${opts.map((o) => `<option ${o === cur ? 'selected' : ''}>${o}</option>`).join('')}</select>`;
  const body: Record<string, () => string> = {
    general: () => row('Notifications', 'Alerts arrive as macOS notifications', '<span class="ok">✓ Granted</span>') +
      row('Language', 'Follow system, restart Pulse after changing', pick('lang', ['Follow system', 'English', 'Türkçe'], 'Follow system')) +
      row('Launch at login', 'Server status is in the menu bar when you reach the desktop', tog('login', true)) +
      row('Check for updates automatically', 'Pulse 0.1.0 is up to date', `<span class="pair"><button class="pb">Check Now</button>${tog('upd', true)}</span>`) +
      row('Panel shortcut', '⌃⌥⌘P shows or hides the panel from any app', tog('key', true)) +
      row('Swap left and right clicks', 'Left-click opens the tools menu, right-click opens the panel', tog('swap', false)),
    server: () => row('Address', 'From tailscale serve', '<code>macmini-server.taild883a6.ts.net:9123</code>') +
      row('Token', 'Stored in the app container, 0600', '<code>••••••••••••••••</code>') +
      row('Connection', 'Connected to macmini-server in 14 ms', '<button class="pb">Test</button>') +
      row('SSH', 'kutluhan@macmini-server', '<button class="pb">Edit</button>'),
    menubar: () => row('Menu bar content', 'Choose an icon, live data, or both', pick('content', ['Both', 'Icon', 'Live data'], 'Both')) +
      row('Animated icon', 'A little character that runs while the server is live', `<span class="pair"><canvas data-sprite data-ink="#fff" class="pv"></canvas>${pick('sprite', ['Server', 'Cat', 'Pulse', 'None'], state.sprite[0].toUpperCase() + state.sprite.slice(1))}</span>`) +
      row('Speed follows CPU load', 'Runs faster as the server gets busier', tog('follow', state.followsLoad)) +
      row('Data layout', 'Columns or a single line', pick('layout', ['Columns', 'Single line'], 'Columns')) +
      row('First status metric', 'Temperature, CPU, memory or another metric', pick('m1', ['CPU temperature'], 'CPU temperature')),
    alerts: () => row('Alerts', 'Notify me when something needs attention', tog('alerts', state.alerts)) +
      row('Temperature', 'Held for 30 seconds', pick('t', ['80 °C', '85 °C', '90 °C'], '85 °C')) +
      row('Memory', 'Held for a minute', pick('m', ['85 %', '90 %', '95 %'], '90 %')) +
      row('Containers', 'Stopped, crashed or unhealthy', tog('c', true)) +
      row('Sites', 'Two failed checks in a row', tog('s', true)) +
      row('Server offline', 'No data for over a minute', tog('o', true)),
    about: () => `<div class="about"><img src="/icon-256.png" alt="" width="88" height="88"><b>Pulse</b><p>Version 0.1.0</p><p>Live monitor for your home server. Free software under GPL-3.0.</p><small>Health score adapted from Mole by tw93.</small></div>`,
  };
  const show = (k: string) => {
    $$('[data-tab]', w).forEach((b) => b.classList.toggle('on', b.dataset.tab === k));
    $('.body', w).innerHTML = body[k]();
    $$<HTMLCanvasElement>('canvas', w).forEach((c) => { c.width = 40; c.height = 36; });
    $$('[data-tog]', w).forEach((b) => b.addEventListener('click', () => {
      const on = !b.classList.contains('on');
      b.classList.toggle('on', on);
      b.setAttribute('aria-pressed', String(on));
      if (b.dataset.tog === 'follow') state.followsLoad = on;
      if (b.dataset.tog === 'alerts') state.alerts = on;
    }));
    $$<HTMLSelectElement>('[data-pick="sprite"]', w).forEach((s) => s.addEventListener('change', () => {
      state.sprite = s.value.toLowerCase() as Kind | 'none';
    }));
  };
  $$('[data-tab]', w).forEach((b) => b.addEventListener('click', () => show(b.dataset.tab!)));
  $('[data-close]', w).addEventListener('click', () => w.remove());
  show(tab);
}

function macUpdate() {
  const s = state.s;
  if (!s) return;
  set('temp', `${Math.round(s.temp)}°`);
  set('cpu', `${Math.round(s.cpu)}%`);
  set('mem', `${Math.round(s.mem)}%`);
  set('cpu-n', String(Math.round(s.cpu)));
  set('temp-n', String(Math.round(s.temp)));
  set('temp-chip', `${Math.round(s.temp)}°C`);
  set('mem-n', String(Math.round(s.mem)));
  const [n, u] = fmtRate(s.rx).split(' ');
  set('rx-n', n);
  set('rx-u', u);
  set('tx', fmtRate(s.tx));
  set('fan', Math.round(s.fan).toLocaleString('de-DE'));
  set('fanpct', String(Math.max(0, Math.round(((s.fan - 2000) / 3500) * 100))));
  spark('cpu', state.hist.cpu, 100);
  spark('temp', state.hist.temp.map((t) => t - 30), 50);
  spark('mem', state.hist.mem, 100);
  spark('rx', state.hist.rx);
}

// --------------------------------------------------------------------- Linux

function linux() {
  app.innerHTML = `
  <div class="desk gnome">
    <div class="topbar">
      <span class="act">Activities</span><span class="clk">Fri 21:14</span>
      <span class="r"><button class="tray" data-tray aria-label="Pulse"><canvas data-sprite data-ink="#f6f5f4"></canvas><span data-v="label">53° 6%</span></button><span class="sys">◢ ◖ ⏻</span></span>
    </div>
    <p class="coach">Click the tray icon · right-click it for the menu</p>
  </div>`;
  $('[data-tray]').addEventListener('click', (e) => {
    e.stopPropagation();
    $('.gmenu')?.remove();
    if ($('.adw')) $('.adw')!.remove();
    else adwWindow();
  });
  $('[data-tray]').addEventListener('contextmenu', (e) => {
    e.preventDefault();
    e.stopPropagation();
    trayMenu();
  });
  document.addEventListener('click', (e) => {
    const t = e.target as HTMLElement;
    if (!t.closest('.gmenu, .popover, [data-tray], [data-menu]')) {
      $('.gmenu')?.remove();
      $('.popover')?.remove();
    }
  });
  startSprites();
  onSample(linuxUpdate);
  setTimeout(adwWindow, 700);
  scheduleAlerts();
}

function adwWindow() {
  const groups = new Map<string, Ctr[]>();
  containers.forEach((c) => groups.set(c.project || 'Standalone', [...(groups.get(c.project || 'Standalone') ?? []), c]));
  const res = (icon: string, t: string, v: string, sub: string, graph: string) =>
    `<div class="rrow"><div class="top"><span class="ri">${icon}</span><div><b>${t}</b><p data-v="${v}-d">${sub}</p></div><strong data-v="${v}-v">–</strong></div>${graph}</div>`;
  const g = (k: string, c: string) => `<svg class="spark ${c}" data-spark="${k}" viewBox="0 0 200 34" preserveAspectRatio="none"></svg>`;
  const w = h(`<div class="adw" role="dialog" aria-label="Pulse window">
    <header class="hb"><button class="hbtn" data-reload aria-label="Reconnect">⟳</button>
      <nav class="vs"><button class="on" data-page="overview">Overview</button><button data-page="containers">Containers</button><button data-page="sites">Sites</button></nav>
      <span class="end"><button class="hbtn" data-menu aria-label="Main menu">☰</button><span class="wbtn">–</span><span class="wbtn">□</span><button class="wbtn" data-x aria-label="Close">✕</button></span></header>
    <div class="pages">
      <section data-p="overview" class="on">
        <div class="hero"><div class="ring"><svg viewBox="0 0 96 96"><circle cx="48" cy="48" r="43" class="bg"/><circle cx="48" cy="48" r="43" class="fg" stroke-dasharray="${(0.98 * 270).toFixed(0)} 999"/></svg><b>98</b></div>
          <div><h2>${host.name}</h2><p class="ok">Excellent</p><p class="dim">Security updates pending</p><div class="chips"><span>${host.os}</span><span>${host.cpu}</span><span>${host.ram}</span><span>${host.uptime}</span></div></div></div>
        <h4>Resources</h4>
        <div class="boxed">
          ${res('▣', 'Processor', 'cpu', 'idle · 8 threads · load 0.83 0.56 0.22', g('cpu', 'blue'))}
          ${res('<svg viewBox="0 0 16 16" width="14" height="14" fill="currentColor"><path d="M8 0a2.5 2.5 0 0 0-2.5 2.5v6.7a3.5 3.5 0 1 0 5 0V2.5A2.5 2.5 0 0 0 8 0zm0 1.5a1 1 0 0 1 1 1v7.4l.3.2a2 2 0 1 1-2.6 0l.3-.2V2.5a1 1 0 0 1 1-1z"/></svg>', 'Temperature', 'temp', 'Normal · cores 49 54 50 46', g('temp', 'orange'))}
          ${res('▤', 'Memory', 'mem', 'Normal · 1.3 GB of 16.7 GB', g('mem', 'purple'))}
          ${res('⛁', 'Storage', 'disk', '46.0 GB free · read 0 KB/s · write 0 KB/s', '<div class="lvl"><i style="width:54%"></i></div>')}
          ${res('⇅', 'Network', 'net', 'enp1s0f0 · 1 Gb/s', g('rx', 'green'))}
          ${res('≋', 'Fan', 'fan', 'Exhaust · Auto', '<div class="lvl"><i data-fanbar style="width:2%"></i></div>')}
        </div>
        <h4>System</h4>
        <div class="boxed">
          <div class="arow"><b>Software updates</b><p>5 packages, 2 security</p></div>
          <div class="arow"><b>Docker</b><p>Engine 28.5.2 · 9 running</p></div>
          <div class="arow"><b>Pulse agent</b><p>Version 0.1.0 · ${host.kernel}</p><span class="suf">14 ms</span></div>
        </div>
      </section>
      <section data-p="containers"><p class="dim lead">9 of 9 running</p>
        ${[...groups].map(([pj, cs]) => `<h4>${pj}</h4><div class="boxed">${cs.map((c) => `<button class="arow act" data-c="${containers.indexOf(c)}"><i class="d ${dot(c)}"></i><div><b>${c.name}</b><p>${c.image} · ${c.status}</p></div><span class="suf2"><em class="${c.health === 'healthy' ? 'ok' : ''}">${c.health === 'healthy' ? 'Healthy' : 'Running'}</em><small>${c.cpu.toFixed(1)} % · ${c.mem} MB</small></span><span class="chev">›</span></button>`).join('')}</div>`).join('')}
      </section>
      <section data-p="sites"><h4>Sites</h4><p class="dim cap">Checked by the agent every minute</p>
        <div class="boxed">${sites.map((s) => `<button class="arow act" data-site><i class="d green"></i><div><b>${s.name}</b><p>${s.url}</p></div><span class="suf">${s.ms} ms</span><span class="chev">›</span></button>`).join('')}</div>
      </section>
    </div></div>`);
  $('.desk').append(w);
  $$('[data-page]', w).forEach((b) => b.addEventListener('click', () => {
    $$('[data-page]', w).forEach((x) => x.classList.toggle('on', x === b));
    $$('[data-p]', w).forEach((x) => x.classList.toggle('on', x.dataset.p === b.dataset.page));
  }));
  $$('[data-c]', w).forEach((b) => b.addEventListener('click', () => logsWindow(containers[Number(b.dataset.c)])));
  $$('[data-site]', w).forEach((b) => b.addEventListener('click', () => toast('Opens the site in your browser.')));
  $('[data-x]', w).addEventListener('click', () => { w.remove(); toast('Pulse keeps running in the tray.'); });
  $('[data-reload]', w).addEventListener('click', () => toast('Reconnected · live'));
  $('[data-menu]', w).addEventListener('click', (e) => { e.stopPropagation(); popover(); });
  $('.coach')?.classList.add('done');
  linuxUpdate();
}

function popover() {
  $('.popover')?.remove();
  const items: [string, () => void][] = [
    ['Copy Status Summary', copy], ['Reconnect', () => toast('Reconnected · live')], ['-', () => {}],
    ['SSH into Server', () => toast('Opens a terminal with ssh.')], ['Portainer', () => toast('Opens Portainer.')], ['Cockpit', () => toast('Opens Cockpit.')], ['-', () => {}],
    ['Preferences', prefs], ['Check for Updates…', () => toast('Pulse 0.1.0 is up to date')], ['About Pulse', () => toast('Pulse 0.1.0 · GPL-3.0')], ['Quit', () => toast('It is a demo: Pulse stays.')],
  ];
  const p = h(`<div class="popover">${items.map(([t], i) => (t === '-' ? '<hr>' : `<button data-i="${i}">${t}</button>`)).join('')}</div>`);
  $('.adw')!.append(p);
  $$('[data-i]', p).forEach((b) => b.addEventListener('click', () => { p.remove(); items[Number(b.dataset.i)][1](); }));
}

function trayMenu() {
  $('.gmenu')?.remove();
  const items: [string, () => void][] = [
    [`${host.name} · 98 Excellent`, () => {}], ['-', () => {}],
    ['Open Pulse', () => { if (!$('.adw')) adwWindow(); }], ['Preferences', () => { if (!$('.adw')) adwWindow(); prefs(); }], ['-', () => {}],
    ['SSH into Server', () => toast('Opens a terminal with ssh.')], ['Container Logs  ›', () => logsWindow(containers[4])], ['Open Site  ›', () => toast('Opens perde.kutluhangil.dev')], ['-', () => {}],
    ['Copy Status Summary', copy], ['Pause Notifications  ›', () => { state.alerts = false; toast('Notifications paused for 1 hour.'); }], ['-', () => {}],
    ['Check for Updates…', () => toast('Pulse 0.1.0 is up to date')], ['Quit', () => toast('It is a demo: Pulse stays.')],
  ];
  const m = h(`<div class="gmenu">${items.map(([t], i) => (t === '-' ? '<hr>' : `<button data-i="${i}" ${i === 0 ? 'disabled' : ''}>${t}</button>`)).join('')}</div>`);
  $('.desk').append(m);
  $$('[data-i]', m).forEach((b) => b.addEventListener('click', () => { m.remove(); items[Number(b.dataset.i)][1](); }));
}

function prefs() {
  $('.prefs')?.remove();
  const sw = (k: string, on: boolean) => `<button class="sw ${on ? 'on' : ''}" data-sw="${k}" aria-pressed="${on}"></button>`;
  const row = (t: string, d: string, c: string) => `<div class="arow"><div><b>${t}</b><p>${d}</p></div><span class="suf">${c}</span></div>`;
  const pages: Record<string, string> = {
    General: `<h4>Behaviour</h4><div class="boxed">${row('Launch at login', 'Pulse starts in the background when you log in', sw('login', false))}${row('Keep running in the background', 'Closing the window leaves Pulse in the tray', sw('bg', true))}${row('Language', 'Restart Pulse after changing', '<span class="combo">Follow system ▾</span>')}</div>
      <h4>Updates</h4><div class="boxed">${row('Check for updates automatically', 'Looks for a new release on GitHub once a day', sw('upd', true))}${row('Pulse version', 'Pulse 0.1.0 is up to date', '<button class="btn2">Check Now</button>')}</div>`,
    Server: `<h4>Agent</h4><div class="boxed">${row('Address', 'macmini-server.taild883a6.ts.net:9123', '')}${row('Token', '••••••••••••••••', '')}${row('Connection', 'Connected to macmini-server in 14 ms', '<button class="btn2">Test</button><button class="btn2 sug">Save</button>')}</div>`,
    Tray: `<h4>Tray icon</h4><div class="boxed">${row('Show tray icon', '', sw('tray', true))}${row('Animated icon', 'LEDs and heartbeat take the health colour', `<select data-anim><option value="server">Hopping server</option><option value="cat">Running cat</option><option value="pulse">Heartbeat</option><option value="none">Still icon</option></select>`)}${row('Speed follows CPU load', 'The busier the server, the faster it runs', sw('follow', state.followsLoad))}${row('Show temperature and CPU', 'Text next to the icon, where the tray supports it', sw('label', state.label))}</div>`,
    Alerts: `<h4>Notifications</h4><div class="boxed">${row('Alerts', 'Desktop notifications when something needs attention', sw('alerts', state.alerts))}</div><h4>Thresholds</h4><div class="boxed">${row('Temperature', '°C, held for 30 seconds', '<span class="spin">− 85 +</span>')}${row('Memory', '% used, held for a minute', '<span class="spin">− 90 +</span>')}${row('Disk', '% used', '<span class="spin">− 85 +</span>')}</div>`,
  };
  const d = h(`<div class="prefs" role="dialog" aria-label="Preferences"><header><b>Preferences</b><button data-close aria-label="Close">✕</button></header><div class="pbody"></div><nav>${Object.keys(pages).map((k) => `<button data-pp="${k}">${k}</button>`).join('')}</nav></div>`);
  $('.adw')!.append(d);
  const show = (k: string) => {
    $$('[data-pp]', d).forEach((b) => b.classList.toggle('on', b.dataset.pp === k));
    $('.pbody', d).innerHTML = pages[k];
    $$('[data-sw]', d).forEach((b) => b.addEventListener('click', () => {
      const on = !b.classList.contains('on');
      b.classList.toggle('on', on);
      if (b.dataset.sw === 'follow') state.followsLoad = on;
      if (b.dataset.sw === 'alerts') state.alerts = on;
      if (b.dataset.sw === 'label') { state.label = on; linuxUpdate(); }
    }));
    const sel = $<HTMLSelectElement>('[data-anim]', d);
    if (sel) {
      sel.value = state.sprite;
      sel.addEventListener('change', () => (state.sprite = sel.value as Kind | 'none'));
    }
  };
  $$('[data-pp]', d).forEach((b) => b.addEventListener('click', () => show(b.dataset.pp!)));
  $('[data-close]', d).addEventListener('click', () => d.remove());
  show('Tray');
}

function linuxUpdate() {
  const s = state.s;
  if (!s) return;
  set('label', state.label ? `${Math.round(s.temp)}° ${Math.round(s.cpu)}%` : '');
  set('cpu-v', `${Math.round(s.cpu)} %`);
  set('temp-v', `${Math.round(s.temp)} °C`);
  set('mem-v', `${Math.round(s.mem)} %`);
  set('disk-v', '54 %');
  set('net-v', `↓ ${fmtRate(s.rx)}`);
  set('net-d', `enp1s0f0 · 1 Gb/s · ↑ ${fmtRate(s.tx)}`);
  set('fan-v', `${Math.round(s.fan).toLocaleString('en-US')} rpm`);
  const fb = $('[data-fanbar]');
  if (fb) fb.style.width = `${Math.max(2, Math.round(((s.fan - 2000) / 3500) * 100))}%`;
  spark('cpu', state.hist.cpu, 100);
  spark('temp', state.hist.temp.map((t) => t - 30), 50);
  spark('mem', state.hist.mem, 100);
  spark('rx', state.hist.rx);
}

if (os === 'mac') mac();
else linux();
