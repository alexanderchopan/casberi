// Coinbase & Kraken promo — live-animated. node render.js clip-exchanges-live.html --size=1080x1920
// Grounded in Model/ExchangeBridge.swift + Screens/ExchangeSetupScreen.swift, prd §162/163:
//   Exchange balances (Coinbase, Kraken) merge into the SAME combined total/treemap as
//   watched wallets — a portfolio built only from onchain addresses is quietly wrong for
//   anyone whose main holding sits on an exchange.
//   Connect = paste a VIEW-ONLY key. ExchangeBridge.connect() asks the exchange what the
//   key may do BEFORE storing it (GetApiKeyInfo / key_permissions) — a key that can trade
//   or transfer is REFUSED and never written to the vault. Fails closed: unverifiable
//   (unreachable, unparseable, unrecognised permission) also refuses.
//   Exact toasts: "Connected — your Coinbase balance now joins your wallets." /
//   "That key can trade — make a view-only one and paste that instead. It wasn't saved."
//   Nothing here can place an order, withdraw, or transfer — no such endpoint is reachable.
const fs=require('fs'), path=require('path');
const AC='#2E63FF', CB='#0052FF', KR='#5741D9', GRN='#3fb950', RED='#E5484D';
const BEATS=[
  {kick:'THE GAP',      head:'Most wallets\nmiss this.',      accent:AC},
  {kick:'CONNECT',      head:'Paste a\nview-only key.',        accent:CB},
  {kick:'CHECKED',      head:'We check.\nNot your word.',      accent:GRN},
  {kick:'COMBINED',     head:'One total.\nEvery venue.',       accent:AC},
  {kick:'READ-ONLY',    head:'Never trades.\nNever withdraws.',accent:AC},
];
const INTRO=0.45,BEAT=2.15,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:112px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0a0a14;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;}
/* the gap — three venue rows, two greyed */
.grow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform,filter;}
.grow:first-of-type{border-top:none;}
.gtile{width:72px;height:72px;border-radius:20px;flex:none;display:flex;align-items:center;justify-content:center;font-size:26px;font-weight:800;color:#fff;}
.gn{font-size:34px;font-weight:650;}
.gv{margin-left:auto;font-size:32px;font-weight:700;}
.gv.miss{color:rgba(255,255,255,.3);font-weight:600;font-size:26px;}
.gnote{margin-top:32px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.gnote b{color:#fff;}
/* connect form */
.fform{background:#05050e;border-radius:24px;padding:36px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.fhead{display:flex;align-items:center;gap:20px;margin-bottom:30px;}
.ftile{width:60px;height:60px;border-radius:16px;flex:none;background:${CB};display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:800;}
.fn{font-size:32px;font-weight:700;}
.finput{background:rgba(255,255,255,.06);border-radius:100px;padding:20px 26px;font-size:27px;color:rgba(255,255,255,.35);margin-bottom:16px;}
.finput.filled{color:#fff;}
.fbtn{margin-top:14px;text-align:center;padding:20px;border-radius:100px;font-size:28px;font-weight:700;background:rgba(255,255,255,.14);color:rgba(255,255,255,.5);will-change:background,color;}
.fbtn.armed{background:${CB};color:#fff;}
.fnote{margin-top:32px;font-size:26px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.fnote b{color:#fff;}
/* checked, not trusted */
.vcard{background:#05050e;border-radius:24px;padding:40px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);text-align:center;}
.vspin{width:56px;height:56px;margin:0 auto;border-radius:50%;border:5px solid rgba(255,255,255,.14);border-top-color:${CB};will-change:opacity,transform;}
.vtext{margin-top:26px;font-size:32px;font-weight:700;will-change:opacity;}
.vok{display:none;align-items:center;justify-content:center;gap:16px;margin:0 auto;}
.vok i{width:64px;height:64px;border-radius:50%;background:${GRN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:34px;font-weight:800;}
.vsub{margin-top:14px;font-size:25px;color:rgba(255,255,255,.5);}
.vnote{margin-top:34px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.vnote b{color:#fff;}
/* combined */
.bighead{font-size:30px;color:rgba(255,255,255,.65);}
.bigval{font-size:104px;font-weight:800;letter-spacing:-.03em;margin-top:4px;}
.band{display:flex;height:26px;border-radius:100px;overflow:hidden;margin-top:28px;}
.legend{display:flex;flex-direction:column;gap:16px;margin-top:30px;}
.lrow2{display:flex;align-items:center;gap:16px;font-size:28px;font-weight:600;will-change:opacity,transform;}
.ldot{width:18px;height:18px;border-radius:50%;flex:none;}
.lval{margin-left:auto;font-weight:700;}
/* read-only */
.vrow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);font-size:33px;font-weight:600;will-change:opacity,transform;}
.vrow:first-of-type{border-top:none;}
.vrow s{width:54px;height:54px;border-radius:50%;flex:none;background:rgba(255,255,255,.06);color:rgba(255,255,255,.3);display:flex;align-items:center;justify-content:center;font-size:28px;text-decoration:none;}
.vrow b{color:#fff;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:30px;font-size:29px;font-weight:650;color:${GRN};will-change:opacity,transform;}
.vgood i{width:48px;height:48px;border-radius:50%;flex:none;background:${GRN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:26px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>EXCHANGES</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono"><span>YOUR PORTFOLIO, TODAY</span></div>
    <div class="grow" id="g0"><span class="gtile" style="background:${AC}"><svg viewBox="0 0 24 24" width="30" height="30"><path fill="#fff" d="M4 7a3 3 0 0 1 3-3h9a2 2 0 0 1 2 2v1h1a2 2 0 0 1 2 2v7a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V7Zm14 6.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z"/></svg></span><div class="gn">Wallets</div><span class="gv">$31.4K</span></div>
    <div class="grow" id="g1"><span class="gtile" style="background:${CB}">C</span><div class="gn">Coinbase</div><span class="gv miss">not counted</span></div>
    <div class="grow" id="g2"><span class="gtile" style="background:#fff;color:${KR}">K</span><div class="gn">Kraken</div><span class="gv miss">not counted</span></div>
    <div class="gnote" id="gnote">A portfolio built only from watched wallets is quietly wrong the moment real money sits on an exchange.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono"><span>MAKE A VIEW-ONLY KEY</span></div>
    <div class="fform">
      <div class="fhead"><span class="ftile">C</span><div class="fn">Coinbase</div></div>
      <div class="finput" id="fin1">Key name</div>
      <div class="finput" id="fin2">Private key (PEM)</div>
      <div class="fbtn" id="fbtn">Connect</div>
    </div>
    <div class="fnote" id="fnote">Give it <b>View</b> permission only — not Trade, not Transfer. Same idea on Kraken: tick only Query, leave Withdraw and Deposit unticked.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono"><span>BEFORE IT'S EVER SAVED</span></div>
    <div class="vcard">
      <div class="vspin" id="vspin"></div>
      <div class="vtext" id="vtext">Checking with Coinbase…</div>
      <div class="vok" id="vok"><i>✓</i></div>
      <div class="vsub" id="vsub" style="display:none">Verified — read-only</div>
    </div>
    <div class="vnote" id="vnote">Casberi asks the exchange what the key can do — <b>not your word for it</b>. A key that can trade is refused, never stored.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="bighead">Across your wallets & exchanges</div>
    <div class="bigval" id="c3val">$0</div>
    <div class="band" id="band">
      <div style="width:0%;background:${AC}" id="bw"></div>
      <div style="width:0%;background:${CB}" id="bc"></div>
      <div style="width:0%;background:${KR}" id="bk"></div>
    </div>
    <div class="legend">
      <div class="lrow2" data-i="0"><span class="ldot" style="background:${AC}"></span>Wallets<span class="lval">$31.4K</span></div>
      <div class="lrow2" data-i="1"><span class="ldot" style="background:${CB}"></span>Coinbase<span class="lval">$11.8K</span></div>
      <div class="lrow2" data-i="2"><span class="ldot" style="background:${KR}"></span>Kraken<span class="lval">$5.0K</span></div>
    </div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono"><span>FAILS CLOSED, BY DESIGN</span></div>
    <div class="vrow" data-i="0"><s>✕</s><span>Never places an <b>order</b></span></div>
    <div class="vrow" data-i="1"><s>✕</s><span>Never <b>withdraws</b> or transfers</span></div>
    <div class="vgood" id="vgood"><i>✓</i> Only reads balances, once verified read-only</div>
    <div class="gnote" style="margin-top:32px" id="v4note">An API key works for whoever holds it — so Casberi keeps the weakest one that does the job.</div>
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
function fmtUSD(v){return '$'+(v/1000).toFixed(1)+'K';}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.28)/1.45);
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
    ['g0','g1','g2'].forEach((id,k)=>{const r=document.getElementById(id);const rp=clamp01((p-k*0.14)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('gnote').style.opacity=clamp01((p-0.55)/0.3);
  } else if(i===1){
    const f1=clamp01((p-0.18)/0.22),f2=clamp01((p-0.36)/0.22);
    const in1=document.getElementById('fin1'),in2=document.getElementById('fin2');
    in1.textContent=f1>0.5?'cb-live-••••••••1a2b':'Key name'; in1.classList.toggle('filled',f1>0.5);
    in2.textContent=f2>0.5?'-----BEGIN EC PRIVATE KEY-----':'Private key (PEM)'; in2.classList.toggle('filled',f2>0.5);
    document.getElementById('fbtn').classList.toggle('armed',clamp01((p-0.5)/0.15)>0.5);
    document.getElementById('fnote').style.opacity=clamp01((p-0.6)/0.3);
  } else if(i===2){
    const spin=document.getElementById('vspin'),txt=document.getElementById('vtext'),ok=document.getElementById('vok'),sub=document.getElementById('vsub');
    const flip=clamp01((p-0.46)/0.1);
    spin.style.transform='rotate('+(t*420)+'deg)';
    spin.style.display=flip>0.5?'none':'block';
    txt.style.display=flip>0.5?'none':'block';
    ok.style.display=flip>0.5?'flex':'none';
    sub.style.display=flip>0.5?'block':'none';
    if(flip>0.5){const okp=clamp01((p-0.5)/0.2);ok.style.opacity=okp;ok.style.transform='scale('+(0.7+0.3*back(okp))+')';}
    document.getElementById('vnote').style.opacity=clamp01((p-0.62)/0.3);
  } else if(i===3){
    const val=48200*easeOut(p);
    document.getElementById('c3val').textContent=fmtUSD(val);
    const wp=31400/48200*100*easeOut(p),cp=11800/48200*100*easeOut(p),kp=5000/48200*100*easeOut(p);
    document.getElementById('bw').style.width=wp+'%'; document.getElementById('bc').style.width=cp+'%'; document.getElementById('bk').style.width=kp+'%';
    document.querySelectorAll('#comp3 .lrow2').forEach((r,k)=>{const rp=clamp01((p-0.3-k*0.13)/0.3);r.style.opacity=rp;r.style.transform='translateY('+((1-easeOut(rp))*14)+'px)';});
  } else if(i===4){
    document.querySelectorAll('#comp4 .vrow').forEach((r,k)=>{const rp=clamp01((p-k*0.14)/0.36);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    const vg=document.getElementById('vgood');const vgp=clamp01((p-0.4)/0.28);vg.style.opacity=vgp;vg.style.transform='translateY('+((1-back(vgp))*18)+'px)';
    document.getElementById('v4note').style.opacity=clamp01((p-0.6)/0.3);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-exchanges-live.html'),html);
console.log('wrote clip-exchanges-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
