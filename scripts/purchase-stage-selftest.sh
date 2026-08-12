#!/bin/zsh
# purchase-stage-selftest.sh — the purchase receipt's judgement, compiled AS
# SHIPPED (prd §368).
#
# WHY THIS EXISTS. `PurchaseStage` decides what a shopping thing sheet SAYS: a
# purchase or a thing you're watching, who you paid, whether the charge is
# final, what the price fell from, and — the sentence the whole pass started
# from — where the row came from. Every failure it can have renders as a
# perfectly good-looking card: an authorization stated as settled, a deal
# introduced as "a store you follow", a grade beside a food this app never
# graded, a merchant that is really the first half of somebody's product name.
# `xcodebuild` is happy with all of them, the screen sweep passes, and nothing
# in the app can tell.
#
# HOW. `Model/PurchaseStage.swift` is Foundation-only BY DESIGN (no SwiftUI, no
# SwiftData, no `Thing`) precisely so this can compile it WHOLE and UNMODIFIED
# — the `WorkStage`/`SocialSheet`/`ASCShape` precedent. No stubs at all: what
# runs here is the shipped file, byte for byte.
#
# THE RULE IT PROTECTS (prd §340, inherited from `WorkStage`). Every joined
# title in this codebase is `String(localized:)`, so it records the merchant
# and the old price in whatever language the device was in WHEN THE ROW LANDED.
# So the archetype comes from the `sourceRef` prefix — a string this app WROTE
# — and every word returned is produced fresh. Group 8 and mutation 5 are that
# rule as a test.
#
# NOTE the negative guards read a COMMENT-STRIPPED copy. The source DOCUMENTS
# this rule by naming the very things it must not do ("never sliced out of the
# title", "parsing it back"), so a guard grepping raw source fires on the prose
# explaining it — the Obsidian/Cursor lesson, earned again here.
set -uo pipefail
ROOT="${0:a:h:h}"
SRC="$ROOT/Casberi/Casberi/Model/PurchaseStage.swift"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[[ -f "$SRC" ]] || { print -u2 "missing $SRC"; exit 1; }

# ── The harness ───────────────────────────────────────────────────────────────
cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func eq(_ label: String, _ got: String?, _ want: String?) {
    if got != want { print("FAIL \(label): got \(got ?? "nil") want \(want ?? "nil")"); failures += 1 }
}
func ok(_ label: String, _ cond: Bool) {
    if !cond { print("FAIL \(label)"); failures += 1 }
}
let day = 86_400.0
func at(_ daysAgo: Double) -> Date { Date(timeIntervalSince1970: 1_760_000_000 - daysAgo * day) }

func row(_ source: String, ref: String? = nil, kind: String = "transaction",
         title: String, tags: [String] = [], price: Double? = nil,
         currency: String? = nil, seller: String? = nil, merchant: String? = nil,
         when: Date = at(1), enriched: String? = nil) -> PurchaseStage.Row {
    PurchaseStage.Row(source: source, sourceRef: ref, kind: kind, title: title,
                      tags: tags, priceValue: price, priceCurrency: currency,
                      sellerField: seller, merchantField: merchant,
                      capturedAt: when, enrichedText: enriched)
}

// 1 ── The fork. A ref this app wrote decides it, never the price alone.
let privacy = row("Privacy", ref: "privacy:txn:abc", title: "Netflix.com · $12.99",
                  tags: ["Card", "Settled"], price: 12.99, currency: "USD",
                  merchant: "Netflix.com")
eq("privacy.archetype", PurchaseStage.archetype(privacy)?.rawValue, "receipt")
let shopify = row("Shopify", ref: "shopify:store.com:1", kind: "product",
                  title: "Cast iron pan, 26cm", price: 72, currency: "EUR",
                  seller: "Aesop")
eq("shopify.archetype", PurchaseStage.archetype(shopify)?.rawValue, "watch")
let low = row("Bitrefill", ref: "bitrefill:balance:low:1", kind: "reminder",
              title: "Your Bitrefill balance is running low — $4.20 left",
              price: 4.20, currency: "USD")
