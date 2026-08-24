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
#     — VibenetAccountMapping.links       (the delegate-mapping, 2026-08-24)
#     — VibenetKeyAggregation.compose     (the room-wide key summary, 2026-08-24)
#     — VibenetBalanceFormat.line         (balance display, never USD, 2026-08-24)
#     — VibenetBalanceAggregation.compose (the feed room's own stat block, 2026-08-24)
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

# Balances (2026-08-24): decimals must be READ LIVE off the chain, never
# assumed — this codebase has been burned by hardcoding ERC-20 decimals
# twice already (Solana SPL, Gnosis Pay's USDCe being 6 not 18).
grep -q 'VibenetABI.decimalsCall' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetBridge.swift no longer reads decimals() for USDV/NFV — a hardcoded scale would repeat the SOL-decimals bug"; exit 1; }
grep -q 'guard (0...36).contains(value) else { return nil }' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetTokenDecimals no longer refuses an implausible decimals() answer — a reverted call could silently scale a balance by 10^0"; exit 1; }
# The native balance is the ONE reading safe to hardcode at 18 decimals —
# an EVM-wide constant, not a per-token guess — so its own scale must
# still be present and distinct from the live-read USDV/NFV path above.
grep -q '/ 1e18' "$TMP/bridge.nc.swift" \
  || { echo "✗ VibenetBridge.swift no longer scales the native balance by 18 decimals"; exit 1; }
# `nativeBalance` must stay OPTIONAL, nil-defaulted — a failed read and a
# genuine zero balance must never look the same (§83).
grep -q 'nativeBalance: Double? = nil' "$TMP/room.nc.swift" \
  || { echo "✗ VibenetAccountItem.nativeBalance is no longer optional/nil-defaulted — a failed read could no longer be told apart from a real zero"; exit 1; }
# Never invent a dollar figure for a devnet token with no real market
# price (§83) — reads COMMENT-STRIPPED copies, since this rule is
# documented by name in the source (the Obsidian/Cursor lesson).
if grep -q 'WalletValue.money\|priceUSD\|usdValue' "$TMP/bridge.nc.swift" "$TMP/room.nc.swift"; then
  echo "✗ a vibenet file appears to price a balance in USD — these are devnet tokens with no real market price (§83)"
  exit 1
fi

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

// MARK: - VibenetScope.grantedCount — byReach's ranking key

check("grantedCount counts named bits AND reserved ones — a bit we can't name is still a power",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer | 0x0020).grantedCount == 3)
check("plainSummary words a real grant in plain English",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).plainSummary
        == "Send any, Pay own gas")
check("an empty scope's plain summary is a real state, never a blank",
      VibenetScope(raw: 0).plainSummary == "No permissions")
check("a reserved bit is still counted, never named, in the plain wording too",
      VibenetScope(raw: VibenetScope.sender | 0x0020).plainSummary == "Send any, +1 unknown")
check("an empty scope reaches nothing",
      VibenetScope(raw: 0).grantedCount == 0)

// MARK: - VibenetScope.grantedPlainLabels — R3.1, the matrix's replacement

print("")
print("VibenetScope.grantedPlainLabels — one chip per granted permission, replacing the matrix")
check("a real grant yields one chip label per permission, in the contract's own order",
      VibenetScope(raw: VibenetScope.sender | VibenetScope.selfPayer).grantedPlainLabels
        == ["Send any", "Pay own gas"])
check("an empty scope yields no chips at all — the caller draws its own sentence instead",
      VibenetScope(raw: 0).grantedPlainLabels.isEmpty)
check("a reserved bit appends ONE trailing '+N unknown' label, never an invented name",
      VibenetScope(raw: VibenetScope.sender | 0x0020).grantedPlainLabels == ["Send any", "+1 unknown"])
check("several reserved bits still collapse to ONE trailing chip, plural",
      VibenetScope(raw: VibenetScope.sender | 0x0020 | 0x0040).grantedPlainLabels == ["Send any", "+2 unknown"])
check("reserved bits alone (nothing named) still yield exactly one chip",
      VibenetScope(raw: 0x0020).grantedPlainLabels == ["+1 unknown"])

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

// MARK: - VibenetLogChunking.ranges — the RPC's 100,000-block ceiling, walked correctly

print("")
print("VibenetLogChunking.ranges — MEASURED 2026-08-23: the RPC refuses a wider eth_getLogs window")
check("a chain shorter than one range needs exactly one chunk, covering genesis to tip",
      VibenetLogChunking.ranges(tip: 500, maxRange: 100_000, maxChunks: 50).map { "\($0.from)-\($0.to)" }
        == ["0-500"])
