#!/usr/bin/env python3
"""App-icon variant audit (prd §869).

iOS 18 lets the person choose Light, Dark, Tinted or Clear for every icon on
the Home Screen, and `AppIcon.appiconset` declares one PNG per luminosity.
**The light PNG was a byte-for-byte copy of the dark one** — same md5 — so
everybody on the light or default appearance got the dark drawing, hot pink on
a black tile, on a light home screen.

Nothing in the pass could see it. The asset compiler is happy to ship the same
bytes twice, a build is green, and the screen sweep only ever photographs
surfaces the APP draws — the home screen is composited by the system and is
outside every check we own. The icon README had even flagged the light and
tinted PNGs as never opened, and that note sat there rather than failing
anything. That is the whole reason this is mechanical: a duplicate file is
invisible to a human reading a diff of a binary, and forever.

The rules, from design/app-icon/README.md:
  1. Contents.json declares a default, a `dark` and a `tinted` luminosity.
  2. Every declared file exists and is a 1024x1024 8-bit truecolour PNG.
  3. No two variants are byte-identical — that is the shipped defect.
  4. The light variant's ground is LIGHT; the dark and tinted grounds are dark.
  5. The tinted variant is greyscale (the system maps luminance to the tint).
  6. All three carry the SAME coverage mask. The eyes and suckers are knocked
     OUT of the mark, so they are the ground; a variant redrawn by hand loses
     that and the arms stop reading. Deriving light from dark keeps it for
     free (design/app-icon/make-light-icon.py).

Usage:  scripts/app-icon-audit.py [--self-test]
Exit 0 = clean.
"""

import sys
import json
import zlib
import struct
import pathlib
import tempfile
import itertools

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Casberi/Casberi/Assets.xcassets/AppIcon.appiconset"

SIDE = 1024
# A pixel counts as mark rather than ground once it is this far (sum of the
# three channel deltas) from the variant's own corner pixel.
MARK_CUTOFF = 60
# How far two variants' masks may disagree. Measured on the shipped three at
# the time of writing: worst pair 0.079%, so this is ~6x headroom and still
# nowhere near the many-percent a different drawing would cost.
MASK_TOLERANCE = 0.005


