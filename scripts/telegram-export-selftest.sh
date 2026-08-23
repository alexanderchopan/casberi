#!/bin/zsh
# Casberi Telegram EXPORT self-test — the SHIPPED parse behind the import half
# of the Telegram seat (prd §456):
#
#   Casberi/Casberi/Model/TelegramExport.swift   (compiled WHOLE and unmodified)
#
# It is Foundation-only BY DESIGN — no `Thing`, no `ModelContext`, deliberately
# not even `IngestSupport` — so it is compiled AS SHIPPED with no stubs at all,
# which is the strongest form a harness takes in this repo. Everything that
# touches the corpus lives in `TelegramImport.swift`, which no harness can
# compile and which carries no judgement to test; the wiring facts that file
# owns are covered by the drift guards below instead.
#
# WHY A HARNESS AND NOT A MEASUREMENT. **No real Telegram export has ever been
# held by this project.** There is no key to mint, no account to open and no
# host to reach — the export is a file a person asks their own desktop client
# for, and this host has never seen one. So unlike the Stripe or PostHog
# harnesses, which anyone willing to mint a key could check against a live
# account, this is not the best proof these rules hold: it is the ONLY one.
#
# Every failure it catches renders as a perfectly ordinary room:
#
#   · a decade of messages dated to nothing at all, because `date_unixtime` was
#     ignored and the naive `date` (ISO local time with NO offset, in a zone the
#     export records nowhere) was trusted instead
#   · an import that lands real rows, reports success, and silently loses every
#     chat but the first — the single-chat fork sniffing `messages`, which a
#     full export's chats all carry too
#   · every photograph, voice note and sticker in the export dropped, because
#     the export was made with file downloading switched OFF and the placeholder
#     sentence was read as "no media"
#   · somebody's words corrupted rather than repaired: a message really
#     containing `\x41` arrives as `\\x41`, and rewriting that escaped pair
#     turns it into a different string
#   · a login code out of `verification_codes` walked into the corpus, into
#     Spotlight, and into whatever a keyed agent is grounded on
#   · a whole conversation attributed to the wrong person, because the self-ID
#     comparison went and the name heuristic — which structurally cannot answer
#     inside a group — was left carrying it
#   · a decade-long friendship ranking below a week-old chat, because the
#     message total was counted AFTER the line clamp
#   · a truncated import wearing a complete import's receipt (prd §307/§309)
#
# Nothing in a build, a screen sweep or a nightly host check can see one of
# them. The live half (`Model/TelegramChannel.swift`) is deliberately NOT
# covered here — it is `scripts/telegram-selftest.sh`'s file, with its own
# shapes and its own failures.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

# TZ IS PINNED, and it is not tidiness. Schema fact 4: `date` is ISO local time
# with no offset, in the EXPORTING machine's zone, which the export records
# NOWHERE — so the shipped fallback reads it in `TimeZone.current` by design
# (see `naiveLocalDate`). Left to the machine, the legacy fixture's expected
# instant would move by up to a day between two developers, and a harness that
# does not mean the same thing twice cannot be believed the first time.
export TZ=UTC

EXPORT="Casberi/Casberi/Model/TelegramExport.swift"
IMPORT="Casberi/Casberi/Model/TelegramImport.swift"
CHANNEL="Casberi/Casberi/Model/TelegramChannel.swift"
THING="Casberi/Shared/Thing.swift"
for f in "$EXPORT" "$IMPORT" "$CHANNEL" "$THING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Comment-stripped copies for the NEGATIVE guards below. Both files DOCUMENT
# the rules they follow by naming the very literal they must not carry —
# `Thing.swift` explains `liveRefPrefixes` by spelling `telegram:saved:…` in
# prose two lines above it — so a guard grepping raw source fires against the
# paragraph explaining the rule rather than a violation of it. That is the
# Obsidian/Cursor lesson, and this repo has now paid for it seven times.
strip_comments() {
  python3 - "$1" > "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
out = []
for line in src.split("\n"):
    s = line.lstrip()
    if s.startswith("//") or s.startswith("///"):
        continue
    out.append(line)
print("\n".join(out))
PY
}
strip_comments "$IMPORT" "$TMP/import.nc"
strip_comments "$THING" "$TMP/thing.nc"

# --- drift guards -----------------------------------------------------------
# Each is a wiring fact the compiled parse cannot prove about itself. A perfect
# `Entry` is worthless if the landing half files it under a namespace that
# floods the All feed, and a perfect `Parsed` is worthless if the gate that
# keeps private correspondence out of it was hardcoded open.

# (1) THE REF NAMESPACES ARE BUILT, NEVER RE-SPELLED. This is
# `ref-shape-audit`'s exact class: a producer stamping one namespace and a
# consumer matching another is two halves in two files that cannot see each
# other, and when they stop agreeing nothing BREAKS — the room simply goes
# quiet, which from outside is indistinguishable from an empty import.
for builder in 'TelegramExport.savedRef(' 'TelegramExport.chatRef(' 'TelegramExport.channelRef('; do
  grep -qF "$builder" "$IMPORT" \
    || { echo "✗ TelegramImport no longer calls $builder — a ref spelled a second time is a ref that can drift"; exit 1; }
done
for literal in 'telegram:saved:' 'telegram:chat:' 'telegram:channel:'; do
  if grep -qF "$literal" "$TMP/import.nc"; then
    echo "✗ TelegramImport spells the literal \"$literal\" instead of calling the builder — the two halves can now drift with nothing to say so"; exit 1
  fi
done

