// App Store marketing screenshot composer — editorial house style.
// Renders a real device screenshot onto the paper ground with a headline,
// at EXACT App Store dimensions. Same visual language as the launch clips.
//
//   node build-appstore-shot.js <raw.png> "<Headline>" "<sub>" <W> <H> <accent>
//   node render.js clip-appstore-shot.html --size=<W>x<H>
//
// Apple-safe by construction: the real app UI is the subject, nothing is
// fabricated, no award/pricing badges — only a background + caption, which
// App Store screenshot guidelines allow.
const fs = require('fs'), path = require('path');
const [rawPath, headline, sub, W, H, accent, theme] = process.argv.slice(2);
const w = parseInt(W, 10), h = parseInt(H, 10);
const AC = accent || '#2E63FF';
// paper = the editorial house style (matches every launch clip).
// blue  = a saturated brand ground, white type.
const T = theme === 'blue'
  ? { bg: 'linear-gradient(165deg,#2E63FF,#12307f)', ink: '#ffffff', sub: 'rgba(255,255,255,.72)',
      rule: 'rgba(255,255,255,.35)', grain: '.18', shadow: 'rgba(4,12,40,.45)' }
  : { bg: '#EEEAE1', ink: '#14110d', sub: '#4a463c',
      rule: '#14110d', grain: '.5', shadow: 'rgba(20,17,13,.30)' };
const img = 'data:image/png;base64,' + fs.readFileSync(rawPath).toString('base64');

// Scale the whole layout off the target width so one template serves every
// device size (6.9" / 6.5" / iPad) without per-size hand-tuning.
const S = w / 1320;
const padX = Math.round(96 * S);
const headSize = Math.round(104 * S);
const subSize = Math.round(40 * S);
const mastSize = Math.round(26 * S);
const shotTop = Math.round(560 * S);
const shotW = Math.round(1080 * S);
const radius = Math.round(56 * S);

const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html,body{width:${w}px;height:${h}px;overflow:hidden;background:${T.bg};
  font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:${T.grain};background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(96*S)}px;display:flex;justify-content:space-between;
  font-size:${mastSize}px;letter-spacing:.16em;color:${T.ink};font-weight:600;}
.rule{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(150*S)}px;height:${Math.max(2,Math.round(3*S))}px;background:${T.rule};}
.head{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(232*S)}px;
  font-size:${headSize}px;line-height:.95;font-weight:800;letter-spacing:-.045em;color:${T.ink};white-space:pre-line;}
.sub{position:absolute;left:${padX}px;right:${padX}px;top:${Math.round(452*S)}px;
  font-size:${subSize}px;line-height:1.35;color:${T.sub};font-weight:500;}
.shot{position:absolute;left:50%;transform:translateX(-50%);top:${shotTop}px;width:${shotW}px;
  border-radius:${radius}px;overflow:hidden;
  box-shadow:${Math.round(40*S)}px ${Math.round(46*S)}px 0 rgba(20,17,13,.13),
             0 ${Math.round(34*S)}px ${Math.round(80*S)}px ${T.shadow};}
.shot img{width:100%;display:block;}
.dot{position:absolute;left:${padX}px;top:${Math.round(196*S)}px;width:${Math.round(18*S)}px;height:${Math.round(18*S)}px;border-radius:50%;background:${theme==="blue"?"#ffffff":AC};}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>casberi.app</span></div>
<div class="rule"></div>
<div class="dot"></div>
<div class="head">${headline.replace(/\\n/g, '\n')}</div>
<div class="sub">${sub}</div>
<div class="shot"><img src="${img}"></div>
<script>window.TOTAL=0.1;window.seek=function(){};</script>
</body></html>`;

fs.writeFileSync(path.join(__dirname, 'clip-appstore-shot.html'), html);
console.log(`composed ${w}x${h} :: ${headline.replace(/\n/g, ' ')}`);
