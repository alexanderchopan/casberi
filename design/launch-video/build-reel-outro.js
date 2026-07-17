// Sizzle-reel end card (editorial). node render.js clip-reel-outro.html --size=1080x1920
const fs=require('fs'),path=require('path');
const TOTAL=2.2;
const html=`<!DOCTYPE html><html><head><meta charset="utf-8"><style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;transition:none!important}
html,body{width:1080px;height:1920px;overflow:hidden;background:#EEEAE1;font-family:-apple-system,"Helvetica Neue","SF Pro Display",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.mono{font-family:ui-monospace,"SF Mono","Menlo",monospace;}
.grain{position:absolute;inset:0;opacity:.5;background-image:radial-gradient(circle at 20% 30%, rgba(0,0,0,.03) 0 1px, transparent 1px),radial-gradient(circle at 70% 65%, rgba(0,0,0,.025) 0 1px, transparent 1px);background-size:7px 7px, 9px 9px;}
.mast{position:absolute;left:70px;right:70px;top:74px;display:flex;justify-content:space-between;font-size:27px;letter-spacing:.16em;color:#14110d;font-weight:600;}
.rule{position:absolute;left:70px;right:70px;top:126px;height:3px;background:#14110d;transform-origin:left;}
.b{position:absolute;left:70px;right:70px;top:760px;font-size:210px;line-height:.88;font-weight:800;letter-spacing:-.05em;color:#14110d;will-change:transform,opacity;}
.u{position:absolute;left:74px;top:1090px;font-size:40px;color:#4a463c;font-weight:600;letter-spacing:.04em;will-change:transform,opacity;}
.u b{color:#14110d;}
.foot{position:absolute;left:74px;right:74px;bottom:70px;display:flex;justify-content:space-between;font-size:26px;letter-spacing:.12em;color:#14110d;font-weight:600;}
</style></head><body>
<div class="grain"></div>
<div class="mast mono"><span>CASBERI</span><span>REEL</span></div>
<div class="rule" id="rule"></div>
<div class="b" id="b">Casberi</div>
<div class="u mono" id="u"><b>casberi.app</b> · free on TestFlight</div>
<div class="foot mono"><span>casberi.app</span><span>—</span></div>
<script>
const clamp01=v=>Math.max(0,Math.min(1,v)),easeOut=p=>1-Math.pow(1-p,3),back=p=>{const c=1.7;return 1+(c+1)*Math.pow(p-1,3)+c*Math.pow(p-1,2);};
window.TOTAL=${TOTAL};
window.seek=function(t){
  document.getElementById('rule').style.transform='scaleX('+easeOut(clamp01(t/0.5))+')';
  const bin=clamp01((t-0.1)/0.55); const b=document.getElementById('b'); b.style.opacity=clamp01((t-0.05)/0.2); b.style.transform='translateY('+((1-back(bin))*80)+'px)';
  const uin=clamp01((t-0.4)/0.45); const u=document.getElementById('u'); u.style.opacity=easeOut(uin); u.style.transform='translateX('+((1-easeOut(uin))*-30)+'px)';
};
window.seek(0);
</script></body></html>`;
fs.writeFileSync(path.join(__dirname,'clip-reel-outro.html'),html);
console.log('wrote clip-reel-outro.html',(html.length/1024).toFixed(0)+'KB',TOTAL.toFixed(1)+'s');
