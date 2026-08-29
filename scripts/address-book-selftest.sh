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
# `AddressSpineCard` — itself deleted 2026-08-27 (prd §497, user ruling); the
# arithmetic survives in `AddressConnections`, covered by
# `wallet-viz-selftest.sh`, and a §497 negative below keeps the drawing from
# quietly returning.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHAPE="Casberi/Casberi/Model/AddressBookShape.swift"
BOOK="Casberi/Casberi/Model/AddressBook.swift"
ACTIVITY="Casberi/Casberi/Model/AddressActivity.swift"
# The ROSTER — your own five addresses, and nothing else (prd §461).
SCREEN="Casberi/Casberi/Screens/WalletScreen.swift"
# §466 split WalletScreen further: the field that WATCHES (shared with the
# roster section below it now lives in the book) and the roster ITSELF —
# rows, rename, remove, sync status — moved into the book as its own section.
# `$SCREEN` is what remains: the first address, the room door, the book door,
# the chains door. Most of the checks that used to name `$SCREEN` for a
# roster-shaped fact now name `$FIELD` or `$ROSTER` instead — moved file
# rather than deleted, the same rule this harness's own header states for
# `address-sky-selftest.sh`'s retirement.
FIELD="Casberi/Casberi/Screens/WalletWatchField.swift"
# §511 DELETED `WalletRosterSection.swift` with the pinned block it drew — the
# five are ordinary rows of the book now, found through the `Watching` chip.
# What survived it is the unwatch verb (the fold, the prune, the sentence, the
# undo) and the chain read's own status, which is not a row; `$UNWATCH` is that
# file, and `$UNFOLLOW` is its social twin. Guards that used to name `$ROSTER`
# for a roster-shaped fact now name `$UNWATCH` or `$BOOKSCREEN` — moved file
# rather than deleted, the rule this harness's own header states for
# `address-sky-selftest.sh`'s retirement.
UNWATCH="Casberi/Casberi/Screens/WalletWatching.swift"
UNFOLLOW="Casberi/Casberi/Screens/SocialUnfollow.swift"
PEOPLE="Casberi/Casberi/Model/AddressBookPeople.swift"
# The BOOK — everyone else, as a room. §461 split these; before it, both of
# these were one screen, which is why most of the guards below moved file
# rather than changing.
BOOKSCREEN="Casberi/Casberi/Screens/AddressBookScreen.swift"
VIEWS="Casberi/Casberi/Screens/AddressBookViews.swift"
GROUPS="Casberi/Casberi/Screens/AddressGroupViews.swift"
BAR="Casberi/Casberi/Screens/AddressIndexBar.swift"
FLIGHT="Casberi/Casberi/Screens/AddressFlight.swift"
REVEAL="Casberi/Casberi/Screens/AddressReveal.swift"
SOURCE="Casberi/Casberi/Model/AddressConnectionsSource.swift"
# The connections MODEL — where §448 cut `headline`/`subhead` out.
CONN="Casberi/Casberi/Model/AddressConnections.swift"
# The shell — where the rail is built and the route node resolved (§461).
SHELL_MAIN="Casberi/Casberi/Shell/MainSurface.swift"
ROUTE="Casberi/Casberi/Shell/HomeRoute.swift"
for f in "$SHAPE" "$BOOK" "$ACTIVITY" "$SCREEN" "$FIELD" "$UNWATCH" "$UNFOLLOW" "$PEOPLE" "$BOOKSCREEN" "$VIEWS" "$GROUPS" "$BAR" "$FLIGHT" "$SOURCE" "$CONN" "$SHELL_MAIN" "$ROUTE"; do
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
strip_comments "$FLIGHT" > "$TMP/flight-bare.swift"
strip_comments "$SCREEN" > "$TMP/screen-bare.swift"
strip_comments "$FIELD"  > "$TMP/field-bare.swift"
strip_comments "$UNWATCH" > "$TMP/unwatch-bare.swift"
strip_comments "$UNFOLLOW" > "$TMP/unfollow-bare.swift"
strip_comments "$PEOPLE" > "$TMP/people-bare.swift"
strip_comments "$BOOKSCREEN" > "$TMP/book-bare.swift"
strip_comments "$GROUPS" > "$TMP/groups-bare.swift"
strip_comments "$VIEWS"  > "$TMP/views-bare.swift"
strip_comments "$SHAPE"  > "$TMP/shape-bare.swift"
strip_comments "$REVEAL" > "$TMP/reveal-bare.swift"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled file cannot prove about itself. A perfect `sections` is
# worthless if the list draws its own order, if the scrubber invents its own
# letters, or if the search field and the book disagree about what a group is.

grep -q 'AddressBookShape.sections(shapeRows(entries), order: bookSort)' "$BOOKSCREEN" \
  || grep -q 'AddressBookShape.sections(rows, order: bookSort)' "$BOOKSCREEN" \
  || { echo "✗ the manager no longer takes its sections from AddressBookShape — the order would be the screen's own and nothing could test it"; exit 1; }
grep -q 'AddressBookShape.index(of: sections)' "$BOOKSCREEN" \
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
grep -q 'private var bookSort: AddressBookShape.Order = .name' "$BOOKSCREEN" \
  || { echo "✗ the book no longer opens A–Z — the letter headings and the scrubber would only appear if somebody changed the sort"; exit 1; }

# THE SEARCH FOLD. Everything above the book collapses while you type, or the
# field is a search box with two screens of chrome above its results. Anchored
# to the two branches that actually fold — the top half and the foot — rather
# than to the flag's declaration, which would pass against a `searching` that
# nothing reads.
grep -q 'if !searching {' "$TMP/book-bare.swift" \
  || { echo "✗ the book room no longer folds the groups strip while searching"; exit 1; }

# ONE SEARCH PER BODY PASS (prd §441). `book.search` was reached four times a
# pass; the fix is a single `let` threaded down. A section builder that goes
# back to the store for its own copy silently restores the cost.
grep -q 'let entries = visibleEntries()' "$TMP/book-bare.swift" \
  || { echo "✗ the body no longer hoists the filtered book — the search would run once per reader again (§441)"; exit 1; }
grep -q 'private func bookSection(entries: \[AddressBook.Entry\]' "$BOOKSCREEN" \
  || { echo "✗ the book list no longer takes its entries as a parameter"; exit 1; }

# ONE CORPUS WALK, TWO READINGS (prd §441).
grep -q 'let things = AddressActivity.relevant(in: modelContext)' "$BOOKSCREEN" \
  || { echo "✗ the book room fetches the corpus twice again — the activity summary and the connections map both walked their own fetch (§441)"; exit 1; }
grep -q 'static func map(things: \[Thing\]) -> Map?' "$SOURCE" \
  || { echo "✗ AddressConnections can no longer be built from an already-fetched array"; exit 1; }
# The re-sort inside `edges(from:)` is load-bearing: AddressActivity hands back
# NEWEST first and node order is FIRST-DEALT (§295), so trusting the caller's
# order silently reverses the spine — a card that renders perfectly and lists
# the newest relationship as the oldest.
grep -q 'things.sorted(by: { $0.capturedAt < $1.capturedAt })' "$SOURCE" \
  || { echo "✗ edges(from:) trusts the caller's order — the spine would be reversed, and it would look completely normal"; exit 1; }

# ── §461: NOTHING ON A READING SURFACE CHANGES WHAT THE APP READS ───────────
#
# The star retired here 2026-08-24 with `connectPromote`'s lift, `§441`'s star
# flight having already gone in §448. The three guards below are the whole
# ruling, and each failure they catch renders as a perfectly ordinary screen:
# a book row that quietly starts a chain sync, an address card that spends one
# of five slots, or a roster that has grown a second address book inside it.
#
# The strongest is the NEGATIVE: `outcome(ofAdding:)` is the one call that
# enrols an address, and it may appear in the roster and nowhere else.
grep -q 'outcome(ofAdding:' "$TMP/field-bare.swift" \
  || { echo "✗ nothing watches anything — WalletWatchField is the only place that may (§461/§466)"; exit 1; }
