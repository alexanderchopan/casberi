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
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
SWITCH="Casberi/Casberi/Design/DSSectionSwitcher.swift"
# The one template the wallet family wears (prd §747, the box · tiles · menu
# of §1039), and the views it composes. Every guard below reads them
# comment-stripped, because these files DOCUMENT the ruling by naming what
# they replaced. (`DSScopeRows` and `RoomActivityChart` are deleted, prd §1039.)
CHROMEVIEW="Casberi/Casberi/Design/DSRoomScopeChrome.swift"
SCOPEHEAD="Casberi/Casberi/Design/DSScopeTiles.swift"
EMPTYFIG="Casberi/Casberi/Screens/WalletScopeEmptyFigure.swift"
CHASSIS="Casberi/Casberi/Design/DSRoomChassis.swift"
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
check(WalletSection.order == [.home, .holdings, .activity, .spending],
      "order is home → holdings → activity → spending (prd §1480, §1529)")
// **FOUR TILES (prd §1480, §1529).** Security is deleted — its parts are Your
// account, Permissions and Threats, each a page off Home — and Markets is
// deleted (§1529). A remembered "security" or "markets" must resolve to Home,
// never to a page that claims to be it.
for gone in ["security", "comingUp", "risk", "watch", "cards", "accounts", "markets"] {
    check(WalletSection(rawValue: gone) == nil, "\(gone) is not a scope (prd §1107, §1480)")
}
check(WalletSection.order.count == 4, "the wallet has four tiles (prd §1529)")
check(WalletSection.activity.label == "Activity", "the stream's tile reads Activity (prd §1480)")
check(WalletSection.spending.label == "Spending", "the tile reads Spending — Home's list's own word (prd §1201)")
// **EVERY OTHER CASE IS A PAGE BEHIND A DOOR (prd §1480).** Home's five,
// Holdings' four and Spending's four; together with the tiles they are
// every case, each once, so a new scope cannot be silently unlisted.
let doors = WalletSection.homeDoors + WalletSection.holdingsDoors + WalletSection.spendingDoors
    + WalletSection.yourAccountDoors
check(Set(WalletSection.order).union(doors) == Set(WalletSection.allCases)
      && WalletSection.order.count + doors.count == WalletSection.allCases.count,
      "the tiles and the doors list every case once (prd §1480)")
check(WalletSection.homeDoors == [.yourAccount, .following, .needsYou, .permissions, .threats],
      "Home's doors are Your account, Following, Needs you, Permissions, Threats (prd §1480, §1498)")
check(WalletSection.holdingsDoors == [.holdingAccounts, .apps, .positions, .nfts],
      "Holdings' pages are Following, Apps, Positions, NFTs (You narrows, Tokens is its sheet) (prd §1503)")
check(WalletSection.spendingDoors == [.subscriptions, .places, .fees, .roundUps],
      "Spending's doors are Subscriptions, Places, Fees, Round-ups (prd §1480, §1523)")
check(WalletSection.yourAccountDoors == [.recoveryKey, .nodes],
      "Your account's doors are the recovery key's check and Nodes (prd §1515, §1517)")
// A page goes back to the page it opened from (prd §1480 item 9).
for s in WalletSection.order { check(s.parent == nil && s.isTile, "\(s.rawValue) is a tile with no parent") }
for s in WalletSection.homeDoors { check(s.parent == .home, "\(s.rawValue) goes back to Home") }
for s in WalletSection.holdingsDoors { check(s.parent == .holdings, "\(s.rawValue) goes back to Holdings") }
for s in WalletSection.spendingDoors { check(s.parent == .spending, "\(s.rawValue) goes back to Spending") }
for s in WalletSection.yourAccountDoors { check(s.parent == .yourAccount, "\(s.rawValue) goes back to Your account") }
check(WalletSection.holdingAccounts.label == "Following", "Holdings' wallets you follow read Following, the word Home uses (prd §1503)")
check(WalletSection.following.label == "Following", "what you follow reads Following, never Accounts (prd §1480)")
check(WalletSection.subscriptions.label == "Subscriptions", "the page reads Subscriptions — Day's tile says it too (prd §1111)")

check(WalletSection.order.last == .spending, "spending is last (prd §1529)")
check(WalletSection.order.first == .home, "home leads")

