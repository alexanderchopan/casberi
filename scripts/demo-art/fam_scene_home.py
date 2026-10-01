"""fam_scene_home — drawn "photographs" of food, rooms, objects and craft.

Every picture is one SVG built from the small motif helpers below, one
composition function per key. They stand in for photographs, so they carry no
words — except the one a subject asks for (a gym timer reading 0:07).

Distinctness is the point of the whole table: the climbing subjects (six of
them), the coffee, the ceramics, the pastry, the houseplants and the
windowsills each take a different viewpoint, surface, palette and time of
day. The notes on each function say which one, so a later edit does not drift
two of them together.
"""

import math
import random

# ── numbers and colours ───────────────────────────────────────────────────


def n(v):
    if isinstance(v, int):
        return str(v)
    s = f"{v:.1f}"
    return s[:-2] if s.endswith(".0") else s


def _hex(c):
    c = c.lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """Blend colour a toward b by t (0..1)."""
    ra, ga, ba = _hex(a)
    rb, gb, bb = _hex(b)
    return "#%02x%02x%02x" % (round(ra + (rb - ra) * t), round(ga + (gb - ga) * t),
                              round(ba + (bb - ba) * t))


def dk(c, t):
    return mix(c, "#000000", t)


def lt(c, t):
    return mix(c, "#ffffff", t)


# ── SVG primitives ────────────────────────────────────────────────────────


def _attrs(kw):
    out = []
    for k, v in kw.items():
        if v is None:
            continue
        k = k.rstrip("_").replace("_", "-")
        out.append(f'{k}="{n(v) if isinstance(v, (int, float)) else v}"')
    return " ".join(out)


def R(x, y, w, h, fill, rx=0, **kw):
    return f'<rect x="{n(x)}" y="{n(y)}" width="{n(w)}" height="{n(h)}" rx="{n(rx)}" fill="{fill}" {_attrs(kw)}/>'


def E(cx, cy, rx, ry, fill, **kw):
    return f'<ellipse cx="{n(cx)}" cy="{n(cy)}" rx="{n(rx)}" ry="{n(ry)}" fill="{fill}" {_attrs(kw)}/>'


def C(cx, cy, r, fill, **kw):
    return f'<circle cx="{n(cx)}" cy="{n(cy)}" r="{n(r)}" fill="{fill}" {_attrs(kw)}/>'


def P(d, fill, **kw):
    return f'<path d="{d}" fill="{fill}" {_attrs(kw)}/>'


def PL(pts, fill, **kw):
    s = " ".join(f"{n(x)},{n(y)}" for x, y in pts)
    return f'<polygon points="{s}" fill="{fill}" {_attrs(kw)}/>'


def PLN(pts, stroke, w=1, **kw):
    s = " ".join(f"{n(x)},{n(y)}" for x, y in pts)
    return f'<polyline points="{s}" fill="none" stroke="{stroke}" stroke-width="{n(w)}" {_attrs(kw)}/>'


def L(x1, y1, x2, y2, stroke, w=1, **kw):
    return (f'<line x1="{n(x1)}" y1="{n(y1)}" x2="{n(x2)}" y2="{n(y2)}" stroke="{stroke}" '
            f'stroke-width="{n(w)}" {_attrs(kw)}/>')


def G(*items, **kw):
    return f'<g {_attrs(kw)}>' + "".join(items) + "</g>"


def T(x, y, text, **kw):
    return f'<text x="{n(x)}" y="{n(y)}" {_attrs(kw)}>{text}</text>'


def tf(x=0, y=0, s=1, sy=None, rot=0):
    out = f"translate({n(x)} {n(y)})"
    if rot:
        out += f" rotate({n(rot)})"
    if s != 1 or (sy is not None and sy != s):
        out += f" scale({n(s)} {n(sy if sy is not None else s)})"
    return out


def quadpt(q, u, v):
    """Bilinear point on a quad (tl, tr, br, bl) — lays grids on a surface in perspective."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = q
    tx, ty = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
    bx, by = x3 + (x2 - x3) * u, y3 + (y2 - y3) * u
    return tx + (bx - tx) * v, ty + (by - ty) * v


def subquad(q, u0, v0, u1, v1):
    return [quadpt(q, u0, v0), quadpt(q, u1, v0), quadpt(q, u1, v1), quadpt(q, u0, v1)]


# ── the canvas ────────────────────────────────────────────────────────────


class Pic:
    def __init__(self, w, h, bg="#000"):
        self.w, self.h, self.bg = w, h, bg
        self.defs, self.body, self._n, self._blur = [], [], 0, {}

    def _id(self, p):
        self._n += 1
        return f"{p}{self._n}"

    @staticmethod
    def _stops(stops):
        out = []
        k = len(stops)
        for i, s in enumerate(stops):
            if isinstance(s, str):
                s = (i / max(1, k - 1), s)
            off, col = s[0], s[1]
            op = s[2] if len(s) > 2 else 1
            out.append(f'<stop offset="{off:.3f}" stop-color="{col}" stop-opacity="{op}"/>')
        return "".join(out)

    def lg(self, *stops, x1=0, y1=0, x2=0, y2=1, user=False):
        i = self._id("g")
        u = ' gradientUnits="userSpaceOnUse"' if user else ""
        self.defs.append(f'<linearGradient id="{i}" x1="{n(x1)}" y1="{n(y1)}" x2="{n(x2)}" '
                         f'y2="{n(y2)}"{u}>{self._stops(stops)}</linearGradient>')
        return f"url(#{i})"

    def rg(self, *stops, cx=.5, cy=.5, r=.5, fx=None, fy=None, user=False, tr=None):
        i = self._id("r")
        u = ' gradientUnits="userSpaceOnUse"' if user else ""
        f = ""
        if fx is not None:
            f = f' fx="{n(fx)}" fy="{n(fy)}"'
        t = f' gradientTransform="{tr}"' if tr else ""
        self.defs.append(f'<radialGradient id="{i}" cx="{n(cx)}" cy="{n(cy)}" r="{n(r)}"{f}{u}{t}>'
                         f'{self._stops(stops)}</radialGradient>')
        return f"url(#{i})"

    def blur(self, sd):
        if sd not in self._blur:
            i = self._id("b")
            self.defs.append(f'<filter id="{i}" filterUnits="userSpaceOnUse" x="-{self.w}" y="-{self.h}" '
                             f'width="{3 * self.w}" height="{3 * self.h}"><feGaussianBlur stdDeviation="{sd}"/></filter>')
            self._blur[sd] = f"url(#{i})"
        return self._blur[sd]

    def clip(self, *shapes):
        i = self._id("c")
        self.defs.append(f'<clipPath id="{i}">' + "".join(shapes) + "</clipPath>")
        return f"url(#{i})"

    def soft(self, item, sd, op=1.0, blend=None):
        st = f"mix-blend-mode:{blend}" if blend else None
        return G(item, filter=self.blur(sd), opacity=op, style=st)

    def add(self, *items):
        self.body.extend(items)

    def html(self):
        w, h = self.w, self.h
        return ("<!doctype html><html><head><meta charset='utf-8'><style>"
                f"html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:{self.bg}}}"
                "svg{display:block}</style></head><body>"
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                f"<defs>{''.join(self.defs)}</defs>{''.join(self.body)}</svg></body></html>")


# ── shared motifs ─────────────────────────────────────────────────────────


def chrome(p, tint="#8a8f96", horizontal=True, glint="#ffffff"):
    """A polished-metal gradient across a cylinder: dark edges, a bright band, a reflected floor."""
    a = dict(x1=0, y1=0, x2=1, y2=0) if horizontal else dict(x1=0, y1=0, x2=0, y2=1)
    return p.lg((0, dk(tint, .55)), (.12, dk(tint, .1)), (.28, lt(tint, .75)), (.36, glint),
                (.46, lt(tint, .3)), (.7, dk(tint, .25)), (.86, lt(tint, .35)), (1, dk(tint, .5)), **a)


def steam(p, x, y, h, col="#ffffff", op=.35, sway=14, wide=10, k=3, seed=1):
    rnd = random.Random(seed)
    out = []
    for i in range(k):
        dx = (i - (k - 1) / 2) * wide
        s = sway * (1 if i % 2 else -1) * rnd.uniform(.6, 1.2)
        d = (f"M{n(x + dx)},{n(y)} C{n(x + dx + s)},{n(y - h * .3)} {n(x + dx - s)},{n(y - h * .6)} "
             f"{n(x + dx + s * .5)},{n(y - h)}")
        out.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{n(wide * .9)}" '
                   f'stroke-linecap="round" opacity="{op}"/>')
    return p.soft("".join(out), 5)


def cup_side(p, cx, base_y, w, h, body, liquid=None, rim_light="#ffffff", handle="right",
             saucer=None, persp=.18, inner=None):
    """An eye-level cup: tapered body, rim ellipse, optional liquid surface, handle, saucer."""
    top_w, bot_w = w / 2, w / 2 * .72
    ty = base_y - h
    ry = top_w * persp
    out = []
    if saucer:
        sw = w * .95
        out.append(E(cx, base_y + 2, sw, sw * persp * 1.1, dk(saucer, .25)))
        out.append(E(cx, base_y - 2, sw, sw * persp * 1.0, p.lg(lt(saucer, .3), saucer, dk(saucer, .1))))
        out.append(E(cx, base_y - 2, sw * .55, sw * .55 * persp, dk(saucer, .08)))
    hx = cx + top_w * .92 if handle == "right" else cx - top_w * .92
    sgn = 1 if handle == "right" else -1
    if handle:
        hd = (f"M{n(hx)},{n(ty + h * .22)} C{n(hx + sgn * w * .36)},{n(ty + h * .18)} "
              f"{n(hx + sgn * w * .34)},{n(ty + h * .74)} {n(hx - sgn * w * .06)},{n(ty + h * .72)}")
        out.append(f'<path d="{hd}" fill="none" stroke="{dk(body, .12)}" stroke-width="{n(w * .085)}" stroke-linecap="round"/>')
    d = (f"M{n(cx - top_w)},{n(ty)} C{n(cx - top_w)},{n(ty + h * .75)} {n(cx - bot_w)},{n(base_y)} {n(cx)},{n(base_y)} "
         f"C{n(cx + bot_w)},{n(base_y)} {n(cx + top_w)},{n(ty + h * .75)} {n(cx + top_w)},{n(ty)} Z")
    out.append(P(d, p.lg((0, dk(body, .28)), (.3, lt(body, .12)), (.55, body), (1, dk(body, .35)), x1=0, y1=0, x2=1, y2=0)))
    out.append(E(cx, ty, top_w, ry, dk(body, .2)))
    out.append(E(cx, ty + 1, top_w * .93, ry * .9, inner or dk(body, .05)))
    if liquid:
        out.append(E(cx, ty + ry * .45, top_w * .86, ry * .72, liquid))
    out.append(E(cx, ty, top_w, ry, "none", stroke=rim_light, stroke_width=1.6, opacity=.7))
    return "".join(out)


def window_panes(x, y, w, h, frame, bar, cols=2, rows=2):
    """Mullions and a frame drawn over an existing view."""
    out = [R(x - bar, y - bar, w + 2 * bar, bar, frame), R(x - bar, y + h, w + 2 * bar, bar, frame),
           R(x - bar, y, bar, h, frame), R(x + w, y, bar, h, frame)]
    for i in range(1, cols):
        out.append(R(x + w * i / cols - bar * .35, y, bar * .7, h, frame))
    for j in range(1, rows):
        out.append(R(x, y + h * j / rows - bar * .35, w, bar * .7, frame))
    return "".join(out)


def grain(p, x, y, w, h, col, k=14, op=.18, seed=3, vertical=False, wav=6):
    """Sparse, smooth wood grain: a few long wavy strokes (cheap for JPEG)."""
    rnd = random.Random(seed)
    out = []
    for _ in range(k):
        if vertical:
            gx = x + rnd.uniform(0, w)
            s = rnd.uniform(-wav, wav)
            d = f"M{n(gx)},{n(y)} C{n(gx + s)},{n(y + h * .33)} {n(gx - s)},{n(y + h * .66)} {n(gx + s * .4)},{n(y + h)}"
        else:
            gy = y + rnd.uniform(0, h)
            s = rnd.uniform(-wav, wav)
            d = f"M{n(x)},{n(gy)} C{n(x + w * .33)},{n(gy + s)} {n(x + w * .66)},{n(gy - s)} {n(x + w)},{n(gy + s * .4)}"
        out.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{n(rnd.uniform(.8, 2.4))}" opacity="{n(rnd.uniform(op * .5, op))}"/>')
    return "".join(out)


def bokeh(p, pts, sd=0):
    out = []
    for (x, y, r, col, op) in pts:
        out.append(C(x, y, r, col, opacity=op))
    g = "".join(out)
    return p.soft(g, sd) if sd else g


def leaf(cx, cy, length, width, angle, fill, vein=None):
    d = (f"M0,0 C{n(width)},{n(-length * .25)} {n(width * .8)},{n(-length * .8)} 0,{n(-length)} "
         f"C{n(-width * .8)},{n(-length * .8)} {n(-width)},{n(-length * .25)} 0,0 Z")
    v = f'<path d="M0,0 L0,{n(-length * .9)}" stroke="{vein}" stroke-width="1.2" fill="none" opacity=".6"/>' if vein else ""
    return f'<g transform="translate({n(cx)} {n(cy)}) rotate({n(angle)})"><path d="{d}" fill="{fill}"/>{v}</g>'


# ── coffee (three subjects, three set-ups) ────────────────────────────────


def x_photo_1(p):
    """Morning: a white cup on a stone ledge, backlit; the city a peach-and-blue blur outside."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#f7cfa9", "#f3dcc5", "#b9cbe0")))
    p.add(p.soft(C(250, 150, 120, "#fff4d8", opacity=.9), 40))
    city = []
    rnd = random.Random(21)
    x = -20
    while x < w:
        bw = rnd.uniform(50, 120)
        bh = rnd.uniform(130, 300)
        city.append(R(x, 420 - bh, bw, bh + 20, rnd.choice(["#9fb0c9", "#aebbd0", "#8ea2c0", "#b6c0d4"]), opacity=.85))
        x += bw + rnd.uniform(-10, 10)
    p.add(p.soft("".join(city), 7))
    glints = [(rnd.uniform(0, w), rnd.uniform(180, 400), rnd.uniform(6, 16), "#ffe7c2", rnd.uniform(.35, .7)) for _ in range(14)]
    p.add(bokeh(p, glints, 3))
    # window frame edges
    p.add(R(0, 0, 26, 440, "#f7f3ee"))
    p.add(R(0, 0, w, 18, "#f7f3ee"))
    p.add(R(420, 0, 14, 440, "#f7f3ee"))
    p.add(R(0, 430, w, 14, "#e9e1d6"))
    # ledge
    p.add(R(0, 440, w, 160, p.lg("#efe6da", "#d9ccbc")))
    p.add(p.soft(PL([(300, 450), (700, 450), (800, 600), (240, 600)], "#fff1d6", opacity=.6), 10))
    # cup (backlit, shadow toward the viewer)
    cx = 590
    p.add(p.soft(PL([(cx - 60, 520), (cx + 60, 520), (cx + 110, 600), (cx - 20, 600)], "#8a735b"), 12, .4))
    p.add(cup_side(p, cx, 520, 150, 112, "#fbf7f1", liquid=p.rg("#8a5a36", "#5a3620"), rim_light="#fff1c9", persp=.2))
    p.add(p.soft(R(cx + 58, 420, 8, 90, "#fff1c9", opacity=.8), 3))
    p.add(steam(p, cx, 390, 150, col="#fff4dc", op=.55, wide=10, seed=8))


def nostr_2b(p):
    """Blue hour and rain: a mustard mug and a tented paperback on a green-painted sill, lamp-lit."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#1d2e4f", "#2f4a73", "#476891")))
    lights = [(x, y, r, c, o) for (x, y, r, c, o) in
              [(120, 330, 10, "#ffcf7a", .6), (180, 300, 7, "#ffcf7a", .5), (600, 280, 9, "#ffd899", .55),
               (660, 320, 12, "#ffb865", .5), (380, 360, 6, "#fff0c2", .5), (720, 250, 6, "#ffcf7a", .4),
               (260, 360, 14, "#ff9d5c", .35), (520, 350, 8, "#ffe2a3", .45)]]
    p.add(p.soft(R(0, 300, w, 120, "#16223a", opacity=.8), 10))
    p.add(bokeh(p, lights, 4))
    rnd = random.Random(31)
    rain = []
    for _ in range(46):
        x = rnd.uniform(0, w)
        y = rnd.uniform(0, 380)
        ln = rnd.uniform(14, 40)
        rain.append(L(x, y, x - ln * .12, y + ln, "#cfe0ff", 1.2, opacity=rnd.uniform(.15, .4)))
    p.add("".join(rain))
    for _ in range(18):
        p.add(C(rnd.uniform(0, w), rnd.uniform(0, 380), rnd.uniform(2, 4.5), "#dfeaff", opacity=.28))
    p.add(window_panes(0, 0, w, 400, "#243a2f", 22, cols=2, rows=1))
    # sill
    p.add(PL([(0, 400), (w, 400), (w, 470), (0, 470)], p.lg("#3f5e4b", "#2e4838")))
    p.add(R(0, 470, w, 130, p.lg("#2b4435", "#1c2e24")))
    p.add(p.soft(E(140, 460, 360, 90, "#ffb76b", opacity=.35), 40))
    # paperback tented
    bx, by = 250, 440
    p.add(p.soft(PL([(bx - 150, by + 8), (bx + 150, by + 8), (bx + 170, by + 22), (bx - 140, by + 24)], "#0c150f"), 6, .6))
    p.add(PL([(bx - 150, by + 10), (bx - 4, by - 70), (bx + 4, by - 70), (bx + 150, by + 10)], "#efe3c8"))
    p.add(PL([(bx - 156, by + 6), (bx, by - 80), (bx, by - 66), (bx - 144, by + 12)], p.lg("#c85a3a", "#8e3524", x2=1, y2=0)))
    p.add(PL([(bx + 156, by + 6), (bx, by - 80), (bx, by - 66), (bx + 144, by + 12)], p.lg("#7a2c1e", "#5a1f15", x2=1, y2=0)))
    p.add(PL([(bx - 110, by - 14), (bx - 50, by - 48), (bx - 44, by - 40), (bx - 104, by - 6)], "#f2c46b", opacity=.8))
    # mustard mug
    p.add(p.soft(E(560, 452, 90, 16, "#0c150f", opacity=.7), 8))
    p.add(cup_side(p, 555, 450, 124, 128, "#d9a53a", liquid=p.rg("#6b4127", "#3d2415"), handle="left", persp=.16,
                   rim_light="#ffd58a"))
    p.add(p.soft(R(496, 340, 10, 100, "#ffe0a0", opacity=.5), 4))
    p.add(steam(p, 555, 300, 120, col="#ffe7c2", op=.3, seed=6))


def ig_save_0(p):
    """A café interior: bottle-green wall, cup shelves, three pendant lamps, white marble counter."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#2f4a3e", "#223a30")))
    # shelves with cups
    for sy in (250, 350):
        p.add(R(40, sy, 560, 10, p.lg("#b88b55", "#7c5a33")))
        p.add(p.soft(R(40, sy + 10, 560, 14, "#0f1c16", opacity=.6), 5))
        for i in range(9):
            x = 70 + i * 60
            col = ["#f2eee6", "#e8d5b5", "#c9d6cf", "#f2eee6"][i % 4]
            p.add(cup_side(p, x, sy, 38, 30, col, handle="right" if i % 2 else None, persp=.2))
    # pendants
    for i, x in enumerate((140, 320, 500)):
        cy = 150 + (i % 2) * 22
        p.add(L(x, 0, x, cy - 40, "#141414", 2))
        p.add(p.soft(E(x, cy + 80, 150, 120, "#ffcf87", opacity=.32), 30))
        p.add(P(f"M{x - 52},{cy} C{x - 50},{cy - 50} {x + 50},{cy - 50} {x + 52},{cy} Z", p.lg("#e4e0d6", "#b8b1a2", x2=1, y2=0)))
        p.add(E(x, cy, 52, 10, "#fff2cf"))
        p.add(p.soft(E(x, cy + 4, 34, 7, "#ffffff"), 3))
    # machine on the counter
    p.add(p.soft(E(330, 540, 220, 20, "#0c1510", opacity=.7), 10))
    p.add(R(150, 380, 360, 162, p.lg("#c75b3c", "#a8442a"), rx=12))
    p.add(R(150, 380, 360, 12, chrome(p, "#9aa0a3", horizontal=False), rx=6))
    p.add(R(166, 400, 328, 48, chrome(p, "#9aa0a3"), rx=6))
    p.add(R(172, 470, 316, 66, "#2a1a14", rx=6))
    p.add(R(172, 520, 316, 16, chrome(p, "#7d8387", horizontal=False), rx=3))
    for gx in (250, 410):
        p.add(R(gx - 30, 448, 60, 26, chrome(p, "#7d8387"), rx=6))
        p.add(R(gx - 34, 472, 68, 12, "#1a1a1a", rx=5))
        p.add(P(f"M{gx - 30},{474} L{gx - 120},{500} L{gx - 116},{512} L{gx - 26},{484} Z", "#141414"))
        p.add(cup_side(p, gx, 520, 40, 30, "#f2eee6", handle="right", persp=.2))
    # steam wand
    p.add(P("M494,430 C530,430 536,470 528,530", "none", stroke="#c9ced3", stroke_width=6, stroke_linecap="round"))
    for i, x in enumerate((190, 222, 254, 440)):
        p.add(cup_side(p, x, 380, 30, 22, "#f2eee6", persp=.2))
    # marble counter
    p.add(R(0, 540, w, 16, p.lg("#ffffff", "#e3e1dc")))
    p.add(R(0, 556, w, 244, p.lg("#f1efea", "#dcd8d0")))
    rnd = random.Random(14)
    for _ in range(9):
        x0 = rnd.uniform(-100, w)
        y0 = rnd.uniform(560, 800)
        d = f"M{n(x0)},{n(y0)} C{n(x0 + 120)},{n(y0 - 40)} {n(x0 + 180)},{n(y0 + 60)} {n(x0 + 320)},{n(y0 + 10)}"
        p.add(f'<path d="{d}" fill="none" stroke="#9c9a95" stroke-width="{n(rnd.uniform(1, 2.6))}" opacity="{n(rnd.uniform(.2, .45))}"/>')
    p.add(p.soft(R(0, 556, w, 60, "#ffd9a0", opacity=.2), 20))


DRAW = {
    "x-photo-1": x_photo_1, "nostr-2b": nostr_2b, "ig-save-0": ig_save_0,
}


def html(p):
    w, h = p["size"]
    pic = Pic(w, h)
    DRAW[p["key"]](pic)
    return pic.html()


# ── more motifs ───────────────────────────────────────────────────────────


def smooth(pts, closed=True):
    """Catmull-Rom through points → a cubic Bézier path string."""
    k = len(pts)
    if closed:
        get = lambda i: pts[i % k]
        rng = range(k)
    else:
        get = lambda i: pts[max(0, min(k - 1, i))]
        rng = range(k - 1)
    d = f"M{n(pts[0][0])},{n(pts[0][1])} "
    for i in rng:
        p0, p1, p2, p3 = get(i - 1), get(i), get(i + 1), get(i + 2)
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f"C{n(c1[0])},{n(c1[1])} {n(c2[0])},{n(c2[1])} {n(p2[0])},{n(p2[1])} "
    return d + ("Z" if closed else "")


def blob(cx, cy, rx, ry, rnd, k=9, jit=.18, rot=0):
    pts = []
    for i in range(k):
        a = 2 * math.pi * i / k
        r = 1 + rnd.uniform(-jit, jit)
        x, y = math.cos(a) * rx * r, math.sin(a) * ry * r
        c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        pts.append((cx + x * c - y * s_, cy + x * s_ + y * c))
    return smooth(pts)