eq("alarm.archetype", PurchaseStage.archetype(low)?.rawValue, "alarm")

// 2 ── THE MEASURED REASON THE PRICE TEST ALONE IS WRONG. Railgun, Peer and
// Bitcoin all stamp a price on an ordinary transfer — two of them with a token
// SYMBOL as the currency, one with real USD. A transfer is not a purchase.
ok("railgun.silent",
   PurchaseStage.reading(row("Railgun", ref: "railgun:unshield:0xabc",
                             title: "Unshielded 0.5 ETH", price: 0.5,
                             currency: "ETH")) == nil)
ok("peer.silent",
   PurchaseStage.reading(row("Peer", ref: "peer:buy:0xabc",
                             title: "Bought 25 USDC with Venmo on Peer",
                             price: 25, currency: "USDC")) == nil)
ok("bitcoin.silent",
   PurchaseStage.reading(row("Bitcoin", ref: "btc:tx:abc", title: "Received 0.01 BTC",
                             price: 640, currency: "USD")) == nil)
ok("wallet.silent",
   PurchaseStage.reading(row("Wallet", ref: "wallet:tx:0xabc",
                             title: "Sent 0.4 ETH")) == nil)

// 3 ── The receipt. The merchant comes from the FIELD, the amount from the
// stored pair, and the subject is not the title.
let rp = PurchaseStage.reading(privacy)!
eq("privacy.verb", rp.verb, "Paid")
eq("privacy.subject", rp.subject, "Netflix.com")
eq("privacy.face", rp.face.rawValue, "money")
ok("privacy.amount.formatted", (rp.amount ?? "").contains("12.99"))
eq("privacy.state", rp.state?.word, "Settled")
eq("privacy.destination", rp.destination, "Privacy")
ok("privacy.no.seller.row", rp.seller == nil)   // the merchant IS the subject

// 4 ── A row landed before its bridge stamped the merchant keeps its title.
// Mildly redundant, never wrong — the trade this file makes everywhere.
eq("privacy.legacy.subject",
   PurchaseStage.reading(row("Privacy", ref: "privacy:txn:old",
                             title: "Netflix.com · $12.99", price: 12.99,
                             currency: "USD"))!.subject,
   "Netflix.com · $12.99")

// 5 ── SETTLED vs AUTHORIZED (the §317 lesson). Absence says nothing — never
// "Settled" by default, which is the fake status the design law bans.
eq("privacy.pending",
   PurchaseStage.reading(row("Privacy", ref: "privacy:txn:p", title: "Blue Bottle · $6.00",
                             tags: ["Card", "Pending"], price: 6, currency: "USD",
                             merchant: "Blue Bottle"))!.state?.word,
   "Not settled yet")
ok("privacy.unknown.silent",
   PurchaseStage.reading(row("Privacy", ref: "privacy:txn:u", title: "x · $1.00",
                             tags: ["Card"], price: 1, currency: "USD"))!.state == nil)
eq("applewallet.refund.tone",
   PurchaseStage.reading(row("Apple Wallet", ref: "applewallet:txn:1", title: "Refund",
                             tags: ["Card", "Refund"], price: 20, currency: "GBP",
                             merchant: "Uniqlo"))!.state?.tone.rawValue,
   "good")

// 6 ── A refill is not a purchase: different verb, and the rail earns the row
// the merchant never gets (because a merchant is already the subject).
let refill = PurchaseStage.reading(
    row("Bitrefill", ref: "bitrefill:invoice:1", kind: "link",
        title: "Balance refill · €100 in bitcoin", price: 100, currency: "EUR",
        merchant: "Bitcoin"))!
eq("refill.verb", refill.verb, "Topped up")
eq("refill.subject", refill.subject, "Balance refill")
eq("refill.party", refill.seller?.name, "Bitcoin")
eq("refill.role", refill.seller?.role, "paid with")
ok("refill.isRefill", PurchaseStage.isRefill(
    row("Bitrefill", ref: "bitrefill:invoice:1", kind: "link", title: "x")))
