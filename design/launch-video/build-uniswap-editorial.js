// Uniswap V3 promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/UniswapLiquidity.swift, Model/UniswapAsk.swift and
// Screens/WalletLiquidityCard.swift (2026-07-30):
//   0 — a third live-state card beside Aave/Morpho in the wallet room, one
//     row per position, never summed (a range can't be averaged away).
//   1 — the range bar: in-range or out-of-range, the fact no Uniswap UI
//     volunteers unless you go and look.
//   2 — a range-crossing alert fires in BOTH directions — drifting out AND
//     re-entering, unlike Aave/Morpho's one-way liquidation alert.
//   3 — settled activity (Increase/Decrease/Collect) lands as things.
//     Capture-only, same as every DeFi read in the app.
//   4 — a lifetime-fees-collected milestone (1-2-5 ladder), the "real money
//     moved" exception to the no-tally module doctrine.
//   5 — read-only: watching the wallet is all it takes, nothing signs.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-uniswap-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const PINK = '#FF007A', GREEN = '#3fb950', ORANGE = '#FF6B4A', AAVE = '#8c40c7', MORPHO_BLUE = '#2470FF';
const BEATS = [
  { kick: 'NEW TODAY',        head: 'Your Uniswap\npositions, live.',        accent: PINK,   tag: 'NEW TODAY' },
  { kick: 'IN RANGE, OR NOT', head: "The one thing\nUniswap won't tell you.", accent: PINK,   tag: null },
  { kick: 'BOTH DIRECTIONS',  head: 'Drifts out.\nComes back. You hear it.',  accent: ORANGE, tag: null },
  { kick: 'EVERY MOVE LANDS', head: "Add, remove,\ncollect — it's all here.",accent: PINK,   tag: null },
  { kick: 'FEE MILESTONES',   head: '$500 in fees?\nWe say so.',             accent: GREEN,  tag: null },
  { kick: 'READ-ONLY',        head: 'Watching is\nall it takes.',            accent: GREEN,  tag: null },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

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
.head{position:absolute;left:70px;top:288px;right:70px;font-size:96px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — a third card beside Aave/Morpho */
.poolwrap{display:flex;flex-direction:column;gap:14px;}
.poolrow{display:flex;align-items:center;gap:18px;background:rgba(255,255,255,.06);border-radius:18px;padding:20px 24px;will-change:opacity,transform;}
.poolrow .pi{width:48px;height:48px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:18px;color:#fff;}
.poolrow .pn{font-size:25px;font-weight:700;}
.poolrow .ps{font-size:19px;color:rgba(255,255,255,.42);margin-top:2px;}
/* 1 — the range bar */
.rangecard{background:rgba(255,255,255,.06);border-radius:22px;padding:30px 28px;will-change:opacity,transform;}
.rangecard .rt{font-size:27px;font-weight:700;}
.rangecard .rs{font-size:19px;color:rgba(255,255,255,.42);margin-top:3px;font-weight:600;}
.rbar{position:relative;height:8px;margin-top:30px;border-radius:100px;background:rgba(255,255,255,.14);}
.rbar .seg{position:absolute;top:0;height:8px;border-radius:100px;background:${GREEN};}
.rbar .dot{position:absolute;top:-6px;width:20px;height:20px;border-radius:50%;background:${GREEN};box-shadow:0 0 0 6px rgba(63,185,80,.25);}
.rlabels{display:flex;justify-content:space-between;margin-top:14px;font-size:17px;color:rgba(255,255,255,.38);font-weight:650;}
/* 2 — both-direction alerts */
.alertcard{border-radius:20px;padding:24px 26px;text-align:left;will-change:opacity,transform;margin-bottom:18px;}
.alertcard .t{font-size:23px;font-weight:700;line-height:1.36;}
.alertcard.out{background:rgba(255,107,74,.1);border:2px solid rgba(255,107,74,.3);}
.alertcard.out .t b{color:${ORANGE};}
.alertcard.in{background:rgba(63,185,80,.1);border:2px solid rgba(63,185,80,.3);}
.alertcard.in .t b{color:${GREEN};}
/* 3 — activity */
.arow{display:flex;align-items:center;gap:18px;padding:16px 0;will-change:opacity,transform;}
.atag{font-size:16px;font-weight:800;padding:7px 14px;border-radius:100px;background:rgba(255,0,122,.16);color:${PINK};flex:none;}
.atxt{font-size:23px;font-weight:650;}
/* 4 — fee milestone */
.milebig{margin-top:8px;text-align:center;}
.milebig .n{font-size:104px;font-weight:800;}
.milebig .l{font-size:19px;color:rgba(255,255,255,.42);margin-top:6px;font-weight:600;letter-spacing:.04em;}
/* 5 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:19px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${PINK};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>WALLET</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">THE WALLET ROOM, NOW WITH THREE</div>
    <div class="poolwrap">
      <div class="poolrow" data-i="0"><span class="pi" style="background:${AAVE}">A</span><div><div class="pn">Aave</div><div class="ps">Collateral $48.2k · debt $12.1k</div></div></div>
      <div class="poolrow" data-i="1"><span class="pi" style="background:${MORPHO_BLUE}">M</span><div><div class="pn">Morpho</div><div class="ps">Health factor 2.4</div></div></div>
      <div class="poolrow" data-i="2"><span class="pi" style="background:${PINK}">U</span><div><div class="pn">Uniswap</div><div class="ps">ETH / USDC · in range</div></div></div>
    </div>
    <div class="cap">One row per position, never summed —<br><b>a range can't be averaged away.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">SELF-SCALING, LIVE</div>
    <div class="rangecard" id="rangecard">
      <div class="rt">ETH / USDC</div>
      <div class="rs">In range · Base</div>
      <div class="rbar"><span class="seg" style="left:22%;width:38%"></span><span class="dot" style="left:39%"></span></div>
      <div class="rlabels"><span>LOWER</span><span>UPPER</span></div>
    </div>
    <div class="cap">Earning only while price sits inside —<br><b>drifting out is silent, until now.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">ON THE CROSSING, EITHER WAY</div>
    <div class="alertcard out" id="alertOut"><div class="t">Your ETH/USDC position drifted <b>out of range</b> — it stopped earning fees</div></div>
    <div class="alertcard in" id="alertIn"><div class="t">Your ETH/USDC position is <b>back in range</b> and earning again</div></div>
    <div class="cap">Re-entering range is real news too —<br><b>not just the bad kind.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">SETTLED, NEVER PENDING</div>
    <div class="arow" data-i="0"><span class="atag">ADD</span><span class="atxt">Added 2.0 ETH + 4,200 USDC</span></div>
    <div class="arow" data-i="1"><span class="atag">REMOVE</span><span class="atxt">Removed liquidity from WBTC/ETH</span></div>
    <div class="arow" data-i="2"><span class="atag">COLLECT</span><span class="atxt">Collected $340 in fees on Uniswap</span></div>
    <div class="cap">Capture-only —<br><b>never a pending intent, never a trade.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">REAL MONEY, NOT A TALLY</div>
    <div class="milebig"><div class="n" style="color:${GREEN}">$500</div><div class="l">IN UNISWAP FEES COLLECTED</div></div>
    <div class="cap">The one number worth counting —<br><b>fees actually collected, never pending.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never signs a transaction</div>
    <div class="vrow" data-i="1"><s>✕</s> Never needs a key</div>
    <div class="vrow" data-i="2"><s>✕</s> Never a separate connect step</div>
    <div class="vgood" id="vgood"><i>✓</i> Watching your wallet is all it takes.</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="tagpill" id="tagpill"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const TAGS=${JSON.stringify(BEATS.map(b=>b.tag))};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.7);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(40,Math.min(240,780/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const tag=document.getElementById('tagpill');
  if(TAGS[active]){
    tag.textContent=TAGS[active];
    tag.style.background='rgba(255,0,122,.15)';
    tag.style.color='${PINK}';
    tag.style.opacity=easeOut(kin);
    tag.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  } else { tag.style.opacity=0; }
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  const cap=document.querySelector('#comp'+i+' .cap');
  if(i===0){
    stag('#comp0 .poolrow',p,0.2,0.32,22);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===1){
    const cp=clamp01((p-0.08)/0.3);
    const rc=document.getElementById('rangecard');
    rc.style.opacity=cp;rc.style.transform='scale('+(0.9+0.1*back(cp))+')';
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===2){
    const op1=clamp01((p-0.08)/0.28);
    const o=document.getElementById('alertOut');o.style.opacity=op1;o.style.transform='scale('+(0.92+0.08*back(op1))+')';
    const op2=clamp01((p-0.42)/0.28);
    const g=document.getElementById('alertIn');g.style.opacity=op2;g.style.transform='scale('+(0.92+0.08*back(op2))+')';
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===3){
    stag('#comp3 .arow',p,0.15,0.28,20);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===4){
    const mp=clamp01((p-0.14)/0.32);
    const m=document.querySelector('#comp4 .milebig');m.style.opacity=mp;m.style.transform='scale('+(0.85+0.15*back(mp))+')';
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-uniswap-editorial.html'),html);
console.log('wrote clip-uniswap-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
