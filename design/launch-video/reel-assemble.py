import subprocess, os
os.chdir('/Users/alexanderchopan/Developer/casberi/design/launch-video')
segs=[f'reel/{n:02d}.mp4' for n in range(11)]
T=0.32   # crossfade duration
def dur(f):
    out=subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',f]).decode().strip()
    return float(out)
D=[dur(s) for s in segs]
inputs=[]
for s in segs: inputs+=['-i',s]
# build xfade chain
filt=[]
prev='0:v'
offset=0.0
for i in range(1,len(segs)):
    offset+=D[i-1]-T
    out=f'v{i}'
    trans='fade'
    filt.append(f'[{prev}][{i}:v]xfade=transition={trans}:duration={T}:offset={offset:.3f}[{out}]')
    prev=out
filt_str=';'.join(filt)
total=sum(D)-T*(len(segs)-1)
cmd=['ffmpeg','-y']+inputs+['-filter_complex',filt_str,'-map',f'[{prev}]',
     '-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-preset','slow','-movflags','+faststart','casberi-reel.mp4']
print('segments:',[f'{d:.2f}' for d in D])
print('total ~%.1fs'%total)
r=subprocess.run(cmd,capture_output=True,text=True)
print('done' if r.returncode==0 else r.stderr[-800:])