grep -q 'outcome(ofAdding:' "$TMP/screen-bare.swift" \
  && { echo "✗ WalletScreen calls outcome(ofAdding:) directly again — that call belongs to WalletWatchField alone, or the setup screen and the book answer a paste two different ways (§466)"; exit 1; }
grep -q 'outcome(ofAdding:' "$TMP/unwatch-bare.swift" \
  && { echo "✗ the unwatch file words a refusal itself — that door belongs to WalletWatchField (§466)"; exit 1; }
grep -q 'outcome(ofAdding:' "$TMP/book-bare.swift" \
  && { echo "✗ the address book words a refusal itself — the outcome-wording door belongs to WalletWatchField (§461/§466)"; exit 1; }
grep -q 'outcome(ofAdding:' "$TMP/views-bare.swift" \
  && { echo "✗ the address card words a refusal itself — see above (§461/§466)"; exit 1; }

# ── §511: THE TWO WATCH DOORS, COUNTED ──────────────────────────────────────
#
# The three greps above were the whole of §461's negative and they stopped
# meaning what they say. `outcome(ofAdding:)` is only the WORDING door; the
# call that actually enrols an address is `add`, and §498 put one in the book
# (the paste preview's capsule) while §511 put one on the address card (the
# overflow menu's Watch row). Both are deliberate, both are argued in their own
# files — and a guard that passes because a new door chose a different spelling
# is green for the wrong reason, which is the failure this repo spends harnesses
# to avoid.
#
# So they are COUNTED, not forbidden: exactly one each, and a second watch door
# appearing silently in either file fails the build. Occurrences, never lines —
# `grep -c` counts lines, and a second call appended to the same line is exactly
# how the equivalent guard in `safetx-selftest.sh` was first defeated.
count_of() { python3 -c "import sys;print(open(sys.argv[1]).read().count(sys.argv[2]))" "$1" "$2"; }
[[ "$(count_of "$TMP/book-bare.swift" 'WalletStore.shared.add(')" == "2" ]] \
  || { echo "✗ the book has other than exactly two watch doors — §498's paste-preview capsule and §511's row menu, and nothing else"; exit 1; }
[[ "$(count_of "$TMP/views-bare.swift" 'WalletStore.shared.add(')" == "1" ]] \
  || { echo "✗ the address card has other than exactly one watch door — §511 allows the overflow menu's Watch row and nothing else"; exit 1; }
# The card may only ADD. Stopping a watch carries a corpus prune, §511's
# keep-or-fold decision and an undo, and a second copy of that is two answers to
# one question.
# The card and the book row both OFFER the unwatch; neither may implement it.
# It prunes the corpus, decides whether the book entry leaves with the watch and
# owes a sentence and an undo for both, and a second copy would get one of those
# subtly differently.
grep -q 'FollowPrune.removeWallet' "$TMP/views-bare.swift" "$TMP/book-bare.swift" \
  && { echo "✗ a screen implements the unwatch itself — it belongs to WalletUnwatch alone (§511)"; exit 1; }
grep -q 'WalletUnwatch.perform(' "$TMP/views-bare.swift" \
  || { echo "✗ the address card cannot stop a watch — a plain tap is the discoverable door §511 added (§511)"; exit 1; }
grep -q 'WalletUnwatch.perform(' "$TMP/book-bare.swift" \
  || { echo "✗ the book row cannot stop a watch (§511)"; exit 1; }

# ── §511: ONE CONSEQUENCE, ONE WORD ─────────────────────────────────────────
#
# The report this fixes was a vocabulary bug, not a model bug: the roster's
# destructive verb and the book's were both spelled "Remove" and meant two
# different things, so unwatching read as a delete that had failed. Each failure
# below renders as a perfectly ordinary menu.
grep -q 'Label("Stop watching"' "$TMP/book-bare.swift" \
  || { echo "✗ the watch verb is not 'Stop watching' — the bare 'Remove' is the book's word for a different consequence (§511)"; exit 1; }
grep -q 'Label("Stop watching"' "$TMP/views-bare.swift" \
  || { echo "✗ the address card's watch verb is not 'Stop watching' (§511)"; exit 1; }
grep -qE 'Label\("Remove", ' "$TMP/views-bare.swift" \
  && { echo "✗ the address card says the bare 'Remove' again (§511)"; exit 1; }
grep -q 'Label("Remove from book"' "$TMP/book-bare.swift" \
  || { echo "✗ the book row's destructive verb no longer names the book — 'Remove' beside the roster's own means nothing (§511)"; exit 1; }
grep -qE 'Label\("Remove", ' "$TMP/book-bare.swift" \
  && { echo "✗ the book says the bare 'Remove' again (§511)"; exit 1; }

# ── §511: THE FOLD, THE SENTENCE, THE UNDO ──────────────────────────────────
#
# The keep-or-fold decision must come from the harnessed function, or it is the
# screen's own and nothing above can test it — and this decision DELETES a book
# entry, so an untested version of it silently discards names.
grep -q 'AddressBookShape.unwatchKeepsEntry(' "$TMP/unwatch-bare.swift" \
  || { echo "✗ the unwatch decides for itself whether it keeps the name — that decision deletes book entries and belongs in AddressBookShape, where it can be tested (§511)"; exit 1; }
# An unwatch that keeps the name DEMOTES the row into a lettered section that is
# usually scrolled off screen. Silently, that is indistinguishable from a delete
# that failed — which is exactly how it was reported.
grep -q 'chrome.flash(' "$TMP/unwatch-bare.swift" \
  || { echo "✗ an unwatch says nothing — it deletes landed rows and can delete the book entry with them (§511)"; exit 1; }
grep -q 'action: .init(label:' "$TMP/unwatch-bare.swift" \
  || { echo "✗ the unwatch toast carries no Undo (§511)"; exit 1; }
grep -q 'FollowPrune.removeWallet' "$TMP/unwatch-bare.swift" \
  || { echo "✗ an unwatch no longer prunes the wallet's landed rows (§387)"; exit 1; }
# The discoverable door. §461 made these rows bare, which is right for the
# resting state and left unwatching reachable only by two gestures nothing on
# screen mentions.
# THE INERT MARK (§511). With the pinned block gone the book must say which
# rows the app actually READS, or the only way to find out is to run a filter —
# a control answering a question the list should already have answered. A glyph
# and never the star: a star is a CONTROL on a row, which is exactly what §461
# deleted.
grep -q '"eye.fill"' "$TMP/views-bare.swift" \
  || { echo "✗ a watched row is indistinguishable from every other row (§511)"; exit 1; }
grep -q 'Button(action: onToggleWatch)' "$VIEWS" \
  || { echo "✗ the row's star is gone entirely — the parameter is what keeps AddressGroupScreen on one anatomy (§461)"; exit 1; }
grep -qE 'star\.fill|"star"' "$TMP/book-bare.swift" \
  && { echo "✗ a star is back on a book row (§461)"; exit 1; }
# …and the row's own star is drawn only when a caller passes the closure, so
# neither screen may pass one. The book row keeps the parameter: `AddressGroupScreen`
# and any future caller still get one anatomy, and a parameter nobody passes is
# what makes that safe.
grep -q 'onToggleWatch' "$TMP/book-bare.swift" \
  && { echo "✗ the book passes a watch toggle to its rows (§461)"; exit 1; }
grep -q 'onToggleWatch' "$TMP/screen-bare.swift" "$TMP/unwatch-bare.swift" \
  && { echo "✗ a screen passes a watch toggle to its rows — §511 merged the lists and did NOT bring the star back (§461)"; exit 1; }
