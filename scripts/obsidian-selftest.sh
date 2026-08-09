#!/bin/zsh
# Casberi Obsidian self-test — the SHIPPED pure logic behind the vault bridge
# (2026-08-06):
#
#   Casberi/Casberi/Model/ObsidianNote.swift
#     — splitFrontmatter  (a note's words are not its YAML)
#     — frontmatterTags / inlineTags / normalize  (the vault's own subjects)
#     — strippingCode     (a `#define` is not a tag)
#     — ObsidianLink      (where Obsidian itself would open the note)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS. Every failure in this file is a SILENT WRONG ANSWER — the
# class that renders perfectly and reads as working:
#
#   • a note whose excerpt is `---\ntags: [reading]\naliases:` and not one word
#     the person wrote (which is what SHIPPED: the reader took the first 300
#     raw bytes, and for a vault using templates, Dataview or the tag pane
#     those bytes are metadata for every single note);
#   • a `---` halfway down a note read as a frontmatter opener, which would
#     delete everything above it;
#   • a heading (`# Heading`), a URL anchor (`…/page#top`) or a C `#include`
#     harvested as a tag, putting words the person never tagged on the room's
#     filter surface;
#   • a note called "Q&A" whose `obsidian://` URL ends its own vault parameter
#     early and opens the wrong note, or nothing.
#
# The DRIFT GUARDS below cover the wiring the pure file cannot prove — chiefly
# the two cap-ordering bugs (this bridge's and the Files bridge it was modelled
# on), which no assertion about parsing could ever reach.
#
# Pure, local, deterministic — no network, no simulator, no vault. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTE="Casberi/Casberi/Model/ObsidianNote.swift"
BRIDGE="Casberi/Casberi/Model/ObsidianBridge.swift"
FILES="Casberi/Casberi/Model/FilesBridge.swift"
LINKS="Casberi/Casberi/Model/NoteLinks.swift"
TOPICS="Casberi/Casberi/Model/ScreenshotTopics.swift"
INSIGHT="Casberi/Casberi/Model/FeedInsight.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
VERBS="Casberi/Casberi/Model/Verbs.swift"
PLIST="Casberi/Casberi/Info.plist"
for f in "$NOTE" "$BRIDGE" "$FILES" "$LINKS" "$TOPICS" "$INSIGHT" "$REFRESH" "$VERBS" "$PLIST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions can't prove on their own. A perfect parser is
# worthless if nothing calls it, and the two sharpest bugs fixed in this pass
# live in code no assertion can reach.

# THE TRUNCATION GUARD, and the reason this harness earns its place in
# verify.sh. Both bridges read `sorted.prefix(100)` and THEN skipped
# already-landed refs, so a vault or folder of more than 100 items could never
# finish arriving: every pass after the first looked at the same newest 100,
# found them all landed, and added nothing. It is invisible from inside the app
# — the room renders perfectly, the sync reports success, and only somebody who
# knows how many notes they have would ever notice (prd §307's lesson, in a
# bridge that had no report against it).
#
# Anchored on the FILTER PRECEDING the cap, not merely on both being present:
# the broken form contains the same two words in the other order.
grep -qE 'filter \{ !existing\.contains\(\$0\.ref\) \}' "$BRIDGE" \
  || { echo "✗ ObsidianIngest no longer filters already-landed refs BEFORE the cap —"; \
       echo "  a vault over $(grep -oE 'landingCap = [0-9]+' "$BRIDGE") notes can never finish arriving"; exit 1; }
grep -qE 'unseen\.prefix\(landingCap\)' "$BRIDGE" \
  || { echo "✗ ObsidianIngest's landing cap no longer applies to the UNSEEN notes"; exit 1; }
# CODE ONLY — both files describe the old broken line in a comment, verbatim,
# so that the next reader knows what not to write. A guard that greps the whole
# file fails on the explanation of the bug it is guarding against (caught on
# this harness's first run).
grep -hvE '^[[:space:]]*(//|\*|/\*)' "$BRIDGE" "$FILES" \
  | grep -qE 'sorted\.prefix\(100\)[[:space:]]+where[[:space:]]+!existing' \
  && { echo "✗ the cap-before-filter truncation is back — see the comment at that line"; exit 1; }
