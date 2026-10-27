#!/bin/zsh
# Casberi Aztec signing self-test — what the phone checks before it signs for
# an Aztec TESTNET account (2026-10-11, prd §1276):
#
#   Casberi/Casberi/Model/AztecSignRequest.swift (+ AztecPoseidon2.swift)
#     — check     (testnet only; the hash rebuilt from the calls must match)
#     — outerHash (the entrypoint's signed hash, natively)
#     — link      (casberi://aztec/sign#<base64url JSON>, both ways)
#     — digest    (sha256 of the hash: what EcdsaRAccount verifies)
#
# Against a REAL request: the one a Secure Enclave key signed for a token mint
# that mined on Aztec's v5 testnet (block 115467). Every failure below is a
# sheet that looks right and signs the wrong thing:
#
#   • a mainnet request offered for signing — real money, which this app
#     must never authorise;
#   • the hash taken from the request instead of rebuilt — blind signing;
#   • a public call hashed as private, or padding hashed as zeros — every
#     honest request refused, or a tampered one accepted;
#   • the digest left unhashed — a signature the account never accepts.
set -euo pipefail
cd "$(dirname "$0")/.."

REQ="Casberi/Casberi/Model/AztecSignRequest.swift"
LOG="Casberi/Casberi/Model/AztecSignedLog.swift"
P2="Casberi/Casberi/Model/AztecPoseidon2.swift"
FIX="scripts/fixtures/aztec/sign-request-v5.json"
# The v6.0.0 testnet's own (prd §1565): a token deploy the simulator's key
# signed through `tools/aztec-signer once --sim`, mined at block 7652
# (tx 0x0d3575e6…a2e9), the sponsored fee payer on v6 paying.
FIX6="scripts/fixtures/aztec/sign-request-v6.json"
for f in "$REQ" "$P2" "$FIX" "$FIX6" "$LOG"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done
# Conduct: the signing key is reached only through the checked tray, and the
# phone never submits anything itself (no Aztec node write here).
grep -q 'AztecSignRequest.check(request, live: live)' Casberi/Casberi/Screens/AztecSignTray.swift \
  || { echo "✗ the sign tray no longer checks the request before offering Sign"; exit 1; }
if grep -rn 'AztecSignerKey.sign(' Casberi/Casberi --include='*.swift' | grep -v 'Screens/AztecSignTray.swift' | grep -q .; then
  echo "✗ AztecSignerKey.sign is called outside the checked tray"; exit 1
fi
grep -q 'kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly' Casberi/Casberi/Model/AztecSignerKey.swift \
  || { echo "✗ the Aztec signing key is not device-only"; exit 1; }

TMP="$(mktemp -d)"
WORK="$TMP/work"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what) (line \(line))"); failures += 1 }
}
let data = try! Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIGN_FIX"]!))
let real = try! JSONDecoder().decode(AztecSignRequest.Request.self, from: data)
func with(_ change: (inout [String: Any]) -> Void) -> AztecSignRequest.Request {
    var obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    change(&obj)
    return try! JSONDecoder().decode(AztecSignRequest.Request.self,
                                     from: try! JSONSerialization.data(withJSONObject: obj))
}
func callsChanged(_ f: (inout [[String: Any]]) -> Void) -> AztecSignRequest.Request {
    with { obj in var calls = obj["calls"] as! [[String: Any]]; f(&calls); obj["calls"] = calls }
}

print("the real request")
check(AztecSignRequest.outerHash(real) == real.messageHash, "the hash rebuilt from its calls is the mined one")
check(AztecSignRequest.check(real) == .sign(network: "Aztec testnet (v5)"), "offered for signing, on the v5 testnet")
check(AztecSignRequest.request(fromLink: AztecSignRequest.link(real)!) == real, "a link carries it whole")
check(AztecSignRequest.digest(real.messageHash)?.count == 32, "the digest is 32 bytes")
check(AztecSignRequest.digest(real.messageHash) != AztecPoseidon2.field(real.messageHash).map { Array($0) },
      "the digest is sha256 of the hash, never the hash")

