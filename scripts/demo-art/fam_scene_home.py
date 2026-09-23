"""fam_scene_home — drawn "photographs" of food, rooms, objects and craft.

Every picture is one SVG built from the small motif helpers below, one
composition function per key. They stand in for photographs, so they carry no
words — except the two a subject asks for (a scale reading 36.0 g, a timer
reading 0:18).

Distinctness is the point of the whole table: the coffee subjects (ten of
them), the ceramics, the pastry and the windowsills each take a different
viewpoint, surface, palette and time of day. The notes on each function say
which one, so a later edit does not drift two of them together.
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


# ── coffee (ten subjects, ten set-ups) ────────────────────────────────────


def tt_post_0(p):
    """Espresso into a glass on a scale reading 36.0 g — dark, eye-level, chrome and amber."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.rg((0, "#3a302a"), (.6, "#171311"), (1, "#0b0909"), cx=.3, cy=.35, r=.9)))
    # group head
    p.add(R(70, -20, 310, 150, chrome(p, "#7c7f86"), rx=18))
    p.add(R(70, 118, 310, 14, "#121212"))
    # portafilter body + handle out to the left
    p.add(P("M120,132 L330,132 L312,196 L138,196 Z", p.lg("#2a2a2c", "#0f0f10", x2=0, y2=1)))
    p.add(R(-20, 142, 160, 34, p.lg("#1b1b1c", "#050505"), rx=14))
    p.add(R(180, 196, 90, 18, chrome(p, "#6e7076"), rx=4))
    # double spout
    for sx in (196, 254):
        p.add(P(f"M{sx - 12},212 L{sx + 12},212 L{sx + 6},250 L{sx - 6},250 Z", chrome(p, "#6e7076")))
    # streams
    for i, sx in enumerate((196, 254)):
        d = f"M{sx - 3},250 C{sx - 2},330 {sx + (6 if i == 0 else -6)},400 {sx + (14 if i == 0 else -14)},470 L{sx + (18 if i == 0 else -10)},470 C{sx + 8},400 {sx + 3},330 {sx + 3},250 Z"
        p.add(P(d, p.lg("#5a2e12", "#b36a2c", "#6b3614")))
    p.add(p.soft(E(225, 480, 60, 14, "#e6a45a", opacity=.25), 12))
    # glass: back rim, liquid, glass walls
    gx0, gx1, gy0, gy1 = 150, 300, 440, 612
    p.add(E(225, gy0, 75, 12, "#ffffff", opacity=.07))
    p.add(P(f"M{gx0 + 6},520 L{gx1 - 6},520 L{gx1 - 12},{gy1 - 8} Q225,{gy1 + 4} {gx0 + 12},{gy1 - 8} Z", p.lg("#3b1a09", "#1a0a03")))
    p.add(P(f"M{gx0 + 6},490 L{gx1 - 6},490 L{gx1 - 6},522 L{gx0 + 6},522 Z", p.lg("#d99a55", "#a4612c", "#5a2c10")))
    p.add(E(225, 490, 69, 10, p.rg("#f0c186", "#c98642", "#9a5a28", cx=.45, cy=.4, r=.6)))
    p.add(P(f"M{gx0},{gy0} L{gx1},{gy0} L{gx1 - 8},{gy1} Q225,{gy1 + 10} {gx0 + 8},{gy1} Z", "#ffffff", opacity=.08))
    p.add(P(f"M{gx0 + 14},{gy0 + 10} L{gx0 + 26},{gy0 + 10} L{gx0 + 30},{gy1 - 16} L{gx0 + 20},{gy1 - 16} Z", "#ffffff", opacity=.28))
    p.add(P(f"M{gx1 - 30},{gy0 + 20} L{gx1 - 24},{gy0 + 20} L{gx1 - 26},{gy1 - 30} L{gx1 - 31},{gy1 - 30} Z", "#ffffff", opacity=.16))
    p.add(E(225, gy0, 75, 12, "none", stroke="#ffffff", stroke_width=2, opacity=.4))
    # scale
    p.add(PL([(52, 624), (398, 624), (412, 646), (38, 646)], "#2b2c2f"))
    p.add(PL([(52, 624), (398, 624), (405, 634), (45, 634)], "#44464b"))
    p.add(R(38, 646, 374, 70, p.lg("#1a1b1d", "#0c0c0d"), rx=6))
    p.add(R(122, 660, 206, 42, "#07090a", rx=5))
    p.add(p.soft(T(225, 693, "36.0 g", fill="#8fe3ff", font_family="Menlo, monospace", font_size=34,
                   text_anchor="middle", font_weight="bold"), 6, .7))
    p.add(T(225, 693, "36.0 g", fill="#c9f3ff", font_family="Menlo, monospace", font_size=34,
            text_anchor="middle", font_weight="bold"))
    # drip tray
    p.add(R(0, 716, w, 84, p.lg("#2c2d30", "#101113")))
    for x in range(-10, w + 20, 26):
        p.add(R(x, 730, 12, 70, "#070708", rx=3))
    # rim light from upper-left
    p.add(p.soft(R(40, 0, 30, h, "#ffcf9a", opacity=.05), 30))


