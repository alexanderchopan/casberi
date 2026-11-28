import SwiftUI

/// **$ | TAC ON TACIT'S AMOUNT (2026-11-27, user: "tac doesn't have a dollar
/// converter like the others do").** Tacit's two sheets type the figure in
/// TAC or in dollars at today's TAC price (`TacitAccount.tacPrice`), as
/// Privacy Pools' and Send's amounts do (prd §1989): the dollars work out the
/// TAC, rounded down so it is never more than typed.
@MainActor
enum TacitDollars {
    static var price: Double? { TacitAccount.shared.tacPrice.flatMap { $0 > 0 ? $0 : nil } }

    /// The TAC a typed dollar figure buys, at TAC's eight places, rounded down.
    static func tac(fromUSD text: String) -> String { MoveDollars.units(fromUSD: text, price: price, places: 8) }

    /// A TAC figure in dollars, to the cent.
    static func usd(fromTAC text: String) -> String { MoveDollars.usd(from: text, price: price) }

    /// The Amount line's figure: dollars while typing in them, else TAC.
    static func value(amount: String, dollars: String, inDollars: Bool, typing: Bool) -> String? {
        if typing, inDollars { return "$" + (dollars.isEmpty ? "0" : MoveSentence.grouped(dollars)) }
        return amount.isEmpty ? (typing ? "0 TAC" : nil) : "\(amount) TAC"
    }

    /// The line under the field: over what there is, in amber; typing in
    /// dollars, the TAC it works out to.
    static func note(amount: String, have: String, inDollars: Bool) -> (text: String, ink: Color)? {
        let against = MoveFieldNote.against(typed: amount, have: have, symbol: "TAC")
        if against?.ink == DS.attentionInk || !inDollars { return against }
        return amount.isEmpty ? against : (String(localized: "≈ \(amount) TAC"), DS.textSecondary)
    }
}

/// **$ | TOKEN, ONE CONVERSION (2026-11-27).** A dollar figure typed on the
/// keys is worked out in the token at today's price, rounded down to the
/// keys' places so it is never more than typed; the flip back is to the cent.
/// Tacit's sheets and Aztec's amount use it, as Privacy Pools' does inline.
enum MoveDollars {
    static func units(fromUSD text: String, price: Double?, places: Int) -> String {
        guard let price, price > 0, let usd = Decimal(string: text), usd > 0 else { return "" }
        var units = usd / Decimal(price), r = Decimal()
        NSDecimalRound(&r, &units, places, .down)
        return NSDecimalNumber(decimal: r).stringValue
    }

    static func usd(from text: String, price: Double?) -> String {
        guard let price, price > 0, let amount = Decimal(string: text), amount > 0 else { return "" }
        var d = amount * Decimal(price), r = Decimal()
        NSDecimalRound(&r, &d, 2, .plain)
        return NSDecimalNumber(decimal: r).stringValue
    }
}
