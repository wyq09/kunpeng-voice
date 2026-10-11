/* 鲲鹏有声 · Kunpeng Voice — promo film
 * Every frame is a pure function of time: window.renderFrame(t).
 * 100 BPM · 1 bar = 2.4s · scene cuts land on every second bar.
 */
const W = 1920, H = 1080, DUR = 40.8;
const cv = document.getElementById('c');
const ctx = cv.getContext('2d');

// ---------- Brand tokens (from Sources/CloneVoice/Views/Theme/Theme.swift) ----------
const C = {
  bg: '#041417', bg2: '#062026', cyan: '#40E6F2', teal: '#13B4C2', gold: '#F6B648',
  coral: '#FF6B6B', text: '#E9F7F8', muted: '#8DB2B7', ink: '#032025', mint: '#3DDC97',
};
const FONT = '"PingFang SC", "Helvetica Neue", sans-serif';
const MONO = '"SF Mono", Menlo, "PingFang SC", monospace';

// ---------- Math ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const P = (t, a, b) => clamp((t - a) / (b - a));
const TAU = Math.PI * 2;
const E = {
  inCubic: x => x * x * x,
  outCubic: x => 1 - Math.pow(1 - x, 3),
  inOutCubic: x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2,
  outQuint: x => 1 - Math.pow(1 - x, 5),
  outExpo: x => x >= 1 ? 1 : 1 - Math.pow(2, -10 * x),
  inExpo: x => x <= 0 ? 0 : Math.pow(2, 10 * x - 10),
  inOutExpo: x => x <= 0 ? 0 : x >= 1 ? 1 : x < .5 ? Math.pow(2, 20 * x - 10) / 2 : (2 - Math.pow(2, -20 * x + 10)) / 2,
  outBack: x => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); },
  inOutSine: x => -(Math.cos(Math.PI * x) - 1) / 2,
  spring: x => x <= 0 ? 0 : x >= 1 ? 1 : 1 - Math.exp(-6.5 * x) * Math.cos(11 * x),
};
const R = i => { const s = Math.sin(i * 12.9898 + 78.233) * 43758.5453; return s - Math.floor(s); };
const hexRGB = h => { const n = parseInt(h.slice(1), 16); return [n >> 16, (n >> 8) & 255, n & 255]; };
const rgba = (h, a) => { const [r, g, b] = hexRGB(h); return `rgba(${r},${g},${b},${a})`; };
const mix = (a, b, f, al = 1) => { const A = hexRGB(a), B = hexRGB(b); return `rgba(${A.map((v, i) => Math.round(lerp(v, B[i], f))).join(',')},${al})`; };

// ---------- Typography helpers ----------
function text(str, x, y, o = {}) {
  ctx.save();
  ctx.font = `${o.weight || 500} ${o.size || 32}px ${o.font || FONT}`;
  ctx.fillStyle = o.color || C.text;
  ctx.globalAlpha *= (o.alpha ?? 1);
  ctx.textAlign = o.align || 'left';
  ctx.textBaseline = 'middle';
  ctx.letterSpacing = (o.ls || 0) + 'px';
  if (o.blur > 0.3) ctx.filter = `blur(${o.blur}px)`;
  ctx.fillText(str, x + (o.align === 'center' ? (o.ls || 0) / 2 : 0), y);
  ctx.restore();
}
function measure(str, size, weight = 500, font = FONT, ls = 0) {
  ctx.save(); ctx.font = `${weight} ${size}px ${font}`; ctx.letterSpacing = '0px';
  const w = ctx.measureText(str).width + ls * Math.max(0, [...str].length - 1);
  ctx.restore(); return w;
}
/** Per-character reveal: rise + de-blur in, lift + blur out. */
function reveal(str, x, y, t, t0, o = {}) {
  const size = o.size || 32, ls = o.ls || 0, stag = o.stagger ?? .04, d = o.dur ?? .8, rise = o.rise ?? 36;
  ctx.save();
  ctx.font = `${o.weight || 600} ${size}px ${o.font || FONT}`;
  ctx.letterSpacing = '0px'; ctx.textBaseline = 'middle'; ctx.textAlign = 'left';
  const chars = [...str], ws = chars.map(c => ctx.measureText(c).width);
  const total = ws.reduce((a, b) => a + b, 0) + ls * (chars.length - 1);
  let cx = o.align === 'center' ? x - total / 2 : o.align === 'right' ? x - total : x;
  const base = ctx.globalAlpha * (o.alpha ?? 1);
  chars.forEach((c, i) => {
    const e = E.outExpo(P(t, t0 + i * stag, t0 + i * stag + d));
    let a = e, oy = (1 - e) * rise, blur = (1 - e) * 14;
    if (o.out != null) {
      const q = E.inCubic(P(t, o.out + i * stag * .4, o.out + i * stag * .4 + .45));
      a *= 1 - q; oy -= q * 26; blur += q * 12;
    }
    if (a > .002 && c !== ' ') {
      ctx.globalAlpha = base * a;
      ctx.filter = blur > .4 ? `blur(${blur.toFixed(1)}px)` : 'none';
      ctx.fillStyle = (o.colorFn && o.colorFn(i, c)) || o.color || C.text;
      ctx.fillText(c, cx, y + oy);
    }
    cx += ws[i] + ls;
  });
  ctx.restore();
  return total;
}
function rr(x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }
function glass(x, y, w, h, r, a = 1) {
  ctx.save(); ctx.globalAlpha *= a;
  rr(x, y, w, h, r);
  ctx.fillStyle = 'rgba(8,36,43,0.72)'; ctx.fill();
  const g = ctx.createLinearGradient(0, y, 0, y + h);
  g.addColorStop(0, 'rgba(120,230,240,0.10)'); g.addColorStop(.3, 'rgba(120,230,240,0.0)');
  ctx.fillStyle = g; ctx.fill();
  ctx.strokeStyle = 'rgba(120,230,240,0.18)'; ctx.lineWidth = 1.5; ctx.stroke();
  ctx.restore();
}
function pill(label, cx, cy, o = {}) {
  const size = o.size || 22, padX = o.padX ?? 18, h = o.h || size * 1.9;
  const w = measure(label, size, o.weight || 500) + padX * 2;
  ctx.save(); ctx.globalAlpha *= (o.alpha ?? 1);
  ctx.translate(cx, cy); const s = o.scale ?? 1; ctx.scale(s, s);
  rr(-w / 2, -h / 2, w, h, h / 2);
  ctx.fillStyle = o.fill || 'rgba(8,36,43,0.85)'; ctx.fill();
  if (o.stroke !== false) { ctx.strokeStyle = o.stroke || 'rgba(120,230,240,0.3)'; ctx.lineWidth = 1.5; ctx.stroke(); }
  ctx.font = `${o.weight || 500} ${size}px ${FONT}`; ctx.fillStyle = o.color || C.text;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(label, 0, 1);
  ctx.restore();
  return w;
}
/** Fixed-cell digits so a running timer never jitters. */
function digits(str, cx, cy, size, color = C.text, weight = 200) {
  ctx.save(); ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const ws = [...str].map(c => c === '.' ? size * .28 : size * .6);
  let x = cx - ws.reduce((a, b) => a + b, 0) / 2;
  [...str].forEach((c, i) => { ctx.fillText(c, x + ws[i] / 2, cy); x += ws[i]; });
  ctx.restore();
}
function label(num, title, x, y, t, t0, o = {}) {
  return reveal(`${num}  ·  ${title}`, x, y, t, t0, { size: 22, weight: 500, color: C.cyan, ls: 5, stagger: .018, rise: 14, ...o });
}

// ---------- Global energy (drives the ambient sound ribbons) ----------
const ENERGY = [[0, 0], [2, .05], [4.8, .35], [5.6, .15], [9.2, .3], [9.6, 1.1], [10.8, .3], [14.4, .55], [15.2, .2],
  [17.6, .5], [19.2, .7], [23.7, .95], [24.3, .15], [28.8, .45], [29.6, .2], [32.1, .5], [33.4, .05], [34.2, 1.4], [36.5, .55], [40.8, .35]];
