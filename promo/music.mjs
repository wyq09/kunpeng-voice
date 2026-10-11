// Synthesizes out/music.wav — 100 BPM, 17 bars (40.8s), every hit locked to promo.js timings.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SR = 48000, DUR = 40.8, N = Math.ceil(SR * DUR);
const BEAT = .6, BAR = 2.4;
const L = new Float32Array(N), Rt = new Float32Array(N);   // dry bus
const vL = new Float32Array(N), vR = new Float32Array(N);  // reverb send
const mtof = m => 440 * Math.pow(2, (m - 69) / 12);
let seed = 1234567; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

function put(i, v, pan = 0, send = 0) {
  if (i < 0 || i >= N) return;
  const gl = Math.cos((pan + 1) * Math.PI / 4), gr = Math.sin((pan + 1) * Math.PI / 4);
  L[i] += v * gl; Rt[i] += v * gr;
  if (send) { vL[i] += v * gl * send; vR[i] += v * gr * send; }
}

// ---- soft-saw wavetable for pads
const TBL = 4096, saw = new Float32Array(TBL);
for (let i = 0; i < TBL; i++) { let v = 0; for (let h = 1; h <= 12; h++) v += Math.sin(2 * Math.PI * h * i / TBL) / h * Math.exp(-h * .28); saw[i] = v * .6; }

// ---- Harmony: one chord per 2 bars, finale resolves to D major
const CHORDS = [
  [0, [50, 57, 60, 64]],          // Dm9 (no 3rd, airy)
  [4.8, [46, 53, 57, 62]],        // Bbmaj7
  [9.6, [53, 57, 60, 64, 67]],    // Fmaj9
  [14.4, [48, 55, 62, 64]],       // C6/9
  [19.2, [50, 57, 60, 64, 65]],   // Dm9
  [24.0, [46, 53, 57, 60, 62]],   // Bbmaj9
  [28.8, [43, 55, 58, 62, 65]],   // Gm9
  [31.2, [45, 52, 57, 62, 64]],   // A7sus — tension into the finale
  [34.2, [38, 50, 57, 62, 66, 69, 76]], // Dmaj9 — the reveal
];
const chordAt = t => { let c = CHORDS[0][1]; for (const [s, n] of CHORDS) if (t >= s) c = n; return c; };

// ---- Pad
CHORDS.forEach(([start, notes], ci) => {
  const end = ci + 1 < CHORDS.length ? CHORDS[ci + 1][0] : DUR;
  const isFinale = start >= 34;
  const s0 = Math.floor((start - (ci ? .25 : 0)) * SR), s1 = Math.min(N, Math.floor((end + 1.4) * SR));
  const gain = (start < 2 ? .028 : .04) * (isFinale ? 1.5 : 1);
  notes.forEach((m, ni) => {
    const f = mtof(m + (m < 45 ? 12 : 0));
    [-.07, 0, .07].forEach((det, di) => {
      const ff = f * Math.pow(2, det / 12);
      let ph = (rnd() + 1) / 2 * (TBL - 1);
      const pan = (ni / Math.max(1, notes.length - 1) - .5) * .9 + (di - 1) * .25;
      for (let i = s0; i < s1; i++) {
        const t = i / SR, lt = t - start + (ci ? .25 : 0);
        const atk = Math.min(1, lt / (start < 1 ? 2.2 : .9));
        const rel = t > end ? Math.max(0, 1 - (t - end) / 1.4) : 1;
        const fade = t > 39.6 ? Math.max(0, 1 - (t - 39.6) / 1.2) : 1;
        const trem = 1 + .12 * Math.sin(t * 2 * Math.PI * .23 + ni);
        ph += ff * TBL / SR; if (ph >= TBL) ph -= TBL;
        put(i, saw[ph | 0] * gain * atk * atk * rel * trem * fade, pan, .5);
      }
    });
  });
});

// ---- Sub bass on each bar downbeat (bars 3–14), long note at the finale
for (let bt = 4.8; bt < 33.6; bt += BAR) {
  const root = chordAt(bt + .01)[0], f = mtof(root - 12 + (root < 45 ? 12 : 0));
  for (let i = 0; i < SR * 2.3; i++) {
    const t = i / SR, env = Math.min(1, t / .02) * Math.exp(-t * 1.1);
    put(Math.floor(bt * SR) + i, Math.sin(2 * Math.PI * f * t) * .22 * env);
  }
}
{ const f = mtof(38); for (let i = 0; i < SR * 6.6; i++) { const t = i / SR; put(Math.floor(34.2 * SR) + i, Math.sin(2 * Math.PI * f * t) * .25 * Math.min(1, t / .02) * Math.exp(-t * .45)); } }

