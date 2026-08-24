#!/bin/zsh
# Casberi vibenet self-test — verifies the SHIPPED pure logic behind the
# Base "vibenet" devnet room (2026-08-23):
#
#   Casberi/Casberi/Model/VibenetRoom.swift
#     — VibenetScope             (permission-bit naming, unknown-bit counting)
#     — VibenetAuthenticatorKind.identify (which key kind an actor's is)
#     — VibenetActorLog.survivors        (the authorize/revoke log UNION)
#     — VibenetAccountItem.orderedActors (a roster's stable order)
#     — VibenetRoom.ordered/headline/note/rowLine/actorSummary/shortAddress
#
# WHY A HARNESS. `-vibenetProbe` needs a real devnet address with a real actor
# roster to exercise anything interesting, and nothing on this host can make
# vibenet authorize an actor, revoke one, or lock an account — so this harness
# is not the best proof the composition is right, it is the ONLY one.
#
# Every failure here is a SILENT WRONG ANSWER that renders as a perfectly
# ordinary card:
#
#   • an actorId whose most recent event was a REVOKE still reading as live —
#     the card would show a key that can no longer act for the account as
#     though it still could, which is the one security-relevant fact this
#     whole feature exists to get right;
#   • a revoked-then-reauthorized actorId reading as dead, because the union
#     trusted input order instead of the log's own chronology;
#   • a reserved scope bit silently NAMED as one of the five known ones —
#     inventing a permission a key doesn't actually carry;
#   • "Not established yet" printed for an account that IS established but
#     has authorized no actor this build can see — two different facts about
#     the account, conflated into one wrong sentence;
#   • a locked account not leading the card, so the one alarm this room can
#     raise goes unseen underneath a page of quiet accounts.
#
# `VibenetRoom.swift` is Foundation-only by design and is compiled WHOLE AND
# UNMODIFIED — never a copy, never extracted piecemeal — which is the
# strongest form of "the harness ran the shipped logic".
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/VibenetRoom.swift"
BRIDGE="Casberi/Casberi/Model/VibenetBridge.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
ROUTER="Casberi/Casberi/Model/BridgeRouting.swift"
for f in "$ROOM" "$BRIDGE" "$CATALOG" "$REACH" "$ROUTER"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

if [[ "${1:-}" == "--self-test" ]]; then
  # This harness's own demonstration that it can fail lives in the mutation
  # block at the bottom, which runs on every invocation rather than behind a
  # flag — a check that cannot fail proves nothing, and one that only tries
  # when asked proves nothing on the runs that matter.
  echo "vibenet-selftest: assertions + mutations run unconditionally below"
fi