# The flight's ends are RAMP tokens the caller passes, and since §448 they are
# REQUIRED: the old defaults named the star flight's own anchors, and a default
# pointing at an anchor nothing publishes draws nothing at all — silently,
# which is the failure this file exists to avoid. The ruling behind them is
# unchanged: the size may never be read off the anchor rects, which are layout
# frames and stop matching the face the moment a mark gains a border.
grep -q 'let size = fromSize + (toSize - fromSize) \* progress' "$FLIGHT" \
  || { echo "✗ the flight no longer interpolates between two ramp sizes"; exit 1; }
grep -q 'var fromSize: CGFloat = DS.Face.list' "$FLIGHT" \
  || { echo "✗ the flight's start stopped being a ramp token — and this file is the only place face-ramp-audit can see that a travelling face's ends are tiers"; exit 1; }
grep -q 'var toSize: CGFloat = DS.Face.shelf' "$FLIGHT" \
  || { echo "✗ the flight's end stopped being a ramp token — see above"; exit 1; }
# The KEYS, unlike the sizes, may carry no default (§448). The old ones named
# the star flight's anchors, and this overlay's answer to a key nothing
# publishes is to draw nothing at all — silently.
grep -qE '(var|let) (from|to)Key: String *=' "$TMP/flight-bare.swift" \
  && { echo "✗ the flight grew a default ANCHOR again — a key nothing publishes draws nothing, silently (§448)"; exit 1; }
grep -qE 'let (from|to)Key: String$' "$FLIGHT" \
  || { echo "✗ the flight's anchors stopped being required (§448)"; exit 1; }
grep -qE '\b[ab]\.(width|height|size)\b' "$TMP/flight-bare.swift" \
  && { echo "✗ the flight sizes itself off the anchor rects again — those are layout frames and stop matching the face the moment a mark gains a border"; exit 1; }

# ── §448: ONE ROW ANATOMY, ONE FACE PER ADDRESS ─────────────────────────────
#
# The shelf drew every watched wallet twice on one screen — a 56pt face in a
# 64pt slot with its name captioned in `label12` (about nine characters, so
# "Cold storage" clipped), while the same wallet's own book row sat lower down
# with the whole name, a subline and a filled star. Every guard here defends a
# failure that renders as a perfectly ordinary list.

# ONE LIST (§511), reversing §461's exclusion and restoring §448's own reading
# of the same question: "a search that also filtered them out would be a search
# that cannot find the wallets you watch". With no block above, excluding them
# here would mean the book cannot find the addresses you care most about.
grep -q 'book.search(query).filter { !isWatched($0) }' "$TMP/book-bare.swift" \
  && { echo "✗ the book excludes your own watched wallets again — §511 deleted the block they used to be drawn in, so they would be nowhere (§511)"; exit 1; }
grep -q 'is one of your own wallets' "$TMP/book-bare.swift" \
  && { echo "✗ the search still sends somebody to another screen for a row that is right here (§511)"; exit 1; }
grep -q 'WalletRosterSection' "$TMP/book-bare.swift" \
  && { echo "✗ the pinned Watching block is back — the book is two lists again (§511)"; exit 1; }
grep -q 'WalletWatchSyncSection()' "$TMP/book-bare.swift" \
  || { echo "✗ the chain read's status is gone — 'reading onchain activity' has no row to be, and a book that is still loading looks finished (§511)"; exit 1; }
# The head must name what it LISTS. "Everyone else" was true only while the five
# sat above; under a narrowing chip it says the count and NOT the population's
# name, because the lit chip is already the name (§366's read-it-twice).
grep -q 'Everyone · \\(count)' "$TMP/book-bare.swift" \
  || { echo "✗ the book's head no longer names or counts what it actually lists (§448/§511)"; exit 1; }
grep -q 'Everyone else' "$TMP/book-bare.swift" \
  && { echo "✗ the head still says 'Everyone else' over a list that holds everyone (§511)"; exit 1; }

# ── §511: THE WATCHING CHIP AND ITS CAP ─────────────────────────────────────
grep -q 'watching: watchedCount' "$TMP/book-bare.swift" \
  || { echo "✗ the chip strip never learns how many are watched — the Watching chip would never be offered (§511)"; exit 1; }
grep -q 'AddressBookShape.watchingLabel(watchedCount' "$TMP/book-bare.swift" \
  || { echo "✗ the Watching chip stopped carrying the cap — deleting the block deleted the only other place the app said how many of the five are spent (§511)"; exit 1; }
grep -q 'watched: isWatched($0)' "$TMP/book-bare.swift" \
  || { echo "✗ the chip filters on something other than the roster's own answer (§511)"; exit 1; }

# ── §511: A SOCIAL ROW HAS A VERB ───────────────────────────────────────────
#
# A starter pack WATCHES everyone in it, so those rows are the roster of what is
# filling the feed. Every write door is shut for an ephemeral row by
# construction (`isInBook` is false), which is why the book listed forty people
# and offered nothing to do about any of them — §83's dead row, forty times.
grep -q 'SocialUnfollow.perform(' "$TMP/book-bare.swift" \
  || { echo "✗ a followed account cannot be unfollowed from the book row (§511)"; exit 1; }
grep -q 'SocialUnfollow.perform(' "$TMP/views-bare.swift" \
  || { echo "✗ a followed account cannot be unfollowed from its card (§511)"; exit 1; }

# RENAMING A WATCHED WALLET GOES THROUGH THE ROSTER (§511). The card is the only
# place a watched wallet is named now that the pinned block is gone, and
# `book.setName` writes only the book — so this door alone would leave
# `WatchedAddress.label` stale forever, and the label is what the face rail's
# caption, the feed's wallet tags and a self-transfer's title all read. The book
# would show the new name and every place money is described the old one.
grep -q 'store.rename(watch.id, to: name)' "$TMP/views-bare.swift" \
  || { echo "✗ renaming a watched wallet no longer updates the roster label — the book and the feed would disagree about its name (§511)"; exit 1; }
# ONE ACT: the row IS the watch, so unfollowing must take the posts with it —
# §286's path, never a copy of it.
grep -q 'HandleBridge(rawValue: pair.source)?.removeName(' "$TMP/unfollow-bare.swift" \
  || { echo "✗ the unfollow no longer routes through HandleBridge.removeName — it would edit a list and leave the posts in the feed forever (§286/§511)"; exit 1; }
grep -q 'SocialTopics.pruneAuthor' "$TMP/unfollow-bare.swift" \
  && { echo "✗ the unfollow prunes the corpus itself — removeName resolves Nostr's pubkey first and reads the remaining topics, and a second copy would drop one of those (§511)"; exit 1; }
# THE LEDGER STAYS CLOSED (§498). A pack of forty must never write forty entries.
grep -qE 'setName\(|\.remove\(' "$TMP/people-bare.swift" \
  && { echo "✗ the ephemeral half writes the book — a starter pack would put forty entries in somebody's ledger and sync them (§498/§511)"; exit 1; }
grep -q 'static func unfollowable(' "$PEOPLE" \
  || { echo "✗ the rows a verb can act on are decided somewhere else now (§511)"; exit 1; }
grep -q 'SocialRoom.hasRoster(source)' "$TMP/people-bare.swift" \
  || { echo "✗ unfollowable no longer gates on a roster existing — Twitch's rows are read off the corpus and have nothing to be removed from (§511)"; exit 1; }

# NEGATIVE, comment-stripped: the shelf may not come back. `DS.Face.shelf` is
# the ramp rung it was drawn at and this screen is the only place it was ever
# used at this size.
grep -qE 'DS.Face.shelf' "$TMP/screen-bare.swift" "$TMP/unwatch-bare.swift" "$TMP/book-bare.swift" \
  && { echo "✗ the watched shelf is back — §448 deleted it because it drew every watched wallet a second time, with its name truncated (§448)"; exit 1; }
