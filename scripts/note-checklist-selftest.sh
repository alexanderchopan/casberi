#!/bin/zsh
# Casberi note-checklist self-test (prd §982) — the pure logic behind a note's
# checklist, compiled WHOLE and UNMODIFIED:
#
#   Casberi/Casberi/Model/NoteSheet.swift     — taskLine, blocks(tasks:)
#   Casberi/Casberi/Model/NoteChecklist.swift — stored, toggled, continued,
#                                               toggleLastLine, plain
#
# Every failure here is a SILENT WRONG ANSWER: a tick that flips the wrong
# item, a kept list whose empty circles land as empty boxes, Return that
# never ends a list, a vault's `- [ ]` ticked in the app and overwritten by
# the next sync, a title reading "- [ ] milk".
#
# The drift guards cover the wiring the pure files cannot prove: that the
# sheet keeps the STORED form, that Return goes through `continued`, that a
# tick goes through `toggled` and only where `ticksTasks` allows it, and that
# a lock clears everything derived from the words.
#
# Usage: scripts/note-checklist-selftest.sh     (exit 0 = clean)

set -u
cd "${0:A:h}/.."

SHEET="Casberi/Casberi/Model/NoteSheet.swift"
LIST="Casberi/Casberi/Model/NoteChecklist.swift"
CAPTURE="Casberi/Casberi/Shell/NoteCaptureSheet.swift"
VIEW="Casberi/Casberi/Screens/ThingSheetView.swift"
SOURCE="Casberi/Casberi/Model/NoteSheetSource.swift"
LOCK="Casberi/Casberi/Model/NoteLock.swift"
PREVIEW="Casberi/Casberi/Model/NotePreview.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"

fail=0
guard() {  # name, pattern, file
  if grep -Eq -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1 ($3)"; fail=1; fi
}

echo "Drift guards — the wiring"
guard "the sheet keeps the stored form, never the circles" \
  'NoteChecklist\.stored\(draft\)' "$CAPTURE"
guard "an edit opens a kept list as circles" \
  'draft = NoteChecklist\.editable\(note\.content\)' "$CAPTURE"
guard "Return inside a list goes through continued" \
  'NoteChecklist\.continued\(old: old, new: new\)' "$CAPTURE"
guard "a tick goes through toggled" \
  'NoteChecklist\.toggled\(thing\.content, ordinal: ordinal\)' "$VIEW"
guard "a tick is offered only where ticksTasks allows it" \
  'onToggleTask: NoteSheetSource\.ticksTasks\(thing\)' "$VIEW"
guard "a vault's list is never ticked (ticksTasks is kept notes only)" \
  'isKeptNote\(thing\) && thing\.kind == \.note && !NoteLock\.isLocked\(thing\)' "$SOURCE"
guard "a lock empties the words" 'thing\.content = ""' "$LOCK"
guard "a lock drops the vector made from the words" 'thing\.embedding = nil' "$LOCK"
guard "a lock drops the detected phone number" 'thing\.detectedTel = nil' "$LOCK"
guard "a lock drops the picture" 'thing\.previewImageData = nil' "$LOCK"
guard "a lock re-indexes Spotlight with the sealed record" 'SpotlightIndex\.index\(\[thing\]\)' "$LOCK"
guard "the Notes room asks a note of yours for its preview (prd §983)" \
  'notePreview: Pinboard\.isPinnedRoom\(source\) && Pinboard\.isNote\(thing\)' "$FEED"
guard "a note of yours draws no dial; its keys stand at the foot (prd §983)" \
  'if !pagedNote \{ noteDial \}' "$VIEW"
guard "the keys ride the sheet's foot" 'if pagedNote \{ keptNoteBand \}' "$VIEW"
[[ $fail -eq 0 ]] || { echo "note-checklist-selftest: ✗ drift guard(s) failed"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    if ok { print("  ✓ \(name)") } else { print("  ✗ \(name)"); failures += 1 }
}

print("Reading items")
check("an open item", NoteChecklist.task("- [ ] milk")! == (false, "milk"))
check("a done item, either case", NoteChecklist.task("- [x] milk")!.done && NoteChecklist.task("* [X] eggs")!.done)
check("an item with no words is not an item", NoteChecklist.task("- [ ]") == nil && NoteChecklist.task("- [ ]   ") == nil)
check("a bracket that is not a box is prose", NoteChecklist.task("- [link] here") == nil)
check("a plain bullet is not an item", NoteChecklist.task("- milk") == nil)

print("Blocks")
let body = "Shop\n- [ ] milk\n- [x] eggs\n\nlater\n- [ ] bread"
let blocks = NoteSheet.blocks(body, markdown: false, tasks: true)
let items = blocks.compactMap { b -> (Bool, String, Int)? in
    if case .task(let d, let t, let o) = b { return (d, t, o) } else { return nil }
}
check("three items, in order, numbered 0 1 2",
      items.map(\.2) == [0, 1, 2] && items.map(\.1) == ["milk", "eggs", "bread"])