def tt_notice_1(p):
    """A fast, pale shot and a 0:18 timer — bright daylight, pale-blue machine, white cup."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#f4f1ec", "#e7e2da")))
    # machine face: cream enamel, chrome trim, a round badge; the group underneath
    p.add(p.soft(R(-20, 180, w + 40, 30, "#8f8778", opacity=.5), 12))
    p.add(R(-20, -40, w + 40, 236, p.lg((0, "#f3e3c2"), (.7, "#e9d3a8"), (1, "#cdb384")), rx=26))
    p.add(R(-20, 176, w + 40, 20, chrome(p, "#9aa3aa", horizontal=False)))
    p.add(C(225, 80, 34, chrome(p, "#9aa3aa")))
    p.add(C(225, 80, 26, "#b5412f"))
    p.add(R(145, 190, 160, 40, chrome(p, "#9aa3aa"), rx=10))
    p.add(R(0, 206, 190, 30, p.lg("#2b2b2b", "#141414"), rx=15))
    p.add(P("M170,226 L280,226 L268,262 L182,262 Z", chrome(p, "#9aa3aa")))
    p.add(P("M214,262 L236,262 L232,286 L218,286 Z", chrome(p, "#8b939a")))
    # fast pale gush, spraying a little
    p.add(P("M216,286 C212,360 206,430 200,520 L250,520 C244,430 238,360 234,286 Z",
            p.lg((0, "#e9bf7c"), (.5, "#d9a25d"), (1, "#c98a45"), x2=1, y2=0)))
    p.add(P("M221,290 C219,360 216,430 214,515 L222,515 C223,430 225,360 226,290 Z", "#fff3d8", opacity=.55))
    rnd = random.Random(7)
    for _ in range(9):
        y = rnd.uniform(330, 500)
        x = 225 + rnd.choice([-1, 1]) * rnd.uniform(26, 44)
        p.add(C(x, y, rnd.uniform(2, 3.6), "#d9a25d", opacity=.8))
    # white cup
    p.add(p.soft(E(225, 626, 96, 16, "#7d7466", opacity=.4), 8))
    p.add(cup_side(p, 225, 620, 150, 118, "#fbfaf7", liquid="#d6a061", handle="right", persp=.16))
    p.add(p.soft(E(222, 507, 32, 8, "#fff3d8", opacity=.7), 3))
    # drip tray grill
    p.add(R(0, 628, w, 172, p.lg("#c9ccd0", "#9ea3a8")))
    for y in range(640, 800, 20):
        p.add(R(0, y, w, 8, "#8a8f95", opacity=.55))
    # timer on the tray
    p.add(p.soft(R(292, 552, 150, 88, "#6d665c", rx=18, opacity=.35), 8))
    p.add(R(286, 540, 150, 90, p.lg("#ffffff", "#e3e1dc"), rx=18))
    p.add(R(300, 554, 122, 50, "#20241f", rx=8))
    p.add(p.soft(T(361, 594, "0:18", fill="#ff6a3d", font_family="Menlo, monospace", font_size=38,
                   text_anchor="middle", font_weight="bold"), 5, .8))
    p.add(T(361, 594, "0:18", fill="#ff9a70", font_family="Menlo, monospace", font_size=38,
            text_anchor="middle", font_weight="bold"))
    p.add(C(320, 616, 5, "#e4644a"))
    p.add(C(402, 616, 5, "#b9b6b0"))


def portafilter_top(p, cx, cy, r, handle_angle, puck, tamped=False, handle_col="#1d1a18"):
    """Top-down portafilter: chrome ring, basket, coffee bed, handle at an angle (deg, 90 = down)."""
    a = math.radians(handle_angle)
    out = []
    hx, hy = cx + math.cos(a) * r * .95, cy + math.sin(a) * r * .95
    out.append(f'<g transform="translate({n(hx)} {n(hy)}) rotate({n(handle_angle)})">'
               + R(-6, -r * .2, r * .38, r * .4, chrome(p, "#8d9298", horizontal=False), rx=6)
               + R(r * .3, -r * .17, r * 1.7, r * .34, p.lg(lt(handle_col, .18), handle_col, dk(handle_col, .5), x2=0, y2=1), rx=r * .17)
               + R(r * .36, -r * .1, r * 1.55, r * .05, "#ffffff", rx=3, opacity=.18) + "</g>")
    for ang in (handle_angle + 90, handle_angle - 90):
        b = math.radians(ang)
        out.append(C(cx + math.cos(b) * r * .98, cy + math.sin(b) * r * .98, r * .13, chrome(p, "#8d9298")))
    out.append(C(cx, cy, r, p.rg((0, "#d6d9dd"), (.8, "#a7acb2"), (.9, "#eef0f2"), (1, "#6f757c"))))
    out.append(C(cx, cy, r * .86, p.lg("#5f656b", "#c9cdd1", "#7a8087", x2=1, y2=1)))
    out.append(C(cx, cy, r * .8, "#2b2724"))
    out.append(C(cx, cy, r * .78, p.rg(*puck, cx=.42, cy=.4, r=.62)))
    if tamped:
        out.append(C(cx, cy, r * .72, "none", stroke="#ffffff", stroke_width=1.5, opacity=.12))
    return "".join(out)


def tt_post_3(p):
    """Macro, top-down: a portafilter full of levelled grounds, a WDT tool — pale oak, soft north light."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#e2c9a3", "#d2b389", x2=1, y2=1)))
    p.add(grain(p, 0, 0, w, h, "#a8834f", k=22, op=.3, seed=11, vertical=True, wav=10))
    cx, cy, r = 225, 330, 172
    shadow = C(cx + 22, cy + 30, r, "#4d3517") + R(cx - 30, cy + 100, 90, 420, "#4d3517", rx=40)
    p.add(p.soft(shadow, 16, .35))
    p.add(portafilter_top(p, cx, cy, r, 92, [(0, "#6b4428"), (.55, "#4e301b"), (1, "#3a2313")]))
    # the levelled bed: a faint polish ring
    p.add(C(cx, cy, r * .6, "none", stroke="#8a5d3a", stroke_width=10, opacity=.18))
    p.add(p.soft(E(cx - 40, cy - 50, 60, 30, "#9b6c46", opacity=.35), 18))
    # WDT tool lying diagonally at the lower right
    g = []
    g.append(R(0, -13, 120, 26, p.lg("#8a5a36", "#5b3a20", "#3d2613", x2=0, y2=1), rx=13))
    g.append(R(8, -9, 100, 5, "#ffffff", rx=2, opacity=.2))
    g.append(R(118, -9, 22, 18, chrome(p, "#9aa0a6", horizontal=False), rx=4))
    for k in range(-3, 4):
        g.append(L(140, k * 2.5, 250, k * 6.5, "#d9dde1", 1.4))
    p.add(p.soft(f'<g transform="translate(212 640) rotate(-32)">{R(6, -8, 250, 26, "#4d3517", rx=12)}</g>', 8, .35))
    p.add(f'<g transform="translate(200 622) rotate(-32)">{"".join(g)}</g>')
    # a few stray grounds
    rnd = random.Random(4)
    for _ in range(16):
        p.add(C(rnd.uniform(40, 420), rnd.uniform(560, 780), rnd.uniform(1.2, 2.4), "#3a2313", opacity=.7))