function energyAt(t) {
  for (let i = 0; i < ENERGY.length - 1; i++) {
    const [a, va] = ENERGY[i], [b, vb] = ENERGY[i + 1];
    if (t <= b) return lerp(va, vb, E.inOutSine(P(t, a, b)));
  }
  return ENERGY[ENERGY.length - 1][1];
}

// ---------- Background: night sky, sound ribbons, stardust, mountains ----------
const STARS = [...Array(170)].map((_, i) => ({ x: R(i) * W, y: R(i + 500) * H * .78, r: .4 + R(i + 900) * 1.5, ph: R(i + 1300) * TAU, sp: .6 + R(i + 1700) * 2.2, gold: i % 5 === 0, z: .2 + R(i + 2100) * .8 }));
const DUST = [...Array(60)].map((_, i) => ({ x: R(i + 3000) * W, rise: .01 + R(i + 3100) * .03, off: R(i + 3200), r: .6 + R(i + 3300) * 1.6, gold: i % 3 === 0, ph: R(i + 3400) * TAU }));
const RIBBONS = [[.70, 46, 1.6, .9, C.cyan, 1.5], [.74, 64, 1.1, .6, C.cyan, 1.1], [.68, 34, 2.2, 1.1, C.gold, 1.3], [.78, 54, 1.4, .75, C.gold, 1.0], [.72, 80, .8, .5, C.teal, 1.0]];
let noisePattern = null;
function makeNoise() {
  const n = document.createElement('canvas'); n.width = n.height = 256;
  const nc = n.getContext('2d'), img = nc.createImageData(256, 256);
  for (let i = 0; i < img.data.length; i += 4) { const v = R(i * .37) * 255; img.data[i] = img.data[i + 1] = img.data[i + 2] = v; img.data[i + 3] = 255; }
  nc.putImageData(img, 0, 0); noisePattern = ctx.createPattern(n, 'repeat');
}
function background(t, en) {
  ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
  let g = ctx.createRadialGradient(W * .88, -H * .12, 0, W * .88, -H * .12, 1150);
  g.addColorStop(0, rgba(C.teal, .22)); g.addColorStop(1, rgba(C.teal, 0));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  g = ctx.createRadialGradient(-W * .05, H * .45, 0, -W * .05, H * .45, 820);
  g.addColorStop(0, rgba(C.gold, .07)); g.addColorStop(1, rgba(C.gold, 0));
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  ctx.globalCompositeOperation = 'lighter';
  for (const s of STARS) {
    const tw = .35 + .65 * (.5 + .5 * Math.sin(t * s.sp + s.ph));
    const x = ((s.x - t * 7 * s.z) % W + W) % W;
    ctx.fillStyle = rgba(s.gold ? C.gold : '#FFFFFF', .55 * tw * s.z);
    ctx.beginPath(); ctx.arc(x, s.y, s.r, 0, TAU); ctx.fill();
  }
  // energy glow
  if (en > .02) {
    const rad = W * (.32 + en * .2);
    g = ctx.createRadialGradient(W / 2, H * .66, 0, W / 2, H * .66, rad);
    g.addColorStop(0, rgba(C.cyan, .12 * Math.min(en, 1.2))); g.addColorStop(.5, rgba(C.gold, .04 * en)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  }
  // sound ribbons (they bow out of the way behind the finale title)
  const dim = 1 - .6 * E.inOutCubic(P(t, 34.8, 36.2));
  for (const [ry, amp, fr, sp, col, wd] of RIBBONS) {
    for (let s = 0; s < 3; s++) {
      ctx.beginPath();
      for (let x = 0; x <= W + 20; x += 14) {
        const u = x / W, env = .55 + .45 * Math.sin(u * Math.PI);
        const y = H * ry + Math.sin(u * Math.PI * fr * 2 + t * sp * 1.3 + s * .5) * amp * 1.5 * env * (1 + en)
          + Math.sin(u * 13 + t * sp * 2) * 6 + Math.sin(u * 47 + t * 9) * en * 12 * env + s * 6;
        x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
      }
      ctx.strokeStyle = rgba(col, Math.min(.6, (.15 - s * .042) * (1 + en * 2.2)) * dim);
      ctx.lineWidth = wd * 1.4; ctx.stroke();
    }
  }
  for (const d of DUST) {
    const y = (1 - ((d.off + t * d.rise) % 1)) * H;
    ctx.fillStyle = rgba(d.gold ? C.gold : '#A1F0F7', (.2 + .2 * Math.sin(t * 2.4 + d.ph)) * (1 + en));
    ctx.beginPath(); ctx.arc(d.x + Math.sin(t * .7 + d.ph) * 14, y, d.r, 0, TAU); ctx.fill();
  }
  ctx.globalCompositeOperation = 'source-over';
}
function mountains(t, lift) {
  const base = H - 40 - 70 * lift;
  ctx.beginPath(); ctx.moveTo(0, H);
  for (let x = 0; x <= W; x += 12) {
    const y = base - (Math.sin(x * .0042 + .6) * 34 + Math.sin(x * .011 + 1) * 20 + Math.sin(x * .027) * 8) * (.7 + lift * .5);
    ctx.lineTo(x, y);
  }
  ctx.lineTo(W, H); ctx.closePath();
  const g = ctx.createLinearGradient(0, base - 80, 0, H);
  g.addColorStop(0, 'rgba(8,51,56,0.6)'); g.addColorStop(1, C.bg);
  ctx.fillStyle = g; ctx.fill();
}
function vignette() {
  const g = ctx.createRadialGradient(W / 2, H / 2, H * .55, W / 2, H / 2, H * 1.15);
  g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.5)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}
function grain(t) {
  if (!noisePattern) makeNoise();
  ctx.save(); ctx.globalAlpha = .045; ctx.globalCompositeOperation = 'overlay';
  ctx.translate(-R(Math.floor(t * 30)) * 256, -R(Math.floor(t * 30) + 7) * 256);
  ctx.fillStyle = noisePattern; ctx.fillRect(0, 0, W + 256, H + 256);
  ctx.restore();
}

// ---------- Speech-like signal (periodic in u, so it can close into a ring) ----------
function speech(u, t, amp) {
  return (Math.sin(TAU * 12 * u + t * 11) * .5 + Math.sin(TAU * 29 * u - t * 17) * .3 +
    Math.sin(TAU * 5 * u + t * 4.3) * .5 + Math.sin(TAU * 47 * u + t * 23) * .16) * amp;
}
const syll = t => Math.pow(Math.abs(Math.sin(t * 6.1)), .6) * (.55 + .45 * Math.sin(t * 1.7 + 1)) + .18;

