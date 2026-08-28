#!/bin/zsh
# WHO CAN ACT FOR YOU — the Permissions rungs (prd §490), compiled AS SHIPPED.
#
# `Model/WalletPermissions.swift` is Foundation-only by design, so this
# compiles it WHOLE and unmodified — no stubs, no copied logic. Every failure
# it catches renders as a perfectly ordinary card, which is why it exists:
#
#   • a rung ordered by anything but reach, so a capped grant draws above a
#     Safe module that can move funds with no signature at all
#   • `scopedSigner` demoted below a cap, which draws a bound nobody can read
#     as though it were a small one (§293's ceiling rule, inverted)
#   • a PARTIAL sum printed as a rung's total — the one wrong number here that
#     looks completely right, because a total quietly missing a grant is more
#     misleading than no total
#   • an unpriced holder counted as ZERO, which sorts the most dangerous
#     things in the scope last (§292 states this trap in its own words)
#   • the eyebrow printing "$0" for a wallet whose only holder is a Safe
#     module — real exposure, no dollars, and a zero says the opposite
#
# None of that fails a build, a screen sweep or a probe: no simulator can
# install a Safe module or make a delegate appear.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/WalletPermissions.swift"
MAP="Casberi/Casberi/Model/WalletPermissionsSource.swift"
CARD="Casberi/Casberi/Screens/WalletPermissionsCard.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
STATE="Casberi/Casberi/Model/WalletWarnings.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

typealias P = WalletPermissions.Power
func h(_ p: P, _ name: String, _ usd: Double? = nil, _ note: String? = nil) -> WalletPermissions.Holder {
    .init(power: p, name: name, usd: usd, note: note)
}

// ── the order IS the claim ───────────────────────────────────────────────────
check(P.allCases == [.actsAsWallet, .movesWithoutSignature, .unlimitedToken,
                     .wholeCollection, .scopedSigner, .cappedAmount],
      "rungs run unbounded → bounded")
check(P.actsAsWallet < P.movesWithoutSignature, "acting as the wallet outranks a module")
check(P.movesWithoutSignature < P.unlimitedToken, "no-signature outranks an unlimited allowance")
check(P.unlimitedToken < P.wholeCollection, "a whole token outranks a whole collection")
// §293's ceiling rule: an unreadable bound is never drawn as a small one.
check(P.scopedSigner < P.cappedAmount, "an unreadable scope outranks a stated cap")

check(P.actsAsWallet.isUnbounded && P.wholeCollection.isUnbounded,
      "the top four are unbounded")
check(!P.scopedSigner.isUnbounded && !P.cappedAmount.isUnbounded,
      "a stated cap and a scoped key are not alarms")

// An amount is IMPOSSIBLE on three rungs and merely absent on the others —
// the difference is what keeps "no amount to state" off rows where it reads
// as an apology for a fact.
check(P.unlimitedToken.canCarryAmount && P.cappedAmount.canCarryAmount,
      "the two token rungs can carry a figure")
check(!P.actsAsWallet.canCarryAmount && !P.movesWithoutSignature.canCarryAmount
      && !P.wholeCollection.canCarryAmount,
      "a delegate, a module and a collection grant are unpriceABLE, not unpriced")

// A rung's grouping must follow the TYPE's order, never the data's — the
// shape has to be the same four rows on every wallet that has them.
let scrambled = WalletPermissions.rungs([
    h(.cappedAmount, "1inch", 500),
    h(.actsAsWallet, "delegate"),
    h(.unlimitedToken, "Uniswap", 6204),
])
check(scrambled.map(\.power) == [.actsAsWallet, .unlimitedToken, .cappedAmount],
      "rungs come back in Power order however they arrived")

// ── a rung is priced ONLY when every holder in it is ─────────────────────────
let mixed = WalletPermissions.rungs([
    h(.unlimitedToken, "Uniswap", 6204),
    h(.unlimitedToken, "0x7a25", nil),
])
check(mixed.count == 1, "one rung")
check(mixed[0].count == 2, "counts both")
check(mixed[0].usd == nil, "a rung holding an unpriced grant states NO total")
check(mixed[0].hasUnpriced, "and says so")

let whole = WalletPermissions.rungs([
    h(.unlimitedToken, "Uniswap", 6204),
    h(.unlimitedToken, "0x7a25", 2220),
])
check(whole[0].usd == 8424, "a fully priced rung sums")
check(!whole[0].hasUnpriced, "and claims to be complete")

