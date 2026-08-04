#!/bin/zsh
# Casberi Cloudflare self-test — verifies the SHIPPED pure logic behind the DNS
# change detector (prd §296, 2026-08-03):
#
#   Casberi/Casberi/Model/CloudflareBridge.swift
#     — diffDNS     (what moved between two passes — the whole judgement)
#     — dnsRef      (a change's identity; get it wrong and changes vanish)
#     — dnsTitle    (what the row says)
#     — daysUntil   (every deadline row's window test)
#
# WHY A HARNESS AND NOT A LIVE CHECK. The bridge was authored against
# Cloudflare's published API reference with no token stored and no
# authenticated access from this host, and every failure mode in `diffDNS` is a
# SILENT WRONG ANSWER rather than a crash:
#
#   · a partial read reporting real records as deleted
#   · a proxy flag flipped from on to off — which exposes an origin server's
#     real address — passing as "no change" under a content-only compare
#   · the second change to a record deduping into the first and never landing
#   · a TXT record whose content contains the delimiter, corrupting the "was"
#
# Every one of those renders perfectly and reads as the feature working.
#
# CloudflareBridge.swift cannot compile as shipped (SwiftData `Thing`,
# ModelContext, IngestSupport), so the pure pieces are EXTRACTED from the
# shipped source by name — never copied into this file — so the harness cannot
# pass against logic the app doesn't run. The only transformation is stripping
# `private `.
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

CF="Casberi/Casberi/Model/CloudflareBridge.swift"
[[ -f "$CF" ]] || { echo "✗ $CF not found"; exit 1; }

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions cannot prove on their own. A perfect
# `diffDNS` is worthless if the caller diffs a prefix, seeds loudly, or lets
# the reconcile close every event row a minute after it lands.
grep -q 'guard let previous = CloudflareDNSLedger.load(zone: zoneID) else { return \[\] }' "$CF" \
  || { echo "✗ first sight no longer seeds silently — connecting would land every existing record as news"; exit 1; }
grep -q 'if page == dnsPageCap { return nil }' "$CF" \
  || { echo "✗ a zone past the page cap no longer refuses — a partial diff invents removals"; exit 1; }
grep -q 'if ref.hasPrefix("cloudflare:dns:") { continue }' "$CF" \
  || { echo "✗ the reconcile no longer exempts DNS event rows — each would close one pass after landing"; exit 1; }
grep -q 'out += await dnsPass(' "$CF" \
  || { echo "✗ the pass no longer runs the DNS diff at all"; exit 1; }
grep -q 'case .cloudflare: CloudflareDNSLedger.clear()' Casberi/Casberi/Model/TokenBridges.swift \
  || { echo "✗ disconnecting no longer clears the DNS ledger — a new account would diff against the old one's records"; exit 1; }

TMP=$(mktemp -d /tmp/cf-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- extract the shipped source ---------------------------------------------
python3 - "$CF" "$TMP/extracted.swift" <<'PY'
import sys
cf, out = sys.argv[1:3]

def grab(path, signature):
    """The whole declaration whose first line contains `signature`,
    brace-matched from the shipped source. Never a copy."""
    src = open(path).read()
    i = src.find(signature)
    if i < 0:
        sys.exit(f"✗ extraction failed: {signature!r} not found in {path}")
    start = src.rfind("\n", 0, i) + 1
    j = src.index("{", i)
    depth, k = 0, j
    while k < len(src):
        if src[k] == "{": depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0: break
        k += 1
    return src[start:k+1].replace("private ", "")

pieces = [
    "import Foundation\n",
    "enum CloudflareFetch {",
    grab(cf, "struct DNSRecord"),
    grab(cf, "struct DNSChange"),
    grab(cf, "static func diffDNS"),
    grab(cf, "static func dnsRef"),
    grab(cf, "static func dnsTitle"),
    grab(cf, "static func daysUntil"),
    "    static let dnsPageCap = 3",
    "    static let dnsChangeCap = 10",
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

typealias CF = CloudflareFetch

/// A record as the API hands it over.
func rec(_ id: String, _ type: String, _ name: String, _ content: String,
         proxied: Bool = false, ttl: Int = 1,
         modified: String = "2026-08-03T10:00:00Z") -> CF.DNSRecord {
    CF.DNSRecord(["id": id, "type": type, "name": name, "content": content,
                  "proxied": proxied, "ttl": ttl, "modified_on": modified])!
}

/// The same record as it would have been REMEMBERED — deliberately built
/// through the shipped `fields` accessor, so the harness can never disagree
/// with storage about field order.
func remembered(_ records: [CF.DNSRecord]) -> [String: [String]] {
    Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.fields) })
}

