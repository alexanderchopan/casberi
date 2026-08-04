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
#   3. DECORATIVE MARQUEES — the website hero rain (index.html .rain) and the
#        onboarding rain (HowItWorksSheet.marqueeApps) — are hand-curated
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
ONBOARD="Casberi/Casberi/Screens/HowItWorksSheet.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
INDEX="website/index.html"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

# --- 3. Website hero marquee tiles (inside the .rain div) -----------------
awk '/class="rain">/{f=1} /rain-target/{f=0} f' "$INDEX" \
  | grep -oE 'alt="[^"]+"' | sed -E 's/alt="([^"]+)"/\1/' \
  | grep -v '^$' | sort -u > "$tmp/web_marquee"

# --- 4. Onboarding ice-pile names (marqueeApps array) --------------------
awk '/marqueeApps *= *\[/{f=1} f{print} f&&/\]/{exit}' "$ONBOARD" \
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
check_marquee_validity "onboarding rain"  "$tmp/onb_marquee"
check_marquee_validity "empty-feed pile"  "$tmp/feed_pile"
[ "$fail" -eq 0 ] && say "  ✓ all marquee names valid"

# === Info: connectable apps not (yet) in a decorative marquee ============
say "Connectable apps absent from a marquee (info only)"
info "hero marquee omits: $(comm -23 "$tmp/connectable" "$tmp/web_marquee" | paste -sd, - | sed 's/,/, /g')"
info "onboarding rain omits: $(comm -23 "$tmp/connectable" "$tmp/onb_marquee" | paste -sd, - | sed 's/,/, /g')"

echo
if [ "$fail" -ne 0 ]; then
  say "catalog-sync: FAIL — the catalog surfaces have drifted (see ✗ above)."
  exit 1
fi
say "catalog-sync: OK — website shelf mirrors the catalog; every marquee name is real."
