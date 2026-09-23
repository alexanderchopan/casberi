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


def yt_1(w, h):
    """Hoffmann: a puck in a basket, cut away, under warm studio light."""
    defs = (rad("bg", [(0, "#5a3521"), (0.55, "#26150c"), (1, "#0d0704")], 0.35, 0.45, 0.8)
            + lin("steel", [(0, "#6b6b6e"), (0.25, "#e9e9ea"), (0.5, "#9a9a9d"), (0.8, "#d7d7d9"), (1, "#5c5c60")], 1, 0)
            + lin("puck", [(0, "#8a5a36"), (0.5, "#5b3620"), (1, "#3a2213")])
            + lin("water", [(0, "#8fd3ff"), (1, "#8fd3ff00")])
            + lin("shot", [(0, "#c7843f"), (1, "#5a2e10")])
            + shadow("sh", 16, 18, .5))
    bg = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    glow = "<ellipse cx='250' cy='210' rx='260' ry='170' fill='#ffb06633' filter='url(#b)'/>"
    cx = 250
    handle = (f"<g filter='url(#sh)'><path d='M{cx - 150},222 L{cx - 212},252' stroke='url(#steel)' stroke-width='26'/>"
              f"<path d='M{cx - 200},246 L{cx - 236},264' stroke='#1c110a' stroke-width='38' stroke-linecap='round'/>"
              f"<path d='M{cx - 204},240 L{cx - 232},254' stroke='#5a3a26' stroke-width='6' stroke-linecap='round'/></g>")
    basket = (f"<g filter='url(#sh)'><path d='M{cx - 150},150 L{cx + 150},150 L{cx + 128},292 Q{cx},312 {cx - 128},292 Z' fill='url(#steel)'/>"
              f"<path d='M{cx - 134},168 L{cx + 134},168 L{cx + 116},282 Q{cx},298 {cx - 116},282 Z' fill='#2a1a10'/>"
              f"<path d='M{cx - 132},196 L{cx + 132},196 L{cx + 116},282 Q{cx},298 {cx - 116},282 Z' fill='url(#puck)'/>")
    layers = "".join(f"<path d='M{cx - 128 + i * 2},{214 + i * 18} L{cx + 128 - i * 2},{214 + i * 18}' stroke='#00000026' stroke-width='3'/>" for i in range(4))
    basket += layers + "</g>"
    arrows = ""
    for i, x in enumerate(range(cx - 100, cx + 101, 50)):
        arrows += (f"<rect x='{x - 5}' y='{58 + (i % 2) * 10}' width='10' height='82' rx='5' fill='url(#water)' transform='rotate(180 {x} 104)'/>"
                   f"<path d='M{x - 14},160 L{x},182 L{x + 14},160' fill='#8fd3ff'/>")
    drips = (f"<path d='M{cx - 30},306 C{cx - 30},340 {cx - 24},370 {cx - 26},420' stroke='url(#shot)' stroke-width='10' fill='none' stroke-linecap='round'/>"
             f"<path d='M{cx + 30},306 C{cx + 30},340 {cx + 24},370 {cx + 26},420' stroke='url(#shot)' stroke-width='10' fill='none' stroke-linecap='round'/>")
    words = (text(468, 138, "WHY", 56, "#f5e6d3", HEAVY, 700)
             + text(462, 256, "9 BAR", 98, "#ffb366", HEAVY, 800)
             + text(468, 312, "and not 12?", 40, "#f5e6d3", HEAVY, 500)
             + "<rect x='470' y='336' width='90' height='8' rx='4' fill='#ffb366'/>")
    return page(w, h, svg(w, h, bg + glow + handle + arrows + basket + drips + words, defs + blur("b", 40)), "#120a06")


