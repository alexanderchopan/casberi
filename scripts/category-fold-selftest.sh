#!/bin/zsh
# Casberi category-fold self-test — the ordering and resolution rules behind
# EVERY folded chip in the source strip (prd §351, 2026-08-11), superseding
# markets-fold-selftest.sh, which tested the same mechanism when it lived
# solely in `MarketsRoom` and applied only to the Markets category above a
# floor of 2 present seats:
#
#   Casberi/Casberi/Model/CategoryFold.swift
#     — members/isMember/isCategory  (derived from the catalog's own categories)
#     — fold / foldAll  (which chip a category's seats collapse into, and WHERE
#                         — now UNCONDITIONAL: no floor, one present member folds)
#     — chipLabel        (which chip lights while you stand in a folded seat)
#     — scopes           (a switcher's display order)
#     — landing/remember (where a folded chip reopens, per category)
#
# WHY A HARNESS. Every failure here is a SILENT WRONG ANSWER that renders as a
# perfectly good strip — the class this project keeps paying for:
#
#   • a fold landing at the TAIL instead of in the best-ranked member's slot,
#     so a strip you use constantly quietly reorders itself and the one chip
#     whose position you had learned is now somewhere else (the strip's own
#     "position is half the identity of an icon-only chip" ruling, 2026-07-30);
#   • a category label leaking into `FeedFilter.source`, which is the ONE
#     invariant this whole feature rests on — nothing downstream of the strip
#     may ever see a category name;
#   • `chipLabel` returning the raw source, so standing in a folded seat lights
#     no chip at all and the room reads as unfiltered;
#   • `foldAll` folding only the FIRST category it sees and stopping, which
#     would look identical to a healthy strip for anyone with one category
#     connected (nearly everyone, on day one) and wrong for everyone else;
#   • a stray floor creeping back into `fold` itself, silently un-doing the
#     ruling this whole file exists to enforce ("i want the category chips
#     always" — not "fold when crowded");
#   • `scopes` following the caller's set order instead of the catalog's, so a
#     switcher reshuffles between opens over identical data.
#
# None of these can be caught by `xcodebuild`, by the static audits, or by a
# screen sweep: the strip draws beautifully in every one of them.
#
# `CategoryFold.swift` is compiled WHOLE AND UNMODIFIED against a STUB
# `BridgeCatalog` — it is Foundation-only by design, its only dependency being
# `BridgeCatalog`, and the stub mirrors that file's real signatures
# (`categories`, `offers`, `allOffers`, `category(of:)`, `category(forSource:)`,
# `offer(forSource:)`) exactly rather than a partial subset, since
# `CategoryFold.chipLabel`/`remember` reach `category(forSource:)`, which
# `MarketsRoom`'s old mechanism never called. So every ordering this file
# asserts is the shipped code's own, not a copy that can drift from it. The
# stub spans TWO categories on purpose (Wallet, Markets) — the old harness only
# ever needed one, and the property that makes `foldAll` safe (disjoint
# membership composes) has no way to fail with only one category to fold.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FOLD="Casberi/Casberi/Model/CategoryFold.swift"
ROOM="Casberi/Casberi/Model/MarketsRoom.swift"
MAIN="Casberi/Casberi/Shell/MainSurface.swift"
CHIPS="Casberi/Casberi/Shell/SourceChips.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
SWITCHER="Casberi/Casberi/Screens/CategoryVenueSwitcher.swift"
BROWSE="Casberi/Casberi/Screens/PredictionBrowseSection.swift"
ROOT="Casberi/Casberi/Shell/RootShell.swift"
APP="Casberi/Casberi/CasberiApp.swift"
BOOK="Casberi/Casberi/Screens/PredictionRoomBook.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
RAIL="Casberi/Casberi/Shell/FaceScopeRail.swift"
CHROME="Casberi/Casberi/Shell/ShellChrome.swift"
OVERLAY="Casberi/Casberi/Shell/SourcesOverlay.swift"
TILES="Casberi/Casberi/Screens/WalletFeedTiles.swift"
for f in "$FOLD" "$ROOM" "$MAIN" "$CHIPS" "$FEED" "$SWITCHER" "$BROWSE" "$BOOK" "$CATALOG" "$ROOT" "$APP" "$RAIL" "$CHROME" "$OVERLAY" "$TILES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/category-fold-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Negative guards read a COMMENT-STRIPPED copy (the Obsidian/Cursor lesson,
# earned repeatedly in this tree): this feature's source DOCUMENTS the things
# it must never do ("keeps a category name out of `filter.source`"), so a
# guard grepping raw source fires against the prose explaining the rule it
# protects.
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = re.sub(r'^\s*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<!:)//.*$', '', src, flags=re.M)
print(src)
PY
}
strip_comments "$MAIN"     > "$TMP/main.nc"
strip_comments "$BROWSE"   > "$TMP/browse.nc"
strip_comments "$BOOK"     > "$TMP/book.nc"
strip_comments "$ROOT"     > "$TMP/root.nc"
strip_comments "$APP"      > "$TMP/app.nc"
strip_comments "$CHIPS"    > "$TMP/chips.nc"
strip_comments "$SWITCHER" > "$TMP/switcher.nc"
strip_comments "$FEED"     > "$TMP/feed.nc"
strip_comments "$RAIL"     > "$TMP/rail.nc"
strip_comments "$CHROME"   > "$TMP/chrome.nc"
strip_comments "$OVERLAY"  > "$TMP/overlay.nc"
strip_comments "$TILES"    > "$TMP/tiles.nc"

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove on their own. A perfect `fold` is
# worthless if nothing calls it, and a perfect `chipLabel` is worthless if the
# strip still passes the raw source as its active chip.

grep -q 'CategoryFold.foldAll(' "$TMP/main.nc" \
  || { echo "✗ MainSurface no longer folds every category — chips would stay unfolded per-source"; exit 1; }
grep -qE 'active: (activeChip|chips\.active)' "$TMP/main.nc" \
  || { echo "✗ the strip is passed a raw source again — standing in a folded seat would light NO chip"; exit 1; }
grep -q 'CategoryFold.chipLabel(for: filter.source' "$TMP/main.nc" \
  || { echo "✗ the active chip is no longer resolved through CategoryFold.chipLabel —"; \
       echo "  whatever the strip is handed as 'active' is a raw seat, not a folded label."; exit 1; }

# THE CENTRAL INVARIANT, and the reason this harness earns its slot in
# verify.sh. A category name is a chip LABEL; `FeedFilter.source` must always
# hold a real seat. `go(to:)` is the one place a label becomes a source, and it
# must write the RESOLVED value. Writing `filter.source = label` instead would
# put a literal category name into every `@Query` predicate, every `Corpus`
# check and every deep link — a room that renders empty forever with no error
# anywhere.
grep -q 'filter.source = target' "$TMP/main.nc" \
  || { echo "✗ go(to:) no longer writes the RESOLVED seat — a category label can reach FeedFilter.source"; exit 1; }
grep -q 'CategoryFold.landing(category: label' "$TMP/main.nc" \
  || { echo "✗ a folded chip no longer resolves to a venue — tapping it would route nowhere"; exit 1; }
grep -q 'CategoryFold.isCategory(label)' "$TMP/main.nc" \
  || { echo "✗ go(to:) no longer recognizes a category label — every fold would resolve as a raw (missing) source"; exit 1; }

# THE TWO LEAK SITES, and they are here because both shipped broken in the
# Markets fold's own first cut, one layer down from this generalization.
# `chrome.chipOrder` carries FOLDED labels, and two surfaces consumed it and
# wrote them straight into `FeedFilter.source`:
#
#   • the sources tray (`RootShell`), which is the one screen whose own doc says
#     it "claims to show every source" — fed the folded list it would drop
#     every member AND grow a category cell whose tap opens a room matching
#     nothing, forever, with the folded chip lit as if it had worked;
#   • Mac's ⌘1–⌘9 (`CasberiApp`), same write, same dead room.
#
# Both are invisible to a build and to every static audit, and the second is
# invisible on iOS entirely.
# THE TRAY'S FEED IS CHECKED IN TWO PLACES BECAUSE IT IS PRESENTED THROUGH A
# WRAPPER (2026-08-17). This guard used to grep RootShell for the literal
# `SourcesTray(labels: chrome.sourceOrder`, and then the tray moved behind
# `SourcesOverlay` — so for every commit since, the guard matched nothing and
# the whole self-test went red while the app was perfectly correct. A guard
# that cannot pass is exactly as useless as one that cannot fail, and the
# lesson is the one this tree already wrote down for `roomFigure`: a guarded
# call that moves files takes its guard with it.
#
# Spelled as a POSITIVE on the list that must be used plus a NEGATIVE on the
# list that must not, so it survives the next wrapper: RootShell may never so
# much as name the folded order, whatever it hands it to.
grep -qE 'labels: chrome\.sourceOrder' "$TMP/root.nc" \
  || { echo "✗ the sources tray is no longer fed chrome.sourceOrder — it would drop every folded category's members"; \
       echo "  and offer a category cell that writes a non-source into FeedFilter.source."; exit 1; }
# The negative is on the FEED, not on the name. A first cut banned
# `chrome.chipOrder` from RootShell outright and immediately cried wolf: the
# `-openSources` probe NSLogs that list as its readiness signal, which is a
# diagnostic print and not a leak, and a lint that fires on correct code gets
# turned off within a week. What must never happen is the folded list being
# handed over AS the tray's labels.
if grep -qE 'labels: chrome\.chipOrder' "$TMP/root.nc"; then
  echo "✗ the sources tray is back on chrome.chipOrder — the FOLDED list. That tray claims to show"
  echo "  every source: it would drop every folded category's members AND offer a category cell"
  echo "  that writes a non-source into FeedFilter.source, opening a room matching nothing."
  exit 1
