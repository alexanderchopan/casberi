#!/bin/zsh
# Casberi Logos Observer self-test — the SHIPPED v2 client logic (2026-10-03):
#
#   Casberi/Casberi/Model/LogosObserverWire.swift
#     — offer(_:)                    (the pairing QR)
#     — pin(p256Point:) / matches    (the SPKI pin, from the key iOS hands us)
#     — canonical / signature / headers (the per-request HMAC)
#     — pairing(_:requested:)        (the activation response)
#     — refusal(status:json:)        (which 401 drops the key)
#     — status(_:) / snapshot(_:)    (omitted vs null, node down is a 200)
#
# The vectors under scripts/fixtures/logos-observer/ are the Observer's OWN
# (github.com/0xterricola/logos-observer, vectors/), copied unmodified: the
# HMAC vector, the sample certificate and its pin, and the sample QR. Every
# failure here looks the same from the phone — each request answered
# `401 bad_signature`, or a pairing that never trusts its Observer:
#
#   • the nonce signed as hex instead of base64url;
#   • the request-target normalised (`%2F` decoded) before signing;
#   • the pin taken over the bare point instead of the DER SPKI;
#   • a failed section (`null`) read as "not granted", or as zero;
#   • any 401 dropping the key, so a skewed clock unpairs the phone.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

WIRE="Casberi/Casberi/Model/LogosObserverWire.swift"
NODE="Casberi/Casberi/Model/LogosWire.swift"
FIX="scripts/fixtures/logos-observer"
for f in "$WIRE" "$NODE" "$FIX/v2-hmac.json" "$FIX/v2-qr.json" "$FIX/v2-spki.json" "$FIX/v2-sample-cert.pem"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
import Security

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if ok { print("  ✓ \(what)") } else { print("  ✗ \(what)"); failures += 1 }
}
let fix = CommandLine.arguments[1]
func json(_ name: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(fix)/\(name)"))) as! [String: Any]
}
func parse(_ s: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed]) }
typealias W = LogosObserverWire

print("HMAC vector")
let h = json("v2-hmac.json")
let key = Data(hexString: h["hmac_key_hex"] as! String)
let nonce = Data(hexString: h["nonce_hex"] as! String)
let canon = W.canonical(method: h["method"] as! String, target: h["request_target"] as! String,
                        timestamp: Int(h["timestamp"] as! String)!, nonce: W.base64urlEncode(nonce),
                        deviceID: h["device_id"] as! String, body: Data())
check(canon == h["canonical"] as! String, "canonical string matches the Observer's byte for byte")
check(W.signature(key: key, canonical: canon) == h["signature_base64url"] as! String, "signature matches")
check(W.base64urlDecode(h["hmac_key_base64url"] as! String) == key, "base64url key decodes to the hex key")
let hdr = W.headers(key: key, deviceID: h["device_id"] as! String, method: "GET",
                    target: h["request_target"] as! String,
                    now: Date(timeIntervalSince1970: TimeInterval(Int(h["timestamp"] as! String)!)), nonce: nonce)
check(hdr["X-Observer-Signature"] == h["signature_base64url"] as? String, "headers() carries the same signature")
check(hdr["X-Observer-Nonce"] == h["nonce_base64url"] as? String, "the nonce header is base64url")
check(hdr["X-Observer-Timestamp"] == h["timestamp"] as? String && hdr["X-Observer-Device"] == h["device_id"] as? String,
      "timestamp and device headers")
let decoded = W.canonical(method: "GET", target: "/v2/status?detail=mining/rewards&limit=10",
                          timestamp: 1791068453, nonce: W.base64urlEncode(nonce), deviceID: "d_test_casberi_01", body: Data())
check(W.signature(key: key, canonical: decoded) != h["signature_base64url"] as! String,
      "a normalised target (%2F decoded) does NOT verify")