ok("order.isNotRefill", !PurchaseStage.isRefill(
    row("Bitrefill", ref: "bitrefill:order:1", kind: "link", title: "x")))

// 7 ── A receipt with no amount is not a receipt. Falls back to the generic
// sheet rather than drawing a hero with a hole in it.
ok("receipt.needs.amount",
   PurchaseStage.reading(row("Privacy", ref: "privacy:txn:z",
                             title: "Netflix.com", merchant: "Netflix.com")) == nil)

// 8 ── THE PROVENANCE SENTENCE — the finding that started the pass. The old
// spec row said "from a store you follow" over all three, and it is true of
// exactly one of them.
let deal = row("Deals", ref: "deals:x", kind: "product",
               title: "Anker 737 power bank — 38% off", tags: ["Deal"],
               seller: "Slickdeals")
let food = row("Open Food Facts", ref: "off:5060403320102", kind: "product",
               title: "Oat drink, barista", tags: ["Food", "Nutri-Score B"],
               seller: "Oatly")
// The user ruling (2026-08-12) that made this optional: the sentence is nil
// unless it names something the SCREEN CANNOT. `watchParty` already renders
// the role a line above ("a store you follow" / "a feed you follow" /
// "brand"), so a sentence repeating it was the same fact twice.
let bitrefill = row("Bitrefill", ref: "bitrefill:order:9", title: "Amazon gift card — $50",
                    price: 50, currency: "USD")
let refillRow = row("Bitrefill", ref: "bitrefill:invoice:9", title: "Added $50 to your balance",
                    price: 50, currency: "USD")
let gnosis = row("Gnosis Pay", ref: "gnosispay:spend:7", title: "Card spend — €18.40",
                 price: 18.40, currency: "EUR")
ok("shopify.prov.silent", PurchaseStage.provenance(shopify) == nil)
ok("food.prov.silent", PurchaseStage.provenance(food) == nil)
ok("privacy.prov.silent", PurchaseStage.provenance(privacy) == nil)
// The three that survive, each naming an absence the sheet has no field for.
ok("deals.prov.stale", PurchaseStage.provenance(deal)?.contains("stale") == true)
ok("bitrefill.prov.code", PurchaseStage.provenance(bitrefill)?.contains("code") == true)
ok("gnosis.prov.merchant", PurchaseStage.provenance(gnosis)?.contains("merchant") == true)
// A refill has no code to explain, so it says nothing.
ok("refill.prov.silent", PurchaseStage.provenance(refillRow) == nil)
// And the ROLE word, which is why the seller is a pair and not a name.
eq("shopify.role", PurchaseStage.watchParty(shopify)?.role, "a store you follow")
eq("deals.role", PurchaseStage.watchParty(deal)?.role, "a feed you follow")
eq("food.role", PurchaseStage.watchParty(food)?.role, "brand")
ok("no.seller.no.party", PurchaseStage.watchParty(
    row("Shopify", ref: "shopify:s:1", kind: "product", title: "x")) == nil)

// 9 ── State words. A drop outranks a sale: both can be true and only one is
// news.
eq("drop.beats.sale",
   PurchaseStage.watchState(row("Shopify", ref: "shopify:s:1", kind: "product",
                                title: "x", tags: ["Sale", "Price drop"]))?.word,
   "Price drop")
eq("sale.alone", PurchaseStage.watchState(
    row("Shopify", ref: "shopify:s:1", kind: "product", title: "x",
        tags: ["Sale"]))?.word, "On sale")
eq("drop.tone", PurchaseStage.watchState(
    row("Shopify", ref: "shopify:s:1", kind: "product", title: "x",
        tags: ["Price drop"]))?.tone.rawValue, "good")

// 10 ── Nutri-Score is READ, never computed, and only a real grade counts.
eq("nutri.b", PurchaseStage.nutriScore(food), "B")
ok("nutri.rejects.junk", PurchaseStage.nutriScore(
    row("Open Food Facts", ref: "off:1", kind: "product", title: "x",
        tags: ["Nutri-Score Z"])) == nil)
