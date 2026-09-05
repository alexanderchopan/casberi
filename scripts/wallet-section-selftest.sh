#!/bin/zsh
# The wallet room's SCOPE rules (prd §483), compiled AS SHIPPED.
#
# `Model/WalletSection.swift` is Foundation-only by design, so this compiles it
# WHOLE and unmodified — no stubs, no copied logic. Every failure it catches
# renders as a perfectly ordinary room, which is the whole reason it exists:
#
#   • a scope that never appears, because `present(…)` dropped its flag —
#     indistinguishable from a wallet that genuinely has no positions
#   • a remembered scope resolving to the WRONG one, so the room opens
#     somewhere nobody picked and nothing on screen can explain why
#   • a conditional scope landing mid-strip, so every chip after it shifts the
#     day an approval is revoked — a control that reflows under you
#   • the strip drawing over a single scope, which is a label wearing a
#     control's clothes (§83)
#
# None of that fails a build, a screen sweep or a probe.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/WalletSection.swift"
VERIFY="scripts/verify.sh"
MAIN="Casberi/Casberi/Shell/MainSurface.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
SWITCH="Casberi/Casberi/Design/DSSectionSwitcher.swift"
SLAB="Casberi/Casberi/Design/DSRoomRailSlab.swift"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { print -u2 "✗ $1"; exit 1; }

# ── the assertions, run against the shipped source ───────────────────────────
cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// ORDER is a ruling, not an accident of declaration.
check(WalletSection.order == [.home, .activity, .holdings, .positions, .nfts, .risk, .permissions],
      "order is home → activity → holdings → positions → nfts → risk → permissions")
check(WalletSection.order.count == WalletSection.allCases.count,
      "order lists every case — a new scope cannot be silently unlisted")

// THE STRUCTURAL RULE: every conditional scope sits at the END. A conditional
// scope in the middle shifts every scope after it the day it appears.
let firstConditional = WalletSection.order.firstIndex { $0.isConditional }!
let lastUnconditional = WalletSection.order.lastIndex { !$0.isConditional }!
check(lastUnconditional < firstConditional,
      "no unconditional scope sits after a conditional one")
check(WalletSection.order.last == .permissions, "permissions is last")
check(WalletSection.order.first == .home, "home leads")

// activity is the front door and is never conditional.
check(WalletSection.home.isAlwaysPresent, "home is always present")
check(WalletSection.activity.isAlwaysPresent, "activity is always present")
check(!WalletSection.home.isConditional, "home is not conditional")
check(!WalletSection.activity.isConditional, "activity is not conditional")
check(!WalletSection.holdings.isConditional, "holdings is not conditional")
for s in [WalletSection.positions, .nfts, .risk, .permissions] {
    check(s.isConditional, "\(s.rawValue) is conditional")
}

// present(): EVERY scope, on every wallet (prd §611). The gate is gone — a
// wallet with no positions, no NFTs, no leverage and no approvals still reaches
// all seven chips, each with an empty state of its own.
let all = WalletSection.present()
check(all == WalletSection.order, "every scope is present, in order")
check(all.count == WalletSection.allCases.count, "no scope is hidden from anybody")

// THE OBLIGATION THAT MAKES THAT HONEST. A chip that opens onto nothing is the
// dead control §83 bans; the scopes that can be empty are allowed only because
// each says what it would hold. A scope that can be empty and has no words is
// the failure.
for s in WalletSection.allCases where s != .home {
    check(!(s.emptyHeadline ?? "").isEmpty, "\(s.rawValue) names its own empty state")
    check(!(s.emptyBody ?? "").isEmpty, "\(s.rawValue) says what it would hold")
    check(s.emptyBody != s.summary, "\(s.rawValue)'s empty state is not its summary restated")
    check((s.emptyBody ?? "").count > 24, "\(s.rawValue)'s empty state teaches rather than labels")
}
// Chips sharing one sentence is the banned strip in new clothes.
let emptyBodies = WalletSection.allCases.compactMap(\.emptyBody)
check(Set(emptyBodies).count == emptyBodies.count, "no two scopes explain themselves the same way")
let emptyHeads = WalletSection.allCases.compactMap(\.emptyHeadline)
check(Set(emptyHeads).count == emptyHeads.count, "no two scopes name the same empty state")
// Home is never empty — its crown IS its content — so it has no empty copy to
// go stale in a branch nothing can reach.
check(WalletSection.home.emptyHeadline == nil && WalletSection.home.emptyBody == nil,
      "home carries no empty copy, because it can never be empty")
