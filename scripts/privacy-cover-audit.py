#!/usr/bin/env python3
"""Casberi privacy-cover audit (2026-08-29) — the app-switcher redaction can be
RAISED but must never be un-raisable.

    Casberi/Casberi/Shell/RootShell.swift

`handleDeactivation` puts the whole shell under `.redacted(.placeholder)` on
ANY non-active scene phase — a Control Centre pull, a Notification Centre
swipe, a system alert, a two-second peek at the app switcher — so the
app-switcher snapshot shows choreography and not content (§14, goal 6). Exactly
one line anywhere in the app clears it again, and it lives in
`handleActivation`.

WHY THIS IS MECHANICAL. `handleActivation` opens with a two-second debounce
(`guard Date.now.timeIntervalSince(lastActivation) > 2`), added 2026-08-01 so
the Mac's two launch doors cannot double-run the activation WORK. The clear sat
BELOW that guard, so any return inside two seconds swallowed it and left the
entire corpus on screen as grey placeholder bars, with no way back except
leaving again and waiting the window out. Reported 2026-08-29 as "the app is
loading very slowly" — nothing was loading; every row was already there, wearing
`.placeholder`. That is the failure this audit exists for and it is INVISIBLE to
everything else in the tree: it compiles, every static audit passes, the screen
sweep photographs a redacted screen that looks like a screen mid-load, and no
harness here can drive a scene phase at all.

Three checks, all static, all on a COMMENT-STRIPPED copy — this file documents
the bug by naming the very symbols it governs, so a guard reading raw source is
satisfied by the prose explaining it (the Obsidian/Cursor lesson).

  A. The cover is still APPLIED: a `.redacted(reason:` modifier reads the flag.
     Without this the other two checks pass over a feature that no longer draws.
  B. The cover is RAISED in exactly one place, and that place is
     `handleDeactivation`. A second setter elsewhere is a second way in that
     this audit's ordering rule would not cover.
  C. The cover is CLEARED inside `handleActivation`, ABOVE the debounce guard.
     This is the ordering the bug was.

Deliberately NOT checked: whether redaction on `.inactive` is right (it is —
iOS samples the snapshot before `.background`), and whether the Mac is exempt
(it is, and that is `handleDeactivation`'s own business). This audit only
proves the cover can always come off.

Pure, local, deterministic. `--self-test` first, then the tree. Exit non-zero on
failure.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SHELL = Path("Casberi/Casberi/Shell/RootShell.swift")

FLAG = "redactNow"
DEBOUNCE = r"guard\s+Date\.now\.timeIntervalSince\(lastActivation\)"
ACTIVATION = r"func\s+handleActivation\s*\("
DEACTIVATION = r"func\s+handleDeactivation\s*\("


def strip_comments(text: str) -> str:
    """Blank `//` comments and `/* */` blocks, preserving line numbering.

    Line-wise and deliberately naive about `//` inside a string literal — this
    file has no URL literals in the region that matters, and over-stripping
    here can only ever LOSE a match, i.e. fail loudly, never pass silently.

    A LINE COMMENT WINS OVER A BLOCK OPENER THAT FOLLOWS IT ON THE SAME LINE,
    and that is not a nicety (2026-09-01). This looked for `/*` first, so a
    `//` comment that merely MENTIONS a glob — `scripts/output/<run>/perf.txt`
    written with a `*` for the run — contains the two characters `/` `*`, was
    read as an unterminated block opener, and blanked EVERY LINE AFTER IT to
    the end of the file. All three checks then failed at once, reporting that
    the privacy cover was gone from a file where all five of its symbols were
    present and correct. That is the worst shape a guard can fail in: it
    accuses the code, and the accusation looks exactly like the real bug this
    audit exists to catch. Found when a perf comment cited a glob path.
    """
    out = []
    in_block = False
    for line in text.split("\n"):
        if in_block:
            end = line.find("*/")
            if end == -1:
                out.append("")
                continue
            line = " " * (end + 2) + line[end + 2:]
            in_block = False
        # WHICHEVER OPENS FIRST WINS. Testing one delimiter before the other
        # is wrong in one direction or the other, and both directions were
        # written before this one: `/*`-first blanks the file on a `//` that
        # mentions a glob, and `//`-first breaks on a `//` sitting INSIDE a
        # one-line `/* … */`. Scanning left to right is the only rule that
        # needs no exception.
        pos = 0
        while True:
            b = line.find("/*", pos)
            s = line.find("//", pos)
            if s != -1 and (b == -1 or s < b):
                line = line[:s]
                break
            if b == -1:
                break
            end = line.find("*/", b + 2)
            if end == -1:
                line = line[:b]
                in_block = True
                break
            line = line[:b] + " " * (end + 2 - b) + line[end + 2:]
            pos = end + 2
        out.append(line)
    return "\n".join(out)


def first_line(lines: list[str], pattern: str) -> int | None:
    rx = re.compile(pattern)
    for i, line in enumerate(lines):
        if rx.search(line):
            return i
    return None


def all_lines(lines: list[str], pattern: str) -> list[int]:
    rx = re.compile(pattern)
    return [i for i, line in enumerate(lines) if rx.search(line)]


def audit(source: str) -> list[str]:
    """Return a list of findings; empty means clean."""
    lines = strip_comments(source).split("\n")
    findings: list[str] = []

    # --- A. the cover is still applied ---------------------------------------
    if not re.search(r"\.redacted\(reason:[^)]*" + FLAG, "\n".join(lines)):
        findings.append(
            f"no `.redacted(reason:` reads `{FLAG}` — the privacy cover no "
            "longer draws, so checks B and C prove nothing"
        )

    # --- B. one setter, inside handleDeactivation ----------------------------
    raises = all_lines(lines, rf"\b{FLAG}\s*=\s*true\b")
    deact = first_line(lines, DEACTIVATION)
    if not raises:
        findings.append(f"nothing ever sets `{FLAG} = true` — the cover never rises")
    elif deact is None:
        findings.append("`handleDeactivation` not found — the cover has no owner")
    else:
        stray = [i for i in raises if i < deact]
        if stray:
            findings.append(
                f"`{FLAG} = true` at line {stray[0] + 1} sits outside "
                "`handleDeactivation` — a second way to raise the cover that "
                "check C's ordering rule does not cover"
            )

    # --- C. cleared inside handleActivation, above the debounce --------------
    act = first_line(lines, ACTIVATION)
    if act is None:
        findings.append("`handleActivation` not found — nothing can clear the cover")
        return findings

    clears = [i for i in all_lines(lines, rf"\b{FLAG}\s*=\s*false\b") if i > act]
    if not clears:
        findings.append(
            f"nothing sets `{FLAG} = false` inside `handleActivation` — once "
            "the cover rises there is no way back"
        )
        return findings

    guard = None
    for i, line in enumerate(lines):
        if i > act and re.search(DEBOUNCE, line):
            guard = i
            break
    if guard is None:
        # No debounce at all is fine: nothing can swallow the clear.
        return findings

    if min(clears) > guard:
        findings.append(
            f"`{FLAG} = false` (line {min(clears) + 1}) sits BELOW the "
            f"activation debounce (line {guard + 1}) — a return inside the "
            "debounce window leaves the whole app as placeholder bars, with no "
            "way back except leaving again. Hoist the clear above the guard."
        )

    return findings


# --- fixtures ----------------------------------------------------------------

CLEAN = """
    private var shellPhaseAware: some View {
        shellBase
        .redacted(reason: redactNow ? .placeholder : [])
    }

    @MainActor
    private func handleActivation() {
        if redactNow { withAnimation { redactNow = false } }
        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }
        lastActivation = .now
    }

    @MainActor
    private func handleDeactivation(phase: ScenePhase) {
        if hasBeenActive && hidePreviews { redactNow = true }
    }
