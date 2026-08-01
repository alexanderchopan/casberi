// Slack promo — EDITORIAL, no app screenshots. Grounded line-by-line in
// Model/SlackBridge.swift + the catalog offer (2026-07-28):
//   0 SLACK'S OWN SIGN-IN — OAuth with PKCE, run entirely on this iPhone —
//     no server ever holds a secret (what un-parked this bridge: Slack made
//     PKCE generally available in March 2026).
//   1 MENTIONS ONLY — lands the same shape a Farcaster/Bluesky mention
//     already does (.chat, full text, socialContext = "mention"). Newest 20,
//     via search.messages — a query for "mentions of you" run every sync.
//   2 ONE SCOPE — search:read, and nothing else. Deliberately never touches
//     conversations.history/replies (Slack throttled those hard for
//     non-Marketplace apps in 2025).
//   3 WHAT LANDS — author, channel, the full text, a permalink straight back
//     to the thread.
//   4 WHAT IT CAN'T DO — can't post, can't read files, can't see a channel
//     it wasn't asked about.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-slack-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ICON = 'data:image/png;base64,' + fs.readFileSync(path.join(
  __dirname, '../../Casberi/Casberi/Assets.xcassets/brand-slack.imageset/icon.png')).toString('base64');

const SLACK_PURPLE = '#611f69', SLACK_GREEN = '#2eb67d', SLACK_BLUE = '#36c5f0', SLACK_YELLOW = '#ecb22e';
const AMBER = '#ff9f0a', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: "SLACK'S OWN SIGN-IN", head: 'No password.\nNo token to paste.', accent: SLACK_PURPLE },
  { kick: 'MENTIONS ONLY',      head: 'Never miss\nan @-mention.',        accent: SLACK_GREEN },
  { kick: 'ONE SCOPE',          head: 'search:read.\nNothing else.',      accent: SLACK_BLUE },
  { kick: 'WHAT LANDS',         head: 'Who, where,\nand the words.',      accent: AMBER },
  { kick: "WHAT IT CAN'T DO",   head: "Can't post.\nCan't peek around.",  accent: ORANGE },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const MENTIONS = [
  { u: 'sam', c: '#design', t: 'hey @you can you take a look at the wallet merge PR?' },
  { u: 'nari', c: '#launch', t: 'pulling @you into the App Store copy thread' },
  { u: 'devon', c: '#eng', t: '@you the decimals bug is back, same shape as before' },
];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:98px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — sign in */
.signcard{background:rgba(255,255,255,.06);border-radius:24px;padding:32px;text-align:center;}
.signmark{width:88px;height:88px;border-radius:22px;margin:0 auto 20px;overflow:hidden;box-shadow:0 10px 26px rgba(0,0,0,.35);}
.signmark img{width:100%;height:100%;display:block;}
.signbtn{margin-top:6px;background:rgba(255,255,255,.1);border-radius:100px;padding:20px 30px;font-size:26px;font-weight:700;will-change:background,color;}
.signbtn.armed{background:#fff;color:#14110d;}
.signnote{margin-top:22px;font-size:22px;color:rgba(255,255,255,.5);font-weight:600;}
/* 1 — mentions */
.mrow{display:flex;align-items:flex-start;gap:18px;padding:18px 0;will-change:opacity,transform;}
.mav{width:52px;height:52px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:22px;color:#fff;}
.mhead{display:flex;align-items:baseline;gap:10px;}
.mu{font-size:24px;font-weight:750;}
.mc{font-size:19px;color:rgba(255,255,255,.4);font-family:ui-monospace,monospace;}
.mt{font-size:22px;color:rgba(255,255,255,.78);margin-top:4px;line-height:1.4;}
/* 2 — scope */
.scopebig{background:rgba(255,255,255,.06);border-radius:22px;padding:28px 30px;display:flex;align-items:center;gap:20px;}
.scopebig code{font-size:32px;font-weight:750;font-family:ui-monospace,monospace;}
.notlist{margin-top:24px;display:flex;flex-direction:column;gap:12px;}
.notlist div{display:flex;align-items:center;gap:18px;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);will-change:opacity,transform;}
.notlist s{width:38px;height:38px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:18px;text-decoration:none;}
/* 3 — what lands */
.lrow{display:flex;align-items:center;gap:20px;padding:19px 0;will-change:opacity,transform;}
.lrow .li{width:50px;height:50px;border-radius:50%;flex:none;background:rgba(255,255,255,.08);display:flex;align-items:center;justify-content:center;}
.lrow .lt{font-size:26px;font-weight:700;}
.lrow .ls{font-size:20px;color:rgba(255,255,255,.42);margin-top:3px;}
/* 4 — can't do */
.crow{display:flex;align-items:center;gap:20px;padding:18px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.crow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.cgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.cgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${SLACK_PURPLE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span class="brand"><img src="${ICON}"><span>SLACK</span></span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">CONNECT</div>
    <div class="signcard">
      <div class="signmark"><img src="${ICON}"></div>
      <div class="signbtn" id="signbtn">Sign in with Slack</div>
      <div class="signnote">No password. No token to paste — PKCE, run entirely on this iPhone.</div>
    </div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">MENTIONS OF YOU</div>
    ${MENTIONS.map((m, i) => `<div class="mrow" data-i="${i}"><span class="mav" style="background:${[SLACK_GREEN, SLACK_BLUE, SLACK_YELLOW][i]}">${m.u[0].toUpperCase()}</span><div><div class="mhead"><span class="mu">${m.u}</span><span class="mc">${m.c}</span></div><div class="mt">${m.t}</div></div></div>`).join('')}
    <div class="cap">Newest 20, every sync —<br><b>never a channel you didn't ask for.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">GRANTED SCOPE</div>
    <div class="scopebig"><span style="width:14px;height:14px;border-radius:50%;background:${GREEN};flex:none"></span><code>search:read</code></div>
    <div class="notlist">
      <div><s>✕</s> conversations.history</div>
      <div><s>✕</s> conversations.replies</div>
      <div><s>✕</s> chat:write</div>
    </div>
    <div class="cap">Not throttled, not touched —<br><b>one scope, nothing wider.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">WHAT LANDS</div>
    <div class="lrow" data-i="0"><span class="li"><svg width="24" height="24" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="rgba(255,255,255,.7)"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="rgba(255,255,255,.7)"/></svg></span><div><div class="lt">Who mentioned you</div><div class="ls">Their name, right on the row</div></div></div>
    <div class="lrow" data-i="1"><span class="li"><svg width="22" height="22" viewBox="0 0 24 24"><path d="M4 4h16v12H8l-4 4V4z" fill="none" stroke="rgba(255,255,255,.7)" stroke-width="2"/></svg></span><div><div class="lt">Which channel</div><div class="ls">#design, #eng — wherever it happened</div></div></div>
    <div class="lrow" data-i="2"><span class="li"><svg width="22" height="22" viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h10" stroke="rgba(255,255,255,.7)" stroke-width="2" stroke-linecap="round"/></svg></span><div><div class="lt">The full text</div><div class="ls">Not a snippet — findable later, in full</div></div></div>
    <div class="lrow" data-i="3"><span class="li"><svg width="22" height="22" viewBox="0 0 24 24"><path d="M9 15 15 9M9 9h6v6" fill="none" stroke="rgba(255,255,255,.7)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></span><div><div class="lt">A permalink</div><div class="ls">Straight back to the real thread</div></div></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">STRUCTURALLY LIMITED</div>
    <div class="crow" data-i="0"><s>✕</s> Can't post a message</div>
    <div class="crow" data-i="1"><s>✕</s> Can't read files</div>
    <div class="crow" data-i="2"><s>✕</s> Can't browse a channel it wasn't asked about</div>
    <div class="cgood" id="cgood"><i>✓</i> Looks up mentions. That's all.</div>
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
    document.querySelector('#comp0 .signcard').style.opacity=clamp01((p-0.04)/0.24);
    document.getElementById('signbtn').classList.toggle('armed',clamp01((p-0.4)/0.16)>0.5);
    document.querySelector('#comp0 .signnote').style.opacity=clamp01((p-0.58)/0.28);
  } else if(i===1){
    stag('#comp1 .mrow',p,0.18,0.32,20);
    if(cap)cap.style.opacity=clamp01((p-0.7)/0.26);
  } else if(i===2){
    document.querySelector('#comp2 .scopebig').style.opacity=clamp01((p-0.04)/0.22);
    stag('#comp2 .notlist div',clamp01((p-0.32)/0.68),0.16,0.3,16);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===3){
    stag('#comp3 .lrow',p,0.15,0.3,20);
  } else if(i===4){
    stag('#comp4 .crow',p,0.15,0.3,20);
    const g=document.getElementById('cgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-slack-editorial.html'),html);
console.log('wrote clip-slack-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
