#!/bin/zsh
# Spend pays with anything (prd §1666): ETH or USDC on Base or Ethereum is
# turned into USDC on Base first. What is sold must cover the card with room,
# a short quote must be asked again for more, and only Base and Ethereum's
# ETH and dollar may pay — or the card is refused at Bitrefill after a swap
# the person already signed, or a token nothing here can turn into dollars
# is offered.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/SpendTopUp.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias T = SpendTopUp
let baseUSDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
let ethUSDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

// Who pays.
check(T.direct(contract: baseUSDC, dollar: baseUSDC, chainId: 8453), "USDC on Base pays as it is")
check(!T.direct(contract: nil, dollar: baseUSDC, chainId: 8453), "ETH on Base is not USDC")
check(!T.direct(contract: ethUSDC, dollar: ethUSDC, chainId: 1), "USDC on Ethereum is not on Base")
check(T.pays(contract: nil, dollar: baseUSDC, chainId: 8453) && T.pays(contract: nil, dollar: ethUSDC, chainId: 1)
      && T.pays(contract: ethUSDC.uppercased(), dollar: ethUSDC, chainId: 1), "ETH and the dollar on Base and Ethereum pay")
check(!T.pays(contract: "0x940181a94a35a4569e4529a3cdfb74e38fd98631", dollar: baseUSDC, chainId: 8453), "any other token pays")
check(!T.pays(contract: nil, dollar: "0x5fc5360d0400a0fd4f2af552add042d716f1d168", chainId: 4663), "Robinhood pays")

// What is sold: $52.50 of ETH at $2,500 is 0.021 ETH, and 3% more.
check(T.estimate(cost: "52500000", price: 2500, decimals: 18) == "21630000000000000", "ETH for $52.50 is not 0.02163: \(T.estimate(cost: "52500000", price: 2500, decimals: 18) ?? "nil")")
check(T.estimate(cost: "52500000", price: 1, decimals: 6) == "54075000", "USDC for $52.50 is not 54.075")
check(T.estimate(cost: "1", price: 3000, decimals: 18).map { $0 != "0" } == true, "a cent of a cent sells nothing")
check(T.estimate(cost: "0", price: 1, decimals: 6) == nil && T.estimate(cost: "100", price: 0, decimals: 6) == nil
      && T.estimate(cost: "100", price: .nan, decimals: 6) == nil, "no cost or no price still sells")
// Short: sold 100, minimum 90, cost 99 → 100 × 99 / 90 × 1.01 = 111.1 → 112.
check(T.rescale(sold: "100", minimum: "90", cost: "99") == "112", "a short quote does not ask for enough more: \(T.rescale(sold: "100", minimum: "90", cost: "99") ?? "nil")")
check(T.rescale(sold: "100", minimum: "0", cost: "99") == nil, "a quote of nothing is scaled")
// Covered by the minimum only.
check(T.covers(minimum: "52500000", cost: "52500000") && !T.covers(minimum: "52499999", cost: "52500000"),
      "a minimum a unit short covers the card")
check(T.covers(minimum: "100000000000000000000000", cost: "52500000"), "a long minimum is misread")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   ETH and USDC on Base and Ethereum, sold with room, asked again when short")
SWIFT

xcrun swiftc -O "$SRC" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped source did not compile"
"$work/t" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/m.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 || fail "mutation did not compile: $why"
  if "$work/m" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "no headroom"                  's/static let headroomBps = 300/static let headroomBps = 0/'
mutate "rounded down"                 's/NSDecimalRound\(&r, &x, 0, \.up\)/NSDecimalRound(&r, &x, 0, .down)/'
mutate "the hope covers"              's/return m >= c/return m + 1 >= c/'
mutate "any network pays"             's/guard chainId == base \|\| chainId == ethereum else \{ return false \}/guard chainId > 0 else { return false }/'
mutate "any token pays"               's/return contract == nil \|\| contract\?\.lowercased\(\) == dollar\.lowercased\(\)/return true/'
mutate "a short quote asks the same"  's/return whole\(s \* c \/ m \* Decimal\(string: "1\.01"\)!\)/return whole(s)/'
mutate "Ethereum USDC pays directly"  's/chainId == base && contract != nil/contract != nil/'
