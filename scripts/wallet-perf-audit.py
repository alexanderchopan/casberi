#!/usr/bin/env python3
"""Wallet-perf audit (docs/wallet-perf-spec.md, 2026-11-09).

WHAT THE WALLET'S WAITS WERE MADE OF, AND THE ORDER THAT TOOK THEM AWAY. Each
rule below is work that no longer runs, runs once, or runs beside something
else. None of them changes what the Wallet shows, so no screen check sees one
come back; this does.

  1. The balance history is decoded once per WRITE, not per body pass:
     `WalletStore.valueSamples` returns the memo while the stored bytes are the
     same bytes, and decodes only after that check (B1).
  2. The combined line is memoised on its lines (B1).
  3. Several wallets' holdings are their own windowed reads, merged: a
     multi-wallet ask goes through each wallet's entry, so the room's per-wallet
     read and the sweep's all-wallet read are one read (A1).
  4. The total's extras start beside the holdings read, not after it (A2).
  5. The doors' riders (approvals, delegations, Safe) run before every other
     rider in the sweep pass (C1).
  6. The spam filters' reads start at the top of the pass, beside the
     transfer reads (C2).
  7. The Wallet's scope is resolved once per filter, never per row (B3).
  8. Every rider and the pass itself stay timed (Phase 0): a rider added
     without `perf.rider` is a rider no reading can name.

Comment-stripped, because the source documents these rules by naming the very
calls being checked. `--self-test` breaks each rule on purpose.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Casberi" / "Casberi"
FILES = {
    "WalletStore": APP / "Model" / "WalletStore.swift",
    "WalletIngest": APP / "Model" / "WalletIngest.swift",
    "Derivations": APP / "Screens" / "FeedScreen+Derivations.swift",
}


def strip(text: str) -> str:
    return re.sub(r"//.*", "", text)


def read() -> dict:
    return {k: strip(p.read_text()) for k, p in FILES.items()}


def body(code: str, signature: str) -> str:
    i = code.find(signature)
    if i < 0:
        return ""
    j = code.find("{", i)
    if j < 0:
        return ""
    depth, k = 0, j
    while k < len(code):
        if code[k] == "{":
            depth += 1
        elif code[k] == "}":
            depth -= 1
            if depth == 0:
                return code[j:k + 1]
        k += 1
    return code[j:]


def before(text: str, first: str, second: str) -> bool:
    a, b = text.find(first), text.find(second)
    return a >= 0 and b >= 0 and a < b


def audit(code: dict) -> list:
    bad = []
    vs = body(code["WalletStore"], "func valueSamples(forAddress")
    if not before(vs, "hit.data == data", "JSONDecoder().decode"):
        bad.append("WalletStore.valueSamples decodes before (or without) its memo — the crown "
                   "decodes every wallet's history on every body pass again (B1)")
    cv = body(code["WalletStore"], "func combinedValueSamples(")
    if "hit.lines == lines" not in cv or "Self.merged(lines)" not in cv:
        bad.append("combinedValueSamples merges without its memo (B1)")

    ingest = code["WalletIngest"]
    dated = body(ingest, "func fetchHeldTokensDated(")
    if "if unique.count > 1" not in dated or "fetchHeldTokensDated(addresses: [address])" not in dated:
        bad.append("a multi-wallet holdings ask is one batched read again — every wallet's "
                   "/positions goes out twice a pass (A1)")

    pr = body(ingest, "static func portfolioReading(")
    if not before(pr, "async let exchangeRead", "await holdingsByWallet()") \
            or not before(pr, "async let lentRead", "await holdingsByWallet()"):
        bad.append("the total's extras no longer start beside the holdings read — the total "
                   "waits for their sum again (A2)")

    rf = body(ingest, "static func refresh(context: ModelContext)")
    first_other = rf.find("PeerBridge.sync(")
    for door in ("WalletApprovals.sync(", "WalletSafety.sync(", "SafeBridge.sync("):
        at = rf.find(door)
        if at < 0 or first_other < 0 or at > first_other:
            bad.append(f"{door.rstrip('(')} no longer runs before the other riders — Needs you "
                       "and Permissions wait on every rider again (C1)")
    for read_ in ("heldByOwnerRead", "ownedNFTsRead", "verifiedNFTsRead"):
        if not before(rf, f"async let {read_}", "IngestSupport.boundedGather(evmAddresses"):
            bad.append(f"{read_} no longer starts before the transfer reads (C2)")
    riders = re.findall(r"let \w+ = await ((?:[A-Z]\w*\.)+sync\w*)\(context:", rf)
    if riders:
        bad.append("a rider runs untimed: " + ", ".join(sorted(set(riders))) +
                   " — wrap it in perf.rider (Phase 0)")
    if "let perf = WalletPerf.Pass()" not in rf or "perf.end(added: result)" not in rf:
        bad.append("the sweep pass is no longer timed (Phase 0)")

    lv = body(code["Derivations"], "func liveVisible(")
    if not before(lv, "let walletAllows = walletScopeTest()", "base.filter") \
            or "walletAllows(thing)" not in lv:
        bad.append("the Wallet's scope is resolved per row again (B3)")
    return bad


def self_test() -> int:
    base = read()
    if audit(base):
        print("✗ self-test: the tree does not pass, so no mutation proves anything")
        for line in audit(base):
            print("   ", line)
        return 1
    cases = [
        ("the decode moves above the memo", "WalletStore",
         lambda t: t.replace("if let hit = sampleMemo[key], hit.data == data {",
                             "let _ = try? JSONDecoder().decode([ValueSample].self, from: data)\n"
                             "        if let hit = sampleMemo[key], hit.data == data {", 1)),
        ("the combined memo goes", "WalletStore",
         lambda t: t.replace("hit.lines == lines", "false", 1)),
        ("the batched holdings read returns", "WalletIngest",
         lambda t: t.replace("if unique.count > 1 {", "if false {", 1)),
        ("the extras wait for the holdings again", "WalletIngest",
         lambda t: t.replace("let read = await holdingsByWallet()",
                             "let read = await holdingsByWallet()\n        async let exchangeRead2 = 0", 1)
                    .replace("async let exchangeRead =", "let exchangeReadLate =", 1)),
        ("Safe goes back to last", "WalletIngest",
         lambda t: t.replace("SafeBridge.sync(", "SafeBridgeLate.sync(", 1)),
        ("the holdings filter read waits for the transfers", "WalletIngest",
         lambda t: t.replace("async let heldByOwnerRead", "let heldByOwnerReadLate", 1)),
        ("a rider runs untimed", "WalletIngest",
         lambda t: t.replace('await perf.rider("PeerBridge.sync") { await PeerBridge.sync(',
                             "await PeerBridge.sync(", 1)),
        ("the pass goes untimed", "WalletIngest",
         lambda t: t.replace("perf.end(added: result)", "", 1)),
        ("the scope is resolved per row", "Derivations",
         lambda t: t.replace("&& walletAllows(thing)", "&& walletScopeTest()(thing)", 1)),
    ]
    ok = True
    for name, key, mutate in cases:
        mutated = dict(base)
        changed = mutate(base[key])
        if changed == base[key]:
            print(f"  DEAD {name} (the mutation changed nothing)")
            ok = False
            continue
        mutated[key] = changed
        if audit(mutated):
            print(f"  ok   {name}")
        else:
            print(f"  SURVIVED {name}")
            ok = False
    return 0 if ok else 1


def main() -> int:
    bad = audit(read())
    if bad:
        print("✗ wallet-perf audit findings:")
        for line in bad:
            print("  " + line)
        print("\nSee docs/wallet-perf-spec.md: each rule is work the Wallet no longer waits on.")
        return 1
    print("✓ wallet-perf audit: history decoded per write, one holdings read per wallet, the total's "
          "extras beside it, the doors' riders first, the filters' reads early, the scope resolved once, "
          "every rider timed")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else main())
