"""fam_ui.py — screens and documents for the demo (render.py's `ui` family).

Phone screenshots (shot-5…12), drawings (file-0/1/2/4), a whiteboard and a
code editor (reddit-2/3), two channel graphics (tg-2/4), a photographed laptop
dashboard (fc-0) and a paper figure (hf-paper-1). Every page is self-contained:
inline CSS and SVG, system fonts only, no logos.

`html(p)` dispatches on `p["key"]`; each builder returns the page's body and
CSS, and `doc()` wraps it at exactly `p["size"]`.
"""

import html as _h
import math
import re

# ── shared helpers ─────────────────────────────────────────────────────────

SANS = "system-ui,'Helvetica Neue',sans-serif"
MONO = "Menlo,monospace"
SERIF = "'Times New Roman',Times,'New York',serif"
HAND = "Noteworthy,'Bradley Hand','Marker Felt',cursive"


def esc(s):
    return _h.escape(s, quote=False)


def doc(p, body, css="", bg="#fff"):
    w, h = p["size"]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;padding:0;width:{w}px;height:{h}px;overflow:hidden;background:{bg}}}
*{{box-sizing:border-box}}
body{{font-family:{SANS};-webkit-font-smoothing:antialiased;position:relative}}
.abs{{position:absolute}}
{css}</style></head><body>{body}</body></html>"""


def status_bar(dark=False, bg="transparent"):
    """iOS status bar, 54pt tall (a 6.1" phone with the island)."""
    c = "#fff" if dark else "#000"
    wifi = "".join(
        f'<path d="M{41 - r * .72:.1f} {12.2 - r * .69:.1f} A{r} {r} 0 0 1 {41 + r * .72:.1f} {12.2 - r * .69:.1f}" '
        f'fill="none" stroke="{c}" stroke-width="2.1" stroke-linecap="round"/>' for r in (3.2, 6.6, 10))
    return f'''<div style="height:54px;position:relative;z-index:5;background:{bg};color:{c}">
<span style="position:absolute;left:0;width:132px;top:17px;text-align:center;font:600 17px {SANS};letter-spacing:-.3px">9:41</span>
<svg width="80" height="16" viewBox="0 0 80 16" style="position:absolute;right:26px;top:20px">
 <g fill="{c}"><rect x="0" y="8.5" width="3.2" height="4" rx="1"/><rect x="4.9" y="6.3" width="3.2" height="6.2" rx="1"/>
 <rect x="9.8" y="3.8" width="3.2" height="8.7" rx="1"/><rect x="14.7" y="1.3" width="3.2" height="11.2" rx="1"/></g>
 <circle cx="41" cy="11.4" r="1.6" fill="{c}"/>{wifi}
 <rect x="52.5" y=".8" width="24.5" height="12" rx="3.8" fill="none" stroke="{c}" stroke-opacity=".4"/>
 <rect x="54.5" y="2.8" width="20.5" height="8" rx="2.2" fill="{c}"/>
 <path d="M78.4 5v4.2c.9-.3 1.4-1.1 1.4-2.1s-.5-1.8-1.4-2.1z" fill="{c}" fill-opacity=".45"/>
</svg></div>'''


def home_bar(dark=False):
    c = "#fff" if dark else "#000"
    return (f'<div class="abs" style="bottom:8px;left:50%;margin-left:-67px;width:134px;height:5px;'
            f'border-radius:3px;background:{c};z-index:9"></div>')


def chev(color, size=22, left=True):
    d = "M14 4 6 12l8 8" if left else "M8 4l8 8-8 8"
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 22 24"><path d="{d}" fill="none" '
            f'stroke="{color}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>')


# A small code highlighter: enough to colour Swift and TypeScript believably.
SWIFT_KW = set("import struct var let some if else in private return func class enum case "
               "true false self static guard while for".split())
TS_KW = set("export type function const let while if continue return new of for "
            "string number boolean import from interface".split())
TOKEN = re.compile(r'(?P<com>//.*$)|(?P<str>"[^"]*")|(?P<rx>/(?:\\.|\[[^\]]*\]|[^/\\\s])+/[a-z]*(?=\.))'
                   r'|(?P<attr>@\w+)|(?P<num>\b\d+(?:\.\d+)?\b)|(?P<mem>\.[A-Za-z_]\w*)'
                   r'|(?P<id>[A-Za-z_]\w*)|(?P<ws>\s+)|(?P<p>.)')


def highlight(line, kw, pal):
    out = []
    for m in TOKEN.finditer(line):
        k, t = m.lastgroup, m.group()
        col, weight = None, ""
        if k == "com":
            col = pal["com"]
        elif k in ("str", "rx"):
            col = pal["str"]
        elif k == "num":
            col = pal["num"]
        elif k == "attr":
            col, weight = pal["kw"], "font-weight:700;"
        elif k == "mem":
            col = pal["mem"]
        elif k == "id":
            nxt = line[m.end():m.end() + 1]
            if t in kw:
                col, weight = pal["kw"], "font-weight:700;" if pal.get("bold") else ""
            elif t[0].isupper():
                col = pal["type"]
            elif nxt == "(":
                col = pal["fn"]
        if col:
            out.append(f'<span style="color:{col};{weight}">{esc(t)}</span>')
        else:
            out.append(esc(t))
    return "".join(out)


def code_block(lines, kw, pal, size, lh, gutter, num_col, active=None, active_bg="transparent", start=1):
    rows = []
    for i, ln in enumerate(lines):
        n = i + start
        bg = active_bg if n == active else "transparent"
        rows.append(f'<div style="display:flex;height:{lh}px;line-height:{lh}px;background:{bg}">'
                    f'<span style="width:{gutter}px;text-align:right;padding-right:10px;color:{num_col};flex:none">{n}</span>'
                    f'<span style="white-space:pre;color:{pal["plain"]}">{highlight(ln, kw, pal)}</span></div>')
    return f'<div style="font:{size}px/{lh}px {MONO}">{"".join(rows)}</div>'


XCODE_DARK = dict(plain="#DFDFE0", kw="#FF7AB2", type="#DABAFF", fn="#B281EB", mem="#67B7A4",
                  num="#D9C97C", str="#FF8170", com="#7F8C98", bold=True)
XCODE_LIGHT = dict(plain="#262626", kw="#AD3DA4", type="#703DAA", fn="#4B21B0", mem="#3E8087",
                   num="#272AD8", str="#D12F1B", com="#707F8C", bold=True)
ONE_DARK = dict(plain="#ABB2BF", kw="#C678DD", type="#E5C07B", fn="#61AFEF", mem="#E06C75",
                num="#D19A66", str="#98C379", com="#7F848E", bold=False)


# ── phone screenshots ──────────────────────────────────────────────────────

def shot_5(p):
    """Figma-like editor, light chrome: the spacing-tokens frame as bars."""
    tokens = [("space-1", 4), ("space-2", 8), ("space-3", 12), ("space-4", 16), ("space-6", 24), ("space-8", 32)]
    rows = ""
    for i, (name, v) in enumerate(tokens):
        sel = name == "space-6"
        outline = ('outline:1.5px solid #0D99FF;outline-offset:3px;' if sel else '')
        badge = ('<span class="abs" style="left:%dpx;top:-19px;background:#0D99FF;color:#fff;font:600 10px %s;'
                 'padding:1px 5px;border-radius:3px">%d</span>' % (v * 5.2 / 2 - 6, SANS, v * 1)) if sel else ""
        handles = "".join(
            f'<span class="abs" style="{pos};width:7px;height:7px;background:#fff;border:1.5px solid #0D99FF"></span>'
            for pos in ("left:-7px;top:-7px", "right:-7px;top:-7px", "left:-7px;bottom:-7px", "right:-7px;bottom:-7px")) if sel else ""
        rows += f'''<div style="display:flex;align-items:center;height:52px;border-top:{'0' if i == 0 else '1px solid #F0F0F0'}">
  <div style="width:92px;font:500 13px {MONO};color:#1E1E1E">{name}</div>
  <div style="width:34px;font:600 14px {SANS};color:#1E1E1E;text-align:right;padding-right:14px">{v}</div>
  <div style="position:relative;width:{v * 5.2:.0f}px;height:22px;background:rgba(242,78,130,.18);border-left:2px solid #F24E82;border-right:2px solid #F24E82;{outline}">
    {badge}{handles}</div></div>'''
    tools = "".join(f'<div style="width:40px;height:40px;border-radius:10px;display:grid;place-items:center;{bg}">{svg}</div>' for bg, svg in [
        ("background:#0D99FF", '<svg width="18" height="18" viewBox="0 0 18 18"><path d="M3 2l11 6-5 1.5L7 15z" fill="#fff"/></svg>'),
        ("", '<svg width="18" height="18" viewBox="0 0 18 18"><path d="M5 1v16M13 1v16M1 5h16M1 13h16" stroke="#333" stroke-width="1.6"/></svg>'),
        ("", '<svg width="18" height="18" viewBox="0 0 18 18"><rect x="2.5" y="2.5" width="13" height="13" fill="none" stroke="#333" stroke-width="1.6"/></svg>'),
        ("", '<svg width="18" height="18" viewBox="0 0 18 18"><path d="M3 15 14 4M11 3l4 4" stroke="#333" stroke-width="1.6" fill="none"/></svg>'),
        ("", '<svg width="18" height="18" viewBox="0 0 18 18"><text x="4" y="14.5" font-family="Georgia" font-size="16" fill="#333">T</text></svg>'),
        ("", '<svg width="18" height="18" viewBox="0 0 18 18"><path d="M3 3h12v9H8l-4 3v-3H3z" fill="none" stroke="#333" stroke-width="1.6" stroke-linejoin="round"/></svg>'),
    ])
    body = f'''{status_bar(False, "#fff")}
<div style="height:52px;background:#fff;display:flex;align-items:center;padding:0 12px;box-shadow:0 1px 0 #E6E6E6;position:relative;z-index:4">
  {chev("#1E1E1E", 20)}
  <div style="flex:1;text-align:center;line-height:1.15">
    <div style="font:600 15px {SANS};color:#1E1E1E">Design system</div>
    <div style="font:400 12px {SANS};color:#7A7A7A">Spacing tokens &#9662;</div></div>
  <svg width="22" height="22" viewBox="0 0 22 22"><path d="M6 4l12 7-12 7z" fill="none" stroke="#1E1E1E" stroke-width="1.8" stroke-linejoin="round"/></svg>
  <div style="width:14px"></div>
  <div style="width:28px;height:28px;border-radius:14px;background:#9747FF;color:#fff;font:600 13px {SANS};display:grid;place-items:center">A</div>
</div>
<div class="abs" style="top:106px;left:0;right:0;bottom:0;background:#EDEDED;
  background-image:radial-gradient(#D9D9D9 1px,transparent 1px);background-size:16px 16px"></div>
<div class="abs" style="top:128px;left:22px;font:500 11px {SANS};color:#7A7A7A">Spacing tokens</div>
<div class="abs" style="top:146px;left:22px;width:346px;background:#fff;padding:24px 22px 18px;box-shadow:0 1px 3px rgba(0,0,0,.08)">
  <div style="font:700 24px {SANS};color:#141414;letter-spacing:-.4px">Spacing tokens</div>
  <div style="font:400 13px {SANS};color:#8A8A8A;margin:4px 0 18px">Design system &middot; 4 pt base unit</div>
  {rows}
  <div style="margin-top:16px;padding:10px 12px;background:#F7F7F7;border-radius:6px;font:400 12px {SANS};color:#6B6B6B">
    Use space-4 between rows, space-6 around cards.</div>
</div>
<div class="abs" style="top:672px;left:22px;font:500 11px {SANS};color:#7A7A7A">Radius tokens</div>
<div class="abs" style="top:690px;left:22px;width:346px;height:200px;background:#fff;padding:22px;box-shadow:0 1px 3px rgba(0,0,0,.08)">
  <div style="font:700 20px {SANS};color:#141414">Radius tokens</div>
  <div style="display:flex;gap:14px;margin-top:16px">{''.join(f'<div style="width:62px;height:62px;border-radius:{r}px;background:#EDE7FF;border:2px solid #9747FF"></div>' for r in (0, 6, 12, 20))}</div>
</div>
<div class="abs" style="left:50%;margin-left:-140px;width:280px;bottom:34px;height:56px;background:#fff;border-radius:16px;
  box-shadow:0 6px 24px rgba(0,0,0,.14);display:flex;align-items:center;justify-content:space-around;padding:0 8px">{tools}</div>
{home_bar()}'''
    return doc(p, body, bg="#EDEDED")


