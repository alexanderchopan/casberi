#!/bin/zsh
# Casberi zFi + Tacit self-test (2026-10-12, prd §1281):
#
#   Casberi/Casberi/Model/ZFiWire.swift
#     — swapOrders / swapOrdersV1 / auctions / bids  (zFi's three boards, read whole)
#     — symbol / decimals                            (the escrowed tokens' names)
#     — title / state / needsYou                     (the Positions row's words)
#   Casberi/Casberi/Model/Tacit.swift
#     — verb                                         (a pool move named Deposited / Withdrew)
#
# Pure, local, deterministic, against replies saved off mainnet
# (scripts/fixtures/zfi/*.json). Every failure below is a clean row that
# says something false about real money:
#
#   • a stranger's order drawn as yours (the holder filter dropped);
#   • a closed order drawn (Swapboard's `active`, a lot's or bid's zero
#     seller/bidder ignored) — escrow that already went back, counted again;
#   • an expired order read as open — money waiting on the board, never said;
#   • a bid's escrow read off the wrong word — "0.06 WETH" that isn't there;
#   • a hostile symbol drawn on a row, or a garbage offset trapping the read;
#   • a router's leg titled "Deposited", or a pool payout titled anything
#     but "Withdrew".
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/ZFiWire.swift"
TACIT="Casberi/Casberi/Model/Tacit.swift"
APP="Casberi/Casberi/Model/ZFiOrders.swift"
FIX="scripts/fixtures/zfi"
for f in "$WIRE" "$TACIT" "$APP" "$FIX"/swapboard-orders.json "$FIX"/swapboard-v1-orders.json "$FIX"/dutchboard-listings.json \
         "$FIX"/floorboard-bids.json "$FIX"/symbol-z.json "$FIX"/symbol-mkr.json "$FIX"/symbol-weth.json "$FIX"/symbol-zzz.json; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done
# The app half: keyless, through the Wallet's own mainnet pool only.
# The one URL is a door the person opens (an order's receipt), never fetched.
if grep -nE 'https?://' "$APP" | grep -v '^\s*[0-9]*:\s*///' | grep -v 'content: "https://etherscan.io/nft/' | grep -q .; then
  echo "✗ ZFiOrders.swift names a host; it reads through WalletApprovals' mainnet pool only"; exit 1
fi
# The rule lives in WalletNeedsYou since §1329 (Home and Day both ask it);
# the Wallet hands it the live book.
grep -q 'if ref.hasPrefix(ZFiOrders.reclaimPrefix) { return ZFiOrders.stillWaiting(ref: ref, in: zfi) }' \
  Casberi/Casberi/Model/WalletNeedsYou.swift || { echo "✗ a waiting zFi escrow no longer leads Needs you"; exit 1; }
grep -q 'let zfi = walletLive.zfiOrders' Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift \
  || { echo "✗ the Wallet no longer hands Needs you the live zFi book"; exit 1; }
grep -q 'if ref.hasPrefix("zfi:reclaim:") { return .poolCleared }' Casberi/Casberi/Model/NotifySweep.swift \
  || { echo "✗ a waiting zFi escrow no longer notifies"; exit 1; }
grep -q 'await ZFiOrders.syncEvents(context: context, addresses: evmAddresses, existing: existing)' \
  Casberi/Casberi/Model/WalletIngest.swift || { echo "✗ the Wallet sweep no longer lands zFi's waiting escrow"; exit 1; }
grep -q 'WalletApprovals.rpcRead(network: network' "$APP" \
  || { echo "✗ ZFiOrders no longer reads through the Wallet's mainnet pool"; exit 1; }
grep -q 'async let zfiBook = ZFiOrders.book(addresses: resolved)' Casberi/Casberi/Model/WalletWarnings.swift \
  || { echo "✗ the Wallet's live read no longer asks for zFi orders"; exit 1; }
grep -q 'WalletZFiOrdersCard(book: walletLive.zfiOrders)' Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift \
  || { echo "✗ Positions no longer draws zFi orders"; exit 1; }
grep -q 'let verb = Tacit.verb(counterparty: cp, received: received)' Casberi/Casberi/Model/WalletIngest.swift \
  || { echo "✗ the Wallet no longer titles Tacit's pool moves"; exit 1; }
