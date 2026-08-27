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

# The demo reaches nothing, so its live line must not claim a check. If the
# demo path ever resolves to `.active` again, the card says "checked just now"
# over a key nothing asked about — §83 inside the experience people judge the
# app by, which is the worst place to keep it.
grep -q 'if DemoMode.isActive { return .seeded }' "$SOURCE" \
  || { echo "✗ the demo live-check no longer returns .seeded — it would claim a check it never made"; exit 1; }

# --- prd §488: the list, the card recipe, and the fixed window -------------
CARD="Casberi/Casberi/Screens/AltanaRoomCard.swift"
[[ -f "$CARD" ]] || { echo "✗ $CARD not found"; exit 1; }
# Read COMMENT-STRIPPED, because this card documents the redesign by NAMING
# everything it must no longer do — the constellation, the tokens, the rail.
# Grepping raw source fires on the prose explaining the guard: the
# Obsidian/Cursor lesson, which this project has now paid for six times.
CARDVIEW=$(sed 's://.*::' "$CARD" | sed '/^[[:space:]]*\/\/\//d')

# THE CARD RECIPE. This head was the only one in the Wallet group with neither,
# so its content ran flush to both screen edges while every sibling sat 18pt in
# — §474's reported bug, and the largest single part of "the room looks messy".
print -r -- "$CARDVIEW" | grep -q 'dsWidgetSurface()' \
  || { echo "✗ the Altana head lost its card surface — prd §488: every sibling room head"
       echo "  ends .dsWidgetSurface() + .padding(.horizontal, DS.Space.s4), and"
       echo "  insightSection presents them all edge-to-edge on purpose"; exit 1; }
print -r -- "$CARDVIEW" | grep -q 'padding(.horizontal, DS.Space.s4)' \
  || { echo "✗ the Altana head lost its outer margin — prd §488/§474"; exit 1; }

# ONE BAR OBJECT. The room next door rolled its own capsule pair for two
# months; two keystore rooms drawing one figure two ways is what
# DSSectionSwitcher was made generic on day one to avoid.
print -r -- "$CARDVIEW" | grep -q 'ShareBar(' \
  || { echo "✗ the key rows no longer draw ShareBar — prd §488"; exit 1; }

# THE CONSTELLATION AND THE RAIL MAY NOT RETURN. Both had defects no restyling
# fixes: an absolutely-positioned width that overflowed a 321pt card with no
# scroll, and an elastic axis whose now-marker was a constant.
for dead in 'AltanaRoom.placement' 'card.rail' 'Placement(' 'RailDot'; do
  print -r -- "$CARDVIEW" | grep -q "$dead" && {
    echo "✗ the Altana head is drawing $dead again — prd §488 replaced both with a list"; exit 1; }
done
ROOMCODE=$(sed 's://.*::' "$ROOM" | sed '/^[[:space:]]*\/\/\//d')
for dead in 'struct Placement' 'struct RailDot' 'static func placement' 'static func rail('; do
  print -r -- "$ROOMCODE" | grep -q "$dead" && {
    echo "✗ $ROOM declares $dead again — prd §488"; exit 1; }
done

# ONE WINDOW, TWO ROOMS. Altana's shelf and vibenet's are the same figure over
# the same subject; two keystore rooms drawing bars on two different scales
# would read as a bug, and neither file can see the other's constant.
VIBE="Casberi/Casberi/Model/VibenetRoom.swift"
ALT_W=$(grep -o 'static let shelfWindow: TimeInterval = [0-9_ *]*' "$ROOM" | grep -o '[0-9_]* \* [0-9_]*' | head -1)
VIB_W=$(grep -o 'static let window: TimeInterval = [0-9_ *]*' "$VIBE" | grep -o '[0-9_]* \* [0-9_]*' | head -1)
[[ -n "$ALT_W" && "$ALT_W" == "$VIB_W" ]] \
  || { echo "✗ the two keystore rooms' shelf windows disagree ('$ALT_W' vs '$VIB_W') — prd §488"; exit 1; }

# THE FACE RAIL'S PICK REACHES THE HEAD. Altana is in the Wallet category, so
# WalletScopeRail has drawn above this room since §356; a head that ignores the
# ringed face is the dead control §83 bans.
grep -q 'AltanaRoom.card(scope: selectedWallet)' "Casberi/Casberi/Screens/FeedScreen.swift" \
  || { echo "✗ the Altana head no longer obeys the wallet scope — prd §488"; exit 1; }

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