check(WalletSection.home.isAlwaysPresent, "home is always present")
check(!WalletSection.home.isConditional, "home is not conditional")
check(!WalletSection.holdings.isConditional, "holdings is not conditional")
for s in [WalletSection.subscriptions, .activity, .spending, .permissions, .threats] {
    check(s.isConditional, "\(s.rawValue) is conditional")
}

// EVERY TILE IS PRESENT, ALWAYS (prd §611).
let all = WalletSection.present()
check(all == WalletSection.order, "every tile is present, in order")
check(all.count == WalletSection.order.count, "no tile is hidden from anybody")

// Every scope that CAN BE EMPTY teaches its own empty state (prd §611, §799).
let drawn = WalletSection.allCases
for s in drawn {
    check(!(s.emptyHeadline ?? "").isEmpty, "\(s.rawValue) names its own empty state")
    check(!(s.emptyBody ?? "").isEmpty, "\(s.rawValue) says what it would hold")
    check(s.emptyBody != s.summary, "\(s.rawValue)'s empty state is not its summary restated")
    check((s.emptyBody ?? "").count > 24, "\(s.rawValue)'s empty state teaches rather than labels")
}
let emptyBodies = drawn.compactMap(\.emptyBody)
check(Set(emptyBodies).count == emptyBodies.count, "no two scopes explain themselves the same way")
let emptyHeads = drawn.compactMap(\.emptyHeadline)
check(Set(emptyHeads).count == emptyHeads.count, "no two scopes name the same empty state")
for s in WalletSection.order {
    let words = (s.emptyHeadline ?? "") + " " + (s.emptyBody ?? "")
    let lower = words.lowercased()
    check(!lower.contains("loading") && !lower.contains("still reading")
          && !lower.contains("will appear") && !lower.contains("once the read"),
          "\(s.rawValue)'s empty state never claims a read is in flight (§83)")
    check(!lower.contains("tap ") && !lower.contains("top up") && !lower.contains("send "),
          "\(s.rawValue)'s empty state carries no door (§799)")
}

// RESOLVE falls back to Home, never to "the first present scope".
check(WalletSection.resolve(nil, present: all) == .home, "nothing remembered resolves to home")
check(WalletSection.resolve(.spending, present: all) == .spending, "a present scope resolves to itself")
check(WalletSection.resolve(.spending, present: [.home, .holdings]) == .home,
      "an absent scope resolves to home")
check(WalletSection.resolve(.holdings, present: [.holdings, .spending]) == .holdings,
      "a present scope resolves to itself even without home")
// The pair that tells "falls back to home" from "falls back to the first
// present scope" — without it, both implementations pass every case above.
check(WalletSection.resolve(.spending, present: [.holdings, .home]) == .home,
      "an absent scope resolves to home, not to the first present scope")
// A page has no tile, but its door opens it: a door that resolves against
// the tiles alone draws Home under its title.
let pages = WalletSection.pages(tiles: WalletSection.present())
for door in doors {
    check(WalletSection.resolve(door, present: pages) == door, "\(door.rawValue)'s door opens its page, a page with no tile")
    check(pages.filter { $0 == door }.count == 1, "pages lists \(door.rawValue) once")
}

check(!WalletSection.shows(present: [.home]), "one scope draws no strip")
check(!WalletSection.shows(present: []), "no scopes draw no strip")
check(WalletSection.shows(present: [.home, .holdings]), "two scopes draw a strip")

check(WalletSection.home.label == "Home", "home reads Home")
check(WalletSection.holdings.label == "Holdings", "holdings reads Holdings")
for s in WalletSection.allCases {
    check(s.label.split(separator: " ").count <= 2, "\(s.rawValue)'s label fits one tile line — the grid must not wrap")
    check(s.label.count <= 13, "\(s.rawValue)'s label is short enough for a tile")
    check(!s.summary.isEmpty, "\(s.rawValue) carries an accessibility summary")
    check(s.summary != s.label, "\(s.rawValue)'s summary says more than its label")
}
check(WalletSection.spending.id == "spending", "id is the raw value")

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

mutate "spending no longer last (prd §1529)" \
  's/\[\.home, \.holdings, \.activity, \.spending\]/[.home, .holdings, .spending, .activity]/'
mutate "spending dropped from the row, its case still compiling (prd §1468)" \
  's/\[\.home, \.holdings, \.activity, \.spending\]/[.home, .holdings, .activity]/'
mutate "home no longer leads" \
  's/\[\.home, \.holdings, \.activity/[.holdings, .home, .activity/'
