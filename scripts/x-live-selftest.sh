#!/bin/zsh
# Casberi X live self-test (prd §741) — the pure half of the notifications
# door, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/XLiveNotice.swift
#
# Every failure here is silent on a device:
#
#   · a notice stamped with the sweep's clock reads "2 min ago" for a like
#     from hours ago (the defect this exists for), and nothing on screen says
#     the time is the read's rather than X's
#   · a time read at the wrong magnitude (milliseconds as seconds, a snowflake
#     as milliseconds) lands a notice decades away and it never shows
#   · an aggregate whose sentence grew ("and 4 others") is left with its first
#     sentence and first time, so the newest likes never appear
#
# The payload fields are UNMEASURED (no X session reaches a build host); these
# fixtures pin the parser's reading of every magnitude, not X's shape.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTICE="Casberi/Casberi/Model/XLiveNotice.swift"
LIVE="Casberi/Casberi/Model/XLiveNotifications.swift"
for f in "$NOTICE" "$LIVE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Code lines only, so a comment quoting the old line cannot satisfy or trip this.
CODE="$(grep -vE '^[[:space:]]*//' "$LIVE")"
print -r -- "$CODE" | grep -qF 'XLiveNoticeTime.date(entry: entry, now: now)' \
  || { echo "✗ XLiveNotifications.refresh no longer reads the notice's own time — every notice lands at the sweep's clock"; exit 1; }
print -r -- "$CODE" | grep -qF 'capturedAt: at,' \
  || { echo "✗ a new notice is not stamped with its own time"; exit 1; }
if print -r -- "$CODE" | grep -qF 'capturedAt: .now'; then
  echo "✗ XLiveNotifications stamps capturedAt: .now again — a like from hours ago reads as minutes ago"; exit 1
fi
print -r -- "$CODE" | grep -qF 'XLiveNoticeTime.changes(' \
  || { echo "✗ an already-landed notice is never rewritten — a growing aggregate keeps its first sentence and time"; exit 1; }
print -r -- "$CODE" | grep -qF 'existing.capturedAt = at' \
  || { echo "✗ a landed notice whose time moved is not restamped"; exit 1; }
echo "x-live-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

let now = Date(timeIntervalSince1970: 1_757_900_000)          // 2025-09-15
let sec: Int64 = 1_757_890_000                                   // ~2h47m before now
let expected = Date(timeIntervalSince1970: TimeInterval(sec))

// ── Magnitudes ───────────────────────────────────────────────────────────
check(XLiveNoticeTime.date("\(sec * 1000)", now: now) == expected, "milliseconds as a string")
check(XLiveNoticeTime.date(NSNumber(value: sec * 1000), now: now) == expected, "milliseconds as a JSON number")
check(XLiveNoticeTime.date("\(sec)", now: now) == expected, "seconds")
// The snowflake is encoded here by X's documented layout, independently of the
// decoder: milliseconds since 2010-11-04 in the top 42 bits.
let snowflake = (sec * 1000 - 1_288_834_974_657) << 22 | 0x3FFFFF
check(XLiveNoticeTime.date("\(snowflake)", now: now) == expected, "a snowflake id decodes to its millisecond")
check(XLiveNoticeTime.date("abc", now: now) == nil, "words are not a time")
check(XLiveNoticeTime.date("0", now: now) == nil, "zero is not a time")
check(XLiveNoticeTime.date("123456", now: now) == nil, "a small counter is not a time")
check(XLiveNoticeTime.date(NSNumber(value: 1.5), now: now) == nil, "a fraction is not a time")
check(XLiveNoticeTime.date("\((sec + 30 * 86_400) * 1000)", now: now) == nil, "a month ahead is not believed")
check(XLiveNoticeTime.date("\(1_000_000_000_000)", now: now) == nil, "2001, before X existed, is not believed")
check(XLiveNoticeTime.date(nil, now: now) == nil, "no value, no time")

// ── Where the time is read from ──────────────────────────────────────────
let both = json(#"{"entryId":"n1","sortIndex":"1757800000000","content":{"itemContent":{"timestamp_ms":"\#(sec * 1000)"}}}"#)
check(XLiveNoticeTime.date(entry: both, now: now) == expected, "timestamp_ms wins over sortIndex")
let sortOnly = json(#"{"entryId":"n2","sortIndex":"\#(sec * 1000)","content":{"itemContent":{}}}"#)
check(XLiveNoticeTime.date(entry: sortOnly, now: now) == expected, "sortIndex when there is no timestamp_ms")
let badFirst = json(#"{"entryId":"n3","sortIndex":"\#(sec * 1000)","content":{"itemContent":{"timestamp_ms":"not-a-time"}}}"#)
check(XLiveNoticeTime.date(entry: badFirst, now: now) == expected, "an unreadable timestamp_ms falls through to sortIndex")
check(XLiveNoticeTime.date(entry: json(#"{"entryId":"n4","content":{}}"#), now: now) == nil, "an entry with no time reads nil")

// ── What a landed notice rewrites ────────────────────────────────────────
let stored = Date(timeIntervalSince1970: TimeInterval(sec))
var c = XLiveNoticeTime.changes(storedTitle: "Ana liked your post", storedAt: stored,
                                title: "Ana liked your post", at: stored.addingTimeInterval(30))
check(!c.title && !c.at, "the same sentence within a minute changes nothing")
c = XLiveNoticeTime.changes(storedTitle: "Ana liked your post", storedAt: stored,
                            title: "Bo and 1 other liked your post", at: stored.addingTimeInterval(3600))
check(c.title && c.at, "a grown aggregate retitles and climbs to its new time")
c = XLiveNoticeTime.changes(storedTitle: "Ana liked your post", storedAt: now,
                            title: "Ana liked your post", at: stored)
check(!c.title && c.at, "a row stamped with the sweep's clock is moved back to X's time")
c = XLiveNoticeTime.changes(storedTitle: "Ana liked your post", storedAt: stored,
                            title: "Ana liked your post ", at: nil)
check(!c.title && !c.at, "trailing space is not a new sentence, and a nil time never moves a row")
c = XLiveNoticeTime.changes(storedTitle: "Ana liked your post", storedAt: stored, title: "", at: nil)
check(!c.title, "an empty sentence never replaces a real one")

print(failures == 0 ? "x-live-selftest: all checks ✓" : "x-live-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$NOTICE" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ x-live-selftest: compile failed"; exit 1; }
"$TMP/run"
