#!/bin/zsh
# Feed-grammar self-test (prd §900, 2026-09-23) — one grammar down the feed's
# column:
#
#   Casberi/Casberi/Design/MoneyClause.swift   compiled WHOLE and unmodified
#
# WHAT §900 CHANGED, and what each half of this file holds:
#
#   • MONEY TRAILS THE TITLE. "Ada Lovelace · $49.00" draws "Ada Lovelace" with
#     $49.00 in the trailing slot. `MoneyClause.split` decides what is money,
#     and a wrong split moves a WORD out of a title, so it is compiled here and
#     driven over the titles the bridges and the demo actually land — including
#     the ones that must be left alone ("$ETH", "€100 in bitcoin", a dispute
#     whose figure is followed by a deadline).
#   • A FOLD NEVER SHOWS MONEY. Its name is the newest member's title, and a
#     figure beside "+3 more" reads as the total of all four. Asserted on the
#     source: both fold rows name themselves through `FoldName.of`, which
#     strips, and neither draws `price17`.
#   • BLUE IS FOR WHAT YOU TAP. A new row's time is primary ink at medium
#     weight, the next event's countdown is primary, and the line's project
#     clause is medium weight in the line's own ink — none of them the tint,
#     and the line no longer wears the source's hue.
#   • THE DOOR SAYS WHAT IT HOLDS. `Show older` is a row with the count of
#     things it holds back, and that count comes from the same walk as the
#     window's `more`, weighted so a fold counts as its members.
#   • ONE PADDING. Feed rows sit in `rowAir` (s1), not s2 on top of the row's
#     own s2.
#
# Plus mutations: each drift guard is run against a copy with the regression
# put back, and must fail — a guard that passes a broken file certifies
# nothing (`mutation-liveness-audit.py`).
#
# Pure, local, deterministic — no network, no simulator, no key.
set -euo pipefail
cd "$(dirname "$0")/.."

MONEY="Casberi/Casberi/Design/MoneyClause.swift"
ROWS="Casberi/Casberi/Screens/ShapedRows.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
TEMPLATE="Casberi/Casberi/Design/DSFeedRow.swift"
DEMO="Casberi/Casberi/Model/DemoSeedAll.swift"
for f in "$MONEY" "$ROWS" "$FEED" "$TEMPLATE" "$DEMO"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/feed-grammar-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# ── 1. The split, compiled ───────────────────────────────────────────────────
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func splits(_ t: String, _ title: String, _ amount: String) {
    let r = MoneyClause.split(t)
    check(r?.title == title && r?.amount == amount, "\"\(t)\" → \"\(title)\" + \(amount)")
}
func stays(_ t: String) {
    check(MoneyClause.split(t) == nil, "\"\(t)\" keeps its title")
}

// The titles payment and sale bridges land.
splits("Ada Lovelace · $49.00", "Ada Lovelace", "$49.00")
splits("Casberi Pro · $29.00", "Casberi Pro", "$29.00")
splits("Payout paid · $4,120.00", "Payout paid", "$4,120.00")
splits("Refund · $12.00", "Refund", "$12.00")
splits("Supermarket · €42.80", "Supermarket", "€42.80")
splits("Boulangerie · 4,20 €", "Boulangerie", "4,20 €")
splits("Spend anomaly · $184.20", "Spend anomaly", "$184.20")
splits("Tesco · −£18.40", "Tesco", "−£18.40")
// Only the LAST clause is money; an earlier " · " stays in the title.
splits("Stripe · Invoice 42 · $900", "Stripe · Invoice 42", "$900")
// Acorns titles its balances with an em dash.
splits("Checking — $191.40", "Checking", "$191.40")
stays("Saturday's match — our view")                      // a dash, no figure