// ---- Drums
function kick(at, g = .55) {
  let ph = 0;
  for (let i = 0; i < SR * .45; i++) {
    const t = i / SR, f = 45 + 95 * Math.exp(-t * 28);
    ph += 2 * Math.PI * f / SR;
    put(Math.floor(at * SR) + i, Math.sin(ph) * g * Math.exp(-t * 8) + (i < 60 ? rnd() * .1 * g : 0));
  }
}
function hat(at, g = .05, pan = .2) {
  let prev = 0;
  for (let i = 0; i < SR * .06; i++) { const n = rnd(); const hp = n - prev; prev = n; put(Math.floor(at * SR) + i, hp * g * Math.exp(-i / SR * 70), pan, .1); }
}
function clap(at, g = .14) {
  let lp = 0;
  for (let i = 0; i < SR * .22; i++) {
    const t = i / SR, n = rnd(); lp += (n - lp) * .35;
    const env = (t < .03 ? (Math.sin(t * 380) > 0 ? 1 : .4) : 1) * Math.exp(-t * 18);
    put(Math.floor(at * SR) + i, (n - lp) * g * env, 0, .45);
  }
}
for (let bt = 9.6; bt < 32.4; bt += BEAT) kick(bt, bt < 14.4 ? .42 : .55);
for (let bt = 14.4; bt < 32.4; bt += BEAT) hat(bt + .3, .045, Math.sin(bt) * .3);
for (let bt = 24.0; bt < 32.4; bt += BEAT / 2) hat(bt + .15, .022, -.3);
for (let bt = 19.2 + BEAT; bt < 32.4; bt += BEAT * 2) clap(bt);

// ---- Bell / pluck arpeggio on 8ths
function bell(at, f, g = .05, pan = 0, dec = 3.2, send = .55) {
  for (let i = 0; i < SR * 1.6; i++) {
    const t = i / SR, env = Math.min(1, t / .004) * Math.exp(-t * dec);
    const v = Math.sin(2 * Math.PI * f * t + 1.3 * Math.exp(-t * 7) * Math.sin(2 * Math.PI * f * 2.0 * t)) + .25 * Math.sin(2 * Math.PI * f * 3.01 * t) * Math.exp(-t * 6);
    put(Math.floor(at * SR) + i, v * g * env, pan, send);
  }
}
const PAT = [0, 2, 1, 3, 2, 4, 3, 1];
for (let k = 0, at = 4.8; at < 33.3; at += BEAT / 2, k++) {
  if (at >= 19.5 && at < 23.8) continue; // the emotion run gets its own line
  const c = chordAt(at + .01).slice(1), n = c[PAT[k % 8] % c.length];
  bell(at, mtof(n + 12), at < 9.6 ? .03 : .04, k % 2 ? .35 : -.35);
}
// S5: one rising note per emotion word swap (19.5 + 0.3k), 15 words
const SCALE = [62, 64, 65, 67, 69, 72, 74, 76, 77, 79, 81, 84, 86, 88, 89];
SCALE.forEach((m, k) => bell(19.5 + k * .3, mtof(m), .045, ((k % 3) - 1) * .4, 4));

// ---- Risers, impacts, whooshes
function riser(a, b, g = .12) {
  let lp = 0;
  for (let i = Math.floor(a * SR); i < Math.floor(b * SR); i++) {
    const p = (i / SR - a) / (b - a), n = rnd(); lp += (n - lp) * (.02 + .5 * p * p);
    put(i, lp * g * p * p * 2.2, Math.sin(p * 9) * .4, .4);
  }
}
function whoosh(at, d = .7, g = .08) {
  let lp = 0;
  for (let i = 0; i < SR * d; i++) {
    const p = i / (SR * d), n = rnd(); lp += (n - lp) * (.03 + .25 * Math.sin(p * Math.PI));
    put(Math.floor(at * SR) + i, lp * g * Math.sin(p * Math.PI) * 2, (p - .5) * 1.2, .3);
  }
}
function impact(at, g = .6) {
  let ph = 0, lp = 0;
  for (let i = 0; i < SR * 2.5; i++) {
    const t = i / SR, f = 30 + 70 * Math.exp(-t * 6);
    ph += 2 * Math.PI * f / SR; const n = rnd(); lp += (n - lp) * .08;
    put(Math.floor(at * SR) + i, (Math.sin(ph) * Math.exp(-t * 1.6) + lp * 1.5 * Math.exp(-t * 5)) * g, 0, .6);
  }
}
riser(8.0, 9.6, .1); impact(9.6, .5);
riser(18.0, 19.2, .07);
riser(31.6, 34.15, .16); impact(34.2, .75);
[4.75, 14.0, 24.0, 28.8].forEach(t => whoosh(t - .2, .8, .07));
whoosh(19.0, .6, .06); whoosh(33.3, .7, .06);

