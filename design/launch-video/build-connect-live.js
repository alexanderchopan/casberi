// "Getting started / Just connect" opener — editorial, live-animated.
// node render.js clip-connect-live.html --size=1080x1920
// Replaces the old sim-recorded clip1 (OpenSea-first, onchain-heavy). Arc:
//   onboarding icon RAIN -> the CATALOG -> connect a FEW (Wallet, GitHub, Spotify)
//   -> the feed FILLS with a varied mix (dev / music / photos / onchain / social).
// Real brand logos inlined from Assets.xcassets/brand-*; Apple apps drawn as
// iOS-style tiles. Deliberately varied so it doesn't read as an onchain app.
const fs=require('fs'), path=require('path');
const AX='/Users/alexanderchopan/Developer/casberi/Casberi/Casberi/Assets.xcassets';
const ic=n=>'data:image/png;base64,'+fs.readFileSync(path.join(AX,'brand-'+n+'.imageset','icon.png')).toString('base64');
const AC='#2E63FF', GRN='#3fb950';
const BEATS=[
  {kick:'START',   head:'Start with\nwhat you use.', accent:AC},
  {kick:'CATALOG', head:'Open the\ncatalog.',        accent:AC},
  {kick:'CONNECT', head:'Connect\na few.',           accent:AC},
  {kick:'LANDS',   head:'It fills\nyour feed.',      accent:AC},
  {kick:'YOURS',   head:'One feed.\nAll yours.',     accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
// the onboarding rain — real brand logos + a few drawn Apple tiles, varied
const RAIN=['github','spotify','farcaster','gmail','claude','chatgpt','notion','strava','bluesky','reddit','youtube','linear','geckoterminal','todoist'];
// connect rows: [label, sub, kind] — kind picks the icon treatment
const CONNECT=[
  ['Wallet','Watch an address','wallet'],
  ['GitHub','Stars, releases, issues','github'],
  ['Spotify','Liked songs','spotify'],
  ['Photos','Screenshots, readable','photos'],
];
// the varied feed — dev / music / photos / onchain / social (NOT onchain-heavy)
const FEED=[
  ['github','GitHub','Released v2.1.0 · react'],
  ['spotify','Spotify','Nights — Frank Ocean'],
  ['photos','Screenshot','Chili oil noodles — recipe'],
  ['wallet','Wallet','Bought 25 USDC with Venmo'],
  ['farcaster','Farcaster','vitalik.eth · One thing I find striking…'],
];

const html=`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:124px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0b0d12;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;}
/* rain */
.rain{position:absolute;inset:0;overflow:hidden;}
.rtile{position:absolute;width:96px;height:96px;border-radius:24px;overflow:hidden;box-shadow:0 10px 24px rgba(0,0,0,.4);will-change:transform,opacity;}
.rtile img{width:100%;height:100%;object-fit:cover;display:block;}
.tile-photos{background:#fff;position:relative;}
.tile-photos::before{content:"";position:absolute;inset:20px;border-radius:50%;background:conic-gradient(#f24d4d,#f2a33c,#f2e23c,#4dd07a,#3ca0f2,#a24df2,#f24d4d);}
.tile-cal{background:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;}
.tile-cal b{color:#ff3b30;font-size:20px;font-weight:800;letter-spacing:.06em;margin-top:8px;}
.tile-cal i{color:#111;font-size:44px;font-weight:800;font-style:normal;line-height:.9;}
.tile-health{background:#fff;display:flex;align-items:center;justify-content:center;color:#fc2c55;font-size:52px;}
.tile-music{background:linear-gradient(160deg,#fb5c74,#fa2f52);display:flex;align-items:center;justify-content:center;color:#fff;font-size:50px;}
.tile-wallet{background:linear-gradient(160deg,#2E63FF,#1b3fc4);display:flex;align-items:center;justify-content:center;}
.tile-wallet svg{width:52px;height:52px;fill:none;stroke:#fff;stroke-width:2.2;}
/* catalog */
.cchips{display:flex;gap:16px;margin-bottom:30px;flex-wrap:wrap;}
.cchip{font-size:26px;font-weight:600;padding:14px 28px;border-radius:100px;background:rgba(255,255,255,.08);color:rgba(255,255,255,.6);will-change:opacity,transform;}
.cchip.on{background:${AC};color:#fff;}
.crow,.orow{display:flex;align-items:center;gap:24px;padding:24px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.crow:first-of-type,.orow:first-of-type{border-top:none;}
.cico{width:76px;height:76px;border-radius:18px;overflow:hidden;flex:none;box-shadow:0 6px 16px rgba(0,0,0,.35);}
.cico img{width:100%;height:100%;object-fit:cover;display:block;}
.cn{font-size:36px;font-weight:650;} .csub{font-size:24px;color:rgba(255,255,255,.45);margin-top:4px;}
.connect{margin-left:auto;flex:none;font-size:27px;font-weight:700;padding:14px 34px;border-radius:100px;background:${AC};color:#fff;will-change:background,color,transform;}
.connect.done{background:rgba(63,185,80,.18);color:${GRN};}
/* feed */
.fdot{width:16px;height:16px;border-radius:50%;flex:none;}
.fsrc{font-size:22px;letter-spacing:.06em;color:rgba(255,255,255,.45);width:200px;flex:none;}
.ftx{font-size:31px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.frow{display:flex;align-items:center;gap:22px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.frow:first-of-type{border-top:none;}
.ynote{margin-top:34px;font-size:28px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.ynote b{color:#fff;}
/* yours */
.ybig{display:flex;align-items:center;gap:22px;margin-top:8px;will-change:opacity,transform;}
.ybig i{width:64px;height:64px;border-radius:50%;flex:none;background:rgba(63,185,80,.16);color:${GRN};display:flex;align-items:center;justify-content:center;font-style:normal;font-size:34px;font-weight:800;}
.ybig span{font-size:38px;font-weight:650;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>GETTING STARTED</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="rain" id="rain">
      ${RAIN.map((n,i)=>`<div class="rtile" data-i="${i}"><img src="${ic(n)}"></div>`).join('')}
      <div class="rtile tile-photos" data-i="${RAIN.length}"></div>
      <div class="rtile tile-cal" data-i="${RAIN.length+1}"><b>THU</b><i>16</i></div>
      <div class="rtile tile-health" data-i="${RAIN.length+2}">♥</div>
      <div class="rtile tile-music" data-i="${RAIN.length+3}">♪</div>
    </div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">THE CATALOG</div>
    <div class="cchips">
      <span class="cchip on" data-i="0">Onchain</span><span class="cchip" data-i="1">Life</span><span class="cchip" data-i="2">Social</span><span class="cchip" data-i="3">Work</span><span class="cchip" data-i="4">Media</span>
    </div>
    <div class="crow" data-i="0"><span class="cico"><img src="${ic('github')}"></span><div><div class="cn">GitHub</div><div class="csub">Stars, releases, issues</div></div><span class="connect">Connect</span></div>
    <div class="crow" data-i="1"><span class="cico"><img src="${ic('spotify')}"></span><div><div class="cn">Spotify</div><div class="csub">Liked songs</div></div><span class="connect">Connect</span></div>
    <div class="crow" data-i="2"><span class="cico tile-wallet"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18M16 14h2"/></svg></span><div><div class="cn">Wallet</div><div class="csub">Watch an address</div></div><span class="connect">Connect</span></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">CONNECT</div>
    ${CONNECT.map((c,i)=>`<div class="orow" data-i="${i}"><span class="cico ${c[2]==='wallet'?'tile-wallet':c[2]==='photos'?'tile-photos':''}">${c[2]==='github'||c[2]==='spotify'?`<img src="${ic(c[2])}">`:c[2]==='wallet'?'<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18M16 14h2"/></svg>':''}</span><div><div class="cn">${c[0]}</div><div class="csub">${c[1]}</div></div><span class="connect" data-c="${i}">Connect</span></div>`).join('')}
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">YOUR FEED</div>
    ${FEED.map((f,i)=>{const col={github:'#8957e5',spotify:'#1DB954',photos:'#E0459C',wallet:'#2E63FF',farcaster:'#7C4DEC'}[f[0]];return `<div class="frow" data-i="${i}"><span class="fdot" style="background:${col}"></span><span class="fsrc mono">${f[1].toUpperCase()}</span><span class="ftx">${f[2]}</span></div>`}).join('')}
    <div class="ynote" id="ynote">Dev, music, a screenshot, a trade, a cast — <b>everything you follow, together</b>.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">NO ACCOUNT, NOTHING LEAVES</div>
    <div class="ybig" data-i="0"><i>✓</i><span>No sign-up, no password</span></div>
    <div class="ybig" data-i="1"><i>✓</i><span>Runs on your iPhone</span></div>
    <div class="ybig" data-i="2"><i>✓</i><span>Nothing leaves the device</span></div>
    <div class="ynote" id="ynote4">You connected apps, not accounts. What lands is <b>yours, on your phone</b>.</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),easeIn=p=>p*p,back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
// deterministic rain layout (golden-ratio spread, like the app's own)
const RN=${RAIN.length+4};
const rainPos=[];for(let i=0;i<RN;i++){const frac=(i*0.381966)%1;rainPos.push({x:60+frac*(840-104-120),restY:120+((i*0.618034)%1)*520,delay:(i%7)*0.05,tilt:[-14,10,-8,16,-12,7][i%6]});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.35);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(90,Math.min(320,900/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.textContent=D[active].head;const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t){
  if(i===0){
    document.querySelectorAll('#rain .rtile').forEach((el,k)=>{
      const P=rainPos[k];const fp=clamp01((p-P.delay)/0.55);      // fall in
      const y=-160+(P.restY+160)*easeIn(fp);
      const settle=0.5+0.5*fp;
      el.style.transform='translate('+P.x+'px,'+y+'px) rotate('+(P.tilt*(1-fp*0.6))+'deg) scale('+settle+')';
      el.style.opacity=clamp01(fp*3);
    });
  } else if(i===1){
    document.querySelectorAll('#comp1 .cchip').forEach((c,k)=>{const cp=clamp01((p-k*0.07)/0.24);c.style.opacity=cp;c.style.transform='translateY('+((1-easeOut(cp))*-14)+'px)';});
    document.querySelectorAll('#comp1 .crow').forEach((r,k)=>{const rp=clamp01((p-0.28-k*0.12)/0.3);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
  } else if(i===2){
    document.querySelectorAll('#comp2 .orow').forEach((r,k)=>{const rp=clamp01((p-k*0.12)/0.3);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';
      const btn=r.querySelector('.connect');const on=clamp01((p-0.4-k*0.13)/0.16);
      if(on>0.5){btn.classList.add('done');btn.textContent='Connected';}else{btn.classList.remove('done');btn.textContent='Connect';}
      btn.style.transform='scale('+(1+0.06*Math.sin(on*Math.PI))+')';});
  } else if(i===3){
    document.querySelectorAll('#comp3 .frow').forEach((r,k)=>{const rp=clamp01((p-k*0.11)/0.3);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('ynote').style.opacity=clamp01((p-0.62)/0.3);
  } else if(i===4){
    document.querySelectorAll('#comp4 .ybig').forEach((r,k)=>{const rp=clamp01((p-k*0.14)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('ynote4').style.opacity=clamp01((p-0.6)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-connect-live.html'),html);
console.log('wrote clip-connect-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
