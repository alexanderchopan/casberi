#!/bin/zsh
# Casberi money-receipt self-test — the SHIPPED pure judgement behind every
# money thing's sheet hero (prd §369, 2026-08-12):
#
#   Casberi/Casberi/Model/MoneyReceipt.swift
#   Casberi/Casberi/Model/MoneyCommentary.swift
#
# Both are Foundation-only BY DESIGN, so both are compiled WHOLE AND UNMODIFIED
# rather than extracted — the strongest form of "the harness ran the shipped
# logic". Everything touching `Thing`/`WalletStore`/`ModelContext` lives in
# `MoneyReceiptSource.swift`, which no harness can compile and which holds no
# judgement to test.
#
# WHY A HARNESS AND NOT A LIVE CHECK. This pass replaced a spec table with
# SENTENCES, and that is precisely what nothing else in the tree can check.
# `xcodebuild` is happy either way. A screen sweep photographs a fluent
# paragraph and cannot tell whether it is true. And every failure here is a
# silent wrong answer that renders beautifully:
#
#   · a received transfer wearing a minus, or a send wearing gain green
#   · a PENDING card authorization drawn with a torn edge — a claim of
#     finality made over an amount that can still change
#   · "Mostly them sending you" printed over a history that is 3–2
#   · "You usually spend about $20" because one outlier dragged a MEAN
#   · "This is the biggest yet" when it isn't
#   · a phishing domain promoted into the currency slot beside the figure,
#     because a spoofed token's "name" was treated as a ticker
#   · a Railgun unshield drawing a monogram, so a privacy guarantee reads as
#     a face we merely failed to load
#   · a deposit still in screening drawn as finished, i.e. as money you can
#     withdraw
#   · a weekday named for a date that hasn't happened yet
#
# Pure, local, deterministic — no network, no simulator. Exit non-zero on
# failure.
set -euo pipefail
cd "$(dirname "$0")/.."

RECEIPT="Casberi/Casberi/Model/MoneyReceipt.swift"
SAYS="Casberi/Casberi/Model/MoneyCommentary.swift"
SOURCE="Casberi/Casberi/Model/MoneyReceiptSource.swift"
CARD="Casberi/Casberi/Screens/MoneyReceiptCard.swift"
SHEET="Casberi/Casberi/Screens/ThingSheetView.swift"
STAGE="Casberi/Casberi/Screens/ThingStage.swift"
TOKENS="Casberi/Casberi/Design/DesignTokens.swift"
PROBES="Casberi/Casberi/Shell/ProbeHooks.swift"
for f in "$RECEIPT" "$SAYS" "$SOURCE" "$CARD" "$SHEET" "$STAGE" "$TOKENS" "$PROBES"; do
  [[ -f "$f" ]] || { echo "✗ $f not found"; exit 1; }
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- drift guards -----------------------------------------------------------
# Wiring facts the compiled types cannot prove about themselves. A perfect
# `compose` is worthless if the sheet never draws it, or if a `Thing` gets held
# where it can be read after a delete.

# The receipt must actually be the sheet's hero. Before this pass the gate was
# `kind == .transaction && source == "Wallet"`, which is why eleven families had
# no hero at all — if this reverts, the whole feature is invisible while every
# assertion below still passes.
grep -q 'if let moneyReceipt {' "$SHEET" \
  || { echo "✗ ThingSheetView no longer draws MoneyReceiptCard as its hero"; exit 1; }
grep -q 'MoneyReceiptCard(receipt: moneyReceipt)' "$SHEET" \
  || { echo "✗ ThingSheetView's hero branch no longer builds MoneyReceiptCard"; exit 1; }

# A receipt suppresses the content area. Without this the sheet draws the
# receipt AND the old `default:` branch under it — which for ten families is a
# block-explorer URL rendered as a paragraph, the exact thing this pass removed.
grep -q 'let contentShown = moneyReceipt == nil' "$SHEET" \
  || { echo "✗ the content area is no longer suppressed under a receipt"; exit 1; }

