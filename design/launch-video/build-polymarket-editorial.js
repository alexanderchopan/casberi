// Polymarket promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/PolymarketBridge.swift + Design/PolymarketMarketView.swift
// (2026-07-28). Polymarket rides the same Markets shape Kalshi already does
// (public odds, read-only, no wallet, no trade) but with two real, kept-not-
// smoothed-away divergences:
//   0 REAL SEARCH — Polymarket's Gamma API has a genuine keyword search,
//     unlike Kalshi (which falls back to a hardcoded sports-series list).
//     An empty query lists the busiest open markets by 24h volume.
//   1 IT LANDS WITH LIVE ODDS — the YES price, landed as a .link thing
//     titled the market's own question, content = the polymarket.com URL.
//   2 A REAL CURVE — Polymarket's CLOB serves genuine price history, so the
//     sheet draws a real scrubbable chart (TokenChartPlot, the same plot
//     token/stock charts use) — the curve Kalshi's own view deliberately
//     refuses to fake when its data is too thin.
//   3 HONEST DEGRADE — a market too new or too thin for a real curve just
//     shows the headline number, no chart — a fallback that stops
//     pretending rather than inventing a line (prd §51).
//   4 KEYLESS, READ-ONLY — gamma-api / clob.polymarket.com, no auth. Public
//     price data only — nothing here ever places a trade.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-polymarket-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/png;base64,' + fs.readFileSync(path.join(
  __dirname, '../../Casberi/Casberi/Assets.xcassets/brand-polymarket.imageset/icon.png')).toString('base64');

