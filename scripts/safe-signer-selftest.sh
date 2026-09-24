#!/bin/zsh
# Casberi signer self-test, the §913 half — the arithmetic behind the three
# things the co-signer signs beyond a Safe transaction, and the one way it is
# asked (prd §913, docs/signer-spec.md §12).
#
#   Casberi/Casberi/Model/SafeTypedData.swift          EIP-712 in general
#   Casberi/Casberi/Model/SafeStatement.swift          Safe messages, SIWE, Snapshot
#   Casberi/Casberi/Model/SafeRecovery.swift           Candide's ExecuteRecovery
#   Casberi/Casberi/Model/SafeWebAuthnSignature.swift  the Enclave owner's bytes, SHA-256
#   Casberi/Casberi/Model/SafePeerRequest.swift        the allowlist and the three shapes
#
# compiled WHOLE and unmodified, with `SafeTransaction.swift`, `Keccak256.swift`
# and `ClearSign.swift` beside them (the encoders lean on `SafeABI`), and pinned
# to what `scripts/support/safe-signer-vectors.py` derives — which proves its
# own Keccak and SHA-256 first and reproduces the spec's "Ether Mail" digest,
# Safe's published `SafeMessage` typehash and Candide's two published hashes
# before it prints a number.
#
# WHY. `safetx-selftest.sh` guards a wrong SafeTx signature. This guards the
# three new preimages, each of which fails the same way: a wrong SafeMessage
# hash is a signature Safe's service rejects (fine) or one over a different
# statement (not fine); a wrong recovery hash approves a DIFFERENT owner set;
# a wrong WebAuthn digest is a signature the factory refuses — the on-chain
# rail catches that last one, and this harness is why it never has to.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
CLEARSIGN="Casberi/Casberi/Model/ClearSign.swift"
TYPED="Casberi/Casberi/Model/SafeTypedData.swift"
STATEMENT="Casberi/Casberi/Model/SafeStatement.swift"
RECOVERY="Casberi/Casberi/Model/SafeRecovery.swift"
WEBAUTHN="Casberi/Casberi/Model/SafeWebAuthnSignature.swift"
PEERREQ="Casberi/Casberi/Model/SafePeerRequest.swift"
PEER="Casberi/Casberi/Model/SafePeer.swift"
STATEMENT_SIGNER="Casberi/Casberi/Model/SafeStatementSigner.swift"
RECOVERY_SIGNER="Casberi/Casberi/Model/SafeRecoverySigner.swift"
ENCLAVE_KEY="Casberi/Casberi/Model/SafeEnclaveKey.swift"
ENCLAVE_SIGNER="Casberi/Casberi/Model/SafeEnclaveSigner.swift"
SIGNER="Casberi/Casberi/Model/SafeSigner.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
VECTORS="scripts/support/safe-signer-vectors.py"
for f in "$TX" "$KECCAK" "$CLEARSIGN" "$TYPED" "$STATEMENT" "$RECOVERY" "$WEBAUTHN" "$PEERREQ" \
         "$PEER" "$STATEMENT_SIGNER" "$RECOVERY_SIGNER" "$ENCLAVE_KEY" "$ENCLAVE_SIGNER" "$SIGNER" \
         "$REACH" "$VECTORS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- the source of the fixtures ---------------------------------------------
python3 "$VECTORS" --self-test >/dev/null \
  || { echo "✗ scripts/support/safe-signer-vectors.py failed its own self-test — the fixtures are not evidence"; exit 1; }
VECOUT=$(python3 "$VECTORS")

TMP=$(mktemp -d /tmp/safe-signer-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
print("\n".join(re.sub(r"//.*$", "", line) for line in src.splitlines()))
PY
}

# --- drift guards -----------------------------------------------------------

# THE NO-OTHER-SIGNING-ENTRY-POINT GUARD, extended (spec §8.4 → §12). The
# peer offers typed-data signing and nothing else, and it keeps that promise
# by these files containing no other path: no sending, no personal_sign of
# free text, no raw eth_sign. Read from comment-stripped copies — the files
# document what they refuse.
for f in "$PEERREQ" "$PEER" "$TYPED" "$STATEMENT" "$RECOVERY" "$WEBAUTHN" "$STATEMENT_SIGNER" "$RECOVERY_SIGNER"; do
  CODE=$(strip_comments "$f")
  for forbidden in 'personal_sign' 'eth_sign"' 'eth_sendTransaction' 'eth_sendRawTransaction' 'wallet_sendCalls' 'Ethereum Signed Message:\\n32'; do
    printf '%s' "$CODE" | grep -qF -- "$forbidden" \
      && { echo "✗ $f now contains a $forbidden path — this phone signs a Safe transaction, statement or recovery and nothing else (prd §913)"; exit 1; }
  done
done
# EIP-191's prefix is allowed in ONE file, for hashing a sign-in's text —
# never with the 32-byte `eth_sign` form, which the loop above forbids.
[[ $(strip_comments "$STATEMENT" | grep -c 'Ethereum Signed Message:') -eq 1 ]] \
  || { echo "✗ the EIP-191 prefix must appear exactly once, in SafeStatement.swift's hash of a sign-in"; exit 1; }

# The pure files reach nothing at all.
for f in "$TYPED" "$STATEMENT" "$RECOVERY" "$WEBAUTHN" "$PEERREQ"; do
  CODE=$(strip_comments "$f")
  for reach in 'URLSession' 'IngestSupport' 'SecItemAdd' 'import Security' 'import SwiftData' 'import SwiftUI' 'import CryptoKit' 'UserDefaults'; do
    printf '%s' "$CODE" | grep -qF -- "$reach" \
      && { echo "✗ $f reached $reach — it must stay Foundation-only so this harness can compile it whole"; exit 1; }
  done
done

# The allowlist is the door, spelled once, and it is two typed-data methods.
PEERREQ_CODE=$(strip_comments "$PEERREQ")
printf '%s' "$PEERREQ_CODE" | grep -q 'static let allowedMethods: Set<String> = \["eth_signTypedData_v4", "eth_signTypedData"\]' \
  || { echo "✗ SafePeerRequest.allowedMethods changed — the methods a paired app may call are a ruling, not a line"; exit 1; }
