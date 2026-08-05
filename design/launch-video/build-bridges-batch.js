// Four launch clips for the 2026-08-04 bridge batch — Sentry, Vercel,
// PagerDuty, and the two package registries (npm + PyPI, one bridge).
//
// Every headline, row title and honesty line is grounded in the shipped
// source: each bridge's own doc header and its real `String(localized:)`
// title shapes —
//   Sentry     "[Regressed] · project · issue title"   (SentryShape.title)
//   Vercel     "[Build failed] · project · subject"    (VercelShape.title)
//   PagerDuty  "[Resolved after 41 min] · service · what"  (PagerDutyShape)
//   npm/PyPI   "react 19.2.0" / "Deprecated · request"  (PackageShape)
//
// One generator, four clips, so the house template stays in one place:
//   node build-bridges-batch.js          writes clip-<name>-editorial.html
//   node render.js clip-<name>-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const INK = '#14110d', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF',
      ORANGE = '#FF6B4A', AMBER = '#ff9f0a';

/* ------------------------------------------------------------------ *
 * The shared editorial template. Each clip supplies BEATS (kick/head/
 * accent/tag), the comp markup, its own scene CSS, and an animateComp.
 * ------------------------------------------------------------------ */
function clip({ name, mast, accent, beats, comps, css, anim }) {
  const INTRO = 0.45, BEAT = 3.15;
  const OUT_AT = INTRO + beats.length * BEAT, TOTAL = OUT_AT + 1.9;
  const DATA = beats.map(b => ({ kick: b.kick, head: b.head, accent: b.accent }));
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
.head{position:absolute;left:70px;top:288px;right:70px;font-size:88px;line-height:1.0;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0d0d09;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
/* shared row grammar */
.row{display:flex;align-items:center;gap:20px;padding:22px 24px;border-radius:20px;background:rgba(255,255,255,.05);margin-bottom:16px;will-change:opacity,transform;}
.pill{flex:none;font-size:19px;font-weight:800;padding:9px 16px;border-radius:11px;font-family:ui-monospace,monospace;}
.rt{font-size:25px;font-weight:750;line-height:1.3;}
.rs{font-size:20px;color:rgba(255,255,255,.45);margin-top:4px;}
.note{margin-top:26px;text-align:center;font-size:22px;font-weight:650;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.note em{font-style:normal;font-weight:750;}
/* the struck-through tally, used by three of the four */
.cnt{display:flex;align-items:center;justify-content:space-between;padding:19px 6px;border-bottom:1px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.cnt .l{font-size:25px;font-weight:650;color:rgba(255,255,255,.55);text-decoration:line-through;text-decoration-color:${ORANGE};text-decoration-thickness:3px;}
.cnt .r{font-size:19px;font-weight:800;color:${ORANGE};letter-spacing:.06em;}
.keep{display:flex;align-items:center;justify-content:space-between;padding:22px 6px;will-change:opacity,transform;}
.keep .l{font-size:25px;font-weight:800;color:#fff;}
.keep .r{font-size:19px;font-weight:800;color:${GREEN};letter-spacing:.06em;}
${css}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:#fff;background:${accent};padding:2px 10px;border-radius:6px;}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>${mast}</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>
${comps}
  <div class="kick mono" id="kick"></div>
  <div class="tagpill" id="tagpill"></div>
  <div class="head" id="head"></div>
  <div class="foot mono"><span>casberi.app</span><span>—</span></div>
  <div class="wipe" id="wipe"></div>
  <div class="outro" id="outro"><div class="b">Casberi</div><div class="u mono"><b>casberi.app</b></div></div>
</div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
const INTRO=${INTRO},BEAT=${BEAT},OUT_AT=${OUT_AT},N=${beats.length};
const D=${JSON.stringify(DATA)};window.TOTAL=${TOTAL};
const TAGS=${JSON.stringify(beats.map(b => b.tag || null))};
const ACCENT=${JSON.stringify(accent)};
const comps=[...document.querySelectorAll('.comp')];
function stag(sel,p,st,dur,dy){document.querySelectorAll(sel).forEach((r,k)=>{const rp=clamp01((p-k*st)/dur);r.style.opacity=rp;r.style.transform='translateY('+((1-back(rp))*(dy||20))+'px)';});}
function pop(el,p,from,dur,dy){if(!el)return 0;const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy||22))+'px)';return rp;}
function show(id,p,from,dur){const e=document.getElementById(id);if(e)e.style.opacity=clamp01((p-from)/(dur||0.24));}
window.seek=function(t){
  let active=Math.max(0,Math.min(N-1,Math.floor((t-INTRO)/BEAT)));
  const bs=INTRO+active*BEAT, local=t-bs, acc=D[active].accent, pIn=clamp01((local-0.26)/1.9);
  let coverAcc=acc,wipeX=200;const bounds=[];for(let k=1;k<N;k++)bounds.push({t:INTRO+k*BEAT,c:D[k].accent});bounds.push({t:OUT_AT,c:'#14110d'});
  for(const b of bounds){const p=(t-(b.t-0.34))/0.68;if(p>=0&&p<=1){wipeX=(1-p)*135-p*135*1.15;coverAcc=b.c;}}
  const wp=document.getElementById('wipe');wp.style.background=coverAcc;wp.style.transform='skewX(-9deg) translateX('+wipeX+'%)';
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.6))+')';
  const wm=document.getElementById('wm');wm.textContent=D[active].kick;wm.style.fontSize=Math.max(40,Math.min(240,780/(0.6*D[active].kick.length)))+'px';wm.style.color=acc;wm.style.opacity=0.09*clamp01(local/0.4);wm.style.transform='translateY('+((1-easeOut(clamp01(local/0.5)))*30)+'px)';
  const ki=document.getElementById('kick');ki.textContent=D[active].kick;ki.style.color=acc;const kin=clamp01(local/0.4);ki.style.opacity=easeOut(kin);ki.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';
  const tag=document.getElementById('tagpill');
  if(TAGS[active]){tag.textContent=TAGS[active];tag.style.background=ACCENT;tag.style.color='#fff';tag.style.opacity=easeOut(kin);tag.style.transform='translateX('+((1-easeOut(kin))*-40)+'px)';}
  else{tag.style.opacity=0;}
  const he=document.getElementById('head');he.innerHTML=D[active].head.replace(/\\n/g,'<br>');const hin=clamp01((local-0.06)/0.5);he.style.opacity=clamp01(local/0.2);he.style.transform='translateY('+((1-back(hin))*80)+'px)';
  comps.forEach((c,i)=>{const cbs=INTRO+i*BEAT,cl=t-cbs,cin=clamp01((cl-0.12)/0.6);const beatEnd=INTRO+(i+1)*BEAT,outp=clamp01((t-(beatEnd-0.3))/0.4);let op=(i===active?1:0)*clamp01(cl/0.15);if(t>OUT_AT)op*=(1-clamp01((t-OUT_AT)/0.25));const y=(1-back(cin))*180+outp*200+Math.sin(t*0.9+i)*5;const rot=(-2.2)+(1-easeOut(cin))*-5+outp*4;c.style.opacity=op;c.style.transform='translateY('+y+'px) rotate('+rot+'deg)';});
  animateComp(active,pIn,t,local);
  const fo=(t>OUT_AT)?(1-clamp01((t-OUT_AT)/0.25)):1;['kick','head'].forEach(id=>{const e=document.getElementById(id);e.style.opacity=Math.min(+e.style.opacity||1,fo);});
  document.getElementById('outro').style.opacity=easeOut(clamp01((t-(OUT_AT+0.25))/0.5));
};
function animateComp(i,p,t,local){
${anim}
}
window.seek(0);
</script></body></html>`;
  const file = `clip-${name}-editorial.html`;
  fs.writeFileSync(path.join(__dirname, file), html);
  console.log('wrote', file, (html.length / 1024).toFixed(0) + 'KB', TOTAL.toFixed(1) + 's');
}

/* =============================== SENTRY ================================ */
clip({
  name: 'sentry', mast: 'SENTRY', accent: '#e1567c',
  beats: [
    { kick: 'THE FILTER',  head: "1,204 times isn't\nnews. Once is.",       accent: ORANGE, tag: 'NEW' },
    { kick: 'IT CAME BACK', head: 'The one you closed,\nback again.',       accent: INK },
    { kick: 'WHERE',       head: 'The project, and\nwhere in your code.',   accent: INK },
    { kick: 'NEVER',       head: 'No stack traces.\nNo one who hit it.',    accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">WHAT NEVER LANDS</div>
    <div class="cnt" data-i="0"><span class="l">1,204 events</span><span class="r">A COUNT</span></div>
    <div class="cnt" data-i="1"><span class="l">318 users affected</span><span class="r">A COUNT</span></div>
    <div class="cnt" data-i="2"><span class="l">14-day sparkline</span><span class="r">A COUNT</span></div>
    <div class="keep" id="keep0"><span class="l">It didn't exist. Now it does.</span><span class="r">LANDS</span></div>
    <div class="note" id="note0">Sentry leads with all four. A tally renders beautifully<br>and means nothing on its own.</div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">THE ONE NOTHING ELSE TELLS YOU</div>
    <div class="row" id="r1a"><span class="pill" style="background:rgba(225,86,124,.2);color:#e1567c">Regressed</span><div><div class="rt">checkout-api · TypeError: cannot read 'total'</div><div class="rs">You closed this in March</div></div></div>
    <div class="row" id="r1b"><span class="pill" style="background:rgba(255,159,10,.18);color:${AMBER}">Escalating</span><div><div class="rt">web · Failed to fetch</div><div class="rs">Sentry un-archived it on your behalf</div></div></div>
    <div class="note" id="note1">A regression is the shape a feed is good at —<br><em>and the second one lands too, not just the first.</em></div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">HOW IT LANDS</div>
    <div class="card" id="card2">
      <div class="ct"><b>Regressed</b> · <b>checkout-api</b> · TypeError: cannot read 'total' of undefined</div>
      <div class="cculprit mono">src/cart/summary.ts &nbsp;in&nbsp; renderTotal</div>
      <div class="ctag">Issue</div>
    </div>
    <div class="note" id="note2">The outcome leads, so the clamp can't eat it.</div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">WHAT IT NEVER READS</div>
    <div class="cnt" data-j="0"><span class="l">The event payload</span><span class="r">NEVER</span></div>
    <div class="cnt" data-j="1"><span class="l">The stack trace</span><span class="r">NEVER</span></div>
    <div class="cnt" data-j="2"><span class="l">Who hit the error</span><span class="r">NEVER</span></div>
    <div class="note" id="note3">A read-only token, and the issue list only.<br><em>Your users' data never leaves Sentry.</em></div>
  </div>`,
  css: `
.card{background:rgba(255,255,255,.06);border-radius:26px;padding:32px;will-change:opacity,transform;}
.ct{font-size:29px;font-weight:700;line-height:1.35;} .ct b{font-weight:800;}
.cculprit{margin-top:18px;font-size:22px;color:rgba(255,255,255,.5);}
.ctag{display:inline-block;margin-top:22px;font-size:19px;font-weight:750;padding:9px 18px;border-radius:100px;background:rgba(225,86,124,.16);color:#e1567c;}`,
  anim: `
  if(i===0){stag('#comp0 .cnt',p,0.13,0.24,16);pop(document.getElementById('keep0'),p,0.5,0.26,20);show('note0',p,0.74);}
  else if(i===1){pop(document.getElementById('r1a'),p,0.03,0.28,20);pop(document.getElementById('r1b'),p,0.34,0.28,20);show('note1',p,0.68);}
  else if(i===2){pop(document.getElementById('card2'),p,0.04,0.3,24);show('note2',p,0.6);}
  else if(i===3){stag('#comp3 .cnt',p,0.14,0.24,16);show('note3',p,0.64);}`,
});