# (2) NEGATIVE — none of the three import namespaces may join the LIVE set.
# `Corpus.liveRefPrefixes` is what decides whether a row reaches the All feed or
# stays in its own bulk-import room, so an overlap either floods All with a
# decade of somebody's DMs or silences a followed channel. Both render
# perfectly from the inside. Read from the comment-stripped copy: `Thing.swift`
# names two of these three in the prose that explains the set.
for literal in 'telegram:saved:' 'telegram:chat:' 'telegram:channel:'; do
  if grep -qF "$literal" "$TMP/thing.nc"; then
    echo "✗ \"$literal\" reaches Corpus.liveRefPrefixes — an imported message would land in the All feed as though it had just arrived"; exit 1
  fi
done
grep -qF '"telegram:post:"' "$THING" \
  || { echo "✗ \"telegram:post:\" is no longer in Corpus.liveRefPrefixes — the live half and the import half no longer divide"; exit 1; }
grep -qF 'static let refPrefix = "telegram:post:"' "$CHANNEL" \
  || { echo "✗ TelegramChannel.refPrefix moved — the non-collision the export's namespaces are chosen against is no longer where they were checked"; exit 1; }

# (3) THE DM GATE IS THE PERSON'S, NOT OURS (prd §310). `includeMessages` is
# OFF by default at every call site: somebody's private correspondence enters
# the corpus only because they said so, in a control above the folder pick that
# they had to find. A hardcoded `true` here lands a decade of DMs on a tap that
# never asked, and every row of it looks exactly like a row they wanted.
grep -qF 'TelegramExport.parse(root, includeMessages: ImportOptions.includeMessages)' "$IMPORT" \
  || { echo "✗ the import no longer routes the DM gate through ImportOptions.includeMessages — private correspondence must never land un-asked"; exit 1; }

# (4) THE ONE SOURCE STRING. Both halves of this seat land under it, so a
# followed channel and an imported export share one room; spelled twice, they
# would quietly become two.
grep -qF 'static let source = TelegramExport.source' "$IMPORT" \
  || { echo "✗ TelegramImport no longer takes its source string from TelegramExport — the live and imported halves would split into two rooms"; exit 1; }

echo "telegram-export-selftest: drift guards ✓"

# --- the assertions ---------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

// Compiled beside TelegramExport.swift, which is taken WHOLE and unmodified.
// Run with TZ=UTC (the script exports it) so the naive-date fallback is
// deterministic — see the note at the top of the harness.

var failures = 0
var checks = 0

