#!/bin/zsh
# Casberi vibenet-signer self-test — the SHIPPED refusal ladder that decides
# whether this phone may sign on Base's EIP-8130 devnet (2026-08-29, prd §523):
#
#   Casberi/Casberi/Model/VibenetSigner.swift
#     — decide()    the ladder: eleven refusals, one ready
#     — sentence()  the copy each refusal carries
#     — name()      the stable label a probe prints
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion below is about the
# bytes the app runs.
#
# WHY A HARNESS, AND WHY IT IS THE ONLY PROOF. This is the first path in this
# app that can produce a signature, and NOTHING else here can see it:
#
#   • no simulator has a Secure Enclave, so every path in `VibenetDeviceKey`
#     runs its unavailable branch and a sim sweep exercises none of it;
#   • a build is happy with a ladder in any order;
#   • the screen sweep proves a sheet painted, never that it painted a refusal
#     rather than a button.
#
# And every failure renders as an ordinary screen. A ladder that reports
# `noKey` for a DESTROYED key offers to make a new one while an account out
# there still authorizes a key this phone can never produce again. A ladder
# that treats "we could not simulate" as permission signs on a maybe. A ladder
# that reads "we could not read the account's keys" as "no" says "this account
# doesn't list your key" about an account it can sign for, forever, with every
# other check green.
#
# THE ONE THAT MATTERS MOST is the chain rail: `wrongChain` is what makes
# signing on a real network IMPOSSIBLE rather than merely unintended, so it is
# mutation-proven below and its removal must fail this script.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGNER="Casberi/Casberi/Model/VibenetSigner.swift"
DEVKEY="Casberi/Casberi/Model/VibenetDeviceKey.swift"
BRIDGE="Casberi/Casberi/Model/VibenetBridge.swift"
for f in "$SIGNER" "$DEVKEY" "$BRIDGE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# DRIFT GUARDS — facts the compiled ladder cannot prove about itself.
#
# Read from a COMMENT-STRIPPED copy, because both files DOCUMENT these rules
# by naming the very things they must not do — a guard grepping raw source
# fires against the prose explaining it (the Obsidian/Cursor lesson, and it
# has now cost this repo eight separate guards).
# ---------------------------------------------------------------------------
strip_comments() {
  sed -E 's://.*$::' "$1" | sed -E 's:/\*.*\*/::'
}
strip_comments "$DEVKEY" > "$WORK/devkey.nocomment"
strip_comments "$SIGNER" > "$WORK/signer.nocomment"

# 1. THE KEY FILE REACHES NOTHING. It makes a key, says whether it is there,
#    and signs 32 bytes. A URL or an RPC method appearing in it means the one
#    file holding a signing key also learned to talk to a host.
for banned in 'URLSession' 'https://' 'http://' 'eth_sendRawTransaction' 'eth_call' 'URLRequest'; do
  if grep -qF "$banned" "$WORK/devkey.nocomment"; then
    echo "✗ VibenetDeviceKey names '$banned' — the signing key file must reach nothing"
    exit 1
  fi
done

# 2. KEYCHAIN POLICY (scripts/keychain-audit.py's rule, asserted here too
#    because this file's item is the one that would matter most). A signing
#    key that rides an encrypted backup onto a restored device is the exact
#    failure that audit exists to prevent.
grep -qF 'kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly' "$WORK/devkey.nocomment" \
  || { echo "✗ VibenetDeviceKey no longer pins a ThisDeviceOnly accessibility"; exit 1; }
grep -qF 'kSecAttrSynchronizable' "$WORK/devkey.nocomment" \
  || { echo "✗ VibenetDeviceKey no longer names kSecAttrSynchronizable"; exit 1; }

# 3. `.biometryCurrentSet`, NOT `.biometryAny`. §427's ruling: a changed
#    enrolled set is a changed AUTHORITY the chain cannot see. Loosening this
#    is a real decision and must not happen by drift.
grep -qF '.biometryCurrentSet' "$WORK/devkey.nocomment" \
  || { echo "✗ VibenetDeviceKey no longer uses .biometryCurrentSet"; exit 1; }
if grep -qF '.biometryAny' "$WORK/devkey.nocomment"; then
  echo "✗ VibenetDeviceKey uses .biometryAny — §427 says the enrolled set is the authority"
  exit 1
fi

# 4. NO EXPORT PATH, counted the way §425 learned to count it: `grep -c`
#    counts LINES, so a second call appended to the same line survives that
#    guard. Count OCCURRENCES, and count the line that actually decrypts
#    (`kSecReturnData`) rather than every SecItemCopyMatching — `presence()`
#    is an honest attribute-only query and must not be mistaken for a reader
#    of the private half.
READS=$(grep -o 'kSecReturnData' "$WORK/devkey.nocomment" | wc -l | tr -d ' ')
if [[ "$READS" != "1" ]]; then
  echo "✗ VibenetDeviceKey has $READS kSecReturnData occurrences, expected exactly 1"
  exit 1
fi

# 5. THE CHAIN THE BRIDGE READS AND THE CHAIN THE KEY SIGNS FOR ARE ONE
#    NUMBER. They are declared in two files, so nothing but this stops them
#    drifting into a state where the app reads vibenet and signs somewhere
#    else. Measured 2026-08-29: eth_chainId answers 0x509f455 = 84538453.
grep -qF '84_538_453' "$WORK/signer.nocomment" \
  || { echo "✗ VibenetSigner.chainID is no longer 84538453 (0x509f455, measured)"; exit 1; }

# 6. CANNOT-SAY STAYS ITS OWN ANSWER. Dropping this case makes an unreadable
#    account indistinguishable from one that refuses this phone, which is the
#    failure the whole ladder is shaped around.
grep -qF 'actorDataUnreadable' "$WORK/signer.nocomment" \
  || { echo "✗ .actorDataUnreadable is gone — cannot-say must never collapse into notAnAuthenticator"; exit 1; }
# MEASURED 2026-08-29: the actorId is supplied by the caller in the
# AuthorizeActor payload, never derived by a contract, so a build that HASHES a
# public key and looks for the result answers "not an authenticator" about
# accounts it can sign for. Guarded as a negative: this file must never reach
# for a hash to answer that question.
if grep -qE 'keccak|sha3|hash\(' "$WORK/signer.nocomment"; then
  echo "✗ VibenetSigner is hashing something — the actorId is caller-supplied, not derived"
  exit 1
