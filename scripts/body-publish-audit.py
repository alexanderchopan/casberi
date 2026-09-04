#!/usr/bin/env python3
"""A view body must not write the observable state it reads (PERF 2026-09-01).

`ShellChrome` is `@Observable`, and its generated setter calls `withMutation`
UNCONDITIONALLY — an equal-valued write still invalidates every observer. So a
body that assigns to `chrome.<something>` and then reads it back in the same
pass invalidates itself, continuously, for as long as that view is on screen.
It is not a slow body; it is a body that never stops running.

**This is written down and it still reached two rooms.** `FeedScreen` states the
rule in `memo`'s own doc — "writing to it during a body evaluation is
memoization, not state, and must never itself schedule another render" — and
that note is why `memo` is a plain class rather than an `@Observable` one. The
Hegotá room wrote `chrome.hegotaSections` from inside `roomBody` anyway, the
Frames room copied Hegotá three weeks later, and both shipped. Wallet and
Vibenet published the identical kind of value correctly from `.onChange` the
whole time, so there was a right answer in the same file to copy from.

That is the case for a check rather than a comment: the failure is invisible
(the room renders perfectly and merely burns the main actor), no build sees it,
the screen sweep photographs a correct screen, and the fix's shape is already
established next to the bug.

WHAT IT FLAGS: an assignment to a property of the `@Observable` shell state made
from inside a body-evaluated closure — the `let _ = { chrome.x = … }()` idiom
this codebase uses to run a statement inside a `@ViewBuilder`.

WHAT IT DELIBERATELY DOES NOT FLAG, so it cannot become a lint that cries wolf:

  * `let _ = { memo… }()`. `FeedScreen.memo` is a plain class, deliberately NOT
    `@Observable`, precisely so it can be written during a body pass. That is
    memoisation, not state, and its own doc says so.
  * A write inside `.onChange`, `.task`, `.onAppear`, `.onDisappear` or a
    button action. Those are events, not body evaluation, and they are the
    correct place for exactly this publish.
  * A write to `@State`/`@Binding` from a closure. Different mechanism, and
    SwiftUI's own runtime warns about the ones that matter.

CHECK 3 is a third mechanism and the same spirit: the room's own emptiness test
must consult every array the room can DRAW from. `FeedScreen.feedThings` prefers
`sourceRoomFallbackSnapshot` — the per-source safety net's rescue array, filled
when the `@Query` disagrees with a raw fetch on the same store — while
`roomBody`'s `roomHasContent` asked `things`, the very query that net exists
because it cannot be trusted. So a rescued room drew "Nothing from <source>
yet." over a full list, and the net could never once rescue anything: both
commits that built it (85adc007, fee89e1e) added the fetch and neither touched
the test one branch upstream. Reported as a Wallet room going empty on a tap
(prd §592). It renders as a perfectly ordinary empty room, on the exact devices
where the query lies and nowhere else, so no build and no screen sweep can see
it.

CHECK 2 is unrelated in mechanism and identical in spirit: `FeedScreen`'s two
`@Query`-staleness safety nets must keep declining while the swipe's transient
`rowBudget` is set. Without that guard the mismatch they test for is
GUARANTEED — 150 rows against a room of thousands — so both run an expensive
recovery fetch on the main actor during every room swipe. It is one line, it
reads as redundant, and deleting it restores the single largest main-actor cost
in the file with nothing else going red.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi" / "Casberi" / "Screens", ROOT / "Casberi" / "Casberi" / "Shell"]

# The observable shell state. A write to one of these from a body-evaluated
# closure is the finding.
OBSERVABLE_RECEIVERS = ("chrome.",)

# `let _ = { … }()` — the idiom for running a statement inside a @ViewBuilder.
# That trailing `()` is what makes it body-evaluated rather than a stored
# closure, so it is part of the pattern rather than incidental.
BODY_CLOSURE = re.compile(r"let\s+_\s*=\s*\{(?P<body>.*?)\}\s*\(\s*\)", re.DOTALL)

ASSIGN = re.compile(
    r"\b(?P<recv>[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*)\s*(?<![=!<>+\-*/%])=(?!=)"
)


def strip_comments(text: str) -> str:
    """Comments out, string literals blanked.

    Both files DOCUMENT this rule by naming the very symbols it governs — the
    replacement lines say "published from `.onChange(of: hegotaSectionPublication)`
    … NOT written here" — so a check reading raw source scores the prose
    explaining the fix as the bug it describes. The Obsidian/Cursor lesson;
    earned again here on this check's own first run.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j == -1 else j + 2
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append('""')
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def body_publishes(text: str):
    """Assignments to observable shell state from inside a body-run closure."""
    found = []
    clean = strip_comments(text)
    for m in BODY_CLOSURE.finditer(clean):
        for a in ASSIGN.finditer(m.group("body")):
            recv = a.group("recv")
            if any(recv.startswith(p) for p in OBSERVABLE_RECEIVERS):
                line = clean.count("\n", 0, m.start() + a.start()) + 1
                found.append((line, recv))
    return found


