#!/bin/zsh
# Casberi address-book self-test — the SHIPPED judgement behind the wallet
# manager's list (prd §440, 2026-08-22):
#
#   Casberi/Casberi/Model/AddressBookShape.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
#
# WHY A HARNESS. Every failure mode here renders as a perfectly ordinary list:
#
#   · a letter heading over rows that don't start with it, which is invisible
#     until you look for the one row that isn't there
#   · a scrubber offering a letter that scrolls nowhere — §83's dead control,
#     twenty-six times
#   · `…44b1` filed under `4` (or under `…`), giving the index a dozen headings
#     nobody can aim at, on a book where every un-named wallet is one
#   · a `#` bucket sorted BEFORE A while its heading is printed last
#   · a non-total order, so two addresses pasted in the same bulk import swap
#     places between body passes and the list reads as glitching (the lesson
#     `agent-panel-selftest` paid for with its tile sort, and `AddressSky` paid
#     for again with its bearings)
#   · a diacritic filed past Z by a comparison that folds it and a heading that
#     doesn't
#   · a search that finds a group's ROWS but not the group, or offers a group
#     whose rows the list beneath it is hiding — two spellings of one rule
#   · "241 days ago" where the month was the fact, or a month from two years
#     ago printed as though it were this spring
#
# Nothing in a build, a screen sweep or any static audit can see one of these.
#
# It replaces `address-sky-selftest.sh`, deleted with the sky the same day
# (§440): four device drawings proved a force-free graph layout answers a
# different geometric question for every corpus shape, and the reading moved to
# `AddressSpineCard`, whose own arithmetic is `AddressConnections`' and is
# covered by `wallet-viz-selftest.sh`.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/AddressBookShape.swift"
BOOK="Casberi/Casberi/Model/AddressBook.swift"
ACTIVITY="Casberi/Casberi/Model/AddressActivity.swift"
SCREEN="Casberi/Casberi/Screens/WalletScreen.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
GROUPS="Casberi/Casberi/Screens/AddressGroupViews.swift"
SPINE="Casberi/Casberi/Screens/AddressSpineCard.swift"
BAR="Casberi/Casberi/Screens/AddressIndexBar.swift"
FLIGHT="Casberi/Casberi/Screens/AddressFlight.swift"
SOURCE="Casberi/Casberi/Model/AddressConnectionsSource.swift"
for f in "$SHAPE" "$BOOK" "$ACTIVITY" "$SCREEN" "$VIEWS" "$GROUPS" "$SPINE" "$BAR" "$FLIGHT" "$SOURCE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A comment-stripped copy for the NEGATIVE guards. These files DOCUMENT what
# they must never do — `AddressSpineCard` explains at length that it reads no
# money, `WalletScreen` names the sky it retired — so a guard grepping raw
# source fires against the prose explaining it (the Obsidian/Cursor lesson,
# earned on several harnesses' own first runs).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*///?.*$', '', src, flags=re.M)
src = re.sub(r'//.*$', '', src, flags=re.M)
sys.stdout.write(src)
PY
}
strip_comments "$SPINE"  > "$TMP/spine-bare.swift"
strip_comments "$SCREEN" > "$TMP/screen-bare.swift"
strip_comments "$GROUPS" > "$TMP/groups-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect `sections` is
# worthless if the list draws its own order, if the scrubber invents its own
# letters, or if the search field and the book disagree about what a group is.

grep -q 'AddressBookShape.sections(shapeRows(entries), order: bookSort)' "$SCREEN" \
  || grep -q 'AddressBookShape.sections(rows, order: bookSort)' "$SCREEN" \
  || { echo "✗ the manager no longer takes its sections from AddressBookShape — the order would be the screen's own and nothing could test it"; exit 1; }
grep -q 'AddressBookShape.index(of: sections)' "$SCREEN" \
  || { echo "✗ the scrubber no longer derives its letters from the rendered sections — it would offer letters that scroll nowhere (§83)"; exit 1; }
grep -q 'AddressBookShape.groupMatches($0, query: q)' "$BOOK" \
  || { echo "✗ AddressBook.search no longer uses the shared group rule — the field's group RESULTS and its row filter would be two spellings of one test"; exit 1; }
