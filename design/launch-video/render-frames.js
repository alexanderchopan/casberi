// Linux-friendly sibling of render.js — renders a seek()-driven clip HTML
// frame-by-frame with the sandbox's pre-installed Chromium (no /opt/homebrew
// path, no real-time recording jank). Deterministic: every frame is a seek.
//
//   NODE_PATH=/opt/node22/lib/node_modules node render-frames.js clip-viz-reel.html \
//     --size=1920x1080 [--fps=30] [--preview] [--spots=1.0,4.5] [--poster=4.6] [--out=frames-viz]
//
// --poster=t additionally writes poster.jpg (quality 82) at that timestamp.
let chromium;
try { ({ chromium } = require('playwright')); }
catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
const fs = require('fs');
const path = require('path');

const arg = (name, dflt) => {
  const a = process.argv.find(x => x.startsWith(`--${name}=`));
  return a ? a.slice(name.length + 3) : dflt;
};
const FPS = Number(arg('fps', '30'));
const HTML = process.argv.find(a => a.endsWith('.html')) || 'clip-viz-reel.html';
const FRAMES_DIR = path.join(__dirname, arg('out', 'frames-viz'));
const PREVIEW = process.argv.includes('--preview');
const SPOTS = arg('spots', '').split(',').filter(Boolean).map(Number);
const [W, H] = arg('size', '1920x1080').split('x').map(Number);
const POSTER = arg('poster', '');

(async () => {
  fs.rmSync(FRAMES_DIR, { recursive: true, force: true });
  fs.mkdirSync(FRAMES_DIR, { recursive: true });

  const launchOpts = { args: ['--no-sandbox', '--disable-dev-shm-usage', '--force-device-scale-factor=1'] };
  if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) {
    launchOpts.executablePath = process.env.CHROME_BIN;
  }
  const browser = await chromium.launch(launchOpts);
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, HTML));
  await page.waitForTimeout(300); // let fonts settle / data-URI images decode

  const total = await page.evaluate(() => window.TOTAL);
  const nFrames = Math.round(total * FPS);

  const times = PREVIEW
    ? (SPOTS.length ? SPOTS : [0.8, 3.5, 6.0, 10.5, 13.5, 18.0, 21.0, 24.0, 25.5, 28.5])
    : Array.from({ length: nFrames }, (_, i) => i / FPS);

  let n = 0;
  for (const t of times) {
    await page.evaluate(tt => window.seek(tt), t);
    const name = PREVIEW ? `preview-${t.toFixed(1)}.png` : `f${String(n).padStart(4, '0')}.png`;
    await page.screenshot({ path: path.join(FRAMES_DIR, name) });
    n++;
    if (!PREVIEW && n % 90 === 0) console.log(`${n}/${nFrames}`);
  }
  if (POSTER) {
    await page.evaluate(tt => window.seek(tt), Number(POSTER));
    await page.screenshot({ path: path.join(FRAMES_DIR, 'poster.jpg'), type: 'jpeg', quality: 82 });
  }
  await browser.close();
  console.log('done:', n, 'frames,', total + 's @', FPS, 'fps ->', FRAMES_DIR);
})();