check("a chain exactly as tall as the range still needs only one chunk",
      VibenetLogChunking.ranges(tip: 99_999, maxRange: 100_000, maxChunks: 50).map { "\($0.from)-\($0.to)" }
        == ["0-99999"])
let overByOne = VibenetLogChunking.ranges(tip: 100_000, maxRange: 100_000, maxChunks: 50)
check("one block past the range needs a SECOND chunk, walked tip-backward",
      overByOne.map { "\($0.from)-\($0.to)" } == ["1-100000", "0-0"])
check("no gaps and no overlaps across chunks — every block from genesis to tip covered exactly once",
      overByOne.reduce(0) { $0 + ($1.to - $1.from + 1) } == 100_001)
let real = VibenetLogChunking.ranges(tip: 285_133, maxRange: 100_000, maxChunks: 50)
check("the live chain height measured this session needs exactly 3 chunks",
      real.count == 3)
check("chunks are walked NEWEST first — a just-authorized key is always inside the first chunk read",
      real.first?.to == 285_133)
check("the LAST chunk always reaches genesis",
      real.last?.from == 0)
check("the chunk-count breaker is real — a chain far taller than maxChunks × maxRange truncates rather than looping forever",
      VibenetLogChunking.ranges(tip: 10_000_000, maxRange: 100_000, maxChunks: 5).count == 5)
check("a truncated walk still starts at the tip — the newest history is never what's dropped",
      VibenetLogChunking.ranges(tip: 10_000_000, maxRange: 100_000, maxChunks: 5).first?.to == 10_000_000)
check("nonsense inputs (negative tip, zero range) return no ranges rather than looping or crashing",
      VibenetLogChunking.ranges(tip: -1, maxRange: 100_000, maxChunks: 50).isEmpty
        && VibenetLogChunking.ranges(tip: 500, maxRange: 0, maxChunks: 50).isEmpty)

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
print("VibenetRoom.headline / note — the lead-based shape (2026-08-23, the ASCRoom precedent)")
let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
check("an unreachable config says so",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false), now: fixedNow)
        == "Couldn't read vibenet's current contracts")
check("nothing watched",
      VibenetRoom.headline(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: true), now: fixedNow)
        == "Nothing watched on vibenet yet")
let oneLocked = VibenetRoom.compose(items: [locked], branch: "main", commit: "abc", configReached: true)
check("the lead's own address and state, no rolled-up count",
      VibenetRoom.headline(oneLocked, now: fixedNow) == "…zzzz · Locked")
let twoLocked = VibenetRoom.compose(items: [locked, account(locked: true)], branch: nil, commit: nil, configReached: true)
check("two locked accounts still name only the LEAD — ordered's own address tie-break decides which",
      VibenetRoom.headline(twoLocked, now: fixedNow) == "…7890 · Locked")
// The reported case, now moot by construction: the card's hero used to draw
// EVERY watched face while the sentence counted only the locked ones, which
// read as a contradiction. There is no hero stack and no rolled-up count
// anymore — the headline names the ONE account it's actually about.
let twoOfFour = VibenetRoom.compose(
    items: [locked, account(locked: true), account(address: "0xaaa"), account(address: "0xbbb")],
    branch: nil, commit: nil, configReached: true)
check("a bigger room still leads with the same one account — size never changes WHO leads",
      VibenetRoom.headline(twoOfFour, now: fixedNow) == "…7890 · Locked")

// MARK: - VibenetRoom.scoped — the face rail narrows the CARD, as wallet's does
check("no pick leaves the room whole",
      twoOfFour.scoped(to: nil).items.count == 4)
check("a pick narrows the card to that one account",
      twoOfFour.scoped(to: "0xaaa").items.map(\.address) == ["0xaaa"])
check("scoping is case-insensitive — a watch list may hold any case",
      twoOfFour.scoped(to: "0xAAA").items.count == 1)
check("an address no longer watched scopes to NOTHING, never silently to everything",
      twoOfFour.scoped(to: "0xdead").items.isEmpty)
// Scoping to the alarmed account's OWN address collapses the room to just
// its lead — the mechanism the card's "click one you see one" relies on.
check("scoping to the locked account leaves it as its own lead",
      twoOfFour.scoped(to: "0xzzzz000000000000000000000000000000zzzz").lead?.address
        == "0xzzzz000000000000000000000000000000zzzz")

