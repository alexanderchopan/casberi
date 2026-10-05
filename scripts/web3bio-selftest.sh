#!/bin/zsh
# web3.bio self-test (prd §916, 2026-09-24) — the resolver behind `ENS` and the
# linked-name rows on an address card:
#
#   Casberi/Casberi/Model/Web3Bio.swift   compiled WHOLE and unmodified
#
# WHY A HARNESS. Every wrong answer here is a SILENCE or a STRANGER'S NAME,
# and both render fine:
#
#   • A RECORD FOR SOMEBODY ELSE. `/ns/{address}` answers records whose own
#     `address` is NOT the one asked — vitalik's Lens row carries a
#     different address (MEASURED). Take the array as "this address's
#     names" and a stranger's handle stands beside somebody's money (§599).
#   • A 404 READ AS AN EMPTY LIST, or a 200 THAT IS NOT AN ARRAY read as one.
#     "Nothing under this query" and "we could not read the answer" must stay
#     apart (§780b), or an outage cached as "no names" for the whole launch.
#   • THE PLACEHOLDER ROW READ AS A NAME. A nameless address answers one
#     `platform: ethereum` row whose identity is the address itself.
#   • A THROTTLE CACHED AS A MISS. A 429 must be asked again on the next
#     intent, never remembered as "no names".
#   • THE DEMO REACHING OUT. `verify.sh`'s "Demo reaches nothing" found
#     `api.ensideas.com` reached for a fabricated address once; the gate is
#     at the function that reads, and this proves it (no request is made).
#   • A `/` IN A NAME TURNING THE QUERY INTO A PATH (§735's Gmail trap).
#   • AN `eip155:` AVATAR HANDED TO AN IMAGE VIEW.
#   • A CHECKSUMMED ADDRESS MISSING ITS OWN LOWERCASED RECORD.
#
# Pure, local, deterministic — no network, no simulator, no key. The network
# is a stub with canned answers, so the async half runs too.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Web3Bio.swift"
[[ -f "$SRC" ]] || { echo "✗ $SRC not found"; exit 1; }

TMP=$(mktemp -d /tmp/web3bio-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

// ── Stubs for the two things the file reaches outside itself ─────────────
enum DemoMode { nonisolated(unsafe) static var isActive = false }
enum ENS {
    static func isHexAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }
}
enum IngestSupport {
    nonisolated(unsafe) static var canned: [String: (Any?, Int)] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    static func getJSONStatus(_ url: String, auth: String? = nil,
                              headers: [String: String] = [:],
                              service: String? = nil) async -> (json: Any?, status: Int) {
        requests.append(url)
        if let hit = canned[url] { return (hit.0, hit.1) }
        return (nil, 0)
    }
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}
func row(_ platform: String, _ identity: String, _ address: String,
         avatar: Any? = nil, display: Any? = nil) -> [String: Any] {
    var r: [String: Any] = ["platform": platform, "identity": identity, "address": address]
    r["avatar"] = avatar ?? NSNull(); r["displayName"] = display ?? NSNull()
    return r
}

/// A `/profile` row (prd §1025): the `/ns` row plus `description` and
/// `links`, each link `{link, handle, sources}` as measured 2026-09-30.
func prow(_ platform: String, _ identity: String, _ address: String,
          bio: String?, links: [String: String]) -> [String: Any] {
    var r = row(platform, identity, address)
    r["description"] = bio ?? NSNull()
    r["links"] = links.mapValues { ["link": "https://x/\($0)", "handle": $0, "sources": []] as [String: Any] }
    return r
}

// The measured vitalik array: four records, three of which carry OTHER
// addresses than the ENS one. The Farcaster row is dropped at parse since the
// seat was retired (prd §1109), so three are read.
let V = "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
let vitalik: [Any] = [
    row("ens", "vitalik.eth", V, avatar: "https://euc.li/vitalik.eth"),
    row("basenames", "vb62831.base.eth", "0x40e82a6269e6a98b852c8ebc5dcdc4f352dca6b7"),
    row("farcaster", "vitalik.eth", "0x96b6bb2bd2eba3b4fbefd7dbac448ad7b6cbf279",
        avatar: "https://media.firefly.land/x.png", display: "Vitalik Buterin"),
    row("lens", "vitalik.lens", "0xe4aaa97cda406c6af7c02a5260a8013910bd683c"),
]

