// Wallet promo — FEATURE-COMPLETE pass (2026-07-21): every group from the
// "What you can do → Wallets" brief gets its own beat, not just a highlight
// reel. The UI is REBUILT as live HTML/CSS/SVG (no screenshots) — balances
// count up, treemap tiles build, sparklines draw, list/tag/chip rows
// stagger in. Wrapped in the same editorial frame (paper ground, oversized
// type, mono masthead, colour wipes) as every other clip.
// Deterministic → node render.js clip-wallet-live.html --size=1080x1920
const fs = require('fs');
const path = require('path');

const BLUE = '#2E63FF', AMBER = '#E8912A', RED = '#E5484D', GRN = '#3fb950';

// One beat per brief group. `dur` varies — list/tag beats get more time to
// read than a single counting number does.
const BEATS = [
  { kick: 'READ-ONLY',    head: 'Watch,\nnever move.',      accent: BLUE,  dur: 2.1 },
  { kick: 'GETTING IN',   head: 'Four ways\nin.',            accent: BLUE,  dur: 2.7 },
  { kick: 'COMBINED',     head: 'One total.\nEvery wallet.', accent: BLUE,  dur: 2.3 },
  { kick: 'HOLDINGS',     head: 'What you\nhold.',           accent: BLUE,  dur: 2.3 },
  { kick: 'YOUR FEED',    head: 'Everything\nlands here.',   accent: BLUE,  dur: 2.7 },
  { kick: 'DEPICTED',     head: 'Shown, not\ndescribed.',    accent: BLUE,  dur: 2.1 },
  { kick: 'MARKETS',      head: 'Live token\ncharts.',       accent: AMBER, dur: 2.0 },
  { kick: 'WORTH A LOOK', head: 'Worth a\nlook.',            accent: RED,   dur: 2.8 },
  { kick: 'ASK',          head: 'Ask it\nplainly.',          accent: BLUE,  dur: 2.3 },
  { kick: 'A WALLET IS',  head: 'A wallet\nis a color.',     accent: GRN,   dur: 2.1 },
  { kick: 'EVERY CHAIN',  head: 'Every chain\nit lives on.', accent: BLUE,  dur: 2.1 },
];
const INTRO = 0.45;
const durs = BEATS.map(b => b.dur);
const STARTS = []; { let acc = INTRO; for (const d of durs) { STARTS.push(acc); acc += d; } }
const OUT_AT = STARTS[STARTS.length - 1] + durs[durs.length - 1];
const TOTAL = OUT_AT + 1.9;
const DATA = BEATS.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));

// treemap tile layouts (grid areas)
const HOLD = [['ETH', '1/1/3/3'], ['USDC', '1/3/3/6'], ['AAVE', '3/1/5/3'], ['ARB', '3/3/5/5'], ['WETH', '3/5/5/6']];
const tiles = arr => arr.map((t, i) => `<div class="tile" data-i="${i}" style="grid-area:${t[1]}"><span class="tk">${t[0]}</span></div>`).join('');

const lrows = items => items.map((r, i) =>
  `<div class="lrow" data-i="${i}"><b class="dot"></b><div><div class="lt">${r[0]}</div><div class="ls">${r[1]}</div></div></div>`).join('');
const pills = (items, cls) => items.map((t, i) => `<div class="${cls}" data-i="${i}">${t}</div>`).join('');