def yt_4(w, h):
    """Hoffmann: three grinders on a studio sweep, a particle chart above."""
    defs = (lin("sweep", [(0, "#f3ebe0"), (0.62, "#e6d8c6"), (1, "#cdb89f")])
            + lin("blk", [(0, "#3a3a3c"), (0.4, "#1d1d1f"), (1, "#0e0e10")], 1, 0)
            + lin("stl", [(0, "#8d8f93"), (0.35, "#f1f1f2"), (0.7, "#a9abaf"), (1, "#6f7175")], 1, 0)
            + lin("wht", [(0, "#ffffff"), (0.7, "#ece8e2"), (1, "#cfc9c0")], 1, 0)
            + lin("hop", [(0, "#ffffffaa"), (1, "#ffffff22")], 1, 0)
            + shadow("card", 8, 12, .18) + blur("b", 10))
    bg = f"<rect width='{w}' height='{h}' fill='url(#sweep)'/>"
    shadows = "".join(f"<ellipse cx='{x}' cy='418' rx='{r}' ry='12' fill='#6b523a55' filter='url(#b)'/>" for x, r in ((150, 80), (395, 60), (620, 90)))
    g1 = ("<rect x='95' y='240' width='110' height='175' rx='14' fill='url(#blk)'/>"
          "<path d='M105,240 L90,178 L210,178 L195,240 Z' fill='url(#hop)' stroke='#ffffff66' stroke-width='2'/>"
          "<rect x='84' y='166' width='132' height='15' rx='6' fill='#1d1d1f'/>"
          "<circle cx='150' cy='300' r='20' fill='#2c2c2e' stroke='#555' stroke-width='3'/>"
          "<rect x='120' y='360' width='60' height='40' rx='4' fill='#111'/>")
    g2 = ("<rect x='355' y='210' width='80' height='205' rx='40' fill='url(#stl)'/>"
          "<rect x='392' y='175' width='6' height='40' fill='#6f7175'/>"
          "<rect x='395' y='172' width='80' height='10' rx='5' fill='#6f7175'/>"
          "<circle cx='478' cy='177' r='14' fill='#7a4a2a'/>"
          "<rect x='355' y='300' width='80' height='10' fill='#00000018'/>")
    g3 = ("<path d='M540,415 L540,300 Q540,270 570,270 L670,270 Q700,270 700,300 L700,415 Z' fill='url(#wht)'/>"
          "<rect x='565' y='240' width='110' height='36' rx='12' fill='#e2ddd5'/>"
          "<circle cx='620' cy='258' r='8' fill='#e0662d'/>"
          "<rect x='590' y='330' width='60' height='60' rx='10' fill='#2a2522'/>")
    chart = "<g filter='url(#card)'><rect x='548' y='24' width='222' height='124' rx='16' fill='#fffdf9'/></g>"
    for col, mu, sd, amp in (("#1d1d1f", 62, 24, 58), ("#8a8d92", 96, 16, 76), ("#e0662d", 134, 13, 84)):
        ps = [(564 + x, 128 - amp * math.exp(-((x - mu) ** 2) / (2 * sd * sd))) for x in range(0, 191, 5)]
        chart += f"<polyline points='{pts(ps)}' fill='none' stroke='{col}' stroke-width='4' stroke-linejoin='round'/>"
    chart += "<rect x='564' y='128' width='190' height='3' rx='1.5' fill='#d8cfc4'/>"
    words = text(40, 90, "MEASURED.", 76, "#241a12", HEAVY, 800)
    words += text(44, 134, "3 grinders · 1 laser", 28, "#8a5a36", HEAVY, 600)
    return page(w, h, svg(w, h, bg + shadows + g1 + g2 + g3 + chart + words, defs), "#efe6da")