mutate "resolve falls back to the first present scope instead of home" \
  's/guard let wanted, present\.contains\(wanted\) else \{ return \.home \}/guard let wanted, present.contains(wanted) else { return present.first ?? .home }/'
mutate "the retired Security tile comes back as a scope (prd §1480)" \
  's/    case spending\n/    case spending\n    case security\n/'
mutate "shows() lets a single scope draw a control" \
  's/present\.count > 1/present.count > 0/'
mutate "every tile gated again, so tiles vanish on the wallet that most needs them" \
  's/static func present\(\) -> \[WalletSection\] \{ order \}/static func present() -> [WalletSection] { order.filter { !\$0.isConditional } }/'
mutate "an empty page left with nothing to say — the dead control this ruling depends on avoiding" \
  's/An address made to look like yours, a fake token or a fake transfer\./ /'
mutate "a Holdings page goes back to Home instead of Holdings (prd §1480 item 9)" \
  's/if Self\.holdingsDoors\.contains\(self\) \{ return \.holdings \}/if Self.holdingsDoors.contains(self) { return .home }/'
mutate "a door dropped from Home's row, its page unreachable (prd §1480)" \
  's/\.permissions, \.threats\]/.permissions]/'
mutate "what you follow is named Accounts again, beside Holdings' Accounts (prd §1480)" \
  's/case \.following:       return String\(localized: "Following"\)/case .following:       return String(localized: "Accounts")/'
mutate "home loses its empty copy again, so the wallet room says nothing when nothing came back (prd §761)" \
  's/case \.home:            return String\(localized: "No balance yet"\)/case .home:            return nil/'
mutate "home's empty copy promises a load state it cannot know (§83)" \
  's/What these accounts are worth, and the line it traces\./The balance will appear once the read lands./'

# ── drift guards ─────────────────────────────────────────────────────────────
# The wiring the compiled enum cannot prove. Read from a COMMENT-STRIPPED copy:
# these files DOCUMENT the rules by naming what they must not do, so a guard
# grepping raw source scores prose as compliance (the Obsidian/Cursor lesson).
strip_comments() { perl -pe 's{//.*$}{}g' "$1"; }
HISTORY="Casberi/Casberi/Screens/WalletHistoryScreen.swift"
WALLETHOME="Casberi/Casberi/Screens/FeedScreen+WalletHome.swift"
SCROLL="Casberi/Casberi/Screens/FeedScreen+Scroll.swift"
WHOSE="Casberi/Casberi/Model/WalletWhose.swift"
WHOSESWITCH="Casberi/Casberi/Screens/WalletWhoseSwitch.swift"
for f in "$MAIN" "$FEED" "$CHROME" "$SWITCH" "$CHROMEVIEW" "$SCOPEHEAD" \
         "$SRC" "$CHASSIS" "$CHIPS" "$EMPTYFIG" "$HISTORY" "$WALLETHOME" "$SCROLL" \
         "$WHOSE" "$WHOSESWITCH"; do
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

# Markets is deleted (prd §1529): no door, tile or landing names it.
PAGES="Casberi/Casberi/Screens/FeedScreen+WalletPages.swift"
WROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
SHAPED="Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift"
for f in "$PAGES" "$WROOM" "$SHAPED"; do strip_comments "$f" > "$work/$(basename $f).bare"; done
deny MainSurface.swift "chrome.walletSection = .markets" \
  "a Markets door lands on a Markets tile again — Markets is deleted (prd §1529)"

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
# **THE OVERVIEW ROWS AND THE ACTIONS BLOCK ARE DELETED (prd §1039).** The
# rows said the tiles a second time; the verbs are the last tiles now. Home
# is box · tiles · menu · list, as in every room, and neither block returns.
deny DSRoomScopeChrome.swift "DSScopeRows(" \
  "the Overview rows are back — they repeat the tiles as rows (prd §1039)"
deny DSRoomScopeChrome.swift 'String(localized: "Actions")' \
  "the Actions block is back on Home — the verbs are the last tiles (prd §1039)"
deny DSRoomScopeChrome.swift 'String(localized: "Overview")' \
  "the Overview block is back on Home (prd §1039)"
