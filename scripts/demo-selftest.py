#!/usr/bin/env python3
"""Guard rails for the furnished demo (prd §217 amendment, 2026-08-07).

WHY THIS EXISTS. Every check here re-catches a bug that ALREADY shipped once
during this feature's own development, invisibly to every other check in the
tree:

  1. `ChipMemory.seedDemo` shipped inside `#if DEBUG` while `DemoSeedAll.swift`
     — the file that calls it — carries no `#if` of its own, so
     `xcodebuild -configuration Release` failed outright
     ("type 'ChipMemory' has no member 'seedDemo'"). `verify.sh` compiles
     DEBUG, every other audit is static-over-source, and the break only
     surfaces at `testflight.sh`'s archive step. Check A re-runs that exact
     class over every demo-facing function, not just the one that broke.
  2. Two sessions independently fixed the same "eight seats furnish nothing"
     bug in the same file, one session unaware of the other's work in
     progress. Because `Thing.sourceRef` carries NO unique constraint, the
     fix didn't collide loudly — it would have silently landed FOUR pairs of
     duplicate rows sharing one ref (`demo:sentry:0`, `demo:sentry:1`,
     `demo:pagerduty:4`, `demo:vercel:2`), the exact class this file's own
     `seed()` doc comment warns about ("a leaderboard's subtitle sums the
     rows it counted... five forced runs read 43,875 saved messages"). Check
     C re-checks the specific sources this collision touched.
  3. `TokenChart.route(from:)` performs NO address validation — any
     `dexscreener.com` URL with 2+ path segments parses as a live chart
     request, address included. A fabricated demo URL there is not a dead
     door, it is a REAL network call for garbage data, on the sheet's primary
     content, from a mode whose entire promise is that it reaches nothing.
     Check B is the general form of the fix for that class.

Checks D and E (2026-08-08) generalize incident 2 into a standing rule rather
than a one-time fix: the app's REAL catalog (`BridgeCatalog.offers`) and the
demo's claimed-connected seats (`DemoSeedAll.seatTable`) are two lists a
person edits separately, with nothing forcing them to agree — exactly how
"eight seats furnish nothing" happened, and it happened WITHOUT either list
being individually wrong. Asked directly (user, 2026-08-08: "as we add new
features to the app does the demo get also updated? if so should we make
that a rule?") — the answer this file gives is the same one `catalog-sync.sh`
already gave for the same shape of problem: not a written reminder (this
codebase's CLAUDE.md documents rules like that being forgotten and re-broken
repeatedly), a build-time check.

**What D/E do NOT claim to check, and why that's deliberate rather than lazy:**
a bridge gaining a new CAPABILITY — a new figure kind, a new field a room
head reads — has no textual signature to grep for; whether the demo's
existing rows still exercise it is a judgment call, not a fact a regex can
verify. That case stays a human step (`-demoProbe`/`-roomInsightProbe`
against the demo corpus after a rendering change), documented in CLAUDE.md's
demo entry, not pretended into a mechanical check that would either miss
real gaps or false-positive on unrelated code.

Check F (2026-08-08) generalizes the SAME rule to `FeedScreen.Shape` — the
room-rendering taxonomy, one shape per source, chosen the moment a room is
opened. Asked directly to extend parity checking "to all parts of the app"
(user, 2026-08-08), this is the next surface with the right shape for a
STATIC check: unlike the agent panel (Check for that lives in `verify.sh`'s
simulator tail, because figure selection depends on runtime ranking noise —
see that check's own header), a source's Shape is a pure function of its
NAME, decided at compile time by `Shape.init(source:)`. No ranking, no
simulator, so a real gap can hard-fail here the way D/E do.

Building it found four near-misses before it found the one real thing,
worth recording because each is the kind of false positive a cruder version
of this check would have shipped: `.x402` is matched via
`case X402Ingest.source:`, an INDIRECT reference, not a literal — resolved
by reading the real constant out of `Model/CircleX402Bridge.swift` rather
than hardcoding "Circle x402" as a second copy that could drift.
`.appStoreConnect` is the same indirection one level deeper —
`case ASCShape.source:` resolves to a constant defined INSIDE a nested
`enum ASCShape` in `Model/AppStoreConnectBridge.swift`, so the first cut
of the extraction (which looked for a bare top-level `static let source`)
missed it and reported zero sources, which check F correctly failed on —
caught by its own first real run, not by a fixture. `.media` is matched by
a DYNAMIC PREDICATE (`case _ where MediaShape.isMediaFeed(source)`)
covering five sources at once — resolved the same way, read out of
`Model/MediaShape.swift`'s own switch rather than copied. `.all` maps from
the literal source name `"All"`, which is a PSEUDO-SOURCE (the unfiltered
aggregate view) that no `Thing` ever carries as its real source — exempted,
not fixed, because there is nothing to seed.

The one real finding, while building this check: `.safari` mapped from
`"Safari"`, a bridge that never shipped — `BookmarksImport` had stamped its
rows `source: "Bookmarks"` since 2026-07-28, so every one of them silently
fell to `.plain`'s generic band row instead of the reading-list shape built
for exactly this content. Not a demo gap — the demo seeds real Bookmarks
rows correctly; the bug was upstream, in the switch itself, naming a source
nothing ever stamps. Flagged as a separate task rather than fixed inline
here (out of scope for a demo-parity pass), and fixed same-day by that task:
`case "Safari"` is now `case "Bookmarks"`, `.safari` is gone from the case
list, and this check needs no exemption for it. `KNOWN_UNBACKED_SHAPE`
stays in place, empty, for the next time this class of bug turns up —
the same `KNOWN_EXEMPT` shape this codebase uses everywhere else, ready
rather than invented under pressure.

Static and source-only — no build, no simulator, matches the DEMO(2026-08-07)
addendum to `docs/demo-spec.md`.

Usage:  scripts/demo-selftest.py [--self-test] [--verbose]
Exit 0 = every check passed (or, under --self-test, every fixture behaved).
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASBERI = ROOT / "Casberi/Casberi"

# Every file that carries a demo-facing seed/forget function. All must be
# fully Release-reachable — nothing here may sit inside `#if DEBUG`.
DEMO_FILES = {
    "DemoMode": CASBERI / "Model/DemoMode.swift",
    "DemoSeedAll": CASBERI / "Model/DemoSeedAll.swift",
    "ChipMemory": CASBERI / "Model/ChipMemory.swift",
    "BriefLedger": CASBERI / "Model/BriefLedger.swift",
    "AskMemory": CASBERI / "Model/AskMemory.swift",
    "AppVisit": CASBERI / "Model/AppVisit.swift",
    # Read-only reference for checks D/E — never mutated by this file's own
    # fixtures, since the fixtures exist to break the DEMO side of the sync,
    # not the catalog.
    "BridgeCatalog": CASBERI / "Model/BridgeCatalog.swift",
    # Read-only references for check F — same reasoning, and same read-only
    # role: fixtures for F mutate the DEMO side only.
    "FeedScreen": CASBERI / "Screens/FeedScreen.swift",
    "MediaShape": CASBERI / "Model/MediaShape.swift",
    "CircleX402Bridge": CASBERI / "Model/CircleX402Bridge.swift",
    "AppStoreConnectBridge": CASBERI / "Model/AppStoreConnectBridge.swift",
    # Read-only reference for checks A/H — Safe is the first bridge to own
    # its demo seed in its own file rather than in DemoSeedAll (2026-08-11),
    # since `SafeRoomSource` reads only this file's `private` state.
    "SafeBridge": CASBERI / "Model/SafeBridge.swift",
    # Read-only references for check J — the per-view reads (2026-08-12).
    "KalshiWatch": CASBERI / "Model/KalshiWatch.swift",
    "PolymarketBridge": CASBERI / "Model/PolymarketBridge.swift",
    "ThingContent": CASBERI / "Screens/ThingContent.swift",
    "ZerionAPI": CASBERI / "Model/ZerionAPI.swift",
    "WalletIngest": CASBERI / "Model/WalletIngest.swift",
    # Read-only reference for check K — the eight LEGACY demo seats live in
    # `BridgeApp.demo` here rather than in `DemoSeedAll.seatTable`, which is
    # exactly why check G could only ever test them by name (2026-08-20).
    "BridgeStore": CASBERI / "Model/BridgeStore.swift",
    # Read-only references for check M — the three fixtures that furnish the
    # ROWLESS seats (2026-08-26). A wallet-riding protocol and an exchange
    # land no `Thing` of their own, so check E's literal-row search can never
    # see them and check M reads the fixture instead. Read-only: checks A and
    # B are scoped to `DEMO_FACING_FUNCS` and to DemoMode/DemoSeedAll, so
    # naming `ExchangeBridge` here does not put its (entirely legitimate)
    # network verbs under check B.
    "WalletWarnings": CASBERI / "Model/WalletWarnings.swift",
    "ExchangeBridge": CASBERI / "Model/ExchangeBridge.swift",
    "HegotaBridge": CASBERI / "Model/HegotaBridge.swift",
    "WalletPortfolio": CASBERI / "Model/WalletPortfolio.swift",
}

# Check J — the reads a VIEW makes on its own, which `BridgeRefresh`'s demo
# gate structurally cannot see.
#
# `DemoMode` gates the foreground sweep and `Notifications.submit`, and for
# months that read as "THE DEMO REACHES NOTHING". It wasn't true: a
# `.task(id:)` hanging off a view is not part of any sweep, so opening the
# Kalshi or Polymarket room went straight out to the exchange, and opening a
# thing sheet let `LPMetadataProvider` scrape whoever the row linked to.
#
# Three costs, and only the first is obvious: the demo made live requests on
# behalf of somebody who has not decided to keep the app; the content depended
# on the network, so offline the room drew "couldn't reach the order book" as
# a first impression; and what came back was whatever the exchange was running
# that day, which is how the demo ended up showing markets that had closed
# three months earlier, in warning orange.
#
# Each entry is `(file key, function signature fragment)` — a function that a
# view can reach while the demo is active AND that issues a network verb, so
# it must decide on `DemoMode` before it does. Adding a per-view read means
# adding a row here; that is the point. Comment-stripped, because two of these
# files DOCUMENT the rule by naming the gate in prose (the Obsidian/Cursor
# lesson), so a guard grepping raw source would pass on the explanation alone.
DEMO_GATED_READS = [
    ("KalshiWatch", "static func book("),
    ("KalshiWatch", "static func categories("),
    ("PolymarketBridge", "static func search("),
    ("PolymarketBridge", "static func categories("),
    ("ThingContent", "private func fetch("),
    # The wallet's holdings and its transfer history — read from
    # `WalletWatch.liveState`, a per-view read no sweep gate can see. Added
    # after the RUNTIME check caught `api.zerion.io` on its first run, which
    # is the difference between a hand list and a measurement.
    ("ZerionAPI", "static func holdings("),
    # The FUNNEL both holdings providers pass through. Gating Zerion alone
    # moved the request to the Alchemy fallback — measured, not reasoned.
    ("WalletIngest", "private static func holdings(addresses:"),
    # The BITCOIN branch, which reaches the price host BEFORE that funnel and
    # is therefore invisible to it — found the same way the Zerion entry above
    # was, by the RUNTIME reach walk naming `coins.llama.fi` and nothing else
    # (2026-08-22). A gate on the funnel closes the EVM path and leaves its
    # sibling wide open; this is that sibling.
    ("WalletIngest", "private static func walletGroupOutcome("),
    ("ZerionAPI", "static func transactions("),
]

# `DemoSeedAll.seatTable` names that legitimately have no ENTRY in
# `BridgeCatalog.offers` at all — a conscious ruling per name, the
# `KNOWN_EXEMPT` pattern this codebase uses everywhere else for "we checked,
# this one's real". Adding a name here without checking is how this class of
# audit rots; each entry states what it IS instead.
KNOWN_NO_CATALOG_SEAT = {
    # An always-on device capability (voice notes recorded in-app), not a
    # connectable bridge — there is nothing in the catalog to connect.
    "Voice",
}

# `DemoSeedAll.seatTable` names whose real `Thing.source` differs from
# `BridgeCatalog.offers`' DISPLAY name — the catalog name is marketing
# copy (`AppDetailScreen`'s hero), the source name is what every ingest
# actually stamps on a row, and this codebase already lets them diverge on
# purpose. Verified against the real bridge file before adding, not guessed:
# `Model/PrivacyPoolsBridge.swift` stamps `source: "Privacy Pools"` on every
# row it lands, while the catalog leads with the branded "0xBow Privacy
# Pools" on its product page. The demo is right to match the SOURCE name.
KNOWN_CATALOG_ALIAS = {
    "Privacy Pools": "0xBow Privacy Pools",
}

# Function names that must never be reachable only from inside `#if DEBUG` —
# named explicitly rather than pattern-matched ("any func named seed*"),
# because a false positive here is a build-breaking false alarm on a file a
# fresh session may not think to check twice.
DEMO_FACING_FUNCS = [
    ("ChipMemory", "static func seedDemo"),
    ("ChipMemory", "static func forgetDemo"),
    ("BriefLedger", "static func seedDemo"),
    ("BriefLedger", "static func shiftDemoWindows"),
    ("BriefLedger", "static func demoCheckpoint"),
    ("BriefLedger", "static func restoreDemoCheckpoint"),
    ("AskMemory", "static func seedDemo"),
    ("AskMemory", "static func forgetDemo"),
    ("AppVisit", "static func seedDemo"),
    ("AppVisit", "static func forgetDemo"),
    ("DemoMode", "static func begin"),
    ("DemoMode", "static func exit"),
    ("DemoMode", "static func pourIfNeeded"),
    ("DemoMode", "static func restampIfStale"),
    ("DemoSeedAll", "static func seed"),
    ("DemoSeedAll", "static func teardown"),
    ("DemoSeedAll", "static func seedBridgeStateForDemo"),
    ("SafeBridge", "static func seedDemoSnapshot"),
    ("SafeBridge", "static func clearDemoSnapshot"),
    ("DemoSeedAll", "static func seedAddressBook"),
    ("DemoSeedAll", "static func forgetAddressBook"),
]

# Network verbs that must never appear in the two files the demo's "reaches
# nothing" promise rests on hardest — DemoMode drives the pour/restamp and
# DemoSeedAll builds every row; if either ever grows a real request, the
# promise is broken at its root regardless of what BridgeRefresh/Notifications
# gate.
NETWORK_VERBS = [
    "URLSession", ".dataTask", "IngestSupport.run", "IngestSupport.getJSON",
    "postJSON", "getJSON(", ".data(from:", "URLRequest(",
]

# The sources a later, independent pass (`work`'s `ops` array, `schedule`'s
# Cal.com/Calendly bookings) already covers with safe, non-empty rows — see
# `infra()`'s own doc comment for the incident this prevents. `infra()` must
# never seed any of these again; if it does, either the collision is back or
# the later pass was removed and `infra()` should be widened to cover the gap
# deliberately, not silently.
INFRA_MUST_NOT_COVER = ["Sentry", "PagerDuty", "Vercel", "npm", "PyPI",
                        "Cal.com", "Calendly"]

VERBOSE = "--verbose" in sys.argv
failures = []


SILENT = False  # set True while verifying a fixture is SUPPOSED to fail


def check(name, got, want):
    if got == want:
        if VERBOSE and not SILENT:
            print(f"  ok   {name}")
    else:
        failures.append(f"{name}: got {got!r}, want {want!r}")
        if not SILENT:
            print(f"  FAIL {name}: got {got!r}, want {want!r}")


def read(path):
    if not path.exists():
        print(f"✗ {path} not found")
        sys.exit(1)
    return path.read_text()


def strip_comments(text):
    """Line comments only — every regex/prose match in this file lives in a
    doc comment (`ChipMemory.seedDemo`'s own header names `#if DEBUG`
    explicitly), so a check reading raw source would fire on the prose
    explaining the rule rather than a real violation. The Obsidian/Cursor
    lesson, paid for twice already in this codebase."""
    return "\n".join(
        line if not (i := line.find("//")) >= 0 else line[:i]
        for line in text.splitlines()
    )


def guard_depth_at(text, index):
    """Net `#if DEBUG` nesting depth at a byte offset — counts every #if as
    +1, #endif as -1, scoped to DEBUG-relevant directives only. A function
    defined where this is > 0 is DEBUG-only, reachable from nowhere a Release
    archive's call graph can reach."""
    depth = 0
    for m in re.finditer(r'^\s*#(if\s+DEBUG|endif|else|elseif\b)', text[:index], re.MULTILINE):
        kw = m.group(1)
        if kw.startswith("if"):
            depth += 1
        elif kw == "endif":
            depth -= 1
        # #else/#elseif inside a DEBUG block don't change nesting depth for
        # this coarse a check — the demo files never nest #if DEBUG so this
        # is sufficient without modeling which branch is active.
    return max(depth, 0)


