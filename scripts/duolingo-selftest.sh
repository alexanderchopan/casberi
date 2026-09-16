#!/bin/zsh
# Casberi Duolingo self-test (prd §776) — the pure half of the practice-day
# door, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/DuolingoDay.swift
#
# THIS SEAT IS UNMEASURED AGAINST DUOLINGO, more strongly than any other live
# door in this tree: no build host here can reach duolingo.com (the session
# that wrote it had the host refused at its egress proxy), so every fixture
# below pins THIS PARSER'S READING, never Duolingo's shape. `-duolingoProbe`
# is what turns the first real sign-in into a measurement. That is the X live
# door's footing (§741) and it is stated rather than implied.
#
# Every failure here is silent on a device:
#
#   · a JWT payload decoded as plain base64 is nil for every token carrying a
#     `-` or `_`, which reads as "not signed in" over a perfectly good session
#     and can never be reproduced on the tokens that happen not to
#   · a day stamped at its UTC midnight files under YESTERDAY for every reader
#     east of Greenwich — every day, forever, and nothing on screen says so
#   · today's row landed at breakfast reads 20 XP all evening unless it is
#     rewritten when what it says changes
#   · a 200 whose body is not a summaries array read as an empty history is a
#     seat that says "up to date" over a response nobody understood
#   · a frozen day with no XP landed as a row puts "0 XP" in the feed and calls
#     it something you did (§83's fake status)
#   · a stored token that names no account is a credential every read refuses,
#     under a page that says "signed in" forever
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED="Casberi/Casberi/Model/DuolingoDay.swift"
LIVE="Casberi/Casberi/Model/DuolingoLive.swift"
LOGIN="Casberi/Casberi/Screens/DuolingoLoginView.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
PLIST="Casberi/Casberi/Info.plist"
VERBS="Casberi/Casberi/Model/Verbs.swift"
for f in "$FEED" "$LIVE" "$LOGIN" "$REACH" "$PLIST" "$VERBS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

grep -qF 'static let refPrefix = "duolingo:day:"' "$FEED" \
  || { echo "✗ DuolingoFeed.refPrefix moved — it must be the literal \"duolingo:day:\""; exit 1; }
grep -qF 'if case .refused = failure { DuolingoLiveAuth.clear() }' "$LIVE" \
  || { echo "✗ DuolingoLive.refresh no longer clears the session on a refusal (and only a refusal) — §711"; exit 1; }

# READ-ONLY, mechanically. This seat holds a live session to a person's own
# account; a write verb reaching it would act AS them, which is the one thing
# every line of copy on the screen promises it cannot do.
if cat "$FEED" "$LIVE" | grep -vE '^[[:space:]]*//' | grep -qE 'httpMethod|"POST"|"PUT"|"PATCH"|"DELETE"'; then
  echo "✗ the Duolingo seat builds a request that is not a GET — it promises read-only"; exit 1
fi

# The sign-in gate is the token that DECODES, not merely a cookie by that name.
grep -qF 'DuolingoFeed.bearer(jar)' "$LOGIN" \
  || { echo "✗ the login sheet no longer captures through DuolingoFeed.bearer — a cookie that names no account would be stored as a session"; exit 1; }

grep -qF '"www.duolingo.com"' "$REACH" \
  || { echo "✗ www.duolingo.com is not declared in NetworkReach — an undisclosed host (prd §205)"; exit 1; }

# A scheme absent from Info.plist always reads absent from `installedSchemes`,
# so the hand-off would be dead in a way nothing renders.
grep -qF '<string>duolingo</string>' "$PLIST" \
  || { echo "✗ the duolingo scheme is not in LSApplicationQueriesSchemes — the hand-off can never resolve"; exit 1; }
grep -qF '"duolingo"' "$VERBS" \
  || { echo "✗ Verbs no longer probes the duolingo scheme"; exit 1; }
echo "duolingo-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

// ── The credential ───────────────────────────────────────────────────────
// Hand-built payloads: {"sub":123456} / {"sub":"778899"} / a payload whose
// base64url carries a `-` / a payload with no `sub` at all.
let head = "eyJhbGciOiJIUzI1NiJ9"
let numeric  = "\(head).eyJzdWIiOjEyMzQ1Nn0.sig"
let stringly = "\(head).eyJzdWIiOiI3Nzg4OTkifQ.sig"
let urlsafe  = "\(head).eyJzdWIiOjQyNDI0MiwiaWF0IjoxNzg5NDMwNDAwLCJqdGkiOiJhP2I-Y35kIn0.sig"
let noSub    = "\(head).eyJpc3MiOiJkdW9saW5nbyIsInR5cCI6IkpXVCJ9.sig"

