// The three how-it-works device clips — one per section, one per platform.
// Every scene is a REAL visualization the app ships, drawn from the code:
//   phone (720x1558, 1242:2688) "Just connect": the catalog with the site's
//     own brand icons -> Farcaster/Bluesky feed with the real post shapes
//     (SocialBridge: handle · /channel, full text, image, like/recast row),
//     a wallet row, a Photos media grid, a Cloudflare deadline.
//   mac (1600x1000, 16:10) "Keep tabs": the visualization gallery —
//     balance + sparkline + composition strip (prd §240), the combined
//     treemap + concentration line (§155), the FLOW BAND with scaled
//     ribbons, the CONNECTED ADDRESSES spine with equal-weight ribbons
//     (§295: "every ribbon draws the same weight"), Cloudflare deadlines
//     with the Sorted closer, the posting heatmap + screenshot topic map
//     (§230) + a media grid.
//   pad (768x1024, ~3:4) "One agent": the Today brief (§166) painting on
//     the left — whisper, money hero with delta pill, movers, up next —
//     while an ask lands on the right with source-attributed rows.
//   node build-device-clips.js && render each (sizes above)
const fs = require('fs'), path = require('path');
const ICONS = JSON.parse(fs.readFileSync(path.join(__dirname, 'brand-icons.json'), 'utf8'));

const INK = '#0b0910', GREEN = '#3fb950', RED = '#ff453a', BLUE = '#2E63FF', VIOLET = '#855dcd', SKY = '#0085ff', CF = '#F6821F';

const BASE = (w, h, body, script, extra) => `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:${w}px;height:${h}px;overflow:hidden;background:${INK};
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:#fff;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
${extra||''}
</style></head><body>
${body}
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.6;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
function pop(el,p,from,dur,dy){const rp=clamp01((p-from)/dur);el.style.opacity=rp;el.style.transform='translateY('+((1-back(rp))*(dy==null?18:dy))+'px)';return rp;}
${script}
window.seek(0);
</script></body></html>`;

// A deterministic identicon-ish avatar: two-stop gradient keyed by index.
const FACE = (i, sz) => {
  const hues = [[264, 210], [16, 42], [152, 190], [330, 288], [200, 240], [48, 20]];
  const [a, b] = hues[i % hues.length];
  return `<span style="width:${sz}px;height:${sz}px;border-radius:50%;flex:none;display:inline-block;background:linear-gradient(135deg,hsl(${a},62%,58%),hsl(${b},68%,40%))"></span>`;
};

// The "Daily doodle" art block — an abstract b/w mark, not anyone's real art.
const DOODLE = `<svg viewBox="0 0 200 110" width="100%" height="100%" preserveAspectRatio="xMidYMid slice" style="background:#fff;display:block">
<g fill="none" stroke="#111" stroke-width="5"><circle cx="100" cy="55" r="34"/><circle cx="100" cy="55" r="20"/></g>
<g fill="#111"><ellipse cx="58" cy="55" rx="26" ry="13" transform="rotate(-24 58 55)"/><ellipse cx="142" cy="55" rx="26" ry="13" transform="rotate(-24 142 55)"/><circle cx="100" cy="55" r="7"/></g></svg>`;

