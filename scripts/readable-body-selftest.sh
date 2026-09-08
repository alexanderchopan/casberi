#!/bin/zsh
# Casberi readable-body self-test — the extractor that turns a saved page into
# the words the sheet draws (prd §645 pass 5, 2026-09-08).
#
#   Casberi/Casberi/Model/ReadableParse.swift  — the whole parse
#   Casberi/Shared/ReadableBody.swift          — the character bound
#
# Both are Foundation-only BY DESIGN and are compiled WHOLE AND UNMODIFIED
# here. `IngestSupport.decodeHTMLEntities` is stubbed as identity — it is a
# shared utility with its own callers, and entity decoding is not this file's
# subject.
#
# WHY THIS FILE EXISTS AT ALL, AND WHY IT DID NOT BEFORE. These functions were
# `private` inside `LinkTitle.swift`, which imports SwiftData and reaches
# `Thing`, `OEmbed` and `ProductMeta` — so nothing on this machine could
# compile them, and every claim about what the app extracts was a claim.
# §645 pass 1 put their output on the thing sheet at `reading20`, and pass 5
# moved the two constants that bound it. Extracting the parse was the price of
# being able to check either.
#
# WHY A HARNESS. Every failure here renders as a perfectly ordinary sheet
# holding the wrong words, and none is visible to a build or a screen sweep:
#
#   • the cap re-applied at a lede's length, so every article ends in "…"
#     mid-sentence — the exact state pass 5 fixed, and the one that would look
#     completely normal to anyone who had not read a long piece in the app;
#   • the paragraph limit dropped back to a handful, which does NOT protect the
#     excerpt from chrome but guarantees it (see the fixtures: a real news
#     page's first six `<p>`s are share rows and topic-subscribe blurbs, and
#     the article's first sentence is paragraph nine);
#   • the content-region narrowing removed, so a page WITH a `<main>` is read
#     from its navigation down;
#   • the prose test dropped, so menu `<p>`s ("About · Search · Log in") join
#     the body;
#   • `<script>` stripping dropped, so a page's inline JavaScript is drawn as
#     an article at `reading20`.
#
# WHAT THIS CANNOT PROVE, stated rather than implied. Whether a REAL page's
# markup yields prose — the fixtures below are shaped from real pages measured
# for the §645 amendment (fifteen of them, over the network, which no harness
# here may do) but they are still fixtures. And nothing here renders anything:
# how 8,000 characters SIT under a preview card is a device question.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PARSE="Casberi/Casberi/Model/ReadableParse.swift"
BOUND="Casberi/Shared/ReadableBody.swift"
ARTICLE="Casberi/Casberi/Model/FeedArticleText.swift"
SHARE="Casberi/ShareExtension/ShareViewController.swift"
for f in "$PARSE" "$BOUND" "$ARTICLE" "$SHARE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/readable-body-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# ONE bound for two processes. The app and the share extension are separate
# binaries clamping the same column, and since pass 1 both are DRAWN — a
# literal in either is the same article read at two lengths depending on
# whether you pasted it or shared it.
grep -q 'ReadableBody.limit' "$SHARE" \
  || { echo "✗ the share extension no longer uses ReadableBody.limit — a shared"; \
       echo "  link and a pasted link would draw the same article at two lengths"; exit 1; }
python3 - "$SHARE" <<'PY' || exit 1
import re, sys
src = "\n".join(l for l in open(sys.argv[1]).read().splitlines()
                if not l.strip().startswith("//"))
if re.search(r"enrichedText\s*=\s*String\(body\.prefix\(\s*\d", src):
    print("✗ the share extension clamps enrichedText with a LITERAL again")
    sys.exit(1)
PY
grep -q 'ReadableBody.limit' "$PARSE" \
  || { echo "✗ ReadableParse no longer uses the shared bound"; exit 1; }

