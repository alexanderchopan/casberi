#!/bin/zsh
# Casberi note-checklist self-test (prd §982) — the pure logic behind a note's
# checklist, compiled WHOLE and UNMODIFIED:
#
#   Casberi/Casberi/Model/NoteSheet.swift     — taskLine, blocks(tasks:)
#   Casberi/Casberi/Model/NoteChecklist.swift — stored, toggled, continuedAt,
#                                               toggleLine, toggleLastLine, plain
#   Casberi/Casberi/Model/NoteLinkTyping.swift — `[[` at the cursor
#
# Every failure here is a SILENT WRONG ANSWER: a tick that flips the wrong
# item, a kept list whose empty circles land as empty boxes, Return that
# never ends a list, a vault's `- [ ]` ticked in the app and overwritten by
# the next sync, a title reading "- [ ] milk".
#
# The drift guards cover the wiring the pure files cannot prove: that the
# sheet keeps the STORED form, that Return goes through `continuedAt`, that a
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
TYPING="Casberi/Casberi/Model/NoteLinkTyping.swift"
FIND="Casberi/Casberi/Model/NoteFind.swift"
TASK="Casberi/Shared/NoteTask.swift"
EXPORT="Casberi/Casberi/Model/NoteExport.swift"
PICS="Casberi/Shared/NotePictures.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"

fail=0
guard() {  # name, pattern, file
  if grep -Eq -- "$2" "$3"; then echo "  ✓ $1"; else echo "  ✗ $1 ($3)"; fail=1; fi
}

echo "Drift guards — the wiring"
guard "the sheet keeps the stored form, never the circles" \
  'NoteChecklist\.stored\(draft\)' "$CAPTURE"
guard "an edit opens a kept list as circles" \
  'draft = NoteChecklist\.editable\(note\.content\)' "$CAPTURE"
guard "Return inside a list goes through continuedAt, at the cursor" \
  'NoteChecklist\.continuedAt\(old: parts\.body, new: new,' "$CAPTURE"
guard "the words field reports its cursor" \
  'selection: \$bodySelection' "$CAPTURE"
guard "the checklist key acts on the cursor's line" \
  'NoteChecklist\.toggleLine\(words, at: cursor\)' "$CAPTURE"
guard "the Notes room filters through NoteFind" \
  'NoteFind\.matches\(title: thing\.title, content: thing\.content,' "$FEED"
guard "a typed [[ completes through NoteLinkTyping" \
  'NoteLinkTyping\.completed\(parts\.body, start: start, cursor: cursor, title: title\)' "$CAPTURE"
guard "a tick goes through toggled" \
  'NoteChecklist\.toggled\(thing\.content, ordinal: ordinal\)' "$VIEW"
guard "a tick is offered only where ticksTasks allows it" \
  'onToggleTask: NoteSheetSource\.ticksTasks\(thing\)' "$VIEW"
guard "a vault's list is never ticked (ticksTasks is kept notes only)" \
  'isKeptNote\(thing\) && thing\.kind == \.note && !NoteLock\.isLocked\(thing\)' "$SOURCE"
guard "a lock empties the words" 'thing\.content = ""' "$LOCK"
guard "a lock seals the pictures after the first" 'thing\.notePictures = nil' "$LOCK"
guard "Add to note knows a locked note by the lock's own mark" 'static let lockedRef = "notelock:v1"' "Casberi/Shared/NoteAppend.swift"
guard "and the lock still spells its mark that way" 'static let refMark = "notelock:v1"' "$LOCK"
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
func cont(_ old: String, _ new: String, hint: Int? = nil) -> (text: String, cursor: Int)? {
    NoteChecklist.continuedAt(old: old, new: new, hint: hint)
}
check("Return after an item starts the next",
      cont("\(o)milk", "\(o)milk\n")?.text == "\(o)milk\n\(o)")
check("and the cursor stands after the new circle",
      cont("\(o)milk", "\(o)milk\n")?.cursor == "\(o)milk\n\(o)".count)
check("Return on an empty item ends the list",
      cont("\(o)milk\n\(o)", "\(o)milk\n\(o)\n")?.text == "\(o)milk\n")
check("Return after prose is left alone", cont("hi", "hi\n") == nil)
check("a paste is left alone", cont("\(o)a", "\(o)a\nb\n") == nil)