let apex = rec("r1", "A", "casberi.app", "203.0.113.10")
let blog = rec("r2", "CNAME", "blog.casberi.app", "casberi.app")

print("diffDNS — nothing moved")
check("identical snapshots produce no changes",
      CF.diffDNS(current: [apex, blog], previous: remembered([apex, blog])).isEmpty)

print("diffDNS — a record changed")
let moved = rec("r1", "A", "casberi.app", "198.51.100.7")
let changed = CF.diffDNS(current: [moved, blog], previous: remembered([apex, blog]))
check("exactly one change is reported", changed.count == 1)
check("it is a change, not an add or a remove", changed.first?.kind == .changed)
check("it names the record that moved", changed.first?.record.id == "r1")
// The single most useful thing this feature says. A diff that knows something
// changed but not what it was is barely better than no diff.
check("it carries what the record used to point at",
      changed.first?.previousContent == "203.0.113.10")

print("diffDNS — the fields a content-only compare would miss")
// Flipping proxied off exposes the origin server's real address. Silent under
// any comparison that only looks at content.
let unproxied = rec("r1", "A", "casberi.app", "203.0.113.10", proxied: true)
check("the proxy flag flipping is a change",
      CF.diffDNS(current: [unproxied], previous: remembered([apex])).count == 1)
// Dropping a TTL to 60 is what someone does right before repointing a domain.
let shortTTL = rec("r1", "A", "casberi.app", "203.0.113.10", ttl: 60)
check("a TTL drop is a change",
      CF.diffDNS(current: [shortTTL], previous: remembered([apex])).count == 1)
let retyped = rec("r1", "AAAA", "casberi.app", "203.0.113.10")
check("a type change is a change",
      CF.diffDNS(current: [retyped], previous: remembered([apex])).count == 1)

print("diffDNS — added and removed")
let added = CF.diffDNS(current: [apex, blog], previous: remembered([apex]))
check("a new record is an add", added.count == 1 && added.first?.kind == .added)
check("an add has no previous content", added.first?.previousContent == nil)
let removed = CF.diffDNS(current: [apex], previous: remembered([apex, blog]))
check("a vanished record is a remove", removed.count == 1 && removed.first?.kind == .removed)
// The ghost is rebuilt from the snapshot alone, so a removal can still say
// WHAT was removed rather than just an opaque id.
check("a remove still names the record", removed.first?.record.name == "blog.casberi.app")
check("…and its type", removed.first?.record.type == "CNAME")

print("diffDNS — a delimiter in the content")
// An SPF record contains every delimiter a fingerprint scheme might pick. This
// is why storage is an ARRAY of fields and not a joined string.
let spfWas = rec("r3", "TXT", "casberi.app", "v=spf1 include:_spf.google.com ~all")
let spfNow = rec("r3", "TXT", "casberi.app", "v=spf1 include:_spf.google.com include:sendgrid.net ~all")
let spf = CF.diffDNS(current: [spfNow], previous: remembered([spfWas]))
check("a TXT record full of delimiters diffs cleanly", spf.count == 1)
check("…and its previous value survives intact",
      spf.first?.previousContent == "v=spf1 include:_spf.google.com ~all")
let piped = rec("r4", "TXT", "casberi.app", "a|b|c|d|e|f")
check("a content field of pure pipes is not mistaken for field boundaries",
      CF.diffDNS(current: [piped], previous: remembered([piped])).isEmpty)

print("diffDNS — a snapshot written by an older build")
// Shorter arrays must degrade, never crash: this is somebody's stored data and
// a trap here is far worse than a change reported without its previous value.
check("a short remembered array still reports the change, without a was-value",
      CF.diffDNS(current: [apex], previous: ["r1": ["A"]]).first?.previousContent == nil)
check("a short remembered array for a removal is skipped, not crashed",
      CF.diffDNS(current: [], previous: ["r1": ["A", "casberi.app"]]).isEmpty)
check("an empty previous makes everything an add",
      CF.diffDNS(current: [apex, blog], previous: [:]).count == 2)