grep -q 'AddressBookShape.matchingGroups(groupNames, query: query)' "$BOOK" \
  || { echo "✗ the book no longer offers matching groups; typing a group name would list its members and never open it (§267)"; exit 1; }
grep -q 'AddressBookShape.lastPhrase(activity.lastAt)' "$VIEWS" \
  || { echo "✗ the row subline no longer states WHEN you last dealt — the count alone cannot separate a correspondent from a stranger"; exit 1; }
grep -q 'static func summaries(in context: ModelContext)' "$ACTIVITY" \
  || { echo "✗ AddressActivity no longer reports a last-dealt date"; exit 1; }

# THE SORT DEFAULT (§440). A-Z is the whole reason the sectioning and the
# scrubber exist; flip it back to `.recent` and both are dead code on first
# open.
grep -q 'private var bookSort: AddressBookShape.Order = .name' "$SCREEN" \
  || { echo "✗ the book no longer opens A–Z — the letter headings and the scrubber would only appear if somebody changed the sort"; exit 1; }

# THE SEARCH FOLD. Everything above the book collapses while you type, or the
# field is a search box with two screens of chrome above its results. Anchored
# to the two branches that actually fold — the top half and the foot — rather
# than to the flag's declaration, which would pass against a `searching` that
# nothing reads.
grep -q 'if !searching {' "$TMP/screen-bare.swift" \
  || { echo "✗ the manager no longer folds its top sections while searching"; exit 1; }
grep -q 'if !searching { footSection }' "$TMP/screen-bare.swift" \
  || { echo "✗ the foot no longer folds while searching — the Connection door and the read-only promise would sit under a list of search results"; exit 1; }

# ONE SEARCH PER BODY PASS (prd §441). `book.search` was reached four times a
# pass; the fix is a single `let` threaded down. A section builder that goes
# back to the store for its own copy silently restores the cost.
grep -q 'let entries = visibleEntries' "$TMP/screen-bare.swift" \
  || { echo "✗ the body no longer hoists the filtered book — the search would run once per reader again (§441)"; exit 1; }
grep -q 'private func bookSection(entries: \[AddressBook.Entry\]' "$SCREEN" \
  || { echo "✗ the book list no longer takes its entries as a parameter"; exit 1; }

# ONE CORPUS WALK, TWO READINGS (prd §441).
grep -q 'let things = AddressActivity.relevant(in: modelContext)' "$SCREEN" \
  || { echo "✗ the manager fetches the corpus twice again — the activity summary and the connections map both walked their own fetch (§441)"; exit 1; }
grep -q 'static func map(things: \[Thing\]) -> Map?' "$SOURCE" \
  || { echo "✗ AddressConnections can no longer be built from an already-fetched array"; exit 1; }
# The re-sort inside `edges(from:)` is load-bearing: AddressActivity hands back
# NEWEST first and node order is FIRST-DEALT (§295), so trusting the caller's
# order silently reverses the spine — a card that renders perfectly and lists
# the newest relationship as the oldest.
grep -q 'things.sorted(by: { $0.capturedAt < $1.capturedAt })' "$SOURCE" \
  || { echo "✗ edges(from:) trusts the caller's order — the spine would be reversed, and it would look completely normal"; exit 1; }

# THE FIVE MOMENTS (prd §441). Each is a real state change, per §79.
grep -q 'launchFlight(entry)' "$SCREEN" \
  || { echo "✗ starring an address no longer sends its face to the shelf (§212's own claimed moment)"; exit 1; }
grep -q 'flightAnchor("slot:" + AddressBook.key(for: addr.address))' "$SCREEN" \
  || { echo "✗ the shelf slot no longer publishes a landing anchor, or stopped keying it the BOOK's way — a watch stored as 'vitalik.eth' would never find its own row"; exit 1; }
grep -q 'DS.Face.list + (DS.Face.shelf - DS.Face.list) \* progress' "$FLIGHT" \
  || { echo "✗ the flight sizes itself off the anchor rects again — those are layout frames and stop matching the face the moment a mark gains a border"; exit 1; }