fi

# ---------------------------------------------------------------------------
# THE LADDER — compiled whole, then asserted.
# ---------------------------------------------------------------------------
cp "$SIGNER" "$WORK/VibenetSigner.swift"

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if !ok { print("  ✗ \(label)"); failures += 1 }
}

let NOW = Date(timeIntervalSince1970: 1_800_000_000)   // fixed, never Date()
let ID  = "0xabc123"

/// A Facts value that is READY, so every fixture below breaks exactly one
/// thing. A fixture that fails for two reasons proves nothing about either.
func ready() -> VibenetSigner.Facts {
    VibenetSigner.Facts(publicKeyHex: "aabbcc",
                        ourActorID: ID,
                        authorizedActorIDs: [ID],
                        simulation: .succeeds)
}

func refusal(_ f: VibenetSigner.Facts) -> String? {
    switch VibenetSigner.decide(f, now: NOW) {
    case .success: return nil
    case .failure(let r): return VibenetSigner.name(r)
    }
}

// --- the baseline is genuinely ready ---------------------------------------
check("baseline is ready", refusal(ready()) == nil)

// --- every rung, one at a time ---------------------------------------------
var f = ready(); f.enclaveAvailable = false
check("no enclave", refusal(f) == "noEnclave")

f = ready(); f.publicKeyHex = nil
check("no key", refusal(f) == "noKey")

f = ready(); f.publicKeyHex = ""
check("empty key reads as no key", refusal(f) == "noKey")

// DESTROYED BEATS ABSENT. A destroyed key keeps its cached public half, so a
// ladder testing absence first reports noKey and offers to make a new one —
// hiding that an account still authorizes a key this phone cannot produce.
f = ready(); f.keyDestroyed = true
check("destroyed key names itself", refusal(f) == "keyDestroyed")
f = ready(); f.keyDestroyed = true; f.publicKeyHex = nil
check("destroyed beats absent", refusal(f) == "keyDestroyed")

// THE RAIL. Signing on a real chain must be impossible.
f = ready(); f.chainID = 1
check("mainnet is refused", refusal(f) == "wrongChain")
f = ready(); f.chainID = 8453
check("base mainnet is refused", refusal(f) == "wrongChain")
f = ready(); f.chainID = nil
check("unknown chain is unreadable, not wrong", refusal(f) == "chainUnreadable")
check("the chain is the measured one", VibenetSigner.chainID == 84_538_453)

f = ready(); f.contractsReadable = false
check("unreadable contracts refuse", refusal(f) == "contractsUnreadable")

f = ready(); f.accountReachable = false
check("unreachable account refuses", refusal(f) == "chainUnreadable")

// CANNOT SAY IS NOT NO.
f = ready(); f.ourActorID = nil
check("nil actor data is its own refusal", refusal(f) == "actorDataUnreadable")
f = ready(); f.ourActorID = ""
check("empty actor data is its own refusal", refusal(f) == "actorDataUnreadable")

f = ready(); f.authorizedActorIDs = ["0xsomeoneelse"]
check("not an authenticator", refusal(f) == "notAnAuthenticator")
f = ready(); f.authorizedActorIDs = []
check("empty roster is not an authenticator", refusal(f) == "notAnAuthenticator")

// CASE. An actorId read off the chain and one built here can differ in case
// and mean the same key; a case-sensitive join refuses an account we can sign
// for, which is this ladder's worst failure mode wearing a different hat.
f = ready(); f.authorizedActorIDs = [ID.uppercased()]
check("the join is case-insensitive", refusal(f) == nil)

// EXPIRY. 0 is Keystore.sol's "no expiry set", a VALUE and not a date —
// reading it as 1970 expires every unlimited key in the app.
f = ready(); f.expiry = 0
check("expiry 0 means never", refusal(f) == nil)
f = ready(); f.expiry = nil
check("absent expiry means never", refusal(f) == nil)
f = ready(); f.expiry = UInt64(NOW.timeIntervalSince1970) - 1
check("past expiry refuses", refusal(f) == "keyExpired")
f = ready(); f.expiry = UInt64(NOW.timeIntervalSince1970) + 3600
check("future expiry is fine", refusal(f) == nil)
// The boundary: expiry exactly now has passed. A `<` here lets a key sign in
// the same second it dies.
f = ready(); f.expiry = UInt64(NOW.timeIntervalSince1970)
check("expiry exactly now has passed", refusal(f) == "keyExpired")

f = ready(); f.accountLocked = true
check("locked account refuses", refusal(f) == "accountLocked")

// SIMULATION. Both of these refuse. "Could not run" is not permission.
f = ready(); f.simulation = nil
check("unread simulation refuses", refusal(f) == "simulationUnread")
f = ready(); f.simulation = .reverts("insufficient funds")
check("reverting simulation refuses", refusal(f) == "simulationFailed")

// --- the ready payload ------------------------------------------------------
switch VibenetSigner.decide(ready(), now: NOW) {
case .failure: check("ready payload", false)
case .success(let r):
    check("ready carries our id", r.actorID == ID)
    check("sole key is the only key", r.isOnlyKey)
}
f = ready(); f.authorizedActorIDs = [ID, "0xother"]
switch VibenetSigner.decide(f, now: NOW) {
case .failure: check("two-key payload", false)
case .success(let r): check("two keys is not only-key", !r.isOnlyKey)
}

// --- fault vs not-yet -------------------------------------------------------
check("a revert is a fault", VibenetSigner.Refusal.simulationFailed(nil).isFault)
check("a destroyed key is a fault", VibenetSigner.Refusal.keyDestroyed.isFault)
check("unreadable contracts are a fault", VibenetSigner.Refusal.contractsUnreadable.isFault)
check("no key is not a fault", !VibenetSigner.Refusal.noKey.isFault)
check("not an authenticator is not a fault", !VibenetSigner.Refusal.notAnAuthenticator.isFault)
check("unread simulation is not a fault", !VibenetSigner.Refusal.simulationUnread.isFault)