print("SPKI pin vector")
let s = json("v2-spki.json")
let pem = try! String(contentsOfFile: "\(fix)/v2-sample-cert.pem", encoding: .utf8)
let b64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
let cert = SecCertificateCreateWithData(nil, Data(base64Encoded: b64)! as CFData)!
let secKey = SecCertificateCopyKey(cert)!
let point = SecKeyCopyExternalRepresentation(secKey, nil)! as Data
check(point.count == 65 && point.first == 0x04, "Security hands back a 65-byte uncompressed P-256 point")
check(W.pin(p256Point: point) == s["expected_pin"] as? String, "pin from the key iOS gives us matches the Observer's")
check(W.matches(pin: s["expected_pin"] as! String, p256Point: point), "matches() accepts the right key")
var other = point; other[64] ^= 0x01
check(!W.matches(pin: s["expected_pin"] as! String, p256Point: other), "matches() refuses a key one bit off")
check(W.pin(spki: point) != s["expected_pin"] as? String, "hashing the bare point (no SPKI prefix) does NOT match")
check(W.pin(p256Point: point.dropFirst()) == nil, "a 64-byte point is not pinned")

print("QR vector")
let q = json("v2-qr.json")
let qrText = q["qr"] as! String
let offer = W.offer(qrText)
check(offer != nil, "the sample QR parses")
if let o = offer {
    check(o.host == "192.168.1.20" && o.port == 8081, "host and port")
    check(o.pin == q["pin"] as? String, "pin")
    check(o.secret == q["bootstrap_secret"] as? String, "secret")
    check(o.name == q["display_name"] as? String, "name")
    check(o.scopes == q["scopes"] as? [String], "scopes, in order")
    check(o.bonjour == "Logos Observer._logos-observer._tcp", "Bonjour name, percent-decoded")
    check(o.expires == Date(timeIntervalSince1970: TimeInterval(q["expires_at"] as! Int)), "expiry")
    check(!o.isExpired(at: Date(timeIntervalSince1970: 1791068752)) && o.isExpired(at: Date(timeIntervalSince1970: 1791068753)),
          "expires at exp, not after")
    check(o.baseURL == "https://192.168.1.20:8081", "base URL")
}
check(qrText.count == q["length"] as! Int, "QR length as stated (\(qrText.count))")
check(W.offer(qrText.replacingOccurrences(of: "v=2", with: "v=1")) == nil, "a v1 QR is refused")
check(W.offer(qrText.replacingOccurrences(of: "rewards.status.read", with: "rewards.claim")) == nil,
      "a QR offering a control scope is refused")