def missing_budget_guard(text: str):
    """Every `.task(id: safetyNetKey)` must decline while `rowBudget` is set."""
    clean = strip_comments(text)
    out = []
    for m in re.finditer(r"\.task\(id:\s*safetyNetKey\)\s*\{", clean):
        depth, i, n = 0, m.end() - 1, len(clean)
        while i < n:
            if clean[i] == "{":
                depth += 1
            elif clean[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        block = clean[m.end():i]
        if not re.search(r"guard\s+rowBudget\s*==\s*nil\s+else\s*\{\s*return\s*\}", block):
            out.append(clean.count("\n", 0, m.start()) + 1)
    return out


def emptiness_ignores_fallback(text: str):
    """`roomHasContent` must name every array `feedThings` can hand back."""
    clean = strip_comments(text)
    out = []
    for m in re.finditer(r"let\s+roomHasContent\s*=", clean):
        # The expression runs to the `if` that consumes it — the next
        # statement — so take everything up to it rather than a line count,
        # which a re-wrap would silently defeat.
        tail = clean[m.end():]
        stop = tail.find("if ")
        expr = tail[:stop if stop != -1 else 400]
        if "sourceRoomFallbackSnapshot" not in expr:
            out.append(clean.count("\n", 0, m.start()) + 1)
    return out


def net_key_ignores_emptiness(text: str):
    """`safetyNetKey` must move when the room's own emptiness moves."""
    clean = strip_comments(text)
    out = []
    for m in re.finditer(r"private\s+var\s+safetyNetKey:\s*String\s*\{", clean):
        depth, i, n = 0, m.end() - 1, len(clean)
        while i < n:
            if clean[i] == "{":
                depth += 1
            elif clean[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if "things.isEmpty" not in clean[m.end():i]:
            out.append(clean.count("\n", 0, m.start()) + 1)
    return out


def self_test() -> bool:
    ok = True

    def check(name, got, want):
        nonlocal ok
        if got != want:
            print(f"  SELF-TEST FAIL {name}: got {got!r} want {want!r}")
            ok = False

    # --- check 1 fixtures ---
    check("the shipped bug", len(body_publishes(
        'let _ = { chrome.hegotaSections = HegotaRoomSource.sections() }()')), 1)
    check("its Frames twin", len(body_publishes(
        'let _ = { chrome.framesSections = FramesRoomSource.sections() }()')), 1)
    # `memo` is a plain class on purpose — writing it during a body is the
    # sanctioned pattern, and flagging it would fire on correct code.
    check("memo is not a finding", len(body_publishes(
        'let _ = { memo.themes = computeThemes() }()')), 0)
    # An event handler is where this publish BELONGS.
    check("onChange is not a finding", len(body_publishes(
        '.onChange(of: pub, initial: true) { _, now in chrome.hegotaSections = now }')), 0)
    check("onDisappear is not a finding", len(body_publishes(
        '.onDisappear { chrome.hegotaSections = [] }')), 0)
    # A closure that is never CALLED is not body-evaluated.
    check("uncalled closure is not a finding", len(body_publishes(
        'let handler = { chrome.hegotaSections = [] }')), 0)
    # Prose describing the rule must never score as the rule being broken.
    check("comment is not a finding", len(body_publishes(
        '// let _ = { chrome.hegotaSections = HegotaRoomSource.sections() }()')), 0)
    # A comparison is not an assignment.
    check("equality is not a finding", len(body_publishes(
        'let _ = { if chrome.hegotaSections == [] { ping() } }()')), 0)
    check("compound-assign is still a finding", len(body_publishes(
        'let _ = { chrome.count = chrome.count + 1 }()')), 1)

    # --- check 2 fixtures ---
    check("guarded task passes", missing_budget_guard(
        '.task(id: safetyNetKey) { guard rowBudget == nil else { return }\n f() }'), [])
    check("unguarded task is a finding", len(missing_budget_guard(
        '.task(id: safetyNetKey) { let x = 1\n f(x) }')), 1)
    check("nested braces do not end the block early", missing_budget_guard(
        '.task(id: safetyNetKey) { if a { b() }\n guard rowBudget == nil else { return } }'), [])

    # --- check 3 fixtures ---
    # The shipped bug, verbatim: the test asks the query the safety net exists
    # to distrust, while the rows come from the rescue array.
    check("the shipped emptiness bug", len(emptiness_ignores_fallback(
        "let roomHasContent = (debouncedAllSnapshot.map { !$0.isEmpty } ?? false)\n"
        "    || Corpus.hasSurfaced(things)\n"
        "if !roomHasContent { empty() }")), 1)
    check("consulting the fallback passes", emptiness_ignores_fallback(
        "let roomHasContent = (debouncedAllSnapshot.map { !$0.isEmpty } ?? false)\n"
        "    || (sourceRoomFallbackSnapshot.map { !$0.isEmpty } ?? false)\n"
        "    || Corpus.hasSurfaced(things)\n"
        "if !roomHasContent { empty() }"), [])
    # Prose naming the array is not the array being consulted — the same
    # comment-stripped rule every other check here keeps.
    check("a comment naming it is not enough", len(emptiness_ignores_fallback(
        "let roomHasContent = Corpus.hasSurfaced(things) // not sourceRoomFallbackSnapshot\n"
        "if !roomHasContent { empty() }")), 1)

    # A net keyed only on the scene and the budget never looks again when a
    # populated room goes empty mid-mount — prd §592's other half.
    check("a key without emptiness is a finding", len(net_key_ignores_emptiness(
        'private var safetyNetKey: String {\n  "\\(scenePhase)" + (rowBudget == nil ? "|full" : "|b")\n}')), 1)
    check("a key with emptiness passes", net_key_ignores_emptiness(
        'private var safetyNetKey: String {\n  "\\(scenePhase)" + (things.isEmpty ? "|empty" : "|rows")\n}'), [])

    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        good = self_test()
        print("body-publish audit self-test:", "ok" if good else "FAILED")
        return 0 if good else 1

    if not self_test():
        print("body-publish audit: its OWN self-test failed — the check is broken, not the code")
        return 1

    findings = []
    for root in SOURCES:
        for path in sorted(root.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            rel = path.relative_to(ROOT)
            for line, recv in body_publishes(text):
                findings.append(
                    f"{rel}:{line}: writes `{recv}` from a body-evaluated closure — "
                    f"an @Observable write during body invalidates the body that reads it. "
                    f"Publish from .onChange(of:initial:) instead, the way the wallet and "
                    f"vibenet rooms already do.")
            if path.name == "FeedScreen.swift":
                for line in emptiness_ignores_fallback(text):
                    findings.append(
                        f"{rel}:{line}: `roomHasContent` does not consult "
                        f"`sourceRoomFallbackSnapshot` — the room DRAWS from it "
                        f"(`feedThings` prefers it) but this asks `things`, the query "
                        f"the safety net exists because it cannot be trusted. A rescued "
                        f"room then paints its empty state over a full list (prd §592).")
                for line in net_key_ignores_emptiness(text):
                    findings.append(
                        f"{rel}:{line}: `safetyNetKey` no longer moves when the room's "
                        f"emptiness moves — a room that goes empty AFTER it mounts then "
                        f"never re-runs the net that exists to rescue it (prd §592).")
                for line in missing_budget_guard(text):
                    findings.append(
                        f"{rel}:{line}: a `.task(id: safetyNetKey)` lost its "
                        f"`guard rowBudget == nil` — while the swipe's transient bound is "
                        f"set the staleness mismatch is guaranteed, so this runs a full "
                        f"recovery fetch on the main actor during every room swipe.")

    if findings:
        print("body-publish audit: FAIL")
        for f in findings:
            print("  " + f)
        return 1
    print("body-publish audit: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