def scallop(cx, cy, r, amp, k):
    pts = [(cx + math.cos(2 * math.pi * i / (k * 4)) * (r + amp * math.cos(2 * math.pi * i / 4)),
            cy + math.sin(2 * math.pi * i / (k * 4)) * (r + amp * math.cos(2 * math.pi * i / 4))) for i in range(k * 4)]
    return smooth(pts)


def flour(p, box, k, rnd, col="#ffffff", op=.5):
    x0, y0, x1, y1 = box
    dots = "".join(C(rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(.8, 2.2), col, opacity=rnd.uniform(op * .4, op))
                   for _ in range(k))
    return dots


# ── pastry and food ───────────────────────────────────────────────────────


def ig_photo_1(p):
    """Pastel de nata, top-down on a pale plate over a navy slate table; cinnamon, a stick of it."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.rg("#3f4b62", "#2a3346", "#1c2232", cx=.3, cy=.25, r=.95)))
    cx, cy = 312, 390
    p.add(p.soft(C(cx + 26, cy + 30, 238, "#0b0f18"), 18, .55))
    p.add(C(cx, cy, 236, p.rg((0, "#eef2f3"), (.72, "#e2e8ea"), (.8, "#f7f9f9"), (1, "#c3cdd2"), cx=.45, cy=.42)))
    p.add(C(cx, cy, 172, "#dbe3e6"))
    p.add(C(cx, cy, 172, "none", stroke="#ffffff", stroke_width=2, opacity=.6))
    # the tart
    tx, ty = cx - 6, cy - 4
    p.add(p.soft(C(tx + 12, ty + 14, 146, "#5a6770"), 8, .6))
    p.add(P(scallop(tx, ty, 140, 5, 18), p.rg((0, "#e8b765"), (.78, "#d99a45"), (.9, "#b8702e"), (1, "#8a4d1d"))))
    for i, r in enumerate((138, 133, 128, 123, 119)):
        p.add(C(tx + (i - 2) * 1.2, ty + (i % 2), r, "none", stroke="#f9dc9a" if i % 2 == 0 else "#95521f", stroke_width=2.4, opacity=.7))
    p.add(C(tx, ty, 116, "#b8702e"))
    p.add(C(tx, ty, 112, p.rg((0, "#fbe08a"), (.6, "#f3c552"), (1, "#e3a43a"), cx=.45, cy=.45)))
    rnd = random.Random(8)
    halo, spots = [], []
    for _ in range(26):
        a = rnd.uniform(0, 2 * math.pi)
        rr = 96 * math.sqrt(rnd.uniform(0, 1))
        x, y = tx + math.cos(a) * rr, ty + math.sin(a) * rr
        big = rnd.random() < .25
        rx_ = rnd.uniform(12, 22) if big else rnd.uniform(4, 10)
        ry_ = rx_ * rnd.uniform(.55, .85)
        rot = rnd.uniform(0, 180)
        halo.append(P(blob(x, y, rx_ * 1.7, ry_ * 1.7, rnd, rot=rot), "#b8641f"))
        spots.append(P(blob(x, y, rx_, ry_, rnd, rot=rot), rnd.choice(["#3a1606", "#4a1e08", "#2a0f04"])))
    p.add(p.soft("".join(halo), 6, .55))
    p.add(p.soft("".join(spots), 1.5, .92))
    p.add(p.soft(E(tx - 40, ty - 44, 50, 26, "#fff6d0", opacity=.45), 10))
    # cinnamon dusting
    p.add(p.soft(C(tx + 20, ty + 10, 60, "#8b4a22", opacity=.22), 14))
    p.add(flour(p, (tx - 90, ty - 80, tx + 100, ty + 90), 120, rnd, col="#7a3a18", op=.7))
    # cinnamon stick
    st = [R(0, -14, 210, 28, p.lg("#9a4f25", "#7a3718", "#4f200c"), rx=10),
          R(0, -14, 210, 8, "#b8683a", rx=4, opacity=.6),
          E(210, 0, 9, 14, "#5a2710"), P("M204,-10 C216,-4 212,6 202,8", "none", stroke="#b8683a", stroke_width=3)]
    p.add(p.soft(f'<g transform="translate(400 700) rotate(-18)">{R(6, -4, 210, 28, "#0b0f18", rx=10)}</g>', 6, .55))
    p.add(f'<g transform="translate(380 694) rotate(-18)">{"".join(st)}</g>')
    p.add(flour(p, (90, 640, 340, 760), 26, rnd, col="#8b4a22", op=.6))


def ig_photo_3(p):
    """Sourdough batard from a high three-quarter view on oatmeal linen: banneton flour rings, one long opened ear."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#4a423c", "#2d2724", x1=0, y1=0, x2=1, y2=.4)))
    p.add(p.soft(E(60, 160, 260, 280, "#8a7a6a", opacity=.35), 60))
    p.add(P("M-20,300 C140,270 480,280 660,300 L660,800 L-20,800 Z", p.lg("#e7dcc8", "#d6c8ae", "#c4b393")))
    p.add(P("M-20,700 C200,690 420,700 660,690 L660,716 C420,726 200,716 -20,726 Z", "#6f8aa3", opacity=.55))
    folds = [("M40,320 C90,480 70,640 120,800", .18), ("M560,300 C520,460 580,640 540,800", .16)]
    for d, op in folds:
        p.add(p.soft(P(d, "none", stroke="#8f7c5c", stroke_width=18, opacity=op), 8))
    cx, cy = 320, 500
    p.add(p.soft(E(cx + 30, cy + 96, 270, 40, "#3f3322"), 16, .65))
    loaf = (f"M{cx - 262},{cy + 70} C{cx - 280},{cy - 70} {cx - 160},{cy - 170} {cx},{cy - 170} "
            f"C{cx + 160},{cy - 170} {cx + 284},{cy - 70} {cx + 262},{cy + 70} C{cx + 230},{cy + 112} {cx - 230},{cy + 112} {cx - 262},{cy + 70} Z")
    p.add(P(loaf, p.rg((0, "#a8622a"), (.45, "#7a3a14"), (.8, "#4e220a"), (1, "#2e1204"), cx=.38, cy=.28, r=.78)))
    clip = p.clip(P(loaf, "#000"))
    rb = random.Random(33)
    blotch = "".join(P(blob(cx + rb.uniform(-230, 230), cy + rb.uniform(-140, 80), rb.uniform(20, 50), rb.uniform(12, 30), rb), rb.choice(["#3a1606", "#b86e32"])) for _ in range(14))
    p.add(G(p.soft(blotch, 8, .45), clip_path=clip))
    blist = "".join(C(cx + rb.uniform(-240, 240), cy + rb.uniform(-150, 90), rb.uniform(1.5, 3.5), "#2a1004", opacity=.7) for _ in range(90))
    p.add(G(blist, clip_path=clip))
    # matte flour at the two ends, and banneton lines across the shoulders
    p.add(G(p.soft(E(cx - 200, cy + 10, 110, 100, "#efe4d2", opacity=.5), 26), p.soft(E(cx + 210, cy - 10, 100, 100, "#efe4d2", opacity=.45), 26), clip_path=clip))
    lines = "".join(P(f"M{cx - 260 + k * 30},{cy + 80} C{cx - 250 + k * 30},{cy - 20} {cx - 200 + k * 34},{cy - 110} {cx - 140 + k * 38},{cy - 160}",
                      "none", stroke="#f1e6d2", stroke_width=4, opacity=.22) for k in range(3))
    lines += "".join(P(f"M{cx + 260 - k * 30},{cy + 80} C{cx + 250 - k * 30},{cy - 20} {cx + 200 - k * 34},{cy - 110} {cx + 140 - k * 38},{cy - 160}",
                       "none", stroke="#f1e6d2", stroke_width=4, opacity=.2) for k in range(3))
    p.add(G(p.soft(lines, 1.2), clip_path=clip))
    # the long score, opened wide, and the ear lifting over it
    ax, ay, bx, by = cx - 190, cy - 30, cx + 200, cy - 80
    p.add(P(f"M{ax},{ay} C{cx - 90},{cy - 140} {cx + 90},{cy - 156} {bx},{by} C{cx + 90},{cy - 100} {cx - 90},{cy - 70} {ax},{ay} Z",
            p.lg("#f0c784", "#d9974e", "#8a4a1c", x2=0, y2=1)))
    p.add(p.soft(P(f"M{ax + 10},{ay - 6} C{cx - 90},{cy - 136} {cx + 90},{cy - 156} {bx - 8},{by - 2}", "none", stroke="#3a1606", stroke_width=14), 5, .55))
    ear = f"M{ax},{ay} C{cx - 100},{cy - 172} {cx + 80},{cy - 190} {bx},{by} C{cx + 80},{cy - 160} {cx - 90},{cy - 138} {ax},{ay} Z"
    p.add(P(ear, p.lg("#7a3a14", "#3a1806", x2=0, y2=1)))
    p.add(P(f"M{ax + 16},{ay - 12} C{cx - 96},{cy - 166} {cx + 76},{cy - 184} {bx - 12},{by - 4}", "none", stroke="#f0b06a", stroke_width=3.5, opacity=.9))
    p.add(P(f"M{ax},{ay} C{cx - 90},{cy - 70} {cx + 90},{cy - 100} {bx},{by}", "none", stroke="#3a1606", stroke_width=3, opacity=.7))
    p.add(p.soft(P(f"M{cx - 240},{cy + 20} C{cx - 230},{cy - 60} {cx - 170},{cy - 120} {cx - 90},{cy - 150}", "none", stroke="#f0b87a", stroke_width=10, opacity=.4), 6))
    rnd = random.Random(13)
    p.add(flour(p, (cx - 250, cy + 90, cx + 270, cy + 170), 40, rnd, col="#f8f2e6", op=.8))


def ig_save_5(p):
    """Laminated dough on a floured steel bench, the cut edge showing butter layers, a tapered pin."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg((0, "#aeb7bf"), (.5, "#c9d0d6"), (1, "#9aa3ab"), x1=0, y1=0, x2=1, y2=1)))
    p.add(p.soft(PL([(0, 120), (640, 0), (640, 110), (0, 260)], "#ffffff", opacity=.35), 30))
    rnd = random.Random(19)
    p.add(p.soft("".join(P(blob(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(40, 110), rnd.uniform(30, 70), rnd), "#ffffff")
                         for _ in range(9)), 14, .45))
    p.add(flour(p, (0, 0, w, h), 160, rnd, op=.6))
    # the slab: top face and a front face of stacked layers
    top = [(90, 250), (500, 210), (560, 520), (130, 580)]
    front = [(130, 580), (560, 520), (560, 572), (130, 634)]
    p.add(p.soft(PL([(140, 610), (580, 540), (600, 600), (150, 660)], "#4a5058"), 12, .45))
    p.add(PL(top, p.lg("#f6ead0", "#ecdab5", x2=1, y2=1)))
    p.add(p.soft(PL(subquad(top, .1, .1, .7, .5), "#ffffff"), 20, .5))
    k = 11
    for i in range(k):
        col = "#f8d977" if i % 2 else "#f1e2c2"
        p.add(PL(subquad(front, 0, i / k, 1, (i + 1) / k), col))
    p.add(PL(front, p.lg((0, "#000", 0), (1, "#6b5a3a", .25)), opacity=1))
    # a cut strip lying in front, turned to show its layers
    strip = [(240, 690), (470, 660), (474, 700), (244, 732)]
    p.add(p.soft(PL([(250, 712), (490, 682), (494, 726), (254, 756)], "#4a5058"), 8, .45))
    for i in range(k):
        col = "#f7d466" if i % 2 else "#efdfbd"
        p.add(PL(subquad(strip, 0, i / k, 1, (i + 1) / k), col))
    p.add(PL([(240, 690), (470, 660), (480, 650), (250, 680)], "#f6ead0"))
    # tapered pin
    pin = [P("M0,-16 C120,-30 300,-30 420,-16 L420,16 C300,30 120,30 0,16 Z", p.lg("#e3c08d", "#c79a60", "#8f6534")),
           P("M20,-10 C140,-22 290,-22 400,-10", "none", stroke="#fff1d6", stroke_width=4, opacity=.6)]
    p.add(p.soft(f'<g transform="translate(250 160) rotate(28)">{pin[0]}</g>', 10, .4))
    p.add(f'<g transform="translate(236 136) rotate(28)">{"".join(pin)}</g>')
    p.add(flour(p, (100, 230, 540, 560), 70, rnd, op=.9))


def ig_save_10(p):
    """Macro: a croissant cut open — honeycomb crumb in the cut face, the rolled, glossy body behind it."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.rg("#4a2e1c", "#2a1a10", "#170e08", cx=.35, cy=.3, r=.9)))
    p.add(R(0, 560, w, 240, p.lg("#5a3a26", "#3a2416")))
    p.add(p.soft(E(360, 600, 300, 40, "#050302"), 16, .8))
    # the body receding to the upper right: rolled bands, glossy
    lobes = [(470, 250, 120, 95, -40), (410, 330, 150, 120, -35), (350, 400, 175, 140, -30)]
    for (x, y, rx_, ry_, rot) in [(560, 170, 70, 48, -45)] + lobes:
        p.add(E(x, y, rx_, ry_, p.lg("#e7a052", "#b86424", "#6a2f0e", x1=.2, y1=0, x2=.8, y2=1), transform=f"rotate({rot} {x} {y})"))
        p.add(E(x - rx_ * .25, y - ry_ * .35, rx_ * .5, ry_ * .22, "#ffd9a0", opacity=.35, transform=f"rotate({rot} {x} {y})"))
        p.add(E(x, y, rx_, ry_, "none", stroke="#4a1f08", stroke_width=3, opacity=.5, transform=f"rotate({rot} {x} {y})"))
    # the cut face, towards the viewer
    cx, cy = 280, 470
    face = f"M{cx - 230},{cy + 110} C{cx - 250},{cy - 30} {cx - 150},{cy - 200} {cx},{cy - 200} C{cx + 150},{cy - 200} {cx + 250},{cy - 30} {cx + 230},{cy + 110} C{cx + 140},{cy + 140} {cx - 140},{cy + 140} {cx - 230},{cy + 110} Z"
    p.add(P(face, p.lg("#d99448", "#a55a22", "#5e2a0c", x1=.2, y1=0, x2=.8, y2=1)))
    inner = f"M{cx - 204},{cy + 96} C{cx - 220},{cy - 22} {cx - 136},{cy - 172} {cx},{cy - 172} C{cx + 136},{cy - 172} {cx + 220},{cy - 22} {cx + 204},{cy + 96} C{cx + 128},{cy + 120} {cx - 128},{cy + 120} {cx - 204},{cy + 96} Z"
    p.add(P(inner, p.rg("#fcecc8", "#f3d9a6", "#e2b877", cx=.45, cy=.4, r=.7)))
    clip = p.clip(P(inner, "#000"))
    rnd = random.Random(23)
    cells, placed = [], []
    tries = 0
    while len(placed) < 170 and tries < 8000:
        tries += 1
        x, y = rnd.uniform(cx - 210, cx + 210), rnd.uniform(cy - 175, cy + 115)
        dxn, dyn = (x - cx) / 215, (y - (cy + 110)) / 285
        rr = math.hypot(dxn, dyn)
        if rr > .97 or rr < .06:
            continue
        big = rnd.random() < .3
        rx_ = rnd.uniform(16, 30) if big else rnd.uniform(6, 15)
        ry_ = rx_ * rnd.uniform(.28, .5)
        if any(math.hypot(x - px, y - py) < (rx_ + pr) * .62 for px, py, pr in placed):
            continue
        placed.append((x, y, rx_))
        tang = math.degrees(math.atan2(dyn, dxn)) + 90 + rnd.uniform(-12, 12)
        cells.append(P(blob(x, y, rx_, ry_, rnd, k=7, jit=.22, rot=tang),
                       p.rg("#7a3f16", "#a9652d", "#d49a5a", cx=.5, cy=.4, r=.6)))
    p.add(G(*cells, clip_path=clip))
    for k in range(3):
        p.add(P(face, "none", stroke="#f0b870" if k % 2 else "#6e320f", stroke_width=1.6, opacity=.5,
                transform=f"translate({cx} {cy + 110}) scale({1 - k * .04}) translate({-cx} {-cy - 110})"))
    p.add(p.soft(P(face, "none", stroke="#ffe0a8", stroke_width=8, opacity=.35, transform="translate(-6 -6)"), 5))
    for (x, y, r) in [(80, 640, 6), (120, 670, 4), (520, 660, 5), (580, 640, 3), (470, 700, 4)]:
        p.add(P(blob(x, y, r * 1.4, r, rnd), "#c98a4a"))


def ig_like_1(p):
    """A black cast-iron pot of stew on a cream range, seen from above at 45°, steam and a wooden spoon."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, 210, p.lg("#8aa4b4", "#7792a3")))
    p.add(R(0, 200, w, 14, "#d9d1c0"))
    p.add(R(0, 214, w, 586, p.lg("#efe7d6", "#ded3bd")))
    # grates
    for gx in (-70, 320, 710):
        p.add(E(gx, 560, 250, 150, "none", stroke="#222", stroke_width=14))
    p.add(L(0, 560, w, 560, "#222", 12))
    p.add(p.soft(E(320, 610, 170, 40, "#3f7bff", opacity=.55), 10))
    cx, cy = 320, 470
    p.add(p.soft(E(cx + 20, cy + 190, 250, 60, "#2b2418"), 18, .6))
    # handles
    for sx in (-1, 1):
        p.add(P(f"M{cx + sx * 220},{cy + 20} q{sx * 50},0 {sx * 50},40 q0,30 {sx * -40},30", "none", stroke="#1b1b1c", stroke_width=16))
    p.add(P(f"M{cx - 232},{cy} L{cx - 222},{cy + 170} C{cx - 150},{cy + 230} {cx + 150},{cy + 230} {cx + 222},{cy + 170} L{cx + 232},{cy} Z",
            p.lg("#111112", "#3a3b3e", "#1a1a1b", "#070707", x2=1, y2=0)))
    p.add(E(cx, cy, 232, 120, "#1c1c1e"))
    p.add(E(cx, cy + 6, 212, 108, p.rg("#b84a24", "#8f3517", "#5f200b", cx=.45, cy=.4, r=.65)))
    rnd = random.Random(29)
    bits = []
    for _ in range(26):
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0, .85)
        x, y = cx + math.cos(a) * 200 * rr, cy + 6 + math.sin(a) * 98 * rr
        kind = rnd.random()
        if kind < .35:
            bits.append(E(x, y, 16, 9, "#e8782a") + E(x - 3, y - 2, 8, 4, "#ffb066", opacity=.7))
        elif kind < .6:
            bits.append(P(blob(x, y, 15, 10, rnd), "#ecd7a0") + E(x - 4, y - 3, 6, 3, "#fff3cf", opacity=.7))
        elif kind < .85:
            bits.append(P(blob(x, y, 18, 11, rnd), "#5e2412"))
        else:
            bits.append(leaf(x, y, 12, 4, rnd.uniform(0, 360), "#3f7a3a"))
    p.add("".join(bits))
    p.add(p.soft(E(cx - 80, cy - 20, 60, 16, "#ffd6b0", opacity=.35), 6))
    p.add(E(cx, cy, 232, 120, "none", stroke="#555", stroke_width=3, opacity=.8))
    # spoon resting in the pot, handle over the rim to the upper right
    sp = [E(0, 0, 44, 30, p.lg("#d6a86c", "#a8773f")), R(30, -9, 300, 18, p.lg("#e2b57a", "#b48548", "#8f6534"), rx=9),
          E(-6, -2, 30, 18, "#8f3517", opacity=.6)]
    p.add(p.soft(f'<g transform="translate({cx + 28} {cy + 26}) rotate(-28)">{R(30, -9, 300, 18, "#1c1c1e", rx=9)}</g>', 6, .6))
    p.add(f'<g transform="translate({cx + 10} {cy + 14}) rotate(-28)">{"".join(sp)}</g>')
    p.add(steam(p, cx - 40, cy - 40, 280, op=.45, wide=26, sway=30, k=4, seed=3))


def tt_save_0(p):
    """Top-down on dark slate: a walnut board, a chef's knife, a heap of finely diced red onion, the cut half."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#32373c", "#23272b", x2=1, y2=1)))
    bx = [(40, 120), (420, 90), (440, 700), (60, 730)]
    p.add(p.soft(PL([(60, 140), (440, 110), (462, 724), (82, 756)], "#050607"), 14, .7))
    p.add(PL(bx, p.lg("#7a5236", "#5c3b25", "#4a2e1b", x2=1, y2=1)))
    p.add(G(grain(p, 0, 80, w, 680, "#2f1c10", k=16, op=.35, seed=4, vertical=True, wav=14), clip_path=p.clip(PL(bx, "#000"))))
    rnd = random.Random(41)
    # diced onion heap
    dice = []
    for _ in range(170):
        a = rnd.uniform(0, 2 * math.pi)
        rr = math.sqrt(rnd.uniform(0, 1))
        x, y = 170 + math.cos(a) * 120 * rr, 520 + math.sin(a) * 110 * rr
        s_ = rnd.uniform(9, 14)
        col = rnd.choice(["#f4e8f0", "#efdbe8", "#e9cfe0", "#f8f0f4"])
        dice.append(R(x - s_ / 2, y - s_ / 2, s_, s_, col, rx=2.5, stroke="#b56c9c", stroke_width=1.2,
                      transform=f"rotate({n(rnd.uniform(0, 90))} {n(x)} {n(y)})"))
    p.add(p.soft(C(176, 530, 120, "#1a0f08"), 10, .35))
    p.add("".join(dice))
    # the cut half, face up: rings
    ox, oy = 320, 250
    p.add(p.soft(C(ox + 8, oy + 10, 84, "#1a0f08"), 8, .5))
    p.add(C(ox, oy, 84, "#7b2754"))
    for i, r in enumerate(range(78, 6, -12)):
        p.add(C(ox, oy, r, "#f3e4ee" if i % 2 == 0 else "#ead2e2", stroke="#b0558d", stroke_width=2.2))
    p.add(C(ox - 20, oy - 24, 24, "#ffffff", opacity=.25))
    # skin curl
    p.add(P("M330,380 C380,370 400,420 372,450 C386,414 360,396 330,398 Z", "#8e3a64"))
    # knife, blade toward the upper left
    kn = [P("M0,-26 L300,-22 C340,-20 372,-6 390,20 L0,24 Z", p.lg("#f1f3f5", "#b9c0c6", "#8a939b")),
          L(0, 12, 380, 16, "#ffffff", 2, opacity=.6),
          R(-150, -18, 156, 36, p.lg("#2a2a2c", "#0d0d0e"), rx=12),
          C(-110, 0, 4, "#c9ced3"), C(-70, 0, 4, "#c9ced3"), C(-30, 0, 4, "#c9ced3")]
    p.add(p.soft(f'<g transform="translate(300 660) rotate(-120)">{kn[0]}{kn[2]}</g>', 8, .6))
    p.add(f'<g transform="translate(290 646) rotate(-120)">{"".join(kn)}</g>')