grep -qE 'filter\(\{ !existing\.contains\(\$0\.ref\) \}\)\.prefix\(100\)' "$FILES" \
  || { echo "✗ FilesIngest no longer filters before its cap — same silent truncation"; exit 1; }

# The single-flight must be TIME-BOXED, never a bare Bool. An iCloud vault's
# `String(contentsOf:)` blocks with no timeout, so a `defer`-cleared flag can
# latch forever and kill the bridge for the life of the app (FilesIngest's own
# 2026-08-02 report, and this bridge's setup copy says iCloud Drive is where
# vaults usually live).
grep -q 'runningSince: Date?' "$BRIDGE" \
  || { echo "✗ ObsidianIngest's single-flight is no longer time-boxed — an evicted"; \
       echo "  iCloud note can latch it and silently kill the bridge forever"; exit 1; }
grep -qE 'private static var running = false' "$BRIDGE" \
  && { echo "✗ the bare single-flight Bool is back"; exit 1; }

# Reading an un-downloaded file is the block that causes exactly that latch.
grep -q 'note.isDownloaded ? read(note) : nil' "$BRIDGE" \
  || { echo "✗ a not-yet-downloaded note is being READ — this is the blocking call"; exit 1; }
# …and it must still be PRESENT for the prune, or "not downloaded" is mistaken
# for "deleted from the vault".
grep -q 'Set(notes.map(\\.ref))' "$BRIDGE" \
  || { echo "✗ the prune's ref set no longer comes from the whole walk"; exit 1; }
# The empty-walk guard: an un-materialized iCloud folder enumerates empty, and
# treating that as an emptied vault deletes the corpus and mirrors it through
# CloudKit to every other device.
grep -q '!existing.isEmpty && !outcome.allRefs.isEmpty' "$BRIDGE" \
  || { echo "✗ the prune's empty-walk guard is gone — a sync hiccup would delete the vault"; exit 1; }

# The retrieval body, and the re-embed that makes an edit reach search.
grep -q 'thing.enrichedText = body' "$BRIDGE" \
  || { echo "✗ a note's full text no longer lands for retrieval — long notes become"; \
       echo "  findable only by their opening paragraph again"; exit 1; }
grep -q 'thing.embedding = nil' "$BRIDGE" \
  || { echo "✗ an edited note keeps its old vector — search would answer with what"; \
       echo "  the note USED to be about"; exit 1; }
grep -q 'thing.topicsAt = nil' "$BRIDGE" \
  || { echo "✗ an edited note keeps its first draft's topics ('we looked' is not 'we"; \
       echo "  looked correctly' — prd §313)"; exit 1; }
# The one-time repair must withhold its done-flag while anything is still owed
# (YouTubeFollowRepair's rule).
grep -q 'repairing && outcome.backlog == 0 && outcome.notDownloaded == 0' "$BRIDGE" \
  || { echo "✗ the reader repair can now mark itself done with notes unrepaired"; exit 1; }

# The registries. Each of these is a call into a table that silently answers
# nothing when the case is missing — the defect X and TikTok each shipped with
# (prd §307/§313), which is why they are mechanical here.
grep -q 'case "Obsidian":  return TopicSource' "$TOPICS" \
  || { echo "✗ Obsidian is not in ScreenshotTopics.topicSource — healTopics would"; \
       echo "  return 0 forever and the room's map could never render"; exit 1; }
grep -q 'enrichedText ?? $0.content' "$TOPICS" \
  || { echo "✗ the vault's terms no longer come off the retrieval body — the map would"; \
       echo "  read each note's opening 300 characters and call it what you write about"; exit 1; }
grep -q 'case "Obsidian":' "$INSIGHT" \
  || { echo "✗ Obsidian is not in FeedInsight.topicMap — the room leads with a heatmap"; exit 1; }
grep -q 'healTopics(source: "Obsidian"' "$REFRESH" \
  || { echo "✗ nothing runs the vault's topic sweep"; exit 1; }
# The Notes delight shipped in July and NOTHING CALLED IT until 2026-08-06.
grep -q 'NoteMoments.checkLinkCrossings' "$REFRESH" \
  || { echo "✗ NoteMoments.checkLinkCrossings is unreachable again — it was written,"; \
       echo "  shipped, and never once called for six weeks"; exit 1; }
