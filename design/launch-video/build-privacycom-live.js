// Privacy.com promo — live-animated. node render.js clip-privacycom-live.html --size=1080x1920
// Grounded in Model/PrivacyBridge.swift + TokenBridges.swift + BridgeCatalog.swift (2026-07-22):
//   Privacy.com virtual card purchases land as things: "Netflix.com · $12.99" (merchant ·
//   settled/authorization amount, formatted via PriceFormat), dated when Privacy recorded it.
//   Connect = one API key (privacy.com account → API, a PAID plan is required).
//   result=APPROVED only — real purchases, not blocked/declined attempts.
//   HONESTY CEILING (the real divergence from every other keyed bridge, stated plainly in
//   both the code comment and the catalog summary): Privacy's API key can NOT be scoped
//   read-only — the same key could also issue/close cards and move money. Unlike Wallet/
//   Exchange (verified read-only BY THE PROVIDER before storage), the "read-only" promise
//   here is kept by CONDUCT: this bridge only ever issues GET /v1/transactions. Never a
//   write call. The clip must NOT reuse the "we verify with the provider" framing built for
//   Coinbase/Kraken — that would misstate a materially different, weaker guarantee.
//   Real logo: privacy.com's own wordmark (black plate, white type), supplied by the user.
const fs=require('fs'), path=require('path');
const AC='#0EA5A5', GRN='#3fb950';
const LOGO_B64=fs.readFileSync('/tmp/privacy_logo_b64.txt','utf8').trim();
const BEATS=[
  {kick:'CONNECTED',   head:'Casberi\nconnects\nPrivacy.',      accent:AC},
  {kick:'THE FEED',    head:'Every card\npurchase.',            accent:AC},
  {kick:'FINDABLE',    head:'Next to\neverything\nyou keep.',   accent:AC},
  {kick:'BY CONDUCT',  head:'By conduct.\nNot by scope.',       accent:GRN},
  {kick:'ONE PLACE',   head:'Just your\nspending, in\none place.', accent:AC},
];
const INTRO=0.45,BEAT=2.2,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
const PURCHASES=[
  ['Netflix.com','$12.99','2h ago'],
  ['Uber','$24.50','yesterday'],
  ['Amazon.com','$58.12','2d ago'],
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:106px;line-height:1;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0a0a0e;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;}
/* connected */
.plate{width:100%;border-radius:18px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,.4);margin-bottom:36px;}
.plate img{width:100%;display:block;}
.cform{background:#000;border-radius:24px;padding:36px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.1);}
.cinput{background:rgba(255,255,255,.06);border-radius:100px;padding:20px 26px;font-size:27px;color:rgba(255,255,255,.35);}
.cinput.filled{color:#fff;}
.cbtn{margin-top:20px;text-align:center;padding:20px;border-radius:100px;font-size:28px;font-weight:700;background:rgba(255,255,255,.14);color:rgba(255,255,255,.5);will-change:background,color;}
.cbtn.armed{background:${AC};color:#04140a;}
.cnote{margin-top:32px;font-size:26px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.cnote b{color:#fff;}
/* the feed */
.prow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.prow:first-of-type{border-top:none;}
.ptile{width:64px;height:64px;border-radius:18px;flex:none;background:${AC};display:flex;align-items:center;justify-content:center;}
.pt{font-size:34px;font-weight:650;} .pt b{font-weight:800;}
.psub{margin-left:auto;font-size:23px;color:rgba(255,255,255,.4);text-align:right;}
.pnote{margin-top:30px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.pnote b{color:#fff;}
/* findable */
.sbar{display:flex;align-items:center;gap:16px;background:rgba(255,255,255,.1);border-radius:100px;padding:20px 28px;margin-bottom:30px;}
.scur{width:3px;height:26px;background:#fff;opacity:.9;}
.stxt{font-size:29px;font-weight:600;flex:1;}
.hitrow{display:flex;align-items:center;gap:20px;padding:20px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;opacity:0;}
.hitrow:first-of-type{border-top:none;}
.hitico{width:48px;height:48px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:800;color:#fff;}
.hitt{font-size:28px;font-weight:650;} .hits{font-size:21px;color:rgba(255,255,255,.4);}
/* by conduct */
.vrow{display:flex;align-items:center;gap:24px;padding:24px 0;border-top:2px solid rgba(255,255,255,.07);font-size:32px;font-weight:600;will-change:opacity,transform;}
.vrow:first-of-type{border-top:none;}
.vrow s{width:52px;height:52px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;font-size:28px;text-decoration:none;}
.vrow b{color:#fff;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:28px;font-size:27px;font-weight:650;color:${GRN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GRN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
/* one place — the single endpoint receipt */
.code{background:#000;border-radius:20px;padding:32px 34px;font-family:ui-monospace,"SF Mono",monospace;font-size:26px;color:${AC};box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.code .m{color:rgba(255,255,255,.4);}
.epnote{margin-top:32px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.epnote b{color:#fff;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>PRIVACY.COM</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="plate"><img src="data:image/png;base64,${LOGO_B64}"></div>
    <div class="cform">
      <div class="cinput" id="cin">API key</div>
      <div class="cbtn" id="cbtn">Connect</div>
    </div>
    <div class="cnote" id="cnote">One key from privacy.com → account → API. <b>A paid Privacy plan is required.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono"><span>APPROVED PURCHASES ONLY</span></div>
    ${PURCHASES.map((p,i)=>`<div class="prow" data-i="${i}"><span class="ptile"><svg viewBox="0 0 24 24" width="28" height="28"><path fill="#fff" d="M4 7a3 3 0 0 1 3-3h9a2 2 0 0 1 2 2v1h1a2 2 0 0 1 2 2v7a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V7Zm14 6.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"/></svg></span><div class="pt">${p[0]} · <b>${p[1]}</b></div><span class="psub">${p[2]}</span></div>`).join('')}
    <div class="pnote" id="pnote1">Merchant, amount, and the date Privacy recorded it — <b>dated like everything else you keep</b>.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="sbar"><div class="scur"></div><div class="stxt" id="stxt">netflix</div></div>
    <div class="hitrow" id="h0"><span class="hitico" style="background:${AC}">P</span><div><div class="hitt">Netflix.com · $12.99</div><div class="hits">Privacy · 2h ago</div></div></div>
    <div class="hitrow" id="h1"><span class="hitico" style="background:#bf5af2">N</span><div><div class="hitt">"cancel Netflix before renewal"</div><div class="hits">Note · last week</div></div></div>
    <div class="hitrow" id="h2"><span class="hitico" style="background:#0a84ff">L</span><div><div class="hitt">What's new on Netflix this month</div><div class="hits">Link · 3 weeks ago</div></div></div>
    <div class="pnote" id="pnote2" style="margin-top:34px">One search, every kind of thing — <b>a purchase sits beside the note and the link about it.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono"><span>THE HONEST CAVEAT</span></div>
    <div class="vrow" data-i="0"><s>✕</s><span>Never <b>creates</b> a card</span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Never <b>closes</b> a card</span></div>
    <div class="vrow" data-i="2"><s>✕</s><span>Never <b>funds</b> a card</span></div>
    <div class="vgood" id="vgood"><i>✓</i> Privacy's key can't be scoped read-only — so the promise is kept by what Casberi's code does</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono"><span>WHAT THE CODE IS ALLOWED TO SEND</span></div>
    <div class="code"><span class="m">GET</span> /v1/transactions<span id="cursor4">|</span></div>
    <div class="epnote" id="epnote">That's the only call this bridge ever makes. <b>Just your spending, in one place.</b></div>
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
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.5);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(60,Math.min(320,900/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.textContent=D[active].head;const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t){
  if(i===0){
    const f=clamp01((p-0.2)/0.22);
    const inp=document.getElementById('cin'); inp.textContent=f>0.5?'priv_live_••••••••92fa':'API key'; inp.classList.toggle('filled',f>0.5);
    document.getElementById('cbtn').classList.toggle('armed',clamp01((p-0.46)/0.15)>0.5);
    document.getElementById('cnote').style.opacity=clamp01((p-0.58)/0.3);
  } else if(i===1){
    document.querySelectorAll('#comp1 .prow').forEach((r,k)=>{const rp=clamp01((p-k*0.14)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('pnote1').style.opacity=clamp01((p-0.55)/0.3);
  } else if(i===2){
    const full='netflix'; const n=Math.round(full.length*clamp01(p/0.22));
    document.getElementById('stxt').textContent=full.slice(0,n);
    ['h0','h1','h2'].forEach((id,k)=>{const r=document.getElementById(id);const rp=clamp01((p-0.28-k*0.14)/0.3);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*16)+'px)';});
    document.getElementById('pnote2').style.opacity=clamp01((p-0.72)/0.26);
  } else if(i===3){
    document.querySelectorAll('#comp3 .vrow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.32);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    const vg=document.getElementById('vgood');const vgp=clamp01((p-0.46)/0.28);vg.style.opacity=vgp;vg.style.transform='translateY('+((1-back(vgp))*16)+'px)';
  } else if(i===4){
    document.getElementById('cursor4').style.opacity=(Math.floor(t*2)%2===0)?1:0;
    document.getElementById('epnote').style.opacity=clamp01((p-0.3)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-privacycom-live.html'),html);
console.log('wrote clip-privacycom-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
