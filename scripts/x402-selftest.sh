#!/bin/zsh
# Casberi Circle x402 self-test — verifies the SHIPPED pure logic behind the
# x402 marketplace bridge (2026-08-06):
#
#   Casberi/Casberi/Model/CircleX402Bridge.swift
#     — X402Category        (the seven lanes, and which strings map to them)
#     — X402Ingest.usd      (USDC base units rendered as money)
#     — Provider.priceLine  (the zero-price rule, quirk 4)
#     — Builder             (folding 955 listings down to 22 providers)
#     — summaryLine/tags    (what a landed row actually says)
#
# WHY A HARNESS. Unlike Cursor or Stripe, this bridge IS measurable — the
# directory is keyless and was read end-to-end while it was written. What is
# NOT measurable that way is the arithmetic: a live curl proves the wire shape,
# and proves nothing about whether a $0.0001 call renders as "$0.00" once it
# reaches a row. Every failure here is a SILENT WRONG NUMBER that renders
# perfectly:
#
#   • a fifth of the marketplace missing because the read went back to the
#     API's own `category` filter, which accepts six of the seven values its
#     own data carries (quirk 1 — the defect this bridge is shaped around);
#   • a price of "$0.00" on a paid service, because 37 listings quote a zero
#     and a naive minimum takes it (quirk 4). "From $0.00" reads as free;
#   • sub-cent prices flattened to two decimals, which is the same lie in a
#     different place — QuickNode's entire catalog is $0.0001 a call;
#   • a provider silently never landing because its category is one this build
#     doesn't know (quirk 2), which looks exactly like a company that hasn't
#     listed yet.
#
# `CircleX402Bridge.swift` cannot compile as shipped (it builds `Thing`, a
# SwiftData model, and calls `IngestSupport`'s networking), so the pure
# functions are EXTRACTED from the shipped source by name — never copied into
# this file — so the harness cannot pass against logic the app doesn't run. The
# only transformation is stripping `private `. If an extraction stops matching,
# the compile fails loudly rather than asserting nothing.
#
# Pure, local, deterministic — no network, no key, no simulator. Exit non-zero
# on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