TMP=$(mktemp -d /tmp/vibenet-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards ------------------------------------------------------------
# Wiring the compiled functions cannot prove: a perfect composition is worth
# nothing if the catalog never offers the seat, the router never resolves it,
# or the app never discloses the two hosts it reaches.

grep -q 'Offer(name: "Base Vibenet"' "$CATALOG" \
  || { echo "✗ Base Vibenet is not a catalog offer — the seat can never be connected"; exit 1; }
grep -q 'rpc.vibes.base.org' "$REACH" \
  || { echo "✗ rpc.vibes.base.org is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'api.vibes.base.org' "$REACH" \
  || { echo "✗ api.vibes.base.org is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'case .vibenet:.*VibenetScreen' "$ROUTER" \
  || { echo "✗ BridgeRouter no longer routes .vibenet to VibenetScreen"; exit 1; }

# THE STANDING CONSTRAINT: vibenet's contracts are redeployed on no fixed
# schedule, so nothing here may ever hardcode one of its addresses outside
# the two the Keystore contract itself declares fixed (K1's address(1), and
# the zero address every revoked actor reads back as). Every real address in
# `eip8130` this build has ever seen begins "0x8130" — six of the eight —
# so a literal starting with it, anywhere outside a comment, is the bug this
# whole feature exists to prevent. Reads a COMMENT-STRIPPED copy of both
# files: the header doc and this very check's reasoning both quote that
# prefix in prose, so a raw grep would flag the documentation explaining the
# rule as a violation of it (the Obsidian/Cursor lesson).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$ROOM"   > "$TMP/room.nc.swift"
strip_comments "$BRIDGE" > "$TMP/bridge.nc.swift"

if grep -qi '0x8130' "$TMP/room.nc.swift" "$TMP/bridge.nc.swift"; then
  echo "✗ a literal vibenet contract address (0x8130…) is hardcoded outside a comment —"
  echo "  vibenet redeploys its contracts; this must come from VibenetConfig's live fetch"
  exit 1
fi
# The two addresses this file MAY hardcode, named so the check above isn't
# fooled by their own presence: K1's fixed constant and the zero address.
grep -q '0x0000000000000000000000000000000000000001' "$TMP/room.nc.swift" \
  || { echo "✗ K1_AUTHENTICATOR's fixed address is missing — secp256k1 actors can never be identified"; exit 1; }

# Genuinely read-only: no signing key of this app's own may ever touch
# vibenet (unlike the Safe co-signer, prd §425/§426 — there is no counterpart
# here), and no write-shaped RPC method may be requested.
if grep -q 'SignerKey\|SafeSigner' "$TMP/room.nc.swift" "$TMP/bridge.nc.swift"; then
  echo "✗ VibenetRoom/VibenetBridge reference a signing type — this feature must never sign"
  exit 1
fi
for method in 'eth_sendTransaction' 'eth_sendRawTransaction' 'eth_sign' \
              'eth_signTransaction' 'personal_sign' 'eth_signTypedData'; do
  grep -q "$method" "$TMP/bridge.nc.swift" \
    && { echo "✗ VibenetBridge.swift requests $method — this must only ever read"; exit 1; }
done

# The redeploy note ("vibenet redeployed since you last checked") is only
# honest if a first-ever read stays silent — nothing stored yet means nothing
# to compare against, the AddressConnectionsSeen/ChipMemory rule. Without this
# guard the note could tell someone the network "redeployed" on their very
# first open, which is a claim about a past this device never observed.
grep -q 'enum VibenetSeenCommit' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetSeenCommit is missing — the redeploy note has nothing to compare against"; exit 1; }
grep -q 'guard let previous else { return false }' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetSeenCommit no longer stays silent on a first-ever read — it would report a redeploy on someone's very first open"; exit 1; }

echo "drift guards ✓"

# --- compile VibenetRoom.swift WHOLE, unmodified -----------------------------

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

// MARK: - Scope

print("VibenetScope — naming and the unknown-bit ceiling")
check("empty scope reads as a real state, not a blank",
      VibenetScope(raw: 0).summary == "No scope")
check("a single known bit",
      VibenetScope(raw: VibenetScope.sender).summary == "Sender")
check("every known bit, in the contract's own order",
      VibenetScope(raw: VibenetScope.known).summary
        == "Sender, Policy, Nonce, Self-payer, Sponsor-payer")
check("a reserved bit is COUNTED, never named",
      VibenetScope(raw: 0x0020).summary == "+1 unknown")
check("two reserved bits",
      VibenetScope(raw: 0x0020 | 0x0040).unknownCount == 2)
check("a known bit plus a reserved one names the known and counts the rest",
      VibenetScope(raw: VibenetScope.sender | 0x0020).summary == "Sender, +1 unknown")
check("names() carries no reserved bit",
      VibenetScope(raw: VibenetScope.sender | 0x0020).names == ["Sender"])
check("the highest bit is still just 'unknown', never invented",
      VibenetScope(raw: 0x8000).summary == "+1 unknown")

// MARK: - VibenetScope matrix (namedLabels / grantedFlags)

check("namedLabels are full words, in the contract's own order — never abbreviated",
      VibenetScope.namedLabels == ["Sender", "Policy", "Nonce", "Self-payer", "Sponsor-payer"])
check("grantedFlags is the SAME order as namedLabels, one bool per bit",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).grantedFlags
        == [true, false, false, true, false])
check("an empty scope's matrix column is all false, never a crash on an all-empty row",
      VibenetScope(raw: 0).grantedFlags == [false, false, false, false, false])
check("grantedCount counts named bits AND reserved ones — a bit we can't name is still a power",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer | 0x0020).grantedCount == 3)
// The card says what a bit MEANS; the probe says what the contract CALLS it.
// Both orders must stay the contract's own, so a column header and a probe
// line can never describe different bits by the same position.
check("plainLabels are what the bits mean, in the contract's own order",
      VibenetScope.plainLabels
        == ["Send any", "Send limited", "Nonce", "Pay own gas", "Pay others"])
check("the spec's constant names survive alongside them, for the probe",
      VibenetScope.namedLabels
        == ["Sender", "Policy", "Nonce", "Self-payer", "Sponsor-payer"])
check("plainSummary words a real grant in plain English",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).plainSummary
        == "Send any, Pay own gas")
check("an empty scope's plain summary is a real state, never a blank",
      VibenetScope(raw: 0).plainSummary == "No permissions")
check("a reserved bit is still counted, never named, in the plain wording too",
      VibenetScope(raw: VibenetScope.sender | 0x0020).plainSummary == "Send any, +1 unknown")
check("an empty scope reaches nothing",
      VibenetScope(raw: 0).grantedCount == 0)

// MARK: - Authenticator identity

print("")
print("VibenetAuthenticatorKind.identify — the five kinds, none invented")
let known = VibenetKnownAuthenticators(
    p256: "0x8130c89f65750431b564a4730397552a11cea256",
    webAuthn: "0x813007b6b1b48e75d91dec5927ab515d12a0f1d0",
    delegate: "0x8130b7d430d041ed4050935814d493299980ade1")
check("K1's fixed address",
      VibenetAuthenticatorKind.identify(authenticator: VibenetAuthenticatorKind.k1Address, known: known) == .secp256k1)
check("K1 matches case-insensitively",
      VibenetAuthenticatorKind.identify(authenticator: "0x0000000000000000000000000000000000000001".uppercased(), known: known) == .secp256k1)
check("the live P256 address",
      VibenetAuthenticatorKind.identify(authenticator: known.p256, known: known) == .p256)
check("the live P256 address, mixed case (an RPC's hex casing isn't a promise)",
      VibenetAuthenticatorKind.identify(authenticator: "0x8130C89F65750431b564A4730397552A11CEA256", known: known) == .p256)
check("the live WebAuthn address",
      VibenetAuthenticatorKind.identify(authenticator: known.webAuthn, known: known) == .webAuthn)
check("the live Delegate address",
      VibenetAuthenticatorKind.identify(authenticator: known.delegate, known: known) == .delegate)
check("an address matching none of the four is custom, never guessed further",
      VibenetAuthenticatorKind.identify(authenticator: "0x000000000000000000000000000000deadbeef", known: known) == .custom)