# The commentary FETCHES. Computing it per body evaluation would walk a source's
# rows on every re-render of an open sheet.
grep -q '@State private var moneySays' "$SHEET" \
  || { echo "✗ commentary is no longer held in state (it fetches — see loadReceipt)"; exit 1; }

# Liveness: the receipt views take VALUES, never a Thing, so no view here can
# hold a tombstoned model across a re-render (the build-188 leaf rule).
if grep -qE '^\s*(let|var) thing: Thing' "$CARD"; then
  echo "✗ a receipt view stores a Thing — it must take values only (build 188)"; exit 1
fi

# The pour is a TOKEN. §8 is law: components hold zero raw hex.
grep -q 'static func receiptPour' "$TOKENS" \
  || { echo "✗ DS.receiptPour is gone — the pour would be raw hex in a view"; exit 1; }
if grep -qE '#[0-9a-fA-F]{6}' "$CARD"; then
  echo "✗ MoneyReceiptCard holds raw hex (§8: every value routes through a token)"; exit 1
fi

# The two parsers that survived the stage retirement, and the two readers that
# depend on them. Deleting either silently drops a swap's rate line and turns a
# self-move's Name disc back on, both of which render as "fine".
grep -q 'struct SwapStage' "$STAGE" \
  || { echo "✗ SwapStage is gone — a swap's rate line has nothing to divide"; exit 1; }
grep -q 'MovedStage(thing) == nil ? nameCounterpartyAction : nil' "$SHEET" \
  || { echo "✗ the Name disc no longer stands down on a self-move"; exit 1; }

# The probe. An absent receipt has six causes and only two are bugs; without
# this hook there is no way to tell them apart on a device.
grep -q 'Hook(key: "receiptProbe")' "$PROBES" \
  || { echo "✗ -receiptProbe is gone"; exit 1; }

# NEGATIVE guards read a COMMENT-STRIPPED copy — these files DOCUMENT the things
# they must never do, by naming them, so a guard grepping raw source fires on
# the prose explaining it (the Obsidian/Cursor lesson, earned a fourth time).
strip_comments() {
  python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
src = "\n".join(l for l in src.splitlines() if not l.strip().startswith("//"))
sys.stdout.write(src)
PY
}
strip_comments "$SOURCE" > "$TMP/source-bare.swift"

# The source half must not re-derive facts from prose. The whole point of the
# pass: a title is a localized sentence, and a receipt built by parsing one is a
# receipt that changes meaning in another language.
if grep -qE 'title\.(hasPrefix|contains|range\(of:)' "$TMP/source-bare.swift"; then
  echo "✗ MoneyReceiptSource parses the title — facts come off stamped fields"; exit 1
fi

# --- the harness ------------------------------------------------------------
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

let cal = Calendar(identifier: .gregorian)
let now = Date(timeIntervalSince1970: 1_754_000_000)   // fixed clock

// Dates relative to the FIXED clock — for the `dayPhrase(_:now:)` units
// below, which pass that clock in explicitly and so are fully deterministic.
func at(_ daysAgo: Int, hour: Int = 9) -> Date {
    let day = cal.date(byAdding: .day, value: -daysAgo, to: now)!
    return cal.date(bySettingHour: hour, minute: 41, second: 0, of: day)!
}

// Dates relative to the REAL clock — for every fixture that goes through
// `MoneyReceipt.compose`. `compose` calls `dayPhrase(f.capturedAt)` with its
// DEFAULT `now`, i.e. the system clock, so a fixture dated off the fixed
// clock above lands ~a year in the past and every sentence comes out in the
// dated form. That is what made "no chain read means no 'on <chain>' clause"
// fail: with no network the sentence is "Received into Main <dayPhrase>." and
// the dated phrase is itself "on 31 July 2025", so the clause the assertion
// was looking for appeared without any chain being read.
func realAt(_ daysAgo: Int, hour: Int = 9) -> Date {
    let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
    return cal.date(bySettingHour: hour, minute: 41, second: 0, of: day)!
}

// MARK: split — the ticker rule