ok("nutri.rejects.word", PurchaseStage.nutriScore(
    row("Open Food Facts", ref: "off:1", kind: "product", title: "x",
        tags: ["Nutri-Score good"])) == nil)
ok("nutri.scoped.to.seat", PurchaseStage.nutriScore(
    row("Shopify", ref: "shopify:s:1", kind: "product", title: "x",
        tags: ["Nutri-Score A"])) == nil)

// 11 ── The barcode, out of the ref it was already sitting in.
eq("barcode.spaced", PurchaseStage.barcode(food), "5060 4033 2010 2")
ok("barcode.rejects.nondigits", PurchaseStage.barcode(
    row("Open Food Facts", ref: "off:abc", kind: "product", title: "x")) == nil)
ok("barcode.scoped", PurchaseStage.barcode(
    row("Shopify", ref: "off:123", kind: "product", title: "x")) == nil)

// 12 ── PRICE HISTORY. Round-trips, is locale-free, and every malformed shape
// is nil rather than a partial reading.
let move = PriceHistory.compose(was: 90, now: 72, currency: "EUR", wasUntil: at(7))
let parsed = PriceHistory.parse(move)!
ok("history.was", parsed.was == 90)
ok("history.now", parsed.now == 72)
eq("history.currency", parsed.currency, "EUR")
ok("history.date", abs(parsed.wasUntil.timeIntervalSince(at(7))) < 1)
ok("history.fell", parsed.fell)
ok("history.fraction", abs((parsed.fraction ?? 0) - -0.2) < 0.0001)
ok("history.rise.notfell", !PriceHistory.parse(
    PriceHistory.compose(was: 50, now: 60, currency: "USD", wasUntil: at(2)))!.fell)
ok("history.nil.on.nothing", PriceHistory.parse(nil) == nil)
ok("history.nil.on.prose", PriceHistory.parse("Was €90.00, now €72.00.") == nil)
ok("history.nil.on.short", PriceHistory.parse("pricemove/1|EUR|90.0|123") == nil)
ok("history.nil.on.garbage", PriceHistory.parse("pricemove/1|EUR|x|123|72.0") == nil)
ok("history.nil.on.zero", PriceHistory.parse("pricemove/1|EUR|0|123|72.0") == nil)
// The marker must be the FIRST line, or a note that happens to quote it wins.
ok("history.first.line.only",
   PriceHistory.parse("some words\n" + move) == nil)

// 13 ── The writer preserves a body it doesn't own, and never stacks.
let kept = PriceHistory.rewrite(existing: "a vault note's own words", with: "HEAD")
ok("rewrite.keeps.body", kept.contains("a vault note's own words"))
ok("rewrite.head.first", kept.hasPrefix("HEAD"))
let twice = PriceHistory.rewrite(
    existing: PriceHistory.rewrite(existing: "body", with: move), with: move)
ok("rewrite.idempotent",
   twice.components(separatedBy: PriceHistory.marker).count == 2)
ok("rewrite.still.has.body", twice.contains("body"))
ok("clear.drops.move", PriceHistory.clear(twice)?.contains(PriceHistory.marker) == false)
ok("clear.keeps.body", PriceHistory.clear(twice)?.contains("body") == true)
ok("clear.nil.when.empty", PriceHistory.clear(move) == nil)
ok("clear.passes.through", PriceHistory.clear("just a note") == "just a note")

// 14 ── The watch reading carries the move through.
let dropped = PurchaseStage.reading(
    row("Shopify", ref: "shopify:s:1", kind: "product", title: "Cast iron pan, 26cm",
        tags: ["Price drop"], price: 72, currency: "EUR", seller: "Aesop",
        enriched: move))!
ok("watch.history.read", dropped.history?.was == 90)
eq("watch.face", dropped.face.rawValue, "product")
ok("watch.no.verb", dropped.verb == nil)

