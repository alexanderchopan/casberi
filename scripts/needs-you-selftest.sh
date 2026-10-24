#!/bin/zsh
# Casberi needs-you self-test — Needs you lives in its place, Day is dated
# rows, and the Feed has no Wallet section: the Wallet's asks light its tab
# (prd §1413, §1489; was day-needs-selftest.sh, prd §1327 item 9):
#
#   Casberi/Casberi/Model/WalletNeedsYou.swift  (compiled whole against stubs
#                                                of the names it reads)
#
# WHY A HARNESS. Every failure here renders as a calm list. A Wallet rule the
# Feed copied instead of shared drifts from the Wallet's own list, and the two
# places disagree about what needs you (§837); a Day section that gathers
# Needs you again conflates what waits on you with what is dated (§1413); a
# Work ask gathered into Day stands twice in one Feed, because Work's section
# draws its own (§1080). Only a case-by-case statement can say the Wallet's
# rule is right, and the drift guards say every reader still asks that one
# rule. Since prd §1344 it also holds Day's own page deleted: its tiles,
# Coming up, the page's Needs you card, and since §1413 the week strip and the
# gather, model included. Since §1489 it holds the Feed's Wallet section
# deleted (its Needs you and its moves) and the tab's dot reading the
# Wallet's one rule.
#
# Pure, local, deterministic. Exit non-zero on failure. `--self-test` (and
# every plain run) also proves each check can fail: plausible mutations of the
# rule must be CAUGHT.
set -euo pipefail
cd "$(dirname "$0")/.."

WALLET="Casberi/Casberi/Model/WalletNeedsYou.swift"
SOURCE="Casberi/Casberi/Model/WalletNeedsSource.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift"
WROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
WHOME="Casberi/Casberi/Screens/FeedScreen+WalletHome.swift"
WPAGES="Casberi/Casberi/Screens/FeedScreen+WalletPages.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
RAIL="Casberi/Casberi/Shell/PlaceRail.swift"
INFEED="Casberi/Casberi/Screens/FeedScreen+DayInFeed.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
MAKE="Casberi/Casberi/Model/DayMake.swift"
SECTIONS="Casberi/Casberi/Screens/FeedScreen+DaySections.swift"
SCROLL="Casberi/Casberi/Screens/FeedScreen+Scroll.swift"
SHAPED="Casberi/Casberi/Screens/FeedScreen+ShapedSections.swift"
GLYPHS="Casberi/Casberi/Screens/ScopeTileGlyphs.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
RSHELL="Casberi/Casberi/Shell/RootShell.swift"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
CAL="Casberi/Casberi/Screens/WalletCalendar.swift"
HOME_SCOPE="Casberi/Casberi/Model/HomeScope.swift"
for f in "$WALLET" "$SOURCE" "$ROOM" "$WROOM" "$WHOME" "$WPAGES" "$TABS" "$RAIL" "$INFEED" "$FEED" "$MAKE" \
         "$SECTIONS" "$SCROLL" "$SHAPED" "$GLYPHS" "$CHROME" "$RSHELL" "$SURFACE" "$CAL" "$HOME_SCOPE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- Day's page, its strip and its gather stay deleted (prd §1344, §1413) ----
