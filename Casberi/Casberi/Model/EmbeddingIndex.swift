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
///
/// **Multilingual (2026-08-02, prd §282).** The index was pinned to
/// `.english` from the day it shipped, so a corpus in any other language got
/// NOTHING from it — every Bluesky/Farcaster/note/screenshot in Spanish,
/// German or Japanese scored 0 on the semantic pass and fell back to keyword
/// overlap, silently. Now each thing is embedded with the sentence model for
/// ITS OWN detected language, and a vector carries the language it was made
/// with (see `Header`), so a Spanish ask reaches Spanish things and can never
/// be cosine'd against an English vector — different models put different
/// meanings at the same coordinates, and comparing across them isn't a weaker
/// match, it's a wrong one.
///
/// **Why not `NLContextualEmbedding`** — the genuinely cross-lingual option,
/// and the obvious reach. Its per-token vectors mean-pool into a sentence
/// vector whose similarity DISTRIBUTION is nothing like `NLEmbedding`'s: the
/// shared component across unrelated sentences is large, so ordinary pairs sit
/// far higher than the floors every caller here was tuned against (`Retriever`'s
/// 0.55 boost / 0.62 qualify, the Related shelf's 0.5). Swapping the model
/// without re-measuring those three numbers would not degrade retrieval
/// visibly — it would make almost everything "related", which reads as the app
/// getting worse at answering while every log line says it's working. Language
/// keying buys the same fix for the corpus people actually have (one or two
/// languages, not fifty) at zero risk to the measured floors. Revisit with a
/// measured distribution, not from intuition.
enum EmbeddingIndex {

    // MARK: - Models, per language

    /// ONE serial queue over every `NLEmbedding` COMPUTE call in this app —
    /// `vector(for:)`, `neighbors(for:)`, `distance`. The model CACHE keeps its
    /// own `modelLock` below; the two are never held together (`model(for:)`
    /// returns, releasing it, before the queue is entered), so there is no
    /// lock order to get wrong.
    ///
    /// **`NLEmbedding` is not thread-safe, and nothing in its documentation
    /// says so — you find out from a crash report.** Build 280 died on open
    /// (2026-08-07, `EXC_BAD_ACCESS` at 0x2000) with two threads inside
    /// `-[NLEmbedding vectorForString:]` at the same instant: the main actor
    /// embedding an ask through `Retriever.rank` → `queryVector`, and the
    /// backfill's detached utility task embedding a batch through
    /// `packedVectors`. Both bottomed out in
    /// `CoreNLP::SentenceEmbedding::fillStringVector` → `BNNSFilterApplyBatch`
    /// reading a torn pointer. Nothing was corrupt on disk and no vector was
    /// wrong; the two calls simply shared the model's scratch state.
    ///
    /// **It is not a rare interleaving — it is what a foreground pass does.**
    /// `RootShell.runForegroundWork` fires `backfill` and the kept-ask digest
    /// recompute (which re-runs `Retriever.rank` for every kept `search:` ask)
    /// a few lines apart, so on any pass where the sweep has something to
    /// embed, both halves are running at once by construction.
    ///
    /// And the window is NOT the launch. Build 281 — the same crash, on a
    /// different binary, with the two threads' roles swapped — died **131
    /// seconds** after launch, which corrects the first read of this bug
    /// ("crashes on open"). Two things widen it: `runForegroundWork` runs on
    /// EVERY activation, not just the first, and `indexPending` loops until
    /// the store drains, so on a large or freshly-synced corpus the detached
    /// sweep is embedding for minutes. Any ask landing anywhere in that
    /// stretch races it.
    ///
    /// ONE gate for EVERY model, not one per instance: both crashing stacks
    /// bottomed out in `CoreNLP::ContextualWordEmbedding::fillWordVectors`,
    /// which the sentence AND word embeddings share — so per-object (or
    /// per-language) locking would leave the cross-object case wide open,
    /// `SemanticExpand.neighbors` against a sentence `vector`, which is
    /// exactly §282's multilingual shape. It would look safe and not be.
    ///
    /// **A SERIAL QUEUE, NOT AN `NSLock` — a mutex trades the crash for a
    /// FREEZE, and this is measured, not reasoned.** A mutex is not fair: the
    /// backfill, looping a 32-text batch, releases and instantly re-acquires,
    /// barging past a main thread already waiting. On one workload —
    /// uncontended 1.6ms median / 3.3ms max; `NSLock` 13–43ms median, **p95
    /// 280–347ms, max 2573ms**; serial FIFO queue 5.5ms median, p95
    /// 6.5–12ms, **max 15ms**. A 2.5-second main-thread stall is a worse bug
    /// than the crash, and it would land on the very foreground path this app
    /// already fights for smoothness. The first cut of this fix used an
    /// `NSRecursiveLock` and claimed a main-thread ask "waits a few ms and
    /// interleaves" — that claim was wrong, and only the measurement showed
    /// it.
    ///
    /// **The race is PROVEN, not inferred**: four threads hammering one shared
    /// model died 3/3 unlocked (SIGSEGV/SIGTRAP) and survived 12,000
    /// inferences 3/3 serialized. `-embedRaceProbe` is that experiment.
    private static let inferenceQueue = DispatchQueue(label: "com.casberi.embedding.inference")

