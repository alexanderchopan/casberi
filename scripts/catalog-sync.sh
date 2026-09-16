#!/usr/bin/env bash
#
# catalog-sync.sh — enforce the single-source-of-truth rule for the app catalog.
#
# Source of truth: BridgeCatalog.offers (Casberi/Casberi/Model/BridgeCatalog.swift).
# Everything else must be a faithful function of it:
#
#   1. WEBSITE CATALOG SHELF  (website/index.html #catalog .mini-cell)
#        MUST equal, name-for-name, the set of CONNECTABLE offers.
#        (Ruling 2026-07-14: the site lists no "Soon" apps — a non-connectable
#         offer simply isn't on the site.) A hard failure either way:
#        a connectable app missing from the site, or a site tile that is not
#        a connectable offer (typo, rename, or a showcase app that slipped in).
#
#   2. ONBOARDING CONNECT LIST is gone (re-ruled 2026-07-16): the connect
#        screen died — onboarding is the "How it works" greeting straight
#        into the catalog, and the catalog is code-derived. Nothing to check.
#
#   3. STORE-COPY APP LISTS (docs/store-copy.md, docs/app-store-submission.md)
#        A `CONNECTS WITH` block is a promise on the App Store that the app
#        connects to each name in it, so every name MUST resolve to a
#        CONNECTABLE offer — stricter than the marquee rule, which only asks
#        that a name be a real offer. Completeness is NOT required (the block
#        is curated and ends open-ended). Nothing read these docs until
#        2026-09-11, and the list had sat six retirements behind: Spotify
#        (a5a515e5) plus the five Markets seats (§638).
#
#   4. DECORATIVE MARQUEES — the website hero rain (index.html .rain) and the
#        onboarding rain (IntroCover.marqueeApps) — are hand-curated
#        SUBSETS by design (the rain has never listed Photos/Wallet/etc.).
#        We do NOT require completeness, but every name they reference MUST
#        resolve to a real offer, so a rename/removal/typo can't leave a dead
#        tile behind. Connectable offers absent from a marquee are reported as
#        INFO (not a failure) so a newly added app is easy to notice.
#
# Exit non-zero on any hard failure. Run from repo root (or anywhere; paths are
# resolved relative to this script). Wired into scripts/verify.sh.

set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
ONBOARD="Casberi/Casberi/Screens/IntroCover.swift"
INDEX="website/index.html"
DOCS="website/docs.html"
# Overridable so the check can be proven against fixtures without mutating a
# tracked file (a peer session's `git add -A` would commit the mutation).
if [ -n "${CATALOG_SYNC_COPYDOCS:-}" ]; then
  read -ra COPYDOCS <<< "$CATALOG_SYNC_COPYDOCS"
else
  COPYDOCS=(docs/store-copy.md docs/app-store-submission.md)
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door. The
# joined copy lives in $tmp: a plain `mktemp -d` is the one form both mktemps
# accept — GNU's `-t feedscreen` fails ("too few X's"), which is what turned
# the audits job red on every push since §718. CI runs this on ubuntu.
FEED="$tmp/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+WalletRoom.swift > "$FEED"

# --- 1. Canonical sets from the Swift source of truth ---------------------
# Each Offer(...) declares name and connectable on the same physical line.
grep -oE 'Offer\(name: "[^"]+".*connectable: true'  "$CATALOG" \
  | sed -E 's/.*name: "([^"]+)".*/\1/' | sort -u > "$tmp/connectable"
grep -oE 'Offer\(name: "[^"]+"' "$CATALOG" \
  | sed -E 's/.*name: "([^"]+)".*/\1/' | sort -u > "$tmp/all"

# --- 2. Website catalog shelf (the #catalog mini-cells) -------------------
awk '/id="catalog"/{f=1} f' "$INDEX" \
  | grep 'mini-cell' \
  | grep -oE '<span>[^<]+</span>' \
  | sed -E 's|<span>([^<]+)</span>|\1|' | sort > "$tmp/web_shelf_raw"
sort -u "$tmp/web_shelf_raw" > "$tmp/web_shelf"

