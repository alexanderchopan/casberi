#!/bin/zsh
# holdings-check-selftest.sh — the Wallet's holdings checked against Ethereum
# itself (prd §1825).
#
# Compiles the real rules (`Model/HoldingsCheck.swift`, Foundation-only) and
# drives them: what is picked, when two amounts agree, the two-in-a-row
# ledger, the key a row's `Part` finds. Then asserts the USE: a check starts
# only off a live holdings read, never in the demo, and both holding rows read
# the verdict. Mutations prove the assertions bite, each checked to have
# changed the source.
set -euo pipefail
cd "$(dirname "$0")/.."
RULES="Casberi/Casberi/Model/HoldingsCheck.swift"
STORE="Casberi/Casberi/Model/HoldingsCheckStore.swift"
INGEST="Casberi/Casberi/Model/WalletIngest.swift"
HIDDEN="Casberi/Casberi/Model/HiddenTokens.swift"
ROWS="Casberi/Casberi/Screens/WalletTokens.swift"
HOME="Casberi/Casberi/Screens/FeedScreen+WalletPages.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$RULES" "$STORE" "$INGEST" "$HIDDEN" "$ROWS" "$HOME" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
echo "holdings-check self-test"
use() { grep -qF -- "$2" "$1" || { echo "✗ $3"; exit 1; } }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "  ok   \(what)" : "  ✗ \(what)"); if !ok { failures += 1 } }
typealias H = HoldingsCheck
let usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
let weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

// What is picked.
let picked = H.pick(network: ["eth-mainnet", "eth-mainnet", "base-mainnet", "eth-mainnet", "eth-mainnet", "eth-mainnet"],
                    contract: [nil, usdc, usdc, weth, "venue:aave", "0x0000000000000000000000000000000000000001"],
                    amount: [1.5, 100, 50, 0.2, 9, nil],
                    usd: [4500, 100, 50, 0.5, 900, 10])
check(picked.map(\.contract) == [nil, usdc.lowercased()], "Ethereum only, a dollar or more, an address, an amount, biggest first")
let many = H.pick(network: Array(repeating: "eth-mainnet", count: 12),
                  contract: (0..<12).map { String(format: "0x%040x", $0 + 1) },
                  amount: Array(repeating: 1, count: 12), usd: (0..<12).map { Double(100 - $0) })
check(many.count == H.cap && many.first?.usd == 100, "at most cap, the biggest kept")

// When two amounts agree.
check(H.matches(read: 100.0, proven: 100.00001), "a part in ten million is rounding")
check(!H.matches(read: 100.0, proven: 100.01), "a cent in a hundred is a different balance")
check(H.matches(read: 0, proven: 0), "zero is zero")
check(!H.matches(read: 1.5, proven: 0), "held against nothing differs")
check(H.verdict(read: 1, proven: nil) == nil, "no proof is no verdict")
check(H.verdict(read: 1, proven: "nonsense") == nil, "an unreadable proof is no verdict")
check(H.verdict(read: 1.5, proven: "1.5") == true, "a proven amount that agrees matches")

// The ledger: two in a row.
var l = H.Ledger()
let k = H.key(owner: "0xABC0000000000000000000000000000000000001", contract: nil)
l.record(k, matched: false)
check(l.mismatched.isEmpty && l.suspect == [k], "one disagreement is a suspicion")
l.record(k, matched: nil)
check(l.mismatched.isEmpty && l.suspect == [k], "no proof changes nothing")
l.record(k, matched: false)
check(l.mismatched == [k] && l.suspect.isEmpty, "two in a row is a mismatch")
l.record(k, matched: false)
check(l.mismatched == [k], "a mismatch stands while it differs")
l.record(k, matched: true)
check(l.mismatched.isEmpty && l.suspect.isEmpty, "one agreement clears it")
l.record(k, matched: false)
l.record(k, matched: true)
check(l.suspect.isEmpty && l.mismatched.isEmpty, "a suspicion cleared never becomes a mismatch")
// finish: only the wallet's own keys, only those not checked.
var f = H.Ledger()
let a1 = H.key(owner: "0xaaa0000000000000000000000000000000000001", contract: nil)
let a2 = H.key(owner: "0xaaa0000000000000000000000000000000000001", contract: usdc)
let b1 = H.key(owner: "0xbbb0000000000000000000000000000000000002", contract: nil)
for key in [a1, a2, b1] { f.record(key, matched: false); f.record(key, matched: false) }
f.finish(owner: "0xAAA0000000000000000000000000000000000001", checked: [a1])
check(f.mismatched == [a1, b1], "a holding no longer checked says nothing; another wallet's stays")

