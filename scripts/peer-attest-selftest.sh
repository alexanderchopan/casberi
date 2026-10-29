#!/bin/zsh
# Peer's enclave key and the sealed session (prd §1598 item 2, §1603).
#
#   Casberi/Casberi/Model/PeerAttestation.swift      the Nitro document, proven
#   Casberi/Casberi/Model/PeerSessionEnvelope.swift  the session, sealed to it
#
# compiled WHOLE and unmodified against one stub (`IngestSupport.getJSON`,
# the fetch this harness never makes), over a REAL document recorded from
# attestation-service.zkp2p.xyz (`scripts/support/peer-attestation-fixture.json`)
# and verified at that document's own time, so a leaf that lives hours still
# proves the chain years later.
#
# WHY. Every check here refuses a key that is not provably Peer's enclave,
# and every one fails SILENTLY when wrong: a skipped nonce, a PCR8 read from
# the service instead of the pin, a chain anchored on the system's roots or
# a signature never checked all still yield a key, the session still seals,
# the verify call still answers — and a payment app's cookies have gone to
# whoever served the document. So each refusal is asserted by a document
# broken in exactly that way, and the mutations below prove each assertion
# can fail.
#
# Independence: the enclave key's hash in the fixture and the AES-GCM vector
# were computed by Python's `cryptography`, not by the code under test; a
# Swift seal was opened by Python on 2026-10-29 (docs/peer-spec.md).
#
# Pure, local, deterministic — no network, no key, no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
ATTEST="Casberi/Casberi/Model/PeerAttestation.swift"
ENVELOPE="Casberi/Casberi/Model/PeerSessionEnvelope.swift"
FIXTURE="scripts/support/peer-attestation-fixture.json"
for f in "$ATTEST" "$ENVELOPE" "$FIXTURE"; do [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }; done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/stub.swift" <<'SWIFT'
import Foundation
enum IngestSupport {
    static func getJSON(_ url: String, headers: [String: String] = [:]) async -> Any? { nil }
}
SWIFT

cat > "$work/main.swift" <<'SWIFT'
import CryptoKit
import Foundation
import Security

var failures = 0
func check(_ ok: Bool, _ what: String) { if !ok { print("  ✗ \(what)"); failures += 1 } }
typealias A = PeerAttestation
typealias E = PeerSessionEnvelope

let fixture = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let nonce = fixture["nonce"] as! String
let doc = Data(base64Encoded: fixture["attestationDocument"] as! String)!
let at = Date(timeIntervalSince1970: (fixture["timestampMs"] as! NSNumber).doubleValue / 1000)

func refusal(_ d: Data = doc, nonce n: String = nonce, now: Date = at,
             pin: Data = A.pcr8Pin, root: Data = A.awsRootDER) -> A.Failure? {
    do { _ = try A.verify(document: d, nonce: n, now: now, pin: pin, root: root); return nil }
    catch let f as A.Failure { return f } catch { return .malformed("?") }
}
func flipped(_ d: Data, at i: Int) -> Data { var m = d; m[m.startIndex + i] ^= 0x01; return m }

// The real document, at its own time.
let key = try? A.verify(document: doc, nonce: nonce, now: at)
check(key != nil, "the recorded document verifies at its own time")
check(key?.boundKeyHex == fixture["enclaveKeySHA256"] as? String, "the bound key is the SPKI's SHA-256, as Python computed it")
check(key.map { SecKeyGetBlockSize($0.publicKey) == 256 } ?? false, "the enclave key is RSA-2048")
check(refusal(now: at.addingTimeInterval(299)) == nil, "a clock 299s off is within the window")

// Each refusal, by a document broken in exactly that way.
check(refusal(nonce: String(repeating: "0", count: 64)) == .nonce, "another nonce is refused")
check(refusal(now: at.addingTimeInterval(301)) == .stale, "a document five minutes old is refused")
check(refusal(now: at.addingTimeInterval(-301)) == .stale, "a document from the future is refused")
check(refusal(pin: flipped(A.pcr8Pin, at: 47)) == .pcr8, "another PCR8 is refused")
check(refusal(root: flipped(A.awsRootDER, at: 200)) == .root, "a root that is not AWS's is refused")
check(refusal(flipped(doc, at: doc.count - 1)) == .signature, "a flipped signature byte is refused")
if let spki = key?.spki, let r = doc.range(of: spki) {
    check(refusal(flipped(doc, at: r.lowerBound + spki.count / 2)) == .signature,
          "a key swapped inside the payload is refused: the key is what is signed")
} else { check(false, "the enclave key is found in the document") }
if let r = doc.range(of: Data([0xa1, 0x01, 0x38, 0x22])) {
    var m = doc; m[r.upperBound - 1] = 0x26
    check(refusal(m) == .algorithm, "an algorithm other than ES384 is refused")
} else { check(false, "the ES384 protected header is found") }
check(refusal(doc.prefix(doc.count / 2)) == .malformed("COSE_Sign1"), "half a document is refused")

