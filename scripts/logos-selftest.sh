#!/bin/zsh
# Casberi Logos self-test — the SHIPPED wire logic behind the Logos seat
# (2026-09-29, prd §988):
#
#   Casberi/Casberi/Model/LogosWire.swift
#     — parseAccountID / watchableID (base58, the Public/Private prefix)
#     — clean / entry / hexKey / isXOnlyKey / accountID (what a paste is, prd §1034)
#     — balance(_:)                  (getAccountBalance, u128 via Decimal)
#     — block(_:)                    (LEZ v0.3's Borsh layout, exact length or nil)
#     — events(_:watched:)           (what a transaction means for one account)
#     — nodeBase / isLoopback / nodeEvents (your own node, prd §989)
#     — nodeMining / nodeTickets and their rows (mining, prd §1016)
#
# Foundation + CryptoKit only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED
# here. The testnet was RESET onto LEZ v0.3 on 2026-09-30 (prd §1007) and the
# v0.2 reader refused every block of it. The real fixture is block 2 of the new
# chain (every block 1…281 decodes to its exact length; its hash resolves with
# getTransaction). No user transaction has run on the reset chain yet, so the
# transfer and private transactions are SYNTHESIZED from LEZ's own v0.3.0
# source (lez/common/src/block.rs, lee/state_machine) — re-measure them
# against the first real one.
#
# WHY A HARNESS. Nothing here can send on LEZ, and a watch is forward-only on a
# quiet testnet, so the landing path runs only when somebody else happens to
# move coins. Every failure below renders as a perfectly good-looking row:
#
#   • a u128 read most-significant-byte first — "Received 40" becomes
#     "Received 53,169,119,831,396,634,916,152,282,411,213,783,040";
#   • the timestamp read as seconds — every row lands in the year 58,660;
#   • the hash taken WITH the variant tag — every row opens a transaction the
#     explorer has never heard of;
#   • sender and recipient swapped — you "received" what you sent;
#   • the node's own per-block transactions not skipped — a row a block, forever;
#   • the producer's key not skipped — every v0.3 block refused;
#   • a trailing byte tolerated — a drifted layout read as garbage amounts;
#   • a Private/ id watched — the sequencer answers it as an empty PUBLIC
#     account, drawn as a confident zero.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/LogosWire.swift"
BRIDGE="Casberi/Casberi/Model/LogosBridge.swift"
SCREEN="Casberi/Casberi/Screens/LogosScreen.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
ROUTING="Casberi/Casberi/Model/BridgeRouting.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$WIRE" "$BRIDGE" "$SCREEN" "$REACH" "$REFRESH" "$ROUTING" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -------------------------------------------------------------
# Comment-stripped copies: the files DOCUMENT what they must never do.
strip() { python3 -c "import re,sys; s=open(sys.argv[1]).read(); s=re.sub(r'/\*.*?\*/','',s,flags=re.S); print(re.sub(r'//[^\n]*','',s))" "$1"; }
guard_fail=0
code="$(strip "$WIRE"; strip "$BRIDGE"; strip "$SCREEN")"
# Conduct: read-only in the strongest grade — no credential, no write method.
# The node's API serves writes beside its reads; only the three GET paths may
# appear (prd §989).
for banned in Authorization sendTransaction requeueCrossZoneDeadLetter '"/leader/claim"' '/pow/claim' '/pow/mining/' '/pow/auto-claim' '/wallet/' '/mempool/add' 'postJSON(base'; do
  if print -r -- "$code" | grep -qF "$banned"; then
    echo "✗ conduct: $banned appears in the Logos seat — it is keyless and read-only"; guard_fail=1
  fi
done
# No invented unit: LEZ has no symbol and no decimals (measured). LGO is the L1's.
if print -r -- "$code" | grep -qE '"[^"]*LGO[^"]*"'; then
  echo "✗ a Logos string names LGO — LEZ amounts carry no unit"; guard_fail=1
