#!/bin/zsh
# Casberi Logos self-test — the SHIPPED wire logic behind the Logos seat
# (2026-09-29, prd §988):
#
#   Casberi/Casberi/Model/LogosWire.swift
#     — parseAccountID / watchableID (base58, the Public/Private prefix)
#     — account(_:)                  (getAccount's measured shape, u128 via Decimal)
#     — block(_:)                    (LEZ v0.2's Borsh layout, exact length or nil)
#     — events(_:watched:programs:)  (what a transaction means for one account)
#     — nodeBase / isLoopback / nodeEvents (your own node, prd §989)
#
# Foundation + CryptoKit only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED
# here. The fixtures are FIVE REAL TESTNET BLOCKS (fetched 2026-09-29 from
# testnet.lez.logos.co's getBlockRange), and every transaction hash asserted
# below was confirmed on chain with getTransaction, which resolved each to its
# own block.
#
# WHY A HARNESS. Nothing here can send on LEZ, and a watch is forward-only on a
# quiet testnet, so the landing path runs only when somebody else happens to
# move coins. Every failure below renders as a perfectly good-looking row:
#
#   • a u128 read most-significant-word first — "Received 40" becomes
#     "Received 3,169,126,500,570,573,503,741,758,013,440";
#   • the timestamp read as seconds — every row lands in the year 58,660;
#   • the hash taken WITH the variant tag — every row opens a transaction the
#     explorer has never heard of;
#   • sender and recipient swapped — you "received" what you sent;
#   • the per-block clock transaction not skipped — a row a minute, forever;
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
for banned in Authorization sendTransaction requeueCrossZoneDeadLetter '"/leader/claim"' '/pow/claim' '/wallet/' '/mempool/add' 'postJSON(base'; do
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
(( guard_fail == 0 )) || exit 1
echo "✓ drift guards"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func block(_ b64: String) -> LogosWire.Block? { LogosWire.block(Data(base64Encoded: b64)!) }

let programs = LogosWire.programIDs([
    "amm": [1765802831,3731187220,2062982807,1520762763,307650957,4265115253,384461553,795532917],
    "authenticated_transfer": [583309054,2344528779,3806558405,2890696795,2257354672,3978764116,2273929063,1518858078],
    "pinata": [2062635772,3904239712,2833328350,20714435,436307236,2247732790,2681611470,2354246644],
    "token": [1047643340,4291649067,2093396023,4016657193,3904308476,481382041,2987082047,2603530278],
] as [String: Any])
func watched(_ ids: String...) -> Set<Data> { Set(ids.map { Data(LogosWire.base58Decode($0)!) }) }

let CBGR = "CbgR6tj5kWx5oziiFptM7jMvrQeYY3Mzaao6ciuhSr2r"
let DUMJ = "DumJ4LCBnHE9jUu2yxPfqdL14g3v756Gzby6LuT9hE51"
let FEWL = "FeWL8ksL4tihgujJhEsNnMiFfDsQarZdTXMEV2QnwCV7"
let SEVEN = "7EfpF91bkSb6sJ9xFFjq5G37BXHLSaACBAqYusoWQ3iT"
let DEF = "5LT5kqKjToJb6DqMtXoba8SzEELnJRoMz8mDUKzvvKxa"
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

print("getAccount")
let measured: [String: Any] = ["program_owner": [2062635772,3904239712,2833328350,20714435,436307236,2247732790,2681611470,2354246644],
                               "balance": 1481100, "data": [3, 58], "nonce": 0]
let acct = LogosWire.account(measured)
check(acct?.balance == 1481100, "the measured balance reads")
check(acct.flatMap { LogosWire.programName($0.programOwner, in: programs) } == "pinata", "its owner resolves to the faucet program")
check(LogosWire.account(["balance": 1] as [String: Any]) == nil, "an account without an owner is refused")
check(LogosWire.decimal("340282366920938463463374607431768211455")?.description == "340282366920938463463374607431768211455", "u128::MAX survives as a string")
check(LogosWire.result(["jsonrpc": "2.0", "error": ["code": -32602]] as [String: Any]) == nil, "an error reply has no result")

