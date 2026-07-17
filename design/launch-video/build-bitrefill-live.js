// Bitrefill promo — live-animated. node render.js clip-bitrefill-live.html --size=1080x1920
// Grounded in Model/BitrefillBridge.swift + BridgeCatalog offer (prd §103, 2026-07-17):
//   read side only, Bearer API key → api-bitrefill.com, key stays in Keychain
//   orders land titled "\(name) · \(value)" wearing the product's artwork
//   deposit invoices land as "Balance refill · $50 in bitcoin"
//   balance feeds the source's lede; BitrefillBalance.formatted
//   HONESTY CEILING: the API reports NO redemption status and NO expiry,
//     so rows NEVER claim "unused"/"expires" — this is the differentiating beat
//   "Read-only by conduct: nothing here ever buys, pays, or spends your balance."
// All product marks are DRAWN tinted tiles — no external logos.
const fs=require('fs'), path=require('path');
const AC='#FF5A3C', GOLD='#F5C451', GRN='#3fb950';
const BEATS=[
  {kick:'CONNECT', head:'One API\nkey.',            accent:AC},
  {kick:'ORDERS',  head:'Every card\nyou bought.',  accent:AC},
  {kick:'REFILLS', head:'Deposits,\ntoo.',          accent:AC},
  {kick:'HONEST',  head:"Won't claim\nwhat it can't see.", accent:AC},
  {kick:'READ-ONLY',head:'Never buys.\nNever spends.',accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:(i+1<10?'0':'')+(i+1)+' · '+b.kick,head:b.head,accent:b.accent}));
