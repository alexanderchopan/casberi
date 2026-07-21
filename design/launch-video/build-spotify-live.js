// Spotify promo — live-animated. node render.js clip-spotify-live.html --size=1080x1920
// Grounded in Model/SpotifyBridge.swift + Screens/SpotifyScreen.swift (shipped d01bc81):
//   PKCE, verifier stays on device, challenge = SHA-256(verifier)
//   the ONLY scope requested is user-library-read
//   liked songs land as link things titled "\(name) — \(artists)"
//   disconnect copy: "Disconnected — your things stay."
const fs=require('fs'), path=require('path');
const ICON='/Users/alexanderchopan/Developer/casberi/Casberi/Casberi/Assets.xcassets/brand-spotify.imageset/icon.png';
const ico='data:image/png;base64,'+fs.readFileSync(ICON).toString('base64');
const GRN='#1DB954', PUR='#7C4DEC', AMB='#E0982A', BLU='#2E63FF';
const BEATS=[
  {kick:'CONNECT',  head:"Spotify's own\nsign-in.",     accent:GRN},
  {kick:'PKCE',     head:'No server holds\na secret.',  accent:GRN},
  {kick:'SCOPE',    head:'One scope.\nRead-only.',      accent:GRN},
  {kick:'LANDS',    head:'Liked songs,\nyour things.',  accent:GRN},
  {kick:'TOGETHER', head:'Alongside\neverything else.', accent:GRN},
];
const INTRO=0.45,BEAT=2.0,OUT_AT=INTRO+BEATS.length*BEAT,TOTAL=OUT_AT+1.9;
const DATA=BEATS.map((b,i)=>({kick:b.kick,head:b.head,accent:b.accent}));
// title format from SpotifyBridge.ingest — "\(name) — \(artists)"
const LIKED=[
  ['Nights — Frank Ocean','added 2h ago'],
  ['Weird Fishes / Arpeggi — Radiohead','added yesterday'],
  ['Redbone — Childish Gambino','added 3d ago'],
  ['Teardrop — Massive Attack','added 5d ago'],
];
// the one-feed close
const MIX=[
  ['Spotify',GRN,'Nights — Frank Ocean'],
  ['Farcaster',PUR,'vitalik.eth · One thing I find striking…'],
  ['Screenshot',AMB,'Chili oil noodles — recipe'],
  ['Calendar',BLU,'Dinner with Mark · Fri 7:00'],
];
const SCOPES=[
  [1,'user-library-read','your liked songs'],
  [0,'play or pause your music',''],
  [0,'change your playlists',''],
  [0,'post, follow, or modify anything',''],
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
.head{position:absolute;left:70px;top:284px;right:70px;font-size:114px;line-height:.94;font-weight:800;letter-spacing:-.045em;color:#14110d;white-space:pre-line;will-change:transform,opacity;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
.wipe{position:absolute;top:-12%;left:0;width:135%;height:124%;transform:skewX(-9deg) translateX(160%);will-change:transform;}
.comp{position:absolute;left:120px;top:820px;width:840px;height:820px;border-radius:34px;overflow:hidden;box-shadow:34px 40px 0 rgba(20,17,13,.13), inset 0 0 0 1px rgba(255,255,255,.05), 0 30px 70px rgba(20,17,13,.26);opacity:0;will-change:transform,opacity;transform-origin:center top;padding:52px;color:#fff;background:#0a0f0b;}
.shd{font-size:28px;letter-spacing:.14em;color:rgba(255,255,255,.5);margin-bottom:24px;}
/* connect */
.logo{width:140px;height:140px;border-radius:32px;display:block;will-change:transform;}
.ctitle{font-size:52px;font-weight:750;margin-top:44px;line-height:1.08;letter-spacing:-.02em;}
.cslot{position:relative;height:104px;margin-top:48px;}
.cslot>*{position:absolute;left:0;top:0;}
.cbtn{background:${GRN};color:#04140a;font-weight:800;font-size:34px;padding:26px 56px;border-radius:100px;will-change:transform,opacity;}
.cok{display:flex;align-items:center;gap:16px;font-size:31px;font-weight:700;color:${GRN};padding:26px 0;will-change:transform,opacity;opacity:0;}
.cok i{width:44px;height:44px;border-radius:50%;flex:none;background:${GRN};color:#04140a;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
.cnote{margin-top:44px;font-size:28px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.cnote b{color:#fff;}
/* pkce */
.pk{display:flex;align-items:center;gap:20px;margin-top:18px;}
.side{flex:1;min-width:0;}
.sl{font-size:22px;letter-spacing:.12em;color:rgba(255,255,255,.4);margin-bottom:18px;text-align:center;}
.tok{background:#050805;border-radius:22px;padding:38px 18px;text-align:center;box-shadow:inset 0 0 0 2px rgba(29,185,84,.4);will-change:opacity,transform;}
.tok b{display:block;font-size:36px;font-weight:750;color:${GRN};}
.tok em{display:block;font-style:normal;font-size:23px;color:rgba(255,255,255,.45);margin-top:10px;}
.tok.out{box-shadow:inset 0 0 0 2px rgba(255,255,255,.16);}
.tok.out b{color:#fff;}
.wire{width:150px;height:4px;background:rgba(255,255,255,.12);position:relative;flex:none;border-radius:4px;}
.pulse{position:absolute;top:-7px;width:18px;height:18px;border-radius:50%;background:${GRN};box-shadow:0 0 22px ${GRN};will-change:transform,opacity;}
.pin{display:inline-flex;align-items:center;gap:9px;margin-top:16px;font-size:22px;color:${GRN};font-weight:700;justify-content:center;width:100%;}
.pnote{margin-top:44px;font-size:28px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.pnote b{color:#fff;}
.rdr{margin-top:34px;background:#050805;border-radius:18px;padding:24px 26px;display:flex;align-items:center;gap:22px;box-shadow:inset 0 0 0 1px rgba(255,255,255,.08);will-change:opacity,transform;}
.rdr .rl{font-size:21px;letter-spacing:.12em;color:rgba(255,255,255,.35);flex:none;}
.rdr .rv{font-size:26px;color:${GRN};font-weight:600;}
/* scope */
.srow{display:flex;align-items:center;gap:22px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);font-size:31px;will-change:opacity,transform;}
.srow:first-of-type{border-top:none;}
.srow i{width:44px;height:44px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-style:normal;font-size:24px;font-weight:800;}
.srow.y i{background:${GRN};color:#04140a;} .srow.y{font-weight:700;}
.srow.n i{background:rgba(255,255,255,.07);color:rgba(255,255,255,.3);} .srow.n{color:rgba(255,255,255,.32);}
.srow em{font-style:normal;font-size:23px;color:rgba(255,255,255,.4);margin-left:auto;}
.snote{margin-top:30px;font-size:27px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.snote b{color:#fff;}
/* liked */
.lrow{display:flex;align-items:center;gap:24px;padding:26px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.lrow:first-of-type{border-top:none;}
.lart{width:66px;height:66px;border-radius:12px;flex:none;background:rgba(29,185,84,.14);display:flex;align-items:center;justify-content:center;}
.lart svg{width:32px;height:32px;fill:${GRN};}
.lt{font-size:33px;font-weight:600;line-height:1.2;} .lm{font-size:23px;color:rgba(255,255,255,.4);margin-top:6px;}
.lnote{margin-top:26px;font-size:26px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.lnote b{color:#fff;}
/* mix */
.mrow{display:flex;align-items:center;gap:22px;padding:30px 0;border-top:2px solid rgba(255,255,255,.07);will-change:opacity,transform;}
.mrow:first-of-type{border-top:none;}
.mdot{width:14px;height:14px;border-radius:50%;flex:none;}
.msrc{font-size:22px;letter-spacing:.1em;width:180px;flex:none;}
.mtx{font-size:31px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.mnote{margin-top:30px;font-size:26px;color:rgba(255,255,255,.5);line-height:1.45;will-change:opacity;}
.outro{position:absolute;inset:0;display:flex;flex-direction:column;align-items:flex-start;justify-content:center;padding:0 74px;opacity:0;will-change:opacity;}
.outro .b{font-size:200px;font-weight:800;letter-spacing:-.05em;color:#14110d;line-height:.9;}
.outro .u{font-size:34px;letter-spacing:.1em;color:#14110d;margin-top:40px;font-weight:600;} .outro .u b{color:${GRN};}
</style></head><body>
<div class="stage">
  <div class="grain"></div>
  <div class="mast mono"><span>CASBERI</span><span>SPOTIFY</span></div>
  <div class="rule" id="rule"></div>
  <div class="wm" id="wm">01</div>

  <div class="comp" id="comp0">
    <img class="logo" id="logo" src="${ico}">
    <div class="ctitle">Your liked songs,<br>in your own feed.</div>
    <div class="cslot">
      <div class="cbtn" id="cbtn">Connect Spotify</div>
      <div class="cok" id="cok"><i>✓</i> Connected — liked songs land in your feed.</div>
    </div>
    <div class="cnote" id="cnote">Sign-in happens on <b>Spotify's own page</b>. No password is ever typed into Casberi.</div>
  </div>

  <div class="comp" id="comp1">
    <div class="shd mono">PKCE</div>
    <div class="pk">
      <div class="side">
        <div class="sl mono">THIS IPHONE</div>
        <div class="tok" id="verif"><b>verifier</b><em>the secret</em></div>
        <div class="pin" id="pin">● stays here</div>
      </div>
      <div class="wire"><div class="pulse" id="pulse"></div></div>
      <div class="side">
        <div class="sl mono">SPOTIFY</div>
        <div class="tok out" id="chal"><b>challenge</b><em>SHA-256(verifier)</em></div>
      </div>
    </div>
    <div class="pnote" id="pnote">A hash goes out. The secret it came from <b>never leaves this phone</b> — which is why there's no server in the middle holding one.</div>
    <div class="rdr" id="rdr"><span class="rl mono">REDIRECT</span><span class="rv mono">casberi://spotify-auth</span></div>
  </div>

  <div class="comp" id="comp2">
    <div class="shd mono">WHAT CASBERI ASKED FOR</div>
    ${SCOPES.map((s,i)=>`<div class="srow ${s[0]?'y':'n'}" data-i="${i}"><i>${s[0]?'✓':'—'}</i><span class="${s[0]?'mono':''}">${s[1]}</span>${s[2]?`<em>${s[2]}</em>`:''}</div>`).join('')}
    <div class="snote" id="snote">One scope, and it only reads. The app <b>couldn't press play if it wanted to</b>.</div>
  </div>

  <div class="comp" id="comp3">
    <div class="shd mono">LIKED SONGS</div>
    ${LIKED.map((l,i)=>`<div class="lrow" data-i="${i}"><span class="lart"><svg viewBox="0 0 24 24"><path d="M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z"/></svg></span><div><div class="lt">${l[0]}</div><div class="lm mono">${l[1]}</div></div></div>`).join('')}
    <div class="lnote" id="lnote">They land in your feed to search and revisit. Disconnect whenever — <b>your things stay</b>.</div>
  </div>

  <div class="comp" id="comp4">
    <div class="shd mono">ONE FEED</div>
    ${MIX.map((m,i)=>`<div class="mrow" data-i="${i}"><span class="mdot" style="background:${m[1]}"></span><span class="msrc mono" style="color:${m[1]}">${m[0].toUpperCase()}</span><span class="mtx">${m[2]}</span></div>`).join('')}
    <div class="mnote" id="mnote">A song sits next to a cast, a screenshot, a dinner. That's the whole point.</div>
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
    const lp=clamp01(p/0.3);
    document.getElementById('logo').style.transform='scale('+(0.6+0.4*back(lp))+') rotate('+((1-easeOut(lp))*-10)+'deg)';
    const b=document.getElementById('cbtn');const bp=clamp01((p-0.4)/0.28);
    const swap=clamp01((p-0.72)/0.18);                       // Connect → Connected
    b.style.opacity=bp*(1-swap);b.style.transform='scale('+((0.9+0.1*back(bp))*(1-0.06*swap))+')';
    const ok=document.getElementById('cok');ok.style.opacity=swap;ok.style.transform='scale('+(0.92+0.08*back(swap))+')';
    document.getElementById('cnote').style.opacity=clamp01((p-0.58)/0.3);
  } else if(i===1){
    const v=document.getElementById('verif');const vp=clamp01(p/0.3);v.style.opacity=vp;v.style.transform='translateY('+((1-back(vp))*24)+'px)';
    const pu=document.getElementById('pulse');const pp=clamp01((p-0.3)/0.32);
    pu.style.opacity=(pp>0&&pp<1)?1:0;pu.style.transform='translateX('+(pp*132)+'px)';
    const c=document.getElementById('chal');const cp=clamp01((p-0.56)/0.26);c.style.opacity=cp;c.style.transform='translateY('+((1-back(cp))*24)+'px)';
    const pi=document.getElementById('pin');const pip=clamp01((p-0.44)/0.24);pi.style.opacity=pip;pi.style.transform='scale('+(0.8+0.2*back(pip))+')';
    document.getElementById('pnote').style.opacity=clamp01((p-0.68)/0.24);
    const rd=document.getElementById('rdr');const rdp=clamp01((p-0.82)/0.18);rd.style.opacity=rdp;rd.style.transform='translateY('+((1-easeOut(rdp))*16)+'px)';
  } else if(i===2){
    document.querySelectorAll('#comp2 .srow').forEach((r,k)=>{const rp=clamp01((p-k*0.12)/0.3);r.style.opacity=rp*(r.classList.contains('n')?0.999:1);r.style.transform='translateX('+((1-easeOut(rp))*-30)+'px)';});
    document.getElementById('snote').style.opacity=clamp01((p-0.62)/0.3);
  } else if(i===3){
    document.querySelectorAll('#comp3 .lrow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    document.getElementById('lnote').style.opacity=clamp01((p-0.66)/0.28);
  } else if(i===4){
    document.querySelectorAll('#comp4 .mrow').forEach((r,k)=>{const rp=clamp01((p-k*0.13)/0.34);r.style.opacity=rp;r.style.transform='translateX('+((1-easeOut(rp))*-32)+'px)';});
    document.getElementById('mnote').style.opacity=clamp01((p-0.68)/0.28);
  }
}
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-spotify-live.html'),html);
console.log('wrote clip-spotify-live.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
