"""fam_cover — made editorial images: thumbnails, article heads, bookmark and
page covers (see pictures.py, family `cover`).

Every picture is inline SVG in one self-contained page. Each key has its own
function below; the shared helpers at the top are only plumbing (the page,
shadows, wobbly marker strokes, isometric boxes), never a shared layout, so no
two pictures read as the same template with different words.
"""

import math
import random

# ── plumbing ──────────────────────────────────────────────────────────────

SANS = "system-ui, 'Helvetica Neue', sans-serif"
HEAVY = "'Avenir Next', system-ui, sans-serif"
COND = "'Avenir Next Condensed', 'DIN Condensed', system-ui, sans-serif"
SERIF = "'New York', Georgia, serif"
MONO = "Menlo, monospace"
MARKER = "'Marker Felt', 'Chalkboard SE', system-ui, sans-serif"


def page(w, h, inner, bg="#fff", css=""):
    return (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        f"html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:{bg}}}"
        "svg{display:block}" + css +
        f"</style></head><body>{inner}</body></html>"
    )


def svg(w, h, content, defs=""):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' "
            f"viewBox='0 0 {w} {h}'><defs>{defs}</defs>{content}</svg>")


def shadow(fid, dy=10, blur=14, op=0.28, color="#000"):
    return (f"<filter id='{fid}' x='-30%' y='-30%' width='160%' height='170%'>"
            f"<feDropShadow dx='0' dy='{dy}' stdDeviation='{blur}' flood-color='{color}' "
            f"flood-opacity='{op}'/></filter>")


def blur(fid, sd):
    return (f"<filter id='{fid}' x='-60%' y='-60%' width='220%' height='220%'>"
            f"<feGaussianBlur stdDeviation='{sd}'/></filter>")


def lin(gid, stops, x2=0, y2=1, x1=0, y1=0):
    s = "".join(f"<stop offset='{o}' stop-color='{c}'/>" for o, c in stops)
    return f"<linearGradient id='{gid}' x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}'>{s}</linearGradient>"


def rad(gid, stops, cx=0.5, cy=0.5, r=0.7):
    s = "".join(f"<stop offset='{o}' stop-color='{c}'/>" for o, c in stops)
    return f"<radialGradient id='{gid}' cx='{cx}' cy='{cy}' r='{r}'>{s}</radialGradient>"


def text(x, y, s, size, fill, family=SANS, weight=400, anchor="start", extra=""):
    return (f"<text x='{x}' y='{y}' font-family=\"{family}\" font-size='{size}' "
            f"font-weight='{weight}' fill='{fill}' text-anchor='{anchor}' {extra}>{s}</text>")


def poster(x, y, lines, size, fill, stroke, family=HEAVY, weight=800, lead=1.0, anchor="start", sw=10):
    """Thumbnail words: heavy type with an outline painted under the fill."""
    out = []
    for i, s in enumerate(lines):
        out.append(text(x, y + i * size * lead, s, size, fill, family, weight, anchor,
                        f"stroke='{stroke}' stroke-width='{sw}' paint-order='stroke' "
                        "stroke-linejoin='round'"))
    return "".join(out)


def pts(ps):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in ps)


def wobble_line(x1, y1, x2, y2, rng, amp=2.0):
    mx, my = (x1 + x2) / 2 + rng.uniform(-amp, amp), (y1 + y2) / 2 + rng.uniform(-amp, amp)
    return f"M{x1:.1f},{y1:.1f} Q{mx:.1f},{my:.1f} {x2:.1f},{y2:.1f}"


def marker_box(x, y, w, h, color, rng, sw=3.5):
    """A box drawn twice by hand: two slightly different passes."""
    out = []
    for k in range(2):
        j = lambda: rng.uniform(-3, 3)  # noqa: E731
        c = [(x + j(), y + j()), (x + w + j(), y + j()), (x + w + j(), y + h + j()), (x + j(), y + h + j())]
        d = "M" + " L".join(f"{a:.1f},{b:.1f}" for a, b in c) + f" L{c[0][0] + 6:.1f},{c[0][1] + j():.1f}"
        out.append(f"<path d='{d}' fill='none' stroke='{color}' stroke-width='{sw - k * 1.2}' "
                   "stroke-linecap='round' stroke-linejoin='round' opacity='.9'/>")
    return "".join(out)


def marker_ring(cx, cy, rx, ry, color, rng, sw=4):
    ps = []
    for i in range(34):
        t = i / 30 * 2 * math.pi
        k = 1 + rng.uniform(-0.03, 0.03)
        ps.append((cx + rx * k * math.cos(t), cy + ry * k * math.sin(t)))
    d = "M" + " L".join(f"{a:.1f},{b:.1f}" for a, b in ps)
    return (f"<path d='{d}' fill='none' stroke='{color}' stroke-width='{sw}' "
            "stroke-linecap='round' stroke-linejoin='round'/>")


def iso(ox, oy, s):
    c = math.cos(math.pi / 6)

    def P(x, y, z):
        return (ox + (x - y) * c * s, oy + (x + y) * 0.5 * s - z * s)
    return P


def iso_box(P, x, y, z, w, d, h, top, left, right, extra=""):
    t = z + h
    faces = [
        ([P(x, y + d, t), P(x + w, y + d, t), P(x + w, y + d, z), P(x, y + d, z)], left),
        ([P(x + w, y, t), P(x + w, y + d, t), P(x + w, y + d, z), P(x + w, y, z)], right),
        ([P(x, y, t), P(x + w, y, t), P(x + w, y + d, t), P(x, y + d, t)], top),
    ]
    return "".join(f"<polygon points='{pts(f)}' fill='{c}' {extra}/>" for f, c in faces)


def torn(x, y, w, h, rng, jag=5):
    """A strip of torn paper: straight sides, ragged top and bottom."""
    top = [(x + i * w / 16, y + rng.uniform(-jag, jag)) for i in range(17)]
    bot = [(x + w - i * w / 16, y + h + rng.uniform(-jag, jag)) for i in range(17)]
    return pts(top + bot)


# ── YouTube thumbnails (800×450) ──────────────────────────────────────────

def yt_0(w, h):
    """Computerphile: a code printout on continuous-feed paper, marked up."""
    rng = random.Random(7)
    bands = "".join(f"<rect x='0' y='{y}' width='{w}' height='30' fill='#e6eedd'/>" for y in range(14, h, 60))
    holes = "".join(f"<circle cx='18' cy='{y}' r='6' fill='#ddd5c4'/>" for y in range(20, h, 30))
    code = text(52, 74, "total = price * 2;", 34, "#2b2b2b", MONO, 500)
    toks = [("total", 52, 103), ("=", 172, 21), ("price", 213, 103), ("*", 334, 21), ("2", 375, 21), (";", 416, 21)]
    tok = ""
    for s, x, tw in toks:
        tok += marker_box(x - 6, 92, tw + 12, 44, "#d6342c", rng)
        tok += text(x + tw / 2, 125, s, 26, "#d6342c", MARKER, 700, "middle")
    nodes = {"=": (230, 215), "total": (120, 300), "*": (345, 300), "price": (275, 390), "2": (420, 390)}
    edges = [("=", "total"), ("=", "*"), ("*", "price"), ("*", "2")]
    tree = "".join(
        f"<path d='{wobble_line(*nodes[a], *nodes[b], rng, 6)}' stroke='#1d1d1d' stroke-width='4' fill='none' stroke-linecap='round'/>"
        for a, b in edges)
    for k, (x, y) in nodes.items():
        rx = 54 if len(k) > 1 else 30
        tree += f"<ellipse cx='{x}' cy='{y}' rx='{rx}' ry='30' fill='#fff7c9'/>"
        tree += marker_ring(x, y, rx, 30, "#1d1d1d", rng)
        tree += text(x, y + 10, k, 28, "#1d1d1d", MARKER, 700, "middle")
    arrow = ("<path d='M250,150 C262,170 246,178 236,183' stroke='#d6342c' stroke-width='5' fill='none' stroke-linecap='round'/>"
             "<path d='M226,172 L234,186 L250,178' stroke='#d6342c' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>")
    words = poster(492, 168, ["HOW IT", "READS"], 88, "#151515", "#f6f1e4", MARKER, 700, 0.95, sw=12)
    under = "<path d='M496,290 C590,278 690,286 760,274' stroke='#d6342c' stroke-width='9' fill='none' stroke-linecap='round'/>"
    words += text(498, 350, "your code", 50, "#d6342c", MARKER, 700)
    return page(w, h, svg(w, h, bands + holes + code + tok + arrow + tree + words + under), "#f6f1e4")


def yt_3(w, h):
    """Computerphile: a parse tree on graph paper, a sticky note saying Part 4."""
    rng = random.Random(3)
    grid = ""
    for i in range(0, max(w, h) + 1, 25):
        c, sw = ("#d2e2f3", 1.5) if i % 100 == 0 else ("#eaf1f9", 1)
        if i <= w:
            grid += f"<line x1='{i}' y1='0' x2='{i}' y2='{h}' stroke='{c}' stroke-width='{sw}'/>"
        if i <= h:
            grid += f"<line x1='0' y1='{i}' x2='{w}' y2='{i}' stroke='{c}' stroke-width='{sw}'/>"
    nodes = {"expr": (250, 70), "term": (150, 160), "+": (270, 165), "term2": (390, 160),
             "a": (80, 260), "×": (160, 265), "b": (240, 260), "c": (390, 260),
             "1": (120, 360), "2": (200, 360)}
    label = {"term2": "term", "1": "x", "2": "y"}
    edges = [("expr", "term"), ("expr", "+"), ("expr", "term2"), ("term", "a"), ("term", "×"),
             ("term", "b"), ("term2", "c"), ("b", "1"), ("b", "2")]
    tree = "".join(
        f"<path d='{wobble_line(*nodes[a], *nodes[b], rng, 5)}' stroke='#1f7a4a' stroke-width='4.5' fill='none' stroke-linecap='round'/>"
        for a, b in edges)
    for k, (x, y) in nodes.items():
        s = label.get(k, k)
        rx = 20 + 12 * len(s)
        fill = "#fff27a" if k in ("expr", "b") else "#ffffff"
        tree += f"<ellipse cx='{x}' cy='{y}' rx='{rx}' ry='28' fill='{fill}' opacity='.95'/>"
        tree += marker_ring(x, y, rx, 28, "#15452c", rng, 3.5)
        tree += text(x, y + 10, s, 28, "#15452c", MARKER, 700, "middle")
    note = ("<g transform='translate(560 225) rotate(6)'>"
            "<rect x='-150' y='-150' width='300' height='300' fill='#ffd84a' filter='url(#sh)'/>"
            "<rect x='-150' y='-150' width='300' height='42' fill='#f5c93a'/>"
            + text(0, 30, "PART", 78, "#1a1a1a", MARKER, 700, "middle")
            + text(0, 128, "4", 120, "#d02f2f", MARKER, 700, "middle")
            + "</g>")
    pen = ("<g transform='translate(460 410) rotate(-18)'>"
           "<rect x='0' y='-9' width='220' height='18' rx='9' fill='#1f7a4a'/>"
           "<rect x='170' y='-10' width='50' height='20' rx='6' fill='#155a35'/>"
           "<polygon points='0,-9 -22,0 0,9' fill='#e8d8b8'/></g>")
    return page(w, h, svg(w, h, grid + tree + pen + note, shadow("sh", 12, 12, .25)), "#fbfcfe")


CITY_INK = "#14213d"
CITY_SUN = "#ffc83d"


def city_bug(w):
    """Cityscope's corner mark, the same on all three of its thumbnails: a
    yellow tile holding a three-tower skyline (a made channel, not a logo)."""
    return (f"<g transform='translate({w - 80} 24)'><rect width='56' height='56' rx='14' fill='{CITY_SUN}'/>"
            f"<g fill='{CITY_INK}'><rect x='11' y='24' width='10' height='20'/><rect x='23' y='13' width='11' height='31'/>"
            "<rect x='36' y='29' width='9' height='15'/><rect x='9' y='43' width='38' height='4' rx='2'/></g></g>")


def city_label(x, y, s, size, width):
    """Cityscope's thumbnail words: navy condensed type on a leaning yellow slab."""
    top = y - size * 0.80
    return (f"<g transform='translate({x} {top}) skewX(-8)'>"
            f"<rect x='8' y='8' width='{width + 36}' height='{size * 0.98:.0f}' fill='{CITY_INK}'/>"
            f"<rect x='0' y='0' width='{width + 36}' height='{size * 0.98:.0f}' fill='{CITY_SUN}'/></g>"
            + text(x + 20, y + size * 0.06, s, size, CITY_INK, COND, 800))