# **NO VERB TILES (prd §1107, §1108).** The Wallet's Watch and the devnets'
# Create/Send/Top up left the tiles for the Accounts list and the rows; the
# chrome hands the grid its scopes and nothing else.
deny DSRoomScopeChrome.swift "verbs: Set(verbs)" \
  "the chrome hands the grid verb tiles again — the room's acts are the Accounts list's and the rows' (prd §1107, §1108)"
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
# Since prd §936 the phone picks the account from the menu under the tiles,
# so the rail mounts only where the iPad/Mac rail stands (`showsRail`).
# §959 moved the social, GitHub and Pinterest rails under the same `if
# showsRail {` block, so the mount is read inside `roomFaces`, not off one line.
# **THE ACCOUNT STRIP LEFT THE BAND (prd §1405).** On the rail layout the
# accounts are a menu on the room's title (`FeedScreen.accountTitleMenu`,
# read off the rail the chrome publishes); the band keeps the social faces
# only. A strip back in `roomFaces` is the floating band §1405 deleted.
awk '/private var roomFaces: some View/{on=1} on&&/^    }$/{exit} on' Casberi/Casberi/Shell/MainSurface.swift \
       | grep -qE '^ +accountRail$' \
  && fail "the account rail is back in the band's faces (prd §1405 moved it to the title's menu)"
grep -q "var accountTitleMenu: some View" Casberi/Casberi/Screens/FeedScreen+RoomTitle.swift \
  && grep -q "chrome.accountRail, rail.source == source, rail.slots.count > 1" Casberi/Casberi/Screens/FeedScreen+RoomTitle.swift \
  || fail "the title's account menu no longer reads the rail the chrome publishes (prd §1405)"
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
# The lead stands only where the box draws (prd §1403): beside a pane the
# column leaves it to the pane, so the line is gated — same place, one gate.
lead_at=$(print -r -- "$chrome_bare" | grep -nE "^            (lead|if boxPlace != \.listWithoutBox \{ lead \})$" | head -1 | cut -d: -f1 || true)
tiles_at=$(print -r -- "$chrome_bare" | grep -n "DSScopeTiles(" | head -1 | cut -d: -f1 || true)
[[ -n "$lead_at" && -n "$tiles_at" ]] && (( lead_at < tiles_at )) \
  || fail "drift: the chrome's lead box is not drawn before its tiles — controls at the top, or a moving bar (§752, §765)"
[[ "$chrome_bare" == *"figure(active)"* && "$chrome_bare" == *"height: DSRoomChassis.visualSlot"* ]] \
  || fail "drift: the chrome no longer draws the section figure in the fixed lead box — the tiles move between pages (§765)"
wallet_fn=$(sed -n '/func walletScopeChromeSection(/,/^    }$/p' "$work/FeedScreen.swift.bare")
[[ "$wallet_fn" == *"figure: { scope in"* && "$wallet_fn" == *"walletScopeVisualSection(scope"* ]] \
  || fail "drift: the wallet no longer hands its section figure to the chrome (§765)"
guard FeedScreen.swift "WalletSection.resolve(" \
  "the room reads chrome.walletSection raw instead of resolving it"
guard FeedScreen.swift "WalletSection.pages(tiles:" \
  "the room resolves against the tiles alone, so Subscriptions (no tile, §1232) draws Home under its title"

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
# **Box, then tiles** (prd §1039, after §750's head · Actions · Readings).
# Read in the chrome, where the order is the source order.
CHROME="Casberi/Casberi/Design/DSRoomScopeChrome.swift"
# Since §765 the crown is drawn by `lead`, the one box both arms share, so the
# head's place in the order is the `lead` call and `lead` must draw the crown.
grep -q "if let showing { crown(showing) }" "$CHROME" \
  || fail "drift: the chrome's lead box no longer draws the crown on Home (§765)"
# **WATCH IS THE ACCOUNTS LIST'S FIRST ROW, NOT A TILE (prd §1107).** The
# wallet hands the chrome an account act that raises the Watch tray (§1090),
# hands it no verbs, and the menu draws the act before every account (user:
# "it shouldn't go at the bottom b/c someone may have tons of things there").
[[ "$chrome_fn" == *"accountAction:"* && "$chrome_fn" == *"feedSheet = .walletFollow"* ]] \
  || fail "drift: Watch a wallet is not handed to the Accounts pill, or no longer raises the Watch tray (prd §1107, §1090)"
[[ "$chrome_fn" != *"verbs:"* ]] \
  || fail "drift: the wallet hands the chrome verb tiles again — Watch is the Accounts list's first row (prd §1107)"