grep -q 'absorbing == key' "$SCREEN" \
  || { echo "✗ a dropped face is no longer absorbed by the deck"; exit 1; }
grep -q 'litNode' "$SPINE" \
  || { echo "✗ tapping a spine node no longer lights its ribbons before the sheet covers them"; exit 1; }
grep -q 'newNodeIDs.contains($0.id)' "$SPINE" \
  || { echo "✗ a newly-seen connection no longer draws dashed"; exit 1; }
grep -q 'AddressConnectionsSeen.markSeen' "$SCREEN" \
  || { echo "✗ nothing marks a drawn connection as seen — every connection would read as new forever"; exit 1; }
grep -q 'defaults.set(true, forKey: seededKey)' "$SOURCE" \
  || { echo "✗ the seen-set no longer seeds silently on first sight — a year of history would announce itself as today's news (the Hyperliquid 2026-07-30 bug)"; exit 1; }

# ONE ROW ANATOMY. Two spellings of the book row is two books.
grep -q 'struct AddressBookRow: View' "$VIEWS" \
  || { echo "✗ the shared row is gone; the manager and the group screen would each draw their own"; exit 1; }
grep -q 'AddressBookRow(entry: entry' "$SCREEN" \
  || { echo "✗ the manager no longer draws the shared row"; exit 1; }
grep -q 'AddressBookRow(entry: entry' "$GROUPS" \
  || { echo "✗ the group screen no longer draws the shared row"; exit 1; }

# THE THREE MOVE DOORS (§440). Each is named, because two of them exist
# precisely so the feature survives the third misbehaving on a device.
grep -q '.draggable(entry.address)' "$SCREEN" \
  || { echo "✗ a book row is no longer draggable — dragging onto a group card is the primary filing gesture"; exit 1; }
grep -q 'dropDestination(for: String.self)' "$SCREEN" \
  || { echo "✗ a group card is no longer a drop target"; exit 1; }
grep -q 'bookSheet = .move(entry)' "$SCREEN" \
  || { echo "✗ swipe no longer opens the filing sheet"; exit 1; }
grep -q 'struct AddressMoveSheet: View' "$GROUPS" \
  || { echo "✗ the filing sheet is gone"; exit 1; }
# The swipe must stay a DOOR and never a write — the design law's own "swipe
# verbs are reads; a write belongs behind a deliberate press" (§212). It opens
# a sheet, and the sheet takes the consent.
grep -q 'swipeActions(edge: .trailing, allowsFullSwipe: false)' "$SCREEN" \
  || { echo "✗ the book's swipe gained a full swipe — a full swipe commits without a second beat, which for a write is exactly what §212 forbids"; exit 1; }

# NEGATIVE, on comment-stripped copies: §435's money ruling. The manager is a
# PEOPLE screen and the feed's crown owns the money reading, once.
for f in "$TMP/spine-bare.swift" "$TMP/screen-bare.swift" "$TMP/groups-bare.swift"; do
  grep -q 'WalletValue.money' "$f" \
    && { echo "✗ a money figure returned to the address book — §435 struck every one of them off this screen"; exit 1; }
done
# …including the one the model still carries for other callers.
grep -q 'column.usd' "$TMP/spine-bare.swift" \
  && { echo "✗ the spine reads Column.usd — the model keeps it for other callers, and this screen may not draw it"; exit 1; }

# NEGATIVE: the sky is gone and must not come back by reference.
grep -q 'AddressSky' "$TMP/screen-bare.swift" \
  && { echo "✗ WalletScreen references AddressSky, which was deleted with §440"; exit 1; }
[[ -f "Casberi/Casberi/Model/AddressSky.swift" ]] \
  && { echo "✗ AddressSky.swift is back; §440 replaced it with the spine"; exit 1; }

# §439's reading survived the retirement — it is the one relationship the
# person asked for by name, and it lives in the model, the bracket and a
# sentence.
grep -q 'walletLinks' "$SPINE" \
  || { echo "✗ the spine no longer draws the direct wallet-to-wallet links (§439)"; exit 1; }
