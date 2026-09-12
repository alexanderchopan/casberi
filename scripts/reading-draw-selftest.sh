#!/bin/zsh
# Casberi reading-draw self-test — the ONE condition prd §645 pass 1 changed
# (2026-09-08): the sheet draws the words the app already holds.
#
#   Casberi/Casberi/Screens/ThingContent.swift  — kindSwitch's `.link` arm,
#                                                 resolved by `linkShape` (§709)
#   Casberi/Casberi/Screens/ArticleBody.swift   — the body it mounts
#
# WHY A SEPARATE HARNESS, when `feed-reading-selftest.sh` already guards this
# pair. That one asserts the FETCH: that a tap and the background sweep share
# one eligibility rule, so neither downloads a podcast's audio file to read its
# first 512KB as text. Its guards are all positive — `readableURL` must be
# named here, and here, and here — and every one of them is still true of the
# condition this pass replaced. The rule §645 adds is a NEGATIVE one about a
# different question, and a negative guard buried in a file full of positive
# ones about the opposite question is how a rule gets deleted as a tidy-up.
#
# THE RULE, in one line: **has a body** and **could get one** are different
# questions, and only the second may consult a source list.
#
#   • DRAW — `FeedArticleText.hasBody`, which reads nothing but `enrichedText`.
#     Source-independent, on purpose: the app has scraped a readable lede off
#     every pasted link for a year (`LinkTitle.enrich`) and drew it for two of
#     ninety-seven seats, because the branch asked only the second question.
#   • FETCH — `FeedArticleText.readableURL`, which checks
#     `FeedArticleText.sources` internally and stays two sources wide.
#
# The failure this exists to catch is a REVERSION, and it renders as a
# perfectly ordinary sheet: put `sources.contains(thing.source)` back in front
# of the condition and ninety-five seats silently stop drawing words they are
# still holding — no crash, no empty frame, no build error, nothing a screen
# sweep would look twice at, and the words are still in the store where the
# answer path can reach them, so even an ask keeps working. That is the exact
# shape of the year-long bug this pass fixed, which is the argument for
# pinning it: it was invisible for a year once.
#
# THE NEGATIVE GUARD READS A COMMENT-STRIPPED COPY. `ThingContent.swift`
# documents this rule by naming the thing it must no longer do — the branch's
# own comment says "`readableURL` checks `FeedArticleText.sources` internally"
# — so a raw grep fires on the prose explaining the rule. This repo has paid
# for that four times (Obsidian, Cursor, the on-device gate, the category fold).
#
# WHAT THIS CANNOT PROVE, stated rather than implied. `ThingContent` is a
# SwiftUI view and cannot be compiled Foundation-only, so nothing here runs the
# branch — these are drift guards over source text, not assertions over
# behaviour. Whether the drawn lede reads as an article or as a nav scrap is a
# question about `LinkTitle`'s extractor on real pages, which is §645 pass 5's
# measurement and needs the network.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
BODY="Casberi/Casberi/Screens/ArticleBody.swift"
ARTICLE="Casberi/Casberi/Model/FeedArticleText.swift"
for f in "$CONTENT" "$BODY" "$ARTICLE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/reading-draw-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
print("\n".join(l for l in src.splitlines() if not l.strip().startswith("//")))
PY
}

# The `.link` arm's article branch, isolated from the rest of a 2,500-line
# view file. Everything below reads THIS, never the whole file: the sheet has
# other branches that legitimately name a source (`thing.source == "GitHub"`
# twice, immediately above), and a whole-file grep would either miss the
# reversion or fire on those.
#
# Sliced by the condition's own opening rather than by line number, so the
# guard survives an edit anywhere else in the file — and if the slice is not
# found at all, that is a failure, not a silent pass over zero bytes. That is
# the `dead-mutations-print-a-passing-line` shape, and it is why the mutation
# at the end restores the OLD condition rather than deleting the new one: a
# mutation that moves the anchor tests nothing.
branch() {
  python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
start = indent = None
for i, line in enumerate(lines):
    if re.match(r"^ *\} else if .*FeedArticleText\.", line):
        start, indent = i, len(line) - len(line.lstrip())
        break
if start is None:
    sys.stderr.write("SLICE-MISSING\n"); sys.exit(3)
end = None
for j in range(start + 1, len(lines)):
    if re.match(r"^ {%d}\}" % indent, lines[j]):
        end = j
        break
if end is None:
    sys.stderr.write("SLICE-UNCLOSED\n"); sys.exit(3)
print("\n".join(lines[start:end]))
PY
}