# Since prd §1133 the pill is deleted and the act leads the room's run in
# the rooms tray (its folder until §1133b): drawn before every account, and the Wallet's raised from any
# room through `walletFollowPending`, which the Wallet room answers. The
# Wallet's row lost its + (prd §1423: no other row draws one); a typed
# address's "Follow this account" is the tray's way in now.
tray_bare=$(sed -e 's://.*$::' Casberi/Casberi/Shell/RoomsTray.swift)
act_at=$(print -r -- "$tray_bare" | grep -n "if let action = folder.action { cells.append(.action(action)) }" | head -1 | cut -d: -f1 || true)
rows_at=$(print -r -- "$tray_bare" | grep -n "cells += folder.items.map(RunCell.item)" | head -1 | cut -d: -f1 || true)
[[ -n "$act_at" && -n "$rows_at" ]] && (( act_at < rows_at )) \
  || fail "drift: the folder no longer leads with its act — Follow sinks under a long list (prd §1107, §1133)"
grep -q "chrome.walletFollowPending = true" Casberi/Casberi/Shell/RoomsTray.swift \
  && grep -q "chrome.walletFollowPending = false" Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift \
  || fail "drift: the tray's Follow this account no longer reaches the Wallet room (prd §1133, §1423)"
grep -q "rail.action.map" Casberi/Casberi/Shell/RoomsTray.swift \
  || fail "drift: the folder drops a standing room's act — New account is unreachable (prd §1107, §1133)"

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
deny DSRoomScopeChrome.swift "dsWidgetSurface" \
  "a block on the wallet family's Home is on a plate again — the head, the acts and the readings are all content on the page (§757/§758)"

# **THE CROWN'S EMPTY BRANCH SAYS WHAT IT WOULD HOLD (prd §761).**
# `walletTilesSection`'s gate is an honesty floor — nothing drawn rather than a
# card with nothing in it — and for as long as `DSRoomSlot` reserved 300pt, that
# rendered as a card of black; §757 dropped the floor and it renders as a room
# that opens on `Actions` with no explanation. Home is a scope like the other
# seven now: its words live in `WalletSection` and are drawn by the one figure.
guard FeedScreen.swift "WalletScopeEmptyFigure(section: .home, padded: false" \
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
guard FeedScreen.swift "case .holdings, .holdingAccounts, .positions, .apps, .nfts:" \
  "Holdings' pages no longer share Holdings' empty gate — a page and its tile could disagree (prd §1480)"
guard FeedScreen.swift "return blockStream.els.isEmpty" \
  "holdings' empty gate no longer reads the treemap's own doc — figure and empty state drift, and the slot shows both or neither"
# Permissions and Threats count off the checkup's own reads (prd §1480).
guard FeedScreen.swift "figureTone: counts.unlimited > 0 ? DS.attentionInk : DS.textPrimary" \
  "the Permissions door no longer reads the checkup's counts — its line and its page could disagree (prd §1480)"
guard FeedScreen.swift "figureTone: DS.destructiveInk" \
  "the Threats door no longer reads the checkup's counts (prd §1480)"
guard FeedScreen.swift "case _ where walletScopeIsEmpty(section):" \
  "the slot no longer draws a scope's empty state — a chip onto an empty scope opens 258 blank points (§611)"
guard FeedScreen.swift "WalletScopeEmptyFigure(section: section, reading: holdingsReads > 0)" \
  "the empty state stopped reading the scope's own words, or says \"Nothing held\" while a holdings read is still on its way"
guard FeedScreen.swift "defer { holdingsReads -= 1 }" \
  "a holdings read no longer ends its count on every path — the box would spin forever"
guard WalletScopeEmptyFigure.swift "if reading {" \
  "the reading form is gone — a cold read says \"Nothing held\" over money not yet read"

guard FeedScreen.swift "chrome.walletSections = " \
  "the room no longer publishes its present scopes"
guard FeedScreen.swift "chrome.walletSections = \[\]" \
  "the room no longer CLEARS its scopes — the toggle would draw over the next room"
guard FeedScreen.swift "walletLive.warnings" \
  "the dot no longer rides warnings — presence-lighting is the §83 overclaim that retired 'Needs attention'"
guard FeedScreen.swift "case .holdings:" \
  "the wallet block no longer switches on the scope"
