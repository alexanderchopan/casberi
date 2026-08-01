import Foundation
import Observation
import SwiftData

/// The Shopify bridge (2026-07-14) — follow any Shopify store and its newest
/// products, restocks, and sale prices land in your feed as product things.
/// It reaches a store the way RSS reaches a site: fetch → filter → dedupe →
/// things, no algorithm in between. Read-only public catalog data — tapping a
/// product opens the store's own page; Casberi never checks out or pays.
///
/// Why this shape (RSS's, not OpenSea's): the person follows a LIST of stores
/// they paste, not a fixed set of toggles. Two keyless endpoints every Shopify
/// store serves without a key or account carry the whole bridge:
///   • `/<store>/meta.json` — the store's real name and currency (and the
///     honest "is this even a Shopify store?" gate: a non-Shopify host has no
///     such file).
///   • `/<store>/products.json` — the full catalog, newest first, with prices,
///     `compare_at_price` (the sale signal, no history needed — the store says
///     it's on sale), availability, and an image that becomes the row thumbnail.
///
/// Honesty: the biggest stores sit behind a bot-WAF (Akamai/Cloudflare) that
/// refuses an automated fetch. That's not an empty catalog — it's a store that
/// won't share, and the setup screen says exactly that rather than showing a
/// silent nothing.

// MARK: - The person's store list

@Observable
final class ShopifyStore {
    static let shared = ShopifyStore()
    private static let key = "shopify.stores.v1"

    struct Shop: Codable, Identifiable, Equatable {
        var id = UUID()
        /// The bare host — "allbirds.com". The join key; dedupe is by host.
        var host: String
        /// The store's own name, learned from meta.json on first sync.
        var name: String = ""
        /// ISO 4217 currency code (USD, EUR, GBP…), learned from meta.json, so
        /// a price is shown in the store's real currency, never a faked "$".
        var currency: String = ""

        var displayName: String { name.isEmpty ? host : name }
    }

    var shops: [Shop] { didSet { persist() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Shop].self, from: data) {
            shops = saved
        } else {
            shops = []
        }
    }

    var connected: Bool { !shops.isEmpty }

    /// What happened to a pasted store address. Two failures used to collapse
    /// into one `false`, which the screen then dropped on the floor — a
    /// malformed address and a store already followed both produced no message,
    /// no haptic and no field change, so "rejected" and "you didn't tap" looked
    /// identical (audit, 2026-07-31). They need different sentences: one is a
    /// typo to fix, the other is nothing to fix at all.
    enum AddOutcome {
        case added
        /// Not a usable web address — nothing to follow.
        case unreadable
        /// Already in the list; the person's already done this.
        case duplicate
    }

    /// Normalizes a pasted store URL (or bare domain) to its host and follows
    /// it. Scheme- and path-forgiving — people paste "allbirds.com",
    /// "https://www.allbirds.com/collections/mens", or a product link, and all
    /// mean the same store.
    @discardableResult
    func add(_ raw: String) -> AddOutcome {
        guard let host = Self.host(from: raw) else { return .unreadable }
        guard !shops.contains(where: { $0.host == host }) else { return .duplicate }
        shops.append(Shop(host: host))
        return .added
    }

    func remove(at offsets: IndexSet) { shops.remove(atOffsets: offsets) }

    /// Records the name + currency once meta.json resolves them — the store
    /// list learns the pretty name and the right currency symbol on first sync
    /// (RSS's learn-the-title-on-fetch pattern).
    func setMeta(name: String, currency: String, for id: UUID) {
        guard let i = shops.firstIndex(where: { $0.id == id }) else { return }
        if !name.isEmpty { shops[i].name = name }
        if !currency.isEmpty { shops[i].currency = currency }
    }

    /// The host of a pasted URL/domain, lowercased, `www.` stripped — nil when
    /// it isn't a usable host.
    static func host(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URL(string: text)?.host() else { return nil }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare.contains(".") ? bare : nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shops) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Ingest