/* =============================== VERCEL ================================ */
clip({
  name: 'vercel', mast: 'VERCEL', accent: '#111',
  beats: [
    { kick: 'THE NOISE',   head: "A dozen previews\na day. All fine.",     accent: ORANGE, tag: 'NEW' },
    { kick: 'WHAT LANDS',  head: 'It went live.\nOr it broke.',            accent: INK },
    { kick: 'THE BRANCH',  head: "Which build failed,\nand what was in it.", accent: INK },
    { kick: 'READ-ONLY',   head: 'One verb.\nNever your env vars.',        accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">A NORMAL WORKING DAY</div>
    <div class="prev" id="prevwrap">
      <div class="pv" data-i="0">preview · ✓</div><div class="pv" data-i="1">preview · ✓</div>
      <div class="pv" data-i="2">preview · ✓</div><div class="pv" data-i="3">preview · ✓</div>
      <div class="pv" data-i="4">preview · ✓</div><div class="pv" data-i="5">preview · ✓</div>
      <div class="pv" data-i="6">preview · ✓</div><div class="pv" data-i="7">preview · ✓</div>
      <div class="pv" data-i="8">preview · ✓</div><div class="pv" data-i="9">preview · ✓</div>
      <div class="pv" data-i="10">preview · ✓</div><div class="pv" data-i="11">preview · ✓</div>
    </div>
    <div class="note" id="note0">Landing every one turns your feed into a git log.<br><em>A successful preview stays out.</em></div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">EXACTLY TWO SHAPES</div>
    <div class="row" id="r1a"><span class="pill" style="background:rgba(63,185,80,.18);color:${GREEN}">Live</span><div><div class="rt">casberi-web · ship the walkthrough</div><div class="rs">Production · your users have it now</div></div></div>
    <div class="row" id="r1b"><span class="pill" style="background:rgba(255,69,58,.18);color:${RED}">Build failed</span><div><div class="rt">casberi-web · fix the flaky test</div><div class="rs">Any target — a broken preview is the point</div></div></div>
    <div class="note" id="note1">The moment your users got the new thing —<br><em>and every build that didn't make it.</em></div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">STILL BUILDING? NOT YET.</div>
    <div class="row ghost" id="r2a"><span class="pill" style="background:rgba(255,255,255,.08);color:rgba(255,255,255,.4)">Building</span><div><div class="rt" style="color:rgba(255,255,255,.42)">casberi-web · wip</div><div class="rs">On screen in Vercel right now</div></div></div>
    <div class="row" id="r2b"><span class="pill" style="background:rgba(255,69,58,.18);color:${RED}">Canceled</span><div><div class="rt">casberi-api · bump deps</div><div class="rs">vercel.app/casberi-api</div></div></div>
    <div class="note" id="note2">An in-flight build carries no outcome and would be<br>stale in ninety seconds. <em>Only what's over lands.</em></div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">WHAT THE TOKEN IS USED FOR</div>
    <div class="keep" data-k="0"><span class="l">GET the deploy list</span><span class="r">THE ONLY ONE</span></div>
    <div class="cnt" data-k="1"><span class="l">Deploy or promote</span><span class="r">NEVER</span></div>
    <div class="cnt" data-k="2"><span class="l">Roll back or cancel</span><span class="r">NEVER</span></div>
    <div class="cnt" data-k="3"><span class="l">Read environment variables</span><span class="r">NEVER</span></div>
    <div class="note" id="note3">Vercel tokens can't be scoped read-only, so the promise<br>is kept by conduct: <em>one verb, one path.</em></div>
  </div>`,
  css: `
.prev{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;}
.pv{padding:20px 12px;border-radius:16px;background:rgba(255,255,255,.045);text-align:center;font-size:20px;font-weight:650;color:rgba(255,255,255,.4);font-family:ui-monospace,monospace;will-change:opacity,transform;}
.row.ghost{background:rgba(255,255,255,.025);}`,
  anim: `
  if(i===0){document.querySelectorAll('#comp0 .pv').forEach((c,k)=>{const rp=clamp01((p-k*0.045)/0.2);c.style.opacity=rp*0.9;c.style.transform='scale('+(0.86+0.14*back(rp))+')';});show('note0',p,0.66);}
  else if(i===1){pop(document.getElementById('r1a'),p,0.03,0.28,20);pop(document.getElementById('r1b'),p,0.34,0.28,20);show('note1',p,0.68);}
  else if(i===2){pop(document.getElementById('r2a'),p,0.03,0.28,20);pop(document.getElementById('r2b'),p,0.34,0.28,20);show('note2',p,0.68);}
  else if(i===3){stag('#comp3 [data-k]',p,0.12,0.24,16);show('note3',p,0.66);}`,
});

/* ============================== PAGERDUTY ============================== */
clip({
  name: 'pagerduty', mast: 'PAGERDUTY', accent: '#06ac38',
  beats: [
    { kick: '2:14 AM',     head: 'Something caught\nfire.',                accent: RED, tag: 'NEW' },
    { kick: 'AND AFTER',   head: 'And how long\nit burned.',               accent: INK },
    { kick: 'THE RECORD',  head: 'Three weeks later,\nyou still know.',    accent: INK },
    { kick: 'READ-ONLY',   head: "It can't page\nanyone.",                 accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">IT LANDS WHEN IT FIRES</div>
    <div class="row" id="r0a"><span class="pill" style="background:rgba(255,69,58,.2);color:${RED}">High</span><div><div class="rt">Checkout API · Checkout is down</div><div class="rs">Triggered 2:14 AM</div></div></div>
    <div class="row" id="r0b"><span class="pill" style="background:rgba(255,159,10,.18);color:${AMBER}">Low</span><div><div class="rt">Workers · Queue depth over threshold</div><div class="rs">Triggered 2:31 AM</div></div></div>
    <div class="note" id="note0">What fired, on which service, how urgent —<br>stamped with the incident's own time.</div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">AND AGAIN WHEN IT'S OUT</div>
    <div class="row" id="r1a"><span class="pill" style="background:rgba(6,172,56,.2);color:#06ac38">Resolved</span><div><div class="rt">Resolved after 41 min · Checkout API · Checkout is down</div><div class="rs">Both ends from PagerDuty itself</div></div></div>
    <div class="dur" id="dur1"><span class="db"><i style="width:100%"></i></span><span class="dlab">2:14 AM → 2:55 AM</span></div>
    <div class="note" id="note1">The duration is the entire reason the second row exists.</div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">WHY THAT MATTERS LATER</div>
    <div class="qb" id="q2">What happened to checkout last month?</div>
    <div class="ab" id="a2">It went down at <em>2:14 AM on the 12th</em> and was resolved after <em>41 minutes</em>.</div>
    <div class="note" id="note2">"Checkout is down" you already knew at 2am.<br><em>This is the record you want in the postmortem.</em></div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">THE KEY IS READ-ONLY AT CREATION</div>
    <div class="keep" data-k="0"><span class="l">Read your incidents</span><span class="r">YES</span></div>
    <div class="cnt" data-k="1"><span class="l">Trigger an incident</span><span class="r">NEVER</span></div>
    <div class="cnt" data-k="2"><span class="l">Acknowledge or resolve</span><span class="r">NEVER</span></div>
    <div class="note" id="note3">A read-write key can wake whoever is on call at 3am.<br><em>The setup step names the checkbox for that reason.</em></div>
  </div>`,
  css: `
.dur{margin-top:22px;}
.db{display:block;height:20px;border-radius:11px;background:rgba(255,255,255,.08);overflow:hidden;}
.db i{display:block;height:100%;border-radius:11px;background:linear-gradient(90deg,${RED},#06ac38);transform-origin:left;}
.dlab{display:block;margin-top:12px;font-size:20px;color:rgba(255,255,255,.45);font-family:ui-monospace,monospace;}
.qb{align-self:flex-end;max-width:78%;background:${BLUE};color:#fff;border-radius:24px 24px 6px 24px;padding:20px 26px;font-size:26px;font-weight:640;line-height:1.35;will-change:opacity,transform;}
.ab{align-self:flex-start;max-width:90%;background:rgba(255,255,255,.08);border-radius:24px 24px 24px 6px;padding:22px 26px;font-size:25px;font-weight:600;line-height:1.45;margin-top:18px;will-change:opacity,transform;}
.ab em{font-style:normal;color:#fff;font-weight:750;}`,
  anim: `
  if(i===0){pop(document.getElementById('r0a'),p,0.03,0.28,20);pop(document.getElementById('r0b'),p,0.32,0.28,20);show('note0',p,0.66);}
  else if(i===1){pop(document.getElementById('r1a'),p,0.03,0.28,20);
    const d=document.getElementById('dur1');if(d){d.style.opacity=clamp01((p-0.3)/0.2);d.querySelector('.db i').style.transform='scaleX('+easeOut(clamp01((p-0.34)/0.4))+')';}
    show('note1',p,0.72);}
  else if(i===2){pop(document.getElementById('q2'),p,0.02,0.24,18);pop(document.getElementById('a2'),p,0.3,0.28,20);show('note2',p,0.68);}
  else if(i===3){stag('#comp3 [data-k]',p,0.14,0.24,16);show('note3',p,0.62);}`,
});

/* =========================== NPM + PYPI ================================ */
clip({
  name: 'packages', mast: 'NPM · PYPI', accent: '#cb3837',
  beats: [
    { kick: 'YOUR DEPS',   head: 'The packages you\nactually depend on.',  accent: BLUE, tag: 'NEW' },
    { kick: 'ON RELEASE',  head: 'You hear when\nthey ship.',              accent: INK },
    { kick: 'DEPRECATED',  head: 'Not six months\nlate.',                  accent: ORANGE },
    { kick: 'KEYLESS',     head: 'No account.\nNothing to mint.',          accent: GREEN },
  ],
  comps: `
  <div class="comp" id="comp0">
    <div class="shd mono">NAME WHAT YOU DEPEND ON</div>
    <div class="pkgs">
      <span class="pk" data-i="0">react</span><span class="pk" data-i="1">next</span>
      <span class="pk" data-i="2">zod</span><span class="pk" data-i="3">requests</span>
      <span class="pk" data-i="4">fastapi</span><span class="pk" data-i="5">pydantic</span>
    </div>
    <div class="regs" id="regs0"><span>npm</span><span>PyPI</span></div>
    <div class="note" id="note0">Two registries, one list. Add a name, that's the setup.</div>
  </div>
  <div class="comp" id="comp1">
    <div class="shd mono">A NEW VERSION IS AN EVENT</div>
    <div class="row" id="r1a"><span class="pill" style="background:rgba(203,56,55,.18);color:#e2564f">npm</span><div><div class="rt">react 19.2.0</div><div class="rs">Stamped with when it actually shipped</div></div></div>
    <div class="row" id="r1b"><span class="pill" style="background:rgba(55,118,171,.24);color:#6ea8dc">PyPI</span><div><div class="rt">fastapi 0.121.0</div><div class="rs">Sorts back to its real release date</div></div></div>
    <div class="note" id="note1">Downloads and dependents never land —<br><em>a registry is a counter dressed as a database.</em></div>
  </div>
  <div class="comp" id="comp2">
    <div class="shd mono">THE ONE YOU'D MISS</div>
    <div class="row" id="r2a"><span class="pill" style="background:rgba(255,107,74,.2);color:${ORANGE}">npm</span><div><div class="rt">Deprecated · request</div><div class="rs">"no longer maintained — use fetch"</div></div></div>
    <div class="note" id="note2">Rare, permanent, and exactly the thing you find out<br>about half a year late. <em>npm only — PyPI has no equivalent, and we say so.</em></div>
  </div>
  <div class="comp" id="comp3">
    <div class="shd mono">WHAT IT COSTS TO RUN</div>
    <div class="bigno" id="bigno">$0</div>
    <div class="bignosub" id="bignosub">No account. No key. No sign-up.</div>
    <div class="note" id="note3">Read straight from the public registries by your phone.<br><em>There is no token, so there's nothing a leak could spend.</em></div>
  </div>`,
  css: `
.pkgs{display:flex;flex-wrap:wrap;gap:14px;justify-content:center;}
.pk{font-size:27px;font-weight:750;padding:14px 24px;border-radius:100px;background:rgba(255,255,255,.07);font-family:ui-monospace,monospace;will-change:opacity,transform;}
.regs{display:flex;gap:14px;justify-content:center;margin-top:30px;will-change:opacity;}
.regs span{font-size:21px;font-weight:800;letter-spacing:.06em;padding:10px 22px;border-radius:12px;background:rgba(255,255,255,.06);color:rgba(255,255,255,.6);}
.bigno{text-align:center;font-size:130px;font-weight:800;letter-spacing:-.04em;color:${GREEN};will-change:opacity,transform;}
.bignosub{margin-top:8px;text-align:center;font-size:27px;font-weight:700;color:#fff;will-change:opacity;}`,
  anim: `
  if(i===0){document.querySelectorAll('#comp0 .pk').forEach((c,k)=>{const rp=clamp01((p-k*0.07)/0.24);c.style.opacity=rp;c.style.transform='translateY('+((1-back(rp))*18)+'px)';});show('regs0',p,0.5);show('note0',p,0.7);}
  else if(i===1){pop(document.getElementById('r1a'),p,0.03,0.28,20);pop(document.getElementById('r1b'),p,0.32,0.28,20);show('note1',p,0.66);}
  else if(i===2){pop(document.getElementById('r2a'),p,0.04,0.3,22);show('note2',p,0.56);}
  else if(i===3){pop(document.getElementById('bigno'),p,0.04,0.3,26);show('bignosub',p,0.34);show('note3',p,0.58);}`,
});