# What is ahead is Needs you's since prd §1480: its page and Home's count read
# the same groups, so the door and the page cannot disagree.
guard FeedScreen.swift "walletComingUpDays(upcoming)" \
  "Needs you no longer lists what's ahead (prd §1041, §1480)"
# Spending's doors are groups' sums through Hide balances, never one purchase
# (prd §1246, §1480).
guard FeedScreen.swift "figure: mask ?? AppleWalletRoom.money(page.recurring, \"USD\")" \
  "Spending's Subscriptions door no longer leads with what recurs, through Hide balances (prd §1480)"
guard FeedScreen.swift "figure: mask ?? AppleWalletRoom.money(page.rest, \"USD\")" \
  "Spending's Places door no longer leads with the rest, through Hide balances (prd §1480)"
deny FeedScreen.swift "SpendingReading.shared.latest" \
  "a Spending door is one purchase again — the same row and figure as Activity's (prd §1246)"
# Home is the overview, no list (prd §1480): the stream is Activity's.
guard FeedScreen.swift "walletHomeDoors(upcoming: upcoming)" \
  "Home no longer draws its six doors (prd §1480)"
deny FeedScreen.swift "func walletHomeSections(" \
  "Home's lists are back — the stream is Activity's, the readings Spending's (prd §1480)"
guard FeedScreen.swift "walletStream(moves, cap: nil)" \
  "Activity's list is capped again — the page is the list (prd §1480 item 3)"
deny FeedScreen.swift "ahead: upcoming" \
  "what's ahead is back on Home — Home is only what happened (prd §1041)"
guard FeedScreen.swift "let all = visible.live.filter { !promoted.contains(\$0.id) }" \
  "Home's stream no longer drops the rows Coming up holds — a deadline would read as a move (prd §1041)"
guard WalletHistoryScreen.swift "RoomAccounts.roomSources(CategoryFold.walletRoom)" \
  "the history screen no longer reads every source Home counts — its door opens a shorter list than it promises (prd §837, §1048)"

# ── the card seats' rows, Subscriptions and NFTs under Holdings (prd §1048, §1105)
# The Wallet's query carries the card seats, and three places must agree on
# which rows those are: the query, the row filter and the safety-net probe. If
# the probe forgets them, every pass reads the card rows as rows the query
# invented and swaps in a Wallet-only fetch, and Home loses every card spend
# with nothing failing (measured on the simulator, 2026-10-01).
guard FeedScreen.swift "RoomAccounts.roomSources(source)" \
  "the Wallet's query or its probe no longer reads RoomAccounts.roomSources — Home loses the card spends (prd §1048)"
guard FeedScreen.swift "RoomAccounts.rides(room: source, source: thing.source)" \
  "the room filter drops the card seats' rows — Home loses the card spends (prd §1048)"
# Subscriptions reads its OWN fetch (the room's is bounded), runs it from a
# task, and since prd §1111 its tile holds subscriptions and nothing else: the
# renewals on its calendar, every plan in its list. What waits on you and the
# dated rows lead Home.
guard FeedScreen.swift ".task(id: walletSubscriptionsKey) {" \
  "Subscriptions no longer refreshes its reading — it stands on whatever was read first (prd §1105, §1111)"
guard FeedScreen.swift "subscriptions: subscriptions," \
  "the Subscriptions box lost the subscriptions — their renewals are off the calendar (prd §1111)"
python3 - "$work/FeedScreen.swift.bare" <<'PY' || fail "drift: Activity no longer reads the moves alone, or Subscriptions holds more than subscriptions (prd §1111, §1480)"
import re, sys
src = open(sys.argv[1]).read()
subs = re.search(r"case \.subscriptions:(.*?)case \.spending:", src, re.S)
# Activity is the stream since prd §1480 (`walletActivitySections`), which
# since prd §1341 reads the moves alone (`walletMoves`), never a balance.
act = re.search(r"func walletActivitySections\(.*?\n    }\n", src, re.S)
ok = subs and act \
    and "Self.walletMoves(all)" in act.group(0) and "walletStream(moves, cap: nil)" in act.group(0) \
    and "walletSubscriptionsSections" in subs.group(1) and "walletComingUp" not in subs.group(1)
sys.exit(0 if ok else 1)
PY
# A repeating bill lives on ONE tile: Coming up and Home leave it to Subscriptions.
guard FeedScreen.swift "!SubscriptionsSource.isBill(\$0, now: now)" \
  "Coming up lists a repeating bill again — the same charge on two tiles (prd §1105)"