def yt_6(w, h):
    """Hoffmann: a filter cone and an espresso cup on two grounds, split."""
    defs = (lin("cone", [(0, "#ffffff"), (0.6, "#f1eee9"), (1, "#d5d0c8")], 1, 0)
            + lin("glass", [(0, "#ffffff55"), (1, "#ffffff18")], 1, 0)
            + lin("brew", [(0, "#b0652a"), (1, "#6c3714")])
            + lin("cup", [(0, "#fbfaf7"), (0.7, "#ece7df"), (1, "#c9c1b5")], 1, 0)
            + shadow("sh", 14, 14, .3))
    bg = (f"<rect width='{w}' height='{h}' fill='#9fb59a'/>"
          f"<polygon points='430,0 {w},0 {w},{h} 350,{h}' fill='#c8643c'/>")
    cone = ("<g filter='url(#sh)'>"
            "<path d='M120,300 L128,410 Q190,432 252,410 L260,300 Z' fill='url(#glass)' stroke='#ffffff99' stroke-width='3'/>"
            "<path d='M132,360 L134,408 Q190,428 246,408 L248,360 Z' fill='url(#brew)' opacity='.9'/>"
            "<path d='M95,160 L285,160 L215,292 L165,292 Z' fill='url(#cone)'/>"
            "<rect x='88' y='150' width='204' height='18' rx='9' fill='#fff'/>"
            "<rect x='150' y='286' width='80' height='16' rx='6' fill='#e7e2da'/></g>")
    ribs = "".join(f"<path d='M{120 + i * 28},172 L{172 + i * 9},284' stroke='#00000012' stroke-width='3'/>" for i in range(6))
    cup = ("<g filter='url(#sh)'>"
           "<ellipse cx='600' cy='392' rx='130' ry='26' fill='#f3efe8'/>"
           "<path d='M520,300 L528,372 Q600,404 672,372 L680,300 Z' fill='url(#cup)'/>"
           "<path d='M678,318 C730,316 730,366 670,362' stroke='#e9e3da' stroke-width='14' fill='none'/>"
           "<ellipse cx='600' cy='300' rx='80' ry='18' fill='#f7f4ef'/>"
           "<ellipse cx='600' cy='302' rx='70' ry='13' fill='#c98a4f'/>"
           "<ellipse cx='590' cy='300' rx='30' ry='5' fill='#e6b98a'/></g>")
    words = (poster(40, 84, ["FILTER"], 70, "#fff", "#46603f", HEAVY, 800, sw=8)
             + poster(760, 84, ["ESPRESSO"], 70, "#fff", "#7b3016", HEAVY, 800, anchor="end", sw=8)
             + "<g transform='translate(400 215)'><circle r='44' fill='#fff'/>"
             "<path d='M-20,0 L18,0 M4,-16 L20,0 L4,16' stroke='#2a2a2a' stroke-width='8' fill='none' stroke-linecap='round' stroke-linejoin='round'/></g>")
    return page(w, h, svg(w, h, bg + ribs + cone + cup + words, defs), "#9fb59a")


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
    """Inside a very small compiler: an isometric machine, tokens in, a tree out."""
    P = iso(420, 228, 26)
    art = f"<rect width='{w}' height='{h}' fill='#cfe9dc'/>"
    art += iso_box(P, -9, -3, -1, 18, 8, 1, "#b7dac8", "#9cc7b1", "#8bb9a2")
    art += iso_box(P, -8, -1, 0, 7, 3, 0.4, "#2d3b55", "#243049", "#1c263b")
    for i, c in enumerate(("#ef8a3c", "#f2c14e", "#5fb3e8", "#ef8a3c")):
        art += iso_box(P, -8 + i * 1.7, -0.2, 0.4, 1.1, 1.1, 1.1, c, c + "cc", c + "99")
    art += iso_box(P, -1.5, -2, 0, 5, 5, 4.2, "#f6f1e6", "#e0d6c3", "#cbbfa8")
    art += iso_box(P, -0.5, -1, 4.2, 3, 3, 0.8, "#ef8a3c", "#d27228", "#bb621c")
    for k in range(3):
        a = P(-1.5 + 1 + k * 1.4, 3, 3)
        art += f"<circle cx='{a[0]:.1f}' cy='{a[1]:.1f}' r='6' fill='#2d3b55'/>"
    art += iso_box(P, 3.5, -1, 0, 5, 3, 0.4, "#2d3b55", "#243049", "#1c263b")
    root = P(6.8, 0.5, 5.4)
    kids = [P(5.3, 0.5, 3.4), P(8.3, 0.5, 3.4)]
    leaves = [P(4.6, 0.5, 1.5), P(6.0, 0.5, 1.5), P(8.6, 0.5, 1.5)]
    for a, b in ((root, kids[0]), (root, kids[1]), (kids[0], leaves[0]), (kids[0], leaves[1]), (kids[1], leaves[2])):
        art += f"<line x1='{a[0]:.1f}' y1='{a[1]:.1f}' x2='{b[0]:.1f}' y2='{b[1]:.1f}' stroke='#2d3b55' stroke-width='4'/>"
    for (x, y), c, r in ([(root, "#ef8a3c", 15)] + [(k, "#5fb3e8", 12) for k in kids] + [(l, "#f2c14e", 10) for l in leaves]):
        art += f"<circle cx='{x:.1f}' cy='{y:.1f}' r='{r}' fill='{c}' stroke='#2d3b55' stroke-width='3'/>"
    puff = P(0.5, 0.5, 6.4)
    art += "".join(f"<circle cx='{puff[0] + dx:.0f}' cy='{puff[1] - dy:.0f}' r='{r}' fill='#ffffff' opacity='.8'/>"
                   for dx, dy, r in ((0, 0, 9), (14, 20, 12), (4, 44, 15)))
    return page(w, h, svg(w, h, art))


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
    """Type systems, plainly: a wooden shape sorter seen from above."""
    defs = (lin("wood", [(0, "#e6b77e"), (1, "#c98f52")], 1, 1) + shadow("sh", 10, 8, .28, "#4a2c10") + blur("sf", 8))
    art = f"<rect width='{w}' height='{h}' fill='#efe4d2'/>"
    art += "<g filter='url(#sh)'><rect x='250' y='80' width='300' height='300' rx='28' fill='url(#wood)'/></g>"
    art += "<rect x='262' y='92' width='276' height='276' rx='20' fill='none' stroke='#ffffff40' stroke-width='3'/>"
    star = [(472 + (42 if i % 2 == 0 else 19) * math.sin(i * math.pi / 5), 298 - (42 if i % 2 == 0 else 19) * math.cos(i * math.pi / 5)) for i in range(10)]
    holes = {"c": "<circle cx='330' cy='160' r='40'/>", "s": "<rect x='432' y='120' width='80' height='80' rx='6'/>",
             "t": "<polygon points='330,258 376,338 284,338'/>", "st": f"<polygon points='{pts(star)}'/>"}
    for k, shape in holes.items():
        # a hole with a wall: dark, and the far wall's lit edge showing at its foot
        defs += f"<clipPath id='h{k}'>{shape}</clipPath>"
        art += f"<g fill='#2e1a08'>{shape}</g>"
        art += f"<g clip-path='url(#h{k})'><g transform='translate(0 16)' fill='#6b4220'>{shape}</g></g>"
    art += "<g filter='url(#sh)'>"
    art += "<circle cx='140' cy='290' r='38' fill='#e2553a'/><circle cx='130' cy='280' r='12' fill='#ffffff33'/>"
    art += "<polygon points='670,90 716,170 624,170' fill='#1bb58a' transform='rotate(12 670 140)'/>"
    star2 = [(x + 220, y + 40) for x, y in star]
    art += f"<polygon points='{pts(star2)}' fill='#f2c14e' transform='rotate(18 692 338)'/>"
    art += "</g>"
    # the square, lifted, about to drop into its hole
    art += ("<rect x='452' y='150' width='80' height='80' rx='6' fill='#2a1a0a' opacity='.25' filter='url(#sf)'/>"
            "<rect x='440' y='112' width='80' height='80' rx='6' fill='#3b7bff' transform='rotate(8 480 152)'/>"
            "<rect x='440' y='112' width='80' height='14' rx='6' fill='#6a9bff' transform='rotate(8 480 152)'/>")
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
    """Local-first, one year on: a tree-ring slice with the newest ring lit."""
    defs = rad("wood", [(0, "#f3d6a8"), (1, "#d9a86c")], 0.5, 0.5, 0.6) + shadow("sh", 14, 16, .28, "#23321f")
    art = f"<rect width='{w}' height='{h}' fill='#a9bf9c'/>"
    art += "<circle cx='640' cy='80' r='120' fill='#b8cdab'/>"
    cx, cy = 390, 225
    rings = ""
    for k, r in enumerate(range(18, 176, 13)):
        ps = []
        for i in range(73):
            t = i / 72 * 2 * math.pi
            rr = r * (1 + 0.035 * math.sin(3 * t + k * 0.7) + 0.02 * math.cos(5 * t + k))
            ps.append((cx + rr * math.cos(t) * 1.02, cy + rr * math.sin(t)))
        d = "M" + " L".join(f"{a:.1f},{b:.1f}" for a, b in ps) + "Z"
        last = r + 13 >= 176
        rings += f"<path d='{d}' fill='none' stroke='{'#e2553a' if last else '#b37a45'}' stroke-width='{5 if last else 2.2}' opacity='{1 if last else 0.55}'/>"
    art += f"<g filter='url(#sh)'><ellipse cx='{cx}' cy='{cy}' rx='{190 * 1.02:.0f}' ry='190' fill='#8a5a33'/></g>"
    art += f"<ellipse cx='{cx}' cy='{cy}' rx='{178 * 1.02:.0f}' ry='178' fill='url(#wood)'/>" + rings
    art += f"<circle cx='{cx}' cy='{cy}' r='6' fill='#8a5a33'/>"
    art += ("<g transform='translate(640 330)'><path d='M0,40 L0,-6' stroke='#3f6b39' stroke-width='5' stroke-linecap='round'/>"
            "<path d='M0,4 C-30,-2 -38,-26 -34,-36 C-12,-34 0,-20 0,4Z' fill='#4f8a45'/>"
            "<path d='M0,-6 C24,-14 34,-40 30,-50 C8,-46 -2,-28 0,-6Z' fill='#6aa85a'/>"
            "<ellipse cx='0' cy='44' rx='36' ry='8' fill='#6b8a5e'/></g>")
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
    """swift-evolution: proposals as fanned cards with status chips."""
    defs = shadow("sh", 12, 14, .16, "#2a2a40")
    art = f"<rect width='{w}' height='{h}' fill='#ecebe7'/>"
    cards = [(-9, 130, 222, "SE-0412", "In review", "#f0a030"), (-2, 285, 182, "SE-0427", "Accepted", "#2fa56a"),
             (6, 440, 200, "SE-0431", "Implemented", "#3a7bd5")]
    for r, x, y, num, st, c in cards:
        cw = len(st) * 9.4 + 30
        art += (f"<g transform='rotate({r} {x + 120} {y})' filter='url(#sh)'>"
                f"<rect x='{x}' y='{y - 150}' width='240' height='300' rx='18' fill='#fff'/>"
                + text(x + 22, y - 110, num, 20, "#8a8a95", MONO, 600)
                + f"<rect x='{x + 22}' y='{y - 90}' width='180' height='16' rx='8' fill='#26262e'/>"
                + f"<rect x='{x + 22}' y='{y - 66}' width='130' height='16' rx='8' fill='#26262e'/>"
                + "".join(f"<rect x='{x + 22}' y='{y - 30 + k * 20}' width='{196 - (k % 3) * 34}' height='9' rx='4.5' fill='#e3e3e8'/>" for k in range(5))
                + f"<rect x='{x + 22}' y='{y + 94}' width='{cw:.0f}' height='32' rx='16' fill='{c}22'/>"
                + f"<circle cx='{x + 38}' cy='{y + 110}' r='5' fill='{c}'/>"
                + text(x + 50, y + 116, st, 15, c, SANS, 700)
                + "</g>")
    return page(w, h, svg(w, h, art, defs))