do {
    check(MoneyReceipt.split("0.9962 ETH").number == "0.9962", "split keeps the number")
    check(MoneyReceipt.split("0.9962 ETH").unit == "ETH", "split reads the ticker")
    check(MoneyReceipt.split("1,240.00 USDC").unit == "USDC", "split reads a grouped amount's ticker")
    check(MoneyReceipt.split("12.4 EURe").unit == "EURe", "a mixed-case ticker still reads")
    // The measured spoof. A phishing domain must never reach the unit slot.
    let spoof = MoneyReceipt.split("4,672 USDT Staked • gitos.org")
    check(spoof.unit == nil, "a spoofed token name yields NO unit")
    check(spoof.number.contains("gitos.org"), "the spoof stays inside the clamped number")
    check(MoneyReceipt.split("100 BTC2").unit == nil, "a unit with a digit is refused")
    check(MoneyReceipt.split("5 VERYLONGTICKERNAME").unit == nil, "an over-long unit is refused")
    check(MoneyReceipt.split(nil).number == "", "nil amount is empty, not a crash")
    check(MoneyReceipt.split("crypto").unit == nil, "a bare word is not a unit")
}

// MARK: dayPhrase — human time, and no weekday for a date that hasn't happened

do {
    check(MoneyReceipt.dayPhrase(at(0, hour: 9), now: now, calendar: cal) == "this morning",
          "today at 09:41 is this morning")
    check(MoneyReceipt.dayPhrase(at(0, hour: 15), now: now, calendar: cal) == "this afternoon",
          "today at 15:41 is this afternoon")
    check(MoneyReceipt.dayPhrase(at(0, hour: 2), now: now, calendar: cal) == "overnight",
          "today at 02:41 is overnight")
    check(MoneyReceipt.dayPhrase(at(1), now: now, calendar: cal) == "yesterday", "yesterday")
    let threeDays = MoneyReceipt.dayPhrase(at(3), now: now, calendar: cal)
    check(threeDays.count > 3 && !threeDays.contains(","), "three days back names a weekday")
    let far = MoneyReceipt.dayPhrase(at(40), now: now, calendar: cal)
    check(far.rangeOfCharacter(from: .decimalDigits) != nil, "forty days back is a date")
    // A clock skew, or a bridge stamping ahead. A weekday for a day that has
    // not happened is the confident wrong answer.
    let future = cal.date(byAdding: .day, value: 3, to: now)!
    let ahead = MoneyReceipt.dayPhrase(future, now: now, calendar: cal)
    check(ahead.rangeOfCharacter(from: .decimalDigits) != nil,
          "a FUTURE date is dated, never given a weekday")
}

// MARK: currency — never a bare number

do {
    check(MoneyReceipt.currency(nil, code: "USD") == nil, "no value, no figure")
    check(MoneyReceipt.currency(6.75, code: nil) == nil, "no currency, no figure")
    check(MoneyReceipt.currency(6.75, code: "") == nil, "an empty currency is no currency")
    check(MoneyReceipt.currency(6.75, code: "USD")?.contains("6.75") == true, "cents where they matter")
    check(MoneyReceipt.currency(-6.75, code: "USD")?.contains("-") == false,
          "the sign is the receipt's, not the formatter's")
}

// MARK: the wallet transfer

func transfer(_ direction: String, amount: String = "0.9962 ETH",
              usd: Double? = 3480) -> MoneyReceipt.Facts {
    var f = MoneyReceipt.Facts(source: "Wallet", title: "Received 0.9962 ETH from maria.eth")
    f.capturedAt = realAt(0)
    f.direction = direction
    f.amount = amount
    f.usd = usd
    f.counterpartyAddress = "0x4f2a"
    f.walletAddress = "0xmine"
    f.partyLabel = "maria.eth"
    f.myLabel = "Main"
    f.network = "Ethereum"
    return f
}