grep -q 'NoteMoments.checkWikilinkReachBack' "$REFRESH" \
  || { echo "✗ NoteMoments.checkWikilinkReachBack is unreachable again"; exit 1; }
grep -q 'markAttention("obsidian"' "$REFRESH" \
  || { echo "✗ an unreadable vault is silent again (prd §284)"; exit 1; }

# The hand-off: a scheme that isn't declared always reads absent, so the verb
# and the plist entry must move together.
grep -q '<string>obsidian</string>' "$PLIST" \
  || { echo "✗ obsidian is not in LSApplicationQueriesSchemes — canOpenURL always"; \
       echo "  answers false and the verb could never appear"; exit 1; }
grep -q '"obsidian"' "$VERBS" \
  || { echo "✗ obsidian is not in HandOffState.candidates — nothing ever probes it"; exit 1; }
grep -q 'installedSchemes.contains("obsidian")' "$VERBS" \
  || { echo "✗ the Obsidian verb is ungated — an unclaimed scheme is refused"; \
       echo "  asynchronously and reports success, so it would be a disc that does nothing"; exit 1; }

# The inverse graph retired OUT of this file 2026-08-08 (prd §340), into
# ThingLinks.pointingAt/ThingLinksSource — generalized to any thing, not just
# an Obsidian note. This guard moved with it: the claim is no longer "NoteLinks
# carries a backlinks function" but "the successor still exists and still
# reads Obsidian's wikilinks", which is what NoteLinks.swift's own trailer
# comment documents as the replacement.
THINGLINKS="Casberi/Casberi/Model/ThingLinks.swift"
THINGLINKS_SRC="Casberi/Casberi/Model/ThingLinksSource.swift"
for f in "$THINGLINKS" "$THINGLINKS_SRC"; do
  [[ -f "$f" ]] || { echo "✗ $f not found — the inverse graph's new home is gone"; exit 1; }
done
grep -q 'static func pointingAt' "$THINGLINKS" \
  || { echo "✗ ThingLinks.pointingAt is gone — the inverse graph is the half a note"; \
       echo "  cannot carry itself"; exit 1; }
grep -q '"Obsidian"' "$THINGLINKS_SRC" \
  || { echo "✗ ThingLinksSource no longer names Obsidian as a wikilink source —"; \
       echo "  a vault's backlinks would silently stop feeding the shelf"; exit 1; }

