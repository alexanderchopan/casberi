#!/bin/zsh
# Casberi Telegram messages self-test (prd §1575) — the pure half of the
# TDLib read, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/LiveConversation.swift
#   Casberi/Casberi/Model/TelegramMessages.swift
#
# Every failure here is silent on a device:
#
#   · a login code from Telegram's service account (777000) lands in the
#     corpus, where Find, Spotlight and the share card can surface it
#   · a channel or a bot lands as somebody you talk to
#   · a service line ("set messages to auto-delete") lands as a message
#   · your own lines in a one-to-one carry the other person's name
#   · Saved Messages says "You:" on every line, or is titled with your name
#   · a caption is dropped and a photo with words reads as just "Photo"
#
# The shapes are TDLib's documented `td_api` objects, MEASURED against one
# account's chats on 2026-10-27 (kinds and content types, never the words).
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CONV="Casberi/Casberi/Model/LiveConversation.swift"
TG="Casberi/Casberi/Model/TelegramMessages.swift"
READ="Casberi/Casberi/Model/TelegramMessagesRead.swift"
CLIENT="Casberi/Casberi/Model/TelegramClient.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
HOOKS="Casberi/Casberi/Shell/ProbeHooks.swift"
THING="Casberi/Shared/Thing.swift"
for f in "$CONV" "$TG" "$READ" "$CLIENT" "$REFRESH" "$HOOKS" "$THING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# Drift guards: wiring the compiled functions cannot prove about themselves.
code() { grep -vE '^[[:space:]]*//' "$1"; }
code "$READ" | grep -F 'guard TelegramClient.signedIn, LiveMessages.reads(.telegram)' >/dev/null \
  || { echo "✗ the Telegram read no longer asks its switch — chats would land for everyone signed in"; exit 1; }
code "$REFRESH" | grep -F 'if TelegramClient.signedIn, LiveMessages.reads(.telegram)' >/dev/null \
  || { echo "✗ the sweep no longer gates on sign-in and the switch — it would start TDLib for everyone"; exit 1; }
code "$READ" | grep -F 'LiveMessagesLanding.land(' >/dev/null \
  || { echo "✗ the Telegram read no longer lands through LiveMessagesLanding"; exit 1; }
code "$THING" | grep -F '"Telegram": ["telegram:post:", "telegram:dm:"]' >/dev/null \
  || { echo "✗ telegram:dm: is not a live prefix — chats stay out of All and \"Remove import\" deletes them"; exit 1; }
# Reading never marks anything read, and this seat never writes.
if code "$READ" "$CLIENT" 2>/dev/null | grep -E '"(viewMessages|sendMessage|openChat|readAllChatMentions|forwardMessages)"' >/dev/null; then
  echo "✗ the Telegram seat sends a write or a read receipt — it only reads"; exit 1
fi
for f in "$READ" "$CLIENT"; do
  if code "$f" | grep -E '"(viewMessages|sendMessage|openChat|forwardMessages|editMessageText)"' >/dev/null; then
    echo "✗ $f sends a write or a read receipt — the seat only reads"; exit 1
  fi
done
# TDLib never starts at launch: only the sign-in or a gated read starts it.
if grep -rE 'TelegramClient\.shared\.start\(\)' Casberi/Casberi --include='*.swift' | grep -v "$CLIENT" >/dev/null; then
  echo "✗ something outside TelegramClient starts TDLib directly — go through settled()"; exit 1
fi
# The probe prints shapes, never words.
if code "$HOOKS" | grep -E 'telegramDM\|' | grep -E '\.text\b|lines\.map|\.content|\.title' >/dev/null; then
  echo "✗ the Telegram messages probe prints message words or titles"; exit 1
