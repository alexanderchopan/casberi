// App Store screenshots — EDITORIAL house style, UI drawn from the app's own
// structure (no simulator captures). Renders posters at an exact App Store
// size and shoots them with headless Chromium in one pass.
//
//   node build-appstore-editorial.js [W] [H] [outDir]
//   defaults: 1242 2688  (6.5" iPhone — iPhone 11 Pro Max / XS Max class)
//   6.9" is 1320x2868; iPad 13" is 2064x2752.
//
// The UI mirrors the real app: the source-chip strip (Shell/SourceChips), the
// All feed's per-source row shapes (Screens/FeedScreen), the combined
// portfolio treemap (prd §155), the agent bar + day brief (prd §166), the
// catalog grid, and Settings → "What this app reaches" (prd §180). Brand
// colours are the real ones from website/styles.css .ai-<name>.
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');

const W = parseInt(process.argv[2] || '1242', 10);
const H = parseInt(process.argv[3] || '2688', 10);
const OUT = process.argv[4] || path.join(__dirname, 'appstore-6.5');
const S = W / 1242;

const BLUE = '#2E63FF', GREEN = '#3fb950', VIOLET = '#855dcd', RED = '#ff453a';
const px = n => Math.round(n * S) + 'px';

const APPS = [
  'conic-gradient(#ff453a,#ff9f0a,#ffd60a,#30d158,#64d2ff,#0a84ff,#bf5af2,#ff453a)',
  '#2962ef', '#855dcd', '#0085ff', '#1db954', '#24292f', '#ff4500', '#ff0000',
  '#d97757', '#5e6ad2', '#e44332', '#fc4c02', '#9146ff', '#f26522', '#4fae7b',
  '#1b2838', '#ff6719', '#e60023', '#2f80ed', '#7c3aed', '#0052ff', '#229ed9',
  '#2081e2', '#1e3a8a', '#006bff', '#008fff', '#0b0b0b', '#40c7c2',
];

const TREE = [
  { s: 'ETH',  v: '$48.2k', x: 0,    y: 0,  w: 55,   h: 100, c: '#4a63d8', f: 40 },
  { s: 'USDC', v: '$19.4k', x: 56.5, y: 0,  w: 43.5, h: 47,  c: '#2775ca', f: 32 },
  { s: 'SOL',  v: '$11.1k', x: 56.5, y: 49, w: 24,   h: 51,  c: '#14f195', f: 26 },
  { s: 'WBTC', v: '$7.8k',  x: 81.5, y: 49, w: 18.5, h: 30,  c: '#f7931a', f: 21 },
  { s: '+12',  v: '',       x: 81.5, y: 81, w: 18.5, h: 19,  c: 'rgba(255,255,255,.16)', f: 19 },
];

const REACH = [
  { s: 'Wallet',    v: '118 req', x: 0,    y: 0,  w: 62,   h: 100, c: '#2962ef', f: 34 },
  { s: 'Farcaster', v: '64 req',  x: 63,   y: 0,  w: 37,   h: 56,  c: '#855dcd', f: 26 },
  { s: 'Photos',    v: '54 req',  x: 63,   y: 57, w: 37,   h: 43,  c: '#0a84ff', f: 24 },
];

const statusBar = () => `
<div class="sbar">
  <span class="t">9:41</span>
  <span class="r">
    <svg width="${18*S}" height="${12*S}" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1" fill="#fff"/><rect x="5" y="5.5" width="3" height="6.5" rx="1" fill="#fff"/><rect x="10" y="3" width="3" height="9" rx="1" fill="#fff"/><rect x="15" y="0" width="3" height="12" rx="1" fill="#fff"/></svg>
    <svg width="${16*S}" height="${12*S}" viewBox="0 0 16 12"><path d="M8 10.5 5.2 7.7a4 4 0 0 1 5.6 0z" fill="#fff"/><path d="M3 5.5a7 7 0 0 1 10 0" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/><path d="M.8 2.8a10.5 10.5 0 0 1 14.4 0" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/></svg>
    <svg width="${25*S}" height="${12*S}" viewBox="0 0 25 12"><rect x="0.5" y="0.5" width="21" height="11" rx="3.2" stroke="rgba(255,255,255,.5)" fill="none"/><rect x="2" y="2" width="18" height="8" rx="2" fill="#3fb950"/><path d="M23 4v4a2.2 2.2 0 0 0 0-4z" fill="rgba(255,255,255,.5)"/></svg>
  </span>
</div>`;