// =====================================================================
// S1 + S2 — The thread: point → line → voice → recording ring
// =====================================================================
const RING_C = { x: 1260, y: 540 }, RING_R = 250;
function thread(t) {
  if (t > 9.8) return;
  const fade = 1 - P(t, 9.58, 9.72);
  // the gold seed of light
  const seedA = E.outCubic(P(t, .3, .9)) * (1 - P(t, 1.0, 1.6));
  if (seedA > 0) {
    const pulse = 1 + .25 * Math.sin(t * 9);
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(960, 540, 0, 960, 540, 90 * pulse);
    g.addColorStop(0, rgba(C.gold, .9 * seedA)); g.addColorStop(.12, rgba(C.gold, .45 * seedA)); g.addColorStop(1, rgba(C.gold, 0));
    ctx.fillStyle = g; ctx.fillRect(800, 380, 320, 320);
    ctx.fillStyle = rgba('#FFFFFF', seedA); ctx.beginPath(); ctx.arc(960, 540, 3.2, 0, TAU); ctx.fill();
    ctx.restore();
  }
  if (t < .95) return;
  const len = 1560 * E.inOutExpo(P(t, .95, 2.15));
  const m = E.inOutCubic(P(t, 4.75, 5.75));                // line → ring morph
  const cx = lerp(960, RING_C.x, m), cy = 540;
  const lineAmp = 78 * E.inOutCubic(P(t, 2.0, 3.0)) * syll(t);
  const ringAmp = 34 * syll(t * 1.1) + 6;
  const N = 420;
  const strands = [[C.cyan, 1, 3.2, 0], [C.gold, .65, 2.0, .35], [C.teal, .45, 1.6, .7]];
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  for (const [col, sc, lw, ph] of strands) {
    ctx.beginPath();
    for (let i = 0; i <= N; i++) {
      const u = i / N;
      const taper = Math.pow(Math.sin(Math.PI * u), 1.4);
      const lx = cx + (u - .5) * len, ly = cy + speech(u, t + ph, lineAmp) * taper * sc;
      const a = -Math.PI / 2 + TAU * u, r = RING_R + speech(u, t * 1.2 + ph, ringAmp) * sc;
      const x = lerp(lx, cx + Math.cos(a) * r, m), y = lerp(ly, cy + Math.sin(a) * r, m);
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    let style = col;
    if (m < 1) {
      const g = ctx.createLinearGradient(cx - len / 2, 0, cx + len / 2, 0);
      g.addColorStop(0, rgba(col, m)); g.addColorStop(.2, rgba(col, 1)); g.addColorStop(.8, rgba(col, 1)); g.addColorStop(1, rgba(col, m));
      style = g;
    }
    ctx.globalAlpha = fade * (col === C.cyan ? 1 : .8);
    ctx.strokeStyle = style; ctx.lineWidth = lw; ctx.shadowColor = col; ctx.shadowBlur = 22;
    ctx.stroke();
  }
  ctx.restore();
}

function s1(t) {
  reveal('每个声音', 960, 330, t, 2.3, { size: 92, align: 'center', stagger: .09, out: 4.35, ls: 6 });
  reveal('都独一无二', 960, 760, t, 2.8, { size: 92, align: 'center', stagger: .08, out: 4.45, ls: 6, colorFn: (i) => i >= 3 ? C.gold : C.text });
  reveal('EVERY VOICE IS ONE OF A KIND', 960, 840, t, 3.3, { size: 20, weight: 400, align: 'center', color: C.muted, ls: 10, stagger: .012, rise: 10, out: 4.5 });
}

const PROMPT_LINES = ['今天的风很温柔，', '我想用自己的声音，说给你听。'];
function s2(t) {
  const { x: cx, y: cy } = RING_C;
  const out = 1 - E.inCubic(P(t, 9.3, 9.7));
  const p = P(t, 5.9, 9.3);
  ctx.save(); ctx.globalAlpha = out;
  // tick dial
  for (let i = 0; i < 72; i++) {
    const a = -Math.PI / 2 + i / 72 * TAU;
    const ta = E.outCubic(P(t, 5.3 + i * .007, 5.8 + i * .007));
    if (ta <= 0) continue;
    const lit = i / 72 < p, r1 = 318, r2 = r1 + (lit ? 18 : 10) * ta;
    ctx.strokeStyle = lit ? rgba(C.gold, .95) : rgba(C.cyan, .22 * ta);
    ctx.lineWidth = lit ? 3 : 2;
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); ctx.stroke();
  }
  // progress arc + comet head
  if (p > 0) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = C.gold; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.shadowColor = C.gold; ctx.shadowBlur = 24;
    ctx.beginPath(); ctx.arc(cx, cy, 300, -Math.PI / 2, -Math.PI / 2 + p * TAU); ctx.stroke();
    const ha = -Math.PI / 2 + p * TAU;
    ctx.fillStyle = '#FFF6E0'; ctx.beginPath(); ctx.arc(cx + Math.cos(ha) * 300, cy + Math.sin(ha) * 300, 6, 0, TAU); ctx.fill();
    ctx.restore();
  }
  // timer
  const appear = E.outCubic(P(t, 5.5, 6.2));
  ctx.globalAlpha = out * appear;
  digits((p * 10).toFixed(1), cx - 14, cy + 4, 120, C.text, 200);
  text('s', cx + 128, cy + 26, { size: 36, weight: 300, color: C.muted });
  const done = t >= 9.3;
  const blink = done ? 1 : .35 + .65 * (Math.sin(t * 6.5) > -.2 ? 1 : 0);
  ctx.fillStyle = rgba(done ? C.cyan : C.coral, blink);
  ctx.beginPath(); ctx.arc(cx - 46, cy - 112, 7, 0, TAU); ctx.fill();
  text(done ? 'DONE' : 'REC', cx - 30, cy - 111, { size: 22, weight: 600, ls: 6, color: done ? C.cyan : C.text });
  text(done ? '声音样本已就绪' : '录音中…', cx, cy + 112, { size: 24, weight: 400, align: 'center', color: done ? C.cyan : C.muted });
  ctx.restore();
  // completion shockwave
  const bp = P(t, 9.3, 10.0);
  if (bp > 0 && bp < 1) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(C.gold, (1 - bp) * .9); ctx.lineWidth = 1 + 4 * (1 - bp);
    ctx.beginPath(); ctx.arc(cx, cy, 300 + E.outCubic(bp) * 260, 0, TAU); ctx.stroke(); ctx.restore();
  }
  // copy
  label('01', '创建声音', 200, 318, t, 5.5, { out: 9.2 });
  reveal('录 10 秒', 192, 452, t, 5.75, { size: 156, stagger: .07, rise: 70, out: 9.25, colorFn: (i, c) => /\d/.test(c) ? C.gold : C.text });
  reveal('照着念一段文字，或拖入一段音频', 200, 568, t, 6.25, { size: 30, weight: 400, color: C.muted, stagger: .014, rise: 14, out: 9.3 });
  // teleprompter with karaoke progress
  const ca = E.outCubic(P(t, 6.6, 7.2)) * out;
  if (ca > 0) {
    glass(200, 630, 640, 168, 22, ca);
    ctx.save(); ctx.globalAlpha *= ca;
    text('照着念', 232, 668, { size: 18, weight: 500, color: C.muted, ls: 4 });
    const all = PROMPT_LINES.join(''), k = P(t, 6.9, 9.2) * [...all].length;
    let idx = 0;
    PROMPT_LINES.forEach((line, li) => {
      let x = 232; const y = 716 + li * 46;
      ctx.font = `500 30px ${FONT}`; ctx.textBaseline = 'middle';
      for (const ch of line) {
        const f = clamp(k - idx);
        ctx.fillStyle = f >= 1 ? C.text : f > 0 ? C.cyan : rgba(C.muted, .45);
        ctx.fillText(ch, x, y); x += ctx.measureText(ch).width; idx++;
      }
    });
    ctx.restore();
  }
}

