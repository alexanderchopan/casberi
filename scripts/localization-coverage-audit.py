#!/usr/bin/env python3
"""Casberi localization COVERAGE audit (2026-08-13) — the drift that hid nine
days of the app in English behind five shipped, working localizations.

WHY THIS EXISTS, and why it is NOT `localization-audit.py`. That audit catches a
translation that EXISTS and has become UNREACHABLE (a call site rewritten to a
bare Swift literal). It says so in its own header, and it is right to: it
deliberately does not police whether a NEW string ever reached the catalog at
all, because an unlocalized key renders as English *gracefully* and "how much to
translate" is a product decision.

That blind spot became the bug. On 2026-08-13 the catalog was **767 keys behind
source** — last touched 2026-08-04, with **248 commits landed since**. Every
user-facing string from every feature shipped in those nine days (MoneyReceipt
§363, the wallet rooms §349, ASCRoom §324, Apple Wallet §313/§317, X402, Cursor,
Railgun, Safe) was English-only in es/ja/ko/zh-Hans. Nothing caught it:
`xcodebuild` is happy, the screen sweep is happy, `localization-audit.py` printed
OK, and on an English device the app is *perfect*. The same invisible-failure
shape every other audit in this repo exists for.

The mechanism is worth knowing, because it is not carelessness. **Xcode's IDE
syncs a String Catalog on build; `xcodebuild` from the CLI does not.** It emits
`.stringsdata` into DerivedData and never writes back. Every session here builds
from the CLI, so the catalog only advances when somebody runs
`xcstringstool sync` by hand — which is exactly the kind of remembered step this
codebase's history says gets forgotten.

TWO CHECKS.

  1. COVERAGE (static, no build, always runs). Every key in every shipped
     catalog carries a translation for every language `LanguageStore.supported`
     declares, minus the source language. The language list is PARSED OUT of
     `Design/LanguageStore.swift` at run time rather than hardcoded here, so
     a sixth language added to the in-app picker demands catalog coverage the
     day it lands — the registry is the source of truth, `catalog-sync.sh`'s
     shape. The source language is deliberately NOT checked: a key with no `en`
     entry falls back to the key itself, which for `Localizable`/`AppShortcuts`
     IS the English text and is correct. (`InfoPlist.xcstrings` INVERTS that and
     is `infoplist-strings-audit.py`'s job — see its header. Two audits, one
     boundary, no overlap.)

  2. DRIFT (needs `--stringsdata`, so it runs in the verify passes and not in a
     bare discovery run). Every key the COMPILER extracted for a target exists
     in that target's catalog. This is the check that would have caught the 767.
     It reads the `.stringsdata` the build already emitted, so it is EXACT —
     no regex over Swift, no guessing at format specifiers. That matters: the
     hand-rolled regex version of this check reported 57 false positives on a
     clean tree (a literal `%` in source is `%%` in the catalog key, a nested
     string literal ends the match early, `\\u{201c}` is not decoded). A lint
     that cries wolf gets turned off within a week, so the compiler's own
     extraction is the only honest input.

     PASS ONE CONFIGURATION'S DIRECTORY, never a whole `Intermediates.noindex`.
     A long-lived derivedData accumulates stringsdata from every configuration
     ever built into it and never recompiles them again, so the root of a real
     `CasberiDD` produced 102 false findings: a months-old
     `Release-iphonesimulator` and a stray `Debug-maccatalyst` sat beside the
     fresh `Debug-iphonesimulator`, still holding strings deleted long ago.
     Filtering on "the source file still exists" does NOT rescue it — 86 of
     those 102 came from files still in the tree that had merely been edited
     since. Within one config dir the data is exact, because an incremental
     build rewrites the stringsdata of every file it recompiles.

     It is ONE-DIRECTIONAL on purpose: stringsdata ⊆ catalog. The reverse
     (a catalog key with no stringsdata) is NOT a finding, because a single
     platform's build cannot see the whole app — 22 files carry a
     `#if targetEnvironment(macCatalyst)` branch no iOS build ever compiles, so
     flagging that direction would report every Mac-only string as dead on
     every iOS pass. Pass BOTH platforms' dirs to widen what check 2 can see;
     passing one is not wrong, only narrower, and the summary says which.

WHAT IT CANNOT SEE: whether a translation is any GOOD (that is a human review —
everything here is machine-translated and marked `needs_review`), whether the
right STRING was localized at all (a bare literal is `localization-audit.py`'s
check 1), and, without `--stringsdata`, anything about drift.

KNOWN_UNTRANSLATED is the escape hatch: an entry is a conscious "this key ships
in English in every language", carrying the reason. Empty by design.

Self-test runs FIRST and is not decoration: a check that cannot fail proves
nothing, so this demonstrates it catches each shape and passes the clean ones
before it certifies the tree.
"""

