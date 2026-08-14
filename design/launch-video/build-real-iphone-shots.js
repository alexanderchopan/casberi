// Composites REAL simulator screenshots (from ~/Downloads) into the
// editorial App Store frame — same visual language as build-appstore-shot.js,
// but batches all 8 in one pass instead of one CLI call per shot.
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');

const W = 1242, H = 2688;
const OUT = path.join(__dirname, 'appstore-real-6.5');
const DL = path.join(require('os').homedir(), 'Downloads');
const S = W / 1320;
const shotFrac = 0.8182;

const SHOTS = [
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.54.14.png', out: '0-catalog',
    head: 'Connect it once.\nIt keeps landing.', sub: '90+ apps you can connect — GitHub to Stripe to Dropbox — and more join regularly.', accent: '#2E63FF' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.52.32.png', out: '1-brief',
    head: 'Your day,\nalready gathered.', sub: 'One tap and the agent shows what moved, where it went, and what you keep circling.', accent: '#2E63FF' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.52.25.png', out: '2-wallet',
    head: 'Every wallet.\nWhere it moved.', sub: 'Holdings, protocols, and where money flowed — merged across every chain you watch.', accent: '#3fb950' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.53.39.png', out: '3-photos',
    head: 'What you screenshot,\nsorted for you.', sub: 'Screenshots cluster by what’s actually in them — no folders, no naming, done automatically.', accent: '#0a84ff' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.54.00.png', out: '4-social',
    head: 'Every account,\none feed.', sub: 'Bluesky, Farcaster, Instagram, Snapchat, TikTok, X — who you talk to most, across all of them.', accent: '#855dcd' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.52.53.png', out: '5-work',
    head: 'Work, in one place\nit already knows.', sub: 'GitHub, Linear, Notion, Slack — where your work actually sits, without opening any of them.', accent: '#2E63FF' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.53.32.png', out: '6-chats',
    head: 'Every conversation,\nfindable again.', sub: 'ChatGPT, Claude, Gemini — your chat history lands here, searchable alongside everything else.', accent: '#855dcd' },
  { file: 'Simulator Screenshot - iPhone 17 Pro - 2026-08-12 at 12.53.10.png', out: '7-posthog',
    head: 'Your product’s own\nnumbers, kept.', sub: 'Metrics you track land here too — trends, milestones, and the answer already open.', accent: '#3fb950' },
];

const padX = Math.round(96 * S);
const headSize = Math.round(104 * S);
const subSize = Math.round(40 * S);
const mastSize = Math.round(26 * S);
const shotTop = Math.round(560 * S);
const shotW = Math.round(W * shotFrac);
const radius = Math.round(56 * S);
const T = { bg: '#EEEAE1', ink: '#14110d', sub: '#4a463c', rule: '#14110d', grain: '.5', shadow: 'rgba(20,17,13,.30)' };

const html = (imgData, headline, sub, accent) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:${T.bg};
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:${T.grain};background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(96*S)}px;display:flex;justify-content:space-between;
  font-size:${mastSize}px;letter-spacing:.16em;color:${T.ink};font-weight:600;}
.rule{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(150*S)}px;height:${Math.max(2,Math.round(3*S))}px;background:${T.rule};}
.head{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(232*S)}px;
  font-size:${headSize}px;line-height:.95;font-weight:800;letter-spacing:-.045em;color:${T.ink};white-space:pre-line;}
.sub{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(452*S)}px;
  font-size:${subSize}px;line-height:1.35;color:${T.sub};font-weight:500;}
.shot{position:absolute;left:50%;transform:translateX(-50%);top:${shotTop}px;width:${shotW}px;
  border-radius:${radius}px;overflow:hidden;
  box-shadow:${Math.round(40*S)}px ${Math.round(46*S)}px 0 rgba(20,17,13,.13),
             0 ${Math.round(34*S)}px ${Math.round(80*S)}px ${T.shadow};}
.shot img{width:100%;display:block;}
.dot{position:absolute;left:${padX}px;top:${Math.round(196*S)}px;width:${Math.round(18*S)}px;height:${Math.round(18*S)}px;border-radius:50%;background:${accent};}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
<div class="rule"></div>
<div class="dot"></div>
<div class="head">${headline}</div>
<div class="sub">${sub}</div>
<div class="shot"><img src="${imgData}"></div>
</body></html>`;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  for (const sh of SHOTS) {
    let srcFile = sh.file;
    if (!fs.existsSync(path.join(DL, srcFile)) && sh.fallback) srcFile = sh.fallback;
    const rawPath = path.join(DL, srcFile);
    if (!fs.existsSync(rawPath)) { console.log(`  MISSING ${srcFile} — skipped ${sh.out}`); continue; }
    const imgData = 'data:image/png;base64,' + fs.readFileSync(rawPath).toString('base64');
    const file = path.join(__dirname, `_real-${sh.out}.html`);
    fs.writeFileSync(file, html(imgData, sh.head, sh.sub, sh.accent));
    await page.goto('file://' + file);
    await page.waitForTimeout(160);
    await page.screenshot({ path: path.join(OUT, `${sh.out}.png`) });
    fs.unlinkSync(file);
    console.log(`  ok ${sh.out}.png  ${W}x${H}  <- ${srcFile}`);
  }
  await browser.close();
  console.log(`\n-> ${OUT}`);
})();