let allUnreached = VibenetRoom.compose(items: [unreached], branch: nil, commit: "xyz", configReached: true)
check("an unreached lead says so, in the same slot a locked one's state would sit",
      VibenetRoom.headline(allUnreached, now: fixedNow) == "…cccc · Couldn't reach the chain")
let notEstablished = VibenetRoom.compose(items: [account(established: false)], branch: nil, commit: nil, configReached: true)
check("reached, nothing established yet",
      VibenetRoom.headline(notEstablished, now: fixedNow) == "…7890 · Not established yet")
let established = VibenetRoom.compose(items: [account(established: true, actors: [a2])], branch: nil, commit: nil, configReached: true)
check("an established lead states its key count",
      VibenetRoom.headline(established, now: fixedNow) == "…7890 · 1 key")

// The lead's own clock — appended as a THIRD clause, never invented for an
// account with nothing ticking. `.relative(presentation:)` formats against
// the REAL wall clock, never the `now:` PARAMETER (see `urgentLine`'s own
// tests below for why `fixedNow`, a fixed 2023 timestamp, can't anchor
// these two — it would print "N years ago" against today's real clock) —
// so these anchor on `Date.now` and check a PREFIX, the same shape every
// other relative-time assertion in this file already uses.
let headlineLiveNow = Date.now
let futureExpiry = UInt64(headlineLiveNow.timeIntervalSince1970) + 2 * 86_400
let expiringActor = VibenetActor(actorId: "e", authenticator: "0x9", kind: .secp256k1,
                                 scope: VibenetScope(raw: 0), expiry: futureExpiry)
let expiringLead = VibenetRoom.compose(items: [account(established: true, actors: [expiringActor])],
                                       branch: nil, commit: nil, configReached: true)
check("an established lead with a key inside the urgency window appends its own expiry",
      VibenetRoom.headline(expiringLead, now: headlineLiveNow).hasPrefix("…7890 · 1 key · Key expires"))
let unlockingLead = VibenetAccountItem(
    address: "0x1234567890123456789012345678901234567890",
    reached: true, established: true, actors: [], locked: true, hasInitiatedUnlock: true,
    unlocksAt: UInt64(headlineLiveNow.timeIntervalSince1970) + 3600, unlockDelay: 7200)
let unlockingRoom = VibenetRoom.compose(items: [unlockingLead], branch: nil, commit: nil, configReached: true)
check("an unlocking lead appends its own countdown, ahead of any key expiry",
      VibenetRoom.headline(unlockingRoom, now: headlineLiveNow).hasPrefix("…7890 · Unlocking · Unlocks"))

check("note states branch and commit — no hidden-count clause when nothing is hidden",
      VibenetRoom.note(oneLocked, drawn: oneLocked.items.count) == "As of vibenet's main branch, commit abc")
check("note falls back to commit alone",
      VibenetRoom.note(allUnreached, drawn: allUnreached.items.count) == "As of vibenet commit xyz")
check("note falls back further with neither",
      VibenetRoom.note(twoLocked, drawn: twoLocked.items.count) == "Read live from vibenet — addresses redeploy often")
check("note over an unreachable config says so plainly, regardless of drawn count",
      VibenetRoom.note(VibenetRoom.compose(items: [], branch: nil, commit: nil, configReached: false), drawn: 0)?
        .contains("redeploy") == true)
// The ASCRoom shape this was built from: how many more aren't drawn, joined
// ahead of the provenance fragment.
check("a capped room states how many more are watched, joined ahead of the provenance",
      VibenetRoom.note(twoOfFour, drawn: 2) == "2 more watched · Read live from vibenet — addresses redeploy often")
check("a singular hidden count doesn't pluralize",
      VibenetRoom.note(twoOfFour, drawn: 3) == "1 more watched · Read live from vibenet — addresses redeploy often")

// A redeploy the device has already seen leads the note over the plain
// provenance line — the single most on-theme fact this room can report.
let redeployed = VibenetRoom.compose(items: [], branch: "main", commit: "def456789",
                                      configReached: true, redeployedSinceLastSeen: true)
check("a seen redeploy leads the note, not the plain provenance line",
      VibenetRoom.note(redeployed, drawn: 0)?.contains("vibenet redeployed") == true)
check("the redeploy note still carries the new commit",
      VibenetRoom.note(redeployed, drawn: 0)?.contains("def456789") == true)
