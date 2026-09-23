#!/usr/bin/env python3
"""The screenshot VISION pass, statically (2026-09-22).

iOS 27 lets the on-device model read the screenshot's own picture beside its
OCR text (`ScreenshotVision`). Four things about that arrangement are invisible
to the compiler, to every simulator run (no on-device model exists there) and
to `ondevice-selftest.sh` (which compiles pure functions, and this is shape):

  1. The picture is DOUBLE-gated — iOS 27 AND an Apple Intelligence device.
     Drop either and the call throws on every phone that lacks it, in a sweep
     whose failures are already swallowed as "the model declined".
  2. The text-only branch SURVIVES. It is what every iOS 26 phone runs; losing
     it silently stops naming screenshots there, and nothing says so.
  3. The honesty rail still runs. A picture makes a wrong title more fluent,
     not more true, so `grounded` must still reject words the OCR text lacks
     (prd §218/§282).
  4. The picture never reaches the KEYED librarian. `AgentLibrarian.name` posts
     to somebody's API; a title is a different promise from a screenshot.
  5. The loader takes a REF, never a `Thing` — a model walked inside an async
     function is the liveness class (docs/liveness.md).

Run with --self-test to prove each check catches its own failure.
"""
import re, sys, pathlib, tempfile, shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
VISION = "Casberi/Casberi/Model/ScreenshotVision.swift"
NAMING = "Casberi/Casberi/Model/ScreenshotNaming.swift"
FACTS = "Casberi/Casberi/Model/ScreenshotFacts.swift"


def strip_comments(text):
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("//") or s.startswith("///"):
            continue
        out.append(line)
    return "\n".join(out)


def check(root):
    fails = []
    src = {}
    for rel in (VISION, NAMING, FACTS):
        p = root / rel
        if not p.exists():
            return ["missing file: %s" % rel]
        src[rel] = strip_comments(p.read_text())

    v = src[VISION]
    # 1. both gates, in the one place that answers "can we show a picture".
    gate = re.search(r"static var available:.*?\n\s*\}", v, re.S)
    if not gate:
        fails.append("ScreenshotVision.available is gone")
    else:
        g = gate.group(0)
        if "#available(iOS 27.0, *)" not in g:
            fails.append("ScreenshotVision.available does not gate on iOS 27")
        if "OnDeviceModel.isAvailable" not in g:
            fails.append("ScreenshotVision.available does not ask whether the model exists")

    # 5. the loader takes a ref, never a Thing.
    loader = re.search(r"static func image\(for[^)]*\)", v)
    if not loader:
        fails.append("ScreenshotVision.image(forAssetRef:) is gone")
    elif "Thing" in loader.group(0):
        fails.append("ScreenshotVision.image takes a Thing — liveness class (docs/liveness.md)")

    for rel in (NAMING, FACTS):
        s = src[rel]
        # 1b. every Attachment sits behind the iOS 27 gate.
        for m in re.finditer(r"Attachment\(", s):
            window = s[max(0, m.start() - 400):m.start()]
            if "#available(iOS 27.0, *)" not in window:
                fails.append("%s: an Attachment( is not behind an iOS 27 gate" % rel)
                break
        # 2. the text-only call survives beside it.
        if "Attachment(" in s and "respond(\n" not in s and "respond(to:" not in s.replace(" ", ""):
            fails.append("%s: the text-only respond( branch is gone" % rel)

    n = src[NAMING]
    # 3. the rail still runs in the sweep.
    if "grounded(title, in: text)" not in n:
        fails.append("ScreenshotNaming: the grounded() rail no longer guards the sweep")
    # 4. the keyed librarian is never handed the picture.
    for m in re.finditer(r"AgentLibrarian\.name\(([^)]*)\)", n):
        if "image" in m.group(1):
            fails.append("ScreenshotNaming: the picture is passed to the keyed librarian")
    return fails


def self_test():
    muts = [
        (VISION, "#available(iOS 27.0, *)", "#available(iOS 26.0, *)", "iOS 27 gate"),
        (VISION, "OnDeviceModel.isAvailable", "true", "model-exists gate"),
        (VISION, "forAssetRef ref: String?", "for thing: Thing?", "ref-not-Thing"),
        (NAMING, "grounded(title, in: text)", "true", "honesty rail"),
        (NAMING, "await AgentLibrarian.name(text: text)",
         "await AgentLibrarian.name(text: text, image: image)", "keyed librarian"),
        (NAMING, "if #available(iOS 27.0, *), let image {", "if let image {", "naming gate"),
        (FACTS, "if #available(iOS 27.0, *), let image {", "if let image {", "facts gate"),
    ]
    ok = True
    for rel, old, new, name in muts:
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            for f in (VISION, NAMING, FACTS):
                (tmp / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / f, tmp / f)
            p = tmp / rel
            text = p.read_text()
            if old not in text:
                print("  DEAD MUTATION (anchor missing): %s" % name)
                ok = False
                continue
            p.write_text(text.replace(old, new, 1))
            if not check(tmp):
                print("  SURVIVED: %s" % name)
                ok = False
            else:
                print("  caught: %s" % name)
    return ok


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        print("screenshot-vision-audit --self-test")
        sys.exit(0 if self_test() else 1)
    problems = check(ROOT)
    for p in problems:
        print("screenshot-vision-audit: %s" % p)
    if problems:
        sys.exit(1)
    print("screenshot-vision-audit: OK")