def shot_9(p):
    """Figma-like editor, dark chrome: the colour ramp as a stacked column."""
    ramp = [("50", "#F7F1E8"), ("100", "#EFE3D1"), ("200", "#E0CBAE"), ("300", "#CDAE87"), ("400", "#B58D63"),
            ("500", "#9A7049"), ("600", "#7E5636"), ("700", "#624128"), ("800", "#472E1C"), ("900", "#2E1D12")]
    sw = ""
    for i, (n, hexv) in enumerate(ramp):
        ink = "#2E1D12" if i < 5 else "#F7F1E8"
        sel = n == "600"
        sw += f'''<div style="position:relative;height:47px;background:{hexv};display:flex;align-items:center;justify-content:space-between;padding:0 16px;
          font:500 13px {SANS};color:{ink};{'outline:2px solid #0D99FF;outline-offset:-1px;z-index:2' if sel else ''}">
          <span>espresso-{n}</span><span style="font:500 12px {MONO};opacity:.85">{hexv}</span></div>'''
    body = f'''{status_bar(True, "#2C2C2C")}
<div style="height:50px;background:#2C2C2C;display:flex;align-items:center;padding:0 12px;color:#fff">
  {chev("#fff", 20)}
  <div style="flex:1;text-align:center;line-height:1.15">
    <div style="font:600 15px {SANS}">Design system</div>
    <div style="font:400 12px {SANS};color:#A0A0A0">Colour ramp &#9662;</div></div>
  <div style="font:600 13px {SANS};background:#0D99FF;padding:5px 11px;border-radius:7px">Share</div>
</div>
<div class="abs" style="top:104px;left:0;right:0;bottom:0;background:#1E1E1E"></div>
<div class="abs" style="top:124px;left:34px;font:500 11px {SANS};color:#9B9B9B">Colour ramp</div>
<div class="abs" style="top:142px;left:34px;width:322px;background:#FFFCF8;box-shadow:0 10px 30px rgba(0,0,0,.45)">
  <div style="padding:18px 16px 14px;display:flex;justify-content:space-between;align-items:baseline">
    <div style="font:700 21px {SANS};color:#2E1D12;letter-spacing:-.3px">Colour ramp</div>
    <div style="font:500 11px {SANS};color:#9A7049">Espresso &middot; 10 steps</div></div>
  {sw}
</div>
<div class="abs" style="left:0;right:0;bottom:0;height:176px;background:#2C2C2C;border-radius:14px 14px 0 0;
  box-shadow:0 -8px 30px rgba(0,0,0,.4);padding:10px 18px;color:#fff">
  <div style="width:36px;height:5px;border-radius:3px;background:#5A5A5A;margin:0 auto 12px"></div>
  <div style="display:flex;justify-content:space-between;font:600 14px {SANS}"><span>Fill</span><span style="color:#8C8C8C;font-weight:400">Selection colours</span></div>
  <div style="display:flex;align-items:center;gap:10px;margin-top:12px;background:#383838;border-radius:8px;padding:9px 10px">
    <span style="width:22px;height:22px;border-radius:4px;background:#7E5636"></span>
    <span style="font:500 14px {MONO}">7E5636</span><span style="flex:1"></span>
    <span style="font:400 14px {SANS};color:#B3B3B3">100%</span></div>
  <div style="font:400 12px {SANS};color:#9B9B9B;margin-top:12px">espresso-600 &middot; used in 14 layers</div>
</div>
{home_bar(True)}'''
    return doc(p, body, bg="#1E1E1E")


def shot_6(p):
    """Dark Swift editor, playground-style, with a quick-help card."""
    lines = [
        "import SwiftUI", "", "struct CardList: View {", "  let cards: [Card]", "",
        "  var body: some View {", "    ScrollView {", "      LazyVStack(spacing: 16) {",
        "        ForEach(cards) { card in", "          CardView(card: card)",
        "            .scrollTransition {", "              content, phase in",
        "              content.opacity(", "                phase.isIdentity",
        "                  ? 1 : 0.4)", "            }", "        }", "      }",
        "      .padding(.horizontal)", "    }", "  }", "}", "",
        "#Preview {", "  CardList(cards: .samples)", "}",
    ]
    code = code_block(lines, SWIFT_KW, XCODE_DARK, 13, 22, 34, "#5E5F66", active=13, active_bg="#2A2C33")
    body = f'''{status_bar(True, "#26272C")}
<div style="height:48px;background:#26272C;display:flex;align-items:center;padding:0 14px;color:#fff">
  <svg width="24" height="20" viewBox="0 0 24 20"><rect x="1" y="1.5" width="22" height="17" rx="3.5" fill="none" stroke="#FF9F0A" stroke-width="1.8"/><path d="M8 2v16" stroke="#FF9F0A" stroke-width="1.8"/></svg>
  <div style="flex:1;text-align:center;font:600 16px {SANS}">ScrollTransitions.swift</div>
  <div style="width:30px;height:30px;border-radius:15px;background:#FF9F0A;display:grid;place-items:center">
    <svg width="12" height="13" viewBox="0 0 12 13"><path d="M2 1l9 5.5L2 12z" fill="#fff"/></svg></div>
</div>
<div style="background:#1F1F24;padding-top:10px;height:742px">{code}</div>
<div class="abs" style="left:16px;right:16px;bottom:40px;background:#2E2F36;border-radius:14px;padding:14px 16px;
  box-shadow:0 12px 30px rgba(0,0,0,.5);color:#E5E5E7">
  <div style="font:600 14px {MONO};color:#B281EB">scrollTransition(_:)</div>
  <div style="font:400 13.5px/1.4 {SANS};color:#B8B8BD;margin-top:6px">Animates the view as it enters and leaves the visible
   region of its scroll view. The phase is identity while fully on screen.</div>
</div>
{home_bar(True)}'''
    return doc(p, body, bg="#1F1F24")


def shot_10(p):
    """Light Swift editor split over a live preview of a card expanding."""
    lines = [
        "struct Gallery: View {", "  @Namespace private var ns", "  @State private var open = false", "",
        "  var body: some View {", "    if open {", "      BigCard()", "        .matchedGeometryEffect(",
        "          id: \"card\", in: ns)", "    } else {", "      SmallCard()", "        .matchedGeometryEffect(",
        "          id: \"card\", in: ns)", "    }", "  }", "}",
    ]
    code = code_block(lines, SWIFT_KW, XCODE_LIGHT, 13, 21, 32, "#A8A8AE", active=9, active_bg="#EAF1FB")
    body = f'''{status_bar(False, "#F7F7F9")}
<div style="height:46px;background:#F7F7F9;display:flex;align-items:center;padding:0 14px">
  {chev("#007AFF", 20)}<span style="font:400 17px {SANS};color:#007AFF;margin-left:2px">Files</span>
  <div style="flex:1;text-align:center;font:600 16px {SANS};color:#111;margin-right:52px">MatchedGeometry.swift</div>
</div>
<div style="background:#fff;padding-top:8px;height:360px">{code}</div>
<div class="abs" style="top:460px;left:0;right:0;bottom:0;background:linear-gradient(#EEF0F5,#E4E7EE)">
  <div style="display:flex;justify-content:space-between;align-items:center;padding:12px 16px 0">
    <span style="font:600 13px {SANS};color:#3C3C43;background:#fff;padding:5px 11px;border-radius:14px;box-shadow:0 1px 2px rgba(0,0,0,.08)">Live Preview</span>
    <span style="font:500 13px {SANS};color:#8E8E93">open = true</span></div>
  <div class="abs" style="left:26px;top:58px;width:112px;height:70px;border-radius:14px;border:2px dashed #A9B0C0"></div>
  <svg class="abs" style="left:74px;top:30px" width="140" height="120" viewBox="0 0 140 120">
    <path d="M40 30C70 8 110 20 128 60" fill="none" stroke="#007AFF" stroke-width="2" stroke-dasharray="4 5" stroke-linecap="round"/>
    <path d="M122 50l7 11 4-13" fill="none" stroke="#007AFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
  <div class="abs" style="left:78px;top:108px;width:276px;height:230px;border-radius:22px;background:#fff;overflow:hidden;
    box-shadow:0 18px 40px rgba(40,50,80,.22)">
    <div style="height:138px;background:linear-gradient(135deg,#FF9A62,#F2566B 55%,#8E5BD8);position:relative;overflow:hidden">
      <div class="abs" style="width:150px;height:150px;border-radius:75px;background:rgba(255,255,255,.18);right:-30px;top:-50px"></div>
      <div class="abs" style="width:90px;height:90px;border-radius:45px;background:rgba(255,255,255,.14);left:20px;bottom:-40px"></div></div>
    <div style="padding:14px 16px">
      <div style="font:700 18px {SANS};color:#111">Card</div>
      <div style="font:400 13px {SANS};color:#8E8E93;margin-top:3px">Shares its frame across views</div>
      <div style="height:8px;width:180px;background:#EDEEF2;border-radius:4px;margin-top:12px"></div></div>
  </div>
</div>
{home_bar()}'''
    return doc(p, body, bg="#fff")


