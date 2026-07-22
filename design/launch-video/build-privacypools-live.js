// 0xBow Privacy Pools promo — live-animated. node render.js clip-privacypools-live.html --size=1080x1920
// Grounded in Model/PrivacyPoolsBridge.swift + Screens/PrivacyPoolsScreen.swift, prd §162:
//   0xBow Privacy Pools — deposit from your own wallet, wait for compliance screening (the ASP)
//   to clear before withdrawing privately. NO account, no key, no OAuth — rides the watched
//   Wallet the way Peer does; connecting is one switch.
//   Deposit title format: "Put 0.0700 ETH into Privacy Pools"
//   Cleared alert: "Privacy Pools cleared your 0.07 ETH deposit — ready to withdraw privately"
//   Declined alert: "...declined your ... deposit — you can reclaim it to your wallet"
//   The whole feature IS that flip — the wait people otherwise keep reloading 0xBow's site for.
//   Withdrawals are unlinkable by design (the chain can't tie them to the deposit) — Casberi
//   never sees or shows that side. Read-only: never deposits, withdraws, or moves funds.
//   Brand: deep violet (0xBow's own privacy-pool aesthetic), drawn shield/pool glyph.
const fs=require('fs'), path=require('path');
const AC='#6C4FE0', GRN='#3fb950', AMBER='#E0982A';
const BEATS=[
  {kick:'THE WAIT',   head:'Stuck in\nreview.',          accent:AC},
  {kick:'WATCHED',    head:'Casberi\nwatches it.',        accent:AC},
  {kick:'THE FLIP',   head:'Cleared.\nReady to\nwithdraw.',accent:AC},
  {kick:'PRIVATE',    head:'The withdrawal\nstays yours.', accent:AC},
  {kick:'READ-ONLY',  head:'No account.\nNo key.',         accent:AC},
];
const INTRO=0.45,BEAT=2.1,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
const SHOWN=[[1,'Your deposit landed'],[1,'The amount & asset'],[1,'The review status']];
const HIDDEN=[[0,'Your withdrawal'],[0,'Who you are IRL'],[0,'Any link to the deposit']];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:112px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;}
/* the wait — a browser mock, reloading */
.brow{background:#05050e;border-radius:22px;padding:0;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);overflow:hidden;}
.btop{display:flex;align-items:center;gap:12px;padding:22px 26px;border-bottom:2px solid rgba(255,255,255,.07);}
.bdot{width:16px;height:16px;border-radius:50%;background:rgba(255,255,255,.15);}
.burl{margin-left:10px;font-size:24px;color:rgba(255,255,255,.4);font-family:ui-monospace,"SF Mono",monospace;}
.bspin{margin-left:auto;width:30px;height:30px;border-radius:50%;border:4px solid rgba(255,255,255,.15);border-top-color:${AC};will-change:transform;}
.bbody{padding:48px 36px;text-align:center;}
.bstatus{font-size:40px;font-weight:700;}
.bsub{font-size:26px;color:rgba(255,255,255,.45);margin-top:14px;}
.bcount{margin-top:34px;font-size:24px;color:rgba(255,255,255,.35);}
.bcount b{color:rgba(255,255,255,.7);}
.wnote{margin-top:34px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.wnote b{color:#fff;}
/* watched — deposit lands as a thing */
.wcard{background:#05050e;border-radius:24px;padding:36px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.wtop{display:flex;align-items:center;gap:22px;}
.wav{width:76px;height:76px;border-radius:50%;flex:none;background:conic-gradient(from 210deg,#a08cff,${AC},#a08cff);}
.wn{font-size:36px;font-weight:700;} .wa{font-size:24px;color:rgba(255,255,255,.45);margin-top:5px;}
.togrow{display:flex;align-items:center;gap:24px;margin-top:34px;padding-top:32px;border-top:2px solid rgba(255,255,255,.08);}
.togl{font-size:31px;font-weight:600;}
.tog{margin-left:auto;width:104px;height:58px;border-radius:100px;background:rgba(255,255,255,.14);position:relative;flex:none;will-change:background;}
.knob{position:absolute;top:5px;left:5px;width:48px;height:48px;border-radius:50%;background:#fff;will-change:transform;}
.drow{display:flex;align-items:center;gap:20px;margin-top:30px;padding-top:28px;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.dtile{width:64px;height:64px;border-radius:18px;flex:none;background:${AC};display:flex;align-items:center;justify-content:center;}
.dt{font-size:30px;font-weight:650;} .dtag{margin-left:auto;font-size:22px;color:rgba(255,255,255,.4);}
/* the flip — pending -> cleared */
.srow{display:flex;align-items:center;gap:22px;padding:26px 30px;border-radius:18px;margin-bottom:20px;font-size:29px;font-weight:600;will-change:opacity,transform,filter;}
.srow .si{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:22px;font-weight:800;}
.srow.pend{background:rgba(255,255,255,.04);box-shadow:inset 0 0 0 2px rgba(255,255,255,.08);color:rgba(255,255,255,.4);}
.srow.pend .si{background:rgba(255,255,255,.08);color:rgba(255,255,255,.4);}
.srow.done{background:rgba(63,185,80,.1);box-shadow:inset 0 0 0 2px rgba(63,185,80,.4);}
.srow.done .si{background:${GRN};color:#04140a;} .srow.done b{color:${GRN};}
.srow .stag{margin-left:auto;font-size:22px;font-weight:700;}
.snote{margin-top:30px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.snote b{color:#fff;}
/* private — two columns */
.pcol{display:flex;gap:22px;margin-top:2px;}
.pc{flex:1;border-radius:22px;padding:32px 26px;will-change:opacity,transform;}
.pcS{background:rgba(108,79,224,.12);box-shadow:inset 0 0 0 2px rgba(108,79,224,.45);}
.pcH{background:rgba(255,255,255,.03);box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);}
.pch{font-size:21px;letter-spacing:.08em;margin-bottom:22px;font-weight:700;}
.pcS .pch{color:#c3b3ff;} .pcH .pch{color:rgba(255,255,255,.4);}
.pr{display:flex;align-items:center;gap:14px;padding:15px 0;font-size:25px;font-weight:600;will-change:opacity;}
.pr i{width:34px;height:34px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:18px;font-weight:800;}
.pcS .pr i{background:${GRN};color:#04140a;} .pcS .pr{color:#fff;}
.pcH .pr i{background:rgba(255,255,255,.08);color:rgba(255,255,255,.35);} .pcH .pr{color:rgba(255,255,255,.34);}
.pnote{margin-top:30px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.pnote b{color:#fff;}
/* read-only */
.vrow{display:flex;align-items:center;gap:24px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);font-size:35px;font-weight:600;will-change:opacity,transform;}
.vrow:first-of-type{border-top:none;}
.vrow s{width:56px;height:56px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;font-size:30px;text-decoration:none;}
.vrow b{color:#fff;}
.vok{display:flex;align-items:center;gap:20px;margin-top:32px;font-size:29px;font-weight:650;color:${GRN};will-change:opacity,transform;}
.vok i{width:50px;height:50px;border-radius:50%;flex:none;background:${GRN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:28px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>PRIVACY POOLS</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono"><span>0XBOW.IO</span></div>
    <div class="brow">
      <div class="btop"><span class="bdot"></span><span class="bdot"></span><span class="bdot"></span><span class="burl">0xbow.io/pools/status</span><span class="bspin" id="bspin"></span></div>
      <div class="bbody"><div class="bstatus">Checking review status…</div><div class="bsub">Your deposit is still in the queue</div><div class="bcount"><b id="bn">0</b> reloads today</div></div>
    </div>
    <div class="wnote" id="wnote0">A Privacy Pools deposit sits in <b>review</b> until 0xBow's screening clears it. Until then, the only way to know is to keep checking their site.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono"><span>NO ACCOUNT · RIDES YOUR WALLET</span></div>
    <div class="wcard">
      <div class="wtop"><span class="wav"></span><div><div class="wn">jesse.base.eth</div><div class="wa mono">0x2211…7dA9 · watched</div></div></div>
      <div class="togrow"><span class="togl">Watch my Privacy Pools deposits</span><span class="tog" id="tog"><span class="knob" id="knob"></span></span></div>
      <div class="drow" id="drow"><span class="dtile"><svg viewBox="0 0 24 24" width="30" height="30"><path fill="#fff" d="M12 2 4 5v6c0 5 3.4 9 8 11 4.6-2 8-6 8-11V5l-8-3z"/></svg></span><div class="dt">Put 0.0700 ETH into Privacy Pools</div><span class="dtag">just now</span></div>
    </div>
    <div class="wnote" id="wnote1">One switch over a wallet you already watch. <b>No sign-up, no key</b> — the deposit lands the moment it's on Ethereum's public chain.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono"><span>THE ASP, POLLED FOR YOU</span></div>
    <div class="srow pend" id="spend"><span class="si">…</span><span>0.07 ETH deposit — in review</span><span class="stag mono">pending</span></div>
    <div class="srow done" id="sdone"><span class="si">✓</span><span>Cleared — <b>ready to withdraw privately</b></span><span class="stag mono">cleared</span></div>
    <div class="snote" id="snote">The moment screening clears your deposit, it shows up in your feed — <b>the wait you'd otherwise keep reloading a website for.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono"><span>UNLINKABLE BY DESIGN</span></div>
    <div class="pcol">
      <div class="pc pcS" data-i="0"><div class="pch mono">CASBERI SEES</div>${SHOWN.map(s=>`<div class="pr"><i>✓</i>${s[1]}</div>`).join('')}</div>
      <div class="pc pcH" data-i="1"><div class="pch mono">STAYS PRIVATE</div>${HIDDEN.map(s=>`<div class="pr"><i>🔒</i>${s[1]}</div>`).join('')}</div>
    </div>
    <div class="pnote" id="pnote">Withdrawals move to a fresh address the chain can't tie to your deposit. The chain never shows it — <b>so neither does Casberi</b>.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono"><span>READ-ONLY, BY RULING</span></div>
    <div class="vrow" data-i="0"><s>✕</s><span>Never <b>deposits</b> for you</span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Never <b>withdraws</b> or proves</span></div>
    <div class="vok" id="vok"><i>✓</i> Only reads deposits & status, once they're public</div>
    <div class="wnote" style="margin-top:36px" id="vnote">No account, no key. Watch a wallet, and the wait becomes a notification.</div>
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
const comps=[...document.querySelectorAll('.comp')];
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.4);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(70,Math.min(320,900/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.textContent=D[active].head;const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t){
  if(i===0){
    document.getElementById('bspin').style.transform='rotate('+(t*360)+'deg)';
    document.getElementById('bn').textContent=Math.round(14*easeOut(clamp01(p/0.6)));
    document.getElementById('wnote0').style.opacity=clamp01((p-0.55)/0.3);
  } else if(i===1){
    const on=clamp01((p-0.22)/0.2);
    document.getElementById('tog').style.background=on>0.5?'${AC}':'rgba(255,255,255,.14)';
    document.getElementById('knob').style.transform='translateX('+(on*46)+'px)';
    const dr=document.getElementById('drow');const drp=clamp01((p-0.44)/0.28);dr.style.opacity=drp;dr.style.transform='translateY('+((1-back(drp))*18)+'px)';
    document.getElementById('wnote1').style.opacity=clamp01((p-0.68)/0.28);
  } else if(i===2){
    const pd=document.getElementById('spend');const pdp=clamp01(p/0.3);pd.style.opacity=pdp;pd.style.transform='translateX('+((1-easeOut(pdp))*-28)+'px)';
    const settle=clamp01((p-0.42)/0.26);
    pd.style.filter='grayscale('+settle+')';pd.style.opacity=pdp*(1-0.5*settle);
    const dn=document.getElementById('sdone');dn.style.opacity=settle;dn.style.transform='translateY('+((1-back(settle))*24)+'px) scale('+(0.96+0.04*settle)+')';
    document.getElementById('snote').style.opacity=clamp01((p-0.64)/0.3);
  } else if(i===3){
    document.querySelectorAll('#comp3 .pc').forEach((r,k)=>{const rp=clamp01((p-k*0.16)/0.4);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*28)+'px)';
      r.querySelectorAll('.pr').forEach((row,j)=>{row.style.opacity=clamp01((p-0.2-k*0.12-j*0.07)/0.24);});});
    document.getElementById('pnote').style.opacity=clamp01((p-0.6)/0.3);
  } else if(i===4){
    document.querySelectorAll('#comp4 .vrow').forEach((r,k)=>{const rp=clamp01((p-k*0.14)/0.36);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    const ok=document.getElementById('vok');const okp=clamp01((p-0.4)/0.28);ok.style.opacity=okp;ok.style.transform='translateY('+((1-back(okp))*18)+'px)';
    document.getElementById('vnote').style.opacity=clamp01((p-0.6)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-privacypools-live.html'),html);
console.log('wrote clip-privacypools-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
