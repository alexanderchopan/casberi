// Files promo — EDITORIAL, no app screenshots: warm paper ground, oversized
// type, monospace masthead, diagonal colour wipes, hand-drawn UI. Grounded
// line-by-line in Model/FilesBridge.swift + Screens/FilesScreen.swift + the
// catalog offer (Model/BridgeCatalog.swift, 2026-07-27):
//   0 PICK A FOLDER — the document picker; a security-scoped BOOKMARK
//     remembers it, so it survives relaunch. "Any folder, findable."
//   1 IT LANDS — the walk enumerates regular files (skipping hidden), sorts by
//     modification date and lands the NEWEST 100 per sync, "so a giant folder
//     arrives in waves instead of flooding the feed". Title = the filename.
//   2 WHAT IT READS — textExtensions (txt/md/csv/json/log/swift/…) land their
//     first 300 characters as the preview; everything else lands its SIZE,
//     "since a binary's bytes aren't a useful preview".
//   3 FINDABLE — landed things are SpotlightIndex.index'd, so they're findable
//     next to everything else in the corpus.
//   4 FULLY LOCAL — "no account, no key, no network, and the folder itself is
//     never modified (read-only enumeration)". Setup note verbatim:
//     "A folder on this iPhone · read-only, never modified".
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-files-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const BLUE = '#0A84FF', GREEN = '#3fb950', AMBER = '#ff9f0a';
const BEATS = [
  { kick: 'PICK A FOLDER', head: 'Point at any\nfolder you keep.',  accent: BLUE },
  { kick: 'IT LANDS',      head: "What's inside\nlands in your feed.", accent: BLUE },
  { kick: 'WHAT IT READS', head: 'Words get read.\nThe rest gets sized.', accent: AMBER },
  { kick: 'FINDABLE',      head: 'Beside everything\nelse you keep.', accent: GREEN },
  { kick: 'FULLY LOCAL',   head: 'Read in place.\nNever modified.',  accent: BLUE },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

// Folders offered by the picker — iCloud Drive is the headline case.
const FOLDERS = [
  { n: 'Receipts',   s: '128 items' },
  { n: 'Scans',      s: '46 items'  },
  { n: 'Downloads',  s: '312 items' },
];
// What lands: the title is the FILENAME, the content is the preview line.
const FILES = [
  { n: 'expenses-jul.csv',    p: 'Date,Merchant,Amount\\n07-24,Lisboa Café,4.80', text: true },
  { n: 'Receipt-Jul-24.pdf',  p: '248 KB',   text: false },
  { n: 'meeting-notes.md',    p: '## Ship the wallet merge\\nBlocked on decimals —', text: true },
  { n: 'scan-contract.jpg',   p: '1.8 MB',   text: false },
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
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:25px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:32px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — the picker */
.pick{background:rgba(255,255,255,.05);border-radius:24px;overflow:hidden;}
.pickbar{display:flex;align-items:center;gap:14px;padding:22px 26px;background:rgba(255,255,255,.06);}
.pickbar .cloud{width:34px;height:34px;flex:none;}
.pickbar .t{font-size:25px;font-weight:700;}
.frow{display:flex;align-items:center;gap:20px;padding:22px 26px;will-change:opacity,transform,background;}
.frow .fo{width:56px;height:46px;border-radius:11px;flex:none;background:${BLUE};position:relative;}
.frow .fo::before{content:'';position:absolute;top:-8px;left:6px;width:24px;height:10px;border-radius:5px 5px 0 0;background:${BLUE};}
.frow .n{font-size:28px;font-weight:650;}
.frow .s{font-size:20px;color:rgba(255,255,255,.4);margin-top:3px;}
.frow .chk{margin-left:auto;width:34px;height:34px;border-radius:50%;flex:none;background:rgba(255,255,255,.1);display:flex;align-items:center;justify-content:center;font-size:19px;font-weight:800;color:transparent;}
.frow.on .chk{background:${BLUE};color:#fff;}
.pickbtn{margin-top:22px;text-align:center;padding:22px;border-radius:100px;font-size:28px;font-weight:750;background:rgba(255,255,255,.12);color:rgba(255,255,255,.5);will-change:background,color;}
.pickbtn.armed{background:${BLUE};color:#fff;}
/* 1 / 2 — landed files */
.lrow{display:flex;align-items:flex-start;gap:20px;padding:18px 0;will-change:opacity,transform;}
.lrow .ic{width:54px;height:66px;border-radius:9px;flex:none;background:rgba(255,255,255,.1);position:relative;overflow:hidden;}
.lrow .ic::after{content:'';position:absolute;top:0;right:0;border-width:0 18px 18px 0;border-style:solid;border-color:transparent #0d0a16 transparent transparent;}
.lrow .ext{position:absolute;bottom:7px;left:0;right:0;text-align:center;font-size:14px;font-weight:800;letter-spacing:.04em;}
.lrow .n{font-size:26px;font-weight:700;word-break:break-all;}
.lrow .p{font-size:20px;color:rgba(255,255,255,.44);margin-top:5px;font-family:ui-monospace,monospace;line-height:1.4;white-space:pre-line;}
.lrow .sz{font-size:20px;color:rgba(255,255,255,.44);margin-top:5px;font-weight:600;}
.tag{margin-left:auto;flex:none;font-size:17px;font-weight:750;padding:7px 14px;border-radius:100px;}
/* 3 — findable beside everything */
.srch{display:flex;align-items:center;gap:16px;background:rgba(255,255,255,.09);border-radius:100px;padding:20px 26px;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);margin-bottom:26px;}
.srch .q{font-size:26px;font-weight:650;}
.mrow{display:flex;align-items:center;gap:18px;padding:17px 0;will-change:opacity,transform;}
.mrow .dot{width:44px;height:44px;border-radius:13px;flex:none;}
.mrow .n{font-size:25px;font-weight:650;}
.mrow .src{margin-left:auto;font-size:19px;color:rgba(255,255,255,.34);font-weight:600;}
/* 4 — local */
.vrow{display:flex;align-items:center;gap:22px;padding:18px 0;font-size:29px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:50px;height:50px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:#FF6B4A;display:flex;align-items:center;justify-content:center;font-size:25px;text-decoration:none;font-weight:700;}
.vrow span{color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.25);}
.vgood{display:flex;align-items:center;gap:20px;margin-top:26px;font-size:28px;font-weight:700;color:${GREEN};will-change:opacity,transform;line-height:1.3;}
.vgood i{width:50px;height:50px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:26px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>FILES</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">CHOOSE A FOLDER</div>
    <div class="pick">
      <div class="pickbar"><span class="cloud"><svg viewBox="0 0 24 24" width="34" height="34"><path d="M6.5 19a4.5 4.5 0 0 1-.4-9 6 6 0 0 1 11.6-1.2A4 4 0 0 1 18 19z" fill="${BLUE}"/></svg></span><span class="t">iCloud Drive</span></div>
      ${FOLDERS.map((f,i)=>`<div class="frow" id="fr${i}" data-i="${i}"><span class="fo"></span><div><div class="n">${f.n}</div><div class="s">${f.s}</div></div><span class="chk">✓</span></div>`).join('')}
    </div>
    <div class="pickbtn" id="pickbtn">Choose this folder</div>
    <div class="cap">Any folder — not just notes.<br><b>It's remembered from then on.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">READING YOUR FILES…</div>
    ${FILES.map((f,i)=>`<div class="lrow" data-i="${i}"><span class="ic"><span class="ext" style="color:${f.text?BLUE:'rgba(255,255,255,.5)'}">${f.n.split('.').pop().toUpperCase()}</span></span><div><div class="n">${f.n}</div><div class="sz">${f.text?'read as words':f.p}</div></div></div>`).join('')}
    <div class="cap"><b>Newest first</b>, a hundred at a time —<br>so a big folder arrives in waves.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">THE PREVIEW LINE</div>
    ${FILES.map((f,i)=>`<div class="lrow" data-i="${i}"><span class="ic"><span class="ext" style="color:${f.text?BLUE:'rgba(255,255,255,.5)'}">${f.n.split('.').pop().toUpperCase()}</span></span><div style="flex:1;min-width:0"><div class="n">${f.n}</div><div class="p">${f.p}</div></div><span class="tag" style="background:${f.text?'rgba(10,132,255,.2)':'rgba(255,159,10,.2)'};color:${f.text?BLUE:AMBER}">${f.text?'first 300':'size'}</span></div>`).join('')}
    <div class="cap">A binary's bytes aren't a preview —<br><b>so it says the size instead.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">SEARCH · SPOTLIGHT TOO</div>
    <div class="srch"><svg viewBox="0 0 24 24" width="28" height="28"><circle cx="11" cy="11" r="7" fill="none" stroke="rgba(255,255,255,.6)" stroke-width="2.4"/><path d="M16.5 16.5 21 21" stroke="rgba(255,255,255,.6)" stroke-width="2.4" stroke-linecap="round"/></svg><span class="q">lisbon</span></div>
    <div class="mrow" data-i="0"><span class="dot" style="background:${BLUE}"></span><span class="n">expenses-jul.csv</span><span class="src">Files</span></div>
    <div class="mrow" data-i="1"><span class="dot" style="background:#ff453a"></span><span class="n">Flight to Lisbon · 4:26PM</span><span class="src">Calendar</span></div>
    <div class="mrow" data-i="2"><span class="dot" style="background:#855dcd"></span><span class="n">Best pastéis de nata in Lisbon</span><span class="src">Farcaster</span></div>
    <div class="mrow" data-i="3"><span class="dot" style="background:#0a84ff"></span><span class="n">Trip plan: Lisbon</span><span class="src">Notes</span></div>
    <div class="cap">Your folder stops being<br><b>a place you have to remember.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s><span>Move or rename a file</span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Upload anything</span></div>
    <div class="vrow" data-i="2"><s>✕</s><span>Ask for an account</span></div>
    <div class="vgood" id="vgood"><i>✓</i> A folder on this iPhone —<br>read-only, never modified.</div>
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
    document.querySelector('#comp0 .pick').style.opacity=clamp01((p-0.02)/0.2);
    stag('#comp0 .frow',clamp01((p-0.06)/0.94),0.11,0.26,16);
    // the middle folder gets picked, then the button arms
    const sel=clamp01((p-0.44)/0.12)>0.5;
    document.getElementById('fr1').classList.toggle('on',sel);
    document.getElementById('fr1').style.background=sel?'rgba(10,132,255,.14)':'transparent';
    document.getElementById('pickbtn').classList.toggle('armed',clamp01((p-0.56)/0.12)>0.5);
    if(cap)cap.style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===1){
    stag('#comp1 .lrow',p,0.14,0.3,26);
    if(cap)cap.style.opacity=clamp01((p-0.62)/0.28);
  } else if(i===2){
    stag('#comp2 .lrow',p,0.14,0.3,22);
    if(cap)cap.style.opacity=clamp01((p-0.64)/0.28);
  } else if(i===3){
    document.querySelector('#comp3 .srch').style.opacity=clamp01((p-0.02)/0.18);
    stag('#comp3 .mrow',clamp01((p-0.12)/0.88),0.13,0.3,20);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.26);
  } else if(i===4){
    stag('#comp4 .vrow',p,0.13,0.3,20);
    const vg=document.getElementById('vgood');const vp=clamp01((p-0.5)/0.28);
    vg.style.opacity=vp;vg.style.transform='translateY('+((1-back(vp))*18)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-files-editorial.html'),html);
console.log('wrote clip-files-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
