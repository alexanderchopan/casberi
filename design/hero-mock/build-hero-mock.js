// Two hero-layout mockups for the "put the real product above the fold"
// question. Writes website/mock-hero-a.html and website/mock-hero-b.html —
// the `mock-*.html` prefix is ALREADY excluded from the deploy zip, so these
// can sit in website/ and load the real styles.css without ever shipping.
//
//   A = the composed trio: Mac / iPad / iPhone as ONE overlapping lineup,
//       centered under the CTA. One object the eye reads once.
//   B = the corner layout the user asked for: devices anchored bottom-left
//       and bottom-right, hero copy floating between them.
//
// Both use REAL screenshots (design/hero-mock/*.png), captured from the
// running app — no drawn UI, since the whole point is proving the product
// exists. Each device shows a DIFFERENT screen: the Mac/iPad carry the split
// view (rail + feed + open thing), the iPhone carries the feed itself.
const fs = require('fs'), path = require('path');

const OUT = path.join(__dirname, '../../website');
const IMG = '../design/hero-mock';   // relative from website/ for file:// viewing

// A Mac shot may not exist yet (Catalyst build running) — fall back to the
// iPad frame so the LAYOUT is still judgeable, and label it honestly.
const hasMac = fs.existsSync(path.join(__dirname, 'mac-raw.png'));
const macSrc = hasMac ? `${IMG}/mac-raw.png` : `${IMG}/ipad-raw.png`;
const macNote = hasMac ? '' : ' data-placeholder="true"';

const shells = `
/* ---- device shells (mockup only) ---- */
.dev { position: relative; flex: none; }
.dev img { display: block; width: 100%; height: 100%; object-fit: cover; object-position: top center; }

/* Mac: window chrome + a thin bezel, on a subtle stand */
.dev-mac { width: var(--macw); }
.dev-mac .screen {
  position: relative; border-radius: 10px 10px 3px 3px; overflow: hidden;
  background: #0b0910; aspect-ratio: 16 / 10;
  box-shadow: 0 0 0 8px #1c1f26, 0 0 0 9px #2b3038, 0 30px 60px rgba(0,0,0,.55);
}
.dev-mac .chrome {
  position: absolute; inset: 0 0 auto 0; height: 22px; z-index: 2;
  background: rgba(20,23,30,.92); display: flex; align-items: center; gap: 6px; padding: 0 10px;
}
.dev-mac .chrome i { width: 8px; height: 8px; border-radius: 50%; display: block; }
.dev-mac .foot {
  height: 10px; margin: 0 auto; width: 72%;
  background: linear-gradient(180deg,#2b3038,#171a20);
  border-radius: 0 0 8px 8px;
}
.dev-mac .lip { height: 4px; width: 16%; margin: 0 auto; background: #12151a; border-radius: 0 0 6px 6px; }

/* iPad: even bezel */
.dev-pad { width: var(--padw); }
.dev-pad .screen {
  border-radius: 18px; overflow: hidden; background: #0b0910; aspect-ratio: 2048 / 2732;
  box-shadow: 0 0 0 9px #1c1f26, 0 0 0 10px #2b3038, 0 26px 54px rgba(0,0,0,.5);
}

/* iPhone: tighter bezel + island */
.dev-phone { width: var(--phonew); }
.dev-phone .screen {
  position: relative; border-radius: 26px; overflow: hidden; background: #0b0910;
  aspect-ratio: 1242 / 2688;
  box-shadow: 0 0 0 7px #1c1f26, 0 0 0 8px #2b3038, 0 24px 50px rgba(0,0,0,.55);
}
.dev-phone .island {
  position: absolute; top: 8px; left: 50%; transform: translateX(-50%);
  width: 30%; height: 16px; border-radius: 999px; background: #000; z-index: 2;
}
/* "Soon" tag for the Mac, so a shell never implies a shipped app */
.dev .soonTag {
  position: absolute; top: -12px; left: 50%; transform: translateX(-50%);
  font-size: 10.5px; font-weight: 800; letter-spacing: .07em; text-transform: uppercase;
  background: var(--blue); color: #fff; border-radius: 999px; padding: 4px 10px;
  box-shadow: 0 4px 14px rgba(22,115,230,.45); z-index: 5; white-space: nowrap;
}
.dev-label {
  margin-top: 10px; text-align: center; font-size: 12px; font-weight: 650;
  color: var(--faint); letter-spacing: .04em;
}
`;

const macShell = (soon = true) => `
<div class="dev dev-mac">
  ${soon ? '<span class="soonTag">Mac · soon</span>' : ''}
  <div class="screen"><span class="chrome"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></span><img src="${macSrc}"${macNote}></div>
  <div class="foot"></div><div class="lip"></div>
</div>`;

const padShell = `
<div class="dev dev-pad">
  <div class="screen"><img src="${IMG}/ipad-raw.png"></div>
</div>`;

