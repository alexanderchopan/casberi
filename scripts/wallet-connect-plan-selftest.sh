#!/bin/zsh
# Casberi WalletConnect-picker self-test — the SHIPPED arithmetic behind the
# connect picker (2026-08-13, prd §376):
#
#   Casberi/Casberi/Model/WalletConnectPlan.swift
#     — matchKey / isHexAddress  (two spellings of one wallet are one row)
#     — make                     (the rows, their order, what's pre-ticked)
#     — Plan.overflow / selectionCeiling / canPick  (the watch cap, in numbers)
#
# That file is Foundation-only BY DESIGN, so it is compiled WHOLE AND
# UNMODIFIED here — no extraction, no `private ` stripping, no copy. Every
# assertion below is about the bytes the app runs.
#
# WHY A HARNESS, and why this one earns its place: the bug this feature fixes
# was invisible for the life of the WalletConnect door. `watchConnected` looped
# `WalletStore.add` over every shared account and reported trouble ONLY when
# every single add failed — so watching three wallets and then connecting one
# sharing four landed two, dropped two, and said "connected". Nobody can catch
# that by using the app: you do not know how many accounts your wallet chose to
# share, so there is no number to notice was wrong. It is prd §307/§309's
# silent-truncation class with the report made structurally impossible.
#
# Every mutation below is therefore a SILENT WRONG ANSWER — the class that
# renders perfectly and reads as working:
#
#   • a sheet that opens with more rows ticked than its own Add button will
#     accept (silent truncation again, now wearing a picker);
#   • `overflow` counted against rows instead of pickable ones, so a person
#     watching two of the three addresses their wallet shared is told one
#     "can't be watched" when there is room for it;
#   • an EVM address arriving in a different case than it is watched in, read
#     as new — the row is offered, `add` refuses it as a duplicate, and the
#     refusal is exactly the silence this replaced;
#   • the same lowercasing applied to Solana, folding two genuinely different
#     wallets into one and discarding the second;
#   • a found Safe pre-ticked, which watches something the person never chose —
#     the old silent add's actual sin, one road over.
#
# The DRIFT GUARDS cover the wiring the pure file cannot prove — chiefly that
# `WalletScreen` no longer bulk-adds, and that this file's two restatements of
# `WalletStore`/`ENS` rules still match their originals.
#
# Pure, local, deterministic — no network, no simulator, no wallet. Exit
# non-zero on failure.
set -euo pipefail
cd "$(dirname "$0")/.."

PLAN="Casberi/Casberi/Model/WalletConnectPlan.swift"
SCREEN="Casberi/Casberi/Screens/WalletScreen.swift"
SHEET="Casberi/Casberi/Screens/WalletConnectPickerSheet.swift"
STORE="Casberi/Casberi/Model/WalletStore.swift"
ENSF="Casberi/Casberi/Model/ENS.swift"
BRIDGE="Casberi/Casberi/Model/WalletConnectBridge.swift"
SAFE="Casberi/Casberi/Model/SafeBridge.swift"
for f in "$PLAN" "$SCREEN" "$SHEET" "$STORE" "$ENSF" "$BRIDGE" "$SAFE"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

# --- drift guards -----------------------------------------------------------

# THE GUARD THIS HARNESS EXISTS FOR. `WalletScreen` must not watch a connected
# account itself — everything the session shares goes to the picker, or the
# cap eats the overflow in silence again.
#
# CODE ONLY: `showConnectPicker`'s own doc comment describes the deleted loop
# verbatim so the next reader knows what not to write, so a guard grepping raw
# source fires on the prose explaining the bug it guards against (the
# Obsidian/Cursor lesson, earned again here on this guard's first run).
CODE=$(mktemp /tmp/wcplan-code.XXXXXX)
trap 'rm -f "$CODE"' EXIT
grep -vE '^[[:space:]]*(//|\*|/\*)' "$SCREEN" > "$CODE"
grep -qE 'wallet\.(add|outcome\(ofAdding:)[^)]*account\.address' "$CODE" \
  && { echo "✗ WalletScreen watches a connected account directly again — the watch"; \
       echo "  cap will drop the overflow with no word to anyone (prd §376)"; exit 1; }
grep -qE 'func watchConnected' "$CODE" \
  && { echo "✗ watchConnected is back — it is the silent bulk-add itself"; exit 1; }
grep -q 'showConnectPicker(found)' "$CODE" \
  || { echo "✗ a settled session no longer routes to the picker"; exit 1; }
