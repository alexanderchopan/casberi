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
        applyAmount(product?["value"], product?["currency"], to: thing)
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
        let thing = Thing(
            kind: .link,
            title: IngestSupport.titleLine(title),
            content: "https://www.bitrefill.com/account/invoices",
            source: "Bitrefill",
            capturedAt: firstDate(["completed_time", "created_time"], in: invoice) ?? .now,
            sourceRef: "bitrefill:invoice:\(id)"
        )
        applyAmount(payment?["price"] ?? payment?["amount"] ?? payment?["value"],
                    payment?["currency"], to: thing)
        return thing
    }

    /// The amount as a NUMBER beside the formatted one in the title (2026-08-06).
    ///
    /// Both row kinds used to carry their money only inside the title string,
    /// so every rollup in the app skipped them — a Bitrefill purchase was
    /// money in the corpus that no total could reach without re-parsing prose,
    /// which is the one thing money arithmetic here never does. It reads the
    /// same fields through the same `PriceFormat.parse` the title does, so the
    /// number and the words can't be read off different values.
    ///
    /// Written as a PAIR or not at all, and STRICTER than the title: `money`
    /// will format an amount whose currency is missing, which is fine for a
    /// string somebody reads and wrong for a number something sums — Bitrefill
    /// genuinely serves several currencies (an order's `currency` is the
    /// product's, an invoice's the payment rail's), so an unnamed one totals
    /// as whatever the reader assumes. An unreadable amount stays nil on both
    /// fields rather than landing a 0 — an unread amount is not a free order.
    ///
    /// BOTH ROW KINDS carry a POSITIVE number and they point opposite ways: an
    /// order is money out, a refill is money in. Nothing sums these rows today
    /// (Bitrefill is deliberately not in `Corpus.cardSpendSources` — its rows
    /// are `.link`), and anything that ever does must split them on
    /// `isOrderRef` first, or a top-up will read as shopping.
    private static func applyAmount(_ value: Any?, _ currency: Any?, to thing: Thing) {
        guard let amount = PriceFormat.parse(value), amount > 0,
              let code = (currency as? String)?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return }
        thing.priceValue = amount
        thing.priceCurrency = code
    }

    private static func refreshBalance(token: String) async {
        guard let root = await IngestSupport.getJSON("\(api)/accounts/balance",
                                                     auth: "Bearer \(token)") as? [String: Any]
        else { return }
        let node = (root["data"] as? [String: Any]) ?? root
        guard let amount = PriceFormat.parse(node["balance"] ?? node["amount"]) else { return }
        // A refill landing is a moment (delight pass 2026-07-21): the balance
        // rising above what it last read, never a drop (topping up isn't
        // news the other direction) — same asymmetric shape as every other
        // moment here. The FIRST read for an account seeds the mark silently.
        let previous = BitrefillBalance.rawAmount
        BitrefillBalance.set(amount: amount, currency: node["currency"] as? String ?? "USD")
        if let previous, amount > previous * 1.0001 {
            let currency = node["currency"] as? String ?? "USD"
            // `PriceFormat.string` is OPTIONAL, and interpolating it directly
            // rendered the toast as `Optional("$5.00")` — the compiler's
            // debug description, in user-facing copy. Unwrapping keeps the
            // format string (and so the localization key) byte-identical.
            // A price this can't format is the only case that fires nothing,
            // and the amount IS the news here — a refill toast with no number
            // says less than staying quiet.
            if let money = PriceFormat.string(amount, currency: currency) {
                let text = String(localized: "Bitrefill balance refilled — \(money) 💳")
                await MainActor.run { SourceMoments.shared.fire(text, source: "Bitrefill") }
            }
        }
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

    /// The raw stored amount, read BEFORE a new one overwrites it — the
    /// refill-moment check's own "previous" (nil until a first read landed).
    static var rawAmount: Double? {
        guard UserDefaults.standard.object(forKey: amountKey) != nil else { return nil }
        return UserDefaults.standard.double(forKey: amountKey)
    }
}
