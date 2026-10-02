#!/bin/zsh
# Casberi mail-scope self-test — the mail rooms' tiles (prd §1019):
#
#   Casberi/Casberi/Model/MailScope.swift
#   Casberi/Casberi/Model/MailBridge.swift
#   Casberi/Casberi/Model/LiveRoomSources.swift
#   Casberi/Casberi/Model/SourceActions.swift
#   Casberi/Casberi/Screens/FeedScreen.swift
#   Casberi/Casberi/Shell/MainSurface.swift
#
# What it proves:
#
#   · the two mail seats are ONE room shape, and the scope names both — a tile
#     set that reached one and not the other would be two rooms pretending to
#     be one
#   · the Attachments tile reads the fact the ingest writes, under one
#     spelling (`MailScope.attachedLabel`) at the write and the read
#   · All and the verb stand every mail; Attachments stands only a mail that
#     came with a file; a mail with no facts stands under All alone
#   · New is a verb, and its tap resolves through `SourceActions` — the one
#     place that already decides Gmail's app over `mailto:`
#   · the "New email" compose row no longer draws in either mail room (§752)
#   · a connected mail seat with no rows keeps its room and holds its lead
#   · the room resets to All on every source change
#
# `MailScope.swift` is Foundation-only by design and is compiled WHOLE AND
# UNMODIFIED below. Pure, local, deterministic. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

SCOPE="Casberi/Casberi/Model/MailScope.swift"
BRIDGE="Casberi/Casberi/Model/MailBridge.swift"
LIVE="Casberi/Casberi/Model/LiveRoomSources.swift"
ACTIONS="Casberi/Casberi/Model/SourceActions.swift"
# FeedScreen is split across files (prd §718). Checks read the room as ONE text,
# so a guard can neither fail nor pass because its code moved next door.
FEED_DIR="$(mktemp -d)"
FEED="$FEED_DIR/FeedScreen.swift"
cat Casberi/Casberi/Screens/FeedScreen.swift Casberi/Casberi/Screens/FeedScreen+*.swift > "$FEED"
SURFACE="Casberi/Casberi/Shell/MainSurface.swift"
for f in "$SCOPE" "$BRIDGE" "$LIVE" "$ACTIONS" "$FEED" "$SURFACE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards ------------------------------------------------------------
# The ingest writes the attachment fact under the scope's own label, never a
# second spelling the tile would not find.
grep -qF 'ThingFact(MailScope.attachedLabel,' "$BRIDGE" \
  || { echo "✗ MailBridge no longer writes the attachment fact under MailScope.attachedLabel — the Attachments tile would read nothing"; exit 1; }
grep -qF 'String(localized: "Attached")' "$BRIDGE" \
  && { echo "✗ MailBridge spells the attachment label itself — one spelling, MailScope.attachedLabel"; exit 1; }
# Both seats, by the names the bridge's provider enum carries.
for seat in '"iCloud Mail"' '"Gmail"'; do
  grep -q "case [a-z]* *= *$seat" "$BRIDGE" || { echo "✗ MailProvider no longer names $seat"; exit 1; }
done
# The room shape is one for both (the §911 arm), and the feed reads the pick
# once, filters by fact labels, draws the tiles through standaloneLead, and
# never draws the compose row for a mail room.
grep -qF 'case "Gmail", "iCloud Mail": self = .gmail' "$FEED" \
  || { echo "✗ the two mail seats no longer share the .gmail shape"; exit 1; }
grep -qF 'let mailPick = MailScope.rooms.contains(source) ? chrome.mailScope : .all' "$FEED" \
  || { echo "✗ the feed no longer reads the mail pick once before the filter (the §993 defect)"; exit 1; }
grep -qF 'mailPick.allows(factLabels: thing.facts.compactMap { ThingFact(encoded: $0)?.label })' "$FEED" \
  || { echo "✗ the feed no longer filters mail by its fact labels"; exit 1; }
grep -qF 'tiles: heroShown ? nil : mailTiles' "$FEED" \
  || { echo "✗ the mail room no longer draws its tiles through standaloneLead"; exit 1; }
grep -qF '!MailScope.rooms.contains(bridge.name),' "$FEED" \
  || { echo "✗ the \"New email\" compose row is back at the top of the mail rooms (§752)"; exit 1; }
grep -qF 'let compose = SourceActions.action(forSource: source)' "$FEED" \
  || { echo "✗ the New tile no longer resolves through SourceActions — Gmail's app over mailto: is decided there"; exit 1; }
grep -qF '(MailScope.rooms.contains(source) && chrome.mailScope != .all)' "$FEED" \
  || { echo "✗ an Attachments pick over nothing would replace the room with the generic empty state"; exit 1; }
grep -qF 'chrome.mailScope = .all' "$SURFACE" \
  || { echo "✗ the mail pick is no longer reset on a source change"; exit 1; }
grep -qE 'static let keepsEmptyRoom: Set<String> = \[.*"Gmail".*"iCloud Mail".*\]' "$LIVE" \
  || { echo "✗ a connected mail seat with no rows no longer keeps its room (prd §1019, §998)"; exit 1; }
for seat in 'case "gmail":' 'case "icloud mail":'; do
  grep -qF "$seat" "$ACTIONS" || { echo "✗ SourceActions no longer composes for $seat — the New tile would not draw"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("✓ \(what)") } else { print("✗ \(what)"); failures += 1 }
}

check(MailScope.rooms == ["Gmail", "iCloud Mail"], "The scope names both mail seats, and only them")
check(MailScope.allCases.map(\.rawValue) == ["all", "attachments", "new"], "Three tiles: All, Attachments, New")
check(MailScope.allCases.filter(\.isVerb) == [.new], "New is the one verb")
check(!MailScope.attachedLabel.isEmpty, "The attachment label is spelled")

let attached = [MailScope.attachedLabel, "From"]
let plain = ["From", "To"]
let none: [String] = []
check(MailScope.all.allows(factLabels: attached) && MailScope.all.allows(factLabels: plain)
      && MailScope.all.allows(factLabels: none), "All stands every mail")
check(MailScope.new.allows(factLabels: none), "The verb stands every mail")
check(MailScope.attachments.allows(factLabels: attached), "Attachments stands a mail that came with a file")
check(!MailScope.attachments.allows(factLabels: plain), "Attachments does not stand a mail with other facts")
check(!MailScope.attachments.allows(factLabels: none), "A mail landed before the ingest named attachments stands under All alone")
check(!MailScope.attachments.allows(factLabels: ["attached"]), "The label is matched as written, not case-folded")

for scope in MailScope.allCases {
    check(!scope.label.isEmpty && !scope.summary.isEmpty && !scope.emptyHeadline.isEmpty,
          "\(scope.rawValue) has a label, a summary and an empty line")
    check(scope.emptyHeadline.hasSuffix("."), "\(scope.rawValue)'s empty line is one clause (§799)")
}
check(MailScope.attachments.emptyHeadline != MailScope.all.emptyHeadline,
      "An empty Attachments pick says what is empty, not the inbox")
check(MailScope(rawValue: "attachments") == .attachments && MailScope(rawValue: "new") == .new,
      "-openSection resolves the tile by its raw value")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("mail-scope self-test: all passed")
SWIFT

xcrun swiftc -O -o "$TMP/mailscope" "$SCOPE" "$TMP/main.swift" 2>&1 | grep -v '^ *$' || true
[[ -x "$TMP/mailscope" ]] || { echo "✗ the harness did not compile"; exit 1; }
"$TMP/mailscope"