grep -q 'case .connectPicker' "$CODE" \
  || { echo "✗ the picker is no longer on WalletScreen's single sheet route —"; \
       echo "  a fourth sibling .sheet self-dismisses the first tap (FeedScreen's lesson)"; exit 1; }

# The sheet must open on the PLAN's preselection, never its own. A sheet that
# ticks its own boxes can tick more than the Add button will take.
grep -q 'picked = plan.preselected' "$SHEET" \
  || { echo "✗ the picker no longer opens on the plan's preselection"; exit 1; }
# …and must gate every pick on the ceiling, or the cap is decorative.
grep -q 'plan.canPick(picked)' "$SHEET" \
  || { echo "✗ the picker no longer gates a pick on the cap — selecting past the"; \
       echo "  limit would land as a silent refusal, the exact bug this replaced"; exit 1; }

# The two restatements. Each is a copy of a rule that lives elsewhere, and a
# copy that drifts is worse than no copy: the sheet would offer a row that
# `WalletStore.add` then refuses as a duplicate.
grep -q 'ENS.isHexAddress(address) ? address.lowercased() : address' "$STORE" \
  || { echo "✗ WalletStore.dedupeKey no longer spells the rule WalletConnectPlan.matchKey"; \
       echo "  mirrors — the picker's duplicate test and the store's would disagree"; exit 1; }
grep -q 'isHexAddress(address) ? address.lowercased() : address' "$PLAN" \
  || { echo "✗ WalletConnectPlan.matchKey no longer mirrors WalletStore.dedupeKey"; exit 1; }
grep -q 'guard t.hasPrefix("0x"), t.count == 42 else { return false }' "$ENSF" \
  || { echo "✗ ENS.isHexAddress changed shape — WalletConnectPlan restates it"; exit 1; }
grep -q 'guard t.hasPrefix("0x"), t.count == 42 else { return false }' "$PLAN" \
  || { echo "✗ WalletConnectPlan.isHexAddress no longer mirrors ENS.isHexAddress"; exit 1; }
# The namespace constant is spelled in both files because the plan is
# Foundation-only and cannot import the SDK.
grep -q 'static let evmNamespace = "eip155"' "$BRIDGE" \
  || { echo "✗ WalletConnectBridge.evmNamespace changed"; exit 1; }
grep -q 'static let evmNamespace = "eip155"' "$PLAN" \
  || { echo "✗ WalletConnectPlan.evmNamespace no longer matches the bridge's"; exit 1; }

# The Safe lookup's spam filter. `/owners/{addr}/safes/` answers for ANY
# address ever named an owner and nothing requires that owner's consent —
# measured 2026-07-30, vitalik.eth returns 59 on eth alone, overwhelmingly not
# his. Both halves are load-bearing: `nonce > 0` costs a decoy's deployer real
# gas, and the live owner check turns "was named" into "is one now".
grep -q 'detail.nonce > 0' "$SAFE" \
  || { echo "✗ the connect lookup no longer requires an EXECUTED Safe — a free"; \
       echo "  spam-deployed decoy naming a stranger would be offered to watch"; exit 1; }
grep -q 'detail.config.owners.contains(owner.lowercased())' "$SAFE" \
  || { echo "✗ the connect lookup no longer confirms CURRENT ownership — a removed"; \
       echo "  signer would be offered a wallet they can no longer act on"; exit 1; }
# "Couldn't look" must survive to the copy, or an unreachable host renders as
# "you sign on no Safes" — a claim we don't have (§85).
grep -q 'var reachable = true' "$SAFE" \
  || { echo "✗ SignerLookup no longer separates unreachable from empty"; exit 1; }
grep -q 'lookup.reachable' "$SHEET" \
  || { echo "✗ the picker no longer says when the Safe read couldn't run"; exit 1; }

TMP=$(mktemp -d /tmp/wcplan-selftest.XXXXXX)
trap 'rm -f "$CODE"; rm -rf "$TMP"' EXIT

# --- the driver -------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ label: String, _ ok: Bool) {
    if ok { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
}

typealias Plan = WalletConnectPlan
let A = "0xAAAA1111bbbb2222CCCC3333dddd4444EEEE5555"   // mixed EIP-55 case
let B = "0xBBBB1111bbbb2222CCCC3333dddd4444EEEE6666"
let C = "0xCCCC1111bbbb2222CCCC3333dddd4444EEEE7777"
let D = "0xDDDD1111bbbb2222CCCC3333dddd4444EEEE8888"
let SAFE1 = "0x5AFE1111bbbb2222CCCC3333dddd4444EEEE9999"
let SOL  = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU"
let SOL2 = "7XKXTG2CW87D97TXJSDPBD5JBKHETQA83TZRUJOSGASU"   // same letters, other case

