// Builds four short (5-7s) 1080x1920 feature clips against the UPDATED app
// look (canonical ~/Developer/casberi): home feed, app catalogue, source
// feed, composer. Same visual system as the earlier launch videos: drifting
// icon backdrop, phone springs up with a real screenshot, caption, phone
// drops out, tiny brand sign-off.
const fs = require('fs');
const path = require('path');

const SITE = '/Users/alexanderchopan/Developer/casberi/website';
const SHOTS = path.join(__dirname, 'shots2');
const index = fs.readFileSync(path.join(SITE, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(SITE, 'styles.css'), 'utf8');

const rainMatch = index.match(/<div class="rain">([\s\S]*?)\n\s*<\/div>\s*\n\s*<div class="rain-target">/);
const iconDivs = rainMatch[1].split('\n').map(s => s.trim()).filter(s => s.startsWith('<div class="ai'));
const berryIcon = index.match(/rel="icon" href="(data:image\/png;base64,[^"]+)"/)[1];

// CLIPS: one shot (single image) or a mid-clip crossfade to a second shot.
const CLIPS = [
  {
    name: 'clip-home', dur: 5.0, title: 'Home', sub: 'Your week, banked automatically —<br>no digging required.',
    shots: [{ img: 'home.png', at: 0.15 }],
  },
  {
    name: 'clip-apps', dur: 5.0, title: 'Connect anything', sub: 'Wallets, markets, your life —<br>more apps landing every week.',
    shots: [{ img: 'apps.png', at: 0.15 }],
  },
  {
    name: 'clip-source-feed', dur: 10.5, title: 'One feed,<br>every shape', sub: 'Tap a chip — the feed<br>takes that app\'s shape.',
    shots: [
      { img: 'feed.png', at: 0.15 },
      { img: 'feed-source-photos.png', at: 2.3, sub2: 'Photos glow blue —<br>a grid, not a list.' },
      { img: 'feed-source-calendar.png', at: 4.6, sub2: 'Calendar wears red —<br>your day, laid out.' },
      { img: 'feed-source.png', at: 6.9, sub2: 'Even agent approvals —<br>right where you\'ll see them.' },
    ],
  },
  {
    name: 'clip-composer', dur: 6.0, title: 'Ask anything', sub: 'Type a question about<br>anything you\'ve connected.',
    shots: [{ img: 'composer-typing.png', at: 0.15 }, { img: 'composer-answer.png', at: 2.6, sub2: 'Answered on-device —<br>and it cites what it used.' }],
  },
  {
    name: 'clip-language', dur: 10.5, title: 'Five languages,<br>one app', sub: 'Pick one — it switches<br>right there, live.',
    shots: [
      { img: 'lang-picker.png', at: 0.15 },
      { img: 'lang-settings-es.png', at: 2.3, sub2: 'Español — down to<br>the date and the tab bar.' },
      { img: 'lang-settings-ja.png', at: 4.6, sub2: '日本語 — no relaunch,<br>no reset.' },
      { img: 'lang-settings-zh.png', at: 6.9, sub2: '简体中文 — every screen<br>follows along.' },
    ],
  },
];

const HELPERS = `
const clamp01 = v => Math.max(0, Math.min(1, v));
const easeOutCubic = p => 1 - Math.pow(1 - p, 3);
const easeInCubic = p => p * p * p;
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

function b64ForImg(name) {
  const buf = fs.readFileSync(path.join(SHOTS, name));
  const ext = name.endsWith('.png') ? 'png' : 'jpeg';
  return `data:image/${ext};base64,${buf.toString('base64')}`;
}

for (const clip of CLIPS) {
  const bgIcons = iconDivs.filter((_, i) => i % 4 === 0)
    .map((d, i) => `<div class="cube bg" id="bgi${i}">${d}</div>`).join('\n');

  const shotImgs = clip.shots.map((s, i) =>
    `<img class="vshot" id="shot${i}" src="${b64ForImg(s.img)}">`).join('\n');

  const OUT_AT = clip.dur - 1.35;
  const BERRY_AT = clip.dur - 1.05;
  const NAME_AT = clip.dur - 0.75;

  // stages[i] = { at, sub } — sub falls back to the clip's base sub for shot 0.
  const stages = clip.shots.map((s, i) => ({ at: s.at, sub: i === 0 ? clip.sub : s.sub2 }));

  const html = `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<style>${css}</style>
<style>
*, *::before, *::after { animation: none !important; transition: none !important; }
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
<div class="cap" id="cap"><h2>${clip.title}</h2><p id="sub">${clip.sub}</p></div>
<div class="vphone" id="phone"><div class="vscreen">${shotImgs}</div></div>
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
window.TOTAL = ${clip.dur};
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

  // N-shot crossfade: each shot fades in at its stage start time and fades
  // out as the next stage's start approaches (last shot just holds).
  const STAGES = ${JSON.stringify(stages)};
  const shots = STAGES.map((_, i) => document.getElementById('shot' + i));
  STAGES.forEach((st, i) => {
    const nextAt = i + 1 < STAGES.length ? STAGES[i + 1].at : Infinity;
    const inX = clamp01((t - st.at) / 0.5);
    const outX = nextAt === Infinity ? 0 : clamp01((t - (nextAt - 0.5)) / 0.5);
    shots[i].style.opacity = inX * (1 - outX);
  });
  let activeStage = 0;
  for (let i = 0; i < STAGES.length; i++) if (t >= STAGES[i].at) activeStage = i;
  document.getElementById('sub').innerHTML = STAGES[activeStage].sub;

  fadeRise(document.getElementById('endWrap'), t, ${BERRY_AT}, 0.6, 16);
};
window.seek(0);
</script></body></html>`;

  fs.writeFileSync(path.join(__dirname, clip.name + '.html'), html);
  console.log('wrote', clip.name + '.html', (html.length / 1024).toFixed(0) + 'KB', clip.dur + 's');
}
