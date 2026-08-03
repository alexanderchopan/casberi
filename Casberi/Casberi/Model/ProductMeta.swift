import Foundation

/// Formats and parses product prices — one place, so Shopify, Deals, and the
/// pasted-product parser all read and write a price the same way.
enum PriceFormat {
    /// Formats an amount in its own currency. Whole amounts drop the cents
    /// ("$105", not "$105.00"); the ISO currency picks the symbol, so a GBP
    /// price reads "£", never a guessed "$". nil when no currency is known.
    static func string(_ amount: Double, currency: String?) -> String? {
        guard let currency, !currency.isEmpty else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        let whole = amount == amount.rounded()
        f.maximumFractionDigits = whole ? 0 : 2
        f.minimumFractionDigits = whole ? 0 : 2   // else the currency default (2) re-adds ".00"
        return f.string(from: amount as NSNumber)
    }

    /// A price number out of a JSON number or a human/string price. Handles US
    /// and European grouping/decimal conventions ("1,299.00" and "1.299,00"
    /// both → 1299; "12,99" → 12.99); nil when there's no number to read. One
    /// parser so Shopify's variant strings and a scraped page's price agree.
    static func parse(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        guard let s0 = raw as? String else { return nil }
        let s = s0.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !s.isEmpty else { return nil }
        let hasDot = s.contains("."), hasComma = s.contains(",")
        var norm = s
        if hasDot && hasComma {
            // The LAST separator is the decimal; the other is grouping.
            if s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                norm = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                norm = s.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            // Comma only: a decimal when exactly two digits trail it ("12,99"),
            // otherwise grouping ("1,299").
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            norm = (parts.count == 2 && parts[1].count == 2)
                ? s.replacingOccurrences(of: ",", with: ".")
                : s.replacingOccurrences(of: ",", with: "")
        }
        return Double(norm)
    }
}

/// A product's price and identity, read off its own web page — the best-effort
/// parser behind price-watch on a pasted product URL. Most e-commerce pages
/// carry one of three machine-readable price sources; this tries all three and
/// returns nil (never a guess) when none is present, so a page with no price
/// stays an ordinary link rather than wearing a made-up number.
struct ProductMeta {
    let title: String?
    let priceValue: Double?
    let priceCurrency: String?
    let image: String?

    /// True when the page actually declared a price — the signal that a saved
    /// link is a product worth watching, not just any web page.
    var isProduct: Bool { priceValue != nil }

    /// Fetches a page and parses its price/identity. Reads at most 400KB — the
    /// head and structured-data blocks live near the top of every product page.
    /// Also carries the plain <title>, so a caller enriching a pasted link
    /// never needs a second fetch for a non-product page.
    static func fetch(_ url: URL) async -> ProductMeta? {
        var request = URLRequest(url: url)
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        // "Saved links" again — same page, read for its product facts.
        NetworkLedger.shared.record(request, as: "Saved links")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        return parse(html)
    }

    static func parse(_ html: String) -> ProductMeta? {
        // 1 — JSON-LD Product (the richest, most reliable source).
        var value: Double?
        var currency: String?
        var title: String?
        var image: String?
        if let ld = jsonLDProduct(html) {
            value = ld.price
            currency = ld.currency
            title = ld.name
            image = ld.image
        }
        // 2 — Open Graph / product meta tags fill any gap JSON-LD left.
        if value == nil, let amount = meta(html, ["product:price:amount", "og:price:amount"]) {
            value = PriceFormat.parse(amount)
        }
        if currency == nil {
            currency = meta(html, ["product:price:currency", "og:price:currency"])
        }
        // 3 — schema.org microdata (itemprop) as a last resort.
        if value == nil, let amount = meta(html, ["price"]) { value = PriceFormat.parse(amount) }
        if title == nil { title = meta(html, ["og:title"]) }
        if title == nil { title = htmlTitle(html) }
        if image == nil { image = meta(html, ["og:image"]) }

        guard value != nil || title != nil else { return nil }
        return ProductMeta(title: title.map { IngestSupport.decodeHTMLEntities($0) },
                           priceValue: value,
                           priceCurrency: currency?.uppercased(),
                           image: IngestSupport.imageURL(image))
    }

    // MARK: - JSON-LD

    private struct LDProduct { let name: String?; let price: Double?; let currency: String?; let image: String? }