printf '%s' "$PEERREQ_CODE" | grep -q 'guard allowedMethods.contains(method) else { return .failure(.methodNotOffered(method)) }' \
  || { echo "✗ the peer no longer refuses a method before parsing its params"; exit 1; }
# …and the peer advertises exactly that list to a proposal.
PEER_CODE=$(strip_comments "$PEER")
printf '%s' "$PEER_CODE" | grep -q 'methods: Array(SafePeerRequest.allowedMethods),' \
  || { echo "✗ SafePeer no longer settles sessions with SafePeerRequest.allowedMethods — the offer and the door drifted apart"; exit 1; }
# The peer transports; it never signs. No key file, no curve.
for reach in 'SignerKey.sign' 'SafeEnclaveKey.sign' 'P256K' 'CryptoKit'; do
  printf '%s' "$PEER_CODE" | grep -qF -- "$reach" \
    && { echo "✗ SafePeer.swift reached $reach — the peer transports and the signers decide"; exit 1; }
done
# A request must name one of this phone's addresses before it is shown.
printf '%s' "$PEER_CODE" | grep -q 'guard identities.contains(where: { $0.address.lowercased() == parsed.address.lowercased() }) else {' \
  || { echo "✗ SafePeer no longer checks that a request is addressed to this phone"; exit 1; }

# The type strings are the contracts', verbatim.
grep -q 'static let typeString = "SafeMessage(bytes message)"' "$STATEMENT" \
  || { echo "✗ the SafeMessage type string changed"; exit 1; }
grep -q '"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"' "$RECOVERY" \
  || { echo "✗ the recovery module's domain type string changed"; exit 1; }
grep -q '"ExecuteRecovery(address wallet,address\[\] newOwners,uint256 newThreshold,uint256 nonce)"' "$RECOVERY" \
  || { echo "✗ the ExecuteRecovery type string changed"; exit 1; }
grep -q 'static let moduleName = "Social Recovery Module"' "$RECOVERY" \
  || { echo "✗ the recovery module's NAME() changed"; exit 1; }

# THE REFUSALS THAT CARRY THE PROMISE, as greps, because the signers reach
# the network and cannot be compiled here. Each is mutation-proven below.
guard_check() {   # $1 = SafeStatementSigner path, $2 = SafeRecoverySigner path, $3 = SafeEnclaveSigner path, $4 = SafeEnclaveKey path
  local st="$1" rc="$2" es="$3" ek="$4"
  local st_code rc_code es_code ek_code
  st_code=$(strip_comments "$st"); rc_code=$(strip_comments "$rc")
  es_code=$(strip_comments "$es"); ek_code=$(strip_comments "$ek")
  # A statement: only a NAMED one is signed, and the words must hash to the ask.
  printf '%s' "$st_code" | grep -q 'if case .unreadable(let why) = reading.statement { return .failure(.unreadable(why: why)) }' || return 1
  printf '%s' "$st_code" | grep -q 'guard reading.hash == innerHash else { return .failure(.messageMismatch) }' || return 1
  # …the Safe's own hash of it, from the chain, and the threshold.
  printf '%s' "$st_code" | grep -q 'guard threshold >= 2 else { return .failure(.thresholdTooLow(threshold)) }' || return 1
  printf '%s' "$st_code" | grep -q 'SafeMessageEncoder.getMessageHashCalldata(message: innerHash)' || return 1
  printf '%s' "$st_code" | grep -q 'guard chain.lowercased() == local.lowercased() else {' || return 1
  # …and both writes go to Safe's service alone.
  [[ $(printf '%s' "$st_code" | grep -o 'postJSONStatus\|postJSON(' | wc -l | tr -d ' ') -eq 2 ]] || return 1
  for host in $(printf '%s' "$st_code" | grep -oE 'https://[a-z0-9.-]+' | sort -u); do
    case "$host" in
      https://safe-client.safe.global|https://api.safe.global|https://app.safe.global) ;;
      *) return 1 ;;
    esac
  done
  # A recovery: the module is read for who it is, the wallet for whether it
  # enabled it, the module for whether this phone guards it, a lone guardian
  # is refused, a stale nonce is refused, and the module's own hash decides.
  printf '%s' "$rc_code" | grep -q 'guard SafeRecovery.decodeString(nameHex) == SafeRecovery.moduleName else {' || return 1
  printf '%s' "$rc_code" | grep -q 'guard enabled else { return .failure(.moduleNotEnabled) }' || return 1
  printf '%s' "$rc_code" | grep -q 'guard let signer else { return .failure(.notAGuardian) }' || return 1
  printf '%s' "$rc_code" | grep -q 'guard guardianThreshold >= 2 else { return .failure(.guardianThresholdTooLow(guardianThreshold)) }' || return 1
  printf '%s' "$rc_code" | grep -q 'guard nonce == request.nonce else { return .failure(.staleNonce(module: nonce)) }' || return 1
  printf '%s' "$rc_code" | grep -q 'SafeRecovery.getRecoveryHashCalldata(request)' || return 1
  printf '%s' "$rc_code" | grep -q 'guard chain.lowercased() == local.lowercased() else {' || return 1
  # No write at all from the recovery signer.
  printf '%s' "$rc_code" | grep -q 'postJSON\|https://' && return 1
  # The Enclave assertion leaves only with the factory's magic value.
  printf '%s' "$es_code" | grep -q 'guard SafeWebAuthn.isMagic(answer) else { return .failure(.notAccepted) }' || return 1
  printf '%s' "$es_code" | grep -q 'else { return .failure(.chainUnreadable) }' || return 1
  # The Enclave key: `.privateKeyUsage` WITH `.biometryCurrentSet`, device-only,
  # the pre-hashed overload, and one reader of the wrapped blob.
  printf '%s' "$ek_code" | grep -q '\[.privateKeyUsage, .biometryCurrentSet\]' || return 1
  printf '%s' "$ek_code" | grep -q 'kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly' || return 1
  printf '%s' "$ek_code" | grep -q 'signature = try key.signature(for: SafeEnclaveDigest(Data(digest)))' || return 1
  [[ $(printf '%s' "$ek_code" | grep -o 'kSecReturnData as String: true' | wc -l | tr -d ' ') -eq 1 ]] || return 1
  printf '%s' "$ek_code" | grep -q 'kSecReturnAttributes as String: true' || return 1
  return 0
}
guard_check "$STATEMENT_SIGNER" "$RECOVERY_SIGNER" "$ENCLAVE_SIGNER" "$ENCLAVE_KEY" \
  || { echo "✗ a §913 refusal is missing or weakened — run guard_check in scripts/safe-signer-selftest.sh"; exit 1; }
