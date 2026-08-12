import Foundation

/// What the app SAYS about a receipt (prd §369, 2026-08-12) — the card under the
/// paper.
///
/// **The rule that shapes every case here: a label over a chart is not
/// commentary.** "Your history with maria.eth" above a bar strip makes the
/// reader do the reading. A sentence that has already read the chart — "You and
/// maria.eth have moved ETH five times, mostly her sending you" — is the app
/// doing its job, with the chart underneath as the evidence.
///
/// **And that raises the stakes, which is why this file is Foundation-only and
/// harness-compiled.** Every headline below is a CLAIM. "Mostly her sending you"
/// is false on an even split; "your highest here" is false if a bigger one is
/// sitting in the corpus unread; "about 30 minutes to go" is a guess unless it
/// comes off a real confirmation count. So each builder returns nil rather than
/// soften a claim it can't support, and each has a shorter form for the case
/// where the strong sentence isn't true.
///
/// **What is deliberately NOT here.** Three visualizations from the design pass
/// need a fact no bridge stamps, and inventing them by parsing prose is exactly
/// what this app's own law forbids:
///
///   · **Peer's paid-vs-market spread.** `PeerBridge` computes it (prd §237) and
///     keeps it as a SENTENCE on `enrichedText`. There is no stored rate, so the
///     two-tick bar cannot be drawn without re-parsing that sentence. It shows
///     as `.note` instead — the real sentence, which is still the payoff fact.
///   · **Privacy Pools' anonymity-set meter.** Same shape: §228 stores "the ETH
///     pool holds about 3,900 accepted deposits" as prose. A meter would need
///     that integer back out of a localized string.
///   · **A lending position's health bar.** The health factor lives in the live
///     protocol read (`MorphoDeFi.book`), never on the row, so a sheet has
///     nothing to draw it from without a network call the sheet shouldn't make.
///
/// Each becomes drawable the day its bridge stamps the number it already
/// computed. Until then the honest form is the sentence the bridge wrote.
enum MoneyCommentary: Equatable {

    /// A signed series with this counterparty — positive received, negative
    /// sent, oldest first, THIS row last.
    case history(headline: String, subline: String?, series: [Double])
    /// Prior spends at the same merchant, oldest first, this row last.
    case merchant(headline: String, subline: String?, values: [Double])
    /// Privacy Pools' screening ladder — the rung reached, and when.
    case ladder(headline: String, subline: String?, rung: Rung, since: Date)
    /// A swap's rate, stated.
    case rate(headline: String, subline: String?)
    /// A fact the bridge already wrote as a sentence. The honest form for
    /// everything in the "deliberately not here" list above.
    case note(headline: String, subline: String?)

    enum Rung: Equatable { case deposited, screening, needsProof, cleared }

    /// The headline, for the probe and for accessibility.
    var headline: String {
        switch self {
        case .history(let h, _, _), .merchant(let h, _, _),
             .ladder(let h, _, _, _), .rate(let h, _), .note(let h, _):
            return h
        }
    }

    // MARK: - Builders

    /// Your history with a counterparty. **Single-token only**, and that is not
    /// a nicety: bar height means quantity, and ETH bars beside USDC bars on one
    /// axis mean nothing at all. A mixed history returns the count with no
    /// series, so the card still says something true and draws no chart.
    ///
    /// `signed` is (amount, isReceived) oldest-first, INCLUDING this row.
    static func history(party: String, unit: String?,
                        signed: [(Double, Bool)]) -> MoneyCommentary? {
        // One transfer is the row you are already reading; two is a pair, not a
        // pattern. Neither earns a card.
        guard signed.count >= 3 else { return nil }
        let received = signed.filter(\.1).count
        let sent = signed.count - received
        let unitName = unit ?? String(localized: "funds")
        let headline = String(localized: "You and \(party) have moved \(unitName) \(signed.count) times.")
        // The claim only where the split is genuinely lopsided — two thirds, so
        // 3–1 qualifies and 3–2 does not.
        var subline: String?
        if received * 3 >= signed.count * 2 {
            subline = String(localized: "Mostly them sending you.")
        } else if sent * 3 >= signed.count * 2 {
            subline = String(localized: "Mostly you sending them.")
        } else {
            subline = String(localized: "Going both ways, fairly evenly.")
        }
        // "The biggest yet" is checkable, so it is worth saying — and it is only
        // said when this row really is the largest of the ones we hold.
        if let mine = signed.last?.0,
           mine > 0, signed.dropLast().allSatisfy({ $0.0 < mine }) {
            subline = (subline.map { $0 + " " } ?? "")
                + String(localized: "This is the biggest yet.")
        }
        guard unit != nil else { return .note(headline: headline, subline: subline) }
        return .history(headline: headline, subline: subline,
                        series: signed.map { $0.1 ? $0.0 : -$0.0 })
    }

