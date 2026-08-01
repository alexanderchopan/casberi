// Farcaster/Bluesky "inbound half" promo — EDITORIAL, no app screenshots.
// Grounded line-by-line in Model/SocialInbound.swift, Model/FarcasterSigners.swift,
// the recast/repost commit (9398f32), and docs/prd.md §239 (2026-07-31):
//   0 — every social read here was OUTBOUND (what an account posts/likes/is
//     mentioned in). Marking an account as "mine" turns on the inbound half:
//     replies received, likes received (can resurface your own post), new
//     followers land as things.
//   1 — the structural gap: a reply names its parent in the RECORD, not the
//     text, so mention-search can never find one. "Did anyone answer me?"
//     had no source at all until this pass.
//   2 — amplify: a recast/repost is a stronger curation signal than a like —
//     they put their own name on it. Farcaster shares the like code path;
//     Bluesky costs NO extra request (reposts were already arriving in the
//     author feed and getting silently discarded by the own-handle filter).
//   3 — which apps can post as you: Farcaster signers, read off the onchain
//     Key Registry, the WalletApprovals doctrine applied to social identity.
//     First sight shows the FULL historical inventory (unlike the wallet
//     sweeps' silent seed) because that list has never once been shown to you.
//   4 — read-only: it reads and previews, never posts, likes, follows, or
//     revokes on your behalf — the revoke happens on Farcaster's own settings.
// Deterministic (stills) -> render frame-by-frame:
//   node render.js clip-social-inbound-editorial.html --size=1080x1920
const fs = require('fs'), path = require('path');

