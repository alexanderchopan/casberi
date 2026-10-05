#!/bin/zsh
# Apple's receipt mails, read strictly (`Model/AppleReceipts.swift`), compiled
# AS SHIPPED — Foundation-only, so no stubs and no copied logic.
#
# EVERY FIXTURE BELOW IS SYNTHETIC. No real Apple receipt was available when
# the reader was written; the texts here are made up to the layouts the reader
# ASSUMES (each marked UNMEASURED in the source). This harness therefore
# proves ONE thing — that the reader FAILS CLOSED — and nothing about whether
# a real receipt is handled. That second question is answered only by
# `-appleReceiptProbe fetch` over a real inbox.
#
# What it catches, each of which would otherwise put a guessed app name
# beside a real charge:
#
#   • a mail from anybody, with an Apple-looking body, read as a receipt
#   • a lookalike domain (`notapple.com`, `apple.com.evil.example`) let in
#   • a half-recognised body yielding a partial line (items that do not sum
#     to the total, a priced block that is not an item, a label stated twice)
#   • a charge matched to a receipt weeks away, or to the first of two apps
#     that fit equally
#   • the probe's layout dump carrying the mail's own words into the log
#   • the reader wired into anything but the probe
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/AppleReceipts.swift"
HOOKS="Casberi/Casberi/Shell/ProbeHooks.swift"
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

// SYNTHETIC senders. The first three are at Apple's registrable domains; the
// rest are the lookalikes the gate exists for.
let apple = "no_reply@email.apple.com"
for good in [apple, "x@apple.com", "do_not_reply@itunes.com", "X@Email.Apple.COM"] {
    check(AppleReceipts.isAppleSender(good), "an address at Apple's domain passes: \(good)")
}
for bad in ["no_reply@notapple.com", "no_reply@apple.com.evil.example", "no_reply@email.apple.co",
            "no_reply@\u{0430}pple.com", "no_reply@apple.com.", "Apple <no_reply@evil.example>",
            "a@b@apple.com", "@apple.com", "apple.com", "no_reply@apple-com.example",
            "no_reply@.apple.com", "no_reply@email..apple.com", ""] {
    check(!AppleReceipts.isAppleSender(bad), "a lookalike is refused: \(bad)")
}
check(!AppleReceipts.isAppleSender(nil), "no address, no sender")

// SYNTHETIC receipt, to the itemised layout the reader assumes.
let receiptSubject = "Your receipt from Apple."
let receipt = """
Apple Receipt

APPLE ID
someone@fixture.example

ORDER ID
MSYNTH0001

DATE
Oct 2, 2026

Quillmark
Pro (Monthly)
Renews Nov 2, 2026
$9.99

TOTAL $9.99

Get help with subscriptions and purchases.
"""
let one = AppleReceipts.parse(sender: apple, subject: receiptSubject, text: receipt)
check(one.count == 1, "a whole receipt reads one line")
check(one.first?.app == "Quillmark" && one.first?.item == "Pro (Monthly)", "the app and its plan")
check(one.first?.amount == 9.99 && one.first?.symbol == "$", "the price and its mark")
check(one.first?.currency == nil, "a bare $ names no one currency")
check(one.first?.renews == AppleReceipts.date("Nov 2, 2026") && one.first?.renews != nil, "the renewal date, stated by month name")

// THE GATE: the same body from anybody else is nothing.
check(AppleReceipts.parse(sender: "billing@shop.example", subject: receiptSubject, text: receipt).isEmpty,
      "a non-Apple sender with an Apple-looking body yields nothing")
check(AppleReceipts.parse(sender: "no_reply@email.apple.com.evil.example", subject: receiptSubject, text: receipt).isEmpty,
      "a lookalike domain with the same body yields nothing")
check(AppleReceipts.parse(sender: "no_reply@notapple.com", subject: receiptSubject, text: receipt).isEmpty,
      "a suffix lookalike with the same body yields nothing")
check(AppleReceipts.parse(sender: nil, subject: receiptSubject, text: receipt).isEmpty,
      "a mail with no sender address yields nothing")
check(AppleReceipts.parse(sender: apple, subject: "A new sign-in to your account", text: receipt).isEmpty,
      "a subject of no known class is never read")

// Two items and tax: lines are the items, the total is the charge.
let two = """
ORDER ID: MSYNTH0002

Quillmark
Pro (Monthly)
$9.99

Tidepool
Family (Yearly)
Renews Oct 2, 2027
$40.00

Subtotal $49.99
Tax $4.00
TOTAL $53.99
"""
let twoLines = AppleReceipts.parse(sender: apple, subject: receiptSubject, text: two)
check(twoLines.map(\.app) == ["Quillmark", "Tidepool"], "two items, in order")
check(AppleReceipts.receipt(sender: apple, subject: receiptSubject, text: two, date: Date())?.total == 53.99,
      "the total is what was charged, tax in")