print("Writing at the cursor (the note-editor ruling)")
let mid = "\(o)milk\nlater"
check("Return at the end of an item in the MIDDLE starts the next item",
      cont(mid, "\(o)milk\n\nlater")?.text == "\(o)milk\n\(o)\nlater")
check("Return inside an item splits it into two items",
      cont("\(o)milk", "\(o)mi\nlk")?.text == "\(o)mi\n\(o)lk")
check("Return on an empty item mid-list ends the list there",
      cont("\(o)a\n\(o)\nb", "\(o)a\n\(o)\n\nb")?.text == "\(o)a\n\nb")
check("the hint picks Return on the blank line under a list, not after its item",
      cont("\(o)a\n\nb", "\(o)a\n\n\nb", hint: 4) == nil)
check("with no hint, the end of the item above",
      cont("\(o)a\n\nb", "\(o)a\n\n\nb")?.text == "\(o)a\n\(o)\n\nb")
let three = "Shop\nmilk\neggs"
check("the key turns the cursor's line into an item",
      NoteChecklist.toggleLine(three, at: 7).text == "Shop\n\(o)milk\neggs")
check("and moves the cursor with its words",
      NoteChecklist.toggleLine(three, at: 7).cursor == 9)
check("the key on an item takes that circle off, not the last line's",
      NoteChecklist.toggleLine("\(o)a\n\(o)b", at: 1).text == "a\n\(o)b")
check("the cursor never lands inside a removed circle",
      NoteChecklist.toggleLine("\(o)a", at: 1).cursor == 0)
check("the key on an empty text starts an item", NoteChecklist.toggleLine("", at: 0).text == o)
check("the lit state reads the cursor's line",
      NoteChecklist.isItem("\(o)a\nb", at: 1) && !NoteChecklist.isItem("\(o)a\nb", at: 4))

print("A link typed at the cursor")
let typed = "See [[Boo"
check("an open [[ is a question", NoteLinkTyping.openQuery(in: typed, cursor: typed.count)! == (4, "Boo"))
check("a closed link is not", NoteLinkTyping.openQuery(in: "See [[Book]] x", cursor: 14) == nil)
check("a new line ends the question", NoteLinkTyping.openQuery(in: "[[a\nb", cursor: 5) == nil)
check("one bracket is prose", NoteLinkTyping.openQuery(in: "a [b", cursor: 4) == nil)
check("the cursor before the brackets asks nothing", NoteLinkTyping.openQuery(in: typed, cursor: 3) == nil)
let done = NoteLinkTyping.completed(typed, start: 4, cursor: typed.count, title: "Book club")
check("a pick writes the exact title in brackets", done.text == "See [[Book club]]")
check("and the cursor stands after it", done.cursor == "See [[Book club]]".count)
check("a ]] already there is taken, not doubled",
      NoteLinkTyping.completed("[[Bo]] x", start: 0, cursor: 4, title: "Book").text == "[[Book]] x")
check("the offer is the pool's order, filtered, three at most",
      NoteLinkTyping.offers("b", in: ["Bread", "Apple", "Book", "Bike", "Boat"]) == ["Bread", "Book", "Bike"])
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
      cont("\(d)eggs", "\(d)eggs\n")?.text == "\(d)eggs\n\(o)")

print("The room's second line (prd §983)")
func pv(_ t: String, _ c: String, voice: Bool = false, locked: Bool = false) -> String? {
    NotePreview.line(title: t, content: c, isVoice: voice, isLocked: locked)
}
check("a locked note says only that", pv("Locked note", "", locked: true) == "Locked")
check("a voice note says it is one", pv("Idea", "the idea", voice: true) == "Voice note")
check("a list says how far and what is next",
      pv("Groceries", "Groceries\n- [x] milk\n- [ ] bread\n- [ ] eggs") == "1 of 3 done · bread")
check("a finished list says it is done", pv("G", "- [x] a\n- [x] b") == "2 of 2 done")
check("the title is never printed twice", pv("Trip", "Trip\nPack the charger") == "Pack the charger")
check("a one-line note has no second line", pv("Just this", "Just this") == nil)
check("a link reads as its thing", pv("Plan", "Plan\nFor [[Book club]] Friday") == "For Book club Friday")

print("Add to note (Shared/NoteTask)")
check("a note that ends in a list takes each line as an item",
      NoteTask.appended("Groceries\n- [ ] milk", "bread\n\neggs") == "Groceries\n- [ ] milk\n- [ ] bread\n- [ ] eggs")
