import Foundation

/// The price, as one object (prd §369 amendment, 2026-08-16) — the receipt
/// treatment applied to the surface that never had it.
///
/// **What it replaces.** A watched token or stock had no hero at all: it fell
/// through every branch of `ThingSheetView`'s cascade to the plain title block,
/// so the price rendered as BODY CONTENT, third on the sheet, under a
/// `heading34` string that had already said the name. Seven independently
/// padded blocks with no container, no subject and nothing the app says —
/// while the sheet title said "Aerodrome · $AERO", the eyebrow said "3h ago",
/// the delta pill said "· 1D", the chips said "1D" and the spec table said
/// "Site dexscreener.com". Five labels and no object, which is precisely the
/// failure `MoneyReceiptCard`'s own doc names.
///
/// **The one deliberate divergence from the receipt.** A receipt's stamp says
/// whether it is FINISHED, and its bottom edge tears when it is. A price is
/// never finished, so that slot carries the only state a price really has:
/// how recently we read it (`freshness`). It is the same rail `TokenChart
/// .fetchedAt` shipped earlier today, given somewhere to live.
///
/// **Foundation-only by design**, the `MoneyReceipt` split: everything that can
/// be wrong while still rendering perfectly lives here, where the harness
/// compiles it whole. `PriceObjectSource` holds the half that touches `Thing`.
struct PriceObject: Equatable {

    /// Slot 0. The same grades-of-knowing rule `MoneyReceipt.Subject` follows,
    /// one case shorter: a price has no address to draw an identicon from.
    ///
    /// **No invented hue.** A token we hold no artwork for takes a neutral
    /// monogram, never a colour hashed out of its symbol — `AssetMark`'s rule,
    /// and it matters more here than almost anywhere, because a watchlist is
    /// mostly long-tail tokens and a hashed palette would read as brand colour
    /// for assets nobody has verified.
    enum Subject: Equatable {
        /// A symbol we can draw a real mark for, or fall back to a monogram on.
        case asset(String)
        /// Nothing to draw — the row never stamped a symbol.
        case none
    }

    /// A price has no finality, only currency (see the type's doc).
    enum Freshness: Equatable {
        /// Read inside the window that earns the live mark.
        case live
        /// Read a while ago. Carries the moment so the card can say it.
        case aged(Date)

        var isLive: Bool { self == .live }
    }

    /// The move, kept apart from its formatting so the view can tone it and
    /// the harness can assert on it.
    struct Move: Equatable {
        /// The fraction, e.g. -0.048.
        var change: Double
        /// The window it is a change OVER — "1D", "7D". Never dropped: a
        /// percentage with no window is not a reading, it is a number.
        var window: String
        /// True when the change rounds away at the one decimal we print.
        /// `TokenChartStyle.isFlat`'s rule, restated here so this file stays
        /// Foundation-only and the harness can compile it.
        var isFlat: Bool { abs(change * 100) < flatFloor }
    }

    static let flatFloor = 0.05

    var subject: Subject
    /// The asset's long name — "Aerodrome". nil leaves the symbol standing
    /// alone, which is correct and common: plenty of tokens have no name worth
    /// printing, and repeating the symbol twice would be the label-for-a-label
    /// failure this object exists to end.
    var name: String?
    /// "$AERO" / "AAPL" — what the object is called.
    var symbol: String
    /// The figure, already formatted by the price ramp the chart uses, so the
    /// object and the curve beneath it can never print the same number two
    /// ways.
    var price: String
    var move: Move?
    var freshness: Freshness
    /// What the app has to say. nil is the healthy answer for most rows most of
    /// the time — the object simply stands alone (`MoneyCommentary`'s rule).
    var sentence: String?

    // MARK: - Said out loud

    /// The object as ONE spoken stop, the receipt's `spokenLabel` rule.
    ///
    /// The window rides WITH the move rather than after it, because a
    /// percentage read on its own is a number about nothing — and the
    /// freshness is spoken too, since on this surface it is the state.
    var spokenLabel: String {
        var said: [String] = []
        said.append(name.map { "\($0), \(symbol)" } ?? symbol)
        said.append(price)
        if let move {
            said.append(move.isFlat
                ? String(localized: "unchanged over \(move.window)")
                : String(localized: "\(PriceObject.percent(move.change)) over \(move.window)"))
        }
        if let sentence { said.append(sentence) }
        return said.joined(separator: ". ")
    }

    /// Freshness as the accessibility VALUE — the state slot, exactly where
    /// the receipt puts finality.
    var spokenValue: String {
        switch freshness {
        case .live: return String(localized: "Read just now")
        case .aged(let when):
            return String(localized: "Read \(when.formatted(.relative(presentation: .named)))")
        }
    }

    /// "+4.2%" / "−1.8%" / "0.0%". A change that rounds away has no direction
    /// to report (§83) — no sign, and the view gives it no colour either.
    static func percent(_ change: Double) -> String {
        guard abs(change * 100) >= flatFloor else { return "0.0%" }
        // U+2212 MINUS SIGN, the figure ramp's own glyph.
        let sign = change > 0 ? "+" : "−"
        return sign + String(format: "%.1f%%", abs(change * 100))
    }
}