// --- every refusal has a sentence and a distinct name ----------------------
let all: [VibenetSigner.Refusal] = [
    .noEnclave, .noKey, .keyDestroyed, .wrongChain(1), .contractsUnreadable,
    .chainUnreadable, .actorDataUnreadable, .notAnAuthenticator,
    .keyExpired(NOW), .accountLocked, .simulationFailed("why"), .simulationUnread,
]
check("twelve refusals", all.count == 12)
for r in all {
    check("sentence for \(VibenetSigner.name(r))", !VibenetSigner.sentence(r).isEmpty)
}
check("names are distinct", Set(all.map(VibenetSigner.name)).count == all.count)
// A refusal whose sentence is its own name is a placeholder, not copy.
for r in all {
    check("\(VibenetSigner.name(r)) has real copy",
          VibenetSigner.sentence(r) != VibenetSigner.name(r))
}
// The reverting case must carry the chain's reason when it has one, or the
// only actionable refusal in the ladder tells you nothing.
check("revert reason is surfaced",
      VibenetSigner.sentence(.simulationFailed("nonce too low")).contains("nonce too low"))
check("revert with no reason still reads",
      !VibenetSigner.sentence(.simulationFailed(nil)).isEmpty)
// The wrong chain says WHICH chain, so the sentence is not a mystery.
check("wrong chain names the chain", VibenetSigner.sentence(.wrongChain(8453)).contains("8453"))

if failures == 0 { print("  ok") } else { exit(1) }
SWIFT

swiftc -O -o "$WORK/run" "$WORK/VibenetSigner.swift" "$WORK/main.swift" 2>"$WORK/build.log" || {
  echo "✗ VibenetSigner.swift did not compile standalone (it must stay Foundation-only)"
  head -30 "$WORK/build.log"
  exit 1
}
echo "vibenet signer:"
"$WORK/run" || exit 1

# ---------------------------------------------------------------------------
# MUTATIONS — each one is a silent wrong answer this harness must catch. A
# check that cannot fail proves nothing, so every rung is broken on purpose
# and the suite must go red.
# ---------------------------------------------------------------------------
mutate() {
  local label="$1" from="$2" to="$3"
  cp "$SIGNER" "$WORK/VibenetSigner.swift"
  if ! grep -qF -- "$from" "$WORK/VibenetSigner.swift"; then
    echo "  ✗ STALE MUTATION '$label' — pattern not found, so it tests nothing"
    return 1
  fi
  python3 - "$WORK/VibenetSigner.swift" "$from" "$to" <<'PY'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if swiftc -O -o "$WORK/mrun" "$WORK/VibenetSigner.swift" "$WORK/main.swift" 2>/dev/null \
     && "$WORK/mrun" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $label"
    return 1
  fi
  echo "  ✓ caught: $label"
  return 0
}

echo "mutations:"
MUT=0
# THE RAIL. Without this the key signs on any chain that answers.
mutate "chain rail removed"        'guard chain == chainID else { return .failure(.wrongChain(chain)) }' \
                                   'if false { return .failure(.wrongChain(chain)) }' || MUT=1
# The measured chain id itself.
mutate "chain id changed"          'static let chainID: UInt64 = 84_538_453' \
                                   'static let chainID: UInt64 = 8453' || MUT=1
# Destroyed-before-absent ordering.
mutate "destroyed ordered after absent" 'if f.keyDestroyed { return .failure(.keyDestroyed) }' \
                                        'if false { return .failure(.keyDestroyed) }' || MUT=1
# "Cannot say" read as "no".
mutate "cannot-say read as no"      'return .failure(.actorDataUnreadable)' \
                                    'return .failure(.notAnAuthenticator)' || MUT=1
# Unread simulation treated as permission.
mutate "unread simulation allowed"  'case .none:                    return .failure(.simulationUnread)' \
                                    'case .none:                    break' || MUT=1
# A revert treated as permission.
mutate "revert allowed"             'case .some(.reverts(let why)): return .failure(.simulationFailed(why))' \
                                    'case .some(.reverts(let why)): _ = why' || MUT=1
# Expiry 0 read as a date — expires every unlimited key.
mutate "expiry 0 read as a date"    'if expiry != 0 {' 'if true {' || MUT=1
# The expiry boundary.
mutate "expiry boundary loosened"   'if when <= now { return .failure(.keyExpired(when)) }' \
                                    'if when < now { return .failure(.keyExpired(when)) }' || MUT=1
# The lock.
mutate "lock ignored"               'if f.accountLocked { return .failure(.accountLocked) }' \
                                    'if false { return .failure(.accountLocked) }' || MUT=1
# Unreadable contracts ignored — signing against a guessed address.
mutate "contracts guard removed"    'guard f.contractsReadable else { return .failure(.contractsUnreadable) }' \
                                    'if false { return .failure(.contractsUnreadable) }' || MUT=1
# The case-insensitive join.
mutate "join made case-sensitive"   'let authorized = f.authorizedActorIDs.map { $0.lowercased() }' \
                                    'let authorized = f.authorizedActorIDs' || MUT=1
# only-key, which is the sentence about whether this decline is the lock.
mutate "only-key inverted"          'isOnlyKey: authorized.count == 1' \
                                    'isOnlyKey: authorized.count != 1' || MUT=1
# A fault that stops reading as one.
mutate "revert stops being a fault" 'case .simulationFailed, .keyDestroyed, .contractsUnreadable: true' \
                                    'case .keyDestroyed, .contractsUnreadable: true' || MUT=1

[[ $MUT -eq 0 ]] || exit 1

# 7. TWO FILES NOW DERIVE THE ACTOR ID AND THEY MUST NOT DRIFT.
#    `VibenetP256Auth.actorID` is compiled and asserted below against the word
#    the deployed contract itself returns; `VibenetDeviceKey.actorID` computes
#    the same thing for THIS phone and cannot be compiled here (it needs
#    Security and CryptoKit). So it is guarded by shape: it must keccak the raw
#    64-byte x||y and nothing else. The tagged form `0x04 || x || y` is how a
#    public key is usually framed and produces a different, plausible-looking
#    word the chain disagrees with — the one wrong answer that would look right.
grep -qF 'Keccak256.hash([UInt8](xy))' "$WORK/devkey.nocomment" \
  || { echo "✗ VibenetDeviceKey.actorID no longer keccaks the raw x||y"; exit 1; }
if grep -qE 'Keccak256\.hash\(\[UInt8\]\(Data\(\[4\]\)' "$WORK/devkey.nocomment"; then
  echo "✗ VibenetDeviceKey.actorID is hashing the 0x04-tagged key — the chain answers differently"
  exit 1
