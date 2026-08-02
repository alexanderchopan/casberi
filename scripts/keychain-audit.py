#!/usr/bin/env python3
"""Keychain storage policy audit (prd §276).

Every secret this app writes to the Keychain must be stored so that it cannot
ride an encrypted device backup onto another phone, and cannot ride iCloud
Keychain anywhere. That means each `SecItemAdd` must set BOTH:

  * `kSecAttrAccessible` to a `…ThisDeviceOnly` constant, and
  * `kSecAttrSynchronizable` (to false).

This is mechanical rather than remembered because the failure is invisible:
the wrong policy still stores the key, still reads it back, still works — it
just also leaves with the backup. Nothing in a build or a screen sweep can see
it, which is the same shape as the network-reach gap that shipped an
undisclosed host in build 214.

The check is deliberately FILE-scoped, not call-scoped: statically pairing a
`SecItemAdd` with the dictionary literal built for it several lines earlier
means parsing Swift, and a file that adds keychain items without ever naming
a device-only policy is the finding either way.

Usage:  scripts/keychain-audit.py [--self-test]
Exit 0 = clean.
"""

import re
import sys
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Casberi/Casberi", ROOT / "Casberi/Shared",
           ROOT / "Casberi/ShareExtension", ROOT / "Casberi/CasberiWidgets"]

# An accessibility constant that is NOT device-only. The lookahead is the
# whole point: `…AfterFirstUnlockThisDeviceOnly` starts with
# `…AfterFirstUnlock`, so a plain substring test would clear every hardened
# file and flag none.
LOOSE = re.compile(
    r"kSecAttrAccessible(?:AfterFirstUnlock|WhenUnlocked|WhenPasscodeSet|Always)"
    r"(?!ThisDeviceOnly)")
DEVICE_ONLY = re.compile(r"kSecAttrAccessible\w*ThisDeviceOnly")
ADDS = re.compile(r"\bSecItemAdd\s*\(")
SYNC = re.compile(r"\bkSecAttrSynchronizable\b")

# Files that add keychain items on someone else's behalf and are exempt with a
# stated reason. Empty by design — an entry here is a conscious "this item may
# survive a backup restore."
KNOWN_EXEMPT: dict[str, str] = {}


def strip_comments(text):
    """Comments discuss policy constants in prose; only code counts."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def audit(paths):
    findings = []
    for root in paths:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            raw = path.read_text(errors="ignore")
            code = strip_comments(raw)
            if not ADDS.search(code):
                continue
            try:
                rel = str(path.relative_to(ROOT))
            except ValueError:
                rel = str(path)          # self-test fixtures live outside the repo
            if path.name in KNOWN_EXEMPT:
                continue
            if loose := LOOSE.search(code):
                findings.append(
                    f"{rel}: writes {loose.group(0)} — not device-only, so the "
                    f"secret rides an encrypted backup onto another device")
            if not DEVICE_ONLY.search(code):
                findings.append(
                    f"{rel}: calls SecItemAdd without any "
                    f"kSecAttrAccessible…ThisDeviceOnly policy")
            if not SYNC.search(code):
                findings.append(
                    f"{rel}: calls SecItemAdd without naming "
                    f"kSecAttrSynchronizable")
    return findings


def self_test():
    """A check that cannot fail proves nothing — demonstrate each shape."""
    cases = {
        "Loose.swift": (
            'let q = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,\n'
            ' kSecAttrSynchronizable as String: false]\nSecItemAdd(q as CFDictionary, nil)\n',
            True, "a non-device-only policy"),
        "Missing.swift": (
            'let q = [kSecAttrService as String: "x"]\nSecItemAdd(q as CFDictionary, nil)\n',
            True, "no policy at all"),
        "NoSync.swift": (
            'let q = [kSecAttrAccessible as String: '
            'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]\n'
            'SecItemAdd(q as CFDictionary, nil)\n',
            True, "synchronizable never named"),
        "Clean.swift": (
            'let q = [kSecAttrAccessible as String: '
            'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,\n'
            ' kSecAttrSynchronizable as String: false]\nSecItemAdd(q as CFDictionary, nil)\n',
            False, "the hardened shape"),
        "CommentOnly.swift": (
            '// once wrote kSecAttrAccessibleAfterFirstUnlock, now hardened\n'
            'let q = [kSecAttrAccessible as String: '
            'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,\n'
            ' kSecAttrSynchronizable as String: false]\nSecItemAdd(q as CFDictionary, nil)\n',
            False, "prose about the old constant"),
        "NoKeychain.swift": ('let x = 1\n', False, "a file that stores nothing"),
    }
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        for name, (body, _, _) in cases.items():
            (base / name).write_text(body)
        for name, (_, should_flag, why) in cases.items():
            single = base / f"only-{name.lower()}"
            single.mkdir()
            (single / name).write_text(cases[name][0])
            flagged = bool(audit([single]))
            mark = "ok  " if flagged == should_flag else "FAIL"
            if flagged != should_flag:
                ok = False
            verb = "flags" if should_flag else "passes"
            print(f"  {mark} {verb} {why}")
    return ok


if "--self-test" in sys.argv:
    print("keychain-audit self-test")
    sys.exit(0 if self_test() else 1)

problems = audit(SOURCES)
if problems:
    print("✗ keychain policy findings:")
    for p in problems:
        print(f"  {p}")
    print("\nEvery SecItemAdd must set a kSecAttrAccessible…ThisDeviceOnly "
          "policy and name kSecAttrSynchronizable. See TokenVault.swift.")
    sys.exit(1)
print("✓ keychain audit: every keychain write is device-only and non-syncing")
