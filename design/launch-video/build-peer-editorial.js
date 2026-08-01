// Peer promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/PeerBridge.swift, both the original build (prd §113, 2026-07-17) and
// today's addition (prd §237, "what else can we do with Peer", 2026-07-29):
//   0 RIDES YOUR WALLET — no account, no key; watching a wallet IS consent,
//     same shape as Privacy Pools.
//   1 THE BUY SIDE (existing) — "Bought 25 USDC with Cash App on Peer",
//     landed only once a trade SETTLES.
//   2 THE SELL SIDE (NEW) — the maker/offramp side, walked via the escrow's
//     depositor: "Sold 34.13 USDC with Venmo on Peer."
//   3 RATE CONTEXT (NEW) — every fill already decoded conversionRate and
//     threw it away; now it becomes one line: "You paid $30.00 for 34.13
//     USDC — about 0.3% above market."
//   4 STUCK INTENTS (NEW) — Peer's own 6h INTENT_EXPIRATION releases a
//     signaled-but-unfulfilled intent back to the deposit; that reclaim now
//     lands once: "A buyer's payment fell through — your money's available
//     again on Peer."
//   5 CAPTURE ONLY — a thing lands when a trade SETTLES, never before;
//     nothing here starts a trade.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-peer-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/png;base64,' + fs.readFileSync(path.join(
  __dirname, '../../Casberi/Casberi/Assets.xcassets/brand-peer.imageset/icon.png')).toString('base64');

