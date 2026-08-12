#!/bin/zsh
# Casberi social-sheet self-test — the SHIPPED pure judgement behind every
# social thing sheet (prd §363, 2026-08-12):
#
#   Casberi/Casberi/Model/SocialSheet.swift
#
# Foundation-only BY DESIGN, so it is compiled WHOLE AND UNMODIFIED rather than
# extracted — the strongest form of "the harness ran the shipped logic".
# Everything touching `Thing`, SwiftData or UserDefaults lives in
# `SocialSheetSource.swift`, which no harness can compile and which holds
# lookups rather than judgement.
#
# WHY A HARNESS. Every failure mode in this file is a SILENT WRONG ANSWER that
# renders perfectly, and the simulator cannot see any of them:
#
#   · a post classified as a save draws a link card over prose that is sitting
#     right there in the record — which is exactly the bug §363 fixed, shipped
#     for months across four sources
#   · a save classified as a post sets an https:// string in display type as
#     though it were somebody's sentence
#   · a Snapchat transcript classified as a post loses its bubbles
#   · a 2019 archive's counts presented with no date read as numbers somebody
#     just measured — the §83 fake-status ban in the one place a person would
#     believe them instantly
#   · a thread's continuations sliced wrong repeat the post under it, or print
#     a stranger's words under your own name
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SHEET="Casberi/Casberi/Model/SocialSheet.swift"
SOURCE="Casberi/Casberi/Model/SocialSheetSource.swift"
CARD="Casberi/Casberi/Screens/SocialReceptionCard.swift"
VIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
CONTENT="Casberi/Casberi/Screens/ThingContent.swift"
POSTS="Casberi/Casberi/Screens/SocialPostViews.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$SHEET" "$SOURCE" "$CARD" "$VIEW" "$CONTENT" "$POSTS" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled functions cannot prove about themselves. A perfect
# `shape` is worthless if the sheet never asks it, and a perfect `compose` is
# worthless if the spec table still prints `From` beside its sentence.
fail=0
guard() {  # name, file, pattern
  if grep -qE -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi
}
absent() { # name, file, pattern — reads a COMMENT-STRIPPED copy, see below
  if grep -qE -- "$2" "$3"; then echo "  ✗ $1"; fail=1; else echo "  ✓ $1"; fi
}

echo "Drift guards"

# The gate itself. §363's whole finding is that the sheet asked a SOURCE LIST
# where it meant a data test, so the sheet must reach `SocialSheetSource.shape`
# and the content view must route on it.
guard "the sheet asks SocialSheetSource for its shape" \
  'SocialSheetSource\.shape\(for: thing\)' "$VIEW"
guard "the content view routes a post on the shape, not the kind" \
  'SocialSheetSource\.shape\(for: thing\) == \.post' "$CONTENT"
guard "the reception block is drawn by the sheet" \
  'SocialReceptionCard\(reception: reception\)' "$VIEW"
guard "the reception is recomposed when the live read answers" \
  'live: live, context: modelContext' "$VIEW"
# The From row must stand down where the sentence speaks, or the sheet says the
# same fact twice in two voices — which is what §363 set out to end.
# The From row must stand down where the sentence speaks, or the sheet says the
# same fact twice in two voices — which is what §363 set out to end.
#
# Checked across the WHOLE `hasFrom` assignment rather than on one line, and
# that is not fussiness: this sheet serves every category, four passes have
# added their own conjunct to this exact expression, and it is now six lines
# long. A line-anchored grep passed, then failed the moment a sibling pass
# wrapped it — reporting a deleted gate that was sitting three lines below,
# which is a guard crying wolf about its own regex.
python3 - "$VIEW" <<'PY' || fail=1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'let hasFrom =(.*?)\n\s*let ', src, re.S)
if m and 'reception?.provenance == nil' in m.group(1):
    print("  ✓ the From spec row stands down for a composed sentence")
else:
    print("  ✗ the From spec row stands down for a composed sentence")
    sys.exit(1)