grep -q '"0x000000000000fb114709235f1ccbffb925f600e4": "zFi"' Casberi/Casberi/Model/WalletIngest.swift \
  || { echo "✗ zRouter is no longer named"; exit 1; }

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let fix = ProcessInfo.processInfo.environment["ZFI_FIX"]!
func reply(_ name: String) -> String? {
    let d = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: fix + "/" + name))) as! [String: Any]
    return d["result"] as? String
}
// 2026-10-12 00:00 UTC — the day the fixtures were read.
let now = Date(timeIntervalSince1970: 1_791_763_200)
let zorz = "0x1c0aa8ccd568d90d61659f060d1bfb1e6f855a20"
let maker = "0xe04885c3f1419c6e8495c33bdcf5f8387cd88846"
let v1maker = "0x9a50a078d80f36e38edfae85affa2b8ab458e2c9"
let ops = "0x006cd14f36f65ecbb29b2519ccbe63a0dc8549f2"
let stranger = "0x" + String(repeating: "1", count: 40)
let z = "0x00a6ba94bbb5474725515de88fe04f854f2dcb12"
let weth = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
let zzz = "0x00000000008835cef3e0d2333695f288ee6b63a6"
let tokens: [String: ZFiWire.Token] = [z: .init(symbol: "Z", decimals: 18), weth: .init(symbol: "WETH", decimals: 18),
                                       zzz: .init(symbol: "zzz", decimals: nil)]

print("Swapboard")
let v2 = ZFiWire.swapOrders(reply: reply("swapboard-orders.json"), firstID: 0, holders: [maker])
check(v2?.map(\.id) == [9, 10], "a maker's two open orders, by id: \(v2?.map(\.id) ?? [])")
check(ZFiWire.swapOrders(reply: reply("swapboard-orders.json"), firstID: 0, holders: [stranger])?.isEmpty == true,
      "a wallet with no orders holds none")
check(ZFiWire.swapOrders(reply: reply("swapboard-orders.json"), firstID: 0, holders: ["0x357836ffcb45307fa7ff2a574f505753c961902b"])?.isEmpty == true,
      "six filled or cancelled orders keep their maker, and none is drawn")
check(ZFiWire.swapOrders(reply: reply("swapboard-orders.json"), firstID: 0, holders: Set([zorz, maker]))?.count == 3,
      "two holders, three orders")
let ten = v2?.first { $0.id == 10 }
check(ten?.escrowToken == z && ten.flatMap { ZFiWire.amount($0.escrowRaw, z, tokens) } == 1_000, "order 10 escrows 1,000 Z")
check(ten.flatMap { ZFiWire.phrase($0.otherRaw, $0.otherToken, tokens) } == "0.3 WETH", "…and asks 0.3 WETH")
check(ten.map { ZFiWire.needsYou($0, now: now) } == true, "expired in August: its escrow waits for you")
check(ten.map { ZFiWire.state($0, tokens, now: now) } == "Expired · cancel to reclaim", "…and the row says so")
check(ten.map { ZFiWire.needsYou($0, now: Date(timeIntervalSince1970: 1_787_771_000)) } == false, "before its expiry it is open")
check(ten.map { ZFiWire.state($0, tokens, now: Date(timeIntervalSince1970: 1_787_771_000)) } == "Open · asks 0.3 WETH",
      "…asking its price")
check(ten.map { ZFiWire.title($0, tokens) } == "Sell Z for WETH", "titled by its pair")
check(ten.map { ZFiWire.reclaimTitle($0, tokens) } == "Your 1,000 Z can be taken back from zFi", "Needs you says what waits")
let v1 = ZFiWire.swapOrdersV1(reply: reply("swapboard-v1-orders.json"), firstID: 0, holders: [v1maker])
check(v1?.map(\.id) == [7, 142, 143], "v1's closed book: a maker's three open orders still hold escrow")
check(v1?.allSatisfy { $0.board == ZFiWire.swapboardV1 && $0.expiry == nil } == true, "v1 orders never expire")
check(ZFiWire.swapOrders(reply: String((reply("swapboard-orders.json") ?? "").dropLast(64)), firstID: 0, holders: [maker]) == nil,
      "a short reply is nothing")

print("Dutchboard")
let lots = ZFiWire.auctions(reply: reply("dutchboard-listings.json"), holders: [zorz])
check(lots?.count == 1 && lots?.first?.id == 0, "z0r0z's live lot")
let lot = lots?.first
check(lot.flatMap { ZFiWire.amount($0.escrowRaw, z, tokens) } == 1_000 && lot?.otherToken == ZFiWire.ether, "1,000 Z for ETH")
check(lot.map { ZFiWire.state($0, tokens, now: now) } == "At its floor · 1 ETH", "past its window, resting at its floor")
check(ZFiWire.auctions(reply: reply("dutchboard-listings.json"), holders: [ZFiWire.ether])?.isEmpty == true,
      "a closed lot (zero seller) belongs to nobody")
