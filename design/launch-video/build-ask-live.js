// Ask promo — live-animated UI in the editorial frame. node render.js clip-ask-live.html --size=1080x1920
const fs = require('fs'); const path = require('path');
const AC = '#5B54E8';
const P = { fc:'#7C4DEC', wl:'#2E63FF', gh:'#2DA44E', ph:'#F5A524' };
const BEATS = [
  { kick:'ASK',      head:'Ask\nanything.',      accent:AC },
  { kick:'GROUNDED', head:'From your\nown things.', accent:AC },
  { kick:'RECAP',    head:'While you\nwere away.', accent:AC },
  { kick:'TOOLS',    head:'Then act\non it.',      accent:AC },
  { kick:'PRIVATE',  head:'All on\ndevice.',       accent:AC },
];
const INTRO=0.45, BEAT=1.95, OUT_AT=INTRO+BEATS.length*BEAT, TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick, head:b.head, accent:b.accent}));
const TOOLS=[['Note','#E3B341'],['Message','#2DA44E'],['Email','#E8452B'],['Event','#E8452B'],['Reminder','#F5A524'],['Search','#2E63FF']];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#111015;}
.abar{display:flex;align-items:center;gap:22px;background:#0a0a0f;border:2px solid rgba(255,255,255,.12);border-radius:26px;padding:30px 34px;font-size:38px;}
.aspark{color:${AC};font-size:40px;}
.acaret{display:inline-block;width:4px;height:40px;background:#fff;vertical-align:-6px;margin-left:3px;}
.aans{margin-top:40px;font-size:42px;line-height:1.4;font-weight:500;}
.aans b{color:${AC};}
.acite{margin-top:34px;display:flex;gap:14px;flex-wrap:wrap;}
.acite span{font-size:25px;padding:12px 24px;border-radius:100px;font-weight:600;will-change:opacity,transform;}
.srow{display:flex;align-items:center;gap:24px;padding:24px 0;border-top:2px solid rgba(255,255,255,.07);font-size:36px;will-change:opacity,transform;}
.srow:first-of-type{border-top:none;}
.sdot{width:44px;height:44px;border-radius:13px;flex:none;}
.sm{margin-left:auto;font-size:26px;color:rgba(255,255,255,.5);}
.shd{font-size:30px;color:rgba(255,255,255,.5);letter-spacing:.06em;margin-bottom:6px;}
.tgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:26px;margin-top:8px;}
.ttile{aspect-ratio:1.4;border-radius:26px;display:flex;flex-direction:column;align-items:flex-start;justify-content:flex-end;padding:26px;font-size:34px;font-weight:650;color:#fff;will-change:opacity,transform;box-shadow:0 12px 30px rgba(0,0,0,.3);}
.pv{display:flex;flex-direction:column;gap:30px;}
.plock{width:120px;height:120px;border-radius:30px;background:${AC}22;display:flex;align-items:center;justify-content:center;color:${AC};font-size:64px;}
.pbig{font-size:56px;font-weight:750;line-height:1.05;}
.pchk{font-size:38px;display:flex;align-items:center;gap:18px;will-change:opacity,transform;}
.pchk i{width:40px;height:40px;border-radius:50%;background:${AC};color:#0a0a0f;display:flex;align-items:center;justify-content:center;font-size:26px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>ASK</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="abar"><span class="aspark">✦</span><span id="aq"></span><span class="acaret" id="acaret"></span></div>
    <div class="aans" id="aans"></div>
    <div class="acite" id="acite"><span style="background:${P.fc}33;color:#c9a6ff">Farcaster</span><span style="background:${P.gh}33;color:#7fe0a0">GitHub</span><span style="background:${P.wl}33;color:#7fb0ff">Wallet</span></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">ANSWERED FROM</div>
    <div class="srow" data-i="0"><div class="sdot" style="background:${P.fc}"></div><div>vitalik.eth · a cast about L2s</div><div class="sm">Farcaster</div></div>
    <div class="srow" data-i="1"><div class="sdot" style="background:${P.gh}"></div><div>PR #142 · token layer</div><div class="sm">GitHub</div></div>
    <div class="srow" data-i="2"><div class="sdot" style="background:${P.wl}"></div><div>Sent 14.86 USDT on Base</div><div class="sm">Wallet</div></div>
    <div class="srow" data-i="3"><div class="sdot" style="background:${P.ph}"></div><div>a screenshot you saved</div><div class="sm">Photos</div></div>
    <div style="margin-top:34px;font-size:30px;color:rgba(255,255,255,.5)" class="mono" id="ansmeta"></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">SINCE YOU LEFT · 3H</div>
    <div class="srow" data-i="0"><div class="sdot" style="background:${P.fc}"></div><div>vitalik.eth posted 2 casts</div><div class="sm">2h</div></div>
    <div class="srow" data-i="1"><div class="sdot" style="background:${P.wl}"></div><div>Wallet · Sent 14.86 USDT</div><div class="sm">1h</div></div>
    <div class="srow" data-i="2"><div class="sdot" style="background:${P.gh}"></div><div>PR #142 was merged</div><div class="sm">40m</div></div>
    <div class="srow" data-i="3"><div class="sdot" style="background:#E8452B"></div><div>Evening run is at 6 PM</div><div class="sm">soon</div></div>
  </div>

  <div class="comp" id="comp3">
    <div class="tgrid">${TOOLS.map((t,i)=>`<div class="ttile" data-i="${i}" style="background:${t[1]}">${t[0]}</div>`).join('')}</div>
  </div>

  <div class="comp" id="comp4">
    <div class="pv">
      <div class="plock">✦</div>
      <div class="pbig">Answered by an on-device model.</div>
      <div style="display:flex;flex-direction:column;gap:24px">
        <div class="pchk" data-i="0"><i>✓</i> No account, ever</div>
        <div class="pchk" data-i="1"><i>✓</i> Nothing leaves your phone</div>
        <div class="pchk" data-i="2"><i>✓</i> Works offline</div>
      </div>
    </div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)), easeOut=p=>1-Math.pow(1-p,3), back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, BEAT=${BEAT}, OUT_AT=${OUT_AT}, N=${BEATS.length};
const D=${JSON.stringify(DATA)}; window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
const AQ='What did I save about Ethereum?';
const AANS='Nine things — four casts from vitalik.eth, a merged GitHub PR, and three wallet moves on Base.'.split(' ');

window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.3);
  let coverAcc=acc, wipeX=200; const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:INTRO+k*BEAT,c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=D[active].kick;wm.style.fontSize=Math.max(90,Math.min(320,900/(0.6*D[active].kick.length)))+'px'; wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc; const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head'); he.textContent=D[active].head; const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT, cl=t-cbs, cin=clamp01((cl-0.12)/0.6); const beatEnd=INTRO+(i+1)*BEAT, outp=clamp01((t-(beatEnd-0.3))/0.4); let op=(i===active?1:0)*clamp01(cl/0.15); if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25)); const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5; const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4; c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active, pIn, t);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1; ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function stagger(sel,p,step,dur,rise){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*step)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*(rise||24))+'px)';});}