grep -qE 'rosterSlot|emptyRosterSlot|rosterSlotWidth' "$TMP/screen-bare.swift" "$TMP/unwatch-bare.swift" "$TMP/book-bare.swift" \
  && { echo "✗ the roster shelf's slots are back (§448)"; exit 1; }

# ── §448: THE FEWEST WORDS ──────────────────────────────────────────────────
#
# User ruling, 2026-08-22: "in the connected section we have redundancy … I
# want it with the least amount of words ever there". The card said one thing
# four times before you reached the drawing — a section header, an eyebrow
# repeating it, a headline counting rows the drawing shows one-per, and a
# subhead defining the word.
# §497: the Connected spine LEFT the book (user ruling, 2026-08-27). The
# drawing is deleted; the arithmetic stays in the model for the probe. A
# reference returning here is the ruling being quietly reversed.
grep -qE 'AddressSpineCard|sectionHeader\(String\(localized: "Connected"\)\)' "$TMP/book-bare.swift" \
  && { echo "✗ the Connected spine is back on the address book — §497 removed it (user ruling, with a screenshot)"; exit 1; }
[[ -f "Casberi/Casberi/Screens/AddressSpineCard.swift" ]] \
  && { echo "✗ AddressSpineCard.swift is back; §497 deleted it with its only call site"; exit 1; }
grep -qE 'static func (headline|subhead)\(count:' "$CONN" \
  && { echo "✗ AddressConnections.headline/subhead are back; §448 cut them"; exit 1; }
# A group says its COUNT and stops. "3 addresses · none watched" clipped to
# "3 addresses · none wat…" at 150pt, and whether a group's members are watched
# is a fact about the Watching section, not about the group.
grep -qE 'watched\)? watched|none watched' "$TMP/groups-bare.swift" \
  && { echo "✗ a group counts its watched members again — user ruling 2026-08-22, and it clipped at 150pt (§448)"; exit 1; }

# THE FILING FLIGHT (§444) — the same face, the other direction. Filing was the
# one gesture in the book whose whole feedback was a checkmark appearing.
grep -q 'fromKey: "head:", toKey: "group:"' "$GROUPS" \
  || { echo "✗ filing an address no longer sends its face into the group — the tick would be the only feedback again"; exit 1; }
grep -q 'flightAnchor("group:" + AddressBook.key(forGroup: name))' "$GROUPS" \
  || { echo "✗ a group row no longer publishes a landing anchor, or stopped keying it the BOOK's way — a group typed in another case would never find its own row"; exit 1; }
grep -q 'toSize: AddressMoveSheet.deckFace' "$GROUPS" \
  || { echo "✗ the filing flight stopped ending at the deck's own face size"; exit 1; }
grep -q 'absorbing == AddressBook.key(forGroup: name)' "$GROUPS" \
  || { echo "✗ the group row no longer takes the hit when a face lands in it"; exit 1; }
# A group row wears the faces of who is in it (§444) — you file by recognising
# people, and a checkmark, a word and a tally names none of them.
grep -q 'AddressMark(entry: member' "$GROUPS" \
  || { echo "✗ a group row lost its members' faces"; exit 1; }
grep -q 'absorbing == key' "$BOOKSCREEN" \
  || { echo "✗ a dropped face is no longer absorbed by the deck"; exit 1; }
grep -q 'defaults.set(true, forKey: seededKey)' "$SOURCE" \
  || { echo "✗ the seen-set no longer seeds silently on first sight — a year of history would announce itself as today's news (the Hyperliquid 2026-07-30 bug)"; exit 1; }

# ONE ROW ANATOMY. Two spellings of the book row is two books.
grep -q 'struct AddressBookRow: View' "$VIEWS" \
  || { echo "✗ the shared row is gone; the manager and the group screen would each draw their own"; exit 1; }
grep -q 'AddressBookRow(entry: entry' "$BOOKSCREEN" \
  || { echo "✗ the book room no longer draws the shared row"; exit 1; }
grep -q 'AddressBookRow(entry: entry' "$GROUPS" \
  || { echo "✗ the group screen no longer draws the shared row"; exit 1; }

# THE THREE MOVE DOORS (§440). Each is named, because two of them exist
# precisely so the feature survives the third misbehaving on a device.
grep -q '.draggable(entry.address)' "$BOOKSCREEN" \
  || { echo "✗ a book row is no longer draggable — dragging onto a group card is the primary filing gesture"; exit 1; }
grep -q 'dropDestination(for: String.self)' "$BOOKSCREEN" \
  || { echo "✗ a group card is no longer a drop target"; exit 1; }
grep -q 'bookSheet = .move(entry)' "$BOOKSCREEN" \
  || { echo "✗ swipe no longer opens the filing sheet"; exit 1; }
grep -q 'struct AddressMoveSheet: View' "$GROUPS" \
  || { echo "✗ the filing sheet is gone"; exit 1; }
# The swipe must stay a DOOR and never a write — the design law's own "swipe
# verbs are reads; a write belongs behind a deliberate press" (§212). It opens
# a sheet, and the sheet takes the consent.
grep -q 'swipeActions(edge: .trailing, allowsFullSwipe: false)' "$BOOKSCREEN" \
  || { echo "✗ the book's swipe gained a full swipe — a full swipe commits without a second beat, which for a write is exactly what §212 forbids"; exit 1; }

# ONE DESTRUCTIVE VERB PER ROW, on the swipe as well as in the menu
# (2026-08-29). Reported as "why do the address book items have a swipe to move
# but not to remove": a plain named row is neither watched nor followed, so both
# of the swipe's destructive arms were skipped and the gesture carried `Move…`
# alone — a move-only affordance on the one population whose verb it is.
#
# COUNTED, never asserted by presence: the phrase is in the context menu too, so
# a bare `grep -q` here passes green with the swipe arm deleted. Counted by
# OCCURRENCE and not by line (`grep -c` counts lines, and one line carrying both
# is how the equivalent guard in `safetx-selftest.sh` was first defeated).
removes=$(grep -o 'Label("Remove from book"' "$TMP/book-bare.swift" | wc -l | tr -d ' ')
[ "$removes" -ge 2 ] \
  || { echo "✗ the book names 'Remove from book' $removes time(s) — the swipe and the long-press menu must each carry it, or an unwatched row's swipe is Move-only again"; exit 1; }
grep -q 'Label("Remove from book", systemImage: "trash")' "$TMP/book-bare.swift" \
  || { echo "✗ the book's remove verb lost its mark (§511)"; exit 1; }

# NEGATIVE, on comment-stripped copies: §435's money ruling. The manager is a
# PEOPLE screen and the feed's crown owns the money reading, once.
for f in "$TMP/screen-bare.swift" "$TMP/book-bare.swift" "$TMP/groups-bare.swift"; do
  grep -q 'WalletValue.money' "$f" \
    && { echo "✗ a money figure returned to the address book — §435 struck every one of them off this screen"; exit 1; }
done

# NEGATIVE: `lastPhrase` may never ask the SYSTEM clock again (prd §448).
# `isDateInToday`/`isDateInYesterday` ignore the `now` they are handed, so the
# two rungs a row shows most often were untestable — and this harness's own
# verdict depended on what hour it ran at: the fixtures went red at 17:00
# Pacific, when UTC rolls over, against code nobody had touched. The file
# documents that by naming both methods, hence the stripped copy.
grep -qE 'isDateIn(Today|Yesterday)' "$TMP/shape-bare.swift" \
  && { echo '✗ lastPhrase asks the system clock again — its now parameter would be a lie for the today and yesterday rungs, and this harness would pass or fail by time of day (§448)'; exit 1; }