// The chain, on its own.
if case .array(let s)? = try? PeerCBOR.decode(doc), case .bytes(let p) = s[2],
   case .map(let payload)? = try? PeerCBOR.decode(p),
   case .bytes(let leafDER)? = payload.first(where: { $0.0 == .text("certificate") })?.1,
   case .array(let items)? = payload.first(where: { $0.0 == .text("cabundle") })?.1,
   let leaf = SecCertificateCreateWithData(nil, leafDER as CFData) {
    let bundle = items.compactMap { item -> Data? in if case .bytes(let d) = item { return d } else { return nil } }
    check(bundle.count >= 3, "the bundle holds the root and its intermediates")
    check(A.chainVerifies(leaf: leaf, bundle: bundle, root: A.awsRootDER, at: at), "the chain verifies to AWS's root")
    check(A.chainVerifies(leaf: leaf, bundle: Array(bundle.reversed()), root: A.awsRootDER, at: at), "in either order")
    var gapped = bundle; gapped.remove(at: 1)
    check(!A.chainVerifies(leaf: leaf, bundle: gapped, root: A.awsRootDER, at: at), "a missing intermediate breaks it")
    check(!A.chainVerifies(leaf: leaf, bundle: bundle, root: A.awsRootDER, at: at.addingTimeInterval(86_400 * 30)),
          "a leaf past its date breaks it")
    check(refusal(root: bundle.last!) == .root, "an intermediate offered as the root is refused by its fingerprint")
} else { check(false, "the document's certificates decode") }

// CBOR, the shapes a first decoder gets wrong.
check((try? PeerCBOR.decode(Data([0xbf, 0x61, 0x61, 0x01, 0xff]))) == .map([(.text("a"), .int(1))]), "an indefinite map decodes")
check((try? PeerCBOR.decode(Data([0x5f, 0x41, 0x01, 0x42, 0x02, 0x03, 0xff]))) == .bytes(Data([1, 2, 3])), "indefinite bytes join their chunks")
check((try? PeerCBOR.decode(Data([0x38, 0x22]))) == .int(-35), "a negative integer decodes")
check((try? PeerCBOR.decode(Data([0x01, 0x01]))) == nil, "trailing bytes are refused")
check((try? PeerCBOR.decode(Data([0x9b] + [UInt8](repeating: 0xff, count: 8)))) == nil, "an impossible length is refused")
check((try? PeerCBOR.decode(Data(repeating: 0x81, count: 64) + Data([0x00]))) == nil, "nesting past 32 is refused")

// Keys.
func spki(pkcs1: Data) -> Data {
    func tlv(_ tag: UInt8, _ body: Data) -> Data {
        let n = body.count
        let len: [UInt8] = n < 128 ? [UInt8(n)] : n < 256 ? [0x81, UInt8(n)] : [0x82, UInt8(n >> 8), UInt8(n & 0xff)]
        return Data([tag] + len) + body
    }
    let alg = tlv(0x30, tlv(0x06, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])) + Data([0x05, 0x00]))
    return tlv(0x30, alg + tlv(0x03, Data([0x00]) + pkcs1))
}
func rsaPair(_ bits: Int) -> (SecKey, SecKey) {
    let priv = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits] as CFDictionary, nil)!
    return (priv, SecKeyCopyPublicKey(priv)!)
}
let (priv, pub) = rsaPair(2048)
let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil)! as Data
check(A.rsaPublicKey(spki: spki(pkcs1: pkcs1)) != nil, "an RSA-2048 SPKI imports")
check(A.rsaPublicKey(spki: pkcs1) == nil, "a bare PKCS#1 key is not an SPKI")
check(A.rsaPublicKey(spki: spki(pkcs1: pkcs1).dropLast()) == nil, "a truncated SPKI is refused")
let small = SecKeyCopyExternalRepresentation(rsaPair(1024).1, nil)! as Data
check(A.rsaPublicKey(spki: spki(pkcs1: small)) == nil, "an RSA-1024 key is refused")
var ecSPKI = spki(pkcs1: pkcs1)
if let r = ecSPKI.range(of: Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01])) { ecSPKI[r.upperBound - 1] = 0x05 }
check(A.rsaPublicKey(spki: ecSPKI) == nil, "another algorithm's OID is refused")