const FC = '#855dcd', BSKY = '#0085ff', GREEN = '#3fb950', ORANGE = '#FF6B4A';
const BEATS = [
  { kick: 'NEW TODAY',          head: 'What happened\nto you.',            accent: FC,    tag: 'NEW TODAY' },
  { kick: 'THE STRUCTURAL GAP', head: "Replies never had\nan @ to find.",  accent: FC,    tag: null },
  { kick: 'STRONGER THAN A LIKE', head: 'A recast puts\ntheir name on it.', accent: BSKY,  tag: null },
  { kick: 'FOUND WHILE BUILDING', head: 'Reposts were already\narriving. Discarded.', accent: ORANGE, tag: null },
  { kick: 'WHO CAN POST AS YOU', head: 'Permissions you\nnever got to see.', accent: FC,    tag: null },
  { kick: 'READ-ONLY',          head: 'It reads.\nIt never posts.',        accent: GREEN, tag: null },
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
.comp{position:absolute;left:120px;top:800px;width:840px;height:860px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#120d1c;display:flex;flex-direction:column;justify-content:center;}
.comp > .shd{position:absolute;top:52px;left:52px;right:52px;margin:0;font-size:24px;letter-spacing:.12em;color:rgba(255,255,255,.45);}
.cap{margin-top:30px;font-size:26px;font-weight:650;color:rgba(255,255,255,.75);text-align:center;line-height:1.45;}
.cap b{color:#fff;}
/* 0 — the inbound list */
.irow{display:flex;align-items:center;gap:20px;padding:18px 0;will-change:opacity,transform;}
.irow .ii{width:52px;height:52px;border-radius:15px;flex:none;background:rgba(133,93,205,.18);color:${FC};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:20px;}
.irow .it{font-size:26px;font-weight:700;}
.irow .is{font-size:20px;color:rgba(255,255,255,.42);margin-top:3px;}
/* 1 — the reply bubble */
.replywrap{will-change:opacity,transform;}
.replybubble{background:rgba(255,255,255,.06);border-radius:20px;padding:26px 28px;}
.replybubble .rh{font-size:20px;font-weight:700;color:rgba(255,255,255,.5);margin-bottom:8px;}
.replybubble .rt{font-size:25px;font-weight:650;line-height:1.4;}
.replynote{margin-top:22px;text-align:center;font-size:21px;font-weight:700;color:${FC};will-change:opacity;}
/* 2 — amplify chips */
.amprow{display:flex;align-items:center;gap:18px;padding:17px 0;will-change:opacity,transform;}
.amptag{font-size:16px;font-weight:800;padding:8px 15px;border-radius:100px;flex:none;}
.amptxt{font-size:23px;font-weight:650;}
.ampnote{margin-top:20px;text-align:center;font-size:21px;font-weight:700;color:rgba(255,255,255,.55);}
/* 3 — the found bug */
.bugcard{background:rgba(255,107,74,.1);border:2px solid rgba(255,107,74,.3);border-radius:22px;padding:30px;text-align:center;will-change:opacity,transform;}
.bugcard .t{font-size:24px;font-weight:700;line-height:1.5;}
.bugcard .t b{color:${ORANGE};}
.bugfix{margin-top:22px;display:flex;align-items:center;justify-content:center;gap:14px;font-size:21px;font-weight:700;color:${GREEN};will-change:opacity;}
.bugfix i{width:38px;height:38px;border-radius:50%;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:19px;}
/* 4 — signers */
.sigrow{border-radius:18px;padding:22px 24px;background:rgba(255,255,255,.06);margin-bottom:14px;will-change:opacity,transform;}
.sigrow .st{font-size:22px;font-weight:700;line-height:1.4;}
.sigrow .st b{color:${FC};}
.signote{margin-top:18px;text-align:center;font-size:20px;color:rgba(255,255,255,.42);font-weight:600;}
/* 5 — read only */
.vrow{display:flex;align-items:center;gap:20px;padding:19px 0;font-size:27px;font-weight:650;will-change:opacity,transform;}
.vrow s{width:48px;height:48px;border-radius:50%;flex:none;background:rgba(255,107,74,.16);color:${ORANGE};display:flex;align-items:center;justify-content:center;font-size:23px;text-decoration:none;font-weight:700;}
.vgood{display:flex;align-items:center;gap:20px;margin-top:24px;font-size:26px;font-weight:700;color:${GREEN};will-change:opacity,transform;}
.vgood i{width:46px;height:46px;border-radius:50%;flex:none;background:${GREEN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${FC};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>SOCIAL</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <div class="shd mono">EVERY READ HERE WAS OUTBOUND — UNTIL NOW</div>
    <div class="irow" data-i="0"><span class="ii">↩</span><div><div class="it">Replies received</div><div class="is">No @ names its parent — invisible until now</div></div></div>
    <div class="irow" data-i="1"><span class="ii">♥</span><div><div class="it">Likes received</div><div class="is">Can resurface your own post</div></div></div>
    <div class="irow" data-i="2"><span class="ii">+</span><div><div class="it">New followers</div><div class="is">Land as things, not a count</div></div></div>
    <div class="cap">One flag — mark an account as yours —<br><b>and the other half turns on.</b></div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">A REPLY NAMES ITS PARENT IN THE RECORD</div>
    <div class="replywrap">
      <div class="replybubble"><div class="rh">Reply on your cast</div><div class="rt">"finally — this is exactly what I wanted from this app"</div></div>
    </div>
    <div class="replynote" id="replynote">Not in the text. Search could never see it.</div>
    <div class="cap">"Did anyone answer me?"<br><b>had no source at all, until this pass.</b></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">FARCASTER + BLUESKY, ONE MARKER</div>
    <div class="amprow" data-i="0"><span class="amptag" style="background:rgba(133,93,205,.18);color:${FC}">RECAST</span><span class="amptxt">Farcaster — same read as a like, one type over</span></div>
    <div class="amprow" data-i="1"><span class="amptag" style="background:rgba(0,133,255,.18);color:${BSKY}">REPOSTED</span><span class="amptxt">Bluesky — costs no extra request</span></div>
    <div class="ampnote" id="ampnote">A like is approval. A recast puts their name on it.</div>
    <div class="cap">The stronger curation signal —<br><b>now watched on both networks.</b></div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">MEASURED WHILE BUILDING</div>
    <div class="bugcard" id="bugcard">
      <div class="t">Bluesky reposts were already arriving in the feed — <b>and silently discarded</b> by the own-handle filter</div>
    </div>
    <div class="bugfix" id="bugfix"><i>✓</i> Fixed — no extra request needed</div>
    <div class="cap">The data was already there.<br><b>It just needed to stop throwing it away.</b></div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">READ OFF THE ONCHAIN KEY REGISTRY</div>
    <div class="sigrow" data-i="0"><div class="st">Gave <b>Warpcast</b> permission to post as you</div></div>
    <div class="sigrow" data-i="1"><div class="st">Gave <b>Farcaster Bot</b> permission to post as you</div></div>
    <div class="signote">First sight shows the whole history — years back, never shown before</div>
    <div class="cap">A standing permission, reviewed for the first time —<br><b>revoke it on Farcaster's own settings.</b></div>
  </div>

  <div class="comp" id="comp5">
    <div class="shd mono">WHAT IT NEVER DOES</div>
    <div class="vrow" data-i="0"><s>✕</s> Never posts, likes, or follows for you</div>
    <div class="vrow" data-i="1"><s>✕</s> Never revokes a permission itself</div>
    <div class="vrow" data-i="2"><s>✕</s> Never a separate connect step</div>
    <div class="vgood" id="vgood"><i>✓</i> Watching the account is all it takes.</div>
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
    tag.style.background='rgba(133,93,205,.16)';
    tag.style.color='${FC}';
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
    stag('#comp0 .irow',p,0.16,0.28,20);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===1){
    const rp=clamp01((p-0.06)/0.3);
    const rb=document.querySelector('#comp1 .replywrap');
    rb.style.opacity=rp;rb.style.transform='scale('+(0.92+0.08*back(rp))+')';
    document.getElementById('replynote').style.opacity=clamp01((p-0.48)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===2){
    stag('#comp2 .amprow',p,0.2,0.3,20);
    document.getElementById('ampnote').style.opacity=clamp01((p-0.56)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.76)/0.2);
  } else if(i===3){
    const bp=clamp01((p-0.06)/0.28);
    const bc=document.getElementById('bugcard');
    bc.style.opacity=bp;bc.style.transform='scale('+(0.9+0.1*back(bp))+')';
    document.getElementById('bugfix').style.opacity=clamp01((p-0.5)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.74)/0.22);
  } else if(i===4){
    stag('#comp4 .sigrow',p,0.2,0.3,20);
    document.querySelector('#comp4 .signote').style.opacity=clamp01((p-0.54)/0.28);
    if(cap)cap.style.opacity=clamp01((p-0.76)/0.2);
  } else if(i===5){
    stag('#comp5 .vrow',p,0.15,0.3,20);
    const g=document.getElementById('vgood');const gp=clamp01((p-0.56)/0.28);
    g.style.opacity=gp;g.style.transform='translateY('+((1-back(gp))*16)+'px)';
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-social-inbound-editorial.html'),html);
console.log('wrote clip-social-inbound-editorial.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
