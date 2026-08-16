#!/bin/zsh
# Casberi RSS discovery self-test — verifies the SHIPPED pure logic behind
# "is this address a feed?" (2026-08-16):
#
#   Casberi/Casberi/Model/RSSIngest.swift
#     — FeedParser.Parsed.root / .isFeed  (the discriminator EVERYTHING hangs off)
#     — RSSStore.normalized               (what a pasted string is followed as)
#
# WHY THIS EXISTS. A user followed https://verse.works/releases and reported
# that they could add two feeds and then it "froze". Measured that day: the
# site declares no `<link rel="alternate">` and answers HTTP 200 with an
# ordinary web page for EVERY conventional feed path (`/feed`, `/rss`,
# `/feed.xml`, …) — a soft 404, which every SPA-routed site is. Three defects
# fell out of it, and all three are invisible to a build, a screen sweep and a
# landed count:
#
#   • the follow read as PERFECTLY HEALTHY forever — 200, zero failures, and
#     nothing to land, so the row said nothing and the screen said "Up to
#     date" about an address that can never produce a post (§83 fake status);
#   • autodiscovery ran when a body carried no ITEMS, so a real-but-empty feed
#     sent an eight-request crawl off its host on every single refresh; and
#   • the crawl's verdict lived in a per-launch `Set`, so every cold start paid
#     the whole crawl again for a follow already proved dead.
#
# THE TRAP THIS PINS, and the reason the check is on the ROOT ELEMENT rather
# than on the title or the item count: `XMLParser` walks a good way into an
# HTML document before it gives up (measured on that page — 271 elements and
# 73,137 characters before NSXMLParserErrorDomain 41), so a web page arrives
# from `FeedParser.parse` carrying a populated `title` — the page's own
# headline. Any discriminator that trusts the title would adopt a web page's
# `<h1>` as the feed's name on a follow that is not a feed at all. Fixture 2
# asserts that title really is populated, so this stays a demonstrated fact and
# not a remembered one.
#
# `RSSIngest.swift` cannot compile as shipped (it builds `Thing`, a SwiftData
# model, and calls `IngestSupport`), so `FeedParser` and `RSSStore` are
# EXTRACTED from the shipped source — never copied into this file — so the
# harness cannot pass against logic the app doesn't run. `IngestSupport` is
# stubbed inert.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/RSSIngest.swift"
FRESH="Casberi/Casberi/Model/FeedFreshness.swift"
SCREEN="Casberi/Casberi/Screens/RSSScreen.swift"
for f in "$SRC" "$FRESH" "$SCREEN"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring the extracted types can't prove on their own. A perfect `isFeed` is
# worthless if the ingest goes on gating discovery with `items.isEmpty`.
#
# The negative guards read a COMMENT-STRIPPED copy: the source DOCUMENTS these
# fixes by naming the broken shapes they replaced ("gated on ... rather than on
# it carrying no items", "the check used to be 'did it parse any items'"), so a
# guard grepping raw source fires against the prose explaining it. Earned on
# the Obsidian and Cursor harnesses; earned again here on this one's first run.
STRIPPED="$WORK/stripped.swift"
sed -e 's:^[[:space:]]*//.*$::' -e 's://[^"]*$::' "$SRC" > "$STRIPPED"

grep -q 'if !parsed.isFeed {' "$STRIPPED" \
  || { echo "✗ RSSIngest no longer gates autodiscovery on isFeed — a real-but-empty feed will crawl its host every pass"; exit 1; }
grep -q 'parsed.items.isEmpty,$' "$STRIPPED" \
  && { echo "✗ the old items-based discovery gate is back — see Parsed.isFeed"; exit 1; }

# The crawl must stay BOUNDED. Both halves matter and they bound different
# things: the per-request timeout caps one stalled candidate, the budget caps
# the eight of them tried in a row. `RSSIngest.running` and the RSS screen's
# `syncing` flag are held for that whole stretch, which is what made a slow
# site look like a frozen bridge.
grep -q 'request.timeoutInterval = probeTimeout' "$STRIPPED" \
  || { echo "✗ FeedDiscovery.fetch no longer sets a timeout — a stalled host costs 60s per candidate"; exit 1; }
grep -q 'crawlBudget' "$STRIPPED" \
  || { echo "✗ FeedDiscovery lost its total crawl budget"; exit 1; }
grep -q 'if !ranOut {' "$STRIPPED" \
  || { echo "✗ FeedDiscovery may now record a no-feed verdict from a crawl it cut short — a bad minute of network would mute a good address for a week"; exit 1; }

# The verdict must be DURABLE, or every cold launch re-crawls a dead follow.
grep -q 'noFeedAt' "$FRESH" \
  || { echo "✗ FeedFreshness lost the no-feed verdict — the crawl result is per-launch again"; exit 1; }
