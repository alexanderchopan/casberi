#!/bin/zsh
# ENS self-test — the SHIPPED pure logic behind the ENS seat (prd §534):
#
#   Casberi/Casberi/Model/ENSName.swift
#     — normalized       (which typed/pasted strings name a followable name)
#     — stage / nextCliff (the four-rung ladder: active → expiring → grace →
#                           premium → released, and which moment is NEXT)
#     — title / tag       (the words a row wears, and its facet)
#     — facts              (parsing the registrar's own metadata payload)
#     — ref / walletRef / name(fromRef:)  (the two namespaces one name can
#                           land under, and the round trip back to a name)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no copy. Every assertion is about the
# bytes the app runs.
#
# WHY A HARNESS. Nothing on this host can make an ENS name lapse, enter its
# grace period, or get released — there is exactly one `.eth` BaseRegistrar
# and this project owns none of it. Every failure here renders as a
# perfectly ordinary row: a name shown as "expires" for the ninety days it
# has already lapsed (the exact bug `ENSExpiry` shipped with and this ladder
# exists to fix), a subname followed into a row that can never speak (the
# metadata service 404s it forever), or a lookalike name followed with no
# warning at all.
#
# WHAT IT DELIBERATELY DOES NOT PROVE. It never reaches
# metadata.ens.domains, so it says nothing about whether that service still
# answers, or in what shape. That is `-ensProbe`'s job.
#
# Pure, local, deterministic — no network, no simulator, no key. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Casberi/Casberi/Model/ENSName.swift"
BRIDGE="Casberi/Casberi/Model/ENSBridge.swift"
EXPIRY="Casberi/Casberi/Model/ENSExpiry.swift"
CATALOG="Casberi/Casberi/Model/BridgeCatalog.swift"
for f in "$NAME" "$BRIDGE" "$EXPIRY" "$CATALOG"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d /tmp/ens-selftest.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# A COMMENT-STRIPPED copy for every negative guard. `ENSBridge.swift` documents
# its own rules by naming what they must not do ("never registers or renews"),
# so a guard grepping raw source fires on the prose explaining it (the
# Obsidian/Cursor lesson).
strip() {
  python3 - "$1" <<'PY'
import re, sys
for line in open(sys.argv[1]).read().split("\n"):
    if line.strip().startswith("//"):
        continue
    print(re.sub(r'\s//(?!/).*$', '', line))
PY
}
strip "$BRIDGE" > "$TMP/bridge.stripped"
strip "$EXPIRY" > "$TMP/expiry.stripped"

# --- drift guards ------------------------------------------------------------

# EVERY TAG THIS SEAT STAMPS MUST BE RULED MECHANICAL (prd §540).
# `theme-tags-audit.py` cannot see these and says so in its own header: it reads
# `tags:` / `tags =` / `tags.append` LITERALS, and these are returned from
# `ENSName.tag(for:)` as a switch and stamped through a variable. §534 ruled two
# of the six and missed four, with every check in the repo green — the rungs
# were landing on real rows and clustering in the Themes map as though "Expiring"
# were something somebody's corpus is about. So the guard lives here, where the
# tags are actually written.
COMPOSITION="Casberi/Casberi/GenUI/HomeComposition.swift"
for tag in Expiring Grace Released Available Renewed Registered; do
  grep -q "\"$tag\"" "$COMPOSITION" \
    || { echo "✗ the ENS tag '$tag' is not ruled in HomeComposition.mechanicalTags —"; \
         echo "  it would cluster in the Themes map as a subject. theme-tags-audit.py"; \
         echo "  CANNOT catch this: these tags are returned from a switch, not stamped"; \
         echo "  as a literal, which is that audit's own stated blind spot."; exit 1; }
done

# Facts the compiled functions can't prove: a perfect ladder is worthless if
# the two halves that share one name never look at it the same way.

# ONE ladder. `ENSExpiry`'s title/cliff must come from `ENSName`, never a
# second spelling — two ladders is how a wallet-found name and a followed name
# disagree about where they stand.
grep -q 'ENSName.title(name: name, expiry: expiry)' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer builds its title through ENSName — a second"; \
       echo "  wording is how the wallet room and the ENS room start disagreeing"; exit 1; }
