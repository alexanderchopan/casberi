import Foundation

/// **TOKENS YOU HID FROM HOLDINGS (user: "should be able to long press and
/// hide a token").** By symbol, the portfolio's own identity for a position
/// (`WalletPortfolio.Position.id`). A hidden token leaves the list, the map
/// and the total; Holdings ends in one row that names how many are hidden and
/// brings each back, so the total never drops a token silently (§83).
enum HiddenTokens {
    static let key = "wallet.hiddenTokens"

    static var symbols: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func set(_ symbol: String, hidden: Bool) {
        var all = symbols
        if hidden { all.insert(symbol.uppercased()) } else { all.remove(symbol.uppercased()) }
        UserDefaults.standard.set(all.sorted(), forKey: key)
    }
}

extension WalletPortfolio {
    /// This portfolio without the tokens you hid, its total with them out.
    func hiding(_ symbols: Set<String>) -> WalletPortfolio {
        guard !symbols.isEmpty else { return self }
        var kept = self
        let gone = positions.filter { symbols.contains($0.symbol.uppercased()) }
        guard !gone.isEmpty else { return self }
        kept.positions.removeAll { symbols.contains($0.symbol.uppercased()) }
        kept.totalUSD = max(0, totalUSD - gone.reduce(0) { $0 + $1.usd })
        return kept
    }
}