check(DuolingoFeed.userID(fromJWT: numeric) == "123456", "the account is the JWT's own sub claim")
check(DuolingoFeed.userID(fromJWT: stringly) == "778899", "a sub spelled as a string reads the same")
check(DuolingoFeed.userID(fromJWT: urlsafe) == "424242", "a payload carrying base64URL's own alphabet decodes")
check(DuolingoFeed.userID(fromJWT: noSub) == nil, "a token naming no account is not a session")
check(DuolingoFeed.userID(fromJWT: "two.parts") == nil, "a two-part token is not a JWT")
check(DuolingoFeed.userID(fromJWT: "") == nil, "an empty token names nobody")

check(DuolingoFeed.bearer([("_csrf", "a"), ("lang", "en")]) == nil, "a signed-out jar is not a session")
check(DuolingoFeed.bearer([("jwt_token", "")]) == nil, "an empty jwt_token is not a session")
check(DuolingoFeed.bearer([("jwt_token", "garbage")]) == nil, "a jwt_token that decodes to nothing is not a session")
check(DuolingoFeed.bearer([("lang", "en"), ("jwt_token", numeric)]) == numeric, "the token is the whole credential")

// ── The requests ─────────────────────────────────────────────────────────
let profile = DuolingoFeed.profileURL(id: "123456")
check(profile.hasPrefix("https://www.duolingo.com/2017-06-30/users/123456?fields="), "the profile is asked by id")
check(profile.contains("streak") && profile.contains("courses"), "the profile names the fields it reads")
let summaries = DuolingoFeed.summariesURL(id: "123456", startDate: "2026-09-02")
check(summaries == "https://www.duolingo.com/2017-06-30/users/123456/xp_summaries?startDate=2026-09-02",
      "the practice record is asked from a plain yyyy-MM-dd")
let now = Date(timeIntervalSince1970: 1789516800)   // 2026-09-16 00:00 UTC
check(DuolingoFeed.dayKey(now) == "2026-09-16", "a day key is UTC, zero-padded")
check(DuolingoFeed.startDate(daysBefore: now) == "2026-09-02", "a sweep looks a fortnight back")

