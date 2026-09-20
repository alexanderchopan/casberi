#!/usr/bin/env python3
"""THE ONCHAIN-CARD SEATS, AND THE FOUR WAYS THEY FAIL WITHOUT FAILING.

Three seats read a card whose swipe settles on a public chain — Gnosis Pay on
Gnosis Chain (prd §222), ether.fi Cash on Optimism, MetaMask Card on Linea
(2026-09-20). They are the same object read three times, and every one of them
is a filtered log read, a cursor, an evidence mark and a money formatter.

Every check below guards a failure that COMPILES, RENDERS AND LOOKS RIGHT. That
is the whole reason this file exists: a card seat that is subtly wrong does not
crash, it simply says you did not spend anything, or says you spent a
thousandth of what you did — and both read exactly like the healthy answer,
because for almost every wallet on earth "no card here" IS the healthy answer.

**(1) A hex key in a lookup table is LOWERCASE.** These tables are keyed by
contract address and looked up with the log's own `address` field lowercased,
so a key carrying one capital letter never matches anything, ever. Nothing
warns: the seat lands zero rows and reads as "this wallet holds no card". The
addresses come from vendor sources that write them in EIP-55 mixed case
(MetaMask's `defaults.ts` does), so hand-lowercasing is a real step a person
really performs, and getting it wrong on one of eight entries is invisible.
Measured when this check was written: 54 such keys in the app, 0 mixed-case.

**(2) An amount with no currency claims no money.** A card table may hold a
token that is not a fiat stablecoin — MetaMask Card can spend WETH — and the
chain does not carry a price. Writing `priceValue` for one of those publishes a
number that every downstream surface reads as dollars, which is §83's fake
status in the most expensive place this app has. So in a file whose token type
declares `currency: String?`, a `priceValue` assignment must sit inside the
unwrap of that currency.

**(3) The cursor advances AFTER the save, never before.** The `WalletApprovals`
rule. A cursor written before a failed save skips those blocks forever — the
spends are not late, they are gone, and the only symptom is a gap in a feed
nobody is diffing against a block explorer.

**(4) A seat's state is swept and cleared.** Each bridge must be called from
`WalletIngest` (or it never runs) and its `clearState` from `WalletStore` (or
unwatching a wallet leaves a stale cursor and an evidence mark, which keeps the
seat lit for a card whose wallet is gone — and, worse, makes re-watching land
nothing because the cursor is still ahead of the blocks it never read).

**(5) Evidence keys are distinct.** Two seats sharing a `WalletSeatEvidence`
key would light each other: hold a Gnosis Pay card and a MetaMask Card seat
appears. A copy-paste of a sibling bridge is exactly how that arrives, and it
is one string in a file nobody re-reads.

What this deliberately does NOT check:
  * That any address is CORRECT. A settlement address, a spender or a token
    contract can only be proved by reading the chain — see each bridge's own
    MEASURED header for what was read and when. A wrong-but-lowercase address
    passes here and lands nothing, which is why those headers name the numbers
    they were verified against.
  * That the decimals are right. Same reason: `decimals()` is a chain call.
    Check 2 only guards the currency/price pairing, not the scale.
  * Anything about the ROWS. Whether a spend reads well in a feed is a matter
    for the room, and no static check sees it.

`--self-test` runs first and is required, per this repo's rule that a check
which cannot demonstrate it catches anything certifies nothing.
"""
import re
import sys
import pathlib

SOURCES = ["Casberi/Casberi", "Casberi/Shared"]

# The onchain-card seats. A new one belongs here the day it lands — an entry
# that does not exist on disk is a finding of its own (check 4), so this list
# cannot rot quietly into a check that scans nothing.
CARD_BRIDGES = [
    "GnosisPayBridge.swift",
    "EtherFiCash.swift",
    "MetaMaskCardBridge.swift",
]

SWEEPER = "WalletIngest.swift"
UNWATCHER = "WalletStore.swift"


def strip(text):
    """Comments and string literals out. Every rule here is documented by
    naming the thing it governs, so raw source fires on the prose explaining
    it — the lesson this repo has paid for four times."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text, flags=re.M)
    return text


def hex_keys(text):
    """Dictionary-literal keys that are 20-byte hex addresses."""
    return re.findall(r'"(0x[0-9a-fA-F]{40})"\s*:', text)


def check_lowercase(name, text):
    out = []
    for addr in hex_keys(text):
        if addr != addr.lower():
            out.append(f"{name}: lookup key {addr} is not lowercase — it is "
                       f"matched against a lowercased log address, so it can "
                       f"never hit and the seat reads as 'no card'")
    return out


def check_price_pairing(name, text):
    """In a file whose token type has an OPTIONAL currency, `priceValue` must
    be written inside that currency's unwrap."""
    if not re.search(r"\blet currency: String\?", text):
        return []
    out = []
    depth = 0
    guarded = []          # brace depths at which a currency unwrap opened
    for line in text.split("\n"):
        opened = re.search(r"\bif\s+let\s+(\w+)\s*=\s*[^\n]*currency[^\n]*\{", line)
        if opened:
            guarded.append(depth + line.count("{") - line.count("}"))
        if re.search(r"\bpriceValue\s*=", line) and not guarded:
            out.append(f"{name}: writes priceValue outside the currency unwrap "
                       f"— a token with no currency would publish a bare number "
                       f"that reads as dollars downstream (§83)")
        depth += line.count("{") - line.count("}")
        guarded = [d for d in guarded if d <= depth]
    return out