func shared(_ xs: [String]) -> [(address: String, namespace: String)] {
    xs.map { (address: $0, namespace: Plan.isHexAddress($0) ? "eip155" : "solana") }
}

// ── the comparison form ────────────────────────────────────────────────────
print("matchKey — two spellings of one wallet are one row")
do {
    check("EVM case collapses (EIP-55 case is a checksum, not identity)",
          Plan.matchKey(A) == Plan.matchKey(A.lowercased()))
    check("…and uppercased too", Plan.matchKey(A) == Plan.matchKey(A.uppercased()))
    // The asymmetry that matters: base58 case IS identity.
    check("Solana case is PRESERVED — lowercasing folds distinct wallets",
          Plan.matchKey(SOL) != Plan.matchKey(SOL2))
    check("a Solana address is untouched", Plan.matchKey(SOL) == SOL)
    check("hex is recognised", Plan.isHexAddress(A))
    check("base58 is not hex", !Plan.isHexAddress(SOL))
    check("a short hex string is not an address", !Plan.isHexAddress("0xabc"))
    check("a 42-char non-hex string is not an address",
          !Plan.isHexAddress("0xZZZZ1111bbbb2222CCCC3333dddd4444EEEE5555"))
}

// ── the rows ───────────────────────────────────────────────────────────────
print("make — order, dedupe, and where a row came from")
do {
    let p = Plan.make(shared: shared([A, B]),
                      safes: [Plan.FoundSafe(address: SAFE1, owner: A, chain: "eth")],
                      watched: [], limit: 5)
    check("every shared account is a row", p.rows.count == 3)
    check("shared come first, in the order the session sent them",
          p.rows[0].address == A && p.rows[1].address == B)
    check("found Safes come after", p.rows[2].address == SAFE1)
    check("a shared row knows it", p.rows[0].origin.isShared)
    check("a found row carries WHY it's here",
          p.rows[2].origin == .safe(via: A, chain: "eth"))
    check("a Safe row is EVM", p.rows[2].namespace == "eip155")
    check("the address is kept as it arrived, not normalised", p.rows[0].address == A)
    // With more room than rows the ceiling is the ROW COUNT, not the room —
    // otherwise `canPick` stays true after everything is already picked, and
    // the sheet's gate is measuring the wrong quantity.
    check("plenty of room: the ceiling is what there is to pick",
          p.roomLeft == 5 && p.selectionCeiling == 3)
    check("nothing more can be picked once everything is",
          !p.canPick(Set(p.rows.map(\.key))))
}
do {
    // An address reached by BOTH roads must be one row — two would consume two
    // watch slots for one wallet and let `add` refuse the second in silence.
    let p = Plan.make(shared: shared([A]),
                      safes: [Plan.FoundSafe(address: A.lowercased(), owner: B, chain: "eth")],
                      watched: [], limit: 5)
    check("shared AND found is ONE row", p.rows.count == 1)
    check("…and the shared origin wins (you were handed it, we didn't find it)",
          p.rows[0].origin.isShared)
}
do {
    let p = Plan.make(shared: shared([A, A.lowercased(), A.uppercased()]),
                      safes: [], watched: [], limit: 5)
    check("one wallet in three cases is one row", p.rows.count == 1)
}

// ── already watching ───────────────────────────────────────────────────────
print("already watching — shown, never pickable, never counted as new")
do {
    // Watched in the OTHER case: the store would refuse this as a duplicate,
    // so the sheet must not offer it.
    let p = Plan.make(shared: shared([A, B]), safes: [],
                      watched: [A.lowercased()], limit: 5)
    check("a watched address is marked however it's cased", p.rows[0].alreadyWatching)
    check("…and the other is not", !p.rows[1].alreadyWatching)
    check("only the new one is pickable", p.pickable.map(\.address) == [B])
    check("a watched row is never pre-ticked", !p.preselected.contains(p.rows[0].key))
    check("the new one is", p.preselected.contains(p.rows[1].key))
}