do {
    guard let r = MoneyReceipt.compose(transfer("received")) else {
        print("  ✗ a received transfer composes nothing"); failures += 1; exit(1)
    }
    check(r.amount?.number == "+0.9962", "a receive wears a plus")
    check(r.amount?.unit == "ETH", "the unit rides beside the figure")
    check(r.amount?.tone == .gain, "a gain is green")
    check(r.finality == .torn, "a settled transfer is torn off")
    check(r.stamp == .settled, "and stamped settled")
    check(r.mine == "0xmine", "your wallet rides as the tucked face")
    check(r.subject == .address("0x4f2a"), "an address beats a name for the disc")
    check(r.sentence.contains("Main"), "the sentence names the wallet")
    check(r.sentence.contains("Ethereum"), "and the network")
    check(r.secondary?.contains("3,480") == true, "worth at landing, not today")

    guard let s = MoneyReceipt.compose(transfer("sent")) else {
        print("  ✗ a sent transfer composes nothing"); failures += 1; exit(1)
    }
    check(s.amount?.number == "−0.9962", "a send wears a minus")
    // Spending is not a loss state; red would editorialize and green would lie.
    check(s.amount?.tone == .plain, "a send is NOT toned as a gain")

    // No price read: nothing rather than a guess.
    let unpriced = MoneyReceipt.compose(transfer("received", usd: nil))
    check(unpriced?.secondary == nil, "an unpriced transfer states no fiat")

    // No network in the content: the clause is dropped, not guessed.
    var noChain = transfer("received"); noChain.network = nil
    check(MoneyReceipt.compose(noChain)?.sentence.contains("on ") == false,
          "no chain read means no 'on <chain>' clause")

    // No stamped direction at all — a swap, a self-move, a Morpho supply.
    var bare = transfer("received"); bare.direction = nil; bare.amount = nil
    let generic = MoneyReceipt.compose(bare)
    check(generic?.amount == nil, "with no stamped figure there is no headline number")
    check(generic?.titleFallback != nil, "it leads with its title instead")
}

// MARK: Bitcoin

do {
    var f = MoneyReceipt.Facts(source: "Wallet", title: "Received 0.0412 BTC")
    f.capturedAt = realAt(0)
    f.direction = "received"
    f.amount = "0.0412 BTC"
    f.venue = "Block 959,701"
    f.walletAddress = "bc1q"
    f.settling = true
    guard let settling = MoneyReceipt.compose(f) else {
        print("  ✗ bitcoin composes nothing"); failures += 1; exit(1)
    }
    check(settling.hue == .bitcoin, "bitcoin pours its own hue")
    check(settling.stamp == .settling, "short of the bar, it is settling")
    // A transfer that can still be reorganized out of the chain is not history.
    check(settling.finality == .open, "and is NOT torn off")
    check(settling.sentence.contains("Block 959,701"), "the block is the sentence's subject")
    check(settling.secondary?.contains("not a market") == true,
          "it says out loud that there is no dollar figure")

    f.settling = false
    check(MoneyReceipt.compose(f)?.finality == .torn, "once settled, it tears")
    f.venue = nil
    check(MoneyReceipt.compose(f)?.sentence.contains("Block") == false,
          "no block read means no block claimed")
}

// MARK: card spends

func card(_ source: String, tags: [String], merchant: String? = "Blue Bottle Coffee")
    -> MoneyReceipt.Facts {
    var f = MoneyReceipt.Facts(source: source, title: "Blue Bottle Coffee · $6.75")
    f.capturedAt = realAt(0)
    f.counterparty = merchant
    f.priceValue = 6.75
    f.priceCurrency = "USD"
    f.tags = tags
    f.authorHandle = "Apple Card, ending 4821"
    return f
}

