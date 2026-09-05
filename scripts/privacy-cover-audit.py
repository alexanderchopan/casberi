#!/usr/bin/env python3
"""Casberi privacy-cover audit (2026-08-29) — the app-switcher cover can be
RAISED but must never be un-raisable, and must never be drawn by redacting the
shell.

    Casberi/Casberi/Shell/RootShell.swift
    Casberi/Casberi/Shell/PrivacyCover.swift

`handleDeactivation` covers the app on ANY non-active scene phase — a Control
Centre pull, a Notification Centre swipe, a system alert, a two-second peek at
the app switcher — so the snapshot iOS takes shows the mark and not content
(§14, goal 6). Exactly one line anywhere in the app lowers it again, and it
lives in `handleActivation`.

**AMENDED 2026-09-05 — the cover is a `UIWindow`, and check D is why.** It was
`.redacted(reason: redactNow ? .placeholder : [])` on `shellBase`, i.e. a
`RedactionReasons` change at the ROOT of the app, which invalidates every view
in the tree. That full-graph update lands in the `CATransaction` UIKit commits
to take the snapshot, and a backgrounded app is CPU-throttled, so it killed two
shipped builds with the same watchdog: `0x8BADF00D`, scene-update, "exhausted
real (wall clock) time allowance of 10.00 seconds" — build 521 inside
`-[UIApplication _createSnapshotContextForScene:…]` → `ForEachChild.updateValue`
→ `AG::LayoutDescriptor::Compare`, build 511 in the same full-graph update
flushed by the ordinary update sequence. Both reports name their own throttle:
10.279s of app CPU at 16%, and 7.723s at 13%. So the mechanism is not a detail
of how the cover is spelled — it is the whole difference between a cover and a
crash, and check D holds the line.

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

Four checks, all static, all on a COMMENT-STRIPPED copy — this file documents
the bug by naming the very symbols it governs, so a guard reading raw source is
satisfied by the prose explaining it (the Obsidian/Cursor lesson).

  A. The cover still DRAWS: the shell calls `PrivacyCover.show()`, and
     `PrivacyCover` really installs a `UIWindow` and unhides it. Without this
     the other checks pass over a feature that no longer covers anything.
  B. The cover is RAISED in exactly one place, and that place is
     `handleDeactivation`. A second raise elsewhere is a second way in that
     this audit's ordering rule would not cover.
  C. The cover is LOWERED inside `handleActivation`, ABOVE the debounce guard.
     This is the ordering the 2026-08-29 bug was.
  D. The shell carries NO `.redacted(reason:` at all. A redaction anywhere in
     this file is on the root modifier chain, which is the watchdog above.

Deliberately NOT checked: whether covering on `.inactive` is right (it is —
iOS samples the snapshot before `.background`), whether the Mac is exempt (it
is, and that is `handleDeactivation`'s own business), and whether individual
image views still honour `redactionReasons` (they do and should, but the window
covers them either way). This audit proves the cover always comes off, and that
it is never drawn the way that crashed.

Pure, local, deterministic. `--self-test` first, then the tree. Exit non-zero on
failure.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

SHELL = Path("Casberi/Casberi/Shell/RootShell.swift")
COVER = Path("Casberi/Casberi/Shell/PrivacyCover.swift")

RAISE = r"PrivacyCover\.show\s*\("
LOWER = r"PrivacyCover\.hide\s*\("
DEBOUNCE = r"guard\s+Date\.now\.timeIntervalSince\(lastActivation\)"
ACTIVATION = r"func\s+handleActivation\s*\("
DEACTIVATION = r"func\s+handleDeactivation\s*\("
# The window itself. Both halves matter: a `UIWindow` that is never unhidden
# covers nothing, and an unhidden view that is not a window cannot sit above a
# presented sheet — which is where a screenshot is shown full-bleed.
WINDOW = r"UIWindow\(windowScene:"
UNHIDE = r"\bisHidden\s*=\s*false\b"


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


def audit(source: str, cover: str = "") -> list[str]:
    """Return a list of findings; empty means clean.

    `cover` is `PrivacyCover.swift`'s source. It defaults to empty ONLY so the
    self-test can drive the shell checks on their own; the real run always
    passes it, and an empty one is reported by check A rather than skipped.
    """
    lines = strip_comments(source).split("\n")
    findings: list[str] = []

    # --- A. the cover still draws --------------------------------------------
    if not re.search(RAISE, "\n".join(lines)):
        findings.append(
            "the shell never calls `PrivacyCover.show()` — the cover no "
            "longer draws, so checks B and C prove nothing"
        )
    cover_lines = strip_comments(cover)
    if not (re.search(WINDOW, cover_lines) and re.search(UNHIDE, cover_lines)):
        findings.append(
            "`PrivacyCover` does not install and unhide a `UIWindow` — a cover "
            "that is not a window cannot sit above a presented sheet, which is "
            "where a screenshot is shown full-bleed"
        )

    # --- D. and never by redacting the shell ---------------------------------
    # The whole reason the cover is a window (see this file's header): a
    # `.redacted(reason:` anywhere in the shell is on the root modifier chain,
    # and invalidating the root tree on background is what tripped the
    # scene-update watchdog on builds 511 and 521.
    redacted = all_lines(lines, r"\.redacted\(reason:")
    if redacted:
        findings.append(
            f"`.redacted(reason:` at line {redacted[0] + 1} — a redaction on "
            "the shell's root chain invalidates the whole view tree on every "
            "background, which is the 0x8BADF00D scene-update watchdog that "
            "killed builds 511 and 521. The cover is a window; keep it one"
        )

    # --- B. one raise, inside handleDeactivation -----------------------------
    raises = all_lines(lines, RAISE)
    deact = first_line(lines, DEACTIVATION)
    if raises and deact is None:
        findings.append("`handleDeactivation` not found — the cover has no owner")
    elif raises:
        stray = [i for i in raises if i < deact]
        if stray:
            findings.append(
                f"`PrivacyCover.show()` at line {stray[0] + 1} sits outside "
                "`handleDeactivation` — a second way to raise the cover that "
                "check C's ordering rule does not cover"
            )

    # --- C. lowered inside handleActivation, above the debounce --------------
    act = first_line(lines, ACTIVATION)
    if act is None:
        findings.append("`handleActivation` not found — nothing can lower the cover")
        return findings

    clears = [i for i in all_lines(lines, LOWER) if i > act]
    if not clears:
        findings.append(
            "nothing calls `PrivacyCover.hide()` inside `handleActivation` — "
            "once the cover rises there is no way back"
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
            f"`PrivacyCover.hide()` (line {min(clears) + 1}) sits BELOW the "
            f"activation debounce (line {guard + 1}) — a return inside the "
            "debounce window leaves the whole app under the cover, with no "
            "way back except leaving again. Hoist the lower above the guard."
        )

    return findings


# --- fixtures ----------------------------------------------------------------

COVER_CLEAN = """
@MainActor
enum PrivacyCover {
    private static var window: UIWindow?
    static func show() {
        guard let scene = hostScene() else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.rootViewController = UIHostingController(rootView: CoverContent())
        w.isHidden = false
        window = w
    }
    static func hide() { window?.isHidden = true; window = nil }
}
"""

# A cover that builds a plain view instead of a window: it cannot rise above a
# presented sheet, which is exactly where a full-bleed screenshot is shown.
COVER_NOT_A_WINDOW = COVER_CLEAN.replace("let w = UIWindow(windowScene: scene)",
                                         "let w = UIView()")

CLEAN = """
    private var shellPhaseAware: some View {
        shellBase
        .onChange(of: scenePhase) { _, phase in }
    }

    @MainActor
    private func handleActivation() {
        PrivacyCover.hide()
        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }
        lastActivation = .now
    }

    @MainActor
    private func handleDeactivation(phase: ScenePhase) {
        if hasBeenActive && hidePreviews { PrivacyCover.show() }
    }
