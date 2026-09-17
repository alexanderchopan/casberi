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
# FeedScreen is split across files (prd §718). Every check reads the room as ONE
# text, so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d -t feedscreen)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift > "$FEED"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
SWITCH="Casberi/Casberi/Design/DSSectionSwitcher.swift"
# The one template all five wallet-family rooms wear (prd §747), and the three
# views it composes. Every guard below reads them comment-stripped, because
# these files DOCUMENT the ruling by naming what they replaced.
CHROMEVIEW="Casberi/Casberi/Design/DSRoomScopeChrome.swift"
SCOPEROWS="Casberi/Casberi/Design/DSScopeRows.swift"
SCOPEHEAD="Casberi/Casberi/Design/DSScopeTiles.swift"
EMPTYFIG="Casberi/Casberi/Screens/WalletScopeEmptyFigure.swift"
CHASSIS="Casberi/Casberi/Design/DSRoomChassis.swift"
ACTIVITY="Casberi/Casberi/Screens/RoomActivityChart.swift"
CHIPS="Casberi/Casberi/Design/DSChip.swift"   # DSRangeChips lives beside Chip since prd §746

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
check(WalletSection.order == [.home, .activity, .holdings, .accounts, .positions, .nfts, .risk, .permissions],
      "order is home → activity → holdings → accounts → positions → nfts → risk → permissions")
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
for s in WalletSection.allCases {
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
// **HOME CAN BE EMPTY, AND IT SAYS SO (prd §761).** This asserted the opposite
// until then — "home carries no empty copy, because it can never be empty" —
// on the premise that its crown IS its content. `walletTilesSection`'s own gate
// disproves it: no total, no line, no warning, no composition and no recent row
// draws nothing at all, which the reserved 300pt box rendered as a card of
// black and §757's collapse rendered as a room that opens on `Actions` with no
// explanation. Home is in the loop above now; this pins the case that was
// exempt from it.
check(!(WalletSection.home.emptyHeadline ?? "").isEmpty
      && !(WalletSection.home.emptyBody ?? "").isEmpty,
      "home says what it would hold, like every other scope")
// …and it may not say WHY it is missing (§83): `total` is nil both before the
// holdings read lands and when nothing priced was found, and no code here can
// tell those apart, so a promise about loading would be a true-sounding claim
// the room cannot stand behind.
for words in [WalletSection.home.emptyBody ?? ""] {
    let lower = words.lowercased()
    check(!lower.contains("loading") && !lower.contains("still reading")
          && !lower.contains("will appear") && !lower.contains("once the read"),
          "home's empty copy claims a load state it cannot know (§83)")
}
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
  # `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
  # and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
  # a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
  # so this file was proven equivalent run-for-run by
  # `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 1.4x faster).
  # Re-probe before trusting it again after adding mutations.
  swiftc -Onone -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1
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
  echo "  ok   catches  $why"
}

mutate "a conditional scope moved out of the tail (the strip reflows)" \
  's/\.home, \.activity, \.holdings, \.accounts, \.positions, \.nfts, \.risk, \.permissions,/.home, .risk, .activity, .holdings, .accounts, .positions, .nfts, .permissions,/'
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
  's/A position a price move could liquidate, and how close it stands\./ /'
mutate "the ruled short noun becomes a question again" \
  's/String\(localized: "Permissions"\)/String(localized: "Who can reach it")/'
mutate "home loses its empty copy again, so the wallet room says nothing when nothing came back (prd §761)" \
  's/case \.home:        return String\(localized: "No balance yet"\)/case .home:        return nil/'
mutate "home's empty copy promises a load state it cannot know (§83)" \
  's/What these accounts are worth, and the line it traces\./The balance will appear once the read lands./'

# ── drift guards ─────────────────────────────────────────────────────────────
# The wiring the compiled enum cannot prove. Read from a COMMENT-STRIPPED copy:
# these files DOCUMENT the rules by naming what they must not do, so a guard
# grepping raw source scores prose as compliance (the Obsidian/Cursor lesson).
strip_comments() { perl -pe 's{//.*$}{}g' "$1"; }
for f in "$MAIN" "$FEED" "$CHROME" "$SWITCH" "$CHROMEVIEW" "$SCOPEROWS" "$SCOPEHEAD" \
         "$SRC" "$CHASSIS" "$ACTIVITY" "$CHIPS" "$EMPTYFIG"; do
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
# THE GUARD FOLLOWED ITS SUBJECT, TWICE (§547 → prd §747, 2026-09-15). It asked
# for `DSSectionSwitcher(` in FeedScreen until the switcher became the slab's
# lower deck, then for `DSRoomRailSlab(` until the slab was deleted outright.
# The RULE is unchanged and is the only thing this ever meant — the control that
# scopes the room is drawn in the room's own content, not pinned in
# `roomControls` (the `deny` directly above is its other half).
guard FeedScreen.swift "DSRoomScopeChrome(" \
  "the scope control is not drawn in the room's content"