    /// Scans every `<script type="application/ld+json">` block for a Product
    /// (directly, in an array, or under an `@graph`) and pulls its first offer.
    private static func jsonLDProduct(_ html: String) -> LDProduct? {
        let scanner = Scanner(string: html)
        scanner.charactersToBeSkipped = nil
        while !scanner.isAtEnd {
            guard scanner.scanUpToString("application/ld+json") != nil,
                  scanner.scanUpToString(">") != nil,
                  scanner.scanString(">") != nil,
                  let body = scanner.scanUpToString("</script>") else { break }
            guard let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let product = findProduct(json) { return product }
        }
        return nil
    }

    /// Depth-first search for a `@type: Product` node in a JSON-LD value.
    private static func findProduct(_ any: Any) -> LDProduct? {
        if let array = any as? [Any] {
            for element in array { if let p = findProduct(element) { return p } }
            return nil
        }
        guard let obj = any as? [String: Any] else { return nil }
        if let graph = obj["@graph"] { if let p = findProduct(graph) { return p } }
        // @type may be a string or an array ("@type": ["Thing","Product"]) — a
        // Product is a Product wherever it appears in that list.
        let types: [String] = (obj["@type"] as? String).map { [$0] } ?? (obj["@type"] as? [String]) ?? []
        let isProduct = types.contains { $0.caseInsensitiveCompare("Product") == .orderedSame }
        guard isProduct else {
            // Not a Product node itself — but a nested value might be.
            for value in obj.values where value is [String: Any] || value is [Any] {
                if let p = findProduct(value) { return p }
            }
            return nil
        }
        // An offer can be an object or an array of them. Take the cheapest
        // offer and read ITS currency — the price and the currency must come
        // from the same offer, or a $80 EUR offer reads as "$80".
        let offers = (obj["offers"] as? [String: Any]).map { [$0] }
            ?? (obj["offers"] as? [[String: Any]]) ?? []
        let priced: [(price: Double, currency: String?)] = offers.compactMap { offer in
            guard let p = PriceFormat.parse(offer["price"]) ?? PriceFormat.parse(offer["lowPrice"])
            else { return nil }
            return (p, offer["priceCurrency"] as? String)
        }
        let cheapest = priced.min { $0.price < $1.price }
        let image = (obj["image"] as? String) ?? (obj["image"] as? [String])?.first
            ?? ((obj["image"] as? [String: Any])?["url"] as? String)
        return LDProduct(name: obj["name"] as? String, price: cheapest?.price,
                         currency: cheapest?.currency, image: image)
    }

    // MARK: - Meta tags

    /// The `content` of the first `<meta>` whose property/name/itemprop matches
    /// any key. Attribute order varies, so it matches the key attribute and the
    /// content attribute independently within one tag.
    private static func meta(_ html: String, _ keys: [String]) -> String? {
        // Match a full <meta> tag, allowing a quoted attribute value to carry a
        // literal `>` without ending the tag early.
        let pattern = "<meta\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            guard let key = attribute(tag, ["property", "name", "itemprop"]),
                  keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
                  let content = attribute(tag, ["content"]), !content.isEmpty
            else { continue }
            return content
        }
        return nil
    }

    /// The value of the first of `names` present as an attribute in `tag`.
    /// Matches against the ACTUAL opening quote (so a value containing the other
    /// quote type — "Levi's 501" in a double-quoted content — isn't truncated),
    /// and requires a real left boundary so `name` never matches inside
    /// `data-name` / `data-content`.
    private static func attribute(_ tag: String, _ names: [String]) -> String? {
        let ns = tag as NSString
        for name in names {
            let pattern = "(?<![-\\w])\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length))
            else { continue }
            // Group 1 = double-quoted value, group 2 = single-quoted.
            for i in 1...2 where m.range(at: i).location != NSNotFound {
                return ns.substring(with: m.range(at: i))
            }
        }
        return nil
    }

    /// The plain `<title>` of a page — the fallback identity when there's no
    /// og:title, so a caller needn't re-fetch the page for it.
    private static func htmlTitle(_ html: String) -> String? {
        guard let open = html.range(of: "<title", options: [.caseInsensitive]),
              let openEnd = html.range(of: ">", range: open.upperBound..<html.endIndex),
              let close = html.range(of: "</title>", options: [.caseInsensitive],
                                     range: openEnd.upperBound..<html.endIndex)
        else { return nil }
        let raw = String(html[openEnd.upperBound..<close.lowerBound])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }
}
