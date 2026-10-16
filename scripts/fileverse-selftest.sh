#!/bin/zsh
# Fileverse self-test (prd §1346) — the read path of the Fileverse seat:
#
#   Casberi/Casberi/Model/Yjs.swift             compiled WHOLE and unmodified
#   Casberi/Casberi/Model/FileverseCrypto.swift  compiled WHOLE and unmodified
#   Casberi/Casberi/Model/FileverseDoc.swift     compiled WHOLE and unmodified
#   Casberi/Casberi/Model/FileverseChain.swift   compiled WHOLE and unmodified
#
# (FileverseKey.swift needs libsecp256k1 and is held to the same vector by
# CasberiTests/FileverseKeyTests.)
#
# WHY A HARNESS. A dDoc is a Yjs update, and the order of its words exists only
# after Yjs's integration rule runs over the inserts. A reader that gets the
# rule slightly wrong does not crash or come back empty: it reorders somebody's
# sentences, quietly, only where two edits raced. So the decoder is held to
# 160 edit histories the REAL yjs library wrote
# (scripts/fileverse-probe/yjs-vectors.json, made by gen-yjs-vectors.mjs:
# three clients editing concurrently, deletes, formats, attribute overwrites,
# emoji, gc on and off), each compared to the tree yjs itself reads back.
#
# Then mutations: each breaks one rule the port depends on and must turn the
# run red, or the check certifies nothing.
#
# Pure, local, deterministic — no network, no simulator, no key, no npm.
set -euo pipefail
cd "$(dirname "$0")/.."

YJS="Casberi/Casberi/Model/Yjs.swift"
CRYPTO="Casberi/Casberi/Model/FileverseCrypto.swift"
DOC="Casberi/Casberi/Model/FileverseDoc.swift"
CHAIN="Casberi/Casberi/Model/FileverseChain.swift"
VECTORS="scripts/fileverse-probe/yjs-vectors.json"
CVECTORS="scripts/fileverse-probe/crypto-vectors.json"
for f in "$YJS" "$CRYPTO" "$DOC" "$CHAIN" "$VECTORS" "$CVECTORS"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/fileverse-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

func value(_ v: Yjs.Value) -> Any {
    switch v {
    case .null, .undefined: return NSNull()
    case .bool(let b): return b
    case .number(let n): return n
    case .string(let s): return s
    case .array(let a): return a.map(value)
    case .object(let o): return o.mapValues(value)
    case .bytes(let d): return d.base64EncodedString()
    }
}

func json(_ n: Yjs.Node) -> Any {
    switch n {
    case .element(let name, let attrs, let children):
        return ["name": name, "attrs": attrs.mapValues(value), "children": children.map(json)] as [String: Any]
    case .text(let runs):
        return ["text": runs.map { r -> [String: Any] in
            ["insert": r.text.map { $0 as Any } ?? ["embed": value(r.embed ?? .null)],
             "attributes": r.attributes.mapValues(value)]
        }] as [String: Any]
    }
}

/// yjs's delta does not merge neighbours under equal formats; the port does.
/// Normalise the expected side the same way before comparing.
func merged(_ node: Any) -> Any {
    guard var o = node as? [String: Any] else { return node }
    if let runs = o["text"] as? [[String: Any]] {
        var out: [[String: Any]] = []
        for r in runs {
            if let last = out.last, let a = last["insert"] as? String, let b = r["insert"] as? String,
               (last["attributes"] as? NSDictionary) == (r["attributes"] as? NSDictionary) {
                out[out.count - 1]["insert"] = a + b
            } else {
                out.append(r)
            }
        }
        o["text"] = out
    }
    if let children = o["children"] as? [Any] { o["children"] = children.map(merged) }
    return o
}

func canonical(_ any: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: any, options: [.sortedKeys, .fragmentsAllowed])
    return String(decoding: data, as: UTF8.self)
}

let file = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let root = try! JSONSerialization.jsonObject(with: file) as! [String: Any]
let vectors = root["vectors"] as! [[String: Any]]
var failed = 0
for (i, v) in vectors.enumerated() {
    let update = Data(base64Encoded: v["update"] as! String)!
    let expected = canonical((v["tree"] as! [Any]).map(merged))
    do {
        let got = canonical(try Yjs.read(update: update).map(json))
        if got != expected {
            failed += 1
            if failed <= 3 {
                print("  ✗ vector \(i) (gc \(v["gc"]!)) differs")
                print("    want \(expected.prefix(300))")
                print("    got  \(got.prefix(300))")
            }
        }
    } catch {
        failed += 1
        if failed <= 3 { print("  ✗ vector \(i) threw \(error)") }
    }
}
print("yjs| \(vectors.count - failed)/\(vectors.count) vectors read as yjs reads them")
exit(failed == 0 ? 0 : 1)
SWIFT

