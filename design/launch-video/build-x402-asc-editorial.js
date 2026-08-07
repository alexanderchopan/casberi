// Launch clips for Circle x402 and App Store Connect (prd §319, §323).
// Template lifted verbatim from build-bridges-batch.js.
//
// Every headline, row title and honesty line is grounded in the shipped
// source: each bridge's own doc header and its real `String(localized:)`
// title shapes —
//   Sentry     "[Regressed] · project · issue title"   (SentryShape.title)
//   Vercel     "[Build failed] · project · subject"    (VercelShape.title)
//   PagerDuty  "[Resolved after 41 min] · service · what"  (PagerDutyShape)
//   npm/PyPI   "react 19.2.0" / "Deprecated · request"  (PackageShape)
//
// One generator, four clips, so the house template stays in one place:
//   node build-bridges-batch.js          writes clip-<name>-editorial.html
//   node render.js clip-<name>-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const INK = '#14110d', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF',
      ORANGE = '#FF6B4A', AMBER = '#ff9f0a';

/* ------------------------------------------------------------------ *
 * The shared editorial template. Each clip supplies BEATS (kick/head/
 * accent/tag), the comp markup, its own scene CSS, and an animateComp.
 * ------------------------------------------------------------------ */
function clip({ name, mast, accent, beats, comps, css, anim }) {
  const INTRO = 0.45, BEAT = 3.15;
  const OUT_AT = INTRO + beats.length * BEAT, TOTAL = OUT_AT + 1.9;
  const DATA = beats.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));
  const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:196px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.tagpill{position:absolute;left:74px;top:238px;font-size:19px;font-weight:800;letter-spacing:.06em;padding:8px 16px;border-radius:100px;will-change:opacity,transform;}