import json
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGUAGE_STORE = ROOT / "Casberi/Casberi/Design/LanguageStore.swift"

# Every shipped catalog. Check 1 covers all of them; check 2 only those a
# build target emits stringsdata for (see TARGET_CATALOG).
CATALOGS = [
    "Casberi/Casberi/Localizable.xcstrings",
    "Casberi/Casberi/InfoPlist.xcstrings",
    "Casberi/Casberi/AppShortcuts.xcstrings",
    "Casberi/CasberiWidgets/Localizable.xcstrings",
    "Casberi/ShareExtension/Localizable.xcstrings",
]

# Which catalog a build target's extracted strings belong to, keyed by
# (target, TABLE). The table half is load-bearing and was paid for on this
# script's first real run: the compiler emits `InfoPlist` and `AppShortcuts`
# as their own tables under the SAME `Casberi` target, so a target-only map
# routed all 18 of their keys at the Localizable catalog and reported perfectly
# correct entries — `NSCameraUsageDescription`, `CFBundleDisplayName` — as
# missing. Route by table, or the check cries wolf on a clean tree.
TARGET_CATALOG = {
    ("Casberi", "Localizable"): "Casberi/Casberi/Localizable.xcstrings",
    ("Casberi", "InfoPlist"): "Casberi/Casberi/InfoPlist.xcstrings",
    ("Casberi", "AppShortcuts"): "Casberi/Casberi/AppShortcuts.xcstrings",
    ("CasberiWidgets", "Localizable"): "Casberi/CasberiWidgets/Localizable.xcstrings",
    ("ShareExtension", "Localizable"): "Casberi/ShareExtension/Localizable.xcstrings",
}

# A conscious "this key ships in English in every language", with the reason.
KNOWN_UNTRANSLATED: dict[str, str] = {}


def shipped_languages(source: Path) -> list[str]:
    """The codes `LanguageStore.supported` declares, in declaration order.

    Parsed rather than hardcoded so the in-app picker and the catalogs cannot
    disagree. Scoped to the `supported` array so an unrelated `Language(code:)`
    elsewhere in the file can't widen it.
    """
    text = source.read_text(errors="replace")
    m = re.search(r"supported:\s*\[Language\]\s*=\s*\[(.*?)\n\s*\]", text, re.S)
    if not m:
        raise SystemExit(f"localization-coverage: can't find LanguageStore.supported in {source}")
    return re.findall(r'Language\(\s*code:\s*"([^"]+)"', m.group(1))


def load_catalog(path: Path) -> tuple[dict, str]:
    d = json.loads(path.read_text())
    return d.get("strings", {}), d.get("sourceLanguage", "en")


def check_coverage(root: Path, langs: list[str], catalogs: list[str]) -> list[str]:
    """CHECK 1 — every key carries every shipped non-source language."""
    findings: list[str] = []
    for rel in catalogs:
        path = root / rel
        if not path.exists():
            findings.append(f"{rel}: catalog is missing entirely")
            continue
        strings, source_lang = load_catalog(path)
        if not strings:
            findings.append(f"{rel}: catalog is empty")
            continue
        wanted = [l for l in langs if l != source_lang]
        gaps: dict[str, list[str]] = {}
        for key, entry in strings.items():
            if key in KNOWN_UNTRANSLATED:
                continue
            have = entry.get("localizations", {})
            missing = [l for l in wanted if l not in have]
            if missing:
                gaps.setdefault(",".join(missing), []).append(key)
        for missing, keys in sorted(gaps.items()):
            findings.append(
                f"{rel}: {len(keys)} key(s) missing [{missing}] — e.g. {keys[0]!r}"
            )
    return findings


def extracted_keys(stringsdata_dirs: list[Path]) -> dict[tuple[str, str], set[str]]:
    """Every key the compiler extracted, per (target, table), from .stringsdata."""
    per_table: dict[tuple[str, str], set[str]] = {}
    for d in stringsdata_dirs:
        for f in d.rglob("*.stringsdata"):
            target = next(
                (p.name[: -len(".build")] for p in f.parents if p.name.endswith(".build")),
                None,
            )
            if target is None:
                continue
            try:
                data = json.loads(f.read_text())
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue  # a stale or half-written file is not a finding
            for table, entries in data.get("tables", {}).items():
                if (target, table) not in TARGET_CATALOG:
                    continue
                for e in entries:
                    key = e.get("key")
                    if key:
                        per_table.setdefault((target, table), set()).add(key)
    return per_table


