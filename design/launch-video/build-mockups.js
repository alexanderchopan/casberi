// Three design-language mockups of casberi.app's below-the-fold sections:
// Cash App / Apple / Uber. Same REAL content in all three (the sections from
// the approved outline: It lands / You see it / It briefs you / It's yours /
// catalog + CTA) so the comparison is purely about design language.
// No fake photography anywhere — text, numbers, charts only.
//   node build-mockups.js   -> website/mock-below-{cashapp,apple,uber}.html
const fs = require('fs'), path = require('path');
const ICONS = JSON.parse(fs.readFileSync(path.join(__dirname, 'brand-icons.json'), 'utf8'));
const SITE = path.join(__dirname, '..', '..', 'website');

const ICON_ROW = ['Farcaster', 'Bluesky', 'Gmail', 'Spotify', 'YouTube', 'GitHub', 'Instagram', 'Snapchat', 'Cloudflare', 'X', 'TikTok', 'Stripe'];
const icons = (sz, r) => ICON_ROW.map(n => `<img src="${ICONS[n]}" style="width:${sz}px;height:${sz}px;border-radius:${r}px" alt="${n}">`).join('');

// ---- shared content fragments (drawn per-language below) ----
const GREEN = '#00D632', INK = '#111', CFO = '#F6821F';

/* =============================== CASH APP ===============================
   Full-bleed color slabs, huge ultra-bold type, chunky rounded cards
   floating at slight angles, one loud accent per slab. */
