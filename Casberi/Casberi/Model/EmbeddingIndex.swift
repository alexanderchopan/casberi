import Foundation
import NaturalLanguage
import SwiftData

/// On-device semantic index (2026-07-12) — a sentence-embedding vector per
/// thing, so the answer path can retrieve by MEANING, not just shared words:
/// "travel plans" reaches "Flight to Lisbon" with zero word overlap. Fully
/// on-device (Apple's NaturalLanguage sentence embedding) — no server.
///
/// Vectors are DERIVED, so they're built by a lazy backfill sweep, never at the
/// ~35 capture sites — which also embeds CloudKit-synced and pre-existing
/// things. The vector rides the thing as packed Float32 bytes (`Thing.embedding`).
enum EmbeddingIndex {
    /// Apple's on-device sentence embedding. nil on runtimes/locales without
    /// one — every path guards, and retrieval falls back to keyword scoring
    /// (zero regression when this is absent).
    private static let model = NLEmbedding.sentenceEmbedding(for: .english)

    static var isAvailable: Bool { model != nil }

    /// The text an answer would match on — the title carries most of the
    /// signal; a short body slice adds substance, and a link's fetched article
    /// text (`enrichedText`) carries what the title alone never could. Capped:
    /// a sentence embedding wants a sentence, not a document, and long inputs
    /// cost more for no gain — but 800 leaves room for a link's lede past its
    /// title (raised from 500, 2026-07-15).
    static func indexText(for thing: Thing) -> String {
        let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [thing.title]
        if !body.isEmpty, body != thing.title { parts.append(body) }
        if let extra = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extra.isEmpty {
            parts.append(extra)
        }
        return String(parts.joined(separator: ". ").prefix(800))
    }

    /// An embedding vector for arbitrary text, as Float. nil when the model is
    /// absent or the text is empty/unembeddable.
    static func vector(for text: String) -> [Float]? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard let model, !trimmed.isEmpty,
              let v = model.vector(for: trimmed) else { return nil }
        return v.map(Float.init)
    }

    // MARK: Packing

    static func pack(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Euclidean norm of a vector — computed once per query so `similarity`
    /// doesn't recompute the query's magnitude for every thing it scores.
    static func norm(_ v: [Float]) -> Float {
        var sum: Float = 0
        for x in v { sum += x * x }
        return sum.squareRoot()
    }

    // MARK: Similarity

    /// Cosine of a query vector against a thing's PACKED stored vector, read in
    /// place — no intermediate `[Float]` allocation, since retrieval scores this
    /// against every thing on the (main-thread) Ask path. `queryNorm` is the
    /// query's precomputed magnitude. Returns 0 for a zero/degenerate or
    /// length-mismatched vector (a cross-revision `NLEmbedding` blob of a
    /// different dimension is simply excluded, never a crash). `loadUnaligned`
    /// tolerates `Data` that isn't 4-byte aligned.
    static func similarity(query: [Float], queryNorm: Float, packed: Data) -> Double {
        let stride = MemoryLayout<Float>.stride
        let count = packed.count / stride
        guard count == query.count, count > 0, queryNorm > 0 else { return 0 }
        return packed.withUnsafeBytes { raw -> Double in
            var dot: Float = 0, nb: Float = 0
            for i in 0..<count {
                let y = raw.loadUnaligned(fromByteOffset: i * stride, as: Float.self)
                dot += query[i] * y
                nb += y * y
            }
            guard nb > 0 else { return 0 }
            return Double(dot / (queryNorm * nb.squareRoot()))
        }
    }

    // MARK: Backfill

    private static var isSweeping = false

    /// Fire-and-forget: embed everything not yet indexed, off the critical path.
    /// Single-flighted and idempotent — safe to call every foreground. The
    /// answer path stays keyword-only for anything the sweep hasn't reached yet.
    @MainActor
    static func backfill(context: ModelContext) {
        guard isAvailable, !isSweeping else { return }
        isSweeping = true
        Task { @MainActor in
            defer { isSweeping = false }
            let n = await indexPending(context: context)
            if n > 0 { NSLog("[Casberi] EmbeddingIndex: embedded %d things", n) }
        }
    }

    /// Embed things with no vector yet — newest first, so what a person just
    /// captured becomes semantically searchable soonest. Loops until the
    /// store drains. Returns the count embedded. Awaited directly by the
    /// headless probe.
    @MainActor
    @discardableResult
    static func indexPending(context: ModelContext) async -> Int {
        guard isAvailable else { return 0 }
        let batchSize = 32
        var total = 0
        while true {
            var descriptor = FetchDescriptor<Thing>(
                predicate: #Predicate { $0.embedding == nil },
                sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
            descriptor.fetchLimit = batchSize
            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }
            // `NLEmbedding.vector` is a real inference call (a few ms each) —
            // 32 of them used to run inline on the main actor, mid-batch
            // yields notwithstanding (2026-07-21 audit). The model itself
            // needs no SwiftData/main-actor access, only reading the source
            // Things and writing the vectors back does — so only the text
            // extraction and the final assignment+save touch the main actor;
            // the actual inference runs off it, and the main actor merely
            // awaits (suspends, doesn't block) while it happens.
            let texts = batch.map(indexText(for:))
            let packed = await packedVectors(for: texts)
            for (thing, data) in zip(batch, packed) {
                thing.embedding = data
            }
            context.saveHonestly()
            total += batch.count
            await Task.yield()
        }
        return total
    }

    /// Off-main-actor inference for a batch of texts — see `indexPending`.
    /// Stamps an empty vector for unembeddable text so the sweep doesn't
    /// re-select the thing forever.
    private static func packedVectors(for texts: [String]) async -> [Data] {
        await Task.detached(priority: .utility) {
            texts.map { vector(for: $0).map(pack) ?? Data() }
        }.value
    }
}
