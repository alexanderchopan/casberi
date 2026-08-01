// Aerodrome promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/AerodromeDeFi.swift (2026-07-30):
//   0 — veAERO locks for a watched wallet on Base, read straight off the
//     VotingEscrow/Voter contracts (keyless eth_call) — no account, no key,
//     no connect switch, the Peer/Gnosis Pay shape.
//   1 — THE WEEKLY VOTE: a held lock that hasn't voted this epoch lands as a
//     dated thing riding "Coming up" — window closes Wed 23:00 UTC, one hour
//     before the epoch flips (read live off the contract, never computed
//     locally). Measured: one sampled lock holding 2,690 AERO last voted
//     April 2024 — TWO YEARS of missed epochs. Nothing in Aerodrome's own
//     UI pushes this.
//   2 — the MELTING lock: a non-permanent lock's voting power visibly
//     decays toward its end (measured real: 2,690.13 AERO → 2,681.06 votes);
//     a permanent lock doesn't melt (390.38 → 390.38).
//   3 — lock EXPIRY lands as a dated row that reconciles if the date moves
//     (the ENSExpiry shape); permanent locks never land one, by definition.
//   4 — read-only: watching the wallet is all it takes, nothing votes,
//     nothing signs.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-aerodrome-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const AEROBLUE = '#2A54F3', SKY = '#57A6FF', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'NEW TODAY',        head: 'Your veAERO,\nwatched.',               accent: AEROBLUE, tag: 'NEW TODAY' },
  { kick: 'THE WEEKLY VOTE',  head: "Voting closes Wed.\nDid you?",         accent: AEROBLUE, tag: null },
  { kick: 'MEASURED',         head: 'One lock: silent\nsince April 2024.',  accent: ORANGE,   tag: null },
  { kick: 'THE MELT',         head: 'Votes decay.\nWatch them do it.',      accent: SKY,      tag: null },
  { kick: 'LOCK EXPIRY',      head: 'The end date,\non your calendar.',     accent: SKY,      tag: null },
  { kick: 'READ-ONLY',        head: 'Watching is\nall it takes.',           accent: GREEN,    tag: null },
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0b0e1a;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — the lock, as a card */
.lockcard{background:rgba(255,255,255,.06);border-radius:22px;padding:30px;will-change:opacity,transform;}
.lockcard .lt{font-size:27px;font-weight:700;}
.lockcard .ls{font-size:19px;color:rgba(255,255,255,.42);margin-top:4px;font-weight:600;}
.lockrow{display:flex;justify-content:space-between;margin-top:22px;font-size:22px;font-weight:650;will-change:opacity;}
.lockrow span:last-child{color:${SKY};}
/* 1 — vote deadline */
.votecard{background:rgba(42,84,243,.12);border:2px solid rgba(42,84,243,.35);border-radius:22px;padding:28px;text-align:left;will-change:opacity,transform;}
.votecard .t{font-size:24px;font-weight:700;line-height:1.4;}
.votecard .t b{color:${SKY};}
.votewhen{margin-top:20px;display:flex;align-items:center;gap:14px;font-size:20px;font-weight:700;color:rgba(255,255,255,.6);will-change:opacity;}
.votewhen i{width:40px;height:40px;border-radius:12px;flex:none;background:rgba(87,166,255,.16);color:${SKY};display:flex;align-items:center;justify-content:center;font-style:normal;font-size:19px;}
/* 2 — silent since */
.silentbig{text-align:center;will-change:opacity,transform;}
.silentbig .n{font-size:84px;font-weight:800;color:${ORANGE};letter-spacing:-.03em;}
.silentbig .l{font-size:22px;color:rgba(255,255,255,.5);margin-top:10px;font-weight:650;line-height:1.5;}
.silentbig .l b{color:#fff;}
/* 3 — the melt */
.meltwrap{will-change:opacity;}
.meltbar{position:relative;height:56px;border-radius:16px;background:rgba(255,255,255,.07);overflow:hidden;}
.meltbar .amt{position:absolute;inset:0;display:flex;align-items:center;padding:0 22px;font-size:22px;font-weight:750;z-index:2;}
.meltbar .fill{position:absolute;left:0;top:0;bottom:0;background:linear-gradient(90deg,${AEROBLUE},${SKY});will-change:width;}
.meltlabels{display:flex;justify-content:space-between;margin-top:12px;font-size:18px;color:rgba(255,255,255,.4);font-weight:650;}
.meltnote{margin-top:26px;text-align:center;font-size:21px;font-weight:700;color:rgba(255,255,255,.6);will-change:opacity;}
.meltnote b{color:${SKY};}
/* 4 — expiry */
.expirycard{background:rgba(87,166,255,.08);border:2px solid rgba(87,166,255,.25);border-radius:22px;padding:30px;text-align:center;will-change:opacity,transform;}
.expirycard .d{font-size:64px;font-weight:800;color:${SKY};}
.expirycard .t{margin-top:10px;font-size:24px;font-weight:700;}
.expirycard .s{margin-top:8px;font-size:19px;color:rgba(255,255,255,.42);font-weight:600;}
/* 5 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:19px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AEROBLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>WALLET</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">READ OFF THE CONTRACTS, KEYLESS</div>
    <div class="lockcard" id="lockcard">
      <div class="lt">veAERO #71205</div>
      <div class="ls">On Base · read straight off VotingEscrow</div>
      <div class="lockrow" data-i="0"><span>Locked</span><span>2,690 AERO</span></div>
      <div class="lockrow" data-i="1"><span>Voting power</span><span>2,681 votes</span></div>
      <div class="lockrow" data-i="2"><span>Unlocks</span><span>Jul 2030</span></div>
    </div>
    <div class="cap">No account, no key, no connect step —<br><b>watching your wallet is the whole setup.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">RIDES "COMING UP"</div>
    <div class="votecard" id="votecard">
      <div class="t">Aerodrome voting closes <b>Wed 11:00 PM</b> — your veAERO #71205 (2,681 votes) hasn't voted this epoch</div>
    </div>
    <div class="votewhen" id="votewhen"><i>◷</i> The window closes one hour before the epoch flips — read live off the Voter contract</div>
    <div class="cap">A dated thing, next to real calendar events —<br><b>your votes stop missing weeks.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">A REAL SAMPLED LOCK</div>
    <div class="silentbig" id="silentbig">
      <div class="n">Apr 2024</div>
      <div class="l">the last time one measured lock voted —<br><b>2,690 AERO</b> sitting out every epoch since</div>
    </div>
    <div class="cap">Two years of missed weeks —<br><b>exactly the gap this alert exists for.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">MEASURED, NOT ESTIMATED</div>
    <div class="meltwrap">
      <div class="meltbar"><span class="fill" id="meltfill"></span><span class="amt" id="meltamt">2,681.06 votes</span></div>
      <div class="meltlabels"><span>DECAYS TOWARD LOCK END</span><span>2,690.13 AERO</span></div>
      <div class="meltnote" id="meltnote">A permanent lock doesn't melt — <b>390.38 stays 390.38</b></div>
    </div>
    <div class="cap">The decay is in the chain's own numbers —<br><b>not a derived estimate.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">THE ENS-EXPIRY SHAPE</div>
    <div class="expirycard" id="expirycard">
      <div class="d">Jul 25</div>
      <div class="t">veAERO #71205 lock expires</div>
      <div class="s">Extend it and the date moves with it</div>
    </div>
    <div class="cap">Permanent locks never land one —<br><b>they don't expire, by definition.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never casts a vote</div>
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
    tag.style.background='rgba(42,84,243,.13)';
    tag.style.color='${AEROBLUE}';
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
    const cp=clamp01((p-0.04)/0.28);
    const lc=document.getElementById('lockcard');
    lc.style.opacity=cp;lc.style.transform='scale('+(0.92+0.08*back(cp))+')';
    document.querySelectorAll('#comp0 .lockrow').forEach((r,k)=>{
      r.style.opacity=clamp01((p-0.3-k*0.12)/0.24);
    });
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===1){
    const vp=clamp01((p-0.06)/0.28);
    const vc=document.getElementById('votecard');
    vc.style.opacity=vp;vc.style.transform='scale('+(0.92+0.08*back(vp))+')';
    document.getElementById('votewhen').style.opacity=clamp01((p-0.46)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===2){
    const sp=clamp01((p-0.1)/0.34);
    const sb=document.getElementById('silentbig');
    sb.style.opacity=sp;sb.style.transform='scale('+(0.88+0.12*back(sp))+')';
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.24);
  } else if(i===3){
    document.querySelector('#comp3 .meltwrap').style.opacity=clamp01((p-0.04)/0.24);
    // the melt: fill narrows slightly from full — decay visualized honestly
    // (2681.06/2690.13 = 99.66%, exaggerated to 86% for legibility... no —
    // keep it honest: draw 99.7% but ANIMATE the approach so the eye sees
    // motion, not a lie about scale)
    const mp=clamp01((p-0.24)/0.5);
    document.getElementById('meltfill').style.width=(100-mp*0.34)+'%';
    document.getElementById('meltnote').style.opacity=clamp01((p-0.58)/0.26);
    if(cap)cap.style.opacity=clamp01((p-0.76)/0.2);
  } else if(i===4){
    const ep=clamp01((p-0.1)/0.32);
    const ec=document.getElementById('expirycard');
    ec.style.opacity=ep;ec.style.transform='scale('+(0.88+0.12*back(ep))+')';
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-aerodrome-editorial.html'),html);
console.log('wrote clip-aerodrome-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
