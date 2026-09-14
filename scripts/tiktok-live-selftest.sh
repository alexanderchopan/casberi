#!/bin/zsh
# Casberi TikTok live self-test (prd §731) — the pure half of the Activity-inbox
# door, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/TikTokLiveNotice.swift
#
# Every failure here is silent on a device:
#
#   · a read that sends is_mark_read=1 clears the unread badge on the person's
#     own phone, and nothing in the app would ever show it
#   · a dead session is a 200 whose BODY says "Login expired" (status_code 8,
#     measured) — classified by HTTP status alone it reads as an empty inbox,
#     the cookies are never cleared, and the page says "signed in" forever
#   · a sign-out visit's cookie jar stored as a session
#   · a ref prefix outside `tiktok:` hides from ImportRemoval.hasLiveHalf, so
#     "Remove import" deletes every notice
#   · a ref prefix missing from Corpus.liveRefPrefixes keeps every notice out
#     of All — the Instagram live door's state as of this writing
#
# The system-notice fixtures are the MEASURED shapes (2026-09-14). The like,
# comment and follow fixtures are the payload names TikTok's notice model uses
# and are NOT measured — they pin the parser's defensive reading, not TikTok.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED="Casberi/Casberi/Model/TikTokLiveNotice.swift"
LIVE="Casberi/Casberi/Model/TikTokLive.swift"
THING="Casberi/Shared/Thing.swift"
for f in "$FEED" "$LIVE" "$THING"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

grep -qF 'static let refPrefix = "tiktok:live:notif:"' "$FEED" \
  || { echo "✗ TikTokLiveFeed.refPrefix moved — it must be the literal \"tiktok:live:notif:\""; exit 1; }
grep -qF '"tiktok:live:notif:"' "$THING" \
  || { echo "✗ \"tiktok:live:notif:\" is not in Corpus.liveRefPrefixes — notices land and never reach the All feed"; exit 1; }
grep -qE 'if case \.refused = failure \{ TikTokLiveAuth\.clear\(\) \}' "$LIVE" \
  || { echo "✗ TikTokLive.refresh no longer clears the session on a refusal (and only a refusal) — §711"; exit 1; }
# Code lines only: the file's own header quotes the page's `is_mark_read: 1`.
if cat "$FEED" "$LIVE" | grep -vE '^[[:space:]]*//' | grep -qE 'is_mark_read\\?"?:? *1|is_mark_read=1'; then
  echo "✗ a read marks the inbox read — the person's own unread badge would clear"; exit 1
fi
echo "tiktok-live-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func json(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8)) }

// ── The request ──────────────────────────────────────────────────────────
let url = TikTokLiveFeed.inboxURL()
let query = URLComponents(string: url)?.queryItems ?? []
let groups = query.first { $0.name == "group_list" }?.value ?? ""
check(url.hasPrefix("https://www.tiktok.com/api/notice/multi/?"), "inbox reads the panel's own path")
check(groups.contains("\"is_mark_read\":0"), "is_mark_read is 0")
check(!groups.contains("\"is_mark_read\":1"), "is_mark_read is never 1")
check(groups.contains("\"group\":500"), "the panel's group, 500")
check(!url.contains("X-Bogus") && !url.contains("X-Gnarly") && !url.contains("msToken"), "no signature parameters")
check(TikTokLiveFeed.inboxURL(group: 661, path: "/api/inbox/notice_list/").contains("%22group%22%3A661"), "group and path are parameters")

// ── The session ──────────────────────────────────────────────────────────
check(TikTokLiveFeed.cookieHeader([("ttwid", "a"), ("msToken", "b")]) == nil, "a signed-out jar is not a session")
check(TikTokLiveFeed.cookieHeader([("sessionid", ""), ("ttwid", "a")]) == nil, "an empty sessionid is not a session")
check(TikTokLiveFeed.cookieHeader([("ttwid", "a"), ("sessionid", "s"), ("sessionid", "t")]) == "ttwid=a; sessionid=s",
      "the whole jar, first of each name, once sessionid is in it")

