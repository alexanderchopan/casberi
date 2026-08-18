#!/bin/zsh
# Casberi Altana keystore self-test — the ROOM HEAD and the WITNESSED date
# decoder (2026-08-18, prd §403).
#
#   Casberi/Casberi/Model/AltanaKeystore.swift  — the model (also compiled by
#                                                 wallet-viz-selftest.sh, which
#                                                 owns the ABI-decode cases)
#   Casberi/Casberi/Model/AltanaRoom.swift      — the head
#
# Both are compiled WHOLE and unmodified — they are Foundation-only by design
# for exactly this reason. The `*Source.swift` halves are not compiled here;
# they need SwiftData and the network.
#
# WHY A HARNESS AND NOT A DEVICE CHECK: nothing on this host can register a
# key, revoke one, or make a grant expire. There are 39 keys on Earth and we
# own none of them. So every reading this room makes is unverifiable by running
# the app, and every failure renders perfectly — a session key shown as a root
# credential, a runway drawn from a date we never confirmed, a card that
# reshuffles between opens. This is the only proof these numbers are right.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="Casberi/Casberi/Model/AltanaKeystore.swift"
ROOM="Casberi/Casberi/Model/AltanaRoom.swift"
SHEET="Casberi/Casberi/Model/AltanaKeySheet.swift"
SOURCE="Casberi/Casberi/Model/AltanaKeystoreSource.swift"
for f in "$MODEL" "$ROOM" "$SHEET" "$SOURCE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- conduct guard: read-only, mechanically -------------------------------
# The seat's whole claim is that it reads and never signs. The pure file NAMES
# every write selector (in `writeSelectors`, and in prose explaining the
# refusal), so the guard is pointed at the SOURCE file — and reads it
# COMMENT-STRIPPED, because that file documents the rule by naming what it must
# not do. Grepping raw source fires on the prose explaining the guard: the
# Obsidian/Cursor lesson, which this project has now paid for five times.
CODE=$(sed 's://.*::' "$SOURCE" | sed '/^[[:space:]]*\/\/\//d')
for sel in 0xa5c2bd05 0x96295a64 0x3cf26a01 0xd7e54cad 0xf2fa7392 0x5ed1e59a; do
  print -r -- "$CODE" | grep -q "$sel" && {
    echo "✗ $SOURCE builds a WRITE selector ($sel) — the catalog copy's"
    echo "  'never registers, revokes, or signs' is now false. Change both, or"
    echo "  don't make the call."; exit 1; }
done
for verb in eth_sendTransaction eth_sendRawTransaction eth_signTypedData personal_sign; do
  print -r -- "$CODE" | grep -q "$verb" && { echo "✗ $SOURCE issues $verb — §112 says nothing here signs"; exit 1; }
done

# --- drift guards ----------------------------------------------------------
# The witness words. These are an INFERRED struct layout, confirmed against
# four real keys — the whole safety of `registeredAt` is that word 7 must equal
# the authoritative `getExpiry`. If either index moves without the fixtures
# below moving too, this harness would certify a date read from the wrong word.
grep -q 'static let registeredAtWord = 5' "$MODEL" \
  || { echo "✗ registeredAtWord moved — re-measure getKey against a real key before trusting $0"; exit 1; }
grep -q 'static let expiryWitnessWord = 7' "$MODEL" \
  || { echo "✗ expiryWitnessWord moved — the layout would no longer be witnessed"; exit 1; }
# The head composes from the stored snapshot, never a live read. If it ever
# calls the chain, every room draw costs an eth_call.
CARDCODE=$(sed 's://.*::' "Casberi/Casberi/Model/AltanaRoomSource.swift" | sed '/^[[:space:]]*\/\/\//d')
print -r -- "$CARDCODE" | grep -q 'AltanaKeystore.call\|eth_call' && {
  echo "✗ the room head reaches the chain — it must compose from AltanaState only"; exit 1; }

TMP=$(mktemp -d /tmp/altana-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
# MUST be named main.swift — with several files on the command line, only
# main.swift's top-level code runs. Named anything else the driver is compiled
# and never executed, and the run exits 0 having asserted nothing.
DRIVER="$TMP/main.swift"

cat > "$DRIVER" <<'SWIFT'
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if !ok { failures += 1; print("  ✗ \(what)") }
}

