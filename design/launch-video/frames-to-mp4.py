# Assemble a frames dir (f0000.png …) into an H.264 mp4 via PyAV — the
# sandbox has no system ffmpeg CLI, but PyAV's bundled libav carries libx264
# (verified 2026-08-04). Flat UI content compresses beautifully at crf 20.
#
#   python3 frames-to-mp4.py <framesDir> <out.mp4> [fps]
#
# Two traps paid for (2026-08-04), both invisible in the tool's own output:
# a frame decoded from a PNG arrives wearing pict_type=I, and libx264 honors
# the force — 882 all-intra frames encoded to 150 MB with crf 20 "applied";
# and with no pts/time_base the mux invents 25fps, stretching a 30fps reel
# to 35s. Reset pict_type and stamp pts explicitly.
import av, sys, os
from fractions import Fraction

frames_dir, dst = sys.argv[1], sys.argv[2]
fps = int(sys.argv[3]) if len(sys.argv) > 3 else 30
names = sorted(f for f in os.listdir(frames_dir) if f.startswith('f') and f.endswith('.png'))
assert names, f'no frames in {frames_dir}'

first = av.open(os.path.join(frames_dir, names[0]))
w = first.streams.video[0].codec_context.width
h = first.streams.video[0].codec_context.height
first.close()

# options must ride add_stream — assigning stream.options after creation was
# silently ignored (measured 2026-08-04: a 29s reel encoded to 150 MB, ~40×
# what crf 20 produces for flat UI).
out = av.open(dst, 'w', options={'movflags': '+faststart'})
stream = out.add_stream('libx264', rate=fps,
                        options={'crf': '20', 'preset': 'medium', 'profile': 'high'})
stream.width, stream.height = w, h
stream.pix_fmt = 'yuv420p'
stream.codec_context.time_base = Fraction(1, fps)

for i, name in enumerate(names):
    img = av.open(os.path.join(frames_dir, name))
    for frame in img.decode(video=0):
        clean = frame.reformat(format='yuv420p')
        clean.pict_type = 0        # NONE — PNG decode stamps I; forced intra defeats crf
        clean.pts = i
        clean.time_base = Fraction(1, fps)
        for pkt in stream.encode(clean):
            out.mux(pkt)
    img.close()
    if (i + 1) % 150 == 0:
        print(f'{i + 1}/{len(names)}')
for pkt in stream.encode():
    out.mux(pkt)
out.close()
print(f'encoded {len(names)} frames -> {dst} ({os.path.getsize(dst) / 1e6:.1f} MB)')