// No door in any of them: every verb lives on the card that has something to act on.
for words in emptyBodies {
    let lower = words.lowercased()
    check(!lower.contains("tap ") && !lower.contains("top up") && !lower.contains("send "),
          "an empty scope states a fact and offers no door")
}

// resolve(): the fallback is activity, NEVER "the first present scope". The
// two differ only when activity is absent, which cannot happen — and that is
// the point, since the wrong fallback silently opens somewhere nobody chose.
check(WalletSection.resolve(nil, present: all) == .home,
      "nil resolves to home — the room's front door")
check(WalletSection.resolve(.risk, present: all) == .risk,
      "a present scope resolves to itself")
check(WalletSection.resolve(.permissions, present: [.home, .holdings]) == .home,
      "a scope whose content has gone falls back to home")
check(WalletSection.resolve(.holdings, present: [.holdings, .risk]) == .holdings,
      "resolve honours a present scope even when activity is absent")
// The fixture that separates "falls back to activity" from "falls back to the
// first present scope" — without it, both implementations pass every case above.
check(WalletSection.resolve(.permissions, present: [.holdings, .home]) == .home,
      "falls back to HOME, not to the first entry of `present`")

// shows(): one scope is a label, not a control (§83).
check(!WalletSection.shows(present: [.home]), "one scope draws no strip")
check(!WalletSection.shows(present: []), "no scopes draw no strip")
check(WalletSection.shows(present: [.home, .activity]), "two scopes draw a strip")

// The labels are the ruled short nouns. Spelled out because the ruling was
// specifically that the four QUESTIONS are too long for a control.
check(WalletSection.home.label == "Home", "home reads Home")
check(WalletSection.activity.label == "Activity", "activity reads Activity")
check(WalletSection.holdings.label == "Holdings", "holdings reads Holdings")
check(WalletSection.positions.label == "Positions", "positions reads Positions")
check(WalletSection.nfts.label == "NFTs", "nfts reads NFTs")
check(WalletSection.risk.label == "Risk", "risk reads Risk")
check(WalletSection.permissions.label == "Permissions", "permissions reads Permissions")
for s in WalletSection.allCases {
    check(!s.label.contains(" "), "\(s.rawValue)'s label is ONE word — the strip must not wrap")
    check(s.label.count <= 11, "\(s.rawValue)'s label is short enough for a chip")
    check(!s.summary.isEmpty, "\(s.rawValue) carries an accessibility summary")
    check(s.summary != s.label, "\(s.rawValue)'s summary says more than its label")
}

// Identity is stable — the switcher scrolls to `id`, and a computed id that
// changed between renders would make the strip re-centre on nothing.
check(WalletSection.risk.id == "risk", "id is the raw value")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   \(WalletSection.allCases.count) scopes, order, presence, resolve, shows, labels")
SWIFT

build() {
  swiftc -O -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1
}

cp "$SRC" "$work/WalletSection.swift"
build "$work/WalletSection.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

# ── mutations ────────────────────────────────────────────────────────────────
# A check that cannot fail proves nothing. Each of these is a silent wrong
# answer that renders as an ordinary room.
mutate() {
  local why="$1" sedexpr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$sedexpr" "$work/m.swift"
  if ! cmp -s "$SRC" "$work/m.swift"; then :; else fail "mutation matched nothing: $why"; fi
  if build "$work/m.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  print "  ok   catches  $why"
}

mutate "a conditional scope moved out of the tail (the strip reflows)" \
  's/\.home, \.activity, \.holdings, \.positions, \.nfts, \.risk, \.permissions,/.home, .risk, .activity, .holdings, .positions, .nfts, .permissions,/'
mutate "home no longer leads" \
  's/\.home, \.activity, \.holdings/.holdings, .home, .activity/'
mutate "resolve falls back to the first present scope instead of activity" \
  's/guard let wanted, present\.contains\(wanted\) else \{ return \.home \}/guard let wanted, present.contains(wanted) else { return present.first ?? .home }/'
mutate "shows() lets a single scope draw a control" \
  's/present\.count > 1/present.count > 0/'
