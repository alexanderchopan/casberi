// Mac App Store screenshots — EDITORIAL frame around the REAL app windows.
// Takes the user's actual CleanShot window captures (2036×1510 @2x) and sets
// each one on the editorial poster: cream ground, grain, CASBERI mast, big
// headline + grounded subhead, the real window in a rounded shadowed frame.
//
//   node build-mac-appstore-real.js [W] [H] [outDir]
//   default: 2880x1800 (largest accepted Mac size; 1280x800 / 1440x900 /
//   2560x1600 are the same 16:10 ratio, so this master downscales cleanly).
//
// Headlines are grounded in what is actually visible in each capture —
// no invented UI, no claims the shot doesn't show.
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');

const W = parseInt(process.argv[2] || '2880', 10);
const H = parseInt(process.argv[3] || '1800', 10);
const OUT = process.argv[4] || path.join(__dirname, 'appstore-mac-real');
const S = W / 2880;
const px = n => Math.round(n * S) + 'px';

const DL = '/Users/alexanderchopan/Downloads';
const SHOTS = [
  {
    id: '1-overview', file: 'CleanShot 2026-08-01 at 18.48.41@2x.png', accent: '#2E63FF',
    head: 'Everything you keep,\non your Mac.',
    sub: 'Your themes, your wallet activity, the art you follow — one window, side by side.',
  },
  {
    id: '2-wallet', file: 'CleanShot 2026-08-01 at 18.49.41@2x.png', accent: '#3fb950',
    head: 'Every wallet.\nOne picture.',
    sub: 'Watch any wallet — an ENS name is enough. Balances, holdings and what’s worth a look, read-only.',
  },
  {
    id: '3-today', file: 'CleanShot 2026-08-01 at 18.51.23@2x.png', accent: '#2E63FF',
    head: 'One glance,\nyour whole day.',
    sub: 'What settled, what’s up next, what’s overdue — composed on your Mac from your own things.',
  },
  {
    id: '4-farcaster', file: 'CleanShot 2026-08-01 at 18.50.03@2x.png', accent: '#855dcd',
    head: 'The people you follow,\nnot an algorithm.',
    sub: 'Farcaster channels and casts land as things — open one and read the whole thread beside your feed.',
  },
  {
    id: '5-bluesky', file: 'CleanShot 2026-08-01 at 18.50.19@2x.png', accent: '#0085ff',
    head: 'Their posting year,\nat a glance.',
    sub: 'Watch a Bluesky account and every post lands — with an activity map of how they show up.',
  },
  {
    id: '6-art', file: 'CleanShot 2026-08-01 at 18.51.46@2x.png', accent: '#ff453a',
    head: 'A feed that’s yours.\nNothing ranked, nothing pushed.',
    sub: 'Mints, doodles, posts and links from the sources you chose — in the order they happened.',
  },
  {
    id: '7-catalog', file: 'CleanShot 2026-08-01 at 18.49.17@2x.png', accent: '#2E63FF',
    head: 'Connect it once.\nIt keeps landing.',
    sub: 'Social, mail, agents, media — most sources are keyless, and none of them see your other things.',
  },
  {
    id: '8-catalog2', file: 'CleanShot 2026-08-01 at 18.52.06@2x.png', accent: '#ff9f0a',
    head: 'Your life, notes, work\nand reading too.',
    sub: 'Calendars, journals, repos, newsletters — sixty-plus apps in the catalog, more added every week.',
  },
];

// Real window captures are 2036×1510 (ratio 1.3483). Frame width below keeps
// the full window inside the 1800-tall canvas with the headline block above.
const IMG_RATIO = 2036 / 1510;
const FRAME_W = 1660;                       // in 2880-space
const FRAME_H = Math.round(FRAME_W / IMG_RATIO); // ≈ 1231

const poster = (sc, b64) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#14110d;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:${px(7)} ${px(7)}, ${px(9)} ${px(9)};}
.mast{position:absolute;left:${px(110)};right:${px(110)};top:${px(62)};display:flex;justify-content:space-between;font-size:${px(26)};letter-spacing:.16em;font-weight:600;}
.rule{position:absolute;left:${px(110)};right:${px(110)};top:${px(110)};height:${px(3)};background:#14110d;}
.dot0{position:absolute;left:50%;margin-left:${px(-9)};top:${px(148)};width:${px(18)};height:${px(18)};border-radius:50%;background:${sc.accent};}
.head{position:absolute;left:${px(200)};right:${px(200)};top:${px(188)};font-size:${px(78)};line-height:1.0;font-weight:800;letter-spacing:-.04em;white-space:pre-line;text-align:center;}
.sub{position:absolute;left:${px(480)};right:${px(480)};top:${px(374)};font-size:${px(29)};line-height:1.4;color:#4a463c;font-weight:500;text-align:center;}
.frame{position:absolute;left:50%;transform:translateX(-50%);top:${px(490)};width:${px(FRAME_W)};height:${px(FRAME_H)};
  border-radius:${px(22)};overflow:hidden;background:#0b0910;
  box-shadow:0 ${px(46)} ${px(100)} rgba(20,17,13,.35), 0 ${px(8)} ${px(26)} rgba(20,17,13,.22), inset 0 0 0 ${px(1)} rgba(255,255,255,.09);}
.frame img{display:block;width:100%;height:100%;object-fit:cover;}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
<div class="rule"></div><div class="dot0"></div>
<div class="head">${sc.head}</div>
<div class="sub">${sc.sub}</div>
<div class="frame"><img src="data:image/png;base64,${b64}"></div>
</body></html>`;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  for (const sc of SHOTS) {
    const src = path.join(DL, sc.file);
    if (!fs.existsSync(src)) { console.error(`  MISSING ${sc.file}`); continue; }
    const b64 = fs.readFileSync(src).toString('base64');
    const file = path.join(__dirname, `_mac-real-${sc.id}.html`);
    fs.writeFileSync(file, poster(sc, b64));
    await page.goto('file://' + file);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(OUT, `${sc.id}.png`) });
    fs.unlinkSync(file);
    console.log(`  ok ${sc.id}.png  ${W}x${H}`);
  }
  await browser.close();
  console.log(`\ndone -> ${OUT}`);
})();