func farOffRowHasNoHours() -> Bool {
    let far = key(60, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) + 5 * 86_400)
    guard let c = AltanaRoom.compose(readings: [reading("0xa", [root, far])], now: now) else { return false }
    return c.rows.last?.hoursLeft == nil && c.rows.last?.daysLeft == 5
}

func demoModel(_ live: AltanaKeySheet.LiveState) -> AltanaKeySheet.Model {
    var m = AltanaKeySheet.Model(keyID: "0x" + String(repeating: "0", count: 64),
                                 address: "0xa", isRoot: false, registeredAt: nil,
                                 expiry: nil, signatureCount: 0, chainLabel: nil,
                                 curve: .unknown, alsoSignsFor: [])
    m.live = live
    return m
}

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
// A real P-256 point, so the kind label is asserted against ground truth
// rather than against our own detector agreeing with itself.
let p256Sample = "0x04" + "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296"
                        + "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5"
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
check(card.rows.count == 3, "EVERY credential gets a row now — the root included")
check(card.sessions.count == 2, "…and `sessions` still answers the old question")
check(card.staleNote?.contains("1 key") == true, "the tidy-up line names the count")
check(card.chains == ["BNB Smart Chain"], "chains are listed, in first-appearance order")
check(card.accounts.count == 1, "one account, one group")
check(card.sharedNote == nil, "…and no shared-credential note when nothing is shared")

// ── ORDER, which compose owns since §405 ──────────────────────────────────
// The defect this replaced: `compose` mapped whatever it was handed, and real
// accounts arrive through `AltanaKeystore.sorted` — roots first then ASCENDING
// expiry — so an expired key, holding the earliest date of all, led the card.
check(card.rows.first?.isRoot == true, "the root leads")
check(card.rows[1].id == live.id, "then the LIVE session")
check(card.rows[2].id == over.id, "and the expired one is LAST, not first")

// Feeding it in the order a real read produces must not change the result.
guard let resorted = AltanaRoom.compose(
        readings: [reading("0xa", AK.sorted([root, live, over]))], now: now) else {
    print("  ✗ a sorted reading composes"); exit(1)
}
check(resorted.rows.map(\.id) == card.rows.map(\.id),
      "THE SORT AND THE DEMO NOW AGREE — the two orderings that used to differ")
check(AltanaRoom.compose(readings: [reading("0xa", [over, live, root])], now: now)?
        .rows.map(\.id) == card.rows.map(\.id),
      "…in any input order at all")

// Two expired keys: most recently expired first, and totally ordered.
let old1 = key(20, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) - 90_000)
let old2 = key(21, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) - 10_000)
guard let twoDead = AltanaRoom.compose(readings: [reading("0xa", [root, old1, old2])], now: now) else {
    print("  ✗ two expired keys compose"); exit(1)
}
check(twoDead.rows[1].id == old2.id, "the most recently expired leads its group")

// ── the row's own words ───────────────────────────────────────────────────
guard let rootRow = card.rows.first else { print("  ✗ root row"); exit(1) }
check(rootRow.progress == nil, "A ROOT HAS NO RUNWAY — no end, so no fraction to draw")
// The case above proves the right thing for the WRONG reason on its own: that
// root has no expiry, so `progress` is nil whatever the row does, and deleting
// the guard ran green. This is the fixture that actually pins it — a root
// carrying BOTH dates, where an unguarded row would happily draw a bar.
let datedRoot = key(50, root: true, reg: Int(now.timeIntervalSince1970) - 3600,
                    exp: Int(now.timeIntervalSince1970) + 3600)
check(datedRoot.progress(now: now) != nil, "…(the underlying key CAN compute one)")
guard let datedCard = AltanaRoom.compose(readings: [reading("0xa", [datedRoot, live])], now: now) else {
    print("  ✗ a dated root composes"); exit(1)
}
check(datedCard.rows.first?.progress == nil,
      "…and the ROW still refuses it: a root's authority does not run out, so a bar would be a lie")
check(rootRow.detail?.contains("registered") == true, "the root row carries its registration date")
// 25, not 24: this fixture was registered an hour before "now" and expires a
// day after it, so its grant really is 25 hours. Asserted exactly rather than
// loosely — a `contains("hour")` here would pass against almost any arithmetic.
check(card.rows[1].detail?.contains("25-hour grant") == true,
      "a session row carries its grant, worded as a GRANT (§406 — the row's title already says key)")
check(card.rows[1].detail?.contains("Session key") != true,
      "…and the role is NOT respelled beside it: a grant implies a session, and 'Session key · 25-hour key' said it twice")

