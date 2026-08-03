// Mac App Store screenshots — EDITORIAL house style, same treatment as
// build-appstore-editorial.js (iOS) but for the Mac Catalyst window: UI drawn
// from the app's own structure (no simulator captures), shot at an exact Mac
// App Store canvas size with headless Chromium in one pass.
//
//   node build-mac-appstore-editorial.js [W] [H] [outDir]
//   default: 2880x1800 (Apple's largest accepted Mac screenshot size, 16:10)
//   other accepted sizes: 1280x800, 1440x900, 2560x1600
//
// The window chrome mirrors the real app (CasberiApp.swift): a native
// title-bar whose text is the current source filter — nil reverts to
// "Casberi" (RootShell.swift, macCatalyst-only) — traffic lights, no
// sidebar (the chip strip owns the top of the content, same as iPhone/iPad,
// just windowed and wider — RootShell's Mac-window-sizing comment: "no
// sidebar", `showsRail` just keeps the horizontal chip strip from ever
// collapsing). Brand colours are the real ones from website/styles.css
// .ai-<name>.
const fs = require('fs'), path = require('path');
const { chromium } = require('/opt/homebrew/lib/node_modules/playwright');

const W = parseInt(process.argv[2] || '2880', 10);
const H = parseInt(process.argv[3] || '1800', 10);
const OUT = process.argv[4] || path.join(__dirname, 'appstore-mac-2880x1800');
const S = W / 2880;

const BLUE = '#2E63FF', GREEN = '#3fb950', VIOLET = '#855dcd', RED = '#ff453a', PINK = '#ff007a';
const px = n => Math.round(n * S) + 'px';

const APPS = [
  'conic-gradient(#ff453a,#ff9f0a,#ffd60a,#30d158,#64d2ff,#0a84ff,#bf5af2,#ff453a)',
  '#2962ef', '#855dcd', '#0085ff', '#1db954', '#24292f', '#ff4500', '#ff0000',
  '#d97757', '#5e6ad2', '#e44332', '#fc4c02', '#9146ff', '#f26522', '#4fae7b',
  '#1b2838', '#ff6719', '#e60023', '#2f80ed', '#7c3aed', '#0052ff', '#229ed9',
  '#2081e2', '#1e3a8a', '#006bff', '#008fff', '#0b0b0b', '#40c7c2',
  '#4830c0', '#0434ff', '#ff007a', '#000000', '#9391f7', '#2a73ff', '#12ff80',
];

const TREE = [
  { s: 'ETH',  v: '$48.2k', x: 0,    y: 0,  w: 46,   h: 100, c: '#4a63d8', f: 30 },
  { s: 'USDC', v: '$19.4k', x: 47.5, y: 0,  w: 34.5, h: 47,  c: '#2775ca', f: 24 },
  { s: 'SOL',  v: '$11.1k', x: 47.5, y: 49, w: 19,   h: 51,  c: '#14f195', f: 20 },
  { s: 'WBTC', v: '$7.8k',  x: 68,   y: 0,  w: 30,   h: 47,  c: '#f7931a', f: 22 },
  { s: 'AERO', v: '$4.1k',  x: 68,   y: 49, w: 14,   h: 51,  c: '#0434ff', f: 16 },
  { s: '+18',  v: '',       x: 84,   y: 49, w: 16,   h: 51,  c: 'rgba(255,255,255,.16)', f: 16 },
];

const chipStrip = (active, extra) => {
  const chips = [
    { n: 'avatar' }, { n: 'grid' },
    { n: 'All', c: 'rgba(255,255,255,.5)' },
    { n: 'Wallet', c: '#2962ef' },
    { n: 'Photos', c: '#0a84ff' },
    { n: 'Calendar', c: RED },
    { n: 'Farcaster', c: VIOLET },
    { n: 'GitHub', c: '#24292f' },
    { n: 'Tokens', c: '#0085ff' },
    ...(extra || []),
  ];
  return `<div class="chips">${chips.map(c => {
    if (c.n === 'avatar') return `<span class="cc av"><svg width="${30*S}" height="${30*S}" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="#14110d"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="#14110d"/></svg></span>`;
    if (c.n === 'grid') return `<span class="cc gr"><svg width="${28*S}" height="${28*S}" viewBox="0 0 24 24" fill="rgba(255,255,255,.75)"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg></span>`;
    const on = c.n === active;
    return `<span class="cc ${on ? 'on' : ''}" style="${on ? `background:${c.c};box-shadow:0 0 0 ${3*S}px rgba(255,255,255,.16)` : ''}">${
      c.n === 'All' ? `<b style="font-size:${px(25)};color:${on ? '#fff' : 'rgba(255,255,255,.72)'}">All</b>`
                    : `<i style="background:${on ? '#fff' : c.c}"></i>`}</span>`;
  }).join('')}</div>`;
};

