#!/bin/zsh
# Casberi on-device-intelligence self-test — verifies the SHIPPED pure logic
# behind the §282 pass (2026-08-02):
#
#   Casberi/Casberi/Model/EmbeddingIndex.swift
#     — Header           (the 12-byte language tag on every stored vector)
#   Casberi/Casberi/Model/RelatedThings.swift
#     — normalizedTitle  (what makes two saves "the same thing")
#     — canonicalLink    (same, for links, once the tracking junk is off)
#   Casberi/Casberi/Model/ScreenshotFacts.swift
#     — dates            (the deterministic half of the calendar hand-off)
#   Casberi/Casberi/Model/ScreenshotNaming.swift
#     — isWeak / grounded (the rail that keeps an invented title out)
#
# WHY A HARNESS AND NOT A SIM CHECK. The simulator has no on-device language
# model, so every model path in this pass runs only its unavailable branch
# there — a sim run cannot exercise a single one of them. What it CAN'T excuse
# is the pure logic around them, and every failure mode here is a SILENT WRONG
# ANSWER rather than a crash:
#
#   · a Header whose magic or offset is off by a byte makes `similarity`
#     return 0 for EVERY pair, which looks exactly like "this corpus has no
#     related things" and would never be reported as a bug;
#   · a `dates` that accepts a status-bar clock puts "9:41 today" on the
#     calendar hand-off of nearly every screenshot in the library;
#   · a `grounded` that accepts anything turns the §218 honesty rail off while
#     still logging that it ran.
#
# The files import SwiftData/NaturalLanguage and reference `Thing`, so they
# cannot compile as shipped. The pure functions are EXTRACTED from the shipped
# source BY NAME — never copied into this file — so the harness cannot pass
# against logic the app doesn't run. If an extraction stops matching, the
# compile fails loudly rather than asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

EMBED="Casberi/Casberi/Model/EmbeddingIndex.swift"
RELATED="Casberi/Casberi/Model/RelatedThings.swift"
FACTS="Casberi/Casberi/Model/ScreenshotFacts.swift"
NAMING="Casberi/Casberi/Model/ScreenshotNaming.swift"
RETRIEVER="Casberi/Casberi/Model/Retriever.swift"
ASKCMD="Casberi/Casberi/Model/AskCommands.swift"
for f in "$EMBED" "$RELATED" "$FACTS" "$NAMING" "$RETRIEVER" "$ASKCMD"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions can't prove on their own: a perfect
# Header is worthless if `similarity` stops consulting it, and a perfect
# `grounded` is worthless if the sweep stops calling it.
grep -q 'guard Header.language(of: packed) == language else { return 0 }' "$EMBED" \
  || { echo "✗ similarity no longer refuses a cross-language comparison — the whole point of the header"; exit 1; }
grep -q 'EmbeddingIndex.queryVector(for: ask)' "$RETRIEVER" \
  || { echo "✗ the retriever no longer embeds the ask in its own language"; exit 1; }
grep -q 'guard grounded(title, in: text) else { continue }' "$NAMING" \
  || { echo "✗ the naming sweep no longer checks a proposed title against the OCR text (§218's rail)"; exit 1; }
grep -q 'matched.wholeMatch(of: bareClock) == nil' "$FACTS" \
  || { echo "✗ the date scan no longer rejects a bare clock on the MATCHED TEXT"; exit 1; }
grep -q 'thing.embedding = nil' "Casberi/Casberi/Model/ThreadDigest.swift" \
  || { echo "✗ a digested thread no longer clears its stale vector"; exit 1; }

# THE ONE-INFERENCE-AT-A-TIME RAIL (2026-08-07, builds 280 and 281).
# `NLEmbedding` is not safe to call from two threads at once and does not say
# so anywhere. The app embeds from the main actor (an ask, via
# `Retriever.rank`) and from a detached utility task (the backfill sweep) —
# both started by the SAME foreground pass, so any pass with something to embed
# runs two inferences concurrently by construction and one of them segfaults
# inside BNNS. Every `NLEmbedding` COMPUTE call must go through
# `EmbeddingIndex.serialized`.
#
# Guarded here rather than remembered because the failure is a hard crash whose
# stack names only Apple's frameworks — nothing in the source looks wrong, and
# a "fix" that unwraps either call site restores it silently while every other
# check stays green (xcodebuild is happy, the audits are static, and the
# simulator ships no on-device model).
#
# The negative sweep reads a COMMENT-STRIPPED copy: the source DOCUMENTS this
# rule by naming the very methods it governs, so a guard grepping raw source
# fires against the prose explaining it (the Obsidian/Cursor lesson).
# No `trap … EXIT` here: this script sets one later for its own $TMP, and a
# second EXIT trap REPLACES the first rather than adding to it — so a trap here
# would be silently discarded and leak the file. Removed explicitly instead.
STRIPPED="$(mktemp)"
sed 's://.*::; s:^ *///.*::' "$EMBED" "$ASKCMD" > "$STRIPPED"