// A commit-less redeploy report can't happen from the real compose path (the
// bridge only ever flags a redeploy when it has a commit to compare), but a
// future caller getting that wrong must fall back to the plain line rather
// than draw a broken sentence with no commit in it.
let redeployedNoCommit = VibenetRoom.compose(items: [], branch: nil, commit: nil,
                                              configReached: true, redeployedSinceLastSeen: true)
check("a redeploy flag with no commit falls back to the plain note, never a broken sentence",
      VibenetRoom.note(redeployedNoCommit, drawn: 0) == "Read live from vibenet — addresses redeploy often")

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
      VibenetRoom.note(demo, drawn: demo.items.count)?.contains("vibenet redeployed") == true)
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
check("the demo carries one real watched-to-watched delegate link — otherwise the mapping section never demos",
      VibenetAccountMapping.links(demo.items).count == 1)
check("the demo's aggregate key summary is non-nil — otherwise that section never demos either",
      VibenetKeyAggregation.compose(demo.items, now: .now) != nil)

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

// MARK: - VibenetChangeSequences.plainLine — the sentence that replaced the chips

print("")
print("VibenetChangeSequences.plainLine — English, or silence")
check("nothing changed at all says NOTHING — a stat of two zeros has no reading",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 0).plainLine == nil)
check("this chain only, once — singular",
      VibenetChangeSequences(multichain: 0, localEpoch: 0, localSequence: 1).plainLine
        == "Changed once, on this chain only")
check("this chain only, several — plural",
      VibenetChangeSequences(multichain: 0, localEpoch: 1, localSequence: 4).plainLine
        == "Changed 4 times, on this chain only")
check("shared across chains, once — singular",
      VibenetChangeSequences(multichain: 1, localEpoch: 0, localSequence: 0).plainLine
        == "Changed once, shared across chains")
check("both kinds names both, never silently drops one",
      VibenetChangeSequences(multichain: 3, localEpoch: 0, localSequence: 2).plainLine
        == "Changed 2 times here, 3 shared across chains")

// MARK: - VibenetKeyHistory.isSequence — dots only when there IS an order

print("")
print("VibenetKeyHistory.isSequence — two keys in ONE transaction are one moment, not two")
check("two moments sharing a block are NOT a sequence — no order to draw",
      !VibenetKeyHistory.isSequence([moment(204532, 0, authorized: true),
                                     moment(204532, 1, authorized: true)]))
check("two moments in different blocks ARE a sequence",
      VibenetKeyHistory.isSequence([moment(204532, 0, authorized: true),
                                    moment(204999, 0, authorized: false)]))
check("a lone moment is never a sequence",
      !VibenetKeyHistory.isSequence([moment(1, 0, authorized: true)]))
check("no moments at all is never a sequence",
      !VibenetKeyHistory.isSequence([]))

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

// MARK: - VibenetAccountMapping.links — the ONE real account-to-account signal

print("")
print("VibenetAccountMapping.links")
func delegateActor(to authenticator: String, actorId: String = "d") -> VibenetActor {
    VibenetActor(actorId: actorId, authenticator: authenticator, kind: .delegate,
                 scope: VibenetScope(raw: 0), expiry: 0)
}
let alice = "0xa1"
let bob = "0xb2"
let carol = "0xc3"
let stranger = "0xdead"

check("no items at all — nothing to derive a mapping from",
      VibenetAccountMapping.links([]).isEmpty)

let aliceDelegatesToBob = account(address: alice, actors: [delegateActor(to: bob)])
let bobPlain = account(address: bob)
check("a delegate authenticator matching a WATCHED account produces a link",
      VibenetAccountMapping.links([aliceDelegatesToBob, bobPlain])
        == [VibenetDelegateLink(from: alice, to: bob)])

let aliceDelegatesToStranger = account(address: alice, actors: [delegateActor(to: stranger)])
check("a delegate authenticator matching NO watched account produces no link — never fabricated",
      VibenetAccountMapping.links([aliceDelegatesToStranger, bobPlain]).isEmpty)

let aliceHoldsAPlainKeyPointingAtBob = account(address: alice, actors: [
    VibenetActor(actorId: "k", authenticator: bob, kind: .secp256k1,
                 scope: VibenetScope(raw: 0), expiry: 0)])
check("a non-delegate actor never produces a link, however its authenticator reads",
      VibenetAccountMapping.links([aliceHoldsAPlainKeyPointingAtBob, bobPlain]).isEmpty)

