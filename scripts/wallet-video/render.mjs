// Records scripts/wallet-video/wallet-demo.html to a video using Playwright's
// native (ffmpeg-backed) recorder. No Xcode/simulator needed — this runs the
// walkthrough in headless Chromium and captures the canvas as it auto-plays.
//
//   node render.mjs [outDir]
//
// Chromium + ffmpeg are provided by the bundled Playwright browsers under
// PLAYWRIGHT_BROWSERS_PATH (/opt/pw-browsers here). The playwright npm package
// is resolved from NODE_PATH (see the sibling render.sh).
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const W = 1080, H = 1920;
const outDir = process.argv[2] || path.join(__dirname, 'out');
fs.mkdirSync(outDir, { recursive: true });

// Prefer the sandbox-provided Chromium when its revision differs from what the
// installed playwright expects (set CHROME_BIN); falls back to playwright's own.
const launchOpts = {
  args: ['--no-sandbox', '--disable-dev-shm-usage', '--force-device-scale-factor=1'],
};
if (process.env.CHROME_BIN && fs.existsSync(process.env.CHROME_BIN)) {
  launchOpts.executablePath = process.env.CHROME_BIN;
}
const browser = await chromium.launch(launchOpts);
const context = await browser.newContext({
  viewport: { width: W, height: H },
  deviceScaleFactor: 1,
  recordVideo: { dir: outDir, size: { width: W, height: H } },
});
const page = await context.newPage();
const url = 'file://' + path.join(__dirname, 'wallet-demo.html');
await page.goto(url, { waitUntil: 'load' });

// Let the director run to completion (it sets window.__done), with a hard cap.
await page.waitForFunction('window.__done === true', null, { timeout: 60000 })
  .catch(() => console.warn('timeline did not finish before timeout — capturing what played'));
await page.waitForTimeout(400);

const video = page.video();
await context.close();      // flush + finalize the .webm
await browser.close();

const src = await video.path();
const dest = path.join(outDir, 'casberi-wallet.webm');
fs.renameSync(src, dest);
console.log('VIDEO:' + dest);
