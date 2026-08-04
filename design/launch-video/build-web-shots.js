// Device-screen loops for the website's #shots family (phone / iPad / Mac).
// The Mac screen is web-clip-feedstrip (16:10, built by build-web-clips.js);
// this file builds the other two at their shells' exact aspect ratios:
//   web-shot-phone (720x1558, 1242:2688)  — the WALLET VISUALIZATION TOUR:
//     balance + sparkline, the combined treemap, the "In protocols"
//     composition strip, the veAERO melt bar, Worth a look. One scrolling
//     column that wraps exactly once over TOTAL -> seamless loop.
//   web-shot-pad (768x1024, ~2048:2732)   — the split view: feed scrolling
//     left (seamless), a visualization pane pinned right (posting-activity
//     heatmap + topic map), matching the iPad's side-panel layout.
//   node build-web-shots.js
//   node render.js web-shot-phone.html --size=720x1558
//   node render.js web-shot-pad.html --size=768x1024
const fs = require('fs'), path = require('path');

const INK = '#0b0910', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF', VIOLET = '#855dcd';

const BASE = (w, h, body, script, extra) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:${w}px;height:${h}px;overflow:hidden;background:${INK};
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#fff;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
${extra||''}
</style></head><body>
${body}
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3);
${script}
window.seek(0);
</script></body></html>`;

/* ------------------------------- PHONE --------------------------------- */
// One column of wallet cards, duplicated, scrolling its own height once per
// TOTAL. Every card is a visualization the app really draws.
const PCARDS = `
<div class="pc">
  <div class="plbl">Across your wallets</div>
  <div class="pbig">$96,812 <span class="ppill">▲ 2.1%</span></div>
  <svg width="100%" height="90" viewBox="0 0 600 90" preserveAspectRatio="none"><path d="M0 70 L75 62 L150 66 L225 46 L300 52 L375 30 L450 36 L525 16 L600 10" fill="none" stroke="${GREEN}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/></svg>
</div>
<div class="pc">
  <div class="plbl">What you hold</div>
  <div class="ptree">
    <span style="left:0;top:0;width:55%;height:100%;background:#4a63d8"><b>ETH</b><i>$48K</i></span>
    <span style="left:56.5%;top:0;width:43.5%;height:47%;background:#2775ca"><b>USDC</b><i>$19K</i></span>
    <span style="left:56.5%;top:49%;width:24%;height:51%;background:#14f195"><b>SOL</b><i>$11K</i></span>
    <span style="left:81.5%;top:49%;width:18.5%;height:51%;background:#f7931a"><b>WBTC</b><i>$8K</i></span>
  </div>
</div>
<div class="pc">
  <div class="plbl">In protocols</div>
  <div class="prow"><span>Deposited</span><b>$41.6K</b></div>
  <div class="pbar"><i style="width:72%;background:#9391f7"></i></div>
  <div class="prow"><span>Locked</span><b>12,977 AERO</b></div>
  <div class="pbar"><i style="width:41%;background:#0434ff"></i></div>
  <div class="psub">veAERO melts — 41% voting power left</div>
  <div class="prow"><span>Owed</span><b>$6,100</b></div>
  <div class="pbar"><i style="width:18%;background:${RED}"></i></div>
</div>
<div class="pc">
  <div class="plbl">Worth a look</div>
  <div class="pap"><span class="pwarn">!</span><div><div class="pttl">Unlimited USDC approval</div><div class="psub2">Reaches $12,400 · revoke</div></div></div>
  <div class="pap"><span class="pwarn">!</span><div><div class="pttl">Old router, still approved</div><div class="psub2">Reaches $1,120</div></div></div>
</div>
<div class="pc">
  <div class="plbl">Lending health</div>
  <div class="pap"><span class="pdot" style="background:#9391f7"></span><div><div class="pttl">Aave · health 2.4</div><div class="psub2">$18,200 supplied</div></div></div>
  <div class="pap"><span class="pdot" style="background:#2a73ff"></span><div><div class="pttl">Morpho · health 1.9</div><div class="psub2">$9,400 in the ETH vault</div></div></div>
</div>`;
const phone = () => BASE(720, 1558, `
<div class="chips">
  <span class="cc av"></span><span class="cc"><b>All</b></span><span class="cc on" style="background:#2962ef"><i></i></span><span class="cc"><i style="background:#855dcd"></i></span><span class="cc"><i style="background:#0a84ff"></i></span>