fi
grep -q 'hosts: \["testnet.lez.logos.co"' "$REACH" || { echo "✗ the sequencer host is not declared in NetworkReach"; guard_fail=1; }
grep -q 'LogosIngest.refresh(context: context)' "$REFRESH" || { echo "✗ BridgeRefresh does not sweep Logos"; guard_fail=1; }
grep -q 'destination: .logos' "$ROUTING" || { echo "✗ no routing row for Logos"; guard_fail=1; }
grep -q 'Offer(name: "Logos"' "$CATALOG" || { echo "✗ no catalog offer for Logos"; guard_fail=1; }
# The cursor moves per BLOCK, after its rows are inserted — never per page.
grep -q 'store.advance(to: block.id)' "$BRIDGE" || { echo "✗ the walk no longer advances per decoded block"; guard_fail=1; }
# The room keeps the family's words and adds only Node (prd §991) and Rewards
# (prd §1016): a Holdings or Permissions case would be a scope with nothing
# this network can fill.
ROOM="Casberi/Casberi/Model/LogosRoom.swift"
grep -q 'static let order: \[LogosSection\] = \[.home, .activity, .accounts, .node, .rewards\]' "$ROOM" \
  || { echo "✗ LogosSection's scopes moved — Home, Activity, Accounts, Node, Rewards (prd §991, §1016)"; guard_fail=1; }
# What the node EARNED is Rewards', never Node's (prd §1016): every kind that
# lands an earning must be in rewardKinds, or it shows under Node.
grep -q 'static let rewardKinds: Set<String> = \["vouchers", "tickets", "mining", "idle"\]' "$ROOM" \
  || { echo "✗ LogosRoom.rewardKinds moved — vouchers, tickets, mining, idle (prd §1016)"; guard_fail=1; }
# The coin glyph is the app's own symbol: it must exist in the catalog and be
# routed through Image(dsSymbol:), or the tile draws nothing, silently.
[[ -f Casberi/Casberi/Assets.xcassets/coins.stack.symbolset/coins.stack.svg ]] \
  || { echo "✗ coins.stack.symbolset is missing (prd §1016)"; guard_fail=1; }
grep -q '"coins.stack"' Casberi/Casberi/Design/DSSymbol.swift \
  || { echo "✗ DSSymbol.custom does not list coins.stack — the tile would draw nothing"; guard_fail=1; }
grep -q 'Image(dsSymbol: name)' Casberi/Casberi/Design/CategoryGlyph.swift \
  || { echo "✗ CategoryGlyph no longer draws through Image(dsSymbol:)"; guard_fail=1; }
if grep -qE '^\s*case (holdings|permissions|positions|nfts|risk)\b' "$ROOM"; then
  echo "✗ LogosSection grew a scope LEZ cannot fill (prd §991)"; guard_fail=1
fi
(( guard_fail == 0 )) || exit 1
echo "✓ drift guards"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func block(_ b64: String) -> LogosWire.Block? { LogosWire.block(Data(base64Encoded: b64)!) }

func watched(_ ids: String...) -> Set<Data> { Set(ids.map { Data(LogosWire.base58Decode($0)!) }) }

let CBGR = "CbgR6tj5kWx5oziiFptM7jMvrQeYY3Mzaao6ciuhSr2r"
let DUMJ = "DumJ4LCBnHE9jUu2yxPfqdL14g3v756Gzby6LuT9hE51"
let HOLD = "6hCX9ScBrjoE7FabbRfxV4YpGGFbR8CkxYkuW95QNXjp"

print("account ids")
check(LogosWire.parseAccountID(CBGR)?.base58 == CBGR, "a bare base58 id parses to itself")
check(LogosWire.watchableID("Public/" + CBGR) == CBGR, "a Public/ id is watchable")
check(LogosWire.watchableID("  public/" + CBGR + "\n") == CBGR, "the prefix is case-blind and whitespace is trimmed")
check(LogosWire.parseAccountID("Private/" + CBGR)?.visibility == .privateAccount, "a Private/ id parses as private")
check(LogosWire.watchableID("Private/" + CBGR) == nil, "a Private/ id is NOT watchable")
check(LogosWire.parseAccountID("notanaddress") == nil, "garbage is refused")
check(LogosWire.parseAccountID(String(CBGR.dropLast(3))) == nil, "a truncated id is refused (32 bytes or nothing)")
check(LogosWire.parseAccountID("0OIl" + CBGR.dropFirst(4)) == nil, "characters outside base58 are refused")
check(LogosWire.base58Encode(LogosWire.base58Decode(DUMJ)!) == DUMJ, "base58 round-trips")
check(LogosWire.base58Encode([0, 0, 1]) == "112", "leading zero bytes keep their 1s")
check(LogosWire.short(CBGR) == "CbgR…Sr2r", "the short form")