run() {
  local src=$1
  swiftc -O -o "$TMP/run" "$src" "$TMP/main.swift" 2>"$TMP/build.log" \
    || { echo "✗ build failed"; tail -20 "$TMP/build.log"; return 2; }
  "$TMP/run" "$VECTORS"
}

echo "Yjs decoder:"
run "$YJS" || { echo "✗ fileverse self-test FAILED"; exit 1; }

# Mutations — each must turn the run red.
mutate() {
  local name=$1 from=$2 to=$3
  local m="$TMP/Yjs-mutant.swift"
  perl -0pe "s/\Q$from\E/$to/" "$YJS" > "$m"
  if cmp -s "$m" "$YJS"; then echo "  ✗ mutation '$name' changed nothing (anchor drifted)"; return 1; fi
  if run "$m" >/dev/null 2>&1; then echo "  ✗ mutation SURVIVED: $name"; return 1; fi
  echo "  ✓ mutation caught: $name"
}
echo "Mutations:"
bad=0
mutate "conflict tie-break by client reversed" 'if cur.id.client < item.id.client {' 'if cur.id.client > item.id.client {' || bad=1
mutate "split unit keeps the run's origin" 'let o = i == 0 ? origin : ID(client: client, clock: clock + UInt64(i) - 1)' 'let o = origin' || bad=1
mutate "delete set ignored" 'for c in clock..<(clock + len) { items[ID(client: client, clock: c)]?.deleted = true }' 'for _ in clock..<(clock + len) { }' || bad=1
mutate "a format's null kept as a value" 'if value == .null { attrs.removeValue(forKey: key) } else { attrs[key] = value }' 'attrs[key] = value' || bad=1
mutate "YATA compares the wrong origin" 'if item.origin == cur.origin {' 'if item.rightOrigin == cur.origin {' || bad=1
mutate "strings split by scalar, not UTF-16 unit" 'case 4: return try d.varString().utf16.map' 'case 4: return try d.varString().unicodeScalars.map { UInt16(truncatingIfNeeded: \$0.value) }.map' || bad=1
mutate "an item inherits its right neighbour's parent first" 'if let l = left, l.parent != nil {' 'if let l = right, l.parent != nil {' || bad=1
# Not mutated, and why: the map-overwrite delete (`item.left?.deleted`) and the
# garbage-collected-neighbour branch are yjs's live-apply rules. A full-state
# update already carries the overwrite in its delete set and the writer has
# already collected anything next to a collected neighbour, so neither can be
# reached from a stored document; a mutation of either survives by design.
(( bad == 0 )) || { echo "✗ fileverse self-test FAILED (mutations)"; exit 1; }

# ---- The document: Fileverse's own vector, opened and written as Markdown ----
mkdir -p "$TMP/doc-src"; cat > "$TMP/doc-src/main.swift" <<'SWIFT'
import Foundation

var failed = 0
func check(_ ok: Bool, _ what: String) {
    print("  \(ok ? "✓" : "✗") \(what)")
    if !ok { failed += 1 }
}
func b64(_ s: String) -> Data { Data(base64Encoded: s)! }

let v = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let eph = b64(v["ephemeral"] as! String)
let point = b64(v["sharedPoint"] as! String)
// The curve half is CasberiTests'; here the point is the vector's own.
let shared: (Data) -> Data? = { $0 == eph ? point : nil }
let expect = v["expect"] as! [String: Any]

do {
    let opened = try FileverseCrypto.open(metadata: Data((v["metadata"] as! String).utf8),
                                          content: b64(v["content"] as! String), sharedPoint: shared)
    check(opened.lock == "appLock", "the appLock opens")
    check(opened.title == expect["title"] as! String, "the title opens to Fileverse's own")
    let nodes = try Yjs.read(update: opened.update)
    let plain = FileverseDoc.plainText(nodes).components(separatedBy: "\n")
    let want = expect["lines"] as! [String]
    check(plain == want, "the body reads as Fileverse's own lines")
    let md = FileverseDoc.markdown(nodes)
    let bare = md.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "_", with: "")
    check(want.allSatisfy { bare.contains($0) }, "the Markdown carries every line")
    check(md.contains("**"), "the bold run is marked bold")
} catch {
    check(false, "the vector opens (\(error))")
}