fi

# ---------------------------------------------------------------------------
# THE TRANSACTION ENCODER — pinned to a hash PROVEN against the chain.
#
# `VibenetTransaction.senderSigningPreimage` produces the bytes that get
# signed. A wrong field order, a stray leading zero on a quantity, a flattened
# `calls`, or the wrong type byte yields a signature that is well-formed and
# recovers to a DIFFERENT address — green build, right screen, wrong
# transaction. `SafeTransaction` answers this class by asking the Safe for
# `getTransactionHash`; vibenet publishes no counterpart, so the proof is that
# a REAL transaction's fields, its 65-byte senderAuth and its `from` agree only
# under one encoding. Sixteen candidates were tried and exactly one recovered
# the signer (`scripts/support/vibenet-tx-vectors.py`, measured 2026-08-29).
#
# The PREIMAGE LENGTH is pinned beside the hash on purpose: a hash fixture
# alone cannot say which of two encodings produced it, and the length is what
# separates a phased `calls` from a flat one.
# ---------------------------------------------------------------------------
TXFILE="Casberi/Casberi/Model/VibenetTransaction.swift"
[[ -f "$TXFILE" ]] || { echo "✗ $TXFILE not found"; exit 1; }

# The generator must still agree with the fixture below. It is NOT run here
# (it needs egress, and a check that cannot run offline must never fail a
# build — `live-integrations.sh`'s contract); what is asserted is that its
# self-test passes and that it still names the same hash this file pins.
python3 scripts/support/vibenet-tx-vectors.py --self-test >/dev/null \
  || { echo "✗ vibenet-tx-vectors self-test failed — its RLP primitives moved"; exit 1; }
grep -qF '96c32d8901d632f6b97b4c79300d46b5daba7667de24724da15de0cbd85f4ca9' scripts/vibenet-signer-selftest.sh \
  || { echo "✗ the proven signing hash is no longer pinned"; exit 1; }

cp "$TXFILE" "$WORK/VibenetTransaction.swift"
cp Casberi/Casberi/Model/Keccak256.swift "$WORK/Keccak256.swift"
cp Casberi/Casberi/Model/VibenetCreate.swift "$WORK/VibenetCreate.swift"
mkdir -p "$WORK/txmain"
cat > "$WORK/txmain/main.swift" <<'SWIFT'
import Foundation
var fails = 0
func check(_ l: String, _ ok: Bool) { if !ok { print("  ✗ \(l)"); fails += 1 } }
func hx(_ s: String) -> Data {
    var t = Substring(s); if t.hasPrefix("0x") { t = t.dropFirst(2) }
    var d = Data(); var i = t.startIndex
    while i < t.endIndex { let j = t.index(i, offsetBy: 2); d.append(UInt8(t[i..<j], radix: 16)!); i = j }
    return d
}
// --- RLP primitives, where the silent hash-changing bugs live ---------------
check("zero is EMPTY, never 0x00", VibenetTransaction.quantity(0).isEmpty)
check("one byte", VibenetTransaction.quantity(1) == Data([1]))
check("no leading zeros", VibenetTransaction.quantity(0x0100) == Data([1, 0]))
check("a small byte is bare", VibenetTransaction.encode(.bytes(Data([1]))) == Data([1]))
check("0x80 takes a prefix", VibenetTransaction.encode(.bytes(Data([0x80]))) == Data([0x81, 0x80]))
check("empty string", VibenetTransaction.encode(.bytes(Data())) == Data([0x80]))
check("empty list", VibenetTransaction.encode(.list([])) == Data([0xc0]))
// THE BOUNDARY, ASSERTED ON LENGTH RATHER THAN ON THE FIRST BYTE. The naive
// version — first byte == 0xb8 for 56 bytes — is VACUOUS, because short form
// would emit 0x80 + 56, which IS 0xb8. Two different encodings, one leading
// byte. Caught by mutation: `< 56` loosened to `< 57` survived it.
check("55 bytes is short form (1 byte of header)",
      VibenetTransaction.encode(.bytes(Data(repeating: 0x61, count: 55))).count == 56)
check("56 bytes is long form (2 bytes of header)",
      VibenetTransaction.encode(.bytes(Data(repeating: 0x61, count: 56))).count == 58)
check("type byte is the measured 0x79", VibenetTransaction.txType == 0x79)

// --- THE PROVEN VECTOR ------------------------------------------------------
let c0 = "0x0000000000000000000000008130faa29d2675d05d01d387c576c6525f280ac1000000000000000000000000be114b191a3ac7519670cac0c5e74aac1d819a130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000"
let c1 = "0x00000000000000000000000050ae99e14139082a785e808acfbe86283b009e9d00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000348130faa29d2675d05d01d387c576c6525f280ac156c93c1577142941eb967b88d32d1717532a66d1fb296edbf73fb3065e8690d8000000000000000000000000"
let sig = "0x000000000000000000000000000000000000000102a1423efdb26b7798274b259d80329e2a22dfe465d89b9098a824a2f00dcba6625160be4546446b89efb3d4e7a017f00d9d5ebda59f77668198aa12dda464101c"
let fields = VibenetTransaction.Fields(
    chainID: 84_538_453, nonceSequence: 2,
    maxPriorityFeePerGas: 0xf4240, maxFeePerGas: 0x3b9aca00, gasLimit: 206_549,
    accountChanges: [.config(.init(sequence: 0,
        changes: [.authorizeActor(hx(c0)), .authorizeActor(hx(c1))], auth: hx(sig)))],
    calls: [[.init(to: hx("0xe36fd7ef90c664e9d005ad7f36796b4be65bfbb9"), data: Data())]])
// --- THE P-256 AUTHENTICATOR, MEASURED AGAINST THE DEPLOYED CONTRACT --------
// Key `c9afa9d8…f6721` over the hash 0x11*32. `P256Authenticator.authenticate`
// answered 0x1547e66d… for exactly this 129-byte payload on 2026-08-29, and
// returned ZERO for a signature presented against the wrong message — so a
// non-zero answer is a real verification, not an echo.
let pX = hx("0x60fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6")
let pY = hx("0x7903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299")
let pR = hx("0xbc4391121bae51e1ebedae7c13eeff416eac2dbcbc1640d61654f9574ea4ebc6")
let pS = hx("0x22a8c1b50005cd63ba151cea077f03589687e7834a3691ec548d7c066610ef19")
let authAddr = hx("0x8130c89f65750431b564a4730397552a11cea256")
let xy = pX + pY
check("actorId is keccak(x|y), the word the contract itself returns",
      VibenetP256Auth.actorID(publicKeyXY: xy)?.map { String(format: "%02x", $0) }.joined()
      == "1547e66da415404f4d702182db1cf7c2c5375aea1b363bd4a67803c7f704051b")
