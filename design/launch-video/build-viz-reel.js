// THE VISUALIZATIONS reel — v3 "one camera", ruled 2026-08-04 after v2 read
// as a slideshow (user: "it's poor"). What changed and why:
//   ONE CONTINUOUS CAMERA — a virtual camera (translate+scale on a world
//     container) opens CROPPED INSIDE the phone screen while the wallet
//     paints at readable size, pulls back to reveal the hardware, then pans
//     laterally phone -> iPad -> Mac. No hard cuts through black; nothing is
//     ever fully still (a small deterministic drift rides every hold).
//   THE CHIP FLIP IS THE EDIT — switching rooms happens the way it happens
//     in the app: the source chip in the phone's own header does its one
//     forward X-axis turn (CoinFlip.swift) and the feed repopulates in
//     place. Delight is the structure, not a beat at the end.
//   BERRY RAIN IN CONTEXT — a pull-to-refresh on the feed near the close:
//     the rows dip, a new post lands on top, and the shower falls INSIDE
//     the screen over real rows (BerryRain rides ShellChrome.refreshPulse
//     over the surface, not over a void).
//   THE NINE EXTRA READS ARE A CONVEYOR — full-size cards sliding through a
//     center focus, ~0.45s apart, each big enough to actually read; the
//     grid wall of v2 made every read postage-stamp sized.
// Colors are the app's own tokens: page #000, sheet #111113, accent ink
// #1673e6, link blue #0a84ff, green #3fb950. No hairlines — depth by tone.
// Deterministic (window.seek/window.TOTAL) -> design/launch-video/render-viz.sh
const fs = require('fs'), path = require('path');

const BLUE = '#0a84ff', INK = '#1673e6', GREEN = '#3fb950', RED = '#ff453a',
      AMBER = '#ff9f0a', VIOLET = '#8c40c7';
const TOTAL = 25.0;

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

// ---- world layout: phone | iPad | Mac on one lateral strip ----------------
const PHONE = { x: 760, y: 146 };   // 378x788 -> center (949, 540)
const IPAD  = { x: 2200, y: 206 };  // 902x668 -> center (2651, 540)
const MAC   = { x: 3900, y: 214 };  // 1014x652 -> center (4407, 540)

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
   'the best interfaces disappear — you notice the thing, not the chrome', 128, 24, 0],
  ['#3a6df0', 'M', 'maya', '@maya · 4h', 'Liked', BLUE,
   'sunset test shots from the new lens', 64, 9, 1],
  ['#2e9e8f', 'L', 'linda', '@linda · 6h', 'Mentions you', BLUE,
   '@you this is exactly the treemap idea we talked about', 12, 2, 0],
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
const HOURS = [12, 20, 32, 26, 44, 58, 40, 66, 84, 60, 92, 74, 50, 34];
const lcg = seed => () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
const rainR = lcg(20260804);
const BERRIES = ['#0a84ff', '#3f9fff', '#0a84ff', '#1266c4'];
// The shower falls INSIDE the phone screen — coordinates are screen-local.
const DROPS = Array.from({ length: 18 }, (_, i) => ({
  x: 18 + rainR() * 312, delay: rainR() * 1.3, dur: 0.85 + rainR() * 0.35,
  r: 4 + rainR() * 6, c: BERRIES[i % 4], drift: (rainR() - 0.5) * 26,
}));

