// Gnosis Pay promo — EDITORIAL, no app screenshots: warm paper ground,
// oversized type, monospace masthead, diagonal colour wipes, hand-drawn UI.
// Grounded line-by-line in Model/GnosisPayBridge.swift + the catalog offer
// (Model/BridgeCatalog.swift, prd §220, 2026-07-26):
//   0 THE CARD   — "a Visa card that settles onchain: every purchase moves
//                  stablecoin out of your own Safe in real time."
//   1 NO ACCOUNT — the seat RIDES the watched wallets like Peer and Privacy
//                  Pools: no account, no key, no connect switch. A Gnosis Pay
//                  account IS a Safe on Gnosis Chain, and the settlement
//                  transfer is public.
//   2 IT LANDS   — the real landed title: "Spent €24.80 with Gnosis Pay",
//                  content = https://gnosisscan.io/tx/<hash>. Three spendables
//                  ship: EURe (EUR, 18), GBPe (GBP, 18), USDCe (USD, **6**).
//   3 HONEST LIMITS — the two ceilings the copy MUST keep naming: no merchant
//                  names (they never reach the chain) and no refunds (they
//                  settle off-chain — measured zero outbound from settlement).
//   4 CAPTURE ONLY — nothing here spends, tops up, freezes a card, or signs.
//                  The API path was refused BY US, not by them: it needs SIWE,
//                  and prd §112 keeps signatures out of the app entirely.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-gnosispay-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/png;base64,' + fs.readFileSync(path.join(
  __dirname, '../../Casberi/Casberi/Assets.xcassets/brand-gnosis-pay.imageset/icon.png')).toString('base64');

const LIME = '#C3F53C', INDIGO = '#3B2ED0', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'THE CARD',      head: 'A Visa that\nsettles onchain.',   accent: INDIGO },
  { kick: 'NO ACCOUNT',    head: 'It rides a wallet\nyou already watch.', accent: INDIGO },
  { kick: 'IT JUST LANDS', head: 'Every purchase,\nin your feed.',   accent: GREEN },
  { kick: 'HONEST LIMITS', head: 'What it can\'t\ntell you.',        accent: ORANGE },
  { kick: 'CAPTURE ONLY',  head: 'It can read.\nIt can never spend.', accent: INDIGO },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

