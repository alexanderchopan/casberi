// Small delights promo — EDITORIAL, no app screenshots at all: warm paper
// ground, oversized black type, monospace masthead + index numbers, diagonal
// colour wipes between beats, hand-drawn (not captured) UI objects. Grounded
// directly in source, not invented:
//   1. Chip coin-flip — Design/CoinFlip.swift: a source chip's icon does ONE
//      full 3D rotation about the horizontal (X) axis (never a flat z-spin),
//      spring(response:.5, damping:.85) — decelerates smoothly into rest.
//      Fires on the chip you're leaving AND the one you're landing on
//      (Shell/SourceChips.swift).
//   2. Pull-to-refresh — Design/BerryRain.swift + TopDoors.swift DoorSpin:
//      ~16 small solid circles fall from the top in the app's blues (or the
//      open source's own brand hue), staggered, drifting, fading out; the
//      avatar icon (leftmost chip) does one full 360° spin at the same time.
//   3. Crown pour — Design/ThemeStore.swift + Shell/MainSurface.swift: a
//      soft gradient wash behind the chip strip in a user-picked, PERSISTENT
//      hue — 5 curated options (Blue/Teal/Violet/Magenta/Slate), chosen once
//      in Settings, not a per-source tint.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-delight-editorial.html --size=1080x1920
const fs = require('fs');

const BLUE = '#1673e6', TEAL = '#40c7c2', VIOLET = '#8c40c7', MAGENTA = '#c74095', SLATE = '#7b8a9e';
const BERRY = ['#0a84ff', '#3f9fff', '#1266c4'];
const HUES = [
  { name: 'Blue', color: BLUE }, { name: 'Teal', color: TEAL }, { name: 'Violet', color: VIOLET },
  { name: 'Magenta', color: MAGENTA }, { name: 'Slate', color: SLATE },
];
const CHIPS = [
  { name: 'You', color: 'rgba(255,255,255,.5)', avatar: true },
  { name: 'Wallet', color: BLUE },
  { name: 'Farcaster', color: VIOLET },
  { name: 'Calendar', color: '#FF3B30' },
  { name: 'Photos', color: TEAL },
];

