// Wallet promo — REIMAGINED as an editorial "poster in motion": warm paper
// ground, oversized black type set flush-left, a monospace masthead + index
// numbers, and the app's own colourful UI cards dropped in as tilted objects
// with hard shadows. Beats change on a diagonal colour WIPE. Deterministic
// (stills) → frame render: node render.js clip-wallet-editorial.html --size=1080x1920
const fs = require('fs');
const path = require('path');
const CROPS = '/Users/alexanderchopan/Developer/casberi/scratchpad/wcrops';
const b64 = f => 'data:image/png;base64,' + fs.readFileSync(path.join(CROPS, f)).toString('base64');

// each beat: a UI card, an editorial kicker, a big headline, an accent colour.
const BEATS = [
  { img: 'watch.png',    kick: 'READ-ONLY',  head: 'Watch any\nwallet.',   accent: '#2E63FF' },
  { img: 'holdings.png', kick: 'HOLDINGS',   head: 'See every\ntoken.',    accent: '#2E63FF' },
  { img: 'tx.png',       kick: 'ACTIVITY',   head: 'Every\ntransaction.',  accent: '#2E63FF' },
  { img: 'chart.png',    kick: 'MARKETS',    head: 'Live token\ncharts.',  accent: '#E8912A' },
  { img: 'networth.png', kick: 'NET WORTH',  head: '$415.8M,\nlive.',      accent: '#2E63FF' },
];

const INTRO = 0.45, BEAT = 1.7;
const OUT_AT = INTRO + BEATS.length * BEAT;
const TOTAL = OUT_AT + 1.9;

const cardTags = BEATS.map((b, i) =>
  `<img class="card" id="card${i}" src="${b64(b.img)}">`).join('\n');

const DATA = BEATS.map((b, i) => ({ kick: (i + 1 < 10 ? '0' : '') + (i + 1) + ' · ' + b.kick,
  head: b.head, accent: b.accent }));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
/* faint paper texture via layered soft dots */
.grain{position:absolute;inset:0;opacity:.5;
  background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),
                   radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);
  background-size:7px 7px, 9px 9px;}
/* masthead */
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;
  font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
/* giant index watermark */
.wm{position:absolute;right:20px;top:150px;font-size:560px;line-height:.8;font-weight:800;
  letter-spacing:-.04em;color:#14110d;opacity:.06;will-change:opacity,transform;}
/* kicker + headline block */
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;
  letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
/* the UI card object */
.card{position:absolute;width:840px;left:120px;top:820px;border-radius:30px;
  box-shadow:34px 40px 0 rgba(20,17,13,.14), 0 30px 70px rgba(20,17,13,.28);
  will-change:transform,opacity;opacity:0;}
/* diagonal colour wipe */
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);
  will-change:transform;}
/* footer */
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;
  font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
/* outro */
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;
  padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:190px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:#2E63FF;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span id="mastR">WALLET</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>
  ${cardTags}
  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span id="pg">01 / 05</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, BEAT=${BEAT}, OUT_AT=${OUT_AT}, N=${BEATS.length};
const D=${JSON.stringify(DATA)};
window.TOTAL=${TOTAL};
const cards=[...document.querySelectorAll('.card')];

window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT;
  const local=t-bs;
  const acc=D[active].accent;

  // ---- diagonal wipe: sweeps across at each beat boundary, hiding the swap ----
  // nearest boundary to t (boundaries at INTRO + k*BEAT, k=1..N-1, plus outro)
  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:INTRO+k*BEAT, c:D[k].accent});
  bounds.push({t:OUT_AT, c:'#14110d'});
  for(const b of bounds){
    const p=(t-(b.t-0.34))/0.68;                 // 0..1 across the wipe
    if(p>=0&&p<=1){ wipeX=(1-p)*135 - p*135*1.15; coverAcc=b.c; }
  }
  const wipe=document.getElementById('wipe');
  wipe.style.background=coverAcc;
  wipe.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  // ---- editorial furniture ----
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');
  wm.textContent=(active+1<10?'0':'')+(active+1);
  wm.style.color=acc; wm.style.opacity=0.10*clamp01(local/0.4);
  wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';

  // kicker
  const ki=document.getElementById('kick');
  ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4);
  ki.style.opacity=easeOut(kin);
  ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';

  // headline slams up
  const he=document.getElementById('head');
  he.textContent=D[active].head;
  const hin=clamp01((local-0.06)/0.5);
  he.style.opacity=clamp01(local/0.2);
  he.style.transform='translateY('+((1-back(hin))*80)+'px)';

  document.getElementById('pg').textContent=(active+1<10?'0':'')+(active+1)+' / 0'+N;
  document.getElementById('mastR').textContent='WALLET';

  // ---- cards ----
  cards.forEach((c,i)=>{
    const cbs=INTRO+i*BEAT, cl=t-cbs;
    const cin=clamp01((cl-0.12)/0.6);
    const beatEnd=INTRO+(i+1)*BEAT;
    const outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=820 + (1-back(cin))*180 + outp*200 + Math.sin(t*0.9+i)*5;
    const rot=(-2.4) + (1-easeOut(cin))*-5 + outp*4;
    c.style.opacity=op;
    c.style.transform='translateY('+(y-820)+'px) rotate('+rot+'deg)';
    c.style.transformOrigin='center top';
  });

  // fade the page furniture out for the outro
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-wallet-editorial.html'), html);
console.log('wrote clip-wallet-editorial.html', (html.length/1024/1024).toFixed(1)+'MB', TOTAL.toFixed(1)+'s');
