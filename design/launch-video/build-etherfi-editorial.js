// ether.fi promo — CONSUMER cut. Grounded line-by-line in
// Model/EtherFiUnstake.swift (2026-07-31):
//   0 — the trap: unstaking eETH does NOT return ETH. It burns the eETH and
//     mints a WithdrawRequestNFT — a claim ticket that queues ~10 days.
//   1 — the silence: it becomes claimable and then STAYS there until someone
//     remembers to press a button. Nothing pushes that moment to you.
//   2 — the proof, and it's measured, not hypothetical: three of the first
//     wallets sampled while building this were sitting on finalized,
//     unclaimed requests — one of them 5.50 ETH (ids #81111/#81112/#81114,
//     measured 2026-07-31 live against mainnet).
//   3 — what lands: ONE reconciling row per request (the ENSExpiry shape),
//     landed while queued and RETITLED in place when it turns claimable —
//     never a second row. Titles on screen are verbatim from line 255-256.
//     The queued row carries NO date on purpose (ether.fi finalizes in
//     batches at its own pace, so any date would be invented); `dueAt` is
//     set exactly when it becomes claimable, which floats it into
//     "What's coming up?". Rides watched wallets — no account, no key.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-etherfi-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const EFI = '#2F5FF7', INK = '#14110d', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'THE TRAP',    head: "Unstaking doesn't\ngive you ETH.",    accent: ORANGE, tag: null },
  { kick: 'THE SILENCE', head: 'It goes claimable.\nNobody tells you.', accent: ORANGE, tag: null },
  { kick: 'WE WENT LOOKING', head: '5.50 ETH,\njust sitting there.',  accent: INK,    tag: null },
  { kick: 'NOW',         head: 'Your ticket\ntells you itself.',      accent: GREEN,  tag: 'NEW' },
];
const INTRO = 0.45, BEAT = 3.15, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#080b16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}

/* 0 — eETH in, a ticket out */
.swap{display:flex;align-items:center;justify-content:center;gap:30px;}
.token{width:180px;height:180px;border-radius:32px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;will-change:opacity,transform;}
.token .n{font-size:34px;font-weight:800;}
.token .s{font-size:19px;font-weight:620;opacity:.6;}
.arrow{font-size:44px;font-weight:300;color:rgba(255,255,255,.35);will-change:opacity;}
.swapnote{margin-top:34px;text-align:center;font-size:24px;font-weight:680;color:rgba(255,255,255,.6);line-height:1.4;will-change:opacity;}
.swapnote em{font-style:normal;color:${ORANGE};}

/* 1 — the queue that ends in nothing */
.step{display:flex;align-items:center;gap:20px;padding:15px 0;will-change:opacity,transform;}
.step i{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:19px;font-weight:800;background:rgba(255,255,255,.08);color:rgba(255,255,255,.5);}
.step .t{font-size:24px;font-weight:650;}
.step.last i{background:rgba(255,107,74,.18);color:${ORANGE};}
.step.last .t{color:${ORANGE};font-weight:750;}
.silence{margin-top:28px;text-align:center;font-size:23px;font-weight:700;color:rgba(255,255,255,.55);will-change:opacity;}