let aliceDelegatesToUppercasedBob = account(address: alice, actors: [delegateActor(to: bob.uppercased())])
check("the compare is case-insensitive — an RPC's hex casing is not a promise",
      VibenetAccountMapping.links([aliceDelegatesToUppercasedBob, bobPlain])
        == [VibenetDelegateLink(from: alice, to: bob)])

// Order must be TOTAL — a mapping section that reshuffles between opens
// over an unchanged room reads as broken, the standard every roster here
// already holds.
let bobDelegatesToAlice = account(address: bob, actors: [delegateActor(to: alice, actorId: "e")])
let carolDelegatesToAlice = account(address: carol, actors: [delegateActor(to: alice, actorId: "f")])
let alicePlain = account(address: alice)
check("links sort by `from`, then `to`, regardless of input order",
      VibenetAccountMapping.links([carolDelegatesToAlice, bobDelegatesToAlice, alicePlain])
        == [VibenetDelegateLink(from: bob, to: alice), VibenetDelegateLink(from: carol, to: alice)])

// MARK: - VibenetKeyAggregation.compose — the room-wide key summary

print("")
print("VibenetKeyAggregation.compose")
let refNowAgg = Date(timeIntervalSince1970: 1_000_000_000)
check("an empty room has nothing to aggregate — the empty state this codebase omits rather than shows",
      VibenetKeyAggregation.compose([], now: refNowAgg) == nil)
check("an account with no actors contributes nothing — still nil",
      VibenetKeyAggregation.compose([account(actors: [])], now: refNowAgg) == nil)

let ak1 = VibenetActor(actorId: "1", authenticator: "0x1", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)
let ak2 = VibenetActor(actorId: "2", authenticator: "0x2", kind: .p256, scope: VibenetScope(raw: 0), expiry: 0)
let ak3 = VibenetActor(actorId: "3", authenticator: "0x3", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)
let roomA = account(address: "0xa", actors: [ak1, ak2])
let roomB = account(address: "0xb", actors: [ak3])
let agg = VibenetKeyAggregation.compose([roomA, roomB], now: refNowAgg)
check("total counts every actor across every account",
      agg?.total == 3)
check("accountCount only counts accounts that contribute at least one key",
      agg?.accountCount == 2)
check("byKind counts within each kind",
      agg?.byKind.first(where: { $0.kind == .secp256k1 })?.count == 2)
check("an account holding NO keys is excluded from accountCount",
      VibenetKeyAggregation.compose([roomA, account(address: "0xc", actors: [])], now: refNowAgg)?.accountCount == 1)
check("plainLine spans several accounts",
      agg?.plainLine == "3 keys authorized across 2 accounts")
check("a single-account aggregate has no 'across' clause",
      VibenetKeyAggregation.compose([roomA], now: refNowAgg)?.plainLine == "2 keys authorized")

let webAuthnOnlyAccount = account(address: "0xw1", actors: [
    VibenetActor(actorId: "w", authenticator: "0x5", kind: .webAuthn, scope: VibenetScope(raw: 0), expiry: 0)])
let secpOnlyAccount = account(address: "0xw2", actors: [
    VibenetActor(actorId: "s", authenticator: "0x6", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: 0)])
check("byKind orders by the contract's own sortRank, never by which ACCOUNT was iterated first",
      VibenetKeyAggregation.compose([webAuthnOnlyAccount, secpOnlyAccount], now: refNowAgg)?.byKind.map(\.kind)
        == [.secp256k1, .webAuthn])

func expiringActor(_ expiry: UInt64, id: String = "e") -> VibenetActor {
    VibenetActor(actorId: id, authenticator: "0x9", kind: .secp256k1, scope: VibenetScope(raw: 0), expiry: expiry)
}
check("expiry == 0 (never) never counts toward the soonest reading",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(0)])], now: refNowAgg)?.soonestExpiry == nil)
// `expiry == 0` must be excluded by its OWN explicit check, not merely by
// falling out of the ">now" comparison — the two coincide for any ordinary
// clock (0 is always before a real "now"), so this needs a `now` that
// ISN'T ordinary to actually separate the two: before the epoch, where
// TimeInterval(0) > now.timeIntervalSince1970 alone would wrongly read
// "never expires" as the soonest-ticking key in the room.
let beforeEpoch = Date(timeIntervalSince1970: -100)
check("expiry == 0 stays excluded even against a 'now' before the epoch, where 0 would otherwise read as future",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(0)])], now: beforeEpoch)?.soonestExpiry == nil)

