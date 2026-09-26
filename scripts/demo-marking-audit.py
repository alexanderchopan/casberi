#!/usr/bin/env python3
"""Demo marking audit (prd §864, 2026-09-20).

WHY THIS EXISTS. Reported by the user: *"i had a user land on demo and not
realize"* — after the capsule had been restyled four times (§662f blue with a
pulse, §679 amber glass, §783 a flat dot, §813 new words). The marking was
never the wrong colour; it was in the wrong place. A 34pt capsule of 12pt type
on the top edge is read as status, like a recording indicator, and people look
at content.

So §864 says the demo TWICE, in two registers: the first-launch cover spells
the word in four falling letter tiles, and the All feed leads with
`DemoLead` — a statement, a line, and the way out as a row. The capsule stays
for every other screen.

That shape has four ways to quietly stop being true, and none of them breaks
a build, moves a pixel on the screen a screenshot sweep opens, or shows up in
a demo census. This file is those four.

ONE · **THE WAY OUT IS ONE IMPLEMENTATION.** `DemoMode.exit` is reached from
exactly one place outside `DemoMode` itself, `DemoLeave.run`. The leave is not
one call: it waits for the fade, deletes in one transaction, resets the source
and tag, lands on Accounts (§863) and clears `demoLeadVisible`. A second copy
written at a new door would look right and drop one of those — and the one it
would drop is the one with no visible symptom until later (a `demoLeadVisible`
left true hides the capsule for the whole of the NEXT demo).

TWO · **THE TWO MARKINGS ARE MUTUALLY EXCLUSIVE, AND BOTH DIRECTIONS HOLD.**
The user's words on seeing them together: *"why would we need to say demo
twice here"*. The capsule gates its opacity on the lead's flag, the flag is
raised from the VIEWPORT, and it is cleared in two places (the lead leaving,
and the leave itself).

**The viewport, not the cell.** The flag must be driven by
`onScrollVisibilityChange`, never by `onAppear`: in a `List` those lifecycle
callbacks track cell recycling, which lags the viewport by most of a screen.
The first cut used `onAppear`, so scrolling the lead just out of sight left
the flag true and the capsule still standing down — a fake crown and somebody
else's rooms with NO marking anywhere, failing exactly where §864 was meant to
fix it. Found by review, not by running it.

Dropping a CLEAR is the other dangerous half — the capsule is then gone from
every room, and §83's price for the demo existing is a marking that is
CONTINUOUS.

THREE · **THE COVER'S WORD COMES FROM THE CATALOG.** `IntroCover.demoLetters`
derives its letters from `String(localized: "Demo")`, so the Japanese cover
drops デ and モ. A hardcoded `"demo"` compiles, passes every other check, and
spells Latin letters across a cover whose every other word is translated — on
the one screen where the word is the whole message.

FOUR · **BOTH MARKINGS ANSWER THE CAPTURE DOOR.** `-hideDemoBanner YES`
(2026-09-08) takes the demo's marking out of an App Store still or preview,
because §83's price is owed to a real user and not to a capture. §864 put a
SECOND marking on screen, and a door that removes one of two removes neither:
the first cut gated only the capsule, so every marketing shot of the All feed
— the primary one — carried the lead with no flag that could remove it, and a
preview video cannot be painted frame by frame. `DemoCapture.hidesMarking` is
the one definition and both sites read it. Found by review, not by running it.

WHAT THIS DELIBERATELY DOES NOT CHECK, so it stays honest about its reach:

  · That the lead is DRAWN, or drawn only in All (check four reads only that
    the capture door reaches it). `FeedScreen` mounts it
    behind a `DemoMode.isActive` gate the demo census walks; a text check
    asserting the call site would be asserting the diff, which is what
    `guards-assert-what-you-built` says not to spend a harness on.
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

FLAG = "demoLeadVisible"


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
            "(the fade, the filter reset, landing on Accounts, clearing "
            f"`{FLAG}`), and the last of those has no symptom until the "
            "NEXT demo runs with no capsule."
        )

    banner = read(BANNER)

    # TWO — the two markings are mutually exclusive, both directions.
    if not re.search(r"\.opacity\([^\n]*\b\w*[Yy]ields\b|\.opacity\([^\n]*" + FLAG, banner):
        findings.append(
            f"the capsule does not stand down for the lead — nothing in "
            f"{BANNER} gates its `.opacity(` on `{FLAG}`. The two say the "
            'same thing in one frame (user: "why would we need to say demo '
            'twice here").'
        )
    raised = re.search(
        r"onScrollVisibilityChange\s*\([^)]*\)\s*\{[^}]*" + FLAG + r"\s*=", banner)
    if raised is None:
        findings.append(
            f"`{FLAG}` is not driven by `onScrollVisibilityChange`. In a "
            "`List`, `onAppear`/`onDisappear` track cell RECYCLING, which "
            "lags the viewport by most of a screen: the lead scrolls out of "
            "sight, the flag stays true, and the capsule stays down — the "
            "demo then shows a fake crown with no marking anywhere, which is "
            "the failure §864 exists to fix."
        )
    clears = len(re.findall(FLAG + r"\s*=\s*false", banner))
    if clears < 2:
        findings.append(
            f"`{FLAG}` is cleared in fewer than two places ({clears}). It is "
            "cleared on the lead's disappear AND in `DemoLeave.run`; drop "
            "either and the capsule is missing from every room, which is "
            "exactly the continuous marking §83 charges the demo for."
        )

    # FOUR — both markings answer the capture door.
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
        if capture not in body:
            findings.append(
                f"{rel} does not read `{capture}`, so `-hideDemoBanner YES` "
                "leaves one of the demo's two markings in an App Store still "
                "or preview — and a preview video cannot be painted out by "
                "hand (prd §864)."
            )
        if '"hideDemoBanner"' in body:
            findings.append(
                f"{rel} reads the `hideDemoBanner` key directly instead of "
                f"through `{capture}`. One door, one definition — a second "
                "copy is what put the lead into every marketing still."
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
    private var yields: Bool {
        chrome.demoLeadVisible && filter.source == "All"
    }
    var body: some View {
        Button { explaining = true } label: { Text("Demo") }
        .opacity(settled && !yields ? 1 : 0)
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
            chrome.demoLeadVisible = false
        }
    }
}

struct DemoLead: View {
    var body: some View {
        Text("This is a demo.")
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                chrome.demoLeadVisible = visible
            }
            .onDisappear { chrome.demoLeadVisible = false }
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
        let demoLead = DemoMode.isActive && !DemoCapture.hidesMarking
        return List { if demoLead { DemoLead() } }
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
        # 2 · the capsule stops reading the lead's flag.
        mutate(
            BANNER,
            ".opacity(settled && !yields ? 1 : 0)",
            ".opacity(settled ? 1 : 0)",
            "a capsule that never stands down was not reported",
        )
        # 3 · the flag goes back to the lifecycle callback, which in a List
        #     lags the viewport by most of a screen.
        mutate(
            BANNER,
            """.onScrollVisibilityChange(threshold: 0.01) { visible in
                chrome.demoLeadVisible = visible
            }""",
            ".onAppear { chrome.demoLeadVisible = true }",
            "a flag driven by cell recycling rather than the viewport was not reported",
        )
        # 4 · the leave stops clearing it — the capsule is then missing from
        #     every room of the NEXT demo, with nothing on screen to say so.
        mutate(
            BANNER,
            "            chrome.demoLeadVisible = false\n        }\n    }\n}",
            "        }\n    }\n}",
            "a leave that never clears the flag was not reported",
        )
        # 5 · the feed's lead stops answering the capture door — every
        #     marketing still of the All feed then carries it.
        mutate(
            FEED,
            "DemoMode.isActive && !DemoCapture.hidesMarking",
            "DemoMode.isActive",
            "a lead that ignores -hideDemoBanner was not reported",
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
    print("The demo's marking has drifted (prd §864):\n")
    for f in findings:
        print(f"  · {f}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
