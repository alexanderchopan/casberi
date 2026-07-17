import Foundation

/// Bitrefill (2026-07-17) — the crypto gift-card account, read side only.
/// A personal API key (bitrefill.com/account/developers) reads the account
/// over Bearer auth against `api-bitrefill.com` (a dash, not a dot — their
/// real API host): orders land as things wearing the product's own artwork,
/// deposit invoices land as balance refills, and the balance itself feeds
/// the source's lede. Nothing here ever creates an invoice or spends.
///
/// Honesty ceiling, verified against the API schema 2026-07-17: an order
/// carries product/name/value/image and delivered_time, but NO redemption
/// status (Bitrefill can't know a code was spent at Amazon) and NO expiry —
/// so rows never claim "unused" or "expires"; the shelf/pulse mock stays
/// deferred until the API can back it (prd ruling §103). The same schema
/// dates every time field as an ISO8601 STRING and returns JSON `null` for
/// a not-yet-delivered order's `delivered_time` — `firstDate` reads the
/// first field that actually parses, so a null never poisons the fallback.
enum BitrefillFetch {

    static let api = "https://api-bitrefill.com/v2"

    /// True for an order thing's ref — the classification the lede needs,
    /// owned here beside the ref it mints (`orderThing`), never re-spelled
    /// as a literal in the view.
    static func isOrderRef(_ ref: String?) -> Bool {
        ref?.hasPrefix("bitrefill:order:") ?? false
    }

    /// Orders + deposit invoices + a balance read. Returns nil only when the
    /// ORDERS read fails — the honest token-rejected signal TokenIngest words
    /// as "check the token"; a failed invoices read just means no refill rows.
    /// Orders gates first (it's the token check); invoices and the balance are
    /// then independent, so they run concurrently (the `async let` norm).
    static func things(token: String) async -> [Thing]? {
        guard let orders = await list("\(api)/orders?limit=50", token: token) else { return nil }
        async let invoicesTask = list("\(api)/invoices?limit=50", token: token)
        async let balanceTask: Void = refreshBalance(token: token)
        var things = orders.compactMap(orderThing)
        if let invoices = await invoicesTask {
            things += invoices.compactMap(depositThing)
        }
        await balanceTask
        return things
    }

    /// A purchase: "Amazon.com · $50", the product's artwork as the thumb,
    /// dated when it was delivered. Covers every product type honestly —
    /// gift card, top-up, eSIM — since the title claims only name and price.
    /// A gift order carries a real per-item permalink (`gift_url`); a plain
    /// order has none in the API, so it opens the account's orders page.
    private static func orderThing(_ order: [String: Any]) -> Thing? {
        guard let id = order["id"] as? String else { return nil }
        let product = order["product"] as? [String: Any]
        let name = (product?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Bitrefill order"
        let title = money(product?["value"], product?["currency"])
            .map { "\(name) · \($0)" } ?? name
        let giftURL = (order["gift_info"] as? [String: Any])?["gift_url"] as? String
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: giftURL ?? "https://www.bitrefill.com/account/orders",
            source: "Bitrefill",
            capturedAt: firstDate(["delivered_time", "created_time"], in: order) ?? .now,
            sourceRef: "bitrefill:order:\(id)"
        )
        thing.previewImageURL = IngestSupport.imageURL(product?["image"] as? String)
        return thing
    }