fi
grep -q 'SourcesTray(labels: labels' "$TMP/overlay.nc" \
  || { echo "✗ SourcesOverlay no longer passes its labels straight through to SourcesTray —"; \
       echo "  the order RootShell chose can no longer be trusted to be the order the tray shows."; exit 1; }
grep -q 'CategoryFold.isCategory(label)' "$TMP/app.nc" \
  || { echo "✗ ⌘1–⌘9 no longer resolves a folded label — it would write the category name"; \
       echo "  into FeedFilter.source and open a permanently empty room."; exit 1; }

# The catch-bob and coin-flip key on the chip that is actually SHOWING. Keyed
# on the raw source instead, every arrival celebration for a folded cluster
# fires against a chip that isn't in the strip, and nothing moves — invisible.
grep -q 'chrome.chipCaught(CategoryFold.chipLabel(' "$TMP/main.nc" \
  || { echo "✗ arrivals no longer bob a folded chip — every celebration behind a fold would be silent"; exit 1; }

# Every real source-bearing chip is now a WORD, not a mark (the strip's own
# reversal of its 2026-07-09/07-10 icon-only ruling, scoped to category
# chips). A category chip rendered through the generic icon path would render
# as a missing brand icon — there is no catalog entry named "Work".
grep -qE 'CategoryFold\.isCategory\(label\)' "$TMP/chips.nc" \
  || { echo "✗ SourceChips no longer branches on CategoryFold.isCategory — a folded chip"; \
       echo "  would render through the generic BridgeIcon path and show a missing brand icon."; exit 1; }
grep -q 'categoryCapsule(label' "$TMP/chips.nc" \
  || { echo "✗ a category chip no longer renders as a capsule — back inside \"All\"'s fixed"; \
       echo "  circle, every word shrinks independently to fit and one strip draws four type sizes."; exit 1; }

# THE CHIP IS ITS OWN SHAPE, whatever that shape is (design pass 2026-08-11).
# Both of these read as decoration and are not: a `Circle()` in a capsule's
# frame draws a ring through the MIDDLE of a wide chip and makes only its
# middle pressable — the 2026-07-26 "press it several times" bug wearing a new
# shape, and invisible to every other check here because a circular capsule in
# a SQUARE frame is exactly a circle, so every circle chip looks untouched
# either way.
#
# SCOPED TO THE CHIP'S OWN BODY, and that is not fussiness — the catalogue door
# beside it is a fixed 46pt square and its `contentShape(Circle())` is correct,
# so a file-wide grep fires on the one shape that is right (caught on this
# guard's first run). "All" keeps its `clipShape(Circle())` inside the chip for
# the same reason, which is why the negatives name the two uses that are wrong
# rather than banning the word.
python3 - "$TMP/chips.nc" <<'PY3'
import re, sys
src = open(sys.argv[1]).read()

def between(a, b, what):
    try:
        return src[src.index(a):src.index(b)]
    except ValueError:
        sys.exit("✗ %s not found in SourceChips — this guard is testing nothing" % what)

# PER FUNCTION, not per file — both of the traps below were live on this
# guard's first mutation run and each is the same shape: a check satisfied by
# a DIFFERENT, correct copy of the words elsewhere in the file.
chip = between("private func chip(_ label:", "private func chipAccessibilityLabel", "chip(_:)")
capsule = between("private func categoryCapsule(", "private func chip(_ label:", "categoryCapsule(_:)")

if "contentShape(Circle())" in chip:
    sys.exit("✗ a chip's hit region is a Circle again — the ends of every category\n"
             "  capsule would look pressable and not be.")
# `\s*` spans the newline ON PURPOSE: reverting the ring to `Circle()` leaves
# `.strokeBorder` on its own line, so the single-line spelling of this check
# passed the very mutation it exists to catch.
if re.search(r"Circle\(\)\s*\.strokeBorder", chip):
    sys.exit("✗ the chip ring is a Circle again — it would draw through the middle of a\n"
             "  capsule, and the sliding active ring would have to swap shape mid-flight.")
if "contentShape(Capsule(style: .circular))" not in chip:
    sys.exit("✗ the chip's hit region is no longer the circular capsule both shapes share.")

# A CATEGORY CHIP IS A WORD — no brand mark inside the capsule (user ruling
# 2026-08-11, "honestly i think it just looks confusing for those logos to be in
# the category chips"). The landing mark shipped hours earlier the same day and
# is DELETED, not deprecated: it drew only where it said something (≥2 present
# members, phone only), so it appeared on some chips and not others and cost the
# strip the one grammar that makes the fold legible. Scoped to the capsule's own
# body — `chip(_:)` beside it draws `BridgeIcon` correctly for the uncategorized
# fallback, and the two fixed doors are marks by design, so a file-wide grep
# would fire on the uses that are right.
if "BridgeIcon" in capsule:
    sys.exit("✗ a brand mark is back inside a category capsule — the row would read as words\n"
             "  for some categories and word-plus-logo for others, which is the treatment\n"
             "  2026-08-11 removed. Wallet-as-an-exception was offered and declined too.")
if "markSize" in capsule:
    sys.exit("✗ the landing mark's metric is back in the capsule — see above.")

# "opens on X" must be suppressed when X IS the chip's own word (prd §354).
# Wallet's category name and its anchor member are the same string, so without
# this VoiceOver says "Wallet, opens on Wallet: Wallet, Peer, …" — a sentence
# that reads as a bug to the one person who cannot see the strip to check, and
# the only surface where this feature's landing is spoken at all. Scoped to
# the function that speaks it.
speech = between("private func chipAccessibilityLabel", "\n}", "chipAccessibilityLabel(...)")
if "opens on" not in speech:
    sys.exit("✗ the chip no longer speaks where it opens — the fold's landing would be\n"
             "  invisible AND unspoken, which for a folded category is no way to know at all.")
if not re.search(r"opens\s*!=\s*label", speech):
    sys.exit("✗ the 'opens on' phrase is no longer suppressed when the landing is the\n"
             "  category's own name — VoiceOver would say \"Wallet, opens on Wallet\" (prd §354).")
PY3

# The mark's INPUT is gone from the call site too, or the next pass re-adds the
# view and finds the wiring still there waiting for it.
grep -q 'activeSource' "$TMP/main.nc" \
  && { echo "✗ MainSurface still hands the strip a live source for the landing mark, which no"; \
       echo "  longer exists — SourceChips.activeSource was deleted with it (2026-08-11)."; exit 1; }
grep -q 'activeSource' "$TMP/chips.nc" \
  && { echo "✗ SourceChips still carries activeSource — its only reader was the landing mark."; exit 1; }

# The switcher is where the folded chip's dashed ring RESOLVES to a seat. Without
# this the ring says "something in here needs you" and the tap it invites arrives
# at a row of identical capsules (prd §351's own promise, unkept until 2026-08-11).
grep -q 'DS.attention' "$TMP/switcher.nc" \
  || { echo "✗ the venue switcher no longer marks a broken seat — the folded chip's dashed"; \
       echo "  ring would name nothing, and only VoiceOver could say which seat it meant."; exit 1; }
grep -q 'BridgeCatalog.offer(forSource: venue)' "$TMP/switcher.nc" \
  || { echo "✗ the switcher resolves attention by raw name — the alias family (Privacy Pools"; \
       echo "  against 0xBow Privacy Pools) would silently never light, which is the whole"; \
       echo "  reason the strip and the tray both resolve through the catalog."; exit 1; }
# The mount moved from FeedScreen to MainSurface on 2026-08-11 (prd §357):
# FeedScreen carries `.id(filter.source)` under a move transition, so a
# switcher mounted THERE is destroyed by the very tap it exists to serve — its
# matched-geometry selection fill could never once travel, because a venue pick
# is the only event that changes `active` and the pick killed the namespace.
grep -q 'CategoryVenueSwitcher(' "$MAIN" \
  || { echo "✗ MainSurface no longer mounts the generic venue switcher — a folded category seat has no way out"; exit 1; }

# §356's DISPLAY-LABEL rule, kept through §358's icon-only switcher. The visible
# half of it is gone — the switcher draws marks now, so there is no `Text` to
# check (user ruling: "for the rooms why not just use ONLY the icon") — but the
# half that could BREAK something is untouched and still guarded below: the seat
# is what `FeedFilter.source` takes, so passing a display label to `onPick` would
# write "Wallets" into the filter, which matches no landed Thing, no Shape case
# and no deep link, and empties the room it just opened.
#
# The switcher must still NAME each venue for anyone who can't read the mark —
# with the word gone this is the only naming left, so it is a harder requirement
# than it was, not a softer one.
grep -q 'accessibilityLabel' "$TMP/switcher.nc" \
  || { echo "✗ the icon-only venue switcher no longer names its venues to VoiceOver — with the"; \
       echo "  words gone (§358) this is the ONLY thing naming a seat in this control."; exit 1; }
grep -qE 'onPick\(venueLabel|onPick\(CategoryFold\.venueLabel' "$TMP/switcher.nc" \
  && { echo "✗ the switcher hands a DISPLAY LABEL back to its caller — \"Wallets\" would land in"; \
       echo "  FeedFilter.source, which no Thing, Shape or deep link answers to (§356)."; exit 1; }

