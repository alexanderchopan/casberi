#!/bin/zsh
# CardPointers wire self-test (prd §420).
#
# Compiles `Model/CardPointersWire.swift` WHOLE and UNMODIFIED — it is
# Foundation-only by design — and asserts it against the bytes MEASURED off
# the live service on 2026-08-20. That measurement is the only one this
# project will ever have for the free-account half, and nothing else in the
# tree can re-derive it: their docs are unreachable, and their CLI (the only
# other description of this protocol) is wrong about two things this file
# gets right.
#
# Every failure here is a silent one. A bridge that mis-parses SSE, or reads
# a pending poll as a failure, does not crash — it produces an empty room,
# which is indistinguishable from an account with nothing in it.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="Casberi/Casberi/Model/CardPointersWire.swift"
OFFER="Casberi/Casberi/Model/CardPointersOffer.swift"
for f in "$SRC" "$OFFER"; do [ -f "$f" ] || { echo "✗ missing $f"; exit 1; }; done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

// --- bytes measured 2026-08-20 against the live service ---
let gated = """
event: message
data: {"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"CardPointers+ subscription required","data":{"upgrade_url":"https://cardpointers.com/plus"}}}
"""
let payload = """
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\\"offers\\":[]}"}]}}
"""

// 1. the subscription wall is recognised AS a wall, and keeps its door
if case .subscriptionRequired(let url) = CardPointersWire.answer(from: gated) {
    check(url == "https://cardpointers.com/plus", "upgrade_url survives")
} else {
    check(false, "-32001 reads as subscriptionRequired")
}

// 2. a real payload comes back as the inner JSON STRING, not the envelope
if case .payload(let text) = CardPointersWire.answer(from: payload) {
    check(text == "{\"offers\":[]}", "inner payload extracted")
} else {
    check(false, "result reads as payload")
}

// 3. SSE: the LAST data frame wins. A service free to send progress frames
//    would otherwise have its first, answerless frame read as the answer.
let twoFrames = """
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"first"}]}}
event: message
data: {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"second"}]}}
"""
if case .payload(let t) = CardPointersWire.answer(from: twoFrames) {
    check(t == "second", "last SSE frame wins")
} else { check(false, "multi-frame SSE parses") }

// 4. unframed JSON still parses — if they ever drop SSE this keeps working
let plain = "{\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"bare\"}]}}"
if case .payload(let t) = CardPointersWire.answer(from: plain) {
    check(t == "bare", "unframed JSON still parses")
} else { check(false, "unframed JSON parses") }

// 5. a NON-subscription error is not laundered into the subscription state —
//    telling somebody to buy a subscription over an outage is a wrong bill.
if case .failed(let code, _) = CardPointersWire.answer(from:
    "data: {\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}") {
    check(code == -32603, "other errors stay failures")
} else { check(false, "-32603 is .failed, not .subscriptionRequired") }

check(CardPointersWire.answer(from: "not json at all") == .unreadable, "garbage is unreadable")

// --- device flow ---
let dc: [String: Any] = ["device_code": "d", "user_code": "9DMN-5EM4",
                         "verification_uri_complete": "https://cardpointers.com/mcp/auth?code=9DMN-5EM4",
                         "expires_in": 900, "interval": 5]
let parsed = CardPointersWire.deviceCode(from: dc)
check(parsed?.userCode == "9DMN-5EM4", "user code parsed")
check(parsed?.interval == 5, "interval parsed")
check(CardPointersWire.deviceCode(from: ["user_code": "x"]) == nil, "no device_code -> nil")

// interval floor: a missing or zero interval must never become a hot loop
check(CardPointersWire.deviceCode(from: ["device_code": "d", "user_code": "u"])?.interval == 5,
      "absent interval defaults to 5")
check(CardPointersWire.deviceCode(from: ["device_code": "d", "user_code": "u", "interval": 0])?.interval ?? 0 >= 1,
      "zero interval is floored")