# The `.article` case of the `.link` switch (prd §709), sliced from its own
# `case .article(` to the next `case` at the same indent.
article_arm() {
  python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1]).read().splitlines()
start = indent = None
for i, line in enumerate(lines):
    if re.match(r"^ *case \.article\(", line):
        start, indent = i, len(line) - len(line.lstrip())
        break
if start is None:
    sys.stderr.write("ARM-MISSING\n"); sys.exit(3)
end = None
for j in range(start + 1, len(lines)):
    if re.match(r"^ {%d}(case |\})" % indent, lines[j]):
        end = j
        break
if end is None:
    sys.stderr.write("ARM-UNCLOSED\n"); sys.exit(3)
print("\n".join(lines[start:end]))
PY
}

strip_comments "$CONTENT" > "$TMP/content.nocomment"
strip_comments "$BODY"    > "$TMP/body.nocomment"

check_tree() {
  local content_nc="$1" body_nc="$2" article="$3" label="$4"
  local slice
  slice=$(branch "$content_nc") || {
    echo "✗ ${label}: the article branch is gone from ThingContent's .link arm —"
    echo "  no row draws a stored body at all any more"; return 1; }

  # ── 1. THE DRAW IS SOURCE-INDEPENDENT ────────────────────────────────────
  # The whole ruling, as a negative. `sources` is a set of two.
  if print -r -- "$slice" | grep -q 'FeedArticleText.sources'; then
    echo "✗ ${label}: the article branch names FeedArticleText.sources again —"
    echo "  the DRAW is gated on a two-source list, so every other seat holding"
    echo "  a scraped lede goes back to showing a preview card and a door out"
    echo "  to Safari (prd §645 pass 1, and the year-long bug it fixed)"
    return 1
  fi
  # …and not by another spelling of the same gate. `thing.source` in this
  # branch can only be a source test; the two GitHub arms above are outside
  # the slice.
  if print -r -- "$slice" | grep -q 'thing.source'; then
    echo "✗ ${label}: the article branch tests thing.source — a source list"
    echo "  spelled inline is the same gate wearing different words"
    return 1
  fi

  # ── 2. …AND THE DRAW IS STILL ASKED ──────────────────────────────────────
  # Deleting `hasBody` would satisfy check 1 perfectly and draw nothing.
  if ! print -r -- "$slice" | grep -q 'FeedArticleText.hasBody(thing)'; then
    echo "✗ ${label}: the article branch no longer asks hasBody — a row that"
    echo "  already holds its words would only be drawn if the FETCH would"
    echo "  also take it, which is the condition this pass replaced"
    return 1
  fi

  # ── 3. THE FETCH KEEPS ITS LIST ──────────────────────────────────────────
  # The other half of the split, and the expensive one: `readableURL` is where
  # the podcast-enclosure fence and the two-source membership live. Widening
  # the DRAW is only safe because this stayed narrow.
  if ! print -r -- "$slice" | grep -q 'FeedArticleText.readableURL(for: thing) != nil'; then
    echo "✗ ${label}: the article branch no longer offers the fetch arm —"
    echo "  a followed story with no body yet draws a preview card forever"
    return 1
  fi
  if ! grep -q 'sources.contains(thing.source)' "$article"; then
    echo "✗ ${label}: FeedArticleText.readableURL dropped its source check — the"
    echo "  DRAW's widening was only safe because the FETCH stayed two sources"
    echo "  wide; every seat in the catalog would now be scraped on open"
    return 1
  fi

  # ── 4. THE PICTURE, THE WORDS, THEN THE DOOR (prd §709, 2026-09-12) ──────
  # §455 kept the preview card above the body — art, headline, host, one
  # button. §709 split it: the art stays above the body as a picture only
  # (`artOnly: true`), the headline the sheet has already set is not drawn
  # again, and the door out to the site is ONE ROW AFTER the body. The arm is
  # the `.article` case of the `.link` switch, sliced by its own opening.
  local arm art_at body_at door_at
  arm=$(article_arm "$content_nc") || {
    echo "✗ ${label}: the .link arm's .article case is gone"; return 1; }
  art_at=$(print -r -- "$arm" | grep -n 'LinkPreviewCard(.*artOnly: true' | head -1 | cut -d: -f1)
  body_at=$(print -r -- "$arm" | grep -n 'ArticleBody(thing: thing)' | head -1 | cut -d: -f1)
  door_at=$(print -r -- "$arm" | grep -n 'ArticleDoor(' | head -1 | cut -d: -f1)
  if [[ -z "$art_at" || -z "$body_at" || -z "$door_at" ]]; then
    echo "✗ ${label}: the article arm lost its art, its body or its door"
    return 1
  fi
  if (( art_at >= body_at )); then
    echo "✗ ${label}: the body is drawn ABOVE the art — the article's own"
    echo "  picture is not replaced by its text"
    return 1
  fi
  if (( door_at <= body_at )); then
    echo "✗ ${label}: the door out to the site is drawn ABOVE the body — the"
    echo "  exit comes after the reading, not before it (prd §709)"
    return 1
  fi
  if print -r -- "$arm" | grep 'LinkPreviewCard(' | grep -qv 'artOnly: true'; then
    echo "✗ ${label}: the article arm draws the preview CARD — headline and"
    echo "  host under the art, one row below the sheet's own title (prd §709)"
    return 1
  fi

  # ── 4b. THE LEDE IS DRAWN ONCE ───────────────────────────────────────────
  # A fetched body leads with the page's description, so the sheet's
  # `summaryBlock` under an article was the same paragraph twice. The gate is
  # `readsAsArticle`; the stand-in is `ArticleBody`'s own summary, drawn only
  # when there is no body to draw.
  if ! grep -q 'if !readsAsArticle { summaryBlock }' "$content_nc"; then
    echo "✗ ${label}: summaryBlock is no longer gated on readsAsArticle — an"
    echo "  article draws its lede twice, once inside the body and once under it"
    return 1
  fi
  if grep -qE '^\s*summaryBlock\s*$' "$content_nc"; then
    echo "✗ ${label}: summaryBlock is drawn unconditionally somewhere"
    return 1
  fi
  if ! grep -q 'ThingSummaryText(text: summary)' "$body_nc"; then
    echo "✗ ${label}: ArticleBody dropped the lede's stand-in — a story whose"
    echo "  fetch missed now draws nothing where its summary used to be"
    return 1
  fi

  # ── 5. THE DUPLICATE TEST ────────────────────────────────────────────────
  # Only reachable once the two sets overlap, which is what this pass did. A
  # publisher whose <description> WAS the article, and an OEmbed link whose
  # only retrieval text is its own title, otherwise draw the same paragraph
  # twice, one row apart, at two different sizes.
  if ! grep -q 'body == (thing.summary ?? "").trimmingCharacters' "$body_nc"; then
    echo "✗ ${label}: ArticleBody no longer tests the body against summary —"
    echo "  a row whose publisher summary WAS the scrape shows it twice"
    return 1
  fi
  if ! grep -q 'body == thing.title.trimmingCharacters' "$body_nc"; then
    echo "✗ ${label}: ArticleBody no longer tests the body against the title —"
    echo "  an OEmbed link whose whole enrichedText is its own title draws the"
    echo "  headline again as a paragraph"
    return 1
  fi
  return 0
}