const cashapp = () => `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Casberi — Cash App direction</title><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,"Helvetica Neue",system-ui,sans-serif;-webkit-font-smoothing:antialiased;color:${INK};background:#fff;}
.slab{padding:110px 8vw;overflow:hidden;position:relative;}
h2{font-size:clamp(48px,7vw,96px);font-weight:800;letter-spacing:-.045em;line-height:.95;}
.sub{font-size:22px;font-weight:600;margin-top:22px;max-width:560px;line-height:1.4;}
.card{background:#fff;border-radius:36px;box-shadow:0 30px 80px rgba(0,0,0,.18);padding:34px;}
.tilt1{transform:rotate(-3deg);} .tilt2{transform:rotate(2.2deg);}
.row{display:flex;align-items:center;gap:16px;padding:14px 0;border-bottom:1px solid #eee;}
.row:last-child{border-bottom:none}
.rt{font-size:19px;font-weight:750;} .rs{font-size:15px;color:#8a8a8a;margin-top:2px;font-weight:600}
.amt{color:#00B02C;font-size:22px;font-weight:800;}
.ico{width:44px;height:44px;border-radius:12px;}
.face{width:44px;height:44px;border-radius:50%;background:linear-gradient(135deg,hsl(264,62%,58%),hsl(210,68%,40%));}
.pill{display:inline-block;background:${INK};color:#fff;font-weight:800;font-size:20px;padding:18px 34px;border-radius:999px;}
.grid2{display:grid;grid-template-columns:1.1fr 1fr;gap:60px;align-items:center;}
.tree{display:grid;grid-template-columns:2.2fr 1.2fr 1fr;grid-template-rows:1fr 1fr;gap:10px;height:300px;}
.tree span{border-radius:18px;display:flex;align-items:flex-end;padding:16px;font-weight:800;font-size:22px;color:#fff;}
.band{display:flex;align-items:center;height:120px;margin-top:14px;border-radius:18px;overflow:hidden;}
.band i{display:block;height:100%;}
.heat{display:grid;grid-template-columns:repeat(14,1fr);gap:6px;margin-top:14px;}
.heat i{aspect-ratio:1;border-radius:4px;display:block;}
.chips{display:flex;gap:12px;flex-wrap:wrap;margin-top:26px;}
.chips span{background:rgba(0,0,0,.08);font-weight:750;font-size:17px;padding:12px 20px;border-radius:999px;}
.iconrow{display:flex;gap:18px;flex-wrap:wrap;margin-top:34px;}
</style></head><body>

<section class="slab" style="background:${GREEN}">
  <div class="grid2">
    <div>
      <h2>It lands.</h2>
      <div class="sub">Connect apps, follow people, watch wallets. Posts, money and deadlines show up on their own — you never file a thing.</div>
      <div style="margin-top:34px"><span class="pill">Get it on TestFlight</span></div>
    </div>
    <div class="card tilt1">
      <div class="row"><span class="face"></span><div style="flex:1"><div class="rt">tomato.eth · /art</div><div class="rs">Daily doodle 2018.</div></div><img class="ico" src="${ICONS['Farcaster']}"></div>
      <div class="row"><div style="flex:1"><div class="amt">+0.42 ETH</div><div class="rs">$1,284 · Base</div></div><div class="rs">Wallet</div></div>
      <div class="row"><img class="ico" src="${ICONS['Cloudflare']}"><div style="flex:1"><div class="rt">Cert expires in 12 days</div><div class="rs">yoursite.com</div></div></div>
      <div class="row"><img class="ico" src="${ICONS['Stripe']}"><div style="flex:1"><div class="rt">Dispute opened · $89</div><div class="rs">respond by Friday</div></div></div>
    </div>
  </div>
</section>

<section class="slab" style="background:${INK};color:#fff">
  <div class="grid2">
    <div class="card tilt2" style="background:#1d1d1d;color:#fff">
      <div style="font-size:15px;font-weight:750;color:#9a9a9a;letter-spacing:.06em">WHAT YOU HOLD</div>
      <div class="tree" style="margin-top:14px">
        <span style="grid-row:1/3;background:#4a63d8">ETH · $48K</span>
        <span style="background:#2775ca">USDC</span>
        <span style="background:#f7931a">WBTC</span>
        <span style="background:#14f195;color:#083b22">SOL</span>
        <span style="background:#333">+14</span>
      </div>
      <div style="font-size:15px;font-weight:750;color:#9a9a9a;letter-spacing:.06em;margin-top:26px">WHERE IT MOVED</div>
      <div class="band">
        <i style="flex:2.2;background:${GREEN}"></i><i style="flex:.9;background:#0d8f2f"></i>
        <i style="flex:.6;background:#2b2b2b"></i>
        <i style="flex:1.6;background:#555"></i><i style="flex:1;background:#3c3c3c"></i>
      </div>
    </div>
    <div>
      <h2 style="color:${GREEN}">You see it.</h2>
      <div class="sub" style="color:#cfcfcf">Not another list. Treemaps, flow bands, heatmaps — your money and your stuff, drawn so one glance answers the question.</div>
    </div>
  </div>
</section>

<section class="slab" style="background:#fff">
  <div class="grid2">
    <div>
      <h2>It briefs you.</h2>
      <div class="sub">Open the app and the day is already composed — from your things, on your device. Ask in plain words when you want more.</div>
      <div class="chips"><span>What's going on?</span><span>While I was away?</span><span>Show my links</span></div>
    </div>
    <div class="card tilt1" style="background:${INK};color:#fff">
      <div style="font-size:14px;color:#9a9a9a;font-weight:700">today so far</div>
      <div style="font-size:34px;font-weight:800;margin-top:4px">What's going on</div>
      <div style="font-size:20px;font-weight:750;margin-top:12px">Book dentist is overdue.</div>
      <div style="font-size:56px;font-weight:800;margin-top:18px">$95K <span style="font-size:18px;color:${GREEN}">▲ 2.1%</span></div>
      <div style="font-size:15px;color:#9a9a9a;margin-top:6px;font-weight:650">20 transactions settled · 3 more overdue</div>
    </div>
  </div>
</section>

<section class="slab" style="background:#F2F2F2">
  <div class="grid2">
    <div class="card tilt2">
      <div class="row"><div style="flex:1"><div class="rt">No account. No server.</div><div class="rs">Your things live on your phone.</div></div><div style="font-size:26px">🔒</div></div>
      <div class="row"><div style="flex:1"><div class="rt">Wallets are watch-only</div><div class="rs">Zero methods, zero events — can't trade, can't move funds.</div></div></div>
      <div class="row"><div style="flex:1"><div class="rt">"What this app reaches"</div><div class="rs">Every host named in Settings, with why.</div></div></div>
    </div>
    <div>
      <h2>It's yours.</h2>
      <div class="sub">All of it on device. Export, import, or delete everything — no account to close because there never was one.</div>
      <div class="iconrow">${icons(52, 14)}</div>
      <div style="margin-top:34px"><span class="pill" style="background:${GREEN};color:${INK}">Get it on TestFlight</span></div>
    </div>
  </div>
</section>
</body></html>`;

