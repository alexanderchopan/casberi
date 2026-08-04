// THE VISUALIZATIONS reel — every chart the app draws, painting itself on in
// iPhone / iPad / Mac shells, closing on the delight layer (berry rain + coin
// flips). EDITORIAL, no app screenshots — the UI is rebuilt as live HTML/CSS/
// SVG grounded in the shipped source:
//   B1 iPhone  — the Wallet room: holdings treemap (GenTagMap), balance
//                sparkline (WalletBalanceHeadline/TokenChartPlot), the flow
//                band (WalletFlowBand: in green, out neutral slab — never
//                red), risk strip (WalletRiskStrip: neutral track, only the
//                far END tinted, labels alternating).
//   B2 iPad    — the room leads: capture-year heatmap (CalendarHeatmapHero/
//                FeedHeatmap), topic map (TopicMapHero — every cell label
//                literally appears in a screenshot), leaderboard
//                (LeaderboardHero — names, not numbers first), contributions
//                (ContributionGraph).
//   B3 Mac     — the Today brief: money hero (GenMoneyHero — money moving is
//                the one sanctioned count), hour bars (GenBars — capsules,
//                no axes, the hairline law holds on charts), movers tile
//                (GenMoversTile), metric ring (PostHog MetricDisc — the
//                metric's own 7-day curve inside its milestone ring).
//   B4 delight — BerryRain (the icon's berry blues #0a84ff/#3f9fff/#1266c4,
//                deterministic seeded shower) + CoinFlip (one forward X-axis
//                turn, spring-settled) over all three shells.
// Colors are the app's own tokens (DesignTokens.swift): page #000, sheet
// #111113, well #080809, accent ink #1673e6, link blue #0a84ff, green
// #3fb950, red #ff453a. No hairlines anywhere — depth by tone.
// Deterministic (window.seek/window.TOTAL) -> render frame-by-frame:
//   design/launch-video/render-viz.sh
const fs = require('fs'), path = require('path');

const BLUE = '#0a84ff', INK = '#1673e6', GREEN = '#3fb950', RED = '#ff453a',
      AMBER = '#ff9f0a', VIOLET = '#8c40c7', BERRY = '#1266c4';

const BEATS = [
  { kick: 'THE WALLET ROOM',   accent: BLUE,   head: 'Holdings,\ndrawn live.',
    items: ['01 — Holdings treemap', '02 — Balance sparkline', '03 — The flow band', '04 — Risk on one axis'] },
  { kick: 'EVERY ROOM LEADS WITH A READ', accent: VIOLET, head: 'Rooms that\nread themselves.',
    items: ['05 — Your capture year', '06 — The topic map', '07 — Leaderboard', '08 — Contributions'] },
  { kick: 'THE MORNING BRIEF', accent: GREEN,  head: 'The day,\ncomposed.',
    items: ['09 — Money hero', '10 — Hour bars', '11 — Movers', '12 — Metric ring'] },
  { kick: 'THE DELIGHT LAYER', accent: BERRY,  head: 'Berry rain.\nCoin flips.',
    items: ['13 — Berry rain', '14 — Coin flip'] },
];
const INTRO = 1.7, DUR = [6.9, 6.9, 6.9, 4.6];
const STARTS = DUR.reduce((a, d) => (a.push(a[a.length - 1] + d), a), [INTRO]);
const OUT_AT = STARTS[4], TOTAL = OUT_AT + 2.4;   // 29.4s

// The Casberi berry mark, light-variant ramp (CasberiMark.swift — painted in
// this order so the bright berry lands on top, exactly as on the icon).
const MARK = [
  [0.654, 0.812, '#cee6ff'], [0.812, 0.469, '#b1d8ff'], [0.337, 0.794, '#b1d8ff'],
  [0.513, 0.487, '#91c8ff'], [0.188, 0.487, '#6cb5ff'], [0.654, 0.188, '#6cb5ff'],
  [0.329, 0.188, '#0a84ff'],
];
const berrySVG = (s, cls) => `<svg class="${cls || ''}" width="${s}" height="${s}" viewBox="0 0 100 100">${
  MARK.map(([x, y, c]) => `<circle cx="${x * 100}" cy="${y * 100}" r="18.8" fill="${c}"/>`).join('')}</svg>`;

// ---- in-screen data (all values are the demo register the other clips use) --
const TREEMAP = [   // [x, y, w, h, symbol, value, hue]
  [0, 0, 190, 178, 'ETH',  '$26,180', '#3a6df0'],
  [194, 0, 126, 86, 'SOL',  '$7,940',  '#8f5bd9'],
  [194, 90, 126, 88, 'USDC', '$6,120', '#2775ca'],
  [0, 182, 96, 98, 'BTC',  '$4,310',  '#c8842a'],
  [100, 182, 92, 98, 'AERO', '$2,140', '#2f66b5'],
  [196, 182, 124, 98, 'HYPE', '$1,520', '#2e9e8f'],
];
const TOPICS = [    // topic map — terms that literally appear in screenshots
  [0, 0, 214, 118, 'figma', 22], [218, 0, 162, 118, 'recipes', 14],
  [0, 122, 148, 90, 'tokyo', 11], [152, 122, 136, 90, 'github.com', 9],
  [292, 122, 88, 90, 'invoice', 7],
];
const LEADERS = [['maya', 34, '#8f5bd9'], ['dwr', 28, '#3a6df0'], ['jesse', 19, '#2e9e8f'], ['kartik', 12, '#c8842a']];
const HOURS = [12, 20, 32, 26, 44, 58, 40, 66, 84, 60, 92, 74, 50, 34];  // tallest lands late
const MOVERS = [['SOL', '+4.1%', 1], ['ETH', '+2.6%', 1], ['HYPE', '−1.9%', 0]];

