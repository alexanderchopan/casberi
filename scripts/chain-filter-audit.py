#!/usr/bin/env python3
"""Chain-filter audit (prd §825, 2026-09-18).

WHY THIS EXISTS. The user opened the Wallet room and saw a Privy app wallet's
money — Zora's, a STORED last read — and nothing at all from their own wallets,
on "All" and on every individual page alike. Two providers had both come back
empty for every watched wallet at once, and nothing on the screen said so.

Both holdings arms ask for every chain in ONE request per wallet, so one chain
a provider refuses does not fail alone: it takes every chain, for every wallet.
Zerion's filter was built from `networkFor.keys` — every chain the file maps,
whatever the person had switched on — and Alchemy's guard against the same
thing was `unprovenNetworks`, a hand-kept list that was EMPTY, which made its
own retry dead code. A list of the chains we already knew about could never
have caught the next one.

So the shape is the check, not any particular chain:

  1. Neither Zerion read builds its chain filter from the whole map. It is
     built from the CALLER's routed networks (`wanted`), because a chain
     nobody enabled must not be able to refuse a call it was never wanted in.
  2. Each Zerion read retries UNFILTERED when the filtered call fails. The
     filter is an optimisation; `WalletIngest.collectCandidatesZerion` has
     always filtered the answer itself, so correctness never needed it.
  3. The Alchemy arm ISOLATES a rejected body — `portfolioTokens` asked with
     one network — and learns the refusal through `RefusedNetworks` rather
     than from a hand-kept list. `unprovenNetworks` may not come back.
  4. `portfolioRead` stands on the last known reading when the live read
     produced no group AND a wallet was UNREACHED (never merely empty), and
     stamps it (`asOf`), because a dated number may be shown and a dated
     number presented as current may not (§83).
  5. The crown DRAWS that stamp, and the room passes it. A fallback nothing
     says is a fallback that lies.

WHAT IT DELIBERATELY DOES NOT CHECK. Whether either provider actually accepts
any given chain — that is a measurement, not a static fact, and `-portfolioProbe`
is where it is read. This only holds the shape that keeps one refusal from
costing every wallet its balances.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = {
    "ZerionAPI": ROOT / "Casberi/Casberi/Model/ZerionAPI.swift",
    "WalletIngest": ROOT / "Casberi/Casberi/Model/WalletIngest.swift",
    "WalletPortfolio": ROOT / "Casberi/Casberi/Model/WalletPortfolio.swift",
    "WalletFeedTiles": ROOT / "Casberi/Casberi/Screens/WalletFeedTiles.swift",
    "FeedScreen": ROOT / "Casberi/Casberi/Screens/FeedScreen.swift",
}


def strip_comments(text: str) -> str:
    """Code only. Every rule below is named in a doc comment somewhere in these
    files — matching against the comments would pass a file whose CODE had been
    reverted, which is the one thing this must never do."""
    out = []
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        out.append(re.sub(r"\s+//(?!/).*$", "", line))
    return "\n".join(out)


def body(code: str, signature: str) -> str:
    """The braced body of the declaration whose signature line contains
    `signature`, by brace balance from the first `{` after it."""
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


def audit(texts: dict) -> list:
    code = {k: strip_comments(v) for k, v in texts.items()}
    bad = []
    zerion = code["ZerionAPI"]
    ingest = code["WalletIngest"]

    # 1 + 2 — both Zerion reads, held to the same two rules.
    for name, sig in (("holdings", "static func holdings(address:"),
                      ("transactions", "static func transactions(address:")):
        b = body(zerion, sig)
        if not b:
            bad.append(f"ZerionAPI.{name} is gone — this audit can no longer see the chain filter")
            continue
        if "filter[chain_ids]" not in b:
            continue   # no filter at all is safe by construction
        # The filter's source set must READ the `networks` parameter — a bare
        # `networkFor` on that line is the whole-map spelling this exists to
        # stop, and it is not enough that the variable is merely named.
        source = [ln for ln in b.split("\n") if re.search(r"\blet wanted\b", ln)]
        fed = any(re.search(r"(?<!networkFor\.)\bnetworks\b(?!\s*For)", re.sub(r"networkFor\.\w+", "", ln))
                  for ln in source)
        if not source or not fed:
            bad.append(f"ZerionAPI.{name} builds its chain filter without the caller's "
                       f"`networks` — a chain nobody enabled can refuse this call (prd §825)")
        if b.count("dataRows(") < 2:
            bad.append(f"ZerionAPI.{name} has no unfiltered retry — one refused chain id "
                       f"empties this read for every wallet (prd §825)")

    # 3 — the Alchemy arm isolates, and learns.
    alch = body(ingest, "static func collectCandidatesAlchemy(")
    if not alch:
        bad.append("WalletIngest.collectCandidatesAlchemy is gone — this audit is blind")
    else:
        if "portfolioTokens(" not in alch or "networks: [network]" not in alch:
            bad.append("collectCandidatesAlchemy no longer asks one network at a time when a "
                       "body is rejected — one chain takes every wallet's balances (prd §825)")
        if "RefusedNetworks.shared.mark(" not in alch:
            bad.append("collectCandidatesAlchemy no longer LEARNS a refusal — the guard is "
                       "back to a hand-kept list (prd §825)")
    if re.search(r"\bunprovenNetworks\s*:", ingest) or "unprovenNetworks =" in ingest:
        bad.append("`unprovenNetworks` is back — a list of the chains we already knew about "
                   "cannot catch the next one (prd §825)")
    pt = body(ingest, "static func portfolioTokens(")
    if pt and "status" not in pt:
        bad.append("portfolioTokens no longer reads the status — an outage would be isolated "
                   "chain by chain as though it were a refusal (prd §825)")

    # 4 — the last-known fallback, gated and stamped.
    pr = body(ingest, "static func portfolioRead(")
    if not pr:
        bad.append("WalletIngest.portfolioRead is gone — this audit is blind")
    else:
        if "lastKnownHoldingsByWallet()" not in pr:
            bad.append("portfolioRead no longer falls back to the last known holdings — an "
                       "unreachable pass shows Privy's stored money and none of yours (prd §825)")
        elif "unreached" not in pr:
            bad.append("portfolioRead's last-known fallback is not gated on UNREACHED — a "
                       "wallet that answered and holds nothing would show a stale figure (prd §825)")
        if "asOf" not in pr:
            bad.append("portfolioRead does not stamp the fallback — §83 forbids a dated "
                       "number presented as current (prd §825)")
    if "var asOf: Date?" not in code["WalletPortfolio"]:
        bad.append("WalletPortfolio dropped `asOf` — nothing can carry the stamp (prd §825)")

    # 5 — and it is drawn, and passed.
    if "asOf" not in body(code["WalletFeedTiles"], "struct WalletBalanceHeadline"):
        bad.append("WalletBalanceHeadline no longer draws `asOf` — the crown would show a "
                   "dated figure as though it were current (prd §825)")
    if "asOf: portfolio?.asOf" not in code["FeedScreen"]:
        bad.append("the wallet room no longer passes `asOf` to its crown — the stamp exists "
                   "and reaches nobody (prd §825)")
    return bad


def read() -> dict:
    out = {}
    for name, path in FILES.items():
        if not path.exists():
            print(f"✗ missing: {path}")
            sys.exit(1)
        out[name] = path.read_text()
    return out


def self_test() -> int:
    """Every rule above, broken on purpose. A check that cannot demonstrate it
    catches anything certifies nothing."""
    base = read()
    if audit(base):
        print("✗ self-test: the tree does not pass, so no mutation proves anything")
        for line in audit(base):
            print("   ", line)
        return 1
    ok = True
    cases = [
        ("the whole-map chain filter comes back", "ZerionAPI",
         lambda t: t.replace("let wanted = networks.isEmpty ? Set(networkFor.values) : networks",
                             "let wanted = Set(networkFor.values)")),
        ("the unfiltered retry is dropped", "ZerionAPI",
         lambda t: t.replace("if rows == nil { rows = await dataRows(stem, auth: auth) }", "", 1)),
        ("the Alchemy arm stops isolating", "WalletIngest",
         lambda t: t.replace("networks: [network]", "networks: asked")),
        ("the Alchemy arm stops learning", "WalletIngest",
         lambda t: t.replace("RefusedNetworks.shared.mark(", "RefusedNetworks.shared.noop(")),
        ("a hand-kept unproven list returns", "WalletIngest",
         lambda t: t.replace("    private actor RefusedNetworks {",
                             "    private static let unprovenNetworks: Set<String> = []\n"
                             "    private actor RefusedNetworks {")),
        ("the last-known fallback is dropped", "WalletIngest",
         lambda t: t.replace("groups = lastKnownHoldingsByWallet()", "groups = []")),
        ("the fallback stops being gated on unreached", "WalletIngest",
         lambda t: t.replace("if groups.isEmpty, read.unreached > 0 { groups = lastKnownHoldingsByWallet() }",
                             "if groups.isEmpty { groups = lastKnownHoldingsByWallet() }")),
        ("the portfolio loses its stamp", "WalletPortfolio",
         lambda t: t.replace("var asOf: Date? = nil", "var stampedAt: Date? = nil", 1)),
        ("the crown stops passing the stamp", "FeedScreen",
         lambda t: t.replace("asOf: portfolio?.asOf,", "")),
    ]
    for label, key, mutate in cases:
        texts = dict(base)
        texts[key] = mutate(texts[key])
        if texts[key] == base[key]:
            print(f"✗ self-test: mutation '{label}' changed nothing — it did not run")
            ok = False
            continue
        if not audit(texts):
            print(f"✗ self-test: '{label}' was not caught")
            ok = False
        else:
            print(f"  ok   {label}")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(self_test())
    findings = audit(read())
    if findings:
        print("✗ chain-filter audit findings:")
        for line in findings:
            print("  " + line)
        print("\nOne chain a provider refuses must not empty every wallet's balances, and a "
              "wallet we could not reach must stand on its last reading, stamped (prd §825).")
        sys.exit(1)
    print("✓ chain-filter audit: one refused chain costs only itself, and an unreachable "
          "pass stands on its last reading with a date on it")