let expired = ZFiWire.auctions(reply: reply("dutchboard-listings.json"), holders: ["0x5833869fdeb4d371b854d7474f5f84b43320fd05"])?.first
check(expired.map { ZFiWire.needsYou($0, now: now) } == true
      && expired.map { ZFiWire.state($0, tokens, now: now) } == "Expired · cancel to reclaim",
      "a lot past its expiry waits for you")

print("Floorboard")
let bids = ZFiWire.bids(reply: reply("floorboard-bids.json"), holders: [ops])
check(bids?.count == 1 && bids?.first?.id == 3, "the ops multisig's live bid")
let bid = bids?.first
check(bid.flatMap { ZFiWire.phrase($0.escrowRaw, $0.escrowToken, tokens) } == "0.05984 WETH", "escrow is `locked`, in WETH")
check(bid.map { ZFiWire.title($0, tokens) } == "Bid for 10,770.56 Z", "titled by what it buys")
check(bid.map { ZFiWire.state($0, tokens, now: now) } == "Closed · cancel to reclaim", "its window closed: escrow waits")
check(bid.map { ZFiWire.reclaimTitle($0, tokens) } == "Your 0.05984 WETH can be taken back from zFi", "…a bid's escrow is its quote")
let nft = ZFiWire.bids(reply: reply("floorboard-bids.json"), holders: [zorz])?.first
check(nft?.otherIsNFT == true && nft.map { ZFiWire.title($0, tokens) } == "Bid for 1 zzz", "an NFT bid counts pieces")
check(ZFiWire.bids(reply: reply("floorboard-bids.json"), holders: [ZFiWire.ether])?.isEmpty == true, "closed bids belong to nobody")
check(ZFiWire.bids(reply: reply("floorboard-bids.json"), holders: [ops, zorz, ZFiWire.ether])?.count == 2, "…however the holders are listed")
let garbage = "0x" + String(repeating: "f", count: 64 * 4)
check(ZFiWire.bids(reply: garbage, holders: [ops]) == nil && ZFiWire.auctions(reply: garbage, holders: [ops]) == nil,
      "garbage offsets are nothing, never a trap")
let skew = "0x" + ZFiWire.word(33) + String((reply("floorboard-bids.json") ?? "").dropFirst(2 + 64))
check(ZFiWire.bids(reply: skew, holders: [ops]) == nil, "a head offset that is not a whole word is nothing")
var bidWords = ZFiWire.words(reply("floorboard-bids.json"))!.map(String.init)
bidWords[2] = ZFiWire.word(ZFiWire.small(Substring(bidWords[2]))! + 1)
check(ZFiWire.bids(reply: "0x" + bidWords.joined(), holders: [ops]) == nil, "a tuple offset that is not a whole word is nothing")

print("tokens")
check(ZFiWire.symbol(reply: reply("symbol-weth.json")) == "WETH", "an ABI string")
check(ZFiWire.symbol(reply: reply("symbol-mkr.json")) == "MKR", "a bytes32 symbol (MKR)")
check(ZFiWire.symbol(reply: reply("symbol-z.json")) == "Z" && ZFiWire.symbol(reply: reply("symbol-zzz.json")) == "zzz",
      "a one-letter symbol, and an NFT collection's")
func encoded(_ s: String) -> String {
    let hex = s.utf8.map { String(format: "%02x", $0) }.joined()
    return "0x" + ZFiWire.word(32) + ZFiWire.word(s.utf8.count) + hex + String(repeating: "0", count: 64 - hex.count % 64)
}
check(ZFiWire.symbol(reply: encoded("VISIT x.io")) == nil, "a symbol with a space is not drawn")
check(ZFiWire.symbol(reply: encoded("CLAIMREWARDS")) == nil, "a twelve-letter symbol is not drawn")
check(ZFiWire.decimals(reply: "0x" + ZFiWire.word(18)) == 18 && ZFiWire.decimals(reply: "0x" + ZFiWire.word(77)) == nil,
      "decimals past 36 are not believed")
check(ZFiWire.symbol(ZFiWire.ether, [:]) == "ETH" && ZFiWire.symbol(stranger, [:]) == "...1111", "ETH by address, an unknown by its tail")