print("block 25894 — a native transfer")
let b1 = block("JmUAAAAAAACIopHL4LZ+cue0/tsb6PVZWjP83LjJPwroy8tt/iawvHn1NLuEyMRvkSr7tQL7W1PvKhjtDv8KkkMCuWVgGhdDdY0H3qABAADn2X7t9XzZQlVKGN5E41JrwJJQvxGX2LyiFCePS9qotZb9vL3h2oMGWdgYGS4gETNTTD4Ikf3gahIULdqS+hHQAgAAAAD+lsQii6u+i8V44+JbiEyssH+MhlQfJ+1nZ4mHXu+HWgIAAACsUt75pBCUuNs4XJHL3PtZ1rImHmzK+/GUyH25XeO997/Qh1eJRbipQ0AExnnmIl8ZNPXr8nuW++xabvIWe548AQAAABoAAAAAAAAAAAAAAAAAAAAFAAAAAAAAACgAAAAAAAAAAAAAAAAAAAABAAAA72KV2QlWDKv5zFbPccdD+eXVP20RScRN2M+PnmwEZY7nen3uo8tF3VGxovKyab3FcwtKwbZd/BxC3HVRp2XUIGqkw2Vpm4nZY++FpZhouWErYAH5B1C0lwZipid2My6BADGfvAVNdyB8uuwLMenMgT7KC0DTENcRLsSg/mQ5XGH8AwAAAC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDAxL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMTAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MAAAAAACAAAAdY0H3qABAAAAAAAAAg==")
check(b1?.id == 25894, "the block id")
check(b1?.timestamp.timeIntervalSince1970 == 1790431432.053, "the millisecond timestamp, as seconds")
let transfer = b1?.transactions.first { $0.programID.first != LogosWire.clockProgramWord }
check(transfer?.hashHex == "80e9990e63bc679dfab183aff254f0fe35148948e1312e074c987c7144ef80f4", "the hash matches the chain's")
check(transfer?.signers == 1, "one signer")
let both = transfer.map { LogosWire.events($0, watched: watched(CBGR, DUMJ), programs: programs) } ?? []
check(both.map(\.title) == ["Sent 40 — to DumJ…hE51", "Received 40 — from CbgR…Sr2r"], "sent and received, each from its own side")
check(both.map(\.account) == [CBGR, DUMJ], "each event names the account it is for")
let one = transfer.map { LogosWire.events($0, watched: watched(DUMJ), programs: programs) } ?? []
check(one.map(\.title) == ["Received 40 — from CbgR…Sr2r"], "the recipient alone sees only the receipt")
check(one.first?.tags == ["Received"], "tagged as state")
let none = transfer.map { LogosWire.events($0, watched: watched(HOLD), programs: programs) } ?? [LogosWire.Event(account: "", title: "", tags: [])]
check(none.isEmpty, "an unwatched transaction lands nothing")

print("the clock")
let clock = b1?.transactions.first { $0.programID.first == LogosWire.clockProgramWord }
check(clock != nil, "every block carries the clock transaction")
let everyone = Set((clock?.accounts ?? []).map { Data($0) })
check(clock.map { LogosWire.events($0, watched: everyone, programs: programs) }?.isEmpty == true, "the clock lands nothing even when its accounts are watched")
let quiet = block("SHEAAAAAAACcj7jS1RSC4jVT8WqGZiR5fQ4JcjhupRv6Xo+uBunI1VBEewJQai2pb0uCZWFfRKjIxOz5iPjVH3ywa10u0gehguUq6aABAACHQ3/5ix+KfwGkkQyyOrh40zR8IMmmu18VQcr9DduqetrqlPbEWpAXugxbmoogmknrkd2J73HHtwdxFN48Nsa6AQAAAAAxn7wFTXcgfLrsCzHpzIE+ygtA0xDXES7EoP5kOVxh/AMAAAAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDAwMS9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDEwL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwNTAAAAAAAgAAAILlKumgAQAAAAAAAAI=")
check(quiet?.transactions.count == 1, "a quiet block decodes to the clock alone")