// The envelope.
let pt = try! E.plaintext(platform: "revolut", actionType: "transfer_revolut",
                          session: ["Cookie": "a=1; b=2", "x-device-id": "dev"],
                          boundKeyHex: "453d44a9f8edec2f9d4ed627d5a6b5e85d82af1f84a03d420d39621c31b039fa")
check(String(decoding: pt, as: UTF8.self) == #"{"actionType":"transfer_revolut","boundPubKeySha256":"453d44a9f8edec2f9d4ed627d5a6b5e85d82af1f84a03d420d39621c31b039fa","platform":"revolut","sessionMaterial":{"Cookie":"a=1; b=2","x-device-id":"dev"}}"#,
      "the plaintext is the four fields the enclave's schema takes, and nothing else")
let fixed = try! E.seal(pt, to: pub, contentKey: SymmetricKey(data: Data(0..<32)),
                        iv: try! AES.GCM.Nonce(data: Data(0..<12)))
let parts = fixed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
check(parts.count == 5, "compact JWE has five parts")
check(parts.first == "eyJhbGciOiJSU0EtT0FFUC0yNTYiLCJlbmMiOiJBMjU2R0NNIn0", "the protected header is RSA-OAEP-256 / A256GCM")
check(parts.count == 5 && parts[2] == "AAECAwQFBgcICQoL", "the IV is the twelve bytes it was given")
check(parts.count == 5 && parts[3] == "PCC3eLGMrXXZOOfuk9NaGfG36UeWHi0jSgKT6nEcdJAtMsyT2q92yAHGNIjx1EBZ3GxWr2D0l-8M8x4tedqT1pVYoxnhtx8FKDHOWN24at1ZvKtXE1tmDMXP_6pJloG5qshqgpBz-H6tJQiAeRYSTthXUZKFpAe2b487rPaAAXzWcDrkxrK9PGSUPIMR-D-nRYeKWltc8j7pLYEWlvDTlbHU8XqClqlcnUG8x-67ptmg_OgOqdNe2ACpqaQU6N6XMXaonmir9LRK",
      "the ciphertext matches Python's AES-GCM over the same key, IV and header")
check(parts.count == 5 && parts[4] == "gDRwQG9osjj4H5lAFDOFrg", "and so does the tag: the header is the AAD")
func b64u(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}
let cek = parts.count == 5 ? b64u(parts[1]).flatMap { SecKeyCreateDecryptedData(priv, .rsaEncryptionOAEPSHA256, $0 as CFData, nil) as Data? } : nil
check(cek == Data(0..<32), "the content key unwraps with RSA-OAEP-256")
let fresh1 = try! E.seal(pt, to: pub), fresh2 = try! E.seal(pt, to: pub)
let f1 = fresh1.split(separator: "."), f2 = fresh2.split(separator: ".")
check(f1[1] != f2[1] && f1[2] != f2[2], "two seals draw a fresh key and a fresh IV")
check(b64u(String(f1[2]))?.count == 12 && b64u(String(f1[4]))?.count == 16, "a twelve-byte IV and a sixteen-byte tag")
if let cek1 = b64u(String(f1[1])).flatMap({ SecKeyCreateDecryptedData(priv, .rsaEncryptionOAEPSHA256, $0 as CFData, nil) as Data? }),
   let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: b64u(String(f1[2]))!),
                                    ciphertext: b64u(String(f1[3]))!, tag: b64u(String(f1[4]))!) {
    check((try? AES.GCM.open(box, using: SymmetricKey(data: cek1), authenticating: Data(String(f1[0]).utf8))) == pt,
          "a fresh seal opens to the plaintext")
    check((try? AES.GCM.open(box, using: SymmetricKey(data: cek1), authenticating: Data("x".utf8))) == nil,
          "and not under another header")
} else { check(false, "a fresh seal unwraps") }
if let key {
    let real = try? E.seal(platform: "revolut", actionType: "transfer_revolut", session: ["Cookie": "a=1"], to: key)
    check(real.map { b64u(String($0.split(separator: ".")[1]))?.count == 256 } ?? false,
          "a seal to the real enclave key wraps to its 256 bytes")
}

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   the document proven (nonce, time, PCR8, AWS root, chain, signature, key), the session sealed as Peer's enclave reads it")
SWIFT