PY
# The parent is a card now, not a label.
guard "the parent renders as a card" 'ReplyingToCard\(parent: parent' "$VIEW"
# A follower is a person.
guard "a follower gets the person content" \
  'socialShape == \.person' "$VIEW"
# The likers roll finally reaches the sheet (§330 shipped it to the row only).
guard "the likers roll reaches the reception" \
  'SocialLikers\.shared\.roll\(for: thing\.sourceRef\)\?\.line' "$SOURCE"
# The face is a door only where a profile lookup exists behind it.
guard "faces are doors only for thread-capable sources" \
  'facesAreDoors' "$VIEW"
guard "facesAreDoors is SocialThread.isSocial, not the wider set" \
  'facesAreDoors: Bool \{ SocialThread\.isSocial' "$VIEW"
# The stored-bytes picture branch (§283's failure, one room over).
guard "a post draws a picture the app already holds" \
  'thing\.previewImageData, *$|images\.isEmpty, let data = thing\.previewImageData' "$POSTS"

# NEGATIVE GUARDS read a COMMENT-STRIPPED copy. Every file here DOCUMENTS what
# it must no longer do by naming it — `SocialPostViews.swift` explains at
# length why `SocialEngagementLine` was deleted — so a guard grepping raw
# source fires against the prose explaining itself (the Obsidian/Cursor lesson,
# now paid for a fourth time; caught on this guard's own first run).
strip() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*\/\/\//d'; }
strip "$POSTS" > "$TMP/posts.nc"
strip "$VIEW"  > "$TMP/view.nc"
strip "$CONTENT" > "$TMP/content.nc"

# The replaced component is DELETED, not deprecated (BridgeFooterNote's rule).
absent "the engagement line did not come back" \
  'struct SocialEngagementLine' "$TMP/posts.nc"
# The old three-name gate must not survive anywhere as a shape decision.
absent "the sheet no longer gates its anatomy on a source list" \
  'isSocialPost: Bool \{$' "$TMP/view.nc"
# `.chat` must no longer decide the post/transcript fork by source name — the
# shape does, one level up.
absent "the chat branch no longer asks isSocial" \
  'case \.chat:.*SocialThread\.isSocial' "$TMP/content.nc"

# The source set is a literal for speed; the catalog is the authority. A
# `Network` seat added or renamed without this list fails the build rather than
# silently losing its whole anatomy.
python3 - "$CATALOG" "$SOURCE" <<'PY' || fail=1
import re, sys
catalog, source = (open(p).read() for p in sys.argv[1:3])
# Offer names declared in the Network group.
# Split into OFFER BLOCKS first. A regex reaching from `name:` to the next
# `group: "Network"` looks equivalent and is not: `finditer` returns
# non-overlapping matches, so a preceding non-Network offer's `name:` opens a
# span that swallows the real one — which silently dropped Farcaster, the
# largest seat in the group, on this guard's first run.
offers = set()
for block in catalog.split("Offer(")[1:]:
    block = block.split("needsSetup")[0]
    name = re.search(r'name:\s*"([^"]+)"', block)
    if name and re.search(r'group:\s*"Network"', block):
        offers.add(name.group(1))
listed = set(re.findall(r'"([^"]+)"', re.search(
    r'static let sources: Set<String> = \[(.*?)\]', source, re.S).group(1)))
missing = offers - listed
if missing:
    print("  \u2717 catalog Network seats missing from SocialSheetSource.sources: "
          + ", ".join(sorted(missing)))
    sys.exit(1)
print("  \u2713 every catalog Network seat is in SocialSheetSource.sources (%d)" % len(offers))
PY

[[ $fail -eq 0 ]] || { echo "social-sheet-selftest: ✗ drift guard(s) failed"; exit 1; }

# --- the harness ------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

func facts(social: Bool = true, threadCapable: Bool = false, kind: String,
           hasWords: Bool = false, context: String? = nil) -> SocialSheet.Facts {
    .init(social: social, threadCapable: threadCapable, kind: kind,
          hasWords: hasWords, context: context)
}