def tt_save_1(p):
    """A sheet pan straight from above: crisp chicken thighs, peppers, red onion, broccoli, lemon, rosemary."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#23403f", "#1a3130")))
    p.add(p.soft(R(40, 60, 390, 700, "#060d0c", rx=24), 14, .7))
    p.add(R(24, 40, 402, 712, p.lg("#4c5156", "#2f3337", x2=1, y2=1), rx=22))
    p.add(R(38, 54, 374, 684, p.lg("#3a3e42", "#26292c"), rx=14))
    p.add(R(50, 66, 350, 660, p.lg("#e9dfcc", "#d8cbb2", x2=1, y2=1), rx=8))
    for d in ("M50,300 L400,340", "M200,66 L220,726", "M50,560 L400,520"):
        p.add(P(d, "none", stroke="#b9a988", stroke_width=2, opacity=.35))
    p.add(p.soft(R(50, 66, 350, 660, "#7a4a1e", rx=8), 30, .25))
    rnd = random.Random(52)
    # chicken thighs
    for (x, y, rot) in [(140, 180, 20), (310, 250, -30), (150, 460, 70), (300, 590, 10)]:
        body = blob(x, y, 78, 58, rnd, k=10, jit=.14, rot=rot)
        p.add(p.soft(P(body, "#3a1c08"), 5, .6))
        p.add(P(body, p.rg("#e8a453", "#c6772d", "#8a4515", cx=.4, cy=.35, r=.7)))
        p.add(P(blob(x - 14, y - 12, 34, 18, rnd, rot=rot), "#f5c880", opacity=.55))
        p.add("".join(C(x + rnd.uniform(-50, 50), y + rnd.uniform(-35, 35), rnd.uniform(1.5, 3), "#3c5a1e", opacity=.8) for _ in range(12)))
    # peppers (curved strips)
    for (x, y, rot, col) in [(290, 110, 30, "#d7342a"), (90, 330, -20, "#f2b52a"), (330, 420, 60, "#d7342a"),
                             (230, 690, -10, "#f2b52a"), (110, 640, 40, "#d7342a")]:
        p.add(f'<g transform="translate({x} {y}) rotate({rot})">'
              + P("M-46,0 C-30,-26 30,-26 46,0 C30,-12 -30,-12 -46,0 Z", col)
              + P("M-30,-12 C-10,-20 10,-20 26,-14", "none", stroke="#ffffff", stroke_width=3, opacity=.4) + "</g>")
    # red onion wedges
    for (x, y, rot) in [(250, 360, 0), (80, 560, 120), (360, 700, 60), (220, 110, 200)]:
        p.add(f'<g transform="translate({x} {y}) rotate({rot})">'
              + "".join(P(f"M-{r},0 A{r},{r} 0 0 1 {r},0", "none", stroke=c, stroke_width=6)
                        for r, c in ((30, "#7b2754"), (22, "#e6c4d8"), (14, "#9c3a6c"))) + "</g>")
    # broccoli
    for (x, y) in [(360, 150), (230, 520), (90, 90), (370, 490)]:
        p.add(R(x - 4, y, 8, 26, "#9dbf6a", rx=3))
        p.add("".join(C(x + rnd.uniform(-18, 18), y + rnd.uniform(-16, 4), rnd.uniform(9, 13), rnd.choice(["#2f5f2a", "#3c7534", "#27501f"])) for _ in range(9)))
    # lemon halves
    for (x, y) in [(220, 250), (380, 610)]:
        p.add(C(x, y, 34, "#e8c131"), C(x, y, 29, "#fbe58a"))
        p.add("".join(L(x, y, x + math.cos(a) * 26, y + math.sin(a) * 26, "#f4d257", 2.4) for a in [i * math.pi / 5 for i in range(10)]))
        p.add(C(x - 8, y - 10, 10, "#ffffff", opacity=.3))
    # rosemary
    for (x, y, rot) in [(150, 300, 30), (280, 470, -50)]:
        g = [L(-60, 0, 60, 0, "#5a4a2a", 2.5)] + [leaf(i * 10 - 55, 0, 16, 3, 60 if i % 2 else 120, "#4b6b3c") for i in range(12)]
        p.add(f'<g transform="translate({x} {y}) rotate({rot})">{"".join(g)}</g>')


def snap_2(p):
    """Birthday cake in a dark room: pink buttercream, striped candles, the only light is theirs."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, "#0c0d16"))
    p.add(p.soft(E(225, 330, 260, 230, "#ffb35c", opacity=.28), 50))
    # table and its reflection of the glow
    p.add(R(0, 560, w, 240, p.lg("#2a1a12", "#120b08")))
    p.add(p.soft(E(225, 600, 220, 40, "#ffb35c", opacity=.35), 20))
    cx, top, base = 225, 430, 610
    p.add(p.soft(E(cx, base + 12, 190, 26, "#000"), 8, .8))
    p.add(E(cx, base + 4, 190, 30, p.lg("#e6e2dc", "#a9a39a")))
    p.add(P(f"M{cx - 150},{top} L{cx - 150},{base - 6} C{cx - 150},{base + 26} {cx + 150},{base + 26} {cx + 150},{base - 6} L{cx + 150},{top} Z",
            p.lg((0, "#8a4a5c"), (.3, "#f1b6c4"), (.55, "#e89aae"), (1, "#6e3444"), x2=1, y2=0)))
    # drips
    rnd = random.Random(61)
    for i in range(11):
        x = cx - 140 + i * 28 + rnd.uniform(-4, 4)
        ln = rnd.uniform(20, 60)
        p.add(P(f"M{n(x - 10)},{top} L{n(x - 10)},{n(top + ln)} a10,10 0 0 0 20,0 L{n(x + 10)},{top} Z", "#fbe9d8"))
    p.add(E(cx, top, 150, 34, p.rg("#fff4ea", "#f6dcd0", cx=.5, cy=.3)))
    # piped border
    for i in range(22):
        a = 2 * math.pi * i / 22
        x, y = cx + math.cos(a) * 138, top + math.sin(a) * 30
        p.add(C(x, y, 9, "#f0a7ba" if math.sin(a) > 0 else "#d98aa0"))
    # sprinkles
    cols = ["#6fc3df", "#ffd166", "#ef476f", "#9bde7e", "#b18cff"]
    for _ in range(30):
        x, y = cx + rnd.uniform(-100, 100), top + rnd.uniform(-18, 18)
        p.add(R(x, y, 7, 2.4, rnd.choice(cols), rx=1.2, transform=f"rotate({n(rnd.uniform(0, 180))} {n(x)} {n(y)})"))
    # candles
    for i, x in enumerate((150, 190, 228, 266, 304)):
        cy = top - 6 + (8 if i % 2 else -4)
        ch = 92
        p.add(R(x - 6, cy - ch, 12, ch, "#f4f0ea"))
        for k in range(6):
            yy = cy - ch + k * 16
            p.add(P(f"M{x - 6},{yy + 8} L{x + 6},{yy} L{x + 6},{yy + 6} L{x - 6},{yy + 14} Z", cols[i]))
        p.add(L(x, cy - ch, x, cy - ch - 8, "#222", 2))
        fy = cy - ch - 8
        p.add(p.soft(C(x, fy - 16, 30, "#ffcf70", opacity=.55), 12))
        p.add(P(f"M{x},{fy - 40} C{x + 12},{fy - 18} {x + 10},{fy} {x},{fy} C{x - 10},{fy} {x - 12},{fy - 18} {x},{fy - 40} Z",
                p.lg("#fffbe8", "#ffd873", "#ff9a3c")))
        p.add(E(x, fy - 6, 3, 5, "#6aa0ff", opacity=.7))
    # rim light on the plate edge
    p.add(p.soft(E(cx, base - 10, 150, 6, "#ffd9a0", opacity=.5), 4))


def dayone_14(p):
    """A long birthday dinner table from directly above, set on a diagonal, candlelit and crowded."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, "#2a1e17"))
    for i in range(-2, 14):
        p.add(R(i * 70, -50, 68, h + 100, "#33251c" if i % 2 else "#2e2119", transform=f"rotate(8 {w / 2} {h / 2})"))
    rnd = random.Random(71)
    g = []
    top, bot = 150, 450
    # chairs, pulled out at different distances and angles
    for side, y0 in (("t", top - 58), ("b", bot + 58)):
        for i in range(8):
            x = -100 + i * 128 + (64 if side == "b" else 0) + rnd.uniform(-14, 14)
            y = y0 + (rnd.uniform(-10, 18) if side == "t" else rnd.uniform(-18, 10))
            rot = rnd.uniform(-14, 14)
            back = -34 if side == "t" else 34
            g.append(f'<g transform="translate({n(x)} {n(y)}) rotate({n(rot)})">'
                     + R(-34, -30, 68, 60, "#5a4030", rx=12) + R(-38, back - 8 if side == "t" else back - 6, 76, 14, "#4a3226", rx=7) + "</g>")
    g.append(p.soft(R(-200, top + 10, w + 400, bot - top, "#000"), 14, .6))
    g.append(R(-200, top, w + 400, bot - top, p.lg("#f5efe4", "#e6ddcd")))
    g.append(R(-200, top, w + 400, 5, "#ffffff", opacity=.7))
    for x in (40, 300, 560, 820):
        g.append(p.soft(E(x, 300, 170, 120, "#ffcf7a", opacity=.35), 30))
    foods = [("#c7662d", "#e79a4a"), ("#5a8a3a", "#9cc36a"), ("#b83a3a", "#e8a07a"), ("#d9b35a", "#f2d68a")]
    for side, y in (("t", top + 58), ("b", bot - 58)):
        for i in range(8):
            x = -100 + i * 128 + (64 if side == "b" else 0) + rnd.uniform(-10, 10)
            yy = y + rnd.uniform(-8, 8)
            g.append(p.soft(C(x + 4, yy + 6, 44, "#6d5a40"), 5, .35))
            g.append(C(x, yy, 44, p.rg("#ffffff", "#f1ede6", "#d7d0c4")))
            g.append(C(x, yy, 32, "#ece6dc"))
            fc = foods[(i * 3 + (side == "b")) % 4]
            if rnd.random() < .8:
                g.append(P(blob(x + rnd.uniform(-6, 6), yy + rnd.uniform(-6, 6), 20, 15, rnd), fc[0]))
                g.append(P(blob(x - 5, yy - 4, 9, 6, rnd), fc[1], opacity=.8))
            ang = rnd.uniform(-25, 25)
            g.append(f'<g transform="rotate({n(ang)} {n(x)} {n(yy)})">' + R(x - 60, yy - 24, 5, 48, "#b9b3a8", rx=2) + R(x + 55, yy - 24, 5, 48, "#b9b3a8", rx=2) + "</g>")
            gy = yy + (44 if side == "t" else -44)
            gx = x + rnd.uniform(30, 56)
            g.append(C(gx, gy, 15, "#ffffff", opacity=.35) + C(gx, gy, 11, "#7a1f2c", opacity=rnd.uniform(.4, .85)))
            g.append(C(gx - 4, gy - 4, 4, "#ffffff", opacity=.6))
            g.append(C(x - 40, gy, 12, "#dfe9ef", opacity=.55, stroke="#ffffff", stroke_width=1.5))
            if rnd.random() < .5:
                g.append(R(x - 70, yy + 20, 30, 22, rnd.choice(["#c9a0a8", "#9fb4c9"]), rx=3, transform=f"rotate({n(rnd.uniform(-30, 30))} {n(x - 55)} {n(yy + 31)})"))
    for x in (40, 300, 560, 820):
        g.append(C(x, 300, 12, "#f7f2e8") + C(x, 300, 5, "#ffcf70"))
        g.append(p.soft(C(x, 300, 22, "#ffe3a0", opacity=.8), 6))
    for x in (170, 690):
        g.append(C(x, 300, 34, "#3f6b8a") + C(x, 300, 28, "#6fae5a") +
                 "".join(C(x + rnd.uniform(-18, 18), 300 + rnd.uniform(-18, 18), 5, rnd.choice(["#e0503a", "#f2d15a", "#fff"])) for _ in range(8)))
    g.append(R(380, 282, 90, 40, "#b98a55", rx=6) + E(425, 302, 34, 13, "#d69a55") + E(425, 302, 26, 8, "#e9b877"))
    g.append(C(-60, 300, 30, "#e8ddd0") + "".join(C(-60 + math.cos(a) * 16, 300 + math.sin(a) * 16, 9, c)
                                                   for a, c in zip([i * 1.26 for i in range(5)], ["#e86a8a", "#f2a0b8", "#ffffff", "#e86a8a", "#f7c26b"])))
    for x in (105, 245, 505, 625):
        g.append(C(x, 300, 14, "#2c4a2a") + C(x, 300, 6, "#4a7a44") + C(x - 4, 296, 3, "#ffffff", opacity=.5))
    for _ in range(30):
        x, y = rnd.uniform(-100, w + 100), rnd.uniform(top + 10, bot - 10)
        g.append(R(x, y, 6, 3, rnd.choice(["#ef476f", "#ffd166", "#6fc3df"]), transform=f"rotate({n(rnd.uniform(0, 180))} {n(x)} {n(y)})"))
    p.add(f'<g transform="rotate(-14 {w / 2} {h / 2}) translate(0 0) scale(1.08)">' + "".join(g) + "</g>")
    p.add(p.soft(R(0, 0, w, h, "none", stroke="#000", stroke_width=120), 40, .5))


DRAW.update({
    "ig-photo-1": ig_photo_1, "ig-photo-3": ig_photo_3, "ig-save-5": ig_save_5, "ig-save-10": ig_save_10,
    "ig-like-1": ig_like_1, "tt-save-0": tt_save_0, "tt-save-1": tt_save_1, "snap-2": snap_2,
    "dayone-14": dayone_14,
})


# ── rooms, ceramics and objects ───────────────────────────────────────────


def lathe(cx, base, prof, fill, **kw):
    """A turned vessel from a profile [(radius, height), …] listed base → rim."""
    right = [(cx + r, base - hh) for r, hh in prof]
    left = [(cx - r, base - hh) for r, hh in reversed(prof)]
    d = smooth(right, closed=False) + " L" + smooth(left, closed=False)[1:] + " Z"
    return P(d, fill, **kw)


def matte(p, col, light="left"):
    stops = [(0, lt(col, .18)), (.35, col), (1, dk(col, .32))]
    if light == "right":
        stops = [(0, dk(col, .32)), (.65, col), (1, lt(col, .18))]
    return p.lg(*stops, x2=1, y2=0)


def shot_14(p):
    """Wordless: a rubber plant in terracotta on a sunlit white sill, sun low from the left, long shadows."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#e9e3d8", "#d8d0c2")))
    # window: sky, a far roofline, the frame
    wx, wy, ww, wh = 70, 40, 460, 470
    p.add(R(wx, wy, ww, wh, p.lg("#5f9bd6", "#a9cdee", "#dbeaf5")))
    p.add(p.soft(PL([(wx, 400), (wx + 120, 380), (wx + 200, 400), (wx + 330, 370), (wx + ww, 390), (wx + ww, wy + wh), (wx, wy + wh)], "#9fb7a4"), 3))
    p.add(p.soft(C(wx + 60, wy + 70, 50, "#fffbe8", opacity=.8), 18))
    p.add(window_panes(wx, wy, ww, wh, "#f7f4ee", 16, cols=2, rows=3))
    # sill in sun
    p.add(PL([(20, 510), (580, 510), (600, 560), (0, 560)], p.lg("#fbf6ec", "#efe6d6")))
    p.add(R(0, 560, w, 28, "#e2d8c6"))
    p.add(R(0, 588, w, 212, p.lg("#ddd4c5", "#cfc4b2")))
    # mullion shadows on the sill, cast right
    for x in (230, 380):
        p.add(PL([(x, 512), (x + 16, 512), (x + 200, 558), (x + 170, 558)], "#b9ab96", opacity=.35))
    # pot and its long shadow
    cx, base = 220, 540
    p.add(p.soft(PL([(cx + 10, base - 4), (cx + 80, base - 8), (600, 516), (600, 548), (cx + 40, base + 12)], "#7a6248"), 5, .6))
    p.add(p.soft(PL([(0, 600), (360, 600), (520, 800), (0, 800)], "#fff3da", opacity=.45), 20))
    p.add(p.soft(P("M300,300 C360,250 470,260 600,300 L600,420 C480,400 380,420 300,480 Z", "#6f6a55"), 14, .25))
    p.add(lathe(cx, base, [(58, 0), (64, 30), (72, 80), (78, 110)], p.lg("#c0663e", "#d98559", "#a5502b", "#7a3a1f", x2=1, y2=0)))
    p.add(R(cx - 86, base - 132, 172, 28, p.lg("#c96e44", "#e59a6c", "#a04a28", x2=1, y2=0), rx=4))
    p.add(E(cx, base - 132, 84, 10, "#4a3226"))
    # stems and big glossy leaves, lit from the left
    rnd = random.Random(90)
    for (x2_, y2_) in [(170, 220), (240, 160), (290, 300), (150, 360), (260, 250)]:
        p.add(P(f"M{cx},{base - 130} Q{(cx + x2_) / 2 - 10},{(base - 130 + y2_) / 2} {x2_},{y2_}", "none", stroke="#4d5a2c", stroke_width=5))
    for (x, y, ln, wd, ang) in [(170, 230, 110, 42, -30), (240, 170, 120, 46, 10), (292, 310, 100, 40, 60), (150, 370, 96, 38, -70),
                                (262, 262, 110, 44, 35), (200, 300, 90, 36, -10), (120, 290, 90, 34, -50), (320, 220, 96, 38, 50)]:
        p.add(leaf(x, y, ln, wd, ang, p.lg("#5f8f4a", "#2f5a2c", "#1f3f1f", x2=1, y2=1), vein="#a6c98a"))
    p.add(p.soft(PL([(0, 0), (70, 0), (70, 800), (0, 800)], "#fff7e0", opacity=.25), 20))


def ig_save_1(p):
    """A wooden studio shelf, face on: books, a trailing pothos, speckled ceramics; soft window light from the left."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#efe9df", "#e0d7ca", x2=1, y2=0)))
    p.add(p.soft(PL([(0, 60), (260, 0), (360, 800), (0, 800)], "#fff9ee", opacity=.5), 30))
    oak = p.lg("#caa27a", "#b58b60")
    x0, x1 = 70, 570
    shelves = [150, 330, 510, 690]
    p.add(R(x0 - 18, 60, 18, 700, p.lg("#b58b60", "#9a724a", x2=1, y2=0)), R(x1, 60, 18, 700, p.lg("#b58b60", "#9a724a", x2=1, y2=0)))
    for y in shelves:
        p.add(p.soft(R(x0, y + 18, x1 - x0, 20, "#5d4a34"), 8, .35))
        p.add(R(x0 - 18, y, x1 - x0 + 36, 18, oak), R(x0 - 18, y, x1 - x0 + 36, 3, "#e8c9a0"))
    rnd = random.Random(101)
    spines = ["#6b7a4a", "#b5532f", "#e8dcc3", "#2f3e5c", "#d0a03e", "#8a3b35", "#c9c1b0", "#3c5a55"]
    # shelf 2: books upright, one leaning, a bowl
    x = x0 + 16
    for i in range(9):
        bw, bh = rnd.uniform(18, 34), rnd.uniform(110, 150)
        p.add(R(x, 330 - bh, bw, bh, rnd.choice(spines), rx=2), R(x + 3, 330 - bh + 14, bw - 6, 5, "#ffffff", opacity=.25))
        x += bw + 1.5
    p.add(R(x + 30, 200, 30, 130, "#b5532f", rx=2, transform=f"rotate(18 {x + 30} 330)"))
    p.add(lathe(470, 330, [(30, 0), (52, 20), (62, 44)], matte(p, "#e9e2d4")))
    p.add(E(470, 286, 62, 8, "#cfc6b4"))
    # shelf 3: ceramics — a speckled jug, stacked bowls, a round vase
    p.add(lathe(150, 510, [(34, 0), (46, 50), (40, 100), (26, 130), (32, 150)], matte(p, "#e4dccb")))
    p.add(P("M178,390 C210,392 214,450 184,468", "none", stroke="#d5ccb9", stroke_width=9))
    p.add(flour(p, (116, 370, 186, 505), 40, rnd, col="#6b5a45", op=.7))
    for i, (col, r) in enumerate([("#6e8c86", 70), ("#a7b8b1", 64), ("#d9d0bf", 58)]):
        p.add(lathe(300, 510 - i * 26, [(r * .55, 0), (r * .9, 16), (r, 26)], matte(p, col)))
    p.add(lathe(460, 510, [(36, 0), (70, 60), (64, 110), (30, 140), (26, 150)], matte(p, "#2f3134")))
    # shelf 4: a stacked pile and a basket
    for i in range(4):
        bw = rnd.uniform(150, 190)
        p.add(R(110 + rnd.uniform(-8, 8), 690 - (i + 1) * 26, bw, 24, rnd.choice(spines), rx=2))
    p.add(R(380, 610, 150, 80, p.lg("#c9a46e", "#a07a44"), rx=10))
    for yy in range(620, 690, 12):
        p.add(L(384, yy, 526, yy, "#8a6636", 2, opacity=.5))
    # top: pothos trailing over the edge
    p.add(lathe(320, 150, [(34, 0), (42, 60), (46, 76)], matte(p, "#f1ece2")))
    vines = [(-1, 320, 140, 300), (1, 360, 150, 260), (-1, 280, 150, 210), (1, 330, 150, 180)]
    for sgn, vx, vy, ln in vines:
        pts = [(vx, vy)]
        for k in range(1, 7):
            pts.append((vx + sgn * (k * 22 + rnd.uniform(-6, 6)), vy + k * ln / 6 + rnd.uniform(-10, 10)))
        p.add(P(smooth(pts, closed=False), "none", stroke="#4f6b33", stroke_width=3))
        for (lx, ly) in pts[1:]:
            p.add(leaf(lx, ly, 30, 13, rnd.uniform(120, 240), rnd.choice(["#4f8a3a", "#6ea34a", "#3f7a33"])))
    for k in range(9):
        p.add(leaf(320 + rnd.uniform(-40, 40), 80 + rnd.uniform(-10, 10), 34, 15, rnd.uniform(-60, 60), rnd.choice(["#4f8a3a", "#6ea34a", "#3f7a33"])))


def ig_save_2(p):
    """Three matte vases — sage, sand, charcoal — on a warm plaster sweep, soft light from the right."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#e9dccb", "#ddcdb7")))
    p.add(R(0, 560, w, 240, p.lg("#e4d5c0", "#d3c1a8")))
    p.add(p.soft(R(0, 540, w, 50, "#e9dccb"), 20))
    p.add(p.soft(E(520, 200, 260, 300, "#fff5e8", opacity=.5), 60))
    # shadows to the left
    for (cx, wd, ht) in [(190, 70, 360), (330, 110, 230), (470, 60, 300)]:
        p.add(p.soft(PL([(cx + wd * .6, 640), (cx - wd, 640), (cx - wd - ht * .7, 610), (cx - wd * .2 - ht * .5, 600)], "#8c7560"), 16, .35))
    base = 640
    p.add(lathe(190, base, [(48, 0), (70, 60), (72, 170), (40, 250), (18, 300), (22, 360)], matte(p, "#9aab8e", "right")))
    p.add(E(190, base - 360, 22, 5, "#5a6a50"))
    # a dry branch in the tall one
    p.add(P("M190,282 C180,200 150,150 120,90 M165,180 C190,150 210,140 240,120 M140,130 C130,110 110,100 90,96", "none", stroke="#7a5a3a", stroke_width=3))
    for (x, y) in [(120, 90), (240, 120), (90, 96), (150, 150), (205, 140)]:
        p.add(C(x, y, 5, "#c9a26a"))
    p.add(lathe(330, base + 10, [(60, 0), (104, 60), (112, 120), (96, 180), (54, 220), (46, 232)], matte(p, "#d6c29e", "right")))
    p.add(E(330, base + 10 - 232, 46, 8, "#a8946e"))
    p.add(lathe(470, base + 4, [(52, 0), (56, 120), (54, 200), (24, 230), (20, 280), (26, 296)], matte(p, "#3e3e41", "right")))
    p.add(E(470, base + 4 - 296, 26, 6, "#1d1d1f"))
    for (cx, y) in [(190, base), (330, base + 10), (470, base + 4)]:
        p.add(p.soft(E(cx, y, 60, 6, "#3a2c20"), 3, .5))


