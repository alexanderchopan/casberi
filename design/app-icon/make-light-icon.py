#!/usr/bin/env python3
"""Derive the LIGHT app-icon variant from the shipped DARK art.

The mark is one ink (#FF2D87) over a plain ground; the eyes and suckers are
knocked OUT of the mark, so they are the ground rather than a painted colour
(design/app-icon/README.md). The light variant is therefore not a re-drawing:
it is the same coverage mask composited over white instead of black, which
turns the eyes and suckers white for free.

Reading the shipped dark PNG is deliberate. The berry-era generator was deleted
because it emitted art the app had stopped shipping; this script cannot drift
that way, because its input IS the shipped art.

    python3 design/app-icon/make-light-icon.py            # write the light PNG
    python3 design/app-icon/make-light-icon.py --self-test # prove the transform

Dependencies: none (pure stdlib PNG read/write).
"""
import os, sys, zlib, struct

MARK = (255, 45, 135)       # #FF2D87
DARK_GROUND = (0, 0, 0)     # #000000
LIGHT_GROUND = (255, 255, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(HERE, '..', '..', 'Casberi', 'Casberi',
                       'Assets.xcassets', 'AppIcon.appiconset')
SRC = os.path.join(ICONSET, 'casberi-octopus-1024-dark.png')
DST = os.path.join(ICONSET, 'casberi-octopus-1024-light.png')


def read_png(path):
    f = open(path, 'rb').read()
    if f[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('not a png: %s' % path)
    i, idat = 8, b''
    w = h = ct = None
    while i < len(f):
        n = struct.unpack('>I', f[i:i+4])[0]
        tag, data = f[i+4:i+8], f[i+8:i+8+n]
        if tag == b'IHDR':
            w, h, bd, ct, comp, filt, inter = struct.unpack('>IIBBBBB', data)
            if (bd, comp, filt, inter) != (8, 0, 0, 0):
                raise ValueError('unsupported png encoding in %s' % path)
            if ct != 2:
                raise ValueError('expected truecolour rgb, got colour type %d' % ct)
        elif tag == b'IDAT':
            idat += data
        i += 12 + n
    raw = zlib.decompress(idat)
    stride = w * 3
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ft = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos+stride]); pos += stride
        if ft == 1:
            for x in range(3, stride):
                line[x] = (line[x] + line[x-3]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x-3] if x >= 3 else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x-3] if x >= 3 else 0
                b = prev[x]
                c = prev[x-3] if x >= 3 else 0
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        elif ft != 0:
            raise ValueError('bad filter type %d' % ft)
        out[y*stride:(y+1)*stride] = line
        prev = line
    return w, h, out


def write_png(path, w, h, data):
    stride = w * 3
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += data[y*stride:(y+1)*stride]

    def chunk(tag, d):
        return (struct.pack('>I', len(d)) + tag + d
                + struct.pack('>I', zlib.crc32(tag + d) & 0xffffffff))

    blob = b'\x89PNG\r\n\x1a\n'
    blob += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    blob += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    blob += chunk(b'IEND', b'')
    open(path, 'wb').write(blob)


# Least-squares projection of the pixel onto the mark-over-black ramp. Using all
# three channels rather than red alone keeps the 8-bit quantisation noise down.
_DENOM = float(sum(c*c for c in MARK))


def coverage(px):
    """Recover the mark's alpha at a pixel of the dark art."""
    a = sum(p*m for p, m in zip(px, MARK)) / _DENOM
    return 0.0 if a < 0.0 else (1.0 if a > 1.0 else a)


def over(a, ground):
    """Composite the mark at coverage `a` over `ground`."""
    return tuple(int(round(a*m + (1.0-a)*g)) for m, g in zip(MARK, ground))


def convert(w, h, src):
    dst = bytearray(len(src))
    cache = {}
    for i in range(0, len(src), 3):
        key = bytes(src[i:i+3])
        val = cache.get(key)
        if val is None:
            val = bytes(over(coverage(key), LIGHT_GROUND))
            cache[key] = val
        dst[i:i+3] = val
    return dst


def self_test():
    fails = []

    def check(name, cond, detail=''):
        if not cond:
            fails.append('%s %s' % (name, detail))

    # The ground inverts and the mark survives it.
    check('ground', over(0.0, LIGHT_GROUND) == LIGHT_GROUND,
          'a=0 gave %r' % (over(0.0, LIGHT_GROUND),))
    check('mark', over(1.0, LIGHT_GROUND) == MARK,
          'a=1 gave %r' % (over(1.0, LIGHT_GROUND),))
    # Coverage round-trips through the dark ramp it was measured on.
    for step in range(0, 101):
        a = step / 100.0
        px = over(a, DARK_GROUND)
        back = coverage(px)
        check('roundtrip', abs(back - a) <= 0.006,
              'a=%.2f -> %r -> %.4f' % (a, px, back))
    # A knocked-out eye is ground, so it must land on the LIGHT ground, not black.
    check('knockout', over(coverage(DARK_GROUND), LIGHT_GROUND) == LIGHT_GROUND)
    # The transform must actually change the art: a no-op would "pass" silently.
    check('not-identity', over(0.5, LIGHT_GROUND) != over(0.5, DARK_GROUND))
    # Monotone: more mark coverage never gets lighter.
    prev = 256
    for step in range(0, 101):
        g = over(step/100.0, LIGHT_GROUND)[1]
        check('monotone', g <= prev, 'at a=%.2f' % (step/100.0))
        prev = g

    if fails:
        print('SELF-TEST FAILED (%d)' % len(fails))
        for f in fails[:10]:
            print('  ', f)
        return 1
    print('self-test ok: ground inverts, mark holds, coverage round-trips, knockout lands on white')
    return 0


def main():
    if '--self-test' in sys.argv:
        return self_test()
    w, h, src = read_png(SRC)
    dst = convert(w, h, src)
    write_png(DST, w, h, dst)
    print('wrote %s (%dx%d) from %s' % (os.path.relpath(DST), w, h, os.path.basename(SRC)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
