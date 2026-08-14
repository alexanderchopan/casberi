#!/bin/zsh
# Casberi calendar self-test — the pure logic behind an event's enrichment
# (2026-08-14):
#
#   Casberi/Casberi/Model/EventDetails.swift
#     — ConferenceLink   (which link in an invite is the way to JOIN the call)
#     — RecurrencePhrase (a collapsed series saying that it repeats)
#
# WHY A HARNESS AND NOT A PROBE. Every input here comes from a real INVITE —
# somebody else's Zoom link, somebody else's RSVP, a rule set on somebody else's
# calendar server. The simulator's calendar is empty and cannot be seeded with
# an invite (`EKParticipant` is read-only and has no initializer), so no sim
# sweep and no launch-arg hook can exercise one line of this. The harness is the
# only proof these answers are right.
#
# Every failure mode is a SILENT WRONG ANSWER that renders perfectly:
#
#   • a "Join" disc built from a link in an invite BODY — text a stranger
#     wrote — landing on a host we never vetted. This is the security boundary
#     in this file, and `contains` instead of a label-boundary match is all it
#     takes to lose it: `zoom.us.attacker.example` reads as Zoom.
#   • a Teams invite whose "Join" opens `…/meetingOptions/…`, the settings page,
#     because the ranking that prefers a real join path went away.
#   • a Google Meet link filed in the LOCATION field drawn as a place, so the
#     row's tap runs a Maps search for a URL — the §83 dead control, wearing a
#     chevron that says it works.
#   • "Every Tuesday" on a rule that means every OTHER Tuesday, which is a
#     wrong claim about a date rather than a missing one.
#
# `EventDetails.swift` is Foundation-only BY DESIGN — it takes three strings
# rather than an `EKEvent` precisely so this can compile it WHOLE and
# UNMODIFIED, never a copy and never an extraction. If it ever stops compiling
# alone, something has reached into EventKit and this harness fails loudly
# instead of asserting nothing.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

DETAILS="Casberi/Casberi/Model/EventDetails.swift"
INGEST="Casberi/Casberi/Model/ScheduleIngest.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
for f in "$DETAILS" "$INGEST" "$SHEET"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/calendar-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring the compiled functions cannot prove about themselves. A perfect
# `ConferenceLink.best` is worth nothing if nothing calls it.
#
# The negative guards read a COMMENT-STRIPPED copy: this file DOCUMENTS the
# behaviour it replaced (the Maps search on a URL, `event.url` winning over the
# join link), so a guard grepping raw source fires against the prose explaining
# the fix. Earned on the Obsidian/Cursor guards before it, twice.
python3 - "$INGEST" "$TMP/ingest.bare" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)   # whole-line comments
src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M) # trailing comments
open(sys.argv[2], 'w').write(src)
PY
BARE="$TMP/ingest.bare"

grep -q 'ConferenceLink.best(url:' "$BARE" \
  || { echo "✗ ScheduleIngest no longer looks for a join link — every meeting loses its Join disc"; exit 1; }
# The link must WIN over event.url, or a Meet link found in the notes is
# overwritten by the invite's web page and the disc opens the wrong thing.
grep -q 'let link = join ?? event.url' "$BARE" \
  || { echo "✗ the join link no longer takes precedence over event.url"; exit 1; }
grep -q 'setFacts(thing, eventFacts(event, join: join))' "$BARE" \
  || { echo "✗ eventFacts is no longer passed the promoted link — it would draw the join URL twice"; exit 1; }
grep -q 'setFacts(thing, reminderFacts(reminder))' "$BARE" \
  || { echo "✗ reminders stopped carrying facts — location and start date are dropped again"; exit 1; }
grep -q 'ConferenceLink.locationURL(place)' "$BARE" \
  || { echo "✗ whereFact no longer asks whether the location is a link — a URL would go to Maps"; exit 1; }
grep -q 'setEnriched(thing, participantText(event))' "$BARE" \
  || { echo "✗ the organizer is out of the retrieval text again — 'the review Ana called' finds nothing"; exit 1; }
# A cancelled meeting is the one addition that fixes a WRONG row rather than a
# missing one, and it is invisible from outside: the row looks like any other
# upcoming event.
grep -q 'case .canceled' "$BARE" \
  || { echo "✗ a cancelled meeting no longer says so — it lands as an ordinary upcoming event"; exit 1; }
grep -q 'first(where: \\.isCurrentUser)' "$BARE" \
  || { echo "✗ the RSVP fact no longer reads YOUR row — it would report somebody else's reply"; exit 1; }
