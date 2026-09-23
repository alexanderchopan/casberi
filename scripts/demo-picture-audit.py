#!/usr/bin/env python3
"""ONE DRAWN PICTURE PER DEMO SUBJECT, AND NOTHING SHIPPED THAT NOTHING DRAWS (prd §890).

Every picture the furnished demo showed was one of four bundled football
photographs: `DemoSeedAll.art(n)` returned `sample:demo-shot-\\((n % 4) + 1)`
and thirty-odd rooms called it with a row index. The fix gives every row its
own drawn asset, keyed by subject — `scripts/demo-art/pictures.py` is the
table, `scripts/demo-art/render.py` draws it, `art("<key>")` names it.

`CasberiTests/DemoPictureTests.swift` owns the question a person sees — no two
POURED rows share a picture, by ref or by bytes, and every named picture is
bundled. This audit owns the three joins that test cannot see, because they
are about files rather than rows:

**(1) Every table row is bundled.** `pictures.py` lists a key whose imageset is
not in `Assets.xcassets` → the seed names a picture the app cannot draw (the
unit test also catches this, but only after a 10-minute build).

**(2) Nothing bundled is orphaned.** A `sample-pic-*` imageset with no table
row ships in every install and is drawn by nothing — and it is exactly what a
renamed key leaves behind.

**(3) The seed and the table agree.** Every `art("…")` / `pixels("…")` literal
in `DemoSeedAll.swift` must match at least one table key (interpolations read
as wildcards), and every table key must be matched by some literal, or by a
Photos screenshot ref (`sample:demo-shot-N`). A key the seed never names is
check (2)'s orphan one layer up.

**(4) The cycle cannot come back.** `art(` / `pixels(` called with a bare
number or index expression — the `n % 4` shape — fails.

**(5) The bundle budget.** The app ships every one of these to every user, for
a demo. Each picture ≤ 160 KB, all of them ≤ 9 MB.

**STATED CEILINGS.** It cannot see PIXELS: two keys whose drawings look alike
pass here (the unit test compares bytes, which catches only identical files,
and no check can judge "looks like a repeat" — that is the contact sheet's
job, `render.py --preview`). It cannot tell that a picture matches its row's
subject; the table's `subject` line is the brief, not a proof.
"""

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "Casberi/Casberi/Model/DemoSeedAll.swift"
ASSETS = ROOT / "Casberi/Casberi/Assets.xcassets"
EACH_CAP = 160 * 1024
TOTAL_CAP = 9 * 1024 * 1024


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def literal_patterns(seed: str) -> list:
    """`art("ig-save-\\(i)")` → regex `^ig\\-save\\-.+$`."""
    out = []
    for m in re.finditer(r'\b(?:art|pixels)\(\s*"((?:[^"\\]|\\.)*)"', seed):
        raw = m.group(1)
        parts = re.split(r"\\\([^)]*\)", raw)
        out.append((raw, re.compile("^" + ".+".join(re.escape(p) for p in parts) + "$")))
    return out


def audit(table: dict, assets: dict, seed: str) -> list:
    """`table`: key → asset name. `assets`: imageset name → jpeg bytes (or
    None when the imageset holds no picture). `seed`: DemoSeedAll source."""
    out = []
    code = strip_comments(seed)

    # (1) every table row is bundled
    for key, name in sorted(table.items()):
        if name not in assets:
            out.append(f"{key}: no {name}.imageset — run scripts/demo-art/render.py --only {key}")
        elif not assets[name]:
            out.append(f"{name}.imageset holds no picture")

    # (2) nothing bundled is orphaned
    drawn = set(table.values())
    for name in sorted(assets):
        if name.startswith("sample-pic-") and name not in drawn:
            out.append(f"{name}.imageset is in no table row — it ships and nothing draws it")

    # (3) the seed and the table agree
    pats = literal_patterns(code)
    for raw, rx in pats:
        if not any(rx.match(k) for k in table):
            out.append(f'art/pixels("{raw}") matches no key in pictures.py')
    shots = {int(n) for n in re.findall(r'sample:demo-shot-\\\(\s*(?:i\s*\+\s*)?(\d+)', code)}
    for key in sorted(table):
        if any(rx.match(key) for _, rx in pats):
            continue
        m = re.fullmatch(r"shot-(\d+)", key)
        if m and any(int(m.group(1)) >= base for base in shots):
            continue
        out.append(f"{key} is drawn but no art()/pixels() literal in DemoSeedAll names it")

    # (4) the cycle cannot come back
    # A non-literal argument is fine only as a KEY passed through a helper
    # (`pixels(_ key:)` calls `art(key)`); a digit, a `%` or a bare index is
    # the row-number shape that cycled four pictures across the demo.
    for m in re.finditer(r"\b(art|pixels)\(\s*([^\"\s)][^)]*)\)", code):
        if not re.search(r"\d|%|^\s*[ijn]\s*$", m.group(2)):
            continue
        out.append(f"{m.group(1)}({m.group(2)}) takes an index, not a key — the n % 4 cycle (prd §890)")

    # (5) the bundle budget
    total = 0
    for name, size in assets.items():
        if name in drawn and size:
            total += size
            if size > EACH_CAP:
                out.append(f"{name} is {size // 1024} KB, over the {EACH_CAP // 1024} KB cap")
    if total > TOTAL_CAP:
        out.append(f"demo pictures total {total // 1024} KB, over the {TOTAL_CAP // 1024} KB budget")
    return out