let pastExpiry = UInt64(refNowAgg.timeIntervalSince1970) - 60
check("an already-expired key never counts as the soonest — it's a standing fact, not a countdown",
      VibenetKeyAggregation.compose([account(address: "0xa", actors: [expiringActor(pastExpiry)])], now: refNowAgg)?.soonestExpiry == nil)

let soonExpiry = UInt64(refNowAgg.timeIntervalSince1970) + 3600
let laterExpiry = UInt64(refNowAgg.timeIntervalSince1970) + 7200
let soonestAgg = VibenetKeyAggregation.compose([
    account(address: "0xa", actors: [expiringActor(laterExpiry, id: "late")]),
    account(address: "0xb", actors: [expiringActor(soonExpiry, id: "soon")]),
], now: refNowAgg)
check("the soonest FUTURE expiry wins across accounts, regardless of input order",
      soonestAgg?.soonestExpiry?.actor.actorId == "soon")
check("the soonest expiry's line names the account it belongs to",
      soonestAgg?.soonestExpiry?.line(now: refNowAgg).hasPrefix("0xb's key") == true)

let tieAgg = VibenetKeyAggregation.compose([
    account(address: "0xb", actors: [expiringActor(soonExpiry, id: "tie-b")]),
    account(address: "0xa", actors: [expiringActor(soonExpiry, id: "tie-a")]),
], now: refNowAgg)
check("a tied soonest expiry breaks deterministically by address, not input order",
      tieAgg?.soonestExpiry?.address == "0xa")

// MARK: - VibenetBalanceFormat.line — never currency-formatted (§83)

print("")
print("VibenetBalanceFormat.line")
check("a whole number prints bare, no trailing zeros or decimal point",
      VibenetBalanceFormat.line(100.0) == "100")
check("zero prints as a bare zero",
      VibenetBalanceFormat.line(0.0) == "0")
check("a clean fraction keeps exactly its own digits",
      VibenetBalanceFormat.line(2.5) == "2.5")
check("rounds to at most 4 decimal places",
      VibenetBalanceFormat.line(1.23456789) == "1.2346")
check("a non-finite amount never prints garbage — falls back to a bare zero",
      VibenetBalanceFormat.line(.infinity) == "0")
check("a NaN amount falls back the same way",
      VibenetBalanceFormat.line(.nan) == "0")
check("no currency symbol or thousands grouping ever appears — devnet tokens have no real price",
      !VibenetBalanceFormat.line(1234.5).contains("$") && !VibenetBalanceFormat.line(1234.5).contains(","))

// MARK: - VibenetBalanceAggregation.compose — the feed room's own stat block

print("")
print("VibenetBalanceAggregation.compose")
check("no accounts at all — nothing to aggregate",
      VibenetBalanceAggregation.compose([]) == nil)

let balAgg = VibenetBalanceAggregation.compose([
    VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
                        nativeBalance: 1.0,
                        tokenBalances: [VibenetTokenBalance(symbol: "USDV", amount: 10)]),
    VibenetAccountItem(address: "0xb", reached: true, established: true, actors: [],
                        locked: true, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil,
                        nativeBalance: 2.5,
                        tokenBalances: [VibenetTokenBalance(symbol: "USDV", amount: 5),
                                        VibenetTokenBalance(symbol: "NFV", amount: 3)]),
    VibenetAccountItem(address: "0xc", reached: true, established: true, actors: [],
                        locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil),
])
check("accountCount counts every item, including one with no balance reading at all",
      balAgg?.accountCount == 3)
check("lockedCount counts the alarmed accounts",
      balAgg?.lockedCount == 1)
check("nativeTotal SUMS every landed reading — never treats a missing one as zero",
      balAgg?.nativeTotal == 3.5)
check("tokenTotals sum WITHIN a symbol, never across symbols",
      balAgg?.tokenTotals.first(where: { $0.symbol == "USDV" })?.amount == 15)
check("a symbol only one account holds is still totalled correctly",
      balAgg?.tokenTotals.first(where: { $0.symbol == "NFV" })?.amount == 3)
check("tokenTotals are sorted by symbol — a TOTAL order, not input/iteration order",
      balAgg?.tokenTotals.map(\.symbol) == ["NFV", "USDV"])

check("nativeTotal is nil when NOT ONE account has a reading — never a guessed 0",
      VibenetBalanceAggregation.compose([
        VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                            locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
      ])?.nativeTotal == nil)
