// Mac App Store screenshots — the SAME eight screens the iPhone set shows,
// in the editorial frame (2026-08-14).
//
// The captures come from scripts/mac-appstore-capture.sh, which drives the
// real Mac Catalyst app and has it render its own key window (`-macSnapshot`).
// Not CleanShot by hand, which is what build-mac-appstore-real.js consumed —
// that script stays as the record of the previous set.
//
//   node build-mac-appstore-current.js [W] [H] [outDir]
//   default: 2880x1800 (largest accepted Mac size; 1280x800 / 1440x900 /
//   2560x1600 are the same 16:10 ratio, so this master downscales cleanly).
//
// Headlines are the iPhone set's, so the two stores tell one story. Each is
// grounded in what its capture actually shows — no invented UI.
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');

const W = parseInt(process.argv[2] || '2880', 10);
const H = parseInt(process.argv[3] || '1800', 10);
const OUT = process.argv[4] || path.join(__dirname, 'appstore-mac-current');
const SRC = path.join(__dirname, 'mac-shots-raw');
const S = W / 2880;
const px = n => Math.round(n * S) + 'px';

const SHOTS = [
  { id: '0-catalog', accent: '#2E63FF',
    head: 'Connect it once.\nIt keeps landing.',
    sub: '90+ apps you can connect — GitHub to Stripe to Dropbox — and more join regularly.' },
  { id: '1-brief', accent: '#2E63FF',
    head: 'Your day,\nalready gathered.',
    sub: 'One tap and the agent shows what moved, where it went, and what you keep circling.' },
  { id: '2-wallet', accent: '#3fb950',
    head: 'Every wallet.\nWhere it moved.',
    sub: 'Holdings, protocols, and where money flowed — merged across every chain you watch.' },
  { id: '3-photos', accent: '#0a84ff',
    head: 'What you screenshot,\nsorted for you.',
    sub: 'Screenshots cluster by what’s actually in them — no folders, no naming, done automatically.' },
  { id: '4-social', accent: '#855dcd',
    head: 'Every account,\none feed.',
    sub: 'Bluesky, Farcaster, Instagram, Snapchat, TikTok, X — who you talk to most, across all of them.' },
  { id: '5-work', accent: '#2E63FF',
    head: 'Work, in one place\nit already knows.',
    sub: 'GitHub, Linear, Notion, Slack — where your work actually sits, without opening any of them.' },
  { id: '6-chats', accent: '#855dcd',
    head: 'Every conversation,\nfindable again.',
    sub: 'ChatGPT, Claude, Gemini — your chat history lands here, searchable alongside everything else.' },
  { id: '7-posthog', accent: '#3fb950',
    head: 'Your product’s own\nnumbers, kept.',
    sub: 'Metrics you track land here too — trends, milestones, and the answer already open.' },
];

// The window renders itself at 2048×1536 (4:3), not the 2036×1510 CleanShot
// produced, so the frame is sized off the real ratio — `object-fit: cover` on
// a frame built for the wrong one silently crops the window's own edges.
const IMG_RATIO = 2048 / 1536;
const FRAME_W = 1660;                             // in 2880-space
const FRAME_H = Math.round(FRAME_W / IMG_RATIO);  // ≈ 1245

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
.sub{position:absolute;left:${px(430)};right:${px(430)};top:${px(374)};font-size:${px(29)};line-height:1.4;color:#4a463c;font-weight:500;text-align:center;}
.frame{position:absolute;left:50%;transform:translateX(-50%);top:${px(478)};width:${px(FRAME_W)};height:${px(FRAME_H)};
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
    const src = path.join(SRC, `${sc.id}.png`);
    if (!fs.existsSync(src)) { console.error(`  MISSING ${sc.id}.png — run scripts/mac-appstore-capture.sh`); continue; }
    const b64 = fs.readFileSync(src).toString('base64');
    const file = path.join(__dirname, `_mac-cur-${sc.id}.html`);
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