check(W.offer(qrText.replacingOccurrences(of: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", with: "AAEC")) == nil,
      "a short secret is refused")
check(W.offer(qrText.replacingOccurrences(of: "sha256/", with: "sha1/")) == nil, "a non-sha256 pin is refused")
check(W.offer(qrText + "&v=3") == nil, "a repeated key is refused")
check(W.offer(qrText.replacingOccurrences(of: "logos-observer://", with: "https://")) == nil, "another scheme is refused")
check(W.splitHostPort("[fe80::1]:9000").map { "\($0.0)|\($0.1)" } == "fe80::1|9000", "IPv6 host in brackets")
check(W.splitHostPort("observer.local").map { $0.1 } == 8081, "a bare host takes the v2 default port")

print("Pairing response")
let req = W.readScopes
let good = parse(#"{"device_id":"d_1","hmac_key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","granted_scopes":["node.status.read","mining.status.read"]}"#)
check(W.pairing(good, requested: req)?.granted == ["node.status.read", "mining.status.read"], "granted scopes are the truth")
check(W.pairing(good, requested: req)?.key == key, "the key decodes to 32 bytes")
check(W.pairing(parse(#"{"device_id":"d_1","hmac_key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","granted_scopes":["mining.control"]}"#), requested: req) == nil,
      "a granted control scope is refused")
check(W.pairing(parse(#"{"device_id":"d_1","hmac_key":"AAEC","granted_scopes":["node.status.read"]}"#), requested: req) == nil,
      "a short key is refused")
let body = String(data: W.pairBody(secret: "S", deviceName: "Phone", scopes: ["node.status.read"]), encoding: .utf8)!
check(body == #"{"device_name":"Phone","scopes":["node.status.read"],"secret":"S"}"#, "pair body: secret, device_name, scopes")

print("Refusals")
check(W.refusal(status: 401, json: parse(#"{"error":"revoked"}"#))?.dropsCredential == true, "revoked drops the key")
for code in ["clock_skew", "bad_signature", "replay"] {
    check(W.refusal(status: 401, json: parse("{\"error\":\"\(code)\"}"))?.dropsCredential == false, "\(code) keeps the key")
}
check(W.refusal(status: 403, json: parse(#"{"error":"scope"}"#)) == .scope, "403 scope")
check(W.refusal(status: 401, json: nil) == .other && W.refusal(status: 401, json: nil)?.dropsCredential == false,
      "an unreadable 401 keeps the key")
check(W.refusal(status: 200, json: nil) == nil && W.refusal(status: 404, json: nil) == nil, "200 and 404 are not refusals")

print("Status")
let tip = String(repeating: "4d", count: 32)
let full = parse("""
{"v":2,"observed_at":"2026-10-03T14:02:11Z",
 "node":{"reachable":true,"phase":"Following","height":184220,"tip":"\(tip)"},
 "network":{"peers":12},
 "mining":{"is_mining":true,"rewards_enabled":true,"auto_claim":false},
 "rewards":{"claimable_tickets":3,"slots_until_expiry":412,"vouchers":2,"total_claimable":"15.000000"}}
""")
let st = W.status(full)!
check(st.node.value?.height == 184220 && st.node.value?.tip?.count == 64, "node section")
check(st.peers == .value(12) && st.mining.value?.isMining == true, "network and mining")
check(st.rewards.value?.claimable == Decimal(string: "15"), "claimable is a decimal string, read exactly")
check(st.observedAt == Date(timeIntervalSince1970: 1791036131), "observed_at")
let snap = W.snapshot(st)
check(snap.synced && snap.peers == 12 && snap.mining == true && snap.miningPays == true
      && snap.tickets == 3 && snap.vouchers == 2, "maps onto the direct read's NodeSnapshot")

let partial = W.status(parse(#"{"v":2,"node":{"reachable":true,"phase":"Following","height":5,"tip":null},"mining":null}"#))!
check(partial.peers == .notGranted && partial.rewards == .notGranted, "an omitted section is not granted")
check(partial.mining == .failed, "a null section is a failed read")
check(W.snapshot(partial).mining == nil && W.snapshot(partial).peers == nil, "neither becomes false or zero")

let down = W.status(parse(#"{"v":2,"node":{"reachable":false,"phase":null,"height":null,"tip":null},"network":null,"mining":null,"rewards":null}"#))!
check(down.node.value?.reachable == false, "node down is a reading, not an error")
check(W.snapshot(down) == .unreachable, "node down maps to unreachable")
check(W.status(parse(#"{"v":1,"node":{"reachable":true}}"#)) == nil, "a v1 body is refused")

print("The stake (Observer 874b746, prd §1216)")
let staked = W.status(parse("""
{"v":2,"node":{"reachable":true,"phase":"Following","height":9,"tip":"aa"},
 "rewards":{"claimable_tickets":0,"slots_until_expiry":null,"vouchers":0,"total_claimable":"0",
  "mining_balance":"190.909090909","mining_notes":212,
  "consensus":{"pow_eligible_notes":0,"pow_eligible_balance":"0","pow_aging_notes":212,
               "wallet_eligible_notes":1,"wallet_eligible_balance":"190.909090909"}}}
"""))!
let sr = staked.rewards.value!
check(sr.miningBalance == Decimal(string: "190.909090909") && sr.miningNotes == 212, "mining_balance and mining_notes")
check(sr.agingNotes == 212 && sr.eligibleNotes == 1 && sr.eligibleBalance == Decimal(string: "190.909090909"),
      "eligible notes and balance add PoW and wallet; aging is PoW's")
let plain = W.status(parse(#"{"v":2,"node":{"reachable":true,"phase":"Following","height":9,"tip":"aa"},"rewards":{"claimable_tickets":0,"vouchers":0,"total_claimable":"0","mining_balance":"5"}}"#))!.rewards.value!
check(plain.miningBalance == 5 && plain.agingNotes == nil && plain.eligibleNotes == nil,
      "no collector: the consensus counts are not told, never zero")
let half = W.status(parse(#"{"v":2,"node":{"reachable":true,"phase":"Following","height":9,"tip":"aa"},"rewards":{"claimable_tickets":0,"vouchers":0,"consensus":{"pow_eligible_notes":2,"pow_aging_notes":true}}}"#))!.rewards.value!
check(half.eligibleNotes == nil && half.agingNotes == nil, "half a count, or a Bool, is no count")
check(W.snapshot(staked).eligibleNotes == 1 && W.snapshot(staked).stage == .eligible, "the snapshot carries the stake to the stage")

print("Chat (chat.read, prd §1155)")
check(W.scopeLabel("chat.read") == "Your chats" && W.isReadScope("chat.read"), "chat.read is a read scope with its own words")
check(W.chatAvailability(parse(#"{"available":false,"reason":"chat_not_started"}"#)) == .notStarted,
      "chat_not_started says open Chat, not unreachable")
check(W.chatAvailability(parse(#"{"available":true,"conversations":[]}"#)) == .available, "available")
check(W.conversations(parse(#"{"available":false,"reason":"chat_not_started"}"#)) == nil, "no list when chat isn't started")
let convos = W.conversations(parse("""
{"available":true,"conversations":[
 {"id":"old","kind":"group","name":"LEZ testers","last_activity_ms":1000,"history_only":true},
 {"id":"new","kind":"direct","nickname":"Terricola","preview":"hi","last_activity_ms":5000,"message_count":3},
 {"kind":"direct"}]}
"""))!
check(convos.map(\.id) == ["new", "old"], "newest activity first; a conversation with no id is dropped")
let none: (String) -> String? = { _ in nil }
check(convos[0].title(names: none) == "Terricola" && convos[1].title(names: none) == "LEZ testers"
      && convos[0].direct && !convos[1].direct,
      "title is nickname, then name; kind decides direct")
check(convos[1].historyOnly, "history_only survives")
check(W.conversations(parse(#"{"available":true,"conversations":[{"convo_id":"raw","kind":"direct"}]}"#))?.first?.id == "raw",
      "chat_module's own convo_id is read when id is absent")
let msgs = W.messages(parse("""
{"available":true,"messages":[
 {"from_self":false,"sender":"0xabc","content":"two","timestamp_ms":2000},
 {"from_self":true,"content":"one","timestamp_ms":1000},
 {"from_self":false,"sender":"0xabc","content":"two","timestamp_ms":2000},
 {"from_self":false,"sender":"","content":"three","timestamp_ms":3000}]}
"""))!
check(msgs.map(\.content) == ["one", "two", "three"], "oldest first, de-duplicated on (time, sender, content)")
check(msgs[0].fromSelf && msgs[0].sender == nil && msgs[2].sender == nil, "an empty sender is no sender")
check(W.messagesTarget(convo: "a b/c?d") == "/v2/chat/messages?convo=a%20b%2Fc%3Fd",
      "the conversation id is percent-encoded once, in the signed target")
check(W.messagesTarget(convo: "c1", sinceMs: 42) == "/v2/chat/messages?convo=c1&since_ms=42", "since_ms rides the target")

print("Who, never what kind (prd §1213)")
let dms = W.conversations(parse("""
{"available":true,"conversations":[
 {"id":"a","kind":"direct","name":"Direct message","last_activity_ms":3000},
 {"id":"b","kind":"direct","name":"Direct message","peer":"0xfeedbeefcafe0001","last_activity_ms":2000},
 {"id":"g","kind":"group","name":"Group chat","last_activity_ms":1000}]}
"""))!
check(dms[0].title(names: none) == "Direct conversation", "Basecamp's \"Direct message\" names nobody")
check(dms[1].peer == "0xfeedbeefcafe0001" && dms[1].title(names: none) == LogosWire.short("0xfeedbeefcafe0001"),
      "an Observer's peer titles the conversation by its address")
check(dms[1].title(names: { $0 == "0xfeedbeefcafe0001" ? "Ana" : nil }) == "Ana", "a name you gave wins over the address")
check(dms[2].title(names: none) == "Group conversation", "a generic group name names nobody either")
let thread: [W.ChatMessage] = [
    .init(fromSelf: false, sender: "0xaaaa1111bbbb2222", content: "hi", timestampMs: 0),
    .init(fromSelf: true, sender: nil, content: "hey", timestampMs: 60_000, delivery: W.delivery("pending")),
    .init(fromSelf: false, sender: "0xaaaa1111bbbb2222", content: "ok", timestampMs: 120_000),
    .init(fromSelf: false, sender: "0xcccc3333dddd4444", content: "me too", timestampMs: 180_000),
    .init(fromSelf: false, sender: "0xcccc3333dddd4444", content: "later", timestampMs: 180_000 + 16 * 60_000)]
let a = dms[0].enriched(with: Array(thread.prefix(3)))
check(a.peer == "0xaaaa1111bbbb2222" && a.title(names: none) == LogosWire.short("0xaaaa1111bbbb2222"),
      "with no peer field, a direct conversation is titled by its first sender")
check(a.previewLine(names: none) == "ok", "a direct preview carries no author for the other person")
check(dms[0].enriched(with: Array(thread.prefix(2))).previewLine(names: none) == "You: hey", "your own line says You")
let g = dms[2].enriched(with: thread)
check(g.peer == nil && g.senders == ["0xaaaa1111bbbb2222", "0xcccc3333dddd4444"], "a group keeps its senders, never a peer")
check(g.previewLine(names: { $0 == "0xcccc3333dddd4444" ? "Mira" : nil }) == "Mira: later", "a group preview says who")
check(g.people(names: { $0 == "0xaaaa1111bbbb2222" ? "Ana" : nil }) == "You, Ana and 1 other", "a group's people")
let lines = W.lines(thread, group: true, names: none)
let authors = lines.filter { if case .author = $0 { return true }; return false }.count
let times = lines.filter { if case .time = $0 { return true }; return false }.count
check(times == 2, "a time opens the thread and every gap over 15 minutes")
check(authors == 4, "an author opens each run of another person's messages, and again after a time")
check(W.lines(thread, group: false, names: none).allSatisfy { if case .author = $0 { return false }; return true },
      "a direct conversation draws no author lines")
check(thread[1].delivery == .pending && W.delivery("delivered") == .sent && W.delivery("failed") == .failed
      && W.delivery(nil) == nil && W.delivery("bogus") == nil,
      "delivery is read only from the words it knows; anything else claims nothing")

print("Several Observers, routed by scope (prd §1155a)")
struct P { let id: String; let granted: [String] }
let nuc = P(id: "nuc", granted: ["node.status.read", "network.status.read"])
let mac = P(id: "mac", granted: ["chat.read"])
let both = P(id: "both", granted: ["node.status.read", "chat.read"])
check(W.pick([nuc, mac], granted: \.granted, scope: W.nodeScope)?.id == "nuc", "Node reads through the NUC")
check(W.pick([nuc, mac], granted: \.granted, scope: W.chatScope)?.id == "mac", "Chat reads through the Mac")
check(W.pick([nuc, mac, both], granted: \.granted, scope: W.nodeScope)?.id == "both"
      && W.pick([nuc, mac, both], granted: \.granted, scope: W.chatScope)?.id == "both",
      "the newest pairing granted a scope wins it")
check(W.pick([mac], granted: \.granted, scope: W.nodeScope) == nil, "no node pairing, no node read")

print(failures == 0 ? "✓ all Observer checks" : "✗ \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)

extension Data {
    init(hexString: String) {
        var d = Data(); var i = hexString.startIndex
        while i < hexString.endIndex {
            let j = hexString.index(i, offsetBy: 2); d.append(UInt8(hexString[i..<j], radix: 16)!); i = j
        }
        self = d
    }
}
SWIFT

xcrun swiftc -O -o "$TMP/run" "$WIRE" "$NODE" "$TMP/main.swift" 2>"$TMP/err" || { cat "$TMP/err"; echo "✗ compile failed"; exit 1; }
"$TMP/run" "$FIX"