def shot_7(p):
    """A maps screen: Alfama's tangle of streets, the river, a dotted walking route."""
    # Building footprints: a deterministic scatter under the streets, so the
    # quarter reads dense the way Alfama does.
    seed = 7
    blocks = []
    for gy in range(0, 600, 34):
        for gx in range(-10, 400, 38):
            seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
            if seed % 5 < 2:
                continue
            w, hh = 18 + seed % 17, 14 + (seed >> 5) % 15
            r = (seed >> 9) % 30 - 15
            blocks.append(f'<rect x="{gx + (seed >> 3) % 10}" y="{gy + (seed >> 7) % 9}" width="{w}" height="{hh}" rx="2" transform="rotate({r} {gx} {gy})"/>')
    streets = [
        "M-20 150C60 160 120 130 190 170S300 190 420 150",
        "M-20 330C50 318 100 346 160 336S260 300 310 330 380 360 420 352",
        "M50 40C80 120 60 200 100 270S110 400 80 520",
        "M230 30C216 110 256 160 244 226S214 330 250 400 290 470 320 560",
        "M350 40C330 140 360 200 336 290S366 400 410 450",
        "M-20 440C60 420 130 460 200 440S300 404 420 440",
        "M140 170C170 210 200 226 262 262",
        "M100 270C150 300 200 322 225 312",
        "M300 330C288 380 318 410 298 460",
        "M-20 520C80 500 170 526 240 496",
        "M160 40C170 90 150 110 170 150",
    ]
    lanes = [
        "M20 220C60 210 90 232 124 222", "M188 80C200 110 186 124 204 150", "M280 190C302 214 292 236 322 246",
        "M160 470C190 490 180 506 212 516", "M30 380C62 370 76 392 108 380", "M270 90C300 104 312 84 344 98",
        "M350 380C372 400 362 420 392 432", "M196 356C214 376 196 396 206 420", "M120 110C140 100 150 120 170 110",
        "M300 270C320 262 330 280 352 272", "M60 470C80 460 96 480 116 470", "M260 420C280 430 270 450 290 456",
    ]
    route = ("M300 210C286 232 272 240 262 262S240 300 225 312 196 330 200 356 "
             "176 396 160 414 134 440 120 470")
    svg = f'''<svg width="390" height="600" viewBox="0 0 390 600" class="abs" style="top:0;left:0">
  <rect width="390" height="600" fill="#F3EFE7"/>
  <g fill="#ECE6DA">{''.join(blocks)}</g>
  <path d="M10 176c40-22 110-18 120 12s-30 58-80 52-66-40-40-64z" fill="#CFE5C3"/>
  <path d="M300 120c34-10 70 4 72 26s-26 36-56 30-40-40-16-56z" fill="#CFE5C3"/>
  <g fill="none" stroke-linecap="round">
    {''.join(f'<path d="{d}" stroke="#DCD4C4" stroke-width="10"/>' for d in streets)}
    {''.join(f'<path d="{d}" stroke="#fff" stroke-width="7.5"/>' for d in streets)}
    {''.join(f'<path d="{d}" stroke="#fff" stroke-width="4"/>' for d in lanes)}
    <path d="M-20 548C90 520 190 552 290 512S380 468 420 462V620H-20z" fill="#A8D1F0" stroke="none"/>
    <path d="{route}" stroke="#fff" stroke-width="12"/>
    <path d="{route}" stroke="#0A84FF" stroke-width="7" stroke-dasharray="0 10.5"/>
  </g>
  <text x="44" y="304" font-family="{SANS}" font-size="15" font-weight="600" fill="#9A9384" letter-spacing="2.5">ALFAMA</text>
  <text x="326" y="506" font-family="{SANS}" font-size="12" font-style="italic" fill="#4F88B6">Rio Tejo</text>
  <text x="34" y="204" font-family="{SANS}" font-size="11" font-weight="500" fill="#5E8A55">Castelo de</text>
  <text x="34" y="217" font-family="{SANS}" font-size="11" font-weight="500" fill="#5E8A55">S&#227;o Jorge</text>
  <circle cx="300" cy="210" r="10" fill="#34C759" stroke="#fff" stroke-width="3"/>
  <circle cx="120" cy="470" r="11" fill="#FF3B30" stroke="#fff" stroke-width="3"/>
  <circle cx="120" cy="470" r="3.5" fill="#fff"/>
  <g font-family="{SANS}" font-size="12" font-weight="600" fill="#2C2C2E" stroke="#F3EFE7" stroke-width="3.5" paint-order="stroke" stroke-linejoin="round">
    <text x="286" y="196" text-anchor="end">Miradouro de</text><text x="286" y="211" text-anchor="end">Santa Luzia</text>
    <text x="138" y="475">S&#233;</text>
  </g>
  <g font-family="{SANS}" font-size="9.5" fill="#8B8578" stroke="#fff" stroke-width="2.5" paint-order="stroke">
    <text x="206" y="298" transform="rotate(-38 206 298)">R. de S&#227;o Miguel</text>
  </g>
</svg>'''
    body = f'''{svg}{status_bar(False)}
<div class="abs" style="top:60px;left:16px;right:70px;height:44px;border-radius:22px;background:rgba(255,255,255,.95);
  box-shadow:0 2px 12px rgba(0,0,0,.12);display:flex;align-items:center;padding:0 16px;font:600 16px {SANS};color:#111">
  <svg width="16" height="16" viewBox="0 0 16 16" style="margin-right:9px"><circle cx="7" cy="7" r="5.3" fill="none" stroke="#8E8E93" stroke-width="2"/><path d="M11 11l4 4" stroke="#8E8E93" stroke-width="2" stroke-linecap="round"/></svg>
  Alfama, Lisbon</div>
<div class="abs" style="top:60px;right:16px;width:44px;border-radius:12px;background:rgba(255,255,255,.95);box-shadow:0 2px 12px rgba(0,0,0,.12)">
  <div style="height:44px;display:grid;place-items:center;font:600 17px Georgia;color:#007AFF;font-style:italic">i</div>
  <div style="height:44px;display:grid;place-items:center"><svg width="18" height="18" viewBox="0 0 18 18"><path d="M16 2 2 8l6 2 2 6z" fill="#007AFF"/></svg></div></div>
<div class="abs" style="left:0;right:0;bottom:0;height:290px;background:#fff;border-radius:18px 18px 0 0;box-shadow:0 -4px 24px rgba(0,0,0,.14);padding:8px 20px 0">
  <div style="width:36px;height:5px;border-radius:3px;background:#D1D1D6;margin:0 auto 14px"></div>
  <div style="display:flex;justify-content:space-between;align-items:flex-start">
    <div><div style="font:700 24px {SANS};color:#111;letter-spacing:-.4px">Alfama walking route</div>
      <div style="font:400 16px {SANS};color:#6C6C70;margin-top:4px">18:40 &middot; 42 min walk</div></div>
    <div style="width:30px;height:30px;border-radius:15px;background:#EEEEF0;display:grid;place-items:center;color:#8E8E93;font:600 15px {SANS}">&#10005;</div></div>
  <div style="display:flex;gap:10px;margin-top:16px">
    {''.join(f'<div style="flex:1;background:#F2F2F7;border-radius:12px;padding:10px 12px"><div style="font:600 17px {SANS};color:#111">{a}</div><div style="font:400 13px {SANS};color:#8E8E93">{b}</div></div>' for a, b in [("2.1 km", "Distance"), ("+68 m", "Climb"), ("19:22", "Arrive")])}
  </div>
  <div style="font:400 14px {SANS};color:#6C6C70;margin-top:14px">From Miradouro de Santa Luzia to S&#233;, down the steps by Largo do Chafariz de Dentro</div>
  <div style="margin-top:16px;height:50px;border-radius:14px;background:#0A84FF;color:#fff;font:600 18px {SANS};display:grid;place-items:center">Go</div>
</div>
{home_bar()}'''
    return doc(p, body, bg="#F3EFE7")


def shot_8(p):
    """A notes app, dark: the espresso dial-in note with a checklist."""
    Y = "#FFD60A"

    def check(done, text):
        mark = (f'<span style="width:22px;height:22px;border-radius:11px;background:{Y};display:grid;place-items:center;flex:none">'
                f'<svg width="12" height="10" viewBox="0 0 12 10"><path d="M1.5 5l3 3 6-6.5" fill="none" stroke="#000" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
                if done else '<span style="width:22px;height:22px;border-radius:11px;border:1.6px solid #6B6B70;flex:none"></span>')
        st = "color:#8E8E93;text-decoration:line-through" if done else "color:#fff"
        return f'<div style="display:flex;align-items:center;gap:12px;margin:12px 0;font:400 17px {SANS};{st}">{mark}{text}</div>'

    icon = lambda d: f'<svg width="26" height="26" viewBox="0 0 26 26" fill="none" stroke="{Y}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{d}</svg>'
    body = f'''{status_bar(True)}
<div style="height:44px;display:flex;align-items:center;padding:0 12px;color:{Y};font:400 17px {SANS}">
  {chev(Y, 22)}<span>Notes</span><span style="flex:1"></span>
  <svg width="22" height="24" viewBox="0 0 22 24" fill="none" stroke="{Y}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 14V2M6 7l5-5 5 5M4 11v10h14V11"/></svg>
  <span style="width:18px"></span>
  <span style="width:26px;height:26px;border-radius:13px;border:2px solid {Y};display:grid;place-items:center;font:700 12px {SANS};line-height:0">&middot;&middot;&middot;</span>
  <span style="width:16px"></span><span style="font-weight:600">Done</span></div>
<div style="padding:4px 20px 0;color:#fff">
  <div style="text-align:center;font:400 13px {SANS};color:#8E8E93;margin-bottom:12px">23 September 2026 at 08:12</div>
  <div style="font:700 30px {SANS};letter-spacing:-.5px">Espresso dial-in</div>
  <div style="font:600 21px {SANS};margin:20px 0 8px">Recipe</div>
  <div style="font:400 17px/1.65 {SANS};color:#EDEDED">
    &bull;&nbsp; 18.0 g in / 36 g out<br>&bull;&nbsp; 28 s<br>&bull;&nbsp; Grind 2.8 &rarr; 2.6<br>
    &bull;&nbsp; Tastes: sour, then balanced</div>
  <div style="font:400 17px/1.5 {SANS};color:#EDEDED;margin-top:16px">Pulled at 93&deg;C. The first shot ran fast and sour;
    one notch finer and it came together.</div>
  <div style="font:600 21px {SANS};margin:22px 0 2px">Next time</div>
  {check(True, "Purge the group head")}
  {check(True, "Grind 2.6, finer by one")}
  {check(False, "Weigh the output, not the cup")}
  {check(False, "Try 94&deg;C with the new beans")}
  {check(False, "Log three shots in a row")}
</div>
<div class="abs" style="left:0;right:0;bottom:30px;height:50px;display:flex;align-items:center;justify-content:space-around;padding:0 16px">
  {icon('<circle cx="6" cy="7" r="2.5"/><path d="M12 7h11M12 13h11M12 19h11"/><circle cx="6" cy="13" r="2.5"/><circle cx="6" cy="19" r="2.5"/>')}
  {icon('<path d="M3 8h4l2-3h8l2 3h4v13H3z"/><circle cx="13" cy="14" r="4"/>')}
  {icon('<path d="M5 21l2-6L18 4l4 4L11 19zM15 7l4 4"/>')}
  {icon('<path d="M4 6h9M4 22V6M22 13v9H4M11 16l1-4 9-9 3 3-9 9z"/>')}
</div>
{home_bar(True)}'''
    return doc(p, body, bg="#000")


def tram_glyph(size=30, color="#1C1C1E"):
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 30 30"><path d="M11 3h8M15 3v4" stroke="{color}" stroke-width="1.8" stroke-linecap="round"/>
<rect x="6" y="7" width="18" height="17" rx="4" fill="{color}"/><rect x="9" y="10" width="5" height="5" rx="1" fill="#FFCC00"/>
<rect x="16" y="10" width="5" height="5" rx="1" fill="#FFCC00"/><circle cx="10.5" cy="20" r="1.4" fill="#FFCC00"/><circle cx="19.5" cy="20" r="1.4" fill="#FFCC00"/>
<path d="M9 24l-2 3M21 24l2 3" stroke="{color}" stroke-width="1.8" stroke-linecap="round"/></svg>'''


def shot_11(p):
    """A transit timetable, light: Tram 28E departures, the next one lit."""
    times = []
    t = 8 * 60 + 2
    while len(times) < 24:
        times.append(t)
        t += 12
    now = 9 * 60 + 41
    cells = ""
    for m in times:
        s = f"{m // 60:02d}:{m % 60:02d}"
        if m < now:
            st = "color:#B4B4BA"
        elif m == min(x for x in times if x >= now):
            st = "background:#FFCC00;color:#1C1C1E;font-weight:700;border-radius:9px"
        else:
            st = "color:#1C1C1E"
        cells += f'<div style="height:38px;display:grid;place-items:center;font:500 16px {SANS};font-variant-numeric:tabular-nums;{st}">{s}</div>'
    stops = ["Martim Moniz", "Gra&#231;a", "Portas do Sol", "S&#233;", "Chiado", "Estrela", "Campo Ourique"]
    stop_rows = "".join(
        f'<div style="display:flex;align-items:center;height:30px;font:400 15px {SANS};color:{"#1C1C1E" if i in (0, 6) else "#3A3A3C"};font-weight:{600 if i in (0, 6) else 400}">'
        f'<span style="width:12px;height:12px;border-radius:6px;background:#fff;border:3px solid #FFCC00;margin:0 14px 0 3px;position:relative;z-index:2"></span>{s}'
        f'<span style="flex:1"></span><span style="color:#8E8E93;font-size:14px;font-weight:400;font-variant-numeric:tabular-nums">{"" if i == 0 else f"+{[0, 4, 9, 13, 19, 27, 34][i]} min"}</span></div>'
        for i, s in enumerate(stops))
    body = f'''{status_bar(False, "#F2F2F7")}
<div style="height:44px;display:flex;align-items:center;padding:0 10px;color:#007AFF;font:400 17px {SANS}">{chev("#007AFF", 22)}Lines
  <span style="flex:1"></span><svg width="22" height="22" viewBox="0 0 22 22"><path d="M11 2l2.6 6 6.4.5-4.9 4.2 1.5 6.3L11 15.6 5.4 19l1.5-6.3L2 8.5 8.4 8z" fill="#007AFF"/></svg></div>
<div style="padding:4px 16px 0">
  <div style="display:flex;align-items:center;gap:14px">
    <div style="width:56px;height:56px;border-radius:14px;background:#FFCC00;display:grid;place-items:center;box-shadow:0 2px 6px rgba(200,150,0,.3)">{tram_glyph(34)}</div>
    <div><div style="font:700 28px {SANS};color:#1C1C1E;letter-spacing:-.4px">Tram 28E</div>
      <div style="font:400 15px {SANS};color:#6C6C70">Martim Moniz &rarr; Campo Ourique</div></div></div>
  <div style="display:flex;background:#E3E3E8;border-radius:9px;padding:2px;margin-top:16px;font:500 13px {SANS}">
    <div style="flex:1;text-align:center;background:#fff;border-radius:7px;padding:6px;box-shadow:0 1px 3px rgba(0,0,0,.1)">Weekday</div>
    <div style="flex:1;text-align:center;padding:6px">Saturday</div><div style="flex:1;text-align:center;padding:6px">Sunday</div></div>
  <div style="display:flex;justify-content:space-between;align-items:baseline;margin:20px 4px 8px">
    <span style="font:600 13px {SANS};color:#6C6C70">Departures &middot; Martim Moniz</span>
    <span style="font:600 13px {SANS};color:#248A3D">Next in 9 min</span></div>
  <div style="background:#fff;border-radius:12px;padding:8px;display:grid;grid-template-columns:repeat(4,1fr);gap:2px 6px">{cells}</div>
  <div style="font:600 13px {SANS};color:#6C6C70;margin:20px 4px 8px">Stops</div>
  <div style="background:#fff;border-radius:12px;padding:8px 12px;position:relative">
    <div class="abs" style="left:23px;top:23px;bottom:23px;width:4px;background:#FFCC00;border-radius:2px"></div>{stop_rows}</div>