do {
    guard let pending = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card", "Pending"])) else {
        print("  ✗ a card spend composes nothing"); failures += 1; exit(1)
    }
    check(pending.stamp == .pending, "an unsettled authorization is pending")
    // The amount can still change. A torn edge here is a claim of finality
    // over a number that isn't final.
    check(pending.finality == .open, "and is NOT torn off")
    check(pending.amount?.number.hasPrefix("−") == true, "a spend wears a minus")
    check(pending.subject == .named("Blue Bottle Coffee"), "the merchant is the subject")
    check(pending.mine == nil, "a card spend has one party, so no tucked face")
    check(pending.secondary?.contains("4821") == true, "the account is named")
    check(pending.sentence.contains("still change"), "and the sentence says it can change")
    check(pending.hue == .neutral, "Apple Card has no brand hue to borrow")

    let settled = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card"]))
    check(settled?.finality == .torn, "a settled charge tears")
    check(settled?.stamp == .settled, "and is stamped settled")

    let refund = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card", "Refund"]))
    check(refund?.amount?.number.hasPrefix("+") == true, "a refund wears a plus")
    check(refund?.amount?.tone == .gain, "a refund is a gain")
    check(refund?.stamp == .refund, "and is stamped as one")

    // Onchain cards carry NO merchant — a ceiling the copy has always named.
    let gnosis = MoneyReceipt.compose(card("Gnosis Pay", tags: ["Card"], merchant: nil))
    check(gnosis?.subject == .absent(.merchantOffchain),
          "an onchain card with no merchant draws a VOID, not a monogram")
    check(gnosis?.hue == .card, "and pours the card hue")
    // Apple Wallet genuinely knows merchants, so a missing one there is an
    // ordinary gap and must NOT claim to be a designed absence.
    let appleNoMerchant = MoneyReceipt.compose(card("Apple Wallet", tags: ["Card"], merchant: nil))
    if case .absent = appleNoMerchant?.subject {
        check(false, "a missing Apple Wallet merchant must not read as a designed absence")
    }

    var unreadable = card("Apple Wallet", tags: ["Card"])
    unreadable.priceValue = nil
    unreadable.amount = nil
    check(MoneyReceipt.compose(unreadable)?.amount == nil, "no readable amount, no figure")
}

// MARK: Privacy Pools

do {
    var f = MoneyReceipt.Facts(source: "Privacy Pools", title: "Put 0.0700 ETH into Privacy Pools")
    f.capturedAt = realAt(6)
    f.amount = "0.0700 ETH"
    f.tags = ["Shielded", "Pending"]
    f.walletAddress = "0xmine"
    f.myLabel = "Main"
    guard let screening = MoneyReceipt.compose(f) else {
        print("  ✗ a deposit composes nothing"); failures += 1; exit(1)
    }
    check(screening.stamp == .screening, "a pending deposit is screening")
    // The money is not yours to move until screening clears.
    check(screening.finality == .open, "and the paper is NOT torn")
    check(screening.sentence.contains("isn't yours to withdraw"), "the sentence says so plainly")
    check(screening.subject == .asset("ETH"), "the pool's asset is the subject")
    check(screening.hue == .shield, "and it pours the shield hue")

    f.tags = ["Shielded", "Approved"]
    let cleared = MoneyReceipt.compose(f)
    check(cleared?.stamp == .cleared, "an approved deposit is clear to withdraw")
    check(cleared?.finality == .torn, "and only then does it tear")

    f.tags = ["Shielded", "Proof"]
    check(MoneyReceipt.compose(f)?.stamp == .needsProof, "a proof request is its own state")
    check(MoneyReceipt.compose(f)?.finality == .open, "and is never final")
}

// MARK: Railgun

do {
    var f = MoneyReceipt.Facts(source: "Railgun", title: "Unshielded 1.5 ETH")
    f.capturedAt = realAt(1)
    f.direction = "received"
    f.amount = "1.5000 ETH"
    f.walletAddress = "0xmine"
    f.myLabel = "Main"
    f.network = "Ethereum"
    guard let unshield = MoneyReceipt.compose(f) else {
        print("  ✗ an unshield composes nothing"); failures += 1; exit(1)
    }
    // The privacy IS the feature. A monogram would read as a face we failed to
    // load, which turns a guarantee into a bug report.
    check(unshield.subject == .absent(.senderPrivate),
          "an unshield's sender is a designed absence")
    check(unshield.finality == .torn, "the arrival is final — privacy is not incompleteness")
    check(unshield.stamp == .shielded, "and it is stamped shielded")
    check(unshield.secondary?.contains("nothing about where it came from") == true,
          "the second line states the ceiling")

    f.direction = "sent"
    let shield = MoneyReceipt.compose(f)
    if case .absent = shield?.subject {
        check(false, "a SHIELD has a known sender — it must not draw the void")
    }
}