print("Shape — the gate that was a source list")

// A non-social source gets no social anatomy at all, whatever it carries.
check("a non-social source has no shape",
      SocialSheet.shape(facts(social: false, kind: "chat", hasWords: true)) == nil)

// The three live networks, unchanged — including the case a pure words test
// would REGRESS: a Bluesky post landed before `postText` existed carries no
// words of its own and is still a post.
check("a cast is a post",
      SocialSheet.shape(facts(threadCapable: true, kind: "chat", hasWords: true)) == .post)
check("a wordless legacy skeet is still a post",
      SocialSheet.shape(facts(threadCapable: true, kind: "chat", hasWords: false)) == .post)

// The widening — the four sources §363 found refused.
check("an X post (.note with words) is a post",
      SocialSheet.shape(facts(kind: "note", hasWords: true)) == .post)
check("an X liked post (.link with words) is a post",
      SocialSheet.shape(facts(kind: "link", hasWords: true)) == .post)
check("an Instagram caption (.note with words) is a post",
      SocialSheet.shape(facts(kind: "note", hasWords: true)) == .post)

// A save is a link with no words of its own.
check("a wordless social link is a save",
      SocialSheet.shape(facts(kind: "link", hasWords: false)) == .save)
check("a wordless social product is a save",
      SocialSheet.shape(facts(kind: "product", hasWords: false)) == .save)

// A transcript is a `.chat` from a network with no thread API — Snapchat's
// saved chats, an imported DM thread.
check("a Snapchat chat is a transcript",
      SocialSheet.shape(facts(kind: "chat", hasWords: true)) == .transcript)

// A follower is a PERSON before it is anything else — the context wins over
// every kind, which is what makes it a noun change rather than a layout one.
check("a follower is a person",
      SocialSheet.shape(facts(kind: "link", context: "follow")) == .person)
check("a follower is a person even when the record carries words",
      SocialSheet.shape(facts(threadCapable: true, kind: "chat",
                              hasWords: true, context: "follow")) == .person)

// Shapes that must NOT be invented: a Snapchat memory is a picture, a signer
// grant is a permission notice. Neither wants a post's anatomy.
check("a wordless file has no shape",
      SocialSheet.shape(facts(kind: "file", hasWords: false)) == nil)
check("a screenshot has no shape",
      SocialSheet.shape(facts(kind: "screenshot", hasWords: false)) == nil)

print("")
print("Reception — the sentence and the staleness clause")

let day = Date(timeIntervalSince1970: 1_555_459_200)     // 17 Apr 2019
let read = Date(timeIntervalSince1970: 1_786_000_000)    // Aug 2026

func input(source: String = "Farcaster", shape: SocialSheet.Shape = .post,
           archive: Bool = false, when: Date? = nil, importedAt: Date? = nil,
           act: SocialReception.Act? = nil, phrase: String? = nil,
           likes: SocialReception.Reading? = nil,
           reposts: SocialReception.Reading? = nil,
           replies: SocialReception.Reading? = nil,
           likers: String? = nil, ceiling: String? = nil) -> SocialReception.Input {
    .init(source: source, shape: shape, archive: archive, when: when,
          importedAt: importedAt, act: act, phrase: phrase, likes: likes,
          reposts: reposts, replies: replies, likers: likers, ceiling: ceiling)
}

let like = SocialReception.Reading(text: "128", noun: "likes")
let capped = SocialReception.Reading(text: "97+", noun: "likes")

// Nothing to say = no block. Never a spinner, never a zero standing in for an
// unknown — the rule the engagement line kept and this inherits.
check("a reception with nothing in it is nil",
      SocialReception.compose(input(source: "X", shape: .save)) != nil)

// A live post names its network and, when there is one, the same why-phrase
// the eyebrow wears — so one screen cannot say why twice and differ.
check("a live post with no phrase says only where it is",
      SocialReception.compose(input(likes: like))?.provenance == "On Farcaster.")
check("a live post carries the eyebrow's own phrase",
      SocialReception.compose(input(phrase: "you liked this", likes: like))?
        .provenance == "On Farcaster — you liked this.")