grep -q 'walletLinkNote' "$TMP/spine-bare.swift" \
  || { echo "✗ §439 lost its sentence — the bracket alone can be looked at without being understood at two watched wallets"; exit 1; }

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

typealias Row = AddressBookShape.Row
typealias Order = AddressBookShape.Order

let epoch = Date(timeIntervalSince1970: 1_700_000_000)
func row(_ name: String, _ id: String? = nil, added: Double = 0,
         watched: Bool = false, activity: Int = 0) -> Row {
    Row(id: id ?? name.lowercased(), name: name,
        addedAt: epoch.addingTimeInterval(added),
        watched: watched, activity: activity)
}

print("Section letters")
check("a plain name takes its initial", AddressBookShape.sectionLetter(for: "Mom") == "M")
check("case folds", AddressBookShape.sectionLetter(for: "alice") == "A")
// The `#` bucket is the one this book needs more than a contacts app does:
// `WalletStore.add` files a bare address under its own short form, so an
// unnamed wallet is literally called `…44b1`.
check("a short-form address files under #", AddressBookShape.sectionLetter(for: "…44b1") == "#")
check("a raw hex name files under #", AddressBookShape.sectionLetter(for: "0x9a2E") == "#")
check("a digit files under #", AddressBookShape.sectionLetter(for: "1inch") == "#")
check("an empty name files under #", AddressBookShape.sectionLetter(for: "   ") == "#")
// Diacritics fold, because `localizedStandardCompare` folds them when it
// ORDERS — a heading that doesn't agree files Ångström past Z.
check("a diacritic folds to its base letter", AddressBookShape.sectionLetter(for: "Ångström") == "A")
// Not an A–Z range: this app ships in five languages, and penning あ into `#`
// would put a Japanese book entirely under one heading.
check("a non-Latin letter is its own heading", AddressBookShape.sectionLetter(for: "Яндекс") == "Я")

print("")
print("A–Z sectioning")
let book = [row("Mom"), row("alice"), row("…44b1"), row("Bankless"), row("Audit"), row("Zoe")]
let az = AddressBookShape.sections(book, order: .name)
check("one section per distinct letter", az.map(\.letter) == ["A", "B", "M", "Z", "#"])
check("rows land under their own heading",
      az.allSatisfy { section in
          guard let letter = section.letter else { return false }
          return section.ids.allSatisfy { id in
              guard let r = book.first(where: { $0.id == id }) else { return false }
              return AddressBookShape.sectionLetter(for: r.name) == letter
          }
      })
check("every row is drawn exactly once",
      az.flatMap(\.ids).sorted() == book.map(\.id).sorted())
// THE ONE ARRANGEMENT THAT IS VISIBLY WRONG: `#` sorts last because its
// heading is printed last.
check("# sorts after the letters", az.last?.letter == "#")
check("the scrubber's letters ARE the headings",
      AddressBookShape.index(of: az) == ["A", "B", "M", "Z", "#"])
check("the scrubber never invents a letter the list hasn't got",
      !AddressBookShape.index(of: az).contains("Q"))

print("")
print("The unlettered orders do not section")
for order in [Order.recent, Order.activity] {
    let s = AddressBookShape.sections(book, order: order)
    check("\(order.rawValue) is one headerless block", s.count == 1 && s[0].letter == nil)
    check("\(order.rawValue) draws every row", s[0].ids.count == book.count)
    check("\(order.rawValue) offers no index", AddressBookShape.index(of: s).isEmpty)
}
check("only .name sections", Order.allCases.filter(\.sections) == [.name])
check("an empty book has no sections", AddressBookShape.sections([], order: .name).isEmpty)

print("")
print("Every order is TOTAL — the ties here are the common case, not a corner")
// A bulk paste writes forty entries inside one millisecond, and forty
// un-dealt-with addresses all have an activity of zero. An order that leaves
// those unordered reshuffles between body passes and reads as a glitch.
let tied = [row("Zed", "z", added: 0), row("Ada", "a", added: 0), row("Mia", "m", added: 0)]
for order in Order.allCases {
    let a = AddressBookShape.ordered(tied, order: order).map(\.id)
    let b = AddressBookShape.ordered(tied.reversed(), order: order).map(\.id)
    check("\(order.rawValue) is insensitive to arrival order", a == b)
}
let sameActivity = [row("Zed", "z", activity: 3), row("Ada", "a", activity: 3)]
check("equal activity falls through to the name",
      AddressBookShape.ordered(sameActivity, order: .activity).map(\.id) == ["a", "z"])
