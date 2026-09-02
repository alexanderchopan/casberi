#!/usr/bin/env python3
"""fetch-bound-audit — an unbounded whole-corpus fetch, made mechanical (PERF 2026-09-01).

`(try? context.fetch(FetchDescriptor<Thing>()))` materialises EVERY row of the
store as a real model object. On the main actor that is the single most
expensive thing this app can do, and it scales with the corpus — which is why
it arrived with the bulk-import rooms and reads to a person as "the app got
slow after I imported my archive", never as a fetch.

**It has re-entered the codebase four times by four different routes** — the
kept-ask digests, `Composer`'s settle block, the two `@Query`-staleness safety
nets, and a room writing its own state — each found by profiling, each fixed one
site at a time, each fix a `fetchLimit` somebody had to think of. That is the
shape this repo makes mechanical rather than remembers: the failure is invisible
(the screen is CORRECT, it merely costs), no build sees it, the screen sweep
photographs a perfect room, and `perf.sh` measures launch, RSS and answer
latency — three numbers that have read clean through every one of the four.

CHECK 1 — THE WHOLE-CORPUS READ.
  A `FetchDescriptor<Thing>` constructed with NO `predicate:` argument reads the
  entire store by construction. In ship code it must either be BOUNDED — a
  `fetchLimit` assigned to it unconditionally — or carry an entry in
  KNOWN_UNBOUNDED saying why it must read everything. The reason is the whole
  point of the registry: an entry is a conscious "this one is the exception, and
  here is its mechanism", never a snooze. Every entry below defends itself.

CHECK 2 — A `@Query`-BACKED DESCRIPTOR, PREDICATE OR NOT.
  A `@Query` is re-evaluated on every store change while its view is mounted, so
  it is the render path by definition and a `source ==` predicate is no bound at
  all on a room a bulk import filled with thousands of rows. A descriptor handed
  to `Query(…)` must therefore be bounded or registered even when predicated.
  "Bounded" here means UNCONDITIONALLY bounded — a `fetchLimit` set at the same
  brace depth as the construction. `if let rowBudget { d.fetchLimit = rowBudget }`
  is a transient bound taken during a swipe and gone the moment the swipe ends,
  so it is not a bound at all in the state the room actually rests in, and the
  source room is registered rather than quietly counted as fixed.

CHECK 3 — `fullCorpus()` KEEPS ITS INSTRUMENTATION.
  `RootShell.fullCorpus()` is the deliberate whole-corpus door and the largest
  unbounded read left standing. It is allowed to exist because it is MEASURED:
  its `askPerf| fullCorpus=%dms rows=%d` line is the only before/after number
  anyone has for it, and "is the ask slow because of this fetch or because of
  the live network reads?" needs opposite fixes depending on the answer. Losing
  the log line loses the ability to ask. Grep-anchored, so a rename fails loudly
  rather than passing vacuously.

WHAT IT DELIBERATELY DOES NOT FLAG, so it cannot become a lint that cries wolf:

  * A PREDICATED descriptor that is not `@Query`-backed. MEASURED on this tree:
    163 unbounded constructions in ship code, of which 133 are predicated —
    almost all a bridge's own `existingSourceRefs`-shaped dedupe read, off the
    render path by construction and reading one source rather than the store.
    Flagging them means a 133-entry exemption list, which is `ref-shape-audit`'s
    refused reverse direction wearing a registry's clothes: a check that fires a
    hundred times on a healthy tree gets turned off within a week. The class
    this audit is named for is the WHOLE-corpus read, and that is what it holds.
  * `fetchCount(FetchDescriptor<Thing>())`. SQLite answers a COUNT without
    materialising a row — it is the CHEAP half of the pattern and the fix the
    expensive sites are supposed to reach for first.
  * Anything inside `#if DEBUG`, and all of `Shell/ProbeHooks.swift`. Probes
    exist to walk the whole store and say what is in it; bounding them would
    make them lie about the corpus they are reporting on.
  * `FeedScreen`'s pinned room, which is `Query(filter:sort:order:)` and
    constructs no descriptor at all, so there is nothing here to see. It is
    unbounded on purpose — the list is as long as you made it by hand, so there
    is no corpus-scale growth to bound and a ceiling could hide a row you pinned.
    Recorded here rather than as a registry entry, because an entry that can
    never fire is a check satisfied for the wrong reason (`catalog-sync.sh`'s
    vacuous-pass lesson).
  * `FeedScreen`'s per-source safety-net recovery fetch, which is predicated on
    `source`. Its own comment states the ruling — "the fix here is to run it at
    the right TIME, never to truncate it" — and it is guarded on time by
    `body-publish-audit.py` check 2 instead, which is where a timing rule
    belongs. Its two UNPREDICATED siblings are bounded and stay that way,
    because a bound there is a correction rather than a trade: `things` is
    capped, so an unbounded recovery re-derived the room from a larger set than
    the room is defined to hold.
  * Whether a bound is the RIGHT SIZE. That is a ruling, not an audit; this
    proves a bound exists and was thought about.

Static text check, no build needed. Runs in verify.sh.
`--self-test` runs FIRST and proves each check can fail.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Ship code. The widget extension is here for the reason the liveness audit put
# it here: it opens its own `ModelContext` over the same store, in a ~30MB
# budget, so a whole-corpus fetch there is worse than one in the app.
SOURCES = ["Casberi/Casberi/Screens", "Casberi/Casberi/Shell",
           "Casberi/Casberi/Model", "Casberi/CasberiWidgets"]

# Entirely debug probe code — every hook in it reads the store to report on it.
SKIP_FILES = {"ProbeHooks.swift"}

# The whole-corpus reads that are legitimate, keyed `file:enclosing symbol` so
# an entry survives the line drift of the files around it and dies when the
# function it defends is renamed or removed.
#
# An entry names the MECHANISM that makes reading everything correct here — the
# thing that would have to change for the exemption to stop being true. "It is
# slow but fine" is not one of those, and no entry below says it.
KNOWN_UNBOUNDED: dict[tuple[str, str], str] = {

    # --- The deliberate whole-corpus door ------------------------------------
    ("Shell/RootShell.swift", "fullCorpus"):
        "THE unscoped read of the answer path, and the one this audit exists "
        "around rather than against. Every scoping this app has (`keptCorpus`, "
        "`categoryCorpus`, `scopedCorpus`) falls back to it by design, so a "
        "fetchLimit here would silently narrow every ask that failed to scope. "
        "Check 3 holds its instrumentation instead, which is the honest trade: "
        "measured, not hidden.",

    # --- Off the render path: background, App Intents, Shortcuts -------------
    ("Model/WalletBackgroundRefresh.swift", "sweepCorpus"):
        "The FAILURE path of a `BGAppRefreshTask` sweep — reached only when the "
        "two bounded reads above it both threw, and a background sweep that "
        "returns nothing has nothing to notify about. No view is mounted.",
    ("Model/CasberiIntents.swift", "perform"):
        "An App Intent in its own process over `SharedStore.extensionContainer()`, "
        "answering `WeekSynthesisIntent` from the whole corpus because that is "
        "what 'my week' means. No view, no main actor of ours.",
    ("Model/CasberiIntents.swift", "corpus"):
        "`IntentCorpus.corpus()` — the shared one-fetch-many-queries door for "
        "Visual Intelligence, which matches a frame's labels several at a time. "
        "Fetching once is the OPTIMISATION here; the alternative is a fresh "
        "container per label.",
    ("Model/ThingEntity.swift", "entities"):
        "`ThingEntityQuery` resolving ids for Shortcuts/Siri in the extension "
        "container. It filters by an id SET, which a `#Predicate` cannot express "
        "against a captured collection of UUIDs, and the caller hands it "
        "whatever ids the system remembered.",
    ("Model/SpotlightIndex.swift", "reindexAll"):
        "Watermarked. The steady state applies `capturedAt > watermark` and "
        "reads almost nothing; the unpredicated form is reached ONLY after "
        "`removeAll()` cleared the watermark (Delete everything), where "
        "re-indexing the whole corpus is literally the job.",
    ("Model/SyncReconcile.swift", "dedupeBySourceRef"):
        "Dedupe cannot be bounded and stay dedupe — a limit means the pair that "
        "sits past it survives forever. Bounded the only way that IS available: "
        "`propertiesToFetch` narrows it to id/sourceRef/createdAt, so it walks "
        "rows without materialising any text.",
    ("Model/IngestSupport.swift", "removeWallet"):
        "Unwatching a wallet must reach EVERY row that named it, or the feed "
        "keeps most of an unwatched wallet's history. `walletAddress` is "
        "compared through `sameAddress`, a Swift function no `#Predicate` can "
        "call, so there is no narrower fetch to make.",

    # --- Settings, connect and disconnect flows ------------------------------
    ("Screens/AccountDetailSheet.swift", "buildExport"):
        "'Everything as one JSON file' — the export is the whole corpus by "
        "definition, and one that quietly stopped at a limit would be a backup "
        "that loses data while reporting success.",
    ("Screens/AccountDetailSheet.swift", "importThings"):
        "The already-here id set an import tests every incoming row against. A "
        "bound here re-lands rows the store already holds.",
    ("Screens/AccountDetailSheet.swift", "deleteEverything"):
        "'Delete everything' has to see everything. A limit leaves rows behind "
        "under a verb that promises none — the §83 failure at its most "
        "expensive.",
    ("Screens/BridgeDetailScreen.swift", "purgeThings"):
        "Disconnect-and-remove, filtered to one source in Swift. Same shape as "
        "the two below it: a one-tap teardown on a pushed settings screen, not "
        "a render path — and a bounded purge leaves rows for a bridge the "
        "catalog now says is gone.",
    ("Screens/BridgeDisconnectSection.swift", "disconnect"):
        "The shared disconnect row's purge. Reaches every row of the named "
        "source for `purgeThings`' reason; runs once, on a tap, on a screen "
        "that is about to dismiss.",
    ("Screens/WalletConnectionScreen.swift", "disconnectWallet"):
        "The wallet's own purge, same tap-once teardown shape.",
    ("Screens/DiagnosticsScreen.swift", "run"):
        "Diagnostics reports on the corpus, so it must read the corpus — a "
        "bounded count is the wrong answer to 'Things: N', and this screen's "
        "whole job (§315 round 3) is telling a predicate's answer apart from a "
        "plain Swift filter's over the SAME store.",
    ("Screens/ProjectDetailScreen.swift", "corpus"):
        "A project is defined by a TAG, and a `#Predicate` over the "
        "transformable `tags` array COMPILES CLEAN AND TRAPS AT RUNTIME (see "
        "CLAUDE.md) — so there is no predicated form to write. A fetchLimit "
        "would drop the older half of a long-running project, which is the half "
        "this screen exists to show. Light-columned instead.",

    # --- The demo's own lifecycle -------------------------------------------
    ("Model/DemoMode.swift", "pourIfNeeded"):
        "The landed-ref set the chunked pour tests against, so a resumed pour "
        "does not re-land what the first pass already wrote. A bound turns the "
        "two-caller race this file already paid for into duplicate rows.",
    ("Model/DemoMode.swift", "restampIfStale"):
        "The freshness re-stamp shifts EVERY demo-owned row by the same number "
        "of whole days; restamping a slice would leave the corpus split across "
        "two eras, which is the one thing the re-stamp exists to prevent.",
    ("Model/DemoSeedAll.swift", "sweepEscapedRows"):
        "A sweep for demo rows that escaped teardown has to look everywhere a "
        "row could have escaped to.",
    ("Model/DemoSeedAll.swift", "seed"):
        "The landed-ref set the seed dedupes against — `Thing.sourceRef` "
        "carries no unique constraint, so this set IS the constraint (check C "
        "of `demo-selftest.py` exists because a partial one landed four "
        "duplicate pairs once).",
    ("Model/DemoSeedAll.swift", "clear"):
        "Teardown, and it removes BY NAME rather than wholesale — which means "
        "it has to see every row to decide which ones are the demo's.",
    ("Model/DemoCorpus.swift", "clear"):
        "Same teardown rule one file over: every row is inspected, only the "
        "demo's are deleted.",

    # --- Composed once, for a corpus already known to be small ---------------
    ("Model/CatalogTaste.swift", "reasons"):
        "Counts kinds across the corpus to pick the catalog's reasons — a "
        "distribution is not a distribution over a slice. Reached from the "
        "catalog's appear, once, and it declines below a five-row floor.",
    ("Model/AgentOpenCache.swift", "scanPaged"):
        "PAGING THE FETCH IS REFUSED, DELIBERATELY: `capturedAt` carries no "
        "index, so nine paged fetches are nine full sorts of the same table and "
        "cost more than the one they replace. The WALK is what is chunked — "
        "1,500 rows then a yield — so the main actor is released repeatedly "
        "even though the read is whole.",
    ("Model/WalletFlowSource.swift", "probeLines"):
        "`-walletFlowProbe`'s own reporting line. A probe that bounded its read "
        "would report on a slice while naming the corpus.",

    # --- The render path, stated rather than excused -------------------------
    ("Shell/Composer.swift", "scheduleLiveRead"):
        "GUARDED BY A COUNT, which is the pattern the rest of this file should "
        "copy: the `fetchCount` two lines above bails past `liveReadCeiling`, "
        "so an oversized corpus costs one cheap SQL COUNT and never reaches "
        "this fetch. The bound is on the store's size, not on the rows.",
    ("Shell/Composer.swift", "runFind"):
        "Find is the composer's DETERMINISTIC door (§215) and its badge says "
        "'Matched on this iPhone' — a retrieval over a truncated corpus would "
        "make that sentence false, silently, on the one surface whose promise "
        "is that nothing was left out. Fires on a tap, never during a body.",
    ("Shell/Composer.swift", "commit"):
        "The settle block, and it is deliberately AFTER the answer is painted "
        "and after a `Task.yield()` — what it feeds is the Keep pill and the "
        "follow-up chip, which arrive a beat later by design. Kept unbounded "
        "because `recognizeKeptAskKind` decides whether a question is standing, "
        "which a recent slice cannot answer.",
    ("Shell/RootShell.swift", "shell"):
        "Migration v1's one-time voice-audio move (2026-07-07), in the launch "
        "migration block: it runs once per install, ever, and must reach every "
        "voice note or the ones it misses lose their audio permanently. `kind` "
        "is transformable-backed, so the filter is in Swift and there is no "
        "predicated form. Guarded by the stored migration number and, since "
        "2026-09-01, chunked at 500 with a yield — `scanPaged`'s answer: slice "
        "the WALK, not the fetch.",
    ("Shell/RootShell.swift", "route"):
        "`casberi://thing/latest` — a deep link, taken once when a link is "
        "opened and never during a body pass. It is nonetheless the one entry "
        "here that a `fetchLimit = 1` would simply delete rather than excuse; "
        "it should go the next time that file is opened for other reasons.",

    # --- Check 2: @Query-backed, predicated, and unbounded on purpose --------
    ("Screens/WalletHistoryScreen.swift", "descriptor"):
        "This IS the 'everything' page, and the door that opens it wears a "
        "count taken from the feed's own unlimited query — a fetchLimit would "
        "let 'See all · 700' open a page showing 500 with nothing saying so. "
        "The five-row preview is what keeps the common case cheap.",
    ("Screens/FeedScreen.swift", "init"):
        "A SOURCE room. A PERMANENT bound is refused by ruling: the room's head "
        "is composed over its rows, so a head over a truncated slice states a "
        "reading about a room it did not see — §83 fake status, in the largest "
        "type on the screen. The transient `rowBudget` bound is the swipe's and "
        "only the swipe's, and the head declines while it is set.",
}


CONSTRUCT = re.compile(r"FetchDescriptor<Thing>\s*\(")

# A declaration that can enclose a fetch. `func`/`init` plus the file-scope and
# static `FetchDescriptor` constants the `@Query` screens use.
DECL = re.compile(
    r"^[ \t]*(?:(?:private|fileprivate|public|internal|open|static|final|class|"
    r"nonisolated|override|weak|lazy|@MainActor|@discardableResult)\s+)*"
    r"(?:func\s+(\w+)|(init)\s*\(|"
    # A computed property (`var body: some View {`) or a stored descriptor
    # (`static var descriptor: FetchDescriptor<Thing> {`). Both need the colon,
    # which is what keeps a local `var d = FetchDescriptor…` out.
    r"(?:var|let)\s+(\w+)\s*:\s*(?:FetchDescriptor|[^=\n]*\{[ \t]*$))")

FULL_CORPUS = re.compile(r"func\s+fullCorpus\s*\([^)]*\)[^\n{]*\{")


def strip_comments(text: str, blank_strings: bool = True) -> str:
    """Comments out, string literals blanked.

    Not fussiness — this repo has been bitten by it five times over. Several of
    the files scanned here DOCUMENT this exact rule by naming `fetchLimit` and
    `FetchDescriptor<Thing>()` in the prose explaining why a bound was added or
    refused (`FeedScreen`'s BOUNDED notes, `WalletHistoryScreen`'s 'a fetchLimit
    here would…', `ProjectDetailScreen`'s 'Still UNBOUNDED'). A check reading
    raw source scores the explanation as the thing it explains.

    `blank_strings` is off for check 3 alone, which has to see the text INSIDE
    an `NSLog` format string. Comments still go — and they have to, because
    `RootShell` documents that very log line in a comment two lines above it
    (measured: the first cut of check 3 searched raw source, so deleting the
    `NSLog` left the guard green on the prose describing it — the sixth time
    this repo has paid for that exact shape).
    """
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j == -1 else j + 2
            # Newlines KEPT. Every line this audit reports is a line somebody
            # has to open, and a block comment that swallowed its own newlines
            # shifted every finding below it in the file — measured 28 lines
            # off in `RootShell` on this check's first real run.
            out.append("\n" * text.count("\n", i, j))
            i = j
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            lit = text[i:min(j + 1, n)]
            out.append('""' + "\n" * lit.count("\n") if blank_strings else lit)
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def debug_spans(text: str) -> list[tuple[int, int]]:
    """Byte ranges inside `#if DEBUG`, nesting-aware.

    Nesting-aware because a `#if DEBUG` inside a `#if targetEnvironment(...)`
    is ordinary in this tree, and a depth-blind scan closes the wrong one — at
    which point the audit either exempts ship code or flags debug code, and
    both read as the check being broken.
    """
    spans: list[tuple[int, int]] = []
    stack: list[list] = []
    for m in re.finditer(r"^[ \t]*#(if|elseif|else|endif)\b([^\n]*)", text, re.M):
        kind, cond = m.group(1), m.group(2)
        if kind == "if":
            is_dbg = "DEBUG" in cond and "!DEBUG" not in cond.replace(" ", "")
            stack.append([is_dbg, m.end()])
        elif kind in ("else", "elseif"):
            if stack:
                if stack[-1][0]:
                    spans.append((stack[-1][1], m.start()))
                # `#else` of a DEBUG block is the RELEASE half — ship code.
                stack[-1] = [False, m.end()]
        elif kind == "endif":
            if stack:
                is_dbg, start = stack.pop()
                if is_dbg:
                    spans.append((start, m.start()))
    return spans


def close_paren(text: str, i: int) -> int:
    depth = 0
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


def symbol_map(text: str) -> list[tuple[int, int, str]]:
    """(start, end, name) for every declaration body, innermost last.

    Brace-depth tracked rather than "the nearest declaration above", which was
    the first cut and named a fetch inside `body`'s `.task` after whichever
    private func happened to be declared last — a stable key, but a lying one,
    and a registry entry is only as good as the name on it.
    """
    decls: list[tuple[int, int, str]] = []
    stack: list[tuple[str | None, int]] = []
    depth = 0
    pending: str | None = None
    pos = 0
    for line in text.splitlines(keepends=True):
        m = DECL.match(line)
        if m:
            pending = m.group(1) or m.group(2) or m.group(3)
        for k, ch in enumerate(line):
            if ch == "{":
                depth += 1
                stack.append((pending, pos + k))
                pending = None
            elif ch == "}":
                if stack:
                    name, start = stack.pop()
                    if name:
                        decls.append((start, pos + k, name))
                depth = max(0, depth - 1)
        pos += len(line)
    for name, start in stack:
        if name:
            decls.append((start, len(text), name))
    decls.sort(key=lambda d: (d[0], -d[1]))
    return decls


def enclosing(decls, pos: int) -> str:
    name = "<file scope>"
    for start, end, n in decls:
        if start <= pos < end:
            name = n
    return name


def brace_depth(text: str, pos: int) -> int:
    return text.count("{", 0, pos) - text.count("}", 0, pos)


def findings(text: str) -> list[tuple[int, str, str]]:
    """(line, enclosing symbol, why) for every unbounded site worth flagging."""
    clean = strip_comments(text)
    spans = debug_spans(clean)
    decls = symbol_map(clean)
    # Names handed to a `Query(…)` anywhere in the file — a descriptor reaching
    # one is on the render path whatever its predicate says.
    queried = set(re.findall(r"\bQuery\(\s*(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)\s*[,)]", clean))

    out: list[tuple[int, str, str]] = []
    for m in CONSTRUCT.finditer(clean):
        if any(a <= m.start() < b for a, b in spans):
            continue
        end = close_paren(clean, m.end() - 1)
        args = clean[m.end():end]
        line_start = clean.rfind("\n", 0, m.start()) + 1
        stmt = clean[line_start:m.start()]

        # A COUNT materialises nothing — it is the cheap half of the pattern.
        if "fetchCount(" in stmt:
            continue

        held = re.search(
            r"\b(?:var|let)\s+([A-Za-z_]\w*)\s*(?::\s*FetchDescriptor<Thing>\s*)?=\s*$", stmt)
        name = held.group(1) if held else None
        bounded_here = False
        if name:
            want = brace_depth(clean, m.start())
            for a in re.finditer(r"\b" + re.escape(name) + r"\.fetchLimit\s*=", clean[end:]):
                # Unconditional only: a `fetchLimit` set one brace deeper is a
                # bound taken on some paths and not others, which is not a bound
                # in the state the descriptor rests in.
                if brace_depth(clean, end + a.start()) == want:
                    bounded_here = True
                    break
        if bounded_here:
            continue

        sym = enclosing(decls, m.start())
        predicated = "predicate" in args
        query_backed = (name in queried) or (sym in queried)
        if not predicated:
            why = "unpredicated — reads the whole store"
        elif query_backed:
            why = "backs a @Query, so it re-fetches on every store change"
        else:
            continue
        out.append((clean.count("\n", 0, m.start()) + 1, sym, why))
    return out


def full_corpus_unmeasured(text: str) -> bool:
    """True when `fullCorpus()` no longer says how long it took.

    The log line must be inside the function's OWN body — anchored there rather
    than anywhere in the file, since the comment above it quotes the string
    verbatim and a file-wide grep therefore passes on the prose.
    """
    clean = strip_comments(text, blank_strings=False)
    m = FULL_CORPUS.search(clean)
    if not m:
        return True
    i, depth = m.end() - 1, 0
    while i < len(clean):
        if clean[i] == "{":
            depth += 1
        elif clean[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return "askPerf| fullCorpus=" not in clean[m.end():i]


def self_test() -> bool:
    ok = True

    def check(name, got, want):
        nonlocal ok
        if got != want:
            print(f"  SELF-TEST FAIL {name}: got {got!r} want {want!r}")
            ok = False

    naked = ("struct S {\n  func f() {\n"
             "    let all = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n  }\n}\n")
    check("a naked whole-corpus fetch is a finding", findings(naked),
          [(3, "f", "unpredicated — reads the whole store")])

    bounded = ("struct S {\n  func f() {\n"
               "    var d = FetchDescriptor<Thing>(sortBy: [x])\n"
               "    d.fetchLimit = 400\n    _ = try? c.fetch(d)\n  }\n}\n")
    check("an unconditional fetchLimit passes", findings(bounded), [])

    # The transient bound: real, and not a bound in the state the room rests in.
    conditional = ("struct S {\n  init() {\n"
                   "    var d = FetchDescriptor<Thing>(sortBy: [x])\n"
                   "    if let budget { d.fetchLimit = budget }\n"
                   "    _things = Query(d)\n  }\n}\n")
    check("a conditional fetchLimit is still a finding", len(findings(conditional)), 1)

    # A predicate narrows to one source; off the render path that is out of
    # scope by ruling, or the registry grows to 132 entries.
    predicated = ("struct S {\n  func f() {\n"
                  "    let rows = (try? c.fetch(FetchDescriptor<Thing>(\n"
                  "        predicate: #Predicate { $0.source == s }))) ?? []\n  }\n}\n")
    check("a predicated non-Query fetch is not a finding", findings(predicated), [])

    # ...but the same fetch behind a @Query is, because a bulk-import room is
    # thousands of rows and the query re-runs on every store change.
    predicated_query = ("struct S {\n  static var descriptor: FetchDescriptor<Thing> {\n"
                        "    FetchDescriptor<Thing>(predicate: #Predicate { $0.source == s })\n"
                        "  }\n"
                        "  @Query(S.descriptor) private var all: [Thing]\n}\n")
    check("a predicated @Query descriptor IS a finding", len(findings(predicated_query)), 1)

    # A COUNT never materialises a row.
    counted = ("struct S {\n  func f() {\n"
               "    let n = (try? c.fetchCount(FetchDescriptor<Thing>())) ?? 0\n  }\n}\n")
    check("fetchCount is not a finding", findings(counted), [])

    # Prose describing the rule must never score as the rule being broken.
    prose = ("struct S {\n  func f() {\n"
             "    // An unbounded `FetchDescriptor<Thing>()` here would read the store.\n"
             "    /* let all = try? c.fetch(FetchDescriptor<Thing>()) */\n"
             "    _ = 1\n  }\n}\n")
    check("a comment is not a finding", findings(prose), [])

    dbg = ("struct S {\n  func f() {\n    #if DEBUG\n"
           "    let all = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n"
           "    #endif\n  }\n}\n")
    check("a DEBUG-only fetch is not a finding", findings(dbg), [])

    # `#else` of a DEBUG block is the RELEASE half, and is ship code.
    dbg_else = ("struct S {\n  func f() {\n    #if DEBUG\n    _ = 1\n    #else\n"
                "    let all = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n"
                "    #endif\n  }\n}\n")
    check("the #else half of a DEBUG block is ship code", len(findings(dbg_else)), 1)

    nested = ("struct S {\n  func f() {\n    #if targetEnvironment(macCatalyst)\n"
              "    #if DEBUG\n    _ = 1\n    #endif\n"
              "    let all = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n"
              "    #endif\n  }\n}\n")
    check("a nested #if does not close the wrong block", len(findings(nested)), 1)

    # The symbol must name the function the fetch is IN, not whichever
    # declaration happened to be last — a registry key that lies is worse than
    # no key, because the entry survives the code it was written for.
    nestedsym = ("struct S {\n  func outer() {\n    _ = 1\n  }\n"
                 "  var body: some View {\n    Text(\"x\").task {\n"
                 "      let all = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n"
                 "    }\n  }\n}\n")
    check("the symbol is the enclosing declaration",
          [s for _, s, _ in findings(nestedsym)], ["body"])

    # --- check 3 fixtures ---
    measured = ('    private func fullCorpus() -> [Thing] {\n'
                '        let rows = (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n'
                '        NSLog("[Casberi] askPerf| fullCorpus=%dms rows=%d", n, rows.count)\n'
                '        return rows\n    }\n')
    check("an instrumented fullCorpus passes", full_corpus_unmeasured(measured), False)
    check("a silent fullCorpus is a finding",
          full_corpus_unmeasured(measured.replace('NSLog("[Casberi] askPerf| fullCorpus=%dms rows=%d", n, rows.count)', '_ = n')), True)
    check("a renamed fullCorpus fails loudly",
          full_corpus_unmeasured(measured.replace("fullCorpus() ->", "wholeCorpus() ->")), True)
    # THE ONE THAT ALREADY FIRED. `RootShell` names this log line in a comment
    # two lines above it, so the first cut of check 3 — a file-wide grep — went
    # green against a real tree with the `NSLog` deleted.
    prosed = ('    // the `askPerf| fullCorpus=` line below is the only number.\n'
              '    private func fullCorpus() -> [Thing] {\n'
              '        return (try? c.fetch(FetchDescriptor<Thing>())) ?? []\n    }\n')
    check("prose naming the log line does not satisfy it",
          full_corpus_unmeasured(prosed), True)
    # ...and the comment must not stop the real line counting, either.
    check("the same prose above a real log line still passes",
          full_corpus_unmeasured(
              '    // the `askPerf| fullCorpus=` line below is the only number.\n' + measured),
          False)

    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        good = self_test()
        print("fetch-bound audit self-test:", "ok" if good else "FAILED")
        return 0 if good else 1

    if not self_test():
        print("fetch-bound audit: its OWN self-test failed — the check is broken, not the code")
        return 1

    problems: list[str] = []
    used: set[tuple[str, str]] = set()
    saw_full_corpus = False

    for src in SOURCES:
        for path in sorted((ROOT / src).rglob("*.swift")):
            if path.name in SKIP_FILES:
                continue
            text = path.read_text(encoding="utf-8")
            rel = str(path.relative_to(ROOT))
            key_file = rel.split("/", 2)[-1]
            for line, sym, why in findings(text):
                key = (key_file, sym)
                if key in KNOWN_UNBOUNDED:
                    used.add(key)
                    continue
                problems.append(
                    f"{rel}:{line}: `FetchDescriptor<Thing>` in `{sym}` is unbounded "
                    f"({why}). Set `fetchLimit`, or add "
                    f'("{key_file}", "{sym}") to KNOWN_UNBOUNDED with the reason it '
                    f"must read everything.")
            if path.name == "RootShell.swift":
                saw_full_corpus = True
                if full_corpus_unmeasured(text):
                    problems.append(
                        f"{rel}: `fullCorpus()` lost its `askPerf| fullCorpus=` line. "
                        f"It is the largest unbounded read left standing and is allowed "
                        f"to exist because it is MEASURED — without the number there is "
                        f"no way to tell a slow ask's fetch from its live reads.")

    if not saw_full_corpus:
        problems.append("RootShell.swift not found — check 3 measured nothing.")

    stale = sorted(set(KNOWN_UNBOUNDED) - used)
    for key in stale:
        problems.append(
            f"KNOWN_UNBOUNDED entry {key} matches nothing — the fetch it defends was "
            f"bounded, moved or renamed. Remove it; an exemption nothing can reach is "
            f"a check satisfied for the wrong reason.")

    if problems:
        print("fetch-bound audit: FAIL")
        for p in problems:
            print("  " + p)
        return 1
    print(f"fetch-bound audit: ok ({len(KNOWN_UNBOUNDED)} known-unbounded, each with a reason)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