grep -q 'FeedFreshness.noteFeedFound' "$STRIPPED" \
  || { echo "✗ nothing clears the no-feed verdict — a site that later adds a feed would wait out noFeedRecheckAfter"; exit 1; }

# The screen must SAY why a follow was refused, and must not drop a follow made
# while another pass is in flight. Both are half of the reported symptom.
grep -q 'waitForInFlight' "$SCREEN" \
  || { echo "✗ RSSScreen no longer asks its sync to wait — a feed followed mid-sweep is silently never read"; exit 1; }
grep -q 'You already follow that' "$SCREEN" \
  || { echo "✗ a refused follow says nothing again — the FOLLOW button reads as dead"; exit 1; }
grep -q 'noFeedFound' "$SCREEN" \
  || { echo "✗ RSSScreen no longer reports an address with no feed — it will read as 'Up to date'"; exit 1; }

# --- extract ----------------------------------------------------------------
# `FeedParser` runs to the end of the file; `RSSStore` is the leading class.
{ echo "import Foundation"; awk '/^enum FeedParser \{/,0' "$SRC"; } > "$WORK/parser.swift"
{ echo "import Foundation"
  awk '/^final class RSSStore \{/,/^\}$/' "$SRC" | sed 's/^@Observable$//'
} > "$WORK/store.swift"
[[ -s "$WORK/parser.swift" ]] || { echo "✗ could not extract FeedParser"; exit 1; }
[[ -s "$WORK/store.swift"  ]] || { echo "✗ could not extract RSSStore"; exit 1; }
grep -q 'var isFeed: Bool' "$WORK/parser.swift" || { echo "✗ extraction missed Parsed.isFeed"; exit 1; }
grep -q 'func normalized' "$WORK/store.swift"   || { echo "✗ extraction missed RSSStore.normalized"; exit 1; }

cat > "$WORK/stubs.swift" <<'SWIFT'
import Foundation

// Inert. `FeedParser` calls these for cosmetics only; nothing this harness
// asserts depends on what they return, and stubbing them keeps every ordering
// below the shipped parser's own.
enum IngestSupport {
    static func decodeHTMLEntities(_ s: String) -> String { s }
}
enum FeedFreshness {
    static func forget(_ url: String) {}
}

// `remove(atOffsets:)` ships in SwiftUI, which this harness deliberately does
// not link. Nothing asserted below removes a feed; this exists only so the
// extracted store compiles as written.
extension RangeReplaceableCollection where Self: MutableCollection, Index == Int {
    mutating func remove(atOffsets offsets: IndexSet) {
        for i in offsets.sorted(by: >) where indices.contains(i) {
            remove(at: i)
        }
    }
}
SWIFT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

// FIRST, before anything touches `RSSStore.shared` — the store persists to
// `UserDefaults.standard`, and a command-line tool's domain is keyed by its
// PROCESS NAME, which is the same on every run even though the binary sits in
// a fresh temp directory each time. So run 1 left "verse.works" followed and
// run 2 failed on `add`, reporting a defect in code that was correct. Cleared
// on the way out too, so the harness leaves nothing behind.
let storeKey = "rss.feeds"
UserDefaults.standard.removeObject(forKey: storeKey)
defer { UserDefaults.standard.removeObject(forKey: storeKey) }

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if !ok { print("✗ \(label)"); failures += 1 }
}

// ── Fixture 1: RSS 2.0, with items. The ordinary case. ─────────────────────
let rss = """
<?xml version="1.0"?>
<rss version="2.0"><channel><title>Overreacted</title>
<item><title>Post</title><link>https://example.com/a</link></item>
</channel></rss>
"""
let p1 = FeedParser.parse(Data(rss.utf8))
check("rss root", p1.root == "rss")
check("rss isFeed", p1.isFeed)
check("rss items", p1.items.count == 1)

// ── Fixture 2: an HTML page. THE case this whole change is about. ──────────
// The `<title>` assertion is not decoration: it is the demonstration that a
// title-based discriminator would name a follow after a web page's headline.
//
// Shaped from the REAL page, and it had to be. The first cut of this fixture
// put `<meta charset>` above `<title>` — and because `<meta>` never closes,
// `XMLParser` nests everything after it one level deeper, past the
// `elementPath.count <= 3` guard, so the title came back EMPTY and this
// assertion failed against a parser that was behaving exactly as described.
// Measured on the shipped parser against the actual 1.3MB verse.works body
// (2026-08-16): `root=html isFeed=false items=0 title=[Releases | Verse]`.
// That string is what the RSS ledger row displayed as the feed's name.
let html = """
<!DOCTYPE html><html lang="en"><head><title>Releases | Verse</title>
<meta charset="utf-8">
<link rel="icon" href="/favicon.ico">
<link rel="preload" href="/_next/static/chunk.js" as="script">
</head><body><main><h1>Releases</h1></main></body></html>
"""
let p2 = FeedParser.parse(Data(html.utf8))
check("html root is html", p2.root == "html")
check("html is NOT a feed", !p2.isFeed)
check("html has no items", p2.items.isEmpty)
// If this ever goes false the trap has moved, not gone — read the header.
check("html DOES carry a title (why title can't be the discriminator)",
      !p2.title.isEmpty)

