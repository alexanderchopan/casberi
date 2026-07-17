// Solana promo — live-animated. node render.js clip-solana-live.html --size=1080x1920
// Supersedes the names-only cut (2026-07-16): prd §86 shipped Solana ACTIVITY,
// so the old beat 4 ("Holdings, not transfers") is now false and is gone.
// Every number is measured, from Model/SolanaActivity.swift + Model/SNS.swift:
//   toly.sol → 86xCnPeV… (verified live against the Bonfida proxy SNS.swift calls)
//   2 requests/wallet vs the EVM path's 10 (5 chains × 2 directions)
//   6 of toly.sol's 10 most recent signatures moved nothing for him
//   0.00203928 SOL = the rent-exempt minimum; nativeNoiseFloor = 0.005
const fs=require('fs'), path=require('path');
const AVD='/Users/alexanderchopan/Developer/casberi/scratchpad/ens';
const av=n=>'data:image/png;base64,'+fs.readFileSync(path.join(AVD,n+'.png')).toString('base64');
const AC='#9945FF', GR='#14F195', HEX='#627EEA';
const BEATS=[
  {kick:'NAME',      head:'Type a name,\nnot a pubkey.', accent:AC},
  {kick:'RESOLVE',   head:'Straight to\nthe pubkey.',     accent:AC},
  {kick:'ACTIVITY',  head:'Two calls,\nnot ten.',          accent:AC},
  {kick:'NEWS',      head:'Six of ten\nmoved nothing.',    accent:AC},
  {kick:'WATCHLIST', head:'One list,\nboth chains.',       accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:(i+1<10?'0':'')+(i+1)+' · '+b.kick,head:b.head,accent:b.accent}));
