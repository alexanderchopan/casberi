// THE VISUALIZATIONS reel — v3, ruled 2026-08-04: NO editorial chrome (v1's
// paper mast/kicker/numbered list died in review — user: "i don't want the
// editorial, i just want a black background and then the shells in it"),
// social/media/mail rooms added, a rapid-fire beat for the wider inventory,
// and the delight close is berry rain THEN source chips flipping (the chip
// strip is where CoinFlip actually lives — a chip flips when you switch
// sources).
//   B1 iPhone  — the Wallet room: holdings treemap (GenTagMap), balance
//                sparkline (TokenChartPlot), flow band (in green, out
//                neutral slab — never red), risk strip (only the far END
//                tinted, labels alternating).
//   B2 iPhone+iPad — a SOCIAL feed populating (PostCard anatomy: face, name,
//                the post's own words, context tag, engagement) beside the
//                MEDIA room (cover shelf + music rows + video thumbs).
//   B3 Mac     — MAIL rows landing beside the Today brief (money hero, hour
//                bars — capsules, no axes — and the PostHog metric ring).
//   B4 iPad    — the room leads: capture-year heatmap, topic map,
//                leaderboard, contributions.
//   B5 Mac     — nine more reads, rapid-fire: "In protocols" composition,
//                the veAERO melt, approval exposure, address connections
//                (equal-weight ribbons by ruling), prediction odds, LP
//                range, Safe 2-of-3, distribution, the Cloudflare runway.
//   B6 delight — BerryRain (icon berry blues, seeded shower) first, then the
//                source chip strip flipping chip to chip (one forward X-axis
//                turn each, the active state following); CasberiMark outro.
// Colors are the app's own tokens: page #000, sheet #111113, accent ink
// #1673e6, link blue #0a84ff, green #3fb950. No hairlines — depth by tone.
// Deterministic (window.seek/window.TOTAL) -> design/launch-video/render-viz.sh
const fs = require('fs'), path = require('path');

const BLUE = '#0a84ff', INK = '#1673e6', GREEN = '#3fb950', RED = '#ff453a',
      AMBER = '#ff9f0a', VIOLET = '#8c40c7';

const INTRO = 1.0, DUR = [5.2, 5.2, 5.0, 4.2, 4.2, 3.6];
const STARTS = DUR.reduce((a, d) => (a.push(a[a.length - 1] + d), a), [INTRO]);
const OUT_AT = STARTS[6], TOTAL = OUT_AT + 1.2;   // 29.6s

const MARK = [
  [0.654, 0.812, '#cee6ff'], [0.812, 0.469, '#b1d8ff'], [0.337, 0.794, '#b1d8ff'],
  [0.513, 0.487, '#91c8ff'], [0.188, 0.487, '#6cb5ff'], [0.654, 0.188, '#6cb5ff'],
  [0.329, 0.188, '#0a84ff'],
];
const berrySVG = (s, cls) => `<svg class="${cls || ''}" width="${s}" height="${s}" viewBox="0 0 100 100">${
  MARK.map(([x, y, c]) => `<circle cx="${x * 100}" cy="${y * 100}" r="18.8" fill="${c}"/>`).join('')}</svg>`;
const HEART = '<svg width="13" height="12" viewBox="0 0 24 22"><path d="M12 21C5 15 1 11 1 6.5 1 3.4 3.4 1 6.5 1 8.6 1 10.6 2 12 3.8 13.4 2 15.4 1 17.5 1 20.6 1 23 3.4 23 6.5 23 11 19 15 12 21z" fill="rgba(235,235,245,.45)"/></svg>';
const RECAST = '<svg width="14" height="12" viewBox="0 0 24 20"><path d="M6 6h10l-2.5-2.5L15 2l5 5-5 5-1.5-1.5L16 8H8v4H6zM18 14H8l2.5 2.5L9 18l-5-5 5-5 1.5 1.5L8 12h10v-4h2z" fill="rgba(235,235,245,.45)"/></svg>';
const PLAY = '<svg width="22" height="22" viewBox="0 0 24 24"><path d="M8 5l12 7-12 7z" fill="rgba(255,255,255,.9)"/></svg>';