echo "  ✓ the §913 refusals are in the shipped signers"

# The privacy screen says what the signers do now.
grep -q 'read back from Safe'"'"'s service by its hash' "$REACH" \
  || { echo "✗ NetworkReach no longer says a statement is read back from Safe's service (prd §913)"; exit 1; }
grep -q 'passkey factory on the chain is asked to verify' "$REACH" \
  || { echo "✗ NetworkReach no longer says the Enclave signature is verified by Safe's factory (prd §913)"; exit 1; }

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func hex(_ b: [UInt8]) -> String { "0x" + Keccak256.hexString(b) }
func h(_ s: String) -> [UInt8] { SafeABI.hexBytes(s)! }

let SAFE = "0x1234567890123456789012345678901234567890"
let TO   = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
let MODULE = "0x949d01d424be050d09c16025dd007cb59b3a8c66"

print("SHA-256 — the FIPS vectors, before the WebAuthn digest is trusted")
check("sha256(\"\")", hex(SHA256Digest.hash([])) == "0xe3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256(\"abc\")", hex(SHA256Digest.hash(Array("abc".utf8))) == "0xba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256(two-block message)",
      hex(SHA256Digest.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)))
        == "0x248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
check("sha256 of 200 bytes is 32 bytes", SHA256Digest.hash([UInt8](repeating: 0x61, count: 200)).count == 32)

print("EIP-712 in general — the spec's own vector, then the SafeTx encoder it must agree with")
let mail = """
{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"Person":[{"name":"name","type":"string"},{"name":"wallet","type":"address"}],"Mail":[{"name":"from","type":"Person"},{"name":"to","type":"Person"},{"name":"contents","type":"string"}]},"primaryType":"Mail","domain":{"name":"Ether Mail","version":"1","chainId":1,"verifyingContract":"0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"},"message":{"from":{"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},"to":{"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},"contents":"Hello, Bob!"}}
"""
guard let mailTyped = EIP712.parse(mail) else { print("  ✗ the Ether Mail envelope did not parse"); exit(1) }
check("encodeType orders dependencies after the primary, alphabetically",
      EIP712.encodeType("Mail", types: mailTyped.types)
        == "Mail(Person from,Person to,string contents)Person(string name,address wallet)")
check("Ether Mail digest (EIP-712's published vector)",
      EIP712.digest(mailTyped).map(hex) == "0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2")

let safeTxTyped = """
{"types":{"SafeTx":[{"name":"to","type":"address"},{"name":"value","type":"uint256"},{"name":"data","type":"bytes"},{"name":"operation","type":"uint8"},{"name":"safeTxGas","type":"uint256"},{"name":"baseGas","type":"uint256"},{"name":"gasPrice","type":"uint256"},{"name":"gasToken","type":"address"},{"name":"refundReceiver","type":"address"},{"name":"nonce","type":"uint256"}]},"primaryType":"SafeTx","domain":{"chainId":1,"verifyingContract":"0x1234567890123456789012345678901234567890"},"message":{"to":"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","value":"1000000000000000000","data":"0x","operation":0,"safeTxGas":0,"baseGas":0,"gasPrice":0,"gasToken":"0x0000000000000000000000000000000000000000","refundReceiver":"0x0000000000000000000000000000000000000000","nonce":0}}
"""
guard let txTyped = EIP712.parse(safeTxTyped) else { print("  ✗ the SafeTx envelope did not parse"); exit(1) }
check("the general encoder reproduces safetx fixture #1",
      EIP712.digest(txTyped).map(hex) == "0x60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d")
check("a uint8 wider than its type is refused",
      EIP712.encodeValue(type: "uint8", value: .number(256), types: [:]) == nil)
check("a negative integer is refused",
      EIP712.encodeValue(type: "uint256", value: .string("-1"), types: [:]) == nil)
check("a bytes32 of the wrong length is refused",
      EIP712.encodeValue(type: "bytes32", value: .string("0x" + String(repeating: "ab", count: 31)), types: [:]) == nil)
check("an unknown type is refused",
      EIP712.encodeValue(type: "uint7", value: .number(1), types: [:]) == nil)
check("a fixed array with the wrong count is refused",
      EIP712.encodeValue(type: "uint32[2]", value: .array([.number(1)]), types: [:]) == nil)

print("Safe messages")
check("SAFE_MSG_TYPEHASH matches CompatibilityFallbackHandler.sol",
      hex(SafeMessageEncoder.typeHash) == "0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca")
let siwe = """
app.safe.global wants you to sign in with your Ethereum account:
0x1234567890123456789012345678901234567890

Sign in to Snapshot with your Safe.

URI: https://app.safe.global
Version: 1
Chain ID: 1
Nonce: 32891756
Issued At: 2026-09-24T10:00:00.000Z
Expiration Time: 2026-09-24T11:00:00.000Z
"""
check("the SIWE fixture's EIP-191 hash",
      hex(EIP191.hash(text: siwe)) == "0x0561ebd8eb761945b4f6409691f7985ec0c0292575aa4da3287544f30fa9186f")
guard let signIn = SafeStatement.read(message: siwe, safe: SAFE) else { print("  ✗ SIWE unreadable"); exit(1) }
check("a sign-in for the Safe is NAMED", signIn.statement.isNamed)
if case .signIn(let parsed) = signIn.statement {
    check("…and its fields are read", parsed.domain == "app.safe.global" && parsed.chainId == 1 && parsed.nonce == "32891756"
          && parsed.statement == "Sign in to Snapshot with your Safe." && parsed.expirationTime == "2026-09-24T11:00:00.000Z")
} else { check("…and its fields are read", false) }
check("a trailing newline (a paste) reads the same",
      SafeStatement.read(message: siwe + "\n", safe: SAFE)?.hash == signIn.hash)