const PEER = '#4b47f6', GREEN = '#3fb950', AMBER = '#ff9f0a', VIOLET = '#8c40c7', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'RIDES YOUR WALLET', head: 'No account.\nNo key.',           accent: PEER },
  { kick: 'THE BUY SIDE',      head: 'Bought something?\nIt lands.',    accent: GREEN },
  { kick: 'THE SELL SIDE',     head: 'Sold something?\nNow it lands too.', accent: VIOLET },
  { kick: 'RATE CONTEXT',      head: 'What you paid,\nagainst the market.', accent: AMBER },
  { kick: 'STUCK INTENTS',     head: 'Payment fell through?\nYou\'ll know.', accent: ORANGE },
  { kick: 'CAPTURE ONLY',      head: 'It lands\nwhen it settles.',       accent: PEER },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

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
.newtag{position:absolute;top:48px;right:52px;font-size:16px;font-weight:800;letter-spacing:.06em;padding:6px 14px;border-radius:100px;background:${AMBER}22;color:${AMBER};}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — rides wallet */
.chain{display:flex;flex-direction:column;align-items:center;gap:18px;}
.node{width:100%;border-radius:22px;background:rgba(255,255,255,.06);padding:22px 26px;display:flex;align-items:center;gap:18px;will-change:opacity,transform;}
.node .ic{width:52px;height:52px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;overflow:hidden;}
.node .nm{font-size:26px;font-weight:700;}
.node .sb{font-size:20px;color:rgba(255,255,255,.42);margin-top:2px;}
.link{width:4px;height:24px;border-radius:3px;background:rgba(255,255,255,.2);}
/* landed-thing card (shared 1/2/4) */
.landcard{background:rgba(255,255,255,.06);border-radius:24px;padding:28px;display:flex;align-items:center;gap:18px;will-change:opacity,transform;}
.landcard .li{width:56px;height:56px;border-radius:16px;flex:none;overflow:hidden;}
.landcard .lt{font-size:26px;font-weight:700;line-height:1.3;}
.landcard .ls{font-size:19px;color:rgba(255,255,255,.42);margin-top:5px;}
/* 3 — rate context */
.ratecard{background:rgba(255,255,255,.06);border-radius:24px;padding:30px;text-align:center;}
.ratebig{font-size:30px;font-weight:700;line-height:1.35;}
.ratepill{margin-top:18px;display:inline-flex;align-items:center;gap:10px;padding:12px 22px;border-radius:100px;background:${GREEN}1e;color:${GREEN};font-size:22px;font-weight:750;}
/* 4 — stuck released */
.releasecard{background:rgba(255,255,255,.06);border-radius:24px;padding:28px;will-change:opacity,transform;}
.releasetop{display:flex;align-items:center;gap:14px;}
.reldot{width:13px;height:13px;border-radius:50%;background:${ORANGE};}
.rellbl{font-size:19px;font-weight:700;color:rgba(255,255,255,.5);letter-spacing:.04em;}
.reltext{margin-top:14px;font-size:26px;font-weight:700;line-height:1.35;}
/* 5 — capture only */
.vrow{display:flex;align-items:center;gap:20px;padding:18px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${PEER};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span class="brand"><img src="${ICON}"><span>PEER</span></span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">HOW IT CONNECTS</div>
    <div class="chain">
      <div class="node" data-i="0"><span class="ic" style="background:#2962ef"><svg width="28" height="28" viewBox="0 0 24 24"><rect x="2" y="6" width="20" height="13" rx="3" fill="none" stroke="#fff" stroke-width="2"/><path d="M2 10h20" stroke="#fff" stroke-width="2"/></svg></span><div><div class="nm">A wallet you watch</div><div class="sb">Already in your list</div></div></div>
      <span class="link"></span>
      <div class="node" data-i="1"><span class="ic"><img src="${ICON}" style="width:100%;height:100%"></span><div><div class="nm">is consent to watch</div><div class="sb">No account, no key, no switch to flip</div></div></div>
    </div>
    <div class="cap">Peer's identity <b>is</b> the wallet —<br>watching it is the whole connection.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">BUY SIDE</div>
    <div class="landcard" id="buycard"><span class="li"><img src="${ICON}" style="width:100%;height:100%"></span><div><div class="lt">Bought 25 USDC with Cash App on Peer</div><div class="ls">Settled — the funds are already yours</div></div></div>
    <div class="cap">Not a bare transfer —<br><b>the platform, the fiat, the why.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="newtag">NEW</div>
    <div class="shd mono">SELL SIDE</div>
    <div class="landcard" id="sellcard"><span class="li"><img src="${ICON}" style="width:100%;height:100%"></span><div><div class="lt">Sold 34.13 USDC with Venmo on Peer</div><div class="ls">Your liquidity, taken by a buyer</div></div></div>
    <div class="cap">The maker side had no shortcut —<br><b>now it's read just as cleanly.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="newtag">NEW</div>
    <div class="shd mono">AGAINST THE MARKET</div>
    <div class="ratecard">
      <div class="ratebig">You paid <b>$30.00</b> for <b>34.13 USDC</b></div>
      <div class="ratepill" id="ratepill">▲ about 0.3% above market</div>
    </div>
    <div class="cap">The rate was always in the event —<br><b>now it's a line, not a discard.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="newtag">NEW</div>
    <div class="shd mono">RELEASED, NOT LOST</div>
    <div class="releasecard" id="releasecard">
      <div class="releasetop"><span class="reldot"></span><span class="rellbl">EXPIRED INTENT</span></div>
      <div class="reltext">A buyer's payment fell through — your 34.13 USDC is available again on Peer</div>
    </div>
    <div class="cap">Used to be invisible.<br><b>Now it lands once, honestly.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">CAPTURE ONLY</div>
    <div class="vrow" data-i="0"><s>✕</s> Never starts a trade</div>
    <div class="vrow" data-i="1"><s>✕</s> Never lands before it settles</div>
    <div class="vrow" data-i="2"><s>✕</s> Never guesses a rate it can't verify</div>
    <div class="vgood" id="vgood"><i>✓</i> Reads a public chain. That's all.</div>
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
    stag('#comp0 .node',p,0.16,0.3,20);
    document.querySelectorAll('#comp0 .link').forEach((l)=>{l.style.opacity=clamp01((p-0.2)/0.2);});
    if(cap)cap.style.opacity=clamp01((p-0.56)/0.3);
  } else if(i===1){
    const cp=clamp01((p-0.06)/0.28);
    const c=document.getElementById('buycard');
    c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*18)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.5)/0.3);
  } else if(i===2){
    const cp=clamp01((p-0.06)/0.28);
    const c=document.getElementById('sellcard');
    c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*18)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.5)/0.3);
  } else if(i===3){
    document.querySelector('#comp3 .ratecard').style.opacity=clamp01((p-0.04)/0.24);
    document.getElementById('ratepill').style.opacity=clamp01((p-0.42)/0.3);
    if(cap)cap.style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===4){
    const cp=clamp01((p-0.06)/0.28);
    const c=document.getElementById('releasecard');
    c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*18)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.56)/0.3);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.16,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-peer-editorial.html'),html);
console.log('wrote clip-peer-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