// An unpriced holder is never zero — that is what would sort it last.
let noAmount = WalletPermissions.rungs([h(.movesWithoutSignature, "a Safe module")])
check(noAmount[0].usd == nil, "no amount is nil, never 0")

// ── names: the caller's order is the ranked one ──────────────────────────────
let named = WalletPermissions.rungs([
    h(.cappedAmount, "biggest", 900),
    h(.cappedAmount, "middle", 500),
    h(.cappedAmount, "smallest", 10),
])
check(named[0].names == ["biggest", "middle"], "names keep the caller's rank, capped at 2")
check(named[0].count == 3, "the count is all of them")
check(WalletPermissions.namesShown == 2, "two names")

// A note rides only a rung of ONE — on a rung of three it would describe
// whichever holder happened to be first.
check(WalletPermissions.rungs([h(.movesWithoutSignature, "m", nil, "installed 14 Mar")])[0].note != nil,
      "a lone holder's note survives")
check(WalletPermissions.rungs([h(.movesWithoutSignature, "a", nil, "x"),
                               h(.movesWithoutSignature, "b", nil, "y")])[0].note == nil,
      "a rung of two carries no note")

// ── the eyebrow ──────────────────────────────────────────────────────────────
check(WalletPermissions.totalUSD([h(.movesWithoutSignature, "m")]) == nil,
      "a wallet with real exposure and no dollars states NO total")
check(WalletPermissions.totalUSD([h(.unlimitedToken, "u", 6204),
                                  h(.movesWithoutSignature, "m")]) == 6204,
      "the total counts what is priced and ignores what is not")
check(WalletPermissions.totalUSD([]) == nil, "nothing at all is nil")
check(WalletPermissions.hasUnbounded([h(.cappedAmount, "c", 5)]) == false,
      "a capped-only wallet is not unbounded")
check(WalletPermissions.hasUnbounded([h(.wholeCollection, "OpenSea")]),
      "a collection grant is unbounded")

// ── the fold counts HOLDERS, not rows ────────────────────────────────────────
let six = WalletPermissions.rungs([
    h(.actsAsWallet, "d"), h(.movesWithoutSignature, "m"),
    h(.unlimitedToken, "u", 1), h(.wholeCollection, "o"),
    h(.scopedSigner, "s"), h(.cappedAmount, "c1", 1), h(.cappedAmount, "c2", 1),
])
check(six.count == 6, "six rungs")
check(WalletPermissions.foldedCount(six) == 3, "the fold counts the 3 holders below the cut, not the 2 rows")
check(WalletPermissions.foldedCount(Array(six.prefix(4))) == nil, "nothing folded is nil")
check(WalletPermissions.rungsShown == 4, "four rungs drawn")

// ── an empty wallet ──────────────────────────────────────────────────────────
check(WalletPermissions.rungs([]).isEmpty, "nothing in, nothing out")

if failures == 0 { print("  ok   \(P.allCases.count) rungs, order, pricing, fold") }
exit(failures == 0 ? 0 : 1)
SWIFT

run() {
  swiftc -O -o "$work/t" "$1" "$work/main.swift" 2>"$work/err" || {
    cat "$work/err" >&2; return 2
  }
  "$work/t"
}

cp "$SRC" "$work/src.swift"
run "$work/src.swift" || fail "assertions failed against the shipped source"

# ── mutations: each one is a silent wrong answer this must catch ─────────────
mutate() {
  local what="$1" from="$2" to="$3"
  python3 - "$work/src.swift" "$work/mut.swift" "$from" "$to" <<'PY'
import io,sys
src,dst,a,b = sys.argv[1:5]
s = io.open(src,encoding='utf-8').read()
if s.count(a) != 1:
    print(f"STALE: {a!r} occurs {s.count(a)}x", file=sys.stderr); sys.exit(3)
io.open(dst,'w',encoding='utf-8').write(s.replace(a,b))
PY
  local rc=$?
  [[ $rc -eq 3 ]] && fail "mutation is STALE and tests nothing: $what"
  if run "$work/mut.swift" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $what"
  fi
  print "  ok   catches  $what"
}

mutate "a stated cap ranked above an unreadable scope" \
  "case scopedSigner = 4" "case scopedSigner = 6"
mutate "a Safe module demoted below an unlimited allowance" \
  "case movesWithoutSignature = 1" "case movesWithoutSignature = 9"
mutate "a capped grant painted as an alarm" \
  "var isUnbounded: Bool { self <= .wholeCollection }" \
  "var isUnbounded: Bool { true }"