check("the zero address is not silently read as K1",
      VibenetAuthenticatorKind.identify(authenticator: VibenetAuthenticatorKind.zeroAddress, known: known) == .custom)
check("kind labels are real words",
      VibenetAuthenticatorKind.secp256k1.label == "secp256k1 key"
        && VibenetAuthenticatorKind.webAuthn.label == "Passkey"
        && VibenetAuthenticatorKind.custom.label == "Custom authenticator")

// MARK: - The actor log union — the sharpest arithmetic in the file

print("")
print("VibenetActorLog.survivors — last-write-wins, by CHRONOLOGY not array order")
func event(_ id: String, _ authorized: Bool, _ block: Int, _ logIndex: Int = 0) -> VibenetActorEvent {
    VibenetActorEvent(actorId: id, authorized: authorized, block: block, logIndex: logIndex)
}
check("a bare authorization survives",
      VibenetActorLog.survivors([event("a1", true, 100)]) == ["a1"])
check("authorize then revoke does NOT survive",
      VibenetActorLog.survivors([event("a1", true, 100), event("a1", false, 200)]).isEmpty)
check("revoke then REAUTHORIZE survives, fed in chronological order",
      VibenetActorLog.survivors([event("a1", false, 100), event("a1", true, 200)]) == ["a1"])
check("revoke then reauthorize survives even fed OUT OF ORDER (the whole point of sorting)",
      VibenetActorLog.survivors([event("a1", true, 200), event("a1", false, 100)]) == ["a1"])
check("log index breaks a same-block tie",
      VibenetActorLog.survivors([
        event("a1", true, 100, 1), event("a1", false, 100, 2),
      ]).isEmpty)
check("two actors are independent",
      VibenetActorLog.survivors([event("a1", true, 100), event("a2", false, 100)]) == ["a1"])
check("no events, no survivors", VibenetActorLog.survivors([]).isEmpty)

// MARK: - Roster order

print("")
print("VibenetAccountItem.orderedActors — the contract's own declaration order")
let a1 = VibenetActor(actorId: "z", authenticator: "0x1", kind: .custom,
                      scope: VibenetScope(raw: 0), expiry: 0)
let a2 = VibenetActor(actorId: "a", authenticator: "0x2", kind: .secp256k1,
                      scope: VibenetScope(raw: 0), expiry: 0)
let a3 = VibenetActor(actorId: "m", authenticator: "0x3", kind: .p256,
                      scope: VibenetScope(raw: 0), expiry: 0)
check("K1 leads, custom trails, regardless of actorId",
      VibenetAccountItem.orderedActors([a1, a3, a2]).map(\.actorId) == ["a", "m", "z"])

// MARK: - byReach — the matrix's column order

print("")
print("VibenetAccountItem.byReach — most-privileged key first")
// Deliberately the INVERSE of orderedActors' kind ranking, so a test that
// passes here for the wrong reason (both orders agreeing by accident) is
// impossible: the weakest kind carries the most power.
let weak   = VibenetActor(actorId: "a", authenticator: "0x1", kind: .secp256k1,
                          scope: VibenetScope(raw: VibenetScope.nonce), expiry: 0)
let strong = VibenetActor(actorId: "z", authenticator: "0x9", kind: .custom,
                          scope: VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer
                                                   | VibenetScope.sponsorPayer), expiry: 0)
check("the key that can do the most leads, even when its KIND ranks last",
      VibenetAccountItem.byReach([weak, strong]).first?.actorId == "z")
check("a tie in reach falls back to the kind order, so the column set stays TOTAL",
      VibenetAccountItem.byReach([a3, a2]).map(\.actorId) == ["a", "m"])
check("byReach over the same set twice agrees with itself",
      VibenetAccountItem.byReach([strong, a2, weak]).map(\.actorId)
        == VibenetAccountItem.byReach([a2, weak, strong]).map(\.actorId))

// MARK: - actorSummary

print("")
print("VibenetRoom.actorSummary")
check("no actors",
      VibenetRoom.actorSummary([]) == "No actors authorized")
check("one actor",
      VibenetRoom.actorSummary([a2]) == "1 secp256k1 key")
check("two of the same kind pluralize",
      VibenetRoom.actorSummary([a2, VibenetActor(actorId: "b", authenticator: "0x4",
                                                   kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)])
        == "2 secp256k1 keys")
check("mixed kinds, in the roster's own order",
      VibenetRoom.actorSummary([a2, a3]) == "1 secp256k1 key, 1 P-256 key")

// MARK: - rowLine — the "established but zero live actors" edge case

print("")
print("VibenetRoom.rowLine")
func account(address: String = "0x1234567890123456789012345678901234567890",
             reached: Bool = true, established: Bool = true, actors: [VibenetActor] = [],
             locked: Bool = false, hasInitiatedUnlock: Bool = false) -> VibenetAccountItem {
    VibenetAccountItem(address: address,
                       reached: reached, established: established, actors: actors,
                       locked: locked, hasInitiatedUnlock: hasInitiatedUnlock,
                       unlocksAt: nil, unlockDelay: nil)
}
// rowLine NEVER restates "Locked"/"Unlocking" — the badge already carries
// that, in bold, beside it — and it COUNTS the keys rather than naming them,
// because the matrix underneath spells every kind out in full the moment the
// row opens. Naming them here too printed the same five words twice, one
// wrapped line apart.
check("a locked account's row line is its key COUNT, not the word 'Locked' again",
      VibenetRoom.rowLine(account(actors: [a2], locked: true)) == "1 key")
