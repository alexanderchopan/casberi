"""fam_sleeve — made square and capsule art: album covers, podcast episodes and
Steam library headers.

Every cover is DRAWN for its row and imitates no real sleeve, show art or game
logo: the albums carry no words and are abstract pictures of each record's mood;
the podcast shows each have one identity (name, type, colour system) that their
two episodes share while their motif, colour and title differ; the game headers
evoke each world with the name set in a face chosen here.

Everything is inline SVG/CSS with system fonts; no image, font or script is
fetched.
"""

import math
import random

# ── shared helpers ────────────────────────────────────────────────────────


def doc(w, h, body, css=""):
    return (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        f"html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:#000}}"
        "svg{display:block}"
        f"{css}</style></head><body>{body}</body></html>"
    )


def svg(w, h, inner, defs=""):
    return (f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' "
            f"viewBox='0 0 {w} {h}'><defs>{defs}</defs>{inner}</svg>")


def lin(id_, stops, x1=0, y1=0, x2=0, y2=1):
    s = "".join(f"<stop offset='{o}' stop-color='{c}' stop-opacity='{a}'/>"
                for o, c, a in (st if len(st) == 3 else (*st, 1) for st in stops))
    return f"<linearGradient id='{id_}' x1='{x1}' y1='{y1}' x2='{x2}' y2='{y2}'>{s}</linearGradient>"


def rad(id_, stops, cx=0.5, cy=0.5, r=0.5, fx=None, fy=None):
    s = "".join(f"<stop offset='{o}' stop-color='{c}' stop-opacity='{a}'/>"
                for o, c, a in (st if len(st) == 3 else (*st, 1) for st in stops))
    f = f" fx='{fx}' fy='{fy}'" if fx is not None else ""
    return f"<radialGradient id='{id_}' cx='{cx}' cy='{cy}' r='{r}'{f}>{s}</radialGradient>"


def blur(id_, sd):
    return (f"<filter id='{id_}' x='-50%' y='-50%' width='200%' height='200%'>"
            f"<feGaussianBlur stdDeviation='{sd}'/></filter>")


def stars(rng, n, w, h, color="#fff", rmax=1.3, ymax=None):
    ymax = ymax or h
    return "".join(
        f"<circle cx='{rng.uniform(0, w):.1f}' cy='{rng.uniform(0, ymax):.1f}' "
        f"r='{rng.uniform(.3, rmax):.2f}' fill='{color}' opacity='{rng.uniform(.25, .9):.2f}'/>"
        for _ in range(n))


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ── albums (600×600, no words) ────────────────────────────────────────────


def reckoner():
    """Warm, layered, falsetto over strings: a gold sun behind a curtain of
    fine falling threads on plum."""
    rng = random.Random(11)
    pal = ["#f6d38a", "#f2a36b", "#e86f6a", "#9fd6c8", "#f7e9cf"]
    lines = []
    for i in range(80):
        x = rng.uniform(0, 600)
        top = rng.uniform(-40, 260)
        ln = rng.uniform(180, 520)
        lines.append(
            f"<line x1='{x:.1f}' y1='{top:.0f}' x2='{x:.1f}' y2='{top + ln:.0f}' "
            f"stroke='{rng.choice(pal)}' stroke-width='{rng.uniform(1.5, 4):.1f}' "
            f"stroke-linecap='round' opacity='{rng.uniform(.18, .75):.2f}'/>")
    defs = (lin("bg", [(0, "#3a1838"), (.6, "#24112a"), (1, "#120a18")])
            + rad("sun", [(0, "#ffe2a0"), (.55, "#f09a5c"), (1, "#c2485a", 0)])
            + lin("fade", [(0, "#120a18", 0), (1, "#120a18", .95)])
            + blur("b", 6))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             "<circle cx='300' cy='250' r='230' fill='url(#sun)' opacity='.85'/>"
             "<circle cx='300' cy='250' r='128' fill='#ffd48e' opacity='.9' filter='url(#b)'/>"
             f"<g>{''.join(lines)}</g>"
             "<rect y='380' width='600' height='220' fill='url(#fade)'/>")
    return svg(600, 600, inner, defs)


def pyramid_song():
    """Underwater and starry: a pyramid on a still horizon, its reflection
    broken into ripples, a black moon and rising bubbles."""
    rng = random.Random(22)
    hz = 340
    tri = "M300 132 L438 340 L162 340 Z"
    slivers = []
    y = hz + 4
    k = 0
    while y < 560:
        hgt = 3 + k * .9
        sh = rng.uniform(-10, 10) * (1 + k * .15)
        slivers.append(f"<rect x='{-sh}' y='{y:.1f}' width='600' height='{hgt:.1f}' fill='white'/>")
        y += hgt + 3 + k * .7
        k += 1
    bubbles = "".join(
        f"<circle cx='{rng.uniform(40, 560):.0f}' cy='{rng.uniform(370, 590):.0f}' "
        f"r='{rng.uniform(1.5, 6):.1f}' fill='none' stroke='#9fc2ff' stroke-width='1' "
        f"opacity='{rng.uniform(.25, .6):.2f}'/>" for _ in range(26))
    defs = (lin("sky", [(0, "#050912"), (.7, "#0f2140"), (1, "#1c3a66")])
            + lin("sea", [(0, "#10284a"), (1, "#03060d")])
            + lin("pyr", [(0, "#35507e"), (1, "#172a4a")], 0, 0, 1, 0)
            + lin("refl", [(0, "#35507e", .7), (1, "#35507e", 0)])
            + "<mask id='rip'>" + "".join(slivers) + "</mask>"
            + blur("g", 18))
    inner = ("<rect width='600' height='600' fill='url(#sky)'/>"
             + stars(rng, 90, 600, hz - 20, "#dfe8ff", 1.2)
             + "<circle cx='438' cy='120' r='52' fill='#8fb0e6' opacity='.35' filter='url(#g)'/>"
             "<circle cx='438' cy='120' r='44' fill='#03050b'/>"
             "<path d='M398 102 A44 44 0 0 1 470 92' stroke='#c9dafc' stroke-width='2' fill='none' opacity='.8'/>"
             f"<rect y='{hz}' width='600' height='{600 - hz}' fill='url(#sea)'/>"
             f"<path d='{tri}' fill='url(#pyr)'/>"
             "<path d='M300 132 L438 340' stroke='#9db8e8' stroke-width='1.5' opacity='.7'/>"
             f"<g mask='url(#rip)'><path d='M300 548 L438 340 L162 340 Z' fill='url(#refl)'/></g>"
             f"<rect y='{hz - 1}' width='600' height='2' fill='#9db8e8' opacity='.35'/>"
             + bubbles)
    return svg(600, 600, inner, defs)