// The conveyor — nine more reads, each card sized to be READ.
const CARDS = [
  ['In protocols', `<div class="pillrow">
     <span class="ppill" style="background:rgba(63,185,80,.16);color:${GREEN}">Deposited $9,420</span>
     <span class="ppill" style="background:rgba(10,132,255,.16);color:${BLUE}">Locked $2,140</span>
     <span class="ppill" style="background:rgba(255,255,255,.08);color:rgba(235,235,245,.6)">Owed $1,200</span></div>
     <div class="gl fadein" style="margin-top:22px">what's deposited, locked, and owed — with the protocols it came from</div>`],
  ['The melt · veAERO', `<div class="track"><div class="grow" style="width:100%;background:rgba(10,132,255,.25)"></div>
     <div class="grow" style="width:41%;background:${BLUE}"></div></div>
     <div class="gl fadein" style="margin-top:18px">5,342 votes left of 12,977 locked · ends 2028 —<br>a lock that decays, drawn decaying</div>`],
  ['Approval exposure', `<div class="exrow fadein"><span class="exs">USDC · $6,120 reachable</span><span class="exchip">Unlimited</span></div>
     <div class="exrow fadein"><span class="exs">ETH · $310 reachable</span><span class="exchip" style="background:rgba(255,255,255,.08);color:rgba(235,235,245,.6)">Capped</span></div>
     <div class="gl fadein" style="margin-top:20px">which grant to revoke first, ranked by dollars at stake</div>`],
  ['Connections', `<svg width="380" height="120" viewBox="0 0 380 120">
     <g class="fadein"><path d="M50,34 C140,34 230,24 330,24" stroke="rgba(235,235,245,.35)" stroke-width="4" fill="none"/>
     <path d="M50,34 C140,40 230,80 330,80" stroke="rgba(235,235,245,.35)" stroke-width="4" fill="none"/>
     <path d="M50,92 C150,92 235,82 330,80" stroke="rgba(235,235,245,.35)" stroke-width="4" fill="none"/></g>
     <circle cx="42" cy="34" r="12" fill="#55555c"/><circle cx="42" cy="92" r="12" fill="#55555c"/>
     <circle cx="338" cy="24" r="13" fill="#3a6df0"/><circle cx="338" cy="80" r="13" fill="#8f5bd9"/></svg>
     <div class="gl fadein">2 counterparties reach two of your wallets — every ribbon the same weight, by ruling</div>`],
  ['Fed cuts by March?', `<div class="track" style="margin-top:26px"><div class="grow" style="width:62%;background:${BLUE}"></div></div>
     <div class="exrow fadein" style="margin-top:14px"><span class="gl">Kalshi · the live book's own bracket</span><span style="font-size:26px;font-weight:800;color:#fff">62%</span></div>`],
  ['LP range · ETH/USDC', `<div class="track" style="margin-top:26px"><div class="grow" style="left:22%;width:46%;background:rgba(10,132,255,.35)"></div></div>
     <span class="rdot fadein" style="left:calc(30px + 44%)"></span>
     <div class="gl fadein" style="margin-top:16px">the position's window on the price axis — in range, earning fees</div>`],
  ['Safe · 2 of 3', `<div style="display:flex;gap:22px;align-items:center;margin-top:10px">
     <svg width="92" height="92" viewBox="0 0 70 70">
       <circle cx="35" cy="35" r="28" fill="none" stroke="#26262a" stroke-width="8"/>
       <circle class="sarc" cx="35" cy="35" r="28" fill="none" stroke="${BLUE}" stroke-width="8" stroke-linecap="round" transform="rotate(-90 35 35)" stroke-dasharray="176" stroke-dashoffset="176"/>
     </svg><div class="gl" style="flex:1">2 signatures collected —<br><b style="color:#fff">yours is needed</b></div></div>`],
  ['What lands here', `<div class="track seg" style="margin-top:26px">
     <div class="grow" style="width:44%;background:${BLUE}"></div><div class="grow" style="left:45%;width:26%;background:${VIOLET}"></div>
     <div class="grow" style="left:72%;width:16%;background:#2e9e8f"></div><div class="grow" style="left:89%;width:11%;background:#c8842a"></div></div>
     <div class="gl fadein" style="margin-top:16px">links · posts · screenshots · notes — the corpus in proportion</div>`],
  ['The runway', `<div class="track thin" style="margin-top:32px"><div class="grow" style="width:100%;background:#26262a"></div></div>
     <span class="rtick fadein" style="left:calc(30px + 12%)"></span><span class="rtick fadein" style="left:calc(30px + 46%)"></span><span class="rtick fadein" style="left:calc(30px + 82%)"></span>
     <div class="gl fadein" style="margin-top:18px">cert 12d · domain 44d · invoice 89d — every deadline on one axis</div>`],
];

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1920px;height:1080px;overflow:hidden;background:#000;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:radial-gradient(1400px 950px at 50% 46%, #101016, #000 72%);}
#world{position:absolute;left:0;top:0;width:6000px;height:1080px;transform-origin:0 0;will-change:transform,opacity;}
.glow{position:absolute;width:1400px;height:1200px;border-radius:50%;background:radial-gradient(closest-side, rgba(18,102,196,.17), transparent 70%);will-change:opacity;}