// ── Pure: parse ─────────────────────────────────────────────────────────
if case .records(let rs) = Web3Bio.parse(vitalik, status: 200) {
    check(rs.count == 3, "three name records parsed — the Farcaster row is dropped (prd §1109)")
    check(rs.first?.platform == .ens && rs.first?.identity == "vitalik.eth", "the ENS row parsed")
    check(rs[1].platform == .basenames, "a basenames row is .basenames")
    check(rs[2].platform == .lens, "a lens row is .lens")
    check(rs[2].avatar == nil, "a null avatar is nil")
} else { check(false, "a 200 array parses as records") }

check(Web3Bio.parse(vitalik, status: 404) == .none, "404 is .none")
check(Web3Bio.parse(vitalik, status: 429) == .throttled, "429 is .throttled")
check(Web3Bio.parse(vitalik, status: 500) == .unreadable, "500 is .unreadable")
check(Web3Bio.parse(nil, status: 0) == .unreadable, "no answer is .unreadable")
check(Web3Bio.parse(["error": "Not Found"], status: 200) == .unreadable,
      "a 200 that is not an array is unreadable, never empty")
check(Web3Bio.parse([], status: 200) == .records([]), "an empty array is an empty answer")

// The placeholder row for a nameless address.
let dead = "0x000000000000000000000000000000000000dead"
check(Web3Bio.parse([row("ethereum", dead, dead)], status: 200) == .records([]),
      "the ethereum placeholder row is not a name")
check(Web3Bio.parse([row("solana", "abc", "abc")], status: 200) == .records([]),
      "the solana placeholder row is not a name")
check(Web3Bio.record(row("myspace", "tom", V)) == nil, "an unknown platform is dropped")
check(Web3Bio.record(row("farcaster", "vitalik.eth", V)) == nil,
      "a Farcaster record is dropped — the seat is retired (prd §1109)")
check(Web3Bio.record(row("ens", "x.eth", V, display: "Vitalik Buterin"))?.displayName == "Vitalik Buterin",
      "displayName kept")
check(Web3Bio.record(row("ENS", "vitalik.eth", "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045"))?.address == V,
      "platform case folded and an EVM address lowercased")
check(Web3Bio.record(row("sns", "toly.sol", "86xCnPeV69n6t3DnyGvkKobf9FdN2H9oiVDdaMpo2MMY"))?.address
      == "86xCnPeV69n6t3DnyGvkKobf9FdN2H9oiVDdaMpo2MMY", "a Solana address keeps its case")
check(Web3Bio.record(row("ens", "", V)) == nil, "an empty identity is dropped")
check(Web3Bio.record(row("ens", "x.eth", "")) == nil, "an empty address is dropped")
check(Web3Bio.record(row("ens", "x.eth", V, avatar: "eip155:1/erc721:0xabc/1"))?.avatar == nil,
      "an eip155 avatar is not an image")
check(Web3Bio.record(row("ens", "x.eth", V, avatar: "https://euc.li/x.eth"))?.avatar == "https://euc.li/x.eth",
      "an http avatar is kept")
check(Web3Bio.record(row("ens", "x.eth", V, display: ""))?.displayName == nil, "an empty displayName is nil")

// ── Pure: ownership and forward ─────────────────────────────────────────
guard case .records(let recs) = Web3Bio.parse(vitalik, status: 200) else { exit(1) }
let own = Web3Bio.names(recs, ownedBy: V)
check(own.count == 1 && own.first?.platform == .ens,
      "only the record whose OWN address is the query names it (the §599 half)")
check(Web3Bio.names(recs, ownedBy: V.uppercased().replacingOccurrences(of: "0X", with: "0x")).count == 1,
      "a checksummed spelling still finds its lowercased record")
check(Web3Bio.names(recs, ownedBy: "0xe4aaa97cda406c6af7c02a5260a8013910bd683c").first?.platform == .lens,
      "the Lens record names ITS address")
check(Web3Bio.forwardAddress(recs, for: "vitalik.lens") == "0xe4aaa97cda406c6af7c02a5260a8013910bd683c",
      "forward picks the record whose identity is the name, not the first row")
check(Web3Bio.forwardAddress(recs, for: "VITALIK.ETH") == V, "forward matches the name case-insensitively")
check(Web3Bio.forwardAddress(recs, for: "nobody.eth") == nil, "forward for an absent name is nil")

// ── Pure: platform words ────────────────────────────────────────────────
check(Web3Bio.Platform.basenames.display("jesse.base.eth") == "jesse.base.eth", "a name is already the name")
check(Web3Bio.Platform.basenames.isLinkedEVMName
      && Web3Bio.Platform.lens.isLinkedEVMName && Web3Bio.Platform.linea.isLinkedEVMName,
      "Base, Linea and Lens are the linked rows")
