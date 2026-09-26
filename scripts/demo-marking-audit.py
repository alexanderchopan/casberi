#!/usr/bin/env python3
"""Demo marking audit (prd §864, §919, §946).

WHY THIS EXISTS. Reported by the user: *"i had a user land on demo and not
realize"* — after the capsule had been restyled four times (§662f blue with a
pulse, §679 amber glass, §783 a flat dot, §813 new words). §864 answered with
a second marking at the head of the All feed (`DemoLead`) and a capsule that
stood down under it; §919 made the capsule a big blue pill carrying the same
fact and the same Exit, and §946 deleted the lead as the demo said twice
(user: "we also have this, so why not just use this"). The first-launch cover
still spells the word in four falling letter tiles.

That shape has four ways to quietly stop being true, and none of them breaks
a build, moves a pixel on the screen a screenshot sweep opens, or shows up in
a demo census. This file is those four.

ONE · **THE WAY OUT IS ONE IMPLEMENTATION.** `DemoMode.exit` is reached from
exactly one place outside `DemoMode` itself, `DemoLeave.run`. The leave is not
one call: it waits for the fade, deletes in one transaction, resets the source
and tag and lands on Accounts (§863). A second copy written at a new door
would look right and drop one of those.

TWO · **ONE MARKING, AND IT NEVER STANDS DOWN.** §83's price for the demo is a
marking that is CONTINUOUS. While the lead existed the pill hid under it, and
the flag that hid it had to come from the viewport — `onAppear` in a `List`
tracks cell recycling, so the first cut left the demo with NO marking for most
of a screen. With the lead deleted there is nothing for the pill to yield to,
so its `.opacity(` may read only its own entrance (`settled`), and neither
`DemoLead` nor its flag (`demoLeadVisible`) may come back into the model
(§723: a feature deleted from the surface is deleted from the model).

THREE · **THE COVER'S WORD COMES FROM THE CATALOG.** `IntroCover.demoLetters`
derives its letters from `String(localized: "Demo")`, so the Japanese cover
drops デ and モ. A hardcoded `"demo"` compiles, passes every other check, and
spells Latin letters across a cover whose every other word is translated — on
the one screen where the word is the whole message.

FOUR · **THE MARKING ANSWERS THE CAPTURE DOOR, THROUGH ONE DEFINITION.**
`-hideDemoBanner YES` (2026-09-08) takes the demo's marking out of an App Store
still or preview, because §83's price is owed to a real user and not to a
capture. `DemoCapture.hidesMarking` is the one definition; the shell reads it
to mount the pill, and nothing else reads the raw key — two spellings of one
DEBUG door drift apart, and the half that drifts is the half nobody
screenshots.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · That the pill is DRAWN. `RootShell` mounts it behind a `DemoMode`
    gate the demo census walks; a text check asserting the call site would
    be asserting the diff, which is what `guards-assert-what-you-built` says
    not to spend a harness on.
  · The letters' timing against `autoLift`. Both are constants in one file
    and the fall is CoreAnimation — nothing here can measure a frame, and
    `measure-motion-by-recording-frames` is the rule for that question.
  · Whether the capsule's own words are right. §813 is that ruling, and the
    strings live in the catalog where `setup-copy-audit.py` reads them.
"""

import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANNER = "Casberi/Casberi/Screens/DemoBanner.swift"
COVER = "Casberi/Casberi/Screens/IntroCover.swift"
MODE = "Casberi/Casberi/Model/DemoMode.swift"
# The mark is a layer of `RootShell` since prd §919 (an overlay beside the
# seat, so a pushed screen carries it); it was `MainSurface`'s top inset.
SURFACE = "Casberi/Casberi/Shell/RootShell.swift"
FEED = "Casberi/Casberi/Screens/FeedScreen.swift"
SOURCE_DIRS = ["Casberi/Casberi", "Casberi/Shared", "Casberi/CasberiWidgets"]

# The deleted lead and its flag (§946) — neither may come back.
GONE = ("demoLeadVisible", "struct DemoLead")


def strip_comments(text: str) -> str:
    """Comments out, string literals kept, line numbers preserved.

    This repo documents its rules by NAMING the symbols they govern — the
    lesson `sharelink-style-audit.py` and `dead-closure-audit.py` each record
    paying for, and which this file would pay on its first run: the prose
    above spells `DemoMode.exit` and `demoLeadVisible` several times each.
    """
    out, line = [], []
    in_block = in_string = False
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            if ch == "\n":
                out.append("".join(line))
                line = []
            i += 1
            continue
        if in_string:
            if ch == "\\":
                line.append("  ")
                i += 2
                continue
            if ch == '"':
                in_string = False
            line.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if ch == '"':
            in_string = True
            line.append(ch)
            i += 1
            continue
        if ch == "\n":
            out.append("".join(line))
            line = []
            i += 1
            continue
        line.append(ch)
        i += 1
    out.append("".join(line))
    return "\n".join(out)


