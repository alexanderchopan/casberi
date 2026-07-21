// Captures clip-farcaster-apple-vid.html in REAL TIME (it plays real <video> elements)
// via Playwright's built-in video recorder, then reports the output path.
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname, 'rec-apple-vid-out');

(async () => {
  fs.rmSync(OUT_DIR, { recursive: true, force: true });
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 1080, height: 1920 },
    deviceScaleFactor: 1,
    recordVideo: { dir: OUT_DIR, size: { width: 1080, height: 1920 } },
  });
  const page = await context.newPage();
  await page.goto('file://' + path.join(__dirname, 'clip-farcaster-apple-vid.html'));
  const total = await page.evaluate(() => window.TOTAL);
  console.log('recording', total, 's...');
  await page.waitForFunction(() => window.__ready === true, { timeout: (total + 8) * 1000 });
  await context.close();
  await browser.close();

  const files = fs.readdirSync(OUT_DIR).filter(f => f.endsWith('.webm'));
  console.log('done:', files);
})();