print("what a paste is (prd §1034)")
for wrapped in ["`" + CBGR + "`", "\"" + CBGR + "\"", "“" + CBGR + "”", CBGR + ".", "\u{FEFF}" + CBGR, "<" + CBGR + ">",
                "https://explorer.testnet.lez.logos.co/account/" + CBGR + "?tab=tx", "Public/" + CBGR + ","] {
    check(LogosWire.entry(wrapped) == .account(CBGR), "a paste cleans to the id: \(wrapped.prefix(12))…")
}
check(LogosWire.entry("node.example.com.") == .node("http://node.example.com:8080"), "a node keeps its address, trailing period gone")
// The curve test against Python's Euler criterion (secp256k1, x³ + 7 a square mod p).
let curve: [(String, Bool)] = [
    ("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", true),   // the generator's x
    ("b65bc5ea6bbc6442cfa9ade3efbd9a5165ca6bdd37a0616eca15e010ad8e0dd4", true),   // a key the Logos team sent
    ("4fba1bd3b931f415156cc639f4b1b7973ac8274125129d1adca70e6efeabee1a", false),  // a chat address they sent
    ("fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc30", false),  // past the field prime
    ("2bc27e528f6dfd28bbf31fc4594437e38bb0203c63f4822ebac3a3265d65b94b", true),
    ("08f43bdf7e2b5b16e25acf77593a695d105c864ba75fa96aa8d0ad82a4aa10f4", true),
    ("653e09f78221d08196c394627a320165c301696ae878eea286a5bda877f3160c", true),
    ("57a9a51694bd6cec42e7a5333bf25ba3340d9c892ef78b0f74941859a5065835", false),
    ("5a263d2f55ff21184ebe64b4231bb874835dfa91c3c6b49a5f3843a25876a0fa", true)]
for (hex, want) in curve {
    check(LogosWire.hexKey(hex).map(LogosWire.isXOnlyKey) == want, "curve: \(hex.prefix(8))… is \(want ? "" : "not ")a key")
}
check(LogosWire.entry("b65bc5ea6bbc6442cfa9ade3efbd9a5165ca6bdd37a0616eca15e010ad8e0dd4")
      == .key("9WGi9TEb22h9eVujFZUV6opHwJ7irRmWu2yoGTPa3oBC"), "a hex key watches its account, derived as LEZ does")
check(LogosWire.entry("0xB65BC5EA6BBC6442CFA9ADE3EFBD9A5165CA6BDD37A0616ECA15E010AD8E0DD4")
      == .key("9WGi9TEb22h9eVujFZUV6opHwJ7irRmWu2yoGTPa3oBC"), "0x and capitals are the same key")
check(LogosWire.entry("4fba1bd3b931f415156cc639f4b1b7973ac8274125129d1adca70e6efeabee1a") == .notKey, "hex off the curve is named, never watched")
check(!LogosWire.arms(.notKey) && !LogosWire.arms(.invalid) && LogosWire.arms(.key("x")), "only a readable entry arms the verb")
check(LogosWire.hexKey(String(repeating: "a", count: 63)) == nil, "63 hex characters are not a key")

print("getAccountBalance (v0.3)")
check(LogosWire.balance(1481100) == 1481100, "a bare number is the balance")
check(LogosWire.balance(["nonce": 0, "data": ["shards": [:]]] as [String: Any]) == nil, "getAccount's v0.3 shape is not a balance")
check(LogosWire.decimal("340282366920938463463374607431768211455")?.description == "340282366920938463463374607431768211455", "u128::MAX survives as a string")
check(LogosWire.result(["jsonrpc": "2.0", "error": ["code": -32602]] as [String: Any]) == nil, "an error reply has no result")