check(!Web3Bio.Platform.ens.isLinkedEVMName && !Web3Bio.Platform.sns.isLinkedEVMName,
      "ENS has its own row and SNS is not EVM")
check(!Web3Bio.Platform.ethereum.isName && !Web3Bio.Platform.solana.isName, "placeholders are not names")
check(Web3Bio.Platform.basenames.label == "Base" && Web3Bio.Platform.linea.label == "Linea"
      && Web3Bio.Platform.lens.label == "Lens" && Web3Bio.Platform.ens.label == "ENS", "the labels")

// ── Pure: one name, one row ─────────────────────────────────────────────
var rows = [Web3Bio.Named(label: "ENS", name: "jesse.base.eth")]
Web3Bio.fold(Web3Bio.Named(label: "Base", name: "Jesse.Base.ETH"), into: &rows)
check(rows.count == 1 && rows[0].label == "Base" && rows[0].name == "jesse.base.eth",
      "a name the ENS step listed is relabelled in place by the specific service, case folded")
Web3Bio.fold(Web3Bio.Named(label: "Linea", name: "jesse.linea.eth"), into: &rows)
check(rows.count == 2 && rows[1].label == "Linea", "a different name appends after it")
Web3Bio.fold(Web3Bio.Named(label: "Lens", name: "x.lens"), into: &rows)
check(rows.map(\.name) == ["jesse.base.eth", "jesse.linea.eth", "x.lens"], "the order is the arrival order")

// ── Pure: the URL ───────────────────────────────────────────────────────
check(Web3Bio.url(for: "vitalik.eth")?.absoluteString == "https://api.web3.bio/ns/vitalik.eth", "a plain name")
check(Web3Bio.url(for: "  jesse.base.eth ")?.absoluteString == "https://api.web3.bio/ns/jesse.base.eth", "trimmed")
check(Web3Bio.url(for: "lens,vitalik.lens")?.absoluteString == "https://api.web3.bio/ns/lens,vitalik.lens",
      "a platform-scoped query keeps its comma")
check(Web3Bio.url(for: "a/b.eth") == nil, "a slash is refused, never encoded into a path")
check(Web3Bio.url(for: "a?b.eth") == nil, "a query string is refused")
check(Web3Bio.url(for: "") == nil, "empty is refused")
check(Web3Bio.url(for: "ünïcode.eth")?.absoluteString == "https://api.web3.bio/ns/%C3%BCn%C3%AFcode.eth",
      "non-ASCII is percent-encoded")