fi
echo "telegram-messages-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func obj(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}
let me: Int64 = 10
let users: [Int64: TelegramMessages.User] = [
    20: TelegramMessages.user(obj(#"{"id":20,"first_name":"Ana","last_name":"Lima","usernames":{"active_usernames":["ana"]},"type":{"@type":"userTypeRegular"}}"#)),
    30: TelegramMessages.user(obj(#"{"id":30,"first_name":"Bo","last_name":"","type":{"@type":"userTypeRegular"}}"#)),
    40: TelegramMessages.user(obj(#"{"id":40,"first_name":"Weather","usernames":{"active_usernames":["wxbot"]},"type":{"@type":"userTypeBot"}}"#)),
]
func message(_ id: Int, _ date: Int, from: Int64, out: Bool = false, _ content: String) -> [String: Any] {
    obj(#"{"id":\#(id),"date":\#(date),"is_outgoing":\#(out),"sender_id":{"@type":"messageSenderUser","user_id":\#(from)},"content":\#(content)}"#)
}
func text(_ s: String) -> String { #"{"@type":"messageText","text":{"@type":"formattedText","text":"\#(s)"}}"# }

// ── Users ─────────────────────────────────────────────────────────────
check(users[20]?.label == "Ana Lima" && users[20]?.handle == "ana", "a name and its active username")
check(users[30]?.label == "Bo" && users[30]?.handle == nil, "an empty last name adds no space")
check(users[40]?.isBot == true, "a bot is known as one")

// ── Which chats are read ──────────────────────────────────────────────
func chat(_ id: Int64, _ type: String, title: String = "") -> [String: Any] {
    obj(#"{"id":\#(id),"title":"\#(title)","type":\#(type)}"#)
}
let ana = chat(20, #"{"@type":"chatTypePrivate","user_id":20}"#, title: "Ana Lima")
let saved = chat(10, #"{"@type":"chatTypePrivate","user_id":10}"#, title: "Me")
let service = chat(777000, #"{"@type":"chatTypePrivate","user_id":777000}"#, title: "Telegram")
let bot = chat(40, #"{"@type":"chatTypePrivate","user_id":40}"#, title: "Weather")
let group = chat(-500, #"{"@type":"chatTypeBasicGroup","basic_group_id":500}"#, title: "Climbing")
let supergroup = chat(-1001, #"{"@type":"chatTypeSupergroup","supergroup_id":1,"is_channel":false}"#, title: "Builders")
let channel = chat(-1002, #"{"@type":"chatTypeSupergroup","supergroup_id":2,"is_channel":true}"#, title: "News")
let secret = chat(-3, #"{"@type":"chatTypeSecret","secret_chat_id":3,"user_id":20}"#)
check(TelegramMessages.kind(ana, me: me, users: users) == .oneToOne(userID: 20), "a one-to-one")
check(TelegramMessages.kind(saved, me: me, users: users) == .saved, "your own chat is Saved Messages")
check(TelegramMessages.kind(service, me: me, users: users) == nil, "Telegram's service account (login codes) is never read")
check(TelegramMessages.kind(bot, me: me, users: users) == nil, "a bot is not somebody you talk to")
check(TelegramMessages.kind(group, me: me, users: users) == .group, "a small group")
check(TelegramMessages.kind(supergroup, me: me, users: users) == .group, "a supergroup")
check(TelegramMessages.kind(channel, me: me, users: users) == nil, "a channel is the follow half's")
check(TelegramMessages.kind(secret, me: me, users: users) == nil, "a secret chat is never read")
let code = TelegramMessages.conversation(chat: service, messages: [message(1, 1_757_890_000, from: 777000, text("Login code: 12345"))],
                                         users: users, me: me)
check(code == nil, "a login code never becomes a conversation")

// ── Content ───────────────────────────────────────────────────────────
check(TelegramMessages.text(obj(text("  hi  "))) == "hi", "words, trimmed")
check(TelegramMessages.text(obj(#"{"@type":"messagePhoto","caption":{"text":"the view"}}"#)) == "Photo: the view", "a photo keeps its caption")
check(TelegramMessages.text(obj(#"{"@type":"messagePhoto","caption":{"text":""}}"#)) == "Photo", "a bare photo is named")
check(TelegramMessages.text(obj(#"{"@type":"messageDocument","document":{"file_name":"plan.pdf"},"caption":{"text":""}}"#)) == "plan.pdf", "a file by its name")
check(TelegramMessages.text(obj(#"{"@type":"messageSticker","sticker":{"emoji":"👍"}}"#)) == "👍", "a sticker as its emoji")
check(TelegramMessages.text(obj(#"{"@type":"messagePoll","poll":{"question":{"text":"Pizza?"}}}"#)) == "Poll: Pizza?", "a poll's question, the newer shape")
check(TelegramMessages.text(obj(#"{"@type":"messagePoll","poll":{"question":"Pizza?"}}"#)) == "Poll: Pizza?", "a poll's question, the older shape")
for service in ["messageChatSetMessageAutoDeleteTime", "messageChatAddMembers", "messagePinMessage",
                "messageChatJoinByLink", "messageChatDeleteMember", "messageMysteryFromTheFuture"] {
    check(TelegramMessages.text(obj(#"{"@type":"\#(service)"}"#)) == nil, "\(service) lands nothing")
}

// ── Conversations ─────────────────────────────────────────────────────
let one = TelegramMessages.conversation(chat: ana, messages: [
    message(3, 1_757_890_120, from: 10, out: true, text("see you at 8")),
    message(2, 1_757_890_060, from: 20, #"{"@type":"messageChatSetMessageAutoDeleteTime"}"#),
    message(1, 1_757_890_000, from: 20, text("dinner?\\nat Rosa's")),
    message(1, 1_757_890_000, from: 20, text("dinner?\\nat Rosa's")),
], users: users, me: me)
check(one?.id == "20" && one?.title == "Messages with Ana Lima" && one?.handle == "ana" && one?.isGroup == false,
      "a one-to-one by the person's name and handle")
check(one?.lines.map(\.text) == ["dinner? at Rosa's", "You: see you at 8"],
      "oldest first, theirs unnamed, yours You, a service line and a repeat dropped")
check(one?.lines.first?.at == Date(timeIntervalSince1970: 1_757_890_000), "TDLib's seconds read as seconds")
let notes = TelegramMessages.conversation(chat: saved, messages: [
    message(1, 1_757_890_000, from: 10, out: true, text("https://example.com/read-later")),
], users: users, me: me)
check(notes?.title == "Saved Messages" && notes?.lines.map(\.text) == ["https://example.com/read-later"],
      "Saved Messages is titled so and its lines carry no You")
let climbing = TelegramMessages.conversation(chat: group, messages: [
    message(2, 1_757_890_060, from: 10, out: true, text("in")),
    message(1, 1_757_890_000, from: 30, text("Saturday?")),
    obj(#"{"id":3,"date":1757890120,"is_outgoing":false,"sender_id":{"@type":"messageSenderChat","chat_id":-1002},"content":\#(text("pinned the plan"))}"#),
], users: users, chatTitles: [-1002: "News"], me: me)
check(climbing?.title == "Messages in Climbing" && climbing?.isGroup == true && climbing?.handle == nil,
      "a group by its title, no face")
check(climbing?.lines.map(\.text) == ["Bo: Saturday?", "You: in", "News: pinned the plan"],
      "members by name, yours You, a chat sender by its title")
check(TelegramMessages.conversation(chat: group, messages: [
    message(1, 1_757_890_000, from: 30, #"{"@type":"messageChatAddMembers"}"#)], users: users, me: me) == nil,
      "a page of only service lines is no conversation")
check(TelegramMessages.lastActivity(obj(#"{"last_message":{"date":1757890000}}"#)) == Date(timeIntervalSince1970: 1_757_890_000),
      "a chat's last activity")

print(failures == 0 ? "telegram-messages-selftest: all checks ✓" : "telegram-messages-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$CONV" "$TG" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ telegram-messages-selftest: compile failed"; exit 1; }
"$TMP/run"