# WHICH HOSTS A SCRAPE IS FAIR ON (prd §645 pass 5 item 4). The rule is a long
# doc comment on `FeedArticleText`, and a rule with no guard is a rule that
# gets re-broken — this repo's own standing finding. Two halves, both read from
# a COMMENT-STRIPPED copy, because that doc names every abstention it excludes.
check_article() {
  local article="$1" label="$2" nc
  nc=$(mktemp "$TMP/article.XXXXXX")
  python3 - "$article" > "$nc" <<'PY'
import re, sys
src = re.sub(r"/\*.*?\*/", "", open(sys.argv[1]).read(), flags=re.S)
print("\n".join(l for l in src.splitlines() if not l.strip().startswith("//")))
PY
  local line
  line=$(grep 'static let sources' "$nc" || true)
  if [[ -z "$line" ]]; then
    echo "✗ ${label}: FeedArticleText.sources is gone — membership is the one"
    echo "  thing that keeps a scrape off a host nobody chose"; return 1
  fi
  # The three abstentions. Each passes the fairness rule and abstains for its
  # OWN stated reason (a watch page, strangers' comments, a player) — so each
  # is a separate decision and a wholesale widening must not quietly take them.
  local seat
  for seat in YouTube Reddit Podcasts; do
    if print -r -- "$line" | grep -q "\"$seat\""; then
      echo "✗ ${label}: $seat is back in FeedArticleText.sources — its page is"
      echo "  not an article, and the type doc says why in its own words"
      return 1
    fi
  done
  # Membership stays a NAMED list. "any http URL" is the shape §5.3 forbids.
  if print -r -- "$line" | grep -qE 'Set<String>\(\)|allCases|\.isEmpty'; then
    echo "✗ ${label}: FeedArticleText.sources stopped being a named list"
    return 1
  fi
  # The receipts label travels with the row. It used to be re-derived after the
  # fetch with a fallback to "RSS", which was harmless while every member was a
  # feed and is a WRONG DISCLOSURE now that a bookmark is one.
  if grep -q '?? "RSS"' "$nc"; then
    echo "✗ ${label}: the sweep falls back to \"RSS\" when it labels a reach —"
    echo "  a scrape of somebody's saved page would be filed on the receipts"
    echo "  screen under a bridge they may not have connected"
    return 1
  fi
  grep -q 'return (ref, url, thing.source)' "$nc" || {
    echo "✗ ${label}: the sweep no longer carries each row's own source into"
    echo "  the fetch loop"; return 1; }
  return 0
}
check_article "$ARTICLE" "the shipped tree" || exit 1
echo "the fairness rule"
echo "  ✓ sources is a named list, and the three abstentions are still out"
echo "  ✓ each reach is labelled with its own row's source"

# --- the driver -------------------------------------------------------------
cat > "$TMP/stub.swift" <<'SWIFT'
import Foundation
enum IngestSupport { static func decodeHTMLEntities(_ s: String) -> String { s } }
SWIFT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func p(_ s: String) -> String { "<p>\(s)</p>" }
/// A paragraph long enough to survive the 24-character floor and carrying a
/// period, which is the prose test.
func prose(_ n: Int, _ word: String = "sentence") -> String {
    p("This is paragraph \(n), a real \(word) of running text with a full stop.")
}

// ── the cap: an article longer than the old 1,200 arrives WHOLE ────────────
// THE MUTATION THAT MATTERS (docs/reading-spec.md A.5): a fixture whose
// article is longer than the old cap, asserting the text does NOT end in "…".
print("the cap")
let longArticle = "<html><body><main>"
    + (1...30).map { prose($0) }.joined()
    + "</main></body></html>"
let long = ReadableParse.parseReadable(in: longArticle) ?? ""
check("an article past the old 1,200 is not truncated",
      long.count > 1200 && !long.hasSuffix("…"))
check("…and it really is longer than the old cap", long.count > 1200)
check("paragraph 20 is present, which six paragraphs could never reach",
      long.contains("paragraph 20"))
// The bound still bounds. A page that runs past it is cut, and says so.
let hugeArticle = "<html><body><main>"
    + (1...400).map { prose($0) }.joined()
    + "</main></body></html>"
let huge = ReadableParse.parseReadable(in: hugeArticle) ?? ""
check("a pathological page is still cut at the bound",
      huge.count == ReadableBody.limit + 1 && huge.hasSuffix("…"))

// ── leading chrome: the finding that inverted A.5's premise ────────────────
// A real news page spends its first paragraphs on share rows and
// topic-subscribe blurbs and reaches its first sentence at paragraph nine.
// A six-paragraph limit does not protect the excerpt from that — it
// guarantees the excerpt is nothing BUT that.
print("\nleading chrome is displaced, not concentrated")
let chromeThenArticle = "<html><body><main>"
    + (1...8).map { _ in p("News Close News Posts from this topic will be added to your daily email digest and your homepage feed.") }.joined()
    + (1...6).map { prose($0, "paragraph of the actual story") }.joined()
    + "</main></body></html>"