def check_drift(root: Path, per_table: dict[tuple[str, str], set[str]]) -> list[str]:
    """CHECK 2 — stringsdata ⊆ catalog. One-directional; see the header."""
    findings: list[str] = []
    for slot, keys in sorted(per_table.items()):
        rel = TARGET_CATALOG[slot]
        strings, _ = load_catalog(root / rel)
        missing = sorted(k for k in keys if k not in strings)
        if missing:
            findings.append(
                f"{rel}: {len(missing)} string(s) in source but NOT in the catalog "
                f"— e.g. {missing[0]!r}"
            )
            for k in missing[1:6]:
                findings.append(f"    also {k!r}")
            if len(missing) > 6:
                findings.append(f"    …and {len(missing) - 6} more")
    return findings


# ── self-test ───────────────────────────────────────────────────────────────
# Each case is a shape this must catch, or a clean one it must not flag.

def _write_catalog(path: Path, keys: dict, source="en"):
    path.parent.mkdir(parents=True, exist_ok=True)
    strings = {}
    for k, langs in keys.items():
        strings[k] = {"localizations": {l: {"stringUnit": {"state": "translated", "value": v}}
                                        for l, v in langs.items()}}
    path.write_text(json.dumps({"sourceLanguage": source, "strings": strings, "version": "1.0"}))


def _write_stringsdata(path: Path, keys: list[str], table: str = "Localizable"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "source": "x.swift",
        "tables": {table: [{"key": k, "comment": "", "location": {}} for k in keys]},
        "version": 1,
    }))


def self_test() -> int:
    print("Self-test")
    ok = True

    def check(label, cond):
        nonlocal ok
        print(f"  {'✓' if cond else '✗'} {label}")
        ok = ok and cond

    tmp = Path(tempfile.mkdtemp())
    try:
        # --- language parsing ------------------------------------------------
        ls = tmp / "LanguageStore.swift"
        ls.write_text('''
        static let supported: [Language] = [
            Language(code: "en",      endonym: "English", gloss: "English"),
            Language(code: "es",      endonym: "Español", gloss: "Spanish"),
            Language(code: "zh-Hans", endonym: "简体中文", gloss: "Chinese"),
        ]
        func other() { _ = Language(code: "de", endonym: "x", gloss: "y") }
        ''')
        langs = shipped_languages(ls)
        check("the shipped language list is parsed from LanguageStore", langs == ["en", "es", "zh-Hans"])
        check("a Language(code:) outside `supported` doesn't widen the list", "de" not in langs)

        check("the REAL LanguageStore still parses (drift guard)",
              set(shipped_languages(LANGUAGE_STORE)) >= {"en", "es", "ja", "ko", "zh-Hans"})

        # --- check 1: coverage ----------------------------------------------
        root = tmp / "clean"
        _write_catalog(root / "c.xcstrings", {"Hello": {"es": "Hola", "zh-Hans": "你好"}})
        check("a fully-translated catalog passes",
              check_coverage(root, langs, ["c.xcstrings"]) == [])

        root2 = tmp / "gap"
        _write_catalog(root2 / "c.xcstrings", {"Hello": {"es": "Hola"}})
        f = check_coverage(root2, langs, ["c.xcstrings"])
        check("a key missing a shipped language is caught",
              len(f) == 1 and "zh-Hans" in f[0])

        root3 = tmp / "srconly"
        _write_catalog(root3 / "c.xcstrings", {"Hello": {"es": "Hola", "zh-Hans": "你好"}})
        check("the SOURCE language is never demanded (a key falls back to itself)",
              check_coverage(root3, langs, ["c.xcstrings"]) == [])

        # a language added to the picker but absent from the catalog
        f = check_coverage(root, langs + ["fr"], ["c.xcstrings"])
        check("a language added to LanguageStore but absent from the catalog is caught",
              len(f) == 1 and "fr" in f[0])

        check("a missing catalog is caught",
              check_coverage(tmp / "nope", langs, ["c.xcstrings"]) != [])

        empty = tmp / "empty"
        (empty / "c.xcstrings").parent.mkdir(parents=True, exist_ok=True)
        (empty / "c.xcstrings").write_text('{"sourceLanguage":"en","strings":{},"version":"1.0"}')
        check("an empty catalog is caught", check_coverage(empty, langs, ["c.xcstrings"]) != [])

        # escape hatch
        KNOWN_UNTRANSLATED["Hello"] = "self-test"
        check("KNOWN_UNTRANSLATED exempts a key",
              check_coverage(root2, langs, ["c.xcstrings"]) == [])
        del KNOWN_UNTRANSLATED["Hello"]

        # --- check 2: drift --------------------------------------------------
        droot = tmp / "drift"
        _write_catalog(droot / TARGET_CATALOG[("Casberi", "Localizable")], {"Kept": {"es": "x"}})
        sd = tmp / "sd" / "Casberi.build" / "Objects-normal"
        _write_stringsdata(sd / "A.stringsdata", ["Kept"])
        per = extracted_keys([tmp / "sd"])
        check("keys are read out of the compiler's stringsdata",
              per.get(("Casberi", "Localizable")) == {"Kept"})
        check("a catalog covering every extracted key passes",
              check_drift(droot, per) == [])

        # The bug this script shipped with, on its own first real run: InfoPlist
        # and AppShortcuts are separate TABLES under the same target, and a
        # target-only route reported 18 correct entries as missing.
        _write_catalog(droot / TARGET_CATALOG[("Casberi", "InfoPlist")],
                       {"NSCameraUsageDescription": {"es": "x"}})
        _write_stringsdata(sd / "P.stringsdata", ["NSCameraUsageDescription"], table="InfoPlist")
        per = extracted_keys([tmp / "sd"])
        check("a non-Localizable table routes to its OWN catalog, not the target's Localizable",
              per.get(("Casberi", "InfoPlist")) == {"NSCameraUsageDescription"}
              and check_drift(droot, per) == [])

        _write_stringsdata(sd / "U.stringsdata", ["Whatever"], table="UnknownTable")
        check("a table with no catalog of its own is ignored",
              ("Casberi", "UnknownTable") not in extracted_keys([tmp / "sd"]))

        _write_stringsdata(sd / "B.stringsdata", ["Kept", "Brand new string"])
        per = extracted_keys([tmp / "sd"])
        f = check_drift(droot, per)
        check("a string in source but NOT in the catalog is caught (the 767)",
              any("Brand new string" in x for x in f))

        # one-directional: a catalog key with no stringsdata is NOT a finding
        _write_catalog(droot / TARGET_CATALOG[("Casberi", "Localizable")],
                       {"Kept": {"es": "x"}, "Mac only": {"es": "y"}, "Brand new string": {"es": "z"}})
        check("a catalog key with no stringsdata is NOT flagged (Catalyst-only strings)",
              check_drift(droot, extracted_keys([tmp / "sd"])) == [])

        # an unreadable stringsdata file is skipped, not a finding
        (sd / "bad.stringsdata").write_text("not json{")
        check("an unreadable stringsdata file is skipped, not reported as drift",
              check_drift(droot, extracted_keys([tmp / "sd"])) == [])

        # a target with no catalog mapping is ignored
        _write_stringsdata(tmp / "sd" / "Other.build" / "C.stringsdata", ["Whatever"])
        check("a build target with no catalog of its own is ignored",
              not any(t == "Other" for t, _ in extracted_keys([tmp / "sd"])))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    return 0 if ok else 1