// 15 ── Deals says its price is unread rather than leaving a gap that looks
// like a missing number — and only Deals, because only Deals never parses one.
ok("deals.says.unchecked",
   PurchaseStage.reading(deal)!.rungs.contains { $0.value == "Not checked" })
ok("shopify.no.unchecked.rung",
   !PurchaseStage.reading(row("Shopify", ref: "shopify:s:2", kind: "product",
                              title: "x", seller: "Aesop"))!
       .rungs.contains { $0.value == "Not checked" })

// 16 ── Shape tags are chrome; a person's own labels survive.
eq("labels.keep.own",
   PurchaseStage.labels(row("Shopify", ref: "shopify:s:1", kind: "product", title: "x",
                            tags: ["Sale", "Price drop", "Kitchen"]),
                        typeTags: ["Product"]).joined(separator: ","),
   "Kitchen")
ok("labels.drop.nutri",
   PurchaseStage.labels(food, typeTags: ["Product"]).isEmpty)

// 17 ── Seats with no shape here are untouched, which is what lets this land.
for source in ["Slack", "Notion", "Bluesky", "Photos", "GitHub", "Stripe"] {
    ok("silent.\(source)",
       PurchaseStage.reading(row(source, ref: "\(source):1", title: "x · y")) == nil)
}

if failures == 0 { print("purchase-stage-selftest: all assertions passed") }
exit(failures == 0 ? 0 : 1)
SWIFT

build_and_run() {  # $1 = source file to compile
  local out="$WORK/bin"
  swiftc -O "$1" "$WORK/main.swift" -o "$out" 2>"$WORK/err" || return 2
  "$out" >"$WORK/out" 2>&1
}

# ── 1. The shipped file must pass ─────────────────────────────────────────────
cp "$SRC" "$WORK/PurchaseStage.swift"
build_and_run "$WORK/PurchaseStage.swift"
case $? in
  0) : ;;
  2) print -u2 "purchase-stage-selftest: the SHIPPED source did not compile"; cat "$WORK/err"; exit 1 ;;
  *) print -u2 "purchase-stage-selftest: the shipped source FAILED its own assertions";
     cat "$WORK/out"; exit 1 ;;
esac

# ── 2. Mutations — each one a silent wrong answer this must catch ─────────────
# A mutation that fails to COMPILE, or that matches nothing (so it silently
# tests the shipped file and scores it green), is itself a failure. Both traps
# are real: `retriever-selftest` and `cursor-selftest` each paid for one.
typeset -gi MUTATIONS=0
mutate() {  # $1 = label, $2 = sed program
  local f="$WORK/mut.swift"
  sed "$2" "$SRC" > "$f"
  if cmp -s "$f" "$SRC"; then
    print -u2 "purchase-stage-selftest: mutation '$1' matched NOTHING — it proves nothing"
    exit 1
  fi
  build_and_run "$f"
  case $? in
    0) print -u2 "purchase-stage-selftest: mutation '$1' SURVIVED — the harness cannot see it";
       exit 1 ;;
    2) print -u2 "purchase-stage-selftest: mutation '$1' did not compile — rewrite it";
       cat "$WORK/err"; exit 1 ;;
    *) (( MUTATIONS++ )) ;;   # died as it should
  esac
}

# THE headline mutation: the fork stops asking the ref and asks the price, which
# is the obvious test and the wrong one. Railgun, Peer and Bitcoin get dressed
# as card purchases.
mutate "fork reads the price instead of the ref" \
  's|if purchaseRefs.contains(where: ref.hasPrefix)|if row.priceValue != nil|'

# An authorization reported as final — §317's own failure, one seat over.
mutate "an unmarked charge defaults to settled" \
  's|if tags.contains("Settled")  {|if true {|'

# The merchant gets sliced out of the localized title instead of read from the
# field — the §340 bug this whole file is shaped around.
mutate "the merchant is sliced out of the title" \
  's|return merchant.isEmpty ? row.title.trimmingCharacters(in: .whitespaces) : merchant|return String(row.title.split(separator: "·").first ?? "")|'