print("block 2 — the v0.3 testnet, live (2026-09-30)")
let b2 = block("AgAAAAAAAAA4uwzzSJPklA8P971eY2jZRvRoXYiE/R6z9nTJwVp3Cm0uosxtzORJF4kAcRVBZ2JCYL23Y6JDcP7s8GMQ8AkWdwvM8qABAAAsS7XK+hFm8Wd4NJK5r0htkxeEuo0B8vO91+o5waxd8Sv2daKtZu0lV2LmDTMemRsCDOcz3WrcpMy+/geFW7DZzGE60Go9Rd1bNaFPxh3/REgg/1UU2QZnaQtb/9OGahsCAAAAABW9oLWl1jKV9JM0dmo9GnrN6Ke2Gs7SrX4zTFVzRD3yBAAAAFhiQRCrAUaxIeOhkkuWtUBSNVbiS9XHwH5Sq/pf66+LFb2gtaXWMpX0kzR2aj0aes3op7YaztKtfjNMVXNEPfJ/Gl6dyYFrnVVFr9xtSHsT1KLGj+K6Ox0VNgCzlaW4xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAciTqtuAvizfYQbFjvriwFHCkLnOHXszPzXIYK+GxO1wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB+xkEVTgqEdIUHwDA6JP3Zaeok41C2GZ2lyzEWVvHukAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwDAAAAL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMDEZWKD8YjKnx+berhrNjWxCoyy+ABMV1RwYL+5F4LAynC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDEwGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MBlYoPxiMqfH5t6uGs2NbEKjLL4AExXVHBgv7kXgsDKcAAAAABAAAAB3C8zyoAEAAAIAAAAAAAAAAAAAAAAC")
check(b2?.id == 2, "the block id")
check(b2?.timestamp.timeIntervalSince1970 == 1790779853.687, "the millisecond timestamp, as seconds")
check(b2?.transactions.count == 2, "the node's two per-block transactions")
check(b2?.transactions.last?.hashHex == "f50ad68c6a4d2434415837e05246bb03258ec566900e7f0f36668a3802cd1411", "the hash matches the chain's (getTransaction)")
let system = b2?.transactions ?? []
check(system.allSatisfy { $0.signers == 0 && !$0.paysFee }, "both are unsigned and fee-exempt")
check(system.allSatisfy { LogosWire.events($0, watched: Set($0.accounts.map { Data($0) })).isEmpty },
      "the node's own transactions land nothing even when their accounts are watched")

print("synthetic v0.3 transactions (none has run on the reset chain yet)")
func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
func le64(_ v: UInt64) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
func u128(_ v: UInt64) -> [UInt8] { le64(v) + le64(0) }
func wrap(_ tx: [UInt8]) -> Data {
    Data(le64(7) + [UInt8](repeating: 1, count: 64) + le64(1_790_000_000_000)
         + [UInt8](repeating: 3, count: 32)                              // producer
         + [UInt8](repeating: 2, count: 64) + le32(1) + tx + [0])
}
let native = [UInt8](repeating: 0, count: 32)
let from = LogosWire.base58Decode(CBGR)!, to = LogosWire.base58Decode(DUMJ)!
func publicTx(program: [UInt8], accounts: [[UInt8]], instruction: [UInt8], fee: Bool, signers: Int) -> [UInt8] {
    var t: [UInt8] = [0] + program + le32(UInt32(accounts.count))
    for a in accounts { t += a + native }                                // (account, shard's program)
    t += le32(1) + u128(4)                                               // nonces
    t += le32(UInt32(instruction.count)) + instruction
    t += fee ? [1] + from + le64(10_000) + le64(1) + u128(500) : [0]
    t += le32(UInt32(signers)) + [UInt8](repeating: 9, count: 96 * signers)
    return t
}
let send = publicTx(program: native, accounts: [from, to], instruction: [0] + u128(40), fee: true, signers: 1)
let transfer = LogosWire.block(wrap(send))?.transactions.first
check(transfer?.paysFee == true && transfer?.signers == 1, "a signed, fee-paying transfer decodes")
let both = transfer.map { LogosWire.events($0, watched: watched(CBGR, DUMJ)) } ?? []
check(both.map(\.title) == ["Sent 40 — to DumJ…hE51", "Received 40 — from CbgR…Sr2r"], "sent and received, each from its own side")
check(both.map(\.account) == [CBGR, DUMJ], "each event names the account it is for")
let one = transfer.map { LogosWire.events($0, watched: watched(DUMJ)) } ?? []
check(one.map(\.title) == ["Received 40 — from CbgR…Sr2r"], "the recipient alone sees only the receipt")
check(one.first?.tags == ["Received"], "tagged as state")
let none = transfer.map { LogosWire.events($0, watched: watched(HOLD)) } ?? [LogosWire.Event(account: "", title: "", tags: [])]
check(none.isEmpty, "an unwatched transaction lands nothing")
let big = LogosWire.block(wrap(publicTx(program: native, accounts: [from, to], instruction: [0] + le64(0) + le64(1), fee: true, signers: 1)))?.transactions.first
check(big.map { LogosWire.events($0, watched: watched(DUMJ)).map(\.title) } == ["Received 18,446,744,073,709,551,616 — from CbgR…Sr2r"], "u128: least-significant byte FIRST (the ninth byte is 2^64)")
let other = LogosWire.block(wrap(publicTx(program: [UInt8](repeating: 7, count: 32), accounts: [from, to], instruction: [0] + u128(40), fee: true, signers: 1)))?.transactions.first
check(other.map { LogosWire.events($0, watched: watched(CBGR)).map(\.title) } == ["Used a program"], "another program's call is said, never read as an amount")
let twice = LogosWire.block(wrap(publicTx(program: [UInt8](repeating: 7, count: 32), accounts: [from, from, to], instruction: [], fee: true, signers: 1)))?.transactions.first
check(twice?.accounts.count == 2, "an account selected for two shards is one party")
let deposit = LogosWire.block(wrap(publicTx(program: native, accounts: [from, to], instruction: [0] + u128(40), fee: false, signers: 0)))?.transactions.first
check(deposit.map { LogosWire.events($0, watched: watched(DUMJ)) }?.isEmpty == true, "an unsigned, fee-exempt transaction is the node's own")

