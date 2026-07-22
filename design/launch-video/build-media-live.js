// Media apps promo — FEATURE-COMPLETE (2026-07-21): every group from the
// "media + reading" brief gets its own beat — the shared grammar that makes
// nine sources feel like one app, then a sweep across media/reading/notes/
// social. Live HTML/CSS/SVG (no screenshots). List rows for content; ONE
// pill beat for the source roll call (a real tag list, not decorative
// chrome — the lesson from Wallets was chip-shaped UI CONTROLS, not tag
// lists). Deterministic → node render.js clip-media-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const BLUE = '#2E63FF', AMBER = '#E8912A', GRN = '#3fb950', PINK = '#E0345C';

const BEATS = [
  { kick: 'ONE GRAMMAR',   head: 'One grammar,\nnot nine apps.',    accent: BLUE,  dur: 2.6 },
  { kick: 'FEELS ALIVE',   head: 'It feels\nalive.',                accent: BLUE,  dur: 2.8 },
  { kick: 'AUTO OVERVIEWS',head: 'Every source\nsums itself up.',   accent: AMBER, dur: 2.7 },
  { kick: 'DAY CARDS',     head: 'A day is\none card.',             accent: BLUE,  dur: 2.6 },
  { kick: 'MEDIA',         head: 'Every media\napp you use.',       accent: BLUE,  dur: 2.6 },
  { kick: 'LIVE & PLAYED', head: 'Live streams.\nWhat you played.', accent: BLUE,  dur: 2.8 },
  { kick: 'AND THE REST',  head: 'Every scroll,\nremembered.',      accent: BLUE,  dur: 3.0 },
  { kick: 'READING',       head: 'What you\nread.',                 accent: BLUE,  dur: 2.8 },
  { kick: 'NOTES & CHATS', head: 'Your own\nwords.',                accent: GRN,   dur: 2.6 },
  { kick: 'SOCIAL',        head: 'Bluesky &\nFarcaster.',           accent: PINK,  dur: 3.0 },
];
const INTRO = 0.45;
const durs = BEATS.map(b => b.dur);
const STARTS = []; { let acc = INTRO; for (const d of durs) { STARTS.push(acc); acc += d; } }
const OUT_AT = STARTS[STARTS.length - 1] + durs[durs.length - 1];
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const lrows = items => items.map((r, i) =>
  `<div class="lrow" data-i="${i}"><b class="dot"></b><div><div class="lt">${r[0]}</div><div class="ls">${r[1]}</div></div></div>`).join('');
const pills = items => items.map((t, i) => `<div class="pill" data-i="${i}">${t}</div>`).join('');

// tiny GitHub-style heatmap: 12 cols x 5 rows, deterministic pseudo-random shading
const HEAT = Array.from({ length: 60 }, (_, i) => ((i * 37 + 11) % 100) / 100);
const heatCells = HEAT.map((v, i) => `<div class="hc" data-i="${i}" style="--v:${v.toFixed(2)}"></div>`).join('');

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;
  background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);
  background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:120px;line-height:.96;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

