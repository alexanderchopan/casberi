#!/bin/zsh
# Casberi agent-reply self-test — the ONE rule that decides how every written
# answer is set on the terminal (2026-09-03, prd §581):
#
#   Casberi/Casberi/Model/AgentReply.swift
#     — prose   (is this document prose and nothing else?)
#     — split   (the first sentence, and everything after it)
#
# Compiled WHOLE AND UNMODIFIED beside `GenUI/GenParser.swift`, which is the
# real element model rather than a stub — both files are Foundation-only by
# design, so every assertion here is about the bytes the app runs.
#
# WHY A HARNESS. §581 made the answer the screen: the question folds to a
# caption and the reply's FIRST SENTENCE takes the display rung, with the rest
# stepping down to reading size. That treatment is the whole fix for what the
# user reported ("the text just always looks like ass and blends into the
# question and bankr name") and it rests on two judgements no build, screen
# sweep or simulator run can see:
#
#   • `prose` must recognise the ONE document shape it can safely re-set, and
#     return nil for every other. A false nil merely costs the treatment. A
#     FALSE POSITIVE DELETES CONTENT — a brief, a Find, an answer with things
#     attached would be re-set as a paragraph and its rows would simply not be
#     drawn, on a screen that otherwise looks perfect.
#   • `split` must never cut inside a number. Bankr writes about money, so
#     "Swapped 0.62 ETH for 2,011 USDC" is the ordinary case, and a decimal
#     point read as a sentence end puts "Swapped 0." at 40pt across the top of
#     the screen with the real answer beneath it in grey.
#
# Both failures render as a perfectly ordinary answer. That is the reason this
# file exists.
#
# Pure, local, deterministic, no network. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

REPLY="Casberi/Casberi/Model/AgentReply.swift"
PARSER="Casberi/Casberi/GenUI/GenParser.swift"
TERMINAL="Casberi/Casberi/Shell/AgentTerminal.swift"
for f in "$REPLY" "$PARSER" "$TERMINAL"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ what: String, _ ok: Bool) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func doc(_ lines: String) -> GenEls {
    GenParser.parse(prefix: lines[...], isComplete: true)
}

// ---- prose: the one shape it may recognise --------------------------------

let plain = doc("""
root = Stack([ins])
ins = Insight("Swapped 0.62 ETH for 2,011 USDC on Base. Gas was $0.04.")
""")
check("a lone Insight under a Stack is prose",
      AgentReply.prose(plain) == "Swapped 0.62 ETH for 2,011 USDC on Base. Gas was $0.04.")

let bare = doc("root = Insight(\"Nothing matches that.\")")
check("a bare Insight root is prose", AgentReply.prose(bare) == "Nothing matches that.")

// A DOCUMENT MUST NEVER BE RE-SET. These are the shapes whose rows ARE the
// answer; recognising one as prose would draw the insight and silently drop
// everything attached to it.
let withRows = doc("""
root = Stack([ins, r1])
ins = Insight("Nine things, mostly from July.")
r1 = Row("Base is now the second-largest L2", "l2beat.com")
""")
check("a document with rows is not prose", AgentReply.prose(withRows) == nil)

let twoInsights = doc("""
root = Stack([a, b])
a = Insight("First.")
b = Insight("Second.")
""")
check("two insights are not prose", AgentReply.prose(twoInsights) == nil)

// A STREAM THAT HAS NOT FINISHED. The root names one Insight and a second
// element is already parsed and waiting to be referenced — that document is
// still growing, and treating it as prose would set a paragraph that is about
// to become a list.
let growing = doc("""
root = Stack([ins])
ins = Insight("Nine things, mostly from July.")
r1 = Row("Base is now the second-largest L2", "l2beat.com")
""")
check("a growing document is not prose", AgentReply.prose(growing) == nil)

let empty = doc("""
root = Stack([ins])
ins = Insight("")
""")
check("an empty insight is not prose", AgentReply.prose(empty) == nil)
check("an empty document is not prose", AgentReply.prose([:]) == nil)

// A NON-STACK ROOT IS NEVER PROSE, even when it holds exactly one Insight.
// `Bento` lays its child out with chrome around it; re-setting that as a bare
// paragraph would draw the words and drop the container they were composed
// for. This fixture is the only one whose root is neither Stack nor Insight,
// so it is the only thing holding that guard up.
let bento = doc("""
root = Bento([ins])
ins = Insight("Nine things, mostly from July.")
""")
check("a non-Stack root is not prose", AgentReply.prose(bento) == nil)

let chart = doc("""
root = Stack([c])
c = Chart("ETH", [p1])
""")
check("a chart is not prose", AgentReply.prose(chart) == nil)

// ---- split: the first sentence, and never inside a number -----------------

let money = AgentReply.split(
    "Swapped 0.62 ETH for 2,011 USDC on Base at 3,244 USDC per ETH. Gas was $0.04. The order id is bk-7f21.")