print("Tacit")
let pool = "0x000000c2A20657CE25f2Ba99737933D031AFBEE9"
check(Tacit.verb(counterparty: pool, received: false) == .deposited, "ETH into the pool: deposited")
check(Tacit.verb(counterparty: pool, received: true) == .withdrew, "ETH out of the pool: withdrew")
check(Tacit.verb(counterparty: "0x0000008ebbf2323f95c4fbc18254f3d65c53998c", received: false) == .deposited, "a token into the zap: deposited")
check(Tacit.verb(counterparty: "0x0000008ebbf2323f95c4fbc18254f3d65c53998c", received: true) == nil, "a refund from the zap is no withdrawal")
check(Tacit.verb(counterparty: "0x0000006c96afa6f1cd4df8fe19bc0d8b6a6cd7b5", received: false) == nil
      && Tacit.knownName(for: "0x0000006c96afa6f1cd4df8fe19bc0d8b6a6cd7b5") == "Tacit", "the router is named, no verb")
check(Tacit.title(.withdrew, amount: "0.88", asset: "ETH") == "Withdrew 0.88 ETH from Tacit", "the venue grammar")
check(Tacit.knownName(for: stranger) == nil, "anything else is not Tacit")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "ZFiWire + Tacit, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "Casberi/Shared/AddressTail.swift" "$WIRE" "$TACIT" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1
fi
ZFI_FIX="$PWD/$FIX" "$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/ZFiWire.swift"; cp "$TACIT" "$WORK/Tacit.swift"
  local target="$WORK/$(basename "$file")"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if cmp -s "$file" "$target"; then echo "  ✗ $name — changed nothing"; exit 1; fi
  if ! swiftc -Onone -o "$TMP/mut" "Casberi/Shared/AddressTail.swift" "$WORK/ZFiWire.swift" "$WORK/Tacit.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if ZFI_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "a stranger's order taken" "$WIRE" \
  'guard flag(f[1]), let maker = address(f[0]), holders.contains(maker),' \
  'guard flag(f[1]), let maker = address(f[0]),'
mutate "a closed Swapboard order drawn" "$WIRE" \
  'guard flag(f[1]), let maker = address(f[0]), holders.contains(maker),
                  let tokenA = address(f[7])' \
  'guard let maker = address(f[0]), holders.contains(maker),
                  let tokenA = address(f[7])'
mutate "an expired order read as open" "$WIRE" \
  'return o.expiry.map { $0 < now } ?? false
        case .auction, .bid:' \
  'return false
        case .auction, .bid:'
mutate "a bid's escrow off the wrong word" "$WIRE" \
  'let locked = uint(f[9])' \
  'let locked = uint(f[10])'
mutate "a closed lot (zero seller) drawn" "$WIRE" \
  'let seller = address(f[1]), seller != ether, holders.contains(seller),' \
  'let seller = address(f[1]), holders.contains(seller),'
mutate "a dynamic tuple read inline" "$WIRE" \
  'guard let w = words(hex), let rows = tuples(w, fields: 15, dynamic: true) else { return nil }
        var out: [Order] = []
        for f in rows.map(Array.init) {
            guard let id = small(f[0]), let bidder' \
  'guard let w = words(hex), let rows = tuples(w, fields: 15, dynamic: false) else { return nil }
        var out: [Order] = []
        for f in rows.map(Array.init) {
            guard let id = small(f[0]), let bidder'
mutate "an unaligned offset trusted" "$WIRE" \
  'guard base + 1 + k < w.count, let off = small(w[base + 1 + k]), off % 32 == 0 else { return nil }' \
  'guard base + 1 + k < w.count, let off = small(w[base + 1 + k]) else { return nil }'
mutate "a hostile symbol drawn" "$WIRE" \
  's.allSatisfy({ $0.isLetter || $0.isNumber || "._-+$".contains($0) })' \
  '!s.isEmpty'
mutate "a zap refund titled a withdrawal" "$TACIT" \
  'if entrances.contains(a), !received { return .deposited }' \
  'if entrances.contains(a) { return received ? .withdrew : .deposited }'
mutate "the router given a verb" "$TACIT" \
  'if pools.contains(a) { return received ? .withdrew : .deposited }' \
  'if pools.contains(a) || named.contains(a) { return received ? .withdrew : .deposited }'

echo "✓ zFi + Tacit self-test passed"