# The stale-price warning lost, so a deal's price reads as rechecked.
# Range-scoped: an unscoped `case "Deals":` also matches `watchParty`'s switch,
# where deleting it is a syntax error rather than the bug being modelled.
mutate "provenance loses the seat that made it necessary" \
  '/static func provenance/,/^    }$/ s|case "Deals":||'

# The ruling reverted — a sentence on every seat again, restating the role line.
mutate "provenance speaks where the screen already spoke" \
  '/static func provenance/,/^    }$/ s|return nil|return word("Read from the account you connected.")|'

# A grade this app invented rather than read.
mutate "Nutri-Score accepts any letter" \
  's|if grade.count == 1, "ABCDE".contains(grade) { return grade }|if grade.count == 1 { return grade }|'

# A sale reported as a drop, so a product that was never cheaper reads as news.
mutate "sale outranks a real price drop" \
  's|if tags.contains("Price drop") { return Badge(word: word("Price drop"), tone: .good) }||'

# A half-read price move — the partial reading the parser refuses.
mutate "price history accepts a malformed record" \
  's|guard parts.count == 4,|guard parts.count >= 2,|'

# The move stops having to be the FIRST line, so any note quoting the marker
# becomes a price claim about the product.
mutate "price history scans the whole body for its marker" \
  's|.first,$|.first(where: { $0.hasPrefix(marker) }),|'

# Re-recording stacks instead of replacing: a product that drops twice
# accumulates contradictory records and the sheet reads the oldest.
mutate "re-recording a move stops replacing the old one" \
  's|lines.removeSubrange(index..<end)|_ = end|'

# A refill claims a merchant it never had.
mutate "a refill reads as a purchase" \
  's|let refill = isRefill(row)|let refill = false|'

# ── 3. Drift guards — the wiring the compiled functions cannot prove ──────────
# Comment-stripped, because the source explains this rule by naming it.
STRIPPED="$WORK/stripped.swift"
sed -E 's@^[[:space:]]*///.*$@@; s@^[[:space:]]*//.*$@@' "$SRC" > "$STRIPPED"

guard() {  # $1 = label, $2 = pattern that MUST be present
  grep -qE "$2" "$STRIPPED" \
    || { print -u2 "purchase-stage-selftest: drift — $1"; exit 1; }
}
deny() {   # $1 = label, $2 = pattern that must NOT appear
  grep -qE "$2" "$STRIPPED" \
    && { print -u2 "purchase-stage-selftest: drift — $1"; exit 1; }
  return 0
}

# The type must stay Foundation-only, or this harness stops being able to
# compile it as shipped and the whole proof evaporates.
deny "PurchaseStage imported SwiftUI — it must stay Foundation-only" '^import SwiftUI'
deny "PurchaseStage imported SwiftData — it must stay Foundation-only" '^import SwiftData'
deny "PurchaseStage reached for Thing directly — it takes primitives (Row)" '\bThing\b'

# The two bridges this pass taught to stamp their merchant must keep doing it,
# or the receipt silently falls back to the title on every row and nothing says
# why. `transferCounterparty` is the ONE home for that fact (Apple Wallet has
# used it since §317) — a second field would let one sheet disagree with itself.
grep -qE 'thing\.transferCounterparty = ' "$ROOT/Casberi/Casberi/Model/BitrefillBridge.swift" \
  || { print -u2 "purchase-stage-selftest: drift — Bitrefill stopped stamping its merchant"; exit 1; }
grep -qE 'thing\.transferCounterparty = name' "$ROOT/Casberi/Casberi/Model/PrivacyBridge.swift" \
  || { print -u2 "purchase-stage-selftest: drift — Privacy stopped stamping its merchant"; exit 1; }
grep -qE 'settled \? "Settled" : "Pending"' "$ROOT/Casberi/Casberi/Model/PrivacyBridge.swift" \
  || { print -u2 "purchase-stage-selftest: drift — Privacy stopped marking settlement"; exit 1; }
