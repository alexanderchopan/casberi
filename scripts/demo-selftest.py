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
}

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
        check(f'E · seatTable "{name}" has a seeded row',
              f'"{name}"' in rest, True)


def run_checks(files_text):
    before = len(failures)
    check_a_release_reachable(files_text)
    check_b_reaches_nothing(files_text)
    check_c_no_source_collision(files_text)
    check_d_seat_names_are_real(files_text)
    check_e_seat_names_have_rows(files_text)
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

    # And the clean tree must pass all three, so the fixtures above are
    # proven against a REAL failure, not a checker that always fails.
    global SILENT
    clean = {k: read(v) for k, v in DEMO_FILES.items()}
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
        print(f"✓ demo guard: {len(DEMO_FACING_FUNCS)} functions Release-reachable, "
              "no network verbs, no source collisions, "
              f"{len(seat_names or [])} catalog seats real and seeded")
        sys.exit(0)
    else:
        print(f"✗ demo guard: {len(failures)} check(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