grep -q 'ENSName.nextCliff(expiry: expiry)' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer stamps dueAt from ENSName.nextCliff — a lapsed"; \
       echo "  name would sit overdue against its EXPIRY forever instead of stepping"; \
       echo "  to the next real cliff (grace ending)"; exit 1; }

# ONE-NAME-ONE-ROW. `ENSExpiry` must stand down for a name the seat follows,
# or the two halves land two rows counting down to the same moment.
grep -q 'ENSWatch.followed(context: context)' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer drops names the ENS seat follows — a followed"; \
       echo "  name would get a second row from the wallet sweep"; exit 1; }

# ADOPTION reads the WALLET namespace and writes the SEAT namespace — the two
# prefixes must stay distinct, or a follow could adopt (or orphan) the wrong row.
grep -q 'ENSName.walletRef(for: name)' "$TMP/bridge.stripped" \
  || { echo "✗ ENSWatch.follow no longer checks the wallet namespace for adoption"; exit 1; }
python3 - "$NAME" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
seat = re.search(r'refPrefix = "([^"]+)"', src)
wallet = re.search(r'walletRefPrefix = "([^"]+)"', src)
if not seat or not wallet:
    print("✗ could not find both ref prefixes in ENSName.swift"); sys.exit(1)
a, b = seat.group(1), wallet.group(1)
if a == b or a.startswith(b) or b.startswith(a):
    print(f"✗ the seat prefix ({a!r}) and the wallet prefix ({b!r}) overlap —");
    print("  a scan for one namespace would also match the other")
    sys.exit(1)
PY

# NEVER REGISTERS OR RENEWS. The seat's whole promise is that a signature
# happens elsewhere (§112) — no write verb, no calldata, anywhere in the file.
for verb in 'httpMethod = "POST"' 'httpMethod = "PUT"' 'httpMethod = "DELETE"' 'postJSON'; do
  grep -qF -- "$verb" "$TMP/bridge.stripped" \
    && { echo "✗ ENSBridge.swift contains a write verb ($verb) — this seat must never"; \
         echo "  register or renew a name, only read and follow"; exit 1; }
done

# The catalog offer exists, is a real seat (not `alsoReads`-only), and sits in
# the Wallet group with every other keyless follow-a-thing seat.
grep -q 'Offer(name: "ENS"' "$CATALOG" \
  || { echo "✗ no ENS offer in BridgeCatalog"; exit 1; }
grep -q 'Offer(name: "ENS".*group: "Wallet"' "$CATALOG" \
  || { echo "✗ the ENS offer is not in the Wallet group"; exit 1; }

# §515a's tripwire, restated for THIS seat: `alsoReads` is for a protocol
# read on the person's behalf that lands no rows of its own — ENS lands rows
# under its own source, so it must never list itself there (the mistake this
# harness exists to catch before it becomes a habit).
python3 - "$CATALOG" <<'PY' || exit 1
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'Offer\(name: "ENS".*?\n(?:.*\n)*?\s*(?:needsSetup|added):', src)
block = m.group(0) if m else ""
also = re.search(r'alsoReads: \[(.*?)\]', block)
if also and '"ENS"' in also.group(1):
    print("✗ the ENS offer names itself in alsoReads — that list is for protocols")
    print("  with no seat of their own, and ENS has one")
    sys.exit(1)
PY

echo "✓ drift guards passed"
echo

# --- the driver ---------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

let ref = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14, a stable "now"
let day: TimeInterval = 86_400

// ── normalized — which typed/pasted strings name a followable name ─────────
print("normalized — accepted forms")
check("a bare .eth name", ENSName.normalized("vitalik.eth") == "vitalik.eth")
check("uppercase is folded", ENSName.normalized("Vitalik.ETH") == "vitalik.eth")
check("whitespace is trimmed", ENSName.normalized("  vitalik.eth \n") == "vitalik.eth")
check("a bare label gets .eth appended", ENSName.normalized("vitalik") == "vitalik.eth")
check("an app.ens.domains link", ENSName.normalized("https://app.ens.domains/name/vitalik.eth") == "vitalik.eth")
check("a link with a trailing path segment",
      ENSName.normalized("https://app.ens.domains/name/vitalik.eth/details") == "vitalik.eth")
check("a link with a query string",
      ENSName.normalized("https://app.ens.domains/name/vitalik.eth?tab=records") == "vitalik.eth")

print("\nnormalized — the refusals")
check("a .com is refused — DNS expiry, not a registrar one",
      ENSName.normalized("example.com") == nil)