def raindrop_3(w, h):
    """Swift README: a terminal building a toolchain, floating on a warm dusk."""
    defs = lin("bg", [(0, "#3a1d5c"), (0.6, "#8a2f5a"), (1, "#d8653e")], 1, 1) + shadow("sh", 22, 26, .45, "#12051f")
    art = f"<rect width='{w}' height='{h}' fill='url(#bg)'/>"
    art += "<circle cx='690' cy='360' r='150' fill='#f39a5a' opacity='.25'/>"
    art += ("<g filter='url(#sh)'><rect x='110' y='50' width='580' height='320' rx='16' fill='#16121f'/></g>"
            "<rect x='110' y='50' width='580' height='38' rx='16' fill='#241e31'/><rect x='110' y='72' width='580' height='16' fill='#241e31'/>"
            "<circle cx='136' cy='69' r='7' fill='#ff5f57'/><circle cx='158' cy='69' r='7' fill='#febc2e'/><circle cx='180' cy='69' r='7' fill='#28c840'/>")
    lines = [("$ ", "#8be9a8", "utils/build-script --release", "#f2eefa"),
             ("", "", "-- Configuring toolchain", "#8f86a6"),
             ("[ 41%] ", "#f39a5a", "Building swift-frontend", "#f2eefa"),
             ("[ 58%] ", "#f39a5a", "Building stdlib (arm64)", "#f2eefa"),
             ("[ 73%] ", "#f39a5a", "Linking swift-driver", "#f2eefa")]
    y = 128
    for pre, pc, s, c in lines:
        art += f"<text x='134' y='{y}' font-family=\"{MONO}\" font-size='19'><tspan fill='{pc}'>{pre}</tspan><tspan fill='{c}'>{s}</tspan></text>"
        y += 34
    art += "<rect x='134' y='310' width='530' height='22' rx='5' fill='#2c2640'/><rect x='134' y='310' width='387' height='22' rx='5' fill='#f39a5a'/>"
    art += "<rect x='134' y='342' width='12' height='20' fill='#f2eefa'/>"
    return page(w, h, svg(w, h, art, defs))


