#!/bin/zsh
# Casberi live messages self-test (prd §1244) — the pure half of the X and
# Instagram DM reads, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/LiveConversation.swift
#   Casberi/Casberi/Model/XLiveMessages.swift
#   Casberi/Casberi/Model/InstagramLiveMessages.swift
#
# Every failure here is silent on a device:
#
#   · a message request (X `trusted: false`) lands beside your conversations,
#     and a stranger's pitch reads as somebody you talk to
#   · your own lines carry your name instead of "You", or a one-to-one is
#     titled with yourself, when the viewer id is read wrong
#   · a time read at the wrong magnitude (Instagram's microseconds as
#     milliseconds) dates a conversation decades away and it never shows
#   · a second read re-appends lines the row already holds, so a transcript
#     doubles every ten minutes, or a merge drops the stored lines
#   · a message's own line break splits one message into two lines, and the
#     count drifts from the conversation
#
# The payload fields are UNMEASURED (no X or Instagram session reaches a build
# host); these fixtures pin the parser's reading of the documented shapes,
# not the networks'.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CONV="Casberi/Casberi/Model/LiveConversation.swift"
XDM="Casberi/Casberi/Model/XLiveMessages.swift"
IGDM="Casberi/Casberi/Model/InstagramLiveMessages.swift"
XLIVE="Casberi/Casberi/Model/XLiveNotifications.swift"
IGLIVE="Casberi/Casberi/Model/InstagramLive.swift"
LAND="Casberi/Casberi/Model/LiveMessagesLanding.swift"
for f in "$CONV" "$XDM" "$IGDM" "$XLIVE" "$IGLIVE" "$LAND"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Drift guards: wiring the compiled functions cannot prove about themselves.
# Code lines only, so a comment quoting a line cannot satisfy or trip these.
code() { grep -vE '^[[:space:]]*//' "$1"; }
code "$XLIVE" | grep -qF 'if LiveMessages.reads(.x)' \
  || { echo "✗ the X messages read no longer asks its switch — DMs would land for everyone"; exit 1; }
code "$IGLIVE" | grep -qF 'if LiveMessages.reads(.instagram)' \
  || { echo "✗ the Instagram messages read no longer asks its switch — DMs would land for everyone"; exit 1; }
code "$XLIVE" | grep -qF 'LiveMessagesLanding.land(' \
  || { echo "✗ the X messages read no longer lands through LiveMessagesLanding"; exit 1; }
code "$IGLIVE" | grep -qF 'LiveMessagesLanding.land(' \
  || { echo "✗ the Instagram messages read no longer lands through LiveMessagesLanding"; exit 1; }
code "$LAND" | grep -qF 'LiveMessages.merge(content: existing.content' \
  || { echo "✗ a landed conversation is no longer merged — new lines never reach it"; exit 1; }
# A read never marks anything read: those are POSTs this app never sends.
if code "$XLIVE" | grep -qE 'mark_read|markRead'; then
  echo "✗ the X live read sends a mark-read — reading here would clear the person's own unread"; exit 1
fi
if code "$IGLIVE" | grep -qE '/seen/|mark_seen|markSeen'; then
  echo "✗ the Instagram live read marks a thread seen — reading here would clear the person's own unread"; exit 1
fi
# The probes print shapes and names, never a message's words.
if code "$XLIVE" | grep -E 'xLiveDM' | grep -qE '\.text\b|lines\.map|\.content'; then
  echo "✗ the X messages probe prints message words"; exit 1
fi
if code "$IGLIVE" | grep -E 'igLiveDM' | grep -qE '\.text\b|lines\.map|\.content'; then
  echo "✗ the Instagram messages probe prints message words"; exit 1
fi
echo "live-messages-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? {
    try? JSONSerialization.jsonObject(with: Data(s.utf8))
}