check("a subname is refused — its lifetime is its parent's",
      ENSName.normalized("sub.vitalik.eth") == nil)
check("a bare TLD-less multi-label subname is refused",
      ENSName.normalized("a.b.eth") == nil)
check("empty is refused", ENSName.normalized("") == nil)
check("whitespace-only is refused", ENSName.normalized("   ") == nil)
// THE SECURITY RULE: the name is percent-encoded into a URL path.
check("a slash is refused", ENSName.normalized("vita/lik.eth") == nil)
check("a parent walk is refused", ENSName.normalized("../vitalik.eth") == nil)
check("a space inside the name is refused", ENSName.normalized("vita lik.eth") == nil)
check("an @ is refused", ENSName.normalized("vita@lik.eth") == nil)
check("a fragment is refused", ENSName.normalized("vita#lik.eth") == nil)
check("a link to something other than /name/ falls through to the bare-label path",
      ENSName.normalized("https://app.ens.domains/") == nil)

// ── ref / walletRef / name(fromRef:) — the round trip ───────────────────────
print("\nref — one name, one identity per namespace")
check("the seat ref", ENSName.ref(for: "vitalik.eth") == "ens:name:vitalik.eth")
check("the wallet ref", ENSName.walletRef(for: "vitalik.eth") == "wallet:ensexpiry:vitalik.eth")
check("the seat ref round-trips", ENSName.name(fromRef: ENSName.ref(for: "vitalik.eth")) == "vitalik.eth")
check("a wallet ref is not a seat ref", ENSName.name(fromRef: ENSName.walletRef(for: "vitalik.eth")) == nil)
check("an unrelated ref is not a seat ref", ENSName.name(fromRef: "wallet:approval:0x1") == nil)
check("an empty-name ref is refused", ENSName.name(fromRef: "ens:name:") == nil)

// ── label — the registrar's own key ─────────────────────────────────────────
print("\nlabel — the registrar's own key")
check("the label is everything before .eth", ENSName.label(of: "vitalik.eth") == "vitalik")
check("a subname has no single label", ENSName.label(of: "sub.vitalik.eth") == nil)
check("a non-.eth name has no label", ENSName.label(of: "vitalik.box") == nil)

// ── stage — the four-rung ladder ────────────────────────────────────────────
print("\nstage — where a name stands")
check("no expiry at all is unregistered", ENSName.stage(expiry: nil, now: ref) == .unregistered)
check("far in the future is active",
      ENSName.stage(expiry: ref.addingTimeInterval(400 * day), now: ref) == .active)
check("inside the 90-day horizon is expiring",
      ENSName.stage(expiry: ref.addingTimeInterval(30 * day), now: ref) == .expiring)
check("exactly at the horizon boundary is expiring",
      ENSName.stage(expiry: ref.addingTimeInterval(Double(ENSName.horizonDays) * day), now: ref) == .expiring)
check("one second past expiry is grace, not expiring",
      ENSName.stage(expiry: ref.addingTimeInterval(-1), now: ref) == .grace)
check("59 days lapsed is still grace (under the 90-day window)",
      ENSName.stage(expiry: ref.addingTimeInterval(-59 * day), now: ref) == .grace)
check("91 days lapsed is past grace — premium",
      ENSName.stage(expiry: ref.addingTimeInterval(-91 * day), now: ref) == .premium)
check("91 + 20 days lapsed is still premium (under the 21-day window)",
      ENSName.stage(expiry: ref.addingTimeInterval(-(91 + 20) * day), now: ref) == .premium)
check("91 + 22 days lapsed is released — the premium has decayed",
      ENSName.stage(expiry: ref.addingTimeInterval(-(91 + 22) * day), now: ref) == .released)

// ── nextCliff — what dueAt carries ──────────────────────────────────────────
print("\nnextCliff — the NEXT moment, not the expiry forever")
check("active: the cliff is the expiry itself",
      ENSName.nextCliff(expiry: ref.addingTimeInterval(400 * day), now: ref)
        == ref.addingTimeInterval(400 * day))
check("grace: the cliff is when grace ends, not the expiry that already passed",
      ENSName.nextCliff(expiry: ref.addingTimeInterval(-10 * day), now: ref)
        == ENSName.graceEnd(expiry: ref.addingTimeInterval(-10 * day)))