def check_a_release_reachable(files_text):
    """Check A — every demo-facing function is outside every `#if DEBUG`."""
    for file_key, func_sig in DEMO_FACING_FUNCS:
        text = files_text[file_key]
        clean = strip_comments(text)
        m = re.search(re.escape(func_sig), clean)
        name = f"A · {file_key}.{func_sig.split()[-1]} reachable in Release"
        if not m:
            check(name, "not found", "found")
            continue
        depth = guard_depth_at(clean, m.start())
        check(name, depth, 0)


def check_b_reaches_nothing(files_text):
    """Check B — DemoMode and DemoSeedAll never issue a network call."""
    for file_key in ("DemoMode", "DemoSeedAll"):
        clean = strip_comments(files_text[file_key])
        hit = next((v for v in NETWORK_VERBS if v in clean), None)
        check(f"B · {file_key} reaches nothing", hit, None)


def check_j_per_view_reads_gated(files_text):
    """Check J — every per-view read decides on `DemoMode` before reaching
    out. See `DEMO_GATED_READS` for why this can't ride on check B."""
    for file_key, signature in DEMO_GATED_READS:
        clean = strip_comments(files_text[file_key])
        start = clean.find(signature)
        if start < 0:
            check(f"J · {file_key} {signature.strip()} found", False, True)
            continue
        # Bracket-match the function body so the gate has to be INSIDE it —
        # a `DemoMode` mention elsewhere in a 600-line bridge is not a gate
        # on this read, and matching the whole file would pass on a
        # neighbour's guard (the per-identifier tightening the liveness
        # audit already learned).
        brace = clean.find("{", start)
        depth, end = 0, len(clean)
        for i in range(brace, len(clean)):
            if clean[i] == "{":
                depth += 1
            elif clean[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = clean[brace:end]
        check(f"J · {file_key}.{signature.strip()} gates on DemoMode",
              "DemoMode" in body, True)


def check_c_no_source_collision(files_text):
    """Check C — `infra()`'s body never re-seeds a source `ops`/`schedule`
    already cover. Scoped to the function body only (between its own `{` and
    the matching top-level `}`), not the whole file, so a doc comment naming
    those sources (as `infra()`'s own header does, to explain the history)
    doesn't false-positive the check meant to catch the code doing it again."""
    clean = strip_comments(files_text["DemoSeedAll"])
    m = re.search(r'private static func infra\(\)[^{]*\{', clean)
    if not m:
        check("C · infra() found", False, True)
        return
    # Bracket-match from the opening brace to find the function's real end —
    # a plain regex up to the next `private static func` would over-run into
    # the next function's own source-name literals.
    depth = 0
    end = None
    for i in range(m.end() - 1, len(clean)):
        if clean[i] == "{":
            depth += 1
        elif clean[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    body = clean[m.end():end] if end else clean[m.end():]
    for source in INFRA_MUST_NOT_COVER:
        check(f'C · infra() does not re-seed "{source}"',
              f'"{source}"' in body, False)


def extract_seat_table(demo_src):
    """The (name, statusLine, capability) tuples `DemoSeedAll.seatTable`
    declares — the seats the demo claims are connected. Returns (names,
    body_span) so callers needing "does this name appear OUTSIDE the table"
    (check E) can exclude the table's own declaration from the search."""
    clean = strip_comments(demo_src)
    m = re.search(
        r'private static let seatTable: \[\(String, String, String\)\] = \[(.*?)\n    \]',
        clean, re.DOTALL)
    if not m:
        return None, None
    names = re.findall(r'\("([^"]+)"', m.group(1))
    return names, (m.start(1), m.end(1))


def extract_catalog_names(catalog_src):
    """Every `Offer(name: "…")` in `BridgeCatalog.swift` — connectable or
    not, since check D asks "does a real catalog entry exist", not "can you
    tap Connect on it today"."""
    clean = strip_comments(catalog_src)
    return set(re.findall(r'Offer\(name:\s*"([^"]+)"', clean))


def check_d_seat_names_are_real(files_text):
    """Check D — every `seatTable` name resolves to a real catalog offer
    (through `KNOWN_CATALOG_ALIAS` where the source name and the catalog's
    display name deliberately differ), or is named in
    `KNOWN_NO_CATALOG_SEAT` as a non-bridge capability. Catches a rename or
    retirement in the real catalog that the demo's seat list didn't follow —
    the seat would still LAND rows (check E's job), but under a name the
    catalog no longer recognizes, so the Apps screen and the feed would
    disagree about what "connected" means for it."""
    names, _ = extract_seat_table(files_text["DemoSeedAll"])
    if names is None:
        check("D · seatTable found", False, True)
        return
    catalog_names = extract_catalog_names(files_text["BridgeCatalog"])
    for name in names:
        if name in KNOWN_NO_CATALOG_SEAT:
            continue
        resolved = KNOWN_CATALOG_ALIAS.get(name, name)
        check(f'D · seatTable "{name}" resolves to a real catalog offer',
              resolved in catalog_names, True)


def check_l_seat_names_resolve_at_runtime(files_text):
    """Check L — every `seatTable` name resolves through the rule the APP
    actually runs, `BridgeCatalog.offer(forSource:)`: exact match, else an
    offer whose name ends in `" " + source`.

    Check D above proves the same names resolve through this SCRIPT's
    `KNOWN_CATALOG_ALIAS`, which is a hand table and a different resolution —
    so D passing says nothing about whether the shipped function answers. The
    two agree today and nothing was making them.

    It matters because `RoomGear` — the room's settings door — is gated on
    exactly this call: a demo seat the shipped rule can't resolve draws no
    gear, silently, in the one mode built to show every room working. That is
    also the honest behaviour for a source with no seat, which is why the
    failure is invisible rather than broken.

    `KNOWN_NO_CATALOG_SEAT` is the escape hatch and carries its reason — a
    voice note connects nothing, so it correctly has no gear."""
    names, _ = extract_seat_table(files_text["DemoSeedAll"])
    if names is None:
        check("L · seatTable found", False, True)
        return
    catalog_names = extract_catalog_names(files_text["BridgeCatalog"])

    def resolves(source):
        if source in catalog_names:
            return True
        # The space boundary is the rule, never `contains`: a bare substring
        # test files "Deals" under "Open Food Facts" the first time an offer
        # name happens to carry the word. Mirrors `offer(forSource:)`.
        return any(name.endswith(" " + source) for name in catalog_names)

    for name in names:
        if name in KNOWN_NO_CATALOG_SEAT:
            # Asserted the other way too, or the hatch silently widens: a name
            # listed here that DOES resolve is a stale exemption hiding a seat
            # that has since gained a catalog entry.
            check(f'L · "{name}" is exempt and really has no offer',
                  not resolves(name), True)
            continue
        check(f'L · seatTable "{name}" resolves via offer(forSource:)',
              resolves(name), True)


# A seat that furnishes a READING rather than rows (2026-08-26, prd §484).
#
# Check E asks "does this seat's name appear as a literal anywhere else in
# `DemoSeedAll`", which is the right question for the eighty seats whose
# rooms are made of `Thing`s and structurally the WRONG one for these nine.
# A wallet-riding protocol lands under `source: "Wallet"` or lands nothing at
# all; an exchange balance lands nothing by §163's own ruling, which is that
# it MERGES into the combined total. Neither can ever satisfy check E, and
# before this pass that was read as "these cannot be demoed" — which was the
# bug, not the rule.
#
# So they are exempt from E and answerable to M instead, which is strictly
# STRONGER: E accepts a name appearing in any literal at all (its own
# documented looseness — three of these nine passed E by accident, off an
# unrelated "Aerodrome vote closes" row title and a "Coinbase" counterparty
# name), while M demands the specific fixture the seat's card is drawn from.
# An entry here without a fixture fails; a fixture that is deleted fails.
#
# The DeFi five left this set on 2026-08-29 (prd §515) — not because they stopped
# being furnished, but because they stopped being SEATS: all five land under
# `source: "Wallet"`, so their catalog icons were second doors to the Wallet
# room, and a demo claiming a seat the catalog no longer offers is fake status
# arriving from the demo's side. Their books are asserted by check N instead,
# which is the same assertion without the seat.
KNOWN_ROWLESS_SEAT = {
    "Coinbase", "Kraken", "Binance", "Gemini Exchange",
    # Ethrex Hegotá (prd §500) — rowless for a different reason from the nine
    # above. Those ride the wallet and land under `source: "Wallet"`; this seat
    # lands NO `Thing` at all, by ruling: its readings are live chain state and
    # a devnet test address has no news. So its whole furnishing is the fixture
    # account `HegotaLiveState.seedDemo` installs, which is what check M holds
    # it to.
    "Ethrex Hegotá",
}

# What proves each rowless seat is really furnished: (file key, regex). Each
# pattern names the ONE fixture field that surface reads, so a check can only
# pass while that field is actually populated.
#
# The DeFi five point at `WalletDemoState.state`, which is what
# `WalletWatch.liveState` returns for the whole demo — the only door those
# protocols have, since `DemoMode` reaches no network. Aave's is matched on
# `protocolName:` rather than on a book assignment because Aave and Spark
# share one array and one type; the other four each own a field.
#
# The exchanges point at `ExchangeBridge.demoBalances`, one venue case each,
# plus the merge in `WalletPortfolio.demoFixture` — BOTH halves, because a
# fixture nothing reads furnishes nothing, and that half-wired state is
# exactly what a seat table would still have claimed as connected.
ROWLESS_SEAT_FIXTURE = {
    # Scoped to the `demoBalances` table BODY, never the whole file: every one
    # of these venue cases also appears in the real read above it
    # (`Holding(… venue: .kraken)`), so a file-wide grep would keep passing
    # after the demo entry was deleted — measured on this check's own first
    # run, where dropping Kraken from the fixture left the suite green.
    "Coinbase":        ("ExchangeBridge:demoBalances", r'\.coinbase\)'),
    "Kraken":          ("ExchangeBridge:demoBalances", r'\.kraken\)'),
    "Binance":         ("ExchangeBridge:demoBalances", r'\.binance\)'),
    "Gemini Exchange": ("ExchangeBridge:demoBalances", r'\.geminiExchange\)'),
    # BOTH halves, the exchanges' rule: the fixture must exist AND something
    # must install it, since a fixture nothing reads furnishes nothing and that
    # half-wired state is exactly what a seat table would still claim as
    # connected. `installDemo` is the only door that writes accounts without a
    # read, so naming it pins the whole chain.
    "Ethrex Hegotá": ("HegotaBridge", r'HegotaLiveState\.shared\.installDemo\('),
}


def extract_demo_balances(exchange_src):
    """The body of `ExchangeBridge.demoBalances` — the four exchange seats'
    only fixture. Returned alone so a venue case can be looked for INSIDE it
    rather than anywhere in a file that names every venue several times."""
    clean = strip_comments(exchange_src)
    m = re.search(
        r'static let demoBalances: \[\(symbol: String, usd: Double, venue: Venue\)\] = \[(.*?)\n    \]',
        clean, re.DOTALL)
    return m.group(1) if m else None


def check_m_rowless_seats_are_furnished(files_text):
    """Check M — every `KNOWN_ROWLESS_SEAT` really has its fixture, and the
    exchange fixture is really read.

    The failure this catches renders as a perfectly healthy catalog: the seat
    says connected, the room it belongs to draws, and the one card that seat
    was supposed to add is simply absent — which from outside is
    indistinguishable from that wallet not using the protocol. It is the
    §349 shape, one layer down from rows.

    Asserted in both directions, so the hatch cannot widen on its own: a name
    exempted from check E must be in `ROWLESS_SEAT_FIXTURE`, and a name in
    `ROWLESS_SEAT_FIXTURE` must really be a seat."""
    names, _ = extract_seat_table(files_text["DemoSeedAll"])
    if names is None:
        check("M · seatTable found", False, True)
        return
    for name in sorted(KNOWN_ROWLESS_SEAT):
        check(f'M · rowless seat "{name}" is still a seat', name in (names or []), True)
        entry = ROWLESS_SEAT_FIXTURE.get(name)
        if entry is None:
            check(f'M · rowless seat "{name}" names a fixture', False, True)
            continue
        file_key, pattern = entry
        if file_key.endswith(":demoBalances"):
            clean = extract_demo_balances(files_text[file_key.split(":")[0]])
            if clean is None:
                check("M · ExchangeBridge.demoBalances found", False, True)
                continue
        else:
            clean = strip_comments(files_text[file_key])
        check(f'M · rowless seat "{name}" has its demo fixture',
              re.search(pattern, clean) is not None, True)
    # The exchange fixture must be READ, not merely declared — `demoFixture`
    # is the only path by which a venue reaches the crown, the treemap and the
    # venue chips.
    portfolio = strip_comments(files_text["WalletPortfolio"])
    check("M · demoFixture merges the exchange balances",
          "ExchangeBridge.demoBalances" in portfolio, True)


# The five protocols that are furnished and are NOT seats (prd §515,
# 2026-08-29) — Aave, Morpho, Uniswap, Hyperliquid and Aerodrome.
#
# `WalletDemoState.state` is the only door they have (`DemoMode` reaches no
# network), and the Wallet room's DeFi tiles draw it. Until §515 that fixture
# was asserted only through check M, as a side effect of each having a seat —
# so retiring the seats would have quietly retired the assertion with them, and
# a demo whose Positions scope had gone empty would look exactly like a wallet
# with no positions. Same patterns, held to directly.
#
# The second half is the tripwire, and it is the mirror of `setup-copy-audit.py`
# check 7e: none of the five may return to `seatTable`. A demo seat is a claim
# that the catalog offers the thing, and the catalog does not.
RETIRED_PROTOCOL_FIXTURE = {
    # Matched on `protocolName:` rather than a book assignment because Aave and
    # Spark share one array and one type; the other four each own a field.
    "Aave":        ("WalletWarnings", r'protocolName:\s*"Aave"'),
    "Morpho":      ("WalletWarnings", r's\.morpho\s*=\s*MorphoDeFi\.Book\('),
    "Hyperliquid": ("WalletWarnings", r's\.hyperliquid\s*=\s*HyperliquidDeFi\.Book\('),
    "Aerodrome":   ("WalletWarnings", r's\.aerodrome\s*=\s*AerodromeDeFi\.Book\('),
    "Uniswap":     ("WalletWarnings", r's\.uniswap\s*=\s*UniswapLiquidity\.Book\('),
}


def check_n_retired_protocols_still_draw(files_text):
    """Check N — the five protocols §515 unseated still have their demo book,
    and have not crept back into the seat table."""
    names, _ = extract_seat_table(files_text["DemoSeedAll"])
    if names is None:
        check("N · seatTable found", False, True)
        return
    for name in sorted(RETIRED_PROTOCOL_FIXTURE):
        file_key, pattern = RETIRED_PROTOCOL_FIXTURE[name]
        clean = strip_comments(files_text[file_key])
        check(f'N · unseated "{name}" still has its demo book',
              re.search(pattern, clean) is not None, True)
        check(f'N · unseated "{name}" is not a demo seat',
              name in (names or []), False)


def check_e_seat_names_have_rows(files_text):
    """Check E — every `seatTable` name appears as a literal string
    somewhere OUTSIDE the table's own declaration — i.e., in one of the
    room-building functions, which is where a real seeded row's `source:`
    would carry it (directly or via a tuple element, both of which still
    contain the literal). This is the exact shape of "eight seats furnish
    nothing": a name sitting in `seatTable` with no matching row anywhere
    else in the file."""
    demo_src = files_text["DemoSeedAll"]
    clean = strip_comments(demo_src)
    names, span = extract_seat_table(demo_src)
    if names is None:
        check("E · seatTable found", False, True)
        return
    clean_names, clean_span = extract_seat_table(clean)
    rest = clean[:clean_span[0]] + clean[clean_span[1]:]
    for name in names:
        # A rowless seat cannot satisfy this by construction — check M proves
        # its fixture instead, and asserts it is still a seat, so a name here
        # can never fall out of both checks at once.
        if name in KNOWN_ROWLESS_SEAT:
            continue
        check(f'E · seatTable "{name}" has a seeded row',
              f'"{name}"' in rest, True)


# `FeedScreen.Shape` names its own source-name mappings via literal string
# cases; two others match via an INDIRECT reference or a DYNAMIC predicate,
# which a plain regex over the switch can't resolve — resolved by reading
# the real functions they point at instead of hardcoding a second copy.
# `all` has no bridge to seed at all (a pseudo-source, the unfiltered
# aggregate view — no `Thing` is ever stamped `source: "All"`).
SHAPE_NO_SOURCE = {"all"}

# A shape whose real bridge does not exist — see this file's module doc for
# the `.safari` finding that motivated this dict (found and fixed same-day,
# so it's empty now). Adding a name here is a conscious, tracked exception,
# not a silent skip — the `KNOWN_EXEMPT` pattern this codebase uses
# everywhere else. Don't add an entry to make a red check green without
# checking, the same way, that the shape's bridge really doesn't exist.
KNOWN_UNBACKED_SHAPE = set()


def extract_shape_sources(feed_src, media_src, x402_src, asc_src):
    """Every FeedScreen.Shape case, and the source name(s) that resolve to
    it — literal cases read directly, `.x402`/`.media`/`.appStoreConnect`
    resolved through the real constants/functions they reference so this
    can't drift from what the switch actually does."""
    clean = strip_comments(feed_src)
    m = re.search(r'private enum Shape \{(.*?)\n    \}', clean, re.DOTALL)
    if not m:
        return None
    body = m.group(1)
    case_line = re.search(r'case ([\w, ]+)\n', body)
    all_cases = [c.strip() for c in case_line.group(1).split(",")] if case_line else []

    mappings = re.findall(r'case ([^:]+):\s*self = \.(\w+)', body)
    shape_sources = {}
    for sources_raw, shape in mappings:
        names = re.findall(r'"([^"]+)"', sources_raw)
        shape_sources.setdefault(shape, []).extend(names)

    # `.x402` — `case X402Ingest.source:`, read the real constant.
    x402_clean = strip_comments(x402_src)
    x402_m = re.search(r'static let source\s*=\s*"([^"]+)"', x402_clean)
    if x402_m:
        shape_sources.setdefault("x402", []).append(x402_m.group(1))

    # `.media` — `case _ where MediaShape.isMediaFeed(source):`, read the
    # real predicate's own switch rather than copying its source list.
    media_clean = strip_comments(media_src)
    mf_m = re.search(r'static func isMediaFeed.*?\{(.*?)\n    \}', media_clean, re.DOTALL)
    if mf_m:
        shape_sources.setdefault("media", []).extend(
            re.findall(r'"([^"]+)"', mf_m.group(1)))

    # `.appStoreConnect` — `case ASCShape.source:`, read the real constant
    # (a second indirect reference, same shape as x402's).
    asc_clean = strip_comments(asc_src)
    asc_m = re.search(r'enum ASCShape \{.*?static let source\s*=\s*"([^"]+)"', asc_clean, re.DOTALL)
    if asc_m:
        shape_sources.setdefault("appStoreConnect", []).append(asc_m.group(1))

    return all_cases, shape_sources


def check_f_shape_coverage(files_text):
    """Check F — every `FeedScreen.Shape` case has at least one mapped
    source whose name appears as a literal somewhere in `DemoSeedAll.swift`.
    Unlike the agent panel's figure kinds (checked live, in `verify.sh`'s
    simulator tail, because figure SELECTION depends on runtime ranking
    noise), a Shape is a pure function of a source's NAME — no ranking, no
    simulator, so this can hard-fail the way checks D/E do rather than warn
    the way the panel check does."""
    result = extract_shape_sources(
        files_text["FeedScreen"], files_text["MediaShape"], files_text["CircleX402Bridge"],
        files_text["AppStoreConnectBridge"])
    if result is None:
        check("F · FeedScreen.Shape found", False, True)
        return
    all_cases, shape_sources = result
    demo_clean = strip_comments(files_text["DemoSeedAll"])
    for shape in all_cases:
        if shape == "plain" or shape in SHAPE_NO_SOURCE or shape in KNOWN_UNBACKED_SHAPE:
            continue
        sources = shape_sources.get(shape, [])
        present = any(f'"{s}"' in demo_clean for s in sources)
        check(f'F · Shape.{shape} has a seeded source among {sources}', present, True)


# Check G is the INVERSE of D/E: D/E ask "does what the demo claims have real
# backing" (catalog -> demo, forward); this asks "does everything the
# catalog offers have a demo seat" (demo -> catalog, reverse). Neither
# direction implies the other — D/E alone would happily pass a demo that
# connects six of ninety-six offers, which is exactly what shipped
# (2026-08-11, user: "i don't think the demo shows every feed actually
# connected... look at wallet for example, it only has a few"). Reading the
# real bridges for every reported gap found ONE more of check D/E's own
# failure shape: "Gemini" (the Google Takeout chat import) already had real
# seeded rows in the `chats` array — via `source: c.1`, a variable, so
# check E's literal-string search never had a hope of seeing it — but no
# seatTable entry, so the catalog/Settings screen read "not connected" over
# a room that wasn't empty. Fixed alongside this check, not found by it —
# a lesson for what this check CAN'T do: it proves a name is accounted for
# somewhere, never that the accounting is consistent with the rows.
#
# Three exemption sets, each a conscious ruling checked against the real
# bridge source before adding — never a guess, and never a bare "seems
# unused":
KNOWN_BYOK_PROVIDER = {
    # Agent-group BYOK key providers (`Model/AgentAnswer.swift` family) —
    # "connecting" one only stores a key that powers "Try with your key" on
    # an ANSWER already composed elsewhere. None lands a `Thing`, so none
    # has a source, a room, or a chip to seed. ("Gemini" is NOT here — the
    # catalog's "Gemini" offer is the chat-IMPORT bridge, which does land
    # rows; Google's Gemini Apps is not itself a BYOK provider in this
    # catalog.)
    "Bankr", "Grok", "OpenRouter", "Venice",
}
KNOWN_BALANCE_ONLY = {
    # Merges into the Wallet room's holdings read (`WalletPortfolio`) and
    # lands no `Thing` of its own — but that is NO LONGER a reason to be
    # exempt, and this set shrank from ten names to one on 2026-08-26
    # (prd §484, user: *"the demo mode does not show all sources active, for
    # example, wallet is missing coinbase kraken … shouldn't we have ALL"*).
    # The old reasoning conflated two different things: landing no rows means
    # a seat cannot be proven by check E, not that it cannot be FURNISHED.
    # Nine of the ten now have demo fixtures and real seats, proven by check
    # M via `KNOWN_ROWLESS_SEAT` below.
    #
    # ETH VALIDATORS IS THE ONE THAT STAYS, and the reason is arithmetic
    # rather than plumbing. A beacon-chain validator's minimum activation
    # balance is 32 ETH — at the demo's own seeded ETH price ($3,180,
    # `DemoSeedAll.tokenSeeds`) that is ~$102,000 against a demo portfolio of
    # ~$19,700 across three wallets. Seeding one would not add a reading to
    # the wallet room, it would REPLACE it: the crown grows six-fold, the
    # treemap collapses to a single ETH cell, and every other holding the
    # room exists to show becomes a sliver. There is no smaller honest
    # number, because 32 ETH is what a validator is. Revisit if the demo's
    # money story is ever scaled up to a size that can carry one.
    "ETH Validators",
}
KNOWN_CHIPLESS_CAPTURE = {
    # Rides the generic share-sheet capture path (`Thing`'s own default
    # source, "You") rather than a distinct bridge — Apple offers no export
    # or live read for Notes, so there is no ingest file to stamp a
    # dedicated source at all. `Corpus.chiplessSources` excludes "You" from
    # ever earning a room or chip by ruling (2026-08-02, "get rid of the you
    # chip and room"), so this could never be tray-visible even if seeded.
    #
    # DO NOT "fix" this by giving Apple Notes a demo seat — that was tried
    # on 2026-08-11 and reverted the same day. `NotesShareScreen` is an
    # INSTRUCTION CARD, not a bridge: its own intro says "there is nothing
    # to connect", and unlike Day One / Apple Journal / Bookmarks (all in
    # the same file) it calls NO `registerConnected`. iOS never tells a
    # share extension which app a share came from, so there is no signal a
    # bridge could ever key on. A demo seat here claims a connected state
    # the real screen explicitly refuses to claim. The seven note rows that
    # seed attempt added are kept, correctly, as `source: "You"` own-captures
    # (`DemoSeedAll.ownCaptures`) — which is exactly what a person who
    # shared those notes really would have.
    "Apple Notes",
}
KNOWN_SEARCH_ONLY = {
    # `Thing.searchOnlySources` — reachable by search/Find, never a room or
    # a chip, by the SAME ruling as the two above but a different mechanism
    # (findable-not-browsable rather than no-distinct-source-at-all).
    "Contacts", "HomeKit",
}


def extract_connectable_catalog_offers(catalog_src):
    """Every `Offer(name: "…", …, connectable: true, …)` — the offers a real
    person can actually tap Connect on. `connectable: false` entries (a
    "Soon" tile with no working setup screen) are excluded on purpose: they
    have nothing to seed."""
    clean = strip_comments(catalog_src)
    pairs = re.findall(
        r'Offer\(name:\s*"([^"]+)".*?connectable:\s*(true|false)',
        clean, re.DOTALL)
    return {name for name, connectable in pairs if connectable == "true"}


def check_g_catalog_offers_have_demo_seats(files_text):
    """Check G — the reverse of D/E. Every CONNECTABLE catalog offer either
    has a demo seat (a `seatTable` entry, via `KNOWN_CATALOG_ALIAS` where the
    names differ — the same alias set D already uses, reused rather than
    duplicated) or is named in one of the three exemption sets above with a
    checked reason. A catalog offer in neither bucket is a demo gap: a real
    person could connect it and see their own things; a demo visitor sees
    nothing, and the "everything already connected" promise is false for
    that seat."""
    names, _ = extract_seat_table(files_text["DemoSeedAll"])
    if names is None:
        check("G · seatTable found", False, True)
        return
    legacy = {"Gmail", "Calendar", "ChatGPT", "Reminders", "Photos",
              "Claude", "Wallet", "Tokens"}
    demo_seat_catalog_names = {KNOWN_CATALOG_ALIAS.get(n, n) for n in names} | legacy
    connectable = extract_connectable_catalog_offers(files_text["BridgeCatalog"])
    exempt = KNOWN_BYOK_PROVIDER | KNOWN_BALANCE_ONLY | KNOWN_CHIPLESS_CAPTURE | KNOWN_SEARCH_ONLY
    for offer in sorted(connectable):
        if offer in exempt:
            continue
        check(f'G · catalog offer "{offer}" has a demo seat',
              offer in demo_seat_catalog_names, True)


# The eight legacy seats check G can only test by NAME, since they live in
# `BridgeApp.demo` rather than in `seatTable`.
LEGACY_DEMO_SEATS = {"Gmail", "Calendar", "ChatGPT", "Reminders", "Photos",
                     "Claude", "Wallet", "Tokens"}

# A legacy seat that is allowed to read as not-connected — and it may only
# stay here while the demo seeds NO rows for it. Reminders is the one: the
# overdue kept-ask the demo primes is carried by a Todoist row
# (`DemoSeedAll.schedule`'s "Book the dentist"), not by a Reminders row, so
# this seat furnishes nothing and a paused seat is the honest reading of
# that. If rows ever land for it, check K fails and the answer is to connect
# the seat, not to widen this set.
KNOWN_UNCONNECTED_LEGACY_SEAT = {"Reminders"}


def check_k_legacy_seats_match_their_rows(files_text):
    """Check K — a legacy demo seat with ROWS must read CONNECTED.

    Check G tests membership and never status, which is how `Photos` shipped
    as `.paused` / "Not connected" while `DemoSeedAll.photos()` seeded the
    screenshot rows that make the demo's single biggest room: the feed was
    full, the sources tray carried the chip, and the catalog said the app was
    not connected (found 2026-08-20). `BridgeStore.demo`'s own comment says
    that table exists to stop exactly this — "a room full of rows whose app
    reads 'not connected'" — and nothing enforced it in the other direction.

    Both halves are checked, so neither kind of drift can hide: a seat with
    rows must be connected, and a seat exempted as unconnected must really
    have no rows."""
    demo_clean = strip_comments(files_text["DemoSeedAll"])
    store_clean = strip_comments(files_text["BridgeStore"])
    # "Seeded" is check E's rule — the name appears as a quoted literal —
    # and NOT the tighter `source: "X"`, which was this check's own first cut
    # and reported ChatGPT and Claude as unseeded while both furnish real
    # rooms: their rows are built from a `chats` array and take
    # `source: c.1`, so the source name lives in a tuple literal that a
    # `source:` grep structurally cannot see. Measured across all eight
    # (2026-08-20): every seat that furnishes anything carries at least one
    # literal, and Reminders carries exactly zero, so the two cases separate
    # cleanly.
    #
    # The known looseness runs one way only and is the harmless one: a name
    # appearing in some non-seeding literal would count as seeded and demand
    # the seat read connected, which for a legacy seat is the right answer
    # anyway. The EXEMPTION half stays strict — zero literals, no exceptions
    # — so a seat cannot be excused while quietly furnishing a room.
    seeded = {name for name in LEGACY_DEMO_SEATS if f'"{name}"' in demo_clean}
    for name in sorted(LEGACY_DEMO_SEATS):
        # The seat's own `.init(…)` line in `BridgeApp.demo`, matched from the
        # name to the end of its status so a neighbouring seat can't answer
        # for it.
        entry = re.search(r'name:\s*"' + re.escape(name) + r'"\s*,\s*status:\s*\.(\w+)',
                          store_clean)
        if entry is None:
            check(f'K · legacy seat "{name}" found in BridgeApp.demo', False, True)
            continue
        connected = entry.group(1) == "connected"
        if name in KNOWN_UNCONNECTED_LEGACY_SEAT:
            check(f'K · exempt seat "{name}" really seeds no rows',
                  name not in seeded, True)
        elif name in seeded:
            check(f'K · seeded legacy seat "{name}" reads connected', connected, True)
        else:
            # Not seeded and not exempt: it furnishes nothing and claims to be
            # working — the "eight seats furnish nothing" shape check E exists
            # for, in the one table check E cannot see.
            check(f'K · unseeded legacy seat "{name}" is exempted with a reason',
                  not connected, True)


# Check H closes the loop check G's own construction left open. A room-head
# bridge whose state is `private` (Safe) cannot be seeded from
# `DemoSeedAll.swift` at all — no `KNOWN_*` exemption in check G can make
# that honest, because the gap isn't "should this be seeded", it's "CAN this
# be seeded from outside the file". Found live (2026-08-11): another session
# added `safeHead` to `verify.sh`'s room-head sweep the same day it added
# the room head, and the sweep correctly failed — `SafeRoomSource.compose`
# reads only `detectedKey`/`configSnapshotKey`/`trackingKey`, all `private`
# to `SafeBridge.swift`. The fix that session landed, independently and in
# parallel with this one (`SafeBridge.seedDemoSnapshot`/`clearDemoSnapshot`),
# is the pattern this check makes standing: a bridge that owns `private`
# room-head state owns seeding it too, in its own file, where private
# access is free — never a second, unreachable attempt from DemoSeedAll.
#
# `STATE_OWNING_BRIDGES` is deliberately NOT "every SourceHead bridge" — only
# the ones whose state genuinely can't be reached any other way. The other
# four state-reading heads (App Store Connect, Apple Wallet, PostHog,
# Cloudflare) work today via a DIFFERENT, also-honest route: their state
# lives in `internal`/public types (`ASCState`, `AppleWalletBridge.connected`,
# `PostHogState`, `CloudflareEstateStore`) that `DemoSeedAll.seedBridgeState`
# already writes directly — no hook needed because nothing is blocking
# access. `KNOWN_CENTRALIZED_STATE_SEED` names them so a future reader
# doesn't mistake the absence of a hook there for the same gap Safe had.
STATE_OWNING_BRIDGES = {
    # Nothing outside SafeBridge.swift can read or write detectedKey/
    # configSnapshotKey/trackingKey — verified against the real file (all
    # three are `private static`).
    "Safe": "SafeBridge",
}
KNOWN_CENTRALIZED_STATE_SEED = {
    "App Store Connect": "ASCState is internal; DemoSeedAll writes .standing/.apps/.lastRead directly",
    "Apple Wallet": "AppleWalletBridge.connected is internal; DemoSeedAll sets it directly",
    "PostHog": "PostHogState is internal; DemoSeedAll writes .replace(metrics) directly",
    "Cloudflare": "CloudflareEstateStore is internal; DemoSeedAll calls .save(...) directly",
}


def check_h_state_owning_bridges_seed_themselves(files_text):
    """Check H — every bridge in `STATE_OWNING_BRIDGES` has a
    `static func seedDemo…` (prefix match, so `seedDemo` and
    `seedDemoSnapshot` both count — two real names already ship) in its OWN
    file. A room-head bridge added to this dict with no matching function is
    the exact gap `safeHead` shipped with until this same day's fix — caught
    here now, statically, before a simulator ever has to prove it by
    failing."""
    for source, file_key in STATE_OWNING_BRIDGES.items():
        src = files_text.get(file_key)
        if src is None:
            check(f'H · {file_key} found for state-owning bridge "{source}"', False, True)
            continue
        clean = strip_comments(src)
        has_hook = re.search(r'static func seedDemo\w*\(', clean) is not None
        check(f'H · {file_key} ("{source}") has its own seedDemo… function',
              has_hook, True)


def extract_move_counterparties(demo_src):
    """The counterparty NAME out of each `walletRoom()` transfer tuple —
    every line of the `moves` table carries exactly two quoted strings, the
    amount and then the name."""
    clean = strip_comments(demo_src)
    m = re.search(r'let moves: \[\(Bool, String, String, Double, Double\)\] = \[(.*?)\n        \]',
                  clean, re.DOTALL)
    if not m:
        return None
    names = set()
    for line in m.group(1).splitlines():
        quoted = re.findall(r'"([^"]*)"', line)
        if len(quoted) == 2:
            names.add(quoted[1])
    return names


def extract_book_counterparties(demo_src):
    """The names `demoCounterparties` puts in the address book."""
    clean = strip_comments(demo_src)
    m = re.search(r'static let demoCounterparties:.*?= \[(.*?)\n    \]', clean, re.DOTALL)
    if not m:
        return None
    return set(re.findall(r'\("([^"]+)",\s*\.\w+\)', m.group(1)))


def check_i_wallet_counterparties_are_named(files_text):
    """Check I — the wallet's transfer counterparties and the demo address
    book name the SAME set of people, both ways.

    A name in the transfers but not the book is a counterparty with no face:
    the row reads fine (it carries `transferCounterparty` as text) while
    everything reading the BOOK — a saved name, an avatar, the whole
    `AddressConnections` graph — has nothing to draw. That is exactly the
    state the demo shipped in until 2026-08-11, and it was invisible from
    the feed, which is why it took probing the book (`1 named`, that one
    being the demo wallet itself) to see it.

    A name in the book but not the transfers is the inverse: a person in
    your address book you have never transacted with, which for a synthetic
    counterparty is a phantom nobody can explain.

    Deliberately not a check that the ADDRESSES agree — they can't disagree
    by construction, since both sides call `counterpartyAddress(for:)`. That
    shared derivation is the fix; this guards the two NAME lists that feed
    it."""
    demo_src = files_text["DemoSeedAll"]
    moves = extract_move_counterparties(demo_src)
    book = extract_book_counterparties(demo_src)
    if moves is None or book is None:
        check("I · wallet moves and demoCounterparties both found",
              False, True)
        return
    for name in sorted(moves - book):
        check(f'I · transfer counterparty "{name}" is named in the address book',
              False, True)
    for name in sorted(book - moves):
        check(f'I · address-book name "{name}" appears in a real transfer',
              False, True)
    if moves == book:
        check(f'I · {len(moves)} wallet counterparties all have book entries',
              True, True)


# A Swift string literal's leading run of REAL characters — everything before
# its first `\(interpolation)` or escape. `[^"\\]*` stops at both, which is the
# whole trick: `\(` is NOT an escape in Swift, so the obvious literal regex
# (`(?:[^"\\]|\\.)*`) swallows it as one and reports a head of `off:\(` for a
# ref whose real head is `off:`. Caught on this check's first run.
LITERAL_HEAD = r'"([^"\\]*)'

# Literal namespaces that are never a `Thing.sourceRef`: bundled sample art
# (`RemoteImageLoader` resolves that scheme in DEBUG), permalinks, and the
# note ids a Nostr row carries as its `content`.
NON_REF_LITERALS = ("http", "sample:", "nostr:note", "obsidian://", "casberi:")

# Argument labels and properties that hold a namespaced string which is not a
# ref. Matched against the 40 characters before the literal.
NON_REF_LABELS = ("content:", "externalLink", "previewImageURL",
                  "authorAvatarURL", "url:", "link:")

# Ref FRAGMENTS — a literal that is assembled into a ref at the call site, so
# the whole ref never appears in the source and no prefix can match this half.
# Each entry names the prefix that covers the assembled form; a new one is a
# conscious "this is a piece, not a ref".
KNOWN_REF_FRAGMENT = {
    # `vibenet()` writes `ref: "vibenet:\(ref)"` over these four event tails
    # (prd §495 gave them real transaction hashes), and `"vibenet:"` covers the
    # assembled ref.
    "actor:0x7c1d4e9a2b6f83c05d17e4a9b820f36cd15e7a48b93c206df41e85a7cb90d24f:0": "vibenet:",
    "actor:0x3f8b25c6d017a94e5b83f2016cd74a9e8b520371fc6ad9e04b18752c3ae6f091:1": "vibenet:",
    "actor:0x5a2c9e18b7043fd61c85920ae3b47d6f0c19a5e8347b26df10a95c8e2b4713a9:0": "vibenet:",
    "locked:0x9e04a71b3c8d526f0a94e7128bd35c6f807a1e29d4b60358cf9a2e714d80b365:0": "vibenet:",
    # The demo repository id, interpolated INTO `radicle:\(kind):\(rid):…`,
    # which `radicle:patch:rad:zDEMO`/`radicle:issue:rad:zDEMO` cover.
    "rad:zDEMOheartwood0000000000001": "radicle:",
}

# `ref:` arguments built by a function. The value is the prefix in
# `refPrefixes`/`escapedPrefixes` that covers what the function returns — which
# a text check cannot derive, and which is exactly why Altana's six rows sat
# uncovered from the day they landed.
KNOWN_COMPUTED_REF = {
    "AltanaKeystore.ref": "altana:key:",
    "Corpus.importReceiptRef": "import:receipt:",
    "L2beatWatch.chainRef": "l2beat:chain:",
    "WalletbeatWatch.walletRef": "walletbeat:wallet:",
    "PostHogWatch.metricRef": "posthog:metric:",
    "StockWatch.symbolRef": "stocktwits:sym:",
}


def check_k_seeded_refs_are_cleared(files_text):
    """Every ref the seeder writes must be covered by a `refPrefixes` entry.

    `refPrefixes` is the ONE list both `clear` and `restampIfStale` walk, so a
    ref missing from it fails twice and silently: the row outlives every demo
    exit, and it freezes in place while the rest of the corpus is shifted
    forward by the freshness re-stamp. Nothing renders wrong — an orphan looks
    exactly like a real synced row, which is the whole problem.

    Absent until 2026-08-17, and its absence had already shipped SEVEN
    orphans: four `wallet:safe:eth:demo…` rows (the worst of them, since
    `teardown` clears the Safe snapshot, so they survived as "Your turn" tags
    with no head behind them), two `1claw:policy:demo…` grants, and the one
    `bitcoin:settled:…` money receipt.

    Compared on literal heads only — a ref like `"bitcoin:settled:\\(demoWallet)
    :demo0"` is half runtime — so this proves a prefix EXISTS to cover the ref,
    never that the interpolations agree. That ceiling is deliberate: the
    alternative is evaluating Swift, and a coarse check that catches an absent
    family is worth more than a precise one nobody writes.

    Compatibility is checked in BOTH directions, and that is not a loosening
    for its own sake. `"railgun:\\(kind):demo\\(i)"` has a literal head of just
    `railgun:` because the part that distinguishes it — shield vs unshield —
    is computed, while its prefixes are the full `railgun:shield:demo`. A
    one-directional test calls that uncovered when at runtime it plainly is,
    and three such rows fired on this check's first run. So a ref is a finding
    only when NO prefix could possibly apply: neither is a prefix of the
    other."""
    text = strip_comments(files_text["DemoSeedAll"])

    # TWO lists since 2026-08-28: `refPrefixes` ends `] + escapedPrefixes`, and
    # the second holds the four families that had escaped it. Both are read, or
    # every entry in the second reads as missing.
    block = re.search(r"static let refPrefixes = \[(.*?)\]\s*\+\s*escapedPrefixes",
                      text, re.DOTALL)
    escaped = re.search(r"static let escapedPrefixes: \[String\] = \[(.*?)\n    \]",
                        text, re.DOTALL)
    # THIRD list (prd §510a): shapes the seeder USED to write. It is swept but
    # never seeded, so its entries are legitimate ref literals that no current
    # prefix covers — the scan below would report every one of them as a
    # finding if the declaration were left inside the body it walks.
    retired = re.search(r"static let retiredPrefixes: \[String\] = \[(.*?)\n    \]",
                        text, re.DOTALL)
    if not block or not escaped or not retired:
        check("K all three prefix lists are findable",
              bool(block) and bool(escaped) and bool(retired), True)
        return
    # Literal entries only. An entry like `PostHogWatch.metricRef("signed_up")`
    # is a computed ref, and the seeder writes it the same computed way, so
    # neither side is a literal and both are skipped together — which is the
    # gap `KNOWN_COMPUTED_REF` closes below.
    declared = block.group(1) + escaped.group(1)
    # `":" in p` drops the `", "` separators the head regex also matches when
    # several entries share a line.
    retired_prefixes = [p for p in re.findall(LITERAL_HEAD, retired.group(1))
                        if p and ":" in p]
    prefixes = [p for p in re.findall(LITERAL_HEAD, declared) if p]
    # The computed entries, by the function that builds them.
    prefix_builders = set(re.findall(r"([A-Za-z_][A-Za-z0-9_.]*)\s*\(", declared))

    # Refs the seeder actually writes. Everything after BOTH lists, so the
    # prefix declarations are not mistaken for seeded refs.
    body = text[max(escaped.end(), retired.end()):]
    uncovered = []
    for m in re.finditer(r'\bref:\s*' + LITERAL_HEAD, body):
        head = m.group(1)
        if not head:
            continue
        if not any(head.startswith(p) or p.startswith(head) for p in prefixes):
            line = body[:m.start()].count("\n") + text[:max(escaped.end(), retired.end())].count("\n") + 1
            uncovered.append(f"{head}… (line {line})")

    check("K every seeded ref is covered by refPrefixes",
          uncovered or "none", "none")

    # ---- The two blind spots this check had until 2026-08-28 (prd §510a) -----
    #
    # The scan above matches `ref:` followed by a LITERAL, which is how most of
    # the seeder writes a ref and is not how any of the four escaped families
    # wrote theirs. `cardPointers()` and the wallet's three deadlines put their
    # refs in a TUPLE TABLE and pass `ref: ref` / `ref: d.ref`; Altana's are
    # built by `AltanaKeystore.ref(...)`. All four were invisible here — the
    # check reported green over exactly the bug it exists to prevent — and the
    # cost was a user on a NEW install seeing four CardPointers offers for a
    # seat they had never connected, with no door to remove them.
    #
    # So: every namespaced literal ANYWHERE in the seeder body, minus the
    # positions that legitimately hold a non-ref string.
    for m in re.finditer(r'"([a-z0-9]+:[^"\n]*)', body):
        value = m.group(1)
        head = value.split("\\(")[0]
        if value.startswith(NON_REF_LITERALS):
            continue
        # A `content:`/`externalLink`/image URL is a namespaced string that is
        # not a ref. Judged by what precedes the literal, which is coarse and
        # is why the prefixes above carry the load; this half only has to be
        # quiet enough to stay switched on.
        if any(label in body[max(0, m.start() - 40):m.start()] for label in NON_REF_LABELS):
            continue
        if head in KNOWN_REF_FRAGMENT:
            continue
        if not any(head.startswith(p) or p.startswith(head) for p in prefixes):
            line = body[:m.start()].count("\n") + text[:max(escaped.end(), retired.end())].count("\n") + 1
            uncovered.append(f"{head}… (line {line})")

    check("K every seeded ref literal is covered, wherever it is written",
          uncovered or "none", "none")

    # And the computed half. A `ref:` argument that is neither a literal nor a
    # plain local name cannot be resolved by a text check, so it must SAY which
    # prefix covers it — an entry here is a conscious "this builder's output
    # starts with that". Without this, `AltanaKeystore.ref(...)` reads as an
    # opaque expression and its six rows outlive every exit unnoticed.
    unexplained = []
    for m in re.finditer(r"\bref:\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\(", body):
        expr = m.group(1)
        covering = KNOWN_COMPUTED_REF.get(expr)
        if covering is None:
            line = body[:m.start()].count("\n") + text[:max(escaped.end(), retired.end())].count("\n") + 1
            unexplained.append(f"{expr}(…) (line {line})")
        elif expr in prefix_builders:
            # The list builds its entry with the SAME function, so the two
            # cannot disagree — the strongest form of coverage there is.
            continue
        elif not any(p.startswith(covering) or covering.startswith(p) for p in prefixes):
            unexplained.append(f"{expr}(…) claims {covering!r}, no such prefix")

    check("K every computed ref names the prefix that covers it",
          unexplained or "none", "none")

    # A "retired" shape that the seeder still writes is not retired — and
    # `sweepEscapedRows` walks that list unconditionally, so the migration
    # would delete rows out from under a demo somebody is standing in. Compared
    # against the seeder body, which is everything after the three lists.
    still_written = sorted({
        p for p in retired_prefixes
        if re.search(r'"' + re.escape(p), body)
    })
    check("K no retired shape is still seeded", still_written or "none", "none")


def run_checks(files_text):
    before = len(failures)
    check_k_seeded_refs_are_cleared(files_text)
    check_a_release_reachable(files_text)
    check_b_reaches_nothing(files_text)
    check_j_per_view_reads_gated(files_text)
    check_c_no_source_collision(files_text)
    check_d_seat_names_are_real(files_text)
    check_l_seat_names_resolve_at_runtime(files_text)
    check_e_seat_names_have_rows(files_text)
    check_m_rowless_seats_are_furnished(files_text)
    check_n_retired_protocols_still_draw(files_text)
    check_f_shape_coverage(files_text)
    check_g_catalog_offers_have_demo_seats(files_text)
    check_k_legacy_seats_match_their_rows(files_text)
    check_h_state_owning_bridges_seed_themselves(files_text)
    check_i_wallet_counterparties_are_named(files_text)
    return len(failures) == before


def verify_fixture(label, mutate_fn, checker_fn, expect_catch):
    """Run `checker_fn` over a mutated copy of the real source, in SILENT mode
    so a deliberately-broken fixture doesn't print as if it were a real
    failure, and restore `failures` afterward so fixture noise never leaks
    into the real report."""
    global SILENT
    bad = {k: read(v) for k, v in DEMO_FILES.items()}
    mutate_fn(bad)
    saved = list(failures)
    failures.clear()
    SILENT = True
    checker_fn(bad)
    caught = len(failures) > 0
    SILENT = False
    failures.clear()
    failures.extend(saved)
    ok = caught == expect_catch
    if ok and VERBOSE:
        print(f"  ok   self-test: {label}")
    elif not ok:
        print(f"✗ self-test: {label} — expected catch={expect_catch}, got={caught}")
    return ok


def self_test():
    """Prove each check can actually fail — a check that cannot fail proves
    nothing (the `swiftdata-liveness-audit.py` lesson, restated here)."""
    ok = True

    # The three shapes check K was BLIND to until 2026-08-28 — each one shipped,
    # and each rendered as an ordinary row nothing could tell from a real one.
    ok &= verify_fixture(
        "a ref written in a TUPLE TABLE, uncovered, is caught",
        # CardPointers passes `ref: ref` out of its own table, so the old
        # `ref:`-followed-by-a-literal scan never saw these four refs at all.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '"cardpointers:offer:demo",', "", 1)),
        check_k_seeded_refs_are_cleared, True)

    ok &= verify_fixture(
        "an uncovered ref built from a demo wallet is caught",
        # The wallet's three reconciling deadlines, passed as `ref: d.ref`.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '"aerodrome:vote:\\(demoWallet):",', "", 1)),
        check_k_seeded_refs_are_cleared, True)

    ok &= verify_fixture(
        "a ref built by a FUNCTION with no covering prefix is caught",
        # Altana's six keys. Dropping both entries leaves `AltanaKeystore.ref`
        # an opaque expression the literal scan cannot reach — which is the
        # state it shipped in.
        lambda f: f.__setitem__("DemoSeedAll", re.sub(
            r"        AltanaKeystore\.ref\(chain: demoAltanaChain[\s\S]*?keyID: \"\"\),\n",
            "", f["DemoSeedAll"])),
        check_k_seeded_refs_are_cleared, True)

    ok &= verify_fixture(
        "a 'retired' shape the seeder still writes is caught",
        # `sweepEscapedRows` walks `retiredPrefixes` unconditionally, so a
        # shape listed there while still being seeded means the migration
        # deletes rows out from under a live demo.
        # `1claw:policy:demo` is already in `refPrefixes` and is still written
        # by `infra()`, so listing it as retired changes exactly one thing —
        # which is what makes this fixture test the rule it names.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '        "bankr:ask-01",', '        "bankr:ask-01", "1claw:policy:demo",', 1)),
        check_k_seeded_refs_are_cleared, True)

    ok &= verify_fixture(
        "a clean tree is NOT flagged by the widened scan",
        lambda f: None,
        check_k_seeded_refs_are_cleared, False)

    ok &= verify_fixture(
        "DEBUG-guarded seedDemo is caught",
        lambda f: f.__setitem__("ChipMemory", f["ChipMemory"].replace(
            "static func seedDemo(_ visits: [String: Int]) {",
            "#if DEBUG\n    static func seedDemo(_ visits: [String: Int]) {",
            1,
        ) + "\n#endif\n"),
        check_a_release_reachable, True)

    ok &= verify_fixture(
        "a network verb in DemoMode is caught",
        # NOT a `//` comment — `strip_comments` correctly erases those, and a
        # fixture hidden behind the exact defense it's testing proves
        # nothing (caught on this check's own first run).
        lambda f: f.__setitem__("DemoMode", f["DemoMode"] + "\nlet x = URLSession.shared\n"),
        check_b_reaches_nothing, True)

    ok &= verify_fixture(
        "an ungated per-view read is caught",
        # Removes the gate from `KalshiWatch.book` the way a refactor would —
        # the room still compiles, still renders, and quietly reaches the
        # exchange again. NOT a comment edit: `strip_comments` erases those,
        # and a fixture hidden behind the defense it tests proves nothing
        # (check B's own lesson, one check over).
        lambda f: f.__setitem__("KalshiWatch", f["KalshiWatch"].replace(
            "if DemoMode.isActive {", "if false {", 1)),
        check_j_per_view_reads_gated, True)

    ok &= verify_fixture(
        "a per-view read whose gate moved OUT of the function is caught",
        # The subtler half: `DemoMode` still appears in the file, just not in
        # this function's body. A whole-file grep would pass; the
        # bracket-matched body check is what catches it.
        lambda f: f.__setitem__("PolymarketBridge", f["PolymarketBridge"].replace(
            "if DemoMode.isActive {\n            return Array(PredictionDemoBook.polymarket",
            "if false {\n            return Array(PredictionDemoBook.polymarket", 1)),
        check_j_per_view_reads_gated, True)

    # Check M's four fixtures. The first two are the real failure — a
    # fixture deleted or renamed while its seat keeps claiming connected —
    # and the third is the half-wired state that would otherwise pass every
    # other check in this file: the balances declared and nothing reading
    # them, so the seats read connected and the crown never changes.
    # Check N's two, which used to be check M's (prd §515 moved the DeFi five
    # out of the seat table and their assertion with them). The failure is the
    # same one it always was — a fixture deleted or renamed while a surface goes
    # on claiming to draw it — and the second is now its opposite: the seat
    # coming back.
    ok &= verify_fixture(
        "a deleted DeFi demo book is caught",
        lambda f: f.__setitem__("WalletWarnings", f["WalletWarnings"].replace(
            "s.uniswap = UniswapLiquidity.Book(", "s.uniswapX = UniswapLiquidity.Book(", 1)),
        check_n_retired_protocols_still_draw, True)

    ok &= verify_fixture(
        "an unseated protocol creeping back into the seat table is caught",
        # The §515 rule from the demo's side: a demo seat claims the catalog
        # offers the thing, and for these five it does not.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("Peer", "Rides your wallet",',
            '("Aave", "Rides your wallet", "Reads your collateral and debt."),\n'
            '        ("Peer", "Rides your wallet",', 1)),
        check_n_retired_protocols_still_draw, True)

    ok &= verify_fixture(
        "a dropped exchange venue is caught",
        # A venue removed from `demoBalances` — the seat still claims
        # connected and the crown silently loses that money. BINANCE, not
        # Kraken: Kraken holds two entries in the table, so re-pointing one of
        # them leaves the other matching and the mutation survives (measured
        # on this fixture's own first run — the "right result for the wrong
        # reason" class this repo keeps re-earning). Binance holds exactly
        # one, so this really unseats it.
        lambda f: f.__setitem__("ExchangeBridge", f["ExchangeBridge"].replace(
            '("USDC", 1_150, .binance)', '("USDC", 1_150, .coinbase)', 1)),
        check_m_rowless_seats_are_furnished, True)

    ok &= verify_fixture(
        "an exchange fixture nothing reads is caught",
        # Targets the `for` line, NOT the first occurrence — the doc comment
        # above it names the same symbol, and replacing that instead leaves
        # the real read in place and the fixture proving nothing (caught on
        # this fixture's own first run).
        lambda f: f.__setitem__("WalletPortfolio", f["WalletPortfolio"].replace(
            "for holding in ExchangeBridge.demoBalances",
            "for holding in [(symbol: String, usd: Double, venue: ExchangeBridge.Venue)]()", 1)),
        check_m_rowless_seats_are_furnished, True)

    ok &= verify_fixture(
        "a rowless seat dropped from the seat table is caught",
        # The other direction: the fixture survives, the SEAT goes — so the
        # demo furnishes a card for an app its catalog says is not connected,
        # which is check G's failure arriving through the exemption set.
        # BINANCE since §515 took the DeFi five out of this set: the fixture
        # must name a seat the set still holds, or it proves nothing.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("Binance", "Read-only key",', '("BinanceX", "Read-only key",', 1)),
        check_m_rowless_seats_are_furnished, True)

    ok &= verify_fixture(
        "a re-seeded source in infra() is caught",
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            "private static func infra() -> [Thing] {",
            'private static func infra() -> [Thing] {\n'
            '        _ = "Sentry"\n',
            1,
        )),
        check_c_no_source_collision, True)

    ok &= verify_fixture(
        "a seatTable name with no matching catalog offer is caught",
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("Voice", "3 notes", "Transcribes on device."),',
            '("Voice", "3 notes", "Transcribes on device."),\n'
            '        ("Totally Fake Bridge Name", "Synced", "Does nothing real."),',
            1,
        )),
        check_d_seat_names_are_real, True)

    ok &= verify_fixture(
        "a seatTable name with no seeded row anywhere else is caught",
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("Voice", "3 notes", "Transcribes on device."),',
            '("Voice", "3 notes", "Transcribes on device."),\n'
            '        ("Quandrafloop Sync Test", "Synced", "Nowhere else in the file."),',
            1,
        )),
        check_e_seat_names_have_rows, True)

    ok &= verify_fixture(
        "a Shape with no seeded source anywhere is caught",
        # Strip every literal occurrence of "Files" — .files's only mapped
        # source — so nothing in the mutated tree can satisfy it. A targeted
        # string a real title/comment doesn't otherwise need, so this can't
        # accidentally break unrelated checks running over the same fixture.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace('"Files"', '"NotFiles"')),
        check_f_shape_coverage, True)

    ok &= verify_fixture(
        "a connectable catalog offer with no demo seat is caught",
        # Strip GitLab's seatTable line — a real, non-exempt, connectable
        # catalog offer with real seeded rows loses its ONLY route into
        # `demo_seat_catalog_names`, so check G must flag it even though its
        # rows are still sitting in the file (this check is about the
        # CATALOG/SETTINGS status, not about rows — check E already covers
        # rows).
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("GitLab", "Synced 10m ago", "Reads issues and merge requests assigned to you."),\n        ',
            '', 1)),
        check_g_catalog_offers_have_demo_seats, True)

    ok &= verify_fixture(
        "a state-owning bridge with no seedDemo… function is caught",
        # Rename the real hook so the prefix match can't find it — the
        # `.replace` targets the function keyword itself, not a comment, so
        # a fixture hidden behind the exact regex it's testing proves
        # nothing (this check's own first-run lesson, paid for twice
        # already by checks D and F).
        lambda f: f.__setitem__("SafeBridge", f["SafeBridge"].replace(
            "static func seedDemoSnapshot", "static func plantDemoSnapshot", 1)),
        check_h_state_owning_bridges_seed_themselves, True)

    ok &= verify_fixture(
        "a wallet counterparty with no address-book entry is caught",
        # Drop Mia from the book table while her two transfers stay — the
        # exact shape the demo shipped in: the row still reads fine off
        # `transferCounterparty`, and nothing reading the book can draw her.
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '("Sam", .wallet), ("Mia", .wallet), ("Coinbase", .wallet),',
            '("Sam", .wallet), ("Coinbase", .wallet),', 1)),
        check_i_wallet_counterparties_are_named, True)

    # And the clean tree must pass all three, so the fixtures above are
    # proven against a REAL failure, not a checker that always fails.
    global SILENT
    clean = {k: read(v) for k, v in DEMO_FILES.items()}
    # Check K, proven against the exact bug it was written for: drop two of the
    # families from `refPrefixes` and the rows they name must be reported as
    # uncleared. This is the shipped state of 2026-08-16 restored on purpose —
    # a fixture that recreates a real incident rather than an invented one.
    ok &= verify_fixture(
        "a seeded ref family missing from refPrefixes is caught",
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"].replace(
            '"wallet:safe:eth:demo", "1claw:policy:demo",', "", 1)),
        check_k_seeded_refs_are_cleared, True)

    # …and the interpolation case, which this check got wrong on its own first
    # run: a ref whose distinguishing segment is COMPUTED (`railgun:\(kind):…`)
    # is covered by a longer literal prefix, and must not be reported. Without
    # the bidirectional test this fixture fails, which is what makes it a
    # guard on the rule rather than on the code that happens to implement it.
    ok &= verify_fixture(
        "a computed-segment ref is not reported as uncleared",
        lambda f: f.__setitem__("DemoSeedAll", f["DemoSeedAll"]),
        check_k_seeded_refs_are_cleared, False)

    saved = list(failures)
    failures.clear()
    SILENT = True
    passed = run_checks(clean)
    SILENT = False
    failures.clear()
    failures.extend(saved)
    if not passed:
        print("✗ self-test: the CLEAN tree failed its own checks")
        ok = False
    elif VERBOSE:
        print("  ok   self-test: clean tree passes")

    return ok


def main():
    if "--self-test" in sys.argv:
        if self_test():
            print("✓ demo self-test: all fixtures behaved as designed")
            sys.exit(0)
        else:
            print("✗ demo self-test: a fixture did not behave as designed")
            sys.exit(1)

    files_text = {k: read(v) for k, v in DEMO_FILES.items()}
    ok = run_checks(files_text)
    if ok:
        seat_names, _ = extract_seat_table(files_text["DemoSeedAll"])
        shape_result = extract_shape_sources(
            files_text["FeedScreen"], files_text["MediaShape"], files_text["CircleX402Bridge"],
            files_text["AppStoreConnectBridge"])
        shape_count = len(shape_result[0]) if shape_result else 0
        print(f"✓ demo guard: {len(DEMO_FACING_FUNCS)} functions Release-reachable, "
              "no network verbs, no ungated per-view reads, no source collisions, "
              f"{len(seat_names or [])} catalog seats real and seeded, "
              f"{shape_count} feed shapes covered")
        sys.exit(0)
    else:
        print(f"✗ demo guard: {len(failures)} check(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
