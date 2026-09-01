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

// ── ONE HOLDER PER THING THAT CAN ACT (prd §514) ─────────────────────────────
//
// The report: "6 · Can act as your wallet" naming `…51d3 · …51d3`, because
// `WalletActingParties.read` answers per ACCOUNT and six of your wallets
// delegate to one contract. Six delegations to one contract are one thing with
// that power, and the rung claims to count things.
func party(_ p: P, _ name: String, key: String, on account: String,
           _ note: String? = nil) -> WalletPermissions.Holder {
    .init(power: p, name: name, usd: nil, note: note, key: key, accounts: [account])
}

let sameDelegate = WalletPermissions.merged([
    party(.actsAsWallet, "...51d3", key: "0x51d3", on: "0xaaa"),
    party(.actsAsWallet, "...51d3", key: "0x51d3", on: "0xbbb"),
    party(.actsAsWallet, "...51d3", key: "0x51d3", on: "0xccc"),
])
check(sameDelegate.count == 1, "one delegate on three wallets is ONE holder")
check(sameDelegate.first?.accounts == ["0xaaa", "0xbbb", "0xccc"],
      "and it says which three, in the order they were seen")
check(WalletPermissions.rungs(sameDelegate).first?.count == 1,
      "so the rung counts 1, not 3")

// The same CONTRACT under two different powers is two things — the merge is
// per (power, key), never per key alone, or a module that is also a delegate
// would lose the more dangerous of its two rungs.
check(WalletPermissions.merged([
    party(.actsAsWallet, "x", key: "0x1", on: "0xaaa"),
    party(.movesWithoutSignature, "x", key: "0x1", on: "0xaaa"),
]).count == 2, "one address under two powers stays two holders")

// Two DIFFERENT contracts that resolve to the same registry label must not
// fold — the whole reason identity is the address and not the name.
check(WalletPermissions.merged([
    party(.actsAsWallet, "Safe", key: "0x1", on: "0xaaa"),
    party(.actsAsWallet, "Safe", key: "0x2", on: "0xaaa"),
]).count == 2, "one label over two addresses stays two holders")

// The same wallet twice (one delegate read per chain) contributes ONE account.
check(WalletPermissions.merged([
    party(.actsAsWallet, "d", key: "0x1", on: "0xAAA"),
    party(.actsAsWallet, "d", key: "0x1", on: "0xaaa"),
]).first?.accounts == ["0xAAA"],
      "the same wallet on two chains is named once, case-insensitively")

// A PRICED grant never merges: §292 has ranked it and its amount is its own.
let twoGrants = WalletPermissions.merged([
    h(.cappedAmount, "Uniswap", 10), h(.cappedAmount, "Uniswap", 20),
])
check(twoGrants.count == 2, "two priced grants to one spender stay two")
check(WalletPermissions.rungs(twoGrants).first?.usd == 30, "and their total is still the sum")

// Ranked order survives the merge — the two names a rung shows are still the
// two biggest.
check(WalletPermissions.merged([
    h(.cappedAmount, "big", 100), h(.cappedAmount, "small", 1),
]).map(\.name) == ["big", "small"], "the merge preserves §292's ranking")

// ── the two halves of the scope ──────────────────────────────────────────────
//
// Split on `accounts`, so a grant can never appear in the acting list AND in
// the approvals list below it.
check(WalletPermissions.actingHolders([
    party(.actsAsWallet, "d", key: "0x1", on: "0xaaa"),
    h(.cappedAmount, "Uniswap", 10),
    h(.wholeCollection, "OpenSea"),
]).map(\.name) == ["d"], "only the holders that name a wallet are the acting half")
check(WalletPermissions.actingHolders([]).isEmpty, "nothing in, nothing out")

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

# prd §514 — the duplication the merge exists to end, and the three ways the
# merge itself can be wrong while still rendering a plausible card.
mutate "the same delegate on six wallets counted six times again" \
  "let mergeable = holder.usd == nil" "let mergeable = false"
mutate "the merge folds two powers together, losing the more dangerous rung" \
  "let id = \"\\(holder.power.rawValue)|\\(holder.key)\"" \
  "let id = holder.key"
mutate "the merge keys on the DISPLAY NAME, folding two contracts one registry labels alike" \
  "let id = \"\\(holder.power.rawValue)|\\(holder.key)\"" \
  "let id = \"\\(holder.power.rawValue)|\\(holder.name)\""
mutate "a merged holder stops saying which of your wallets it acts for" \
  "accounts: already.accounts + fresh)" "accounts: already.accounts)"
mutate "two priced grants to one spender collapse, and a real amount is dropped" \
  "let mergeable = holder.usd == nil" "let mergeable = true"
mutate "the same wallet, read once per chain, is named twice on one row" \
  "!already.accounts.contains { \$0.caseInsensitiveCompare(account) == .orderedSame }" \
  "false"
mutate "a grant is offered to the acting list as well as to the approvals list" \
  "holders.filter { !\$0.accounts.isEmpty }" "holders"

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

