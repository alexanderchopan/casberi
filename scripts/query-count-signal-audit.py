#!/usr/bin/env python3
"""A BOUNDED `@Query`'s `.count` is not a change signal.

WHY THIS EXISTS, and why it is a script rather than a sentence in CLAUDE.md.

SwiftData's `@Query` fetches in its GETTER — the 6,000-row main-thread profile
(`scripts/output/profile-ios-cold-6k.txt`) puts the CoreData fetch under
`FeedScreen.things.getter`, not under any update hook. So reading `.count` is
not a free read of an array already in hand; it materialises the whole fetch,
on the main actor, once per body evaluation. That alone is a perf bug.

The reason it is worth a build-time check is the SECOND failure, which is a
correctness one and is invisible:

    a `@Query` whose descriptor sets `fetchLimit = N` reports `.count == N`
    for every corpus larger than N, forever.

So `.task(id: things.count)` never restarts and `.onChange(of: things.count)`
never fires — on exactly the corpora big enough to need them. Nothing throws,
nothing logs, and the screen looks right until you notice it stopped updating.

This shipped twice, in the same week, from the same well-meant change:

  • `FeedScreen`, bound at 1,200 on 2026-08-06. The All room's debounced
    snapshot was populated once and never refreshed again for the life of the
    mount. Masked by `MainSurface` carrying `.id(filter.source)` — leaving the
    room and coming back builds a new screen, which paints correctly — so it
    read as "the feed only updates when I switch chips".
  • `MainSurface`, bound at 400 the same day. NEITHER arrival watcher fired:
    no arrival bob, no berry rain, no `refreshLiveChips()` when a source
    appeared, no `detail.pruneIfDead()`. It read as "delight is a bit random".

Both were found five days later by reading, not by any check here: the build is
happy, every audit is static, and a demo corpus is far below either bound, so
no sweep and no probe on any simulator can reach the broken state. That is the
exact profile of a rule this repo has learned not to leave to memory.

THE FIX the finding points at: key on `Corpus.count(in: modelContext)`
(`Casberi/Shared/Thing.swift`) — a SQL `COUNT` over the whole store, so no
ceiling and no model instantiation.

WHAT IT DELIBERATELY DOES NOT DO (a lint that cries wolf gets turned off within
a week):

  • It says nothing about an UNBOUNDED query's `.count`. That is only a cost
    question, it has no silent-wrong-answer, and plenty of small per-source
    rooms read it perfectly reasonably.
  • It only looks at the three positions where a value is used AS A KEY —
    `onChange(of:)`, `.task(id:)`, `.id()`. A bounded `.count` rendered as
    text is a different question (is the number honest?) that `FeedScreen`'s
    own `reachedFetchCeiling` copy already answers.
  • It matches per LINE. These are written on one line in practice, and a
    multi-line key expression is rare enough that the miss is cheaper than the
    parser it would take to catch it.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ["Casberi/Casberi", "Casberi/Shared"]

# A file is "bounded" if it declares a @Query AND sets a fetchLimit anywhere.
# Coarse on purpose: the descriptor is built in `init` in one case and in a
# static computed property in the other, and chasing which descriptor feeds
# which query means parsing Swift.
QUERY_DECL = re.compile(r"@Query\b[^\n]*?\bvar\s+([A-Za-z_]\w*)")
FETCH_LIMIT = re.compile(r"\bfetchLimit\s*=")
# The three key positions.
KEY_POSITION = re.compile(r"\.onChange\s*\(\s*of\s*:|\.task\s*\(\s*id\s*:|\.id\s*\(")

# A conscious "this query's count really is the right key here." Each entry is
# a ruling, not a snooze — spell out why the bound cannot be reached.
KNOWN_EXEMPT: dict[str, str] = {}


def strip_comments(text: str) -> str:
    """Comments describe this rule by quoting the very expression it bans."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def audit_text(text: str, name: str) -> list[str]:
    code = strip_comments(text)
    if not FETCH_LIMIT.search(code):
        return []
    queries = set(QUERY_DECL.findall(code))
    if not queries:
        return []
    out = []
    for i, line in enumerate(code.splitlines(), 1):
        if not KEY_POSITION.search(line):
            continue
        for q in queries:
            if re.search(rf"\b{re.escape(q)}\s*\.count\b", line):
                out.append(f"{name}:{i} keys on `{q}.count`, and `{q}` is a "
                           f"bounded @Query — past the bound that value can "
                           f"never change. Use `Corpus.count(in: modelContext)`.")
    return out


