// Website section clips — pure HTML-animated UI (no sim recordings, no
// screenshots). Four loops for casberi.app, replacing the 2026-07 sim
// captures whose UI has since drifted:
//   web-connect   (720x1280)  "Just connect": catalog tiles -> rows landing
//   web-keeptabs  (720x1280)  "Keep tabs": treemap -> sparkline -> heatmap -> approvals
//   web-agent     (720x1280)  "One agent": the Today brief painting itself
//   web-feedstrip (1600x1000) hero strip: the feed scrolling through a day
//                             (seamless loop — columns wrap exactly once)
// Content is grounded in the real screens: the brief mirrors the user's own
// Mac capture (What's going on / $95K / Send Lisbon dates to Sam), the
// wallet numbers match the shipped demo scale, row shapes match FeedScreen.
//   node build-web-clips.js            writes all four HTML files
//   node render.js web-clip-<name>.html --size=WxH   then ffmpeg each
const fs = require('fs'), path = require('path');

const INK = '#0b0910', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF', VIOLET = '#855dcd';

const BASE = (w, h, body, script, extra) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:${w}px;height:${h}px;overflow:hidden;background:${INK};
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#fff;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.pour{position:absolute;left:0;right:0;top:0;height:${Math.round(h*0.24)}px;background:linear-gradient(to bottom, rgba(46,99,255,.24), rgba(0,0,0,0));}
${extra||''}
</style></head><body>
${body}
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.6;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
function pop(el,p,from,dur,dy){const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy==null?18:dy))+'px)';return rp;}
${script}
window.seek(0);
</script></body></html>`;

// The chip strip every phone clip wears — the app's real top-of-screen shape.
const CHIPS = (active) => {
  const dots = [
    ['All', 'rgba(255,255,255,.5)'], ['#2962ef'], ['#0a84ff'], ['#ff453a'], ['#855dcd'], ['#ff4500'],
  ];
  let out = `<div class="chips">`;
  out += `<span class="cc av"><svg width="26" height="26" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="#14110d"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="#14110d"/></svg></span>`;
  out += `<span class="cc gr"><svg width="24" height="24" viewBox="0 0 24 24" fill="rgba(255,255,255,.75)"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg></span>`;
  dots.forEach((d, i) => {
    const isAll = d[0] === 'All';
    const on = (isAll && active === 'All') || (!isAll && active === i);
    out += `<span class="cc ${on ? 'on' : ''}" ${on ? `style="background:${isAll ? 'rgba(255,255,255,.28)' : d[0]}"` : ''}>${
      isAll ? `<b style="font-size:21px;color:#fff">All</b>` : `<i style="background:${on ? '#fff' : d[0]}"></i>`}</span>`;
  });
  return out + `</div>`;
};

const PHONE_CSS = `
.chips{display:flex;align-items:center;gap:13px;padding:64px 30px 22px;}
.cc{width:62px;height:62px;border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;}
.cc.av{background:#fff;} .cc i{width:22px;height:22px;border-radius:50%;display:block;}
.cc.on{box-shadow:0 0 0 3px rgba(255,255,255,.18);}
.sect{font-size:22px;font-weight:700;color:rgba(255,255,255,.42);margin:20px 32px 6px;}
.sect em{font-style:normal;color:rgba(255,255,255,.26);margin-left:8px;}
.row{display:flex;align-items:center;gap:16px;padding:15px 32px;will-change:opacity,transform;}
.row .col{flex:1;min-width:0;}
.avx{width:52px;height:52px;border-radius:50%;background:rgba(255,255,255,.15);flex:none;}
.thumb{width:52px;height:52px;border-radius:13px;background:linear-gradient(140deg,#3b4d70,#1e2a42);flex:none;}
.dot{width:13px;height:13px;border-radius:50%;flex:none;margin:0 19px;}
.bar{height:12px;border-radius:7px;background:rgba(255,255,255,.24);}
.bar.s{height:10px;background:rgba(255,255,255,.12);margin-top:8px;}
.ttl{font-size:23px;font-weight:650;}
.sub2{font-size:19px;color:rgba(255,255,255,.44);margin-top:3px;}
.amt{font-size:25px;font-weight:750;}
.src{margin-left:auto;font-size:17px;color:rgba(255,255,255,.32);font-weight:600;flex:none;}
.time{font-size:20px;font-weight:700;color:rgba(255,255,255,.55);width:56px;flex:none;}
.vbar{width:6px;height:38px;border-radius:4px;flex:none;}
`;

/* ============================== A. CONNECT ============================== */
const APPS20 = [
  'conic-gradient(#ff453a,#ff9f0a,#ffd60a,#30d158,#64d2ff,#0a84ff,#bf5af2,#ff453a)',
  '#2962ef', '#855dcd', '#0085ff', '#1db954', '#24292f', '#ff4500', '#ff0000',
  '#d97757', '#5e6ad2', '#e44332', '#fc4c02', '#9146ff', '#4fae7b', '#ff6719',
  '#e60023', '#0052ff', '#2081e2', '#006bff', '#F6821F',
];
const connect = () => BASE(720, 1280, `
<div class="pour"></div>
<div id="cat">
  <div class="sect" style="margin-top:80px">The catalog <em>60+</em></div>
  <div class="agrid">${APPS20.map((c, i) => `<span class="at" data-i="${i}" style="background:${c}"></span>`).join('')}</div>
  <div class="hint" id="hint">Tap to connect — no account, no sign-up</div>
</div>
<div id="feed" style="opacity:0">
  ${CHIPS('All')}
  <div class="sect">Today <em id="cnt">0</em></div>
  <div class="row" data-r="0"><span class="avx"></span><div class="col"><div class="bar" style="width:72%"></div><div class="bar s" style="width:46%"></div></div><span class="src">Farcaster</span></div>
  <div class="row" data-r="1"><span class="dot" style="background:#2962ef"></span><div class="col"><div class="amt" style="color:${GREEN}">+0.42 ETH</div><div class="sub2">$1,284.00 · Base</div></div><span class="src">Wallet</span></div>
  <div class="row" data-r="2"><span class="thumb"></span><div class="col"><div class="ttl">Screenshot · 2:14pm</div><div class="bar s" style="width:40%"></div></div><span class="src">Photos</span></div>
  <div class="row" data-r="3"><span class="time">4:30</span><span class="vbar" style="background:${RED}"></span><div class="col"><div class="ttl">Design review</div><div class="bar s" style="width:34%"></div></div><span class="src">Calendar</span></div>
  <div class="row" data-r="4"><span class="avx" style="background:rgba(255,255,255,.08)"></span><div class="col"><div class="bar" style="width:60%"></div><div class="bar s" style="width:42%"></div></div><span class="src">Bluesky</span></div>
  <div class="row" data-r="5"><span class="dot" style="background:#ff6719"></span><div class="col"><div class="ttl">Why local-first won</div><div class="sub2">A newsletter you follow</div></div><span class="src">RSS</span></div>
</div>`,
`window.TOTAL=9.0;
const rows=[...document.querySelectorAll('#feed .row')];
window.seek=function(t){
  const cat=document.getElementById('cat'),feed=document.getElementById('feed');
  // catalog phase
  const catIn=clamp01(t/0.4), catOut=1-clamp01((t-2.9)/0.4);
  cat.style.opacity=Math.min(catIn,catOut);
  document.querySelectorAll('#cat .at').forEach((a,i)=>{
    const rp=clamp01((t-0.15-(i%5)*0.05-Math.floor(i/5)*0.09)/0.4);
    a.style.opacity=rp;a.style.transform='scale('+(0.6+0.4*back(rp))+')';
    if(i===2){ // the tapped tile pulses before the switch
      const pu=clamp01((t-2.1)/0.5);
      a.style.boxShadow='0 0 0 '+(pu*10)+'px rgba(133,93,205,'+(0.5*(1-pu))+')';
    }
  });
  document.getElementById('hint').style.opacity=clamp01((t-1.2)/0.4)*catOut;
  // feed phase
  const fIn=clamp01((t-3.2)/0.35), fOut=1-clamp01((t-8.55)/0.45);
  feed.style.opacity=Math.min(fIn,fOut);
  let landed=0;
  rows.forEach((r,i)=>{const rp=pop(r,t,3.5+i*0.55,0.5,26);if(rp>0.5)landed++;});
  document.getElementById('cnt').textContent=landed;
};`,
PHONE_CSS + `
.agrid{display:grid;grid-template-columns:repeat(5,1fr);gap:18px;padding:16px 32px;}
.at{aspect-ratio:1;border-radius:22%;display:block;box-shadow:0 6px 14px rgba(0,0,0,.35);will-change:transform,opacity;}
.hint{margin:28px 32px 0;text-align:center;font-size:21px;font-weight:650;color:rgba(255,255,255,.45);}
#cat,#feed{position:absolute;inset:0;will-change:opacity;}
`);

/* ============================= B. KEEP TABS ============================= */
const TREE2 = [
  { s: 'ETH',  v: '$48K', x: 0,    y: 0,  w: 55,   h: 100, c: '#4a63d8', f: 34 },
  { s: 'USDC', v: '$19K', x: 56.5, y: 0,  w: 43.5, h: 47,  c: '#2775ca', f: 27 },
  { s: 'SOL',  v: '$11K', x: 56.5, y: 49, w: 24,   h: 51,  c: '#14f195', f: 23 },
  { s: 'WBTC', v: '$8K',  x: 81.5, y: 49, w: 18.5, h: 30,  c: '#f7931a', f: 19 },
  { s: '+14',  v: '',     x: 81.5, y: 81, w: 18.5, h: 19,  c: 'rgba(255,255,255,.16)', f: 17 },
];
const keeptabs = () => BASE(720, 1280, `
<div class="pour" style="background:linear-gradient(to bottom, rgba(63,185,80,.2), rgba(0,0,0,0))"></div>
<div class="scene" id="s0">
  <div class="lbl mono">WHAT YOU HOLD</div>
  <div class="tree">${TREE2.map((c, i) => `<span class="tc" data-i="${i}" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${c.c}"><b style="font-size:${c.f}px">${c.s}</b>${c.v ? `<i style="font-size:${Math.round(c.f*0.62)}px">${c.v}</i>` : ''}</span>`).join('')}</div>
  <div class="cap">Every wallet you watch, one map — read-only.</div>
</div>
<div class="scene" id="s1" style="opacity:0">
  <div class="lbl mono">ACROSS YOUR WALLETS</div>
  <div class="bign" id="bign">$0</div>
  <div class="pill" id="pill">▲ 2.1% today</div>
  <div class="sparkwrap"><svg width="100%" height="150" viewBox="0 0 640 150" preserveAspectRatio="none"><defs><clipPath id="cp"><rect id="cprect" x="0" y="0" width="0" height="150"/></clipPath></defs><path clip-path="url(#cp)" d="M0 118 L80 104 L160 112 L240 78 L320 88 L400 52 L480 62 L560 30 L640 18" fill="none" stroke="${GREEN}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
  <div class="cap">The line starts once a second reading lands.</div>
</div>
<div class="scene" id="s2" style="opacity:0">
  <div class="lbl mono">POSTING ACTIVITY</div>
  <div class="heat" id="heat">${Array.from({length: 112}).map((_, i) => `<span data-i="${i}"></span>`).join('')}</div>
  <div class="cap">Anyone you follow — how they actually show up.</div>
</div>
<div class="scene" id="s3" style="opacity:0">
  <div class="lbl mono">WORTH A LOOK</div>
  <div class="ap" data-i="0"><span class="warn">!</span><div class="col"><div class="ttl">Unlimited USDC approval</div><div class="sub2">Reaches $12,400 · granted 2026-06-02</div></div></div>
  <div class="ap" data-i="1"><span class="warn">!</span><div class="col"><div class="ttl">Old router, still approved</div><div class="sub2">Reaches $1,120 · granted 2025-11-18</div></div></div>
  <div class="ap" data-i="2"><span class="warn" style="opacity:.6">!</span><div class="col"><div class="ttl">NFT operator approval</div><div class="sub2">Reaches nothing it can spend</div></div></div>
  <div class="cap">Ranked by what each one could actually reach.</div>
</div>`,
`window.TOTAL=10.4;
const S=[[0,2.6],[2.6,5.2],[5.2,7.8],[7.8,10.4]];
window.seek=function(t){
  S.forEach((w,i)=>{
    const el=document.getElementById('s'+i);
    const inn=clamp01((t-w[0])/0.35), out=1-clamp01((t-(w[1]-0.35))/0.35);
    el.style.opacity=Math.min(inn,out);
    const p=clamp01((t-w[0]-0.15)/(w[1]-w[0]-0.5));
    if(i===0){document.querySelectorAll('#s0 .tc').forEach((c,k)=>{const rp=clamp01((p-k*0.1)/0.3);c.style.opacity=rp;c.style.transform='scale('+(0.7+0.3*back(rp))+')';});}
    if(i===1){const n=Math.round(96812*easeOut(clamp01(p/0.55)));document.getElementById('bign').textContent='$'+n.toLocaleString('en-US');
      document.getElementById('pill').style.opacity=clamp01((p-0.55)/0.2);
      document.getElementById('cprect').setAttribute('width',String(640*easeOut(clamp01(p/0.8))));}
    if(i===2){document.querySelectorAll('#heat span').forEach((c,k)=>{
      const on=((k*2654435761)>>>0)%97<38;const rp=clamp01((p-(((k*40503)>>>0)%100)/100*0.7)/0.2);
      c.style.background=on?'rgba(63,185,80,'+(0.15+0.75*rp)+')':'rgba(255,255,255,.06)';});}
    if(i===3){document.querySelectorAll('#s3 .ap').forEach((r,k)=>{pop(r,p,0.06+k*0.18,0.3,22);});}
    const cap=el.querySelector('.cap');if(cap)cap.style.opacity=clamp01((p-0.55)/0.25);
  });
};`,
PHONE_CSS + `
.scene{position:absolute;inset:0;padding:120px 40px 0;will-change:opacity;}
.lbl{font-size:20px;letter-spacing:.14em;color:rgba(255,255,255,.4);font-weight:650;margin-bottom:26px;}
.tree{position:relative;height:560px;border-radius:24px;overflow:hidden;}
.tc{position:absolute;border-radius:16px;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 0 0 0 2px rgba(0,0,0,.2);will-change:transform,opacity;}
.tc b{font-weight:800;color:#fff;} .tc i{font-style:normal;color:rgba(255,255,255,.82);margin-top:5px;font-weight:600;}
.cap{margin-top:34px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.bign{font-size:96px;font-weight:800;letter-spacing:-.03em;}
.pill{display:inline-block;margin-top:14px;font-size:23px;font-weight:750;padding:9px 20px;border-radius:100px;background:rgba(63,185,80,.16);color:${GREEN};will-change:opacity;}
.sparkwrap{margin-top:44px;}
.heat{display:grid;grid-template-columns:repeat(16,1fr);gap:9px;margin-top:8px;}
.heat span{aspect-ratio:1;border-radius:5px;background:rgba(255,255,255,.06);display:block;}
.ap{display:flex;align-items:center;gap:18px;padding:20px 0;will-change:opacity,transform;}
.warn{width:50px;height:50px;border-radius:50%;background:rgba(255,159,10,.18);color:#ff9f0a;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:26px;flex:none;}
`);

/* =============================== C. AGENT =============================== */
const agent = () => BASE(720, 1280, `
<div class="pour"></div>
<div class="brief">
  <div class="eyeb" id="eyeb">today so far</div>
  <div class="bh" id="bh">What's going on</div>
  <div class="bd" id="bd">Saturday, August 1</div>
  <div class="lede" id="lede">Book dentist is overdue.</div>
  <div class="card" id="money">
    <div class="mn" id="mn">$0</div>
    <div class="mrow">
      <span class="mtile" style="flex:2.2;background:linear-gradient(120deg,#3b4dd8,#26327e)"><b>ETH</b><i>$19K</i></span>
      <span class="mcol">
        <span class="mrowi"><b>AWETH</b><i>$96</i></span>
        <span class="mrowi"><b>MATIC</b><i>$85</i></span>
      </span>
    </div>
    <div class="msub" id="msub">20 transactions settled</div>
  </div>
  <div class="card" id="next">
    <div class="nlbl">Up next</div>
    <div class="nttl">Send Lisbon dates to Sam</div>
    <div class="nsub">Mon 11:00 AM</div>
    <div class="nred">3 more overdue</div>
  </div>
  <div class="chiprow" id="chiprow">
    <span class="ask">⊙ Show Book club</span><span class="ask">✦ Noticed</span><span class="ask">▦ What's this week?</span>
  </div>
  <div class="composer" id="composer"><span>Ask about this…</span><span class="mic"><svg width="24" height="24" viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3" fill="${BLUE}"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" stroke="${BLUE}" stroke-width="2" fill="none" stroke-linecap="round"/></svg></span></div>
</div>`,
`window.TOTAL=9.6;
window.seek=function(t){
  const out=1-clamp01((t-9.15)/0.45);
  document.querySelector('.brief').style.opacity=out;
  pop(document.getElementById('eyeb'),t,0.2,0.4,12);
  pop(document.getElementById('bh'),t,0.35,0.5,20);
  pop(document.getElementById('bd'),t,0.55,0.4,12);
  pop(document.getElementById('lede'),t,0.9,0.5,16);
  const mp=pop(document.getElementById('money'),t,1.6,0.6,30);
  const n=Math.round(95000*easeOut(clamp01((t-1.9)/1.1)));
  document.getElementById('mn').textContent='$'+(n>=1000?Math.round(n/1000)+'K':n);
  document.getElementById('msub').style.opacity=clamp01((t-2.9)/0.4);
  pop(document.getElementById('next'),t,3.6,0.6,30);
  pop(document.getElementById('chiprow'),t,4.7,0.5,20);
  pop(document.getElementById('composer'),t,5.3,0.5,20);
};`,
`
.brief{position:absolute;inset:0;padding:100px 44px 0;will-change:opacity;}
.eyeb{font-size:21px;color:rgba(255,255,255,.42);font-weight:650;will-change:opacity,transform;}
.bh{font-size:52px;font-weight:800;letter-spacing:-.02em;margin-top:6px;will-change:opacity,transform;}
.bd{font-size:21px;color:rgba(255,255,255,.42);font-weight:600;margin-top:8px;will-change:opacity,transform;}
.lede{font-size:34px;font-weight:800;margin-top:18px;will-change:opacity,transform;}
.card{background:rgba(255,255,255,.055);border-radius:24px;padding:28px;margin-top:26px;will-change:opacity,transform;}
.mn{font-size:64px;font-weight:800;letter-spacing:-.03em;}
.mrow{display:flex;gap:12px;margin-top:18px;height:150px;}
.mtile{border-radius:14px;display:flex;flex-direction:column;align-items:flex-start;justify-content:flex-end;padding:14px;}
.mtile b{font-size:22px;font-weight:800;} .mtile i{font-style:normal;font-size:18px;color:rgba(255,255,255,.75);margin-top:2px;}
.mcol{flex:1;display:flex;flex-direction:column;gap:10px;}
.mrowi{flex:1;border-radius:12px;background:rgba(255,255,255,.07);display:flex;flex-direction:column;justify-content:center;padding:0 14px;}
.mrowi b{font-size:16px;font-weight:750;} .mrowi i{font-style:normal;font-size:14px;color:rgba(255,255,255,.5);}
.msub{margin-top:16px;font-size:20px;color:rgba(255,255,255,.5);font-weight:600;will-change:opacity;}
.nlbl{font-size:19px;color:rgba(255,255,255,.42);font-weight:650;}
.nttl{font-size:27px;font-weight:750;margin-top:8px;}
.nsub{font-size:20px;color:rgba(255,255,255,.5);margin-top:5px;}
.nred{font-size:20px;color:${RED};font-weight:700;margin-top:12px;}
.chiprow{display:flex;gap:12px;margin-top:30px;flex-wrap:wrap;will-change:opacity,transform;}
.ask{font-size:19px;font-weight:650;padding:12px 18px;border-radius:100px;background:rgba(255,255,255,.09);}
.composer{position:absolute;left:44px;right:44px;bottom:44px;display:flex;align-items:center;justify-content:space-between;background:rgba(255,255,255,.1);border-radius:100px;padding:19px 26px;font-size:22px;font-weight:600;color:rgba(255,255,255,.55);box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);will-change:opacity,transform;}
`);

/* ============================ D. FEED STRIP ============================= */
// Three columns scrolling at different speeds. Each column's content block
// repeats exactly twice and scrolls its own height over an integer number of
// cycles in TOTAL seconds -> the loop is mathematically seamless.
const CARD = (inner, cls) => `<div class="fc ${cls || ''}">${inner}</div>`;
const col0 = [
  CARD(`<div class="fhd"><span class="fdot" style="background:#2962ef"></span>Wallet</div><div class="famt">+0.42 ETH</div><div class="fsub">$1,284.00 · Base</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:${VIOLET}"></span>Farcaster · /art</div><div class="fimg" style="background:linear-gradient(130deg,#b06ab3,#4568dc)"></div><div class="fttl">Daily doodle 2018.</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#ff9f0a"></span>Reminders</div><div class="fttl">Send Lisbon dates to Sam</div><div class="fsub">Mon 11:00 AM</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#1db954"></span>Spotify</div><div class="fttl">Saved 3 songs</div><div class="fsub">Liked from the car</div>`),
];
const VIZCARDS = [
  CARD(`<div class="fhd"><span class="fdot" style="background:#2962ef"></span>What you hold</div><div class="minitree"><span style="flex:5;background:#4a63d8"><b>ETH</b></span><span style="flex:2.2;background:#2775ca"><b>USDC</b></span><span style="flex:1.4;background:#14f195"><b>SOL</b></span></div><div class="fsub">$95K across 18 tokens in 2 wallets</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#0434ff"></span>Aerodrome</div><div class="fttl">veAERO — 41% voting power left</div><div class="melt"><i style="width:41%"></i></div><div class="fsub">12,977 AERO locked · melts to 2028</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:${VIOLET}"></span>Posting activity</div><div class="miniheat">${Array.from({length: 48}).map((_, k) => `<i style="background:rgba(63,185,80,${((k*2654435761)>>>0)%97<40 ? (0.2 + (((k*40503)>>>0)%60)/100) : 0.06})"></i>`).join('')}</div>`),
];
const col1 = [
  CARD(`<div class="fhd"><span class="fdot" style="background:${BLUE}"></span>Today</div><div class="fbig">$95K</div><div class="fsub">Across your wallets · ▲ 2.1%</div><svg width="100%" height="54" viewBox="0 0 300 54" preserveAspectRatio="none"><path d="M0 42 L40 36 L80 40 L120 26 L160 30 L200 18 L240 22 L300 8" fill="none" stroke="${GREEN}" stroke-width="4" stroke-linecap="round"/></svg>`, 'tall'),
  CARD(`<div class="fhd"><span class="fdot" style="background:#0a84ff"></span>Photos</div><div class="fgrid"><i style="background:linear-gradient(140deg,#3b4d70,#1e2a42)"></i><i style="background:linear-gradient(140deg,#704a3b,#42281e)"></i><i style="background:linear-gradient(140deg,#3b7053,#1e422c)"></i></div><div class="fsub">3 screenshots, read on-device</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#FFD21E"></span>Hugging Face</div><div class="fttl">Scaling Laws for Sparse MoE</div><div class="fsub">Daily Papers · abstract saved</div>`),
];
col0.splice(2, 0, VIZCARDS[1]);
col1.splice(1, 0, VIZCARDS[0]);
const col2 = [
  CARD(`<div class="fhd"><span class="fdot" style="background:${RED}"></span>Calendar</div><div class="fttl">Design review</div><div class="fsub">Today · 4:30 PM</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#0085ff"></span>Bluesky</div><div class="fbars"><span style="width:84%"></span><span style="width:58%"></span></div><div class="fsub">From someone you follow</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#F6821F"></span>Cloudflare</div><div class="fttl">TLS cert expires in 12 days</div><div class="fsub">yoursite.com — before the browser warning</div>`),
  CARD(`<div class="fhd"><span class="fdot" style="background:#24292f"></span>GitHub</div><div class="fttl">Merged #412</div><div class="fsub">casberi/casberi</div>`),
];
col2.splice(2, 0, VIZCARDS[2]);
const feedstrip = () => BASE(1600, 1000, `
<div class="pour" style="height:340px"></div>
<div class="wrap">
  <div class="colv" id="c0"><div class="inner">${col0.join('')}${col0.join('')}</div></div>
  <div class="colv" id="c1"><div class="inner">${col1.join('')}${col1.join('')}</div></div>
  <div class="colv" id="c2"><div class="inner">${col2.join('')}${col2.join('')}</div></div>
</div>
<div class="fade top"></div><div class="fade bot"></div>`,
`window.TOTAL=14;
const cols=[{el:null,n:1},{el:null,n:2},{el:null,n:1}];
window.addEventListener ? null : null;
function h(i){const el=document.querySelector('#c'+i+' .inner');return el.scrollHeight/2;}
window.seek=function(t){
  for(let i=0;i<3;i++){
    const inner=document.querySelector('#c'+i+' .inner');
    const half=inner.scrollHeight/2;
    const n=[1,2,1][i];
    const y=((t/window.TOTAL)*n*half)%half;
    inner.style.transform='translateY('+(-y)+'px)';
  }
};`,
`
.wrap{position:absolute;inset:60px 120px;display:flex;gap:28px;}
.colv{flex:1;overflow:hidden;border-radius:0;}
.inner{will-change:transform;}
.fc{background:rgba(255,255,255,.06);border-radius:22px;padding:26px;margin-bottom:28px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.05);}
.fhd{display:flex;align-items:center;gap:10px;font-size:18px;font-weight:700;color:rgba(255,255,255,.45);margin-bottom:14px;}
.fdot{width:12px;height:12px;border-radius:50%;display:inline-block;}
.famt{font-size:34px;font-weight:800;color:${GREEN};}
.fbig{font-size:52px;font-weight:800;letter-spacing:-.02em;}
.fttl{font-size:24px;font-weight:700;line-height:1.3;}
.fsub{font-size:18px;color:rgba(255,255,255,.42);margin-top:8px;}
.fimg{height:150px;border-radius:14px;margin-bottom:14px;}
.fgrid{display:flex;gap:10px;margin-bottom:12px;}
.fgrid i{flex:1;aspect-ratio:1;border-radius:12px;display:block;}
.fbars span{display:block;height:13px;border-radius:8px;background:rgba(255,255,255,.22);margin-bottom:9px;}
.minitree{display:flex;gap:8px;height:110px;margin-bottom:12px;}
.minitree span{border-radius:12px;display:flex;align-items:flex-end;padding:10px;}
.minitree b{font-size:16px;font-weight:800;}
.melt{height:16px;border-radius:9px;background:rgba(255,255,255,.09);margin:12px 0 4px;overflow:hidden;}
.melt i{display:block;height:100%;border-radius:9px;background:linear-gradient(90deg,#0434ff,#5b7cfa);}
.miniheat{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;}
.miniheat i{aspect-ratio:1;border-radius:4px;display:block;}
.fade{position:absolute;left:0;right:0;height:110px;z-index:3;pointer-events:none;}
.fade.top{top:0;background:linear-gradient(to bottom,${INK},rgba(11,9,16,0));}
.fade.bot{bottom:0;background:linear-gradient(to top,${INK},rgba(11,9,16,0));}
`);

const OUT = {
  'web-clip-connect.html': connect(),
  'web-clip-keeptabs.html': keeptabs(),
  'web-clip-agent.html': agent(),
  'web-clip-feedstrip.html': feedstrip(),
};
for (const [f, html] of Object.entries(OUT)) {
  fs.writeFileSync(path.join(__dirname, f), html);
  console.log('wrote', f, (html.length / 1024).toFixed(0) + 'KB');
}
