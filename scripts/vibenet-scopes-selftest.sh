#!/bin/zsh
# THE VIBENET SCOPES' DRAWING (prd §491), compiled AS SHIPPED.
#
# `Model/VibenetChangeFlow.swift` is Foundation-only BY DESIGN, so this
# compiles it WHOLE and unmodified alongside the type it reads
# (`VibenetKeyMoment`). The sub-account web it once compiled beside it
# (`VibenetAccountWeb`) is deleted with the drawing (prd §948): every room's
# Accounts crown is its accounts face by face.
# Separate from `vibenet-selftest.sh` — which is four minutes of assertions
# over the whole room — so these run in one.
#
# Every failure it catches renders as a perfectly ordinary card:
#
#   • ribbons scaled across kinds, so one revocation draws as a hairline
#     beside forty grants and an account being emptied of keys reads as quiet
#   • a lock counted as a key moment, inventing an event with no block
#
# None of that fails a build, and no simulator can make a key be revoked.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOM="Casberi/Casberi/Model/VibenetRoom.swift"
LEDGER="Casberi/Casberi/Model/VibenetLedger.swift"
FACTS="Casberi/Casberi/Model/VibenetEventFacts.swift"
FLOW="Casberi/Casberi/Model/VibenetChangeFlow.swift"
CARD="Casberi/Casberi/Screens/VibenetRoomCard.swift"
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
    print("  ok   flow counting, per-kind scaling")
}
exit(failures == 0 ? 0 : 1)
SWIFT


# **STUBS THE ROOM NOW NEEDS (prd §553).** §552b put `VibenetRoom.demoSignableAccount()`
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

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 4.5x faster).
# Re-probe before trusting it again after adding mutations.
run() { swiftc -Onone -o "$work/t" "$1" "$ROOM" "$LEDGER" "$FACTS" "$work/stubs.swift" "$work/main.swift" 2>"$work/err" || { cat "$work/err" >&2; return 2; }; "$work/t"; }

cp "$FLOW" "$work/flow.swift"
echo "Assertions"
run "$work/flow.swift" || fail "assertions failed against the shipped source"

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
  if run "$work/mut.swift" >/dev/null 2>&1; then fail "mutation SURVIVED — $what"; fi
  print "  ok   catches  $what"
}

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
FLOWCARD_NC="$(strip "$FLOWCARD")"

grep -q 'case .accounts:        accountsFigure' "$CARD" \
  || fail "the Accounts scope no longer leads with its figure (prd §948: your accounts, face by face)"
grep -q 'case .activity:        activityChart' "$CARD" \
  || fail "the Activity scope no longer leads with its chart (prd §686 — how many, and when)"
grep -q 'case .permissions:     permissionsFigure' "$CARD" \
  || fail "the Permissions scope no longer leads with the capability census"

# The figure speaks as one sentence (§299) rather than as loose marks.
grep -q 'accessibilityLabel(Text(VibenetChangeFlow.spoken(flow)))' "$FLOWCARD" \
  || fail "the change flow stopped speaking its ordered sentence"
# ...and the flow's taps stay reachable as ACTIONS, which is what makes its
# accessibility exemption stronger than WalletFlowBand's.
grep -q 'accessibilityActions' "$FLOWCARD" \
  || fail "the change flow's account taps are no longer reachable to VoiceOver"

# Bare on the page (§483) — neither figure may grow a card.
[[ "$FLOWCARD_NC" == *'dsWidgetSurface'* ]] && fail "the change flow is on a card again"

print "  ok   5 mutations, 7 drift guards"