// ── Times, in every magnitude ─────────────────────────────────────────
let sec = 1_757_890_000.0
check(LiveMessages.date(epoch: "1757890000000") == Date(timeIntervalSince1970: sec), "X's millisecond string")
check(LiveMessages.date(epoch: 1_757_890_000_000_000 as Int64) == Date(timeIntervalSince1970: sec), "Instagram's microseconds")
check(LiveMessages.date(epoch: "1757890000000000") == Date(timeIntervalSince1970: sec), "microseconds as a string")
check(LiveMessages.date(epoch: 1_757_890_000) == Date(timeIntervalSince1970: sec), "plain seconds")
check(LiveMessages.date(epoch: "soon") == nil && LiveMessages.date(epoch: nil) == nil && LiveMessages.date(epoch: 0) == nil,
      "anything else is nil, never now")

// ── Lines and titles ──────────────────────────────────────────────────
check(LiveMessages.line(sender: "Ana", isMe: false, text: "see you\n\nat 8 ") == "Ana: see you at 8",
      "a message's own line breaks become one line")
check(LiveMessages.line(sender: "Ana", isMe: true, text: "ok") == "You: ok", "your own line says You")
check(LiveMessages.line(sender: nil, isMe: false, text: "hi") == "hi", "an unknown sender is just the words")
check(LiveMessages.title(names: ["Ana"]) == "Messages with Ana", "a one-to-one names the person")
check(LiveMessages.title(names: ["Ana", "Bo"]) == "Messages with Ana and Bo", "two names")
check(LiveMessages.title(names: ["Ana", "Bo", "Cy", "Di"]) == "Messages with Ana, Bo and 2 more", "a crowd")
check(LiveMessages.title(names: []) == "Messages", "nobody named")

// ── The merge ─────────────────────────────────────────────────────────
func at(_ m: Double) -> Date { Date(timeIntervalSince1970: sec + m * 60) }
let a = LiveConversation.Line(id: "1", at: at(0), text: "Ana: hi")
let b = LiveConversation.Line(id: "2", at: at(1), text: "You: hey")
let c = LiveConversation.Line(id: "3", at: at(2), text: "Ana: dinner?")
let first = LiveMessages.merge(content: nil, newest: nil, count: nil, lines: [b, a])
check(first == LiveMessages.Merge(content: "Ana: hi\nYou: hey", newest: at(1), count: 2, appended: 2),
      "a first landing sorts oldest first and counts what it holds")
check(LiveMessages.merge(content: first!.content, newest: first!.newest, count: first!.count, lines: [a, b]) == nil,
      "a second read of the same lines changes nothing")
let grown = LiveMessages.merge(content: first!.content, newest: first!.newest, count: first!.count, lines: [a, b, c])
check(grown == LiveMessages.Merge(content: "Ana: hi\nYou: hey\nAna: dinner?", newest: at(2), count: 3, appended: 1),
      "a later read appends only what is newer")
let imported = LiveMessages.merge(content: "old one\nold two", newest: at(-10), count: 412, lines: [c])
check(imported?.count == 413 && imported?.content == "old one\nold two\nAna: dinner?",
      "the stored count is the conversation's, never the slice's")
let many = (0..<80).map { LiveConversation.Line(id: "\($0)", at: at(Double($0)), text: "line \($0)") }
let clamped = LiveMessages.merge(content: nil, newest: nil, count: nil, lines: many)!
check(clamped.content.split(separator: "\n").count == 60 && clamped.content.hasPrefix("line 20")
        && clamped.count == 80, "the transcript keeps the newest sixty lines and counts all eighty")
let long = LiveMessages.clamp([String(repeating: "a", count: 5000)])
check(long.count == LiveMessages.transcriptBytes, "and stays inside the byte ceiling")

// ── X ─────────────────────────────────────────────────────────────────
check(XLiveMessages.userID(fromTwid: "u%3D1234567890") == "1234567890", "twid, encoded")
check(XLiveMessages.userID(fromTwid: "\"u=42\"") == "42", "twid, decoded and quoted")
check(XLiveMessages.userID(fromTwid: "u=abc") == nil && XLiveMessages.userID(fromTwid: "") == nil, "not an id")

