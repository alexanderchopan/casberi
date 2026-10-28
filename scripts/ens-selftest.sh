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
KECCAK="Casberi/Casberi/Model/Keccak256.swift"
for f in "$NAME" "$BRIDGE" "$EXPIRY" "$CATALOG" "$KECCAK"; do
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
grep -q 'ENSName.title(name: name, expiry: expiry, migrated: migrated)' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer builds its title through ENSName — a second"; \
       echo "  wording is how the wallet room and the ENS room start disagreeing"; exit 1; }
grep -q 'ENSName.nextCliff(expiry: expiry, migrated: migrated)' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer stamps dueAt from ENSName.nextCliff — a lapsed"; \
       echo "  name would sit overdue against its EXPIRY forever instead of stepping"; \
       echo "  to the next real cliff (grace ending)"; exit 1; }

# ONE PARSE. The wallet half reads the metadata through `ENSName.facts`, so an
# unmigrated name's v1 date and a migrated name's grace (prd §1585) reach both
# rooms; a second parser would read the wire's ENSv2 date as the expiry.
grep -q 'ENSName.facts(name: name, json:' "$TMP/expiry.stripped" \
  || { echo "✗ ENSExpiry no longer parses through ENSName.facts — the wallet room"; \
       echo "  would show an unmigrated name expiring 62 days after it stops working"; exit 1; }

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

// ── labelhash — the metadata service's only key since ENSv2 (prd §1573) ─────
// The vector is viem's `keccak256(toHex("vitalik"))`, an independent
// implementation; the live heartbeat reads the service at this same id.
print("\nlabelhash — the metadata service's key")
let vitalikHash = "0xaf2caa1c2ca1d027f1ac823b529d0a67cd144264b2789fa2ea4d63a67c7103cc"
check("vitalik.eth hashes its LABEL, not the name", ENSName.labelhash(of: "vitalik.eth") == vitalikHash)
check("a subname has no labelhash", ENSName.labelhash(of: "sub.vitalik.eth") == nil)
check("a DNS name has no labelhash", ENSName.labelhash(of: "vitalik.box") == nil)
check("the metadata URL is keyed by labelhash",
      ENSName.metadataURL(for: "vitalik.eth")
        == "https://metadata.ens.domains/mainnet/0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85/" + vitalikHash)
check("the metadata URL never carries the name (a 400 since ENSv2)",
      !(ENSName.metadataURL(for: "vitalik.eth") ?? "vitalik").contains("vitalik"))

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
check("59 days lapsed is still grace (an unmigrated name's 90 days)",
      ENSName.stage(expiry: ref.addingTimeInterval(-59 * day), now: ref) == .grace)
check("91 days lapsed is past grace — premium",
      ENSName.stage(expiry: ref.addingTimeInterval(-91 * day), now: ref) == .premium)
// prd §1585, MEASURED 2026-10-28: a migrated name gets `ETHRegistrar`'s 28 days
// from its ENSv2 expiry, an unmigrated one `ETHRenewerV1`'s 90 from its v1 one.
check("a migrated name 26 days lapsed is still grace",
      ENSName.stage(expiry: ref.addingTimeInterval(-26 * day), migrated: true, now: ref) == .grace)
check("a migrated name 30 days lapsed is premium, not v1's 90-day grace",
      ENSName.stage(expiry: ref.addingTimeInterval(-30 * day), migrated: true, now: ref) == .premium)
check("the two windows are 90 and 28 days",
      ENSName.graceDays(migrated: false) == 90 && ENSName.graceDays(migrated: true) == 28)
// DERIVED FROM THE SHIPPED CONSTANTS, AND NEVER ON THE BOUNDARY ITSELF.
// `graceDays + premiumDays` days lapsed IS the release moment, and the two
// fixtures here used to spell it `91 + 20` — 111 days, exactly that moment.
// Whether it read as premium or released then depended on the MACHINE:
// `stage` walks the ladder with `Calendar.current.date(byAddingDays:)`, so a
// zone that crosses a DST fall-back inside the span gains an hour and lands
// just short of `now` (premium), while UTC — every hosted runner — lands
// exactly on it and reads released. Green on the laptop, red on CI, for days,
// over a rule neither machine disagreed about.
//
// So each fixture sits two days INSIDE the window it names, which no DST
// shift can cross, and both are spelled from `ENSName`'s own constants so a
// change to either one moves the fixtures with it.
let releaseDay = Double(ENSName.unmigratedGraceDays + ENSName.premiumDays)
check("two days before the premium decays away it is still premium",
      ENSName.stage(expiry: ref.addingTimeInterval(-(releaseDay - 2) * day), now: ref) == .premium)
check("two days after it, the name is released — the premium has decayed",
      ENSName.stage(expiry: ref.addingTimeInterval(-(releaseDay + 2) * day), now: ref) == .released)

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
check("a migrated name's cliff steps on ITS grace",
      ENSName.nextCliff(expiry: ref.addingTimeInterval(-10 * day), migrated: true, now: ref)
        == ENSName.graceEnd(expiry: ref.addingTimeInterval(-10 * day), migrated: true))
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

// ── ENSv2's copy — the bonus and the re-stamped dates (prd §1585) ──────────
print("\nENSv2's copy — not a renewal, not a registration")
// vitalik.eth, measured 2026-10-28: v1 2464042424, ENSv2 2469399224.
let v1Expiry = Date(timeIntervalSince1970: 2_464_042_424)
let v2Expiry = Date(timeIntervalSince1970: 2_469_399_224)
check("the measured 62-day move is ENSv2's bonus, not a renewal",
      ENSName.isMigrationBonus(from: v1Expiry, to: v2Expiry))
