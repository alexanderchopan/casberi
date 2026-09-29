#!/bin/zsh
# Voice-timeline self-test (prd §987, 2026-09-29) — a kept recording read back
# with a time for every word, its length, and the player's speeds:
#
#   Casberi/Casberi/Model/VoiceTimeline.swift   compiled WHOLE and unmodified
#
# WHY A HARNESS. The sheet lights the word being said and seeks to a word you
# tap, and the heal replaces a note's live words with the whole file's reading.
# Every failure below compiles, runs and looks nearly right:
#
#   • A CHARACTER LOST OR ADDED in `build` — the timed words no longer equal
#     the note's words, `matches` fails, and the sheet silently falls back to
#     plain text on every note.
#   • THE LIT WORD OFF BY ONE, or dark in the gap between two words.
#   • A SHORT OR EMPTY READING REPLACING WHAT WAS HEARD LIVE — a wrong-language
#     read of a minute's note would leave three words.
#   • A LENGTH ROUNDED DOWN ("0:06" for 6.9s) or a clock showing a second that
#     has not happened yet.
#   • THE HEAL UNHOOKED: kept notes never read, the row never told the length,
#     or the older recognizer (whose live path may use Apple's server) asked to
#     read recordings in the background — drift guards, since no compiled
#     assertion can see a call site.
#
# Pure, local, deterministic — no simulator, no model, no network.
set -euo pipefail
cd "$(dirname "$0")/.."

TL="Casberi/Casberi/Model/VoiceTimeline.swift"
TR="Casberi/Casberi/Model/VoiceTranscribe.swift"
for f in "$TL" "$TR"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/voice-timeline-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// --- build: the analyzer's runs, as measured on macOS 27 (a leading space on
// every word after the first, punctuation inside the word's run) ------------
let measured: [(text: String, start: Double?, end: Double?)] = [
    ("Remember", 0.0, 0.48), (" to", 0.48, 0.66), (" pick", 0.66, 0.78),
    (" up", 0.78, 0.96), (" Thursday,", 2.22, 2.76), (" then", 2.76, 3.12),
]
let t = VoiceTimeline.build(runs: measured)!
check(t.text == "Remember to pick up Thursday, then", "text is the runs joined — got \(t.text)")
check(t.words.count == 6, "one word per timed run — got \(t.words.count)")

// Untimed runs join the word before; leading untimed text joins the first.
let mixed = VoiceTimeline.build(runs: [
    (" ", nil, nil), ("Hello", 0, 0.5), (" ", nil, nil), ("world", 0.6, 1.0), (".", nil, nil), ("  ", nil, nil)])!
check(mixed.text == "Hello world.", "untimed runs kept, ends trimmed — got '\(mixed.text)'")
check(mixed.words.map(\.text) == ["Hello ", "world."], "spaces and a stop join the word before — got \(mixed.words.map(\.text))")
check(VoiceTimeline.build(runs: [(" ", nil, nil)]) == nil, "nothing timed builds nothing")
check(VoiceTimeline.build(runs: [("x", 2, 1)]) == nil, "a run ending before it starts is not a word")
check(VoiceTimeline.build(runs: [("  ", 0, 1)]) == nil, "a timed run of only space is not a word")

// --- the lit word --------------------------------------------------------------
check(t.wordIndex(at: -1) == nil, "nothing lit before the first word")
check(t.wordIndex(at: 0) == 0, "the first word lights at its start")
check(t.wordIndex(at: 0.5) == 1, "the word that has started is lit")
check(t.wordIndex(at: 1.5) == 3, "the gap keeps the earlier word lit — got \(String(describing: t.wordIndex(at: 1.5)))")
check(t.wordIndex(at: 99) == 5, "past the end, the last word")

// --- matches -------------------------------------------------------------------
check(t.matches("Remember to pick up\nThursday,  then"), "a line break is not a different transcript")
check(!t.matches("Remember to pick up Friday, then"), "different words do not match")