def yt_1(w, h):
    """Cityscope: a calm street in one-point perspective — trees, a bike lane,
    cafe tables, and no cars."""
    vx, vy, f, eye = 540, 200, 250, 1.6

    def P(X, Y, Z):
        return (vx + X * f / Z, vy + (eye - Y) * f / Z)

    def quad(a, b, c, d, fill, extra=""):
        return f"<polygon points='{pts([a, b, c, d])}' fill='{fill}' {extra}/>"

    defs = lin("sky", [(0, "#a9d8ee"), (1, "#fdf0d6")]) + blur("b", 3)
    art = f"<rect width='{w}' height='{h}' fill='url(#sky)'/>"
    zn, zf = 1.0, 95
    # the far end of the street
    art += quad(P(-7, 0, zf), P(7, 0, zf), P(7, 16, zf), P(-7, 16, zf), "#d9c7b0")
    # ground: pavement · road · bike lane · kerb · pavement
    strips = [(-7, -4.6, "#e7dccb"), (-4.6, -4.4, "#cdbfa9"), (-4.4, 1.6, "#a7a199"),
              (1.6, 3.3, "#3fae7a"), (3.3, 3.6, "#f4efe6"), (3.6, 7, "#e7dccb")]
    for x0, x1, c in strips:
        art += quad(P(x0, 0, zn), P(x1, 0, zn), P(x1, 0, zf), P(x0, 0, zf), c)
    for z in range(3, 90, 4):  # the bike lane's dashed edge
        art += quad(P(1.62, 0, z), P(1.78, 0, z), P(1.78, 0, z + 1.8), P(1.62, 0, z + 1.8), "#ffffff")
    for z in (8, 26):  # a bike painted in the lane
        cx, cy = P(2.45, 0, z)
        s = 0.55 * f / z
        art += (f"<g transform='translate({cx:.1f} {cy:.1f}) scale({s:.2f} {s * 0.35:.2f})' stroke='#ffffff' stroke-width='{2.2 / s:.2f}' fill='none'>"
                "<circle cx='-0.55' cy='0' r='0.42'/><circle cx='0.55' cy='0' r='0.42'/>"
                "<path d='M-0.55,0 L-0.1,0 L0.25,-0.5 L-0.3,-0.5 L-0.1,0 M0.25,-0.5 L0.55,0'/></g>")
    # facades, left and right, building by building
    walls = {-7: ["#f0d3b3", "#e3a684", "#f3e6cf", "#c8d3bf", "#ecc497", "#d6dde1", "#f2d8bd", "#e6b493"],
             7: ["#d9b89a", "#c8cfc6", "#e8c8a0", "#c98f72", "#dde0d6", "#d8b48f", "#c4cdd2", "#e2c3a3"]}
    cuts = [1.2, 7, 13, 20, 28, 38, 52, 70, zf]
    tall = [15, 12, 17, 13, 16, 12.5, 15, 14]
    for X, cols in walls.items():
        side = -1 if X < 0 else 1
        for i in range(len(cuts) - 1):
            z0, z1, H = cuts[i], cuts[i + 1], tall[(i + (0 if side < 0 else 3)) % len(tall)]
            art += quad(P(X, 0, z0), P(X, 0, z1), P(X, H, z1), P(X, H, z0), cols[i])
            art += quad(P(X, H - 0.5, z0), P(X, H - 0.5, z1), P(X, H, z1), P(X, H, z0), "#00000018")
            # a shopfront and an awning on the ground floor
            art += quad(P(X, 0.2, z0 + 0.6), P(X, 0.2, z1 - 0.6), P(X, 2.6, z1 - 0.6), P(X, 2.6, z0 + 0.6), "#6d8794")
            aw = ["#e2553a", "#2f6f8f", "#3f8f5a", "#e8a33a"][i % 4]
            art += quad(P(X, 2.7, z0 + 0.4), P(X, 2.7, z1 - 0.4), P(X - side * 1.2, 2.3, z1 - 0.4), P(X - side * 1.2, 2.3, z0 + 0.4), aw)
            zz = z0 + 0.9
            while zz + 1.2 < z1 - 0.4:
                y0 = 3.6
                while y0 + 1.6 < H - 1.0:
                    art += quad(P(X, y0, zz), P(X, y0, zz + 1.2), P(X, y0 + 1.7, zz + 1.2), P(X, y0 + 1.7, zz), "#41515c")
                    y0 += 3.0
                zz += 2.3
    # things on the pavements, far to near: trees, cafe tables, two people
    things = []
    for z in range(6, 80, 7):
        things.append((z, "tree", -5.6))
        things.append((z + 3.5, "tree", 6.2))
    for z in (4.2, 6.6, 9.4, 12.6):
        things.append((z, "table", 4.9))
    things.append((16, "person", -6.0))
    things.append((21, "person", 4.4))
    things.sort(key=lambda t: -t[0])
    for z, kind, X in things:
        k = f / z
        if kind == "tree":
            bx, by = P(X, 0, z)
            cx, cy = P(X, 4.6, z)
            art += f"<path d='M{bx:.1f},{by:.1f} L{cx:.1f},{cy:.1f}' stroke='#6b4f3a' stroke-width='{0.28 * k:.1f}'/>"
            art += f"<circle cx='{cx - 0.4 * k:.1f}' cy='{cy - 0.3 * k:.1f}' r='{2.0 * k:.1f}' fill='#4f9a4f'/>"
            art += f"<circle cx='{cx + 0.6 * k:.1f}' cy='{cy - 0.9 * k:.1f}' r='{1.6 * k:.1f}' fill='#66b25c'/>"
            art += f"<circle cx='{cx - 0.9 * k:.1f}' cy='{cy - 1.2 * k:.1f}' r='{0.8 * k:.1f}' fill='#82c46f'/>"
        elif kind == "table":
            tx, ty = P(X, 0.75, z)
            gx, gy = P(X, 0, z)
            ux, uy = P(X, 2.5, z)
            art += f"<ellipse cx='{gx:.1f}' cy='{gy:.1f}' rx='{1.0 * k:.1f}' ry='{0.18 * k:.1f}' fill='#00000022'/>"
            art += f"<path d='M{gx:.1f},{gy:.1f} L{ux:.1f},{uy:.1f}' stroke='#3a3a3a' stroke-width='{0.06 * k:.1f}'/>"
            for dx in (-0.55, 0.55):  # two chairs
                cxx, cyy = P(X + dx * 0.6, 0.45, z + dx)
                art += f"<rect x='{cxx - 0.18 * k:.1f}' y='{cyy - 0.45 * k:.1f}' width='{0.36 * k:.1f}' height='{0.9 * k:.1f}' rx='{0.06 * k:.1f}' fill='#2f3b40'/>"
            art += f"<ellipse cx='{tx:.1f}' cy='{ty:.1f}' rx='{0.45 * k:.1f}' ry='{0.12 * k:.1f}' fill='#f7f3ea'/>"
            art += f"<path d='M{tx:.1f},{ty:.1f} L{gx:.1f},{gy:.1f}' stroke='#3a3a3a' stroke-width='{0.07 * k:.1f}'/>"
            art += (f"<path d='M{ux - 1.2 * k:.1f},{uy + 0.35 * k:.1f} Q{ux:.1f},{uy - 0.55 * k:.1f} {ux + 1.2 * k:.1f},{uy + 0.35 * k:.1f} Z' fill='#f2efe6'/>"
                    f"<path d='M{ux - 1.2 * k:.1f},{uy + 0.35 * k:.1f} L{ux + 1.2 * k:.1f},{uy + 0.35 * k:.1f}' stroke='#e2553a' stroke-width='{0.12 * k:.1f}'/>")
        else:
            px, py = P(X, 0, z)
            art += (f"<rect x='{px - 0.22 * k:.1f}' y='{py - 1.45 * k:.1f}' width='{0.44 * k:.1f}' height='{1.45 * k:.1f}' rx='{0.2 * k:.1f}' fill='#2f4858'/>"
                    f"<circle cx='{px:.1f}' cy='{py - 1.6 * k:.1f}' r='{0.17 * k:.1f}' fill='#2f4858'/>")
    art += city_label(36, 400, "CALM?", 116, 334) + city_bug(w)
    return page(w, h, svg(w, h, art, defs), "#fdf0d6")


def car(x, y, s, body, glass="#cfe3ee"):
    """A side-view hatchback, facing right; (x, y) is its rear wheel's ground point."""
    return (f"<g transform='translate({x} {y}) scale({s})'>"
            f"<path d='M-14,-14 L-14,-34 Q-12,-44 0,-46 L26,-48 L44,-70 Q48,-74 58,-74 L104,-74 Q114,-74 120,-66 L136,-46 L156,-42 Q166,-40 166,-28 L166,-14 Z' fill='{body}'/>"
            f"<path d='M52,-48 L62,-66 L84,-66 L84,-48 Z M90,-48 L90,-66 L110,-66 Q114,-66 118,-60 L126,-48 Z' fill='{glass}'/>"
            "<circle cx='14' cy='-12' r='16' fill='#1d1d1f'/><circle cx='14' cy='-12' r='7' fill='#9aa0a6'/>"
            "<circle cx='128' cy='-12' r='16' fill='#1d1d1f'/><circle cx='128' cy='-12' r='7' fill='#9aa0a6'/>"
            "<rect x='158' y='-36' width='8' height='6' rx='2' fill='#ffd36b'/></g>")


def yt_4(w, h):
    """Cityscope: before/after on one street — cars and asphalt on the left, a
    tram on a grass track on the right."""
    defs = lin("sky", [(0, "#bfe4f5"), (1, "#f4f1e6")])
    gy = 336
    # the shared street: sky and one row of buildings
    city = f"<rect width='{w}' height='{h}' fill='url(#sky)'/>"
    rows = [(0, 120, 140, "#e8c9a8"), (120, 110, 170, "#d7dfd6"), (230, 130, 120, "#efd9bd"), (360, 100, 160, "#d9a98a"),
            (460, 140, 135, "#e9dcc5"), (600, 110, 175, "#c9d6dc"), (710, 100, 145, "#ecc8a2")]
    for x, bw, bh, c in rows:
        top = gy - 36 - bh
        city += f"<rect x='{x}' y='{top}' width='{bw}' height='{bh + 36}' fill='{c}'/>"
        city += f"<rect x='{x}' y='{top}' width='{bw}' height='10' fill='#00000014'/>"
        for wx in range(x + 16, x + bw - 20, 30):
            for wy in range(top + 24, gy - 60, 36):
                city += f"<rect x='{wx}' y='{wy}' width='14' height='20' rx='2' fill='#5a6a74'/>"
    city += f"<rect x='0' y='{gy - 36}' width='{w}' height='36' fill='#e4dccd'/>"  # the pavement
    split = "M430,0 L370,450"
    left = (f"<rect x='0' y='{gy}' width='{w}' height='{h - gy}' fill='#6f6c69'/>"
            + "".join(f"<rect x='{x}' y='{gy + 52}' width='44' height='6' fill='#f2efe6'/>" for x in range(10, 470, 80))
            + car(30, gy + 40, 0.82, "#c9452f") + car(210, gy + 40, 0.82, "#3d5a80")
            + car(120, gy + 108, 0.95, "#e7b83a") + car(330, gy + 108, 0.95, "#8d99ae")
            + f"<rect x='0' y='0' width='{w}' height='{h}' fill='#6b6f78' opacity='.28'/>"
            + "<ellipse cx='20' cy='350' rx='30' ry='12' fill='#9a9a9a' opacity='.6'/>")
    tram_y = gy + 34
    right = (f"<rect x='0' y='{gy}' width='{w}' height='{h - gy}' fill='#e4dccd'/>"
             f"<rect x='0' y='{gy + 14}' width='{w}' height='{h - gy - 14}' fill='#6dbb5c'/>"
             + "".join(f"<path d='M{x},{gy + 30 + (x * 7) % 90} l4,-10 l4,10' stroke='#4f9a45' stroke-width='3' fill='none'/>" for x in range(380, 800, 23))
             + f"<rect x='0' y='{tram_y + 4}' width='{w}' height='6' fill='#8a8f94'/><rect x='0' y='{tram_y + 10}' width='{w}' height='4' fill='#5c6166'/>"
             # the overhead wire and its poles
             + f"<path d='M400,{tram_y - 176} L800,{tram_y - 176}' stroke='#3a3f45' stroke-width='3'/>"
             + "".join(f"<rect x='{x}' y='{tram_y - 192}' width='8' height='{192}' fill='#4a5058'/><rect x='{x - 10}' y='{tram_y - 182}' width='28' height='5' fill='#4a5058'/>" for x in (720,))
             # the tram
             + f"<g transform='translate(0 {tram_y})'>"
             "<path d='M528,-120 L548,-150 L596,-150 L616,-120' stroke='#2b2f36' stroke-width='5' fill='none'/>"
             "<path d='M572,-150 L560,-176 L590,-176' stroke='#2b2f36' stroke-width='4' fill='none'/>"
             "<path d='M470,-6 L470,-96 Q472,-122 506,-122 L830,-122 L830,-6 Z' fill='#f7f5ef'/>"
             "<path d='M470,-40 L830,-40 L830,-24 L470,-24 Z' fill='#e2553a'/>"
             "<path d='M472,-90 Q476,-112 506,-112 L530,-112 L530,-56 L472,-56 Z' fill='#27323d'/>"
             + "".join(f"<rect x='{x}' y='-108' width='46' height='50' rx='6' fill='#27323d'/>" for x in (548, 610, 712, 774))
             + "".join(f"<rect x='{x}' y='-110' width='40' height='104' rx='4' fill='#cfd6db'/><rect x='{x + 19}' y='-108' width='2' height='100' fill='#9aa3aa'/>" for x in (664,))
             + "".join(f"<circle cx='{x}' cy='-84' r='9' fill='{c}'/><path d='M{x - 15},-58 Q{x},-76 {x + 15},-58 Z' fill='{c}'/>" for x, c in ((571, '#f1c16b'), (633, '#5a3a26'), (735, '#2a2a2a'), (797, '#c98f60')))
             + "<rect x='466' y='-6' width='368' height='10' rx='4' fill='#3a3f45'/></g>"
             # trees and people along the new street
             + "".join(f"<rect x='{x - 4}' y='{gy - 70}' width='8' height='44' fill='#6b4f3a'/><circle cx='{x}' cy='{gy - 92}' r='34' fill='#4f9a4f'/><circle cx='{x + 14}' cy='{gy - 104}' r='22' fill='#66b25c'/>" for x in (420,))
             + "".join(f"<rect x='{x - 7}' y='{gy - 76}' width='14' height='42' rx='7' fill='{c}'/><circle cx='{x}' cy='{gy - 84}' r='8' fill='{c}'/>" for x, c in ((442, "#2f4858"), (456, "#c9452f"))))
    defs += f"<clipPath id='L'><path d='M0,0 L430,0 L370,450 L0,450 Z'/></clipPath><clipPath id='R'><path d='M430,0 L{w},0 L{w},{h} L370,450 Z'/></clipPath>"
    art = city + f"<g clip-path='url(#L)'>{left}</g><g clip-path='url(#R)'>{right}</g>"
    art += f"<path d='{split}' stroke='#ffffff' stroke-width='8'/>"
    art += ("<g transform='translate(400 244)'><circle r='30' fill='#ffffff'/>"
            f"<path d='M-14,0 L12,0 M2,-11 L14,0 L2,11' stroke='{CITY_INK}' stroke-width='6' fill='none' stroke-linecap='round' stroke-linejoin='round'/></g>")
    art += city_label(34, 104, "ONE LINE", 90, 346) + city_bug(w)
    return page(w, h, svg(w, h, art, defs), "#f4f1e6")


def cyclist(x, gy, s, shirt, bike, helmet=None, skin="#6b4a36", cargo=False):
    """A side-view rider facing right; (x, gy) is the rear wheel's ground point,
    `s` pixels per metre."""
    def p(a, b):
        return f"{x + a * s:.1f},{gy - b * s:.1f}"
    sw = 0.05 * s
    out = f"<g stroke-linecap='round' stroke-linejoin='round'>"
    fx = 1.35 if cargo else 1.05
    for cx in (0, fx):
        out += f"<circle cx='{x + cx * s:.1f}' cy='{gy - 0.34 * s:.1f}' r='{0.31 * s:.1f}' fill='none' stroke='#22252a' stroke-width='{0.06 * s:.1f}'/>"
    if cargo:
        out += f"<path d='M{p(0.62, 0.42)} L{p(1.28, 0.42)} L{p(1.32, 0.86)} L{p(0.62, 0.86)} Z' fill='#e8a33a'/>"
        out += f"<circle cx='{x + 0.92 * s:.1f}' cy='{gy - 0.98 * s:.1f}' r='{0.12 * s:.1f}' fill='{skin}'/>"
    hx = fx - 0.13
    out += (f"<path d='M{p(0, 0.34)} L{p(0.45, 0.30)} L{p(0.35, 0.92)} Z M{p(0.35, 0.92)} L{p(hx, 0.95)} L{p(0.45, 0.30)} "
            f"M{p(hx, 0.95)} L{p(fx, 0.34)} M{p(hx, 0.95)} L{p(hx - 0.04, 1.06)}' fill='none' stroke='{bike}' stroke-width='{sw:.1f}'/>")
    out += f"<path d='M{p(0.28, 0.95)} L{p(0.44, 0.95)}' stroke='#22252a' stroke-width='{0.06 * s:.1f}'/>"
    out += (f"<path d='M{p(0.36, 0.98)} L{p(0.6, 0.66)} L{p(0.52, 0.2)} M{p(0.36, 0.98)} L{p(0.5, 0.7)} L{p(0.40, 0.42)}' "
            f"fill='none' stroke='#2b3a4a' stroke-width='{0.12 * s:.1f}'/>")
    out += f"<path d='M{p(0.36, 1.0)} L{p(0.58, 1.48)}' stroke='{shirt}' stroke-width='{0.24 * s:.1f}'/>"
    out += f"<path d='M{p(0.58, 1.44)} L{p(hx - 0.04, 1.06)}' stroke='{shirt}' stroke-width='{0.08 * s:.1f}'/>"
    out += f"<circle cx='{x + 0.66 * s:.1f}' cy='{gy - 1.68 * s:.1f}' r='{0.12 * s:.1f}' fill='{skin}'/>"
    if helmet:
        out += (f"<path d='M{p(0.53, 1.70)} A{0.14 * s:.1f},{0.14 * s:.1f} 0 0 1 {p(0.80, 1.70)} Z' fill='{helmet}' stroke='none'/>")
    return out + "</g>"