grep -q 'serialized({ model.vector(for: trimmed) })' "$EMBED" \
  || { echo "✗ EmbeddingIndex.vector no longer serializes its inference — two threads in NLEmbedding is what crashed 280 and 281"; exit 1; }
grep -q 'inferenceQueue.sync(execute: body)' "$EMBED" \
  || { echo "✗ EmbeddingIndex.serialized is no longer a serial queue — an NSLock here trades the crash for a 2.5s main-thread stall (measured)"; exit 1; }
grep -q 'DispatchQueue(label: "com.casberi.embedding.inference")' "$EMBED" \
  || { echo "✗ the inference queue is gone or is no longer serial (a concurrent queue serializes nothing)"; exit 1; }
grep -q 'EmbeddingIndex.serialized { embedding.neighbors(for: term, maximumCount: 8) }' "$ASKCMD" \
  || { echo "✗ SemanticExpand's word-embedding neighbours no longer serialize — the word and sentence models share fillWordVectors"; exit 1; }
# Every compute call in these two files, comments removed, must name
# `serialized` ON THE SAME LINE — which is why the two shipped call sites are
# written as one-liners rather than wrapped across three lines: a line-wise
# guard cannot see a closure that opens on one line and calls on the next, and
# the first cut of this check fired on its own correct code.
if grep -nE '\.(vector|neighbors|distance)\(for:' "$STRIPPED" | grep -v 'serialized' | grep -q .; then
  echo "✗ an NLEmbedding compute call is not inside EmbeddingIndex.serialized:"
  grep -nE '\.(vector|neighbors|distance)\(for:' "$STRIPPED" | grep -v 'serialized'
  exit 1
fi
# The sweep above is scoped to the only two files that HOLD an `NLEmbedding`;
# everything else in the app calls `EmbeddingIndex.vector`, which is serialized
# for them. That scope is only correct while it stays true — a third file
# taking its own model would be un-swept and invisible, so it fails here
# instead. (Comment-stripped: several files discuss NLEmbedding in prose.)
#
# The `|| true` is load-bearing under `set -e`: the loop's exit status is its
# LAST iteration's, and the last file checked normally does NOT match, so the
# command substitution returns 1 and `VAR=$(…)` aborts the whole script —
# exit 1, no output, on a perfectly clean tree. Verified by running it.
THIRD=$(for f in $(grep -rl 'NLEmbedding' --include=*.swift Casberi/ 2>/dev/null); do
          case "$f" in *EmbeddingIndex.swift|*AskCommands.swift) continue;; esac
          sed 's://.*::; s:^ *///.*::' "$f" | grep -q 'NLEmbedding' && echo "$f"
        done || true)
rm -f "$STRIPPED"
[[ -z "$THIRD" ]] \
  || { echo "✗ a third file holds an NLEmbedding and is not covered by the sweep above: $THIRD"; exit 1; }