def pin_2(p):
    """A row of small matte cups on a dark walnut plank, cool grey-blue wall, leaf shadows."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#bcc6cb", "#a7b3b9")))
    rnd = random.Random(111)
    p.add(p.soft("".join(leaf(rnd.uniform(0, 540), rnd.uniform(0, 300), rnd.uniform(60, 110), rnd.uniform(20, 36), rnd.uniform(0, 360), "#6f7d86")
                         for _ in range(14)), 7, .35))
    y = 560
    p.add(p.soft(R(0, y + 40, w, 40, "#39434a"), 10, .5))
    p.add(R(-10, y, w + 20, 44, p.lg("#5e3f2a", "#3e2818")))
    p.add(R(-10, y, w + 20, 4, "#8a6448"))
    p.add(grain(p, 0, y + 4, w, 40, "#26170c", k=6, op=.5, seed=6))
    cups = [(64, 48, 124, "#f3efe7"), (168, 52, 100, "#d8c9ae"), (272, 49, 136, "#b35a36"), (376, 52, 110, "#8aa1b0"), (478, 46, 128, "#2e2d2f")]
    for (cx, r, ht, col) in cups:
        p.add(p.soft(E(cx - 16, y + 2, r, 6, "#1a120c"), 3, .5))
        p.add(lathe(cx, y + 2, [(r * .7, 0), (r * .92, 16), (r, ht * .7), (r * .98, ht)], matte(p, col)))
        p.add(E(cx, y + 2 - ht, r * .98, 7, dk(col, .2)))
        p.add(E(cx, y + 2 - ht, r * .98, 7, "none", stroke=lt(col, .3), stroke_width=1.4, opacity=.8))
        # a raw clay foot
        p.add(R(cx - r * .7, y - 6, r * 1.4, 8, "#c8a37e", rx=2))
    # below the plank: the wall again, darker
    p.add(R(0, y + 44, w, h - y - 44, p.lg("#8d9aa1", "#7c8a92")))


def ig_save_4(p):
    """Night: an architect lamp pours one cone of light onto a walnut desk and a closed laptop."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#141a2b", "#0c101b")))
    p.add(PL([(0, 480), (w, 440), (w, h), (0, h)], p.lg("#2a1c14", "#140d09")))
    p.add(p.soft(E(360, 560, 250, 110, "#ffcf87", opacity=.55), 30))
    p.add(p.soft(PL([(250, 190), (300, 170), (560, 560), (170, 600)], "#ffd99a", opacity=.12), 12))
    # desk edge
    p.add(PL([(0, 480), (w, 440), (w, 446), (0, 486)], "#6a4a34", opacity=.8))
    # laptop, closed, in the pool
    lap = [(250, 540), (470, 520), (520, 580), (270, 604)]
    p.add(p.soft(PL([(260, 560), (490, 540), (540, 600), (270, 626)], "#000"), 8, .7))
    p.add(PL([(270, 604), (520, 580), (520, 588), (270, 612)], "#5a5d63"))
    p.add(PL(lap, p.lg("#c9ccd1", "#8e9298", x2=1, y2=1)))
    p.add(p.soft(PL(subquad(lap, .2, .1, .7, .6), "#fff3dc"), 10, .6))
    # a pen beside it
    p.add(L(540, 610, 600, 590, "#1a1a1a", 5, stroke_linecap="round"))
    # the lamp: base, two arms, shade
    p.add(E(120, 560, 60, 14, "#0b0b0d"), E(120, 556, 56, 12, p.lg("#3a3d44", "#1b1c20")))
    p.add(L(120, 552, 170, 330, "#2c2f36", 8, stroke_linecap="round"))
    p.add(L(170, 330, 280, 190, "#2c2f36", 8, stroke_linecap="round"))
    p.add(C(170, 330, 9, "#44474f"))
    p.add(P("M246,160 L322,150 L346,230 L276,250 Z", p.lg("#3b3f48", "#1d2026", x2=1, y2=0)))
    p.add(E(311, 240, 38, 12, "#fff3d0", transform="rotate(-16 311 240)"))
    p.add(p.soft(E(311, 244, 30, 10, "#ffffff"), 4))
    p.add(p.soft(C(311, 244, 70, "#ffd99a", opacity=.45), 24))


def ig_save_7(p):
    """Two chairs, backs to us, facing a tall window: cool soft daylight, honey floorboards in perspective."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#dcdcd6", "#cfcfc8")))
    vx, vy = 320, 440
    p.add(PL([(0, 520), (w, 520), (w, h), (0, h)], p.lg("#c7a071", "#a8804f")))
    for i in range(-8, 9):
        p.add(L(vx + i * 30, 520, vx + i * 150, h, "#7e5a33", 2, opacity=.45))
    p.add(R(0, 510, w, 12, "#ecebe6"))
    # window
    wx, wy, ww, wh = 200, 70, 240, 440
    p.add(R(wx, wy, ww, wh, p.lg("#dbe7ee", "#c2d6df", "#a9c2a6")))
    p.add(p.soft(E(wx + 70, wy + 330, 100, 70, "#7fa27a", opacity=.7), 16))
    p.add(p.soft(E(wx + 190, wy + 360, 70, 60, "#90b28a", opacity=.7), 16))
    p.add(window_panes(wx, wy, ww, wh, "#f4f3ef", 12, cols=2, rows=4))
    # light spilling onto the floor
    p.add(p.soft(PL([(wx, 522), (wx + ww, 522), (wx + ww + 150, h), (wx - 150, h)], "#ffffff", opacity=.45), 16))
    p.add(p.soft(E(320, 300, 300, 260, "#ffffff", opacity=.25), 50))

    def chair(x, y, s, col):
        g = [R(-60, 40, 10, 160, col), R(50, 40, 10, 160, col),                 # back legs
             R(-54, 110, 12, 140, dk(col, .25)), R(42, 110, 12, 140, dk(col, .25)),  # front legs, further away
             R(-64, 110, 128, 16, lt(col, .1), rx=4),                             # seat edge
             R(-64, -80, 128, 22, lt(col, .15), rx=10)]                           # top rail
        for k in range(5):
            g.append(R(-44 + k * 20, -60, 7, 172, col))
        g.append(R(-60, -80, 10, 124, col))
        g.append(R(50, -80, 10, 124, col))
        return f'<g transform="translate({x} {y}) scale({s})">' + "".join(g) + "</g>"

    for (x, y, s, col) in [(200, 530, 1.0, "#2b2a28"), (450, 545, 1.05, "#b98a5c")]:
        p.add(p.soft(PL([(x - 60 * s, y + 200 * s), (x + 60 * s, y + 200 * s), (x + 90 * s, h), (x - 90 * s, h)], "#6a4a2a"), 10, .35))
        p.add(chair(x, y, s, col))


def ig_notice_1(p):
    """Late afternoon: a raking gold rectangle of sun and leaf shadows on a white wall, one black chair in it."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#e7e2dc", "#d6d0c9", x2=1, y2=1)))
    p.add(R(0, 640, w, 160, p.lg("#cbbfae", "#b8aa96")))
    p.add(R(0, 634, w, 8, "#f1ece6"))
    # the patch of sun, with the window's cross in it
    patch = [(150, 90), (560, 170), (600, 700), (230, 640)]
    p.add(p.soft(PL(patch, "#ffcf7a", opacity=.75), 4))
    p.add(p.soft(PL(subquad(patch, .1, .08, .9, .92), "#ffe6b0", opacity=.6), 16))
    p.add(PL(subquad(patch, .47, 0, .53, 1), "#d9c7c9", opacity=.9))
    p.add(PL(subquad(patch, 0, .47, 1, .52), "#d9c7c9", opacity=.9))
    rnd = random.Random(121)
    p.add(p.soft("".join(leaf(rnd.uniform(420, 620), rnd.uniform(120, 400), rnd.uniform(40, 70), rnd.uniform(14, 22), rnd.uniform(0, 360), "#b9a5b0")
                         for _ in range(10)), 3, .7))
    # chair in profile (a bentwood side chair) and its long shadow up the wall
    def chair(col):
        return (P("M0,0 C-6,-120 10,-230 36,-270", "none", stroke=col, stroke_width=11, stroke_linecap="round")
                + P("M0,-130 L120,-130", "none", stroke=col, stroke_width=12, stroke_linecap="round")
                + P("M110,-130 L126,0 M20,-130 L-4,0", "none", stroke=col, stroke_width=10, stroke_linecap="round")
                + P("M8,-60 C40,-50 90,-50 118,-60", "none", stroke=col, stroke_width=6)
                + P("M4,-150 C14,-190 20,-220 34,-250", "none", stroke=col, stroke_width=5))
    p.add(p.soft(f'<g transform="translate(470 640) skewX(-40) scale(1 .9)">{chair("#9d8e96")}</g>', 5, .6))
    p.add(f'<g transform="translate(250 700) scale(1.1)">{chair("#1b1b1c")}</g>')
    p.add(p.soft(E(320, 704, 110, 10, "#3a2f28"), 5, .4))


def pin_1(p):
    """Evening corner: teal walls, a tripod floor lamp's drum shade glowing over a rust velvet armchair."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, "#284847"))
    p.add(PL([(0, 0), (150, 60), (150, 620), (0, 700)], "#1d3736"))
    p.add(PL([(0, 700), (150, 620), (w, 620), (w, h), (0, h)], p.lg("#6a4a38", "#3c2a20")))
    p.add(p.soft(E(330, 300, 280, 330, "#ffcf87", opacity=.4), 60))
    p.add(p.soft(E(330, 690, 240, 60, "#ffcf87", opacity=.25), 20))
    # rug
    p.add(E(320, 710, 230, 56, p.rg("#e8dcc8", "#cbbba0")))
    # lamp: tripod legs, stem, drum shade glowing
    p.add(L(410, 690, 440, 250, "#1b1b1b", 4), L(470, 690, 440, 250, "#1b1b1b", 4), L(440, 700, 440, 250, "#2a2a2a", 4))
    p.add(p.soft(E(440, 200, 120, 90, "#ffd99a", opacity=.6), 20))
    p.add(P("M380,140 L500,140 L512,250 L368,250 Z", p.lg("#fff2d0", "#f5d79a", "#e9b964", x2=1, y2=0)))
    p.add(E(440, 250, 72, 10, "#fffbe8"))
    p.add(p.soft(PL([(368, 250), (512, 250), (620, 700), (260, 700)], "#ffe0a0", opacity=.12), 10))
    # armchair (rust velvet), three-quarter
    p.add(p.soft(E(270, 690, 160, 24, "#1b120c"), 8, .7))
    p.add(P("M140,420 C140,340 400,340 400,420 L404,560 L136,560 Z", p.lg("#c05a38", "#8f3a22", x2=1, y2=0)))
    p.add(P("M120,500 C110,470 170,460 176,500 L176,660 L124,660 Z", p.lg("#b14f30", "#7a2f1c", x2=1, y2=0)))
    p.add(P("M360,500 C356,462 420,460 420,500 L420,660 L364,660 Z", p.lg("#d06a44", "#9a4226", x2=1, y2=0)))
    p.add(R(170, 560, 196, 70, p.lg("#d06a44", "#a8472a"), rx=18))
    p.add(R(176, 626, 186, 34, "#7a2f1c", rx=8))
    p.add(p.soft(P("M170,380 C220,360 330,360 380,392", "none", stroke="#ffb487", stroke_width=10, opacity=.45), 6))
    for x in (140, 404):
        p.add(R(x - 4, 660, 10, 28, "#2a1a10"))
    # side table and a book
    p.add(R(520, 540, 90, 10, "#3a2618"), R(560, 550, 10, 130, "#3a2618"), R(530, 680, 70, 8, "#3a2618"))
    p.add(R(530, 526, 64, 14, "#d9c6a2", rx=2), R(532, 516, 58, 10, "#4f6b6a", rx=2))


def pin_0(p):
    """Open kitchen shelves on terracotta-pink limewash: stacked plates, jars of pasta and lentils, a trailing plant."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#dca792", "#cf9580", x2=1, y2=1)))
    rnd = random.Random(131)
    p.add(p.soft("".join(P(blob(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(60, 140), rnd.uniform(40, 90), rnd), "#e8bca8")
                         for _ in range(8)), 20, .5))
    oak = p.lg("#d2ae82", "#b48a5c")
    for y in (300, 540):
        p.add(p.soft(R(20, y + 18, 500, 24, "#6e3f30"), 8, .4))
        p.add(R(20, y, 500, 22, oak), R(20, y, 500, 3, "#ecd0a8"))
    # top shelf: plate stack, bowl stack, a jug, a plant trailing
    for i in range(7):
        p.add(E(110, 296 - i * 7, 70, 9, "#f4efe6" if i % 2 else "#e7e0d4"))
    p.add(E(110, 247, 70, 9, "#faf7f2"))
    for i, col in enumerate(("#6f8f98", "#9fb7bd", "#e9e2d4")):
        p.add(lathe(250, 300 - i * 22, [(26, 0), (46, 16), (52, 24)], matte(p, col)))
    p.add(lathe(370, 300, [(30, 0), (40, 50), (32, 100), (24, 116), (30, 130)], matte(p, "#f0e9dc")))
    p.add(lathe(460, 300, [(32, 0), (38, 50), (42, 64)], matte(p, "#b85b3c")))
    for sgn, vx, ln in [(-1, 460, 220), (1, 480, 150)]:
        pts = [(vx, 236)] + [(vx + sgn * (k * 10) + rnd.uniform(-6, 6), 236 + k * ln / 6) for k in range(1, 7)]
        p.add(P(smooth(pts, closed=False), "none", stroke="#46642f", stroke_width=2.5))
        for (lx, ly) in pts[1:]:
            p.add(leaf(lx, ly, 26, 12, rnd.uniform(150, 210), rnd.choice(["#4f8a3a", "#6ea34a"])))
    for k in range(7):
        p.add(leaf(460 + rnd.uniform(-30, 30), 236, 30, 13, rnd.uniform(-70, 70), rnd.choice(["#4f8a3a", "#3f7a33"])))
    # lower shelf: glass jars with contents
    jars = [(80, 60, 150, "#f2c65a", "pasta"), (180, 54, 120, "#d9772f", "lentils"), (280, 58, 170, "#f3ede0", "beans"),
            (390, 50, 110, "#8a5a2f", "coffee"), (475, 44, 140, "#e9d9b0", "oats")]
    for (cx, jw, jh, col, kind) in jars:
        y = 540
        p.add(R(cx - jw / 2, y - jh, jw, jh, "#ffffff", rx=10, opacity=.25))
        fill_h = jh * .72
        p.add(R(cx - jw / 2 + 4, y - fill_h, jw - 8, fill_h - 3, col, rx=6))
        if kind == "pasta":
            for k in range(12):
                yy = y - fill_h + 8 + k * 9
                p.add(L(cx - jw / 2 + 6, yy, cx + jw / 2 - 6, yy + 4, "#d9a53a", 2))
        else:
            p.add(flour(p, (cx - jw / 2 + 6, y - fill_h + 4, cx + jw / 2 - 6, y - 6), 26, rnd, col=dk(col, .3), op=.8))
        p.add(R(cx - jw / 2 - 2, y - jh - 12, jw + 4, 14, "#c9a57a", rx=3))
        p.add(R(cx - jw / 2 + 6, y - jh + 6, 6, jh - 14, "#ffffff", rx=3, opacity=.45))
    # cups hanging from hooks under the top shelf
    for x in (160, 240, 320):
        p.add(L(x, 322, x, 336, "#2b2b2b", 2))
        p.add(cup_side(p, x + 4, 390, 44, 44, "#f0e9dc", handle="left", persp=.18))
    # counter at the bottom
    p.add(R(0, 740, w, 70, p.lg("#e8e3da", "#cfc8bc")))
    p.add(R(0, 736, w, 6, "#fbf9f5"))


def pin_3(p):
    """A narrow hallway in one-point perspective: sage wainscot, a slim oak bench, coats on hooks, a lit doorway."""
    w, h = p.w, p.h
    vx, vy = 300, 360
    fx0, fx1, fy0, fy1 = 230, 370, 250, 500      # far wall
    p.add(PL([(0, 0), (w, 0), (fx1, fy0), (fx0, fy0)], "#f1ede6"))                  # ceiling
    p.add(PL([(0, 0), (fx0, fy0), (fx0, fy1), (0, h)], p.lg("#ebe6dd", "#d9d2c6", x2=1, y2=0)))   # left wall
    p.add(PL([(w, 0), (fx1, fy0), (fx1, fy1), (w, h)], p.lg("#cfc8bb", "#e2dcd2", x2=1, y2=0)))   # right wall
    p.add(PL([(0, h), (fx0, fy1), (fx1, fy1), (w, h)], p.lg("#b58d62", "#8d6a44")))  # floor
    # wainscot, sage, on both walls
    def wall_pt(side, t, v):
        # t: 0 near .. 1 far, v: 0 top .. 1 floor
        if side == "l":
            x = 0 + (fx0 - 0) * t
            top, bot = 0 + (fy0 - 0) * t, h + (fy1 - h) * t
        else:
            x = w + (fx1 - w) * t
            top, bot = 0 + (fy0 - 0) * t, h + (fy1 - h) * t
        return x, top + (bot - top) * v
    for side, col in (("l", "#8fa38a"), ("r", "#7d9178")):
        p.add(PL([wall_pt(side, 0, .55), wall_pt(side, 1, .55), wall_pt(side, 1, 1), wall_pt(side, 0, 1)], col))
        p.add(PL([wall_pt(side, 0, .55), wall_pt(side, 1, .55), wall_pt(side, 1, .56), wall_pt(side, 0, .57)], "#f3f0ea"))
    # the far wall: an open door full of light
    p.add(R(fx0, fy0, fx1 - fx0, fy1 - fy0, "#e6e0d4"))
    p.add(R(270, 330, 62, 170, p.lg("#fffaf0", "#ffe9bf")))
    p.add(p.soft(PL([(270, 500), (332, 500), (420, 810), (180, 810)], "#fff3d6", opacity=.5), 14))
    # runner rug
    p.add(PL([(250, 800), (290, 500), (312, 500), (360, 800)], "#a2433a"))
    p.add(PL([(262, 800), (293, 510), (309, 510), (348, 800)], "none", stroke="#e7c9a0", stroke_width=3))
    # bench along the left wall
    b = [wall_pt("l", .05, .72), wall_pt("l", .55, .72), (fx0 * .55 + 24, wall_pt("l", .55, .72)[1] + 16), (40, wall_pt("l", .05, .72)[1] + 50)]
    p.add(p.soft(PL([(0, 690), (140, 520), (170, 530), (60, 760)], "#4a3a2a"), 8, .35))
    p.add(PL(b, p.lg("#d0a674", "#b0844f")))
    for t in (.1, .45):
        x, y = wall_pt("l", t, .72)
        p.add(L(x + 26 - t * 10, y + 30 - t * 20, x + 26 - t * 10, wall_pt("l", t, 1)[1] - 10 + t * 10, "#6e4f2c", 8 - t * 5))
    # hooks, a coat, a tote
    for t in (.12, .3, .45):
        x, y = wall_pt("l", t, .28)
        p.add(C(x, y, 6 - t * 4, "#1c1c1c"))
    x, y = wall_pt("l", .12, .28)
    p.add(P(f"M{x},{y} C{x + 40},{y + 20} {x + 50},{y + 160} {x + 30},{y + 260} L{x - 10},{y + 250} C{x - 20},{y + 140} {x - 10},{y + 40} {x},{y} Z", p.lg("#4a5a6e", "#2f3c4d", x2=1, y2=0)))
    x, y = wall_pt("l", .3, .28)
    p.add(P(f"M{x - 4},{y} L{x - 20},{y + 60} M{x + 4},{y} L{x + 20},{y + 60}", "none", stroke="#c9a26a", stroke_width=3))
    p.add(R(x - 30, y + 58, 60, 70, "#e3d3b4", rx=4))
    x, y = wall_pt("l", .45, .28)
    p.add(P(f"M{x},{y} C{x + 16},{y + 20} {x + 20},{y + 60} {x + 10},{y + 110} L{x - 8},{y + 106} C{x - 12},{y + 60} {x - 6},{y + 20} {x},{y} Z", "#b8573a"))
    # a round mirror on the right wall
    p.add(E(508, 300, 34, 60, "#c9a26a"), E(508, 300, 28, 52, p.lg("#f7f3ea", "#d9d2c4")))


def pin_4(p):
    """A kitchen wall of square white tiles with dark grout; an oak shelf with oil, bowls, a board; a brass tap."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, "#4a4a4c"))
    s = 66
    rnd = random.Random(141)
    for j in range(-1, 13):
        for i in range(-1, 9):
            x, y = i * s + 2, j * s + 2 - 20
            p.add(R(x, y, s - 4, s - 4, p.lg(lt("#eceae4", rnd.uniform(0, .5)), "#e2dfd7", "#d5d2c9", x2=1, y2=1), rx=2))
    p.add(p.soft(PL([(0, 0), (260, 0), (80, 810), (0, 810)], "#ffffff", opacity=.25), 30))
    p.add(p.soft(R(0, 0, w, h, "none", stroke="#000", stroke_width=90), 50, .25))
    y = 360
    p.add(p.soft(R(30, y + 20, 480, 26, "#1b1b1c"), 10, .45))
    p.add(R(20, y, 500, 26, p.lg("#d4ad7e", "#ad8252")), R(20, y, 500, 3, "#f0d3a8"))
    # on the shelf: an oil bottle, bowls, a leaning board, a small plant
    p.add(lathe(90, y, [(22, 0), (24, 90), (8, 120), (7, 150), (9, 156)], p.lg("#6e7a2a", "#9aa63a", "#4a5418", x2=1, y2=0)))
    p.add(R(81, y - 164, 18, 12, "#1c1c1c", rx=2))
    for i, col in enumerate(("#2f3134", "#d9cdb4")):
        p.add(lathe(200, y - i * 24, [(30, 0), (50, 18), (56, 26)], matte(p, col)))
    p.add(R(300, y - 230, 110, 230, p.lg("#c89a64", "#9c6e3a", x2=1, y2=0), rx=40, transform=f"rotate(-8 355 {y})"))
    p.add(C(346, y - 206, 9, "#2c2c2e", transform=f"rotate(-8 355 {y})"))
    p.add(lathe(465, y, [(24, 0), (30, 40), (32, 50)], matte(p, "#f2eee6")))
    for k in range(9):
        p.add(leaf(465 + rnd.uniform(-20, 20), y - 50, 44, 12, rnd.uniform(-50, 50), rnd.choice(["#3f7a33", "#5a9a44"])))
    # counter and a brass tap
    p.add(R(0, 690, w, 120, p.lg("#3a3b3d", "#1f2021")))
    p.add(R(0, 686, w, 6, "#5a5b5e"))
    p.add(R(380, 560, 16, 130, p.lg("#e8c27a", "#b8893a", "#7a5a22", x2=1, y2=0)))
    p.add(P("M388,566 C388,500 470,500 470,560 L470,590", "none", stroke="#c9a04a", stroke_width=14, stroke_linecap="round"))
    p.add(R(350, 640, 20, 40, "#c9a04a", rx=4))


def pin_5(p):
    """A cork board in an oak frame: pinned sketches, paint chips, fabric swatches, coloured pins."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#b88c5e", "#9c7246")))
    p.add(R(20, 20, w - 40, h - 40, p.lg("#c9985f", "#b8864e", x2=1, y2=1)))
    rnd = random.Random(151)
    p.add(flour(p, (20, 20, w - 20, h - 20), 220, rnd, col="#7a5228", op=.55))
    p.add(flour(p, (20, 20, w - 20, h - 20), 90, rnd, col="#e8c08a", op=.6))
    p.add(p.soft(R(20, 20, w - 40, h - 40, "none", stroke="#3a2412", stroke_width=20), 8, .5))

    def pinned(x, y, wd, ht, rot, inner, pin_col):
        sh = p.soft(f'<g transform="translate({x + 8} {y + 10}) rotate({rot})">{R(0, 0, wd, ht, "#3a2412")}</g>', 6, .45)
        g = f'<g transform="translate({x} {y}) rotate({rot})">' + inner + C(wd / 2, 12, 8, pin_col) + C(wd / 2 - 2, 10, 3, "#ffffff", opacity=.6) + "</g>"
        return sh + g

    def sketch(wd, ht, kind):
        out = R(0, 0, wd, ht, "#faf8f2")
        if kind == "chair":
            out += P(f"M{wd * .3},{ht * .2} L{wd * .32},{ht * .6} L{wd * .7},{ht * .6} M{wd * .32},{ht * .6} L{wd * .3},{ht * .9} M{wd * .7},{ht * .6} L{wd * .72},{ht * .9}",
                     "none", stroke="#5a5a5a", stroke_width=2.2, stroke_linecap="round")
        elif kind == "lamp":
            out += P(f"M{wd * .5},{ht * .85} L{wd * .5},{ht * .35} M{wd * .3},{ht * .85} L{wd * .7},{ht * .85} M{wd * .3},{ht * .35} L{wd * .7},{ht * .35} L{wd * .62},{ht * .16} L{wd * .38},{ht * .16} Z",
                     "none", stroke="#5a5a5a", stroke_width=2.2)
        else:
            for k in range(4):
                out += P(f"M{wd * .12},{ht * (.25 + k * .17)} C{wd * .4},{ht * (.15 + k * .17)} {wd * .6},{ht * (.35 + k * .17)} {wd * .88},{ht * (.25 + k * .17)}",
                         "none", stroke="#7a7a7a", stroke_width=1.8)
        return out

    def chip(wd, ht, cols):
        out = R(0, 0, wd, ht, "#ffffff")
        for k, c in enumerate(cols):
            out += R(6, 24 + k * (ht - 30) / len(cols), wd - 12, (ht - 30) / len(cols) - 4, c)
        return out

    def fabric(wd, ht, col, stripe=None):
        out = R(0, 0, wd, ht, col)
        if stripe:
            for k in range(0, int(wd), 12):
                out += R(k, 0, 5, ht, stripe, opacity=.6)
        return out

    p.add(pinned(50, 60, 200, 240, -4, sketch(200, 240, "chair"), "#e0503a"))
    p.add(pinned(280, 50, 180, 210, 5, sketch(180, 210, "lamp"), "#2f6bd6"))
    p.add(pinned(390, 290, 100, 260, -6, chip(100, 260, ["#c05a38", "#d98b5f", "#e8b893", "#f3dccb"]), "#f2c14a"))
    p.add(pinned(60, 340, 110, 280, 3, chip(110, 280, ["#2f5250", "#4f7a76", "#8fb3ac", "#cfe0da"]), "#e0503a"))
    p.add(pinned(200, 330, 170, 150, 8, fabric(170, 150, "#d9c8a8", "#b89a6a"), "#3a8a5a"))
    p.add(pinned(210, 510, 160, 130, -7, fabric(160, 130, "#6b7fa3"), "#f2c14a"))
    p.add(pinned(300, 610, 200, 150, 4, sketch(200, 150, "curves"), "#2f6bd6"))
    p.add(pinned(40, 640, 150, 120, -3, R(0, 0, 150, 120, "#fff") + R(8, 8, 134, 86, p.lg("#8fb6d6", "#e8c9a0")) + P("M8,80 L50,50 L80,70 L110,40 L142,70 L142,94 L8,94 Z", "#5a7a4a"), "#e0503a"))