# prd §514 — the LIST half. `namesShown` promises "the list below carries
# every holder", and until this it carried only the token grants: a Safe
# module, a delegate and a keystore credential were counted by the card and
# listed by nothing, which is how a wallet with six delegates and no approvals
# drew a count over an empty page.
ROWS="Casberi/Casberi/Screens/WalletActingPartiesRows.swift"
[ -f "$ROWS" ] || fail "the acting-parties list is gone — the card's names fold into nothing again"
grep -q 'walletActingSection' "$FEED" \
  || fail "the Permissions scope no longer draws the acting-parties list"
# Acting BEFORE approvals, or the unbounded holders sort under the capped ones
# and contradict the card directly above them.
# Blank lines are squeezed out first: `strip` turns a comment into an empty
# line, so a bare `-A 2` counts the prose rather than the code under it.
# Anchored on the ROW switch, not the head switch — `case .permissions:` also
# names the drawing one level up, and an unanchored grep reads that block's
# closing brace as this one's first row.
order=$(strip "$FEED" | sed '/^[[:space:]]*$/d' | grep -A 2 '^            case .permissions:$')
print -r -- "$order" | sed -n '2p' | grep -q 'walletActingSection' \
  || fail "the acting list no longer leads the Permissions scope's rows"
print -r -- "$order" | sed -n '3p' | grep -q 'walletApprovalsSection' \
  || fail "the approvals list no longer follows it in the Permissions scope"

# A LIST, NOT A CONTROL (§112/§293): nothing here signs, revokes or opens.
# A delegate is undone from the wallet app that set it, so a chevron here
# would be §83's dead control.
strip "$ROWS" | grep -qE 'openURL|Button|onTap|sheet' \
  && fail "the acting-parties list grew a control — §112: it is an inventory with no verb"

# The row's sentence is the RUNG's, so a row and the count above it can never
# describe the same holder differently.
grep -q 'holder.power.phrase' "$ROWS" \
  || fail "the row stopped taking its sentence from the rung it is counted in"
# ...and it must say which of your wallets, or the merge has hidden a fact
# rather than tidied one.
grep -q 'holder.accounts.map' "$ROWS" \
  || fail "a merged holder no longer names the wallets it acts for"
# §293's ceiling: an account whose modules cannot be listed says so, because an
# empty list and an unreadable one look identical.
grep -q 'modulesUnreadable' "$ROWS" \
  || fail "the unreadable-modules ceiling is no longer stated in the list"
grep -q 'keystorePartial' "$ROWS" \
  || fail "the capped-keystore ceiling is no longer stated in the list"

# THE PAIR, BOTH DIRECTIONS (2026-08-31). The two Permissions lists sit one
# above the other and must never look alike: the acting list is inert by the
# ruling above, so the approvals list — which opens each grant's sheet, and with
# it the only revoke hand-off this app has — must SAY that it is a door. It did
# not, and the scope read as a wall of dead rows. Guarded here rather than in
# the card's own harness because the fact being protected is the DIFFERENCE
# between the two files, and a guard living in one of them can only see half of
# it.
GRANTS="Casberi/Casberi/Screens/WalletApprovalExposureCard.swift"
# Read from a COMMENT-STRIPPED copy, and match the CALL: the note above
# the chevron explains the rule by naming the component, so a raw grep
# scored the prose as the code and deleting the row's chevron ran green
# (the Obsidian/Cursor lesson, caught by mutation on this guard's first run).
strip "$GRANTS" | grep -q 'WalletRowChevron()' || fail "the approvals rows lost their chevron — they look exactly like the inert list above them"
# ...and it must be the room's shared glyph, not a second grammar for the same
# promise (`WalletRowChevron`'s own header: six spellings once, two survive).
strip "$GRANTS" | grep -q 'Image(systemName: "chevron'   && fail "the approvals rows draw their own chevron instead of the room's one glyph"
# A tap that finds nothing must SAY so — a silent return is indistinguishable
# from the door being broken, which is the report this pass answered.
# Blank lines squeezed first — `strip` leaves a comment as an empty line, so a
# bare `-A` counts the prose rather than the code under it (the ruling above).
strip "$FEED" | sed '/^[[:space:]]*$/d' | grep -A 3 'first(where: { $0.isLive && $0.id == grant.thingID })' | grep -q 'chrome.flash' || fail "a stale approval row taps into silence again"

# The card speaks as ONE sentence (§299), like the risk bars two scopes over.
grep -q 'accessibilityElement(children: .combine)' "$CARD" \
  || fail "the card stopped speaking as one ordered sentence"

# THE SLOT IS COUNTS, NEVER NAMES (prd §546, user: "we can't just repeat the
# list", then "do the counts"). The rung rows used to carry a name subline,
# which on a sparse wallet made the slot the acting list restated word for
# word — the drawing and the list under it saying the same two facts twice.
# The names' one home is the two lists below; the slot's reading is the
# AGGREGATE, which a per-actor list structurally does not have. Read from a
# COMMENT-STRIPPED copy: the card documents this rule by naming what it must
# not do.
strip "$CARD" | grep -qE '\.names|rung\.names' \
  && fail "the slot names a holder again — that is the list restated (§546)"
# ...and the numerals must stay at figure size: the count IS the drawing now,
# so demoting it back to a row-sized stat is the old list wearing a new doc.
grep -q 'dsText(.price40)' "$CARD" \
  || fail "the slot's counts are no longer drawn as figures (§546)"

print "  ok   18 mutations, 25 drift guards"