/* ================================= APPLE =================================
   Centered, airy, huge tight type, alternating light/dark, captions small
   and gray, the product front and center, one quiet link per section. */
const apple = () => `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Casberi — Apple direction</title><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,"Helvetica Neue",system-ui,sans-serif;-webkit-font-smoothing:antialiased;background:#fbfbfd;color:#1d1d1f;}
section{padding:130px 6vw;text-align:center;}
h2{font-size:clamp(44px,5.6vw,76px);font-weight:700;letter-spacing:-.03em;line-height:1.05;}
.sub{font-size:23px;color:#6e6e73;font-weight:500;margin:18px auto 0;max-width:640px;line-height:1.45;}
.link{display:inline-block;margin-top:16px;color:#0066cc;font-size:19px;font-weight:500;}
.stagewrap{margin:64px auto 0;max-width:980px;}
.dark{background:#000;color:#f5f5f7;}
.dark .sub{color:#86868b;}
.panel{border-radius:28px;overflow:hidden;background:#161617;box-shadow:0 40px 100px rgba(0,0,0,.35);padding:44px;text-align:left;color:#f5f5f7;}
.light .panel{background:#fff;color:#1d1d1f;box-shadow:0 30px 80px rgba(0,0,0,.1);}
.row{display:flex;align-items:center;gap:16px;padding:16px 0;border-bottom:1px solid rgba(120,120,128,.18);}
.row:last-child{border:none}
.rt{font-size:19px;font-weight:600;} .rs{font-size:15px;color:#86868b;margin-top:2px;}
.ico{width:42px;height:42px;border-radius:11px;} .face{width:42px;height:42px;border-radius:50%;background:linear-gradient(135deg,hsl(264,62%,58%),hsl(210,68%,40%));}
.amt{font-size:21px;font-weight:700;color:#30d158;}
.tree{display:grid;grid-template-columns:2.2fr 1.2fr 1fr;grid-template-rows:1fr 1fr;gap:8px;height:330px;}
.tree span{border-radius:14px;display:flex;align-items:flex-end;padding:16px;font-weight:700;font-size:20px;color:#fff;}
.duo{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px;}
.heat{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;}
.heat i{aspect-ratio:1;border-radius:4px;display:block;}
.map{display:flex;flex-direction:column;gap:8px;}
.map span{border-radius:12px;display:flex;align-items:flex-end;padding:14px;font-weight:700;font-size:18px;color:#fff;}
.chips{display:flex;gap:10px;justify-content:center;margin-top:26px;flex-wrap:wrap;}
.chips span{border:1px solid rgba(120,120,128,.3);border-radius:999px;padding:10px 20px;font-size:16px;font-weight:500;color:inherit;}
.iconrow{display:flex;gap:16px;justify-content:center;flex-wrap:wrap;margin-top:40px;}
.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin-top:60px;max-width:980px;margin-left:auto;margin-right:auto;}
.tile{background:#fff;border-radius:22px;padding:34px 26px;text-align:left;box-shadow:0 20px 50px rgba(0,0,0,.06);}
.tile b{font-size:19px;font-weight:700;display:block;} .tile span{font-size:15px;color:#6e6e73;display:block;margin-top:8px;line-height:1.5;}
.cta{display:inline-block;margin-top:44px;background:#0071e3;color:#fff;font-size:19px;font-weight:500;padding:14px 30px;border-radius:999px;}
</style></head><body>

<section class="light">
  <h2>Everything lands.<br>Automatically.</h2>
  <div class="sub">Connect apps, follow people, watch wallets. Posts, money and deadlines arrive on their own — nothing to file, nothing to check.</div>
  <div class="stagewrap" style="max-width:640px">
    <div class="panel">
      <div class="row"><span class="face"></span><div style="flex:1"><div class="rt">tomato.eth · /art</div><div class="rs">Daily doodle 2018.</div></div><img class="ico" src="${ICONS['Farcaster']}"></div>
      <div class="row"><div style="flex:1"><div class="amt">+0.42 ETH</div><div class="rs">$1,284 · Base</div></div><div class="rs">Wallet</div></div>
      <div class="row"><img class="ico" src="${ICONS['Cloudflare']}"><div style="flex:1"><div class="rt">Certificate expires in 12 days</div><div class="rs">yoursite.com — before the browser warning</div></div></div>
      <div class="row"><img class="ico" src="${ICONS['Stripe']}"><div style="flex:1"><div class="rt">Dispute opened · $89.00</div><div class="rs">Respond by Friday</div></div></div>
    </div>
  </div>
</section>

<section class="dark">
  <h2>See it. Don't scroll it.</h2>
  <div class="sub">Treemaps for what you hold. Flow bands for where it moved. Heatmaps for how they post. Your things, drawn.</div>
  <div class="stagewrap">
    <div class="panel">
      <div class="tree">
        <span style="grid-row:1/3;background:#4a63d8">ETH · $48.2K</span>
        <span style="background:#2775ca">USDC · $19.4K</span>
        <span style="background:#f7931a">WBTC · $7.8K</span>
        <span style="background:#14f195;color:#0b3d24">SOL · $11.1K</span>
        <span style="background:#3a3a3c">+14</span>
      </div>
      <div class="duo" style="margin-top:22px">
        <div class="map">
          <span style="flex:2;background:rgba(74,99,216,.9)">figma.com</span>
          <span style="flex:1.3;background:rgba(133,93,205,.85)">recipes</span>
          <span style="flex:1;background:rgba(255,159,10,.75)">flights</span>
        </div>
        <div class="heat">${Array.from({length: 48}).map((_, k) => `<i style="background:rgba(48,209,88,${((k*2654435761)>>>0)%97<40 ? (0.25 + (((k*40503)>>>0)%55)/100) : 0.08})"></i>`).join('')}</div>
      </div>
    </div>
  </div>
  <a class="link">See every visualization ›</a>
</section>

<section class="light">
  <h2>Your day, already composed.</h2>
  <div class="sub">Open the app and the brief is waiting — what settled, what's next, what's overdue. Written on your device, from your own things.</div>
  <div class="stagewrap" style="max-width:560px">
    <div class="panel" style="background:#000;color:#f5f5f7">
      <div style="font-size:14px;color:#86868b">today so far</div>
      <div style="font-size:32px;font-weight:700;margin-top:4px;letter-spacing:-.02em">What's going on</div>
      <div style="font-size:19px;font-weight:600;margin-top:12px">Book dentist is overdue.</div>
      <div style="font-size:54px;font-weight:700;margin-top:20px;letter-spacing:-.03em">$95K <span style="font-size:17px;color:#30d158;font-weight:600">▲ 2.1%</span></div>
      <div style="font-size:15px;color:#86868b;margin-top:8px">20 transactions settled · 3 reminders overdue</div>
    </div>
  </div>
  <div class="chips"><span>What's going on?</span><span>While I was away?</span><span>Show my links</span></div>
</section>

<section class="light" style="padding-top:40px">
  <h2>Private by structure.</h2>
  <div class="sub">Not a promise — an architecture.</div>
  <div class="grid3">
    <div class="tile"><b>No account. No server.</b><span>Your things live on your device and sync with iCloud only if you turn it on.</span></div>
    <div class="tile"><b>Wallets are watch-only.</b><span>Connecting proposes zero methods and zero events — watching can never trade or move funds.</span></div>
    <div class="tile"><b>Every host, named.</b><span>Settings lists every service the app reaches, and why. Nothing routes through us — there is no us.</span></div>
  </div>
  <div class="iconrow">${icons(46, 12)}</div>
  <a class="cta">Get it on TestFlight</a>
</section>
</body></html>`;

