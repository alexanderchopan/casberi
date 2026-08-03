// Railgun promo — CONSUMER cut. Grounded line-by-line in
// Model/RailgunBridge.swift + its catalog offer (2026-08-01, prd §252):
//   0 — what Railgun is: a shielded pool. Two public doors only — shield in,
//     unshield out. Everything between is encrypted, by design.
//   1 — the differentiated read: an unshield can be YOU withdrawing, or
//     someone paying you privately — the chain can't tell them apart, and
//     that's the product working. Title is verbatim line 401: "Received
//     500 USDC from Railgun." enrichedText verbatim line 419.
//   2 — the honesty wall: nothing inside the pool is ever read. No private
//     balance, no viewing key, no trial-decryption. That's not a missing
//     feature — it's the one thing this bridge refuses to build.
//   3 — read-only, rides watched wallets, no account, no key.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-railgun-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const RG = '#00D18F', INK = '#14110d', VIOLET = '#7C5CFC', GREEN = '#3fb950';
const BEATS = [
  { kick: 'NEW',           head: 'Money can find you\nprivately now.',   accent: RG,     tag: 'NEW' },
  { kick: 'THE ONE ROW',   head: "Even we don't\nknow who sent it.",     accent: VIOLET, tag: null },
  { kick: 'THE LINE WE WON’T CROSS', head: 'Inside the pool,\nwe see nothing.', accent: INK, tag: null },
  { kick: 'READ-ONLY',     head: 'Watching is\nall it takes.',           accent: GREEN,  tag: null },
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#080e0c;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}

/* 0 — the two doors, and the encrypted middle */
.doorway{display:flex;align-items:center;justify-content:center;gap:20px;}
.door{width:150px;height:150px;border-radius:28px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;will-change:opacity,transform;}
.door .n{font-size:22px;font-weight:800;}
.door .s{font-size:15px;font-weight:620;opacity:.6;}
.pool{width:180px;height:150px;border-radius:28px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;background:rgba(255,255,255,.04);border:2px dashed rgba(255,255,255,.14);will-change:opacity,transform;}
.pool .n{font-size:34px;}
.pool .s{font-size:14px;font-weight:700;letter-spacing:.06em;color:rgba(255,255,255,.4);text-transform:uppercase;}
.doornote{margin-top:34px;text-align:center;font-size:24px;font-weight:680;color:rgba(255,255,255,.6);line-height:1.4;will-change:opacity;}
.doornote em{font-style:normal;color:${RG};}

/* 1 — the received row + the honest badge */
.rowcard{background:rgba(255,255,255,.07);border-radius:20px;padding:26px 28px;will-change:opacity,transform;}
.rowcard .t{font-size:27px;font-weight:750;line-height:1.35;}
.badgecard{margin-top:18px;background:rgba(124,92,252,.12);border:2px solid rgba(124,92,252,.35);border-radius:18px;padding:22px 24px;will-change:opacity,transform;}
.badgecard .t{font-size:21px;font-weight:620;line-height:1.5;color:rgba(255,255,255,.85);}
.badgecard .t b{color:${VIOLET};}
.eithernote{margin-top:26px;text-align:center;font-size:22px;font-weight:700;color:rgba(255,255,255,.55);will-change:opacity;}
.eithernote b{color:#fff;}

/* 2 — what stays invisible */
.nope{display:flex;align-items:center;gap:18px;padding:16px 0;font-size:25px;font-weight:650;will-change:opacity,transform;}
.nope s{width:44px;height:44px;border-radius:50%;flex:none;background:rgba(255,255,255,.08);color:rgba(255,255,255,.45);display:flex;align-items:center;justify-content:center;font-size:22px;text-decoration:none;font-weight:700;}
.whynote{margin-top:26px;text-align:center;font-size:22px;font-weight:700;color:${RG};line-height:1.4;will-change:opacity;}

/* 3 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:17px 0;font-size:26px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:46px;height:46px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:#FF6B4A;display:flex;align-items:center;justify-content:center;font-size:22px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:25px;font-weight:700;color:${GREEN};line-height:1.35;will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${RG};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>RAILGUN</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">A SHIELDED POOL, TWO PUBLIC DOORS</div>
    <div class="doorway">
      <span class="door" id="d1" style="background:rgba(0,209,143,.15);color:${RG}"><span class="n">SHIELD</span><span class="s">tokens in</span></span>
      <span class="pool" id="dp"><span class="n">🔒</span><span class="s">encrypted</span></span>
      <span class="door" id="d2" style="background:rgba(124,92,252,.15);color:${VIOLET}"><span class="n">UNSHIELD</span><span class="s">back out</span></span>
    </div>
    <div class="doornote" id="doornote">Everything between the two doors<br>is <em>readable by no one but you</em>.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">SOMEONE CAN PAY YOU PRIVATELY</div>
    <div class="rowcard" id="rowcard">
      <div class="t">Received 500 USDC from Railgun</div>
    </div>
    <div class="badgecard" id="badgecard">
      <div class="t">Railgun can't tell you who sent this — inside the pool the sender is private <b>by design</b>. If you unshielded this yourself, that's you.</div>
    </div>
    <div class="eithernote" id="eithernote">You, or a payment. <b>The chain can't tell them apart</b> — and that's the product working.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHAT NEVER GETS READ</div>
    <div class="nope" data-i="0"><s>✕</s> Your private balance</div>
    <div class="nope" data-i="1"><s>✕</s> Transfers inside the pool</div>
    <div class="nope" data-i="2"><s>✕</s> A viewing key, anywhere near this app</div>
    <div class="whynote" id="whynote">Not a missing feature.<br>The whole point.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">TWO PUBLIC DOORS, NOTHING ELSE</div>
    <div class="vrow" data-i="0"><s>✕</s> Never shields or unshields</div>
    <div class="vrow" data-i="1"><s>✕</s> Never proves or signs</div>
    <div class="vrow" data-i="2"><s>✕</s> No account, no key</div>
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
    tag.style.background='${RG}';tag.style.color='#04140a';
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
    pop(document.getElementById('d1'),p,0.02,0.24,18);
    pop(document.getElementById('dp'),p,0.26,0.24,18);
    pop(document.getElementById('d2'),p,0.5,0.24,18);
    document.getElementById('doornote').style.opacity=clamp01((p-0.68)/0.24);
  } else if(i===1){
    pop(document.getElementById('rowcard'),p,0.03,0.26,20);
    pop(document.getElementById('badgecard'),p,0.32,0.28,20);
    document.getElementById('eithernote').style.opacity=clamp01((p-0.68)/0.24);
  } else if(i===2){
    stag('#comp2 .nope',p,0.2,0.28,20);
    document.getElementById('whynote').style.opacity=clamp01((p-0.62)/0.26);
  } else if(i===3){
    stag('#comp3 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.58)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-railgun-editorial.html'),html);
console.log('wrote clip-railgun-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
