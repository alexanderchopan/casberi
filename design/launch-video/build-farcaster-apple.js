// Builds an Apple-style walkthrough clip from 8 real device screenshots:
// clean dark stage, the screenshot floating in a device frame, one bold caption
// per beat, slow Ken Burns + cross-dissolves. Rendered FRAME-BY-FRAME (the
// beats are stills, so deterministic seek gives buttery motion) — pair with
// render.js: `node render.js clip-farcaster-apple.html --size=1080x1920`.
const fs = require('fs');
const path = require('path');

const SHOTS = '/Users/alexanderchopan/Developer/casberi/scratchpad/fc-shots/ordered';
const b64 = f => 'data:image/jpeg;base64,' + fs.readFileSync(path.join(SHOTS, f)).toString('base64');

const index = fs.readFileSync('/Users/alexanderchopan/Developer/casberi/website/index.html', 'utf8');
const berryIcon = index.match(/rel="icon" href="(data:image\/png;base64,[^"]+)"/)[1];

// Beat = one screenshot + a headline and a supporting line (Apple voice: short,
// confident, benefit-first).
const BEATS = [
  { img: 'b01.jpg', head: 'Add Farcaster',        sub: 'Right from the in-app store.' },
  { img: 'b02.jpg', head: 'Just a username',      sub: 'No password. Nothing stored but the name.' },
  { img: 'b03.jpg', head: 'Find anyone',          sub: 'Here: vitalik.eth.' },
  { img: 'b04.jpg', head: 'Follow their world',   sub: 'Casts, likes, and mentions.' },
  { img: 'b05.jpg', head: 'Pin them to Home',     sub: 'And follow /channels by name.' },
  { img: 'b06.jpg', head: 'One feed. Every cast.', sub: 'Synced the moment you open.' },
  { img: 'b07.jpg', head: 'Open any cast',        sub: 'The whole thread — faces and all.' },
  { img: 'b08.jpg', head: 'All on your Home',     sub: 'Where your day comes together.' },
];

const INTRO = 0.12;
const BEAT_DUR = 0.56;                 // fast montage — ~5s overall
const OUT_AT = INTRO + BEATS.length * BEAT_DUR;
const TOTAL = OUT_AT + 1.1;
const OUTRO_AT = OUT_AT + 0.12;

const imgTags = BEATS.map((b, i) =>
  `<img class="shot" id="shot${i}" src="${b64(b.img)}">`).join('\n');

const BEATDATA = BEATS.map(b => ({ head: b.head, sub: b.sub }));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;
  background:#06070b;
  font-family:-apple-system,"SF Pro Display","SF Pro Text","Helvetica Neue",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}
.stage{position:absolute;inset:0;overflow:hidden;background:#06070b;}
/* soft brand glow, drifts slowly */
.glow{position:absolute;inset:-20%;
  background:radial-gradient(900px 700px at 50% 30%, rgba(124,77,220,.22), transparent 62%),
             radial-gradient(760px 620px at 72% 82%, rgba(64,42,120,.16), transparent 60%);
  will-change:transform;}
.cap{position:absolute;left:90px;right:90px;top:172px;text-align:center;will-change:transform,opacity;}
.cap h1{color:#fff;font-size:82px;line-height:1.02;font-weight:700;letter-spacing:-.028em;}
.cap p{display:none;}
.phone{position:absolute;left:230px;top:500px;width:620px;height:1319px;
  background:#0c0d11;border:1px solid rgba(255,255,255,.08);border-radius:70px;
  box-shadow:0 50px 120px rgba(0,0,0,.6), inset 0 1px 0 rgba(255,255,255,.06);
  will-change:transform,opacity;overflow:hidden;}
.screen{position:absolute;inset:12px;border-radius:58px;overflow:hidden;background:#000;}
.shot{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:top center;
  opacity:0;will-change:transform,opacity;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  opacity:0;will-change:opacity,transform;}
.outro .ic{width:132px;height:132px;border-radius:33px;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.55);}
.outro .ic img{width:100%;height:100%;display:block;}
.outro .wm{color:#fff;font-size:56px;font-weight:700;letter-spacing:-.02em;margin-top:34px;}
.outro .tf{color:rgba(255,255,255,.55);font-size:31px;font-weight:450;margin-top:14px;}
.outro .tf b{color:#a98bf0;font-weight:600;}
</style></head><body>
<div class="stage">
  <div class="glow" id="glow"></div>
  <div class="phone" id="phone"><div class="screen">${imgTags}</div></div>
  <div class="cap" id="cap"><h1 id="head"></h1><p id="sub"></p></div>
  <div class="outro" id="outro">
    <div class="ic"><img src="${berryIcon}"></div>
    <div class="wm">Casberi</div>
    <div class="tf"><b>casberi.app</b> &nbsp;·&nbsp; Free on TestFlight</div>
  </div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const easeInOut=p=>p<.5?4*p*p*p:1-Math.pow(-2*p+2,3)/2;
const INTRO=${INTRO}, BEAT_DUR=${BEAT_DUR}, OUT_AT=${OUT_AT}, OUTRO_AT=${OUTRO_AT};
const BEATS=${JSON.stringify(BEATDATA)};
window.TOTAL=${TOTAL};
const shots=BEATS.map((_,i)=>document.getElementById('shot'+i));

window.seek=function(t){
  // drifting brand glow
  const g=Math.sin(t*0.5), h=Math.cos(t*0.4);
  document.getElementById('glow').style.transform='translate('+(g*16)+'px,'+(h*14)+'px)';

  const active=Math.max(0,Math.min(BEATS.length-1,Math.floor((t-INTRO)/BEAT_DUR)));
  const bStart=INTRO+active*BEAT_DUR;

  // phone: quick fade+scale in, a tiny SNAP on every cut (whole frame + shot
  // scale together, so nothing looks cropped), drops away at the end.
  const inP=easeOut(clamp01(t/0.3));
  const snap=1+0.014*(1-easeOut(clamp01((t-bStart)/0.2)));
  let py=(1-inP)*40, ps=(0.972+0.028*inP)*snap, pop=inP;
  if(t>OUT_AT){const o=clamp01((t-OUT_AT)/0.4);py+=easeInOut(o)*120;pop*=(1-o);}
  const phone=document.getElementById('phone');
  phone.style.transform='translateY('+py+'px) scale('+ps+')';
  phone.style.opacity=pop;

  // screenshots: STATIC in the frame (no zoom), just a fast cross-cut — each
  // fades in over the one before (stacked, later on top = no black dip).
  BEATS.forEach((_,i)=>{
    shots[i].style.opacity=clamp01((t-(INTRO+i*BEAT_DUR))/0.16);
  });

  // caption: headline only, snaps in fast on each cut.
  const cin=clamp01((t-bStart)/0.13);
  let cop=easeOut(cin);
  if(t>OUT_AT) cop*=(1-clamp01((t-OUT_AT)/0.22));
  const cap=document.getElementById('cap');
  cap.style.opacity=cop;
  cap.style.transform='translateY('+((1-easeOut(cin))*14)+'px)';
  document.getElementById('head').textContent=BEATS[active].head;

  // outro sign-off
  const o=document.getElementById('outro');
  const oin=clamp01((t-OUTRO_AT)/0.4);
  o.style.opacity=easeOut(oin);
  o.style.transform='translateY('+((1-easeOut(oin))*20)+'px)';
};
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-farcaster-apple.html'), html);
console.log('wrote clip-farcaster-apple.html', (html.length/1024/1024).toFixed(1)+'MB', TOTAL.toFixed(1)+'s');