# ...and the chrome really carries BOTH halves, rather than having become a deck
# with the readings quietly dropped. Home draws them as rows, a pushed scope as
# a header; without both this passes on a room that lost what it scopes by.
guard DSRoomScopeChrome.swift "DSScopeRows(" \
  "the chrome no longer draws the scope rows — Home's list IS the readings (§747)"
# **THE HEADER BECAME TILES, UNDER THE FIGURE** (prd §752, user: "i don't want
# the app to have controls at the top of the screen anywhere"). The chrome draws
# the scopes as a grid, and nothing brings the strip back.
guard DSRoomScopeChrome.swift "DSScopeTiles(" \
  "the chrome no longer draws the scope tiles — a pushed scope must offer the rest (§752)"
deny DSRoomScopeChrome.swift "DSScopeHeader(" \
  "the scope header is back — a control at the top of the screen (§752)"
# **THE ACCOUNTS ARE THE SHELL'S FACE RAIL, NOT A DECK** (prd §750, user: "put
# the wallets row of accounts on a third row above the tab bar like we do for
# socials"). The deck is deleted; the chrome publishes its accounts and the
# shell draws them where the social faces are. Both halves, because a chrome
# that stops publishing leaves the shell's rail silently empty.
guard DSRoomScopeChrome.swift "chrome.accountRail = rail" \
  "the chrome no longer publishes its accounts — the rail above the dock is empty (§750)"
grep -q "private var accountRail: some View" Casberi/Casberi/Shell/MainSurface.swift \
  && grep -q "        accountRail$" Casberi/Casberi/Shell/MainSurface.swift \
  || fail "the shell no longer mounts the account rail beside the social faces (§750)"
deny DSRoomScopeChrome.swift "DSAccountDeck(" \
  "the account deck is back — the faces over the figure read as a contacts header (§750)"
# THE SWIPE IS THE ROOM'S, NOT THE SCOPES' (user ruling, prd §747: "inside can't
# be swipe bc swipe is for rooms but can be a scroll header"). A header that
# grew a DragGesture would make one gesture mean two things by depth.
deny DSScopeTiles.swift "DragGesture" \
  "the scope tiles take a swipe — the swipe is the room's and the pick is a tap (§747)"
# Off Home the figure leads and the tiles follow it (§752), and since §765 the
# CHROME draws that figure, in the same lead box Home's crown takes — so the
# tiles land at one height on every page. A figure drawn as a sibling Section
# above the chrome takes its own insets and the List's section spacing, and the
# tiles walk up and down as you pick (user, 2026-09-15).
chrome_bare=$(sed -e 's://.*$::' Casberi/Casberi/Design/DSRoomScopeChrome.swift)
lead_at=$(print -r -- "$chrome_bare" | grep -n "^            lead$" | head -1 | cut -d: -f1 || true)
tiles_at=$(print -r -- "$chrome_bare" | grep -n "DSScopeTiles(" | head -1 | cut -d: -f1 || true)
[[ -n "$lead_at" && -n "$tiles_at" ]] && (( lead_at < tiles_at )) \
  || fail "drift: the chrome's lead box is not drawn before its tiles — controls at the top, or a moving bar (§752, §765)"
[[ "$chrome_bare" == *"figure(active)"* && "$chrome_bare" == *"height: DSRoomChassis.visualSlot"* ]] \
  || fail "drift: the chrome no longer draws the section figure in the fixed lead box — the tiles move between pages (§765)"
wallet_fn=$(sed -n '/func walletScopeChromeSection(/,/^    }$/p' "$work/FeedScreen.swift.bare")
[[ "$wallet_fn" == *"figure: { scope in"* && "$wallet_fn" == *"walletScopeVisualSection(scope)"* ]] \
  || fail "drift: the wallet no longer hands its section figure to the chrome (§765)"
