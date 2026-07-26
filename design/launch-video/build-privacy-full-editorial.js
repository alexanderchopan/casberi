// Privacy promo (FULL) — EDITORIAL, no app screenshots: warm paper ground,
// oversized type, monospace masthead, diagonal colour wipes, hand-drawn UI.
// Every beat is grounded in shipped code / the live privacy policy:
//   0 NO ACCOUNT   — no account, no sign-up, no password (privacy.html).
//   1 NO SERVER    — corpus in a local DB on device; there is no backend.
//   2 NO TRACKING  — no analytics, no ads, no ad identifiers, nothing sold.
//   3 FULL DISCLOSURE — Model/NetworkReach.swift + Screens/NetworkReachScreen
//                    (Settings row "Network" → "What this app reaches"), made
//                    complete-by-construction by scripts/network-reach-audit.sh
//                    wired into verify.sh — an undisclosed host fails the build.
//   4 YOUR ICLOUD  — sync optional + OFF by default; ADP nudge shipped this
//                    session in Screens/AccountDetailSheet.swift.
//   5 ON DEVICE    — Apple's on-device model writes answers; Vision reads
//                    screenshot text on device (privacy.html).
//   6 YOUR KEY     — BYOK, only on tap, straight to the provider, Keychain
//                    (AccountDetailSheet key tray copy).
//   7 YOURS TO TAKE— Hide previews (privacy.hidePreviews), Export, and the two
//                    delete verbs: Delete things / Delete access.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-privacy-full-editorial.html --size=1080x1920
const fs = require('fs');