// What must NOT move.
stays("Ethereum · $ETH")                                  // a ticker, not a figure
stays("Tesla · $TSLA")
stays("Balance refill · €100 in bitcoin")                 // words after the figure
stays("Dispute opened · $49.00 — evidence due Oct 2")     // a deadline after it
stays("$49.00")                                           // no title to leave
stays(" · $49.00")                                        // nothing before it
stays("Alarm · prod-api-5xx")                             // no symbol
stays("Swapped 0.5 ETH → 1,240 USDC")                     // no clause at all
stays("Budget · $")                                       // a symbol, no digits
stays("Rate · $1.2k")                                     // a suffix is not a figure
stays("Price · $$40")                                     // two symbols
stays("Mixed · $40 €")                                    // one each side

// A fold's name is stripped, and a plain title passes through untouched.
check(MoneyClause.stripped("Ada Lovelace · $49.00") == "Ada Lovelace", "a fold's name drops its figure")
check(MoneyClause.stripped("TAP-1147-confirmation.pdf") == "TAP-1147-confirmation.pdf", "a plain title is unchanged")

if failures > 0 { print("✗ \(failures) money-clause case(s) failed"); exit(1) }
SWIFT

echo "▶ MoneyClause, compiled whole"
swiftc -O -o "$TMP/money" "$MONEY" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ MoneyClause.swift did not compile Foundation-only"; exit 1; }
"$TMP/money"

# ── 2. Drift guards, each a function so the mutations can re-run it ──────────
strip_comments() { perl -0pe 's{/\*.*?\*/}{}gs; s{//[^\n]*}{}g' "$1"; }

# Prints nothing when clean; one line per violation.
guards() {
  local rows="$1" feed="$2" template="$3" demo="$4"
  local R F T D
  R=$(strip_comments "$rows"); F=$(strip_comments "$feed")
  T=$(strip_comments "$template"); D=$(strip_comments "$demo")

  # Money: the single row reads the title's figure, gated on a stored price.
  grep -q -- 'guard moneyAmount == nil, thing.priceValue != nil' <<< "$R" \
    || echo "a title's money is no longer gated on the row's stored price"
  grep -q -- 'MoneyClause.split(thing.title)' <<< "$R" \
    || echo "BandRow no longer reads the title's figure through MoneyClause"
  grep -q -- 'else if let figure = titleFigure' <<< "$R" \
    || echo "the title's figure no longer draws in the trailing slot"

  # A fold never shows money.
  local bundle strip
  bundle=$(awk '/^struct BundleRow/{p=1} /^enum FoldName/{p=0} p' <<< "$R")
  strip=$(awk '/^struct StripRow/{p=1} /^\/\/ MARK: - All/{p=0} p' <<< "$R")
  grep -q -- 'DSFeedRow(name: FoldName.of(lead' <<< "$bundle" \
    || echo "BundleRow no longer names itself by its newest member through FoldName"
  grep -q -- 'DSFeedRow(name: FoldName.of(lead' <<< "$strip" \
    || echo "StripRow no longer names itself by its newest member through FoldName"
  grep -q -- 'price17' <<< "$bundle$strip" \
    && echo "a fold draws a price — beside '+N more' it reads as the total"
  grep -q -- 'MoneyClause.stripped(lead)' <<< "$R" \
    || echo "FoldName no longer strips a money clause from the fold's name"
  grep -q -- 'DSFoldLead(source: source)' <<< "$bundle" \
    || echo "BundleRow no longer leads with the fold's stacked mark"

  # Blue is for what you tap.
  grep -q -- 'return isAlarm ? DS.destructive : DS.textPrimary' <<< "$R" \
    || echo "a new row's time is no longer primary ink (the tint is for taps)"
  grep -q -- 'Text(countdown).dsText(.label12).foregroundStyle(DS.tint)' <<< "$R" \
    && echo "the countdown wears the tint again"
  grep -qE -- 'labelHue|legibleInk\(for: thing\.source\) \?\? DS\.textSecondary' <<< "$R" \
    && echo "the line's project clause wears the source's hue again"
  grep -q -- 'Text(p).fontWeight(.medium)' <<< "$R" \
    || echo "the line's project clause is no longer told apart by weight"

  # The door counts, from the window's own walk.
  # BOTH doors — the All feed's and every room's section path.
  local doors
  doors=$(grep -c -- 'if window.more { olderRow(hidden: window.hidden) }' <<< "$F" || true)
  [[ "$doors" == 2 ]] \
    || echo "a Show older door no longer carries the window's hidden count ($doors of 2)"
  grep -q -- 'windowed(split.groups, weight: Self.things(in:))' <<< "$F" \
    || echo "the All feed's window no longer counts a fold as its members"
  grep -q -- 'DSPushRowLabel(title: Text("Show older")' <<< "$F" \
    || echo "Show older is no longer a row in the column"

  # One padding.
  grep -q -- 'static let rowAir: CGFloat = DS.Space.s1' <<< "$F" \
    || echo "rowAir is no longer s1 — the row's own s2 is doubled again"
  local folds
  folds=$(awk '/private func bundleListRow/{p=1} /private func stripListRow/{q=1} p||q{print; n++} n>=80{exit}' <<< "$F")
  grep -q -- 'top: DS.Space.s2' <<< "$folds" \
    && echo "a fold row sits in the old s2 inset"

  # A tail with no line stands in the trailing column.
  grep -q -- 'Spacer(minLength: 0)' <<< "$T" \
    || echo "DSFeedRow's line tail no longer yields to the trailing edge when there is no line"

  # The demo's stream is not poured live.
  grep -q -- 'TwitchIngest.seedDemo(\[\])' <<< "$D" \
    || echo "the demo pours its Twitch stream live again — the live hero takes the cover slot"
}

