// Sizzle reel — EDITORIAL, no app screenshots: warm paper ground, oversized
// type, monospace masthead, diagonal colour wipes, hand-drawn UI. The five
// beats the app actually leads with:
//   0 APPS RAIN  — the catalog's icon rain (Design/BerryRain-adjacent onboarding
//                  rain, HowItWorksSheet.marqueeApps); brand colours are the
//                  REAL ones from website/styles.css .ai-<name> backgrounds.
//   1 ALL FEED   — the "All" source chip: every source in one feed, each row
//                  taking its content's shape (Screens/FeedScreen.swift).
//   2 SOURCE FEEDS — tap a chip and the feed narrows AND reshapes: Photos is a
//                  grid, Wallet is amounts, Calendar is a laid-out day. The
//                  crown pour follows the source's brand hue (Shell/SourceChips).
//   3 WALLET     — the combined portfolio treemap across chains (prd §155,
//                  Screens/WalletFeedTiles.swift) with its delta pill.
//   4 WHAT'S GOING ON — the agent bar's day brief (prd §166 Today brief,
//                  Model/TodayBrief.swift): ask in plain words, answered from
//                  your own things, with real drawn charts.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-sizzle-editorial.html --size=1080x1920
const fs = require('fs');

const BLUE = '#2E63FF', GREEN = '#3fb950', VIOLET = '#855dcd', TEAL = '#40c7c2';
const BEATS = [
  { kick: 'THE CATALOG',    head: 'Connect it once.\nIt keeps landing.', accent: BLUE },
  { kick: 'ONE FEED',       head: 'Everything,\nin one place.',          accent: BLUE },
  { kick: 'TAP A CHIP',     head: 'The feed takes\nits shape.',          accent: VIOLET },
  { kick: 'YOUR WALLETS',   head: 'Every chain,\none picture.',          accent: GREEN },
  { kick: "WHAT'S GOING ON", head: 'Just ask.\nIt already knows.',       accent: BLUE },
];
const INTRO = 0.45, BEAT = 3.0, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

// Real brand colours (website/styles.css .ai-*). White-mark brands get a
// readable dark chip so the rain doesn't blow out on the dark card.
const APPS = [
  ['Photos', 'conic-gradient(#ff453a,#ff9f0a,#ffd60a,#30d158,#64d2ff,#0a84ff,#bf5af2,#ff453a)'],
  ['Wallet', '#2962ef'], ['Farcaster', '#855dcd'], ['Bluesky', '#0085ff'],
  ['Spotify', '#1db954'], ['GitHub', '#24292f'], ['Reddit', '#ff4500'],
  ['YouTube', '#ff0000'], ['Claude', '#d97757'], ['Linear', '#5e6ad2'],
  ['Todoist', '#e44332'], ['Strava', '#fc4c02'], ['Twitch', '#9146ff'],
  ['RSS', '#f26522'], ['Kalshi', '#4fae7b'], ['Steam', '#1b2838'],
  ['Substack', '#ff6719'], ['Pinterest', '#e60023'], ['Raindrop', '#2f80ed'],
  ['Obsidian', '#7c3aed'], ['Coinbase', '#0052ff'], ['Telegram', '#229ed9'],
  ['OpenSea', '#2081e2'], ['Readwise', '#1e3a8a'], ['Calendly', '#006bff'],
];
const RAIN = APPS.map((a, i) => ({
  name: a[0], bg: a[1],
  col: i % 5,
  row: Math.floor(i / 5),
  delay: ((i * 7) % 25) * 0.032,
}));

// One feed, every source — each row a different shape.
const FEEDROWS = [
  { kind: 'social', src: 'Farcaster', c: '#855dcd', who: 'dwr.eth', t1: 78, t2: 52 },
  { kind: 'money',  src: 'Wallet',    c: '#2962ef', amt: '+0.42 ETH', usd: '$1,284.00' },
  { kind: 'photo',  src: 'Photos',    c: '#0a84ff', cap: 'Screenshot · 2:14pm' },
  { kind: 'event',  src: 'Calendar',  c: '#ff453a', time: '4:30', title: 'Design review' },
];

