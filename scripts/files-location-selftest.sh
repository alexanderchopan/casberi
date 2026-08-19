#!/bin/zsh
# Casberi Files-location self-test — the SHIPPED pure logic behind the folder
# door on a folder-picked file (2026-08-19, prd §408):
#
#   Casberi/Casberi/Model/FilesLocation.swift
#     — components  (the path inside the connected folder, fenced)
#     — folderName  ("in Receipts", the words the sheet's From row says)
#     — revealURL   (where pressing that row lands in the Files app)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion below is about the
# bytes the app runs.
#
# WHY A HARNESS. Nothing on this side can be seen from a build, a screen sweep
# or a simulator, and each failure renders as a perfectly ordinary row:
#
#   • a ref that walks upward ("..") building a URL onto a folder OUTSIDE the
#     one the person picked — the string is handed to another app, so nothing
#     here would ever report it;
#   • the FILE's path where the folder's was meant, which opens a preview of
#     the thing the person is already looking at instead of taking them to
#     where it is saved (the whole of the request);
#   • an unencoded space or `#` in a folder name, which makes `URL(string:)`
#     answer nil or truncate — i.e. the door silently stops existing for
#     exactly the people whose folders have ordinary names;
#   • "in June.pdf" — the FILE named as the place it is in — which reads as a
#     sentence and is a lie.
#
# The URL SCHEME itself cannot be proven here and this harness does not
# pretend to: iOS publishes no public API that reveals a file, so
# `shareddocuments://` is unmeasured and `-filesRevealProbe` is what measures
# it. What the drift guards below prove is that the door is GATED — declared
# in Info.plist, probed by HandOffState, and offered only when something
# claims the scheme — because an unclaimed scheme is refused asynchronously
# and reports success, which is the dead control §83 bans.
#
# Pure, local, deterministic — no network, no simulator, no folder. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

LOC="Casberi/Casberi/Model/FilesLocation.swift"
BRIDGE="Casberi/Casberi/Model/FilesBridge.swift"
VERBS="Casberi/Casberi/Model/Verbs.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
FEED="Casberi/Casberi/Screens/FeedScreen.swift"
PLIST="Casberi/Casberi/Info.plist"
for f in "$LOC" "$BRIDGE" "$VERBS" "$SHEET" "$FEED" "$PLIST"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Facts the compiled functions can't prove on their own. A perfect URL builder
# is worthless if nothing offers it, or if it is offered where it can't work.

# The ref shape this whole file parses is stamped by the walk. If the walk's
# prefix ever changes, every function here answers nil and the door silently
# stops existing for every file in the corpus.
grep -qF 'ref: "files:\(rel)"' "$BRIDGE" \
  || { echo "✗ FilesIngest.walk no longer stamps a 'files:' ref — FilesLocation"; \
       echo "  parses that prefix and would answer nil for every file"; exit 1; }
grep -q 'static let refPrefix = "files:"' "$LOC" \
  || { echo "✗ FilesLocation.refPrefix no longer matches what the walk stamps"; exit 1; }
# The verb's own gate must run the SAME parse the row's does, or a fenced ref
# offers a disc and no row (or the other way round).
grep -q 'FilesLocation.components(ref: thing.sourceRef) != nil' "$VERBS" \
  || { echo "✗ the Files verb no longer parses the ref through FilesLocation —"; \
       echo "  a fenced ref would offer a door the row refuses to draw"; exit 1; }

# The door itself: resolve the bookmark HERE, build the URL there.
grep -q 'static func revealURL(for sourceRef: String?) -> URL?' "$BRIDGE" \
  || { echo "✗ FilesIngest.revealURL is gone — the sheet has no way to resolve"; \
       echo "  the bookmark, so the From row can never become a door"; exit 1; }

# The hand-off is gated three ways, and all three are load-bearing.
grep -q '<string>shareddocuments</string>' "$PLIST" \
  || { echo "✗ shareddocuments is not in LSApplicationQueriesSchemes — canOpenURL"; \
       echo "  always answers false and the verb could never appear"; exit 1; }