// poll outcomes — measured strings, including the HTTP-400 pending case
check(CardPointersWire.poll(from: ["error": "authorization_pending"]) == .pending, "pending")
check(CardPointersWire.poll(from: ["error": "slow_down"]) == .pending, "slow_down is pending")
check(CardPointersWire.poll(from: ["error": "access_denied"]) == .denied, "denied")
check(CardPointersWire.poll(from: ["error": "expired_token"]) == .expired, "expired")
check(CardPointersWire.poll(from: ["error": "invalid_grant"]) == .expired, "invalid_grant is terminal")

if case .granted(let t) = CardPointersWire.poll(from:
    ["access_token": "abc", "token_type": "bearer", "is_pro": false]) {
    check(t.accessToken == "abc", "token parsed")
    check(t.isPro == false, "is_pro false parsed")
} else { check(false, "token grants") }

if case .granted(let t) = CardPointersWire.poll(from: ["access_token": "abc", "is_pro": true]) {
    check(t.isPro, "is_pro true parsed")
} else { check(false, "pro token grants") }

// absent is_pro must read as NOT pro — claiming a subscription somebody does
// not have puts them in front of a room that can never fill (§83)
if case .granted(let t) = CardPointersWire.poll(from: ["access_token": "abc"]) {
    check(t.isPro == false, "absent is_pro is pessimistic")
} else { check(false, "token without is_pro still grants") }

check(CardPointersWire.apiBase == "https://mcp.cardpointers.com",
      "device flow lives on the MCP host, not cardpointers.com")

// ---------- offers and the room head ----------
func at(_ days: Double) -> Date { Date().addingTimeInterval(days * 86400) }
let base = Date()

// snoozed is an offer somebody deliberately put away: a room built around
// "what needs you" must never hand it back
let book = [
    CardPointers.Offer(id: "1", merchant: "Amazon", card: "Amex Gold", status: .active,  expires: at(3),  terms: "$10 back"),
    CardPointers.Offer(id: "2", merchant: "Shell",  card: "Amex Gold", status: .active,  expires: at(20), terms: "20% off"),
    CardPointers.Offer(id: "3", merchant: "Hilton", card: "Chase",     status: .snoozed, expires: at(2),  terms: nil),
    CardPointers.Offer(id: "4", merchant: "Uber",   card: "Chase",     status: .active,  expires: nil,    terms: nil),
    CardPointers.Offer(id: "5", merchant: "Gap",    card: "Chase",     status: .redeemed, expires: at(1), terms: nil),
]
if let room = CardPointers.room(offers: book, now: base) {
    check(room.soonest?.merchant == "Amazon", "soonest is the nearest ACTIVE offer")
    check(room.soonest?.merchant != "Hilton", "a snoozed offer is never the headline")
    check(room.headline.contains("1"), "one offer inside the week")
    check(room.undated == 1, "undated offers are counted, not hidden")
    check(room.cards.first?.name == "Amex Gold", "cards rank by active count")
    check(room.cards.count == 2, "a card row per card with active offers")
    check(room.cards.allSatisfy { $0.active > 0 }, "no empty card rows")
} else { check(false, "room composes over a real book") }

// an already-passed date is not a deadline — their `expired` status is the
// authority on that, a date we parsed is not
let past = [
    CardPointers.Offer(id: "a", merchant: "M1", card: "C", status: .active, expires: at(-5), terms: nil),
    CardPointers.Offer(id: "b", merchant: "M2", card: "C", status: .active, expires: at(9),  terms: nil),
]
check(CardPointers.room(offers: past, now: base)?.soonest?.merchant == "M2",
      "a past date is never the soonest")

// the floor: one offer is not a book
check(CardPointers.room(offers: [book[0]], now: base) == nil, "below the floor there is no head")
check(CardPointers.room(offers: [], now: base) == nil, "no offers, no head")
// a book of nothing but snoozed/redeemed has no head either
check(CardPointers.room(offers: [book[2], book[4]], now: base) == nil,
      "snoozed and redeemed alone earn no head")

