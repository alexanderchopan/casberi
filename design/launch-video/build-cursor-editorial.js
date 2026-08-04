// Cursor promo — CONSUMER cut, written to match the launch tweet:
//   "The cloud agents you launch land in your feed once they're done — the
//    repo they ran on, what the agent says it changed, and the PR it opened.
//    A run that failed says so.  It only ever lists your agents. It never
//    starts one."
// Grounded line-by-line in Model/CursorBridge.swift + the catalog offer:
//   0 — ONCE THEY'RE DONE. Only a TERMINAL run lands; CREATING/RUNNING are
//     states (§216) and never become things. The in-flight row is drawn
//     greyed and explicitly does not land.
//   1 — WHAT IT CHANGED. The title is "org/repo · agent name" (repo LEADS —
//     an agent name alone is a fragment), and `summary` is display copy:
//     what the agent says it did.
//   2 — THE PR, AND A FAILURE THAT SAYS SO. The PR is the permalink when
//     there is one; an abnormal run wears its outcome in FRONT ("Failed ·
//     org/repo · …") because titleLine clamps at 80 and a trailing outcome
//     is exactly what the clamp eats.
//   3 — LISTS, NEVER STARTS. Read-only by conduct: one GET against one path.
//     The four verbs it does not use are named.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-cursor-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const INK = '#14110d', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF', GREY = '#8a8a8a';
const BEATS = [
  { kick: 'WHEN IT’S DONE', head: 'Your agent finishes.\nIt lands.',        accent: BLUE,  tag: 'NEW' },
  { kick: 'WHAT IT DID',    head: 'The repo, and what\nit says it changed.', accent: INK,  tag: null },
  { kick: 'THE PR',         head: 'With the pull request.\nOr why it failed.', accent: INK, tag: null },
  { kick: 'READ-ONLY',      head: 'It lists your agents.\nIt never starts one.', accent: GREEN, tag: null },
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
.head{position:absolute;left:70px;top:288px;right:70px;font-size:88px;line-height:1.0;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0d09;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}

/* 0 — running never lands; finished does */
.state{display:flex;align-items:center;gap:22px;padding:26px 28px;border-radius:22px;background:rgba(255,255,255,.05);margin-bottom:20px;will-change:opacity,transform;}
.spin{width:26px;height:26px;border-radius:50%;border:4px solid rgba(255,255,255,.16);border-top-color:rgba(255,255,255,.5);flex:none;will-change:transform;}
.tick{width:30px;height:30px;border-radius:50%;background:rgba(63,185,80,.2);color:${GREEN};display:flex;align-items:center;justify-content:center;font-size:19px;font-weight:800;flex:none;}
.stt{font-size:27px;font-weight:700;} .sts{font-size:21px;color:rgba(255,255,255,.42);margin-top:4px;}
.state.ghosted .stt,.state.ghosted .sts{color:rgba(255,255,255,.3);}
.verdict{margin-left:auto;font-size:19px;font-weight:800;letter-spacing:.06em;flex:none;}
.landnote{margin-top:28px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.landnote em{font-style:normal;color:#fff;font-weight:750;}

/* 1 — the row, as it lands */
.card{background:rgba(255,255,255,.06);border-radius:26px;padding:32px;will-change:opacity,transform;}
.crepo{font-size:30px;font-weight:800;font-family:ui-monospace,monospace;letter-spacing:-.01em;}
.cname{font-size:30px;font-weight:650;color:rgba(255,255,255,.72);}
.csum{margin-top:22px;font-size:24px;line-height:1.5;color:rgba(255,255,255,.62);}
.ctag{display:inline-block;margin-top:24px;font-size:19px;font-weight:750;padding:9px 18px;border-radius:100px;background:rgba(46,99,255,.16);color:#7aa2f7;}
.sumnote{margin-top:26px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);will-change:opacity;}

/* 2 — the PR, and the failure */
.pr{display:flex;align-items:center;gap:20px;padding:24px 26px;border-radius:20px;background:rgba(63,185,80,.1);will-change:opacity,transform;}
.prg{width:44px;height:44px;border-radius:50%;background:rgba(63,185,80,.2);color:${GREEN};display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:800;flex:none;}
.prt{font-size:24px;font-weight:700;} .prs{font-size:19px;color:rgba(255,255,255,.45);margin-top:3px;font-family:ui-monospace,monospace;}
.fail{display:flex;align-items:center;gap:20px;padding:24px 26px;border-radius:20px;background:rgba(255,69,58,.1);margin-top:18px;will-change:opacity,transform;}
.failpill{font-size:19px;font-weight:800;padding:9px 16px;border-radius:10px;background:rgba(255,69,58,.2);color:${RED};flex:none;}
.failt{font-size:24px;font-weight:700;} .fails{font-size:19px;color:rgba(255,255,255,.45);margin-top:3px;}
.prnote{margin-top:26px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.prnote em{font-style:normal;color:${RED};font-weight:750;}

/* 3 — one verb, four it never uses */
.verb{display:flex;align-items:center;justify-content:space-between;padding:20px 8px;border-bottom:1px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.verb .l{font-size:26px;font-weight:750;font-family:ui-monospace,monospace;}
.verb .r{font-size:19px;font-weight:800;letter-spacing:.06em;}
.verb.no .l{color:rgba(255,255,255,.45);text-decoration:line-through;text-decoration-color:${RED};text-decoration-thickness:3px;}
.verb.no .r{color:rgba(255,255,255,.32);}
.verb.yes .r{color:${GREEN};}
.keynote{margin-top:30px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.55);line-height:1.5;will-change:opacity;}
.keynote em{font-style:normal;color:#fff;font-weight:750;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:#fff;background:${INK};padding:2px 10px;border-radius:6px;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>CURSOR</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">YOUR CLOUD AGENTS</div>
    <div class="state ghosted" id="st0"><span class="spin" id="spin"></span><div><div class="stt">Running · fix the flaky test</div><div class="sts">Still going in Cursor</div></div><span class="verdict" id="v0" style="color:rgba(255,255,255,.3)">NOT YET</span></div>
    <div class="state" id="st1"><span class="tick">✓</span><div><div class="stt">Finished · add README docs</div><div class="sts">Done 2 minutes ago</div></div><span class="verdict" id="v1" style="color:${GREEN}">LANDS</span></div>
    <div class="landnote" id="landnote">A run in flight is already on screen in Cursor.<br><em>Only a finished one becomes a thing.</em></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">HOW IT LANDS IN YOUR FEED</div>
    <div class="card" id="card">
      <div><span class="crepo">casberi/casberi</span> <span class="cname">· Add README documentation</span></div>
      <div class="csum" id="csum">“Added a README covering setup, the build script and the three ship gates. Split the install steps out of the contributing guide.”</div>
      <span class="ctag">Agent run</span>
    </div>
    <div class="sumnote" id="sumnote">The repo it ran on, and what the agent says it changed.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHERE IT TAKES YOU</div>
    <div class="pr" id="pr"><span class="prg">↗</span><div><div class="prt">Opens the pull request</div><div class="prs">github.com/casberi/casberi/pull/418</div></div></div>
    <div class="fail" id="fail"><span class="failpill">Failed</span><div><div class="failt">casberi/casberi · migrate the token vault</div><div class="fails">No PR — opens the run, where the error is</div></div></div>
    <div class="prnote" id="prnote">The outcome leads the title, so it can never be cut —<br><em>a failed run says so.</em></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">WHAT THE KEY IS USED FOR</div>
    <div class="verb yes" data-v="0"><span class="l">GET /v0/agents</span><span class="r">THE ONLY ONE</span></div>
    <div class="verb no" data-v="1"><span class="l">POST an agent</span><span class="r">NEVER</span></div>
    <div class="verb no" data-v="2"><span class="l">POST a follow-up</span><span class="r">NEVER</span></div>
    <div class="verb no" data-v="3"><span class="l">DELETE an agent</span><span class="r">NEVER</span></div>
    <div class="keynote" id="keynote">Cursor keys carry no scopes, so the promise is kept by conduct:<br><em>one request, one path, read-only.</em></div>
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
function pop(el,p,from,dur,dy){const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy||22))+'px)';return rp;}
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
  if(TAGS[active]){tag.textContent=TAGS[active];tag.style.background='${BLUE}';tag.style.color='#fff';tag.style.opacity=easeOut(kin);tag.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';}
  else{tag.style.opacity=0;}
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  if(i===0){
    pop(document.getElementById('st0'),p,0.02,0.26,20);
    document.getElementById('spin').style.transform='rotate('+(t*300)+'deg)';
    pop(document.getElementById('st1'),p,0.3,0.28,22);
    document.getElementById('landnote').style.opacity=clamp01((p-0.6)/0.26);
  } else if(i===1){
    pop(document.getElementById('card'),p,0.03,0.3,24);
    document.getElementById('csum').style.opacity=clamp01((p-0.34)/0.26);
    document.getElementById('sumnote').style.opacity=clamp01((p-0.66)/0.24);
  } else if(i===2){
    pop(document.getElementById('pr'),p,0.03,0.28,20);
    pop(document.getElementById('fail'),p,0.34,0.28,20);
    document.getElementById('prnote').style.opacity=clamp01((p-0.68)/0.24);
  } else if(i===3){
    stag('#comp3 .verb',p,0.13,0.24,18);
    document.getElementById('keynote').style.opacity=clamp01((p-0.62)/0.24);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-cursor-editorial.html'),html);
console.log('wrote clip-cursor-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