/* shells */
.iphone{position:absolute;width:378px;height:788px;background:#131318;border-radius:62px;padding:11px;box-shadow:0 0 0 1.5px rgba(255,255,255,.18), 0 46px 100px rgba(0,0,0,.88);}
.iphone .scr{position:relative;width:100%;height:100%;background:#050507;border-radius:52px;overflow:hidden;}
.island{position:absolute;left:50%;top:13px;transform:translateX(-50%);width:104px;height:30px;border-radius:16px;background:#000;z-index:9;}
.ipad{position:absolute;width:902px;height:668px;background:#131318;border-radius:44px;padding:21px;box-shadow:0 0 0 1.5px rgba(255,255,255,.18), 0 46px 100px rgba(0,0,0,.88);}
.ipad .scr{position:relative;width:100%;height:100%;background:#000;border-radius:24px;overflow:hidden;padding:22px;}
.mac{position:absolute;width:1014px;height:652px;border-radius:18px;overflow:hidden;box-shadow:0 0 0 1.5px rgba(255,255,255,.18), 0 46px 100px rgba(0,0,0,.88);background:#000;}
.mac .bar{height:44px;background:#1c1c1e;display:flex;align-items:center;padding:0 18px;gap:8px;}
.mac .bar i{width:13px;height:13px;border-radius:50%;}
.mac .bar .ttl{flex:1;text-align:center;font-size:15px;color:rgba(255,255,255,.5);font-weight:600;margin-right:55px;}
.mac .scr{position:relative;height:608px;background:#000;padding:26px 30px;}
.sweep{position:absolute;inset:-10%;background:linear-gradient(115deg, transparent 42%, rgba(255,255,255,.07) 50%, transparent 58%);transform:translateX(-120%);will-change:transform;pointer-events:none;z-index:20;}

/* phone chrome */
.appbar{display:flex;align-items:center;gap:8px;padding:58px 18px 10px;}
.fchipw{perspective:420px;}
.fchip{display:inline-block;font-size:13px;font-weight:700;padding:7px 14px;border-radius:100px;background:#1c1c1e;color:rgba(255,255,255,.85);will-change:transform,background;}
.fchip.on{background:${INK};color:#fff;}
.panel{position:absolute;left:18px;right:18px;top:112px;bottom:14px;will-change:opacity,transform;}
.cap13{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;}
.money{font-size:36px;font-weight:800;color:#fff;letter-spacing:-.02em;margin-top:3px;display:flex;align-items:center;gap:12px;}
.pill{font-size:14px;font-weight:750;color:#04270f;background:${GREEN};padding:4px 11px;border-radius:100px;will-change:transform,opacity;}
.mover{font-size:13px;color:rgba(235,235,245,.49);font-weight:600;margin-top:8px;}
.card{background:#111113;border-radius:20px;padding:14px;margin-top:14px;}
.card .t{font-size:15px;font-weight:700;color:#fff;}
.tm{position:relative;margin-top:10px;}
.tmcell{position:absolute;border-radius:12px;padding:10px 12px;will-change:transform,opacity;}
.tmcell .sym{font-size:15px;font-weight:800;color:#fff;}
.tmcell .val{font-size:12px;font-weight:650;color:rgba(255,255,255,.72);margin-top:1px;}
.conc{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:10px;}

/* social feed */
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
.newpost{position:absolute;left:0;right:0;top:0;will-change:opacity,transform;}
.drop{position:absolute;border-radius:50%;will-change:transform,opacity;z-index:30;}

/* iPad media */
.roomh{font-size:17px;font-weight:750;color:#fff;}
.roomsub{font-size:12px;color:rgba(235,235,245,.49);font-weight:600;margin-top:2px;}
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

/* Mac mail + brief */
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

/* the conveyor — screen space */
#conveyor{position:absolute;inset:0;opacity:0;will-change:opacity;}
.ccard{position:absolute;top:340px;width:640px;height:400px;background:#111113;border-radius:26px;padding:30px;box-shadow:0 0 0 1.5px rgba(255,255,255,.14), 0 40px 90px rgba(0,0,0,.8);will-change:transform,opacity;}
.ccard .gt{font-size:24px;font-weight:800;color:#fff;letter-spacing:-.01em;}
.gl{font-size:16px;color:rgba(235,235,245,.55);font-weight:600;line-height:1.5;}
.pillrow{display:flex;flex-wrap:wrap;gap:10px;margin-top:24px;}
.ppill{font-size:15px;font-weight:750;padding:9px 16px;border-radius:100px;}
.track{position:relative;height:16px;border-radius:8px;background:#1d1d20;margin-top:26px;overflow:hidden;}
.track.thin{height:8px;border-radius:4px;}
.track .grow{position:absolute;left:0;top:0;bottom:0;border-radius:8px;transform-origin:left;will-change:transform;}
.exrow{display:flex;align-items:center;justify-content:space-between;margin-top:18px;}
.exs{font-size:17px;font-weight:650;color:rgba(255,255,255,.88);}
.exchip{font-size:13px;font-weight:750;padding:4px 12px;border-radius:100px;background:rgba(255,159,10,.16);color:${AMBER};}
.rdot{position:absolute;top:84px;width:16px;height:16px;border-radius:50%;background:#fff;box-shadow:0 0 0 4px #111113;}
.rtick{position:absolute;top:88px;width:4px;height:18px;border-radius:2px;background:${BLUE};}
.fadein{will-change:opacity;}
.ckick{position:absolute;left:0;right:0;top:212px;text-align:center;font-size:19px;letter-spacing:.14em;color:rgba(255,255,255,.5);font-weight:650;will-change:opacity;}

/* outro */
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;opacity:0;will-change:opacity;}
.outro .b{font-size:120px;font-weight:800;letter-spacing:-.045em;color:#fff;line-height:.9;margin-top:30px;}
.outro .u{font-size:24px;letter-spacing:.1em;color:rgba(255,255,255,.55);margin-top:26px;font-weight:600;}
.outro .u b{color:${BLUE};}
.outro svg{will-change:transform,opacity;}
</style></head><body>
<div class="stage">
<div id="world">
  <div class="glow" id="glowPhone" style="left:${PHONE.x - 510}px;top:-60px"></div>
  <div class="glow" id="glowPad" style="left:${IPAD.x - 250}px;top:-60px"></div>
  <div class="glow" id="glowMac" style="left:${MAC.x - 190}px;top:-60px"></div>

  <!-- the protagonist phone -->
  <div class="iphone" style="left:${PHONE.x}px;top:${PHONE.y}px"><div class="scr" id="phoneScr">
    <div class="island"></div>
    <div class="appbar">
      <span class="fchipw"><span class="fchip on" data-c="0">Wallet</span></span>
      <span class="fchipw"><span class="fchip" data-c="1">Farcaster</span></span>
      <span class="fchipw"><span class="fchip" data-c="2">Photos</span></span>
      <span class="fchipw"><span class="fchip" data-c="3">All</span></span>
    </div>
    <div class="panel" id="roomWallet">
      <div class="cap13">Across your wallets</div>
      <div class="money"><span id="balnum">$0</span><span class="pill" id="balpill">+2.6%</span></div>
      <svg id="sparkline" width="320" height="64" viewBox="0 0 320 64" style="margin-top:10px">
        <path id="sparkpath" d="M2,50 C34,46 52,54 76,44 C104,32 118,40 142,34 C170,27 186,36 210,24 C238,10 258,20 284,14 L318,8" fill="none" stroke="${GREEN}" stroke-width="2.5" stroke-linecap="round"/>
        <circle id="sparkdot" cx="2" cy="50" r="4" fill="${GREEN}"/>
      </svg>
      <div class="mover" id="moverline">Mostly ETH · +$310</div>
      <div class="card"><div class="t">Holdings</div>
        <div class="tm" style="height:284px">${TREEMAP.map(([x, y, w, h, s, v, c], k) =>
          `<div class="tmcell" data-k="${k}" style="left:${x}px;top:${y}px;width:${w}px;height:${h}px;background:${c}"><div class="sym">${s}</div><div class="val">${v}</div></div>`).join('')}
        </div>
        <div class="conc" id="concline">ETH is 54% of the book</div>
      </div>
    </div>
    <div class="panel" id="roomSocial" style="opacity:0">
      <div class="newpost" id="newpost" style="opacity:0">
        <div class="post" style="margin-top:0">
          <div class="hd"><span class="av" style="background:#c8842a">S</span>
            <span><span class="nm">sofia</span><br><span class="mt">@sofia · just now</span></span>
            <span class="ctx" style="color:${BLUE}">New</span></div>
          <div class="tx">coffee later? found a place with the good light</div>
        </div>
      </div>
      <div id="oldposts">${POSTS.map(([hue, ini, nm, mt, ctx, chue, tx, lk, rc, imgs], k) => `
        <div class="post" data-k="${k}"${k === 0 ? ' style="margin-top:0"' : ''}>
          <div class="hd"><span class="av" style="background:${hue}">${ini}</span>
            <span><span class="nm">${nm}</span><br><span class="mt">${mt}</span></span>
            <span class="ctx" style="color:${chue}">${ctx}</span></div>
          <div class="tx">${tx}</div>
          ${imgs ? `<div class="imgs"><i style="background:linear-gradient(150deg,#d97b2a,#5a2508)"></i><i style="background:linear-gradient(150deg,#d94f70,#2c1140)"></i></div>` : ''}
          <div class="eng">${HEART}<span class="lk" data-n="${lk}">0</span><span class="gap"></span>${RECAST}<span class="rc" data-n="${rc}">0</span></div>
        </div>`).join('')}
      </div>
    </div>
    ${DROPS.map((d, k) => `<span class="drop" data-k="${k}" style="width:${(d.r * 2) | 0}px;height:${(d.r * 2) | 0}px;background:${d.c};left:${d.x | 0}px;top:0"></span>`).join('')}
    <div class="sweep" id="sweepPhone"></div>
  </div></div>

  <!-- iPad: the media room -->
  <div class="ipad" style="left:${IPAD.x}px;top:${IPAD.y}px"><div class="scr">
    <div class="roomh">Media</div><div class="roomsub">Spotify · YouTube · Podcasts — everything you played, kept</div>
    <div class="shelf">${COVERS.map(([t, g], k) => `<div class="cover" data-k="${k}"><div class="art" style="background:${g}"></div><div class="cl">${t}</div></div>`).join('')}</div>
    <div style="margin-top:8px">${SONGS.map(([t, a, d, hue], k) => `
      <div class="mrow2" data-k="${k}"><span class="art" style="background:linear-gradient(140deg,${hue},#111)"></span>
        <span><span class="tt">${t}</span><br><span class="ar">${a}</span></span><span class="du">${d}</span></div>`).join('')}
    </div>
    <div class="shelf" style="margin-top:12px">${VIDEOS.map(([t, d], k) => `
      <div class="vthumb" data-k="${k}"><div class="fr">${PLAY}<span class="dur">${d}</span></div><div class="vt">${t}</div></div>`).join('')}
    </div>
    <div class="sweep" id="sweepPad"></div>
  </div></div>

  <!-- Mac: Mail beside the brief -->
  <div class="mac" style="left:${MAC.x}px;top:${MAC.y}px">
    <div class="bar"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i><span class="ttl">Casberi</span></div>
    <div class="scr">
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
      </div>
      <div class="sweep" id="sweepMac"></div>
    </div>
  </div>
</div>

<div id="scrim" style="position:absolute;inset:0;background:#000;opacity:0;will-change:opacity"></div>
<div id="conveyor">
  <div class="ckick mono">AND THE REST OF THE READS</div>
  ${CARDS.map(([t, body], k) => `<div class="ccard" data-k="${k}"><div class="gt">${t}</div>${body}</div>`).join('')}
</div>

<div class="outro" id="outro">${berrySVG(130, 'omark')}<div class="b">Casberi</div><div class="u mono">EVERY READ, ON DEVICE — <b>casberi.app</b></div></div>
</div>
<script>
var clamp01=function(v){return Math.max(0,Math.min(1,v));};
var easeOut=function(p){return 1-Math.pow(1-p,3);};
var easeIO=function(p){return p<0.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2;};
var back=function(p){var c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
window.TOTAL=${TOTAL};
var DROPS=${JSON.stringify(DROPS.map(d => ({ x: d.x | 0, delay: +d.delay.toFixed(3), dur: +d.dur.toFixed(3), drift: +d.drift.toFixed(1) })))};

// ---- camera keyframes: {t, cx, cy, s} — world point at frame center -------
var K=[
 {t:0.0, cx:949, cy:410, s:2.35},
 {t:1.35,cx:949, cy:410, s:2.42},
 {t:2.75,cx:949, cy:655, s:2.0},
 {t:3.25,cx:949, cy:655, s:2.04},
 {t:4.15,cx:949, cy:540, s:1.34},
 {t:5.1, cx:949, cy:520, s:1.5},
 {t:6.6, cx:949, cy:645, s:1.52},
 {t:7.0, cx:949, cy:645, s:1.44},
 {t:8.4, cx:2651,cy:505, s:1.8},
 {t:9.7, cx:2651,cy:530, s:1.86},
 {t:10.9,cx:2651,cy:545, s:1.9},
 {t:11.3,cx:2651,cy:545, s:1.84},
 {t:12.5,cx:4165,cy:520, s:1.62},
 {t:13.9,cx:4185,cy:535, s:1.58},
 {t:14.7,cx:4620,cy:540, s:1.62},
 {t:15.9,cx:4620,cy:540, s:1.55},
 {t:20.2,cx:4620,cy:540, s:1.47},
 {t:21.1,cx:949, cy:545, s:1.36},
 {t:23.4,cx:949, cy:560, s:1.44},
 {t:25.0,cx:949, cy:565, s:1.5},
];
function camAt(t){
  if(t<=K[0].t)return K[0];
  for(var i=0;i<K.length-1;i++){
    var a=K[i],b=K[i+1];
    if(t>=a.t&&t<=b.t){
      var p=easeIO(clamp01((t-a.t)/(b.t-a.t)));
      return {cx:a.cx+(b.cx-a.cx)*p, cy:a.cy+(b.cy-a.cy)*p, s:a.s+(b.s-a.s)*p};
    }
  }
  return K[K.length-1];
}
// smooth on/off window with 0.6s shoulders
function win(t,a,b){return clamp01((t-a)/0.6)*(1-clamp01((t-b)/0.6));}
function fmt(n){return '$'+Math.round(n).toLocaleString('en-US');}
function sweep(id,t,at){var p=clamp01((t-at)/0.9);document.getElementById(id).style.transform='translateX('+(-120+p*260)+'%)';}

var world=document.getElementById('world');
var sparkLen=null,curveLen=null;
var T_CONV0=16.5, T_STEP=0.44, CSPACE=690;

window.seek=function(t){
  // ---- camera ----
  var c=camAt(t);
  var cx=c.cx+4*Math.sin(t*0.62), cy=c.cy+3*Math.cos(t*0.81);  // never fully still
  world.style.transform='translate('+(960-cx*c.s)+'px,'+(540-cy*c.s)+'px) scale('+c.s+')';
  // world dims under the conveyor (plus a screen-space scrim), fades for the outro
  var dim=1-0.7*win(t,15.9,20.1);
  var outw=1-clamp01((t-23.4)/0.6);
  world.style.opacity=Math.min(dim,outw);
  document.getElementById('scrim').style.opacity=0.85*win(t,15.9,20.2);
  // device glows follow the camera's subject
  document.getElementById('glowPhone').style.opacity=Math.max(win(t,-1,7.6),win(t,20.4,24))*0.9;
  document.getElementById('glowPad').style.opacity=win(t,7.6,11.7)*0.9;
  document.getElementById('glowMac').style.opacity=win(t,11.7,16.2)*0.9;
  // one reflection sweep per arrival
  sweep('sweepPhone',t,4.2);sweep('sweepPad',t,8.6);sweep('sweepMac',t,12.7);

  // ---- phone: wallet room ----
  var np=easeOut(clamp01((t-0.25)/0.8));
  document.getElementById('balnum').textContent=fmt(48210*np);
  var pp=clamp01((t-1.05)/0.35);
  var pill=document.getElementById('balpill');pill.style.opacity=pp;pill.style.transform='scale('+(0.5+0.5*back(pp))+')';
  var sp=document.getElementById('sparkpath');
  if(sparkLen===null)sparkLen=sp.getTotalLength();
  var spp=easeOut(clamp01((t-0.35)/1.15));
  sp.style.strokeDasharray=sparkLen;sp.style.strokeDashoffset=sparkLen*(1-spp);
  var pt=sp.getPointAtLength(sparkLen*spp);
  var sd=document.getElementById('sparkdot');sd.setAttribute('cx',pt.x);sd.setAttribute('cy',pt.y);sd.style.opacity=spp>0.02&&spp<1?1:0;
  document.getElementById('moverline').style.opacity=clamp01((t-1.6)/0.4);
  var cells=document.querySelectorAll('#roomWallet .tmcell');
  for(var k=0;k<cells.length;k++){var cp=clamp01((t-1.5-k*0.16)/0.45);cells[k].style.opacity=cp;cells[k].style.transform='scale('+(0.82+0.18*back(cp))+')';}
  document.getElementById('concline').style.opacity=clamp01((t-2.85)/0.35);

  // ---- the chip flip IS the edit: Wallet -> Farcaster at 3.45 ----
  var chips=document.querySelectorAll('.fchip');
  var fp=clamp01((t-3.45)/0.55);
  chips[1].style.transform='rotateX('+(360*easeOut(fp))+'deg)';
  var active=fp>0.5?1:0;
  for(var c2=0;c2<chips.length;c2++)chips[c2].className='fchip'+(c2===active?' on':'');
  var swapOut=clamp01((t-3.5)/0.45), swapIn=clamp01((t-3.72)/0.5);
  var rw=document.getElementById('roomWallet');
  rw.style.opacity=1-swapOut;rw.style.transform='translateY('+(-swapOut*44)+'px)';
  var rs=document.getElementById('roomSocial');
  rs.style.opacity=swapIn;

  // ---- phone: social room (posts land, engagement ticks) ----
  var posts=document.querySelectorAll('#oldposts .post');
  for(var p1=0;p1<posts.length;p1++){
    var pp2=clamp01((t-4.0-p1*0.55)/0.5);
    posts[p1].style.opacity=pp2;posts[p1].style.transform='translateY('+((1-back(pp2))*46)+'px)';
    var tick=easeOut(clamp01((t-4.35-p1*0.55)/0.7));
    var lk=posts[p1].querySelector('.lk'),rc=posts[p1].querySelector('.rc');
    lk.textContent=Math.round(parseInt(lk.getAttribute('data-n'))*tick);
    rc.textContent=Math.round(parseInt(rc.getAttribute('data-n'))*tick);
  }
  // pull-to-refresh at 21.0: the feed dips, a new post lands, rain falls
  var dipP=clamp01((t-21.0)/0.55);
  var dip=Math.sin(Math.PI*Math.min(1,dipP))*26;
  var push=easeOut(clamp01((t-21.35)/0.55));
  var op=document.getElementById('oldposts');
  op.style.transform='translateY('+(dip+push*152)+'px)';
  var npst=document.getElementById('newpost');
  npst.style.opacity=clamp01((t-21.45)/0.4);
  npst.style.transform='translateY('+(dip+(1-back(clamp01((t-21.45)/0.5)))*-30)+'px) scale('+(0.94+0.06*back(clamp01((t-21.45)/0.5)))+')';
  // the shower, inside the screen, motion-stretched by speed
  var drops=document.querySelectorAll('.drop');
  for(var d2=0;d2<drops.length;d2++){var dd=DROPS[d2];var pp3=(t-21.15-dd.delay)/dd.dur;
    if(pp3<0||pp3>1){drops[d2].style.opacity=0;continue;}
    var yy=-30+Math.pow(pp3,1.5)*800;
    var stretch=1+0.9*Math.sin(Math.PI*Math.min(1,pp3));
    drops[d2].style.transform='translate('+(dd.drift*pp3)+'px,'+yy+'px) scaleY('+stretch+')';
    drops[d2].style.opacity=Math.min(clamp01(pp3/0.12),1-clamp01((pp3-0.82)/0.18));}

  // ---- iPad: media room (paints as the camera arrives) ----
  var cvs=document.querySelectorAll('.cover');
  for(var c1=0;c1<cvs.length;c1++){var cp1=clamp01((t-7.9-c1*0.16)/0.45);cvs[c1].style.opacity=cp1;cvs[c1].style.transform='scale('+(0.84+0.16*back(cp1))+')';}
  var mr=document.querySelectorAll('.mrow2');
  for(var m1=0;m1<mr.length;m1++){var mp1=clamp01((t-9.3-m1*0.3)/0.45);mr[m1].style.opacity=mp1;mr[m1].style.transform='translateX('+((1-easeOut(mp1))*36)+'px)';}
  var vt=document.querySelectorAll('.vthumb');
  for(var v1=0;v1<vt.length;v1++){var vp1=clamp01((t-10.3-v1*0.2)/0.45);vt[v1].style.opacity=vp1;vt[v1].style.transform='translateY('+((1-back(vp1))*26)+'px)';}

  // ---- Mac: mail lands, then the brief paints as the camera drifts right --
  var rows=document.querySelectorAll('.mailrow');
  for(var r1=0;r1<rows.length;r1++){var rp1=clamp01((t-11.9-r1*0.3)/0.48);rows[r1].style.opacity=rp1;rows[r1].style.transform='translateX('+((1-easeOut(rp1))*-34)+'px)';
    var dt=rows[r1].querySelector('.dot');if(dt&&!dt.classList.contains('z')){var dp1=clamp01((t-12.25-r1*0.3)/0.3);dt.style.transform='scale('+(0.3+0.7*back(dp1))+')';dt.style.opacity=dp1;}}
  var hp2=easeOut(clamp01((t-14.2)/0.85));
  document.getElementById('heronum').textContent=fmt(48210*hp2);
  var hpp=clamp01((t-15.0)/0.3);
  var hpill=document.getElementById('heropill');hpill.style.opacity=hpp;hpill.style.transform='scale('+(0.5+0.5*back(hpp))+')';
  var bars=document.querySelectorAll('#hourbars i');
  for(var k7=0;k7<bars.length;k7++){var bp=clamp01((t-14.5-k7*0.06)/0.45);bars[k7].style.transform='scaleY('+back(bp)+')';}
  document.getElementById('hourlbl').style.opacity=clamp01((t-15.3)/0.35);
  var rp3=easeOut(clamp01((t-14.8)/0.9));
  document.getElementById('ringarc').style.strokeDashoffset=289*(1-0.82*rp3);
  document.getElementById('ringnum').textContent=Math.round(82*rp3);
  var rcv=document.getElementById('ringcurve');
  if(curveLen===null)curveLen=rcv.getTotalLength();
  var rcp=easeOut(clamp01((t-15.1)/0.7));
  rcv.style.strokeDasharray=curveLen;rcv.style.strokeDashoffset=curveLen*(1-rcp);

  // ---- the conveyor ----
  var conv=document.getElementById('conveyor');
  conv.style.opacity=win(t,15.8,20.3);
  var ccards=document.querySelectorAll('.ccard');
  for(var cc=0;cc<ccards.length;cc++){
    var Tk=T_CONV0+cc*T_STEP;
    var x=960+(Tk-t)*1560;                              // 686px between cards — wider than a card, so neighbors never stack
    var f=1-Math.min(1,Math.abs(t-Tk)/0.55);            // focus at center
    ccards[cc].style.transform='translate('+(x-320)+'px,0) scale('+(0.82+0.18*f)+')';
    ccards[cc].style.opacity=(0.14+0.86*f)*conv.style.opacity;
    var prog=clamp01((t-(Tk-0.6))/0.6);
    var grows=ccards[cc].querySelectorAll('.grow');
    for(var g2=0;g2<grows.length;g2++){grows[g2].style.transform='scaleX('+easeOut(clamp01((prog-g2*0.12)/0.8))+')';}
    var fades=ccards[cc].querySelectorAll('.fadein');
    for(var g3=0;g3<fades.length;g3++){fades[g3].style.opacity=clamp01((prog-0.25-g3*0.08)/0.4);}
    var sa=ccards[cc].querySelector('.sarc');
    if(sa)sa.style.strokeDashoffset=176*(1-0.667*easeOut(prog));
  }
  document.querySelector('.ckick').style.opacity=win(t,16.0,20.0)*0.9;

  // ---- outro ----
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-23.6)/0.5));
  var om=document.querySelector('.omark');if(om){var omp=clamp01((t-23.7)/0.6);om.style.transform='scale('+(0.6+0.4*back(omp))+')';om.style.opacity=omp;}
};
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname, 'clip-viz-reel.html'), html);
console.log('wrote clip-viz-reel.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