check("the lead is the first sentence",
      money.lead == "Swapped 0.62 ETH for 2,011 USDC on Base at 3,244 USDC per ETH.")
check("the rest is everything after it",
      money.rest == "Gas was $0.04. The order id is bk-7f21.")
// THE CASE THIS FILE EXISTS FOR: a decimal point is not a sentence end.
check("a decimal never ends a sentence", !money.lead.hasSuffix("0."))
check("a decimal never ends a sentence, second reading",
      money.lead.contains("0.62"))

let one = AgentReply.split("Up 4.1% today, mostly ETH.")
check("a one-sentence reply is all lead", one.lead == "Up 4.1% today, mostly ETH.")
check("a one-sentence reply has no rest", one.rest.isEmpty)

let fragment = AgentReply.split("2,011 USDC")
check("a fragment with no stop is the lead", fragment.lead == "2,011 USDC")
check("a fragment leaves no rest", fragment.rest.isEmpty)

// ABBREVIATIONS. A two-letter run before a stop is a title, not a sentence.
let title = AgentReply.split("Sent it to Mr. Chen on Base. It settled.")
check("a title abbreviation does not end the sentence",
      title.lead == "Sent it to Mr. Chen on Base.")

let dotted = AgentReply.split("The U.S. account is empty. Try the other one.")
check("a dotted abbreviation does not end the sentence",
      dotted.lead == "The U.S. account is empty.")

// A RUN WITH A DIGIT ALWAYS ENDS IT, and this is the fixture that proves the
// digit rule is load-bearing rather than decorative: "$0.04" is five
// characters (so the length rule would not split it) AND carries a stop
// inside it (so the dotted-abbreviation rule would refuse to split it). The
// digit test is the only thing that lets this sentence end.
let priced = AgentReply.split("It cost $0.04. Nothing else moved.")
check("a run carrying a digit ends the sentence", priced.lead == "It cost $0.04.")
check("a priced sentence keeps its rest", priced.rest == "Nothing else moved.")

// A three-letter run DOES end it — that is what separates "ETH." from "Mr.".
let ticker = AgentReply.split("You hold 12 ETH. Nothing else moved.")
check("a real word before the stop ends the sentence",
      ticker.lead == "You hold 12 ETH.")

// Questions and exclamations end sentences with no run test at all.
let question = AgentReply.split("Which wallet? The one on Base.")
check("a question mark ends the sentence", question.lead == "Which wallet?")

// A NEWLINE IS A BREAK. A reply that opens with its own line has already said
// where the break is.
// The first line carries NO stop of its own, or the sentence rule breaks it
// first and this fixture proves nothing about newlines at all (the "right
// result for the wrong reason" trap, third instance in this session).
let lined = AgentReply.split("Done\nThe order id is bk-7f21.")
check("a newline breaks the lead", lined.lead == "Done")
check("a newline leaves the rest whole", lined.rest == "The order id is bk-7f21.")

// THE CAP. Past it there is no lead at all and the whole reply is set at
// reading size — a first sentence longer than four lines of display type is
// not a headline, it is the answer.
let long = String(repeating: "a very long clause indeed ", count: 8) + ". And more."
let capped = AgentReply.split(long)
check("an over-long first sentence takes no display rung", capped.lead.isEmpty)
check("an over-long first sentence keeps every word", capped.rest.contains("And more."))
check("the cap is the one that ships", AgentReply.leadCap == 110)

let blank = AgentReply.split("   \n  ")
check("blank text yields nothing", blank.lead.isEmpty && blank.rest.isEmpty)

let padded = AgentReply.split("  Done.  The rest.  ")
check("the lead is trimmed", padded.lead == "Done.")
check("the rest is trimmed", padded.rest == "The rest.")

if failures == 0 { print("  ✓ AgentReply — 32 assertions") }
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run() {
  local src="$1" out="$2"
  # -Onone deliberately (the 2026-09-02 ruling): the optimizer buys nothing an
  # assertion can see, and a trapping harness under -O prints NOTHING.
  # `-enable-bare-slash-regex` is required, not optional: `GenParser` uses the
  # bare `/…/` literal and without the flag it parses as division (the trap
  # `ondevice-selftest` already paid for).
  swiftc -Onone -enable-bare-slash-regex -o "$out" "$src" \
    "$WORK/GenParser.swift" "$WORK/main.swift" 2>"$WORK/build.err" || {
    echo "✗ compile failed:"; head -20 "$WORK/build.err"; return 2
  }
  "$out"
}

cp "$PARSER" "$WORK/GenParser.swift"
cp "$REPLY" "$WORK/AgentReply.swift"
build_and_run "$WORK/AgentReply.swift" "$WORK/harness" || exit 1