</div>
<div class="scroller"><div class="inner">${PCARDS}${PCARDS}</div></div>
<div class="fade top"></div><div class="fade bot"></div>`,
`window.TOTAL=16;
window.seek=function(t){
  const inner=document.querySelector('.inner');
  const half=inner.scrollHeight/2;
  const y=((t/window.TOTAL)*half)%half;
  inner.style.transform='translateY('+(-y)+'px)';
};`,
`
.chips{position:absolute;top:0;left:0;right:0;z-index:4;display:flex;align-items:center;gap:14px;padding:80px 34px 22px;background:linear-gradient(to bottom, rgba(21,26,46,.98) 55%, rgba(11,9,16,0));}
.cc{width:64px;height:64px;border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;}
.cc.av{background:#fff;} .cc i{width:22px;height:22px;border-radius:50%;display:block;background:#fff;}
.cc b{font-size:22px;color:rgba(255,255,255,.8);}
.cc.on{box-shadow:0 0 0 3px rgba(255,255,255,.2);}
.scroller{position:absolute;inset:150px 0 0;overflow:hidden;}
.inner{padding:40px 34px;will-change:transform;}
.pc{background:rgba(255,255,255,.055);border-radius:26px;padding:30px;margin-bottom:30px;}
.plbl{font-size:21px;font-weight:700;color:rgba(255,255,255,.42);margin-bottom:14px;}
.pbig{font-size:56px;font-weight:800;letter-spacing:-.025em;margin-bottom:16px;}
.ppill{font-size:21px;font-weight:750;padding:8px 16px;border-radius:100px;background:rgba(63,185,80,.16);color:${GREEN};vertical-align:middle;}
.ptree{position:relative;height:330px;border-radius:18px;overflow:hidden;}
.ptree span{position:absolute;border-radius:13px;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 0 0 0 2px rgba(0,0,0,.2);}
.ptree b{font-size:26px;font-weight:800;} .ptree i{font-style:normal;font-size:18px;color:rgba(255,255,255,.8);margin-top:4px;}
.prow{display:flex;justify-content:space-between;font-size:22px;font-weight:650;margin-top:16px;}
.prow span{color:rgba(255,255,255,.6);} .prow b{font-weight:750;}
.pbar{height:14px;border-radius:8px;background:rgba(255,255,255,.08);margin-top:10px;overflow:hidden;}
.pbar i{display:block;height:100%;border-radius:8px;}
.psub{font-size:18px;color:rgba(255,255,255,.42);margin-top:8px;}
.pap{display:flex;align-items:center;gap:16px;padding:14px 0;}
.pwarn{width:46px;height:46px;border-radius:50%;background:rgba(255,159,10,.18);color:#ff9f0a;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:24px;flex:none;}
.pdot{width:15px;height:15px;border-radius:50%;flex:none;margin:0 15px;}
.pttl{font-size:23px;font-weight:700;}
.psub2{font-size:18px;color:rgba(255,255,255,.44);margin-top:3px;}
.fade{position:absolute;left:0;right:0;height:90px;z-index:3;pointer-events:none;}
.fade.top{top:150px;background:linear-gradient(to bottom,${INK},rgba(11,9,16,0));}
.fade.bot{bottom:0;background:linear-gradient(to top,${INK},rgba(11,9,16,0));}
`);

/* -------------------------------- IPAD --------------------------------- */
// Feed scrolls left (seamless); the right pane is a pinned visualization
// detail (posting heatmap + topic map) — static by design so the loop's only
// moving part wraps cleanly.
const FROWS = `
<div class="frow"><span class="favx"></span><div class="fcol"><div class="fbar" style="width:78%"></div><div class="fbar s" style="width:50%"></div></div></div>
<div class="frow"><span class="fdot" style="background:#2962ef"></span><div class="fcol"><div class="fam">+0.42 ETH</div><div class="fsb">$1,284 · Base</div></div></div>
<div class="frow"><span class="fth"></span><div class="fcol"><div class="ftt">Screenshot · 2:14pm</div><div class="fbar s" style="width:38%"></div></div></div>
<div class="frow"><span class="favx" style="background:rgba(255,255,255,.08)"></span><div class="fcol"><div class="fbar" style="width:64%"></div><div class="fbar s" style="width:40%"></div></div></div>
<div class="frow"><span class="fdot" style="background:#ff6719"></span><div class="fcol"><div class="ftt">Why local-first won</div><div class="fsb">RSS</div></div></div>
<div class="frow"><span class="fth" style="background:linear-gradient(140deg,#b06ab3,#4568dc)"></span><div class="fcol"><div class="ftt">Daily doodle 2018.</div><div class="fsb">Farcaster · /art</div></div></div>`;
const pad = () => BASE(768, 1024, `
<div class="left">
  <div class="lhd"><span class="lcc av"></span><span class="lcc on"><b>All</b></span><span class="lcc"><i style="background:#855dcd"></i></span><span class="lcc"><i style="background:#2962ef"></i></span></div>
  <div class="lscroll"><div class="linner">${FROWS}${FROWS}</div></div>
</div>
<div class="right">
  <div class="rlbl mono">POSTING ACTIVITY</div>
  <div class="rheat">${Array.from({length: 84}).map((_, k) => `<i style="background:rgba(63,185,80,${((k*2654435761)>>>0)%97<40 ? (0.18 + (((k*40503)>>>0)%62)/100) : 0.06})"></i>`).join('')}</div>
  <div class="rlbl mono" style="margin-top:34px">WHAT YOUR SCREENSHOTS SAY</div>
  <div class="rmap">
    <span style="flex:3.2;background:rgba(74,99,216,.85)">figma.com</span>
    <span style="flex:2.1;background:rgba(133,93,205,.8)">recipes</span>
    <span style="flex:1.5;background:rgba(63,185,80,.7)">receipts</span>
    <span style="flex:1.2;background:rgba(255,159,10,.65)">flights</span>
  </div>
  <div class="rcap">Read on-device — the search never leaves it.</div>
</div>`,
`window.TOTAL=14;
window.seek=function(t){
  const inner=document.querySelector('.linner');
  const half=inner.scrollHeight/2;
  const y=((t/window.TOTAL)*half)%half;
  inner.style.transform='translateY('+(-y)+'px)';
};`,
`
.left{position:absolute;left:0;top:0;bottom:0;width:57%;border-right:1px solid rgba(255,255,255,.06);}
.lhd{display:flex;align-items:center;gap:11px;padding:40px 26px 18px;position:relative;z-index:4;background:linear-gradient(to bottom, rgba(21,26,46,.98) 60%, rgba(11,9,16,0));}
.lcc{width:48px;height:48px;border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;}
.lcc.av{background:#fff;} .lcc i{width:17px;height:17px;border-radius:50%;display:block;}
.lcc b{font-size:17px;color:#fff;} .lcc.on{background:rgba(255,255,255,.26);box-shadow:0 0 0 3px rgba(255,255,255,.16);}
.lscroll{position:absolute;inset:106px 0 0;overflow:hidden;}
.linner{padding:16px 26px;will-change:transform;}
.frow{display:flex;align-items:center;gap:13px;padding:13px 0;}
.fcol{flex:1;min-width:0;}
.favx{width:42px;height:42px;border-radius:50%;background:rgba(255,255,255,.15);flex:none;}
.fth{width:42px;height:42px;border-radius:11px;background:linear-gradient(140deg,#3b4d70,#1e2a42);flex:none;}
.fdot{width:11px;height:11px;border-radius:50%;flex:none;margin:0 15px;}
.fbar{height:10px;border-radius:6px;background:rgba(255,255,255,.24);}
.fbar.s{height:8px;background:rgba(255,255,255,.12);margin-top:7px;}
.ftt{font-size:18px;font-weight:650;}
.fsb{font-size:15px;color:rgba(255,255,255,.44);margin-top:2px;}
.fam{font-size:19px;font-weight:750;color:${GREEN};}
.right{position:absolute;right:0;top:0;bottom:0;width:43%;padding:52px 30px 0;background:rgba(255,255,255,.025);}
.rlbl{font-size:14px;letter-spacing:.13em;color:rgba(255,255,255,.4);font-weight:650;margin-bottom:16px;}
.rheat{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;}
.rheat i{aspect-ratio:1;border-radius:4px;display:block;}
.rmap{display:flex;flex-direction:column;gap:8px;height:300px;}
.rmap span{border-radius:12px;display:flex;align-items:flex-end;padding:12px;font-size:17px;font-weight:750;}
.rcap{margin-top:20px;font-size:15px;color:rgba(255,255,255,.42);font-weight:600;line-height:1.4;}
`);

fs.writeFileSync(path.join(__dirname, 'web-shot-phone.html'), phone());
fs.writeFileSync(path.join(__dirname, 'web-shot-pad.html'), pad());
console.log('wrote web-shot-phone.html, web-shot-pad.html');