var priv: [UInt8] = [1] + le32(1) + from + le32(1) + native + native + le32(2) + [5, 5]   // one public action, one effect
priv += le32(0)                                                                  // nonces
priv += le32(1) + [UInt8](repeating: 3, count: 96) + le32(2) + [1, 2] + le32(1) + [7] + [4]   // one private action
priv += [0] + [1] + le64(5) + [0] + [0]                                          // validity windows
priv += le32(2) + [0] + [UInt8](repeating: 6, count: 64) + [1] + [UInt8](repeating: 6, count: 32)  // image claims
priv += le32(0) + le32(3) + [8, 8, 8]                                            // witness: no sigs, a proof
let p = LogosWire.block(wrap(priv))?.transactions.first
check(p?.kind == .privacyPreserving, "a privacy-preserving transaction decodes")
check(p.map { LogosWire.events($0, watched: watched(CBGR)).map(\.title) } == ["Private transaction"], "only its public side is named")
check(LogosWire.block(wrap([2] + le32(3) + [9, 9, 9])) == nil, "v0.2's deployment variant is refused, not guessed at")

print("exact length")
var raw = Data(base64Encoded: "AgAAAAAAAAA4uwzzSJPklA8P971eY2jZRvRoXYiE/R6z9nTJwVp3Cm0uosxtzORJF4kAcRVBZ2JCYL23Y6JDcP7s8GMQ8AkWdwvM8qABAAAsS7XK+hFm8Wd4NJK5r0htkxeEuo0B8vO91+o5waxd8Sv2daKtZu0lV2LmDTMemRsCDOcz3WrcpMy+/geFW7DZzGE60Go9Rd1bNaFPxh3/REgg/1UU2QZnaQtb/9OGahsCAAAAABW9oLWl1jKV9JM0dmo9GnrN6Ke2Gs7SrX4zTFVzRD3yBAAAAFhiQRCrAUaxIeOhkkuWtUBSNVbiS9XHwH5Sq/pf66+LFb2gtaXWMpX0kzR2aj0aes3op7YaztKtfjNMVXNEPfJ/Gl6dyYFrnVVFr9xtSHsT1KLGj+K6Ox0VNgCzlaW4xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAciTqtuAvizfYQbFjvriwFHCkLnOHXszPzXIYK+GxO1wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB+xkEVTgqEdIUHwDA6JP3Zaeok41C2GZ2lyzEWVvHukAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwDAAAAL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMDEZWKD8YjKnx+berhrNjWxCoyy+ABMV1RwYL+5F4LAynC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDEwGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MBlYoPxiMqfH5t6uGs2NbEKjLL4AExXVHBgv7kXgsDKcAAAAABAAAAB3C8zyoAEAAAIAAAAAAAAAAAAAAAAC")!
check(LogosWire.block(raw.dropLast(1)) == nil, "a truncated block is refused")
raw.append(0)
check(LogosWire.block(raw) == nil, "a block with a trailing byte is refused")
check(!LogosWire.amount(1_000).contains("LGO"), "no unit is invented")