// The honesty rail moved with the date: no witnessed registration, no date.
guard let undatedCard = AltanaRoom.compose(
        readings: [reading("0xa", [key(7, root: true, reg: nil, exp: nil), live])], now: now) else {
    print("  ✗ an undated root still composes"); exit(1)
}
check(undatedCard.rows.first?.detail?.contains("registered") != true,
      "NO DATE when it wasn't witnessed — 'registered today' must never stand in for 'we don't know'")

// ── the kind label (§404's curve, which the room ignored until §405) ──────
let passkey = AK.Key(id: "0x" + kid(30), isRoot: false,
                     expiry: Date(timeIntervalSince1970: TimeInterval(Int(now.timeIntervalSince1970) + 86_400)),
                     signatureCount: 0, publicKey: p256Sample,
                     registeredAt: Date(timeIntervalSince1970: TimeInterval(sessReg)),
                     chainLabel: "BNB Smart Chain")
guard let kindCard = AltanaRoom.compose(readings: [reading("0xa", [root, passkey])], now: now),
      let kindRow = kindCard.rows.last else { print("  ✗ a passkey composes"); exit(1) }
check(kindRow.title == "Passkey", "a P-256 credential is titled by the word a person already owns")
check(kindRow.detail?.contains("Session key") != true,
      "…and the role is IMPLIED by the grant, not respelled (§406)")
// The role IS said when nothing else implies it: a kind-titled session with
// no readable grant would otherwise be a row whose two lines never say what
// the credential is.
let grantless = AK.Key(id: "0x" + kid(32), isRoot: false,
                       expiry: nil, signatureCount: 0, publicKey: p256Sample,
                       registeredAt: nil, chainLabel: "BNB Smart Chain")
guard let grantlessCard = AltanaRoom.compose(readings: [reading("0xa", [root, grantless])], now: now) else {
    print("  ✗ a grantless session composes"); exit(1)
}
check(grantlessCard.rows.last?.title == "Passkey", "…(fixture premise: the title took the kind)")
check(grantlessCard.rows.last?.detail?.contains("Session key") == true,
      "…so with NO grant to imply it, the role IS said — the exception that keeps the rule honest")
let unknownKind = AltanaRoom.compose(readings: [reading("0xa", [root, live])], now: now)
check(unknownKind?.rows.last?.title == "Session key",
      "an unreadable curve falls back to the role, never a guess")

// ── usage, said only when it carries information ─────────────────────────
check(kindRow.usageNote == "never used", "a credential that has never signed says so")
let used = AK.Key(id: "0x" + kid(31), isRoot: false,
                  expiry: Date(timeIntervalSince1970: TimeInterval(Int(now.timeIntervalSince1970) + 86_400)),
                  signatureCount: 12, publicKey: nil,
                  registeredAt: Date(timeIntervalSince1970: TimeInterval(sessReg)),
                  chainLabel: "BNB Smart Chain")
guard let usedCard = AltanaRoom.compose(readings: [reading("0xa", [root, used])], now: now) else {
    print("  ✗ a used session composes"); exit(1)
}
check(usedCard.rows.last?.usageNote == nil,
      "a session key doing its job needs no remark — only the never-used one is notable")
check(usedCard.rows.first?.usageNote != nil,
      "…but a ROOT key's count is the account's own activity, so it is always stated")

// ── §406: two wordings, one measured computation ─────────────────────────
check(AltanaRoom.grantPhrase(seconds: 86_400) == "24-hour key", "the sheet's wording is untouched")
check(AltanaRoom.grantDetail(seconds: 86_400) == "24-hour grant", "the room's wording says grant")
check(AltanaRoom.grantDetail(seconds: 86_400 * 30) == "30-day grant", "…in days too")
check(AltanaRoom.grantDetail(seconds: 90 * 60) == "90-minute grant", "…and minutes")
check(AltanaRoom.grantDetail(seconds: 0) == nil, "a zero grant has no detail either")
check(AltanaRoom.grantDetail(seconds: 86_400 + 600) == "24-hour grant",
      "both wordings share the measured rounding — they cannot drift apart")

// ── §406: root detail leads "Root", not "Root key", when the title says key ─
// The plain fixture root has no key material, so its title IS "Root key" and
// its detail rightly does not respell "Root" — asserting on it was the wrong
// premise. The kind-titled case needs a root whose curve resolves.
check(rootRow.detail?.hasPrefix("Root") != true,
      "a role-titled root does not repeat itself in its own detail")
let kindRoot = AK.Key(id: "0x" + kid(33), isRoot: true, expiry: nil,
                      signatureCount: 128, publicKey: p256Sample,
                      registeredAt: Date(timeIntervalSince1970: TimeInterval(rootReg)),
                      chainLabel: "BNB Smart Chain")