</div>
{home_bar()}'''
    return doc(p, body, bg="#F2F2F7")


def shot_12(p):
    """A chart screenshot in espresso colours: grind vs shot time, target band."""
    pts = [(2.3, 35.2), (2.4, 33.1), (2.5, 31.0), (2.6, 28.4), (2.7, 27.2), (2.8, 25.6), (2.9, 24.1), (3.0, 22.8), (3.1, 21.5)]
    X0, X1, Y0, Y1 = 2.2, 3.2, 20, 36
    L, R, T, B = 44, 330, 16, 300

    def px(x):
        return L + (x - X0) / (X1 - X0) * (R - L)

    def py(y):
        return B - (y - Y0) / (Y1 - Y0) * (B - T)
    grid = "".join(f'<line x1="{L}" x2="{R}" y1="{py(v):.1f}" y2="{py(v):.1f}" stroke="#EDE3D6" stroke-width="1"/>'
                   f'<text x="{L - 8}" y="{py(v) + 4:.1f}" text-anchor="end" font-size="11" fill="#9C8773">{v}</text>' for v in range(20, 37, 4))
    xt = "".join(f'<text x="{px(v):.1f}" y="{B + 18}" text-anchor="middle" font-size="11" fill="#9C8773">{v:.1f}</text>' for v in (2.2, 2.4, 2.6, 2.8, 3.0, 3.2))
    line = " ".join(f"{px(x):.1f},{py(y):.1f}" for x, y in pts)
    dots = "".join(f'<circle cx="{px(x):.1f}" cy="{py(y):.1f}" r="{6 if x == 2.6 else 4.5}" fill="{"#C7843B" if x == 2.6 else "#fff"}" stroke="#5B3A24" stroke-width="2.2"/>' for x, y in pts)
    chart = f'''<svg width="346" height="330" viewBox="0 0 346 330" font-family="{SANS}">
  <rect x="{L}" y="{py(30):.1f}" width="{R - L}" height="{py(25) - py(30):.1f}" fill="#E9C99E" fill-opacity=".45"/>
  <text x="{R - 6}" y="{py(30) + 15:.1f}" text-anchor="end" font-size="11" font-weight="600" fill="#9A6A33">Target 25&ndash;30 s</text>
  {grid}{xt}
  <polyline points="{line}" fill="none" stroke="#5B3A24" stroke-width="2.6" stroke-linejoin="round"/>{dots}
  <g transform="translate({px(2.6) + 10:.1f},{py(28.4) - 34:.1f})"><rect width="74" height="24" rx="6" fill="#3B2A20"/>
  <text x="37" y="16" text-anchor="middle" font-size="12" font-weight="600" fill="#FFF6EA">2.6 &middot; 28.4 s</text></g>
  <text x="{(L + R) / 2}" y="{B + 30}" text-anchor="middle" font-size="12" fill="#7B6552">Grind setting</text>
  <text transform="translate(12 {(T + B) / 2}) rotate(-90)" text-anchor="middle" font-size="12" fill="#7B6552">Shot time (s)</text>
</svg>'''
    stats = "".join(f'<div style="flex:1"><div style="font:700 22px {SANS};color:#3B2A20;letter-spacing:-.3px">{a}</div>'
                    f'<div style="font:400 13px {SANS};color:#9C8773">{b}</div></div>' for a, b in [("2.6", "Sweet spot"), ("28.4 s", "Average"), ("14", "Shots")])
    shots = "".join(f'<div style="display:flex;justify-content:space-between;padding:11px 0;font:400 15px {SANS};color:#3B2A20">'
                    f'<span>{a}</span><span style="color:#9C8773;font-variant-numeric:tabular-nums">{b}</span></div>' for a, b in [
                        ("Today, 08:12 &middot; grind 2.6", "28 s"), ("Yesterday &middot; grind 2.8", "25 s")])
    body = f'''{status_bar(False)}
<div style="padding:8px 20px 0">
  <div style="display:flex;justify-content:space-between;color:#9A6A33;font:400 17px {SANS}"><span style="display:flex;align-items:center">{chev("#9A6A33", 22)}Shots</span><span>Edit</span></div>
  <div style="font:700 34px {SANS};color:#3B2A20;letter-spacing:-.6px;margin-top:10px">Grind chart</div>
  <div style="font:400 15px {SANS};color:#9C8773;margin-top:2px">Shot time by grind setting &middot; last 14 shots</div>
  <div style="background:#FFFBF5;border-radius:18px;margin-top:18px;padding:14px 4px 6px;box-shadow:0 2px 10px rgba(91,58,36,.08)">{chart}</div>
  <div style="display:flex;gap:10px;margin-top:22px;padding:0 4px">{stats}</div>
  <div style="margin-top:20px;padding:4px 16px;background:#FFFBF5;border-radius:14px">{shots}</div>
</div>
{home_bar()}'''
    return doc(p, body, bg="#F6EEE3")


# ── drawings ───────────────────────────────────────────────────────────────

PENCIL_FILTER = '''<filter id="pen" x="-5%" y="-5%" width="110%" height="110%">
  <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="4"/>
  <feDisplacementMap in="SourceGraphic" scale="2.6"/></filter>'''


def dim_h(x1, x2, y, label, col, fs=15, font=HAND, tick=7):
    return (f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}"/><line x1="{x1}" y1="{y - tick}" x2="{x1}" y2="{y + tick}"/>'
            f'<line x1="{x2}" y1="{y - tick}" x2="{x2}" y2="{y + tick}"/>'
            f'<text x="{(x1 + x2) / 2}" y="{y - 7}" text-anchor="middle" stroke="none" fill="{col}" font-family="{font}" font-size="{fs}">{label}</text>')


def dim_v(x, y1, y2, label, col, fs=15, font=HAND, tick=7):
    cy = (y1 + y2) / 2
    return (f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y2}"/><line x1="{x - tick}" y1="{y1}" x2="{x + tick}" y2="{y1}"/>'
            f'<line x1="{x - tick}" y1="{y2}" x2="{x + tick}" y2="{y2}"/>'
            f'<text transform="translate({x - 8} {cy}) rotate(-90)" text-anchor="middle" stroke="none" fill="{col}" font-family="{font}" font-size="{fs}">{label}</text>')


def file_0(p):
    """Kitchen plan v3 — graphite on white paper, hatched walls, a door swing."""
    g = "#4A4A4E"
    x0, y0, x1, y1 = 150, 110, 610, 470
    wall = 16
    hatch = f'''<pattern id="hatch" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <line x1="0" y1="0" x2="0" y2="7" stroke="{g}" stroke-width="1" stroke-opacity=".55"/></pattern>'''
    svg = f'''<svg width="800" height="600" viewBox="0 0 800 600">
<defs>{PENCIL_FILTER}{hatch}</defs>
<g filter="url(#pen)" stroke="{g}" fill="none" stroke-linecap="round" stroke-width="1.5">
  <path d="M{x0} {y0}H{x1}V{y1}H{x0 + 110}M{x0 + 30} {y1}H{x0}V{y0}" stroke-width="2"/>
  <path d="M{x0 + wall} {y0 + wall}H{x1 - wall}V{y1 - wall}H{x0 + 110}M{x0 + 30} {y1 - wall}H{x0 + wall}V{y0 + wall}" stroke-width="2"/>
  <path d="M{x0} {y0}H{x1}V{y1}H{x0 + 110}V{y1 - wall}H{x1 - wall}V{y0 + wall}H{x0 + wall}V{y1 - wall}H{x0 + 30}V{y1}H{x0}z" fill="url(#hatch)" stroke="none"/>
  <!-- window over the sink -->
  <path d="M300 {y0}h130M300 {y0 + 6}h130M300 {y0 + 11}h130M300 {y0 - 2}v{wall + 4}M430 {y0 - 2}v{wall + 4}" stroke-width="1.2" stroke="#fff"/>
  <rect x="300" y="{y0}" width="130" height="{wall}" fill="#FBFAF6" stroke="none"/>
  <path d="M300 {y0 + 4}h130M300 {y0 + 11}h130M300 {y0}v{wall}M430 {y0}v{wall}" stroke-width="1.1"/>
  <!-- door + swing -->
  <path d="M{x0 + 30} {y1}V{y1 - 80}" stroke-width="1.8"/>
  <path d="M{x0 + 30} {y1 - 80}A80 80 0 0 1 {x0 + 110} {y1 - 2}" stroke-dasharray="5 4" stroke-width="1.1"/>
  <!-- counters: along the top and the right -->
  <path d="M{x0 + wall} {y0 + wall + 60}H{x1 - wall - 60}V{y1 - wall - 90}H{x1 - wall}" stroke-width="1.6"/>
  <!-- sink -->
  <rect x="318" y="{y0 + wall + 9}" width="94" height="42" rx="7"/><rect x="324" y="{y0 + wall + 14}" width="40" height="32" rx="5"/>
  <circle cx="344" cy="{y0 + wall + 30}" r="3"/><path d="M365 {y0 + wall + 9}v-6"/>
  <!-- hob -->
  <rect x="{x1 - wall - 56}" y="220" width="50" height="92" rx="3" stroke-width="1.1"/>
  {''.join(f'<circle cx="{x1 - wall - 31 + dx}" cy="{cy}" r="{r}"/>' for dx, cy, r in [(-12, 240, 9), (12, 244, 6), (-12, 290, 6), (12, 286, 9)])}
  <!-- fridge -->
  <rect x="{x0 + wall + 4}" y="{y0 + wall + 4}" width="62" height="62" stroke-width="1.6"/>
  <path d="M{x0 + wall + 4} {y0 + wall + 4}l62 62M{x0 + wall + 66} {y0 + wall + 4}l-62 62" stroke-width=".9" stroke-opacity=".7"/>
  <!-- table and chairs -->
  <circle cx="330" cy="330" r="46" stroke-width="1.6"/>
  {''.join(f'<rect x="{330 + 64 * math.cos(a) - 13:.1f}" y="{330 + 64 * math.sin(a) - 13:.1f}" width="26" height="26" rx="5" transform="rotate({math.degrees(a) + 90:.0f} {330 + 64 * math.cos(a):.1f} {330 + 64 * math.sin(a):.1f})"/>' for a in (math.pi * .25, math.pi * .75, math.pi * 1.25, math.pi * 1.75))}
</g>
<g filter="url(#pen)" stroke="#6B6B70" stroke-width="1" fill="none">
  {dim_h(x0, x1, y0 - 34, "3400", "#3A3A3E", 18)}
  {dim_v(x0 - 34, y0, y1, "2650", "#3A3A3E", 18)}
  {dim_v(x1 - wall - 70, y0 + wall, y0 + wall + 60, "600", "#3A3A3E", 13)}
  {dim_h(300, 430, y0 + 100, "1200", "#3A3A3E", 13)}
</g>
<g font-family="{HAND}" fill="#3A3A3E">
  <text x="{x0 + 22}" y="{y0 + wall + 96}" font-size="13">fridge</text>
  <text x="420" y="{y0 + wall + 36}" font-size="13">sink</text>
  <text x="{x1 - wall - 60}" y="336" font-size="13">hob</text>
  <text x="{x0 + 50}" y="{y1 + 28}" font-size="13">door 800</text>
  <text x="310" y="336" font-size="13">table</text>
</g>
<g transform="translate(612 478)">
  <path d="M0 64h170M0 0h170v84H0z" stroke="{g}" fill="none" stroke-width="1.2" filter="url(#pen)"/>
  <text x="10" y="26" font-family="{HAND}" font-size="17" fill="#2E2E32">Kitchen plan</text>
  <text x="10" y="50" font-family="{HAND}" font-size="12" fill="#6B6B70">scale 1:25 &middot; mm</text>
  <text x="10" y="79" font-family="{HAND}" font-size="12" fill="#6B6B70">23.09</text>
  <ellipse cx="140" cy="31" rx="26" ry="18" stroke="#C0392B" stroke-width="2" fill="none" filter="url(#pen)"/>
  <text x="140" y="39" text-anchor="middle" font-family="{HAND}" font-size="22" font-weight="700" fill="#C0392B">v3</text>