print("your node — the address")
check(LogosWire.nodeBase("127.0.0.1:8080") == "http://127.0.0.1:8080", "host:port")
check(LogosWire.nodeBase("localhost") == "http://localhost:8080", "no port means the node's default, 8080")
check(LogosWire.nodeBase("http://192.168.1.5") == "http://192.168.1.5:8080", "a scheme without a port still means 8080, never 80")
check(LogosWire.nodeBase("https://node.example.com:9000/") == "https://node.example.com:9000", "a full URL keeps its port, loses its slash")
check(LogosWire.nodeBase("http://x/path") == nil, "a path is refused — the node answers at its root")
check(LogosWire.nodeBase("ftp://x") == nil && LogosWire.nodeBase("two words") == nil, "not an address")
check(LogosWire.isLoopback("http://127.0.0.1:8080") && LogosWire.isLoopback("http://localhost:8080") && LogosWire.isLoopback("http://[::1]:8080"), "loopback in every spelling")
check(!LogosWire.isLoopback("http://192.168.1.5:8080") && !LogosWire.isLoopback("http://10.0.0.2:8080"), "a network address is not loopback")

print("your node — the reads (shapes from logos-blockchain @11711d3)")
let info = LogosWire.nodeInfo(["cryptarchia_info": ["lib": "aa", "lib_slot": 10, "tip": "bb", "slot": 12, "height": 71763, "state": "Online"], "phase": "Following"] as [String: Any])
check(info?.height == 71763 && info?.tip == "bb" && info?.phase == "Following", "cryptarchia/info, nested")
check(LogosWire.nodeInfo(["height": 5, "tip": "cc"] as [String: Any])?.height == 5, "a flat reply still reads")
check(LogosWire.nodeInfo(["code": 404, "message": "x"] as [String: Any]) == nil, "an error body is not a reading")
check(LogosWire.nodePeers(["n_peers": 8, "n_connections": 9] as [String: Any]) == 8, "network/info peers")
let v = LogosWire.nodeVouchers(["tip": "bb", "vouchers": [["commitment": "c1", "nullifier": "n1"], ["commitment": "c2", "nullifier": "n2"]], "reward_amount": 600, "total_claimable": 1200] as [String: Any])
check(v?.count == 2 && v?.claimable == 1200, "leader/claim/vouchers")