# NEGATIVE: the sky is gone and must not come back by reference.
grep -qE 'AddressSky' "$TMP/screen-bare.swift" "$TMP/book-bare.swift" \
  && { echo "✗ a wallet screen references AddressSky, which was deleted with §440"; exit 1; }
[[ -f "Casberi/Casberi/Model/AddressSky.swift" ]] \
  && { echo "✗ AddressSky.swift is back; §440 replaced it with the spine"; exit 1; }

# ── §462: THE SAVE ANSWERS, AND THE QUIET TOP ───────────────────────────────
#
# The save's three answers are one flow, and each fails silently alone: a
# whisper that stopped counting reads as a save that rewrote nothing, a scroll
# that stopped firing files the row off-screen, and a flight with no Reduce
# Motion guard is the §79 violation the motion audit cannot see (it is
# gesture-driven, so the audit's appear-trigger check never fires).
grep -q 'CounterpartyRetitle.applyCurrentName(for: target, in: modelContext)' "$BOOKSCREEN" \
  || { echo "✗ the save no longer captures what the name rewrote — the whisper would count nothing forever (§462)"; exit 1; }
grep -q 'rewrote > 0' "$TMP/book-bare.swift" \
  || { echo "✗ the whisper lost its zero gate — 'Saved — 0 transfers' is a count of nothing (§83/§462)"; exit 1; }
grep -q 'isReduceMotionEnabled == false else { return }' "$BOOKSCREEN" \
  || { echo "✗ the save flight ignores Reduce Motion (§462)"; exit 1; }
grep -q 'onChange(of: pendingReveal)' "$BOOKSCREEN" \
  || { echo "✗ the save no longer scrolls to the row it filed — the row lands off-screen under its letter (§462)"; exit 1; }
# THE QUIET TOP (§462). The strip waits for a REAL group; the zeroes are one
# sentence at the foot. The foot line is also §267's discoverability answer,
# so it may not lose the filing hint.
grep -q 'private func quietFootSection' "$BOOKSCREEN" \
  || { echo "✗ the quiet foot is gone — the filing hint has no home (§462; its spine line left with §497)"; exit 1; }
grep -q 'Groups arrive with your first filing' "$TMP/book-bare.swift" \
  || { echo "✗ the foot lost the filing hint — with the dashed card gone, nothing on the screen says groups exist (§267/§462)"; exit 1; }
grep -q 'if !groups.isEmpty {' "$TMP/book-bare.swift" \
  || { echo "✗ the groups strip no longer waits for a real group (§462)"; exit 1; }
# WHEN, down the trailing edge (§462) — recency left the subline for the slot
# the star vacated. Both halves guarded, or the fact is drawn twice or not at
# all.
grep -q 'AddressBookShape.lastPhrase(activity.lastAt)' "$TMP/views-bare.swift" \
  || { echo "✗ the row no longer states WHEN you last dealt (§440/§462)"; exit 1; }

# ── §461: THE DOORS ─────────────────────────────────────────────────────────
#
# A room nobody can reach is worse than no room. There are TWO doors and each
# covers the other's blind spot: the rail's slot is gated on the rail drawing at
# all (`WalletScopeRail.shows` wants more than one wallet watched), so with
# nothing watched — the state a new person is in — it does not exist; the
# roster's row is always there. The minimum corpus is the common one here, which
# is the correction §436–§438 kept paying for.
# **THE DOOR MOVED, IT DID NOT GO** (2026-08-27). §483's rail rewrite left the
# rail's book slot in `FeedScreen` (`onOpenBook:`) while this guard kept
# reading `MainSurface`, where §357 had moved the room CONTROLS. §461's ruling
# is intact — the rail still carries the book glyph — so the fix is to ask
# both files rather than to name one. Asking both is also the stronger check:
# it survives the next move.
grep -qs 'route.push(.addressBook)' "$SHELL_MAIN" "Casberi/Casberi/Screens/FeedScreen.swift" \
  || { echo "✗ the wallet rail's address-book slot is gone — the room would be reachable only from the roster (§461)"; exit 1; }
grep -q 'bookTitle: String(localized: "Address Book")' "$SHELL_MAIN" \
  || { echo "✗ the rail's book door lost its name — the slot is captionless, so the label IS its only naming (VoiceOver and the Mac tooltip)"; exit 1; }
grep -q 'route.push(.addressBook)' "$SCREEN" \
  || { echo "✗ the setup screen lost its door to the book — with nothing watched the rail does not draw, so this is the only way in (§461/§466)"; exit 1; }
grep -q 'case addressBook' "$ROUTE" \
  || { echo "✗ the address book has no route node"; exit 1; }
grep -q 'AddressBookScreen()' "$SHELL_MAIN" \
  || { echo "✗ nothing resolves the addressBook node to a screen"; exit 1; }
# THE ADD VERB IS GONE, not merely stepping aside at the cap (§466, reversing
# §461's own "steps aside at the cap" — watching a new wallet and seeing the
# whole roster are the same screen now that the roster moved into the book,
# so a second slot pointing at the identical destination was chrome, not a
# choice; the same move Vibenet's rail made the same day). The arithmetic
# that motivated the original cap-only rule still applies at fewer slots: two
# trailing doors plus five faces plus All is 402pt against a 393pt phone.
grep -q 'addTitle: nil,' "$SHELL_MAIN" \
  || { echo "✗ the wallet rail's add slot is back — watching a new wallet and seeing the roster are the same screen now (§466)"; exit 1; }
grep -q 'addTitle: wallet.canWatchMore ? String(localized: "Add a wallet") : nil' "$SHELL_MAIN" \
  && { echo "✗ the wallet rail's add slot came back cap-gated — §466 removed it outright, not just at five of five"; exit 1; }
# THE WAY ONWARD (§460). The roster is a connect page and was the one screen in
# the catalog's largest family without the door every other one carries.
grep -q 'RoomDoor(name: "Wallet", source: "Wallet")' "$SCREEN" \
  || { echo "✗ the roster lost its View feed door (§460)"; exit 1; }

# §439's wallet-to-wallet reading lives in the MODEL alone now — its bracket
# and sentence left with the spine (§497).
grep -q 'walletLinks' "$SOURCE" \
  || { echo "✗ AddressConnections lost the direct wallet-to-wallet links (§439) — the model half must survive the drawing"; exit 1; }

# --- §502: the five delight moments ------------------------------------------
# Each of these is motion or a fact that renders as NOTHING when its wiring is
# cut: the deck simply doesn't draw, the letter simply doesn't answer, the
# address simply stays folded. A build cannot see any of it, and neither can a
# screen sweep — every one of them is a frame in the middle of a gesture.

# 1 · THE HERO IS THE FACE THE ROW WAS WEARING. Both ends are RAMP tiers, which
# is the same rule `AddressFlightOverlay` states about a travelling face: the
# sizes a growing face passes through have to be sizes the face has really
# been, and `face-ramp-audit` can only see that when they are named.
grep -q 'addressHeroArrival(size: Self.identityFace)' "$TMP/views-bare.swift" \
  || { echo "✗ the address card's hero no longer enters at the row's size — the sheet's 96pt face reads as a picture this screen had rather than as the one you tapped (§502)"; exit 1; }
grep -q 'DS.Face.list / size' "$TMP/reveal-bare.swift" \
  || { echo "✗ the hero's entering size is no longer a ramp tier — a literal there is a size the face has never been drawn at (§502)"; exit 1; }
grep -q 'guard !reduceMotion else { grown = true; return }' "$TMP/reveal-bare.swift" \
  || { echo "✗ the hero's growth no longer honours Reduce Motion (§299's law, and design-motion-audit only sees appear-triggered animation it can name)"; exit 1; }