// Tap a chip — the shape the feed becomes.
const SHAPES = [
  { name: 'Photos',   c: '#0a84ff', kind: 'grid' },
  { name: 'Wallet',   c: '#2962ef', kind: 'money' },
  { name: 'Calendar', c: '#ff453a', kind: 'day' },
];
const CHIPS = [
  { n: 'All', c: 'rgba(255,255,255,.55)' },
  { n: 'Photos', c: '#0a84ff' },
  { n: 'Wallet', c: '#2962ef' },
  { n: 'Calendar', c: '#ff453a' },
];

// Combined portfolio treemap (proportional tiles, biggest first).
const TREE = [
  { s: 'ETH',  v: '$48.2k', x: 0,    y: 0,   w: 55, h: 100, c: '#4a63d8', f: 34 },
  { s: 'USDC', v: '$19.4k', x: 56.5, y: 0,   w: 43.5, h: 47, c: '#2775ca', f: 27 },
  { s: 'SOL',  v: '$11.1k', x: 56.5, y: 49,  w: 24,   h: 51, c: '#14f195', f: 23 },
  { s: 'WBTC', v: '$7.8k',  x: 81.5, y: 49,  w: 18.5, h: 30, c: '#f7931a', f: 19 },
  { s: '+12',  v: '',       x: 81.5, y: 81,  w: 18.5, h: 19, c: 'rgba(255,255,255,.14)', f: 17 },
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:104px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:790px;width:840px;height:880px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:46px;color:#fff;background:#0d0a16;}
/* the source-brand "crown pour" washing the top of the card, as in-app */
.pour{position:absolute;left:0;right:0;top:0;height:230px;will-change:background;pointer-events:none;}
.shd{position:absolute;top:46px;left:46px;right:46px;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);z-index:3;}
.body{position:absolute;left:46px;right:46px;top:110px;bottom:46px;z-index:2;}
.cap{position:absolute;left:46px;right:46px;bottom:40px;font-size:26px;font-weight:650;color:rgba(255,255,255,.72);text-align:center;line-height:1.42;z-index:3;}
.cap b{color:#fff;}
/* 0 — app rain into the catalog grid */
.grid{display:grid;grid-template-columns:repeat(5,1fr);gap:26px 24px;}
.tile{aspect-ratio:1;border-radius:26px;will-change:transform,opacity;box-shadow:0 10px 22px rgba(0,0,0,.35);}
/* 1 — all feed */
.chiprow{display:flex;gap:14px;margin-bottom:26px;}
.chip{padding:12px 22px;border-radius:100px;font-size:21px;font-weight:650;background:rgba(255,255,255,.08);color:rgba(255,255,255,.5);will-change:background,color;white-space:nowrap;}
.chip.on{color:#fff;}
.frow{display:flex;align-items:center;gap:18px;padding:17px 0;will-change:opacity,transform;}
.fdot{width:10px;height:10px;border-radius:50%;flex:none;}
.fav{width:56px;height:56px;border-radius:50%;background:rgba(255,255,255,.14);flex:none;}
.fthumb{width:56px;height:56px;border-radius:14px;flex:none;background:linear-gradient(140deg,#3a4a6b,#22304a);}
.fbar{height:13px;border-radius:7px;background:rgba(255,255,255,.22);}
.fbar.s{height:11px;background:rgba(255,255,255,.12);margin-top:8px;}
.fname{font-size:24px;font-weight:700;}
.famt{font-size:27px;font-weight:750;}
.fusd{font-size:20px;color:rgba(255,255,255,.42);margin-top:3px;}
.ftime{font-size:22px;font-weight:700;color:rgba(255,255,255,.55);width:66px;flex:none;}
.fttl{font-size:24px;font-weight:650;}
.fcap{font-size:21px;color:rgba(255,255,255,.5);}
.fsrc{margin-left:auto;font-size:19px;color:rgba(255,255,255,.35);font-weight:600;}
/* 2 — source shapes */
.pgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;}
.pcell{aspect-ratio:1;border-radius:18px;background:linear-gradient(140deg,#3a4a6b,#22304a);will-change:opacity,transform;}
.mrow{display:flex;align-items:center;justify-content:space-between;padding:20px 0;}
.dayrow{display:flex;align-items:center;gap:20px;padding:16px 0;}
.daybar{width:6px;height:44px;border-radius:4px;flex:none;}
/* 3 — treemap */
.tree{position:relative;height:390px;border-radius:20px;overflow:hidden;}
.tcell{position:absolute;border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;will-change:opacity,transform;box-shadow:inset 0 0 0 2px rgba(0,0,0,.18);}
.tcell b{font-weight:800;color:#fff;}
.tcell span{color:rgba(255,255,255,.8);margin-top:5px;font-weight:600;}
.total{display:flex;align-items:baseline;gap:18px;margin-bottom:24px;}
.total .n{font-size:56px;font-weight:800;letter-spacing:-.02em;}
.pill{font-size:22px;font-weight:750;padding:9px 18px;border-radius:100px;background:rgba(63,185,80,.18);color:${GREEN};}
/* 4 — agent */
.askbar{display:flex;align-items:center;gap:16px;background:rgba(255,255,255,.09);border-radius:100px;padding:20px 26px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.1);}
.askbar .q{font-size:26px;font-weight:600;color:#fff;}
.caret{width:3px;height:28px;background:${BLUE};display:inline-block;vertical-align:middle;will-change:opacity;}
.ans{margin-top:26px;background:rgba(255,255,255,.05);border-radius:22px;padding:28px;will-change:opacity,transform;}
.ansh{font-size:29px;font-weight:750;line-height:1.3;}
.ansrow{display:flex;align-items:center;gap:16px;margin-top:20px;will-change:opacity,transform;}
.ansrow .ic{width:44px;height:44px;border-radius:13px;flex:none;}
.ansrow .tx{font-size:22px;color:rgba(255,255,255,.72);font-weight:600;}
.spark{margin-top:22px;height:86px;position:relative;}
.badge{margin-top:20px;font-size:19px;color:rgba(255,255,255,.4);font-weight:600;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="pour" id="pour0"></div>
    <div class="shd mono">THE CATALOG</div>
    <div class="body"><div class="grid">
      ${RAIN.map((a,i)=>`<div class="tile" id="tile${i}" style="background:${a.bg}"></div>`).join('')}
    </div></div>
  </div>

  <div class="comp" id="comp1">
    <div class="pour" id="pour1"></div>
    <div class="shd mono">ALL SOURCES</div>
    <div class="body">
      <div class="chiprow">${CHIPS.map((c,i)=>`<div class="chip${i===0?' on':''}" style="${i===0?'background:rgba(255,255,255,.2)':''}">${c.n}</div>`).join('')}</div>
      <div class="frow" data-i="0"><span class="fav"></span><div style="flex:1"><div class="fbar" style="width:78%"></div><div class="fbar s" style="width:52%"></div></div><span class="fsrc">Farcaster</span></div>
      <div class="frow" data-i="1"><span class="fdot" style="background:#2962ef"></span><div style="flex:1"><div class="famt" style="color:${GREEN}">+0.42 ETH</div><div class="fusd">$1,284.00 · Base</div></div><span class="fsrc">Wallet</span></div>
      <div class="frow" data-i="2"><span class="fthumb"></span><div style="flex:1"><div class="fcap">Screenshot · 2:14pm</div><div class="fbar s" style="width:44%"></div></div><span class="fsrc">Photos</span></div>
      <div class="frow" data-i="3"><span class="ftime">4:30</span><span class="daybar" style="background:#ff453a"></span><div style="flex:1"><div class="fttl">Design review</div><div class="fbar s" style="width:38%"></div></div><span class="fsrc">Calendar</span></div>
    </div>
  </div>

  <div class="comp" id="comp2">
    <div class="pour" id="pour2"></div>
    <div class="shd mono" id="shd2">PHOTOS</div>
    <div class="body">
      <div class="chiprow" id="chips2">${CHIPS.map((c,i)=>`<div class="chip" id="c2_${i}">${c.n}</div>`).join('')}</div>
      <div id="shape_grid"><div class="pgrid">${Array.from({length:6}).map((_,i)=>`<div class="pcell" id="pc${i}"></div>`).join('')}</div></div>
      <div id="shape_money" style="display:none">
        ${[['+0.42 ETH','$1,284.00','Base'],['−120 USDC','$120.00','Arbitrum'],['+1.9 SOL','$402.10','Solana']].map(r=>`<div class="mrow"><div><div class="famt">${r[0]}</div><div class="fusd">${r[2]}</div></div><div class="famt" style="font-size:24px;color:rgba(255,255,255,.6)">${r[1]}</div></div>`).join('')}
      </div>
      <div id="shape_day" style="display:none">
        ${[['9:00','Standup'],['11:30','1:1 with Sam'],['4:30','Design review'],['7:00','Dinner — Nari']].map(r=>`<div class="dayrow"><span class="ftime">${r[0]}</span><span class="daybar" style="background:#ff453a"></span><span class="fttl">${r[1]}</span></div>`).join('')}
      </div>
    </div>
  </div>

  <div class="comp" id="comp3">
    <div class="pour" id="pour3"></div>
    <div class="shd mono">COMBINED PORTFOLIO · 5 CHAINS</div>
    <div class="body">
      <div class="total"><span class="n" id="wtotal">$86,512</span><span class="pill" id="wpill">▲ 2.4%</span></div>
      <div class="tree">
        ${TREE.map((c,i)=>`<div class="tcell" id="tc${i}" style="left:${c.x}%;top:${c.y}%;width:${c.w}%;height:${c.h}%;background:${c.c}"><b style="font-size:${c.f}px">${c.s}</b>${c.v?`<span style="font-size:${Math.round(c.f*0.62)}px">${c.v}</span>`:''}</div>`).join('')}
      </div>
      <div class="cap" style="position:static;margin-top:26px">Ethereum · Base · Arbitrum · Solana · Polygon<br><b>Read-only. Watching can never move funds.</b></div>
    </div>
  </div>

  <div class="comp" id="comp4">
    <div class="pour" id="pour4"></div>
    <div class="shd mono">THE AGENT</div>
    <div class="body">
      <div class="askbar"><span class="q" id="askq"></span><span class="caret" id="caret"></span></div>
      <div class="ans" id="ans">
        <div class="ansh">Quiet morning — <b>14 new things</b> landed, and your wallets are up 2.4%.</div>
        <div class="ansrow" data-i="0"><span class="ic" style="background:#2962ef"></span><span class="tx">ETH did the lifting · +$1,284</span></div>
        <div class="ansrow" data-i="1"><span class="ic" style="background:#ff453a"></span><span class="tx">Design review at 4:30</span></div>
        <div class="ansrow" data-i="2"><span class="ic" style="background:#855dcd"></span><span class="tx">6 casts from people you follow</span></div>
        <div class="spark"><svg width="100%" height="86" viewBox="0 0 640 86" preserveAspectRatio="none"><path id="sparkpath" d="M0 66 L80 58 L160 62 L240 44 L320 48 L400 30 L480 34 L560 18 L640 12" fill="none" stroke="${GREEN}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg></div>
        <div class="badge" id="badge">Written on this iPhone, from your own things</div>
      </div>
    </div>
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
const RAIN=${JSON.stringify(RAIN)},SHAPES=${JSON.stringify(SHAPES)},CHIPS=${JSON.stringify(CHIPS)};
const comps=[...document.querySelectorAll('.comp')];
const ASKQ="What's going on?";
function pour(id,hue,amt){document.getElementById(id).style.background='linear-gradient(to bottom, '+hue+' 0%, rgba(0,0,0,0) 100%)';document.getElementById(id).style.opacity=amt;}
function stagRows(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
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
  if(i===0){
    pour('pour0','rgba(46,99,255,.28)',1);
    // every tile RAINS down into its catalog slot, each on its own beat
    RAIN.forEach((a,k)=>{
      const el=document.getElementById('tile'+k);
      const rp=clamp01((local-0.18-a.delay)/0.62);
      el.style.opacity=clamp01(rp*2.4);
      el.style.transform='translateY('+((1-back(rp))*-330)+'px) rotate('+((1-rp)*-14)+'deg)';
    });
  } else if(i===1){
    pour('pour1','rgba(46,99,255,.24)',1);
    document.querySelector('#comp1 .chiprow').style.opacity=clamp01((p-0.02)/0.2);
    stagRows('#comp1 .frow',clamp01((p-0.12)/0.88),0.15,0.32,26);
  } else if(i===2){
    // cycle Photos -> Wallet -> Calendar; chip, pour, eyebrow and SHAPE change
    const cyc=clamp01((p-0.06)/0.9);
    const idx=Math.min(SHAPES.length-1,Math.floor(cyc*SHAPES.length*0.999));
    const s=SHAPES[idx];
    pour('pour2',hexA(s.c,.32),1);
    document.getElementById('shd2').textContent=s.name.toUpperCase();
    CHIPS.forEach((c,k)=>{const el=document.getElementById('c2_'+k);const on=(c.n===s.name);el.style.background=on?hexA(s.c,.9):'rgba(255,255,255,.08)';el.style.color=on?'#fff':'rgba(255,255,255,.5)';});
    ['grid','money','day'].forEach(kind=>{document.getElementById('shape_'+kind).style.display=(kind===s.kind)?'block':'none';});
    // the newly-shown shape springs in on each switch
    const localIn=clamp01((cyc*SHAPES.length)%1/0.4);
    if(s.kind==='grid'){document.querySelectorAll('#comp2 .pcell').forEach((c,k)=>{const rp=clamp01((localIn-k*0.06)/0.4);c.style.opacity=rp;c.style.transform='scale('+(0.82+0.18*back(rp))+')';});}
    else {document.querySelectorAll('#shape_'+s.kind+' > div').forEach((c,k)=>{const rp=clamp01((localIn-k*0.09)/0.4);c.style.opacity=rp;c.style.transform='translateY('+((1-back(rp))*18)+'px)';});}
  } else if(i===3){
    pour('pour3','rgba(63,185,80,.22)',1);
    document.querySelector('#comp3 .total').style.opacity=clamp01((p-0.02)/0.22);
    document.getElementById('wpill').style.opacity=clamp01((p-0.28)/0.2);
    document.querySelectorAll('#comp3 .tcell').forEach((c,k)=>{const rp=clamp01((p-0.12-k*0.09)/0.34);c.style.opacity=rp;c.style.transform='scale('+(0.72+0.28*back(rp))+')';});
    document.querySelector('#comp3 .cap').style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===4){
    pour('pour4','rgba(46,99,255,.24)',1);
    document.querySelector('#comp4 .askbar').style.opacity=clamp01((p-0.02)/0.16);
    const chars=Math.round(clamp01((p-0.06)/0.34)*ASKQ.length);
    document.getElementById('askq').textContent=ASKQ.slice(0,chars);
    document.getElementById('caret').style.opacity=(chars<ASKQ.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    const ap=clamp01((p-0.42)/0.3);
    const ans=document.getElementById('ans');ans.style.opacity=ap;ans.style.transform='translateY('+((1-back(ap))*24)+'px)';
    stagRows('#comp4 .ansrow',clamp01((p-0.5)/0.5),0.13,0.3,16);
    const sp=clamp01((p-0.66)/0.28);
    const path=document.getElementById('sparkpath');const L=path.getTotalLength();
    path.style.strokeDasharray=L;path.style.strokeDashoffset=L*(1-easeOut(sp));
    document.getElementById('badge').style.opacity=clamp01((p-0.82)/0.18);
  }
}
function hexA(hex,a){const h=hex.replace('#','');const r=parseInt(h.slice(0,2),16),g=parseInt(h.slice(2,4),16),b=parseInt(h.slice(4,6),16);return 'rgba('+r+','+g+','+b+','+a+')';}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(require('path').join(__dirname,'clip-sizzle-editorial.html'),html);
console.log('wrote clip-sizzle-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