// The key a row's Part finds: owner, then HiddenTokens.contractKey's spelling.
check(H.key(owner: "0xABC", contract: nil) == "0xabc:eth-mainnet:native", "ETH's key")
check(H.key(owner: "0xABC", contract: usdc) == "0xabc:eth-mainnet:" + usdc.lowercased(), "a token's key")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
SWIFT
swiftc -O -o "$TMP/run" "$RULES" "$TMP/main.swift" 2>&1 | grep -v "^$" | head -20 || true
[[ -x "$TMP/run" ]] || { echo "✗ the rules did not compile"; exit 1; }
"$TMP/run" || { echo "✗ the holdings check's rules fail their own self-test"; exit 1; }

# Drift guards: the USE.
use "$HIDDEN" '"\(network):\(contract ?? "native")".lowercased()' "HiddenTokens.contractKey changed spelling, so no row finds a holdings verdict"
awk '/private static func fetchHeldTokensUncached/,/^    }$/' "$INGEST" > "$TMP/uncached"
use "$TMP/uncached" "HoldingsCheckStore.shared.consider(owner: owner, held: picked)" "a live holdings read no longer starts a check"
if awk '/private static func fetchHeldTokensDated/,/^    }$/' "$INGEST" | grep -q "HoldingsCheckStore"; then
  echo "✗ a window's hit starts a check (once a window at most)"; exit 1
fi
use "$STORE" "!DemoMode.isActive" "the demo's wallets are checked against Ethereum"
use "$STORE" "Date().timeIntervalSince(lastRun[owner] ?? .distantPast) > HoldingsCheck.every" "a wallet is checked more than once a window"
use "$STORE" "PrivacyEngine.shared.verifyHoldings(owner: owner, tokens: held.map(\\.contract))" "the store no longer asks the verified provider"
# Since prd §1954 the row reads the verdict once, as `twoLine` (its pitch
# rides it), and the amber line stands on it.
use "$ROWS" "var twoLine: Bool { HoldingsCheckStore.shared.mismatched(position) }" "the Tokens list no longer reads whether a holding matches"
awk '/struct WalletTokenRowLabel/,/^}$/' "$ROWS" | grep -A1 "if twoLine {" | grep -q "Doesn't match Ethereum" \
  || { echo "✗ the Tokens list no longer says a holding doesn't match"; exit 1; }
use "$HOME" "let differs = HoldingsCheckStore.shared.mismatched(token)" "Home's tokens no longer say a holding doesn't match"
use "$REACH" 'Endpoint(service: "Wallet check",' "the check's hosts are not declared"
awk '/Endpoint\(service: "Wallet check",/,/throughTor: true\)/' "$REACH" | grep -q "throughTor: true" \
  || { echo "✗ the check's reads do not go through Tor"; exit 1; }

# Mutations: each must change the source and fail the rules.
mutate() {
  local what="$1" pattern="$2"
  cp "$RULES" "$TMP/mut.swift"
  perl -0pi -e "$pattern" "$TMP/mut.swift"
  cmp -s "$RULES" "$TMP/mut.swift" && { echo "✗ mutation did not change the source: $what"; exit 1; }
  if swiftc -O -o "$TMP/mut" "$TMP/mut.swift" "$TMP/main.swift" >/dev/null 2>&1 && "$TMP/mut" >/dev/null 2>&1; then
    echo "✗ survives: $what"; exit 1
  fi
  echo "  ok   catches  $what"
}
mutate "one disagreement is a mismatch" 's/\} else if suspect\.contains\(key\) \|\| mismatched\.contains\(key\) \{/} else if true {/'
mutate "rounding reads as a different balance" 's/scale \* 1e-6/scale * 0/'
mutate "Base is checked against Ethereum" 's/where network\[i\] == Self\.network/where true/'
mutate "the cap is lost" 's/\.prefix\(cap\)\)/)/'
mutate "finish clears another wallet's verdict" 's/!\$0\.hasPrefix\(prefix\) \|\| checked\.contains\(\$0\)/checked.contains(\$0)/g'
mutate "no proof clears a suspicion" 's/guard let matched else \{ return \}/let matched = matched ?? true/'
echo "✓ holdings check: picked, compared, two in a row; started off a live read only, never in the demo, drawn on both rows; 6 mutations"
