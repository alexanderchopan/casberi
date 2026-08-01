// Four "closes a blind spot in your total" promos — EDITORIAL, no app
// screenshots. ONE generator, four clips, sharing the same card vocabulary
// (typed field / host-read rows / checklist rows / stat reveal / close chips)
// since all four are the same shape of feature: something that used to be
// invisible to the combined portfolio total now counts.
//
//   Ethereum validators — Model/EthValidatorWatch.swift (2026-07-27)
//     Watched by INDEX (no free path from a wallet address to its
//     validators on the beacon chain — a Solana stake account can be found
//     by withdraw authority, Ethereum can't). Keyless:
//     ethereum-beacon-api.publicnode.com, the standard Beacon API. An
//     exiting-but-not-fully-exited validator still counts. Read-only —
//     never stakes, exits, or moves anything.
//   Solana staking — Model/SolanaStaking.swift (2026-07-27)
//     Read via getProgramAccounts filtered by WITHDRAW authority (not
//     staker) — one request, dataSize:200 narrows first. A deactivating
//     account still counts until the epoch actually passes.
//   Gemini Exchange — Model/ExchangeBridge.swift (2026-07-27)
//     MUST say "Gemini Exchange", never bare "Gemini" — that name already
//     belongs to the Gemini AI-chat importer bridge. Gemini's own read-only
//     "Auditor" API-key role, checked via POST /v1/roles before the key is
//     ever stored; isTrader/isFundManager refuses it.
//   Binance — Model/ExchangeBridge.swift (2026-07-27)
//     A pasted key is checked (canTrade/canWithdraw) before storage; either
//     one refuses and hands the key back.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-<file>.html --size=1080x1920
const fs = require('fs'), path = require('path');

const ETH = '#627eea', SOL_G = '#14F195', GEMINI = '#00DCFA', BINANCE = '#F0B90B';
const GREEN = '#3fb950', ORANGE = '#FF6B4A';

const CLIPS = [
  {
    file: 'clip-eth-validator-2026.html', mast: 'ETH VALIDATORS', accent: ETH,
    beats: [
      { kick: 'BY ITS INDEX',   head: 'Your validator.\nBy its own number.', card: 'field', fieldVal: '741852', fieldLabel: 'Validator index', fieldSub: 'The number your staking client already shows you' },
      { kick: 'KEYLESS',        head: 'No account.\nNo key.',                card: 'hosts', hosts: [['ethereum-beacon-api.publicnode.com', true]], hostNote: 'The standard public Beacon API — one request, any number of indices' },
      { kick: 'IT COUNTS NOW',  head: 'Staked ETH\njoins your total.',       card: 'stat', statBig: '+32.1 ETH', statSub: 'Was invisible to your combined total. Now it isn\'t.' },
      { kick: 'STILL COUNTED',  head: "Exiting doesn't\nmean gone yet.",     card: 'checklist', rows: [['Active', true], ['Exiting — still holds its balance', true], ['Fully exited — no longer counted', false]] },
      { kick: 'READ ONLY',      head: 'Reads balance\nand status. That\'s all.', card: 'close', chips: ['Never stakes', 'Never exits', 'Never moves anything'] },
    ],
  },
  {
    file: 'clip-solana-staking-2026.html', mast: 'SOLANA STAKING', accent: SOL_G,
    beats: [
      { kick: 'THE BLIND SPOT', head: 'Staked SOL wasn\'t\nin your total.',  card: 'stat', statBig: '32 SOL', statSub: 'Delegated — and invisible to every read until now' },
      { kick: 'WHOSE MONEY',    head: 'Read by withdraw\nauthority.',        card: 'checklist', rows: [['Withdraw authority — it\'s their money', true], ['Staker authority alone — not enough', false]] },
      { kick: 'ONE CALL',       head: 'One request.\nNot a thousand.',       card: 'hosts', hosts: [['getProgramAccounts', true]], hostNote: 'Narrowed by account size first — one filtered call, not a scan' },
      { kick: 'STILL COUNTS',   head: 'Cooling down\nstill counts.',         card: 'checklist', rows: [['Active', true], ['Deactivating — still real SOL', true], ['Fully inactive — no longer counted', false]] },
      { kick: 'KEYLESS',        head: 'No key.\nNo account.',                card: 'close', chips: ['Same wallet you already watch', 'Nothing about "watching" changes'] },
    ],
  },
  {
    file: 'clip-gemini-exchange-2026.html', mast: 'GEMINI EXCHANGE', accent: GEMINI,
    beats: [
      { kick: 'ONE ROLE',        head: 'Auditor.\nRead-only, by design.',    card: 'field', fieldVal: 'account-xxxxxxxxxxxx', fieldLabel: 'Gemini API key', fieldSub: 'Create it with the Auditor role — nothing else' },
      { kick: 'CHECKED FIRST',   head: 'Checked before\nit\'s ever stored.', card: 'hosts', hosts: [['POST /v1/roles', true]], hostNote: 'Gemini\'s own answer to "what can this key do?" — asked first' },
      { kick: 'REFUSED, NOT TRUSTED', head: 'Can trade?\nHanded back.',      card: 'checklist', rows: [['isAuditor — accepted', true], ['isTrader — refused', false], ['isFundManager — refused', false] ] },
      { kick: 'IT JOINS THE TOTAL', head: 'Your balance,\nin the total.',    card: 'stat', statBig: '+$4,120', statSub: 'Folded into your combined total and map, like every venue here' },
      { kick: 'READ ONLY',       head: 'No order.\nNo withdrawal.',          card: 'close', chips: ['No trade reachable', 'No withdrawal reachable', 'No transfer reachable'] },
    ],
  },
  {
    file: 'clip-binance-2026.html', mast: 'BINANCE', accent: BINANCE,
    beats: [
      { kick: 'ONE MORE VENUE', head: 'Binance joins\nthe lineup.',          card: 'field', fieldVal: 'a1b2c3d4e5f6…', fieldLabel: 'Binance API key', fieldSub: 'View-only — reading enabled, nothing else' },
      { kick: 'CHECKED FIRST',  head: 'Checked before\nit\'s ever stored.',  card: 'hosts', hosts: [['GET /api/v3/account', true]], hostNote: 'Asked what the key can do — before it\'s ever saved' },
      { kick: 'HANDED BACK',    head: 'Can trade?\nCan withdraw?\nHanded back.', card: 'checklist', rows: [['canTrade — refused', false], ['canWithdraw — refused', false], ['Read-only — accepted', true]] },
      { kick: 'IT JOINS THE TOTAL', head: 'Your balance,\none less blind spot.', card: 'stat', statBig: '+$2,840', statSub: 'Folded into your combined total, same as every wallet here' },
      { kick: 'READ ONLY',       head: 'No order.\nNo withdrawal.',          card: 'close', chips: ['No trade reachable', 'No withdrawal reachable', 'No transfer reachable'] },
    ],
  },
];

