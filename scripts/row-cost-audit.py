#!/usr/bin/env python3
"""Casberi row-cost audit (prd §626, 2026-09-06).

Six costs that ran PER ROW PER BODY EVALUATION, each fixed by removing the
work rather than tuning it, each re-introducible by one plausible edit. This
pins them.

WHY AN AUDIT AND NOT A HARNESS. There is no scroll instrument in this project
— `docs/perf-spec.md` P3 says so and refuses to optimise scroll blind. So
these fixes were found by READING, and nothing that runs can tell you they are
still in place: the build is happy either way, every existing self-test passes
either way, and the symptom is "the feed feels slower on a big corpus", which
is exactly the report this codebase has already chased four times down three
wrong paths. A static check is the only thing standing between these and the
next refactor.

WHAT MAKES THESE PARTICULAR LINES WORTH PINNING. A row's body is not evaluated
once. SwiftUI re-evaluates a LEAF view's body on the model's own observation,
through that leaf's own attribute node, with no involvement from the parent
(liveness corollary 5, build 188) — and this app writes to the store
constantly during a foreground sweep, every bridge save re-emitting every live
`@Query`. So anything in a row body runs again and again, multiplied by the
rows on screen, in precisely the window the app is least able to draw.

Each check below is mutation-tested by --self-test: it rewrites the guarded
line back to the shape it had before the fix and asserts the check fails.

Exit non-zero on a finding.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (file, must-contain, must-NOT-contain, what it was, why it cost)
CHECKS = [
    (
        "Casberi/Casberi/Screens/FeedScreen.swift",
        "private func refreshWatchedIDs() {",
        r"Set\(visible\.live\.compactMap \{ (Walletbeat|L2beat)Watch\.",
        "walletbeatWatchedIDs / l2beatWatchedIDs walking visible.live themselves",
        "they are read PER ROW, so a walk of the room's whole corpus inside them "
        "is O(n^2) in the room's size — the most expensive thing in this file",
    ),
    (
        "Casberi/Casberi/Screens/ShapedRows.swift",
        "SharedStore.groupDefaults?.double(forKey: \"widget.lastSeen\")",
        r"UserDefaults\(suiteName: SharedStore\.appGroup\)",
        "BandRow.newSinceLastSeen building its own app-group suite",
        "UserDefaults(suiteName:) opens a suite and builds a search list, and this "
        "is reached about six times per row per body evaluation",
    ),
    (
        "Casberi/Casberi/Model/TwitchBridge.swift",
        "if let cached = liveRefsCache { return cached }",
        None,
        "TwitchIngest.liveRefs rebuilding its Set on every access",
        "two feed readers reach it per row per body evaluation, in EVERY room "
        "rather than only Twitch's",
    ),
    (
        "Casberi/Shared/Thing.swift",
        "guard let flags = securityFlag else { return false }",
        None,
        "isFlagged answering through securityFlags",
        "securityFlags allocates a split, a map and a filter — on a corpus where "
        "almost nothing is flagged, almost every one of those was to prove a negative",
    ),
    (
        "Casberi/Casberi/Screens/ShapedRows.swift",
        "StoredPixels.probe(thing)",
        None,
        "PostCard.liveBody decoding previewImageData itself",
        "an external-storage file read plus a fresh, undecoded UIImage per body "
        "evaluation, in the rooms that carry pictures",
    ),
    (
        "Casberi/Casberi/Screens/ThingContent.swift",
        "ShareTargetMemo.url(for: thing)",
        r"Capture\.detectURL\(in: shareText\)",
        "ThingShareLink running NSDataDetector in its body",
        "inside every row's non-escaping context menu: a content fault plus a "
        "detector pass per row per body evaluation — the scan a §260 amendment says was removed",
    ),
    (
        "Casberi/Casberi/Design/AppIconTile.swift",
        "if let hit = inkMemo[key] { return hit }",
        # The key must name the PAGE BACKGROUND, which is what `DS.themedPage`
        # reads. The first cut keyed on `bleed`, which `legibleInk` never reads
        # — so changing the background while keeping the bleed served an ink
        # solved against the old page, i.e. a contrast ratio below the one this
        # function exists to promise, rendering perfectly.
        r"theme\.bleed",
        "legibleInk running solveInk on every call",
        "an 8-step binary search recomputing luminance at each step, per row "
        "carrying a project label",
    ),
]

# `previewImageData` + `UIImage(data:)` in one statement is only allowed where
# it runs ONCE — a load function behind `.task`/`@State` — never in a body.
DECODE_ALLOWED = {
    ("Casberi/Casberi/Design/StoredPixels.swift", "imageNow"),       # the cache's own sync door
}

# The writers that can REPLACE (or clear) a picture a row has already drawn
# must forget that row's memo (2026-09-08, in place of the sweep-end flush,
# which re-decoded every visible picture on main after every foreground).
# Each assignment line must be followed, within three lines, by its forget.
FORGETS = [
    ("Casberi/Casberi/Model/InstagramCaptions.swift", "thing.previewImageData = thumb"),
    ("Casberi/Casberi/Model/SnapchatImport.swift", "thing.previewImageData = data"),
    ("Casberi/Casberi/Model/ImportMedia.swift", "thing.previewImageData = data"),
    ("Casberi/Casberi/Model/ContactsIngest.swift", "thing.previewImageData = data"),
    ("Casberi/Casberi/Model/ContactsIngest.swift", "thing.previewImageData = nil"),
]
# And the flush must NOT come back to the sweep: it is the cost this replaced.
NO_SWEEP_FLUSH = ("Casberi/Casberi/Shell/RootShell.swift", "StoredPixels.flush()")


def strip_comments(text):
    """Comments name the very calls these guards forbid — the Obsidian/Cursor
    lesson, paid for repeatedly in this repo. Read the code, not the prose."""
    out = []
    for line in text.split("\n"):
        # Not a full parser: string literals holding "//" would be mangled, and
        # none of the guarded shapes live in one.
        out.append(re.sub(r"//.*$", "", line))
    return "\n".join(out)


def enclosing_func(text, index):
    """The nearest `func`/`var body` declaration above `index`."""
    head = text[:index]
    hits = list(re.finditer(r"(?:func|var)\s+(\w+)", head))
    return hits[-1].group(1) if hits else "?"


def audit(files):
    findings = []
    for path, needed, forbidden, was, why in CHECKS:
        src = strip_comments(files[path])
        if needed not in src:
            findings.append(f"{path}: lost `{needed}`\n    was: {was}\n    cost: {why}")
        if forbidden and re.search(forbidden, src):
            findings.append(f"{path}: `{was}` is back\n    cost: {why}")

    # The decode sweep — any call site outside the allowed load functions.
    for path, text in files.items():
        if not path.endswith(".swift"):
            continue
        src = strip_comments(text)
        for m in re.finditer(r"previewImageData[^\n]{0,80}UIImage\(data:", src):
            fn = enclosing_func(src, m.start())
            if (path, fn) in DECODE_ALLOWED:
                continue
            findings.append(
                f"{path}: previewImageData decoded inside `{fn}`\n"
                "    cost: an external-storage read plus a fresh undecoded UIImage per\n"
                "    body evaluation, and a bitmap decoded on the main thread at draw.\n"
                "    Use StoredPixels.probe + StoredPicture (a body) or\n"
                "    StoredPixels.prepared(for:) (a load function)."
            )

    for fpath, assign in FORGETS:
        src = strip_comments(files[fpath])
        lines = src.split("\n")
        hits = [i for i, l in enumerate(lines) if assign in l]
        if not hits:
            findings.append(f"{fpath}: lost the writer `{assign}` this audit pins")
            continue
        for i in hits:
            window = "\n".join(lines[i:i + 4])
            if "StoredPixels.forget(thing.id)" not in window:
                findings.append(
                    f"{fpath}:{i + 1}: `{assign}` without StoredPixels.forget(thing.id)\n"
                    "    cost: a row already drawn keeps its old picture for the session —\n"
                    "    the memo is forgotten per row now, never flushed per sweep."
                )
    fpath, forbidden = NO_SWEEP_FLUSH
    if forbidden in strip_comments(files[fpath]):
        findings.append(
            f"{fpath}: `{forbidden}` is back\n"
            "    cost: every return to the app re-decodes every visible picture on\n"
            "    the main thread during the first scroll."
        )
    return findings


def read_all():
    files = {}
    for sub in ("Casberi/Casberi", "Casberi/Shared"):
        for p in (ROOT / sub).rglob("*.swift"):
            files[str(p.relative_to(ROOT))] = p.read_text()
    return files


def self_test():
    """Each mutation restores a pre-fix shape and must be caught."""
    files = read_all()
    if audit(files):
        print("✗ self-test cannot run: the tree already has findings")
        for f in audit(files):
            print("   " + f)
        return 1

    mutations = [
        ("the quadratic watched-id walk returns",
         "Casberi/Casberi/Screens/FeedScreen.swift",
         lambda t: t.replace(
             "        refreshWatchedIDs()\n        return memo.walletbeatWatched",
             "        Set(visible.live.compactMap { WalletbeatWatch.walletID(from: $0) })")),
        ("the app-group suite is rebuilt per read",
         "Casberi/Casberi/Screens/ShapedRows.swift",
         lambda t: t.replace(
             'SharedStore.groupDefaults?.double(forKey: "widget.lastSeen")',
             'UserDefaults(suiteName: SharedStore.appGroup)?.double(forKey: "widget.lastSeen")')),
        ("liveRefs rebuilds its Set",
         "Casberi/Casberi/Model/TwitchBridge.swift",
         lambda t: t.replace("if let cached = liveRefsCache { return cached }", "")),
        ("isFlagged allocates again",
         "Casberi/Shared/Thing.swift",
         lambda t: t.replace("guard let flags = securityFlag else { return false }", "")),
        ("a row decodes previewImageData in its body",
         "Casberi/Casberi/Screens/ShapedRows.swift",
         lambda t: t.replace(
             "} else if let stored = StoredPixels.probe(thing) {",
             "} else if let stored = thing.previewImageData, let _ = UIImage(data: stored) {")),
        ("legibleInk solves on every call again",
         "Casberi/Casberi/Design/AppIconTile.swift",
         lambda t: t.replace("if let hit = inkMemo[key] { return hit }", "")),
        ("the ink memo keys on the bleed instead of the page background",
         "Casberi/Casberi/Design/AppIconTile.swift",
         lambda t: t.replace("theme.background.name", "theme.bleed.name")),
        ("the sweep-end flush returns",
         "Casberi/Casberi/Shell/RootShell.swift",
         lambda t: t.replace("defer { ShareTargetMemo.flush() }",
                             "defer { StoredPixels.flush(); ShareTargetMemo.flush() }")),
        ("a replacing writer stops forgetting its row",
         "Casberi/Casberi/Model/ContactsIngest.swift",
         lambda t: t.replace("            StoredPixels.forget(thing.id)   // a drawn face was removed — prd §626\n", "")),
        ("PhotoWell decodes at draw again",
         "Casberi/Casberi/Screens/ShapedRows.swift",
         lambda t: t.replace(
             "        if let stored = await StoredPixels.prepared(for: thing) {\n            image = stored.image",
             "        if let data = thing.previewImageData, let stored = UIImage(data: data) {\n            image = stored")),
        ("the share menu detects per row again",
         "Casberi/Casberi/Screens/ThingContent.swift",
         lambda t: t.replace("ShareTargetMemo.url(for: thing)", "Capture.detectURL(in: shareText)")),
    ]

    failures = 0
    for name, path, mutate in mutations:
        mutated = dict(files)
        before = mutated[path]
        mutated[path] = mutate(before)
        if mutated[path] == before:
            print(f"✗ mutation '{name}' changed nothing — its anchor drifted")
            failures += 1
            continue
        if not audit(mutated):
            print(f"✗ mutation '{name}' SURVIVED — the audit cannot see it")
            failures += 1
    if failures:
        return 1
    print(f"✓ row-cost audit self-test: {len(mutations)} mutations caught")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    findings = audit(read_all())
    if findings:
        print("row-cost audit: FINDINGS")
        for f in findings:
            print("  ✗ " + f)
        return 1
    print(f"row-cost audit: ok ({len(CHECKS)} pinned row costs, decode sweep clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