def raindrop_3b(w, h):
    """Swift README, second image: a full-bleed light build log ending green."""
    art = f"<rect width='{w}' height='{h}' fill='#fdf6e3'/>"
    art += f"<rect x='0' y='0' width='64' height='{h}' fill='#f3ead2'/>"
    log = [("[1/9]", "Compiling Lexer.swift"), ("[2/9]", "Compiling Parser.swift"), ("[3/9]", "Compiling Sema.swift"),
           ("[4/9]", "Compiling IRGen.swift"), ("[5/9]", "Emitting module Swift"), ("[6/9]", "Compiling Driver.swift"),
           ("[7/9]", "Linking swiftc"), ("[8/9]", "Applying Package.swift")]
    y = 40
    for i, (a, b) in enumerate(log):
        art += text(52, y, str(101 + i), 15, "#b8ab88", MONO, 400, "end")
        art += f"<text x='84' y='{y}' font-family=\"{MONO}\" font-size='19'><tspan fill='#268bd2'>{a}</tspan><tspan fill='#586e75'> {b}</tspan></text>"
        y += 38
    art += "<rect x='64' y='334' width='736' height='56' fill='#d9f2d2'/>"
    art += text(52, 369, "109", 15, "#6aa56a", MONO, 400, "end")
    art += ("<circle cx='102' cy='362' r='14' fill='#2fa84f'/><path d='M95,362 L100,368 L110,356' stroke='#fff' stroke-width='3.5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>")
    art += text(130, 369, "Build complete!", 22, "#1f7f3a", MONO, 700) + text(340, 369, "(412.08s)", 20, "#4f9a5f", MONO, 400)
    return page(w, h, svg(w, h, art))


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
}


def html(p):
    w, h = p["size"]
    return DRAW[p["key"]](w, h)
