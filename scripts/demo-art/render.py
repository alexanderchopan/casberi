#!/usr/bin/env python3
"""render.py — the demo's pictures, one per subject (2026-09-23).

WHY THIS EXISTS. Until this pass every picture in the furnished demo — an
Instagram save, a Figma screenshot, a YouTube still, an album cover, a
Pinterest pin, a journal photo — was one of FOUR bundled stock photographs of
football, handed out by `DemoSeedAll.art(n)` as `n % 4`. So the same luchador
mask stood behind a Lisbon tram timetable, a Radiohead song and a Notion page,
and a person scrolling any two rooms saw the same four pictures again and again
(user: "we use the same screenshots. that is really bad").

So every picture the demo shows is now its OWN asset, drawn for the row it
belongs to: `sample:pic-<key>` resolves to `sample-pic-<key>` (and the Photos
room's screenshots keep their `sample:demo-shot-N` → `sample-screenshot-N`
identity). `CasberiTests/DemoPictureTests.swift` fails if two demo rows ever
share one again, or if a row names a picture that is not bundled.

These are DRAWN, like `scripts/make-demo-art.swift`'s product stills, and for
that file's reason: the demo reaches nothing, and a generated still is honest
about being a placeholder where a stock photograph is a picture nobody took.

HOW. Each family module (`fam_*.py`) returns a self-contained HTML page for a
key; this driver screenshots it with headless Chrome and writes a JPEG
imageset. Chrome, not WebKit, because its `--screenshot` flag needs no run
loop; the pages use only system fonts, so the output does not depend on
anything but this Mac's font set.

Usage:
  python3 scripts/demo-art/render.py                 # every picture → Assets.xcassets
  python3 scripts/demo-art/render.py --only ig-save-0,yt-3
  python3 scripts/demo-art/render.py --family scene_home --preview DIR
      (--preview writes PNGs and DIR/index.html, and touches no asset)
"""

import argparse
import concurrent.futures as cf
import html as htmllib
import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "Casberi", "Casberi", "Assets.xcassets")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
sys.path.insert(0, HERE)

from pictures import PICTURES  # noqa: E402

JPEG_QUALITY = 74


def asset_name(p):
    return p.get("asset") or f"sample-pic-{p['key']}"


def page(p):
    mod = importlib.import_module(f"fam_{p['family']}")
    return mod.html(p)


def screenshot(doc, w, h, scale, out_png, profile):
    """One headless Chrome run. Chrome writes the file and then lingers, so
    wait for the file rather than for the process, and kill it after."""
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(doc)
        src = f.name
    try:
        if os.path.exists(out_png):
            os.remove(out_png)
        proc = subprocess.Popen(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--no-first-run", "--no-default-browser-check", "--disable-extensions",
             "--disable-sync", "--disable-background-networking",
             f"--user-data-dir={profile}",
             f"--force-device-scale-factor={scale}",
             f"--window-size={w},{h}",
             f"--screenshot={out_png}", f"file://{src}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 45
        last = -1
        while time.time() < deadline:
            if os.path.exists(out_png):
                size = os.path.getsize(out_png)
                if size > 0 and size == last:
                    break
                last = size
            time.sleep(0.15)
        proc.kill()
        proc.wait()
        if not os.path.exists(out_png) or os.path.getsize(out_png) == 0:
            raise RuntimeError(f"chrome produced nothing for {out_png}")
    finally:
        os.unlink(src)


def write_imageset(p, png):
    name = asset_name(p)
    d = os.path.join(ASSETS, f"{name}.imageset")
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    jpg = os.path.join(d, "pic.jpg")
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions",
                    str(JPEG_QUALITY), png, "--out", jpg],
                   check=True, stdout=subprocess.DEVNULL)
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "pic.jpg", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    return os.path.getsize(jpg)


def contact_sheet(todo, out_dir, per=12, cell=300):
    """Pages of labelled thumbnails, so a whole family can be LOOKED at in a
    few images rather than one file at a time."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return
    for page_i in range(0, len(todo), per):
        chunk = todo[page_i:page_i + per]
        cols = 4
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), "white")
        draw = ImageDraw.Draw(sheet)
        for j, p in enumerate(chunk):
            im = Image.open(os.path.join(out_dir, f"{p['key']}.png")).convert("RGB")
            im.thumbnail((cell - 8, cell - 8))
            x, y = (j % cols) * cell, (j // cols) * (cell + 18)
            sheet.paste(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2))
            draw.text((x + 4, y + cell + 2), p["key"], fill="black")
        sheet.save(os.path.join(out_dir, f"sheet-{page_i // per + 1}.jpg"), quality=85)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="comma-separated keys")
    ap.add_argument("--family", help="render one family")
    ap.add_argument("--preview", help="write PNGs + index.html here; touch no asset")
    ap.add_argument("--jobs", type=int, default=6)
    args = ap.parse_args()

    todo = PICTURES
    if args.only:
        want = set(args.only.split(","))
        todo = [p for p in todo if p["key"] in want]
    if args.family:
        todo = [p for p in todo if p["family"] == args.family]
    if not todo:
        sys.exit("nothing to render")

    work = tempfile.mkdtemp(prefix="demo-art-")
    out_dir = args.preview or work
    os.makedirs(out_dir, exist_ok=True)

    def one(i_p):
        i, p = i_p
        w, h = p["size"]
        scale = p.get("scale", 1)
        png = os.path.join(out_dir, f"{p['key']}.png")
        # One profile per render: `i % jobs` let two concurrent renders share
        # a profile directory, and Chrome locks it.
        profile = os.path.join(work, f"profile-{p['key']}")
        # Chrome under load (five families rendering at once) occasionally
        # never finishes a load inside the deadline; a retry is all it takes.
        for attempt in range(3):
            try:
                screenshot(page(p), w, h, scale, png, profile)
                break
            except RuntimeError:
                if attempt == 2:
                    raise
        if args.preview:
            return p, None
        return p, write_imageset(p, png)

    total = 0
    failed = []
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(one, (i, p)): p for i, p in enumerate(todo)}
        for fut in cf.as_completed(futs):
            p = futs[fut]
            try:
                _, size = fut.result()
                if size:
                    total += size
                print(f"ok   {p['key']:<22} {size // 1024 if size else '-':>4}{'KB' if size else ''}")
            except Exception as e:  # noqa: BLE001
                failed.append(p["key"])
                print(f"FAIL {p['key']}: {e}")

    if args.preview:
        cells = "".join(
            f'<figure><img src="{p["key"]}.png"><figcaption><b>{p["key"]}</b> '
            f'{htmllib.escape(p["subject"])}</figcaption></figure>' for p in todo)
        with open(os.path.join(out_dir, "index.html"), "w") as f:
            f.write("<style>body{font:12px system-ui;display:flex;flex-wrap:wrap;gap:12px}"
                    "figure{margin:0;width:260px}img{width:260px;border-radius:6px;"
                    "box-shadow:0 1px 4px #0003}</style>" + cells)
        contact_sheet(todo, out_dir)
        print(f"preview: {out_dir}/index.html and {out_dir}/sheet-*.jpg")
    else:
        print(f"{len(todo) - len(failed)} written, {total // 1024}KB total")
    shutil.rmtree(work, ignore_errors=True)
    if failed:
        sys.exit(f"failed: {', '.join(failed)}")


if __name__ == "__main__":
    main()