def swift_files(root: Path):
    for rel in SOURCE_DIRS:
        base = root / rel
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.swift")):
            yield path


def audit(root: Path):
    findings = []

    def read(rel: str) -> str:
        path = root / rel
        return strip_comments(path.read_text()) if path.is_file() else ""

    # ONE — the way out is one implementation.
    callers = []
    for path in swift_files(root):
        rel = path.relative_to(root).as_posix()
        if rel == MODE:
            continue
        body = strip_comments(path.read_text())
        for lineno, line in enumerate(body.splitlines(), 1):
            if "DemoMode.exit(" in line:
                callers.append((rel, lineno))
    if len(callers) != 1 or callers[0][0] != BANNER:
        where = ", ".join(f"{r}:{n}" for r, n in callers) or "nowhere"
        findings.append(
            "the demo's exit is not one implementation — `DemoMode.exit(` is "
            f"called from {where}, and it belongs to `DemoLeave.run` in "
            f"{BANNER} alone. A second copy drops a step of the leave "
            "(the fade, the one-transaction delete, the filter reset, landing "
            "on Accounts)."
        )

    banner = read(BANNER)

    # TWO — one marking, and it never stands down.
    for m in re.finditer(r"\.opacity\(([^\n]*)\)", banner):
        if m.group(1).strip() != "settled ? 1 : 0":
            findings.append(
                f"the pill's opacity reads more than its entrance "
                f"(`.opacity({m.group(1).strip()})` in {BANNER}). There is no "
                "second marking for it to yield to since §946, so anything it "
                "stands down for is a screen of the demo with NO marking — "
                "the continuous marking §83 charges the demo for."
            )
    if re.search(r"\.allowsHitTesting\(|\.accessibilityHidden\(\s*(?!true)", banner):
        findings.append(
            f"the pill can stop answering a tap or VoiceOver ({BANNER}) — "
            "the marking carries the only way out (§946)."
        )
    for path in swift_files(root):
        body = strip_comments(path.read_text())
        for gone in GONE:
            if gone in body:
                findings.append(
                    f"`{gone}` is back in {path.relative_to(root).as_posix()}. "
                    "The All feed's lead was deleted as the demo said twice "
                    "(§946); a second marking needs a ruling, not a revert."
                )

    # FOUR — the marking answers the capture door, through one definition.
    capture = "DemoCapture.hidesMarking"
    declared = re.search(r"enum\s+DemoCapture\b[^\n]*\{", banner) and "hidesMarking" in banner
    if not declared:
        findings.append(
            f"`{capture}` is not declared where the markings can share it "
            f"({BANNER}). Two spellings of one DEBUG door drift apart, and "
            "the half that drifts is the half nobody screenshots."
        )
    # The raw key may be read ONLY through that one door.
    for rel in (SURFACE, FEED):
        body = read(rel)
        if rel == SURFACE and capture not in body:
            findings.append(
                f"{rel} does not read `{capture}`, so `-hideDemoBanner YES` "
                "leaves the demo's pill in an App Store still or preview — "
                "and a preview video cannot be painted out by hand (§864)."
            )
        if '"hideDemoBanner"' in body:
            findings.append(
                f"{rel} reads the `hideDemoBanner` key directly instead of "
                f"through `{capture}`. One door, one definition — a second "
                "copy drifts, and the half that drifts is the half nobody "
                "screenshots."
            )

    # THREE — the cover's word comes from the catalog.
    cover = read(COVER)
    letters = re.search(r"demoLetters\s*:\s*\[String\]\s*\{(.*?)\n    \}", cover, re.S)
    if letters is None:
        findings.append(
            f"`demoLetters` is gone from {COVER} — the cover's falling word."
        )
    elif 'String(localized: "Demo")' not in letters.group(1):
        findings.append(
            "the cover's letter tiles do not come from the catalog — "
            '`demoLetters` must read `String(localized: "Demo")`, or the '
            "Japanese cover spells Latin letters while every other word on "
            "the screen is translated."
        )

    return findings


# --------------------------------------------------------------------------
# Self-test