typealias AK = AltanaKeystore

func w(_ v: Int) -> String {
    let s = String(v, radix: 16)
    return String(repeating: "0", count: 64 - s.count) + s
}
func kid(_ n: Int) -> String { w(n) }

// ===========================================================================
// The witnessed registration date
//
// This is the sharpest thing in the file. The struct layout is INFERRED, and
// the failure mode of guessing one is a confident wrong date on a security
// screen — a key registered last week rendering as 1970, with nothing about
// it looking broken. So the layout is not trusted, it is WITNESSED.
// ===========================================================================
print("AltanaKeystore.registeredAt")

/// A getKey reply shaped like the real ones measured on BNB.
func getKeyReply(registered: Int, expiry: Int) -> String {
    var words = [String](repeating: w(0), count: 14)
    words[0] = w(32)
    words[AK.registeredAtWord] = w(registered)
    words[AK.expiryWitnessWord] = w(expiry)
    words[9] = w(65)
    return "0x" + words.joined()
}

// Measured real values from BNB, 2026-08-18: a root key registered
// 2026-08-11 05:03 UTC with no expiry, and a 24-hour session key.
let rootReg = 1_786_424_584
let sessReg = 1_786_507_440, sessExp = 1_786_593_840

check(AK.registeredAt(fromGetKey: getKeyReply(registered: rootReg, expiry: 0), expectedExpiry: 0)
        == Date(timeIntervalSince1970: TimeInterval(rootReg)),
      "a root key's registration decodes when the witness (expiry 0) matches")
check(AK.registeredAt(fromGetKey: getKeyReply(registered: sessReg, expiry: sessExp), expectedExpiry: sessExp)
        == Date(timeIntervalSince1970: TimeInterval(sessReg)),
      "a session key's registration decodes when the witness matches its expiry")

// THE GUARD ITSELF. If the struct ever gains, loses or reorders a field, word 7
// stops equalling the authoritative expiry and we must return nil rather than
// hand back whatever word 5 now holds.
check(AK.registeredAt(fromGetKey: getKeyReply(registered: sessReg, expiry: sessExp), expectedExpiry: 999) == nil,
      "WITNESS MISMATCH RETURNS NIL — a shifted layout costs a date, never invents one")
check(AK.registeredAt(fromGetKey: getKeyReply(registered: rootReg, expiry: 0), expectedExpiry: 12345) == nil,
      "…including when the reply says 'never' and the authority says otherwise")

// A zero registration is "not recorded", not 1970.
check(AK.registeredAt(fromGetKey: getKeyReply(registered: 0, expiry: 0), expectedExpiry: 0) == nil,
      "a zero registration is refused, never rendered as 1970")
// A date before the contract existed is the right word read from a wrong buffer.
check(AK.registeredAt(fromGetKey: getKeyReply(registered: 1_500_000_000, expiry: 0), expectedExpiry: 0) == nil,
      "a pre-2026 registration is refused — the keystore did not exist yet")
check(AK.earliestPlausibleRegistration > 1_767_000_000,
      "…and the floor really is 2026, not an epoch-shaped constant")
check(AK.registeredAt(fromGetKey: "0x", expectedExpiry: 0) == nil, "a revert decodes to nil")
check(AK.registeredAt(fromGetKey: "0x" + w(32) + w(0), expectedExpiry: 0) == nil,
      "a reply too short to hold the witness word is refused")

// ===========================================================================
// The registry table — the correction that cost this seat its first cut
// ===========================================================================
print("AltanaKeystore.registries")

check(AK.registries.count == 2, "both registries are present")
check(AK.registries.first?.label == "BNB Smart Chain",
      "BNB LEADS — 38 of the 39 keys that exist are there, and a wallet with "
      + "nothing anywhere should fail fast on the busy chain first")
check(AK.registries.allSatisfy { !$0.hosts.isEmpty }, "every registry has at least one host")
check(AK.registries.allSatisfy { $0.contract == $0.contract.lowercased() },
      "contracts are lowercased — they are compared against RPC replies")
check(Set(AK.registries.map(\.label)).count == AK.registries.count,
      "no two registries share a label, which the row's chain tag reads")