# THE DOOR THAT STAYS SHUT. prd §232 dropped `.navigationTransition(.zoom)` for
# SHEETS after a deterministic device crash that never reproduced here, and the
# obvious way to "improve" this moment is to put it back. Read from a
# comment-stripped copy, because both files explain the decision by naming the
# API it governs (the Obsidian/Cursor lesson).
grep -q 'navigationTransition' "$TMP/views-bare.swift" "$TMP/book-bare.swift" "$TMP/reveal-bare.swift" \
  && { echo "✗ the address book reached for .navigationTransition(.zoom) again — prd §232 dropped it for sheets after a device-specific crash; restore only on a symbolicated stack proving another cause"; exit 1; }

# 2 · THE PASTE'S DECK. It must read the WRITE's own tokenizer, or the preview
# and the write are two parsers for one format and the deck shows faces the
# save will not land.
grep -q 'func bulkAddresses(_ raw: String) -> \[String\]' "$BOOK" \
  || { echo "✗ AddressBook no longer enumerates a paste's addresses — the deck would need a parser of its own (§502)"; exit 1; }
[[ $(grep -c 'Self.tokens(in: line)' "$BOOK") -ge 3 ]] \
  || { echo "✗ the paste's three readers no longer share one tokenizer — the deck, the bulk test and the write would disagree about what a list is (§502)"; exit 1; }
grep -q 'book.bulkAddresses(draft)' "$TMP/book-bare.swift" \
  || { echo "✗ the deck no longer reads the paste through the shared tokenizer (§502)"; exit 1; }
grep -q 'prefix(AddressDeck.shown)' "$TMP/book-bare.swift" \
  || { echo "✗ the deck no longer caps its faces — a fan of forty is a smear (§502)"; exit 1; }
grep -q 'AddressDeck.line(count: addresses.count)' "$TMP/book-bare.swift" \
  || { echo "✗ the deck's count is no longer AddressDeck's — a hand-rolled string here is how the tail stops being named (§300, §502)"; exit 1; }

# 3 · THE FILTER NARROWS RATHER THAN REPLACING, and only when it is a FILTER:
# while searching the same rows are rewritten on every keystroke, and a lateral
# slide per character is motion spent on something that is not a decision.
grep -q '.transition(draft.isEmpty' "$TMP/book-bare.swift" \
  || { echo "✗ the book's rows no longer distinguish a filter change from a keystroke — every search character would slide the whole list sideways (§502)"; exit 1; }
grep -q '.opacity.combined(with: .move(edge: .leading))' "$TMP/book-bare.swift" \
  || { echo "✗ a filtered-out row no longer leaves toward the leading edge — the chip reads as handing you a different book rather than narrowing this one (§502)"; exit 1; }

# 4 · THE SCRUB LANDS SOMEWHERE. Two halves in two functions: the bar's callback
# records where you arrived, the heading reads it. Either alone is silent.
grep -q 'landedLetter = letter' "$TMP/book-bare.swift" \
  || { echo "✗ the scrubber's pick no longer records where it landed — the destination would say nothing again (§502)"; exit 1; }
grep -q 'landedLetter == letter ? DS.tint : DS.textSecondary' "$TMP/book-bare.swift" \
  || { echo "✗ the letter you land on no longer answers the scrub (§502)"; exit 1; }

# 5 · WHAT THE COPY TOOK. ONE copy path on the card, so the tile and the reach
# row cannot answer differently — which is exactly what had happened: the row's
# own button said "Copied" in place and the tile said nothing at all.
grep -q 'private func didCopy(_ value: String)' "$VIEWS" \
  || { echo "✗ the address card's copies no longer run through one path — the tile and the reach row would answer differently again (§502)"; exit 1; }
[[ $(grep -c 'DSPasteboard.copy(' "$TMP/views-bare.swift") -eq 1 ]] \
  || { echo "✗ the address card has a second copy call site — one of them will stop answering (§502)"; exit 1; }
grep -q 'value: hex && !copyOpen ? current.short : current.address' "$TMP/views-bare.swift" \
  || { echo "✗ a copied address no longer unfolds from the house short form — the one screen whose subject is an address would never show the middle of it (§502)"; exit 1; }
grep -q 'addressCopySweep(token: copyToken, hue: pourHue)' "$TMP/views-bare.swift" \
  || { echo "✗ the copy no longer sweeps what it took, in the hue the face is worked out from (§444, §502)"; exit 1; }
grep -q 'guard !reduceMotion, token > 0 else { return }' "$TMP/reveal-bare.swift" \
  || { echo "✗ the copy sweep no longer honours Reduce Motion (§299)"; exit 1; }
# THE UNFOLD IS INFORMATION, THE SWEEP IS DECORATION, and only one of them may
# be taken away by Reduce Motion. The card holds no such environment value at
# all, so the unfold cannot be gated on it by accident.
[[ $(grep -c 'reduceMotion' "$TMP/views-bare.swift") -eq 0 ]] \
  || { echo "✗ the address card reads Reduce Motion — the address's unfold is a FACT and must not be one of the things that setting removes (§502)"; exit 1; }

# ── THE MIRROR MAY NOT BE TOUCHED WHILE `shared` IS BEING BUILT ──────────────
# Crash, build 436 (2026-08-28): `init` runs migrations, a migration MUTATES
# `entries`, `entries.didSet` calls `persist()`, and `persist()` ended in
# `AddressBookSync.shared.push()` — whose mirror closures read
# `AddressBook.shared`, mid-`dispatch_once` on the same thread. libdispatch
# kills the process for that ("trying to lock recursively"), before a first
# frame.
#
# Nothing here could catch it and that is the point of guarding it statically:
# it needs a device with iCloud sync ON and older vibenet data to migrate, so a
# signed-out simulator with empty defaults no-ops through the migration and
# every build, audit, harness and launch sweep passes green.
#
# Note `didSet` does NOT fire for an assignment in `init`'s own body — only for
# one made by a METHOD init calls, which is exactly the shape here. Reproduced
# and fixed A/B in isolation before shipping (SIGTRAP vs survives).
book_bare="$TMP/addressbook-bare.swift"
strip_comments "$BOOK" > "$book_bare"
grep -q 'guard !initializing else { return }' "$book_bare" \
  || { echo "✗ AddressBook.persist() no longer holds the iCloud push during init — the mirror re-enters AddressBook.shared's dispatch_once and the app dies on launch (build 436)"; exit 1; }
# ORDER matters, not just presence: the guard must come BEFORE the push, or it
# guards nothing. `AddressBookSync.shared.push()` appears once in this file, so
# plain line numbers settle it.
guard_line=$(grep -n 'guard !initializing else { return }' "$book_bare" | head -1 | cut -d: -f1)
push_line=$(grep -n 'AddressBookSync.shared.push()' "$book_bare" | head -1 | cut -d: -f1)
[[ -n "$guard_line" && -n "$push_line" && "$guard_line" -lt "$push_line" ]] \
  || { echo "✗ the initializing guard no longer precedes the iCloud push in persist() — the launch deadlock is back"; exit 1; }