grep -q '"shareddocuments"' "$VERBS" \
  || { echo "✗ shareddocuments is not in HandOffState.candidates — nothing ever"; \
       echo "  probes it, so installedSchemes can never contain it"; exit 1; }
grep -q 'installedSchemes.contains(FilesLocation.revealScheme)' "$VERBS" \
  || { echo "✗ the Files verb is ungated — an unclaimed scheme is refused"; \
       echo "  asynchronously and reports success, so it would be a disc that does nothing"; exit 1; }
# Scoped to the SOURCE, never the kind: Dropbox lands `.file` rows too and its
# bytes are not on this device, so the Files app has nothing to show for one.
grep -qE 'thing\.source == "Files",$' "$VERBS" \
  || { echo "✗ the Files verb is no longer scoped to the Files source — a Dropbox"; \
       echo "  row would offer a folder that does not exist on this device"; exit 1; }

# Both verb dispatchers must run it. A `Verb.Action` case that one switch
# handles and the other doesn't is a verb that works from one surface only.
grep -q 'case .showInFiles:' "$SHEET" \
  || { echo "✗ the thing sheet no longer performs .showInFiles"; exit 1; }
grep -q 'case .showInFiles:' "$FEED" \
  || { echo "✗ the feed no longer performs .showInFiles"; exit 1; }

# The row the feedback pointed at. `specRow` is a label; `fromRow` is the one
# that can become a door.
grep -q 'fromRow(PlaceWords.line(for: thing))' "$SHEET" \
  || { echo "✗ the sheet's From row is a plain label again — the press that was"; \
       echo "  asked for goes nowhere"; exit 1; }
# …and it must still stand down when there is nowhere to go. The gate is the
# CHEAP one (no bookmark resolve in a view body), so a stale bookmark reaches
# the tap and its sentence — but an unparseable ref, an unconnected folder and
# an unclaimed scheme never draw a chevron at all.
grep -q 'FilesLocation.components(ref: thing.sourceRef) != nil' "$SHEET" \
  || { echo "✗ the From row is a button unconditionally — a row that shrugs is"; \
       echo "  the dead control §83 bans"; exit 1; }
grep -q 'thing.source == "Files", FilesStore.shared.connected' "$SHEET" \
  || { echo "✗ the From row's door no longer requires a connected folder"; exit 1; }

# The From row's words come from the folder, not from six fixed words.
grep -q 'FilesLocation.folderName(ref: thing.sourceRef' "$VERBS" \
  || { echo "✗ PlaceWords no longer names the folder — every file in the corpus"; \
       echo "  reads 'in your folder' again"; exit 1; }

# NEGATIVE, and read from a COMMENT-STRIPPED copy: this file's own doc explains
# the rule by naming what it must not do, so a guard grepping raw source fires
# on the prose explaining it (the Obsidian/Cursor lesson).
#
# `showInFiles` must not route through `jump`, which copies the thing's words
# to the pasteboard first. That is right for Calendar and Reminders (neither
# scheme can carry text) and wrong here: the destination is the whole verb, and
# replacing somebody's clipboard on the way is a side effect nothing on screen
# promised.
python3 - "$VERBS" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
body = src.split("static func showInFiles", 1)
if len(body) < 2:
    print("✗ HandOff.showInFiles is gone"); sys.exit(1)
# The function ends at the next declaration at the same depth; the next
# `enum `/`static func ` line is close enough and errs toward MORE text.
rest = body[1]
end = re.search(r"\n    (static func |enum |}\n)", rest)
fn = rest[: end.start()] if end else rest
code = "\n".join(l for l in fn.splitlines() if not l.strip().startswith("//"))
for banned, why in (("DSPasteboard", "copies to the pasteboard"),
                    ("jump(", "routes through `jump`, which copies first")):
    if banned in code:
        print(f"✗ HandOff.showInFiles {why} — the destination is the whole verb")
        sys.exit(1)
