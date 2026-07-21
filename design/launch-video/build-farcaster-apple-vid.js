// Apple-style Farcaster walkthrough — REAL simulator motion (dark mode).
// Same clean dark stage / device frame / bold headline captions as the stills
// version, but each beat is a live screen-recording clip (store push, feed
// recolor, cast sheet slide, board), fast-cut. Videos play in realtime, so
// record with Playwright (record-farcaster-apple-vid.js), not frame-seek.
const fs = require('fs');
const path = require('path');

const index = fs.readFileSync('/Users/alexanderchopan/Developer/casberi/website/index.html', 'utf8');
const berryIcon = index.match(/rel="icon" href="(data:image\/png;base64,[^"]+)"/)[1];

const BEATS = [
  { clip: 'store.mp4',     head: 'Add Farcaster' },
  { clip: 'farcaster.mp4', head: 'Follow vitalik.eth' },
  { clip: 'feed.mp4',      head: 'Casts, likes, mentions' },
  { clip: 'thread.mp4',    head: 'Open any cast' },
  { clip: 'home.mp4',      head: 'All on your Home' },
];

const INTRO = 0.15;
const BEAT_DUR = 1.15;                 // fast, but enough for the motion to read
const OUT_AT = INTRO + BEATS.length * BEAT_DUR;
const TOTAL = OUT_AT + 1.5;
const OUTRO_AT = OUT_AT + 0.15;

const videoTags = BEATS.map((b, i) =>
  `<video class="shot" id="shot${i}" src="fc-clips-dark/${b.clip}" muted playsinline preload="auto"></video>`).join('\n');
const HEADS = BEATS.map(b => b.head);

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#06070b;
  font-family:-apple-system,"SF Pro Display","SF Pro Text","Helvetica Neue",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}
.stage{position:absolute;inset:0;overflow:hidden;background:#06070b;}
.glow{position:absolute;inset:-20%;
  background:radial-gradient(900px 700px at 50% 30%, rgba(124,77,220,.22), transparent 62%),
             radial-gradient(760px 620px at 72% 82%, rgba(64,42,120,.16), transparent 60%);
  will-change:transform;}
.cap{position:absolute;left:90px;right:90px;top:176px;text-align:center;will-change:transform,opacity;}
.cap h1{color:#fff;font-size:82px;line-height:1.02;font-weight:700;letter-spacing:-.028em;}
.phone{position:absolute;left:230px;top:500px;width:620px;height:1319px;
  background:#0c0d11;border:1px solid rgba(255,255,255,.08);border-radius:70px;
  box-shadow:0 50px 120px rgba(0,0,0,.6), inset 0 1px 0 rgba(255,255,255,.06);
  will-change:transform,opacity;overflow:hidden;}
.screen{position:absolute;inset:12px;border-radius:58px;overflow:hidden;background:#000;}
.shot{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:top center;opacity:0;}
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
  <div class="phone" id="phone"><div class="screen">${videoTags}</div></div>
  <div class="cap" id="cap"><h1 id="head"></h1></div>
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
const HEADS=${JSON.stringify(HEADS)};
window.TOTAL=${TOTAL};
const shots=HEADS.map((_,i)=>document.getElementById('shot'+i));
const started=HEADS.map(()=>false);

window.seek=function(t){
  const g=Math.sin(t*0.5), h=Math.cos(t*0.4);
  document.getElementById('glow').style.transform='translate('+(g*16)+'px,'+(h*14)+'px)';

  const active=Math.max(0,Math.min(HEADS.length-1,Math.floor((t-INTRO)/BEAT_DUR)));
  const bStart=INTRO+active*BEAT_DUR;

  const inP=easeOut(clamp01(t/0.3));
  const snap=1+0.014*(1-easeOut(clamp01((t-bStart)/0.2)));
  let py=(1-inP)*40, ps=(0.972+0.028*inP)*snap, pop=inP;
  if(t>OUT_AT){const o=clamp01((t-OUT_AT)/0.4);py+=easeInOut(o)*120;pop*=(1-o);}
  const phone=document.getElementById('phone');
  phone.style.transform='translateY('+py+'px) scale('+ps+')';
  phone.style.opacity=pop;

  // clips: fade in over the previous one (stacked), start playing on cut
  HEADS.forEach((_,i)=>{
    const at=INTRO+i*BEAT_DUR;
    shots[i].style.opacity=clamp01((t-at)/0.16);
    if(t>=at-0.1 && !started[i]){
      started[i]=true;
      try{shots[i].currentTime=0;shots[i].play().catch(()=>{});}catch(e){}
    }
  });

  const cin=clamp01((t-bStart)/0.13);
  let cop=easeOut(cin);
  if(t>OUT_AT) cop*=(1-clamp01((t-OUT_AT)/0.22));
  const cap=document.getElementById('cap');
  cap.style.opacity=cop;
  cap.style.transform='translateY('+((1-easeOut(cin))*14)+'px)';
  document.getElementById('head').textContent=HEADS[active];

  const o=document.getElementById('outro');
  const oin=clamp01((t-OUTRO_AT)/0.4);
  o.style.opacity=easeOut(oin);
  o.style.transform='translateY('+((1-easeOut(oin))*20)+'px)';
};

// realtime driver (videos need wall-clock playback)
window.__ready=false;
let startTime=null;
function loop(now){
  if(startTime===null) startTime=now;
  const t=(now-startTime)/1000;
  window.seek(t);
  if(t<window.TOTAL+0.4) requestAnimationFrame(loop);
  else window.__ready=true;
}
requestAnimationFrame(loop);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-farcaster-apple-vid.html'), html);
console.log('wrote clip-farcaster-apple-vid.html', TOTAL.toFixed(1)+'s');