// --- replaces ------------------------------------------------------------------
let live = "remember to pick up the film from the lab on thursday"
check(VoiceTimeline.replaces(live, with: "Remember to pick up the film from the lab on Thursday."), "a better reading replaces")
check(VoiceTimeline.replaces("", with: "Hello there."), "words replace an empty note")
check(!VoiceTimeline.replaces(live, with: "   "), "an empty reading never replaces")
check(!VoiceTimeline.replaces(live, with: "remember  to pick up the film\nfrom the lab on thursday"), "the same words are not a rewrite")
check(!VoiceTimeline.replaces(live, with: "hola que tal"), "fewer than half as many words never replace")

// --- lengths -------------------------------------------------------------------
check(VoiceLength.label(6.9) == "0:07", "a length rounds to nearest — got \(VoiceLength.label(6.9))")
check(VoiceLength.label(6.9, rounding: .down) == "0:06", "the clock rounds down")
check(VoiceLength.label(272) == "4:32", "minutes — got \(VoiceLength.label(272))")
check(VoiceLength.label(3725) == "1:02:05", "hours — got \(VoiceLength.label(3725))")
check(VoiceLength.label(0) == "0:00" && VoiceLength.label(.nan) == "0:00", "nothing or nonsense is 0:00")
let start = Date(timeIntervalSince1970: 1_000)
check(VoiceLength.seconds(from: start, to: start.addingTimeInterval(42)) == 42, "the span is the length")
check(VoiceLength.seconds(from: start, to: nil) == nil, "no end, no length")
check(VoiceLength.seconds(from: start, to: start) == nil, "a zero span is no length")

// --- speeds --------------------------------------------------------------------
check(VoiceLength.next(after: 1) == 1.5 && VoiceLength.next(after: 1.5) == 2 && VoiceLength.next(after: 2) == 1,
      "1× → 1.5× → 2× → 1×")
check(VoiceLength.next(after: 3) == 1, "a stored speed not on the list starts over")
check(VoiceLength.rateLabel(1) == "1×" && VoiceLength.rateLabel(1.5) == "1.5×", "speed words")

// --- the cache round-trips -----------------------------------------------------
let data = try! JSONEncoder().encode(t)
check(try! JSONDecoder().decode(VoiceTimeline.self, from: data) == t, "a timeline survives its cache")

if failures > 0 { print("✗ voice-timeline-selftest: \(failures) failure(s)"); exit(1) }
SWIFT

swiftc -O -o "$TMP/run" "$TL" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log"; echo "✗ voice-timeline-selftest did not compile"; exit 1; }
"$TMP/run"

# --- drift guards --------------------------------------------------------------
grep -q 'await VoiceHeal.settle(thing, in: context)' Casberi/Casberi/Shell/NoteCaptureSheet.swift \
  || { echo "✗ a kept recording is never read back — no times, no length heal"; exit 1; }
grep -q 'await VoiceHeal.run(context:' Casberi/Casberi/Shell/RootShell.swift \
  || { echo "✗ the launch heal is not scheduled — older and synced notes are never read"; exit 1; }
grep -q '\\\.endAt' <(awk '/static let lightColumns/,/^    \]/' Casberi/Casberi/Screens/FeedScreen.swift) \
  || { echo "✗ endAt left out of lightColumns — every voice row faults for its length"; exit 1; }
grep -q 'voiceLength' <(awk '/private var previewLine/,/^    }$/' Casberi/Casberi/Screens/ShapedRows.swift) \
  || { echo "✗ the Notes room's voice line no longer carries the length"; exit 1; }
if grep -q 'SFSpeech' "$TR"; then
  echo "✗ the background read asks the older recognizer, whose live path may use Apple's server"; exit 1
fi
grep -q 'guard !DemoMode.isActive' <(awk '/static func run\(context/,/^    }$/' "$TR") \
  || { echo "✗ the voice heal runs in the demo"; exit 1; }
grep -q 'VoiceTimeline.replaces' <(awk '/static func rewrite\(/,/^    }$/' "$TR") \
  || { echo "✗ rewrite no longer asks VoiceTimeline.replaces — a short reading can eat a note"; exit 1; }

echo "✓ voice-timeline-selftest passed"
