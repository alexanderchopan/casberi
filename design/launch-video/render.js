// Renders video.html frame-by-frame with headless Chromium.
// usage: node render.js [--preview]   (--preview: only 6 spot-check frames)
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');
const fs = require('fs');
const path = require('path');

const FPS = 30;
const FRAMES_DIR = path.join(__dirname, 'frames');
const PREVIEW = process.argv.includes('--preview');
const HTML = process.argv.find(a => a.endsWith('.html')) || 'video.html';
const SPOTS = (process.argv.find(a => a.startsWith('--spots=')) || '').slice(8)
  .split(',').filter(Boolean).map(Number);
const SIZE = (process.argv.find(a => a.startsWith('--size=')) || '--size=1920x1080').slice(7);
const [W, H] = SIZE.split('x').map(Number);

(async () => {
  fs.rmSync(FRAMES_DIR, { recursive: true, force: true });
  fs.mkdirSync(FRAMES_DIR, { recursive: true });

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(__dirname, HTML));
  await page.waitForTimeout(300); // let data-URI images decode

  const total = await page.evaluate(() => window.TOTAL);
  const nFrames = Math.round(total * FPS);

  const times = PREVIEW
    ? (SPOTS.length ? SPOTS : [0.8, 2.2, 4.2, 5.2, 8.0, 12.5])
    : Array.from({ length: nFrames }, (_, i) => i / FPS);

  let n = 0;
  for (const t of times) {
    await page.evaluate(tt => window.seek(tt), t);
    const name = PREVIEW ? `preview-${t.toFixed(1)}.png` : `f${String(n).padStart(4, '0')}.png`;
    await page.screenshot({ path: path.join(FRAMES_DIR, name) });
    n++;
    if (!PREVIEW && n % 60 === 0) console.log(`${n}/${nFrames}`);
  }
  await browser.close();
  console.log('done:', n, 'frames,', total + 's @', FPS, 'fps');
})();
