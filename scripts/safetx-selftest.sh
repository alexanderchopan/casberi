#!/bin/zsh
# Casberi Safe co-signer self-test — the arithmetic behind every signature
# this app will ever produce (prd §425, docs/signer-spec.md §3/§6/§8).
#
#   Casberi/Casberi/Model/SafeTransaction.swift   compiled WHOLE and unmodified
#   Casberi/Casberi/Model/Keccak256.swift         its only dependency
#
# WHY THIS IS THE MOST LOAD-BEARING HARNESS IN THE REPO. Every other check
# here guards a wrong READING; this one guards a wrong SIGNATURE. A wrong
# domain separator, a wrong type hash, a mispadded word or an INLINED `data`
# field all produce a signature that is well-formed, recovers to a real
# address, and is valid over a DIFFERENT transaction than the one the person
# was shown. Nothing in a build, a screen sweep, a probe or a device test can
# see that — the screen is correct, the tap is correct, and the money leaves.
#
# The fixtures are not recalled. They are computed by
# `scripts/support/safetx-vectors.py`, whose own Keccak-256 is checked against
# four published vectors first (empty string, "abc", the ERC-20 `Transfer`
# topic, the `transfer(address,uint256)` selector) so it cannot be quietly
# running NIST SHA3 instead of Keccak. Three of the five exist ONLY to prove
# that `nonce`, `chainId` and `operation` are each really inside the preimage:
# a signer that dropped `nonce` would let a signature replay at a later nonce,
# and one that dropped `chainId` would let a mainnet signature execute on a
# testnet Safe at the same address.
#
# Compiled WHOLE, never extracted — `SafeTransaction.swift` is Foundation-only
# BY DESIGN (that is why the Keychain, the curve and the chain reads live in
# `SignerKey.swift`/`SafeSigner.swift`), so there is nothing to stub and no
# way for this harness to pass against logic the app does not run.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

TX="Casberi/Casberi/Model/SafeTransaction.swift"
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
SIGNER="Casberi/Casberi/Model/SafeSigner.swift"
KEY="Casberi/Casberi/Model/SignerKey.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
CARD="Casberi/Casberi/Screens/SafeQueueCard.swift"
SCREEN="Casberi/Casberi/Screens/SafeScreen.swift"
VECTORS="scripts/support/safetx-vectors.py"
for f in "$TX" "$KECCAK" "$SIGNER" "$KEY" "$REACH" "$CARD" "$VECTORS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- the source of the fixtures ---------------------------------------------
# Run the derivation FIRST, including its own Keccak self-test. If the vectors
# script cannot prove it is computing Keccak, the numbers below are not
# evidence and this harness must not pretend otherwise.
python3 "$VECTORS" >/dev/null \
  || { echo "✗ scripts/support/safetx-vectors.py failed its own self-test — the fixtures are not evidence"; exit 1; }

# …and the fixtures pinned in Swift below must be the ones that script prints,
# or this harness is testing a private copy of the numbers. Every expected
# hash in the driver is grepped out of the script's own output.
VECOUT=$(python3 "$VECTORS")

TMP=$(mktemp -d /tmp/safetx-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions cannot prove about themselves.

# THE NO-OTHER-SIGNING-ENTRY-POINT GUARD (spec §8.4), and the reason this
# harness runs on every pass. The promise is that Casberi signs a SafeTx and
# nothing else — no `personal_sign` of arbitrary text, no raw `eth_sign`, no
# free-form typed data, no `eth_sendTransaction`. That promise is kept by
# these files containing no such path.
#
# Read from a COMMENT-STRIPPED copy: this file documents the forbidden methods
# by NAMING them (`SafeSignature`'s doc explains what `v > 30` means by
# spelling out the `eth_sign` prefix), so a guard grepping raw source fires
# against the prose explaining the rule. The Obsidian/Cursor lesson, sixth
# instance, and it caught this guard on its own first run.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
print("\n".join(re.sub(r"//.*$", "", line) for line in src.splitlines()))
PY
}
CODE=$(strip_comments "$TX")
for forbidden in 'personal_sign' 'eth_sign' 'eth_sendTransaction' 'eth_signTypedData' 'Ethereum Signed Message'; do
  printf '%s' "$CODE" | grep -q "$forbidden" \
    && { echo "✗ SafeTransaction.swift now contains a $forbidden path — Casberi may sign a SafeTx and nothing else (spec §8.4)"; exit 1; }
done
# The positive half: this file must reach nothing at all.
for reach in 'URLSession' 'IngestSupport' 'SecItemAdd' 'import Security' 'import SwiftData' 'import SwiftUI'; do
  printf '%s' "$CODE" | grep -q "$reach" \
    && { echo "✗ SafeTransaction.swift reached $reach — it must stay Foundation-only so this harness can compile it whole"; exit 1; }
done
# The type strings are Safe's, verbatim. A single character here is a
# different hash, and the mutation pass below proves each one is load-bearing
# — but only against the shipped spelling, so pin that spelling too.
grep -q 'EIP712Domain(uint256 chainId,address verifyingContract)' "$TX" \
  || { echo "✗ the Safe >= 1.3.0 domain type string changed"; exit 1; }
grep -q 'SafeTx(address to,uint256 value,bytes data,uint8 operation,' "$TX" \
  || { echo "✗ the SafeTx type string changed"; exit 1; }

# THE SIX REFUSALS (spec §8), as greps, because `SafeSigner.swift` reaches
# SwiftData and the network and so cannot be compiled here. Each is
# mutation-proven below: the mutation is applied to a copy and the guard must
# then FAIL, or the guard is decorative.
#
# `guard_check` is the shared body so the live run and the mutation run cannot
# drift — a guard that tests one file and a mutation that tests another is the
# "right result for the wrong reason" this repo keeps paying for.
guard_check() {   # $1 = SafeSigner.swift path, $2 = SignerKey.swift path
  # COMMENT-STRIPPED copies. Both files DOCUMENT these rules by naming the
  # things they must not do — `SignerKey` explains its access control by
  # spelling out "`.biometryCurrentSet`, not `.biometryAny`" — so a guard
  # grepping raw source is satisfied by the prose explaining the rule. The
  # Obsidian/Cursor lesson, and it caught the biometry mutation here: widening
  # the real flag left the guard green because the COMMENT still said the
  # right word.
  local sg="$TMP/guard-signer.swift" ky="$TMP/guard-key.swift"
  strip_comments "$1" > "$sg"
  strip_comments "$2" > "$ky"
  # (1) A 1-of-N Safe naming this phone is a custodial wallet wearing a
  # multisig's clothes. Anchored so `threshold >= 2 || debug` cannot pass.
  grep -qE 'guard threshold >= 2 else \{ return \.failure\(\.thresholdTooLow\(threshold\)\) \}' "$sg" || return 1
  # …and read from the CHAIN, not from a cached SafeBridge config, because the
  # cache is exactly what an attacker holding the desktop key would beat.
  # ANCHORED TO `prepare`'s OWN CALL SITE. Both selectors are now read in two
  # places — `prepare` before a signature, and `standing` for the N-of-N
  # warning — so a bare name grep passes while the one that gates signing is
  # gone. That mutation survived this guard's first run after `standing`
  # landed; the same shape `cursor-selftest.sh` records ("a guard must prove
  # the condition is the WHOLE condition, not that the words appear").
  grep -q 'async let thresholdRead = call(rail, to: safeAddress, data: SafeCall.getThresholdSelector)' "$sg" || return 1
  # (2) Ownership, also from the chain.
  grep -qE 'guard owners\.contains\(me\.lowercased\(\)\) else \{ return \.failure\(\.notAnOwner\) \}' "$sg" || return 1
  grep -q 'async let ownersRead = call(rail, to: safeAddress, data: SafeCall.getOwnersSelector)' "$sg" || return 1
  # (3) THE RAIL. Both halves: a mismatch refuses, and so does a failure to
  # read — not knowing is not knowing it is fine.
  grep -q 'SafeCall.getTransactionHash(tx)' "$sg" || return 1
  grep -qE 'guard chain\.lowercased\(\) == local\.lowercased\(\) else \{' "$sg" || return 1
  grep -qE 'else \{ return \.failure\(\.chainUnreadable\) \}' "$sg" || return 1
  # (4) One signing entry point and one only, and it takes a HASH — a function
  # here that took a transaction would be a second place the refusals above
  # could be forgotten.
  # COUNT OCCURRENCES, not matching LINES. `grep -c` counts lines, so a second
  # call appended to the same line passed cleanly — which is exactly how the
  # export-path mutation below survived this guard's first run.
  [[ $(grep -o 'static func sign(' "$ky" | wc -l | tr -d ' ') -eq 1 ]] || return 1
  grep -q 'static func sign(hash: \[UInt8\], reason: String)' "$ky" || return 1
  # (5) NO EXPORT PATH. `SecItemCopyMatching` appears exactly once in the key
  # file, inside that one function; a second reader is an export however it is
  # spelled.
  # …counted on `kSecReturnData`, not on `SecItemCopyMatching`. That is the
  # line that decrypts the scalar; `presence()` queries ATTRIBUTES ONLY and
  # never sees a byte of it, which is exactly why it can run on every screen
  # appearance without a Face ID prompt. Counting the query would have made
  # the honest second reader indistinguishable from an export — and it did,
  # on this guard's first run after `presence()` landed.
  [[ $(grep -o 'kSecReturnData as String: true' "$ky" | wc -l | tr -d ' ') -eq 1 ]] || return 1
  [[ $(grep -o 'SecItemCopyMatching' "$ky" | wc -l | tr -d ' ') -le 2 ]] || return 1
  # (6) The key is gated at the only moment that matters.
  grep -q '\.biometryCurrentSet' "$ky" || return 1
  grep -q 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' "$ky" || return 1
  # …and the signature is checked back to this phone's own address before the
  # bytes are handed out.
  grep -q 'recoveredAddress.lowercased() == expected.lowercased()' "$ky" || return 1
  # (7) THE N-of-N RULE (prd §426). An N-of-N Safe cannot be repaired once an
  # owner is lost — owner management is itself a threshold-meeting
  # transaction — so it must be STATED. And it must never become a refusal:
  # in a 2-of-2 that names this phone, declining to sign IS the lock. So the
  # positive half is that the fact exists and is carried to the surface…
  grep -q 'var hasNoSpareOwner: Bool { ownerCount > 0 && ownerCount == threshold }' "$sg" || return 1
  grep -q 'let standing: Standing' "$sg" || return 1
  # …and the negative half is that no refusal is ever built out of it. This is
  # the guard that keeps the warning from quietly becoming the very lock the
  # ruling forbids.
  grep -qE 'return \.failure\(\.[A-Za-z]*[Ss]pare' "$sg" && return 1
  grep -q 'hasNoSpareOwner.*return .failure' "$sg" && return 1
  grep -qE 'owners\.count == threshold.*return \.failure' "$sg" && return 1
  # (8) A destroyed key is named as destroyed, not reported as a locked one —
  # `.biometryCurrentSet` erases the item, and the cached address survives it.
  grep -q 'case destroyed' "$ky" || return 1
  # …by an attribute-only query, or the check that tells you your key is gone
  # would itself cost a Face ID on every screen appearance.
  grep -qE 'kSecReturnAttributes as String: true' "$ky" || return 1
  grep -q 'if status == errSecItemNotFound { return .destroyed }' "$ky" || return 1
  # …and an unreadable keychain is never reported as destroyed: that sentence
  # sends somebody to get an on-chain transaction done.
  grep -qE 'return \.present$' "$ky" || return 1
  return 0
}
guard_check "$SIGNER" "$KEY" \
  || { echo "✗ a Safe co-signer refusal is missing or weakened — run guard_check in scripts/safetx-selftest.sh"; exit 1; }