# THE TWO ROWS OF CIRCLES ARE ONE SIZE, AND THE SLOT IS THE TOUCH FLOOR (prd
# §540, 2026-09-01). Both halves are guarded because both fail INVISIBLY and
# neither is reachable by `xcodebuild` or a screen sweep.
#
# §483 pinned this chip's SEAT to `DS.Face.list` and left the MARK at `row`, so
# a 26pt mark drew above the rail's full-bleed 36pt silhouettes — matching
# frames, mismatched ink, which is what "the icons look smaller than the
# silhouette rail" turned out to be. The mark is sized off the FACE ramp (never
# `DS.Mark`) because `face-ramp-audit.py` holds circular marks to it, and it must
# be the SAME rung `FaceScopeRail` draws or the two rows disagree again.
#
# The seat is separately load-bearing: it is this chip's whole tap target, it was
# 36 for its entire life, and it is the only way out of a folded category seat.
# `accessibility-audit.py` check 3 covers it now (§540 widened it past
# `Image(systemName:)`), so this guard is belt to that check's braces — worth
# keeping BOTH, since that audit reads a literal or a named token and a future
# refactor that hands the size in as a parameter goes silent there while this
# still names the file.
grep -q 'BridgeIcon(name: venue, size: markSize, circular: true)' "$TMP/switcher.nc" \
  || { echo "✗ the venue switcher's mark is no longer the full-bleed markSize —"; \
       echo "  it draws directly above FaceScopeRail's faces, so a mark inset inside"; \
       echo "  its seat reads as two rows of circles at two sizes (§540/§483)."; exit 1; }
grep -qE 'markSize: CGFloat \{ compact \? DS\.Face\.row : DS\.Face\.list \}' "$TMP/switcher.nc" \
  || { echo "✗ the venue switcher's mark no longer folds on FaceScopeRail.faceSize's own two"; \
       echo "  rungs — the rail below folds 36→26 and a pinned mark row above it puts 36"; \
       echo "  over 26 on every scroll, which is §483's complaint in the folded state."; exit 1; }
# The FOLD SIGNAL is cross-file, so it is guarded where it is passed. Two
# controls stacked on one screen folding on two different expressions is the
# drift this whole guard block exists for, one level up from the sizes.
# ANCHORED TO THE CALL, never to the file. Both face rails already pass this
# exact expression, so a bare file-wide grep is satisfied by THEIR copies and
# would stay green with the switcher's own argument deleted — a guard proving
# the words appear rather than that the condition holds, which is the defect
# `cursor-selftest.sh` records against its own first cut.
awk '/CategoryVenueSwitcher\(/,/\{ venue in/' "$TMP/main.nc" | grep -q 'compact: chrome.minimized && !showsRail' \
  || { echo "✗ the venue switcher is no longer handed the shell's fold state, or is handed a"; \
       echo "  different expression from the face rails beneath it (§540). Both rails take"; \
       echo "  'chrome.minimized && !showsRail'; a switcher on anything else steps apart"; \
       echo "  from the row under it on exactly the scrolls nobody screenshots."; exit 1; }
# ...and the SEAT must NOT fold with it. The slot is the tap target, so a fold
# that shrank it would buy back space by dropping the control under the touch
# floor — `dsTapTarget`'s ruling run backwards, and the defect §540 just fixed.
# The SEAT must not fold with the mark, and its size is spelled LITERALLY at the
# frame. Both halves matter: a folding slot drops the chip under the touch floor
# on every scroll, and hoisting the floor into a computed property blinds
# `accessibility-audit.py` check 3 to this very chip — which is what happened
# while §540 was being written, minutes after that check was widened to catch it.
grep -q 'frame(width: DS.Hit.min, height: DS.Hit.min)' "$TMP/switcher.nc" \
  || { echo "✗ the venue switcher's chip no longer claims a literal DS.Hit.min footprint —"; \
       echo "  its whole slot IS the tap target (under the floor from §351 to §540), and a"; \
       echo "  size lifted into a property also goes invisible to accessibility check 3."; exit 1; }
# And the annulus that selection lives in cannot be closed by 'tidying' the
# seat down onto the mark: a full-bleed mark covers a fill drawn behind it, so
# a seat equal to the mark silently deletes the active state while the control
# still looks and behaves correctly in every still frame. §540 refused a
# selection RING for this control (attention is already a ring, and the two
# would collide on an active-and-broken seat), so the fill is the only cue
# there is.
grep -q 'Capsule(style: .continuous).fill(DS.tint.opacity(' "$TMP/switcher.nc" \
  || { echo "✗ the venue switcher's SELECTION FILL is gone — with the mark full-bleed the"; \
       echo "  fill reads in the annulus between it and the DS.Hit.min seat, and it is the"; \
       echo "  only selection cue this control has (§540: a ring would collide with"; \
       echo "  attention, which is already a dashed ring on the same capsule)."; exit 1; }
# The scope must live on the shell, or it dies with the room. `MainSurface`
# gives FeedScreen `.id(filter.source)`, so `@State` here is destroyed on every
# room change — which is the bug §356 exists to fix.
grep -q 'var walletScope' "Casberi/Casberi/Shell/ShellChrome.swift" \
  || { echo "✗ ShellChrome.walletScope is gone — the wallet scope would return to @State on a"; \
       echo "  screen carrying .id(filter.source), so it dies on every room change (§356)."; exit 1; }
grep -qE '@State private var selectedWallet' "$FEED" \
  && { echo "✗ selectedWallet is @State on FeedScreen again — .id(filter.source) destroys it on"; \
       echo "  every room change, so the scope silently evaporates when you leave the room."; exit 1; }
# The scope filter must be gated on the ROOM, or a scope set in the balance
# room reaches Social and Work, where every walletAddress is nil — so those
# rooms render EMPTY with nothing on screen able to explain why.
grep -q 'guard roomTakesWalletScope' "$FEED" \
  || { echo "✗ walletScopeAllows no longer gates on the room — a live wallet scope would empty"; \
       echo "  every non-wallet room, since their rows carry no walletAddress (§356)."; exit 1; }
# PINNED, not a List section — `walletSwitcherBar`'s 2026-07-20 ruling, kept
# through the §357 move: the switcher and the wallet rail now ride
# `MainSurface.topInset` (itself the shell's one top `safeAreaInset`), via
# `roomControls`. As a section either would scroll away with the room it
# scopes, and its glass would blur nothing.
# **`walletScopeRail` IS `socialScopeRail` SINCE §483** (2026-08-27). The rail
# stopped being Wallet's alone when the room became seven scopes and vibenet
# took the same chassis, so it was renamed for what it is. The RULING is
# untouched — both room controls still live in `roomControls`, which is the
# whole of what §357 asked — and this guard was naming the identifier rather
# than the rule. Following a rename, not loosening a check.
# **AMENDED FOR §483 (prd §495).** This demanded BOTH room controls in
# `roomControls`, which was §357's ruling and is no longer the arrangement:
# §483 moved the wallet rail and its switcher OUT, into the room's own content
# under the crown ("we need to have those toggles be below the sparkline", "we
# cannot have four rows of chips"), and `wallet-section-selftest` now DENIES
# their presence in `roomControls` — so the two harnesses were asserting
# opposite things and this one had been red for several commits.
#
# What survives from §357 is the part that was never about the wallet: the
# CATEGORY switcher is shell chrome, it scopes which room you are in rather
# than what a room shows, and it must stay pinned. The social rail sits beside
# it for the same reason.
grep -q 'roomControls' "$MAIN" \
  && grep -qE '^\s*categorySwitcher$' "$MAIN" \
  && grep -qE '^\s*socialScopeRail$' "$MAIN" \
  || { echo "✗ MainSurface.roomControls no longer carries both room controls — a switcher or"; \
       echo "  rail mounted anywhere else either scrolls away or (back on FeedScreen) is"; \
       echo "  destroyed by every venue change, the §357 bug returned."; exit 1; }
# …and NOT on FeedScreen, which is the regression §357 exists to prevent: any
# top inset there is inside the `.id(filter.source)` subtree, so it travels
# with the room and dies on every move it commands. (`walletSwitcherBar` and
# `categorySwitcher` were both exactly this until 2026-08-11.)
# Comment-stripped, because the file DOCUMENTS the move by naming the very
# modifier it must no longer carry — a guard grepping raw source fires on the
# prose explaining it (the Obsidian/Cursor lesson, earned again here).
grep -qE 'safeAreaInset\(edge: \.top' "$TMP/feed.nc" \
  && { echo "✗ FeedScreen grew a top safeAreaInset again — chrome pinned inside the"; \
       echo "  .id(filter.source) subtree is destroyed and re-slid on every room change,"; \
       echo "  which is the §357 bug (a switcher torn down by the tap it serves)."; exit 1; }

# --- the Mac half of both room controls (prd §360, 2026-08-11) --------------
# These four are POINTER and KEYBOARD rules. None of them can fail on a phone,
# none shows up in a screenshot taken on one, and the app is shipped to Mac
# TestFlight from the same tree — which is exactly how the wallet rail landed
# (2026-08-11) as the one shell control with no hover state and no tooltip
# while every sibling had carried both since 2026-08-01.