"""

BELOW_GUARD = CLEAN.replace(
    "        if redactNow { withAnimation { redactNow = false } }\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n",
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n"
    "        withAnimation { redactNow = false }\n",
)

NO_CLEAR = CLEAN.replace(
    "        if redactNow { withAnimation { redactNow = false } }\n", ""
)

# The clear present only as PROSE above the guard, the real one below it — the
# exact shape a raw-source grep would score as compliant.
COMMENT_ONLY = CLEAN.replace(
    "        if redactNow { withAnimation { redactNow = false } }\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n",
    "        // the crossfade below does `redactNow = false` on every return\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n"
    "        withAnimation { redactNow = false }\n",
)

STRAY_RAISE = CLEAN.replace(
    "    private var shellPhaseAware: some View {\n",
    "    private func somethingElse() { redactNow = true }\n"
    "    private var shellPhaseAware: some View {\n",
)

NOT_DRAWN = CLEAN.replace(".redacted(reason: redactNow ? .placeholder : [])", "")

NO_DEBOUNCE = CLEAN.replace(
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n", ""
)

# A `//` comment that merely MENTIONS a glob, ABOVE everything this audit
# looks for. The two characters `/` `*` inside it used to read as an
# unterminated block-comment opener, which blanked every line after it and made
# all three checks fail at once against a file whose cover was perfectly
# intact. This fixture is the regression: it must come back CLEAN (2026-09-01,
# found when a perf comment cited a run-directory glob).
GLOB_IN_COMMENT = (
    "    // compare against the old numbers in scripts/output/*/perf.txt\n" + CLEAN
)

# The other direction, which the first cut of that fix broke: a `//` sitting
# INSIDE a one-line `/* … */`. Cutting at the line comment first would leave an
# unterminated opener and blank the file just as badly, so the rule is
# whichever delimiter opens FIRST — not one tested before the other.
SLASHES_INSIDE_BLOCK = (
    "    /* a // b */ let x = 1\n" + CLEAN
)


def self_test() -> int:
    cases = [
        ("clean tree", CLEAN, False),
        ("clear below the debounce guard", BELOW_GUARD, True),
        ("no clear at all", NO_CLEAR, True),
        ("clear above the guard only in a comment", COMMENT_ONLY, True),
        ("a second raise outside handleDeactivation", STRAY_RAISE, True),
        ("the cover no longer draws", NOT_DRAWN, True),
        ("no debounce — nothing to swallow the clear", NO_DEBOUNCE, False),
        ("a glob in a line comment does not blank the file", GLOB_IN_COMMENT, False),
        ("slashes inside a one-line block comment", SLASHES_INSIDE_BLOCK, False),
    ]
    bad = 0
    for name, fixture, should_fail in cases:
        findings = audit(fixture)
        got = bool(findings)
        if got != should_fail:
            want = "a finding" if should_fail else "no findings"
            print(f"  ✗ self-test: {name} — expected {want}, got {findings or 'none'}")
            bad += 1
        else:
            print(f"  ✓ self-test: {name}")
    return bad


def main() -> int:
    if "--self-test" in sys.argv:
        bad = self_test()
        if bad:
            print(f"✗ privacy-cover audit self-test: {bad} case(s) wrong")
            return 1
        print("✓ privacy-cover audit self-test: 9/9")
        return 0

    if not SHELL.is_file():
        print(f"✗ {SHELL} not found (run from the repo root)")
        return 1

    findings = audit(SHELL.read_text(encoding="utf-8"))
    if findings:
        print(f"✗ privacy-cover audit — {SHELL}")
        for f in findings:
            print(f"  • {f}")
        return 1
    print("✓ privacy-cover audit: the app-switcher cover always comes off")
    return 0


if __name__ == "__main__":
    sys.exit(main())