# …and init must CLEAR it, or the book would persist locally and never sync again.
grep -q 'initializing = false' "$book_bare" \
  || { echo "✗ init never clears \`initializing\` — the address book would never sync to iCloud again"; exit 1; }

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
// **A PAST DATE ON PURPOSE, and it is the whole point of this block**
// (2026-08-22, prd §448). It was the real current day, and the first two
// rungs were spelled `calendar.isDateInToday`/`isDateInYesterday` — which
// IGNORE the `now` handed in and compare against the system clock. So while
// the pinned day and the real day agreed, those two fixtures passed without
// exercising anything, and the moment UTC rolled over (17:00 Pacific) three
// assertions went red on code nobody had touched. Pinned years in the past,
// `isDateInToday` can never be true, so these fixtures now fail the old
// spelling at every hour of every day — the standing rule that a fixture only
// tests the rule it names if it FAILS that rule and passes every other one.
let now = cal.date(from: DateComponents(year: 2021, month: 8, day: 22, hour: 12))!
func phrase(_ c: DateComponents) -> String? {
    AddressBookShape.lastPhrase(cal.date(from: c)!, now: now, calendar: cal)
}
check("today", phrase(.init(year: 2021, month: 8, day: 22, hour: 9)) == "today")
check("yesterday", phrase(.init(year: 2021, month: 8, day: 21, hour: 9)) == "yesterday")
// Same calendar DAY as `now` but a later hour — inside the guard, so it is a
// real "today" rather than the future case below. Without it the today rung
// is only ever asked about a morning, and a row stamped this afternoon is the
// common one on a screen counting today's transfers.
check("later today is still today", phrase(.init(year: 2021, month: 8, day: 22, hour: 11, minute: 59)) == "today")
check("inside the week counts days", phrase(.init(year: 2021, month: 8, day: 19)) == "3 days ago")
// The rungs get COARSER as they get older: "241 days ago" is arithmetic nobody
// wanted, and at that distance the month is the fact.
check("six days is still counted", phrase(.init(year: 2021, month: 8, day: 16)) == "6 days ago")
check("seven days becomes a month name", phrase(.init(year: 2021, month: 8, day: 15))?.contains("August") == true)
check("earlier this year names its month", phrase(.init(year: 2021, month: 5, day: 4))?.contains("May") == true)
// THE BOUNDARY, where an off-by-one prints a month from two years ago as
// though it were this spring.
check("last year names the year", phrase(.init(year: 2020, month: 12, day: 31)) == "2020")
check("…and the day after is this year's month",
      phrase(.init(year: 2021, month: 1, day: 1))?.contains("Jan") == true)
check("an older year names its own year", phrase(.init(year: 2018, month: 5, day: 4)) == "2018")
// A landed thing stamped ahead of the clock is a bridge's bad timestamp;
// inventing a phrase for it prints nonsense on a row.
check("a future date says nothing", phrase(.init(year: 2022, month: 1, day: 1)) == nil)
check("now itself is today", AddressBookShape.lastPhrase(now, now: now, calendar: cal) == "today")
// And the injected clock is REALLY the clock: a phrase measured against a
// `now` one day later must move a rung. This is the assertion the old
// spelling could not survive under any circumstances, since `isDateInToday`
// would answer the same for both.
check("the phrase follows the `now` it is given",
      AddressBookShape.lastPhrase(cal.date(from: .init(year: 2021, month: 8, day: 22, hour: 9))!,
                                  now: cal.date(from: .init(year: 2021, month: 8, day: 23, hour: 9))!,
                                  calendar: cal) == "yesterday")

// ── The filter chips (prd §498) ─────────────────────────────────────────────
//
// Every failure here renders as a perfectly ordinary list: a chip that hides
// rows it should show, a chip offered over a population that isn't there, or a
// selection that survives its own population and leaves the book empty with
// nothing on screen explaining why.
print("")
print("Filter chips")
typealias Filter = AddressBookShape.BookFilter

// WALLETS TAKES THREE KINDS, and each one is a real population this book holds.
// `unknown` is the sharpest: detection is gated off for devnets (§496), so
// EVERY vibenet account sits in it for life — drop it and the wallet chip hides
// an entire network's accounts while looking perfectly correct.
check("wallets takes a plain wallet", Filter.wallets.matches(kind: "wallet"))
check("wallets takes a smart account", Filter.wallets.matches(kind: "smartAccount"))
check("wallets takes an unchecked address", Filter.wallets.matches(kind: "unknown"))
check("wallets refuses a contract", !Filter.wallets.matches(kind: "contract"))
check("wallets refuses a safe", !Filter.wallets.matches(kind: "safe"))
check("wallets refuses a key", !Filter.wallets.matches(kind: "key"))
check("wallets refuses a contact", !Filter.wallets.matches(kind: "contact"))
check("keys takes only keys", Filter.keys.matches(kind: "key")
      && !Filter.keys.matches(kind: "wallet"))
check("contacts takes only contacts", Filter.contacts.matches(kind: "contact")
      && !Filter.contacts.matches(kind: "social"))
check("social takes only social", Filter.social.matches(kind: "social")
      && !Filter.social.matches(kind: "contact"))
check("all takes everything", Filter.allCases.allSatisfy { Filter.all.matches(kind: $0.rawValue) })
check("only all fails to narrow",
      Filter.allCases.filter { !$0.narrows } == [.all])

// A CHIP WITH NO MEMBERS IS §83'S DEAD CONTROL. On a fresh crypto-only book
// four of the five would be exactly that.
check("all is always offered", AddressBookShape.availableFilters(kinds: []) == [.all])
check("a chip appears only with members",
      AddressBookShape.availableFilters(kinds: ["wallet", "key"]) == [.all, .wallets, .keys])
check("chips keep declaration order",
      AddressBookShape.availableFilters(kinds: ["social", "contact", "wallet"])
        == [.all, .wallets, .contacts, .social])
// A contract is a real entry with NO chip of its own — Contracts and Contacts
// one letter apart is the misread this drops the chip to avoid, and `wallets`
// is the hide-the-machinery filter instead.
check("machinery earns no chip of its own",
      AddressBookShape.availableFilters(kinds: ["contract", "safe"]) == [.all])

// THE ONE TRANSITION THAT CAN STRAND THE SCREEN: the last key is removed while
// `keys` is selected, so the chip leaves the strip while still filtering.
check("a selection survives while its population does",
      AddressBookShape.settledFilter(.keys, kinds: ["wallet", "key"]) == .keys)
check("a selection whose population vanished falls back to all",
      AddressBookShape.settledFilter(.keys, kinds: ["wallet"]) == .all)
check("all always settles as itself",
      AddressBookShape.settledFilter(.all, kinds: []) == .all)

// THE PASTE'S DECK (prd §502). Every failure here draws a perfectly ordinary
// row of faces: a fan that stacks flat, a count that reports what is drawn
// rather than what was read, or a word that claims a write happened while the
// paste is still sitting in the field.
print("")
print("The deck a pasted list makes")
check("the deck stays a deck", (3...8).contains(AddressDeck.shown))
check("the fan cycles rather than clamping",
      AddressDeck.tilt(0) == AddressDeck.tilt(5)
        && AddressDeck.tilt(1) == AddressDeck.tilt(6))
check("neighbours never share an angle",
      (0..<AddressDeck.shown).allSatisfy { AddressDeck.tilt($0) != AddressDeck.tilt($0 + 1) })
// A fan, not a hand held up: past about eight degrees the top card clips the
// one behind it at DS.Face.list and the row reads as a rendering fault.
check("the fan stays subtle",
      (0..<12).allSatisfy { abs(AddressDeck.tilt($0)) <= 8 })
check("a negative index cannot trap",
      (-6...(-1)).allSatisfy { abs(AddressDeck.tilt($0)) <= 8 })
// The tail is COUNTED, never dropped: five faces beside "5" is a silent
// truncation wearing a number.
check("the line reports the total, not the drawn count",
      AddressDeck.line(count: 12) != AddressDeck.line(count: AddressDeck.shown))
check("the line names the number it was given",
      AddressDeck.line(count: 12).contains("12"))
// "read", never "named": nothing has been written while this is on screen.
check("the line claims a reading, not a write",
      AddressDeck.line(count: 12).lowercased().contains("read")
        && !AddressDeck.line(count: 12).lowercased().contains("named"))

// The Watching chip (prd §511). It is offered only over a roster that exists,
// its label carries the cap the deleted block used to state, and `watched`
// travels beside `kind` rather than inside it — §461's ruling in the type
// system, and the reason no row can ever toggle it.
check("the watching chip needs a roster",
      AddressBookShape.availableFilters(kinds: ["wallet"], watching: 0) == [.all, .wallets])