check("several keys pluralize, and still never name a kind the matrix is about to name",
      VibenetRoom.rowLine(account(actors: [a1, a2, a3])) == "3 keys")
check("locked with no keys falls back to the same line an unlocked empty account gets",
      VibenetRoom.rowLine(account(locked: true, hasInitiatedUnlock: true)) == "No keys authorized")
check("unreached reads as unreached",
      VibenetRoom.rowLine(account(reached: false)) == "Couldn't reach the chain")
check("not established",
      VibenetRoom.rowLine(account(established: false)) == "Not established yet")
// THE edge case the feature brief calls out by name: established with NO
// live actors is a real, different state from never having been established
// at all, and must not be reported as the latter.
check("established but ZERO live actors reads as its own state, not 'not established'",
      VibenetRoom.rowLine(account(established: true, actors: [])) == "No keys authorized")
check("established with actors counts them",
      VibenetRoom.rowLine(account(established: true, actors: [a2])) == "1 key")

// MARK: - ordered — the one alarm this room can raise

print("")
print("VibenetRoom.ordered")
// Sorts AFTER every "quiet" fixture's address below, on purpose — an
// ordering bug that only ever ties on the address tie-break (both fixtures
// sharing `account()`'s default address) would pass by accident.
let locked = account(address: "0xzzzz000000000000000000000000000000zzzz", locked: true)
let quietA = VibenetAccountItem(address: "0xaaaa000000000000000000000000000000aaaa",
                                reached: true, established: true, actors: [],
                                locked: false, hasInitiatedUnlock: false,
                                unlocksAt: nil, unlockDelay: nil)
let quietB = VibenetAccountItem(address: "0xbbbb000000000000000000000000000000bbbb",
                                reached: true, established: true, actors: [],
                                locked: false, hasInitiatedUnlock: false,
                                unlocksAt: nil, unlockDelay: nil)
let unreached = VibenetAccountItem(address: "0xcccc000000000000000000000000000000cccc",
                                   reached: false, established: false, actors: [],
                                   locked: false, hasInitiatedUnlock: false,
                                   unlocksAt: nil, unlockDelay: nil)
check("a locked account leads even when it sorts last alphabetically",
      VibenetRoom.ordered([quietB, locked]).first?.address == locked.address)
check("an unreached read outranks a reached-but-quiet one",
      VibenetRoom.ordered([quietA, unreached]).first?.address == unreached.address)
check("ties break on address, alphabetically",
      VibenetRoom.ordered([quietB, quietA]).map(\.address) == [quietA.address, quietB.address])
check("ordering is TOTAL — a second pass over the same set agrees with the first",
      VibenetRoom.ordered([quietB, locked, unreached, quietA])
        == VibenetRoom.ordered([quietA, locked, unreached, quietB]))

// The matrix column headers are `shortLabel` — the ONE place a kind name
// must fit a narrow column. It stays a real word ("secp256k1", "Passkey"),
// never an abbreviation and never a glyph: both of those shipped once and
// both were undecodable on the device.
print("")
print("VibenetAuthenticatorKind.shortLabel — matrix column headers")
check("shortLabel is a real word, just without the key/authenticator suffix",
      VibenetAuthenticatorKind.secp256k1.shortLabel == "secp256k1"
        && VibenetAuthenticatorKind.custom.shortLabel == "Custom"
        && !VibenetAuthenticatorKind.secp256k1.shortLabel.contains("key"))

// The single-key sentence's own title — plain words over spec jargon, but
// each line is the WHOLE claim this build is willing to make.
print("")
print("VibenetAuthenticatorKind.plainTitle / plainDetail — meaning over jargon")
check("secp256k1 reads as a wallet key, not the scheme name",
      VibenetAuthenticatorKind.secp256k1.plainTitle == "Wallet key")
check("a delegate reads as another contract signing, not spec jargon",
      VibenetAuthenticatorKind.delegate.plainTitle == "Another contract")
check("P-256 names the CURVE only, never where a particular key lives",
      VibenetAuthenticatorKind.p256.plainDetail == "the curve passkeys and secure enclaves use")
check("an unidentified authenticator gets no invented detail",
      VibenetAuthenticatorKind.custom.plainDetail == nil)
check("every kind but custom carries a detail clause",
      [VibenetAuthenticatorKind.secp256k1, .p256, .webAuthn, .delegate]
        .allSatisfy { $0.plainDetail != nil })

// MARK: - headline / note

print("")
print("VibenetRoom.headline / note")
check("an unreachable config says so",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false))
        == "Couldn't read vibenet's current contracts")
check("nothing watched",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: true))
        == "Nothing watched on vibenet yet")
let oneLocked = VibenetRoom.compose(items: [locked], branch: "main", commit: "abc", configReached: true)
check("one locked account, singular",
      VibenetRoom.headline(oneLocked) == "1 watched account is locked")
let twoLocked = VibenetRoom.compose(items: [locked, account(locked: true)], branch: nil, commit: nil, configReached: true)
check("two locked accounts, plural",
      VibenetRoom.headline(twoLocked) == "2 watched accounts are locked")
let allUnreached = VibenetRoom.compose(items: [unreached], branch: nil, commit: "xyz", configReached: true)
check("every account unreached",
      VibenetRoom.headline(allUnreached) == "Couldn't reach vibenet for any watched account")
let notEstablished = VibenetRoom.compose(items: [account(established: false)], branch: nil, commit: nil, configReached: true)
check("reached, nothing established yet",
      VibenetRoom.headline(notEstablished) == "Not established yet")