check("the SIWE safeMessageHash on mainnet",
      SafeMessageEncoder.safeMessageHash(chainId: 1, safe: SAFE, message: signIn.hash).map(hex)
        == "0x320b256597f39833cfb3cc7b36e551490567afdfa32d2f99a7e59bf211d49a8a")
check("a sign-in for ANOTHER address is unreadable, and still hashed",
      SafeStatement.read(message: siwe, safe: TO).map { !$0.statement.isNamed && $0.hash == signIn.hash } == true)
check("free text is unreadable",
      SafeStatement.read(message: "please sign this", safe: SAFE)?.statement.isNamed == false)
check("a sign-in with no nonce does not parse",
      SIWEMessage.parse(siwe.replacingOccurrences(of: "Nonce: 32891756\n", with: "")) == nil)
check("a sign-in with an unknown field does not parse",
      SIWEMessage.parse(siwe + "\nPermit: everything") == nil)

let vote = """
{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"}],"Vote":[{"name":"from","type":"address"},{"name":"space","type":"string"},{"name":"timestamp","type":"uint64"},{"name":"proposal","type":"bytes32"},{"name":"choice","type":"uint32"},{"name":"reason","type":"string"},{"name":"app","type":"string"},{"name":"metadata","type":"string"}]},"primaryType":"Vote","domain":{"name":"snapshot","version":"0.1.4"},"message":{"from":"0x1234567890123456789012345678901234567890","space":"ens.eth","timestamp":1790000000,"proposal":"0xabababababababababababababababababababababababababababababababab","choice":1,"reason":"","app":"snapshot","metadata":"{}"}}
"""
let voteObject = try! JSONSerialization.jsonObject(with: vote.data(using: .utf8)!) as! [String: Any]
guard let voteRead = SafeStatement.read(message: voteObject, safe: SAFE) else { print("  ✗ vote unreadable"); exit(1) }
check("the Snapshot vote fixture's digest",
      hex(voteRead.hash) == "0xb98c2d8baa4cb422fde55dd8a84916803e384c4bf259d845c6e2d067a169439d")
check("a Snapshot vote from the Safe is NAMED", voteRead.statement.isNamed)
if case .snapshotVote(let v) = voteRead.statement {
    check("…and reads its space and choice", v.space == "ens.eth" && v.choice == "1" && v.reason == nil)
} else { check("…and reads its space and choice", false) }
check("the vote safeMessageHash on mainnet",
      SafeMessageEncoder.safeMessageHash(chainId: 1, safe: SAFE, message: voteRead.hash).map(hex)
        == "0xc09e68e9c82528fd200c3cc14b21896a685ce3611962ffe42b5811eabedc6fb2")
var order = voteObject; order["domain"] = ["name": "CoW Swap", "version": "1"]; order["primaryType"] = "Order"
order["types"] = ["EIP712Domain": [["name": "name", "type": "string"], ["name": "version", "type": "string"]],
                  "Order": [["name": "from", "type": "address"]]]
order["message"] = ["from": SAFE]
check("typed data in another domain is unreadable", SafeStatement.read(message: order, safe: SAFE)?.statement.isNamed == false)
check("getMessageHash(bytes) calldata",
      SafeMessageEncoder.getMessageHashCalldata(message: signIn.hash)
        == "0x0a1028c4" + "0000000000000000000000000000000000000000000000000000000000000020"
           + "0000000000000000000000000000000000000000000000000000000000000020"
           + String(hex(signIn.hash).dropFirst(2)))

print("the recovery module")
check("DOMAIN_SEPARATOR_TYPEHASH matches SocialRecoveryModule.sol",
      hex(SafeRecovery.domainTypeHash) == "0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f")
check("EXECUTE_RECOVERY_TYPEHASH matches SocialRecoveryModule.sol",
      hex(SafeRecovery.executeRecoveryTypeHash) == "0x124b64921a7c7e677c6cc3b132eaaa57130bc6fc05ab157f35fe5264a7c198d5")
let recovery = SafeRecovery.Request(chainId: 1, module: MODULE, wallet: SAFE,
                                    newOwners: [TO, "0x1111111111111111111111111111111111111111"],
                                    newThreshold: 1, nonce: 3,
                                    name: SafeRecovery.moduleName, version: "0.2.0")
check("the recovery domain separator",
      SafeRecovery.domainSeparator(recovery).map(hex) == "0xc003a90f91e2f4a8cdf211feb002f77a3a44e8cee1e1312b1dddfdcc08cd7b4b")
check("the recovery hash fixture",
      SafeRecovery.recoveryHash(recovery).map(hex) == "0xfcbf27ae9b93d8ce65b4aba98b1d90d6bdb80fecc2196e98c3d553ee11ed3be8")
let reordered = SafeRecovery.Request(chainId: 1, module: MODULE, wallet: SAFE,
                                     newOwners: ["0x1111111111111111111111111111111111111111", TO],
                                     newThreshold: 1, nonce: 3, name: SafeRecovery.moduleName, version: "0.2.0")
check("owner order is inside the hash", SafeRecovery.recoveryHash(reordered) != SafeRecovery.recoveryHash(recovery))
let later = SafeRecovery.Request(chainId: 1, module: MODULE, wallet: SAFE, newOwners: recovery.newOwners,
                                 newThreshold: 1, nonce: 4, name: SafeRecovery.moduleName, version: "0.2.0")
check("the nonce is inside the hash", SafeRecovery.recoveryHash(later) != SafeRecovery.recoveryHash(recovery))
let elsewhere = SafeRecovery.Request(chainId: 8453, module: MODULE, wallet: SAFE, newOwners: recovery.newOwners,
                                     newThreshold: 1, nonce: 3, name: SafeRecovery.moduleName, version: "0.2.0")
check("the chain is inside the hash", SafeRecovery.recoveryHash(elsewhere) != SafeRecovery.recoveryHash(recovery))
check("a threshold above the owner count is refused",
      SafeRecovery.structHash(SafeRecovery.Request(chainId: 1, module: MODULE, wallet: SAFE, newOwners: [TO],
                                                   newThreshold: 2, nonce: 3, name: SafeRecovery.moduleName, version: "0.2.0")) == nil)