for sibling in "FramesRoomFigure(head: head," "HegotaRoomFigure(head: head,"; do
  (( $(grep -c "$sibling" "$work/FeedScreen.swift.bare") == 2 )) \
    || fail "drift: a devnet figure is drawn outside the chrome again — its tiles move between pages (§765): $sibling"
done
# A ROOM WITH ONE READING DRAWS NO ROWS (\u00a783). The gate used to sit in the
# room, beside the switcher it suppressed; under \u00a7744 the chrome must draw on
# Home either way (it carries the crown and the acts), so the gate moved into
# the rows themselves. Same rule, one place, all five rooms.
guard DSScopeRows.swift "if !sections.isEmpty" \
  "the rows are not gated — a room with one reading would draw an empty plate (\u00a783)"
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
# **The anchor moved with its subject again** (prd §747). The slab and its
# switcher are deleted: the crown is the `crown:` argument of
# `DSRoomScopeChrome`, drawn inside the account deck's card, and the scopes are
# `DSScopeRows` BELOW that deck. Source order in FeedScreen no longer says draw
# order (a closure argument follows its call), so the guard reads both halves:
# the wallet passes its sparkline as the chrome's crown, and the chrome draws
# it first (see the order check below).
chrome_fn=$(sed -n '/func walletScopeChromeSection(/,/^    }$/p' "$work/FeedScreen.swift.bare")
[[ "$chrome_fn" == *"DSRoomScopeChrome("* && "$chrome_fn" == *"crown: { slot in"* \
   && "$chrome_fn" == *"walletTilesSection(visible"* ]] \
  || fail "drift: the wallet no longer passes its crown into DSRoomScopeChrome"
# **One surface, in reading order** (prd §750): the head, then Actions, then
# Readings. Read in the chrome, where the order is the source order.
CHROME="Casberi/Casberi/Design/DSRoomScopeChrome.swift"
# Since §765 the crown is drawn by `lead`, the one box both arms share, so the
# head's place in the order is the `lead` call and `lead` must draw the crown.
grep -q "if let showing { crown(showing) }" "$CHROME" \
  || fail "drift: the chrome's lead box no longer draws the crown on Home (§765)"
head_at=$(grep -n "^            lead$" "$CHROME" | head -1 | cut -d: -f1 || true)
acts_at=$(grep -n 'String(localized: "Actions")' "$CHROME" | head -1 | cut -d: -f1 || true)
rows_at=$(grep -n "DSScopeRows(sections:" "$CHROME" | head -1 | cut -d: -f1 || true)
[[ -n "$head_at" && -n "$acts_at" && -n "$rows_at" ]] \
  || fail "drift: cannot locate the head, Actions or the Readings in DSRoomScopeChrome"
(( head_at < acts_at && acts_at < rows_at )) \
  || fail "drift: Home is out of order — the head, then Actions, then Readings (§750)"
# ...and the section tiles sit between the head and Actions on Home too (§752b,
# user: "i think they should always show"). The first match is Home's.
tiles_at=$(grep -n "DSScopeTiles(sections:" "$CHROME" | head -1 | cut -d: -f1 || true)
[[ -n "$tiles_at" ]] && (( head_at < tiles_at && tiles_at < acts_at )) \
  || fail "drift: Home's section tiles are missing or out of order — the head, then the tiles, then Actions (§752b)"
guard DSScopeRows.swift "section.glyph" \
  "the Readings rows lost their glyph — they must lead with the tile's symbol (§752b)"

# ── §757: the rows stand on nothing, and Home reserves no box ────────────────
# **THE PLATES** (user, 2026-09-15: "they should not have cards"). Actions and
# Readings drew on `dsWidgetSurface`, the elevated card — the one thing §749
# took off every row in the app ("i made a mistake by adding cards to rows") and
# §708 off every account page ("nothing on an account page is boxed but the
# entry well"). This was the last surface in the app drawing rows on plates.
#
# §757 kept the HEAD's plate on the grounds that a head card is what every room
# draws. A day later the user said the same thing about a room head ("again
# here, we don't want cards that are like this"), so §758 took it off the head
# template and off this crown: NOTHING on Home stands on a plate, and the guard
# is a plain `deny` on both files.
deny DSScopeRows.swift "dsWidgetSurface" \
  "the readings are back on a plate — §749 took the card off every row in the app (§757)"
deny DSRoomScopeChrome.swift "dsWidgetSurface" \
  "a block on the wallet family's Home is on a plate again — the head, the acts and the readings are all content on the page (§757/§758)"

