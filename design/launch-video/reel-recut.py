import subprocess, os
os.chdir('/Users/alexanderchopan/Developer/casberi/design/launch-video')
WORK='reel2'; os.makedirs(WORK, exist_ok=True)

def sh(cmd):
    r=subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode!=0: print('ERR:', ' '.join(cmd)[:90], '\n', r.stderr[-500:])
    return r.returncode==0

# uniform slice params so xfade accepts every input
VF='scale=1080:1920,setsar=1,fps=30,format=yuv420p'
def enc(inp, out, ss=None, t=None):
    cmd=['ffmpeg','-y','-v','error']
    if ss is not None: cmd+=['-ss',f'{ss}']
    cmd+=['-i',inp]
    if t is not None: cmd+=['-t',f'{t}']
    cmd+=['-an','-vf',VF,'-c:v','libx264','-crf','18','-preset','fast',out]
    return sh(cmd)

# 1) intro + outro cards, rendered fresh
def card(build, html, out):
    sh(['node', build])
    sh(['node','render.js', html, '--size=1080x1920'])
    sh(['ffmpeg','-y','-v','error','-framerate','30','-i','frames/f%04d.png',
        '-vf',VF,'-c:v','libx264','-crf','18','-preset','fast',out])
card('build-reel-intro.js','clip-reel-intro.html', f'{WORK}/intro.mp4')
card('build-reel-outro.js','clip-reel-outro.html', f'{WORK}/outro.mp4')

# 2) hero beat per clip. beat->start: 0->0.85 1->2.85 2->4.85 3->6.85 4->8.85
B={0:0.85,1:2.85,2:4.85,3:6.85,4:8.85}
SLICE=1.2
# narrative order: daily -> social -> markets -> crypto/agent/trust -> privacy close
ORDER=[
 ('home',4),('ask',1),('screenshots',2),('farcaster',3),('spotify',2),
 ('bitrefill',3),('github',2),('tokens',2),('markets',2),('bankr',1),
 ('wallet',0),('basenames',1),('solana',3),('peer',3),('revoke',2),
 ('smartaccounts',0),('1claw',1),('privacy',1),
]
segs=[f'{WORK}/intro.mp4']
for i,(name,beat) in enumerate(ORDER):
    src=f'casberi-{name}-live.mp4'
    out=f'{WORK}/s{i:02d}-{name}.mp4'
    if not os.path.exists(src): print('MISSING', src); continue
    enc(src, out, ss=B[beat], t=SLICE)
    segs.append(out)
segs.append(f'{WORK}/outro.mp4')

# 3) xfade chain
def dur(f):
    return float(subprocess.check_output(['ffprobe','-v','error','-show_entries',
        'format=duration','-of','default=noprint_wrappers=1:nokey=1',f]).decode().strip())
D=[dur(s) for s in segs]
T=0.28
inputs=[]
for s in segs: inputs+=['-i',s]
filt=[]; prev='0:v'; off=0.0
for i in range(1,len(segs)):
    off+=D[i-1]-T
    filt.append(f'[{prev}][{i}:v]xfade=transition=fade:duration={T}:offset={off:.3f}[v{i}]')
    prev=f'v{i}'
total=sum(D)-T*(len(segs)-1)
cmd=['ffmpeg','-y','-v','error']+inputs+['-filter_complex',';'.join(filt),
     '-map',f'[{prev}]','-c:v','libx264','-pix_fmt','yuv420p','-crf','18',
     '-preset','slow','-movflags','+faststart','casberi-reel.mp4']
print(f'segments: {len(segs)} (intro + {len(ORDER)} features + outro)')
print(f'total ~{total:.1f}s')
print('done' if sh(cmd) else 'FAILED')