# A control a cursor can rest on must answer. `dsHover` is folded into
# `dsListCardRow` for lists; anything that isn't a List row has to say it,
# which is why this is a per-control check and not a global one.
grep -q 'dsHover()' "$TMP/rail.nc" \
  || { echo "✗ the wallet rail has no hover state — on Mac a cursor crossing five faces and"; \
       echo "  a + gets no response from any of them, which reads as a dead app (the same"; \
       echo "  argument dsListCardRow's own note makes for the 27 rows it covers)."; exit 1; }
# The wallet rail draws NO caption at all since §450, so on Mac the tooltip is
# the only thing a slot says before you click it — and on the social rail, where
# the caption survives, it is still the only place a full address or bio fits.
grep -q 'dsTooltip' "$TMP/rail.nc" \
  || { echo "✗ the face rail names nothing on hover — the wallet rail captions nothing at"; \
       echo "  all (§450) and the social caption is lineLimit(1) in a 66pt slot, so the"; \
       echo "  tooltip is the only thing that can tell two faces apart without clicking one."; exit 1; }

# --- §450: the wallet rail's names moved into the room ----------------------
# Four halves of one ruling, in four files. Every failure below renders as a
# perfectly ordinary screen — a rail of unlabelled circles with no name anywhere,
# or a name that no longer follows the face you picked — which is why none of it
# can be caught by a build, a sweep or a screenshot.

# The flag is the ruling. It must be ON for wallets and OFF for people: a social
# roster runs to dozens of faces, has no crown card under it to name a pick, and
# unlabelled avatars there are §362's identicon problem at scale.
# Windowed between the two properties rather than by a line count: strip_comments
# BLANKS a comment line rather than deleting it, so an `-A<n>` window is really a
# count of the prose above the thing being checked (this guard failed on its own
# first run for exactly that reason).
# **§450 WAS OVERTURNED BY USE (prd §495).** It ruled the wallet rail must NOT
# caption its faces — a 66pt slot at label12 fits about nine characters, so
# `accountless.eth` read `accountle…` while the crown card below had room for
# the whole name. §483 gave the rail captions anyway, and the user has since
# refined their FORMAT rather than questioning their existence ("if it is an
# address then only has last four digits no ellipsis"), which settles it: the
# captions stay.
#
# So the check is no longer "must not caption". It is that the decision is
# EXPLICIT — `namesInRoom` is passed at the call site rather than defaulted —
# because the parameter's default is `false` and a rail that captions by
# omission is a rail nobody decided about. §450's real concern, truncation,
# is carried by the caption itself being short (an address is four characters
# now) and by `FaceScopeRail`'s own line limit.
# **READ INTO A VARIABLE, NEVER `sed | grep -q`.** Under `pipefail` that is a
# race this repo has already paid for once: `grep -q` exits 0 the instant it
# matches and closes the pipe, `sed` takes SIGPIPE and exits 141, and pipefail
# makes 141 the PIPELINE's status — so a SUCCESSFUL match fails the check. It
# reproduced here immediately and deterministically, because the match is on
# the first few lines of a long range.
railBlock=$(sed -n '/private var walletScopeRailSection/,/private var walletSectionSwitcherSection/p' "$TMP/feed.nc")
[[ "$railBlock" == *"namesInRoom:"* ]] \
  || { echo "✗ the wallet rail's caption decision is implicit again (§450 → §495) — the"; \
       echo "  parameter defaults to false, so a rail that captions by OMISSION is a rail"; \
       echo "  nobody decided about. §450 banned these captions outright; §483 shipped them"; \
       echo "  and the user then refined their format rather than questioning them, so what"; \
       echo "  is enforced now is that the choice is made on purpose."; exit 1; }
socialBlock=$(sed -n '/private var socialScopeRail/,/private var socialAccounts/p' "$TMP/main.nc")
[[ "$socialBlock" == *"namesInRoom"* ]] \
  && { echo "✗ the SOCIAL rail has taken §450's flag. It has no crown card to name a pick"; \
       echo "  in and its roster runs to dozens, so this turns a Farcaster room into forty"; \
       echo "  unlabelled avatars — §362's identicon problem, at scale."; exit 1; }

# Undrawn is not unspoken. With no caption a slot's only content is an identicon,
# and `dsTooltip` is Mac-only by its own ruling — so without this VoiceOver reads
# five unlabelled buttons.
grep -q 'accessibilityLabel(Text(item.caption))' "$TMP/rail.nc" \
  || { echo "✗ a face-rail slot no longer speaks its caption. With §450 the wallet rail"; \
       echo "  draws no words at all and dsTooltip is Mac-only (on touch it becomes a HINT),"; \
       echo "  so every watched wallet becomes an unlabelled button to VoiceOver."; exit 1; }

# The ring carries selection ONLY where `ringed` has nothing else to say. Gated
# on the adapter's flag, never per-item: a rail that meant both at once would be
# a mark with two senses and no way to tell them apart.
grep -qE 'item\.ringed \|\| \(namesInRoom && isOn\)' "$TMP/rail.nc" \
  || { echo "✗ FaceScopeRail's ring is no longer the §450 pair. Dropping the caption took"; \
       echo "  selection's semibold with it, leaving restOpacity's gentle 0.7 to carry the"; \
       echo "  pick alone — and ungated, a social 'posted since you looked' ring and a"; \
       echo "  'this is the one you picked' ring become one mark meaning two things."; exit 1; }

# The other half: the crown card must actually NAME the scope, through the rail's
# own function. Two derivations of "what is this wallet called" is how the ringed
# face and the name a centimetre below it end up disagreeing.
grep -q 'WalletScopeRail.caption(for:' "$TMP/feed.nc" \
  && grep -q 'captionAddress: selectedWallet' "$TMP/feed.nc" \
  || { echo "✗ the wallet crown no longer names the scoped wallet (§450) — so the rail"; \
       echo "  captions nothing, the card says 'Balance', and the app has no place at all"; \
       echo "  that says which wallet you are looking at."; exit 1; }
grep -q 'if let captionAddress' "$TMP/tiles.nc" \
  || { echo "✗ WalletBalanceHeadline no longer draws the scoped wallet's face beside its"; \
       echo "  name (§450) — the badge is what ties the ringed face in the rail above to"; \
       echo "  the name below it, so without it the ring reads as a coincidence."; exit 1; }

# An unnamed wallet gets `shortAddress` and NOTHING fuller, though the card has
# the room. `AddressSafety.displayForm` keys on that function on purpose — the
# display form IS the address-poisoning surface — so a second, longer truncation
# would be the one display in the app the lookalike check cannot see.
sed -n '/static func caption(for address/,/^}/p' "$TMP/rail.nc" | grep -qE 'prefix\(' \
  && { echo "✗ the scoped caption has grown a head-and-tail address form (§450). That"; \
       echo "  spelling was retired 2026-08-12 for naming nobody, and AddressSafety"; \
       echo "  .displayForm keys on shortAddress deliberately — a second truncation here is"; \
       echo "  one the poisoning lookalike check cannot see, on the screen holding money."; exit 1; }
sed -n '/static func caption(for address/,/^}/p' "$TMP/rail.nc" | grep -q 'isAutoName' \
  || { echo "✗ the scoped caption no longer tests isAutoName — add/addBulk file a bare"; \
       echo "  address under its own short form as a display fallback, so the card would"; \
       echo "  read '…4f4f · …4f4f' for every wallet nobody has named."; exit 1; }

# THE COHESION ITSELF, made mechanical (prd §362, 2026-08-11). The wallet rail
# and the social rail spent months as two controls that looked alike and behaved
# differently — 36pt vs 56pt, an "All" slot on one, one pinned as chrome and one
# scrolling away with the room — because each was built for its own room and
# nothing held them to each other. The user's ruling is that sameness IS the
# simplification ("the app has a lot of superpowers… the best way to [make it
# simple] is things being the same"), so the guarantee is structural: ONE view
# type, and the per-room parts are pure adapters with no view code to drift.
#
# None of this can be caught by a build or a screen sweep — two rails that have
# diverged again render perfectly, and the cost is only ever paid by somebody
# learning the app twice.
grep -q 'struct FaceScopeRail: View' "$TMP/rail.nc" \
  || { echo "✗ the shared face rail is gone — wallets and people are drawing their own"; \
       echo "  rows of faces again, which is the exact drift §362 collapsed (36pt vs 56pt,"; \
       echo "  an All slot on one, one pinned and one scrolling)."; exit 1; }
for a in WalletScopeRail SocialScopeRail; do
  grep -qE "enum $a" "$TMP/rail.nc" \
    || { echo "✗ $a is no longer a pure adapter on the shared rail — if it has grown view"; \
         echo "  code of its own the two rails can diverge again silently."; exit 1; }
done
# An UNSCOPED rail may not dim anything (2026-08-13, user: "the avatars on
# socials that aren't selected but followed are very dim. same for wallet").
# Both slot builders take their rest weight from `restOpacity`, and that has to
# be gated on `scope == nil` — the rail's resting state is "All", where nothing
# is `isOn`, so a flat `isOn ? 1 : <dim>` recedes the ENTIRE roster in the state
# the control spends nearly all its life in, saying "excluded" over faces that
# are all included. Checked in both directions: the gate must exist, and no slot
# may carry a literal opacity ternary of its own again.
#
# Invisible to every other check here — it builds, it sweeps, it screenshots,
# and each still frame looks like a deliberate style.
grep -qE 'var restOpacity: Double \{ scope == nil \? 1 :' "$TMP/rail.nc" \
  || { echo "✗ FaceScopeRail.restOpacity is gone or no longer gated on \`scope == nil\` — an"; \
       echo "  unscoped rail is the DEFAULT state (All), so an ungated dim greys every"; \
       echo "  followed face and every watched wallet the moment the room opens."; exit 1; }