// ── Async: the network half over canned answers ─────────────────────────
// The main actor is served by this thread's run loop, so the wait below
// PUMPS it rather than blocking on a semaphore (which deadlocks the task).
nonisolated(unsafe) var done = false
Task { @MainActor in
    let base = "https://api.web3.bio/ns/"
    IngestSupport.canned = [
        base + V: (vitalik, 200),
        base + "vitalik.eth": (vitalik, 200),
        base + "nobody.eth": (["error": "Not Found"], 404),
        base + "busy.eth": (nil, 429),
        base + "broken.eth": (["error": "x"], 200),
        base + "lens,vitalik.lens": ([row("lens", "vitalik.lens", "0xe4aaa97cda406c6af7c02a5260a8013910bd683c")], 200),
        base + "basenames,jesse.base.eth": ([row("basenames", "jesse.base.eth", "0x2211d1d0020daea8039e46cf1367962070d77da9")], 200),
        base + "0x2211d1d0020daea8039e46cf1367962070d77da9":
            ([row("basenames", "jesse.base.eth", "0x2211d1d0020daea8039e46cf1367962070d77da9"),
              row("linea", "jesse.linea.eth", "0x2211d1d0020daea8039e46cf1367962070d77da9",
                  avatar: "https://i.example/jesse.png"),
              row("lens", "jesse.lens", "0x2211d1d0020daea8039e46cf1367962070d77da9")], 200),
        // The forward answer is ANOTHER address — the record is not believed.
        base + "linea,jesse.linea.eth": ([row("linea", "jesse.linea.eth", "0x0000000000000000000000000000000000000001")], 200),
        // The forward answer names the address on the SAME platform under a
        // DIFFERENT identity — a squatter's shape. Not verified.
        base + "lens,jesse.lens": ([row("lens", "other.lens", "0x2211d1d0020daea8039e46cf1367962070d77da9")], 200),
    ]

    // Forward.
    check(await Web3Bio.resolve("vitalik.eth") == V, "resolve answers the address")
    check(await Web3Bio.resolve("nobody.eth") == nil, "a 404 resolves to nil")
    check(await Web3Bio.resolve("busy.eth") == nil, "a 429 resolves to nil")
    check(await Web3Bio.resolve("broken.eth") == nil, "an unreadable body resolves to nil")

    // Reverse: only records naming THIS address.
    let names = await Web3Bio.names(for: V)
    check(names.count == 1 && names.first?.platform == .ens,
          "names(for:) keeps the ENS row and drops the ones web3.bio joined in")

    // Forward verification: the record's own platform+identity comes back to the address.
    let jesse = "0x2211d1d0020daea8039e46cf1367962070d77da9"
    let jn = await Web3Bio.names(for: jesse)
    check(jn.count == 3, "all three of jesse's records name jesse")
    check(await Web3Bio.verified(jn[0], is: jesse) == true, "the basename forward-verifies")
    check(await Web3Bio.verified(jn[1], is: jesse) == false,
          "a record whose forward answer is another address FAILS closed")
    check(await Web3Bio.verified(jn[2], is: jesse) == false,
          "a record whose forward answer names the address under ANOTHER identity fails closed")
    check(IngestSupport.requests.contains(base + "basenames,jesse.base.eth"),
          "verification asked the platform-scoped forward query")

    // Avatar: ENS's first, http only, and for an address only its own records.
    check(await Web3Bio.avatar(for: V) == "https://euc.li/vitalik.eth", "the ENS avatar leads")
    check(await Web3Bio.avatar(for: jesse) == "https://i.example/jesse.png", "else the first http avatar")
    check(await Web3Bio.avatar(for: "nobody.eth") == nil, "no avatar for a 404")

    // Cache: a hit and a miss are remembered; a throttle and an unreadable are not.
    let before = IngestSupport.requests.count
    _ = await Web3Bio.resolve("vitalik.eth")
    _ = await Web3Bio.resolve("nobody.eth")
    check(IngestSupport.requests.count == before, "a hit and a 404 are cached per launch")
    _ = await Web3Bio.resolve("busy.eth")
    _ = await Web3Bio.resolve("broken.eth")
    check(IngestSupport.requests.count == before + 2, "a throttle and an unreadable answer are asked again")
    _ = await Web3Bio.resolve("VITALIK.ETH")
    check(IngestSupport.requests.count == before + 2, "the cache key folds case")

    // The /profile read (prd §1025): the address's OWN records, with bio and links.
    let pj = "0x2211d1d0020daea8039e46cf1367962070d77da9"
    let pbase = "https://api.web3.bio/profile/"
    IngestSupport.canned[pbase + pj] = ([
        prow("basenames", "jesse.base.eth", pj, bio: "  base.eth builder #001 ",
             links: ["github": "jessepollak", "twitter": "jessepollak", "website": "jesse.xyz"]),
        prow("lens", "someoneelse.lens", "0x0000000000000000000000000000000000000009",
             bio: "not jesse", links: ["github": "impostor"]),
    ], 200)
    IngestSupport.canned[pbase + "0x0000000000000000000000000000000000000404"] = (["error": "x"], 404)
    IngestSupport.canned[pbase + "0x0000000000000000000000000000000000000429"] = (nil, 429)
    let prof = await Web3Bio.profile(for: pj.uppercased().replacingOccurrences(of: "0X", with: "0x"))
    check(prof?.count == 1, "a profile keeps only the records whose own address is the one asked")
    check(prof?.first?.links["github"] == "jessepollak" && prof?.first?.links["twitter"] == "jessepollak",
          "a profile record carries its links by platform")
    check(prof?.first?.bio == "base.eth builder #001", "the description is trimmed into the bio")
    check(await Web3Bio.profile(for: "0x0000000000000000000000000000000000000404") == [],
          "a 404 is an answer: nothing linked")
    check(await Web3Bio.profile(for: "0x0000000000000000000000000000000000000429") == nil,
          "a throttle is no answer, so nothing is stored")
    check(Web3Bio.profileURL(for: "vitalik.eth") == nil, "only an address is asked on /profile")
    check(Web3Bio.profileURL(for: "0xZZ11d1d0020daea8039e46cf1367962070d77da9") == nil, "a non-hex body is refused")
    check(Web3Bio.profileURL(for: pj.uppercased().replacingOccurrences(of: "0X", with: "0x"))?.absoluteString == pbase + pj,
          "the address is lowercased into the path")

    // The demo reaches nothing — and makes no request at all.
    DemoMode.isActive = true
    let quiet = IngestSupport.requests.count
    check(await Web3Bio.resolve("fresh-name.eth") == nil, "the demo resolves nothing")
    check(await Web3Bio.names(for: "0x1111111111111111111111111111111111111111").isEmpty, "the demo names nothing")
    check(await Web3Bio.profile(for: "0x1111111111111111111111111111111111111111") == nil, "the demo reads no profile")
    check(IngestSupport.requests.count == quiet, "the demo made NO request")
    DemoMode.isActive = false

    // A refused query never becomes a request.
    let r0 = IngestSupport.requests.count
    check(await Web3Bio.resolve("a/b.eth") == nil, "a slashed name resolves to nil")
    check(IngestSupport.requests.count == r0, "and was never requested")

    done = true
}
let deadline = Date().addingTimeInterval(20)
while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
check(done, "the async half finished within 20s")