print("your node — what lands")
let synced = LogosWire.NodeSnapshot(reachable: true, phase: "Following", height: 71763, tip: "bb", peers: 8, vouchers: 0, claimable: 0)
let syncing = LogosWire.NodeSnapshot(reachable: true, phase: "InitialBlockDownload", height: 100, tip: "aa", peers: 3, vouchers: 0, claimable: 0)
check(LogosWire.nodeEvents(old: nil, new: synced).isEmpty, "first sight lands nothing — a node already in sync did not just sync")
check(LogosWire.nodeEvents(old: syncing, new: synced).map(\.title) == ["Your node is in sync — height 71,763"], "catching up lands once")
check(LogosWire.nodeEvents(old: synced, new: syncing).map(\.title) == ["Your node fell behind"], "falling behind lands")
check(LogosWire.nodeEvents(old: synced, new: .unreachable).map(\.title) == ["Your node stopped answering"], "going quiet lands")
let downWhileSynced = synced.remembering(synced).remembering(nil)
let keptDown = LogosWire.NodeSnapshot.unreachable.remembering(synced)
check(downWhileSynced == synced && keptDown.phase == "Following" && !keptDown.reachable, "a reading while down keeps the last-known state, marked down")
check(LogosWire.nodeEvents(old: keptDown, new: synced).map(\.title) == ["Your node is answering"], "coming back in sync says only that it is answering")
var keptPaid = synced; keptPaid.vouchers = 2; keptPaid.claimable = 1200
let paidDown = LogosWire.NodeSnapshot.unreachable.remembering(keptPaid)
check(LogosWire.nodeEvents(old: paidDown, new: keptPaid).map(\.title) == ["Your node is answering"], "vouchers held before going down are not news on return")
check(LogosWire.nodeEvents(old: .unreachable, new: synced).map(\.title) == ["Your node is answering", "Your node is in sync — height 71,763"], "first reachable reading after an unknown down: answering, and in sync")
check(LogosWire.nodeEvents(old: keptDown, new: .unreachable).isEmpty, "still down is not news")
var more = synced; more.peers = 30; more.height = 80000
check(LogosWire.nodeEvents(old: synced, new: more).isEmpty, "peers and height moving are not rows")
var paid = synced; paid.vouchers = 2; paid.claimable = 1200
check(LogosWire.nodeEvents(old: synced, new: paid).map(\.title) == ["2 reward vouchers ready — 1,200 claimable"], "a new voucher lands with what it is worth")
check(LogosWire.nodeEvents(old: paid, new: paid).isEmpty, "the same vouchers do not land twice")
var claimed = paid; claimed.vouchers = 1; claimed.claimable = 600
check(LogosWire.nodeEvents(old: paid, new: claimed).isEmpty, "claiming one is not news")
var worthless = synced; worthless.vouchers = 1; worthless.claimable = 0
check(LogosWire.nodeEvents(old: synced, new: worthless).isEmpty, "a voucher worth nothing yet (before its epoch) does not land")
check(LogosWire.nodeLine(synced) == "In sync · height 71,763 · 8 peers", "the roster line")

print("your node — mining (shapes from logos-blockchain 0.3.0, services/pow/src/service.rs)")
let status = LogosWire.nodeMining(["is_mining": true, "are_rewards_enabled": true,
                                   "auto_claim": ["is_armed": false, "tick": ["unit": "seconds", "value": 10], "targets": []]] as [String: Any])
check(status?.mining == true && status?.pays == true, "pow/status reads mining and whether it pays")
check(LogosWire.nodeMining(["code": 500, "message": "x"] as [String: Any]) == nil, "an error body is not a mining reading")
check(LogosWire.nodeTickets(["claimable_tickets": 3, "slots_until_expiry": [120, 240, 299]] as [String: Any]) == 3, "pow/rewards/claimable reads the ticket count")
check(LogosWire.nodeTickets(["error": "x"] as [String: Any]) == nil, "no count is not zero")
var idle = synced; idle.mining = false; idle.tickets = 0
var mining = synced; mining.mining = true; mining.tickets = 0
check(LogosWire.nodeEvents(old: idle, new: mining).map(\.title) == ["Your node started mining"], "mining starting lands")
check(LogosWire.nodeEvents(old: mining, new: idle).map(\.title) == ["Your node stopped mining"], "mining stopping lands")
var won = mining; won.tickets = 3
check(LogosWire.nodeEvents(old: mining, new: won).map(\.title) == ["3 mining tickets ready"], "tickets rising land with their count")
check(LogosWire.nodeEvents(old: won, new: mining).isEmpty, "tickets claimed is not news")
check(LogosWire.nodeEvents(old: won, new: won).isEmpty, "the same tickets do not land twice")
check(LogosWire.nodeEvents(old: synced, new: won).isEmpty, "first sight of mining (an older reading) lands nothing")
var lost = won; lost.mining = nil; lost.tickets = nil
check(LogosWire.nodeEvents(old: lost, new: won).isEmpty, "a failed mining read, then a good one, is not news")
check(LogosWire.nodeEvents(old: synced, new: paid).first?.tags == ["Rewards", "Voucher"], "a voucher is a reward")
check(LogosWire.nodeLine(won) == "In sync · height 71,763 · 8 peers · mining", "the roster line says mining")
check(LogosWire.nodeLine(.unreachable) == "Not answering", "the roster line, unreachable")

if failures > 0 { print("✗ \(failures) assertion(s) failed"); exit(1) }
print("✓ all assertions passed")
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$WIRE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the harness did not compile against the shipped LogosWire:"
  sed -n '1,40p' "$TMP/build.log"
  exit 1
fi
"$TMP/run" || exit 1