// ===========================================================================
// Key readings
// ===========================================================================
print("AltanaKeystore.Key")

let now = Date(timeIntervalSince1970: 1_787_083_931)   // measured "now", 2026-08-18
func key(_ n: Int, root: Bool, reg: Int?, exp: Int?) -> AK.Key {
    AK.Key(id: "0x" + kid(n), isRoot: root,
           expiry: exp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
           signatureCount: 0, publicKey: nil,
           registeredAt: reg.map { Date(timeIntervalSince1970: TimeInterval($0)) },
           chainLabel: "BNB Smart Chain")
}

// A real 24-hour grant, measured shape.
let day = key(1, root: false, reg: sessReg, exp: sessExp)
check(day.grantDuration == 86_400, "a 24-hour grant measures 86,400 seconds")
check(AltanaRoom.grantPhrase(seconds: 86_400) == "24-hour key",
      "…and is NAMED as a 24-hour key, not '1-day key'")
check(AltanaRoom.grantPhrase(seconds: 86_400 * 30) == "30-day key", "a month-long grant is a 30-day key")
check(AltanaRoom.grantPhrase(seconds: 3_600) == "1-hour key", "an hour-long grant is an hour key")
check(AltanaRoom.grantPhrase(seconds: 90 * 60) == "90-minute key", "…and 90 minutes is not rounded to 2 hours")
check(AltanaRoom.grantPhrase(seconds: 0) == nil, "a zero grant has no phrase")
// The refusal to print "1.02-day key" for a grant plainly written as a day.
// Asserted against the exact phrase, not `contains("day")` — a one-day grant
// is spelled "24-hour key", so the looser check was testing nothing and failed
// for the right reason on its first run.
check(AltanaRoom.grantPhrase(seconds: 86_400 + 600) == "24-hour key",
      "a grant a few minutes off a whole day is still named as the day it plainly is")
check(AltanaRoom.grantPhrase(seconds: 86_400 * 30 + 900) == "30-day key",
      "…and the same holds for a month-long grant with drift on it")

// A key with no witnessed registration has no runway. The bar is a claim about
// elapsed time and must not be drawn from a date we never confirmed.
let undated = key(2, root: false, reg: nil, exp: sessExp)
check(undated.grantDuration == nil, "no registration, no grant duration")
check(undated.progress(now: now) == nil, "NO RUNWAY without a witnessed start")

// Progress is clamped and real.
let half = key(3, root: false,
               reg: Int(now.timeIntervalSince1970) - 3600,
               exp: Int(now.timeIntervalSince1970) + 3600)
if let p = half.progress(now: now) {
    check(abs(p - 0.5) < 0.01, "halfway through a grant reads as 0.5")
} else { check(false, "halfway through a grant reads as 0.5") }
let over = key(4, root: false, reg: sessReg, exp: sessExp)
check(over.progress(now: now) == 1.0, "a finished grant clamps to 1, never past it")

// Expired-but-listed: the hygiene finding, and it is REAL — two of six session
// keys sampled on BNB are in this state today.
check(over.isExpiredButListed(now: now), "a session key past its expiry is expired-but-listed")
check(!over.isUsable(now: now), "…and cannot act")
let root = key(5, root: true, reg: rootReg, exp: nil)
check(!root.isExpiredButListed(now: now), "a key with no expiry is never expired")
check(root.isUsable(now: now), "…and is always usable")

// ===========================================================================
// The room head
// ===========================================================================
print("AltanaRoom")

func reading(_ address: String, _ keys: [AK.Key]) -> AK.Reading {
    AK.Reading(address: address, keys: keys, truncated: false)
}

check(AltanaRoom.compose(readings: [], now: now) == nil, "nothing watched, no card")
check(AltanaRoom.compose(readings: [reading("0xa", [])], now: now) == nil, "no keys, no card")
check(AltanaRoom.compose(readings: [reading("0xa", [root])], now: now) == nil,
      "a lone root key is under the floor — the account merely existing is what the rows already say")

let live = key(6, root: false, reg: Int(now.timeIntervalSince1970) - 3600,
               exp: Int(now.timeIntervalSince1970) + 86_400)