print("block 152 — a token transfer")
let b2 = block("mAAAAAAAAADw5qtQ05o9ezB/IsxtmFZhg4N6XXGwtveu+1f5YQbebVEO4bXDDc7UpWtqGP62UT9PNgbq7WxuCc7OTfppG3tj6uLCgaABAAC2RgqrqlYV875GnM26R17vBzKRxWYzNTsbDy7GOBPghekwBBBP0w/OF5W6Q32e3GszRR80EtW5fb7spSYPaiDrAgAAAADMxHE+K17N/zewxnwpU2nv/AS36JlOsRw/QQuyJrgumwIAAADZn0Uzo6ytQv1QuWbJsPi8+T08O46JRLTuNgd7Godhylymj1CweRiZyVBVFdg7X4544MROZWUb5mLncSI3/rhUAQAAAAEAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAEBCDwAAAAAAAAAAAAAAAAABAAAAA3n9LqTcKMJUgtwQ3gqeCsFpIJPbsfaY5DtRWaFz914Cp98rEhulV2xyicNQdbCvTKcqkc1BVabjAV0j1MLfFIOL35nGQixwm2xHdUHAKOyQ8fGbq/5/ub4LNgG9lzmCADGfvAVNdyB8uuwLMenMgT7KC0DTENcRLsSg/mQ5XGH8AwAAAC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDAxL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMTAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MAAAAAACAAAA6uLCgaABAAAAAAAAAg==")
let tok = b2?.transactions.first { $0.programID.first != LogosWire.clockProgramWord }
check(tok?.hashHex == "a4adb5c918fcdda5dff0162bb82458630bc062be54e62461e94cda1f8125f2db", "the hash matches the chain's")
check(tok.map { LogosWire.events($0, watched: watched(FEWL, SEVEN), programs: programs).map(\.title) } ==
      ["Sent 1,000,000 tokens — to 7Efp…Q3iT", "Received 1,000,000 tokens — from FeWL…wCV7"], "token amounts, both sides")

print("block 26043 — a token created")
let b3 = block("u2UAAAAAAADKqVtck8u2hKyTm/ufqZsTfljZZJ90jNh87moeQmiGha2QKvNfDwoHMpdhdboBfA1BGu/puqxC5w2ocut9QoXCR1iQ3qABAAD97SGOHDZZx3grv5qDS2+ZT6BNrJyeBUwB7SNObsx9TCU9Hgg+VFXwHwAwTYfe9o1y5NXVPFpTOWGkzv4K9tTKAgAAAADMxHE+K17N/zewxnwpU2nv/AS36JlOsRw/QQuyJrgumwIAAABAakYqYue7iOP6KpdR/6EChg4XEDEjCQhyHJ7hqV+cV1SWsUJV8Vcf0EHqqJU6ARd7hH4qpLSsu56WoPHvP/SjAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAEAAAAEAAAAQU5UVkBCDwAAAAAAAAAAAAAAAAACAAAAalq9/E/0S4X+itHrz/PgbLsEHdbCBERCiXVsB+1fywYIzrH18R2qdsFisUaiGRHSFO2nt5rXdwUaaBzopAkPJWe8wJjZS97F/VF6uDV7sEyZtgUVtXZblbqlPYdxL6CGjj3zXi+LTTSJe5m5lKd+F03TIP/K7mcal0iwv4fwBUbQzOshOUZuY/EEvey8WymqfnRMn+Y49hJZjgQZpgDe32X5F4k14u1AiMQC5G+p3BoDUqtwoJzWTz9nFvaqtMETADGfvAVNdyB8uuwLMenMgT7KC0DTENcRLsSg/mQ5XGH8AwAAAC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDAxL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMTAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MAAAAAACAAAAR1iQ3qABAAAAAAAAAg==")
let made = b3?.transactions.first { $0.programID.first != LogosWire.clockProgramWord }
check(made.map { LogosWire.events($0, watched: watched(DEF), programs: programs).map(\.title) } == ["Created token ANTV"], "the token's name is read out of the instruction")

