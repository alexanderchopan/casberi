#!/usr/bin/env python3
"""swiftdata-liveness-audit — enforce the "never read a dead Thing" rule.

CLAUDE.md's recurring crash class: builds 137, 138, 139, 142 and 150 were all
the same defect, each found by a TestFlight user, each fixed one site at a
time. Reading a stored property of a SwiftData @Model AFTER it has been
deleted or invalidated traps inside SwiftData (_assertionFailure →
EXC_BREAKPOINT). The app deletes Things on the MAIN context while the UI is
live — SyncReconcile at launch, a per-foreground heal in nearly every bridge,
plus CloudKit-propagated deletes — so this is not a rare race, it is the
normal case.

The rule has been written down since build 139 and re-broken twice anyway,
because it is enforced by memory. This makes it mechanical.

CHECK 1 — DERIVED FOREACH.
  A `ForEach` **directly** over a @Query array is coordinated by SwiftData and
  is safe. A `ForEach` over a DERIVED array holding raw Thing refs is NOT:
  SwiftUI re-reads each element's `id` during identity diffing on every graph
  update, including the exact transaction a delete lands. "Derived" includes
  an inline chain off a @Query array (`ForEach(things.filter { … })`) — the
  chain produces a plain Array that SwiftData no longer coordinates, which is
  why a bare-name allowance must not extend to a chained one.
  Such a ForEach must go through `.keyed` (Screens/ThingRowKeying.swift),
  which captures the id as a String while the model is still valid.

CHECK 2 — HELD REFERENCES.
  A Thing kept in @State — or an array of them — outlives the body that made
  it, so a delete can land under an open sheet or a pushed screen. Reads of a
  held ref must be guarded by `isLive` (single ref) or `.live` (array).
  Flagged only when the file BOTH holds a Thing in @State AND reads a STORED
  property off that held name — a screen that merely holds an array and hands
  it to a renderer which guards (RecentThingsSection) is not a finding, and a
  lint that cried wolf there would be turned off within a week. The stored-
  property set is read out of Shared/Thing.swift at audit time, so a new
  @Model field is covered the day it is added.

CHECK 3 — KEYED FOREACH, UNGUARDED BODY.
  Keying fixes IDENTITY DIFFING and nothing else. `ForEachChild.updateValue()`
  re-evaluates the CONTENT closure against the array the ForEach value already
  holds, under its own observation callback, when a tracked model changes —
  the parent body has not re-run, so the array still holds the row that was
  just deleted, and the closure's first stored-property read traps. Upstream
  filtering (`rows.filter(\\.isLive)`, a `liveXs` computed property) does NOT
  count: it ran when the view value was made, which is before the delete.
  So a ForEach content closure that reaches `.thing` must re-check liveness
  INSIDE the closure — `if let thing = row.live { … }`.

Corollary 2 (build 150) is why check 1 is not only about the ForEach line: a
correctly-keyed ForEach still crashed because the SECTION HEADER beside it did
`Set(rows.map(\\.kind))` over the same raw derived array. The fix there is
`filter(\\.isLive)` once at the top of the view that owns the array — which
check 2's file-level `isLive` requirement also nudges toward.

Corollary 3 (build 176) is why check 3 exists at all: the feed's day rows were
correctly keyed, the header was correctly filtered, check 1 and check 2 both
passed — and it crashed on first open anyway, on `thing.kind` in the row
builder. Every rule the audit knew was being followed. Note the deliberate
limit: check 3 triggers on `.thing`, so a Thing bound out of some other
wrapper is invisible to it. That is why `FeedScreen.FeedRow.single` carries a
`KeyedThing` rather than a raw `Thing` — the crash site is kept in the shape
the lint can see. Keep new wrappers that way too.

CHECK 5 — THE LEAF (build 188, and the deepest form of the class).
  Checks 1/3/4 are all about the CONTAINER, and a container guard only stops a
  dead row being CREATED. SwiftUI re-evaluates a leaf view's body on the
  MODEL'S OWN observation, through that leaf's own attribute node
  (`DynamicBody.updateValue` → `ViewBodyAccessor.updateBody`), with no
  involvement from the parent — so a row ALREADY in the tree is untouched by
  anything the parent does. 188 crashed on exactly that: `BandRow.body` →
  `mailSender` → `thing.kind`, re-run inside a UICollectionView batch update
  while the source pager animated. Keying was right, the ForEach closure guard
  was right, the boundary filter was right, and none of them were in the path.
  A View struct storing a `Thing` guards its own body:
      var body: some View { if thing.isLive { liveBody } }
      @ViewBuilder private var liveBody: some View { …original… }
  This was already CLAUDE.md's build-142 lesson ("guard the sheet's CHILD
  views … the parent's guard doesn't cover a child SwiftUI re-renders on the
  model's own observation") — scoped to two sheet views and never generalised
  to the 25 row/content views with the identical shape. This check is that
  generalisation.

Runs in verify.sh (pure static text check, no build needed).
Exit non-zero on any unguarded site.  --self-test proves the checks can fail.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [
    "Casberi/Casberi/Screens",
    "Casberi/Casberi/Shell",
    "Casberi/Casberi/Design",
    # GenUI renders Things too — it was outside the audit until 2026-07-28.
    "Casberi/Casberi/GenUI",
    # Model/ joined 2026-08-03: build 250 crashed in `TodayBrief.compose`,
    # async MODEL code holding a [Thing] across an await. Checks 1–5 are all
    # view-shaped and simply find nothing here; CHECK 6 is the one that bites.
    "Casberi/Casberi/Model",
]

# Files that legitimately hold Things in @State with no isLive guard. Adding
# one is a conscious "no stored property of a held Thing is ever read here" —
# e.g. the ref is only passed onward by identity, or re-fetched on every read.
KNOWN_UNGUARDED: set[str] = set()

# Check 4's escape hatch, keyed on (file, exact line). Adding one is a
# conscious "filtering HERE would be wrong, and the read is guarded where it
# actually happens" — never "the lint is in my way". The reason is required
# because the whole crash class comes from unwritten promises.
HANDOFF_OK: dict[tuple[str, str], str] = {
    ("TokenWatchScreen.swift", "unwatch(displayed: watched, at: offsets)"):
        "`offsets` index the array the caller displayed (resolved via "
        "firstIndex at the tap), so filtering the source would misalign them. "
        "unwatch(displayed:) filters the DROPPED rows instead.",
}

# `@Query … var name: [Thing]` / `@Query(descriptor) private var name: [Thing]`
QUERY_DECL = re.compile(r"@Query\b[^\n]*?\bvar\s+([A-Za-z_]\w*)")
# Any [Thing]-typed property or local, however declared.
THING_DECL = re.compile(r"\b(?:var|let)\s+([A-Za-z_]\w*)\s*:\s*\[Thing\]")
# A held single/array Thing in @State — captures the NAME so check 2 can look
# for stored-property reads off exactly that identifier.
HELD_DECL = re.compile(r"@State[^\n]*?\bvar\s+([A-Za-z_]\w*)\s*:\s*(?:\[Thing\]|Thing\?)")
# Check 5: `struct X: View {` (possibly with other conformances/generics), and
# a STORED `Thing` property on it. The struct extent is found by scanning to the
# next top-level declaration — crude, but these are all file-scope value types.
# Check 6: an `async` func that takes a `[Thing]` — the shape that can hold a
# model across a suspension.
ASYNC_THING_FUNC = re.compile(
    r"^\s*(?:@\w+\s+)*(?:private |static |public |final )*func\s+(\w+)\s*\([^)]*\[Thing\][^)]*\)[^\n{]*\basync\b[^\n{]*\{",
    re.M | re.S)

# Check 7: an `async` func that takes a BARE `Thing` — check 6's sibling, and
# the gap that let build 256's crash ship. `[^)]*(?<!\[)\bThing\b(?!\])` is the
# whole difference: one Thing, not an array of them.
ASYNC_ONE_THING_FUNC = re.compile(
    r"^\s*(?:@\w+\s+)*(?:private |static |public |final )*func\s+(\w+)\s*"
    r"\([^)]*(?<!\[)\bThing\b(?!\])[^)]*\)[^\n{]*\basync\b[^\n{]*\{",
    re.M | re.S)

VIEW_STRUCT = re.compile(r"^(?:private |public )?struct (\w+)[^\n{]*:\s*[^\n{]*\bView\b[^\n{]*\{", re.M)
STORED_THING_PROP = re.compile(r"^\s{0,8}(?:let|var)\s+(\w*[Tt]hing\w*)\s*:\s*Thing\b", re.M)

# Check 4's narrower target: a held ARRAY of Things (optional or not). Arrays
# are what get handed onward wholesale into helpers that then iterate them.
HELD_ARRAY_DECL = re.compile(r"@State[^\n]*?\bvar\s+([A-Za-z_]\w*)\s*:\s*\[Thing\]\??")
# Collection ops that turn a coordinated @Query array into a plain Array.
DERIVING_OP = re.compile(r"\.(?:filter|map|compactMap|flatMap|sorted|prefix|suffix|reversed|dropFirst|dropLast|shuffled)\s*[({]")


def thing_stored_properties() -> set[str]:
    """The @Model's STORED properties — the ones whose read traps once dead.

    Parsed out of Shared/Thing.swift rather than hardcoded, so a new field is
    covered the day it lands. A computed property (`var x: T {`) is excluded:
    it isn't persisted, and its own body is what would trap, not the access.
    """
    src = (ROOT / "Casberi/Shared/Thing.swift").read_text(encoding="utf-8")
    start = src.find("final class Thing")
    if start < 0:
        raise SystemExit("swiftdata-liveness-audit: can't find `final class Thing` — model moved?")
    body = src[start:]
    props = set()
    for line in body.splitlines():
        m = re.match(r"\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+([A-Za-z_]\w*)\s*:\s*[^{=]+(=|$)", line)
        if m:
            props.add(m.group(1))
    return props


def foreach_argument(line: str, start: int) -> str:
    """Return the text inside the ForEach(...) starting at `start`, brace-aware."""
    depth = 0
    out = []
    for ch in line[start:]:
        if ch in "([{":
            depth += 1
            if depth == 1 and ch == "(":
                continue
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                break
        if depth >= 1:
            out.append(ch)
    return "".join(out)


def _strip_noncode(s: str) -> str:
    """Blank comments and string literals, PRESERVING length and newlines.

    Length-preserving because check 3 slices the original text by offsets
    computed here. A one-pass scanner rather than two regex passes: this
    codebase has `//` inside string literals (every API host) and `"` inside
    comments (every quoted ruling), so whichever of the two you strip first
    with a regex, the other one corrupts it.
    """
    out = list(s)
    i, n = 0, len(s)
    in_str = in_line_comment = in_block_comment = False
    while i < n:
        c = s[i]
        nxt = s[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            else:
                out[i] = " "
        elif in_block_comment:
            if c == "*" and nxt == "/":
                out[i] = out[i + 1] = " "
                i += 2
                in_block_comment = False
                continue
            if c != "\n":
                out[i] = " "
        elif in_str:
            out[i] = " "
            if c == "\\":
                if i + 1 < n and nxt != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if c == '"' or c == "\n":   # an unterminated literal ends at EOL
                in_str = False
        elif c == "/" and nxt == "/":
            out[i] = out[i + 1] = " "
            i += 2
            in_line_comment = True
            continue
        elif c == "/" and nxt == "*":
            out[i] = out[i + 1] = " "
            i += 2
            in_block_comment = True
            continue
        elif c == '"':
            out[i] = " "
            in_str = True
        i += 1
    return "".join(out)


def foreach_content_closures(text: str):
    """Yield (line number, body text) for every `ForEach(…) { … }` closure.

    The body is the trailing view-builder closure — the thing check 3 cares
    about. Brace-matched over the whole file rather than per line, since a row
    body spans dozens of lines.
    """
    code = _strip_noncode(text)
    for m in re.finditer(r"\bForEach\s*\(", code):
        # Walk the ForEach's own parenthesised argument to its close.
        depth, i = 0, m.end() - 1
        while i < len(code):
            if code[i] in "([{":
                depth += 1
            elif code[i] in ")]}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if i >= len(code):
            continue
        j = i + 1
        while j < len(code) and code[j] in " \t\n":
            j += 1
        if j >= len(code) or code[j] != "{":
            continue  # `ForEach(…)` with the content passed some other way
        depth, k = 0, j
        while k < len(code):
            if code[k] == "{":
                depth += 1
            elif code[k] == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        if k >= len(code):
            continue
        # Report against the ORIGINAL text so comments/strings are readable.
        yield code.count("\n", 0, m.start()) + 1, text[j + 1:k]


STORED: set[str] = set()


def audit_file(path: pathlib.Path, findings: list[str]) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    rel = path.relative_to(ROOT)
    query_names = set(QUERY_DECL.findall(text))
    thing_names = set(THING_DECL.findall(text)) | query_names

    # ── Check 1: derived ForEach without .keyed ──────────────────────
    # (Skipped when the file declares no [Thing] array — nothing to iterate.
    # Check 2 below still runs: a held `Thing?` needs no array declaration.)
    for lineno, line in enumerate(text.splitlines(), 1) if thing_names else []:
        for m in re.finditer(r"\bForEach\(", line):
            arg = foreach_argument(line, m.end() - 1)
            # Which [Thing] identifiers does this ForEach actually mention?
            mentioned = {n for n in thing_names if re.search(rf"\b{re.escape(n)}\b", arg)}
            if not mentioned:
                continue
            if "keyed" in arg:
                continue
            # A BARE @Query array (`ForEach(things)`, `ForEach(things, id: \.id)`)
            # is coordinated by SwiftData — the one safe raw case.
            bare = arg.split(",")[0].strip()
            if bare in query_names and not DERIVING_OP.search(arg):
                continue
            why = (
                "chained off a @Query array"
                if mentioned & query_names and DERIVING_OP.search(arg)
                else "derived [Thing] array"
            )
            findings.append(
                f"✗ {rel}:{lineno} — ForEach over a {why} without .keyed\n"
                f"      {line.strip()[:120]}"
            )

    # ── Check 3: keyed ForEach whose CONTENT closure reads a model ───
    # Corollary 3 (build 176, 2026-07-28). `keyed` protects identity diffing
    # and nothing else. `ForEachChild.updateValue()` re-evaluates the CONTENT
    # closure against the array the ForEach value already holds, under its own
    # observation callback, when a tracked model changes — the parent body has
    # not re-run, so the array still holds the row that was just deleted, and
    # the first stored-property read in the closure traps. Filtering upstream
    # (`rows.filter(\.isLive)`, a `liveXs` computed property) does NOT count:
    # that ran when the view value was made, which is before the delete.
    # So: any ForEach content closure that reaches `.thing` must re-check
    # liveness INSIDE the closure.
    for lineno, body in foreach_content_closures(text):
        # `\b` matters: `.thingID` is a plain String on a brief's move row, and
        # a substring match reported it as a dead-model read (false positive
        # caught 2026-07-28, the first time this check was pointed at GenUI).
        if not re.search(r"\.thing\b", body):
            continue
        if "isLive" in body or ".live" in body:
            continue
        findings.append(
            f"✗ {rel}:{lineno} — ForEach content closure reads .thing with no "
            f"isLive guard inside the closure\n"
            f"      {body.strip().splitlines()[0][:110] if body.strip() else ''}"
        )

    # ── Check 5: a LEAF View holding a Thing, body unguarded ─────────
    # Build 188, and the deepest form of this class. SwiftUI re-evaluates a
    # leaf view's body on the MODEL'S OWN observation, through its own
    # attribute node (`DynamicBody.updateValue` → `ViewBodyAccessor`), with no
    # involvement from the parent that built it. So checks 1/3/4 — all about
    # the container — cannot protect a row that is ALREADY in the tree: they
    # stop a dead row being created, and 188 crashed on one that already
    # existed (`BandRow.body` → `mailSender` → `thing.kind`, re-run inside a
    # UICollectionView batch update while the pager animated).
    # The lesson was already in CLAUDE.md from build 142, scoped to sheet
    # CHILD views, and never generalised to the 25 row/content views that had
    # the identical shape. THE RULE: a View struct storing a `Thing` guards its
    # own body.
    # Read a COMMENT-STRIPPED copy, or a guard NAMED IN PROSE clears the
    # struct (2026-08-06). This check tested the raw text, so a doc line
    # mentioning another row's `.live` counted as this row's guard — which is
    # precisely how `MediaRow`, the row every podcast renders through, carried
    # no guard at all and passed this audit every night. `_strip_noncode`
    # preserves length and newlines, so the reported line numbers, which are
    # still counted against the ORIGINAL text, stay correct.
    # Same correction `cursor-selftest.sh` and `obsidian-selftest.sh` each made
    # after their negative guards fired against the prose explaining them.
    code5 = _strip_noncode(text)
    for m in VIEW_STRUCT.finditer(code5):
        name, start = m.group(1), m.end()
        nxt = re.search(r"^(?:private |public )?(?:struct|extension|final class) ",
                        code5[start:], re.M)
        extent = code5[start:start + (nxt.start() if nxt else len(code5) - start)]
        if not STORED_THING_PROP.search(extent):
            continue
        if "isLive" in extent or ".live" in extent:
            continue
        findings.append(
            f"✗ {rel}:{text[:m.start()].count(chr(10)) + 1} — View '{name}' stores a "
            f"Thing but its body has no isLive guard\n"
            f"      a leaf body re-evaluates on the model's own observation — "
            f"guard it, don't rely on the parent"
        )

    # ── Check 6: a [Thing] held across an AWAIT ──────────────────────
    # Build 250 (2026-08-03), and the first of this class outside the view
    # layer. `TodayBrief.compose` took a `[Thing]`, suspended on three live
    # reads bounded at 8s, then read `.kind`/`.source` off the SAME array —
    # and the app's own foreground heals delete Things in exactly that window.
    # No view-side guard can help: there is no ForEach, no leaf body, no @State.
    # An async function handed a `[Thing]` must re-filter `.live` after it
    # suspends (or on entry, if its caller awaited before handing it over).
    for m in ASYNC_THING_FUNC.finditer(text):
        name, start = m.group(1), m.end()
        nxt = re.search(r"\n    (?:@\w+\s+)?(?:private |static |public |final )*func\s", text[start:])
        body = text[start:start + (nxt.start() if nxt else min(len(text) - start, 20000))]
        if "await" not in body:
            continue
        after = body[body.rindex("await"):]
        # Something read off a model AFTER the last suspension?
        reads = re.search(rf"\.({'|'.join(sorted(STORED))})\b", after)
        if not reads:
            continue
        if ".live" in body or "isLive" in body:
            continue
        findings.append(
            f"✗ {rel}:{text[:m.start()].count(chr(10)) + 1} — async '{name}' holds a "
            f"[Thing] across an await, then reads a stored property\n"
            f"      re-filter `.live` after the suspension — a heal can delete during it"
        )

    # ── Check 7: ONE Thing handed to an async func ──────────────────
    # Build 256 (2026-08-03). `LinkTitle.enrich(_ thing: Thing, …) async` read
    # `thing.kind` on its FIRST line and trapped — "backing data was detached
    # from a context without resolving attribute faults". Check 6 could not see
    # it: the parameter is one Thing, not `[Thing]`.
    #
    # The trap is the CALLER's shape, which all four of enrich's call sites
    # share: `Task { @MainActor in await LinkTitle.enrich(thing, …) }`. A
    # detached task is SCHEDULED, not run — the pass that created it carries on,
    # and §286's reconcile deletes unexplained social rows on every refresh, so
    # the row can be gone before the task's first line executes.
    #
    # So unlike check 6 this does NOT look only after the last `await`: the
    # crashing read was before any suspension at all. The rule is simply that a
    # function handed one Thing asynchronously must establish it is still live
    # before reading it — on entry, and again after each suspension.
    for m in ASYNC_ONE_THING_FUNC.finditer(text):
        name, start = m.group(1), m.end()
        nxt = re.search(r"\n    (?:@\w+\s+)?(?:private |static |public |final )*func\s", text[start:])
        body = text[start:start + (nxt.start() if nxt else min(len(text) - start, 20000))]
        if not re.search(rf"\.({'|'.join(sorted(STORED))})\b", body):
            continue
        if ".live" in body or "isLive" in body:
            continue
        findings.append(
            f"✗ {rel}:{text[:m.start()].count(chr(10)) + 1} — async '{name}' takes one "
            f"Thing and reads a stored property with no liveness guard\n"
            f"      guard `thing.isLive` on entry — a detached Task runs LATER, and the row can already be deleted"
        )

    # ── Check 4: a held [Thing] handed onward without .live ──────────
    # Build 177. `@State private var debouncedAllSnapshot: [Thing]?` — the All
    # room's perf snapshot, raw model refs held across a debounce window, so
    # DELIBERATELY behind the live corpus. Nothing read a stored property off
    # that name directly (check 2's shape), so check 2 saw nothing; the refs
    # FLOWED OUT through `visible` into `HomeComposition.projectClusters`,
    # which read `thing.tags` and trapped. The rule that would have caught it:
    # a held Thing array must be `.live`-filtered where it is READ, not on a
    # promise that every downstream reader guards. (That promise was written
    # in the comment above the property, and it was false.)
    # Deliberately narrow, so it stays believable: only the array HANDED ONWARD
    # WHOLE — `return held`, or `held` passed as a call argument — and only the
    # first such site per name. Direct `held.property` reads stay check 2's job.
    # Comments are stripped and re-bindings (`if let watched = …`) skipped;
    # without those two, this fired 15 times on one screen in its first run.
    code_lines = _strip_noncode(text).splitlines()
    for lineno, line in enumerate(code_lines, 1):
        m = HELD_ARRAY_DECL.search(line)
        if not m:
            continue
        name = m.group(1)
        esc = re.escape(name)
        for n, l in enumerate(code_lines, 1):
            if n == lineno or not re.search(rf"\b{esc}\b", l):
                continue
            if re.search(rf"\b(?:let|var)\s+{esc}\b", l):
                continue                              # a DIFFERENT, shadowing binding
            if re.match(rf"\s*{esc}\s*=", l):
                continue                              # populating the snapshot
            if re.search(r"\.live\b", l) or "isLive" in l:
                continue                              # guarded
            # "Handed onward WHOLE" means the array itself is passed as a
            # value — `return held`, `f(held)`, `label: held`. A member access
            # off it (`held.count`, `held?.count`, `held.isEmpty`, `held[0]`)
            # is NOT the array handed on: `.count`/`.isEmpty` read array
            # metadata, never a `Thing`, and an element read like `held.first`
            # is check 2's job, not this one. The `(?![\w.?\[])` lookahead
            # keeps this from firing on `debouncedAllSnapshot?.count` — a false
            # positive caught 2026-07-29 the first time a held array was read
            # for its length rather than its contents.
            tail = r"(?![\w.?\[])"
            handed_on = (
                re.search(rf"\breturn\s+{esc}{tail}", l)          # return held
                or re.search(rf"[(,:]\s*{esc}{tail}\s*[,)]", l)   # f(held) / label: held
            )
            if not handed_on:
                continue
            if (path.name, l.strip()) in HANDOFF_OK:
                continue
            findings.append(
                f"✗ {rel}:{n} — '{name}' is a held [Thing] (declared line "
                f"{lineno}), handed onward without .live\n"
                f"      {l.strip()[:110]}"
            )
            break                                     # one finding per held array

    # ── Check 2: held Thing refs read without an isLive guard ────────
    if path.name in KNOWN_UNGUARDED:
        return
    for lineno, line in enumerate(text.splitlines(), 1):
        m = HELD_DECL.search(line)
        if not m:
            continue
        name = m.group(1)
        # Is THIS identifier guarded anywhere in the file?
        #
        # Scoped PER IDENTIFIER, not per file. It used to be per file — any
        # `isLive`/`.live` anywhere returned early and skipped the whole file —
        # which quietly decayed into no check at all: 68 files carry a guard
        # today, so 68 files were exempt, and a NEW held `Thing` added beside a
        # guarded one could never be flagged. Check 5 already scopes to the
        # enclosing struct; this is the same tightening one level down.
        #
        # Still deliberately coarse: a guard ANYWHERE in the file clears this
        # identifier, because the reads are matched by line and there is no
        # control-flow analysis here — the real guard is usually the `if let
        # recent, recent.isLive` wrapping the read, which no line-wise match
        # can see. Demanding proximity would fire on
        # `BridgeDetailScreen.recent`, which is correctly guarded, and a lint
        # that cries wolf gets turned off within a week (see this file's head).
        if re.search(rf"\b{re.escape(name)}\b\??\.(?:isLive|live)\b", text):
            continue
        # Does the file read a STORED property off exactly this held name?
        reads = [
            (n, l)
            for n, l in enumerate(text.splitlines(), 1)
            if re.search(rf"\b{re.escape(name)}\b\??\.({'|'.join(sorted(STORED))})\b", l)
        ]
        if not reads:
            continue  # held and passed onward only — the renderer guards.
        n, l = reads[0]
        findings.append(
            f"✗ {rel}:{lineno} — '{name}' is a held Thing, read unguarded at line {n}\n"
            f"      {line.strip()}\n"
            f"      {n}: {l.strip()[:110]}"
        )


def self_test() -> int:
    """Prove the checks can fail — a green audit means nothing otherwise."""
    import tempfile

    cases = {
        "derived": (
            "@Query private var things: [Thing]\n"
            "var recent: [Thing] { things.filter { $0.pinned } }\n"
            "var body: some View { ForEach(recent) { t in Text(t.title) } }\n",
            "derived [Thing] array",
        ),
        "chained": (
            "@Query private var things: [Thing]\n"
            "var body: some View { ForEach(things.filter { $0.pinned }) { t in Text(t.title) } }\n",
            "chained off a @Query array",
        ),
        "held": (
            "@State private var openThing: Thing?\n"
            "var body: some View { Text(openThing?.title ?? \"\") }\n",
            "is a held Thing, read unguarded",
        ),
        # DOCTRINE CHANGE (build 177). This case used to assert "handed to a
        # renderer which guards is fine". That is exactly the promise build 177
        # died on — `debouncedAllSnapshot` was handed onward on the written
        # promise that "every downstream reader already re-filters", and one
        # reader didn't. A promise that lives in another file cannot be checked
        # here, and `.live` at the hand-off costs one filter, so the hand-off
        # is now where the guard belongs.
        "held-passed-on-unfiltered": (
            "@State private var recent: [Thing] = []\n"
            "var body: some View { RecentThingsSection(header: \"x\", things: recent) }\n",
            "handed onward without .live",
        ),
        "clean-held-passed-on-live": (
            "@State private var recent: [Thing] = []\n"
            "var body: some View { RecentThingsSection(header: \"x\", things: recent.live) }\n",
            None,
        ),
        # Build 177's own shape: a held array returned out of a computed
        # property, into helpers that then read stored properties off it.
        "held-returned-unfiltered": (
            "@State private var snapshot: [Thing]?\n"
            "private var visible: [Thing] { return snapshot ?? [] }\n",
            "handed onward without .live",
        ),
        # Reading a held array for its LENGTH is not handing it onward — `.count`
        # touches no `Thing` (false positive fixed 2026-07-29).
        "clean-held-count-read": (
            "@State private var snapshot: [Thing]?\n"
            "private var revision: Int { return snapshot?.count ?? 0 }\n",
            None,
        ),
        # Build 188's shape: the LEAF. Keying and every container guard were in
        # place; the row already in the tree re-ran its own body and trapped.
        "leaf-view-unguarded": (
            "struct BandRow: View {\n"
            "    let thing: Thing\n"
            "    var body: some View { Text(thing.title) }\n"
            "}\n",
            "stores a Thing but its body has no isLive guard",
        ),
        # Build 250's shape: async model code holding a [Thing] across a
        # suspension, then reading it. No view guard can reach this.
        "async-holds-thing-across-await": (
            "static func compose(things: [Thing], context: ModelContext) async -> String? {\n"
            "    let landed = DayBrief.landed(things)\n"
            "    let holdings = await liveHoldings()\n"
            "    return landed.filter { $0.kind == .transaction }.first?.title\n"
            "}\n",
            "holds a [Thing] across an await",
        ),
        "clean-async-refiltered-after-await": (
            "static func compose(things: [Thing], context: ModelContext) async -> String? {\n"
            "    var landed = DayBrief.landed(things)\n"
            "    let holdings = await liveHoldings()\n"
            "    landed = landed.live\n"
            "    return landed.filter { $0.kind == .transaction }.first?.title\n"
            "}\n",
            None,
        ),
        # Build 256's shape: ONE Thing handed to an async func, read on entry.
        # Deliberately has NO await before the read — that is the whole point,
        # and why check 6's after-the-last-await rule could not have caught it.
        "async-one-thing-unguarded": (
            "static func enrich(_ thing: Thing, context: ModelContext) async {\n"
            "    guard thing.kind == .link else { return }\n"
            "    let page = await fetchPage(url)\n"
            "    thing.title = page.title\n"
            "}\n",
            "takes one Thing and reads a stored property",
        ),
        "clean-async-one-thing-guarded": (
            "static func enrich(_ thing: Thing, context: ModelContext) async {\n"
            "    guard thing.isLive else { return }\n"
            "    guard thing.kind == .link else { return }\n"
            "    let page = await fetchPage(url)\n"
            "    guard thing.isLive else { return }\n"
            "    thing.title = page.title\n"
            "}\n",
            None,
        ),
        # An ARRAY parameter must stay check 6's business, not get double-flagged
        # by the new one — `(?<!\[)Thing(?!\])` is what keeps them apart.
        "clean-async-array-is-check-sixs-job": (
            "static func compose(things: [Thing], context: ModelContext) async -> String? {\n"
            "    let landed = things.live\n"
            "    return landed.first?.title\n"
            "}\n",
            None,
        ),
        "clean-leaf-view-guarded": (
            "struct BandRow: View {\n"
            "    let thing: Thing\n"
            "    var body: some View { if thing.isLive { liveBody } }\n"
            "    @ViewBuilder private var liveBody: some View { Text(thing.title) }\n"
            "}\n",
            None,
        ),
        # A guard NAMED IN A COMMENT is not a guard. This is `MediaRow`'s own
        # shape, verbatim in miniature: every podcast row rendered through it,
        # it held a `Thing`, its body read stored properties unguarded, and one
        # doc line mentioning `BandRow.live` cleared the check — so the audit
        # certified it clean for as long as it existed. The mention must sit
        # INSIDE the struct to reproduce: `extent` starts after the declaration,
        # so a doc comment above the struct was never in scope and a fixture
        # written that way passes even against the unfixed check.
        "leaf-view-guard-only-in-a-comment": (
            "struct MediaRow: View {\n"
            "    let thing: Thing\n"
            "    // Unlike `BandRow.live`, this draws a fixed 48pt box.\n"
            "    var body: some View { Text(thing.title) }\n"
            "}\n",
            "has no isLive guard",
        ),
        # The regression the OLD file-scoped exemption allowed: one held Thing
        # correctly guarded, a second one beside it not. Any `isLive` in the
        # file used to clear both, so this shape was unflaggable in every file
        # that had ever been guarded — which, after the corollary-5 sweep, was
        # most of them.
        "held-unguarded-beside-a-guarded-one": (
            "@State private var openThing: Thing?\n"
            "@State private var pending: Thing?\n"
            "var body: some View {\n"
            "  if let openThing, openThing.isLive { Text(openThing.title) }\n"
            "  Text(pending?.title ?? \"\")\n"
            "}\n",
            "is a held Thing, read unguarded",
        ),
        "clean-held-guarded": (
            "@State private var openThing: Thing?\n"
            "var body: some View { Text(openThing?.isLive == true ? openThing!.title : \"\") }\n",
            None,
        ),
        "clean-bare-query": ("@Query private var things: [Thing]\n"
                            "var body: some View { ForEach(things) { t in Text(t.title) } }\n", None),
        # Corollary 3: keyed, so check 1 passes — and it still crashed in the
        # field (build 176), because the CONTENT closure reads the model.
        "keyed-but-body-unguarded": (
            "@Query private var things: [Thing]\n"
            "var recent: [Thing] { things.filter { $0.pinned } }\n"
            "var body: some View { ForEach(recent.keyed) { i in Text(i.thing.title) } }\n",
            "content closure reads .thing with no isLive guard",
        ),
        # Filtering upstream is NOT the guard — that ran before the delete.
        "prefiltered-body-unguarded": (
            "@State private var rows: [KeyedThing] = []\n"
            "var liveRows: [KeyedThing] { rows.filter { $0.thing.isLive } }\n"
            "var body: some View { ForEach(liveRows) { r in Text(r.thing.title) } }\n",
            "content closure reads .thing with no isLive guard",
        ),
        "clean-keyed": (
            "@Query private var things: [Thing]\n"
            "var recent: [Thing] { things.filter { $0.pinned } }\n"
            "var body: some View { ForEach(recent.keyed) { i in\n"
            "    if let t = i.live { Text(t.title) } } }\n",
            None,
        ),
        # A URL's `//` inside a literal, and a quote inside a comment, must not
        # derail the closure scanner (both are everywhere in this codebase).
        "clean-keyed-with-url-and-quoted-comment": (
            "@Query private var things: [Thing]\n"
            "var recent: [Thing] { things.filter { $0.pinned } }\n"
            "var body: some View { ForEach(recent.keyed) { i in\n"
            "    // the row's \"own\" title { not a brace }\n"
            "    if let t = i.live { Text(t.title + \"https://api.example.com/{x}\") } } }\n",
            None,
        ),
    }
    global STORED
    STORED = thing_stored_properties()
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (src, expect) in cases.items():
            p = pathlib.Path(tmp) / f"{name}.swift"
            p.write_text(src)
            found: list[str] = []
            # audit_file reports paths relative to ROOT; give it a real root.
            global ROOT
            saved, ROOT = ROOT, pathlib.Path(tmp)
            audit_file(p, found)
            ROOT = saved
            hit = "\n".join(found)
            if expect is None:
                if found:
                    print(f"  self-test FAIL: {name} should be clean, got:\n{hit}")
                    ok = False
                else:
                    print(f"  self-test ok: {name} — clean, as expected")
            elif expect in hit:
                print(f"  self-test ok: {name} — caught ({expect})")
            else:
                print(f"  self-test FAIL: {name} — expected {expect!r}, got: {hit or '(nothing)'}")
                ok = False
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        print("swiftdata-liveness-audit: self-test")
        return self_test()

    global STORED
    STORED = thing_stored_properties()
    findings: list[str] = []
    for source in SOURCES:
        for path in sorted((ROOT / source).rglob("*.swift")):
            audit_file(path, findings)

    if findings:
        print("swiftdata-liveness-audit: FAILED")
        for f in findings:
            print(f"  {f}")
        print()
        print("  Derived ForEach → iterate 'things.keyed', read $0.thing in the body.")
        print("  Held @State ref → guard stored-property reads with 'thing.isLive'.")
        print("  Both live in Casberi/Casberi/Screens/ThingRowKeying.swift.")
        return 1

    print("swiftdata-liveness-audit: OK — every derived ForEach is keyed "
          "and every held Thing is guarded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
