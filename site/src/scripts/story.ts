// Timeline of the scroll story. Same choreography as the Floo.design landing
// (load intro, then scroll progress s = 0..1 drives every element), rewritten
// for Pulse and for window scrolling instead of an inner scroller.
import { animateSprites } from './sprites';
import { every, fmtRate, sparkPath, type Sample } from './sim';

const W = 1440;
const H = 1036;
const STORY = 2600; // scroll distance of the story, design px
const INTRO = 2.6;
const SPLIT = 0.74;

const cl = (x: number) => (x < 0 ? 0 : x > 1 ? 1 : x);
const p = (t: number, a: number, b: number) => cl((t - a) / (b - a));
const eo = (x: number) => 1 - Math.pow(1 - x, 3);
const eio = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);

type El = HTMLElement;

function blur(el: El, k: number, amt = 14, dy = 0, o?: number) {
  el.style.opacity = (o == null ? k : k * o).toFixed(3);
  el.style.filter = `blur(${((1 - k) * amt).toFixed(2)}px)`;
  el.style.transform = `translateY(${((1 - k) * 10 + dy).toFixed(2)}px)`;
}

function reveal(el: El, k: number) {
  el.style.opacity = k.toFixed(3);
  el.style.maxHeight = (k * 40).toFixed(1) + 'px';
  el.style.marginTop = el.previousElementSibling ? (k * 12).toFixed(1) + 'px' : '0';
  el.style.filter = `blur(${((1 - k) * 4).toFixed(2)}px)`;
}

let latest: Sample | null = null;

