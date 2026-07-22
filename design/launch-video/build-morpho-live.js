// Morpho promo (2026-07-21, prd §157) — the first clip to MIX real captures
// with the editorial frame: three beats show genuine simulator screenshots
// (the Wallet feed's Morpho tile + liquidation warning, a landed borrow's
// thing sheet, the composer's live health-factor answer — all real data from
// a real borrower wallet, shot the day the seat shipped), and three beats
// are rebuilt-UI editorial in the house style (paper ground, oversized type,
// mono masthead, colour wipes). Real shots live in shots-morpho/ and are
// inlined as base64 so the html stays self-contained.
// Deterministic → node render.js clip-morpho-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const BLUE = '#2E63FF', AMBER = '#E8912A', RED = '#E5484D', GRN = '#3fb950';
const SHOTS = path.join(__dirname, 'shots-morpho');
const shot = n => 'data:image/png;base64,' + fs.readFileSync(path.join(SHOTS, n)).toString('base64');

const BEATS = [
  { kick: 'NEW SEAT',       head: 'Morpho,\nwatched.',        accent: BLUE,  dur: 2.7 },
  { kick: 'THE LIVE BOOK',  head: 'Your loans,\nlive.',        accent: BLUE,  dur: 2.7 },
  { kick: 'SETTLED EVENTS', head: 'Every move\nlands.',        accent: BLUE,  dur: 2.7 },
  { kick: 'WORTH A LOOK',   head: 'Before it\nliquidates.',    accent: RED,   dur: 2.5 },
  { kick: 'ASK',            head: 'Ask it\nplainly.',          accent: AMBER, dur: 2.7 },
  { kick: 'READ-ONLY',      head: 'Watching can\nnever trade.', accent: GRN,  dur: 2.3 },
];
const INTRO = 0.45;
const durs = BEATS.map(b => b.dur);
const STARTS = []; { let acc = INTRO; for (const d of durs) { STARTS.push(acc); acc += d; } }
const OUT_AT = STARTS[STARTS.length - 1] + durs[durs.length - 1];
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

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
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;z-index:5;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;z-index:8;}

/* --- comp cards --- */
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;
  transform-origin:center top;padding:52px;color:#fff;}