const agentBar = (text) => `
<div class="abar"><span>${text || 'Ask your things…'}</span>
  <span class="mic"><svg width="${28*S}" height="${28*S}" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="${BLUE}"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" stroke="${BLUE}" stroke-width="2" fill="none" stroke-linecap="round"/></svg></span>
</div>`;

const SCREENS = [
  {
    id: '1-feed', mac: null, accent: BLUE, pour: 'rgba(46,99,255,.28)',
    head: 'Everything you keep,\nnow on your desktop.',
    sub: 'Wallets, posts, photos, events, notes — every app you connect lands in one feed, right on your Mac.',
    body: `${chipStrip('All')}
      <div class="sect">Today <em>16</em></div>
      <div class="row"><span class="av"></span><div class="col"><div class="bar" style="width:70%"></div><div class="bar s" style="width:44%"></div></div><span class="src">Farcaster</span></div>
      <div class="row"><span class="dot" style="background:#2962ef"></span><div class="col"><div class="amt" style="color:${GREEN}">+0.42 ETH</div><div class="sub2">$1,284.00 · Base</div></div><span class="src">Wallet</span></div>
      <div class="row"><span class="thumb"></span><div class="col"><div class="ttl">Screenshot · 2:14pm</div><div class="bar s" style="width:38%"></div></div><span class="src">Photos</span></div>
      <div class="row"><span class="dot" style="background:#24292f"></span><div class="col"><div class="ttl">Merged #412 — Mac window sizing</div><div class="sub2">casberi/casberi</div></div><span class="src">GitHub</span></div>
      <div class="sect">Yesterday <em>11</em></div>
      <div class="row"><span class="time">4:30</span><span class="vbar" style="background:${RED}"></span><div class="col"><div class="ttl">Design review</div><div class="bar s" style="width:32%"></div></div><span class="src">Calendar</span></div>
      <div class="row"><span class="av" style="background:rgba(255,255,255,.1)"></span><div class="col"><div class="bar" style="width:58%"></div><div class="bar s" style="width:40%"></div></div><span class="src">Bluesky</span></div>
      ${agentBar()}`,
  },
  {
    id: '2-wallet', mac: 'Wallet', accent: GREEN, pour: 'rgba(63,185,80,.24)',
    head: 'Every wallet.\nA bigger picture.',
    sub: 'Holdings merged across Ethereum, Base, Arbitrum, Solana and more — read-only, on a screen with room for all of it.',
    body: `${chipStrip('Wallet')}
      <div class="wtot">Across your wallets</div>
      <div class="wrow"><span class="wn">$96,812</span><span class="wpill">▲ 2.1%</span></div>
      <div class="wsub">Mostly ETH · +$1,412 today</div>
      <div class="spark"><svg width="100%" height="${86*S}" viewBox="0 0 900 86" preserveAspectRatio="none"><path d="M0 66 L110 58 L220 62 L330 40 L440 46 L550 26 L660 32 L770 14 L900 8" fill="none" stroke="${GREEN}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
      <div class="tree">${TREE.map(c=>`<span class="tc" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${c.c}"><b style="font-size:${px(c.f)}">${c.s}</b>${c.v?`<i style="font-size:${px(c.f*0.62)}">${c.v}</i>`:''}</span>`).join('')}</div>
      <div class="row" style="margin-top:${px(22)}"><span class="warn">!</span><div class="col"><div class="ttl">Worth a look</div><div class="sub2">3 open approvals · review and revoke</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '3-ask', mac: null, accent: BLUE, pour: 'rgba(46,99,255,.28)',
    head: 'Ask in plain words.\nAnswered from your things.',
    sub: 'Written on this Mac by Apple’s on-device model, grounded in what you actually saved — never invented.',
    body: `${chipStrip('All')}
      <div class="askq">What’s going on?</div>
      <div class="acard">
        <div class="ah">Quiet morning — <b>16 new things</b> landed, and your wallets are up 2.1%.</div>
        <div class="arow"><span class="ai" style="background:#2962ef"></span><span>ETH did the lifting · +$1,412</span></div>
        <div class="arow"><span class="ai" style="background:${RED}"></span><span>Design review at 4:30</span></div>
        <div class="arow"><span class="ai" style="background:${VIOLET}"></span><span>7 casts from people you follow</span></div>
        <div class="arow"><span class="ai" style="background:#24292f"></span><span>PR #412 merged on casberi/casberi</span></div>
        <div class="spark" style="margin-top:${px(18)}"><svg width="100%" height="${74*S}" viewBox="0 0 900 74" preserveAspectRatio="none"><path d="M0 58 L110 50 L220 54 L330 34 L440 38 L550 22 L660 26 L770 12 L900 8" fill="none" stroke="${GREEN}" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="abadge">Written on this Mac, from your own things</div>
      </div>
      ${agentBar('What’s going on?')}`,
  },
  {
    id: '4-catalog', mac: null, accent: BLUE, pour: 'rgba(46,99,255,.28)',
    head: 'Connect it once.\nIt keeps landing.',
    sub: 'Photos, Calendar, GitHub, Farcaster, wallets, DeFi protocols and more — one catalog, now with room for the whole grid.',
    body: `${chipStrip('All')}
      <div class="sect">The catalog <em>52</em></div>
      <div class="agrid">${APPS.map(c=>`<span class="at" style="background:${c}"></span>`).join('')}</div>
      <div class="row" style="margin-top:${px(24)}"><span class="dot" style="background:${GREEN}"></span><div class="col"><div class="ttl">No account. No sign-up.</div><div class="sub2">Public sources need nothing at all</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '5-privacy', mac: 'Settings', accent: BLUE, pour: 'rgba(46,99,255,.24)',
    head: 'No account. No server.\nNothing tracked.',
    sub: 'Your things live on this Mac. Settings lists every service the app reaches — and why.',
    body: `${chipStrip('All')}
      <div class="ptitle">What this app reaches</div>
      <div class="pnote">Casberi has no server. Every request goes straight from this Mac to the service named.</div>
      <div class="sect">Reaching now</div>
      <div class="row"><span class="pic" style="background:#2962ef"></span><div class="col"><div class="ttl">Wallet</div><div class="sub2">Balances of the wallets you watch</div><div class="host">api.g.alchemy.com</div></div></div>
      <div class="row"><span class="pic" style="background:${VIOLET}"></span><div class="col"><div class="ttl">Farcaster</div><div class="sub2">Public casts you follow</div><div class="host">api.farcaster.xyz</div></div></div>
      <div class="row"><span class="pic" style="background:#24292f"></span><div class="col"><div class="ttl">GitHub</div><div class="sub2">Repos and PRs you connect</div><div class="host">api.github.com</div></div></div>
      <div class="sect">Only when you tap</div>
      <div class="row"><span class="pic" style="background:rgba(255,255,255,.16)"></span><div class="col"><div class="ttl">Your agent key</div><div class="sub2">Only on "Try with your key" — never otherwise</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '6-today', mac: null, accent: BLUE, pour: 'rgba(46,99,255,.28)',
    head: 'One glance,\nyour whole day.',
    sub: 'A morning brief composed on-device from what actually happened — wallets, casts, calendar, work.',
    body: `${chipStrip('All')}
      <div class="askq" style="background:rgba(255,255,255,.06)">Your Wednesday · 16 new, wallet +2.1%</div>
      <div class="acard">
        <div class="ah">The week’s theme so far: <b>Onchain</b> and <b>Work</b> — seven days of ETH doing the lifting.</div>
        <div class="arow"><span class="ai" style="background:#2962ef"></span><span>Wallet up $1,412 today · mostly ETH</span></div>
        <div class="arow"><span class="ai" style="background:#24292f"></span><span>3 PRs merged this week on casberi/casberi</span></div>
        <div class="arow"><span class="ai" style="background:${VIOLET}"></span><span>A new follower on Farcaster</span></div>
        <div class="abadge">Composed on this Mac, every morning you open it</div>
      </div>
      ${agentBar('How’s my day?')}`,
  },
  {
    id: '7-defi', mac: 'Wallet', accent: GREEN, pour: 'rgba(63,185,80,.22)',
    head: 'Your positions,\nwatched while you work.',
    sub: 'Lending health, staked ETH and open approvals — reviewed in one glance, revoked with one tap.',
    body: `${chipStrip('Wallet')}
      <div class="sect">In protocols <em>$41.6k</em></div>
      <div class="row"><span class="pic" style="background:#9391f7"></span><div class="col"><div class="ttl">Aave · health factor 2.4</div><div class="sub2">$18,200 supplied · $6,100 borrowed</div></div></div>
      <div class="row"><span class="pic" style="background:#2a73ff"></span><div class="col"><div class="ttl">Morpho · health factor 1.9</div><div class="sub2">$9,400 in the ETH vault</div></div></div>
      <div class="row"><span class="pic" style="background:#0434ff"></span><div class="col"><div class="ttl">Aerodrome · veAERO locked</div><div class="sub2">12,977 AERO · ~41% voting power left</div></div></div>
      <div class="sect">Worth a look <em>3</em></div>
      <div class="row"><span class="warn">!</span><div class="col"><div class="ttl">Uniswap router approval, unlimited</div><div class="sub2">Granted 2026-06-02 · revoke.cash</div></div></div>
      <div class="row"><span class="warn">!</span><div class="col"><div class="ttl">Morpho position near liquidation</div><div class="sub2">Health factor dropped to 1.2</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '8-social', mac: 'Farcaster', accent: VIOLET, pour: 'rgba(133,93,205,.26)',
    head: 'Casts, likes and replies —\nyour room, not a feed you don’t run.',
    sub: 'Farcaster and Bluesky, read the way you already scroll them — mentions, recasts, who you follow.',
    body: `${chipStrip('Farcaster')}
      <div class="sect">/design <em>8</em></div>
      <div class="row"><span class="av"></span><div class="col"><div class="bar" style="width:82%"></div><div class="bar s" style="width:54%"></div></div><span class="src">Recast</span></div>
      <div class="row"><span class="av" style="background:rgba(255,255,255,.1)"></span><div class="col"><div class="bar" style="width:66%"></div><div class="bar s" style="width:36%"></div></div><span class="src">Mentions you</span></div>
      <div class="row"><span class="av"></span><div class="col"><div class="bar" style="width:74%"></div><div class="bar s" style="width:48%"></div></div><span class="src">Liked</span></div>
      <div class="sect">Signers <em>2</em></div>
      <div class="row"><span class="pic" style="background:#855dcd"></span><div class="col"><div class="ttl">Warpcast client</div><div class="sub2">Can post as you · added 2026-04-11</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '9-markets', mac: 'Tokens', accent: '#0085ff', pour: 'rgba(0,133,255,.26)',
    head: 'Charts and odds,\nwithout leaving your things.',
    sub: 'Watch a token or a prediction market and its chart lands right beside everything else you keep.',
    body: `${chipStrip('Tokens')}
      <div class="sect">Watching <em>4</em></div>
      <div class="row"><span class="dot" style="background:#f7931a"></span><div class="col"><div class="ttl">WBTC</div><div class="sub2">$97,412 · +1.8% today</div></div><span class="spk"><svg width="${100*S}" height="${34*S}" viewBox="0 0 100 34"><path d="M0 24 L20 20 L40 26 L60 12 L80 16 L100 6" fill="none" stroke="${GREEN}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></span></div>
      <div class="row"><span class="dot" style="background:#14f195"></span><div class="col"><div class="ttl">SOL</div><div class="sub2">$168.20 · -0.6% today</div></div><span class="spk"><svg width="${100*S}" height="${34*S}" viewBox="0 0 100 34"><path d="M0 10 L20 14 L40 8 L60 20 L80 18 L100 24" fill="none" stroke="${RED}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg></span></div>
      <div class="sect">Markets <em>2</em></div>
      <div class="row"><span class="pic" style="background:#12ff80"></span><div class="col"><div class="ttl">Fed cuts rates in September?</div><div class="sub2">Kalshi · 62¢ Yes</div></div></div>
      ${agentBar()}`,
  },
  {
    id: '10-import', mac: null, accent: BLUE, pour: 'rgba(46,99,255,.26)',
    head: 'Bring your history.\nKeep it, searchable.',
    sub: 'Import Instagram, Snapchat, ChatGPT and more — one receipt lands in your feed, the rest waits in its own room.',
    body: `${chipStrip('All')}
      <div class="sect">Today <em>3</em></div>
      <div class="row"><span class="thumb" style="background:linear-gradient(140deg,#e1306c,#fd1d1d,#fcaf45)"></span><div class="col"><div class="ttl">Imported Instagram — 1,204 saves and likes</div><div class="sub2">Search Instagram’s room any time</div></div><span class="src">Instagram</span></div>
      <div class="row"><span class="thumb" style="background:linear-gradient(140deg,#fffc00,#111)"></span><div class="col"><div class="ttl">Imported Snapchat — 340 chats, 812 memories</div><div class="sub2">Dated, searchable, yours to keep</div></div><span class="src">Snapchat</span></div>
      <div class="row"><span class="thumb" style="background:linear-gradient(140deg,#10a37f,#0b3b32)"></span><div class="col"><div class="ttl">Imported ChatGPT — 2,481 conversations</div><div class="sub2">One tap. Nothing leaves this Mac.</div></div><span class="src">ChatGPT</span></div>
      ${agentBar()}`,
  },
];