// A lock that is not four parts, a wrong point, a flipped byte: refused.
check((try? FileverseCrypto.openLock("a__n__b", sharedPoint: shared)) == nil, "a two-part lock is refused")
check((try? FileverseCrypto.open(metadata: Data((v["metadata"] as! String).utf8),
                                 content: b64(v["content"] as! String), sharedPoint: { _ in Data(repeating: 2, count: 33) })) == nil,
      "a wrong ECDH point opens nothing")
var flipped = b64(v["content"] as! String)
flipped[9] ^= 1
check((try? FileverseCrypto.open(metadata: Data((v["metadata"] as! String).utf8), content: flipped, sharedPoint: shared)) == nil,
      "a flipped content byte is refused")

// The Markdown, for a tree with every block the editor writes.
typealias N = Yjs.Node
func t(_ s: String, _ a: [String: Yjs.Value] = [:]) -> N { .text([Yjs.Run(text: s, embed: nil, attributes: a)]) }
func e(_ name: String, _ attrs: [String: Yjs.Value] = [:], _ kids: [N] = []) -> N { .element(name: name, attrs: attrs, children: kids) }
let tree: [N] = [
    e("dBlock", [:], [e("heading", ["level": .number(2)], [t("Goals")])]),
    e("dBlock", [:], [e("paragraph", [:], [.text([
        Yjs.Run(text: "We ", embed: nil, attributes: [:]),
        Yjs.Run(text: "ship ", embed: nil, attributes: ["bold": .bool(true)]),
        Yjs.Run(text: "a*b", embed: nil, attributes: [:]),
        Yjs.Run(text: " here", embed: nil, attributes: ["link": .object(["href": .string("https://x.y")])]),
    ])])]),
    e("dBlock", [:], [e("bulletList", [:], [
        e("listItem", [:], [e("paragraph", [:], [t("one")]), e("bulletList", [:], [e("listItem", [:], [e("paragraph", [:], [t("nested")])])])]),
        e("listItem", [:], [e("paragraph", [:], [t("two")])]),
    ])]),
    e("dBlock", [:], [e("taskList", [:], [e("taskItem", ["checked": .bool(true)], [e("paragraph", [:], [t("done")])])])]),
    e("dBlock", [:], [e("table", [:], [
        e("tableRow", [:], [e("tableHeader", [:], [e("paragraph", [:], [t("Owner")])]), e("tableHeader", [:], [e("paragraph", [:], [t("Due")])])]),
        e("tableRow", [:], [e("tableCell", [:], [e("paragraph", [:], [t("Ana")])]), e("tableCell", [:], [e("paragraph", [:], [t("a|b")])])]),
    ])]),
    e("dBlock", [:], [e("horizontalRule")]),
    e("dBlock", [:], [e("resizableMedia", ["src": .string("https://img/x.png")])]),
    e("dBlock", [:], [e("mysteryBlock", [:], [e("paragraph", [:], [t("kept")])])]),
]
let want = """
## Goals

We **ship** a\\*b[ here](https://x.y)

- one
  - nested
- two

- [x] done

| Owner | Due |
| --- | --- |
| Ana | a\\|b |

---

![](https://img/x.png)

kept
"""
let got = FileverseDoc.markdown(tree)
check(got == want, "every block writes as Markdown")
if got != want { print(got) }

