// PostHog promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/PostHogBridge.swift + Screens/PostHogScreen.swift (2026-07-27).
// User ask: make sure the VISUALIZATIONS show — so this leans hard on the
// one real visual differentiator, drawn faithfully:
//   THE DISC — MetricDisc: a metric's mark is its OWN seven-day curve, not a
//     generic glyph (the TickerDisc reasoning — a stock has no logo, the
//     ticker IS the mark; here the DATA is the mark). Solid stroke rising,
//     DASHED falling — colour-blind-survivable, the same treatment
//     Sparkline adopted. A progress RING traces how far the metric has come
//     toward its next milestone rung.
//   0 NAME A METRIC — the thing IS the watch (TokenWatch/StockWatch shape).
//   1 THE DISC ITSELF — its curve becomes its icon; the ring is milestone
//     progress.
//   2 UPDATES IN PLACE — a count is exactly what the module doctrine forbids
//     a thing to be, so a watched metric never re-lands weekly with a new
//     number.
//   3 THREE THINGS LAND — annotations (with the delta since, e.g.
//     "signed_up +18% since"), milestones ("<event> crossed <n>", the 1-2-5
//     ladder, once per rung), silence ("<event> hasn't fired since
//     yesterday").
//   4 READ-ONLY, STRUCTURALLY — query:read / annotation:read /
//     event_definition:read; the key literally cannot ship a flag or write
//     back.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-posthog-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/jpeg;base64,' + fs.readFileSync(path.join(__dirname, 'posthog-icon.jpg')).toString('base64');
const PH_ORANGE = '#F54E00', BLUE = '#2E63FF', GREEN = '#3fb950', AMBER = '#ff9f0a', VIOLET = '#8c40c7';
const BEATS = [
  { kick: 'NAME A METRIC',    head: 'Watch the number\nthat matters.',    accent: PH_ORANGE },
  { kick: 'THE DISC IS THE DATA', head: 'Its curve\nis its icon.',        accent: BLUE },
  { kick: 'UPDATES IN PLACE', head: 'Never a tally.\nAlways the shape.',  accent: GREEN },
  { kick: 'THREE THINGS LAND', head: 'A note. A milestone.\nA silence.',  accent: AMBER },
  { kick: 'READ-ONLY',        head: "Can't ship a flag.\nCan't write back.", accent: VIOLET },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

// Real seven-day shapes for the roster (rising solid / falling dashed / flat).
const METRICS = [
  { n: 'signed_up',    series: [40, 44, 39, 52, 58, 63, 71], c: GREEN, prog: 0.62 },
  { n: 'checkout_start', series: [120, 118, 121, 110, 103, 96, 88], c: '#ff6b6b', prog: 0.24, falling: true },
  { n: 'app_opened',   series: [900, 905, 899, 912, 908, 915, 918], c: BLUE, prog: 0.9 },
];

const NEWS = [
  { tag: 'ANNOTATION', c: BLUE,   title: 'Shipped 2.4.0',                    sub: 'signed_up +18% since' },
  { tag: 'MILESTONE',  c: GREEN,  title: 'signed_up crossed 1,000',           sub: 'The count as the event — landed once' },
  { tag: 'SILENCE',    c: '#ff6b6b', title: "checkout_start hasn't fired since yesterday", sub: 'The most valuable thing analytics can say' },
];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:98px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — name a metric */
.field{background:rgba(255,255,255,.07);border-radius:100px;padding:24px 30px;font-size:27px;font-weight:650;font-family:ui-monospace,monospace;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;align-items:center;}
.caret{width:3px;height:30px;background:#fff;margin-left:3px;display:inline-block;}
.pledge{margin-top:28px;text-align:center;font-size:23px;color:rgba(255,255,255,.55);font-weight:600;line-height:1.5;will-change:opacity;}
.pledge b{color:#fff;}
/* 1 — the disc, big and center stage */
.discwrap{display:flex;justify-content:center;padding:20px 0;}
.discbig{position:relative;width:340px;height:340px;}
.discbig svg{width:100%;height:100%;}
.disclabel{margin-top:22px;text-align:center;}
.disclabel .n{font-size:32px;font-weight:750;font-family:ui-monospace,monospace;}
.disclabel .s{font-size:22px;color:rgba(255,255,255,.45);margin-top:6px;font-weight:600;}
/* 2 — updates in place */
.rosterrow{display:flex;justify-content:center;gap:38px;padding:20px 0 6px;}
.slot{display:flex;flex-direction:column;align-items:center;gap:14px;will-change:opacity,transform;}
.slot .discsm{width:120px;height:120px;}
.slot .ln{font-size:20px;font-weight:700;font-family:ui-monospace,monospace;}
.slot .chg{font-size:18px;font-weight:750;margin-top:-8px;}
/* 3 — three things land */
.nrow{display:flex;align-items:flex-start;gap:18px;padding:18px 0;will-change:opacity,transform;}
.ntag{font-size:16px;font-weight:800;letter-spacing:.05em;padding:7px 13px;border-radius:100px;flex:none;margin-top:2px;}
.ntitle{font-size:24px;font-weight:700;}
.nsub{font-size:19px;color:rgba(255,255,255,.44);margin-top:3px;}
/* 4 — read only */
.scoperow{display:flex;align-items:center;gap:18px;padding:16px 0;font-size:26px;font-weight:650;will-change:opacity,transform;}
.scoperow i{width:44px;height:44px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:22px;font-weight:800;}
.scoperow code{font-family:ui-monospace,monospace;font-size:22px;color:rgba(255,255,255,.8);}
.cant{margin-top:24px;display:flex;flex-direction:column;gap:12px;}
.cant div{display:flex;align-items:center;gap:18px;font-size:23px;font-weight:650;color:rgba(255,255,255,.5);will-change:opacity,transform;}
.cant s{width:38px;height:38px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:#FF6B4A;display:flex;align-items:center;justify-content:center;font-size:19px;text-decoration:none;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${PH_ORANGE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span class="brand"><img src="${ICON}"><span>POSTHOG</span></span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">WATCH AN EVENT</div>
    <div class="field"><span id="typed"></span><span class="caret" id="caret"></span></div>
    <div class="pledge">The thing IS the watch — <b>deleting the row unwatches it.</b><br>No side store to drift out of sync.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">THE DISC IS THE DATA</div>
    <div class="discwrap"><div class="discbig" id="discbig">
      <svg viewBox="0 0 200 200">
        <circle cx="100" cy="100" r="70" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="3"/>
        <circle id="ring" cx="100" cy="100" r="70" fill="none" stroke="${GREEN}" stroke-width="4" stroke-linecap="round" transform="rotate(-90 100 100)"/>
        <path id="curve" fill="none" stroke="${GREEN}" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </div></div>
    <div class="disclabel"><div class="n">signed_up</div><div class="s" id="ringlabel">7-day curve · ring = milestone progress</div></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">A METRIC NEVER RE-LANDS</div>
    <div class="rosterrow">${METRICS.map((m, i) => `<div class="slot" data-i="${i}"><div class="discsm" id="sd${i}"><svg viewBox="0 0 200 200"><circle cx="100" cy="100" r="72" fill="none" stroke="rgba(255,255,255,.08)" stroke-width="6"/><circle cx="100" cy="100" r="72" fill="none" stroke="${m.c}" stroke-width="7" stroke-linecap="round" stroke-dasharray="${m.prog * 452} 452" transform="rotate(-90 100 100)"/><path fill="none" stroke="${m.c}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="${m.falling ? '9 6' : 'none'}" d="${sparkPath(m.series)}"/></svg></div><div class="ln">${m.n}</div><div class="chg" style="color:${m.c}">${m.falling ? '▼' : '▲'} ${m.falling ? '−18%' : '+' + Math.round((m.series[6]/m.series[0]-1)*100) + '%'}</div></div>`).join('')}</div>
    <div class="cap" style="margin-top:20px">A count is exactly what a thing<br><b>is never allowed to be here.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">ONLY NEWS LANDS</div>
    ${NEWS.map((n, i) => `<div class="nrow" data-i="${i}"><span class="ntag" style="background:${n.c}22;color:${n.c}">${n.tag}</span><div><div class="ntitle">${n.title}</div><div class="nsub">${n.sub}</div></div></div>`).join('')}
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">GRANTED SCOPES</div>
    <div class="scoperow" data-i="0"><i>✓</i><code>query:read</code></div>
    <div class="scoperow" data-i="1"><i>✓</i><code>annotation:read</code></div>
    <div class="scoperow" data-i="2"><i>✓</i><code>event_definition:read</code></div>
    <div class="cant" id="cant">
      <div><s>✕</s> Can't ship a feature flag</div>
      <div><s>✕</s> Can't edit a dashboard</div>
      <div><s>✕</s> Never an individual's profile — aggregates only</div>
    </div>
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
const EVENT="signed_up";
const SERIES=${JSON.stringify(METRICS[0].series)};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
function sparkPathAt(series,frac){
  const n=series.length, cx=100, cy=100, r=48;
  const low=Math.min(...series), high=Math.max(...series);
  const pts=series.map((v,i)=>{
    const ang=-90+ (i/(n-1))*70 - 35; // small arc, decorative — real path built in JS below for beat1's big disc
    return v;
  });
  return '';
}
document.getElementById('curve') && (function(){})();
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
function buildCurve(series,cx,cy,r){
  const low=Math.min(...series), high=Math.max(...series);
  const n=series.length;
  return series.map((v,i)=>{
    const x=cx-r+ (i/(n-1))*r*2;
    const norm=high>low?(v-low)/(high-low):0.5;
    const y=cy+r*0.62 - norm*r*1.24;
    return (i===0?'M':'L')+x.toFixed(1)+' '+y.toFixed(1);
  }).join(' ');
}
function animateComp(i,p,t,local){
  const cap=document.querySelector('#comp'+i+' .cap');
  if(i===0){
    const n=Math.round(clamp01((p-0.06)/0.36)*EVENT.length);
    document.getElementById('typed').textContent=EVENT.slice(0,n);
    document.getElementById('caret').style.opacity=(n<EVENT.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    document.querySelector('#comp0 .pledge').style.opacity=clamp01((p-0.5)/0.3);
  } else if(i===1){
    const dp=clamp01((p-0.08)/0.5);
    const path=document.getElementById('curve');
    const full=buildCurve(SERIES,100,100,54);
    // reveal the curve point-by-point via stroke-dash trick on the live path
    path.setAttribute('d', full);
    const len=path.getTotalLength ? path.getTotalLength() : 300;
    path.style.strokeDasharray=len;
    path.style.strokeDashoffset=len*(1-easeOut(dp));
    const ring=document.getElementById('ring');
    const C=2*Math.PI*70;
    const ringP=clamp01((p-0.45)/0.4)*0.62;
    ring.style.strokeDasharray=C;
    ring.style.strokeDashoffset=C*(1-ringP);
    document.querySelector('#comp1 .disclabel').style.opacity=clamp01((p-0.55)/0.3);
  } else if(i===2){
    stag('#comp2 .slot',p,0.18,0.32,26);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.26);
  } else if(i===3){
    stag('#comp3 .nrow',p,0.18,0.32,22);
  } else if(i===4){
    stag('#comp4 .scoperow',p,0.15,0.28,18);
    stag('#comp4 .cant div',clamp01((p-0.5)/0.5),0.16,0.3,16);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-posthog-editorial.html'),html);
console.log('wrote clip-posthog-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');

function sparkPath(series){
  const low=Math.min(...series), high=Math.max(...series);
  const n=series.length, cx=100, cy=100, r=54;
  return series.map((v,i)=>{
    const x=cx-r+ (i/(n-1))*r*2;
    const norm=high>low?(v-low)/(high-low):0.5;
    const y=cy+r*0.62 - norm*r*1.24;
    return (i===0?'M':'L')+x.toFixed(1)+' '+y.toFixed(1);
  }).join(' ');
}