    /// A deposit: an invoice with no orders on it is money added to the
    /// balance — "Balance refill · $50 in bitcoin". Order-bearing invoices
    /// are skipped; their orders already landed as their own rows. The orders
    /// field is read as `[Any]` (not `[[String:Any]]`), so an invoice whose
    /// orders arrive as ID strings is still recognised as a purchase, not
    /// mis-emitted as a phantom refill that double-counts the same spend.
    private static func depositThing(_ invoice: [String: Any]) -> Thing? {
        guard let id = invoice["id"] as? String,
              ((invoice["orders"] as? [Any]) ?? []).isEmpty else { return nil }
        let payment = invoice["payment"] as? [String: Any]
        var title = "Balance refill"
        if let amount = money(payment?["price"] ?? payment?["amount"] ?? payment?["value"],
                              payment?["currency"]) {
            title += " · \(amount)"
        }
        if let method = (payment?["method"] as? String).map(methodName) {
            title += " in \(method)"
        }
        return Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: "https://www.bitrefill.com/account/invoices",
            source: "Bitrefill",
            capturedAt: firstDate(["completed_time", "created_time"], in: invoice) ?? .now,
            sourceRef: "bitrefill:invoice:\(id)"
        )
    }

    private static func refreshBalance(token: String) async {
        guard let root = await IngestSupport.getJSON("\(api)/accounts/balance",
                                                     auth: "Bearer \(token)") as? [String: Any]
        else { return }
        let node = (root["data"] as? [String: Any]) ?? root
        guard let amount = PriceFormat.parse(node["balance"] ?? node["amount"]) else { return }
        BitrefillBalance.set(amount: amount, currency: node["currency"] as? String ?? "USD")
    }

    /// The v2 list envelope — `{"meta": …, "data": […]}` — with a fallback
    /// for a bare array, so a wrapper change degrades to "no rows", never a
    /// crash.
    private static func list(_ url: String, token: String) async -> [[String: Any]]? {
        let root = await IngestSupport.getJSON(url, auth: "Bearer \(token)")
        if let bare = root as? [[String: Any]] { return bare }
        return (root as? [String: Any])?["data"] as? [[String: Any]]
    }

    /// The first of `keys` whose value parses as an ISO8601 date. A JSON
    /// `null` deserialises to `NSNull` (a non-nil `Any`), so a plain
    /// `a ?? b` would keep the null and never reach `b`; `isoDate` reads only
    /// strings, so a null field is skipped and the next key is tried.
    private static func firstDate(_ keys: [String], in dict: [String: Any]) -> Date? {
        for key in keys {
            if let date = IngestSupport.isoDate(dict[key]) { return date }
        }
        return nil
    }

    /// "$50", "€25", "SEK 12.40" — the shared product formatter, so a
    /// Bitrefill row reads a price exactly as a Shopify/Deals row does
    /// (NumberFormatter on the ISO currency: whole amounts drop the cents,
    /// the symbol is never guessed). The value arrives as a number OR a
    /// string depending on endpoint; `PriceFormat.parse` reads both.
    private static func money(_ value: Any?, _ currency: Any?) -> String? {
        guard let amount = PriceFormat.parse(value) else { return nil }
        return PriceFormat.string(amount, currency: currency as? String)
    }

    /// The payment rail, in Bob's words — "lightning" IS bitcoin, and a
    /// chain-suffixed stablecoin ("usdt_trc20") is just the coin.
    private static func methodName(_ raw: String) -> String {
        let base = raw.split(separator: "_").first.map(String.init) ?? raw
        switch base {
        case "lightning":                  return "bitcoin"
        case "usdt", "usdc", "btc", "eth": return base.uppercased()
        default:                           return base
        }
    }
}

/// The account balance, cached for the feed's lede. UserDefaults, not the
/// corpus — a balance is a reading, not a thing. `formatted` is nil until a
/// read has actually landed, so the lede never invents a $0; `clear()` drops
/// it when the token is removed, so a reconnected DIFFERENT account never
/// wears the prior account's balance. Formatting routes through the shared
/// `PriceFormat`, so the lede and the order rows can't disagree on style.
enum BitrefillBalance {
    private static let amountKey   = "bitrefill.balance.amount"
    private static let currencyKey = "bitrefill.balance.currency"

    static func set(amount: Double, currency: String) {
        UserDefaults.standard.set(amount, forKey: amountKey)
        UserDefaults.standard.set(currency, forKey: currencyKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: amountKey)
        UserDefaults.standard.removeObject(forKey: currencyKey)
    }

    static var formatted: String? {
        guard UserDefaults.standard.object(forKey: amountKey) != nil else { return nil }
        let amount = UserDefaults.standard.double(forKey: amountKey)
        return PriceFormat.string(amount, currency: UserDefaults.standard.string(forKey: currencyKey) ?? "USD")
    }
}