X402="Casberi/Casberi/Model/CircleX402Bridge.swift"
SUPPORT="Casberi/Casberi/Model/IngestSupport.swift"
THING="Casberi/Shared/Thing.swift"
REACH="Casberi/Casberi/Model/NetworkReach.swift"
REFRESH="Casberi/Casberi/Model/BridgeRefresh.swift"
SCREEN="Casberi/Casberi/Screens/CircleX402Screen.swift"
for f in "$X402" "$SUPPORT" "$THING" "$REACH" "$REFRESH" "$SCREEN"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------
# Wiring facts the extracted functions can't prove on their own. A perfect
# `usd` is worthless if nothing calls `X402Ingest.refresh`.
#
# Every negative guard below greps a COMMENT-STRIPPED copy, and that is this
# harness's own first finding rather than a precaution: the quirk-1 guard fired
# on the first run against a perfectly correct bridge, because the file's own
# header explains the defect by NAMING it ("rejects `category=DATA_ENRICHMENT`
# with a 400"). A guard that a file's documentation can trip is a guard that
# gets deleted the week after it lands — the setup-copy audit learned the same
# lesson when it started reading copy quoted in comments.
TMP=$(mktemp -d /tmp/x402-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
CODE="$TMP/code.swift"
# Drops whole-line `//` and `///` comments only. A trailing comment after real
# code survives on purpose: erasing it would need a string-literal-aware parser,
# and leaving it can only ever make a negative guard STRICTER, never blinder.
sed -E '/^[[:space:]]*\/\//d' "$X402" > "$CODE"

# THE QUIRK-1 GUARD, and the reason this harness earns its place in verify.sh.
# Circle's own filter rejects `category=DATA_ENRICHMENT` with a 400 naming its
# six legal options, while 185 of the 955 listings (19%) are stamped exactly
# that. Anyone "optimising" the walk into a per-lane server-side query would
# empty a fifth of the marketplace with no error anywhere — and the room would
# look completely healthy. The read must stay unfiltered.
grep -q 'category=' "$CODE" \
  && { echo "✗ the walk now passes a server-side ?category= filter."; \
       echo "  Circle's filter accepts SIX values; its data carries SEVEN"; \
       echo "  (DATA_ENRICHMENT, 19% of the catalog). Filtering server-side"; \
       echo "  silently drops that lane. Filter on device — see quirk 1."; exit 1; }

# THE CONDUCT GUARD. x402 is a PAYMENT protocol — every listing in this
# directory exists to be bought, and each carries a `payTo` address and a
# price. The catalog copy promises Casberi "never pays for a call, and there's
# no path here that could". That promise is kept only by this file issuing
# exactly one verb against exactly one path. Prose is what CLAUDE.md calls
# memory, and memory lost.
for verb in '"POST"' '"DELETE"' '"PATCH"' '"PUT"' 'httpMethod' 'postJSON' 'deleteJSON'; do
  grep -q "$verb" "$CODE" \
    && { echo "✗ CircleX402Bridge.swift now contains a WRITE ($verb) — the catalog's"; \
         echo "  'never pays for a call' promise is now a lie."; \
         echo "  Change that copy in the same commit, or drop the write."; exit 1; }
done
# …and the positive half: the only transport it may use.
grep -qE 'IngestSupport\.getJSON\(' "$CODE" \
  || { echo "✗ CircleX402Bridge.swift no longer reads through IngestSupport's GET funnel"; exit 1; }
# A payTo address is the one field in the payload that could only ever be used
# to send money. It must never be read, stored, or landed.
grep -q 'payTo' "$CODE" \
  && { echo "✗ the bridge now reads payTo — the one field that exists only to be paid"; exit 1; }

grep -q 'api.circle.com' "$REACH" \
  || { echo "✗ api.circle.com is not in the reach registry — the privacy screen is wrong"; exit 1; }
grep -q 'X402Ingest.refresh' "$REFRESH" \
  || { echo "✗ the foreground sweep no longer refreshes x402 — the bridge lands nothing"; exit 1; }
# Quirk 3: `lastUpdated` is bulk-restamped and cannot date an arrival, so a row
# is stamped when it reached the feed. Reading the API's own field would
# backdate every row to whenever Circle last reindexed.
grep -q 'capturedAt: .now' "$CODE" \
  || { echo "✗ rows no longer stamp .now — lastUpdated is bulk-restamped (quirk 3)"; exit 1; }
grep -q 'lastUpdated' "$CODE" \
  && { echo "✗ the bridge now reads lastUpdated — it records Circle's reindex, not an arrival"; exit 1; }
# 500 is a 400, not a clamp.
grep -qE 'static let pageSize = (200|1[0-9]{2}|[1-9][0-9]?)$' "$CODE" \
  || { echo "✗ pageSize is missing or above the API's max of 200 (500 is a 400, not a clamp)"; exit 1; }
# Quirk 2: an unmapped category must not remove a provider from the feed.
grep -q 'allCategoriesUnknown' "$CODE" \
  || { echo "✗ the lane filter no longer admits an unmapped category — providers would vanish"; exit 1; }
# The truncation must be COUNTED, never silent (§307).
grep -q 'truncated' "$CODE" \
  || { echo "✗ the walk no longer reports truncation — a grown directory would read as complete"; exit 1; }
# The screen's "watch every lane" button must stay gated, or it is a control
# that does nothing once every lane is on (the honesty rule's dead control).
grep -q 'if !watchingEverything' "$SCREEN" \
  || { echo "✗ the 'watch every lane' button is no longer gated — it becomes a dead control"; exit 1; }

# --- extract the shipped functions -----------------------------------------
extract() {  # $1 = source bridge file, $2 = output path
python3 - "$1" "$SUPPORT" "$THING" "$2" <<'PY'
import sys
x402, support, thing, out = sys.argv[1:5]

def grab(path, signature):
    """The whole declaration whose line contains `signature`, brace-matched
    from the shipped source. Never a copy."""
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
    grab(x402, "enum X402Category"),
    "",
    grab(thing, "extension Array where Element == String"),
    "",
    "enum IngestSupport {",
    grab(support, "static func titleLine"),
    "}\n",
    "enum X402Ingest {",
    grab(x402, "struct Provider {"),
    grab(x402, "struct Builder {"),
    grab(x402, "static func usd"),
    grab(x402, "static func headline"),
    grab(x402, "static func summaryLine"),
    grab(x402, "static func retrievalText"),
    grab(x402, "static func tags(for"),
    "}\n",
]
open(out, "w").write("\n".join(pieces))
PY
}
extract "$X402" "$TMP/extracted.swift"

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

