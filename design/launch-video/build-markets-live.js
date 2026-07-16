// Markets & odds promo — live-animated. node render.js clip-markets-live.html --size=1080x1920
const fs=require('fs'), path=require('path');
const NFTDIR='/Users/alexanderchopan/Developer/casberi/scratchpad/nft';
const nft=n=>'data:image/jpeg;base64,'+fs.readFileSync(path.join(NFTDIR,n+'.jpg')).toString('base64');
const AC='#0FB5C4', UP='#3fb950', DN='#f85149';
const BEATS=[
  {kick:'ODDS',   head:'Live\nodds.',        accent:AC},
  {kick:'STOCKS', head:'Stock\nchatter.',    accent:AC},
  {kick:'DROPS',  head:'New\ndrops.',         accent:AC},
  {kick:'CHARTS', head:'Every\nchart.',       accent:AC},
  {kick:'ONE FEED',head:'All the money,\none feed.',accent:AC},
];
const INTRO=0.45,BEAT=1.9,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:(i+1<10?'0':'')+(i+1)+' · '+b.kick,head:b.head,accent:b.accent}));
const ODDS=[['Fed holds rates in March',68],['Lakers make the playoffs',74],['BTC over $100k by Q1',41]];
const NFTS=[['Fidenza','fidenza'],['Squiggle','squiggle'],['Archetype','archetype'],['Gazers','gazers']];
const FEED=[['Kalshi','#0FB5C4','Fed holds rates · 68%'],['Stocktwits','#e0325a','$NVDA · 82% bullish'],['OpenSea','#2081E2','Fidenza · new drop'],['GeckoTerminal','#E0982A','$BRETT trending on Base']];