guard let kindRootCard = AltanaRoom.compose(readings: [reading("0xa", [kindRoot, live])], now: now) else {
    print("  ✗ a kind-titled root composes"); exit(1)
}
check(kindRootCard.rows.first?.title == "Passkey", "…(fixture premise: the title took the kind)")
check(kindRootCard.rows.first?.detail?.hasPrefix("Root ·") == true,
      "a kind-titled root's detail leads the bare word Root — its title already says key")

// ── §407a: every account draws, and the aggregate is real ─────────────────
// The old card ranked accounts and drew ONE; the keyring draws them all.
let acctA = reading("0xaaa", [root, live])                    // no imminent deadline
let acctB = reading("0xbbb", [key(70, root: true, reg: rootReg, exp: nil),
                              key(71, root: false, reg: sessReg,
                                  exp: Int(now.timeIntervalSince1970) + 4 * 3600)])
guard let multi = AltanaRoom.compose(readings: [acctA, acctB], now: now) else {
    print("  ✗ two accounts compose"); exit(1)
}
check(multi.accounts.count == 2, "BOTH accounts draw — the footnote is retired")
check(multi.accounts.first?.address == "0xbbb",
      "the account with the soonest live deadline draws on TOP — ranking orders, it no longer selects")
check(multi.usableCount == 4, "the census spans every account")
check(multi.headline.contains("for 2 accounts") || multi.subline?.contains("for 2 accounts") == true,
      "…and says so")
check(multi.urgentHours == 4, "urgency is the soonest deadline ANYWHERE")
// (No mutation can separate "urgency over all keys" from "urgency over the
// top-ranked account's keys": the ranking puts the soonest deadline on top by
// construction, so the two are equivalent. Recorded so nobody chases it.)
check(AltanaRoom.compose(readings: [acctB, acctA], now: now)?.accounts.map(\.id)
        == multi.accounts.map(\.id),
      "group order is total — input order cannot flip the card")

// ── §407a: the shared credential is detected by ID, never inferred ────────
let sharedKey = key(72, root: false, reg: sessReg,
                    exp: Int(now.timeIntervalSince1970) + 86_400)
let shA = reading("0xaaa", [root, sharedKey])
let shB = reading("0xbbb", [key(73, root: true, reg: rootReg, exp: nil), sharedKey])
guard let sharedCard = AltanaRoom.compose(readings: [shA, shB], now: now) else {
    print("  ✗ shared-credential accounts compose"); exit(1)
}
check(sharedCard.sharedKeyIDs == [sharedKey.id.lowercased()],
      "the same key id under two accounts is the shared credential — by construction, no inference")
// A key SIGNS FOR an account and never HOLDS one (user ruling, §408a) — the
// overclaim this seat is otherwise careful about, in the sentence most likely
// to be read.
check(sharedCard.sharedNote?.contains("can sign for") == true,
      "…and the card says it once, as SIGNS FOR — never 'holds'")
check(sharedCard.sharedNote?.lowercased().contains("hold") == false,
      "…the word 'hold' never appears: a key does not hold an account")
check(multi.sharedKeyIDs.isEmpty,
      "distinct ids across accounts share NOTHING — the badge must be rare or it is wallpaper")
// The same id twice under ONE account is a duplicate row, not a shared
// credential — sharing means crossing an account boundary.
let dupA = reading("0xaaa", [root, sharedKey, sharedKey])
check(AltanaRoom.compose(readings: [dupA], now: now)?.sharedKeyIDs.isEmpty == true,
      "a duplicate within one account is not 'shared' — sharing crosses accounts")

// ── §407a: the floor is the TOTAL across accounts ─────────────────────────
let lonelyA = reading("0xaaa", [key(74, root: true, reg: rootReg, exp: nil)])
let lonelyB = reading("0xbbb", [key(75, root: true, reg: rootReg, exp: nil)])
check(AltanaRoom.compose(readings: [lonelyA], now: now) == nil,
      "one root alone is still under the floor")
check(AltanaRoom.compose(readings: [lonelyA, lonelyB], now: now) != nil,
      "…but two accounts of one root each clear it — the registry exists in aggregate")

// ── §407a: the sheet keeps the root's date now the card rows are gone ─────
var regM = demoModel(.seeded)
check(AltanaKeySheet.registeredLine(regM) == nil,
      "no witnessed date, no Registered row — never 'today' standing in for unknown")
regM = AltanaKeySheet.Model(keyID: regM.keyID, address: "0xa", isRoot: true,
                            registeredAt: Date(timeIntervalSince1970: TimeInterval(rootReg)),
                            expiry: nil, signatureCount: 128, chainLabel: nil,
                            curve: .unknown, alsoSignsFor: [])
