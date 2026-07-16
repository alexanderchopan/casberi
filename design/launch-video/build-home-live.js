// Home promo — live-animated UI (no screenshots) in the editorial frame.
// Finale: ask-your-things answer streaming in. node render.js clip-home-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const RED = '#E8452B';
const P = { fc:'#7C4DEC', wl:'#2E63FF', gh:'#2DA44E', cal:'#E8452B', gpt:'#10A37F', ph:'#F5A524', bs:'#1D9BF0', rm:'#F5A524', nt:'#E3B341', mu:'#EC4899' };
const BEATS = [
  { kick: 'ONE FEED', head: 'Everything,\none feed.',  accent: RED },
  { kick: 'TODAY',    head: 'Your day at\na glance.',   accent: RED },
  { kick: 'PINNED',   head: 'Pin what\nmatters.',       accent: RED },
  { kick: 'SOURCES',  head: '40+ apps\nland here.',     accent: RED },
  { kick: 'ASK',      head: 'Ask your\nthings.',        accent: RED },
];
const INTRO = 0.45, BEAT = 1.95;
const OUT_AT = INTRO + BEATS.length * BEAT;
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map((b, i) => ({ kick: (i + 1 < 10 ? '0' : '') + (i + 1) + ' · ' + b.kick, head: b.head, accent: b.accent }));
const ASSETS = '/Users/alexanderchopan/Developer/casberi/Casberi/Casberi/Assets.xcassets';
const icon = n => 'data:image/png;base64,' + fs.readFileSync(path.join(ASSETS, 'brand-' + n + '.imageset', 'icon.png')).toString('base64');
const ICONS = ['farcaster','github','chatgpt','claude','bluesky','notion','reddit','spotify','youtube','x','gmail','strava'];

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:560px;line-height:.8;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#111015;}