// ---- UI sound design
bell(.3, mtof(93), .05, 0, 2.2, .8);            // the seed of light
bell(.32, mtof(100), .025, .2, 2.5, .8);
whoosh(.9, 1.3, .05);                              // line stretches out
bell(9.3, mtof(81), .07, -.2, 2.4, .7);            // recording complete chime
bell(9.42, mtof(88), .06, .2, 2.4, .7);
function tick(at, g = .06) {
  let prev = 0; const tone = 1800 + rnd() * 600;
  for (let i = 0; i < SR * .025; i++) { const t = i / SR, n = rnd(), hp = n - prev; prev = n; put(Math.floor(at * SR) + i, (hp * .6 + Math.sin(2 * Math.PI * tone * t) * .5) * g * Math.exp(-t * 260), rnd() * .3, .08); }
}
// S4 typing: 26 units from 15.1 at 16/s
for (let i = 0; i < 26; i++) tick(15.1 + i / 16);
// button press (17.0) — soft thump + click
for (let i = 0; i < SR * .12; i++) { const t = i / SR; put(Math.floor(17.0 * SR) + i, Math.sin(2 * Math.PI * (160 - 300 * t) * t) * .22 * Math.exp(-t * 30)); }
tick(17.0, .09);
// generation sparkle → playback (17.25 / 17.55)
[0, 4, 7, 11].forEach((s, k) => bell(17.25 + k * .06, mtof(76 + s), .035, (k - 1.5) * .3, 5));
// S6 chip pops & S7 node pops
[24.8, 25.4, 25.55, 25.7].forEach((t, k) => bell(t, mtof(84 + k * 2), .03, (k - 1.5) * .3, 7, .3));
[29.4, 30.1, 30.28, 30.46].forEach((t, k) => bell(t, mtof(86 + k * 3), .032, (k - 1.5) * .3, 7, .3));
// S7 terminal typing (char counts mirror TERM_LINES)
const typeLine = (t0, t1, n) => { for (let i = 0; i < n; i++) tick(t0 + (t1 - t0) * i / n, .045); };
typeLine(29.5, 30.4, [...'$ claude mcp add clonevoice -- 鲲鹏有声 mcp'].length);
tick(30.6, .07);
typeLine(31.0, 31.9, [...'$ clonevoice speak "[开心]你好呀！" --play'].length);
// Finale title shimmer
[0, 7, 12, 16, 19].forEach((s, k) => bell(35.0 + k * .09, mtof(74 + s), .03, (k - 2) * .25, 2.2, .8));

// ---- Schroeder reverb on the send bus
function reverb(inp, offs) {
  const out = new Float32Array(N);
  const combs = [1557, 1617, 1491, 1422, 1277, 1356].map(d => ({ d: Math.round((d + offs) * SR / 44100), buf: null, i: 0, lp: 0 }));
  combs.forEach(c => c.buf = new Float32Array(c.d));
  const aps = [556, 441, 341, 225].map(d => ({ d: Math.round((d + offs) * SR / 44100), buf: null, i: 0 }));
  aps.forEach(a => a.buf = new Float32Array(a.d));
  for (let n = 0; n < N; n++) {
    const x = inp[n]; let s = 0;
    for (const c of combs) { const y = c.buf[c.i]; c.lp = y * .72 + c.lp * .28; c.buf[c.i] = x + c.lp * .86; c.i = (c.i + 1) % c.d; s += y; }
    s /= combs.length;
    for (const a of aps) { const b = a.buf[a.i]; const y = -s * .5 + b; a.buf[a.i] = s + b * .5; a.i = (a.i + 1) % a.d; s = y; }
    out[n] = s;
  }
  return out;
}
const wL = reverb(vL, 0), wR = reverb(vR, 23);

// ---- Master
const outBuf = Buffer.alloc(44 + N * 4);
let peak = 0;
const mixL = new Float32Array(N), mixR = new Float32Array(N);
for (let i = 0; i < N; i++) {
  const t = i / SR, fade = Math.min(1, t / .3) * (t > 40.0 ? Math.max(0, 1 - (t - 40.0) / .8) : 1);
  mixL[i] = Math.tanh((L[i] + wL[i] * 1.1) * 1.4) * fade;
  mixR[i] = Math.tanh((Rt[i] + wR[i] * 1.1) * 1.4) * fade;
  peak = Math.max(peak, Math.abs(mixL[i]), Math.abs(mixR[i]));
}
const norm = .89 / peak;
outBuf.write('RIFF', 0); outBuf.writeUInt32LE(36 + N * 4, 4); outBuf.write('WAVE', 8); outBuf.write('fmt ', 12);
outBuf.writeUInt32LE(16, 16); outBuf.writeUInt16LE(1, 20); outBuf.writeUInt16LE(2, 22); outBuf.writeUInt32LE(SR, 24);
outBuf.writeUInt32LE(SR * 4, 28); outBuf.writeUInt16LE(4, 32); outBuf.writeUInt16LE(16, 34); outBuf.write('data', 36); outBuf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  outBuf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixL[i] * norm)) * 32767), 44 + i * 4);
  outBuf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mixR[i] * norm)) * 32767), 46 + i * 4);
}
fs.mkdirSync(path.join(ROOT, 'out'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'out/music.wav'), outBuf);
console.log('music → out/music.wav', (N / SR).toFixed(2) + 's', 'peak', peak.toFixed(2));