// the card order is TOTAL — a head that reshuffles between opens over
// identical data reads as broken (§324)
// EIGHT cards, every one tied on count and on date, so only the name can
// order them. Two would not discriminate: the rows come out of a Dictionary,
// whose order is unspecified, so a sort that returns "no opinion" lands on
// the right pair often enough to pass by luck — the fixture would then be
// testing nothing, which a mutation proved on this very case.
let tiedNames = ["Golf", "Charlie", "Hotel", "Alpha", "Echo", "Bravo", "Foxtrot", "Delta"]
// ONE shared timestamp, computed once. `at()` calls `Date()` each time, so
// building eight "tied" offers with eight `at(4)` calls ties nothing — the
// dates differ by microseconds and the sort orders by date, which is creation
// order, which passes or fails depending on machine speed. A flaky fixture is
// worse than no fixture: it fails for a reason that has nothing to do with the
// rule it names.
let tiedAt = at(4)
let tied = tiedNames.enumerated().map { i, name in
    CardPointers.Offer(id: "t\(i)", merchant: "m", card: name, status: .active,
                       expires: tiedAt, terms: nil)
}
check(CardPointers.room(offers: tied, now: base)?.cards.map(\.name) == tiedNames.sorted(),
      "ties break by name, so the order is total")

// decoding is tolerant because the payload shape has never been seen
check(CardPointers.decodeList("[{\"id\":\"1\",\"merchant\":\"Amazon\"}]").count == 1, "bare array decodes")
check(CardPointers.decodeList("{\"offers\":[{\"id\":\"1\",\"name\":\"Amazon\"}]}").count == 1, "wrapped array decodes")
check(CardPointers.decodeList("{\"results\":[{\"offer_id\":\"1\",\"merchant_name\":\"Shell\"}]}").count == 1, "alternate key spellings decode")
check(CardPointers.decodeList("[{\"merchant\":\"NoID\"}]").isEmpty, "no id -> dropped, or it re-lands forever")
check(CardPointers.decodeList("[{\"id\":\"1\"}]").isEmpty, "no merchant -> dropped")
check(CardPointers.decodeList("garbage").isEmpty, "garbage decodes to nothing")

// an UNKNOWN status reads as active: hiding a live offer is the worse failure
check(CardPointers.decode(["id": "1", "merchant": "m", "status": "brand_new"])?.status == .active,
      "unknown status is treated as active")
check(CardPointers.decode(["id": "1", "merchant": "m", "status": "snoozed"])?.status == .snoozed,
      "snoozed round-trips")

// a date we cannot parse is nil, NEVER today — an offer stamped today enters
// the deadline machinery as expiring immediately
check(CardPointers.date("not a date") == nil, "unparseable date is nil, not now")
check(CardPointers.date(nil) == nil, "absent date is nil")
check(CardPointers.date("2026-08-20") != nil, "plain yyyy-MM-dd parses")
check(CardPointers.date("2026-08-20T12:00:00Z") != nil, "ISO datetime parses")
check(CardPointers.date(1_755_000_000 as NSNumber) != nil, "epoch seconds parse")
// milliseconds decided by MAGNITUDE, never by a field name (the Snapchat lesson)
if let ms = CardPointers.date(1_755_000_000_000 as NSNumber), let sec = CardPointers.date(1_755_000_000 as NSNumber) {
    check(abs(ms.timeIntervalSince(sec)) < 1, "epoch milliseconds are detected by magnitude")
} else { check(false, "epoch ms parses") }

check(CardPointers.categories.count == 18, "their 18 categories, as measured")
check(CardPointers.categories.contains("everywhere else"), "multi-word categories kept verbatim")