# And both must REPAIR rows already landed, or only the half of the corpus that
# arrived after 2026-08-12 can name who you paid — a corpus silently
# half-covered reads as complete.
for f in PrivacyBridge BitrefillBridge; do
  grep -qE 'repairLanded' "$ROOT/Casberi/Casberi/Model/$f.swift" \
    || { print -u2 "purchase-stage-selftest: drift — $f stopped healing landed rows"; exit 1; }
done

# Shopify must RECORD a drop rather than write it into the title, which is
# where it lived and where nothing could read it honestly.
grep -qE 'PriceHistory\.compose' "$ROOT/Casberi/Casberi/Model/ShopifyBridge.swift" \
  || { print -u2 "purchase-stage-selftest: drift — Shopify stopped recording price moves"; exit 1; }
grep -qE '\(was \\\(' "$ROOT/Casberi/Casberi/Model/ShopifyBridge.swift" \
  && { print -u2 "purchase-stage-selftest: drift — Shopify is writing the old price back into the title"; exit 1; }

# The sheet must actually draw it. A perfect `PurchaseStage` nothing renders is
# the §311/§340 shape: the reading composes, and no screen shows it.
grep -qE 'PurchaseStageView\(thing:' "$ROOT/Casberi/Casberi/Screens/ThingSheetView.swift" \
  || { print -u2 "purchase-stage-selftest: drift — the sheet stopped drawing the purchase card"; exit 1; }
# …and the spec table's `From` row must stand down where the card's own
# sentence says it better, or the sheet says where this came from twice and
# differs (the row said "from a store you follow" over a barcode scan).
grep -qE 'hasFrom = showsWho && !isWork && purchaseReading == nil' \
  "$ROOT/Casberi/Casberi/Screens/ThingSheetView.swift" \
  || { print -u2 "purchase-stage-selftest: drift — the From row no longer stands down"; exit 1; }

# The seller must reach the FEED row too. It was stamped by all three bridges
# and drawn nowhere, which is half of what this pass was for.
grep -qE '"Shopify", "Deals", "Open Food Facts"' "$ROOT/Casberi/Casberi/Screens/ShapedRows.swift" \
  || { print -u2 "purchase-stage-selftest: drift — the feed row stopped naming the seller"; exit 1; }

# DEMO PARITY (the standing rule). A demo ref that doesn't match the real one
# is a feature that silently never renders — the Peer / Privacy Pools room-head
# failure, which cost a whole pass to find. These are the exact prefixes
# `purchaseRefs` tests.
DEMO="$ROOT/Casberi/Casberi/Model/DemoSeedAll.swift"
for ref in 'privacy:txn:' 'bitrefill:order:' 'bitrefill:invoice:' 'off:'; do
  grep -qF "\"$ref" "$DEMO" \
    || { print -u2 "purchase-stage-selftest: drift — the demo stopped seeding a real $ref ref"; exit 1; }
done
grep -qE 'PriceHistory\.compose' "$DEMO" \
  || { print -u2 "purchase-stage-selftest: drift — the demo stopped seeding a price drop"; exit 1; }
grep -qE 'Nutri-Score \\\(' "$DEMO" \
  || { print -u2 "purchase-stage-selftest: drift — the demo stopped seeding a Nutri-Score tag"; exit 1; }
# …and every one of those real-shaped refs must be in `refPrefixes`, or the row
# OUTLIVES the demo — indistinguishable from a real synced purchase, on a corpus
# the person never chose to keep. The exact trap `DemoSeedAll` documents for
# Peer / Privacy Pools / Railgun / Stocktwits, hit again by this pass.
for ref in 'privacy:txn:demo' 'bitrefill:order:demo' 'bitrefill:invoice:demo' \
           'off:5060403320102'; do
  awk '/static let refPrefixes/,/\]$/' "$DEMO" | grep -qF "$ref" \
    || { print -u2 "purchase-stage-selftest: drift — demo exit no longer removes $ref rows"; exit 1; }
done

print "purchase-stage-selftest: shipped source passes, $MUTATIONS mutations caught, drift guards clean"