// MARK: Safe

do {
    var f = MoneyReceipt.Facts(source: "Safe", title: "Treasury · a transfer of 12,500 USDC")
    f.capturedAt = realAt(0)
    f.walletAddress = "0xsafe"
    f.myLabel = "Treasury"
    f.tags = ["Your turn"]
    f.signaturesHave = 2
    f.signaturesNeed = 3
    guard let waiting = MoneyReceipt.compose(f) else {
        print("  ✗ a Safe transaction composes nothing"); failures += 1; exit(1)
    }
    check(waiting.stamp == .yourTurn, "a tagged transaction says it's your turn")
    check(waiting.finality == .open, "an unsigned transaction is never torn")
    // An empty "Receipt —" row reads as a bug; a sentence reads as the truth.
    check(waiting.sentence.contains("no receipt to show"),
          "it says in words that there is no receipt yet")
    check(waiting.secondary?.contains("one more signature") == true,
          "one short is said as one short")
    check(waiting.amount == nil, "a multisig payload's value is never parsed out of prose")

    f.signaturesHave = 3
    let executed = MoneyReceipt.compose(f)
    check(executed?.finality == .torn, "an executed transaction tears")
    f.signaturesHave = 1
    check(MoneyReceipt.compose(f)?.secondary == nil, "two short is not 'one more'")
}

// MARK: sources

do {
    let unknown = MoneyReceipt.Facts(source: "Bluesky", title: "a post")
    check(MoneyReceipt.compose(unknown) == nil, "a non-money source draws no receipt")
    check(MoneyReceipt.sources.contains("Peer"), "Peer is a money source")
    check(MoneyReceipt.sources.contains("Apple Wallet"), "Apple Wallet is a money source")
}

// MARK: commentary — history