check(AltanaKeySheet.registeredLine(regM) != nil,
      "a ROOT gets the Registered row — with the card rows retired, this is the date's one home")
let windowed = AltanaKeySheet.Model(keyID: regM.keyID, address: "0xa", isRoot: false,
                                    registeredAt: Date(timeIntervalSince1970: TimeInterval(sessReg)),
                                    expiry: Date(timeIntervalSince1970: TimeInterval(sessExp)),
                                    signatureCount: 0, chainLabel: nil,
                                    curve: .unknown, alsoSignsFor: [])
check(AltanaKeySheet.registeredLine(windowed) == nil,
      "…while a drawn window already says Granted, so the row stays away (§406's duplicate rule)")

// ── the headline leads with the clock when there is one ──────────────────
check(card.headline.contains("2"), "with nothing imminent the headline states the census")
check(card.urgentHours == nil, "…and no urgency is claimed")
let imminent = key(40, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) + 9 * 3600)
guard let urgent = AltanaRoom.compose(readings: [reading("0xa", [root, imminent])], now: now) else {
    print("  ✗ an imminent expiry composes"); exit(1)
}
check(urgent.urgentHours == 9, "nine hours out is nine hours")
check(urgent.headline.contains("9 hours"), "ALARM FIRST — the thing with a clock on it leads")
check(urgent.subline?.contains("can sign") == true,
      "…and the census SURVIVES as a subline — the alarm used to delete it (§406)")
check(card.subline == nil,
      "with no alarm the headline IS the census, and the card never says it twice")
// Inside the last day the row agrees with the headline about the same clock.
check(urgent.rows.last?.hoursLeft == 9, "a sub-day deadline carries its hours")
check(farOffRowHasNoHours(), "…and a distant one does not — hours past a day are noise")
let farOff = key(41, root: false, reg: sessReg, exp: Int(now.timeIntervalSince1970) + 5 * 86_400)
check(AltanaRoom.compose(readings: [reading("0xa", [root, farOff])], now: now)?.urgentHours == nil,
      "a deadline days away is a row's business, not a headline's")
check(AltanaRoom.compose(readings: [reading("0xa", [root, over])], now: now)?.urgentHours == nil,
      "an ALREADY expired key is never urgent — it needs nothing")

// ── §406 on the SHEET: the role is never said twice ──────────────────────
var sheetM = demoModel(.seeded)
check(AltanaKeySheet.subtitle(sheetM) == "",
      "no curve, no chain — the subtitle is empty, and the view skips it")
sheetM = AltanaKeySheet.Model(keyID: "0x" + String(repeating: "0", count: 64),
                              address: "0xa", isRoot: false,
                              registeredAt: Date(timeIntervalSince1970: TimeInterval(sessReg)),
                              expiry: Date(timeIntervalSince1970: TimeInterval(sessExp)),
                              signatureCount: 0, chainLabel: "BNB Smart Chain",
                              curve: .p256, alsoSignsFor: [])
check(AltanaKeySheet.subtitle(sheetM) == "Passkey · BNB Smart Chain",
      "THE ROLE IS GONE FROM THE SUBTITLE — the title states or implies it, and two adjacent lines both saying session was §406's complaint")
check(AltanaKeySheet.title(sheetM) == "24-hour key",
      "…(fixture premise: the title is the grant phrase, which implies the role)")
// Usage: the age rides along only when the window above is not drawn.
check(AltanaKeySheet.usageLine(sheetM) == "Never used",
      "with the grant window drawn, usage does not repeat the Granted date two rows up")
var rootM = sheetM; // root: window absent, so the age lives here — its one home
rootM = AltanaKeySheet.Model(keyID: sheetM.keyID, address: "0xa", isRoot: true,
                             registeredAt: Date(timeIntervalSince1970: TimeInterval(rootReg)),
                             expiry: nil, signatureCount: 0, chainLabel: nil,
                             curve: .unknown, alsoSignsFor: [])
check(AltanaKeySheet.usageLine(rootM, now: now).contains("never used"),
      "with NO window drawn the age stays in the usage line — the one place it shows")
check(AltanaKeySheet.usageLine(rootM, now: now).contains("days ago"),
      "…dated, because nothing else on the card dates a root")
check(AltanaKeySheet.scopeCeiling(sheetM) == "Only a key’s deadline is published, never its scope.",
      "the sheet's ceiling matches the card's, word for word — two spellings of one fact drift")

// The demo's own state says the true thing and no more.
check(!AltanaKeySheet.liveLine(demoModel(.seeded)).contains("checked"),
      "THE DEMO NEVER CLAIMS A CHECK — it reaches nothing, so it may not say it looked")