check("a one-year renewal is a renewal",
      !ENSName.isMigrationBonus(from: v1Expiry, to: v1Expiry.addingTimeInterval(365 * day)))
check("a renewal on top of the bonus is a renewal",
      !ENSName.isMigrationBonus(from: v1Expiry, to: v2Expiry.addingTimeInterval(365 * day)))
// The copy stamped vitalik.eth 2026-10-03 (read 2026-10-28); this is that day.
let restamped: [String: Any] = [
    "attributes": [
        ["trait_type": "Created Date", "value": 1_791_001_680_000.0],
        ["trait_type": "Registration Date", "value": 1_791_001_680_000.0],
        ["trait_type": "Expiration Date", "value": 2_469_399_224_000.0],
    ],
]
let copied = ENSName.facts(name: "vitalik.eth", json: restamped)
check("a registration date ENSv2's copy stamped is dropped", copied?.registered == nil)
check("a created date ENSv2's copy stamped is dropped", copied?.created == nil)
check("with no Migration Status the wire's date is kept", copied?.expiry == v2Expiry)
func status(_ value: String) -> [String: Any] {
    ["attributes": [["trait_type": "Expiration Date", "value": 2_469_399_224_000.0],
                    ["trait_type": "Migration Status", "value": value]]]
}
// vitalik.eth is "unmigrated"; ENS's Explorer shows Expires Jan 30, 2048 —
// the v1 date, which the wire's ENSv2 date is 62 days past.
let unmigrated = ENSName.facts(name: "vitalik.eth", json: status("unmigrated"))
check("an unmigrated name expires on its v1 date", unmigrated?.expiry == v1Expiry)
check("an unmigrated name is not migrated", unmigrated?.migrated == false)
let migrated = ENSName.facts(name: "nick.eth", json: status("migrated"))
check("a migrated name expires on the wire's ENSv2 date", migrated?.expiry == v2Expiry)
check("a migrated name says so", migrated?.migrated == true)
// Both end grace the same day (62 + 28 = 90): the moment anyone may register
// the name does not depend on which date we show as its expiry.
if let a = ENSName.graceEnd(expiry: v1Expiry, migrated: false),
   let b = ENSName.graceEnd(expiry: v2Expiry, migrated: true) {
    check("the two readings end grace on the same day", abs(a.timeIntervalSince(b)) < 2 * 3600)
} else { check("the two readings end grace on the same day", false) }
check("a name registered after activation keeps its date",
      ENSName.facts(name: "x.eth", json: ["attributes": [
          ["trait_type": "Registration Date", "value": 1_793_100_000_000.0]]])?.registered
        == Date(timeIntervalSince1970: 1_793_100_000))

print(failures == 0 ? "\nAll assertions passed." : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

# `-Onone`, not `-O`: 97% of a pure-logic harness's wall time is the optimizer,
# and it buys nothing an assertion can see. NOT a blanket rule — `-O` can change
# a harness's OBSERVABLE behaviour (a trapping one prints NOTHING under `-O`) —
# so this file was proven equivalent run-for-run by
# `scripts/support/harness-opt-probe.sh` before the swap (2026-09-05, 2.2x faster).
# Re-probe before trusting it again after adding mutations.
if ! swiftc -Onone -o "$TMP/run" "$NAME" "$KECCAK" "$TMP/main.swift" 2>"$TMP/build.log"; then
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
  if ! swiftc -Onone -o "$TMP/mut" "$WORK/ENSName.swift" "$KECCAK" "$TMP/main.swift" 2>/dev/null; then
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
  'case .grace:            return graceEnd(expiry: expiry, migrated: migrated)' \
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

# 11. The metadata service keyed by the NAME again — what shipped until ENSv2
#     (2026-10-27), when every such read became a silent 400 (prd §1573).
mutate "the metadata URL keyed by name" \
  'labelhash(of: name).map { "https://metadata.ens.domains/mainnet/\(baseRegistrar)/\($0)" }' \
  'labelhash(of: name).map { _ in "https://metadata.ens.domains/mainnet/\(baseRegistrar)/\(name)" }'

# 12. The whole name hashed instead of its label — a well-formed id for an
#     entry nobody registered, so every name would read as unregistered.
mutate "the name hashed, not the label" \
  'return "0x" + Keccak256.hexString(Keccak256.hash(Array(label.utf8)))' \
  'return "0x" + Keccak256.hexString(Keccak256.hash(Array(name.utf8)))'

# 13. v1's 90-day grace back — 62 days of "can still be renewed" about a name
#     anyone may register (prd §1585).
mutate "a migrated name given v1's 90-day grace" \
  'static let migratedGraceDays = 28' \
  'static let migratedGraceDays = 90'

# 13b. The wire's ENSv2 date taken as an unmigrated name's expiry — it reads
#      as working for 62 days after it stopped.
mutate "an unmigrated name's v1 date not restored" \
  'expiry: status == "unmigrated" ? wire?.addingTimeInterval(-migrationBonus) : wire,' \
  'expiry: wire,'

# 14. The bonus read as a renewal — "was renewed" on every followed name the
#     day the stored v1 readings are read again.
mutate "the migration bonus counts as a renewal" \
  'abs(now.timeIntervalSince(was) - migrationBonus) < 60' \
  'false'

# 15. ENSv2's copy date kept as the term's start.
mutate "a re-stamped registration date kept" \
  'registered: date("Registration Date").flatMap { isReservationStamp($0) ? nil : $0 },' \
  'registered: date("Registration Date"),'

echo
echo "✓ ens-selftest passed"