guard let card = AltanaRoom.compose(readings: [reading("0xa", [root, live, over])], now: now) else {
    print("  ✗ a real account composes a card"); exit(1)
}
check(card.usableCount == 2, "usable counts the root and the live session, not the expired one")
check(card.rootCount == 1, "one root")
check(card.staleCount == 1, "one expired-but-listed key")
check(card.sessions.count == 2, "both sessions are drawn, expired included")
check(card.staleNote?.contains("1 key") == true, "the tidy-up line names the count")
check(card.rootLine?.contains("registered") == true, "the root line dates the account when witnessed")
check(card.chains == ["BNB Smart Chain"], "chains are listed, in first-appearance order")
check(card.otherWallets == 0, "one wallet, no others note")
check(card.otherWalletsNote == nil, "…and the note is silent rather than saying zero")

// A root key with no witnessed date states the count and NOT a date.
guard let undatedCard = AltanaRoom.compose(
        readings: [reading("0xa", [key(7, root: true, reg: nil, exp: nil), live])], now: now) else {
    print("  ✗ an undated root still composes"); exit(1)
}
check(undatedCard.rootLine?.contains("registered") == false,
      "NO DATE when it wasn't witnessed — 'registered today' must never stand in for 'we don't know'")

// Headline arithmetic.
check(card.headline.contains("2"), "the headline states how many keys can sign")
guard let noneCard = AltanaRoom.compose(readings: [reading("0xa", [over, key(8, root: false, reg: sessReg, exp: sessExp)])],
                                        now: now) else {
    print("  ✗ an all-expired account still composes"); exit(1)
}
check(noneCard.usableCount == 0, "every key expired means none can sign")
check(noneCard.headline.contains("No key"), "…and the headline says so plainly")

// RANKING is total — a head that reshuffles between opens over identical data
// reads as broken (the ASCRoom ruling).
let soonest = key(9, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) + 100)
let later   = key(10, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) + 100_000)
let a = reading("0xaaa", [root, soonest])
let b = reading("0xbbb", [root, later])
check(AltanaRoom.compose(readings: [a, b], now: now)?.address == "0xaaa",
      "the soonest deadline leads")
check(AltanaRoom.compose(readings: [b, a], now: now)?.address == "0xaaa",
      "…in either input order — the ranking is total")
check(AltanaRoom.compose(readings: [a, b], now: now)?.otherWallets == 1,
      "the other wallet with keys is counted, never dropped in silence")

// A wallet with NO live deadline never outranks one that has one, however many
// keys it holds — trouble with a clock first.
let many = reading("0xccc", [root, over, key(11, root: true, reg: rootReg, exp: nil),
                             key(12, root: true, reg: rootReg, exp: nil)])
check(AltanaRoom.compose(readings: [many, a], now: now)?.address == "0xaaa",
      "a live deadline outranks a bigger pile with no clock in it")

// ===========================================================================
// The curve — what KIND of credential this is (prd §404)
//
// The point below is REAL: measured off BNB 2026-08-18 and reassembled from
// the getKey words. It lies on secp256k1, verified independently in Python
// before this test existed. So this asserts the shipped detector against
// ground truth, not against itself.
// ===========================================================================
print("AltanaKeystore.curve")

let realKey = "04a376e7011da0888af6a46b1803c93760db185736229fbcf96d2c9750f9e3eacb"
            + "021abf6eeffcd4f7645c343e2d43c3dc5e2a352ee7ab15c7b8f16649531ba940"
check(AK.curve(fromPublicKey: realKey) == .secp256k1,
      "the one real key on the network is secp256k1 — a WALLET key, not a passkey")
check(AK.Curve.secp256k1.label == "Wallet key", "…and it is named in a word people know")
check(AK.Curve.p256.label == "Passkey", "P-256 is the passkey curve")
check(AK.Curve.unknown.label == nil,
      "an unrecognised curve says NOTHING — naming it anyway is the §83 line here")

// A real P-256 point: the NIST P-256 generator, whose coordinates are public
// and fixed. If the detector mixed the two equations up, this would come back
// secp256k1 and every passkey would be labelled a wallet key.
let p256Generator = "04"
  + "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
  + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
check(AK.curve(fromPublicKey: p256Generator) == .p256,
      "the P-256 generator is identified as P-256, not as secp256k1")