# Day is the Feed's section (§1343); its page, its All · Coming up · New tiles,
# Coming up (and the DayDated entries only it drew), the page's calendar box,
# its Needs you card, the week strip that opened five weeks in place and the
# gather of every place's Needs you are gone, model included (CLAUDE.md: a
# feature deleted from the surface is deleted from the model). A file coming
# back, or a file that would wire it back naming it, fails here. Paths are
# literal so verify.sh's skip cache re-runs this the moment one exists again.
DELETED_FILES=(
  "Casberi/Casberi/Model/DayScope.swift"
  "Casberi/Casberi/Model/DayDated.swift"
  "Casberi/Casberi/Model/DayNeeds.swift"
  "Casberi/Casberi/Model/DayNeedsSource.swift"
  "Casberi/Casberi/Screens/FeedScreen+ComingUp.swift"
  "Casberi/Casberi/Screens/FeedScreen+DayDated.swift"
  "Casberi/Casberi/Screens/FeedScreen+DayNeeds.swift"
  "Casberi/Casberi/Screens/DayCalendarFigure.swift"
)
WATCHED=("$ROOM" "$INFEED" "$FEED" "$SECTIONS" "$SCROLL" "$SHAPED" "$GLYPHS" "$CHROME" "$RSHELL" "$SURFACE" "$MAKE" "$CAL")
GONE='DayScope|dayScope|dayComingUp|ComingUpWeek|DayDated|dayDatedRow|DayCalendarFigure|dayAheadRow|dayNeedsSection|DayMakeDialog|dayMakeOpen|dayHasApp|func pickDay[(]|DayNeeds|dayNeeds|dayNeedsRows|dayNeedsKey|loadDayNeeds|dayCalendarOpen|daySelected|pickFeedDay|dayPickedSection|dayCalendarMarks|dayFeedCalendarRow|dayFeedWeekEnd|shownWeeks|dotCell|onDay|Back to today'
day_page_gone() { # $1 a root holding the paths above; prints the breach and fails
  local root="$1" f
  for f in "${DELETED_FILES[@]}"; do
    [[ -e "$root/$f" ]] && { echo "✗ $f is back — Day has no page, no tiles, no Coming up, no strip and no gather (prd §1344, §1413)"; return 1; }
  done
  for f in "${WATCHED[@]}"; do
    if grep -v '^[[:space:]]*//' "$root/$f" | grep -Ewq "$GONE"; then
      echo "✗ $f names Day's deleted page, strip or gather again ($(grep -v '^[[:space:]]*//' "$root/$f" | grep -Ewo "$GONE" | head -1)) — prd §1344, §1413"
      return 1
    fi
  done
  return 0
}
day_page_gone . || exit 1

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove about themselves.
grep -q 'WalletNeedsYou.waiting(' "$WROOM" \
  || { echo "✗ the Wallet's Home no longer asks WalletNeedsYou — the Feed and the Wallet can disagree"; exit 1; }
grep -q 'WalletNeedsYou.waiting(' "$SOURCE" \
  || { echo "✗ the Wallet tab's dot no longer asks the Wallet's own rule (prd §1489)"; exit 1; }
grep -q 'let ids = await waiting(rows, safePending: safe, now: .now)' "$SOURCE" \
  || { echo "✗ WalletNeedsSource.count no longer counts through its own waiting (prd §1489)"; exit 1; }
grep -q '.task(id: feedSectionsKey)' "$FEED" \
  || { echo "✗ Day's and Notes' rows are no longer read in a task (prd §628)"; exit 1; }
# The tab's dot (prd §1489): read off the corpus in the shell's task, never a
# body (§628), and worn by the Wallet's tab on the phone's bar and the rail.
grep -q 'let asks = await WalletNeedsSource.count(context: modelContext)' "$SURFACE" \
  || { echo "✗ the shell no longer reads the Wallet's asks for its tab (prd §1489)"; exit 1; }
grep -B 3 'WalletNeedsSource.count(context: modelContext)' "$SURFACE" | grep -c '.task(id: corpusRevision)' >/dev/null \
  || { echo "✗ the Wallet's asks are read somewhere other than the corpus task (prd §628, §1489)"; exit 1; }
grep -q 'modifier(WalletAlarm(active: tab == .wallet))' "$TABS" \
  || { echo "✗ the phone's Wallet tab no longer wears the dot (prd §1489)"; exit 1; }
grep -q 'modifier(WalletAlarm(active: tab == .wallet))' "$RAIL" \
  || { echo "✗ the Mac rail's Wallet tile no longer wears the dot (prd §1489, §1402)"; exit 1; }
grep -q 'chrome.walletAsks > 0 || RecoveryKeyNudge.shown || OutsideKeyNudge.shown' "$TABS" \
  || { echo "✗ the Wallet's dot no longer lights for an ask and the key nudges (prd §1489)"; exit 1; }
# Day is dated rows (prd §1413): nothing in its section names Needs you, and
# its window is bounded by the cap alone.
grep -v '^[[:space:]]*//' "$INFEED" | grep -Eq 'needsYou|Needs you|needsYouGroup' \
  && { echo "✗ Day's section draws Needs you again — it lives in its place (prd §1413)"; exit 1; }
grep -q 'let window = dayFeedWindow(visible)' "$INFEED" \
  || { echo "✗ Day's window is bounded by something other than the cap again (prd §1413)"; exit 1; }