if "canOpenURL" not in code:
    print("✗ HandOff.showInFiles no longer checks canOpenURL before opening")
    sys.exit(1)
PY

TMP=$(mktemp -d /tmp/files-location-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func folder(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

// ── components — the fence ─────────────────────────────────────────────────
print("components — the path inside the connected folder")
check("a nested file splits", FilesLocation.components(ref: "files:/Receipts/June.pdf")
        == ["Receipts", "June.pdf"])
check("a file at the root is one component",
      FilesLocation.components(ref: "files:/June.pdf") == ["June.pdf"])
check("a ref with no leading separator still parses",
      FilesLocation.components(ref: "files:June.pdf") == ["June.pdf"])
check("repeated separators collapse",
      FilesLocation.components(ref: "files://a//June.pdf") == ["a", "June.pdf"])
check("a deep path keeps every component",
      FilesLocation.components(ref: "files:/a/b/c/June.pdf") == ["a", "b", "c", "June.pdf"])
// The fence. Each of these would name a folder outside the picked one.
check("a parent walk is refused", FilesLocation.components(ref: "files:/../secrets/x.pdf") == nil)
check("a parent walk anywhere in the path is refused",
      FilesLocation.components(ref: "files:/a/../../x.pdf") == nil)
check("a `.` component is refused", FilesLocation.components(ref: "files:/a/./x.pdf") == nil)
// Failures are nil, never a best effort.
check("another bridge's ref → nil", FilesLocation.components(ref: "obsidian:/A.md") == nil)
check("a bare prefix → nil", FilesLocation.components(ref: "files:") == nil)
check("a prefix and a separator → nil", FilesLocation.components(ref: "files:/") == nil)
check("no ref at all → nil", FilesLocation.components(ref: nil) == nil)
check("an empty string → nil", FilesLocation.components(ref: "") == nil)

// ── folderName — the words the row says ────────────────────────────────────
print("\nfolderName — the place, in a sentence")
check("a nested file names its immediate parent",
      FilesLocation.folderName(ref: "files:/Receipts/June.pdf", connectedFolder: "Downloads")
        == "Receipts")
check("a deep file names the parent, not the path",
      FilesLocation.folderName(ref: "files:/Documents/2026/Q3/Receipts/June.pdf",
                               connectedFolder: "Downloads") == "Receipts")
check("a file at the root takes the connected folder's name",
      FilesLocation.folderName(ref: "files:/June.pdf", connectedFolder: "Downloads")
        == "Downloads")
check("…and never the file's own name",
      FilesLocation.folderName(ref: "files:/June.pdf", connectedFolder: "Downloads")
        != "June.pdf")
check("no connected name → nil, so the caller keeps its old words",
      FilesLocation.folderName(ref: "files:/June.pdf", connectedFolder: "") == nil)
check("a blank connected name → nil",
      FilesLocation.folderName(ref: "files:/June.pdf", connectedFolder: "   ") == nil)
check("a folder name is trimmed",
      FilesLocation.folderName(ref: "files:/June.pdf", connectedFolder: " Downloads ")
        == "Downloads")
check("another bridge's ref → nil",
      FilesLocation.folderName(ref: "dropbox:/June.pdf", connectedFolder: "Downloads") == nil)
check("a fenced ref → nil",
      FilesLocation.folderName(ref: "files:/../June.pdf", connectedFolder: "Downloads") == nil)

// ── revealURL — where the press lands ──────────────────────────────────────
print("\nrevealURL — the folder, never the file")
check("a nested file resolves to its FOLDER",
      FilesLocation.revealURL(folder: folder("/private/var/mobile/Docs"),
                              ref: "files:/Receipts/June.pdf")?.absoluteString
        == "shareddocuments:///private/var/mobile/Docs/Receipts")
check("a file at the root resolves to the connected folder",
      FilesLocation.revealURL(folder: folder("/private/var/mobile/Docs"),
                              ref: "files:/June.pdf")?.absoluteString
        == "shareddocuments:///private/var/mobile/Docs")
check("a deep file resolves to the folder it is in",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/a/b/c/June.pdf")?
        .absoluteString == "shareddocuments:///Docs/a/b/c")
check("the file's own name never reaches the URL",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/Receipts/June.pdf")?
        .absoluteString.contains("June") == false)
// Encoding. Each of these is an ordinary folder name and each breaks
// `URL(string:)` unencoded — i.e. the door disappears for whoever has one.
check("a space is encoded",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/My Receipts/June.pdf")?
        .absoluteString == "shareddocuments:///Docs/My%20Receipts")
check("a `#` is encoded (it would otherwise end the URL)",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/Notes #1/June.pdf")?
        .absoluteString == "shareddocuments:///Docs/Notes%20%231")
check("a `?` is encoded",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/Why?/June.pdf")?
        .absoluteString == "shareddocuments:///Docs/Why%3F")
check("a percent is encoded",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/100%/June.pdf")?
        .absoluteString == "shareddocuments:///Docs/100%25")
check("a non-Latin folder name still builds a URL",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/読書/June.pdf") != nil)
check("the separators survive",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/a/b/June.pdf")?
        .absoluteString.hasSuffix("/Docs/a/b") == true)
// Failures are nil, never a URL onto the wrong place.
check("a fenced ref → nil",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/../x/June.pdf") == nil)
check("another bridge's ref → nil",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "dropbox:/June.pdf") == nil)
check("no ref → nil", FilesLocation.revealURL(folder: folder("/Docs"), ref: nil) == nil)
check("a bare prefix → nil", FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:") == nil)
check("a folder that isn't a file URL → nil",
      FilesLocation.revealURL(folder: URL(string: "https://example.com/Docs")!,
                              ref: "files:/Receipts/June.pdf") == nil)
check("the scheme is the Files app's own",
      FilesLocation.revealURL(folder: folder("/Docs"), ref: "files:/a/June.pdf")?.scheme
        == FilesLocation.revealScheme)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "$LOC" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped FilesLocation.swift did not compile against the harness"
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
  cp "$LOC" "$WORK/FilesLocation.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/FilesLocation.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/FilesLocation.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/FilesLocation.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. The fence dropped — a ref walks out of the folder the person picked.
mutate "the parent-walk fence removed" \
  'guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }' \
  'guard !parts.isEmpty else { return nil }'

# 2. The whole path where the parent belonged — a field value wearing "in".
mutate "the folder named by its whole path" \
  'if parts.count >= 2 { return parts[parts.count - 2] }' \
  'if parts.count >= 2 { return parts.dropLast().joined(separator: "/") }'

# 3. The FILE named as the place it is in.
mutate "the file named as its own folder" \
  'if parts.count >= 2 { return parts[parts.count - 2] }' \
  'if parts.count >= 2 { return parts[parts.count - 1] }'

# 4. An empty connected name answered anyway — "in " with nothing after it.
mutate "an empty connected folder name accepted" \
  'return root.isEmpty ? nil : root' \
  'return root'

# 5. The file's own path in the URL — opens a preview of what you are looking at.
mutate "the URL points at the file, not the folder" \
  'for part in parts.dropLast() { url.appendPathComponent(part) }' \
  'for part in parts { url.appendPathComponent(part) }'

# 6. Encoding dropped — the door vanishes for any folder with a space in it.
mutate "percent encoding dropped" \
  'let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)' \
  'let encoded = Optional(path)'

# 7. The file-URL guard dropped — anything with a path builds a door.
mutate "the file-URL guard removed" \
  'guard folder.isFileURL, let parts = components(ref: ref) else { return nil }' \
  'guard let parts = components(ref: ref) else { return nil }'

echo
echo "✓ files-location self-test: assertions and mutations all passed"