TMP=$(mktemp -d /tmp/ondevice-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped functions -----------------------------------------
python3 - "$EMBED" "$RELATED" "$FACTS" "$NAMING" "$TMP/extracted.swift" <<'PY'
import sys
embed, related, facts, naming, out = sys.argv[1:6]

def block(path, signature, kind="brace"):
    """The whole declaration whose header line contains `signature`,
    brace-matched out of the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

def line(path, signature):
    """A one-line `static let`."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    return src[start:src.index("\n", i) + 1].replace("private ", "")

def bracket(path, signature):
    """A `static let` whose value is a multi-line `[...]` literal — cutting it
    at the first newline (which `line` does) yields an unterminated array and a
    compile error that reads as an unrelated syntax problem."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("[", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "[": depth += 1
        elif src[k] == "]":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

pieces = [
    "import Foundation\n",
    "import NaturalLanguage\n",
    # The placeholder `normalizedTitle` refuses, lifted so the harness can't
    # drift from the string the app actually uses.
    'enum ScreenshotTitle { static let placeholder = "Screenshot" }\n',
    # `canonicalLink` takes a `Thing`; the harness narrows that one dependency
    # to the single field it reads. File-scope, so it can't land inside a
    # literal being extracted.
    "struct Stub { var content: String }\n",
    "enum EmbeddingIndex {",
    block(embed, "enum Header {"),
    "}\n",
    "enum RelatedThings {",
    block(related, "static func normalizedTitle"),
    bracket(related, "static let trackingParams"),
    block(related, "static func canonicalLink"),
    "}\n",
    "enum ScreenshotFacts {",
    line(facts, "static let bareClock"),
    block(facts, "static func dates"),
    "}\n",
    "enum ScreenshotNaming {",
    block(naming, "static func isWeak"),
    block(naming, "static func grounded"),
    "}\n",
]
src = "\n".join(pieces)
# `canonicalLink` takes a `Thing`; the harness feeds it a `Stub` carrying the
# one field it reads. Done by substitution on the EXTRACTED text (never in the
# shipped file), and asserted so a signature change can't silently no-op it.
before = src
src = src.replace("static func canonicalLink(_ thing: Thing) -> String? {",
                  "static func canonicalLink(_ thing: Stub) -> String? {")
if src == before:
    sys.exit("✗ canonicalLink's signature changed — the harness stub no longer applies")
open(out, "w").write(src)
PY

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
import NaturalLanguage

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("✗ \(what)"); failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    if a != b { print("✗ \(what) — got \(a), expected \(b)"); failures += 1 }
}

// ── Header: the tag on every stored vector ────────────────────────────────
// A vector is 12 bytes of preamble then Float32s. Getting the offset or the
// magic wrong doesn't crash — it makes every cosine 0, which reads as "you
// have no related things" forever.
let english = EmbeddingIndex.Header.bytes(for: .english)
eq(english.count, EmbeddingIndex.Header.size, "header is 12 bytes")
eq(EmbeddingIndex.Header.language(of: english), NLLanguage.english, "english round-trips")
eq(EmbeddingIndex.Header.offset(in: english), 12, "a tagged blob's floats start at 12")

for lang in [NLLanguage.spanish, .japanese, .german, .simplifiedChinese, .traditionalChinese] {
    let h = EmbeddingIndex.Header.bytes(for: lang)
    eq(EmbeddingIndex.Header.language(of: h), lang, "\(lang.rawValue) round-trips")
}
// The reason the tag is 8 bytes and not 4: these two are one model each and
// share their first four characters. A 4-byte tag folds them together and
// every Simplified/Traditional cosine becomes noise scored as a match.
check(EmbeddingIndex.Header.bytes(for: .simplifiedChinese)
      != EmbeddingIndex.Header.bytes(for: .traditionalChinese),
      "zh-Hans and zh-Hant get DIFFERENT tags")

// A pre-header vector — what every vector written before 2026-08-02 looks
// like. It must read as English and start at byte 0, or the upgrade silently
// invalidates the whole existing index.
var legacy = Data()
for f in [Float(0.5), 0.25, -0.75] { withUnsafeBytes(of: f) { legacy.append(contentsOf: $0) } }
eq(EmbeddingIndex.Header.language(of: legacy), NLLanguage.english, "a legacy vector reads as English")
eq(EmbeddingIndex.Header.offset(in: legacy), 0, "a legacy vector's floats start at 0")
eq(EmbeddingIndex.Header.language(of: Data()), nil, "an empty blob has no language")

// ── normalizedTitle: what makes two saves "the same thing" ────────────────
eq(RelatedThings.normalizedTitle("The Lisbon Flight!"),
   RelatedThings.normalizedTitle("the lisbon flight"), "case and punctuation don't matter")
eq(RelatedThings.normalizedTitle("Screenshot"), nil, "the placeholder is never a duplicate key")
eq(RelatedThings.normalizedTitle("Hi all"), nil, "too short to be a claim")
check(RelatedThings.normalizedTitle("Quarterly planning notes") != nil, "a real title survives")
check(RelatedThings.normalizedTitle("Apples and pears")
      != RelatedThings.normalizedTitle("Pears and apples"), "word ORDER still distinguishes")

// ── canonicalLink: two saves of one page ──────────────────────────────────
func link(_ s: String) -> String? { RelatedThings.canonicalLink(.init(content: s)) }
eq(link("https://www.example.com/post/"), link("http://example.com/post"),
   "scheme, www. and a trailing slash don't make a second link")
eq(link("https://example.com/p?utm_source=rss&utm_campaign=x"), link("https://example.com/p"),
   "tracking parameters come off")
check(link("https://example.com/watch?v=abc") != link("https://example.com/watch?v=xyz"),
      "a MEANINGFUL query still distinguishes — v= is not tracking")
eq(link("not a url"), nil, "a note's text is not a link")
eq(link("mailto:someone@example.com"), nil, "only http(s) counts")
check(link("https://example.com/a") != link("https://example.com/b"), "different paths differ")

// ── dates: the deterministic half of the hand-off ─────────────────────────
// Fixed reference so the assertions don't depend on the day this runs.
let ref = Date(timeIntervalSince1970: 1_754_092_800)   // 2025-08-02 00:00 UTC
let soon = ref.addingTimeInterval(30 * 86_400)
let fmt = DateFormatter()
fmt.dateFormat = "MMMM d, yyyy 'at' h:mm a"
fmt.locale = Locale(identifier: "en_US_POSIX")
fmt.timeZone = TimeZone(identifier: "UTC")

// The status bar of nearly every iOS screenshot. NSDataDetector resolves it to
// today at that time, and by then it is indistinguishable from a real meeting
// — which is why the rejection is on the matched TEXT.
eq(ScreenshotFacts.dates(in: "9:41", reference: ref).count, 0, "a bare clock is not an appointment")
eq(ScreenshotFacts.dates(in: "12:05 AM\n100%\n5G", reference: ref).count, 0,
   "a status bar yields nothing")
eq(ScreenshotFacts.dates(in: "", reference: ref).count, 0, "empty text yields nothing")

let future = "Your booking is confirmed for \(fmt.string(from: soon))."
check(ScreenshotFacts.dates(in: future, reference: ref).count >= 1, "a real future booking is found")

let past = "Receipt dated \(fmt.string(from: ref.addingTimeInterval(-60 * 86_400)))."
eq(ScreenshotFacts.dates(in: past, reference: ref).count, 0, "a past date is not a plan")

let tooFar = "Expires \(fmt.string(from: ref.addingTimeInterval(500 * 86_400)))."
eq(ScreenshotFacts.dates(in: tooFar, reference: ref).count, 0, "beyond a year is a misparse, not a plan")

let two = "Check in \(fmt.string(from: soon)) then out \(fmt.string(from: soon.addingTimeInterval(3 * 86_400)))."
check(ScreenshotFacts.dates(in: two, reference: ref, limit: 2).count <= 2, "the cap holds")
let sorted = ScreenshotFacts.dates(in: two, reference: ref, limit: 2)
check(sorted == sorted.sorted(), "soonest first")

// ── isWeak / grounded: the §218 rail ──────────────────────────────────────
check(ScreenshotNaming.isWeak("Screenshot"), "the placeholder is weak")
check(ScreenshotNaming.isWeak(""), "an empty title is weak")
check(ScreenshotNaming.isWeak("Fitness"), "a one-word widget label is weak — the §218 failure shape")
check(ScreenshotNaming.isWeak("Settings General"), "two words is still a label")
check(!ScreenshotNaming.isWeak("Flight to Lisbon confirmed"), "a real sentence is not weak")

let ocr = "Confirmation\nYour dentist appointment with Dr Ramos\nGreen Lane Clinic\nBook again"
check(ScreenshotNaming.grounded("Dentist appointment Ramos", in: ocr),
      "a title built from the text is grounded")
check(!ScreenshotNaming.grounded("Flight to Lisbon", in: ocr),
      "an invented title is REJECTED — the whole rail")
check(!ScreenshotNaming.grounded("", in: ocr), "an empty title is never grounded")
// Partial credit must not pass: one real word out of three is the shape of a
// model anchoring on a detail and inventing the rest.
check(!ScreenshotNaming.grounded("Lisbon holiday appointment", in: ocr),
      "one grounded word in three is not enough")

if failures == 0 {
    print("✓ on-device self-test: all assertions passed")
} else {
    print("✗ on-device self-test: \(failures) failure(s)")
    exit(1)
}
SWIFT

swiftc -O -enable-bare-slash-regex -o "$TMP/harness" "$TMP/extracted.swift" "$TMP/main.swift" 2>&1 \
  | grep -v "^$" || true
[[ -x "$TMP/harness" ]] || { echo "✗ harness failed to compile — an extraction stopped matching the shipped source"; exit 1; }
"$TMP/harness"