    /// Exclusive access to NaturalLanguage INFERENCE — see `inferenceQueue`.
    /// Every `NLEmbedding` compute call in the app goes through here,
    /// including `SemanticExpand`'s word-embedding neighbours, which lives in
    /// another file and shares no model object with this one.
    static func serialized<T>(_ body: () -> T) -> T {
        inferenceQueue.sync(execute: body)
    }

    /// Every language Apple ships a sentence embedding for is discovered by
    /// ASKING, not by carrying a list: `sentenceEmbedding(for:)` returns nil
    /// where there's no model, and the set differs by OS version. Cached
    /// because loading one is not free and retrieval asks per query.
    ///
    /// This guards the CACHE only — a dictionary lookup, microseconds, with no
    /// barging concern — and is released before any caller enters
    /// `inferenceQueue`.
    private static let modelLock = NSLock()
    nonisolated(unsafe) private static var models: [NLLanguage: NLEmbedding?] = [:]

    private static func model(for language: NLLanguage) -> NLEmbedding? {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cached = models[language] { return cached }
        let loaded = NLEmbedding.sentenceEmbedding(for: language)
        models[language] = loaded
        return loaded
    }

    /// English stays the default and the fallback — it's the only language the
    /// index has ever had, so every vector written before this existed is
    /// English by definition (see `Header.language(of:)`).
    static let fallbackLanguage: NLLanguage = .english

    static var isAvailable: Bool { model(for: fallbackLanguage) != nil }

