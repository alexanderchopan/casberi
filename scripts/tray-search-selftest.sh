#!/bin/zsh
# Casberi tray-search self-test — the rules behind the tray's one search,
# grouped by category (prd §1185):
#
#   Casberi/Casberi/Model/TraySearch.swift  (compiled whole)
#
# WHY A HARNESS. Every failure here draws a plausible list. "eth" matching
# "something" floods Wallet with nonsense; "ethereum" missing your ETH says you
# hold none; Markets trailing Day on "meta" buries the exact hit; a typo row
# that shows when a real hit exists pushes the hit down.
#
# Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/TraySearch.swift"
TRAY="Casberi/Casberi/Shell/RoomsTray.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }

# The tray uses the rules: it groups through TraySearch, and the search runs
# after a pause, outside the body.
grep -q 'TraySearch.groups(' "$TRAY" \
  || { echo "✗ the tray no longer groups its hits through TraySearch.groups"; exit 1; }
grep -q 'TraySearch.closest(' "$TRAY" \
  || { echo "✗ the tray no longer offers the closest names when nothing matches"; exit 1; }
grep -q '\.task(id: query)' "$TRAY" \
  || { echo "✗ the tray's search no longer runs after a pause — it would rebuild in every body"; exit 1; }
grep -q 'MarketsIndex.matches(' "$TRAY" \
  || { echo "✗ the tray no longer finds a company by its ticker or an app it makes"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp "$SRC" "$TMP/"
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
typealias C = TraySearch.Candidate

// ── Words ────────────────────────────────────────────────────────────
check(TraySearch.normalized("  $PEPE ") == "PEPE", "a leading $ is dropped")
check(TraySearch.match("Spotify", "spotify") == .exact, "the whole name is exact, any case")
check(TraySearch.match("Spotify Technology", "spot") == .prefix, "the start is a prefix")
check(TraySearch.match("Meta for Developers", "dev") == .word, "a word's start is a word match")
check(TraySearch.match("Coinbase", "base") == .inside, "three letters inside a name match")
check(TraySearch.match("Coinbase", "ba") == nil, "two letters inside a name do not")
check(TraySearch.match("Something new", "eth", anyWord: true) == nil, "a sentence never matches inside a word")
check(TraySearch.match("Sent 0.5 ETH to Uniswap", "eth", anyWord: true) == .word, "a sentence matches at a word")
check(TraySearch.match("Lisbon trip plan", "trip lis") == .word, "several words match in any order")
check(TraySearch.match("Café", "cafe") == .exact, "accents fold")

// ── Coins by any name ────────────────────────────────────────────────
let eth = C(index: 0, group: "Wallet", name: "ETH", aliases: TraySearch.aliases(forSymbol: "ETH"), tier: .money)
check(TraySearch.match(eth, "ethereum") == .exact, "ethereum finds ETH")
check(TraySearch.match(eth, "$eth") == .exact, "$eth finds ETH")
check(TraySearch.match(eth, "ether") == .exact, "ether finds ETH")
let ethThing = C(index: 1, group: "Wallet", name: "Sent 0.5 ETH to Uniswap", tier: .thing, anyWord: true)
check(TraySearch.match(ethThing, "ethereum") != nil, "ethereum finds a transfer that says ETH")
check(TraySearch.match(ethThing, "ethereum") != .exact, "another name never scores exact")
check(TraySearch.otherNames("BTC") == ["Bitcoin"], "BTC's other name is Bitcoin")
check(TraySearch.otherNames("zzz").isEmpty, "a stranger has no other names")

// ── Groups: "meta" ───────────────────────────────────────────────────
let meta: [C] = [
    C(index: 0, group: "Wallet", name: "MetaMask Card"),
    C(index: 1, group: "Day", name: "Meta earnings call"),
    C(index: 2, group: "Day", name: "Meta for Developers"),
    C(index: 3, group: "Agents", name: "Muse", aliases: ["Meta"]),
    C(index: 4, group: "Markets", name: "Meta", aliases: ["META"], tier: .money),
    C(index: 5, group: "Social", name: "Threads", aliases: ["Meta"], tier: .add),
    C(index: 6, group: "Reading", name: "Our gametapes, sorted", tier: .thing, anyWord: true),
]
let dock = ["Wallet", "Work", "Day", "Agents", "Social", "Reading"]
let g = TraySearch.groups(meta, query: "meta", standing: nil, dockOrder: dock)
check(g.first?.name == "Markets", "an exact name leads its group to the top (\(g.map(\.name)))")
check(g.map(\.name) == ["Markets", "Wallet", "Day", "Agents", "Social"], "then the dock's order (\(g.map(\.name)))")
check(!g.contains { $0.name == "Reading" }, "a sentence with the letters inside a word is no hit")
let standing = TraySearch.groups(meta, query: "meta", standing: "Day", dockOrder: dock)
check(standing.first?.name == "Day", "the group you stand in leads")
let spotify: [C] = [
    C(index: 0, group: "Markets", name: "Spotify", aliases: ["SPOT"], tier: .money),
    C(index: 1, group: "Media", name: "Spotify"),
    C(index: 2, group: "Wallet", name: "Spotify Premium", tier: .money),
]
let sp = TraySearch.groups(spotify, query: "spotify", standing: nil, dockOrder: ["Wallet", "Media"]).map(\.name)
check(sp == ["Media", "Markets", "Wallet"], "the app's group before its stock's on a tie (\(sp))")

// ── Inside a group ───────────────────────────────────────────────────
let wallet: [C] = [
    C(index: 0, group: "Wallet", name: "Sent 1 ETH", tier: .thing, anyWord: true),
    C(index: 1, group: "Wallet", name: "Swapped ETH", tier: .thing, anyWord: true),
    C(index: 2, group: "Wallet", name: "Got ETH back", tier: .thing, anyWord: true),
    C(index: 3, group: "Wallet", name: "ETH", tier: .money),
    C(index: 4, group: "Wallet", name: "Ether.fi Cash", tier: .add),
    C(index: 5, group: "Wallet", name: "stETH", tier: .money),
]
let w = TraySearch.groups(wallet, query: "eth", standing: nil, dockOrder: dock)[0].hits.map(\.index)
check(w.first == 3, "the exact ETH leads (\(w))")
let named = TraySearch.groups([C(index: 0, group: "Wallet", name: "ether.fi"),
                               C(index: 1, group: "Wallet", name: "ETH", tier: .money)],
                              query: "eth", standing: nil, dockOrder: dock)[0].hits.map(\.index)
check(named == [1, 0], "an exact match leads a name of a better tier (\(named))")
check(w.filter { [0, 1, 2].contains($0) }.count == TraySearch.thingCap, "at most two things (\(w))")
check(w.count <= TraySearch.groupCap, "a group draws at most four")
check(w.contains(5), "stETH finds by a word inside it")

// ── Nothing matched ──────────────────────────────────────────────────
let names = ["Spotify", "Spotify Technology", "Shopify", "Slack"]
let near = TraySearch.closest("spotfy", among: names)
check(near.first == 0 && near.contains(1), "a typo reaches Spotify and its company (\(near))")
check(!near.contains(3), "and not Slack")
check(TraySearch.closest("spo", among: names).isEmpty, "under four letters nothing is close")
check(TraySearch.distance("spotfy", "spotify", cap: 2) == 1, "one letter missing is one edit")
check(TraySearch.distance("sptoify", "spotify", cap: 2) == 1, "two letters swapped is one edit")

// ── What the words are ───────────────────────────────────────────────
check(TraySearch.isEVMAddress("0x71C7656EC7ab88b098defB751B7401B5f6d8976F"), "a pasted address is an address")
check(!TraySearch.isEVMAddress("0x71C7"), "a stub is not")
check(TraySearch.looksLikeTicker("$qzx"), "a short word could be a ticker")
check(!TraySearch.looksLikeTicker("spotify"), "a long word is not")

if failures > 0 { print("✗ tray search: \(failures) failing"); exit(1) }
print("✓ tray search self-test passed")
SWIFT

swiftc -O -o "$TMP/tray" "$TMP/TraySearch.swift" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/tray" ]] || { echo "✗ tray search harness did not compile"; exit 1; }
"$TMP/tray"
