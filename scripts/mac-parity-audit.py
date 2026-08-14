#!/usr/bin/env python3
"""Mac parity audit — the drift a Catalyst COMPILE cannot see (2026-08-12).

`verify.sh`'s step 1b proves the Mac still BUILDS. It says nothing about
whether the Mac still WORKS, and the three registries below are exactly where
that gap lives: a feature lands, Catalyst compiles it perfectly, and the Mac
ships with a screen nothing ever opens, a keyboard shortcut pointing at the
wrong room, or an entitlement that fails the archive weeks later at ship time.

Each check is derived from a registry IN THE SOURCE, never a hand-copied list,
so a new screen / entitlement / shortcut is covered the day it lands. That is
the whole point: the question this answers is "do I have to flag new features
for Mac parity", and the answer should be no.

Three checks, and deliberately only three. A lint that cries wolf gets turned
off within a week, so each one is a mechanical fact with no judgement in it.

    1. SWEPT SCREENS. Every `case "<host>"` in `RootShell.route(_:)` is a
       screen a deep link can reach, and therefore one both screen sweeps can
       reach headlessly. A host neither sweep opens is a screen no automated
       pass has ever LOOKED at on either platform.

    2. ENTITLEMENT DECISIONS. Every key in a target's iOS entitlements must
       have a DECISION in its Catalyst sibling — present, or listed here as
       deliberately iOS-only with a reason. Not "must match": HealthKit,
       HomeKit and FinanceKit are unavailable on macOS by Apple's own
       declaration, so demanding equality would be demanding a lie. The
       failure this catches is the silent one — a new capability added to iOS
       alone, which nothing notices until a signed Catalyst archive fails.

    3. THE DIGIT SHORTCUTS. ⌘1–⌘9 must stay positional against what you can
       SEE (`chipOrder`, the folded list) and must resolve a folded category
       label before writing `FeedFilter.source`. Writing the label raw puts a
       category name where no predicate matches it: the room is empty forever
       while the chip lights up as if it worked.

Static, self-tested, no build, no network, no simulator. Named `*-audit.py` so
`verify-mac.sh`'s discovery loop wires it in with no line of its own.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ROUTER = ROOT / "Casberi/Casberi/Shell/RootShell.swift"
COMMANDS = ROOT / "Casberi/Casberi/CasberiApp.swift"
SWEEPERS = [ROOT / "scripts/verify.sh", ROOT / "scripts/verify-mac.sh"]

# Entitlement pairs: (iOS file, Catalyst file). Discovered rather than listed —
# any `X.entitlements` with an `X-Catalyst.entitlements` beside it is a pair.
ENTITLEMENT_DIRS = [
    ROOT / "Casberi/Casberi",
    ROOT / "Casberi/ShareExtension",
    ROOT / "Casberi/CasberiWidgets",
]

# A deep-link host the sweeps deliberately do NOT open. Each entry is a
# conscious "no automated screenshot of this screen exists", with the reason.
# Adding one is a ruling; a NEW host must be swept or land here.
KNOWN_UNSWEPT = {
    "brief": (
        "the brief STREAMS for ~20-25s (CLAUDE.md: a screenshot taken early "
        "shows skeleton rows and unloaded thumbnails). A 4s sweep shot would "
        "photograph a loading state and certify it as the screen."
    ),
    "person": (
        "needs a real social handle already in the corpus — the card is "
        "`casberi://person/<Source>/<handle>`, and a handle no bridge has "
        "landed opens nothing. Covered by `-deeplink` by hand instead."
    ),
    "thing": (
        "needs a real thing: a UUID changes every install and "
        "`casberi://thing/latest` needs a seeded corpus the sweep does not "
        "build. `-openThing \"<title prefix>\"` is the sheet's headless door."
    ),
    "ask": (
        "`brief`'s reason, twice over (prd §382, 2026-08-14). It opens the "
        "composer onto a STREAMING answer, so a 4s sweep shot photographs a "
        "skeleton and certifies it as the screen — and it needs a `?q=` that "
        "actually retrieves, which the sweep's empty corpus cannot supply "
        "(bare `casberi://ask` returns early by design). `-answerProbe` / "
        "`-uiAnswerProbe` are its headless doors, and they read the document "
        "rather than photograph it."
    ),
}

# An iOS entitlement with no Catalyst counterpart, by Apple's own platform
# availability. Each is a conscious "the Mac cannot have this", not a gap.
KNOWN_IOS_ONLY = {
    "com.apple.developer.healthkit":
        "HealthKit does not exist on macOS; the Strava seat rides it, so that "
        "seat is iOS-only by construction.",
    "com.apple.developer.homekit":
        "HomeKit does not exist on macOS.",
    "com.apple.developer.financekit":
        "FinanceKit is `@available(macOS, unavailable)` — and shipping it in "
        "the Catalyst entitlements FAILS a signed archive, because the Mac "
        "profile does not carry the capability (guarded in "
        "applewallet-selftest.sh too, from the entitlement's own side).",
}


def strip_comments(text):
    """Swift source minus comments.

    Every negative guard here reads this rather than raw source: these files
    DOCUMENT the rules they follow, quoting the very spellings that must not
    appear, so a guard grepping raw source fires on the prose explaining it.
    Earned three times in this repo (Obsidian, Cursor, on-device).
    """
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def route_groups(source):
    """Deep-link hosts from `route(_:)`'s own switch — the screen registry.

    Returns one GROUP per `case` line, not one entry per spelling, because
    several hosts on one case are ALIASES FOR ONE SCREEN — `case "account",
    "apps":` is the catalog reached by its old name and its new one. Counting
    spellings instead of screens demands a second screenshot of a screen
    already swept, which is how a lint starts crying wolf: the first cut of
    this check did exactly that and reported `casberi://apps` unswept on both
    platforms while both sweeps were opening it as `casberi://account`.
    """
    body = strip_comments(source)
    start = body.find("private func route(")
    if start == -1:
        return []
    seg = body[start:]
    groups = []
    for match in re.finditer(r'^\s*case\s+((?:"[^"]+"\s*,?\s*)+):', seg, re.M):
        groups.append(re.findall(r'"([^"]+)"', match.group(1)))
    return groups


def route_hosts(source):
    """Flat host list — the parse, without the alias grouping."""
    return [h for group in route_groups(source) for h in group]


def check_swept(findings):
    if not ROUTER.exists():
        findings.append("%s is missing — the screen registry cannot be read" % ROUTER.name)
        return
    groups = route_groups(ROUTER.read_text())
    if not groups:
        findings.append(
            "no deep-link hosts parsed out of RootShell.route(_:) — the check "
            "is broken, not the code (it would pass vacuously)")
        return
    for script in SWEEPERS:
        if not script.exists():
            findings.append("%s is missing" % script.name)
            continue
        text = script.read_text()
        for group in groups:
            # Exempt if ANY spelling is exempt — one screen, one ruling.
            if any(h in KNOWN_UNSWEPT for h in group):
                continue
            # Covered if ANY alias is swept: they are one screen.
            if any(("casberi://" + h) in text for h in group):
                continue
            findings.append(
                "deep link %s is a screen %s never opens — add it to that "
                "script's screen sweep, or to KNOWN_UNSWEPT with the reason "
                "no screenshot of it exists"
                % (" / ".join("`casberi://" + h + "`" for h in group),
                   script.name))


def entitlement_keys(path):
    return re.findall(r"<key>([^<]+)</key>", path.read_text())


def check_entitlements(findings):
    pairs = 0
    for directory in ENTITLEMENT_DIRS:
        if not directory.exists():
            continue
        for ios in sorted(directory.glob("*.entitlements")):
            if ios.name.endswith("-Catalyst.entitlements"):
                continue
            catalyst = ios.with_name(ios.stem + "-Catalyst.entitlements")
            if not catalyst.exists():
                findings.append(
                    "%s has no Catalyst sibling — the Mac target's "
                    "entitlements are undecided" % ios.name)
                continue
            pairs += 1
            mac_keys = set(entitlement_keys(catalyst))
            for key in entitlement_keys(ios):
                if key in mac_keys or key in KNOWN_IOS_ONLY:
                    continue
                findings.append(
                    "`%s` is in %s but has no decision in %s — add it to the "
                    "Catalyst entitlements, or to KNOWN_IOS_ONLY with the "
                    "reason the Mac cannot have it. An undecided capability "
                    "does not fail here; it fails a signed archive at ship "
                    "time." % (key, ios.name, catalyst.name))
    if pairs == 0:
        findings.append(
            "no entitlement pairs found — the check is broken, not the code")


def check_digit_shortcuts(findings):
    if not COMMANDS.exists():
        findings.append("%s is missing" % COMMANDS.name)
        return
    body = strip_comments(COMMANDS.read_text())
    # The ⌘-digit run: a ForEach over 1...9 carrying a .command digit shortcut.
    block = re.search(
        r"ForEach\(1\.\.\.9.*?keyboardShortcut\(KeyEquivalent.*?modifiers:\s*\.command\)",
        body, re.S)
    if not block:
        findings.append(
            "the ⌘1–⌘9 command run was not found in CasberiApp.swift — the "
            "check is broken, or the shortcut grammar changed")
        return
    text = block.group(0)
    if "chipOrder" not in text:
        findings.append(
            "the ⌘1–⌘9 run no longer reads `chipOrder` — it must stay "
            "positional against what the strip SHOWS (folded). Fed "
            "`sourceOrder` it counts seats nobody can see, so ⌘3 stops "
            "meaning the third chip you can point at.")
    if "CategoryFold.isCategory" not in text:
        findings.append(
            "the ⌘1–⌘9 run no longer resolves a folded category before "
            "writing `FeedFilter.source` — a chip LABEL is not a source, so "
            "the raw write lands a category name where no predicate matches "
            "it: the room is empty forever and the chip lights up as if it "
            "worked.")


CHECKS = [
    ("swept screens", check_swept),
    ("entitlement decisions", check_entitlements),
    ("digit shortcuts", check_digit_shortcuts),
]


def run():
    findings = []
    for _, fn in CHECKS:
        fn(findings)
    return findings


# ── Self-test ──────────────────────────────────────────────────────────────
# Required, not decoration: a check that cannot demonstrate it catches
# anything certifies nothing. Each fixture is a real drift shape.

FIXTURE_ROUTER = '''
    private func route(_ url: URL) {
        switch url.host() {
        case "home":    sceneState.filter.source = "All"
        case "feed":    sceneState.filter.source = "All"
        case "account", "apps": sceneState.route.present(.apps)
        // case "ghost": a commented-out route is not a screen
        case "settings": sceneState.route.present(.settings)
        default: break
        }
    }
'''

FIXTURE_COMMANDS_GOOD = '''
            CommandGroup(after: .toolbar) {
                ForEach(1...9, id: \\.self) { n in
                    let order = focusedChrome?.chipOrder ?? ["All"]
                    Button("Switch") {
                        if CategoryFold.isCategory(label) { resolve() }
                        else { focusedScene?.filter.source = label }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\\(n)")), modifiers: .command)
                }
            }
'''


def selftest():
    ok = True

    def case(desc, got, want):
        nonlocal ok
        good = got == want
        ok = good and ok
        print("  %-4s %s" % ("ok" if good else "FAIL", desc))
        if not good:
            print("       expected %s, got %s" % (want, got))

    # 1. Route parsing: multi-case lines split, comments ignored.
    hosts = route_hosts(FIXTURE_ROUTER)
    case("parses every deep-link host, multi-case lines included",
         hosts, ["home", "feed", "account", "apps", "settings"])
    case("a COMMENTED-OUT case is not counted as a screen",
         "ghost" in hosts, False)

    # 2. Alias grouping: several hosts on one `case` are ONE screen.
    case("hosts on one `case` line group as a single screen",
         route_groups(FIXTURE_ROUTER)[2], ["account", "apps"])

    # 3. An unswept screen is a finding; an alias already swept is NOT
    #    (the first cut's false positive, pinned so it cannot come back).
    f = []
    swept = ('sweep home "casberi://home"\nsweep feed "casberi://feed"\n'
             'sweep apps "casberi://account"\n')
    for group in route_groups(FIXTURE_ROUTER) + [["newscreen"]]:
        if any(h in KNOWN_UNSWEPT for h in group):
            continue
        if any(("casberi://" + h) in swept for h in group):
            continue
        f.append("/".join(group))
    case("a NEW deep-linked screen no sweep opens is a finding",
         f, ["settings", "newscreen"])
    case("`apps` is NOT re-reported when swept as its alias `account`",
         any("apps" in x for x in f), False)

    # 3. Entitlements: an undecided iOS key is a finding, a KNOWN_IOS_ONLY isn't.
    ios_keys = ["aps-environment", "com.apple.developer.healthkit",
                "com.apple.developer.newthing"]
    mac_keys = {"aps-environment"}
    missing = [k for k in ios_keys
               if k not in mac_keys and k not in KNOWN_IOS_ONLY]
    case("a new iOS entitlement with no Catalyst decision is a finding",
         missing, ["com.apple.developer.newthing"])
    case("HealthKit is NOT a finding (macOS cannot have it)",
         "com.apple.developer.healthkit" in missing, False)

    # 4. Digit shortcuts: the clean fixture passes.
    f = []
    saved = globals()["COMMANDS"]
    try:
        tmp = ROOT / "scripts" / ".mac-parity-fixture.swift"
        tmp.write_text(FIXTURE_COMMANDS_GOOD)
        globals()["COMMANDS"] = tmp
        check_digit_shortcuts(f)
        case("a correct ⌘1–⌘9 run passes", f, [])

        # Mutation A: reads sourceOrder instead of chipOrder.
        f = []
        tmp.write_text(FIXTURE_COMMANDS_GOOD.replace("chipOrder", "sourceOrder"))
        check_digit_shortcuts(f)
        case("flags ⌘1–⌘9 fed the UNFOLDED order", len(f), 1)

        # Mutation B: writes the label raw, no fold resolution.
        f = []
        tmp.write_text(FIXTURE_COMMANDS_GOOD.replace("CategoryFold.isCategory", "alwaysTrue"))
        check_digit_shortcuts(f)
        case("flags a raw label written into FeedFilter.source", len(f), 1)

        # Mutation C: the run is gone entirely — must not pass vacuously.
        f = []
        tmp.write_text("// no commands here\n")
        check_digit_shortcuts(f)
        case("does NOT pass vacuously when the run is missing", len(f), 1)
    finally:
        globals()["COMMANDS"] = saved
        tmp.unlink(missing_ok=True)

    print("\nself-test %s" % ("passed" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    if "--self-test" in sys.argv:
        return selftest()
    findings = run()
    if findings:
        print("✗ Mac parity findings:")
        for f in findings:
            print("  " + f)
        print("\nA Catalyst COMPILE proves the Mac still builds. These are the "
              "things it cannot see: a screen no pass opens, a capability that "
              "fails the archive weeks later, a shortcut aimed at the wrong "
              "room. Each renders perfectly and is wrong.")
        return 1
    print("✓ mac parity (%d checks)" % len(CHECKS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
