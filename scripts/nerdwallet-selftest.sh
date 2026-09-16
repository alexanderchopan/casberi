#!/bin/zsh
# Casberi NerdWallet self-test (2026-09-15) — pins the SHIPPED pure logic and
# the design decision behind the seat:
#
#   Casberi/Casberi/Model/NerdWalletBridge.swift
#   Casberi/Casberi/Model/RSSIngest.swift  (FeedParser, extracted — never copied)
#
# WHY THIS EXISTS. The seat is one switch over one feed, and that is a MEASURED
# fact about the publisher, not a simplification anyone chose for convenience.
# Measured 2026-09-15, keylessly:
#
#   • `/blog/feed/` is the only feed — 200, `application/rss+xml`, 10 items.
#   • `/blog/category/<topic>/feed/` answers 301 to the site root, for every
#     topic tried (mortgages, credit-cards, investing, banking, loans,
#     insurance, travel, small-business).
#   • `?cat=<topic>` is accepted, parsed and IGNORED: the filtered and
#     unfiltered documents come back with identical item titles.
#
# That is why the seat is not a `FeedFollowKind`. All five of those watch a
# LIST of names the person supplies; rendering that grammar here would put a
# "follow a publication" field on the page holding exactly one value nobody
# chose — §83's dead control, arriving as a text field. The guards below are
# what make that reasoning survive somebody "improving" the seat into a follow
# list without re-measuring the publisher.
#
# THE OTHER HALF is the honesty fact, and it is the one most likely to rot: the
# name says "wallet" and the shelf says Reading, so the seat must keep saying,
# in words, that it reaches NO account. There is no sign-in, no token and no
# personal data in either direction.
#
# Pure, local, deterministic — no network, no simulator. `--self-test` proves
# each guard catches the mutation it claims to.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/NerdWalletBridge.swift"
PARSER="Casberi/Casberi/Model/RSSIngest.swift"
SCREEN="Casberi/Casberi/Screens/NerdWalletScreen.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"

SELFTEST=0
[[ "${1:-}" == "--self-test" ]] && SELFTEST=1

for f in "$SRC" "$PARSER" "$SCREEN" "$CATALOG" "$REACH" "$REFRESH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
note() { echo "  ✗ $1"; fail=1; }
ok()   { echo "  ✓ $1"; }

# The negative guards read a COMMENT-STRIPPED copy: the source DOCUMENTS these
# decisions by naming the shapes they rule out ("that is why this is NOT a
# FeedFollowKind"), so a guard grepping raw source fires against the prose
# explaining it. Earned on the Obsidian, Cursor and RSS harnesses.
STRIPPED="$WORK/stripped.swift"
sed -e 's:^[[:space:]]*//.*$::' -e 's:^[[:space:]]*///.*$::' "$SRC" > "$STRIPPED"
SCREEN_STRIPPED="$WORK/screen.swift"
sed -e 's:^[[:space:]]*//.*$::' -e 's:^[[:space:]]*///.*$::' "$SCREEN" > "$SCREEN_STRIPPED"

# --- guard 1: ONE feed, and it is the measured one --------------------------
grep -q 'nerdwallet.com/blog/feed/' "$STRIPPED" \
  || note "the feed URL changed — re-measure the publisher before trusting a new one"
[[ $(grep -c 'https://www.nerdwallet.com' "$STRIPPED") -le 3 ]] \
  || note "more than one NerdWallet URL is fetched — the seat is one feed (see the header)"

# --- guard 2: the seat did not grow a follow list ---------------------------
grep -qE 'FeedFollowStore|FeedFollowKind|FeedFollowEntry' "$STRIPPED" \
  && note "the seat grew a follow list — the publisher has no per-topic feeds (measured); see the header"

# --- guard 3: a 304 is REACHED, not failed ----------------------------------
# `notModified -> 0` and `failed -> nil` is what keeps a healthy quiet feed
# from reading as a broken bridge. Collapsing them is invisible to a build.
grep -q 'case .notModified:     return 0' "$STRIPPED" \
  || note "a 304 no longer returns 0 — a quiet feed will read as unreachable"
grep -q 'case .failed:          return nil' "$STRIPPED" \
  || note "a failed fetch no longer returns nil — an unreachable feed will read as 'Up to date' (§83)"

# --- guard 4: the root element decides, never the item count ----------------
grep -q 'guard parsed.isFeed else' "$STRIPPED" \
  || note "the feed check is no longer on the root element — an HTML error page parses with a title"

# --- guard 5: the dedupe key survives a retitle -----------------------------
# NerdWallet re-titles its rate-tracker posts every weekday; keying on the link
# alone would be fine, keying on the TITLE would land a duplicate a day.
grep -q 'item.guid.isEmpty ? item.link : item.guid' "$STRIPPED" \
  || note "the dedupe key is no longer guid-then-link — a retitled post will land twice"
