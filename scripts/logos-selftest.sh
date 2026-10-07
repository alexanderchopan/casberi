#!/bin/zsh
# Casberi Logos self-test — the SHIPPED wire logic behind the Logos seat
# (2026-09-29, prd §988):
#
#   Casberi/Casberi/Model/LogosWire.swift
#     — parseAccountID / watchableID (base58, the Public/Private prefix)
#     — clean / entry / hexKey / isXOnlyKey / accountID (what a paste is, prd §1034)
#     — header / isSystem / showsResetNote (resets and network accounts, prd §1035)
#     — balance(_:)                  (getAccountBalance, u128 via Decimal)
#     — block(_:)                    (LEZ v0.3's Borsh layout, exact length or nil)
#     — events(_:watched:)           (what a transaction means for one account)
#     — nodeBase / isLoopback / nodeEvents (your own node, prd §989)
#     — nodeMining / nodeTickets and their rows (mining, prd §1016)
#     — tokenCall / tokenEvents / shards / tokenHolding / tokenName (prd §1084)
#     — transferMessage / messageHash / publicTransaction / refusal (sending, prd §1084)
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
# Conduct: the WATCH is read-only in the strongest grade — no credential, no
# write method. The node's API serves writes beside its reads; only the GET
# paths may appear (prd §989). Sending (prd §1084) lives in LogosSend.swift
# alone: the wire builds bytes, the bridge and the page never submit them.
for banned in Authorization sendTransaction requeueCrossZoneDeadLetter '"/leader/claim"' '/pow/claim' '/pow/mining/' '/pow/auto-claim' '/wallet/' '/mempool/add' 'postJSON(base'; do
  if print -r -- "$code" | grep -qF "$banned"; then
    echo "✗ conduct: $banned appears in the Logos seat — it is keyless and read-only"; guard_fail=1
  fi
done
# No invented unit: LEZ has no symbol and no decimals (measured). LGO is the L1's.
if print -r -- "$code" | grep -qE '"[^"]*LGO[^"]*"'; then
  echo "✗ a Logos string names LGO — LEZ amounts carry no unit"; guard_fail=1
fi
SEND="Casberi/Casberi/Model/LogosSend.swift"
ROOM_FILE="Casberi/Casberi/Model/LogosRoom.swift"
KEY="Casberi/Casberi/Model/LogosKey.swift"
grep -q '"sendTransaction"' "$SEND" || { echo "✗ LogosSend no longer submits through sendTransaction"; guard_fail=1; }
for f in "$KEY" "$ROOM_FILE" Casberi/Casberi/Screens/FeedScreen+LogosRoom.swift Casberi/Casberi/Screens/LogosRoomCard.swift; do
  if strip "$f" | grep -qF 'sendTransaction'; then
    echo "✗ conduct: sendTransaction appears in $f — LogosSend.swift is the one door"; guard_fail=1
  fi
done
# Its own Keychain service: never another seat's key (prd §1084).
for other in casberi-frames-signer casberi-hegota-signer casberi-dev-signer; do
  if grep -qF "$other" "$KEY"; then echo "✗ LogosKey names $other — a different chain's key"; guard_fail=1; fi
done
grep -q 'service = "casberi-logos-signer"' "$KEY" || { echo "✗ LogosKey's service moved"; guard_fail=1; }
grep -q 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' "$KEY" || { echo "✗ LogosKey is not device-only"; guard_fail=1; }
# Every signature is verified against this phone's key before it leaves.
strip "$KEY" | grep -q 'isValidSignature(signature, for: HashDigest(hash))' \
  || { echo "✗ LogosKey.sign no longer verifies its own signature"; guard_fail=1; }
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
# Activity and Accounts went with the merge (prd §1039): Home lists the moves,
# the account menu picks the account. Holdings arrived with v0.3's token
# shards. No verb is a tile (prd §1108): Create heads the Accounts menu and
# Send leads Holdings, so the enum is the four scopes and nothing else.
grep -q 'static let order: \[LogosSection\] = \[.home, .chat, .holdings, .node\]' "$ROOM" \
  || { echo "✗ LogosSection's scopes moved — Home, Chat, Holdings, Node (prd §991, §1084, §1155)"; guard_fail=1; }