do {
    // Four received, one sent: lopsided, so the claim is allowed.
    let lopsided: [(Double, Bool)] = [(1, true), (2, true), (0.5, false), (1, true), (3, true)]
    guard case .history(let head, let sub, let series)? =
        MoneyCommentary.history(party: "maria.eth", unit: "ETH", signed: lopsided) else {
        print("  ✗ a lopsided history composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("maria.eth") && head.contains("5"), "the headline counts and names")
    check(sub?.contains("Mostly them") == true, "and claims the direction")
    check(sub?.contains("biggest yet") == true, "the largest is called out")
    check(series.count == 5, "one bar per transfer")
    check(series[2] < 0, "a send is drawn below the line")

    // 3–2 is NOT lopsided. Claiming it would be a fluent wrong answer.
    let even: [(Double, Bool)] = [(1, true), (1, true), (1, false), (1, false), (1, true)]
    guard case .history(_, let evenSub, _)? =
        MoneyCommentary.history(party: "x", unit: "ETH", signed: even) else {
        print("  ✗ an even history composes nothing"); failures += 1; exit(1)
    }
    check(evenSub?.contains("Mostly") == false, "an even split makes NO 'mostly' claim")
    check(evenSub?.contains("both ways") == true, "it says both ways instead")

    // Two is a pair, not a pattern. One is the row you're reading.
    check(MoneyCommentary.history(party: "x", unit: "ETH",
                                  signed: [(1, true), (2, true)]) == nil,
          "two transfers earn no card")

    // Mixed tokens: the sentence survives, the bars do not — height means
    // quantity, and ETH beside USDC on one axis means nothing.
    guard case .note? = MoneyCommentary.history(party: "x", unit: nil,
                                                signed: lopsided) else {
        print("  ✗ a mixed-token history should degrade to a note"); failures += 1; exit(1)
    }

    // "Biggest yet" must be checkable, not decorative.
    let notBiggest: [(Double, Bool)] = [(9, true), (1, true), (2, true)]
    guard case .history(_, let nb, _)? =
        MoneyCommentary.history(party: "x", unit: "ETH", signed: notBiggest) else {
        print("  ✗ composes nothing"); failures += 1; exit(1)
    }
    check(nb?.contains("biggest") == false, "it is not called the biggest when it isn't")
}

// MARK: commentary — merchant

do {
    // One outlier. A MEAN would report ~$20 as typical, which is a spend that
    // never happened.
    let values: [Double] = [5, 5, 5, 5, 100, 6]
    guard case .merchant(let head, let sub, let drawn)? =
        MoneyCommentary.merchant(name: "Blue Bottle", values: values, currency: "USD") else {
        print("  ✗ a merchant board composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("5.00"), "typical is the MEDIAN, not the mean")
    check(!head.contains("20"), "and is not dragged by an outlier")
    check(sub?.contains("6") == true, "the window is named in the sentence")
    check(drawn.count == 6, "every charge is drawn")

    let highest: [Double] = [4, 5, 6, 99]
    guard case .merchant(_, let hs, _)? =
        MoneyCommentary.merchant(name: "x", values: highest, currency: "USD") else {
        print("  ✗ composes nothing"); failures += 1; exit(1)
    }
    check(hs?.contains("highest") == true, "a real high is called out")

    check(MoneyCommentary.merchant(name: "x", values: [5, 6], currency: "USD") == nil,
          "two charges are not a habit")
    check(MoneyCommentary.merchant(name: "x", values: [5, 6, 7], currency: nil) == nil,
          "no currency, no claim about money")
}

// MARK: commentary — rate

do {
    guard case .rate(let head, _)? =
        MoneyCommentary.rate(out: "0.5 ETH", into: "1,240.00 USDC") else {
        print("  ✗ a swap rate composes nothing"); failures += 1; exit(1)
    }
    check(head.contains("2480"), "0.5 ETH for 1,240 USDC is 2480 per ETH")
    check(head.contains("ETH") && head.contains("USDC"), "both units are named")
    check(MoneyCommentary.rate(out: "0.5", into: "1,240 USDC") == nil,
          "a leg with no unit yields no rate")
    check(MoneyCommentary.rate(out: "0 ETH", into: "1 USDC") == nil,
          "a zero leg is not divided by")
    check(MoneyCommentary.rate(out: "some ETH", into: "1 USDC") == nil,
          "an unreadable leg yields no rate")
}

// MARK: median

do {
    check(MoneyCommentary.median([1, 2, 3]) == 2, "odd median")
    check(MoneyCommentary.median([1, 2, 3, 4]) == 2.5, "even median")
    check(MoneyCommentary.median([]) == nil, "empty has no median")
    check(MoneyCommentary.number("1,240.00") == 1240, "grouped numbers read")
    check(MoneyCommentary.number("12 USDC") == nil, "a number with a word does not")
}

if failures > 0 {
    print("\(failures) assertion(s) failed")
    exit(1)
}
print("all assertions passed")
SWIFT

echo "money-receipt-selftest: compiling MoneyReceipt + MoneyCommentary WHOLE and unmodified…"
swiftc -O -o "$TMP/run" "$RECEIPT" "$SAYS" "$TMP/main.swift" \
  || { echo "✗ the shipped receipt logic does not compile Foundation-only — something reached Thing/SwiftUI"; exit 1; }
"$TMP/run" || exit 1

# --- mutation pass ----------------------------------------------------------
# Every mutation below is a silent wrong answer that renders perfectly. A
# mutation that survives means nothing here was testing that line.
echo ""
echo "mutations (each must be caught):"

mutate() {
  local name="$1" which="$2" frm="$3" to="$4"
  cp "$RECEIPT" "$TMP/MoneyReceipt.swift"
  cp "$SAYS" "$TMP/MoneyCommentary.swift"
  local a="$TMP/MoneyReceipt.swift" b="$TMP/MoneyCommentary.swift"
  local target
  case "$which" in
    receipt) target="$a" ;;
    says)    target="$b" ;;
  esac
  FRM="$frm" TO="$to" python3 - "$target" <<'PY'
import os, sys
path = sys.argv[1]
src = open(path).read()
frm, to = os.environ["FRM"], os.environ["TO"]
if frm not in src:
    sys.exit(1)
open(path, "w").write(src.replace(frm, to, 1))
PY
  if [[ $? -ne 0 ]] || ! grep -qF -- "$to" "$target"; then
    echo "  ✗ $name — the mutation did not apply (the shipped source moved)"; exit 1
  fi
  if ! swiftc -O -o "$TMP/mut" "$a" "$b" "$TMP/main.swift" 2>/dev/null; then
    echo "  ✓ $name (rejected at compile)"; return
  fi
  if "$TMP/mut" > /dev/null 2>&1; then
    echo "  ✗ $name — the harness still passed, so nothing was testing this"; exit 1
  fi
  echo "  ✓ $name"
}

# A receive wearing a minus. Renders perfectly; means the opposite.
mutate "the transfer sign is inverted" receipt \
  'number: (received ? "+" : "−") + parts.number,
                           unit: parts.unit,' \
  'number: (received ? "−" : "+") + parts.number,
                           unit: parts.unit,'

# Spending drawn as a gain — green over money that left.
mutate "a send is toned as a gain" receipt \
  'tone: received ? .gain : .plain),
            secondary: worthLine(f.usd),
            sentence: transferSentence' \
  'tone: .gain),
            secondary: worthLine(f.usd),
            sentence: transferSentence'

# A pending authorization claiming finality over an amount that can change.
mutate "a pending card charge is torn off" receipt \
  'finality: pending ? .open : .torn,
            hue: hue)' \
  'finality: .torn,
            hue: hue)'

