"""The Casberi mark: one octopus arm curled into a lowercase c.

This is the geometry source for the mark, and `Design/CasberiMark.swift` is a
port of `outline()` below — same parameters, same order of operations. Change
one, change the other.

Writes, beside this file:
    casberi-mark.svg          the full cut (suckers), 100x100 unit space
    casberi-mark-small.svg    the clean cut (no suckers, blunter tip)
    casberi-wordmark-c.svg    the clean cut cropped to its own box, for the
                              wordmark, where it stands in for the c
and into the app's icon set:
    casberi-octopus-1024-dark.png    pink on black
    casberi-octopus-1024-light.png   the same bytes: the black tile in the
                                     default appearance too (prd §1639)
    casberi-octopus-1024-tinted.png  white on black

    python3 design/app-icon/tentacle.py

Needs Pillow for the PNGs.
"""
import math, os

HERE = os.path.dirname(os.path.abspath(__file__))
ICONSET = os.path.join(HERE, '..', '..', 'Casberi', 'Casberi', 'Assets.xcassets', 'AppIcon.appiconset')
PINK = (0xFA, 0x2D, 0x48)

# The arm's centreline is a circle of radius 27 about (50, 50), opening to the
# right, walked from -48 deg through 282 deg; past 73% of the walk its radius
# shrinks by 9 so the tip turns in. The whole mark leans -9 deg about (50, 50),
# the angle the octopus's head leaned.
CX, CY, R, A0, SWEEP, CURL_FROM, CURL, CPOW = 50, 50, 27, -48, 282, 0.73, 9, 1.4
LEAN = -9
N = 80

FULL = dict(w0=17, w1=4, pw=0.9, suckers=((10, 3.0), (22, 2.7), (34, 2.4), (46, 2.0), (56, 1.7), (65, 1.3)))
CLEAN = dict(w0=18, w1=7, pw=1.0, suckers=())


def _centreline():
    pts = []
    K = 400
    for k in range(K + 1):
        u = k / K
        th = math.radians(A0 - SWEEP * u)
        r = R if u < CURL_FROM else R - CURL * ((u - CURL_FROM) / (1 - CURL_FROM)) ** CPOW
        pts.append((CX + r * math.cos(th), CY + r * math.sin(th)))
    # resample to N equal steps of arc length
    acc = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc.append(acc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    out, j = [], 0
    for i in range(N + 1):
        s = acc[-1] * i / N
        while j < len(acc) - 2 and acc[j + 1] < s:
            j += 1
        t = (s - acc[j]) / ((acc[j + 1] - acc[j]) or 1)
        a, b = pts[j], pts[j + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _lean(p):
    a = math.radians(LEAN)
    x, y = p[0] - CX, p[1] - CY
    return (CX + x * math.cos(a) - y * math.sin(a), CY + x * math.sin(a) + y * math.cos(a))


def outline(w0, w1, pw, suckers):
    """One closed contour with round caps at both ends, plus the sucker
    circles (cx, cy, r), all leaned."""
    c = _centreline()
    width = lambda i: w0 + (w1 - w0) * (i / N) ** pw
    left, right, tangent = [], [], []
    for i, p in enumerate(c):
        a, b = c[max(i - 1, 0)], c[min(i + 1, N)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        d = math.hypot(tx, ty) or 1
        tx, ty = tx / d, ty / d
        nx, ny = -ty, tx
        w = width(i) / 2
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
        tangent.append((tx, ty, nx, ny))

    def cap(i, forward):
        p, (tx, ty, nx, ny), w = c[i], tangent[i], width(i) / 2
        sgn = 1 if forward else -1
        pts = []
        for k in range(1, 12):
            phi = math.pi * k / 12
            # forward: left -> tip -> right; backward: right -> tail -> left
            ux = math.cos(phi) * nx * sgn + math.sin(phi) * tx * sgn
            uy = math.cos(phi) * ny * sgn + math.sin(phi) * ty * sgn
            pts.append((p[0] + ux * w, p[1] + uy * w))
        return pts

    contour = left + cap(N, True) + list(reversed(right)) + cap(0, False)
    holes = []
    for i, r in suckers:
        p = c[i]
        vx, vy = CX - p[0], CY - p[1]
        dv = math.hypot(vx, vy)
        off = width(i) * 0.26
        holes.append(_lean((p[0] + vx / dv * off, p[1] + vy / dv * off)) + (r,))
    return [_lean(p) for p in contour], holes


def _f(x):
    return f"{x:.2f}".rstrip("0").rstrip(".")


def svg(cut, ground="#000", ink="#FA2D48", box=(0, 0, 100, 100), size=1024):
    contour, holes = outline(**cut)
    d = "M" + " L".join(f"{_f(x)},{_f(y)}" for x, y in contour) + " Z"
    body = f'<path d="{d}" fill="{ink}"/>'
    body += "".join(f'<circle cx="{_f(x)}" cy="{_f(y)}" r="{r}" fill="{ground}"/>' for x, y, r in holes)
    bg = f'<rect x="{box[0]}" y="{box[1]}" width="{box[2]}" height="{box[3]}" fill="{ground}"/>' if ground else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
            f'viewBox="{" ".join(_f(v) for v in box)}">{bg}{body}</svg>\n')


def bbox(cut):
    contour, _ = outline(**cut)
    xs, ys = [p[0] for p in contour], [p[1] for p in contour]
    return min(xs), min(ys), max(xs), max(ys)


def icon_masks(size=1024, fill=0.6, ss=4):
    """Coverage of the full cut on a square icon, as an 8-bit L image: the
    arm's box is `fill` of the tile's width, centred on the box."""
    from PIL import Image, ImageDraw
    contour, holes = outline(**FULL)
    x0, y0, x1, y1 = bbox(FULL)
    S = size * ss
    k = S * fill / max(x1 - x0, y1 - y0)
    ox, oy = S / 2 - (x0 + x1) / 2 * k, S / 2 - (y0 + y1) / 2 * k
    im = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(im)
    dr.polygon([(ox + x * k, oy + y * k) for x, y in contour], fill=255)
    for x, y, r in holes:
        cx, cy, rr = ox + x * k, oy + y * k, r * k
        dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=0)
    return im.resize((size, size), Image.LANCZOS)


def main():
    open(os.path.join(HERE, "casberi-mark.svg"), "w").write(svg(FULL))
    open(os.path.join(HERE, "casberi-mark-small.svg"), "w").write(svg(CLEAN, size=29))
    x0, y0, x1, y1 = bbox(CLEAN)
    side = max(x1 - x0, y1 - y0)
    box = ((x0 + x1 - side) / 2, (y0 + y1 - side) / 2, side, side)
    open(os.path.join(HERE, "casberi-wordmark-c.svg"), "w").write(svg(CLEAN, ground=None, box=box, size=512))

    from PIL import Image
    a = icon_masks()
    black = Image.new("RGB", a.size, (0, 0, 0))
    dark = os.path.join(ICONSET, "casberi-octopus-1024-dark.png")
    Image.composite(Image.new("RGB", a.size, PINK), black, a).save(dark)
    with open(dark, "rb") as src, open(os.path.join(ICONSET, "casberi-octopus-1024-light.png"), "wb") as dst:
        dst.write(src.read())
    Image.composite(Image.new("RGB", a.size, (255, 255, 255)), black, a).save(
        os.path.join(ICONSET, "casberi-octopus-1024-tinted.png"))
    print("wrote the three SVGs and the three icons")


if __name__ == "__main__":
    main()
