// Simulated live numbers for the page. The real agent never faces the internet
// (it is reachable only on the tailnet), so the site shows a believable
// macmini-server: idle Ivy Bridge, a few containers, the odd download spike.
export interface Sample {
  cpu: number;
  temp: number;
  mem: number;
  rx: number;
  tx: number;
  fan: number;
  t: number;
}

let t = 0;
let spike = 0;

export function next(): Sample {
  t += 1;
  if (spike <= 0 && Math.random() < 0.04) spike = 6 + Math.floor(Math.random() * 6);
  const busy = spike > 0 ? 1 : 0;
  spike -= 1;
  const wave = Math.sin(t / 9) * 0.5 + Math.sin(t / 3.7) * 0.3;
  return {
    t,
    cpu: Math.max(1, 6 + 5 * wave + busy * (18 + Math.random() * 14) + Math.random() * 2),
    temp: 52 + 3 * wave + busy * 7 + Math.random(),
    mem: 7.8 + 0.25 * wave + busy * 0.6,
    rx: Math.max(300, 2200 + 1800 * wave + busy * (2_400_000 + Math.random() * 900_000)),
    tx: Math.max(120, 800 + 500 * wave + busy * 90_000),
    fan: 2000 + busy * 900 + Math.max(0, wave) * 120,
  };
}

export const fmtRate = (bps: number) => {
  const kb = bps / 1000;
  if (kb < 1000) return `${Math.round(kb)} KB/s`;
  const mb = kb / 1000;
  return `${mb < 100 ? mb.toFixed(1) : Math.round(mb)} MB/s`;
};

/** Calls `fn` once a second with a fresh sample, paused while the tab is hidden. */
export function every(fn: (s: Sample) => void) {
  fn(next());
  setInterval(() => {
    if (!document.hidden) fn(next());
  }, 1000);
}

export function sparkPath(values: number[], w: number, h: number, top?: number) {
  const max = top ?? Math.max(1, ...values);
  const step = w / Math.max(1, values.length - 1);
  return values.map((v, i) => `${i ? 'L' : 'M'}${(i * step).toFixed(1)},${(h - 2 - (h - 4) * Math.min(1, v / max)).toFixed(1)}`).join('');
}
