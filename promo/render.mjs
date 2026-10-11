// Usage:
//   node render.mjs                     → out/video.mp4 (60 fps, no audio)
//   FPS=30 node render.mjs              → faster draft
//   node render.mjs stills 3,7.5,12     → out/stills/*.jpg for review
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const PW_PATHS = [process.env.PLAYWRIGHT_CORE, 'playwright-core', '/private/tmp/kpshot/node_modules/playwright-core'].filter(Boolean);
let chromium;
for (const p of PW_PATHS) { try { ({ chromium } = require(p)); break; } catch { } }
if (!chromium) throw new Error('playwright-core not found; npm i playwright-core');

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/^\/$/, '/index.html'));
  fs.readFile(f, (err, buf) => { if (err) { res.writeHead(404); return res.end(); } res.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' }); res.end(buf); });
}).listen(0);
await once(server, 'listening');
const url = `http://127.0.0.1:${server.address().port}/index.html`;

// Use any cached headless shell if the exact build playwright wants isn't installed.
function findChrome() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const cache = path.join(process.env.HOME, 'Library/Caches/ms-playwright');
  const dirs = fs.existsSync(cache) ? fs.readdirSync(cache).filter(d => d.startsWith('chromium_headless_shell-')).sort().reverse() : [];
  for (const d of dirs) {
    const p = path.join(cache, d, 'chrome-headless-shell-mac-arm64/chrome-headless-shell');
    if (fs.existsSync(p)) return p;
  }
}
const browser = await chromium.launch({ executablePath: findChrome(), args: ['--force-color-profile=srgb', '--font-render-hinting=none'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
page.on('pageerror', e => { console.error('PAGE ERROR', e); process.exit(1); });
await page.goto(url);
await page.evaluate(() => window.ready);
const DUR = await page.evaluate(() => window.DURATION);
const grab = (t, type = 'image/png', q) => page.evaluate(([t, type, q]) => { window.renderFrame(t); return document.getElementById('c').toDataURL(type, q); }, [t, type, q]);

fs.mkdirSync(path.join(ROOT, 'out'), { recursive: true });
if (process.argv[2] === 'stills') {
  const dir = path.join(ROOT, 'out/stills'); fs.mkdirSync(dir, { recursive: true });
  for (const t of process.argv[3].split(',').map(Number)) {
    const b64 = await grab(t, 'image/jpeg', .82);
    fs.writeFileSync(path.join(dir, `t${t.toFixed(2)}.jpg`), Buffer.from(b64.split(',')[1], 'base64'));
  }
  console.log('stills →', dir);
} else {
  const fps = Number(process.env.FPS || 60), total = Math.round(DUR * fps);
  const out = path.join(ROOT, 'out/video.mp4');
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-tune', 'film', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let f = 0; f < total; f++) {
    const b64 = await grab(f / fps);
    if (!ff.stdin.write(Buffer.from(b64.slice(22), 'base64'))) await once(ff.stdin, 'drain');
    if (f % 120 === 0) console.log(`frame ${f}/${total}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  }
  ff.stdin.end(); await once(ff, 'close');
  console.log('video →', out);
}
await browser.close(); server.close();