TMP=$(mktemp -d /tmp/obsidian-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

// ── frontmatter ────────────────────────────────────────────────────────────
print("splitFrontmatter — a note's words are not its YAML")
do {
    let md = "---\ntitle: Reading\ntags: [books, 2026]\n---\nThe actual note text.\n"
    let split = ObsidianNote.splitFrontmatter(md)
    check("the block is found", split.frontmatter?.contains("tags: [books, 2026]") == true)
    check("the body is the words", split.body.trimmingCharacters(in: .whitespacesAndNewlines)
            == "The actual note text.")
    check("the excerpt is the words, not the metadata",
          ObsidianNote.parse(md).excerpt == "The actual note text.")
    check("…and carries no YAML at all", !ObsidianNote.parse(md).excerpt.contains("tags:"))
}
do {
    // `...` is YAML's other document terminator and real vaults contain it.
    let md = "---\ntags: [a]\n...\nBody here."
    check("a `...` terminator closes the block",
          ObsidianNote.parse(md).excerpt == "Body here.")
}
do {
    // THE DANGEROUS CASE. A `---` that never closes is a horizontal rule on
    // line one, not frontmatter — consuming to end-of-file would empty the note.
    let md = "---\nJust a note that opens with a rule.\nMore words."
    let split = ObsidianNote.splitFrontmatter(md)
    check("an unterminated `---` is NOT frontmatter", split.frontmatter == nil)
    check("…and the note keeps every word", split.body == md)
    check("…so the excerpt is non-empty", !ObsidianNote.parse(md).excerpt.isEmpty)
}
do {
    // A `---` further down is a horizontal rule. Treating it as an opener
    // would delete everything above it.
    let md = "Opening paragraph.\n\n---\n\nSecond section."
    check("a mid-note `---` opens nothing",
          ObsidianNote.splitFrontmatter(md).frontmatter == nil)
    check("…and the opening survives",
          ObsidianNote.parse(md).excerpt.hasPrefix("Opening paragraph."))
}
do {
    let md = "---\r\ntags: [crlf]\r\n---\r\nWindows line endings.\r\n"
    check("a CRLF file still splits", ObsidianNote.parse(md).tags == ["crlf"])
}
do {
    check("a note with no frontmatter is untouched",
          ObsidianNote.parse("Plain note.").excerpt == "Plain note.")
    check("an empty note parses to nothing", ObsidianNote.parse("").excerpt.isEmpty)
    check("a frontmatter-only note has an empty body",
          ObsidianNote.parse("---\ntags: [x]\n---\n").body.isEmpty)
}

// ── frontmatter tags ───────────────────────────────────────────────────────
print("frontmatterTags — the three shapes YAML writes a tag list in")
check("an inline array", ObsidianNote.frontmatterTags("tags: [alpha, beta]") == ["alpha", " beta"])
check("an inline comma list", ObsidianNote.frontmatterTags("tags: alpha, beta") == ["alpha", " beta"])
check("a block list",
      ObsidianNote.frontmatterTags("tags:\n  - alpha\n  - beta") == [" alpha", " beta"])
check("the singular key is read too", ObsidianNote.frontmatterTags("tag: solo") == ["solo"])
check("an unrelated key is ignored", ObsidianNote.frontmatterTags("title: Reading").isEmpty)
// A `tags:` nested under another key belongs to that key — a Dataview block or
// a plugin's config, not the note's subject.
check("an INDENTED tags: is not the note's",
      ObsidianNote.frontmatterTags("dataview:\n  tags: [internal]").isEmpty)
check("a block list stops at the next key",
      ObsidianNote.normalize(ObsidianNote.frontmatterTags("tags:\n  - alpha\naliases:\n  - other"))
        == ["alpha"])

print("parse — frontmatter and inline tags arrive together")
do {
    let md = "---\ntags: [reading, books]\n---\nA note about #philosophy and #reading."
    let tags = ObsidianNote.parse(md).tags
    check("frontmatter tags land", tags.contains("reading") && tags.contains("books"))
    check("inline tags land too", tags.contains("philosophy"))
    check("a tag in both places appears ONCE", tags.filter { $0 == "reading" }.count == 1)
}

// ── inline tags ────────────────────────────────────────────────────────────
print("inlineTags — what is and is not a tag")
check("a plain tag", ObsidianNote.inlineTags(in: "about #philosophy today") == ["philosophy"])
check("a tag at line start", ObsidianNote.inlineTags(in: "#alpha and more") == ["alpha"])
check("a nested tag keeps its slash",
      ObsidianNote.inlineTags(in: "see #project/casberi here") == ["project/casberi"])
check("a hyphenated tag", ObsidianNote.inlineTags(in: "#note-taking") == ["note-taking"])
check("a bracketed tag", ObsidianNote.inlineTags(in: "[#alpha]") == ["alpha"])
check("a blockquote tag", ObsidianNote.inlineTags(in: "> #quoted") == ["quoted"])
// Each of these is a real false positive the boundary rules exist to stop.
check("a markdown heading is NOT a tag", ObsidianNote.inlineTags(in: "# Heading").isEmpty)
check("a sub-heading is NOT a tag", ObsidianNote.inlineTags(in: "## Sub").isEmpty)
check("a URL anchor is NOT a tag",
      ObsidianNote.inlineTags(in: "see https://example.com/page#anchor").isEmpty)
check("a shebang is NOT a tag", ObsidianNote.inlineTags(in: "#!/usr/bin/env swift").isEmpty)
check("a bare number is dropped", ObsidianNote.normalize(ObsidianNote.inlineTags(in: "#2026")).isEmpty)
check("…but a tag CONTAINING digits survives",
      ObsidianNote.normalize(ObsidianNote.inlineTags(in: "#q4-2026")) == ["q4-2026"])
// A tag written in a non-Latin script is a tag.
check("a non-Latin tag lands",
      ObsidianNote.normalize(ObsidianNote.inlineTags(in: "書いた #読書 today")) == ["読書"])

print("strippingCode — a #define is not a subject")
check("a fenced block is skipped",
      ObsidianNote.parse("Words.\n\n```c\n#include <stdio.h>\n#define X 1\n```\n").tags.isEmpty)
check("a tilde fence is skipped too",
      ObsidianNote.parse("Words.\n\n~~~sh\n#!/bin/sh\n#taglike\n~~~\n").tags.isEmpty)
check("an inline code span is skipped",
      ObsidianNote.parse("The `#include` directive.").tags.isEmpty)
check("a real tag AFTER a fence still lands",
      ObsidianNote.parse("```\n#define X\n```\nabout #reading").tags == ["reading"])
check("an unterminated fence swallows the rest (safe direction)",
      ObsidianNote.parse("intro\n```\n#define X\nmore").tags.isEmpty)

// ── normalize ──────────────────────────────────────────────────────────────
print("normalize — quoting, duplicates, and the cap")
check("YAML quotes are trimmed", ObsidianNote.normalize(["\"reading\"", "'books'"]) == ["reading", "books"])
check("a leading # is trimmed", ObsidianNote.normalize(["#reading"]) == ["reading"])
check("whitespace is trimmed", ObsidianNote.normalize(["  reading  "]) == ["reading"])
check("a trailing slash is trimmed", ObsidianNote.normalize(["project/"]) == ["project"])
// Obsidian treats #Reading and #reading as ONE tag: landing both would put two
// chips on the filter surface that can never be told apart.
check("de-dupe is case-insensitive", ObsidianNote.normalize(["Reading", "reading"]) == ["Reading"])
check("…and KEEPS the first spelling", ObsidianNote.normalize(["Reading", "reading"]).first == "Reading")
check("empties are dropped", ObsidianNote.normalize(["", "  ", "#"]).isEmpty)
check("a letterless tag is dropped", ObsidianNote.normalize(["2026", "---"]).isEmpty)
check("an absurdly long tag is dropped",
      ObsidianNote.normalize([String(repeating: "a", count: 41)]).isEmpty)
check("the cap holds",
      ObsidianNote.normalize((1...50).map { "tag\($0)" }).count == ObsidianNote.tagLimit)

// ── the clamps ─────────────────────────────────────────────────────────────
print("clamps — the excerpt shows, the retrieval body searches")
do {
    let long = String(repeating: "word ", count: 4000)
    let parsed = ObsidianNote.parse(long)
    check("the excerpt is clamped", parsed.excerpt.count == ObsidianNote.excerptLimit)
    check("the retrieval body is clamped", parsed.body.count == ObsidianNote.retrievalLimit)
    // The whole point of the split: retrieval must reach far past the row.
    check("…and reaches far beyond the excerpt",
          ObsidianNote.retrievalLimit > ObsidianNote.excerptLimit * 10)
    check("the excerpt is a prefix of the body", parsed.body.hasPrefix(parsed.excerpt))
}

// ── the hand-off URL ───────────────────────────────────────────────────────
print("ObsidianLink — where Obsidian itself would open the note")
check("a note at the vault root",
      ObsidianLink.openURL(vault: "Notes", sourceRef: "obsidian:/Daily.md")?.absoluteString
        == "obsidian://open?vault=Notes&file=Daily")
check("a note in a subfolder keeps its path",
      ObsidianLink.openURL(vault: "Notes", sourceRef: "obsidian:/Work/Q4.md")?.absoluteString
        == "obsidian://open?vault=Notes&file=Work%2FQ4")
// Each of these characters ends a query parameter early if it is not encoded,
// which opens the wrong note or none — silently, since the scheme still
// resolves and Obsidian still launches.
check("an ampersand in the vault name is encoded",
      ObsidianLink.openURL(vault: "Q&A", sourceRef: "obsidian:/N.md")?.absoluteString
        == "obsidian://open?vault=Q%26A&file=N")
check("a space is encoded",
      ObsidianLink.openURL(vault: "My Vault", sourceRef: "obsidian:/A Note.md")?.absoluteString
        == "obsidian://open?vault=My%20Vault&file=A%20Note")
check("a hash is encoded",
      ObsidianLink.openURL(vault: "V", sourceRef: "obsidian:/C#1.md")?.absoluteString
        == "obsidian://open?vault=V&file=C%231")
check("a plus is encoded (a reader may decode it as a space)",
      ObsidianLink.openURL(vault: "V", sourceRef: "obsidian:/C++.md")?.absoluteString
        == "obsidian://open?vault=V&file=C%2B%2B")
check("a non-Latin name is encoded",
      ObsidianLink.openURL(vault: "V", sourceRef: "obsidian:/読書.md") != nil)
// Failures must be nil, never a URL that opens the wrong thing.
check("no vault name → nil", ObsidianLink.openURL(vault: "", sourceRef: "obsidian:/A.md") == nil)
check("a blank vault name → nil", ObsidianLink.openURL(vault: "   ", sourceRef: "obsidian:/A.md") == nil)
check("another bridge's ref → nil", ObsidianLink.openURL(vault: "V", sourceRef: "files:/A.md") == nil)
check("no ref at all → nil", ObsidianLink.openURL(vault: "V", sourceRef: nil) == nil)
check("a ref with no path → nil", ObsidianLink.openURL(vault: "V", sourceRef: "obsidian:/") == nil)
check("relativePath strips the leading separator",
      ObsidianLink.relativePath(from: "obsidian:/Work/Q4.md") == "Work/Q4.md")

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "$NOTE" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped ObsidianNote.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/run"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a plausible
# "simplification" of the shipped source, and each must break the run.
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$NOTE" "$WORK/ObsidianNote.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/ObsidianNote.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/ObsidianNote.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/ObsidianNote.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The bug that shipped: no frontmatter handling at all.
mutate "frontmatter left in the excerpt" \
  'let split = splitFrontmatter(markdown)' \
  'let split: (frontmatter: String?, body: String) = (nil, markdown)'

# 2. An unterminated `---` consuming the file — the note empties.
mutate "an unterminated opener treated as frontmatter" \
  'return (nil, markdown)
    }' \
  'return (lines.dropFirst().joined(separator: "\n"), "")
    }'