// HALF-RECOGNISED BODIES: each is nothing, never a partial reading.
func none(_ text: String, _ why: String, subject: String = receiptSubject) {
    check(AppleReceipts.parse(sender: apple, subject: subject, text: text).isEmpty, why)
}
none(receipt.replacingOccurrences(of: "ORDER ID\nMSYNTH0001\n\n", with: ""), "no Order ID: not a receipt")
none(receipt.replacingOccurrences(of: "TOTAL $9.99", with: "TOTAL $19.99"), "items that do not sum to the total")
none(receipt.replacingOccurrences(of: "TOTAL $9.99\n", with: ""), "no total")
none(receipt + "\nTOTAL $9.99\n", "two totals")
none(receipt.replacingOccurrences(of: "TOTAL $9.99", with: "$5.00\n\nTOTAL $9.99"), "a priced block that is not an item")
none(receipt.replacingOccurrences(of: "Pro (Monthly)", with: "$4.99"), "a price in the middle of an item")
none(receipt.replacingOccurrences(of: "TOTAL $9.99", with: "TOTAL €9.99"), "two currency marks in one receipt")
none(receipt.replacingOccurrences(of: "$9.99\n\nTOTAL $9.99", with: "$9.99\nTOTAL $9.99"), "an item run into the total")
none(receipt.replacingOccurrences(of: "$9.99\n\nTOTAL", with: "9.99 dollars\n\nTOTAL"), "a price in a spelling not in the table")
none(receipt.replacingOccurrences(of: "Quillmark\n", with: "Quillmark\nOne\nTwo\nThree\n"), "an item block longer than the layout")
none("ORDER ID: MSYNTH0003\n\nQuillmarkPro (Monthly)$9.99\n\nTOTAL $9.99", "table cells run together by an HTML strip")
none("", "an empty body")

// SYNTHETIC confirmation, to the labelled layout the reader assumes.
let confirmSubject = "Your Subscription Confirmation"
let confirm = """
Subscription Confirmation

App                 Quillmark
Subscription        Pro (Monthly)
Content Provider    Quillmark Ltd
Renewal Price       $9.99/month
Renewal Date        Nov 2, 2026
"""
let c = AppleReceipts.parse(sender: apple, subject: confirmSubject, text: confirm)
check(c.count == 1 && c.first?.app == "Quillmark" && c.first?.amount == 9.99, "a labelled confirmation reads one line")
check(c.first?.item == "Pro (Monthly)" && c.first?.renews != nil, "its plan and its renewal date")
let stacked = "App\nQuillmark\n\nRenewal Price\nUS$9.99\n"
let s = AppleReceipts.parse(sender: apple, subject: "Your subscription is renewing", text: stacked)
check(s.first?.app == "Quillmark" && s.first?.currency == "USD", "a label on its own line takes the next line; US$ is USD")
none(confirm + "\nApp                 Tidepool\n", "an app stated twice", subject: confirmSubject)
none(confirm.replacingOccurrences(of: "Renewal Price       $9.99/month\n", with: ""), "an app with no price", subject: confirmSubject)
none(confirm.replacingOccurrences(of: "$9.99/month", with: "$9.99 - $19.99"), "a price range", subject: confirmSubject)
none(confirm.replacingOccurrences(of: "App                 Quillmark\n", with: ""), "a price with no app", subject: confirmSubject)
none("App\nRenewal Price\n$9.99", "a label followed by a label", subject: confirmSubject)
none(confirm, "a confirmation's layout under a receipt's subject")
none(confirm, "an expiring notice is not read", subject: "Your subscription is expiring")
check(AppleReceipts.parse(sender: "billing@shop.example", subject: confirmSubject, text: confirm).isEmpty,
      "a non-Apple sender with a confirmation's body yields nothing")

// PRICES and DATES: one spelling each way, or nothing.
check(AppleReceipts.price("$9.99", allowPeriod: false)?.amount == 9.99, "$9.99")
check(AppleReceipts.price("US$1,299.00", allowPeriod: false)?.amount == 1299, "US$1,299.00")
check(AppleReceipts.price("9,99 €", allowPeriod: false)?.currency == "EUR", "9,99 € is euros")
check(AppleReceipts.price("¥980", allowPeriod: false)?.currency == nil, "¥ names no one currency")
for bad in ["$9.9", "-$9.99", "$1,29.00", "9.99", "$9.99 each", "$", "$9.99/month", "about $9.99"] {
    check(AppleReceipts.price(bad, allowPeriod: false) == nil, "not a price: \(bad)")
}
check(AppleReceipts.price("$9.99/month", allowPeriod: true)?.amount == 9.99, "a period is dropped where one is allowed")
check(AppleReceipts.date("11/02/2026") == nil, "a slash date reads two ways and is refused")
check(AppleReceipts.date("Nov 2, 2026 or so") == nil, "a date with words after it is refused")
check(AppleReceipts.date("2026-11-02") == AppleReceipts.date("November 2, 2026"), "ISO and the month's name agree")