let established = VibenetRoom.compose(items: [account(established: true, actors: [a2])], branch: nil, commit: nil, configReached: true)
check("one account, established",
      VibenetRoom.headline(established) == "1 account established on vibenet")

check("note states branch and commit",
      VibenetRoom.note(oneLocked) == "As of vibenet's main branch, commit abc")
check("note falls back to commit alone",
      VibenetRoom.note(allUnreached) == "As of vibenet commit xyz")
check("note falls back further with neither",
      VibenetRoom.note(twoLocked) == "Read live from vibenet — addresses redeploy often")
check("note over an unreachable config says so plainly",
      VibenetRoom.note(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false))
        .contains("redeploy"))

// A redeploy the device has already seen leads the note over the plain
// provenance line — the single most on-theme fact this room can report.
let redeployed = VibenetRoom.compose(items: [], branch: "main", commit: "def456789",
                                      configReached: true, redeployedSinceLastSeen: true)
check("a seen redeploy leads the note, not the plain provenance line",
      VibenetRoom.note(redeployed).contains("redeployed since you last checked"))
check("the redeploy note still carries the new commit",
      VibenetRoom.note(redeployed).contains("def456789"))
// A commit-less redeploy report can't happen from the real compose path (the
// bridge only ever flags a redeploy when it has a commit to compare), but a
// future caller getting that wrong must fall back to the plain line rather
// than draw a broken sentence with no commit in it.
let redeployedNoCommit = VibenetRoom.compose(items: [], branch: nil, commit: nil,
                                              configReached: true, redeployedSinceLastSeen: true)
check("a redeploy flag with no commit falls back to the plain note, never a broken sentence",
      VibenetRoom.note(redeployedNoCommit) == "Read live from vibenet — addresses redeploy often")

// MARK: - demoFixture — every state the card can draw, in one snapshot

print("")
print("VibenetRoom.demoFixture")
let demo = VibenetRoom.demoFixture()
check("four accounts, matching the four addresses DemoSeedAll seeds",
      demo.items.count == 4)
check("exactly two locked (one plain, one mid-unlock)",
      demo.lockedCount == 2)
check("all five nameable authenticator kinds appear somewhere in the roster",
      Set(demo.items.flatMap { $0.actors.map(\.kind) }) ==
        Set([.secp256k1, .p256, .webAuthn, .delegate, .custom]))
check("the roster's own unknown-scope actor reports an unknown count, never an invented name",
      demo.items.flatMap(\.actors).contains { $0.scope.unknownCount > 0 })
check("one account is reachable but not yet established",
      demo.items.contains { $0.reached && !$0.established })
check("the fixture reports its own redeploy, so the note shows it off too",
      VibenetRoom.note(demo).contains("redeployed since you last checked"))
check("at least one actor carries a future expiry — the matrix's own sub-label, otherwise never demoed",
      demo.items.flatMap(\.actors).contains { $0.expiry > UInt64(Date.now.timeIntervalSince1970) })
check("a single-actor account ALSO carries an expiry — singleKeyLine's own code path, not just the matrix's",
      demo.items.contains { $0.actors.count == 1 && ($0.actors.first?.expiry ?? 0) > 0 })
check("at least one account carries a non-nil changeSequences — the multichain footer line, otherwise never demoed",
      demo.items.contains { $0.changeSequences != nil })
check("R2: at least one account carries a multi-moment history — the strip's own dots, otherwise never demoed",
      demo.items.contains { $0.history.count > 1 })
check("R2: at least one account carries EXACTLY one history moment — the strip's no-strip floor",
      demo.items.contains { $0.history.count == 1 })
check("R2: at least one account has a key inside the 7-day urgency window — the collapsed row's own alarm",
      demo.items.contains { $0.urgentLine(now: .now)?.hasPrefix("Key expires") == true })

// MARK: - VibenetActor.expiryLabel / VibenetAccountItem.unlockLabel

print("")
print("VibenetActor.expiryLabel / unlockLabel — the two clocks that were read and thrown away")
let refNow = Date(timeIntervalSince1970: 1_000_000_000)
func actorWithExpiry(_ expiry: UInt64) -> VibenetActor {
    VibenetActor(actorId: "e", authenticator: "0x1", kind: .secp256k1,
                 scope: VibenetScope(raw: 0), expiry: expiry)
}
check("expiry == 0 is Keystore.sol's own convention for 'never', not a date",
      actorWithExpiry(0).expiryLabel(now: refNow) == "Never expires")
check("a future expiry counts down",
      actorWithExpiry(UInt64(refNow.timeIntervalSince1970) + 3600).expiryLabel(now: refNow)
        .hasPrefix("Expires"))
check("a past expiry reads as expired, not as a countdown that went negative",
      actorWithExpiry(UInt64(refNow.timeIntervalSince1970) - 3600).expiryLabel(now: refNow)
        .hasPrefix("Expired"))

check("no unlock initiated yet — the badge has nothing to count down to",
      account(locked: true, hasInitiatedUnlock: false).unlockLabel(now: refNow) == nil)
let readyItem = VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                                    locked: true, hasInitiatedUnlock: true,
                                    unlocksAt: UInt64(refNow.timeIntervalSince1970) - 60, unlockDelay: nil)
check("an unlock time already in the past reads as ready, not a negative countdown",
      readyItem.unlockLabel(now: refNow) == "Unlock ready")