def reddit_1(p):
    """Wide flat lay on a sage tamping mat: portafilter (tamped), a lying tamper, a distribution tool."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#efe9df", "#e3dccf", x2=1, y2=1)))
    p.add(p.soft(R(58, 58, 700, 500, "#6d7162", rx=40), 14, .35))
    p.add(R(46, 44, 700, 500, p.lg("#b5c4ab", "#9fb096", x2=1, y2=1), rx=40))
    p.add(R(46, 44, 700, 500, "none", rx=40, stroke="#cfdcc6", stroke_width=3, opacity=.6))
    # portafilter, handle toward lower-left
    cx, cy = 300, 260
    p.add(p.soft(C(cx + 12, cy + 16, 120, "#3f4a3a") +
                 f'<g transform="translate({cx + 12} {cy + 16}) rotate(145)">{R(100, -22, 230, 44, "#3f4a3a", rx=22)}</g>', 10, .4))
    p.add(portafilter_top(p, cx, cy, 118, 145, [(0, "#5c3a22"), (.7, "#4a2d19"), (1, "#3b2313")], tamped=True, handle_col="#6b4428"))
    p.add(C(cx - 20, cy - 24, 58, "#ffffff", opacity=.05))
    # tamper lying on its side, upper right
    tx, ty = 560, 170
    t = [R(-18, -62, 36, 124, chrome(p, "#8f969d"), rx=6),
         P("M18,-18 L60,-12 L60,12 L18,18 Z", chrome(p, "#8f969d", horizontal=False)),
         E(98, 0, 46, 34, p.lg("#8a5a36", "#5e3b20", "#40271a", x2=0, y2=1)),
         E(92, -12, 26, 9, "#ffffff", opacity=.18)]
    p.add(p.soft(f'<g transform="translate({tx + 10} {ty + 14}) rotate(8)">{R(-18, -62, 36, 124, "#3f4a3a")}{E(98, 0, 46, 34, "#3f4a3a")}</g>', 8, .4))
    p.add(f'<g transform="translate({tx} {ty}) rotate(8)">{"".join(t)}</g>')
    # distribution tool, upside down so its vanes show
    dx, dy, dr = 590, 390, 80
    p.add(p.soft(C(dx + 10, dy + 14, dr, "#3f4a3a"), 8, .4))
    p.add(C(dx, dy, dr, p.rg("#d9dcdf", "#b3b8bd", "#6f757c")))
    p.add(C(dx, dy, dr * .86, "#8d949b"))
    vanes = []
    for k in range(4):
        vanes.append(f'<g transform="rotate({k * 90})"><path d="M8,-6 C30,-40 52,-42 64,-26 L58,-18 C46,-28 30,-24 14,4 Z" fill="{p.lg("#e8eaec", "#9aa1a8")}"/></g>')
    p.add(f'<g transform="translate({dx} {dy})">{"".join(vanes)}</g>')
    p.add(C(dx, dy, 12, chrome(p, "#8f969d")))
    # a few grounds on the mat
    rnd = random.Random(2)
    for _ in range(10):
        p.add(C(rnd.uniform(420, 520), rnd.uniform(420, 520), rnd.uniform(1.5, 2.6), "#3b2313", opacity=.7))


def reddit_0(p):
    """An old chrome lever machine on butcher block, oxblood wall, warm lamp from the left."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.rg("#8a3a33", "#5c211e", "#3a1413", cx=.3, cy=.3, r=.9)))
    p.add(p.soft(E(170, 140, 220, 160, "#f5b673", opacity=.25), 40))
    # counter
    p.add(R(0, 470, w, 130, p.lg("#b88453", "#8c5c33")))
    p.add(R(0, 470, w, 8, "#d9a574"))
    p.add(grain(p, 0, 478, w, 122, "#6b4323", k=12, op=.35, seed=5))
    p.add(p.soft(E(430, 474, 230, 20, "#2a120c", opacity=.6), 10))
    # base
    p.add(R(270, 360, 320, 116, chrome(p, "#8c6a62"), rx=10))
    p.add(R(270, 360, 320, 8, "#f6e0d4", opacity=.5))
    # boiler
    p.add(R(310, 130, 240, 236, chrome(p, "#8c6a62"), rx=6))
    p.add(P("M310,132 C310,40 550,40 550,132 Z", p.lg("#f6ece6", "#b28e84", "#6b4a42", x2=1, y2=1)))
    p.add(C(430, 58, 16, "#241816"))
    p.add(E(425, 52, 6, 3, "#ffffff", opacity=.5))
    # a brass band
    p.add(R(310, 220, 240, 14, p.lg("#e7c27a", "#b08638", "#7a5a22", x2=1, y2=0)))
    # gauge
    p.add(C(370, 290, 30, "#1c1515"))
    p.add(C(370, 290, 25, p.rg("#fbf5e8", "#e6dcc6")))
    for k in range(9):
        a = math.radians(140 + k * 32.5)
        p.add(L(370 + math.cos(a) * 17, 290 + math.sin(a) * 17, 370 + math.cos(a) * 22, 290 + math.sin(a) * 22, "#3b2b28", 1.4))
    p.add(L(370, 290, 385, 279, "#b32a1f", 2.2))
    # group head
    p.add(R(440, 280, 70, 110, chrome(p, "#8c6a62"), rx=8))
    p.add(R(430, 386, 90, 20, chrome(p, "#6f5550"), rx=6))
    # lever
    p.add(P("M470,290 L630,40 L646,50 L486,300 Z", chrome(p, "#8c6a62")))
    p.add(C(640, 44, 22, p.rg("#4a3a36", "#140e0d", cx=.35, cy=.35)))
    p.add(C(634, 38, 6, "#ffffff", opacity=.35))
    # portafilter + handle toward the viewer (left)
    p.add(R(440, 404, 74, 22, "#1c1515", rx=6))
    p.add(P("M444,412 L300,440 L296,420 L440,404 Z", "#140e0d"))
    # cup on the tray
    p.add(R(420, 450, 110, 12, chrome(p, "#6f5550"), rx=4))
    p.add(cup_side(p, 476, 450, 44, 34, "#f2ece4", handle="right", persp=.2))