// ---- in-screen data (demo register, same as the other clips) ---------------
const TREEMAP = [
  [0, 0, 190, 178, 'ETH',  '$26,180', '#3a6df0'],
  [194, 0, 126, 86, 'SOL',  '$7,940',  '#8f5bd9'],
  [194, 90, 126, 88, 'USDC', '$6,120', '#2775ca'],
  [0, 182, 96, 98, 'BTC',  '$4,310',  '#c8842a'],
  [100, 182, 92, 98, 'AERO', '$2,140', '#2f66b5'],
  [196, 182, 124, 98, 'HYPE', '$1,520', '#2e9e8f'],
];
const POSTS = [
  ['#8f5bd9', 'D', 'dwr', '@dwr · 2h', '/design', VIOLET,
   'the best interfaces disappear — you notice the thing, not the chrome', '128', '24', 0],
  ['#3a6df0', 'M', 'maya', '@maya · 4h', 'Liked', BLUE,
   'sunset test shots from the new lens', '64', '9', 1],
  ['#2e9e8f', 'L', 'linda', '@linda · 6h', 'Mentions you', BLUE,
   '@you this is exactly the treemap idea we talked about', '12', '2', 0],
];
const COVERS = [
  ['Night Drive', 'linear-gradient(140deg,#8f5bd9,#2c1b4e)'],
  ['Glasshouse', 'linear-gradient(140deg,#2e9e8f,#0d3330)'],
  ['Coastline', 'linear-gradient(140deg,#3a6df0,#12224a)'],
  ['Low Sun', 'linear-gradient(140deg,#c8842a,#4a2c08)'],
  ['Attic Tapes', 'linear-gradient(140deg,#d94f70,#4a1622)'],
];
const SONGS = [['Night Drive', 'Mara Vela', '3:41', '#8f5bd9'], ['Glasshouse', 'The Verdant', '4:12', '#2e9e8f'], ['Coastline', 'Ivo Ray', '2:58', '#3a6df0']];
const VIDEOS = [['How the pros sharpen film scans', '12:04'], ['Tokyo on 35mm', '8:51'], ['Build log: the desk', '21:17']];
const MAIL = [
  ['Ada Lin', 'Re: dinner on Friday', 'perfect — see you at 7, bringing the', '9:41', 1],
  ['Stripe', 'Your February payout', '$1,204.00 was sent to your bank acco', '8:26', 1],
  ['GitHub', 'casberi: 2 new reviews', 'alexander pushed 3 commits to main —', '7:58', 0],
  ['Linear', 'CAS-212 moved to In Progress', 'Treemap cells should stage in — assig', 'Yesterday', 0],
  ['Sofia Reyes', 'photos from the weekend', 'finally pulled these off the camera,', 'Yesterday', 1],
];
const TOPICS = [
  [0, 0, 214, 118, 'figma', 22], [218, 0, 162, 118, 'recipes', 14],
  [0, 122, 148, 90, 'tokyo', 11], [152, 122, 136, 90, 'github.com', 9],
  [292, 122, 88, 90, 'invoice', 7],
];
const LEADERS = [['maya', 34, '#8f5bd9'], ['dwr', 28, '#3a6df0'], ['jesse', 19, '#2e9e8f'], ['kartik', 12, '#c8842a']];
const HOURS = [12, 20, 32, 26, 44, 58, 40, 66, 84, 60, 92, 74, 50, 34];
const CHIPS = ['All', 'Wallet', 'Photos', 'Farcaster', 'Spotify'];
const lcg = seed => () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const rainR = lcg(20260804);
const BERRIES = ['#0a84ff', '#3f9fff', '#0a84ff', '#1266c4'];
const DROPS = Array.from({ length: 34 }, (_, i) => ({
  x: 440 + rainR() * 1040, delay: rainR() * 1.5, dur: 1.0 + rainR() * 0.45,
  r: 5 + rainR() * 7, c: BERRIES[i % 4], drift: (rainR() - 0.5) * 40,
}));
const heatR = lcg(7);
const HEAT = Array.from({ length: 22 * 7 }, () => { const v = heatR(); return v < 0.22 ? 0 : v; });
const contribR = lcg(99);
const CONTRIB = Array.from({ length: 20 * 7 }, () => { const v = contribR(); return { v: v < 0.3 ? 0 : v, o: contribR() }; });

// B5 — nine more reads, one mini-card each. `grow` elements scaleX in with
// the card; `fadein` elements fade after.
const GRID9 = [
  ['In protocols', `<div class="pillrow">
     <span class="ppill" style="background:rgba(63,185,80,.16);color:${GREEN}">Deposited $9,420</span>
     <span class="ppill" style="background:rgba(10,132,255,.16);color:${BLUE}">Locked $2,140</span>
     <span class="ppill" style="background:rgba(255,255,255,.08);color:rgba(235,235,245,.6)">Owed $1,200</span></div>`],
  ['The melt · veAERO', `<div class="track"><div class="grow" style="width:100%;background:rgba(10,132,255,.25)"></div>
     <div class="grow" style="width:41%;background:${BLUE}"></div></div>
     <div class="gl fadein">5,342 votes left of 12,977 locked · ends 2028</div>`],
  ['Approval exposure', `<div class="exrow fadein"><span class="exs">USDC · $6,120 reachable</span><span class="exchip">Unlimited</span></div>
     <div class="exrow fadein"><span class="exs">ETH · $310 reachable</span><span class="exchip" style="background:rgba(255,255,255,.08);color:rgba(235,235,245,.6)">Capped</span></div>`],
  ['Connections', `<svg width="256" height="86" viewBox="0 0 256 86">
     <g class="fadein"><path d="M36,26 C90,26 150,18 216,18" stroke="rgba(235,235,245,.35)" stroke-width="3" fill="none"/>
     <path d="M36,26 C90,30 150,58 216,58" stroke="rgba(235,235,245,.35)" stroke-width="3" fill="none"/>
     <path d="M36,66 C96,66 150,60 216,58" stroke="rgba(235,235,245,.35)" stroke-width="3" fill="none"/></g>
     <circle cx="30" cy="26" r="9" fill="#55555c"/><circle cx="30" cy="66" r="9" fill="#55555c"/>
     <circle cx="224" cy="18" r="10" fill="#3a6df0"/><circle cx="224" cy="58" r="10" fill="#8f5bd9"/></svg>
     <div class="gl fadein" style="margin-top:2px">2 counterparties reach two of your wallets</div>`],
  ['Fed cuts by March?', `<div class="track" style="margin-top:14px"><div class="grow" style="width:62%;background:${BLUE}"></div></div>
     <div class="exrow fadein" style="margin-top:8px"><span class="gl">Kalshi · live book</span><span style="font-size:17px;font-weight:800;color:#fff">62%</span></div>`],
  ['LP range · ETH/USDC', `<div class="track" style="margin-top:14px"><div class="grow" style="left:22%;width:46%;background:rgba(10,132,255,.35)"></div></div>
     <span class="rdot fadein" style="left:calc(18px + 44%)"></span>
     <div class="gl fadein" style="margin-top:10px">in range — earning fees</div>`],
  ['Safe · 2 of 3', `<div style="display:flex;gap:14px;align-items:center;margin-top:6px">
     <svg width="62" height="62" viewBox="0 0 70 70">
       <circle cx="35" cy="35" r="28" fill="none" stroke="#26262a" stroke-width="8"/>
       <circle class="sarc" cx="35" cy="35" r="28" fill="none" stroke="${BLUE}" stroke-width="8" stroke-linecap="round" transform="rotate(-90 35 35)" stroke-dasharray="176" stroke-dashoffset="176"/>
     </svg><div class="gl" style="width:150px">2 signatures collected —<br><b style="color:#fff">yours is needed</b></div></div>`],
  ['What lands here', `<div class="track seg" style="margin-top:14px">
     <div class="grow" style="width:44%;background:${BLUE}"></div><div class="grow" style="left:45%;width:26%;background:${VIOLET}"></div>
     <div class="grow" style="left:72%;width:16%;background:#2e9e8f"></div><div class="grow" style="left:89%;width:11%;background:#c8842a"></div></div>
     <div class="gl fadein" style="margin-top:10px">links · posts · screenshots · notes</div>`],
  ['The runway', `<div class="track thin" style="margin-top:20px"><div class="grow" style="width:100%;background:#26262a"></div></div>
     <span class="rtick fadein" style="left:calc(18px + 12%)"></span><span class="rtick fadein" style="left:calc(18px + 46%)"></span><span class="rtick fadein" style="left:calc(18px + 82%)"></span>
     <div class="gl fadein" style="margin-top:12px">cert 12d · domain 44d · invoice 89d</div>`],
];

