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
for f in "$FOLD" "$ROOM" "$MAIN" "$CHIPS" "$FEED" "$SWITCHER" "$BROWSE" "$BOOK" "$CATALOG" "$ROOT" "$APP"; do
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
strip_comments "$MAIN"   > "$TMP/main.nc"
strip_comments "$BROWSE" > "$TMP/browse.nc"
strip_comments "$BOOK"   > "$TMP/book.nc"
strip_comments "$ROOT"   > "$TMP/root.nc"
strip_comments "$APP"    > "$TMP/app.nc"

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
grep -qE 'if CategoryFold\.isCategory\(label\)' "$CHIPS" \
  || { echo "✗ SourceChips no longer branches on CategoryFold.isCategory — a folded chip"; \
       echo "  would render through the generic BridgeIcon path and show a missing brand icon."; exit 1; }
grep -q 'CategoryVenueSwitcher(' "$FEED" \
  || { echo "✗ FeedScreen no longer mounts the generic venue switcher — a folded category seat has no way out"; exit 1; }
# PINNED, not a List section — `walletSwitcherBar`'s 2026-07-20 ruling. As a
# section it scrolls away with the room it names, and its glass blurs nothing.
grep -qE 'safeAreaInset\(edge: \.top, spacing: 0\) \{ categorySwitcher \}' "$FEED" \
  || { echo "✗ the category venue switcher is no longer pinned — it would scroll away with the"; \
       echo "  room it scopes, and its glass would have nothing moving behind it."; exit 1; }
# EVERY category, not Markets alone — the whole point of this follow-up
# (user: "each category should have a switcher"). A gate re-narrowed to
# `MarketsRoom.isMember(source)` would silently take the switcher away from
# every other category while this exact grep still finds `CategoryVenueSwitcher(`.
grep -qE 'let category = BridgeCatalog\.category\(forSource: source\)' "$FEED" \
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
  'members(of: category).filter { present.contains($0) }|||Array(present)' || mfail=1
mutate "landing ignores whether the remembered venue is still present" \
  'present.contains(last) { return last }|||!last.isEmpty { return last }' || mfail=1
mutate "remember accepts a source that belongs to no category" \
  'guard let category = BridgeCatalog.category(forSource: source) else { return }|||let category = BridgeCatalog.category(forSource: source) ?? "Life"' || mfail=1

[[ $mfail -eq 0 ]] || { echo "category-fold-selftest: a mutation SURVIVED — a check above proves nothing"; exit 1; }
echo "category-fold-selftest: OK — fold order, resolution, composability and switcher order all pinned."