check("the watching chip appears with one watched address",
      AddressBookShape.availableFilters(kinds: ["wallet"], watching: 1)
        == [.all, .watching, .wallets])
check("watching leads the narrowing chips",
      AddressBookShape.availableFilters(kinds: ["social", "wallet"], watching: 2)
        == [.all, .watching, .wallets, .social])
check("watching takes a watched row of any kind",
      Filter.watching.matches(kind: "contract", watched: true))
check("watching refuses an unwatched wallet",
      !Filter.watching.matches(kind: "wallet", watched: false))
check("no other chip reads watched",
      Filter.wallets.matches(kind: "wallet", watched: false)
        && Filter.wallets.matches(kind: "wallet", watched: true))
check("a watching selection whose roster emptied falls back to all",
      AddressBookShape.settledFilter(.watching, kinds: ["wallet"], watching: 0) == .all)
check("the chip label carries the cap",
      AddressBookShape.watchingLabel(3, limit: 5).contains("3")
        && AddressBookShape.watchingLabel(3, limit: 5).contains("5"))

print("")
print("Unwatching — keep the name, or take it with the watch (prd §511)")
// The ordinary case, and the whole reason the fold exists: a bare pasted
// address whose book entry is the placeholder `WalletStore.add` minted.
check("a placeholder name with nothing else leaves with the watch",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true) == false)
check("a name somebody typed keeps the row",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: false))
check("a group keeps an unnamed row",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, groups: ["Work"]))
check("a note keeps an unnamed row",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, note: "paid me in March"))
check("a verified provenance keeps an unnamed row",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, provenance: "Farcaster · @jesse"))
// A network tag records a MEETING, and meetings do not repeat — nothing would
// ever put it back.
check("a network tag keeps an unnamed row",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, networks: ["vibenet"]))
// Blank is not authorship. Without these an empty group name or a whitespace
// note pins an unnamed address in the book forever, with nothing on screen to
// say why.
check("an empty group name is not authorship",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, groups: [""]) == false)
check("a whitespace note is not authorship",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, note: "   ") == false)
check("a whitespace provenance is not authorship",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, provenance: " ") == false)
check("an empty network list is not authorship",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, groups: [], networks: []) == false)
// A fixture only tests the rule it names if it FAILS that rule and passes every
// other one — the standing lesson this repo has paid for four times. The typed
// name must be carrying this on its own.
check("the typed-name case is not carried by some other field",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: false, groups: [],
                                         note: "", provenance: "", networks: []))
// …and each keep-fixture above must be the ONLY thing keeping its row: every
// one of them is a placeholder name with empty everything else.
check("each keeper is alone in its fixture",
      AddressBookShape.unwatchKeepsEntry(isPlaceholderName: true, groups: [], note: "",
                                         provenance: "", networks: []) == false)

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
# The two rungs §448 rewrote. Each renders as an ordinary subline: a row you
# dealt with this morning reading "0 days ago", or yesterday's reading "1 days
# ago" — plural, and wrong twice over.
mutate "today stops being its own rung" \
  'if days == 0 { return String(localized: "today") }' \
  'if days == -1 { return String(localized: "today") }'
mutate "yesterday stops being its own rung" \
  'if days == 1 { return String(localized: "yesterday") }' \
  'if days == -1 { return String(localized: "yesterday") }'
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

# ── The filter chips (prd §498) ─────────────────────────────────────────────
# The Wallets chip hides an entire network. `unknown` is the resting state of
# EVERY vibenet account for life — detection is gated off for devnets (§496) —
# so dropping it from this arm files a whole chain's accounts outside the chip
# that claims to hold the wallets, and the strip looks perfectly correct.
mutate "the wallets chip stops taking unchecked addresses" \
  'case .wallets:  return kind == "wallet" || kind == "smartAccount" || kind == "unknown"' \
  'case .wallets:  return kind == "wallet" || kind == "smartAccount"'
# A smart account is somebody's own wallet made of code (§294) — the whole
# reason that kind exists rather than being filed as a contract.
mutate "the wallets chip stops taking smart accounts" \
  'case .wallets:  return kind == "wallet" || kind == "smartAccount" || kind == "unknown"' \
  'case .wallets:  return kind == "wallet" || kind == "unknown"'
# A chip whose only possible outcome is an empty list — §83's dead control,
# four times over on a fresh book.
mutate "a chip is offered over a population that is not there" \
  '!filter.narrows || kinds.contains(where: { filter.matches(kind: $0) })' \
  'true'
# THE STRANDING: remove the last key while Keys is selected and the chip leaves
# the strip while still filtering, so the book reads as empty with nothing on
# screen to explain it.
mutate "a selection outlives the population it filters" \
  'availableFilters(kinds: kinds, watching: watching).contains(selected) ? selected : .all' \
  'selected'

# THE DECK (prd §502) — each renders as a perfectly ordinary row of faces.
# A fan that clamps: every card past the fifth lies flat on the fifth's angle,
# so a long paste's deck stops looking like a deck halfway along.
mutate "the fan clamps instead of cycling" \
  'return tilts[((index % tilts.count) + tilts.count) % tilts.count]' \
  'return tilts[min(index, tilts.count - 1)]'
# The silent truncation: five faces beside "5 addresses read" on a paste of
# forty, which is indistinguishable from a paste of five that worked.
mutate "the count reports what is drawn rather than what was read" \
  'String(localized: "\(count) addresses read")' \
  'String(localized: "\(min(count, shown)) addresses read")'
# The word that claims the write already happened, while the paste is still
# sitting in the field and `Add all` has not been pressed.
mutate "the deck claims a write it has not made" \
  'String(localized: "\(count) addresses read")' \
  'String(localized: "\(count) addresses named")'
# A fan wide enough that the top card clips the one behind it.
# ── §511: the fold that DELETES a book entry ────────────────────────────────
#
# Every one of these renders as a perfectly ordinary list — the row is simply
# there, or simply not — and the direction that fails silently is the expensive
# one: a name nobody can retype, gone with a watch somebody stopped.
mutate "a typed name stops keeping the row" \
  'if !isPlaceholderName { return true }' \
  'if false { return true }'
mutate "an empty group name counts as authorship" \
  'if (groups ?? []).contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {' \
  'if !(groups ?? []).isEmpty {'
mutate "a whitespace note counts as authorship" \
  'if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }' \
  'if let note, !note.isEmpty { return true }'
mutate "a verified provenance stops keeping the row" \
  'if let provenance, !provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }' \
  'if provenance == nil, provenance != nil {
            return true
        }'
mutate "a network tag stops keeping the row" \
  'if (networks ?? []).contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }' \
  'if (networks ?? []).isEmpty, !(networks ?? []).isEmpty {
            return true
        }'
mutate "the fold keeps everything, so the second gesture is back" \
  'if !isPlaceholderName { return true }' \
  'if true { return true }'

# ── §511: the Watching chip ─────────────────────────────────────────────────
mutate "the Watching chip is offered over an empty roster" \
  'if filter == .watching { return watching > 0 }' \
  'if filter == .watching { return true }'
mutate "watching stops being separate from kind" \
  'case .watching: return watched' \
  'case .watching: return kind == "wallet"'
mutate "the chip label drops the cap" \
  'String(localized: "Watching \(count)/\(limit)")' \
  'String(localized: "Watching \(count)")'

mutate "the fan swings wide enough to clip" \
  'private static let tilts: [Double] = [-6, 3, -2, 5, -4]' \
  'private static let tilts: [Double] = [-26, 13, -2, 25, -14]'

echo ""
echo "address-book-selftest: OK — assertions pass and every mutation is caught."
