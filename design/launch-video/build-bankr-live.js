// Bankr promo — live-animated UI (no screenshots), editorial frame.
// node render.js clip-bankr-live.html --size=1080x1920
const fs=require('fs'), path=require('path');
const AS='/Users/alexanderchopan/Developer/casberi/Casberi/Casberi/Assets.xcassets';
const ico=n=>'data:image/png;base64,'+fs.readFileSync(path.join(AS,'brand-'+n+'.imageset','icon.png')).toString('base64');
const AC='#8B5CF6', OR='#FF6D3D', OK='#3fb950';
const BEATS=[
  {kick:'STORE',    head:'Find it in\nthe store.',   accent:AC},
  {kick:'CONNECT',  head:'Paste a\nread-only key.',  accent:AC},
  {kick:'ASK',      head:'Try it with\nyour key.',   accent:AC},
  {kick:'GROUNDED', head:'It weighs\nyour wallet.',  accent:AC},
  {kick:'SAFE',     head:'Answer only.\nNever trades.',accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
const SHELF=['chatgpt','claude','gemini','venice','bankr'];

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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:126px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#131019;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;}
/* store shelf */
.shelf{display:flex;gap:24px;margin-bottom:44px;}
.stile{width:126px;height:126px;border-radius:30px;overflow:hidden;will-change:opacity,transform;box-shadow:0 10px 26px rgba(0,0,0,.4);position:relative;}
.stile img{width:100%;height:100%;display:block;}
.stile.on{box-shadow:0 0 0 5px ${AC}, 0 14px 34px rgba(0,0,0,.5);}
.offer{display:flex;align-items:center;gap:26px;background:#0b0910;border-radius:26px;padding:28px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.07);will-change:opacity,transform;}
.offer .lg{width:104px;height:104px;border-radius:24px;overflow:hidden;flex:none;}
.offer .lg img{width:100%;height:100%;display:block;}
.on2{font-size:44px;font-weight:750;} .ot{font-size:29px;color:rgba(255,255,255,.55);margin-top:6px;}
.obtn{margin-left:auto;background:${AC};color:#fff;font-weight:750;font-size:30px;padding:20px 40px;border-radius:100px;will-change:transform;}
/* steps + key */
.step{display:flex;gap:20px;align-items:flex-start;margin-bottom:22px;font-size:29px;line-height:1.35;color:rgba(255,255,255,.85);will-change:opacity,transform;}
.step i{width:44px;height:44px;border-radius:50%;background:${AC};color:#fff;font-size:24px;font-weight:800;display:flex;align-items:center;justify-content:center;flex:none;font-style:normal;}
.kfield{margin-top:14px;background:#0b0910;border:2px solid rgba(255,255,255,.14);border-radius:22px;padding:28px 32px;font-size:36px;display:flex;align-items:center;min-height:96px;letter-spacing:.1em;}
.kcaret{display:inline-block;width:4px;height:38px;background:${AC};margin-left:4px;}
.kbtn{margin-top:26px;background:${AC};color:#fff;font-weight:750;font-size:32px;padding:22px 46px;border-radius:100px;display:inline-block;will-change:opacity;}
.kok{margin-top:26px;font-size:29px;color:${OK};display:flex;align-items:center;gap:14px;will-change:opacity,transform;}
.kok i{width:38px;height:38px;border-radius:50%;background:${OK};color:#04140a;display:flex;align-items:center;justify-content:center;font-size:24px;font-style:normal;}
/* composer */
.abar{display:flex;align-items:center;gap:20px;background:#0b0910;border:2px solid rgba(255,255,255,.12);border-radius:24px;padding:26px 30px;font-size:34px;}
.spark{color:${AC};font-size:36px;}
.acaret{display:inline-block;width:4px;height:36px;background:#fff;margin-left:3px;}
.ans{margin-top:32px;font-size:36px;line-height:1.38;color:rgba(255,255,255,.9);}
.verbs{display:flex;gap:16px;margin-top:34px;}
.verb{font-size:27px;font-weight:650;padding:16px 30px;border-radius:100px;background:rgba(255,255,255,.08);color:rgba(255,255,255,.6);display:flex;align-items:center;gap:12px;will-change:opacity,transform,background;}
.verb img{width:32px;height:32px;border-radius:8px;}
/* grounded */
.badge{display:flex;align-items:center;gap:16px;margin-bottom:24px;}
.badge img{width:56px;height:56px;border-radius:14px;}
.badge span{font-size:30px;font-weight:700;color:${AC};}
.gans{font-size:40px;line-height:1.36;font-weight:500;} .gans b{color:${OR};}
.gchips{display:flex;gap:14px;margin-top:34px;}
.gchips span{font-size:25px;font-weight:650;padding:14px 26px;border-radius:100px;background:${AC}26;color:#c9b6ff;will-change:opacity,transform;}
/* safe */
.big{font-size:76px;font-weight:800;letter-spacing:-.03em;color:${OR};line-height:1.02;}
.chk{font-size:38px;display:flex;align-items:center;gap:18px;font-weight:600;will-change:opacity,transform;}
.chk i{width:44px;height:44px;border-radius:50%;background:${OK};color:#04140a;display:flex;align-items:center;justify-content:center;font-size:26px;flex:none;font-style:normal;}
.note{font-size:27px;color:rgba(255,255,255,.5);line-height:1.4;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>BANKR</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">APPS · AGENTS</div>
    <div class="shelf">${SHELF.map((n,i)=>`<div class="stile${n==='bankr'?' on':''}" data-i="${i}"><img src="${ico(n)}"></div>`).join('')}</div>
    <div class="offer" id="offer"><div class="lg"><img src="${ico('bankr')}"></div><div><div class="on2">Bankr</div><div class="ot">Answers that know your wallet</div></div><div class="obtn" id="obtn">Connect</div></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">GET YOUR KEY</div>
    <div class="step" data-i="0"><i>1</i><div>At <b>bankr.bot/api-keys</b>, sign in and create a key.</div></div>
    <div class="step" data-i="1"><i>2</i><div>Make it <b>read-only</b>, and enable agent access.</div></div>
    <div class="step" data-i="2"><i>3</i><div>Paste it below — it's checked with Bankr before it saves.</div></div>
    <div class="kfield mono"><span id="ktype"></span><span class="kcaret" id="kcaret"></span></div>
    <div class="kbtn" id="kbtn">Connect</div>
    <div class="kok" id="kok"><i>✓</i> Connected — answers now offer "Try with your key".</div>
  </div>

  <div class="comp" id="comp2">
    <div class="abar"><span class="spark">✦</span><span id="aq"></span><span class="acaret" id="acaret"></span></div>
    <div class="ans" id="ans"></div>
    <div class="verbs">
      <div class="verb" data-i="0">Keep</div>
      <div class="verb" data-i="1" id="vkey"><img src="${ico('bankr')}">Try with your key</div>
    </div>
  </div>

  <div class="comp" id="comp3">
    <div class="badge" id="gbadge"><img src="${ico('bankr')}"><span>Bankr</span></div>
    <div class="gans" id="gans"></div>
    <div class="gchips"><span data-i="0">Your wallet</span><span data-i="1">Live markets</span></div>
  </div>

  <div class="comp" id="comp4">
    <div style="display:flex;flex-direction:column;gap:34px;height:100%;justify-content:center">
      <div class="shd mono" style="margin:0">EVERY QUESTION SAYS</div>
      <div class="big">"answer only"</div>
      <div style="display:flex;flex-direction:column;gap:22px">
        <div class="chk" data-i="0"><i>✓</i> Never trades</div>
        <div class="chk" data-i="1"><i>✓</i> Never sends</div>
        <div class="chk" data-i="2"><i>✓</i> Never swaps</div>
      </div>
      <div class="note" data-i="3">Read-only key, kept in your Keychain. It goes only to Bankr, and Bankr bills you directly.</div>
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
const comps=[...document.querySelectorAll('.comp')];
const KEY='bankr-agent-7f3c9a21e8', AQ="How's my portfolio doing?";
const A1='Six wallet moves this week, mostly on Base.';
const GA='You hold 3.2 ETH and $14.2k in stables. ETH is up 4.1% today — your position is up about $420 since Monday.'.split(' ');
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
    document.querySelectorAll('#comp0 .stile').forEach((s,k)=>{const cp=clamp01((p-k*0.09)/0.35);s.style.opacity=cp;s.style.transform='scale('+(0.5+0.5*back(cp))+')';});
    const of=document.getElementById('offer');const op=clamp01((p-0.5)/0.35);of.style.opacity=op;of.style.transform='translateY('+((1-back(op))*40)+'px)';
    const b=document.getElementById('obtn');const bp=clamp01((p-0.75)/0.25);b.style.transform='scale('+(1+0.07*Math.sin(bp*Math.PI))+')';
  } else if(i===1){
    document.querySelectorAll('#comp1 .step').forEach((s,k)=>{const cp=clamp01((p-k*0.1)/0.3);s.style.opacity=cp;s.style.transform='translateX('+((1-easeOut(cp))*-26)+'px)';});
    const n=Math.round(KEY.length*clamp01((p-0.34)/0.3));
    document.getElementById('ktype').textContent='•'.repeat(n);
    document.getElementById('kcaret').style.opacity=(p<0.68&&Math.floor(t*2)%2)?1:0;
    const bp=clamp01((p-0.66)/0.12); const btn=document.getElementById('kbtn');
    btn.textContent=(p>0.78?'Checking…':'Connect'); btn.style.opacity=(p>0.9?0:bp);
    const ok=document.getElementById('kok');const okp=clamp01((p-0.9)/0.1);ok.style.opacity=okp;ok.style.transform='translateY('+((1-easeOut(okp))*14)+'px)';
  } else if(i===2){
    const n=Math.round(AQ.length*clamp01(p/0.3));document.getElementById('aq').textContent=AQ.slice(0,n);
    document.getElementById('acaret').style.opacity=(p<0.34&&Math.floor(t*2)%2)?1:0;
    document.getElementById('ans').textContent=(p>0.4?A1:'');
    document.getElementById('ans').style.opacity=clamp01((p-0.4)/0.2);
    document.querySelectorAll('#comp2 .verb').forEach((v,k)=>{const cp=clamp01((p-0.6-k*0.08)/0.2);v.style.opacity=cp;v.style.transform='translateY('+((1-easeOut(cp))*14)+'px)';});
    const vk=document.getElementById('vkey');const hp=clamp01((p-0.82)/0.18);
    if(hp>0){vk.style.background='${AC}';vk.style.color='#fff';vk.style.transform='scale('+(1+0.06*Math.sin(hp*Math.PI))+')';}
  } else if(i===3){
    const bd=document.getElementById('gbadge');const bp=clamp01(p/0.25);bd.style.opacity=bp;bd.style.transform='translateY('+((1-easeOut(bp))*16)+'px)';
    const ap=clamp01((p-0.2)/0.6),nw=Math.round(GA.length*ap);
    document.getElementById('gans').innerHTML=GA.slice(0,nw).join(' ').replace('3.2 ETH','<b>3.2 ETH</b>').replace('4.1%','<b>4.1%</b>').replace('$420','<b>$420</b>');
    document.querySelectorAll('#comp3 .gchips span').forEach((s,k)=>{const cp=clamp01((p-0.82-k*0.06)/0.14);s.style.opacity=cp;s.style.transform='translateY('+((1-easeOut(cp))*12)+'px)';});
  } else if(i===4){
    document.querySelectorAll('#comp4 .chk, #comp4 .note').forEach((r,k)=>{const rp=clamp01((p-0.15-k*0.14)/0.3);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-28)+'px)';const ic=r.querySelector('i');if(ic)ic.style.transform='scale('+(0.4+0.6*back(rp))+')';});
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-bankr-live.html'),html);
console.log('wrote clip-bankr-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