xcrun swiftc -O "$ATTEST" "$ENVELOPE" "$work/stub.swift" "$work/main.swift" -o "$work/t" 2>&1 | grep -v "^$" || true
[[ -x "$work/t" ]] || fail "the shipped sources did not compile"
"$work/t" "$FIXTURE" || fail "assertions failed against the shipped sources"

mutate() {
  local why="$1" file="$2" expr="$3"
  cp "$ATTEST" "$work/a.swift"; cp "$ENVELOPE" "$work/e.swift"
  local target="$work/a.swift"; [[ "$file" == envelope ]] && target="$work/e.swift"
  perl -0pi -e "$expr" "$target"
  cmp -s "$ATTEST" "$work/a.swift" && cmp -s "$ENVELOPE" "$work/e.swift" && fail "mutation matched nothing: $why"
  xcrun swiftc -O "$work/a.swift" "$work/e.swift" "$work/stub.swift" "$work/main.swift" -o "$work/m" >/dev/null 2>&1 \
    || fail "mutation did not compile: $why"
  if "$work/m" "$FIXTURE" >/dev/null 2>&1; then fail "mutation SURVIVED — $why"; fi
  print "  ok   catches  $why"
}
mutate "the nonce never checked"        attest 's/userData == Data\(nonce\.utf8\)/!userData.isEmpty/'
mutate "the clock never checked"        attest 's/abs\(stamped\.timeIntervalSince\(now\)\) <= maxSkew/stamped > .distantPast/'
mutate "PCR8 never pinned"              attest 's/case \.bytes\(let pcr8\)\? = pcrs\.value\(\.int\(8\)\), pcr8 == pin/case .bytes? = pcrs.value(.int(8))/'
mutate "the root never fingerprinted"   attest 's/guard SHA256\.hash\(data: root\)\.hex == awsRootSHA256 else \{ throw Failure\.root \}|guard hexString\(SHA256\.hash\(data: root\)\) == awsRootSHA256 else \{ throw Failure\.root \}//'
mutate "the system's roots trusted too" attest 's/SecTrustSetAnchorCertificatesOnly\(trust, true\)/SecTrustSetAnchorCertificatesOnly(trust, false)/; s/SecTrustSetAnchorCertificates\(trust, \[anchor\] as CFArray\) == errSecSuccess,\n//'
mutate "the chain never evaluated"      attest 's/return SecTrustEvaluateWithError\(trust, nil\)/return true/'
mutate "the signature never checked"    attest 's/signer\.isValidSignature\(sig, for: toSign\)/signer.rawRepresentation.count > 0/'
mutate "the payload not what is signed" attest 's/PeerCBOR\.encodeBytes\(Data\(\)\) \+ PeerCBOR\.encodeBytes\(payloadBytes\)/PeerCBOR.encodeBytes(Data()) + PeerCBOR.encodeBytes(protected)/'
mutate "any algorithm accepted"         attest 's/header\.value\(\.int\(1\)\) == \.int\(-35\), //'
mutate "indefinite lengths dropped"     attest 's/if info == 31 \{/if info == 31 \&\& false {/'
mutate "small RSA keys accepted"        attest 's/SecKeyGetBlockSize\(key\) >= 256/SecKeyGetBlockSize(key) >= 128/'
mutate "OAEP with SHA-1"                envelope 's/\.rsaEncryptionOAEPSHA256/.rsaEncryptionOAEPSHA1/g'
mutate "the header not authenticated"   envelope 's/authenticating: Data\(protectedHeader\.utf8\)/authenticating: Data()/'
mutate "padded base64"                  envelope 's/\.replacingOccurrences\(of: "=", with: ""\)//'
mutate "the bound key left out"         envelope 's/"boundPubKeySha256": boundKeyHex\]/"boundPubKeySha256": ""]/'