def bsky_2(p):
    """Daylight desk: a laptop with syntax-coloured code, an espresso on a saucer front-right."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#dfe4e8", "#c9d0d6")))
    p.add(p.soft(PL([(520, 0), (800, 0), (800, 330), (640, 330)], "#ffffff", opacity=.55), 24))
    p.add(PL([(0, 330), (w, 330), (w, h), (0, h)], p.lg("#e8d6bd", "#d4bc9a")))
    p.add(grain(p, 0, 330, w, 270, "#b89468", k=10, op=.25, seed=9))
    # laptop, angled a little
    sq = [(110, 60), (520, 40), (540, 330), (130, 336)]
    p.add(p.soft(PL([(120, 340), (600, 328), (720, 470), (60, 486)], "#5c4a36"), 14, .3))
    p.add(PL([(96, 50), (534, 28), (556, 338), (118, 346)], "#2f3236"))
    p.add(PL(sq, "#1b1f2b"))
    cols = ["#ff7a9c", "#7fd6e8", "#f2c96b", "#b59cff", "#9fe39a", "#c6cbd6"]
    rnd = random.Random(12)
    y = 0.07
    indent = 0
    while y < 0.93:
        u = 0.1 + indent * 0.05
        p.add(PL(subquad(sq, .035, y, .07, y + .022), "#565d70"))
        for _ in range(rnd.randint(1, 4)):
            ln = rnd.uniform(.05, .18)
            if u + ln > .95:
                break
            p.add(PL(subquad(sq, u, y, u + ln, y + .024), rnd.choice(cols), opacity=.9))
            u += ln + .02
        indent = max(0, min(4, indent + rnd.choice([-1, 0, 0, 1])))
        y += .052
    p.add(PL([(110, 60), (300, 50), (250, 336), (130, 336)], "#ffffff", opacity=.04))
    # deck
    deck = [(118, 346), (556, 338), (690, 470), (40, 490)]
    p.add(PL(deck, p.lg("#d9dce0", "#b7bcc2")))
    p.add(PL(subquad(deck, .1, .1, .9, .62), "#a4a9b0", opacity=.6))
    p.add(PL(subquad(deck, .38, .7, .62, .95), "#c7cbd0"))
    p.add(PL([(40, 490), (690, 470), (690, 478), (40, 498)], "#8f949a"))
    # espresso
    p.add(p.soft(E(640, 540, 100, 26, "#6a5238", opacity=.45), 10))
    p.add(cup_side(p, 628, 528, 96, 66, "#ffffff", liquid=p.rg("#c88b52", "#8a5129"), saucer="#f4f2ee", persp=.26))
    p.add(steam(p, 628, 450, 110, op=.5, wide=8, seed=4))


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


def tt_post_2(p):
    """Coffee at altitude: an enamel camp mug on a plank table, snowy peaks in a log-cabin window."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#2d6fb8", "#7fb4e3", "#cfe5f5")))
    # peaks
    p.add(PL([(-20, 470), (70, 330), (140, 380), (230, 240), (300, 330), (360, 290), (470, 420), (470, 520), (-20, 520)], "#e9f1f8"))
    p.add(PL([(230, 240), (300, 330), (270, 330), (240, 300), (210, 350), (180, 330)], "#9fb9d6"))
    p.add(PL([(70, 330), (140, 380), (110, 390), (60, 360)], "#a9c1db"))
    p.add(PL([(360, 290), (470, 420), (430, 420), (380, 360)], "#9fb9d6"))
    p.add(PL([(-20, 520), (-20, 440), (40, 470), (120, 430), (200, 470), (300, 440), (380, 470), (470, 450), (470, 520)], "#b7cde3"))
    trees = []
    rnd = random.Random(5)
    for i in range(24):
        x = i * 20 + rnd.uniform(-6, 6)
        th = rnd.uniform(40, 80)
        trees.append(PL([(x, 540 - th), (x - 12, 545), (x + 12, 545)], "#23443a"))
    p.add("".join(trees))
    p.add(R(0, 540, w, 20, "#1c3830"))
    # log window frame
    wood = p.lg("#9b6a3f", "#7a4f2c", "#5e3a1f", x2=1, y2=0)
    p.add(R(0, 0, 34, 560, wood), R(w - 34, 0, 34, 560, wood), R(0, 0, w, 30, wood))
    p.add(R(212, 30, 26, 520, wood))
    p.add(R(0, 530, w, 36, p.lg("#b07a4a", "#7a4f2c")))
    # table
    p.add(PL([(0, 566), (w, 566), (w, h), (0, h)], p.lg("#8e5b33", "#6a4022")))
    for x in (-40, 80, 200, 320, 440):
        p.add(L(x + 60, 566, x - 30, h, "#4e2e17", 3, opacity=.6))
    p.add(p.soft(PL([(0, 566), (w, 566), (w, 640), (0, 700)], "#ffe7b8", opacity=.18), 10))
    # enamel mug
    p.add(p.soft(E(210, 712, 92, 18, "#2e1a0c", opacity=.6), 8))
    mx, my = 214, 706
    p.add(cup_side(p, mx, my, 150, 140, "#f4f5f2", liquid=p.rg("#6b4127", "#2f1b10"), handle="right", persp=.18, inner="#e8ebea"))
    p.add(E(mx, my - 140, 75, 13.5, "none", stroke="#1f3f73", stroke_width=6))
    for (x, y, r) in [(170, 640, 5), (246, 610, 4), (200, 680, 3)]:
        p.add(C(x, y, r, "#8a9290", opacity=.5))
    p.add(steam(p, mx, 540, 150, op=.5, seed=9))


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