/// What a price is allowed to say (prd §369 amendment, 2026-08-16).
///
/// **Why this type exists at all.** The price surface said nothing. Every other
/// room in this app makes a claim and puts its evidence underneath — that is
/// what `MoneyCommentaryCard` does, deliberately inverted so the reader is not
/// made to do the reading. A chart with no sentence is a chart the reader has
/// to interpret unaided, which on a screen full of numbers is the one thing an
/// app can help with.
///
/// **Every line here is arithmetic on the closes array already fetched, plus
/// the watch anchor already stored on the thing.** No request, no new field, no
/// model. Fluency is the danger — a wrong sentence about money reads perfectly
/// — so the harness compiles this file whole and mutates every threshold.
///
/// ## What it will never say, and why
///
/// · **A prediction.** "Looks like it's breaking out." We do not forecast, and
///   a forecast dressed as an observation is the worst version of that.
/// · **Advice.** "Down 8% — might be worth buying." Not in this domain, ever.
/// · **A ranking across the watchlist.** "Your best performer." The sheet is
///   handed one row and cannot see the others; saying otherwise is a claim
///   about data this code does not have.
/// · **Anything about volume or flows.** We do not fetch them on this path.
/// · **Congratulation.** "+41% since you watched — nice call." It flatters a
///   number that could as easily have been red, which makes the app's voice a
///   cheerleader on the one surface where that is least welcome.
enum PriceCommentary {

    /// Peak-to-trough under this and the window is worth calling quiet.
    ///
    /// One percent, measured against the alternative rather than chosen for
    /// roundness: at 0.5% almost nothing qualifies and the line never fires; at
    /// 2% a token that swung 2% in a day gets called quiet, which anyone
    /// watching it would read as wrong.
    static let quietBand = 0.01

    /// A retrace has to give back at least this share of the run for the shape
    /// to be the story rather than the close.
    static let giveBackShare = 0.5

    /// Below this many closes the shape observations are refused outright: the
    /// coarse Dexscreener fallback is five back-solved points, and "its highest
    /// in thirty days" over five points is a sentence about nothing.
    static let minimumCloses = 8

    /// The whole sentence — the shape observation and the watch clause, in that
    /// order, either of which may be absent.
    static func sentence(closes: [Double], window: String,
                         watched: (price: Double, date: Date)?,
                         now: Date = .now) -> String? {
        let parts = [shape(closes: closes, window: window),
                     anchor(closes: closes, watched: watched)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The observation about the curve's own shape. One of them, or none.
    ///
    /// The order is a RANKING and it is the interesting decision here: each
    /// line is placed by how much it tells you that the 40pt figure above it
    /// cannot. A retrace beats an extreme because the number shows neither the
    /// run nor the give-back; an extreme beats quiet because it is an event;
    /// quiet beats round-trip because "nothing happened all week" is a stronger
    /// statement than "it ended where it started".
    static func shape(closes: [Double], window: String) -> String? {
        guard closes.count >= minimumCloses,
              let first = closes.first, let last = closes.last,
              let high = closes.max(), let low = closes.min(),
              first > 0, low > 0 else { return nil }

        // 1. Ran up and gave it back. The close alone hides both halves.
        let runUp = (high - first) / first
        let given = high > last ? (high - last) / max(high - first, .leastNonzeroMagnitude) : 0
        if runUp >= 0.02, given >= giveBackShare, high > last {
            return String(localized: "Up \(PriceObject.percent(runUp).dropFirst()) at its high, and gave most of it back.")
        }

        // 2. Nothing happened — which is a real reading, and one no number on
        //    this card can give.
        //
        //    **Ranked ABOVE the extremes deliberately, and the harness caught
        //    why.** In a window that moved a third of a percent, the last close
        //    is the highest about half the time by coincidence — so checking
        //    extremes first printed "Its highest across this 1W window" over a
        //    flat line. True, and materially misleading, which is the exact
        //    class of fluent-wrong-answer this whole type is guarded against.
        if (high - low) / low < quietBand {
            return String(localized: "Quiet — it hasn't moved more than a percent across this \(window) window.")
        }

        // 3. An extreme, and only when the LAST close really is the extreme —
        //    "its highest" about a peak three days ago is a different sentence.
        if last == high, high > low {
            return String(localized: "Its highest across this \(window) window.")
        }
        if last == low, high > low {
            return String(localized: "Its lowest across this \(window) window.")
        }

        // 4. Round trip. Deliberately last: it is the weakest of the four.
        if abs((last - first) / first) * 100 < PriceObject.flatFloor {
            return String(localized: "Back where it started this \(window) window.")
        }
        return nil
    }

    /// "You watched at $0.6510, so it's up 41% since 2 June." — the one reading
    /// no market site can show, because it is the app's own record.
    ///
    /// Refused rather than guessed when the anchor is missing or nonsensical: a
    /// zero or negative watch price is not a price, and dividing by it would
    /// print a confident infinity.
    static func anchor(closes: [Double],
                       watched: (price: Double, date: Date)?) -> String? {
        guard let watched, watched.price > 0, let last = closes.last, last > 0
        else { return nil }
        let change = (last - watched.price) / watched.price
        // A move that rounds away says nothing worth a clause. Saying "it's up
        // 0.0% since you watched" is a sentence that costs a line to report
        // that nothing is being reported.
        guard abs(change * 100) >= PriceObject.flatFloor else { return nil }
        let when = watched.date.formatted(.dateTime.day().month(.abbreviated))
        let direction = change > 0
            ? String(localized: "up \(PriceObject.percent(change).dropFirst())")
            : String(localized: "down \(PriceObject.percent(change).dropFirst())")
        return String(localized: "You watched at \(money(watched.price)), so it's \(direction) since \(when).")
    }

    /// The price ramp, restated here so this file needs no view import. Kept
    /// byte-identical to `TokenChartStyle.priceText` on purpose — the object,
    /// the sentence and the curve must never print one number three ways, and
    /// the harness pins the pair.
    static func money(_ p: Double) -> String {
        if p >= 1 { return String(format: "$%.2f", p) }
        if p >= 0.01 { return String(format: "$%.4f", p) }
        return String(format: "$%.8f", p)
    }
}
