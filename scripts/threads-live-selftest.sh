#!/bin/zsh
# Casberi Threads live self-test (prd §1131) — the pure half of the Activity
# door, compiled WHOLE and unmodified:
#
#   Casberi/Casberi/Model/ThreadsLiveFeed.swift
#
# Every failure here is silent on a device:
#
#   · a read that sent the page's MarkInboxAsSeen mutation would clear the
#     unread badge on the person's own phone, and nothing in the app shows it
#   · a stale query id read as a refusal would sign the person out every time
#     Threads ships a web deploy; read as a drift, the feed would go quiet
#     forever instead of finding the id again
#   · a query answered with an HTML page (no page token) read as JSON is
#     "unexpected shape", never "fetch the token again"
#   · a sign-out visit's cookie jar (mid, csrftoken) stored as a session
#   · a query without the browser's Sec-Fetch-* headers answers with a page,
#     every time, from a native client (measured on the simulator)
#
# The fixtures are the MEASURED shapes (2026-10-05), values replaced. The
# measured account held only Threads' own notices; the follow fixture is the
# parser's defensive reading, not Threads.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

FEED="Casberi/Casberi/Model/ThreadsLiveFeed.swift"
LIVE="Casberi/Casberi/Model/ThreadsLive.swift"
SCOPE="Casberi/Casberi/Model/SocialScope.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
for f in "$FEED" "$LIVE" "$SCOPE" "$REACH"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

grep -qF 'static let refPrefix = "threads-live:notif:"' "$FEED" \
  || { echo "✗ ThreadsLiveFeed.refPrefix moved — it must be the literal \"threads-live:notif:\""; exit 1; }
grep -qF 'ref.hasPrefix("threads-live:notif:")' "$SCOPE" \
  || { echo "✗ SocialScope.isToYou no longer knows a Threads notice is to you"; exit 1; }
grep -qE 'if case \.refused = failure \{ ThreadsLiveAuth\.clear\(\) \}' "$LIVE" \
  || { echo "✗ ThreadsLive.refresh no longer clears the session on a refusal (and only a refusal) — §711"; exit 1; }
[[ $(grep -c 'ThreadsLiveAuth.clear()' "$LIVE") == 1 ]] \
  || { echo "✗ ThreadsLive clears the session somewhere other than a refusal — §711"; exit 1; }
grep -qF 'Endpoint(service: "Threads live",' "$REACH" \
  || { echo "✗ NetworkReach has no \"Threads live\" entry — the receipts would name an undisclosed service"; exit 1; }
[[ $(grep -c 'service: "Threads live"' "$LIVE") == 2 ]] \
  || { echo "✗ a Threads request is recorded under a service other than \"Threads live\""; exit 1; }
grep -qF '"Sec-Fetch-Site": "same-origin", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Dest": "empty"' "$LIVE" \
  && grep -qF 'for (field, value) in fetchMetadata' "$LIVE" \
  || { echo "✗ the query no longer sends Sec-Fetch-* — measured: without them Threads answers every query with a page"; exit 1; }
# Code lines only: the feed file's header names the mutation it never sends.
if cat "$FEED" "$LIVE" | grep -vE '^[[:space:]]*//' | grep -qE 'MarkInboxAsSeen|27685991674412591'; then
  echo "✗ a read sends the mark-seen mutation — the person's own unread badge would clear"; exit 1
fi
echo "threads-live-selftest: drift guards ✓"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
func failure(_ r: Result<[String: Any], ThreadsLiveFeed.Failure>) -> ThreadsLiveFeed.Failure? {
    if case .failure(let f) = r { return f } else { return nil }
}

// ── The session ──────────────────────────────────────────────────────────
check(ThreadsLiveFeed.cookieHeader([("mid", "a"), ("csrftoken", "b")]) == nil,
      "a signed-out jar is not a session")
check(ThreadsLiveFeed.cookieHeader([("sessionid", "s"), ("csrftoken", "b")]) == nil,
      "sessionid without ds_user_id is not a session")
check(ThreadsLiveFeed.cookieHeader([("mid", "a"), ("sessionid", "s"), ("ds_user_id", "9"), ("sessionid", "x")])
      == "mid=a; sessionid=s; ds_user_id=9", "a signed-in jar is one header, first value of each name")