def read_png(path):
    """Decode an 8-bit truecolour PNG to (w, h, rgb bytes). Stdlib only."""
    blob = path.read_bytes()
    if blob[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png")
    i, idat, w, h = 8, b"", None, None
    while i < len(blob):
        n = struct.unpack(">I", blob[i:i + 4])[0]
        tag, data = blob[i + 4:i + 8], blob[i + 8:i + 8 + n]
        if tag == b"IHDR":
            w, h, bd, ct, comp, filt, inter = struct.unpack(">IIBBBBB", data)
            if bd != 8 or ct != 2 or comp or filt or inter:
                raise ValueError(f"expected 8-bit truecolour rgb, got depth {bd} type {ct}")
        elif tag == b"IDAT":
            idat += data
        i += 12 + n
    raw = zlib.decompress(idat)
    stride, out, prev, pos = w * 3, bytearray(w * h * 3), bytearray(w * 3), 0
    for y in range(h):
        ft = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos + stride]); pos += stride
        if ft == 1:
            for x in range(3, stride):
                line[x] = (line[x] + line[x - 3]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                a = line[x - 3] if x >= 3 else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - 3] if x >= 3 else 0
                b, c = prev[x], (prev[x - 3] if x >= 3 else 0)
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 255
        elif ft != 0:
            raise ValueError(f"bad filter {ft}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, out


def variants(contents):
    """Map luminosity name -> filename, from an asset catalog's Contents.json."""
    found = {}
    for entry in contents.get("images", []):
        name = entry.get("filename")
        if not name:
            continue
        lum = "light"
        for app in entry.get("appearances", []):
            if app.get("appearance") == "luminosity":
                lum = app.get("value")
        found[lum] = name
    return found


def mask_of(rgb, count):
    ground = tuple(rgb[0:3])
    mask = bytearray(count)
    for i in range(count):
        j = i * 3
        if (abs(rgb[j] - ground[0]) + abs(rgb[j + 1] - ground[1])
                + abs(rgb[j + 2] - ground[2])) > MARK_CUTOFF:
            mask[i] = 1
    return ground, mask


def audit(iconset, side=SIDE):
    findings = []
    cjson = iconset / "Contents.json"
    if not cjson.exists():
        return [f"{iconset.name}: no Contents.json"]
    try:
        contents = json.loads(cjson.read_text())
    except ValueError as exc:
        return [f"Contents.json does not parse: {exc}"]

    declared = variants(contents)
    for want in ("light", "dark", "tinted"):
        if want not in declared:
            findings.append(
                f"Contents.json declares no {want} variant — iOS 18 lets the "
                f"person pick it, so it has to exist")
    if findings:
        return findings

    # 2. every file present, right size, decodable
    pixels, blobs = {}, {}
    for lum, name in declared.items():
        path = iconset / name
        if not path.exists():
            findings.append(f"{lum}: Contents.json names {name}, which is not in the iconset")
            continue
        blobs[lum] = path.read_bytes()
        try:
            w, h, rgb = read_png(path)
        except ValueError as exc:
            findings.append(f"{lum} ({name}): {exc}")
            continue
        if (w, h) != (side, side):
            findings.append(f"{lum} ({name}): {w}x{h}, expected {side}x{side}")
            continue
        pixels[lum] = (w, h, rgb)
    if findings:
        return findings

    # 3. THE SHIPPED DEFECT: two variants that are the same file
    for a, b in itertools.combinations(sorted(blobs), 2):
        if blobs[a] == blobs[b]:
            findings.append(
                f"{a} and {b} are byte-identical ({declared[a]} == {declared[b]}) — "
                f"one of the two appearances is showing the other's drawing")

    grounds, masks = {}, {}
    for lum, (w, h, rgb) in pixels.items():
        grounds[lum], masks[lum] = mask_of(rgb, w * h)

    # 4. grounds point the right way
    for lum, ground in grounds.items():
        lightness = sum(ground) / 3.0
        if lum == "light" and lightness < 128:
            findings.append(
                f"light: ground is {ground}, which is dark — a light-appearance "
                f"home screen gets a dark tile")
        if lum in ("dark", "tinted") and lightness > 128:
            findings.append(f"{lum}: ground is {ground}, which is light")

    # 5. tinted is greyscale
    if "tinted" in pixels:
        w, h, rgb = pixels["tinted"]
        for i in range(0, len(rgb), 3):
            if not (rgb[i] == rgb[i + 1] == rgb[i + 2]):
                findings.append(
                    "tinted: not greyscale — the system maps its luminance to the "
                    "person's tint, so colour in it is thrown away or muddied")
                break

    # 6. one mask across all three
    total = side * side
    for a, b in itertools.combinations(sorted(masks), 2):
        diff = sum(1 for x, y in zip(masks[a], masks[b]) if x != y)
        if diff / total > MASK_TOLERANCE:
            findings.append(
                f"{a} and {b} do not share a coverage mask ({100.0 * diff / total:.2f}% "
                f"of pixels differ) — a variant was redrawn instead of derived, and "
                f"the knocked-out eyes and suckers do not survive that")
    return findings


def self_test():
    """Build synthetic iconsets and prove each check catches its own defect."""
    # Deliberately NOT 1024: the checks are side-agnostic and the shipped size
    # is one of the things under test, so the fixtures run small and the whole
    # self-test costs a tenth of a second instead of five.
    TINY = 128

    def art(ground, mark, holes=True, side=TINY):
        """A stand-in icon: a mark block with knocked-out holes."""
        lo, hi = side // 5, side - side // 5
        ex_lo, ex_hi = side // 3, side // 3 + side // 6
        px = bytearray()
        for y in range(side):
            for x in range(side):
                on = lo < x < hi and lo < y < hi
                if holes and on and (ex_lo < x < ex_hi and ex_lo < y < ex_hi):
                    on = False          # a knocked-out eye
                px += bytes(mark if on else ground)
        return bytes(px)

    def write(path, rgb, side=TINY):
        stride = side * 3
        raw = bytearray()
        for y in range(side):
            raw.append(0)
            raw += rgb[y * stride:(y + 1) * stride]

        def chunk(tag, d):
            return (struct.pack(">I", len(d)) + tag + d
                    + struct.pack(">I", zlib.crc32(tag + d) & 0xffffffff))
        path.write_bytes(b"\x89PNG\r\n\x1a\n"
                         + chunk(b"IHDR", struct.pack(">IIBBBBB", side, side, 8, 2, 0, 0, 0))
                         + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
                         + chunk(b"IEND", b""))

    BLACK, WHITE, PINK = (0, 0, 0), (255, 255, 255), (255, 45, 135)
    good = {"light": art(WHITE, PINK), "dark": art(BLACK, PINK), "tinted": art(BLACK, WHITE)}

    def build(tmp, arts, contents=None, side=TINY):
        d = pathlib.Path(tmp); d.mkdir(parents=True, exist_ok=True)
        for lum, rgb in arts.items():
            write(d / f"icon-{lum}.png", rgb, side)
        if contents is None:
            contents = {"images": [
                {"filename": "icon-light.png", "idiom": "universal"},
                {"filename": "icon-dark.png", "idiom": "universal",
                 "appearances": [{"appearance": "luminosity", "value": "dark"}]},
                {"filename": "icon-tinted.png", "idiom": "universal",
                 "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
            ]}
        (d / "Contents.json").write_text(json.dumps(contents))
        return d

    cases = []
    cases.append(("passes a correct iconset", False, lambda t: build(t, good)))
    # The defect this audit exists for.
    cases.append(("flags  light shipped as a copy of dark (THE shipped defect)", True,
                  lambda t: build(t, {**good, "light": good["dark"]})))
    cases.append(("flags  a light variant whose ground is dark", True,
                  lambda t: build(t, {**good, "light": art(BLACK, (250, 250, 250))})))
    cases.append(("flags  a tinted variant that is not greyscale", True,
                  lambda t: build(t, {**good, "tinted": art(BLACK, (255, 46, 135))})))
    cases.append(("flags  a light variant redrawn without the knockouts", True,
                  lambda t: build(t, {**good, "light": art(WHITE, PINK, holes=False)})))
    cases.append(("flags  an undeclared tinted variant", True,
                  lambda t: build(t, good, contents={"images": [
                      {"filename": "icon-light.png", "idiom": "universal"},
                      {"filename": "icon-dark.png", "idiom": "universal",
                       "appearances": [{"appearance": "luminosity", "value": "dark"}]}]})))
    cases.append(("flags  a file Contents.json names but the iconset lacks", True,
                  lambda t: build(t, {k: v for k, v in good.items() if k != "tinted"})))
    cases.append(("flags  art that is not the shipped square size", True,
                  lambda t: build(t, {k: art(c[0], c[1], side=TINY // 2)
                                      for k, c in {"light": (WHITE, PINK), "dark": (BLACK, PINK),
                                                   "tinted": (BLACK, WHITE)}.items()},
                                  side=TINY // 2)))
    # A near-identical pair must still PASS, or the mask check is just noise.
    nudged = bytearray(good["light"])
    nudged[3 * (TINY // 2 * TINY + TINY // 2)] = 254
    cases.append(("passes two variants differing by one pixel of antialiasing", False,
                  lambda t: build(t, {**good, "light": bytes(nudged)})))

    ok = True
    for why, should_flag, make in cases:
        with tempfile.TemporaryDirectory() as tmp:
            flagged = bool(audit(make(pathlib.Path(tmp) / "AppIcon.appiconset"), side=TINY))
        if flagged != should_flag:
            ok = False
        print(f"  {'ok  ' if flagged == should_flag else 'FAIL'} "
              f"{'flags ' if should_flag else 'passes'} {why.split(maxsplit=1)[1]}")
    return ok


if "--self-test" in sys.argv:
    print("app-icon self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(ICONSET)
if problems:
    print("✗ app icon findings:")
    for p in problems:
        print(f"  {p}")
    print("\nThe light variant is DERIVED, never redrawn: "
          "python3 design/app-icon/make-light-icon.py")
    sys.exit(1)
print("✓ app icon: three distinct variants, grounds point the right way, "
      "tinted is greyscale, one coverage mask across all three")
