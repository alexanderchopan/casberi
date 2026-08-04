// THE VISUALIZATIONS reel — v4 "full bleed", ruled 2026-08-04. v3's device
// shells died in review (user: "maybe now we shouldn't have the shells and we
// just show the visualizations"), and with them every screen that needed
// FAKE CONTENT — the colored-tile album covers, the invented posts, the mail
// — because a gradient square pretending to be album art is what read as
// unreal. What survives is what the reel is named for: the READS, which are
// abstract data graphics and therefore look real at any size.
//   One visualization at a time, drawn at cinema scale on black. The only
//   chrome is the app's own source chip, top-left — and it does its CoinFlip
//   turn (one forward X-axis rotation, the label swapping at 90°) every time
//   the scene moves to a different source. Twelve scenes:
//     Wallet: balance line (leading dot, area wash) -> holdings treemap ->
//             the flow band (in green, out neutral — never red) -> risk axis
//     Photos: capture-year heatmap -> topic map
//     Instagram: leaderboard      Today: hour bars (capsules, no axes)
//     PostHog: the metric ring    Aerodrome: the melt
//     Wallet: connections (equal-weight ribbons, drawn on)
//     Cloudflare: the runway
//   Finale: BerryRain full-canvas over the chip strip doing a cascade of
//   coin flips; CasberiMark berry outro.
// Colors are the app's own tokens: page #000, sheet #111113, accent ink
// #1673e6, link blue #0a84ff, green #3fb950. No hairlines — depth by tone.
// Deterministic (window.seek/window.TOTAL) -> design/launch-video/render-viz.sh
const fs = require('fs'), path = require('path');

const BLUE = '#0a84ff', INK = '#1673e6', GREEN = '#3fb950', RED = '#ff453a',
      AMBER = '#ff9f0a', VIOLET = '#8c40c7';

const MARK = [
  [0.654, 0.812, '#cee6ff'], [0.812, 0.469, '#b1d8ff'], [0.337, 0.794, '#b1d8ff'],
  [0.513, 0.487, '#91c8ff'], [0.188, 0.487, '#6cb5ff'], [0.654, 0.188, '#6cb5ff'],
  [0.329, 0.188, '#0a84ff'],
];
const berrySVG = (s, cls) => `<svg class="${cls || ''}" width="${s}" height="${s}" viewBox="0 0 100 100">${
  MARK.map(([x, y, c]) => `<circle cx="${x * 100}" cy="${y * 100}" r="18.8" fill="${c}"/>`).join('')}</svg>`;

// ---- scene table -----------------------------------------------------------
// [dur, chip, title, accent]
const SC = [
  [2.5, 'Wallet',     'Across your wallets',      GREEN],
  [2.4, 'Wallet',     'Holdings',                 BLUE],
  [2.5, 'Wallet',     'Where the money went',     GREEN],
  [2.0, 'Wallet',     'Distance to liquidation',  AMBER],
  [2.2, 'Photos',     'Your capture year',        BLUE],
  [2.0, 'Photos',     'What your images say',     BLUE],
  [2.0, 'Instagram',  'Who you save most',        VIOLET],
  [1.9, 'Today',      'Your day, hour by hour',   INK],
  [1.9, 'PostHog',    'signed_up',                INK],
  [1.8, 'Aerodrome',  'The melt',                 BLUE],
  [2.0, 'Wallet',     'Connections',              BLUE],
  [1.8, 'Cloudflare', 'The runway',               BLUE],
];
const T0 = SC.reduce((a, s) => (a.push(a[a.length - 1] + s[0]), a), [0.3]); // scene starts
const FIN = T0[12], TOTAL = FIN + 4.6;   // finale + outro -> 30.0s at these durations