// THE MATCH: a cent, three days, one app — or no name.
let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func days(_ d: Double) -> Date { t0.addingTimeInterval(d * 86_400) }
func line(_ app: String, _ amount: Double, code: String? = nil, mark: String = "$") -> AppleReceipts.Line {
    .init(app: app, item: nil, amount: amount, symbol: mark, currency: code, renews: nil)
}
let r1 = AppleReceipts.Receipt(date: t0, lines: [line("Quillmark", 9.99)], total: 9.99)
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: days(2), in: [r1]) == .app("Quillmark"), "same price, two days on")
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: days(-3), in: [r1]) == .app("Quillmark"), "three days is inside")
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: days(4), in: [r1]) == .none, "four days is outside")
check(AppleReceipts.match(amount: 10.01, currency: "USD", at: t0, in: [r1]) == .none, "two cents is not a cent")
check(AppleReceipts.match(amount: 9.99, currency: "EUR", at: t0, in: [r1]) == .none, "a $ line is not a euro charge")
let r2 = AppleReceipts.Receipt(date: days(1), lines: [line("Tidepool", 9.99)], total: 9.99)
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: t0, in: [r1, r2]) == .ambiguous, "two apps at one price: no name")
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: t0, in: [r1, r1]) == .app("Quillmark"), "the same app twice is one app")
let taxed = AppleReceipts.Receipt(date: t0, lines: [line("Quillmark", 9.99)], total: 10.81)
check(AppleReceipts.match(amount: 10.81, currency: "USD", at: t0, in: [taxed]) == .app("Quillmark"), "a one-item total with tax is that item")
let basket = AppleReceipts.Receipt(date: t0, lines: [line("Quillmark", 9.99), line("Tidepool", 40)], total: 53.99)
check(AppleReceipts.match(amount: 53.99, currency: "USD", at: t0, in: [basket]) == .ambiguous, "a several-item total names no one app")
check(AppleReceipts.match(amount: 40, currency: "USD", at: t0, in: [basket]) == .app("Tidepool"), "a line of a basket names its app")
let euro = AppleReceipts.Receipt(date: t0, lines: [line("Quillmark", 9.99, code: "EUR", mark: "€")], total: 9.99)
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: t0, in: [euro]) == .none, "a euro line is not a dollar charge")
check(AppleReceipts.match(amount: 9.99, currency: "USD", at: t0, in: []) == .none, "no receipts, no name")

// The descriptors a charge arrives under: exact, never a substring.
for yes in ["Apple", "APPLE.COM/BILL", " apple services ", "APL*ITUNES.COM/BILL", "APL* APPLE.COM/BILL"] {
    check(AppleReceipts.isAppleBilling(merchant: yes), "an App Store descriptor: \(yes)")
}
for no in ["Applebee's", "Pineapple Express", "Apple Store Fifth Avenue", "Snapple", ""] {
    check(!AppleReceipts.isAppleBilling(merchant: no), "not the App Store: \(no)")
}

// THE LAYOUT DUMP carries the layout and none of the mail.
let skeleton = AppleReceipts.skeleton(receipt).joined(separator: "\n")
for secret in ["Quillmark", "quillmark", "someone", "fixture", "MSYNTH0001", "9.99", "Monthly)", "2026", "Oct"] {
    check(!skeleton.contains(secret), "the layout dump does not carry \(secret)")
}
check(skeleton.contains("order id") && skeleton.contains("total <price>") && skeleton.contains("renews w 9"),
      "the layout dump keeps the receipt's own words and shapes")
check(AppleReceipts.skeleton(String(repeating: "x\n", count: 500)).count <= 60, "the layout dump is bounded")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   sender gate, both layouts, fail-closed bodies, prices, dates, match, layout dump")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/AppleReceipts.swift"
build "$work/AppleReceipts.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutations=0
mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  # A mutant that does not COMPILE proves nothing and would print a passing
  # line all the same, so it fails the harness instead.
  build "$work/m.swift" || { cat "$work/err"; fail "mutation does not compile: $why"; }
  if "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  mutations=$((mutations + 1))
  echo "  ok   catches  $why"
}

mutate "the sender gate dropped from the reader" \
  's/guard isAppleSender\(sender\) else \{ return nil \}/_ = sender/'