.head{position:absolute;left:70px;top:288px;right:70px;font-size:88px;line-height:1.0;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0d09;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
/* shared row grammar */
.row{display:flex;align-items:center;gap:20px;padding:22px 24px;border-radius:20px;background:rgba(255,255,255,.05);margin-bottom:16px;will-change:opacity,transform;}
.pill{flex:none;font-size:19px;font-weight:800;padding:9px 16px;border-radius:11px;font-family:ui-monospace,monospace;}
.rt{font-size:25px;font-weight:750;line-height:1.3;}
.rs{font-size:20px;color:rgba(255,255,255,.45);margin-top:4px;}
.note{margin-top:26px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.note em{font-style:normal;font-weight:750;}
/* the struck-through tally, used by three of the four */
.cnt{display:flex;align-items:center;justify-content:space-between;padding:19px 6px;border-bottom:1px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.cnt .l{font-size:25px;font-weight:650;color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:${ORANGE};text-decoration-thickness:3px;}
.cnt .r{font-size:19px;font-weight:800;color:${ORANGE};letter-spacing:.06em;}
.keep{display:flex;align-items:center;justify-content:space-between;padding:22px 6px;will-change:opacity,transform;}
.keep .l{font-size:25px;font-weight:800;color:#fff;}
.keep .r{font-size:19px;font-weight:800;color:${GREEN};letter-spacing:.06em;}
${css}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:#fff;background:${accent};padding:2px 10px;border-radius:6px;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>${mast}</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>
${comps}
  <div class="kick mono" id="kick"></div>
  <div class="tagpill" id="tagpill"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${beats.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const TAGS=${JSON.stringify(beats.map(b => b.tag || null))};
const ACCENT=${JSON.stringify(accent)};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
function pop(el,p,from,dur,dy){if(!el)return 0;const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy||22))+'px)';return rp;}
function show(id,p,from,dur){const e=document.getElementById(id);if(e)e.style.opacity=clamp01((p-from)/(dur||0.24));}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.9);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(40,Math.min(240,780/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const tag=document.getElementById('tagpill');
  if(TAGS[active]){tag.textContent=TAGS[active];tag.style.background=ACCENT;tag.style.color='#fff';tag.style.opacity=easeOut(kin);tag.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';}
  else{tag.style.opacity=0;}
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
${anim}
}
window.seek(0);
</script></body></html>`;
  const file = `clip-${name}-editorial.html`;
  fs.writeFileSync(path.join(__dirname, file), html);
  console.log('wrote', file, (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
}


/* =============================== CIRCLE x402 =========================== */
// Grounded in CircleX402Bridge.swift's own measurements (2026-08-06):
// 955 listings / 22 providers; Orthogonal 310, QuickNode 132; DATA_ENRICHMENT
// is 185 of 955 and Circle's own category filter 400s on it.
const CIRCLE = '#00d395';
clip({
  name: 'x402', mast: 'CIRCLE x402', accent: CIRCLE,
  beats: [
    { kick: 'THE MARKET', head: 'APIs that sell\nto software.',        accent: ORANGE, tag: 'NEW' },
    { kick: 'WHAT LANDS', head: 'A company.\nNot 310 endpoints.',      accent: INK },
    { kick: 'THE GAP',    head: "A fifth of it their\nown filter can't reach.", accent: INK },
    { kick: 'NEVER PAYS', head: 'Every row has a price.\nNone is a button.', accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">PAY-PER-REQUEST, SETTLED IN USDC</div>
    <div class="row" id="r0a"><span class="pill" style="background:rgba(0,211,149,.18);color:${CIRCLE}">402</span><div><div class="rt">An API answers an unpaid request with a price</div><div class="rs">x402 — the HTTP status nobody used, put to work</div></div></div>
    <div class="row" id="r0b"><span class="pill" style="background:rgba(255,255,255,.1);color:#fff">FREE</span><div><div class="rt">No account, no key, nothing to mint</div><div class="rs">Circle runs the directory. One GET reads it all</div></div></div>
    <div class="note" id="note0">Software buying from software, by the call.<br><em>Watchable the way you watch a market.</em></div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">955 LISTINGS · 22 SELLERS</div>
    <div class="cnt" data-i="0"><span class="l">Orthogonal — 310 listings</span><span class="r">1 ROW</span></div>
    <div class="cnt" data-i="1"><span class="l">QuickNode — 132 listings</span><span class="r">1 ROW</span></div>
    <div class="keep" id="keep1"><span class="l">Orthogonal · 310 services · from $0.0001</span><span class="r">LANDS</span></div>
    <div class="note" id="note1">Landing per endpoint files 310 rows the day one<br>company onboards. <em>The company is the event.</em></div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">MEASURED, NOT ASSUMED</div>
    <div class="stat" id="stat2"><div class="big">185</div><div class="of">of 955 listings</div></div>
    <div class="cnt" data-j="0"><span class="l">category=DATA_ENRICHMENT</span><span class="r">400</span></div>
    <div class="note" id="note2">Circle's filter takes six values. The data carries seven.<br><em>So we fetch unfiltered and narrow on your phone.</em></div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">THE CEILING IS THE POINT</div>
    <div class="cnt" data-k="0"><span class="l">Pays a service</span><span class="r">NEVER</span></div>
    <div class="cnt" data-k="1"><span class="l">Holds a wallet that could</span><span class="r">NEVER</span></div>
    <div class="cnt" data-k="2"><span class="l">Shows a path to buy</span><span class="r">NEVER</span></div>
    <div class="note" id="note3">A read-only room where every listing is priced.<br><em>Buying is somebody else's app.</em></div>
  </div>`,
  css: `
.stat{text-align:center;padding:14px 0 30px;will-change:opacity,transform;}
.stat .big{font-size:150px;font-weight:800;letter-spacing:-.05em;line-height:.9;color:${CIRCLE};font-family:ui-monospace,monospace;}
.stat .of{margin-top:10px;font-size:24px;font-weight:700;color:rgba(255,255,255,.5);}`,
  anim: `
  if(i===0){pop(document.getElementById('r0a'),p,0.03,0.28,20);pop(document.getElementById('r0b'),p,0.34,0.28,20);show('note0',p,0.68);}
  else if(i===1){stag('#comp1 .cnt',p,0.14,0.24,16);pop(document.getElementById('keep1'),p,0.5,0.26,20);show('note1',p,0.76);}
  else if(i===2){pop(document.getElementById('stat2'),p,0.04,0.32,26);stag('#comp2 .cnt',p,0.42,0.26,16);show('note2',p,0.7);}
  else if(i===3){stag('#comp3 .cnt',p,0.14,0.24,16);show('note3',p,0.68);}`,
});

/* ========================== APP STORE CONNECT ========================== */
// Grounded in AppStoreConnectBridge.swift: the verdict LEADS the title; a
// customer review renders "★★☆☆☆ · Casberi · Crashes on launch"; and NO
// aggregate rating is ever shown — Apple's API publishes individual reviews
// only, so any average would be the mean of the twenty we read (§83).
const ASC = '#0a84ff';
clip({
  name: 'appstoreconnect', mast: 'APP STORE CONNECT', accent: ASC,
  beats: [
    { kick: 'THE WAIT',  head: "You shipped it.\nNow it's their desk.",    accent: ORANGE, tag: 'NEW' },
    { kick: 'THE VERDICT', head: 'Rejected leads,\nso nothing eats it.',   accent: INK },
    { kick: 'REAL WORDS', head: 'What someone actually\nwrote about it.',  accent: INK },
    { kick: 'NO AVERAGE', head: 'Twenty reviews is not\na star rating.',   accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">FOUR THINGS SOMEBODY ELSE DECIDED</div>
    <div class="cnt2" data-i="0"><span class="l">A review verdict</span></div>
    <div class="cnt2" data-i="1"><span class="l">A customer review</span></div>
    <div class="cnt2" data-i="2"><span class="l">A build finishing processing</span></div>
    <div class="cnt2" data-i="3"><span class="l">A TestFlight build about to expire</span></div>
    <div class="note" id="note0">App Store Connect emails some of it and buries the rest.<br><em>It tells you nothing at all about the last one.</em></div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">HOW A VERDICT LANDS</div>
    <div class="row" id="r1a"><span class="pill" style="background:rgba(255,69,58,.18);color:${RED}">Rejected</span><div><div class="rt">Rejected · Casberi 1.0.4</div><div class="rs">Guideline 2.1 — Information Needed</div></div></div>
    <div class="row" id="r1b"><span class="pill" style="background:rgba(63,185,80,.18);color:${GREEN}">Live</span><div><div class="rt">Live on the App Store · Casberi 1.0.3</div><div class="rs">Approved — yours to release</div></div></div>
    <div class="note" id="note1">Titles clamp at 80 characters, so a trailing verdict is<br>what gets eaten. <em>A rejection must not read as a release.</em></div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">THE MOST THING-SHAPED OBJECT THEY HAVE</div>
    <div class="review" id="rev2">
      <div class="stars">★★☆☆☆</div>
      <div class="rtitle">Casberi · Crashes on launch</div>
      <div class="rbody">"Loved the idea. Opened it three times this morning and it closed itself every time on my 15 Pro."</div>
      <div class="rwho mono">— United States</div>
    </div>
    <div class="note" id="note2">Real words, in the feed, the day they land.</div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">WHAT IT WILL NOT SHOW YOU</div>
    <div class="stat" id="stat3"><div class="big">4.2</div><div class="of">the mean of the 20 we happened to read</div></div>
    <div class="note" id="note3">Apple's API publishes individual reviews and no average.<br><em>A number we invented is one you'd believe instantly.</em></div>
  </div>`,
  css: `
.cnt2{padding:22px 6px;border-bottom:1px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.cnt2 .l{font-size:27px;font-weight:700;}
.review{background:rgba(255,255,255,.06);border-radius:26px;padding:34px;will-change:opacity,transform;}
.stars{font-size:34px;color:${AMBER};letter-spacing:.1em;}
.rtitle{margin-top:14px;font-size:27px;font-weight:800;}
.rbody{margin-top:14px;font-size:23px;line-height:1.45;color:rgba(255,255,255,.72);}
.rwho{margin-top:20px;font-size:19px;color:rgba(255,255,255,.4);}
.stat{text-align:center;padding:22px 0 34px;will-change:opacity,transform;}
.stat .big{font-size:140px;font-weight:800;letter-spacing:-.05em;line-height:.9;color:rgba(255,255,255,.22);text-decoration:line-through;text-decoration-color:${ORANGE};text-decoration-thickness:7px;font-family:ui-monospace,monospace;}
.stat .of{margin-top:18px;font-size:23px;font-weight:700;color:rgba(255,255,255,.5);}`,
  anim: `
  if(i===0){stag('#comp0 .cnt2',p,0.12,0.24,16);show('note0',p,0.72);}
  else if(i===1){pop(document.getElementById('r1a'),p,0.03,0.28,20);pop(document.getElementById('r1b'),p,0.34,0.28,20);show('note1',p,0.68);}
  else if(i===2){pop(document.getElementById('rev2'),p,0.04,0.34,26);show('note2',p,0.66);}
  else if(i===3){pop(document.getElementById('stat3'),p,0.04,0.32,26);show('note3',p,0.6);}`,
});
