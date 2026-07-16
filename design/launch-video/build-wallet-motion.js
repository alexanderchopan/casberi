// Farcaster promo — animated motion-graphics from cropped UI portions of real
// dark screenshots (no phone frame). Each beat springs its UI card(s) onto a
// dark stage with a drifting brand glow; captions ease in; the thread beat
// leads on the replies (faces). Deterministic (stills) → render frame-by-frame:
//   node render.js clip-wallet-motion.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const CROPS = '/Users/alexanderchopan/Developer/casberi/scratchpad/wcrops';
const b64 = f => 'data:image/png;base64,' + fs.readFileSync(path.join(CROPS, f)).toString('base64');
const index = fs.readFileSync('/Users/alexanderchopan/Developer/casberi/website/index.html', 'utf8');
const berryIcon = index.match(/rel="icon" href="(data:image\/png;base64,[^"]+)"/)[1];

const BEATS = [
  { imgs: ['watch.png'],    head: 'Watch any wallet',    sub: 'No keys — read-only, on your phone.' },
  { imgs: ['holdings.png'], head: 'See every holding',   sub: 'A live treemap of what they hold.' },
  { imgs: ['tx.png'],       head: 'Every transaction',   sub: 'Sent and received, on-chain.' },
  { imgs: ['chart.png'],    head: 'Live token charts',   sub: 'Price, liquidity, market cap.' },
  { imgs: ['networth.png'], head: 'Your whole net worth', sub: '$415.8M across 33 tokens.' },
];

const INTRO = 0.3;
const BEAT_DUR = 1.45;
const OUT_AT = INTRO + BEATS.length * BEAT_DUR;
const TOTAL = OUT_AT + 1.6;
const OUTRO_AT = OUT_AT + 0.15;

// flatten images with their beat + index-in-beat
let cards = [];
BEATS.forEach((b, bi) => b.imgs.forEach((im, ii) =>
  cards.push({ src: b64(im), beat: bi, idx: ii, count: b.imgs.length })));

const cardTags = cards.map((c, i) =>
  `<img class="card" id="c${i}" src="${c.src}" data-beat="${c.beat}" data-idx="${c.idx}" data-count="${c.count}">`).join('\n');
const HEADS = BEATS.map(b => ({ head: b.head, sub: b.sub }));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#08080e;
  font-family:-apple-system,"SF Pro Display","SF Pro Text","Helvetica Neue",system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;}