print("a real request on the v6.0.0 testnet (prd §1565)")
let v6 = try! JSONDecoder().decode(AztecSignRequest.Request.self,
                                   from: Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIGN_FIX6"]!)))
check(AztecSignRequest.outerHash(v6) == v6.messageHash, "the hash rebuilt from its three calls is the one v6 aztec.js asked for")
check(AztecSignRequest.check(v6) == .sign(network: "Aztec testnet (v6)"), "offered with no live reading, on the v6 testnet")
check(v6.calls[0].signature == "sponsor_unconditionally()" && AztecSignRequest.nameChecked(v6.calls[0])
      && AztecSignRequest.line(v6.calls[0]) == "The sponsored fee payer pays the fee", "v6's sponsored fee payer, its name checked")
check(v6.calls[2].type == "public" && AztecSignRequest.nameChecked(v6.calls[2]), "the token's public constructor, its name checked")
check(v6.calls[1].signature == nil, "a protocol call the tool cannot name goes unnamed")

print("refusals")
let mainnet = with { $0["chainId"] = "0x" + String(repeating: "0", count: 63) + "1" }
check(AztecSignRequest.check(mainnet) == .refused("This request is not for an Aztec testnet. Casberi signs for test money only."),
      "Ethereum mainnet is refused")
// Aztec mainnet's rollup, with a hash honestly rebuilt for it: only the
// allowlist can refuse this one.
let alphaVersion = "0x" + String(4_248_422_647, radix: 16)
let alphaHash = AztecSignRequest.outerHash(with { $0["version"] = alphaVersion })!
let alpha = with { $0["version"] = alphaVersion; $0["messageHash"] = alphaHash }
check(AztecSignRequest.check(alpha) == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "Aztec mainnet's rollup is refused, its hash matching")
// …and Ethereum mainnet with a matching hash too, so the chain check is the
// only thing standing.
let mainnetHash = AztecSignRequest.outerHash(with { $0["chainId"] = "0x1" })!
let mainnetHonest = with { $0["chainId"] = "0x1"; $0["messageHash"] = mainnetHash }
check(AztecSignRequest.check(mainnetHonest) == .refused("This request is not for an Aztec testnet. Casberi signs for test money only."),
      "Ethereum mainnet is refused, its hash matching")
let tampered = callsChanged { $0[1]["args"] = [($0[1]["args"] as! [String])[0], "0x" + String(1000, radix: 16)] }
if case .refused = AztecSignRequest.check(tampered) { check(true, "a changed amount no longer matches the hash") } else { check(false, "a changed amount no longer matches the hash") }
let retargeted = callsChanged { $0[1]["to"] = "0x" + String(repeating: "1", count: 64) }
if case .refused = AztecSignRequest.check(retargeted) { check(true, "a changed contract no longer matches the hash") } else { check(false, "a changed contract no longer matches the hash") }
let renamed = callsChanged { $0[1]["name"] = "totally_harmless" }
check(AztecSignRequest.check(renamed) == .sign(network: "Aztec testnet (v5)"),
      "a renamed call still matches — names are the computer's, and the sheet says so")
let empty = with { $0["calls"] = [] as [Any] }
if case .refused = AztecSignRequest.check(empty) { check(true, "no calls, nothing to sign") } else { check(false, "no calls, nothing to sign") }
check(AztecSignRequest.request(fromLink: "casberi://aztec/sign#!!") == nil, "a broken link is no request")
check(AztecPoseidon2.field("０x１") == nil && AztecPoseidon2.field("0x１") == nil, "fullwidth digits are no field (they crashed the parse)")
let fullwidth = callsChanged { $0[1]["args"] = [($0[1]["args"] as! [String])[0], "0x１"] }
if case .refused = AztecSignRequest.check(fullwidth) { check(true, "…and a request carrying one is refused") } else { check(false, "…and a request carrying one is refused") }
// p + 1: reduced mod p it hashes as 1, so its own hash matches — only the
// range check stands between it and a sheet showing a different number.
let pPlusOne = "0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000002"
let wrapped = callsChanged { $0[1]["args"] = [($0[1]["args"] as! [String])[0], pPlusOne] }
check(AztecSignRequest.outerHash(wrapped) == real.messageHash, "p + 1 hashes as 1 (why the range check exists)")
check(AztecSignRequest.check(with { o in var c = o["calls"] as! [[String: Any]]; c[1]["args"] = [(c[1]["args"] as! [String])[0], pPlusOne]; o["calls"] = c }) == .refused("This request carries a value that is not a valid Aztec field. Nothing was signed."),
      "a value past the modulus is refused, its hash matching")
check(AztecSignRequest.request(fromLink: "https://evil.example/aztec/sign#" + AztecSignRequest.link(real)!.split(separator: "#")[1]) == nil,
      "only the app's own scheme")

print("a testnet that moved")
func onVersion(_ v: Int, chain: String = "0x" + String(11_155_111, radix: 16)) -> AztecSignRequest.Request {
    let hex = "0x" + String(v, radix: 16)
    let hash = AztecSignRequest.outerHash(with { $0["version"] = hex; $0["chainId"] = chain })!
    return with { $0["version"] = hex; $0["chainId"] = chain; $0["messageHash"] = hash }
}
check(AztecSignRequest.check(onVersion(679_261_766)) == .sign(network: "Aztec testnet (v6)"), "v6.0.0's rollup is known (prd §1565)")
check(AztecSignRequest.check(onVersion(3_409_706_519)) == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "a release candidate no node answers any more is refused with no live reading")
let mainnetFirst = onVersion(2_934_756_905)
check(AztecSignRequest.check(mainnetFirst, live: .init(rollupVersion: 2_934_756_905, l1ChainID: 11_155_111))
      == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "every rollup mainnet's Registry lists is refused, even vouched for (prd §1565)")
let moved = onVersion(1_234_567)
check(AztecSignRequest.check(moved) == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "an unknown rollup is refused with no live reading")
check(AztecSignRequest.check(moved, live: .init(rollupVersion: 1_234_567, l1ChainID: 11_155_111)) == .sign(network: "Aztec testnet"),
      "…and signed when Aztec's testnet node reports it, on Sepolia")
check(AztecSignRequest.check(moved, live: .init(rollupVersion: 1_234_567, l1ChainID: 1)) != .sign(network: "Aztec testnet"),
      "a node reporting it on Ethereum mainnet is not a testnet")
check(AztecSignRequest.check(moved, live: .init(rollupVersion: 7, l1ChainID: 11_155_111)) != .sign(network: "Aztec testnet"),
      "a live reading of another rollup does not vouch for this one")
let mainnetLie = onVersion(4_248_422_647)
check(AztecSignRequest.check(mainnetLie, live: .init(rollupVersion: 4_248_422_647, l1ChainID: 11_155_111))
      == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "Aztec mainnet's rollup is refused even if a node calls it a testnet")
let mainnetV6 = onVersion(2_070_860_440)
check(AztecSignRequest.check(mainnetV6, live: .init(rollupVersion: 2_070_860_440, l1ChainID: 11_155_111))
      == .refused("This request names a rollup that is not one of Aztec's testnets."),
      "so is mainnet's V6 rollup, the one governance proposal 5 adds (prd §1446)")

print("names, checked (prd §1446)")
check(AztecSignRequest.selector(of: "sponsor_unconditionally()") == 0x23d7_7f89
      && AztecSignRequest.selector(of: "mint_to_public((Field),u128)") == 0x451b_5fae,
      "a signature's selector is Aztec's, as the mined request carries it")
check(AztecSignRequest.selector(of: "mint_to_public((Field), u128)") == nil, "a signature with a space is no signature")
func signed(_ sigs: [String?], names: [String]? = nil) -> AztecSignRequest.Request {
    callsChanged { calls in
        for i in calls.indices {
            if let sig = sigs[i] { calls[i]["signature"] = sig }
            if let names { calls[i]["name"] = names[i] }
        }
    }
}
let named = signed(["sponsor_unconditionally()", "mint_to_public((Field),u128)"])
check(AztecSignRequest.check(named) == .sign(network: "Aztec testnet (v5)"), "true signatures are signed")
check(AztecSignRequest.check(signed([nil, "transfer_in_public((Field),(Field),u128,Field)"], names: ["sponsor_unconditionally", "transfer_in_public"]))
      == .refused("A call's name does not match the function it runs. Nothing was signed."),
      "a call named as another function is refused, though the hash matches")
check(AztecSignRequest.check(signed([nil, "mint_to_public((Field),u128)"], names: ["sponsor_unconditionally", "burn"]))
      == .refused("A call's name does not match the function it runs. Nothing was signed."),
      "a name that is not its own signature's is refused")
check(AztecSignRequest.line(named.calls[0]) == "The sponsored fee payer pays the fee",
      "a checked fee call reads in plain words")
check(AztecSignRequest.line(real.calls[0]) == "sponsor_unconditionally()", "an unchecked one keeps the computer's name")
check(AztecSignRequest.line(named.calls[1], account: real.account) == "mint_to_public(your account, 1)",
      "the account itself is \"your account\"")
check(AztecSignRequest.target(named.calls[1], account: real.account) != "your account"
      && AztecSignRequest.target(.init(name: "x", to: real.account, selector: "0x1", type: "private",
                                       hideMsgSender: false, isStatic: false, args: []), account: real.account) == "your account",
      "a call to the account itself goes to \"your account\"")

print("the signed log")
let suite = "aztec.sign.selftest.\(ProcessInfo.processInfo.processIdentifier)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
AztecSignedLog.record(AztecSignedLog.entry(for: real, network: "Aztec testnet (v5)", at: Date(timeIntervalSince1970: 1)), defaults)
AztecSignedLog.record(AztecSignedLog.entry(for: real, network: "Aztec testnet (v5)", at: Date(timeIntervalSince1970: 2)), defaults)
let logged = AztecSignedLog.entries(defaults)
check(logged.count == 1 && logged[0].at == Date(timeIntervalSince1970: 2), "the same hash signed twice is one entry, the newer")
check(logged[0].lines == real.calls.map { AztecSignRequest.line($0, account: real.account) } && logged[0].account == real.account.lowercased(),
      "it keeps what the sheet showed")
for i in 0..<40 { AztecSignedLog.record(.init(at: .now, network: "t", account: "a", messageHash: "0x\(i)", lines: []), defaults) }
check(AztecSignedLog.entries(defaults).count == AztecSignedLog.cap && AztecSignedLog.entries(defaults).first?.messageHash == "0x39",
      "capped, newest first")

print("words")
let mintLine = AztecSignRequest.line(real.calls[1])
check(mintLine.hasPrefix("mint_to_public(0x") && mintLine.hasSuffix(", 1)") && mintLine.count == "mint_to_public(".count + 66 + ", 1)".count,
      "a call's line, the address whole: \(mintLine)")
let oneToken = AztecPoseidon2.field("0x0de0b6b3a7640000")!
let aMillion = AztecPoseidon2.field("0xd3c21bcecceda1000000")!
check(AztecSignRequest.decimal(oneToken) == "1000000000000000000" && AztecSignRequest.decimal(aMillion) == "1000000000000000000000000",
      "an 18-decimal amount in whole digits, one token never reading as a million")
check(AztecSignRequest.decimal(AztecPoseidon2.field("0x" + String(repeating: "f", count: 32))!) == "340282366920938463463374607431768211455",
      "the widest u128")
check(AztecSignRequest.decimal(AztecPoseidon2.field("0x1" + String(repeating: "0", count: 32))!) == nil, "2^128 is not an amount")
check(AztecSignRequest.short("0x07ba1234567890abcdef00000000000000000000000000000000000000008416") == "...8416",
      "an address is its tail, never its ends (prd §1553)")
check(AztecSignRequest.short("0x07ba") == "0x07ba", "a short value is shown whole")
check(AztecSignRequest.signatureLine(r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32)).hasPrefix("casberi-aztec-sig:0101"),
      "the line the computer waits for")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AztecSignRequest, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "Casberi/Shared/AddressTail.swift" "$REQ" "$P2" "$LOG" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1