// The secp256k1 generator, likewise.
let k1Generator = "04"
  + "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
  + "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"
check(AK.curve(fromPublicKey: k1Generator) == .secp256k1,
      "the secp256k1 generator is identified as secp256k1")

// Junk, and near-misses, all refuse.
check(AK.curve(fromPublicKey: "04" + String(repeating: "11", count: 64)) == .unknown,
      "a point on neither curve is unknown")
// A VALID secp256k1 point wearing the wrong prefix. The earlier fixture used
// 64 bytes of junk, which is refused by the curve equation whether or not the
// prefix is checked — so it proved nothing about the prefix guard and the
// mutation survived. This one is on the curve, so only the prefix can reject it.
check(AK.curve(fromPublicKey: "03"
      + "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
      + "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8") == .unknown,
      "a COMPRESSED prefix is refused even on a point that IS on the curve")
check(AK.curve(fromPublicKey: "03" + String(repeating: "aa", count: 64)) == .unknown,
      "…and junk with a compressed prefix likewise")
check(AK.curve(fromPublicKey: "04ff") == .unknown, "a short key is refused")
check(AK.curve(fromPublicKey: "") == .unknown, "an empty key is refused")
// A coordinate at or above the field prime is not on the curve, whatever it
// reduces to.
// X = p + 1, which is >= the field prime but REDUCES to x = 1 — a real point
// on the curve, with a Y that genuinely satisfies the equation after
// reduction. So this is accepted the moment the range check goes, and is the
// only shape that pins it: the earlier fixture (X = p exactly) reduces to
// x = 0, whose y² = 7 the paired Y does not satisfy, so it was refused by the
// equation rather than by the range check and the mutation survived.
check(AK.curve(fromPublicKey: "04"
      + "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc30"
      + "4218f20ae6c646b363db68605822fb14264ca8d2587fdd6fbc750d587e76a7ee") == .unknown,
      "a coordinate ABOVE the field prime is refused, never silently reduced")

// ===========================================================================
// The change diff — revocations and first use
// ===========================================================================
print("AltanaKeystore.changes")

check(AK.changes(previous: nil, current: [("0xa", 0), ("0xb", 3)]).isEmpty,
      "FIRST SIGHT REPORTS NOTHING — not the arrivals, and not a key that had already signed")
check(AK.changes(previous: [:], current: [("0xa", 0)]) == [.added("0xa")],
      "an empty baseline is real, so the next key is an arrival")
check(AK.changes(previous: ["0xa": 0], current: [("0xa", 0)]).isEmpty,
      "nothing changed, nothing said")
check(AK.changes(previous: ["0xa": 0], current: [("0xa", 0), ("0xb", 0)]) == [.added("0xb")],
      "a new key is an arrival")
check(AK.changes(previous: ["0xa": 0, "0xb": 0], current: [("0xa", 0)]) == [.revoked("0xb")],
      "A KEY THAT VANISHED IS A REVOCATION — the event the arrivals-only diff could not see")
check(AK.changes(previous: ["0xa": 0], current: [("0xa", 1)]) == [.firstUse("0xa")],
      "a nonce leaving zero is a FIRST USE")
check(AK.changes(previous: ["0xa": 3], current: [("0xa", 9)]).isEmpty,
      "…but an already-used key signing again is not news — only the first time is")
check(AK.changes(previous: ["0xa": 5], current: [("0xa", 2)]).isEmpty,
      "a nonce that FELL is a misread, not a signature — say nothing")
check(AK.changes(previous: ["0xA": 0], current: [("0xa", 1)]) == [.firstUse("0xa")],
      "the comparison is case-insensitive")
// Determinism: several revocations must come back in a stable order, or the
// rows reshuffle between passes.
let manyRevoked = AK.changes(previous: ["0xc": 0, "0xa": 0, "0xb": 0], current: [])
check(manyRevoked == [.revoked("0xa"), .revoked("0xb"), .revoked("0xc")],
      "several revocations arrive sorted, never in a Set's order")

// ===========================================================================
// The credential sheet
// ===========================================================================
print("AltanaKeySheet")