.stage{position:absolute;inset:0;overflow:hidden;background:
  radial-gradient(1200px 900px at 50% 8%, #0c1830 0%, #0a0e18 55%, #07090e 100%);}
.glow{position:absolute;inset:-25%;will-change:transform;
  background:radial-gradient(760px 620px at 50% 46%, rgba(56,120,255,.30), transparent 60%),
             radial-gradient(680px 560px at 74% 84%, rgba(29,78,180,.20), transparent 62%);}
.cap{position:absolute;left:80px;right:80px;top:150px;text-align:center;will-change:transform,opacity;z-index:9;}
.cap h1{color:#fff;font-size:80px;line-height:1.0;font-weight:750;letter-spacing:-.03em;}
.cap p{color:rgba(255,255,255,.6);font-size:33px;line-height:1.3;font-weight:450;margin-top:20px;letter-spacing:-.01em;}
.spot{position:absolute;left:50%;top:1010px;width:1040px;height:1040px;transform:translate(-50%,-50%);
  background:radial-gradient(closest-side, rgba(56,120,255,.18), transparent 72%);will-change:opacity;opacity:0;}
.card{position:absolute;left:100px;width:880px;height:auto;border-radius:34px;
  box-shadow:0 40px 90px rgba(0,0,0,.6), 0 0 0 1px rgba(255,255,255,.06);
  will-change:transform,opacity;opacity:0;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
  opacity:0;will-change:opacity,transform;z-index:20;}
.outro .ic{width:140px;height:140px;border-radius:35px;overflow:hidden;box-shadow:0 22px 55px rgba(0,0,0,.55);}
.outro .ic img{width:100%;height:100%;display:block;}
.outro .wm{color:#fff;font-size:58px;font-weight:750;letter-spacing:-.02em;margin-top:36px;}
.outro .tf{color:rgba(255,255,255,.55);font-size:31px;font-weight:450;margin-top:14px;}
.outro .tf b{color:#7fb0ff;font-weight:600;}
</style></head><body>
<div class="stage">
  <div class="glow" id="glow"></div>
  <div class="spot" id="spot"></div>
  ${cardTags}
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
// gentle overshoot spring for card entrances
const back=p=>{const c=1.6;return 1+ (c+1)*Math.pow(p-1,3) + c*Math.pow(p-1,2);};
const INTRO=${INTRO}, BEAT_DUR=${BEAT_DUR}, OUT_AT=${OUT_AT}, OUTRO_AT=${OUTRO_AT};
const HEADS=${JSON.stringify(HEADS)};
window.TOTAL=${TOTAL};
const cards=[...document.querySelectorAll('.card')];

// Lay each beat's card(s) out: scaled to 880 wide, stacked and centred on y=1010.
const ZONE_Y=1010, GAP=26;
function layout(){
  const byBeat={};
  cards.forEach(c=>{const b=+c.dataset.beat;(byBeat[b]=byBeat[b]||[]).push(c);});
  Object.values(byBeat).forEach(group=>{
    const hs=group.map(c=>880*(c.naturalHeight/c.naturalWidth));
    const total=hs.reduce((a,b)=>a+b,0)+GAP*(group.length-1);
    let y=ZONE_Y-total/2;
    group.forEach((c,i)=>{c.dataset.baseTop=y;c.style.top=y+'px';y+=hs[i]+GAP;});
  });
}
layout();

window.seek=function(t){
  const g=Math.sin(t*0.32), h=Math.cos(t*0.24);
  document.getElementById('glow').style.transform='translate('+(g*22)+'px,'+(h*18)+'px)';

  let active=Math.max(0,Math.min(HEADS.length-1,Math.floor((t-INTRO)/BEAT_DUR)));
  const bStart=INTRO+active*BEAT_DUR;

  cards.forEach(c=>{
    const bi=+c.dataset.beat, idx=+c.dataset.idx;
    const bs=INTRO+bi*BEAT_DUR + idx*0.14;        // stagger multi-card beats
    const local=t-bs;
    const ein=clamp01(local/0.62);
    const fadeIn=clamp01(local/0.42);
    // exit: the card slides up and fades just before the next beat lands, so
    // two different cards never sit ghosted on top of each other.
    const beatEnd=INTRO+bi*BEAT_DUR+BEAT_DUR;
    const exit=clamp01((t-(beatEnd-0.28))/0.5);
    let op=fadeIn*(1-exit);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.35));
    const base=+c.dataset.baseTop;
    const yOff=(1-back(ein))*70 - easeInOut(exit)*90 + Math.sin(t*1.1+idx*0.7)*4;  // spring up-in, slide up-out
    const sc=(0.9+0.1*easeOut(ein))*(1-0.05*exit);
    c.style.opacity=op;
    c.style.top=(base+yOff)+'px';
    c.style.transform='scale('+sc+')';
    c.style.transformOrigin='center center';
  });

  // spotlight glows with the active card
  const sp=document.getElementById('spot');
  sp.style.opacity=(0.6*clamp01((t-bStart)/0.5))*(t>OUT_AT?(1-clamp01((t-OUT_AT)/0.3)):1);

  const cin=clamp01((t-bStart)/0.4);
  let cop=easeOut(cin);
  if(t>OUT_AT) cop*=(1-clamp01((t-OUT_AT)/0.3));
  const cap=document.getElementById('cap');
  cap.style.opacity=cop;
  cap.style.transform='translateY('+((1-easeOut(cin))*22)+'px)';
  document.getElementById('head').textContent=HEADS[active].head;
  document.getElementById('sub').textContent=HEADS[active].sub;

  const o=document.getElementById('outro');
  const oin=clamp01((t-OUTRO_AT)/0.6);
  o.style.opacity=easeOut(oin);
  o.style.transform='translateY('+((1-easeOut(oin))*22)+'px)';
};
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-wallet-motion.html'), html);
console.log('wrote clip-wallet-motion.html', (html.length/1024/1024).toFixed(1)+'MB', TOTAL.toFixed(1)+'s');