// Two entries that print the same NAME — the collision the book warns about on
// its own rows — must still order stably, which only the id can do.
let twins = [row("Mom", "second"), row("Mom", "first")]
check("identical names fall through to the id",
      AddressBookShape.ordered(twins, order: .name).map(\.id) == ["first", "second"])

print("")
print("What each order actually orders on")
let mixed = [row("Ada", "a", added: 0, watched: false, activity: 1),
             row("Zed", "z", added: 100, watched: false, activity: 9),
             row("Mia", "m", added: 50, watched: true, activity: 5)]
check("name is alphabetical",
      AddressBookShape.ordered(mixed, order: .name).map(\.id) == ["a", "m", "z"])
// §433's surviving half: a star is the person's own statement that a row
// matters more, so recency honours it.
check("recent hoists the watched, then newest-named",
      AddressBookShape.ordered(mixed, order: .recent).map(\.id) == ["m", "z", "a"])
check("activity is most-dealt-with first",
      AddressBookShape.ordered(mixed, order: .activity).map(\.id) == ["z", "m", "a"])
// The fixture must FAIL the rule it names and pass every other one, or it is
// testing something else: these three ids are in a different order under each.
check("the fixture discriminates all three orders",
      Set([AddressBookShape.ordered(mixed, order: .name).map(\.id),
           AddressBookShape.ordered(mixed, order: .recent).map(\.id),
           AddressBookShape.ordered(mixed, order: .activity).map(\.id)]).count == 3)
// A `#` name must not lead the list under a heading printed at the bottom.
let hashLed = [row("…44b1", "h"), row("Ada", "a")]
check("a # name never leads an A–Z list",
      AddressBookShape.ordered(hashLed, order: .name).map(\.id) == ["a", "h"])

print("")
print("Group matching — ONE rule, so the results and the rows agree")
check("a whole name matches", AddressBookShape.groupMatches("Family", query: "family"))
check("case folds", AddressBookShape.groupMatches("family", query: "FAMILY"))
check("a partial query matches by substring", AddressBookShape.groupMatches("Family", query: "fam"))
check("surrounding whitespace folds", AddressBookShape.groupMatches("Family", query: "  fam  "))
check("an unrelated query does not match", !AddressBookShape.groupMatches("Family", query: "work"))
// An empty query must find NOTHING — the book returns everything for an empty
// search, and a group offered above that list would claim the whole book was a
// match for it.
check("an empty query matches no group", !AddressBookShape.groupMatches("Family", query: ""))
check("a whitespace query matches no group", !AddressBookShape.groupMatches("Family", query: "   "))
check("matchingGroups keeps the given order",
      AddressBookShape.matchingGroups(["Work", "Family", "Cold"], query: "o") == ["Work", "Cold"])

print("")
print("The recency phrase")
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(secondsFromGMT: 0)!
// Pinned, or the month name is whatever language the host happens to run in
// and the boundary assertions below compare against English.
cal.locale = Locale(identifier: "en_US_POSIX")
let now = cal.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 12))!
func phrase(_ c: DateComponents) -> String? {
    AddressBookShape.lastPhrase(cal.date(from: c)!, now: now, calendar: cal)
}
check("today", phrase(.init(year: 2026, month: 8, day: 22, hour: 9)) == "today")
check("yesterday", phrase(.init(year: 2026, month: 8, day: 21, hour: 9)) == "yesterday")
check("inside the week counts days", phrase(.init(year: 2026, month: 8, day: 19)) == "3 days ago")
// The rungs get COARSER as they get older: "241 days ago" is arithmetic nobody
// wanted, and at that distance the month is the fact.
check("six days is still counted", phrase(.init(year: 2026, month: 8, day: 16)) == "6 days ago")
check("seven days becomes a month name", phrase(.init(year: 2026, month: 8, day: 15))?.contains("August") == true)
check("earlier this year names its month", phrase(.init(year: 2026, month: 5, day: 4))?.contains("May") == true)
// THE BOUNDARY, where an off-by-one prints a month from two years ago as
// though it were this spring.
check("last year names the year", phrase(.init(year: 2025, month: 12, day: 31)) == "2025")
check("…and the day after is this year's month",
      phrase(.init(year: 2026, month: 1, day: 1))?.contains("Jan") == true)