echo "drift guards — the draw condition"
check_tree "$TMP/content.nocomment" "$TMP/body.nocomment" "$ARTICLE" "the shipped tree" \
  || exit 1
echo "  ✓ the draw asks hasBody and names no source list"
echo "  ✓ the fetch arm keeps readableURL, and readableURL keeps its sources"
echo "  ✓ the art is drawn above the body, the door after it, and never the card"
echo "  ✓ the lede is drawn once — summaryBlock gated, ArticleBody's stand-in kept"
echo "  ✓ the body is tested against summary and title before it is drawn"

# --- mutations --------------------------------------------------------------
# A guard that cannot fire proves nothing, and a guard whose ANCHOR has drifted
# fires on nothing while printing a pass (`dead-mutations-print-a-passing-line`).
# So each mutation asserts it APPLIED before asserting the guard caught it.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"; mkdir -p "$WORK"
mutate() {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$CONTENT" "$WORK/ThingContent.swift"
  cp "$BODY"    "$WORK/ArticleBody.swift"
  cp "$ARTICLE" "$WORK/FeedArticleText.swift"
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
  strip_comments "$WORK/ThingContent.swift" > "$WORK/content.nocomment"
  strip_comments "$WORK/ArticleBody.swift"  > "$WORK/body.nocomment"
  if check_tree "$WORK/content.nocomment" "$WORK/body.nocomment" "$WORK/FeedArticleText.swift" "MUTANT" >/dev/null 2>&1; then
    echo "  ✗ $name — the guards still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE REVERSION ITSELF: the old condition, restored verbatim. This is the
#    shape the branch wore from 2026-08-21 to 2026-09-08.
mutate "the source gate restored in front of the draw" ThingContent.swift \
  '} else if FeedArticleText.hasBody(thing)' \
  '} else if FeedArticleText.sources.contains(thing.source),
                      FeedArticleText.hasBody(thing)'

# 2. The same gate spelled inline, which is what a "tidy-up" that had been told
#    not to name `sources` would plausibly write.
mutate "the source gate spelled inline" ThingContent.swift \
  '} else if FeedArticleText.hasBody(thing)' \
  '} else if thing.source == "RSS" || thing.source == "Substack",
                      FeedArticleText.hasBody(thing)'

# 3. The draw question deleted rather than widened — passes check 1 and draws
#    nothing new at all.
mutate "the draw question dropped" ThingContent.swift \
  'FeedArticleText.hasBody(thing)
                    || FeedArticleText.readableURL(for: thing) != nil {' \
  'FeedArticleText.readableURL(for: thing) != nil {'

# 4. The fetch arm dropped, so a followed story with no body yet never gets one.
mutate "the fetch arm dropped" ThingContent.swift \
  'FeedArticleText.hasBody(thing)
                    || FeedArticleText.readableURL(for: thing) != nil {' \
  'FeedArticleText.hasBody(thing) {'

# 5. The body hoisted above the art.
mutate "the body drawn above the art" ThingContent.swift \
  '                if let door {
                    LinkPreviewCard(url: door, storedImageURL: thing.previewImageURL, artOnly: true)
                }
                ArticleBody(thing: thing)' \
  '                ArticleBody(thing: thing)
                if let door {
                    LinkPreviewCard(url: door, storedImageURL: thing.previewImageURL, artOnly: true)
                }'

# 5b. The door hoisted above the body — the exit before the reading.
mutate "the door drawn above the body" ThingContent.swift \
  '                ArticleBody(thing: thing)
                if let door {
                    ArticleDoor(url: door)
                }' \
  '                if let door {
                    ArticleDoor(url: door)
                }
                ArticleBody(thing: thing)'

# 5c. The card back in the article arm — the headline drawn twice again.
mutate "the card's headline back above the article" ThingContent.swift \
  'LinkPreviewCard(url: door, storedImageURL: thing.previewImageURL, artOnly: true)' \
  'LinkPreviewCard(url: door, storedImageURL: thing.previewImageURL)'

# 5d. The summary gate removed — the lede under the piece again.
mutate "the summary drawn under the article again" ThingContent.swift \
  'if !readsAsArticle { summaryBlock }' \
  'summaryBlock'

# 5e. The stand-in dropped — a missed fetch draws nothing where the lede was.
mutate "the lede's stand-in dropped" ArticleBody.swift \
  'ThingSummaryText(text: summary)' \
  'EmptyView()'

# 6. The duplicate test against `summary` removed — the one thing the old
#    condition made unnecessary and this pass made load-bearing.
mutate "the summary duplicate test removed" ArticleBody.swift \
  'let dupe = body == (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)' \
  'let dupe = false || body == (thing.summary2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)'

# 7. …and against the title.
mutate "the title duplicate test removed" ArticleBody.swift \
  '|| body == thing.title.trimmingCharacters(in: .whitespacesAndNewlines)' \
  '|| body == thing.titleX.trimmingCharacters(in: .whitespacesAndNewlines)'

# 8. The FETCH widened to every seat, which is the reach half of the pass and
#    the one with a NetworkReach cost (§645 pass 5, not shipped).
mutate "the fetch's source membership dropped" FeedArticleText.swift \
  'guard sources.contains(thing.source),' \
  'guard true,'

echo
echo "✓ reading-draw self-test: guards and mutations all passed"