/* ================================ PHONE ================================= */
const CATALOG = ['Farcaster', 'Bluesky', 'Gmail', 'Spotify', 'YouTube', 'GitHub', 'Instagram', 'Snapchat', 'Cloudflare', 'X', 'TikTok', 'Stripe', 'Hugging Face', 'Reddit', 'Twitch', 'Notion'];
const phone = () => BASE(720, 1558, `
<div class="pour"></div>
<div id="cat">
  <div class="chd">The catalog <em>60+ apps</em></div>
  <div class="agrid">${CATALOG.map((n, i) => `<span class="cell" data-i="${i}"><img src="${ICONS[n]}" alt=""><b>${n === 'Hugging Face' ? 'HF' : n}</b></span>`).join('')}</div>
  <div class="hint" id="hint">No account. No sign-up. Tap to connect.</div>
</div>
<div id="feed" style="opacity:0">
  <div class="chips">
    <span class="cc av"></span><span class="cc"><b>All</b></span>
    <span class="cc on" style="background:${VIOLET}"><img src="${ICONS['Farcaster']}"></span>
    <span class="cc"><img src="${ICONS['Bluesky']}"></span>
    <span class="cc"><i style="background:#2962ef"></i></span>
    <span class="cc"><img src="${ICONS['Cloudflare']}"></span>
  </div>
  <div class="sect">Today <em id="cnt">0</em></div>
  <div class="post" data-r="0">
    <div class="ph">${FACE(0, 46)}<div class="pwho"><b>tomato.eth</b><i>/art · 1d</i></div><img class="psrc" src="${ICONS['Farcaster']}"></div>
    <div class="ptxt">Daily doodle 2018.</div>
    <div class="part">${DOODLE}</div>
    <div class="pmeta">♡ 3&nbsp;&nbsp;&nbsp;↻ 0</div>
  </div>
  <div class="post" data-r="1">
    <div class="ph">${FACE(4, 46)}<div class="pwho"><b>bsky.app</b><i>23d</i></div><img class="psrc" src="${ICONS['Bluesky']}"></div>
    <div class="ptxt">v1.127 is live! We're rolling out improvements to search over the coming weeks…</div>
    <div class="pmeta">♡ 3,470&nbsp;&nbsp;&nbsp;↻ 580</div>
  </div>
  <div class="row" data-r="2"><span class="dot" style="background:#2962ef"></span><div class="col"><div class="amt" style="color:${GREEN}">+0.42 ETH</div><div class="sub2">$1,284.00 · Base</div></div><span class="src">Wallet</span></div>
  <div class="mrow" data-r="3">
    <div class="mhd">Photos · 3 screenshots</div>
    <div class="mgrid"><i style="background:linear-gradient(140deg,#3b4d70,#1e2a42)"></i><i style="background:linear-gradient(140deg,#704a3b,#42281e)"></i><i style="background:linear-gradient(140deg,#3b7053,#1e422c)"></i></div>
  </div>
  <div class="row" data-r="4"><img class="rico" src="${ICONS['Cloudflare']}"><div class="col"><div class="ttl">TLS cert expires in 12 days</div><div class="sub2">yoursite.com — before the browser warning</div></div><span class="src">Cloudflare</span></div>
</div>`,
`window.TOTAL=13;
window.seek=function(t){
  const cat=document.getElementById('cat'),feed=document.getElementById('feed');
  const catOut=1-clamp01((t-3.1)/0.4);
  cat.style.opacity=Math.min(clamp01(t/0.4),catOut);
  document.querySelectorAll('#cat .cell').forEach((a,i)=>{
    const rp=clamp01((t-0.12-(i%4)*0.06-Math.floor(i/4)*0.1)/0.4);
    a.style.opacity=rp;a.style.transform='translateY('+((1-back(rp))*18)+'px)';
    if(i===0){const pu=clamp01((t-2.2)/0.55);
      a.style.boxShadow=pu>0?('0 0 0 '+(pu*12)+'px rgba(133,93,205,'+(0.55*(1-pu))+')'):'none';}
  });
  document.getElementById('hint').style.opacity=clamp01((t-1.3)/0.4)*catOut;
  const fOut=1-clamp01((t-12.55)/0.45);
  feed.style.opacity=Math.min(clamp01((t-3.4)/0.35),fOut);
  let landed=0;
  document.querySelectorAll('#feed [data-r]').forEach((r,i)=>{
    const rp=pop(r,t,3.8+i*1.05,0.55,30);if(rp>0.5)landed++;
  });
  document.getElementById('cnt').textContent=landed;
};`,
`
.pour{position:absolute;left:0;right:0;top:0;height:380px;background:linear-gradient(to bottom, rgba(133,93,205,.22), rgba(0,0,0,0));}
#cat,#feed{position:absolute;inset:0;will-change:opacity;}
.chd{font-size:30px;font-weight:800;margin:110px 40px 8px;} .chd em{font-style:normal;font-size:21px;color:rgba(255,255,255,.4);font-weight:650;margin-left:10px;}
.agrid{display:grid;grid-template-columns:repeat(4,1fr);gap:24px 16px;padding:26px 36px;}
.cell{display:flex;flex-direction:column;align-items:center;gap:10px;will-change:transform,opacity;}
.cell img{width:104px;height:104px;border-radius:26px;box-shadow:0 8px 18px rgba(0,0,0,.4);}
.cell b{font-size:17px;font-weight:650;color:rgba(255,255,255,.75);white-space:nowrap;overflow:hidden;max-width:120px;text-overflow:ellipsis;}
.hint{margin:26px 40px 0;text-align:center;font-size:21px;font-weight:650;color:rgba(255,255,255,.45);}
.chips{display:flex;align-items:center;gap:13px;padding:88px 30px 16px;}
.cc{width:62px;height:62px;border-radius:50%;background:rgba(255,255,255,.09);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden;}
.cc.av{background:linear-gradient(135deg,hsl(28,70%,62%),hsl(340,60%,45%));}
.cc b{font-size:21px;color:rgba(255,255,255,.8);} .cc i{width:22px;height:22px;border-radius:50%;display:block;}
.cc img{width:38px;height:38px;border-radius:10px;}
.cc.on{box-shadow:0 0 0 3px rgba(255,255,255,.22);}
.cc.on img{width:62px;height:62px;border-radius:0;}
.sect{font-size:22px;font-weight:700;color:rgba(255,255,255,.42);margin:12px 34px 10px;}
.sect em{font-style:normal;color:rgba(255,255,255,.26);margin-left:8px;}
.post{background:rgba(255,255,255,.05);border-radius:22px;padding:22px;margin:0 26px 18px;will-change:opacity,transform;}
.ph{display:flex;align-items:center;gap:13px;}
.pwho{flex:1;} .pwho b{display:block;font-size:21px;font-weight:750;} .pwho i{font-style:normal;font-size:17px;color:${VIOLET};font-weight:650;}
.psrc{width:30px;height:30px;border-radius:8px;}
.ptxt{font-size:23px;font-weight:600;line-height:1.35;margin:14px 0 0;}
.part{height:180px;border-radius:14px;overflow:hidden;margin-top:14px;}
.pmeta{margin-top:14px;font-size:18px;color:rgba(255,255,255,.42);font-weight:650;}
.row{display:flex;align-items:center;gap:16px;padding:16px 34px;will-change:opacity,transform;}
.row .col{flex:1;min-width:0;}
.rico{width:46px;height:46px;border-radius:12px;flex:none;}
.dot{width:13px;height:13px;border-radius:50%;flex:none;margin:0 17px;}
.ttl{font-size:22px;font-weight:650;} .sub2{font-size:18px;color:rgba(255,255,255,.44);margin-top:3px;}
.amt{font-size:25px;font-weight:750;} .src{margin-left:auto;font-size:17px;color:rgba(255,255,255,.32);font-weight:600;flex:none;}
.mrow{margin:4px 26px 18px;background:rgba(255,255,255,.05);border-radius:22px;padding:20px;will-change:opacity,transform;}
.mhd{font-size:18px;font-weight:700;color:rgba(255,255,255,.45);margin-bottom:12px;}
.mgrid{display:flex;gap:10px;} .mgrid i{flex:1;aspect-ratio:1;border-radius:13px;display:block;}
`);