// The portal's log, replayed: an edit supersedes, a delete removes, block
// order wins over list order, setup events are skipped.
func word(_ v: UInt64) -> String { String(repeating: "0", count: 48) + String(format: "%016llx", v) }
func abi(_ appFileId: String, _ type: UInt64, _ meta: String, _ content: String, _ gate: String, _ version: UInt64) -> String {
    let strings = [appFileId, meta, content, gate]
    var heads: [String] = [], tails: [String] = []
    var offset: UInt64 = 6 * 32
    var stringHeads: [String] = []
    for s in strings {
        stringHeads.append(word(offset))
        let bytes = Array(s.utf8)
        var tail = word(UInt64(bytes.count)) + bytes.map { String(format: "%02x", $0) }.joined()
        while tail.count % 64 != 0 { tail += "0" }
        tails.append(tail)
        offset += UInt64(tail.count / 2)
    }
    heads = [stringHeads[0], word(type), stringHeads[1], stringHeads[2], stringHeads[3], word(version)]
    return "0x" + heads.joined() + tails.joined()
}
func topicID(_ id: UInt64) -> String { "0x" + word(id) }
func log(_ t0: String, _ id: UInt64, _ data: String, block: UInt64, index: String = "0x0") -> [String: Any] {
    ["topics": [t0, topicID(id), "0x" + word(7)], "data": data, "blockNumber": String(format: "0x%llx", block), "logIndex": index]
}
let logs: [[String: Any]] = [
    log(FileverseChain.edited, 1, abi("a1", 2, "metaV2", "contentV2", "gate", 2), block: 20),
    log(FileverseChain.added, 1, abi("a1", 2, "metaV1", "contentV1", "gate", 1), block: 10, index: "0x"),
    log(FileverseChain.added, 2, abi("a2", 2, "m2", "c2", "g", 1), block: 11),
    log(FileverseChain.deleted, 2, "0x", block: 30),
    log(FileverseChain.added, 3, abi("a3", 2, "m3", "c3", "g", 1), block: 12),
    ["topics": ["0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0", "0x" + word(1)], "data": "0x", "blockNumber": "0x5", "logIndex": "0x0"],
]
let live = FileverseChain.liveFiles(logs)
check(live.map(\.fileId) == ["3", "1"], "the live set is files 3 and 1, newest id first")
check(live.last?.contentCID == "contentV2" && live.last?.version == 2 && live.last?.block == 20, "an edit supersedes its add, whatever the list order")
check(FileverseChain.decode("0x1234", ["string"]) == nil, "a short body decodes to nothing")
check(FileverseChain.deletedIDs(logs) == ["2"], "only the file the log deleted is deleted")
// A partial read (a public node answering with part of the log) deletes nothing.
check(FileverseChain.deletedIDs(Array(logs.prefix(1))).isEmpty, "a partial log deletes nothing")
let readded = logs + [log(FileverseChain.added, 2, abi("a2", 2, "m2b", "c2b", "g", 2), block: 40)]
check(FileverseChain.deletedIDs(readded).isEmpty, "a file added again after its delete is not deleted")
print(failed == 0 ? "doc| ok" : "doc| \(failed) FAILED")
exit(failed == 0 ? 0 : 1)
SWIFT

rundoc() {
  local crypto=$1
  swiftc -O -o "$TMP/doc" "$YJS" "$crypto" "$DOC" "${chain:-$CHAIN}" "$TMP/doc-src/main.swift" 2>"$TMP/doc-build.log" \
    || { echo "✗ build failed"; tail -20 "$TMP/doc-build.log"; return 2; }
  "$TMP/doc" "$CVECTORS"
}
echo "Fileverse document:"
rundoc "$CRYPTO" || { echo "✗ fileverse self-test FAILED"; exit 1; }

mutatec() {
  local name=$1 from=$2 to=$3
  local m="$TMP/FileverseCrypto-mutant.swift"
  perl -0pe "s/\Q$from\E/$to/" "$CRYPTO" > "$m"
  if cmp -s "$m" "$CRYPTO"; then echo "  ✗ mutation '$name' changed nothing (anchor drifted)"; return 1; fi
  if rundoc "$m" >/dev/null 2>&1; then echo "  ✗ mutation SURVIVED: $name"; return 1; fi
  echo "  ✓ mutation caught: $name"
}
echo "Mutations:"
bad=0
mutatec "wrong ECIES HKDF info" 'info: "ECIES-AES256-GCM-SHA256")' 'info: "ECIES-AES256-GCM")' || bad=1
mutatec "content iv read from the front" 'AES.GCM.Nonce(data: b[(b.count - 12)...])' 'AES.GCM.Nonce(data: b[0..<12])' || bad=1
mutatec "title nonce read as 12 bytes" 'AES.GCM.Nonce(data: b[0..<24])' 'AES.GCM.Nonce(data: b[0..<12])' || bad=1
mutatec "ECIES salt dropped" 'let key = hkdf(point, salt: eph,' 'let key = hkdf(point, salt: Data(),' || bad=1
mutatechain() {
  local name=$1 from=$2 to=$3
  local m="$TMP/FileverseChain-mutant.swift"
  perl -0pe "s/\Q$from\E/$to/" "$CHAIN" > "$m"
  if cmp -s "$m" "$CHAIN"; then echo "  ✗ mutation '$name' changed nothing (anchor drifted)"; return 1; fi
  if chain="$m" rundoc "$CRYPTO" >/dev/null 2>&1; then echo "  ✗ mutation SURVIVED: $name"; return 1; fi
  echo "  ✓ mutation caught: $name"
}
mutatechain "a delete ignored" 'files.removeValue(forKey: fileId)' '_ = fileId' || bad=1
mutatechain "a re-add leaves the delete standing" 'deleted.remove(fileId)' '_ = fileId' || bad=1
mutatechain "the log replayed in list order" 'let ordered = logs.sorted {' 'let ordered = logs; _ = logs.sorted {' || bad=1
(( bad == 0 )) || { echo "✗ fileverse self-test FAILED (mutations)"; exit 1; }
echo "✓ fileverse self-test passed"