print("block 27220 — a mint")
let b4 = block("VGoAAAAAAAD9l6U1TRmZmyFkZvm0ibfd3iqEQLU3EMwy5Xrtj6kgQCGzs9dSNZDyfsizuOQNPPIO6y6hOPhvyip8zNpUBFaB6NrI4qABAABeMKNAXZ3BkNHXJ18td+vntsgjv1jnloOAXNoiDEyXFEUT68N1g9uXmhlEcNx88uBWTzw9U9k4uhp/uXqe3BwhAgAAAADMxHE+K17N/zewxnwpU2nv/AS36JlOsRw/QQuyJrgumwIAAABAakYqYue7iOP6KpdR/6EChg4XEDEjCQhyHJ7hqV+cV1SWsUJV8Vcf0EHqqJU6ARd7hH4qpLSsu56WoPHvP/SjAQAAAAEAAAAAAAAAAAAAAAAAAAAFAAAABQAAAICEHgAAAAAAAAAAAAAAAAABAAAApLJRD8FQCBi4EiTNxSzLM1VeW0P/ddnJ7NqaictypH1h2CkKL1ly7bXrD0ZNpgckM6ZlAVzZANf4ImBQ0noT0me8wJjZS97F/VF6uDV7sEyZtgUVtXZblbqlPYdxL6CGADGfvAVNdyB8uuwLMenMgT7KC0DTENcRLsSg/mQ5XGH8AwAAAC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDAxL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMTAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MAAAAAACAAAA6NrI4qABAAAAAAAAAg==")
let mint = b4?.transactions.first { $0.programID.first != LogosWire.clockProgramWord }
check(mint?.hashHex == "58f2f92b1fc4f2b7fa2014f3c61db6845b3defc32acc2340153383accce2d3cf", "the hash matches the chain's")
check(mint.map { LogosWire.events($0, watched: watched(HOLD), programs: programs).map(\.title) } == ["Minted 2,000,000 tokens"], "the minted amount")

print("amounts")
check(LogosWire.u128([40, 0, 0, 0]) == 40, "u128: least-significant word FIRST")
check(LogosWire.amount(LogosWire.u128([0, 0, 1, 0])!) == "18,446,744,073,709,551,616", "u128: the third word is 2^64")
check(!LogosWire.amount(1_000).contains("LGO"), "no unit is invented")
check(LogosWire.string([4, 1448365633])?.0 == "ANTV", "a risc0 String unpacks four bytes to a word")

print("exact length")
var raw = Data(base64Encoded: "JmUAAAAAAACIopHL4LZ+cue0/tsb6PVZWjP83LjJPwroy8tt/iawvHn1NLuEyMRvkSr7tQL7W1PvKhjtDv8KkkMCuWVgGhdDdY0H3qABAADn2X7t9XzZQlVKGN5E41JrwJJQvxGX2LyiFCePS9qotZb9vL3h2oMGWdgYGS4gETNTTD4Ikf3gahIULdqS+hHQAgAAAAD+lsQii6u+i8V44+JbiEyssH+MhlQfJ+1nZ4mHXu+HWgIAAACsUt75pBCUuNs4XJHL3PtZ1rImHmzK+/GUyH25XeO997/Qh1eJRbipQ0AExnnmIl8ZNPXr8nuW++xabvIWe548AQAAABoAAAAAAAAAAAAAAAAAAAAFAAAAAAAAACgAAAAAAAAAAAAAAAAAAAABAAAA72KV2QlWDKv5zFbPccdD+eXVP20RScRN2M+PnmwEZY7nen3uo8tF3VGxovKyab3FcwtKwbZd/BxC3HVRp2XUIGqkw2Vpm4nZY++FpZhouWErYAH5B1C0lwZipid2My6BADGfvAVNdyB8uuwLMenMgT7KC0DTENcRLsSg/mQ5XGH8AwAAAC9MRVovQ2xvY2tQcm9ncmFtQWNjb3VudC8wMDAwMDAxL0xFWi9DbG9ja1Byb2dyYW1BY2NvdW50LzAwMDAwMTAvTEVaL0Nsb2NrUHJvZ3JhbUFjY291bnQvMDAwMDA1MAAAAAACAAAAdY0H3qABAAAAAAAAAg==")!
check(LogosWire.block(raw.dropLast(1)) == nil, "a truncated block is refused")
raw.append(0)
check(LogosWire.block(raw) == nil, "a block with a trailing byte is refused")