if grep -qE '^\s*case (create|explorer|send)\b' "$ROOM"; then
  echo "✗ a Logos verb is a tile again — Create is the menu's first row, Send leads Holdings (prd §1108)"; guard_fail=1
fi
grep -q 'accountAction: LogosSection.canCreate' Casberi/Casberi/Screens/FeedScreen+LogosRoom.swift \
  || { echo "✗ Logos' New account left the Accounts menu (prd §1108)"; guard_fail=1; }
# What the node EARNED rides Node since §1155 (no Rewards tile): every node
# row is Node's, so none can fall between two tiles.
grep -q 'static func isNodeRef(_ ref: String?) -> Bool { nodeKind(ofRef: ref) != nil }' "$ROOM" \
  || { echo "✗ LogosRoom.isNodeRef no longer takes every node row (prd §1155)"; guard_fail=1; }
# The coin glyph is the app's own symbol: it must exist in the catalog and be
# routed through Image(dsSymbol:), or the tile draws nothing, silently.
[[ -f Casberi/Casberi/Assets.xcassets/coins.stack.symbolset/coins.stack.svg ]] \
  || { echo "✗ coins.stack.symbolset is missing (prd §1016)"; guard_fail=1; }
grep -q '"coins.stack"' Casberi/Casberi/Design/DSSymbol.swift \
  || { echo "✗ DSSymbol.custom does not list coins.stack — the tile would draw nothing"; guard_fail=1; }
grep -q 'Image(dsSymbol: name)' Casberi/Casberi/Design/CategoryGlyph.swift \
  || { echo "✗ CategoryGlyph no longer draws through Image(dsSymbol:)"; guard_fail=1; }
if grep -qE '^\s*case (permissions|positions|nfts|risk|activity|accounts)\b' "$ROOM"; then
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

print("a reset, said (prd §1035)")
let reset = Date(timeIntervalSince1970: 1790779853.687)   // block 2 of the 9-30 chain
let day: TimeInterval = 86400
check(LogosWire.showsResetNote(chainStart: reset, now: reset + day, balances: [0]), "an empty account the day after a reset: say it")
check(LogosWire.showsResetNote(chainStart: reset, now: reset + day, balances: [nil, 5, 0]), "one empty account among others is enough")
check(!LogosWire.showsResetNote(chainStart: reset, now: reset + day, balances: [5, nil]), "no account reads zero: nothing to explain")
check(!LogosWire.showsResetNote(chainStart: reset, now: reset + day, balances: [nil]), "an unread balance is not a zero")
check(!LogosWire.showsResetNote(chainStart: reset, now: reset + 31 * day, balances: [0]), "a month on, an empty account is just quiet")
check(!LogosWire.showsResetNote(chainStart: nil, now: reset, balances: [0]), "no chain read yet: nothing to say")

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
let B2 = "AgAAAAAAAAA4uwzzSJPklA8P971eY2jZRvRoXYiE/R6z9nTJwVp3Cm0uosxtzORJF4kAcRVBZ2JCYL23Y6JDcP7s8GMQ8AkWdwvM8qABAAAsS7XK+hFm8Wd4NJK5r0htkxeEuo0B8vO91+o5waxd8Sv2daKtZu0lV2LmDTMemRsCDOcz3WrcpMy+/geFW7DZzGE60Go9Rd1bNaFPxh3/REgg/1UU2QZnaQtb/9OGahsCAAAAABW9oLWl1jKV9JM0dmo9GnrN6Ke2Gs7SrX4zTFVzRD3yBAAAAFhiQRCrAUaxIeOhkkuWtUBSNVbiS9XHwH5Sq/pf66+LFb2gtaXWMpX0kzR2aj0aes3op7YaztKtfjNMVXNEPfJ/Gl6dyYFrnVVFr9xtSHsT1KLGj+K6Ox0VNgCzlaW4xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAciTqtuAvizfYQbFjvriwFHCkLnOHXszPzXIYK+GxO1wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB+xkEVTgqEdIUHwDA6JP3Zaeok41C2GZ2lyzEWVvHukAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwDAAAAL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMDEZWKD8YjKnx+berhrNjWxCoyy+ABMV1RwYL+5F4LAynC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDEwGVig/GIyp8fm3q4azY1sQqMsvgATFdUcGC/uReCwMpwvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MBlYoPxiMqfH5t6uGs2NbEKjLL4AExXVHBgv7kXgsDKcAAAAABAAAAB3C8zyoAEAAAIAAAAAAAAAAAAAAAAC"
let b2 = block(B2)
check(b2?.id == 2, "the block id")
check(b2?.timestamp.timeIntervalSince1970 == 1790779853.687, "the millisecond timestamp, as seconds")
check(b2?.transactions.count == 2, "the node's two per-block transactions")
check(b2?.transactions.last?.hashHex == "f50ad68c6a4d2434415837e05246bb03258ec566900e7f0f36668a3802cd1411", "the hash matches the chain's (getTransaction)")
let system = b2?.transactions ?? []
check(system.allSatisfy { $0.signers == 0 && !$0.paysFee }, "both are unsigned and fee-exempt")
check(system.allSatisfy(LogosWire.isSystem), "both read as the network's own (isSystem)")
let head2 = LogosWire.header(Data(base64Encoded: B2)!)
check(head2?.id == 2 && head2?.timestamp.timeIntervalSince1970 == 1790779853.687, "the header alone reads id and time")
check(head2?.hashHex == "6d2ea2cc6dcce44917890071154167624260bdb763a24370feecf06310f00916", "the header's own hash, bytes 40–72")
check(LogosWire.header(Data([1, 2, 3])) == nil, "a stub is no header")
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
// Genesis carries one of these for real (block 1, two signers, no fee):
// signed is a person's act, fee or none.
let signedFree = LogosWire.block(wrap(publicTx(program: native, accounts: [from, to], instruction: [0] + u128(40), fee: false, signers: 1)))?.transactions.first
check(signedFree.map(LogosWire.isSystem) == false, "a signed transaction with no fee is not the network's")
check(signedFree.map { LogosWire.events($0, watched: watched(DUMJ)).map(\.title) } == ["Received 40 — from CbgR…Sr2r"], "and it lands")

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