mutate "risk is marked unconditional, so the tail rule stops being enforced" \
  's/case \.positions, \.nfts, \.risk, \.permissions: return true/case .positions, .nfts, .permissions: return true\n        case .risk: return false/'
mutate "every scope gated again, so five chips vanish on the wallet that most needs them" \
  's/static func present\(\) -> \[WalletSection\] \{ order \}/static func present() -> [WalletSection] { order.filter { !\$0.isConditional } }/'
mutate "an empty scope left with nothing to say — the dead control this ruling depends on avoiding" \
  's/A position a price move could liquidate, and how close it stands\. Nothing here carries leverage\./ /'
mutate "the ruled short noun becomes a question again" \
  's/String\(localized: "Permissions"\)/String(localized: "Who can reach it")/'

# ── drift guards ─────────────────────────────────────────────────────────────
# The wiring the compiled enum cannot prove. Read from a COMMENT-STRIPPED copy:
# these files DOCUMENT the rules by naming what they must not do, so a guard
# grepping raw source scores prose as compliance (the Obsidian/Cursor lesson).
strip_comments() { perl -pe 's{//.*$}{}g' "$1"; }
for f in "$MAIN" "$FEED" "$CHROME" "$SWITCH" "$SLAB" "$SRC"; do
  strip_comments "$f" > "$work/$(basename $f).bare"
done

# **A guard that cannot fire proves nothing**, so both of these hard-fail when
# the file they were pointed at is absent. Written the obvious way first, this
# suite shipped a `deny` against a `.bare` file the loop above never created:
# `grep` failed for want of a file, `&& fail … || true` swallowed the non-zero,
# and the guard reported ok having read nothing at all.
have() { [[ -f "$work/$1.bare" ]] || fail "guard points at a file that was never prepared: $1"; }
guard() { have "$1"; grep -q -- "$2" "$work/$1.bare" || fail "drift: $3"; }
deny()  { have "$1"; if grep -q -- "$2" "$work/$1.bare"; then fail "drift: $3"; fi }

guard MainSurface.swift "extension WalletSection: DSSectionScope" \
  "the conformance moved — it must stay OUT of the Foundation-only model file"

# BELOW THE SPARKLINE, IN THE CONTENT (user ruling, 2026-08-26: "we need to have
# those toggles be below the sparkline", "we cannot have four rows of chips").
# It mounted in roomControls for one build, which made it the FOURTH pinned strip
# and pushed the crown to about 45% down the screen.
deny MainSurface.swift "walletSectionSwitcher" \
  "the switcher is back in roomControls — it belongs in the room's content, under the crown"
# THE GUARD FOLLOWED ITS SUBJECT (prd §547, 2026-09-01). It asked for
# `DSSectionSwitcher(` in FeedScreen until the switcher stopped being drawn
# there directly: it is the lower deck of `DSRoomRailSlab` now, which the room
# mounts instead. The RULE is unchanged and is the only thing this ever meant —
# the control that scopes the room is drawn in the room's own content, not
# pinned in `roomControls` (the `deny` directly above is its other half).
guard FeedScreen.swift "DSRoomRailSlab(" \
  "the scope control is not drawn in the room's content"
# ...and the slab really carries the switcher, rather than having become a rail
# with the scope control quietly dropped. Without this the pair above passes on
# a room that lost half of what it is scoping by.
guard DSRoomRailSlab.swift "DSSectionSwitcher(" \
  "the slab no longer draws the scope switcher — fusing must not delete a deck"
guard FeedScreen.swift "WalletSection.shows(present:" \
  "the draw is not gated on shows() — a single scope would draw a control (\u00a783)"
guard FeedScreen.swift "WalletSection.resolve(" \
  "the room reads chrome.walletSection raw instead of resolving it"