const BLUE = '#2E63FF', GREEN = '#3fb950', ORANGE = '#FF6B4A', VIOLET = '#8c40c7';
const BEATS = [
  { kick: 'NO ACCOUNT',      head: 'Nothing to\nsign up for.',        accent: BLUE },
  { kick: 'NO SERVER',       head: 'There is no\nbackend.',           accent: ORANGE },
  { kick: 'NO TRACKING',     head: 'Nothing counted.\nNothing sold.',  accent: ORANGE },
  { kick: 'FULL DISCLOSURE', head: 'Every host,\nlisted.',            accent: BLUE },
  { kick: 'YOUR ICLOUD',     head: 'Off by default.\nYours if you want.', accent: GREEN },
  { kick: 'ON DEVICE',       head: 'Answers written\nright here.',     accent: VIOLET },
  { kick: 'YOUR KEY',        head: 'Only when\nyou tap.',              accent: VIOLET },
  { kick: 'YOURS TO TAKE',   head: 'Export it all.\nDelete it for real.', accent: GREEN },
];
const INTRO = 0.45, BEAT = 2.45, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const SIGNUP = ['Email address', 'Password', 'Username'];
const TRACK  = ['Analytics', 'Usage tracking', 'Advertising', 'Ad identifiers', 'Selling your data'];
const NETROWS = [
  { n: 'Wallet', p: 'Balances you watch', h: 'api.g.alchemy.com' },
  { n: 'Farcaster', p: 'Casts you follow', h: 'api.farcaster.xyz' },
];
const TAKE = [
  { t: 'Hide previews', s: 'Blur your things in the app switcher', i: 'eye' },
  { t: 'Export', s: 'Everything, one file, any time', i: 'up' },
  { t: 'Delete things', s: 'This iPhone and iCloud. No undo.', i: 'trash' },
  { t: 'Delete access', s: 'Every token and key Casberi holds', i: 'key' },
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
/* the eyebrow stays pinned to the card's top edge; the rest centers under it */
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;}
.shd{font-size:25px;letter-spacing:.12em;color:rgba(255,255,255,.45);margin-bottom:30px;}
.cap{margin-top:34px;font-size:27px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* struck rows (no account / no tracking) */
.xrow{display:flex;align-items:center;gap:22px;padding:19px 0;will-change:opacity,transform;}
.xrow s{width:50px;height:50px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:26px;text-decoration:none;font-weight:700;}
.xrow span{font-size:30px;font-weight:600;color:rgba(255,255,255,.5);text-decoration:line-through;text-decoration-color:rgba(255,255,255,.28);}
/* no server */
.srvwrap{display:flex;align-items:center;justify-content:center;gap:34px;padding:30px 0 10px;}
.phone{width:170px;height:290px;border-radius:30px;background:rgba(255,255,255,.08);box-shadow:inset 0 0 0 3px rgba(255,255,255,.16);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;flex:none;}
.phone .pl{width:96px;height:13px;border-radius:7px;background:rgba(255,255,255,.3);}
.phone .pl.a{background:${BLUE};} .phone .pl.b{background:${VIOLET};} .phone .pl.c{background:${GREEN};}
.arrowx{display:flex;flex-direction:column;align-items:center;gap:12px;will-change:opacity;}
.arrowx .ln{width:120px;height:4px;background:rgba(255,255,255,.16);position:relative;}
.arrowx .xx{font-size:56px;color:${ORANGE};font-weight:800;line-height:1;}
.server{width:180px;height:150px;border-radius:22px;background:rgba(255,255,255,.04);box-shadow:inset 0 0 0 3px rgba(255,255,255,.08);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;flex:none;opacity:.4;}
.server .sl{width:110px;height:11px;border-radius:6px;background:rgba(255,255,255,.14);}
.srvlbl{text-align:center;font-size:22px;color:rgba(255,255,255,.4);margin-top:12px;font-weight:600;}
/* network list */
.netgroup{font-size:21px;letter-spacing:.1em;color:rgba(255,255,255,.32);font-weight:650;margin:0 0 14px;}
.netrow{display:flex;align-items:center;gap:18px;padding:13px 0;will-change:opacity,transform;}
.neticon{width:48px;height:48px;border-radius:14px;background:rgba(255,255,255,.1);flex:none;}
.netname{font-size:26px;font-weight:700;}
.netp{font-size:20px;color:rgba(255,255,255,.42);margin-top:1px;}
.neth{font-size:18px;color:rgba(255,255,255,.28);font-family:ui-monospace,monospace;margin-top:1px;}
.term{background:#000;border-radius:16px;padding:22px 24px;font-family:ui-monospace,monospace;font-size:20px;line-height:1.75;margin-top:22px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);}
.term .ok{color:${GREEN};font-weight:700;}
.term .dim{color:rgba(255,255,255,.55);}
/* icloud */
.togglecard{background:rgba(255,255,255,.05);border-radius:22px;padding:28px;}
.togglehead{display:flex;align-items:center;justify-content:space-between;}
.togglelbl2{font-size:29px;font-weight:700;}
.toggle{width:86px;height:47px;border-radius:100px;background:rgba(255,255,255,.14);position:relative;}
.toggleknob{position:absolute;top:5px;width:37px;height:37px;border-radius:50%;background:#fff;will-change:left,background;}
.nudge{margin-top:22px;font-size:23px;line-height:1.5;color:rgba(255,255,255,.55);will-change:opacity;}
.nudge b{color:#fff;}
.lockwrap{display:flex;justify-content:center;margin-bottom:26px;}
.lock{width:118px;height:118px;border-radius:50%;background:rgba(255,255,255,.06);display:flex;align-items:center;justify-content:center;will-change:background;}
/* on device */
.chipwrap{display:flex;flex-direction:column;align-items:center;gap:26px;padding:14px 0 4px;}
.chipbox{width:210px;height:210px;border-radius:44px;background:rgba(255,255,255,.06);box-shadow:inset 0 0 0 3px rgba(255,255,255,.14);display:flex;align-items:center;justify-content:center;position:relative;will-change:box-shadow;}
.chipbox .core{width:96px;height:96px;border-radius:24px;background:${VIOLET};will-change:transform,opacity;}
.pulse{position:absolute;inset:0;border-radius:44px;box-shadow:0 0 0 3px ${VIOLET};opacity:0;will-change:transform,opacity;}
.odrow{display:flex;align-items:center;gap:18px;font-size:26px;font-weight:600;color:rgba(255,255,255,.8);will-change:opacity,transform;padding:11px 0;}
.odrow i{width:44px;height:44px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
/* your key */
.keycard{background:#05050e;border-radius:22px;padding:32px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.keyfield{background:rgba(255,255,255,.06);border-radius:100px;padding:19px 26px;font-size:25px;color:rgba(255,255,255,.85);font-family:ui-monospace,monospace;}
.trybtn{margin-top:20px;text-align:center;padding:20px;border-radius:100px;font-size:27px;font-weight:700;background:rgba(255,255,255,.12);color:rgba(255,255,255,.5);will-change:background,color,transform;}
.trybtn.armed{background:${VIOLET};color:#fff;}
.keynote{margin-top:26px;font-size:23px;line-height:1.5;color:rgba(255,255,255,.55);will-change:opacity;}
.keynote b{color:#fff;}
/* take */
.trow{display:flex;align-items:center;gap:20px;padding:17px 0;will-change:opacity,transform;}
.trow .ti{width:52px;height:52px;border-radius:15px;flex:none;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;}
.trow .tt{font-size:27px;font-weight:700;}
.trow .ts{font-size:20px;color:rgba(255,255,255,.42);margin-top:2px;}
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
    <div class="shd mono">SIGN UP</div>
    ${SIGNUP.map((s,i)=>`<div class="xrow" data-i="${i}"><s>✕</s><span>${s}</span></div>`).join('')}
    <div class="cap">No account. No password.<br><b>Nothing for us to lose.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">WHERE YOUR THINGS LIVE</div>
    <div class="srvwrap">
      <div class="phone"><span class="pl a"></span><span class="pl b"></span><span class="pl"></span><span class="pl c"></span><span class="pl"></span></div>
      <div class="arrowx" id="arrowx"><span class="ln"></span><span class="xx">✕</span></div>
      <div class="server"><span class="sl"></span><span class="sl"></span><span class="sl"></span></div>
    </div>
    <div class="srvlbl">this iPhone &nbsp;&nbsp;·&nbsp;&nbsp; a Casberi server</div>
    <div class="cap">Your corpus is a database <b>on your phone.</b><br>There is no "us" to upload it to.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHAT WE COLLECT</div>
    ${TRACK.map((s,i)=>`<div class="xrow" data-i="${i}"><s>✕</s><span>${s}</span></div>`).join('')}
    <div class="cap">No analytics, no ads, no identifiers.<br><b>Nothing to sell — we never receive it.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">SETTINGS → WHAT THIS APP REACHES</div>
    <div class="netgroup">REACHING NOW</div>
    ${NETROWS.map((r,i)=>`<div class="netrow" data-i="${i}"><span class="neticon"></span><div><div class="netname">${r.n}</div><div class="netp">${r.p}</div><div class="neth">${r.h}</div></div></div>`).join('')}
    <div class="term">
      <div class="dim" id="t0">$ network-reach-audit.sh</div>
      <div id="t1"><span class="dim">every host disclosed</span> <span class="ok">✓ OK</span></div>
    </div>
    <div class="cap">An undisclosed host<br><b>fails the build.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">DATA → ICLOUD SYNC</div>
    <div class="lockwrap"><div class="lock" id="lock"><svg id="lockicon" width="52" height="52" viewBox="0 0 24 24"><rect x="4" y="11" width="16" height="9" rx="2.5" fill="rgba(255,255,255,.5)"/><path d="M7 11V7a5 5 0 0 1 10 0v4" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2.2"/></svg></div></div>
    <div class="togglecard">
      <div class="togglehead"><span class="togglelbl2">iCloud Sync</span><div class="toggle"><div class="toggleknob" id="knob"></div></div></div>
      <div class="nudge" id="nudge">Your own private iCloud — never ours. For end-to-end encryption turn on <b>Advanced Data Protection</b>: only your devices can read it, <b>not even Apple.</b></div>
    </div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">ON-DEVICE INTELLIGENCE</div>
    <div class="chipwrap"><div class="chipbox" id="chipbox"><div class="pulse" id="pulse"></div><div class="core" id="core"></div></div></div>
    <div style="margin-top:28px">
      <div class="odrow" data-i="0"><i>✓</i><span>Apple's on-device model writes answers</span></div>
      <div class="odrow" data-i="1"><i>✓</i><span>Vision reads your screenshots here</span></div>
    </div>
    <div class="cap"><b>Nothing is sent</b> to us, to Apple, or to anyone.</div>
  </div>

  <div class="comp" id="comp6">
    <div class="shd mono">YOUR OWN AI KEY — OPTIONAL</div>
    <div class="keycard">
      <div class="keyfield">sk-ant-••••••••4f2a</div>
      <div class="trybtn" id="trybtn">Try with your key</div>
      <div class="keynote" id="keynote">Only when you tap, your question goes <b>straight from this iPhone</b> to the provider you chose. The key lives in the <b>Keychain</b>. Remove it and the button disappears.</div>
    </div>
  </div>

  <div class="comp" id="comp7">
    <div class="shd mono">IT'S YOURS</div>
    ${TAKE.map((r,i)=>`<div class="trow" data-i="${i}"><span class="ti">${r.i==='eye'?'<svg width="26" height="26" viewBox="0 0 24 24"><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z" fill="none" stroke="rgba(255,255,255,.75)" stroke-width="2"/><circle cx="12" cy="12" r="3" fill="rgba(255,255,255,.75)"/><path d="M3 21 21 3" stroke="rgba(255,255,255,.75)" stroke-width="2"/></svg>':r.i==='up'?'<svg width="26" height="26" viewBox="0 0 24 24"><path d="M12 19V5M5 12l7-7 7 7" fill="none" stroke="rgba(255,255,255,.75)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>':r.i==='trash'?'<svg width="26" height="26" viewBox="0 0 24 24"><path d="M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13" fill="none" stroke="rgba(255,255,255,.75)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>':'<svg width="26" height="26" viewBox="0 0 24 24"><circle cx="8" cy="12" r="4" fill="none" stroke="rgba(255,255,255,.75)" stroke-width="2"/><path d="M12 12h9M18 12v4" fill="none" stroke="rgba(255,255,255,.75)" stroke-width="2" stroke-linecap="round"/></svg>'}</span><div><div class="tt">${r.t}</div><div class="ts">${r.s}</div></div></div>`).join('')}
    <div class="cap">Take it all with you.<br><b>Or make it gone, for real.</b></div>
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
function stagRows(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.4);
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
  if(i===0){ stagRows('#comp0 .xrow',p,0.13,0.3); if(cap)cap.style.opacity=clamp01((p-0.5)/0.3); }
  else if(i===1){
    document.querySelector('#comp1 .srvwrap').style.opacity=clamp01((p-0.02)/0.22);
    document.getElementById('arrowx').style.opacity=clamp01((p-0.3)/0.25);
    document.querySelector('#comp1 .srvlbl').style.opacity=clamp01((p-0.2)/0.25);
    if(cap)cap.style.opacity=clamp01((p-0.5)/0.3);
  }
  else if(i===2){ stagRows('#comp2 .xrow',p,0.1,0.26); if(cap)cap.style.opacity=clamp01((p-0.6)/0.3); }
  else if(i===3){
    stagRows('#comp3 .netrow',p,0.12,0.28);
    document.querySelector('#comp3 .netgroup').style.opacity=clamp01((p-0.02)/0.2);
    document.getElementById('t0').style.opacity=clamp01((p-0.4)/0.2);
    document.getElementById('t1').style.opacity=clamp01((p-0.56)/0.2);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.25);
  }
  else if(i===4){
    document.querySelector('#comp4 .togglecard').style.opacity=clamp01((p-0.02)/0.2);
    const on=clamp01((p-0.4)/0.18);
    document.getElementById('knob').style.left=(5+on*39)+'px';
    document.getElementById('knob').style.background=on>0.5?'${GREEN}':'#fff';
    document.getElementById('nudge').style.opacity=clamp01((p-0.42)/0.3);
    const lp=clamp01((p-0.42)/0.3);
    document.getElementById('lock').style.background=lp>0.5?'${GREEN}':'rgba(255,255,255,.06)';
    document.getElementById('lockicon').querySelectorAll('rect,path').forEach(el=>{el.setAttribute(el.tagName==='rect'?'fill':'stroke',lp>0.5?'#fff':'rgba(255,255,255,.5)');});
  }
  else if(i===5){
    document.querySelector('#comp5 .chipwrap').style.opacity=clamp01((p-0.02)/0.2);
    const bp=(t*1.5)%1;
    const pu=document.getElementById('pulse');pu.style.opacity=(1-bp)*0.5;pu.style.transform='scale('+(1+bp*0.22)+')';
    document.getElementById('core').style.transform='scale('+(1+Math.sin(t*3.4)*0.07)+')';
    stagRows('#comp5 .odrow',clamp01((p-0.3)/0.7),0.16,0.32);
    if(cap)cap.style.opacity=clamp01((p-0.68)/0.25);
  }
  else if(i===6){
    document.querySelector('#comp6 .keycard').style.opacity=clamp01((p-0.02)/0.2);
    const tap=clamp01((p-0.38)/0.14);
    const btn=document.getElementById('trybtn');
    btn.classList.toggle('armed',tap>0.5);
    btn.style.transform='scale('+(tap>0.5&&tap<0.9?0.97:1)+')';
    document.getElementById('keynote').style.opacity=clamp01((p-0.5)/0.3);
  }
  else if(i===7){ stagRows('#comp7 .trow',p,0.12,0.28); if(cap)cap.style.opacity=clamp01((p-0.66)/0.28); }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(require('path').join(__dirname,'clip-privacy-full-editorial.html'),html);
console.log('wrote clip-privacy-full-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