check(AltanaKeySheet.liveLine(demoModel(.active)).contains("checked"),
      "…while a real read does say so, which is the whole distinction")

// ── §408a: credentials, not registrations ─────────────────────────────────
// The picture draws a shared key ONCE, so the census counts it once. Saying
// "5 keys" over a drawing of 4 tokens is the card disagreeing with itself.
check(sharedCard.credentials.count == 3,
      "a key shared across two accounts is ONE credential, not two")
check(sharedCard.rows.count == 4, "…while the per-account rows still count both registrations")
check(sharedCard.usableCount == 3, "the census counts credentials")
guard let sharedCred = sharedCard.credentials.first(where: { $0.isShared }) else {
    print("  ✗ the shared credential is marked"); exit(1)
}
check(sharedCred.accountAddresses.count == 2, "…and carries both accounts it can sign for")
check(sharedCred.accountAddresses == ["0xaaa", "0xbbb"],
      "…in the order the accounts are drawn, so the ties are stable between opens")
check(multi.credentials.allSatisfy { !$0.isShared }, "distinct keys are never marked shared")

// ── §488: THE SHELF — one bar per key, on ONE FIXED WINDOW ───────────────
// This replaces §408a's dot rail, which carried `VibenetKeyShelf`'s own
// measured defect: the axis spanned `now … furthest live deadline`, so `now`
// was the minimum on every render (every expiry is in the future) and the
// marker was a constant, while a single far-off key crushed everything else
// against it. Every failure below renders as a perfectly ordinary row.
let shelfNow = Date(timeIntervalSince1970: 1_787_083_931)
func at(_ n: Int, hours: Double) -> AK.Key {
    key(n, root: false, reg: sessReg, exp: Int(shelfNow.timeIntervalSince1970 + hours * 3600))
}
func rowFor(_ k: AK.Key, with others: [AK.Key] = [root]) -> AltanaRoom.KeyRow? {
    AltanaRoom.compose(readings: [reading("0xa", others + [k])], now: shelfNow)?
        .credentials.first { $0.id == k.id }
}

guard let near = rowFor(at(80, hours: 9)),
      let mid  = rowFor(at(81, hours: 45 * 24)),
      let far  = rowFor(at(82, hours: 200 * 24)) else {
    print("  ✗ the shelf rows compose"); exit(1)
}
check(abs((mid.shelfFraction(now: shelfNow) ?? 0) - 0.5) < 0.01,
      "half the window left draws half a bar")
check(far.shelfFraction(now: shelfNow) == 1.0,
      "a key beyond the window CLAMPS to a full bar — the countdown beside it stays exact")
check(near.shelfFraction(now: shelfNow) == AltanaRoom.minimumFraction,
      "a key lapsing in hours is floored to a bar you can still see, never drawn as a hole")

// THE FIXTURE THAT SEPARATES A FIXED WINDOW FROM AN ELASTIC ONE, and the only
// one that can: the same 9-hour key in two rooms whose furthest deadline is
// wildly different must draw the SAME bar. Under the old rail these two were
// 0.012 and 0.9 — the same key, two pictures, neither comparable to the other.
guard let nearBesideFar = AltanaRoom.compose(
        readings: [reading("0xa", [root, at(83, hours: 9), at(84, hours: 2000)])], now: shelfNow)?
        .credentials.first(where: { $0.id == at(83, hours: 9).id }),
      let nearAlone = rowFor(at(83, hours: 9)) else {
    print("  ✗ the two-room comparison composes"); exit(1)
}
check(nearBesideFar.shelfFraction(now: shelfNow) == nearAlone.shelfFraction(now: shelfNow),
      "THE WINDOW IS FIXED — a key's bar cannot change because another key exists")

// The states with no clock. nil is the correct answer for three of the four,
// and each is its own reason: no end, no time left, not on the shelf at all.
guard let clockless = AltanaRoom.compose(readings: [reading("0xa", [root, live, over])], now: shelfNow),
      let rootRow = clockless.credentials.first(where: \.isRoot),
      let expiredRow = clockless.credentials.first(where: { $0.id == over.id }) else {
    print("  ✗ the clockless rows compose"); exit(1)
}
check(rootRow.shelfFraction(now: shelfNow) == nil,
      "A ROOT HAS NO BAR — drawing one would state a completion that does not exist")
check(rootRow.countdown(now: shelfNow) == "no expiry", "…and says so in words")
check(expiredRow.shelfFraction(now: shelfNow) == nil, "an expired key has no bar")
check(expiredRow.countdown(now: shelfNow) == "expired", "…and its countdown says which state it is in")