def tt_save_3(p):
    """A mint pegboard wall, tools hung neatly: hammer, screwdrivers, wrenches, pliers, saw, tape, twine."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#bcd6c6", "#a9c6b5")))
    holes = []
    for j in range(0, 44):
        for i in range(0, 25):
            holes.append(C(12 + i * 18, 10 + j * 18, 2.3, "#6f8a7a"))
    p.add(G(*holes, opacity=.55))
    p.add(p.soft(R(0, 0, w, h, "none", stroke="#46604f", stroke_width=60), 30, .25))

    def hung(item, dx=6, dy=8):
        return p.soft(f'<g transform="translate({dx} {dy})">{item}</g>', 5, .35) + item

    def mono(item):
        import re
        return re.sub(r'fill="(?!none)[^"]*"', 'fill="#2f463a"', re.sub(r'stroke="(?!none)[^"]*"', 'stroke="#2f463a"', item))

    def put(item):
        p.add(p.soft(f'<g transform="translate(6 8)">{mono(item)}</g>', 5, .35))
        p.add(item)

    # hammer
    put(R(60, 90, 22, 230, p.lg("#d9a86a", "#a8773f", x2=1, y2=0), rx=8) + R(28, 70, 90, 34, p.lg("#5a6068", "#2a2e33"), rx=6))
    # saw
    put(P("M170,70 L230,70 L260,380 L170,380 Z", p.lg("#e6e9ec", "#a9b0b6", x2=1, y2=0))
        + P("".join(f"M{170 + 0},{80 + k * 12} l-8,6 l8,6" for k in range(25)), "none", stroke="#8a9096", stroke_width=1.5)
        + R(160, 20, 90, 60, "#c0473a", rx=18) + R(186, 38, 40, 22, "#bcd6c6", rx=10))
    # screwdrivers
    for i, col in enumerate(("#e2b23a", "#d44c3a", "#2f6bd6", "#1c1c1c")):
        x = 300 + i * 34
        put(R(x - 9, 80, 18, 70, col, rx=8) + R(x - 3, 150, 6, 90 - i * 10, "#b9c0c6"))
    # wrenches in size order
    for i in range(5):
        x = 60 + i * 34
        ln = 110 + i * 22
        put(R(x - 5, 420, 10, ln, p.lg("#e3e6e9", "#9aa1a8", x2=1, y2=0), rx=5) + C(x, 420, 12 + i, "#c4c9ce") + C(x, 412, 5 + i * .6, "#bcd6c6"))
    # pliers
    put(P("M290,420 L276,560 M310,420 L324,560", "none", stroke="#b9c0c6", stroke_width=10, stroke_linecap="round")
        + P("M276,540 L262,660 M324,540 L338,660", "none", stroke="#d44c3a", stroke_width=16, stroke_linecap="round")
        + C(300, 480, 8, "#8a9096"))
    # tape measure and twine
    put(C(390, 470, 38, "#f2c230") + C(390, 470, 16, "#1c1c1c") + R(424, 490, 20, 10, "#1c1c1c"))
    put(R(360, 560, 64, 80, "#d9c39a", rx=10) + "".join(L(360, 568 + k * 8, 424, 568 + k * 8, "#b8a070", 2) for k in range(9)))
    # shelf with jars of screws
    p.add(p.soft(R(20, 730, 410, 20, "#2f463a"), 6, .4))
    p.add(R(10, 712, 430, 18, p.lg("#d2ae82", "#a8804f")))
    for i, col in enumerate(("#b98a3a", "#8a9096", "#c9a04a", "#6f757c")):
        x = 70 + i * 100
        p.add(R(x - 28, 640, 56, 72, "#ffffff", rx=8, opacity=.3), R(x - 24, 668, 48, 42, col, rx=5, opacity=.8),
              R(x - 30, 632, 60, 12, "#e04a3a", rx=3))


DRAW.update({
    "shot-14": shot_14, "ig-save-1": ig_save_1, "ig-save-2": ig_save_2, "pin-2": pin_2, "ig-save-4": ig_save_4,
    "ig-save-7": ig_save_7, "ig-notice-1": ig_notice_1, "pin-1": pin_1, "pin-0": pin_0, "pin-3": pin_3,
    "pin-4": pin_4, "pin-5": pin_5, "tt-save-3": tt_save_3,
})


# ── craft, tiles and paper ────────────────────────────────────────────────


def ig_save_8(p):
    """A wet clay bowl on the wheel, high three-quarter view: grey splash pan, slip, a sponge and a rib."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#8f8b84", "#77736c")))
    rnd = random.Random(161)
    p.add(p.soft("".join(P(blob(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(8, 20), rnd.uniform(5, 12), rnd), "#9c8672") for _ in range(12)), 2, .5))
    cx, cy = 320, 470
    p.add(p.soft(E(cx + 10, cy + 40, 300, 180, "#2e2b27"), 18, .6))
    p.add(E(cx, cy, 300, 180, p.lg("#c3ccd1", "#98a3aa")))
    p.add(E(cx, cy + 6, 262, 152, p.lg("#6f7a80", "#8d989e")))
    p.add(E(cx, cy + 14, 250, 142, p.rg("#8f705a", "#6e523f", "#5a4230", cx=.5, cy=.6)))
    p.add(p.soft(E(cx - 90, cy - 40, 60, 16, "#d9c2ae", opacity=.5), 6))
    # wheel head, with spin streaks
    p.add(E(cx, cy + 10, 190, 104, p.lg("#6c7075", "#44484c")))
    for k in range(4):
        p.add(E(cx, cy + 10, 170 - k * 34, 93 - k * 19, "none", stroke="#8b9095", stroke_width=1.5, opacity=.5))
    for k in range(5):
        a0 = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(.55, .95)
        x0, y0 = cx + math.cos(a0) * 190 * rr, cy + 10 + math.sin(a0) * 104 * rr
        x1, y1 = cx + math.cos(a0 + .7) * 190 * rr, cy + 10 + math.sin(a0 + .7) * 104 * rr
        p.add(P(f"M{n(x0)},{n(y0)} A{n(190 * rr)},{n(104 * rr)} 0 0 1 {n(x1)},{n(y1)}", "none", stroke="#c9ced3", stroke_width=2.5, opacity=.35))
    # the bowl: body, rim, inside
    clay = p.lg((0, "#5e2e1a"), (.25, "#9c5536"), (.45, "#b8694a"), (.7, "#86432a"), (1, "#4a2213"), x2=1, y2=0)
    p.add(P(f"M{cx - 70},{cy + 40} C{cx - 110},{cy + 10} {cx - 150},{cy - 60} {cx - 156},{cy - 110} L{cx + 156},{cy - 110} C{cx + 150},{cy - 60} {cx + 110},{cy + 10} {cx + 70},{cy + 40} C{cx + 30},{cy + 58} {cx - 30},{cy + 58} {cx - 70},{cy + 40} Z", clay))
    for k in range(4):
        yy = cy - 90 + k * 30
        rx_ = 150 - k * 22
        p.add(P(f"M{cx - rx_},{yy} A{rx_},{rx_ * .3} 0 0 0 {cx + rx_},{yy}", "none", stroke="#4a2213", stroke_width=2.5, opacity=.5))
        p.add(P(f"M{cx - rx_},{yy + 4} A{rx_},{rx_ * .3} 0 0 0 {cx + rx_},{yy + 4}", "none", stroke="#e3a07a", stroke_width=1.5, opacity=.5))
    p.add(E(cx, cy - 110, 156, 62, "#8a4a2e"))
    p.add(E(cx, cy - 106, 146, 56, p.rg("#5a2a17", "#7a3d25", "#9c5536", cx=.5, cy=.65, r=.6)))
    for k in range(3):
        p.add(E(cx, cy - 96 + k * 8, 110 - k * 32, 40 - k * 12, "none", stroke="#b8694a", stroke_width=2, opacity=.45))
    p.add(E(cx, cy - 110, 156, 62, "none", stroke="#d98a64", stroke_width=3, opacity=.8))
    # wet shine
    p.add(p.soft(P(f"M{cx - 120},{cy - 80} C{cx - 110},{cy - 30} {cx - 80},{cy + 10} {cx - 50},{cy + 30}", "none", stroke="#fff1e6", stroke_width=8, opacity=.5), 3))
    p.add(p.soft(E(cx - 60, cy - 130, 40, 8, "#fff1e6", opacity=.5), 3))
    # sponge and rib on the pan's rim
    p.add(p.soft(R(470, 330, 80, 50, "#2e2b27", rx=14, transform="rotate(20 510 355)"), 5, .5))
    p.add(R(462, 320, 80, 50, p.lg("#f3d25a", "#d9b23a"), rx=14, transform="rotate(20 502 345)"))
    p.add(P("M90,560 C120,520 200,520 230,560 C200,576 120,576 90,560 Z", p.lg("#c9a26a", "#9c7440")))


def ig_save_11(p):
    """A front-loading kiln thrown open: shelves of pots glowing orange-white, the door's brick face swung aside."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#1c1512", "#0f0b09")))
    p.add(R(0, 680, w, 120, p.lg("#2a1d16", "#15100c")))
    p.add(p.soft(E(290, 720, 300, 60, "#ff8a3a", opacity=.35), 30))
    p.add(p.soft(E(290, 400, 280, 320, "#ff7a2a", opacity=.3), 60))
    # kiln body
    p.add(R(70, 120, 420, 580, p.lg("#3a3a3c", "#2a2a2c", "#1e1e20", x2=1, y2=0), rx=10))
    for x in (90, 470):
        for y in range(150, 690, 60):
            p.add(C(x, y, 4, "#58585c"))
    # chamber
    ch = (120, 170, 320, 480)
    p.add(R(*ch, p.rg((0, "#fff6c8"), (.35, "#ffc45a"), (.75, "#f26a1c"), (1, "#8a2a0a"), cx=.5, cy=.5, r=.7)))
    for j in range(12):
        p.add(L(120, 170 + j * 40, 440, 170 + j * 40, "#b8420f", 1.5, opacity=.4))
    # shelves and posts
    shelves = [300, 440, 580]
    for y in shelves:
        p.add(R(128, y, 304, 14, p.lg("#ffe2a0", "#e8903a")))
        p.add(R(140, y + 14, 12, 126 if y < 580 else 66, "#f2a24a"), R(408, y + 14, 12, 126 if y < 580 else 66, "#f2a24a"))
    # pots, glowing (tinted by their glazes)
    pots = [
        (190, 300, [(20, 0), (34, 40), (26, 80), (14, 96), (18, 106)], "#ffd27a"),
        (270, 300, [(26, 0), (44, 24), (48, 44)], "#ffe7a0"),
        (360, 300, [(22, 0), (30, 50), (30, 90)], "#ffbf6a"),
        (200, 440, [(28, 0), (46, 20), (52, 36)], "#ffe39a"),
        (300, 440, [(24, 0), (40, 60), (34, 100), (22, 116)], "#ffca70"),
        (385, 440, [(18, 0), (24, 60), (24, 70)], "#ffd88a"),
        (230, 580, [(30, 0), (50, 30), (54, 50)], "#ffcd7a"),
        (340, 580, [(22, 0), (40, 50), (30, 86), (20, 96)], "#ffe0a0"),
    ]
    for (x, y, prof, col) in pots:
        p.add(lathe(x, y, prof, p.lg(lt(col, .5), col, dk(col, .25), x2=1, y2=0)))
        p.add(E(x, y - prof[-1][1], prof[-1][0], prof[-1][0] * .25, dk(col, .35)))
    p.add(p.soft(R(*ch, "#ffffff", opacity=.12), 8))
    # the door, swung open to the right in perspective
    door = [(492, 150), (600, 110), (600, 740), (492, 690)]
    p.add(PL(door, p.lg("#e0a060", "#b8682e", x2=1, y2=0)))
    for j in range(1, 12):
        p.add(PL([quadpt(door, 0, j / 12), quadpt(door, 1, j / 12)], "none", stroke="#8a4a1e", stroke_width=2))
    for j in range(12):
        for i in (1, 2):
            u = (i / 3) + (.16 if j % 2 else 0)
            if u < 1:
                x0_, y0_ = quadpt(door, u, j / 12)
                x1_, y1_ = quadpt(door, u, (j + 1) / 12)
                p.add(L(x0_, y0_, x1_, y1_, "#8a4a1e", 1.5))
    p.add(PL([(600, 110), (622, 118), (622, 746), (600, 740)], "#2a2a2c"))
    p.add(p.soft(PL(door, "#ff9a4a", opacity=.3), 6))
    # heat shimmer above the opening
    p.add(p.soft(P("M160,170 C200,120 180,80 230,40 M300,170 C330,130 300,90 350,50 M400,170 C420,120 400,90 440,60", "none", stroke="#ffb870", stroke_width=10, opacity=.18), 8))


def ig_like_2(p):
    """Macro from just below: a slim black steel bracket under an oak shelf, raking sun, its shadow on plaster."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#d8d1c6", "#c2baae", x2=1, y2=1)))
    p.add(p.soft(PL([(640, 0), (640, 800), (200, 800)], "#fff4e0", opacity=.35), 40))
    # the shelf's shadow on the wall, and the bracket's, falling down-left
    p.add(p.soft(PL([(0, 330), (640, 330), (640, 380), (0, 440)], "#6e6456"), 10, .35))
    p.add(p.soft(PL([(352, 330), (374, 330), (250, 640), (228, 640)], "#5e5448"), 5, .45))
    # front face and underside of the shelf
    p.add(PL([(0, 290), (640, 290), (640, 332), (0, 332)], p.lg("#b88752", "#9a6c3c")))
    p.add(R(0, 200, w, 92, p.lg("#e0b27a", "#cf9f64", "#b98a52")))
    p.add(grain(p, 0, 204, w, 84, "#8a5a2a", k=12, op=.4, seed=17, wav=10))
    p.add(R(0, 200, w, 4, "#f4d3a3"))
    p.add(p.soft(R(0, 286, w, 8, "#5a3a1a"), 3, .5))
    # a leaf of a plant trailing over the edge
    p.add(P("M120,200 C118,240 130,280 150,330", "none", stroke="#3f6b2f", stroke_width=3))
    p.add(leaf(150, 330, 50, 20, 170, "#4f8a3a", vein="#a6c98a"))
    p.add(leaf(128, 262, 40, 16, 210, "#5f9a44", vein="#a6c98a"))
    # bracket: arm along the underside, plate down the wall
    p.add(PL([(330, 292), (360, 292), (374, 332), (352, 332)], "#1b1b1c"))
    p.add(PL([(330, 292), (336, 292), (356, 332), (352, 332)], "#5a5a5e"))
    p.add(R(352, 332, 22, 250, p.lg("#2a2a2c", "#0e0e0f", x2=1, y2=0), rx=2))
    p.add(R(354, 336, 4, 240, "#6a6a70", opacity=.6))
    for y in (380, 520):
        p.add(C(363, y, 6, "#3a3a3e"), L(359, y, 367, y, "#0a0a0a", 1.8))
    p.add(P("M352,582 L374,582 L374,588 Q363,596 352,588 Z", "#0e0e0f"))


def tile(p, x, y, s, col, rot=0, gloss=True, rnd=None, sh=0.4):
    g = [R(-s / 2, -s / 2, s, s, p.lg(lt(col, .12), col, dk(col, .18), x2=1, y2=1), rx=3)]
    if rnd:
        g.append(P(blob(rnd.uniform(-s * .2, s * .2), rnd.uniform(-s * .2, s * .2), s * .32, s * .22, rnd), dk(col, .12), opacity=.35))
    if gloss:
        g.append(PL([(-s / 2 + 4, -s / 2 + 4), (s * .1, -s / 2 + 4), (-s / 2 + 4, s * .1)], "#ffffff", opacity=.28))
    g.append(R(-s / 2, -s / 2, s, s, "none", rx=3, stroke=lt(col, .35), stroke_width=1.5, opacity=.6))
    shadow = p.soft(f'<g transform="translate({n(x + 5)} {n(y + 7)}) rotate({n(rot)})">{R(-s / 2, -s / 2, s, s, "#000", rx=3)}</g>', 5, sh)
    return shadow + f'<g transform="translate({n(x)} {n(y)}) rotate({n(rot)})">' + "".join(g) + "</g>"


def file_3(p):
    """Top-down on pale grey concrete: tile samples in greens and whites, loosely gridded, a carpenter's pencil."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#c6c3bd", "#b3b0aa", x2=1, y2=1)))
    rnd = random.Random(171)
    p.add(p.soft("".join(P(blob(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(40, 120), rnd.uniform(30, 80), rnd), rnd.choice(["#bdb9b2", "#cfccc6"])) for _ in range(14)), 18, .7))
    cols = ["#2f6b4f", "#f3f1ea", "#7fa88a", "#e9e4d6", "#1f4a3a", "#a9c4b0", "#fafaf6", "#4c8a6a"]
    k = 0
    for j in range(2):
        for i in range(4):
            x = 150 + i * 170 + rnd.uniform(-10, 10)
            y = 180 + j * 200 + rnd.uniform(-10, 10)
            s_ = 130 if (i + j) % 3 else 120
            p.add(tile(p, x, y, s_, cols[k], rnd.uniform(-5, 5), rnd=rnd))
            k += 1
    # a subway sample leaning over two squares
    p.add(f'<g transform="rotate(-8 400 520)">{tile(p, 400, 520, 90, "#5f9a7a", rnd=rnd)}{tile(p, 490, 520, 90, "#5f9a7a", rnd=rnd)}</g>')
    p.add(p.soft(R(600, 510, 170, 16, "#000", transform="rotate(-24 690 520)"), 4, .4))
    p.add(R(590, 500, 170, 16, "#e9b43a", rx=2, transform="rotate(-24 680 508)"))
    p.add(PL([(750, 470), (772, 460), (768, 470)], "#3a3a3a", transform="rotate(-24 680 508)"))


def file_5(p):
    """Looking down into an open cardboard box: a stack of square green tiles, their edges showing, packing paper."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#8a8f86", "#6e7369")))
    p.add(p.soft(R(0, 0, w, h, "none", stroke="#000", stroke_width=100), 40, .35))
    # box in perspective: rim quad, inner walls, flaps
    rim = [(170, 150), (640, 130), (700, 520), (120, 540)]
    p.add(p.soft(PL([(140, 170), (680, 150), (740, 570), (100, 590)], "#000"), 16, .6))
    p.add(PL([(170, 150), (40, 60), (500, 40), (640, 130)], p.lg("#b8905e", "#a37c4c")))       # back flap
    p.add(PL([(640, 130), (780, 90), (800, 470), (700, 520)], p.lg("#c29a66", "#a8804f", x2=1, y2=0)))  # right flap
    p.add(PL([(120, 540), (700, 520), (740, 600), (80, 600)], p.lg("#d4ad78", "#c29a66")))   # front flap
    p.add(PL([(170, 150), (120, 540), (10, 560), (60, 180)], p.lg("#a8804f", "#c29a66", x2=1, y2=0)))  # left flap
    p.add(PL(rim, "#6e5232"))
    inner = [(200, 180), (610, 164), (660, 490), (160, 506)]
    p.add(PL(inner, "#4a3520"))
    # crumpled paper around the stack
    rnd = random.Random(181)
    for _ in range(7):
        p.add(P(blob(rnd.uniform(200, 620), rnd.uniform(200, 480), rnd.uniform(40, 70), rnd.uniform(24, 40), rnd), "#efe8da"))
    # the stack: edges (layer lines) then the top tile
    top = [(260, 220), (560, 210), (590, 420), (230, 432)]
    for k in range(9, 0, -1):
        off = k * 7
        q = [(x, y + off) for (x, y) in top]
        p.add(PL(q, "#2f6b4f" if k % 2 else "#d9cfbd"))
    p.add(PL(top, p.lg("#5aa27c", "#2f7a55", "#1f5a3e", x2=1, y2=1)))
    p.add(PL([(262, 224), (400, 218), (268, 330)], "#ffffff", opacity=.22))
    p.add(PL(top, "none", stroke="#a9d8bd", stroke_width=2, opacity=.6))
    p.add(P(blob(420, 330, 60, 30, rnd), "#1f5a3e", opacity=.25))