# --- 2b. The website DOCS list (docs.html #every-app), which nothing checked
#         until 2026-09-15. It is a second hand-kept copy of the same catalog,
#         grouped by a website taxonomy of its own, and it had silently drifted
#         one app away from the shelf. The "97 apps" line above it was wrong by
#         two at the same time — a hand-kept NUMBER beside a hand-kept LIST.
awk '/id="every-app"/{f=1} f' "$DOCS" \
  | grep -oE '<li><b>[^<]+</b>' \
  | sed -E 's|<li><b>([^<]+)</b>|\1|' | sort > "$tmp/web_docs_raw"
sort -u "$tmp/web_docs_raw" > "$tmp/web_docs"

# --- 3. Website hero marquee tiles (inside the .rain div) -----------------
awk '/class="rain">/{f=1} /rain-target/{f=0} f' "$INDEX" \
  | grep -oE 'alt="[^"]+"' | sed -E 's/alt="([^"]+)"/\1/' \
  | grep -v '^$' | sort -u > "$tmp/web_marquee"

# --- 4. The onboarding rain is DERIVED from the catalog (2026-08-31), so
#        there is no hand list left to go stale. What IS a hand list is the
#        six tiles that LAND on the shelf, and those are checked here.
awk '/landers *= *\[/{f=1} f{print} f&&/\]/{exit}' "$ONBOARD" \
  | grep -oE '"[^"]+"' | tr -d '"' | sort -u > "$tmp/onb_marquee"

# --- 5. Empty-feed pile names (EmptyFeedPile.pileApps array) --------------
awk '/pileApps *= *\[/{f=1} f{print} f&&/\]/{exit}' "$FEED" \
  | grep -oE '"[^"]+"' | tr -d '"' | sort -u > "$tmp/feed_pile"

fail=0
say()  { printf '%s\n' "$*"; }
bad()  { printf '  ✗ %s\n' "$*"; fail=1; }
info() { printf '  · %s\n' "$*"; }

# === Check 1: website shelf == connectable (strict) ======================
say "Website catalog shelf ↔ connectable offers"
# A DUPLICATE tile is invisible to the set comparison below (`sort -u`
# collapses it), which is exactly how Railgun shipped twice in the Wallet
# shelf and was found by eye instead. Counted before the sets are compared.
dupes="$(uniq -d "$tmp/web_shelf_raw")"

missing="$(comm -23 "$tmp/connectable" "$tmp/web_shelf")"
extra="$(comm -13 "$tmp/connectable" "$tmp/web_shelf")"
if [ -n "$dupes" ]; then
  while IFS= read -r n; do
    [ -n "$n" ] && echo "  ✗ listed more than once on the website shelf: $n" && fail=1
  done <<< "$dupes"
fi
if [ -n "$missing" ]; then
  while IFS= read -r a; do bad "connectable but MISSING from website shelf: $a"; done <<< "$missing"
fi
if [ -n "$extra" ]; then
  while IFS= read -r a; do bad "on website shelf but NOT a connectable offer: $a"; done <<< "$extra"
fi
[ -z "$missing$extra" ] && say "  ✓ in sync"

# === Check 1b: the docs "every app" list == connectable ==================
# Added 2026-09-15 after the user found the count stale ("we need to update the
# number of apps here, or just remove that number, and we need to update the
# docs on the website too"). The shelf was gated and the docs list was not, so
# the docs list is where drift accumulated silently.
say "Website docs list ↔ connectable offers"
docs_dupes="$(uniq -d "$tmp/web_docs_raw")"
docs_missing="$(comm -23 "$tmp/connectable" "$tmp/web_docs")"
docs_extra="$(comm -13 "$tmp/connectable" "$tmp/web_docs")"
if [ -n "$docs_dupes" ]; then
  while IFS= read -r n; do
    [ -n "$n" ] && bad "listed more than once in the docs list: $n"
  done <<< "$docs_dupes"
fi
if [ -n "$docs_missing" ]; then
  while IFS= read -r a; do bad "connectable but MISSING from docs.html #every-app: $a"; done <<< "$docs_missing"
fi
if [ -n "$docs_extra" ]; then
  while IFS= read -r a; do bad "in docs.html #every-app but NOT a connectable offer: $a"; done <<< "$docs_extra"
fi
[ -z "$docs_missing$docs_extra" ] && say "  ✓ in sync"