// 129 EXACTLY. 128 and 130 both revert on chain, so this is the length, not a
// minimum — and the order is measured too: x|y|r|s reverts.
check("auth data is exactly 129 bytes",
      VibenetP256Auth.authData(r: pR, s: pS, publicKeyXY: xy)?.count == 129)
check("auth data is r|s|x|y|pad",
      VibenetP256Auth.authData(r: pR, s: pS, publicKeyXY: xy) == pR + pS + xy + Data([0]))
check("senderAuth prefixes the authenticator, 149 bytes",
      VibenetP256Auth.senderAuth(authenticator: authAddr, r: pR, s: pS, publicKeyXY: xy)
      == authAddr + pR + pS + xy + Data([0]))
// Lengths are refused rather than padded — a short key would otherwise compose
// a payload the chain reverts on, reported as an ordinary failure.
check("a wrong-length key is refused",
      VibenetP256Auth.authData(r: pR, s: pS, publicKeyXY: Data(repeating: 1, count: 63)) == nil)
check("a wrong-length r is refused",
      VibenetP256Auth.authData(r: Data(repeating: 1, count: 31), s: pS, publicKeyXY: xy) == nil)
check("a wrong-length authenticator is refused",
      VibenetP256Auth.senderAuth(authenticator: Data(repeating: 1, count: 19), r: pR, s: pS, publicKeyXY: xy) == nil)
// The tag'd form produces a DIFFERENT, plausible-looking word the contract
// does not agree with. Measured both ways; this pins the one that is right.
check("the id is NOT keccak(0x04|x|y)",
      VibenetP256Auth.actorID(publicKeyXY: xy) != Data(Keccak256.hash([UInt8](Data([4]) + xy))))

// --- A REAL, SPONSORED, P-256-SIGNED ACCOUNT CREATION -----------------------
// tx 0xee57134d… on this chain. The strongest fixture here, because the
// signature is somebody ELSE'S over bytes we did not choose: if our encoder
// disagrees by one byte, the real P-256 signature stops verifying against the
// hash we compute. Three such creations were checked and 3/3 verified.
//
// It also settles the design question this feature turned on: `sender` is the
// account itself and `payer` is the FAUCET, so an account signs its own
// creation with its Face ID key and pays nothing. No ordinary wallet anywhere.
let cCode = hx("0x7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc54801561002c57610043565b5073813035e3fc4a102ce2b4a73d78a25d1ea5afadef5b363d3d373d3d3d363d855af43d82803e903d91605b57fd5bf3")
let cSalt = hx("0x64c0ad5c8013ab8acbb9a30b4058a93ae34b9637cfbcdd71093eb436d8636d60")
let cActorID = hx("0x8fa4f35fb50332c07b5eacfb7c79f0e0c2fa9976c2fd992367ba43b46052f85d")
let creation = VibenetTransaction.Fields(
    chainID: 84_538_453,
    sender: hx("0x4a408a2a4dcdb313a0b5baa79f1067f6171106c4"),
    nonceSequence: 0,
    maxPriorityFeePerGas: 0xf4240, maxFeePerGas: 0x3b9aca00, gasLimit: 227_000,
    accountChanges: [.create(.init(userSalt: cSalt, code: cCode,
        initialActors: [.init(actorID: cActorID,
                              authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
                              scope: 0, policyData: Data())]))],
    calls: [[.init(to: hx("0xb88341910b9b396a5c5d92d17e868c5326c127b6"), data: Data())]],
    metadata: hx("0x53706f6e736f726564207472616e73616374696f6e"),
    payer: hx("0xfedbf7fb9716409586bcc74175b2704bdf919ef0"))
let cPre = VibenetTransaction.senderSigningPreimage(creation)
print("CREATEPRE=" + cPre.map { String(format: "%02x", $0) }.joined())
// The account's OWN first actor id is keccak(x|y) of the key that signed it —
// the same derivation, seen in real data rather than in a probe.
check("the creation's actorId is keccak(x|y) of its signer",
      VibenetP256Auth.actorID(publicKeyXY:
        hx("0x24f65a4ae084d179defd8ea06a058f29f2861a3b4b7d318d05ae7b8f40f4f140")
        + hx("0xda708b03652812ccfef684df4f135a48c74dd61d8095b56db2b897fe2de33717")) == cActorID)
check("a sponsored creation names a payer", !creation.payer.isEmpty)

// --- THE BROADCAST ENVELOPE -------------------------------------------------
// Its field ORDER is spec-derived rather than recovery-proven (the two auth
// fields are excluded from the hash by definition, so nothing can recover
// them, and this node 403s every raw-transaction read). What IS asserted is
// the relationship that must hold either way: the broadcast bytes are the
// signing bytes with exactly two fields appended, so the two encoders can
// never disagree about the thirteen they share.
let rawAuth = Data(repeating: 0xAB, count: 149)
let raw = VibenetTransaction.encoded(creation, senderAuth: rawAuth)
check("broadcast leads with the same type byte", raw.first == 0x79)
check("broadcast is longer than the signing preimage", raw.count > cPre.count)
check("broadcast carries the signature", raw.range(of: rawAuth) != nil)
// An unsponsored transaction still emits an EMPTY payer_auth rather than
// dropping the field — a 15-element list with one empty string is not the same
// RLP as a 14-element list, and the node counts.
let noPayer = VibenetTransaction.encoded(creation, senderAuth: rawAuth, payerAuth: Data())
let withPayer = VibenetTransaction.encoded(creation, senderAuth: rawAuth,
                                           payerAuth: Data(repeating: 0xCD, count: 65))
check("payer_auth is always present, empty when unsponsored", noPayer != withPayer)
check("a sponsored envelope carries the payer signature",
      withPayer.range(of: Data(repeating: 0xCD, count: 65)) != nil)