// =====================================================================
// S3 — Shatter & re-form as a voiceprint (cyan left · gold right, like the icon)
// =====================================================================
let _glow = null;
function glowSprite() {
  if (_glow) return _glow;
  _glow = document.createElement('canvas'); _glow.width = _glow.height = 64;
  const g2 = _glow.getContext('2d'), gr = g2.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(160,245,250,0.9)'); gr.addColorStop(.35, 'rgba(64,230,242,0.35)'); gr.addColorStop(1, 'rgba(64,230,242,0)');
  g2.fillStyle = gr; g2.fillRect(0, 0, 64, 64); return _glow;
}
const PN = 950;
const PARTS = [...Array(PN)].map((_, i) => ({
  a0: i / PN * TAU, k: i % 14, th: R(i * 3.1) * TAU,
  bd: 160 + R(i * 7.7) * 520, ba: i / PN * TAU + (R(i * 1.3) - .5) * 1.1,
  del: R(i * 5.5) * .45, sz: .8 + R(i * 9.1) * 1.9, ph: R(i * 2.3) * TAU,
}));
const PRINT_C = { x: 960, y: 500 }, AVATAR = { x: 466, y: 362 }, AV_SCALE = .1;
/** S4 card slides up on a spring; the voiceprint must land on the avatar wherever the card is. */
const cardOff = t => (1 - E.spring(P(t, 14.1, 15.2))) * 80;
const ringR = (k, th, t) => 34 + k * 16 + 7 * Math.sin(th * (3 + k % 4) + k * 1.7 + t * 1.4) + 3 * Math.sin(th * 9 - t * 2 + k);
const printCol = (th, a = 1) => mix(C.cyan, C.gold, E.inOutSine(clamp(.5 + Math.cos(th) * .9)), a);
function voiceprint(t, cx, cy, sc, alpha, lw = 1.6) {
  const rot = t * .12;
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha *= alpha;
  const g = ctx.createLinearGradient(cx - 260 * sc, 0, cx + 260 * sc, 0);
  g.addColorStop(0, C.cyan); g.addColorStop(.45, '#BFF6FA'); g.addColorStop(.55, '#FFE2AE'); g.addColorStop(1, C.gold);
  ctx.strokeStyle = g; ctx.lineWidth = lw;
  for (let k = 0; k < 14; k++) {
    ctx.beginPath();
    for (let j = 0; j <= 160; j++) {
      const th = j / 160 * TAU, r = ringR(k, th, t) * sc;
      const x = cx + Math.cos(th + rot) * r, y = cy + Math.sin(th + rot) * r;
      j === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.globalAlpha = alpha * (.35 + .4 * (1 - k / 14));
    ctx.stroke();
  }
  ctx.restore();
}
function s3(t) {
  const m = E.inOutCubic(P(t, 14.0, 14.8));
  const cx = lerp(PRINT_C.x, AVATAR.x, m), cy = lerp(PRINT_C.y, AVATAR.y + cardOff(t), m), sc = lerp(1, AV_SCALE, m);
  const rot = t * .12;
  const pb = E.outExpo(P(t, 9.6, 10.5));
  // core glow
  const core = E.outCubic(P(t, 10.8, 11.8));
  if (core > 0) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, 320 * sc);
    g.addColorStop(0, rgba('#FFFFFF', .22 * core)); g.addColorStop(.25, rgba(C.cyan, .12 * core)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(cx - 320 * sc, cy - 320 * sc, 640 * sc, 640 * sc); ctx.restore();
  }
  voiceprint(t, cx, cy, sc, E.outCubic(P(t, 11.1, 12.1)), lerp(1.6, 1.1, m));
  // ripples on every beat
  for (let b = 12.0; b < 13.3; b += .6) {
    const rp = P(t, b, b + 1.3);
    if (rp <= 0 || rp >= 1) continue;
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(C.cyan, (1 - rp) * .35); ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.arc(cx, cy, (250 + E.outCubic(rp) * 230) * sc, 0, TAU); ctx.stroke(); ctx.restore();
  }
  // particles
  ctx.save(); ctx.globalCompositeOperation = 'lighter';
  for (let i = 0; i < PN; i++) {
    const q = PARTS[i];
    const sx = RING_C.x + Math.cos(q.a0) * RING_R, sy = RING_C.y + Math.sin(q.a0) * RING_R;
    const bx = sx + Math.cos(q.ba) * q.bd * pb + Math.sin(t * 2 + q.ph) * 12 * pb;
    const by = sy + Math.sin(q.ba) * q.bd * pb + Math.cos(t * 1.7 + q.ph) * 12 * pb;
    const r = ringR(q.k, q.th, t) * sc;
    const tx = cx + Math.cos(q.th + rot) * r, ty = cy + Math.sin(q.th + rot) * r;
    const pc = E.inOutCubic(P(t, 10.25 + q.del, 11.35 + q.del));
    const x = lerp(bx, tx, pc), y = lerp(by, ty, pc);
    const settle = P(t, 11.6, 12.4);
    const a = lerp(1, .55 + .45 * Math.sin(t * 3 + q.ph), settle) * (1 - P(t, 14.3, 14.8));
    const col = pc < .5 ? mix(C.gold, C.cyan, clamp(pb * 1.2), a) : printCol(q.th + rot, a);
    ctx.fillStyle = col;
    const burst = pb * (1 - pc);
    const s = q.sz * lerp(1, .7, settle) * lerp(1, .4, m) * (1 + 1.3 * burst);
    ctx.beginPath(); ctx.arc(x, y, s, 0, TAU); ctx.fill();
    if (burst > .05) { // soft round halo while flying
      const hs = s * 9;
      ctx.globalAlpha = a * .5 * burst;
      ctx.drawImage(glowSprite(), x - hs / 2, y - hs / 2, hs, hs);
      ctx.globalAlpha = 1;
    }
  }
  ctx.restore();
  label('02', '零样本克隆', 960, 150, t, 11.0, { align: 'center', out: 13.85 });
  reveal('这就是你的声音', 960, 858, t, 11.5, { size: 84, align: 'center', stagger: .07, out: 13.9, ls: 4 });
  reveal('无需训练 · 即刻可用 · Zero-shot Voice Cloning', 960, 934, t, 12.1, { size: 24, weight: 400, align: 'center', color: C.muted, stagger: .01, rise: 10, ls: 2, out: 13.95 });
}