let xInbox = json("""
{"inbox_initial_state": {
  "entries": [
    {"message": {"id": "m1", "conversation_id": "100-200", "message_data": {"id": "m1", "time": "1757890000000",
      "sender_id": "200", "recipient_id": "100", "text": "read this https://t.co/abc",
      "entities": {"urls": [{"url": "https://t.co/abc", "expanded_url": "https://example.com/post"}]}}}},
    {"message": {"id": "m2", "conversation_id": "100-200", "message_data": {"id": "m2", "time": "1757890060000",
      "sender_id": "100", "text": "on it"}}},
    {"message": {"id": "m2", "conversation_id": "100-200", "message_data": {"id": "m2", "time": "1757890060000",
      "sender_id": "100", "text": "on it"}}},
    {"message": {"id": "m3", "conversation_id": "100-300", "message_data": {"id": "m3", "time": "1757890120000",
      "sender_id": "300", "text": "https://t.co/pic", "attachment": {"photo": {"url": "https://t.co/pic"}}}}},
    {"message": {"id": "m4", "conversation_id": "100-999", "message_data": {"id": "m4", "time": "1757890180000",
      "sender_id": "999", "text": "buy my course"}}},
    {"message": {"id": "m5", "conversation_id": "g1", "message_data": {"id": "m5", "time": "1757890240000",
      "sender_id": "300", "text": "who's in"}}},
    {"reaction_create": {"id": "r1", "conversation_id": "100-200"}},
    {"message": {"id": "m6", "conversation_id": "100-200", "message_data": {"id": "m6", "time": "1757890300000",
      "sender_id": "200", "text": "   "}}}
  ],
  "users": {
    "100": {"name": "Me", "screen_name": "me"},
    "200": {"name": "Ana", "screen_name": "ana", "profile_image_url_https": "https://pbs.twimg.com/a_normal.jpg"},
    "300": {"name": "", "screen_name": "bo"},
    "999": {"name": "Spam", "screen_name": "spam"}
  },
  "conversations": {
    "100-200": {"conversation_id": "100-200", "type": "ONE_TO_ONE", "trusted": true,
                "participants": [{"user_id": "100"}, {"user_id": "200"}]},
    "100-300": {"conversation_id": "100-300", "type": "ONE_TO_ONE",
                "participants": [{"user_id": "100"}, {"user_id": "300"}]},
    "100-999": {"conversation_id": "100-999", "type": "ONE_TO_ONE", "trusted": false,
                "participants": [{"user_id": "100"}, {"user_id": "999"}]},
    "g1": {"conversation_id": "g1", "type": "GROUP_DM", "name": "Trip", "trusted": true,
           "participants": [{"user_id": "100"}, {"user_id": "200"}, {"user_id": "300"}]}
  }
}}
""")
check(XLiveMessages.viewerID(xInbox) == "100", "the one id every conversation shares is you")
check(XLiveMessages.viewerID(json("""
{"inbox_initial_state": {"conversations": {"1-2": {"participants": [{"user_id": "1"}, {"user_id": "2"}]}}}}
""")) == nil, "a lone one-to-one cannot say which of two is you")
let xs = XLiveMessages.conversations(xInbox, me: "100") ?? []
check(xs.map(\.id) == ["g1", "100-300", "100-200"], "newest first, the message request skipped")
let ana = xs.first { $0.id == "100-200" }
check(ana?.title == "Messages with Ana" && ana?.handle == "ana", "a one-to-one is titled and faced by the other person")
check(ana?.avatar == "https://pbs.twimg.com/a_400x400.jpg", "at X's named size")
check(ana?.lines.map(\.text) == ["Ana: read this https://example.com/post", "You: on it"],
      "t.co out, your line is You, a repeated id lands once, an empty message not at all")
check(ana?.lines.first?.at == Date(timeIntervalSince1970: sec), "a line carries its own time")
check(xs.first { $0.id == "100-300" }?.lines.map(\.text) == ["@bo: Photo"],
      "a picture with no words is named, the link to itself dropped, a nameless sender by handle")