const chipStrip = (active) => {
  const chips = [
    { n: 'avatar' }, { n: 'grid' },
    { n: 'All', c: 'rgba(255,255,255,.5)' },
    { n: 'Wallet', c: '#2962ef' },
    { n: 'Photos', c: '#0a84ff' },
    { n: 'Calendar', c: RED },
    { n: 'Farcaster', c: VIOLET },
  ];
  return `<div class="chips">${chips.map(c => {
    if (c.n === 'avatar') return `<span class="cc av"><svg width="${26*S}" height="${26*S}" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="#14110d"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="#14110d"/></svg></span>`;
    if (c.n === 'grid') return `<span class="cc gr"><svg width="${24*S}" height="${24*S}" viewBox="0 0 24 24" fill="rgba(255,255,255,.75)"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg></span>`;
    const on = c.n === active;
    return `<span class="cc ${on ? 'on' : ''}" style="${on ? `background:${c.c};box-shadow:0 0 0 ${3*S}px rgba(255,255,255,.16)` : ''}">${
      c.n === 'All' ? `<b style="font-size:${px(23)};color:${on ? '#fff' : 'rgba(255,255,255,.72)'}">All</b>`
                    : `<i style="background:${on ? '#fff' : c.c}"></i>`}</span>`;
  }).join('')}</div>`;
};

const agentBar = (text) => `
<div class="abar"><span>${text || 'Ask your things…'}</span>
  <span class="mic"><svg width="${26*S}" height="${26*S}" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="${BLUE}"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" stroke="${BLUE}" stroke-width="2" fill="none" stroke-linecap="round"/></svg></span>
</div>`;

const STEP = (glyph, hue, title, line) => `
  <div class="step">
    <span class="sglyph" style="background:${hue}"><svg width="${24*S}" height="${24*S}" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${glyph}</svg></span>
    <div class="col"><div class="ttl">${title}</div><div class="sub2" style="white-space:normal">${line}</div></div>
  </div>`;

const GLYPH_GRID = '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>';
const GLYPH_FILTER = '<circle cx="12" cy="12" r="9"/><path d="M9 12h6M10.5 15h3"/>';
const GLYPH_SPARK = '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M18 6l-2.5 2.5M8.5 15.5 6 18"/>';

