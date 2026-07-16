// Wallet promo — the UI is REBUILT as live HTML/CSS/SVG (no screenshots): the
// net-worth number counts up, the chart line draws on, treemap tiles build,
// the transaction amount ticks, rows + sparkline animate. Wrapped in the same
// editorial frame (paper ground, oversized type, mono masthead, colour wipes).
// Deterministic → node render.js clip-wallet-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const BLUE = '#2E63FF', AMBER = '#E8912A';
const BEATS = [
  { kick: 'READ-ONLY', head: 'Watch any\nwallet.',  accent: BLUE },
  { kick: 'HOLDINGS',  head: 'See every\ntoken.',   accent: BLUE },
  { kick: 'ACTIVITY',  head: 'Every\ntransaction.', accent: BLUE },
  { kick: 'MARKETS',   head: 'Live token\ncharts.', accent: AMBER },
  { kick: 'NET WORTH', head: '',                    accent: BLUE }, // headline is the live count-up
];
const INTRO = 0.45, BEAT = 1.9;
const OUT_AT = INTRO + BEATS.length * BEAT;
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map((b, i) => ({ kick: (i + 1 < 10 ? '0' : '') + (i + 1) + ' · ' + b.kick, head: b.head, accent: b.accent }));

// treemap tile layouts (grid areas), sized by rough value order
const HOLD = [['ETH', '1/1/3/3'], ['AWETH', '1/3/3/6'], ['RUSSEL', '3/1/5/3'], ['WBTC', '3/3/5/5'], ['WETH', '3/5/5/6']];
const NET = [['ETH', '1/1/3/4'], ['SYN', '1/4/3/6'], ['PUNDIX', '3/1/4/3'], ['ZKC', '3/3/4/5'], ['MANA', '3/5/4/6']];
const tiles = arr => arr.map((t, i) => `<div class="tile" data-i="${i}" style="grid-area:${t[1]}"><span class="tk">${t[0]}</span></div>`).join('');

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;
  background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);
  background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:560px;line-height:.8;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

/* --- the live UI card --- */
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;
  transform-origin:center top;padding:52px;color:#fff;}