def trello_0(p):
    """Green glazed tiles fanned like a hand of cards on warm linen — pale celadon through bottle green."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#efe6d8", "#e0d4c2", x2=1, y2=1)))
    rnd = random.Random(191)
    p.add(p.soft("".join(P(f"M{rnd.uniform(-50, 640)},0 C{rnd.uniform(0, 640)},120 {rnd.uniform(0, 640)},240 {rnd.uniform(0, 640)},360", "none", stroke="#c9b9a0", stroke_width=10) for _ in range(5)), 8, .4))
    cols = ["#cfe3d2", "#a9cdb3", "#7fb392", "#56987a", "#3b7d60", "#2a624a", "#1c4a37"]
    px, py = 320, 380
    for i, col in enumerate(cols):
        ang = -54 + i * 18
        g = tile(p, 0, -170, 118, col, rnd=rnd, sh=.3)
        p.add(f'<g transform="translate({px} {py}) rotate({ang})">{g}</g>')


def fc_5a(p):
    """Eye level on a desk: a stack of seven books, page edges toward us, a jar of pencils, light from the left."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#c9cfc4", "#b8bfb3", x2=1, y2=0)))
    p.add(p.soft(PL([(0, 0), (300, 0), (520, 470), (0, 470)], "#fff8e8", opacity=.35), 30))
    p.add(PL([(0, 470), (w, 470), (w, h), (0, h)], p.lg("#c69a68", "#a57a4a")))
    p.add(R(0, 466, w, 6, "#e0b88a"))
    rnd = random.Random(201)
    books = [(300, 44, "#2f3e5c"), (270, 30, "#c9a24a"), (320, 38, "#8a3b35"), (250, 26, "#e6dcc6"), (290, 34, "#4f6b5a"),
             (240, 40, "#b5532f"), (280, 28, "#1f2a38")]
    y = 470
    cx = 380
    p.add(p.soft(E(cx + 30, 474, 200, 12, "#3a2410"), 6, .6))
    for (bw, bh, col) in books:
        x = cx - bw / 2 + rnd.uniform(-18, 18)
        y -= bh
        p.add(R(x, y, bw, bh, col, rx=3))
        p.add(R(x + bw - 10, y + 3, 8, bh - 6, "#f4ecd8", rx=1))
        for k in range(1, int(bh // 5)):
            p.add(L(x + bw - 10, y + 3 + k * 5, x + bw - 2, y + 3 + k * 5, "#d6cbb0", .8))
        p.add(R(x, y, bw, 3, "#ffffff", opacity=.18))
        p.add(R(x + 18, y + bh * .35, 6, bh * .3, lt(col, .3), opacity=.5))
    # a glass jar of pencils
    jx = 640
    p.add(p.soft(E(jx + 10, 474, 50, 8, "#3a2410"), 4, .5))
    for i, col in enumerate(("#e9b43a", "#2f6bd6", "#d44c3a", "#3a8a5a", "#1c1c1c")):
        x = jx - 26 + i * 13
        top = 300 + (i % 3) * 18
        p.add(L(x, 470, x + (i - 2) * 8, top, col, 7))
        p.add(L(x + (i - 2) * 8, top, x + (i - 2) * 8.4, top - 10, "#e8c9a0", 5))
    p.add(R(jx - 44, 360, 88, 110, "#ffffff", rx=8, opacity=.25))
    p.add(R(jx - 36, 366, 10, 96, "#ffffff", rx=4, opacity=.45))


def fc_5b(p):
    """Top-down on dark stained oak: an open book with pencil underlines and margin notes, a pencil, black coffee."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#4a3222", "#34221a", x2=1, y2=1)))
    p.add(grain(p, 0, 0, w, h, "#1e120b", k=14, op=.4, seed=21, wav=12))
    p.add(p.soft(E(180, 120, 260, 180, "#f0c48a", opacity=.18), 50))
    g = []
    g.append(p.soft(R(-236, -176, 480, 350, "#000", rx=6), 14, .6))
    for sx in (-1, 1):
        g.append(R(-240 if sx < 0 else 0, -180, 240, 350, p.lg("#f6efdf", "#ece2cc", x2=sx, y2=0) if sx > 0 else p.lg("#ece2cc", "#f6efdf", x2=1, y2=0), rx=4))
    g.append(R(-18, -180, 36, 350, p.lg((0, "#000", 0), (.5, "#6b5a3a", .3), (1, "#000", 0), x2=1, y2=0)))
    rnd = random.Random(211)
    for sx in (-1, 1):
        x0 = -214 if sx < 0 else 30
        for k in range(17):
            y = -150 + k * 18
            ln = rnd.uniform(140, 184) if k % 6 != 5 else rnd.uniform(60, 110)
            g.append(R(x0, y, ln, 5, "#8f8778", rx=2, opacity=.7))
            if rnd.random() < .18:
                g.append(P(f"M{x0},{y + 9} C{x0 + ln * .3},{y + 7} {x0 + ln * .6},{y + 11} {x0 + ln * .95},{y + 8}", "none", stroke="#4a4a4a", stroke_width=1.6, opacity=.8))
    # margin notes: a bracket, squiggles, a star
    g.append(P("M200,-80 C210,-80 210,-30 214,-26 C210,-22 210,24 200,24", "none", stroke="#4a4a4a", stroke_width=1.8))
    g.append(P("M218,-20 c6,-6 10,4 16,-2 c6,-6 10,4 16,-2", "none", stroke="#4a4a4a", stroke_width=1.6))
    g.append(P("M-232,60 l8,-14 l8,14 l-16,-9 h16 z", "none", stroke="#4a4a4a", stroke_width=1.4))
    p.add(f'<g transform="translate(340 300) rotate(-6)">' + "".join(g) + "</g>")
    # pencil
    p.add(p.soft(R(90, 520, 300, 14, "#000", transform="rotate(-12 240 527)"), 4, .5))
    p.add(R(80, 510, 280, 14, "#e9b43a", transform="rotate(-12 220 517)"))
    p.add(PL([(360, 510), (386, 517), (360, 524)], "#e8c9a0", transform="rotate(-12 220 517)"))
    p.add(R(60, 510, 20, 14, "#e79aa0", transform="rotate(-12 220 517)"))
    # coffee from above
    cx, cy = 680, 470
    p.add(p.soft(C(cx + 10, cy + 14, 92, "#000"), 10, .6))
    p.add(C(cx, cy, 92, p.rg("#faf7f1", "#e9e3d8", "#cfc6b8")))
    p.add(C(cx, cy, 58, "#f2eee6"), C(cx, cy, 50, p.rg("#3a2213", "#241409", "#1a0e06", cx=.45, cy=.45)))
    p.add(C(cx, cy, 50, "none", stroke="#8a5a36", stroke_width=3, opacity=.6))
    p.add(E(cx - 16, cy - 18, 14, 6, "#ffffff", opacity=.35))
    p.add(P(f"M{cx + 56},{cy - 10} C{cx + 86},{cy - 12} {cx + 86},{cy + 14} {cx + 56},{cy + 12}", "none", stroke="#ece6dc", stroke_width=10))


def bsky_4a(p):
    """A dotted notebook open on a pale sage table, low evening sun from the right: a fountain pen's long shadow."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#c9d3c6", "#b5c1b2", x2=1, y2=1)))
    p.add(p.soft(PL([(800, 0), (800, 600), (300, 600), (560, 0)], "#ffe9c0", opacity=.3), 40))
    nb = [(150, 150), (640, 110), (720, 470), (110, 530)]
    p.add(p.soft(PL([(120, 170), (650, 130), (740, 500), (80, 570)], "#3a4a38"), 14, .45))
    p.add(PL([(150, 150), (640, 110), (720, 470), (110, 530)], "#2f3f5a"))
    pg = [(158, 156), (632, 118), (710, 462), (118, 520)]
    left = subquad(pg, 0, 0, .5, 1)
    right = subquad(pg, .5, 0, 1, 1)
    p.add(PL(left, p.lg("#f6f2e8", "#ebe5d8", x2=1, y2=0)), PL(right, p.lg("#e9e3d6", "#f8f5ee", x2=1, y2=0)))
    p.add(PL(subquad(pg, .47, 0, .53, 1), "#000", opacity=.08))
    dots = []
    for i in range(1, 22):
        for j in range(1, 16):
            x, y = quadpt(pg, i / 22, j / 16)
            dots.append(C(x, y, 1.3, "#b5ad9d"))
    p.add(G(*dots))
    rnd = random.Random(221)
    for k in range(9):
        u0 = .06
        v = .1 + k * .07
        pts = []
        u = u0
        end = rnd.uniform(.3, .44)
        while u < end:
            x, y = quadpt(pg, u, v)
            pts.append((x, y + rnd.uniform(-5, 3)))
            u += .012
        p.add(P(smooth(pts, closed=False), "none", stroke="#2c4a8a", stroke_width=1.6, opacity=.85))
    # elastic band down the right edge
    p.add(PL(subquad(nb, .9, 0, .92, 1), "#1c2436"))
    # pen and its long shadow (sun from the right, low)
    p.add(p.soft(PL([(470, 330), (640, 250), (646, 262), (300, 420)], "#2a3528"), 5, .45))
    pen = [R(0, -9, 190, 18, p.lg("#2b2b2e", "#101012", x2=0, y2=1), rx=9), R(150, -10, 12, 20, "#c9a04a"),
           P("M190,-7 L230,0 L190,7 Z", "#c9a04a"), R(10, -6, 120, 3, "#ffffff", rx=1.5, opacity=.25)]
    p.add(f'<g transform="translate(410 330) rotate(-24)">{"".join(pen)}</g>')
    # a eucalyptus sprig
    p.add(P("M60,480 C90,420 120,380 170,350", "none", stroke="#7a8a6e", stroke_width=3))
    for t in range(6):
        x, y = 70 + t * 18, 462 - t * 20
        p.add(C(x - 10, y, 13, "#8fa89a"), C(x + 12, y - 6, 12, "#9ab3a5"))


DRAW.update({
    "ig-save-8": ig_save_8, "ig-save-11": ig_save_11, "ig-like-2": ig_like_2, "file-3": file_3, "file-5": file_5,
    "trello-0": trello_0, "fc-5a": fc_5a, "fc-5b": fc_5b, "bsky-4a": bsky_4a,
})


# ── climbing (six subjects, six set-ups) ──────────────────────────────────
# A climbing gym is drawn like an interior: walls, holds, mats, light. The six
# never share a wall colour or a viewpoint: tan plywood looking UP an overhang
# (tt-post-0), a charcoal macro (tt-post-1), a home doorway at lamp-light
# (tt-post-2), a pale grey wall straight on (tt-post-3), a sage slab at low
# golden light (tt-notice-0), a black training wall at night (tt-notice-1).

HOLD_COLS = ["#f2c230", "#e8457a", "#3fae5a", "#f07a2a", "#2f7fd6", "#8a4fd0", "#26292e", "#f4f1ea", "#21b5b0"]


def rot_pt(x, y, deg):
    a = math.radians(deg)
    return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)


def hold(p, x, y, r, col, rnd, kind="jug", rot=0, shadow=(.22, .28), sh_op=.38, sh_blur=3, bolt=True):
    """One climbing hold: a lumpy resin shape lit from the upper left, its bolt, its cast shadow."""
    shapes = {"jug": (1, .74, .16, 9), "crimp": (1.3, .36, .1, 8), "sloper": (1.1, .92, .07, 10),
              "pinch": (.55, 1.1, .14, 8), "chip": (.8, .5, .22, 7)}
    fx, fy, jit, k = shapes[kind]
    d = blob(0, 0, r * fx, r * fy, rnd, k, jit, rot)
    out = [p.soft(P(d, "#000", transform=f"translate({n(x + shadow[0] * r)} {n(y + shadow[1] * r)})"), sh_blur, sh_op)]
    body = p.rg((0, lt(col, .42)), (.45, col), (1, dk(col, .38)), cx=.36, cy=.3, r=.85)
    out.append(P(d, body, transform=f"translate({n(x)} {n(y)})"))
    if kind == "jug":
        # the incut lip: a dark crescent under the top edge
        ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        lx, ly = x - sa * r * .12, y + ca * r * .12
        out.append(E(lx, ly, r * .62, r * .2, dk(col, .5), transform=f"rotate({n(rot)} {n(lx)} {n(ly)})", opacity=.8))
    if bolt and r > 9:
        bx, by = x + r * .12, y + (r * .3 if kind == "jug" else 0)
        out.append(C(bx, by, r * .14, dk(col, .55)))
        out.append(C(bx, by, r * .07, "#c9ccd0"))
    out.append(E(x - r * .3, y - r * .28 * fy, r * .32 * fx, r * .12 * fy, "#ffffff", opacity=.28))
    return "".join(out)


def tnuts(quad, cols, rows, r, col, op):
    """The T-nut grid every gym wall carries, laid on a quad in perspective (r scales with depth)."""
    out = []
    for i in range(1, cols):
        for j in range(1, rows):
            u, v = i / cols, j / rows
            x, y = quadpt(quad, u, v)
            out.append(C(x, y, r(v), col))
    return G(*out, opacity=op)


SHOE = ("M24,8 C4,6 -4,-16 0,-40 C3,-60 14,-74 30,-78 C52,-80 74,-74 92,-70 C120,-66 150,-56 178,-44 "
        "C210,-30 236,-16 248,-2 C254,6 250,14 238,14 C200,14 150,2 110,4 C80,6 50,10 24,8 Z")


def shoe(p, x, y, rot, s=1.0, upper="#f2b531", rand="#1c1c1f", strap="#d6453b", flip=False):
    """A downturned climbing shoe in profile, heel at the origin, toe to the right (flip mirrors it)."""
    cid = p.clip(P(SHOE, "#fff"))
    inner = [P(SHOE, p.lg(lt(upper, .25), upper, dk(upper, .25))),
             P("M-12,30 L-12,-50 C12,-58 32,-40 46,-18 C52,-8 54,4 56,30 Z", rand),       # heel rubber cup
             P("M-12,0 C60,4 150,-6 262,-8 L262,30 L-12,30 Z", rand),                     # sole
             P("M40,-2 C110,-6 170,-12 236,-14", "none", stroke=rand, stroke_width=7),    # rand
             P("M196,-32 C222,-22 240,-12 262,-2 L262,30 L204,30 C216,8 212,-14 196,-32 Z", rand),  # toe patch
             P("M98,-72 L126,-63 L106,-8 L80,-12 Z", strap),
             P("M102,-66 L120,-60 L108,-24 L94,-26 Z", "#ffffff", opacity=.14),
             P("M6,-40 C8,-58 18,-70 32,-74", "none", stroke="#ffffff", stroke_width=3, opacity=.22),
             P("M140,-54 C180,-40 214,-26 236,-12", "none", stroke="#ffffff", stroke_width=3, opacity=.3)]
    tab = P("M16,-72 C8,-92 24,-100 36,-90 L34,-74 Z", rand)
    sx = -s if flip else s
    return (f'<g transform="translate({n(x)} {n(y)}) rotate({n(rot)}) scale({n(sx)} {n(s)})">'
            + tab + G(*inner, clip_path=cid) + "</g>")


def shoe_pt(x, y, rot, s, flip, lx, ly):
    """Where a point of the shoe's local outline lands on the canvas."""
    if flip:
        lx = -lx
    rx, ry = rot_pt(lx * s, ly * s, rot)
    return x + rx, y + ry


def limb(a, b, w0, w1, fill, **kw):
    """A tapered limb from a (width w0) to b (width w1), round at both ends."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    pts = [(x0 + nx * w0 / 2, y0 + ny * w0 / 2), (x1 + nx * w1 / 2, y1 + ny * w1 / 2),
           (x1 - nx * w1 / 2, y1 - ny * w1 / 2), (x0 - nx * w0 / 2, y0 - ny * w0 / 2)]
    return G(PL(pts, fill), C(x0, y0, w0 / 2, fill), C(x1, y1, w1 / 2, fill), **kw)


def seg7(x, y, w, h, digit, on, off):
    """One seven-segment LED digit, unlit segments ghosted as on a real gym timer."""
    t = w * .2
    segs = {"a": (x + t * .6, y, w - t * 1.2, t, "h"), "d": (x + t * .6, y + h - t, w - t * 1.2, t, "h"),
            "g": (x + t * .6, y + h / 2 - t / 2, w - t * 1.2, t, "h"),
            "f": (x, y + t * .6, t, h / 2 - t * .9, "v"), "b": (x + w - t, y + t * .6, t, h / 2 - t * .9, "v"),
            "e": (x, y + h / 2 + t * .3, t, h / 2 - t * .9, "v"), "c": (x + w - t, y + h / 2 + t * .3, t, h / 2 - t * .9, "v")}
    lit = {"0": "abcdef", "7": "abc", "1": "bc"}[digit]
    out = []
    for k, (sx, sy, sw, sh, o) in segs.items():
        c = on if k in lit else off
        if o == "h":
            pts = [(sx, sy + sh / 2), (sx + sh / 2, sy), (sx + sw - sh / 2, sy), (sx + sw, sy + sh / 2),
                   (sx + sw - sh / 2, sy + sh), (sx + sh / 2, sy + sh)]
        else:
            pts = [(sx + sw / 2, sy), (sx + sw, sy + sw / 2), (sx + sw, sy + sh - sw / 2), (sx + sw / 2, sy + sh),
                   (sx, sy + sh - sw / 2), (sx, sy + sw / 2)]
        out.append(PL(pts, c))
    return "".join(out)


def chalk(p, x, y, rx, ry, op=.55, sd=6):
    return p.soft(E(x, y, rx, ry, "#ffffff", opacity=op), sd)


def tt_post_0(p):
    """Looking UP a steep overhang from the mats: tan plywood, every colour of hold, a climber
    pulling over the lip against a bright skylit ceiling. Midday, the brightest of the six."""
    w, h = p.w, p.h
    rnd = random.Random(101)
    # ceiling, skylight and steel above the lip
    p.add(R(0, 0, w, 260, p.lg("#dfe6ec", "#c5ced6")))
    p.add(PL([(60, 0), (300, 0), (360, 120), (90, 150)], "#ffffff"))
    p.add(p.soft(PL([(60, 0), (300, 0), (360, 120), (90, 150)], "#ffffff"), 22, .9))
    for (x0, x1) in ((0, 470), (-40, 300)):
        p.add(L(x0, 40 + x0 * .2, x1, 150 - x1 * .1, "#3b4148", 7, opacity=.7))
    p.add(L(380, 0, 420, 200, "#3b4148", 9, opacity=.6))
    # the overhang: near (bottom) wide, the lip (top) far and narrow
    q = [(-30, 205), (480, 180), (620, 720), (-170, 740)]
    p.add(PL(q, p.lg((0, "#c9a476"), (.5, "#d8b585"), (1, "#c09868"))))
    p.add(PL(subquad(q, 0, 0, 1, .2), "#ffffff", opacity=.12))
    for i in range(1, 5):
        a, b = quadpt(q, i / 5, 0), quadpt(q, i / 5, 1)
        p.add(L(a[0], a[1], b[0], b[1], "#9c7a52", 1.6, opacity=.55))
    for j in range(1, 5):
        a, b = quadpt(q, 0, j / 5), quadpt(q, 1, j / 5)
        p.add(L(a[0], a[1], b[0], b[1], "#9c7a52", 1.6, opacity=.55))
    p.add(tnuts(q, 16, 14, lambda v: 1.2 + 2.2 * v, "#5a4228", .55))
    # two volumes bolted to the wall
    vq = subquad(q, .08, .34, .36, .62)
    p.add(p.soft(PL([(vq[0][0] + 14, vq[0][1] + 16), (vq[1][0] + 14, vq[1][1] + 16), (vq[3][0] + 14, vq[3][1] + 16)], "#000"), 8, .3))
    p.add(PL([vq[0], vq[1], vq[3]], "#7fc8bb"), PL([vq[1], vq[3], quadpt(q, .26, .56)], "#5fae9f"))
    v2 = subquad(q, .62, .12, .88, .4)
    p.add(PL([v2[0], v2[1], v2[2]], "#ef8f7a"), PL([v2[0], v2[2], quadpt(q, .7, .34)], "#d8705c"))
    # holds, bigger as they come toward the camera
    spots = []
    for _ in range(46):
        u, v = rnd.uniform(.03, .97), rnd.uniform(.06, .96)
        if any(abs(u - a) < .07 and abs(v - b) < .06 for a, b in spots):
            continue
        spots.append((u, v))
        x, y = quadpt(q, u, v)
        if x < -10 or x > w + 10:
            continue
        r = 7 + 26 * v ** 1.3
        p.add(hold(p, x, y, r, rnd.choice(HOLD_COLS), rnd, rnd.choice(["jug", "jug", "crimp", "sloper", "pinch"]),
                   rot=rnd.uniform(-40, 40), shadow=(.15, .35)))
    # the lip: a padded edge
    p.add(PL([(-30, 196), (480, 171), (480, 186), (-30, 211)], "#3d3f45"))
    p.add(p.soft(PL([(-30, 211), (480, 186), (480, 230), (-30, 255)], "#000"), 10, .25))
    # the climber mantling over the lip: elbows up, one heel hooked on the edge, one leg hanging
    sk, top, bot, sh = "#b77a5a", "#e2553c", "#2b2f3b", "#f2c230"
    lip = lambda x: 196 - (x + 30) * 25 / 510
    hx = 298
    hip = (hx, lip(hx) + 10)
    p.add(hold(p, 280, lip(280) + 118, 14, "#2f7fd6", rnd, "jug", shadow=(.15, .35)))
    p.add(limb((hx - 10, hip[1]), (272, lip(272) + 62), 24, 17, bot))            # hanging leg
    p.add(limb((272, lip(272) + 62), (282, lip(282) + 104), 17, 12, bot))
    p.add(E(286, lip(286) + 108, 17, 8, sh, transform=f"rotate(20 286 {n(lip(286) + 108)})"))
    p.add(limb((hx + 8, hip[1]), (356, lip(356) + 22), 24, 17, bot))             # heel-hook leg
    p.add(limb((356, lip(356) + 22), (404, lip(404) - 2), 17, 12, bot))
    p.add(E(412, lip(412) - 6, 18, 8, sh, transform=f"rotate(-12 412 {n(lip(412) - 6)})"))
    sy = lip(hx) - 46
    p.add(limb(hip, (hx, sy + 6), 46, 54, top))                                    # torso over the lip
    p.add(C(hx, sy - 18, 17, "#2e211b"), R(hx - 7, sy - 6, 14, 10, sk))
    for side in (-1, 1):
        sh_ = (hx + side * 24, sy + 2)
        el = (hx + side * 64, sy - 18)
        hd = (hx + side * 58, lip(hx + side * 58) - 8)
        p.add(limb(sh_, el, 15, 12, top if side < 0 else top), limb(el, hd, 12, 10, sk))
        p.add(E(hd[0], hd[1], 11, 6, sk))
    p.add(C(hx + 16, hip[1] + 2, 8, "#f4f1ea"))                                   # chalk bag on the hip
    p.add(p.soft(E(hx, sy - 10, 90, 60, "#ffffff", opacity=.35), 14))            # backlight halo
    p.add(p.soft(PL([(-30, 0), (w, 0), (w, 120), (-30, 160)], "#ffffff"), 30, .25))
    # the mats underfoot
    p.add(PL([(-20, 708), (470, 690), (470, h), (-20, h)], p.lg("#2c5aa0", "#1f4683")))
    p.add(PL([(-20, 708), (470, 690), (470, 698), (-20, 716)], "#5b86c9"))
    p.add(PL([(200, 700), (226, 699), (250, h), (214, h)], "#1a3c72"))
    p.add(chalk(p, 120, 760, 60, 14, .35, 10), chalk(p, 360, 740, 40, 8, .3, 8))


def tt_post_1(p):
    """Macro on a charcoal wall: a yellow shoe's heel hooked over a big teal ball of a hold, toe
    cocked up, chalk hanging in the air. Hard light from the upper right; the rest falls to dark."""
    w, h = p.w, p.h
    rnd = random.Random(111)
    p.add(R(0, 0, w, h, p.rg("#3b3e46", "#24262c", "#141519", cx=.7, cy=.35, r=.95)))
    p.add(G(*[C(rnd.uniform(0, w), rnd.uniform(0, h), rnd.uniform(.6, 1.6), rnd.choice(["#4a4d56", "#1a1b20"])) for _ in range(260)], opacity=.7))
    p.add(bokeh(p, [(390, 90, 34, "#f2c230", .4), (60, 760, 44, "#3fae5a", .35), (410, 770, 56, "#8a4fd0", .35),
                    (40, 470, 24, "#e8457a", .35)], 14))
    # the hold: a big round dome, its top worn white with chalk
    cx, cy, rx, ry = 262, 660, 205, 168
    p.add(p.soft(E(cx + 34, cy + 40, rx, ry, "#000"), 18, .65))
    p.add(E(cx, cy, rx, ry, p.rg((0, "#86e6dc"), (.3, "#33b8ab"), (.75, "#177d74"), (1, "#0b4642"), cx=.66, cy=.22, r=.85)))
    hcid = p.clip(E(cx, cy, rx, ry, "#fff"))
    p.add(G(*[C(rnd.uniform(cx - rx, cx + rx), rnd.uniform(cy - ry, cy + ry), rnd.uniform(.8, 1.8),
                rnd.choice(["#0b4642", "#a6efe7"]), opacity=rnd.uniform(.25, .5)) for _ in range(420)], clip_path=hcid))
    p.add(p.soft(E(cx + 70, cy - 112, 80, 26, "#ffffff", opacity=.4), 10))
    p.add(p.soft(E(cx - 50, cy - 140, 110, 26, "#eef5f4", opacity=.65), 8))
    p.add(p.soft(E(cx + 30, cy - 96, 70, 30, "#eef5f4", opacity=.3), 12))
    p.add(C(cx + 10, cy + 20, 13, "#0b4642"), C(cx + 10, cy + 20, 6, "#c9ccd0"))
    # leg first, then the shoe over its cuff
    x, y, rot, s = 128, 516, -30, 1.34
    a, b = shoe_pt(x, y, rot, s, False, 32, -76), shoe_pt(x, y, rot, s, False, 90, -70)
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    p.add(limb((mid[0] - 6, mid[1] + 4), (-70, -60), 82, 136, p.lg("#2b1f3a", "#4c3864", "#36284a", x2=1, y2=0)))
    p.add(P(f"M{n(mid[0] + 24)},{n(mid[1] - 10)} C{n(mid[0] - 10)},{n(mid[1] - 160)} 70,120 30,-10", "none",
            stroke="#6d5488", stroke_width=10, opacity=.45, stroke_linecap="round"))
    p.add(limb(a, b, 16, 16, "#f4f1ea"))                                         # sock cuff
    p.add(p.soft(P(SHOE, "#000", transform=f"translate({x + 14} {y + 16}) rotate({rot}) scale({s})"), 8, .55))
    p.add(shoe(p, x, y, rot, s))
    # chalk knocked loose at the heel, hanging in the light
    for (px, py, r_, op) in [(196, 500, 40, .45), (250, 470, 30, .3), (150, 470, 26, .3), (300, 430, 44, .18), (350, 380, 30, .15)]:
        p.add(chalk(p, px, py, r_, r_ * .7, op, 10))
    for _ in range(46):
        p.add(C(rnd.uniform(150, 440), rnd.uniform(330, 520), rnd.uniform(.8, 2.2), "#ffffff", opacity=rnd.uniform(.3, .85)))


def tt_post_2(p):
    """At home, evening, lamp-lit: a pale beech fingerboard screwed above a white doorway on a
    terracotta wall, two chalky hands hanging from it, the room beyond in blue dusk."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#c98a6c", "#b5735a", "#94583f")))
    p.add(p.soft(E(40, 170, 200, 260, "#ffd29a", opacity=.55), 50))
    # sconce at the left edge
    p.add(p.soft(E(40, 200, 90, 70, "#fff0c8", opacity=.6), 20))
    p.add(R(-6, 140, 14, 60, "#b08a4a", rx=4), P("M8,170 C24,170 30,160 34,152", "none", stroke="#b08a4a", stroke_width=5))
    p.add(P("M14,96 L62,96 L78,158 L-2,158 Z", p.lg("#fff6e0", "#f6d9a2", "#e8bd78")))
    p.add(E(38, 158, 40, 6, "#fffaf0"))
    # the doorway, the room beyond
    p.add(R(66, 470, 318, 330, p.lg("#2c3a55", "#1d2639")))
    p.add(R(250, 520, 110, 150, p.lg("#5c79a8", "#3a5481")))       # far window at dusk
    p.add(R(300, 520, 6, 150, "#1d2639"), R(250, 590, 110, 6, "#1d2639"))
    p.add(p.soft(C(120, 640, 50, "#ffc070", opacity=.45), 20))
    p.add(R(100, 700, 120, 100, "#151b29"))
    p.add(R(46, 450, 358, 22, p.lg("#fbf7f0", "#e6dccd")), R(46, 450, 22, 350, "#f3ece1"), R(382, 450, 22, 350, "#e3d8c7"))
    # backing plank and the board
    p.add(p.soft(R(26, 262, 410, 168, "#4a2a1a"), 10, .5))
    p.add(R(18, 250, 414, 168, p.lg("#7a4e33", "#5c3824")), )
    for sx_, sy_ in ((40, 270), (410, 270), (40, 398), (410, 398)):
        p.add(C(sx_, sy_, 6, "#c9ccd0"), L(sx_ - 4, sy_ - 4, sx_ + 4, sy_ + 4, "#6b6f74", 1.5))
    bx0, by0, bw, bh = 52, 270, 346, 132
    p.add(p.soft(R(bx0 + 6, by0 + 12, bw, bh, "#2a160c", rx=18), 6, .55))
    beech = p.lg("#f1d4a6", "#e2bd88", "#c99c62")
    p.add(R(bx0, by0, bw, bh, beech, rx=18))
    p.add(R(bx0, by0, bw, 26, "#f7e3c2", rx=14))                 # the rounded top jug
    p.add(R(bx0 + 8, by0 + 26, bw - 16, 4, "#a77c48", opacity=.6))
    for i, (px, pw) in enumerate([(70, 70), (152, 52), (246, 52), (320, 70)]):   # pockets
        p.add(R(px, 312, pw, 30, "#7a5530", rx=13), R(px + 4, 314, pw - 8, 10, "#4f3519", rx=6))
    p.add(R(bx0 + 10, 356, bw - 20, 30, "#c99c62", rx=8), R(bx0 + 12, 358, bw - 24, 8, "#8a6338", rx=4))
    p.add(grain(p, bx0, by0, bw, bh, "#b8874f", k=10, op=.25, seed=21))
    for cx_ in (150, 300):
        p.add(chalk(p, cx_, 362, 50, 9, .7, 4), chalk(p, cx_ + 14, 300, 26, 6, .45, 5))
    # two hands, from behind: fingers over the bottom edge, forearms falling toward the camera
    sk, skd = "#e6ad8c", "#b97d60"
    for cx_, inward in ((150, 1), (300, -1)):
        lean = 8 * inward
        p.add(p.soft(PL([(cx_ - 30, 440), (cx_ + 34, 440), (cx_ + 74 + lean, h), (cx_ - 54 + lean, h)], "#1a1010"), 10, .35))
        p.add(PL([(cx_ - 29, 430), (cx_ + 29, 430), (cx_ + 56 + lean, h + 10), (cx_ - 56 + lean, h + 10)],
                 p.lg(skd, sk, lt(sk, .1), skd, x2=1, y2=0)))
        # back of the hand
        p.add(P(f"M{cx_ - 46},388 C{cx_ - 46},414 {cx_ - 34},436 {cx_ - 28},446 L{cx_ + 28},446 "
                f"C{cx_ + 34},436 {cx_ + 46},414 {cx_ + 46},388 Z", p.lg(lt(sk, .12), sk, skd)))
        p.add(limb((cx_ + 36 * inward, 436), (cx_ + 46 * inward, 404), 19, 15, skd))      # thumb, tucked along the index
        p.add(limb((cx_ + 35 * inward, 436), (cx_ + 44 * inward, 405), 15, 12, sk))
        # four fingers, index nearest the thumb, the little finger shortest
        for k in range(4):
            fx = cx_ + inward * (34 - k * 23)
            top_ = 356 + (8 if k == 3 else 0)
            p.add(R(fx - 10, top_, 20, 396 - top_, p.lg(dk(sk, .12), sk, lt(sk, .1)), rx=9))
            p.add(E(fx, 392, 9, 5, lt(sk, .25), opacity=.7))
            p.add(R(fx - 9, top_, 18, 7, "#ffffff", rx=3, opacity=.55))
        p.add(chalk(p, cx_, 384, 36, 8, .45, 5))