print("tokens — the 10-01 chain's own transactions (prd §1084)")
func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []; var i = hex.startIndex
    while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); out.append(UInt8(hex[i..<j], radix: 16)!); i = j }
    return out
}
let FIELD_DEF = "5NVdBghqGS8LF556tjfGK2zbzDhM9yZpFaD1WoEKFHgc"
let HOLD43 = "43oiVPkd5xDcyQSYd7nmfPma3qBduuZs3fJFdgmrR51v"
let HOLD5O = "5oX8kWmEbSaEWbnDVyqXRKfmw1DahmQu9ENmfGrQSfwP"
check(LogosWire.base58Encode(LogosWire.tokenProgram) == "AxDdLwqkWgR9qaSctvABV1ZtvWJJyzXB8199xZueifPj",
      "the token program's account id is SHA256(prefix ‖ \"token\") — the shard key getAccount shows")
let tTransfer = bytes("00e803000000000000000000000000000040f04f4f54704ae708e344b994e6672f77c56a931d9d95230d7299f548c699a900")
let tDefine = bytes("01090000004649454c445445535430750000000000000000000000000000")
let tMint = bytes("05f4010000000000000000000000000000")
check(LogosWire.tokenCall(tTransfer) == .transfer(amount: 1000, definition: LogosWire.base58Decode(FIELD_DEF)!, kind: .fungible),
      "block 137: Transfer 1,000 of 5NVd…, fungible")
check(LogosWire.tokenCall(tDefine) == .define(name: "FIELDTEST", supply: 30000, nft: false), "block 133: a new FIELDTEST, 30,000")
check(LogosWire.tokenCall(tMint) == .mint(amount: 500), "block 152: Mint 500")
check(LogosWire.tokenCall(tTransfer + [0]) == nil, "a byte left over refuses the call")
check(LogosWire.tokenCall(Array(tTransfer.dropLast())) == nil, "a byte short refuses the call")
check(LogosWire.tokenCall([7]) == nil, "an unknown variant refuses the call")
func tokenTx(_ ins: [UInt8], _ a: String, _ b: String) -> LogosWire.Transaction {
    LogosWire.Transaction(kind: .publicCall, hashHex: "", program: LogosWire.tokenProgram,
                          accounts: [LogosWire.base58Decode(a)!, LogosWire.base58Decode(b)!],
                          instruction: ins, signers: 2, paysFee: true)
}
let named: [Data: String] = [Data(LogosWire.base58Decode(FIELD_DEF)!): "FIELDTEST"]
let sentT = LogosWire.events(tokenTx(tTransfer, HOLD43, HOLD5O), watched: watched(HOLD43, HOLD5O), names: named)
check(sentT.map(\.title) == ["Sent 1,000 FIELDTEST — to 5oX8…SfwP", "Received 1,000 FIELDTEST — from 43oi…R51v"],
      "a token transfer names the amount and the token, both sides")
