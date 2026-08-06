import Foundation
import SwiftData

/// Gives an x402 seller a face (2026-08-06).
///
/// Every row in this room wore the same Circle mark, because Circle's directory
/// serves no image of any kind — it names a website and nothing else. One page
/// read per seller turns that into the company's own `og:image`.
///
/// ## It stamps the PICTURE and nothing else
///
/// The single most important line in this file is the one that isn't here: it
/// never touches `title`. `LinkTitle.enrich` renames a link still wearing its
/// URL, and that is right for a pasted link and wrong here — a seller's row is
/// named from Circle's directory, which is the authority on who they are, and
/// a marketing `<title>` ("Alchemy | The Web3 Development Platform") would
/// overwrite a good name with a slogan. §245 made exactly this ruling for
/// Instagram's imported rows; this is the same one.
///
/// ## Bounded, paced, self-terminating
///
/// A second act like `-tiktokFaces`, and under no deadline at all — unlike
/// Snapchat's expiring memories, a company's home page will still be there
/// tomorrow. So it runs behind `dueForHeal`, a small slice per pass, and asks
/// each seller exactly ONCE ever: a page that serves no `og:image` is a fact
/// about that company, not a transient failure, and re-asking it every
/// foreground forever would be a request budget spent on a known answer.
///
/// ## Receipts
///
/// The hosts here come from Circle's directory, so no static registry could
/// ever contain them (`NetworkReach`'s stated blind spot). The call names its
/// own service to `NetworkLedger` instead, which is the documented handling for
/// exactly this case — otherwise every seller's domain reads on the receipts
/// screen as an undisclosed reach.
enum X402Faces {

    /// Sellers asked per pass. Small on purpose: this is pure polish, and it
    /// competes with the foreground sweep's ~45 other slots.
    static let perPass = 6

    /// Which sellers have been asked, ever — including the ones that answered
    /// with nothing, so a page with no `og:image` is asked once and never again.
    private static let askedKey = "x402.faces.asked.v1"

    private static var asked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: askedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: askedKey) }
    }

    /// Forgets the ledger so a reconnect can try again — a seller may well have
    /// added an image since.
    static func reset() { UserDefaults.standard.removeObject(forKey: askedKey) }

    /// Reads up to `perPass` seller pages and stamps whatever picture they
    /// declare. Returns how many rows gained a face.
    @MainActor
    @discardableResult
    static func heal(context: ModelContext) async -> Int {
        var seen = asked
        // Snapshot the work as VALUES before any await — ref and URL, never a
        // `Thing` carried across a suspension (corollary 6).
        let rows = IngestSupport.thingsByRef(context, source: X402Ingest.source)
        var jobs: [(ref: String, url: URL)] = []
        for (ref, thing) in rows {
            guard thing.isLive, thing.previewImageURL == nil, !seen.contains(ref) else { continue }
            guard let url = URL(string: thing.content), url.scheme?.lowercased() == "https" else { continue }
            jobs.append((ref, url))
            if jobs.count >= perPass { break }
        }
        guard !jobs.isEmpty else { return 0 }

        var found: [String: String] = [:]
        for job in jobs {
            seen.insert(job.ref)
            if let image = await ogImage(job.url) { found[job.ref] = image }
        }
        asked = seen
        guard !found.isEmpty else { return 0 }

        // Re-fetch AFTER the awaits — the rows above are stale by definition
        // now, and a delete may have landed while this was reading the network.
        let fresh = IngestSupport.thingsByRef(context, source: X402Ingest.source)
        var stamped = 0
        for (ref, image) in found {
            guard let thing = fresh[ref], thing.isLive, thing.previewImageURL == nil else { continue }
            thing.previewImageURL = image
            stamped += 1
        }
        if stamped > 0 { context.saveHonestly() }
        return stamped
    }

    /// The page's declared image, or nil. Reuses `ProductMeta.parse`, which
    /// already reads `og:image` (and JSON-LD's, and falls back cleanly) — the
    /// fetch is spelled out here only so the receipt names THIS bridge rather
    /// than "Saved links".
    static func ogImage(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(IngestSupport.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        NetworkLedger.shared.record(request, as: X402Ingest.source)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let html = String(decoding: data.prefix(400_000), as: UTF8.self)
        // `image` only. The parsed title is deliberately discarded — see the
        // header: Circle's directory names these companies, not their own SEO.
        return ProductMeta.parse(html)?.image
    }
}