def yt_6(w, h):
    """Cityscope: a protected bike lane, busy, a kerb between it and the road,
    and a plan of the junction pinned in a card."""
    defs = shadow("sh", 10, 14, .25, "#1b2a33") + lin("park", [(0, "#a8d39a"), (1, "#7fbf73")])
    art = f"<rect width='{w}' height='{h}' fill='url(#park)'/>"
    rng = random.Random(6)
    for i in range(14):  # a row of park trees behind the road
        x = i * 62 + rng.uniform(-10, 10)
        r = rng.uniform(34, 50)
        art += f"<circle cx='{x:.0f}' cy='{150 - r * 0.4:.0f}' r='{r:.0f}' fill='{rng.choice(['#4f9a4f', '#5daa55', '#468a46'])}'/>"
    art += f"<rect x='0' y='150' width='{w}' height='80' fill='#7a7772'/>"  # the road
    art += "".join(f"<rect x='{x}' y='186' width='46' height='6' fill='#f2efe6'/>" for x in range(0, w, 90))
    art += car(560, 222, 0.62, "#3d5a80") + car(110, 222, 0.62, "#c9452f")
    art += f"<rect x='0' y='230' width='{w}' height='14' fill='#d9d4c8'/><rect x='0' y='244' width='{w}' height='8' fill='#a9a397'/>"  # the kerb
    art += f"<rect x='0' y='252' width='{w}' height='132' fill='#3fae7a'/>"  # the lane
    art += "".join(f"<rect x='{x}' y='314' width='34' height='5' fill='#ffffff88'/>" for x in range(0, w, 70))
    art += f"<rect x='0' y='384' width='{w}' height='10' fill='#f4efe6'/><rect x='0' y='394' width='{w}' height='{h - 394}' fill='#e4dccd'/>"
    riders = [
        (0, 306, 60, "#e2553a", "#2f3b40", "#2f6f8f", False),
        (150, 306, 60, "#6a4c93", "#3f8f5a", None, False),
        (410, 306, 60, "#2f6f8f", "#c9452f", None, False),
        (40, 374, 74, "#f2efe6", "#2f3b40", "#e8a33a", False),
        (196, 374, 74, "#c9452f", "#2f6f8f", "#2f3b40", True),
        (400, 374, 74, "#2f4858", "#e8a33a", "#f2efe6", False),
        (560, 374, 74, "#e8a33a", "#3d5a80", None, False),
        (280, 306, 60, "#f2efe6", "#2f3b40", "#3f8f5a", False),
        (560, 306, 60, "#3f8f5a", "#e2553a", None, False),
        (690, 306, 60, "#2f6f8f", "#e2553a", "#e8a33a", False),
        (700, 374, 74, "#6a4c93", "#2f3b40", None, False),
    ]
    skins = ["#6b4a36", "#e0b48f", "#a8714f", "#f0c9a5", "#5a3c2a"]
    for i, (x, gy, s, shirt, bike, helmet, cargo) in enumerate(sorted(riders, key=lambda r: r[1])):
        art += cyclist(x, gy, s, shirt, bike, helmet, skins[i % len(skins)], cargo)
    # the inset: the junction in plan
    ix, iy, iw, ih = 470, 26, 200, 146
    card = f"<g filter='url(#sh)'><rect x='{ix}' y='{iy}' width='{iw}' height='{ih}' rx='16' fill='#f7f4ec'/></g>"
    defs += f"<clipPath id='ins'><rect x='{ix}' y='{iy}' width='{iw}' height='{ih}' rx='16'/></clipPath>"
    cx, cy = ix + iw / 2, iy + ih / 2
    plan = f"<rect x='{ix}' y='{iy}' width='{iw}' height='{ih}' fill='#b7d9a8'/>"
    plan += f"<rect x='{ix}' y='{cy - 30}' width='{iw}' height='60' fill='#8d8a84'/><rect x='{cx - 30}' y='{iy}' width='60' height='{ih}' fill='#8d8a84'/>"
    lane = "#3fae7a"
    for sx in (-1, 1):
        for sy in (-1, 1):
            # each corner: a green lane bending round a kerbed island
            ax, ay = cx + sx * 40, cy + sy * 40
            plan += (f"<path d='M{ix if sx < 0 else ix + iw},{ay} L{cx + sx * 52},{ay} "
                     f"M{ax},{iy if sy < 0 else iy + ih} L{ax},{cy + sy * 52}' stroke='{lane}' stroke-width='9'/>")
            plan += f"<path d='M{cx + sx * 52},{ay} Q{ax},{ay} {ax},{cy + sy * 52}' stroke='{lane}' stroke-width='9' fill='none'/>"
            plan += f"<circle cx='{cx + sx * 32}' cy='{cy + sy * 32}' r='7' fill='#f2efe6'/>"
    for k in range(5):  # zebra crossings
        o = -16 + k * 8
        plan += (f"<rect x='{cx + o}' y='{cy - 38}' width='4' height='10' fill='#ffffff'/><rect x='{cx + o}' y='{cy + 28}' width='4' height='10' fill='#ffffff'/>"
                 f"<rect x='{cx - 38}' y='{cy + o}' width='10' height='4' fill='#ffffff'/><rect x='{cx + 28}' y='{cy + o}' width='10' height='4' fill='#ffffff'/>")
    art += card + f"<g clip-path='url(#ins)'>{plan}</g>"
    art += f"<rect x='{ix}' y='{iy}' width='{iw}' height='{ih}' rx='16' fill='none' stroke='#ffffff' stroke-width='6'/>"
    art += city_label(34, 100, "IT WORKS", 90, 376) + city_bug(w)
    return page(w, h, svg(w, h, art, defs), "#a8d39a")


def yt_2(w, h):
    """Strange Loop: the slide seen from the seats — a lit screen in a dark hall."""
    defs = (rad("hall", [(0, "#1b2233"), (1, "#05070b")], 0.5, 0.35, 0.8)
            + lin("beam", [(0, "#ffffff22"), (1, "#ffffff00")])
            + blur("b", 18))
    bg = f"<rect width='{w}' height='{h}' fill='url(#hall)'/>"
    beam = "<polygon points='400,470 150,40 650,40' fill='url(#beam)' opacity='.5'/>"
    scr = [(130, 30), (670, 30), (660, 330), (140, 330)]
    halo = f"<polygon points='{pts(scr)}' fill='#dfe8ff' opacity='.35' filter='url(#b)'/>"
    screen = f"<polygon points='{pts(scr)}' fill='#fbfbf8'/>"
    slide = text(170, 108, "Scale", 70, "#101828", HEAVY, 800) + text(170, 180, "down.", 70, "#e0542e", HEAVY, 800)
    box = ""
    for (x, y) in ((420, 78), (540, 78), (480, 170)):
        box += f"<rect x='{x}' y='{y}' width='70' height='48' rx='8' fill='none' stroke='#101828' stroke-width='5'/>"
    box += ("<path d='M490,102 L536,102 M455,126 L495,166 M575,126 L535,166' stroke='#101828' stroke-width='4'/>"
            "<g transform='translate(492 250)'><rect x='0' y='0' width='44' height='56' rx='6' fill='#e0542e'/>"
            "<rect x='8' y='10' width='28' height='5' rx='2.5' fill='#fff'/><rect x='8' y='22' width='28' height='5' rx='2.5' fill='#fff'/>"
            "<circle cx='22' cy='42' r='4' fill='#fff'/></g>"
            "<path d='M515,218 L515,246' stroke='#101828' stroke-width='4' stroke-dasharray='6 6'/>")
    slide += box + text(170, 300, "27", 18, "#9aa3b2", SANS, 600)
    podium = ("<ellipse cx='80' cy='372' rx='70' ry='40' fill='#8fa6ff' opacity='.12' filter='url(#b)'/>"
              "<circle cx='92' cy='318' r='13' fill='#1a2030'/><rect x='76' y='330' width='32' height='60' rx='12' fill='#1a2030'/>"
              "<path d='M40,352 L96,352 L90,420 L46,420 Z' fill='#222a3c'/><rect x='36' y='346' width='64' height='10' rx='3' fill='#2a3348'/>")
    heads = ""
    for row, (y, r, n) in enumerate(((432, 30, 9), (462, 38, 7))):
        for i in range(n):
            x = (i + 0.5 + (row % 2) * 0.3) * w / n
            heads += f"<circle cx='{x:.0f}' cy='{y}' r='{r}' fill='#030407'/><rect x='{x - r * 1.5:.0f}' y='{y + r * 0.6:.0f}' width='{r * 3}' height='60' rx='{r}' fill='#030407'/>"
    return page(w, h, svg(w, h, bg + beam + halo + screen + slide + podium + heads, defs), "#05070b")


def yt_5(w, h):
    """Strange Loop: a full-bleed light slide — a stock, two flows, two loops."""
    navy, acc = "#1b2a4a", "#ef7d32"
    bg = f"<rect width='{w}' height='{h}' fill='#f4efe6'/>"
    words = text(48, 110, "IT'S", 64, navy, HEAVY, 800) + text(48, 196, "LOOPS.", 96, acc, HEAVY, 800)
    words += text(50, 244, "systems thinking", 26, "#6b7385", HEAVY, 500)
    stock = ("<rect x='470' y='190' width='160' height='110' rx='14' fill='#fff' stroke='#1b2a4a' stroke-width='6'/>"
             "<rect x='476' y='240' width='148' height='54' rx='8' fill='#f7c9a6'/>")
    flows = ("<path d='M360,245 L466,245' stroke='#1b2a4a' stroke-width='14'/>"
             "<path d='M634,245 L740,245' stroke='#1b2a4a' stroke-width='14'/>"
             "<polygon points='440,228 470,245 440,262' fill='#1b2a4a'/>"
             "<polygon points='722,228 752,245 722,262' fill='#1b2a4a'/>"
             "<path d='M396,228 L420,262 M420,228 L396,262' stroke='#1b2a4a' stroke-width='6'/>"
             "<circle cx='408' cy='245' r='3' fill='#1b2a4a'/>"
             "<path d='M670,228 L694,262 M694,228 L670,262' stroke='#1b2a4a' stroke-width='6'/>")
    cloud = lambda x, y: (f"<g fill='#d8d2c6'><circle cx='{x}' cy='{y}' r='22'/><circle cx='{x + 22}' cy='{y - 8}' r='18'/>"  # noqa: E731
                          f"<circle cx='{x - 20}' cy='{y + 4}' r='16'/></g>")
    loops = (f"<path d='M420,215 C420,120 560,110 560,185' stroke='{acc}' stroke-width='6' fill='none'/>"
             f"<polygon points='548,176 560,196 572,176' fill='{acc}'/>"
             f"<path d='M600,305 C620,400 700,390 700,275' stroke='{acc}' stroke-width='6' fill='none' stroke-dasharray='14 10'/>"
             f"<polygon points='688,284 700,262 712,284' fill='{acc}'/>"
             f"<g transform='translate(490 128)'><circle r='24' fill='{acc}'/>" + text(0, 9, "R", 26, "#fff", HEAVY, 800, "middle") + "</g>"
             f"<g transform='translate(650 372)'><circle r='24' fill='{navy}'/>" + text(0, 9, "B", 26, "#fff", HEAVY, 800, "middle") + "</g>")
    foot = text(752, 426, "14", 20, "#a59e92", SANS, 600, "end") + f"<rect x='48' y='410' width='60' height='8' rx='4' fill='{acc}'/>"
    return page(w, h, svg(w, h, bg + words + cloud(330, 245) + cloud(770, 245) + flows + stock + loops + foot), "#f4efe6")


def yt_7(w, h):
    """Strange Loop: a dark slide with a type lattice in neon strokes."""
    defs = rad("bg", [(0, "#1c1f45"), (1, "#0a0b1c")], 0.7, 0.5, 0.8) + blur("g", 6)
    bg = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    venn = ("<circle cx='560' cy='200' r='150' fill='#6a5cff14'/>"
            "<circle cx='660' cy='200' r='150' fill='#ff4fa314'/>")
    top, bot = (590, 44), (590, 356)
    mid = [("Int", 426, "#39e0c8"), ("String", 536, "#ff5fa8"), ("Bool", 646, "#c6f23c"), ("[T]", 740, "#ffb43c")]
    lines = ""
    for s, x, c in mid:
        lines += f"<path d='M{top[0]},{top[1]} L{x},200 L{bot[0]},{bot[1]}' stroke='{c}' stroke-width='3' fill='none' opacity='.75'/>"
    nodes = ""
    for s, x, c in mid:
        tw = 26 + 17 * len(s)
        nodes += (f"<rect x='{x - tw / 2}' y='178' width='{tw}' height='44' rx='22' fill='{c}' opacity='.5' filter='url(#g)'/>"
                  f"<rect x='{x - tw / 2}' y='178' width='{tw}' height='44' rx='22' fill='#0f1130' stroke='{c}' stroke-width='3'/>"
                  + text(x, 208, s, 24, c, MONO, 700, "middle"))
    for (x, y), s in ((top, "Any"), (bot, "Never")):
        tw = 30 + 17 * len(s)
        nodes += (f"<rect x='{x - tw / 2}' y='{y - 24}' width='{tw}' height='48' rx='24' fill='#ffffff'/>"
                  + text(x, y + 9, s, 26, "#0f1130", MONO, 700, "middle"))
    words = (text(44, 318, "TYPES,", 84, "#ffffff", HEAVY, 800)
             + text(44, 400, "TOURED", 84, "#39e0c8", HEAVY, 800)
             + "<rect x='46' y='418' width='120' height='8' rx='4' fill='#ff5fa8'/>"
             + text(52, 96, "λ", 64, "#ffffff40", SERIF, 400))
    return page(w, h, svg(w, h, bg + venn + lines + nodes + words, defs), "#0a0b1c")


# ── Substack headers (800×420, no words) ──────────────────────────────────

def substack_0(w, h):
    """Small software: one small bright square in a quiet Bauhaus field."""
    defs = shadow("sh", 18, 16, .22, "#5a3a20")
    art = (f"<rect width='{w}' height='{h}' fill='#efe8dc'/>"
           "<circle cx='170' cy='420' r='260' fill='#e2d6c2'/>"
           "<rect x='520' y='-40' width='330' height='300' fill='#c9d2d4'/>"
           "<circle cx='690' cy='330' r='54' fill='#1f3440'/>"
           "<rect x='80' y='60' width='14' height='14' fill='#1f3440'/>"
           "<rect x='354' y='166' width='92' height='92' fill='#e2553a' filter='url(#sh)'/>"
           "<rect x='354' y='166' width='92' height='20' fill='#f07352'/>")
    return page(w, h, svg(w, h, art, defs))


def substack_1(w, h):
    """A good changelog: torn paper strips stacked like a list, one stamped."""
    rng = random.Random(11)
    defs = shadow("sh", 6, 6, .25, "#10302c")
    art = f"<rect width='{w}' height='{h}' fill='#1f4b47'/>"
    cols = ["#f4ecd8", "#f2c14e", "#f4ecd8", "#ef8a6b", "#f4ecd8"]
    ys = [46, 118, 190, 262, 334]
    for i, (y, c) in enumerate(zip(ys, cols)):
        x = 150 + rng.uniform(-20, 20)
        ww = 420 + rng.uniform(-60, 80)
        art += f"<g transform='rotate({rng.uniform(-2.5, 2.5):.1f} 400 {y + 25})' filter='url(#sh)'>"
        art += f"<polygon points='{torn(x, y, ww, 50, rng)}' fill='{c}'/>"
        art += f"<circle cx='{x + 34}' cy='{y + 25}' r='11' fill='#1f4b47'/>"
        for k in range(3):
            bw = rng.uniform(50, 120)
            bx = x + 64 + k * 130
            if bx + bw < x + ww - 20:
                art += f"<rect x='{bx:.0f}' y='{y + 20}' width='{bw:.0f}' height='10' rx='5' fill='#1f4b4733'/>"
        art += "</g>"
    art += ("<g transform='translate(640 150) rotate(-14)' opacity='.92'>"
            "<circle r='74' fill='none' stroke='#e2553a' stroke-width='8'/>"
            "<circle r='58' fill='none' stroke='#e2553a' stroke-width='3'/>"
            "<path d='M-28,2 L-6,24 L32,-22' stroke='#e2553a' stroke-width='12' fill='none' stroke-linecap='round' stroke-linejoin='round'/></g>")
    return page(w, h, svg(w, h, art, defs))