function cardHTML(b, accent) {
  if (b.card === 'field') return `
    <div class="shd mono">${b.fieldLabel.toUpperCase()}</div>
    <div class="field"><span id="typed"></span><span class="caret" id="caret"></span></div>
    <div class="fsub">${b.fieldSub}</div>
    <div class="pledge"><span class="pdot" style="background:${accent}"></span><span>Checked with the venue before it's ever stored.</span></div>`;
  if (b.card === 'hosts') return `
    <div class="shd mono">HOW IT READS</div>
    <div class="hostrow">${b.hosts.map(([h]) => `<div class="hnode" data-i="0"><span class="hd" style="background:${GREEN}"></span><span class="hn">${h}</span></div>`).join('')}</div>
    <div class="hostnote">${b.hostNote}</div>`;
  if (b.card === 'stat') return `
    <div class="shd mono">FOLDED IN</div>
    <div class="statwrap"><div class="statbig" id="statbig" style="color:${accent}">${b.statBig}</div><div class="statsub">${b.statSub}</div></div>`;
  if (b.card === 'checklist') return `
    <div class="shd mono">WHAT COUNTS</div>
    ${b.rows.map(([t, ok], i) => `<div class="crow" data-i="${i}"><span class="cmark ${ok ? 'ok' : 'no'}">${ok ? '✓' : '✕'}</span><span class="ct">${t}</span></div>`).join('')}`;
  if (b.card === 'close') return `
    <div class="shd mono">READ-ONLY</div>
    <div class="chipwrap">${b.chips.map((c, i) => `<div class="chip2" data-i="${i}"><span class="chipdot"></span>${c}</div>`).join('')}</div>`;
  return '';
}

