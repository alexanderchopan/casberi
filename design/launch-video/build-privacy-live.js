// Privacy / on-device promo — live-animated. node render.js clip-privacy-live.html --size=1080x1920
const fs=require('fs'), path=require('path');
const AC='#10B981';
const BEATS=[
  {kick:'NO ACCOUNT', head:'No account.\nEver.',      accent:AC},
  {kick:'ON-DEVICE',  head:'Runs on\nyour phone.',     accent:AC},
  {kick:'WATCH-ONLY', head:'Watch-only\nwallets.',      accent:AC},
  {kick:'LOCAL',      head:'Your things,\nyour iCloud.',accent:AC},
  {kick:'CONTROL',    head:'Delete it all,\nany time.', accent:AC},
];
const INTRO=0.45,BEAT=1.9,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));

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
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:56px;color:#fff;background:#0c1512;}
.pv{display:flex;flex-direction:column;gap:34px;height:100%;}
.chk{font-size:46px;display:flex;align-items:center;gap:24px;font-weight:600;will-change:opacity,transform;}
.chk i{width:52px;height:52px;border-radius:50%;background:${AC};color:#04140a;display:flex;align-items:center;justify-content:center;font-size:32px;flex:none;}
.psub{font-size:32px;color:rgba(255,255,255,.5);}
.lock{width:150px;height:150px;border-radius:38px;background:${AC}22;display:flex;align-items:center;justify-content:center;}
.lock svg{width:84px;height:84px;stroke:${AC};}
.zlabel{font-size:30px;letter-spacing:.14em;color:rgba(255,255,255,.5);}
.zero{font-size:220px;font-weight:800;line-height:.9;color:${AC};letter-spacing:-.04em;}
.pbig{font-size:56px;font-weight:750;line-height:1.06;}
.wrow{display:flex;align-items:center;gap:30px;}
.keybox{width:150px;height:150px;border-radius:30px;background:#101d19;display:flex;align-items:center;justify-content:center;position:relative;flex:none;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.keybox svg{width:80px;height:80px;stroke:rgba(255,255,255,.55);}
.slash{position:absolute;left:22px;top:22px;width:106px;height:106px;}
.slash line{stroke:${DN='#f85149'};stroke-width:10;stroke-linecap:round;}
.addr{font-size:34px;} .addr .lbl{color:rgba(255,255,255,.5);font-size:28px;margin-bottom:8px;}
.chips{display:flex;gap:18px;margin-top:8px;flex-wrap:wrap;}
.chips span{font-size:30px;font-weight:650;padding:16px 28px;border-radius:100px;background:${AC}22;color:${AC};will-change:opacity,transform;}
.drow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.08);font-size:40px;font-weight:600;will-change:opacity,transform;} .drow:first-of-type{border-top:none;}
.drow .x{margin-left:auto;color:${DN};font-size:34px;}
.done{margin-top:34px;font-size:52px;font-weight:750;color:${AC};will-change:opacity,transform;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;} .outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>PRIVACY</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="pv" style="justify-content:center">
      <div class="chk" data-i="0"><i>✓</i> No email</div>
      <div class="chk" data-i="1"><i>✓</i> No password</div>
      <div class="chk" data-i="2"><i>✓</i> No sign-up</div>
      <div class="psub" data-i="3" style="margin-top:14px">Just connect the apps you want.</div>
    </div>
  </div>

  <div class="comp" id="comp1">
    <div class="pv" style="justify-content:center;gap:26px">
      <div class="lock" id="lock1"><svg viewBox="0 0 24 24" fill="none" stroke-width="2"><rect x="5" y="11" width="14" height="9" rx="2.5"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11"/></svg></div>
      <div class="zlabel mono">REQUESTS TO OUR SERVERS</div>
      <div class="zero" id="zero">0</div>
      <div class="psub">The model runs on your iPhone — nothing leaves.</div>
    </div>
  </div>

  <div class="comp" id="comp2">
    <div class="pv" style="justify-content:center;gap:40px">
      <div class="wrow">
        <div class="keybox"><svg viewBox="0 0 24 24" fill="none" stroke-width="2"><circle cx="8" cy="9" r="4"/><path d="M11 12 L20 21 M17 18 l3 -3 M14 15 l2 -2"/></svg>
          <svg class="slash"><line id="slashln" x1="10" y1="96" x2="96" y2="10"/></svg></div>
        <div class="addr"><div class="lbl mono">WATCHING</div>0xd8dA…6045</div>
      </div>
      <div class="chips"><span data-i="0">No keys</span><span data-i="1">No trades</span><span data-i="2">Read-only</span></div>
    </div>
  </div>

  <div class="comp" id="comp3">
    <div class="pv" style="justify-content:center;gap:30px">
      <div class="lock"><svg viewBox="0 0 24 24" fill="none" stroke-width="2"><rect x="5" y="11" width="14" height="9" rx="2.5"/><path d="M8 11V7.5a4 4 0 0 1 8 0V11"/></svg></div>
      <div class="pbig">Your corpus lives on your device.</div>
      <div style="display:flex;flex-direction:column;gap:22px">
        <div class="chk" data-i="0" style="font-size:38px"><i>✓</i> Synced through your iCloud</div>
        <div class="chk" data-i="1" style="font-size:38px"><i>✓</i> Never our servers</div>
        <div class="chk" data-i="2" style="font-size:38px"><i>✓</i> Works offline</div>
      </div>
    </div>
  </div>

  <div class="comp" id="comp4">
    <div class="pv" style="justify-content:center">
      <div class="zlabel mono" style="margin-bottom:6px">DELETE EVERYTHING</div>
      <div class="drow" data-i="0">All your things <span class="x">removed</span></div>
      <div class="drow" data-i="1">All app access <span class="x">removed</span></div>
      <div class="drow" data-i="2">iCloud zone <span class="x">purged</span></div>
      <div class="done" id="done">Gone. Nothing kept.</div>
    </div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.3);
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
function chk(sel,p,step,dur){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*step)/dur);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-34)+'px)';const ic=r.querySelector('i');if(ic)ic.style.transform='scale('+(0.4+0.6*back(rp))+')';});}
function animateComp(i,p,t){
  if(i===0){chk('#comp0 .chk, #comp0 .psub',p,0.16,0.35);}
  else if(i===1){const lk=document.getElementById('lock1');const lp=clamp01(p/0.4);lk.style.transform='scale('+(0.5+0.5*back(lp))+')';lk.style.opacity=lp;const z=document.getElementById('zero');const zp=clamp01((p-0.35)/0.35);z.style.transform='scale('+(0.6+0.4*back(zp))+')';z.style.opacity=zp;}
  else if(i===2){const s=document.getElementById('slashln');const L=130;s.style.strokeDasharray=L;s.style.strokeDashoffset=L*(1-clamp01((p-0.3)/0.35));document.querySelectorAll('#comp2 .chips span').forEach((c,k)=>{const cp=clamp01((p-0.55-k*0.1)/0.25);c.style.opacity=cp;c.style.transform='translateY('+((1-easeOut(cp))*14)+'px) scale('+(0.85+0.15*easeOut(cp))+')';});}
  else if(i===3){chk('#comp3 .chk',p,0.16,0.35);}
  else if(i===4){document.querySelectorAll('#comp4 .drow').forEach((r,k)=>{const inp=clamp01((p-k*0.12)/0.3);const outp=clamp01((p-0.5-k*0.1)/0.3);r.style.opacity=inp*(1-outp);r.style.transform='translateX('+(easeOut(outp)*120)+'px)';});const dn=document.getElementById('done');const dp=clamp01((p-0.8)/0.2);dn.style.opacity=dp;dn.style.transform='scale('+(0.8+0.2*back(dp))+')';}
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-privacy-live.html'),html);
console.log('wrote clip-privacy-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