def substack_2(w, h):
    """Interface latency: one ink line — a cursor, its ripples, a delayed pulse."""
    ink = "#1d2a44"
    art = f"<rect width='{w}' height='{h}' fill='#f5f0e6'/>"
    ps = []
    for x in range(40, 761, 4):
        t = (x - 470) / 26
        y = 300 - 120 * math.exp(-t * t) * math.cos(t * 1.6)
        ps.append((x, y))
    art += f"<polyline points='{pts(ps)}' fill='none' stroke='{ink}' stroke-width='3.5' stroke-linejoin='round'/>"
    art += "<circle cx='220' cy='300' r='9' fill='#e2553a'/>"
    art += f"<path d='M220,300 L220,120' stroke='{ink}' stroke-width='2' stroke-dasharray='3 9' stroke-linecap='round'/>"
    art += f"<path d='M470,300 L470,178' stroke='{ink}' stroke-width='2' stroke-dasharray='3 9' stroke-linecap='round'/>"
    art += f"<path d='M232,112 L458,112' stroke='{ink}' stroke-width='2.5'/><path d='M446,104 L458,112 L446,120' stroke='{ink}' stroke-width='2.5' fill='none'/>"
    cur = "<g transform='translate(196 118) scale(1.5)'><path d='M0,0 L0,34 L9,26 L15,40 L21,37 L15,24 L27,24 Z' fill='#f5f0e6' stroke='#1d2a44' stroke-width='2.2' stroke-linejoin='round'/></g>"
    for i, r in enumerate((18, 34, 52)):
        art += f"<circle cx='196' cy='118' r='{r}' fill='none' stroke='{ink}' stroke-width='{2.5 - i * 0.6}' opacity='{0.8 - i * 0.22}'/>"
    art += cur
    return page(w, h, svg(w, h, art))


def substack_3(w, h):
    """Latency is a feature: a mesh of colour, one sphere moving deliberately."""
    defs = (blur("b", 60) + rad("sp", [(0, "#ffffff"), (0.35, "#ffd6b8"), (1, "#e2553a")], 0.35, 0.3, 0.75))
    art = (f"<rect width='{w}' height='{h}' fill='#221a4a'/>"
           "<g filter='url(#b)'>"
           "<circle cx='150' cy='110' r='170' fill='#6b4cff'/>"
           "<circle cx='640' cy='80' r='160' fill='#ff8a6b'/>"
           "<circle cx='520' cy='380' r='190' fill='#3fb6ff'/>"
           "<circle cx='250' cy='420' r='130' fill='#ff4fa3'/></g>")
    for i in range(6):
        x = 250 + i * 46
        art += f"<circle cx='{x}' cy='{250 - i * 10}' r='{44 + i * 2}' fill='#ffffff' opacity='{0.05 + i * 0.03:.2f}'/>"
    art += "<circle cx='540' cy='190' r='62' fill='url(#sp)'/>"
    art += "<ellipse cx='540' cy='300' rx='70' ry='12' fill='#0d0a24' opacity='.35'/>"
    return page(w, h, svg(w, h, art, defs))


def substack_4(w, h):
    """Writing for skimmers: a risograph page, blue text bars, pink highlights."""
    css = "svg .ov{mix-blend-mode:multiply}"
    blue, pink = "#2b7bc0", "#ff5aa5"
    art = f"<rect width='{w}' height='{h}' fill='#f6f1e7'/>"
    art += "<rect x='230' y='24' width='340' height='396' fill='#fffdf8'/>"
    y = 64
    rng = random.Random(4)
    paras = [(4, 1), (3, 0), (5, 1), (3, 1), (2, 0)]
    for n, hl in paras:
        for k in range(n):
            ww = 280 if k < n - 1 else rng.uniform(120, 220)
            art += f"<rect x='260' y='{y}' width='{ww:.0f}' height='9' rx='4.5' fill='{blue}' opacity='{0.95 if k == 0 else 0.45}'/>"
            if k == 0 and hl:
                art += f"<rect class='ov' x='252' y='{y - 8}' width='{rng.uniform(110, 170):.0f}' height='25' rx='3' fill='{pink}' opacity='.85'/>"
            y += 20
        y += 16
    art += (f"<path class='ov' d='M210,60 L150,60 L150,150 L120,150 L120,260 L160,260 L160,370' stroke='{pink}' stroke-width='16' fill='none' stroke-linejoin='round' stroke-linecap='round' opacity='.9'/>"
            f"<polygon class='ov' points='142,362 160,394 178,362' fill='{pink}'/>"
            f"<circle class='ov' cx='660' cy='130' r='70' fill='{pink}' opacity='.8'/>"
            f"<circle class='ov' cx='700' cy='170' r='60' fill='{blue}' opacity='.75'/>"
            f"<rect class='ov' x='600' y='290' width='140' height='20' rx='10' fill='{blue}' opacity='.6'/>"
            f"<rect class='ov' x='630' y='326' width='90' height='20' rx='10' fill='{pink}' opacity='.8'/>")
    return page(w, h, svg(w, h, art), css=css)


def substack_5(w, h):
    """The end of the settings screen: toggles lifting off an emptied panel."""
    defs = lin("sky", [(0, "#c9c2f0"), (0.6, "#f4cdd6"), (1, "#ffe0c4")]) + shadow("sh", 8, 10, .18, "#503060")
    art = f"<rect width='{w}' height='{h}' fill='url(#sky)'/>"
    art += "<g filter='url(#sh)'><rect x='270' y='238' width='260' height='200' rx='26' fill='#ffffffcc'/></g>"
    for i in range(4):
        y = 268 + i * 40
        art += f"<rect x='296' y='{y}' width='120' height='10' rx='5' fill='#b8aed633'/>"
        if i in (0, 2):
            art += f"<rect x='446' y='{y - 8}' width='56' height='28' rx='14' fill='none' stroke='#b8aed688' stroke-width='2' stroke-dasharray='4 5'/>"
        else:
            art += f"<rect x='446' y='{y - 8}' width='56' height='28' rx='14' fill='#34c07a'/><circle cx='488' cy='{y + 6}' r='11' fill='#fff'/>"
    flying = [(470, 200, 0.95, -18, 1, "#34c07a"), (330, 170, 0.8, 22, 0, "#ffffff"), (560, 110, 0.65, -30, 1, "#8c7cf0"),
              (250, 90, 0.55, 15, 1, "#ff8a6b"), (420, 60, 0.45, 40, 0, "#ffffff"), (640, 40, 0.35, -12, 1, "#34c07a"),
              (160, 170, 0.4, -25, 0, "#ffffff")]
    for x, y, s, r, on, c in flying:
        op = 0.35 + s * 0.65
        knob = 42 if on else 14
        fill = c if on else "#e7e2f2"
        art += (f"<g transform='translate({x} {y}) rotate({r}) scale({s * 1.6:.2f})' opacity='{op:.2f}' filter='url(#sh)'>"
                f"<rect x='0' y='0' width='56' height='28' rx='14' fill='{fill}'/><circle cx='{knob}' cy='14' r='11' fill='#fff'/></g>")
    for x, y, r in ((380, 24, 4), (520, 20, 3), (300, 40, 3), (700, 90, 4), (90, 120, 3)):
        art += f"<circle cx='{x}' cy='{y}' r='{r}' fill='#ffffff' opacity='.7'/>"
    return page(w, h, svg(w, h, art, defs))


# ── News lead images (800×450, no words) ──────────────────────────────────

def rss_0(w, h):
    """Quieter notifications: a brass bell under a glass cloche."""
    defs = (rad("bg", [(0, "#5b2e5e"), (1, "#1b0c22")], 0.5, 0.55, 0.75)
            + lin("brass", [(0, "#8a5a1c"), (0.3, "#f7d27a"), (0.55, "#d9a441"), (1, "#6b4212")], 1, 0)
            + lin("dome", [(0, "#ffffff30"), (0.5, "#ffffff0a"), (1, "#ffffff22")], 1, 0)
            + blur("b", 30))
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += "<ellipse cx='400' cy='250' rx='190' ry='150' fill='#ffb65c' opacity='.18' filter='url(#b)'/>"
    art += "<ellipse cx='400' cy='390' rx='210' ry='22' fill='#0a0410' opacity='.6'/>"
    art += "<rect x='200' y='372' width='400' height='20' rx='10' fill='#3a1f3e'/>"
    art += ("<path d='M330,330 Q330,210 400,196 Q470,210 470,330 L488,352 L312,352 Z' fill='url(#brass)'/>"
            "<circle cx='400' cy='190' r='12' fill='url(#brass)'/>"
            "<ellipse cx='400' cy='360' rx='20' ry='12' fill='#b8862f'/>"
            "<path d='M352,300 Q356,236 392,214' stroke='#fff3c8' stroke-width='6' fill='none' opacity='.55' stroke-linecap='round'/>")
    art += ("<path d='M240,372 L240,200 Q240,70 400,70 Q560,70 560,200 L560,372' fill='url(#dome)' stroke='#ffffff55' stroke-width='3'/>"
            "<circle cx='400' cy='58' r='16' fill='#ffffff44'/>"
            "<path d='M270,300 L270,200 Q272,110 360,92' stroke='#ffffffaa' stroke-width='6' fill='none' stroke-linecap='round'/>"
            "<path d='M530,250 L530,210' stroke='#ffffff55' stroke-width='5' stroke-linecap='round'/>")
    for x, y, r, o in ((640, 140, 9, .5), (690, 100, 6, .35), (720, 160, 4, .25), (140, 180, 7, .35), (110, 130, 4, .2)):
        art += f"<circle cx='{x}' cy='{y}' r='{r}' fill='#ff6b8a' opacity='{o}'/>"
    return page(w, h, svg(w, h, art, defs))


def rss_1(w, h):
    """A weather station on an old e-reader: the reader propped on a sill, its
    grey screen drawing the forecast, wired to a sensor; rain on the window."""
    defs = (lin("wall", [(0, "#d7e1e4"), (1, "#c3d0d4")]) + lin("sky", [(0, "#8fa7b8"), (1, "#c4d2d9")])
            + lin("sill", [(0, "#d9a46c"), (1, "#b47d48")]) + shadow("sh", 12, 12, .28, "#2a3438"))
    art = f"<rect width='{w}' height='{h}' fill='url(#wall)'/>"
    # the window, rain on it, a small anemometer outside
    art += "<rect x='470' y='30' width='290' height='300' rx='6' fill='#f4f1ea'/>"
    art += "<rect x='486' y='46' width='258' height='268' fill='url(#sky)'/>"
    art += "<g fill='#e9eef1' opacity='.9'><circle cx='560' cy='120' r='40'/><circle cx='606' cy='104' r='48'/><circle cx='652' cy='126' r='34'/><rect x='520' y='118' width='166' height='40' rx='20'/></g>"
    rng = random.Random(21)
    for _ in range(26):
        x, y = rng.uniform(492, 738), rng.uniform(52, 300)
        art += f"<path d='M{x:.0f},{y:.0f} l-3,{rng.uniform(10, 22):.0f}' stroke='#ffffff' stroke-width='2.5' stroke-linecap='round' opacity='.7'/>"
    art += ("<g transform='translate(690 210)' stroke='#2f3b40' stroke-width='4' fill='none' stroke-linecap='round'>"
            "<path d='M0,0 L0,104'/><path d='M0,0 L-30,-8 M0,0 L26,-16 M0,0 L6,24'/></g>"
            "<g fill='#2f3b40'><circle cx='660' cy='202' r='9'/><circle cx='716' cy='194' r='9'/><circle cx='696' cy='234' r='9'/><circle cx='690' cy='210' r='5'/></g>")
    art += "<rect x='614' y='46' width='10' height='268' fill='#f4f1ea'/><rect x='486' y='176' width='258' height='10' fill='#f4f1ea'/>"
    # the sill
    art += f"<rect x='0' y='330' width='{w}' height='120' fill='url(#sill)'/><rect x='0' y='330' width='{w}' height='10' fill='#e8bd8a'/>"
    # the sensor on its little board, and the cable
    art += ("<path d='M350,356 C420,400 470,404 520,372' stroke='#2b2b2b' stroke-width='6' fill='none' stroke-linecap='round'/>"
            "<g filter='url(#sh)'><rect x='500' y='344' width='120' height='34' rx='4' fill='#2f8a5a'/></g>"
            "<rect x='516' y='352' width='24' height='18' rx='2' fill='#1d1d1f'/>"
            + "".join(f"<circle cx='{x}' cy='372' r='2.5' fill='#e3c06b'/>" for x in range(552, 612, 9))
            + "<rect x='556' y='310' width='40' height='40' rx='6' fill='#f4f4f2'/>"
            + "".join(f"<rect x='562' y='{316 + k * 8}' width='28' height='3' rx='1.5' fill='#c9ccce'/>" for k in range(4)))
    # the e-reader on its stand
    art += "<path d='M180,350 L250,300 L260,306 L196,356 Z' fill='#7a5a3c'/>"
    art += ("<g filter='url(#sh)' transform='rotate(-4 260 210)'>"
            "<rect x='150' y='56' width='230' height='300' rx='18' fill='#4a4a4c'/>"
            "<rect x='170' y='76' width='190' height='244' rx='4' fill='#e3e1d8'/>"
            "<rect x='240' y='330' width='50' height='10' rx='5' fill='#3a3a3c'/>")
    # the screen: a sun behind a cloud, a temperature line, a week of icons
    ink = "#3b3b3b"
    art += (f"<circle cx='238' cy='134' r='26' fill='none' stroke='{ink}' stroke-width='5'/>"
            + "".join(f"<path d='M{238 + 36 * math.cos(a):.1f},{134 + 36 * math.sin(a):.1f} L{238 + 46 * math.cos(a):.1f},{134 + 46 * math.sin(a):.1f}' stroke='{ink}' stroke-width='5' stroke-linecap='round'/>"
                      for a in [i * math.pi / 4 for i in range(8)])
            + f"<g fill='#e3e1d8' stroke='{ink}' stroke-width='5'><path d='M240,176 a20,20 0 0 1 14,-34 a26,26 0 0 1 50,6 a18,18 0 0 1 4,28 Z'/></g>")
    temps = [16, 18, 21, 23, 22, 19, 17]
    ps = [(186 + i * 26, 250 - (t - 14) * 5) for i, t in enumerate(temps)]
    art += f"<path d='M186,252 L342,252' stroke='#b5b3aa' stroke-width='2'/>"
    art += f"<polyline points='{pts(ps)}' fill='none' stroke='{ink}' stroke-width='3.5' stroke-linejoin='round'/>"
    art += "".join(f"<circle cx='{x}' cy='{y}' r='4' fill='{ink}'/>" for x, y in ps)
    for i, kind in enumerate(("sun", "cloud", "rain", "sun", "cloud")):
        x, y = 196 + i * 34, 290
        if kind == "sun":
            art += f"<circle cx='{x}' cy='{y}' r='7' fill='{ink}'/>"
        else:
            art += f"<path d='M{x - 11},{y + 4} a6,6 0 0 1 4,-11 a8,8 0 0 1 15,1 a6,6 0 0 1 3,10 Z' fill='{ink}'/>"
            if kind == "rain":
                art += f"<path d='M{x - 5},{y + 8} l-2,6 M{x + 3},{y + 8} l-2,6' stroke='{ink}' stroke-width='2.5' stroke-linecap='round'/>"
    art += "</g>"
    return page(w, h, svg(w, h, art, defs))


def rss_2(w, h):
    """The return of local-first: blocks coming home from a cloud into a phone."""
    defs = shadow("sh", 12, 10, .22, "#6b4a00")
    art = f"<rect width='{w}' height='{h}' fill='#ffd23f'/>"
    art += "<circle cx='250' cy='250' r='190' fill='#ffdf6e'/>"
    art += ("<g filter='url(#sh)'><rect x='170' y='80' width='170' height='320' rx='30' fill='#1b2140'/>"
            "<rect x='182' y='94' width='146' height='292' rx='20' fill='#f7f3ea'/></g>")
    stack = [("#ff4f6d", 0), ("#3b7bff", 1), ("#1bb58a", 2), ("#ff4f6d", 3), ("#3b7bff", 4)]
    for c, i in stack:
        art += f"<rect x='{204 + (i % 2) * 52}' y='{320 - (i // 2) * 52}' width='46' height='46' rx='10' fill='{c}'/>"
    art += ("<g filter='url(#sh)'><g fill='#ffffff'>"
            "<circle cx='620' cy='130' r='56'/><circle cx='680' cy='150' r='44'/><circle cx='566' cy='156' r='38'/>"
            "<rect x='540' y='140' width='180' height='54' rx='27'/></g></g>")
    art += "<path d='M600,200 C590,300 460,330 348,300' stroke='#1b2140' stroke-width='5' fill='none' stroke-dasharray='2 14' stroke-linecap='round'/>"
    for t, c in ((0.18, "#1bb58a"), (0.5, "#ff4f6d"), (0.8, "#3b7bff")):
        x = (1 - t) ** 3 * 600 + 3 * (1 - t) ** 2 * t * 590 + 3 * (1 - t) * t * t * 460 + t ** 3 * 348
        y = (1 - t) ** 3 * 200 + 3 * (1 - t) ** 2 * t * 300 + 3 * (1 - t) * t * t * 330 + t ** 3 * 300
        art += f"<rect x='{x - 17:.0f}' y='{y - 17:.0f}' width='34' height='34' rx='8' fill='{c}' transform='rotate({t * 60 - 20:.0f} {x:.0f} {y:.0f})' filter='url(#sh)'/>"
    art += "<polygon points='352,284 334,300 356,314' fill='#1b2140'/>"
    return page(w, h, svg(w, h, art, defs))