mutate "a suffix lookalike let in (notapple.com)" \
  's/host\.hasSuffix\("\." \+ \$0\)/host.hasSuffix(\$0)/'
mutate "the domain matched by contains (apple.com.evil.example)" \
  's/host == \$0 \|\| host\.hasSuffix\("\." \+ \$0\)/host.contains(\$0)/'
mutate "a subject of no known class read as a receipt" \
  's/case \.expiring, \.other:        return nil/case .expiring, .other:        return itemised(text)/'
mutate "a receipt read without its Order ID" \
  's/guard all\.contains\(where: \{ \$0\.lowercased\(\) == "order id" \|\| \$0\.lowercased\(\)\.hasPrefix\("order id:"\) \}\)\n        else \{ return nil \}/_ = all/'
mutate "items that do not sum to the total still read" \
  's/guard abs\(sum - against\) < 0\.005 else \{ return nil \}//'
mutate "a priced block that is not an item skipped instead of voiding the mail" \
  's/guard \(2\.\.\.5\)\.contains\(block\.count\), isName\(block\[0\]\) else \{ return nil \}/guard (2...5).contains(block.count), isName(block[0]) else { continue }/'
mutate "two currency marks in one receipt" \
  's/guard marks\.count == 1 else \{ return nil \}//'
mutate "an app stated twice takes the first" \
  's/if hits\.count > 1 \{ return \.none \}//'
mutate "a bare \$ assumed to be US dollars" \
  's/\("\$", nil\), \("€"/("\$", "USD"), ("€"/'
mutate "a slash date believed (leniency on)" \
  's#if let d = f\.date\(from: s\), f\.string\(from: d\)\.lowercased\(\) == s\.lowercased\(\) \{ return d \}#if let d = f.date(from: s) { return d }\n            f.dateFormat = "MM/dd/yyyy"; if let d = f.date(from: s) { return d }#'
mutate "a charge matched to a receipt a month away" \
  's/static let matchDays = 3\.0/static let matchDays = 30.0/'
mutate "a charge matched two cents off" \
  's/static let matchCents = 0\.01/static let matchCents = 0.05/'
mutate "two apps at one price resolved to one of them" \
  's/if apps\.count == 1, !ambiguous, let app = apps\.first \{ return \.app\(app\) \}/if let app = apps.sorted().first { return .app(app) }/'
mutate "a several-item total named after its first item" \
  's/if r\.lines\.count == 1 \{ apps\.insert\(first\.app\) \} else \{ ambiguous = true \}/apps.insert(first.app)/'
mutate "a dollar line matched to any currency" \
  's/case "\$": return \["USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN"\]\.contains\(currency\)/case "\$": return true/'
mutate "the layout dump carrying the mail's own words" \
  's/\{ token = "w" \}/{ token = w }/'
mutate "the layout dump carrying the mail's numbers" \
  's/\{ token = "9" \}/{ token = w }/'
mutate "an App Store descriptor matched by substring (Pineapple Express)" \
  's/\]\.contains\(m\)\n    \}/].contains { m.contains(\$0) }\n    }/'

# The reader is a MEASUREMENT: it is called from the probe and nowhere else.
# The day a real inbox has been measured and a ruling wires it in, this guard
# is amended by that ruling — not deleted to get a build through.
callers=$(grep -rl "AppleReceipts\." Casberi --include='*.swift' | grep -v "$SRC" | sort | tr '\n' ' ')
[[ "$callers" == "$HOOKS " ]] \
  || fail "AppleReceipts is referenced outside the probe ($callers) — an unmeasured reader may not name a real charge"
grep -q "UNMEASURED" "$SRC" || fail "drift: the source no longer marks its assumptions UNMEASURED"
grep -q 'Hook(key: "appleReceiptProbe")' "$HOOKS" || fail "drift: the -appleReceiptProbe hook is gone"
# The hook that connects a real inbox takes an app password on the command
# line; `probeArgs:` must not print it.
grep -q '"-mailBridge",' "$HOOKS" || fail "drift: -mailBridge is no longer redacted in probeArgs"
# The probe's log: no subject, no address. It formats a class and counts.
if grep -n 'NSLog("appleReceipt' "$HOOKS" -A4 | grep -E 'mail\.subject|mail\.sender|fromAddress|provider\.address' >/dev/null; then
  fail "the probe logs a subject or an address"
fi
if [[ -z "${APPLE_RECEIPTS_PREMERGE:-}" ]]; then
  grep -q "apple-receipts-selftest.sh" "$VERIFY" \
    || fail "not wired into verify.sh — the completeness guard requires it, with its reason"
fi

echo "✓ apple receipts: fail-closed reader over SYNTHETIC fixtures, $mutations mutations (the real format is unmeasured)"