echo "▶ drift guards"
OUT=$(guards "$ROWS" "$FEED" "$TEMPLATE" "$DEMO")
if [[ -n "$OUT" ]]; then
  print -r -- "$OUT" | sed 's/^/  ✗ /'
  exit 1
fi
echo "  ✓ all drift guards hold"

# ── 3. Mutations: put each regression back, the guards must see it ──────────
echo "▶ mutations"
mutate() {  # label, file-var, perl expression
  local label="$1" which="$2" expr="$3"
  cp "$ROWS" "$TMP/rows.swift"; cp "$FEED" "$TMP/feed.swift"
  cp "$TEMPLATE" "$TMP/template.swift"; cp "$DEMO" "$TMP/demo.swift"
  local target="$TMP/$which.swift"
  cp "$target" "$target.orig"
  perl -0pi -e "$expr" "$target"
  if cmp -s "$target" "$target.orig"; then
    echo "  ✗ mutation '$label' changed nothing — its anchor drifted"; exit 1
  fi
  local got
  got=$(guards "$TMP/rows.swift" "$TMP/feed.swift" "$TMP/template.swift" "$TMP/demo.swift")
  if [[ -z "$got" ]]; then
    echo "  ✗ mutation '$label' SURVIVED"; exit 1
  fi
  echo "  ✓ caught: $label"
}
mutate "new time back in the tint" rows \
  's/return isAlarm \? DS\.destructive : DS\.textPrimary/return isAlarm ? DS.destructive : DS.tint/'
mutate "a fold draws its newest figure" rows \
  's/(struct BundleRow.*?LiveTimeText\(date: newest\))/$1\n            Text("\$1").dsText(.price17)/s'
mutate "a fold names itself by its source again" rows \
  's/(struct StripRow.*?)DSFeedRow\(name: FoldName\.of\(lead, source: source\)/$1DSFeedRow(name: source/s'
mutate "title money ungated" rows \
  's/guard moneyAmount == nil, thing\.priceValue != nil else/guard moneyAmount == nil else/'
mutate "the door forgets its count" feed \
  's/if window\.more \{ olderRow\(hidden: window\.hidden\) \}/if window.more { olderRow(hidden: 0) }/'
mutate "rows doubled again" feed \
  's/static let rowAir: CGFloat = DS\.Space\.s1/static let rowAir: CGFloat = DS.Space.s2/'
mutate "the demo stream live again" demo \
  's/TwitchIngest\.seedDemo\(\[\]\)/TwitchIngest.seedDemo(["demo:twitch:0"])/'

echo "✓ feed grammar holds (prd §900)"