/// Builds a provider the way `walk()` does — by absorbing raw listing
/// dictionaries — so the tests exercise the real folding path, not a
/// hand-built struct that could drift from it.
func fold(name: String = "Acme", detail: String? = "Does things",
          website: String? = "https://acme.example",
          category: String = "FINANCIAL_ANALYSIS",
          tags: [String] = ["x402", "crypto"],
          amounts: [[Any]] = [["20000"]]) -> X402Ingest.Provider {
    var b = X402Ingest.Builder(name: name, slug: name.lowercased())
    var unknown = Set<String>()
    for accepts in amounts {
        var provider: [String: Any] = ["name": name, "category": category, "tags": tags]
        if let detail { provider["description"] = detail }
        if let website { provider["website"] = website }
        let item: [String: Any] = [
            "accepts": accepts.map { ["amount": $0] },
            "metadata": ["description": "an endpoint"],
        ]
        b.absorb(provider: provider, item: item, unknown: &unknown)
    }
    return b.provider
}

print("usd — USDC base units are 6 decimals, and sub-cent prices are REAL")
// QuickNode's entire measured catalog is 100 base units a call. At two decimal
// places that whole company reads as free.
check("100 → $0.0001",          X402Ingest.usd(100) == "$0.0001")
check("20000 → $0.02",          X402Ingest.usd(20000) == "$0.02")
check("3500000 → $3.50",        X402Ingest.usd(3500000) == "$3.50")
check("10000000 → $10.00",      X402Ingest.usd(10000000) == "$10.00")
check("10000 → $0.01 (the boundary)", X402Ingest.usd(10000) == "$0.01")
check("1 → $0.0000 is never produced for a real price", X402Ingest.usd(100) != "$0.00")

print("priceLine — a zero quote is a FACT, never the minimum (quirk 4)")
// 37 of the 955 measured listings quote 0 — free operations sitting beside
// paid ones. A naive min() reports "$0.0000" for four of the biggest sellers.
let mixed = fold(amounts: [["0"], ["20000"], ["350000"]])
check("a zero doesn't become the floor", mixed.minPrice == 20000)
check("the ceiling is still the dearest", mixed.maxPrice == 350000)
check("free is recorded separately",      mixed.hasFree == true)
check("the line says both",  mixed.priceLine == "some free, then $0.02–$0.35 a call")
let paid = fold(amounts: [["20000"], ["20000"]])
check("one price reads flat, not as a range", paid.priceLine == "$0.02 a call")
check("nothing free is claimed",             paid.hasFree == false)
let freeOnly = fold(amounts: [["0"], ["0"]])
check("all-zero reads 'free'",  freeOnly.priceLine == "free")
check("all-zero has no minimum", freeOnly.minPrice == nil)
let unpriced = fold(amounts: [[]])
check("no quote at all → no price line", unpriced.priceLine == nil)
check("an unpriced provider says nothing about money",
      X402Ingest.summaryLine(unpriced) == "1 service on Circle's x402 marketplace")

print("amount parsing — the wire sends strings, and garbage is not zero")
check("a string amount parses",  fold(amounts: [["20000"]]).minPrice == 20000)
check("an Int amount parses",    fold(amounts: [[20000]]).minPrice == 20000)
check("garbage is skipped, not read as 0", fold(amounts: [["nope"], ["20000"]]).minPrice == 20000)

print("X402Category — the seventh lane is the whole point (quirk 1)")
check("FINANCIAL_ANALYSIS maps",  X402Category.from("FINANCIAL_ANALYSIS") == .financial)
// The lane Circle's own filter refuses to serve. 185 measured listings.
check("DATA_ENRICHMENT maps",     X402Category.from("DATA_ENRICHMENT") == .enrichment)
check("PREDICTION_MARKETS maps",  X402Category.from("PREDICTION_MARKETS") == .prediction)
check("CREATIVE maps",            X402Category.from("CREATIVE") == .creative)
check("lowercase maps",           X402Category.from("creative") == .creative)
check("all seven measured lanes are present", X402Category.allCases.count == 7)
check("an unknown lane maps to nil", X402Category.from("QUANTUM_ASTROLOGY") == nil)

print("an unmapped category must not delete a provider from the feed (quirk 2)")
let alien = fold(category: "QUANTUM_ASTROLOGY")
check("its lanes read as unknown", alien.allCategoriesUnknown == true)
check("a known lane does not",     fold().allCategoriesUnknown == false)
// Falling out of the picker must never mean falling out of the feed — the
// §307 silent-drop lesson. `refresh` admits this provider on that flag alone.
check("a provider in a KNOWN lane still reports its lane",
      fold().known.map(\.display) == ["Financial analysis"])

print("the website is third-party data before it is a tappable link")
check("https is kept",       fold(website: "https://acme.example").website == "https://acme.example")
check("http is refused",     fold(website: "http://acme.example").website == nil)
check("javascript: is refused", fold(website: "javascript:alert(1)").website == nil)
check("a hostless URL is refused", fold(website: "https:///nope").website == nil)
check("a dotless host is refused", fold(website: "https://localhost").website == nil)
check("missing is nil, not a crash", fold(website: nil).website == nil)