# THE CONDUCT GUARD (spec §7). This is Casberi's FIRST outbound write in its
# history, and the promise is that it is one POST of one signature to one
# endpoint. Any other write verb, or any other host, appearing in this file
# makes that false — so the build fails rather than a comment going stale.
SIGNER_CODE=$(strip_comments "$SIGNER")
for verb in 'postJSONArray' 'deleteJSON' '"PUT"' '"PATCH"' '"DELETE"' 'httpMethod'; do
  printf '%s' "$SIGNER_CODE" | grep -qF -- "$verb" \
    && { echo "✗ SafeSigner.swift gained a write verb ($verb) — the one-POST promise is now false"; exit 1; }
done
[[ $(printf '%s' "$SIGNER_CODE" | grep -o 'postJSONStatus\|postJSON(' | wc -l | tr -d ' ') -eq 1 ]] \
  || { echo "✗ SafeSigner.swift makes more than one POST — it may make exactly one"; exit 1; }
printf '%s' "$SIGNER_CODE" | grep -q 'multisig-transactions/\\(safeTxHash)/confirmations/' \
  || { echo "✗ the one POST no longer goes to Safe's confirmations endpoint"; exit 1; }
# Every host this file names must be Safe's own.
for host in $(printf '%s' "$SIGNER_CODE" | grep -oE 'https://[a-z0-9.-]+' | sort -u); do
  [[ "$host" == "https://api.safe.global" ]] \
    || { echo "✗ SafeSigner.swift reaches $host — it may reach api.safe.global and nothing else"; exit 1; }
done
# EVERY RAIL MUST HAVE A READER (2026-09-07). The entire safety argument for
# signing on a chain is that `getTransactionHash` can be read back from the
# Safe there — "a chain where the cross-check cannot run is a chain this app
# must not sign on". A rail added with no reader case would compile fine and
# would sign against a hash only this app has ever computed, so the count of
# rails and the count of reader arms are pinned to each other.
RAIL_COUNT=$(printf '%s' "$SIGNER_CODE" | grep -c 'Rail(seg:')
[[ "$RAIL_COUNT" -eq 6 ]] \
  || { echo "✗ SafeSigner's rail list changed ($RAIL_COUNT rails) — every rail must have a Reader that can run the getTransactionHash cross-check, and adding one is a decision, not a line"; exit 1; }
printf '%s' "$SIGNER_CODE" | grep -q 'case .gnosisChain:' \
  || { echo "✗ the Gnosis rail lost its reader — it would sign against a hash only this app computed"; exit 1; }
# …and it borrows the hosts from the bridge that already owns and discloses
# them, rather than naming one here (which the host guard above forbids, and
# which would add an undisclosed reach).
printf '%s' "$SIGNER_CODE" | grep -q 'GnosisPayBridge.read(method: "eth_call"' \
  || { echo "✗ the Gnosis cross-check no longer goes through GnosisPayBridge's disclosed hosts"; exit 1; }
grep -q 'own hash of a transaction before this phone will sign it' "$REACH" \
  || { echo "✗ NetworkReach no longer says the Gnosis hosts are reached for a signature cross-check — the privacy screen understates what this app does"; exit 1; }

# …and the write must be disclosed on the privacy screen, in words.
grep -qi 'signature is sent to Safe' "$REACH" \
  || { echo "✗ NetworkReach no longer says a signature is SENT — the privacy screen understates what this app does"; exit 1; }

# The two facts must reach a SCREEN, not just a struct. A perfect
# `hasNoSpareOwner` nothing renders is the §311 failure — the reading exists,
# the room stays quiet, and from outside that is indistinguishable from being
# fine.
CARD_CODE=$(strip_comments "$CARD")
printf '%s' "$CARD_CODE" | grep -q 'ready.standing.hasNoSpareOwner' \
  || { echo "✗ the sign block no longer states an N-of-N Safe — the one warning that cannot be recovered from"; exit 1; }
printf '%s' "$CARD_CODE" | grep -q 'SignerKey.presence() == .destroyed' \
  || { echo "✗ the sign block no longer detects a destroyed key — it would show a Sign button that can never work"; exit 1; }
grep -q 'needingASpareOwner' Casberi/Casberi/Screens/SafeScreen.swift \
  || { echo "✗ the Safe setup screen no longer warns about an N-of-N Safe"; exit 1; }
# …and never from a read that did not answer.
grep -q 'report.reachable' Casberi/Casberi/Screens/SafeScreen.swift \
  || { echo "✗ the N-of-N warning no longer gates on the read having answered — silence would read as an all-clear"; exit 1; }

# THE CATALOG COPY, which is where this feature's promise is READ (§303's
# tripwire, and it had already gone stale once). The Safe offer's summary said
# "signing always happens in your own Safe app" for the whole first day this
# feature existed — the setup-copy audit never saw it, because that audit
# governs a connect screen's intro and this is the product page. So: the offer
# may not claim signing happens elsewhere, and must say that it happens here.
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
SAFE_OFFER=$(python3 - "$CATALOG" <<'OFFER'
import re, sys
src = open(sys.argv[1]).read()
i = src.index('Offer(name: "Safe",')
j = src.index('needsSetup:', i)
print(re.sub(r"^\s*//.*$", "", src[i:j], flags=re.M))
OFFER
)
printf '%s' "$SAFE_OFFER" | grep -qi 'signing always happens in your own Safe app' \
  && { echo "✗ the Safe offer still says signing happens elsewhere — prd §425 made that false"; exit 1; }
printf '%s' "$SAFE_OFFER" | grep -qi 'sign' \
  || { echo "✗ the Safe offer never mentions signing — the co-signer is unfindable for anyone without a Safe yet"; exit 1; }
# …and the two honest limits that make the claim safe to print at all.
#
# READ OFF THE SCREEN, NOT THE OFFER (prd §641b). Until §641 these lived in the
# offer's `features` list, which the product page drew; that page and those
# lists are deleted, so the catalog literal is now name/tagline/group and can
# never carry a limit again. The RULING is unchanged — the limit travels with
# the pitch — so this reads the screen the tagline's claim leads to. Checking
# the offer here would be checking a file that structurally cannot pass.
for claim in 'never execute' 'Face ID'; do
  grep -qi "$claim" "$SCREEN" \
    || { echo "✗ SafeScreen claims signing without saying '$claim' — the limit has to travel with the pitch"; exit 1; }
done

# The key file must reach nothing at all: no network, no model, no view.
KEY_CODE=$(strip_comments "$KEY")
for reach in 'URLSession' 'IngestSupport' 'import SwiftData' 'import SwiftUI' 'UserDefaults.standard.set(true'; do
  printf '%s' "$KEY_CODE" | grep -qF -- "$reach" \
    && { echo "✗ SignerKey.swift reached $reach — the key file holds a key and nothing else"; exit 1; }