/* 2 — what we found */
.big{text-align:center;will-change:opacity,transform;}
.big .n{font-size:132px;font-weight:800;letter-spacing:-.04em;line-height:1;}
.big .l{font-size:23px;color:rgba(255,255,255,.5);margin-top:16px;font-weight:650;line-height:1.5;}
.big .l b{color:#fff;}
.ids{margin-top:26px;display:flex;gap:10px;justify-content:center;}
.idp{font-size:18px;font-weight:700;padding:10px 16px;border-radius:100px;background:rgba(255,255,255,.07);color:rgba(255,255,255,.45);font-family:ui-monospace,"SF Mono",monospace;will-change:opacity,transform;}

/* 3 — the row that retitles itself */
.rowcard{border-radius:20px;padding:24px 26px;will-change:opacity,transform;}
.rowcard.was{background:rgba(255,255,255,.06);}
.rowcard.now{background:rgba(63,185,80,.11);border:2px solid rgba(63,185,80,.32);margin-top:16px;}
.rowcard .l{font-size:17px;font-weight:750;letter-spacing:.08em;margin-bottom:10px;color:rgba(255,255,255,.38);}
.rowcard.now .l{color:${GREEN};}
.rowcard .t{font-size:23px;font-weight:680;line-height:1.35;}
.samerow{margin-top:26px;text-align:center;font-size:22px;font-weight:700;color:rgba(255,255,255,.6);line-height:1.4;will-change:opacity;}
.samerow em{font-style:normal;color:${GREEN};}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${EFI};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>ETHER.FI</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">WHAT UNSTAKING ACTUALLY DOES</div>
    <div class="swap">
      <span class="token" id="tokA" style="background:rgba(47,95,247,.18);color:#8fa8ff"><span class="n">eETH</span><span class="s">burned</span></span>
      <span class="arrow" id="arrow">→</span>
      <span class="token" id="tokB" style="background:rgba(255,107,74,.15);color:${ORANGE}"><span class="n">NFT</span><span class="s">a claim ticket</span></span>
    </div>
    <div class="swapnote" id="swapnote">You don't get ETH back.<br>You get <em>a queue ticket</em> for about ten days.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">THE PART NOBODY BUILT</div>
    <div class="step" data-i="0"><i>1</i><span class="t">You ask to unstake</span></div>
    <div class="step" data-i="1"><i>2</i><span class="t">It queues, ~10 days</span></div>
    <div class="step" data-i="2"><i>3</i><span class="t">It becomes claimable</span></div>
    <div class="step last" data-i="3"><i>4</i><span class="t">…and sits there. Forever.</span></div>
    <div class="silence" id="silence">Nothing pushes that moment to you.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">FIRST WALLETS WE SAMPLED</div>
    <div class="big" id="big">
      <div class="n" style="color:${ORANGE}">5.50 ETH</div>
      <div class="l">finalized, claimable, <b>and nobody had claimed it</b><br>— one of three we found in a morning</div>
      <div class="ids">
        <span class="idp" data-i="0">#81111</span>
        <span class="idp" data-i="1">#81112</span>
        <span class="idp" data-i="2">#81114</span>
      </div>
    </div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">ONE ROW, RETITLED IN PLACE</div>
    <div class="rowcard was" id="rowWas">
      <div class="l mono">WHILE IT QUEUES</div>
      <div class="t">2.40 ETH is unstaking from ether.fi — still in the queue</div>
    </div>
    <div class="rowcard now" id="rowNow">
      <div class="l mono">THE DAY IT'S READY</div>
      <div class="t">Your 2.40 ETH from ether.fi is ready to claim</div>
    </div>
    <div class="samerow" id="samerow">The same row, rewritten —<br><em>and now it's in what's coming up.</em></div>
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
function pop(el,p,from,dur,dy){const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy||22))+'px)';}
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
  if(TAGS[active]){
    tag.textContent=TAGS[active];
    tag.style.background='${EFI}';tag.style.color='#fff';
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
  if(i===0){
    pop(document.getElementById('tokA'),p,0.02,0.24,18);
    document.getElementById('arrow').style.opacity=clamp01((p-0.24)/0.18);
    pop(document.getElementById('tokB'),p,0.34,0.26,18);
    document.getElementById('swapnote').style.opacity=clamp01((p-0.62)/0.26);
  } else if(i===1){
    stag('#comp1 .step',p,0.15,0.24,18);
    document.getElementById('silence').style.opacity=clamp01((p-0.7)/0.24);
  } else if(i===2){
    const bp=clamp01((p-0.06)/0.3);
    const b=document.getElementById('big');
    b.style.opacity=bp;b.style.transform='scale('+(0.86+0.14*back(bp))+')';
    document.querySelectorAll('#comp2 .idp').forEach((e,k)=>{
      const rp=clamp01((p-0.5-k*0.08)/0.2);
      e.style.opacity=rp;e.style.transform='translateY('+((1-back(rp))*12)+'px)';
    });
  } else if(i===3){
    pop(document.getElementById('rowWas'),p,0.03,0.26,20);
    pop(document.getElementById('rowNow'),p,0.36,0.28,20);
    document.getElementById('samerow').style.opacity=clamp01((p-0.7)/0.24);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-etherfi-editorial.html'),html);
console.log('wrote clip-etherfi-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