const TREEMAP = [   // scaled to a 1300x760 stage
  [0, 0, 771, 483, 'ETH',  '$26,180', '#3a6df0'],
  [783, 0, 517, 235, 'SOL',  '$7,940',  '#8f5bd9'],
  [783, 247, 517, 236, 'USDC', '$6,120', '#2775ca'],
  [0, 495, 390, 265, 'BTC',  '$4,310',  '#c8842a'],
  [402, 495, 378, 265, 'AERO', '$2,140', '#2f66b5'],
  [792, 495, 508, 265, 'HYPE', '$1,520', '#2e9e8f'],
];
const TOPICS = [    // 1240x560 word map — every label appears in a screenshot
  [0, 0, 700, 340, 'figma', 64, 0.42], [716, 0, 524, 340, 'recipes', 46, 0.3],
  [0, 356, 470, 204, 'tokyo', 38, 0.26], [486, 356, 430, 204, 'github.com', 34, 0.22],
  [932, 356, 308, 204, 'invoice', 30, 0.18],
];
const LEADERS = [['maya', 34, '#8f5bd9'], ['dwr', 28, '#3a6df0'], ['jesse', 19, '#2e9e8f'], ['kartik', 12, '#c8842a']];
const HOURS = [12, 20, 32, 26, 44, 58, 40, 66, 84, 60, 92, 74, 50, 34];
const MONTHS = ['Jan', 'Mar', 'May', 'Jul', 'Sep', 'Nov'];
const CHIPSTRIP = ['All', 'Wallet', 'Photos', 'Farcaster', 'Spotify', 'GitHub'];
const lcg = seed => () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const heatR = lcg(7);
const HEAT = Array.from({ length: 30 * 7 }, () => { const v = heatR(); return v < 0.24 ? 0 : v; });
const rainR = lcg(20260804);
const BERRIES = ['#0a84ff', '#3f9fff', '#0a84ff', '#1266c4'];
const DROPS = Array.from({ length: 42 }, (_, i) => ({
  x: 140 + rainR() * 1640, delay: rainR() * 1.7, dur: 0.95 + rainR() * 0.45,
  r: 5 + rainR() * 9, c: BERRIES[i % 4], drift: (rainR() - 0.5) * 60,
}));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1920px;height:1080px;overflow:hidden;background:#000;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:radial-gradient(1500px 1000px at 50% 42%, #0b0b10, #000 74%);}
.wash{position:absolute;inset:0;opacity:0;will-change:opacity,background;}

