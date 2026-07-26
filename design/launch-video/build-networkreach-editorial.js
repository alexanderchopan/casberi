// "What this app reaches" promo — EDITORIAL, no app screenshots. Grounded
// directly in source, not invented (prd §180, shipped this session):
//   1. Model/NetworkReach.swift + Screens/NetworkReachScreen.swift — a
//      settings screen (Settings → Network) grouping every host the app
//      calls into "Reaching now" / "Only when you tap" / "Only if you
//      connect them", each with a plain-English purpose sentence.
//   2. Screens/AccountDetailSheet.swift — an Advanced Data Protection nudge
//      shown under the iCloud Sync toggle (only while sync is on): "turn on
//      Advanced Data Protection... then only your devices can read it —
//      not even Apple."
//   3. scripts/network-reach-audit.sh (wired into verify.sh) — greps every
//      https:// host literal in the app and fails the BUILD if one isn't in
//      the registry or the explicit non-reach denylist. Complete by
//      construction, not just documented.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-networkreach-editorial.html --size=1080x1920
const fs = require('fs');

const BLUE = '#2E63FF', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'FULL DISCLOSURE', head: 'See exactly\nwhat we reach.',      accent: BLUE },
  { kick: 'YOUR ICLOUD COPY', head: 'Turn on Advanced\nData Protection.', accent: GREEN },
  { kick: 'PROVABLE, NOT PROMISED', head: 'Every host\nmust be listed.', accent: ORANGE },
];
const INTRO = 0.45, BEAT = 2.7, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const NOW_ROWS = [
  { name: 'Wallet', purpose: 'Balances & activity you watch', host: 'api.g.alchemy.com' },
  { name: 'Farcaster', purpose: 'Casts from accounts you follow', host: 'api.farcaster.xyz' },
];
const LATER_ROWS = [
  { name: 'GitHub', host: 'api.github.com' },
  { name: 'Spotify', host: 'api.spotify.com' },
];
const AUDIT_LINES = [
  { host: 'api.g.alchemy.com', ok: true },
  { host: 'api.farcaster.xyz', ok: true },
  { host: 'public.api.bsky.app', ok: true },
  { host: 'api.anthropic.com', ok: true },
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;}
.shd{font-size:26px;letter-spacing:.12em;color:rgba(255,255,255,.5);margin-bottom:28px;}
/* beat 0 — network reach list */
.netgroup{font-size:22px;letter-spacing:.1em;color:rgba(255,255,255,.35);font-weight:650;margin:22px 0 14px;}
.netgroup:first-of-type{margin-top:0;}
.netrow{display:flex;align-items:center;gap:20px;padding:16px 0;will-change:opacity,transform;}
.neticon{width:52px;height:52px;border-radius:15px;background:rgba(255,255,255,.1);flex:none;}
.netname{font-size:28px;font-weight:700;}
.netpurpose{font-size:21px;color:rgba(255,255,255,.45);margin-top:2px;}
.nethost{font-size:19px;color:rgba(255,255,255,.3);margin-top:2px;font-family:ui-monospace,monospace;}
.netrow.dim{opacity:.4;}
/* beat 1 — ADP nudge */
.togglecard{background:rgba(255,255,255,.05);border-radius:22px;padding:30px;}
.togglehead{display:flex;align-items:center;justify-content:space-between;}
.togglelbl2{font-size:30px;font-weight:700;}
.toggle{width:88px;height:48px;border-radius:100px;background:rgba(255,255,255,.14);position:relative;}
.toggleknob{position:absolute;top:5px;width:38px;height:38px;border-radius:50%;background:#fff;will-change:left,background;}
.nudgetext{margin-top:26px;font-size:24px;line-height:1.5;color:rgba(255,255,255,.55);will-change:opacity;}
.nudgetext b{color:#fff;}
.lockwrap{display:flex;justify-content:center;margin:40px 0 10px;}
.lock{width:130px;height:130px;border-radius:50%;background:rgba(255,255,255,.06);display:flex;align-items:center;justify-content:center;will-change:background;}
/* beat 2 — build audit */
.term{background:#000;border-radius:20px;padding:30px;font-family:ui-monospace,monospace;font-size:22px;line-height:1.9;box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);}
.termline{opacity:0;will-change:opacity,transform;color:rgba(255,255,255,.7);}
.termline .h{color:rgba(255,255,255,.9);}
.termline .ok{color:${GREEN};font-weight:700;}
.termstamp{margin-top:26px;text-align:center;font-size:30px;font-weight:800;color:${GREEN};opacity:0;will-change:opacity,transform;}
.label-caption{margin-top:36px;font-size:28px;font-weight:650;color:rgba(255,255,255,.8);text-align:center;}
.label-caption b{color:#fff;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>PRIVACY</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">SETTINGS → NETWORK</div>
    <div class="netgroup">REACHING NOW</div>
    ${NOW_ROWS.map((r, i) => `<div class="netrow" id="now${i}"><span class="neticon"></span><div><div class="netname">${r.name}</div><div class="netpurpose">${r.purpose}</div><div class="nethost">${r.host}</div></div></div>`).join('')}
    <div class="netgroup" id="laterlbl">ONLY IF YOU CONNECT THEM</div>
    ${LATER_ROWS.map((r, i) => `<div class="netrow dim" id="later${i}"><span class="neticon"></span><div><div class="netname">${r.name}</div><div class="nethost">${r.host}</div></div></div>`).join('')}
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">DATA → ICLOUD SYNC</div>
    <div class="lockwrap"><div class="lock" id="lock"><svg id="lockicon" width="56" height="56" viewBox="0 0 24 24"><rect x="4" y="11" width="16" height="9" rx="2.5" fill="rgba(255,255,255,.5)"/><path d="M7 11V7a5 5 0 0 1 10 0v4" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2.2"/></svg></div></div>
    <div class="togglecard">
      <div class="togglehead"><span class="togglelbl2">iCloud Sync</span><div class="toggle"><div class="toggleknob" id="knob" style="left:45px;background:${BLUE}"></div></div></div>
      <div class="nudgetext" id="nudge">For end-to-end encryption of your iCloud copy, turn on <b>Advanced Data Protection</b> in Settings → [your name] → iCloud. Then only your devices can read it — <b>not even Apple.</b></div>
    </div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">$ NETWORK-REACH-AUDIT.SH</div>
    <div class="term">
      ${AUDIT_LINES.map((l, i) => `<div class="termline" id="tl${i}">checking <span class="h">${l.host}</span> ... <span class="ok">✓ disclosed</span></div>`).join('')}
      <div class="termline" id="tlfinal">network-reach-audit: <span class="ok">OK</span></div>
    </div>
    <div class="termstamp" id="stamp">✓ AN UNDISCLOSED HOST FAILS THE BUILD</div>
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
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.5);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(50,Math.min(260,850/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function stagger(sel,p,stagger,dur){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*stagger)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*22)+'px)';});}
function animateComp(i,p,t,local){
  if(i===0){
    stagger('#comp0 .netrow', p, 0.14, 0.32);
    document.getElementById('laterlbl').style.opacity=clamp01((p-0.55)/0.2);
  } else if(i===1){
    const adp=clamp01((p-0.42)/0.18);
    document.getElementById('knob').style.left=(45-adp*40)+'px';
    document.getElementById('nudge').style.opacity=clamp01((p-0.42)/0.3);
    const lockp=clamp01((p-0.42)/0.3);
    document.getElementById('lock').style.background = lockp>0.5 ? '${GREEN}' : 'rgba(255,255,255,.06)';
    document.getElementById('lockicon').querySelectorAll('rect,path').forEach(el=>{ el.setAttribute(el.tagName==='rect'?'fill':'stroke', lockp>0.5?'#fff':'rgba(255,255,255,.5)'); });
    document.querySelector('#comp1 .togglecard').style.opacity=clamp01((p-0.02)/0.2);
  } else if(i===2){
    document.querySelector('#comp2 .term').style.opacity=clamp01((p-0.02)/0.2);
    [0,1,2,3].forEach(k=>{ const el=document.getElementById('tl'+k); const lp=clamp01((p-0.12-k*0.13)/0.16); el.style.opacity=lp; el.style.transform='translateX('+((1-easeOut(lp))*-20)+'px)'; });
    const finalp=clamp01((p-0.68)/0.16);
    document.getElementById('tlfinal').style.opacity=finalp;
    const stampp=clamp01((p-0.8)/0.2);
    document.getElementById('stamp').style.opacity=stampp;
    document.getElementById('stamp').style.transform='scale('+(0.7+0.3*back(stampp))+')';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(require('path').join(__dirname, 'clip-networkreach-editorial.html'), html);
console.log('wrote clip-networkreach-editorial.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