function build(N) {
  const INTRO = 0.45, BEAT = 2.9;
  const OUT_AT = INTRO + N.beats.length * BEAT, TOTAL = OUT_AT + 1.9;
  const DATA = N.beats.map(b => ({ kick: b.kick, head: b.head, accent: N.accent }));

  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.stage{position:absolute;inset:0;overflow:hidden;background:#EEEAE1;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.wm{position:absolute;right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;font-weight:800;letter-spacing:-.04em;opacity:.08;will-change:opacity,transform;}
.kick{position:absolute;left:74px;top:238px;font-size:32px;letter-spacing:.14em;font-weight:600;will-change:transform,opacity;}
.head{position:absolute;left:70px;top:284px;right:70px;font-size:94px;line-height:1;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0a16;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
/* the eyebrow stays pinned to the card's top edge; the rest centers under it */
/* field */
.field{background:rgba(255,255,255,.07);border-radius:100px;padding:24px 30px;font-size:27px;font-weight:650;font-family:ui-monospace,monospace;box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);display:flex;align-items:center;overflow:hidden;}
.caret{width:3px;height:30px;background:#fff;margin-left:3px;display:inline-block;flex:none;}
.fsub{margin-top:18px;text-align:center;font-size:22px;color:rgba(255,255,255,.44);font-weight:600;}
.pledge{margin-top:28px;display:flex;align-items:center;gap:16px;justify-content:center;font-size:22px;color:rgba(255,255,255,.6);font-weight:600;text-align:center;}
.pdot{width:12px;height:12px;border-radius:50%;flex:none;}
/* hosts */
.hostrow{display:flex;flex-direction:column;gap:14px;}
.hnode{display:flex;align-items:center;gap:16px;background:rgba(255,255,255,.05);border-radius:16px;padding:20px 24px;will-change:opacity,transform;}
.hnode .hd{width:12px;height:12px;border-radius:50%;flex:none;}
.hnode .hn{font-size:24px;font-weight:650;font-family:ui-monospace,monospace;color:rgba(255,255,255,.85);}
.hostnote{margin-top:24px;text-align:center;font-size:22px;color:rgba(255,255,255,.44);font-weight:600;line-height:1.4;}
/* stat */
.statwrap{text-align:center;}
.statbig{font-size:96px;font-weight:800;letter-spacing:-.02em;will-change:opacity,transform;}
.statsub{margin-top:18px;font-size:24px;color:rgba(255,255,255,.55);font-weight:600;line-height:1.4;}
/* checklist */
.crow{display:flex;align-items:center;gap:20px;padding:18px 0;will-change:opacity,transform;}
.cmark{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:800;}
.cmark.ok{background:rgba(63,185,80,.18);color:${GREEN};}
.cmark.no{background:rgba(255,107,74,.16);color:${ORANGE};}
.ct{font-size:26px;font-weight:650;}
/* close chips */
.chipwrap{display:flex;flex-direction:column;gap:14px;}
.chip2{display:flex;align-items:center;gap:16px;font-size:26px;font-weight:650;color:rgba(255,255,255,.8);will-change:opacity,transform;}
.chipdot{width:12px;height:12px;border-radius:50%;background:${GREEN};flex:none;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${N.accent};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>${N.mast}</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>
  ${N.beats.map((b, i) => `<div class="comp" id="comp${i}">${cardHTML(b, N.accent)}</div>`).join('\n')}
  <div class="kick mono" id="kick"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${N.beats.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const KINDS=${JSON.stringify(N.beats.map(b=>b.card))};
const FIELDVALS=${JSON.stringify(N.beats.map(b=>b.fieldVal||''))};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.7);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(50,Math.min(300,880/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
  const kind=KINDS[i];
  if(kind==='field'){
    const val=FIELDVALS[i];
    const n=Math.round(clamp01((p-0.06)/0.36)*val.length);
    document.getElementById('typed').textContent=val.slice(0,n);
    document.getElementById('caret').style.opacity=(n<val.length)?((Math.floor(t*2.6)%2)?1:0.15):0;
    document.querySelector('#comp'+i+' .fsub').style.opacity=clamp01((p-0.46)/0.24);
    document.querySelector('#comp'+i+' .pledge').style.opacity=clamp01((p-0.6)/0.26);
  } else if(kind==='hosts'){
    stag('#comp'+i+' .hnode',p,0.16,0.3,18);
    document.querySelector('#comp'+i+' .hostnote').style.opacity=clamp01((p-0.42)/0.3);
  } else if(kind==='stat'){
    const sp=clamp01((p-0.08)/0.38);
    const sb=document.querySelector('#comp'+i+' .statbig');
    sb.style.opacity=sp;sb.style.transform='scale('+(0.7+0.3*back(sp))+')';
    document.querySelector('#comp'+i+' .statsub').style.opacity=clamp01((p-0.4)/0.3);
  } else if(kind==='checklist'){
    stag('#comp'+i+' .crow',p,0.16,0.3,20);
  } else if(kind==='close'){
    stag('#comp'+i+' .chip2',p,0.15,0.3,18);
  }
}
window.seek(0);
</script></body></html>`;
}

for (const N of CLIPS) {
  const html = build(N);
  fs.writeFileSync(path.join(__dirname, N.file), html);
  const total = (0.45 + N.beats.length * 2.9 + 1.9).toFixed(1);
  console.log('wrote', N.file, (html.length/1024).toFixed(0)+'KB', total+'s');
}