DIRTY_TASK = """
struct A: View {
    @Query private var things: [Thing]
    init() { var d = FetchDescriptor<Thing>(); d.fetchLimit = 1200; _things = Query(d) }
    var body: some View { List {}.task(id: things.count) { } }
}
"""
DIRTY_ONCHANGE = """
struct B: View {
    @Query(B.corpus) private var things: [Thing]
    static var corpus: FetchDescriptor<Thing> { var d = FetchDescriptor<Thing>(); d.fetchLimit = 400; return d }
    var body: some View { List {}.onChange(of: things.count) { _, _ in } }
}
"""
CLEAN_UNBOUNDED = """
struct C: View {
    @Query private var things: [Thing]
    var body: some View { List {}.task(id: things.count) { } }
}
"""
CLEAN_FIXED = """
struct D: View {
    @Query private var things: [Thing]
    init() { var d = FetchDescriptor<Thing>(); d.fetchLimit = 1200; _things = Query(d) }
    private var corpusRevision: Int { Corpus.count(in: modelContext) }
    var body: some View { List {}.task(id: corpusRevision) { } }
}
"""
CLEAN_DISPLAY = """
struct E: View {
    @Query private var things: [Thing]
    init() { var d = FetchDescriptor<Thing>(); d.fetchLimit = 1200; _things = Query(d) }
    var body: some View { Text("\\(things.count) things") }
}
"""
CLEAN_COMMENT = """
struct F: View {
    @Query private var things: [Thing]
    init() { var d = FetchDescriptor<Thing>(); d.fetchLimit = 1200; _things = Query(d) }
    // Never `.task(id: things.count)` here — see corpusRevision.
    var body: some View { List {}.task(id: corpusRevision) { } }
}
"""


def self_test() -> int:
    cases = [
        ("a bounded query keyed by .task(id:)", DIRTY_TASK, True),
        ("a bounded query keyed by .onChange(of:)", DIRTY_ONCHANGE, True),
        ("an UNBOUNDED query's count is not this rule", CLEAN_UNBOUNDED, False),
        ("the fixed form, keyed on a real count", CLEAN_FIXED, False),
        ("a bounded count RENDERED is a different question", CLEAN_DISPLAY, False),
        ("a comment naming the banned expression doesn't fire", CLEAN_COMMENT, False),
    ]
    ok = True
    for name, text, should_flag in cases:
        hits = audit_text(text, "fixture.swift")
        if bool(hits) == should_flag:
            print(f"  ✓ {name}")
        else:
            print(f"  ✗ {name} — expected {'a finding' if should_flag else 'clean'}, "
                  f"got {hits or '(nothing)'}")
            ok = False
    return 0 if ok else 1


def main() -> int:
    if "--self-test" in sys.argv:
        print("query-count-signal audit: self-test")
        return self_test()
    if self_test() != 0:
        print("query-count-signal audit: SELF-TEST FAILED — not certifying the tree")
        return 1

    findings: list[str] = []
    scanned = 0
    for source in SOURCES:
        for path in sorted((ROOT / source).rglob("*.swift")):
            rel = str(path.relative_to(ROOT))
            if rel in KNOWN_EXEMPT:
                continue
            scanned += 1
            findings += audit_text(path.read_text(encoding="utf-8"), rel)

    if findings:
        print("query-count-signal audit: FAILED")
        for f in findings:
            print(f"  {f}")
        return 1
    print(f"✓ query-count-signal audit: {scanned} files, no bounded @Query "
          f"is used as a change signal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