def check_cursor_after_save(name, text):
    """`defaults.set(<cursor>, forKey:` must not precede the save."""
    cursor = re.search(r"defaults\.set\(\s*scanned\s*,\s*forKey:", text)
    if not cursor:
        return []
    save = re.search(r"saveHonestly\(\)", text)
    if not save:
        return [f"{name}: advances a scan cursor but never calls saveHonestly() "
                f"— every landed spend is lost on the next launch"]
    if cursor.start() < save.start():
        return [f"{name}: advances its scan cursor BEFORE the save — a failed "
                f"save then skips those blocks forever (the WalletApprovals rule)"]
    return []


def audit_text(name, text):
    if name not in CARD_BRIDGES:
        # Check 1 is the one rule that is worth applying to EVERY file: it is
        # about a lookup that silently misses, and nothing about it is specific
        # to a card.
        return check_lowercase(name, strip(text))
    t = strip(text)
    return (check_lowercase(name, t)
            + check_price_pairing(name, t)
            + check_cursor_after_save(name, t))


def audit_wiring(bridges, sweeper_text, unwatcher_text):
    """Checks 4 and 5 — cross-file, so they take their inputs rather than
    reading the tree, which is what makes them self-testable."""
    out = []
    sweeper_text = strip(sweeper_text)
    unwatcher_text = strip(unwatcher_text)
    seen_keys = {}
    for name, text in bridges.items():
        enum = name[:-len(".swift")]
        t = strip(text)
        if f"{enum}.sync(" not in sweeper_text:
            out.append(f"{enum} is never swept — nothing in {SWEEPER} calls "
                       f"{enum}.sync(, so the seat can only ever be empty")
        if "clearState" in t and f"{enum}.clearState(" not in unwatcher_text:
            out.append(f"{enum}.clearState is never called from {UNWATCHER} — "
                       f"unwatching leaves a cursor ahead of unread blocks and "
                       f"an evidence mark that keeps the seat lit")
        for key in re.findall(r'WalletSeatEvidence\("([^"]+)"\)', t):
            if key in seen_keys:
                out.append(f"{enum} shares its evidence key \"{key}\" with "
                           f"{seen_keys[key]} — one seat's card would light the "
                           f"other's")
            seen_keys[key] = enum
    return out


# ---------------------------------------------------------------- self-test

CLEAN_BRIDGE = '''
enum AcmeCardBridge {
    struct Spendable { let symbol: String; let decimals: Int; let currency: String? }
    static let spendable: [String: Spendable] = [
        "0x176211869ca2b568f2a7d4ee941e073a821ee1ff": Spendable(symbol: "USDC", decimals: 6, currency: "USD"),
    ]
    static let evidence = WalletSeatEvidence("acme.accounts")
    static func clearState(address: String) {}
    static func sync() {
        if let currency = spend.token.currency {
            thing.priceValue = amount
            thing.priceCurrency = currency
        }
        guard context.saveHonestly() else { continue }
        defaults.set(scanned, forKey: key)
    }
}
'''

MIXED_CASE = CLEAN_BRIDGE.replace(
    "0x176211869ca2b568f2a7d4ee941e073a821ee1ff",
    "0x176211869cA2b568f2A7D4EE941E073a821EE1ff")

BARE_PRICE = CLEAN_BRIDGE.replace(
    """        if let currency = spend.token.currency {
            thing.priceValue = amount
            thing.priceCurrency = currency
        }""",
    """        thing.priceValue = amount
        thing.priceCurrency = currency ?? "USD\"""")

CURSOR_FIRST = CLEAN_BRIDGE.replace(
    """        guard context.saveHonestly() else { continue }
        defaults.set(scanned, forKey: key)""",
    """        defaults.set(scanned, forKey: key)
        guard context.saveHonestly() else { continue }""")

NO_SAVE = CLEAN_BRIDGE.replace(
    "        guard context.saveHonestly() else { continue }\n", "")