grep -cE '\.opacity\(isOn \? 1 : restOpacity\)' "$TMP/rail.nc" | grep -q '^2$' \
  || { echo "✗ the All slot and the face slot no longer BOTH take their rest weight from"; \
       echo "  restOpacity — one of them has a literal back, so the two halves of one rail"; \
       echo "  can fade to different depths."; exit 1; }
grep -qE '\.opacity\(isOn \? 1 : 0\.[0-9]' "$TMP/rail.nc" \
  && { echo "✗ a face-rail slot dims to a literal again. 0.4 was the shipped value and 40%"; \
       echo "  of an avatar is a portrait behind frosting — the same 'a mark someone"; \
       echo "  recognizes stays opaque' rule that keeps glass off these faces. Recession is"; \
       echo "  0.7, which is what scrollTransition already fades an edge slot to (one"; \
       echo "  recessed weight, and the two can no longer compound to 0.28)."; exit 1; }
# Both rails must be MOUNTED — but no longer in the same place, and that split
# is §483's ruling rather than drift (prd §495).
#
# §357 put both in `roomControls` on the principle that a filter you are
# standing in must not scroll away. §483 moved the WALLET rail into the room's
# own content, under the crown, because pinning it made a fourth row of chips
# and pushed the crown to about 45% down the screen — a real cost against a
# real one, and the user ruled. The SOCIAL rail stays pinned: it has no crown
# above it to compete with.
#
# So each is checked where its own ruling put it. The scroll-away cost §357
# named is real and is now carried by §495's return-to-head on a scope change,
# with pinning left as its own open ruling rather than assumed here.
socialRail=$(grep -c 'socialScopeRail' "$TMP/main.nc" || true)
walletRail=$(grep -c 'walletScopeRailSection' "$TMP/feed.nc" || true)
[[ "$socialRail" -gt 0 ]] \
  || { echo "✗ the social rail is gone from MainSurface.roomControls — it is pinned chrome"; \
       echo "  (§357/§362): a person filter you are standing in that scrolls away is a"; \
       echo "  filter with no visible way out."; exit 1; }
[[ "$walletRail" -gt 0 ]] \
  || { echo "✗ the wallet rail is gone from the room's content — §483 moved it OUT of"; \
       echo "  roomControls deliberately ('we cannot have four rows of chips'), so its home"; \
       echo "  is FeedScreen's walletScopeRailSection, not the shell."; exit 1; }
# The social scope must die with the room. A handle belongs to ONE network, so a
# Farcaster handle carried into Bluesky matches no row and paints an empty feed
# with nothing on screen able to explain why.
grep -q 'chrome.personScope = nil' "$TMP/main.nc" \
  || { echo "✗ the person scope is no longer cleared on a source change — carried into"; \
       echo "  another network's room it matches nothing and the feed renders empty (§362)."; exit 1; }
# `SourceChips.folds` is `minimized && axis == .horizontal`, i.e. the strip
# refuses to fold wherever it is a rail. The wallet rail sits directly under it
# and must decline on the same surface, or it is the single piece of shell
# chrome that resizes on scroll on Mac — one control twitching, not a system
# compressing.
grep -qE 'compact: chrome\.minimized && !showsRail' "$TMP/main.nc" \
  || { echo "✗ the wallet rail's compression is no longer gated on !showsRail — it would"; \
       echo "  compress on Mac and iPad, where SourceChips.folds explicitly declines"; \
       echo "  (folds = minimized && axis == .horizontal). Chrome that resizes alone reads"; \
       echo "  as a glitch; the surface wide enough to wear a rail is not short of height."; exit 1; }
# A key equivalent that outlives the control it drives is a dead control nobody
# can even see to distrust — `roomControls` is mounted INSIDE the
# NavigationStack precisely so a pushed room covers it (§357).
# Checked as its DEFINITION, not as the string appearing somewhere: a first cut
# grepped the file for `shellChromeClear` and passed happily against a renamed
# property, because `canWalk`'s own use of it still matched. What has to hold is
# that all THREE flags are still in the expression — dropping `walkInPushedRoom`
# alone compiles, reads fine, and silently hands the shortcuts back to a pushed
# room, which is the exact hole §357 closed.
# `grep … >/dev/null` and not `grep -q` as the TAIL of a pipeline: under this
# script's `set -o pipefail`, `-q` exits at the first match and the upstream
# grep dies of SIGPIPE (141), which pipefail reports as a failed check even
# though the pattern was FOUND. Timing-dependent on whether the upstream has
# finished writing, so it presents as an intermittent failure in correct code
# — this file flaked twice inside full verify runs while passing standalone.
grep -A2 'var shellChromeClear' "$TMP/chrome.nc" \
  | grep '!walkModalOpen && !walkSheetOpen && !walkInPushedRoom' >/dev/null \
  || { echo "✗ ShellChrome.shellChromeClear no longer tests all three flags — the room-control"; \
       echo "  shortcuts would keep driving a switcher and a rail that a pushed room, a raised"; \
       echo "  agent or an open sheet has covered (§357/§360). It is also canWalk's gate, so"; \
       echo "  a flag dropped here takes ↑/↓/Return with it."; exit 1; }
grep -c 'shellChromeClear' "$TMP/app.nc" | grep -qE '^[2-9]|^[0-9]{2}' \
  || { echo "✗ fewer than two menu commands gate on shellChromeClear — both the venue pair"; \
       echo "  (⌘⇧[ / ⌘⇧]) and the wallet run (⌥1–⌥6) must, or one of them drives a control"; \
       echo "  that is not on screen (§360)."; exit 1; }

