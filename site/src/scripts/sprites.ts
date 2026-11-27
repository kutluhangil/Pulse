// Canvas port of the app's menu bar characters (app/.../MenuBarSprites.swift),
// drawn in the sprite's own 20 x 18 point space with y pointing up.
export type Kind = 'server' | 'cat' | 'pulse';

const W = 20;
const H = 18;

export function drawSprite(ctx: CanvasRenderingContext2D, kind: Kind, phase: number, ink: string, health: string) {
  const c = ctx.canvas;
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, c.width, c.height);
  const s = Math.min(c.width / W, c.height / H);
  ctx.translate((c.width - W * s) / 2, (c.height + H * s) / 2);
  ctx.scale(s, -s);
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  if (kind === 'server') server(ctx, phase, ink, health);
  else if (kind === 'cat') cat(ctx, phase, ink);
  else pulse(ctx, phase, health);
  ctx.restore();
}

function rr(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, r);
}

function oval(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number) {
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
}

function server(ctx: CanvasRenderingContext2D, phase: number, ink: string, health: string) {
  const hop = Math.max(0, Math.sin(phase * 2 * Math.PI));
  const landing = Math.max(0, -Math.sin(phase * 2 * Math.PI));
  const w = 12 + landing * 1.6;
  const h = 12 - landing * 1.8;
  const x = W / 2 - w / 2;
  const y = 2 + hop * 4.2;
  ctx.globalAlpha = 0.22;
  ctx.fillStyle = ink;
  const sw = 10 - hop * 4;
  oval(ctx, W / 2 - sw / 2, 0, sw, 1.6);
  ctx.fill();
  ctx.globalAlpha = 1;
  ctx.strokeStyle = ink;
  ctx.lineWidth = 1.2;
  rr(ctx, x + 0.6, y + 0.6, w - 1.2, h - 1.2, 2.2);
  ctx.stroke();
  ctx.lineWidth = 1;
  for (let i = 0; i < 3; i++) {
    const sy = y + 2.4 + i * 3.2;
    ctx.beginPath();
    ctx.moveTo(x + 2.4, sy);
    ctx.lineTo(x + w - 5, sy);
    ctx.stroke();
    const on = Math.floor(phase * 6 + i) % 3 !== 0;
    ctx.globalAlpha = on ? 1 : 0.25;
    ctx.fillStyle = health;
    oval(ctx, x + w - 3.8, sy - 1, 2, 2);
    ctx.fill();
    ctx.globalAlpha = 1;
  }
}

function cat(ctx: CanvasRenderingContext2D, phase: number, ink: string) {
  const t = phase * 2 * Math.PI;
  const bob = Math.abs(Math.sin(t)) * 1.2;
  ctx.fillStyle = ink;
  ctx.strokeStyle = ink;
  const bx = 4, by = 6 + bob, bw = 10, bh = 5.5;
  rr(ctx, bx, by, bw, bh, 2.75);
  ctx.fill();
  const hx = bx + bw - 2, hy = by + 2.5, hw = 6, hh = 5.5;
  oval(ctx, hx, hy, hw, hh);
  ctx.fill();
  for (const dx of [0.6, 3.4]) {
    ctx.beginPath();
    ctx.moveTo(hx + dx, hy + hh - 1.2);
    ctx.lineTo(hx + dx + 1.1, hy + hh + 1.8);
    ctx.lineTo(hx + dx + 2.2, hy + hh - 1.2);
    ctx.closePath();
    ctx.fill();
  }
  ctx.lineWidth = 1.4;
  ctx.beginPath();
  ctx.moveTo(bx + 0.5, by + bh / 2 + 1);
  ctx.bezierCurveTo(bx - 2, by + bh / 2, bx - 3.5, by + bh, bx - 3.2, by + bh + 2.5 + Math.sin(t * 2) * 1.2);
  ctx.stroke();
  ctx.lineWidth = 1.3;
  for (const [lx, off] of [[bx + 2, 0], [bx + 3.5, Math.PI], [bx + bw - 2.5, Math.PI], [bx + bw - 1, 0]]) {
    const swing = Math.sin(t + off) * 2.2;
    ctx.beginPath();
    ctx.moveTo(lx, by + 0.8);
    ctx.lineTo(lx + swing, 1 + Math.max(0, Math.cos(t + off)) * 1.2);
    ctx.stroke();
  }
}

const BEAT = [[0, 0], [0.3, 0], [0.36, 0.25], [0.42, -0.35], [0.5, 0.95], [0.57, -0.55], [0.63, 0.12], [0.7, 0], [1, 0]];

function pulse(ctx: CanvasRenderingContext2D, phase: number, health: string) {
  const mid = H / 2, amp = H * 0.42, shift = phase * W;
  ctx.beginPath();
  ctx.rect(0, 0, W, H);
  ctx.clip();
  ctx.beginPath();
  let first = true;
  for (const copy of [0, 1]) {
    for (const [bx, by] of BEAT) {
      const px = (bx + copy) * W - shift, py = mid + by * amp;
      if (first) { ctx.moveTo(px, py); first = false; } else ctx.lineTo(px, py);
    }
  }
  ctx.strokeStyle = health;
  ctx.lineWidth = 1.5;
  ctx.stroke();
}

/** Loops every canvas[data-sprite] on the page; speed follows the simulated CPU. */
export function animateSprites(root: ParentNode, cpu: () => number) {
  const canvases = [...root.querySelectorAll<HTMLCanvasElement>('canvas[data-sprite]')];
  if (!canvases.length) return;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  for (const c of canvases) {
    const r = devicePixelRatio || 1;
    c.width = Math.round(c.clientWidth * r) || 40;
    c.height = Math.round(c.clientHeight * r) || 36;
  }
  let phase = 0;
  let last = performance.now();
  const frame = (now: number) => {
    const loop = 1.4 - (1.05 * Math.min(100, Math.max(0, cpu()))) / 100;
    phase = (phase + (now - last) / 1000 / loop) % 1;
    last = now;
    for (const c of canvases) {
      if (!c.isConnected || c.offsetParent === null) continue;
      drawSprite(c.getContext('2d')!, (c.dataset.sprite as Kind) || 'server', reduce ? 0.25 : phase,
        c.dataset.ink || '#fff', c.dataset.health || '#34d17a');
    }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