.comp{position:absolute;left:120px;top:840px;width:840px;height:800px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;
  transform-origin:center top;padding:52px;color:#fff;}
.comp.blue{background:linear-gradient(160deg,#2E63FF,#1B49D6);}
.comp.amber{background:linear-gradient(160deg,#F0A93A,#D97913);}
.comp.grn{background:linear-gradient(160deg,#0f2e1c,#0a1a10);}
.comp.pink{background:linear-gradient(160deg,#E0345C,#8a1638);}

.lhead{font-size:34px;font-weight:650;margin-bottom:22px;}
.lrow{display:flex;align-items:flex-start;gap:20px;padding:16px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.lrow:first-of-type{border-top:none;}
.dot{width:12px;height:12px;border-radius:50%;background:rgba(255,255,255,.5);flex:none;margin-top:9px;}
.lt{font-size:28px;font-weight:700;}
.ls{font-size:21px;color:rgba(255,255,255,.6);margin-top:3px;line-height:1.38;}

.phead{font-size:34px;font-weight:650;margin-bottom:28px;}
.pgrid{display:flex;flex-wrap:wrap;gap:14px;}
.pill{padding:16px 26px;border-radius:100px;background:rgba(255,255,255,.12);font-size:27px;font-weight:650;will-change:opacity,transform;opacity:0;}

/* auto-overviews visual: heatmap + leaderboard */
.ohead{font-size:30px;color:rgba(255,255,255,.65);margin-bottom:14px;}
.heat{display:grid;grid-template-columns:repeat(12,1fr);gap:7px;margin-bottom:34px;}
.hc{aspect-ratio:1;border-radius:5px;background:rgba(255,255,255,var(--v));will-change:opacity,transform;opacity:0;}
.boardhead{font-size:26px;color:rgba(255,255,255,.65);margin:8px 0 14px;}
.boardrow{display:flex;align-items:center;gap:18px;margin-bottom:14px;will-change:opacity,transform;}
.boardn{font-size:25px;font-weight:700;width:180px;flex:none;}
.boardbar{height:22px;border-radius:8px;background:rgba(255,255,255,.85);flex:none;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:#2E63FF;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>MEDIA</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <!-- 0 ONE GRAMMAR -->
  <div class="comp blue" id="comp0">
    <div class="lhead">Nine sources, one grammar</div>
    ${lrows([
      ['Chip strip navigation', 'no tab bar — circular brand chips, the selection ring slides between them'],
      ['Chip life', 'a chip bobs when a thing lands; switching plays a coin-flip'],
      ['Landing memory', 'the app reopens on whichever chip you last stood on'],
    ])}
  </div>

  <!-- 1 FEELS ALIVE -->
  <div class="comp blue" id="comp1">
    <div class="lhead">Small signals, everywhere</div>
    ${lrows([
      ['“New since” seam', '“New since Friday · 4” — frozen for the whole visit, so it can’t shift under you'],
      ['Pull-to-refresh delight', 'one pull rains berries in that source’s own brand hue'],
      ['Honest footer', 'every feed ends “That’s everything from Spotify · 41”'],
      ['Row entrance choreography', 'photos scale in, music lifts, calendar slides — each shape moves its own way'],
    ])}
  </div>

  <!-- 2 AUTO OVERVIEWS (visual) -->
  <div class="comp amber" id="comp2">
    <div class="ohead">Heatmap years — your capture year, your casting activity</div>
    <div class="heat">${heatCells}</div>
    <div class="boardhead">Leaderboards — computed from your corpus</div>
    ${[['Your top artists', 92], ['Who writes you', 68], ['Your subreddits', 48]].map((r, i) =>
      `<div class="boardrow" data-i="${i}"><div class="boardn">${r[0]}</div><div class="boardbar" style="width:${r[1]}%"></div></div>`).join('')}
  </div>

  <!-- 3 DAY CARDS -->
  <div class="comp blue" id="comp3">
    <div class="lhead">A day, one card</div>
    ${lrows([
      ['Day cards', 'a day’s rows merge into one lifted card, headers speaking the source’s unit'],
      ['Sparse sources coarsen', 'to “This week / Last week” instead of a ladder of one-row days'],
      ['Empty states', 'a fresh feed falls into a pile of app tiles; a connected-but-empty source shows its own skeleton, plus a try-it chip'],
    ])}
  </div>

  <!-- 4 MEDIA (source roll call) -->
  <div class="comp blue" id="comp4">
    <div class="phead">Every media app you use</div>
    <div class="pgrid">${pills(['Twitch', 'Spotify', 'Apple Music', 'Photos', 'Podcasts', 'YouTube', 'Steam', 'Pinterest'])}</div>
  </div>

  <!-- 5 LIVE & PLAYED (Twitch + Spotify/Apple Music) -->
  <div class="comp blue" id="comp5">
    <div class="lhead">Live streams. What you played.</div>
    ${lrows([
      ['Twitch', 'live streams float to the top with a green dot + “Live” — a real stream-frame thumbnail, only while it’s live'],
      ['Spotify & Apple Music', '44pt covers grouped into listening sittings; today’s covers fan like a hand of cards; “Your top artists” leaderboard'],
    ])}
  </div>

  <!-- 6 AND THE REST -->
  <div class="comp blue" id="comp6">
    <div class="lhead">Every scroll, remembered</div>
    ${lrows([
      ['Photos', 'a continuous grid, day pills on the first photo of each day — tap zooms into the sheet'],
      ['Podcasts', '“Your shows” leaderboard over episode rows'],
      ['YouTube', '“Latest uploads” thumbnail mosaic'],
      ['Steam', '“Recently played” by two-week hours'],
      ['Pinterest', '“Your pins” mosaic'],
    ])}
  </div>

  <!-- 7 READING -->
  <div class="comp blue" id="comp7">
    <div class="lhead">What you read</div>
    ${lrows([
      ['Safari saves', 'page image + domain; the lede is facts, not guilt — “12 saved this month · 4 older · oldest 4 months”'],
      ['RSS & Substack', 'the publisher’s own mark leads the row; “Your publications” leaderboard'],
      ['Readwise & Kindle', '“Most highlighted” by book'],
      ['Reddit', '“Your subreddits” ranked bars'],
    ])}
  </div>

  <!-- 8 NOTES & CHATS -->
  <div class="comp grn" id="comp8">
    <div class="lhead">Your own words</div>
    ${lrows([
      ['Notes, journals, AI chats', 'excerpt rows — title plus a body preview'],
      ['A pinned chat', 'becomes a free-standing takeaway card'],
      ['Year heatmaps', 'for journaling and for chats, same grammar as capture years'],
    ])}
  </div>

  <!-- 9 SOCIAL -->
  <div class="comp pink" id="comp9">
    <div class="lhead">Bluesky & Farcaster</div>
    ${lrows([
      ['Post cards', 'full text, unclamped — author face and handle, images at card width, never bundled or collapsed'],
      ['Context markers', 'the row says why it’s here — “Liked,” “Mentions you,” “/design”'],
      ['Thread walking', 'quote cards are recessed and tappable; replies and quotes push deeper, as far as the thread goes'],
      ['Profile cards', 'tap any face — avatar, bio, and a Watch verb; Farcaster adds “Watch their wallet”'],
    ])}
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, N=${BEATS.length}, OUT_AT=${OUT_AT};
const DUR=${JSON.stringify(durs)};
const START=${JSON.stringify(STARTS)};
const D=${JSON.stringify(DATA)};
window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];

function activeAt(t){ for(let i=N-1;i>=0;i--) if(t>=START[i]) return i; return 0; }
function staggerRows(sel,p,stagger,dur,dx){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*stagger)/dur);
    r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*(dx||-40))+'px)';
  });
}
function staggerPop(sel,p,stagger,dur){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*stagger)/dur);
    r.style.opacity=rp; r.style.transform='scale('+(0.6+0.4*back(rp))+')';
  });
}

window.seek=function(t){
  const active=activeAt(t);
  const bs=START[active], local=t-bs, dur=DUR[active], acc=D[active].accent;
  const pIn=clamp01((local-0.26)/Math.max(0.5,dur-0.45));

  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:START[k],c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=D[active].kick;
  wm.style.fontSize=Math.max(60,Math.min(320,900/(0.6*D[active].kick.length)))+'px';
  wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';

  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';

  const he=document.getElementById('head'); he.textContent=D[active].head;
  const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';

  comps.forEach((c,i)=>{
    const cbs=START[i], cl=t-cbs, cin=clamp01((cl-0.12)/0.6);
    const beatEnd=START[i]+DUR[i], outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=(1-back(cin))*180 + outp*200 + Math.sin(t*0.9+i)*5;
    const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;
    c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';
  });

  animateComp(active, pIn);

  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};

function animateComp(i,p){
  if(i===0) staggerRows('#comp0 .lrow', p, 0.15, 0.35, -40);
  else if(i===1) staggerRows('#comp1 .lrow', p, 0.12, 0.3, -40);
  else if(i===2){
    staggerPop('#comp2 .hc', p, 0.008, 0.3);
    staggerRows('#comp2 .boardrow', clamp01((p-0.55)/0.4), 0.12, 0.35, -30);
  }
  else if(i===3) staggerRows('#comp3 .lrow', p, 0.15, 0.35, -40);
  else if(i===4) staggerPop('#comp4 .pill', p, 0.08, 0.32);
  else if(i===5) staggerRows('#comp5 .lrow', p, 0.18, 0.4, -40);
  else if(i===6) staggerRows('#comp6 .lrow', p, 0.1, 0.28, -40);
  else if(i===7) staggerRows('#comp7 .lrow', p, 0.13, 0.32, -40);
  else if(i===8) staggerRows('#comp8 .lrow', p, 0.15, 0.35, -40);
  else if(i===9) staggerRows('#comp9 .lrow', p, 0.12, 0.3, -40);
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-media-live.html'), html);
console.log('wrote clip-media-live.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's', BEATS.length + ' beats');