// ── The page ─────────────────────────────────────────────────────────────
let page = #"""
<html><script>["DTSGInitialData",[],{"token":"NAc-TOKEN_84:12:3"},258]</script>
<script>{"viewer":{"id":"1","is_verified":false,"username":"some.one_2"}}</script>
<script src="https://static.cdninstagram.com/rsrc.php/v4/yx/r/AAA.js" async></script>
<link href="https://static.cdninstagram.com/rsrc.php/v4ig/yC/l/en_US-j/BBB.js?_nc_x=1" rel="preload">
<script src="https://static.cdninstagram.com/rsrc.php/v4/yx/r/AAA.js"></script>
<img src="https://static.cdninstagram.com/rsrc.php/yz/r/icon.ico">
"""#
check(ThreadsLiveFeed.dtsg(inPage: page) == "NAc-TOKEN_84:12:3", "the page token is read off DTSGInitialData")
check(ThreadsLiveFeed.dtsg(inPage: "<html></html>") == nil, "a page with no token has none")
check(ThreadsLiveFeed.viewerUsername(inPage: page) == "some.one_2", "the viewer's handle is read off the page")
let scripts = ThreadsLiveFeed.scriptURLs(inPage: page)
check(scripts == ["https://static.cdninstagram.com/rsrc.php/v4/yx/r/AAA.js",
                  "https://static.cdninstagram.com/rsrc.php/v4ig/yC/l/en_US-j/BBB.js?_nc_x=1"],
      "the page's scripts, once each, in order, no icons")
check(ThreadsLiveFeed.isLoginPage(path: "/login") && ThreadsLiveFeed.isLoginPage(path: "/login/")
      && !ThreadsLiveFeed.isLoginPage(path: "/activity") && !ThreadsLiveFeed.isLoginPage(path: nil),
      "only a page that ended at /login is a refusal")

// The measured module shape, and a neighbour that must not be mistaken for it.
let script = #"__d("BarcelonaActivityFeedV2StoryListContainerQuery_facebookRelayOperation",[],(function(t,n,r,o,a,i){a.exports="111111111"}),null);"#
    + "\n" + #"__d("BarcelonaActivityFeedV2StoryListContainerQuery_threadsRelayOperation",[],(function(t,n,r,o,a,i){a.exports="38749413951373454"}),null);"#
check(ThreadsLiveFeed.docID(inScript: script) == "38749413951373454", "the query id is found by its module name")
check(ThreadsLiveFeed.docID(inScript: "__d(\"Other_threadsRelayOperation\",[],(function(t){a.exports=\"5\"}))") == nil,
      "another query's id is never taken")

// ── The query ────────────────────────────────────────────────────────────
let form = ThreadsLiveFeed.formBody(docID: "38749413951373454", dtsg: "a+b:c")
let fields = Dictionary(uniqueKeysWithValues: form.split(separator: "&").map {
    let kv = $0.split(separator: "=", maxSplits: 1).map(String.init)
    return (kv[0], kv.count > 1 ? kv[1].removingPercentEncoding ?? "" : "")
})
check(fields["doc_id"] == "38749413951373454" && fields["fb_dtsg"] == "a+b:c", "the form carries the id and the token, round-tripped")
check(!form.contains("a+b") && form.contains("a%2Bb"), "a + in the token is encoded, never read as a space")
check(fields["variables"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any] != nil,
      "the variables are JSON")
check(fields["lsd"] == nil && fields["av"] == nil, "nothing the query was measured not to need")

check(failure(ThreadsLiveFeed.classify(status: 200, body: #"{"errors":[{"message":"The GraphQL document with ID 1 was not found.","severity":"CRITICAL"}],"extensions":{"is_final":true}}"#)) == .staleQuery,
      "an unknown query id is stale, not a refusal")
check(failure(ThreadsLiveFeed.classify(status: 200, body: "<!DOCTYPE html><html class=\"_9dls\">")) == .tokenRejected,
      "a page in place of JSON is a refused token")
check(failure(ThreadsLiveFeed.classify(status: 401, body: nil)) == .refused(401), "a 401 is a refusal")
check(failure(ThreadsLiveFeed.classify(status: 429, body: nil)) == .throttled, "a 429 is a throttle")
check(failure(ThreadsLiveFeed.classify(status: 0, body: nil)) == .unreachable, "no response is unreachable")
check(failure(ThreadsLiveFeed.classify(status: 200, body: #"{"data":{}}"#)) == .drifted, "a feed with no notifications drifted")
check(failure(ThreadsLiveFeed.classify(status: 200, body: #"for (;;);{"data":{"notifications":{"edges":[]}}}"#)) == nil,
      "the for(;;) guard is stripped")

// ── Notices (MEASURED shapes, values replaced) ───────────────────────────
let body = #"""
{"data":{"notifications":{"edges":[
 {"node":{"__typename":"XTHNotifFeedBucketHeader"}},
 {"node":{"__typename":"XTHNotificationFeedRow","edge_id":"17800000000000001","ndid":"65d1",
   "notif_name":"threads_app_daily_digest","story_type":21341,"timestamp":1791260028,
   "title":{"text":"ana","ranges":[{"offset":0,"length":3,"entity":{"__typename":"XTHUser","username":"ana"}}]},
   "subtitle":{"text":"Because you follow","ranges":[]},"body":{"text":"Being a plus 1.","ranges":[]},
   "sender_users":{"edges":[{"node":{"__typename":"XTHUser","id":"7","username":"ana","profile_picture_uri":"https://scontent.cdninstagram.com/ana.jpg"}}]},
   "image_list":["https://scontent.cdninstagram.com/p1.jpg","https://scontent.cdninstagram.com/p2.jpg"],
   "inline_follow_actor":null,
   "ufi_media":{"code":"DPabcdefGHI","id":"1","pk":"1","like_count":4,"user":{"pk":"7","id":"7","username":"ana"}}}},
 {"node":{"__typename":"XTHNotificationFeedRow","edge_id":"17900000000000002","notif_name":"text_post_app_insights",
   "timestamp":1790559937,"title":{"text":"Your thread got 12 views","ranges":[]},
   "subtitle":{"text":"See your insights","ranges":[]},
   "sender_users":{"edges":[]},"image_list":["https://scontent.cdninstagram.com/p3.jpg"],
   "ufi_media":{"code":"DPzyxwvuTSR","user":{"username":"me"}}}},
 {"node":{"__typename":"XTHNotificationFeedRow","edge_id":"17800000000000003","notif_name":"text_post_app_unified_settings_link",
   "timestamp":1788898867,"title":{"text":"Try the new settings","ranges":[]},
   "sender_users":{"edges":[]},"image_list":[],"ufi_media":null}},
 {"node":{"__typename":"XTHNotificationFeedRow","edge_id":"17800000000000004","notif_name":"follow",
   "timestamp":1788898900,"title":{"text":"cy followed you","ranges":[]},
   "sender_users":{"edges":[{"node":{"username":"cy"}}]},"image_list":[],
   "inline_follow_actor":{"username":"cy"},"ufi_media":null}}
]}}}
"""#
guard case .success(let feed) = ThreadsLiveFeed.classify(status: 200, body: body) else {
    print("  ✗ the measured feed does not classify"); exit(1)
}
let notices = ThreadsLiveFeed.notices(feed)
check(notices.count == 3, "the header and the settings link land nothing; three notices do")
let digest = notices.first
check(digest?.id == "17800000000000001" && digest?.text == "Being a plus 1.", "a title that is only a name gives way to the post's words")
check(digest?.detail == "Because you follow", "and Threads' reason is the second line")
check(digest?.isSuggestion == true, "a daily digest is a suggestion, not something done to you")
check(digest?.actorHandle == "ana" && digest?.actorAvatar == "https://scontent.cdninstagram.com/ana.jpg", "who acted is the face")
check(digest?.permalink == "https://www.threads.com/@ana/post/DPabcdefGHI", "a notice opens the post it is about")
check(digest?.image == "https://scontent.cdninstagram.com/p1.jpg", "the first picture is the notice's")
check(digest?.at == Date(timeIntervalSince1970: 1791260028), "the timestamp is the notice's date")
check(digest?.isFollow == false, "a notice with a post is not a follow")
let insight = notices.dropFirst().first
check(insight?.text == "Your thread got 12 views" && insight?.detail == "See your insights", "a sentence title leads; the line under it follows")
check(insight?.isSuggestion == false, "an insight is not a suggestion")
check(insight?.permalink == "https://www.threads.com/@me/post/DPzyxwvuTSR", "and opens your post")
let follow = notices.last
check(follow?.text == "cy followed you", "a follow keeps Threads' sentence")
check(follow?.isFollow == true && follow?.permalink == "https://www.threads.com/@cy", "a follow opens the follower")

print(failures == 0 ? "threads-live-selftest: all checks ✓" : "threads-live-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -O -o "$TMP/run" "$FEED" "$TMP/main.swift" 2>&1 | grep -v "^$" || true
[[ -x "$TMP/run" ]] || { echo "✗ threads-live-selftest: compile failed"; exit 1; }
"$TMP/run"