// --- WHERE A NEW ACCOUNT WILL LIVE -----------------------------------------
// The creation fixture's own parameters must reproduce its own address. This
// is the strongest form available for this function: the address is not ours,
// it is what the chain assigned, and it is signed over — so a wrong derivation
// is not a wrong guess, it is a signature over a different transaction.
let KEYSTORE = hx("0x813011b7a5f25f8433ac1e0993de06cb2d1500ac")
let creationActor = VibenetTransaction.InitialActor(
    actorID: cActorID, authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
    scope: 0, policyData: Data())
check("the creation's own address is reproduced",
      VibenetAddress.derive(keystore: KEYSTORE, userSalt: cSalt, code: cCode,
                            initialActors: [creationActor])
      == hx("0x4a408a2a4dcdb313a0b5baa79f1067f6171106c4"))
// THE DECOY. `AccountCreated`'s second word is keccak(code), which looks
// exactly like the init-code hash CREATE2 wants and is the wrong value — the
// header must be prepended. If this stops differing, the header was dropped.
check("the deployment header is 14 bytes",
      VibenetAddress.deploymentHeader(codeLength: 93)?.count == 14)
check("the header encodes the length twice, big-endian",
      VibenetAddress.deploymentHeader(codeLength: 93)
      == hx("0x61005d600e60003961005d6000f3"))
check("an empty body has no header", VibenetAddress.deploymentHeader(codeLength: 0) == nil)
check("a body over 64KB has no header", VibenetAddress.deploymentHeader(codeLength: 0x10000) == nil)
// SCOPE IS TWO BYTES. Proven against the Keystore's own computeAddress; a
// one-byte encoding produces a different, valid-looking address.
check("scope is two bytes inside the leaf",
      VibenetAddress.leaf(creationActor)?.count == 32)
check("an out-of-range scope is refused",
      VibenetAddress.leaf(VibenetTransaction.InitialActor(
        actorID: cActorID, authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
        scope: 70_000, policyData: Data())) == nil)
