#!/bin/zsh
# THE VIBENET SCOPES' TWO NEW DRAWINGS (prd §491), compiled AS SHIPPED.
#
# `Model/VibenetAccountWeb.swift` and `Model/VibenetChangeFlow.swift` are
# Foundation-only BY DESIGN, so this compiles them WHOLE and unmodified
# alongside the types they read (`VibenetSubAccount`, `VibenetKeyMoment`).
# Separate from `vibenet-selftest.sh` — which is four minutes of assertions
# over the whole room — so these run in one.
#
# Every failure it catches renders as a perfectly ordinary card:
#
#   • the unwatched sub-account sorted LAST, which buries the only row the
#     drawing exists for and the only one that can offer to do anything
#   • an undated authorization treated as the oldest, ranking a failed
#     block-time read above a fact the chain actually published
#   • ribbons scaled across kinds, so one revocation draws as a hairline
#     beside forty grants and an account being emptied of keys reads as quiet
#   • a lock counted as a key moment, inventing an event with no block
#   • the headline saying "0 unwatched" — a card apologising for
#     being fine
#
# None of that fails a build, and no simulator can make a key be revoked.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/VibenetRoom.swift"
LEDGER="Casberi/Casberi/Model/VibenetLedger.swift"
FACTS="Casberi/Casberi/Model/VibenetEventFacts.swift"
WEB="Casberi/Casberi/Model/VibenetAccountWeb.swift"
FLOW="Casberi/Casberi/Model/VibenetChangeFlow.swift"
CARD="Casberi/Casberi/Screens/VibenetRoomCard.swift"
WEBCARD="Casberi/Casberi/Screens/VibenetAccountWebCard.swift"
FLOWCARD="Casberi/Casberi/Screens/VibenetChangeFlowCard.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_780_000_000)
func sub(_ a: String, _ watched: Bool, _ daysAgo: Double?) -> VibenetSubAccount {
    VibenetSubAccount(address: a, watched: watched,
                      authorizedAt: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) })
}

// ── the web: UNWATCHED FIRST, then oldest ────────────────────────────────────
let web = VibenetAccountWeb.web(owner: "0xowner", subAccounts: [
    sub("0xwatchedOld", true, 90),
    sub("0xunwatchedNew", false, 1),
    sub("0xwatchedNew", true, 2),
    sub("0xunwatchedOld", false, 30),
])!
check(web.nodes.map(\.address) == ["0xunwatchedOld", "0xunwatchedNew",
                                   "0xwatchedOld", "0xwatchedNew"],
      "unwatched first, then oldest within each half")
check(web.unwatched == 2, "the unwatched count is precomputed")
check(web.owner == "0xowner", "the owner is carried")

// An undated node is a FAILED READ, not the oldest fact — it sorts last in
// its own half rather than leading it.
// THREE, not two, and the assertion is on POSITION rather than on the whole
// array — with two elements Swift calls the comparator once, so an inconsistent
// ordering can still land in the expected order and the mutation survives. It
// did, on this harness's first run. (The standing rule, third time in this
// repo: a fixture only tests the rule it names if it FAILS that rule and
// passes every other one.)
let undated = VibenetAccountWeb.web(owner: "0xo", subAccounts: [
    sub("0xnoDate", false, nil),
    sub("0xrecent", false, 1),
    sub("0xold", false, 50),
])!
check(undated.nodes.map(\.address) == ["0xold", "0xrecent", "0xnoDate"],
      "an undated authorization sorts last, never as the oldest")
check(undated.nodes.last?.address == "0xnoDate",
      "and it is genuinely last, not merely somewhere after one dated node")

check(VibenetAccountWeb.web(owner: "0xo", subAccounts: []) == nil,
      "no sub-accounts is nil, never an empty web")

// ── the headline drops a zero rather than printing one ───────────────────────
let allWatched = VibenetAccountWeb.web(owner: "0xo", subAccounts: [sub("0xa", true, 3)])!
check(!VibenetAccountWeb.headline(allWatched).contains("0"),
      "a fully watched web never says '0 unwatched'")
check(VibenetAccountWeb.headline(allWatched) == "1 account",
      "one watched sub-account reads as a bare count")
check(VibenetAccountWeb.headline(web).contains("2"),
      "the unwatched count reaches the headline when there is one")
// THE HEADLINE HAS TO FIT ONE LINE OF `stat24` BESIDE THE GEAR (user,
// 2026-08-26). It shipped as "2 accounts · 1 you don't watch yet" and
// truncated mid-word on a 402pt screen — the card's own comment already said
// the gear reserves 44pt of the trailing corner, and the remaining ~300pt at
// 24pt is about 28 characters. The card carries a `minimumScaleFactor`, so
// the failure is not a crash but a headline drawn smaller on this scope than
// on the other four, or an ellipsis where the count should be.
//
// A character budget, not a rendered width: nothing here can measure text.
// It is deliberately loose (32, against a fit of ~28) so it catches a clause
// growing back into a sentence and never fires on a legitimately larger
// number — "12 accounts · 11 unwatched" is 26 and must pass.
check(VibenetAccountWeb.headline(web).count <= 32,
      "the headline fits its line rather than relying on being shrunk")