def rss_3(w, h):
    """The paper map's return: a folded map open on a desk, a pencilled route, a
    compass on it, and a phone turned face down beside it."""
    defs = (shadow("sh", 14, 14, .35, "#0d1a1d") + lin("brass", [(0, "#f3d382"), (1, "#b8862f")], 1, 1)
            + "<clipPath id='map'><rect x='150' y='50' width='500' height='340'/></clipPath>")
    art = f"<rect width='{w}' height='{h}' fill='#284650'/>"
    art += "<g transform='rotate(-5 400 220)'>"
    art += "<g filter='url(#sh)'><rect x='150' y='50' width='500' height='340' fill='#f3ecd9'/></g>"
    m = "<g clip-path='url(#map)'>"
    rng = random.Random(8)
    # land use: woods and a lake, contour rings, a river
    for cx, cy, rx, ry in ((250, 120, 90, 60), (560, 320, 110, 70), (470, 90, 60, 40)):
        m += f"<ellipse cx='{cx}' cy='{cy}' rx='{rx}' ry='{ry}' fill='#cfe0b4'/>"
    for k in range(5):
        m += f"<ellipse cx='{380 + k * 3}' cy='{250 - k * 4}' rx='{120 - k * 22}' ry='{78 - k * 14}' fill='none' stroke='#c9a77a' stroke-width='1.6'/>"
    m += "<path d='M150,330 C230,300 260,360 340,330 C420,300 440,220 520,200 C580,186 610,140 650,120' stroke='#7fb3d5' stroke-width='12' fill='none'/>"
    m += "<ellipse cx='600' cy='210' rx='34' ry='22' fill='#9cc6e0'/>"
    # roads, then the pencilled route over them
    m += ("<path d='M150,200 C260,210 330,170 420,180 C520,190 560,260 650,250' stroke='#ffffff' stroke-width='9' fill='none'/>"
          "<path d='M150,200 C260,210 330,170 420,180 C520,190 560,260 650,250' stroke='#e8a33a' stroke-width='5' fill='none'/>"
          "<path d='M300,50 C310,140 280,260 320,390' stroke='#ffffff' stroke-width='6' fill='none'/>"
          "<path d='M470,50 C460,120 500,220 470,390' stroke='#ffffff' stroke-width='5' fill='none'/>")
    for _ in range(14):  # a village's houses
        x, y = rng.uniform(395, 455), rng.uniform(150, 210)
        m += f"<rect x='{x:.0f}' y='{y:.0f}' width='8' height='8' fill='#7b6a5a'/>"
    m += ("<path d='M210,150 C250,190 280,236 330,250 C390,268 420,300 520,296' stroke='#d6342c' stroke-width='4' fill='none' "
          "stroke-dasharray='10 8' stroke-linecap='round'/>"
          "<circle cx='210' cy='150' r='8' fill='#d6342c'/>"
          "<circle cx='520' cy='296' r='13' fill='none' stroke='#d6342c' stroke-width='4'/>")
    # the folds: alternate panels catch the light differently
    for i in range(4):
        for j in range(2):
            shade = "#ffffff" if (i + j) % 2 == 0 else "#5a4320"
            op = 0.18 if shade == "#ffffff" else 0.10
            m += f"<rect x='{150 + i * 125}' y='{50 + j * 170}' width='125' height='170' fill='{shade}' opacity='{op}'/>"
    for i in range(1, 4):
        m += f"<path d='M{150 + i * 125},50 L{150 + i * 125},390' stroke='#5a4320' stroke-width='1.5' opacity='.25'/>"
    m += "<path d='M150,220 L650,220' stroke='#5a4320' stroke-width='1.5' opacity='.25'/>"
    art += m + "</g></g>"
    # the compass on the map
    art += ("<g filter='url(#sh)'><circle cx='600' cy='120' r='58' fill='url(#brass)'/></g>"
            "<circle cx='600' cy='120' r='48' fill='#fbf7ec'/>"
            + "".join(f"<path d='M{600 + 40 * math.cos(a):.1f},{120 + 40 * math.sin(a):.1f} L{600 + 46 * math.cos(a):.1f},{120 + 46 * math.sin(a):.1f}' stroke='#3a3a3a' stroke-width='2.5'/>"
                      for a in [i * math.pi / 8 for i in range(16)])
            + "<g transform='rotate(24 600 120)'><polygon points='600,80 610,120 590,120' fill='#d6342c'/><polygon points='600,160 610,120 590,120' fill='#3a3a3a'/></g>"
            "<circle cx='600' cy='120' r='5' fill='#b8862f'/>")
    # a pencil across the corner
    art += ("<g transform='translate(470 400) rotate(-28)' filter='url(#sh)'>"
            "<rect x='0' y='-9' width='200' height='18' fill='#f2c14e'/><rect x='0' y='-9' width='200' height='6' fill='#f7d77a'/>"
            "<polygon points='0,-9 -30,0 0,9' fill='#e9cfa2'/><polygon points='-20,-3 -30,0 -20,3' fill='#3a3a3a'/>"
            "<rect x='200' y='-9' width='16' height='18' fill='#c9ccce'/><rect x='216' y='-9' width='18' height='18' rx='4' fill='#ef8a8a'/></g>")
    # the phone, face down, set aside
    art += ("<g transform='rotate(14 96 300)' filter='url(#sh)'><rect x='40' y='196' width='112' height='210' rx='22' fill='#1b2427'/>"
            "<rect x='58' y='214' width='40' height='54' rx='14' fill='#2a363a'/><circle cx='70' cy='228' r='8' fill='#0f1517'/><circle cx='86' cy='252' r='8' fill='#0f1517'/></g>")
    return page(w, h, svg(w, h, art, defs))


def rss_4(w, h):
    """Why your app feels slow: a snail whose shell is a loading spinner."""
    defs = lin("bg", [(0, "#0f6e6a"), (1, "#0a3f4a")], 1, 1) + shadow("sh", 10, 10, .3)
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += "<rect x='80' y='330' width='640' height='22' rx='11' fill='#ffffff1f'/>"
    art += "<rect x='80' y='330' width='250' height='22' rx='11' fill='#7ee0c3'/>"
    art += ("<g filter='url(#sh)'><path d='M220,330 Q210,300 250,296 L470,296 Q520,296 540,262 Q552,240 572,244 Q590,250 580,280 Q570,318 520,330 Z' fill='#f4ead2'/>"
            "<path d='M556,246 L548,200 M572,246 L586,204' stroke='#f4ead2' stroke-width='6' stroke-linecap='round'/>"
            "<circle cx='548' cy='198' r='8' fill='#f4ead2'/><circle cx='586' cy='202' r='8' fill='#f4ead2'/></g>")
    cx, cy, r = 380, 210, 92
    art += f"<circle cx='{cx}' cy='{cy}' r='{r + 8}' fill='#0a3f4a'/>"
    for i in range(12):
        a = i * math.pi / 6
        x1, y1 = cx + 46 * math.cos(a), cy + 46 * math.sin(a)
        x2, y2 = cx + 82 * math.cos(a), cy + 82 * math.sin(a)
        art += f"<line x1='{x1:.1f}' y1='{y1:.1f}' x2='{x2:.1f}' y2='{y2:.1f}' stroke='#7ee0c3' stroke-width='18' stroke-linecap='round' opacity='{0.12 + 0.88 * i / 11:.2f}'/>"
    return page(w, h, svg(w, h, art, defs))


def rss_5(w, h):
    """The cost of a background sync: a phone at night, a sync ring, a battery running low."""
    defs = (lin("sky", [(0, "#0b1030"), (1, "#1b2a5a")]) + blur("b", 16) + shadow("sh", 10, 12, .4))
    art = f"<rect width='{w}' height='{h}' fill='url(#sky)'/>"
    rng = random.Random(5)
    for _ in range(26):
        art += f"<circle cx='{rng.uniform(0, w):.0f}' cy='{rng.uniform(0, 260):.0f}' r='{rng.uniform(1, 2.4):.1f}' fill='#fff' opacity='{rng.uniform(.3, .8):.2f}'/>"
    art += "<circle cx='660' cy='96' r='44' fill='#f7e7b8'/><circle cx='682' cy='82' r='40' fill='#0e1436'/>"
    art += f"<rect x='0' y='360' width='{w}' height='90' fill='#0a0d22'/>"
    art += "<circle cx='400' cy='230' r='120' fill='#5f7bff' opacity='.25' filter='url(#b)'/>"
    for a0 in (0, 180):
        a1, a2 = math.radians(a0 + 20), math.radians(a0 + 150)
        x1, y1 = 400 + 132 * math.cos(a1), 230 + 132 * math.sin(a1)
        x2, y2 = 400 + 132 * math.cos(a2), 230 + 132 * math.sin(a2)
        art += f"<path d='M{x1:.1f},{y1:.1f} A132,132 0 0 1 {x2:.1f},{y2:.1f}' stroke='#9fb2ff' stroke-width='10' fill='none' stroke-linecap='round'/>"
        tx, ty = x2, y2
        dx, dy = -math.sin(a2), math.cos(a2)
        nx, ny = math.cos(a2), math.sin(a2)
        art += f"<polygon points='{pts([(tx + dx * 22, ty + dy * 22), (tx + nx * 16, ty + ny * 16), (tx - nx * 16, ty - ny * 16)])}' fill='#9fb2ff'/>"
    art += ("<g filter='url(#sh)'><rect x='340' y='120' width='120' height='220' rx='22' fill='#141a3a'/>"
            "<rect x='350' y='130' width='100' height='200' rx='14' fill='#1f2a5c'/></g>"
            "<rect x='370' y='210' width='52' height='26' rx='6' fill='none' stroke='#ffd166' stroke-width='4'/>"
            "<rect x='424' y='218' width='5' height='10' rx='2' fill='#ffd166'/>"
            "<rect x='376' y='216' width='10' height='14' rx='2' fill='#ff6b5a'/>")
    return page(w, h, svg(w, h, art, defs))


def rss_6(w, h):
    """Night trains are busy again: a sleeper crossing a viaduct after dark,
    every window lit and full, the light doubled in the lake below."""
    defs = (lin("sky", [(0, "#120f33"), (0.55, "#2c2361"), (1, "#6a4180")]) + lin("lake", [(0, "#2a2257"), (1, "#0d0b24")])
            + lin("beam", [(0, "#fff1c4aa"), (1, "#fff1c400")], 1, 0) + blur("g", 16))
    art = f"<rect width='{w}' height='{h}' fill='url(#sky)'/>"
    rng = random.Random(16)
    for _ in range(46):
        art += f"<circle cx='{rng.uniform(0, w):.0f}' cy='{rng.uniform(0, 150):.0f}' r='{rng.uniform(0.8, 1.9):.1f}' fill='#fff' opacity='{rng.uniform(.25, .75):.2f}'/>"
    far = [(0, 196), (90, 150), (190, 186), (300, 118), (420, 180), (540, 128), (660, 176), (800, 140), (800, 320), (0, 320)]
    art += f"<polygon points='{pts(far)}' fill='#43357a'/>"
    near = [(0, 250), (120, 222), (260, 252), (380, 218), (520, 246), (650, 214), (800, 240), (800, 320), (0, 320)]
    art += f"<polygon points='{pts(near)}' fill='#33295f'/>"
    lake = 320
    art += f"<rect x='0' y='{lake}' width='{w}' height='{h - lake}' fill='url(#lake)'/>"
    # the viaduct: a deck on tall arched piers, a silhouette against the hills
    deck = 222
    via = "#120e2a"
    art += f"<rect x='0' y='{deck}' width='{w}' height='16' fill='{via}'/>"
    for x in range(-60, w + 100, 100):
        art += (f"<path d='M{x},{deck + 16} L{x},{lake + 6} L{x + 18},{lake + 6} L{x + 18},{deck + 70} "
                f"Q{x + 50},{deck + 24} {x + 82},{deck + 70} L{x + 82},{lake + 6} L{x + 100},{lake + 6} L{x + 100},{deck + 16} Z' fill='{via}'/>")
        # the pier's reflection, broken by ripples
        for r in range(4):
            art += f"<rect x='{x + 1}' y='{lake + 12 + r * 16}' width='16' height='8' fill='{via}' opacity='{0.7 - r * 0.15:.2f}'/>"
    # the train, heading right: coaches off the left edge, the engine and its lamp beam
    win = "#ffcf6e"
    body, roof, band = "#1e3a52", "#2a5070", "#c9452f"
    coaches = [(-70 + i * 132, 126) for i in range(5)]
    eng_x = coaches[-1][0] + 132
    tr = f"<polygon points='{eng_x + 120},{deck - 36} {w + 10},{deck - 70} {w + 10},{deck + 10} {eng_x + 120},{deck - 14}' fill='url(#beam)'/>"
    glow = ""
    for i, (x, cw) in enumerate(coaches):
        tr += f"<rect x='{x}' y='{deck - 50}' width='{cw}' height='48' rx='8' fill='{body}'/>"
        tr += f"<rect x='{x + 4}' y='{deck - 54}' width='{cw - 8}' height='10' rx='5' fill='{roof}'/>"
        tr += f"<rect x='{x}' y='{deck - 14}' width='{cw}' height='5' fill='{band}'/>"
        for k in range(3):
            wx = x + 12 + k * 38
            glow += f"<rect x='{wx - 4}' y='{deck - 44}' width='38' height='32' fill='{win}'/>"
            tr += f"<rect x='{wx}' y='{deck - 40}' width='30' height='22' rx='3' fill='{win}'/>"
            n = 1 + (i * 5 + k * 2) % 2  # busy: nobody's window is empty
            if (i + k) % 4 == 1:
                tr += f"<path d='M{wx + 2},{deck - 38} L{wx + 9},{deck - 38} Q{wx + 6},{deck - 28} {wx + 9},{deck - 20} L{wx + 2},{deck - 20} Z' fill='#d98e3e'/>"
            for j in range(n):
                hx = wx + (17 if n == 1 else 12 + j * 11)
                c = ["#3a2a3f", "#4a3346", "#2c2236"][(i + k + j) % 3]
                tr += (f"<circle cx='{hx}' cy='{deck - 31}' r='4' fill='{c}'/>"
                       f"<rect x='{hx - 5.5}' y='{deck - 25.5}' width='11' height='8' rx='4' fill='{c}'/>")
        tr += f"<rect x='{x + cw}' y='{deck - 40}' width='6' height='28' fill='#14243a'/>"
    tr += (f"<path d='M{eng_x},{deck - 2} L{eng_x},{deck - 52} L{eng_x + 92},{deck - 52} Q{eng_x + 120},{deck - 50} {eng_x + 124},{deck - 22} L{eng_x + 124},{deck - 2} Z' fill='{body}'/>"
           f"<path d='M{eng_x + 92},{deck - 46} Q{eng_x + 112},{deck - 44} {eng_x + 116},{deck - 30} L{eng_x + 92},{deck - 30} Z' fill='{win}'/>"
           f"<rect x='{eng_x}' y='{deck - 14}' width='124' height='5' fill='{band}'/>"
           f"<circle cx='{eng_x + 118}' cy='{deck - 20}' r='4' fill='#fff7da'/>")
    art += f"<g filter='url(#g)' opacity='.55'>{glow}</g>" + tr
    # the windows' light on the water, broken into streaks
    for x, cw in coaches:
        for k in range(3):
            wx = x + 12 + k * 38
            for r in range(6):
                ww = 28 - r * 3 + rng.uniform(-4, 3)
                art += f"<rect x='{wx + rng.uniform(-4, 4):.0f}' y='{lake + 14 + r * 15}' width='{ww:.0f}' height='4' rx='2' fill='{win}' opacity='{0.6 - r * 0.09:.2f}'/>"
    return page(w, h, svg(w, h, art, defs))


