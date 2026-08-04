#!/usr/bin/env python3
"""Info.plist string-catalog audit (ITMS-90738, 2026-08-04).

Every key in an `InfoPlist.xcstrings` must carry a real source-language (`en`)
value. This is mechanical because the failure is INVISIBLE to every other gate
here and inverts the rule that holds for every OTHER catalog in the tree:

  * In `Localizable.xcstrings` / `AppShortcuts.xcstrings` the KEY IS the
    English source text, so a key with no `en` localization is normal — 1,496
    of 1,705 keys in `Localizable.xcstrings` have none, and all of them are
    correct.
  * In `InfoPlist.xcstrings` the key is an Info.plist KEY NAME. A key with no
    `en` localization compiles to `"NSCameraUsageDescription" =
    "NSCameraUsageDescription";` in `en.lproj/InfoPlist.strings`, which then
    OVERRIDES the perfectly good sentence in the target's own
    `INFOPLIST_KEY_NSCameraUsageDescription` build setting.

That is what shipped in builds 267/268: all thirteen purpose strings, plus
`CFBundleDisplayName`, resolved to their own key names on an English device —
so every permission prompt read `NSPhotoLibraryUsageDescription` and the app
name under the icon read `CFBundleDisplayName`. `xcodebuild` succeeded, the
screen sweep passed, `Info.plist` looked right in the bundle, and the only
thing that noticed was App Store Connect, hours after upload, by email.

The check reads the catalogs and nothing else — no pbxproj parse, no build. It
deliberately does NOT flag a purpose string that is missing from the catalog
entirely (that key simply stays English everywhere, which is untranslated, not
broken), and it does NOT compare against the `INFOPLIST_KEY_*` build settings
(a catalog value is ALLOWED to differ; the catalog is what ships). A lint that
cries wolf gets turned off within a week.

Usage:  scripts/infoplist-strings-audit.py [--self-test]
Exit 0 = clean.
"""

import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi"]

# The catalog whose keys are NOT their own English text. Scoped by FILENAME on
# purpose: pointing this audit at `Localizable.xcstrings` would flag ~1,500
# perfectly correct entries, and that misfire is the whole distinction the
# audit exists to encode.
CATALOG = "InfoPlist.xcstrings"


def audit(paths):
    findings = []
    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob(CATALOG)):
            try:
                rel = str(path.relative_to(ROOT))
            except ValueError:
                rel = str(path)          # self-test fixtures live outside the repo
            try:
                catalog = json.loads(path.read_text())
            except (json.JSONDecodeError, UnicodeDecodeError) as err:
                findings.append(f"{rel}: not readable as a string catalog ({err})")
                continue
            source = catalog.get("sourceLanguage", "en")
            for key, entry in sorted(catalog.get("strings", {}).items()):
                locs = entry.get("localizations") or {}
                if not locs:
                    # No localizations at all: nothing is emitted for this key
                    # in any lproj, so it can't override the Info.plist value.
                    # Dead weight, not a defect.
                    continue
                if source not in locs:
                    findings.append(
                        f"{rel}: \"{key}\" has {len(locs)} translation(s) and no "
                        f"\"{source}\" value — it compiles to its own key name "
                        f"in {source}.lproj and overrides the Info.plist string")
                for lang, unit in sorted(locs.items()):
                    value = (unit.get("stringUnit") or {}).get("value")
                    if value is None:
                        continue         # a variation/plural unit, not a flat string
                    if value == key:
                        findings.append(
                            f"{rel}: \"{key}\" is its own value in {lang}.lproj — "
                            f"the permission prompt would read the key name")
                    elif not value.strip():
                        findings.append(
                            f"{rel}: \"{key}\" is empty in {lang}.lproj — Apple "
                            f"rejects an empty purpose string (ITMS-90738)")
    return findings


def self_test():
    """A check that cannot fail proves nothing — demonstrate each shape."""
    def catalog(strings):
        return json.dumps({"sourceLanguage": "en", "version": "1.0",
                           "strings": strings})

    def unit(value, state="translated"):
        return {"stringUnit": {"state": state, "value": value}}

    cases = {
        "no-en": (CATALOG, catalog({
            "NSCameraUsageDescription": {
                "localizations": {"ja": unit("カメラ")}}}),
            True, "a translated key with no source-language value (builds 267/268)"),
        "key-as-value": (CATALOG, catalog({
            "NSCameraUsageDescription": {
                "localizations": {
                    "en": unit("NSCameraUsageDescription")}}}),
            True, "a value that is literally its own key"),
        "empty": (CATALOG, catalog({
            "NSCameraUsageDescription": {
                "localizations": {"en": unit("  ")}}}),
            True, "an empty purpose string"),
        "clean": (CATALOG, catalog({
            "NSCameraUsageDescription": {
                "localizations": {"en": unit("Casberi scans a barcode."),
                                  "ja": unit("バーコードを読み取ります。")}}}),
            False, "a key translated in every language including en"),
        "no-localizations": (CATALOG, catalog({
            "OPML feed list": {"localizations": {}}}),
            False, "a key with no localizations at all (emits nothing)"),
        "english-only": (CATALOG, catalog({
            "NSCameraUsageDescription": {
                "localizations": {"en": unit("Casberi scans a barcode.")}}}),
            False, "a key that is English-only"),
        # The distinction the whole audit rests on: the SAME shape that is a
        # defect above is correct in a catalog whose keys are source text, so
        # the audit must never reach one.
        "localizable": ("Localizable.xcstrings", catalog({
            "Connect an app": {"localizations": {"ja": unit("アプリを接続")}}}),
            False, "the identical shape in Localizable.xcstrings, where key == source text"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, (filename, body, should_flag, why) in cases.items():
            single = pathlib.Path(tmp) / name
            single.mkdir()
            (single / filename).write_text(body)
            flagged = bool(audit([single]))
            if flagged != should_flag:
                ok = False
            mark = "ok  " if flagged == should_flag else "FAIL"
            verb = "flags" if should_flag else "passes"
            print(f"  {mark} {verb} {why}")
    return ok


if "--self-test" in sys.argv:
    print("infoplist-strings-audit self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ Info.plist string-catalog findings:")
    for p in problems:
        print(f"  {p}")
    print("\nEvery key in InfoPlist.xcstrings needs a real source-language "
          "value — without one it compiles to its own key name and overrides "
          "the target's INFOPLIST_KEY_* string. Apple rejects that as "
          "ITMS-90738; the user sees it as a permission prompt reading "
          "\"NSPhotoLibraryUsageDescription\".")
    sys.exit(1)
print("✓ infoplist strings: every catalogued Info.plist key has a real "
      "source-language value")