let trip = xs.first { $0.id == "g1" }
check(trip?.title == "Messages in Trip" && trip?.handle == nil && trip?.isGroup == true, "a group by its name, no face")
let unknownMe = XLiveMessages.conversations(xInbox, me: nil) ?? []
check(unknownMe.first { $0.id == "100-200" }?.lines.last?.text == "Me: on it",
      "without your id, your line keeps your name rather than guessing")
check(XLiveMessages.conversations(json(#"{"errors": [{"code": 239}]}"#), me: "1") == nil, "not an inbox is nil")

// ── Instagram ─────────────────────────────────────────────────────────
let igInbox = json("""
{"viewer": {"pk": 1, "username": "me"},
 "inbox": {"threads": [
   {"thread_id": "t1", "thread_title": "lena", "is_group": false,
    "users": [{"pk": 2, "pk_id": "2", "username": "lena", "full_name": "Lena", "profile_pic_url": "https://ig/lena.jpg"}],
    "items": [
      {"item_id": "i3", "user_id": 2, "timestamp": 1757890120000000, "item_type": "clip"},
      {"item_id": "i1", "user_id": 2, "timestamp": "1757890000000000", "item_type": "text", "text": "hey"},
      {"item_id": "i2", "user_id": 1, "timestamp": 1757890060000000, "item_type": "link", "link": {"text": "look https://x.y"}},
      {"item_id": "i4", "user_id": 2, "timestamp": 1757890180000000, "item_type": "action_log"},
      {"item_id": "i5", "user_id": 2, "timestamp": 1757890240000000, "item_type": "media", "media": {"media_type": 2}}
    ]},
   {"thread_id": "t2", "thread_title": "Climbing", "is_group": true,
    "users": [{"pk": 2, "username": "lena", "full_name": "Lena"}, {"pk": 3, "username": "rui", "full_name": ""}],
    "items": [{"item_id": "j1", "user_id": 3, "timestamp": 1757890300000000, "item_type": "text", "text": "sat?"},
              {"item_id": "j2", "user_id": 1, "timestamp": 1757890360000000, "item_type": "like", "is_sent_by_viewer": true}]},
   {"thread_id": "t3", "users": [{"pk": 4, "username": "quiet"}], "items": [{"item_id": "k1", "user_id": 4,
    "timestamp": 1757890000000000, "item_type": "placeholder"}]}
 ]}}
""")
check(InstagramLiveMessages.viewerID(igInbox) == "1", "the inbox states who you are")
let ig = InstagramLiveMessages.conversations(igInbox, me: "999") ?? []
check(ig.map(\.id) == ["t2", "t1"], "newest first, a thread with nothing readable skipped")
let lena = ig.first { $0.id == "t1" }
check(lena?.title == "Messages with Lena" && lena?.handle == "lena" && lena?.avatar == "https://ig/lena.jpg",
      "a one-to-one by the person's name and face")
check(lena?.lines.map(\.text) == ["Lena: hey", "You: look https://x.y", "Lena: Shared a reel", "Lena: Video"],
      "sorted by time, your line is You (the inbox's viewer beats the cookie), a share named, a log skipped")
check(lena?.lines.first?.at == Date(timeIntervalSince1970: sec), "microseconds read as microseconds")
let climbing = ig.first { $0.id == "t2" }
check(climbing?.title == "Messages in Climbing" && climbing?.isGroup == true && climbing?.handle == nil,
      "a group by its title, no face")
check(climbing?.lines.map(\.text) == ["@rui: sat?", "You: ❤️"], "a nameless member by handle, a like as a heart")
check(InstagramLiveMessages.conversations(json(#"{"message": "login_required", "status": "fail"}"#), me: "1") == nil,
      "not an inbox is nil")
check(InstagramLiveMessages.text(["item_type": "mystery"]) == nil, "an unknown item type is skipped, never guessed")

print(failures == 0 ? "live-messages-selftest: all checks ✓" : "live-messages-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$CONV" "$XDM" "$IGDM" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ live-messages-selftest: compile failed"; exit 1; }
"$TMP/run"