enum ShopifyIngest {

    /// Serializes refreshes — the launch hook can race the foreground refresh,
    /// and both would read "existing" before either saved (the RSS lesson).
    @MainActor private static var running = false

    /// A store's name + currency, or nil when meta.json can't be had (the host
    /// isn't a Shopify store, or its WAF refused the fetch). A Safari-shaped UA
    /// (shared, in IngestSupport) gets through a store's bot-WAF more often.
    private static func meta(_ host: String) async -> (name: String, currency: String)? {
        guard let json = await IngestSupport.getJSON(
            "https://\(host)/meta.json", headers: ["User-Agent": IngestSupport.safariUserAgent]
        ) as? [String: Any] else { return nil }
        // A real Shopify meta.json always carries a currency; its absence means
        // this host answered but isn't a Shopify store.
        guard let currency = json["currency"] as? String, !currency.isEmpty else { return nil }
        let name = (json["name"] as? String) ?? host
        return (name, currency)
    }

    /// The newest products in a store, or nil when the catalog can't be had.
    /// Empty (not nil) is a real answer: the store is reachable but published
    /// nothing new worth landing this pass.
    private static func fetch(_ host: String, currency: String) async -> [Product]? {
        let url = "https://\(host)/products.json?limit=50"
        guard let root = await IngestSupport.getJSON(url, headers: ["User-Agent": IngestSupport.safariUserAgent]) as? [String: Any],
              let raw = root["products"] as? [[String: Any]]
        else { return nil }
        return raw.compactMap { Product(json: $0, host: host, currency: currency) }
    }

    /// One product worth landing — parsed and quality-filtered at the door.
    private struct Product {
        let id: String
        let name: String
        let url: String
        let image: String?
        let onSale: Bool
        /// The cheapest variant's price, and the store's currency — the numbers
        /// a re-check compares to say "dropped $40".
        let priceValue: Double?
        let currency: String
        /// When the store published it — so "New drops" lands the newest first,
        /// regardless of the order products.json returns.
        let published: Date?

        /// Title carries the price in the store's real currency ("Cruiser ·
        /// $105"). No currency known → the bare name, never a faked symbol.
        var title: String {
            if let priceValue, let money = PriceFormat.string(priceValue, currency: currency) {
                return IngestSupport.titleLine("\(name) · \(money)")
            }
            return IngestSupport.titleLine(name)
        }