if failures == 0 { print("  all assertions passed") }
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run () { # $1 = source file
  swiftc -O "$1" "$2" "$WORK/main.swift" -o "$WORK/run" 2>"$WORK/err" || { echo "COMPILE-FAIL"; return 2; }
  "$WORK/run" >"$WORK/out" 2>&1 && return 0 || return 1
}

echo "CardPointers wire self-test"
if build_and_run "$SRC" "$OFFER"; then
  cat "$WORK/out"
else
  echo "✗ assertions failed against the shipped source:"; cat "$WORK/out" 2>/dev/null || cat "$WORK/err"
  exit 1
fi

# --- mutations: each is a silent wrong answer this must catch ---
mutate () { # $1 name, $2 sed script
  cp "$SRC" "$WORK/mut.swift"
  perl -0pi -e "$2" "$WORK/mut.swift"
  if cmp -s "$SRC" "$WORK/mut.swift"; then
    echo "  ✗ MUTATION STALE (matched nothing): $1"; return 1
  fi
  if build_and_run "$WORK/mut.swift" "$OFFER"; then
    echo "  ✗ MUTATION SURVIVED: $1"; return 1
  fi
  echo "  ✓ caught: $1"; return 0
}

bad=0
mutate "SSE takes the first frame instead of the last" 's/return data\.last \?\? body/return data.first ?? body/' || bad=1
mutate "subscription code drifts" 's/subscriptionRequiredCode = -32001/subscriptionRequiredCode = -32002/' || bad=1
mutate "absent is_pro defaults to TRUE" 's/d\["is_pro"\] as\? Bool \?\? false/d["is_pro"] as? Bool ?? true/' || bad=1
mutate "invalid_grant treated as pending (polls forever)" 's/case "expired_token", "invalid_grant"/case "expired_token"/' || bad=1
mutate "slow_down is not pending" 's/case "authorization_pending", "slow_down"/case "authorization_pending"/' || bad=1
mutate "interval floor removed (hot poll loop)" 's/max\(1, d\["interval"\] as\? Int \?\? 5\)/d["interval"] as? Int ?? 0/' || bad=1
mutate "host drifts to the marketing domain" 's{apiBase = "https://mcp\.cardpointers\.com"}{apiBase = "https://cardpointers.com"}' || bad=1

mutate_offer () { # $1 name, $2 perl script
  cp "$OFFER" "$WORK/mutoffer.swift"
  perl -0pi -e "$2" "$WORK/mutoffer.swift"
  if cmp -s "$OFFER" "$WORK/mutoffer.swift"; then
    echo "  ✗ MUTATION STALE (matched nothing): $1"; return 1
  fi
  if swiftc -O "$SRC" "$WORK/mutoffer.swift" "$WORK/main.swift" -o "$WORK/run" 2>/dev/null && "$WORK/run" >/dev/null 2>&1; then
    echo "  ✗ MUTATION SURVIVED: $1"; return 1
  fi
  echo "  ✓ caught: $1"; return 0
}

mutate_offer "a snoozed offer reaches the room" 's/self == \.active/self != .redeemed/' || bad=1
mutate_offer "a past date counts as the soonest" 's/dated\.filter \{ \$0\.1 > now \}/dated/' || bad=1
mutate_offer "an unparseable date becomes now" 's/return plain\.date\(from: s\)/return plain.date(from: s) ?? Date()/' || bad=1
mutate_offer "an offer with no id still lands" 's/guard let id = string\(d, \["id", "offer_id", "offerId", "uuid"\]\) else \{ return nil \}/let id = string(d, ["id", "offer_id", "offerId", "uuid"]) ?? "x"/' || bad=1
mutate_offer "the room floor drops to one offer" 's/roomFloor = 2/roomFloor = 1/' || bad=1
mutate_offer "card order stops being total" 's/default: return \$0\.name < \$1\.name/default: return false/' || bad=1

[ $bad -eq 0 ] || { echo "✗ mutation coverage incomplete"; exit 1; }
echo "✓ cardpointers: wire + offers, assertions + 13 mutations"