const macTitleBar = (title) => `
<div class="tbar">
  <span class="tl"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></span>
  <span class="ttxt">${title || 'Casberi'}</span>
</div>`;

const poster = (sc) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html,body{width:${W}px;height:${H}px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#14110d;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:${px(7)} ${px(7)}, ${px(9)} ${px(9)};}
.mast{position:absolute;left:${px(110)};right:${px(110)};top:${px(72)};display:flex;justify-content:space-between;font-size:${px(27)};letter-spacing:.16em;font-weight:600;}
.rule{position:absolute;left:${px(110)};right:${px(110)};top:${px(122)};height:${px(3)};background:#14110d;}
.dot0{position:absolute;left:50%;transform:translateX(-${px(9)});top:${px(160)};width:${px(18)};height:${px(18)};border-radius:50%;background:${sc.accent};margin-left:${px(-370)};}
.head{position:absolute;left:${px(260)};right:${px(260)};top:${px(202)};font-size:${px(80)};line-height:.98;font-weight:800;letter-spacing:-.04em;white-space:pre-line;text-align:center;}
.sub{position:absolute;left:${px(430)};right:${px(430)};top:${px(392)};font-size:${px(30)};line-height:1.4;color:#4a463c;font-weight:500;text-align:center;}
.win{position:absolute;left:50%;transform:translateX(-50%);top:${px(600)};width:${px(1760)};height:${px(1080)};
  border-radius:${px(20)};overflow:hidden;background:#0b0910;
  box-shadow:0 ${px(50)} ${px(110)} rgba(20,17,13,.34), inset 0 0 0 ${px(1)} rgba(255,255,255,.08);}
.pour{position:absolute;left:0;right:0;top:0;height:${px(340)};background:linear-gradient(to bottom, ${sc.pour} 0%, rgba(0,0,0,0) 100%);}
.tbar{position:relative;height:${px(58)};background:#15121b;display:flex;align-items:center;padding:0 ${px(22)};}
.tl{display:flex;gap:${px(9)};} .tl i{width:${px(14)};height:${px(14)};border-radius:50%;display:block;}
.ttxt{position:absolute;left:0;right:0;text-align:center;font-size:${px(22)};font-weight:600;color:rgba(255,255,255,.55);}
.inner{position:absolute;left:0;right:0;top:${px(58)};bottom:0;padding:${px(30)} ${px(46)} 0;color:#fff;}
.chips{display:flex;align-items:center;gap:${px(15)};margin-bottom:${px(24)};flex-wrap:wrap;}
.cc{width:${px(64)};height:${px(64)};border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;}
.cc.av{background:#fff;} .cc i{width:${px(22)};height:${px(22)};border-radius:50%;display:block;}
.sect{font-size:${px(23)};font-weight:700;color:rgba(255,255,255,.42);margin:${px(20)} 0 ${px(10)};letter-spacing:.02em;}
.sect em{font-style:normal;color:rgba(255,255,255,.28);margin-left:${px(8)};}
.row{display:flex;align-items:center;gap:${px(18)};padding:${px(14)} 0;}
.row .col{flex:1;min-width:0;}
.av{width:${px(52)};height:${px(52)};border-radius:50%;background:rgba(255,255,255,.16);flex:none;}
.thumb{width:${px(52)};height:${px(52)};border-radius:${px(13)};background:linear-gradient(140deg,#3b4d70,#1e2a42);flex:none;}
.dot{width:${px(13)};height:${px(13)};border-radius:50%;flex:none;margin:0 ${px(20)};}
.pic{width:${px(50)};height:${px(50)};border-radius:${px(14)};flex:none;}
.warn{width:${px(46)};height:${px(46)};border-radius:50%;background:rgba(255,159,10,.2);color:#ff9f0a;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:${px(25)};flex:none;margin:0 ${px(3)};}
.bar{height:${px(13)};border-radius:${px(7)};background:rgba(255,255,255,.24);}
.bar.s{height:${px(10)};background:rgba(255,255,255,.12);margin-top:${px(8)};}
.ttl{font-size:${px(23)};font-weight:650;}
.sub2{font-size:${px(19)};color:rgba(255,255,255,.44);margin-top:${px(4)};}
.host{font-size:${px(17)};color:rgba(255,255,255,.3);margin-top:${px(3)};font-family:ui-monospace,monospace;}
.amt{font-size:${px(25)};font-weight:750;}
.time{font-size:${px(20)};font-weight:700;color:rgba(255,255,255,.55);width:${px(58)};flex:none;}
.vbar{width:${px(6)};height:${px(38)};border-radius:${px(4)};flex:none;}
.src{margin-left:auto;font-size:${px(17)};color:rgba(255,255,255,.32);font-weight:600;flex:none;}
.spk{margin-left:auto;flex:none;}
.pgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:${px(12)};}
.pc{aspect-ratio:1;border-radius:${px(16)};display:block;}
.agrid{display:grid;grid-template-columns:repeat(10,1fr);gap:${px(14)};}
.at{aspect-ratio:1;border-radius:${px(16)};display:block;box-shadow:0 ${px(5)} ${px(12)} rgba(0,0,0,.35);}
.wtot{font-size:${px(21)};color:rgba(255,255,255,.45);margin-top:${px(6)};font-weight:600;}
.wrow{display:flex;align-items:baseline;gap:${px(16)};margin-top:${px(4)};}
.wn{font-size:${px(56)};font-weight:800;letter-spacing:-.025em;}
.wpill{font-size:${px(21)};font-weight:750;padding:${px(7)} ${px(16)};border-radius:100px;background:rgba(63,185,80,.18);color:${GREEN};}
.wsub{font-size:${px(20)};color:rgba(255,255,255,.42);margin-top:${px(5)};}
.spark{margin:${px(12)} 0 ${px(16)};}
.tree{position:relative;height:${px(340)};border-radius:${px(18)};overflow:hidden;}
.tc{position:absolute;border-radius:${px(14)};display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 0 0 0 ${px(2)} rgba(0,0,0,.2);}
.tc b{font-weight:800;color:#fff;} .tc i{font-style:normal;color:rgba(255,255,255,.82);margin-top:${px(4)};font-weight:600;}
.askq{font-size:${px(27)};font-weight:700;background:rgba(255,255,255,.09);border-radius:100px;padding:${px(17)} ${px(26)};box-shadow:inset 0 0 0 ${px(2)} rgba(255,255,255,.1);display:inline-block;}
.acard{margin-top:${px(20)};background:rgba(255,255,255,.05);border-radius:${px(22)};padding:${px(26)};}
.ah{font-size:${px(27)};font-weight:700;line-height:1.32;}
.arow{display:flex;align-items:center;gap:${px(14)};margin-top:${px(16)};font-size:${px(20)};color:rgba(255,255,255,.74);font-weight:600;}
.ai{width:${px(40)};height:${px(40)};border-radius:${px(12)};flex:none;}
.abadge{margin-top:${px(18)};font-size:${px(18)};color:rgba(255,255,255,.4);font-weight:600;}
.ptitle{font-size:${px(34)};font-weight:800;letter-spacing:-.02em;margin-top:${px(4)};}
.pnote{font-size:${px(20)};color:rgba(255,255,255,.5);line-height:1.45;margin-top:${px(8)};}
.abar{position:absolute;left:${px(46)};right:${px(46)};bottom:${px(30)};display:flex;align-items:center;justify-content:space-between;
  background:rgba(255,255,255,.11);border-radius:100px;padding:${px(19)} ${px(26)};
  box-shadow:inset 0 0 0 ${px(2)} rgba(255,255,255,.12), 0 ${px(10)} ${px(28)} rgba(0,0,0,.4);
  font-size:${px(23)};font-weight:600;color:rgba(255,255,255,.6);}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
<div class="rule"></div>
<div class="head">${sc.head}</div>
<div class="sub">${sc.sub}</div>
<div class="win">${macTitleBar(sc.mac)}<div class="pour"></div><div class="inner">${sc.body}</div></div>
</body></html>`;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  for (const sc of SCREENS) {
    const file = path.join(__dirname, `_mac-appstore-${sc.id}.html`);
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