let manyIndexes: [Int] = Array(0..<12)
let manyWeb = VibenetAccountWeb.web(owner: "0xo", subAccounts:
    manyIndexes.map { sub("0xsub\($0)", $0 == 0, Double($0 + 1)) })!
check(VibenetAccountWeb.headline(manyWeb).count <= 32,
      "and still fits with two-digit counts on both sides")

// ── the flow ─────────────────────────────────────────────────────────────────
func moment(_ authorized: Bool, _ block: Int) -> VibenetKeyMoment {
    VibenetKeyMoment(block: block, logIndex: 0, authorized: authorized,
                     kind: .secp256k1, date: now)
}
let flow = VibenetChangeFlow.flow([
    (address: "0xA", moments: [moment(true, 1), moment(true, 2), moment(false, 3)], locked: false),
    (address: "0xB", moments: [moment(true, 4)], locked: true),
    (address: "0xQuiet", moments: [], locked: false),
])!
check(flow.total == 5, "every event counted once, the lock included")
check(flow.total(.authorized) == 3 && flow.total(.revoked) == 1 && flow.total(.locked) == 1,
      "kinds counted apart")
check(flow.addresses == ["0xA", "0xB"],
      "an account with nothing to say contributes no node")
check(flow.edges.filter { $0.address == "0xA" }.count == 2,
      "one edge per kind per account")

// A LOCK IS A STATE, not a moment: it must come from the flag and never be
// read out of the key history.
let lockOnly = VibenetChangeFlow.flow([(address: "0xL", moments: [], locked: true)])!
check(lockOnly.total == 1 && lockOnly.total(.locked) == 1,
      "a locked account with no key history still draws")

// THE SCALING RULE: within a kind, never across.
check(flow.heaviest(.authorized) == 2, "the heaviest authorization edge is per-kind")
check(flow.heaviest(.revoked) == 1, "the heaviest revocation edge is its own")
check(flow.heaviest(.locked) == 1, "and so is the lock's")

check(VibenetChangeFlow.Kind.allCases == [.authorized, .revoked, .locked],
      "kinds run in their declared order")
// `allCases` follows DECLARATION order, so it cannot see a changed rawValue —
// and rawValue is what `Comparable` and therefore the EDGE order rest on. This
// is the assertion that actually pins it: rows that reshuffle between opens
// over identical data read as broken (§292's total-order rule).
check(flow.edges.map(\.kind) == [.authorized, .authorized, .revoked, .locked],
      "edges come back in the kinds' declared rank, then by address")
check(!VibenetChangeFlow.Kind.authorized.isAlarming
        && !VibenetChangeFlow.Kind.revoked.isAlarming
        && VibenetChangeFlow.Kind.locked.isAlarming,
      "only a lock is alarming — the rest are decisions somebody made")

check(VibenetChangeFlow.flow([]) == nil, "nothing in, nil out")
check(VibenetChangeFlow.flow([(address: "0xZ", moments: [], locked: false)]) == nil,
      "an account with no changes yields no drawing")
check(VibenetChangeFlow.headline(flow).contains("5"), "the headline counts changes")

if failures == 0 {
    print("  ok   web ordering, headline, flow counting, per-kind scaling")
}
exit(failures == 0 ? 0 : 1)
SWIFT


# **STUBS THE ROOM NOW NEEDS (prd §551).** §548b put `VibenetRoom.demoSignableAccount()`
# into this Foundation-only file, and it reaches two types this harness has never
# compiled: `DemoMode` (the tour's own flag) and `VibenetTransaction` (the hex
# decoder). Neither has anything to do with the drawings under test, so both are
# INERT here — the demo is always off and the decoder always answers nil, which
# is the state every assertion below already assumes.
cat > "$work/stubs.swift" <<'SWIFT'
import Foundation

enum DemoMode {
    static var isActive: Bool { false }
}

enum VibenetTransaction {
    static func data(fromHex: String) -> Data? { nil }
}
SWIFT

run() { swiftc -O -o "$work/t" "$1" "$2" "$ROOM" "$LEDGER" "$FACTS" "$work/stubs.swift" "$work/main.swift" 2>"$work/err" || { cat "$work/err" >&2; return 2; }; "$work/t"; }

cp "$WEB" "$work/web.swift"; cp "$FLOW" "$work/flow.swift"
echo "Assertions"
run "$work/web.swift" "$work/flow.swift" || fail "assertions failed against the shipped source"