# --- the Feed's Wallet section stays deleted (prd §1489) ---------------------
# It repeated the top of the Wallet tab's Home: Needs you, then the moves. The
# Feed's categories leave the Wallet out, the file that drew its Needs you is
# gone, and nothing in the Feed's scroll names its reads again.
FEED_WALLET_GONE='walletNeeds|walletNeedsRows|loadWalletNeeds|walletNeedsFirstRows|walletMoves'
feed_wallet_gone() { # $1 a root holding the files below; prints the breach and fails
  local root="$1"
  [[ -e "$root/Casberi/Casberi/Screens/FeedScreen+WalletNeeds.swift" ]] \
    && { echo "✗ FeedScreen+WalletNeeds.swift is back — the Feed has no Wallet section (prd §1489)"; return 1; }
  grep -q '$0 != RoomAccounts.testnetsRoom && $0 != CategoryFold.walletRoom' "$root/$HOME_SCOPE" \
    || { echo "✗ the Feed's categories take the Wallet again (HomeScope.feedCategories, prd §1489)"; return 1; }
  local f
  for f in "$SCROLL" "$FEED"; do
    if grep -v '^[[:space:]]*//' "$root/$f" | grep -Ewq "$FEED_WALLET_GONE"; then
      echo "✗ $f reads the Feed's Wallet section again ($(grep -v '^[[:space:]]*//' "$root/$f" | grep -Ewo "$FEED_WALLET_GONE" | head -1)) — prd §1489"
      return 1
    fi
  done
  return 0
}
feed_wallet_gone . || exit 1
# Every door to Day lands on its section (prd §1344): on the phone a door
# naming Day is a Feed section, and Day's room on iPad and the Mac draws that
# one section, never a page of its own.
grep -q 'scrollSection(RoomAccounts.dayRoom, visible, nextEventID: nextEventID)' "$ROOM" \
  || { echo "✗ Day's room on iPad and the Mac no longer draws the Feed's Day section (prd §1344)"; exit 1; }
grep -q 'source != CategoryFold.walletRoom && source != RoomAccounts.testnetsRoom' "$HOME_SCOPE" \
  && ! grep -q 'source != RoomAccounts.dayRoom' "$HOME_SCOPE" \
  || { echo "✗ a door naming Day no longer lands on its Feed section (HomeScope.isFeedSection, prd §1343)"; exit 1; }
# Day's + (prd §1343): Track a subscription, in the verb's own word, raising
# the Wallet's own tray (moved here from day-dated-selftest.sh, §1344).
grep -q 'case .subscription: return SubscriptionWords.track' "$MAKE" \
  || { echo "✗ Day's + lost Track a subscription, or its verb is not SubscriptionWords.track"; exit 1; }
grep -q 'feedSheet = .subscriptionAdd' "$ROOM" \
  || { echo "✗ Day's Track a subscription no longer raises the Wallet's own tray"; exit 1; }
# Each place keeps its own Needs you (prd §1329, §1413).
grep -q 'WorkAsk.needsYou(' "$ROOM" \
  || { echo "✗ Work's own section lost its Needs you — each place keeps its own"; exit 1; }
grep -q 'walletDaySections(\[(Self.needsYouGroup' "$WPAGES" \
  || { echo "✗ the Wallet's Home lost its Needs you — each place keeps its own"; exit 1; }
# A dot, never a count (prd §1489): Home's Needs you counts what the tab
# does not read, and two numbers for one list disagree (§837).
grep -v '^[[:space:]]*//' "$TABS" | grep -Eqi 'badge|walletAsks\)' \
  && { echo "✗ the tab bar wears a count — the Wallet's tab wears a dot (prd §1489, §1327 item 9)"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Stubs of the names WalletNeedsYou reads, at their shipped spellings.
cat > "$TMP/stubs.swift" <<'SWIFT'
import Foundation
enum SafeBridge { static let sourceName = "Safe" }
enum PrivacyPoolsBridge { static let sourceName = "Privacy Pools" }
enum AppleWalletBridge { static let sourceName = "Apple Wallet" }
struct PrivacyPoolsRoom {
    static let depositPrefix = "privacypools:dep:"
    enum State: String { case pending = "Pending", needsProof = "Needs proof", approved = "Approved"
        var resolved: Bool { self != .pending && self != .needsProof } }
    static func state(tags: [String]) -> State? { tags.lazy.compactMap(State.init(rawValue:)).first }
}
enum WiseShape {
    static let source = "Wise"
    static func isStuck(tags: [String]) -> Bool { tags.contains("Needs attention") }
}
enum AztecStakeWire {
    // The shipped rule is AztecStakeWire.upgradeWaiting (aztec-stake-selftest.sh
    // tests it); this stub only says whether the hook routes to it.
    static func upgradeWaiting(ref: String, now: Date) -> Bool { ref.hasSuffix(":future") }
}
enum ZFiOrders {
    struct Book: Equatable { var waiting: Set<String> = []; var complete = true }
    static let reclaimPrefix = "zfi:reclaim:"
    static func stillWaiting(ref: String, in book: Book) -> Bool {
        guard ref.hasPrefix(reclaimPrefix) else { return false }
        return book.waiting.contains(ref) || !book.complete
    }
}
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("✗ \(what)") }
}
let now = Date(timeIntervalSince1970: 2_000_000_000)
func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3_600) }