// ORDER MATTERS, so the derivation sorts rather than trusting its caller.
let a1 = VibenetTransaction.InitialActor(actorID: hx("0x" + String(repeating: "11", count: 32)),
    authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"), scope: 0, policyData: Data())
let a2 = VibenetTransaction.InitialActor(actorID: hx("0x" + String(repeating: "22", count: 32)),
    authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"), scope: 0, policyData: Data())
check("actor order does not change the address",
      VibenetAddress.derive(keystore: KEYSTORE, userSalt: cSalt, code: cCode, initialActors: [a1, a2])
      == VibenetAddress.derive(keystore: KEYSTORE, userSalt: cSalt, code: cCode, initialActors: [a2, a1]))
check("a different salt is a different account",
      VibenetAddress.derive(keystore: KEYSTORE, userSalt: Data(repeating: 9, count: 32),
                            code: cCode, initialActors: [creationActor])
      != hx("0x4a408a2a4dcdb313a0b5baa79f1067f6171106c4"))
check("no actors, no address",
      VibenetAddress.derive(keystore: KEYSTORE, userSalt: cSalt, code: cCode, initialActors: []) == nil)

// --- THE COMPOSER, AGAINST THE SAME REAL CREATION ---------------------------
// `plan()` takes an intent and produces the address, the actor id and the bytes
// to sign. Asserted against tx 0xee57134d…: same address, same actorId, and the
// preimage is checked below by verifying that creation's REAL P-256 signature
// against it. Nothing about that signature is ours, so this cannot pass by
// construction.
let planned = VibenetCreate.plan(
    keystore: KEYSTORE,
    defaultAccount: hx("0x813035e3fc4a102ce2b4a73d78a25d1ea5afadef"),
    authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
    publicKeyXY: hx("0x24f65a4ae084d179defd8ea06a058f29f2861a3b4b7d318d05ae7b8f40f4f140")
               + hx("0xda708b03652812ccfef684df4f135a48c74dd61d8095b56db2b897fe2de33717"),
    userSalt: cSalt, nonceSequence: 0, gasLimit: 227_000,
    maxFeePerGas: 0x3b9aca00, maxPriorityFeePerGas: 0xf4240,
    calls: [[.init(to: hx("0xb88341910b9b396a5c5d92d17e868c5326c127b6"), data: Data())]],
    payer: hx("0xfedbf7fb9716409586bcc74175b2704bdf919ef0"),
    metadata: hx("0x53706f6e736f726564207472616e73616374696f6e"))
check("plan() reproduces the real account address",
      planned?.address == hx("0x4a408a2a4dcdb313a0b5baa79f1067f6171106c4"))
check("plan() reproduces the real actor id", planned?.actorID == cActorID)
check("plan() reproduces the real signing preimage", planned?.preimage == cPre)
// The proxy body is 93 bytes with the target spliced in — NOT the canonical
// 45-byte minimal proxy, which would give a different init-code hash and a
// different address.
check("the proxy body is 93 bytes",
      VibenetCreate.proxyCode(forAccount: hx("0x813035e3fc4a102ce2b4a73d78a25d1ea5afadef"))?.count == 93)
check("the proxy body is the real one",
      VibenetCreate.proxyCode(forAccount: hx("0x813035e3fc4a102ce2b4a73d78a25d1ea5afadef")) == cCode)
check("a short target has no proxy body",
      VibenetCreate.proxyCode(forAccount: Data(repeating: 1, count: 19)) == nil)
// Length guards: a short key or salt must be refused rather than padded into a
// perfectly valid signature over an account nobody asked for.
check("a short key is refused",
      VibenetCreate.plan(keystore: KEYSTORE, defaultAccount: hx("0x813035e3fc4a102ce2b4a73d78a25d1ea5afadef"),
        authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
        publicKeyXY: Data(repeating: 1, count: 63), userSalt: cSalt,
        gasLimit: 1, maxFeePerGas: 1, maxPriorityFeePerGas: 1) == nil)
check("a short salt is refused",
      VibenetCreate.plan(keystore: KEYSTORE, defaultAccount: hx("0x813035e3fc4a102ce2b4a73d78a25d1ea5afadef"),
        authenticator: hx("0x8130c89f65750431b564a4730397552a11cea256"),
        publicKeyXY: Data(repeating: 1, count: 64), userSalt: Data(repeating: 2, count: 31),
        gasLimit: 1, maxFeePerGas: 1, maxPriorityFeePerGas: 1) == nil)
// The address is SIGNED OVER, so it must be the one in `sender`.
check("the derived address is what gets signed as sender",
      planned?.fields.sender == planned?.address)

let pre = VibenetTransaction.senderSigningPreimage(fields)
check("preimage is the proven 613 bytes", pre.count == 613)
check("preimage leads with the type byte", pre.first == 0x79)
// THE VECTOR CANNOT SEE `payer`, because the transaction it was taken from was
// not sponsored — so dropping the field is a no-op against it and the mutation
// survived. Asserted structurally instead: two Fields differing ONLY in payer
// must not produce the same bytes to sign. Sponsorship is the whole reason
// that field exists, and a signature blind to WHO PAYS is one somebody else
// can re-point.
var sponsored = fields
sponsored.payer = hx("0x00000000000000000000000000000000000000aa")
check("payer changes what gets signed",
      VibenetTransaction.senderSigningPreimage(sponsored) != pre)
check("sender changes what gets signed",
      VibenetTransaction.senderSigningPreimage({ var f = fields; f.sender = hx("0x00000000000000000000000000000000000000bb"); return f }()) != pre)
print("PREIMAGE=" + pre.map { String(format: "%02x", $0) }.joined())
if fails == 0 { print("  ok") } else { exit(1) }
SWIFT
swiftc -O -o "$WORK/txrun" "$WORK/VibenetTransaction.swift" "$WORK/Keccak256.swift" "$WORK/VibenetCreate.swift" "$WORK/VibenetSigner.swift" "$WORK/txmain/main.swift" 2>"$WORK/tx.log" || {
  echo "✗ VibenetTransaction.swift did not compile standalone (it must stay Foundation-only)"
  head -20 "$WORK/tx.log"; exit 1; }
echo "vibenet transaction:"
"$WORK/txrun" > "$WORK/tx.out" || { grep '✗' "$WORK/tx.out"; exit 1; }
grep -v '^PREIMAGE=' "$WORK/tx.out"
# The hash itself — computed here rather than in Swift, so the fixture is
# checked by a DIFFERENT keccak than the app would use.
python3 - "$WORK/tx.out" <<'HASH' || exit 1
import sys, sha3
line = [l for l in open(sys.argv[1]) if l.startswith("PREIMAGE=")][0].strip()[9:]
k = sha3.keccak_256(); k.update(bytes.fromhex(line))
want = "96c32d8901d632f6b97b4c79300d46b5daba7667de24724da15de0cbd85f4ca9"
if k.hexdigest() != want:
    print(f"  ✗ signing hash is 0x{k.hexdigest()}, the PROVEN one is 0x{want}")
    sys.exit(1)
print("  ✓ signing hash matches the vector proven against the chain")
HASH

# The creation fixture is checked by VERIFYING A REAL P-256 SIGNATURE against
# the hash our encoder produces. Nothing about that signature is ours, so this
# cannot pass by construction — it passes only if every byte agrees.
python3 - "$WORK/tx.out" <<'CREATE' || exit 1
import sys, sha3
try:
    from cryptography.hazmat.primitives.asymmetric import ec, utils as asu
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.backends import default_backend
except ImportError:
    print("  · creation check SKIPPED (no `cryptography` module) — install it to re-prove")
    sys.exit(0)
line = [l for l in open(sys.argv[1]) if l.startswith("CREATEPRE=")][0].strip()[10:]
k = sha3.keccak_256(); k.update(bytes.fromhex(line)); digest = k.digest()
R = 0x7a78b8c5ee7278d3e6812ebf2a4477bca7f0c2a1abd075ceafcc990ba383f83b
S = 0x62623ad1059cbe29ae29cda1fc6c910dce18ce267eb9c16650710e8040550dce
X = 0x24f65a4ae084d179defd8ea06a058f29f2861a3b4b7d318d05ae7b8f40f4f140
Y = 0xda708b03652812ccfef684df4f135a48c74dd61d8095b56db2b897fe2de33717
pub = ec.EllipticCurvePublicNumbers(X, Y, ec.SECP256R1()).public_key(default_backend())
try:
    pub.verify(asu.encode_dss_signature(R, S), digest,
               ec.ECDSA(asu.Prehashed(hashes.SHA256())))
except Exception:
    print("  ✗ a REAL on-chain P-256 signature no longer verifies against our signing hash")
    sys.exit(1)
print("  ✓ a real on-chain P-256 creation still verifies against our signing hash")
CREATE

# A SECOND mutator, named for the file it copies. The sibling harness earned
# this the hard way: mutations written against a function that copies a
# DIFFERENT file all report ANCHOR-MISSING, which reads as "the shipped source
# moved" when the source is exactly where it was left. Naming the file in the
# function name makes that mistake unmakeable — and it just caught two of mine.
createmutate() {
  local label="$1" from="$2" to="$3"
  cp Casberi/Casberi/Model/VibenetCreate.swift "$WORK/VibenetCreate.swift"
  cp "$TXFILE" "$WORK/VibenetTransaction.swift"
  if ! grep -qF -- "$from" "$WORK/VibenetCreate.swift"; then
    echo "  ✗ STALE MUTATION '$label' — pattern not found in VibenetCreate.swift"
    return 1
  fi
  python3 - "$WORK/VibenetCreate.swift" "$from" "$to" <<'PYC'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PYC
  if swiftc -O -o "$WORK/cm" "$WORK/VibenetTransaction.swift" "$WORK/Keccak256.swift" \
       "$WORK/VibenetCreate.swift" "$WORK/VibenetSigner.swift" "$WORK/txmain/main.swift" 2>/dev/null \
     && "$WORK/cm" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $label"; return 1
  fi
  echo "  ✓ caught: $label"; return 0
}

echo "transaction mutations:"
TXMUT=0
txmutate() {
  local label="$1" from="$2" to="$3"
  cp "$TXFILE" "$WORK/VibenetTransaction.swift"
  grep -qF -- "$from" "$WORK/VibenetTransaction.swift" \
    || { echo "  ✗ STALE MUTATION '$label' — pattern not found"; return 1; }
  python3 - "$WORK/VibenetTransaction.swift" "$from" "$to" <<'PY2'
import sys, io
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY2
  if swiftc -O -o "$WORK/txm" "$WORK/VibenetTransaction.swift" "$WORK/Keccak256.swift" "$WORK/VibenetCreate.swift" "$WORK/VibenetSigner.swift" "$WORK/txmain/main.swift" 2>/dev/null \
     && "$WORK/txm" > "$WORK/m.out" 2>/dev/null \
     && python3 - "$WORK/m.out" <<'H2' >/dev/null 2>&1
import sys, sha3
line = [l for l in open(sys.argv[1]) if l.startswith("PREIMAGE=")][0].strip()[9:]
k = sha3.keccak_256(); k.update(bytes.fromhex(line))
sys.exit(0 if k.hexdigest() == "96c32d8901d632f6b97b4c79300d46b5daba7667de24724da15de0cbd85f4ca9" else 1)
H2
  then
    echo "  ✗ MUTATION SURVIVED: $label"; return 1
  fi
  echo "  ✓ caught: $label"; return 0
}
# Zero encoded as 0x00 instead of empty — the classic, and it changes the hash.
txmutate "zero encoded as 0x00"     'guard value != 0 else { return Data() }' \
                                    'guard value != 1 else { return Data() }' || TXMUT=1
# The type byte.
txmutate "type byte changed"        'static let txType: UInt8 = 0x79' \
                                    'static let txType: UInt8 = 0x78' || TXMUT=1
# Field ORDER — a swap that still compiles and still produces a valid signature.
txmutate "fee fields swapped"       '.bytes(quantity(f.maxPriorityFeePerGas)),
         .bytes(quantity(f.maxFeePerGas)),' \
                                    '.bytes(quantity(f.maxFeePerGas)),
         .bytes(quantity(f.maxPriorityFeePerGas)),' || TXMUT=1
# The auth fields must stay OUT of the sender hash.
txmutate "payer dropped from the body" '.bytes(f.payer)]' '.bytes(Data())]' || TXMUT=1
# calls flattened — one of the sixteen candidates the proof rejected.
txmutate "calls flattened"          '.list(f.calls.map { phase in Item.list(phase.map(\.item)) })' \
                                    '.list(f.calls.flatMap { $0 }.map(\.item))' || TXMUT=1
# The measured per-change tag.
txmutate "AuthorizeActor tag moved"  'Change(tag: 0x00, payload: payload)' \
                                     'Change(tag: 0x01, payload: payload)' || TXMUT=1
# The measured channel.
txmutate "channel is no longer Local" 'var channel: UInt64 = 0' 'var channel: UInt64 = 1' || TXMUT=1
# The config-change entry tag.
txmutate "entry tag moved"           '.list([.bytes(quantity(0x01)), .bytes(quantity(channel)),' \
                                     '.list([.bytes(quantity(0x02)), .bytes(quantity(channel)),' || TXMUT=1
# RLP long-form boundary.
txmutate "RLP short/long boundary"   'if length < 56 { return Data([offset + UInt8(length)]) }' \
                                     'if length < 57 { return Data([offset + UInt8(length)]) }' || TXMUT=1
txmutate "P-256 order transposed"    'return r + s + publicKeyXY + Data([padByte])' \
                                     'return publicKeyXY + r + s + Data([padByte])' || TXMUT=1
txmutate "P-256 length no longer 129" 'return r + s + publicKeyXY + Data([padByte])' \
                                      'return r + s + publicKeyXY' || TXMUT=1
txmutate "actorId takes the 0x04 tag" 'return Data(Keccak256.hash([UInt8](publicKeyXY)))' \
                                      'return Data(Keccak256.hash([UInt8](Data([4]) + publicKeyXY)))' || TXMUT=1
txmutate "short key accepted"        'guard r.count == 32, s.count == 32, publicKeyXY.count == 64 else { return nil }' \
                                     'guard r.count == 32, s.count == 32 else { return nil }' || TXMUT=1
# The two encoders must keep sharing one body — a second copy of the field
# order is how a broadcast starts describing a different transaction than the
# one that was signed.
txmutate "broadcast stops reusing signingBody" 'Data([txType]) + encode(.list(signingBody(f)
                                      + [.bytes(senderAuth), .bytes(payerAuth)]))' \
                                     'Data([txType]) + encode(.list([.bytes(senderAuth), .bytes(payerAuth)]))' || TXMUT=1