"""

BELOW_GUARD = CLEAN.replace(
    "        PrivacyCover.hide()\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n",
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n"
    "        PrivacyCover.hide()\n",
)

NO_CLEAR = CLEAN.replace("        PrivacyCover.hide()\n", "")

# The lower present only as PROSE above the guard, the real one below it — the
# exact shape a raw-source grep would score as compliant.
COMMENT_ONLY = CLEAN.replace(
    "        PrivacyCover.hide()\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n",
    "        // the return path below calls PrivacyCover.hide() on every wake\n"
    "        guard Date.now.timeIntervalSince(lastActivation) > 2 else { return }\n"
    "        PrivacyCover.hide()\n",
)

STRAY_RAISE = CLEAN.replace(
    "    private var shellPhaseAware: some View {\n",
    "    private func somethingElse() { PrivacyCover.show() }\n"
    "    private var shellPhaseAware: some View {\n",
)

NOT_DRAWN = CLEAN.replace("if hasBeenActive && hidePreviews { PrivacyCover.show() }", "")

# Check D's own mutation: the root redaction put back, cover and all. This is
# the shape that shipped in 511 and 521 and tripped the scene-update watchdog,
# and it passes every other check in this file — the cover still rises, still
# lowers, still lowers above the guard.
REDACTED_BACK = CLEAN.replace(
    "        shellBase\n",
    "        shellBase\n        .redacted(reason: redactNow ? .placeholder : [])\n",
)

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


def self_test() -> tuple[int, int]:
    cases = [
        ("clean tree", CLEAN, COVER_CLEAN, False),
        ("lower below the debounce guard", BELOW_GUARD, COVER_CLEAN, True),
        ("no lower at all", NO_CLEAR, COVER_CLEAN, True),
        ("lower above the guard only in a comment", COMMENT_ONLY, COVER_CLEAN, True),
        ("a second raise outside handleDeactivation", STRAY_RAISE, COVER_CLEAN, True),
        ("the cover no longer draws", NOT_DRAWN, COVER_CLEAN, True),
        ("the cover is not a window", CLEAN, COVER_NOT_A_WINDOW, True),
        ("the root redaction put back", REDACTED_BACK, COVER_CLEAN, True),
        ("no debounce — nothing to swallow the lower", NO_DEBOUNCE, COVER_CLEAN, False),
        ("a glob in a line comment does not blank the file",
         GLOB_IN_COMMENT, COVER_CLEAN, False),
        ("slashes inside a one-line block comment",
         SLASHES_INSIDE_BLOCK, COVER_CLEAN, False),
    ]
    bad = 0
    for name, fixture, cover, should_fail in cases:
        findings = audit(fixture, cover)
        got = bool(findings)
        if got != should_fail:
            want = "a finding" if should_fail else "no findings"
            print(f"  ✗ self-test: {name} — expected {want}, got {findings or 'none'}")
            bad += 1
        else:
            print(f"  ✓ self-test: {name}")
    return bad, len(cases)


def main() -> int:
    if "--self-test" in sys.argv:
        bad, total = self_test()
        if bad:
            print(f"✗ privacy-cover audit self-test: {bad} case(s) wrong")
            return 1
        print(f"✓ privacy-cover audit self-test: {total}/{total}")
        return 0

    for path in (SHELL, COVER):
        if not path.is_file():
            print(f"✗ {path} not found (run from the repo root)")
            return 1

    findings = audit(SHELL.read_text(encoding="utf-8"),
                     COVER.read_text(encoding="utf-8"))
    if findings:
        print(f"✗ privacy-cover audit — {SHELL}")
        for f in findings:
            print(f"  • {f}")
        return 1
    print("✓ privacy-cover audit: the app-switcher cover always comes off")
    return 0


if __name__ == "__main__":
    sys.exit(main())