mutate() {
  local what="$1" file="$2" from="$3" to="$4"
  python3 - "$file" "$work/mut.swift" "$from" "$to" <<'PY'
import io,sys
src,dst,a,b = sys.argv[1:5]
s = io.open(src,encoding='utf-8').read()
if s.count(a) != 1:
    print(f"STALE: {a!r} occurs {s.count(a)}x", file=sys.stderr); sys.exit(3)
io.open(dst,'w',encoding='utf-8').write(s.replace(a,b))
PY
  [[ $? -eq 3 ]] && fail "mutation is STALE and tests nothing: $what"
  local a b
  if [[ "$file" == "$work/web.swift" ]]; then a="$work/mut.swift"; b="$work/flow.swift"
  else a="$work/web.swift"; b="$work/mut.swift"; fi
  if run "$a" "$b" >/dev/null 2>&1; then fail "mutation SURVIVED — $what"; fi
  print "  ok   catches  $what"
}

mutate "the unwatched sub-account sorted last, burying the only actionable row" \
  "$work/web.swift" "if a.watched != b.watched { return !a.watched }" \
  "if a.watched != b.watched { return a.watched }"
# BOTH nil branches, not one. Flipping a single branch leaves an INCONSISTENT
# comparator — (nil, dated) and (dated, nil) would both answer "before" — and
# Swift's sort is then free to return anything, which on this fixture happened
# to be the correct order. The mutation survived, and it was the mutation that
# was broken rather than the guard. A mutation has to be a VALID ordering that
# is wrong, not an invalid one.
mutate "an undated authorization ranked as the oldest fact" \
  "$work/web.swift" "case (nil, _?):    return false
                case (_?, nil):    return true" \
  "case (nil, _?):    return true
                case (_?, nil):    return false"
mutate "the headline apologising with a zero" \
  "$work/web.swift" "guard web.unwatched > 0 else { return count }" "" 
mutate "a lock counted as a key moment rather than a state" \
  "$work/flow.swift" "let locked = account.locked ? 1 : 0" "let locked = 0"
mutate "ribbons scaled across kinds instead of within one" \
  "$work/flow.swift" "edges.filter { \$0.kind == kind }.map(\\.count).max() ?? 0" \
  "edges.map(\\.count).max() ?? 0"
mutate "an authorization painted as an alarm" \
  "$work/flow.swift" "var isAlarming: Bool { self == .locked }" "var isAlarming: Bool { true }"
mutate "a quiet account drawn as a node with nothing on it" \
  "$work/flow.swift" "guard authorized + revoked + locked > 0 else { continue }" ""
mutate "the kinds reordered, so the rows move between opens" \
  "$work/flow.swift" "case revoked = 1" "case revoked = 9"

# ── drift guards: the wiring the compiled arithmetic cannot prove ────────────
# **NEVER `strip … | grep -q` (CLAUDE.md's own recorded trap, hit by this
# harness on its first run).** `grep -q` exits 0 the instant it matches and
# closes the pipe; the writer takes SIGPIPE and exits 141, and `pipefail` makes
# 141 the PIPELINE's status — so a SUCCESSFUL match fires the `||` branch and
# the guard reports a finding against source that is perfectly correct. It did
# exactly that here. Read the stripped text into a variable once; no pipe,
# nothing to signal.
strip() { sed -E 's://.*::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }
CARD_NC="$(strip "$CARD")"
WEBCARD_NC="$(strip "$WEBCARD")"
FLOWCARD_NC="$(strip "$FLOWCARD")"

grep -q 'case .accounts:        accountsFigure' "$CARD" \
  || fail "the Accounts scope no longer leads with the web"
grep -q 'case .activity:        activityFigure' "$CARD" \
  || fail "the Activity scope no longer leads with the change flow"
grep -q 'case .permissions:     permissionsFigure' "$CARD" \
  || fail "the Permissions scope no longer leads with the capability census"

# PER ACCOUNT, never aggregated — merging owners would attribute a
# relationship to an account that does not hold it.
[[ "$CARD_NC" == *'VibenetAccountWeb.web(owner: $0.address, subAccounts: $0.subAccounts)'* ]] \
  || fail "the sub-account web is no longer built from ONE account's own read"

# Both figures speak as one sentence (§299) rather than as loose marks.
grep -q 'accessibilityLabel(Text(VibenetAccountWeb.spoken(web)))' "$WEBCARD" \
  || fail "the sub-account web stopped speaking its ordered sentence"
grep -q 'accessibilityLabel(Text(VibenetChangeFlow.spoken(flow)))' "$FLOWCARD" \
  || fail "the change flow stopped speaking its ordered sentence"
# ...and the flow's taps stay reachable as ACTIONS, which is what makes its
# accessibility exemption stronger than WalletFlowBand's.
grep -q 'accessibilityActions' "$FLOWCARD" \
  || fail "the change flow's account taps are no longer reachable to VoiceOver"

# Bare on the page (§483) — neither figure may grow a card.
[[ "$WEBCARD_NC" == *'dsWidgetSurface'* ]] && fail "the sub-account web is on a card again"
[[ "$FLOWCARD_NC" == *'dsWidgetSurface'* ]] && fail "the change flow is on a card again"

print "  ok   8 mutations, 9 drift guards"