// ── Classification ───────────────────────────────────────────────────────
let clean = json(#"{"summaries":[]}"#)
check(DuolingoFeed.classify(status: 200, json: clean) == nil, "an empty history is a clean read")
check(DuolingoFeed.days(clean)?.isEmpty == true, "an empty history parses to nothing, not nil")
check(DuolingoFeed.classify(status: 200, json: json(#"{"error":"nope"}"#)) == .drifted,
      "a 200 that is not a summaries array is drift, never an empty history")
check(DuolingoFeed.classify(status: 401, json: nil) == .refused(401), "401 refuses")
check(DuolingoFeed.classify(status: 403, json: nil) == .refused(403), "403 refuses")
check(DuolingoFeed.classify(status: 429, json: nil) == .throttled, "429 throttles, never refuses")
check(DuolingoFeed.classify(status: 503, json: nil) == .unreachable, "a 5xx is Duolingo's bad minute, never a refusal")
check(DuolingoFeed.classify(status: 0, json: nil) == .unreachable, "no response is unreachable")
check(DuolingoFeed.days(json(#"{"error":"nope"}"#)) == nil, "a body with no summaries parses to nil")

// ── The profile (BOTH shapes the endpoint answers in) ────────────────────
let object = json(#"""
{"id":123456,"username":"ana","name":"Ana","streak":0,
 "streakData":{"currentStreak":{"length":214,"startDate":"2026-02-14"},"longestStreak":{"length":300}},
 "totalXp":48210,"currentCourseId":"DUOLINGO_ES_EN",
 "courses":[{"id":"DUOLINGO_FR_EN","title":"French","xp":900},
            {"id":"DUOLINGO_ES_EN","title":"Spanish","xp":400}],
 "picture":"//simple-avatars.duolingo.com/abc"}
"""#)
let p = DuolingoFeed.profile(object)
check(p?.username == "ana" && p?.who == "ana", "the handle is who you are signed in as")
check(p?.streak == 214, "a zero streak field falls through to streakData")
check(p?.totalXP == 48210, "the lifetime XP")
check(p?.course == "Spanish", "the course is the CURRENT one, never the first in the array")
check(p?.picture == "https://simple-avatars.duolingo.com/abc/large", "a protocol-relative avatar is made https and sized")

let roster = json(#"{"users":[{"username":"bo","totalXp":10,"courses":[{"id":"x","title":"German","xp":10}]}]}"#)
check(DuolingoFeed.profile(roster)?.who == "bo", "a one-element roster reads the same as the object")
check(DuolingoFeed.profile(roster)?.course == "German", "with no current course named, the one with the most XP")
check(DuolingoFeed.profile(json(#"{"blocked":true}"#)) == nil, "a body naming no account is not an empty profile")

// ── The days ─────────────────────────────────────────────────────────────
let record = json(#"""
{"summaries":[
 {"date":1789430400,"gainedXp":38,"numSessions":3,"totalSessionTime":842,"streakExtended":true,"frozen":false},
 {"date":1789344000,"gainedXp":0,"numSessions":0,"totalSessionTime":0,"streakExtended":false,"frozen":true},
 {"date":1789257600,"gainedXp":"15","numSessions":1,"totalSessionTime":0,"streakExtended":true,"frozen":false},
 {"gainedXp":99}
]}
"""#)
let days = DuolingoFeed.days(record) ?? []
check(days.count == 3, "a summary with no date is not a day")
check(days[0].key == "2026-09-15" && days[0].ref == "duolingo:day:2026-09-15", "a day's ref is its UTC date")
check(days[0].practised && !days[1].practised, "a frozen day with no XP is a day you did not practise")
check(days[2].xp == 15, "XP spelled as a string still reads as a number")

check(DuolingoFeed.title(days[0], course: "Spanish") == "38 XP in Spanish", "the row says what was practised")
check(DuolingoFeed.title(days[0], course: nil) == "38 XP on Duolingo", "with no course named, it claims none")
check(DuolingoFeed.line(days[0]) == "3 lessons · 14 min", "the lessons and the minutes")
check(DuolingoFeed.line(days[2]) == "1 lesson", "one lesson is singular, and a day with no time claims none")
check(DuolingoFeed.line(DuolingoFeed.Day(dayStartUTC: now, xp: 5, sessions: 0, seconds: 0,
                                         streakExtended: true, frozen: false)) == nil,
      "a day carrying neither gets no line rather than an empty one")
check(DuolingoFeed.line(DuolingoFeed.Day(dayStartUTC: now, xp: 5, sessions: 0, seconds: 20,
                                         streakExtended: true, frozen: false)) == "1 min",
      "twenty seconds is a minute, never zero")

// ── Where the row sits ───────────────────────────────────────────────────
// A reader thirteen hours ahead of UTC is the case that breaks: the practice
// day arrives as midnight UTC, and the naive stamp files it under yesterday.
var ahead = Calendar(identifier: .gregorian)
ahead.timeZone = TimeZone(secondsFromGMT: 13 * 3600)!
let muchLater = Date(timeIntervalSince1970: 1789430400 + 30 * 86_400)
let filed = DuolingoFeed.stamp(days[0], now: muchLater, calendar: ahead)
let parts = ahead.dateComponents([.year, .month, .day, .hour], from: filed)
check(parts.year == 2026 && parts.month == 9 && parts.day == 15,
      "a UTC practice day files under the reader's own day, thirteen hours ahead")
check(parts.hour == 12, "a day with no clock sits at midday")

var behind = Calendar(identifier: .gregorian)
behind.timeZone = TimeZone(secondsFromGMT: -11 * 3600)!
let west = behind.dateComponents([.year, .month, .day],
                                 from: DuolingoFeed.stamp(days[0], now: muchLater, calendar: behind))
check(west.day == 15, "and under the same day eleven hours behind")

// Today is landed while today is still running, so an un-clamped midday is a
// feed row stamped in the future every morning.
let breakfast = Date(timeIntervalSince1970: 1789430400 + 8 * 3600)
check(DuolingoFeed.stamp(days[0], now: breakfast, calendar: ahead) <= breakfast,
      "today's row is never stamped in the future")

// ── Today is not finished ────────────────────────────────────────────────
check(DuolingoFeed.rewrites(landedTitle: "20 XP in Spanish", landedLine: "1 lesson",
                            title: "38 XP in Spanish", line: "3 lessons · 14 min"),
      "a day that grew since it landed is rewritten")
check(!DuolingoFeed.rewrites(landedTitle: "38 XP in Spanish", landedLine: "3 lessons · 14 min",
                             title: "38 XP in Spanish", line: "3 lessons · 14 min"),
      "a read that learnt nothing moves nothing")
check(DuolingoFeed.rewrites(landedTitle: "38 XP in French", landedLine: "3 lessons · 14 min",
                            title: "38 XP in Spanish", line: "3 lessons · 14 min"),
      "a switched course is rewritten too")
check(DuolingoFeed.rewrites(landedTitle: "5 XP in Spanish", landedLine: "1 lesson",
                            title: "5 XP in Spanish", line: nil),
      "a line that went away is a rewrite, not a no-op")

print(failures == 0 ? "duolingo-selftest: all checks ✓" : "duolingo-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ duolingo-selftest: compile failed"; exit 1; }
"$TMP/run"