.comp.blue{background:linear-gradient(160deg,#2E63FF,#1B49D6);}
.comp.amber{background:linear-gradient(160deg,#F0A93A,#D97913);}
.comp.dark{background:#0d0e13;}

/* watching */
.wrow{display:flex;align-items:center;gap:26px;padding:22px 4px;will-change:transform,opacity;}
.av{width:74px;height:74px;border-radius:20px;flex:none;}
.av0,.av2{background:radial-gradient(circle at 35% 30%,#8ea2c8,#38507e 70%);}
.av1{background:radial-gradient(circle at 40% 35%,#7dffb0,#12a15a);}
.wn{font-size:40px;font-weight:650;}
.wa{font-size:26px;color:rgba(255,255,255,.55);margin-top:4px;}
.wsp{margin-left:auto;}

/* treemap */
.thead{font-size:34px;font-weight:600;margin-bottom:26px;}
.thead b{font-weight:750;}
.tmap{display:grid;grid-template-columns:repeat(5,1fr);grid-template-rows:repeat(4,132px);gap:16px;}
.comp.dark .tile,.comp.blue .tile{background:#0a0a0f;}
.tile{border-radius:20px;position:relative;will-change:transform,opacity;transform-origin:center;
  display:flex;align-items:flex-end;padding:22px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.05);}
.tk{font-size:34px;font-weight:650;}

/* transaction */
.txk{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.65);}
.txbig{font-size:96px;font-weight:800;letter-spacing:-.03em;margin-top:22px;}
.txhash{font-size:27px;color:rgba(255,255,255,.6);margin-top:26px;line-height:1.5;word-break:break-all;overflow:hidden;white-space:nowrap;}
.txr{display:flex;justify-content:space-between;font-size:32px;padding:22px 0;border-top:2px solid rgba(255,255,255,.14);margin-top:30px;will-change:opacity,transform;}
.txr span:first-child{color:rgba(255,255,255,.55);}

/* chart */
.chead{font-size:38px;font-weight:750;}
.cprice{font-size:76px;font-weight:800;margin-top:10px;letter-spacing:-.02em;}
.ctabs{font-size:28px;color:rgba(255,255,255,.7);letter-spacing:.1em;margin-top:6px;}
.ctabs b{color:#fff;}
.chart{width:100%;height:250px;margin-top:6px;overflow:visible;}
.cstats{display:flex;gap:20px;margin-top:14px;}
.cstats div{flex:1;}
.cstats span{display:block;font-size:24px;color:rgba(255,255,255,.6);}
.cstats b{font-size:38px;font-weight:750;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:#2E63FF;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>WALLET</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp dark" id="comp0">
    ${[['Vitalik','0xd8dA…6045','av0',false],['Binance 14','0x28C6…1d60','av1',true],['vitalik.eth','','av2',false]]
      .map((r,i)=>`<div class="wrow" data-i="${i}"><div class="av ${r[2]}"></div><div><div class="wn">${r[0]}</div>${r[1]?`<div class="wa mono">${r[1]}</div>`:''}</div>${r[3]?`<svg class="wsp" width="150" height="60"><path id="spark" d="M2 46 L38 40 L74 44 L110 22 L148 8" fill="none" stroke="#48e08a" stroke-width="5" stroke-linecap="round"/></svg>`:''}</div>`).join('')}
  </div>

  <div class="comp blue" id="comp1">
    <div class="thead">Vitalik &nbsp;·&nbsp; <b id="t1val">$0</b> across 11 tokens</div>
    <div class="tmap">${tiles(HOLD)}</div>
  </div>

  <div class="comp blue" id="comp2">
    <div class="txk mono">TRANSACTION · NOW</div>
    <div class="txbig">Sent <span id="txamt">0.00</span> USDT</div>
    <div class="txhash mono" id="txhash">etherscan.io/tx/0x6c381e5ae73c2e14588de1bd12376547</div>
    <div class="txr" data-i="0"><span>From</span><span>in your wallet</span></div>
    <div class="txr" data-i="1"><span>Who</span><span class="mono">0xfc6d…e8ad</span></div>
  </div>

  <div class="comp amber" id="comp3">
    <div class="chead">Brett (Based) &nbsp;·&nbsp; $BRETT</div>
    <div class="cprice" id="cpx">$0.0000</div>
    <div class="ctabs mono"><b>1D</b> &nbsp; 7D &nbsp; 30D</div>
    <svg class="chart" viewBox="0 0 740 250" preserveAspectRatio="none">
      <defs><linearGradient id="cg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".35"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient></defs>
      <path id="cfill" d="" fill="url(#cg)"/>
      <path id="cpath" d="" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    <div class="cstats">
      <div><span>Liquidity</span><b id="s0">$0</b></div>
      <div><span>FDV</span><b id="s1">$0</b></div>
      <div><span>Market cap</span><b id="s2">$0</b></div>
    </div>
  </div>

  <div class="comp blue" id="comp4">
    <div class="thead"><b id="t4val">$0</b> across 33 tokens</div>
    <div class="tmap">${tiles(NET)}</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span id="pg">01 / 05</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b> · free on TestFlight</div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const easeIO=p=>p<.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2;
const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, BEAT=${BEAT}, OUT_AT=${OUT_AT}, N=${BEATS.length};
const D=${JSON.stringify(DATA)};
window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];

// build a jagged rising chart path once
const CPTS=[[0,205],[60,180],[120,196],[190,150],[250,168],[320,120],[390,138],[460,86],[540,104],[620,54],[700,66],[740,30]];
function chartD(p){
  const n=Math.max(2,Math.round(CPTS.length*p));
  const pts=CPTS.slice(0,n);
  // partial last segment for a smooth draw
  return 'M'+pts.map(q=>q[0]+' '+q[1]).join(' L');
}
function fmtUSD(v){
  if(v>=1e6) return '$'+(v/1e6).toFixed(1)+'M';
  if(v>=1e3) return '$'+(v/1e3).toFixed(0)+'K';
  return '$'+v.toFixed(0);
}

window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent;
  const pIn=clamp01((local-0.28)/1.25);   // internal animation progress (after card lands)

  // wipe
  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:INTRO+k*BEAT,c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=(active+1<10?'0':'')+(active+1);
  wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';

  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';

  // headline (beat 5 = live counting net worth)
  const he=document.getElementById('head');
  let hText=D[active].head;
  if(active===4){ hText='$'+(415.8*easeOut(pIn)).toFixed(1)+'M\\nnet worth.'; }
  he.textContent=hText;
  const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';

  document.getElementById('pg').textContent=(active+1<10?'0':'')+(active+1)+' / 0'+N;

  // cards: entrance + per-beat internal animation
  comps.forEach((c,i)=>{
    const cbs=INTRO+i*BEAT, cl=t-cbs, cin=clamp01((cl-0.12)/0.6);
    const beatEnd=INTRO+(i+1)*BEAT, outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=(1-back(cin))*180 + outp*200 + Math.sin(t*0.9+i)*5;
    const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;
    c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';
  });

  animateComp(active, pIn);

  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};

function animateComp(i,p){
  if(i===0){ // watching rows slide in, sparkline draws
    document.querySelectorAll('#comp0 .wrow').forEach((r,k)=>{
      const rp=clamp01((p-k*0.16)/0.4); r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*-46)+'px)';
    });
    const sp=document.getElementById('spark'); if(sp){const L=200; sp.style.strokeDasharray=L; sp.style.strokeDashoffset=L*(1-clamp01((p-0.35)/0.5));}
  } else if(i===1||i===4){ // treemap tiles build + value counts
    const val=(i===1?20000:415800000);
    document.getElementById(i===1?'t1val':'t4val').textContent=fmtUSD(val*easeOut(p));
    document.querySelectorAll('#comp'+i+' .tile').forEach((tl,k)=>{
      const tp=clamp01((p-k*0.09)/0.4); const s=0.6+0.4*back(tp);
      tl.style.opacity=clamp01(tp/0.5); tl.style.transform='scale('+s+')';
    });
  } else if(i===2){ // transaction amount ticks, hash reveals, rows in
    document.getElementById('txamt').textContent=(14.86*easeOut(p)).toFixed(2);
    const h=document.getElementById('txhash'); h.style.width=(clamp01((p-0.2)/0.5)*100)+'%';
    document.querySelectorAll('#comp2 .txr').forEach((r,k)=>{const rp=clamp01((p-0.4-k*0.14)/0.35); r.style.opacity=rp; r.style.transform='translateY('+((1-easeOut(rp))*16)+'px)';});
  } else if(i===3){ // chart draws, price + stats count
    document.getElementById('cpx').textContent='$'+(0.0505*easeOut(p)).toFixed(4);
    const d=chartD(clamp01(p/0.85)); document.getElementById('cpath').setAttribute('d',d);
    const fp=d==='M'?'':(d+' L740 250 L0 250 Z'); document.getElementById('cfill').setAttribute('d', d.includes('L')?fp:'');
    document.getElementById('s0').textContent=fmtUSD(503600000*easeOut(p));
    document.getElementById('s1').textContent=fmtUSD(504600000*easeOut(p));
    document.getElementById('s2').textContent=fmtUSD(504600000*easeOut(p));
  }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-wallet-live.html'), html);
console.log('wrote clip-wallet-live.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