function animateComp(i,p,t){
  if(i===0){
    const qn=Math.round(AQ.length*clamp01(p/0.3)); document.getElementById('aq').textContent=AQ.slice(0,qn);
    document.getElementById('acaret').style.opacity=(p<0.36&&Math.floor(t*2)%2)?1:0;
    const ap=clamp01((p-0.38)/0.42), nw=Math.round(AANS.length*ap);
    document.getElementById('aans').innerHTML=AANS.slice(0,nw).join(' ').replace('vitalik.eth','<b>vitalik.eth</b>').replace('GitHub','<b>GitHub</b>').replace('Base.','<b>Base</b>.');
    document.querySelectorAll('#comp0 .acite span').forEach((s,k)=>{const cp=clamp01((p-0.84-k*0.05)/0.14);s.style.opacity=cp;s.style.transform='translateY('+((1-easeOut(cp))*12)+'px)';});
  } else if(i===1){ stagger('#comp1 .srow',p,0.12,0.36,22); const m=document.getElementById('ansmeta'); m.style.opacity=clamp01((p-0.6)/0.3); m.textContent='6 things · on-device · 0.8s'; }
  else if(i===2){ stagger('#comp2 .srow',p,0.13,0.36,22); }
  else if(i===3){ document.querySelectorAll('#comp3 .ttile').forEach((s,k)=>{const cp=clamp01((p-k*0.08)/0.4);s.style.opacity=cp;s.style.transform='scale('+(0.6+0.4*back(cp))+') translateY('+((1-easeOut(cp))*20)+'px)';}); }
  else if(i===4){ document.querySelectorAll('#comp4 .pchk').forEach((r,k)=>{const rp=clamp01((p-0.2-k*0.16)/0.35);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';}); }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-ask-live.html'),html);
console.log('wrote clip-ask-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
