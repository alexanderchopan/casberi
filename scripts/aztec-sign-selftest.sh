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
P2="Casberi/Casberi/Model/AztecPoseidon2.swift"
FIX="scripts/fixtures/aztec/sign-request-v5.json"
for f in "$REQ" "$P2" "$FIX"; do [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }; done
# Conduct: the signing key is reached only through the checked tray, and the
# phone never submits anything itself (no Aztec node write here).
grep -q 'AztecSignRequest.check(request)' Casberi/Casberi/Screens/AztecSignTray.swift \
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
check(AztecSignRequest.short("0x07ba1234567890abcdef00000000000000000000000000000000000000008416") == "0x07ba1234…00008416",
      "an address keeps its leading zeros and ten and eight characters")
check(AztecSignRequest.signatureLine(r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32)).hasPrefix("casberi-aztec-sig:0101"),
      "the line the computer waits for")

if failures > 0 { print("✗ \(failures) failed"); exit(1) }
SWIFT

echo "AztecSignRequest, compiled whole"
if ! swiftc -Onone -o "$TMP/run" "$REQ" "$P2" "$TMP/main.swift" > "$TMP/build.log" 2>&1; then
  echo "✗ the harness did not compile:"; sed -n '1,30p' "$TMP/build.log"; exit 1
fi
SIGN_FIX="$PWD/$FIX" "$TMP/run" || exit 1

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
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/AztecSignRequest.swift" "$P2" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if SIGN_FIX="$PWD/$FIX" "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

mutate "a mainnet request offered" \
  'guard int(r.chainId) == l1ChainID else {' \
  'guard int(r.chainId) != nil else {'
mutate "any rollup accepted" \
  'guard let version = int(r.version), let network = testnetRollups[version] else {' \
  'guard let version = int(r.version), let network = testnetRollups[version] ?? Optional("any") else {'
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