</g>
<g transform="translate(690 120)" stroke="{g}" fill="none" stroke-width="1.4" filter="url(#pen)">
  <circle r="20"/><path d="M0 16V-26M-6 -18 0 -28 6 -18"/>
  <text y="44" text-anchor="middle" stroke="none" fill="{g}" font-family="{HAND}" font-size="14">N</text></g>
</svg>'''
    css = "body{background:radial-gradient(ellipse at 40% 35%,#FFFFFD,#F3F1EB 80%)}"
    return doc(p, svg, css, bg="#F6F4EE")


def file_1(p):
    """Hallway measurements — a squared-paper sheet on a desk, blue ballpoint."""
    ink = "#23408E"
    sq = 26
    plan = f'''<svg width="560" height="470" viewBox="0 -24 560 470" style="position:absolute;left:0;top:0">
<defs>{PENCIL_FILTER}</defs>
<g filter="url(#pen)" stroke="{ink}" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
  <path d="M72 108H468V198H310V410H216V198H72Z"/>
  <path d="M150 108v-16a40 40 0 0 1 40 16M390 198v16a40 40 0 0 0 40-16M216 330h-16a36 36 0 0 0 16 36M310 250h16a36 36 0 0 1-16 36" stroke-width="1.5"/>
  <rect x="226" y="360" width="10" height="44" stroke-width="1.4"/>
  <path d="M84 196h70" stroke-width="5" stroke-opacity=".35"/>
  <circle cx="460" cy="150" r="5" stroke-width="1.5"/>
</g>
<g filter="url(#pen)" stroke="{ink}" stroke-width="1.2" fill="none" font-family="{HAND}">
  {dim_h(72, 468, 80, "412 cm", ink, 17)}
  {dim_v(52, 108, 198, "96 cm", ink, 15)}
  {dim_v(372, 198, 410, "225 cm", ink, 15)}
  {dim_h(216, 310, 434, "98 cm", ink, 15)}
  <path d="M470 150h16" stroke-width="1.1"/>
</g>
<g font-family="{HAND}" fill="{ink}">
  <text x="90" y="186" font-size="13">coat hooks</text>
  <text x="252" y="400" font-size="12" transform="rotate(-90 252 400)">radiator 80</text>
  <text x="492" y="146" font-size="13">switch</text><text x="492" y="162" font-size="13">h 105</text>
  <text x="140" y="130" font-size="12">front door</text>
  <text x="384" y="236" font-size="12">bath</text>
  <text x="332" y="258" font-size="12">bed</text>
  <text x="236" y="300" font-size="13">ceiling 262</text>
</g>
</svg>'''
    body = f'''<div class="abs" style="inset:0;background:radial-gradient(ellipse at 30% 20%,#8C7B69,#5E5044 75%)"></div>