    /// The language a piece of text is written in, when we're confident enough
    /// to key a vector on it. Confidence matters: `NLLanguageRecognizer` will
    /// name a language for three words of anything, and a mis-keyed vector is
    /// invisible — it just never matches. Below the floor the caller falls back
    /// (to the corpus's own dominant language for a query, to English for a
    /// thing), which is the pre-existing behaviour.
    static func language(of text: String, minimumConfidence: Double = 0.55) -> NLLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
              top.value >= minimumConfidence,
              model(for: top.key) != nil        // no model → not a language we can key on
        else { return nil }
        return top.key
    }

    /// What most of this person's embedded things are written in — read by the
    /// query side when an ask is too short to detect (which is most asks:
    /// "travel plans" is three words). Without it a Spanish corpus would be
    /// searched in English forever, since a two-word Spanish query never clears
    /// the confidence floor. Written by the sweep, so it costs the query path
    /// nothing.
    private static let dominantKey = "embedding.dominantLanguage"

    static var dominantLanguage: NLLanguage? {
        guard let raw = UserDefaults.standard.string(forKey: dominantKey) else { return nil }
        let language = NLLanguage(rawValue: raw)
        return model(for: language) != nil ? language : nil
    }

    /// The language a QUERY should be embedded in: what it plainly is, else
    /// what the corpus mostly is, else English.
    static func queryLanguage(for text: String) -> NLLanguage {
        language(of: text) ?? dominantLanguage ?? fallbackLanguage
    }

    // MARK: - Header

    /// A stored vector's 12-byte preamble: a magic word, then the language tag
    /// the vector was made with. It exists because two sentence models can
    /// produce the SAME dimension while meaning different things by it — a
    /// length check (which is all the old `similarity` had) would call those
    /// comparable and score pure noise as a match.
    ///
    /// Vectors written before this existed carry no header at all, and are
    /// English by definition — that's what the magic distinguishes, and it's
    /// why this change re-embeds nothing on upgrade: an English corpus keeps
    /// every vector it has.
    enum Header {
        /// Little-endian, deliberately not a plausible Float32 bit pattern for
        /// a first coordinate.
        static let magic: UInt32 = 0xCA5B_E001
        /// 4 magic + 8 language tag. Eight bytes because four would fold
        /// `zh-Hans` and `zh-Hant` onto the same tag — two different models.
        static let size = 12
        private static let tagSize = 8

        /// The language of a packed blob: its tag when it carries one, English
        /// when it's a pre-header vector. nil only for a blob too short to be
        /// either (a corrupt or empty record).
        static func language(of packed: Data) -> NLLanguage? {
            guard packed.count >= MemoryLayout<UInt32>.size else { return nil }
            let stamped = packed.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            }
            guard stamped == magic else { return .english }   // legacy vector
            guard packed.count >= size else { return nil }
            let raw = packed[(packed.startIndex + 4)..<(packed.startIndex + size)]
            let text = String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            return text.isEmpty ? nil : NLLanguage(rawValue: text)
        }

        /// Where the floats start — 0 for a legacy vector, `size` for a
        /// tagged one.
        static func offset(in packed: Data) -> Int {
            guard packed.count >= MemoryLayout<UInt32>.size else { return 0 }
            let stamped = packed.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            }
            return stamped == magic ? size : 0
        }

        static func bytes(for language: NLLanguage) -> Data {
            var out = withUnsafeBytes(of: magic.littleEndian) { Data($0) }
            var tag = Data(language.rawValue.utf8.prefix(tagSize))
            tag.append(contentsOf: [UInt8](repeating: 0, count: tagSize - tag.count))
            out.append(tag)
            return out
        }
    }

    // MARK: - Text

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
        // The source's own abstract (2026-07-22) — a feed item's summary, a
        // task's description. Ahead of `enrichedText` on purpose: it's the
        // publisher's words rather than our scrape, so it's the better
        // signal when a thing carries both.
        if let abstract = thing.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !abstract.isEmpty {
            parts.append(abstract)
        }
        if let extra = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extra.isEmpty {
            parts.append(extra)
        }
        return String(parts.joined(separator: ". ").prefix(800))
    }

    // MARK: - Vectors

    /// An embedding vector for arbitrary text, as Float, in a NAMED language.
    /// nil when that language has no model or the text is empty/unembeddable.
    ///
    /// The inference runs under `serialized` — the model is shared across
    /// every caller and every thread, and running two of these at once is what
    /// crashed builds 280 and 281 (see `inferenceQueue`). `model(for:)` is
    /// resolved FIRST and outside the queue, so the cache lock and the
    /// inference queue are never held together.
    static func vector(for text: String, language: NLLanguage) -> [Float]? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty, let model = model(for: language) else { return nil }
        guard let raw = serialized({ model.vector(for: trimmed) }) else { return nil }
        return raw.map(Float.init)
    }

    /// A query vector plus the language it was made in — the pair every caller
    /// needs, since a vector may only be compared against things embedded the
    /// same way. nil when nothing could be embedded.
    static func queryVector(for text: String) -> (vector: [Float], language: NLLanguage)? {
        let language = queryLanguage(for: text)
        if let v = vector(for: text, language: language) { return (v, language) }
        // The detected/dominant language had no usable answer — English is the
        // fallback the index has always had.
        guard language != fallbackLanguage,
              let v = vector(for: text, language: fallbackLanguage) else { return nil }
        return (v, fallbackLanguage)
    }

    // MARK: - Packing

    static func pack(_ vector: [Float], language: NLLanguage) -> Data {
        var out = Header.bytes(for: language)
        out.append(vector.withUnsafeBufferPointer { Data(buffer: $0) })
        return out
    }

    /// A stored blob as plain Doubles, header stripped.
    ///
    /// Every other reader here SCORES a packed vector in place (`similarity`
    /// walks the bytes without ever materialising them) because scoring is all
    /// retrieval needs. The panel's semantic map (§337) is the one caller that
    /// has to PROJECT them, so it needs the numbers themselves — which is why
    /// this exists and why it is the only unpacking path: a second hand-rolled
    /// one would be a second place to get the header offset wrong, and a wrong
    /// offset reads a language tag as two coordinates and plots a dot that
    /// means nothing.
    ///
    /// nil for a blob that isn't a whole number of floats — a truncated record
    /// still projects to a perfectly plausible-looking point.
    static func unpack(_ packed: Data) -> [Double]? {
        let start = Header.offset(in: packed)
        let width = MemoryLayout<Float>.size
        let bytes = packed.count - start
        guard bytes > 0, bytes % width == 0 else { return nil }
        let count = bytes / width
        return packed.withUnsafeBytes { raw in
            (0..<count).map {
                Double(raw.loadUnaligned(fromByteOffset: start + $0 * width, as: Float.self))
            }
        }
    }

    /// Euclidean norm of a vector — computed once per query so `similarity`
    /// doesn't recompute the query's magnitude for every thing it scores.
    static func norm(_ v: [Float]) -> Float {
        var sum: Float = 0
        for x in v { sum += x * x }
        return sum.squareRoot()
    }

    // MARK: - Similarity

    /// Cosine of a query vector against a thing's PACKED stored vector, read in
    /// place — no intermediate `[Float]` allocation, since retrieval scores this
    /// against every thing on the (main-thread) Ask path. `queryNorm` is the
    /// query's precomputed magnitude.
    ///
    /// Returns 0 — never a match, never a crash — for a zero/degenerate vector,
    /// a length mismatch (a cross-revision `NLEmbedding` blob of a different
    /// dimension), or a vector embedded in a DIFFERENT LANGUAGE than the query.
    /// That last one is the 2026-08-02 addition and the reason the header
    /// exists: two sentence models can share a dimension while disagreeing
    /// about what those coordinates mean, so a length check alone would have
    /// scored noise as similarity. `loadUnaligned` tolerates `Data` that isn't
    /// 4-byte aligned.
    static func similarity(query: [Float], queryNorm: Float, packed: Data,
                           language: NLLanguage) -> Double {
        guard Header.language(of: packed) == language else { return 0 }
        let offset = Header.offset(in: packed)
        let stride = MemoryLayout<Float>.stride
        let count = (packed.count - offset) / stride
        guard count == query.count, count > 0, queryNorm > 0 else { return 0 }
        return packed.withUnsafeBytes { raw -> Double in
            var dot: Float = 0, nb: Float = 0
            for i in 0..<count {
                let y = raw.loadUnaligned(fromByteOffset: offset + i * stride, as: Float.self)
                dot += query[i] * y
                nb += y * y
            }
            guard nb > 0 else { return 0 }
            return Double(dot / (queryNorm * nb.squareRoot()))
        }
    }

    // MARK: - Backfill

    private static var isSweeping = false

    /// How many 32-row batches ONE foreground sweep may commit (PERF
    /// 2026-09-01, perf spec P5.3). 8 × 32 = 256 things per activation.
    ///
    /// **Every batch ends in a `saveHonestly()`, and every save re-emits every
    /// live `@Query`** — which means it rebuilds the feed the person is
    /// looking at. Unbounded, that is not one rebuild, it is a TRAIN of them:
    /// a batch is 32 real inference calls at a few ms each, so the saves land
    /// roughly ten a second for as long as the sweep runs. On the 13,412-row
    /// corpus `AgentOpenCache` measured against, draining is 419 batches —
    /// about fifty seconds of continuous rebuilding — and build 281's report
    /// puts the sweep at MINUTES on a freshly-synced corpus, which is the same
    /// window that report describes an ask racing into.
    ///
    /// **The bound is structural, not a tuned number.** It is sized to one
    /// activation: 8 batches is on the order of a second of sweeping, which
    /// fits inside the burst `RootShell.runForegroundWork` already pays on
    /// every activation (the bridge sweeps, the kept-ask digest recompute,
    /// `SyncReconcile`, the Spotlight reindex). So the sweep adds no NEW period
    /// of jank rather than merely a shorter one.
    ///
    /// **What it costs is latency-to-fully-indexed, never correctness**, and
    /// that is the whole trade. The sweep re-arms on EVERY activation, so a
    /// bounded pass is resumed rather than abandoned; each pass makes strict
    /// progress (a stamped vector — an empty one for unembeddable text — is
    /// never re-selected). Two things make the latency cheap: the fetch is
    /// NEWEST FIRST, so what a person just captured is embedded in the first
    /// batch of the first pass, and a thing the sweep hasn't reached is still
    /// retrievable by keyword — the degradation this file already documents.
    /// A large first-run backfill therefore completes over tens of activations
    /// instead of one long one.
    ///
    /// In STEADY STATE the bound never binds: an ordinary foreground's
    /// arrivals are well under 256, so the sweep drains completely and behaves
    /// exactly as it did. It bites only on the first-run and big-sync
    /// backfills — which is the case it exists for. UNMEASURED, like every
    /// number in the perf spec: no reading here has been taken on hardware.
    private static let foregroundBatchBudget = 8

    /// Fire-and-forget: embed everything not yet indexed, off the critical path.
    /// Single-flighted and idempotent — safe to call every foreground. The
    /// answer path stays keyword-only for anything the sweep hasn't reached yet.
    ///
    /// **The batch bound lives HERE and not on `indexPending`** — this is the
    /// path that runs on every activation while somebody is watching the feed,
    /// so it is the path that owns the "how much per pass" policy. The two
    /// headless probes (`-answerProbe`, `-byokProbe`) call `indexPending`
    /// directly and must keep draining, or a semantic ask over a large corpus
    /// stops being deterministic — which is the whole reason they index first.
    @MainActor
    static func backfill(context: ModelContext) {
        guard isAvailable, !isSweeping else { return }
        isSweeping = true
        Task { @MainActor in
            defer { isSweeping = false }
            let n = await indexPending(context: context, maxBatches: foregroundBatchBudget)
            if n > 0 { NSLog("[Casberi] EmbeddingIndex: embedded %d things", n) }
            // Only once the new work is done: retire vectors written in the
            // wrong language (see `remedyMistagged`). Bounded and cursored, so
            // this is a few hundred cheap language checks per foreground, not
            // a corpus walk.
            let fixed = await remedyMistagged(context: context)
            if fixed > 0 { NSLog("[Casberi] EmbeddingIndex: re-queued %d mis-keyed vectors", fixed) }
        }
    }

    /// Embed things with no vector yet — newest first, so what a person just
    /// captured becomes semantically searchable soonest. Returns the count
    /// embedded. Awaited directly by the headless probes.
    ///
    /// `maxBatches` caps how many 32-row batches — and therefore how many
    /// saves, and therefore how many feed rebuilds — one call may commit; see
    /// `foregroundBatchBudget`, which is what the live sweep passes. **nil
    /// means drain**, which is the default because that is what the probes
    /// need and what this has always done: the bound is the foreground sweep's
    /// policy, not this function's. A bounded call leaves the rest pending and
    /// the next call resumes it — the fetch selects on `embedding == nil`, so
    /// there is no cursor to keep and no work to lose.
    @MainActor
    @discardableResult
    static func indexPending(context: ModelContext, maxBatches: Int? = nil) async -> Int {
        guard isAvailable else { return 0 }
        let batchSize = 32
        var total = 0
        var batches = 0
        var landed: [NLLanguage: Int] = [:]
        while true {
            // Checked before the FETCH, not after the save: reaching the bound
            // and then reading 32 more rows just to discard them would pay the
            // pass's most expensive main-actor step for nothing.
            if let cap = maxBatches, batches >= cap { break }
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
            for (thing, result) in zip(batch, packed) {
                thing.embedding = result.data
                if let language = result.language {
                    landed[language, default: 0] += 1
                }
            }
            context.saveHonestly()
            total += batch.count
            batches += 1
            await Task.yield()
        }
        if !landed.isEmpty { recordDominant(landed) }
        return total
    }

    /// Off-main-actor inference for a batch of texts — see `indexPending`.
    /// Each text is embedded in its OWN detected language (English when it's
    /// too short or too ambiguous to tell, which is what every vector written
    /// before 2026-08-02 assumed). Stamps an empty vector for unembeddable text
    /// so the sweep doesn't re-select the thing forever.
    private static func packedVectors(for texts: [String]) async -> [(data: Data, language: NLLanguage?)] {
        await Task.detached(priority: .utility) {
            texts.map { text in
                let language = self.language(of: text) ?? fallbackLanguage
                guard let v = vector(for: text, language: language) else {
                    // A language we detected but couldn't embed falls back to
                    // English rather than leaving the thing unindexed.
                    guard language != fallbackLanguage,
                          let english = vector(for: text, language: fallbackLanguage)
                    else { return (Data(), nil) }
                    return (pack(english, language: fallbackLanguage), fallbackLanguage)
                }
                return (pack(v, language: language), language)
            }
        }.value
    }

    /// Keep a running tally of which languages this corpus embeds in, and
    /// publish the leader — `queryLanguage` reads it so a short ask in a
    /// Spanish corpus is searched in Spanish. Counts persist so a single quiet
    /// foreground can't flip the answer.
    private static func recordDominant(_ landed: [NLLanguage: Int]) {
        let key = "embedding.languageCounts"
        var counts = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        for (language, n) in landed { counts[language.rawValue, default: 0] += n }
        UserDefaults.standard.set(counts, forKey: key)
        if let top = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) {
            UserDefaults.standard.set(top.key, forKey: dominantKey)
        }
    }

    // MARK: - Remedy

    /// The corpus that existed BEFORE language keying is the whole reason this
    /// pass exists: every one of its vectors was made with the English model,
    /// including the Spanish notes and the Japanese posts, and those vectors
    /// are not weak matches — they're meaningless coordinates that a Spanish
    /// query would now (correctly) refuse to compare against, leaving those
    /// things permanently unreachable by meaning.
    ///
    /// So: walk the corpus ONCE, bounded per foreground, and nil the embedding
    /// of anything whose text plainly isn't the language its vector claims.
    /// `indexPending` re-embeds it properly on the next sweep. The cursor is
    /// persisted and the walk stops for good when it reaches the end — the
    /// language check is cheap, but it is not free, and this is a one-time
    /// repair, not a standing cost.
    private static let remedyCursorKey = "embedding.remedyCursor"
    private static let remedyDoneKey = "embedding.remedyDone.v1"

    @MainActor
    @discardableResult
    static func remedyMistagged(context: ModelContext, window: Int = 200) async -> Int {
        guard isAvailable, !UserDefaults.standard.bool(forKey: remedyDoneKey) else { return 0 }
        let offset = UserDefaults.standard.integer(forKey: remedyCursorKey)
        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = window
        let batch = (try? context.fetch(descriptor)) ?? []
        guard !batch.isEmpty else {
            UserDefaults.standard.set(true, forKey: remedyDoneKey)
            return 0
        }
        var cleared = 0
        for thing in batch where thing.isLive {
            guard let packed = thing.embedding, !packed.isEmpty,
                  let stamped = Header.language(of: packed) else { continue }
            // Only a CONFIDENT disagreement clears a vector — an undetectable
            // text (short, mixed, numeric) leaves the vector exactly as it is.
            guard let actual = language(of: indexText(for: thing)),
                  actual != stamped else { continue }
            thing.embedding = nil
            cleared += 1
        }
        if cleared > 0 { context.saveHonestly() }
        UserDefaults.standard.set(offset + batch.count, forKey: remedyCursorKey)
        if batch.count < window { UserDefaults.standard.set(true, forKey: remedyDoneKey) }
        return cleared
    }
}
