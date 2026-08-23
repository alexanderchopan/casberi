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
check("locked leads over everything else",
      VibenetRoom.rowLine(account(actors: [a2], locked: true)) == "Locked")
check("locked + unlock initiated says so",
      VibenetRoom.rowLine(account(locked: true, hasInitiatedUnlock: true)) == "Locked — unlock initiated")
check("unreached reads as unreached",
      VibenetRoom.rowLine(account(reached: false)) == "Couldn't reach the chain")
check("not established",
      VibenetRoom.rowLine(account(established: false)) == "Not established yet")
// THE edge case the feature brief calls out by name: established with NO
// live actors is a real, different state from never having been established
// at all, and must not be reported as the latter.
check("established but ZERO live actors reads as its own state, not 'not established'",
      VibenetRoom.rowLine(account(established: true, actors: [])) == "No actors authorized")
check("established with actors reads the roster",
      VibenetRoom.rowLine(account(established: true, actors: [a2])) == "1 secp256k1 key")

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

// MARK: - shortAddress

print("")
print("VibenetRoom.shortAddress")
check("a real address is middle-elided",
      VibenetRoom.shortAddress("0x8130931874c894ac4963e128d6273ae520dafa57") == "0x8130…fa57")
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
mutate "a locked account must rank first" \
  'if a.alarmed != b.alarmed { return a.alarmed }' \
  'if false { return a.alarmed }'

# The edge case named in the feature brief: dropping this guard collapses
# "established with nothing authorized" into "not established at all".
mutate "established-with-no-actors must not read as not-established" \
  'guard item.established else { return String(localized: "Not established yet") }' \
  ' '

echo ""
echo "✓ vibenet-selftest: drift guards, assertions and mutations all passed"
