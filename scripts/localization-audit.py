#!/usr/bin/env python3
"""Casberi localization audit (2026-08-04) — the class that hid ~89% of the
app in English behind five shipped, working localizations.

WHY THIS EXISTS. A localization sweep on 2026-08-04 found the app ships
en/es/ja/ko/zh-Hans with a real in-app language picker (`LanguageStore`), but
the string catalog had drifted 1,275 keys behind source, and 194 PREVIOUSLY
TRANSLATED strings had regressed into bare Swift literals — the translation
still sat in `Localizable.xcstrings`, unreachable, because the call site had
been rewritten to a plain `"..."` (often during an unrelated refactor) instead
of `String(localized:)`/`Text(LocalizedStringKey(...))`. This renders
PERFECTLY in every language: English, because that's what a bare literal always
shows. Nothing in a build or a screen sweep catches it — the same invisible-
failure shape every other audit in this repo exists for.

Two more findings from the same sweep, mechanical for the same reason:
`InfoPlist.xcstrings`/`AppShortcuts.xcstrings` didn't exist at all (12
permission prompts and 4 Siri phrases were English-only in every language),
and 44 sites hand-composed an English-only plural (`count == 1 ? "" : "s"`),
which for a non-English reader either silently never appears (the ternary runs
in Swift, so the catalog only ever sees whichever branch fired) or — worse,
confirmed live in the catalog — glues a bare Latin "s" onto an already-
translated sentence via a stray %@ argument.

THREE CHECKS, all static, no build.

  1. UNREACHABLE TRANSLATION. A catalog key that is `extractionState: stale`
     (Xcode's own "not found in source this run" marker) AND still has a real
     translation (an `es` localization exists) AND appears as a bare Swift
     string literal somewhere in source, outside a `String(localized:)`,
     `Text(`, `LocalizedStringKey(`, `LocalizedStringResource(`, or
     `IntentDialog(` call. The translation is unreachable and the fix is
     always the same: wrap the call site.

  2. INFOPLIST / APPSHORTCUTS CATALOGS EXIST. The Casberi target must carry
     `InfoPlist.xcstrings` (permission usage descriptions) and
     `AppShortcuts.xcstrings` (Siri phrase templates) alongside
     `Localizable.xcstrings`, non-empty.

  3. HAND-COMPOSED ENGLISH PLURAL. `<expr> == 1 ? "" : "s"` (or the inverted
     `== 1 ? "s" : ""`) in application Swift source. English-only by
     construction — no other language pluralizes by appending "s" — and the
     fix is a String Catalog plural variation (`variations.plural`), not
     another ternary. `KNOWN_EXEMPT` covers NSLog-only probe/diagnostic
     output, which is developer text, not shipped UI.

WHAT IT CANNOT SEE: whether a translation is any GOOD (that's a human
review), whether a NEW string was ever added to the catalog at all (a
brand-new key with no translation renders as English too, gracefully, and
is a product decision — how much to translate — not a regression this audit
polices), and anything inside GenUI's DSL strings once they're built into a
larger interpolated payload (those are wrapped in `String(localized:)` at the
interpolation site, same as everywhere else, and check 1 sees them the same
way).

Self-test runs FIRST and is not decoration: a check that cannot fail proves
nothing, so this demonstrates it catches each shape and passes the clean ones
before it certifies the tree.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_SOURCES = [
    "Casberi/Casberi/Design",
    "Casberi/Casberi/GenUI",
    "Casberi/Casberi/Model",
    "Casberi/Casberi/Screens",
    "Casberi/Casberi/Shell",
]
CATALOGS = [
    "Casberi/Casberi/Localizable.xcstrings",
    "Casberi/CasberiWidgets/Localizable.xcstrings",
    "Casberi/ShareExtension/Localizable.xcstrings",
]
INFOPLIST_CATALOG = ROOT / "Casberi/Casberi/InfoPlist.xcstrings"
APPSHORTCUTS_CATALOG = ROOT / "Casberi/Casberi/AppShortcuts.xcstrings"

# --- Exemptions --------------------------------------------------------------
# Each entry is a ruling, not a snooze: developer-only text (NSLog probe
# output, MCP tool responses meant for an LLM client) that is never shown in
# the app's own UI, so English-only plural composition there costs nothing a
# reader of the app ever sees.
KNOWN_EXEMPT = {
    "ProbeHooks.swift",       # -*Probe NSLog output — developer diagnostics only
    "GnosisPayBridge.swift",  # accountSummary() is the probe's status line
    "RailgunBridge.swift",    # accountSummary() is the probe's status line
    "SafeBridge.swift",       # probe() is -safeProbe's NSLog output
    "MCPTools.swift",         # MCP tool text is consumed by an LLM client, not the app UI
}

LOCALIZED_CALL_RE = re.compile(
    r"(?:String\(localized:|Text\(|LocalizedStringKey\(|LocalizedStringResource\(|IntentDialog\()"
)
PLURAL_TERNARY_RE = re.compile(
    r'==\s*1\s*\?\s*""\s*:\s*"s"|==\s*1\s*\?\s*"s"\s*:\s*""'
)


def strip_comments(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def swift_files():
    for root in APP_SOURCES:
        for path in sorted((ROOT / root).rglob("*.swift")):
            yield path


# --- Check 1: unreachable translation ----------------------------------------

def stale_translated_keys(catalog_path: Path):
    """Stale keys that still carry a real `es` translation — candidates for
    the regression class. `manual`-marked keys are excluded: that state means
    a human already confirmed the key is reached through a runtime-resolved
    string (GenUI's DSL, a `placeholder:`/`proof:` property) rather than a
    literal Xcode's static scanner can see, which is exactly NOT this bug."""
    data = json.loads(catalog_path.read_text())
    out = []
    for key, entry in data.get("strings", {}).items():
        if entry.get("extractionState") != "stale":
            continue
        if not key or len(key) < 3:
            continue
        es = entry.get("localizations", {}).get("es")
        if not es:
            continue
        out.append(key)
    return out


def literal_call_sites(key: str, sources_text):
    """Every (path, line_no, line_text) where `key` appears as a bare Swift
    string literal, i.e. NOT already passed through a localizing call on that
    same line. One line of context is enough: every real call site in this
    codebase wraps the literal directly (`String(localized: "...")`), so a
    localizing call token anywhere on the line clears it."""
    lit = '"' + key.replace("\\", "\\\\").replace('"', '\\"') + '"'
    hits = []
    for path, lines in sources_text:
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            if lit in line and not LOCALIZED_CALL_RE.search(line):
                hits.append((path, i, stripped[:110]))
    return hits


def check_unreachable_translations(sources_text):
    findings = []
    for rel in CATALOGS:
        catalog_path = ROOT / rel
        if not catalog_path.exists():
            continue
        for key in stale_translated_keys(catalog_path):
            for path, line, text in literal_call_sites(key, sources_text):
                findings.append(
                    (str(path.relative_to(ROOT)), line,
                     "translated key %r is unreachable — literal, not wrapped: %s"
                     % (key[:60], text))
                )
    return findings


# --- Check 2: InfoPlist/AppShortcuts catalogs exist --------------------------

def check_plist_catalogs():
    findings = []
    for path, name in [(INFOPLIST_CATALOG, "InfoPlist.xcstrings"),
                        (APPSHORTCUTS_CATALOG, "AppShortcuts.xcstrings")]:
        if not path.exists():
            findings.append((str(path.relative_to(ROOT)), 0,
                              "%s is missing — permission prompts/Siri phrases ship English-only" % name))
            continue
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            findings.append((str(path.relative_to(ROOT)), 0, "invalid JSON: %s" % e))
            continue
        if not data.get("strings"):
            findings.append((str(path.relative_to(ROOT)), 0, "%s has no entries" % name))
    return findings


# --- Check 3: hand-composed English plural -----------------------------------

def check_plural_ternaries(sources_text):
    findings = []
    for path, lines in sources_text:
        if path.name in KNOWN_EXEMPT:
            continue
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            if PLURAL_TERNARY_RE.search(line):
                try:
                    rel = str(path.relative_to(ROOT))
                except ValueError:
                    rel = str(path)
                findings.append(
                    (rel, i, "hand-composed English-only plural: %s" % stripped[:110])
                )
    return findings


def run_checks(sources_text):
    findings = []
    findings += check_unreachable_translations(sources_text)
    findings += check_plist_catalogs()
    findings += check_plural_ternaries(sources_text)
    return findings


# --- Self-test ----------------------------------------------------------------

def self_test() -> bool:
    ok = True
    print("Self-test")

    # Check 1: unreachable translation.
    tmp_catalog = json.dumps({
        "sourceLanguage": "en",
        "strings": {
            "Hello there": {
                "extractionState": "stale",
                "localizations": {"es": {"stringUnit": {"state": "translated", "value": "Hola"}}},
            },
            "Untranslated stale": {
                "extractionState": "stale",
                "localizations": {},
            },
            "Reachable fine": {
                "extractionState": "manual",
                "localizations": {"es": {"stringUnit": {"state": "translated", "value": "Bien"}}},
            },
        },
    })
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        cat = tdp / "Localizable.xcstrings"
        cat.write_text(tmp_catalog)

        cases = [
            ("a stale translated key reached as a bare literal is caught",
             'let x = "Hello there"\n', 1),
            ("the same key wrapped in String(localized:) passes",
             'let x = String(localized: "Hello there")\n', 0),
            ("the same key wrapped in Text( passes",
             'Text("Hello there")\n', 0),
            ("a stale key with NO translation is not flagged (nothing to reach)",
             'let x = "Untranslated stale"\n', 0),
            ("a non-stale (manual) key is not flagged even if literal",
             'let x = "Reachable fine"\n', 0),
        ]
        for name, src, expected in cases:
            sources_text = [(tdp / "Fixture.swift", src.split("\n"))]
            keys = stale_translated_keys(cat)
            found = 0
            for key in keys:
                found += len(literal_call_sites(key, sources_text))
            if found == expected:
                print("  ✓ %s" % name)
            else:
                print("  ✗ %s (expected %d, got %d)" % (name, expected, found))
                ok = False

    # Check 2: plist catalogs.
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        missing = tdp / "Nope.xcstrings"
        empty = tdp / "Empty.xcstrings"
        empty.write_text(json.dumps({"sourceLanguage": "en", "strings": {}}))
        good = tdp / "Good.xcstrings"
        good.write_text(json.dumps({"sourceLanguage": "en", "strings": {"A": {}}}))

        def check_one(path, name):
            if not path.exists():
                return 1
            data = json.loads(path.read_text())
            return 0 if data.get("strings") else 1

        cases2 = [
            ("a missing catalog is caught", missing, 1),
            ("an empty catalog is caught", empty, 1),
            ("a populated catalog passes", good, 0),
        ]
        for name, path, expected in cases2:
            got = check_one(path, path.name)
            if got == expected:
                print("  ✓ %s" % name)
            else:
                print("  ✗ %s (expected %d, got %d)" % (name, expected, got))
                ok = False

    # Check 3: plural ternaries.
    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        cases3 = [
            ("count == 1 ? \"\" : \"s\" is caught",
             'let l = "\\(n) thing\\(n == 1 ? "" : "s")"\n', "Real.swift", 1),
            ("the inverted form n == 1 ? \"s\" : \"\" is caught",
             'l += " \\(n) need\\(n == 1 ? "s" : "") attention."\n', "Real.swift", 1),
            ("a proper String(localized:) call has no ternary to catch",
             'let l = String(localized: "\\(n) thing")\n', "Real.swift", 0),
            ("the exact same bad line in an exempt probe file passes",
             'let l = "\\(n) thing\\(n == 1 ? "" : "s")"\n', "ProbeHooks.swift", 0),
        ]
        for name, src, fname, expected in cases3:
            f = tdp / fname
            f.write_text(src)
            sources_text = [(f, src.split("\n"))]
            found = len(check_plural_ternaries(sources_text))
            if found == expected:
                print("  ✓ %s" % name)
            else:
                print("  ✗ %s (expected %d, got %d)" % (name, expected, found))
                ok = False

    return ok


def main() -> int:
    if "--self-test" in sys.argv:
        return 0 if self_test() else 1

    if not self_test():
        print("\nlocalization-audit: ✗ self-test failed — the audit itself is broken")
        return 1

    sources_text = [(p, p.read_text().split("\n")) for p in swift_files()]

    findings = run_checks(sources_text)

    print("")
    if not findings:
        print("localization-audit: OK — no unreachable translations, "
              "InfoPlist/AppShortcuts catalogs present, no hand-composed plurals.")
        return 0

    print("localization-audit: %d finding(s)\n" % len(findings))
    for rel, line, why in findings:
        print("  %s:%d  %s" % (rel, line, why))
    print("\nFix the call site (wrap in String(localized:)/Text(...)), add the "
          "missing catalog, or use a String Catalog plural variation instead "
          "of a ternary. A developer-only probe/diagnostic file can be added "
          "to KNOWN_EXEMPT with a reason.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