# THE DECOY, as a mutation: keccak(code) is right there in the event and is the
# wrong init-code hash.
txmutate "init-code hash drops the header" 'let initCodeHash = Data(Keccak256.hash([UInt8](header + code)))' \
                                     'let initCodeHash = Data(Keccak256.hash([UInt8](code)))' || TXMUT=1
txmutate "scope encoded in one byte"  'Data([UInt8(scope >> 8), UInt8(scope & 0xff)])' \
                                      'Data([UInt8(scope & 0xff)])' || TXMUT=1
txmutate "actors no longer sorted"    'initialActors.sorted(by: { $0.actorID.lexicographicallyPrecedes($1.actorID) })' \
                                      'initialActors' || TXMUT=1
txmutate "leaves not double-hashed"   'let commitment = Data(Keccak256.hash([UInt8](leaves)))' \
                                      'let commitment = leaves' || TXMUT=1
txmutate "salt not folded with actors" 'let effectiveSalt = Data(Keccak256.hash([UInt8](userSalt + commitment)))' \
                                       'let effectiveSalt = userSalt' || TXMUT=1
# The composer must not invent what the transaction DOES — `calls` is signed
# over, so a fabricated entry is a signature over a transaction nobody asked
# for. (A first draft assumed a call to the new account itself; the real
# creations target something else entirely.)
createmutate "composer invents a call"   'calls: calls,' 'calls: [[.init(to: address, data: Data())]],' || TXMUT=1
createmutate "composer skips the derived sender" 'sender: address,' 'sender: Data(),' || TXMUT=1
createmutate "proxy body drops the target" 'return prologue + target + epilogue' 'return prologue + epilogue' || TXMUT=1
# NOT A MUTATION HERE, on purpose. `plan`'s three length guards are EARLY
# EXITS, not the protection: removing them survives, because
# `VibenetP256Auth.actorID` re-checks the key, `VibenetAddress.derive` the salt
# and `VibenetAddress.leaf` the authenticator, so every bad length still yields
# nil. Measured by writing the mutation and watching it live. Keeping a
# mutation that cannot fail would claim coverage this file does not have —
# the guards below are what actually hold.
[[ $TXMUT -eq 0 ]] || exit 1


echo "✓ vibenet signer self-test passed"
