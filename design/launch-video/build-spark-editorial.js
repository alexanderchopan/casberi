// Morpho + Spark promo — EDITORIAL, no app screenshots. Split into what's
// EXISTING (Morpho, since 2026-07-21) and what's NEW TODAY (Spark,
// 2026-07-30), grounded line-by-line in Model/MorphoDeFi.swift and
// Model/WalletDeFi.swift:
//   0 EXISTING — Morpho vault deposits, market collateral/debt, and a
//     per-market health factor, read from Morpho's own keyless GraphQL API.
//   1 EXISTING — a risk alert lands only when a wallet's worst health
//     factor on a chain crosses INTO risk (below 1.5) — never a stale
//     re-announce, and no debt resets to a definitive "safe".
//   2 EXISTING — settled Morpho activity (supply, borrow, repay, vault
//     deposits/withdrawals, liquidations) lands as things. Capture-only —
//     never a pending intent, never a path that trades.
//   3 NEW — Spark (SparkLend) positions now read beside Aave's, in the SAME
//     pool table: a straight Aave V3 fork (identical selector, identical
//     six-word return layout), so it's a second row, not a new type.
//     Ethereum only for now.
//   4 NEW — one ask spans all three: the catalog's own words, "Shows your
//     Aave, Spark and Morpho positions."
//   5 READ-ONLY — nothing here ever signs; watching the wallet is all it
//     takes, same as every DeFi read in the app.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-spark-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const MORPHO_BLUE = '#2470FF', SPARK_AMBER = '#FF9900', GREEN = '#3fb950', ORANGE = '#FF6B4A', VIOLET = '#8c40c7';
const BEATS = [
  { kick: 'ALREADY: MORPHO', head: 'Vaults, markets,\nhealth factor.',   accent: MORPHO_BLUE, tag: 'EXISTING' },
  { kick: 'ALREADY: RISK ALERTS', head: 'Crosses into risk?\nYou hear it.', accent: MORPHO_BLUE, tag: 'EXISTING' },
  { kick: 'ALREADY: ACTIVITY', head: 'Every settled\nmove lands.',        accent: MORPHO_BLUE, tag: 'EXISTING' },
  { kick: 'NEW: SPARK',       head: 'Now reading\nSpark too.',            accent: SPARK_AMBER, tag: 'NEW TODAY' },
  { kick: 'NEW: ONE ASK',     head: 'One question,\nthree protocols.',    accent: VIOLET,      tag: 'NEW TODAY' },
  { kick: 'READ-ONLY',        head: 'Watching is\nall it takes.',         accent: GREEN,       tag: null },
];
const INTRO = 0.45, BEAT = 2.9, OUT_AT = INTRO + BEATS.length * BEAT, TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:196px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.tagpill{position:absolute;left:74px;top:238px;font-size:19px;font-weight:800;letter-spacing:.06em;padding:8px 16px;border-radius:100px;will-change:opacity,transform;}
.head{position:absolute;left:70px;top:288px;right:70px;font-size:96px;line-height:.98;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — morpho vaults/markets */
.mrow{display:flex;align-items:center;gap:20px;padding:19px 0;will-change:opacity,transform;}
.mrow .mi{width:52px;height:52px;border-radius:15px;flex:none;background:${MORPHO_BLUE};display:flex;align-items:center;justify-content:center;}
.mrow .mt{font-size:26px;font-weight:700;}
.mrow .ms{font-size:20px;color:rgba(255,255,255,.42);margin-top:3px;}
.hfbig{margin-top:24px;text-align:center;}
.hfbig .n{font-size:60px;font-weight:800;}
.hfbig .l{font-size:19px;color:rgba(255,255,255,.42);margin-top:4px;font-weight:600;}
/* 1 — risk alert */
.riskcard{background:rgba(255,107,74,.1);border:2px solid rgba(255,107,74,.3);border-radius:22px;padding:28px;text-align:center;will-change:opacity,transform;}
.riskcard .t{font-size:25px;font-weight:700;line-height:1.36;}
.riskcard .t b{color:${ORANGE};}
.risksafe{margin-top:20px;display:flex;align-items:center;justify-content:center;gap:14px;font-size:22px;font-weight:700;color:${GREEN};will-change:opacity;}
.risksafe i{width:38px;height:38px;border-radius:50%;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:19px;}
/* 2 — activity */
.arow{display:flex;align-items:center;gap:18px;padding:16px 0;will-change:opacity,transform;}
.atag{font-size:16px;font-weight:800;padding:7px 14px;border-radius:100px;background:rgba(36,112,255,.18);color:${MORPHO_BLUE};flex:none;}
.atxt{font-size:23px;font-weight:650;}
/* 3 — spark joins aave */
.poolwrap{display:flex;flex-direction:column;gap:14px;}
.poolrow{display:flex;align-items:center;gap:18px;background:rgba(255,255,255,.06);border-radius:18px;padding:20px 24px;will-change:opacity,transform;}
.poolrow .pi{width:48px;height:48px;border-radius:14px;flex:none;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:18px;color:#fff;}
.poolrow .pn{font-size:25px;font-weight:700;}
.poolrow .ps{font-size:19px;color:rgba(255,255,255,.42);margin-top:2px;}
.sparknote{margin-top:22px;text-align:center;font-size:21px;color:rgba(255,255,255,.44);font-weight:600;}
/* 4 — one ask */
.askbar{background:rgba(255,255,255,.09);border-radius:100px;padding:20px 26px;font-size:26px;font-weight:650;text-align:center;}
.protorow{display:flex;justify-content:center;gap:14px;margin-top:26px;}
.protorow span{font-size:19px;font-weight:750;padding:12px 20px;border-radius:100px;will-change:opacity,transform;}
/* 5 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:19px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${MORPHO_BLUE};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>DEFI</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">MORPHO</div>
    <div class="mrow" data-i="0"><span class="mi"><svg width="24" height="24" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" rx="4" fill="none" stroke="#fff" stroke-width="2"/></svg></span><div><div class="mt">USDC Vault</div><div class="ms">Deposit, live</div></div></div>
    <div class="mrow" data-i="1"><span class="mi"><svg width="24" height="24" viewBox="0 0 24 24"><path d="M4 17 10 9l4 4 6-8" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg></span><div><div class="mt">ETH / USDC market</div><div class="ms">Collateral & debt, per market</div></div></div>
    <div class="hfbig"><div class="n" style="color:${GREEN}">2.4</div><div class="l">HEALTH FACTOR</div></div>
    <div class="cap">Read from Morpho's own keyless API —<br><b>nothing here needs a key.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">ONLY ON THE CROSSING</div>
    <div class="riskcard" id="riskcard">
      <div class="t">Your Morpho position on Base is close to liquidation — <b>health factor 1.32</b></div>
    </div>
    <div class="risksafe" id="risksafe"><i>✓</i> No debt resets to a definitive "safe"</div>
    <div class="cap">Never a stale re-announce —<br><b>only the moment it crosses in.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">SETTLED, NEVER PENDING</div>
    <div class="arow" data-i="0"><span class="atag">SUPPLY</span><span class="atxt">Deposited 2.0 ETH into a vault</span></div>
    <div class="arow" data-i="1"><span class="atag">BORROW</span><span class="atxt">Borrowed 1,200 USDC</span></div>
    <div class="arow" data-i="2"><span class="atag">REPAY</span><span class="atxt">Repaid 400 USDC</span></div>
    <div class="arow" data-i="3"><span class="atag">WITHDRAW</span><span class="atxt">Withdrew from a vault</span></div>
    <div class="cap">Capture-only —<br><b>never a pending intent, never a trade.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">THE SAME POOL TABLE</div>
    <div class="poolwrap">
      <div class="poolrow" data-i="0"><span class="pi" style="background:#8c40c7">A</span><div><div class="pn">Aave</div><div class="ps">Collateral $48.2k · debt $12.1k</div></div></div>
      <div class="poolrow" data-i="1"><span class="pi" style="background:${SPARK_AMBER}">S</span><div><div class="pn">Spark</div><div class="ps">Collateral $9.4k · debt $3.0k</div></div></div>
    </div>
    <div class="sparknote">A straight Aave V3 fork — same selector,<br>same six-word layout. Ethereum, for now.</div>
    <div class="cap">A second row in the same table —<br><b>not a whole new type.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">"WHAT'S MY DEFI LOOK LIKE?"</div>
    <div class="askbar">Shows your Aave, Spark and Morpho positions.</div>
    <div class="protorow">
      <span id="p0" style="background:rgba(140,64,192,.18);color:#8c40c7">Aave</span>
      <span id="p1" style="background:rgba(255,153,0,.18);color:${SPARK_AMBER}">Spark</span>
      <span id="p2" style="background:rgba(36,112,255,.18);color:${MORPHO_BLUE}">Morpho</span>
    </div>
    <div class="cap">One ask. One risk bucket.<br><b>Every protocol, together.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never signs a transaction</div>
    <div class="vrow" data-i="1"><s>✕</s> Never needs a key</div>
    <div class="vrow" data-i="2"><s>✕</s> Never a separate connect step</div>
    <div class="vgood" id="vgood"><i>✓</i> Watching your wallet is all it takes.</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="tagpill" id="tagpill"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${BEATS.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const TAGS=${JSON.stringify(BEATS.map(b=>b.tag))};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.7);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(40,Math.min(240,780/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const tag=document.getElementById('tagpill');
  if(TAGS[active]){
    tag.textContent=TAGS[active];
    tag.style.background = TAGS[active]==='NEW TODAY' ? 'rgba(255,153,0,.18)' : 'rgba(36,112,255,.15)';
    tag.style.color = TAGS[active]==='NEW TODAY' ? '${SPARK_AMBER}' : '${MORPHO_BLUE}';
    tag.style.opacity=easeOut(kin);
    tag.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  } else { tag.style.opacity=0; }
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  const cap=document.querySelector('#comp'+i+' .cap');
  if(i===0){
    stag('#comp0 .mrow',p,0.16,0.3,18);
    const hp=clamp01((p-0.46)/0.3);
    document.querySelector('#comp0 .hfbig').style.opacity=hp;
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===1){
    const cp=clamp01((p-0.06)/0.28);
    const rc=document.getElementById('riskcard');
    rc.style.opacity=cp;rc.style.transform='scale('+(0.9+0.1*back(cp))+')';
    document.getElementById('risksafe').style.opacity=clamp01((p-0.44)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===2){
    stag('#comp2 .arow',p,0.15,0.28,20);
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===3){
    stag('#comp3 .poolrow',p,0.2,0.32,22);
    document.querySelector('#comp3 .sparknote').style.opacity=clamp01((p-0.5)/0.3);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===4){
    document.querySelector('#comp4 .askbar').style.opacity=clamp01((p-0.04)/0.24);
    ['p0','p1','p2'].forEach((id,k)=>{const el=document.getElementById(id);const rp=clamp01((p-0.36-k*0.1)/0.24);el.style.opacity=rp;el.style.transform='scale('+(0.8+0.2*back(rp))+')';});
    if(cap)cap.style.opacity=clamp01((p-0.72)/0.24);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-spark-editorial.html'),html);
console.log('wrote clip-spark-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