mutate "an unbounded rung stops reading as one" \
  "var isUnbounded: Bool { self <= .wholeCollection }" \
  "var isUnbounded: Bool { self <= .actsAsWallet }"
mutate "a PARTIAL sum printed as a rung's total" \
  "usd: complete && !priced.isEmpty ? priced.reduce(0, +) : nil" \
  "usd: priced.isEmpty ? nil : priced.reduce(0, +)"
mutate "a rung stops admitting it holds an unpriced grant" \
  "hasUnpriced: priced.count < group.count" "hasUnpriced: false"
mutate "the fold counts ROWS rather than holders" \
  "let folded = rungs.dropFirst(rungsShown).reduce(0) { \$0 + \$1.count }" \
  "let folded = rungs.dropFirst(rungsShown).count"
mutate "the eyebrow prints \$0 where there is no amount to state" \
  "return priced.isEmpty ? nil : priced.reduce(0, +)" \
  "return priced.reduce(0, +)"
mutate "a rung of several carries the first holder's note as if it described them all" \
  "note: group.count == 1 ? group[0].note : nil" "note: group.first?.note"
# REVERSED, not `byPower.keys` (amended 2026-08-28). The dictionary's key order
# is nondeterministic in Swift, so on the three-rung fixture that discriminates
# this rule the mutation landed on the correct order roughly one run in six and
# SURVIVED — a flaky mutation, which is worse than none: it passes on the
# machine you test on and fails a nightly nobody is watching. Reversing is
# deterministically wrong and pins the same rule. (Second instance of this exact
# trap in one day; see hegota-selftest's frame-mix tie-break.)
mutate "the rungs come back in the data's order instead of the type's" \
  "return Power.allCases.compactMap { power in" \
  "return Power.allCases.reversed().compactMap { power in"
mutate "an unpriceable rung starts apologising for having no figure" \
  "self == .unlimitedToken || self == .cappedAmount" "true"
mutate "a token rung stops expecting a figure, so a failed price read goes silent" \
  "self == .unlimitedToken || self == .cappedAmount" "false"
mutate "a rung names more holders than it can draw" \
  "names: group.prefix(namesShown).map(\\.name)" "names: group.map(\\.name)"

# ── drift guards: the wiring the compiled arithmetic cannot prove ────────────
strip() { sed -E 's://.*::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }

grep -q 'case .permissions: walletPermissionsSection' "$FEED" \
  || fail "the Permissions scope no longer leads with this card"

# The publication flag must be the section's OWN gate, spelled the same way —
# §483's rule, whose failure was a chip that opened a blank page.
grep -q 'permissions: !WalletPermissionsSource.holders(exposure: walletLive.exposure,' "$FEED" \
  || fail "the Permissions presence flag has drifted from the section's render gate"
grep -q 'if !holders.isEmpty {' "$FEED" \
  || fail "the section's render gate is no longer !holders.isEmpty"

# The acting-parties read must stay IN the live state, not on the card: a chain
# read hung off a row's `.task` fires on every scroll that remounts it.
grep -q 'async let actingRead = WalletActingParties.read(addresses: resolved)' "$STATE" \
  || fail "the acting-parties read left WalletWatch.liveState"
grep -q 'acting: await actingRead' "$STATE" \
  || fail "the acting-parties read is no longer published into WalletLiveState"

# Bare on the page, like every other scope's lead (§483).
strip "$CARD" | grep -q 'dsWidgetSurface' \
  && fail "the Permissions lead is on a card again (§483: we don't do cards)"

# An operator grant must never carry a figure — §292 prices no NFT.
grep -q 'usd: grant.forAll ? nil : grant.usd' "$MAP" \
  || fail "an operator grant can now carry a dollar amount"
# ...and must be tested BEFORE unlimited, or a collection lands in a rung whose
# sentence names a token.
strip "$MAP" | grep -A 2 'static func power(for grant:' | grep -q 'if grant.forAll' \
  || fail "forAll is no longer resolved before unlimited"

# An acting party never carries an amount at all — the whole reason this card
# exists rather than a ranking.
grep -q 'usd: nil,' "$MAP" \
  || fail "an acting party can now carry a dollar amount"

# The card speaks as ONE sentence (§299), like the risk bars two scopes over.
grep -q 'accessibilityElement(children: .combine)' "$CARD" \
  || fail "the card stopped speaking as one ordered sentence"

print "  ok   11 mutations, 10 drift guards"