/* the lockup — the app's own chip, then the read's name */
.lockup{position:absolute;left:120px;top:86px;z-index:50;}
.fchipw{perspective:520px;display:inline-block;}
.fchip{display:inline-block;font-size:24px;font-weight:750;padding:12px 26px;border-radius:100px;background:${INK};color:#fff;box-shadow:0 0 0 1px rgba(255,255,255,.08), 0 14px 34px rgba(0,0,0,.6);will-change:transform;}
.ltitle{margin-top:22px;font-size:52px;font-weight:800;letter-spacing:-.03em;color:#fff;will-change:opacity,transform;}

/* scenes */
.scene{position:absolute;inset:0;opacity:0;will-change:opacity,transform;}
.sstage{position:absolute;left:50%;top:54%;transform:translate(-50%,-50%);}
.bignum{font-size:150px;font-weight:800;letter-spacing:-.035em;color:#fff;font-variant-numeric:tabular-nums;display:flex;align-items:center;gap:36px;}
.pillL{font-size:30px;font-weight:750;color:#04270f;background:${GREEN};padding:10px 24px;border-radius:100px;will-change:transform,opacity;}
.subL{font-size:27px;color:rgba(235,235,245,.55);font-weight:600;margin-top:26px;will-change:opacity;}

.tmcell{position:absolute;border-radius:22px;padding:26px 30px;will-change:transform,opacity;}
.tmcell .sym{font-size:40px;font-weight:800;color:#fff;letter-spacing:-.01em;}
.tmcell .val{font-size:26px;font-weight:650;color:rgba(255,255,255,.75);margin-top:4px;font-variant-numeric:tabular-nums;}

.risktrack{position:relative;width:1400px;height:10px;border-radius:5px;background:#232327;}
.riskcap{position:absolute;right:0;top:0;width:64px;height:10px;border-radius:5px;background:${RED};opacity:.9;}
.riskdot{position:absolute;top:-9px;width:28px;height:28px;border-radius:50%;box-shadow:0 0 0 7px rgba(17,17,19,.9), 0 0 34px rgba(255,255,255,.12);will-change:transform,opacity;}
.risklbl{position:absolute;font-size:25px;font-weight:700;color:rgba(255,255,255,.85);white-space:nowrap;will-change:opacity;}

.hm2{display:grid;grid-template-columns:repeat(30,34px);grid-auto-rows:34px;gap:7px;}
.hm2 i{border-radius:8px;background:${BLUE};will-change:opacity,transform;}
.hm2 i.z{background:#1b1b1f;}
.hmonths{display:flex;justify-content:space-between;width:1224px;margin-top:22px;font-size:22px;color:rgba(235,235,245,.4);font-weight:650;}

.topiccell{position:absolute;border-radius:24px;display:flex;align-items:flex-end;padding:26px;font-weight:800;color:#fff;letter-spacing:-.015em;will-change:transform,opacity;}

.leadrow2{display:flex;align-items:center;gap:28px;margin-top:38px;will-change:opacity;}
.leadrow2 .av{width:66px;height:66px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:28px;font-weight:800;color:#fff;}
.leadrow2 .nm{width:170px;font-size:32px;font-weight:750;color:#fff;}
.leadrow2 .bar{height:30px;border-radius:15px;background:${VIOLET};transform-origin:left;will-change:transform;}
.leadrow2 .ct{font-size:30px;font-weight:750;color:rgba(235,235,245,.55);margin-left:auto;font-variant-numeric:tabular-nums;}

.bars2{display:flex;align-items:flex-end;gap:20px;height:460px;}
.bars2 i{width:62px;border-radius:31px;background:${INK};opacity:.42;transform-origin:bottom;will-change:transform;}
.bars2 i:last-child{opacity:1;}

.ringtxt2 .n{font-size:120px;font-weight:800;color:#fff;font-variant-numeric:tabular-nums;line-height:1;}
.ringtxt2 .l{font-size:28px;color:rgba(235,235,245,.55);font-weight:600;margin-top:14px;width:420px;line-height:1.5;}

.melttrack{position:relative;width:1300px;height:36px;border-radius:18px;background:#1b1b1f;overflow:hidden;}
.melttrack .grow{position:absolute;left:0;top:0;bottom:0;border-radius:18px;transform-origin:left;will-change:transform;}
.meltlbl{display:flex;justify-content:space-between;width:1300px;margin-top:26px;font-size:27px;font-weight:650;color:rgba(235,235,245,.55);}
.meltlbl b{color:#fff;font-weight:750;}

.conlbl{position:absolute;font-size:25px;font-weight:700;color:rgba(235,235,245,.6);white-space:nowrap;will-change:opacity;}

.runtrack{position:relative;width:1400px;height:8px;border-radius:4px;background:#232327;}
.runtick{position:absolute;top:-13px;width:6px;height:34px;border-radius:3px;background:${BLUE};box-shadow:0 0 24px rgba(10,132,255,.4);will-change:transform,opacity;}
.runlbl{position:absolute;top:44px;font-size:25px;font-weight:700;color:rgba(255,255,255,.85);white-space:nowrap;transform:translateX(-50%);will-change:opacity;}
.runtoday{position:absolute;left:0;top:-40px;font-size:22px;font-weight:650;color:rgba(235,235,245,.4);}

/* finale */
#finale{position:absolute;inset:0;opacity:0;will-change:opacity;}
.strip{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);display:flex;gap:18px;}
.strip .fchip2w{perspective:560px;}
.strip .fchip2{display:inline-block;font-size:27px;font-weight:750;padding:15px 32px;border-radius:100px;background:#1c1c1e;color:rgba(255,255,255,.9);box-shadow:0 0 0 1px rgba(255,255,255,.1), 0 18px 40px rgba(0,0,0,.6);will-change:transform,background;}
.strip .fchip2.on{background:${INK};color:#fff;}
.drop{position:absolute;border-radius:50%;will-change:transform,opacity;z-index:40;filter:drop-shadow(0 0 10px rgba(10,132,255,.35));}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;opacity:0;will-change:opacity;}
.outro .b{font-size:120px;font-weight:800;letter-spacing:-.045em;color:#fff;line-height:.9;margin-top:30px;}
.outro .u{font-size:24px;letter-spacing:.1em;color:rgba(255,255,255,.55);margin-top:26px;font-weight:600;}
.outro .u b{color:${BLUE};}
.outro svg{will-change:transform,opacity;}
</style></head><body>
<div class="stage">
<div class="wash" id="wash"></div>

<div class="lockup" id="lockup">
  <span class="fchipw"><span class="fchip" id="lchip">Wallet</span></span>
  <div class="ltitle" id="ltitle">Across your wallets</div>
</div>

<!-- 0 · balance line -->
<div class="scene" id="s0"><div class="sstage" style="width:1560px">
  <div class="bignum"><span id="s0num">$0</span><span class="pillL" id="s0pill">+2.6%</span></div>
  <svg width="1560" height="430" viewBox="0 0 1560 430" style="margin-top:30px;overflow:visible">
    <defs><linearGradient id="gfill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${GREEN}" stop-opacity=".16"/><stop offset="1" stop-color="${GREEN}" stop-opacity="0"/></linearGradient></defs>
    <path id="s0area" d="M2,340 C160,320 260,362 380,300 C520,232 600,282 720,240 C860,192 940,252 1060,152 C1180,62 1300,122 1420,92 L1558,62 L1558,430 L2,430 Z" fill="url(#gfill)" opacity="0"/>
    <path id="s0line" d="M2,340 C160,320 260,362 380,300 C520,232 600,282 720,240 C860,192 940,252 1060,152 C1180,62 1300,122 1420,92 L1558,62" stroke="${GREEN}" stroke-width="5" fill="none" stroke-linecap="round" style="filter:drop-shadow(0 0 14px rgba(63,185,80,.45))"/>
    <circle id="s0dot" r="9" fill="${GREEN}" style="filter:drop-shadow(0 0 16px rgba(63,185,80,.9))"/>
  </svg>
  <div class="subL" id="s0sub">Mostly ETH · +$310 — sampled on device, every four hours</div>
</div></div>

<!-- 1 · holdings treemap -->
<div class="scene" id="s1"><div class="sstage" style="width:1300px;height:760px;top:57%">
  ${TREEMAP.map(([x, y, w, h, s, v, c], k) =>
    `<div class="tmcell" data-k="${k}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;background:linear-gradient(155deg,${c},${c}e6)"><div class="sym">${s}</div><div class="val">${v}</div></div>`).join('')}
</div></div>

<!-- 2 · flow band -->
<div class="scene" id="s2"><div class="sstage" style="width:1500px">
  <svg width="1500" height="430" viewBox="0 0 1500 430" style="overflow:visible">
    <defs>
      <clipPath id="fclipL"><rect id="fclipLr" x="730" y="0" width="0" height="430"/></clipPath>
      <clipPath id="fclipR"><rect id="fclipRr" x="744" y="0" width="0" height="430"/></clipPath>
    </defs>
    <g clip-path="url(#fclipL)">
      <rect x="0" y="40" width="300" height="132" fill="${GREEN}"/>
      <polygon points="300,40 718,120 718,196 300,172" fill="${GREEN}" opacity=".8"/>
      <rect x="0" y="244" width="300" height="62" fill="${GREEN}" opacity=".85"/>
      <polygon points="300,244 718,212 718,244 300,306" fill="${GREEN}" opacity=".55"/>
      <text x="26" y="116" fill="#04270f" font-size="27" font-weight="750">Coinbase</text>
      <text x="26" y="288" fill="#04270f" font-size="24" font-weight="750">Peer</text>
    </g>
    <g clip-path="url(#fclipR)">
      <rect x="1200" y="66" width="300" height="72" fill="#3a3a3e"/>
      <polygon points="756,128 1200,66 1200,138 756,176" fill="#3a3a3e" opacity=".8"/>
      <rect x="1200" y="196" width="300" height="106" fill="#3a3a3e"/>
      <polygon points="756,186 1200,196 1200,302 756,240" fill="#3a3a3e" opacity=".55"/>
      <text x="1226" y="112" fill="rgba(255,255,255,.85)" font-size="25" font-weight="700">Gnosis Pay</text>
      <text x="1226" y="256" fill="rgba(255,255,255,.85)" font-size="25" font-weight="700">Aave</text>
    </g>
    <rect x="730" y="106" width="26" height="212" rx="13" fill="${BLUE}" id="fspine" style="filter:drop-shadow(0 0 20px rgba(10,132,255,.5))"/>
  </svg>
  <div style="display:flex;justify-content:space-between;margin-top:22px">
    <span class="subL" style="margin:0;color:${GREEN}">$3,000 in</span>
    <span class="subL" style="margin:0">$1,210 out — every lane a real transfer</span>
  </div>
</div></div>

<!-- 3 · risk axis -->
<div class="scene" id="s3"><div class="sstage" style="width:1400px;height:220px">
  <div class="risktrack" style="margin-top:100px"><span class="riskcap"></span>
    <span class="riskdot" data-k="0" style="left:16%;background:${GREEN}"></span>
    <span class="riskdot" data-k="1" style="left:44%;background:${BLUE}"></span>
    <span class="riskdot" data-k="2" style="left:76%;background:${AMBER}"></span>
    <span class="risklbl" data-k="0" style="left:12%;top:-64px">Aave · hf 2.1</span>
    <span class="risklbl" data-k="1" style="left:40%;top:44px">Morpho · hf 1.6</span>
    <span class="risklbl" data-k="2" style="left:69%;top:-64px">Hyperliquid · 15%</span>
  </div>
</div></div>

<!-- 4 · capture-year heatmap -->
<div class="scene" id="s4"><div class="sstage">
  <div class="hm2">${HEAT.map(v => `<i${v === 0 ? ' class="z"' : ''} data-v="${v.toFixed(2)}"></i>`).join('')}</div>
  <div class="hmonths">${MONTHS.map(m => `<span>${m}</span>`).join('')}</div>
</div></div>

<!-- 5 · topic map -->
<div class="scene" id="s5"><div class="sstage" style="width:1240px;height:560px">
  ${TOPICS.map(([x, y, w, h, t, fz, a], k) =>
    `<div class="topiccell" data-k="${k}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;font-size:${fz}px;background:rgba(10,132,255,${a})">${t}</div>`).join('')}
</div></div>

<!-- 6 · leaderboard -->
<div class="scene" id="s6"><div class="sstage" style="width:1340px">
  ${LEADERS.map(([n, c, hue], k) =>
    `<div class="leadrow2" data-k="${k}"><span class="av" style="background:${hue}">${n[0].toUpperCase()}</span><span class="nm">${n}</span><span class="bar" data-w="${(c / 34 * 820) | 0}" style="width:${(c / 34 * 820) | 0}px;background:linear-gradient(90deg,${VIOLET},${VIOLET}cc)"></span><span class="ct" data-n="${c}">0</span></div>`).join('')}
</div></div>

<!-- 7 · hour bars -->
<div class="scene" id="s7"><div class="sstage">
  <div class="bars2">${HOURS.map(h => `<i style="height:${h}%"></i>`).join('')}</div>
</div></div>

<!-- 8 · metric ring -->
<div class="scene" id="s8"><div class="sstage" style="display:flex;align-items:center;gap:90px">
  <svg width="380" height="380" viewBox="0 0 380 380" style="overflow:visible">
    <circle cx="190" cy="190" r="158" fill="none" stroke="#1e1e22" stroke-width="26"/>
    <circle id="s8arc" cx="190" cy="190" r="158" fill="none" stroke="${INK}" stroke-width="26" stroke-linecap="round" transform="rotate(-90 190 190)" stroke-dasharray="993" stroke-dashoffset="993" style="filter:drop-shadow(0 0 26px rgba(22,115,230,.45))"/>
    <polyline id="s8curve" points="120,230 152,214 178,222 210,192 242,200 272,168" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="6" stroke-linecap="round"/>
  </svg>
  <div class="ringtxt2"><div class="n" id="s8num">0</div><div class="l">of the next 100 — the metric's own week drawn inside its milestone ring</div></div>
</div></div>

<!-- 9 · the melt -->
<div class="scene" id="s9"><div class="sstage" style="width:1300px">
  <div class="melttrack">
    <div class="grow" id="s9dim" style="width:100%;background:rgba(10,132,255,.22)"></div>
    <div class="grow" id="s9lit" style="width:41%;background:linear-gradient(90deg,${BLUE},#3f9fff)"></div>
  </div>
  <div class="meltlbl"><span><b>5,342 votes</b> still standing</span><span>12,977 locked · ends 2028</span></div>
</div></div>

<!-- 10 · connections -->
<div class="scene" id="s10"><div class="sstage" style="width:1300px;height:460px">
  <svg width="1300" height="420" viewBox="0 0 1300 420" style="overflow:visible">
    <path class="ribbon" d="M140,120 C420,120 780,90 1140,90" stroke="rgba(235,235,245,.4)" stroke-width="6" fill="none"/>
    <path class="ribbon" d="M140,120 C420,140 780,300 1140,310" stroke="rgba(235,235,245,.4)" stroke-width="6" fill="none"/>
    <path class="ribbon" d="M140,320 C460,320 800,314 1140,310" stroke="rgba(235,235,245,.4)" stroke-width="6" fill="none"/>
    <circle cx="128" cy="120" r="22" fill="#4c4c52"/><circle cx="128" cy="320" r="22" fill="#4c4c52"/>
    <circle cx="1154" cy="90" r="25" fill="#3a6df0" style="filter:drop-shadow(0 0 18px rgba(58,109,240,.5))"/>
    <circle cx="1154" cy="310" r="25" fill="#8f5bd9" style="filter:drop-shadow(0 0 18px rgba(143,91,217,.5))"/>
  </svg>
  <span class="conlbl" style="left:60px;top:158px">counterparty</span>
  <span class="conlbl" style="left:60px;top:358px">counterparty</span>
  <span class="conlbl" style="left:1210px;top:78px;color:#fff">main</span>
  <span class="conlbl" style="left:1210px;top:298px;color:#fff">vault</span>
</div></div>

<!-- 11 · the runway -->
<div class="scene" id="s11"><div class="sstage" style="width:1400px;height:200px">
  <div class="runtrack" style="margin-top:90px">
    <span class="runtoday">today</span>
    <span class="runtick" data-k="0" style="left:12%"></span>
    <span class="runtick" data-k="1" style="left:46%"></span>
    <span class="runtick" data-k="2" style="left:82%"></span>
    <span class="runlbl" data-k="0" style="left:12%">cert · 12d</span>
    <span class="runlbl" data-k="1" style="left:46%">domain · 44d</span>
    <span class="runlbl" data-k="2" style="left:82%">invoice · 89d</span>
  </div>
</div></div>

<div id="finale">
  <div class="strip">${CHIPSTRIP.map((c, k) =>
    `<span class="fchip2w"><span class="fchip2${k === 0 ? ' on' : ''}" data-k="${k}">${c}</span></span>`).join('')}</div>
  ${DROPS.map((d, k) => `<span class="drop" data-k="${k}" style="width:${(d.r * 2) | 0}px;height:${(d.r * 2) | 0}px;background:${d.c};left:${d.x | 0}px;top:0"></span>`).join('')}
</div>

<div class="outro" id="outro">${berrySVG(130, 'omark')}<div class="b">Casberi</div><div class="u mono">EVERY READ, ON DEVICE — <b>casberi.app</b></div></div>
</div>
<script>
var clamp01=function(v){return Math.max(0,Math.min(1,v));};
var easeOut=function(p){return 1-Math.pow(1-p,3);};
var easeO4=function(p){return 1-Math.pow(1-p,4);};
var easeIO=function(p){return p<0.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2;};
var back=function(p){var c=1.6;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
window.TOTAL=${TOTAL};
var T0=${JSON.stringify(T0.map(t => +t.toFixed(3)))};
var CHIPS=${JSON.stringify(SC.map(s => s[1]))};
var TITLES=${JSON.stringify(SC.map(s => s[2]))};
var ACC=${JSON.stringify(SC.map(s => s[3]))};
var FIN=${+FIN.toFixed(3)};
var DROPS=${JSON.stringify(DROPS.map(d => ({ delay: +d.delay.toFixed(3), dur: +d.dur.toFixed(3), drift: +d.drift.toFixed(1) })))};
var scenes=[];for(var i=0;i<12;i++)scenes.push(document.getElementById('s'+i));
var lineLen=null,curveLen=null,ribbonLens=null;

function sceneIdx(t){for(var i=11;i>=0;i--){if(t>=T0[i])return i;}return 0;}

window.seek=function(t){
  var idx=sceneIdx(Math.min(t,FIN-0.01));
  // ---- lockup: chip flips when the SOURCE changes; title crossfades every scene
  var lchip=document.getElementById('lchip'),ltitle=document.getElementById('ltitle');
  var lockOp=Math.min(clamp01((t-0.15)/0.4),1-clamp01((t-(FIN-0.3))/0.3));
  document.getElementById('lockup').style.opacity=lockOp;
  var shown=idx;
  var rot=0;
  // find the most recent boundary where the chip changed
  for(var b=1;b<12;b++){
    if(CHIPS[b]!==CHIPS[b-1]){
      var fp=clamp01((t-(T0[b]-0.18))/0.5);
      if(fp>0&&fp<1)rot=360*easeOut(fp);
      if(t>=T0[b]-0.18&&fp<0.5)shown=b-1;   // label swaps at 90°
    }
  }
  lchip.textContent=CHIPS[shown];
  lchip.style.transform='rotateX('+rot+'deg)';
  // title: fade at each scene boundary
  var tb=T0[idx],tin=clamp01((t-tb-0.02)/0.3);
  ltitle.textContent=TITLES[idx];
  ltitle.style.opacity=Math.min(tin,lockOp);
  ltitle.style.transform='translateY('+((1-easeOut(tin))*16)+'px)';
  // hue wash follows the scene's accent, very quiet
  var wash=document.getElementById('wash');
  wash.style.background='radial-gradient(1300px 800px at 50% 46%, '+ACC[idx]+'14, transparent 70%)';
  wash.style.opacity=(t<FIN)?1:1-clamp01((t-FIN)/0.5);

  // ---- scene visibility: OVERLAPPED crossfades — the incoming scene is
  // already most of the way in at the boundary, so no frame ever dips to
  // black (the v4 first cut had a visible black trough at every cut)
  for(var i2=0;i2<12;i2++){
    var a=T0[i2],b2=T0[i2+1];
    var op=clamp01((t-(a-0.22))/0.34)*(1-clamp01((t-(b2-0.12))/0.34));
    if(t<a-0.27||t>b2+0.4)op=0;
    scenes[i2].style.opacity=op;
    var outp=clamp01((t-(b2-0.12))/0.34);
    scenes[i2].style.transform='translateY('+((1-easeOut(clamp01((t-(a-0.22))/0.55)))*22-outp*20)+'px)';
    if(op>0)anim(i2,t-a);
  }

  // ---- finale: the shower, then the strip's cascade of coin flips
  var fin=document.getElementById('finale');
  fin.style.opacity=clamp01((t-FIN+0.15)/0.35)*(1-clamp01((t-(FIN+3.3))/0.4));
  var lf=t-FIN;
  var drops=document.querySelectorAll('.drop');
  for(var d2=0;d2<drops.length;d2++){var dd=DROPS[d2];var pp=(lf-0.1-dd.delay)/dd.dur;
    if(pp<0||pp>1){drops[d2].style.opacity=0;continue;}
    var yy=-40+Math.pow(pp,1.5)*1140;
    drops[d2].style.transform='translate('+(dd.drift*pp)+'px,'+yy+'px) scaleY('+(1+0.9*Math.sin(Math.PI*Math.min(1,pp)))+')';
    drops[d2].style.opacity=Math.min(clamp01(pp/0.12),1-clamp01((pp-0.85)/0.15));}
  var chips2=document.querySelectorAll('.fchip2');
  var active2=0;
  for(var c3=0;c3<chips2.length;c3++){
    var ft=0.55+c3*0.17;                     // the wave
    var cp=clamp01((lf-ft)/0.6);
    chips2[c3].style.transform='rotateX('+(360*easeOut(cp))+'deg)';
    if(cp>0.5)active2=c3;
  }
  for(var c4=0;c4<chips2.length;c4++)chips2[c4].className='fchip2'+(c4===active2?' on':'');

  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(FIN+3.4))/0.5));
  var om=document.querySelector('.omark');if(om){var omp=clamp01((t-(FIN+3.5))/0.6);om.style.transform='scale('+(0.6+0.4*back(omp))+')';om.style.opacity=omp;}
};

function anim(i,lt){
  if(i===0){
    document.getElementById('s0num').textContent='$'+Math.round(48210*easeO4(clamp01((lt-0.1)/1.0))).toLocaleString('en-US');
    var pp=clamp01((lt-1.0)/0.35);
    var pl=document.getElementById('s0pill');pl.style.opacity=pp;pl.style.transform='scale('+(0.6+0.4*back(pp))+')';
    var ln=document.getElementById('s0line');
    if(lineLen===null)lineLen=ln.getTotalLength();
    var sp=easeIO(clamp01((lt-0.15)/1.5));
    ln.style.strokeDasharray=lineLen;ln.style.strokeDashoffset=lineLen*(1-sp);
    var pt=ln.getPointAtLength(lineLen*Math.max(0.001,sp));
    var dt=document.getElementById('s0dot');dt.setAttribute('cx',pt.x);dt.setAttribute('cy',pt.y);dt.style.opacity=sp>0.01&&sp<0.999?1:0;
    document.getElementById('s0area').style.opacity=clamp01((lt-1.5)/0.5);
    document.getElementById('s0sub').style.opacity=clamp01((lt-1.55)/0.4);
  } else if(i===1){
    var cells=document.querySelectorAll('#s1 .tmcell');
    for(var k=0;k<cells.length;k++){var cp=clamp01((lt-0.08-k*0.15)/0.5);cells[k].style.opacity=cp;cells[k].style.transform='scale('+(0.86+0.14*back(cp))+') translateY('+((1-easeOut(cp))*20)+'px)';}
  } else if(i===2){
    document.getElementById('fspine').style.opacity=clamp01(lt/0.3);
    var fl=easeIO(clamp01((lt-0.25)/0.95));
    var lr=document.getElementById('fclipLr');lr.setAttribute('x',730-730*fl);lr.setAttribute('width',730*fl);
    var fr=easeIO(clamp01((lt-0.55)/0.95));
    document.getElementById('fclipRr').setAttribute('width',760*fr);
    document.querySelector('#s2 .sstage > div').style.opacity=clamp01((lt-1.6)/0.4);
  } else if(i===3){
    var dots=document.querySelectorAll('#s3 .riskdot');
    for(var k3=0;k3<dots.length;k3++){var dp=clamp01((lt-0.15-k3*0.2)/0.45);dots[k3].style.opacity=dp;dots[k3].style.transform='translateY('+((1-back(dp))*-46)+'px)';}
    var lbls=document.querySelectorAll('#s3 .risklbl');
    for(var k4=0;k4<lbls.length;k4++){lbls[k4].style.opacity=clamp01((lt-0.4-k4*0.2)/0.4);}
  } else if(i===4){
    var hm=document.querySelectorAll('#s4 .hm2 i');
    for(var h=0;h<hm.length;h++){var col=h%30;var v=parseFloat(hm[h].getAttribute('data-v')||'0');
      var ap=clamp01((lt-0.05-col*0.038)/0.3);
      hm[h].style.opacity=hm[h].classList.contains('z')?ap*0.9:ap*(0.2+v*0.8);
      hm[h].style.transform='scale('+(0.5+0.5*easeOut(ap))+')';}
    document.querySelector('#s4 .hmonths').style.opacity=clamp01((lt-1.1)/0.4);
  } else if(i===5){
    var tc=document.querySelectorAll('#s5 .topiccell');
    for(var k5=0;k5<tc.length;k5++){var tp=clamp01((lt-0.08-k5*0.14)/0.45);tc[k5].style.opacity=tp;tc[k5].style.transform='scale('+(0.86+0.14*back(tp))+')';}
  } else if(i===6){
    var lb=document.querySelectorAll('#s6 .leadrow2');
    for(var k6=0;k6<lb.length;k6++){var lp=clamp01((lt-0.1-k6*0.16)/0.55);lb[k6].style.opacity=Math.min(1,lp*3);
      lb[k6].querySelector('.bar').style.transform='scaleX('+easeO4(lp)+')';
      var ct=lb[k6].querySelector('.ct');ct.textContent=Math.round(parseInt(ct.getAttribute('data-n'))*easeO4(lp));}
  } else if(i===7){
    var bars=document.querySelectorAll('#s7 .bars2 i');
    for(var k7=0;k7<bars.length;k7++){var bp=clamp01((lt-0.05-k7*0.07)/0.5);bars[k7].style.transform='scaleY('+back(bp)+')';}
  } else if(i===8){
    var rp=easeIO(clamp01((lt-0.1)/1.1));
    document.getElementById('s8arc').style.strokeDashoffset=993*(1-0.82*rp);
    document.getElementById('s8num').textContent=Math.round(82*rp);
    var rc=document.getElementById('s8curve');
    if(curveLen===null)curveLen=rc.getTotalLength();
    var rcp=easeIO(clamp01((lt-0.5)/0.8));
    rc.style.strokeDasharray=curveLen;rc.style.strokeDashoffset=curveLen*(1-rcp);
    document.querySelector('#s8 .ringtxt2 .l').style.opacity=clamp01((lt-0.7)/0.4);
  } else if(i===9){
    document.getElementById('s9dim').style.transform='scaleX('+easeIO(clamp01((lt-0.1)/0.7))+')';
    document.getElementById('s9lit').style.transform='scaleX('+easeIO(clamp01((lt-0.5)/0.8))+')';
    document.querySelector('#s9 .meltlbl').style.opacity=clamp01((lt-1.0)/0.4);
  } else if(i===10){
    var ribs=document.querySelectorAll('#s10 .ribbon');
    if(ribbonLens===null){ribbonLens=[];for(var r0=0;r0<ribs.length;r0++)ribbonLens.push(ribs[r0].getTotalLength());}
    for(var r1=0;r1<ribs.length;r1++){var rpp=easeIO(clamp01((lt-0.1-r1*0.18)/0.8));
      ribs[r1].style.strokeDasharray=ribbonLens[r1];ribs[r1].style.strokeDashoffset=ribbonLens[r1]*(1-rpp);}
    var cls=document.querySelectorAll('#s10 .conlbl');
    for(var r2=0;r2<cls.length;r2++)cls[r2].style.opacity=clamp01((lt-0.8-r2*0.08)/0.4);
  } else if(i===11){
    var tks=document.querySelectorAll('#s11 .runtick');
    for(var k8=0;k8<tks.length;k8++){var kp=clamp01((lt-0.15-k8*0.18)/0.45);tks[k8].style.opacity=kp;tks[k8].style.transform='translateY('+((1-back(kp))*-40)+'px)';}
    var rls=document.querySelectorAll('#s11 .runlbl');
    for(var k9=0;k9<rls.length;k9++)rls[k9].style.opacity=clamp01((lt-0.4-k9*0.18)/0.4);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname, 'clip-viz-reel.html'), html);
console.log('wrote clip-viz-reel.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
