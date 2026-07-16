// Farcaster promo — live-animated UI (no screenshots) in the editorial frame.
// node render.js clip-farcaster-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');
const AVDIR = '/Users/alexanderchopan/Developer/casberi/scratchpad/fc-avatars';
const av = n => 'data:image/png;base64,' + fs.readFileSync(path.join(AVDIR, n + '.png')).toString('base64');

const PUR = '#7C4DEC', PUR2 = '#5B32C0';
const BEATS = [
  { kick: 'CONNECT',  head: 'Just a\nusername.',  accent: PUR },
  { kick: 'ACCOUNTS', head: 'Follow\nanyone.',    accent: PUR },
  { kick: 'FEED',     head: 'Every\ncast.',        accent: PUR },
  { kick: 'REPLIES',  head: 'The whole\nthread.',  accent: PUR },
  { kick: 'HOME',     head: 'All on your\nHome.',  accent: PUR },
];
const INTRO = 0.45, BEAT = 1.9;
const OUT_AT = INTRO + BEATS.length * BEAT;
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map((b, i) => ({ kick: (i + 1 < 10 ? '0' : '') + (i + 1) + ' · ' + b.kick, head: b.head, accent: b.accent }));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
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
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:54px;color:#fff;}
.comp.pur{background:linear-gradient(160deg,#7C4DEC,#5B32C0);}
.comp.dark{background:#100e17;}
.av{border-radius:50%;flex:none;background:#2a2440 center/cover no-repeat;}
.av.g1{background:radial-gradient(circle at 38% 32%,#8fd6b0,#1f8f66 72%);}
.av.g2{background:radial-gradient(circle at 38% 32%,#f0b48a,#c26a2a 72%);}
.av.g3{background:radial-gradient(circle at 38% 32%,#9ab6f0,#2f5bc0 72%);}
.av.g4{background:radial-gradient(circle at 38% 32%,#e79ad0,#a83b86 72%);}

/* connect */
.fmark{width:120px;height:120px;border-radius:30px;background:rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center;}
.fmark svg{width:66px;height:66px;}
.ftitle{font-size:52px;font-weight:750;margin-top:36px;line-height:1.06;letter-spacing:-.02em;}
.ffield{margin-top:44px;background:rgba(255,255,255,.14);border-radius:22px;padding:30px 34px;font-size:38px;display:flex;align-items:center;min-height:100px;}
.pre{color:rgba(255,255,255,.5);}
.caret{width:4px;height:44px;background:#fff;margin-left:4px;}
.fbtn{margin-top:36px;align-self:flex-start;background:#fff;color:#5B32C0;font-weight:700;font-size:36px;padding:26px 54px;border-radius:24px;display:inline-block;will-change:transform;}

/* account row + chips */
.acc{display:flex;align-items:center;gap:30px;will-change:transform,opacity;}
.acc .av{width:100px;height:100px;}
.an{font-size:52px;font-weight:700;}
.ah{font-size:30px;color:rgba(255,255,255,.55);margin-top:6px;}
.chips{display:flex;gap:22px;margin-top:44px;}
.chip{font-size:34px;font-weight:600;padding:20px 44px;border-radius:100px;background:rgba(255,255,255,.09);color:rgba(255,255,255,.6);will-change:background,color,transform;}
.chipnote{font-size:28px;color:rgba(255,255,255,.5);margin-top:40px;line-height:1.4;}

/* casts / replies */
.rhead{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.55);margin-bottom:14px;}
.cast{display:flex;gap:24px;padding:26px 0;will-change:transform,opacity;border-top:2px solid rgba(255,255,255,.08);}
.cast:first-of-type{border-top:none;}
.cast .av{width:70px;height:70px;}
.ch{font-size:28px;color:rgba(255,255,255,.55);margin-bottom:8px;}
.ct{font-size:38px;line-height:1.24;font-weight:500;}
.reply{display:flex;gap:22px;padding:20px 0;will-change:transform,opacity;}
.reply .av{width:58px;height:58px;}
.rh{font-size:26px;color:rgba(255,255,255,.55);}
.rt{font-size:34px;margin-top:5px;line-height:1.2;}
.htitle{font-size:44px;font-weight:750;margin-bottom:20px;}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:#7C4DEC;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>FARCASTER</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp pur" id="comp0">
    <div class="fmark"><svg viewBox="0 0 100 100" fill="none" stroke="#fff" stroke-width="9" stroke-linecap="round"><path d="M20 26 h60"/><path d="M28 26 V80"/><path d="M72 26 V80"/><path d="M28 44 a22 22 0 0 1 44 0"/></svg></div>
    <div class="ftitle">Track any Farcaster account</div>
    <div class="ffield mono"><span class="pre">farcaster.xyz/</span><span id="ftype"></span><span class="caret" id="caret"></span></div>
    <div class="fbtn" id="fbtn">Connect</div>
  </div>

  <div class="comp dark" id="comp1">
    <div class="acc" id="acc"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="an">Vitalik Buterin</div><div class="ah mono">@vitalik.eth · hullo</div></div></div>
    <div class="chips"><div class="chip" data-i="0">Likes</div><div class="chip" data-i="1">Mentions</div></div>
    <div class="chipnote">Their casts — plus the ones they like and get mentioned in — all land here.</div>
  </div>

  <div class="comp dark" id="comp2">
    <div class="cast" data-i="0"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="ch mono">vitalik.eth · 4d</div><div class="ct">One thing I find striking in the discourse between AI 2040 and its detractors…</div></div></div>
    <div class="cast" data-i="1"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="ch mono">vitalik.eth · 7d</div><div class="ct">They are trying to push Chat Control through again.</div></div></div>
    <div class="cast" data-i="2"><div class="av" style="background-image:url('${av('july')}')"></div><div><div class="ch mono">july · 8d</div><div class="ct">The shi in question.</div></div></div>
  </div>

  <div class="comp dark" id="comp3">
    <div class="cast" data-i="0" style="padding-top:0"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="ch mono">vitalik.eth · 7d</div><div class="ct">They are trying to push Chat Control through again.</div></div></div>
    <div class="rhead mono" style="margin-top:22px">REPLIES · 8+</div>
    <div class="reply" data-i="0"><div class="av" style="background-image:url('${av('omghaxeth')}')"></div><div><div class="rh mono">@omghax.eth</div><div class="rt">OOF…</div></div></div>
    <div class="reply" data-i="1"><div class="av" style="background-image:url('${av('strangesmell')}')"></div><div><div class="rh mono">@strangesmell</div><div class="rt">I hate the world we have built…</div></div></div>
    <div class="reply" data-i="2"><div class="av" style="background-image:url('${av('aldinias')}')"></div><div><div class="rh mono">@aldinias</div><div class="rt">again? feels like they just keep retrying.</div></div></div>
    <div class="reply" data-i="3"><div class="av" style="background-image:url('${av('mooneth')}')"></div><div><div class="rh mono">@moon.eth</div><div class="rt">They will never stop.</div></div></div>
  </div>

  <div class="comp dark" id="comp4">
    <div class="htitle">Recent posts</div>
    <div class="cast" data-i="0"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="ch mono">vitalik.eth</div><div class="ct">One thing I find striking in the discourse between AI 2040…</div></div></div>
    <div class="cast" data-i="1"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="ch mono">vitalik.eth</div><div class="ct">They are trying to push Chat Control through again.</div></div></div>
    <div class="cast" data-i="2"><div class="av" style="background-image:url('${av('july')}')"></div><div><div class="ch mono">july</div><div class="ct">The shi in question.</div></div></div>
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
const HANDLE='vitalik.eth';

window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent;
  const pIn=clamp01((local-0.28)/1.25);

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

function stagger(sel, p, step, dur, rise){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*step)/dur); r.style.opacity=rp; r.style.transform='translateY('+((1-easeOut(rp))*(rise||24))+'px)';
  });
}
function animateComp(i,p,t){
  if(i===0){
    const n=Math.round(HANDLE.length*clamp01(p/0.6));
    document.getElementById('ftype').textContent=HANDLE.slice(0,n);
    document.getElementById('caret').style.opacity=(Math.floor(t*2)%2)?1:0.2;
    const bp=clamp01((p-0.62)/0.3); const pulse=1+0.06*Math.sin(clamp01((p-0.62)/0.38)*Math.PI);
    const btn=document.getElementById('fbtn'); btn.style.opacity=bp; btn.style.transform='scale('+(bp?pulse:0.9)+')';
  } else if(i===1){
    const a=document.getElementById('acc'); const ap=clamp01(p/0.4); a.style.opacity=ap; a.style.transform='translateX('+((1-easeOut(ap))*-40)+'px)';
    document.querySelectorAll('#comp1 .chip').forEach((c,k)=>{
      const cp=clamp01((p-0.4-k*0.16)/0.3);
      c.style.background=cp>0.5?'#7C4DEC':'rgba(255,255,255,.09)';
      c.style.color=cp>0.5?'#fff':'rgba(255,255,255,.6)';
      c.style.transform='scale('+(0.9+0.1*easeOut(cp))+')';
    });
  } else if(i===2){ stagger('#comp2 .cast', p, 0.16, 0.4, 26); }
  else if(i===3){
    const c0=document.querySelector('#comp3 .cast'); const cp=clamp01(p/0.35); c0.style.opacity=cp; c0.style.transform='translateY('+((1-easeOut(cp))*20)+'px)';
    document.querySelector('#comp3 .rhead').style.opacity=clamp01((p-0.3)/0.2);
    document.querySelectorAll('#comp3 .reply').forEach((r,k)=>{
      const rp=clamp01((p-0.4-k*0.13)/0.32); r.style.opacity=rp; r.style.transform='translateY('+((1-easeOut(rp))*22)+'px)';
      r.querySelector('.av').style.transform='scale('+(0.5+0.5*back(rp))+')';
    });
  }
  else if(i===4){ document.querySelector('#comp4 .htitle').style.opacity=clamp01(p/0.25); stagger('#comp4 .cast', p, 0.16, 0.4, 26); }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-farcaster-live.html'), html);
console.log('wrote clip-farcaster-live.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