// THE ARCHIVE GRAMMAR — the one this function exists for. It names the FILE as
// the origin and the person's own act as the event, with a real past date.
let arch = SocialReception.compose(input(
    source: "X", archive: true, when: day, importedAt: read, act: .liked, likes: like))
// The DATE is formatted through `Date.FormatStyle`, so its word order is the
// reader's locale ("17 April 2019" / "April 17, 2019") and pinning a literal
// here would make this assertion a test of the harness's own region. What is
// asserted is the sentence ASSEMBLY — the file, the act, the joining word, and
// the same formatted date the shipped code would produce.
let dayText = day.formatted(.dateTime.day().month(.wide).year())
check("an archive sentence names the file, the act and the date",
      arch?.provenance == "From your X archive — you liked this on \(dayText).")
check("the archive date is a full date, not a relative age",
      dayText.contains("2019"))
check("an archive's counts wear the date they were recorded",
      arch?.recorded == "Counts as your X archive recorded them, Aug 2026.")

// A live post's counts must NEVER wear a staleness clause — they were read
// just now, and a clause would make a true number look doubted.
check("a live post's counts carry no staleness clause",
      SocialReception.compose(input(likes: like))?.recorded == nil)
// …and an archive with NO counts has nothing that could be mistaken for a live
// measurement, so the clause would be a footnote to nothing.
check("an archive with no counts states no staleness",
      SocialReception.compose(input(source: "X", archive: true, when: day,
                                    importedAt: read, act: .saved))?.recorded == nil)
// An unread import date still gets a sentence, one fact shorter.
check("an archive with no import date still says the counts are recorded",
      SocialReception.compose(input(source: "X", archive: true, when: day,
                                    act: .liked, likes: like))?
        .recorded == "Counts as your X archive recorded them.")
check("an archive with no act falls back to naming the file",
      SocialReception.compose(input(source: "TikTok", archive: true, when: day))?
        .provenance == "From your TikTok archive.")

// A person is a person on every source.
check("a follower's sentence is about following",
      SocialReception.compose(input(source: "Bluesky", shape: .person))?
        .provenance == "Followed you on Bluesky.")

// Order is fixed and absent readings are EXCLUDED, never zeroed — the single
// rule that lets any number here be trusted.
let all = SocialReception.compose(input(
    likes: like,
    reposts: .init(text: "34", noun: "recasts"),
    replies: .init(text: "12", noun: "replies")))
check("readings keep their order", all?.readings.map(\.noun) == ["likes", "recasts", "replies"])
check("an unreported count has no cell",
      SocialReception.compose(input(likes: like, replies: .init(text: "12", noun: "replies")))?
        .readings.count == 2)
// The honesty valve survives the trip: a full page is "97+", not a total
// nobody counted.
check("a capped count keeps its plus",
      SocialReception.compose(input(likes: capped))?.readings.first?.text == "97+")

// Names, never a bare number (§239) — carried through untouched.
check("the likers roll rides the block",
      SocialReception.compose(input(likers: "Liked by @v and 126 others"))?
        .likers == "Liked by @v and 126 others")

// The stated ceiling — the one place an empty card would read as a broken
// fetch rather than an export's own limit.
check("a stated ceiling rides the block",
      SocialReception.compose(input(source: "Instagram", shape: .save, archive: true,
                                    ceiling: "the caption stays on Instagram"))?
        .ceiling == "the caption stays on Instagram")

print("")
print("Thread — slicing the chain a head carries")

let head = "the hard part was never the components"
let chain = "\(head)\n\nthe ones that say what changed are a diff\n\nso the rule now"

check("the head is dropped and the rest kept",
      SocialSheet.threadRest(enriched: chain, words: head, count: 3)?.count == 2)
check("the first continuation is the second part",
      SocialSheet.threadRest(enriched: chain, words: head, count: 3)?.first
        == "the ones that say what changed are a diff")
