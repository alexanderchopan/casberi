// Builds ONE combined "delight moments" clip from real screen-recording
// footage (not static screenshots) against the same visual system as the
// other launch clips: drifting icon backdrop, phone springs up, real video
// plays inside the screen, caption per moment, phone drops out, sign-off.
const fs = require('fs');
const path = require('path');

const SITE = '/Users/alexanderchopan/Developer/casberi/website';
const index = fs.readFileSync(path.join(SITE, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(SITE, 'styles.css'), 'utf8');

const rainMatch = index.match(/<div class="rain">([\s\S]*?)\n\s*<\/div>\s*\n\s*<div class="rain-target">/);
const iconDivs = rainMatch[1].split('\n').map(s => s.trim()).filter(s => s.startsWith('<div class="ai'));
const berryIcon = index.match(/rel="icon" href="(data:image\/png;base64,[^"]+)"/)[1];

// Each moment: a trimmed real recording + a non-editorializing caption.
const STAGE_DUR = 3.6; // spacing between stage starts
const MOMENTS = [
  { file: 'feed-switch.mp4', at: 0.15, sub: 'Switch the feed to a source —<br>the color follows.' },
  { file: 'thing-sheet.mp4', at: 0.15 + STAGE_DUR * 1, sub: 'Open a thing —<br>its icon turns to meet you.' },
  { file: 'shelf-stock.mp4', at: 0.15 + STAGE_DUR * 2, sub: 'Every catalog row<br>lands in its own beat.' },
  { file: 'kalshi-open.mp4', at: 0.15 + STAGE_DUR * 3, sub: 'Open an app —<br>the page wears its brand.' },
  { file: 'connect.mp4', at: 0.15 + STAGE_DUR * 4, sub: 'Connect —<br>straight into setup.' },
];
const LAST_HOLD = 3.8;
const OUT_AT = MOMENTS[MOMENTS.length - 1].at + LAST_HOLD;
const DUR = OUT_AT + 1.35;
const BERRY_AT = DUR - 1.05;

const TITLE = 'Small moments,<br>everywhere';

const bgIcons = iconDivs.filter((_, i) => i % 4 === 0)
  .map((d, i) => `<div class="cube bg" id="bgi${i}">${d}</div>`).join('\n');

const videoTags = MOMENTS.map((m, i) =>
  `<video class="vshot" id="shot${i}" src="clips/${m.file}" muted playsinline preload="auto"></video>`).join('\n');

const STAGES = MOMENTS.map((m, i) => ({ at: m.at, sub: m.sub, file: m.file }));

const HELPERS = `
const clamp01 = v => Math.max(0, Math.min(1, v));
const easeOutCubic = p => 1 - Math.pow(1 - p, 3);
function springStep(t, duration, bounce) {
  if (t <= 0) return 0;
  const zeta = 1 - bounce, wn = 2 * Math.PI / duration;
  const wd = wn * Math.sqrt(1 - zeta * zeta);
  const e = Math.exp(-zeta * wn * t);
  return 1 - e * (Math.cos(wd * t) + (zeta * wn / wd) * Math.sin(wd * t));
}
const JIT = [-4, 3, -2, 5, -5, 2, -3, 4];
function fadeRise(el, t, at, dur = 0.55, rise = 22) {
  const p = clamp01((t - at) / dur);
  el.style.opacity = p;
  el.style.transform = 'translateY(' + ((1 - easeOutCubic(p)) * rise) + 'px)';
}
`;

const html = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<style>${css}</style>
<style>
*, *::before, *::after { transition: none !important; }
html, body { width: 1080px; height: 1920px; overflow: hidden; background: var(--bg); }
.stage { position: relative; width: 1080px; height: 1920px; overflow: hidden; }
.glow { position: absolute; inset: 0;
  background: radial-gradient(700px 900px at 50% 40%, rgba(22,115,230,.12), transparent 70%); }
.cube.bg { position: absolute; width: 56px; height: 56px; opacity: 0; will-change: transform; }
.cube.bg .ai { width: 56px; height: 56px; border-radius: 15px; font-size: 22px; transform: scale(1.7); }
.cap { position: absolute; left: 70px; right: 70px; top: 150px; text-align: center; opacity: 0; }
.cap h2 { font-size: 88px; line-height: 1.02; font-weight: 850; letter-spacing: -0.035em; color: var(--ink); }
.cap p { font-size: 35px; line-height: 1.45; color: var(--muted); margin-top: 24px; opacity: 0; }
.vphone { position: absolute; left: 200px; top: 560px; width: 680px; height: 1424px;
  border-radius: 104px; background: #16181d; border: 1px solid rgba(255,255,255,.09);
  box-shadow: 0 40px 90px rgba(0,0,0,.55); will-change: transform; transform: translateY(1500px); }