guard FeedScreen.swift ".union(visible.filter { SubscriptionsSource.isBill(\$0) }" \
  "Home's stream lists a repeating bill again — it belongs to Subscriptions (prd §1105)"

python3 - "$work/FeedScreen+WalletPages.swift.bare" <<'PY' || fail "drift: Holdings' doors are not Apps, Tokens, Positions, then NFTs (prd §1503, §1536)"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"func walletHoldingsDoors\(.*?\n    }\n", src, re.S)
body = m.group(0) if m else ""
order = [body.find(k) for k in ("walletDoor(.apps", "feedSheet = .walletTokens",
                                "walletDoor(.positions", "walletDoor(.nfts")]
# Whose money it is says money, never a count (user: "i don't care that i
# have 90 apps. i care about the total of tokens in those apps").
if '.count)")' in body:
    sys.exit(1)
sys.exit(0 if all(i >= 0 for i in order) and order == sorted(order) else 1)
PY
# **NO WHOSE ROWS ON HOLDINGS (prd §1536, user: "i think yours following all
# switch is most sensible").** You and Following were rows that picked an
# account, the box's switch under other words; Apps stands on All only, the
# one word an app's money belongs to.
python3 - "$work/FeedScreen+WalletPages.swift.bare" <<'PY' || fail "drift: Holdings picks an account again — the switch is the one whose-control (prd §1536)"
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"func walletHoldingsDoors\(.*?\n    }\n", src, re.S)
body = m.group(0) if m else ""
bad = "walletDoor(.yourAccount" in body or "walletDoor(.holdingAccounts" in body \
    or "chrome.walletScope =" in body or "All tokens" in body
sys.exit(0 if not bad and "if walletOnAll, hasApps" in body else 1)
PY
# Tokens is a door on Holdings since prd §1480, opening every token in its
# sheet; Holdings itself never lists them, or Positions sink under forty rows.
deny FeedScreen.swift "ForEach(portfolio.positions)" \
  "Holdings lists every token again — on a wallet of forty, Positions are forty rows down (prd §1107)"

# The Foundation-only promise: this file must stay compilable without SwiftUI,
# or the harness above cannot run at all.
deny WalletSection.swift "import SwiftUI" "WalletSection imports SwiftUI — it must stay compilable without it, or this harness cannot run at all"

# The shared control must stay generic — a Wallet-shaped assumption inside it
# is the fork a second room asked us to avoid before either shipped.
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
guard FeedScreen.swift "DSRoomChassis.crownChart(chips: ranges.count > 1 || WalletWhoseSwitch.shows(chrome))" \
  "the wallet crown stopped paying for its foot row (range chips, Yours · Following · All, prd §1526, §1536) — the track clips at the slot's edge"
# (The activity chart's own guard went with the chart, prd §1039.)
# (The chart's `chartHeight(chips:)` budget, and the guard that its predicate
# stayed the chips' own gate, went with prd §942: a flexing drawing reserves
# nothing, so there is no second answer for the chips to disagree with.)
guard DSChip.swift "if ranges.count > 1" \
  "the chips' own draw gate moved — every budget above spells this predicate and would now be asking the wrong question"

# **ACCOUNTS LEADS OVERVIEW AND ADDS FROM ITS HEADER (prd §1410, user: "we
# need a way while in wallet to be able to add accounts there same way like in
# feed you can add stuff to follow").** The Wallet's one add door was the
# accounts menu's first row, in the tray behind the face on the phone. Now
# Overview's first row counts the accounts, the Accounts list stands under
# Overview, and its header's + is the Feed's with two rows — Follow an account
# (the tray) and Connect an app (the catalogue on its Wallet card) — the same
# two the Feed's Wallet section offered (§1347 grew; that section is deleted,
# §1489, and the menu is the Accounts header's alone). Since prd §1480 the list
# is Following, a door on Home: your own account apart (it is Your account's),
# every other account a row with its Rename and Stop following.
# Since prd §1536 Following is a word on the switch, not a door on Home: lit,
# Home leads with the wallets you follow; on All a Following row would be the
# switch's choice a second time.
guard FeedScreen.swift "if walletOnFollowing { walletFollowingPage }" \
  "Home under Following no longer lists the wallets you follow (prd §1536)"