def teardrop():
    """Dark and heavy: a single glossy black drop with a crimson rim light,
    about to land in a still black pool."""
    drop = ("M300 96 C300 96 404 250 404 334 C404 394 357 438 300 438 "
            "C243 438 196 394 196 334 C196 250 300 96 300 96 Z")
    rings = "".join(
        f"<ellipse cx='300' cy='520' rx='{60 + i * 46}' ry='{10 + i * 7.6}' fill='none' "
        f"stroke='#c23a3f' stroke-width='1.4' opacity='{.5 - i * .09:.2f}'/>" for i in range(5))
    defs = (rad("bg", [(0, "#1d1b1c"), (.7, "#0b0a0b"), (1, "#030303")], .5, .45, .75)
            + rad("body", [(0, "#2c2a2c"), (.5, "#0d0c0d"), (1, "#000")], .38, .62, .7)
            + lin("rim", [(0, "#ff4a4a", 0), (.55, "#e03a42", .2), (1, "#ff5a55", .95)], 0, 0, 1, .4)
            + rad("pool", [(0, "#5a1418", .55), (1, "#000", 0)])
            + blur("s", 7) + blur("s2", 22))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             "<ellipse cx='300' cy='520' rx='250' ry='46' fill='url(#pool)'/>"
             + rings +
             f"<path d='{drop}' fill='#b0262d' opacity='.35' filter='url(#s2)' transform='translate(10 6)'/>"
             f"<path d='{drop}' fill='url(#body)'/>"
             f"<path d='{drop}' fill='none' stroke='url(#rim)' stroke-width='3'/>"
             "<ellipse cx='258' cy='300' rx='16' ry='46' fill='#fff' opacity='.55' filter='url(#s)' transform='rotate(18 258 300)'/>"
             "<ellipse cx='262' cy='292' rx='4' ry='16' fill='#fff' opacity='.8' transform='rotate(18 262 292)'/>")
    return svg(600, 600, inner, defs)


def unfinished_sympathy():
    """A soaring city night: long-exposure streaks of sodium orange and
    electric blue racing under a dark skyline."""
    rng = random.Random(33)
    towers = []
    x = 0
    while x < 600:
        w = rng.uniform(26, 70)
        h = rng.uniform(80, 250)
        towers.append(f"<rect x='{x:.0f}' y='{330 - h:.0f}' width='{w + 1:.0f}' height='{h:.0f}' fill='#0e1430'/>")
        for _ in range(int(h / 22)):
            if rng.random() < .35:
                towers.append(
                    f"<rect x='{x + rng.uniform(4, w - 8):.0f}' y='{330 - rng.uniform(10, h - 8):.0f}' "
                    f"width='3' height='4' fill='#ffcf7a' opacity='{rng.uniform(.4, .9):.2f}'/>")
        x += w
    streaks = []
    for i in range(46):
        y = 350 + (i / 46) ** 1.6 * 240 + rng.uniform(-4, 4)
        thick = 1 + (y - 340) / 50
        L = rng.uniform(160, 520)
        x0 = rng.uniform(-80, 600 - L * .4)
        g = rng.choice(["o", "b", "w", "o", "b"])
        streaks.append(
            f"<rect x='{x0:.0f}' y='{y:.1f}' width='{L:.0f}' height='{thick:.1f}' rx='{thick / 2:.1f}' "
            f"fill='url(#{g})' opacity='{rng.uniform(.55, 1):.2f}'/>")
    defs = (lin("sky", [(0, "#070914"), (1, "#1a1f4a")])
            + lin("road", [(0, "#10142c"), (1, "#05060d")])
            + lin("o", [(0, "#ff7a2e", 0), (.8, "#ffa04a"), (1, "#fff1d6")], 0, 0, 1, 0)
            + lin("b", [(0, "#2f6bff", 0), (.7, "#4d86ff"), (1, "#e2ecff")], 0, 0, 1, 0)
            + lin("w", [(0, "#fff", 0), (1, "#fff")], 0, 0, 1, 0)
            + rad("glow", [(0, "#ff8a3d", .55), (1, "#ff8a3d", 0)])
            + blur("bl", 3))
    inner = ("<rect width='600' height='600' fill='url(#sky)'/>"
             "<ellipse cx='300' cy='330' rx='420' ry='120' fill='url(#glow)'/>"
             + "".join(towers) +
             "<rect y='330' width='600' height='270' fill='url(#road)'/>"
             f"<g filter='url(#bl)' opacity='.7'>{''.join(streaks[::3])}</g>"
             + "".join(streaks))
    return svg(600, 600, inner, defs)


def svefn():
    """Glacial and luminous: a sonar ping spreading in pale ice water from one
    warm point of light."""
    rings = []
    r = 14
    i = 0
    while r < 900:
        rings.append(f"<circle cx='300' cy='340' r='{r:.0f}' fill='none' stroke='#ffffff' "
                     f"stroke-width='{max(1.4, 4 - i * .22):.2f}' opacity='{max(.14, .95 - i * .07):.2f}'/>")
        r *= 1.2
        i += 1
    echo = "".join(
        f"<circle cx='168' cy='196' r='{8 * 1.35 ** k:.0f}' fill='none' stroke='#dff4ff' "
        f"stroke-width='1' opacity='{.45 - k * .07:.2f}'/>" for k in range(6))
    defs = (rad("bg", [(0, "#e4f4fa"), (.3, "#a9cfdf"), (.7, "#5f93ad"), (1, "#355f7a")], .5, .56, .8)
            + rad("pt", [(0, "#fffdf2"), (.3, "#fff4d8", .9), (1, "#fff", 0)])
            + blur("b", .9))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             f"<g filter='url(#b)'>{''.join(rings)}</g>"
             f"<g filter='url(#b)'>{echo}</g>"
             "<circle cx='300' cy='340' r='70' fill='url(#pt)'/>"
             "<circle cx='300' cy='340' r='7' fill='#fffef6'/>"
             "")
    return svg(600, 600, inner, defs)


def hoppipolla():
    """Joy after rain: pastel orbs of light rising through a bright dawn."""
    rng = random.Random(44)
    cols = ["#ffd1dc", "#ffe9a8", "#bfe6ff", "#ffc2a1", "#e8d4ff", "#ffffff"]
    orbs = []
    for i in range(34):
        r = rng.uniform(14, 96)
        cx = rng.uniform(-20, 620)
        cy = rng.uniform(40, 620) + r * .5
        c = rng.choice(cols)
        orbs.append((r, f"<circle cx='{cx:.0f}' cy='{cy:.0f}' r='{r:.0f}' fill='{c}' "
                        f"opacity='{rng.uniform(.35, .8):.2f}' filter='url(#{'b1' if r > 50 else 'b0'})'/>"
                        f"<circle cx='{cx - r * .28:.0f}' cy='{cy - r * .3:.0f}' r='{r * .22:.0f}' fill='#fff' opacity='.35' filter='url(#b0)'/>"))
    orbs.sort(key=lambda o: -o[0])
    defs = (lin("bg", [(0, "#fff7ec"), (.45, "#ffe0c8"), (.8, "#ffb9b3"), (1, "#f59bb4")])
            + rad("sun", [(0, "#fff"), (.4, "#fffbe8", .9), (1, "#fff5e0", 0)])
            + blur("b0", 1.5) + blur("b1", 5))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             "<circle cx='300' cy='90' r='260' fill='url(#sun)'/>"
             + "".join(o[1] for o in orbs))
    return svg(600, 600, inner, defs)