.vphone .vscreen { position: absolute; inset: 24px; border-radius: 82px; overflow: hidden; background: #000; }
.vshot { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top; opacity: 0; will-change: transform, opacity; }
.endWrap { position: absolute; left: 0; right: 0; bottom: 130px; display: flex; flex-direction: column;
  align-items: center; opacity: 0; will-change: transform, opacity; }
.endIcon { width: 100px; height: 100px; border-radius: 26px; overflow: hidden; box-shadow: 0 14px 34px rgba(0,0,0,.5); }
.endIcon img { width: 100%; height: 100%; display: block; }
.endUrl { font-size: 30px; color: var(--muted); margin-top: 16px; }
.endUrl b { color: var(--blue-bright); font-weight: 650; }
</style>
</head><body>
<div class="stage"><div class="glow"></div>
<div id="bgRain">${bgIcons}</div>
<div class="cap" id="cap"><h2>${TITLE}</h2><p id="sub">${MOMENTS[0].sub}</p></div>
<div class="vphone" id="phone"><div class="vscreen">${videoTags}</div></div>
<div class="endWrap" id="endWrap">
  <div class="endIcon"><img src="${berryIcon}"></div>
  <div class="endUrl"><b>casberi.app</b> &nbsp;·&nbsp; Free on TestFlight</div>
</div>
</div>
<script>${HELPERS}
const bgis = [...document.querySelectorAll('.cube.bg')].map((el, i) => {
  el.style.left = (40 + ((i * 419) % 990)) + 'px';
  return { el, i, speed: 40 + (i * 17) % 46, phase: (i * 523) % 2100 };
});
const PHONE_AT = 0.15, PHONE_OUT = ${OUT_AT};
window.TOTAL = ${DUR};
const STAGES = ${JSON.stringify(STAGES)};
const shots = STAGES.map((_, i) => document.getElementById('shot' + i));
const started = STAGES.map(() => false);

window.seek = function (t) {
  const bgOp = clamp01((t - 0.3) / 1.0) * (1 - clamp01((t - PHONE_OUT) / 0.5));
  for (const b of bgis) {
    b.el.style.opacity = 0.09 * bgOp;
    b.el.style.transform = 'translateY(' + (((t * b.speed + b.phase) % 2280) - 180) + 'px) rotate(' + JIT[b.i % 8] * 2 + 'deg)';
  }
  const pin = springStep(Math.max(0, Math.min(t - PHONE_AT, 1.9)), 1.0, 0.32);
  let py = 1500 * (1 - pin);
  if (t > PHONE_OUT) py += Math.pow(clamp01((t - PHONE_OUT) / 0.6), 3) * 1650;
  document.getElementById('phone').style.transform = 'translateY(' + py + 'px)';
  const cap = document.getElementById('cap');
  fadeRise(cap, t, 0.55, 0.65);
  document.getElementById('sub').style.opacity = clamp01((t - 0.9) / 0.6);
  if (t > PHONE_OUT) cap.style.opacity = Math.min(cap.style.opacity, 1 - clamp01((t - PHONE_OUT) / 0.4));

  STAGES.forEach((st, i) => {
    const nextAt = i + 1 < STAGES.length ? STAGES[i + 1].at : Infinity;
    const inX = clamp01((t - st.at) / 0.5);
    const outX = nextAt === Infinity ? 0 : clamp01((t - (nextAt - 0.5)) / 0.5);
    shots[i].style.opacity = inX * (1 - outX);
    if (t >= st.at && !started[i]) {
      started[i] = true;
      try { shots[i].currentTime = 0; shots[i].play().catch(() => {}); } catch (e) {}
    }
  });
  let activeStage = 0;
  for (let i = 0; i < STAGES.length; i++) if (t >= STAGES[i].at) activeStage = i;
  document.getElementById('sub').innerHTML = STAGES[activeStage].sub;

  fadeRise(document.getElementById('endWrap'), t, ${BERRY_AT}, 0.6, 16);
};

// Real-time driver: rAF loop using actual elapsed time so <video> playback
// stays in sync (deterministic per-frame seeking doesn't work for <video>).
window.__ready = false;
let startTime = null;
function loop(now) {
  if (startTime === null) startTime = now;
  const t = (now - startTime) / 1000;
  window.seek(t);
  if (t < window.TOTAL + 0.5) requestAnimationFrame(loop);
  else window.__ready = true;
}
requestAnimationFrame(loop);
</script></body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-delight.html'), html);
console.log('wrote clip-delight.html', (html.length / 1024).toFixed(0) + 'KB', DUR.toFixed(1) + 's');
console.log('stages:', STAGES.map(s => s.at.toFixed(2) + 's ' + s.file).join(', '));