def tt_post_3(p):
    """Straight on, flat daylight: a pale grey wall and one route of purple holds snaking up it,
    start tape at the bottom, a mustard chalk bag waiting on the charcoal mat."""
    w, h = p.w, p.h
    rnd = random.Random(131)
    q = [(0, 0), (w, 0), (w, 700), (0, 700)]
    p.add(R(0, 0, w, 700, p.lg("#eef0f2", "#e1e4e8", "#d4d8dd")))
    p.add(p.soft(E(225, 0, 300, 160, "#ffffff", opacity=.7), 40))
    for x in (150, 300):
        p.add(L(x, 0, x, 700, "#c3c8ce", 1.6))
    for y in (175, 350, 525):
        p.add(L(0, y, w, y, "#c3c8ce", 1.6))
    p.add(tnuts(q, 12, 20, lambda v: 2.1, "#8c939b", .6))
    # a few neutral holds from other routes, small and quiet
    for _ in range(12):
        x, y = rnd.uniform(20, w - 20), rnd.uniform(30, 650)
        p.add(hold(p, x, y, rnd.uniform(8, 13), rnd.choice(["#f8f8f8", "#2a2c30", "#b9bec5"]), rnd,
                   rnd.choice(["crimp", "chip", "jug"]), rot=rnd.uniform(-30, 30), sh_op=.22))
    # the purple line
    line = [(118, 620, 30, "jug"), (190, 560, 24, "crimp"), (150, 488, 30, "sloper"), (236, 440, 26, "pinch"),
            (302, 380, 28, "jug"), (250, 312, 24, "crimp"), (182, 262, 30, "sloper"), (230, 196, 24, "pinch"),
            (306, 150, 26, "crimp"), (262, 82, 34, "jug")]
    purples = ["#8a4fd0", "#7a3fc0", "#9a5fe0", "#6e35b0"]
    for i, (x, y, r, kind) in enumerate(line):
        p.add(hold(p, x, y, r, purples[i % 4], rnd, kind, rot=rnd.uniform(-35, 35), sh_op=.32))
        p.add(chalk(p, x - 4, y - r * .4, r * .7, r * .25, .45, 3))
    p.add(R(70, 650, 34, 10, "#8a4fd0", transform="rotate(-8 87 655)"), R(76, 664, 34, 10, "#8a4fd0", transform="rotate(6 93 669)"))
    # floor: wall foot shadow, charcoal mat
    p.add(p.soft(R(0, 690, w, 24, "#000"), 8, .3))
    p.add(R(0, 700, w, 100, p.lg("#4a4e56", "#33363c")))
    p.add(R(0, 700, w, 5, "#666b74"))
    p.add(R(0, 748, w, 6, "#2a2d32", opacity=.8))
    p.add(chalk(p, 100, 730, 44, 8, .3, 8), chalk(p, 300, 770, 50, 9, .25, 8))
    # the chalk bag
    bx, by = 320, 762
    p.add(p.soft(E(bx + 8, by + 6, 52, 10, "#000"), 6, .5))
    p.add(L(bx - 120, by + 8, bx - 40, by + 2, "#1d1f24", 6, stroke_linecap="round"))
    p.add(P(f"M{bx - 44},{by - 70} L{bx + 44},{by - 70} C{bx + 50},{by - 30} {bx + 48},{by - 4} {bx + 40},{by} "
            f"C{bx + 20},{by + 8} {bx - 20},{by + 8} {bx - 40},{by} C{bx - 48},{by - 4} {bx - 50},{by - 30} {bx - 44},{by - 70} Z",
            p.lg("#b27f22", "#e3b047", "#f0c35c", "#c7922e", "#8f6418", x2=1, y2=0)))
    p.add(E(bx, by - 70, 46, 12, "#f4efe4"), E(bx, by - 70, 36, 8, "#3a2f26"), E(bx - 4, by - 72, 26, 5, "#ffffff", opacity=.85))
    p.add(R(bx + 40, by - 64, 10, 40, "#2c2f35", rx=4), R(bx + 42, by - 92, 6, 30, "#c99a5a", rx=2))
    p.add(chalk(p, bx - 60, by + 4, 26, 6, .6, 4))


def tt_notice_0(p):
    """Low on the mat looking UP a sage slab at golden hour: low sun through tall windows rakes
    across it in stripes, small grey chips throw long shadows, two red shoes balance on two of them."""
    w, h = p.w, p.h
    rnd = random.Random(141)
    p.add(R(0, 0, w, h, p.lg("#93a98e", "#86a083", "#7a9377")))
    # the slab recedes upward: seams converge, rows crowd together toward the top
    q = [(90, -40), (360, -40), (720, 800), (-270, 800)]
    vs = lambda t: t ** 1.6
    for i in range(1, 6):
        a_, b_ = quadpt(q, i / 6, 0), quadpt(q, i / 6, 1)
        p.add(L(a_[0], a_[1], b_[0], b_[1], "#6a8166", 1.8, opacity=.6))
    for t in (.3, .5, .68, .84):
        a_, b_ = quadpt(q, 0, vs(t)), quadpt(q, 1, vs(t))
        p.add(L(a_[0], a_[1], b_[0], b_[1], "#6a8166", 1.8, opacity=.6))
    dots = []
    for i in range(1, 24):
        for j in range(1, 22):
            x_, y_ = quadpt(q, i / 24, vs(j / 22))
            if -5 < x_ < w + 5:
                dots.append(C(x_, y_, 1 + 2 * vs(j / 22), "#4a5e4a"))
    p.add(G(*dots, opacity=.5))
    # low sun through tall windows: warm stripes across the slab
    for (x0, x1) in ((-60, 60), (130, 230), (330, 400)):
        p.add(p.soft(PL([(x0, 0), (x1, 0), (x1 + 260, h), (x0 + 180, h)], "#ffcf7e", opacity=.38), 7))
    # small grey chips with long shadows to the right
    for _ in range(34):
        u, t = rnd.uniform(.02, .98), rnd.uniform(.05, .97)
        x_, y_ = quadpt(q, u, vs(t))
        if not (-10 < x_ < w + 10):
            continue
        r = 3 + 10 * vs(t)
        p.add(hold(p, x_, y_, r, rnd.choice(["#8e9297", "#a7abb0", "#6f7378"]), rnd, rnd.choice(["chip", "crimp"]),
                   rot=rnd.uniform(-20, 20), shadow=(1.8, .3), sh_op=.32, sh_blur=2.5, bolt=False))
    # the feet: inside edges on two tiny footholds, toes cocked up
    feet = [(70, 556, -10, .92, False, 214), (380, 446, 10, .86, True, 270)]
    for (x_, y_, rot, s, flip, top_x) in feet:
        tip = shoe_pt(x_, y_, rot, s, flip, 236, 10)
        p.add(hold(p, tip[0] + (14 if flip else -14), tip[1] + 18, 17, "#686d74", rnd, "crimp", rot=-6 if flip else 6,
                   shadow=(1.8, .3), sh_op=.4, sh_blur=2.5, bolt=False))
    for (x_, y_, rot, s, flip, top_x) in feet:
        a_ = shoe_pt(x_, y_, rot, s, flip, 32, -76)
        b_ = shoe_pt(x_, y_, rot, s, flip, 90, -70)
        mid = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
        p.add(p.soft(PL([a_, b_, (top_x + 90, 0), (top_x + 30, 0)], "#3a4a38"), 10, .25))
        p.add(limb((mid[0], mid[1] - 20), (top_x, -60), 50, 86, p.lg("#2b303b", "#454c5a", "#2b303b", x2=1, y2=0)))
        p.add(limb(a_, b_, 20, 20, "#c08a6a"))                                      # bare ankle
        p.add(PL([(a_[0], a_[1] - 22), (b_[0], b_[1] - 22), (b_[0], b_[1] - 34), (a_[0], a_[1] - 34)], "#1f232b"))
        p.add(p.soft(P(SHOE, "#000", transform=f"translate({x_ + 40} {y_ + 8}) rotate({rot}) scale({-s if flip else s} {s})"), 5, .3))
        p.add(shoe(p, x_, y_, rot, s, upper="#d9543f", strap="#1f2a44", flip=flip))
    p.add(p.soft(PL([(0, 0), (w, 0), (w, 120), (0, 170)], "#fff2d6", opacity=.25), 30))
    # the mat edge at the very bottom
    p.add(PL([(-10, 750), (460, 738), (460, h), (-10, h)], p.lg("#3b4250", "#262b35")))
    p.add(PL([(-10, 750), (460, 738), (460, 744), (-10, 756)], "#59617a"))


def tt_notice_1(p):
    """Night in the training corner: black wall, a big LED interval timer reading 0:07 over a
    chalked resin hangboard on a pine beam, one spot of light, a kettlebell and a chalk bucket."""
    w, h = p.w, p.h
    rnd = random.Random(151)
    p.add(R(0, 0, w, h, p.lg("#20242b", "#16191e")))
    p.add(G(*[C(rnd.uniform(0, w), rnd.uniform(0, 680), rnd.uniform(.6, 1.4), "#2c3139") for _ in range(160)]))
    p.add(p.soft(PL([(150, 300), (300, 300), (470, 700), (-20, 700)], "#fff1d8", opacity=.12), 20))
    p.add(p.soft(E(225, 470, 230, 120, "#ffe9c4", opacity=.18), 30))
    # the timer
    p.add(p.soft(R(66, 116, 330, 156, "#000"), 10, .7))
    p.add(R(56, 104, 338, 156, p.lg("#2a2d33", "#0d0e10"), rx=14))
    p.add(R(70, 118, 310, 128, "#060607", rx=8))
    on, off = "#ff3b2f", "#2a0d0b"
    dg = [(88, "0"), (232, "0"), (308, "7")]
    glow = []
    for x, d in dg:
        glow.append(seg7(x, 136, 56, 92, d, on, "none"))
    p.add(G(*[seg7(x, 136, 56, 92, d, on, off) for x, d in dg]))
    p.add(R(170, 162, 12, 12, on, rx=2), R(170, 198, 12, 12, on, rx=2))
    p.add(p.soft("".join(glow) + R(170, 162, 12, 12, on) + R(170, 198, 12, 12, on), 8, .7))
    p.add(R(70, 118, 310, 40, "#ffffff", rx=8, opacity=.04))
    p.add(p.soft(E(225, 300, 170, 30, "#ff3b2f", opacity=.12), 20))
    # pine beam and the resin hangboard
    p.add(p.soft(R(0, 410, w, 70, "#000"), 8, .5))
    p.add(R(0, 400, w, 64, p.lg("#d9b27a", "#b98d52", "#93693a")))
    p.add(grain(p, 0, 400, w, 64, "#7a5530", k=8, op=.3, seed=17))
    for x in (30, 420):
        p.add(C(x, 432, 7, "#9aa0a6"), C(x, 432, 3, "#3a3d42"))
    bx0, by0, bw, bh = 64, 418, 322, 116
    p.add(p.soft(R(bx0 + 6, by0 + 14, bw, bh, "#000", rx=26), 8, .6))
    p.add(R(bx0, by0, bw, bh, p.lg("#5a5f68", "#40444c", "#2c2f35"), rx=26))
    p.add(P(f"M{bx0 + 10},{by0 + 18} C{bx0 + 60},{by0 - 6} {bx0 + bw - 60},{by0 - 6} {bx0 + bw - 10},{by0 + 18} Z", "#6c727c"))
    for px, pw in ((86, 64), (164, 44), (242, 44), (300, 64)):
        p.add(R(px, by0 + 42, pw, 28, "#1a1c20", rx=12), R(px + 4, by0 + 44, pw - 8, 8, "#0c0d0f", rx=4))
    p.add(R(bx0 + 16, by0 + 82, bw - 32, 22, "#1f2226", rx=8))
    p.add(R(bx0 + 18, by0 + 82, bw - 36, 6, "#0c0d0f", rx=3))
    for (cx_, cy_, rx_, op) in ((122, 462, 22, .55), (330, 462, 22, .55), (196, 462, 16, .45), (256, 462, 16, .45),
                                (150, 504, 34, .5), (300, 504, 34, .5), (225, 420, 70, .3)):
        p.add(chalk(p, cx_, cy_, rx_, rx_ * .28, op, 3))
    # floor: rubber tiles, a kettlebell and a chalk bucket
    p.add(R(0, 680, w, 120, p.lg("#2a2d33", "#1b1d21")))
    p.add(R(0, 680, w, 3, "#3d4149"))
    p.add(L(225, 683, 225, h, "#14161a", 2), L(0, 742, w, 742, "#14161a", 2))
    kx, ky = 110, 760
    p.add(p.soft(E(kx + 6, ky + 4, 52, 10, "#000"), 6, .7))
    p.add(P(f"M{kx - 30},{ky - 74} C{kx - 32},{ky - 112} {kx + 32},{ky - 112} {kx + 30},{ky - 74}", "none", stroke="#2a2c30", stroke_width=12))
    p.add(C(kx, ky - 38, 46, p.rg("#5a5e66", "#2a2c30", "#141518", cx=.35, cy=.3, r=.8)))
    p.add(R(kx - 34, ky - 4, 68, 10, "#141518", rx=4))
    cbx, cby = 330, 766
    p.add(p.soft(E(cbx + 6, cby + 4, 54, 10, "#000"), 6, .7))
    p.add(P(f"M{cbx - 50},{cby - 90} L{cbx + 50},{cby - 90} L{cbx + 42},{cby} L{cbx - 42},{cby} Z",
            p.lg("#cfd2d6", "#f2f3f4", "#b9bdc2", x2=1, y2=0)))
    p.add(E(cbx, cby - 90, 50, 10, "#9da2a8"), E(cbx, cby - 89, 46, 8, "#fbfbfa"))
    p.add(chalk(p, cbx, cby - 96, 40, 10, .8, 4))


# ── houseplants ───────────────────────────────────────────────────────────