# --- mutations --------------------------------------------------------------
# Each edits a scratch copy and must make the suite FAIL. A check that cannot
# fail proves nothing, and every one of these is a silent wrong answer on a
# screen that looks perfect.
mutate() {
  local what="$1" from="$2" to="$3"
  cp "$REPLY" "$WORK/mutant.swift"
  python3 - "$WORK/mutant.swift" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
if old not in s:
    sys.stderr.write("STALE MUTATION: pattern not found: %s\n" % old)
    sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
  local rc=$?
  [[ $rc -eq 3 ]] && { echo "  ✗ stale mutation: $what"; exit 1; }
  if build_and_run "$WORK/mutant.swift" "$WORK/mutant" >/dev/null 2>&1; then
    echo "  ✗ mutation SURVIVED: $what"; exit 1
  fi
  echo "  ✓ caught: $what"
}

mutate "a decimal point is read as a sentence end" \
       'let ends = next == nil || next!.isWhitespace' \
       'let ends = true'
mutate "an abbreviation ends a sentence" \
       'return run.count <= 2' \
       'return false'
mutate "a digit in the run no longer forces a sentence end" \
       'if run.contains(where: { $0.isNumber }) { return false }' \
       'if run.contains(where: { $0.isNumber }) { return true }'
mutate "a dotted abbreviation ends a sentence" \
       'if run.contains(".") { return true }' \
       'if run.contains(".") { return false }'
mutate "the lead cap stops holding" \
       'guard !lead.isEmpty, lead.count <= leadCap else { return ("", whole) }' \
       'guard !lead.isEmpty else { return ("", whole) }'
mutate "a newline stops breaking the lead" \
       'if ch == "\n" {' \
       'if false {'
mutate "a document with rows is re-set as prose" \
       'guard refs.count == 1, let only = els[refs[0]], only.comp == "Insight" else { return nil }' \
       'guard let only = els[refs[0]] else { return nil }'
mutate "a still-growing document is re-set as prose" \
       'guard els.count == 2 else { return nil }' \
       'guard els.count >= 2 else { return nil }'
mutate "an empty insight counts as prose" \
       'return s.isEmpty ? nil : s' \
       'return s'
mutate "any root component counts as prose" \
       'guard root.comp == "Stack" else { return nil }' \
       'if false { return nil }'

# --- drift guards: what the compiled functions cannot prove -----------------
# The source DOCUMENTS these rules by naming what it must not do, so every
# negative guard reads a comment-stripped copy (the Obsidian/Cursor lesson).
strip_comments() { sed -E 's://.*::' "$1"; }
strip_comments "$TERMINAL" > "$WORK/terminal.nc"
strip_comments "$REPLY"    > "$WORK/reply.nc"

# The split is USED, at the two rungs §581 ruled. A `split` nothing draws is
# arithmetic, and the treatment is the point.
grep -q 'AgentReply.split(text)' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: the prose answer no longer splits its lead"; exit 1; }
# THE LEAD LEADS INSIDE THE BUBBLE (prd §581b). It came OFF the display rung
# when both sides gained bubbles: a 40pt headline inside a bubble is a poster
# in an envelope, and the bubble now does the separating that type was doing
# alone. What must survive is the STEP — a lead that is heavier and a rest that
# is a rung down and secondary — because that is the hierarchy `split` exists
# to produce, and without it the split is arithmetic nothing draws.
grep -q 'dsText(.heading22)' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: the lead lost its rung"; exit 1; }
grep -q 'dsText(.reading20)' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: the rest no longer steps down from the lead"; exit 1; }
# AND IT IS IN A BUBBLE, LEADING, where the question's trails. That mirror is
# what makes authorship legible before a word is read.
grep -q 'Spacer(minLength: DS.Space.s8)' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: the reply's bubble no longer leads"; exit 1; }
# THE LEAD IS WHITE AND THE REST IS SECONDARY. That contrast is the whole
# separation — same size in two greys was the blend the user reported.
grep -q 'foregroundStyle(DS.textSecondary)' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: the rest is no longer set apart from the lead"; exit 1; }
# A FAILURE IS AMBER, NEVER RED. A refused key is a thing to fix, not damage.
grep -q 'DS.attention' "$WORK/terminal.nc" \
  || { echo "  ✗ drift: a failure lost its amber lead"; exit 1; }
grep -q 'DS.destructive' "$WORK/terminal.nc" \
  && { echo "  ✗ drift: a failure went red — it is a thing to fix, not damage"; exit 1; }
# THE MODEL STAYS FOUNDATION-ONLY, or this harness cannot compile it and the
# rule above stops being provable at all.
grep -qE '^import (SwiftUI|UIKit)' "$WORK/reply.nc" \
  && { echo "  ✗ drift: AgentReply imports a UI framework — the harness cannot compile it"; exit 1; }
echo "  ✓ 7 drift guards"

echo "agent-reply-selftest: OK"
