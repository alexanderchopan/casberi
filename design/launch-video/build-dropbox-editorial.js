// Dropbox promo — EDITORIAL, no app screenshots. Grounded in
// Model/DropboxBridge.swift + Screens/DropboxScreen.swift + the catalog offer
// (2026-07-27). Catalog tagline is literally "Your Dropbox, without the
// notifications", so the clip leads on that pain:
//   0 THE NOISE — a stranger shares a folder and your phone lights up. The
//     bridge's whole pitch: "A stranger sharing something with you can never
//     make it appear here, because nothing outside the folder you named is
//     ever read." Never shared links, never "shared with me".
//   1 NAME A FOLDER — the setup screen's folder field; empty means all of
//     Dropbox, otherwise exactly that path. "Changing it starts a fresh sync."
//   2 IT LANDS — files land as findable things; text formats get a real
//     preview (first 2KB via a Range request against the file's id), anything
//     else lands its size — the same bar as FilesIngest.
//   3 DELETES TOO — synced on Dropbox's OWN delta cursor (list_folder once,
//     then list_folder/continue forever), which is what turns a delete into
//     news for free instead of something a re-walk has to infer.
//   4 READ-ONLY — PKCE on-device (no server holds a secret), granted scopes
//     are files.metadata.read + files.content.read only: it cannot write.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-dropbox-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const DBX = '#0061FF', GREEN = '#3fb950', ORANGE = '#FF6B4A', AMBER = '#ff9f0a';
const BEATS = [
  { kick: 'THE NOISE',    head: 'Someone shared\na folder. Again.',   accent: ORANGE },
  { kick: 'NAME A FOLDER', head: 'Only the one\nyou name.',           accent: DBX },
  { kick: 'IT LANDS',     head: "What's inside\nbecomes findable.",   accent: DBX },
  { kick: 'DELETES TOO',  head: 'Gone there\nmeans gone here.',       accent: AMBER },
  { kick: 'READ-ONLY',    head: "It can't write\nto your Dropbox.",   accent: GREEN },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const SPAM = [
  'unknown@mailer.biz shared "INVOICE_2026.pdf"',
  'A folder was shared with you',
  'noreply@promos shared "Claim_Now.docx"',
];
const FILES = [
  { n: 'Q3-contract.pdf',   p: '412 KB',  text: false },
  { n: 'handover.md',       p: '## Handover\\nAccounts move Monday —', text: true },
  { n: 'invoice-0412.csv',  p: 'Date,Client,Total\\n07-24,Nari,1,240', text: true },
  { n: 'floorplan.png',     p: '2.1 MB',  text: false },
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:98px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — the noise */
.note{display:flex;align-items:center;gap:18px;background:rgba(255,255,255,.07);border-radius:20px;padding:20px 24px;margin-bottom:14px;will-change:opacity,transform;}
.note .bx{width:48px;height:48px;border-radius:13px;flex:none;background:${DBX};display:flex;align-items:center;justify-content:center;}
.note .tx{font-size:22px;font-weight:600;color:rgba(255,255,255,.72);line-height:1.35;}
.note .x{margin-left:auto;flex:none;color:${ORANGE};font-size:26px;font-weight:800;}
/* 1 — the folder field */
.fieldlbl{font-size:22px;color:rgba(255,255,255,.45);font-weight:650;margin-bottom:12px;}
.field{background:rgba(255,255,255,.07);border-radius:18px;padding:24px 28px;font-size:29px;font-weight:700;font-family:ui-monospace,monospace;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;align-items:center;}
.caret{width:3px;height:32px;background:#fff;margin-left:3px;display:inline-block;}
.nrow{display:flex;align-items:center;gap:20px;padding:18px 0;will-change:opacity,transform;}
.nrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:24px;text-decoration:none;font-weight:700;}
.nrow span{font-size:26px;font-weight:650;color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.24);}
/* 2 — files */
.lrow{display:flex;align-items:flex-start;gap:20px;padding:16px 0;will-change:opacity,transform;}
.lrow .ic{width:52px;height:64px;border-radius:9px;flex:none;background:rgba(255,255,255,.1);position:relative;overflow:hidden;}
.lrow .ic::after{content:'';position:absolute;top:0;right:0;border-width:0 17px 17px 0;border-style:solid;border-color:transparent #0d0a16 transparent transparent;}
.lrow .ext{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:13px;font-weight:800;letter-spacing:.04em;}
.lrow .n{font-size:25px;font-weight:700;word-break:break-all;}
.lrow .p{font-size:19px;color:rgba(255,255,255,.44);margin-top:5px;font-family:ui-monospace,monospace;line-height:1.4;white-space:pre-line;}
/* 3 — deltas */
.dline{display:flex;align-items:center;gap:18px;padding:18px 0;will-change:opacity,transform;}
.dline .tag{font-size:17px;font-weight:800;padding:7px 14px;border-radius:100px;flex:none;letter-spacing:.04em;}
.dline .nm{font-size:25px;font-weight:650;}
.dline.gone .nm{color:rgba(255,255,255,.45);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.28);}
.cursor{margin-top:22px;background:#000;border-radius:16px;padding:20px 24px;font-family:ui-monospace,monospace;font-size:19px;line-height:1.8;color:rgba(255,255,255,.55);box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);}
.cursor b{color:${GREEN};}
/* 4 — read only */
.scope{display:flex;align-items:center;gap:20px;padding:18px 0;font-size:26px;font-weight:650;will-change:opacity,transform;}
.scope i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
.scope code{font-family:ui-monospace,monospace;font-size:23px;color:rgba(255,255,255,.8);}
.cant{margin-top:24px;display:flex;align-items:center;gap:20px;font-size:27px;font-weight:700;color:${ORANGE};will-change:opacity,transform;}
.cant s{width:46px;height:46px;border-radius:50%;flex:none;background:rgba(255,107,74,.18);display:flex;align-items:center;justify-content:center;font-size:24px;text-decoration:none;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${DBX};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>DROPBOX</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">EVERY OTHER WEEK</div>
    ${SPAM.map((s,i)=>`<div class="note" data-i="${i}"><span class="bx"><svg width="26" height="26" viewBox="0 0 24 24"><path d="M6 3 1 6.5 6 10l5-3.5L6 3zm12 0-5 3.5L18 10l5-3.5L18 3zM1 13.5 6 17l5-3.5L6 10l-5 3.5zm17-3.5-5 3.5 5 3.5 5-3.5-5-3.5zM12 18l-5 3.5L12 25l5-3.5L12 18z" fill="#fff"/></svg></span><span class="tx">${s}</span><span class="x">✕</span></div>`).join('')}
    <div class="cap">Your Dropbox is useful.<br><b>The notifications aren't.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">SETUP · FOLDER</div>
    <div class="fieldlbl">Folder to follow</div>
    <div class="field"><span id="typed"></span><span class="caret" id="caret"></span></div>
    <div style="margin-top:26px">
      <div class="nrow" data-i="0"><s>✕</s><span>Shared links</span></div>
      <div class="nrow" data-i="1"><s>✕</s><span>"Shared with me"</span></div>
      <div class="nrow" data-i="2"><s>✕</s><span>Anything outside it</span></div>
    </div>
    <div class="cap">A stranger sharing a folder<br><b>can never put it in your feed.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">IN YOUR FEED</div>
    ${FILES.map((f,i)=>`<div class="lrow" data-i="${i}"><span class="ic"><span class="ext" style="color:${f.text?DBX:'rgba(255,255,255,.5)'}">${f.n.split('.').pop().toUpperCase()}</span></span><div style="flex:1;min-width:0"><div class="n">${f.n}</div><div class="p">${f.p}</div></div></div>`).join('')}
    <div class="cap">Words get read. The rest gets sized.<br><b>Findable next to everything else.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">DROPBOX'S OWN CHANGE FEED</div>
    <div class="dline" data-i="0"><span class="tag" style="background:rgba(63,185,80,.2);color:${GREEN}">NEW</span><span class="nm">Q3-contract.pdf</span></div>
    <div class="dline" data-i="1"><span class="tag" style="background:rgba(63,185,80,.2);color:${GREEN}">NEW</span><span class="nm">handover.md</span></div>
    <div class="dline gone" data-i="2"><span class="tag" style="background:rgba(255,107,74,.2);color:${ORANGE}">GONE</span><span class="nm">old-draft.docx</span></div>
    <div class="cursor" id="cursor">list_folder/continue → <b>3 changes</b></div>
    <div class="cap">It asks what changed, not what exists —<br><b>so a delete is news, not a guess.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">WHAT IT WAS GRANTED</div>
    <div class="scope" data-i="0"><i>✓</i><code>files.metadata.read</code></div>
    <div class="scope" data-i="1"><i>✓</i><code>files.content.read</code></div>
    <div class="cant" id="cant"><s>✕</s> Nothing that can write</div>
    <div class="cap">Sign-in happens on Dropbox's own page.<br><b>No password in the app, no server holds a secret.</b></div>
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
const PATH="/Work/Contracts";
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
    stag('#comp0 .note',p,0.17,0.3,-22);
    if(cap)cap.style.opacity=clamp01((p-0.6)/0.28);
  } else if(i===1){
    document.querySelector('#comp1 .fieldlbl').style.opacity=clamp01((p-0.02)/0.18);
    document.querySelector('#comp1 .field').style.opacity=clamp01((p-0.02)/0.18);
    const n=Math.round(clamp01((p-0.06)/0.3)*PATH.length);
    document.getElementById('typed').textContent=PATH.slice(0,n);
    document.getElementById('caret').style.opacity=(n<PATH.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    stag('#comp1 .nrow',clamp01((p-0.38)/0.62),0.14,0.3,18);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.24);
  } else if(i===2){
    stag('#comp2 .lrow',p,0.13,0.3,22);
    if(cap)cap.style.opacity=clamp01((p-0.64)/0.28);
  } else if(i===3){
    stag('#comp3 .dline',p,0.16,0.3,20);
    document.getElementById('cursor').style.opacity=clamp01((p-0.5)/0.24);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.26);
  } else if(i===4){
    stag('#comp4 .scope',p,0.15,0.3,18);
    const c=document.getElementById('cant');const cp=clamp01((p-0.4)/0.26);
    c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*16)+'px)';
    if(cap)cap.style.opacity=clamp01((p-0.62)/0.26);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-dropbox-editorial.html'),html);
console.log('wrote clip-dropbox-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
