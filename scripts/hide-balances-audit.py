#!/usr/bin/env python3
"""Hide-wallet-balances audit (prd §374, 2026-08-13).

The §374 privacy gate lives in ONE place per shape (`WalletValue`), and its
whole value is that a wallet view cannot print a figure without passing through
it. Nothing about that is enforced by the compiler: a new card that reaches for
`TokenStats.compact` directly renders perfectly, ships, and quietly leaks the
number the setting promised to hide — with the toggle still sitting in Privacy
saying it doesn't.

That is precisely the class this repo makes mechanical rather than remembered
(`catalog-sync.sh`, `network-reach-audit.sh`, `keychain-audit.py`): a rule whose
violation is INVISIBLE at runtime.

Two checks:

  A. No wallet VIEW calls a raw value formatter. The formatters keep their old
     names and behaviour because INGEST still needs them unmasked — so the rule
     is about WHERE they are called, not that they exist.

  B. The mask can never be confused with a real reading. `BalancePrivacy.mask`
     must not be a digit, a zero, a currency symbol or empty: the wallet's
     honesty rails already spend "0" (a grant that reaches nothing) and nil
     ("we can't know"), and a mask colliding with either turns a privacy
     setting into a false statement about money.

--self-test runs first and is REQUIRED: a check that cannot demonstrate it
catches anything certifies nothing.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
VIEWS = ROOT / "Casberi/Casberi/Screens"
PRIVACY = ROOT / "Casberi/Casberi/Model/BalancePrivacy.swift"

# The raw formatters. A view calling one of these directly bypasses the gate.
RAW = [
    r"\bTokenStats\.compact\s*\(",
    r"\bWalletIngest\.format\s*\(",
    r"\bWalletApprovalExposure\.money\s*\(",
]

# Which view files are WALLET surfaces. Scoped by filename rather than by
# reading imports, for `infoplist-strings-audit`'s reason: a filename is a fact
# and an inferred "is this a wallet screen" is a judgement that drifts.
WALLET_VIEWS = (
    "WalletFeedTiles.swift", "WalletScreen.swift", "WalletWatchField.swift",
    "WalletRosterSection.swift", "WalletHistoryScreen.swift",
    "WalletFlowBand.swift", "WalletLiquidityCard.swift", "WalletPerpsCard.swift",
    "WalletRiskStrip.swift", "WalletApprovalExposureCard.swift",
    "AddressBookViews.swift", "AddressConnectionsCard.swift",
    "GnosisPayRoomCard.swift", "RailgunRoomCard.swift", "PeerRoomCard.swift",
    "PrivacyPoolsRoomCard.swift", "SafeRoomCard.swift", "SafeQueueCard.swift",
    "TokenQuickSheet.swift", "EthValidatorScreen.swift", "WalletRow.swift",
    "ApprovalPrepareCard.swift",
)

# A conscious "this call site is not a displayed balance", matched by PATTERN
# rather than by line number — a line-keyed exemption rots on the next edit to
# the file and then silently exempts whatever moved into that line.
#
# Each entry carries the ruling that put it here.
KNOWN_EXEMPT: list[tuple[str, str, str]] = [
    ("WalletFeedTiles.swift", r'Health \\\(WalletIngest\.format\(health\)\)',
     "A health factor is a RATIO, not a dollar or token amount — §374 hides "
     "what you have, and 1.4 says how close a position is to liquidation. "
     "Hiding it would remove a warning to protect a number it doesn't carry."),
]


def strip_comments(text: str) -> str:
    """Comments describe the rule by naming the very functions it bans, so a
    guard grepping raw source fires against the prose explaining it. Earned
    three times in this repo already (Obsidian, Cursor, on-device)."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def check_views(files) -> list[str]:
    findings = []
    for path in files:
        if path.name not in WALLET_VIEWS:
            continue
        body = strip_comments(path.read_text(encoding="utf-8"))
        for i, line in enumerate(body.splitlines(), 1):
            for pattern in RAW:
                if re.search(pattern, line):
                    if any(path.name == f and re.search(p, line)
                           for f, p, _ in KNOWN_EXEMPT):
                        continue
                    findings.append(
                        f"{path.name}:{i} calls a raw formatter directly — "
                        f"route it through WalletValue so §374 can hide it")
    return findings


def check_mask(text: str) -> list[str]:
    m = re.search(r'static let mask\s*=\s*"([^"]*)"', text)
    if not m:
        return ["BalancePrivacy.mask is missing — the gate has nothing to show"]
    mask = m.group(1)
    if not mask:
        return ["BalancePrivacy.mask is empty — a blank reads as no value, not a hidden one"]
    if any(c.isdigit() for c in mask):
        return [f"BalancePrivacy.mask {mask!r} contains a digit — it must not read as a reading"]
    if any(c in mask for c in "$€£¥"):
        return [f"BalancePrivacy.mask {mask!r} carries a currency symbol — it must not read as money"]
    return []


def self_test() -> None:
    import tempfile
    print("Self-test")
    with tempfile.TemporaryDirectory() as d:
        tmp = pathlib.Path(d)
        dirty = tmp / "WalletFeedTiles.swift"
        dirty.write_text('Text(TokenStats.compact(total))\n')
        assert check_views([dirty]), "a raw formatter in a wallet view must be caught"
        print("  ✓ a raw formatter in a wallet view is caught")

        gated = tmp / "WalletScreen.swift"
        gated.write_text('Text(WalletValue.money(total))\n')
        assert not check_views([gated]), "the gated call must pass"
        print("  ✓ the gated call passes")

        commented = tmp / "WalletRow.swift"
        commented.write_text('// TokenStats.compact is what a view must never call\nText(x)\n')
        assert not check_views([commented]), "a comment naming the formatter must not fire"
        print("  ✓ a comment naming the banned formatter doesn't fire")

        elsewhere = tmp / "FeedScreen.swift"
        elsewhere.write_text('Text(TokenStats.compact(total))\n')
        assert not check_views([elsewhere]), "a non-wallet view is out of scope"
        print("  ✓ a non-wallet view is out of scope")

        for bad, why in [('"0"', "a zero"), ('"$0"', "a currency"), ('""', "empty")]:
            assert check_mask(f"static let mask = {bad}"), f"{why} mask must be caught"
        print("  ✓ a mask that reads as zero, money or nothing is caught")
        assert not check_mask('static let mask = "••••"'), "the shipped mask must pass"
        print("  ✓ the shipped mask passes")
    print()


def main() -> int:
    if "--self-test" in sys.argv:
        self_test()
    findings = check_views(sorted(VIEWS.glob("*.swift")))
    findings += check_mask(PRIVACY.read_text(encoding="utf-8"))
    if findings:
        print("hide-balances-audit: FAIL")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print("hide-balances-audit: OK — every wallet view prints figures through the §374 gate.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