def load_table() -> dict:
    sys.path.insert(0, str(ROOT / "scripts/demo-art"))
    from pictures import PICTURES  # noqa: E402
    return {p["key"]: p.get("asset") or f"sample-pic-{p['key']}" for p in PICTURES}


def load_assets() -> dict:
    out = {}
    for d in ASSETS.glob("sample-*.imageset"):
        jpgs = [f for f in d.iterdir() if f.suffix.lower() in (".jpg", ".jpeg", ".png")]
        out[d.name[:-len(".imageset")]] = sum(f.stat().st_size for f in jpgs) or None
    return out


def self_test() -> bool:
    seed = '''
    private static func art(_ key: String) -> String { "sample:pic-\\(key)" }
    private static func pixels(_ key: String) -> Data? { stored(art(key)) }
    row(.screenshot, s.0, source: "Photos", ref: "sample:demo-shot-\\(i + 5)")
    t.previewImageURL = art("ig-save-\\(i)")
    t.previewImageData = pixels("x-video-0")
    '''
    table = {"ig-save-0": "sample-pic-ig-save-0", "ig-save-1": "sample-pic-ig-save-1",
             "x-video-0": "sample-pic-x-video-0", "shot-5": "sample-screenshot-5"}
    assets = {v: 40_000 for v in table.values()}
    cases = [
        ("healthy tree is clean", table, assets, seed, 0),
        ("a table row with no imageset", table,
         {k: v for k, v in assets.items() if k != "sample-pic-ig-save-1"}, seed, 1),
        ("an orphaned imageset", table, {**assets, "sample-pic-old-9": 40_000}, seed, 1),
        ("a literal no key matches", table, assets,
         seed + '\n    t.previewImageURL = art("yt-\\(i)")', 1),
        ("a key nothing names", {**table, "rss-0": "sample-pic-rss-0"},
         {**assets, "sample-pic-rss-0": 40_000}, seed, 1),
        ("the index cycle is back", table, assets,
         seed + "\n    t.previewImageURL = art(i + 1)", 1),
        ("a picture over the cap", table, {**assets, "sample-pic-x-video-0": 400_000}, seed, 1),
        ("a commented-out literal does not count", {**table, "rss-0": "sample-pic-rss-0"},
         {**assets, "sample-pic-rss-0": 40_000}, seed + '\n    // art("rss-\\(i)")', 1),
    ]
    ok = True
    for name, t, a, s, want in cases:
        got = len(audit(t, a, s))
        good = got >= want if want else got == 0
        ok &= good
        print(f"  {'ok  ' if good else 'FAIL'} {name} ({got} finding(s))")
    return ok


def main() -> int:
    print("demo-picture-audit self-test")
    if not self_test():
        print("SELF-TEST FAILED")
        return 1
    if "--self-test" in sys.argv:
        print("  self-test passed")
        return 0
    findings = audit(load_table(), load_assets(), SEED.read_text(encoding="utf-8"))
    if findings:
        print("demo-picture-audit: FAIL")
        for f in findings:
            print(f"  {f}")
        return 1
    print("demo-picture-audit: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