# --- mutations ----------------------------------------------------------------
echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$WIRE" "$WORK/LogosWire.swift"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/LogosWire.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1; fi
  if cmp -s "$WIRE" "$WORK/LogosWire.swift"; then
    echo "  ✗ $name — the mutation changed nothing"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/LogosWire.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "u128 read most-significant first" \
  'for byte in b.reversed() { value = value * 256 + Decimal(byte) }' \
  'for byte in b { value = value * 256 + Decimal(byte) }'
mutate "the timestamp read as seconds" \
  'Date(timeIntervalSince1970: Double(ms) / 1000)' \
  'Date(timeIntervalSince1970: Double(ms))'
mutate "the hash taken with the variant tag" \
  'let start = r.offset' \
  'let start = r.offset - 1'
mutate "a trailing byte tolerated" \
  'guard let status = r.u8(), status < 3, r.atEnd else { return nil }' \
  'guard let status = r.u8(), status < 3 else { return nil }'
mutate "the node's own transactions not skipped" \
  'if tx.signers == 0 && !tx.paysFee { return [] }' \
  'if tx.signers < 0 && !tx.paysFee { return [] }'
mutate "the producer's key not skipped" \
  'let ms = r.u64(), r.skip(32 + 64),' \
  'let ms = r.u64(), r.skip(64),'
mutate "any program read as the native token" \
  'if tx.program == nativeProgram, tx.accounts.count == 2,' \
  'if tx.accounts.count == 2,'
mutate "sender and recipient swapped" \
  'i == 1
                    ? Event(account: id(1), title: "Received' \
  'i == 0
                    ? Event(account: id(1), title: "Received'
mutate "a private id made watchable" \
  'guard let id = parseAccountID(raw), id.visibility != .privateAccount else { return nil }' \
  'guard let id = parseAccountID(raw) else { return nil }'
mutate "any length accepted as an id" \
  'guard let bytes = base58Decode(text), bytes.count == 32 else { return nil }' \
  'guard let bytes = base58Decode(text), bytes.count > 0 else { return nil }'

mutate "the node's first reading lands rows" \
  'guard let old else { return [] }' \
  'let old = old ?? NodeSnapshot.unreachable'
mutate "a voucher lands whenever any are held" \
  'if let count = new.vouchers, count > (old.vouchers ?? 0),' \
  'if let count = new.vouchers, count > 0,'
mutate "no port means 80" \
  'return "\(scheme)://\(hostPart):\(url.port ?? 8080)"' \
  'return "\(scheme)://\(hostPart):\(url.port ?? 80)"'
mutate "a down reading forgets what the node held" \
  'guard !reachable, var kept = last else { return self }' \
  'guard !reachable, var kept = Optional(self), last != nil else { return self }'
mutate "tickets land on first sight" \
  'if let before = old.tickets, let count = new.tickets, count > before {' \
  'if let count = new.tickets, count > (old.tickets ?? 0) {'
mutate "a mining change read from one side" \
  'if let was = old.mining, let now = new.mining, was != now {' \
  'if let now = new.mining, old.mining != now {'
mutate "mining stopping lands as starting" \
  'NodeEvent(kind: "idle", title: "Your node stopped mining"' \
  'NodeEvent(kind: "idle", title: "Your node started mining"'
mutate "the ticket count read from the wrong key" \
  '["claimable_tickets"] as? NSNumber' \
  '["slots_until_expiry"] as? NSNumber'
mutate "hex watched without the curve test" \
  'guard isXOnlyKey(bytes) else { return .notKey }' \
  'guard !bytes.isEmpty else { return .notKey }'
mutate "the key's id derived without its padding" \
  '[UInt8](repeating: 0, count: 5)' \
  '[UInt8](repeating: 0, count: 0)'
mutate "a sentence's period kept" \
  'let trailing = CharacterSet(charactersIn: ".,;!")' \
  'let trailing = CharacterSet(charactersIn: ",;!")'
mutate "the explorer link not unwrapped" \
  'if let range = text.range(of: "/account/", options: .backwards) {' \
  'if let range = text.range(of: "/account-never/", options: .backwards) {'
mutate "a network address read as loopback" \
  'host.hasPrefix("127.")' \
  'host.hasPrefix("1")'

echo "✓ Logos self-test passed"