check("the words around them stay prose",
      blocks.contains(.paragraph("Shop")) && blocks.contains(.paragraph("later")))
check("without the flag a kept note's box is prose",
      !NoteSheet.blocks(body, markdown: false).contains { if case .task = $0 { return true }; return false })
check("a markdown body reads its boxes as items, not bullets",
      NoteSheet.blocks("- [ ] a", markdown: true).first == .task(done: false, text: "a", ordinal: 0))

print("Ticking")
let ticked = NoteChecklist.toggled(body, ordinal: 2)
check("the third item ticks and nothing else moves",
      ticked == "Shop\n- [ ] milk\n- [x] eggs\n\nlater\n- [x] bread")
check("ticking twice is where it started", NoteChecklist.toggled(ticked, ordinal: 2) == body)
check("the done item unticks", NoteChecklist.toggled(body, ordinal: 1).contains("- [ ] eggs"))
check("an ordinal past the list changes nothing", NoteChecklist.toggled(body, ordinal: 9) == body)
check("progress counts the list", NoteChecklist.progress(body)! == (1, 3))

print("Writing")
let o = NoteChecklist.editorMark
check("the key on an empty draft starts an item", NoteChecklist.toggleLastLine("") == o)
check("the key after words starts the next line as an item", NoteChecklist.toggleLastLine("Shop") == "Shop\n" + o)
check("the key on an item takes the circle off", NoteChecklist.toggleLastLine("Shop\n\(o)milk") == "Shop\nmilk")
check("Return after an item starts the next",
      NoteChecklist.continued(old: "\(o)milk", new: "\(o)milk\n") == "\(o)milk\n\(o)")
check("Return on an empty item ends the list",
      NoteChecklist.continued(old: "\(o)milk\n\(o)", new: "\(o)milk\n\(o)\n") == "\(o)milk\n")
check("Return after prose is left alone", NoteChecklist.continued(old: "hi", new: "hi\n") == nil)
check("a paste is left alone", NoteChecklist.continued(old: "\(o)a", new: "\(o)a\nb\n") == nil)
check("kept, circles become boxes and empty items go",
      NoteChecklist.stored("Shop\n\(o)milk\n\(o)\n\(o)eggs") == "Shop\n- [ ] milk\n- [ ] eggs")
check("a list's first item names the note without its box", NoteChecklist.plain("- [ ] milk") == "milk")

print("Editing a kept list (prd §981's edit path)")
let d = NoteChecklist.doneEditorMark
let kept = "Shop\n- [ ] milk\n- [x] eggs"
check("a kept list opens as circles, ticks kept",
      NoteChecklist.editable(kept) == "Shop\n\(o)milk\n\(d)eggs")
check("and keeps again exactly as it was",
      NoteChecklist.stored(NoteChecklist.editable(kept)) == kept)
check("Return after a ticked item starts an open one",
      NoteChecklist.continued(old: "\(d)eggs", new: "\(d)eggs\n") == "\(d)eggs\n\(o)")

print("The room's second line (prd §983)")
func pv(_ t: String, _ c: String, voice: Bool = false, locked: Bool = false) -> String? {
    NotePreview.line(title: t, content: c, isVoice: voice, isLocked: locked)
}
check("a locked note says only that", pv("Locked note", "", locked: true) == "Locked")
// A voice note's line (prd §1099): its length, then the words past its
// title — "Voice note" only when it has neither.
func pvv(_ t: String, _ c: String, _ len: String?) -> String? {
    NotePreview.line(title: t, content: c, isVoice: true, isLocked: false, length: len)
}
check("a voice note with no length and nothing past its title says it is one",
      pvv("the idea", "the idea", nil) == "Voice note")
check("a voice note leads with its length", pvv("the idea", "the idea", "0:42") == "0:42")
check("a cut title has nothing under it but the length",
      pvv(String(repeating: "a", count: 80) + "…", String(repeating: "a", count: 95), "1:05") == "1:05")
check("a corrected transcript reads its next line",
      pvv("Shop", "Shop\noat milk", "0:11") == "0:11 · oat milk")
check("a list says how far and what is next",
      pv("Groceries", "Groceries\n- [x] milk\n- [ ] bread\n- [ ] eggs") == "1 of 3 done · bread")
check("a finished list says it is done", pv("G", "- [x] a\n- [x] b") == "2 of 2 done")
check("the title is never printed twice", pv("Trip", "Trip\nPack the charger") == "Pack the charger")
check("a one-line note has no second line", pv("Just this", "Just this") == nil)
check("a link reads as its thing", pv("Plan", "Plan\nFor [[Book club]] Friday") == "For Book club Friday")

print("Bullets and numbers (prd §1099)")
let b = NoteChecklist.bulletMark
check("a dash and a space at a line's start become a bullet",
      NoteChecklist.bulleted(old: "Trip\n-", new: "Trip\n- ") == "Trip\n\(b)")
