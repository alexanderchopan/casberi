#!/bin/zsh
# Dust-sweep self-test (prd §1537) — Move › Sweep: every token on one network
# under $1 (or $5) swapped for ETH in one transaction:
#
#   Casberi/Casberi/Model/DustSweep.swift   compiled WHOLE and unmodified
#
# The failures that cost money or trust, each one silent until it signs:
#
#   • A STRANGER'S TOKEN SOLD. Most dust is airdropped, and selling it calls
#     its own contract: only what Relay verified, or a swap here bought.
#   • ROUND-UPS' CHANGE SWEPT. The change waits in the network's dollar.
#   • A TOKEN WITH NO PRICE SWEPT. Nothing says it is under the line.
#   • ETH SOLD FOR ETH. It is what comes back.
#   • A SWAP THAT RETURNS LESS THAN HALF. Relay's flat fee on a few cents.
#   • A LINE OTHER THAN $1 OR $5. The setting takes those two only.
#   • A BATCH PAST TEN SWAPS. The rest wait for the next sweep.
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

SWEEP="Casberi/Casberi/Model/DustSweep.swift"
[[ -f "$SWEEP" ]] || { echo "✗ $SWEEP not found"; exit 1; }
TMP=$(mktemp -d /tmp/dust-sweep-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The demo's switch, the one name DustSweep reaches outside itself.
cat > "$TMP/stubs.swift" <<'SWIFT'
enum YourAccountDemo { static var isOn = false }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
typealias D = DustSweep
func h(_ symbol: String, _ usd: Double?, trusted: Bool = true, dollar: Bool = false,
       native: Bool = false, units: String = "1000") -> D.Holding {
    // A contract spelled from the symbol: distinct, and the same every run.
    let hex = symbol.utf8.map { String(format: "%02x", $0) }.joined()
    let contract: String? = native ? nil : "0x" + String(repeating: "0", count: max(0, 40 - hex.count)) + hex
    return .init(symbol: symbol, contract: contract, decimals: 18, units: units, usd: usd, trusted: trusted, isDollar: dollar)
}

// ── What is swept ────────────────────────────────────────────────────────
let eth = h("ETH", 0.40, native: true)
let aero = h("AERO", 0.55)
let degen = h("DEGEN", 0.12)
let usdc = h("USDC", 0.70, dollar: true)
let pepe = h("PEPE2", 0.24, trusted: false)
let mystery = h("MYST", nil)
let big = h("CBBTC", 118.0)
let three = h("MORPHO", 3.10)
let empty = h("ZERO", 0.0, units: "0")
let all = [eth, aero, degen, usdc, pepe, mystery, big, three, empty]

let one = D.plan(all, under: 1, roundUpsWaiting: false)
check(one.sweeps.map(\.symbol) == ["USDC", "AERO", "DEGEN"], "under $1, most dollars first: \(one.sweeps.map(\.symbol))")
check(!one.sweeps.contains { $0.isNative } && !one.stays.contains { $0.0.isNative }, "ETH is never swept, nor named as staying")
check(one.stays.contains { $0.0.symbol == "PEPE2" && $0.1 == .notVerified }, "a stranger's token stays, named")
check(one.stays.contains { $0.0.symbol == "MYST" && $0.1 == .noPrice }, "a token with no price stays, named")
check(!one.sweeps.contains { $0.symbol == "CBBTC" } && !one.stays.contains { $0.0.symbol == "CBBTC" }, "over the line is not dust, and not listed")
check(!one.sweeps.contains { $0.symbol == "MORPHO" }, "$3.10 is over $1")
check(!one.sweeps.contains { $0.symbol == "ZERO" } && !one.stays.contains { $0.0.symbol == "ZERO" }, "nothing held is nothing listed")
check(abs(one.sweptUSD - (0.70 + 0.55 + 0.12)) < 0.0001, "the swept dollars are the sweeps'")
check(one.rows.prefix(3).allSatisfy { $0.stay == nil } && one.rows.dropFirst(3).allSatisfy { $0.stay != nil }
      && one.rows.count == one.sweeps.count + one.stays.count, "the rows are the sweeps, then the stays")

let five = D.plan(all, under: 5, roundUpsWaiting: false)
check(five.sweeps.map(\.symbol) == ["MORPHO", "USDC", "AERO", "DEGEN"], "under $5 takes $3.10 too: \(five.sweeps.map(\.symbol))")
check(D.plan(all, under: 3, roundUpsWaiting: false) == one, "a line other than $1 or $5 is $1")
check(D.plan([h("EDGE", 1.0)], under: 1, roundUpsWaiting: false).sweeps.isEmpty, "exactly $1 is not under $1")

let waiting = D.plan(all, under: 1, roundUpsWaiting: true)
check(waiting.stays.contains { $0.0.symbol == "USDC" && $0.1 == .roundUps } && !waiting.sweeps.contains { $0.isDollar },
      "the dollar stays while round-ups count change in it")
let out = D.plan(all, under: 1, roundUpsWaiting: false, leftOut: [aero.id])
check(out.stays.contains { $0.0.symbol == "AERO" && $0.1 == .leftOut } && !out.sweeps.contains { $0.symbol == "AERO" },
      "a token you took out stays, named")

let many = (0..<13).map { h("T\($0)", 0.5 - Double($0) * 0.01) }
let capped = D.plan(many, under: 1, roundUpsWaiting: false)
check(capped.sweeps.count == D.maxSwaps, "ten swaps at most in one sweep")
check(capped.stays.filter { $0.1 == .nextSweep }.count == 3, "the rest wait for the next sweep")
check(capped.sweeps.first?.symbol == "T0", "the biggest go first")

// ── Relay's answers ──────────────────────────────────────────────────────
// ETH at $4,000: 0.0001 ETH is $0.40.
let quotes: [String: String] = [
    usdc.id: "170000000000000",   // $0.68 for $0.70
    aero.id: "50000000000000",    // $0.20 for $0.55: under half
]
let judged = D.judged(one, back: { quotes[$0] }, ethPrice: 4_000)
check(judged.sweeps.map(\.symbol) == ["USDC"], "only what returns half or more: \(judged.sweeps.map(\.symbol))")
check(judged.stays.contains { $0.0.symbol == "AERO" && $0.1 == .costsMore }, "a swap returning under half stays, named")
check(judged.stays.contains { $0.0.symbol == "DEGEN" && $0.1 == .noRoute }, "no quote is no route")
check(judged.stays.contains { $0.0.symbol == "PEPE2" && $0.1 == .notVerified }, "the plan's own stays are kept")
let unpriced = D.judged(one, back: { quotes[$0] }, ethPrice: nil)
check(unpriced.sweeps.map(\.symbol) == ["USDC", "AERO"], "no ETH price keeps every quoted token")
let zero = D.judged(one, back: { _ in "0" }, ethPrice: 4_000)
check(zero.sweeps.isEmpty, "a quote of nothing is no route")

// ── Base units ───────────────────────────────────────────────────────────
check(D.total(["170000000000000", "50000000000000"]) == "220000000000000", "the ETH back sums exactly")
check(D.total([]) == "0", "nothing back is zero")
check(D.total(["12.5", "1"]) == "1", "a fraction is not base units")
check(D.isPositive("1") && !D.isPositive("0") && !D.isPositive("000") && !D.isPositive("") && !D.isPositive("-1"), "positive base units")
check(D.dollars("1000000000000000000", decimals: 18, price: 4_000).map { abs($0 - 4_000) < 0.0001 } == true, "one ETH at $4,000")
check(D.dollars("0x10", decimals: 18, price: 1) == nil, "hex is not base units")

if failures > 0 { print("✗ dust-sweep-selftest: \(failures) failure(s)"); exit(1) }
print("✓ dust-sweep-selftest: the line, the stays and Relay's answers hold")
SWIFT

swiftc -O -o "$TMP/run" "$SWEEP" "$TMP/stubs.swift" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ dust-sweep-selftest did not compile"; exit 1; }
"$TMP/run"