check(sentT.map(\.tags) == [["Sent"], ["Received"]], "…tagged Sent and Received")
check(LogosWire.events(tokenTx(tTransfer, HOLD43, HOLD5O), watched: watched(HOLD5O)).map(\.title)
      == ["Received 1,000 tokens — from 43oi…R51v"], "an unread name says tokens, never a guess")
check(LogosWire.events(tokenTx(tDefine, FIELD_DEF, HOLD43), watched: watched(HOLD43)).map(\.title)
      == ["Created FIELDTEST — 30,000"], "a definition names itself")
check(LogosWire.events(tokenTx(tMint, FIELD_DEF, HOLD43), watched: watched(FIELD_DEF, HOLD43), names: named).map(\.title)
      == ["Minted 500 FIELDTEST — to 43oi…R51v", "Received 500 FIELDTEST — minted"], "a mint, from both sides")
check(LogosWire.events(tokenTx(tTransfer + [0], HOLD43, HOLD5O), watched: watched(HOLD5O)).map(\.title)
      == ["Used a program"], "an undecodable token call falls back to Used a program")

print("holdings — getAccount, measured")
let acct5O = try! JSONSerialization.jsonObject(with: Data("""
{"nonce":5,"data":{"shards":{"11111111111111111111111111111111":[224,136,137,59,0,0,0,0,0,0,0,0,0,0,0,0],"AxDdLwqkWgR9qaSctvABV1ZtvWJJyzXB8199xZueifPj":[0,64,240,79,79,84,112,74,231,8,227,68,185,148,230,103,47,119,197,106,147,29,157,149,35,13,114,153,245,72,198,153,169,140,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}}}
""".utf8))
let shards5O = LogosWire.shards(acct5O)
check(shards5O?.count == 2, "two shards: native and token")
check(LogosWire.nativeBalance(shards5O?[LogosWire.nativeShardKey]) == 998_869_216,
      "the native shard reads 998,869,216 — what getAccountBalance answered")