/* feed rows */
.frow{display:flex;align-items:center;gap:26px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:transform,opacity;}
.frow:first-of-type{border-top:none;}
.fi{width:64px;height:64px;border-radius:17px;flex:none;display:flex;align-items:center;justify-content:center;font-size:30px;color:#fff;font-weight:700;}
.ft{font-size:39px;font-weight:600;line-height:1.15;}
.fm{font-size:26px;color:rgba(255,255,255,.5);margin-top:6px;}

/* today: stat chips + coming up */
.chips{display:flex;gap:20px;flex-wrap:wrap;}
.chip{font-size:32px;font-weight:600;padding:20px 32px;border-radius:100px;will-change:opacity,transform;}
.cu{margin-top:44px;}
.cuh{font-size:30px;color:rgba(255,255,255,.5);letter-spacing:.06em;margin-bottom:20px;}
.curow{display:flex;justify-content:space-between;align-items:center;padding:22px 0;font-size:36px;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.cutag{font-size:26px;padding:8px 22px;border-radius:100px;font-weight:600;}

/* pinned */
.pgrid{display:grid;grid-template-columns:1fr 1fr;gap:26px;}
.pcard{background:#0a0a0f;border-radius:24px;padding:30px;height:300px;position:relative;will-change:opacity,transform;box-shadow:inset 0 0 0 1px rgba(255,255,255,.06);}
.pcard .ph{font-size:30px;font-weight:650;margin-bottom:20px;}
.ptreemap{display:grid;grid-template-columns:repeat(3,1fr);grid-template-rows:repeat(2,1fr);gap:12px;height:180px;}
.ptile{background:#1a2a55;border-radius:14px;display:flex;align-items:flex-end;padding:14px;font-size:24px;font-weight:600;}
.pin{position:absolute;top:26px;right:26px;font-size:28px;opacity:.5;}
.pline{height:24px;border-radius:8px;background:rgba(255,255,255,.08);margin-bottom:16px;}

/* sources grid */
.sgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:30px;margin-top:6px;}
.stile{aspect-ratio:1;border-radius:30px;overflow:hidden;will-change:opacity,transform;box-shadow:0 12px 30px rgba(0,0,0,.4);}
.stile img{width:100%;height:100%;display:block;}

/* ask */
.abar{display:flex;align-items:center;gap:22px;background:#0a0a0f;border:2px solid rgba(255,255,255,.12);border-radius:26px;padding:30px 34px;font-size:38px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.03);}
.aspark{color:${RED};font-size:40px;}
.acaret{display:inline-block;width:4px;height:40px;background:#fff;vertical-align:-6px;margin-left:3px;}
.aans{margin-top:40px;font-size:40px;line-height:1.4;color:#fff;font-weight:500;}
.aans b{color:${RED};}
.acite{margin-top:30px;display:flex;gap:14px;}
.acite span{font-size:24px;padding:10px 22px;border-radius:100px;font-weight:600;will-change:opacity,transform;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:${RED};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>HOME</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="frow" data-i="0"><div class="fi" style="background:${P.fc}">◈</div><div><div class="ft">One thing I find striking in the discourse…</div><div class="fm">Farcaster · vitalik.eth · 4d</div></div></div>
    <div class="frow" data-i="1"><div class="fi" style="background:${P.wl}">▦</div><div><div class="ft">Sent 14.86 USDT</div><div class="fm">Wallet · 0xfc6d…e8ad · 5m</div></div></div>
    <div class="frow" data-i="2"><div class="fi" style="background:${P.gh}">⌥</div><div><div class="ft">PR #142 · token layer</div><div class="fm">GitHub · casberi/casberi · 1h</div></div></div>
    <div class="frow" data-i="3"><div class="fi" style="background:${P.cal}">▤</div><div><div class="ft">Evening run</div><div class="fm">Calendar · today · 6:00 PM</div></div></div>
  </div>

  <div class="comp" id="comp1">
    <div class="chips">
      <div class="chip c" data-v="177" data-s="chats" style="background:#2b1740;color:#c9a6ff"></div>
      <div class="chip c" data-v="6" data-s="events" style="background:#3a1712;color:#ff9d86"></div>
      <div class="chip c" data-v="24" data-s="links" style="background:#0d2340;color:#7fb0ff"></div>
      <div class="chip c" data-v="4" data-s="reminders" style="background:#3a2c0d;color:#f5cf6b"></div>
    </div>
    <div class="cu">
      <div class="cuh mono">COMING UP</div>
      <div class="curow" data-i="0"><span>Book dentist</span><span class="cutag" style="background:#3a1712;color:#ff9d86">overdue</span></div>
      <div class="curow" data-i="1"><span>Evening run</span><span class="cutag" style="background:#12331f;color:#7fe0a0">today</span></div>
      <div class="curow" data-i="2"><span>Design review</span><span class="cutag" style="background:rgba(255,255,255,.08);color:rgba(255,255,255,.6)">tomorrow</span></div>
    </div>
  </div>

  <div class="comp" id="comp2">
    <div class="pgrid">
      <div class="pcard" data-i="0"><div class="ph">Wallet <span class="pin">📌</span></div><div class="ptreemap"><div class="ptile" style="grid-area:1/1/3/2">ETH</div><div class="ptile">AWETH</div><div class="ptile">WBTC</div><div class="ptile" style="grid-area:2/2/3/4">WETH</div></div></div>
      <div class="pcard" data-i="1"><div class="ph">Recent posts <span class="pin">📌</span></div><div class="pline" style="width:90%"></div><div class="pline" style="width:75%"></div><div class="pline" style="width:85%"></div><div class="pline" style="width:60%"></div></div>
    </div>
  </div>

  <div class="comp" id="comp3">
    <div class="sgrid">${ICONS.map((n,i)=>`<div class="stile" data-i="${i}"><img src="${icon(n)}"></div>`).join('')}</div>
  </div>

  <div class="comp" id="comp4">
    <div class="abar"><span class="aspark">✦</span><span id="aq"></span><span class="acaret" id="acaret"></span></div>
    <div class="aans" id="aans"></div>
    <div class="acite" id="acite"><span style="background:${P.fc}33;color:#c9a6ff">Farcaster</span><span style="background:${P.wl}33;color:#7fb0ff">Wallet</span><span style="background:${P.gh}33;color:#7fe0a0">GitHub</span></div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span id="pg">01 / 05</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b> · free on TestFlight</div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, BEAT=${BEAT}, OUT_AT=${OUT_AT}, N=${BEATS.length};
const D=${JSON.stringify(DATA)};
window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
const AQ='What did I save about Base?';
const AANS='6 things — a cast from vitalik.eth, three wallet moves, and a merged PR.'.split(' ');

window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent;
  const pIn=clamp01((local-0.28)/1.3);

  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:INTRO+k*BEAT,c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=(active+1<10?'0':'')+(active+1);
  wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head'); he.textContent=D[active].head;
  const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  document.getElementById('pg').textContent=(active+1<10?'0':'')+(active+1)+' / 0'+N;

  comps.forEach((c,i)=>{
    const cbs=INTRO+i*BEAT, cl=t-cbs, cin=clamp01((cl-0.12)/0.6);
    const beatEnd=INTRO+(i+1)*BEAT, outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;
    const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;
    c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';
  });
  animateComp(active, pIn, t);

  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};

function stagger(sel,p,step,dur,rise){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*step)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*(rise||24))+'px)';});}
function animateComp(i,p,t){
  if(i===0){ stagger('#comp0 .frow',p,0.14,0.4,26); }
  else if(i===1){
    document.querySelectorAll('#comp1 .chip').forEach((c,k)=>{
      const cp=clamp01((p-k*0.1)/0.4); c.style.opacity=cp; c.style.transform='scale('+(0.85+0.15*back(cp))+')';
      c.textContent=Math.round((+c.dataset.v)*easeOut(cp))+' '+c.dataset.s;
    });
    stagger('#comp1 .curow',p-0.25,0.12,0.3,18);
  }
  else if(i===2){ document.querySelectorAll('#comp2 .pcard').forEach((c,k)=>{const cp=clamp01((p-k*0.18)/0.5);c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*40)+'px) scale('+(0.92+0.08*easeOut(cp))+')';}); }
  else if(i===3){ document.querySelectorAll('#comp3 .stile').forEach((s,k)=>{const cp=clamp01((p-k*0.05)/0.35);s.style.opacity=cp;s.style.transform='scale('+(0.4+0.6*back(cp))+')';}); }
  else if(i===4){
    const qn=Math.round(AQ.length*clamp01(p/0.35)); document.getElementById('aq').textContent=AQ.slice(0,qn);
    document.getElementById('acaret').style.opacity=(p<0.4&&Math.floor(t*2)%2)?1:0;
    // answer streams word by word after the question
    const ap=clamp01((p-0.42)/0.42); const nw=Math.round(AANS.length*ap);
    const ans=AANS.slice(0,nw).join(' ');
    document.getElementById('aans').innerHTML=ans.replace('vitalik.eth','<b>vitalik.eth</b>').replace('PR','<b>PR</b>');
    document.querySelectorAll('#comp4 .acite span').forEach((s,k)=>{const cp=clamp01((p-0.86-k*0.05)/0.14);s.style.opacity=cp;s.style.transform='translateY('+((1-easeOut(cp))*12)+'px)';});
  }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-home-live.html'), html);
console.log('wrote clip-home-live.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