check("premium: the cliff is when the premium decays away",
      ENSName.nextCliff(expiry: ref.addingTimeInterval(-100 * day), now: ref)
        == ENSName.premiumEnd(expiry: ref.addingTimeInterval(-100 * day)))
check("released: nothing is ahead — nil, not a stale date",
      ENSName.nextCliff(expiry: ref.addingTimeInterval(-200 * day), now: ref) == nil)
check("unregistered: nothing is ahead",
      ENSName.nextCliff(expiry: nil, now: ref) == nil)

// ── title — present tense follows the STAGE, not the raw date ──────────────
print("\ntitle — the tense follows the stage")
let activeExpiry = ref.addingTimeInterval(10 * day)
check("active reads 'expires', future tense",
      ENSName.title(name: "vitalik.eth", expiry: activeExpiry, now: ref).contains("expires"))
let graceExpiry = ref.addingTimeInterval(-5 * day)
check("grace reads 'expired', past tense — it already happened",
      ENSName.title(name: "vitalik.eth", expiry: graceExpiry, now: ref).contains("expired"))
check("grace says it can still be renewed",
      ENSName.title(name: "vitalik.eth", expiry: graceExpiry, now: ref).lowercased().contains("still be renewed"))
// §540. MEASURED 2026-08-31 by reading the deployed controller: `renew` has NO
// owner check — anyone can renew any name. So a grace title must NOT say the
// owner is the only one who can act, which is what this file said until §540.
// Wrong in the direction that talks somebody out of an act they could take.
check("grace never claims only the owner can renew",
      !ENSName.title(name: "vitalik.eth", expiry: graceExpiry, now: ref).lowercased().contains("owner"))
let releasedExpiry = ref.addingTimeInterval(-200 * day)
check("released never says 'expires' or 'expired' — it's a different name's fate now",
      !ENSName.title(name: "vitalik.eth", expiry: releasedExpiry, now: ref).contains("expire"))
check("unregistered says nobody has registered it",
      ENSName.title(name: "brandnew.eth", expiry: nil, now: ref).lowercased().contains("nobody"))
check("no title ever says 'in N days' — a stored title starts lying the next morning",
      !ENSName.title(name: "vitalik.eth", expiry: activeExpiry, now: ref).lowercased().contains(" in "))

// ── tag — the facet, one per stage ──────────────────────────────────────────
print("\ntag — one facet, never a stack of stale ones")
check("active wears no tag — the ordinary state names nothing", ENSName.tag(for: .active) == nil)
check("expiring is tagged", ENSName.tag(for: .expiring) == "Expiring")
check("grace is tagged", ENSName.tag(for: .grace) == "Grace")
check("premium and released share a tag — both mean anyone can register it",
      ENSName.tag(for: .premium) == ENSName.tag(for: .released))
check("unregistered is tagged", ENSName.tag(for: .unregistered) == "Available")

// ── facts — parsing the registrar's own metadata payload ───────────────────
print("\nfacts — the metadata service's own shape (measured 2026-08-29)")
let payload: [String: Any] = [
    "attributes": [
        ["trait_type": "Created Date", "value": 1_497_775_154_000.0],
        ["trait_type": "Registration Date", "value": 1_581_013_420_000.0],
        ["trait_type": "Expiration Date", "value": 2_464_042_424_000.0],
    ],
    "is_normalized": true,
]
let parsed = ENSName.facts(name: "vitalik.eth", json: payload)
check("expiry is read as MILLISECONDS, not seconds",
      parsed?.expiry == Date(timeIntervalSince1970: 2_464_042_424))
check("registration date is read", parsed?.registered == Date(timeIntervalSince1970: 1_581_013_420))
check("created date is read", parsed?.created == Date(timeIntervalSince1970: 1_497_775_154))
check("is_normalized is carried through", parsed?.isNormalized == true)
let lookalike: [String: Any] = ["attributes": [] as [[String: Any]], "is_normalized": false]
check("a lookalike name is flagged", ENSName.facts(name: "vitalıc.eth", json: lookalike)?.isNormalized == false)
check("a missing is_normalized key defaults to normalized — an unrecognised payload must not warn about every name at once",
      ENSName.facts(name: "vitalik.eth", json: ["attributes": [] as [[String: Any]]])?.isNormalized == true)
