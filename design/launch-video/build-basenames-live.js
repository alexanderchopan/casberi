// Basenames promo — live-animated. node render.js clip-basenames-live.html --size=1080x1920
const fs=require('fs'), path=require('path');
const AVD='/Users/alexanderchopan/Developer/casberi/scratchpad/ens';
const av=n=>'data:image/png;base64,'+fs.readFileSync(path.join(AVD,n+'.png')).toString('base64');
const AC='#0052FF', OK='#3fb950';
const BEATS=[
  {kick:'NAME',      head:'Type a name,\nnot an address.', accent:AC},
  {kick:'RESOLVE',   head:'Address and\navatar, both.',    accent:AC},
  {kick:'SUBNAMES',  head:'Basenames are\nENS subnames.',  accent:AC},
  {kick:'WATCHLIST', head:'Faces,\nnot hex.',              accent:AC},
  {kick:'FREE',      head:'Nothing\nto build.',            accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:(i+1<10?'0':'')+(i+1)+' · '+b.kick,head:b.head,accent:b.accent}));

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:126px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0a0e18;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;}
/* field */
.field{background:#050810;border:2px solid rgba(255,255,255,.14);border-radius:22px;padding:30px 34px;font-size:40px;display:flex;align-items:center;min-height:104px;}
.ph{color:rgba(255,255,255,.28);}
.caret{display:inline-block;width:4px;height:42px;background:${AC};margin-left:4px;}
.wbtn{margin-top:28px;background:${AC};color:#fff;font-weight:750;font-size:32px;padding:22px 48px;border-radius:100px;display:inline-block;will-change:transform;}
.hex{margin-top:32px;font-size:30px;color:rgba(255,255,255,.3);}
.hex s{text-decoration-color:#f85149;}
/* resolved */
.rcard{display:flex;align-items:center;gap:30px;background:#050810;border-radius:26px;padding:34px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);will-change:opacity,transform;}
.rcard img{width:132px;height:132px;border-radius:50%;flex:none;will-change:transform;}
.rn{font-size:46px;font-weight:750;}
.ra{font-size:30px;color:rgba(255,255,255,.5);margin-top:8px;}
.rok{display:inline-flex;align-items:center;gap:12px;margin-top:30px;font-size:29px;color:${OK};font-weight:650;will-change:opacity,transform;}
.rok i{width:36px;height:36px;border-radius:50%;background:${OK};color:#04140a;display:flex;align-items:center;justify-content:center;font-size:23px;font-style:normal;}
/* chain */
.node{background:#050810;border-radius:20px;padding:26px 30px;font-size:36px;font-weight:700;box-shadow:inset 0 0 0 1px rgba(255,255,255,.09);will-change:opacity,transform;text-align:center;}
.node.hex2{color:${AC};}
.arrow{display:flex;align-items:center;gap:14px;justify-content:center;padding:14px 0;font-size:24px;color:rgba(255,255,255,.45);letter-spacing:.1em;will-change:opacity;}
.arrow em{font-style:normal;}
.arrow b{color:${AC};font-size:30px;}
.cnote{margin-top:30px;font-size:28px;color:rgba(255,255,255,.5);line-height:1.4;will-change:opacity;}
/* watchlist */
.wrow{display:flex;align-items:center;gap:26px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.wrow:first-of-type{border-top:none;}
.wrow img{width:88px;height:88px;border-radius:50%;flex:none;}
.wn{font-size:40px;font-weight:700;} .wa{font-size:26px;color:rgba(255,255,255,.45);margin-top:5px;}
/* free */
.zero{font-size:230px;font-weight:800;line-height:.85;color:${AC};letter-spacing:-.05em;will-change:opacity,transform;}
.zsub{font-size:40px;font-weight:700;margin-top:6px;}
.znote{font-size:29px;color:rgba(255,255,255,.5);line-height:1.45;margin-top:28px;will-change:opacity;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>BASENAMES</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">WATCH AN ADDRESS</div>
    <div class="field mono"><span id="ftype"></span><span class="caret" id="caret"></span></div>
    <div class="wbtn" id="wbtn">Watch</div>
    <div class="hex mono" id="hexghost">instead of <s>0x2211d1D0020DAEA8039E46Cf1367962070d77DA9</s></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">RESOLVED</div>
    <div class="rcard" id="rcard"><img id="rav" src="${av('jessebaseeth')}"><div><div class="rn">jesse.base.eth</div><div class="ra mono">0x2211…7dA9</div></div></div>
    <div class="rok" id="rok"><i>✓</i> Address and avatar, from one name.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="node" data-i="0">jesse.base.eth</div>
    <div class="arrow" data-i="0"><b>↓</b><em>SUBNAME OF</em></div>
    <div class="node" data-i="1">base.eth</div>
    <div class="arrow" data-i="1"><b>↓</b><em>ENS RESOLVER</em></div>
    <div class="node hex2 mono" data-i="2">0x2211…7dA9</div>
    <div class="cnote" id="cnote">A Basename is an ENS subname — the resolver just follows it.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">WATCHING</div>
    <div class="wrow" data-i="0"><img src="${av('vitaliketh')}"><div><div class="wn">vitalik.eth</div><div class="wa mono">0xd8dA…6045</div></div></div>
    <div class="wrow" data-i="1"><img src="${av('jessebaseeth')}"><div><div class="wn">jesse.base.eth</div><div class="wa mono">0x2211…7dA9</div></div></div>
  </div>

  <div class="comp" id="comp4">
    <div style="display:flex;flex-direction:column;height:100%;justify-content:center">
      <div class="zero" id="zero">0</div>
      <div class="zsub">lines of Basename code.</div>
      <div class="znote" id="znote">They resolve through the same ENS path everything else uses — address and avatar, both. Nothing to special-case.</div>
    </div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span id="pg">01 / 05</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b> · free on TestFlight</div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
const NAME='jesse.base.eth';
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.35);
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
function animateComp(i,p,t){
  if(i===0){
    const n=Math.round(NAME.length*clamp01(p/0.45));
    document.getElementById('ftype').textContent=NAME.slice(0,n);
    document.getElementById('caret').style.opacity=(p<0.52&&Math.floor(t*2)%2)?1:0;
    const b=document.getElementById('wbtn');const bp=clamp01((p-0.5)/0.25);b.style.opacity=bp;b.style.transform='scale('+(0.9+0.1*back(bp))+')';
    document.getElementById('hexghost').style.opacity=clamp01((p-0.7)/0.25)*0.9;
  } else if(i===1){
    const c=document.getElementById('rcard');const cp=clamp01(p/0.4);c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*36)+'px)';
    document.getElementById('rav').style.transform='scale('+(0.5+0.5*back(clamp01((p-0.15)/0.4)))+')';
    const ok=document.getElementById('rok');const okp=clamp01((p-0.55)/0.3);ok.style.opacity=okp;ok.style.transform='translateY('+((1-easeOut(okp))*14)+'px)';
  } else if(i===2){
    document.querySelectorAll('#comp2 .node').forEach((s,k)=>{const cp=clamp01((p-k*0.18)/0.3);s.style.opacity=cp;s.style.transform='translateY('+((1-back(cp))*26)+'px)';});
    document.querySelectorAll('#comp2 .arrow').forEach((s,k)=>{s.style.opacity=clamp01((p-0.12-k*0.18)/0.2);});
    document.getElementById('cnote').style.opacity=clamp01((p-0.6)/0.25);
  } else if(i===3){
    document.querySelectorAll('#comp3 .wrow').forEach((r,k)=>{const rp=clamp01((p-k*0.18)/0.4);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-36)+'px)';});
  } else if(i===4){
    const z=document.getElementById('zero');const zp=clamp01(p/0.35);z.style.opacity=zp;z.style.transform='scale('+(0.5+0.5*back(zp))+')';
    document.getElementById('znote').style.opacity=clamp01((p-0.4)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-basenames-live.html'),html);
console.log('wrote clip-basenames-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