print("synthetic kinds")
func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
func le64(_ v: UInt64) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
func wrap(_ tx: [UInt8]) -> Data {
    Data(le64(7) + [UInt8](repeating: 1, count: 64) + le64(1_790_000_000_000)
         + [UInt8](repeating: 2, count: 64) + le32(1) + tx + [0])
}
let deploy = LogosWire.block(wrap([2] + le32(3) + [9, 9, 9]))
check(deploy?.transactions.first?.kind == .programDeployment, "a program deployment decodes")
let who = LogosWire.base58Decode(CBGR)!
var priv: [UInt8] = [1] + le32(1) + who + [UInt8](repeating: 0, count: 32) + [UInt8](repeating: 0, count: 16) + le32(2) + [5, 5] + [UInt8](repeating: 0, count: 16)
priv += le32(0)                                                                  // nonces
priv += le32(1) + [UInt8](repeating: 3, count: 96) + le32(2) + [1, 2] + le32(1) + [7] + [4]   // one private action
priv += [0] + [1] + le64(5) + [0] + [0]                                          // validity windows
priv += le32(0) + le32(3) + [8, 8, 8]                                            // witness: no sigs, a proof
let p = LogosWire.block(wrap(priv))?.transactions.first
check(p?.kind == .privacyPreserving, "a privacy-preserving transaction decodes")
check(p.map { LogosWire.events($0, watched: watched(CBGR), programs: programs).map(\.title) } == ["Private transaction"], "only its public side is named")

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
  'for word in w.reversed() { value = value * 4_294_967_296 + Decimal(word) }' \
  'for word in w { value = value * 4_294_967_296 + Decimal(word) }'
mutate "the timestamp read as seconds" \
  'Date(timeIntervalSince1970: Double(ms) / 1000)' \
  'Date(timeIntervalSince1970: Double(ms))'
mutate "the hash taken with the variant tag" \
  'let start = r.offset' \
  'let start = r.offset - 1'
mutate "a trailing byte tolerated" \
  'guard r.u8() != nil, r.atEnd else { return nil }' \
  'guard r.u8() != nil else { return nil }'
mutate "the clock not skipped" \
  'if tx.programID.first == clockProgramWord { return [] }' \
  'if tx.programID.isEmpty { return [] }'
mutate "sender and recipient swapped" \
  '                out.append(i == 1
                    ? Event(account: id(1), title: "Received' \
  '                out.append(i == 0
                    ? Event(account: id(1), title: "Received'
mutate "a private id made watchable" \
  'guard let id = parseAccountID(raw), id.visibility != .privateAccount else { return nil }' \
  'guard let id = parseAccountID(raw) else { return nil }'
mutate "any length accepted as an id" \
  'guard let bytes = base58Decode(text), bytes.count == 32 else { return nil }' \
  'guard let bytes = base58Decode(text), bytes.count > 0 else { return nil }'
mutate "the token name not read" \
  'let made = string(ins.dropFirst()).map { "Created token \($0.0)" } ?? "Created a token"' \
  'let made = "Created a token"'

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
mutate "a network address read as loopback" \
  'host.hasPrefix("127.")' \
  'host.hasPrefix("1")'

echo "✓ Logos self-test passed"