check("an empty owner set is refused",
      SafeRecovery.structHash(SafeRecovery.Request(chainId: 1, module: MODULE, wallet: SAFE, newOwners: [],
                                                   newThreshold: 1, nonce: 3, name: SafeRecovery.moduleName, version: "0.2.0")) == nil)
let recoveryTyped = """
{"types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"ExecuteRecovery":[{"name":"wallet","type":"address"},{"name":"newOwners","type":"address[]"},{"name":"newThreshold","type":"uint256"},{"name":"nonce","type":"uint256"}]},"primaryType":"ExecuteRecovery","domain":{"name":"Social Recovery Module","version":"0.2.0","chainId":1,"verifyingContract":"0x949d01d424be050d09c16025dd007cb59b3a8c66"},"message":{"wallet":"0x1234567890123456789012345678901234567890","newOwners":["0xabcdefabcdefabcdefabcdefabcdefabcdefabcd","0x1111111111111111111111111111111111111111"],"newThreshold":1,"nonce":3}}
"""
guard let recTyped = EIP712.parse(recoveryTyped), let recRequest = SafeRecovery.request(from: recTyped) else {
    print("  ✗ the ExecuteRecovery envelope did not read"); exit(1)
}
check("the typed-data door reads the same request", recRequest == recovery)
check("the general encoder and the contract's own hash agree on ExecuteRecovery",
      EIP712.digest(recTyped) == SafeRecovery.recoveryHash(recovery))
check("getRecoveryHash calldata carries the owner array after a 4-word head",
      SafeRecovery.getRecoveryHashCalldata(recovery)?.hasPrefix("0x5f19df08"
        + "000000000000000000000000" + String(SAFE.dropFirst(2))
        + "0000000000000000000000000000000000000000000000000000000000000080") == true)
check("isGuardian selector", SafeRecovery.isGuardianCalldata(wallet: SAFE, guardian: TO)?.hasPrefix("0xd4ee9734") == true)
check("isModuleEnabled selector", SafeRecovery.isModuleEnabledCalldata(module: MODULE)?.hasPrefix("0x2d9ad53d") == true)
check("NAME() selector", SafeRecovery.nameSelector == "0xa3f4df7e")
check("a string return decodes",
      SafeRecovery.decodeString("0x" + "0000000000000000000000000000000000000000000000000000000000000020"
                                + "0000000000000000000000000000000000000000000000000000000000000016"
                                + "536f6369616c205265636f76657279204d6f64756c6500000000000000000000") == "Social Recovery Module")
check("a bool return decodes, and 2 is not a bool",
      SafeRecovery.decodeBool("0x0000000000000000000000000000000000000000000000000000000000000001") == true
      && SafeRecovery.decodeBool("0x0000000000000000000000000000000000000000000000000000000000000002") == nil)

print("the Enclave owner's bytes")
check("verifiers packs the precompile above Daimo's verifier",
      SafeWebAuthn.verifiersWord.map(hex) == "0x000000000000000000000100c2b78104907f722dabac4c69f826a522b2754de4")
check("authenticatorData: sha256(rpID) ‖ 0x05 ‖ 0",
      hex(SafeWebAuthn.authenticatorData) == "0xa27e23df90f851506774528f4a41fd2beb53e46e6e4d3a8909af195acb4d4a850500000000")
let challenge = h("0x60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d")
check("clientDataJSON byte for byte",
      SafeWebAuthn.clientDataJSON(challenge: challenge)
        == "{\"type\":\"webauthn.get\",\"challenge\":\"YFURkO73VHTKBjzOqRzzJG6S0gvJ7tWAje5tPRAogY0\",\"origin\":\"https://casberi.app\",\"crossOrigin\":false}")
check("the signing digest", SafeWebAuthn.signingDigest(challenge: challenge).map(hex)
        == "0x1d4b33fa937e50420c4199ed824babe1bcb5222646c3c5b8bfc8315956e0330c")
let r = [UInt8](repeating: 0x33, count: 32), s = [UInt8](repeating: 0x44, count: 32)
let sig = SafeWebAuthn.signatureBytes(r: r, s: s)
check("signature bytes: abi.encode(bytes, string, uint256, uint256)",
      sig.map(hex) == "0x000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000e0333333333333333333333333333333333333333333333333333333333333333344444444444444444444444444444444444444444444444444444444444444440000000000000000000000000000000000000000000000000000000000000025a27e23df90f851506774528f4a41fd2beb53e46e6e4d3a8909af195acb4d4a8505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000032226f726967696e223a2268747470733a2f2f636173626572692e617070222c2263726f73734f726967696e223a66616c73650000000000000000000000000000")
check("the contract-signature envelope: r = signer, s = 65, v = 0, then length ‖ data",
      SafeWebAuthn.contractSignature(signer: "0x5555555555555555555555555555555555555555", data: sig!).map(hex)
        == "0x00000000000000000000000055555555555555555555555555555555555555550000000000000000000000000000000000000000000000000000000000000041000000000000000000000000000000000000000000000000000000000000000140" + String(hex(sig!).dropFirst(2)))
let x = [UInt8](repeating: 0x11, count: 32), y = [UInt8](repeating: 0x22, count: 32)
check("getSigner calldata",
      SafeWebAuthn.getSignerCalldata(x: x, y: y)
        == "0xa541d91a11111111111111111111111111111111111111111111111111111111111111112222222222222222222222222222222222222222222222222222222222222222000000000000000000000100c2b78104907f722dabac4c69f826a522b2754de4")
check("isValidSignatureForSigner calldata",
      SafeWebAuthn.isValidSignatureForSignerCalldata(message: challenge, signature: sig!, x: x, y: y)?
        .hasPrefix("0xcb48798b60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d00000000000000000000000000000000000000000000000000000000000000a0") == true)
check("the magic value is recognised in one word",
      SafeWebAuthn.isMagic("0x1626ba7e00000000000000000000000000000000000000000000000000000000")
      && !SafeWebAuthn.isMagic("0x0000000000000000000000000000000000000000000000000000000000000000"))
check("getSigner's answer decodes to a checksummed address",
      SafeWebAuthn.decodeAddress("0x0000000000000000000000005555555555555555555555555555555555555555")
        == "0x5555555555555555555555555555555555555555")