/* ================================= UBER =================================
   Editorial black on white, hard grid, numbered sections, square corners,
   rule lines, one accent (safety blue), utilitarian. */
const uber = () => `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Casberi — Uber direction</title><style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,"Helvetica Neue",system-ui,sans-serif;-webkit-font-smoothing:antialiased;background:#fff;color:#000;}
.wrap{max-width:1200px;margin:0 auto;padding:0 40px;}
section{padding:90px 0;border-top:3px solid #000;}
.num{font-size:16px;font-weight:700;letter-spacing:.08em;color:#276EF1;}
h2{font-size:clamp(40px,5vw,68px);font-weight:800;letter-spacing:-.03em;line-height:1;margin-top:14px;}
.sub{font-size:19px;color:#333;margin-top:18px;max-width:520px;line-height:1.5;font-weight:500;}
.g{display:grid;grid-template-columns:1fr 1fr;gap:70px;align-items:start;margin-top:10px;}
.panel{border:2px solid #000;padding:28px;}
.row{display:flex;align-items:center;gap:14px;padding:15px 0;border-bottom:1px solid #d9d9d9;}
.row:last-child{border-bottom:none;}
.rt{font-size:17px;font-weight:700;} .rs{font-size:14px;color:#666;margin-top:2px;font-weight:500}
.ico{width:38px;height:38px;} .face{width:38px;height:38px;border-radius:50%;background:#276EF1;}
.amt{font-size:19px;font-weight:800;}
.tree{display:grid;grid-template-columns:2.2fr 1.2fr 1fr;grid-template-rows:1fr 1fr;gap:4px;height:280px;margin-top:4px;}
.tree span{display:flex;align-items:flex-end;padding:12px;font-weight:800;font-size:17px;color:#fff;background:#000;}
.band{display:flex;height:84px;margin-top:4px;}
.band i{display:block;height:100%;}
.heat{display:grid;grid-template-columns:repeat(16,1fr);gap:4px;margin-top:4px;}
.heat i{aspect-ratio:1;display:block;}
.btn{display:inline-block;background:#000;color:#fff;font-size:17px;font-weight:700;padding:16px 28px;margin-top:30px;}
.list{margin-top:22px;}
.list div{display:flex;justify-content:space-between;padding:16px 0;border-bottom:1px solid #d9d9d9;font-size:17px;font-weight:600;}
.list div span:last-child{color:#666;font-weight:500;}
.iconrow{display:flex;gap:10px;flex-wrap:wrap;margin-top:26px;}
.cap{font-size:13px;color:#666;margin-top:10px;font-weight:600;letter-spacing:.04em;}
</style></head><body>
<div class="wrap">

<section>
  <div class="num">01</div>
  <h2>It lands.</h2>
  <div class="g">
    <div class="sub">Connect apps, follow people, watch wallets. Posts, money and deadlines land in one feed, in the order they happened. No ranking. No algorithm.</div>
    <div class="panel">
      <div class="row"><span class="face"></span><div style="flex:1"><div class="rt">tomato.eth · /art</div><div class="rs">Daily doodle 2018.</div></div><img class="ico" src="${ICONS['Farcaster']}"></div>
      <div class="row"><div style="flex:1"><div class="amt">+0.42 ETH</div><div class="rs">$1,284 · Base</div></div><div class="rs">WALLET</div></div>
      <div class="row"><img class="ico" src="${ICONS['Cloudflare']}"><div style="flex:1"><div class="rt">Cert expires in 12 days</div><div class="rs">yoursite.com</div></div></div>
      <div class="row"><img class="ico" src="${ICONS['Stripe']}"><div style="flex:1"><div class="rt">Dispute opened · $89</div><div class="rs">Respond by Friday</div></div></div>
    </div>
  </div>
</section>

<section>
  <div class="num">02</div>
  <h2>You see it.</h2>
  <div class="g">
    <div>
      <div class="sub">Holdings as a treemap. Movement as a flow band. Posting as a density grid. The chart is the interface, not a report at the end of it.</div>
      <div class="list">
        <div><span>What you hold</span><span>treemap</span></div>
        <div><span>Where it moved</span><span>flow band</span></div>
        <div><span>Who's connected</span><span>drawn, never inferred</span></div>
        <div><span>How they post</span><span>heatmap</span></div>
      </div>
    </div>
    <div>
      <div class="tree">
        <span style="grid-row:1/3;background:#276EF1">ETH · $48K</span>
        <span>USDC</span><span>WBTC</span><span style="background:#333">SOL</span><span style="background:#666">+14</span>
      </div>
      <div class="band">
        <i style="flex:2.2;background:#276EF1"></i><i style="flex:.9;background:#7aa2f7"></i>
        <i style="flex:.5;background:#000"></i>
        <i style="flex:1.6;background:#999"></i><i style="flex:1;background:#ccc"></i>
      </div>
      <div class="heat">${Array.from({length: 64}).map((_, k) => `<i style="background:${((k*2654435761)>>>0)%97<38 ? '#276EF1' : '#eee'};opacity:${((k*2654435761)>>>0)%97<38 ? (0.35 + (((k*40503)>>>0)%65)/100) : 1}"></i>`).join('')}</div>
      <div class="cap">TREEMAP · FLOW BAND · POSTING DENSITY</div>
    </div>
  </div>
</section>

<section>
  <div class="num">03</div>
  <h2>It briefs you.</h2>
  <div class="g">
    <div class="sub">Open the app to a composed brief: what settled, what's next, what's overdue. Written on the device, from your own things — ask in plain words for anything else.</div>
    <div class="panel" style="background:#000;color:#fff;border-color:#000">
      <div style="font-size:13px;color:#999;font-weight:700;letter-spacing:.06em">TODAY SO FAR</div>
      <div style="font-size:30px;font-weight:800;margin-top:6px">What's going on</div>
      <div style="font-size:18px;font-weight:700;margin-top:10px">Book dentist is overdue.</div>
      <div style="font-size:48px;font-weight:800;margin-top:16px">$95K <span style="font-size:15px;color:#7aa2f7">▲ 2.1%</span></div>
      <div style="font-size:14px;color:#999;margin-top:6px;font-weight:600">20 TRANSACTIONS SETTLED · 3 OVERDUE</div>
    </div>
  </div>
</section>

<section>
  <div class="num">04</div>
  <h2>It's yours.</h2>
  <div class="g">
    <div>
      <div class="sub">No account, no server, everything on device. Wallets connect watch-only — zero methods, zero events. Settings names every host the app reaches, and why.</div>
      <div class="iconrow">${icons(40, 0)}</div>
    </div>
    <div>
      <div class="list" style="margin-top:0">
        <div><span>Account required</span><span>none</span></div>
        <div><span>Server</span><span>none</span></div>
        <div><span>Wallet permissions</span><span>0 methods · 0 events</span></div>
        <div><span>Hosts reached</span><span>all named in Settings</span></div>
        <div><span>Delete everything</span><span>one tap, including iCloud</span></div>
      </div>
      <span class="btn">Get it on TestFlight →</span>
    </div>
  </div>
</section>

</div></body></html>`;

fs.writeFileSync(path.join(SITE, 'mock-below-cashapp.html'), cashapp());
fs.writeFileSync(path.join(SITE, 'mock-below-apple.html'), apple());
fs.writeFileSync(path.join(SITE, 'mock-below-uber.html'), uber());
console.log('wrote mock-below-cashapp.html, mock-below-apple.html, mock-below-uber.html');