/* ================================= MAC ================================== */
// Six scenes, each a shipped visualization. Fixed window chrome: title says
// where you are (the Mac's real title-bar behaviour).
const macScene = (id, title, inner) => `<div class="scene" id="${id}"><div class="stitle">${title}</div>${inner}</div>`;
const mac = () => BASE(1600, 1000, `
<div class="topbar"><span class="tl"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></span><span class="twhere" id="twhere">Wallet</span></div>
${macScene('sA', 'Across your wallets', `
  <div class="wrow"><span class="wn" id="wn">$0</span><span class="wpill">▲ 2.1% today</span></div>
  <svg class="spark" width="760" height="120" viewBox="0 0 760 120" preserveAspectRatio="none"><defs><clipPath id="cpA"><rect id="cpArect" x="0" y="0" width="0" height="120"/></clipPath></defs><path clip-path="url(#cpA)" d="M0 94 L95 82 L190 88 L285 60 L380 68 L475 40 L570 48 L665 22 L760 14" fill="none" stroke="${GREEN}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/></svg>
  <div class="comp">
    <div class="crow" data-c="0"><span>Deposited</span><div class="cbar"><i style="width:72%;background:#9391f7"></i></div><b>$41.6K</b></div>
    <div class="crow" data-c="1"><span>Locked</span><div class="cbar"><i style="width:41%;background:#0434ff"></i></div><b>12,977 AERO</b></div>
    <div class="crow" data-c="2"><span>Owed</span><div class="cbar"><i style="width:18%;background:${RED}"></i></div><b>$6,100</b></div>
  </div>
  <div class="cap" id="capA">The lock melts on its own clock — 41% of its voting power left.</div>`)}
${macScene('sB', 'What you hold', `
  <div class="tree">
    <span class="tc" style="left:0;top:0;width:46%;height:100%;background:#4a63d8"><b>ETH</b><i>$48.2K</i></span>
    <span class="tc" style="left:47%;top:0;width:29%;height:54%;background:#2775ca"><b>USDC</b><i>$19.4K</i></span>
    <span class="tc" style="left:77%;top:0;width:23%;height:54%;background:#f7931a"><b>WBTC</b><i>$7.8K</i></span>
    <span class="tc" style="left:47%;top:57%;width:20%;height:43%;background:#14f195"><b>SOL</b><i>$11.1K</i></span>
    <span class="tc" style="left:68%;top:57%;width:14%;height:43%;background:#0434ff"><b>AERO</b><i>$4.1K</i></span>
    <span class="tc" style="left:83%;top:57%;width:17%;height:43%;background:rgba(255,255,255,.14)"><b>+13</b></span>
  </div>
  <div class="cap" id="capB">ETH is 50% of everything · <u>Where it's held →</u></div>`)}
${macScene('sC', 'Where it moved', `
  <svg class="sankey" viewBox="0 0 1600 520" width="1600" height="520" style="margin-left:-120px">
    <!-- inflows: green slabs, edge to edge (the app's one green moment) -->
    <rect data-s="0" x="0" y="60"  width="430" height="120" fill="rgba(63,185,80,.85)"/>
    <rect data-s="1" x="0" y="210" width="430" height="64"  fill="rgba(63,185,80,.55)"/>
    <!-- straight tapers, square shoulders — no bezier softness -->
    <polygon data-s="0" points="430,60 730,120 730,208 430,180" fill="rgba(63,185,80,.32)"/>
    <polygon data-s="1" points="430,210 730,214 730,252 430,274" fill="rgba(63,185,80,.2)"/>
    <!-- the spine is you -->
    <rect x="730" y="80" width="120" height="360" rx="0" fill="rgba(255,255,255,.1)"/>
    <!-- outflows: neutral slabs, never red -->
    <polygon data-s="2" points="850,120 1120,80 1120,190 850,214" fill="rgba(255,255,255,.16)"/>
    <rect data-s="2" x="1120" y="80" width="480" height="110" fill="rgba(255,255,255,.24)"/>
    <polygon data-s="3" points="850,240 1120,250 1120,330 850,320" fill="rgba(255,255,255,.12)"/>
    <rect data-s="3" x="1120" y="250" width="480" height="80" fill="rgba(255,255,255,.2)"/>
    <g font-family="-apple-system" font-weight="800">
      <text x="24" y="130" fill="#08210e" font-size="30">Peer fill · $10,030</text>
      <text x="24" y="248" fill="#0b2a12" font-size="24">Unshield · $2,400</text>
      <text x="790" y="270" fill="#fff" font-size="24" text-anchor="middle" transform="rotate(-90 790 270)">vitalik.eth</text>
      <text x="1144" y="142" fill="rgba(255,255,255,.9)" font-size="28">Aave deposit · $8,200</text>
      <text x="1144" y="298" fill="rgba(255,255,255,.85)" font-size="24">Uniswap · $3,100</text>
    </g>
  </svg>
  <div class="cap" id="capC">Inflows left, outflows right — every lane sized by what it was worth when it moved.</div>`)}
${macScene('sD', '2 of your addresses are connected', `
  <svg class="sankey" viewBox="0 0 1200 500" width="100%" height="500">
    <g id="spine">
      <path data-s="0" fill="none" stroke="rgba(255,255,255,.34)" stroke-width="3" d="M240 120 C 520 120, 680 200, 960 200"/>
      <path data-s="1" fill="none" stroke="rgba(255,255,255,.34)" stroke-width="3" d="M240 380 C 520 380, 680 220, 960 210"/>
    </g>
    <g font-family="-apple-system" font-weight="700" font-size="24">
      <circle cx="200" cy="120" r="42" fill="hsl(264,62%,58%)"/><text x="270" y="112" fill="#fff">vitalik.eth</text><text x="270" y="140" fill="rgba(255,255,255,.45)" font-size="19">watched</text>
      <circle cx="200" cy="380" r="42" fill="hsl(152,62%,48%)"/><text x="270" y="372" fill="#fff">lido.eth</text><text x="270" y="400" fill="rgba(255,255,255,.45)" font-size="19">watched</text>
      <circle cx="1000" cy="205" r="36" fill="rgba(255,255,255,.16)"/><text x="1000" y="286" fill="#fff" text-anchor="middle">0xa5d1…956f</text><text x="1000" y="314" fill="rgba(255,255,255,.45)" font-size="19" text-anchor="middle">reaches both</text>
    </g>
  </svg>
  <div class="cap" id="capD">It has transacted with more than one of your wallets — drawn, never inferred.</div>`)}
${macScene('sE', 'The dates behind your sites', `
  <div class="cfwrap">
    <div class="cf" data-c="0"><span class="dpill">12d</span><div><div class="cft">yoursite.com — TLS certificate expires in 12 days</div><div class="cfs">Renewal hasn't happened yet</div></div></div>
    <div class="cf" data-c="1"><span class="dpill">44d</span><div><div class="cft">yoursite.com renews in 44 days</div><div class="cfs">Auto-renew still fails on a dead card</div></div></div>
    <div class="cf" data-c="2"><span class="dpill red">now</span><div><div class="cft">staging.yoursite.com isn't active — pending</div><div class="cfs">Not being served in this state</div></div></div>
    <div class="cf sorted" data-c="3"><span class="scheck">✓</span><div><div class="cft" style="color:${GREEN}">Sorted: yoursite.com — TLS certificate</div><div class="cfs">The renewal went through — the row closes itself</div></div></div>
  </div>
  <div class="cap" id="capE">A quiet feed means everything is current.</div>`)}
${macScene('sF', 'What your screenshots say', `
  <div class="duo">
    <div class="dmap">
      <span style="flex:3.4;background:rgba(74,99,216,.85)">figma.com</span>
      <span style="flex:2.2;background:rgba(133,93,205,.8)">recipes</span>
      <div class="dmaprow"><span style="flex:1.6;background:rgba(63,185,80,.7)">receipts</span><span style="flex:1.2;background:rgba(255,159,10,.65)">flights</span><span style="flex:1;background:rgba(255,255,255,.14)">+9</span></div>
    </div>
    <div class="dside">
      <div class="dlbl mono">POSTING ACTIVITY</div>
      <div class="dheat">${Array.from({length: 60}).map((_, k) => `<i data-h="${k}"></i>`).join('')}</div>
      <div class="dlbl mono" style="margin-top:26px">MEMORIES</div>
      <div class="dmedia">${[0,1,2,3,4,5].map(k => `<i style="background:linear-gradient(${120+k*40}deg,hsl(${k*55+10},45%,38%),hsl(${k*55+40},40%,20%))"></i>`).join('')}</div>
    </div>
  </div>
  <div class="cap" id="capF">Every word came off a screenshot, read on-device.</div>`)}`,
`window.TOTAL=21;
const SC=[['sA','Wallet',0,3.5],['sB','Wallet',3.5,7],['sC','Wallet',7,10.5],['sD','Wallet',10.5,14],['sE','Cloudflare',14,17.5],['sF','Photos',17.5,21]];
window.seek=function(t){
  let where='Wallet';
  SC.forEach(([id,ttl,a,b])=>{
    const el=document.getElementById(id);
    const inn=clamp01((t-a)/0.4), out=1-clamp01((t-(b-0.4))/0.4);
    el.style.opacity=Math.min(inn,out);
    if(t>=a&&t<b)where=ttl;
    const p=clamp01((t-a-0.15)/(b-a-0.6));
    if(id==='sA'){
      const n=Math.round(96812*easeOut(clamp01(p/0.5)));
      document.getElementById('wn').textContent='$'+n.toLocaleString('en-US');
      document.getElementById('cpArect').setAttribute('width',String(760*easeOut(clamp01(p/0.7))));
      document.querySelectorAll('#sA .crow').forEach((r,k)=>{
        const rp=clamp01((p-0.35-k*0.14)/0.25);r.style.opacity=rp;
        r.querySelector('.cbar i').style.transform='scaleX('+easeOut(rp)+')';
      });
    }
    if(id==='sB'){document.querySelectorAll('#sB .tc').forEach((c,k)=>{const rp=clamp01((p-k*0.09)/0.3);c.style.opacity=rp;c.style.transform='scale('+(0.75+0.25*back(rp))+')';});}
    if(id==='sC'){document.querySelectorAll('#sC [data-s]').forEach((r,k)=>{r.style.opacity=clamp01((p-0.03-k*0.09)/0.22);});}
    if(id==='sD'){document.querySelectorAll('#sD [data-s]').forEach((r,k)=>{
      const rp=clamp01((p-0.15-k*0.2)/0.35);
      const len=1300;r.style.strokeDasharray=len;r.style.strokeDashoffset=String(len*(1-easeOut(rp)));});}
    if(id==='sE'){document.querySelectorAll('#sE .cf').forEach((r,k)=>{pop(r,p,0.05+k*0.16,0.26,20);});}
    if(id==='sF'){document.querySelectorAll('#sF .dheat i').forEach((c,k)=>{
      const on=((k*2654435761)>>>0)%97<40;const rp=clamp01((p-(((k*40503)>>>0)%100)/100*0.5)/0.2);
      c.style.background=on?'rgba(63,185,80,'+(0.16+0.7*rp)+')':'rgba(255,255,255,.06)';});
      document.querySelectorAll('#sF .dmap span, #sF .dmaprow span').forEach((c,k)=>{const rp=clamp01((p-k*0.08)/0.3);c.style.opacity=rp;});
      document.querySelectorAll('#sF .dmedia i').forEach((c,k)=>{const rp=clamp01((p-0.2-k*0.07)/0.25);c.style.opacity=rp;});
    }
    const cap=el.querySelector('.cap');if(cap)cap.style.opacity=clamp01((p-0.6)/0.25);
  });
  document.getElementById('twhere').textContent=where;
};`,
`
.topbar{position:absolute;top:0;left:0;right:0;height:52px;background:#15121b;display:flex;align-items:center;padding:0 20px;z-index:5;}
.tl{display:flex;gap:8px;} .tl i{width:13px;height:13px;border-radius:50%;display:block;}
.twhere{position:absolute;left:0;right:0;text-align:center;font-size:19px;font-weight:600;color:rgba(255,255,255,.55);}
.scene{position:absolute;inset:52px 0 0;padding:56px 120px 0;will-change:opacity;opacity:0;}
.stitle{font-size:26px;font-weight:700;color:rgba(255,255,255,.45);margin-bottom:22px;}
.wrow{display:flex;align-items:baseline;gap:24px;}
.wn{font-size:110px;font-weight:800;letter-spacing:-.03em;}
.wpill{font-size:26px;font-weight:750;padding:10px 24px;border-radius:100px;background:rgba(63,185,80,.16);color:${GREEN};}
.spark{margin:26px 0 34px;display:block;}
.comp{max-width:900px;}
.crow{display:flex;align-items:center;gap:24px;margin-top:20px;will-change:opacity;}
.crow span{width:130px;font-size:24px;font-weight:650;color:rgba(255,255,255,.6);}
.crow b{width:170px;font-size:24px;font-weight:750;text-align:right;}
.cbar{flex:1;height:18px;border-radius:10px;background:rgba(255,255,255,.08);overflow:hidden;}
.cbar i{display:block;height:100%;border-radius:10px;transform-origin:left;}
.cap{margin-top:36px;font-size:24px;font-weight:650;color:rgba(255,255,255,.5);will-change:opacity;}
.cap u{text-decoration-color:rgba(255,255,255,.3);}
.tree{position:relative;height:560px;border-radius:26px;overflow:hidden;}
.tc{position:absolute;border-radius:18px;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:inset 0 0 0 2px rgba(0,0,0,.22);will-change:transform,opacity;}
.tc b{font-size:38px;font-weight:800;} .tc i{font-style:normal;font-size:24px;color:rgba(255,255,255,.82);margin-top:6px;font-weight:600;}
.sankey{display:block;}
.sankey text{font-family:-apple-system,'Helvetica Neue',system-ui,sans-serif;}
.sankey [data-s]{will-change:opacity;}
.cfwrap{max-width:1000px;}
.cf{display:flex;align-items:center;gap:24px;padding:22px 0;will-change:opacity,transform;}
.dpill{flex:none;min-width:110px;text-align:center;font-size:24px;font-weight:800;padding:12px 14px;border-radius:14px;background:rgba(246,130,31,.16);color:${CF};font-family:ui-monospace,monospace;}
.dpill.red{background:rgba(255,69,58,.14);color:${RED};}
.scheck{flex:none;width:58px;height:58px;border-radius:50%;background:rgba(63,185,80,.18);color:${GREEN};display:flex;align-items:center;justify-content:center;font-size:30px;font-weight:800;margin:0 26px;}
.cft{font-size:27px;font-weight:700;} .cfs{font-size:21px;color:rgba(255,255,255,.44);margin-top:4px;}
.duo{display:flex;gap:44px;height:560px;}
.dmap{flex:1.3;display:flex;flex-direction:column;gap:12px;}
.dmap>span,.dmaprow span{border-radius:18px;display:flex;align-items:flex-end;padding:20px;font-size:27px;font-weight:800;will-change:opacity;}
.dmaprow{display:flex;gap:12px;flex:1.4;}
.dside{flex:1;}
.dlbl{font-size:18px;letter-spacing:.13em;color:rgba(255,255,255,.4);font-weight:650;margin-bottom:14px;}
.dheat{display:grid;grid-template-columns:repeat(12,1fr);gap:8px;}
.dheat i{aspect-ratio:1;border-radius:5px;background:rgba(255,255,255,.06);display:block;}
.dmedia{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;}
.dmedia i{aspect-ratio:1;border-radius:14px;display:block;will-change:opacity;}
`);

/* ================================= PAD ================================== */
const pad = () => BASE(768, 1024, `
<div class="left">
  <div class="eyeb" id="eyeb">today so far</div>
  <div class="bh" id="bh">What's going on</div>
  <div class="lede" id="lede">Book dentist is overdue.</div>
  <div class="card" id="money">
    <div class="mn" id="mn">$0</div>
    <div class="mtree">
      <span style="flex:3;background:linear-gradient(120deg,#3b4dd8,#26327e)"><b>ETH</b><i>$19K</i></span>
      <span class="mside"><em><b>AWETH</b><i>$96</i></em><em><b>MATIC</b><i>$85</i></em></span>
    </div>
    <div class="msub" id="msub">20 transactions settled</div>
  </div>
  <div class="card" id="next">
    <div class="nlbl">Up next</div>
    <div class="nttl">Send Lisbon dates to Sam</div>
    <div class="nsub">Mon 11:00 AM</div>
    <div class="nred">3 more overdue</div>
  </div>
  <div class="themes" id="themes"><span>Work</span><span>Casberi</span></div>
</div>
<div class="right">
  <div class="qb" id="qb">What's going on?</div>
  <div class="acard" id="acard">
    <div class="ah">Quiet morning — <b>16 new things</b> landed, and your wallets are up 2.1%.</div>
    <div class="arow" data-a="0"><span class="adot" style="background:#2962ef"></span><span>ETH did the lifting · +$1,412</span></div>
    <div class="arow" data-a="1"><img src="${ICONS['Farcaster']}"><span>7 casts from people you follow</span></div>
    <div class="arow" data-a="2"><span class="adot" style="background:${RED}"></span><span>Design review at 4:30</span></div>
    <div class="arow" data-a="3"><img src="${ICONS['Cloudflare']}"><span>A certificate needs a look — 12 days</span></div>
    <div class="abadge" id="abadge">Written on this iPad, from your own things</div>
  </div>
  <div class="composer" id="composer"><span>Ask about this…</span></div>
</div>`,
`window.TOTAL=13;
window.seek=function(t){
  pop(document.getElementById('eyeb'),t,0.15,0.35,10);
  pop(document.getElementById('bh'),t,0.3,0.45,16);
  pop(document.getElementById('lede'),t,0.65,0.45,14);
  pop(document.getElementById('money'),t,1.2,0.55,26);
  const n=Math.round(95000*easeOut(clamp01((t-1.5)/1.0)));
  document.getElementById('mn').textContent='$'+(n>=1000?Math.round(n/1000)+'K':n);
  document.getElementById('msub').style.opacity=clamp01((t-2.4)/0.4);
  pop(document.getElementById('next'),t,2.9,0.55,26);
  pop(document.getElementById('themes'),t,3.7,0.45,16);
  pop(document.getElementById('qb'),t,4.6,0.4,14);
  pop(document.getElementById('acard'),t,5.3,0.5,24);
  document.querySelectorAll('.arow').forEach((r,k)=>{pop(r,t,6.0+k*0.55,0.4,14);});
  document.getElementById('abadge').style.opacity=clamp01((t-8.6)/0.4);
  pop(document.getElementById('composer'),t,9.2,0.4,14);
  const out=1-clamp01((t-12.55)/0.45);
  document.querySelector('.left').style.opacity=Math.min(1,out);
  document.querySelector('.right').style.opacity=Math.min(1,out);
};`,
`
.left{position:absolute;left:0;top:0;bottom:0;width:55%;padding:64px 34px 0;border-right:1px solid rgba(255,255,255,.06);will-change:opacity;}
.right{position:absolute;right:0;top:0;bottom:0;width:45%;padding:64px 28px 0;background:rgba(255,255,255,.02);will-change:opacity;}
.eyeb{font-size:17px;color:rgba(255,255,255,.42);font-weight:650;}
.bh{font-size:38px;font-weight:800;letter-spacing:-.02em;margin-top:5px;}
.lede{font-size:25px;font-weight:800;margin-top:12px;}
.card{background:rgba(255,255,255,.055);border-radius:20px;padding:22px;margin-top:20px;will-change:opacity,transform;}
.mn{font-size:48px;font-weight:800;letter-spacing:-.03em;}
.mtree{display:flex;gap:9px;margin-top:14px;height:120px;}
.mtree>span{border-radius:12px;display:flex;flex-direction:column;align-items:flex-start;justify-content:flex-end;padding:12px;}
.mtree b{font-size:18px;font-weight:800;} .mtree i{font-style:normal;font-size:14px;color:rgba(255,255,255,.75);}
.mside{flex:1;display:flex;flex-direction:column;gap:8px;background:none!important;padding:0!important;}
.mside em{flex:1;font-style:normal;border-radius:10px;background:rgba(255,255,255,.07);display:flex;flex-direction:column;justify-content:center;padding:0 12px;}
.mside b{font-size:13px;} .mside i{font-size:12px;}
.msub{margin-top:12px;font-size:16px;color:rgba(255,255,255,.5);font-weight:600;will-change:opacity;}
.nlbl{font-size:15px;color:rgba(255,255,255,.42);font-weight:650;}
.nttl{font-size:21px;font-weight:750;margin-top:6px;}
.nsub{font-size:16px;color:rgba(255,255,255,.5);margin-top:4px;}
.nred{font-size:16px;color:${RED};font-weight:700;margin-top:9px;}
.themes{display:flex;gap:10px;margin-top:20px;will-change:opacity,transform;}
.themes span{flex:1;font-size:18px;font-weight:700;padding:16px;border-radius:14px;background:rgba(46,99,255,.13);}
.qb{background:${BLUE};color:#fff;border-radius:18px 18px 5px 18px;padding:14px 18px;font-size:18px;font-weight:650;margin-left:auto;max-width:80%;width:fit-content;will-change:opacity,transform;}
.acard{margin-top:16px;background:rgba(255,255,255,.05);border-radius:18px;padding:20px;will-change:opacity,transform;}
.ah{font-size:19px;font-weight:700;line-height:1.35;}
.arow{display:flex;align-items:center;gap:11px;margin-top:14px;font-size:16px;color:rgba(255,255,255,.74);font-weight:600;will-change:opacity,transform;}
.arow img{width:28px;height:28px;border-radius:8px;flex:none;}
.adot{width:12px;height:12px;border-radius:50%;flex:none;margin:0 8px;}
.abadge{margin-top:16px;font-size:14px;color:rgba(255,255,255,.4);font-weight:600;will-change:opacity;}
.composer{margin-top:18px;background:rgba(255,255,255,.1);border-radius:100px;padding:14px 20px;font-size:16px;font-weight:600;color:rgba(255,255,255,.55);box-shadow:inset 0 0 0 2px rgba(255,255,255,.1);will-change:opacity,transform;}
`);

fs.writeFileSync(path.join(__dirname, 'web-sec-phone.html'), phone());
fs.writeFileSync(path.join(__dirname, 'web-sec-mac.html'), mac());
fs.writeFileSync(path.join(__dirname, 'web-sec-pad.html'), pad());
console.log('wrote web-sec-phone.html, web-sec-mac.html, web-sec-pad.html');