deny FeedScreen.swift "walletDoor(.following, figure:" \
  "Home has a Following door again beside the switch's Following (prd §1536)"
# The switch: three words, Following lit for any wallet you follow, its lit
# word a way back (a second tap on Following leaves one wallet for all).
guard WalletWhose.swift "case yours, following, everything" \
  "the switch lost a word (prd §1536)"
guard WalletWhose.swift 'case .everything: return String(localized: "All")' \
  "the switch says Everything again; it is All (prd §1536)"
# No followed wallet, no switch (prd §1590): All alone, unlabelled.
guard WalletWhose.swift "guard hasFollowing else { return \[.everything\] }" \
  "the switch offers Yours · All with nothing followed again (prd §1590)"
guard WalletWhose.swift "guard hasFollowing else { return nil }" \
  "a launch with nothing followed opens on Yours again, leaving out cash and exchanges (prd §1590)"
guard FeedScreen+WalletRoom.swift "if none { WalletWhoseSwitch.settleUnfollowed(chrome) }" \
  "unfollowing the last wallet strands the Wallet on Yours with no switch (prd §1590)"
guard WalletWhoseSwitch.swift "repicks: true" \
  "a tap on the lit Following no longer leaves one followed wallet (prd §1536)"
guard FeedScreen.swift "scope: walletOnFollowing ? nil : chrome.walletScope" \
  "the box draws nothing under Following — no account slot is Following (prd §1536)"
# A door is a section's name with a figure (prd §1496): the glyph in the head
# column, the name at the section rung, the figure at its peer rung, one pitch,
# no line. Every page's doors come from this one row, so the rule is held here
# and nowhere else.
guard FeedScreen.swift ".frame(width: DSRoomChassis.headGlyph)" \
  "the door's glyph left the header's column (prd §1496)"
guard FeedScreen.swift ".dsText(.heading24)" \
  "a door's name is no longer the section rung (prd §1496)"
guard FeedScreen.swift ".dsText(.stat24)" \
  "a door's figure is no longer the section rung's peer (prd §1496)"
deny FeedScreen.swift "lineTone:" \
  "a door carries a line again (prd §1496: a door has no line; its state is the figure's ink)"
guard FeedScreen.swift "ForEach(slots) { slot in walletAccountRow(slot) }" \
  "the Following page no longer lists the accounts you follow (prd §1410, §1480)"
guard FeedScreen+WalletHome.swift "glyph: ScopeTileGlyph.wallets) { feedSheet = .walletFollow }" \
  "the Accounts header's + no longer raises Follow an account (prd §1410, §1090)"
guard FeedScreen+WalletHome.swift "route.present(.apps)" \
  "Connect an app no longer lands on the catalogue (prd §1410, §1234)"
guard FeedScreen+WalletHome.swift "WalletUnwatch.perform(entry, context: modelContext, chrome: chrome, bridges: bridges)" \
  "an account row's hold lost Stop following (prd §1302, §1410)"
# Following is wallets only, and what rode a wallet leaves with it (prd §1504,
# user: "i'm nto following any wallets so why would it show Safe").
guard FeedScreen+WalletPages.swift "!Self.isYourAccount(slot.id) && !RoomAccounts.isSeat(slot.id)" \
  "Following lists the apps the Wallet folded in again — a connected Safe reads as followed (prd §1504)"
WATCHING="Casberi/Casberi/Screens/WalletWatching.swift"
strip_comments "$WATCHING" > "$work/WalletWatching.swift.bare"
guard WalletWatching.swift "let dropped = dropRiders(of: gone, context: context, bridges: bridges)" \
  "an unfollow no longer drops what rode the wallet — Privy and Safe outlive it (prd §1504)"
guard WalletWatching.swift "SafeBridge.forgetUnfollowed(context: context)" \
  "an unfollow leaves the Safes it led to until the next launch again (prd §1504, §1330)"
guard FeedScreen+Scroll.swift "if category == Self.accountsName {" \
  "the Accounts header lost its + (prd §1410)"
guard FeedScreen+Scroll.swift "adds = walletAccountAdds" \
  "the Accounts header's + draws its own rows instead of the one menu (prd §1410)"

echo "  ok   drift guards: mount, gate, publication, clear, dot, scopes, generic control, crown chip budget, accounts (§1410)"
echo "✓ wallet sections: order, presence, resolve, shows, labels, 11 mutations, drift guards"