let countingItem = VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                                       locked: true, hasInitiatedUnlock: true,
                                       unlocksAt: UInt64(refNow.timeIntervalSince1970) + 3600, unlockDelay: nil)
check("a future unlock time counts down",
      countingItem.unlockLabel(now: refNow)?.hasPrefix("Unlocks") == true)

// MARK: - VibenetAccountItem.unlockProgress — nil unless BOTH endpoints are known

print("")
print("VibenetAccountItem.unlockProgress — a bar with a guessed start is fake status, §83")
check("no unlock initiated — nothing to show a bar for",
      account(locked: true, hasInitiatedUnlock: false).unlockProgress(now: refNow) == nil)
check("unlocksAt known but unlockDelay missing — no start point, so no bar",
      countingItem.unlockProgress(now: refNow) == nil)
func unlockingItem(delaySeconds: UInt16, secondsIntoDelay: Double) -> VibenetAccountItem {
    // start = now - secondsIntoDelay (so `elapsed` at `now` is exactly
    // secondsIntoDelay); end = start + delay.
    let start = refNow.timeIntervalSince1970 - secondsIntoDelay
    let end = start + Double(delaySeconds)
    return VibenetAccountItem(address: "0x1", reached: true, established: true, actors: [],
                               locked: true, hasInitiatedUnlock: true,
                               unlocksAt: UInt64(end), unlockDelay: delaySeconds)
}
check("right at the start of the timelock reads as 0",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 0).unlockProgress(now: refNow) == 0)
check("right at the end reads as 1",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 3600).unlockProgress(now: refNow) == 1)
let midway = unlockingItem(delaySeconds: 3600, secondsIntoDelay: 1800).unlockProgress(now: refNow)
check("midway through reads as ~0.5",
      midway != nil && abs(midway! - 0.5) < 0.001)
check("clamped — never negative even if the delay reads slightly off",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: -600).unlockProgress(now: refNow) == 0)
check("clamped — never past 1 even past the unlock moment",
      unlockingItem(delaySeconds: 3600, secondsIntoDelay: 9000).unlockProgress(now: refNow) == 1)

// MARK: - VibenetAccountItem.urgentLine — R2.2, the collapsed row's own alarm clock

print("")
print("VibenetAccountItem.urgentLine — the time-critical fact surfaces before you open anything")
func itemWithExpiries(_ expiries: [UInt64]) -> VibenetAccountItem {
    let actors = expiries.enumerated().map { i, e in
        VibenetActor(actorId: "e\(i)", authenticator: "0x1", kind: .secp256k1,
                    scope: VibenetScope(raw: 0), expiry: e)
    }
    return VibenetAccountItem(address: "0x1", reached: true, established: true, actors: actors,
                              locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
}
let day = 86_400.0
check("nothing dated at all — no urgency to report",
      itemWithExpiries([0]).urgentLine(now: refNow) == nil)
check("a key expiring well outside the 7-day window says nothing",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 + 8 * day)]).urgentLine(now: refNow) == nil)
check("a key expiring inside the window leads the row",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 + 6 * day)]).urgentLine(now: refNow)?.hasPrefix("Key expires") == true)
// `.relative(presentation:)` formats against the REAL wall clock, not the
// `now:` PARAMETER — so two dates that are both merely "in the past
// relative to `refNow`" (a fixed 2001 timestamp) both print "N years ago"
// at real-world granularity and a text comparison can't tell them apart.
// Anchored to `Date.now` here for exactly that reason (`expiryLabel`'s own
// doc already names this; the demo fixture is the other sanctioned spot).
let liveNow = Date.now
let nearOnly = UInt64(liveNow.timeIntervalSince1970 + 1 * day)
let farOnly = UInt64(liveNow.timeIntervalSince1970 + 6 * day)
check("of two future expiries, the SOONEST wins — matches the near-only line, not the far-only one",
      itemWithExpiries([nearOnly, farOnly]).urgentLine(now: liveNow) == itemWithExpiries([nearOnly]).urgentLine(now: liveNow)
        && itemWithExpiries([nearOnly, farOnly]).urgentLine(now: liveNow) != itemWithExpiries([farOnly]).urgentLine(now: liveNow))
check("a ticking clock outranks an already-expired key on the same account",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day),
                        UInt64(refNow.timeIntervalSince1970 + 2 * day)])
        .urgentLine(now: refNow)?.hasPrefix("Key expires") == true)
check("nothing ticking, one already expired — counted, singular",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day)]).urgentLine(now: refNow) == "1 key expired")
check("nothing ticking, several expired — counted, plural",
      itemWithExpiries([UInt64(refNow.timeIntervalSince1970 - day),
                        UInt64(refNow.timeIntervalSince1970 - 2 * day)])
        .urgentLine(now: refNow) == "2 keys expired")
check("expiry == 0 (Keystore's own 'never') never counts toward either half",
      itemWithExpiries([0, UInt64(refNow.timeIntervalSince1970 - day)]).urgentLine(now: refNow) == "1 key expired")

// MARK: - VibenetKeyHistory — R2.1, the account's own story as a sequence strip

print("")
print("VibenetKeyHistory — a SEQUENCE strip, never a time-proportional axis")
func moment(_ block: Int, _ logIndex: Int, authorized: Bool, date: Date? = nil) -> VibenetKeyMoment {
    VibenetKeyMoment(block: block, logIndex: logIndex, authorized: authorized, kind: authorized ? .secp256k1 : nil, date: date)
}
let unordered = [moment(5, 1, authorized: true), moment(5, 0, authorized: false), moment(3, 0, authorized: true)]
check("ordered is TOTAL — block first, then logIndex — a second pass agrees with the first",
      VibenetKeyHistory.ordered(unordered).map(\.id) == VibenetKeyHistory.ordered(VibenetKeyHistory.ordered(unordered)).map(\.id))