const html = `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;
  background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);
  background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:132px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}

/* --- the live UI card --- */
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;
  box-shadow:34px 40px 0 rgba(20,17,13,.13), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;
  transform-origin:center top;padding:52px;color:#fff;}
.comp.blue{background:linear-gradient(160deg,#2E63FF,#1B49D6);}
.comp.amber{background:linear-gradient(160deg,#F0A93A,#D97913);}
.comp.dark{background:#0d0e13;}
.comp.red{background:linear-gradient(160deg,#3a1216,#1a0a0c);}
.comp.grn{background:linear-gradient(160deg,#0f2e1c,#0a1a10);}

/* watching / pledge */
.wrow{display:flex;align-items:center;gap:26px;padding:20px 4px;will-change:transform,opacity;}
.av{width:74px;height:74px;border-radius:20px;flex:none;}
.av0{background:radial-gradient(circle at 35% 30%,#8ea2c8,#38507e 70%);}
.av1{background:radial-gradient(circle at 40% 35%,#7dffb0,#12a15a);}
.wn{font-size:40px;font-weight:650;}
.wa{font-size:26px;color:rgba(255,255,255,.55);margin-top:4px;}
.wsp{margin-left:auto;}
.pledge{display:flex;align-items:flex-start;gap:18px;margin-top:36px;padding-top:32px;border-top:2px solid rgba(255,255,255,.12);will-change:opacity,transform;}
.pledge .dot{background:${GRN};margin-top:9px;}
.pledge p{font-size:27px;line-height:1.5;color:rgba(255,255,255,.82);}
.pledge b{color:#fff;}

/* generic list row (getting-in / worth-a-look) */
.lhead{font-size:34px;font-weight:650;margin-bottom:22px;}
.lrow{display:flex;align-items:flex-start;gap:20px;padding:19px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.lrow:first-of-type{border-top:none;}
.dot{width:12px;height:12px;border-radius:50%;background:rgba(255,255,255,.5);flex:none;margin-top:10px;}
.lt{font-size:32px;font-weight:700;}
.ls{font-size:24px;color:rgba(255,255,255,.6);margin-top:4px;line-height:1.4;}

/* tag pills (feed inventory / chains) */
.phead{font-size:34px;font-weight:650;margin-bottom:28px;}
.pgrid{display:flex;flex-wrap:wrap;gap:14px;}
.pill,.cpill{padding:16px 26px;border-radius:100px;background:rgba(255,255,255,.1);font-size:27px;font-weight:650;
  will-change:opacity,transform;opacity:0;}
.cpill{background:rgba(255,255,255,.12);}

/* combined portfolio */
.wsw{display:flex;gap:12px;margin-bottom:8px;}
.wswc{padding:12px 24px;border-radius:100px;font-size:24px;font-weight:650;background:rgba(255,255,255,.1);color:rgba(255,255,255,.55);}
.wswc.on{background:#fff;color:#1B49D6;}
.bighead{font-size:30px;color:rgba(255,255,255,.65);margin-top:18px;}
.bigval{font-size:104px;font-weight:800;letter-spacing:-.03em;margin-top:4px;}
.bigdelta{display:inline-block;margin-left:6px;font-size:32px;font-weight:700;vertical-align:middle;}
.bigsub{font-size:28px;color:rgba(255,255,255,.65);margin-top:10px;}
.spark2{width:100%;height:150px;margin-top:26px;}
.tfrow{display:flex;gap:14px;margin-top:22px;}
.tfchip{padding:12px 22px;border-radius:100px;font-size:24px;font-weight:650;background:rgba(255,255,255,.1);color:rgba(255,255,255,.7);}
.tfchip.on{background:rgba(255,255,255,.22);color:#fff;}

/* holdings treemap */
.thead{font-size:34px;font-weight:600;margin-bottom:26px;}
.thead b{font-weight:750;}
.tmap{display:grid;grid-template-columns:repeat(5,1fr);grid-template-rows:repeat(4,118px);gap:16px;}
.comp .tile{background:rgba(0,0,0,.28);}
.tile{border-radius:20px;position:relative;will-change:transform,opacity;transform-origin:center;
  display:flex;align-items:flex-end;padding:22px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.05);}
.tk{font-size:32px;font-weight:650;}
.conc{font-size:27px;color:rgba(255,255,255,.7);margin-top:24px;will-change:opacity;}
.conc b{color:#fff;}

/* depicted transaction */
.faces{display:flex;align-items:center;gap:24px;margin-bottom:8px;}
.face{width:80px;height:80px;border-radius:22px;flex:none;}
.face0{background:radial-gradient(circle at 35% 30%,#8ea2c8,#38507e 70%);}
.face1{background:radial-gradient(circle at 40% 35%,#7dffb0,#12a15a);}
.farrow{flex:1;height:2px;background:rgba(255,255,255,.3);position:relative;}
.farrow::after{content:'';position:absolute;right:-2px;top:-6px;border:7px solid transparent;border-left-color:rgba(255,255,255,.5);}
.dtxt{font-size:64px;font-weight:800;letter-spacing:-.02em;line-height:1.15;margin-top:18px;}
.dcap{font-size:25px;color:rgba(255,255,255,.55);margin-top:30px;line-height:1.6;}
.dcap b{color:rgba(255,255,255,.85);}

/* chart */
.chead{font-size:38px;font-weight:750;}
.cprice{font-size:76px;font-weight:800;margin-top:10px;letter-spacing:-.02em;}
.ctabs{font-size:28px;color:rgba(255,255,255,.7);letter-spacing:.1em;margin-top:6px;}
.ctabs b{color:#fff;}
.chart{width:100%;height:230px;margin-top:6px;overflow:visible;}
.cstats{display:flex;gap:20px;margin-top:14px;}
.cstats div{flex:1;}
.cstats span{display:block;font-size:24px;color:rgba(255,255,255,.6);}
.cstats b{font-size:38px;font-weight:750;}

/* ask */
.abar{display:flex;align-items:center;gap:16px;background:rgba(255,255,255,.1);border-radius:100px;padding:22px 30px;margin-bottom:30px;}
.acur{width:3px;height:30px;background:#fff;opacity:.9;}
.atxt{font-size:30px;font-weight:600;flex:1;}
.atag{font-size:20px;letter-spacing:.08em;color:rgba(255,255,255,.5);text-transform:uppercase;}
.achead{font-size:26px;color:rgba(255,255,255,.55);margin-bottom:18px;}
.achip{padding:18px 26px;border-radius:22px;background:rgba(255,255,255,.08);font-size:28px;font-weight:600;margin-bottom:14px;
  will-change:opacity,transform;opacity:0;}

/* a wallet is a color */
.swrow{display:flex;align-items:center;gap:24px;padding:20px 0;border-top:2px solid rgba(255,255,255,.08);will-change:opacity,transform;}
.swrow:first-of-type{border-top:none;}
.sw-av{width:70px;height:70px;border-radius:20px;flex:none;}
.sw-av.main{background:radial-gradient(circle at 35% 30%,#8ea2c8,#38507e 70%);}
.sw-av.trading{background:radial-gradient(circle at 40% 35%,#7dffb0,#12a15a);}
.sw-av.ens{background:conic-gradient(#f0a93a,#e5484d,#3fb950,#2e63ff,#f0a93a);}
.swn{font-size:32px;font-weight:700;}
.sws{font-size:24px;color:rgba(255,255,255,.55);margin-top:3px;}
.berry{margin-top:30px;padding-top:26px;border-top:2px solid rgba(255,255,255,.12);font-size:26px;color:rgba(255,255,255,.65);
  display:flex;align-items:center;gap:14px;will-change:opacity;}
.berry .dot{background:${GRN};}

.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .big{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;}
.outro .u b{color:#2E63FF;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>WALLET</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <!-- 0 READ-ONLY -->
  <div class="comp dark" id="comp0">
    ${[['Main', '0x1a2b…4f91', 'av0', true], ['Trading', '0x7c3e…0a12', 'av1', false]]
      .map((r, i) => `<div class="wrow" data-i="${i}"><div class="av ${r[2]}"></div><div><div class="wn">${r[0]}</div><div class="wa mono">${r[1]}</div></div>${r[3] ? `<svg class="wsp" width="150" height="60"><path id="spark" d="M2 46 L38 40 L74 44 L110 22 L148 8" fill="none" stroke="#48e08a" stroke-width="5" stroke-linecap="round"/></svg>` : ''}</div>`).join('')}
    <div class="pledge"><b class="dot"></b><p><b>Read-only and structural</b> — watching an address can never trade or move funds. WalletConnect proposes zero methods, zero events, and tears the session down on close.</p></div>
  </div>

  <!-- 1 GETTING IN -->
  <div class="comp blue" id="comp1">
    <div class="lhead">Four ways in</div>
    ${lrows([
      ['Paste anything', 'an address, ENS, .sol, or a basename'],
      ['Connect a wallet app', 'hands over the address — never signs'],
      ['Peek at a public wallet', 'one tap to watch, then it retires forever'],
      ['From a Farcaster profile', '“Watch their wallet” resolves the verified address'],
    ])}
  </div>

  <!-- 2 COMBINED -->
  <div class="comp blue" id="comp2">
    <div class="bighead">Across your wallets — Main + Trading</div>
    <div><span class="bigval" id="c2val">$0</span><span class="bigdelta" id="c2delta"></span></div>
    <div class="bigsub" id="c2sub">Mostly ETH · +$0</div>
    <svg class="spark2" viewBox="0 0 740 150" preserveAspectRatio="none">
      <path id="spark2" d="" fill="none" stroke="#ffffff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  </div>

  <!-- 3 HOLDINGS -->
  <div class="comp blue" id="comp3">
    <div class="thead"><b id="t3val">$0</b> across 30 tokens</div>
    <div class="tmap">${tiles(HOLD)}</div>
    <div class="conc" id="conc3">ETH is <b>62%</b> of everything</div>
  </div>

  <!-- 4 YOUR FEED (inventory) -->
  <div class="comp blue" id="comp4">
    <div class="phead">Every one of these lands as a thing</div>
    <div class="pgrid">${pills(['Transfers', 'Swaps', 'Solana', 'Approvals & revokes', 'NFT grants', 'Peer fills', 'Delegation changes', 'Aave alerts', 'Safe signatures'], 'pill')}</div>
  </div>

  <!-- 5 DEPICTED -->
  <div class="comp blue" id="comp5">
    <div class="txk mono" style="font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.65)">TRANSACTION · TODAY</div>
    <div class="faces" style="margin-top:26px"><div class="face face0"></div><div class="farrow"></div><div class="face face1"></div></div>
    <div class="dtxt" id="dtxt">Swapped <span id="damt">0.00</span> ETH → 1,240 USDC</div>
    <div class="dcap">Counterparties get names: <b>your label</b> → a watched Farcaster handle → known contracts → reverse ENS. The title never carries a raw hash.</div>
  </div>

  <!-- 6 MARKETS -->
  <div class="comp amber" id="comp6">
    <div class="chead">Wrapped Ether &nbsp;·&nbsp; $WETH</div>
    <div class="cprice" id="cpx">$0.00</div>
    <div class="ctabs mono"><b>1D</b> &nbsp; 7D &nbsp; 30D</div>
    <svg class="chart" viewBox="0 0 740 230" preserveAspectRatio="none">
      <defs><linearGradient id="cg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".35"/><stop offset="1" stop-color="#ffffff" stop-opacity="0"/></linearGradient></defs>
      <path id="cfill" d="" fill="url(#cg)"/>
      <path id="cpath" d="" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    <div class="cstats">
      <div><span>Liquidity</span><b id="s0">$0</b></div>
      <div><span>FDV</span><b id="s1">$0</b></div>
      <div><span>Market cap</span><b id="s2">$0</b></div>
    </div>
  </div>

  <!-- 7 WORTH A LOOK -->
  <div class="comp red" id="comp7">
    <div class="lhead">Worth a look · 6</div>
    ${lrows([
      ['Token approvals', 'new grants open that wallet’s Revoke.cash page'],
      ['Address poisoning', 'flags a copycat of an address you’ve used'],
      ['EIP-7702 delegation', 'your wallet starting to delegate control'],
      ['Aave health factor', 'an alert on a new crossing below 1.5'],
      ['Safe multisig', '“2 of 3 signatures collected”'],
      ['The prepare card', 'fee quoted, copyable JSON — signed elsewhere'],
    ])}
  </div>

  <!-- 8 ASK -->
  <div class="comp blue" id="comp8">
    <div class="abar"><div class="acur"></div><div class="atxt" id="atxt">how's my wallet</div><div class="atag">Ask</div></div>
    <div class="achead">Computed live from your own things. No model, no guessing.</div>
    ${['“How’s my wallet”', '“How’s my Aave loan”', '“What have I spent on gas”', '“Anything pending on my Safe”'].map((t, i) => `<div class="achip" data-i="${i}">${t}</div>`).join('')}
  </div>

  <!-- 9 A WALLET IS A COLOR -->
  <div class="comp grn" id="comp9">
    ${[['Main', 'main', 'One seed → identicon and tint'], ['Trading', 'trading', 'Carries through switcher, bands, tray'], ['poap.eth', 'ens', 'ENS avatars replace identicons']]
      .map((r, i) => `<div class="swrow" data-i="${i}"><div class="sw-av ${r[1]}"></div><div><div class="swn">${r[0]}</div><div class="sws">${r[2]}</div></div></div>`).join('')}
    <div class="berry"><b class="dot"></b><span>A new high rains a quiet berry — in that wallet’s own hue.</span></div>
  </div>

  <!-- 10 EVERY CHAIN -->
  <div class="comp blue" id="comp10">
    <div class="phead">Routed only to the chains it can live on</div>
    <div class="pgrid">${pills(['Ethereum', 'Base', 'Arbitrum', 'Optimism', 'Polygon', 'Solana', 'Robinhood Chain'], 'cpill')}</div>
  </div>

  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="big">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v));
const easeOut=p=>1-Math.pow(1-p,3);
const back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO}, N=${BEATS.length}, OUT_AT=${OUT_AT};
const DUR=${JSON.stringify(durs)};
const START=${JSON.stringify(STARTS)};
const D=${JSON.stringify(DATA)};
window.TOTAL=${TOTAL};
const comps=[...document.querySelectorAll('.comp')];

const CPTS=[[0,205],[60,180],[120,196],[190,150],[250,168],[320,120],[390,138],[460,86],[540,104],[620,54],[700,66],[740,30]];
function chartD(p){ const n=Math.max(2,Math.round(CPTS.length*p)); return 'M'+CPTS.slice(0,n).map(q=>q[0]+' '+q[1]).join(' L'); }
const SPTS=[[0,120],[74,132],[148,108],[222,116],[296,86],[370,98],[444,58],[518,70],[592,34],[666,44],[740,10]];
function sparkD(p){ const n=Math.max(2,Math.round(SPTS.length*p)); return 'M'+SPTS.slice(0,n).map(q=>q[0]+' '+q[1]).join(' L'); }
function fmtUSD(v){ if(v>=1e6) return '$'+(v/1e6).toFixed(1)+'M'; if(v>=1e3) return '$'+(v/1e3).toFixed(0)+'K'; return '$'+v.toFixed(0); }

function activeAt(t){
  for(let i=N-1;i>=0;i--) if(t>=START[i]) return i;
  return 0;
}

function staggerRows(sel,p,stagger,dur,dx){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*stagger)/dur);
    r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*(dx||-40))+'px)';
  });
}
function staggerPop(sel,p,stagger,dur){
  document.querySelectorAll(sel).forEach((r,k)=>{
    const rp=clamp01((p-k*stagger)/dur);
    r.style.opacity=rp; r.style.transform='scale('+(0.6+0.4*back(rp))+')';
  });
}

window.seek=function(t){
  const active=activeAt(t);
  const bs=START[active], local=t-bs, dur=DUR[active], acc=D[active].accent;
  const pIn=clamp01((local-0.26)/Math.max(0.5,dur-0.45));

  // diagonal wipe at each beat boundary
  let coverAcc=acc, wipeX=200;
  const bounds=[]; for(let k=1;k<N;k++) bounds.push({t:START[k],c:D[k].accent}); bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68; if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe'); wp.style.background=coverAcc; wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';

  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm'); wm.textContent=D[active].kick;
  wm.style.fontSize=Math.max(80,Math.min(320,900/(0.6*D[active].kick.length)))+'px';
  wm.style.color=acc; wm.style.opacity=0.09*clamp01(local/0.4); wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';

  const ki=document.getElementById('kick'); ki.textContent=D[active].kick; ki.style.color=acc;
  const kin=clamp01(local/0.4); ki.style.opacity=easeOut(kin); ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';

  const he=document.getElementById('head'); he.textContent=D[active].head;
  const hin=clamp01((local-0.06)/0.5); he.style.opacity=clamp01(local/0.2); he.style.transform='translateY('+((1-back(hin))*80)+'px)';

  comps.forEach((c,i)=>{
    const cbs=START[i], cl=t-cbs, cin=clamp01((cl-0.12)/0.6);
    const beatEnd=START[i]+DUR[i], outp=clamp01((t-(beatEnd-0.3))/0.4);
    let op=(i===active?1:0)*clamp01(cl/0.15);
    if(t>OUT_AT) op*=(1-clamp01((t-OUT_AT)/0.25));
    const y=(1-back(cin))*180 + outp*200 + Math.sin(t*0.9+i)*5;
    const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;
    c.style.opacity=op; c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';
  });

  animateComp(active, pIn);

  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;
  ['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};

function animateComp(i,p){
  if(i===0){ // watching rows + sparkline + pledge
    document.querySelectorAll('#comp0 .wrow').forEach((r,k)=>{
      const rp=clamp01((p-k*0.16)/0.4); r.style.opacity=rp; r.style.transform='translateX('+((1-easeOut(rp))*-46)+'px)';
    });
    const sp=document.getElementById('spark'); if(sp){const L=200; sp.style.strokeDasharray=L; sp.style.strokeDashoffset=L*(1-clamp01((p-0.35)/0.5));}
    const pl=document.querySelector('#comp0 .pledge'); if(pl){const pp=clamp01((p-0.4)/0.4); pl.style.opacity=pp; pl.style.transform='translateY('+((1-easeOut(pp))*14)+'px)';}
  } else if(i===1){ // getting in
    staggerRows('#comp1 .lrow', p, 0.14, 0.35, -40);
  } else if(i===2){ // combined portfolio
    const val=1051475*easeOut(p);
    document.getElementById('c2val').textContent=fmtUSD(val);
    document.getElementById('c2delta').textContent=' +'+(5.4*easeOut(p)).toFixed(1)+'%';
    document.getElementById('c2delta').style.color='#8effc0';
    document.getElementById('c2sub').textContent='Mostly ETH · +'+fmtUSD(23000*easeOut(p));
    const d=sparkD(clamp01((p-0.1)/0.7)); document.getElementById('spark2').setAttribute('d',d);
  } else if(i===3){ // holdings treemap + concentration
    document.getElementById('t3val').textContent=fmtUSD(1051475*easeOut(p));
    document.querySelectorAll('#comp3 .tile').forEach((tl,k)=>{
      const tp=clamp01((p-k*0.09)/0.4); const s=0.6+0.4*back(tp);
      tl.style.opacity=clamp01(tp/0.5); tl.style.transform='scale('+s+')';
    });
    const cc=document.getElementById('conc3'); cc.style.opacity=clamp01((p-0.55)/0.35);
  } else if(i===4){ // feed inventory tags
    staggerPop('#comp4 .pill', p, 0.075, 0.32);
  } else if(i===5){ // depicted transaction
    document.querySelectorAll('#comp5 .face').forEach((f,k)=>{const fp=clamp01((p-k*0.12)/0.4); f.style.opacity=fp; f.style.transform='scale('+(0.7+0.3*back(fp))+')';});
    document.getElementById('damt').textContent=(0.50*easeOut(p)).toFixed(2);
    const dc=document.querySelector('#comp5 .dcap'); dc.style.opacity=clamp01((p-0.4)/0.4);
  } else if(i===6){ // chart
    document.getElementById('cpx').textContent='$'+(1931.02*easeOut(p)).toFixed(2);
    const d=chartD(clamp01(p/0.85)); document.getElementById('cpath').setAttribute('d',d);
    const fp=d==='M'?'':(d+' L740 230 L0 230 Z'); document.getElementById('cfill').setAttribute('d', d.includes('L')?fp:'');
    document.getElementById('s0').textContent=fmtUSD(18400000*easeOut(p));
    document.getElementById('s1').textContent=fmtUSD(24100000*easeOut(p));
    document.getElementById('s2').textContent=fmtUSD(23600000*easeOut(p));
  } else if(i===7){ // worth a look
    staggerRows('#comp7 .lrow', p, 0.12, 0.32, -40);
  } else if(i===8){ // ask
    const chars='how\\'s my wallet'; const n=Math.round(chars.length*clamp01(p/0.5));
    document.getElementById('atxt').textContent=chars.slice(0,n);
    staggerRows('#comp8 .achip', clamp01((p-0.5)/0.5), 0.13, 0.32, 20);
    document.querySelectorAll('#comp8 .achip').forEach(r=>{r.style.transform=r.style.transform.replace('translateX','translateY');});
  } else if(i===9){ // wallet is a color
    staggerRows('#comp9 .swrow', p, 0.15, 0.4, -40);
    const b=document.querySelector('#comp9 .berry'); if(b){const bp=clamp01((p-0.55)/0.35); b.style.opacity=bp;}
  } else if(i===10){ // chains
    staggerPop('#comp10 .cpill', p, 0.09, 0.32);
  }
}
window.seek(0);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-wallet-live.html'), html);
console.log('wrote clip-wallet-live.html', (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's', BEATS.length + ' beats');