# === Check 1c: the app COUNT on the home page is the real one ============
# The no-JS fallback. `app.js` derives it at runtime from the shelf, so this
# only pins the server-rendered number — but that number is what a crawler and
# a JS-less visitor read, and it is the one that was wrong.
# The claim is "100+" — rounded DOWN to a ten, so it stays true as seats are
# added and can never over-promise. Checked as: the stated ten must be the
# shelf's own floor. A stated 100+ over a 99-cell shelf is a lie; over 109 it
# is stale but still true, and the check still fails it, because a number that
# drifts silently is what put "97" over a 101-cell shelf.
say "Home page app count"
shelf_n="$(wc -l < "$tmp/web_shelf_raw" | tr -d ' ')"
stated_n="$(grep -oE 'id="bk-count">[0-9]+\+? apps' "$INDEX" | grep -oE '[0-9]+' || echo 0)"
want_n=$(( shelf_n / 10 * 10 ))
if [ "$stated_n" != "$want_n" ]; then
  bad "the home page says ${stated_n}+ apps; the shelf holds $shelf_n, so it should say ${want_n}+"
else
  say "  ✓ ${stated_n}+ apps, the floor of the shelf's $shelf_n"
fi

# === Check 2: every marquee name resolves to a real offer ================
check_marquee_validity() {
  local label="$1" file="$2"
  local dead; dead="$(comm -23 "$file" "$tmp/all")"
  if [ -n "$dead" ]; then
    while IFS= read -r a; do bad "$label references a name that is not an offer: $a"; done <<< "$dead"
  fi
}
say "Marquee names resolve to real offers"
check_marquee_validity "website hero marquee" "$tmp/web_marquee"
check_marquee_validity "onboarding landing tiles"  "$tmp/onb_marquee"
# The rain itself must stay derived — a hand list creeping back is exactly the
# drift this check existed to catch.
grep -q 'BridgeCatalog.offers.filter' "$ONBOARD" \
  || bad "the onboarding rain no longer derives its names from the catalog"
check_marquee_validity "empty-feed pile"  "$tmp/feed_pile"
[ "$fail" -eq 0 ] && say "  ✓ all marquee names valid"

# === Check 3: store-copy CONNECTS WITH names are connectable =============
# Fires only where such a block exists, so a doc without one is silent rather
# than green-by-absence. The block is one paragraph: the line(s) after the
# heading, up to the first blank line.
say "Store-copy app lists ↔ connectable offers"
found_block=0
for doc in "${COPYDOCS[@]}"; do
  [ -f "$doc" ] || continue
  awk '/^CONNECTS WITH[[:space:]]*$/{f=1;next} f&&/^[[:space:]]*$/{exit} f{print}' "$doc" \
    > "$tmp/copy_raw"
  [ -s "$tmp/copy_raw" ] || continue
  found_block=1
  # Comma-separated names; drop the trailing open-ended clause after an em dash.
  sed -E 's/[[:space:]]*—.*$//' "$tmp/copy_raw" \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | grep -v '^$' | sort -u > "$tmp/copy_names"
  dead="$(comm -23 "$tmp/copy_names" "$tmp/connectable")"
  if [ -n "$dead" ]; then
    while IFS= read -r a; do
      bad "$doc CONNECTS WITH names a seat that is not a connectable offer: $a"
    done <<< "$dead"
  fi
done
if [ "$found_block" -eq 0 ]; then
  info "no CONNECTS WITH block in the copy docs — nothing to check"
elif [ "$fail" -eq 0 ]; then
  say "  ✓ every listed seat is connectable"
fi

# === Info: connectable apps not (yet) in a decorative marquee ============
say "Connectable apps absent from a marquee (info only)"
info "hero marquee omits: $(comm -23 "$tmp/connectable" "$tmp/web_marquee" | paste -sd, - | sed 's/,/, /g')"
info "onboarding rain: derived from the catalog — every connectable seat falls"

echo
if [ "$fail" -ne 0 ]; then
  say "catalog-sync: FAIL — the catalog surfaces have drifted (see ✗ above)."
  exit 1
fi
say "catalog-sync: OK — website shelf mirrors the catalog; every marquee name is real."