let addr = "2b589af23311e44398e626895af0e3d43e0c97a8"
let goodRef = "altana:key:bnb-smart-chain:\(addr):\(kid(1))"
check(AltanaKeySheet.parse(ref: goodRef)?.address == addr, "a key ref parses to its wallet")
check(AltanaKeySheet.parse(ref: "altana:event:revoked:\(addr):\(kid(1))") == nil,
      "an EVENT ref is refused — it is not a credential and must not open this sheet")
check(AltanaKeySheet.parse(ref: "altana:key:bnb:short:\(kid(1))") == nil, "a bad address is refused")
check(AltanaKeySheet.parse(ref: "peer:demo0") == nil, "another bridge's ref is refused")

func sheetKey(_ n: Int, root: Bool, reg: Int?, exp: Int?, sigs: Int, pub: String? = nil) -> AK.Key {
    AK.Key(id: "0x" + kid(n), isRoot: root,
           expiry: exp.map { Date(timeIntervalSince1970: TimeInterval($0)) },
           signatureCount: sigs, publicKey: pub,
           registeredAt: reg.map { Date(timeIntervalSince1970: TimeInterval($0)) },
           chainLabel: "BNB Smart Chain")
}
let sheetReading = AK.Reading(address: addr, keys: [
    sheetKey(1, root: false, reg: sessReg, exp: sessExp, sigs: 47, pub: realKey),
    sheetKey(2, root: true, reg: rootReg, exp: nil, sigs: 0),
], truncated: false)
let otherWallet = AK.Reading(address: "aaaa", keys: [
    sheetKey(1, root: false, reg: sessReg, exp: sessExp, sigs: 2)
], truncated: false)

guard let sheet = AltanaKeySheet.compose(ref: goodRef, readings: [sheetReading, otherWallet]) else {
    print("  ✗ the sheet composes"); exit(1)
}
check(AltanaKeySheet.title(sheet) == "24-hour key",
      "the heading is the grant duration when both ends are known")
check(AltanaKeySheet.subtitle(sheet).contains("Wallet key"),
      "the subtitle carries the CURVE, computed from real key material")
check(AltanaKeySheet.usageLine(sheet) == "Signed 47 times", "the usage line states the count")
check(sheet.alsoSignsFor == ["aaaa"],
      "THE SAME KEY ID ON ANOTHER WATCHED WALLET IS SURFACED — one credential, several accounts")
check(sheet.live == .checking,
      "the mounted state is 'checking' — the sheet never claims a status it hasn't asked for")
check(AltanaKeySheet.liveLine(sheet).contains("Checking"), "…and says so")
check(AltanaKeySheet.scopeCeiling(sheet) != nil, "a session key states the scope ceiling")

// A never-used key says so WITH its age, which is the part worth noticing.
guard let rootSheet = AltanaKeySheet.compose(
        ref: "altana:key:bnb-smart-chain:\(addr):\(kid(2))", readings: [sheetReading]) else {
    print("  ✗ the root sheet composes"); exit(1)
}
check(AltanaKeySheet.usageLine(rootSheet, now: Date(timeIntervalSince1970: TimeInterval(rootReg + 62 * 86_400)))
        == "Registered 62 days ago, never used",
      "a never-used key is stated with its age, never as 'signed 0 times'")
check(AltanaKeySheet.title(rootSheet) == "Root key", "a root key has no grant phrase")
check(AltanaKeySheet.scopeCeiling(rootSheet) == nil,
      "a root key does NOT claim a scope ceiling — its authority isn't scoped")
check(rootSheet.alsoSignsFor.isEmpty, "a key registered nowhere else surfaces nothing")

// An unreadable live check must never render as revoked.
var unreadable = sheet; unreadable.live = .unreadable
check(!AltanaKeySheet.liveLine(unreadable).lowercased().contains("revoked"),
      "AN UNREACHABLE RPC IS NOT A REVOCATION — the alarming direction is the wrong one")

print("")
if failures == 0 {
    print("✓ altana self-test: \(checks) checks passed")
} else {
    print("✗ altana self-test: \(failures) of \(checks) checks FAILED")
    exit(1)
}
SWIFT

swiftc -O -o "$TMP/selftest" "$MODEL" "$ROOM" "$SHEET" "$DRIVER"
"$TMP/selftest"