<div class="abs" style="left:112px;top:52px;width:560px;height:470px;transform:rotate(-3.2deg);background-color:#FDFDF8;
  background-image:linear-gradient(#DCE6F4 1px,transparent 1px),linear-gradient(90deg,#DCE6F4 1px,transparent 1px);
  background-size:{sq}px {sq}px;background-position:-1px -1px;
  box-shadow:0 22px 40px rgba(20,10,0,.45),0 3px 6px rgba(20,10,0,.3)">
  <div class="abs" style="left:0;right:0;top:0;height:18px;background:#FDFDF8;
    background-image:radial-gradient(circle at 9px 9px,#6A5B4D 3.5px,transparent 4px);background-size:22px 18px"></div>
  <div class="abs" style="left:26px;top:28px;font:700 23px {HAND};color:{ink}">Hallway &mdash; measurements</div>
  <div class="abs" style="left:376px;top:34px;font:400 14px {HAND};color:{ink}">Sat 20/9</div>
  {plan}
  <div class="abs" style="inset:0;background:linear-gradient(115deg,rgba(255,255,255,.35),transparent 40%,rgba(0,0,0,.05))"></div>
</div>
<div class="abs" style="left:560px;top:470px;width:250px;height:15px;transform:rotate(-24deg);transform-origin:0 50%;
  box-shadow:0 10px 12px rgba(0,0,0,.35);border-radius:2px;
  background:linear-gradient(#F2C230,#E5A91A 50%,#C98F12)">
  <div class="abs" style="left:-26px;top:0;width:0;height:0;border-top:7.5px solid transparent;border-bottom:7.5px solid transparent;border-right:26px solid #E8C9A0"></div>
  <div class="abs" style="left:-26px;top:5px;width:0;height:0;border-top:2.5px solid transparent;border-bottom:2.5px solid transparent;border-right:9px solid #333"></div>
  <div class="abs" style="right:-28px;top:0;width:18px;height:15px;background:linear-gradient(#D8D8D8,#9A9A9A)"></div>
  <div class="abs" style="right:-40px;top:0;width:14px;height:15px;border-radius:0 4px 4px 0;background:linear-gradient(#F29A9A,#D96C6C)"></div>
</div>'''
    return doc(p, body, bg="#6E5E50")


def file_2(p):
    """Shelf bracket spec — an orthographic CAD sheet with a title block."""
    k = "#1A1D24"
    thin = "stroke-width:0.9"

    def arrow_dim(x1, y1, x2, y2, label, lx, ly, rot=0):
        return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" marker-start="url(#ar)" marker-end="url(#ar)" style="{thin}"/>'
                f'<text x="{lx}" y="{ly}" text-anchor="middle" font-size="12" fill="{k}" stroke="none" transform="rotate({rot} {lx} {ly})">{label}</text>')
    def pt(x, y, z, ox=604, oy=236, sc=1.0):
        return f"{ox + (x - y) * .866 * sc:.1f},{oy + (x + y) * .5 * sc - z * sc:.1f}"

    def face(pts, fill):
        return f'<polygon points="{" ".join(pt(*q) for q in pts)}" fill="{fill}"/>'
    t, W = 6, 40
    lit, mid, dark = "#EEF2F8", "#C9D3E1", "#9FAEC4"
    iso = f'''<g stroke="{k}" stroke-width="1.2" stroke-linejoin="round">
  {face([(0, 0, 150), (t, 0, 150), (t, W, 150), (0, W, 150)], lit)}
  {face([(t, 0, t), (t, 0, 150), (t, W, 150), (t, W, t)], mid)}
  {face([(0, W, 0), (t, W, 0), (t, W, 150), (0, W, 150)], dark)}
  {face([(0, 0, t), (120, 0, t), (120, W, t), (0, W, t)], lit)}
  {face([(0, W, 0), (120, W, 0), (120, W, t), (0, W, t)], dark)}
  {face([(120, 0, 0), (120, W, 0), (120, W, t), (120, 0, t)], mid)}
  {face([(t, 17, t), (t, 17, 60), (60, 17, t)], mid)}
  {face([(t, 17, 60), (t, 23, 60), (60, 23, t), (60, 17, t)], lit)}
  {face([(t, 23, t), (t, 23, 60), (60, 23, t)], dark)}
</g>
<g fill="#fff" stroke="{k}" stroke-width="1">
  {''.join(f'<ellipse cx="{pt(t, 20, zz).split(",")[0]}" cy="{pt(t, 20, zz).split(",")[1]}" rx="4" ry="9" transform="rotate(-30 {pt(t, 20, zz).replace(",", " ")})"/>' for zz in (85, 130))}
  {''.join(f'<ellipse cx="{pt(xx, 20, t).split(",")[0]}" cy="{pt(xx, 20, t).split(",")[1]}" rx="7" ry="4" transform="rotate(30 {pt(xx, 20, t).replace(",", " ")})"/>' for xx in (80, 107))}
</g>'''
    svg = f'''<svg width="800" height="600" viewBox="0 0 800 600" font-family="'Helvetica Neue',{SANS}">
<defs><marker id="ar" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
  <path d="M0 1.5L10 5 0 8.5z" fill="{k}"/></marker>
</defs>
<rect x="16" y="16" width="768" height="568" fill="none" stroke="{k}" stroke-width="1.6"/>
<rect x="26" y="26" width="748" height="548" fill="none" stroke="{k}" stroke-width=".8"/>
{''.join(f'<text x="{26 + 187 * i + 93}" y="23" text-anchor="middle" font-size="8" fill="{k}">{i + 1}</text>' for i in range(4))}
{''.join(f'<text x="21" y="{26 + 137 * i + 70}" text-anchor="middle" font-size="8" fill="{k}">{c}</text>' for i, c in enumerate("ABCD"))}
<g stroke="{k}" fill="none" stroke-width="2" stroke-linejoin="miter">
  <!-- front view: the L with a gusset -->
  <path d="M110 110V330H290V322H118V110Z"/>
  <path d="M118 242L200 322" stroke-width="1.4"/><path d="M118 256 186 322" stroke-width="1.4"/>
  <!-- side view: the wall leg face with two slots -->
  <rect x="370" y="110" width="60" height="220"/>
  <rect x="392" y="124" width="16" height="30" rx="8" stroke-width="1.4"/><rect x="392" y="190" width="16" height="30" rx="8" stroke-width="1.4"/>
  <path d="M400 116v46M400 182v46" stroke-width=".7" stroke-dasharray="14 3 2 3"/>
  <path d="M400 330V322" stroke-width="1"/>
  <!-- top view: the shelf leg with two holes, hidden gusset -->
  <rect x="110" y="410" width="180" height="60"/>
  <circle cx="230" cy="440" r="7" stroke-width="1.4"/><circle cx="270" cy="440" r="7" stroke-width="1.4"/>
  <path d="M110 437h90M110 443h76" stroke-width="1" stroke-dasharray="6 4"/>
  <path d="M100 440h200M230 426v28M270 426v28" stroke-width=".7" stroke-dasharray="14 3 2 3"/>
</g>
<g stroke="{k}" fill="none">
  {arrow_dim(80, 110, 80, 330, "150", 70, 224, -90)}
  {arrow_dim(110, 355, 290, 355, "120", 200, 349)}
  {arrow_dim(370, 350, 430, 350, "40", 400, 344)}
  {arrow_dim(450, 139, 450, 205, "45", 462, 172, -90)}
  {arrow_dim(110, 492, 230, 492, "80", 170, 486)}
  {arrow_dim(310, 410, 310, 470, "40", 322, 444, -90)}
  <path d="M110 330v30M290 330v30M370 330v26M430 330v26M430 139h26M430 205h26M230 447v51M110 470v28M290 410h26M290 470h26" stroke-width=".6"/>
  <path d="M119 170L262 134h40" stroke-width=".8"/>
</g>
<text x="306" y="138" font-size="12" fill="{k}">t = 3</text>
<text x="206" y="400" font-size="12" fill="{k}">2 &times; &#8960;7 through</text>
<g font-size="12" fill="#4A5160"><text x="110" y="96">Front view</text><text x="370" y="96">Side view</text><text x="110" y="398">Top view</text></g>
<!-- isometric -->
{iso}
<text x="560" y="338" font-size="12" fill="#4A5160">Isometric</text>
<!-- title block -->
<g transform="translate(494 440)" font-size="11" fill="{k}">
  <rect width="280" height="134" fill="#fff" stroke="{k}" stroke-width="1.2"/>
  <path d="M0 44H280M0 74H280M0 104H280M140 74V134M210 104V134" stroke="{k}" stroke-width=".8"/>
  <text x="10" y="18" fill="#6A7080" font-size="9">Title</text>
  <text x="10" y="37" font-size="19" font-weight="600">Shelf bracket</text>
  <text x="10" y="64">Material: steel S235, 3 mm, powder coat</text>
  <text x="10" y="94">Scale 1:2</text><text x="150" y="94">Units: mm</text>
  <text x="10" y="124">Drawn 23.09.26</text><text x="150" y="124">Sheet 1/1</text><text x="220" y="124" font-weight="600">Rev B</text>
</g>
<text x="40" y="562" font-size="10" fill="#6A7080">Break all edges 0.5. Tolerances &plusmn;0.2 unless stated.</text>
</svg>'''
    return doc(p, svg, bg="#FCFCFA")


def file_4(p):
    """Plans — lighting run: a blueprint of two rooms, fittings and a cable run."""
    wl = "#EAF2FF"
    amb = "#FFB547"

    def pendant(x, y):
        return f'<g transform="translate({x} {y})"><circle r="13" fill="#123C66" stroke="{wl}" stroke-width="1.8"/><path d="M-9-9 9 9M9-9-9 9" stroke="{wl}" stroke-width="1.6"/></g>'

    def wall_light(x, y, rot):
        return f'<g transform="translate({x} {y}) rotate({rot})"><path d="M-11 0A11 11 0 0 1 11 0Z" fill="#123C66" stroke="{wl}" stroke-width="1.6"/><path d="M-5-3 5-3" stroke="{wl}" stroke-width="1.4"/></g>'

    def switch(x, y, rot, label=""):
        return (f'<g transform="translate({x} {y}) rotate({rot})"><circle r="6" fill="{wl}"/><path d="M0 0 13-13" stroke="{wl}" stroke-width="1.8"/></g>'
                + (f'<text x="{x - 14}" y="{y + 4}" text-anchor="end" font-size="11" fill="#9DB9DD">{label}</text>' if label else ""))

    def downlight(x, y):
        return f'<g transform="translate({x} {y})"><circle r="7" fill="none" stroke="{wl}" stroke-width="1.6"/><circle r="2.5" fill="{wl}"/></g>'
    svg = f'''<svg width="800" height="600" viewBox="0 0 800 600" font-family="'Avenir Next',{SANS}">
<defs><pattern id="gr" width="25" height="25" patternUnits="userSpaceOnUse"><path d="M25 0H0V25" fill="none" stroke="#244F80" stroke-width=".6"/></pattern>
<pattern id="grb" width="100" height="100" patternUnits="userSpaceOnUse"><path d="M100 0H0V100" fill="none" stroke="#33669C" stroke-width="1"/></pattern>
<radialGradient id="bg" cx=".4" cy=".4" r=".9"><stop offset="0" stop-color="#1A4C80"/><stop offset="1" stop-color="#0E2D52"/></radialGradient></defs>
<rect width="800" height="600" fill="url(#bg)"/><rect width="800" height="600" fill="url(#gr)" opacity=".55"/><rect width="800" height="600" fill="url(#grb)" opacity=".7"/>
<g stroke="{wl}" fill="none" stroke-linejoin="miter">
  <path d="M60 90H560V510H60Z" stroke-width="7"/>
  <path d="M340 90V300M340 370V510" stroke-width="5"/>
  <path d="M60 300H180M250 300H340" stroke-width="5"/>
  <path d="M340 300A70 70 0 0 1 410 370" stroke-width="1" stroke-dasharray="4 4" transform="translate(-70 0)"/>
  <path d="M130 90h110M420 90h90" stroke="#0E2D52" stroke-width="4"/><path d="M130 86h110M130 94h110M420 86h90M420 94h90" stroke-width="1.4"/>
</g>
<g fill="none" stroke="{amb}" stroke-width="2.2" stroke-dasharray="9 6" stroke-linecap="round">
  <path d="M320 470C300 420 240 410 200 400S200 200 200 195"/>
  <path d="M200 195C260 180 300 200 330 200"/>
  <path d="M320 470C340 520 400 460 450 440S450 320 450 300"/>
  <path d="M450 300C480 250 480 190 450 150"/>
  <path d="M450 300C500 300 530 300 546 300"/>
  <path d="M120 220C110 250 120 280 100 300"/>
  <path d="M200 195C170 200 140 210 120 220"/>
</g>
{pendant(200, 195)}{pendant(450, 300)}
{downlight(330, 200)}{downlight(450, 150)}{downlight(120, 220)}
{wall_light(546, 300, -90)}{wall_light(100, 300, 180)}
{switch(320, 470, 0, "S1  two-way")}
<g font-size="15" fill="{wl}" font-weight="600"><text x="120" y="140">Living room</text><text x="400" y="140">Study</text><text x="90" y="470">Hall</text></g>
<g font-size="11" fill="#9DB9DD"><text x="212" y="182">P1</text><text x="462" y="288">P2</text><text x="520" y="330">W1</text><text x="70" y="330">W2</text></g>
<g transform="translate(598 90)">
  <rect width="170" height="248" fill="#0F2F55" stroke="{wl}" stroke-width="1.2"/>
  <text x="14" y="26" font-size="14" font-weight="600" fill="{wl}">Legend</text>
  {pendant(26, 56)}<text x="48" y="61" font-size="12" fill="{wl}">Pendant</text>
  {downlight(26, 94)}<text x="48" y="99" font-size="12" fill="{wl}">Downlight</text>
  {wall_light(26, 136, 0)}<text x="48" y="137" font-size="12" fill="{wl}">Wall light</text>
  {switch(22, 176, 0)}<text x="48" y="175" font-size="12" fill="{wl}">Switch</text>
  <path d="M14 214h26" stroke="{amb}" stroke-width="2.2" stroke-dasharray="9 6"/><text x="48" y="211" font-size="12" fill="{wl}">Cable run</text>
  <text x="48" y="226" font-size="10" fill="#9DB9DD">1.5 mm&#178; T&amp;E</text>
</g>
<g transform="translate(598 380)">
  <rect width="170" height="130" fill="#0F2F55" stroke="{wl}" stroke-width="1.2"/>
  <text x="14" y="30" font-size="17" font-weight="600" fill="{wl}">Lighting run</text>
  <text x="14" y="52" font-size="12" fill="#9DB9DD" font-family="{SANS}">Ground floor, circuit L1</text>
  <path d="M0 66H170" stroke="{wl}" stroke-width=".8"/>
  <text x="14" y="88" font-size="12" fill="{wl}">Scale 1:50</text><text x="14" y="110" font-size="12" fill="{wl}">Rev 2 &middot; Sept</text>
</g>
<text x="60" y="560" font-size="13" fill="#9DB9DD">Plans &mdash; lighting run</text>
</svg>'''
    return doc(p, svg, bg="#0E2D52")


# ── saves: a whiteboard and an editor ──────────────────────────────────────

def reddit_2(p):
    """A whiteboard sequence diagram in marker: client, queue, server."""
    M = "'Marker Felt',Noteworthy,cursive"
    cols = {"Client": 170, "Queue": 400, "Server": 630}
    blue, black, red, green = "#1F4FB5", "#23262B", "#C8322B", "#1F7A45"

    def box(name, x, col):
        return (f'<rect x="{x - 66}" y="70" width="132" height="54" rx="9" fill="none" stroke="{col}" stroke-width="3.2"/>'
                f'<text x="{x}" y="106" text-anchor="middle" font-family="{M}" font-size="24" fill="{col}">{name}</text>'
                f'<path d="M{x} 126V508" stroke="{col}" stroke-width="2" stroke-dasharray="3 11" stroke-linecap="round"/>')

    def msg(a, b, y, label, col, dashed=False):
        x1, x2 = cols[a], cols[b]
        d = 1 if x2 > x1 else -1
        dash = ' stroke-dasharray="12 9"' if dashed else ""
        return (f'<path d="M{x1 + 6 * d} {y}Q{(x1 + x2) / 2} {y - 5} {x2 - 8 * d} {y + 1}" fill="none" stroke="{col}" stroke-width="2.8"{dash} stroke-linecap="round"/>'
                f'<path d="M{x2 - 22 * d} {y - 9}L{x2 - 7 * d} {y + 1} {x2 - 22 * d} {y + 11}" fill="none" stroke="{col}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>'
                f'<text x="{(x1 + x2) / 2}" y="{y - 12}" text-anchor="middle" font-family="{M}" font-size="19" fill="{col}">{label}</text>')
    svg = f'''<svg width="800" height="600" viewBox="0 0 800 600" filter="url(#pen)">
<defs>{PENCIL_FILTER}</defs>
{box("Client", 170, blue)}{box("Queue", 400, black)}{box("Server", 630, green)}
{msg("Client", "Queue", 172, "1. enqueue(op)", blue)}
{msg("Queue", "Client", 220, "2. ack (local)", blue, True)}
{msg("Queue", "Server", 272, "3. flush batch", black)}
{msg("Server", "Queue", 322, "4. 409 conflict", red, True)}
<path d="M406 352c60-6 60 44 2 42" fill="none" stroke="{black}" stroke-width="2.8" stroke-linecap="round"/>
<path d="M424 386 406 394 421 405" fill="none" stroke="{black}" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>
<text x="470" y="382" font-family="{M}" font-size="19" fill="{black}">5. rebase + retry</text>
{msg("Queue", "Server", 432, "6. flush again", black)}
{msg("Server", "Queue", 470, "200 OK", green, True)}
{msg("Queue", "Client", 500, "7. confirm", blue, True)}
<g transform="rotate(-6 150 400)"><ellipse cx="150" cy="392" rx="96" ry="40" fill="none" stroke="{red}" stroke-width="2.8"/>
<text x="150" y="386" text-anchor="middle" font-family="{M}" font-size="18" fill="{red}">idempotency</text>
<text x="150" y="408" text-anchor="middle" font-family="{M}" font-size="18" fill="{red}">key per op!</text></g>
<path d="M240 378C290 360 300 340 334 330" fill="none" stroke="{red}" stroke-width="2.4" stroke-linecap="round"/>
<text x="40" y="44" font-family="{M}" font-size="22" fill="{black}">sync v2 &mdash; happy path + conflict</text>
</svg>'''
    ghosts = "".join(f'<div class="abs" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;border-radius:40%;background:rgba(120,130,140,.045);filter:blur(10px)"></div>'
                     for x, y, w, h in [(560, 40, 190, 28), (40, 520, 150, 24), (520, 170, 120, 20)])
    body = f'''<div class="abs" style="inset:0;background:linear-gradient(160deg,#F4F6F7 0%,#FFFFFF 35%,#EEF1F3 60%,#FBFCFC 80%,#E9ECEF)"></div>
{ghosts}
<div class="abs" style="left:-60px;top:-40px;width:420px;height:700px;transform:rotate(20deg);background:linear-gradient(90deg,transparent,rgba(255,255,255,.7),transparent)"></div>
{svg.replace('<svg ', '<svg class="abs" style="left:0;top:0" ', 1)}
<div class="abs" style="left:0;right:0;top:0;height:10px;background:linear-gradient(#B9BEC4,#E3E6E9)"></div>
<div class="abs" style="left:0;right:0;bottom:0;height:34px;background:linear-gradient(#CDD2D7,#9EA4AB);box-shadow:0 -2px 6px rgba(0,0,0,.15)"></div>
{''.join(f'<div class="abs" style="left:{x}px;bottom:14px;width:118px;height:17px;border-radius:9px;background:linear-gradient({c1},{c2});box-shadow:0 3px 4px rgba(0,0,0,.25)"><div class="abs" style="right:0;top:0;width:34px;height:17px;border-radius:0 9px 9px 0;background:{cap}"></div></div>'
         for x, c1, c2, cap in [(470, "#F5F5F5", "#CFCFCF", blue), (604, "#F5F5F5", "#CFCFCF", red)])}'''
    return doc(p, body, bg="#F4F6F7")


def reddit_3(p):
    """A desktop editor, dark, on a tiny tokenizer."""
    lines = [
        "// lexer.ts — turn source text into tokens",
        "export type Token =",
        "  | { kind: \"num\"; value: number }",
        "  | { kind: \"ident\"; name: string }",
        "  | { kind: \"op\"; op: string };",
        "",
        "export function tokenize(src: string): Token[] {",
        "  const out: Token[] = [];",
        "  let i = 0;",
        "  while (i < src.length) {",
        "    const c = src[i];",
        "    if (/\\s/.test(c)) { i++; continue; }",
        "    if (/\\d/.test(c)) {",
        "      let j = i;",
        "      while (/\\d/.test(src[j])) j++;",
        "      out.push({ kind: \"num\", value: Number(src.slice(i, j)) });",
        "      i = j; continue;",
        "    }",
        "    if (/\\w/.test(c)) {",
        "      let j = i;",
        "      while (/\\w/.test(src[j] ?? \"\")) j++;",
        "      out.push({ kind: \"ident\", name: src.slice(i, j) });",
        "      i = j; continue;",
        "    }",
        "    out.push({ kind: \"op\", op: c }); i++;",
        "  }",
        "  return out;",
        "}",
    ]
    code = code_block(lines, TS_KW, ONE_DARK, 12, 17.5, 40, "#4B5263", active=15, active_bg="#2C313C")
    tree = [("&#9662; src", 0, False), ("lexer.ts", 1, True), ("parser.ts", 1, False), ("check.ts", 1, False), ("emit.ts", 1, False),
            ("&#9656; test", 0, False), ("package.json", 0, False), ("README.md", 0, False)]
    tree_html = "".join(f'<div style="height:22px;line-height:22px;padding-left:{14 + 14 * d}px;font:12.5px {SANS};'
                        f'color:{"#D7DAE0" if sel else "#9DA5B4"};background:{"#2C313A" if sel else "transparent"}">{n}</div>'
                        for n, d, sel in tree)
    mini = "".join(f'<div style="height:2px;margin:1.5px 0;width:{w}px;background:{c};opacity:.55"></div>' for w, c in [
        (40, "#7F848E"), (20, "#C678DD"), (30, "#E5C07B"), (32, "#98C379"), (28, "#98C379"), (0, "#000"), (46, "#61AFEF"),
        (24, "#C678DD"), (12, "#C678DD"), (26, "#ABB2BF"), (18, "#ABB2BF"), (34, "#98C379"), (22, "#98C379"), (12, "#ABB2BF"),
        (30, "#98C379"), (56, "#61AFEF"), (18, "#ABB2BF"), (6, "#ABB2BF"), (22, "#98C379"), (12, "#ABB2BF"), (36, "#98C379"),
        (48, "#61AFEF"), (18, "#ABB2BF"), (6, "#ABB2BF"), (34, "#E06C75"), (4, "#ABB2BF"), (12, "#C678DD")])
    tab = lambda n, on: (f'<div style="height:34px;line-height:34px;padding:0 16px;font:12.5px {SANS};color:{"#D7DAE0" if on else "#7D8594"};'
                         f'background:{"#23272E" if on else "transparent"};border-top:2px solid {"#528BFF" if on else "transparent"}">{n}</div>')
    body = f'''<div class="abs" style="inset:0;background:#23272E"></div>
<div class="abs" style="left:0;right:0;top:0;height:30px;background:#1B1E23;display:flex;align-items:center;padding-left:12px;gap:8px">
  {''.join(f'<span style="width:12px;height:12px;border-radius:6px;background:{c}"></span>' for c in ("#FF5F57", "#FEBC2E", "#28C840"))}
  <span style="flex:1;text-align:center;font:12.5px {SANS};color:#9DA5B4;margin-right:60px">lexer.ts &mdash; tiny-compiler</span></div>
<div class="abs" style="left:0;top:30px;bottom:24px;width:176px;background:#1E2227;padding-top:10px">
  <div style="font:600 11px {SANS};color:#7D8594;padding:0 14px 8px;">Explorer</div>{tree_html}</div>
<div class="abs" style="left:176px;right:0;top:30px;height:34px;background:#1E2227;display:flex">{tab("lexer.ts", True)}{tab("parser.ts", False)}{tab("README.md", False)}</div>
<div class="abs" style="left:176px;right:64px;top:70px;bottom:24px;overflow:hidden">{code}</div>
<div class="abs" style="right:0;top:70px;width:64px;bottom:24px;padding:4px 8px">
  <div class="abs" style="left:4px;right:4px;top:70px;height:60px;background:rgba(255,255,255,.06)"></div>{mini}</div>
<div class="abs" style="left:0;right:0;bottom:0;height:24px;background:#21252B;display:flex;align-items:center;gap:18px;padding:0 12px;
  font:11.5px {SANS};color:#9DA5B4"><span style="color:#D7DAE0">main</span><span>0 problems</span><span style="flex:1"></span>
  <span>Ln 16, Col 54</span><span>Spaces: 2</span><span>UTF-8</span><span>TypeScript</span></div>'''
    return doc(p, body, bg="#23272E")


# ── channel graphics ───────────────────────────────────────────────────────

def tg_2(p):
    """Info channel graphic: scheduled messages — a phone and a calendar tile."""
    bubble = lambda text, out, extra="": (
        f'<div style="align-self:{"flex-end" if out else "flex-start"};max-width:78%;background:{"#E1FFC7" if out else "#fff"};'
        f'border-radius:14px;padding:7px 10px 6px;font:400 12.5px/1.35 {SANS};color:#111;box-shadow:0 1px 1px rgba(0,0,0,.08)">{text}{extra}</div>')
    sched = (f'<div style="display:flex;align-items:center;gap:5px;margin-top:5px;font:600 10.5px {SANS};color:#3A9A4A">'
             f'<svg width="11" height="11" viewBox="0 0 11 11"><circle cx="5.5" cy="5.5" r="4.6" fill="none" stroke="#3A9A4A" stroke-width="1.3"/>'
             f'<path d="M5.5 3v2.7l1.8 1.1" stroke="#3A9A4A" stroke-width="1.3" fill="none" stroke-linecap="round"/></svg>Scheduled &middot; Tue 09:00</div>')
    phone = f'''<div class="abs" style="left:470px;top:62px;width:240px;height:470px;border-radius:40px;background:#0E1A26;padding:9px;
  box-shadow:0 30px 60px rgba(8,40,90,.45),inset 0 0 0 1.5px rgba(255,255,255,.12);transform:rotate(6deg)">
  <div style="width:100%;height:100%;border-radius:32px;overflow:hidden;background:linear-gradient(160deg,#CFE3C8,#B7D6C9 50%,#C9D9B4);position:relative">
    <div style="height:74px;background:rgba(247,247,247,.96);padding:30px 14px 0;display:flex;align-items:center;gap:9px">
      <span style="width:30px;height:30px;border-radius:15px;background:linear-gradient(#F7B35B,#F08A3C);display:grid;place-items:center;color:#fff;font:600 13px {SANS}">P</span>
      <div><div style="font:600 13px {SANS};color:#111">Project room</div><div style="font:400 11px {SANS};color:#8A8A8E">3 members</div></div></div>
    <div style="display:flex;flex-direction:column;gap:7px;padding:14px 10px">
      <div style="align-self:center;background:rgba(0,0,0,.18);color:#fff;font:600 10.5px {SANS};padding:3px 9px;border-radius:10px">Today</div>
      {bubble("Can someone send the notes to the client before the call?", False)}
      {bubble("I'll queue them for the morning", True)}
      {bubble("Hi both &mdash; the notes from Friday are attached. Talk at ten.", True, sched)}
    </div>
    <div class="abs" style="left:0;right:0;bottom:0;height:52px;background:rgba(247,247,247,.96);display:flex;align-items:center;gap:8px;padding:0 10px">
      <div style="flex:1;height:30px;border-radius:15px;background:#fff;border:1px solid #DADADF"></div>
      <span style="width:30px;height:30px;border-radius:15px;background:#3A9CE0;display:grid;place-items:center">
        <svg width="14" height="14" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5.2" fill="none" stroke="#fff" stroke-width="1.6"/><path d="M7 4v3.3l2 1.3" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round"/></svg></span></div>
  </div></div>'''
    cal = f'''<div class="abs" style="left:400px;top:290px;width:118px;height:118px;border-radius:26px;background:#fff;overflow:hidden;transform:rotate(-8deg);
  box-shadow:0 22px 40px rgba(8,40,90,.4)">
  <div style="height:32px;background:linear-gradient(#FF6B5E,#F0473A);color:#fff;font:700 15px {SANS};text-align:center;line-height:32px">Tue</div>
  <div style="font:300 60px/82px {SANS};color:#1A1A1A;text-align:center;letter-spacing:-2px">24</div></div>'''
    body = f'''<div class="abs" style="inset:0;background:radial-gradient(circle at 78% 30%,#6FD0FF 0%,transparent 45%),linear-gradient(135deg,#1F8FE0,#2AABEE 45%,#1C74D0)"></div>
<div class="abs" style="left:-80px;bottom:-160px;width:420px;height:420px;border-radius:50%;background:rgba(255,255,255,.07)"></div>
<div class="abs" style="left:250px;top:-120px;width:260px;height:260px;border-radius:50%;background:rgba(255,255,255,.06)"></div>
<div class="abs" style="left:60px;top:118px;width:340px;color:#fff">
  <div style="display:inline-block;font:600 13px {SANS};background:rgba(255,255,255,.2);padding:5px 12px;border-radius:14px">New in chats</div>
  <div style="font:800 46px/1.02 {SANS};letter-spacing:-1.4px;margin-top:18px">Scheduled<br>messages</div>
  <div style="font:400 18px/1.4 {SANS};opacity:.9;margin-top:16px">Write it now. Pick a day and a time,<br>and it goes out then &mdash; on its own.</div>
</div>
{phone}{cal}'''
    return doc(p, body, bg="#2AABEE")


def tg_4(p):
    """News channel graphic: a watch face with a chat list, on deep blue."""
    chats = [("M", "#F5A623", "Maya", "See you at 7?", "09:58"), ("R", "#7ED321", "Run club", "Route is up", "09:40"),
             ("D", "#BD10E0", "Dev notes", "Build 42 is out", "09:12"), ("H", "#FF6F61", "Home", "Keys under the pot", "08:30")]
    rows = "".join(f'''<div style="display:flex;align-items:center;gap:9px;padding:7px 4px">
  <span style="width:30px;height:30px;border-radius:15px;background:{c};display:grid;place-items:center;color:#fff;font:700 13px {SANS};flex:none">{i}</span>
  <div style="flex:1;min-width:0"><div style="display:flex;justify-content:space-between;font:600 13px {SANS};color:#fff">{n}<span style="font:400 10px {SANS};color:#8E8E93">{t}</span></div>
  <div style="font:400 11.5px {SANS};color:#9A9AA0;white-space:nowrap;overflow:hidden">{m}</div></div></div>''' for i, c, n, m, t in chats)
    band = "linear-gradient(90deg,#1A2436,#2B3850 50%,#1A2436)"
    watch = f'''<div class="abs" style="left:150px;top:-20px;width:176px;height:120px;border-radius:0 0 20px 20px;background:{band}"></div>
<div class="abs" style="left:150px;bottom:-20px;width:176px;height:120px;border-radius:20px 20px 0 0;background:{band}"></div>
<div class="abs" style="left:122px;top:86px;width:232px;height:278px;border-radius:62px;background:linear-gradient(145deg,#5C6273,#2A2F3A 45%,#14171D);
  box-shadow:0 36px 60px rgba(0,10,40,.55),inset 0 1px 1px rgba(255,255,255,.35);padding:12px">
  <div style="width:100%;height:100%;border-radius:52px;background:#000;padding:22px 16px 10px;overflow:hidden">
    <div style="display:flex;justify-content:space-between;align-items:center;margin:0 8px 6px">
      <span style="font:700 16px {SANS};color:#3AA0F2">Chats</span><span style="font:600 14px {SANS};color:#fff">10:09</span></div>
    {rows}</div></div>
<div class="abs" style="left:350px;top:170px;width:14px;height:44px;border-radius:5px;background:linear-gradient(90deg,#5A6070,#2C313C);
  box-shadow:inset 0 0 0 1px rgba(255,255,255,.1)"></div>
<div class="abs" style="left:352px;top:236px;width:8px;height:56px;border-radius:4px;background:#3A404C"></div>'''
    body = f'''<div class="abs" style="inset:0;background:radial-gradient(circle at 26% 55%,#3D7BFF 0%,transparent 50%),linear-gradient(120deg,#0B2A78,#143CA8 50%,#2657D6)"></div>
<div class="abs" style="left:40px;top:40px;width:400px;height:400px;border-radius:50%;border:1px solid rgba(255,255,255,.12)"></div>
<div class="abs" style="left:90px;top:90px;width:300px;height:300px;border-radius:50%;border:1px solid rgba(255,255,255,.1)"></div>
{watch}
<div class="abs" style="left:430px;top:128px;width:330px;color:#fff">
  <div style="font:600 13px {SANS};color:#9CC3FF">Update &middot; Watch</div>
  <div style="font:800 44px/1.04 {SANS};letter-spacing:-1.3px;margin-top:12px">Your chats,<br>on your wrist</div>
  <div style="font:400 17px/1.45 {SANS};color:#D5E3FF;margin-top:16px">Read the newest first, answer with a<br>tap or your voice, and leave the phone<br>in your pocket.</div>
</div>'''
    return doc(p, body, bg="#143CA8")


# ── photo of a laptop dashboard ────────────────────────────────────────────

def fc_0(p):
    """A photographed laptop screen: a dark dashboard of small charts and a treemap."""
    def spark(pts, col, fill=True):
        d = " ".join(f"{i * 100 / (len(pts) - 1):.1f},{40 - v * 0.38:.1f}" for i, v in enumerate(pts))
        f = f'<polygon points="0,40 {d} 100,40" fill="{col}" fill-opacity=".18"/>' if fill else ""
        return f'<svg viewBox="0 0 100 40" preserveAspectRatio="none" style="width:100%;height:46px">{f}<polyline points="{d}" fill="none" stroke="{col}" stroke-width="1.6" vector-effect="non-scaling-stroke"/></svg>'

    def card(title, val, inner, col=1):
        return (f'<div style="grid-column:span {col};background:#161B24;border-radius:8px;padding:9px 11px">'
                f'<div style="font:500 9px {SANS};color:#7C8698">{title}</div><div style="font:600 17px {SANS};color:#E8ECF3;margin:2px 0 4px">{val}</div>{inner}</div>')
    bars = "".join(f'<div style="flex:1;height:{h}%;background:{"#8B7CF6" if i == 9 else "#3F4A6B"};border-radius:2px"></div>' for i, h in enumerate([40, 55, 35, 60, 72, 50, 66, 80, 58, 92, 70, 64]))
    tm = [(0, 0, 46, 60, "#2E7D6B", "Wallet"), (46, 0, 30, 36, "#3F5FA8", "Social"), (76, 0, 24, 36, "#8B5A9E", "Reading"),
          (46, 36, 20, 24, "#A8743F", "Photos"), (66, 36, 34, 24, "#3D6E8F", "Work"), (0, 60, 28, 40, "#6A4FA0", "Agents"),
          (28, 60, 38, 40, "#2F7F8F", "Mail"), (66, 60, 34, 40, "#7F4A5A", "Calendar")]
    tmap = "".join(f'<div class="abs" style="left:{x}%;top:{y}%;width:{w}%;height:{h}%;padding:1.5px"><div style="width:100%;height:100%;background:{c};border-radius:4px;'
                   f'font:600 9px {SANS};color:rgba(255,255,255,.85);padding:5px 6px">{n}</div></div>' for x, y, w, h, c, n in tm)
    donut = ('<svg viewBox="0 0 42 42" style="width:62px;height:62px"><circle cx="21" cy="21" r="15.9" fill="none" stroke="#243047" stroke-width="5"/>'
             '<circle cx="21" cy="21" r="15.9" fill="none" stroke="#F2B84B" stroke-width="5" stroke-dasharray="62 38" transform="rotate(-90 21 21)"/>'
             '<circle cx="21" cy="21" r="15.9" fill="none" stroke="#56C2A6" stroke-width="5" stroke-dasharray="22 78" stroke-dashoffset="-62" transform="rotate(-90 21 21)"/></svg>')
    screen = f'''<div style="width:100%;height:100%;background:#0D1117;padding:12px 14px;font-family:{SANS}">
  <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
    <span style="width:14px;height:14px;border-radius:4px;background:linear-gradient(135deg,#8B7CF6,#56C2A6)"></span>
    <span style="font:600 13px {SANS};color:#E8ECF3">Panel</span><span style="font:400 10px {SANS};color:#6B7486">every room, one place</span>
    <span style="flex:1"></span><span style="font:500 9px {SANS};color:#7C8698;background:#161B24;padding:3px 8px;border-radius:10px">Last 30 days</span></div>
  <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:8px">
    {card("Things kept", "4,812", spark([20, 26, 24, 34, 38, 36, 48, 52, 60, 58, 70, 78], "#56C2A6"))}
    {card("Wallet", "$12,340", spark([50, 46, 52, 58, 54, 62, 60, 66, 72, 68, 74, 80], "#8B7CF6"))}
    {card("Replies", "128", spark([30, 60, 40, 70, 50, 44, 80, 62, 58, 90, 64, 72], "#F2B84B", False))}
    {card("Reading", "36 h", f'<div style="display:flex;align-items:flex-end;gap:3px;height:46px">{bars}</div>')}
  </div>
  <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:8px">
    <div style="background:#161B24;border-radius:8px;padding:9px 11px">
      <div style="font:500 9px {SANS};color:#7C8698;margin-bottom:6px">Rooms by size</div>
      <div style="position:relative;height:172px">{tmap}</div></div>
    <div style="display:flex;flex-direction:column;gap:8px">
      <div style="background:#161B24;border-radius:8px;padding:9px 11px;display:flex;gap:10px;align-items:center">{donut}
        <div style="font:500 9px/1.7 {SANS};color:#9AA4B6"><span style="color:#F2B84B">&#9679;</span> Saved<br><span style="color:#56C2A6">&#9679;</span> Synced<br><span style="color:#3A4660">&#9679;</span> Idle</div></div>
      {card("Activity", "Today", spark([10, 30, 22, 50, 40, 64, 30, 44, 70, 52, 84, 60], "#5AA9F2"))}
    </div></div>
</div>'''
    body = f'''<div class="abs" style="inset:0;background:radial-gradient(ellipse at 82% 20%,#3B2A1C 0%,transparent 45%),radial-gradient(ellipse at 50% 60%,#1A1E27,#07080B 80%)"></div>
{''.join(f'<div class="abs" style="left:{x}px;top:{y}px;width:{r}px;height:{r}px;border-radius:50%;background:{c};filter:blur({b}px)"></div>' for x, y, r, c, b in [
        (660, 30, 90, 'rgba(255,170,90,.35)', 18), (720, 110, 50, 'rgba(255,200,120,.3)', 12), (40, 60, 70, 'rgba(120,150,255,.15)', 20)])}
<div class="abs" style="left:50%;top:50%;width:660px;height:430px;margin:-250px 0 0 -330px;perspective:1100px">
  <div style="width:100%;height:100%;transform:rotateY(-14deg) rotateX(7deg) rotateZ(-1deg);transform-origin:50% 60%;position:relative">
    <div class="abs" style="inset:0;border-radius:18px;background:linear-gradient(#1C1F25,#0F1115);padding:14px 14px 22px;
      box-shadow:0 40px 80px rgba(0,0,0,.7),0 0 0 1.5px #2C3038,0 0 90px rgba(90,110,200,.18)">
      <div style="width:100%;height:100%;border-radius:4px;overflow:hidden;position:relative;filter:blur(.35px)">{screen}
        <div class="abs" style="inset:0;background:linear-gradient(118deg,rgba(255,255,255,.10) 0%,rgba(255,255,255,.02) 38%,transparent 55%)"></div></div>
    </div>
    <div class="abs" style="left:-40px;right:-40px;bottom:-40px;height:26px;border-radius:0 0 14px 14px;
      background:linear-gradient(#5A5E66,#2A2D33 40%,#15171A);box-shadow:0 20px 40px rgba(0,0,0,.6)"></div>
  </div>
</div>
<div class="abs" style="inset:0;background:radial-gradient(ellipse at 50% 45%,transparent 55%,rgba(0,0,0,.55))"></div>'''
    css = "body{filter:saturate(.95)}"
    return doc(p, body, css, bg="#07080B")


# ── a paper figure ─────────────────────────────────────────────────────────

def hf_paper_1(p):
    """Figure 1 from 'Scaling laws for retrieval': log-log recall vs corpus size."""
    L, R, T, B = 110, 560, 40, 440
    xs = [4, 5, 6, 7, 8]  # log10 corpus size

    def px(lx):
        return L + (lx - 4) / 4 * (R - L)

    def py(ly):  # log10 recall, from log10(0.2) to 0
        lo = math.log10(0.2)
        return B - (ly - lo) / (0 - lo) * (B - T)
    models = [("110M", "#3B6FB6", "circle", 0.90, 0.105), ("350M", "#D9822B", "square", 0.92, 0.075), ("1.3B", "#3E9651", "tri", 0.94, 0.045)]
    def marker(mk, cx, cy, col):
        if mk == "circle":
            return f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="4.6" fill="{col}" stroke="#fff" stroke-width="1"/>'
        if mk == "square":
            return f'<rect x="{cx - 4.3:.1f}" y="{cy - 4.3:.1f}" width="8.6" height="8.6" fill="{col}" stroke="#fff" stroke-width="1"/>'
        return f'<path d="M{cx:.1f} {cy - 5.5:.1f}l5.3 9.2h-10.6z" fill="{col}" stroke="#fff" stroke-width="1"/>'
    series = ""
    for name, col, mk, a, slope in models:
        pts = [(x, math.log10(a) - slope * (x - 4) * (1 + 0.02 * ((x * 7) % 3 - 1))) for x in [4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8]]
        fit = f'<line x1="{px(4):.1f}" y1="{py(math.log10(a)):.1f}" x2="{px(8):.1f}" y2="{py(math.log10(a) - slope * 4):.1f}" stroke="{col}" stroke-width="1.2" stroke-dasharray="5 4" opacity=".7"/>'
        poly = " ".join(f"{px(x):.1f},{py(y):.1f}" for x, y in pts)
        marks = "".join(marker(mk, px(x), py(y), col) for x, y in pts)
        series += fit + f'<polyline points="{poly}" fill="none" stroke="{col}" stroke-width="2"/>' + marks
    grid = ""
    for x in xs:
        grid += f'<line x1="{px(x):.1f}" x2="{px(x):.1f}" y1="{T}" y2="{B}" stroke="#E4E4E4"/>'
        grid += f'<text x="{px(x):.1f}" y="{B + 24}" text-anchor="middle" font-size="16">10<tspan dy="-7" font-size="11">{x}</tspan></text>'
        if x < 8:
            for m in range(2, 10):
                mx = px(x + math.log10(m))
                grid += f'<line x1="{mx:.1f}" x2="{mx:.1f}" y1="{B}" y2="{B - 4}" stroke="#222"/>'
        grid += f'<line x1="{px(x):.1f}" x2="{px(x):.1f}" y1="{B}" y2="{B - 8}" stroke="#222"/>'
    for v in (0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1.0):
        y = py(math.log10(v))
        major = v in (0.2, 0.5, 1.0)
        grid += f'<line x1="{L}" x2="{R}" y1="{y:.1f}" y2="{y:.1f}" stroke="{"#E4E4E4" if major else "#F1F1F1"}"/>'
        grid += f'<line x1="{L}" x2="{L + (8 if major else 4)}" y1="{y:.1f}" y2="{y:.1f}" stroke="#222"/>'
        grid += f'<text x="{L - 10}" y="{y + 5:.1f}" text-anchor="end" font-size="15">{v:.1f}</text>'
    legend = "".join(f'<g transform="translate(0 {i * 24})"><line x1="0" x2="28" y1="0" y2="0" stroke="{c}" stroke-width="2"/>'
                     f'{marker(m, 14, 0, c)}<text x="38" y="5" font-size="15">{n} params</text></g>' for i, (n, c, m, *_r) in enumerate(models))
    svg = f'''<svg width="800" height="600" viewBox="0 0 800 600" font-family="{SERIF}" fill="#1A1A1A">
{grid}
<rect x="{L}" y="{T}" width="{R - L}" height="{B - T}" fill="none" stroke="#222" stroke-width="1.2"/>
{series}
<g transform="translate({R + 26} {T + 30})">
  <text x="0" y="-8" font-size="15" font-style="italic">Retriever</text>{legend}
  <g transform="translate(0 84)"><line x1="0" x2="28" y1="0" y2="0" stroke="#666" stroke-width="1.2" stroke-dasharray="5 4"/><text x="38" y="5" font-size="15">power-law fit</text></g>
</g>
<text x="{(L + R) / 2}" y="{B + 50}" text-anchor="middle" font-size="17">Corpus size (documents)</text>
<text transform="translate(52 {(T + B) / 2}) rotate(-90)" text-anchor="middle" font-size="17">Recall@10</text>
<text x="{R - 10}" y="{T + 22}" text-anchor="end" font-size="14" fill="#555" font-style="italic">R &#8733; N<tspan dy="-6" font-size="10">&#8722;&#945;</tspan></text>
</svg>'''
    body = f'''<div class="abs" style="left:0;top:0">{svg}</div>
<div class="abs" style="left:60px;right:60px;top:522px;font:15px/1.4 {SERIF};color:#1A1A1A;text-align:justify">
  <b>Figure 1:</b> Recall@10 against corpus size on log&ndash;log axes, for three retriever sizes. Each follows a power law
  (dashed fits); the larger retriever&rsquo;s exponent is less than half the smallest&rsquo;s, so the gap widens as the corpus grows.</div>'''
    return doc(p, body, bg="#fff")


# ── dispatch ───────────────────────────────────────────────────────────────

BUILDERS = {
    "shot-5": shot_5, "shot-6": shot_6, "shot-7": shot_7, "shot-8": shot_8,
    "shot-9": shot_9, "shot-10": shot_10, "shot-11": shot_11, "shot-12": shot_12,
    "file-0": file_0, "file-1": file_1, "file-2": file_2, "file-4": file_4,
    "reddit-2": reddit_2, "reddit-3": reddit_3,
    "tg-2": tg_2, "tg-4": tg_4,
    "fc-0": fc_0, "hf-paper-1": hf_paper_1,
}


def html(p):
    build = BUILDERS.get(p["key"])
    if build is None:
        raise KeyError(f"fam_ui has no drawing for {p['key']}")
    return build(p)