const POLY_BLUE = '#1652F0', KALSHI_GREEN = '#4fae7b', GREEN = '#3fb950', AMBER = '#ff9f0a', ORANGE = '#FF6B4A', VIOLET = '#8c40c7';
const BEATS = [
  { kick: 'SEARCH ANY QUESTION', head: 'Type it.\nIt finds it.',        accent: POLY_BLUE },
  { kick: 'LIVE ODDS',           head: 'Watched —\nwith its real price.', accent: GREEN },
  { kick: 'TWO CROWDS, ONE QUESTION', head: 'Same question.\nDifferent odds.', accent: VIOLET },
  { kick: 'A REAL CURVE',        head: 'Not a sketch.\nA real chart.',   accent: POLY_BLUE },
  { kick: 'HONEST DEGRADE',      head: 'Too thin to chart?\nIt says so.', accent: AMBER },
  { kick: 'KEYLESS, READ-ONLY',  head: 'Onchain odds.\nNever a trade.',  accent: ORANGE },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const RESULTS = [
  { t: 'Fed cuts rates in September?', p: 68 },
  { t: 'Will it rain in NYC this week?', p: 41 },
  { t: '2026 midterm turnout record?', p: 22 },
];
const SERIES = [22, 24, 21, 28, 33, 31, 38, 44, 41, 47, 53, 58, 61, 68];

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;align-items:center;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.mast .brand{display:flex;align-items:center;gap:14px;}
.mast .brand img{width:34px;height:34px;border-radius:9px;display:block;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:96px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — search */
.field{background:rgba(255,255,255,.07);border-radius:100px;padding:24px 30px;font-size:27px;font-weight:650;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;align-items:center;}
.caret{width:3px;height:30px;background:#fff;margin-left:3px;display:inline-block;}
.rrow{display:flex;align-items:center;gap:18px;padding:17px 0;will-change:opacity,transform;}
.rrow .rt{font-size:23px;font-weight:650;flex:1;}
.rrow .rp{font-size:24px;font-weight:800;color:${GREEN};font-family:ui-monospace,monospace;}
/* 1 — live odds */
.oddscard{background:rgba(255,255,255,.06);border-radius:24px;padding:30px;text-align:center;}
.oddsq{font-size:28px;font-weight:700;line-height:1.32;}
.oddsbig{font-size:96px;font-weight:800;margin-top:18px;letter-spacing:-.02em;will-change:opacity,transform;}
/* 2 — twin comparison (PredictionTwin) */
.twinq{font-size:27px;font-weight:700;text-align:center;line-height:1.32;}
.twinrow{display:flex;gap:16px;margin-top:26px;}
.twinside{flex:1;background:rgba(255,255,255,.06);border-radius:20px;padding:24px 18px;display:flex;flex-direction:column;align-items:center;gap:8px;will-change:opacity,transform;}
.twindot{width:14px;height:14px;border-radius:50%;}
.twinname{font-size:21px;font-weight:650;color:rgba(255,255,255,.6);}
.twinpct{font-size:44px;font-weight:800;}
.twinbar{margin-top:20px;height:16px;border-radius:8px;overflow:hidden;display:flex;background:rgba(255,255,255,.08);}
.twinfillK{width:0%;will-change:width;} .twinfillP{width:0%;will-change:width;}
.twinmoment{margin-top:24px;background:rgba(140,64,192,.14);border-radius:16px;padding:18px 22px;font-size:22px;font-weight:650;color:#fff;text-align:center;line-height:1.4;will-change:opacity,transform;}
.oddssub{margin-top:10px;font-size:22px;color:rgba(255,255,255,.44);font-weight:600;}
/* 2 — real curve */
.chartwrap{background:rgba(255,255,255,.05);border-radius:24px;padding:28px;}
.chartval{font-size:52px;font-weight:800;}
.chartsub{font-size:21px;color:rgba(255,255,255,.42);margin-top:4px;font-weight:600;}
.chartsvg{margin-top:20px;}
/* 3 — degrade */
.degcard{background:rgba(255,255,255,.06);border-radius:24px;padding:34px;text-align:center;}
.degq{font-size:26px;font-weight:700;line-height:1.32;}
.degbig{font-size:70px;font-weight:800;margin-top:16px;}
.degnote{margin-top:16px;font-size:21px;color:rgba(255,255,255,.42);font-weight:600;}
.degbars{display:flex;gap:6px;justify-content:center;margin-top:22px;opacity:.3;}
.degbars span{width:5px;height:20px;border-radius:3px;background:rgba(255,255,255,.5);}
/* 4 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:18px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${POLY_BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span class="brand"><img src="${ICON}"><span>POLYMARKET</span></span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">SEARCH ANY QUESTION</div>
    <div class="field"><span id="typed"></span><span class="caret" id="caret"></span></div>
    <div style="margin-top:22px">${RESULTS.map((r, i) => `<div class="rrow" data-i="${i}"><span class="rt">${r.t}</span><span class="rp">${r.p}%</span></div>`).join('')}</div>
    <div class="cap">Polymarket's own search —<br><b>not a hardcoded list.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">WATCHED</div>
    <div class="oddscard">
      <div class="oddsq">Fed cuts rates in September?</div>
      <div class="oddsbig" id="oddsbig" style="color:${GREEN}">68%</div>
      <div class="oddssub">YES · lands in your feed like anything else</div>
    </div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">THE OTHER EXCHANGE, ASKED</div>
    <div class="twinq">Fed cuts rates in September?</div>
    <div class="twinrow">
      <div class="twinside" data-i="0"><span class="twindot" style="background:${KALSHI_GREEN}"></span><span class="twinname">Kalshi</span><span class="twinpct" id="twinK" style="color:${KALSHI_GREEN}">61%</span></div>
      <div class="twinside" data-i="1"><span class="twindot" style="background:${POLY_BLUE}"></span><span class="twinname">Polymarket</span><span class="twinpct" id="twinP" style="color:${POLY_BLUE}">68%</span></div>
    </div>
    <div class="twinbar"><div class="twinfillK" id="twinFillK" style="background:${KALSHI_GREEN}"></div><div class="twinfillP" id="twinFillP" style="background:${POLY_BLUE}"></div></div>
    <div class="twinmoment" id="twinMoment">Kalshi says 61%, Polymarket says 68% — same question, different odds</div>
    <div class="cap">Two independent crowds disagreeing —<br><b>informational only, never a signal to act on.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">PRICE HISTORY</div>
    <div class="chartwrap">
      <div class="chartval" style="color:${GREEN}">68%</div>
      <div class="chartsub">▲ +46pts since open</div>
      <div class="chartsvg"><svg width="100%" height="180" viewBox="0 0 640 180" preserveAspectRatio="none"><path id="curve" fill="none" stroke="${GREEN}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
    </div>
    <div class="cap">The same real chart<br><b>your token watches draw.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">A THINNER MARKET</div>
    <div class="degcard">
      <div class="degq">Will a new species be discovered this year?</div>
      <div class="degbig">12%</div>
      <div class="degbars">${Array.from({length:10}).map(()=>`<span></span>`).join('')}</div>
      <div class="degnote">Too new for a real curve — no chart shown</div>
    </div>
    <div class="cap">A fallback stops pretending<br><b>rather than faking a line.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never connects a wallet</div>
    <div class="vrow" data-i="1"><s>✕</s> Never places a trade</div>
    <div class="vrow" data-i="2"><s>✕</s> Never needs a key</div>
    <div class="vgood" id="vgood"><i>✓</i> Public onchain odds. Read-only.</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const QUERY="fed rates";
const SERIES=${JSON.stringify(SERIES)};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
function buildCurve(series,w,h,pad){
  const low=Math.min(...series), high=Math.max(...series);
  const n=series.length;
  return series.map((v,i)=>{
    const x=(i/(n-1))*w;
    const norm=high>low?(v-low)/(high-low):0.5;
    const y=h-pad-norm*(h-pad*2);
    return (i===0?'M':'L')+x.toFixed(1)+' '+y.toFixed(1);
  }).join(' ');
}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.7);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(50,Math.min(300,880/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  const cap=document.querySelector('#comp'+i+' .cap');
  if(i===0){
    const n=Math.round(clamp01((p-0.06)/0.3)*QUERY.length);
    document.getElementById('typed').textContent=QUERY.slice(0,n);
    document.getElementById('caret').style.opacity=(n<QUERY.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    stag('#comp0 .rrow',clamp01((p-0.36)/0.64),0.15,0.3,16);
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.26);
  } else if(i===1){
    document.querySelector('#comp1 .oddscard').style.opacity=clamp01((p-0.04)/0.2);
    const sp=clamp01((p-0.3)/0.4);
    const ob=document.getElementById('oddsbig');
    ob.style.opacity=sp;ob.style.transform='scale('+(0.7+0.3*back(sp))+')';
  } else if(i===2){
    stag('#comp2 .twinside',p,0.14,0.26,18);
    const barp=clamp01((p-0.3)/0.34);
    document.getElementById('twinFillK').style.width=(61*barp)+'%';
    document.getElementById('twinFillP').style.width=(68*barp)+'%';
    const mp=clamp01((p-0.56)/0.3);
    const m=document.getElementById('twinMoment');
    m.style.opacity=mp;m.style.transform='translateY('+((1-back(mp))*14)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.78)/0.2);
  } else if(i===3){
    document.querySelector('#comp3 .chartwrap').style.opacity=clamp01((p-0.04)/0.22);
    const dp=clamp01((p-0.16)/0.62);
    const path=document.getElementById('curve');
    path.setAttribute('d', buildCurve(SERIES,640,180,16));
    const len=path.getTotalLength ? path.getTotalLength() : 700;
    path.style.strokeDasharray=len;
    path.style.strokeDashoffset=len*(1-easeOut(dp));
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===4){
    document.querySelector('#comp4 .degcard').style.opacity=clamp01((p-0.04)/0.24);
    if(cap)cap.style.opacity=clamp01((p-0.6)/0.3);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.16,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.54)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-polymarket-editorial.html'),html);
console.log('wrote clip-polymarket-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