let mixed = ReadableParse.parseReadable(in: chromeThenArticle) ?? ""
check("the story's own words are reached", mixed.contains("paragraph 1"))
check("…and its later paragraphs too", mixed.contains("paragraph 6"))
// The de-dupe means the eight identical chrome blocks collapse to one, which
// is the other half of why a wider limit reads better rather than worse.
check("repeated chrome collapses to one copy",
      mixed.components(separatedBy: "daily email digest").count - 1 == 1)

// ── contentRegion: narrowing, and what happens when it misses ──────────────
print("\ncontentRegion")
let withMain = "<html><body><nav>" + p("About Search Log in Subscribe now today.")
    + "</nav><main>" + prose(1) + "</main></body></html>"
check("a page WITH <main> is read from the marker down",
      (ReadableParse.parseReadable(in: withMain) ?? "").contains("paragraph 1"))
check("…and its navigation is not in the body",
      !(ReadableParse.parseReadable(in: withMain) ?? "").contains("Log in Subscribe"))
check("<article> is a marker too",
      ReadableParse.contentRegion("<html><body><nav>x</nav><article>y</article></body></html>")
        .hasPrefix("<article"))
check("role=\"main\" is a marker too",
      ReadableParse.contentRegion("<html><nav>x</nav><div role=\"main\">y</div></html>")
        .contains("role=\"main\""))
// THE MISS, stated as a test rather than as a comment: no marker means the
// whole page, so a wider paragraph limit admits whatever the footer holds.
// This is the known cost of pass 5 and the reason it is asserted here.
let noMarker = "<html><body>" + (1...4).map { prose($0) }.joined()
    + p("This is a link post by somebody, posted on the sixth of September.")
    + "</body></html>"
check("no marker returns the WHOLE page",
      ReadableParse.contentRegion(noMarker) == noMarker)
check("…so a trailing footer line does reach the body — the known cost",
      (ReadableParse.parseReadable(in: noMarker) ?? "").contains("link post by somebody"))

// ── the prose test and the script strip ───────────────────────────────────
print("\nchrome is dropped, code is never drawn")
let menu = "<html><body><main>"
    + p("About Search Log in Newsletter Careers Advertise Contact") + prose(1)
    + "</main></body></html>"
check("a menu paragraph with no sentence is dropped",
      !(ReadableParse.parseReadable(in: menu) ?? "").contains("Careers Advertise"))
// The real shape: a script INSIDE a paragraph. `paragraphs` strips inner
// tags, so without the script strip the code between them survives as prose.
let scripted = "<html><body><main>"
    + p("The story begins here. <script>var a = 1; alert(\"gotcha\");</script> And continues.")
    + prose(1) + "</main></body></html>"
check("inline script never reaches the body",
      !(ReadableParse.parseReadable(in: scripted) ?? "").contains("gotcha"))
check("…and the paragraph around it survives",
      (ReadableParse.parseReadable(in: scripted) ?? "").contains("The story begins here"))
check("a page whose only text is under the 24-char floor returns nil",
      ReadableParse.parseReadable(in: "<html><body><main>" + p("Too short.")
                                      + "</main></body></html>") == nil)
// Between the two floors on purpose: 30 characters clears the per-piece
// floor of 24 and falls under the whole-body floor of 40, so only the SECOND
// guard can reject it. A fixture that fails both tests neither.
let scrap = "<html><body><main>" + p("A short but real sentence here.")
    + "</main></body></html>"
check("a page whose whole body is one scrap returns nil",
      ReadableParse.parseReadable(in: scrap) == nil)

// ── the meta description leads, and is not repeated ───────────────────────
print("\nthe meta description")
let dupeDesc = "<html><head><meta name=\"description\" content=\"This is paragraph 1, a real sentence of running text with a full stop.\">"
    + "</head><body><main>" + prose(1) + prose(2) + "</main></body></html>"
let dd = ReadableParse.parseReadable(in: dupeDesc) ?? ""
check("a description repeating the first paragraph appears once",
      dd.components(separatedBy: "paragraph 1,").count - 1 == 1)
check("…and the rest of the article still follows", dd.contains("paragraph 2"))

// ── a paywall teaser ──────────────────────────────────────────────────────
print("\na paywall teaser is whatever the page gave, and nothing more")
let paywall = "<html><head><meta property=\"og:description\" content=\"The board met for six hours before it reached a decision that surprised everyone.\">"
    + "</head><body><main>" + p("Subscribe to read the rest of this article today.")
    + "</main></body></html>"