check("ordered sorts by block then logIndex, oldest first",
      VibenetKeyHistory.ordered(unordered).map { "\($0.block),\($0.logIndex)" } == ["3,0", "5,0", "5,1"])

check("summaryLine is nil when there is nothing to summarize",
      VibenetKeyHistory.summaryLine([]) == nil)
check("summaryLine counts adds alone, singular",
      VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true)]) == "1 key added")
check("summaryLine counts both halves, correct plurals, added leads",
      VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true), moment(2, 0, authorized: true),
                                     moment(3, 0, authorized: false)]) == "2 keys added · 1 revoked")
check("summaryLine omits a zero half rather than saying '0 revoked'",
      !VibenetKeyHistory.summaryLine([moment(1, 0, authorized: true)])!.contains("revoked"))

let refDate = Date(timeIntervalSince1970: 2_000_000_000)
// Live-anchored (the same reason `urgentLine`'s soonest-wins test is,
// above): `.relative` formats against the REAL wall clock, and two
// `refDate`-relative endpoints only 8 days apart both round to the same
// "N years ago" at that granularity — collapsing `newest` to nil for a
// reason that has nothing to do with the function under test.
let liveDated = [moment(1, 0, authorized: true, date: liveNow.addingTimeInterval(-10 * day)),
                 moment(2, 0, authorized: false, date: liveNow.addingTimeInterval(-2 * day))]
let liveLabels = VibenetKeyHistory.endpointLabels(liveDated, now: liveNow)
check("endpointLabels resolves both real endpoints, distinctly",
      liveLabels.oldest != nil && liveLabels.newest != nil && liveLabels.oldest != liveLabels.newest)
check("an endpoint with no date is omitted, never guessed",
      VibenetKeyHistory.endpointLabels([moment(1, 0, authorized: true, date: nil),
                                        moment(2, 0, authorized: false, date: refDate)],
                                       now: refDate).oldest == nil)
check("a single moment's newest label collapses to nil rather than repeating the oldest",
      VibenetKeyHistory.endpointLabels([moment(1, 0, authorized: true, date: refDate)], now: refDate).newest == nil)
check("newest wraps the newest cap-worth of events, chronologically ordered",
      VibenetKeyHistory.newest([VibenetActorEvent(actorId: "a", authorized: true, block: 1, logIndex: 0),
                                VibenetActorEvent(actorId: "b", authorized: true, block: 2, logIndex: 0),
                                VibenetActorEvent(actorId: "c", authorized: true, block: 3, logIndex: 0)],
                               cap: 2).map(\.block) == [2, 3])

// MARK: - VibenetChangeSequences.chips — R2.3

print("")
print("VibenetChangeSequences.chips — number-hero chips, replacing the single-chain sentence")
let cs = VibenetChangeSequences(multichain: 12, localEpoch: 2, localSequence: 5)
check("two chips, multichain first",
      cs.chips.map(\.value) == ["12", "5"])
check("a zero standing is a real reading, never hidden",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 0).chips.map(\.value) == ["0", "0"])
check("labels carry the epoch, not just a bare 'local'",
      cs.chips[1].label.contains("2"))

// MARK: - VibenetMultichainSync

print("")
print("VibenetMultichainSync — honestly a one-chain reading until 8130 has a second live chain")
let oneChain = [VibenetChainStanding(chainName: "vibenet",
                                     sequences: VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 3))]
check("with one chain there is nothing to compare — never guesses at a sync gap",
      VibenetMultichainSync.summary(oneChain) == "Only one EIP-8130 chain to compare — nothing to sync yet")
check("laggingChains is empty below two chains, the same honesty rule",
      VibenetMultichainSync.laggingChains(oneChain).isEmpty)

let leader = VibenetChainStanding(chainName: "vibenet",
                                  sequences: VibenetChangeSequences(multichain: 5, localEpoch: 0, localSequence: 5))
let laggard = VibenetChainStanding(chainName: "sepolia-8130",
                                   sequences: VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 3))
check("a chain behind the leading multichain count is named as lagging",
      VibenetMultichainSync.laggingChains([leader, laggard]).map(\.chainName) == ["sepolia-8130"])
check("summary counts the lagging chains, singular wording",
      VibenetMultichainSync.summary([leader, laggard])
        == "1 chain hasn't applied the latest multichain change yet")
let caughtUp = VibenetChainStanding(chainName: "sepolia-8130",
                                    sequences: VibenetChangeSequences(multichain: 5, localEpoch: 0, localSequence: 1))
check("two chains at the same multichain count read as fully caught up",
      VibenetMultichainSync.summary([leader, caughtUp]).hasPrefix("Every chain has applied"))

// MARK: - VibenetEventKind — the feed-landing titles

print("")
print("VibenetEventKind.title — the feed's own door into this room")
check("a new key lands with its resolved kind when one was confirmed",
      VibenetEventKind.actorAuthorized.title(shortAddress: "…0b1c", keyLabel: "secp256k1 key")
        == "New secp256k1 key authorized for …0b1c")
check("a new key still lands honestly with no invented kind when the re-read couldn't confirm one",
      VibenetEventKind.actorAuthorized.title(shortAddress: "…0b1c", keyLabel: nil)
        == "New key authorized for …0b1c")
