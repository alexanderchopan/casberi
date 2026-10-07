#!/usr/bin/env python3
"""Keychain storage policy audit (prd §277).

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
KNOWN_EXEMPT: dict[str, str] = {
    # The locked-note key (prd §982, the user's ruling 2026-09-28): its whole
    # job is to reach the person's other devices, so a locked note opens on
    # each of them and survives a new phone — Apple Notes' own design. It is
    # synchronizable through iCloud Keychain (end-to-end encrypted) and
    # AfterFirstUnlock, because a synchronizable item cannot be ThisDeviceOnly.
    # Opening a note is gated by device-owner authentication in the app.
    "NoteLock.swift": "the locked-note key syncs through iCloud Keychain by ruling (prd §982)",
}

# Files that write BOTH kinds by a stated rule (prd §1162, user 2026-10-07:
# "yes let them"): a pasted API key syncs through iCloud Keychain, everything
# else stays device-only. Not an exemption — the file is still audited, and
# must still name a ThisDeviceOnly policy (what stays) and
# kSecAttrSynchronizable. The one extra demand is kSecAttrAccessGroup: a
# synced item written into a platform's DEFAULT group syncs and is unreadable
# on the other platform (the Mac's default group is not the iPhone's), so a
# sync that does not name the shared group is the bug this would hide.
SYNC_RULED: dict[str, str] = {
    "TokenVault.swift": "pasted keys sync, sessions and refresh tokens stay (prd §1162)",
}
ACCESS_GROUP = re.compile(r"\bkSecAttrAccessGroup\b")


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
            ruled = path.name in SYNC_RULED
            if ruled and LOOSE.search(code) and not ACCESS_GROUP.search(code):
                findings.append(
                    f"{rel}: syncs an item without naming kSecAttrAccessGroup — "
                    f"it lands in this platform's default group and the other "
                    f"device cannot read it")
            if not ruled and (loose := LOOSE.search(code)):
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
    # The ruled file, by its real name, in its own directory each time.
    ruled = {
        "group": (
            'let local = [kSecAttrAccessible as String: '
            'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,\n'
            ' kSecAttrSynchronizable as String: false]\n'
            'let synced = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,\n'
            ' kSecAttrSynchronizable as String: true, kSecAttrAccessGroup as String: g]\n'
            'SecItemAdd(q as CFDictionary, nil)\n',
            False, "the ruled vault syncing into the shared group"),
        "nogroup": (
            'let local = [kSecAttrAccessible as String: '
            'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,\n'
            ' kSecAttrSynchronizable as String: false]\n'
            'let synced = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,\n'
            ' kSecAttrSynchronizable as String: true]\n'
            'SecItemAdd(q as CFDictionary, nil)\n',
            True, "the ruled vault syncing into a default group"),
        "nolocal": (
            'let synced = [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,\n'
            ' kSecAttrSynchronizable as String: true, kSecAttrAccessGroup as String: g]\n'
            'SecItemAdd(q as CFDictionary, nil)\n',
            True, "the ruled vault with no device-only policy left"),
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
        for tag, (body, should_flag, why) in ruled.items():
            single = base / f"ruled-{tag}"
            single.mkdir()
            (single / "TokenVault.swift").write_text(body)
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
print("✓ keychain audit: every keychain write is device-only and non-syncing, "
      "or syncs by a stated rule into the shared group"
      + (f" ({len(KNOWN_EXEMPT)} reasoned exemption, {len(SYNC_RULED)} ruled)"
         if KNOWN_EXEMPT or SYNC_RULED else ""))