check("a star does too", NoteChecklist.bulleted(old: "Trip\n*", new: "Trip\n* ") == "Trip\n\(b)")
check("a dash inside words is left alone", NoteChecklist.bulleted(old: "a -", new: "a - ") == nil)
check("Return after a bullet starts the next",
      NoteChecklist.continued(old: "\(b)milk", new: "\(b)milk\n") == "\(b)milk\n\(b)")
check("Return on an empty bullet ends the list",
      NoteChecklist.continued(old: "\(b)milk\n\(b)", new: "\(b)milk\n\(b)\n") == "\(b)milk\n")
check("Return after a numbered line takes the next number",
      NoteChecklist.continued(old: "1. call", new: "1. call\n") == "1. call\n2. ")
check("kept, a bullet is markdown's dash", NoteChecklist.stored("T\n\(b)milk\n\(b)") == "T\n- milk")
check("and opens as a bullet again", NoteChecklist.editable("T\n- milk") == "T\n\(b)milk")
check("a task is never a bullet", NoteChecklist.bullet("- [ ] milk") == nil)
check("a bullet's first line names the note without its dot", NoteChecklist.plain("- milk") == "milk")
check("the cover keeps a bullet's dot",
      NotePreview.body(title: "T", content: "T\n- milk") == "\(b)milk")

print("The page's tick (prd §1099)")
check("the page ticks the second item and nothing else",
      NoteChecklist.toggledEditor("T\n\(o)a\nx\n\(o)b", ordinal: 1) == "T\n\(o)a\nx\n\(d)b")
check("and unticks it", NoteChecklist.toggledEditor("\(d)b", ordinal: 0) == "\(o)b")

print("A bare address reads as its site (prd §1099)")
check("the scheme and slashes go, the page's last part stays",
      NotePreview.readableLinks("Start at https://en.wikipedia.org/wiki/Bauhaus_Archive.")
          == "Start at en.wikipedia.org › Bauhaus Archive.")
check("a site with no path is its site", NotePreview.readableLinks("see https://www.apple.com") == "see apple.com")

print("The room's cover reads a note of yours")
check("the cover draws the list as circles, never the title or a box",
      NotePreview.body(title: "Groceries", content: "Groceries\n- [x] milk\n- [ ] bread\n\nSee you")
          == "\(d)milk\n\(o)bread\nSee you")
check("a one-line note has no body on its cover",
      NotePreview.body(title: "Just this", content: "Just this").isEmpty)

if failures > 0 { print("note-checklist-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("note-checklist-selftest: assertions pass")
SWIFT

if ! swiftc -Onone -o "$TMP/nc" "$SHEET" "$LIST" "$PREVIEW" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "note-checklist-selftest: ✗ did not compile"; cat "$TMP/build.log"; exit 1
fi
"$TMP/nc" || exit 1

# MUTATIONS — each must be APPLIED (the file changed) and then CAUGHT.
mutate() {  # name, file, perl expression
  local name=$1 file=$2 expr=$3
  local copy="$TMP/mut-${file:t}"
  cp "$file" "$copy"
  perl -0pi -e "$expr" "$copy"
  if cmp -s "$file" "$copy"; then echo "  ✗ mutation did not apply: $name"; fail=1; return; fi
  local a=$SHEET b=$LIST
  [[ $file == $SHEET ]] && a=$copy || b=$copy
  if swiftc -Onone -o "$TMP/mut" "$a" "$b" "$PREVIEW" "$TMP/main.swift" 2>/dev/null && "$TMP/mut" >/dev/null 2>&1; then
    echo "  ✗ SURVIVED: $name"; fail=1
  else
    echo "  ✓ caught: $name"
  fi
}

echo "Mutations"
mutate "a tick flips the first item, whatever was tapped" "$LIST" 's/if seen == ordinal \{/if true {/'
mutate "kept circles stay circles" "$LIST" 's/lead \+ \(done \? doneMark : openMark\) \+ words/lead + editorMark + words/'
mutate "Return on an empty item starts another" "$LIST" 's/if words\.isEmpty \{/if false {/'
mutate "items are never numbered past the first" "$SHEET" 's/ordinal \+= 1\n/\n/'
mutate "an edit drops the ticks" "$LIST" 's/return lead \+ \(item\.done \? doneEditorMark : editorMark\)/return lead + editorMark/'
mutate "a bullet keeps as a dot" "$LIST" 's/lead \+ keptBullet \+ words/lead + bulletMark + words/'
mutate "a numbered list repeats its number" "$LIST" 's/item\.number \+ 1/item.number/'
mutate "the page ticks the first item, whatever was tapped" "$LIST" 's/if seen == ordinal \{\n                lines\[i\] = lead/if true {\n                lines[i] = lead/'
mutate "the tasks flag is ignored" "$SHEET" 's/if tasks \|\| takesMarkers, let item/if takesMarkers, let item/'

[[ $fail -eq 0 ]] || { echo "note-checklist-selftest: ✗ mutation check failed"; exit 1; }
echo "note-checklist-selftest: OK — assertions, guards and mutations all pass."