const phoneShell = `
<div class="dev dev-phone">
  <div class="screen"><span class="island"></span><img src="${IMG}/iphone-raw.png"></div>
</div>`;

const page = (title, variantCSS, heroInner) => `<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><title>${title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="styles.css">
<style>
body { padding-bottom: 60px; }
.mocklabel {
  position: fixed; top: 0; left: 0; right: 0; z-index: 999;
  background: #ffcc00; color: #14110d; font: 700 12px/1 -apple-system, sans-serif;
  padding: 7px 12px; letter-spacing: .04em; text-align: center;
}
header.hero { padding-top: 34px; }
${shells}
${variantCSS}
</style></head><body>
<div class="mocklabel">${title} — MOCKUP, not shipped</div>
<div class="wrap">
  <nav>
    <a class="brand" href="#top"><span class="brandmark" style="background:#12151b;border-radius:8px;display:inline-block"></span> Casberi</a>
    <div class="nav-links"><a href="docs.html">Docs</a><a href="privacy.html">Privacy</a></div>
  </nav>
  <header class="hero">
    ${heroInner}
  </header>
</div>
</body></html>`;

// Shared hero copy — identical in both so only the LAYOUT differs.
const copyBlock = `
    <h1>One place for <em>your apps.</em></h1>
    <p class="hero-line">An agent that keeps tabs on what matters.</p>
    <div class="priv-chips hero-chips">
      <span>No account</span><span>No server</span><span>All on device</span>
    </div>
    <div class="cta-row"><a class="cta" href="#">Get it on TestFlight</a></div>
    <div class="platforms">
      <span class="plat">iPhone</span><span class="plat">iPad</span>
      <span class="plat next">Mac<em>Soon</em></span>
    </div>`;

// ── A: composed trio, one unit, centered under the CTA ───────────────────
const cssA = `
.trio {
  --macw: 620px; --padw: 250px; --phonew: 150px;
  display: flex; align-items: flex-end; justify-content: center;
  margin-top: 40px; padding-bottom: 8px;
}
.trio .dev-pad   { margin-right: -54px; margin-bottom: 16px; z-index: 1; }
.trio .dev-mac   { z-index: 2; }
.trio .dev-phone { margin-left: -46px; margin-bottom: -6px; z-index: 3; }
@media (max-width: 900px) {
  .trio { --macw: 400px; --padw: 165px; --phonew: 100px; }
  .trio .dev-pad { margin-right: -34px; } .trio .dev-phone { margin-left: -30px; }
}
@media (max-width: 560px) {
  .trio { --macw: 290px; --padw: 118px; --phonew: 74px; margin-top: 28px; }
  .trio .dev-pad { margin-right: -24px; } .trio .dev-phone { margin-left: -22px; }
}`;

const heroA = `${copyBlock}
    <div class="trio">
      ${padShell}
      ${macShell(true)}
      ${phoneShell}
    </div>`;

// ── B: corner-anchored, hero copy between them ───────────────────────────
const cssB = `
.cornerstage {
  --macw: 460px; --padw: 210px; --phonew: 132px;
  position: relative; min-height: 640px; margin-top: 10px;
}
.cornerstage .copy { position: relative; z-index: 4; }
.corner-l { position: absolute; left: -70px;  bottom: -40px; z-index: 1; transform: rotate(-6deg); }
.corner-r { position: absolute; right: -40px; bottom: -50px; z-index: 1; transform: rotate(6deg);
            display: flex; align-items: flex-end; }
.corner-r .dev-phone { margin-left: -40px; margin-bottom: -10px; z-index: 2; }
@media (max-width: 1100px) {
  .cornerstage { --macw: 340px; --padw: 160px; --phonew: 100px; min-height: 560px; }
  .corner-l { left: -90px; } .corner-r { right: -60px; }
}
@media (max-width: 760px) {
  /* the honest failure mode: corners can't hold three devices on a phone,
     so they stack under the copy and the layout stops being "corners" */
  .cornerstage { --macw: 250px; --padw: 120px; --phonew: 78px; min-height: 0; }
  .corner-l, .corner-r { position: static; transform: none; display: flex;
                         justify-content: center; margin-top: 22px; }
}`;

const heroB = `<div class="cornerstage">
      <div class="corner-l">${macShell(true)}</div>
      <div class="copy">${copyBlock}</div>
      <div class="corner-r">${padShell}${phoneShell}</div>
    </div>`;

fs.writeFileSync(path.join(OUT, 'mock-hero-a.html'), page('A · composed trio', cssA, heroA));
fs.writeFileSync(path.join(OUT, 'mock-hero-b.html'), page('B · bottom corners', cssB, heroB));
console.log('wrote website/mock-hero-a.html and website/mock-hero-b.html');
console.log('mac shot:', hasMac ? 'REAL Catalyst capture' : 'PLACEHOLDER (iPad shot) — Catalyst build still running');