# --- glassEffectID may never decorate a shape with no glass (prd §360) -------
# `glassEffectID` is a NO-OP on a view carrying no `glassEffect` — it does not
# warn, it does not draw differently in a still frame, it simply removes the
# travel of whatever it replaced. This tree has now paid for that twice in one
# day: `WordChipFill` swapped it in for `matchedGeometryEffect`, lost the travel,
# and reverted after frame-stepping at 60fps ("swapping it in silently deleted
# the travel it replaced" — 0c93a6c); `CategoryVenueSwitcher` was left on the
# losing side of that same finding, so its selection fill teleported on iOS 26
# while its own pre-26 fallback animated correctly. A rule that costs a session
# an afternoon twice is a rule that belongs in a script.
#
# Checked per FILE rather than per call — pairing a `glassEffectID` with the
# shape it decorates means parsing Swift, and a file that reaches for the id
# without ever applying `glassEffect`/`dsGlassBlob` is the finding either way.
for gf in "$TMP"/*.nc; do
  grep -q 'glassEffectID' "$gf" || continue
  grep -qE 'glassEffect\(|dsGlassBlob\(' "$gf" \
    || { echo "✗ $(basename "$gf" .nc) uses glassEffectID with no glassEffect anywhere in the file."; \
         echo "  That decoration is INERT on a shape with no glass — it draws identically in"; \
         echo "  every still frame and silently deletes the travel it replaced (§360). Use"; \
         echo "  matchedGeometryEffect, which is what beat it on a frame-stepped 60fps"; \
         echo "  recording, or give the shape real glass."; exit 1; }
done

# --- the rail's column must be reserved for everything (prd §361/§371) ------
# §361 gave `topInset` its OWN `.padding(.leading, railWidth)` on the premise
# that "the stack's CONTENT respects the leading safe area; a top inset view
# does not". **The first half of that was wrong, and it was measured wrong on
# 2026-08-12**: the feed's `safeAreaInsets.leading` reads 0 at every window
# width, so NOTHING respected the rail — the band was simply the one thing
# paying for it by hand. What hid it is that the feed is capped at
# `readingMaxWidth` and centred, which clears an 88pt rail only while the space
# being centred in exceeds 876pt; the detail pane takes 400–560pt off that, so
# at the shipped default 1120pt Mac window every row title was drawn under the
# chips with its first characters cut ("Calendar" → "alendar").
#
# The reservation moved to the stack's content (`dsRailColumn`), which covers
# the band, the feed and every pushed room at once. So the guard inverts: the
# band must NOT pad itself any more (that would inset it twice, putting it
# 88pt right of the cards it sits above), and the pager and the pushed rooms
# must both reserve. User ruling 2026-08-12: "the rail should be preserved and
# content not go behind it."
#
# Scoped to `topInset`'s own body (up to `bandContent`, the property it was
# split into) rather than the whole file — `dsAdaptiveContentWidth()` is the
# app's general column cap and appears on plenty of screens, so a file-wide grep
# would pass while this band had lost it. A fixed `-A<n>` window does NOT work
# here: `strip_comments` blanks comment lines rather than deleting them, so the
# doc block above the construction still counts toward the window.
awk '/private var topInset/,/private var bandContent/' "$TMP/main.nc" > "$TMP/topinset.nc"
grep -qE 'padding\(\.leading, showsRail \? PadLayout\.railWidth' "$TMP/topinset.nc" \
  && { echo "✗ MainSurface.topInset reserves the rail AGAIN, on top of the pager's own"; \
       echo "  dsRailColumn — the band would be inset twice and sit 88pt right of every"; \
       echo "  card beneath it. One reservation, at the stack's content (§371)."; exit 1; }
# Both halves of that one reservation: the pager (so the feed, the band and the
# pane all sit beside the rail) and the pushed rooms (Apps, Settings and every
# bridge form are drawn under the rail too — it lives outside the stack
# precisely so it survives a push).
(( $(grep -c 'dsRailColumn(showsRail)' "$TMP/main.nc") >= 2 )) \
  || { echo "✗ MainSurface no longer reserves the rail's column for both the pager and its"; \
       echo "  pushed rooms — content draws under the chips wherever the window is under"; \
       echo "  ~876pt of feed column, which on Mac is every size a pane fits in (§371)."; exit 1; }
# A PADDING, never a safe-area inset — that distinction IS the finding. The
# rail is already drawn by `.safeAreaInset(edge: .leading)` on the stack and
# that inset reaches nothing inside it; reserving the column the same way
# would compile, read as correct, and change no pixel.
awk '/func dsRailColumn/,/^}/' "Casberi/Casberi/Design/PadLayout.swift" | grep 'padding(.leading' >/dev/null \
  || { echo "✗ dsRailColumn no longer reserves with a padding — a safeAreaInset applied to"; \
       echo "  the stack does not reach its content (measured: leading reads 0 at every"; \
       echo "  width), so the column would silently stop being reserved (§371)."; exit 1; }
# PADDING, never a spacer view. `Color.clear.frame(width:)` leaves the height
# unbounded, so the spacer grows to the whole window and the top inset swallows
# the surface — the feed renders NOTHING and the banner floats in the middle of
# an empty canvas. That cut built cleanly and passed every static check; only the
# Mac renderer showed it (§361).
grep -q 'Color.clear.frame(width:' "$TMP/topinset.nc" \
  && { echo "✗ MainSurface.topInset reserves the rail with a spacer view again — Color fills"; \
       echo "  what it is offered, and constraining only its width leaves it full-height, so"; \
       echo "  the inset takes the whole window and the feed disappears (§361)."; exit 1; }
# The other half of the same bug: without the cap the band runs PAST the feed
# column it sits above (the banner's "Exit" hung ~100pt beyond the card below
# it). It must be the feed's OWN modifier, not a hand-rolled width, or the two
# can agree today and drift apart the next time the column changes.
grep -q 'PadLayout.readingMaxWidth' "$TMP/topinset.nc" \
  || { echo "✗ MainSurface.topInset no longer wears the reading cap — the band runs wider than"; \
       echo "  the column it sits above, so the demo banner and the room controls overhang"; \
       echo "  every card beneath them on Mac and iPad (§361)."; exit 1; }
# EVERY category, not Markets alone — the whole point of this follow-up
# (user: "each category should have a switcher"). A gate re-narrowed to
# `MarketsRoom.isMember(source)` would silently take the switcher away from
# every other category while this exact grep still finds `CategoryVenueSwitcher(`.
grep -qE 'let category = BridgeCatalog\.category\(forSource: filter\.source\)' "$MAIN" \
  || { echo "✗ the switcher no longer resolves ITS OWN category from the room's source —"; \
       echo "  it would still be gated to Markets alone (or one other hardcoded category)."; exit 1; }

# The switcher and the prediction book must not BOTH offer a venue control —
# two capsules over one book, each able to change which venue you're reading,
# with no way to tell from either which one won.
grep -q 'foldedIntoMarkets' "$TMP/book.nc" \
  || { echo "✗ PredictionRoomBook's own switcher no longer stands down under the Markets fold"; exit 1; }
grep -q 'MarketsRoom.switcherFloor' "$TMP/book.nc" \
  || { echo "✗ PredictionRoomBook no longer gates on the switcher's own floor — a single"; \
       echo "  connected market seat would grow a one-scope switcher (\"not a control\")."; exit 1; }

# The twin price must NOT be gated on the merged scope again. §298's comparison
# was reachable only from `.all`, which the fold retires — re-gating it would
# make the one reading an aggregate produces silently disappear.
grep -qE 'scope == \.all \? await PredictionDisagreement' "$TMP/browse.nc" \
  && { echo "✗ the twin read is gated on .all again — the fold retires that scope, so"; \
       echo "  cross-venue disagreement would vanish from every room."; exit 1; }
grep -qE 'guard bothConnected else' "$TMP/browse.nc" \
  || { echo "✗ the twin read no longer keys on both venues being connected"; exit 1; }
grep -qE 'twinPrices = \[:\]' "$TMP/browse.nc" \
  || { echo "✗ twin prices are never cleared — a disconnected venue's numbers would persist"; exit 1; }
grep -q 'twinVenue' "$TMP/browse.nc" \
  || { echo "✗ the twin bar no longer names whose price it is — it would wear the wrong mark"; exit 1; }
grep -qE 'KalshiWatch\.book\(\s*""' "Casberi/Casberi/Model/PredictionDisagreement.swift" \
  || { echo "✗ findReverse no longer reads Kalshi's book once with an empty query —"; \
       echo "  a per-row title query hits a substring scan and matches nothing, ever."; exit 1; }
python3 - "$TMP/browse.nc" <<'PY2'
import sys
src = open(sys.argv[1]).read()
try:
    loaded = src.index("loaded = true")
except ValueError:
    sys.exit("✗ `loaded = true` not found in PredictionBrowseSection")
twin = src.find("PredictionDisagreement.find")
if twin < 0:
    sys.exit("✗ the twin read is gone from PredictionBrowseSection")
if twin < loaded:
    sys.exit("✗ the twin read runs BEFORE the book is committed — six sequential\n"
             "  searches would hold the skeleton up on every room load.")
PY2

# THE REAL CATALOG still answers, and every category in it still names at
# least one real offer — a stub proves the DERIVATION; only this proves the
# derivation still finds anything against the file that actually ships. A
# renamed/emptied category folds nothing and breaks nothing loudly.
python3 - "$CATALOG" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
cat_block = re.search(r'static let categories:.*?=\s*\[(.*?)\n    \]', src, re.S)
if not cat_block:
    sys.exit("✗ BridgeCatalog.categories not found at all")
entries = re.findall(r'\("([^"]+)",\s*"[^"]+",\s*\[([^\]]*)\]\)', cat_block.group(1))
if not entries:
    sys.exit("✗ BridgeCatalog.categories parsed to zero entries")
failures = []
for name, groups_raw in entries:
    groups = re.findall(r'"([^"]+)"', groups_raw)
    if not groups:
        failures.append(f"{name} names no groups")
        continue
    n = sum(len(re.findall(r'group:\s*"%s"' % re.escape(g), src)) for g in groups)
    if n < 1:
        failures.append(f"{name} (groups {groups}) has NO offers — it can never fold, and every one"
                         " of its members (if the group is later reused) folds into a chip nobody sees")
if failures:
    sys.exit("✗ " + "\n✗ ".join(failures))
markets = next((g for n, g in entries if n == "Markets"), None)
if markets is None:
    sys.exit('✗ BridgeCatalog.categories no longer has a "Markets" category — MarketsVenueSwitcher targets it by name')
print(f"  ✓ real catalog: {len(entries)} categories, every one names ≥1 real offer")

# Every SEATLESS source (a device capability the catalog has nothing to
# connect — "Voice") must name a category that really exists. Its whole job is
# to keep such a source inside the fold instead of sitting alone beside a row
# of category words (user ruling 2026-08-11); a category renamed out from under
# this table sends it silently back to the strip's bare circle and the tray's
# "Other" block, which looks exactly like the bug it fixed.
names = {n for n, _ in entries}
table = re.search(r'categoryBySeatlessSource:\s*\[String:\s*String\]\s*=\s*\[(.*?)\n    \]', src, re.S)
if not table:
    sys.exit("✗ BridgeCatalog.categoryBySeatlessSource not found — a seatless source"
             " (Voice) is filed nowhere again")
pairs = re.findall(r'"([^"]+)"\s*:\s*"([^"]+)"', table.group(1))
if not pairs:
    sys.exit("✗ categoryBySeatlessSource parsed to zero entries")
for source, category in pairs:
    if category not in names:
        sys.exit(f'✗ categoryBySeatlessSource maps "{source}" → "{category}",'
                 f" which is not a real category (have: {sorted(names)})")
    # It must ALSO be genuinely seatless: gaining a real offer makes the entry
    # dead code, and the live `offer(forSource:)` answer would then win.
    if re.search(r'name:\s*"%s"' % re.escape(source), src):
        sys.exit(f'✗ "{source}" now has a real catalog offer — drop it from'
                 " categoryBySeatlessSource, whose entries are for sources with no seat")
if "Voice" not in dict(pairs):
    sys.exit('✗ "Voice" is no longer filed by categoryBySeatlessSource')
print(f"  ✓ seatless sources: {len(pairs)} filed, every one into a real category")
PY

# --- the fixture catalog -----------------------------------------------------
# TWO categories on purpose (the old Markets-only harness only ever needed
# one) — `foldAll`'s disjointness-composability property cannot fail with a
# single category to fold, since there is nothing for a second pass to
# interfere with. "Wallet" also covers the identity-fold edge case: its own
# category name equals its sole always-present member's name, which must fold
# to a no-op rather than something surprising.
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation

enum BridgeCatalog {
    struct Offer { let name: String; let group: String }
    static let categories: [(name: String, exemplar: String, groups: Set<String>)] = [
        ("Wallet",  "Wallet", ["Wallet"]),
        ("Markets", "Kalshi", ["Markets", "NFTs"]),
    ]
    static let allOffers: [Offer] = [
        Offer(name: "Wallet",     group: "Wallet"),
        Offer(name: "Peer",       group: "Wallet"),
        // The 0xBow-shaped alias, on purpose: the real catalog names this
        // offer "0xBow Privacy Pools" while every landed thing carries
        // `source: "Privacy Pools"` — a real mismatch `fold`/`foldAll`
        // silently failed to bridge on their first cut (found LIVE,
        // 2026-08-11, reading the strip's own `chipLabels:` NSLog — this
        // stub had no aliased member and so could not have caught it).
        Offer(name: "0xBow Vault", group: "Wallet"),
        Offer(name: "Walletbeat",  group: "Wallet"),
        Offer(name: "CardPointers", group: "Wallet"),
        Offer(name: "Tokens",     group: "Markets"),
        Offer(name: "Kalshi",     group: "Markets"),
        Offer(name: "Polymarket", group: "Markets"),
        Offer(name: "OpenSea",    group: "NFTs"),
        Offer(name: "Photos",     group: "Photos"),
    ]
    static var offers: [Offer] { allOffers }

    static func category(of offer: Offer) -> String {
        categories.first { $0.groups.contains(offer.group) }?.name ?? "Life"
    }
    static func category(forSource source: String) -> String? {
        offer(forSource: source).map(category(of:))
    }
    static func offer(forSource source: String) -> Offer? {
        if let exact = allOffers.first(where: { $0.name == source }) { return exact }
        return allOffers.first(where: { $0.name.hasSuffix(" " + source) })
    }
}
SWIFT

# --- the driver ---------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") }
    else { print("  ✗ \(label)"); failures += 1 }
}

let markets = CategoryFold.memberSet(of: "Markets")
let wallet = CategoryFold.memberSet(of: "Wallet")

// --- members / isCategory: the derivation -----------------------------------
check("Markets spans both category groups",
      CategoryFold.members(of: "Markets") == ["Tokens", "Kalshi", "Polymarket", "OpenSea"])
check("Wallet has its own members",
      CategoryFold.members(of: "Wallet") == ["Wallet", "Peer", "0xBow Vault", "Walletbeat", "CardPointers"])
check("a non-member is not a member", !CategoryFold.isMember("Photos", of: "Markets"))
// isMember resolves through the catalog alias, exactly like fold — the
// second place the shipped bug lived (found live, 2026-08-11: this function
// feeds `MainSurface`'s `categoryVenues[category]`, so a false-negative here
// meant "Privacy Pools" was invisible to the switcher even though the fold
// itself had already been fixed).
check("isMember resolves an aliased source (short name vs. catalog display name)",
      CategoryFold.isMember("Vault", of: "Wallet"))
check("isMember rejects a source aliased into a DIFFERENT category",
      !CategoryFold.isMember("Vault", of: "Markets"))
check("a category name is recognized", CategoryFold.isCategory("Markets"))
check("a category name is recognized (Wallet)", CategoryFold.isCategory("Wallet"))
check("a plain source is not a category", !CategoryFold.isCategory("Kalshi"))

// CARDPOINTERS FOLDS (user ruling 2026-08-24, overturning the 2026-08-20/prd §423
// exemption after four days). It sits in the Wallet GROUP in the catalog — "it is cards
// people follow" — and the strip's fixed head has no room to spare for a standing
// exception, so it folds exactly like every other Wallet member now. Both halves are
// asserted for the same reason Walletbeat's are: it must vanish from the strip behind
// the Wallet chip AND appear inside that chip's switcher, or it is reachable never
// rather than twice.
check("CardPointers folds into Wallet",
      !CategoryFold.fold(["CardPointers", "Peer"], category: "Wallet",
                         members: CategoryFold.memberSet(of: "Wallet")).contains("CardPointers"))
check("CardPointers's chip reads as its category",
      CategoryFold.chipLabel(for: "CardPointers", folded: ["Wallet"]) == "Wallet")
check("CardPointers IS a Wallet switcher venue",
      CategoryFold.scopes(category: "Wallet", present: ["CardPointers", "Peer"]).contains("CardPointers"))
check("a fellow Wallet member is still a venue",
      CategoryFold.scopes(category: "Wallet", present: ["CardPointers", "Peer"]).contains("Peer"))

// WALLETBEAT FOLDS, and both halves are asserted for the same reason the exemption's
// were: it is a source room in the Wallet band, so it must vanish from the strip behind
// the Wallet chip AND appear inside that chip's switcher. Exempt-and-in-the-switcher is
// reachable twice; folded-and-absent is reachable never, which is what the day-long
// exemption was written to fix and is the failure to keep an eye on.
check("Walletbeat folds into Wallet",
      !CategoryFold.fold(["Walletbeat", "Peer"], category: "Wallet",
                         members: CategoryFold.memberSet(of: "Wallet")).contains("Walletbeat"))
check("Walletbeat's chip reads as its category",
      CategoryFold.chipLabel(for: "Walletbeat", folded: ["Wallet"]) == "Wallet")
check("Walletbeat IS a Wallet switcher venue",
      CategoryFold.scopes(category: "Wallet", present: ["Walletbeat", "Peer"]).contains("Walletbeat"))
check("an unknown label is not a category", !CategoryFold.isCategory("Nonsense"))

// --- fold: UNCONDITIONAL now — the whole point of §351 ----------------------
check("no fold with zero members present",
      CategoryFold.fold(["All", "Photos", "Wallet"], category: "Markets", members: markets)
        == ["All", "Photos", "Wallet"])
// THE KEY BEHAVIOR CHANGE FROM MarketsRoom: a SINGLE present member now
// folds too — the old harness pinned the opposite ("no fold with one member")
// because MarketsRoom.foldFloor was 2. Pinning this the other way is the
// whole reason this file replaces that one.
check("ONE present member still folds (no floor)",
      CategoryFold.fold(["All", "Kalshi", "Photos"], category: "Markets", members: markets)
        == ["All", "Markets", "Photos"])
check("folds into the first member's slot",
      CategoryFold.fold(["All", "Photos", "Kalshi", "Tokens"], category: "Markets", members: markets)
        == ["All", "Photos", "Markets"])
check("the category is inserted exactly ONCE for three members",
      CategoryFold.fold(["All", "Tokens", "Kalshi", "Polymarket", "OpenSea"], category: "Markets", members: markets)
        == ["All", "Markets"])
check("every member is removed",
      CategoryFold.fold(["All", "Tokens", "Photos", "OpenSea"], category: "Markets", members: markets)
        .allSatisfy { !markets.contains($0) })
check("folding is idempotent",
      CategoryFold.fold(CategoryFold.fold(["All", "Tokens", "Kalshi"], category: "Markets", members: markets),
                         category: "Markets", members: markets)
        == ["All", "Markets"])
// The identity edge case: Wallet's own category name equals its sole
// always-present member's name — folding must be a no-op, not double up or
// vanish the chip.
check("a category name equal to its own member folds to a no-op",
      CategoryFold.fold(["All", "Wallet", "Photos"], category: "Wallet", members: wallet)
        == ["All", "Wallet", "Photos"])

// --- fold: THE ALIAS BUG, found live 2026-08-11 ------------------------------
// "Vault" here is what a landed THING'S OWN `source` would say (the
// `Thing.source` string) — never the catalog's display name "0xBow Vault",
// which only `BridgeCatalog.offer(forSource:)`'s suffix match can bridge. A
// `fold` that tested `members.contains(label)` directly (the shipped bug)
// would see "Vault" ∉ {"Wallet","Peer","0xBow Vault"} and never fold it —
// exactly what happened to the real "Privacy Pools" source against the real
// "0xBow Privacy Pools" catalog offer, caught only by reading the strip's own
// live NSLog output, not by this file's own self-test (before this pair of
// assertions, the stub had no aliased member to expose it).
check("an ALIASED source (short name vs. the catalog's longer display name) still folds",
      CategoryFold.fold(["All", "Vault", "Photos"], category: "Wallet", members: wallet)
        == ["All", "Wallet", "Photos"])
check("foldAll resolves the same alias",
      CategoryFold.foldAll(["All", "Vault", "Kalshi"]) == ["All", "Wallet", "Markets"])

// --- foldAll: disjoint composability across every category ------------------
// The property a single-category harness cannot test: category A's fold
// leaves category B's members untouched, and both fold in one pass.
check("foldAll folds two independent categories in one pass",
      CategoryFold.foldAll(["All", "Peer", "Kalshi", "Photos"]) == ["All", "Wallet", "Markets", "Photos"])
check("foldAll folds a lone member from EITHER category",
      CategoryFold.foldAll(["All", "Peer", "Photos"]) == ["All", "Wallet", "Photos"])
check("foldAll leaves a corpus with no category members untouched",
      CategoryFold.foldAll(["All", "Photos"]) == ["All", "Photos"])
check("foldAll is order-independent for the categories it walks",
      CategoryFold.foldAll(["All", "Kalshi", "Peer", "Tokens"])
        == CategoryFold.foldAll(["All", "Kalshi", "Peer", "Tokens"]))

// --- chipLabel: which chip lights -------------------------------------------
let folded = CategoryFold.foldAll(["All", "Tokens", "Kalshi", "Photos"])
check("a folded member lights its category chip",
      CategoryFold.chipLabel(for: "Kalshi", folded: folded) == "Markets")
check("a non-catalog source lights itself",
      CategoryFold.chipLabel(for: "Photos", folded: folded) == "Photos")
// UNFOLDED, a member must light ITSELF — returning the category label here
// would point at a chip that isn't in the strip, which reads as no filter.
check("an unfolded member lights itself",
      CategoryFold.chipLabel(for: "Kalshi", folded: ["All", "Kalshi", "Photos"]) == "Kalshi")
check("a category name passed as a 'source' is inert (never a real source)",
      CategoryFold.chipLabel(for: "Markets", folded: folded) == "Markets")

// --- scopes: a switcher's own display order ---------------------------------
check("scopes follow catalog order, not the caller's",
      CategoryFold.scopes(category: "Markets", present: ["OpenSea", "Kalshi", "Tokens"])
        == ["Tokens", "Kalshi", "OpenSea"])
check("scopes exclude absent members",
      !CategoryFold.scopes(category: "Markets", present: ["Tokens", "Kalshi"]).contains("OpenSea"))
check("scopes exclude non-members",
      CategoryFold.scopes(category: "Markets", present: ["Tokens", "Photos"]) == ["Tokens"])
// The third place the alias bug lived (found live, 2026-08-11): scopes used
// to filter catalog NAMES by whether the caller's present SET (source
// strings) contained them — so "Vault" (present) could never match "0xBow
// Vault" (the catalog name `members(of:)` returns), and the aliased seat
// silently vanished from the switcher's own scope list, not merely
// mis-ordered within it.
check("scopes resolves an aliased present source rather than dropping it",
      CategoryFold.scopes(category: "Wallet", present: ["Vault", "Peer"]).contains("Vault"))
check("scopes places an aliased source at its OWN catalog offer's position",
      CategoryFold.scopes(category: "Wallet", present: ["Vault", "Peer", "Wallet"])
        == ["Wallet", "Peer", "Vault"])

// --- landing / remember: per-category isolation -----------------------------
let mKey = "categoryFold.lastVenue.Markets"
let wKey = "categoryFold.lastVenue.Wallet"
let lifeKey = "categoryFold.lastVenue.Life"
// This is a REAL UserDefaults.standard, keyed by this compiled binary's own
// identity, not a sandboxed fixture — a leftover value from a PRIOR run of
// this very script (or an earlier draft of it) persists on disk across runs.
// Clear every key this test can possibly touch before asserting any of them.
[mKey, wKey, lifeKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }
check("with no memory, lands on the first present venue",
      CategoryFold.landing(category: "Markets", present: ["Kalshi", "Tokens"]) == "Kalshi")
check("with nothing present, lands nowhere",
      CategoryFold.landing(category: "Markets", present: []) == nil)
CategoryFold.remember("Polymarket")
check("remembers a member under ITS OWN category's key",
      UserDefaults.standard.string(forKey: mKey) == "Polymarket")
check("reopens where you left off",
      CategoryFold.landing(category: "Markets", present: ["Tokens", "Polymarket"]) == "Polymarket")
// A remembered venue that has since disappeared (disconnected, last row
// deleted) must NOT be handed back — that is a room with no door.
check("a remembered venue that vanished falls back",
      CategoryFold.landing(category: "Markets", present: ["Tokens", "Kalshi"]) == "Tokens")
// The other category's memory must be UNTOUCHED by any of the above — the
// whole reason the key is namespaced per category rather than the single
// `markets.lastVenue` MarketsRoom used to own.
check("remembering a Markets venue never touches Wallet's own memory",
      UserDefaults.standard.string(forKey: wKey) == nil)
CategoryFold.remember("Peer")
check("Wallet's own memory is independent",
      UserDefaults.standard.string(forKey: wKey) == "Peer"
        && UserDefaults.standard.string(forKey: mKey) == "Polymarket")
// "Photos" is NOT a fit test here: it IS a real stub offer whose group maps
// to no category, so `category(of:)`'s own `?? "Life"` fallback resolves it
// to "Life" rather than nil — a source the catalog has genuinely never heard
// of ("All", "Pinned", or anything absent from `allOffers`) is the only input
// that makes `category(forSource:)` return nil, which is what `remember`'s
// guard actually depends on.
CategoryFold.remember("TotallyUnknownThing")
check("refuses to remember a source the catalog has never heard of",
      UserDefaults.standard.string(forKey: mKey) == "Polymarket"
        && UserDefaults.standard.string(forKey: wKey) == "Peer"
        && UserDefaults.standard.string(forKey: lifeKey) == nil)

// --- the Wallet anchor (prd §354): the chip always lands home ---------------
// wKey still holds "Peer" from above — the anchor must BEAT a real, present
// memory, or it does nothing for the exact person it exists for (one who
// actually visits the riders).
check("Wallet lands on the balance room despite a remembered rider",
      CategoryFold.landing(category: "Wallet", present: ["Peer", "Wallet", "Vault"]) == "Wallet")
// The anchor answers only when its member is PRESENT — otherwise it would be
// a room with no door, the same rule as a vanished remembered venue.
check("an absent anchor falls back to the memory",
      CategoryFold.landing(category: "Wallet", present: ["Peer", "Vault"]) == "Peer")
// Markets has no anchor: reopening where you left off is the point there —
// no venue is home, so §354's ruling is Wallet's alone.
check("Markets still reopens where you left off (no anchor)",
      CategoryFold.landing(category: "Markets", present: ["Tokens", "Polymarket"]) == "Polymarket")
[mKey, wKey, lifeKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }

print(failures == 0 ? "category-fold-selftest: OK" : "category-fold-selftest: \(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
SWIFT

echo "category-fold-selftest: compiling CategoryFold.swift as shipped…"
swiftc -O -o "$TMP/run" "$FOLD" "$TMP/stub.swift" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/run" ]] || { echo "✗ compile failed — CategoryFold.swift no longer builds Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ------------------------------------------------------
# Each mutation is a plausible edit that must be CAUGHT. A check that cannot
# fail proves nothing (the `--self-test` doctrine used by every audit here).
mutate() {
  local label="$1" expr="$2"
  python3 - "$FOLD" "$TMP/mutated.swift" "$expr" <<'PY'
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3].split("|||")
if old not in src:
    sys.exit(f"✗ mutation anchor not found: {old!r} — this harness is testing stale code")
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PY
  if swiftc -O -o "$TMP/mrun" "$TMP/mutated.swift" "$TMP/stub.swift" "$TMP/main.swift" 2>/dev/null \
     && "$TMP/mrun" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $label"
    return 1
  fi
  echo "  ✓ mutation caught: $label"
}

echo "category-fold-selftest: mutation pass…"
mfail=0
mutate "fold appends to the tail instead of the member's slot" \
  'if !placed { folded.append(category); placed = true }|||continue' || mfail=1
mutate "fold inserts the category once per member instead of once" \
  'if !placed { folded.append(category); placed = true }|||folded.append(category)' || mfail=1
mutate "a floor creeps back into fold — the ruling this file exists to enforce" \
  'guard !members.isEmpty else { return ordered }|||let present = ordered.filter { members.contains($0) }; guard present.count >= 2 else { return ordered }' || mfail=1
mutate "fold tests the raw member set instead of resolving each label's own category (THE SHIPPED BUG)" \
  'guard BridgeCatalog.category(forSource: label) == category
            else { folded.append(label); continue }|||guard members.contains(label) else { folded.append(label); continue }' || mfail=1
mutate "foldAll stops after the first category instead of walking all of them" \
  'for category in BridgeCatalog.categories {
            chips = fold(chips, category: category.name, members: memberSetCache[category.name] ?? [])
        }
        return chips|||if let first = BridgeCatalog.categories.first {
            chips = fold(chips, category: first.name, members: memberSetCache[first.name] ?? [])
        }
        return chips' || mfail=1
mutate "chipLabel returns the raw source while folded" \
  'else { return source }
        return category|||else { return source }
        return source' || mfail=1
mutate "members reads only the first group instead of every group the category names" \
  '.filter { category.groups.contains($0.group) }|||.filter { $0.group == category.name }' || mfail=1
# Deterministically wrong, NOT `Array(filtered)` (amended 2026-08-28).
# `present` is a Set, so `Array` of it is in hash order — which matched the
# fixture's expected order often enough that this mutation SURVIVED at random
# and reddened a Mac run (the cache-free loop) while iOS held a cached green.
# Reverse-alphabetical is a real order and never the catalog's. Third instance
# of this trap in one day — see wallet-permissions and hegota-selftest.
mutate "scopes follows the caller's order instead of catalog order" \
  'return filtered.sorted {
            let ra = rank($0), rb = rank($1)
            return ra != rb ? ra < rb : $0 < $1
        }|||return filtered.sorted(by: >)' || mfail=1
mutate "scopes tests the raw member set instead of resolving each present source's own category (THE SHIPPED BUG, a third place)" \
  'BridgeCatalog.category(forSource: $0) == category|||order.contains($0)' || mfail=1
mutate "landing ignores whether the remembered venue is still present" \
  'present.contains(last) { return last }|||!last.isEmpty { return last }' || mfail=1
mutate "the Wallet anchor is gone — the chip reopens on whichever rider you last visited (prd §354)" \
  'if let anchor = anchors[category], present.contains(anchor) { return anchor }
        if let last|||if let last' || mfail=1
mutate "the anchor ignores whether its member is present — a room with no door" \
  'anchors[category], present.contains(anchor) { return anchor }|||anchors[category] { return anchor }' || mfail=1
mutate "remember accepts a source that belongs to no category" \
  'guard let category = BridgeCatalog.category(forSource: source) else { return }|||let category = BridgeCatalog.category(forSource: source) ?? "Life"' || mfail=1

[[ $mfail -eq 0 ]] || { echo "category-fold-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "category-fold-selftest: OK — fold order, resolution, composability and switcher order all pinned."