func check(_ ok: Bool, _ what: String) {
    checks += 1
    if !ok {
        failures += 1
        print("  ✗ \(what)")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    checks += 1
    if a != b {
        failures += 1
        print("  ✗ \(what)\n      got:      \(a)\n      expected: \(b)")
    }
}

print("TelegramExport")

// MARK: - 1. repairControlEscapes (schema fact 1)

// Backslashes are spelled out rather than written into a raw literal, so no
// expectation here can hide a literal control byte that only LOOKS repaired.
let BS = "\\"

eq(TelegramExport.repairControlEscapes("a" + BS + "x0bb"), "a" + BS + "u000bb", "single control escape")
eq(TelegramExport.repairControlEscapes(BS + "x1f"), BS + "u001f", "escape at string start")
eq(TelegramExport.repairControlEscapes("plain text"), "plain text", "no backslash-x is identity")
// THE TRAP, and the reason the run is counted rather than looked at. An ESCAPED
// backslash followed by the literal characters x41 is somebody's own text and
// must NOT be rewritten — rewriting it turns their words into a different
// string, which is worse than not repairing at all.
eq(TelegramExport.repairControlEscapes("a" + BS + BS + "x41b"), "a" + BS + BS + "x41b", "escaped backslash left alone")
// PARITY, both ways. These four are the hard-won half: a fixture set that only
// ever tests ONE parity is satisfied by inverting the rule, so the odd runs and
// the even runs are asserted together and the mutation below has nowhere to
// hide. Three backslashes: two are a pair, the third introduces a real escape.
eq(TelegramExport.repairControlEscapes("a" + BS + BS + BS + "x0bb"), "a" + BS + BS + BS + "u000bb", "odd run after a pair")
eq(TelegramExport.repairControlEscapes("a" + String(repeating: BS, count: 4) + "x41"), "a" + String(repeating: BS, count: 4) + "x41", "four backslashes are two pairs")
eq(TelegramExport.repairControlEscapes("a" + BS + "xzz"), "a" + BS + "xzz", "non-hex left alone")
eq(TelegramExport.repairControlEscapes("a" + BS + "x0"), "a" + BS + "x0", "truncated escape left alone")
eq(TelegramExport.repairControlEscapes("a" + BS + "nb" + BS + "x09c"), "a" + BS + "nb" + BS + "u0009c", "real JSON escapes survive untouched")
eq(TelegramExport.repairControlEscapes(BS + "x0b" + BS + "x0c"), BS + "u000b" + BS + "u000c", "two in a row")
eq(TelegramExport.repairControlEscapes(BS + "x0B"), BS + "u000B", "uppercase hex")

// MARK: - 2. decode over invalid JSON

// The whole reason `decode` exists: `JSONSerialization` refuses the WHOLE
// document over one control byte and returns no partial result, so a real
// export carrying a single vertical tab in a decade of messages is unreadable
// end to end — and the failure looks exactly like "this isn't a Telegram
// export".
let brokenJSON = #"""
{"name":"Bob","type":"personal_chat","id":222,"messages":[
 {"id":1,"type":"message","date":"2016-06-01T09:30:00","date_unixtime":"1464773400",
  "from":"Bob","from_id":222,"text":"line1\x0bline2"}]}
"""#
let brokenData = Data(brokenJSON.utf8)
check((try? JSONSerialization.jsonObject(with: brokenData)) == nil, "JSONSerialization refuses the raw bytes")
guard let repairedRoot = TelegramExport.decode(brokenData) else {
    print("  ✗ decode failed on the \\xNN fixture — nothing else can run")
    exit(1)
}
let repairedChats = TelegramExport.chats(in: repairedRoot)
eq(repairedChats.count, 1, "repaired single-chat export yields one chat")
if let first = (repairedChats.first?["messages"] as? [Any])?.first as? [String: Any] {
    eq(TelegramExport.body(of: first), "line1\u{0b}line2", "control byte survives the repair as itself")
}

// MARK: - 3. Modern full export

let modern = #"""
{
  "about": "an export",
  "personal_information": {"user_id": 111, "first_name": "Ada", "last_name": "L"},
  "chats": {
    "about": "chats",
    "list": [
      { "type": "saved_messages", "id": 111,
        "messages": [
          {"id": 1, "type": "message", "date": "2020-08-01T22:01:49", "date_unixtime": "1596319309",
           "from": "Ada L", "from_id": "user111",
           "text": [{"type":"plain","text":"read this "},{"type":"link","text":"https://example.com/a"}],
           "text_entities": [{"type":"plain","text":"read this "},{"type":"link","text":"https://example.com/a"}]},
          {"id": 2, "type": "message", "date": "2020-08-01T22:03:20", "date_unixtime": "1596319400",
           "from": "Ada L", "from_id": "user111",
           "photo": "chats/chat_01/photos/photo_1@01-08-2020_22-03-20.jpg",
           "photo_file_size": 1234, "width": 10, "height": 10,
           "text": "", "text_entities": []},
          {"id": 3, "type": "unsupported"},
          {"id": 4, "type": "service", "date": "2020-08-01T22:04:00", "date_unixtime": "1596319440",
           "actor": "Ada L", "actor_id": "user111", "action": "pin_message",
           "text": "", "text_entities": []},
          {"id": 5, "type": "message", "date": "2020-08-02T09:00:00", "date_unixtime": "1596358800",
           "from": "Ada L", "from_id": "user111",
           "file": "(File not included. Change data exporting settings to download.)",
           "media_type": "voice_message", "duration_seconds": 7,
           "text": "", "text_entities": []},
          {"id": 6, "type": "message", "date": "2020-08-02T10:00:00", "date_unixtime": "1596362400",
           "from": "Ada L", "from_id": "user111", "text": "", "text_entities": [],
           "poll": {"question": [{"type":"plain","text":"Tea or coffee?"}], "closed": false,
                    "total_voters": 3,
                    "answers": [{"text":"Tea","voters":2,"chosen":true},
                                {"text":[{"type":"plain","text":"Coffee"}],"voters":1,"chosen":false}]}},
          {"id": 7, "type": "message", "date": "2020-08-02T11:00:00", "date_unixtime": "1596366000",
           "from": "Ada L", "from_id": "user111", "forwarded_from": "Some Channel",
           "text": "forwarded words", "text_entities": [{"type":"plain","text":"forwarded words"}]},
          {"id": 8, "type": "message", "date": "1999-01-01T00:00:00", "date_unixtime": "1596400000",
           "from": "Ada L", "from_id": "user111", "reply_to_message_id": 7,
           "text": "disagreeing stamps", "text_entities": [{"type":"plain","text":"disagreeing stamps"}]},
          {"id": 9, "type": "message", "date": "2020-08-02T12:00:00", "date_unixtime": "1596400500",
           "from": "Ada L", "from_id": "user111",
           "text_entities": [{"type":"text_link","text":"the docs","href":"https://a.example/one"},
                             {"type":"plain","text":" and "},
                             {"type":"link","text":"https://b.example/two"}]}
        ]},
      { "name": "Bob", "type": "personal_chat", "id": 222,
        "messages": [
          {"id":1,"type":"message","date":"2021-01-01T10:00:00","date_unixtime":"1609495200",
           "from":"Bob","from_id":"user222","text":"hi","text_entities":[{"type":"plain","text":"hi"}]},
          {"id":2,"type":"message","date":"2021-01-01T10:01:00","date_unixtime":"1609495260",
           "from":"Ada L","from_id":"user111","text":"hello","text_entities":[{"type":"plain","text":"hello"}]},
          {"id":3,"type":"message","date":"2021-01-01T10:02:00","date_unixtime":"1609495320",
           "from":"Bob","from_id":"user222",
           "file":"chats/chat_02/round_video_messages/video_1@01-01-2021.mp4",
           "media_type":"video_message","text":"","text_entities":[]}
        ]},
      { "name": "Some Channel", "type": "public_channel", "id": 333,
        "messages": [
          {"id":10,"type":"message","date":"2022-05-05T12:00:00","date_unixtime":"1651752000",
           "from":"Some Channel","from_id":"channel333","text":"post one",
           "text_entities":[{"type":"plain","text":"post one"}]},
          {"id":11,"type":"message","date":"2022-05-06T12:00:00","date_unixtime":"1651838400",
           "from":"Some Channel","from_id":"channel333",
           "text":[{"type":"text_link","text":"docs","href":"https://example.org/docs"}],
           "text_entities":[{"type":"text_link","text":"docs","href":"https://example.org/docs"}]}
        ]},
      { "type": "verification_codes", "id": 444,
        "messages": [
          {"id":1,"type":"message","date":"2022-05-05T12:00:00","date_unixtime":"1651752000",
           "from":"Telegram","from_id":"user777","text":"Login code: 55512",
           "text_entities":[{"type":"plain","text":"Login code: 55512"}]}
        ]}
    ]
  },
  "left_chats": {"about":"left","list":[
      {"name":"Old Group","type":"private_group","id":555,
       "messages":[{"id":1,"type":"message","date":"2019-03-03T08:00:00","date_unixtime":"1551600000",
                    "from":"Cid","from_id":"user999","text":"yo",
                    "text_entities":[{"type":"plain","text":"yo"}]},
                   {"id":2,"type":"message","date":"2019-03-03T08:01:00","date_unixtime":"1551600060",
                    "from":"Ada Lovelace","from_id":"user111","text":"mine",
                    "text_entities":[{"type":"plain","text":"mine"}]}]}
  ]}
}
"""#

guard let modernRoot = TelegramExport.decode(Data(modern.utf8)) else {
    print("  ✗ modern fixture did not decode")
    exit(1)
}

eq(TelegramExport.chats(in: modernRoot).count, 5, "full export folds in left_chats")

let quiet = TelegramExport.parse(modernRoot, includeMessages: false)
check(quiet.isExport, "modern export is recognised as one")
eq(quiet.counts.chats, 5, "chats counted")
eq(quiet.conversations.count, 0, "DMs are OFF unless asked for")
eq(quiet.counts.service, 1, "the service message was counted, not landed")
eq(quiet.counts.unsupported, 1, "the unsupported message was counted, not landed")
eq(quiet.counts.chatsSkipped, 1, "verification_codes is skipped")
check(!quiet.savedMessages.contains { $0.text.contains("55512") },
      "a login code never enters the corpus")

eq(quiet.savedMessages.map(\.id), [9, 8, 7, 6, 5, 2, 1], "saved messages newest first, service/unsupported gone")

let saved = Dictionary(uniqueKeysWithValues: quiet.savedMessages.map { ($0.id, $0) })
if let one = saved[1] {
    eq(one.text, "read this https://example.com/a", "entity array joins in order")
    eq(one.links, ["https://example.com/a"], "a `link` entity's own text is the URL")
    eq(one.date, Date(timeIntervalSince1970: 1596319309), "date_unixtime is authoritative")
    check(one.mediaLabel == nil, "a words-only message has no media label")
    check(!one.isPhoto, "a words-only message is not a photo")
}
if let two = saved[2] {
    eq(two.text, "", "a bare photograph carries no words")
    eq(two.mediaLabel, "Photo", "the `photo` key alone names a photograph")
    check(two.isPhoto, "isPhoto is set off the photo key")
    eq(two.mediaPath, "chats/chat_01/photos/photo_1@01-08-2020_22-03-20.jpg",
       "the per-chat prefix is preserved exactly")
    check(two.isWordless, "wordless")
}
if let five = saved[5] {
    eq(five.mediaLabel, "Voice message", "media_type names the message")
    check(five.mediaPath == nil, "a placeholder path resolves to nil")
    check(!five.isPhoto, "a voice note is not a photo")
}
if let six = saved[6] {
    check(six.text.hasPrefix("Tea or coffee?"), "a poll's question leads")
    check(six.text.contains("· Tea") && six.text.contains("· Coffee"),
          "both polymorphic answers are read")
    check(!six.text.contains("2"), "vote tallies are refused")
    eq(six.mediaLabel, "Poll", "a poll labels itself")
}
if let seven = saved[7] {
    eq(seven.forwardedFrom, "Some Channel", "forwarded_from survives")
    check(seven.replyTo == nil, "no reply_to means no replyTo")
}
if let nine = saved[9] {
    eq(nine.text, "the docs and https://b.example/two", "both entity kinds render their words")
    // FIXTURE 3 OF THE FOUR HARD-WON ONES. This message carries a `text_link`
    // AND a bare `link`, and the bare-URL FALLBACK structurally cannot reach
    // it: the fallback runs only when the entity pass found nothing, and the
    // text_link already made that pass non-empty. So this is the only shape
    // that can prove `case "link"` is still collected on the entity path —
    // a message with a lone bare link is rescued by the fallback and passes
    // green with that case deleted.
    eq(nine.links, ["https://a.example/one", "https://b.example/two"],
       "a text_link's href AND a bare link's own text")
}
if let eight = saved[8] {
    // FIXTURE 1 OF THE FOUR. The two stamps DISAGREE by 21 years ON PURPOSE:
    // a fixture whose `date` and `date_unixtime` mean the same instant cannot
    // fail the rule it names, so "ignore date_unixtime and trust the naive
    // date" passes green over it. Here the naive date is 1999 and the
    // authoritative one is 2020.
    eq(eight.date, Date(timeIntervalSince1970: 1596400000),
       "date_unixtime BEATS the naive date, not merely agrees with it")
    eq(eight.replyTo, 7, "reply_to_message_id")
}

eq(quiet.channels.count, 1, "one channel")
if let channel = quiet.channels.first {
    eq(channel.id, 333, "channel id")
    eq(channel.name, "Some Channel", "channel name")
    eq(channel.entries.map(\.id), [11, 10], "channel posts newest first")
    eq(channel.entries.first?.text, "docs", "text_link words are the body")
    eq(channel.entries.first?.links ?? [], ["https://example.org/docs"],
       "a text_link's href is the URL, not its words")
}

// Refs must never collide with the LIVE channel prefix — an overlap either
// floods the All feed with a decade of somebody's DMs or silences a followed
// channel, and both render perfectly from the inside.
for ref in [TelegramExport.savedRef(messageID: 1),
            TelegramExport.chatRef(chatID: 222),
            TelegramExport.channelRef(chatID: 333, messageID: 11)] {
    check(!ref.hasPrefix("telegram:post:"), "\(ref) does not collide with the live prefix")
}
eq(TelegramExport.channelRef(chatID: 333, messageID: 11), "telegram:channel:333/11", "channel ref shape")

// MARK: - 4. Conversations, gated

let loud = TelegramExport.parse(modernRoot, includeMessages: true)
eq(loud.conversations.count, 2, "a DM and a left group")
if let bob = loud.conversations.first(where: { $0.id == 222 }) {
    eq(bob.handle, "Bob", "named after the counterpart")
    eq(bob.kind, TelegramExport.ChatKind.personal, "kind")
    eq(bob.total, 3, "every message counted")
    eq(bob.lines, ["Bob: hi", "You: hello", "Bob sent a video message"],
       "own messages say You; a wordless one says what it was")
    eq(bob.newest, Date(timeIntervalSince1970: 1609495320), "newest is the last message")
    eq(bob.transcript, "Bob: hi\nYou: hello\nBob sent a video message", "transcript joins lines")
}
if let group = loud.conversations.first(where: { $0.id == 555 }) {
    // FIXTURE 2 OF THE FOUR. The group message's `from` is "Ada Lovelace" and
    // the account's `personal_information` name is "Ada L" — they DIFFER on
    // purpose. The name heuristic structurally cannot answer inside a group
    // (it would label every other member "You"), and the display-name test
    // cannot fire either, so the id comparison is the ONLY thing that can
    // answer here. Make the two names equal and deleting the id comparison
    // survives green.
    eq(group.lines, ["Cid: yo", "You: mine"],
       "in a group only the self ID can say You")
    eq(group.kind, TelegramExport.ChatKind.group, "supergroup folds to group")
}
check(loud.savedMessages.count == quiet.savedMessages.count,
      "the gate touches only conversations")

// MARK: - 5. Legacy single-chat export (no date_unixtime, no text_entities, numeric from_id)

let legacy = #"""
{"name":"Bob","type":"personal_chat","id":222,"messages":[
 {"id":1,"type":"message","date":"2016-06-01T09:30:00","from":"Bob","from_id":222,"text":"legacy hi"},
 {"id":2,"type":"message","date":"2016-06-01T09:31:00","from":"Ada L","from_id":111,
  "text":["see ","https://legacy.example/x"]},
 {"id":3,"type":"message","date":"2016-06-01T09:32:00","from":"Bob","from_id":222,
  "photo":"photos/photo_1@01-06-2016_09-32-00.jpg"},
 {"id":4,"type":"message","date":"2016-06-01T09:33:00","from":"Bob","from_id":222,"text":""}
]}
"""#
guard let legacyRoot = TelegramExport.decode(Data(legacy.utf8)) else {
    print("  ✗ legacy fixture did not decode")
    exit(1)
}
eq(TelegramExport.chats(in: legacyRoot).count, 1, "a bare chat object IS the export")
let old = TelegramExport.parse(legacyRoot, includeMessages: true)
check(old.isExport, "single-chat export recognised")
eq(old.conversations.count, 1, "one conversation")
if let convo = old.conversations.first {
    eq(convo.lines,
       ["Bob: legacy hi", "You: see https://legacy.example/x", "Bob sent a photo"],
       "legacy: numeric from_id, polymorphic array text, name heuristic for You")
    eq(convo.total, 3, "the empty message is not counted as a line")
}
eq(old.counts.empty, 1, "a message with neither words nor media is counted")
// TZ=UTC makes the naive fallback exact; 2016-06-01T09:30:00Z == 1464773400.
if let legacyMessages = (TelegramExport.chats(in: legacyRoot).first?["messages"] as? [Any]),
   let first = legacyMessages.first as? [String: Any] {
    eq(TelegramExport.timestamp(first), Date(timeIntervalSince1970: 1464773400),
       "naive local date, read in the device zone")
    eq(TelegramExport.body(of: first), "legacy hi", "legacy body comes off `text`")
}
if let legacyMessages = (TelegramExport.chats(in: legacyRoot).first?["messages"] as? [Any]),
   legacyMessages.count > 1, let second = legacyMessages[1] as? [String: Any] {
    eq(TelegramExport.links(in: second), ["https://legacy.example/x"],
       "bare-URL fallback when the export carries no entities")
}

// A full export must NOT be read as a bare chat even though its chats have
// messages (schema fact 2) — sniffing `messages` reads the first chat and
// throws every other one away, which lands real rows and reports success.
eq(TelegramExport.chats(in: ["chats": ["list": [[String: Any]]()], "messages": [Any]()]).count, 0,
   "the fork keys on `chats`, never on `messages`")

// MARK: - 6. Media placeholders, all three, prefixed and bare (schema fact 6)

for placeholder in [
    "(File unavailable, please try again later)",
    "(File exceeds maximum size. Change data exporting settings to download.)",
    "(File not included. Change data exporting settings to download.)",
] {
    check(TelegramExport.mediaPath(placeholder) == nil, "bare placeholder: \(placeholder)")
    // The PREFIXED form is what makes the substring match load-bearing:
    // Telegram writes `name + " " + "(File not included…)"`, so an equality
    // test resolves the sentence to a "path" the landing half then tries to
    // open.
    check(TelegramExport.mediaPath("report.pdf " + placeholder) == nil,
          "name-prefixed placeholder: \(placeholder)")
}
eq(TelegramExport.mediaPath("photos/photo_1@x.jpg"), "photos/photo_1@x.jpg", "a real path survives")
check(TelegramExport.mediaPath(nil) == nil, "absent path")
check(TelegramExport.mediaPath("") == nil, "empty path")
// The photo field uses the "File" wording despite its key name.
eq(TelegramExport.mediaLabel(["photo": "(File not included. Change settings.)"]), "Photo",
   "a photo whose file was not exported is still a photo")
check(TelegramExport.attachmentPath(["photo": "(File not included. Change settings.)"]) == nil,
      "…but has no pixels on disk")

// MARK: - 7. mediaLabel across the six media types plus the generic document

eq(TelegramExport.mediaLabel(["file": "a", "media_type": "sticker"]), "Sticker", "sticker")
eq(TelegramExport.mediaLabel(["file": "a", "media_type": "video_message"]), "Video message", "video note")
eq(TelegramExport.mediaLabel(["file": "a", "media_type": "voice_message"]), "Voice message", "voice")
eq(TelegramExport.mediaLabel(["file": "a", "media_type": "animation"]), "GIF", "animation")
eq(TelegramExport.mediaLabel(["file": "a", "media_type": "video_file"]), "Video", "video file")
eq(TelegramExport.mediaLabel(["file": "a", "media_type": "audio_file"]), "Audio", "audio file")
eq(TelegramExport.mediaLabel(["file": "a", "file_name": "quarterly.pdf"]), "quarterly.pdf",
   "a generic document answers with its own name")
eq(TelegramExport.mediaLabel(["file": "a"]), "File", "an unnamed document")
check(TelegramExport.mediaLabel(["text": "hi"]) == nil, "no media, no label")

// MARK: - 8. plainText, the three shapes plus nesting (schema fact 5)

eq(TelegramExport.plainText(""), "", "empty string")
eq(TelegramExport.plainText("bare"), "bare", "bare string")
eq(TelegramExport.plainText(["a ", ["type": "bold", "text": "b"], " c"]), "a b c", "mixed array")
eq(TelegramExport.plainText(["type": "code", "text": "x"]), "x", "lone entity object")
eq(TelegramExport.plainText(nil), "", "nil")
eq(TelegramExport.plainText(42), "", "a shape we do not know is empty, never a crash")
eq(TelegramExport.plainText([["type": "unknown", "text": "u"]]), "u",
   "the really-emitted `unknown` type still yields its text")
// text_entities wins, and `plain` is the spelling.
eq(TelegramExport.body(of: ["text": "old", "text_entities": [["type": "plain", "text": "new"]]]),
   "new", "text_entities is preferred")
eq(TelegramExport.body(of: ["text": "only", "text_entities": [Any]()]),
   "only", "an empty text_entities falls back rather than losing the words")

// MARK: - 9. Type gate — unsupported carries nothing at all (schema fact 3)

var counts = TelegramExport.Counts()
check(TelegramExport.entry(from: ["id": 3, "type": "unsupported"], counts: &counts) == nil,
      "an unsupported message never lands")
eq(counts.unsupported, 1, "counted")
check(TelegramExport.entry(from: ["id": 4, "type": "service", "date_unixtime": "1596319440",
                                  "actor": "Ada", "action": "pin_message"], counts: &counts) == nil,
      "a service message never lands")
eq(counts.service, 1, "counted")
check(TelegramExport.entry(from: ["id": 5, "type": "message", "text": "no date"],
                           counts: &counts) == nil,
      "an undated message is skipped, never stamped now")
eq(counts.undated, 1, "counted")
check(TelegramExport.entry(from: ["type": "message", "date_unixtime": "1", "text": "no id"],
                           counts: &counts) == nil, "no id, no ref, no landing")
eq(counts.malformed, 1, "counted")
check(TelegramExport.entry(from: ["id": 9, "type": "wormhole", "date_unixtime": "1", "text": "x"],
                           counts: &counts) == nil, "an unknown type is refused")

// MARK: - 10. ChatKind

eq(TelegramExport.ChatKind(rawType: "saved_messages"), .savedMessages, "saved")
eq(TelegramExport.ChatKind(rawType: "personal_chat"), .personal, "personal")
eq(TelegramExport.ChatKind(rawType: "bot_chat"), .bot, "bot")
for raw in ["private_group", "private_supergroup", "public_supergroup"] {
    eq(TelegramExport.ChatKind(rawType: raw), .group, "\(raw) folds to group")
}
for raw in ["private_channel", "public_channel"] {
    eq(TelegramExport.ChatKind(rawType: raw), .channel, "\(raw) folds to channel")
}
for raw in ["replies", "verification_codes", "something_new", nil] {
    eq(TelegramExport.ChatKind(rawType: raw), .other, "\(raw ?? "nil") is other")
}
check(TelegramExport.ChatKind.savedMessages.landsPerMessage, "saved lands per message")
check(TelegramExport.ChatKind.channel.landsPerMessage, "channel lands per message")
check(!TelegramExport.ChatKind.personal.landsPerMessage, "a DM lands as one thing")

// MARK: - 11. Names, ids, self identity

eq(TelegramExport.displayName(of: ["type": "saved_messages", "id": 1], kind: .savedMessages),
   "Saved Messages", "the absent name has a real answer")
eq(TelegramExport.displayName(of: ["name": NSNull(), "id": 7], kind: .personal), "Chat 7",
   "a null name falls back to the id")
eq(TelegramExport.displayName(of: ["name": " Bob ", "id": 7], kind: .personal), "Bob", "trimmed")
eq(TelegramExport.normalizeFromID("user111"), "user111", "modern from_id")
eq(TelegramExport.normalizeFromID(111), "user111", "legacy numeric from_id")
eq(TelegramExport.normalizeFromID("111"), "user111", "quoted numeric from_id")
check(TelegramExport.normalizeFromID(nil) == nil, "absent from_id")
let me = TelegramExport.selfIdentity(in: modernRoot)
eq(me.id, "user111", "self id read off personal_information")
eq(me.name, "Ada L", "self name joined")
check(!TelegramExport.selfIdentity(in: legacyRoot).isKnown,
      "a single-chat export names nobody, so the heuristic must carry it")

// MARK: - 12. Caps are counted, never silent (prd §307/§309)

eq(TelegramExport.savedCap, 20_000, "saved cap")
eq(TelegramExport.conversationCap, 5_000, "conversation cap")
eq(TelegramExport.channelPostCap, 10_000, "channel post cap")
var many = "{\"type\":\"saved_messages\",\"id\":1,\"messages\":["
many += (0..<25).map {
    "{\"id\":\($0),\"type\":\"message\",\"date_unixtime\":\"\(1_500_000_000 + $0)\",\"text\":\"m\($0)\"}"
}.joined(separator: ",")
many += "]}"
if let manyRoot = TelegramExport.decode(Data(many.utf8)) {
    // Re-check the cap arithmetic against a fixture the shipped cap cannot
    // reach, by asserting the refusal is reported at all when nothing is cut.
    let parsed = TelegramExport.parse(manyRoot, includeMessages: false)
    eq(parsed.savedMessages.count, 25, "everything under the cap lands")
    eq(parsed.counts.savedDropped, 0, "nothing refused")
    eq(parsed.counts.dropped, 0, "the receipt number is zero")
    eq(parsed.savedMessages.first?.id, 24, "newest first, so a cap would refuse the oldest")
}

// MARK: - 13. The clamps, on a conversation big enough to reach them

// FIXTURE 4 OF THE FOUR. A three-message fixture cannot fail `lineCap`,
// `transcriptCap` or "total is counted BEFORE the clamp" — every one of those
// mutations survives it, because 3 < 60 and the transcript is far under its
// ceiling. This one is deliberately past all three, and the last assertion
// pins the premise: `total` and `lines.count` must really DIFFER here, or the
// split it exists to prove is untestable again.
let longBody = String(repeating: "word ", count: 24)
var bigChat = "{\"name\":\"Dee\",\"type\":\"personal_chat\",\"id\":777,\"messages\":["
bigChat += (0..<70).map { i in
    "{\"id\":\(i),\"type\":\"message\",\"date_unixtime\":\"\(1_600_000_000 + i * 60)\","
        + "\"from\":\"Dee\",\"from_id\":\"user777\",\"text\":\"m\(i) \(longBody)\"}"
}.joined(separator: ",")
bigChat += "]}"
if let bigRoot = TelegramExport.decode(Data(bigChat.utf8)) {
    let big = TelegramExport.parse(bigRoot, includeMessages: true)
    if let convo = big.conversations.first {
        eq(convo.total, 70, "total counts every message, BEFORE the line clamp")
        eq(convo.lines.count, TelegramExport.lineCap, "lines are clamped to lineCap")
        check(convo.lines.first?.contains("m10 ") == true,
              "the clamp keeps the NEWEST lines, dropping the oldest ten")
        check(convo.lines.last?.contains("m69 ") == true, "…and ends on the newest")
        eq(convo.transcript.count, TelegramExport.transcriptCap,
           "the joined transcript is clamped to its byte ceiling")
        check(convo.total != convo.lines.count,
              "the two numbers really differ here, so the split is testable")
    }
}

print("")
if failures > 0 {
    print("\(failures) of \(checks) assertions failed")
    exit(1)
}
print("all \(checks) assertions passed")
SWIFT

echo "telegram-export-selftest: compiling the parser WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$EXPORT" "$TMP/main.swift" \
  || { echo "✗ TelegramExport does not compile Foundation-only — something reached Thing/SwiftUI/IngestSupport"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a SILENT WRONG ANSWER that renders as an ordinary
# room. A mutation that survives means nothing above was testing that line, and
# the assertion should be rewritten rather than shipped — which is exactly how
# the four fixtures marked above earned their shape.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" frm="$2" to="$3"
  cp "$EXPORT" "$TMP/TelegramExport.swift"
  # The python exit is tested INLINE, not through `$?` on the next line: this
  # script runs under `set -e`, so a failed edit would kill the run before the
  # check could report it — a mutation that never applied would read as the
  # whole harness dying with no message at all.
  #
  # It also refuses an AMBIGUOUS pattern rather than replacing the first of
  # several: a mutation that silently lands somewhere other than the line it
  # names proves something, but not the thing its own comment claims.
  local applied=1
  FRM="$frm" TO="$to" python3 - "$TMP/TelegramExport.swift" <<'PY' && applied=0
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if src.count(frm) != 1:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if (( applied != 0 )) || ! grep -qF -- "$to" "$TMP/TelegramExport.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved, or the pattern is no longer unique)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$TMP/TelegramExport.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# SCHEMA FACT 1, and the most dangerous line in the file: getting the run parity
# backwards CORRUPTS somebody's text rather than failing to repair it. `\\x41`
# is an escaped backslash followed by the literal characters x41 — their words —
# and rewriting it silently produces a different string.
mutate "backslash run parity inverted" \
  'if run % 2 == 1,' \
  'if run % 2 == 0,'

# SCHEMA FACT 2. A full export's chats each carry `messages` too, so sniffing on
# that key reads the FIRST chat and throws every other one away — an import that
# lands real rows, reports success, and silently loses the rest.
mutate "the single-chat fork sniffs \`messages\` instead of \`chats\`" \
  'if dict["chats"] != nil {' \
  'if dict["messages"] != nil {'

# SCHEMA FACT 6. The placeholder sentence can be PREFIXED by the file's own
# name, so an equality test resolves it to a "path" the landing half then tries
# to open — every skipped file becoming a broken attachment.
mutate "media placeholders matched by equality" \
  'for placeholder in mediaPlaceholders where text.contains(placeholder) { return nil }' \
  'for placeholder in mediaPlaceholders where text == placeholder { return nil }'

# SCHEMA FACT 4, the expensive one. `date` is ISO local time with no offset in a
# zone the export records nowhere; `date_unixtime` is the only exact reading
# there is. Caught only because fixture 1's two stamps are 21 years apart.
mutate "date_unixtime ignored, naive date trusted" \
  'instant(unix: message["date_unixtime"], naive: message["date"])' \
  'instant(unix: nil, naive: message["date"])'

# SCHEMA FACT 3, half one. A service message has no `from` at all — it has
# `actor`/`action`, because it is Telegram narrating itself — so landing it
# files "somebody joined" as a message somebody wrote.
mutate "service messages land" \
  '        case "service":
            counts.service += 1' \
  '        case "service_never":
            counts.service += 1'

# SCHEMA FACT 3, half two. An `unsupported` message is `{id, type}` and nothing
# else: no date, no from, no text. Landing it files an undated blank.
mutate "unsupported messages land" \
  '        case "message":
            break' \
  '        case "message", "unsupported":
            break'

# SCHEMA FACT 5. `text_entities` is lossless and monomorphic; `text` is
# polymorphic and lossy. Preferring the wrong one loses the words of every
# message written as a phrase-with-a-link.
mutate "text_entities no longer preferred" \
  'let entities = tidy(plainText(message["text_entities"]))' \
  'let entities = tidy(plainText(message["nope"]))'

# THE CHECKBOX BUG. An export made with file downloading switched off says
# "(File not included…)" for every photograph, voice note and sticker — so
# gating the LABEL on the resolved PATH deletes the shape of somebody's whole
# chat history because of a setting in the exporter.
mutate "mediaLabel gated on the resolved path" \
  'if message["photo"] != nil { return "Photo" }' \
  'if mediaPath(message["photo"]) != nil { return "Photo" }'

# Attribution, both ways. Caught only because fixture 2's group message names
# "Ada Lovelace" where `personal_information` says "Ada L": the name heuristic
# cannot answer inside a group, so the id comparison is all there is.
mutate "the self-ID comparison dropped" \
  'if let mine = me.id, let from = normalizeFromID(message["from_id"]) {' \
  'if let mine = me.id, let from = normalizeFromID(message["nope"]) {'

mutate "the self-ID comparison inverted" \
  '            return from == mine' \
  '            return from != mine'

# …and the fallback the legacy export depends on entirely: a pre-2021 export
# names nobody in `personal_information`, so a 1:1 chat's own name is the only
# thing that can say which side is yours.
mutate "the personal-chat name heuristic dropped" \
  '        return from != name' \
  '        return false'

# Newest first is what makes the caps refuse the OLDEST rather than whatever
# the export happened to list last — a truncated import losing this year.
mutate "saved messages sorted oldest first" \
  'saved.sort { $0.date > $1.date }' \
  'saved.sort { $0.date < $1.date }'

mutate "channel posts sorted oldest first" \
  'entries.sort { $0.date > $1.date }' \
  'entries.sort { $0.date < $1.date }'

# `Conversation.total` is the only moment the true message count exists —
# nothing downstream can recover it from a stored transcript. Counted after the
# clamp, a decade-long friendship and a week-old chat both read as 60.
mutate "total counted AFTER the line clamp" \
  'total: ordered.count' \
  'total: Array(ordered.suffix(lineCap)).count'

mutate "the line clamp keeps the OLDEST lines" \
  'lines: Array(ordered.suffix(lineCap).map(\.line)),' \
  'lines: Array(ordered.prefix(lineCap).map(\.line)),'

mutate "the transcript ceiling doubled" \
  'prefix(TelegramExport.transcriptCap)' \
  'prefix(TelegramExport.transcriptCap * 2)'

# A `text_link` is words standing in for a destination, so its URL is in `href`
# and never in its text. Reading the text collects the words and loses every
# link that was ever written as a phrase — which for a pile of forwarded links
# is the entire point of the room.
mutate "a text_link yields its words instead of its href" \
  'if let href = entity["href"] as? String { consider(href) }' \
  'if let href = entity["text"] as? String { consider(href) }'

# Caught only by fixture 3: a message carrying a text_link AND a bare link, so
# the bare-URL fallback cannot rescue it.
mutate "bare \`link\` entities no longer collected" \
  '                case "link":' \
  '                case "link_never":'

# `.other` is never landed, and `verification_codes` is why: its entire content
# is one-time login secrets. Defaulting to a landable kind walks a pile of live
# credentials into the corpus, into Spotlight, and into a keyed agent's context.
mutate "an unknown chat type lands instead of being refused" \
  '            default: self = .other' \
  '            default: self = .savedMessages'

# Entity runs are contiguous fragments of one sentence — joined with a space,
# every message gains gaps where its own formatting was.
mutate "plainText joins runs with a space" \
  'return parts.map(plainText).joined()' \
  'return parts.map(plainText).joined(separator: " ")'

# A skipped message is recoverable by re-importing a better export; a message
# stamped `.now` files somebody's 2016 as today's news, and nothing downstream
# can ever tell that it did.
mutate "an undated message is stamped now" \
  '        guard let date = timestamp(message) else {
            counts.undated += 1
            return nil
        }' \
  '        let date = timestamp(message) ?? Date()'

# A wordless message is a photograph, a voice note, a sticker — most of what a
# chat history IS. Dropping them leaves a year of voice notes reading as a chat
# that never happened.
mutate "a wordless media message is dropped" \
  '        guard !text.isEmpty || label != nil else {' \
  '        guard !text.isEmpty else {'

# A poll has no `text` of its own — its words live under `poll`, so a parser
# that only reads `text` drops every poll as empty.
mutate "the poll body is never read" \
  '        if text.isEmpty, let poll = pollText(message["poll"]) {' \
  '        if false, let poll = pollText(message["poll"]) {'

# `left_chats` holds every group somebody has left — years of history, absent
# with no error and no count anywhere.
mutate "left_chats dropped" \
  'return list(in: dict["chats"]) + list(in: dict["left_chats"])' \
  'return list(in: dict["chats"])'

# Pre-2021 exports write `from_id` as a bare NUMBER. Refusing it makes every
# old export's messages read as somebody else's — in exactly the case where
# "You" matters most.
mutate "a numeric from_id is refused" \
  '        if let number = intValue(raw) { return "user\(number)" }' \
  '        if let number = intValue(raw), false { return "user\(number)" }'

# The answers are the poll's content; only the vote tallies are refused (module
# doctrine). Folding the answers away leaves a question nobody answered.
mutate "poll answers folded away" \
  'lines += answers.map { "· \($0)" }' \
  'lines += [String]()'

echo ""
echo "telegram-export-selftest: OK"