var high = SafeWebAuthn.curveOrder; high[31] -= 1        // n - 1, the highest s
let folded = SafeWebAuthn.lowS(high)
check("a high s folds to n - s", folded == [UInt8](repeating: 0, count: 31) + [1])
check("a low s is untouched", SafeWebAuthn.lowS(SafeWebAuthn.curveHalfOrder) == SafeWebAuthn.curveHalfOrder)

print("the peer's door")
check("the allowlist is the two typed-data methods",
      SafePeerRequest.allowedMethods == ["eth_signTypedData_v4", "eth_signTypedData"])
if case .failure(.methodNotOffered(let m)) = SafePeerRequest.parse(method: "eth_" + "sendTransaction", params: [TO, [:]] as [Any], chainId: 1) {
    check("a send is refused by name", m == "eth_" + "sendTransaction")
} else { check("a send is refused by name", false) }
if case .failure(.methodNotOffered) = SafePeerRequest.parse(method: "personal_" + "sign", params: ["0x68656c6c6f", TO], chainId: 1) {
    check("free text is refused by name", true)
} else { check("free text is refused by name", false) }
switch SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, safeTxTyped], chainId: 1) {
case .success(let parsed):
    check("a SafeTx envelope reads as a SafeTx", { if case .safeTx = parsed.ask { return true }; return false }())
    check("…addressed to the account the app named", parsed.address == TO)
    if case .safeTx(let chainId, let safe, let tx, let requesterHash) = parsed.ask {
        check("…with the ten fields", chainId == 1 && safe == SAFE && tx.nonce == 0 && tx.value == "1000000000000000000")
        check("…and the requester's digest is the one the encoder pins",
              hex(requesterHash) == "0x60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d")
        check("…which the specific encoder reproduces",
              SafeTxEncoder.safeTxHash(chainId: chainId, safe: safe, tx: tx) == requesterHash)
    }
case .failure(let refusal):
    check("a SafeTx envelope reads as a SafeTx (\(refusal))", false)
}
if case .failure(.chainMismatch(let request, let domain)) = SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, safeTxTyped], chainId: 8453) {
    check("a session chain that disagrees with the domain is refused", request == 8453 && domain == 1)
} else { check("a session chain that disagrees with the domain is refused", false) }
let namedDomain = safeTxTyped.replacingOccurrences(of: "\"domain\":{\"chainId\":1,", with: "\"domain\":{\"name\":\"Gnosis Safe\",\"chainId\":1,")
if case .failure(.foreignDomain) = SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, namedDomain], chainId: 1) {
    check("a SafeTx under a NAMED domain (pre-1.3.0, or a costume) is refused", true)
} else { check("a SafeTx under a NAMED domain (pre-1.3.0, or a costume) is refused", false) }
let message = """
{"types":{"EIP712Domain":[{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"SafeMessage":[{"name":"message","type":"bytes"}]},"primaryType":"SafeMessage","domain":{"chainId":1,"verifyingContract":"0x1234567890123456789012345678901234567890"},"message":{"message":"0x0561ebd8eb761945b4f6409691f7985ec0c0292575aa4da3287544f30fa9186f"}}
"""
switch SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, message], chainId: 1) {
case .success(let parsed):
    if case .safeMessage(let chainId, let safe, let inner, let requesterHash) = parsed.ask {
        check("a SafeMessage envelope reads as a statement ask", chainId == 1 && safe == SAFE && hex(inner) == "0x0561ebd8eb761945b4f6409691f7985ec0c0292575aa4da3287544f30fa9186f")
        check("…and the requester's digest is the Safe's own message hash",
              hex(requesterHash) == "0x320b256597f39833cfb3cc7b36e551490567afdfa32d2f99a7e59bf211d49a8a")
    } else { check("a SafeMessage envelope reads as a statement ask", false) }
case .failure(let refusal):
    check("a SafeMessage envelope reads as a statement ask (\(refusal))", false)
}
switch SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, recoveryTyped], chainId: 1) {
case .success(let parsed):
    if case .recovery(let request, let requesterHash) = parsed.ask {
        check("an ExecuteRecovery envelope reads as a recovery ask", request == recovery)
        check("…with the module's own hash", hex(requesterHash) == "0xfcbf27ae9b93d8ce65b4aba98b1d90d6bdb80fecc2196e98c3d553ee11ed3be8")
    } else { check("an ExecuteRecovery envelope reads as a recovery ask", false) }
case .failure(let refusal):
    check("an ExecuteRecovery envelope reads as a recovery ask (\(refusal))", false)
}
if case .failure(.notASafeShape(let primary)) = SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, mail], chainId: 1) {
    check("any other typed data is refused by its primary type", primary == "Mail")
} else { check("any other typed data is refused by its primary type", false) }
let permit = safeTxTyped.replacingOccurrences(of: "\"primaryType\":\"SafeTx\"", with: "\"primaryType\":\"Permit\"")
if case .failure = SafePeerRequest.parse(method: "eth_signTypedData_v4", params: [TO, permit], chainId: 1) {
    check("a Permit wearing a Safe's domain is refused", true)
} else { check("a Permit wearing a Safe's domain is refused", false) }
check("params that are not [address, typedData] are refused",
      { if case .failure(.paramsUnreadable) = SafePeerRequest.parse(method: "eth_signTypedData_v4", params: ["nope"], chainId: 1) { return true }; return false }())

print("")
if failures == 0 {
    print("all assertions passed")
} else {
    print("\(failures) assertion(s) failed")
    exit(1)
}
SWIFT

SOURCES=("$TX" "$KECCAK" "$CLEARSIGN" "$TYPED" "$STATEMENT" "$RECOVERY" "$WEBAUTHN" "$PEERREQ")
echo "safe-signer-selftest: compiling the five §913 encoders WHOLE and unmodified…"
swiftc -Onone -o "$TMP/run" "${SOURCES[@]}" "$TMP/main.swift" \
  || { echo "✗ the shipped encoders do not compile Foundation-only — something reached the Keychain, the curve, the network or SwiftData"; exit 1; }
"$TMP/run" || exit 1