# The crown and its chart belong to NO scope, so the switcher must come AFTER
# them: above it, the toggle would appear to scope the balance it does not scope.
# **`|| true` IS LOAD-BEARING, and its absence made this guard fail SILENTLY**
# (prd §495). Under `set -e` an assignment takes the exit status of its command
# substitution, so a `grep` that matches nothing kills the script THERE —
# before reaching the `|| fail` written two lines below to explain it. The
# whole harness then exited 1 having printed every check as ok and no reason
# at all, which is the "a check that cannot say why is not a check" failure
# this repo bans, arriving in the checker rather than the code.
#
# The anchor itself had also drifted: the crown's call gained `streamTotal:`
# and `drawsChart:` (§483) and lost `latest:`, so it had been matching nothing
# for several commits. Anchored on the FUNCTION NAME plus its first argument,
# which is what this guard actually cares about — the crown's position — and
# not on a signature that will keep changing.
crown_at=$(grep -n "walletTilesSection(visible" "$work/FeedScreen.swift.bare" | head -1 | cut -d: -f1 || true)
# The CALL SITE, not the declaration — which sits earlier in the file and
# made this guard fire on a correctly-ordered room the first time it ran.
#
# **The anchor moved with its subject** (prd §547): the switcher's own section
# is gone, so what has to sit below the crown is the SLAB that carries it.
# `walletScopeRailSection(section)` is that call, and it takes an argument now
# precisely because it absorbed the switcher's — which is what keeps this
# anchored on a call site rather than on a bare identifier that also matches
# the declaration.
switch_at=$(grep -n "walletScopeRailSection(section)" "$work/FeedScreen.swift.bare" | head -1 | cut -d: -f1 || true)
[[ -n "$crown_at" && -n "$switch_at" ]] || fail "drift: cannot locate the crown or the switcher in the wallet block"
(( crown_at < switch_at )) || fail "drift: the switcher is drawn ABOVE the crown — it must sit below the sparkline"

# EVERY empty-state gate must be the section's OWN render gate, spelled the same
# way (prd §611 moved these from presence flags to `walletScopeIsEmpty`; the
# rule is unchanged). Reported from the device as "we can't do this" — the Risk
# chip opening an empty page, because presence read `!= nil` while the section
# needs non-empty. Now the failure would be a scope drawing its figure AND its
# empty state, or neither.
guard FeedScreen.swift "WalletSection.present()" \
  "the strip is deriving its scopes from evidence again — five chips vanish on the wallet that most needs to learn what they are (§611)"
deny  FeedScreen.swift "WalletSection.present(holdings:" \
  "present() is being handed evidence again — the gate §611 removed"
guard FeedScreen.swift "case .positions:   return !(hasLendingCard" \
  "positions' empty gate no longer reads hasLendingCard — figure and empty state drift, and the slot shows both or neither"
guard FeedScreen.swift "case .risk:        return (walletRiskEntries ?? \[\]).isEmpty" \
  "risk's empty gate is on nil-ness again — a non-nil EMPTY strip would draw neither the figure nor the words"
guard FeedScreen.swift "case _ where walletScopeIsEmpty(section):" \
  "the slot no longer draws a scope's empty state — a chip onto an empty scope opens 258 blank points (§611)"
guard FeedScreen.swift "WalletScopeEmptyFigure(section: section)" \
  "the empty state stopped reading the scope's own words, so every empty scope says the same thing"

guard FeedScreen.swift "chrome.walletSections = " \
  "the room no longer publishes its present scopes"
guard FeedScreen.swift "chrome.walletSections = \[\]" \
  "the room no longer CLEARS its scopes — the toggle would draw over the next room"
guard FeedScreen.swift "walletLive.warnings" \
  "the dot no longer rides warnings — presence-lighting is the §83 overclaim that retired 'Needs attention'"
guard FeedScreen.swift "case .activity:" \
  "the wallet block no longer switches on the scope"
guard FeedScreen.swift "Ahead" \
  "the forward-dated rows lost their heading in Activity"

# The Foundation-only promise: this file must stay compilable without SwiftUI,
# or the harness above cannot run at all.
deny WalletSection.swift "import SwiftUI" "WalletSection imports SwiftUI — it must stay compilable without it, or this harness cannot run at all"

# The shared control must stay generic — a Wallet-shaped assumption inside it
# is the fork Vibenet asked us to avoid before either room shipped.
deny DSSectionSwitcher.swift "WalletSection" \
  "DSSectionSwitcher names WalletSection — it must stay generic over DSSectionScope"

# This harness must stay in verify.sh's hand list (that guard fails the build
# until it is named WITH its reason, which is the part that gets skipped).
grep -q "wallet-section-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

print "  ok   drift guards: mount, gate, publication, clear, dot, scopes, generic control"
print "✓ wallet sections: order, presence, resolve, shows, labels, 8 mutations, 16 drift guards"
