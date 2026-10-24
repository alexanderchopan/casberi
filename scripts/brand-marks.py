#!/usr/bin/env python3
"""Fetch a brand's App Store artwork into the asset catalogue (prd §1489).

WHY. Buy's merchants are Bitrefill's catalogue, and most US retail and
restaurant brands are in no open icon set (Simple Icons dropped them on
trademark grounds). Their mark is their app's App Store artwork, the source
§1164 already rules for a service mark. This script turns a manifest line into
`brand-<name>.imageset/icon.png` at 512px, so adding a merchant is a line,
not a session with a browser.

    python3 scripts/brand-marks.py            # fetch every mark not yet bundled
    python3 scripts/brand-marks.py --dry-run  # say what each search would pick
    python3 scripts/brand-marks.py --refresh  # re-fetch even bundled ones
    python3 scripts/brand-marks.py --self-test

The manifest is `scripts/brand-marks.json`: `asset` is the name after
`brand-` (what `BridgeIconArt.assetName` makes of the merchant's name, or an
alias in `BridgeIcon.swift`), `term` the App Store search, `seller` a word the
app's seller name must hold, so a fan app or a coupon app never passes as the
brand. A search with no such result is reported and writes nothing.

Run on a Mac: it needs `itunes.apple.com` and `sips`. It writes PNG only, and
never touches an imageset it did not create unless `--refresh` is passed.
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Casberi", "Casberi", "Assets.xcassets")
MANIFEST = os.path.join(ROOT, "scripts", "brand-marks.json")
CONTENTS = {"images": [{"filename": "icon.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1}}


def pick(results, seller):
    """The first result whose seller name holds `seller`, case-insensitive."""
    want = seller.lower()
    for r in results:
        if want in (r.get("sellerName") or "").lower() or want in (r.get("artistName") or "").lower():
            return r
    return None


def search(term):
    q = urllib.parse.urlencode({"term": term, "entity": "software", "country": "us", "limit": 10})
    with urllib.request.urlopen(f"https://itunes.apple.com/search?{q}", timeout=20) as r:
        return json.load(r).get("results", [])


def write(asset, url):
    folder = os.path.join(ASSETS, f"brand-{asset}.imageset")
    os.makedirs(folder, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "art")
        urllib.request.urlretrieve(url, src)
        subprocess.run(["sips", "-s", "format", "png", "-z", "512", "512", src,
                        "--out", os.path.join(folder, "icon.png")], check=True, capture_output=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(CONTENTS, f, indent=2)


def self_test():
    results = [{"trackName": "Home Depot Deals", "sellerName": "Coupon Apps LLC"},
               {"trackName": "The Home Depot", "sellerName": "Home Depot Product Authority, LLC"}]
    ok = pick(results, "Home Depot")["trackName"] == "The Home Depot"
    ok &= pick(results[:1], "Home Depot") is None
    entries = json.load(open(MANIFEST))
    names = [e["asset"] for e in entries]
    ok &= len(names) == len(set(names))
    ok &= all(set(e) == {"asset", "term", "seller"} for e in entries)
    ok &= all(a == a.lower() and " " not in a and "'" not in a for a in names)
    print("brand-marks self-test:", "ok" if ok else "FAILED")
    return 0 if ok else 1


def main(argv):
    if "--self-test" in argv:
        return self_test()
    dry, refresh = "--dry-run" in argv, "--refresh" in argv
    missing = 0
    for e in json.load(open(MANIFEST)):
        folder = os.path.join(ASSETS, f"brand-{e['asset']}.imageset")
        if os.path.isdir(folder) and not refresh:
            continue
        try:
            hit = pick(search(e["term"]), e["seller"])
        except Exception as err:  # a timeout is one line, not the run
            print(f"  ✗ {e['asset']}: {err}")
            missing += 1
            continue
        if hit is None:
            print(f"  ✗ {e['asset']}: no app sold by “{e['seller']}” for “{e['term']}”")
            missing += 1
            continue
        line = f"{e['asset']}: {hit['trackName']} — {hit['sellerName']}"
        if dry:
            print(f"  · {line}")
            continue
        write(e["asset"], hit["artworkUrl512"])
        print(f"  ✓ {line}")
    print(f"brand-marks: {missing} without a mark")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