// Deterministic LCG (BerryRain's own trick — never system randomness, so two
// renders of the same frame deal the same drops).
const lcg = seed => () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const rainR = lcg(20260804);
const BERRIES = ['#0a84ff', '#3f9fff', '#0a84ff', '#1266c4'];
const DROPS = Array.from({ length: 34 }, (_, i) => ({
  x: 860 + rainR() * 990, delay: rainR() * 2.1, dur: 1.05 + rainR() * 0.5,
  r: 5 + rainR() * 7, c: BERRIES[i % 4], drift: (rainR() - 0.5) * 40,
}));
const heatR = lcg(7);
const HEAT = Array.from({ length: 22 * 7 }, () => { const v = heatR(); return v < 0.22 ? 0 : v; });
const contribR = lcg(99);
const CONTRIB = Array.from({ length: 20 * 7 }, () => { const v = contribR(); return { v: v < 0.3 ? 0 : v, o: contribR() }; });

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1920px;height:1080px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:52px;display:flex;justify-content:space-between;font-size:24px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:102px;height:3px;background:#14110d;transform-origin:left;}
.foot{position:absolute;left:74px;right:74px;bottom:46px;display:flex;justify-content:space-between;font-size:22px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

/* intro */
.intro{position:absolute;left:90px;top:330px;will-change:opacity;}
.intro .t{font-size:150px;font-weight:800;letter-spacing:-.045em;color:#14110d;line-height:.96;}
.intro .s{margin-top:38px;font-size:30px;letter-spacing:.1em;color:#14110d;font-weight:600;}
.intro .s b{color:${INK};}

/* caption column */
.kick{position:absolute;left:92px;top:210px;font-size:27px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:88px;top:258px;width:760px;font-size:92px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.items{position:absolute;left:92px;top:560px;font-size:25px;line-height:2.05;color:#14110d;font-weight:600;letter-spacing:.05em;}
.items div{will-change:opacity,transform;}
.items b{color:${INK};font-weight:700;}

/* beats */
.beat{position:absolute;inset:0;opacity:0;will-change:opacity;}

/* device shells */
.iphone{position:absolute;left:1258px;top:148px;width:378px;height:788px;background:#0b0b0d;border-radius:62px;padding:11px;box-shadow:30px 38px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.28);will-change:transform,opacity;}
.iphone .scr{position:relative;width:100%;height:100%;background:#050507;border-radius:52px;overflow:hidden;}
.island{position:absolute;left:50%;top:13px;transform:translateX(-50%);width:104px;height:30px;border-radius:16px;background:#000;z-index:9;}
.ipad{position:absolute;left:952px;top:184px;width:902px;height:668px;background:#0b0b0d;border-radius:44px;padding:21px;box-shadow:30px 38px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.28);will-change:transform,opacity;}
.ipad .scr{position:relative;width:100%;height:100%;background:#000;border-radius:24px;overflow:hidden;padding:22px;}
.mac{position:absolute;left:836px;top:196px;width:1014px;height:652px;border-radius:18px;overflow:hidden;box-shadow:30px 38px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.28);will-change:transform,opacity;background:#000;}
.mac .bar{height:44px;background:#1c1c1e;display:flex;align-items:center;padding:0 18px;gap:8px;}
.mac .bar i{width:13px;height:13px;border-radius:50%;}
.mac .bar .ttl{flex:1;text-align:center;font-size:15px;color:rgba(255,255,255,.5);font-weight:600;margin-right:55px;}
.mac .scr{position:relative;height:608px;background:#000;padding:26px 30px;}

/* app chrome bits */
.appbar{display:flex;align-items:center;gap:8px;padding:58px 18px 10px;}
.appbar .chip{font-size:13px;font-weight:700;padding:7px 14px;border-radius:100px;background:#1c1c1e;color:rgba(255,255,255,.85);}
.appbar .chip.on{background:${INK};color:#fff;}
.panel{position:absolute;left:18px;right:18px;top:112px;bottom:14px;will-change:opacity,transform;}
.cap13{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;}
.money{font-size:36px;font-weight:800;color:#fff;letter-spacing:-.02em;margin-top:3px;display:flex;align-items:center;gap:12px;}
.pill{font-size:14px;font-weight:750;color:#04270f;background:${GREEN};padding:4px 11px;border-radius:100px;will-change:transform,opacity;}
.mover{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:8px;}
.card{background:#111113;border-radius:20px;padding:14px;margin-top:14px;}
.card .t{font-size:15px;font-weight:700;color:#fff;}
.card .s{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
.tm{position:relative;margin-top:10px;}
.tmcell{position:absolute;border-radius:12px;padding:10px 12px;will-change:transform,opacity;}
.tmcell .sym{font-size:15px;font-weight:800;color:#fff;}
.tmcell .val{font-size:12px;font-weight:650;color:rgba(255,255,255,.72);margin-top:1px;}
.conc{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:10px;}

/* flow band + risk strip */
.flowlbl{display:flex;justify-content:space-between;font-size:12px;font-weight:700;margin-top:8px;color:rgba(235,235,245,.6);}
.risktrack{position:relative;height:8px;border-radius:4px;background:#26262a;margin:52px 8px 46px;}
.riskcap{position:absolute;right:0;top:0;width:34px;height:8px;border-radius:4px;background:${RED};opacity:.85;}
.riskdot{position:absolute;top:-5px;width:18px;height:18px;border-radius:50%;box-shadow:0 0 0 4px #111113;will-change:transform,opacity;}
.risklbl{position:absolute;font-size:12px;font-weight:700;color:rgba(255,255,255,.78);white-space:nowrap;will-change:opacity;}

/* iPad room cards */
.roomgrid{display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;gap:16px;height:100%;}
.rcard{background:#111113;border-radius:20px;padding:18px;position:relative;will-change:transform,opacity;}
.rcard .t{font-size:17px;font-weight:750;color:#fff;}
.rcard .s{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
.hm{position:absolute;left:18px;top:74px;display:grid;grid-template-columns:repeat(22,13px);grid-auto-rows:13px;gap:4px;}
.hm i{border-radius:3px;background:${BLUE};will-change:opacity;}
.hm i.z{background:#1d1d20;}
.topicwrap{position:absolute;left:18px;top:74px;width:308px;height:214px;}
.topiccell{position:absolute;border-radius:12px;display:flex;align-items:flex-end;padding:10px;font-weight:750;color:#fff;background:#0f2f57;will-change:transform,opacity;}
.leadrow{display:flex;align-items:center;gap:12px;margin-top:17px;}
.leadrow .av{width:34px;height:34px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:800;color:#fff;}
.leadrow .nm{width:78px;font-size:14px;font-weight:700;color:#fff;}
.leadrow .bar{height:14px;border-radius:7px;background:${VIOLET};transform-origin:left;will-change:transform;}
.leadrow .ct{font-size:13px;font-weight:700;color:rgba(235,235,245,.49);margin-left:auto;}
.cg{position:absolute;left:18px;top:74px;display:grid;grid-template-columns:repeat(20,13px);grid-auto-rows:13px;gap:4px;}
.cg i{border-radius:3px;background:${GREEN};will-change:opacity;}
.cg i.z{background:#1d1d20;}

/* Mac brief */
.briefL{position:absolute;left:30px;top:26px;width:520px;}
.briefR{position:absolute;right:30px;top:26px;width:370px;}
.eyebrow{font-size:15px;font-weight:700;color:${BLUE};letter-spacing:.02em;}
.bignum{font-size:74px;font-weight:800;color:#fff;letter-spacing:-.03em;margin-top:6px;display:flex;align-items:baseline;gap:18px;}
.bigsub{font-size:17px;color:rgba(235,235,245,.6);font-weight:600;margin-top:10px;width:430px;line-height:1.45;}
.bars{display:flex;align-items:flex-end;gap:10px;height:150px;margin-top:44px;}
.bars i{width:24px;border-radius:12px;background:${INK};opacity:.45;transform-origin:bottom;will-change:transform;}
.bars i:last-child{opacity:1;}
.barslbl{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:12px;}
.mcard{background:#111113;border-radius:20px;padding:18px;margin-bottom:16px;}
.mcard .t{font-size:15px;font-weight:750;color:#fff;margin-bottom:4px;}
.mrow{display:flex;align-items:center;gap:12px;padding:9px 0;will-change:opacity,transform;}
.mrow .sym{width:52px;font-size:15px;font-weight:800;color:#fff;}
.mrow .spark{flex:1;height:22px;}
.mrow .chg{font-size:14px;font-weight:750;}
.ringwrap{display:flex;gap:16px;align-items:center;}
.ringtxt .n{font-size:26px;font-weight:800;color:#fff;}
.ringtxt .l{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:3px;width:170px;line-height:1.4;}

/* delight composite */
.mini{position:absolute;border-radius:30px;background:#0b0b0d;box-shadow:22px 28px 0 rgba(20,17,13,.12), 0 24px 54px rgba(20,17,13,.26);will-change:transform,opacity;}
.mini .scr{position:absolute;inset:9px;background:#050507;border-radius:22px;overflow:hidden;padding:14px;}
.drop{position:absolute;border-radius:50%;will-change:transform,opacity;z-index:40;}
.cointile{position:absolute;width:84px;height:84px;border-radius:20px;display:flex;align-items:center;justify-content:center;box-shadow:0 16px 34px rgba(20,17,13,.3);will-change:transform,opacity;perspective:600px;}
.minitm{position:absolute;border-radius:8px;}
.minibar{position:absolute;bottom:14px;border-radius:6px;background:${INK};}

/* outro */
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;opacity:0;will-change:opacity;background:#EEEAE1;}
.outro .b{font-size:170px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;margin-top:34px;}
.outro .u{font-size:30px;letter-spacing:.1em;color:#14110d;margin-top:30px;font-weight:600;}
.outro .u b{color:${INK};}
.outro svg{will-change:transform,opacity;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>THE VISUALIZATIONS</span></div>
  <div class="rule" id="rule"></div>
  <div class="foot mono"><span>casberi.app</span><span>14 READS · IPHONE · IPAD · MAC</span></div>

  <div class="intro" id="intro">
    <div class="t">Your things,<br>drawn.</div>
    <div class="s mono">EVERY CHART THE APP PAINTS — <b>IN 30 SECONDS</b></div>
  </div>

  <!-- B1: iPhone, the Wallet room -->
  <div class="beat" id="b0">
    <div class="iphone" id="phone"><div class="scr">
      <div class="island"></div>
      <div class="appbar"><span class="chip on">Wallet</span><span class="chip">All</span><span class="chip">Photos</span><span class="chip">Farcaster</span></div>
      <div class="panel" id="pA">
        <div class="cap13">Across your wallets</div>
        <div class="money"><span id="balnum">$48,210</span><span class="pill" id="balpill">+2.6%</span></div>
        <svg id="sparkline" width="320" height="64" viewBox="0 0 320 64" style="margin-top:10px">
          <path id="sparkpath" d="M2,50 C34,46 52,54 76,44 C104,32 118,40 142,34 C170,27 186,36 210,24 C238,10 258,20 284,14 L318,8" fill="none" stroke="${GREEN}" stroke-width="2.5" stroke-linecap="round"/>
        </svg>
        <div class="mover" id="moverline">Mostly ETH · +$310</div>
        <div class="card"><div class="t">Holdings</div>
          <div class="tm" style="height:284px">${TREEMAP.map(([x, y, w, h, s, v, c], k) =>
            `<div class="tmcell" data-k="${k}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;background:${c}"><div class="sym">${s}</div><div class="val">${v}</div></div>`).join('')}
          </div>
          <div class="conc" id="concline">ETH is 54% of the book</div>
        </div>
      </div>
      <div class="panel" id="pB" style="opacity:0">
        <div class="card" style="margin-top:2px"><div class="t">Where the money went</div><div class="s">7 days · every lane a real transfer</div>
          <svg id="flowsvg" width="316" height="196" viewBox="0 0 316 196" style="margin-top:8px">
            <defs>
              <clipPath id="clipL"><rect id="clipLrect" x="158" y="0" width="0" height="196"/></clipPath>
              <clipPath id="clipR"><rect id="clipRrect" x="158" y="0" width="0" height="196"/></clipPath>
            </defs>
            <g clip-path="url(#clipL)">
              <rect x="0" y="22" width="64" height="58" rx="0" fill="${GREEN}"/>
              <polygon points="64,22 148,64 148,86 64,80" fill="${GREEN}" opacity=".8"/>
              <rect x="0" y="110" width="64" height="26" fill="${GREEN}" opacity=".85"/>
              <polygon points="64,110 148,90 148,102 64,136" fill="${GREEN}" opacity=".6"/>
            </g>
            <g clip-path="url(#clipR)">
              <rect x="252" y="34" width="64" height="30" fill="#3a3a3e"/>
              <polygon points="168,64 252,34 252,64 168,78" fill="#3a3a3e" opacity=".8"/>
              <rect x="252" y="86" width="64" height="44" fill="#3a3a3e"/>
              <polygon points="168,82 252,86 252,130 168,104" fill="#3a3a3e" opacity=".6"/>
            </g>
            <rect x="150" y="52" width="16" height="66" rx="8" fill="${BLUE}" id="flowspine"/>
          </svg>
          <div class="flowlbl"><span style="color:${GREEN}">Coinbase · Peer &nbsp;$3,000 in</span><span>out $1,210 · Gnosis Pay · Aave</span></div>
        </div>
        <div class="card"><div class="t">Distance to liquidation</div><div class="s">every leveraged position, one axis</div>
          <div class="risktrack"><span class="riskcap"></span>
            <span class="riskdot" data-k="0" style="left:16%;background:${GREEN}"></span>
            <span class="riskdot" data-k="1" style="left:44%;background:${BLUE}"></span>
            <span class="riskdot" data-k="2" style="left:76%;background:${AMBER}"></span>
            <span class="risklbl" data-k="0" style="left:9%;top:-34px">Aave · hf 2.1</span>
            <span class="risklbl" data-k="1" style="left:36%;top:20px">Morpho · hf 1.6</span>
            <span class="risklbl" data-k="2" style="left:66%;top:-34px">Hyperliquid · 15%</span>
          </div>
        </div>
      </div>
    </div></div>
  </div>

  <!-- B2: iPad, the room leads -->
  <div class="beat" id="b1">
    <div class="ipad" id="pad"><div class="scr"><div class="roomgrid">
      <div class="rcard" data-k="0"><div class="t">Your capture year</div><div class="s">1,284 things · busiest in March</div>
        <div class="hm">${HEAT.map(v => `<i${v === 0 ? ' class="z"' : ''} data-v="${v.toFixed(2)}"></i>`).join('')}</div>
      </div>
      <div class="rcard" data-k="1"><div class="t">What your images say</div><div class="s">every label appears in a screenshot</div>
        <div class="topicwrap" style="width:380px;height:212px">${TOPICS.map(([x, y, w, h, t, n], k) =>
          `<div class="topiccell" data-k="${k}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;font-size:${k === 0 ? 21 : 15}px;background:rgba(10,132,255,${(0.16 + n * 0.028).toFixed(2)})">${t}</div>`).join('')}
        </div>
      </div>
      <div class="rcard" data-k="2"><div class="t">Who you save most</div><div class="s">names, never a tally</div>
        ${LEADERS.map(([n, c, hue], k) =>
          `<div class="leadrow" data-k="${k}"><span class="av" style="background:${hue}">${n[0].toUpperCase()}</span><span class="nm">${n}</span><span class="bar" data-w="${(c / 34 * 150) | 0}" style="width:${(c / 34 * 150) | 0}px"></span><span class="ct">${c}</span></div>`).join('')}
      </div>
      <div class="rcard" data-k="3"><div class="t">GitHub · contributions</div><div class="s">the year, cell by cell</div>
        <div class="cg">${CONTRIB.map(d => `<i${d.v === 0 ? ' class="z"' : ''} data-v="${d.v.toFixed(2)}" data-o="${d.o.toFixed(2)}"></i>`).join('')}</div>
      </div>
    </div></div></div>
  </div>

  <!-- B3: Mac, the Today brief -->
  <div class="beat" id="b2">
    <div class="mac" id="macwin">
      <div class="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i><span class="ttl">Casberi</span></div>
      <div class="scr">
        <div class="briefL">
          <div class="eyebrow">Your Tuesday</div>
          <div class="bignum"><span id="heronum">$0</span><span class="pill" id="heropill">+$1,204 · 2.6%</span></div>
          <div class="bigsub" id="herosub">ETH did the lifting — seven days running. 14 new things while you were away.</div>
          <div class="bars" id="hourbars">${HOURS.map(h => `<i style="height:${h}%"></i>`).join('')}</div>
          <div class="barslbl" id="hourlbl">Your day, hour by hour — capsules, never axes</div>
        </div>
        <div class="briefR">
          <div class="mcard"><div class="t">Movers</div>
            ${MOVERS.map(([s, c, up], k) =>
              `<div class="mrow" data-k="${k}"><span class="sym">${s}</span><svg class="spark" viewBox="0 0 120 22"><path d="${up ? 'M2,18 C30,16 50,12 70,10 C90,8 105,6 118,3' : 'M2,5 C30,7 50,10 70,12 C90,15 105,16 118,19'}" fill="none" stroke="${up ? GREEN : RED}" stroke-width="2" stroke-linecap="round"/></svg><span class="chg" style="color:${up ? GREEN : RED}">${c}</span></div>`).join('')}
          </div>
          <div class="mcard"><div class="t">signed_up</div>
            <div class="ringwrap">
              <svg width="110" height="110" viewBox="0 0 110 110">
                <circle cx="55" cy="55" r="46" fill="none" stroke="#26262a" stroke-width="9"/>
                <circle id="ringarc" cx="55" cy="55" r="46" fill="none" stroke="${INK}" stroke-width="9" stroke-linecap="round" transform="rotate(-90 55 55)" stroke-dasharray="289" stroke-dashoffset="289"/>
                <polyline id="ringcurve" points="36,66 44,62 50,64 58,56 66,58 74,50" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2" stroke-linecap="round"/>
              </svg>
              <div class="ringtxt"><div class="n" id="ringnum">0</div><div class="l">of the next 100 — its own week inside the ring</div></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- B4: delight over all three -->
  <div class="beat" id="b3">
    <div class="mini" id="miniPad" style="left:940px;top:270px;width:430px;height:320px;">
      <div class="scr">
        <div style="font-size:12px;font-weight:750;color:#fff">Your capture year</div>
        <div style="position:absolute;left:14px;top:40px;display:grid;grid-template-columns:repeat(22,12px);grid-auto-rows:12px;gap:3px">${
          HEAT.map(v => `<i style="border-radius:3px;background:${v === 0 ? '#1d1d20' : `rgba(10,132,255,${(0.18 + v * 0.75).toFixed(2)})`}"></i>`).join('')}</div>
      </div>
    </div>
    <div class="mini" id="miniMac" style="left:1400px;top:250px;width:440px;height:300px;border-radius:14px;">
      <div class="scr" style="border-radius:8px;">
        <div style="font-size:11px;font-weight:700;color:${BLUE}">Your Tuesday</div>
        <div style="font-size:30px;font-weight:800;color:#fff;margin-top:2px">$48,210 <span style="font-size:11px;font-weight:750;color:#04270f;background:${GREEN};padding:2px 8px;border-radius:100px;vertical-align:middle">+2.6%</span></div>
        ${HOURS.map((h, k) => `<span class="minibar" style="left:${16 + k * 29}px;width:17px;height:${h * 1.1}px;opacity:${k === HOURS.length - 1 ? 1 : 0.45}"></span>`).join('')}
      </div>
    </div>
    <div class="mini" id="miniPhone" style="left:1140px;top:330px;width:230px;height:470px;border-radius:38px;z-index:20;">
      <div class="scr" style="border-radius:30px;">
        <div style="font-size:11px;font-weight:600;color:rgba(235,235,245,.49)">Across your wallets</div>
        <div style="font-size:24px;font-weight:800;color:#fff">$48,210</div>
        ${TREEMAP.map(([x, y, w, h, s, v, c]) =>
          `<span class="minitm" style="left:${14 + x * 0.63}px;top:${86 + y * 0.63}px;width:${w * 0.63}px;height:${h * 0.63}px;background:${c}"></span>`).join('')}
        <div style="position:absolute;bottom:14px;left:14px;font-size:10px;font-weight:600;color:rgba(235,235,245,.49)">ETH is 54% of the book</div>
      </div>
    </div>
    ${[0, 1, 2].map(k => {
      const tiles = [['#000', berrySVG(46)], [GREEN, '<div style="width:34px;height:34px;border-radius:50%;background:#fff;opacity:.92"></div>'], [VIOLET, '<div style="width:32px;height:32px;border-radius:9px;background:#fff;opacity:.92"></div>']];
      return `<div class="cointile" data-k="${k}" style="left:${370 + k * 118}px;top:700px;background:${tiles[k][0]}"><div class="coininner" style="display:flex;align-items:center;justify-content:center;width:100%;height:100%;will-change:transform">${tiles[k][1]}</div></div>`;
    }).join('')}
    ${DROPS.map((d, k) => `<span class="drop" data-k="${k}" style="width:${(d.r * 2) | 0}px;height:${(d.r * 2) | 0}px;background:${d.c};left:${d.x | 0}px;top:0"></span>`).join('')}
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="items mono" id="items"></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro">${berrySVG(150, 'omark')}<div class="b">Casberi</div><div class="u mono">EVERY READ, ON DEVICE — <b>casberi.app</b></div></div>
</div>
<script>
var clamp01=function(v){return Math.max(0,Math.min(1,v));};
var easeOut=function(p){return 1-Math.pow(1-p,3);};
var back=function(p){var c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
var INTRO=${INTRO},STARTS=${JSON.stringify(STARTS)},OUT_AT=${OUT_AT},N=4;
var D=${JSON.stringify(BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent, items: b.items })))};
var DROPS=${JSON.stringify(DROPS.map(d => ({ delay: +d.delay.toFixed(3), dur: +d.dur.toFixed(3), drift: +d.drift.toFixed(1) })))};
window.TOTAL=${TOTAL};
var beats=[document.getElementById('b0'),document.getElementById('b1'),document.getElementById('b2'),document.getElementById('b3')];
var sparkLen=null;
function fmt(n){return '$'+Math.round(n).toLocaleString('en-US');}

window.seek=function(t){
  var active=0;for(var i=0;i<N;i++){if(t>=STARTS[i])active=i;}
  if(t<INTRO)active=-1;
  var acc=active>=0?D[active].accent:'#14110d';
  // intro
  var io=document.getElementById('intro');
  io.style.opacity=(t<INTRO)?clamp01(t/0.35):0;
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  // wipes at each beat boundary + outro
  var wipeX=200,coverAcc=acc;
  var bounds=[];for(var k2=0;k2<N;k2++)bounds.push({t:STARTS[k2],c:D[k2].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(var bi=0;bi<bounds.length;bi++){var b=bounds[bi];var p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  var wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  // captions
  var ki=document.getElementById('kick'),he=document.getElementById('head'),it=document.getElementById('items');
  if(active>=0&&t<OUT_AT+0.3){
    var bs=STARTS[active],local=t-bs;
    ki.textContent=D[active].kick;ki.style.color=acc;
    var kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
    he.innerHTML=D[active].head.replace(/\\n/g,'<br>');
    var hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*70)+'px)';
    var rows='';for(var r=0;r<D[active].items.length;r++){var lbl=D[active].items[r].split(' \\u2014 ');rows+='<div data-r="'+r+'"><b>'+D[active].items[r].slice(0,2)+'</b>'+D[active].items[r].slice(2)+'</div>';}
    it.innerHTML=rows;
    var itemAt=[[1.0,1.5,3.9,5.2],[0.9,1.9,2.9,3.9],[0.9,2.2,3.2,4.2],[0.7,1.7]][active];
    var rowsEls=it.children;
    for(var r2=0;r2<rowsEls.length;r2++){var rp=clamp01((local-itemAt[r2])/0.4);rowsEls[r2].style.opacity=rp;rowsEls[r2].style.transform='translateX('+((1-easeOut(rp))*-24)+'px)';}
    var fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
    ki.style.opacity=Math.min(parseFloat(ki.style.opacity)||1,fo);he.style.opacity=Math.min(parseFloat(he.style.opacity)||1,fo);it.style.opacity=fo;
  } else {ki.style.opacity=0;he.style.opacity=0;it.style.opacity=0;}
  // beats visibility
  for(var bi2=0;bi2<N;bi2++){
    var el=beats[bi2],bs2=STARTS[bi2],be=STARTS[bi2+1]||OUT_AT;
    var op=(t>=bs2-0.02&&t<be)?clamp01((t-bs2)/0.15):0;
    if(t>=be)op=0;if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));
    el.style.opacity=op;el.style.pointerEvents='none';
    if(op>0)animate(bi2,t-bs2,t);
  }
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
  var om=document.querySelector('.omark');if(om){var omp=clamp01((t-(OUT_AT+0.35))/0.6);om.style.transform='scale('+(0.6+0.4*back(omp))+')';om.style.opacity=omp;}
};

function animate(i,local,t){
  if(i===0){
    var ph=document.getElementById('phone');
    var pin=clamp01((local-0.05)/0.6);
    ph.style.opacity=pin;ph.style.transform='translateY('+((1-back(pin))*120)+'px) rotate('+((1-easeOut(pin))*-2)+'deg)';
    // panel A: balance + spark + treemap
    var pA=document.getElementById('pA'),pB=document.getElementById('pB');
    var swap=clamp01((local-3.75)/0.45);
    pA.style.opacity=1-swap;pA.style.transform='translateY('+(-swap*40)+'px)';
    pB.style.opacity=swap;pB.style.transform='translateY('+((1-swap)*50)+'px)';
    var np=clamp01((local-0.5)/0.4);
    document.getElementById('balnum').style.opacity=np;
    var pp=clamp01((local-0.85)/0.35);
    var pillEl=document.getElementById('balpill');pillEl.style.opacity=pp;pillEl.style.transform='scale('+(0.5+0.5*back(pp))+')';
    var sp=document.getElementById('sparkpath');
    if(sparkLen===null)sparkLen=sp.getTotalLength();
    var spp=easeOut(clamp01((local-1.35)/1.1));
    sp.style.strokeDasharray=sparkLen;sp.style.strokeDashoffset=sparkLen*(1-spp);
    document.getElementById('moverline').style.opacity=clamp01((local-2.3)/0.4);
    var cells=document.querySelectorAll('#pA .tmcell');
    for(var k=0;k<cells.length;k++){var cp=clamp01((local-0.9-k*0.14)/0.45);cells[k].style.opacity=cp;cells[k].style.transform='scale('+(0.82+0.18*back(cp))+')';}
    document.getElementById('concline').style.opacity=clamp01((local-2.4)/0.4);
    // panel B: flow band reveal + risk dots
    var fl=easeOut(clamp01((local-4.15)/0.9));
    var lr=document.getElementById('clipLrect');lr.setAttribute('x',158-158*fl);lr.setAttribute('width',158*fl);
    var fr=easeOut(clamp01((local-4.5)/0.9));
    document.getElementById('clipRrect').setAttribute('width',158*fr);
    document.getElementById('flowspine').style.opacity=clamp01((local-4.0)/0.3);
    document.querySelector('#pB .flowlbl').style.opacity=clamp01((local-5.0)/0.4);
    var dots=document.querySelectorAll('.riskdot');
    for(var k3=0;k3<dots.length;k3++){var dp=clamp01((local-5.25-k3*0.22)/0.4);dots[k3].style.opacity=dp;dots[k3].style.transform='translateY('+((1-back(dp))*-26)+'px)';}
    var lbls=document.querySelectorAll('.risklbl');
    for(var k4=0;k4<lbls.length;k4++){lbls[k4].style.opacity=clamp01((local-5.45-k4*0.22)/0.35);}
  } else if(i===1){
    var pad=document.getElementById('pad');
    var pin2=clamp01((local-0.05)/0.6);
    pad.style.opacity=pin2;pad.style.transform='translateY('+((1-back(pin2))*120)+'px)';
    var rcards=document.querySelectorAll('#b1 .rcard');
    for(var c=0;c<rcards.length;c++){var rp2=clamp01((local-0.4-c*0.55)/0.5);rcards[c].style.opacity=rp2;rcards[c].style.transform='translateY('+((1-back(rp2))*46)+'px)';}
    // heatmap column sweep
    var hm=document.querySelectorAll('#b1 .hm i');
    for(var h=0;h<hm.length;h++){var col=h%22;var v=parseFloat(hm[h].getAttribute('data-v')||'0');
      var ap=clamp01((local-0.9-col*0.055)/0.3);
      hm[h].style.opacity=hm[h].classList.contains('z')?ap*0.8:ap*(0.18+v*0.78);}
    // topic cells pop
    var tc=document.querySelectorAll('.topiccell');
    for(var k5=0;k5<tc.length;k5++){var tp=clamp01((local-1.95-k5*0.16)/0.4);tc[k5].style.opacity=tp;tc[k5].style.transform='scale('+(0.82+0.18*back(tp))+')';}
    // leaderboard bars
    var lb=document.querySelectorAll('.leadrow');
    for(var k6=0;k6<lb.length;k6++){var lp2=clamp01((local-2.95-k6*0.2)/0.55);lb[k6].style.opacity=Math.min(1,lp2*3);
      lb[k6].querySelector('.bar').style.transform='scaleX('+easeOut(lp2)+')';
      lb[k6].querySelector('.ct').style.opacity=clamp01((lp2-0.7)/0.3);}
    // contributions: hash-ordered fill
    var cg=document.querySelectorAll('#b1 .cg i');
    for(var g=0;g<cg.length;g++){var o=parseFloat(cg[g].getAttribute('data-o')||'0');var v2=parseFloat(cg[g].getAttribute('data-v')||'0');
      var gp=clamp01((local-3.95-o*1.3)/0.25);
      cg[g].style.opacity=cg[g].classList.contains('z')?gp*0.8:gp*(0.2+v2*0.8);}
  } else if(i===2){
    var mac=document.getElementById('macwin');
    var pin3=clamp01((local-0.05)/0.6);
    mac.style.opacity=pin3;mac.style.transform='translateY('+((1-back(pin3))*110)+'px)';
    var cp2=easeOut(clamp01((local-0.5)/1.3));
    document.getElementById('heronum').textContent=fmt(48210*cp2);
    var hp=clamp01((local-1.85)/0.35);
    var hpill=document.getElementById('heropill');hpill.style.opacity=hp;hpill.style.transform='scale('+(0.5+0.5*back(hp))+')';
    document.getElementById('herosub').style.opacity=clamp01((local-2.1)/0.5);
    var bars=document.querySelectorAll('#hourbars i');
    for(var k7=0;k7<bars.length;k7++){var bp=clamp01((local-2.3-k7*0.09)/0.55);bars[k7].style.transform='scaleY('+back(bp)+')';}
    document.getElementById('hourlbl').style.opacity=clamp01((local-3.6)/0.4);
    var mrows=document.querySelectorAll('.mrow');
    for(var k8=0;k8<mrows.length;k8++){var mp=clamp01((local-3.25-k8*0.25)/0.45);mrows[k8].style.opacity=mp;mrows[k8].style.transform='translateX('+((1-easeOut(mp))*30)+'px)';}
    var rp3=easeOut(clamp01((local-4.25)/1.1));
    document.getElementById('ringarc').style.strokeDashoffset=289*(1-0.82*rp3);
    document.getElementById('ringnum').textContent=Math.round(82*rp3);
    var rc=document.getElementById('ringcurve');
    if(!rc.dataset.len)rc.dataset.len=rc.getTotalLength();
    var rcl=parseFloat(rc.dataset.len);var rcp=easeOut(clamp01((local-4.7)/0.8));
    rc.style.strokeDasharray=rcl;rc.style.strokeDashoffset=rcl*(1-rcp);
  } else if(i===3){
    var minis=[document.getElementById('miniPad'),document.getElementById('miniMac'),document.getElementById('miniPhone')];
    for(var k9=0;k9<3;k9++){var np2=clamp01((local-0.1-k9*0.16)/0.55);minis[k9].style.opacity=np2;minis[k9].style.transform='translateY('+((1-back(np2))*90)+'px)';}
    // berry rain — deterministic shower, accel like gravity, fade at the end
    var drops=document.querySelectorAll('.drop');
    for(var d2=0;d2<drops.length;d2++){var dd=DROPS[d2];var pp2=(local-0.7-dd.delay)/dd.dur;
      if(pp2<0||pp2>1){drops[d2].style.opacity=0;continue;}
      var yy=150+Math.pow(pp2,1.55)*880;
      drops[d2].style.transform='translate('+(dd.drift*pp2)+'px,'+yy+'px)';
      drops[d2].style.opacity=Math.min(clamp01(pp2/0.12),1-clamp01((pp2-0.82)/0.18));}
    // coin flips — one forward X turn each, staggered
    var coins=document.querySelectorAll('.cointile');
    for(var c2=0;c2<coins.length;c2++){var ct=clamp01((local-0.5-c2*0.5)/0.7);
      coins[c2].style.opacity=clamp01((local-0.2-c2*0.12)/0.3);
      coins[c2].querySelector('.coininner').style.transform='rotateX('+(360*easeOut(ct))+'deg)';}
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname, 'clip-viz-reel.html'), html);
console.log('wrote clip-viz-reel.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