fi
SIGN_FIX="$PWD/$FIX" SIGN_FIX6="$PWD/$FIX6" "$TMP/run" || exit 1

echo
echo "mutations — each must be caught"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$REQ" "$WORK/AztecSignRequest.swift"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/AztecSignRequest.swift" <<'PY'
import os, sys
p = sys.argv[1]; s = open(p).read(); f, t = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if f not in s: sys.exit(2)
open(p, "w").write(s.replace(f, t, 1))
PY
  then echo "  ✗ $name — the mutation did not apply"; exit 1; fi
  if cmp -s "$REQ" "$WORK/AztecSignRequest.swift"; then echo "  ✗ $name — changed nothing"; exit 1; fi
  if ! swiftc -Onone -o "$TMP/mut" "Casberi/Shared/AddressTail.swift" "$WORK/AztecSignRequest.swift" "$P2" "$LOG" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if SIGN_FIX="$PWD/$FIX" SIGN_FIX6="$PWD/$FIX6" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "a mainnet request offered" \
  'guard int(r.chainId) == l1ChainID else {' \
  'guard int(r.chainId) != nil else {'
mutate "any rollup accepted" \
  '              let network = testnetRollups[version]' \
  '              let network = testnetRollups[version] ?? Optional("any")'
mutate "Aztec mainnet's rollup trusted when a node vouches" \
  'guard let version = int(r.version), !mainnetRollups.contains(version),' \
  'guard let version = int(r.version),'