def jug(p, x, y, rot, s=1.0):
    """A steel milk jug whose spout tip sits at (x, y); rot tilts it (about 115 pours down-right)."""
    body = p.lg("#5f656b", "#c9ced3", "#f4f6f7", "#9aa1a8", "#50565c", x1=0, y1=0, x2=1, y2=0)
    g = [P("M-170,20 C-172,120 -178,170 -178,196 L6,196 C4,170 0,120 -2,20 Z", body),
         E(-86, 196, 92, 16, "#6f757b"),
         P("M-176,40 C-230,40 -236,150 -176,160", "none", stroke="#8a9096", stroke_width=14, stroke_linecap="round"),
         E(-86, 20, 84, 14, "#3d4247"),
         P("M-40,10 L0,0 L-6,26 Z", "#c9ced3"),
         E(-86, 20, 84, 14, "none", stroke="#eef0f2", stroke_width=3),
         R(-150, 40, 10, 140, "#ffffff", rx=4, opacity=.35)]
    return f'<g transform="translate({n(x)} {n(y)}) rotate({n(rot)}) scale({n(s)})">' + "".join(g) + "</g>"


def tt_notice_0(p):
    """Latte art from above-and-behind: a steel jug pouring into a teal bowl-cup, rosetta forming."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#3b2a22", "#241914")))
    p.add(bokeh(p, [(60, 90, 40, "#ffb866", .3), (380, 60, 55, "#ffd28f", .22), (330, 200, 26, "#ff9d57", .25),
                    (40, 300, 20, "#ffe2b0", .2), (420, 330, 36, "#ffb866", .18)], 10))
    p.add(R(0, 600, w, 200, p.lg("#5a4034", "#3a281f")))
    p.add(R(0, 600, w, 3, "#7a5a48", opacity=.6))
    cx, cy = 225, 520
    p.add(p.soft(E(cx, 742, 150, 22, "#140c08", opacity=.85), 10))
    # bowl, foot, rim
    p.add(R(cx - 70, 700, 140, 40, p.lg("#155055", "#2f9a98", "#123f43", x2=1, y2=0), rx=10))
    p.add(P(f"M{cx - 184},{cy} C{cx - 180},{cy + 170} {cx - 80},{cy + 196} {cx},{cy + 196} "
            f"C{cx + 80},{cy + 196} {cx + 180},{cy + 170} {cx + 184},{cy} Z",
            p.lg((0, "#155a5e"), (.3, "#3fb0ab"), (.5, "#2a8f8c"), (1, "#0f4448"), x2=1, y2=0)))
    p.add(p.soft(P(f"M{cx - 150},{cy + 30} C{cx - 140},{cy + 120} {cx - 100},{cy + 160} {cx - 80},{cy + 170}",
                   "none", stroke="#bff3ee", stroke_width=8, opacity=.45), 3))
    p.add(E(cx, cy, 184, 94, "#eee9df"))
    p.add(E(cx, cy + 4, 170, 85, p.rg("#c9874a", "#a3602d", "#7a4220", cx=.5, cy=.45, r=.6)))
    # rosetta: drawn from above, squashed into the ellipse; widest at the near side, heart at the tip
    lay = []
    k = 12
    for i in range(k):
        y = 92 - i * 12.5
        wd = 100 * math.sin(math.pi * (i + 1.5) / (k + 1.2)) ** .8 + 8
        th = 7
        lay.append(f'<path d="M{n(-wd)},{n(y + 10)} C{n(-wd * .7)},{n(y - 24)} {n(wd * .7)},{n(y - 24)} {n(wd)},{n(y + 10)} '
                   f'C{n(wd * .6)},{n(y - 24 + th * 2.2)} {n(-wd * .6)},{n(y - 24 + th * 2.2)} {n(-wd)},{n(y + 10)} Z" fill="#f7efe1"/>')
    heart = '<path d="M0,-66 C-30,-104 -56,-72 0,-50 C56,-72 30,-104 0,-66 Z" fill="#f7efe1"/>'
    stem = '<path d="M0,-86 L0,104" stroke="#f7efe1" stroke-width="5" stroke-linecap="round"/>'
    p.add(f'<g transform="translate({cx} {cy + 6}) scale(1 0.5)">' + "".join(lay) + heart + stem + "</g>")
    p.add(E(cx, cy, 184, 94, "none", stroke="#ffffff", stroke_width=3, opacity=.6))
    # the jug and its stream, landing on the heart
    p.add(P("M244,300 C250,360 240,420 228,498 L218,498 C226,420 236,360 234,302 Z", "#f7efe1"))
    p.add(jug(p, 252, 296, 118, 1.05))
    p.add(p.soft(E(224, 500, 18, 7, "#ffffff", opacity=.8), 3))


DRAW = {
    "tt-post-0": tt_post_0, "tt-notice-1": tt_notice_1, "tt-post-3": tt_post_3, "reddit-1": reddit_1,
    "reddit-0": reddit_0, "bsky-2": bsky_2, "x-photo-1": x_photo_1, "nostr-2b": nostr_2b,
    "tt-post-2": tt_post_2, "ig-save-0": ig_save_0, "tt-notice-0": tt_notice_0,
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


def tt_post_1(p):
    """Grinder teardown, knolled flat on a slate-blue mat: body, hopper, cone and ring burrs, screws, tools."""
    w, h = p.w, p.h
    p.add(R(0, 0, w, h, p.lg("#3e5a6c", "#2e4757", x2=1, y2=1)))
    p.add(p.soft(R(0, 0, w, 160, "#ffffff", opacity=.08), 40))

    def sh(item, dx=8, dy=10):
        return p.soft(f'<g transform="translate({dx} {dy})">{item}</g>', 7, .45)

    # grinder body without its hopper (top view)
    body = C(150, 170, 92, p.rg("#3a3a3c", "#1c1c1e")) + C(150, 170, 66, "#0e0e0f") + C(150, 170, 40, p.rg("#8b9197", "#4a5056"))
    p.add(sh(C(150, 170, 92, "#000")), body)
    # hopper (smoked translucent)
    p.add(sh(C(345, 150, 70, "#000"), 6, 8))
    p.add(C(345, 150, 70, "#8a6a4a", opacity=.45), C(345, 150, 70, "none", stroke="#d8c3a8", stroke_width=5, opacity=.8),
          C(330, 132, 30, "#ffffff", opacity=.15))
    # conical burr: spiral teeth
    cx, cy = 130, 400
    p.add(sh(C(cx, cy, 78, "#000")))
    p.add(C(cx, cy, 78, p.rg("#e7eaed", "#a9b0b6", "#6c737a")))
    p.add("".join(P(f"M{n(cx + math.cos(a) * 18)},{n(cy + math.sin(a) * 18)} Q{n(cx + math.cos(a + .5) * 50)},{n(cy + math.sin(a + .5) * 50)} {n(cx + math.cos(a + .9) * 76)},{n(cy + math.sin(a + .9) * 76)}",
                    "none", stroke="#5f666d", stroke_width=3) for a in [i * math.pi / 9 for i in range(18)]))
    p.add(C(cx, cy, 16, "#3a3f44"))
    # ring burr: teeth inward
    rx_, ry_ = 320, 410
    p.add(sh(C(rx_, ry_, 88, "#000")))
    p.add(C(rx_, ry_, 88, p.rg("#dfe3e6", "#a2a9b0")), C(rx_, ry_, 56, "#2e4757"))
    p.add("".join(L(rx_ + math.cos(a) * 56, ry_ + math.sin(a) * 56, rx_ + math.cos(a + .12) * 72, ry_ + math.sin(a + .12) * 72, "#6c737a", 3)
                  for a in [i * math.pi / 14 for i in range(28)]))
    # screws in a row, brass
    for i in range(5):
        x = 80 + i * 36
        p.add(sh(C(x, 560, 11, "#000"), 3, 4), C(x, 560, 11, p.rg("#f2d38b", "#b98a3a")), L(x - 6, 560, x + 6, 560, "#6e4f1c", 2.5))
    # springs / washers
    for i in range(3):
        x = 290 + i * 40
        p.add(C(x, 560, 13, "none", stroke="#b9c0c6", stroke_width=5))
    # hex key
    p.add(sh(P("M60,650 L300,650 L300,700", "none", stroke="#000", stroke_width=12)))
    p.add(P("M60,650 L300,650 L300,700", "none", stroke="#2a2d31", stroke_width=12, stroke_linejoin="round"),
          P("M64,647 L296,647", "none", stroke="#8a9096", stroke_width=2))
    # brush
    p.add(sh(R(60, 730, 250, 26, "#000", rx=10)))
    p.add(R(60, 730, 170, 26, "#d2442f", rx=10), R(226, 732, 26, 22, "#b9c0c6"), R(250, 728, 90, 30, "#e7d6b5", rx=4))
    p.add("".join(L(254 + i * 7, 730, 254 + i * 7, 756, "#c7b48c", 1.5) for i in range(12)))
    # a little heap of old grounds
    rnd = random.Random(81)
    p.add(p.soft(C(390, 700, 34, "#2a1a0e"), 6, .9))
    p.add(flour(p, (340, 650, 440, 750), 30, rnd, col="#3a2313", op=.9))


DRAW.update({
    "ig-photo-1": ig_photo_1, "ig-photo-3": ig_photo_3, "ig-save-5": ig_save_5, "ig-save-10": ig_save_10,
    "ig-like-1": ig_like_1, "tt-save-0": tt_save_0, "tt-save-1": tt_save_1, "snap-2": snap_2,
    "dayone-14": dayone_14, "tt-post-1": tt_post_1,
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
