// 1Claw promo — live-animated. node render.js clip-1claw-live.html --size=1080x1920
// Grounded in Model/OneClawBridge.swift (branch claude/1claw-vault-permissions-api-dht3mt, prd §111):
//   agent key ocv_… JWT-exchanges, then vaults + each vault's grant table land as things
//   grant title format: "\(vault) · \(secret_path_pattern) · \(permissions joined)"
//     e.g. "Prod · secrets/anthropic/* · read, rotate"
//   METADATA ONLY: "nothing here ever reads a secret VALUE, signs, or spends"
//   lede = the key's reach: N vaults · M grants (vault count cached, grants counted from rows)
//   HONESTY CEILING: a key lacking policies:read degrades to vaults with NO grant rows —
//     never an invented grant table; the probe exists so "no grants" and "can't read
//     grants" stop looking identical. That distinction IS the feature.
//   RECONCILES: a revoked grant's row is deleted (only when every table was readable);
//     an edited grant's title/expiry follow the record.
//   brand: DS.brandHue "1claw" #990029 + glyph lock.shield
// Drawn mark, no external logos.
const fs=require('fs'), path=require('path');
const ICON='/Users/alexanderchopan/Developer/casberi/Casberi/Casberi/Assets.xcassets/brand-1claw.imageset/icon.png';
const ico='data:image/png;base64,'+fs.readFileSync(ICON).toString('base64');
const AC='#D11846', ROSE='#FF5C7A', DEEP='#990029', GRN='#3fb950';
const BEATS=[
  {kick:'CONNECT', head:"Paste an\nagent's key.",     accent:AC},
  {kick:'VAULT',   head:'Grants,\nnot secrets.',      accent:AC},
  {kick:'REACH',   head:'Everything it\ncan touch.',  accent:AC},
  {kick:'HONEST',  head:'None? Or\nnot allowed?',      accent:AC},
  {kick:'LIVE',    head:'Revoke it,\nit’s gone.',      accent:AC},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
// policyThing titles — "\(vault) · \(pattern) · \(perms)"
const GRANTS=[
  ['Prod','secrets/anthropic/*','read, rotate'],
  ['Prod','secrets/stripe/*','read'],
  ['Staging','secrets/openai/*','read, list'],
  ['CI','secrets/deploy/*','read, rotate, list'],
];
// what the exchange reads vs what it can't
const READS=[
  [1,'Which vaults the key sees',''],
  [1,'Each grant’s secret paths','secrets/anthropic/*'],
  [1,'The permissions it names','read, rotate'],
  [0,'The secret value itself',''],
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:118px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#150408;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;display:flex;align-items:center;justify-content:space-between;}
.reach{font-size:26px;font-weight:800;color:${ROSE};letter-spacing:0;}
/* connect */
.mark{width:132px;height:132px;border-radius:30px;display:block;object-fit:cover;box-shadow:0 16px 44px rgba(153,0,41,.5);will-change:transform;}
.field{margin-top:40px;background:#0a0305;border:2px solid rgba(255,255,255,.14);border-radius:22px;padding:30px 34px;font-size:34px;display:flex;align-items:center;min-height:100px;}
.field .pre{color:rgba(255,255,255,.4);}
.caret{display:inline-block;width:4px;height:40px;background:${ROSE};margin-left:4px;}
.cnote{margin-top:38px;font-size:29px;color:rgba(255,255,255,.55);line-height:1.55;will-change:opacity,transform;}
.cnote i{display:inline-flex;width:44px;height:44px;border-radius:50%;background:rgba(209,24,70,.18);color:${ROSE};align-items:center;justify-content:center;font-style:normal;font-size:24px;vertical-align:-12px;margin-right:16px;}
.cnote b{color:#fff;font-weight:700;}
/* vault (grants not secrets) */
.vr{display:flex;align-items:center;gap:22px;padding:24px 0;border-top:2px solid rgba(255,255,255,.07);font-size:32px;will-change:opacity,transform;}
.vr:first-of-type{border-top:none;}
.vr i{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
.vr.y i{background:${GRN};color:#04140a;} .vr.y{font-weight:600;}
.vr.n i{background:rgba(255,255,255,.07);color:rgba(255,255,255,.3);} .vr.n{color:rgba(255,255,255,.34);}
.vr em{font-style:normal;font-size:23px;color:rgba(255,255,255,.4);margin-left:auto;}
.vr.n em{text-decoration:line-through;text-decoration-color:rgba(255,255,255,.2);}
.vnote{margin-top:30px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.vnote b{color:#fff;}
/* reach — grant rows */
.grow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.grow:first-of-type{border-top:none;}
.gv{font-size:24px;font-weight:800;padding:8px 18px;border-radius:12px;flex:none;background:rgba(209,24,70,.18);color:${ROSE};}
.gp{font-size:33px;font-weight:600;} .gperm{font-size:24px;color:rgba(255,255,255,.45);margin-top:6px;}
.gperm b{color:${ROSE};font-weight:700;}
/* honest — split */
.hcol{display:flex;gap:24px;margin-top:2px;}
.hc{flex:1;background:#0a0305;border-radius:22px;padding:34px 30px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);will-change:opacity,transform;}
.hc .hi{width:60px;height:60px;border-radius:16px;display:flex;align-items:center;justify-content:center;font-size:32px;margin-bottom:22px;}
.hc .ht{font-size:33px;font-weight:750;line-height:1.12;}
.hc .hs{font-size:25px;color:rgba(255,255,255,.5);margin-top:14px;line-height:1.35;}
.hc.a .hi{background:rgba(63,185,80,.16);color:${GRN};} .hc.a .ht{color:${GRN};}
.hc.b .hi{background:rgba(255,92,122,.16);color:${ROSE};} .hc.b .ht{color:${ROSE};}
.hnote{margin-top:34px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.hnote b{color:#fff;}
/* live — reconcile */
.lrow{display:flex;align-items:center;gap:24px;padding:28px 0;border-top:2px solid rgba(255,255,255,.07);font-size:33px;will-change:opacity,transform,filter;}
.lrow:first-of-type{border-top:none;}
.lv{font-size:22px;font-weight:800;padding:7px 16px;border-radius:11px;flex:none;background:rgba(209,24,70,.18);color:${ROSE};}
.lstate{margin-left:auto;font-size:25px;font-weight:700;}
.lnote{margin-top:34px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.lnote b{color:#fff;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${AC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>1CLAW</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono"><span>CONNECT</span></div>
    <img class="mark" id="mark" src="${ico}">

    <div class="field mono" id="field"><span class="pre">key&nbsp;</span><span id="ktype"></span><span class="caret" id="caret"></span></div>
    <div class="cnote" id="cnote"><i>🛡</i> Names and permissions only. Nothing here ever reads a <b>secret's value</b>, signs, or spends.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono"><span>WHAT THE KEY LETS CASBERI READ</span></div>
    ${READS.map((r,i)=>`<div class="vr ${r[0]?'y':'n'}" data-i="${i}"><i>${r[0]?'✓':'🔒'}</i><span>${r[1]}</span>${r[2]?`<em class="mono">${r[2]}</em>`:''}</div>`).join('')}
    <div class="vnote" id="vnote">1Claw is the vault that holds the secret. Casberi reads the <b>grants around it</b> — never what's inside.</div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono"><span>THE KEY'S REACH</span><span class="reach" id="reach">3 vaults · 4 grants</span></div>
    ${GRANTS.map((g,i)=>`<div class="grow" data-i="${i}"><span class="gv">${g[0]}</span><div><div class="gp mono">${g[1]}</div><div class="gperm">can <b>${g[2]}</b></div></div></div>`).join('')}
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono"><span>AN EMPTY TABLE, TWO MEANINGS</span></div>
    <div class="hcol">
      <div class="hc a" data-i="0"><div class="hi">∅</div><div class="ht">No grants</div><div class="hs">The key reaches this vault, but holds nothing in it.</div></div>
      <div class="hc b" data-i="1"><div class="hi">🔒</div><div class="ht">Can't read grants</div><div class="hs">The key lacks <span class="mono">policies:read</span> — the table is hidden.</div></div>
    </div>
    <div class="hnote" id="hnote">Most tools show an empty list for both. Casberi <b>says which</b> — and never invents a grant table it couldn't read.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono"><span>WHEN ACCESS CHANGES</span></div>
    <div class="lrow" data-i="0"><span class="lv">Prod</span><span class="mono">secrets/anthropic/*</span><span class="lstate" id="ls0" style="color:${GRN}">✓ live</span></div>
    <div class="lrow" data-i="1"><span class="lv">Staging</span><span class="mono">secrets/openai/*</span><span class="lstate" id="ls1" style="color:${ROSE}">revoked</span></div>
    <div class="lrow" data-i="2"><span class="lv">CI</span><span class="mono">secrets/deploy/*</span><span class="lstate" id="ls2" style="color:${GRN}">✓ live</span></div>
    <div class="lnote" id="lnote">Grants are live records. Revoke one and its row <b>leaves the feed</b>; edit one and the row follows. Your reach is never overstated.</div>
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
const KEY='ocv_a41f…9d2c';
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
    const mp=clamp01(p/0.3);
    document.getElementById('mark').style.transform='scale('+(0.6+0.4*back(mp))+') rotate('+((1-easeOut(mp))*-12)+'deg)';
    const n=Math.round(KEY.length*clamp01((p-0.28)/0.4));
    document.getElementById('ktype').textContent=KEY.slice(0,n);
    document.getElementById('caret').style.opacity=(p>0.28&&p<0.72&&Math.floor(t*2)%2)?1:0;
    const k=document.getElementById('cnote');const kp=clamp01((p-0.66)/0.28);k.style.opacity=kp;k.style.transform='translateY('+((1-easeOut(kp))*16)+'px)';
  } else if(i===1){
    document.querySelectorAll('#comp1 .vr').forEach((r,k)=>{const rp=clamp01((p-k*0.12)/0.3);r.style.opacity=rp*(r.classList.contains('n')?0.999:1);r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('vnote').style.opacity=clamp01((p-0.6)/0.3);
  } else if(i===2){
    document.querySelectorAll('#comp2 .grow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    document.getElementById('reach').style.opacity=clamp01((p-0.5)/0.3);
  } else if(i===3){
    document.querySelectorAll('#comp3 .hc').forEach((r,k)=>{const rp=clamp01((p-k*0.16)/0.4);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*30)+'px)';});
    document.getElementById('hnote').style.opacity=clamp01((p-0.58)/0.3);
  } else if(i===4){
    document.querySelectorAll('#comp4 .lrow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    // the revoked row strikes through and dims late in the beat
    const rev=clamp01((p-0.6)/0.28);
    const row=document.querySelectorAll('#comp4 .lrow')[1];
    if(row){row.style.filter='grayscale('+rev+')';row.style.opacity=Math.min(row.style.opacity||1,1-0.55*rev);
      row.querySelector('.mono').style.textDecoration=rev>0.4?'line-through':'none';}
    document.getElementById('lnote').style.opacity=clamp01((p-0.66)/0.28);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-1claw-live.html'),html);
console.log('wrote clip-1claw-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