FIXTURE_BANNER = '''
import SwiftUI

struct DemoBanner: View {
    var body: some View {
        Button { leave() } label: { Text("Demo") }
        .opacity(settled ? 1 : 0)
    }
    private func leave() {
        DemoLeave.run(context: modelContext, store: store, route: route,
                      filter: filter, chrome: chrome)
    }
}

@MainActor
enum DemoCapture {
    static var hidesMarking: Bool { false }
}

@MainActor
enum DemoLeave {
    static func run(context: ModelContext, store: BridgeStore, route: HomeRoute,
                    filter: FeedFilter, chrome: ShellChrome) {
        Task { @MainActor in
            DemoMode.exit(context: context, store: store)
        }
    }
}
'''

FIXTURE_COVER = '''
import SwiftUI

struct IntroCover: View {
    private static var demoLetters: [String] {
        String(localized: "Demo").lowercased().map(String.init)
    }
    var body: some View { Text("Here's a") }
}
'''

FIXTURE_SURFACE = '''
struct RootShell: View {
    var body: some View {
        if demoActive && !DemoCapture.hidesMarking { DemoBanner() }
    }
}
'''

FIXTURE_FEED = '''
struct FeedScreen: View {
    var body: some View {
        List { roomHead }
    }
}
'''

FIXTURE_MODE = '''
enum DemoMode {
    static func exit(context: ModelContext, store: BridgeStore) {}
}
'''

FIXTURE_OTHER = '''
struct SomeScreen: View {
    var body: some View { Text("hi") }
}
'''


def self_test() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for rel, text in (
            (BANNER, FIXTURE_BANNER),
            (COVER, FIXTURE_COVER),
            (MODE, FIXTURE_MODE),
            (SURFACE, FIXTURE_SURFACE),
            (FEED, FIXTURE_FEED),
            ("Casberi/Casberi/Screens/SomeScreen.swift", FIXTURE_OTHER),
        ):
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

        if audit(root):
            failures.append(
                "the healthy tree was reported: " + "; ".join(audit(root))
            )

        def mutate(rel, old, new, why):
            path = root / rel
            kept = path.read_text()
            assert old in kept, f"stale mutation anchor: {why}"
            path.write_text(kept.replace(old, new, 1))
            caught = bool(audit(root))
            path.write_text(kept)
            if not caught:
                failures.append(why)

        # 1 · a second door calls the exit directly, skipping the leave.
        mutate(
            "Casberi/Casberi/Screens/SomeScreen.swift",
            'Text("hi")',
            "Text(DemoMode.exit(context: c, store: s))",
            "a second caller of DemoMode.exit was not reported",
        )
        # 2 · the pill learns to stand down again.
        mutate(
            BANNER,
            ".opacity(settled ? 1 : 0)",
            ".opacity(settled && !yields ? 1 : 0)",
            "a pill that stands down was not reported",
        )
        # 3 · the lead comes back.
        mutate(
            FEED,
            "List { roomHead }",
            "List { DemoLead(); roomHead }\n}\nstruct DemoLead: View {",
            "a revived DemoLead was not reported",
        )
        # 4 · its flag comes back into the model.
        mutate(
            "Casberi/Casberi/Screens/SomeScreen.swift",
            'Text("hi")',
            'Text("hi").onDisappear { chrome.demoLeadVisible = false }',
            "a revived demoLeadVisible was not reported",
        )
        # 5 · the pill stops answering a tap.
        mutate(
            BANNER,
            ".opacity(settled ? 1 : 0)",
            ".opacity(settled ? 1 : 0)\n        .allowsHitTesting(ready)",
            "a pill that can refuse its tap was not reported",
        )
        # 6 · the shell grows its own copy of the door instead of sharing one.
        mutate(
            SURFACE,
            "DemoCapture.hidesMarking",
            'UserDefaults.standard.string(forKey: "hideDemoBanner") != nil',
            "a second definition of the capture door was not reported",
        )
        # 7 · the cover's word is hardcoded Latin.
        mutate(
            COVER,
            'String(localized: "Demo").lowercased()',
            '"demo"',
            "a hardcoded cover word was not reported",
        )

    if failures:
        for f in failures:
            print(f"self-test FAILED: {f}", file=sys.stderr)
        return 1
    print("demo marking audit self-test: ok (7 mutations)")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    findings = audit(ROOT)
    if not findings:
        print("demo marking audit: ok (4 checks)")
        return 0
    print("The demo's marking has drifted (prd §864, §946):\n")
    for f in findings:
        print(f"  · {f}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