// The countdown. Days round UP — 30 hours reading "1d" understates it on the
// one line whose whole job is to say how much time there is.
check(near.countdown(now: shelfNow) == "9h", "under a day counts in hours")
check(mid.countdown(now: shelfNow) == "45d", "past a day counts in days")
check(rowFor(at(85, hours: 30))?.countdown(now: shelfNow) == "2d",
      "30 hours left rounds UP to 2d, never down to 1d")
check(rowFor(at(86, hours: 0.5))?.countdown(now: shelfNow) == "<1h",
      "inside the hour says so rather than printing 0h")

// The mark, and it is the headline's own threshold rather than a second one.
check(near.isUrgent(now: shelfNow), "a key inside the day is the row that earns the mark")
check(rowFor(at(87, hours: 25))?.isUrgent(now: shelfNow) == false,
      "…and one just outside it is not — same threshold the headline's alarm uses")
check(expiredRow.isUrgent(now: shelfNow) == false, "an expired key is never urgent — it is finished")

// ── §488: the cap is said, never silent ──────────────────────────────────
// A card that stops at six looks exactly like an account that has six — the
// silent-truncation class this repo has paid for in four import rooms.
let many = (100...107).map { at($0, hours: Double($0 - 99) * 24) }
guard let capped = AltanaRoom.compose(readings: [reading("0xa", [root] + many)], now: shelfNow) else {
    print("  ✗ a capped card composes"); exit(1)
}
check(capped.credentials.count == 9, "every credential is still counted")
check(capped.drawn.count == AltanaRoom.rowCap, "…while only the cap is drawn")
check(capped.moreLine?.contains("3") == true, "…and the remainder is SAID")
check(AltanaRoom.compose(readings: [reading("0xa", [root, live])], now: shelfNow)?.moreLine == nil,
      "a card inside the cap says nothing about it")

// ── §488: the face rail's pick narrows the head ──────────────────────────
// Altana sits in the Wallet category, so the wallet face rail has drawn above
// this room since §356 and the head ignored it entirely — a scope control the
// head does not obey is the dead control §83 bans.
guard let scoped = AltanaRoom.compose(readings: [shA, shB], now: now, scope: "0xaaa") else {
    print("  ✗ a scoped card composes"); exit(1)
}
check(scoped.accounts.count == 1, "one account draws when one is picked")
check(scoped.accounts.first?.address == "0xaaa", "…the one that was picked")
check(scoped.credentials.allSatisfy { $0.accountAddresses.contains("0xaaa") },
      "…and every row can sign for it")
check(scoped.credentials.count == 2, "the other account's own root is gone")

// THE ONE THAT MATTERS: narrowing happens AFTER the dedupe, so a credential
// that also signs for a wallet now out of scope keeps saying so. Filtering the
// readings on the way in would make the single most valuable fact on a scoped
// card structurally unsayable.
guard let scopedShared = scoped.credentials.first(where: { $0.id == sharedKey.id }) else {
    print("  ✗ the shared credential survives scoping"); exit(1)
}
check(scopedShared.isShared, "A SCOPED ROW STILL KNOWS IT IS SHARED")
check(scopedShared.accountAddresses.count == 2, "…and still names both accounts it signs for")
check(scoped.sharedNote != nil, "…so the sentence survives too")

// Hex compares case-insensitively — EIP-55 case is a checksum, not identity.
check(AltanaRoom.compose(readings: [shA, shB], now: now, scope: "0xAAA")?.accounts.count == 1,
      "a checksummed spelling of the same address is the same account")
// A scope this keystore has never seen DECLINES rather than falling back to
// the aggregate, which would draw every account under one ringed face.
check(AltanaRoom.compose(readings: [shA, shB], now: now, scope: "0xzzz") == nil,
      "a wallet the keystore has never seen has no card, and does not borrow one")
check(AltanaRoom.compose(readings: [shA, shB], now: now, scope: nil)?.accounts.count == 2,
      "and All is unchanged")

// The alarm and the census follow the scope, or a scoped card reports the
// room's soonest deadline under one account's face.
guard let scopedB = AltanaRoom.compose(readings: [acctA, acctB], now: now, scope: "0xaaa") else {
    print("  ✗ the unhurried account composes scoped"); exit(1)
}
// Asserted as "not 0xbbb's number", never as "nil": 0xaaa's own session lands
// exactly on the 24-hour urgency boundary, so a nil here would pass for a
// reason that has nothing to do with scoping — the right-result-wrong-reason
// class this repo keeps re-earning.
check(multi.urgentHours == 4, "the unscoped card's alarm is the soonest deadline anywhere")
check(scopedB.urgentHours != 4,
      "THE ALARM IS SCOPED — 0xbbb's four-hour deadline is not 0xaaa's news")
