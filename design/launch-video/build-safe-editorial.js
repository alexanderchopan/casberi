// Safe promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/SafeBridge.swift (2026-07-20, extended 2026-07-30). Three ways a
// watched wallet touches a Safe, all keyless against Safe's own Transaction
// Service, all riding the existing wallet watch — no separate connect step:
//   0 EXISTING (2026-07-20) — watch a Safe directly and its pending
//     signature queue lands as things: exact title format
//     "2 of 3 signatures collected on a transfer to vitalik.eth".
//   1 NEW (2026-07-30) — signer discovery: watching your own EOA now finds
//     every Safe that names it as an owner, even ones you never added
//     yourself, via /owners/{eoa}/safes/. Filtered to real Safes only
//     (non-empty pending queue AND nonce>0) so a spam-deployed decoy naming
//     a stranger doesn't surface.
//   2 NEW (2026-07-30) — once we know which owner you are, the queue item
//     says so plainly: "— your signature is needed" vs "— waiting on
//     others".
//   3 NEW (2026-07-30) — config-change alerts, seeded silently on first
//     sight then fired only on drift: a new/removed owner, a changed
//     threshold, and the highest-stakes one stated plainly rather than
//     folded into a generic line — "enabled a module that can move funds
//     without a signature".
//   4 READ-ONLY — nothing here ever signs; that always happens in the
//     person's own Safe app.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-safe-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/png;base64,' + fs.readFileSync(path.join(__dirname, 'safe-icon.png')).toString('base64');
const SAFE_GREEN = '#12ff80', GREEN = '#3fb950', AMBER = '#ff9f0a', ORANGE = '#FF6B4A', VIOLET = '#8c40c7';
const BEATS = [
  { kick: 'THE QUEUE, LIVE',   head: 'Every pending\nsignature.',       accent: SAFE_GREEN },
  { kick: 'NEW: SIGNER FOUND', head: 'Not just Safes\nyou added.',      accent: VIOLET },
  { kick: "NEW: YOUR TURN?",   head: 'It says whose\nturn it is.',      accent: AMBER },
  { kick: 'NEW: CONFIG ALERTS', head: 'A module changed?\nYou\'ll know.', accent: ORANGE },
  { kick: 'READ-ONLY',         head: 'Signing stays\nin your Safe app.', accent: GREEN },
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:94px;line-height:1;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:25px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — queue */
.qcard{background:rgba(255,255,255,.06);border-radius:24px;padding:30px;}
.qtitle{font-size:26px;font-weight:700;line-height:1.32;}
.qbar{margin-top:22px;height:14px;border-radius:8px;background:rgba(255,255,255,.1);overflow:hidden;}
.qfill{height:100%;width:0%;background:${SAFE_GREEN};border-radius:8px;will-change:width;}
.qnums{margin-top:14px;display:flex;justify-content:space-between;font-size:20px;color:rgba(255,255,255,.5);font-weight:650;}
.qnums b{color:#fff;font-size:24px;}
/* 1 — signer discovery */
.discrow{display:flex;align-items:center;gap:18px;padding:18px 0;will-change:opacity,transform;}
.discrow .di{width:52px;height:52px;border-radius:16px;flex:none;display:flex;align-items:center;justify-content:center;}
.discrow .dt{font-size:25px;font-weight:700;}
.discrow .ds{font-size:19px;color:rgba(255,255,255,.42);margin-top:3px;}
/* 2 — your turn */
.turnrow{display:flex;align-items:center;gap:18px;padding:20px 0;will-change:opacity,transform;}
.turntag{font-size:18px;font-weight:800;padding:9px 16px;border-radius:100px;flex:none;}
.turntxt{font-size:24px;font-weight:650;}
/* 3 — config alerts */
.alertcard{background:rgba(255,107,74,.1);border:2px solid rgba(255,107,74,.3);border-radius:22px;padding:26px;will-change:opacity,transform;}
.alerttitle{font-size:25px;font-weight:700;line-height:1.36;}
.alerttitle b{color:${ORANGE};}
.alertlist{margin-top:22px;display:flex;flex-direction:column;gap:12px;}
.alertlist div{display:flex;align-items:center;gap:14px;font-size:21px;color:rgba(255,255,255,.55);font-weight:600;will-change:opacity,transform;}
.alertlist span{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.3);flex:none;}
/* 4 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:19px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${SAFE_GREEN};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span class="brand"><img src="${ICON}"><span>SAFE</span></span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">PENDING QUEUE</div>
    <div class="qcard">
      <div class="qtitle">2 of 3 signatures collected on a transfer to vitalik.eth</div>
      <div class="qbar"><div class="qfill" id="qfill"></div></div>
      <div class="qnums"><span><b id="qhave">0</b> collected</span><span>3 required</span></div>
    </div>
    <div class="cap">Read from Safe's own Transaction Service —<br><b>keyless, across six chains.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">/OWNERS/{EOA}/SAFES/</div>
    <div class="discrow" data-i="0"><span class="di" style="background:rgba(255,255,255,.08)"><svg width="26" height="26" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4" fill="none" stroke="rgba(255,255,255,.6)" stroke-width="2"/></svg></span><div><div class="dt">Safe you watch directly</div><div class="ds">Already known</div></div></div>
    <div class="discrow" data-i="1"><span class="di" style="background:${VIOLET}"><svg width="26" height="26" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="#fff" stroke-width="2"/><path d="M12 7v5l3.5 2" stroke="#fff" stroke-width="2" stroke-linecap="round"/></svg></span><div><div class="dt">Safe you're a signer on</div><div class="ds">Found automatically — you never added it</div></div></div>
    <div class="cap">Filtered to Safes that have<br><b>actually executed something — no decoys.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHOSE TURN</div>
    <div class="turnrow" data-i="0"><span class="turntag" style="background:rgba(255,159,10,.2);color:${AMBER}">YOU</span><span class="turntxt">— your signature is needed</span></div>
    <div class="turnrow" data-i="1"><span class="turntag" style="background:rgba(255,255,255,.08);color:rgba(255,255,255,.5)">OTHERS</span><span class="turntxt">— waiting on others</span></div>
    <div class="cap">Only sayable now that Casberi knows<br><b>exactly which owner you are.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">SETTINGS, WATCHED</div>
    <div class="alertcard">
      <div class="alerttitle">Your Safe <b>enabled a module that can move funds without a signature</b></div>
      <div class="alertlist">
        <div data-i="0"><span></span>New or removed owner</div>
        <div data-i="1"><span></span>Changed signature threshold</div>
        <div data-i="2"><span></span>Module enabled or removed</div>
      </div>
    </div>
    <div class="cap">Seeded silently on first sight —<br><b>fired only when something actually drifts.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never signs a transaction</div>
    <div class="vrow" data-i="1"><s>✕</s> Never needs a key</div>
    <div class="vrow" data-i="2"><s>✕</s> Never a separate connect step</div>
    <div class="vgood" id="vgood"><i>✓</i> Watching your wallet is all it takes.</div>
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
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(46,Math.min(280,860/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
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
    document.querySelector('#comp0 .qcard').style.opacity=clamp01((p-0.04)/0.24);
    const fp=clamp01((p-0.3)/0.4);
    document.getElementById('qfill').style.width=(fp*66.6)+'%';
    document.getElementById('qhave').textContent=Math.round(fp*2);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===1){
    stag('#comp1 .discrow',p,0.2,0.34,22);
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.26);
  } else if(i===2){
    stag('#comp2 .turnrow',p,0.22,0.34,20);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.28);
  } else if(i===3){
    const cp=clamp01((p-0.04)/0.24);
    const ac=document.querySelector('#comp3 .alertcard');
    ac.style.opacity=cp;ac.style.transform='scale('+(0.9+0.1*back(cp))+')';
    stag('#comp3 .alertlist div',clamp01((p-0.4)/0.5),0.14,0.28,14);
    if(cap)cap.style.opacity=clamp01((p-0.78)/0.2);
  } else if(i===4){
    stag('#comp4 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-safe-editorial.html'),html);
console.log('wrote clip-safe-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