.comp.blue{background:linear-gradient(160deg,#2E63FF,#1B49D6);}
.comp.dark{background:#0d0e13;}
.comp.red{background:linear-gradient(160deg,#3a1216,#1a0a0c);}
.comp.grn{background:linear-gradient(160deg,#0f2e1c,#0a1a10);}
/* a REAL capture fills its card edge to edge; the drift is the only motion */
.comp.shot{padding:0;background:#0b0d12;height:900px;}
.comp.shot img{display:block;width:840px;will-change:transform;}
.shotcap{position:absolute;left:0;right:0;bottom:0;padding:26px 34px;display:flex;align-items:center;gap:14px;
  background:linear-gradient(transparent, rgba(5,6,9,.92) 45%);font-size:25px;font-weight:600;color:rgba(255,255,255,.92);z-index:2;}
.livechip{padding:7px 16px;border-radius:100px;background:rgba(63,185,80,.18);color:#7dffb0;font-size:20px;letter-spacing:.1em;font-weight:700;flex:none;}

/* rebuilt Morpho tile (beat 0) */
.mtcap{font-size:27px;color:rgba(255,255,255,.6);font-weight:600;}
.mstats{display:flex;gap:34px;margin-top:30px;}
.mstat span{display:block;font-size:24px;color:rgba(255,255,255,.55);white-space:nowrap;}
.mstat b{font-size:44px;font-weight:800;letter-spacing:-.02em;display:block;margin-top:6px;}
.mstat b.risk{color:#ffb864;}
.pledge{display:flex;align-items:flex-start;gap:18px;margin-top:44px;padding-top:36px;border-top:2px solid rgba(255,255,255,.12);will-change:opacity,transform;}
.pledge .dot{background:${GRN};margin-top:9px;}
.pledge p{font-size:27px;line-height:1.5;color:rgba(255,255,255,.82);}
.pledge b{color:#fff;}
.dot{width:12px;height:12px;border-radius:50%;background:rgba(255,255,255,.5);flex:none;margin-top:10px;}

/* worth-a-look rows (beat 3) */
.lrow{display:flex;align-items:flex-start;gap:20px;padding:19px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.lrow:first-of-type{border-top:none;}
.lt{font-size:32px;font-weight:700;}
.lt .risk{color:#ff9a9e;}
.ls{font-size:24px;color:rgba(255,255,255,.6);margin-top:4px;line-height:1.4;}

.outro{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:20px;opacity:0;z-index:9;}
.outro .big{font-size:120px;font-weight:800;letter-spacing:-.04em;color:#14110d;}
.outro .sm{font-size:30px;letter-spacing:.14em;color:#14110d;font-weight:600;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI — WALLET</span><span>№ MORPHO</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm"></div>
  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>

  <div class="comp dark" id="comp0" style="height:520px">
    <div class="mtcap">DeFi · Morpho on Ethereum</div>
    <div class="mstats">
      <div class="mstat"><span>Collateral</span><b id="m0c">$0</b></div>
      <div class="mstat"><span>Debt</span><b id="m0d">$0</b></div>
      <div class="mstat"><span>Health · at risk</span><b class="risk" id="m0h">—</b></div>
    </div>
    <div class="pledge"><b class="dot"></b><p>No account, no key, nothing to connect — <b>Morpho rides the wallets you already watch</b>, markets and vaults both.</p></div>
  </div>

  <div class="comp shot" id="comp1"><img id="img1" src="${shot('feed.png')}">
    <div class="shotcap"><span class="livechip mono">REAL SCREEN</span><span>The Wallet feed, reading a live borrower — nothing staged.</span></div>
  </div>

  <div class="comp shot" id="comp2"><img id="img2" src="${shot('sheet.png')}">
    <div class="shotcap"><span class="livechip mono">REAL SCREEN</span><span>A settled borrow, landed as a thing — the explorer link is the door.</span></div>
  </div>

  <div class="comp red" id="comp3" style="height:600px">
    <div class="lrow"><b class="dot" style="background:${RED}"></b><div><div class="lt">Morpho position <span class="risk">close to liquidation</span></div><div class="ls">Ethereum · kBTC / RLUSD · health factor 1.25</div></div></div>
    <div class="lrow"><b class="dot"></b><div><div class="lt">Each market warns on its own</div><div class="ls">Morpho markets are isolated — two risky markets are two liquidations, not one.</div></div></div>
    <div class="lrow"><b class="dot"></b><div><div class="lt">Acting stays on Morpho</div><div class="ls">The alert links app.morpho.org. Casberi reads; it never touches.</div></div></div>
  </div>

  <div class="comp shot" id="comp4"><img id="img4" src="${shot('ask.png')}">
    <div class="shotcap"><span class="livechip mono">REAL SCREEN</span><span>Asked in the composer, answered from the live book.</span></div>
  </div>

  <div class="comp grn" id="comp5" style="height:470px">
    <div class="pledge" style="margin-top:8px;padding-top:0;border-top:none;"><b class="dot"></b><p><b>Settled events only.</b> Never a pending intent, never a signature, never a path that trades.</p></div>
    <div class="pledge"><b class="dot"></b><p>Public data, read keyless from Morpho's own API — <b>on your phone, for your eyes</b>.</p></div>
  </div>

  <div class="foot mono"><span>CASBERI.APP</span><span>AAVE + MORPHO · 2026</span></div>
  <div class="outro"><div class="big">casberi.app</div><div class="sm mono">YOUR WALLETS, WATCHED</div></div>
  <div class="wipe" id="wipe"></div>
</div>
<script>
window.TOTAL=${TOTAL.toFixed(2)};
const D=${JSON.stringify(DATA)};
const START=${JSON.stringify(STARTS.map(s => +s.toFixed(3)))};
const DUR=${JSON.stringify(durs)};
const OUT_AT=${OUT_AT.toFixed(3)};
const N=D.length;
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const back=p=>{const c=1.35;const q=p-1;return 1+(c+1)*q*q*q+c*q*q;};
const comps=[...document.querySelectorAll('.comp')];
function fmtUSD(v){ return '$'+Math.round(v).toLocaleString('en-US'); }
function activeAt(t){ for(let i=N-1;i>=0;i--) if(t>=START[i]) return i; return 0; }

window.seek=function(t){
  const active=activeAt(t);
  const bs=START[active], local=t-bs, dur=DUR[active], acc=D[active].accent;
  const pIn=clamp01((local-0.26)/Math.max(0.5,dur-0.45));

  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:START[k],c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=D[active].kick;
  wm.style.fontSize=Math.max(80,Math.min(320,900/(0.6*D[active].kick.length)))+'px';
  wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';

  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';

  const he=document.getElementById('head'); he.textContent=D[active].head;
  const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';

  comps.forEach((c,i)=>{
    const cbs=START[i], cl=t-cbs, cin=clamp01((cl-0.12)/0.6);
    const beatEnd=START[i]+DUR[i], outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=(1-back(cin))*180 + outp*200 + Math.sin(t*0.9+i)*5;
    const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;
    c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';
  });

  animateComp(active, pIn, t-START[active]);

  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.querySelector('.outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};

function staggerRows(sel,p,stagger,dur,dx){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*stagger)/dur);
    r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*(dx||-40))+'px)';
  });
}

function animateComp(i,p,local){
  if(i===0){ // the rebuilt tile counts up to the REAL measured numbers
    document.getElementById('m0c').textContent=fmtUSD(134124608*easeOut(p));
    document.getElementById('m0d').textContent=fmtUSD(92611662*easeOut(p));
    document.getElementById('m0h').textContent=(p<0.2)?'—':(1.25*easeOut(clamp01((p-0.2)/0.6))+0).toFixed(2);
    const pl=document.querySelector('#comp0 .pledge'); const pp=clamp01((p-0.45)/0.4);
    pl.style.opacity=pp; pl.style.transform='translateY('+((1-easeOut(pp))*14)+'px)';
  } else if(i===1){ // real feed capture: slow drift up (Ken Burns, nothing else)
    document.getElementById('img1').style.transform='translateY('+(-80*easeOut(p))+'px)';
  } else if(i===2){
    document.getElementById('img2').style.transform='translateY('+(-40*easeOut(p))+'px)';
  } else if(i===3){
    staggerRows('#comp3 .lrow', p, 0.16, 0.38, -40);
  } else if(i===4){
    document.getElementById('img4').style.transform='translateY('+(-14*easeOut(p))+'px)';
  } else if(i===5){
    staggerRows('#comp5 .pledge', p, 0.22, 0.42, -30);
  }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-morpho-live.html'), html);
console.log('wrote clip-morpho-live.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's', BEATS.length + ' beats');