check("an item already spelled is not boxed twice",
      NoteTask.appended("- [ ] a", "- [x] b") == "- [ ] a\n- [x] b")
check("prose takes the words on a new line", NoteTask.appended("Plan\nFriday", "bring cake") == "Plan\nFriday\nbring cake")
check("nothing to add changes nothing", NoteTask.appended("Plan", "  \n ") == "Plan")
check("an empty note takes the words", NoteTask.appended("", "hello") == "hello")
check("the widget's items read the same parser",
      NoteTask.items("x\n- [ ] a\n- [x] b").map(\.text) == ["a", "b"])

print("The Note widget's page (Shared/NoteTask)")
let pg = NoteTask.page(title: "Groceries", content: "Groceries\n- [x] milk\n\nfor [[Book club]]\n- [ ] bread")
check("the title's own line goes, blank lines go, links read as titles",
      pg == [.item(done: true, text: "milk", ordinal: 0), .words("for Book club"),
             .item(done: false, text: "bread", ordinal: 1)])
check("a list's first item stays an item when it names the note",
      NoteTask.page(title: "milk", content: "- [ ] milk\n- [ ] eggs").count == 2)
check("a long first line cut into the title still goes",
      NoteTask.page(title: "A very long first line…", content: "A very long first line that ran on\nnext") == [.words("next")])

print("Export as Markdown")
let day = Date(timeIntervalSince1970: 1_790_000_000)
let ex = NoteExport.plan([
    .init(title: "Groceries", content: "Groceries\n- [ ] milk", folder: "Home", created: day),
    .init(title: "Groceries", content: "Groceries\nagain", folder: "home", created: day),
    .init(title: "Secret", content: "", folder: nil, created: day, isLocked: true),
    .init(title: "a/b: c?", content: "x", folder: nil, created: day, hasPicture: true, morePictures: 2),
])
check("a locked note is left out, and counted", ex.lockedLeftOut == 1)
check("a folder is a directory, one whatever its case",
      ex.files.filter { $0.path.first == "Home" }.count == 2 && !ex.files.contains { $0.path.first == "home" })
check("two notes with one title in one folder get two names",
      Set(ex.files.map { $0.path.joined(separator: "/") }).isSuperset(of: ["Home/Groceries.md", "Home/Groceries 2.md"]))
check("a title is a safe file name", ex.files.contains { $0.path == ["a b c.md"] })
check("every picture after the first is a file of its own, embedded in order",
      ex.files.contains { $0.path == ["a b c 3.jpg"] && $0.body == .picture(note: 3, index: 2) }
      && ex.files.contains { if case .markdown(let m) = $0.body { return m.contains("![[a b c.jpg]]\n![[a b c 2.jpg]]\n![[a b c 3.jpg]]") }; return false })

print("A note's pictures (Shared/NotePictures)")
let pics = [Data([1]), Data([2]), Data([3])]
check("the pictures after the first round-trip", NotePictures.decode(NotePictures.encode(pics)) == pics)
check("none is no field", NotePictures.encode([]) == nil)
check("a field past the limit keeps the limit",
      NotePictures.decode(NotePictures.encode(Array(repeating: Data([9]), count: 12))).count == NotePictures.limit - 1)
check("a field that does not decode is no pictures", NotePictures.decode(Data([0, 1, 2])).isEmpty)
check("all is the first, then the rest", NotePictures.all(first: Data([0]), rest: NotePictures.encode(pics)).count == 4)
check("room counts down to zero", NotePictures.room(after: NotePictures.limit) == 0 && NotePictures.room(after: 99) == 0)
check("the picture sits beside its note and is embedded",
      ex.files.contains { $0.path == ["a b c.jpg"] && $0.body == .picture(note: 3) }
      && ex.files.contains { if case .markdown(let m) = $0.body { return m.contains("![[a b c.jpg]]") }; return false })
if case .markdown(let md)? = ex.files.first(where: { $0.path == ["Home", "Groceries.md"] })?.body {
    check("the words keep their list, under a date", md.contains("created: ") && md.contains("- [ ] milk"))
    check("no heading when the words open with the title", !md.contains("# Groceries"))
} else { check("the first note has a file", false) }
check("a note whose words do not open with its title gets it as a heading",
      NoteExport.markdown(.init(title: "Photo", content: "", folder: nil, created: day), embeds: []).contains("# Photo"))