check(LogosWire.nativeBalance(nil) == 0, "no native shard is a zero balance (the encoding drops zero)")
let held = shards5O.flatMap { $0[LogosWire.tokenShardKey] }.flatMap(LogosWire.tokenHolding)
check(held?.kind == .fungible && held?.amount == 908, "the token shard holds 908, fungible")
check(held.map { LogosWire.base58Encode($0.definition) } == FIELD_DEF, "…of the FIELDTEST definition")
let defShard: [UInt8] = [0,9,0,0,0,70,73,69,76,68,84,69,83,84,36,119,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
check(LogosWire.tokenName(definitionShard: defShard) == "FIELDTEST", "a definition's shard names it")
check(LogosWire.tokenHolding(defShard) == nil, "a definition is not a holding")
check(LogosWire.tokenHolding(held.map { _ in Array(shards5O![LogosWire.tokenShardKey]!) + [0] } ?? []) == nil,
      "a holding with a byte left over is refused")

print("sending — a signed transfer from the 10-01 chain, block 54 (prd §1084)")
let rawTx = [UInt8](Data(base64Encoded: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAFTWYrZkUZy4rvYIroSmPgQcwWAZ5KB8NIKDEZlvDIF6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABHGylfyUuVYs5gi2GDDR0ZDmF8fvNQ6XGQ/wtB/xkcFgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAARAAAAAAAQpdToAAAAAAAAAAAAAAABVNZitmRRnLiu9giuhKY+BBzBYBnkoHw0goMRmW8MgXqAhB4AAAAAAAAAAAAAAAAA////////////////////fwEAAADv9aw5mlAkdjVH9ndAtgZiu7UtVfWEtY0BpzPoHs4/0u0N0vd0wGVf9HdnKvkdQVGiQT2+yLbL3DN6lupq/oRztusOWYyx+8uP+7E72d7vDkrUxrs5OChz97UJ4F8yFPo=")!)
let SENDER = "6iArKUXxhUJqS7kCaPNhwMWt3ro71PDyBj7jwAyE2VQV"
let RECIP = "5nZyAk76asHnSivwtY9q5Dt7jtDBs4zPjEQoRHiVW7nd"
let msg = LogosWire.transferMessage(from: LogosWire.base58Decode(SENDER)!, to: LogosWire.base58Decode(RECIP)!,
                                    amount: 1_000_000_000_000, nonce: 0)
check(msg?.count == 270, "the message is 270 bytes")
let sig = Array(rawTx[(rawTx.count - 96)..<(rawTx.count - 32)]), pk = Array(rawTx.suffix(32))
check(msg.flatMap { LogosWire.publicTransaction(message: $0, signature: sig, publicKey: pk) } == rawTx,
      "message + witness rebuild the chain's own transaction, byte for byte")
check(LogosWire.transactionHash(rawTx) == "e2467872813b6a0a8ac85f0bfa50e4d0a3e43621a3dc0001d01a735664ac82c6",
      "its hash is the one the chain and the walk key it by")
check(LogosWire.accountID(publicKey: pk) == SENDER, "the witness key derives the sender")
// The hash the chain's own BIP-340 signature verifies over (checked with the
// BIP-340 reference verifier, 2026-10-03): SHA256(prefix ‖ message).
check(msg.map { LogosWire.messageHash($0).map { String(format: "%02x", $0) }.joined() } == "b8a8764ef112850c421f1f475b4dc8c6bfc16a633c05dad816aa14ef1a84ddb6",
      "the message hash is the one the signature on the chain signs")
check(LogosWire.messagePrefix.count == 32 && LogosWire.messagePrefix.starts(with: Array("/LEE/v0.3/Message/Public/".utf8)),
      "the hash prefix is the 32-byte padded v0.3 tag")
check(LogosWire.transferMessage(from: LogosWire.base58Decode(SENDER)!, to: LogosWire.base58Decode(SENDER)!,
                                amount: 1, nonce: 0) == nil, "no message to yourself")
check(LogosWire.transferMessage(from: LogosWire.base58Decode(SENDER)!, to: LogosWire.base58Decode(RECIP)!,
                                amount: 0, nonce: 0) == nil, "no message for nothing")
check(LogosWire.transferMessage(from: LogosWire.base58Decode(SENDER)!, to: LogosWire.base58Decode(RECIP)!,
                                amount: Decimal(string: "1.5")!, nonce: 0) == nil, "no message for a fraction")
check(LogosWire.u128Bytes(Decimal(string: "340282366920938463463374607431768211455")!) == [UInt8](repeating: 255, count: 16),
      "u128::MAX encodes as sixteen 0xff")
check(LogosWire.typedAmount("340282366920938463463374607431768211455") != nil, "u128::MAX can be typed")
check(LogosWire.typedAmount("340282366920938463463374607431768211456") == nil,
      "past u128 is refused, never rounded into range (Decimal drops a 39th digit)")
check(LogosWire.typedAmount("007") == 7, "leading zeros are the same number")
check(LogosWire.typedAmount("1,000") == 1000, "a typed amount takes grouping")
check(LogosWire.typedAmount("1.5") == nil, "a fraction is refused — LEZ has no decimals")
check(LogosWire.typedAmount("0") == nil, "zero is refused")
check(LogosWire.feeReserve(baseFeeExec: 8, baseFeeStor: 8, dataBytes: LogosWire.transferBytes) == 16_002_968,
      "the reserve at base fee 8: 2,000,000 × 8 + 371 × 8")
check(LogosWire.transferBytes == rawTx.count, "a transfer's length is the chain's")
check(LogosWire.sendBlock(from: SENDER, to: RECIP, amount: 10, balance: 16_002_977, reserve: 16_002_968) == .short(needs: 16_002_978),
      "the amount AND the reserve must be held")
check(LogosWire.sendBlock(from: SENDER, to: RECIP, amount: 10, balance: 16_002_978, reserve: 16_002_968) == nil,
      "exactly enough sends")
check(LogosWire.sendBlock(from: SENDER, to: SENDER, amount: 10, balance: .greatestFiniteMagnitude, reserve: 0) == .sameAccount,
      "not to yourself")
check(LogosWire.refusal(["error": ["code": -32602, "message": "Incorrect fee"]]) == .funds,
      "MEASURED: an empty payer answers Incorrect fee")
check(LogosWire.refusal(["error": ["code": -32602, "message": "Invalid signature(-s)"]]) == .other,
      "a bad signature is ours, never the person's funds")
check(LogosWire.refusal(["result": "ab"]) == nil, "a success is no refusal")
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
  'if isSystem(tx) { return [] }' \
  'if tx.signers < 0 { return [] }'
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
mutate "an unread balance read as a reset's zero" \
  'return balances.contains { $0 == 0 }' \
  'return balances.contains { $0 == 0 || $0 == nil }'
mutate "the reset named forever" \
  'guard let chainStart, now.timeIntervalSince(chainStart) < resetNoticeWindow,' \
  'guard let chainStart, now.timeIntervalSince(chainStart) < .infinity,'
mutate "the header's hash read from the previous block's" \
  'guard let id = r.u64(), r.skip(32), let hash = r.bytes(32), let ms = r.u64() else { return nil }' \
  'guard let id = r.u64(), let hash = r.bytes(32), r.skip(32), let ms = r.u64() else { return nil }'
mutate "a signed transaction read as the network's" \
  'tx.kind == .publicCall && tx.signers == 0 && !tx.paysFee' \
  'tx.kind == .publicCall && !tx.paysFee'
mutate "a network address read as loopback" \
  'host.hasPrefix("127.")' \
  'host.hasPrefix("1")'

mutate "a token transfer's sender and recipient swapped" \
  '                return holder
                    ? Event(account: id(1), title: "Received \(what) — from \(other(0))"' \
  '                return !holder
                    ? Event(account: id(1), title: "Received \(what) — from \(other(0))"'
mutate "a token call read past its end" \
  '        return r.atEnd ? call : nil
    }

    /// The token definition a call is about' \
  '        return call
    }

    /// The token definition a call is about'
mutate "the token program named by the wrong name" \
  'static let tokenProgram = builtinProgram("token")' \
  'static let tokenProgram = builtinProgram("tokens")'
mutate "a holding's balance read before its definition" \
  'guard let k = r.u8().flatMap(TokenKind.init(rawValue:)), let def = r.bytes(32) else { return nil }
        let holding: TokenHolding' \
  'guard let k = r.u8().flatMap(TokenKind.init(rawValue:)), r.skip(16), let def = r.bytes(32) else { return nil }
        let holding: TokenHolding'
mutate "the fee declared with a tip" \
  'm += [1] + from + le64(gasLimit) + le64(0) + maxFee' \
  'm += [1] + from + le64(gasLimit) + le64(1) + maxFee'
mutate "the selectors' program left out" \
  'm += le32(2) + from + nativeProgram + to + nativeProgram' \
  'm += le32(2) + from + to'
mutate "the message hashed without its prefix" \
  'Array(SHA256.hash(data: messagePrefix + message))' \
  'Array(SHA256.hash(data: message))'
mutate "the transaction hashed with its tag" \
  'SHA256.hash(data: tx.dropFirst())' \
  'SHA256.hash(data: tx)'
mutate "the reserve not required beside the amount" \
  'let needs = amount + reserve' \
  'let needs = amount'
mutate "an empty account's refusal read as ours" \
  'if message.contains("Incorrect fee") || message.contains("PayerCannotFund")' \
  'if message.contains("PayerCannotFund")'
mutate "a typed amount trusted past Decimal's precision" \
  '"\(value)" == String(digits.drop { $0 == "0" })' \
  'value == value'
mutate "a fraction rounded into a send" \
  'guard value >= 0, value == value.rounded0 else { return nil }' \
  'guard value >= 0 else { return nil }'

echo "✓ Logos self-test passed"
