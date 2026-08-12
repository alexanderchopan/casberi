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
for f in "$FOLD" "$ROOM" "$MAIN" "$CHIPS" "$FEED" "$SWITCHER" "$BROWSE" "$BOOK" "$CATALOG" "$ROOT" "$APP" "$RAIL" "$CHROME"; do
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
grep -q 'SourcesTray(labels: chrome.sourceOrder' "$TMP/root.nc" \
  || { echo "✗ the sources tray is back on chipOrder — it would drop every folded category's members"; \
       echo "  and offer a category cell that writes a non-source into FeedFilter.source."; exit 1; }
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
grep -q 'roomControls' "$MAIN" \
  && grep -qE '^\s*categorySwitcher$' "$MAIN" \
  && grep -qE '^\s*walletScopeRail$' "$MAIN" \
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
# The caption is lineLimit(1) in a 66pt slot and an unnamed wallet wears
# `short` — so two wallets sharing a prefix are indistinguishable, and the
# tooltip is the ONLY place the full address can appear.
grep -q 'dsTooltip' "$TMP/rail.nc" \
  || { echo "✗ the wallet rail names nothing on hover — an unnamed wallet's caption is a"; \
       echo "  truncated hex in a 66pt slot, so the tooltip is the only thing that can tell"; \
       echo "  two wallets sharing a prefix apart without clicking one (dsTooltip's own reason)."; exit 1; }

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
# Both must be MOUNTED, and mounted together: a rail that is not in `roomControls`
# is not chrome, and a filter you are standing in that scrolls away is a filter
# with no visible way out (§136/§357, re-earned for the social rail by §362).
grep -q 'walletScopeRail' "$TMP/main.nc" && grep -q 'socialScopeRail' "$TMP/main.nc" \
  || { echo "✗ MainSurface.roomControls no longer carries BOTH face rails — one of them has"; \
       echo "  gone back to being a card inside FeedScreen, where .id(filter.source) destroys"; \
       echo "  it on every move it commands (§357) and it scrolls away with the room."; exit 1; }
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
grep -A2 'var shellChromeClear' "$TMP/chrome.nc" \
  | grep -q '!walkModalOpen && !walkSheetOpen && !walkInPushedRoom' \
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

# --- the top inset must clear the rail (prd §361) ---------------------------
# `topInset` is a `.safeAreaInset(edge: .top)` applied INSIDE the NavigationStack
# and the rail is a `.safeAreaInset(edge: .leading)` applied OUTSIDE it, on the
# stack — so the rail spans the window's full height from the very top and this
# band is laid out across the full width beneath it. The stack's CONTENT respects
# the leading safe area; a top inset view does not. Everything in that VStack —
# the demo banner AND both §357 room controls — therefore drew under the rail's
# head doors on every regular-width surface. Verified on the real Mac renderer
# (`-macSnapshot`) before and after, which is the only place it is visible at all:
# it cannot happen on a phone, where `showsRail` is false.
# Scoped to `topInset`'s own body (up to `bandContent`, the property it was
# split into) rather than the whole file — `dsAdaptiveContentWidth()` is the
# app's general column cap and appears on plenty of screens, so a file-wide grep
# would pass while this band had lost it. A fixed `-A<n>` window does NOT work
# here: `strip_comments` blanks comment lines rather than deleting them, so the
# doc block above the construction still counts toward the window.
awk '/private var topInset/,/private var bandContent/' "$TMP/main.nc" > "$TMP/topinset.nc"
grep -qE 'padding\(\.leading, showsRail \? PadLayout\.railWidth' "$TMP/topinset.nc" \
  || { echo "✗ MainSurface.topInset no longer reserves the rail's column — the demo banner and"; \
       echo "  both room controls (§357) draw under the rail's head doors on Mac and iPad,"; \
       echo "  because a top safeAreaInset does not respect the leading one applied outside"; \
       echo "  the stack (§361). Invisible on iPhone, where showsRail is false."; exit 1; }
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
      CategoryFold.members(of: "Wallet") == ["Wallet", "Peer", "0xBow Vault"])
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
mutate "scopes follows the caller's order instead of catalog order" \
  'return filtered.sorted {
            let ra = rank($0), rb = rank($1)
            return ra != rb ? ra < rb : $0 < $1
        }|||return Array(filtered)' || mfail=1
mutate "scopes tests the raw member set instead of resolving each present source's own category (THE SHIPPED BUG, a third place)" \
  'let filtered = present.filter { BridgeCatalog.category(forSource: $0) == category }|||let filtered = present.filter { order.contains($0) }' || mfail=1
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