# Status is a FACT and must never become a tag: `addTag` only ever appends, so
# an un-cancelled meeting would wear "Cancelled" forever.
grep -qE 'addTag\((statusWord|rsvpWord)' "$BARE" \
  && { echo "✗ status/RSVP became a TAG — tags only append, so the word would outlive the state"; exit 1; }

python3 - "$SHEET" "$TMP/sheet.bare" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'^[ \t]*//.*$', '', src, flags=re.M)
src = re.sub(r'(?<![:/])//.*$', '', src, flags=re.M)
open(sys.argv[2], 'w').write(src)
PY
grep -q 'ConferenceLink.isConference(url)' "$TMP/sheet.bare" \
  || { echo "✗ the Join verb no longer re-checks the host — any stored link would become a tap target"; exit 1; }
grep -q 'UIApplication.shared.canOpenURL(url)' "$TMP/sheet.bare" \
  || { echo "✗ the Join verb lost its canOpenURL gate (prd §275) — it could be a disc that does nothing"; exit 1; }
grep -q 'joinVerb' "$TMP/sheet.bare" \
  || { echo "✗ joinVerb is gone — the stored meeting link is unreachable again"; exit 1; }

# --- the driver -------------------------------------------------------------
cp "$DETAILS" "$TMP/EventDetails.swift"

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}
func u(_ s: String) -> URL { URL(string: s)! }

print("isConference — the security boundary, since `notes` is a stranger's text")
check("zoom.us",              ConferenceLink.isConference(u("https://zoom.us/j/123")))
check("a Zoom tenant",        ConferenceLink.isConference(u("https://us02web.zoom.us/j/123")))
check("Google Meet",          ConferenceLink.isConference(u("https://meet.google.com/abc-defg-hij")))
check("Teams",                ConferenceLink.isConference(u("https://teams.microsoft.com/l/meetup-join/x")))
check("a Webex tenant",       ConferenceLink.isConference(u("https://acme.webex.com/meet/ana")))
check("FaceTime",             ConferenceLink.isConference(u("https://facetime.apple.com/join#v=1")))
check("http, not just https", ConferenceLink.isConference(u("http://zoom.us/j/123")))
// THE ONE THAT MATTERS. A `contains` match reads every one of these as Zoom.
check("zoom.us.attacker.example is REFUSED",
      !ConferenceLink.isConference(u("https://zoom.us.attacker.example/j/1")))
check("notzoom.us is REFUSED",
      !ConferenceLink.isConference(u("https://notzoom.us/j/1")))
check("a lookalike path is REFUSED",
      !ConferenceLink.isConference(u("https://evil.example/zoom.us/j/1")))
check("an ordinary link is REFUSED",
      !ConferenceLink.isConference(u("https://example.com/agenda")))
// A non-web scheme must never reach `openURL` off third-party text.
check("a non-http scheme is REFUSED",
      !ConferenceLink.isConference(u("javascript:alert(1)")))
// …and the fixture that ISOLATES the scheme gate. The line above proves
// nothing about it: `javascript:alert(1)` has no host at all, so deleting the
// scheme check still refuses it and the mutation survived (caught by this
// harness's own mutation pass, first run). The host must MATCH so that the
// scheme is the only thing left to reject it on.
check("a vetted host on a non-http scheme is REFUSED",
      !ConferenceLink.isConference(u("ftp://zoom.us/j/1")))
check("case in the host is ignored",
      ConferenceLink.isConference(u("https://ZOOM.US/j/123")))

print("best — the field says how much the invite meant it")
let notesOnly = ConferenceLink.best(
    url: nil, location: nil,
    notes: "Agenda attached.\nJoin: https://zoom.us/j/98765\nDial in: +1 555")
check("a link in the body is found", notesOnly == "https://zoom.us/j/98765")
check("a body with no conference link → nil",
      ConferenceLink.best(url: nil, location: nil,
                          notes: "Bring the printouts. https://example.com/deck") == nil)
check("nothing anywhere → nil",
      ConferenceLink.best(url: nil, location: nil, notes: nil) == nil)
check("empty strings → nil",
      ConferenceLink.best(url: "", location: "", notes: "") == nil)
// The URL FIELD is the strongest statement; a body link is the weakest. Both
// candidates are unmarked here, so only the field ordering can decide it.
check("the url field beats the body",
      ConferenceLink.best(url: "https://meet.google.com/aaa-bbbb-ccc",
                          location: nil,
                          notes: "or https://meet.google.com/zzz-zzzz-zzz")
        == "https://meet.google.com/aaa-bbbb-ccc")