const BEATS = [
  { kick: 'SWITCH SOURCES', head: 'A chip flips\nlike a coin.',       accent: BLUE },
  { kick: 'PULL TO REFRESH', head: 'A good refresh\ndrops a berry.',  accent: '#0a84ff' },
  { kick: 'YOUR COLOR',     head: 'Pick a hue —\nit pours over.',     accent: VIOLET },
];
const INTRO = 0.45, BEAT = 2.7, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const BERRY_N = 16;
const berries = Array.from({ length: BERRY_N }, (_, i) => ({
  x: 6 + (i * 97) % 88,
  delay: (i * 0.091) % 0.9,
  dur: 0.9 + ((i * 53) % 50) / 100,
  size: 8 + (i * 37) % 13,
  drift: ((i % 2 === 0) ? 1 : -1) * (6 + (i * 13) % 18),
  color: BERRY[i % BERRY.length],
}));

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:108px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:36px;}
/* beat 0 — chip strip coin flip */
.chipstrip{display:flex;gap:22px;align-items:center;justify-content:center;padding:70px 0 40px;perspective:900px;}
.chipwrap{display:flex;flex-direction:column;align-items:center;gap:16px;}
.chip{width:112px;height:112px;border-radius:50%;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,.08);will-change:transform,background;}
.chip svg{width:44px;height:44px;}
.chipnm{font-size:22px;color:rgba(255,255,255,.45);font-weight:600;}
.fliplabel{margin-top:44px;font-size:29px;font-weight:650;color:rgba(255,255,255,.8);text-align:center;}
/* beat 1 — berry rain + avatar spin */
.refreshstage{position:relative;height:560px;border-radius:24px;background:rgba(255,255,255,.03);overflow:hidden;}
.avatarrow{position:absolute;top:26px;left:26px;right:26px;display:flex;align-items:center;gap:16px;z-index:2;}
.avatarspin{width:72px;height:72px;border-radius:50%;background:rgba(255,255,255,.9);display:flex;align-items:center;justify-content:center;will-change:transform;}
.avatarspin svg{width:34px;height:34px;}
.pulltext{font-size:26px;color:rgba(255,255,255,.4);font-weight:600;}
.berry{position:absolute;border-radius:50%;will-change:transform,opacity;}
.refreshlabel{margin-top:36px;font-size:29px;font-weight:650;color:rgba(255,255,255,.8);text-align:center;}
/* beat 2 — crown pour */
.pourcard{position:relative;border-radius:28px;overflow:hidden;background:rgba(255,255,255,.03);height:520px;}
.pourwash{position:absolute;inset:0;will-change:background;}
.pourchips{position:absolute;top:34px;left:34px;right:34px;display:flex;gap:14px;}
.pourchip{width:64px;height:64px;border-radius:50%;background:rgba(255,255,255,.14);}
.colordots{position:absolute;bottom:36px;left:0;right:0;display:flex;justify-content:center;gap:22px;}
.dot2{width:46px;height:46px;border-radius:50%;will-change:box-shadow;}
.pourlabel{margin-top:36px;font-size:29px;font-weight:650;color:rgba(255,255,255,.8);text-align:center;}
.pourlabel b{color:#fff;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>DELIGHT</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">SWITCH SOURCES</div>
    <div class="chipstrip" id="chipstrip">${CHIPS.map((c, i) => `<div class="chipwrap"><div class="chip" id="chip${i}" data-i="${i}" style="background:${c.avatar ? 'rgba(255,255,255,.9)' : 'rgba(255,255,255,.08)'}">${c.avatar ? `<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="#14110d"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="#14110d"/></svg>` : `<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7" fill="${c.color}"/></svg>`}</div><div class="chipnm">${c.name}</div></div>`).join('')}</div>
    <div class="fliplabel" id="fliplabel">One flips like a coin —<br>the one you're leaving, and the one you land on.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">PULL TO REFRESH</div>
    <div class="refreshstage" id="refreshstage">
      <div class="avatarrow"><div class="avatarspin" id="avatarspin"><svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="#14110d"/><path d="M4 20c0-4 3.6-6 8-6s8 2 8 6" fill="#14110d"/></svg></div><span class="pulltext">Refreshing your feed…</span></div>
      ${berries.map((b, i) => `<div class="berry" id="berry${i}" style="left:${b.x}%;width:${b.size}px;height:${b.size}px;background:${b.color}"></div>`).join('')}
    </div>
    <div class="refreshlabel">A good refresh<br>drops a berry or two.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">YOUR COLOR</div>
    <div class="pourcard">
      <div class="pourwash" id="pourwash"></div>
      <div class="pourchips">${CHIPS.map(c => `<div class="pourchip"></div>`).join('')}</div>
      <div class="colordots">${HUES.map((h, i) => `<div class="dot2" id="dot${i}" style="background:${h.color}"></div>`).join('')}</div>
    </div>
    <div class="pourlabel" id="pourlabel">Pick a hue in Settings —<br><b>it pours over your whole feed.</b></div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),easeIn=p=>p*p;
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const HUES=${JSON.stringify(HUES)}, BERRIES=${JSON.stringify(berries)};
const comps=[...document.querySelectorAll('.comp')];
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.5);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(60,Math.min(320,900/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);const back=p=>{const cc=1.7;return 1+(cc+1)*Math.pow(p-1,3)+cc*Math.pow(p-1,2);};let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  if(i===0){
    // two chips (Wallet=1, Farcaster=2) coin-flip on the X axis; Farcaster ends active/colored.
    const flipP = clamp01((local-0.35)/0.85);
    const angle = 360*easeOut(flipP);
    [1,2].forEach(idx=>{ const el=document.getElementById('chip'+idx); el.style.transform='rotateX('+angle+'deg)'; });
    const landed = flipP>0.96;
    document.getElementById('chip2').style.background = landed ? '${VIOLET}' : 'rgba(255,255,255,.08)';
    document.getElementById('chip1').style.background = 'rgba(255,255,255,.08)';
    document.getElementById('fliplabel').style.opacity=clamp01((p-0.05)/0.3);
    document.getElementById('chipstrip').style.opacity=clamp01((p-0.02)/0.2);
  } else if(i===1){
    document.getElementById('refreshstage').style.opacity=clamp01((p-0.02)/0.2);
    const spinP=clamp01((local-0.2)/0.7);
    document.getElementById('avatarspin').style.transform='rotate('+(360*easeOut(spinP))+'deg)';
    BERRIES.forEach((b,k)=>{
      const el=document.getElementById('berry'+k);
      const bl = clamp01((local - 0.15 - b.delay)/b.dur);
      const y = -20 + bl*580;
      const x = Math.sin(bl*Math.PI)*b.drift;
      const op = bl<=0?0:(bl>=1?0:(bl<0.85?1:1-((bl-0.85)/0.15)));
      el.style.transform='translate('+x+'px,'+y+'px)';
      el.style.opacity=op;
    });
    document.querySelector('#comp1 .refreshlabel').style.opacity=clamp01((p-0.1)/0.3);
  } else if(i===2){
    document.querySelector('#comp2 .pourcard').style.opacity=clamp01((p-0.02)/0.2);
    const cyc=clamp01((p-0.1)/0.85);
    const idx=Math.min(HUES.length-1,Math.floor(cyc*HUES.length*0.999));
    const hue=HUES[idx].color;
    document.getElementById('pourwash').style.background='linear-gradient(to bottom, '+hue+' 0%, rgba(0,0,0,0) 62%)';
    document.getElementById('pourwash').style.opacity=0.4;
    HUES.forEach((h,k)=>{ const d=document.getElementById('dot'+k); d.style.boxShadow = (k===idx) ? '0 0 0 6px rgba(255,255,255,.35)' : 'none'; });
    document.getElementById('pourlabel').style.opacity=clamp01((p-0.15)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(require('path').join(__dirname, 'clip-delight-editorial.html'), html);
console.log('wrote clip-delight-editorial.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
