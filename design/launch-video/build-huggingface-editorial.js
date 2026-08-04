// Hugging Face promo — CONSUMER cut. Grounded line-by-line in
// Model/HuggingFaceBridge.swift + BridgeCatalog's offer (2026-08-03):
//   0 — the watch: name an org or a person (meta-llama, google, karpathy —
//     the file's own examples) and their NEW models, datasets and Spaces
//     land as links. Row nouns are the shipped strings: "new model" /
//     "new dataset" / "new Space".
//   1 — Daily Papers: HF's own curated list lands with a real title and the
//     FULL abstract, so you can search what a paper was about months later.
//   2 — the filter, which is the design: HF is a firehose of counts, and a
//     count is never a thing (the PostHog lesson). Downloads, likes,
//     trending — none of it lands. Only "it did not exist, and now it
//     does" (createdAt, never lastModified).
//   3 — keyless: no account, no key, nothing to mint; read-only — never
//     publishes, stars, or downloads weights (offer copy).
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-huggingface-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const HF = '#FFD21E', INK = '#14110d', GREEN = '#3fb950', ORANGE = '#FF6B4A', BLUE = '#2E63FF';
const BEATS = [
  { kick: 'THE WATCH',    head: 'Name a lab.\nSee what ships.',            accent: INK,   tag: 'NEW' },
  { kick: 'DAILY PAPERS', head: "Today's research,\nsearchable forever.",  accent: INK,   tag: null },
  { kick: 'THE FILTER',   head: "Counts aren't news.\nNew things are.",    accent: ORANGE, tag: null },
  { kick: 'KEYLESS',      head: 'No account.\nNo key.',                    accent: GREEN, tag: null },
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0d09;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}

/* 0 — the watch rows */
.hfrow{display:flex;align-items:center;gap:20px;padding:17px 0;will-change:opacity,transform;}
.hficon{width:56px;height:56px;border-radius:14px;flex:none;background:${HF};display:flex;align-items:center;justify-content:center;font-size:30px;}
.hfname{font-size:24px;font-weight:700;font-family:ui-monospace,monospace;}
.hfnoun{font-size:20px;color:rgba(255,255,255,.45);margin-top:3px;}
.watchnote{margin-top:26px;text-align:center;font-size:22px;font-weight:700;color:rgba(255,255,255,.7);line-height:1.4;will-change:opacity;}
.watchnote em{font-style:normal;color:${HF};}

/* 1 — a paper with a face */
.paper{background:rgba(255,255,255,.07);border-radius:20px;padding:28px;will-change:opacity,transform;}
.pcover{height:120px;border-radius:14px;background:linear-gradient(120deg,#3b2f63,#7a5cc4 55%,#ffb26b);margin-bottom:20px;}
.ptitle{font-size:26px;font-weight:750;line-height:1.3;}
.pabs{margin-top:12px;font-size:21px;color:rgba(255,255,255,.55);line-height:1.5;}
.papernote{margin-top:24px;text-align:center;font-size:22px;font-weight:700;color:rgba(255,255,255,.7);line-height:1.45;will-change:opacity;}
.papernote em{font-style:normal;color:${HF};}

/* 2 — counts aren't news */
.cnt{display:flex;align-items:center;justify-content:space-between;padding:19px 8px;border-bottom:1px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.cnt .l{font-size:25px;font-weight:650;color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:${ORANGE};text-decoration-thickness:3px;}
.cnt .r{font-size:20px;font-weight:700;color:${ORANGE};letter-spacing:.06em;}
.newrow{display:flex;align-items:center;justify-content:space-between;padding:22px 8px;will-change:opacity,transform;}
.newrow .l{font-size:25px;font-weight:750;color:#fff;}
.newrow .r{font-size:20px;font-weight:800;color:${GREEN};letter-spacing:.06em;}
.filternote{margin-top:22px;text-align:center;font-size:21px;font-weight:640;color:rgba(255,255,255,.42);line-height:1.45;will-change:opacity;}

/* 3 — keyless */
.bigno{text-align:center;font-size:120px;font-weight:800;letter-spacing:-.04em;color:${GREEN};will-change:opacity,transform;}
.bignosub{margin-top:8px;text-align:center;font-size:27px;font-weight:700;color:#fff;will-change:opacity;}
.keynote{margin-top:34px;text-align:center;font-size:22px;font-weight:640;color:rgba(255,255,255,.5);line-height:1.5;will-change:opacity;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:#14110d;background:${HF};padding:2px 10px;border-radius:6px;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>HUGGING FACE</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">WATCH ANY ORG OR PERSON</div>
    <div class="hfrow" data-i="0"><span class="hficon">🤗</span><div><div class="hfname">meta-llama/Llama-4-Scout</div><div class="hfnoun">new model · today</div></div></div>
    <div class="hfrow" data-i="1"><span class="hficon">🤗</span><div><div class="hfname">google/gemma-3-27b-it</div><div class="hfnoun">new model · today</div></div></div>
    <div class="hfrow" data-i="2"><span class="hficon">🤗</span><div><div class="hfname">karpathy/nanochat-demo</div><div class="hfnoun">new Space · yesterday</div></div></div>
    <div class="watchnote" id="watchnote">Their new models, datasets and Spaces —<br><em>in your feed, with everything else.</em></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">HUGGING FACE'S OWN DAILY PICK</div>
    <div class="paper" id="paper">
      <div class="pcover"></div>
      <div class="ptitle">Scaling Laws for Sparse Mixture-of-Experts</div>
      <div class="pabs">We study how sparse expert models scale with compute and data, and find that…</div>
    </div>
    <div class="papernote" id="papernote">Every paper lands with its full abstract —<br><em>ask about it months later.</em></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHAT NEVER LANDS</div>
    <div class="cnt" data-i="0"><span class="l">1.4M downloads</span><span class="r">A COUNT</span></div>
    <div class="cnt" data-i="1"><span class="l">62k likes</span><span class="r">A COUNT</span></div>
    <div class="cnt" data-i="2"><span class="l">Trending #1</span><span class="r">A COUNT</span></div>
    <div class="newrow" id="newrow"><span class="l">Didn't exist yesterday. Does now.</span><span class="r">LANDS</span></div>
    <div class="filternote" id="filternote">A model updated for a README typo isn't news either — only genuinely new things land.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">NOTHING TO MINT, NOTHING TO LEAK</div>
    <div class="bigno" id="bigno">$0</div>
    <div class="bignosub" id="bignosub">No account. No key. No sign-up.</div>
    <div class="keynote" id="keynote">Fetched straight from the public hub by your device.<br>Read-only — it never publishes, stars, or downloads weights.</div>
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
    tag.style.background='${HF}';tag.style.color='#14110d';
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
    stag('#comp0 .hfrow',p,0.16,0.28,20);
    document.getElementById('watchnote').style.opacity=clamp01((p-0.62)/0.26);
  } else if(i===1){
    pop(document.getElementById('paper'),p,0.04,0.3,22);
    document.getElementById('papernote').style.opacity=clamp01((p-0.52)/0.28);
  } else if(i===2){
    stag('#comp2 .cnt',p,0.13,0.24,16);
    pop(document.getElementById('newrow'),p,0.5,0.26,20);
    document.getElementById('filternote').style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===3){
    pop(document.getElementById('bigno'),p,0.04,0.3,26);
    document.getElementById('bignosub').style.opacity=clamp01((p-0.34)/0.24);
    document.getElementById('keynote').style.opacity=clamp01((p-0.56)/0.26);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-huggingface-editorial.html'),html);
console.log('wrote clip-huggingface-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