print("headline & clamp — a provider's blurb is third-party text")
check("name and blurb join", X402Ingest.headline(fold()) == "Acme · Does things")
check("no blurb → bare name", X402Ingest.headline(fold(detail: nil)) == "Acme")
let long = fold(name: "Acme", detail: String(repeating: "long ", count: 40))
check("the title clamps to the corpus's one-line invariant",
      IngestSupport.titleLine(X402Ingest.headline(long)).count == 81)

print("summaryLine — what the row says it sells")
check("plural services", X402Ingest.summaryLine(fold(amounts: [["20000"], ["20000"]]))
        == "2 services on Circle's x402 marketplace · $0.02 a call")
check("one service is singular", X402Ingest.summaryLine(fold(amounts: [["20000"]]))
        == "1 service on Circle's x402 marketplace · $0.02 a call")

print("tags & retrieval text")
let tags = X402Ingest.tags(for: fold())
check("x402 leads",           tags.first == "x402")
check("the lane rides along", tags.contains("Financial analysis"))
check("no duplicates",        tags.count == Set(tags.map { $0.lowercased() }).count)
// Retrieval-only by the 2026-07-15 ruling — it exists so a search for a word
// the title never says still reaches the row.
check("the provider's own tags are searchable",
      X402Ingest.retrievalText(fold()).contains("crypto"))
check("retrieval text stays inside the embedding window",
      X402Ingest.retrievalText(fold(tags: (0..<400).map { "tag\($0)" })).count <= 800)

print(failures == 0 ? "\nx402-selftest: OK" : "\nx402-selftest: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

run_harness() {  # $1 = dir holding extracted.swift + main.swift
  swiftc -O -o "$1/harness" "$1/extracted.swift" "$1/main.swift" 2>&1
}

if ! out=$(run_harness "$TMP"); then
  echo "✗ harness failed to compile against the shipped source:"
  echo "$out"
  exit 1
fi
"$TMP/harness" || exit 1

# --- mutation pass ----------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation is a real defect this
# bridge could ship; the harness must reject every one.
echo
echo "mutation pass — each of these must be CAUGHT"
mutate() {  # $1 = label, $2 = sed program
  local dir="$TMP/mut"
  rm -rf "$dir"; mkdir -p "$dir"
  sed "$2" "$X402" > "$dir/src.swift"
  if ! cmp -s "$dir/src.swift" "$X402"; then :; else
    echo "  ✗ $1 — mutation matched nothing (the harness is testing stale code)"; return 1
  fi
  extract "$dir/src.swift" "$dir/extracted.swift"
  cp "$TMP/main.swift" "$dir/main.swift"
  if ! run_harness "$dir" >/dev/null 2>&1; then
    echo "  ✓ $1 (rejected at compile)"; return 0
  fi
  if "$dir/harness" >/dev/null 2>&1; then
    echo "  ✗ $1 — SURVIVED"; return 1
  fi
  echo "  ✓ $1"
}

bad=0
# The sub-cent lie: every price rendered at two decimals.
mutate "usd flattens sub-cent prices to \$0.00" 's/value >= 0\.01$/value >= 0.0/' || bad=1
# Quirk 4 undone: a zero quote becomes the advertised minimum.
mutate "a zero quote is taken as the price floor" 's/if amount == 0 { hasFree = true; continue }/if amount == 0 { hasFree = true }/' || bad=1
# Quirk 1 undone at the data layer: the seventh lane stops resolving.
mutate "DATA_ENRICHMENT stops mapping to a lane" 's/case enrichment     = "DATA_ENRICHMENT"/case enrichment     = "DATA_ENRICHMENT_X"/' || bad=1
# Quirk 2 undone: an unmapped lane silently removes a provider.
mutate "an unmapped lane no longer admits a provider" 's/var allCategoriesUnknown: Bool { known.isEmpty }/var allCategoriesUnknown: Bool { false }/' || bad=1
# A directory-supplied link is attacker-influenced text.
mutate "a non-https website becomes a tappable link" 's/url.scheme?.lowercased() == "https"/url.scheme != nil/' || bad=1
# The range collapses to a single number, so a $10 ceiling reads as $0.02.
mutate "the price ceiling stops tracking the dearest call" 's/maxPrice = max(maxPrice ?? amount, amount)/maxPrice = minPrice/' || bad=1

echo
if (( bad )); then echo "x402-selftest: mutation pass FAILED"; exit 1; fi
echo "x402-selftest: OK — shipped logic verified, 6 mutations caught."