// SolanaActivity.title() formats — "Swapped a → b on venue" / "Received a" / "Sent a"
const SIGS=[
  ['mention','Named in someone else’s PumpSwap buy'],
  ['move','Swapped 299.9 USDC → 1.4 SOL on PumpSwap'],
  ['mention','Named in someone else’s PumpSwap buy'],
  ['mention','Nothing moved for this wallet'],
  ['move','Sent 12.5 SOL'],
  ['mention','Nothing moved for this wallet'],
  ['mention','Named in someone else’s swap'],
  ['move','Received 1,200 USDC'],
  ['mention','Nothing moved for this wallet'],
  ['move','Swapped 0.8 SOL → 140 JUP on Jupiter'],
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:120px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;}
.field{background:#07050d;border:2px solid rgba(255,255,255,.14);border-radius:22px;padding:30px 34px;font-size:40px;display:flex;align-items:center;min-height:104px;}
.caret{display:inline-block;width:4px;height:42px;background:${GR};margin-left:4px;}
.wbtn{margin-top:28px;background:linear-gradient(100deg,${AC},${GR});color:#0b0713;font-weight:800;font-size:32px;padding:22px 48px;border-radius:100px;display:inline-block;will-change:transform;}
.hex{margin-top:32px;font-size:27px;color:rgba(255,255,255,.3);line-height:1.4;word-break:break-all;}
.hex s{text-decoration-color:#f85149;}
/* resolved */
.rcard{display:flex;align-items:center;gap:28px;background:#07050d;border-radius:26px;padding:34px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);will-change:opacity,transform;}
.ident{width:120px;height:120px;border-radius:50%;flex:none;background:conic-gradient(from 200deg,${AC},${GR},${AC});will-change:transform;}
.rn{font-size:46px;font-weight:750;} .ra{font-size:26px;color:rgba(255,255,255,.5);margin-top:8px;word-break:break-all;}
.rok{display:inline-flex;align-items:center;gap:12px;margin-top:28px;font-size:28px;color:${GR};font-weight:650;will-change:opacity,transform;}
.rok i{width:36px;height:36px;border-radius:50%;background:${GR};color:#04140a;display:flex;align-items:center;justify-content:center;font-size:23px;font-style:normal;}
/* activity — request bars */
.bar{margin-bottom:34px;will-change:opacity,transform;}
.bl{display:flex;align-items:baseline;font-size:34px;font-weight:650;margin-bottom:14px;}
.bl .cnt{margin-left:auto;font-size:30px;font-weight:800;}
.bl em{font-style:normal;font-size:24px;color:rgba(255,255,255,.4);margin-left:14px;}
.btrack{height:30px;border-radius:100px;background:rgba(255,255,255,.08);overflow:hidden;}
.bfill{height:100%;border-radius:100px;width:0;}
.anote{margin-top:24px;font-size:26px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.anote b{color:${GR};}
.brk{background:#07050d;border-radius:20px;padding:8px 28px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);}
.brow{display:flex;align-items:center;gap:22px;padding:22px 0;border-top:2px solid rgba(255,255,255,.07);font-size:27px;will-change:opacity,transform;}
.brow:first-child{border-top:none;}
.bn{width:44px;height:44px;border-radius:12px;flex:none;background:rgba(20,241,149,.14);color:${GR};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:24px;}
.brow em{font-style:normal;color:rgba(255,255,255,.4);font-size:23px;}
.bt{margin-left:auto;color:${GR};font-weight:700;font-size:25px;}
/* news — signature rows */
.sgrid{display:flex;flex-direction:column;gap:7px;}
.sig{display:flex;align-items:center;gap:18px;padding:9px 18px;border-radius:12px;background:rgba(255,255,255,.05);font-size:22px;will-change:opacity,transform;}
.sig .sd{width:11px;height:11px;border-radius:50%;flex:none;}
.sig .stx{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.nnote{margin-top:22px;font-size:24px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.nnote b{color:#fff;}
/* watchlist */
.wrow{display:flex;align-items:center;gap:26px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.wrow:first-of-type{border-top:none;}
.wrow img,.wrow .ident{width:86px;height:86px;border-radius:50%;flex:none;}
.wn{font-size:38px;font-weight:700;} .wa{font-size:24px;color:rgba(255,255,255,.45);margin-top:5px;}
.chain{margin-left:auto;font-size:21px;font-weight:800;padding:8px 18px;border-radius:100px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>SOLANA</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">WATCH AN ADDRESS</div>
    <div class="field mono"><span id="ftype"></span><span class="caret" id="caret"></span></div>
    <div class="wbtn" id="wbtn">Watch</div>
    <div class="hex mono" id="hexghost">instead of <s>86xCnPeV69n6t3DnyGvkKobf9FdN2H9oiVDdaMpo2MMY</s></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">RESOLVED · SNS</div>
    <div class="rcard" id="rcard"><div class="ident" id="rident"></div><div><div class="rn">toly.sol</div><div class="ra mono">86xCnPeV…aMpo2MMY</div></div></div>
    <div class="rok" id="rok"><i>✓</i> Bonfida's public resolver. No key, no account.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">REQUESTS PER WALLET, PER PASS</div>
    <div class="bar" data-i="0">
      <div class="bl"><span style="color:${HEX}">Ethereum &amp; friends</span><em>5 chains × 2 directions</em><span class="cnt" id="c0" style="color:${HEX}">0</span></div>
      <div class="btrack"><div class="bfill" id="b0" style="background:${HEX}" data-w="100"></div></div>
    </div>
    <div class="bar" data-i="1">
      <div class="bl"><span style="color:${GR}">Solana</span><em>batched JSON-RPC</em><span class="cnt" id="c1" style="color:${GR}">0</span></div>
      <div class="btrack"><div class="bfill" id="b1" style="background:${GR}" data-w="20"></div></div>
    </div>
    <div class="brk">
      <div class="brow" data-i="0"><span class="bn mono">1</span><span>getSignaturesForAddress</span></div>
      <div class="brow" data-i="1"><span class="bn mono">1</span><span>getTransaction <em>× 10, batched</em></span><span class="bt mono">~0.4s</span></div>
    </div>
    <div class="anote" id="anote">Solana's RPC takes an array of calls, so <b>ten whole transactions arrive in one request</b>. The chain everyone assumed would cost more costs less.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">TOLY.SOL · LAST TEN SIGNATURES</div>
    <div class="sgrid">
      ${SIGS.map((s,i)=>`<div class="sig" data-i="${i}" data-k="${s[0]}"><span class="sd"></span><span class="stx">${s[1]}</span></div>`).join('')}
    </div>
    <div class="nnote" id="nnote">A signature means you were <b>named</b>, not that anything moved. Six here were someone else's trade. The app drops what has no legs — and keeps what you signed.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">WATCHING</div>
    <div class="wrow" data-i="0"><img src="${av('vitaliketh')}"><div><div class="wn">vitalik.eth</div><div class="wa mono">0xd8dA…6045</div></div><span class="chain" style="background:${HEX}33;color:#9db4f5">Ethereum</span></div>
    <div class="wrow" data-i="1"><img src="${av('jessebaseeth')}"><div><div class="wn">jesse.base.eth</div><div class="wa mono">0x2211…7dA9</div></div><span class="chain" style="background:#0052FF33;color:#7fa8ff">Base</span></div>
    <div class="wrow" data-i="2"><div class="ident"></div><div><div class="wn">toly.sol</div><div class="wa mono">86xCnPeV…2MMY</div></div><span class="chain" style="background:${GR}26;color:${GR}">Solana</span></div>
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
const NAME='toly.sol';
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
    const n=Math.round(NAME.length*clamp01(p/0.45));
    document.getElementById('ftype').textContent=NAME.slice(0,n);
    document.getElementById('caret').style.opacity=(p<0.52&&Math.floor(t*2)%2)?1:0;
    const b=document.getElementById('wbtn');const bp=clamp01((p-0.5)/0.25);b.style.opacity=bp;b.style.transform='scale('+(0.9+0.1*back(bp))+')';
    document.getElementById('hexghost').style.opacity=clamp01((p-0.7)/0.25)*0.9;
  } else if(i===1){
    const c=document.getElementById('rcard');const cp=clamp01(p/0.4);c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*36)+'px)';
    document.getElementById('rident').style.transform='scale('+(0.5+0.5*back(clamp01((p-0.15)/0.4)))+') rotate('+(p*40)+'deg)';
    const ok=document.getElementById('rok');const okp=clamp01((p-0.55)/0.3);ok.style.opacity=okp;ok.style.transform='translateY('+((1-easeOut(okp))*14)+'px)';
  } else if(i===2){
    document.querySelectorAll('#comp2 .bar').forEach((s,k)=>{const cp=clamp01((p-k*0.14)/0.32);s.style.opacity=cp;s.style.transform='translateX('+((1-easeOut(cp))*-30)+'px)';});
    [[0,10],[1,2]].forEach(([k,target])=>{
      const gp=clamp01((p-0.12-k*0.14)/0.4);
      const f=document.getElementById('b'+k);f.style.width=(+f.dataset.w*easeOut(gp))+'%';
      document.getElementById('c'+k).textContent=Math.round(target*easeOut(gp));
    });
    document.querySelectorAll('#comp2 .brow').forEach((r,k)=>{const rp=clamp01((p-0.5-k*0.1)/0.28);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-24)+'px)';});
    document.getElementById('anote').style.opacity=clamp01((p-0.72)/0.26);
  } else if(i===3){
    document.querySelectorAll('#comp3 .sig').forEach((r,k)=>{
      const rp=clamp01((p-k*0.045)/0.22);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-26)+'px)';
      const mention=r.dataset.k==='mention';
      const fade=clamp01((p-0.6)/0.25);            // the filter sweeps through
      const dim=mention?(1-0.72*fade):1;
      r.style.opacity=rp*dim;
      const dot=r.querySelector('.sd');
      dot.style.background=mention?'rgba(255,255,255,.25)':'${GR}';
      r.style.background=mention?'rgba(255,255,255,.05)':('rgba(20,241,149,'+(0.05+0.1*fade)+')');
      r.querySelector('.stx').style.textDecoration=(mention&&fade>0.5)?'line-through':'none';
    });
    document.getElementById('nnote').style.opacity=clamp01((p-0.72)/0.25);
  } else if(i===4){
    document.querySelectorAll('#comp4 .wrow').forEach((r,k)=>{const rp=clamp01((p-k*0.15)/0.4);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-34)+'px)';});
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-solana-live.html'),html);
console.log('wrote clip-solana-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