# The fixtures in the driver must be the ones the derivation prints.
for h in be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2 \
         0561ebd8eb761945b4f6409691f7985ec0c0292575aa4da3287544f30fa9186f \
         320b256597f39833cfb3cc7b36e551490567afdfa32d2f99a7e59bf211d49a8a \
         b98c2d8baa4cb422fde55dd8a84916803e384c4bf259d845c6e2d067a169439d \
         c09e68e9c82528fd200c3cc14b21896a685ce3611962ffe42b5811eabedc6fb2 \
         c003a90f91e2f4a8cdf211feb002f77a3a44e8cee1e1312b1dddfdcc08cd7b4b \
         fcbf27ae9b93d8ce65b4aba98b1d90d6bdb80fecc2196e98c3d553ee11ed3be8 \
         1d4b33fa937e50420c4199ed824babe1bcb5222646c3c5b8bfc8315956e0330c \
         a27e23df90f851506774528f4a41fd2beb53e46e6e4d3a8909af195acb4d4a850500000000 \
         YFURkO73VHTKBjzOqRzzJG6S0gvJ7tWAje5tPRAogY0; do
  printf '%s' "$VECOUT" | grep -q "$h" \
    || { echo "✗ fixture $h is pinned in Swift but is NOT what safe-signer-vectors.py derives"; exit 1; }
  grep -q "$h" "$TMP/main.swift" \
    || { echo "✗ fixture $h vanished from the driver"; exit 1; }
done
echo "  ✓ every pinned fixture matches scripts/support/safe-signer-vectors.py's own output"

# --- mutation pass ----------------------------------------------------------
echo ""
echo "mutations (each must be caught):"

# Every anchor must still exist in the shipped source, checked up front
# (safetx-selftest's lesson: under `set -e` a drifted anchor reads as a run
# that simply stopped).
python3 - "$0" "${SOURCES[@]}" <<'ANCHORS'
import re, sys
sh = open(sys.argv[1]).read()
srcs = {p: open(p).read() for p in sys.argv[2:]}
dead = []
for m in re.finditer(r"mutate \"([^\"]+)\" (\S+) \\\s*\n\s*'(.*?)' \\\s*\n\s*'(.*?)'\s*\n", sh, re.S):
    name, which, frm = m.group(1), m.group(2), m.group(3)
    path = next((p for p in srcs if p.endswith("/" + which + ".swift")), None)
    if path is None or frm not in srcs[path]:
        dead.append(name)
if dead:
    print("✗ mutation anchors no longer in the shipped source — these mutations test NOTHING:")
    for d in dead:
        print(f"    {d}")
    sys.exit(1)
ANCHORS
[[ $? -eq 0 ]] || exit 1

mutate() {   # $1 = name, $2 = file stem, $3 = from, $4 = to
  local name="$1" which="$2" frm="$3" to="$4"
  local -a mutated=()
  local src
  for src in "${SOURCES[@]}"; do
    cp "$src" "$TMP/$(basename "$src")"
    mutated+=("$TMP/$(basename "$src")")
  done
  FRM="$frm" TO="$to" python3 - "$TMP/$which.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]]; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "${mutated[@]}" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# EIP-712: dependencies unsorted — the Ether Mail vector is the only witness.
mutate "encodeType stops sorting dependencies" SafeTypedData \
  'let ordered = [primary] + deps.filter { $0 != primary }.sorted()' \
  'let ordered = [primary] + deps.filter { $0 != primary }'
# EIP-712: a dynamic string inlined instead of hashed.
mutate "a string is encoded as its bytes instead of its keccak" SafeTypedData \
  'return Keccak256.hash(Array(s.utf8))' \
  'return Array(s.utf8) + [UInt8](repeating: 0, count: max(0, 32 - s.utf8.count))'
# EIP-712: the width check dropped.
mutate "an integer wider than its type is accepted" SafeTypedData \
  'guard word.prefix(fullBytes).allSatisfy({ $0 == 0 }) else { return nil }' \
  '_ = fullBytes'
# Safe message: the inner hash hashed once instead of twice.
mutate "SafeMessage stops hashing the inner bytes" SafeStatement \
  'let structHash = Keccak256.hash(typeHash + Keccak256.hash(message))' \
  'let structHash = Keccak256.hash(typeHash + message)'
# Safe message: a sign-in for another address accepted.
mutate "a sign-in for another address is named" SafeStatement \
  'guard siwe.address.lowercased() == safe.lowercased() else {' \
  'guard true else {'
# Safe message: a vote from another domain named.
mutate "typed data outside Snapshot's domain is named" SafeStatement \
  'guard typed.domainName == "snapshot" else {' \
  'guard typed.domainName != nil else {'
# Recovery: the nonce dropped from the struct hash.
mutate "the nonce drops out of the recovery hash" SafeRecovery \
  'return Keccak256.hash(executeRecoveryTypeHash + wallet + owners + threshold + nonce)' \
  'return Keccak256.hash(executeRecoveryTypeHash + wallet + owners + threshold)'
# Recovery: the domain loses its version.
mutate "the version drops out of the recovery domain" SafeRecovery \
  '+ Keccak256.hash(Array(r.version.utf8)) + chainId + module)' \
  '+ chainId + module)'
# Recovery: the typed-data door stops checking the module's name.
mutate "the recovery door accepts any domain name" SafeRecovery \
  'typed.domainName == moduleName,' \
  'typed.domainName != nil,'
# WebAuthn: user verification unset.
mutate "the flags byte drops user verification" SafeWebAuthnSignature \
  'SHA256Digest.hash(Array(rpID.utf8)) + [0x05] + [0, 0, 0, 0]' \
  'SHA256Digest.hash(Array(rpID.utf8)) + [0x01] + [0, 0, 0, 0]'
# WebAuthn: the contract-signature envelope says v = 1.
mutate "the contract signature's v byte is not 0" SafeWebAuthnSignature \
  'return owner + offset + [0] + length + data' \
  'return owner + offset + [1] + length + data'
# WebAuthn: the precompile falls out of verifiers.
mutate "verifiers loses the precompile" SafeWebAuthnSignature \
  'word[10] = UInt8((precompile >> 8) & 0xFF)' \
  'word[10] = 0'
# SHA-256: one round constant wrong.
mutate "a SHA-256 round constant changes" SafeWebAuthnSignature \
  '0x428a2f98, 0x71374491,' \
  '0x428a2f99, 0x71374491,'
# Low-s: folding stops.
mutate "a high s is no longer folded" SafeWebAuthnSignature \
  'guard high else { return s }' \
  'return s; guard high else { return s }'
# The peer: the allowlist grows.
mutate "the allowlist grows a third method" SafePeerRequest \
  'static let allowedMethods: Set<String> = ["eth_signTypedData_v4", "eth_signTypedData"]' \
  'static let allowedMethods: Set<String> = ["eth_signTypedData_v4", "eth_signTypedData", "eth_sign"]'
# The peer: the chain check dropped.
mutate "a session chain that disagrees with the domain is accepted" SafePeerRequest \
  'if let chainId, chainId != domainChain {' \
  'if false {'
# The peer: a named domain accepted for a SafeTx.
mutate "a SafeTx under a named domain is accepted" SafePeerRequest \
  'guard typed.domainName == nil, typed.domainVersion == nil else { return .failure(.foreignDomain) }
            guard typed.types["SafeTx"] == safeTxFields' \
  'guard typed.types["SafeTx"] == safeTxFields'
# The peer: any primary type accepted as a SafeTx.
mutate "the primary-type switch loses its default refusal" SafePeerRequest \
  'default:
            return .failure(.notASafeShape(primaryType: typed.primaryType))' \
  'default:
            guard let tx = safeTransaction(typed.message) else { return .failure(.typedDataUnreadable) }
            return .success(.safeTx(chainId: domainChain, safe: contract, tx: tx, requesterHash: requesterHash))'

# --- the refusal guards, mutation-proven -----------------------------------
guard_mutate() {   # $1 = name, $2 = statement|recovery|enclave|key, $3 = from, $4 = to
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$STATEMENT_SIGNER" "$TMP/SafeStatementSigner.swift"
  cp "$RECOVERY_SIGNER" "$TMP/SafeRecoverySigner.swift"
  cp "$ENCLAVE_SIGNER" "$TMP/SafeEnclaveSigner.swift"
  cp "$ENCLAVE_KEY" "$TMP/SafeEnclaveKey.swift"
  local target
  case "$which" in
    statement) target="$TMP/SafeStatementSigner.swift" ;;
    recovery)  target="$TMP/SafeRecoverySigner.swift" ;;
    enclave)   target="$TMP/SafeEnclaveSigner.swift" ;;
    key)       target="$TMP/SafeEnclaveKey.swift" ;;
  esac
  FRM="$frm" TO="$to" python3 - "$target" <<'GMUT'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
