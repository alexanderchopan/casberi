// Farcaster promo — live-animated UI (no screenshots) in the editorial frame.
// node render.js clip-farcaster-live.html --size=1080x1920
// Refreshed 2026-07-17 for the newest social features:
//   prd 74 — likes / mentions / channels as watch targets
//   prd 81 — "the post itself, why it's here, the people behind it":
//     full postText, socialContext markers ("Liked" / "Mentions you" / "/design"
//     channel — channel wins), quote/parent SocialCard, like/repost/replyCount
//   prd 87 — "Who they follow": the follow graph as a PICKER, not a mirror
//     (a measured account follows 1,848; nothing is auto-watched)
// Marker strings verbatim from ShapedRows/SocialBridge: "Liked","Mentions you","/design".
const fs = require('fs');
const path = require('path');
const AVDIR = '/Users/alexanderchopan/Developer/casberi/scratchpad/fc-avatars';
const av = n => 'data:image/png;base64,' + fs.readFileSync(path.join(AVDIR, n + '.png')).toString('base64');

const PUR = '#7C4DEC', PUR2 = '#5B32C0';
const BEATS = [
  { kick: 'CONNECT',  head: 'Just a\nusername.',   accent: PUR },
  { kick: 'WATCH',    head: 'Casts, likes,\nmentions.', accent: PUR },
  { kick: 'CONTEXT',  head: "Why it's\nhere.",       accent: PUR },
  { kick: 'THE POST', head: 'The whole\npost.',      accent: PUR },
  { kick: 'FOLLOWS',  head: 'Who they\nfollow.',     accent: PUR },
];
const INTRO = 0.45, BEAT = 2.0;
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:126px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:54px;color:#fff;}
.comp.pur{background:linear-gradient(160deg,#7C4DEC,#5B32C0);}
.comp.dark{background:#100e17;}
.av{border-radius:50%;flex:none;background:#2a2440 center/cover no-repeat;}

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
.an{font-size:50px;font-weight:700;}
.ah{font-size:30px;color:rgba(255,255,255,.55);margin-top:6px;}
.chips{display:flex;gap:20px;margin-top:44px;flex-wrap:wrap;}
.chip{font-size:32px;font-weight:600;padding:18px 40px;border-radius:100px;background:rgba(255,255,255,.09);color:rgba(255,255,255,.6);will-change:background,color,transform;}
.chipnote{font-size:28px;color:rgba(255,255,255,.5);margin-top:40px;line-height:1.4;}

/* context rows — why it's here */
.crow{display:flex;align-items:center;gap:24px;padding:28px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.crow:first-of-type{border-top:none;}
.crow .av{width:76px;height:76px;}
.cn{font-size:28px;color:rgba(255,255,255,.55);margin-bottom:7px;}
.cx{font-size:33px;line-height:1.22;font-weight:500;}
.mk{margin-left:auto;flex:none;font-size:25px;font-weight:700;padding:11px 24px;border-radius:100px;}
.mk.like{background:rgba(255,92,122,.16);color:#ff8fa3;}
.mk.chan{background:rgba(124,77,236,.22);color:#c3aef8;}
.mk.ment{background:rgba(63,185,80,.16);color:#7ee08a;}
.cnote{margin-top:32px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.cnote b{color:#fff;}

/* the post — enriched */
.ptop{display:flex;gap:24px;align-items:center;will-change:opacity,transform;}
.ptop .av{width:82px;height:82px;}
.ph{font-size:30px;color:rgba(255,255,255,.55);}
.pn{font-size:38px;font-weight:700;}
.ptext{font-size:37px;line-height:1.32;font-weight:500;margin-top:26px;will-change:opacity,transform;}
.quote{margin-top:28px;border-radius:20px;padding:26px 28px;background:rgba(255,255,255,.06);box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;gap:18px;align-items:flex-start;will-change:opacity,transform;}
.quote .av{width:52px;height:52px;}
.qn{font-size:26px;color:rgba(255,255,255,.55);margin-bottom:6px;}
.qt{font-size:30px;line-height:1.25;}
.counts{display:flex;gap:44px;margin-top:34px;font-size:31px;color:rgba(255,255,255,.6);font-weight:600;will-change:opacity;}
.counts b{color:#fff;}

/* follow picker */
.fhead{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.55);margin-bottom:20px;}
.prow{display:flex;align-items:center;gap:24px;padding:22px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.prow:first-of-type{border-top:none;}
.prow .av{width:76px;height:76px;}
.pnm{font-size:36px;font-weight:650;} .phn{font-size:25px;color:rgba(255,255,255,.45);margin-top:4px;}
.watch{margin-left:auto;flex:none;font-size:28px;font-weight:700;padding:14px 34px;border-radius:100px;background:rgba(255,255,255,.1);color:rgba(255,255,255,.75);will-change:background,color,transform;}
.watch.on{background:#fff;color:#5B32C0;}
.fnote{margin-top:26px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.fnote b{color:#fff;}

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
    <div class="chips"><div class="chip" data-i="0">Casts</div><div class="chip" data-i="1">Likes</div><div class="chip" data-i="2">Mentions</div><div class="chip" data-i="3">Channels</div></div>
    <div class="chipnote">Their casts — plus the ones they like, get mentioned in, and the channels they post to. All land in your feed.</div>
  </div>

  <div class="comp dark" id="comp2">
    <div class="crow" data-i="0"><div class="av" style="background-image:url('${av('july')}')"></div><div><div class="cn mono">july · 8d</div><div class="cx">The shi in question.</div></div><span class="mk like">Liked</span></div>
    <div class="crow" data-i="1"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="cn mono">vitalik.eth · 4d</div><div class="cx">Some notes on the protocol's design tradeoffs…</div></div><span class="mk chan">/design</span></div>
    <div class="crow" data-i="2"><div class="av" style="background-image:url('${av('omghaxeth')}')"></div><div><div class="cn mono">omghax.eth · 2d</div><div class="cx">@vitalik.eth what do you make of this?</div></div><span class="mk ment">Mentions you</span></div>
    <div class="cnote" id="cnote">Every post says <b>why it landed</b> — a like, a mention, or the channel it's in.</div>
  </div>

  <div class="comp dark" id="comp3">
    <div class="ptop" id="ptop"><div class="av" style="background-image:url('${av('vitaliketh')}')"></div><div><div class="pn">vitalik.eth</div><div class="ph mono">@vitalik.eth · 4d</div></div></div>
    <div class="ptext" id="ptext">One thing I find striking in the discourse between AI 2040 and its detractors is how much both sides agree on the facts, and differ only on the framing.</div>
    <div class="quote" id="quote"><div class="av" style="background-image:url('${av('july')}')"></div><div><div class="qn mono">july</div><div class="qt">the shi in question.</div></div></div>
    <div class="counts mono" id="counts"><span>♥ <b>1,240</b></span><span>↺ <b>340</b></span><span>💬 <b>89</b></span></div>
  </div>

  <div class="comp dark" id="comp4">
    <div class="fhead mono">VITALIK.ETH FOLLOWS · 1,848</div>
    <div class="prow" data-i="0"><div class="av" style="background-image:url('${av('july')}')"></div><div><div class="pnm">july</div><div class="phn mono">@july</div></div><span class="watch" data-w>Watch</span></div>
    <div class="prow" data-i="1"><div class="av" style="background-image:url('${av('omghaxeth')}')"></div><div><div class="pnm">omghax.eth</div><div class="phn mono">@omghax.eth</div></div><span class="watch" data-w>Watch</span></div>
    <div class="prow" data-i="2"><div class="av" style="background-image:url('${av('strangesmell')}')"></div><div><div class="pnm">strangesmell</div><div class="phn mono">@strangesmell</div></div><span class="watch" data-w>Watch</span></div>
    <div class="prow" data-i="3"><div class="av" style="background-image:url('${av('aldinias')}')"></div><div><div class="pnm">aldinias</div><div class="phn mono">@aldinias</div></div><span class="watch" data-w>Watch</span></div>
    <div class="fnote" id="fnote">Bring in who they follow — <b>you pick</b> who to watch. Nothing's auto-followed.</div>
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
  const pIn=clamp01((local-0.28)/1.35);

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
    const rp=clamp01((p-k*step)/dur); r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';
  });
}
function animateComp(i,p,t){
  if(i===0){
    const n=Math.round(HANDLE.length*clamp01(p/0.55));
    document.getElementById('ftype').textContent=HANDLE.slice(0,n);
    document.getElementById('caret').style.opacity=(Math.floor(t*2)%2)?1:0.2;
    const bp=clamp01((p-0.6)/0.3); const pulse=1+0.06*Math.sin(clamp01((p-0.6)/0.38)*Math.PI);
    const btn=document.getElementById('fbtn'); btn.style.opacity=bp; btn.style.transform='scale('+(bp?pulse:0.9)+')';
  } else if(i===1){
    const a=document.getElementById('acc'); const ap=clamp01(p/0.4); a.style.opacity=ap; a.style.transform='translateX('+((1-easeOut(ap))*-40)+'px)';
    document.querySelectorAll('#comp1 .chip').forEach((c,k)=>{
      const cp=clamp01((p-0.3-k*0.12)/0.28);
      c.style.background=cp>0.5?'#7C4DEC':'rgba(255,255,255,.09)';
      c.style.color=cp>0.5?'#fff':'rgba(255,255,255,.6)';
      c.style.transform='scale('+(0.9+0.1*easeOut(cp))+')';
    });
  } else if(i===2){
    document.querySelectorAll('#comp2 .crow').forEach((r,k)=>{
      const rp=clamp01((p-k*0.16)/0.36); r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';
      const mk=r.querySelector('.mk'); mk.style.transform='scale('+(0.7+0.3*back(clamp01((p-0.12-k*0.16)/0.3)))+')';
    });
    document.getElementById('cnote').style.opacity=clamp01((p-0.6)/0.3);
  } else if(i===3){
    const tp=document.getElementById('ptop'); const tpp=clamp01(p/0.3); tp.style.opacity=tpp; tp.style.transform='translateY('+((1-easeOut(tpp))*18)+'px)';
    const tx=document.getElementById('ptext'); const txp=clamp01((p-0.16)/0.32); tx.style.opacity=txp; tx.style.transform='translateY('+((1-easeOut(txp))*18)+'px)';
    const q=document.getElementById('quote'); const qp=clamp01((p-0.42)/0.3); q.style.opacity=qp; q.style.transform='translateY('+((1-back(qp))*22)+'px)';
    document.getElementById('counts').style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===4){
    document.querySelector('#comp4 .fhead').style.opacity=clamp01(p/0.22);
    document.querySelectorAll('#comp4 .prow').forEach((r,k)=>{
      const rp=clamp01((p-0.1-k*0.12)/0.3); r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';
    });
    // the first Watch pill taps on — you choose who to watch
    const w0=document.querySelector('#comp4 .prow .watch');
    const on=clamp01((p-0.66)/0.2);
    if(on>0.5){ w0.classList.add('on'); w0.textContent='Watching'; } else { w0.classList.remove('on'); w0.textContent='Watch'; }
    w0.style.transform='scale('+(1+0.08*Math.sin(on*Math.PI))+')';
    document.getElementById('fnote').style.opacity=clamp01((p-0.62)/0.3);
  }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-farcaster-live.html'), html);
console.log('wrote clip-farcaster-live.html', (html.length/1024).toFixed(0)+'KB', TOTAL.toFixed(1)+'s');
