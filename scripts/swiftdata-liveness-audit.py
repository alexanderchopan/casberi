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

Corollary 2 (build 150) is why check 1 is not only about the ForEach line: a
correctly-keyed ForEach still crashed because the SECTION HEADER beside it did
`Set(rows.map(\\.kind))` over the same raw derived array. The fix there is
`filter(\\.isLive)` once at the top of the view that owns the array — which
check 2's file-level `isLive` requirement also nudges toward.

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
]

# Files that legitimately hold Things in @State with no isLive guard. Adding
# one is a conscious "no stored property of a held Thing is ever read here" —
# e.g. the ref is only passed onward by identity, or re-fetched on every read.
KNOWN_UNGUARDED: set[str] = set()

# `@Query … var name: [Thing]` / `@Query(descriptor) private var name: [Thing]`
QUERY_DECL = re.compile(r"@Query\b[^\n]*?\bvar\s+([A-Za-z_]\w*)")
# Any [Thing]-typed property or local, however declared.
THING_DECL = re.compile(r"\b(?:var|let)\s+([A-Za-z_]\w*)\s*:\s*\[Thing\]")
# A held single/array Thing in @State — captures the NAME so check 2 can look
# for stored-property reads off exactly that identifier.
HELD_DECL = re.compile(r"@State[^\n]*?\bvar\s+([A-Za-z_]\w*)\s*:\s*(?:\[Thing\]|Thing\?)")
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

    # ── Check 2: held Thing refs read without an isLive guard ────────
    if path.name in KNOWN_UNGUARDED or "isLive" in text or ".live" in text:
        return
    for lineno, line in enumerate(text.splitlines(), 1):
        m = HELD_DECL.search(line)
        if not m:
            continue
        name = m.group(1)
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
        "clean-held-passed-on": (
            "@State private var recent: [Thing] = []\n"
            "var body: some View { RecentThingsSection(header: \"x\", things: recent) }\n",
            None,
        ),
        "clean-held-guarded": (
            "@State private var openThing: Thing?\n"
            "var body: some View { Text(openThing?.isLive == true ? openThing!.title : \"\") }\n",
            None,
        ),
        "clean-bare-query": ("@Query private var things: [Thing]\n"
                            "var body: some View { ForEach(things) { t in Text(t.title) } }\n", None),
        "clean-keyed": (
            "@Query private var things: [Thing]\n"
            "var recent: [Thing] { things.filter { $0.pinned } }\n"
            "var body: some View { ForEach(recent.keyed) { i in Text(i.thing.title) } }\n",
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