mutate "mainnet's V6 rollup left off the refused list" \
  'static let mainnetRollups: Set<Int> = [4_248_422_647, 2_070_860_440, 2_934_756_905]' \
  'static let mainnetRollups: Set<Int> = [4_248_422_647, 2_934_756_905]'
mutate "mainnet's first Alpha rollup left off the refused list" \
  'static let mainnetRollups: Set<Int> = [4_248_422_647, 2_070_860_440, 2_934_756_905]' \
  'static let mainnetRollups: Set<Int> = [4_248_422_647, 2_070_860_440]'
mutate "the v6 testnet's rollup left off the list" \
  'static let testnetRollups: [Int: String] = [679_261_766: "Aztec testnet (v6)",' \
  'static let testnetRollups: [Int: String] = [679_261_767: "Aztec testnet (v6)",'
mutate "a dead release candidate kept on the list" \
  '1_821_665_230: "Aztec testnet (v5)"]' \
  '1_821_665_230: "Aztec testnet (v5)", 3_409_706_519: "Aztec testnet (v6)"]'
mutate "a call's name never checked" \
  'guard r.calls.allSatisfy({ $0.signature == nil || nameChecked($0) }) else {' \
  'guard true else {'
mutate "a signature read big-endian" \
  'fields.append(Data(chunk.reversed()))' \
  'fields.append(Data(chunk))'