check("an older year names its own year", phrase(.init(year: 2023, month: 5, day: 4)) == "2023")
// A landed thing stamped ahead of the clock is a bridge's bad timestamp;
// inventing a phrase for it prints nonsense on a row.
check("a future date says nothing", phrase(.init(year: 2027, month: 1, day: 1)) == nil)
check("now itself is today", AddressBookShape.lastPhrase(now, now: now, calendar: cal) == "today")

print("")
if failures > 0 { print("\(failures) failure(s)"); exit(1) }
print("all assertions pass")
SWIFT

echo "address-book-selftest: compiling AddressBookShape.swift AS SHIPPED…"
swiftc -O -o "$TMP/run" "$SHAPE" "$TMP/main.swift" 2>&1 | sed 's/^/  /'
"$TMP/run"

# --- the mutation pass ------------------------------------------------------
# A check that cannot fail proves nothing. Each of these is a silent wrong
# answer this file exists to catch.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$SHAPE" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
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

echo ""
echo "Mutations — each is a list that looks completely normal:"

# `…44b1` under `4`, and every unnamed wallet in the book with it.
mutate "a non-letter gets its own heading instead of #" \
  'return first.isLetter ? String(first).uppercased() : "#"' \
  'return String(first).uppercased()'
# Ångström filed past Z by a heading that doesn't fold what the sort does.
mutate "the heading stops folding diacritics" \
  'guard let first = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                          locale: .current).first' \
  'guard let first = trimmed.first'
# The one arrangement that is visibly wrong: a # row leading a list whose #
# heading is printed at the bottom.
mutate "# stops sorting after the letters" \
  'if la == "#" { return false }' \
  'if la == "#" { return true }'
# The tie-break that keeps a bulk paste from reshuffling between body passes.
mutate "the name order stops being total" \
  'return a.id < b.id' \
  'return false'
mutate "activity ties stop falling through to the name" \
  'if $0.activity != $1.activity { return $0.activity > $1.activity }
                return byName($0, $1)' \
  'return $0.activity > $1.activity'
mutate "recency stops hoisting the watched" \
  'if $0.watched != $1.watched { return $0.watched }' \
  'if false { return $0.watched }'
# A run of rows split into one section per row, each with its own heading.
mutate "adjacent rows stop merging into one section" \
  'if out.last?.letter == letter' \
  'if false'
# The scrubber, offering every letter of the alphabet on a book of six.
mutate "the index stops being derived from the sections" \
  'sections.compactMap(\.letter)' \
  '["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]'
# A group offered as a result for a query that matches nothing — which on an
# EMPTY query means every group is offered above the whole book.
mutate "an empty query starts matching every group" \
  'guard !q.isEmpty else { return false }' \
  'guard !q.isEmpty else { return true }'
# "241 days ago", where the month was the fact.
mutate "the day count stops handing over to the month" \
  'if days < 7 { return String(localized: "\(days) days ago") }' \
  'return String(localized: "\(days) days ago")'
# A month from two years ago printed as though it were this spring.
mutate "the year boundary stops being checked" \
  'if calendar.component(.year, from: date) == calendar.component(.year, from: now) {' \
  'if true {'
# A row claiming you dealt with somebody today because a bridge stamped a
# timestamp ahead of the clock.
mutate "a future date gets a phrase" \
  'guard date <= now else { return nil }' \
  'guard true else { return nil }'
# Sectioning turned on for an order that isn't alphabetical — letter headings
# over rows arranged by recency.
mutate "an unlettered order starts sectioning" \
  'var sections: Bool { self == .name }' \
  'var sections: Bool { true }'

echo ""
echo "address-book-selftest: OK — assertions pass and every mutation is caught."
