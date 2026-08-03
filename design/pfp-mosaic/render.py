#!/usr/bin/env python3
"""Rebuild a picture out of the Casberi app-icon set.

Mirrors the JS in mosaic.html so a still can be produced without a browser.
Tiles come from tiles/png (the 53 catalog icons, SVGs pre-rasterized by qlmanage).
"""
import math, pathlib, sys
from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).parent
NAMES = dict(l.split('\t') for l in (HERE / 'tiles/names.tsv').read_text().strip().split('\n'))


def rgb2lab(r, g, b):
    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    r, g, b = [((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92
               for c in (r, g, b)]
    x = f((r * .4124 + g * .3576 + b * .1805) / .95047)
    y = f(r * .2126 + g * .7152 + b * .0722)
    z = f((r * .0193 + g * .1192 + b * .9505) / 1.08883)
    return (116 * y - 16, 500 * (x - y), 200 * (y - z))


def dE(a, b):
    # value is weighted over hue — a mosaic reads by lightness first
    dl, da, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return dl * dl * 2.4 + da * da + db * db


def palette(cell):
    out = []
    for f in sorted((HERE / 'tiles/png').glob('*.png')):
        im = Image.open(f).convert('RGBA')
        s = im.resize((24, 24), Image.LANCZOS)
        r = g = b = a = 0.0
        for px in s.getdata():
            al = px[3] / 255
            r += px[0] * al; g += px[1] * al; b += px[2] * al; a += al
        if a < 4:
            continue
        rgb = (r / a, g / a, b / a)
        out.append({
            'name': NAMES.get(f.stem, f.stem),
            'img': im.resize((cell, cell), Image.LANCZOS),
            'lab': rgb2lab(*rgb),
        })
    return out


def render(src_path, out_path, n=32, bed=0.70, scale=0.76, ink=0.85,
           mode='bed', size=1024, circle=True):
    cell = size // n
    size = cell * n
    tiles = palette(int(cell * scale))

    sub = Image.open(src_path).convert('RGB')
    s = min(sub.size)
    sub = sub.crop(((sub.width - s) // 2, (sub.height - s) // 2,
                    (sub.width - s) // 2 + s, (sub.height - s) // 2 + s))
    small = sub.resize((n, n), Image.BOX)
    px = small.load()

    canvas = Image.new('RGBA', (size, size), (10, 12, 16, 255))
    chosen = {}
    used = {}

    for y in range(n):
        for x in range(n):
            c = px[x, y]
            lab = rgb2lab(*c)
            left, up = chosen.get((x - 1, y)), chosen.get((x, y - 1))
            best, bestd = 0, math.inf
            for i, t in enumerate(tiles):
                d = dE(lab, t['lab'])
                if i == left or i == up:
                    d *= 1.55
                if d < bestd:
                    bestd, best = d, i
            chosen[(x, y)] = best
            used[tiles[best]['name']] = used.get(tiles[best]['name'], 0) + 1
            t = tiles[best]

            x0, y0 = x * cell, y * cell
            if mode != 'pure':
                canvas.paste(Image.new('RGBA', (cell, cell),
                                       (*c, int(bed * 255))), (x0, y0),
                             Image.new('L', (cell, cell), int(bed * 255)))

            icon = t['img']
            if mode == 'tint':
                wash = Image.new('RGBA', icon.size, (*c, 158))
                icon = Image.alpha_composite(icon, Image.composite(
                    wash, Image.new('RGBA', icon.size, (0, 0, 0, 0)), icon.split()[3]))
            if ink < 1:
                a = icon.split()[3].point(lambda v: int(v * ink))
                icon = icon.copy(); icon.putalpha(a)
            off = (cell - icon.width) // 2
            canvas.alpha_composite(icon, (x0 + off, y0 + off))

    if circle:
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        cut = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        cut.paste(canvas, (0, 0), mask)
        canvas = cut

    canvas.save(out_path)
    top = sorted(used.items(), key=lambda kv: -kv[1])[:6]
    print(f"{out_path}  {n}x{n}  {len(used)} apps used  top: " +
          ", ".join(f"{k} {v}" for k, v in top))


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else str(HERE / 'subject.png')
    render(src, HERE / 'out-bed.png', mode='bed')
    render(src, HERE / 'out-pure.png', mode='pure', n=40, ink=1.0, scale=0.92)
    render(src, HERE / 'out-tint.png', mode='tint', bed=0.35, ink=1.0, scale=0.9)