def dayvan_cowboy():
    """A sun-bleached print: a halftone sun over a desert horizon, faded teal
    sky, a light leak in the corner, a paper border."""
    defs = (lin("sky", [(0, "#8fbcb8"), (.55, "#cfd6b8"), (1, "#f2c79a")])
            + lin("land", [(0, "#c98f5f"), (1, "#8a5a3c")])
            + "<pattern id='dots' width='9' height='9' patternUnits='userSpaceOnUse'>"
              "<circle cx='4.5' cy='4.5' r='3.1' fill='#e8773f'/></pattern>"
            + rad("sunglow", [(0, "#ffd9a0", .8), (1, "#ffd9a0", 0)])
            + lin("leak", [(0, "#ff6a3a", 0), (.7, "#ff7a3a", .25), (1, "#ffb35a", .55)], 0, 0, 1, .3)
            + rad("vig", [(0, "#000", 0), (.75, "#000", 0), (1, "#3a2410", .35)], .5, .5, .72)
            + "<clipPath id='ph'><rect x='38' y='38' width='524' height='470' rx='6'/></clipPath>"
            + "<clipPath id='sunc'><circle cx='300' cy='312' r='108'/></clipPath>")
    mesa = ("M38 356 L120 356 L134 330 L196 330 L206 356 L340 356 L352 340 L402 340 "
            "L410 356 L562 356 L562 520 L38 520 Z")
    inner = ("<rect width='600' height='600' fill='#efe7d6'/>"
             "<g clip-path='url(#ph)'>"
             "<rect x='38' y='38' width='524' height='470' fill='url(#sky)'/>"
             "<circle cx='300' cy='312' r='190' fill='url(#sunglow)'/>"
             "<g clip-path='url(#sunc)'><rect x='180' y='190' width='240' height='240' fill='url(#dots)'/></g>"
             f"<path d='{mesa}' fill='url(#land)'/>"
             "<path d='M38 400 Q300 382 562 404' stroke='#e7b47c' stroke-width='2' fill='none' opacity='.6'/>"
             "<path d='M38 446 Q300 424 562 452' stroke='#e7b47c' stroke-width='2' fill='none' opacity='.45'/>"
             "<rect x='38' y='38' width='524' height='470' fill='url(#leak)'/>"
             "<rect x='38' y='38' width='524' height='470' fill='url(#vig)'/>"
             "<rect x='38' y='38' width='524' height='470' fill='#f5ead2' opacity='.18'/>"
             "</g>")
    return svg(600, 600, inner, defs)


def roygbiv():
    """A 70s supergraphic in faded colour: seven bands drop down the left edge,
    turn a corner and run off to the right."""
    cols = ["#c9594a", "#d98a4a", "#dcb656", "#8fab63", "#5f97a3", "#5f6f9e", "#8a6a98"]
    bw = 30
    bands = []
    cx, cy = 300, 250
    for i, c in enumerate(cols):
        x = 70 + i * bw + bw / 2
        r = cx - x
        # down from the top, quarter-turn, then right to the edge
        bands.append(f"<path d='M{x} -10 L{x} {cy} A{r} {r} 0 0 0 {cx} {cy + r} L 620 {cy + r}' "
                     f"stroke='{c}' stroke-width='{bw + .5}' fill='none'/>")
    defs = (lin("bg", [(0, "#efe4c8"), (1, "#e2d2ad")])
            + rad("vig", [(0, "#fff", 0), (.7, "#fff", 0), (1, "#6b5330", .3)], .5, .5, .75))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             "<circle cx='468' cy='150' r='64' fill='#e5c77e' opacity='.9'/>"
             "<circle cx='468' cy='150' r='64' fill='none' stroke='#d6b36a' stroke-width='10' opacity='.5'/>"
             f"<g opacity='.9'>{''.join(bands)}</g>"
             "<rect width='600' height='600' fill='url(#vig)'/>"
             "<rect width='600' height='600' fill='#f3ead6' opacity='.14'/>")
    return svg(600, 600, inner, defs)


def kid_for_today():
    """Countryside through a red filter: hills folded into haze under a low
    sun, the colour of an old slide."""
    layers = [
        ("#c9603f", 300, 26, 1.3, .0),
        ("#a8493a", 350, 34, 1.9, 1.1),
        ("#833a36", 400, 40, 1.4, 2.4),
        ("#5e2c30", 452, 44, 2.2, .7),
        ("#3b1d24", 510, 38, 1.7, 3.0),
    ]
    paths = []
    for c, base, amp, freq, ph in layers:
        pts = []
        for x in range(0, 601, 20):
            t = x / 600
            y = base - amp * (math.sin(t * math.pi * freq + ph) * .7 + math.sin(t * math.pi * freq * 2.3 + ph * 1.7) * .3)
            pts.append(f"{x},{y:.1f}")
        paths.append(f"<polygon points='{' '.join(pts)} 600,600 0,600' fill='{c}'/>"
                     f"<rect y='{base - amp - 30}' width='600' height='60' fill='url(#haze)'/>")
    trees = "".join(
        f"<path d='M{x} {y} l6 -22 l6 22 Z' fill='#2c141a'/>" for x, y in
        [(430, 468), (446, 472), (461, 470), (120, 520), (134, 524)])
    defs = (lin("sky", [(0, "#e9785a"), (.55, "#f3b184"), (1, "#f7d3a4")])
            + lin("haze", [(0, "#f6c49a", 0), (.5, "#f6c49a", .35), (1, "#f6c49a", 0)])
            + rad("sun", [(0, "#fff3d8"), (.5, "#ffe0b0", .8), (1, "#ffd0a0", 0)]))
    inner = ("<rect width='600' height='600' fill='url(#sky)'/>"
             "<circle cx='190' cy='250' r='120' fill='url(#sun)'/>"
             "<circle cx='190' cy='250' r='38' fill='#fff1d4'/>"
             + "".join(paths) + trees +
             "<rect width='600' height='600' fill='#ffcfa0' opacity='.08'/>")
    return svg(600, 600, inner, defs)