// ── Classification (measured bodies) ─────────────────────────────────────
let signedInEmpty = json(#"{"extra":{"fatal_item_ids":[],"logid":"x","now":1},"log_pb":{},"notice_lists":[],"status_code":0,"status_msg":""}"#)
let expired = json(#"{"log_pb":{},"status_code":8,"status_msg":"Login expired"}"#)
check(TikTokLiveFeed.classify(status: 200, json: signedInEmpty) == nil, "signed-in and empty is a clean read")
check(TikTokLiveFeed.classify(status: 200, json: expired) == .refused(200), "status_code 8 in a 200 is a refusal")
check(TikTokLiveFeed.classify(status: 200, json: json(#"{"status_code":5,"status_msg":"?"}"#)) == .drifted, "an unknown code is drift, never a refusal")
check(TikTokLiveFeed.classify(status: 200, json: json(#"{"status_code":0}"#)) == .drifted, "a 0 with no lists is drift")
check(TikTokLiveFeed.classify(status: 401, json: nil) == .refused(401), "401 refuses")
check(TikTokLiveFeed.classify(status: 429, json: nil) == .throttled, "429 throttles, never refuses")
check(TikTokLiveFeed.classify(status: 0, json: nil) == .unreachable, "no response is unreachable")
check(TikTokLiveFeed.notices(signedInEmpty)?.isEmpty == true, "an empty inbox parses to nothing, not nil")
check(TikTokLiveFeed.notices(expired) == nil, "an expired body parses to nil")

check(TikTokLiveFeed.username(json(#"{"message":"success","data":{"user_id":1,"username":"someone"}}"#)) == "someone", "the passport's username")
check(TikTokLiveFeed.username(json(#"{"message":"error","data":{"error_code":13,"name":"session_expired"}}"#)) == nil, "a signed-out passport names nobody")

// ── System notices (measured payload names) ──────────────────────────────
let system = json(#"""
{"status_code":0,"notice_lists":[{"group":661,"has_more":0,"max_time":1,"min_time":1,"notice_list":[
 {"nid":7400000000000009000,"type":2,"display_type":2,"has_read":false,"create_time":1788000000,
  "template_notice":{"notice":{"title":"Community Guidelines update","content":"We will be updating our Community Guidelines."}}},
 {"nid":"7400000000000004000","type":1,"create_time":1788000001,
  "announcement":{"title":"LIVE","content":"LIVE rewards payout update","schema_url":"snssdk1233://live","type":1}},
 {"nid":7400000000000001000,"type":9,"create_time":1788000002,"mystery":{"flag":true}}
]}]}
"""#)
let sys = TikTokLiveFeed.notices(system) ?? []
check(sys.count == 2, "two system notices parse, the wordless unknown payload does not")
check(sys.first?.kind == "template_notice" && sys.first?.text == "We will be updating our Community Guidelines.", "a template notice leads with its content")
check(sys.first?.id == "7400000000000009000", "a numeric nid keeps every digit")
check(sys.last?.permalink == "https://www.tiktok.com/", "an app-scheme link is never a permalink")
check(sys.first?.at == Date(timeIntervalSince1970: 1788000000), "create_time is the notice's date")

// ── Social notices (UNMEASURED payload names) ────────────────────────────
let social = json(#"""
{"status_code":0,"notice_lists":[{"group":500,"notice_list":[
 {"nid_str":"1","type":41,"create_time":1788000100,
  "digg":{"from_user":[{"unique_id":"ana","nickname":"Ana","avatar_thumb":{"url_list":["https://p16/ana.jpg"]}}],
          "aweme":{"aweme_id":"730","desc":"my cat","author":{"unique_id":"me"},"video":{"cover":{"url_list":["https://p16/cover.jpg"]}}}}},
 {"nid_str":"2","type":31,"create_time":1788000200,
  "comment":{"comment":{"text":"so good","user":{"unique_id":"bo"},"aweme":{"aweme_id":"731","author":{"unique_id":"me"}}}}},
 {"nid_str":"3","type":33,"create_time":1788000300,
  "follow":{"from_user":[{"unique_id":"cy"}]}},
 {"nid_str":"4","type":45,"create_time":1788000400,"at":{}}
]}]}
"""#)
let soc = TikTokLiveFeed.notices(social) ?? []
check(soc.count == 4, "a like, a comment, a follow and a bare mention parse")
check(soc.first?.text == "Ana liked your video", "a like names who liked")
check(soc.first?.actorHandle == "ana" && soc.first?.actorAvatar == "https://p16/ana.jpg", "the liker is the face")
check(soc.first?.permalink == "https://www.tiktok.com/@me/video/730", "a like opens the video")
check(soc.first?.videoCover == "https://p16/cover.jpg" && soc.first?.videoCaption == "my cat", "the video's cover and words")
check(soc.dropFirst().first?.text == "@bo: so good", "a comment carries its words, under the handle when no name")
check(soc.dropFirst().first?.videoID == "731", "a comment's video is read through the comment")
check(soc.dropFirst(2).first?.isFollow == true && soc.dropFirst(2).first?.permalink == "https://www.tiktok.com/@cy", "a follow opens the follower")
check(soc.last?.text == "Mentioned you" && soc.last?.permalink == "https://www.tiktok.com/", "a mention with nothing under it names no one and guesses no video")

print(failures == 0 ? "tiktok-live-selftest: all checks ✓" : "tiktok-live-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ tiktok-live-selftest: compile failed"; exit 1; }
"$TMP/run"