check("no attributes at all still parses (an unregistered-name-shaped payload)",
      ENSName.facts(name: "x.eth", json: ["attributes": [] as [[String: Any]]])?.expiry == nil)
check("not a dictionary at all yields nil", ENSName.facts(name: "x.eth", json: "not json") == nil)
check("a zero-valued expiry is dropped, never read as epoch zero",
      ENSName.facts(name: "x.eth",
                    json: ["attributes": [["trait_type": "Expiration Date", "value": 0.0]]])?.expiry == nil)

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

if ! swiftc -O -o "$TMP/run" "$NAME" "$TMP/main.swift" 2>"$TMP/build.log"; then
  echo "✗ the shipped ENSName.swift did not compile against the harness"
  grep -E 'error:' "$TMP/build.log" | head -30
  exit 1
fi
"$TMP/run"

# --- mutations ----------------------------------------------------------------
echo
echo "mutations (each must be caught)"

WORK="$TMP/work"
mutate() {
  local name="$1" from="$2" to="$3"
  rm -rf "$WORK"; mkdir -p "$WORK"
  cp "$NAME" "$WORK/ENSName.swift"
  MUT_FROM="$from" MUT_TO="$to" python3 - "$WORK/ENSName.swift" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["MUT_FROM"], os.environ["MUT_TO"]
if frm not in src:
    sys.stderr.write("ANCHOR-MISSING\n"); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$WORK/ENSName.swift"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/ENSName.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. A subname accepted — its lifetime is its parent's, and the metadata
#    service 404s it forever, so this follows a name into a row that can
#    never speak.
mutate "a subname accepted" \
  'guard labels.count == 2, labels[1] == "eth", !labels[0].isEmpty else { return nil }' \
  'guard labels.count >= 2, labels.last == "eth", !labels[0].isEmpty else { return nil }'

# 2. Any TLD accepted — a .com expires in DNS where no ENS read can see it.
mutate "any TLD accepted, not just .eth" \
  'guard labels.count == 2, labels[1] == "eth", !labels[0].isEmpty else { return nil }' \
  'guard labels.count == 2, !labels[0].isEmpty else { return nil }'

# 3. The injection guard dropped — the name is interpolated into a URL path.
mutate "the injection guard removed" \
  '$0.isWhitespace || $0 == "/" || $0 == "\\" || $0 == "@" || $0 == "#"' \
  'false'

# 4. The horizon boundary inverted — a name just inside the window reads as
#    an ordinary "active" one, so the deadline never becomes news.
mutate "the horizon comparison inverted" \
  'return expiry <= horizon ? .expiring : .active' \
  'return expiry <= horizon ? .active : .expiring'

# 5. Grace treated as still-active — the ninety days where ONLY the owner can
#    renew reads as an ordinary future expiry, which is the exact bug
#    ENSExpiry shipped with and this ladder exists to fix.
mutate "grace collapsed into active" \
  'if now < expiry {' \
  'if true {'

# 6. nextCliff returns the raw expiry through grace — a lapsed name sits
#    overdue forever instead of stepping to when grace actually ends.
mutate "nextCliff never advances past the expiry" \
  'case .grace:            return graceEnd(expiry: expiry)' \
  'case .grace:            return expiry'

# 7. A released name still returns a cliff — a stale deadline for something
#    that has already happened, forever in "Coming up".
mutate "released still returns a next cliff" \
  'case .released, .unregistered: return nil' \
  'case .unregistered: return nil'

# 8. Milliseconds read as seconds — every name's expiry lands in 1970 and is
#    permanently, silently overdue (the exact unit bug ENSExpiry's own header
#    warns against).
mutate "milliseconds read as seconds" \
  'return Date(timeIntervalSince1970: ms / 1000)' \
  'return Date(timeIntervalSince1970: ms)'

# 9. A zero-valued expiry accepted — epoch zero read as a real date.
mutate "a zero expiry accepted" \
  'if let ms = attribute["value"] as? Double, ms > 0 {' \
  'if let ms = attribute["value"] as? Double {'

# 10. is_normalized read as false by default — every name with an
#     unrecognised payload would warn as a lookalike (the lint-that-cries-wolf
#     failure).
mutate "is_normalized defaults to false" \
  'isNormalized: (root["is_normalized"] as? Bool) ?? true)' \
  'isNormalized: (root["is_normalized"] as? Bool) ?? false)'

echo
echo "✓ ens-selftest passed"