print("Find in Notes")
func find(_ q: String, _ t: String, _ c: String = "", folder: String? = nil) -> Bool {
    NoteFind.matches(title: t, content: c, folder: folder, query: q)
}
check("an empty query is no filter", find("   ", "anything"))
check("a word in the title matches", find("grocer", "Groceries"))
check("a word in the words matches", find("bread", "Groceries", "- [ ] bread"))
check("a folder's name matches", find("work", "Plan", folder: "Work"))
check("every word must match, in any order", find("bread shop", "Shop", "bread") && !find("bread car", "Shop", "bread"))
check("case and accents fold", find("CAFE", "Café list"))
check("a locked note is found by title only", !find("secret", "Locked note", ""))

print("The room's cover reads a note of yours")
check("the cover draws the list as circles, never the title or a box",
      NotePreview.body(title: "Groceries", content: "Groceries\n- [x] milk\n- [ ] bread\n\nSee you")
          == "\(d)milk\n\(o)bread\nSee you")
check("a one-line note has no body on its cover",
      NotePreview.body(title: "Just this", content: "Just this").isEmpty)

if failures > 0 { print("note-checklist-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("note-checklist-selftest: assertions pass")
SWIFT

if ! swiftc -Onone -o "$TMP/nc" "$SHEET" "$LIST" "$PREVIEW" "$TYPING" "$FIND" "$TASK" "$EXPORT" "$PICS" "$TMP/main.swift" 2>"$TMP/build.log"; then
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
  local a=$SHEET b=$LIST c=$TYPING
  [[ $file == $SHEET ]] && a=$copy
  [[ $file == $LIST ]] && b=$copy
  [[ $file == $TYPING ]] && c=$copy
  local f=$FIND t=$TASK
  [[ $file == $FIND ]] && f=$copy
  [[ $file == $TASK ]] && t=$copy
  local e=$EXPORT
  [[ $file == $EXPORT ]] && e=$copy
  if swiftc -Onone -o "$TMP/mut" "$a" "$b" "$PREVIEW" "$c" "$f" "$t" "$e" "$PICS" "$TMP/main.swift" 2>/dev/null && "$TMP/mut" >/dev/null 2>&1; then
    echo "  ✗ SURVIVED: $name"; fail=1
  else
    echo "  ✓ caught: $name"
  fi
}

echo "Mutations"
mutate "a tick flips the first item, whatever was tapped" "$TASK" 's/if seen == ordinal \{/if true {/'
mutate "kept circles stay circles" "$LIST" 's/lead \+ \(done \? doneMark : openMark\) \+ words/lead + editorMark + words/'
mutate "Return on an empty item starts another" "$LIST" 's/if words\.isEmpty && /if false && /'
mutate "the hint is ignored" "$LIST" 's/let p = hint\.map \{ min\(max\(\$0, first\), last\) \} \?\? first/let p = first/'
mutate "the key acts on the last line whatever the cursor" "$LIST" 's/let \(start, end\) = lineBounds\(text, at: at\)\n        let line = String\(chars\[start\.\.<end\]\)/let (start, end) = lineBounds(text, at: chars.count)\n        let line = String(chars[start..<end])/'
mutate "a closing bracket does not end the question" "$TYPING" 's/if c == "\\n" \|\| c == "\]" \{ return nil \}/if c == "\\n" { return nil }/'
mutate "a list's addition lands as prose" "$TASK" 's/if line\(lastLine\) != nil \{/if false {/'
mutate "a locked note is exported" "$EXPORT" 's/if note\.isLocked \{ locked \+= 1; continue \}/if note.isLocked { locked += 1 }/'
mutate "one matching word is enough" "$FIND" 's/wanted\.allSatisfy/wanted.contains/'
mutate "a ]] at the cursor is doubled" "$TYPING" 's/to \+= 2/to += 0/'
mutate "items are never numbered past the first" "$SHEET" 's/ordinal \+= 1\n/\n/'
mutate "an edit drops the ticks" "$LIST" 's/return lead \+ \(item\.done \? doneEditorMark : editorMark\)/return lead + editorMark/'
mutate "the tasks flag is ignored" "$SHEET" 's/if tasks \|\| takesMarkers, let item/if takesMarkers, let item/'

[[ $fail -eq 0 ]] || { echo "note-checklist-selftest: ✗ mutation check failed"; exit 1; }
echo "note-checklist-selftest: OK — assertions, guards and mutations all pass."