check("tokenTotals is empty when no account holds any token balance",
      VibenetBalanceAggregation.compose([
        VibenetAccountItem(address: "0xa", reached: true, established: true, actors: [],
                            locked: false, hasInitiatedUnlock: false, unlocksAt: nil, unlockDelay: nil)
      ])?.tokenTotals.isEmpty == true)

check("plainLine: several accounts, none locked, never prints '0 locked'",
      VibenetBalanceAggregate(accountCount: 3, lockedCount: 0, nativeTotal: nil, tokenTotals: [])
        .plainLine == "3 accounts")
check("plainLine: a real locked count IS printed",
      VibenetBalanceAggregate(accountCount: 3, lockedCount: 1, nativeTotal: nil, tokenTotals: [])
        .plainLine == "3 accounts · 1 locked")
check("plainLine: singular account, singular locked",
      VibenetBalanceAggregate(accountCount: 1, lockedCount: 1, nativeTotal: nil, tokenTotals: [])
        .plainLine == "1 account · 1 locked")

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
# An off-by-one here either re-reads one block twice (harmless but wasteful)
# or SKIPS one block silently — and a skipped block can hide the one event
# that would have kept a live actor in the roster. Both are real failures
# of the "no gaps, no overlaps" contract chunking exists for.
mutate "VibenetLogChunking.ranges must not skip the boundary block between chunks" \
  'let from = max(0, to - maxRange + 1)' \
  'let from = max(0, to - maxRange)'

# Without the chunk-count breaker, an oversized `tip` (a devnet that
# outgrows every bound this file assumes) spins forever against a shared
# public RPC — exactly the unbounded crawl this whole design exists to
# refuse.
mutate "VibenetLogChunking.ranges must stop at maxChunks, never loop unbounded" \
  'while to >= 0, chunk < maxChunks {' \
  'while to >= 0 {'

# A key row's whole content is its granted-permission chips — losing the
# NAMED ones while keeping only the unknown-count tail would show a key
# that can send transactions and pay its own gas as a row with a single
# "+1 unknown" chip, hiding the powers that actually matter.
mutate "grantedPlainLabels must include the NAMED permissions, not just the unknown tail" \
  'var parts = plainNames' \
  'var parts: [String] = []'

# Two keys authorized in one transaction share a block. Counting MOMENTS
# instead of BLOCKS makes that read as a sequence, and the sheet draws two
# dots side by side claiming an order that never happened.
mutate "isSequence must count distinct BLOCKS, not moments" \
  'Set(moments.map(\.block)).count > 1' \
  'moments.count > 1'

# A zero/zero standing means nothing has changed. Rendering it as a
# sentence instead of silence puts a line on the sheet that says nothing
# and reads as though it does.
mutate "plainLine must stay SILENT when nothing has changed" \
  'case (0, 0):' \
  'case (99, 99):'

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

mutate "the headline must say Locked/Unlocking itself — the row's own badge doesn't draw beside it" \
  'return item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked")' \
  'return String(localized: "")'

# The `hidden` count is what makes the note say "N more watched" — losing it
# collapses back to a bare provenance line with no signal that the card
# capped its own row count.
mutate "the note must count what the card didn't draw" \
  'let hidden = room.items.count - drawn' \
  'let hidden = 0'

# A stale pick falling back to the whole room is indistinguishable from no
# pick at all, while the rail sits lit on a face it is not describing.
mutate "scoped() must not fall back to the whole room on an unwatched address" \
  'items: items.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame },' \
  'items: items,'

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

# A case-sensitive compare would tell someone their account has NO
# delegate relationship the moment a live RPC happens to hand back the
# other address's hex in a different casing than this build stored it —
# the exact "an RPC's hex casing is not a promise" failure this file's own
# doc calls out.
mutate "VibenetAccountMapping.links must compare authenticator addresses case-INSENSITIVELY" \
  '$0.address.caseInsensitiveCompare(actor.authenticator) == .orderedSame' \
  '$0.address == actor.authenticator'

# Dropping the `.delegate` filter would read EVERY actor's authenticator as
# a potential relationship — including a plain secp256k1 key's
# authenticator, which is `Keystore.sol`'s own fixed K1 constant and would
# collide with itself across every account in the room, inventing a web of
# relationships that was never there.
mutate "VibenetAccountMapping.links must only ever consider .delegate actors" \
  'for actor in item.actors where actor.kind == .delegate {' \
  'for actor in item.actors {'

