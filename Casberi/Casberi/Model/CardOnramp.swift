import Foundation

/// **Move › Buy (prd §1599).** A card buys USDC or ETH straight
/// into your account, through a seller's own page: Stripe on Ethereum, Ramp
/// on Base. No server and no fee of ours. Each page does the sign-in, the ID
/// check and the payment itself; the coins land as an ordinary arrival, read
/// off the chain like any other.
///
/// **One seller per network, never a choice that cannot work.** Stripe's
/// no-account link takes Ethereum, Solana, Polygon and Bitcoin only (read off
/// `crypto-onramp-outer.js`, 2026-10-28: `btc sol matic eth usdc` on
/// `bitcoin ethereum solana polygon`), so Base is Ramp's. Ramp refuses to
/// draw without a partner key ("Integration issue detected", seen
/// 2026-10-28), so until `rampHostKey` holds one, Base offers no card.
///
/// **What each page is told.** Stripe's link names the coin and the network
/// and cannot take an address: the address is copied before the page opens,
/// and Link keeps it after the first buy. Ramp's takes the address too.
/// Ramp's parameter names are from its docs and UNMEASURED until a key
/// draws the page.
enum CardOnramp {
    enum Seller: Sendable, Equatable {
        case stripe, ramp

        var name: String {
            switch self {
            case .stripe: "Stripe"
            case .ramp: "Ramp"
            }
        }

        /// Whether the page is handed the address, or the person pastes it.
        var takesAddress: Bool { self == .ramp }
    }

    enum Coin: String, CaseIterable, Sendable {
        case usdc, eth

        var symbol: String { rawValue.uppercased() }
    }

    static let ethereum = 1
    static let base = 8453

    /// Ramp's partner key: a public identifier that counts purchases made
    /// through Casberi and is safe in a URL (Ramp's own words), so it lives
    /// here like the Reown project id. Nil until Ramp issues one.
    static let shippedRampKey: String? = nil

    static var rampHostKey: String? {
        #if DEBUG
        // `-rampHostKey <key>`: draw Ramp's page before the key ships.
        if let key = UserDefaults.standard.string(forKey: "rampHostKey"), !key.isEmpty { return key }
        #endif
        return shippedRampKey
    }

    /// The seller for a network, or nil where no card can buy.
    static func seller(chainId: Int, rampKey: String? = rampHostKey) -> Seller? {
        switch chainId {
        case ethereum: .stripe
        case base: rampKey == nil ? nil : .ramp
        default: nil
        }
    }

    /// The seller's page with the coin, the network and the dollars set, and
    /// the address where the page takes one; nil where no card can buy, or
    /// for an address Ramp would not be safe to hand. No dollars (empty, zero
    /// or not a number) leaves the amount to the page.
    static func url(_ coin: Coin, chainId: Int, address: String, dollars: String = "",
                    rampKey: String? = rampHostKey) -> URL? {
        let usd = wholeCents(dollars)
        switch seller(chainId: chainId, rampKey: rampKey) {
        case .stripe:
            var c = URLComponents(string: "https://crypto.link.com")!
            // The coin and network as the only choice: the page reads
            // "Buy USDC (Ethereum)".
            var items = [
                URLQueryItem(name: "destination_currency", value: coin.rawValue),
                URLQueryItem(name: "destination_network", value: "ethereum"),
                URLQueryItem(name: "supported_destination_currencies", value: coin.rawValue),
                URLQueryItem(name: "supported_destination_networks", value: "ethereum"),
            ]
            if let usd {
                items += [URLQueryItem(name: "source_currency", value: "usd"),
                          URLQueryItem(name: "source_amount", value: dollarsText(usd))]
            }
            c.queryItems = items
            return c.url
        case .ramp:
            guard let rampKey, isEVMAddress(address) else { return nil }
            var c = URLComponents(string: "https://app.ramp.network")!
            var items = [
                URLQueryItem(name: "hostApiKey", value: rampKey),
                URLQueryItem(name: "hostAppName", value: "Casberi"),
                URLQueryItem(name: "enabledFlows", value: "ONRAMP"),
                URLQueryItem(name: "defaultFlow", value: "ONRAMP"),
                URLQueryItem(name: "enabledCryptoAssets", value: "BASE_\(coin.symbol)"),
                URLQueryItem(name: "userAddress", value: address),
            ]
            // Ramp counts the amount in the currency's smallest unit
            // ("10.00 EUR becomes 1000", its docs).
            if let usd {
                items += [URLQueryItem(name: "inAsset", value: "USD"),
                          URLQueryItem(name: "inAssetValue", value: String(usd))]
            }
            c.queryItems = items
            return c.url
        case nil:
            return nil
        }
    }

    /// Typed dollars as whole cents, "50" → 5000, "12.345" → 1234; nil for
    /// nothing, zero or anything not a number.
    static func wholeCents(_ typed: String) -> Int? {
        // A decimal pad types "12,5" where the comma is the decimal mark.
        var t = typed.trimmingCharacters(in: .whitespaces)
        t = t.contains(".") ? t.replacingOccurrences(of: ",", with: "") : t.replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")), d > 0, d < 1_000_000 else { return nil }
        var cents = d * 100, whole = Decimal()
        NSDecimalRound(&whole, &cents, 0, .down)
        let n = NSDecimalNumber(decimal: whole).intValue
        return n > 0 ? n : nil
    }

    /// Cents as dollars for a URL: 5000 → "50", 1234 → "12.34".
    static func dollarsText(_ cents: Int) -> String {
        cents % 100 == 0 ? String(cents / 100) : String(format: "%d.%02d", cents / 100, cents % 100)
    }

    static func isEVMAddress(_ s: String) -> Bool {
        s.count == 42 && s.hasPrefix("0x") && s.dropFirst(2).allSatisfy(\.isHexDigit)
    }
}