print("dnsRef — a change's identity")
let first = CF.diffDNS(current: [rec("r1", "A", "casberi.app", "198.51.100.7",
                                     modified: "2026-08-03T10:00:00Z")],
                       previous: remembered([apex]))[0]
let second = CF.diffDNS(current: [rec("r1", "A", "casberi.app", "198.51.100.9",
                                      modified: "2026-08-04T11:00:00Z")],
                        previous: remembered([apex]))[0]
// Key on the record id alone and the second change to a record dedupes into
// the first and is never seen again.
check("two changes to the SAME record get different refs",
      CF.dnsRef(first) != CF.dnsRef(second))
check("a ref is stable for the same change",
      CF.dnsRef(first) == CF.dnsRef(first))
check("a removal's ref is fixed, since it has no new timestamp",
      CF.dnsRef(removed[0]) == "cloudflare:dns:r2:removed")
check("every ref carries the prefix the reconcile exempts",
      [first, second, removed[0], added[0]].allSatisfy {
          CF.dnsRef($0).hasPrefix("cloudflare:dns:") })

print("dnsTitle — what the row says")
let title = CF.dnsTitle(first, zoneName: "casberi.app")
check("a change names the record and where it now points",
      title.contains("A casberi.app") && title.contains("198.51.100.7"))
check("a removal reads as a removal",
      CF.dnsTitle(removed[0], zoneName: "casberi.app").contains("removed"))
check("an add reads as an add",
      CF.dnsTitle(added[0], zoneName: "casberi.app").contains("added"))

print("daysUntil — every deadline row's window test")
let now = Date(timeIntervalSince1970: 1_800_000_000)
check("12 days out reads as 12",
      CF.daysUntil(now.addingTimeInterval(12 * 86_400), from: now) == 12)
check("today reads as 0", CF.daysUntil(now.addingTimeInterval(3600), from: now) == 0)
// An expired certificate must land, not fall out of the window. It is the most
// urgent row this bridge has.
check("already past reads negative, so it still lands",
      (CF.daysUntil(now.addingTimeInterval(-2 * 86_400), from: now) ?? 99) < 0)

print("")
if failures > 0 { print("cloudflare-selftest: ✗ \(failures) assertion(s) failed"); exit(1) }
print("cloudflare-selftest: OK — every assertion passed against the shipped source.")
SWIFT

build() {
  swiftc -O -o "$TMP/cf-selftest" "$1" "$TMP/main.swift" 2>"$TMP/build.log"
}

if ! build "$TMP/extracted.swift"; then
  echo "✗ harness failed to compile against the shipped source"
  grep -E 'error:' "$TMP/build.log" | head -20
  exit 1
fi
"$TMP/cf-selftest"

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a plausible
# "simplification" of the shipped logic, and each must break at least one
# assertion above. A mutation that still passes means the rule it broke was
# never actually being tested.
echo ""
echo "Mutations (each must break something)"
mutate() {
  local label="$1" sedexpr="$2"
  sed "$sedexpr" "$TMP/extracted.swift" > "$TMP/mutant.swift"
  if ! cmp -s "$TMP/extracted.swift" "$TMP/mutant.swift"; then
    if build "$TMP/mutant.swift" && "$TMP/cf-selftest" >/dev/null 2>&1; then
      echo "  ✗ $label — mutation survived, the rule is untested"
      exit 1
    fi
    echo "  ✓ $label"
  else
    echo "  ✗ $label — mutation did not apply, the harness is stale"
    exit 1
  fi
}

# Compare content only — the shape that misses a proxy flag being turned off.
mutate "content-only comparison is caught" \
  's/guard was != record.fields else { continue }/guard was.count < 3 || was[2] != record.content else { continue }/'
# Key a change on the record alone — the shape where a second change vanishes.
mutate "keying a change on the record alone is caught" \
  's|case .added, .changed: "cloudflare:dns:\\(change.record.id):\\(change.record.modifiedOn)"|case .added, .changed: "cloudflare:dns:\\(change.record.id)"|'
# Report changes only, never removals.
mutate "dropping removal detection is caught" \
  's/for (id, was) in previous where !seen.contains(id) {/for (id, was) in previous where false \&\& !seen.contains(id) { _ = id; _ = was;/'
# Forget the previous value, keeping the change itself.
mutate "losing the previous value is caught" \
  's/previousContent: was.count > 2 ? was\[2\] : nil/previousContent: nil/'

echo ""
echo "cloudflare-selftest: OK — assertions pass and every mutation was caught."