    /// What you usually spend at this merchant. `values` is oldest-first
    /// including this row, all in ONE currency (the source half filters, since a
    /// total across currencies is the failure `Corpus.cardSpendSources` documents).
    ///
    /// The window is named IN THE SENTENCE rather than as a caption under an
    /// axis, because that is where the caveat belongs: a first sync backfills
    /// about six days, so "usually" is usually-of-what-we-read.
    static func merchant(name: String, values: [Double],
                         currency: String?) -> MoneyCommentary? {
        guard values.count >= 3, let mine = values.last else { return nil }
        let prior = values.dropLast()
        let typical = median(Array(prior))
        guard let typical, typical > 0,
              let money = MoneyReceipt.currency(typical, code: currency)
        else { return nil }
        let headline = String(localized: "You usually spend about \(money) at \(name).")
        var subline = String(localized: "Of the \(values.count) charges seen here.")
        if prior.allSatisfy({ $0 < mine }) {
            subline = String(localized: "Your highest of the \(values.count) seen here.")
        }
        return .merchant(headline: headline, subline: subline, values: values)
    }

    /// Bitcoin, still short of the settle bar. **No pip count and no estimate**
    /// — the bridge stores a pending SET of txids and no per-transfer
    /// confirmation number, so "3 of 6" and "about 30 minutes to go" are both
    /// facts this app does not have. A one-line change in `BitcoinBridge` to
    /// stamp the count it already reads would make both drawable; until then the
    /// honest card names the bar and promises the notice.
    static func settling(need: Int) -> MoneyCommentary {
        .note(headline: String(localized: "Still settling."),
              subline: String(localized: "You'll be told when it reaches \(need) confirmations."))
    }

    /// The screening ladder — the reason this seat exists, and a status the
    /// sheet showed nowhere before this pass.
    static func ladder(rung: Rung, since: Date, days: Int) -> MoneyCommentary {
        switch rung {
        case .cleared:
            return .ladder(headline: String(localized: "Screening cleared."),
                           subline: String(localized: "This is yours to withdraw."),
                           rung: rung, since: since)
        case .needsProof:
            return .ladder(headline: String(localized: "Privacy Pools has asked you for proof."),
                           subline: String(localized: "Open 0xBow to respond — nothing clears until you do."),
                           rung: rung, since: since)
        default:
            let head = days <= 1
                ? String(localized: "Waiting on screening.")
                : String(localized: "Waiting on screening, \(days) days in.")
            return .ladder(headline: head,
                           subline: String(localized: "Checked every sync — you'll be told the day it clears."),
                           rung: .screening, since: since)
        }
    }

    /// A swap's rate. Both legs come from the title's own " → " separator, which
    /// `SwapStage` has parsed since 2026-07-21 — a structural delimiter the
    /// bridge writes, not prose. nil when either leg carries no readable number,
    /// because a rate is a division and a division needs two numbers.
    static func rate(out: String, into: String) -> MoneyCommentary? {
        let a = MoneyReceipt.split(out), b = MoneyReceipt.split(into)
        guard let outUnit = a.unit, let inUnit = b.unit,
              let outValue = number(a.number), let inValue = number(b.number),
              outValue > 0, inValue > 0 else { return nil }
        let rate = inValue / outValue
        let shown = rate >= 100 ? String(format: "%.0f", rate)
            : rate >= 1 ? String(format: "%.2f", rate)
            : String(format: "%.6f", rate)
        return .rate(headline: String(localized: "1 \(outUnit) = \(shown) \(inUnit)"),
                     subline: String(localized: "The rate you traded at."))
    }

    // MARK: - Arithmetic

    /// The MEDIAN, never the mean — one unusual charge would drag a mean and
    /// make "usually" describe a spend that never happened.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// A grouped decimal string back to a number ("1,240.00" → 1240). Returns
    /// nil for anything it can't read cleanly, so a rate is refused rather than
    /// computed from a partial parse.
    static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return Double(cleaned)
    }
}
