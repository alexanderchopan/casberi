"""The Casberi mark: one octopus arm curled into a lowercase c, and the app
icon: the same arm reaching in from off the tile and curling into a spiral
(prd §1708). The two are separate drawings: `outline()` is the mark,
`icon_arm()` the icon.

This is the geometry source for the mark, and `Design/CasberiMark.swift` is a
port of `outline()` below — same parameters, same order of operations. Change
one, change the other.

Writes, beside this file:
    casberi-mark.svg          the full cut (suckers), 100x100 unit space
    casberi-mark-small.svg    the clean cut (no suckers, blunter tip)
    casberi-wordmark-c.svg    the clean cut cropped to its own box, for the
                              wordmark, where it stands in for the c
and into the app's icon set, from `icon_arm()`:
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


# THE ICON (prd §1708, 2026-11-05). The mark's c read as a worm on the home
# screen (user: "it kinda looks like a worm"): an even, blunt body with a round
# end that reads as a head, spots for suckers, and two ends that just stop. The
# icon's arm is a cursive C whose exit stroke runs off the tile, the join into
# an "a" you never see (user: "i think of it like a cursive C ... connecting to
# cursive A for casberi but a is off the screen"). No end reads as a head: the
# thick end leaves the tile, the other narrows to a fine tip that spirals in.
# The suckers are rings that shrink toward the tip, one row on the inside of the
# curl (paired rows blurred to speckle at 60px). Same pink, same -9 deg lean,
# same ground.
#
# Centreline: a circle of radius 26 about (50, 50), walked from -62 deg through
# 308 deg; past 58% its radius shrinks by 17 (the spiral). The C ends at its
# foot, where the stroke already heads right, and runs on for RUNOFF units,
# easing toward RUNTO degrees, so the join leaves through the right side with no
# S-bend and no cut end inside the tile. The whole drawing is mirrored top to
# bottom (the tip curls at the top, the join leaves low right), leaned -9 deg
# and shown at 1.3x.
ICON = dict(R=26, A0=-62, SWEEP=308, CURL_FROM=0.58, CURL=17, CPOW=1.45, LEAD=4, GROW=0, RUNOFF=90, RUNTO=10,
            w0=19, w1=1.3, pw=0.9, zoom=1.3, ring=0.5,
            suckers=((0.04, 3.0), (0.14, 2.8), (0.24, 2.55), (0.34, 2.3), (0.44, 2.0),
                     (0.54, 1.75), (0.63, 1.45), (0.71, 1.15), (0.78, 0.9)))


def icon_arm(n=200):
    """The icon's arm: one contour (open at the lead-in, which leaves the
    tile) and its suckers (cx, cy, r) in 100x100 unit space, mirrored and
    leaned."""
    g = ICON
    pts, K, lead = [], 1200, g["LEAD"] / g["SWEEP"]
    for k in range(K + 1):
        u = -lead + (1 + lead) * k / K
        th = math.radians(g["A0"] - g["SWEEP"] * u)
        if u < 0:
            r = g["R"] + g["GROW"] * (-u / lead) ** 1.6
        elif u < g["CURL_FROM"]:
            r = g["R"]
        else:
            r = g["R"] - g["CURL"] * ((u - g["CURL_FROM"]) / (1 - g["CURL_FROM"])) ** g["CPOW"]
        pts.append((CX + r * math.cos(th), CY + r * math.sin(th), u))
    acc = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc.append(acc[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    c, j = [], 0
    for i in range(n + 1):
        s_ = acc[-1] * i / n
        while j < len(acc) - 2 and acc[j + 1] < s_:
            j += 1
        t = (s_ - acc[j]) / ((acc[j + 1] - acc[j]) or 1)
        a, b = pts[j], pts[j + 1]
        c.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    # The lead-in runs on past the tile for RUNOFF units, bending smoothly
    # from its own heading toward RUNTO degrees, so it leaves through the right
    # side and its cut end never shows (user: "should the arm run off the
    # screen tho? instead of having the flat edge").
    (x0, y0, u0), (x1, y1, _) = c[0], c[1]
    h0 = math.atan2(y0 - y1, x0 - x1)
    h1 = math.radians(g["RUNTO"])
    dh = (h1 - h0 + math.pi) % (2 * math.pi) - math.pi
    ext, x, y, step = [], x0, y0, g["RUNOFF"] / 24
    for k in range(1, 25):
        e = k / 24
        h = h0 + dh * (1 - (1 - e) ** 2)
        x, y = x + math.cos(h) * step, y + math.sin(h) * step
        ext.append((x, y, u0))
    c = list(reversed(ext)) + c
    n = len(c) - 1

    def width(i):
        return g["w0"] + (g["w1"] - g["w0"]) * max(0.0, c[i][2]) ** g["pw"]

    left, right, tang = [], [], []
    for i, p in enumerate(c):
        a, b = c[max(i - 1, 0)], c[min(i + 1, n)]
        vx, vy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(vx, vy) or 1
        vx, vy = vx / d, vy / d
        nx, ny = -vy, vx
        w = width(i) / 2
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
        tang.append((vx, vy, nx, ny))
    p, (vx, vy, nx, ny), w = c[n], tang[n], width(n) / 2
    tip = [(p[0] + (math.cos(math.pi * k / 16) * nx + math.sin(math.pi * k / 16) * vx) * w,
            p[1] + (math.cos(math.pi * k / 16) * ny + math.sin(math.pi * k / 16) * vy) * w) for k in range(1, 16)]
    contour = left + tip + list(reversed(right))

    holes = []
    for f, r in g["suckers"]:
        i = next((i for i in range(n) if c[i][2] <= f <= c[i + 1][2]), n)
        p, (vx, vy, nx, ny) = c[i], tang[i]
        s_ = 1 if (CX - p[0]) * nx + (CY - p[1]) * ny > 0 else -1
        off = width(i) * 0.24
        holes.append((p[0] + nx * s_ * off, p[1] + ny * s_ * off, r))

    def place(q):
        x, y = q[0], 100 - q[1]
        a = math.radians(LEAN)
        x, y = x - CX, y - CY
        return (CX + x * math.cos(a) - y * math.sin(a), CY + x * math.sin(a) + y * math.cos(a))

    return [place(q) for q in contour], [place(h) + (h[2],) for h in holes]


def icon_masks(size=1024, ss=4):
    """Coverage of the icon's arm on a square tile, as an 8-bit L image: the
    arm drawn at `zoom` about the tile's centre, its lead-in running off the
    right edge, each sucker a ring (the ground punched out, the ink's dot left
    in the middle)."""
    from PIL import Image, ImageDraw
    contour, holes = icon_arm()
    S = size * ss
    k = S / 100 * ICON["zoom"]
    o = S / 2 - 50 * k
    im = Image.new("L", (S, S), 0)
    dr = ImageDraw.Draw(im)
    dr.polygon([(o + x * k, o + y * k) for x, y in contour], fill=255)
    for x, y, r in holes:
        cx, cy, rr = o + x * k, o + y * k, r * k
        dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=0)
        q = rr * ICON["ring"]
        dr.ellipse([cx - q, cy - q, cx + q, cy + q], fill=255)
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
    # The app icon as an in-app image: the default face where you have not set
    # a photo (Library's tab, the tray's You row; prd §1708 item 6), so the app
    # wears its own icon, not the c.
    face = os.path.join(HERE, '..', '..', 'Casberi', 'Casberi', 'Assets.xcassets', 'casberi-app-icon.imageset')
    os.makedirs(face, exist_ok=True)
    Image.open(dark).convert("RGB").resize((256, 256), Image.LANCZOS).save(os.path.join(face, "icon.png"))
    with open(os.path.join(face, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    {\n      "filename" : "icon.png",\n      "idiom" : "universal"\n    }\n  ],\n'
                '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print("wrote the three SVGs, the three icons and the in-app icon")


if __name__ == "__main__":
    main()