def main() -> int:
    args = sys.argv[1:]
    if "--self-test" in args:
        return self_test()

    dirs: list[Path] = []
    i = 0
    while i < len(args):
        if args[i] == "--stringsdata":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                dirs.append(Path(args[i]))
                i += 1
        else:
            print(f"localization-coverage: unknown argument {args[i]!r}", file=sys.stderr)
            return 2

    langs = shipped_languages(LANGUAGE_STORE)
    findings = check_coverage(ROOT, langs, CATALOGS)

    usable = [d for d in dirs if d.exists()]
    if usable:
        per_table = extracted_keys(usable)
        findings += check_drift(ROOT, per_table)
        seen = ", ".join(f"{t}/{tbl}" for t, tbl in sorted(per_table)) or "none"
        scope = f"drift checked against {sum(len(v) for v in per_table.values())} extracted keys ({seen})"
    else:
        # Never let a skipped check read as a passed one.
        scope = ("drift NOT checked — no --stringsdata given, so this run proves "
                 "coverage only, not that the catalog is level with source")

    if findings:
        for f in findings:
            print(f"  {f}")
        print()
        print("localization-coverage: FAILED — the catalogs are behind source.")
        print("  Fix: build, then sync the catalog from the compiler's own extraction:")
        print("    xcrun xcstringstool sync <catalog> --skip-marking-strings-stale \\")
        print("      --stringsdata <every .stringsdata for that target>")
        print("  then translate the new keys. See CLAUDE.md's localization section.")
        return 1

    print(f"✓ localization coverage: {len(CATALOGS)} catalogs carry every "
          f"{'/'.join(l for l in langs if l != 'en')} translation; {scope}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
