import Foundation

/// The US-dollar coins (prd §1090): a quantity of one IS a dollar amount, so a
/// move in it can be stated in dollars with no rate.
///
/// An EXPLICIT set, never a prefix or substring rule: `hasPrefix("USD")` would
/// also swallow every scam token that names itself `USDCoin` or `USDT_CLAIM`,
/// and this app already raises a `spoofedSymbol` warning for exactly that.
///
/// The stable share it also held (the holdings card's "21% stables") is
/// deleted with the line that drew it (prd §1309).
///
/// PURE AND FOUNDATION-ONLY, so the shipped source compiles standalone under
/// `scripts/wallet-viz-selftest.sh`.
enum WalletStables {

    static let dollarSymbols: Set<String> = [
        "USDC", "USDC.E", "USDBC", "USDT", "USDT.E", "DAI", "USDS",
        "USDE", "PYUSD", "TUSD", "FDUSD", "LUSD", "SUSD", "CRVUSD",
        "GHO", "FRAX", "BUSD", "RLUSD", "USDG", "USDP", "GUSD", "USDD", "USD0",
        "DOLA", "MIM", "USDL", "AUSD", "USDF",
    ]

    static func isDollar(_ symbol: String) -> Bool {
        dollarSymbols.contains(symbol.trimmingCharacters(in: .whitespaces).uppercased())
    }
}