export function start() {
  const root = document.querySelector<El>('[data-story]');
  if (!root) return;
  const stage = root.querySelector<El>('[data-stage]')!;
  const $ = (k: string) => root.querySelector<El>(`[data-k="${k}"]`)!;
  const kids = (k: string) => [...$(k).children] as El[];

  const hero = $('hero'), scene = $('scene'), nav = $('nav'), logo = $('logo'), badge = $('badge'),
    h1s = kids('h1'), cta = $('cta'), hint = $('hint'), crm = $('crm'), cur = $('cur'), spin = $('spin'),
    fps = kids('found'), h2s = kids('h2'), h2 = $('h2'), panel = $('panel'), tabs = $('tabs'),
    tab0 = $('tab0'), tab1 = $('tab1'), bar0 = $('bar0').firstElementChild as El,
    bar1 = $('bar1').firstElementChild as El, copyA = $('copyA'), copyB = $('copyB'), pic = $('pic'),
    rock = root.querySelector<El>('.rock')!, rockfg = root.querySelector<El>('.rockfg')!, glass = $('glass'),
    menu = $('menu'), items = kids('menu'), gmsg = $('gmsg'), glook = $('glook'), spin2 = $('spin2'),
    gfound = $('gfound'), gfs = kids('gfound'), ints = [...root.querySelectorAll<El>('.int')], wire = $('wire'), ai = $('ai');

  function render(t: number, s: number) {
    // Load: the sky opens, nav, badge, headline line by line, CTA, the card rises behind the hills.
    const grow = eo(p(t, 0.1, 0.9)), collapse = eio(p(s, 0.2, 0.32));
    hero.style.height = (1000 * grow - 636 * collapse).toFixed(1) + 'px';
    nav.style.opacity = eo(p(t, 0.72, 1)).toFixed(3);
    logo.style.transform = `scale(${(0.86 + 0.14 * eo(p(t, 0.72, 1.15))).toFixed(3)})`;

    // Scroll 1: the copy lifts away, the dashboard climbs out of the hills while the alert resolves.
    const out = 1 - eio(p(s, 0.015, 0.1)), lift = -110 * eio(p(s, 0, 0.12));
    blur(badge, eo(p(t, 0.95, 1.3)), 14, lift * 1.2, out);
    blur(h1s[0], eo(p(t, 1.1, 1.65)), 14, lift, out);
    blur(h1s[1], eo(p(t, 1.32, 1.87)), 14, lift * 0.9, out);
    blur(h1s[2], eo(p(t, 1.55, 2.1)), 14, lift * 0.8, out);
    blur(cta, eo(p(t, 1.85, 2.25)), 14, lift * 0.7, out);
    const up = eo(p(t, 1.3, 2.05)), climb = eio(p(s, 0.02, 0.13)), sink = eio(p(s, 0.17, 0.24));
    crm.style.transform = `translateY(${(150 * (1 - up) - 250 * climb + 330 * sink).toFixed(1)}px) scale(${(1 + climb * 0.04).toFixed(4)})`;
    crm.style.opacity = (up * (1 - p(s, 0.2, 0.25))).toFixed(3);
    scene.style.transform = `scale(${(1 + 0.045 * climb * (1 - collapse)).toFixed(4)})`;
    reveal(fps[1], eo(p(s, 0.07, 0.1)));
    reveal(fps[2], eo(p(s, 0.1, 0.13)));
    spin.style.transform = `rotate(${(s * 2400).toFixed(0)}deg)`;
    const ck = eio(p(s, 0.05, 0.16));
    cur.style.opacity = (eo(p(s, 0.04, 0.07)) * (1 - p(s, 0.17, 0.2))).toFixed(3);
    cur.style.transform = `translate(${(612 - 92 * ck).toFixed(1)}px,${(40 + 266 * ck).toFixed(1)}px)`;
    hint.style.opacity = (p(t, 2.2, 2.6) * (1 - p(s, 0, 0.015))).toFixed(3);

    // Scroll 2: the hero folds into the header band, the second headline arrives.
    h2.style.opacity = s > 0.27 ? '1' : '0';
    blur(h2s[0], eo(p(s, 0.28, 0.33)));
    blur(h2s[1], eo(p(s, 0.3, 0.35)));
    const pk = eo(p(s, 0.32, 0.4));
    pic.style.opacity = pk.toFixed(3);
    pic.style.filter = `blur(${((1 - pk) * 10).toFixed(2)}px) brightness(${(1 + (1 - pk) * 0.25).toFixed(3)})`;
    panel.style.opacity = eo(p(s, 0.34, 0.4)).toFixed(3);
    tabs.style.opacity = eo(p(s, 0.36, 0.42)).toFixed(3);

    // Scroll 3: macOS tab. The menu drops, the cursor walks it, a container alert fires and recovers.
    const sw = eio(p(s, SPLIT - 0.035, SPLIT + 0.035));
    const ak = eo(p(s, 0.38, 0.44));
    copyA.style.opacity = (ak * (1 - sw)).toFixed(3);
    copyA.style.transform = `translateY(${((1 - ak) * 10 - sw * 14).toFixed(1)}px)`;
    copyA.style.filter = `blur(${((1 - ak) * 6 + sw * 8).toFixed(2)}px)`;
    copyB.style.opacity = sw.toFixed(3);
    copyB.style.transform = `translateY(${((1 - sw) * 14).toFixed(1)}px)`;
    copyB.style.filter = `blur(${((1 - sw) * 8).toFixed(2)}px)`;
    tab0.classList.toggle('off', sw > 0.5);
    tab1.classList.toggle('off', sw <= 0.5);
    const gk = eo(p(s, 0.4, 0.47));
    glass.style.opacity = (gk * (1 - sw)).toFixed(3);
    glass.style.transform = `translateY(${((1 - gk) * 16).toFixed(1)}px) scale(${(0.97 + gk * 0.03 - sw * 0.03).toFixed(4)})`;
    glass.style.filter = `blur(${((1 - gk) * 8 + sw * 8).toFixed(2)}px)`;
    const mk = eo(p(s, 0.42, 0.46));
    menu.style.opacity = mk.toFixed(3);
    menu.style.transform = `scale(${(0.94 + 0.06 * mk).toFixed(3)})`;
    const walk = Math.floor(p(s, 0.44, 0.53) * items.length);
    items.forEach((li, i) => li.classList.toggle('hl', mk > 0.9 && i === Math.min(walk, 5)));
    blur(gmsg, eo(p(s, 0.5, 0.54)), 6, -2);
    blur(glook, eo(p(s, 0.55, 0.58)), 6, -4);
    const fk = eo(p(s, 0.59, 0.63));
    gfound.style.opacity = fk.toFixed(3);
    gfound.style.transform = `translateY(${((1 - fk) * 8).toFixed(1)}px)`;
    reveal(gfs[1], eo(p(s, 0.63, 0.68)));
    spin2.style.transform = `rotate(${(s * 2400).toFixed(0)}deg)`;

    // Scroll 4: Linux tab. The tools Pulse sits next to stagger in, then the agent card.
    ints.forEach((el, i) => {
      const k = eo(p(s, SPLIT + 0.02 + i * 0.022, SPLIT + 0.09 + i * 0.022));
      el.style.opacity = k.toFixed(3);
      el.style.transform = `translateY(${((1 - k) * 14).toFixed(1)}px) scale(${(0.96 + k * 0.04).toFixed(4)})`;
      el.style.filter = `blur(${((1 - k) * 6).toFixed(2)}px)`;
    });
    const wk = eo(p(s, 0.9, 0.94));
    wire.style.opacity = wk.toFixed(3);
    wire.style.transform = `scaleY(${wk.toFixed(3)})`;
    const ak2 = eo(p(s, 0.92, 0.98));
    ai.style.opacity = ak2.toFixed(3);
    ai.style.transform = `translateY(${((1 - ak2) * 10).toFixed(1)}px)`;
    ai.style.filter = `blur(${((1 - ak2) * 6).toFixed(2)}px)`;
    bar0.style.width = (p(s, 0.4, SPLIT) * 100).toFixed(2) + '%';
    bar0.style.background = sw > 0.5 ? '#8fb2ec' : '#2457a8';
    bar1.style.width = (p(s, SPLIT, 1) * 100).toFixed(2) + '%';
    const rz = `scale(${(1 + 0.04 * p(s, 0.4, 1)).toFixed(4)})`;
    rock.style.transform = rz;
    rockfg.style.transform = rz;
  }

  // Layout: scale the design to the viewport, give the story its scroll length.
  let z = 1;
  const fit = () => {
    const vw = root.clientWidth, vh = window.innerHeight;
    z = Math.min(vw / W, vh / H) || 1;
    stage.style.setProperty('--z', String(z));
    stage.style.setProperty('--st', Math.max(0, (vh - H * z) / 2) + 'px');
    root.style.setProperty('--story-px', STORY * z + 'px');
  };
  fit();
  const ro = new ResizeObserver(fit);
  ro.observe(root);
  window.addEventListener('resize', fit);

  const progress = () => cl((window.scrollY - root.offsetTop) / Math.max(1, STORY * z));
  const still = matchMedia('(prefers-reduced-motion: reduce)').matches || navigator.webdriver;
  if (still) root.classList.add('still');

  let t0 = performance.now(), sT = 0, sC = still ? progress() : 0, raf = 0;
  const tick = (now: number) => {
    const t = still ? 9 : (now - t0) / 1000;
    sT = progress();
    sC = still ? sT : sC + (sT - sC) * 0.12;
    if (Math.abs(sT - sC) < 0.0003) sC = sT;
    render(t, sC);
    raf = t < INTRO || sC !== sT ? requestAnimationFrame(tick) : 0;
  };
  const wake = () => {
    if (!raf) raf = requestAnimationFrame(tick);
  };
  window.addEventListener('scroll', wake, { passive: true });
  window.addEventListener('resize', wake);
  const go = (s: number) => window.scrollTo({ top: root.offsetTop + s * STORY * z, behavior: 'smooth' });
  tab0.addEventListener('click', () => go(0.66));
  tab1.addEventListener('click', () => go(1));
  raf = requestAnimationFrame(tick);

  // Live numbers in the dashboard card and the mini menu bar.
  const rx: number[] = [];
  const set = (k: string, v: string) => root.querySelectorAll<El>(`[data-sim="${k}"]`).forEach((e) => (e.textContent = v));
  every((x) => {
    latest = x;
    set('cpu', Math.round(x.cpu).toString());
    set('temp', Math.round(x.temp).toString());
    set('mem', Math.round(x.mem).toString());
    set('rx', fmtRate(x.rx));
    set('menubar', `${Math.round(x.temp)}° ${Math.round(x.cpu)}%`);
    rx.push(x.rx);
    if (rx.length > 40) rx.shift();
    const line = sparkPath(rx, 210, 46);
    root.querySelector('[data-sim="spark"]')?.setAttribute('d', line);
    root.querySelector('[data-sim="spark-fill"]')?.setAttribute('d', `${line}L210,46L0,46Z`);
  });
  animateSprites(root, () => latest?.cpu ?? 6);
}