mutate "a signature that names another function accepted" \
  'guard let sig = c.signature, sig.hasPrefix(c.name + "("),' \
  'guard let sig = c.signature,'
mutate "your own account drawn as an address" \
  'if let own, data == own { return String(localized: "your account") }' \
  'if let own, data == own, false { return String(localized: "your account") }'
mutate "a live reading trusted off Sepolia" \
  '$0.rollupVersion == version && $0.l1ChainID == l1ChainID ? "Aztec testnet" : nil' \
  '$0.rollupVersion == version ? "Aztec testnet" : nil'
mutate "the hash trusted, not rebuilt" \
  'guard let rebuilt = outerHash(r), rebuilt == normalized(r.messageHash) else {' \
  'guard outerHash(r) != nil || true else {'
mutate "a public call hashed as private" \
  'let isPublic = c.type == "public"' \
  'let isPublic = false'
mutate "padding hashed as zeros" \
  'payload += [AztecPoseidon2.hash([zero], separator: publicCalldata), zero, zero, one, zero, zero]' \
  'payload += [zero, zero, zero, zero, zero, zero]'
mutate "a value past the modulus signed" \
  'guard values.allSatisfy({ AztecPoseidon2.field($0).map(AztecPoseidon2.isCanonical) == true }) else {' \
  'guard values.allSatisfy({ AztecPoseidon2.field($0) != nil }) else {'
mutate "an amount shortened to its ends" \
  'return decimal(data) ?? AztecPoseidon2.hex(data)' \
  'return decimal(data).map { $0.count > 12 ? short($0) : $0 } ?? short(AztecPoseidon2.hex(data))'
mutate "the digest left unhashed" \
  'return Array(SHA256.hash(data: bytes))' \
  'return Array(bytes)'

echo "✓ Aztec signing self-test passed"