check("a revocation names no kind at all — the key that's gone isn't re-read to find one",
      VibenetEventKind.actorRevoked.title(shortAddress: "…0b1c", keyLabel: "secp256k1 key")
        == "Key revoked for …0b1c")
check("a lock event",
      VibenetEventKind.locked.title(shortAddress: "…0b1c", keyLabel: nil) == "…0b1c locked on vibenet")

// MARK: - shortAddress

print("")
print("VibenetRoom.shortAddress")
check("a real address is tail-only elided — one truncation, not two",
      VibenetRoom.shortAddress("0x8130931874c894ac4963e128d6273ae520dafa57") == "…fa57")
check("a short string passes through untouched",
      VibenetRoom.shortAddress("0xabc") == "0xabc")

print("")
if failures == 0 {
    print("✓ vibenet self-test: all assertions passed")
} else {
    print("✗ vibenet self-test: \(failures) assertion(s) failed")
    exit(1)
}
SWIFT

echo "Assertions"
if ! swiftc -O -o "$TMP/run" "$ROOM" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ VibenetRoom.swift did not compile with the harness"
  tail -25 "$TMP/build.log"
  exit 1
fi
"$TMP/run"

# --- mutations — a check that cannot fail proves nothing ---------------------

echo ""
echo "Mutations (each must be caught)"

mutate() { # mutate <name> <from> <to>
  local name="$1" from="$2" to="$3"
  local target="$TMP/m-room.swift"
  cp "$ROOM" "$target"
  if ! MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# A revoked actorId reading as live is the sharpest possible failure here —
# it would tell someone a key can still act for an account when it can't.
mutate "a revoked actorId must NOT survive its own revoke" \
  'return Set(latest.filter(\.value).map(\.key))' \
  'return Set(latest.map(\.key))'

# Without the sort, the union trusts whatever order the RPC happened to
# return logs in, which is not a promise `eth_getLogs` makes.
mutate "survivorship must be decided by CHRONOLOGY, not array order" \
  'let chronological = events.sorted { ($0.block, $0.logIndex) < ($1.block, $1.logIndex) }' \
  'let chronological = events'

# A reserved scope bit silently counted as a KNOWN one is exactly the
# invented permission this file's whole design refuses to state.
mutate "a reserved scope bit must never be folded into the known set" \
  'static let known: UInt16 = sender | policy | nonce | selfPayer | sponsorPayer' \
  'static let known: UInt16 = sender | policy | nonce | selfPayer | sponsorPayer | 0x0020'

# The one alarm this room can raise must actually lead the card.
# The matrix's columns are ranked by REACH so the most-privileged key is
# read first. Inverted, the card leads with the key that can do the LEAST —
# which renders perfectly and buries the one worth looking at.
mutate "the matrix must lead with the key that can do the MOST" \
  'return a.scope.grantedCount > b.scope.grantedCount' \
  'return a.scope.grantedCount < b.scope.grantedCount'

mutate "a locked account must rank first" \
  'if a.alarmed != b.alarmed { return a.alarmed }' \
  'if false { return a.alarmed }'

# The edge case named in the feature brief: dropping this guard collapses
# "established with nothing authorized" into "not established at all".
mutate "established-with-no-actors must not read as not-established" \
  'guard item.established else { return String(localized: "Not established yet") }' \
  ' '

# The clamp is the whole reason unlockProgress is safe to draw as a bar —
# without it a delay measured slightly wrong by the chain draws past either
# end of the track.
mutate "unlockProgress must clamp — never draw past either end of the bar" \
  'return min(1, max(0, elapsed / total))' \
  'return elapsed / total'

# A detail clause on `.custom` would be an invented fact about an
# authenticator this build could never actually identify.
mutate "an unidentified authenticator must never get an invented detail clause" \
  'case .custom:    nil' \
  'case .custom:    String(localized: "unknown")'

# The row's own alarm clock must lead with the SOONEST ticking key, not the
# LATEST — a swap here buries the key someone actually needs to act on
# behind one that has months left.
mutate "urgentLine must pick the SOONEST future expiry, never the latest" \
  '.min()' \
  '.max()'

# Without the logIndex tiebreak, two events in the SAME block sort however
# the array happened to arrive — the strip reshuffling between opens over
# an unchanged history is exactly the fault ordering exists to prevent.
mutate "VibenetKeyHistory.ordered must break ties by logIndex, not array order" \
  'if $0.logIndex != $1.logIndex { return $0.logIndex < $1.logIndex }' \
  'if false { return $0.logIndex < $1.logIndex }'

# Counting a revocation as an addition would tell someone their roster grew
# when a key was actually taken away — the sharpest possible wrong reading
# of a security-relevant summary line.
mutate "summaryLine must count adds and revokes separately, never conflate them" \
  'let added = moments.filter(\.authorized).count' \
  'let added = moments.count'

# Swapping the chip order puts the local-epoch count where the cross-chain
# count belongs — the two numbers mean structurally different things
# (§the EIP's own split) and reading the wrong one as the other is a real
# misreading, not a cosmetic reorder.
mutate "VibenetChangeSequences.chips must lead with multichain, not local" \
  '[(String(multichain), String(localized: "cross-chain changes")),' \
  '[(String(localSequence), String(localized: "cross-chain changes")),'

echo ""
echo "✓ vibenet-selftest: drift guards, assertions and mutations all passed"