// ── The Wallet's one rule ────────────────────────────────────────────
func waits(_ source: String, ref: String?, tags: [String] = [], at: Date = ago(1),
           safe: Set<String> = [], zfi: ZFiOrders.Book = .init()) -> Bool {
    WalletNeedsYou.waiting(source: source, ref: ref, tags: tags, capturedAt: at,
                           safePending: safe, zfi: zfi, now: now)
}
check(waits("Safe", ref: "safe:tx:1", tags: ["Your turn"], safe: ["safe:tx:1"]), "a Safe transaction waiting on your signature needs you")
check(!waits("Safe", ref: "safe:tx:1", safe: ["safe:tx:1"]), "one collecting others' signatures does not (prd §1340)")
check(!waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Pending"]), "a deposit under review waits on the screener, not you (prd §1340)")
check(!waits("Safe", ref: "safe:tx:2", safe: ["safe:tx:1"]), "an executed one does not, whatever its tags")
check(waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Needs proof"]), "a deposit waiting on proof needs you")
check(!waits("Privacy Pools", ref: "privacypools:dep:1", tags: ["Approved"]), "a cleared deposit does not")
check(!waits("Privacy Pools", ref: "privacypools:dep:1"), "an untagged deposit is not called waiting")
check(waits("Wise", ref: "wise:transfer:1", tags: ["Needs attention"]), "a stuck Wise transfer needs you")
check(!waits("Wise", ref: "wise:transfer:2"), "a Wise transfer that moved does not")
check(waits("Wallet", ref: "zfi:reclaim:b:1", zfi: .init(waiting: ["zfi:reclaim:b:1"])), "a zFi escrow still on the board needs you")
check(!waits("Wallet", ref: "zfi:reclaim:b:1"), "one the book no longer lists does not")
check(waits("Apple Wallet", ref: "aw:1", tags: ["Price rise"], at: ago(24 * 29)), "a price rise stands a month")
check(!waits("Apple Wallet", ref: "aw:1", tags: ["Price rise"], at: ago(24 * 31)), "and goes after it")
check(!waits("Apple Wallet", ref: "aw:2", tags: ["Spend"]), "an ordinary charge does not")
check(!waits("Safe", ref: nil, safe: ["x"]), "a row with no ref never waits")
check(waits("Wallet", ref: "aztec:upgrade:0xe37a:future"), "an Aztec upgrade still to come needs you (prd §1446)")
check(!waits("Wallet", ref: "aztec:upgrade:0xe37a:past"), "one that can already execute does not")
check(WalletNeedsYou.readsBook(ref: "zfi:reclaim:b:1") && !WalletNeedsYou.readsBook(ref: "wise:transfer:1"),
      "the zFi book is read for reclaim rows only")

if failures > 0 { print("✗ needs you: \(failures) failing"); exit(1) }
print("✓ needs you self-test passed")
SWIFT

build() { # $1 WalletNeedsYou.swift, $2 binary
  swiftc -Onone -o "$2" "$1" "$TMP/stubs.swift" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
}

build "$WALLET" "$TMP/run"
[[ -x "$TMP/run" ]] || { echo "✗ needs-you harness did not compile — WalletNeedsYou no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" file="$2" expr="$3"
  python3 - "$file" "$TMP/mutated.swift" "$expr" <<'PY' || { echo "  ✗ STALE MUTATION: the applier exited non-zero (anchor not found — nothing was tested)"; exit 1; }
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  rm -f "$TMP/mrun"
  build "$TMP/mutated.swift" "$TMP/mrun" >/dev/null
  if [[ -x "$TMP/mrun" ]] && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "needs-you-selftest: mutation pass…"
mfail=0
mutate "a price rise stands forever" "$WALLET" \
  'return now.timeIntervalSince(capturedAt) < priceRiseWindow|||return true' || mfail=1
mutate "an executed Safe transaction still waits" "$WALLET" \
  'return safePending.contains(ref) && |||return true || ' || mfail=1
mutate "every Wise transfer waits" "$WALLET" \
  'return WiseShape.isStuck(tags: tags)|||return true' || mfail=1
mutate "a deposit under review is called waiting" "$WALLET" \
  'PrivacyPoolsRoom.state(tags: tags) == .needsProof|||PrivacyPoolsRoom.state(tags: tags).map { !$0.resolved } ?? false' || mfail=1
mutate "an Aztec upgrade never waits" "$WALLET" \
  'if ref.hasPrefix("aztec:upgrade:") { return AztecStakeWire.upgradeWaiting(ref: ref, now: now) }|||' || mfail=1
mutate "a Safe transaction waiting on others still waits on you" "$WALLET" \
  'safePending.contains(ref) && tags.contains("Your turn")|||safePending.contains(ref)' || mfail=1

# The stays-deleted guard (prd §1344, §1413), over a copy of the watched
# files: a deleted file brought back, and a watched file naming the page, the
# strip or the gather again, must each be caught; the untouched copy must
# pass, or the catches prove nothing.
guard_root() { # a fresh copy of every watched file under $TMP/root
  rm -rf "$TMP/root"
  local f
  for f in "${WATCHED[@]}"; do mkdir -p "$TMP/root/$(dirname "$f")"; cp "$f" "$TMP/root/$f"; done
}
guard_mutate() { # $1 label, then a command run inside the copy
  local label="$1"; shift
  guard_root
  ( cd "$TMP/root" && eval "$*" )
  if day_page_gone "$TMP/root" >/dev/null; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}
guard_root
day_page_gone "$TMP/root" >/dev/null \
  || { echo "  ✗ the stays-deleted guard fails an untouched copy — it would catch anything"; mfail=1; }
guard_mutate "Coming up's file comes back" \
  'mkdir -p Casberi/Casberi/Screens && echo "extension FeedScreen {}" > Casberi/Casberi/Screens/FeedScreen+ComingUp.swift' || mfail=1
guard_mutate "DayScope comes back" \
  'echo "enum DayScope { case all, comingUp, new }" >> Casberi/Casberi/Model/DayMake.swift' || mfail=1
guard_mutate "the gather comes back" \
  'mkdir -p Casberi/Casberi/Model && echo "enum DayNeeds {}" > Casberi/Casberi/Model/DayNeeds.swift' || mfail=1
guard_mutate "the chrome holds Day's tile again" \
  'echo "    var dayScope = 0" >> Casberi/Casberi/Shell/ShellChrome.swift' || mfail=1
guard_mutate "Day's section gathers Needs you again" \
  'echo "    func dayNeedsRows(nextEventID: UUID?) {}" >> Casberi/Casberi/Screens/FeedScreen+DayInFeed.swift' || mfail=1
guard_mutate "the strip's picked day comes back" \
  'echo "    @State var daySelected: Date? = nil" >> Casberi/Casberi/Screens/FeedScreen.swift' || mfail=1
guard_mutate "the calendar takes a tap again" \
  'echo "    var onDay: ((Date) -> Void)? = nil" >> Casberi/Casberi/Screens/WalletCalendar.swift' || mfail=1

# The Feed's Wallet section stays deleted (prd §1489), over its own copy.
wallet_root() {
  rm -rf "$TMP/wroot"
  local f
  for f in "$HOME_SCOPE" "$SCROLL" "$FEED"; do mkdir -p "$TMP/wroot/$(dirname "$f")"; cp "$f" "$TMP/wroot/$f"; done
}
wallet_mutate() { # $1 label, then a command run inside the copy
  local label="$1"; shift
  wallet_root
  ( cd "$TMP/wroot" && eval "$*" )
  if feed_wallet_gone "$TMP/wroot" >/dev/null; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}
wallet_root
feed_wallet_gone "$TMP/wroot" >/dev/null \
  || { echo "  ✗ the Feed-Wallet guard fails an untouched copy — it would catch anything"; mfail=1; }
wallet_mutate "the Wallet section's file comes back" \
  'echo "extension FeedScreen {}" > Casberi/Casberi/Screens/FeedScreen+WalletNeeds.swift' || mfail=1
wallet_mutate "the Feed's categories take the Wallet again" \
  'sed -i.bak "s/CategoryFold.walletRoom\$/CategoryFold.dayRoom/" Casberi/Casberi/Model/HomeScope.swift' || mfail=1
wallet_mutate "the Feed reads the Wallet's asks again" \
  'echo "    @State var walletNeeds: [Thing] = []" >> Casberi/Casberi/Screens/FeedScreen.swift' || mfail=1
wallet_mutate "the scroll lists the Wallet's moves again" \
  'echo "    let m = Self.walletMoves([])" >> Casberi/Casberi/Screens/FeedScreen+Scroll.swift' || mfail=1

[[ $mfail -eq 0 ]] || { echo "needs-you-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "needs-you-selftest: OK — the Wallet's one rule, its tab's dot reading it, the Feed's Wallet section deleted, Work's own, and Day's deleted page, strip and gather all pinned."