// ── Fixture 3: Atom. ───────────────────────────────────────────────────────
let atom = """
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>A blog</title>
<entry><title>Entry</title><link href="https://example.com/e"/></entry>
</feed>
"""
let p3 = FeedParser.parse(Data(atom.utf8))
check("atom root", p3.root == "feed")
check("atom isFeed", p3.isFeed)

// ── Fixture 4: RSS 1.0, whose root is <rdf:RDF>. ───────────────────────────
// Namespace processing is OFF, so the name arrives qualified and `isFeed` has
// to strip the prefix. Dropping that strip silently un-follows every RSS 1.0
// feed — it would be crawled as if it were a web page.
let rdf = """
<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns="http://purl.org/rss/1.0/"><channel><title>Old school</title></channel>
<item><title>Item</title><link>https://example.com/i</link></item></rdf:RDF>
"""
let p4 = FeedParser.parse(Data(rdf.utf8))
check("rdf root is qualified", p4.root == "rdf:RDF")
check("rdf isFeed", p4.isFeed)

// ── Fixture 5: a VALID feed with nothing posted yet. ───────────────────────
// The regression the item-count gate caused: this is a real feed, and treating
// it as a site sent an eight-request crawl off its host on every refresh,
// forever, for a blog that simply hadn't published.
let empty = """
<?xml version="1.0"?>
<rss version="2.0"><channel><title>Brand new</title></channel></rss>
"""
let p5 = FeedParser.parse(Data(empty.utf8))
check("empty feed has no items", p5.items.isEmpty)
check("empty feed IS still a feed", p5.isFeed)

// ── Fixture 6: unparseable bytes name no root, so nothing is claimed. ──────
let junk = FeedParser.parse(Data("not xml at all".utf8))
check("junk root empty", junk.root.isEmpty)
check("junk is not a feed", !junk.isFeed)

// ── Fixture 7: an XML document that is not a feed. ─────────────────────────
// A sitemap sitting at a guessed path must not be adopted as one.
let sitemap = FeedParser.parse(Data("""
<?xml version="1.0"?><urlset><url><loc>https://example.com/</loc></url></urlset>
""".utf8))
check("sitemap is not a feed", !sitemap.isFeed)

// ── RSSStore.normalized — what a pasted string is followed AS. ─────────────
let store = RSSStore.shared
check("bare domain gains a scheme",
      store.normalized("verse.works") == "https://verse.works")
check("whitespace trimmed",
      store.normalized("  https://example.com/feed  ") == "https://example.com/feed")
check("an http address is left alone",
      store.normalized("http://example.com/rss") == "http://example.com/rss")
check("empty is refused", store.normalized("   ") == nil)
check("a space inside is refused", store.normalized("https://exa mple.com/feed") == nil)
// A scheme with no host is the shape a half-pasted address takes, and it used
// to be followed happily and fail forever with nothing said.
check("scheme with no host is refused", store.normalized("https://") == nil)

check("isFollowing is false on an empty list", !store.isFollowing("example.com"))
check("add accepts", store.add("verse.works"))
check("isFollowing matches the NORMALIZED form, not the typed one",
      store.isFollowing("verse.works") && store.isFollowing("https://verse.works"))
check("a second add of the same address is refused", !store.add("https://verse.works"))
check("a refused add did not grow the list", store.feeds.count == 1)

if failures == 0 {
    print("✓ RSS discovery self-test passed")
} else {
    print("\(failures) failure(s)")
    exit(1)
}
SWIFT

# `|| true` on the pipeline, not decoration: this script runs `set -euo
# pipefail`, and on a SUCCESSFUL compile `grep` matches nothing and exits 1,
# which pipefail hands to `set -e` — so a clean build is what would kill the
# run. Cost one confused minute here; it is the same trap CLAUDE.md records
# between verify.sh and verify-mac.sh.
{ swiftc -O -enable-bare-slash-regex \
    "$WORK/stubs.swift" "$WORK/parser.swift" "$WORK/store.swift" "$WORK/main.swift" \
    -o "$WORK/rsstest" 2>&1 | grep -v "^$" | head -20 ; } || true
[[ -x "$WORK/rsstest" ]] || { echo "✗ harness did not compile — an extraction has drifted"; exit 1; }
"$WORK/rsstest"