let pw = ReadableParse.parseReadable(in: paywall) ?? ""
check("the teaser is drawn", pw.contains("six hours"))
check("…and it is not padded out to look like an article", pw.count < 200)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -Onone -o "$TMP/run" "$PARSE" "$BOUND" "$TMP/stub.swift" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped ReadableParse.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
echo
echo "mutations (each must be caught)"
WORK="$TMP/work"
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$PARSE" "$WORK/ReadableParse.swift"
  cp "$BOUND" "$WORK/ReadableBody.swift"
  local target="$WORK/$file"
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
    echo "  ✗ $name — the mutation did not apply (the shipped source moved,"
    echo "    so this guard has been testing nothing)"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/ReadableParse.swift" "$WORK/ReadableBody.swift" \
        "$TMP/stub.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ONE A.5 NAMES: the cap back at a lede's length, so every article ends
#    mid-sentence in an ellipsis.
mutate "the character bound back to a lede" ReadableBody.swift \
  'static let limit = 8_000' \
  'static let limit = 1_200'

# 2. The paragraph limit back to a handful — which reads as "tidier" and is how
#    a page whose chrome leads goes back to drawing nothing but chrome.
mutate "the paragraph limit back to six" ReadableParse.swift \
  'static let maxParagraphs = 200' \
  'static let maxParagraphs = 6'

# 2b. The paragraph limit lowered to a value that still looks generous but
#     BINDS BEFORE THE CAP on a page written in short paragraphs — the bug the
#     first cut of this pass shipped, caught by the pathological fixture.
mutate "the paragraph limit binding before the cap" ReadableParse.swift \
  'static let maxParagraphs = 200' \
  'static let maxParagraphs = 60'

# 3. The content region not narrowed, so a page with a <main> is read from its
#    navigation down.
mutate "contentRegion stops narrowing" ReadableParse.swift \
  'return String(html[r.lowerBound...])' \
  'return html'

# 4. The prose test dropped: menu `<p>`s join the body.
mutate "the prose test dropped" ReadableParse.swift \
  'let isProse = text.contains(". ") || text.hasSuffix(".")' \
  'let isProse = true'

# 5. Script stripping dropped: a page's JavaScript drawn at reading20.
mutate "script stripping dropped" ReadableParse.swift \
  '.replacingOccurrences(of: "<script[^>]*>.*?</script>", with: " ",' \
  '.replacingOccurrences(of: "<script[^>]*></script>", with: " ",'

# 6. The de-dupe dropped, so eight identical chrome blocks are drawn eight
#    times — the thing that makes a wide limit safe.
mutate "the de-dupe dropped" ReadableParse.swift \
  '.filter { $0.count > 24 && seen.insert($0).inserted }' \
  '.filter { $0.count > 24 }'

# 7. The 24-character floor dropped, so nav scraps rejoin.
mutate "the short-piece floor dropped" ReadableParse.swift \
  '.filter { $0.count > 24 && seen.insert($0).inserted }' \
  '.filter { _ in true }'

# 8. The "nothing readable" floor dropped, so a page with one fragment returns
#    a body and the sheet draws a scrap under a preview card.
mutate "the nothing-readable floor dropped" ReadableParse.swift \
  'guard text.count >= 40 else { return nil }' \
  'guard !text.isEmpty else { return nil }'

# The membership guards, mutated. A separate loop because these are drift
# guards over source text — the driver above cannot run them.
mutate_article() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$ARTICLE" "$WORK/FeedArticleText.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/FeedArticleText.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/FeedArticleText.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved,"
    echo "    so this guard has been testing nothing)"; exit 1
  fi
  if check_article "$WORK/FeedArticleText.swift" "MUTANT" >/dev/null 2>&1; then
    echo "  ✗ $name — the guards still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 10. An abstention taken back wholesale — the plausible "we widened it anyway".
mutate_article "YouTube back in the source list" \
  '"RSS", "Substack", "Bookmarks", "Raindrop"' \
  '"RSS", "Substack", "Bookmarks", "Raindrop", "YouTube"'

# 11. The receipts label back to a fallback, which mislabels a bookmark's host.
mutate_article "the receipts label back to a fallback" \
  'return (ref, url, thing.source)' \
  'return (ref, url, "RSS")'

echo
echo "✓ readable-body self-test: assertions and mutations all passed"
