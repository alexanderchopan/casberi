#!/usr/bin/env python3
"""Ask-and-remove audit (prd §1302).

Two rules that came out of the journeys (2026-10-14), made rules so a new
screen cannot drift from them:

1. A CONNECT PAGE'S ONE ASK TAKES THE KEYBOARD. `AccountPage` hands a
   `DSAskFocus` to its act while not connected and its mode is `.pasteKey` or
   `.noAccount` (never `.signIn`, whose keyboard would hide the Sign in tile),
   and the first `DSSlabField` to appear claims it. Checked at the two places
   the rule lives, so all 32 such pages keep it without each remembering.

2. WHAT YOU ADDED TO A LIST GOES FROM A HOLD ON ITS ROW. Every subscription,
   mail list and followed row drawn in the Feed's and the Wallet's lists
   (`WalletSubscriptionRow`, `MailSubscriptionRow`, `FollowingRow` in a
   `FeedScreen*.swift`) carries a `.contextMenu` within a few lines of it.

Usage:  scripts/ask-and-remove-audit.py [--self-test]
Exit 0 = clean.
"""

import pathlib
import re
import shutil
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SLAB = "Casberi/Casberi/Design/DSSlab.swift"
PAGE = "Casberi/Casberi/Screens/AccountPage.swift"
SCREENS = "Casberi/Casberi/Screens"
ROWS = ("WalletSubscriptionRow(", "MailSubscriptionRow(", "FollowingRow(")
# How far below a row's constructor its menu may sit: the label's own
# modifiers, the button style, then the menu.
LOOKAHEAD = 14


def ask_findings(root):
    out = []
    slab = (root / SLAB).read_text()
    start = slab.find("struct DSSlabField: View {")
    if start < 0:
        return [f"{SLAB}: no DSSlabField"]
    nxt = slab.find("\nstruct ", start + 1)
    field = slab[start:nxt if nxt > 0 else len(slab)]
    if ".onAppear(perform: claimAsk)" not in field:
        out.append(f"{SLAB}: DSSlabField no longer claims the page's ask on appear")
    claim = re.search(r"func claimAsk\(\)\s*\{(.*?)\n    \}", field, re.S)
    if not claim or "focusField()" not in claim.group(1):
        out.append(f"{SLAB}: claimAsk no longer focuses the field")
    if "@Environment(\\.dsAskFocus)" not in field:
        out.append(f"{SLAB}: DSSlabField does not read dsAskFocus")

    page = (root / PAGE).read_text()
    if not re.search(r"\.environment\(\\\.dsAskFocus,\s*asksForField", page):
        out.append(f"{PAGE}: the act no longer hands its ask to its fields")
    asks = re.search(r"private var asksForField: Bool \{(.*?)\n    \}", page, re.S)
    body = asks.group(1) if asks else ""
    if ".pasteKey" not in body or ".noAccount" not in body:
        out.append(f"{PAGE}: asksForField no longer covers .pasteKey and .noAccount")
    if ".signIn" in body:
        out.append(f"{PAGE}: asksForField takes .signIn, whose keyboard hides the Sign in tile")
    return out


def row_findings(root):
    out = []
    for path in sorted((root / SCREENS).glob("FeedScreen*.swift")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("//"):
                continue
            for row in ROWS:
                if row in line:
                    window = "\n".join(lines[i:i + LOOKAHEAD])
                    if ".contextMenu" not in window:
                        rel = path.relative_to(root)
                        out.append(f"{rel}:{i + 1}: {row[:-1]} has no hold menu to remove it")
    return out


# Library's followed-wallet rows went with its box (2026-10-30); the Wallet's
# Following list is where a followed account stands now.
WALLETS = "Casberi/Casberi/Screens/FeedScreen+WalletHome.swift"


def wallet_findings(root):
    """The Wallet's followed accounts (prd §1302): each row removes from a hold."""
    text = (root / WALLETS).read_text()
    i = text.find("if case .wallet(let address)? = slot.faces.first {")
    if i < 0:
        return [f"{WALLETS}: no followed-wallet rows found (the audit's anchor moved)"]
    block = text[max(0, i - 200):i + 1200]
    if ".contextMenu" not in block or "WalletUnwatch.perform" not in block:
        return [f"{WALLETS}: a followed wallet's row has no hold menu to stop following it"]
    return []


def audit(root):
    return ask_findings(root) + row_findings(root) + wallet_findings(root)


def self_test():
    """Break each rule in a copy of the tree's files and require a finding."""
    cases = [
        (SLAB, ".onAppear(perform: claimAsk)", "", "claims the page's ask"),
        (SLAB, "DispatchQueue.main.async { focusField() }", "DispatchQueue.main.async { }", "focuses the field"),
        (PAGE, "return mode == .pasteKey || mode == .noAccount",
         "return mode == .pasteKey || mode == .noAccount || mode == .signIn", "takes .signIn"),
        (PAGE, "return mode == .pasteKey || mode == .noAccount", "return mode == .pasteKey", "covers .pasteKey and .noAccount"),
        (PAGE, ".environment(\\.dsAskFocus, asksForField ? askFocus : nil)", "", "hands its ask"),
        (SCREENS + "/FeedScreen+Subscriptions.swift", ".contextMenu { stopTrackingMenu(item) }", "", "WalletSubscriptionRow has no hold menu"),
        (SCREENS + "/FeedScreen+MergedRoom.swift", ".contextMenu { stopTrackingMenu(item) }", "", "MailSubscriptionRow has no hold menu"),
        (SCREENS + "/FeedScreen+Following.swift", ".contextMenu { stopFollowingMenu(item, room) }", "", "FollowingRow has no hold menu"),
        (WALLETS, "WalletUnwatch.perform(entry, context: modelContext, chrome: chrome, bridges: bridges)", "", "followed wallet's row has no hold menu"),
    ]
    clean = audit(ROOT)
    if clean:
        print("self-test: the tree itself is not clean:\n  " + "\n  ".join(clean), file=sys.stderr)
        return 1
    failed = 0
    for rel, old, new, expect in cases:
        with tempfile.TemporaryDirectory() as tmp:
            copy = pathlib.Path(tmp)
            for f in (SLAB, PAGE, WALLETS):
                (copy / f).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / f, copy / f)
            (copy / SCREENS).mkdir(parents=True, exist_ok=True)
            for f in (ROOT / SCREENS).glob("FeedScreen*.swift"):
                shutil.copy(f, copy / SCREENS / f.name)
            target = copy / rel
            text = target.read_text()
            if old not in text:
                print(f"self-test FAILED: mutation anchor moved in {rel}: {old[:50]}", file=sys.stderr)
                failed += 1
                continue
            target.write_text(text.replace(old, new, 1))
            found = audit(copy)
            if not any(expect in f for f in found):
                print(f"self-test FAILED: breaking '{expect}' went unnoticed", file=sys.stderr)
                failed += 1
    if failed:
        return 1
    print(f"ask-and-remove audit self-test: ok ({len(cases)} mutations)")
    return 0


def main():
    if "--self-test" in sys.argv[1:]:
        return self_test()
    findings = audit(ROOT)
    for f in findings:
        print(f"  {f}")
    if findings:
        print(f"✗ ask-and-remove audit: {len(findings)} finding(s) (prd §1302)")
        return 1
    print("✓ ask-and-remove audit: connect pages focus their one ask; every added row and followed wallet removes from a hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
