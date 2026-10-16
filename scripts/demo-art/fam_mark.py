"""fam_mark — made app icons for the demo's own apps (prd §1338).

The demo's Privy rows named six real products and drew the stack glyph for
every one, because the demo never reads Privy's logos. Real names would want
real logos, and a drawn logo on a real product is a forgery, so the demo's
apps are made up (Tidepool, Lantern, …) and each wears a mark drawn here: a
rounded square in the app's own colours with one simple motif, no words.

Everything is inline SVG with no fetched asset.
"""


def doc(w, h, body):
    return (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        f"html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:transparent}}"
        "svg{display:block}</style></head><body>" + body + "</body></html>"
    )


def icon(top, bottom, motif):
    """A 180px squircle-ish tile with a vertical gradient and one motif."""
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' width='180' height='180' viewBox='0 0 180 180'>"
        "<defs><linearGradient id='g' x1='0' y1='0' x2='0' y2='1'>"
        f"<stop offset='0' stop-color='{top}'/><stop offset='1' stop-color='{bottom}'/>"
        "</linearGradient></defs>"
        "<rect width='180' height='180' rx='40' fill='url(#g)'/>"
        f"{motif}</svg>"
    )


def tidepool():
    # Three nested waves.
    waves = "".join(
        f"<path d='M30 {y} q15 -14 30 0 t30 0 t30 0 t30 0' fill='none' stroke='#fff' "
        f"stroke-width='10' stroke-linecap='round' opacity='{o}'/>"
        for y, o in ((70, 1), (95, .75), (120, .5)))
    return icon("#2bb3c9", "#1559a8", waves)


def lantern():
    # A lantern's flame in a ring.
    motif = ("<circle cx='90' cy='92' r='46' fill='none' stroke='#fff3d6' stroke-width='9'/>"
             "<path d='M90 58 C108 82 106 104 90 118 C74 104 72 82 90 58 Z' fill='#fff3d6'/>")
    return icon("#f6a33a", "#c2401f", motif)


def kitebox():
    # A kite: a diamond with its spar and a tail.
    motif = ("<path d='M90 34 L128 82 L90 130 L52 82 Z' fill='#fff'/>"
             "<path d='M90 34 L90 130 M52 82 L128 82' stroke='#6a3fd1' stroke-width='5'/>"
             "<path d='M90 130 q10 12 0 20 q-10 8 0 16' fill='none' stroke='#fff' stroke-width='6' stroke-linecap='round'/>")
    return icon("#9b6cf2", "#4b23a8", motif)


def mossline():
    # A leaf over a horizon line.
    motif = ("<path d='M56 116 C56 70 92 48 128 48 C128 92 104 116 56 116 Z' fill='#eaf7df'/>"
             "<path d='M58 114 L120 56' stroke='#2f7d3a' stroke-width='5' stroke-linecap='round'/>"
             "<rect x='36' y='134' width='108' height='9' rx='4.5' fill='#eaf7df' opacity='.7'/>")
    return icon("#5fbf55", "#22693a", motif)


def pebble_arcade():
    # A pad: a plus and two buttons.
    motif = ("<rect x='34' y='60' width='112' height='64' rx='32' fill='#fff'/>"
             "<path d='M62 80 v24 M50 92 h24' stroke='#d6336c' stroke-width='7' stroke-linecap='round'/>"
             "<circle cx='114' cy='84' r='7' fill='#d6336c'/><circle cx='128' cy='100' r='7' fill='#d6336c'/>")
    return icon("#ff7aa8", "#c2185b", motif)


def sundial():
    # A half sun with its gnomon's shadow.
    rays = "".join(
        f"<rect x='87' y='30' width='6' height='18' rx='3' fill='#2a2a2a' transform='rotate({a} 90 108)'/>"
        for a in (-60, -30, 0, 30, 60))
    motif = (rays + "<path d='M44 108 A46 46 0 0 1 136 108 Z' fill='#2a2a2a'/>"
             "<rect x='36' y='112' width='108' height='9' rx='4.5' fill='#2a2a2a'/>")
    return icon("#ffe27a", "#f2b705", motif)


DRAW = {
    "privy-tidepool": tidepool,
    "privy-lantern": lantern,
    "privy-kitebox": kitebox,
    "privy-mossline": mossline,
    "privy-pebble-arcade": pebble_arcade,
    "privy-sundial": sundial,
}


def html(p):
    w, h = p["size"]
    return doc(w, h, DRAW[p["key"]]())