grep -q 'refPrefix = "nerdwallet:"' "$STRIPPED" \
  || note "the ref prefix changed — already-landed rows will re-land as duplicates"

# --- guard 6: turning it off forgets the HTTP record ------------------------
grep -q 'FeedFreshness.forget' "$STRIPPED" \
  || note "stopFollowing no longer forgets the feed's HTTP record — a reconnect gets a 304 for a body it no longer holds"

# --- guard 7: the honesty sentence stays, and stays true --------------------
grep -qi 'no sign-in' "$SCREEN_STRIPPED" \
  || note "the screen no longer says there is no sign-in — the seat's name invites the opposite reading"
grep -qE 'TokenVault|WKWebView|Authorization|bearer' "$STRIPPED" "$SCREEN_STRIPPED" \
  && note "the seat gained a credential — then 'No sign-in, and nothing here reads your money' is a lie (§83)"

# --- guard 8: the catalog and the registry agree ----------------------------
grep -q '"NerdWallet"' "$CATALOG" \
  || note "NerdWallet left the catalog but the seat is still here"
# WALLET since §780c (user: "acorns and rocket and nerd go in wallet"),
# reversing §780's Reading placement. The original guard read the other way and
# said "a money shelf promises the account this seat has no door to" — a fair
# design argument the user overruled: a person looking for their finance apps
# looks in one place. What still has to hold is the honesty half, and that is
# the TAGLINE — "news", not a balance — which is checked below. A red guard
# after a ruling is a guard to amend, not delete.
grep -q 'group: "Wallet"' <(grep 'Offer(name: "NerdWallet"' "$CATALOG") \
  || note "NerdWallet left the Wallet shelf — §780c put all three finance seats on one shelf"
grep -qi 'news' <(grep 'Offer(name: "NerdWallet"' "$CATALOG") \
  || note "NerdWallet's tagline no longer says 'news' — on a money shelf that word is what keeps it honest (§780c)"
grep -q 'www.nerdwallet.com' "$REACH" \
  || note "the host left NetworkReach — it is fetched on every foreground (ship gate, prd §205)"
grep -q 'NerdWalletIngest.refresh' "$REFRESH" \
  || note "the seat is no longer swept on foreground — it will only sync when its own page is opened"

# --- the parse, against the real document's shape ---------------------------
{ echo "import Foundation"; awk '/^enum FeedParser \{/,0' "$PARSER"; } > "$WORK/parser.swift"
grep -q 'var isFeed: Bool' "$WORK/parser.swift" || { echo "✗ could not extract FeedParser"; exit 1; }

cat > "$WORK/stub.swift" <<'STUB'
import Foundation
enum IngestSupport {
    static func decodeHTMLEntities(_ s: String) -> String {
        var t = s
        for (e, c) in [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),
                       ("&#8217;","\u{2019}"),("&#8230;","\u{2026}")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        return t
    }
    static func imageURL(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }; return raw
    }
}
STUB

# A trimmed copy of the real document's STRUCTURE (2026-09-15) — the element
# set and namespaces exactly as the publisher sends them, with the bodies cut
# to a few words. What is asserted is shape, never content.
cat > "$WORK/fixture.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
  <title>NerdWallet</title>
  <link>https://www.nerdwallet.com</link>
  <item>
    <title>Mortgage Rates Today, Tuesday, September 15</title>
    <link>https://www.nerdwallet.com/article/mortgages/rates-0915</link>
    <dc:creator><![CDATA[Kate Wood]]></dc:creator>
    <pubDate>Tue, 15 Sep 2026 13:00:38 +0000</pubDate>
    <guid isPermaLink="false">https://www.nerdwallet.com/?p=100001</guid>
    <description><![CDATA[Mortgage rates eased a little today across most loan terms.]]></description>
    <content:encoded><![CDATA[<p>Mortgage rates eased a little today across most loan terms, and here is the fuller body that the parser should prefer over the shorter description above.</p>]]></content:encoded>
  </item>
  <item>
    <title>Mortgage Rates Today, Monday, September 14</title>
    <link>https://www.nerdwallet.com/article/mortgages/rates-0914</link>
    <dc:creator><![CDATA[Kate Wood]]></dc:creator>
    <pubDate>Mon, 14 Sep 2026 12:43:06 +0000</pubDate>
    <guid isPermaLink="false">https://www.nerdwallet.com/?p=100002</guid>
    <description><![CDATA[Mortgage rates climbed back over seven percent today.]]></description>
  </item>
  <item>
    <title>A house post with no byline</title>
    <link>https://www.nerdwallet.com/article/finance/house</link>
    <dc:creator><![CDATA[NerdWallet]]></dc:creator>
    <pubDate>Sun, 13 Sep 2026 09:00:00 +0000</pubDate>
    <guid isPermaLink="false">https://www.nerdwallet.com/?p=100003</guid>
    <description><![CDATA[A house-written explainer with no named author on it.]]></description>
  </item>
  <item>
    <title>A post whose feed body is only a markup scrap</title>
    <link>https://www.nerdwallet.com/article/finance/scrap</link>
    <pubDate>Sat, 12 Sep 2026 09:00:00 +0000</pubDate>
    <guid isPermaLink="false">https://www.nerdwallet.com/?p=100004</guid>
    <description><![CDATA[&nbsp;]]></description>
  </item>