GMUT
  if [[ $? -ne 0 ]]; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if guard_check "$TMP/SafeStatementSigner.swift" "$TMP/SafeRecoverySigner.swift" "$TMP/SafeEnclaveSigner.swift" "$TMP/SafeEnclaveKey.swift"; then
    echo "  ✗ $name — guard_check still passed, so nothing was guarding this"; exit 1
  fi
  echo "  ✓ $name"
}

guard_mutate "an unreadable statement is signed" statement \
  'if case .unreadable(let why) = reading.statement { return .failure(.unreadable(why: why)) }' \
  '_ = reading.statement'
guard_mutate "words that do not hash to the ask are signed" statement \
  'guard reading.hash == innerHash else { return .failure(.messageMismatch) }' \
  '_ = innerHash'
guard_mutate "a statement is signed for a 1-of-N Safe" statement \
  'guard threshold >= 2 else { return .failure(.thresholdTooLow(threshold)) }' \
  'guard threshold >= 1 else { return .failure(.thresholdTooLow(threshold)) }'
guard_mutate "the statement signer grows a third write" statement \
  'private static func post(_ ready: Ready, signature: String) async -> Int {' \
  'private static func post(_ ready: Ready, signature: String) async -> Int {
        _ = await IngestSupport.postJSONStatus("https://api.safe.global/tx-service/eth/api/v1/echo/", body: [:])'
guard_mutate "the statement signer reaches a host that is not Safe's" statement \
  '"https://safe-client.safe.global/v1/chains/\(chainId)"' \
  '"https://safe-gateway.example.com/v1/chains/\(chainId)"'
guard_mutate "a contract that is not the module is signed for" recovery \
  'guard SafeRecovery.decodeString(nameHex) == SafeRecovery.moduleName else {' \
  'guard true else {'
guard_mutate "a module the wallet never enabled is signed for" recovery \
  'guard enabled else { return .failure(.moduleNotEnabled) }' \
  '_ = enabled'
guard_mutate "a phone that is not a guardian signs" recovery \
  'guard let signer else { return .failure(.notAGuardian) }' \
  'guard let signer = signer ?? identities.first else { return .failure(.notAGuardian) }'
guard_mutate "a lone guardian signs" recovery \
  'guard guardianThreshold >= 2 else { return .failure(.guardianThresholdTooLow(guardianThreshold)) }' \
  'guard guardianThreshold >= 1 else { return .failure(.guardianThresholdTooLow(guardianThreshold)) }'
guard_mutate "a stale nonce is signed" recovery \
  'guard nonce == request.nonce else { return .failure(.staleNonce(module: nonce)) }' \
  '_ = nonce'
guard_mutate "the recovery signer grows a write" recovery \
  'static func land(context: ModelContext, ready: Ready) {' \
  'static func land(context: ModelContext, ready: Ready) {
        _ = IngestSupport.postJSON("https://api.safe.global/tx-service/eth/api/v1/echo/", body: [:])'
guard_mutate "an assertion leaves without the factory's magic value" enclave \
  'guard SafeWebAuthn.isMagic(answer) else { return .failure(.notAccepted) }' \
  '_ = answer'
guard_mutate "the Enclave key is made without user presence" key \
  '[.privateKeyUsage, .biometryCurrentSet]' \
  '[.privateKeyUsage]'
guard_mutate "the Enclave key hashes its digest again" key \
  'signature = try key.signature(for: SafeEnclaveDigest(Data(digest)))' \
  'signature = try key.signature(for: Data(digest))'
guard_mutate "a second reader of the Enclave blob appears" key \
  'kSecReturnData as String: true,' \
  'kSecReturnData as String: true, kSecReturnPersistentRef as String: true, kSecReturnData as String: true,'

echo ""
echo "✓ safe-signer self-test: fixtures pinned, refusals proven, every mutation caught"
