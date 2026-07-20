import glob, os, sys
os.chdir('/Users/alexanderchopan/Developer/casberi/design/launch-video')

# transforms: (find, replace, label)
T = [
  # 1. DATA kick: drop the "0N · " prefix -> just the section word
  ("kick:(i+1<10?'0':'')+(i+1)+' · '+b.kick", "kick:b.kick", "data-kick"),
  # 2. giant watermark: number -> section word, auto-sized to fit
  ("wm.textContent=(active+1<10?'0':'')+(active+1);",
   "wm.textContent=D[active].kick;wm.style.fontSize=Math.max(90,Math.min(320,900/(0.6*D[active].kick.length)))+'px';",
   "wm-word"),
  # 3. drop the footer counter (JS updater)
  ("document.getElementById('pg').textContent=(active+1<10?'0':'')+(active+1)+' / 0'+N;", "", "pg-js"),
  # 4. footer span: counter -> em dash (matches intro/outro cards)
  ('<span id="pg">01 / 05</span>', '<span>—</span>', "pg-html"),
  # 5. watermark CSS: allow a word (nowrap, right-aligned); JS sets per-beat size
  ("right:20px;top:150px;font-size:560px;line-height:.8;",
   "right:20px;top:150px;font-size:280px;line-height:.82;white-space:nowrap;text-align:right;",
   "wm-css"),
]

files = [f for f in glob.glob('build-*-live.js') if 'home' not in f]  # home clip is retired
only = sys.argv[1:] if len(sys.argv) > 1 else None
for f in sorted(files):
    if only and f not in only: continue
    s = open(f).read(); applied = []
    for find, repl, label in T:
        n = s.count(find)
        if n: s = s.replace(find, repl); applied.append(f"{label}×{n}")
        else: applied.append(f"{label}:MISS")
    open(f, 'w').write(s)
    print(f"{f:32} {'  '.join(applied)}")