const html=`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
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
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0b1113;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:20px;}
/* odds */
.orow{margin-bottom:40px;will-change:opacity,transform;}
.ol{font-size:38px;font-weight:600;display:flex;justify-content:space-between;margin-bottom:16px;} .ol b{color:${AC};}
.obar{height:26px;border-radius:100px;background:rgba(255,255,255,.09);overflow:hidden;} .ofill{height:100%;border-radius:100px;background:${AC};width:0;}
/* stocks */
.srow{display:flex;align-items:center;gap:24px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;} .srow:first-of-type{border-top:none;}
.st{font-size:44px;font-weight:750;width:170px;} .sp{font-size:34px;} .sc{font-weight:700;}
.sent{margin-left:auto;text-align:right;} .sentb{width:180px;height:16px;border-radius:100px;background:rgba(255,255,255,.09);overflow:hidden;margin-top:8px;} .sentf{height:100%;background:${UP};width:0;}
.sl{font-size:24px;color:rgba(255,255,255,.5);}
/* drops */
.dgrid{display:grid;grid-template-columns:1fr 1fr;gap:26px;margin-top:6px;}
.dtile{border-radius:24px;height:300px;position:relative;overflow:hidden;will-change:opacity,transform;box-shadow:0 12px 30px rgba(0,0,0,.35);}
.dtile .art{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;}
.dtile .cap{position:absolute;left:0;right:0;bottom:0;padding:24px;background:linear-gradient(transparent,rgba(0,0,0,.6));font-size:34px;font-weight:700;}
.dtile .nw{position:absolute;top:20px;right:20px;background:${AC};color:#04211f;font-size:22px;font-weight:800;padding:8px 18px;border-radius:100px;}
/* chart */
.chead{font-size:40px;font-weight:750;} .cprice{font-size:76px;font-weight:800;margin-top:8px;} .cprice .c{font-size:38px;color:${UP};margin-left:14px;}
.chart{width:100%;height:280px;margin-top:12px;overflow:visible;}
/* feed */
.frow{display:flex;align-items:center;gap:26px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;} .frow:first-of-type{border-top:none;}
.fi{width:60px;height:60px;border-radius:16px;flex:none;} .ft{font-size:38px;font-weight:600;} .fm{font-size:25px;color:rgba(255,255,255,.5);margin-top:4px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;} .outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>MARKETS</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">KALSHI · LIVE ODDS</div>
    ${ODDS.map((o,i)=>`<div class="orow" data-i="${i}"><div class="ol">${o[0]} <b class="opct" data-pct="${o[1]}">0%</b></div><div class="obar"><div class="ofill" data-pct="${o[1]}"></div></div></div>`).join('')}
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">STOCKTWITS</div>
    ${[['NVDA','$121.40','+2.1%',82],['TSLA','$248.50','-1.4%',54],['AAPL','$229.10','+0.6%',67]].map((s,i)=>`<div class="srow" data-i="${i}"><div class="st">$${s[0]}</div><div><div class="sp">${s[1]} <span class="sc" style="color:${s[2][0]==='+'?UP:DN}">${s[2]}</span></div></div><div class="sent"><div class="sl">${s[3]}% bullish</div><div class="sentb"><div class="sentf" data-pct="${s[3]}"></div></div></div></div>`).join('')}
  </div>

  <div class="comp" id="comp2">
    <div class="dgrid">${NFTS.map((n,i)=>`<div class="dtile" data-i="${i}"><img class="art" src="${nft(n[1])}"><div class="nw">NEW</div><div class="cap">${n[0]}</div></div>`).join('')}</div>
  </div>

  <div class="comp" id="comp3">
    <div class="chead">$NVDA · NVIDIA</div>
    <div class="cprice"><span id="cpx">$0.00</span><span class="c" id="cpc">+0%</span></div>
    <svg class="chart" viewBox="0 0 740 280" preserveAspectRatio="none"><defs><linearGradient id="cg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${UP}" stop-opacity=".4"/><stop offset="1" stop-color="${UP}" stop-opacity="0"/></linearGradient></defs><path id="cfill" d="" fill="url(#cg)"/><path id="cpath" d="" fill="none" stroke="${UP}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/></svg>
  </div>

  <div class="comp" id="comp4">
    ${FEED.map((f,i)=>`<div class="frow" data-i="${i}"><div class="fi" style="background:${f[1]}"></div><div><div class="ft">${f[2]}</div><div class="fm">${f[0]}</div></div></div>`).join('')}
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span id="pg">01 / 05</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b> · free on TestFlight</div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
const CPTS=[[0,230],[70,200],[140,215],[210,150],[280,175],[350,110],[420,135],[500,80],[580,100],[660,45],[740,24]];
function chartD(p){const n=Math.max(2,Math.round(CPTS.length*p));return 'M'+CPTS.slice(0,n).map(q=>q[0]+' '+q[1]).join(' L');}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.3);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=(active+1<10?'0':'')+(active+1);wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.textContent=D[active].head;const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  document.getElementById('pg').textContent=(active+1<10?'0':'')+(active+1)+' / 0'+N;
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function stagger(sel,p,step,dur,rise){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*step)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*(rise||24))+'px)';});}
function animateComp(i,p,t){
  if(i===0){document.querySelectorAll('#comp0 .orow').forEach((r,k)=>{const rp=clamp01((p-k*0.12)/0.4);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*20)+'px)';const pct=+r.querySelector('.ofill').dataset.pct;const fp=clamp01((p-0.15-k*0.12)/0.5);r.querySelector('.ofill').style.width=(pct*easeOut(fp))+'%';r.querySelector('.opct').textContent=Math.round(pct*easeOut(fp))+'%';});}
  else if(i===1){document.querySelectorAll('#comp1 .srow').forEach((r,k)=>{const rp=clamp01((p-k*0.12)/0.4);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*20)+'px)';const pct=+r.querySelector('.sentf').dataset.pct;r.querySelector('.sentf').style.width=(pct*easeOut(clamp01((p-0.2-k*0.12)/0.5)))+'%';});}
  else if(i===2){document.querySelectorAll('#comp2 .dtile').forEach((s,k)=>{const cp=clamp01((p-k*0.12)/0.45);s.style.opacity=cp;s.style.transform='rotateY('+((1-easeOut(cp))*70)+'deg) scale('+(0.8+0.2*easeOut(cp))+')';});}
  else if(i===3){document.getElementById('cpx').textContent='$'+(121.40*easeOut(p)).toFixed(2);document.getElementById('cpc').textContent='+'+(2.1*easeOut(p)).toFixed(1)+'%';const d=chartD(clamp01(p/0.85));document.getElementById('cpath').setAttribute('d',d);document.getElementById('cfill').setAttribute('d',d.includes('L')?d+' L740 280 L0 280 Z':'');}
  else if(i===4){stagger('#comp4 .frow',p,0.13,0.36,24);}
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-markets-live.html'),html);
console.log('wrote clip-markets-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