// ── the cap, which is the whole point ──────────────────────────────────────
print("the watch cap — the arithmetic that used to happen in silence")
do {
    let p = Plan.make(shared: shared([A, B, C, D]), safes: [],
                      watched: ["0x1111111111111111111111111111111111111111",
                                "0x2222222222222222222222222222222222222222",
                                "0x3333333333333333333333333333333333333333"],
                      limit: 5)
    check("room is measured against the watch list", p.roomLeft == 2)
    check("four shared, two fit", p.pickable.count == 4 && p.selectionCeiling == 2)
    // THE NUMBER THAT WAS MISSING. Before this type, nothing anywhere in the
    // app represented "two of these cannot be watched" — which is precisely
    // why the old path could drop them without a word.
    check("overflow names what cannot fit", p.overflow == 2)
    check("preselection never exceeds the room", p.preselected.count == 2)
    check("…and preselects the first ones in order",
          p.preselected == Set([p.rows[0].key, p.rows[1].key]))
    check("a pick is refused once the ceiling is reached",
          !p.canPick(Set([p.rows[0].key, p.rows[1].key])))
    check("…and allowed below it", p.canPick(Set([p.rows[0].key])))
}
do {
    let p = Plan.make(shared: shared([A]), safes: [],
                      watched: ["0x1111111111111111111111111111111111111111",
                                "0x2222222222222222222222222222222222222222",
                                "0x3333333333333333333333333333333333333333",
                                "0x4444444444444444444444444444444444444444",
                                "0x5555555555555555555555555555555555555555"],
                      limit: 5)
    check("a full watch list leaves no room", p.roomLeft == 0)
    check("nothing is pre-ticked", p.preselected.isEmpty)
    check("the ceiling is zero, so the sheet can offer no pick", p.selectionCeiling == 0)
    check("…and says so: one row cannot fit", p.overflow == 1)
    check("the row is still SHOWN — hiding it would read as 'your wallet didn't share it'",
          p.rows.count == 1)
}
do {
    // §170 grandfathers an install already past the limit. The arithmetic must
    // floor at zero rather than going negative, which would make `overflow`
    // larger than the list and `selectionCeiling` nonsense.
    let over = (1...7).map { (n: Int) -> String in
        let digit = String(n)
        return "0x" + String(repeating: digit, count: 40)
    }
    let p = Plan.make(shared: shared([A]), safes: [], watched: over, limit: 5)
    check("a grandfathered over-cap list floors room at zero", p.roomLeft == 0)
    check("overflow stays sane", p.overflow == 1)
    check("the ceiling never goes negative", p.selectionCeiling == 0)
}
do {
    // Rows already watched must not be counted as overflow — telling somebody
    // their own watched wallet "can't be watched" is a false refusal.
    let p = Plan.make(shared: shared([A, B]), safes: [],
                      watched: [A, B, "0x3333333333333333333333333333333333333333",
                                "0x4444444444444444444444444444444444444444",
                                "0x5555555555555555555555555555555555555555"],
                      limit: 5)
    check("everything already watched is zero overflow", p.overflow == 0)
    check("…with nothing pickable", p.pickable.isEmpty)
}

// ── preselection's rule ────────────────────────────────────────────────────
print("preselection — what you handed over, never what we went and found")
do {
    let p = Plan.make(shared: shared([A]),
                      safes: [Plan.FoundSafe(address: SAFE1, owner: A, chain: "eth"),
                              Plan.FoundSafe(address: B, owner: A, chain: "base")],
                      watched: [], limit: 5)
    check("the shared account is ticked", p.preselected.contains(Plan.matchKey(A)))
    check("a found Safe is NOT", !p.preselected.contains(Plan.matchKey(SAFE1)))
    check("…nor the second", !p.preselected.contains(Plan.matchKey(B)))
    check("all three are still offered", p.rows.count == 3)
}
do {
    // Room for one, and the one shared account is already watched: the found
    // Safe must still not be auto-ticked just because a slot is free.
    let p = Plan.make(shared: shared([A]),
                      safes: [Plan.FoundSafe(address: SAFE1, owner: A, chain: "eth")],
                      watched: [A, "0x2222222222222222222222222222222222222222",
                                "0x3333333333333333333333333333333333333333",
                                "0x4444444444444444444444444444444444444444"],
                      limit: 5)
    check("room for one", p.roomLeft == 1)
    check("the found Safe is offered", p.pickable.map(\.address) == [SAFE1])
    check("and left un-ticked", p.preselected.isEmpty)
}

// ── stability ──────────────────────────────────────────────────────────────
print("stability — the same connect gives the same list")
do {
    let a = Plan.make(shared: shared([A, B]),
                      safes: [Plan.FoundSafe(address: SAFE1, owner: A, chain: "eth")],
                      watched: [C], limit: 5)
    let b = Plan.make(shared: shared([A, B]),
                      safes: [Plan.FoundSafe(address: SAFE1, owner: A, chain: "eth")],
                      watched: [C], limit: 5)
    check("rows are identical across builds", a.rows == b.rows)
    check("…and so is the preselection", a.preselected == b.preselected)
}