if failures > 0 { print("✗ \(failures) failure(s)"); exit(1) }
print("✓ web3bio self-test: every assertion held")
SWIFT

echo "web3.bio self-test — compiling $SRC whole against a canned network"
if ! swiftc -Onone -o "$TMP/run" "$SRC" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ compile failed:"; sed 's/^/  /' "$TMP/build.log" | head -30; exit 1
fi
"$TMP/run" || exit 1

# --- the mutation pass ------------------------------------------------------
# A check that cannot fail proves nothing. Each of these is a silent wrong
# answer this file exists to catch; each must make the run above FAIL.
mutate() {
  local name="$1" from="$2" to="$3"
  local target="$TMP/mut.swift"
  cp "$SRC" "$target"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if cmp -s "$SRC" "$target"; then
    echo "  ✗ $name — the mutant is byte-identical to the source"; exit 1
  fi
  if ! swiftc -Onone -o "$TMP/mut" "$target" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

echo ""
echo "Mutations — each is a resolver that looks completely normal:"
mutate "a stranger's record names this address (§599 half one dropped)" \
  'records.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame }' \
  'records'
mutate "ownership compares case-sensitively (a checksummed address loses its names)" \
  'records.filter { $0.address.caseInsensitiveCompare(address) == .orderedSame }' \
  'records.filter { $0.address == address }'
mutate "a 404 reads as an empty answer" \
  'case 404: return .none' \
  'case 404: return .records([])'
mutate "a 200 that is not an array reads as empty" \
  'guard let rows = json as? [Any] else { return .unreadable }' \
  'guard let rows = json as? [Any] else { return .records([]) }'
mutate "the placeholder row becomes a name" \
  '              platform.isName,' \
  '              true,'
mutate "forward takes the first row instead of the named one" \
  'return records.first { $0.identity.caseInsensitiveCompare(wanted) == .orderedSame }?.address' \
  'return records.first?.address'
mutate "a throttle is cached as a miss" \
  'case .records, .none: cache[key] = outcome' \
  'case .records, .none, .throttled: cache[key] = outcome'
mutate "the demo reaches out" \
  'guard !DemoMode.isActive else { return .unreadable }' \
  'guard true else { return .unreadable }'
mutate "a slash is encoded into the path" \
  'guard !q.isEmpty, !q.contains("/"), !q.contains("?"),' \
  'guard !q.isEmpty, !q.contains("?"),'
mutate "an eip155 avatar is handed to an image view" \
  '(row["avatar"] as? String).flatMap { $0.hasPrefix("http") ? $0 : nil }' \
  '(row["avatar"] as? String)'
mutate "verification believes any record on the platform" \
  '                     && $0.identity.caseInsensitiveCompare(record.identity) == .orderedSame }' \
  '                     }'
mutate "verification stops asking the forward query" \
  'guard case .records(let records) = await lookup("\(record.platform.rawValue),\(record.identity)")' \
  'guard case .records(let records) = await lookup(address)'
mutate "the same name is listed twice under two services" \
  '            rows[i].label = row.label' \
  '            rows.append(row)'
mutate "a profile keeps another address's links" \
  '        case .records(let records): return names(records, ownedBy: address)' \
  '        case .records(let records): return records'
mutate "a profile's links are dropped" \
  '            links[platform.lowercased()] = handle' \
  '            _ = handle'
mutate "a throttled profile reads as nothing linked" \
  '        case .throttled, .unreadable: return nil' \
  '        case .throttled, .unreadable: return []'
mutate "a name is asked on /profile" \
  '        guard a.hasPrefix("0x"), a.count == 42,
              a.dropFirst(2).allSatisfy(\.isHexDigit) else { return nil }' \
  '        guard !a.isEmpty else { return nil }'
mutate "the demo reads a profile" \
  '        guard !DemoMode.isActive, let url = profileURL(for: address) else { return nil }' \
  '        guard let url = profileURL(for: address) else { return nil }'

echo ""
echo "✓ web3bio self-test passed"