# The mapping section must never reshuffle between opens — flipping the
# primary sort to descending is exactly the kind of drift a card comparison
# across two composes of an unchanged room would catch as "broken".
mutate "VibenetAccountMapping.links must sort by from ascending, not descending" \
  'if f != .orderedSame { return f == .orderedAscending }' \
  'if f != .orderedSame { return f == .orderedDescending }'

# `expiry == 0` is Keystore.sol's own convention for "never expires" —
# folding it into the soonest reading would report a key that can never
# lapse as the most urgent one in the entire room.
mutate "VibenetKeyAggregation.compose must never count expiry == 0 toward the soonest reading" \
  '$0.1.expiry > 0 && TimeInterval($0.1.expiry) > now.timeIntervalSince1970' \
  'TimeInterval($0.1.expiry) > now.timeIntervalSince1970'

# The whole point of a "soonest expiry" callout is to point at what needs
# attention FIRST — swapping the comparator points at whatever lapses
# LAST instead, burying the one key someone actually needs to act on.
mutate "VibenetKeyAggregation.compose must pick the SOONEST future expiry, never the latest" \
  'if a.1.expiry != b.1.expiry { return a.1.expiry < b.1.expiry }' \
  'if a.1.expiry != b.1.expiry { return a.1.expiry > b.1.expiry }'

# Without this filter, an account that authorized nothing would still be
# counted in "N keys across M accounts" — inflating M and understating how
# concentrated the room's keys actually are.
mutate "VibenetKeyAggregation.compose's accountCount must exclude accounts with no actors" \
  'let accountCount = items.filter { !$0.actors.isEmpty }.count' \
  'let accountCount = items.count'

# byKind must read the Keystore's own declared order (ascending sortRank).
# Reversing it silently swaps which kind leads the summary — a cosmetic
# change on a two-kind room, but a real misreading on one with several,
# where the least-capable kind would lead instead of the most standard one.
mutate "VibenetKeyAggregation.compose's byKind must sort sortRank ASCENDING, not descending" \
  '.sorted { $0.sortRank < $1.sortRank }' \
  '.sorted { $0.sortRank > $1.sortRank }'

# A coarser round loses real precision — the whole reason 4 decimal places
# was chosen (enough to separate "some" from "dust" on a devnet) rather
# than the 2 places a currency figure would use, which this format is
# explicitly NOT.
mutate "VibenetBalanceFormat.line must round to 4 decimal places, not fewer" \
  'let rounded = (amount * 10_000).rounded() / 10_000' \
  'let rounded = (amount * 1).rounded() / 1'

# Without the finite guard, a non-finite amount reaches `String(format:)`
# directly and prints whatever Foundation happens to render for infinity/
# NaN — an unreadable balance on the one card this feature exists to make
# trustworthy, instead of the honest "0" this file promises on failure.
mutate "VibenetBalanceFormat.line must guard non-finite input before formatting" \
  'guard amount.isFinite else { return "0" }' \
  ' '

# A nil-guard dropped here turns "nobody's native balance ever landed"
# into a confidently-wrong "0 ETH" — the guessed-zero failure §83 exists
# to prevent, on the one card this feature is building trust around.
mutate "VibenetBalanceAggregation.compose must never guess 0 when no account has a native reading" \
  'let nativeTotal = natives.isEmpty ? nil : natives.reduce(0, +)' \
  'let nativeTotal: Double? = natives.reduce(0, +)'

# Summing every symbol into one bucket would add USDV to NFV — two
# different assets with no shared unit, exactly the "never combined"
# rule this room's own model already enforces per account.
mutate "VibenetBalanceAggregation.compose must sum tokenTotals WITHIN a symbol, never merge symbols" \
  'sums[balance.symbol, default: 0] += balance.amount' \
  'sums["all", default: 0] += balance.amount'

# Without a TOTAL order, the token chips would reorder between opens
# depending on which watched account the walk happened to reach first —
# the same standing rule every other roster/chip list in this file holds.
mutate "VibenetBalanceAggregation.compose's tokenTotals must sort by symbol ascending, not descending" \
  '.sorted { $0.symbol < $1.symbol }' \
  '.sorted { $0.symbol > $1.symbol }'

# A locked count of zero is a real, unalarming state — printing "· 0
# locked" on every quiet room is noise pretending to be a finding.
mutate "VibenetBalanceAggregate.plainLine must never print a zero locked count" \
  'if lockedCount > 0 {' \
  'if true {'

echo ""
echo "✓ vibenet-selftest: drift guards, assertions and mutations all passed"