// orderThing titles — "\(name) · \(value)"; tiles are drawn, tinted per brand
const ORDERS=[
  ['Amazon.com','$50','#232F3E','#FF9900','a'],
  ['Steam','$25','#1B2838','#66C0F4','S'],
  ['Uber','$30','#000000','#ffffff','U'],
  ['App Store','$15','#0A84FF','#ffffff','▲'],
];
// depositThing titles — "Balance refill · $50 in bitcoin"
const REFILLS=[
  ['Balance refill','$50','bitcoin','#F7931A'],
  ['Balance refill','$100','USDC','#2775CA'],
];
// the honesty grid — what the API gives vs what it can't know
const KNOW=[
  [1,'Product & value','Amazon.com · $50'],
  [1,'Its own artwork','the card face'],
  [1,'When it arrived','delivered_time'],
  [0,'Whether it was redeemed',''],
  [0,'When it expires',''],
];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:118px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#140b09;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;}
.baln{font-size:26px;font-weight:800;color:${GOLD};letter-spacing:0;}
/* connect */
.mark{width:130px;height:130px;border-radius:32px;background:linear-gradient(150deg,${AC},#E0381C);display:flex;align-items:center;justify-content:center;box-shadow:0 16px 40px rgba(255,90,60,.4);will-change:transform;}
.mark svg{width:66px;height:66px;}
.field{margin-top:40px;background:#080504;border:2px solid rgba(255,255,255,.14);border-radius:22px;padding:30px 34px;font-size:34px;display:flex;align-items:center;min-height:100px;box-shadow:inset 0 0 0 0 ${AC};}
.field .pre{color:rgba(255,255,255,.4);}
.caret{display:inline-block;width:4px;height:40px;background:${AC};margin-left:4px;}
.klock{margin-top:38px;font-size:29px;color:rgba(255,255,255,.55);line-height:1.55;will-change:opacity,transform;}
.klock i{display:inline-flex;width:44px;height:44px;border-radius:50%;background:rgba(255,90,60,.16);color:${AC};align-items:center;justify-content:center;font-style:normal;font-size:24px;vertical-align:-12px;margin-right:16px;}
.klock b{color:#fff;font-weight:700;}
/* orders */
.orow{display:flex;align-items:center;gap:26px;padding:24px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.orow:first-of-type{border-top:none;}
.otile{width:88px;height:88px;border-radius:18px;flex:none;display:flex;align-items:center;justify-content:center;font-size:44px;font-weight:800;box-shadow:0 8px 20px rgba(0,0,0,.4);}
.on{font-size:38px;font-weight:650;} .ov{font-size:27px;color:rgba(255,255,255,.45);margin-top:5px;}
.oval{margin-left:auto;font-size:40px;font-weight:800;color:${GOLD};}
/* refills */
.rrow{display:flex;align-items:center;gap:24px;padding:30px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.rrow:first-of-type{border-top:none;}
.rcoin{width:70px;height:70px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:26px;color:#fff;}
.rt{font-size:37px;font-weight:600;} .rm{font-size:25px;color:rgba(255,255,255,.45);margin-top:5px;}
.rplus{margin-left:auto;font-size:38px;font-weight:800;color:${GRN};}
.rnote{margin-top:32px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.rnote b{color:${GOLD};}
/* honest */
.krow{display:flex;align-items:center;gap:22px;padding:22px 0;border-top:2px solid rgba(255,255,255,.07);font-size:32px;will-change:opacity,transform;}
.krow:first-of-type{border-top:none;}
.krow i{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
.krow.y i{background:${GRN};color:#04140a;} .krow.y{font-weight:650;}
.krow.n i{background:rgba(255,255,255,.07);color:rgba(255,255,255,.3);} .krow.n{color:rgba(255,255,255,.34);}
.krow em{font-style:normal;font-size:23px;color:rgba(255,255,255,.4);margin-left:auto;}
.knote{margin-top:28px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.knote b{color:#fff;}
/* read-only */
.vrow{display:flex;align-items:center;gap:26px;padding:30px 0;border-top:2px solid rgba(255,255,255,.07);font-size:40px;font-weight:600;will-change:opacity,transform;}
.vrow:first-of-type{border-top:none;}
.vrow s{width:64px;height:64px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;font-size:34px;text-decoration:none;}
.vnote{margin-top:36px;font-size:28px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.vnote b{color:#fff;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>BITREFILL</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono"><span>CONNECT</span></div>
    <div class="mark" id="mark"><svg viewBox="0 0 100 100" fill="#fff"><path d="M58 6 24 54h20l-8 40 34-50H50z"/></svg></div>
    <div class="field mono" id="field"><span class="pre">key&nbsp;</span><span id="ktype"></span><span class="caret" id="caret"></span></div>
    <div class="klock" id="klock"><i>🔒</i> Stays in this iPhone's <b>Keychain</b>, goes only to Bitrefill. <b>Read-only.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono"><span>ORDERS</span><span class="baln" id="baln1">$127.40 balance</span></div>
    ${ORDERS.map((o,i)=>`<div class="orow" data-i="${i}"><span class="otile" style="background:${o[2]};color:${o[3]}">${o[4]}</span><div><div class="on">${o[0]}</div><div class="ov mono">gift card</div></div><span class="oval">${o[1]}</span></div>`).join('')}
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono"><span>BALANCE REFILLS</span><span class="baln" id="baln2">$127.40 balance</span></div>
    ${REFILLS.map((r,i)=>`<div class="rrow" data-i="${i}"><span class="rcoin" style="background:${r[3]}">${r[2]==='bitcoin'?'₿':'$'}</span><div><div class="rt">${r[0]}</div><div class="rm mono">in ${r[2]}</div></div><span class="rplus">+${r[1]}</span></div>`).join('')}
    <div class="rnote" id="rnote">A deposit with no order on it is money you added — it lands as a refill, and the balance rides the <b>top of the feed</b>.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono"><span>WHAT THE API ACTUALLY REPORTS</span></div>
    ${KNOW.map((k,i)=>`<div class="krow ${k[0]?'y':'n'}" data-i="${i}"><i>${k[0]?'✓':'—'}</i><span>${k[1]}</span>${k[2]?`<em class="mono">${k[2]}</em>`:''}</div>`).join('')}
    <div class="knote" id="knote">Bitrefill can't know a code was spent at Amazon — so Casberi <b>never says it was</b>. No "unused", no "expires". Only what's true.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono"><span>READ-ONLY BY CONDUCT</span></div>
    <div class="vrow" data-i="0"><s>✕</s><span>Never <b style="color:#fff">buys</b></span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Never <b style="color:#fff">pays</b></span></div>
    <div class="vrow" data-i="2"><s>✕</s><span>Never <b style="color:#fff">spends your balance</b></span></div>
    <div class="vnote" id="vnote">It reads your account and stops there. What you bought just <b>joins everything else</b> you keep.</div>
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
const KEY='bfl_9f3a…2c7e';
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
    const mp=clamp01(p/0.3);
    document.getElementById('mark').style.transform='scale('+(0.6+0.4*back(mp))+') rotate('+((1-easeOut(mp))*-12)+'deg)';
    const n=Math.round(KEY.length*clamp01((p-0.28)/0.4));
    document.getElementById('ktype').textContent=KEY.slice(0,n);
    document.getElementById('caret').style.opacity=(p>0.28&&p<0.72&&Math.floor(t*2)%2)?1:0;
    const k=document.getElementById('klock');const kp=clamp01((p-0.66)/0.28);k.style.opacity=kp;k.style.transform='translateY('+((1-easeOut(kp))*16)+'px)';
  } else if(i===1){
    document.querySelectorAll('#comp1 .orow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-34)+'px)';});
    document.getElementById('baln1').style.opacity=clamp01((p-0.5)/0.3);
  } else if(i===2){
    document.querySelectorAll('#comp2 .rrow').forEach((r,k)=>{const rp=clamp01((p-k*0.16)/0.4);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    document.getElementById('baln2').style.opacity=clamp01((p-0.4)/0.3);
    document.getElementById('rnote').style.opacity=clamp01((p-0.56)/0.3);
  } else if(i===3){
    document.querySelectorAll('#comp3 .krow').forEach((r,k)=>{const rp=clamp01((p-k*0.1)/0.3);r.style.opacity=rp*(r.classList.contains('n')?0.999:1);r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('knote').style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===4){
    document.querySelectorAll('#comp4 .vrow').forEach((r,k)=>{const rp=clamp01((p-k*0.14)/0.36);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    document.getElementById('vnote').style.opacity=clamp01((p-0.62)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-bitrefill-live.html'),html);
console.log('wrote clip-bitrefill-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
