#!/bin/zsh
# Billers in the address book (prd §1106), compiled AS SHIPPED.
#
# `Model/Billers.swift`, the `Subscriptions.swift` it composes through, the
# `AppleWalletRoom.swift` and `RoomLede.swift` those read, and the address
# index's `ContactIndex.swift` + `ContactLinks.swift` are Foundation-only, so
# this compiles them WHOLE — no stubs, no copied logic.
# Every failure it catches renders as an ordinary-looking address book:
#
#   • the power bill missing, because only one-price plans were let in
#   • a weekly coffee shop filed as a biller
#   • a plan you cancelled still standing as a biller
#   • one plan listed twice, once as a subscription and once as a biller
#   • a moving bill marked a subscription, so its page says "Renews"
#   • a charge's merchant keyed differently from the biller, so its page
#     shows no charges and Recent never files it
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/Billers.swift"
SUBS="Casberi/Casberi/Model/Subscriptions.swift"
AWR="Casberi/Casberi/Model/AppleWalletRoom.swift"
LEDE="Casberi/Casberi/Model/RoomLede.swift"
INDEX="Casberi/Casberi/Model/ContactIndex.swift"
LINKS="Casberi/Casberi/Model/ContactLinks.swift"
VERIFY="scripts/verify.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!
func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

func found(_ merchant: String, _ charges: [(Double, Double)]) -> [Subscriptions.Found] {
    let spends = charges.map {
        AppleWalletRoom.Spend(merchant: merchant, amount: $0.0, currency: "USD", date: ago($0.1))
    }
    return AppleWalletRoom.recurringSeries(spends, now: now).map {
        .init(series: $0, paysWith: "Apple Card", source: "Apple Wallet", was: nil)
    }
}
func compose(_ f: [Subscriptions.Found], bills: [Subscriptions.Bill] = []) -> [Billers.Biller] {
    Billers.compose(found: f, bills: bills, manual: [], now: now, calendar: cal)
}

let claude = found("Claude", [(20, 66), (20, 36), (20, 6)])
let power  = found("PG&E", [(84.12, 66), (61.40, 36), (97.03, 6)])
let coffee = found("Blue Bottle", [(6.5, 21), (6.5, 14), (6.5, 7), (6.5, 0.5)])
// Charged monthly, then nothing for four months.
let gym    = found("Gym", [(40, 186), (40, 156), (40, 126)])
// A moving bill that stopped two months ago.
let water  = found("Water", [(30.1, 120), (41.7, 90), (35.2, 60)])

let all = compose(claude + power + coffee + gym + water)
let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.item.name, $0) })

check(byName["Claude"]?.subscription == true, "a one-price plan is a biller AND a subscription")
check(byName["PG&E"] != nil, "a bill whose amount moves is a biller")
check(byName["PG&E"]?.subscription == false, "…and never a subscription")
check(byName["PG&E"]?.item.was == nil, "a moving bill carries no price rise")
check(byName["PG&E"]?.item.paysWith == "Apple Card", "a moving bill keeps what pays it")
check(byName["Blue Bottle"] == nil, "a weekly coffee is no biller")
check(byName["Gym"] == nil, "a plan quit months ago is no biller")
check(byName["Water"] == nil, "a moving bill that stopped is no biller")
check(all.filter { $0.item.name == "Claude" }.count == 1, "a plan is listed once")

// A Rocket Money bill for the same plan merges into it, still once.
let rm = Subscriptions.Bill(name: "claude", amount: 20, currency: "USD",
                            due: now.addingTimeInterval(3 * 86_400), source: "Rocket Money")
check(compose(claude, bills: [rm]).count == 1, "a bill and a card charge for one plan are one biller")
// The card stopped, but Rocket Money still dates the next bill: it stands.
let rmGym = Subscriptions.Bill(name: "Gym", amount: 40, currency: "USD",
                               due: now.addingTimeInterval(5 * 86_400), source: "Rocket Money")
check(compose(gym, bills: [rmGym]).map(\.item.name) == ["Gym"], "a stopped card does not hide a bill another reading still dates")

// The index key: a charge's merchant must key to the biller it belongs to,
// spelled however the card spells it, and only when the caller says it is a
// billing seat's row.
let key = Identity.key(.biller, "Netflix.com")
check(key == "biller:" + Subscriptions.key("Netflix.com"), "the biller key is the subscriptions' merge key behind the prefix")
check(Identity.key(.biller, " NETFLIX.COM ") == key, "a merchant cased or padded differently is the same biller")
check(Identity.parse(key: key)?.kind == .biller, "a biller key parses back to its kind")
let charged = ContactIndex.keys(source: "Apple Wallet", kind: "transaction", sourceRef: nil,
                                authorHandle: "Apple Card, ending 4821", walletAddress: nil,
                                counterpartyAddress: nil, authorEmail: nil,
                                isNotification: false, merchant: "Netflix.com")
check(charged.contains(key), "a card charge keys to its merchant's biller")
let transfer = ContactIndex.keys(source: "Wallet", kind: "transaction", sourceRef: nil,
                                 authorHandle: nil, walletAddress: nil,
                                 counterpartyAddress: "0x" + String(repeating: "a", count: 40),
                                 authorEmail: nil, isNotification: false)
check(!transfer.contains { $0.hasPrefix("biller:") }, "a row with no merchant keys no biller")
check(Identity.Kind.allCases.last == .biller, "a biller never leads a contact anything else names")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   billers, cadence floor, stopped, merge, keys")
SWIFT

build() { swiftc -Onone -o "$work/run" "$SUBS" "$AWR" "$LEDE" "$INDEX" "$LINKS" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/Billers.swift"
build "$work/Billers.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  if build "$work/m.swift" && "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "a weekly charge let in (the cadence floor dropped)" \
  's/f\.series\.cadenceDays >= Subscriptions\.minCadenceDays/true/'
mutate "a stopped bill still standing" \
  's/!seen\.contains\(key\), !stopped\.contains\(key\)/!seen.contains(key)/'
mutate "a plan quit months ago still standing (the silences ceiling inherited)" \
  's/!stopped\.contains\(item\.id\) \|\| /true || /'
mutate "a stopped card hides a bill another reading still dates" \
  's/ \|\| item\.foundIn\.contains \{ !cards\.contains\(\$0\) \}//'
mutate "a plan listed twice" \
  's/guard !key\.isEmpty, !seen\.contains\(key\),/guard !key.isEmpty,/'
mutate "a moving bill marked a subscription" \
  's/subscription: false\)\)/subscription: true))/'
mutate "only one-price plans let in (the moving bills dropped)" \
  's/(var out = standing\.map \{ Biller\(item: \$0, subscription: true\) \})/\$1\n        return out/'

# Wiring: the index seeds billers and keys charges to them; the reading
# composes through this function; the pass runs this harness.
grep -q "Billers.compose(found: SubscriptionsSource.found" Casberi/Casberi/Model/BillersSource.swift \
  || fail "drift: BillersSource no longer composes through Billers.compose"
grep -q "BillersSource.read(context: context)" Casberi/Casberi/Model/ContactIndexSources.swift \
  || fail "drift: the address index no longer seeds billers"
grep -q "merchant: BillersSource.merchant(of: thing)" Casberi/Casberi/Model/ContactIndexSources.swift \
  || fail "drift: the activity walk no longer keys a charge to its biller (Recent and the line go quiet)"
grep -q "billers-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "✓ billers: moving bills in, weekly and stopped out, one per merchant, keys, 7 mutations"