check(scopedB.usableCount == 2, "…and so is the census")

// ── §410: revoked credentials the picture remembers ─────────────────────
// The registry DROPS a revoked key from getKeys, so a ghost can only ever be
// something we saw before it went — forward-only by construction, and the copy
// says "while you were watching" rather than implying a complete history.
func ghost(_ n: Int, address: String = "0xaaa", root: Bool = false) -> AltanaRoom.Ghost {
    AltanaRoom.Ghost(address: address, keyID: "0x" + kid(n), isRoot: root,
                     kindLabel: "Passkey", chainLabel: "BNB Smart Chain",
                     noticedAt: shelfNow.addingTimeInterval(-3 * 86_400))
}
guard let withGhost = AltanaRoom.compose(
        readings: [reading("0xaaa", [root, live])], ghosts: [ghost(90)], now: now) else {
    print("  ✗ a ghost composes"); exit(1)
}
check(withGhost.credentials.count == 3, "the ghost joins the picture")
check(withGhost.credentials.last?.isGone == true, "…and is drawn LAST, after the living")
check(withGhost.usableCount == 2,
      "A GHOST IS NOT USABLE — a revoked key must never be counted as one that can sign")
check(withGhost.revokedNote?.contains("1 key") == true, "the sentence names the count")
check(withGhost.revokedNote?.contains("while you were watching") == true,
      "…and says WHILE YOU WERE WATCHING, because the history before that is unknowable")
// A ghost is not on the shelf at all — it has no clock, and a bar for it would
// say it is still running down toward something (§488; it was a CUT TIE in the
// constellation, which is the same reading in the drawing that replaced it).
guard let ghostRow = withGhost.credentials.first(where: \.isGone) else {
    print("  ✗ the ghost is a row"); exit(1)
}
check(ghostRow.shelfFraction(now: now) == nil, "a revoked credential draws no bar")
check(ghostRow.countdown(now: now) == "revoked", "…and its row says which state it is in")
check(ghostRow.isUrgent(now: now) == false, "…and it is never urgent — it is already gone")

// ── §488: ONE line, ranked ───────────────────────────────────────────────
// Both sentences became summaries of drawn rows the moment the constellation
// became a list, so the card says one and the rows carry the rest.
guard let both = AltanaRoom.compose(
        readings: [reading("0xaaa", [root, live, over])], ghosts: [ghost(92)], now: now) else {
    print("  ✗ a card with both notes composes"); exit(1)
}
check(both.revokedNote != nil && both.staleNote != nil, "the fixture really has both to say")
check(both.note == both.revokedNote,
      "REVOCATION OUTRANKS HYGIENE — a key somebody took away beats a key that merely lapsed")
guard let staleOnly = AltanaRoom.compose(
        readings: [reading("0xaaa", [root, live, over])], now: now) else {
    print("  ✗ a stale-only card composes"); exit(1)
}
check(staleOnly.note == staleOnly.staleNote,
      "…and the hygiene line comes back on its own once there is no ghost")

// A key that came BACK is alive, not a ghost — drawing both would be wrong in
// two directions at once.
guard let returned = AltanaRoom.compose(
        readings: [reading("0xaaa", [root, live])],
        ghosts: [AltanaRoom.Ghost(address: "0xaaa", keyID: live.id, isRoot: false,
                                  kindLabel: nil, chainLabel: nil, noticedAt: now)],
        now: now) else { print("  ✗ a returned key composes"); exit(1) }
check(returned.credentials.count == 2, "a re-registered id is NOT also drawn as a ghost")
check(returned.credentials.allSatisfy { !$0.isGone }, "…and nothing is marked gone")
check(AltanaRoom.compose(readings: [reading("0xaaa", [root, live])], now: now)?
        .revokedNote == nil, "no ghosts, no sentence")

// The same ghost handed in twice is drawn once. The store dedupes too, but a
// fixture with a single ghost can never exercise this — and the belt-and-
// braces guard is exactly the kind that rots unnoticed without its own case.
guard let twice = AltanaRoom.compose(readings: [reading("0xaaa", [root, live])],
                                     ghosts: [ghost(91), ghost(91)], now: now) else {
    print("  ✗ duplicate ghosts compose"); exit(1)
}
check(twice.credentials.filter(\.isGone).count == 1, "one ghost, however many times handed in")
check(twice.revokedNote?.contains("1 key") == true, "…and the sentence counts it once")

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