def monstera(x, y, length, ang, rnd, light="#4f9a52", dark="#2f6d3a", slits=4, holes=2, p=None):
    """A split monstera leaf, base at (x, y), pointing along ang (0 = up): slits cut in from both
    edges and a few windows near the midrib, both cut out of one evenodd path."""
    L_, W = length, length * .46
    N = 46

    def edge(s):
        return (W * math.sin(math.pi * s) ** .8 * (1 - .22 * s), -L_ * s + .6 * L_ * math.sin(math.pi * s) * (1 - s) ** 2)

    def side(sign):
        cuts = [.14 + (k + rnd.uniform(.25, .75)) * .7 / slits for k in range(slits)] if slits else []
        pts = []
        for i in range(N + 1):
            s = i / N
            if cuts and abs(s - cuts[0]) < .5 / N:
                c = cuts.pop(0)
                # a long, nearly parallel slit running in along the lateral vein toward the midrib
                ex, ey = edge(c)
                dx_, dy_ = -ex, -L_ * max(.02, c - .1) - ey
                ln = math.hypot(dx_, dy_) or 1
                nx, ny = -dy_ / ln, dx_ / ln
                g = L_ * .022
                dpt = rnd.uniform(.62, .84)
                ix, iy = ex + dx_ * dpt, ey + dy_ * dpt
                pts += [((ex - nx * g) * sign, ey - ny * g), ((ix - nx * g * .5) * sign, iy - ny * g * .5),
                        ((ix + nx * g * .5) * sign, iy + ny * g * .5), ((ex + nx * g) * sign, ey + ny * g)]
                continue
            ex, ey = edge(s)
            pts.append((ex * sign, ey))
        return pts

    right = side(1)
    left = list(reversed(side(-1)))
    d = "M" + " L".join(f"{n(a)},{n(b)}" for a, b in right + left) + " Z"
    for _ in range(holes):
        s = rnd.uniform(.25, .7)
        sg = rnd.choice([-1, 1])
        hx, hy = sg * W * .36 * math.sin(math.pi * s), -L_ * s
        rx, ry = L_ * .05, L_ * .022
        d += f" M{n(hx - rx)},{n(hy)} a{n(rx)},{n(ry)} 0 1,0 {n(2 * rx)},0 a{n(rx)},{n(ry)} 0 1,0 {n(-2 * rx)},0 Z"
    fill = p.lg((0, dark), (.5, dk(light, .08)), (.5, light), (1, lt(light, .1)), x2=1, y2=0) if p else light
    veins = "".join(L(0, -L_ * s, sg * W * .8 * math.sin(math.pi * s), -L_ * s - L_ * .14, lt(light, .3), 1.2, opacity=.35)
                    for s in (.2, .35, .5, .65) for sg in (-1, 1))
    mid = L(0, 0, 0, -L_ * .95, lt(light, .35), 2, opacity=.6)
    inner = G(veins, mid, clip_path=p.clip(P(d, "#fff", clip_rule="evenodd"))) if p else ""
    return (f'<g transform="translate({n(x)} {n(y)}) rotate({n(ang)})">'
            f'<path d="{d}" fill="{fill}" fill-rule="evenodd"/>{inner}</g>')


def corner_room(p, x0, w, h, big, rnd):
    """The same sunny room corner — oak floor, white skirting, a small framed print — with a monstera
    in it. `big` is three years on."""
    cx, fy = x0 + w * .6, 430
    p.add(PL([(x0, 0), (cx, 0), (cx, fy), (x0, fy + 70)], p.lg("#f6efe2", "#eee4d2", x2=1, y2=0)))
    p.add(PL([(cx, 0), (x0 + w, 0), (x0 + w, fy + 46), (cx, fy)], p.lg("#ddd1bd", "#e7dccb", x2=1, y2=0)))
    p.add(p.soft(PL([(x0 - 20, 40), (x0 + 120, 20), (x0 + 150, 330), (x0 - 20, 380)], "#fff8e6", opacity=.8), 18))
    # floor and skirting
    p.add(PL([(x0, fy + 70), (cx, fy), (x0 + w, fy + 46), (x0 + w, h), (x0, h)], p.lg("#c99a64", "#b3834f")))
    for k in range(-6, 9):
        p.add(L(cx, fy, x0 + w * .6 + k * 70, h, "#9a6c3c", 1.4, opacity=.45))
    p.add(PL([(x0, fy + 56), (cx, fy - 12), (cx, fy), (x0, fy + 70)], "#fbf8f2"))
    p.add(PL([(cx, fy - 12), (x0 + w, fy + 34), (x0 + w, fy + 46), (cx, fy)], "#ece6db"))
    p.add(p.soft(PL([(x0, fy + 120), (x0 + 150, fy + 90), (x0 + 230, h), (x0, h)], "#ffe9c2", opacity=.5), 14))
    # framed print on the right wall
    p.add(PL([(cx + 50, 110), (cx + 120, 122), (cx + 120, 222), (cx + 50, 214)], "#3a3330"))
    p.add(PL([(cx + 56, 118), (cx + 114, 128), (cx + 114, 214), (cx + 56, 207)], "#efe7d8"))
    p.add(C(cx + 84, 160, 16, "#d77a4a"), PL([(cx + 62, 200), (cx + 84, 176), (cx + 108, 204)], "#4a6a7a"))
    if not big:
        px, py = cx - 6, fy + 40
        p.add(p.soft(E(px + 20, py + 2, 50, 10, "#5a3a20"), 6, .45))
        stems = [(-22, -64, -38, 70), (14, -78, 22, 82), (-4, -92, -6, 64), (30, -54, 52, 58)]
        for (dx, dy, ang, ln) in stems:
            p.add(P(f"M{px},{py - 40} Q{px + dx * .4},{py - 40 + dy * .6} {px + dx},{py - 40 + dy}", "none", stroke="#4f7a3a", stroke_width=3))
        for (dx, dy, ang, ln) in stems:
            p.add(monstera(px + dx, py - 40 + dy, ln, ang, rnd, slits=2 if ln > 66 else 0, holes=0, p=p))
        p.add(P(f"M{px - 34},{py - 44} L{px + 34},{py - 44} L{px + 26},{py} L{px - 26},{py} Z", p.lg("#d07a4c", "#b45f36", "#93492a", x2=1, y2=0)))
        p.add(R(px - 38, py - 52, 76, 12, "#c96f42", rx=3))
    else:
        px, py = cx - 10, fy + 70
        p.add(p.soft(E(px + 40, py, 130, 22, "#4a2f18"), 10, .5))
        leaves = [(-150, -250, -62, 170), (130, -280, 58, 160), (-60, -360, -20, 175), (60, -400, 18, 165),
                  (-190, -150, -84, 150), (190, -150, 82, 150), (0, -250, 4, 170), (-110, -420, -36, 150),
                  (150, -390, 42, 150), (-20, -170, -10, 140), (100, -200, 40, 150), (-120, -320, -40, 160)]
        for (dx, dy, ang, ln) in leaves:
            p.add(P(f"M{px},{py - 80} Q{px + dx * .25},{py - 80 + dy * .7} {px + dx * .6},{py - 80 + dy * .55}", "none", stroke="#4f7a3a", stroke_width=6))
        for (dx, dy, ang, ln) in leaves:
            sx, sy = px + dx * .6, py - 80 + dy * .55
            lc = rnd.choice(["#4f9a52", "#468f4a", "#5aa45a"])
            p.add(p.soft(f'<g transform="translate(14 18)">{monstera(sx, sy, ln, ang, random.Random(int(dx * 7 + dy)), light="#1f3320", slits=4, holes=3)}</g>', 8, .25))
            p.add(monstera(sx, sy, ln, ang, random.Random(int(dx * 7 + dy)), light=lc, slits=4, holes=3, p=p))
        p.add(P(f"M{px - 92},{py - 92} L{px + 92},{py - 92} L{px + 76},{py} L{px - 76},{py} Z", p.lg("#cfa76e", "#b48a52", "#8e6a3a", x2=1, y2=0)))
        for k in range(1, 6):
            yy = py - 92 + k * 16
            p.add(L(px - 92 + k * 3, yy, px + 92 - k * 3, yy, "#7a5a30", 2, opacity=.5))


def reddit_0(p):
    """Before and after, side by side: the same oak-floored corner in soft daylight, a little
    monstera in a terracotta pot, then a huge one filling the corner from a basket."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, "#ffffff"))
    pw = (w - 10) / 2
    for i, big in enumerate((False, True)):
        x0 = i * (pw + 10)
        cid = p.clip(R(x0, 0, pw, h, "#fff"))
        p.body.append(f'<g clip-path="{cid}">')
        corner_room(p, x0, pw, h, big, random.Random(7 + i))
        p.body.append("</g>")


def pothos(x, y, length, ang, rnd, p, col="#4f9a46"):
    """A heart-shaped pothos leaf with pale-yellow marbling, base at (x, y)."""
    L_, W = length, length * .42
    d = (f"M0,0 C{n(W * .9)},{n(L_ * .12)} {n(W * 1.3)},{n(-L_ * .45)} 0,{n(-L_)} "
         f"C{n(-W * 1.3)},{n(-L_ * .45)} {n(-W * .9)},{n(L_ * .12)} 0,0 Z")
    cid = p.clip(P(d, "#fff"))
    streaks = "".join(P(f"M{n(rnd.uniform(-W, W))},{n(rnd.uniform(-L_ * .2, 0))} C{n(rnd.uniform(-W, W))},{n(-L_ * .4)} "
                        f"{n(rnd.uniform(-W, W))},{n(-L_ * .6)} {n(rnd.uniform(-W * .3, W * .3))},{n(-L_)}",
                        "none", stroke="#f3eca0", stroke_width=n(rnd.uniform(5, 10)), opacity=.38, stroke_linecap="round") for _ in range(3))
    return (f'<g transform="translate({n(x)} {n(y)}) rotate({n(ang)})">'
            + P(d, p.lg((0, dk(col, .12)), (.5, col), (.5, lt(col, .1)), (1, lt(col, .2)), x2=1, y2=0))
            + G(streaks, clip_path=cid) + L(0, 0, 0, -L_ * .9, lt(col, .4), 1.5, opacity=.6) + "</g>")


def reddit_1(p):
    """Bright morning, backlit: five odd glass jars on a white sill, pothos cuttings trailing white
    roots in the water, their shadows and caustics thrown toward the camera."""
    w, h = p.w, p.h
    rnd = random.Random(171)
    # the view: sky, soft trees
    p.add(R(0, 0, w, 400, p.lg("#a9d4f2", "#d6ecf8", "#eef7fb")))
    p.add(bokeh(p, [(rnd.uniform(0, w), rnd.uniform(240, 380), rnd.uniform(40, 90),
                     rnd.choice(["#8fbf7a", "#a5cc8a", "#7fae6c"]), .7) for _ in range(16)], 14))
    p.add(p.soft(C(650, 60, 120, "#ffffff", opacity=.95), 40))
    p.add(window_panes(18, 0, w - 36, 380, "#f7f5f0", 18, cols=2, rows=1))
    p.add(R(0, 0, 18, 400, "#f1eee7"), R(w - 18, 0, 18, 400, "#e8e4db"))
    # sill
    p.add(PL([(0, 380), (w, 380), (w, 520), (0, 520)], p.lg("#fbf9f4", "#f1ece2")))
    p.add(R(0, 520, w, 36, p.lg("#e6e0d4", "#d6cfc1")))
    p.add(R(0, 556, w, 44, p.lg("#cfc7b8", "#bdb4a3")))
    jars = [(120, 470, 92, 118, "mason"), (262, 462, 66, 170, "bottle"), (402, 476, 104, 98, "tumbler"),
            (546, 466, 80, 104, "jam"), (684, 470, 74, 146, "tall")]
    # shadows and caustics, thrown forward-left
    for (cx, by, jw, jh, kind) in jars:
        p.add(p.soft(PL([(cx - jw / 2, by), (cx + jw / 2, by), (cx + jw / 2 - 40, by + 52), (cx - jw / 2 - 70, by + 54)], "#8a8f86"), 6, .35))
        p.add(p.soft(E(cx - 30, by + 30, jw * .28, 9, "#fff6c8", opacity=.9), 4))
    for i, (cx, by, jw, jh, kind) in enumerate(jars):
        top = by - jh
        mouth = jw * (.36 if kind == "bottle" else .5)
        water = by - jh * (.5 if kind != "bottle" else .42)
        # back wall of the glass
        if kind == "bottle":
            body = (f"M{cx - jw / 2},{by - 8} L{cx - jw / 2},{by - jh * .55} C{cx - jw / 2},{by - jh * .7} {cx - mouth / 2},{by - jh * .75} "
                    f"{cx - mouth / 2},{by - jh * .82} L{cx - mouth / 2},{top} L{cx + mouth / 2},{top} L{cx + mouth / 2},{by - jh * .82} "
                    f"C{cx + mouth / 2},{by - jh * .75} {cx + jw / 2},{by - jh * .7} {cx + jw / 2},{by - jh * .55} L{cx + jw / 2},{by - 8} "
                    f"Q{cx + jw / 2},{by} {cx + jw / 2 - 8},{by} L{cx - jw / 2 + 8},{by} Q{cx - jw / 2},{by} {cx - jw / 2},{by - 8} Z")
        else:
            tw = jw * (.94 if kind == "tumbler" else 1)
            body = (f"M{cx - jw / 2},{by - 10} L{cx - tw / 2},{top} L{cx + tw / 2},{top} L{cx + jw / 2},{by - 10} "
                    f"Q{cx + jw / 2},{by} {cx + jw / 2 - 10},{by} L{cx - jw / 2 + 10},{by} Q{cx - jw / 2},{by} {cx - jw / 2},{by - 10} Z")
        p.add(P(body, "#e9f4f2", opacity=.55))
        wcid = p.clip(P(body, "#fff"))
        p.add(G(R(cx - jw, water, jw * 2, jh, "#8fc7c3", opacity=.4), clip_path=wcid))
        # stems and roots inside
        stems = rnd.randint(2, 3)
        for k in range(stems):
            sx = cx + (k - (stems - 1) / 2) * mouth * .3
            p.add(L(sx, top - 6, sx + rnd.uniform(-6, 6), water + 18, "#5d8a3e", 4))
            ry0 = water + 14
            for _ in range(6):
                rx_ = sx + rnd.uniform(-4, 4)
                ln = rnd.uniform(.55, 1) * (by - ry0 - 8)
                ex = rx_ + rnd.uniform(-jw * .32, jw * .32)
                d_ = f"M{n(rx_)},{n(ry0)} C{n(rx_ + rnd.uniform(-14, 14))},{n(ry0 + ln * .4)} {n(ex + rnd.uniform(-10, 10))},{n(ry0 + ln * .7)} {n(ex)},{n(ry0 + ln)}"
                wd = rnd.uniform(2.4, 3.6)
                p.add(P(d_, "none", stroke="#9fa894", stroke_width=n(wd + 1.6), stroke_linecap="round", opacity=.55))
                p.add(P(d_, "none", stroke="#fbf8ec", stroke_width=n(wd), stroke_linecap="round"))
        # water, then the glass's front
        p.add(G(R(cx - jw, water, jw * 2, jh, "#9fd2cf", opacity=.12),
                E(cx, water, jw * .6, 5, "#ffffff", opacity=.6), clip_path=wcid))
        p.add(P(body, "none", stroke="#ffffff", stroke_width=2.5, opacity=.75))
        p.add(G(R(cx - jw / 2, top, 7, jh, "#7aa9a8", opacity=.3), R(cx + jw / 2 - 7, top, 7, jh, "#7aa9a8", opacity=.3),
                R(cx - jw * .3, top + 10, 6, jh - 26, "#ffffff", opacity=.7), clip_path=wcid))
        p.add(E(cx, by - 4, jw * .44, 5, "#cfe6e2", opacity=.8))
        if kind == "mason":
            for k in range(3):
                p.add(R(cx - jw / 2, top + 4 + k * 6, jw, 2.5, "#ffffff", opacity=.6))
        p.add(E(cx, top, mouth / 2 if kind == "bottle" else jw / 2 * (.94 if kind == "tumbler" else 1), 4, "none", stroke="#ffffff", stroke_width=2))
        # the cuttings' leaves above the mouth
        for k in range(rnd.randint(3, 4)):
            ang = rnd.uniform(-70, 70)
            sx, sy = cx + rnd.uniform(-8, 8), top - 4
            ex, ey = sx + math.sin(math.radians(ang)) * rnd.uniform(26, 60), sy - math.cos(math.radians(ang)) * rnd.uniform(20, 50)
            p.add(P(f"M{n(sx)},{n(sy)} Q{n(sx)},{n(ey)} {n(ex)},{n(ey)}", "none", stroke="#5d8a3e", stroke_width=3))
            p.add(pothos(ex, ey, rnd.uniform(44, 62), ang + rnd.uniform(-20, 20), rnd, p, col=rnd.choice(["#4f9a46", "#5aa84c", "#468e40"])))
    p.add(p.soft(PL([(560, 0), (800, 0), (800, 600), (420, 600)], "#fffbe8", opacity=.18), 30))


# ── the workshop ──────────────────────────────────────────────────────────


def sawhorse(p, x, top, foot, width=120):
    """A pine A-frame sawhorse seen three-quarters on: back legs darker, a brace, the top beam."""
    pine, pd = "#e2c08a", "#b8955e"
    out = [limb((x - width / 2 + 16, top + 8), (x - width / 2 - 6, foot - 30), 14, 14, pd),
           limb((x + width / 2 - 16, top + 8), (x + width / 2 + 2, foot - 30), 14, 14, pd),
           limb((x - width / 2 + 22, top + 10), (x - width / 2 - 20, foot), 16, 16, pine),
           limb((x + width / 2 - 22, top + 10), (x + width / 2 + 16, foot), 16, 16, pine),
           R(x - width / 2 - 8, (top + foot) / 2 + 10, width + 16, 12, pd, rx=2),
           R(x - width / 2 - 10, top - 4, width + 20, 22, p.lg("#efd3a2", pine, pd), rx=3)]
    return "".join(out)


def bsky_2(p):
    """A small workshop in late-afternoon window light: a walnut shelf across two pine sawhorses,
    freshly sanded, the right end wet with its first coat; sandpaper, an oil tin, sawdust."""
    w, h = p.w, p.h
    rnd = random.Random(181)
    # plywood wall, a window, clamps on a rail
    p.add(R(0, 0, w, 400, p.lg("#d8b98d", "#c9a676")))
    for x in (0, 244, 488, 732):
        p.add(L(x, 0, x, 400, "#a7834f", 2, opacity=.6))
    p.add(grain(p, 0, 0, w, 400, "#b08a55", k=16, op=.22, seed=31, vertical=True, wav=14))
    p.add(R(40, 40, 230, 190, p.lg("#cfe2d6", "#9fc2a8")))
    p.add(bokeh(p, [(90, 170, 40, "#7fae6c", .6), (200, 150, 50, "#6f9d5c", .55), (150, 90, 30, "#ffffff", .5)], 10))
    p.add(window_panes(40, 40, 230, 190, "#efe9de", 12, cols=2, rows=2))
    p.add(p.soft(PL([(70, 240), (300, 240), (560, 600), (60, 600)], "#fff1cc", opacity=.28), 30))
    p.add(R(470, 80, 290, 12, "#6b4a2a"))
    for i, x in enumerate((500, 560, 620, 680, 730)):
        col = ["#d6453b", "#f2a33a", "#d6453b", "#3a6fb0", "#f2a33a"][i]
        p.add(R(x, 92, 8, 130 + (i % 2) * 20, chrome(p, "#8f969d")))
        p.add(R(x - 4, 96, 34, 12, "#5a5f66", rx=2), R(x - 4, 150 + (i % 2) * 20, 34, 12, "#5a5f66", rx=2))
        p.add(R(x + 22, 108, 14, 40 + (i % 2) * 18, col, rx=6))
    # concrete floor
    p.add(R(0, 400, w, 200, p.lg("#a8a49c", "#8e8a82")))
    p.add(R(0, 396, w, 8, "#7a6a55"))
    p.add(p.soft(PL([(120, 420), (360, 420), (520, 600), (90, 600)], "#fff1cc", opacity=.25), 24))
    # sawdust on the floor
    for (sx, sy, r_) in ((200, 520, 70), (560, 510, 80), (380, 560, 50)):
        p.add(p.soft(E(sx, sy, r_, r_ * .22, "#e8d3ab", opacity=.85), 8))
    p.add(flour(p, (120, 470, 680, 590), 120, rnd, col="#f0dcb6", op=.8))
    # sawhorses
    p.add(p.soft(E(220, 540, 110, 14, "#3a3026"), 8, .5), p.soft(E(590, 536, 110, 14, "#3a3026"), 8, .5))
    p.add(sawhorse(p, 220, 380, 540), sawhorse(p, 590, 376, 536))
    # the walnut board
    top = [(70, 330), (730, 316), (748, 356), (60, 374)]
    p.add(p.soft(PL([(70, 380), (748, 362), (760, 400), (60, 420)], "#2a1a10"), 10, .5))
    p.add(PL([(60, 374), (748, 356), (748, 378), (60, 396)], p.lg("#4a2c1c", "#2e1a10")))
    p.add(PL([(60, 374), (70, 330), (70, 352), (60, 396)], "#5a3826"))
    p.add(PL(top, p.lg("#86604a", "#7a5540", x2=1, y2=0)))
    cid = p.clip(PL(top, "#fff"))
    g = [grain(p, 40, 300, 740, 90, "#4a2c1c", k=18, op=.55, seed=41, wav=5),
         grain(p, 40, 300, 740, 90, "#a07a5e", k=8, op=.35, seed=42, wav=4)]
    oiled = subquad(top, .64, 0, 1, 1)
    g.append(PL(oiled, p.lg("#5a321c", "#4a2814", x2=1, y2=0), opacity=.88))
    g.append(grain(p, 480, 300, 300, 90, "#2a140a", k=8, op=.5, seed=43, wav=4))
    g.append(p.soft(PL(subquad(top, .7, .1, .9, .45), "#ffe6c0", opacity=.45), 6))
    g.append(PL(subquad(top, 0, 0, .62, 1), "#e8dccb", opacity=.12))
    p.add(G(*g, clip_path=cid))
    p.add(PL(subquad([(60, 374), (748, 356), (748, 378), (60, 396)], .64, 0, 1, 1), "#1e0f06", opacity=.5))
    p.add(flour(p, (120, 330, 420, 370), 60, rnd, col="#e8d3ab", op=.8))
    # sanding block wrapped in paper, loose sheets
    p.add(p.soft(R(206, 336, 100, 30, "#1a0f08", rx=6, transform="rotate(-4 256 351)"), 4, .5))
    p.add(R(200, 326, 100, 28, "#c9935a", rx=6, transform="rotate(-4 250 340)"))
    p.add(R(204, 322, 92, 12, "#e8c08a", rx=5, transform="rotate(-4 250 328)"))
    for (pts_, col) in (([(330, 452), (420, 440), (446, 476), (352, 492)], "#d8b27a"),
                        ([(372, 470), (462, 474), (452, 512), (360, 506)], "#c46a4a")):
        p.add(p.soft(PL([(x_ + 3, y_ + 4) for x_, y_ in pts_], "#2a1a10"), 3, .35))
        p.add(PL(pts_, col))
        p.add(G(*[C(rnd.uniform(min(a for a, _ in pts_) + 8, max(a for a, _ in pts_) - 8),
                    rnd.uniform(min(b for _, b in pts_) + 6, max(b for _, b in pts_) - 6), .9, dk(col, .3)) for _ in range(40)], opacity=.6))
    p.add(PL([(446, 476), (420, 440), (432, 444), (452, 470)], "#f3ead8"))      # a curled corner, paper side up
    p.add(PL([(330, 338), (392, 334), (398, 352), (334, 357)], "#d8b27a", opacity=.95))
    # the oil tin and a rag on the floor by the right sawhorse
    tx, ty = 700, 500
    p.add(p.soft(E(tx + 10, ty + 4, 44, 10, "#2a1a10"), 5, .6))
    p.add(R(tx - 36, ty - 70, 72, 70, chrome(p, "#b5a14e"), rx=3))
    p.add(R(tx - 36, ty - 52, 72, 30, "#2f4a3c"))
    p.add(R(tx - 30, ty - 46, 20, 18, "#c9a04a", rx=2))
    p.add(E(tx, ty - 70, 36, 8, "#d9cfa0"), E(tx, ty - 70, 20, 4, "#8f8a70"))
    p.add(E(tx, ty, 36, 6, "#7a6a2a"))
    p.add(P("M600,520 C610,494 640,496 650,508 C668,502 684,520 670,534 C650,546 610,544 600,520 Z", "#f1ece2"))
    p.add(P("M612,520 C622,506 640,508 646,516", "none", stroke="#c9b9a0", stroke_width=3))
    p.add(P("M640,528 C650,520 664,524 664,530", "none", stroke="#6b3a1c", stroke_width=4, opacity=.6))


DRAW.update({
    "tt-post-0": tt_post_0, "tt-post-1": tt_post_1, "tt-post-2": tt_post_2, "tt-post-3": tt_post_3,
    "tt-notice-0": tt_notice_0, "tt-notice-1": tt_notice_1, "reddit-0": reddit_0, "reddit-1": reddit_1,
    "bsky-2": bsky_2,
})