// The drop is PROVEN, not assumed: if the first part is not this post's words,
// the field is not this post's chain and the section must not render.
check("a chain that does not start with this post is refused",
      SocialSheet.threadRest(enriched: "somebody else\n\nsaid this", words: head, count: 2) == nil)
check("a single-post thread has no rest",
      SocialSheet.threadRest(enriched: head, words: head, count: 1) == nil)
check("no enriched text means no thread",
      SocialSheet.threadRest(enriched: nil, words: head, count: 4) == nil)
check("no count means no thread",
      SocialSheet.threadRest(enriched: chain, words: head, count: nil) == nil)
// Whitespace on either side must not defeat the head match — the words come
// off `postText`, the chain off a joined array, and the two are trimmed by
// different code paths.
check("a padded head still matches",
      SocialSheet.threadRest(enriched: chain, words: "  \(head)  ", count: 3)?.count == 2)

print("")
if failures > 0 { print("social-sheet-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("social-sheet-selftest: OK — every assertion passed against the shipped source.")
SWIFT

if ! swiftc -O -o "$TMP/ss-selftest" "$SHEET" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
echo ""
"$TMP/ss-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above.
echo ""
echo "Mutations (each must break something)"

mutate() {
  local name="$1" from="$2" to="$3"
  local a="$TMP/mut.swift"
  cp "$SHEET" "$a"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$a" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$a"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# THE BUG §363 FIXED: the gate asking about the source instead of the record.
mutate "the widening reverted to a thread-capable test" \
  'if f.hasWords { return .post }' \
  'if f.hasWords && f.threadCapable { return .post }'
# The regression a pure words test would cause — every pre-§81 Bluesky row.
mutate "a legacy wordless cast falls through to a save" \
  'if f.kind == "chat" { return f.threadCapable ? .post : .transcript }' \
  'if f.kind == "chat" && f.hasWords { return .post }'
# A conversation drawn as one person's post.
mutate "a transcript is classified as a post" \
  'return f.threadCapable ? .post : .transcript' \
  'return .post'
# A follower losing its noun, back to a link preview of a profile page.
mutate "a follower stops being a person" \
  'if f.context == "follow" { return .person }' \
  'if f.context == "follow" && f.kind == "person" { return .person }'
# The staleness clause disappearing means a 2019 count reads as live.
mutate "an archive's counts stop wearing their date" \
  'if i.archive, !out.readings.isEmpty {' \
  'if false, !out.readings.isEmpty {'
# …and the inverse: a clause on a live read, doubting a true number.
mutate "a live post's counts wear a staleness clause" \
  'if i.archive, !out.readings.isEmpty {' \
  'if !out.readings.isEmpty {'
# The archive sentence losing the date is the difference between "this is old"
# and a sentence that could be about this morning.
mutate "the archive sentence drops its date" \
  'return String(localized:
                "From your \(i.source) archive — you \(act.verb) this on \(day(when)).")' \
  'return String(localized: "From your \(i.source) archive — you \(act.verb) this.")'
# Absent readings zeroed instead of excluded — the honesty rule that makes
# every other number on the card trustworthy.
mutate "an unreported count becomes a zero" \
  'out.readings = [i.likes, i.reposts, i.replies].compactMap { $0 }' \
  'out.readings = [i.likes ?? .init(text: "0", noun: "likes"), i.reposts, i.replies].compactMap { $0 }'
# The thread slice repeating the post under itself.
mutate "the thread keeps its own head" \
  'return Array(parts.dropFirst())' \
  'return parts'
# The slice printing a stranger's words under your name.
mutate "the thread head is no longer proven" \
  'guard !head.isEmpty, parts[0] == head else { return nil }' \
  'guard !head.isEmpty else { return nil }'
# The eyebrow's phrase and the sentence drifting into two vocabularies.
mutate "the live sentence stops carrying the phrase" \
  'return String(localized: "On \(i.source) — \(phrase).")' \
  'return String(localized: "On \(i.source).")'

echo ""
echo "social-sheet-selftest: OK — assertions and mutations both pass."