def avril_14th():
    """A delicate piano line, cold and minimal: a piano roll of short graphite
    marks drifting across pale grey, one note in red."""
    rng = random.Random(55)
    notes = []
    x = 64
    pitch = 250
    while x < 530:
        pitch += rng.choice([-26, -13, 0, 13, 26, -39, 39])
        pitch = max(110, min(360, pitch))
        L = rng.choice([18, 26, 36, 54])
        notes.append((x, pitch, L))
        if rng.random() < .55:
            notes.append((x + rng.choice([0, 6]), pitch + rng.choice([78, 104, 130]), L * 1.7))
        x += L * .75 + rng.uniform(3, 10)
    marks = "".join(
        f"<rect x='{nx:.0f}' y='{ny:.0f}' width='{nl:.0f}' height='9' rx='2' fill='#262b31' "
        f"opacity='{.3 + .65 * (1 - abs(nx - 300) / 270):.2f}'/>" for nx, ny, nl in notes)
    rx, ry, rl = notes[len(notes) // 2 + 3]
    grid = "".join(f"<rect x='56' y='{y}' width='488' height='13' fill='#dde2e7'/>"
                   for y in range(104, 520, 52))
    inner = ("<rect width='600' height='600' fill='#eceff2'/>"
             f"{grid}{marks}"
             f"<rect x='{rx:.0f}' y='{ry:.0f}' width='{rl:.0f}' height='9' rx='2' fill='#d4412f'/>")
    return svg(600, 600, inner)


def xtal():
    """Cold ambient: a single crystal of grey facets lit from inside by a thin
    cyan light, alone in the dark."""
    rng = random.Random(66)
    pts = {
        "t": (300, 96), "a": (238, 214), "b": (356, 196), "c": (392, 318), "d": (318, 470),
        "e": (218, 356), "f": (300, 300), "g": (262, 150), "h": (342, 140),
    }
    faces = [("t", "g", "h", "#7f8a99"), ("g", "a", "f", "#4a5563"), ("h", "b", "f", "#9aa5b3"),
             ("g", "h", "f", "#b8c4d0"), ("a", "e", "f", "#2f3844"), ("b", "c", "f", "#6d7988"),
             ("e", "d", "f", "#1f262f"), ("c", "d", "f", "#3f4a57")]
    polys = "".join(
        f"<polygon points='{pts[p][0]},{pts[p][1]} {pts[q][0]},{pts[q][1]} {pts[r][0]},{pts[r][1]}' "
        f"fill='{c}' stroke='#9cf1ff' stroke-width='.9' stroke-opacity='.65'/>" for p, q, r, c in faces)
    shards = []
    for _ in range(9):
        x, y = rng.uniform(80, 520), rng.uniform(420, 540)
        s = rng.uniform(8, 22)
        shards.append(f"<polygon points='{x},{y - s} {x + s * .5},{y} {x},{y + s * .35} {x - s * .5},{y}' "
                      f"fill='#5b6674' opacity='{rng.uniform(.35, .7):.2f}'/>")
    defs = (rad("bg", [(0, "#16202a"), (.6, "#0a0e13"), (1, "#040507")], .5, .45, .7)
            + rad("glow", [(0, "#7fe8ff", .5), (1, "#7fe8ff", 0)])
            + lin("floor", [(0, "#9cf1ff", .18), (1, "#9cf1ff", 0)])
            + blur("b", 10))
    inner = ("<rect width='600' height='600' fill='url(#bg)'/>"
             "<ellipse cx='300' cy='290' rx='200' ry='230' fill='url(#glow)'/>"
             "<ellipse cx='300' cy='486' rx='230' ry='18' fill='url(#floor)'/>"
             f"<g>{polys}</g>"
             "<line x1='300' y1='96' x2='300' y2='300' stroke='#dffbff' stroke-width='1.2' opacity='.8'/>"
             "<circle cx='300' cy='300' r='5' fill='#e8fdff' filter='url(#b)'/>"
             + "".join(shards) +
             stars(rng, 30, 600, 600, "#bfe9f5", .9))
    return svg(600, 600, inner, defs)


def lianne():
    """Warm folk-tronica as a paper collage: an arched window of terracotta,
    leaves cut from mustard, olive and dusty pink, their shadows on cream."""
    rng = random.Random(77)
    leaf = "M0 0 C22 -30 58 -30 80 0 C58 30 22 30 0 0 Z"
    cols = ["#b5892f", "#6f7a3a", "#d9927e", "#8d4f2e", "#e0b24c", "#4f5a2a"]
    leaves = []
    for i in range(16):
        x, y = rng.uniform(40, 540), rng.uniform(60, 560)
        rot = rng.uniform(0, 360)
        sc = rng.uniform(.8, 1.8)
        c = rng.choice(cols)
        leaves.append(
            f"<g transform='translate({x:.0f} {y:.0f}) rotate({rot:.0f}) scale({sc:.2f})'>"
            f"<path d='{leaf}' fill='#5a3a1c' opacity='.22' transform='translate(4 5)' filter='url(#sh)'/>"
            f"<path d='{leaf}' fill='{c}'/>"
            f"<path d='M4 0 L76 0' stroke='#f3e2c0' stroke-width='1.4' opacity='.55'/></g>")
    defs = blur("sh", 3) + lin("arch", [(0, "#c8643d"), (1, "#a94c2e")])
    arch = "M160 560 L160 250 A140 140 0 0 1 440 250 L440 560 Z"
    inner = ("<rect width='600' height='600' fill='#f1e2c2'/>"
             f"<path d='{arch}' fill='#5a3a1c' opacity='.2' transform='translate(6 8)' filter='url(#sh)'/>"
             f"<path d='{arch}' fill='url(#arch)'/>"
             "<circle cx='300' cy='270' r='58' fill='#f4cf7a'/>"
             "<path d='M160 470 Q300 430 440 470 L440 560 L160 560 Z' fill='#7d3a24' opacity='.5'/>"
             + "".join(leaves))
    return svg(600, 600, inner, defs)


# ── podcast episodes (600×600) ────────────────────────────────────────────


def signals(ep_no, title, accent, ground, motif):
    """Signals and Threads: an engineering show. Dark ground, Menlo, a
    two-thread mark; each episode changes its phosphor and its figure."""
    mark = (f"<path d='M40 58 C54 36 66 80 80 58 S106 36 120 58' stroke='{accent}' stroke-width='3' fill='none'/>"
            f"<path d='M40 58 C54 80 66 36 80 58 S106 80 120 58' stroke='{accent}' stroke-width='3' fill='none' opacity='.45'/>")
    lines = title.split("|")
    tspans = "".join(f"<tspan x='40' dy='{0 if i == 0 else 58}'>{esc(t)}</tspan>" for i, t in enumerate(lines))
    rule = "".join(f"<rect x='{40 + i * 8}' y='396' width='4' height='4' fill='{accent}' opacity='.35'/>" for i in range(65))
    inner = (f"<rect width='600' height='600' fill='{ground}'/>"
             f"<rect width='600' height='600' fill='url(#tint)'/>"
             + mark +
             f"<text x='136' y='65' font-family='Menlo' font-size='21' fill='#e9efe9'>Signals and Threads</text>"
             f"<text x='560' y='65' text-anchor='end' font-family='Menlo' font-size='18' fill='{accent}'>ep {ep_no}</text>"
             + motif + rule +
             f"<text y='468' font-family='system-ui' font-weight='700' font-size='50' fill='#f4f7f4'>{tspans}</text>")
    defs = rad("tint", [(0, accent, .16), (1, accent, 0)], .7, .35, .6)
    return svg(600, 600, inner, defs)


def podcast_compilers():
    acc = "#5cf0a0"
    nodes = {"fn": (330, 120), "let": (220, 200), "ret": (440, 200), "=": (150, 290), "+": (285, 290),
             "x": (110, 360), "1": (190, 360), "a": (250, 360), "b": (320, 360), "call": (440, 290)}
    edges = [("fn", "let"), ("fn", "ret"), ("let", "="), ("let", "+"), ("=", "x"), ("=", "1"),
             ("+", "a"), ("+", "b"), ("ret", "call")]
    e = "".join(f"<line x1='{nodes[a][0]}' y1='{nodes[a][1]}' x2='{nodes[b][0]}' y2='{nodes[b][1]}' "
                f"stroke='{acc}' stroke-width='1.6' opacity='.55'/>" for a, b in edges)
    n = "".join(
        f"<circle cx='{x}' cy='{y}' r='24' fill='#0c1512' stroke='{acc}' stroke-width='2'/>"
        f"<text x='{x}' y='{y + 6}' text-anchor='middle' font-family='Menlo' font-size='{15 if len(k) > 2 else 18}' fill='{acc}'>{esc(k)}</text>"
        for k, (x, y) in nodes.items())
    return signals(41, "The one about|compilers", acc, "#0c1512", e + n)


def podcast_latency():
    acc = "#ffb547"
    rng = random.Random(88)
    bars = []
    for i in range(44):
        x = 40 + i * 12
        t = i / 43
        h = 230 * math.exp(-((t - .16) ** 2) / .012) + 14 * math.exp(-t * 2.2) + (6 if i in (31, 36, 40) else 0) + rng.uniform(0, 3)
        bars.append(f"<rect x='{x}' y='{360 - h:.0f}' width='8' height='{h:.0f}' rx='1.5' fill='{acc}' "
                    f"opacity='{.9 if t < .4 else .5}'/>")
    p99 = (f"<line x1='436' y1='120' x2='436' y2='366' stroke='#f4f7f4' stroke-width='1.5' stroke-dasharray='4 5'/>"
           f"<text x='446' y='138' font-family='Menlo' font-size='17' fill='#f4f7f4'>p99</text>"
           f"<text x='446' y='160' font-family='Menlo' font-size='15' fill='{acc}' opacity='.8'>412 µs</text>")
    return signals(42, "Latency,|end to end", acc, "#15110b", "".join(bars) + p99)


def design_details(ground, ink, title, motif):
    """Design Details: a design show. Light ground, a heavy black frame, the
    name in Avenir Next, the title in Georgia italic; each episode is one
    shape in its own two colours."""
    lines = title.split("|")
    tspans = "".join(f"<tspan x='300' dy='{0 if i == 0 else 46}'>{esc(t)}</tspan>" for i, t in enumerate(lines))
    inner = (f"<rect width='600' height='600' fill='{ground}'/>"
             f"<rect x='22' y='22' width='556' height='556' rx='18' fill='none' stroke='{ink}' stroke-width='8'/>"
             f"<text x='300' y='82' text-anchor='middle' font-family='Avenir Next' font-weight='800' font-size='30' fill='{ink}'>Design Details</text>"
             f"<rect x='270' y='98' width='60' height='5' rx='2.5' fill='{ink}'/>"
             + motif +
             f"<text y='{482 if len(lines) > 1 else 505}' text-anchor='middle' font-family='Georgia' font-style='italic' font-size='40' fill='{ink}'>{tspans}</text>")
    return svg(600, 600, inner)


def podcast_two_people():
    motif = ("<g style='mix-blend-mode:multiply'>"
             "<circle cx='246' cy='280' r='118' fill='#ff6b4a'/>"
             "<circle cx='354' cy='280' r='118' fill='#3d7bff'/></g>"
             "<circle cx='246' cy='280' r='6' fill='#1b1b1f'/><circle cx='354' cy='280' r='6' fill='#1b1b1f'/>")
    return design_details("#f5efe3", "#1b1b1f", "Making things|for two people", motif)


def podcast_good_demo():
    # the arc of a demo: a slow rise, a peak, then an ending that lands
    pts = [(96, 380), (170, 360), (250, 300), (330, 196), (380, 164), (430, 214), (480, 330), (506, 380)]
    d = f"M{pts[0][0]} {pts[0][1]} " + " ".join(
        f"S{(a[0] + b[0]) / 2:.0f} {b[1]} {b[0]} {b[1]}" for a, b in zip(pts, pts[1:]))
    motif = ("<rect x='80' y='392' width='440' height='16' rx='8' fill='#1b1b1f'/>"
             "<path d='M380 150 L300 392 L460 392 Z' fill='#ffd84a' opacity='.55'/>"
             f"<path d='{d}' stroke='#2c3fd9' stroke-width='10' fill='none' stroke-linecap='round'/>"
             "<circle cx='380' cy='164' r='16' fill='#ffd84a' stroke='#1b1b1f' stroke-width='5'/>")
    return design_details("#e6eaf7", "#1b1b1f", "The shape of|a good demo", motif)


def filter_stories(ground, ink, accent, title, motif):
    """Filter Stories: a coffee show. A round stamp with the name set on its
    rim, Futura, one hand-cut figure per episode on its own ground."""
    tspans = "".join(f"<tspan x='300' dy='{0 if i == 0 else 40}'>{esc(t)}</tspan>" for i, t in enumerate(title.split("|")))
    defs = "<path id='rimtop' d='M300 300 m-232 0 a232 232 0 1 1 464 0'/>"
    inner = (f"<rect width='600' height='600' fill='{ground}'/>"
             f"<circle cx='300' cy='300' r='262' fill='none' stroke='{ink}' stroke-width='3'/>"
             f"<circle cx='300' cy='300' r='206' fill='none' stroke='{ink}' stroke-width='1.5' opacity='.5'/>"
             f"<text font-family='Futura' font-weight='bold' font-size='30' fill='{ink}'>"
             f"<textPath href='#rimtop' startOffset='50%' text-anchor='middle'>Filter Stories</textPath></text>"
             f"<circle cx='88' cy='300' r='5' fill='{accent}'/><circle cx='512' cy='300' r='5' fill='{accent}'/>"
             + motif +
             f"<text y='464' text-anchor='middle' font-family='Avenir Next' font-weight='700' font-size='32' fill='{ink}'>{tspans}</text>")
    return svg(600, 600, inner, defs)


def podcast_coffee_measured():
    ink, acc = "#3a2317", "#c2562b"
    ticks = "".join(
        f"<line x1='{200 + i * 10}' y1='{396 if i % 5 else 388}' x2='{200 + i * 10}' y2='404' stroke='{ink}' stroke-width='2'/>"
        for i in range(13))
    motif = (f"<path d='M226 150 L374 150 L336 228 L264 228 Z' fill='{acc}'/>"
             f"<rect x='214' y='140' width='172' height='14' rx='4' fill='{ink}'/>"
             f"<rect x='292' y='228' width='16' height='12' fill='{ink}'/>"
             f"<path d='M300 246 L300 262' stroke='{acc}' stroke-width='4' stroke-linecap='round'/>"
             f"<circle cx='300' cy='276' r='4' fill='{acc}'/>"
             f"<path d='M246 292 L354 292 L346 360 Q300 372 254 360 Z' fill='#f3e6cf' stroke='{ink}' stroke-width='5' stroke-linejoin='round'/>"
             f"<rect x='182' y='364' width='236' height='42' rx='8' fill='{ink}'/>"
             + ticks.replace(ink, "#f3e6cf") +
             f"<text x='400' y='392' text-anchor='end' font-family='Menlo' font-size='16' fill='#ffb68a'>18.0 g</text>")
    return filter_stories("#e6cfa9", ink, acc, "Coffee, measured", motif)


def podcast_altitude():
    ink, acc = "#f1e4c8", "#e0a15a"
    contours = "".join(
        f"<path d='M110 {300 + i * 14} Q200 {262 + i * 14} 300 {288 + i * 14} T490 {280 + i * 14}' "
        f"stroke='{ink}' stroke-width='1.3' fill='none' opacity='{.35 - i * .05:.2f}'/>" for i in range(6))
    motif = (f"<ellipse cx='300' cy='184' rx='40' ry='54' fill='{acc}' transform='rotate(-24 300 184)'/>"
             f"<path d='M284 146 Q306 184 316 222' stroke='#1d3a2e' stroke-width='5' fill='none' stroke-linecap='round' transform='rotate(-24 300 184)'/>"
             f"<path d='M120 372 L218 244 L262 290 L330 204 L480 372 Z' fill='{ink}'/>"
             f"<path d='M330 204 L480 372 L380 372 Z' fill='#1d3a2e' opacity='.18'/>"
             f"<path d='M218 244 L262 290 L240 300 Z' fill='#1d3a2e' opacity='.18'/>"
             + contours)
    return filter_stories("#1d3a2e", ink, acc, "Roasting at altitude", motif)


# ── Steam library headers (736×344) ───────────────────────────────────────

W, H = 736, 344


def title_block(text, font, size, fill, x=44, y=None, weight="700", extra="", style=""):
    y = y or H - 48
    return (f"<text x='{x}' y='{y}' font-family=\"{font}\" font-weight='{weight}' font-size='{size}' "
            f"fill='{fill}' {extra} style='{style}'>{esc(text)}</text>")


def factorio():
    rng = random.Random(101)
    belt_h = "<pattern id='chev' width='22' height='26' patternUnits='userSpaceOnUse'>" \
             "<rect width='22' height='26' fill='#3b352e'/>" \
             "<path d='M4 5 L12 13 L4 21' stroke='#d9ab38' stroke-width='3' fill='none' opacity='.85'/></pattern>"
    belt_v = "<pattern id='chevv' width='26' height='22' patternUnits='userSpaceOnUse'>" \
             "<rect width='26' height='22' fill='#3b352e'/>" \
             "<path d='M5 4 L13 12 L21 4' stroke='#d9ab38' stroke-width='3' fill='none' opacity='.85'/></pattern>"
    grid = "<pattern id='grid' width='32' height='32' patternUnits='userSpaceOnUse'>" \
           "<rect width='32' height='32' fill='#2a251f'/><rect width='31' height='31' fill='#2f2a23'/></pattern>"
    defs = (belt_h + belt_v + grid
            + lin("plate", [(0, "#16130f", .97), (.75, "#16130f", .9), (1, "#16130f", 0)], 0, 0, 1, 0)
            + rad("fire", [(0, "#ffd27a"), (.6, "#ff8a2a"), (1, "#ff5a1a", 0)])
            + blur("b", 6))

    def machine(x, y, s, lit=True):
        g = (f"<rect x='{x + 4}' y='{y + 6}' width='{s}' height='{s}' rx='4' fill='#000' opacity='.35'/>"
             f"<rect x='{x}' y='{y}' width='{s}' height='{s}' rx='4' fill='#5c5249'/>"
             f"<rect x='{x + 5}' y='{y + 5}' width='{s - 10}' height='{s - 10}' rx='3' fill='#4a423a'/>"
             f"<circle cx='{x + s / 2}' cy='{y + s / 2}' r='{s * .24}' fill='none' stroke='#8a7e70' stroke-width='4' stroke-dasharray='5 4'/>")
        if lit:
            g += (f"<circle cx='{x + s / 2}' cy='{y + s / 2}' r='{s * .28}' fill='url(#fire)' filter='url(#b)' opacity='.8'/>"
                  f"<rect x='{x + s * .3}' y='{y + s * .72}' width='{s * .4}' height='6' rx='2' fill='#ffb347'/>")
        return g

    parts = ["<rect width='736' height='344' fill='url(#grid)'/>"]
    for y in (40, 150, 262):
        parts.append(f"<rect x='0' y='{y}' width='736' height='26' fill='url(#chev)'/>")
    for x in (300, 520, 640):
        parts.append(f"<rect x='{x}' y='0' width='26' height='344' fill='url(#chevv)'/>")
    parts.append("<path d='M360 110 L470 110 L470 220 L700 220' stroke='#7c8a93' stroke-width='12' fill='none' stroke-linejoin='round'/>"
                 "<path d='M360 110 L470 110 L470 220 L700 220' stroke='#a9b6bd' stroke-width='3' fill='none' opacity='.5' transform='translate(0 -3)'/>")
    for (x, y, s, lit) in [(360, 72, 64, True), (560, 80, 64, False), (400, 184, 56, True), (566, 300, 56, True),
                           (660, 110, 60, False), (350, 290, 48, False), (440, 20, 40, True), (690, 20, 40, True)]:
        parts.append(machine(x, y, s, lit))
    for _ in range(26):
        x, y = rng.choice([(rng.uniform(0, 736), 53), (rng.uniform(0, 736), 163), (rng.uniform(0, 736), 275)])
        c = rng.choice(["#c77a3a", "#8fa3ad", "#b8b0a0", "#4fa35a"])
        parts.append(f"<rect x='{x - 5:.0f}' y='{y - 5}' width='10' height='10' rx='2' fill='{c}'/>")
    parts.append("<rect width='360' height='344' fill='url(#plate)'/>")
    parts.append(title_block("Factorio", "Futura", 62, "#f2e2c4", y=210, weight="700"))
    parts.append("<rect x='46' y='232' width='96' height='6' rx='3' fill='#e09a3a'/>")
    return svg(W, H, "".join(parts), defs)


def balatro():
    suits = [("♠", "#1b1f3a"), ("♥", "#e0304a"), ("♦", "#e0304a"), ("♣", "#1b1f3a"), ("♥", "#e0304a")]
    ranks = ["A", "K", "7", "J", "Q"]
    cards = []
    for i, ((s, c), r) in enumerate(zip(suits, ranks)):
        rot = -28 + i * 14
        cards.append(
            f"<g transform='translate(580 410) rotate({rot}) translate(-58 -300)'>"
            f"<rect x='-2' y='-2' width='120' height='168' rx='12' fill='#6ef2ff' opacity='.35' filter='url(#glow)'/>"
            f"<rect width='116' height='164' rx='11' fill='#f7f1e3' stroke='#1b1f3a' stroke-width='3'/>"
            f"<text x='12' y='34' font-family='Rockwell' font-weight='700' font-size='28' fill='{c}'>{r}</text>"
            f"<text x='12' y='58' font-family='system-ui' font-size='22' fill='{c}'>{s}</text>"
            f"<text x='58' y='118' text-anchor='middle' font-family='system-ui' font-size='56' fill='{c}'>{s}</text></g>")
    chips = "".join(
        f"<g transform='translate({x} {y})'><circle r='22' fill='{c}'/>"
        f"<circle r='22' fill='none' stroke='#fff' stroke-width='5' stroke-dasharray='6 5.5'/>"
        f"<circle r='12' fill='none' stroke='#fff' stroke-width='1.5' opacity='.7'/></g>"
        for x, y, c in [(400, 296, "#2f6bff"), (436, 314, "#e0304a"), (706, 60, "#f0b429")])
    defs = (rad("sw1", [(0, "#ff3d6e", .9), (1, "#ff3d6e", 0)], .5, .5, .5)
            + rad("sw2", [(0, "#2de0d0", .7), (1, "#2de0d0", 0)], .5, .5, .5)
            + rad("sw3", [(0, "#7a3dff", .9), (1, "#7a3dff", 0)], .5, .5, .5)
            + blur("glow", 8) + blur("soft", 30))
    inner = ("<rect width='736' height='344' fill='#1c0f33'/>"
             "<g filter='url(#soft)'>"
             "<ellipse cx='160' cy='80' rx='300' ry='180' fill='url(#sw3)'/>"
             "<ellipse cx='600' cy='300' rx='280' ry='200' fill='url(#sw1)'/>"
             "<ellipse cx='380' cy='20' rx='220' ry='120' fill='url(#sw2)'/>"
             "<path d='M-40 260 C140 120 300 380 520 200 S760 60 800 120' stroke='#ff9a3d' stroke-width='40' fill='none' opacity='.45'/></g>"
             + "".join(cards) + chips +
             title_block("Balatro", "Rockwell", 84, "#2de0d0", x=47, y=213, extra="opacity='.9'")
             + title_block("Balatro", "Rockwell", 84, "#ff3d6e", x=41, y=209)
             + title_block("Balatro", "Rockwell", 84, "#fff6e8", x=44, y=210)
             + "<text x='48' y='252' font-family='Menlo' font-size='18' fill='#f0b429'>× 4 mult</text>")
    return svg(W, H, inner, defs)


def outer_wilds():
    rng = random.Random(202)

    def planet(cx, cy, r, base, shade, extra=""):
        return (f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='{base}'/>"
                f"<circle cx='{cx + r * .35}' cy='{cy + r * .3}' r='{r}' fill='{shade}' opacity='.55' clip-path='url(#c{cx})'/>"
                f"<clipPath id='c{cx}'><circle cx='{cx}' cy='{cy}' r='{r}'/></clipPath>{extra}")

    trees = "".join(
        f"<g transform='rotate({math.degrees(a) + 90:.0f} 188 128)'>"
        f"<path d='M{188 - 5} {128 - 28} l5 -{h} l5 {h} Z' fill='#2c6a3e'/></g>"
        for a, h in [(-2.5, 12), (-2.1, 16), (-1.75, 11), (-1.3, 15), (-0.9, 12), (-0.5, 9)])
    defs = (rad("sun", [(0, "#fff2c8"), (.25, "#ffc05a"), (.6, "#ff7a2a", .6), (1, "#ff5a1a", 0)])
            + rad("fire", [(0, "#fff0b0"), (.5, "#ffa53a"), (1, "#ff5a1a", 0)])
            + lin("ground", [(0, "#3d3a2f"), (1, "#1c1a15")])
            + blur("b", 4))
    inner = ("<rect width='736' height='344' fill='#070a18'/>"
             + stars(rng, 140, 736, 344, "#dfe6ff", 1.3) +
             "<circle cx='760' cy='60' r='250' fill='url(#sun)'/>"
             + planet(188, 128, 30, "#6cae6a", "#1c3a2a", trees)
             + planet(470, 70, 16, "#e0c08a", "#5a3a20")
             + planet(500, 82, 12, "#d8a36a", "#5a3a20")
             + planet(620, 210, 40, "#3f8fc4", "#0e2a4a",
                      "<path d='M590 196 Q620 186 650 200' stroke='#9fd4ff' stroke-width='3' fill='none' opacity='.6'/>")
             + planet(330, 36, 9, "#b0b6c4", "#2a2f3a")
             + "<ellipse cx='330' cy='36' rx='20' ry='5' fill='none' stroke='#d8dde8' stroke-width='1.5' opacity='.7'/>"
             "<path d='M-20 344 Q368 212 756 344 Z' fill='url(#ground)'/>"
             "<ellipse cx='520' cy='250' rx='120' ry='40' fill='#ff8a2a' opacity='.22' filter='url(#b)'/>"
             "<g transform='translate(520 254) scale(1.9) translate(-368 -262)'>"
             "<path d='M352 268 L384 260 M354 260 L382 270' stroke='#5a3a22' stroke-width='4' stroke-linecap='round'/>"
             "<path d='M368 262 C356 248 362 236 368 226 C372 240 382 244 368 262 Z' fill='url(#fire)'/>"
             "<circle cx='375' cy='236' r='1.4' fill='#ffd07a'/><circle cx='362' cy='222' r='1.1' fill='#ffd07a' opacity='.7'/>"
             "<circle cx='371' cy='212' r='.9' fill='#ffd07a' opacity='.5'/></g>"
             "<g transform='translate(420 150) rotate(-18)'><rect x='-14' y='-9' width='28' height='18' rx='8' fill='#d8d2c4'/>"
             "<circle cx='5' cy='0' r='4.5' fill='#6fd0ff'/><path d='M-14 -6 L-24 -12 M-14 6 L-24 12' stroke='#d8d2c4' stroke-width='3'/>"
             "<path d='M-16 0 L-34 0' stroke='#ffb45a' stroke-width='4' stroke-linecap='round' opacity='.8'/></g>"
             + title_block("Outer Wilds", "Avenir Next", 56, "#f7ead2", y=312, weight="600", extra="letter-spacing='1'"))
    return svg(W, H, inner, defs)


def slay_the_spire():
    rng = random.Random(303)
    spire = ("M520 344 L520 250 L536 220 L530 190 L548 150 L542 120 L556 84 L552 60 L562 22 L566 0 "
             "L572 22 L580 58 L576 84 L592 122 L586 150 L602 190 L596 222 L612 250 L612 344 Z")
    windows = "".join(f"<rect x='{rng.uniform(548, 580):.0f}' y='{y}' width='3' height='7' fill='#ff6a3a' opacity='{rng.uniform(.5, 1):.2f}'/>"
                      for y in range(90, 320, 26))
    clouds = "".join(
        f"<ellipse cx='{rng.uniform(0, 736):.0f}' cy='{y:.0f}' rx='{rng.uniform(90, 220):.0f}' ry='{rng.uniform(10, 22):.0f}' "
        f"fill='{c}' opacity='{o}' filter='url(#b)'/>"
        for y, c, o in [(120, "#3a1520", .6), (180, "#5a1a22", .5), (240, "#7a2422", .45), (150, "#2a1022", .6),
                        (270, "#9a3a28", .35), (210, "#431822", .55)])
    crags = ("M0 344 L0 290 L60 270 L110 288 L170 262 L240 292 L320 280 L380 300 L450 284 L520 310 "
             "L612 300 L680 276 L736 290 L736 344 Z")
    defs = (lin("sky", [(0, "#0d0f1c"), (.55, "#2a1224"), (.85, "#7a2a22"), (1, "#c2522c")])
            + rad("moon", [(0, "#f2d9a8", .9), (1, "#f2d9a8", 0)])
            + lin("sp", [(0, "#0a0a12"), (1, "#1c1016")], 0, 0, 1, 0)
            + blur("b", 7))
    inner = ("<rect width='736' height='344' fill='url(#sky)'/>"
             "<circle cx='640' cy='70' r='80' fill='url(#moon)'/>"
             "<circle cx='640' cy='70' r='24' fill='#f4e2bc'/>"
             + clouds +
             f"<path d='{spire}' fill='url(#sp)'/>" + windows +
             "<path d='M566 0 L566 -4' stroke='#ff6a3a'/>"
             "<circle cx='566' cy='40' r='4' fill='#ff5a3a'/><circle cx='566' cy='40' r='12' fill='#ff5a3a' opacity='.4' filter='url(#b)'/>"
             f"<path d='{crags}' fill='#08070c'/>"
             + title_block("Slay the Spire", "Didot", 66, "#efe0c4", y=150, weight="700")
             + "<path d='M46 176 L330 176' stroke='#c2522c' stroke-width='3'/>"
             "<path d='M330 176 l-10 -6 l0 12 Z' fill='#c2522c'/>")
    return svg(W, H, inner, defs)


def tunic():
    tw, th, dz = 58, 29, 24

    def iso(i, j, k=0):
        return 480 + (i - j) * tw / 2, 58 + (i + j) * th / 2 - k * dz

    def block(i, j, k, top, left, right):
        x, y = iso(i, j, k)
        return (f"<path d='M{x} {y} l{tw / 2} {th / 2} l{-tw / 2} {th / 2} l{-tw / 2} {-th / 2} Z' fill='{top}'/>"
                f"<path d='M{x - tw / 2} {y + th / 2} l{tw / 2} {th / 2} l0 {dz} l{-tw / 2} {-th / 2} Z' fill='{left}'/>"
                f"<path d='M{x} {y + th} l{tw / 2} {-th / 2} l0 {dz} l{-tw / 2} {th / 2} Z' fill='{right}'/>")

    rng = random.Random(404)
    heights = {}
    for i in range(9):
        for j in range(9):
            d = math.hypot(i - 4, j - 4)
            if d < 4.6:
                heights[(i, j)] = 1 if (i <= 3 and j <= 2) or (i <= 1 and j <= 4) else 0
    water = {(6, 2), (7, 2), (6, 3), (7, 3)}
    parts = []
    for (i, j) in sorted(heights, key=lambda t: (t[0] + t[1], t[0])):
        k = heights[(i, j)]
        if (i, j) in water:
            parts.append(block(i, j, -0.3, "#5fc8e8", "#3a8fb0", "#2f7a98"))
            continue
        for kk in range(k + 1):
            top = "#8fdc7a" if kk == k else "#8fdc7a"
            parts.append(block(i, j, kk, top, "#d3a86a", "#b08650"))
        if rng.random() < (.45 if k else .1) and (i, j) not in {(4, 4), (4, 5), (5, 4), (3, 4)}:
            x, y = iso(i, j, k)
            parts.append(f"<path d='M{x} {y - 30} l15 38 l-30 0 Z' fill='#2f9a5a'/><path d='M{x} {y - 30} l15 38 l-15 0 Z' fill='#237a46'/>"
                         f"<rect x='{x - 2.5}' y='{y + 8}' width='5' height='9' fill='#8a5a30'/>")
    fx, fy = iso(4, 4, 0)
    fox = (f"<g transform='translate({fx} {fy + 16}) scale(1.35)'>"
           f"<ellipse cx='0' cy='6' rx='12' ry='4' fill='#000' opacity='.18'/>"
           f"<path d='M-9 4 Q-10 -14 0 -18 Q10 -14 9 4 Z' fill='#3f9a5a'/>"
           f"<circle cx='0' cy='-24' r='8' fill='#ff8a2a'/>"
           f"<path d='M-7 -28 L-6 -40 L-1 -30 Z M7 -28 L6 -40 L1 -30 Z' fill='#ff8a2a'/>"
           f"<path d='M-3 -21 L0 -16 L3 -21 Z' fill='#fff4e6'/>"
           f"<path d='M10 -6 L22 -24' stroke='#e8f2ff' stroke-width='3' stroke-linecap='round'/>"
           f"<path d='M9 -12 L15 -8' stroke='#b08650' stroke-width='3'/></g>")
    defs = (lin("sky", [(0, "#bfeaff"), (1, "#f4fbff")])
            + rad("sun", [(0, "#fffbe0"), (1, "#fffbe0", 0)]))
    clouds = "".join(f"<ellipse cx='{x}' cy='{y}' rx='{rx}' ry='{rx * .34:.0f}' fill='#fff' opacity='.85'/>"
                     for x, y, rx in [(110, 90, 60), (150, 76, 40), (650, 60, 70), (690, 50, 40), (620, 280, 50)])
    inner = ("<rect width='736' height='344' fill='url(#sky)'/>"
             "<circle cx='620' cy='40' r='120' fill='url(#sun)'/>"
             + clouds + "".join(parts) + fox +
             "<text x='46' y='196' font-family='Gill Sans' font-weight='600' font-size='84' fill='#1e7a8a' opacity='.25' transform='translate(3 4)'>Tunic</text>"
             + title_block("Tunic", "Gill Sans", 84, "#1f5a6e", x=46, y=196, weight="600")
             + "<path d='M50 222 L150 222' stroke='#ff8a2a' stroke-width='5' stroke-linecap='round'/>"
             "<path d='M150 222 l10 -9 l6 9 l-6 9 Z' fill='#ff8a2a'/>")
    return svg(W, H, inner, defs)


# ── dispatch ──────────────────────────────────────────────────────────────

DRAW = {
    "music-0": reckoner,
    "music-1": pyramid_song,
    "music-2": teardrop,
    "music-3": unfinished_sympathy,
    "music-4": svefn,
    "music-5": hoppipolla,
    "spotify-0": dayvan_cowboy,
    "spotify-1": roygbiv,
    "spotify-2": kid_for_today,
    "spotify-3": avril_14th,
    "spotify-4": xtal,
    "spotify-5": lianne,
    "podcast-0": podcast_compilers,
    "podcast-1": podcast_latency,
    "podcast-2": podcast_two_people,
    "podcast-3": podcast_good_demo,
    "podcast-4": podcast_coffee_measured,
    "podcast-5": podcast_altitude,
    "steam-0": factorio,
    "steam-1": balatro,
    "steam-2": outer_wilds,
    "steam-3": slay_the_spire,
    "steam-4": tunic,
}


def html(p):
    w, h = p["size"]
    return doc(w, h, DRAW[p["key"]]())