# ── Bluesky link card (800×420) ───────────────────────────────────────────

def bsky_link_0(w, h):
    """A laptop holding its own data: a small shelf of files inside the screen."""
    defs = (lin("bg", [(0, "#eef0e6"), (1, "#dfe5d6")]) + lin("scr", [(0, "#f7f4ec"), (1, "#ece6d8")])
            + shadow("sh", 14, 18, .18, "#3d4a33"))
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += f"<rect x='0' y='330' width='{w}' height='90' fill='#d3dac7'/>"
    art += "<circle cx='640' cy='96' r='54' fill='#f3d9b1'/>"
    art += ("<g filter='url(#sh)'><rect x='210' y='60' width='380' height='250' rx='18' fill='#3b4236'/>"
            "<path d='M170,318 L630,318 L606,340 L194,340 Z' fill='#8e9784'/>"
            "<rect x='170' y='310' width='460' height='12' rx='6' fill='#b5bdab'/></g>"
            "<rect x='224' y='74' width='352' height='222' rx='8' fill='url(#scr)'/>")
    cols = ["#c9785a", "#7f9a6b", "#d9b56a", "#6f8fa6", "#c9785a", "#9a86b0", "#7f9a6b"]
    x = 262
    for i, c in enumerate(cols):
        hh = 70 + (i * 17) % 40
        ww = 26 + (i % 3) * 6
        art += f"<rect x='{x}' y='{240 - hh}' width='{ww}' height='{hh}' rx='5' fill='{c}'/>"
        x += ww + 6
    art += "<rect x='250' y='240' width='300' height='10' rx='3' fill='#b58c63'/>"
    art += ("<g transform='translate(500 180)'><path d='M0,60 L0,20' stroke='#5c7a4f' stroke-width='4'/>"
            "<ellipse cx='-12' cy='18' rx='14' ry='7' fill='#6f9a5c' transform='rotate(-30 -12 18)'/>"
            "<ellipse cx='12' cy='10' rx='14' ry='7' fill='#86b070' transform='rotate(25 12 10)'/>"
            "<path d='M-16,40 L16,40 L12,60 L-12,60 Z' fill='#c9785a'/></g>")
    art += ("<g transform='translate(118 250)'><path d='M-22,0 L22,0 L18,68 L-18,68 Z' fill='#f7f4ec'/>"
            "<path d='M22,14 C40,14 40,44 20,44' stroke='#f7f4ec' stroke-width='8' fill='none'/>"
            "<path d='M-6,-10 C-12,-24 4,-30 -2,-44 M8,-10 C2,-22 16,-28 10,-40' stroke='#b5bdab' stroke-width='3' fill='none' stroke-linecap='round'/></g>")
    return page(w, h, svg(w, h, art, defs))


# ── Raindrop bookmark covers (800×420) ────────────────────────────────────

def raindrop_0(w, h):
    """HIG: soft UI panels layered in depth on a pale wash."""
    defs = (lin("bg", [(0, "#e7ecf9"), (1, "#f5eefb")], 1, 1) + shadow("sh", 18, 22, .16, "#2a3570"))
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += "<circle cx='120' cy='360' r='140' fill='#d9e2fb'/><circle cx='720' cy='40' r='120' fill='#f1def5'/>"
    art += ("<g filter='url(#sh)'><rect x='140' y='70' width='300' height='300' rx='30' fill='#ffffff' opacity='.8'/></g>"
            "<rect x='170' y='104' width='160' height='16' rx='8' fill='#d6dcef'/>"
            "<rect x='170' y='134' width='220' height='12' rx='6' fill='#e7ebf5'/>"
            "<rect x='170' y='156' width='190' height='12' rx='6' fill='#e7ebf5'/>")
    art += ("<g filter='url(#sh)'><rect x='300' y='130' width='330' height='220' rx='30' fill='#ffffff'/></g>"
            "<circle cx='350' cy='182' r='24' fill='#7c8cff'/>"
            "<rect x='386' y='168' width='140' height='12' rx='6' fill='#cfd5ea'/><rect x='386' y='188' width='90' height='10' rx='5' fill='#e3e7f3'/>"
            "<rect x='330' y='236' width='270' height='8' rx='4' fill='#e3e7f3'/><rect x='330' y='236' width='170' height='8' rx='4' fill='#7c8cff'/>"
            "<circle cx='500' cy='240' r='14' fill='#fff' stroke='#e3e7f3' stroke-width='2'/>"
            "<rect x='330' y='280' width='150' height='12' rx='6' fill='#e3e7f3'/>"
            "<rect x='540' y='272' width='60' height='32' rx='16' fill='#35c46b'/><circle cx='584' cy='288' r='13' fill='#fff'/>")
    art += ("<g filter='url(#sh)'><rect x='560' y='60' width='130' height='130' rx='30' fill='#ffffff'/></g>"
            "<rect x='584' y='84' width='82' height='82' rx='20' fill='#ff9f6b'/>"
            "<g filter='url(#sh)'><rect x='240' y='300' width='120' height='54' rx='27' fill='#1f2a55'/></g>"
            "<rect x='266' y='322' width='68' height='10' rx='5' fill='#ffffffcc'/>")
    return page(w, h, svg(w, h, art, defs))