const SCREENS = [
  {
    id: '0-onboarding', accent: BLUE, pour: 'rgba(46,99,255,.30)',
    head: 'How it works.\nNothing to set up.',
    sub: 'Everything you care about, from every app, in one place that’s yours.',
    body: `
      <div class="onb">
        ${STEP(GLYPH_GRID, '#2962ef', 'Connect your apps', 'Everything you connect lands here on its own — the catalog is top left.')}
        ${STEP(GLYPH_FILTER, '#ff2d92', 'One feed, or one app', 'Narrow it to one app with the chips up top.')}
        ${STEP(GLYPH_SPARK, '#855dcd', 'Ask anything', 'Ask the bar at the bottom about anything you’ve saved.')}
        <div class="onbcta">Try the demo</div>
        <div class="onbsecondary">Start with my own things</div>
      </div>`,
  },
  {
    id: '1-feed', accent: BLUE, pour: 'rgba(46,99,255,.30)',
    head: 'Everything you keep,\nin one feed.',
    sub: 'Wallets, posts, photos, events, notes — every app you connect lands here, automatically.',
    body: `${chipStrip('All')}
      <div class="sect">Today <em>12</em></div>
      <div class="row"><span class="av"></span><div class="col"><div class="bar" style="width:76%"></div><div class="bar s" style="width:50%"></div></div><span class="src">Farcaster</span></div>
      <div class="row"><span class="dot" style="background:#2962ef"></span><div class="col"><div class="amt" style="color:${GREEN}">+0.42 ETH</div><div class="sub2">$1,284.00 · Base</div></div><span class="src">Wallet</span></div>
      <div class="row"><span class="thumb"></span><div class="col"><div class="ttl">Screenshot · 2:14pm</div><div class="bar s" style="width:42%"></div></div><span class="src">Photos</span></div>
      <div class="sect">Yesterday <em>9</em></div>
      <div class="row"><span class="time">4:30</span><span class="vbar" style="background:${RED}"></span><div class="col"><div class="ttl">Design review</div><div class="bar s" style="width:36%"></div></div><span class="src">Calendar</span></div>
      <div class="row"><span class="av" style="background:rgba(255,255,255,.1)"></span><div class="col"><div class="bar" style="width:64%"></div><div class="bar s" style="width:44%"></div></div><span class="src">Bluesky</span></div>
      <div class="row"><span class="dot" style="background:#1db954"></span><div class="col"><div class="ttl">Saved 3 songs</div><div class="bar s" style="width:30%"></div></div><span class="src">Spotify</span></div>
      ${agentBar()}`,
  },
  {
    id: '2-source', accent: '#0a84ff', pour: 'rgba(10,132,255,.32)',
    head: 'Tap a chip —\nthe feed reshapes.',
    sub: 'Photos become a grid. Money becomes amounts. A day lays itself out. Each source, its own shape.',
    body: `${chipStrip('Photos')}
      <div class="sect">Photos <em>240</em></div>
      <div class="pgrid">${Array.from({length:9}).map((_,i)=>`<span class="pc" style="background:linear-gradient(${140+i*17}deg,#3b4d70,#1e2a42)"></span>`).join('')}</div>
      <div class="sect" style="margin-top:${px(34)}">Read on this iPhone</div>
      <div class="row"><span class="thumb"></span><div class="col"><div class="ttl">"Ship the wallet merge"</div><div class="sub2">Text read on-device · 2 days ago</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '3-wallet', accent: GREEN, pour: 'rgba(63,185,80,.26)',
    head: 'Every wallet.\nOne picture.',
    sub: 'Holdings merged across Ethereum, Base, Arbitrum, Solana and more. Read-only — watching can never move funds.',
    body: `${chipStrip('Wallet')}
      <div class="wtot">Across your wallets</div>
      <div class="wrow"><span class="wn">$86,512</span><span class="wpill">▲ 2.4%</span></div>
      <div class="wsub">Mostly ETH · +$1,284 today</div>
      <div class="spark"><svg width="100%" height="${100*S}" viewBox="0 0 640 100" preserveAspectRatio="none"><path d="M0 78 L80 70 L160 74 L240 52 L320 58 L400 34 L480 40 L560 20 L640 12" fill="none" stroke="${GREEN}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="tree">${TREE.map(c=>`<span class="tc" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${c.c}"><b style="font-size:${px(c.f)}">${c.s}</b>${c.v?`<i style="font-size:${px(c.f*0.6)}">${c.v}</i>`:''}</span>`).join('')}</div>
      <div class="row" style="margin-top:${px(26)}"><span class="warn">!</span><div class="col"><div class="ttl">Worth a look</div><div class="sub2">3 open approvals · review and revoke</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '4-ask', accent: BLUE, pour: 'rgba(46,99,255,.30)',
    head: 'Ask in plain words.\nAnswered from your things.',
    sub: 'Written on your iPhone by Apple\'s on-device model, grounded in what you actually saved — never invented.',
    body: `${chipStrip('All')}
      <div class="askq">What's going on?</div>
      <div class="acard">
        <div class="ah">Quiet morning — <b>14 new things</b> landed, and your wallets are up 2.4%.</div>
        <div class="arow"><span class="ai" style="background:#2962ef"></span><span>ETH did the lifting · +$1,284</span></div>
        <div class="arow"><span class="ai" style="background:${RED}"></span><span>Design review at 4:30</span></div>
        <div class="arow"><span class="ai" style="background:${VIOLET}"></span><span>6 casts from people you follow</span></div>
        <div class="spark" style="margin-top:${px(22)}"><svg width="100%" height="${86*S}" viewBox="0 0 640 86" preserveAspectRatio="none"><path d="M0 66 L80 58 L160 62 L240 44 L320 48 L400 30 L480 34 L560 18 L640 12" fill="none" stroke="${GREEN}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="abadge">Written on this iPhone, from your own things</div>
      </div>
      ${agentBar('What\'s going on?')}`,
  },
  {
    id: '5-catalog', accent: BLUE, pour: 'rgba(46,99,255,.30)',
    head: 'Connect it once.\nIt keeps landing.',
    sub: 'Photos, Calendar, Health, GitHub, Spotify, Farcaster, Bluesky, wallets — and more join regularly.',
    body: `${chipStrip('All')}
      <div class="sect">The catalog <em>90+</em></div>
      <div class="agrid">${APPS.slice(0,28).map(c=>`<span class="at" style="background:${c}"></span>`).join('')}</div>
      <div class="row" style="margin-top:${px(30)}"><span class="dot" style="background:${GREEN}"></span><div class="col"><div class="ttl">No account. No sign-up.</div><div class="sub2">Public sources need nothing at all</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '6-privacy', accent: BLUE, pour: 'rgba(46,99,255,.26)',
    head: 'No account. No server.\nNothing tracked.',
    sub: 'Your things live on your iPhone. Settings lists every service the app reaches — and why.',
    body: `${chipStrip('All')}
      <div class="ptitle">What this app reaches</div>
      <div class="pnote">Casberi has no server. Every request goes straight from this iPhone to the service named.</div>
      <div class="sect">Reaching now</div>
      <div class="row"><span class="pic" style="background:#2962ef"></span><div class="col"><div class="ttl">Wallet</div><div class="sub2">Balances of the wallets you watch</div><div class="host">api.g.alchemy.com</div></div></div>
      <div class="row"><span class="pic" style="background:${VIOLET}"></span><div class="col"><div class="ttl">Farcaster</div><div class="sub2">Public casts you follow</div><div class="host">api.farcaster.xyz</div></div></div>
      <div class="sect">Only when you tap</div>
      <div class="row"><span class="pic" style="background:rgba(255,255,255,.16)"></span><div class="col"><div class="ttl">Your agent key</div><div class="sub2">Only on "Try with your key" — never otherwise</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '7-reach', accent: GREEN, pour: 'rgba(63,185,80,.26)',
    head: 'See exactly\nwhere it reaches.',
    sub: 'Not a promise — a live receipt. Every host this iPhone actually talked to, and when.',
    body: `${chipStrip('All')}
      <div class="ptitle">What it actually reached</div>
      <div class="reachtop"><span class="reachn">312</span><span class="reachlabel">requests</span><span class="reachpill">All declared</span></div>
      <div class="tree">${REACH.map(c=>`<span class="tc" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${c.c}"><b style="font-size:${px(c.f)}">${c.s}</b><i style="font-size:${px(c.f*0.55)}">${c.v}</i></span>`).join('')}</div>
      <div class="sect" style="margin-top:${px(30)}">Reached</div>
      <div class="row"><span class="pic" style="background:#2962ef"></span><div class="col"><div class="ttl">Wallet</div><div class="host">api.g.alchemy.com · 118 requests</div></div></div>
      <div class="row"><span class="pic" style="background:${VIOLET}"></span><div class="col"><div class="ttl">Farcaster</div><div class="host">api.farcaster.xyz · 64 requests</div></div></div>
      ${agentBar()}`,
  },
];

const poster = (sc) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#14110d;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:${px(7)} ${px(7)}, ${px(9)} ${px(9)};}
.mast{position:absolute;left:${px(78)};right:${px(78)};top:${px(86)};display:flex;justify-content:space-between;font-size:${px(25)};letter-spacing:.16em;font-weight:600;}
.rule{position:absolute;left:${px(78)};right:${px(78)};top:${px(140)};height:${px(3)};background:#14110d;}
.dot0{position:absolute;left:${px(78)};top:${px(184)};width:${px(17)};height:${px(17)};border-radius:50%;background:${sc.accent};}
.head{position:absolute;left:${px(78)};right:${px(70)};top:${px(226)};font-size:${px(90)};line-height:.97;font-weight:800;letter-spacing:-.045em;white-space:pre-line;}
.sub{position:absolute;left:${px(78)};right:${px(96)};top:${px(452)};font-size:${px(33)};line-height:1.36;color:#4a463c;font-weight:500;}
.scr{position:absolute;left:50%;transform:translateX(-50%);top:${px(660)};width:${px(1040)};height:${px(1900)};
  border-radius:${px(62)};overflow:hidden;background:#0b0910;
  box-shadow:${px(34)} ${px(42)} 0 rgba(20,17,13,.12), 0 ${px(34)} ${px(80)} rgba(20,17,13,.34), inset 0 0 0 ${px(2)} rgba(255,255,255,.07);}
.pour{position:absolute;left:0;right:0;top:0;height:${px(420)};background:linear-gradient(to bottom, ${sc.pour} 0%, rgba(0,0,0,0) 100%);}
.inner{position:absolute;inset:0;padding:${px(20)} ${px(34)} 0;color:#fff;}
.sbar{display:flex;align-items:center;justify-content:space-between;padding:${px(14)} ${px(12)} ${px(18)};}
.sbar .t{font-size:${px(26)};font-weight:700;}
.sbar .r{display:flex;align-items:center;gap:${px(8)};}
.chips{display:flex;align-items:center;gap:${px(14)};margin-bottom:${px(26)};}
.cc{width:${px(74)};height:${px(74)};border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;}
.cc.av{background:#fff;} .cc i{width:${px(26)};height:${px(26)};border-radius:50%;display:block;}
.sect{font-size:${px(24)};font-weight:700;color:rgba(255,255,255,.42);margin:${px(24)} 0 ${px(10)};letter-spacing:.02em;}
.sect em{font-style:normal;color:rgba(255,255,255,.28);margin-left:${px(8)};}
.row{display:flex;align-items:center;gap:${px(18)};padding:${px(17)} 0;}
.row .col{flex:1;min-width:0;}
.av{width:${px(60)};height:${px(60)};border-radius:50%;background:rgba(255,255,255,.16);flex:none;}
.thumb{width:${px(60)};height:${px(60)};border-radius:${px(15)};background:linear-gradient(140deg,#3b4d70,#1e2a42);flex:none;}
.dot{width:${px(14)};height:${px(14)};border-radius:50%;flex:none;margin:0 ${px(23)};}
.pic{width:${px(58)};height:${px(58)};border-radius:${px(16)};flex:none;}
.warn{width:${px(52)};height:${px(52)};border-radius:50%;background:rgba(255,159,10,.2);color:#ff9f0a;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:${px(28)};flex:none;margin:0 ${px(4)};}
.bar{height:${px(14)};border-radius:${px(8)};background:rgba(255,255,255,.24);}
.bar.s{height:${px(11)};background:rgba(255,255,255,.12);margin-top:${px(9)};}
.ttl{font-size:${px(26)};font-weight:650;}
.sub2{font-size:${px(21)};color:rgba(255,255,255,.44);margin-top:${px(4)};}
.host{font-size:${px(19)};color:rgba(255,255,255,.3);margin-top:${px(3)};font-family:ui-monospace,monospace;}
.amt{font-size:${px(29)};font-weight:750;}
.time{font-size:${px(23)};font-weight:700;color:rgba(255,255,255,.55);width:${px(66)};flex:none;}
.vbar{width:${px(6)};height:${px(44)};border-radius:${px(4)};flex:none;}
.src{margin-left:auto;font-size:${px(19)};color:rgba(255,255,255,.32);font-weight:600;flex:none;}
.pgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:${px(12)};}
.pc{aspect-ratio:1;border-radius:${px(16)};display:block;}
.agrid{display:grid;grid-template-columns:repeat(7,1fr);gap:${px(16)};}
.at{aspect-ratio:1;border-radius:${px(20)};display:block;box-shadow:0 ${px(6)} ${px(14)} rgba(0,0,0,.35);}
.wtot{font-size:${px(23)};color:rgba(255,255,255,.45);margin-top:${px(8)};font-weight:600;}
.wrow{display:flex;align-items:baseline;gap:${px(18)};margin-top:${px(6)};}
.wn{font-size:${px(62)};font-weight:800;letter-spacing:-.025em;}
.wpill{font-size:${px(23)};font-weight:750;padding:${px(8)} ${px(18)};border-radius:100px;background:rgba(63,185,80,.18);color:${GREEN};}
.wsub{font-size:${px(22)};color:rgba(255,255,255,.42);margin-top:${px(6)};}
.spark{margin:${px(14)} 0 ${px(20)};}
.tree{position:relative;height:${px(420)};border-radius:${px(22)};overflow:hidden;}
.tc{position:absolute;border-radius:${px(16)};display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 0 0 0 ${px(2)} rgba(0,0,0,.2);}
.tc b{font-weight:800;color:#fff;} .tc i{font-style:normal;color:rgba(255,255,255,.82);margin-top:${px(5)};font-weight:600;}
.askq{font-size:${px(30)};font-weight:700;background:rgba(255,255,255,.09);border-radius:100px;padding:${px(20)} ${px(28)};box-shadow:inset 0 0 0 ${px(2)} rgba(255,255,255,.1);}
.acard{margin-top:${px(24)};background:rgba(255,255,255,.05);border-radius:${px(26)};padding:${px(30)};}
.ah{font-size:${px(31)};font-weight:700;line-height:1.32;}
.arow{display:flex;align-items:center;gap:${px(16)};margin-top:${px(20)};font-size:${px(23)};color:rgba(255,255,255,.74);font-weight:600;}
.ai{width:${px(46)};height:${px(46)};border-radius:${px(14)};flex:none;}
.abadge{margin-top:${px(20)};font-size:${px(20)};color:rgba(255,255,255,.4);font-weight:600;}
.ptitle{font-size:${px(38)};font-weight:800;letter-spacing:-.02em;margin-top:${px(6)};}
.pnote{font-size:${px(22)};color:rgba(255,255,255,.5);line-height:1.45;margin-top:${px(10)};}
.abar{position:absolute;left:${px(34)};right:${px(34)};bottom:${px(38)};display:flex;align-items:center;justify-content:space-between;
  background:rgba(255,255,255,.11);border-radius:100px;padding:${px(22)} ${px(28)};
  box-shadow:inset 0 0 0 ${px(2)} rgba(255,255,255,.12), 0 ${px(10)} ${px(30)} rgba(0,0,0,.4);
  font-size:${px(26)};font-weight:600;color:rgba(255,255,255,.6);}
.onb{padding-top:${px(30)};}
.step{display:flex;align-items:flex-start;gap:${px(20)};margin-bottom:${px(30)};}
.sglyph{width:${px(56)};height:${px(56)};border-radius:${px(16)};display:flex;align-items:center;justify-content:center;flex:none;}
.onbcta{margin-top:${px(50)};background:${BLUE};color:#fff;text-align:center;font-size:${px(27)};font-weight:700;
  border-radius:100px;padding:${px(22)} 0;box-shadow:0 ${px(10)} ${px(30)} rgba(46,99,255,.4);}
.onbsecondary{margin-top:${px(18)};text-align:center;font-size:${px(23)};font-weight:600;color:rgba(255,255,255,.55);}
.reachtop{display:flex;align-items:baseline;gap:${px(14)};margin-top:${px(16)};}
.reachn{font-size:${px(56)};font-weight:800;letter-spacing:-.02em;}
.reachlabel{font-size:${px(23)};color:rgba(255,255,255,.42);font-weight:600;}
.reachpill{margin-left:auto;font-size:${px(21)};font-weight:750;padding:${px(9)} ${px(20)};border-radius:100px;
  background:rgba(63,185,80,.18);color:${GREEN};align-self:center;}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
<div class="rule"></div><div class="dot0"></div>
<div class="head">${sc.head}</div>
<div class="sub">${sc.sub}</div>
<div class="scr"><div class="pour"></div><div class="inner">${statusBar()}${sc.body}</div></div>
</body></html>`;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  for (const sc of SCREENS) {
    const file = path.join(__dirname, `_appstore-${sc.id}.html`);
    fs.writeFileSync(file, poster(sc));
    await page.goto('file://' + file);
    await page.waitForTimeout(160);
    await page.screenshot({ path: path.join(OUT, `${sc.id}.png`) });
    fs.unlinkSync(file);
    console.log(`  ok ${sc.id}.png  ${W}x${H}`);
  }
  await browser.close();
  console.log(`\n${SCREENS.length} shots -> ${OUT}`);
})();