// title carries the fiat rendering, `transferAmount` the token amount — the
// two fields the bridge actually sets, so the row shows one of each.
const SPENDS = [
  { m: '€24.80', t: '2h ago',    a: '24.80 EURe' },
  { m: '£12.40', t: 'yesterday', a: '12.40 GBPe' },
  { m: '$38.00', t: 'Tuesday',   a: '38.00 USDCe' },
];

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:100px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:25px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:34px;font-size:27px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — the card */
.cardwrap{display:flex;justify-content:center;padding:6px 0 4px;}
.card{width:600px;height:376px;border-radius:34px;background:linear-gradient(150deg,${LIME} 0%,${LIME} 46%,#8fd44f 70%,${INDIGO} 100%);
  padding:36px;display:flex;flex-direction:column;justify-content:space-between;box-shadow:0 26px 60px rgba(0,0,0,.5);will-change:transform;}
.card .top{display:flex;align-items:center;justify-content:space-between;}
.card .mark{width:78px;height:78px;border-radius:22px;overflow:hidden;box-shadow:0 6px 18px rgba(0,0,0,.28);}
.card .mark img{width:100%;height:100%;display:block;}
.card .visa{font-size:34px;font-weight:800;font-style:italic;color:${INDIGO};letter-spacing:-.02em;}
.card .num{font-size:34px;font-weight:700;color:${INDIGO};letter-spacing:.14em;font-family:ui-monospace,monospace;}
.card .btm{display:flex;align-items:flex-end;justify-content:space-between;}
.card .nm{font-size:24px;font-weight:700;color:rgba(59,46,208,.75);letter-spacing:.06em;}
/* 1 — rides the wallet */
.chain{display:flex;flex-direction:column;align-items:center;gap:20px;}
.node{width:100%;border-radius:22px;background:rgba(255,255,255,.06);padding:24px 28px;display:flex;align-items:center;gap:20px;will-change:opacity,transform;}
.node .ic{width:56px;height:56px;border-radius:16px;flex:none;display:flex;align-items:center;justify-content:center;overflow:hidden;}
.node .nm{font-size:28px;font-weight:700;}
.node .sb{font-size:21px;color:rgba(255,255,255,.45);margin-top:3px;}
.link{width:4px;height:26px;border-radius:3px;background:rgba(255,255,255,.2);}
.nokey{margin-top:26px;display:flex;justify-content:center;gap:16px;}
.nokey span{font-size:22px;font-weight:700;padding:12px 22px;border-radius:100px;background:rgba(255,255,255,.07);color:rgba(255,255,255,.55);}
/* 2 — rows landing */
.srow{display:flex;align-items:center;gap:20px;padding:20px 0;will-change:opacity,transform;}
.srow .ic{width:58px;height:58px;border-radius:16px;overflow:hidden;flex:none;}
.srow .ic img{width:100%;height:100%;display:block;}
.srow .t1{font-size:28px;font-weight:700;}
.srow .t2{font-size:21px;color:rgba(255,255,255,.42);margin-top:3px;}
.srow .amt{margin-left:auto;font-size:23px;font-weight:750;color:${LIME};}
.tx{margin-top:24px;font-size:21px;color:rgba(255,255,255,.35);font-family:ui-monospace,monospace;text-align:center;}
/* 3 — limits */
.lrow{display:flex;align-items:flex-start;gap:22px;padding:22px 0;will-change:opacity,transform;}
.lrow s{width:52px;height:52px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:26px;text-decoration:none;font-weight:700;}
.lrow .lt{font-size:28px;font-weight:700;}
.lrow .ls{font-size:22px;color:rgba(255,255,255,.48);margin-top:5px;line-height:1.4;}
/* 4 — capture only */
.vrow{display:flex;align-items:center;gap:22px;padding:19px 0;font-size:29px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:50px;height:50px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:25px;text-decoration:none;font-weight:700;}
.vrow span{color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.25);}
.vgood{display:flex;align-items:center;gap:20px;margin-top:26px;font-size:29px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:50px;height:50px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:26px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${INDIGO};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>GNOSIS PAY</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">THE CARD</div>
    <div class="cardwrap"><div class="card" id="card">
      <div class="top"><span class="mark"><img src="${ICON}"></span><span class="visa">VISA</span></div>
      <div class="num">•••• •••• •••• 4417</div>
      <div class="btm"><span class="nm">GNOSIS PAY</span><span class="nm">SELF-CUSTODIAL</span></div>
    </div></div>
    <div class="cap">Every purchase moves stablecoin<br><b>out of your own Safe, in real time.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">HOW IT CONNECTS</div>
    <div class="chain">
      <div class="node" data-i="0"><span class="ic" style="background:#2962ef"><svg width="30" height="30" viewBox="0 0 24 24"><rect x="2" y="6" width="20" height="13" rx="3" fill="none" stroke="#fff" stroke-width="2"/><path d="M2 10h20" stroke="#fff" stroke-width="2"/></svg></span><div><div class="nm">A wallet you watch</div><div class="sb">Already in your list</div></div></div>
      <span class="link"></span>
      <div class="node" data-i="1"><span class="ic" style="background:rgba(255,255,255,.1)"><svg width="30" height="30" viewBox="0 0 24 24"><path d="M12 2 4 6v6c0 5 3.4 9 8 10 4.6-1 8-5 8-10V6l-8-4z" fill="none" stroke="#fff" stroke-width="2"/></svg></span><div><div class="nm">is a Safe on Gnosis Chain</div><div class="sb">Public, like any other address</div></div></div>
      <span class="link"></span>
      <div class="node" data-i="2"><span class="ic"><img src="${ICON}" style="width:100%;height:100%"></span><div><div class="nm">so its card spends are too</div><div class="sb">Read straight off the chain</div></div></div>
    </div>
    <div class="nokey"><span id="nk0">No account</span><span id="nk1">No key</span><span id="nk2">No switch to flip</span></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">IN YOUR FEED</div>
    ${SPENDS.map((s,i)=>`<div class="srow" data-i="${i}"><span class="ic"><img src="${ICON}"></span><div><div class="t1">Spent ${s.m} with Gnosis Pay</div><div class="t2">${s.t}</div></div><span class="amt">${s.a}</span></div>`).join('')}
    <div class="tx" id="tx">gnosisscan.io/tx/0x7f3a…c1d9</div>
    <div class="cap">The amount, the moment,<br><b>and the transaction itself.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">TWO THINGS IT WON'T CLAIM</div>
    <div class="lrow" data-i="0"><s>✕</s><div><div class="lt">No merchant names</div><div class="ls">Where you were never reaches the chain — only what you spent, and when.</div></div></div>
    <div class="lrow" data-i="1"><s>✕</s><div><div class="lt">No refunds</div><div class="ls">Reversals settle off-chain, so this is a record of spending — not a balanced statement.</div></div></div>
    <div class="cap">We'd rather say so<br><b>than quietly guess.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">WHAT IT CANNOT DO</div>
    <div class="vrow" data-i="0"><s>✕</s><span>Spend or top up</span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Freeze a card</span></div>
    <div class="vrow" data-i="2"><s>✕</s><span>Sign anything</span></div>
    <div class="vgood" id="vgood"><i>✓</i> It reads a public chain. That's all.</div>
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
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
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
    const cp=clamp01((p-0.04)/0.4);
    const card=document.getElementById('card');
    card.style.opacity=cp;
    card.style.transform='perspective(1400px) rotateY('+((1-easeOut(cp))*26)+'deg) rotateX('+(Math.sin(t*0.8)*2.2)+'deg) scale('+(0.9+0.1*back(cp))+')';
    if(cap)cap.style.opacity=clamp01((p-0.46)/0.3);
  } else if(i===1){
    stag('#comp1 .node',p,0.16,0.32,26);
    document.querySelectorAll('#comp1 .link').forEach((l,k)=>{l.style.opacity=clamp01((p-0.12-k*0.16)/0.2);});
    [0,1,2].forEach(k=>{const e=document.getElementById('nk'+k);const rp=clamp01((p-0.52-k*0.08)/0.2);e.style.opacity=rp;e.style.transform='scale('+(0.8+0.2*back(rp))+')';});
  } else if(i===2){
    stag('#comp2 .srow',p,0.15,0.32,26);
    document.getElementById('tx').style.opacity=clamp01((p-0.55)/0.25);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.26);
  } else if(i===3){
    stag('#comp3 .lrow',p,0.18,0.34,24);
    if(cap)cap.style.opacity=clamp01((p-0.6)/0.28);
  } else if(i===4){
    stag('#comp4 .vrow',p,0.13,0.3,20);
    const vg=document.getElementById('vgood');const vp=clamp01((p-0.52)/0.28);
    vg.style.opacity=vp;vg.style.transform='translateY('+((1-back(vp))*18)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-gnosispay-editorial.html'),html);
console.log('wrote clip-gnosispay-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