COMMENTED = CLEAN_BRIDGE.replace(
    '    static let evidence = WalletSeatEvidence("acme.accounts")',
    '    // was "0x176211869cA2b568f2A7D4EE941E073a821EE1ff": before the rename\n'
    '    static let evidence = WalletSeatEvidence("acme.accounts")')

NON_CARD_MIXED = '''
enum Somewhere {
    static let labels: [String: String] = [
        "0x176211869cA2b568f2A7D4EE941E073a821EE1ff": "USDC",
    ]
}
'''


def self_test():
    cases = [
        ("passes a clean card bridge", "MetaMaskCardBridge.swift", CLEAN_BRIDGE, 0),
        ("flags  a mixed-case lookup key", "MetaMaskCardBridge.swift", MIXED_CASE, 1),
        ("flags  an unguarded priceValue", "MetaMaskCardBridge.swift", BARE_PRICE, 1),
        ("flags  a cursor advanced before the save", "MetaMaskCardBridge.swift", CURSOR_FIRST, 1),
        ("flags  a cursor with no save at all", "MetaMaskCardBridge.swift", NO_SAVE, 1),
        ("passes a mixed-case address in a COMMENT", "MetaMaskCardBridge.swift", COMMENTED, 0),
        ("flags  a mixed-case key in any file", "Somewhere.swift", NON_CARD_MIXED, 1),
        ("passes an empty file", "MetaMaskCardBridge.swift", "", 0),
    ]
    ok = True
    for label, name, text, want in cases:
        found = audit_text(name, text)
        mark = "ok  " if len(found) == want else "FAIL"
        if len(found) != want:
            ok = False
            for f in found:
                print(f"       · {f}")
        print(f"  {mark} {label} (expected {want}, got {len(found)})")

    wiring = [
        ("passes a swept, cleared, uniquely-keyed seat",
         {"AcmeCardBridge.swift": CLEAN_BRIDGE},
         "AcmeCardBridge.sync(context:", "AcmeCardBridge.clearState(address:", 0),
        ("flags  a bridge nothing sweeps",
         {"AcmeCardBridge.swift": CLEAN_BRIDGE},
         "// nothing here", "AcmeCardBridge.clearState(address:", 1),
        ("flags  a bridge unwatch never clears",
         {"AcmeCardBridge.swift": CLEAN_BRIDGE},
         "AcmeCardBridge.sync(context:", "// nothing here", 1),
        ("flags  two seats sharing an evidence key",
         {"AcmeCardBridge.swift": CLEAN_BRIDGE,
          "BetaCardBridge.swift": CLEAN_BRIDGE.replace("AcmeCard", "BetaCard")},
         "AcmeCardBridge.sync( BetaCardBridge.sync(",
         "AcmeCardBridge.clearState( BetaCardBridge.clearState(", 1),
        ("passes a sweep call named only in a COMMENT? no — it must be real",
         {"AcmeCardBridge.swift": CLEAN_BRIDGE},
         "// AcmeCardBridge.sync(context:", "AcmeCardBridge.clearState(address:", 1),
    ]
    for label, bridges, sweeper, unwatcher, want in wiring:
        found = audit_wiring(bridges, sweeper, unwatcher)
        mark = "ok  " if len(found) == want else "FAIL"
        if len(found) != want:
            ok = False
            for f in found:
                print(f"       · {f}")
        print(f"  {mark} {label} (expected {want}, got {len(found)})")
    return ok


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--self-test" in sys.argv:
        print("card-spend-audit self-test")
        if not self_test():
            print("SELF-TEST FAILED")
            return 1
        print("  self-test passed")

    findings, scanned = [], 0
    bridges, sweeper, unwatcher = {}, "", ""
    for src in SOURCES:
        base = root / src
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            scanned += 1
            text = path.read_text(encoding="utf-8", errors="replace")
            findings.extend(audit_text(path.name, text))
            if path.name in CARD_BRIDGES:
                bridges[path.name] = text
            elif path.name == SWEEPER:
                sweeper = text
            elif path.name == UNWATCHER:
                unwatcher = text

    for name in CARD_BRIDGES:
        if name not in bridges:
            findings.append(f"{name} is listed as a card seat here but is not "
                            f"on disk — this check is scanning nothing for it")
    findings.extend(audit_wiring(bridges, sweeper, unwatcher))

    if findings:
        print(f"card-spend-audit: {len(findings)} finding(s) in {scanned} files")
        for f in findings:
            print(f"  ✗ {f}")
        return 1
    print(f"card-spend-audit: clean ({scanned} files, {len(bridges)} card seats) "
          f"— lowercase keys, no unpriced money, cursors behind their saves, "
          f"every seat swept and cleared")
    return 0


if __name__ == "__main__":
    sys.exit(main())