        init?(json: [String: Any], host: String, currency: String) {
            // Shopify ids are numbers in JSON; accept either shape.
            let idValue = (json["id"] as? Int).map(String.init)
                ?? (json["id"] as? String)
            guard let id = idValue, !id.isEmpty else { return nil }
            let name = ((json["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard let handle = json["handle"] as? String, !handle.isEmpty else { return nil }

            // Price + sale come from the cheapest variant — the number a
            // shopper reads as "from". compare_at_price above price is the
            // store's own on-sale flag; no price history required.
            let variants = (json["variants"] as? [[String: Any]]) ?? []
            let priced = variants.compactMap { PriceFormat.parse($0["price"]) }
            let onSale = variants.contains { v in
                guard let p = PriceFormat.parse(v["price"]), let was = PriceFormat.parse(v["compare_at_price"])
                else { return false }
                return was > p
            }

            self.id = id
            self.name = name
            self.priceValue = priced.min()
            self.currency = currency
            self.onSale = onSale
            self.published = IngestSupport.isoDate(json["published_at"])
            self.url = "https://\(host)/products/\(handle)"
            self.image = Self.firstImage(json)
        }

        /// The first product image, normalized for RemoteThumb (https-only).
        private static func firstImage(_ json: [String: Any]) -> String? {
            let images = (json["images"] as? [[String: Any]]) ?? []
            for image in images {
                if let src = IngestSupport.imageURL(image["src"] as? String) { return src }
            }
            return nil
        }
    }

    /// Fetches the newest products in every followed store and lands new ones
    /// as product things. Returns the number of NEW things, 0 when up to date,
    /// nil when nothing was reachable (offline, or every store refused).
    @MainActor
    static func refresh(context: ModelContext) async -> Int? {
        let store = ShopifyStore.shared
        let shops = store.shops
        guard !shops.isEmpty, !running else { return running ? 0 : nil }
        running = true
        defer { running = false }

        // Resolve meta (name + currency) for any store that hasn't learned it,
        // and drop stores that can't be reached at all — those report failure.
        var reachable: [(shop: ShopifyStore.Shop, currency: String)] = []
        for shop in shops {
            var currency = shop.currency
            if currency.isEmpty {
                guard let meta = await meta(shop.host) else { continue }
                currency = meta.currency
                store.setMeta(name: meta.name, currency: meta.currency, for: shop.id)
            }
            reachable.append((shop, currency))
        }
        guard !reachable.isEmpty else { return nil }

        let results = await IngestSupport.boundedGather(reachable, maxConcurrent: 4) { entry in
            await fetch(entry.shop.host, currency: entry.currency)
        }

        var existing = IngestSupport.existingSourceRefs(context, source: "Shopify")
        let landed = IngestSupport.thingsByRef(context, source: "Shopify")
        let backfill = ArtlessBackfill(context, source: "Shopify")
        var added = 0
        var touched = false
        var reachedAny = false

        for (entry, result) in zip(reachable, results) {
            guard let products = result else { continue }
            reachedAny = true
            // Newest first, so "New drops" lands the newest — products.json's
            // own order isn't guaranteed by date.
            let ordered = products.sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
            // EVERY already-landed product is re-checked for a price move (a
            // drop on an older, long-followed item is exactly what price-watch
            // exists to catch); only NEW products are capped — the newest 12
            // per store, because the catalog is a firehose and the corpus isn't.
            var landedThisStore = 0
            for product in ordered {
                let ref = "shopify:\(entry.shop.host):\(product.id)"
                if existing.contains(ref) {
                    backfill.patch(ref, image: product.image)
                    if let thing = landed[ref], let now = product.priceValue {
                        if let before = thing.priceValue, now < before {
                            // A DROP — re-stamp capturedAt so it rides "while I
                            // was away", show "was $X" beside today's price, tag it.
                            thing.capturedAt = .now
                            if !thing.tags.contains("Price drop") { thing.tags.append("Price drop") }
                            let was = PriceFormat.string(before, currency: product.currency).map { " (was \($0))" } ?? ""
                            thing.title = IngestSupport.titleLine(product.title + was)
                            thing.priceValue = now
                            thing.priceCurrency = product.currency
                            thing.embedding = nil          // title changed → re-embed
                            touched = true
                        } else if thing.priceValue != now {
                            // Rose or first-seen number — update in place, and
                            // clear a stale "Price drop" tag now the price recovered.
                            thing.priceValue = now
                            thing.priceCurrency = product.currency
                            thing.title = product.title
                            thing.tags.removeAll { $0 == "Price drop" }
                            thing.embedding = nil
                            touched = true
                        }
                    }
                    continue
                }
                guard landedThisStore < 12 else { continue }
                let thing = Thing(
                    kind: .product,
                    title: product.title,
                    content: product.url,
                    source: "Shopify",
                    capturedAt: .now,
                    tags: product.onSale ? ["Sale"] : [],
                    sourceRef: ref
                )
                thing.previewImageURL = product.image
                thing.priceValue = product.priceValue
                thing.priceCurrency = product.currency
                // Which store it came from — the row names it when more than
                // one store is followed (the RSS/Wallet naming pattern).
                thing.authorHandle = entry.shop.displayName
                context.insert(thing)
                existing.insert(ref)
                SpotlightIndex.index([thing])
                added += 1
                landedThisStore += 1
            }
        }
        if added > 0 || backfill.any || touched { context.saveHonestly() }
        return reachedAny ? added : nil
    }
}
