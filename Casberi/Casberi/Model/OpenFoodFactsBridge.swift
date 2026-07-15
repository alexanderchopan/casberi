import Foundation
import SwiftData

/// The Open Food Facts bridge (2026-07-14) — scan a grocery item's barcode and
/// the product lands in your feed, named, pictured, and graded, from the open
/// food database. Keyless and free: Open Food Facts is a public, collaborative
/// catalog (like Wikipedia for food), so this needs no account and nothing
/// about you leaves the device but the barcode you scan. Read-only.
///
/// There's no ongoing sync — a barcode is a one-shot lookup, not a feed — so
/// the bridge has no store and no foreground refresh. The seat registers on the
/// first item you land, and lives in `BridgeStore` like any other.

enum OpenFoodFacts {

    /// A product looked up from its barcode.
    struct Food {
        let barcode: String
        let name: String
        let brand: String?
        let image: String?
        /// The Nutri-Score letter (A–E), uppercased, when the database has one.
        let nutriscore: String?

        /// The product's page on Open Food Facts — where the row opens.
        var url: String { "https://world.openfoodfacts.org/product/\(barcode)" }
    }

    /// Looks a barcode up in the open database. Returns nil when the code isn't
    /// a real product there (the honest "not found", distinct from offline).
    static func lookup(_ barcode: String) async -> Food? {
        let code = barcode.filter(\.isNumber)
        guard code.count >= 8 else { return nil }
        let url = "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,image_url,nutriscore_grade,code"
        guard let root = await IngestSupport.getJSON(url) as? [String: Any],
              (root["status"] as? Int) == 1,
              let product = root["product"] as? [String: Any] else { return nil }
        let name = ((product["product_name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }   // a code with no name is no product worth a row
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        let grade = (product["nutriscore_grade"] as? String)?.uppercased()
        return Food(
            barcode: code,
            name: name,
            brand: (brand?.isEmpty == false) ? brand : nil,
            image: IngestSupport.imageURL(product["image_url"] as? String),
            nutriscore: (grade?.count == 1 && "ABCDE".contains(grade!)) ? grade : nil
        )
    }

    /// Lands a looked-up food as a product thing, deduped on its barcode.
    /// Returns the thing when newly landed, nil when it was already in the
    /// corpus (so the caller can say "already saved" rather than double-count).
    @MainActor
    @discardableResult
    static func land(_ food: Food, context: ModelContext) -> Thing? {
        let ref = "off:\(food.barcode)"
        // A single-key existence check — a targeted fetch, not the whole-corpus
        // ref scan a batch ingest uses (this is a one-shot lookup).
        var seen = FetchDescriptor<Thing>(predicate: #Predicate { $0.sourceRef == ref })
        seen.fetchLimit = 1
        if (try? context.fetch(seen))?.isEmpty == false { return nil }
        var tags = ["Food"]
        if let grade = food.nutriscore { tags.append("Nutri-Score \(grade)") }
        let thing = Thing(
            kind: .product,
            title: IngestSupport.titleLine(food.name),
            content: food.url,
            source: "Open Food Facts",
            capturedAt: .now,
            tags: tags,
            sourceRef: ref
        )
        thing.previewImageURL = food.image
        if let brand = food.brand { thing.authorHandle = brand }
        context.insert(thing)
        try? context.save()
        SpotlightIndex.index([thing])
        return thing
    }
}