# **THE CROWN'S EMPTY BRANCH SAYS WHAT IT WOULD HOLD (prd §761).**
# `walletTilesSection`'s gate is an honesty floor — nothing drawn rather than a
# card with nothing in it — and for as long as `DSRoomSlot` reserved 300pt, that
# rendered as a card of black; §757 dropped the floor and it renders as a room
# that opens on `Actions` with no explanation. Home is a scope like the other
# seven now: its words live in `WalletSection` and are drawn by the one figure.
guard FeedScreen.swift "WalletScopeEmptyFigure(section: .home, padded: false)" \
  "the wallet crown's empty branch draws nothing again, or hand-rolls its own copy instead of \`WalletSection\`'s (§611/§761)"
# `padded: false` is not decoration: Home's crown sets no horizontal padding of
# its own, so the scope slot's pad would set these words 16pt right of the
# balance they stand in for. The HEIGHT is not switched — §760 put the 300pt box
# back on Home, and this empty state fills it like every other scope's.
guard WalletScopeEmptyFigure.swift "var padded: Bool = true" \
  "the empty figure lost its pad switch — Home's crown would take the scope slot's 16pt and sit off the balance's edge (§761)"

# **THE 300pt BOX ON HOME, AND THE DECK THAT IS NOT THERE.** `DSRoomSlot` pins
# every scope figure to `visualSlot` so the scopes align and the drawings sized
# off that constant get their height. §747 gave HOME the same box for a second
# reason — the account deck paged sideways — and §750/§753 deleted the deck. All
# it reserved afterwards was 200pt of black under a balance whose second reading
# has not landed yet.
# §760 REVERSED THE DROP: every room's lead is held to this height, and Home is
# where it was taken from, so no slot may opt out of the box again.
deny DSRoomChassis.swift "reservesBox" \
  "a slot can opt out of the fixed box again — every room's lead is held to Home's height (§760, reversing §757)"
deny FeedScreen.swift "reservesBox" \
  "a Home crown drops the fixed box again — the height every other room's lead copies (§760)"
guard DSRoomChassis.swift "minHeight: DSRoomChassis.visualSlot" \
  "DSRoomSlot no longer pins its floor to visualSlot — the Home crown shrinks below every other room's lead (§760)"
grep -q "DSRoomSlot(headline: nil, reservesHeadline: false) {" "$work/FeedScreen.swift.bare" \
  || fail "drift: the wallet's OFF-Home figure lost the fixed slot — a drawing sized for the whole box is clipped along its bottom (§757/§495)"

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

# ── the crown's budget pays for its range chips (2026-09-14) ─────────────────
# `DSRoomSlot` is a hard box with `.clipped()`, so a crown whose line takes the
# whole box pushes its own range track out through the bottom edge — reported
# as "7d and watched is clipping", and the failure renders as an ordinary room
# with a sliced control. §688 measured the chips and spent them in
# `RoomHomeCrown` only; the Wallet's crown and `RoomActivityChart` build their
# own headline and went on budgeting them at nothing. One expression now, asked
# per drawing, because the chips are not always offered.
guard DSRoomChassis.swift "crownChrome + (chips ? crownRangeChips : 0)" \
  "the chips left the crown's budget — every crown drawing a range track clips it again"
guard FeedScreen.swift "DSRoomChassis.crownChart(chips: ranges.count > 1)" \
  "the wallet crown stopped paying for its range chips — the 7d/Watched track clips at the slot's edge"
guard RoomActivityChart.swift "DSRoomChassis.crownChart(box: box, chips: chips)" \
  "the activity chart stopped paying for its range chips — its track clips exactly as the crown's did"
# The predicate must stay the chips' OWN gate. A budget that asks a different
# question than the drawing does is the same clip wearing a second answer.
guard RoomActivityChart.swift "chartHeight(chips: offered.count > 1)" \
  "the activity chart's budget no longer reads the offered windows — it can reserve the track on a record that draws none, or none on one that does"
guard DSChip.swift "if ranges.count > 1" \
  "the chips' own draw gate moved — every budget above spells this predicate and would now be asking the wrong question"

echo "  ok   drift guards: mount, gate, publication, clear, dot, scopes, generic control, crown chip budget"
echo "✓ wallet sections: order, presence, resolve, shows, labels, 8 mutations, 16 drift guards"