// =====================================================================
// S4 — Type anything; it speaks in your voice
// =====================================================================
const CARD = { x: 410, y: 300, w: 1100, h: 520 };
const S4_TEXT = '[开心]你好呀！今天想听什么故事？[温柔]闭上眼睛，我讲给你听。';
const TYPE0 = 15.1, TYPE_RATE = 16, PRESS = 17.0, PLAY0 = 17.55, PLAY1 = 19.25;
const TAG_COL = { '开心': C.gold, '温柔': C.cyan };
let s4Layout = null;
function layoutS4() {
  const units = []; let i = 0, cur = C.text;
  while (i < S4_TEXT.length) {
    if (S4_TEXT[i] === '[') { const j = S4_TEXT.indexOf(']', i); const tag = S4_TEXT.slice(i + 1, j); cur = TAG_COL[tag]; units.push({ tag, col: cur }); i = j + 1; }
    else { units.push({ ch: S4_TEXT[i], col: cur }); i++; }
  }
  const maxX = CARD.x + CARD.w - 56; let x = CARD.x + 56, y = CARD.y + 184, ci = 0;
  for (const u of units) {
    u.w = u.tag ? measure(u.tag, 22, 600) + 30 : measure(u.ch, 40, 500);
    if (x + u.w > maxX) { x = CARD.x + 56; y += 66; }
    u.x = x; u.y = y; x += u.w + (u.tag ? 12 : 0);
    if (u.ch) u.ci = ci++;
  }
  return { units, chars: ci };
}
function s4(t) {
  if (!s4Layout) s4Layout = layoutS4();
  const { x, y, w, h } = CARD;
  const aa = E.outCubic(P(t, 14.2, 14.7));
  label('03', '文字转语音', 960, 150, t, 14.6, { align: 'center' });
  reveal('输入任何文字，用你的声音读出来', 960, 220, t, 14.75, { size: 60, align: 'center', stagger: .035, ls: 2 });
  ctx.save();
  ctx.translate(0, cardOff(t));
  glass(x, y, w, h, 30, aa);
  ctx.globalAlpha *= aa;
  // header — the voiceprint from S3 lands here as the avatar
  if (t >= 14.8) {
    voiceprint(t, AVATAR.x, AVATAR.y, AV_SCALE, 1, 1.1);
  }
  ctx.strokeStyle = 'rgba(120,230,240,0.35)'; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.arc(AVATAR.x, AVATAR.y, 31, 0, TAU); ctx.stroke();
  text('我的声音', x + 104, y + 50, { size: 26, weight: 600 });
  text('刚刚创建 · 10 秒样本', x + 104, y + 82, { size: 18, weight: 400, color: C.muted });
  pill('CosyVoice 3', x + w - 130, y + 62, { size: 20, color: C.cyan });
  ctx.fillStyle = 'rgba(120,230,240,0.12)'; ctx.fillRect(x + 40, y + 124, w - 80, 1.5);
  // typing
  const n = Math.floor(Math.max(0, t - TYPE0) * TYPE_RATE);
  const spoken = P(t, PLAY0, PLAY1) * s4Layout.chars;
  const playing = t > PLAY0 - .1;
  let lastX = x + 56, lastY = y + 184;
  s4Layout.units.forEach((u, i) => {
    if (i >= n) return;
    const ut = TYPE0 + i / TYPE_RATE, e = E.outCubic(P(t, ut, ut + .15));
    if (u.tag) {
      const sc = E.outBack(P(t, ut, ut + .3));
      pill(u.tag, u.x + u.w / 2, u.y, { size: 22, weight: 600, h: 40, padX: 15, color: u.col, fill: rgba(u.col, .16), stroke: rgba(u.col, .7), scale: sc, alpha: e });
    } else {
      let col = C.text;
      if (playing) { const f = clamp(spoken - u.ci); col = f > 0 ? (f >= 1 ? u.col : '#FFFFFF') : rgba(C.text, .5); }
      text(u.ch, u.x, u.y + (1 - e) * 10, { size: 40, weight: 500, color: col, alpha: e });
    }
    lastX = u.x + u.w + 4; lastY = u.y;
  });
  if (t < PRESS + .2 && t > 14.9) {
    const on = (t < TYPE0 + s4Layout.units.length / TYPE_RATE) || Math.sin(t * 9) > 0;
    if (on) { ctx.fillStyle = C.cyan; ctx.fillRect(lastX, lastY - 22, 3, 44); }
  }
  // generated waveform + playhead
  const wx0 = x + 56, wx1 = x + w - 56, wy = y + 360, NB = 120;
  const split = 13 / 24;
  for (let j = 0; j < NB; j++) {
    const f = j / (NB - 1);
    const grow = E.outBack(P(t, PRESS + .25 + f * .45, PRESS + .55 + f * .45));
    if (grow <= .001) continue;
    const gap = Math.abs(f - split) < .025 ? .08 : 1;
    const amp = (.22 + .78 * Math.abs(Math.sin(j * .37) * Math.sin(j * .113 + 1))) * (.6 + .4 * R(j)) * gap;
    const played = P(t, PLAY0, PLAY1) > f;
    const col = f < split ? C.gold : C.cyan;
    const bh = Math.max(3, amp * 46 * grow * (played ? 1 + .25 * Math.sin(t * 20 + j) : 1));
    ctx.fillStyle = played ? col : rgba(col, .28);
    const bx = lerp(wx0, wx1, f);
    rr(bx - 2.5, wy - bh, 5, bh * 2, 2.5); ctx.fill();
  }
  const ph = P(t, PLAY0, PLAY1);
  if (ph > 0 && ph < 1) {
    const px = lerp(wx0, wx1, ph);
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createRadialGradient(px, wy, 0, px, wy, 70); g.addColorStop(0, rgba('#FFFFFF', .35)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(px - 70, wy - 70, 140, 140);
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(px - 1, wy - 54, 2, 108); ctx.restore();
  }
  // footer
  text('情绪  开心 → 温柔', x + 56, y + h - 54, { size: 20, weight: 400, color: C.muted });
  text('语速  正常', x + 290, y + h - 54, { size: 20, weight: 400, color: C.muted });
  const press = P(t, PRESS, PRESS + .3), bs = 1 - .08 * Math.sin(press * Math.PI);
  ctx.save(); ctx.translate(x + w - 136, y + h - 54); ctx.scale(bs, bs);
  rr(-80, -28, 160, 56, 28);
  const bg = ctx.createLinearGradient(-80, 0, 80, 0); bg.addColorStop(0, C.cyan); bg.addColorStop(1, C.teal);
  ctx.fillStyle = bg; ctx.shadowColor = rgba(C.cyan, .5); ctx.shadowBlur = 24 + 30 * Math.sin(press * Math.PI); ctx.fill(); ctx.shadowBlur = 0;
  const btn = t < PRESS ? '▶ 生成' : t < PLAY0 ? '生成中…' : t < PLAY1 ? '播放中' : '▶ 播放';
  text(btn, 0, 1, { size: 22, weight: 600, color: C.ink, align: 'center' });
  ctx.restore();
  if (press > 0 && press < 1) {
    ctx.strokeStyle = rgba(C.cyan, 1 - press); ctx.lineWidth = 2;
    rr(x + w - 216 - press * 20, y + h - 82 - press * 20, 160 + press * 40, 56 + press * 40, 28 + press * 20); ctx.stroke();
  }
  ctx.restore();
}

// =====================================================================
// S5 — 15 emotions, kinetic slot + morphing waveform
// =====================================================================
const EMO = [
  ['自然', C.text, [60, 3, 3, .2]], ['平静', C.teal, [34, 1.6, 1.5, .05]], ['温柔', C.cyan, [44, 2, 2, .08]],
  ['开心', C.gold, [82, 4, 6, .3]], ['兴奋', '#FFC86B', [112, 6, 9, .5]], ['悲伤', '#7C9CFF', [40, 1.2, 1.2, .05]],
  ['生气', C.coral, [132, 7, 12, 1]], ['惊讶', C.gold, [100, 2.5, 5, .4]], ['害怕', '#C7D6FF', [58, 9, 14, .6]],
  ['严肃', C.text, [50, 2, 2.5, .1]], ['撒娇', '#FF9FB0', [70, 3.5, 4, .25]], ['播音', C.cyan, [66, 3, 3.5, .15]],
  ['讲故事', C.gold, [56, 2.2, 2.2, .12]], ['广告', '#FFD98A', [96, 5, 7, .35]], ['耳语', C.muted, [16, 5, 6, .4]],
];
const EMO0 = 19.5, EMO_STEP = .3;
function emoWave(u, t, [amp, fr, sp, jag]) {
  const env = Math.pow(Math.sin(Math.PI * u), 1.2);
  return (Math.sin(u * TAU * fr + t * sp) + jag * .45 * Math.sin(u * TAU * fr * 5.3 + t * sp * 2.1)) * amp * env;
}
let chipLayout = null;
function s5(t) {
  const fIdx = (t - EMO0) / EMO_STEP;
  const idx = clamp(Math.floor(fIdx), 0, EMO.length - 1);
  const e = t < EMO0 ? 0 : idx === EMO.length - 1 && fIdx > EMO.length ? 1 : E.outCubic(clamp((fIdx - idx) / .6));
  const intro = E.outCubic(P(t, 19.2, 19.7));
  // giant ghost numeral
  ctx.save(); ctx.globalAlpha *= .07 * intro;
  ctx.font = `700 760px ${FONT}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.strokeStyle = C.cyan; ctx.lineWidth = 2;
  const gs = 1 + (t - 19.2) * .02; ctx.translate(960, 520); ctx.scale(gs, gs); ctx.strokeText('15', 0, 0);
  ctx.restore();
  label('04', '情绪与场景', 960, 150, t, 19.3, { align: 'center' });
  reveal('15 种语气，一键切换', 960, 220, t, 19.4, { size: 56, align: 'center', stagger: .04, ls: 2, colorFn: (i) => i < 2 ? C.gold : C.text });
  // morphing waveform
  const cur = EMO[idx], prev = EMO[Math.max(0, idx - 1)];
  const wy = 640, wx0 = 310, wx1 = 1610;
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha *= intro;
  for (let s = 0; s < 3; s++) {
    ctx.beginPath();
    for (let i = 0; i <= 260; i++) {
      const u = i / 260;
      const v = lerp(emoWave(u, t + s * .15, prev[2]), emoWave(u, t + s * .15, cur[2]), idx === 0 ? 1 : e);
      const xx = lerp(wx0, wx1, u), yy = wy + v * (1 - s * .25);
      i ? ctx.lineTo(xx, yy) : ctx.moveTo(xx, yy);
    }
    const col = mix(prev[1], cur[1], e);
    ctx.strokeStyle = col; ctx.lineWidth = 3 - s; ctx.shadowColor = col; ctx.shadowBlur = 18;
    ctx.globalAlpha = intro * (.9 - s * .28);
    ctx.stroke();
  }
  ctx.restore();
  // slot word
  if (t >= EMO0) {
    const pe = EMO[idx - 1];
    ctx.save(); ctx.beginPath(); ctx.rect(0, 340, W, 220); ctx.clip();
    if (pe && e < 1) text(pe[0], 960, 452 - e * 110, { size: 150, weight: 600, align: 'center', color: pe[1], alpha: 1 - e, blur: e * 10, ls: 8 });
    text(cur[0], 960, 452 + (1 - e) * 110, { size: 150, weight: 600, align: 'center', color: cur[1], alpha: e, blur: (1 - e) * 10, ls: 8 });
    ctx.restore();
  }
  // chip rail
  if (!chipLayout) {
    const ws = EMO.map(([n]) => measure(n, 22, 500) + 36), gap = 14;
    const tot = ws.reduce((a, b) => a + b, 0) + gap * (ws.length - 1);
    let x = 960 - tot / 2; chipLayout = ws.map(w => { const c = x + w / 2; x += w + gap; return c; });
  }
  EMO.forEach(([n, col], i) => {
    const ap = E.outBack(P(t, 19.6 + i * .03, 20.0 + i * .03));
    if (ap <= 0) return;
    const active = t >= EMO0 && i === idx, visited = t >= EMO0 && i < idx;
    const finale = E.outCubic(P(t, 23.75 + i * .012, 23.95 + i * .012));
    const lit = active ? 1 : finale;
    pill(n, chipLayout[i], 880, {
      size: 22, scale: ap * (active ? 1.12 : 1), color: lit ? (active ? C.ink : col) : visited ? C.text : C.muted,
      fill: active ? col : lit ? rgba(col, .18) : 'rgba(8,36,43,0.85)', stroke: active ? col : rgba(lit ? col : C.cyan, lit ? .6 : visited ? .35 : .18),
    });
  });
  reveal('写下 [生气]我真的生气了。[平静]算了。  就能逐段切换', 960, 962, t, 20.4, { size: 22, weight: 400, align: 'center', color: C.muted, stagger: .008, rise: 8 });
}

// =====================================================================
// S6 — Fully local on Apple Silicon. Nothing leaves your Mac.
// =====================================================================
const LP = { cx: 640, cy: 500, w: 640, h: 400 };
const TRACES = (() => {
  const out = [], { cx, cy, w, h } = LP, ccx = cx, ccy = cy - 10, half = 75;
  const L = cx - w / 2 + 26, Rr = cx + w / 2 - 26, T = cy - h / 2 + 26, B = cy + h / 2 - 26;
  for (let k = 0; k < 3; k++) {
    const o = (k - 1) * 40, j = (k - 1) * 60;
    out.push([[ccx + half, ccy + o], [ccx + half + 50, ccy + o], [ccx + half + 90, ccy + o + j], [Rr, ccy + o + j]]);
    out.push([[ccx - half, ccy + o], [ccx - half - 50, ccy + o], [ccx - half - 90, ccy + o + j], [L, ccy + o + j]]);
    out.push([[ccx + o, ccy - half], [ccx + o, ccy - half - 30], [ccx + o + j * 1.6, ccy - half - 70], [ccx + o + j * 1.6, T]]);
    out.push([[ccx + o, ccy + half], [ccx + o, ccy + half + 30], [ccx + o + j * 1.6, ccy + half + 70], [ccx + o + j * 1.6, B]]);
  }
  return out.map(pts => { let len = 0; const seg = []; for (let i = 1; i < pts.length; i++) { const d = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); seg.push(d); len += d; } return { pts, seg, len }; });
})();
function alongTrace(tr, f) {
  let d = f * tr.len;
  for (let i = 0; i < tr.seg.length; i++) {
    if (d <= tr.seg[i]) { const a = tr.pts[i], b = tr.pts[i + 1], q = d / tr.seg[i]; return [lerp(a[0], b[0], q), lerp(a[1], b[1], q)]; }
    d -= tr.seg[i];
  }
  return tr.pts[tr.pts.length - 1];
}
const MODELS = ['CosyVoice 3', 'VoxCPM 2', 'Qwen3-TTS'];
function orbitChips(t, front) {
  MODELS.forEach((m, i) => {
    const a = (t - 24) * .55 + i * TAU / 3 + .6;
    const depth = Math.sin(a);
    if ((depth > 0) !== front) return;
    const ap = E.outBack(P(t, 25.4 + i * .15, 25.9 + i * .15));
    if (ap <= 0) return;
    const x = LP.cx + Math.cos(a) * 430, y = LP.cy + 30 + depth * 120;
    const s = (.82 + .2 * (depth + 1) / 2) * ap;
    pill(m, x, y, { size: 22, scale: s, color: C.cyan, alpha: .45 + .55 * (depth + 1) / 2, stroke: rgba(C.cyan, .45) });
  });
}
function s6(t) {
  const { cx, cy, w, h } = LP;
  const draw = E.inOutCubic(P(t, 24.1, 25.1));
  orbitChips(t, false);
  ctx.save();
  // screen fill
  ctx.globalAlpha *= E.outCubic(P(t, 24.6, 25.2));
  rr(cx - w / 2, cy - h / 2, w, h, 22); ctx.fillStyle = '#05191D'; ctx.fill();
  ctx.restore();
  ctx.save();
  ctx.strokeStyle = rgba(C.cyan, .75); ctx.lineWidth = 2.2; ctx.lineCap = 'round'; ctx.shadowColor = C.cyan; ctx.shadowBlur = 12;
  ctx.setLineDash([2200, 2200]); ctx.lineDashOffset = 2200 * (1 - draw);
  rr(cx - w / 2, cy - h / 2, w, h, 22); ctx.stroke();
  ctx.setLineDash([2000, 2000]); ctx.lineDashOffset = 2000 * (1 - E.inOutCubic(P(t, 24.4, 25.3)));
  ctx.beginPath(); ctx.moveTo(cx - w / 2 - 70, cy + h / 2 + 22); ctx.lineTo(cx + w / 2 + 70, cy + h / 2 + 22);
  ctx.lineTo(cx + w / 2 + 40, cy + h / 2 + 40); ctx.lineTo(cx - w / 2 - 40, cy + h / 2 + 40); ctx.closePath(); ctx.stroke();
  ctx.restore();
  // privacy boundary — marching ants
  const sa = E.outCubic(P(t, 25.6, 26.2));
  if (sa > 0) {
    ctx.save(); ctx.globalAlpha *= sa; ctx.strokeStyle = rgba(C.gold, .45); ctx.lineWidth = 1.5;
    ctx.setLineDash([8, 10]); ctx.lineDashOffset = -t * 30;
    rr(cx - w / 2 + 12, cy - h / 2 + 12, w - 24, h - 24, 14); ctx.stroke(); ctx.restore();
  }
  // traces & bouncing pulses (data reaches the edge… and comes back)
  const ta = E.outCubic(P(t, 25.0, 25.6));
  if (ta > 0) {
    ctx.save(); ctx.globalAlpha *= ta;
    TRACES.forEach((tr, i) => {
      ctx.strokeStyle = rgba(C.cyan, .22); ctx.lineWidth = 1.5; ctx.beginPath();
      tr.pts.forEach(([x, y], j) => j ? ctx.lineTo(x, y) : ctx.moveTo(x, y)); ctx.stroke();
      const ph = ((t - 25.2) * .7 + R(i * 4.1)) % 1, f = ph < .5 ? ph * 2 : 2 - ph * 2;
      const [px, py] = alongTrace(tr, E.inOutSine(f));
      ctx.save(); ctx.globalCompositeOperation = 'lighter';
      const near = f > .9;
      ctx.fillStyle = near ? C.gold : C.cyan; ctx.shadowColor = near ? C.gold : C.cyan; ctx.shadowBlur = 14;
      ctx.beginPath(); ctx.arc(px, py, near ? 4 : 3, 0, TAU); ctx.fill(); ctx.restore();
    });
    ctx.restore();
  }
  // Apple Silicon chip
  const cp = E.outBack(P(t, 24.8, 25.4));
  if (cp > 0) {
    ctx.save(); ctx.translate(cx, cy - 10); ctx.scale(cp, cp);
    ctx.strokeStyle = rgba(C.gold, .8); ctx.lineWidth = 2;
    for (let k = 0; k < 6; k++) {
      const o = -50 + k * 20;
      [[o, -75, o, -88], [o, 75, o, 88], [-75, o, -88, o], [75, o, 88, o]].forEach(([a, b, c, d]) => { ctx.beginPath(); ctx.moveTo(a, b); ctx.lineTo(c, d); ctx.stroke(); });
    }
    rr(-75, -75, 150, 150, 20);
    const g = ctx.createLinearGradient(-75, -75, 75, 75); g.addColorStop(0, '#13343A'); g.addColorStop(1, '#0A1F24');
    ctx.fillStyle = g; ctx.fill(); ctx.shadowColor = C.gold; ctx.shadowBlur = 20 + 10 * Math.sin(t * 4); ctx.stroke(); ctx.shadowBlur = 0;
    text('Apple', 0, -14, { size: 22, weight: 600, align: 'center', color: C.gold });
    text('Silicon', 0, 16, { size: 22, weight: 600, align: 'center', color: C.gold });
    ctx.restore();
  }
  orbitChips(t, true);
  // copy
  label('05', '隐私优先', 1180, 360, t, 24.6);
  reveal('完全本地运行', 1172, 460, t, 24.8, { size: 92, stagger: .06, rise: 50 });
  reveal('音频不上传', 1172, 572, t, 25.2, { size: 92, stagger: .06, rise: 50, colorFn: i => i >= 2 ? C.gold : C.text });
  reveal('推理全部在 Apple Silicon 上完成', 1180, 668, t, 25.7, { size: 28, weight: 400, color: C.muted, stagger: .012, rise: 12 });
  reveal('录音与生成结果，只留在你的 Mac 上', 1180, 712, t, 25.9, { size: 28, weight: 400, color: C.muted, stagger: .012, rise: 12 });
}

// =====================================================================
// S7 — Plug into AI agents (MCP / CLI)
// =====================================================================
const TERM = { x: 150, y: 300, w: 900, h: 390 };
const TERM_LINES = [
  { t0: 29.5, t1: 30.4, segs: [['$ ', C.cyan], ['claude mcp add clonevoice -- ', C.text], ['鲲鹏有声', C.gold], [' mcp', C.text]] },
  { t0: 30.6, t1: 30.6, segs: [['✓ ', C.mint], ['Added MCP server ', C.muted], ['clonevoice', C.cyan]] },
  { t0: 31.0, t1: 31.9, segs: [['$ ', C.cyan], ['clonevoice speak ', C.text], ['"[开心]你好呀！"', C.gold], [' --play', C.muted]] },
  { t0: 32.1, t1: 32.1, segs: [['▶ ', C.gold], ['正在用「我的声音」朗读', C.text]] },
];
const HUB = { x: 1470, y: 560 };
const NODES = [{ n: 'Claude Code', x: 1240, y: 330 }, { n: 'Cursor', x: 1720, y: 360 }, { n: 'Codex', x: 1590, y: 840 }];
const SPEAK0 = 32.1;
function bez(a, b, f) {
  const mx = (a.x + b.x) / 2 + (b.y - a.y) * .25, my = (a.y + b.y) / 2 - (b.x - a.x) * .25;
  const u = 1 - f; return [u * u * a.x + 2 * u * f * mx + f * f * b.x, u * u * a.y + 2 * u * f * my + f * f * b.y];
}
function s7(t) {
  label('06', '接入 AI Agent', 150, 168, t, 28.9);
  reveal('让 AI 用你的声音说话', 146, 236, t, 29.05, { size: 60, stagger: .04, ls: 2 });
  // terminal
  const tp = E.spring(P(t, 28.9, 29.9)), ta = E.outCubic(P(t, 28.9, 29.3));
  ctx.save(); ctx.translate(-(1 - tp) * 120, 0); ctx.globalAlpha *= ta;
  const { x, y, w, h } = TERM;
  rr(x, y, w, h, 20); ctx.fillStyle = 'rgba(2,14,17,0.92)'; ctx.fill(); ctx.strokeStyle = 'rgba(120,230,240,0.18)'; ctx.lineWidth = 1.5; ctx.stroke();
  [C.coral, C.gold, C.mint].forEach((c, i) => { ctx.fillStyle = c; ctx.beginPath(); ctx.arc(x + 30 + i * 24, y + 26, 7, 0, TAU); ctx.fill(); });
  text('zsh — clonevoice', x + w / 2, y + 26, { size: 16, weight: 400, color: C.muted, align: 'center' });
  ctx.fillStyle = 'rgba(120,230,240,0.10)'; ctx.fillRect(x, y + 52, w, 1);
  let cursor = null;
  TERM_LINES.forEach((ln, li) => {
    const full = ln.segs.map(s => s[0]).join(''), N = [...full].length;
    const shown = ln.t1 > ln.t0 ? Math.floor(P(t, ln.t0, ln.t1) * N) : (t >= ln.t0 ? N : 0);
    if (shown <= 0) return;
    const ly = y + 104 + li * 58;
    const fa = ln.t1 > ln.t0 ? 1 : E.outCubic(P(t, ln.t0, ln.t0 + .25));
    let cx = x + 36, left = shown;
    ctx.save(); ctx.globalAlpha *= fa; ctx.font = `400 25px ${MONO}`; ctx.textBaseline = 'middle';
    for (const [s, col] of ln.segs) {
      const part = [...s].slice(0, Math.max(0, left)).join(''); left -= [...s].length;
      ctx.fillStyle = col; ctx.fillText(part, cx, ly); cx += ctx.measureText(part).width;
      if (left <= 0) break;
    }
    ctx.restore();
    cursor = [cx + 4, ly];
    if (li === 3) { // inline live waveform
      for (let j = 0; j < 22; j++) {
        const on = E.outCubic(P(t, SPEAK0 + .1 + j * .02, SPEAK0 + .3 + j * .02));
        const hh = Math.max(2, on * (6 + 18 * Math.abs(Math.sin(t * 13 + j * .9)) * syll(t + j * .05)));
        ctx.fillStyle = j % 2 ? C.cyan : C.gold; rr(cx + 24 + j * 9, ly - hh, 4, hh * 2, 2); ctx.fill();
      }
    }
  });
  if (cursor && (Math.sin(t * 9) > 0 || (t > 29.5 && t < 31.9))) { ctx.fillStyle = rgba(C.cyan, .85); ctx.fillRect(cursor[0], cursor[1] - 14, 12, 28); }
  ctx.restore();
  // links hub → agents
  NODES.forEach((nd, i) => {
    const lp = E.inOutCubic(P(t, 29.7 + i * .18, 30.4 + i * .18));
    if (lp <= 0) return;
    ctx.save(); ctx.strokeStyle = rgba(C.cyan, .35); ctx.lineWidth = 1.6; ctx.beginPath();
    for (let j = 0; j <= 40; j++) { const f = j / 40 * lp; const [bx, by] = bez(HUB, nd, f); j ? ctx.lineTo(bx, by) : ctx.moveTo(bx, by); }
    ctx.stroke(); ctx.restore();
    // pulses when the voice speaks
    for (let b = SPEAK0; b < 33.4; b += .3) {
      const f = P(t, b + i * .05, b + i * .05 + .55);
      if (f <= 0 || f >= 1) continue;
      const [px, py] = bez(HUB, nd, E.inOutSine(f));
      ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = C.gold; ctx.shadowColor = C.gold; ctx.shadowBlur = 16;
      ctx.beginPath(); ctx.arc(px, py, 4.5, 0, TAU); ctx.fill(); ctx.restore();
    }
  });
  NODES.forEach((nd, i) => {
    const ap = E.outBack(P(t, 30.1 + i * .18, 30.5 + i * .18));
    if (ap <= 0) return;
    const hot = t > SPEAK0 + .5 ? .5 + .5 * Math.sin((t - SPEAK0) * TAU / .6) : 0;
    pill(nd.n, nd.x, nd.y, { size: 24, h: 60, padX: 26, scale: ap, weight: 600, stroke: rgba(hot ? C.gold : C.cyan, .4 + .4 * hot), color: C.text });
    if (hot) { // sound arcs
      ctx.save(); ctx.strokeStyle = rgba(C.gold, .5 * hot); ctx.lineWidth = 2;
      const pw = measure(nd.n, 24, 600) / 2 + 40;
      for (let k = 0; k < 2; k++) { ctx.beginPath(); ctx.arc(nd.x + pw, nd.y, 10 + k * 10, -.7, .7); ctx.stroke(); }
      ctx.restore();
    }
  });
  // hub = the app icon
  const hp = E.outBack(P(t, 29.4, 30.0));
  if (hp > 0 && ICON.complete) {
    for (let b = 29.6; b < 33.6; b += .6) {
      const rp = P(t, b, b + 1.2); if (rp <= 0 || rp >= 1) continue;
      ctx.strokeStyle = rgba(C.cyan, (1 - rp) * .4); ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(HUB.x, HUB.y, 80 + rp * 120, 0, TAU); ctx.stroke();
    }
    const s = 150 * hp;
    ctx.save(); ctx.shadowColor = rgba(C.cyan, .6); ctx.shadowBlur = 40;
    rr(HUB.x - s / 2, HUB.y - s / 2, s, s, s * .23); ctx.fillStyle = C.bg; ctx.fill(); ctx.shadowBlur = 0; ctx.clip();
    ctx.drawImage(ICON, HUB.x - s / 2, HUB.y - s / 2, s, s); ctx.restore();
    text('鲲鹏有声 MCP', HUB.x, HUB.y + 108, { size: 20, weight: 500, align: 'center', color: C.muted, alpha: hp, ls: 2 });
  }
}

// =====================================================================
// S8 — Finale
// =====================================================================
const ICON = new Image();
function s8(t) {
  // implosion flash
  const fl = P(t, 33.9, 34.25), fo = P(t, 34.25, 35.1);
  if (fl > 0 && fo < 1) {
    const a = fl < 1 ? E.inExpo(fl) : 1 - E.outCubic(fo);
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const r = lerp(20, 1400, fl < 1 ? E.inExpo(fl) * .3 : .3 + E.outCubic(fo) * .7);
    const g = ctx.createRadialGradient(960, 420, 0, 960, 420, r);
    g.addColorStop(0, rgba('#FFFFFF', a)); g.addColorStop(.2, rgba(C.cyan, .5 * a)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.restore();
  }
  // a horizontal light streak right at the hit
  const st = P(t, 34.15, 34.9);
  if (st > 0 && st < 1) {
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    const g = ctx.createLinearGradient(0, 0, W, 0);
    g.addColorStop(0, rgba(C.cyan, 0)); g.addColorStop(.5, rgba('#FFFFFF', (1 - st) * .9)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(0, 420 - 1.5 - (1 - st) * 2, W, 3 + (1 - st) * 4); ctx.restore();
  }
  // sound rings from the icon on the beat
  for (let b = 34.2; b < 39.0; b += .6) {
    const rp = P(t, b, b + 1.8); if (rp <= 0 || rp >= 1) continue;
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    ctx.strokeStyle = rgba(Math.round((b - 34.2) / .6) % 2 ? C.gold : C.cyan, (1 - rp) * .32); ctx.lineWidth = 1.4;
    ctx.beginPath(); ctx.arc(960, 420, 150 + E.outCubic(rp) * 420, 0, TAU); ctx.stroke(); ctx.restore();
  }
  // icon
  const ip = P(t, 34.15, 35.3);
  if (ip > 0 && ICON.complete) {
    const s = 250 * lerp(.62, 1, E.spring(ip)), a = E.outCubic(P(t, 34.15, 34.6)), bl = (1 - E.outCubic(P(t, 34.15, 34.8))) * 18;
    const float = Math.sin((t - 34) * 1.6) * 5;
    ctx.save(); ctx.globalAlpha *= a;
    const g = ctx.createRadialGradient(960, 420, 0, 960, 420, 340);
    g.addColorStop(0, rgba(C.cyan, .28)); g.addColorStop(1, rgba(C.cyan, 0));
    ctx.fillStyle = g; ctx.fillRect(600, 60, 720, 720);
    if (bl > .4) ctx.filter = `blur(${bl}px)`;
    ctx.translate(0, float);
    rr(960 - s / 2, 420 - s / 2, s, s, s * .23); ctx.save(); ctx.clip();
    ctx.drawImage(ICON, 960 - s / 2, 420 - s / 2, s, s);
    // light sweep
    const sw = P(t, 35.0, 35.9);
    if (sw > 0 && sw < 1) {
      const sx = lerp(960 - s, 960 + s, E.inOutCubic(sw));
      const lg = ctx.createLinearGradient(sx - 80, 0, sx + 80, 0);
      lg.addColorStop(0, 'rgba(255,255,255,0)'); lg.addColorStop(.5, 'rgba(255,255,255,0.38)'); lg.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = lg;
      ctx.translate(sx, 420); ctx.rotate(.35); ctx.translate(-sx, -420); ctx.fillRect(sx - 80, 420 - s, 160, s * 2);
    }
    ctx.restore();
    ctx.strokeStyle = 'rgba(160,240,248,0.25)'; ctx.lineWidth = 1.5; rr(960 - s / 2, 420 - s / 2, s, s, s * .23); ctx.stroke();
    ctx.restore();
  }
  reveal('鲲鹏有声', 960, 648, t, 35.0, { size: 112, stagger: .09, rise: 50, ls: 18, align: 'center' });
  reveal('KUNPENG VOICE', 960, 724, t, 35.5, { size: 24, weight: 500, color: C.muted, ls: 16, align: 'center', stagger: .02, rise: 10 });
  reveal('录 10 秒，用你的声音读出任何文字。', 960, 812, t, 36.1, { size: 40, weight: 500, align: 'center', stagger: .035, rise: 18, colorFn: (i, c) => /\d/.test(c) ? C.gold : C.text });
  const ia = E.outCubic(P(t, 37.0, 37.8));
  if (ia > 0) {
    const a = 'voice.kunpeng.si', b = '   ·   macOS 15+   ·   Apple Silicon   ·   开源免费';
    const wa = measure(a, 24, 500), wb = measure(b, 22, 400), x0 = 960 - (wa + wb) / 2;
    text(a, x0, 962 + (1 - ia) * 12, { size: 24, weight: 500, color: C.cyan, alpha: ia });
    text(b, x0 + wa, 962 + (1 - ia) * 12, { size: 22, weight: 400, color: C.muted, alpha: ia });
  }
}

// =====================================================================
// Compositor
// =====================================================================
function layer(t, outT, outD, zoom, fn) {
  const o = E.inCubic(P(t, outT, outT + outD));
  if (o >= 1) return;
  ctx.save(); ctx.globalAlpha = 1 - o;
  const s = 1 + zoom * o; ctx.translate(960, 540); ctx.scale(s, s); ctx.translate(-960, -540);
  if (o > .05) ctx.filter = `blur(${(o * 8).toFixed(1)}px)`;
  fn(); ctx.restore();
}
function renderFrame(t) {
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.filter = 'none'; ctx.globalCompositeOperation = 'source-over';
  const en = energyAt(t);
  background(t, en);
  mountains(t, lerp(.4, 1.3, E.inOutCubic(P(t, 34, 36.5))));
  if (t < 9.8) thread(t);
  if (t < 5) s1(t);
  if (t > 5 && t < 10) s2(t);
  if (t > 9.55 && t < 14.85) s3(t);
  if (t > 14.25 && t < 19.8) layer(t, 19.15, .5, .1, () => s4(t));
  if (t > 19.15 && t < 24.5) layer(t, 23.95, .45, -.12, () => s5(t));
  if (t > 24.0 && t < 29.4) layer(t, 28.7, .5, .08, () => s6(t));
  if (t > 28.8 && t < 34.1) layer(t, 33.3, .6, -.25, () => s7(t));
  if (t > 33.8) s8(t);
  vignette();
  grain(t);
  const fade = Math.max(1 - P(t, 0, .5), P(t, 39.9, 40.8));
  if (fade > 0) { ctx.fillStyle = `rgba(0,0,0,${fade})`; ctx.fillRect(0, 0, W, H); }
}
window.renderFrame = renderFrame;
window.DURATION = DUR;
window.ready = new Promise(res => {
  ICON.onload = () => document.fonts.ready.then(() => { renderFrame(0); res(true); });
  ICON.src = 'assets/icon.png';
});
// Realtime preview: open index.html#play (served over http)
if (location.hash === '#play') {
  window.ready.then(() => {
    const start = performance.now();
    const loop = () => { renderFrame(((performance.now() - start) / 1000) % DUR); requestAnimationFrame(loop); };
    loop();
  });
}