// ── empties ────────────────────────────────────────────────────────────────
print("empties")
do {
    let p = Plan.make(shared: [], safes: [], watched: [], limit: 5)
    check("no shared accounts is an empty plan", p.rows.isEmpty)
    check("…with nothing to overflow", p.overflow == 0)
    check("…and nothing ticked", p.preselected.isEmpty)
}

if failures > 0 { print("\n\(failures) failure(s)"); exit(1) }
SWIFT

echo "wallet-connect-plan self-test"
swiftc -O -o "$TMP/run" "$PLAN" "$TMP/main.swift" 2>&1 | grep -E "error" && exit 1
"$TMP/run" || exit 1

# --- mutations --------------------------------------------------------------
# A check that cannot fail proves nothing. Each mutation below is a real
# silent-wrong-answer this harness must catch.
echo
echo "mutations (each must make the harness FAIL)"
WORK="$TMP/work"; mkdir -p "$WORK"

mutate() {
  local name="$1" from="$2" to="$3"
  cp "$PLAN" "$WORK/WalletConnectPlan.swift"
  python3 - "$WORK/WalletConnectPlan.swift" "$from" "$to" <<'PY'
import sys
path, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
if frm not in src:
    print("  ✗ MUTATION IS STALE — anchor not found:", frm[:70]); sys.exit(2)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -eq 2 ]]; then exit 1; fi
  if ! swiftc -O -o "$TMP/mut" "$WORK/WalletConnectPlan.swift" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# 1. THE ORIGINAL BUG, in its new clothes: preselect everything shared,
#    ignoring the room. The sheet opens with four ticked and two slots, and
#    the Add button silently drops two — exactly what shipped.
mutate "preselection ignores the watch cap" \
  'guard preselected.count < roomLeft else { break }' \
  'guard preselected.count < Int.max else { break }'

# 2. Room unfloored — a grandfathered over-cap install goes negative, and
#    every number computed from it becomes nonsense.
mutate "room allowed to go negative" \
  'let roomLeft = max(0, limit - watchedKeys.count)' \
  'let roomLeft = limit - watchedKeys.count'

# 3. Overflow measured against ALL rows — a person watching the addresses
#    their wallet shared is told they "can't be watched".
mutate "overflow counts already-watched rows" \
  'max(0, pickable.count - roomLeft)' \
  'max(0, rows.count - roomLeft)'

# 4. The ceiling stops clamping to what's actually pickable.
mutate "the ceiling ignores how many rows there are" \
  'min(pickable.count, roomLeft)' \
  'roomLeft'

# 5. Off-by-one on the gate — one more than the cap gets picked, and the
#    refusal lands back in silence.
mutate "canPick allows one past the cap" \
  'picked.count < selectionCeiling' \
  'picked.count <= selectionCeiling'

# 6. Base58 lowercased with the hex — two genuinely different Solana wallets
#    fold into one and the second is discarded.
mutate "Solana addresses lowercased too" \
  'isHexAddress(address) ? address.lowercased() : address' \
  'address.lowercased()'

# 7. Nothing normalised — the same EVM wallet in another case reads as new,
#    is offered, and `add` refuses it silently as a duplicate.
mutate "EVM case no longer collapses" \
  'isHexAddress(address) ? address.lowercased() : address' \
  'address'

# 8. Found Safes pre-ticked — watching something nobody chose.
mutate "found Safes pre-ticked" \
  'for row in rows where row.origin.isShared && !row.alreadyWatching {' \
  'for row in rows where !row.alreadyWatching {'

# 9. An already-watched row pre-ticked — the Add button then reports a
#    refusal for a wallet that was already fine.
mutate "already-watched rows pre-ticked" \
  'row.origin.isShared && !row.alreadyWatching' \
  'row.origin.isShared'

# 10. Dedupe dropped — an address both shared and found takes two rows and
#     two watch slots for one wallet.
mutate "the shared/found dedupe removed" \
  'guard seen.insert(key).inserted else { continue }
            rows.append(Row(address: safe.address,' \
  'guard true else { continue }
            rows.append(Row(address: safe.address,'

# 11. The watched set built from raw strings — a wallet watched in another
#     case stops being recognised.
mutate "the watched set skips normalisation" \
  'Set(watched.map(matchKey))' \
  'Set(watched)'

echo
echo "✓ wallet-connect-plan self-test: assertions and mutations all passed"