done


# --- extract SafeSigner's three pure parsers --------------------------------
# `SafeSigner.swift` reaches SwiftData and the network, so it cannot be
# compiled whole the way `SafeTransaction.swift` is. Its three field readers
# ARE pure, and they are exactly where the transaction service's two
# serializer versions get reconciled, so they are extracted BY NAME from the
# shipped source — never copied — and a rename fails the compile loudly
# instead of asserting nothing.
python3 - "$SIGNER" "$TMP/signer.swift" <<'EXTRACT'
import sys
src_path, out = sys.argv[1:3]
src = open(src_path).read()

def grab(signature):
    i = src.find(signature)
    if i < 0:
        sys.exit(f"\u2717 extraction failed: {signature!r} not found in {src_path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1]

open(out, "w").write("\n".join([
    "import Foundation\n",
    "enum SafeSigner {",
    grab("struct Standing: Equatable"),
    grab("struct Ready: Equatable"),
    grab("static func amountField"),
    grab("static func addressField"),
    grab("static func transaction(from row"),
    "}\n",
]))
EXTRACT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func hex(_ b: [UInt8]) -> String { "0x" + Keccak256.hexString(b) }

let SAFE = "0x1234567890123456789012345678901234567890"
let TO   = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
let USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
let ONE_ETH = "1000000000000000000"
// transfer(0xabcd…abcd, 1_000_000) — one USDC at six decimals.
let TRANSFER_CALLDATA =
    "0xa9059cbb"
    + "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
    + "00000000000000000000000000000000000000000000000000000000000f4240"

print("the type hashes — computed from Safe's own type strings, never pasted")
check("DOMAIN_SEPARATOR_TYPEHASH",
      hex(SafeTxEncoder.domainTypeHash)
        == "0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218")
check("SAFE_TX_TYPEHASH",
      hex(SafeTxEncoder.safeTxTypeHash)
        == "0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8")
// Recognised in order to REFUSE. A Safe < 1.3.0 signs against this domain,
// and signing a modern preimage for one produces a valid signature over
// nothing the contract will accept.
check("the LEGACY (pre-1.3.0) domain typehash is a DIFFERENT number",
      hex(SafeTxEncoder.legacyDomainTypeHash)
        == "0x035aff83d86937d35b32e04f0ddc6ff469290eef2f1b692d8a815c89404d4749")
check("…and the modern domain is not the legacy one",
      SafeTxEncoder.domainTypeHash != SafeTxEncoder.legacyDomainTypeHash)

print("the five pinned safeTxHash fixtures")
func hash(_ chainId: Int, _ tx: SafeTransaction) -> String {
    guard let h = SafeTxEncoder.safeTxHash(chainId: chainId, safe: SAFE, tx: tx) else { return "nil" }
    return hex(h)
}
let plainETH = SafeTransaction(to: TO, value: ONE_ETH, data: "", operation: 0, nonce: 0)
check("1 ETH → 0xabcd…abcd, mainnet, nonce 0",
      hash(1, plainETH) == "0x60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d")
let nonceOne = SafeTransaction(to: TO, value: ONE_ETH, data: "", operation: 0, nonce: 1)
check("same, nonce 1 — the nonce is really inside the preimage",
      hash(1, nonceOne) == "0x7a9bddd1a58aa59b34bf69d88f7210def0dd22cd4cc7822040d8bff3d3e2bd8d")
check("…and nonce 0 and nonce 1 differ (or the fixture above proves nothing)",
      hash(1, plainETH) != hash(1, nonceOne))
check("same, chainId 8453 — the chain is really inside the preimage",
      hash(8453, plainETH) == "0x7828bf9e6c5d5d73fddb54b51222c9bee3bc4031a0e76c82551b8a3c02e11739")
check("…and mainnet and Base differ",
      hash(1, plainETH) != hash(8453, plainETH))
let erc20 = SafeTransaction(to: USDC, value: "0", data: TRANSFER_CALLDATA, operation: 0, nonce: 7)
check("USDC transfer calldata, operation 0, nonce 7",
      hash(1, erc20) == "0x7be693d2f7ba83533e3052848cfd6e799dab186e964fcab31e3e4ae19cefcc8d")
let delegate = SafeTransaction(to: USDC, value: "0", data: TRANSFER_CALLDATA, operation: 1, nonce: 7)
// THE SIXTH FIXTURE, and the one the mutation pass demanded. The five above
// leave safeTxGas/baseGas/gasPrice/gasToken/refundReceiver all at zero, which
// makes the last five words of the struct hash indistinguishable — swapping
// safeTxGas and baseGas reproduced every one of them, and that mutation
// SURVIVED this harness's first run. A fixture only tests the rule it names
// if it fails that rule and passes every other one.
let distinct = SafeTransaction(
    to: TO, value: ONE_ETH, data: "0xdeadbeef", operation: 0,
    safeTxGas: "100000", baseGas: "21000", gasPrice: "3",
    gasToken: USDC, refundReceiver: "0x1111111111111111111111111111111111111111",
    nonce: 42)
check("every field distinct — the gas words and the two addresses cannot be transposed",
      hash(1, distinct) == "0xd04701f3b47ce88fa373fe8f455450d33b3a3616c05d6a8e9af232ecfd98687f")
check("identical but DELEGATECALL — the operation is really inside the preimage",
      hash(1, delegate) == "0xf563d44af5a41ac0f458c21c2d203ff7da09149720227ac15aff2b345df24d38")
check("…and CALL and DELEGATECALL differ",
      hash(1, erc20) != hash(1, delegate))

print("abi.encode's static head")
// `data` is a DYNAMIC bytes: its keccak goes in the word. The empty string
// hashes to Keccak's own empty-input digest, which is what makes a plain send
// differ from a call with one zero byte of data.
check("empty calldata hashes to keccak(\"\")",
      hex(Keccak256.hash([]))
        == "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
check("a plain send and a one-zero-byte call are DIFFERENT transactions",
      hash(1, plainETH)
        != hash(1, SafeTransaction(to: TO, value: ONE_ETH, data: "0x00", operation: 0, nonce: 0)))
check("an address word is left-padded to 32 bytes",
      SafeABI.word(address: "0x" + String(repeating: "ff", count: 20))
        == [UInt8](repeating: 0, count: 12) + [UInt8](repeating: 0xff, count: 20))
check("the 0x prefix is optional and the case is irrelevant",
      SafeABI.word(address: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        == SafeABI.word(address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"))
check("an ENS name is not an address", SafeABI.word(address: "alice.eth") == nil)
check("39 hex digits is not an address",
      SafeABI.word(address: "0x" + String(repeating: "a", count: 39)) == nil)

print("uint256 — the wire sends decimal, and Double cannot hold it")
check("1 ETH in wei", hex(SafeABI.word(uint256: ONE_ETH)!)
        == "0x0000000000000000000000000000000000000000000000000de0b6b3a7640000")
// 2^64 − the exact point a UInt64 implementation starts lying, and well
// inside the range of an ordinary balance.
check("2^64 encodes exactly", hex(SafeABI.word(uint256: "18446744073709551616")!)
        == "0x0000000000000000000000000000000000000000000000010000000000000000")
// max uint256 — the ERC-20 unlimited approval, i.e. the single most
// consequential number this encoder will ever see.
check("max uint256 encodes exactly",
      SafeABI.word(uint256: "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        == [UInt8](repeating: 0xff, count: 32))
check("one past max uint256 REFUSES rather than wrapping",
      SafeABI.word(uint256: "115792089237316195423570985008687907853269984665640564039457584007913129639936") == nil)
check("hex is accepted too (the eth_call cross-check answers in hex)",
      SafeABI.word(uint256: "0xde0b6b3a7640000") == SafeABI.word(uint256: ONE_ETH))
check("an empty value is not zero", SafeABI.word(uint256: "") == nil)
check("a negative is refused", SafeABI.word(uint256: "-1") == nil)
check("a decimal point is refused", SafeABI.word(uint256: "1.5") == nil)
check("a stray letter in a decimal is refused", SafeABI.word(uint256: "10a") == nil)
check("a negative Int is refused", SafeABI.word(uint: -1) == nil)
check("odd-length calldata is refused, never half-read", SafeABI.hexBytes("0xabc") == nil)
check("a non-hex digit in calldata is refused", SafeABI.hexBytes("0xzz") == nil)
check("an unparseable field makes the whole hash nil, never a guess",
      SafeTxEncoder.safeTxHash(chainId: 1, safe: SAFE,
        tx: SafeTransaction(to: "alice.eth", value: "0", data: "", operation: 0, nonce: 0)) == nil)
check("an unparseable Safe address makes the hash nil",
      SafeTxEncoder.safeTxHash(chainId: 1, safe: "not-an-address", tx: plainETH) == nil)

print("the 65 bytes — v is a DISCRIMINATOR, not a parity bit")
let lowS = [UInt8](repeating: 0x11, count: 32)
let r    = [UInt8](repeating: 0x22, count: 32)
check("recid 0 → v = 27",
      SafeSignature.serialize(compact: r + lowS, recoveryId: 0)?.last == 27)
check("recid 1 → v = 28",
      SafeSignature.serialize(compact: r + lowS, recoveryId: 1)?.last == 28)
check("the body is r ‖ s, untouched",
      Array(SafeSignature.serialize(compact: r + lowS, recoveryId: 0)!.prefix(64)) == r + lowS)
check("65 bytes exactly",
      SafeSignature.serialize(compact: r + lowS, recoveryId: 0)?.count == 65)
// 2 and 3 exist on the curve and never occur in practice; Ethereum's v has
// nowhere to put them, so emitting 29/30 is a signature no Safe can read.
check("recid 2 is refused", SafeSignature.serialize(compact: r + lowS, recoveryId: 2) == nil)
check("recid 3 is refused", SafeSignature.serialize(compact: r + lowS, recoveryId: 3) == nil)
check("a negative recid is refused", SafeSignature.serialize(compact: r + lowS, recoveryId: -1) == nil)
check("a short compact form is refused",
      SafeSignature.serialize(compact: [UInt8](repeating: 0, count: 63), recoveryId: 0) == nil)
check("a long compact form is refused",
      SafeSignature.serialize(compact: [UInt8](repeating: 0, count: 65), recoveryId: 0) == nil)

print("low-s — the same approval must not exist twice")
check("s = n/2 exactly is LOW (the boundary is inclusive)",
      SafeSignature.isLowS(SafeSignature.halfOrder))
var justOver = SafeSignature.halfOrder; justOver[31] += 1
check("s = n/2 + 1 is HIGH", !SafeSignature.isLowS(justOver))
var justUnder = SafeSignature.halfOrder; justUnder[31] -= 1
check("s = n/2 − 1 is LOW", SafeSignature.isLowS(justUnder))
// The comparison must be big-endian across all 32 bytes. A byte-count or
// last-byte-only test passes the boundary cases above and fails this one.
check("a high s differing only in its FIRST byte is caught",
      !SafeSignature.isLowS([0x80] + [UInt8](repeating: 0, count: 31)))
check("s = 0 is low", SafeSignature.isLowS([UInt8](repeating: 0, count: 32)))
check("s = max is high", !SafeSignature.isLowS([UInt8](repeating: 0xff, count: 32)))
check("a high s is REFUSED serialization, not silently emitted",
      SafeSignature.serialize(compact: r + [UInt8](repeating: 0xff, count: 32), recoveryId: 0) == nil)
check("the half order is 32 bytes", SafeSignature.halfOrder.count == 32)
check("a wrong-length s is not low", !SafeSignature.isLowS([0x00]))

print("calldata — read from the bytes, and refused when it does not read")
check("no calldata is a plain send",
      SafeCalldata.read(data: "", to: TO, value: ONE_ETH, safe: SAFE) == .send)
check("0x is the same as empty",
      SafeCalldata.read(data: "0x", to: TO, value: ONE_ETH, safe: SAFE) == .send)
// Safe's own reject shape: zero value, no data, addressed to the Safe itself.
check("zero to itself with no data is a REJECTION, not a send",
      SafeCalldata.read(data: "0x", to: SAFE, value: "0", safe: SAFE) == .rejection)
check("…and the case of the address does not decide it",
      SafeCalldata.read(data: "0x", to: SAFE.uppercased(), value: "0", safe: SAFE) == .rejection)
check("a NON-zero value to itself is a real send, not a rejection",
      SafeCalldata.read(data: "0x", to: SAFE, value: "1", safe: SAFE) == .send)
check("an ERC-20 transfer reads its recipient and amount",
      SafeCalldata.read(data: TRANSFER_CALLDATA, to: USDC, value: "0", safe: SAFE)
        == .erc20Transfer(recipient: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD", amount: "1000000"))
let approveMax = "0x095ea7b3"
    + "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
    + String(repeating: "f", count: 64)
check("an unlimited approval reads its full uint256, not a rounded Double",
      SafeCalldata.read(data: approveMax, to: USDC, value: "0", safe: SAFE)
        == .erc20Approve(spender: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD",
                         amount: "115792089237316195423570985008687907853269984665640564039457584007913129639935"))
// The Safe-administration calls, which are the ones a co-signer most needs to
// read correctly: they change WHO can spend.
let addOwner = "0x0d582f13"
    + "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
    + "0000000000000000000000000000000000000000000000000000000000000002"
check("addOwnerWithThreshold reads the owner and the new threshold",
      SafeCalldata.read(data: addOwner, to: SAFE, value: "0", safe: SAFE)
        == .addOwner(owner: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD", threshold: "2"))
// removeOwner(prevOwner, owner, threshold) — the owner being removed is the
// SECOND argument. Reading the first names a linked-list cursor as the person
// losing their key.
let removeOwner = "0xf8dc5dd9"
    + "0000000000000000000000001111111111111111111111111111111111111111"
    + "0000000000000000000000002222222222222222222222222222222222222222"
    + "0000000000000000000000000000000000000000000000000000000000000001"
check("removeOwner names the SECOND argument, not the list cursor",
      SafeCalldata.read(data: removeOwner, to: SAFE, value: "0", safe: SAFE)
        == .removeOwner(owner: EIP55.checksum("0x2222222222222222222222222222222222222222")))
let changeThreshold = "0x694e80c3"
    + "0000000000000000000000000000000000000000000000000000000000000001"
check("changeThreshold reads the new threshold — the number that can void the whole promise",
      SafeCalldata.read(data: changeThreshold, to: SAFE, value: "0", safe: SAFE)
        == .changeThreshold(threshold: "1"))
let enableModule = "0x610b5925"
    + "000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
check("enableModule is named — a module moves funds outside the threshold entirely",
      SafeCalldata.read(data: enableModule, to: SAFE, value: "0", safe: SAFE)
        == .enableModule(module: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD"))
check("a multiSend whose payload is empty is a batch of nothing, not a lie",
      SafeCalldata.read(data: "0x8d80ff0a" + String(repeating: "0", count: 64),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
check("an unknown selector is UNDECODED and carries its four bytes",
      SafeCalldata.read(data: "0xdeadbeef" + String(repeating: "0", count: 64),
                        to: USDC, value: "0", safe: SAFE) == .undecoded(selector: "0xdeadbeef"))
// A KNOWN selector with truncated arguments must not be summarised as a
// transfer of an amount we invented. This is the refusal that matters most.
check("a truncated transfer is UNDECODED, never a transfer of a guessed amount",
      SafeCalldata.read(data: "0xa9059cbb" + String(repeating: "0", count: 32),
                        to: USDC, value: "0", safe: SAFE) == .undecoded(selector: "0xa9059cbb"))
// A non-zero left pad means the word is not an address at all.
check("a dirty address word is UNDECODED, not a truncated address",
      SafeCalldata.read(data: "0xa9059cbb"
                            + "0000000000000000000000ffabcdefabcdefabcdefabcdefabcdefabcdefabcd"
                            + "00000000000000000000000000000000000000000000000000000000000f4240",
                        to: USDC, value: "0", safe: SAFE) == .undecoded(selector: "0xa9059cbb"))
check("fewer than four bytes of data is undecoded, not a crash",
      SafeCalldata.read(data: "0xa9", to: USDC, value: "0", safe: SAFE)
        == .undecoded(selector: "0xa9"))
check(".undecoded is the only reading the surface may not state as fact",
      SafeCalldata.undecoded(selector: "0xdeadbeef").isDecoded == false
        && SafeCalldata.send.isDecoded == true
        && SafeCalldata.batch([]).isDecoded == true)

// --- THE BATCH WALK (2026-09-07) -------------------------------------------
// §238 measured 96 of a real Safe's last 100 transactions as `multiSend`, so
// this is the shape a co-signer actually meets. Until this pass the sign
// block answered every one of them with "Casberi won't summarise a batch",
// which is honest and is a refusal to do the job on almost every real case.
//
// The refusal DOCTRINE is what these checks pin: a payload that does not walk
// exactly must return `[]` and never the entries it thinks it got, because a
// partial list is the fluent-wrong-summary in its most dangerous form — every
// line on screen true, and the total false.
print("the multiSend walk — itemised, or refused whole")

func packedEntry(op: Int, to: String, value: Int, data: String) -> String {
    let d = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
    return String(format: "%02x", op) + String(to.dropFirst(2))
        + String(format: "%064x", value) + String(format: "%064x", d.count / 2) + d
}
func multiSend(_ entries: [String]) -> String {
    let packed = entries.joined()
    let pad = String(repeating: "0", count: (64 - packed.count % 64) % 64)
    return "0x8d80ff0a" + String(format: "%064x", 32)
        + String(format: "%064x", packed.count / 2) + packed + pad
}
let ONE_TRANSFER = packedEntry(op: 0, to: USDC, value: 0, data: TRANSFER_CALLDATA)

let twoTransfers = SafeCalldata.read(data: multiSend([ONE_TRANSFER, ONE_TRANSFER]),
                                     to: SAFE, value: "0", safe: SAFE)
check("two packed transfers walk into two calls",
      twoTransfers.batchCalls.count == 2)
check("…and each inner call is read by the SAME decoder a lone one gets",
      twoTransfers.batchCalls.allSatisfy {
          $0.reading == .erc20Transfer(recipient: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD",
                                       amount: "1000000")
      })
check("…and a batch every call of which read is fully readable",
      twoTransfers.isFullyReadable)
check("…and the destination comes off the PACKED entry, not the outer `to`",
      twoTransfers.batchCalls.first?.to == EIP55.checksum(USDC))
// A NON-ZERO VALUE, because every other entry here carries zero and a zero
// reads the same however far off the word boundary you are. The value word
// starts at byte 21 of the entry — one byte early and it begins on the last
// byte of the address, which is a real number and a wrong one. This assertion
// is what makes the "value word read one byte over" mutation fail; without it
// the mutation SURVIVED, because nothing here had a value to get wrong.
let withValue = SafeCalldata.read(
    data: multiSend([packedEntry(op: 0, to: TO, value: 1, data: ""),
                     packedEntry(op: 0, to: USDC, value: 0, data: TRANSFER_CALLDATA)]),
    to: SAFE, value: "0", safe: SAFE)
check("a native-coin value inside a batch reads EXACTLY, off byte 21",
      withValue.batchCalls.first?.value == "1"
        && withValue.batchCalls.first?.reading == .send)
check("…and the entry beside it is unaffected",
      withValue.batchCalls.last?.value == "0"
        && withValue.batchCalls.last?.reading
            == .erc20Transfer(recipient: "0xABcdEFABcdEFabcdEfAbCdefabcdeFABcDEFabCD",
                              amount: "1000000"))

// An inner DELEGATECALL runs somebody else's code in the SAFE's own storage,
// so it can rewrite the owner list whatever the rest of the batch claims. It
// is the sharpest fact this decoder can surface and it must survive the walk.
let delegated = SafeCalldata.read(
    data: multiSend([packedEntry(op: 1, to: USDC, value: 0, data: TRANSFER_CALLDATA)]),
    to: SAFE, value: "0", safe: SAFE)
check("an inner DELEGATECALL is carried, not flattened to a call",
      delegated.batchCalls.first?.isDelegateCall == true)
check("…and an ordinary inner call is not marked as one",
      twoTransfers.batchCalls.first?.isDelegateCall == false)
check("an operation that is neither CALL nor DELEGATECALL refuses the batch",
      SafeCalldata.read(data: multiSend([packedEntry(op: 2, to: USDC, value: 0,
                                                     data: TRANSFER_CALLDATA)]),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))

// THE PARTIAL CASE, which is the one the surface has to get right: nameable,
// listable, and NOT complete.
let mixed = SafeCalldata.read(
    data: multiSend([ONE_TRANSFER,
                     packedEntry(op: 0, to: USDC, value: 0,
                                 data: "0xdeadbeef" + String(repeating: "0", count: 64))]),
    to: SAFE, value: "0", safe: SAFE)
check("a batch with one unreadable call still walks and still lists",
      mixed.batchCalls.count == 2)
check("…and the unreadable one arrives as .undecoded, exactly as it would alone",
      mixed.batchCalls.last?.reading == .undecoded(selector: "0xdeadbeef"))
check("…and the batch is nameable but NOT fully readable",
      mixed.isDecoded && !mixed.isFullyReadable)

// EVERY structural failure returns `[]`. A list of the entries the walk got
// before losing the thread is precisely the summary this decoder refuses.
let goodPacked = ONE_TRANSFER + ONE_TRANSFER
func rawMultiSend(lengthOverride: Int? = nil, offsetOverride: Int? = nil,
                  packed: String = goodPacked) -> String {
    let pad = String(repeating: "0", count: (64 - packed.count % 64) % 64)
    return "0x8d80ff0a" + String(format: "%064x", offsetOverride ?? 32)
        + String(format: "%064x", lengthOverride ?? packed.count / 2) + packed + pad
}
check("a length running past the buffer refuses the WHOLE batch",
      SafeCalldata.read(data: rawMultiSend(lengthOverride: goodPacked.count / 2 + 64),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
// TWO GOOD ENTRIES then a stray byte, so a walker returning what it already
// has would return two real calls — the failure this must catch is a batch
// that renders two true lines and is not the transaction being signed.
check("a truncated final entry refuses the whole batch, never the first N",
      SafeCalldata.read(data: rawMultiSend(packed: goodPacked + "00"),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
check("an offset pointing past the arguments refuses",
      SafeCalldata.read(data: rawMultiSend(offsetOverride: 4096),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
// A CRAFTED OFFSET MUST NOT TRAP. Swift's `+` is checked, so the first cut's
// `args.count >= offset + 32` CRASHED THE PROCESS on an offset near Int.max —
// and these bytes come off a proposal in Safe's transaction service, which any
// co-signer can write, so it was a way to kill the app from outside. Every
// bound is a subtraction now. Found by testing the walker against Int.max, not
// by reading it.
let INT_MAX_WORD = String(repeating: "0", count: 48) + "7fffffffffffffff"
check("an offset near Int.max refuses instead of trapping",
      SafeCalldata.read(data: "0x8d80ff0a" + INT_MAX_WORD + String(repeating: "0", count: 64),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
check("a payload length near Int.max refuses instead of trapping",
      SafeCalldata.read(data: "0x8d80ff0a" + String(format: "%064x", 32) + INT_MAX_WORD
                              + String(repeating: "0", count: 64),
                        to: SAFE, value: "0", safe: SAFE) == .batch([]))
check("an inner dataLength near Int.max refuses instead of trapping",
      SafeCalldata.read(
        data: multiSend([String(format: "%02x", 0) + String(USDC.dropFirst(2))
                         + String(format: "%064x", 0)
                         + String(repeating: "0", count: 48) + "7fffffffffffffff"]),
        to: SAFE, value: "0", safe: SAFE) == .batch([]))
// A GOOD ENTRY FIRST, then the bad one — and that ordering is the whole test.
// With the bad entry alone the walker's `calls` is still empty when it bails,
// so returning `calls` and returning `[]` are the same bytes and a mutation
// swapping them SURVIVES. This harness shipped exactly that mistake and the
// mutation pass named it within the minute.
check("an inner dataLength wider than the payload refuses the calls already walked",
      SafeCalldata.read(
        data: multiSend([ONE_TRANSFER,
                         String(format: "%02x", 0) + String(USDC.dropFirst(2))
                         + String(format: "%064x", 0)
                         + String(format: "%064x", 4096)]),
        to: SAFE, value: "0", safe: SAFE) == .batch([]))
// The OFFSET IS READ, not assumed to be 0x20. A hardcoded 0x20 misreads a
// legal payload the encoder chose to place elsewhere.
let shifted = "0x8d80ff0a" + String(format: "%064x", 64) + String(repeating: "0", count: 64)
    + String(format: "%064x", goodPacked.count / 2) + goodPacked
    + String(repeating: "0", count: (64 - goodPacked.count % 64) % 64)
check("the ABI offset is READ — a payload placed past 0x20 still walks",
      SafeCalldata.read(data: shifted, to: SAFE, value: "0", safe: SAFE).batchCalls.count == 2)

// A batch inside a batch is legal and terminates without a depth counter: an
// inner payload is contained in its parent's and each entry costs 85 bytes of
// header, so the length strictly decreases.
let nested = SafeCalldata.read(
    data: multiSend([packedEntry(op: 0, to: SAFE, value: 0, data: multiSend([ONE_TRANSFER]))]),
    to: SAFE, value: "0", safe: SAFE)
check("a nested batch is walked, not refused",
      nested.batchCalls.first?.reading.batchCalls.count == 1)
check("…and an empty batch is never 'fully readable' — [] is the refusal",
      !SafeCalldata.batch([]).isFullyReadable)

print("the selectors are derived, and one of them is the cross-check rail")
// `getTransactionHash` is the call §5 makes on the Safe itself. Its selector
// is the one constant in this app whose wrongness produces a DECLINE that
// looks like a network failure — so it is pinned against the value
// scripts/support/safetx-vectors.py derives.
check("getTransactionHash → 0xd8d11f78",
      SafeCalldata.selector("getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)")
        == "0xd8d11f78")
check("domainSeparator() → 0xf698da25", SafeCalldata.selector("domainSeparator()") == "0xf698da25")
check("nonce() → 0xaffed0e0", SafeCalldata.selector("nonce()") == "0xaffed0e0")
check("getOwners() → 0xa0e67e2b", SafeCalldata.selector("getOwners()") == "0xa0e67e2b")
check("getThreshold() → 0xe75235b8", SafeCalldata.selector("getThreshold()") == "0xe75235b8")
check("VERSION() → 0xffa1ad74", SafeCalldata.selector("VERSION()") == "0xffa1ad74")
check("transfer(address,uint256) → 0xa9059cbb",
      SafeCalldata.selector("transfer(address,uint256)") == "0xa9059cbb")

print("the rail's own calldata — a wrong encoding here refuses FOREVER, silently")
// If `getTransactionHash`'s calldata is malformed the node reverts, the rail
// reads as a network failure, and the co-signer declines every transaction
// while looking merely offline. These two are derived independently (plain
// abi.encode: ten head words, `data` by offset, length-then-padded tail).
check("plain ETH send",
      SafeCall.getTransactionHash(plainETH)
        == "0xd8d11f78000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd0000000000000000000000000000000000000000000000000de0b6b3a7640000"
         + "0000000000000000000000000000000000000000000000000000000000000140"
         + String(repeating: "0", count: 64 * 7)
         + String(repeating: "0", count: 64))
check("USDC transfer — data by OFFSET, then length, then padded bytes",
      SafeCall.getTransactionHash(erc20)
        == "0xd8d11f78000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
         + String(repeating: "0", count: 64)
         + "0000000000000000000000000000000000000000000000000000000000000140"
         + String(repeating: "0", count: 64 * 6)
         + "0000000000000000000000000000000000000000000000000000000000000007"
         + "0000000000000000000000000000000000000000000000000000000000000044"
         + "a9059cbb000000000000000000000000abcdefabcdefabcdefabcdefabcdefabcdefabcd"
         + "00000000000000000000000000000000000000000000000000000000000f4240"
         + String(repeating: "0", count: 56))
// The offset is measured from the start of the ARGUMENTS, i.e. after the
// four-byte selector — 0x140 = 320 = ten words, not 324.
check("the data offset is 0x140, counted after the selector",
      SafeCall.getTransactionHash(plainETH)?
        .contains("0000000000000000000000000000000000000000000000000000000000000140") == true)
check("an unencodable field refuses the call too",
      SafeCall.getTransactionHash(
        SafeTransaction(to: "alice.eth", value: "0", data: "", operation: 0, nonce: 0)) == nil)

print("reading the Safe's answers back")
let twoOwners = "0x"
    + "0000000000000000000000000000000000000000000000000000000000000020"
    + "0000000000000000000000000000000000000000000000000000000000000002"
    + "0000000000000000000000001111111111111111111111111111111111111111"
    + "0000000000000000000000002222222222222222222222222222222222222222"
check("getOwners decodes an address[] lowercased for comparison",
      SafeCall.decodeAddressArray(twoOwners)
        == ["0x1111111111111111111111111111111111111111",
            "0x2222222222222222222222222222222222222222"])
// An empty list would read as "you are not an owner", which is the same
// refusal a real answer gives — so a malformed answer must be nil, not [].
check("a truncated answer is nil, NOT an empty owner set",
      SafeCall.decodeAddressArray("0x"
        + "0000000000000000000000000000000000000000000000000000000000000020"
        + "0000000000000000000000000000000000000000000000000000000000000002"
        + "0000000000000000000000001111111111111111111111111111111111111111") == nil)
check("a wrong head offset is nil",
      SafeCall.decodeAddressArray("0x"
        + "0000000000000000000000000000000000000000000000000000000000000040"
        + "0000000000000000000000000000000000000000000000000000000000000000") == nil)
check("empty is nil, not an empty list", SafeCall.decodeAddressArray("0x") == nil)
// A non-zero left pad means the word is not an address. Reading its last 20
// bytes anyway would put a fabricated owner in the set this phone checks
// itself against.
check("a dirty owner word is nil, not a truncated address",
      SafeCall.decodeAddressArray("0x"
        + "0000000000000000000000000000000000000000000000000000000000000020"
        + "0000000000000000000000000000000000000000000000000000000000000001"
        + "00000000000000000000ffff1111111111111111111111111111111111111111") == nil)
check("getThreshold reads 2",
      SafeCall.decodeUInt("0x" + String(repeating: "0", count: 63) + "2") == 2)
check("a threshold we cannot read is nil, never a number to compare against 2",
      SafeCall.decodeUInt("0xff") == nil)
check("an absurdly large answer is nil rather than a wrapped Int",
      SafeCall.decodeUInt("0x" + String(repeating: "f", count: 64)) == nil)
// THE FIXTURE ABOVE PASSES FOR THE WRONG REASON on its own: its high 24 bytes
// are non-zero, so it is rejected before the accumulator ever runs. This one
// has a clean high word and a full low word — the only shape that reaches the
// shift — and the shipped code TRAPPED on it until 2026-08-21. A crash is not
// a decline.
check("a full 64-bit low word is nil, and does not TRAP",
      SafeCall.decodeUInt("0x" + String(repeating: "0", count: 48)
                               + String(repeating: "f", count: 16)) == nil)
check("Int.max exactly still reads",
      SafeCall.decodeUInt("0x" + String(repeating: "0", count: 48) + "7fffffffffffffff")
        == Int.max)
check("a plausible nonce reads",
      SafeCall.decodeUInt("0x" + String(repeating: "0", count: 62) + "2a") == 42)

print("the transaction service's own shapes — v1 sends Ints, v2 sends Strings")
// Both are real: `SafeMultisigTransactionResponseSerializer` sends `nonce`,
// `baseGas` and `safeTxGas` as integers; its V2 subclass sends the same three
// as strings. A parser that read one would silently fail on the other and the
// rail would refuse everything.
let v1: [String: Any] = ["to": TO, "value": ONE_ETH, "safeTxGas": 0, "baseGas": 0,
                         "gasPrice": 0, "operation": 0, "nonce": 3]
let v2: [String: Any] = ["to": TO, "value": ONE_ETH, "safeTxGas": "0", "baseGas": "0",
                         "gasPrice": "0", "operation": 0, "nonce": "3"]
check("v1's integer fields parse", SafeSigner.transaction(from: v1)?.nonce == 3)
check("v2's string fields parse",  SafeSigner.transaction(from: v2)?.nonce == 3)
check("both produce the SAME transaction",
      SafeSigner.transaction(from: v1) == SafeSigner.transaction(from: v2))
// `gasToken`/`refundReceiver` arrive null routinely, and null legitimately
// MEANS the zero address — the one place a default is correct, and the rail
// proves it because a Safe that meant otherwise disagrees.
check("a null gasToken is the zero address",
      SafeSigner.addressField(nil) == SafeTransaction.zeroAddress)
check("an empty-string address is the zero address too",
      SafeSigner.addressField("") == SafeTransaction.zeroAddress)
// An amount we failed to read is a DIFFERENT transaction. Nil, never zero.
check("a missing amount is nil, never a zero default",
      SafeSigner.amountField(nil) == nil)
check("a missing baseGas refuses the whole parse",
      SafeSigner.transaction(from: ["to": TO, "value": "0", "safeTxGas": "0",
                                    "gasPrice": "0", "operation": 0, "nonce": 0]) == nil)
check("a negative nonce refuses the parse",
      SafeSigner.transaction(from: ["to": TO, "value": "0", "safeTxGas": "0", "baseGas": "0",
                                    "gasPrice": "0", "operation": 0, "nonce": -1]) == nil)
check("null data is empty calldata, not a failure",
      SafeSigner.transaction(from: v1)?.data == "")

print("the N-of-N rule — the one Safe failure that cannot be undone")
func standing(_ owners: Int, _ threshold: Int) -> SafeSigner.Standing {
    SafeSigner.Standing(safeAddress: SAFE, seg: "eth", ownerCount: owners, threshold: threshold)
}
// Owner management is itself a threshold-meeting transaction, so in an N-of-N
// a lost key ends the Safe: it can never be signed for and never be repaired.
check("2-of-2 has no spare owner", standing(2, 2).hasNoSpareOwner)
check("3-of-3 has no spare owner", standing(3, 3).hasNoSpareOwner)
check("2-of-3 has one to spare",
      !standing(3, 2).hasNoSpareOwner && standing(3, 2).spareOwners == 1)
check("2-of-5 has three to spare", standing(5, 2).spareOwners == 3)
// An unread owner set must not claim safety. Zero owners is not "no spare
// owner is fine", it is an answer we did not get — and `prepare` refuses on
// an unreadable owner list before this is ever consulted.
check("an empty owner set claims nothing", !standing(0, 0).hasNoSpareOwner)
// A threshold ABOVE the owner count cannot execute at all; it must not read
// as comfortably spare.
check("a threshold above the owner count has no spare", standing(2, 3).spareOwners == 0)

print("…and the transaction that repairs it")
func ready(_ reading: SafeCalldata, _ owners: Int, _ threshold: Int) -> SafeSigner.Ready {
    SafeSigner.Ready(seg: "eth", chainId: 1, safeAddress: SAFE,
                     safeTxHash: "0x00", tx: plainETH, reading: reading,
                     have: 1, required: 2, standing: standing(owners, threshold))
}
// Adding an owner WITHOUT raising the threshold is the fix; adding one AND
// raising the threshold to match leaves the Safe exactly as stuck as before,
// so it must not be greeted as the repair.
check("addOwner keeping the threshold is the repair",
      ready(.addOwner(owner: TO, threshold: "2"), 2, 2).addsASpareOwner)
check("addOwner that ALSO raises the threshold is NOT the repair",
      !ready(.addOwner(owner: TO, threshold: "3"), 2, 2).addsASpareOwner)
check("an ordinary transfer is not the repair",
      !ready(.erc20Transfer(recipient: TO, amount: "1"), 2, 2).addsASpareOwner)
// A threshold we cannot parse must not be optimistically read as the fix.
check("an unparseable threshold is not the repair",
      !ready(.addOwner(owner: TO, threshold: "many"), 2, 2).addsASpareOwner)

print("uint256 → decimal, for a figure a person reads before approving")
check("zero", SafeCalldata.decimal([UInt8](repeating: 0, count: 32)) == "0")
check("one", SafeCalldata.decimal([UInt8](repeating: 0, count: 31) + [1]) == "1")
check("max uint256 round-trips exactly",
      SafeCalldata.decimal([UInt8](repeating: 0xff, count: 32))
        == "115792089237316195423570985008687907853269984665640564039457584007913129639935")
check("1 ETH in wei round-trips",
      SafeCalldata.decimal(SafeABI.word(uint256: ONE_ETH)!) == ONE_ETH)

print("")
if failures == 0 {
    print("all assertions passed")
} else {
    print("\(failures) assertion(s) failed")
    exit(1)
}
SWIFT

echo "safetx-selftest: compiling SafeTransaction + Keccak256 WHOLE and unmodified…"
# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 5.1x faster).
# Re-probe before trusting it again after adding mutations.
swiftc -Onone -o "$TMP/run" "$TX" "$KECCAK" "$TMP/signer.swift" "$TMP/main.swift" \
  || { echo "✗ the shipped encoder does not compile Foundation-only — something reached the Keychain, the curve or SwiftData"; exit 1; }
"$TMP/run" || exit 1

# The fixtures in the driver above must be the ones the derivation prints.
# Without this the harness could pass forever against five numbers somebody
# typed in once — which is precisely the failure the derivation exists to
# prevent, moved one file over.
for h in 60551190eef75474ca063ccea91cf3246e92d20bc9eed5808dee6d3d1028818d \
         7a9bddd1a58aa59b34bf69d88f7210def0dd22cd4cc7822040d8bff3d3e2bd8d \
         7828bf9e6c5d5d73fddb54b51222c9bee3bc4031a0e76c82551b8a3c02e11739 \
         7be693d2f7ba83533e3052848cfd6e799dab186e964fcab31e3e4ae19cefcc8d \
         f563d44af5a41ac0f458c21c2d203ff7da09149720227ac15aff2b345df24d38 \
         d04701f3b47ce88fa373fe8f455450d33b3a3616c05d6a8e9af232ecfd98687f; do
  printf '%s' "$VECOUT" | grep -q "$h" \
    || { echo "✗ fixture $h is pinned in Swift but is NOT what safetx-vectors.py derives"; exit 1; }
  grep -q "$h" "$TMP/main.swift" \
    || { echo "✗ fixture $h vanished from the driver"; exit 1; }
done
echo "  ✓ all six fixtures match scripts/support/safetx-vectors.py's own output"

# --- mutation pass ----------------------------------------------------------
# Each of these is a signature that is well-formed, recovers to a real
# address, and authorizes something other than what was shown. A mutation that
# SURVIVES means nothing above was testing that line — and on this file that
# is not a gap in coverage, it is an unguarded way to lose money.
echo ""
echo "mutations (each must be caught):"

# EVERY MUTATION'S ANCHOR MUST STILL EXIST IN THE SHIPPED SOURCE, checked in
# one pass BEFORE any of them runs (2026-09-07).
#
# `mutate` already fails on an anchor it cannot find — but under `set -e` the
# heredoc's own `exit 1` kills the script before that message is printed, so a
# drifted anchor reads as a run that simply stopped, with the last line being a
# ✓. That happened three times in one hour while the overflow fix below was
# being written: each rewrite of a bounds check silently orphaned the mutation
# guarding it. This is the dead-mutation trap ("a drifted anchor makes a
# mutation change nothing, pass, and report SURVIVED") in its quieter form —
# here it does not even report. Checking up front names every casualty at once
# instead of one per fifteen-minute run.
python3 - "$TX" "$0" <<'ANCHORS'
import re, sys
src, sh = open(sys.argv[1]).read(), open(sys.argv[2]).read()
dead = [m.group(1) for m in
        re.finditer(r"mutate \"([^\"]+)\" \\\s*\n\s*'(.*?)' \\\s*\n\s*'(.*?)'\s*\n", sh, re.S)
        if m.group(2) not in src]
if dead:
    print("\u2717 mutation anchors no longer in the shipped source — these mutations test NOTHING:")
    for d in dead:
        print(f"    {d}")
    sys.exit(1)
ANCHORS
[[ $? -eq 0 ]] || exit 1

mutate() {
  local name="$1" frm="$2" to="$3"
  cp "$TX" "$TMP/SafeTransaction.swift"
  FRM="$frm" TO="$to" python3 - "$TMP/SafeTransaction.swift" <<'PY'
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
  if ! swiftc -Onone -o "$TMP/mut" "$TMP/SafeTransaction.swift" "$KECCAK" "$TMP/signer.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# §10's eight required mutations. The first five are the encoder's; the last
# three are the signature's. (The ninth — letting `threshold == 1` through —
# belongs to SafeSigner's own refusals and is asserted in that file's guards.)

# A signature replayable at any later nonce.
mutate "nonce dropped from the struct hash" \
  '+ safeTxGas + baseGas + gasPrice + gasToken + refundReceiver + nonce)' \
  '+ safeTxGas + baseGas + gasPrice + gasToken + refundReceiver)'

# A mainnet signature that executes on a testnet Safe at the same address.
mutate "chainId dropped from the domain" \
  'return Keccak256.hash(domainTypeHash + chain + verifying)' \
  'return Keccak256.hash(domainTypeHash + verifying)'

# The classic. Still 32 bytes, still hashes, wrong for every transaction that
# carries calldata — which is most of them.
mutate "data INLINED instead of its keccak" \
  'let dataHash = Keccak256.hash(dataBytes)' \
  'let dataHash = dataBytes'

# Caught ONLY by the sixth fixture. In the five the spec pins, both fields are
# zero, so this mutation reproduced every hash and survived — which is how the
# sixth fixture came to exist.
mutate "baseGas and safeTxGas swapped" \
  '+ safeTxGas + baseGas + gasPrice' \
  '+ baseGas + safeTxGas + gasPrice'

# gasToken and refundReceiver are both zero in five of the six fixtures, so
# this is caught only by the sixth. Same class as the gas swap above.
mutate "gasToken and refundReceiver transposed" \
  '+ gasToken + refundReceiver + nonce)' \
  '+ refundReceiver + gasToken + nonce)'

# Signing a pre-1.3.0 preimage for a modern Safe.
mutate "the legacy domain typehash is used to sign" \
  'Keccak256.hash(domainTypeHash + chain + verifying)' \
  'Keccak256.hash(legacyDomainTypeHash + chain + verifying)'

# The `to` and `value` words transposed — a transfer of the recipient's
# address as an amount, to an address made of the amount.
mutate "to and value transposed" \
  'safeTxTypeHash + to + value + dataHash' \
  'safeTxTypeHash + value + to + dataHash'

# 0x1901 is EIP-712's own prefix. 0x1900 is a different, valid-looking hash.
mutate "the EIP-712 prefix byte changed" \
  'Keccak256.hash([0x19, 0x01] + separator + structure)' \
  'Keccak256.hash([0x19, 0x00] + separator + structure)'

# v > 30 makes the Safe verify against the "\x19Ethereum Signed Message:\n32"
# hash and recover a stranger.
mutate "v = 31 instead of 27" \
  'return compact + [UInt8(27 + recoveryId)]' \
  'return compact + [UInt8(31 + recoveryId)]'

# Malleability: the same approval existing twice under two byte strings.
mutate "a high-s signature is emitted" \
  'guard isLowS(s) else { return nil }' \
  'guard true else { return nil }'

# The boundary that decides low-s. Off by one on the top byte and every
# signature is "low".
mutate "the half order's leading byte is widened" \
  '0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,' \
  '0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,'

# The threshold accumulator, back to the shifting-Int form that traps. Under
# `-O` a trapping harness prints nothing, which is why `mutate` treats a
# non-zero exit as caught rather than looking for a ✗.
mutate "the uint256 answer is shifted into an Int again" \
  'var value: UInt64 = 0
        for byte in bytes.suffix(8) { value = value << 8 | UInt64(byte) }
        guard value <= UInt64(Int.max) else { return nil }
        return Int(value)' \
  'var value = 0
        for byte in bytes.suffix(8) { value = value << 8 | Int(byte) }
        return value'

# A uint256 that wraps rather than refusing — an amount nobody agreed to.
mutate "uint256 overflow wraps instead of refusing" \
  'if carry != 0 { return nil }' \
  'if carry != 0 { }'

# An address word whose top twelve bytes are not checked: a 32-byte word of
# junk read as its own last twenty bytes.
# The SAME line appears twice in the file — once decoding an owner list, once
# decoding a calldata argument — so each mutation carries the line AFTER it to
# name which one it is breaking. Without that, `replace(…, 1)` silently only
# ever tested whichever came first in the file, and the second was uncovered
# while the pass read green. (It found exactly that: the calldata one was
# unguarded once `SafeCall` was inserted above it.)
mutate "a dirty owner word is accepted from getOwners" \
  'guard word.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
            out.append(' \
  'guard true else { return nil }
            out.append('

mutate "a dirty address word is accepted in calldata" \
  'guard word.prefix(12).allSatisfy({ $0 == 0 }) else { return nil }
            return EIP55.checksum(' \
  'guard true else { return nil }
            return EIP55.checksum('

# --- THE BATCH WALK (2026-09-07) --------------------------------------------
# Every one of these produces a batch that renders perfectly and is not the
# transaction being signed. §238 measured 96 of 100 real Safe transactions as
# `multiSend`, so these are mutations on the COMMON path, not an exotic one.

# THE PARTIAL LIST — the single most dangerous failure this walker can have.
# Returning what it got before losing the thread means every line on screen is
# true and the total is false, which is exactly the fluent-wrong-summary
# `SafeCalldata` exists to refuse.
mutate "a truncated entry returns the calls it already got" \
  'guard payload.count - i >= 85 else { return [] }' \
  'guard payload.count - i >= 85 else { return calls }'

mutate "an inner dataLength past the buffer returns a partial list" \
  'dataLength <= payload.count - i - 85 else { return [] }' \
  'dataLength <= payload.count - i - 85 else { return calls }'

# NOT MUTATED, DELIBERATELY, and this is the reason written down rather than a
# gap: `guard i == payload.count` after the loop is UNREACHABLE as a failure.
# The in-loop bound is `payload.count >= i + 85 + dataLength`, so after
# `i += 85 + dataLength` we always have `i <= payload.count`, and the `while
# i < payload.count` condition exits only at exactly `==`. So no input can
# make that guard fire, `guard i <= payload.count` behaves identically, and a
# mutation swapping them SURVIVES while changing nothing — which is the
# dead-mutation trap this repo records (a drifted or inert mutation prints a
# passing line and certifies nothing). The guard stays in the source because
# it pins the invariant the bounds arithmetic above it must keep; it is an
# assertion about a future edit, not a check with a failing input today, and
# claiming a mutation proved it would be false.

# The ABI offset assumed rather than read. A legal payload placed elsewhere is
# then read from the wrong bytes.
mutate "the ABI offset is assumed to be 0x20" \
  'guard let offset = int(Array(args[0..<32])), offset >= 0,' \
  'guard let offset = Optional(32), offset >= 0,'

# The declared length ignored, so trailing padding is walked as entry data.
mutate "the payload length is not bounds-checked" \
  'length <= args.count - offset - 32 else { return [] }' \
  'length >= 0 else { return [] }'

# The entry header is 1 + 20 + 32 + 32 = 85 bytes. Any other stride reads every
# field of every entry from the wrong place.
mutate "the packed entry header is mis-sized" \
  'i += 85 + dataLength' \
  'i += 84 + dataLength'

mutate "the value word is read one byte over" \
  'let value = decimal(Array(payload[(i + 21)..<(i + 53)]))' \
  'let value = decimal(Array(payload[(i + 20)..<(i + 52)]))'

# THE OVERFLOW TRAP. Swift's `+` is checked, so an additive bound on a word an
# attacker chooses is a CRASH, not a wrong answer — and this calldata comes off
# a proposal anyone who can write to the Safe's transaction service controls.
# `mutate` treats a non-zero exit as caught, which is exactly what a trap is.
mutate "the ABI offset bound goes back to an addition that can trap" \
  'offset <= args.count - 32 else { return [] }' \
  'args.count >= offset + 32 else { return [] }'

mutate "the payload length bound goes back to an addition that can trap" \
  'length <= args.count - offset - 32 else { return [] }' \
  'args.count >= offset + 32 + length else { return [] }'

mutate "the inner dataLength bound goes back to an addition that can trap" \
  'dataLength <= payload.count - i - 85 else { return [] }' \
  'payload.count >= i + 85 + dataLength else { return [] }'

# An unknown operation byte accepted. Safe's multiSend defines 0 and 1; a
# third value means these are not the bytes this decoder thinks they are.
mutate "an unknown operation byte is accepted" \
  'guard operation == 0 || operation == 1 else { return [] }' \
  'guard operation >= 0 else { return [] }'

# DELEGATECALL flattened to an ordinary call — the warning disappears from a
# call that can rewrite the owner list.
mutate "an inner DELEGATECALL is reported as a plain call" \
  'var isDelegateCall: Bool { operation == 1 }' \
  'var isDelegateCall: Bool { false }'

# A batch containing an unreadable call claimed as fully read: the screen then
# lists four sentences and drops the one that says it could not read the fifth.
mutate "a batch with an unreadable call claims to be fully read" \
  'return !calls.isEmpty && calls.allSatisfy { $0.reading.isFullyReadable }' \
  'return true'

# An EMPTY batch — the walk's own refusal — presented as fully read.
mutate "an unwalkable batch is presented as fully read" \
  'return !calls.isEmpty && calls.allSatisfy' \
  'return calls.isEmpty || calls.allSatisfy'

# removeOwner's linked-list cursor named as the owner being removed.
mutate "removeOwner reads its list cursor as the owner" \
  'if let a = address(1) { return .removeOwner(owner: a) }' \
  'if let a = address(0) { return .removeOwner(owner: a) }'

# The refusal itself. A known selector with unreadable arguments summarised
# anyway is the fluent wrong summary §8.5 exists to ban.
mutate "an undecodable calldata claims to be decoded" \
  'if case .undecoded = self { return false }' \
  'if case .undecoded = self { return true }'

# --- the refusals, mutation-proven ------------------------------------------
# `guard_check` above is greps, and a grep that cannot fail proves nothing. Each
# mutation here edits a COPY of the shipped file and requires the same
# `guard_check` to go red — so the guards are demonstrated against the real
# source rather than trusted.
echo ""
echo "refusal mutations (each must turn guard_check red):"

guard_mutate() {   # $1 = name, $2 = signer|key, $3 = from, $4 = to
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$SIGNER" "$TMP/SafeSigner.swift"
  cp "$KEY" "$TMP/SignerKey.swift"
  local target
  case "$which" in
    signer) target="$TMP/SafeSigner.swift" ;;
    key)    target="$TMP/SignerKey.swift" ;;
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
  if guard_check "$TMP/SafeSigner.swift" "$TMP/SignerKey.swift"; then
    echo "  ✗ $name — guard_check still passed, so nothing was guarding this"; exit 1
  fi
  echo "  ✓ $name"
}

# §8.1 — the mutation the spec names by hand. A 1-of-N Safe naming this phone
# is a custodial wallet wearing a multisig's clothes.
guard_mutate "threshold == 1 is let through" signer \
  'guard threshold >= 2 else' 'guard threshold >= 1 else'
# …and the weaker version, which reads as a tightening and is not one.
guard_mutate "the threshold guard grows an escape clause" signer \
  'guard threshold >= 2 else { return .failure(.thresholdTooLow(threshold)) }' \
  'guard threshold >= 2 || true else { return .failure(.thresholdTooLow(threshold)) }'
# §8.2 — ownership read from the chain.
guard_mutate "the owner check is dropped" signer \
  'guard owners.contains(me.lowercased()) else { return .failure(.notAnOwner) }' \
  'if false { return .failure(.notAnOwner) }'
guard_mutate "the threshold is taken from a cache instead of the chain" signer \
  'async let thresholdRead = call(rail, to: safeAddress, data: SafeCall.getThresholdSelector)' \
  'async let thresholdRead = call(rail, to: safeAddress, data: SafeBridge.cachedThreshold)'
guard_mutate "the owner list is taken from a cache instead of the chain" signer \
  'async let ownersRead = call(rail, to: safeAddress, data: SafeCall.getOwnersSelector)' \
  'async let ownersRead = call(rail, to: safeAddress, data: SafeBridge.cachedOwners)'
# §8.3 — the rail itself, and BOTH halves of it.
guard_mutate "the getTransactionHash cross-check is removed" signer \
  'SafeCall.getTransactionHash(tx)' 'Optional<String>.none'
guard_mutate "a hash mismatch stops refusing" signer \
  'guard chain.lowercased() == local.lowercased() else {' \
  'if false {'
# §8.6 — no export path. A second reader of the key is an export however it is
# spelled, and this is the mutation that says so.
guard_mutate "a second reader of the private bytes appears" key \
  'kSecReturnData as String: true,' \
  'kSecReturnData as String: true, kSecReturnPersistentRef as String: true, kSecReturnData as String: true,'
# …and the attribute-only presence check must not quietly start pulling the
# value, which would make the "is the key still there?" test cost a Face ID on
# every screen appearance — and put the scalar in memory for a question that
# never needed it.
guard_mutate "the presence check starts decrypting the key" key \
  'kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess { return .present }' \
  'kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess { return .present }'
# THE ONE THE RULING TURNS ON (prd §426). Refusing to sign an N-of-N is not a
# safety measure, it IS the lock: in a 2-of-2 that names this phone, our
# decline is what stops the Safe reaching its threshold. So the warning must
# never grow into a refusal, and this proves the guard would notice.
guard_mutate "the N-of-N warning becomes a refusal" signer \
  'let required = (row["confirmationsRequired"] as? Int) ?? threshold' \
  'if owners.count == threshold { return .failure(.notAnOwner) }
        let required = (row["confirmationsRequired"] as? Int) ?? threshold'

# The biometric gate.
# Targets the CALL, not the flag name: the file explains its own choice in a
# comment that also spells `.biometryCurrentSet`, so a bare flag-name mutation
# edits the prose and leaves the code alone — a mutation that proves nothing.
guard_mutate "the biometric gate is widened to any enrolled face" key \
  'SecAccessControlCreateWithFlags(nil, accessible, [.biometryCurrentSet], &acError)' \
  'SecAccessControlCreateWithFlags(nil, accessible, [.biometryAny], &acError)'
# The self-check that the signature really is this phone's.
guard_mutate "the recovered-address self-check is dropped" key \
  'recoveredAddress.lowercased() == expected.lowercased()' 'true'

echo ""
echo "✓ safetx self-test: fixtures pinned, refusals proven, every mutation caught"