# A deposit still in screening drawn as finished — i.e. as withdrawable money.
mutate "a screening deposit reads as final" receipt \
  'finality: cleared ? .torn : .open,
            hue: .shield)' \
  'finality: .torn,
            hue: .shield)'

# The privacy guarantee downgraded to "we couldn't read it".
mutate "an unshield draws a monogram instead of the void" receipt \
  'subject: unshield ? .absent(.senderPrivate)' \
  'subject: unshield ? .named("Railgun")'

# A phishing domain promoted into the currency slot.
mutate "the unit rule stops checking for letters" receipt \
  'last.allSatisfy({ $0.isLetter })' \
  'true'

# A weekday named for a day that has not happened.
mutate "a future date is given a weekday" receipt \
  'if days >= 2, days <= 6 {' \
  'if days <= 6 {'

# Bitcoin reaching for a market it does not read.
# Anchored on the LINE AFTER it, not on the sentence itself (2026-08-12).
# A mutation is by nature an exact source edit, so this used to pin Bitcoin's
# whole no-fiat sentence — and a copy pass that rewrote it ("Casberi reads the
# chain here…" → "Read from the chain…") stopped the mutation applying, which
# `set -e` turned into a silent exit with no ✗ at all. `sentence:
# bitcoinSentence(f),` is structure rather than prose: it names a function, so
# it only moves if the composition really moves, and inserting the fiat line
# above it is the same inversion the old edit made.
mutate "bitcoin claims a fiat figure" receipt \
  'sentence: bitcoinSentence(f),' \
  'secondary: worthLine(f.usd), sentence: bitcoinSentence(f),'

# "Mostly them sending you" over a 3–2 split.
mutate "the lopsided guard is dropped" says \
  'if received * 3 >= signed.count * 2 {' \
  'if received >= 1 {'

# One outlier redefining "usually".
mutate "typical becomes the mean" says \
  'let sorted = values.sorted()
        let mid = sorted.count / 2' \
  'let sorted = [values.reduce(0, +) / Double(values.count)]
        let mid = sorted.count / 2'

# A pair reported as a pattern.
mutate "two transfers earn a history card" says \
  'guard signed.count >= 3 else { return nil }' \
  'guard signed.count >= 1 else { return nil }'

# "The biggest yet" as decoration rather than a checked claim.
mutate "biggest-yet stops being checked" says \
  'signed.dropLast().allSatisfy({ $0.0 < mine })' \
  'true'

# A rate divided out of a leg that could not be read.
mutate "a zero leg is divided by" says \
  'outValue > 0, inValue > 0 else { return nil }' \
  'outValue >= 0, inValue >= 0 else { return nil }'

echo ""
echo "money-receipt-selftest: OK"
