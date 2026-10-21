#!/bin/zsh
# Casberi needs-you self-test — Needs you lives in its place, and Day is dated
# rows (prd §1413; was day-needs-selftest.sh, prd §1327 item 9):
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
# gather, model included.
#
# Pure, local, deterministic. Exit non-zero on failure. `--self-test` (and
# every plain run) also proves each check can fail: plausible mutations of the
# rule must be CAUGHT.
set -euo pipefail
cd "$(dirname "$0")/.."

WALLET="Casberi/Casberi/Model/WalletNeedsYou.swift"
SOURCE="Casberi/Casberi/Model/WalletNeedsSource.swift"
SCREEN="Casberi/Casberi/Screens/FeedScreen+WalletNeeds.swift"
ROOM="Casberi/Casberi/Screens/FeedScreen+MergedRoom.swift"
WROOM="Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift"
WHOME="Casberi/Casberi/Screens/FeedScreen+WalletHome.swift"
TABS="Casberi/Casberi/Design/PlaceTabBar.swift"
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
for f in "$WALLET" "$SOURCE" "$SCREEN" "$ROOM" "$WROOM" "$WHOME" "$TABS" "$INFEED" "$FEED" "$MAKE" \
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
WATCHED=("$ROOM" "$SCREEN" "$INFEED" "$FEED" "$SECTIONS" "$SCROLL" "$SHAPED" "$GLYPHS" "$CHROME" "$RSHELL" "$SURFACE" "$MAKE" "$CAL")
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
  || { echo "✗ the Feed's Wallet section no longer asks the Wallet's own rule (prd §1413)"; exit 1; }
grep -q 'WalletNeedsSource.waiting(' "$SCREEN" \
  || { echo "✗ the Feed no longer reads the Wallet's Needs you through WalletNeedsSource (prd §1413)"; exit 1; }
grep -q 'walletNeedsRows(nextEventID: nextEventID, limit: needsLimit)' "$SCROLL" \
  || { echo "✗ the Feed's Wallet section no longer leads with Needs you (prd §1413)"; exit 1; }
grep -q 'static let walletNeedsFirstRows = 3' "$SCREEN" \
  || { echo "✗ the Wallet's Needs you no longer takes three on the first page (prd §1413)"; exit 1; }
grep -q '.task(id: feedSectionsKey)' "$FEED" \
  || { echo "✗ the Wallet's Needs you is no longer read in a task (prd §628)"; exit 1; }
grep -q 'Set(walletNeeds.live.map(\\.id))' "$SCROLL" \
  || { echo "✗ the Wallet's moves no longer skip what its Needs you leads with (prd §1343 item 7)"; exit 1; }
# Day is dated rows (prd §1413): nothing in its section names Needs you, and
# its window is bounded by the cap alone.
grep -v '^[[:space:]]*//' "$INFEED" | grep -Eq 'needsYou|Needs you|needsYouGroup' \
  && { echo "✗ Day's section draws Needs you again — it lives in its place (prd §1413)"; exit 1; }
grep -q 'let window = dayFeedWindow(visible)' "$INFEED" \
  || { echo "✗ Day's window is bounded by something other than the cap again (prd §1413)"; exit 1; }
# One shape per section (prd §1413 item 7): the Wallet's asks take the row
# the moves under them take, never the grouped one.
grep -v '^[[:space:]]*//' "$SCREEN" | grep -q 'grouped: true' \
  && { echo "✗ the Wallet's Needs you rows took the grouped shape beside plain moves (prd §1413 item 7)"; exit 1; }
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
grep -q 'walletDaySections(\[(Self.needsYouGroup' "$WHOME" \
  || { echo "✗ the Wallet's Home lost its Needs you — each place keeps its own"; exit 1; }
grep -qi 'badge' "$TABS" \
  && { echo "✗ the tab bar wears a badge — the Day tab does not (user, prd §1327 item 9)"; exit 1; }

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

[[ $mfail -eq 0 ]] || { echo "needs-you-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "needs-you-selftest: OK — the Wallet's one rule, the Feed's Wallet section leading with it, Work's own, and Day's deleted page, strip and gather all pinned."