check("the location field beats the body",
      ConferenceLink.best(url: nil,
                          location: "https://meet.google.com/aaa-bbbb-ccc",
                          notes: "https://meet.google.com/zzz-zzzz-zzz")
        == "https://meet.google.com/aaa-bbbb-ccc")
// Google files the Meet link in LOCATION and nowhere else — the case the
// whole location fork exists for.
check("a Meet link in the location field is found",
      ConferenceLink.best(url: nil, location: "https://meet.google.com/abc-defg-hij",
                          notes: nil) == "https://meet.google.com/abc-defg-hij")
// THE TEAMS CASE. Both links are on the same host in the same field, so the
// join marker is the only thing separating the meeting from its settings page.
let teams = ConferenceLink.best(
    url: nil, location: nil,
    notes: """
    ________________________________
    Microsoft Teams
    Meeting options: https://teams.microsoft.com/meetingOptions/?p=abc
    Join the meeting now: https://teams.microsoft.com/l/meetup-join/19%3ameeting_x
    ________________________________
    """)
check("the join link beats the options page, despite coming second",
      teams == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x")
// A marked link in a LATER field must still lose to an unmarked one earlier:
// the field is the stronger signal and the tiers say so.
check("field beats marker across fields",
      ConferenceLink.best(url: "https://meet.google.com/aaa-bbbb-ccc",
                          location: nil,
                          notes: "https://zoom.us/j/111")
        == "https://meet.google.com/aaa-bbbb-ccc")

print("urls — the detector finds a link the way people really paste one")
check("a trailing full stop is not part of the link",
      ConferenceLink.urls(in: "See https://zoom.us/j/5 for the call.")
        .first?.absoluteString == "https://zoom.us/j/5")
check("a scheme-less host still parses",
      ConferenceLink.urls(in: "meet.google.com/abc-defg-hij").count == 1)
check("plain prose yields nothing", ConferenceLink.urls(in: "no links here").isEmpty)
// The scan is bounded: this runs for every event on every foreground over text
// somebody else wrote.
let flood = String(repeating: "x", count: ConferenceLink.scanCap) + " https://zoom.us/j/9"
check("a link past the scan cap is not read", ConferenceLink.urls(in: flood).isEmpty)

print("isLink — a location is a place unless the WHOLE value is a link")
check("a bare URL is a link",   ConferenceLink.isLink("https://meet.google.com/abc"))
check("a scheme-less URL is a link", ConferenceLink.isLink("meet.google.com/abc"))
check("surrounding space is ignored", ConferenceLink.isLink("  https://zoom.us/j/1  "))
check("a room name is NOT a link", !ConferenceLink.isLink("Room 4"))
check("an address is NOT a link", !ConferenceLink.isLink("12 Ilica, Zagreb"))
// The narrowness is deliberate: a place that MENTIONS a link is still a place,
// and sending it to Maps is the right answer.
check("a place mentioning a link is still a place",
      !ConferenceLink.isLink("Room 4 (backup meet.google.com/abc)"))
check("empty is not a link", !ConferenceLink.isLink("   "))
check("locationURL answers for a link",
      ConferenceLink.locationURL("https://zoom.us/j/1")?.absoluteString == "https://zoom.us/j/1")
check("locationURL is nil for a place", ConferenceLink.locationURL("Room 4") == nil)

print("RecurrencePhrase — a collapsed series says that it repeats")
func phrase(_ c: RecurrenceShape.Cadence, _ i: Int = 1, _ d: [Int] = []) -> String? {
    RecurrencePhrase.text(RecurrenceShape(cadence: c, interval: i, weekdays: d))
}
check("daily",   phrase(.daily)   == "Every day")
check("weekly",  phrase(.weekly)  == "Every week")
check("monthly", phrase(.monthly) == "Every month")
check("yearly",  phrase(.yearly)  == "Every year")
check("every other week",  phrase(.weekly, 2)  == "Every other week")
check("every other month", phrase(.monthly, 2) == "Every other month")
check("every 3 weeks",     phrase(.weekly, 3)  == "Every 3 weeks")
check("every 10 days",     phrase(.daily, 10)  == "Every 10 days")
// The locale's own word, asserted against the locale rather than against
// "Tuesday" — this must hold on a device that has never seen English.
let tuesday = Calendar.current.weekdaySymbols[2]
check("one named day is spoken", phrase(.weekly, 1, [3]) == "Every \(tuesday)")
let sunday = Calendar.current.weekdaySymbols[0]
check("Sunday maps to index 0", phrase(.weekly, 1, [1]) == "Every \(sunday)")
let saturday = Calendar.current.weekdaySymbols[6]
check("Saturday maps to index 6", phrase(.weekly, 1, [7]) == "Every \(saturday)")
// Several days is left at "Every week": listing five weekdays is a sentence
// you parse to learn what the dates already told you.
check("several days stay generic", phrase(.weekly, 1, [2, 3, 4, 5, 6]) == "Every week")
// AND THE ONE THAT IS A WRONG CLAIM RATHER THAN A MISSING ONE: an interval
// above 1 must suppress the day, or a fortnightly meeting reads as weekly.
check("every other Tuesday never reads as 'Every Tuesday'",
      phrase(.weekly, 2, [3]) == "Every other week")
check("an out-of-range weekday is ignored", phrase(.weekly, 1, [9]) == "Every week")
check("interval 0 is floored to 1", phrase(.weekly, 0) == "Every week")

if failures > 0 { print("\n\(failures) failed"); exit(1) }
print("\nall checks passed")
SWIFT

swiftc -O -o "$TMP/run" "$TMP/EventDetails.swift" "$TMP/main.swift" 2>&1 \
  | grep -v '^ *$' || true
[[ -x "$TMP/run" ]] || { echo "✗ EventDetails.swift no longer compiles Foundation-only"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a real way this
# logic could be broken while every screen still renders.
echo "\nmutations (each must FAIL the harness):"
mutate() {
  local label="$1" sedexpr="$2"
  local dir="$TMP/mut"; rm -rf "$dir"; mkdir -p "$dir"
  sed "$sedexpr" "$DETAILS" > "$dir/EventDetails.swift"
  cmp -s "$dir/EventDetails.swift" "$DETAILS" \
    && { echo "  ✗ $label — the mutation matched NOTHING (stale after a refactor)"; return 1; }
  if ! swiftc -O -o "$dir/run" "$dir/EventDetails.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✗ $label — the mutation does not compile, so it tests nothing"; return 1
  fi
  if "$dir/run" >/dev/null 2>&1; then
    echo "  ✗ $label — the harness PASSED against broken logic"; return 1
  fi
  echo "  ✓ $label is caught"
}

# The security boundary: label-boundary matching → substring matching. This is
# the mutation this whole harness exists for — it turns a stranger's invite
# body into a tap target on any host that merely CONTAINS a vetted name.
mutate "a substring host match (zoom.us.attacker.example reads as Zoom)" \
  's@host == $0 || host.hasSuffix("." + $0)@host.contains($0)@'
# The field ordering: every field weighted the same, so a marked link three
# paragraphs into a footer beats the URL the organizer put in the URL field.
mutate "the field tier dropped (a footer link beats the URL field)" \
  's@let tier = field [*] 2 + marked@let tier = marked@'
# The join-marker ranking: a Teams "Join" disc that opens the settings page.
mutate "join markers ignored (Teams opens meetingOptions)" \
  's@} ? 0 : 1@} ? 1 : 1@'
# The location fork: a URL in the location field handed to Maps again — and
# its mirror image, an ordinary room name treated as a link.
mutate "isLink accepting a value with spaces (a room name becomes a link)" \
  's@guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }@guard !trimmed.isEmpty else { return false }@'
# The wrong-CLAIM mutation rather than a missing one: with the interval pinned
# to 1, a fortnightly series reads as weekly and "every other Tuesday" reads as
# "Every Tuesday" — a false statement about a date.
mutate "the recurrence interval ignored (every other week reads as weekly)" \
  's@let interval = max(1, shape.interval)@let interval = 1@'
# Several named days collapsing to the first, so a weekday-daily standup reads
# as "Every Monday".
mutate "weekdayName accepting several days (a 5-day rule reads as one day)" \
  's@guard weekdays.count == 1, let day = weekdays.first,@guard let day = weekdays.first,@'
# The scan cap: unbounded link detection over third-party text, for every
# event, on every foreground.
mutate "the scan cap removed" \
  's@let scanned = text.count > scanCap ? String(text.prefix(scanCap)) : text@let scanned = text@'
# The scheme gate: a `javascript:` URL out of an invite body reaching openURL.
mutate "the scheme gate removed (a non-http URL becomes a Join disc)" \
  's@guard url.scheme == "https" || url.scheme == "http",$@guard true,@'

echo "\n✓ calendar self-test passed"