</channel>
</rss>
XML

cat > "$WORK/main.swift" <<'MAIN'
import Foundation

let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let parsed = FeedParser.parse(data)
var bad = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ✓ \(what)" : "  ✗ \(what)"); if !ok { bad += 1 }
}

check(parsed.isFeed, "the document is read as a feed (root=\(parsed.root))")
check(parsed.title == "NerdWallet", "the feed names itself — the row's trailing label")
check(parsed.items.count == 4, "every item is seen (\(parsed.items.count))")

// Every field NerdWalletIngest reads off an item. A publisher dropping one is
// silent: the row just lands emptier.
check(parsed.items.allSatisfy { !$0.guid.isEmpty }, "every item has a guid — the retitle-proof dedupe key")
check(parsed.items.allSatisfy { !$0.link.isEmpty }, "every item is openable")
check(parsed.items.allSatisfy { $0.date != nil }, "every item is dated — otherwise it lands stamped .now")
check(parsed.items.allSatisfy { !$0.title.isEmpty }, "every item is titled — the ingest drops untitled ones")
check(parsed.items.prefix(3).allSatisfy { !$0.summary.isEmpty }, "every real item has words for the sheet")
// The LONGEST candidate wins: this feed carries both a short <description> and
// a full <content:encoded>, and the fuller one is the better read.
check(parsed.items[0].summary.contains("fuller body"),
      "the fuller content:encoded beats the shorter description")
// Anything under 20 characters is dropped as a markup scrap, by design — which
// is why a fixture with three-word bodies reads as a parser failure. Item 4
// carries exactly that, and must land with no summary rather than a scrap.
check(parsed.items[3].summary.isEmpty,
      "a sub-20-character body is dropped as a markup scrap, not shown as words")

// The byline rule: an author that only repeats the publication is dropped, so
// a house post is not filed as a person called NerdWallet.
let kept = parsed.items.map { FeedParser.author($0.author, feedName: parsed.title) }
check(kept[0] == "Kate Wood", "a real byline is kept (\(kept[0] ?? "nil"))")
check(kept[2] == nil, "a house post's byline is dropped, not filed as a person")

print(bad == 0 ? "  parse: ok" : "  parse: \(bad) failed")
exit(bad == 0 ? 0 : 1)
MAIN

swiftc -O "$WORK/parser.swift" "$WORK/stub.swift" "$WORK/main.swift" -o "$WORK/run" 2>"$WORK/swiftc.log" \
  || { echo "✗ could not compile the extracted parser:"; tail -5 "$WORK/swiftc.log"; exit 1; }
"$WORK/run" "$WORK/fixture.xml" || fail=1

# --- the self-test: every guard above must catch its own mutation -----------
if (( SELFTEST )); then
  echo "  — self-test —"
  probe() {  # probe <name> <file> <sed-expr> ; expects the run to FAIL
    local name="$1" target="$2" expr="$3"
    local sandbox="$WORK/sandbox"
    rm -rf "$sandbox"; mkdir -p "$sandbox"
    # A COPY of the tree, never the tracked file: a concurrent session's
    # `git add -A` would otherwise commit the mutation (see the repo's memory).
    cp -R Casberi scripts "$sandbox/" 2>/dev/null
    sed -i '' "$expr" "$sandbox/$target"
    if ( cd "$sandbox" && zsh scripts/nerdwallet-selftest.sh >/dev/null 2>&1 ); then
      echo "  ✗ self-test: '$name' was NOT caught"; fail=1
    else
      echo "  ✓ catches $name"
    fi
  }
  probe "the seat growing a follow list" "$SRC" \
        's|static let source = "NerdWallet"|static let source = "NerdWallet"\
    static let store = FeedFollowStore.substack|'
  probe "a 304 collapsing into a failure" "$SRC" \
        's|case .notModified:     return 0|case .notModified:     return nil|'
  probe "the dedupe key falling back to the title" "$SRC" \
        's|item.guid.isEmpty ? item.link : item.guid|item.title|'
  probe "the seat gaining a credential" "$SRC" \
        's|static let apiHostless = 0||; s|enum NerdWalletIngest {|enum NerdWalletIngest {\
    static let token = TokenVault.get("x")|'
  probe "the honesty sentence going missing" "$SCREEN" \
        's|No sign-in, and nothing here reads your money.|Connected.|'
fi

if (( fail )); then
  echo "nerdwallet-selftest: FAILED"
  exit 1
fi
echo "nerdwallet-selftest: ok"
