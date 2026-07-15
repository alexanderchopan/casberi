import av, sys
src, dst = sys.argv[1], sys.argv[2]
inp = av.open(src)
istream = inp.streams.video[0]
out = av.open(dst, 'w')
# H.264, yuv420p, ~high quality for flat UI content
try:
    ostream = out.add_stream('libx264', rate=25)
    ostream.options = {'crf': '20', 'preset': 'slow', 'profile': 'high', 'movflags': '+faststart'}
except Exception as e:
    print('libx264 unavailable, falling back to mpeg4:', e)
    ostream = out.add_stream('mpeg4', rate=25)
    ostream.options = {'qscale': '3'}
ostream.width = istream.codec_context.width
ostream.height = istream.codec_context.height
ostream.pix_fmt = 'yuv420p'
n=0
for frame in inp.decode(istream):
    for pkt in ostream.encode(frame):
        out.mux(pkt); n+=1
for pkt in ostream.encode():
    out.mux(pkt)
out.close(); inp.close()
print('encoded frames:', n, '->', dst)