const iphoneShell = (id, x, y, inner) => `
  <div class="iphone" id="${id}" style="left:${x}px;top:${y}px"><div class="scr">
    <div class="island"></div>${inner}
  </div></div>`;
const macShell = (id, x, y, inner) => `
  <div class="mac" id="${id}" style="left:${x}px;top:${y}px">
    <div class="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i><span class="ttl">Casberi</span></div>
    <div class="scr">${inner}</div>
  </div>`;

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1920px;height:1080px;overflow:hidden;background:#000;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:radial-gradient(1300px 900px at 50% 44%, #121218, #000 70%);}
.beat{position:absolute;inset:0;opacity:0;will-change:opacity,transform;}
.iphone{position:absolute;width:378px;height:788px;background:#131318;border-radius:62px;padding:11px;box-shadow:0 0 0 1.5px rgba(255,255,255,.17), 0 40px 90px rgba(0,0,0,.85);will-change:transform,opacity;}
.iphone .scr{position:relative;width:100%;height:100%;background:#050507;border-radius:52px;overflow:hidden;}
.island{position:absolute;left:50%;top:13px;transform:translateX(-50%);width:104px;height:30px;border-radius:16px;background:#000;z-index:9;}
.ipad{position:absolute;width:902px;height:668px;background:#131318;border-radius:44px;padding:21px;box-shadow:0 0 0 1.5px rgba(255,255,255,.17), 0 40px 90px rgba(0,0,0,.85);will-change:transform,opacity;}
.ipad .scr{position:relative;width:100%;height:100%;background:#000;border-radius:24px;overflow:hidden;padding:22px;}
.mac{position:absolute;width:1014px;height:652px;border-radius:18px;overflow:hidden;box-shadow:0 0 0 1.5px rgba(255,255,255,.17), 0 40px 90px rgba(0,0,0,.85);will-change:transform,opacity;background:#000;}
.mac .bar{height:44px;background:#1c1c1e;display:flex;align-items:center;padding:0 18px;gap:8px;}
.mac .bar i{width:13px;height:13px;border-radius:50%;}
.mac .bar .ttl{flex:1;text-align:center;font-size:15px;color:rgba(255,255,255,.5);font-weight:600;margin-right:55px;}
.mac .scr{position:relative;height:608px;background:#000;padding:26px 30px;}
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
.flowlbl{display:flex;justify-content:space-between;font-size:12px;font-weight:700;margin-top:8px;color:rgba(235,235,245,.6);}
.risktrack{position:relative;height:8px;border-radius:4px;background:#26262a;margin:52px 8px 46px;}
.riskcap{position:absolute;right:0;top:0;width:34px;height:8px;border-radius:4px;background:${RED};opacity:.85;}
.riskdot{position:absolute;top:-5px;width:18px;height:18px;border-radius:50%;box-shadow:0 0 0 4px #111113;will-change:transform,opacity;}
.risklbl{position:absolute;font-size:12px;font-weight:700;color:rgba(255,255,255,.78);white-space:nowrap;will-change:opacity;}
.post{background:#111113;border-radius:20px;padding:14px;margin-top:12px;will-change:opacity,transform;}
.post .hd{display:flex;align-items:center;gap:10px;}
.post .av{width:34px;height:34px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:800;color:#fff;}
.post .nm{font-size:14px;font-weight:750;color:#fff;}
.post .mt{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;}
.post .ctx{margin-left:auto;font-size:11px;font-weight:750;padding:3px 9px;border-radius:100px;background:rgba(255,255,255,.07);}
.post .tx{font-size:14px;line-height:1.45;color:rgba(255,255,255,.86);font-weight:550;margin-top:9px;}
.post .imgs{display:flex;gap:8px;margin-top:10px;}
.post .imgs i{flex:1;height:104px;border-radius:12px;}
.post .eng{display:flex;align-items:center;gap:6px;margin-top:10px;font-size:12px;font-weight:700;color:rgba(235,235,245,.45);}
.post .eng .gap{width:10px;}
.shelf{display:flex;gap:14px;margin-top:14px;}
.cover{width:148px;will-change:transform,opacity;}
.cover .art{width:148px;height:148px;border-radius:14px;}
.cover .cl{font-size:12px;font-weight:650;color:rgba(235,235,245,.6);margin-top:7px;white-space:nowrap;overflow:hidden;}
.mrow2{display:flex;align-items:center;gap:12px;padding:9px 0;will-change:opacity,transform;}
.mrow2 .art{width:44px;height:44px;border-radius:10px;flex:none;}
.mrow2 .tt{font-size:14px;font-weight:700;color:#fff;}
.mrow2 .ar{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
.mrow2 .du{margin-left:auto;font-size:12px;color:rgba(235,235,245,.49);font-weight:650;}
.vthumb{width:196px;will-change:transform,opacity;}
.vthumb .fr{position:relative;width:196px;height:110px;border-radius:12px;background:linear-gradient(150deg,#23232a,#0c0c10);display:flex;align-items:center;justify-content:center;}
.vthumb .dur{position:absolute;right:8px;bottom:8px;font-size:10px;font-weight:750;color:#fff;background:rgba(0,0,0,.72);padding:2px 6px;border-radius:6px;}
.vthumb .vt{font-size:12px;font-weight:650;color:rgba(235,235,245,.6);margin-top:7px;white-space:nowrap;overflow:hidden;}
.roomh{font-size:17px;font-weight:750;color:#fff;}
.roomsub{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
.mailrow{display:flex;gap:12px;padding:13px 0;will-change:opacity,transform;}
.mailrow .dot{width:9px;height:9px;border-radius:50%;background:${BLUE};margin-top:6px;flex:none;will-change:transform,opacity;}
.mailrow .dot.z{background:transparent;}
.mailrow .snd{font-size:15px;font-weight:750;color:#fff;}
.mailrow .sub{font-size:13.5px;font-weight:650;color:rgba(255,255,255,.85);margin-top:3px;}
.mailrow .snp{font-size:12.5px;color:rgba(235,235,245,.49);font-weight:550;margin-top:3px;white-space:nowrap;overflow:hidden;max-width:300px;}
.mailrow .tm2{margin-left:auto;font-size:12px;color:rgba(235,235,245,.49);font-weight:650;flex:none;}
.briefR2{position:absolute;right:30px;top:26px;width:390px;}
.eyebrow{font-size:15px;font-weight:700;color:${BLUE};letter-spacing:.02em;}
.bignum{font-size:54px;font-weight:800;color:#fff;letter-spacing:-.03em;margin-top:6px;display:flex;align-items:baseline;gap:14px;}
.bars{display:flex;align-items:flex-end;gap:8px;height:120px;margin-top:26px;}
.bars i{width:20px;border-radius:10px;background:${INK};opacity:.45;transform-origin:bottom;will-change:transform;}
.bars i:last-child{opacity:1;}
.barslbl{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:10px;}
.mcard{background:#111113;border-radius:20px;padding:18px;margin-top:18px;}
.mcard .t{font-size:15px;font-weight:750;color:#fff;margin-bottom:4px;}
.ringwrap{display:flex;gap:16px;align-items:center;}
.ringtxt .n{font-size:24px;font-weight:800;color:#fff;}
.ringtxt .l{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:3px;width:170px;line-height:1.4;}
.roomgrid{display:grid;grid-template-columns:1fr 1fr;grid-template-rows:1fr 1fr;gap:16px;height:100%;}
.rcard{background:#111113;border-radius:20px;padding:18px;position:relative;will-change:transform,opacity;}
.rcard .t{font-size:17px;font-weight:750;color:#fff;}
.rcard .s{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
.hm{position:absolute;left:18px;top:74px;display:grid;grid-template-columns:repeat(22,13px);grid-auto-rows:13px;gap:4px;}
.hm i{border-radius:3px;background:${BLUE};will-change:opacity;}
.hm i.z{background:#1d1d20;}
.topicwrap{position:absolute;left:18px;top:74px;width:380px;height:212px;}
.topiccell{position:absolute;border-radius:12px;display:flex;align-items:flex-end;padding:10px;font-weight:750;color:#fff;background:#0f2f57;will-change:transform,opacity;}
.leadrow{display:flex;align-items:center;gap:12px;margin-top:17px;}
.leadrow .av{width:34px;height:34px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:800;color:#fff;}
.leadrow .nm{width:78px;font-size:14px;font-weight:700;color:#fff;}
.leadrow .bar{height:14px;border-radius:7px;background:${VIOLET};transform-origin:left;will-change:transform;}
.leadrow .ct{font-size:13px;font-weight:700;color:rgba(235,235,245,.49);margin-left:auto;}
.cg{position:absolute;left:18px;top:74px;display:grid;grid-template-columns:repeat(20,13px);grid-auto-rows:13px;gap:4px;}
.cg i{border-radius:3px;background:${GREEN};will-change:opacity;}
.cg i.z{background:#1d1d20;}
/* B5 rapid-fire grid */
.g9{display:grid;grid-template-columns:1fr 1fr 1fr;grid-template-rows:1fr 1fr 1fr;gap:14px;height:100%;}
.gcard{background:#111113;border-radius:18px;padding:16px 18px;position:relative;overflow:hidden;will-change:transform,opacity;}
.gcard .gt{font-size:14px;font-weight:750;color:#fff;}
.gl{font-size:12px;color:rgba(235,235,245,.55);font-weight:600;line-height:1.45;}
.pillrow{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px;}
.ppill{font-size:12px;font-weight:750;padding:6px 12px;border-radius:100px;}
.track{position:relative;height:12px;border-radius:6px;background:#1d1d20;margin-top:18px;overflow:hidden;}
.track.thin{height:6px;border-radius:3px;}
.track .grow{position:absolute;left:0;top:0;bottom:0;border-radius:6px;transform-origin:left;will-change:transform;}
.exrow{display:flex;align-items:center;justify-content:space-between;margin-top:12px;}
.exs{font-size:13px;font-weight:650;color:rgba(255,255,255,.85);}
.exchip{font-size:11px;font-weight:750;padding:3px 10px;border-radius:100px;background:rgba(255,159,10,.16);color:${AMBER};}
.rdot{position:absolute;top:48px;width:14px;height:14px;border-radius:50%;background:#fff;box-shadow:0 0 0 3px #111113;}
.rtick{position:absolute;top:51px;width:3px;height:14px;border-radius:2px;background:${BLUE};}
.fadein{will-change:opacity;}
/* delight */
.mini{position:absolute;border-radius:30px;background:#131318;box-shadow:0 0 0 1.5px rgba(255,255,255,.15), 0 30px 70px rgba(0,0,0,.8);will-change:transform,opacity;}
.mini .scr{position:absolute;inset:9px;background:#050507;border-radius:22px;overflow:hidden;padding:14px;}
.drop{position:absolute;border-radius:50%;will-change:transform,opacity;z-index:40;}
.minitm{position:absolute;border-radius:8px;}
.minibar{position:absolute;bottom:14px;border-radius:6px;background:${INK};}
.flipchips{position:absolute;left:50%;top:868px;transform:translateX(-50%);display:flex;gap:12px;will-change:opacity;}
.fchipw{perspective:520px;will-change:opacity,transform;}
.fchip{display:inline-block;font-size:17px;font-weight:750;padding:11px 22px;border-radius:100px;background:#1c1c1e;color:rgba(255,255,255,.88);box-shadow:0 0 0 1px rgba(255,255,255,.1), 0 14px 30px rgba(0,0,0,.55);will-change:transform,background;}
.fchip.on{background:${INK};color:#fff;}
.introMark{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);will-change:opacity;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;opacity:0;will-change:opacity;}
.outro .b{font-size:120px;font-weight:800;letter-spacing:-.045em;color:#fff;line-height:.9;margin-top:30px;}
.outro .u{font-size:24px;letter-spacing:.1em;color:rgba(255,255,255,.55);margin-top:26px;font-weight:600;}
.outro .u b{color:${BLUE};}
.outro svg{will-change:transform,opacity;}
</style></head><body>
<div class="stage">
  <div class="introMark" id="introMark">${berrySVG(120)}</div>

  <!-- B1: iPhone, the Wallet room -->
  <div class="beat" id="b0">
    ${iphoneShell('phone', 771, 128, `
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
              <rect x="0" y="22" width="64" height="58" fill="${GREEN}"/>
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
      </div>`)}
  </div>

  <!-- B2: iPhone social feed + iPad media room -->
  <div class="beat" id="b1">
    ${iphoneShell('phone2', 268, 128, `
      <div class="appbar"><span class="chip on">Farcaster</span><span class="chip">Bluesky</span><span class="chip">All</span><span class="chip">Wallet</span></div>
      <div class="panel">
        ${POSTS.map(([hue, ini, nm, mt, ctx, chue, tx, lk, rc, imgs], k) => `
        <div class="post" data-k="${k}">
          <div class="hd"><span class="av" style="background:${hue}">${ini}</span>
            <span><span class="nm">${nm}</span><br><span class="mt">${mt}</span></span>
            <span class="ctx" style="color:${chue}">${ctx}</span></div>
          <div class="tx">${tx}</div>
          ${imgs ? `<div class="imgs"><i style="background:linear-gradient(150deg,#d97b2a,#5a2508)"></i><i style="background:linear-gradient(150deg,#d94f70,#2c1140)"></i></div>` : ''}
          <div class="eng">${HEART}<span>${lk}</span><span class="gap"></span>${RECAST}<span>${rc}</span></div>
        </div>`).join('')}
      </div>`)}
    <div class="ipad" id="pad1" style="left:800px;top:188px"><div class="scr">
      <div class="roomh">Media</div><div class="roomsub">Spotify · YouTube · Podcasts — everything you played, kept</div>
      <div class="shelf">${COVERS.map(([t, g], k) => `<div class="cover" data-k="${k}"><div class="art" style="background:${g}"></div><div class="cl">${t}</div></div>`).join('')}</div>
      <div style="margin-top:8px">${SONGS.map(([t, a, d, hue], k) => `
        <div class="mrow2" data-k="${k}"><span class="art" style="background:linear-gradient(140deg,${hue},#111)"></span>
          <span><span class="tt">${t}</span><br><span class="ar">${a}</span></span><span class="du">${d}</span></div>`).join('')}
      </div>
      <div class="shelf" style="margin-top:12px">${VIDEOS.map(([t, d], k) => `
        <div class="vthumb" data-k="${k}"><div class="fr">${PLAY}<span class="dur">${d}</span></div><div class="vt">${t}</div></div>`).join('')}
      </div>
    </div></div>
  </div>

  <!-- B3: Mac — Mail beside the Today brief -->
  <div class="beat" id="b2">
    ${macShell('macwin', 453, 196, `
        <div style="position:absolute;left:30px;top:26px;width:470px">
          <div class="roomh">Mail</div><div class="roomsub">what landed while you were away</div>
          <div style="margin-top:8px">${MAIL.map(([snd, sub, snp, tm, un], k) => `
            <div class="mailrow" data-k="${k}"><span class="dot${un ? '' : ' z'}"></span>
              <span style="min-width:0"><span class="snd">${snd}</span><br><span class="sub">${sub}</span><br><span class="snp">${snp}…</span></span>
              <span class="tm2">${tm}</span></div>`).join('')}
          </div>
        </div>
        <div class="briefR2">
          <div class="eyebrow">Your Tuesday</div>
          <div class="bignum"><span id="heronum">$0</span><span class="pill" id="heropill">+$1,204 · 2.6%</span></div>
          <div class="bars" id="hourbars">${HOURS.map(h => `<i style="height:${h}%"></i>`).join('')}</div>
          <div class="barslbl" id="hourlbl">Your day, hour by hour</div>
          <div class="mcard"><div class="t">signed_up</div>
            <div class="ringwrap">
              <svg width="96" height="96" viewBox="0 0 110 110">
                <circle cx="55" cy="55" r="46" fill="none" stroke="#26262a" stroke-width="9"/>
                <circle id="ringarc" cx="55" cy="55" r="46" fill="none" stroke="${INK}" stroke-width="9" stroke-linecap="round" transform="rotate(-90 55 55)" stroke-dasharray="289" stroke-dashoffset="289"/>
                <polyline id="ringcurve" points="36,66 44,62 50,64 58,56 66,58 74,50" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2" stroke-linecap="round"/>
              </svg>
              <div class="ringtxt"><div class="n" id="ringnum">0</div><div class="l">of the next 100 — its own week inside the ring</div></div>
            </div>
          </div>
        </div>`)}
  </div>

  <!-- B4: iPad, the room leads -->
  <div class="beat" id="b3">
    <div class="ipad" id="pad" style="left:509px;top:184px"><div class="scr"><div class="roomgrid">
      <div class="rcard" data-k="0"><div class="t">Your capture year</div><div class="s">1,284 things · busiest in March</div>
        <div class="hm">${HEAT.map(v => `<i${v === 0 ? ' class="z"' : ''} data-v="${v.toFixed(2)}"></i>`).join('')}</div>
      </div>
      <div class="rcard" data-k="1"><div class="t">What your images say</div><div class="s">every label appears in a screenshot</div>
        <div class="topicwrap">${TOPICS.map(([x, y, w, h, t, n], k) =>
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

  <!-- B5: Mac — nine more reads, rapid-fire -->
  <div class="beat" id="b4">
    ${macShell('macwin2', 453, 196, `<div class="g9">${GRID9.map(([t, body], k) =>
      `<div class="gcard" data-k="${k}"><div class="gt">${t}</div>${body}</div>`).join('')}</div>`)}
  </div>

  <!-- B6: delight — berry rain, then the source chips flip -->
  <div class="beat" id="b5">
    <div class="mini" id="miniPad" style="left:510px;top:250px;width:430px;height:320px;">
      <div class="scr">
        <div style="font-size:12px;font-weight:750;color:#fff">Your capture year</div>
        <div style="position:absolute;left:14px;top:40px;display:grid;grid-template-columns:repeat(22,12px);grid-auto-rows:12px;gap:3px">${
          HEAT.map(v => `<i style="border-radius:3px;background:${v === 0 ? '#1d1d20' : `rgba(10,132,255,${(0.18 + v * 0.75).toFixed(2)})`}"></i>`).join('')}</div>
      </div>
    </div>
    <div class="mini" id="miniMac" style="left:970px;top:232px;width:440px;height:300px;border-radius:14px;">
      <div class="scr" style="border-radius:8px;">
        <div style="font-size:11px;font-weight:700;color:${BLUE}">Your Tuesday</div>
        <div style="font-size:30px;font-weight:800;color:#fff;margin-top:2px">$48,210 <span style="font-size:11px;font-weight:750;color:#04270f;background:${GREEN};padding:2px 8px;border-radius:100px;vertical-align:middle">+2.6%</span></div>
        ${HOURS.map((h, k) => `<span class="minibar" style="left:${16 + k * 29}px;width:17px;height:${h * 1.1}px;opacity:${k === HOURS.length - 1 ? 1 : 0.45}"></span>`).join('')}
      </div>
    </div>
    <div class="mini" id="miniPhone" style="left:710px;top:308px;width:230px;height:470px;border-radius:38px;z-index:20;">
      <div class="scr" style="border-radius:30px;">
        <div style="font-size:11px;font-weight:600;color:rgba(235,235,245,.49)">Across your wallets</div>
        <div style="font-size:24px;font-weight:800;color:#fff">$48,210</div>
        ${TREEMAP.map(([x, y, w, h, s, v, c]) =>
          `<span class="minitm" style="left:${14 + x * 0.63}px;top:${86 + y * 0.63}px;width:${w * 0.63}px;height:${h * 0.63}px;background:${c}"></span>`).join('')}
        <div style="position:absolute;bottom:14px;left:14px;font-size:10px;font-weight:600;color:rgba(235,235,245,.49)">ETH is 54% of the book</div>
      </div>
    </div>
    <div class="flipchips" id="flipchips">${CHIPS.map((c, k) =>
      `<span class="fchipw"><span class="fchip${k === 0 ? ' on' : ''}" data-k="${k}">${c}</span></span>`).join('')}</div>
    ${DROPS.map((d, k) => `<span class="drop" data-k="${k}" style="width:${(d.r * 2) | 0}px;height:${(d.r * 2) | 0}px;background:${d.c};left:${d.x | 0}px;top:0"></span>`).join('')}
  </div>

  <div class="outro" id="outro">${berrySVG(130, 'omark')}<div class="b">Casberi</div><div class="u mono">EVERY READ, ON DEVICE — <b>casberi.app</b></div></div>
</div>
<script>
var clamp01=function(v){return Math.max(0,Math.min(1,v));};
var easeOut=function(p){return 1-Math.pow(1-p,3);};
var back=function(p){var c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
var INTRO=${INTRO},STARTS=${JSON.stringify(STARTS)},OUT_AT=${OUT_AT},N=6;
var DROPS=${JSON.stringify(DROPS.map(d => ({ delay: +d.delay.toFixed(3), dur: +d.dur.toFixed(3), drift: +d.drift.toFixed(1) })))};
var FLIPS=[1,2,3],FLIPAT=[1.75,2.25,2.75];  // chips that flip, and when — after the rain
window.TOTAL=${TOTAL};
var beats=[0,1,2,3,4,5].map(function(i){return document.getElementById('b'+i);});
var sparkLen=null;
function fmt(n){return '$'+Math.round(n).toLocaleString('en-US');}

window.seek=function(t){
  var im=document.getElementById('introMark');
  im.style.opacity=Math.min(clamp01(t/0.3),1-clamp01((t-(INTRO-0.25))/0.3));
  for(var bi=0;bi<N;bi++){
    var el=beats[bi],bs=STARTS[bi],be=STARTS[bi+1]||OUT_AT;
    var op=clamp01((t-bs)/0.18)*(1-clamp01((t-(be-0.24))/0.24));
    if(t<bs-0.02||t>=be+0.3)op=0;
    var outp=clamp01((t-(be-0.24))/0.24);
    el.style.opacity=op;
    el.style.transform='translateY('+(-34*outp)+'px)';
    el.style.pointerEvents='none';
    if(op>0)animate(bi,t-bs,t);
  }
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.08))/0.5));
  var om=document.querySelector('.omark');if(om){var omp=clamp01((t-(OUT_AT+0.18))/0.6);om.style.transform='scale('+(0.6+0.4*back(omp))+')';om.style.opacity=omp;}
};

function shellIn(el,local,dy){var p=clamp01((local-0.05)/0.6);el.style.opacity=p;el.style.transform='translateY('+((1-back(p))*(dy||110))+'px)';return p;}

function animate(i,local,t){
  if(i===0){
    shellIn(document.getElementById('phone'),local);
    var pA=document.getElementById('pA'),pB=document.getElementById('pB');
    var swap=clamp01((local-2.9)/0.42);
    pA.style.opacity=1-swap;pA.style.transform='translateY('+(-swap*40)+'px)';
    pB.style.opacity=swap;pB.style.transform='translateY('+((1-swap)*50)+'px)';
    document.getElementById('balnum').style.opacity=clamp01((local-0.4)/0.35);
    var pp=clamp01((local-0.7)/0.32);
    var pillEl=document.getElementById('balpill');pillEl.style.opacity=pp;pillEl.style.transform='scale('+(0.5+0.5*back(pp))+')';
    var sp=document.getElementById('sparkpath');
    if(sparkLen===null)sparkLen=sp.getTotalLength();
    var spp=easeOut(clamp01((local-1.05)/0.95));
    sp.style.strokeDasharray=sparkLen;sp.style.strokeDashoffset=sparkLen*(1-spp);
    document.getElementById('moverline').style.opacity=clamp01((local-1.95)/0.4);
    var cells=document.querySelectorAll('#pA .tmcell');
    for(var k=0;k<cells.length;k++){var cp=clamp01((local-0.7-k*0.12)/0.42);cells[k].style.opacity=cp;cells[k].style.transform='scale('+(0.82+0.18*back(cp))+')';}
    document.getElementById('concline').style.opacity=clamp01((local-2.0)/0.4);
    var fl=easeOut(clamp01((local-3.2)/0.8));
    var lr=document.getElementById('clipLrect');lr.setAttribute('x',158-158*fl);lr.setAttribute('width',158*fl);
    var fr=easeOut(clamp01((local-3.5)/0.8));
    document.getElementById('clipRrect').setAttribute('width',158*fr);
    document.getElementById('flowspine').style.opacity=clamp01((local-3.1)/0.3);
    document.querySelector('#pB .flowlbl').style.opacity=clamp01((local-4.05)/0.4);
    var dots=document.querySelectorAll('.riskdot');
    for(var k3=0;k3<dots.length;k3++){var dp=clamp01((local-4.2-k3*0.18)/0.38);dots[k3].style.opacity=dp;dots[k3].style.transform='translateY('+((1-back(dp))*-26)+'px)';}
    var lbls=document.querySelectorAll('.risklbl');
    for(var k4=0;k4<lbls.length;k4++){lbls[k4].style.opacity=clamp01((local-4.4-k4*0.18)/0.34);}
  } else if(i===1){
    shellIn(document.getElementById('phone2'),local);
    shellIn(document.getElementById('pad1'),local,90);
    var posts=document.querySelectorAll('#b1 .post');
    for(var p1=0;p1<posts.length;p1++){var pp2=clamp01((local-0.6-p1*0.46)/0.5);posts[p1].style.opacity=pp2;posts[p1].style.transform='translateY('+((1-back(pp2))*44)+'px)';}
    var cvs=document.querySelectorAll('#b1 .cover');
    for(var c1=0;c1<cvs.length;c1++){var cp1=clamp01((local-0.85-c1*0.14)/0.42);cvs[c1].style.opacity=cp1;cvs[c1].style.transform='scale('+(0.84+0.16*back(cp1))+')';}
    var mr=document.querySelectorAll('#b1 .mrow2');
    for(var m1=0;m1<mr.length;m1++){var mp1=clamp01((local-1.85-m1*0.26)/0.42);mr[m1].style.opacity=mp1;mr[m1].style.transform='translateX('+((1-easeOut(mp1))*36)+'px)';}
    var vt=document.querySelectorAll('#b1 .vthumb');
    for(var v1=0;v1<vt.length;v1++){var vp1=clamp01((local-2.85-v1*0.18)/0.42);vt[v1].style.opacity=vp1;vt[v1].style.transform='translateY('+((1-back(vp1))*26)+'px)';}
  } else if(i===2){
    shellIn(document.getElementById('macwin'),local);
    var rows=document.querySelectorAll('#b2 .mailrow');
    for(var r1=0;r1<rows.length;r1++){var rp1=clamp01((local-0.6-r1*0.3)/0.48);rows[r1].style.opacity=rp1;rows[r1].style.transform='translateX('+((1-easeOut(rp1))*-34)+'px)';
      var dt=rows[r1].querySelector('.dot');if(dt&&!dt.classList.contains('z')){var dp1=clamp01((local-0.95-r1*0.3)/0.3);dt.style.transform='scale('+(0.3+0.7*back(dp1))+')';dt.style.opacity=dp1;}}
    var cp2=easeOut(clamp01((local-0.8)/1.0));
    document.getElementById('heronum').textContent=fmt(48210*cp2);
    var hp=clamp01((local-1.85)/0.34);
    var hpill=document.getElementById('heropill');hpill.style.opacity=hp;hpill.style.transform='scale('+(0.5+0.5*back(hp))+')';
    var bars=document.querySelectorAll('#hourbars i');
    for(var k7=0;k7<bars.length;k7++){var bp=clamp01((local-1.95-k7*0.075)/0.48);bars[k7].style.transform='scaleY('+back(bp)+')';}
    document.getElementById('hourlbl').style.opacity=clamp01((local-3.0)/0.4);
    var rp3=easeOut(clamp01((local-3.1)/0.95));
    document.getElementById('ringarc').style.strokeDashoffset=289*(1-0.82*rp3);
    document.getElementById('ringnum').textContent=Math.round(82*rp3);
    var rc=document.getElementById('ringcurve');
    if(!rc.dataset.len)rc.dataset.len=rc.getTotalLength();
    var rcl=parseFloat(rc.dataset.len);var rcp=easeOut(clamp01((local-3.5)/0.75));
    rc.style.strokeDasharray=rcl;rc.style.strokeDashoffset=rcl*(1-rcp);
  } else if(i===3){
    shellIn(document.getElementById('pad'),local);
    var rcards=document.querySelectorAll('#b3 .rcard');
    for(var c=0;c<rcards.length;c++){var rp2=clamp01((local-0.28-c*0.36)/0.48);rcards[c].style.opacity=rp2;rcards[c].style.transform='translateY('+((1-back(rp2))*46)+'px)';}
    var hm=document.querySelectorAll('#b3 .hm i');
    for(var h=0;h<hm.length;h++){var col=h%22;var v=parseFloat(hm[h].getAttribute('data-v')||'0');
      var ap=clamp01((local-0.65-col*0.045)/0.28);
      hm[h].style.opacity=hm[h].classList.contains('z')?ap*0.8:ap*(0.18+v*0.78);}
    var tc=document.querySelectorAll('#b3 .topiccell');
    for(var k5=0;k5<tc.length;k5++){var tp=clamp01((local-1.3-k5*0.13)/0.38);tc[k5].style.opacity=tp;tc[k5].style.transform='scale('+(0.82+0.18*back(tp))+')';}
    var lb=document.querySelectorAll('#b3 .leadrow');
    for(var k6=0;k6<lb.length;k6++){var lp2=clamp01((local-1.9-k6*0.16)/0.48);lb[k6].style.opacity=Math.min(1,lp2*3);
      lb[k6].querySelector('.bar').style.transform='scaleX('+easeOut(lp2)+')';
      lb[k6].querySelector('.ct').style.opacity=clamp01((lp2-0.7)/0.3);}
    var cg=document.querySelectorAll('#b3 .cg i');
    for(var g=0;g<cg.length;g++){var o=parseFloat(cg[g].getAttribute('data-o')||'0');var v2=parseFloat(cg[g].getAttribute('data-v')||'0');
      var gp=clamp01((local-2.3-o*1.1)/0.25);
      cg[g].style.opacity=cg[g].classList.contains('z')?gp*0.8:gp*(0.2+v2*0.8);}
  } else if(i===4){
    shellIn(document.getElementById('macwin2'),local);
    var gcards=document.querySelectorAll('#b4 .gcard');
    for(var g1=0;g1<gcards.length;g1++){
      var gp1=clamp01((local-0.25-g1*0.26)/0.45);
      gcards[g1].style.opacity=gp1;gcards[g1].style.transform='translateY('+((1-back(gp1))*36)+'px)';
      var grows=gcards[g1].querySelectorAll('.grow');
      for(var g2=0;g2<grows.length;g2++){grows[g2].style.transform='scaleX('+easeOut(clamp01((local-0.5-g1*0.26-g2*0.12)/0.5))+')';}
      var fades=gcards[g1].querySelectorAll('.fadein');
      for(var g3=0;g3<fades.length;g3++){fades[g3].style.opacity=clamp01((local-0.75-g1*0.26-g3*0.08)/0.35);}
      var sa=gcards[g1].querySelector('.sarc');
      if(sa)sa.style.strokeDashoffset=176*(1-0.667*easeOut(clamp01((local-0.6-g1*0.26)/0.6)));
    }
  } else if(i===5){
    var minis=[document.getElementById('miniPad'),document.getElementById('miniMac'),document.getElementById('miniPhone')];
    for(var k9=0;k9<3;k9++){var np2=clamp01((local-0.08-k9*0.13)/0.48);minis[k9].style.opacity=np2;minis[k9].style.transform='translateY('+((1-back(np2))*90)+'px)';}
    // the rain first…
    var drops=document.querySelectorAll('.drop');
    for(var d2=0;d2<drops.length;d2++){var dd=DROPS[d2];var pp3=(local-0.35-dd.delay)/dd.dur;
      if(pp3<0||pp3>1){drops[d2].style.opacity=0;continue;}
      var yy=120+Math.pow(pp3,1.55)*840;
      drops[d2].style.transform='translate('+(dd.drift*pp3)+'px,'+yy+'px)';
      drops[d2].style.opacity=Math.min(clamp01(pp3/0.12),1-clamp01((pp3-0.82)/0.18));}
    // …then the source chips flip, the active state following the flips
    document.getElementById('flipchips').style.opacity=clamp01((local-0.4)/0.4);
    var chips=document.querySelectorAll('.fchip');
    var active=0;
    for(var f1=0;f1<FLIPS.length;f1++){if(clamp01((local-FLIPAT[f1])/0.55)>0.5)active=FLIPS[f1];}
    for(var c3=0;c3<chips.length;c3++){
      var rot=0;
      for(var f2=0;f2<FLIPS.length;f2++){if(FLIPS[f2]===c3)rot=360*easeOut(clamp01((local-FLIPAT[f2])/0.55));}
      chips[c3].style.transform='rotateX('+rot+'deg)';
      chips[c3].className='fchip'+(c3===active?' on':'');
    }
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname, 'clip-viz-reel.html'), html);
console.log('wrote clip-viz-reel.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
