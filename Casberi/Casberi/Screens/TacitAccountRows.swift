import Foundation

/// TACIT'S AMOUNTS, AS WORDS. The page these rows drew is deleted (prd §1981):
/// Tacit's money stands in Holdings › Private, its verbs in Move (Make
/// private §1976, back to public §1977), its addresses on Receive, and
/// Connect, Read again and Disconnect on its account page (`TacitScreen`).
enum TacitAccountRows {
    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...4)))
    }
}