# 3. Frontmatter opened anywhere, not just line one — deletes the text above.
mutate "frontmatter opened mid-note" \
  'guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---"' \
  'guard let first = lines.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---" }),
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---"'

# 4. The inline-tag boundary dropped — headings and URL anchors become tags.
mutate "the tag boundary removed" \
  '#"(?:^|[\s(\[>])#([\w/\-]+)"#' \
  '##"#([\w/\-]+)"##'

# 5. Code no longer stripped — every C header becomes a subject.
mutate "code fences scanned for tags" \
  'let scanned = strippingCode(body)' \
  'let scanned = body'

# 6. Case-sensitive de-dupe — #Reading and #reading become two chips.
mutate "case-sensitive tag de-dupe" \
  'seen.insert(tag.lowercased()).inserted' \
  'seen.insert(tag).inserted'

# 7. The letter requirement dropped — a bare year is a tag.
mutate "letterless tags accepted" \
  'tag.rangeOfCharacter(from: .letters) != nil,' \
  'true,'

# 8. Retrieval clamped to the excerpt — the whole point of the split lost.
mutate "the retrieval body clamped to the excerpt" \
  'static let retrievalLimit = 8_000' \
  'static let retrievalLimit = 300'

# 9. Query-value encoding relaxed to `.urlQueryAllowed` — "Q&A" opens nothing.
mutate "the URL encoding relaxed" \
  'allowed.remove(charactersIn: "+&=?#/")' \
  'allowed.remove(charactersIn: "")'

# 10. An indented `tags:` harvested — a plugin's config becomes the subject.
mutate "indented YAML keys read as the note's tags" \
  'guard let first = raw.first, first != " ", first != "\t" else { continue }' \
  'guard let first = raw.first, first != "\u{0}" else { continue }'

# 11. The tag cap removed.
mutate "the tag cap removed" \
  'if out.count == tagLimit { break }' \
  'if out.count == Int.max { break }'

echo
echo "✓ obsidian self-test: assertions and mutations all passed"