def raindrop_0b(w, h):
    """HIG, second image: a colour and typography specimen page."""
    art = f"<rect width='{w}' height='{h}' fill='#fbfaf7'/>"
    art += text(40, 250, "Aa", 230, "#161616", SERIF, 600)
    art += text(46, 300, "Serif · Display", 20, "#8a8a8a", SANS, 500)
    ladder = [("Large Title", 34, 700), ("Title", 26, 600), ("Headline", 20, 600), ("Body", 17, 400), ("Caption", 13, 400)]
    y = 70
    for s, sz, wt in ladder:
        art += text(360, y, s, sz, "#222", SANS, wt)
        y += sz + 22
    art += "<rect x='40' y='340' width='280' height='40' rx='10' fill='#161616'/>" + text(180, 366, "Button", 17, "#fff", SANS, 600, "middle")
    sw = [("#ff3b30", "Red"), ("#ff9500", "Orange"), ("#ffcc00", "Yellow"), ("#34c759", "Green"),
          ("#30b0c7", "Teal"), ("#007aff", "Blue"), ("#5856d6", "Indigo"), ("#af52de", "Purple"), ("#ff2d55", "Pink")]
    for i, (c, n) in enumerate(sw):
        x, yy = 560 + (i % 3) * 72, 50 + (i // 3) * 112
        art += f"<rect x='{x}' y='{yy}' width='60' height='60' rx='14' fill='{c}'/>"
        art += text(x, yy + 82, n, 13, "#333", SANS, 600) + text(x, yy + 98, c.upper(), 11, "#999", MONO, 400)
    return page(w, h, svg(w, h, art))


def raindrop_1(w, h):
    """SwiftUI docs: nested stacks drawn as a blueprint over a layout grid."""
    art = f"<rect width='{w}' height='{h}' fill='#0d2d5e'/>"
    for x in range(0, w + 1, 20):
        art += f"<line x1='{x}' y1='0' x2='{x}' y2='{h}' stroke='#ffffff{'1f' if x % 100 == 0 else '0c'}'/>"
    for y in range(0, h + 1, 20):
        art += f"<line x1='0' y1='{y}' x2='{w}' y2='{y}' stroke='#ffffff{'1f' if y % 100 == 0 else '0c'}'/>"
    st = "stroke='#e8f1ff' stroke-width='3' fill='none'"
    art += f"<rect x='240' y='40' width='320' height='340' rx='14' {st}/>"
    art += f"<rect x='270' y='70' width='260' height='100' rx='10' {st} stroke-dasharray='10 7'/>"
    art += "<rect x='290' y='90' width='60' height='60' rx='12' fill='#ff8a3d'/>"
    art += "<rect x='370' y='100' width='140' height='14' rx='7' fill='#e8f1ff'/><rect x='370' y='126' width='100' height='10' rx='5' fill='#e8f1ff88'/>"
    for i in range(3):
        y = 190 + i * 60
        art += f"<rect x='270' y='{y}' width='260' height='44' rx='10' {st}/>"
        art += f"<rect x='286' y='{y + 15}' width='{150 - i * 30}' height='14' rx='7' fill='#e8f1ff66'/>"
    art += ("<path d='M580,70 L580,170' stroke='#ff8a3d' stroke-width='2.5'/><path d='M572,70 L588,70 M572,170 L588,170' stroke='#ff8a3d' stroke-width='2.5'/>"
            + text(596, 126, "16", 20, "#ff8a3d", MONO, 700)
            + "<path d='M270,26 L530,26' stroke='#ff8a3d' stroke-width='2.5'/><path d='M270,18 L270,34 M530,18 L530,34' stroke='#ff8a3d' stroke-width='2.5'/>")
    art += "<line x1='400' y1='0' x2='400' y2='420' stroke='#ff8a3d' stroke-width='1.5' stroke-dasharray='4 6' opacity='.6'/>"
    art += "".join(f"<rect x='{x}' y='{y}' width='70' height='{hh}' rx='8' fill='none' stroke='#e8f1ff55' stroke-width='2'/>" for x, y, hh in ((80, 80, 120), (80, 220, 70), (650, 110, 180)))
    return page(w, h, svg(w, h, art))


def raindrop_2(w, h):
    """A field guide to Berlin courtyards: one city block in isometric, its
    wings and rear houses in stucco, the courtyards inside picked out in green."""
    P = iso(400, 62, 28)
    art = f"<rect width='{w}' height='{h}' fill='#efe9dd'/>"
    # the streets round the block, and the pavements
    art += f"<polygon points='{pts([P(-3, -3, 0), P(15, -3, 0), P(15, 13, 0), P(-3, 13, 0)])}' fill='#d9d2c4'/>"
    art += f"<polygon points='{pts([P(-0.8, -0.8, 0), P(12.8, -0.8, 0), P(12.8, 10.8, 0), P(-0.8, 10.8, 0)])}' fill='#e8e2d6'/>"
    for t in range(0, 13, 2):  # street trees
        for (x, y) in ((t, -1.9), (13.6, t * 10 / 12)):
            cx, cy = P(x, y, 0.9)
            art += f"<circle cx='{cx:.1f}' cy='{cy:.1f}' r='9' fill='#9cbf8a'/>"
    # the courtyards' floors, in green
    courts = [(1.6, 1.6, 3.8, 3.0), (6.2, 1.6, 4.2, 3.0), (7.0, 4.6, 3.4, 1.0), (1.6, 5.6, 8.8, 2.8)]
    for x, y, cw, cd in courts:
        art += f"<polygon points='{pts([P(x, y, 0), P(x + cw, y, 0), P(x + cw, y + cd, 0), P(x, y + cd, 0)])}' fill='#4fbf62'/>"

    def trees(spots):
        out = ""
        for x, y, r in spots:
            gx, gy = P(x, y, 0)
            cx, cy = P(x, y, 1.1)
            out += f"<ellipse cx='{gx:.1f}' cy='{gy:.1f}' rx='{r * 0.9:.0f}' ry='{r * 0.45:.0f}' fill='#3f8a4c'/>"
            out += f"<path d='M{gx:.1f},{gy:.1f} L{cx:.1f},{cy:.1f}' stroke='#6b4f3a' stroke-width='3'/>"
            out += f"<circle cx='{cx:.1f}' cy='{cy:.1f}' r='{r}' fill='#2f9a4f'/><circle cx='{cx - r * 0.3:.1f}' cy='{cy - r * 0.35:.1f}' r='{r * 0.45:.1f}' fill='#7fd08a'/>"
        return out

    def block(x, y, bw, bd, hh, top, left, right):
        out = iso_box(P, x, y, 0, bw, bd, hh, top, left, right)
        # windows on the two faces we can see
        for k in range(int(bw / 0.8)):
            for f in range(int(hh / 0.5)):
                a = x + 0.25 + k * 0.8
                z = 0.35 + f * 0.5
                if a + 0.35 < x + bw:
                    out += f"<polygon points='{pts([P(a, y + bd, z), P(a + 0.35, y + bd, z), P(a + 0.35, y + bd, z + 0.25), P(a, y + bd, z + 0.25)])}' fill='#00000033'/>"
        for k in range(int(bd / 0.8)):
            for f in range(int(hh / 0.5)):
                b = y + 0.25 + k * 0.8
                z = 0.35 + f * 0.5
                if b + 0.35 < y + bd:
                    out += f"<polygon points='{pts([P(x + bw, b, z), P(x + bw, b + 0.35, z), P(x + bw, b + 0.35, z + 0.25), P(x + bw, b, z + 0.25)])}' fill='#00000026'/>"
        return out

    roof = "#c98a6a"
    art += block(0, 0, 12, 1.6, 1.7, roof, "#e8cfa6", "#d6b88c")         # the back row
    art += block(0, 1.6, 1.6, 6.8, 1.6, roof, "#e6d6c0", "#d9c4a6")       # the left row
    art += block(5.4, 1.6, 0.8, 3.0, 1.4, roof, "#efe3cf", "#ddcdb2")     # a side wing
    art += trees([(3.4, 3.2, 13), (8.4, 3.0, 12)])
    art += block(1.6, 4.6, 5.4, 1.0, 1.4, roof, "#f0d9c6", "#e0c3aa")     # the rear house
    art += block(10.4, 1.6, 1.6, 6.8, 1.6, roof, "#e3c9b7", "#d2b19b")    # the right row
    art += trees([(4.0, 7.0, 15), (8.4, 6.8, 11)])
    art += block(0, 8.4, 12, 1.6, 1.8, roof, "#f2dcc0", "#e2c6a0")        # the street front
    # a gateway through the front, into the first court
    gx = 5.4
    art += f"<polygon points='{pts([P(gx, 10, 0), P(gx + 1, 10, 0), P(gx + 1, 10, 0.75), P(gx, 10, 0.75)])}' fill='#4a3a32'/>"
    return page(w, h, svg(w, h, art))


def raindrop_3(w, h):
    """Allotment planting calendar: months across, vegetables down, a sowing
    bar and a harvest bar on each row."""
    art = f"<rect width='{w}' height='{h}' fill='#e6efdc'/>"
    art += "<rect x='24' y='20' width='752' height='380' rx='16' fill='#fffdf6'/>"
    art += text(48, 60, "Planting calendar", 24, "#2e3a28", SERIF, 700)
    left, col, top, row = 176, 48, 112, 38
    months = "JFMAMJJASOND"
    for i, m in enumerate(months):
        x = left + i * col
        if i % 2 == 0:
            art += f"<rect x='{x}' y='{top - 30}' width='{col}' height='{row * 7 + 34}' fill='#f2efe2'/>"
        art += text(x + col / 2, top - 10, m, 15, "#6b7560", SANS, 700, "middle")
    sow, crop = "#c98a4f", "#4f9a4a"
    veg = [("Broad beans", "#7fae5a", [(2, 4)], [(6, 8)]),
           ("Carrots", "#ef8a3c", [(4, 7)], [(7, 10)]),
           ("Lettuce", "#9ccc65", [(3, 8)], [(5, 10)]),
           ("Tomatoes", "#e2553a", [(2, 3)], [(7, 9)]),
           ("Potatoes", "#c9a26b", [(3, 4)], [(7, 9)]),
           ("Squash", "#f2b632", [(4, 5)], [(9, 10)]),
           ("Leeks", "#6aa37a", [(3, 4)], [(10, 12), (1, 2)])]
    for r, (name, c, sows, crops) in enumerate(veg):
        y = top + r * row
        art += f"<circle cx='56' cy='{y + 18}' r='8' fill='{c}'/>"
        art += text(74, y + 24, name, 16, "#2e3a28", SANS, 600)
        for a, b in sows:
            art += f"<rect x='{left + (a - 1) * col + 4}' y='{y + 6}' width='{(b - a + 1) * col - 8}' height='10' rx='5' fill='{sow}'/>"
        for a, b in crops:
            art += f"<rect x='{left + (a - 1) * col + 4}' y='{y + 20}' width='{(b - a + 1) * col - 8}' height='12' rx='6' fill='{crop}'/>"
    ly = top + 7 * row + 18
    art += (f"<rect x='{left}' y='{ly}' width='28' height='10' rx='5' fill='{sow}'/>" + text(left + 36, ly + 10, "Sow", 14, "#4a5541", SANS, 600)
            + f"<rect x='{left + 90}' y='{ly - 1}' width='28' height='12' rx='6' fill='{crop}'/>" + text(left + 126, ly + 10, "Harvest", 14, "#4a5541", SANS, 600))
    # a sprouting seedling in the corner
    art += ("<g transform='translate(726 58)'><path d='M0,10 L0,-12' stroke='#4f9a4a' stroke-width='3' stroke-linecap='round'/>"
            "<path d='M0,-6 C-14,-8 -18,-20 -16,-26 C-6,-24 0,-16 0,-6Z' fill='#6fbf5a'/>"
            "<path d='M0,-10 C12,-14 18,-26 16,-30 C6,-28 0,-20 0,-10Z' fill='#4f9a4a'/>"
            "<path d='M-16,10 L16,10 L12,22 L-12,22 Z' fill='#c98a4f'/></g>")
    return page(w, h, svg(w, h, art))


def raindrop_3b(w, h):
    """The planting calendar, second image: seed packets fanned out on a wooden
    table, a trowel beside them, a few seeds spilled."""
    defs = shadow("sh", 8, 8, .3, "#3a2410") + lin("blade", [(0, "#e3e6e8"), (0.5, "#a9b0b5"), (1, "#7d858b")], 1, 0)
    art = f"<rect width='{w}' height='{h}' fill='#b98552'/>"
    rng = random.Random(30)
    for y in range(0, h, 84):  # planks and their grain
        art += f"<rect x='0' y='{y}' width='{w}' height='82' fill='{rng.choice(['#b98552', '#c08b57', '#b27e4c'])}'/>"
        art += f"<rect x='0' y='{y + 82}' width='{w}' height='2' fill='#8a5c32'/>"
        for _ in range(4):
            gy = y + rng.uniform(10, 72)
            art += f"<path d='M0,{gy:.0f} C200,{gy - 6:.0f} 400,{gy + 8:.0f} {w},{gy - 2:.0f}' stroke='#a3703f' stroke-width='2' fill='none' opacity='.6'/>"

    def carrot():
        return ("<path d='M-10,-30 L10,-30 L0,24 Z' fill='#ef8a3c'/>"
                "<path d='M0,-30 L-10,-52 M0,-30 L0,-56 M0,-30 L10,-52' stroke='#4f9a4a' stroke-width='5' stroke-linecap='round'/>")

    def tomato():
        return ("<circle cx='0' cy='0' r='26' fill='#e2553a'/><circle cx='-8' cy='-8' r='7' fill='#ffffff44'/>"
                "<path d='M0,-24 L-10,-30 M0,-24 L10,-30 M0,-24 L0,-34 M0,-24 L-12,-20 M0,-24 L12,-20' stroke='#3f8a4c' stroke-width='4' stroke-linecap='round'/>")

    def pea():
        return ("<path d='M-30,10 Q0,-30 30,-10 Q0,22 -30,10 Z' fill='#6fbf5a'/>"
                + "".join(f"<circle cx='{x}' cy='{-2 - x * 0.2:.0f}' r='6' fill='#9be07f'/>" for x in (-14, 0, 14)))

    def beet():
        return ("<circle cx='0' cy='6' r='22' fill='#8e2b5a'/><path d='M0,28 Q2,38 -2,46' stroke='#8e2b5a' stroke-width='3' fill='none'/>"
                "<path d='M0,-14 C-16,-30 -14,-44 -6,-46 C0,-36 2,-24 0,-14 Z M0,-14 C14,-32 20,-40 12,-48 C4,-40 0,-28 0,-14 Z' fill='#4f9a4a'/>")

    def sunflower():
        out = "".join(f"<ellipse cx='0' cy='-20' rx='7' ry='14' fill='#f2c14e' transform='rotate({a})'/>" for a in range(0, 360, 30))
        return out + "<circle r='14' fill='#6b4a2a'/>"

    packets = [(-30, "#f4c9a0", carrot), (-15, "#f7d6d0", tomato), (0, "#d7ebc6", pea), (15, "#ead3e2", beet), (30, "#fbe7b0", sunflower)]
    px, py = 330, 520
    for rot, band, pic in packets:
        art += (f"<g transform='rotate({rot} {px} {py})' filter='url(#sh)'>"
                f"<rect x='{px - 72}' y='{py - 420}' width='144' height='210' rx='6' fill='#f7f1e3'/>"
                f"<rect x='{px - 72}' y='{py - 420}' width='144' height='26' rx='6' fill='{band}'/>"
                f"<path d='M{px - 72},{py - 400} l144,0' stroke='#00000014' stroke-width='2'/>"
                f"<rect x='{px - 54}' y='{py - 382}' width='108' height='100' rx='8' fill='{band}' opacity='.55'/>"
                f"<g transform='translate({px} {py - 332})'>{pic()}</g>"
                f"<rect x='{px - 54}' y='{py - 266}' width='84' height='9' rx='4.5' fill='#5a4a3a' opacity='.7'/>"
                f"<rect x='{px - 54}' y='{py - 250}' width='60' height='7' rx='3.5' fill='#5a4a3a' opacity='.35'/>"
                "</g>")
    # spilled seeds and a crumb of soil
    for _ in range(18):
        x, y = rng.uniform(470, 560), rng.uniform(330, 400)
        art += f"<ellipse cx='{x:.0f}' cy='{y:.0f}' rx='4' ry='2.5' fill='#f1e2c0' transform='rotate({rng.uniform(0, 180):.0f} {x:.0f} {y:.0f})'/>"
    for _ in range(14):
        x, y = rng.uniform(600, 700), rng.uniform(300, 360)
        art += f"<circle cx='{x:.0f}' cy='{y:.0f}' r='{rng.uniform(2, 5):.1f}' fill='#4a3322'/>"
    # the trowel
    art += ("<g transform='translate(640 210) rotate(28)' filter='url(#sh)'>"
            "<path d='M-40,0 C-40,-40 -10,-80 0,-110 C10,-80 40,-40 40,0 C40,22 -40,22 -40,0 Z' fill='url(#blade)'/>"
            "<path d='M0,-100 L0,8' stroke='#ffffff66' stroke-width='3'/>"
            "<rect x='-6' y='14' width='12' height='34' fill='#7d858b'/>"
            "<rect x='-15' y='46' width='30' height='120' rx='14' fill='#3f8a4c'/>"
            "<rect x='-11' y='50' width='8' height='108' rx='4' fill='#ffffff33'/>"
            "<circle cx='0' cy='150' r='4' fill='#1f4a28'/></g>")
    return page(w, h, svg(w, h, art, defs))


def raindrop_4(w, h):
    """CSS scroll-driven animations: a scrollbar's thumb driving a progress bar."""
    defs = lin("bg", [(0, "#4b2fd0"), (1, "#8f3fd8")], 1, 1) + shadow("sh", 18, 22, .35, "#1a0a50")
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += ("<g filter='url(#sh)'><rect x='170' y='40' width='460' height='340' rx='18' fill='#fbfaff'/></g>"
            "<rect x='170' y='40' width='460' height='40' rx='18' fill='#eeeaf9'/><rect x='170' y='62' width='460' height='18' fill='#eeeaf9'/>"
            "<circle cx='194' cy='60' r='6' fill='#d5cdef'/><circle cx='214' cy='60' r='6' fill='#d5cdef'/><circle cx='234' cy='60' r='6' fill='#d5cdef'/>"
            "<rect x='170' y='80' width='460' height='8' fill='#e6e0f7'/><rect x='170' y='80' width='276' height='8' fill='#ff7ab6'/>")
    for i, y in enumerate(range(110, 360, 44)):
        art += f"<rect x='200' y='{y}' width='{300 - (i % 3) * 50}' height='14' rx='7' fill='#e6e0f7'/>"
        art += f"<rect x='200' y='{y + 20}' width='{220 - (i % 2) * 60}' height='10' rx='5' fill='#f0ecfa'/>"
    art += "<rect x='598' y='96' width='16' height='270' rx='8' fill='#eeeaf9'/><rect x='598' y='236' width='16' height='70' rx='8' fill='#6a4be0'/>"
    art += ("<path d='M624,270 C700,270 700,84 454,84' stroke='#ffffff' stroke-width='3' fill='none' stroke-dasharray='6 8'/>"
            "<polygon points='462,76 448,84 462,92' fill='#fff'/>")
    for i, x in enumerate((220, 330, 440, 550)):
        art += f"<rect x='{x - 8}' y='{396 - 8}' width='16' height='16' rx='3' transform='rotate(45 {x} 396)' fill='{'#ffffff' if i < 3 else '#ffffff55'}'/>"
    art += "<rect x='220' y='394' width='330' height='4' rx='2' fill='#ffffff55'/>"
    return page(w, h, svg(w, h, art, defs))


def raindrop_5(w, h):
    """SwiftData: three model cards linked to a glowing database cylinder."""
    defs = (lin("bg", [(0, "#101a24"), (1, "#18303a")], 1, 1) + lin("cyl", [(0, "#1fbfae"), (0.5, "#6ff0dc"), (1, "#128c80")], 1, 0)
            + blur("b", 24) + shadow("sh", 10, 14, .45))
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    models = [(70, 40, "Trip", ["name", "start", "places"]), (70, 230, "Place", ["title", "coord", "notes"]),
              (300, 135, "Note", ["body", "created"])]
    for x, y, name, props in models:
        hh = 58 + 30 * len(props)
        art += f"<g filter='url(#sh)'><rect x='{x}' y='{y}' width='190' height='{hh}' rx='14' fill='#1f2e3a'/></g>"
        art += f"<rect x='{x}' y='{y}' width='190' height='44' rx='14' fill='#27414d'/><rect x='{x}' y='{y + 30}' width='190' height='14' fill='#27414d'/>"
        art += text(x + 18, y + 29, "@Model " + name, 17, "#6ff0dc", MONO, 700)
        for k, pr in enumerate(props):
            art += text(x + 18, y + 72 + k * 30, pr, 16, "#b9cbd3", MONO, 400)
            art += f"<rect x='{x + 120}' y='{y + 60 + k * 30}' width='50' height='14' rx='7' fill='#34505c'/>"
    art += ("<path d='M260,90 C300,90 280,170 300,170' stroke='#6ff0dc88' stroke-width='3' fill='none'/>"
            "<path d='M260,290 C300,290 280,240 300,240' stroke='#6ff0dc88' stroke-width='3' fill='none'/>"
            "<path d='M490,200 C540,200 540,210 580,210' stroke='#6ff0dc' stroke-width='4' fill='none'/>"
            "<path d='M165,164 L165,226' stroke='#6ff0dc88' stroke-width='3' stroke-dasharray='5 6'/>")
    art += "<ellipse cx='660' cy='210' rx='110' ry='130' fill='#1fbfae' opacity='.28' filter='url(#b)'/>"
    art += ("<path d='M590,110 L590,300 A70,22 0 0 0 730,300 L730,110 Z' fill='url(#cyl)'/>"
            "<ellipse cx='660' cy='110' rx='70' ry='22' fill='#a8fff0'/>"
            "<path d='M590,173 A70,22 0 0 0 730,173 M590,236 A70,22 0 0 0 730,236' stroke='#0f5c55' stroke-width='3' fill='none' opacity='.6'/>")
    return page(w, h, svg(w, h, art, defs))


# ── Notion page covers (900×360, no words) ────────────────────────────────

def notion_0(w, h):
    """Roadmap: lanes with rounded milestone bars on a calm gradient."""
    defs = lin("bg", [(0, "#dfe9fb"), (1, "#efe4fa")], 1, 0.4)
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    bars = [[(60, 260, "#8fb0f2"), (300, 520, "#8fb0f2"), (560, 640, "#8fb0f2")],
            [(140, 380, "#b39af0"), (430, 760, "#b39af0")],
            [(40, 160, "#f2a4c2"), (200, 330, "#f2a4c2"), (380, 600, "#f2a4c2"), (650, 860, "#f2a4c2")],
            [(240, 700, "#8fd6c2")]]
    for i, lane in enumerate(bars):
        y = 50 + i * 72
        art += f"<rect x='0' y='{y - 10}' width='{w}' height='56' fill='#ffffff' opacity='{0.35 if i % 2 == 0 else 0.15}'/>"
        for a, b, c in lane:
            art += f"<rect x='{a}' y='{y}' width='{b - a}' height='36' rx='18' fill='{c}'/>"
            art += f"<circle cx='{b - 18}' cy='{y + 18}' r='7' fill='#ffffff'/>"
    art += "<line x1='470' y1='20' x2='470' y2='340' stroke='#4b5fa8' stroke-width='3' stroke-dasharray='6 8' stroke-linecap='round'/>"
    art += "<circle cx='470' cy='20' r='9' fill='#4b5fa8'/>"
    for x, y in ((720, 30), (300, 332)):
        art += f"<rect x='{x - 10}' y='{y - 10}' width='20' height='20' rx='4' transform='rotate(45 {x} {y})' fill='#4b5fa8'/>"
    return page(w, h, svg(w, h, art, defs))


def notion_3(w, h):
    """Trip plan: a pastel map of Lisbon's river edge, a bridge, a walking route."""
    rng = random.Random(33)
    art = f"<rect width='{w}' height='{h}' fill='#f7eadb'/>"
    for _ in range(46):
        x, y = rng.uniform(0, w), rng.uniform(0, 220)
        c = rng.choice(["#f4d3c4", "#f1dcc2", "#e9d6e4", "#f6e2b8", "#dfe6cf"])
        art += f"<rect x='{x:.0f}' y='{y:.0f}' width='{rng.uniform(40, 110):.0f}' height='{rng.uniform(26, 60):.0f}' rx='6' fill='{c}' transform='rotate({rng.uniform(-18, 18):.0f} {x:.0f} {y:.0f})'/>"
    art += "<path d='M0,220 C180,190 300,250 470,226 C640,202 760,250 900,230 L900,360 L0,360 Z' fill='#a9cfe6'/>"
    art += "<path d='M0,238 C180,208 300,268 470,244 C640,220 760,268 900,248' stroke='#c7e2f1' stroke-width='5' fill='none'/>"
    # the bridge: a deck across the river, two towers, sagging main cables
    deck = [(560, 212), (720, 360)]
    art += f"<path d='M{deck[0][0]},{deck[0][1]} L{deck[1][0]},{deck[1][1]}' stroke='#c9442c' stroke-width='9' stroke-linecap='round'/>"
    tops = []
    for t in (0.3, 0.72):
        x, y = 560 + 160 * t, 212 + 148 * t
        art += f"<rect x='{x - 5:.0f}' y='{y - 62:.0f}' width='10' height='66' rx='3' fill='#c9442c'/>"
        tops.append((x, y - 60))
    (ax, ay), (bx, by) = tops
    art += (f"<path d='M{deck[0][0]},{deck[0][1]} Q{(deck[0][0] + ax) / 2:.0f},{ay + 40:.0f} {ax:.0f},{ay:.0f} "
            f"Q{(ax + bx) / 2:.0f},{(ay + by) / 2 + 70:.0f} {bx:.0f},{by:.0f} Q{(bx + 740) / 2:.0f},{by + 60:.0f} 740,380' "
            "stroke='#e2553a' stroke-width='3' fill='none'/>")
    art += "<path d='M140,160 C200,110 260,140 300,90 C330,56 380,70 420,50' stroke='#5a6fb0' stroke-width='5' fill='none' stroke-dasharray='2 12' stroke-linecap='round'/>"
    art += "<circle cx='140' cy='160' r='10' fill='#5a6fb0'/><circle cx='420' cy='50' r='12' fill='#f2b632' stroke='#fff' stroke-width='4'/>"
    art += "<path d='M60,200 C140,150 240,200 330,176' stroke='#f2b632' stroke-width='6' fill='none' opacity='.8'/>"
    for x, y in ((230, 300), (330, 320), (780, 300)):
        art += f"<path d='M{x - 18},{y} L{x + 18},{y} L{x + 10},{y + 8} L{x - 10},{y + 8} Z' fill='#ffffff' opacity='.8'/>"
    return page(w, h, svg(w, h, art))


def notion_6(w, h):
    """Hiring loop: a loop of connected circles in soft colours."""
    defs = lin("bg", [(0, "#e3f3ec"), (1, "#e2ecfb")], 1, 0) + shadow("sh", 8, 10, .14, "#2a4a60")
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    cx, cy, rx, ry = 450, 180, 290, 110
    art += f"<ellipse cx='{cx}' cy='{cy}' rx='{rx}' ry='{ry}' fill='none' stroke='#9fb7c9' stroke-width='5' stroke-dasharray='1 14' stroke-linecap='round'/>"
    cols = ["#f3a5a0", "#f6c77a", "#9ed3a8", "#8fc1ec", "#b8a4ee"]
    for i, c in enumerate(cols):
        t = -math.pi / 2 + i * 2 * math.pi / 5
        x, y = cx + rx * math.cos(t), cy + ry * math.sin(t)
        t2 = t + math.pi / 5
        ax, ay = cx + rx * math.cos(t2), cy + ry * math.sin(t2)
        dx, dy = -rx * math.sin(t2), ry * math.cos(t2)
        n = math.hypot(dx, dy)
        dx, dy = dx / n, dy / n
        art += f"<polygon points='{pts([(ax + dx * 12, ay + dy * 12), (ax - dx * 8 - dy * 10, ay - dy * 8 + dx * 10), (ax - dx * 8 + dy * 10, ay - dy * 8 - dx * 10)])}' fill='#7d97ad'/>"
        r = 46 if i == 0 else 40
        art += f"<g filter='url(#sh)'><circle cx='{x:.0f}' cy='{y:.0f}' r='{r}' fill='#ffffff'/></g>"
        art += f"<circle cx='{x:.0f}' cy='{y:.0f}' r='{r - 10}' fill='{c}'/>"
        art += f"<circle cx='{x:.0f}' cy='{y - 6:.0f}' r='9' fill='#ffffff' opacity='.85'/><path d='M{x - 15:.0f},{y + 18:.0f} Q{x:.0f},{y - 2:.0f} {x + 15:.0f},{y + 18:.0f}' fill='#ffffff' opacity='.85'/>"
    art += f"<circle cx='{cx}' cy='{cy}' r='26' fill='#ffffff' opacity='.7'/><path d='M{cx - 10},{cy} L{cx - 2},{cy + 9} L{cx + 12},{cy - 9}' stroke='#5fa97a' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>"
    return page(w, h, svg(w, h, art, defs))


def notion_9(w, h):
    """Recipes: a flat lay of herbs, lemons and a bowl on linen."""
    defs = (rad("lem", [(0, "#fff3a0"), (1, "#f2c31e")], 0.4, 0.35, 0.7) + rad("bowl", [(0, "#ffffff"), (1, "#e7e2d8")])
            + shadow("sh", 8, 8, .22, "#5a4a30"))
    art = f"<rect width='{w}' height='{h}' fill='#efe8dc'/>"

    def sprig(x, y, rot, n, leaf):
        s = f"<g transform='translate({x} {y}) rotate({rot})' filter='url(#sh)'><path d='M0,0 L{n * 22},0' stroke='#4d6b3a' stroke-width='3'/>"
        for i in range(1, n):
            s += (f"<ellipse cx='{i * 22}' cy='-12' rx='{leaf}' ry='{leaf * 0.45:.1f}' fill='#5f8f45' transform='rotate(-35 {i * 22} -12)'/>"
                  f"<ellipse cx='{i * 22 + 8}' cy='12' rx='{leaf}' ry='{leaf * 0.45:.1f}' fill='#6fa352' transform='rotate(35 {i * 22 + 8} 12)'/>")
        return s + "</g>"
    art += sprig(40, 90, 20, 8, 16) + sprig(610, 300, -28, 7, 13) + sprig(780, 40, 70, 6, 18)
    art += ("<g filter='url(#sh)'><circle cx='450' cy='180' r='128' fill='url(#bowl)'/></g>"
            "<circle cx='450' cy='180' r='110' fill='#2f5d8a'/><circle cx='450' cy='180' r='100' fill='#e9dcc0'/>")
    rng = random.Random(9)
    for _ in range(22):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(0, 80)
        art += f"<circle cx='{450 + r * math.cos(a):.0f}' cy='{180 + r * math.sin(a):.0f}' r='{rng.uniform(8, 14):.0f}' fill='{rng.choice(['#d9b56a', '#c99a4f', '#e8c98a', '#7aa05a'])}'/>"
    art += "<g filter='url(#sh)'><ellipse cx='220' cy='250' rx='62' ry='50' fill='url(#lem)' transform='rotate(-20 220 250)'/></g>"
    art += ("<g filter='url(#sh)'><circle cx='700' cy='150' r='56' fill='#f2c31e'/></g><circle cx='700' cy='150' r='48' fill='#fff6c9'/>")
    for i in range(8):
        a = i * math.pi / 4
        art += f"<path d='M700,150 L{700 + 44 * math.cos(a):.1f},{150 + 44 * math.sin(a):.1f}' stroke='#f2d25a' stroke-width='3'/>"
    art += "<circle cx='700' cy='150' r='6' fill='#fff6c9'/>"
    for x, y in ((150, 60), (170, 44), (330, 320), (560, 60), (578, 76), (820, 250), (840, 270), (300, 40)):
        art += f"<circle cx='{x}' cy='{y}' r='5' fill='#3a2e26'/>"
    art += ("<g filter='url(#sh)' transform='rotate(-12 330 300)'><rect x='240' y='294' width='150' height='12' rx='6' fill='#c9955c'/>"
            "<ellipse cx='400' cy='300' rx='30' ry='20' fill='#c9955c'/></g>")
    return page(w, h, svg(w, h, art, defs))


# ── Book covers (400×600) ─────────────────────────────────────────────────
# Made covers, never the real jackets: each sets its title and author in type
# over a motif of its own, in a palette of its own.

BASKERVILLE = "Baskerville, 'New York', Georgia, serif"
GILL = "'Gill Sans', 'Avenir Next', system-ui, sans-serif"
FUTURA = "Futura, 'Avenir Next', system-ui, sans-serif"


def cover_state(w, h):
    """Seeing Like a State: an old town's crooked blocks, and a surveyor's
    straight red grid laid over them."""
    paper, ink, red = "#efe6d2", "#2b2620", "#b8322a"
    art = f"<rect width='{w}' height='{h}' fill='{paper}'/>"
    defs = "<clipPath id='plan'><rect x='36' y='40' width='328' height='328'/></clipPath>"
    rng = random.Random(41)
    n = 8
    step = 328 / (n - 1)

    def warp(x, y):  # the old town's lanes bend with the ground, not the survey
        return (x + 16 * math.sin(y / 46 + 0.6) + rng.uniform(-6, 6),
                y + 14 * math.sin(x / 52 + 1.9) + rng.uniform(-6, 6))
    grid = [[warp(36 + i * step, 40 + j * step) for i in range(n)] for j in range(n)]
    plan = f"<rect x='36' y='40' width='328' height='328' fill='{paper}'/>"
    for j in range(n - 1):
        for i in range(n - 1):
            q = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            cx = sum(p[0] for p in q) / 4
            cy = sum(p[1] for p in q) / 4
            q = [(cx + (x - cx) * 0.86, cy + (y - cy) * 0.86) for x, y in q]
            # each edge bends once, so the lanes between blocks wander
            ring = []
            for a, b in zip(q, q[1:] + q[:1]):
                ring.append(a)
                ring.append(((a[0] + b[0]) / 2 + rng.uniform(-5, 5), (a[1] + b[1]) / 2 + rng.uniform(-5, 5)))
            plan += f"<polygon points='{pts(ring)}' fill='{ink}' opacity='{rng.uniform(0.62, 0.86):.2f}' stroke='{ink}' stroke-opacity='.2' stroke-width='1.5' stroke-linejoin='round'/>"
    plan += f"<circle cx='200' cy='204' r='22' fill='{paper}'/>"  # a market square
    lines = ""
    for k in range(0, 5):
        v = 36 + k * 82
        lines += (f"<path d='M{v},40 L{v},368' stroke='{red}' stroke-width='4'/>"
                  f"<path d='M36,{v + 4} L364,{v + 4}' stroke='{red}' stroke-width='4'/>")
    marks = "".join(f"<path d='M{36 + i * 82 - 6},{44 + j * 82} l12,0 M{36 + i * 82},{38 + j * 82} l0,12' stroke='{paper}' stroke-width='3'/>"
                    for i in range(5) for j in range(5))
    art += f"<g clip-path='url(#plan)'>{plan}{lines}{marks}</g>"
    art += text(36, 446, "Seeing Like", 46, ink, BASKERVILLE, 700)
    art += text(36, 496, "a State", 46, ink, BASKERVILLE, 700)
    art += f"<rect x='36' y='520' width='48' height='4' fill='{red}'/>"
    art += text(36, 560, "James C. Scott", 20, ink, BASKERVILLE, 400)
    return page(w, h, svg(w, h, art, defs), paper)


def cover_timeless(w, h):
    """The Timeless Way of Building: one gabled house and the path to its door,
    repeated quietly as a pattern behind."""
    ground, cream, deep = "#b65a34", "#f6e8d2", "#7a3520"
    art = f"<rect width='{w}' height='{h}' fill='{ground}'/>"

    def house(x, y, s, fill, stroke=None, sw=0):
        st = f"stroke='{stroke}' stroke-width='{sw}' stroke-linejoin='round'" if stroke else ""
        return f"<path d='M{x - 20 * s},{y} L{x - 20 * s},{y - 22 * s} L{x},{y - 40 * s} L{x + 20 * s},{y - 22 * s} L{x + 20 * s},{y} Z' fill='{fill}' {st}/>"

    for j in range(8):  # the pattern: small houses in staggered rows
        for i in range(6):
            x = 20 + i * 72 + (36 if j % 2 else 0)
            y = 60 + j * 64
            art += house(x, y, 0.62, "#c46d44")
    # the motif: a house, its door, a winding path of stepping stones
    art += f"<rect x='60' y='60' width='280' height='300' fill='{ground}'/>"
    art += f"<rect x='60' y='60' width='280' height='300' fill='none' stroke='{cream}' stroke-width='3'/>"
    art += house(200, 230, 3.2, cream)
    art += f"<rect x='186' y='184' width='28' height='46' rx='14' fill='{deep}'/>"
    art += f"<rect x='150' y='150' width='22' height='22' fill='{deep}'/><rect x='228' y='150' width='22' height='22' fill='{deep}'/>"
    art += f"<circle cx='200' cy='124' r='9' fill='{deep}'/>"
    stones = [(200, 248, 16), (188, 272, 15), (204, 296, 14), (226, 316, 13), (246, 334, 12)]
    for x, y, r in stones:
        art += f"<ellipse cx='{x}' cy='{y}' rx='{r}' ry='{r * 0.5:.1f}' fill='{cream}'/>"
    art += f"<path d='M84,230 L316,230' stroke='{cream}' stroke-width='3'/>"
    art += f"<rect x='40' y='392' width='320' height='170' fill='{ground}'/>"
    art += text(200, 432, "The Timeless Way", 34, cream, GILL, 600, "middle")
    art += text(200, 474, "of Building", 34, cream, GILL, 600, "middle")
    art += f"<circle cx='200' cy='504' r='4' fill='{cream}'/>"
    art += text(200, 546, "Christopher Alexander", 21, cream, GILL, 400, "middle")
    return page(w, h, svg(w, h, art), ground)


def cover_systems(w, h):
    """Thinking in Systems: a tank (the stock), a tap filling it, a drain
    emptying it, and the loop arrow that feeds back to the tap."""
    bg, ink, acc, water = "#dcefe6", "#163c45", "#f07a3a", "#5fb7c9"
    art = f"<rect width='{w}' height='{h}' fill='{bg}'/>"
    art += text(36, 92, "Thinking", 56, ink, FUTURA, 700)
    art += text(36, 150, "in Systems", 56, ink, FUTURA, 700)
    # the inflow: a pipe and a tap, a stream falling into the tank
    art += f"<path d='M36,236 L170,236' stroke='{ink}' stroke-width='16'/>"
    art += (f"<path d='M118,220 L138,236 L118,252 Z M158,220 L138,236 L158,252 Z' fill='{ink}'/>"
            f"<path d='M138,236 L138,206' stroke='{ink}' stroke-width='6'/><rect x='122' y='198' width='32' height='10' rx='5' fill='{acc}'/>"
            f"<path d='M170,236 Q186,236 186,254' stroke='{ink}' stroke-width='16' fill='none'/>"
            f"<rect x='180' y='262' width='12' height='60' rx='6' fill='{water}'/>")
    # the stock
    art += (f"<rect x='120' y='272' width='160' height='170' rx='10' fill='#ffffff' stroke='{ink}' stroke-width='8'/>"
            f"<path d='M128,348 Q160,340 200,348 T272,348 L272,432 Q272,436 266,436 L134,436 Q128,436 128,432 Z' fill='{water}'/>")
    # the outflow
    art += (f"<path d='M280,412 L364,412' stroke='{ink}' stroke-width='16'/>"
            f"<path d='M312,396 L332,412 L312,428 Z M352,396 L332,412 L352,428 Z' fill='{ink}'/>"
            f"<path d='M332,412 L332,382' stroke='{ink}' stroke-width='6'/>")
    # the loop: from the stock's level back to the inflow tap
    art += (f"<path d='M290,330 C350,300 350,190 240,184 C190,182 160,186 146,196' stroke='{acc}' stroke-width='7' fill='none' stroke-linecap='round'/>"
            f"<polygon points='140,190 154,206 160,186' fill='{acc}'/>")
    art += f"<rect x='36' y='496' width='56' height='6' rx='3' fill='{acc}'/>"
    art += text(36, 548, "Donella Meadows", 24, ink, FUTURA, 500)
    return page(w, h, svg(w, h, art), bg)


# ── dispatch ──────────────────────────────────────────────────────────────

DRAW = {
    "yt-0": yt_0, "yt-1": yt_1, "yt-2": yt_2, "yt-3": yt_3,
    "yt-4": yt_4, "yt-5": yt_5, "yt-6": yt_6, "yt-7": yt_7,
    "substack-0": substack_0, "substack-1": substack_1, "substack-2": substack_2,
    "substack-3": substack_3, "substack-4": substack_4, "substack-5": substack_5,
    "rss-0": rss_0, "rss-1": rss_1, "rss-2": rss_2, "rss-3": rss_3,
    "rss-4": rss_4, "rss-5": rss_5, "rss-6": rss_6,
    "bsky-link-0": bsky_link_0,
    "raindrop-0": raindrop_0, "raindrop-0b": raindrop_0b, "raindrop-1": raindrop_1,
    "raindrop-2": raindrop_2, "raindrop-3": raindrop_3, "raindrop-3b": raindrop_3b,
    "raindrop-4": raindrop_4, "raindrop-5": raindrop_5,
    "notion-0": notion_0, "notion-3": notion_3, "notion-6": notion_6, "notion-9": notion_9,
    "cover-state": cover_state, "cover-timeless": cover_timeless, "cover-systems": cover_systems,
}


def html(p):
    w, h = p["size"]
    return DRAW[p["key"]](w, h)
