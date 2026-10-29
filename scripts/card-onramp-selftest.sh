#!/bin/zsh
# Move › Buy (prd §1599): which seller a network gets, and the page it
# opens. A network with no seller that drew the act, Ramp offered with no
# key (its page refuses to draw), Stripe handed Base (its no-account link
# takes none), or a dollar figure mangled into the URL would each open a
# page that cannot sell — and nothing on Move's screen would say so.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/CardOnramp.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias C = CardOnramp
let me = "0xDE70a11ce0C4F7e2b9a1D3C5e7F90B2D4a6c8e01"
func query(_ u: URL?) -> [String: String] {
    Dictionary((URLComponents(url: u ?? URL(string: "x:")!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
}

// Which seller.
check(C.seller(chainId: 1, rampKey: nil) == .stripe, "Ethereum is Stripe's")
check(C.seller(chainId: 8453, rampKey: nil) == nil, "Base offers no card without Ramp's key")
check(C.seller(chainId: 8453, rampKey: "k") == .ramp, "Base is Ramp's with its key")
check(C.seller(chainId: 42161, rampKey: "k") == nil, "a network with no seller offers none")
check(C.seller(chainId: 1, rampKey: "k") == .stripe, "Ethereum stays Stripe's with Ramp's key")
check(!C.Seller.stripe.takesAddress && C.Seller.ramp.takesAddress, "only Ramp's page takes the address")

// Stripe's page.
let s = C.url(.usdc, chainId: 1, address: me, dollars: "50", rampKey: nil)
check(s?.host == "crypto.link.com", "Stripe opens crypto.link.com")
let sq = query(s)
check(sq["destination_currency"] == "usdc" && sq["destination_network"] == "ethereum", "Stripe is told the coin and network")
check(sq["supported_destination_currencies"] == "usdc" && sq["supported_destination_networks"] == "ethereum", "Stripe offers that coin only")
check(sq["source_amount"] == "50" && sq["source_currency"] == "usd", "Stripe is told the dollars")
check(sq["wallet_address"] == nil && !(s?.absoluteString.contains(me) ?? true), "Stripe's link carries no address")
check(query(C.url(.eth, chainId: 1, address: me, rampKey: nil))["destination_currency"] == "eth", "ETH buys ETH")
check(query(C.url(.usdc, chainId: 1, address: me, dollars: "", rampKey: nil))["source_amount"] == nil, "no dollars leaves the amount to the page")
check(query(C.url(.usdc, chainId: 1, address: me, dollars: "12.5", rampKey: nil))["source_amount"] == "12.50", "cents are kept")

// Ramp's page.
check(C.url(.usdc, chainId: 8453, address: me, rampKey: nil) == nil, "no key, no Ramp page")
let r = C.url(.usdc, chainId: 8453, address: me, dollars: "50", rampKey: "pk")
let rq = query(r)
check(r?.host == "app.ramp.network", "Ramp opens app.ramp.network")
check(rq["hostApiKey"] == "pk" && rq["userAddress"] == me, "Ramp is handed the key and the address")
check(rq["enabledCryptoAssets"] == "BASE_USDC", "Ramp sells USDC on Base")
check(query(C.url(.eth, chainId: 8453, address: me, rampKey: "pk"))["enabledCryptoAssets"] == "BASE_ETH", "and ETH on Base")
check(rq["inAsset"] == "USD" && rq["inAssetValue"] == "5000", "Ramp counts the dollars in cents")
check(C.url(.usdc, chainId: 8453, address: "0x123", rampKey: "pk") == nil, "a malformed address is never handed to Ramp")

// Typed dollars.
check(C.wholeCents("50") == 5000 && C.wholeCents("12.345") == 1234, "dollars to whole cents, rounded down")
check(C.wholeCents("12,5") == 1250, "a comma is the decimal mark")
check(C.wholeCents("") == nil && C.wholeCents("0") == nil && C.wholeCents("abc") == nil && C.wholeCents("-5") == nil, "nothing, zero, words and negatives are no amount")
check(C.dollarsText(5000) == "50" && C.dollarsText(1205) == "12.05", "cents back to dollars")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   one seller per network, Ramp only with its key, the page told the coin, network and dollars")
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
mutate "Ramp offered with no key"     's/case base: rampKey == nil \? nil : \.ramp/case base: .ramp/'
mutate "Base handed to Stripe"        's/case base: rampKey == nil \? nil : \.ramp/case base: .stripe/'
mutate "Stripe told to take the address" 's/var takesAddress: Bool \{ self == \.ramp \}/var takesAddress: Bool { true }/'
mutate "Ramp handed a bad address"    's/guard let rampKey, isEVMAddress\(address\) else/guard let rampKey else/'
mutate "dollars, not cents, to Ramp"  's/value: String\(usd\)\)\]/value: dollarsText(usd))]/'
mutate "the comma dropped"            's/: t\.replacingOccurrences\(of: ",", with: "\."\)/: t.replacingOccurrences(of: ",", with: "")/'
mutate "the wrong Ramp asset"         's/"BASE_\\\(coin\.symbol\)"/"ETH_\\(coin.symbol)"/'
