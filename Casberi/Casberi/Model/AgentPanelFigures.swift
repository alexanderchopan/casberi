import Foundation

/// The three CROSS-SOURCE figures (prd §337) — the ones no room can draw.
///
/// Every registry figure in `FeedInsight` is pure over ONE room's things by
/// contract, which is exactly why the All feed has never had a hero: a chart
/// of everything at once, composed that way, is a chart of nothing. These three
/// are composed the other way round — they take the WHOLE corpus and find the
/// axis all rooms genuinely share:
///
///   • `dial`    — the clock. Every thing has an hour; nothing in the app has
///                 ever asked which one.
///   • `river`   — the weeks. The topic maps already extract themes; this is
///                 the same extraction shown as movement instead of state.
///   • `scatter` — meaning. §282's embeddings serve retrieval invisibly; this
///                 is the one surface that draws them.
///
/// Foundation-only over flat inputs, like `AgentPanel` itself, so
/// `scripts/agent-panel-selftest.sh` compiles them whole with no stubs.
enum AgentPanelFigures {

    // MARK: - Input

    /// One thing, flattened to what these three read.
    struct Entry: Equatable {
        var source: String
        var at: Date
        /// The terms already stamped on the thing (`ocrTopics` + tags).
        var terms: [String] = []
        /// The stored embedding, or nil. Only `scatter` reads it.
        var vector: [Double]? = nil
    }

    // MARK: - 1 · The day dial

    /// A week of things placed on a 24-hour clock.
    ///
    /// Hour is taken in the CURRENT calendar, not UTC: the question is "when
    /// is your day", and a day is a local thing. Recency is normalised across
    /// the window rather than against a fixed span, so a quiet week still uses
    /// the whole radius instead of huddling at the rim.
    static func dial(_ entries: [Entry], now: Date = .now,
                     days: Int = 7, cap: Int = 400) -> [AgentPanel.DialMark] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -days, to: now) else { return [] }
        let window = entries.filter { $0.at >= start && $0.at <= now }
        guard !window.isEmpty else { return [] }
        let span = max(1, now.timeIntervalSince(start))
        // Newest first, then capped — a busy corpus draws its most recent
        // `cap` marks rather than a random sample, so the rim is always true.
        return window
            .sorted { $0.at > $1.at }
            .prefix(cap)
            .map { entry in
                let comps = cal.dateComponents([.hour, .minute], from: entry.at)
                let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
                let recency = 1 - (now.timeIntervalSince(entry.at) / span)
                return AgentPanel.DialMark(hour: hour,
                                           recency: min(1, max(0, recency)),
                                           source: entry.source)
            }
    }

    // MARK: - 2 · The theme river

    /// Themes as weekly bands, oldest week first.
    ///
    /// Bands are ordered by TOTAL volume descending and then by name, never by
    /// when they peaked — a river whose bands re-stack between opens shimmers,
    /// and the ordering has to be total for the same reason `AgentPanel.rank`
    /// does (§332's per-process Dictionary hashing, one file over).
    ///
    /// A theme must appear in at least `minWeeks` distinct weeks to be a
    /// current: a single burst is an event, and drawing it as a band claims a
    /// trend that isn't there.
    static func river(_ entries: [Entry], now: Date = .now,
                      weeks: Int = 10, maxBands: Int = 5,
                      minWeeks: Int = 2) -> [AgentPanel.RiverBand] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -7 * weeks, to: now) else { return [] }
        // term -> per-week counts
        var buckets: [String: [Int]] = [:]
        for entry in entries where entry.at >= start && entry.at <= now {
            let elapsed = now.timeIntervalSince(entry.at)
            let index = weeks - 1 - Int(elapsed / (7 * 86_400))
            guard index >= 0, index < weeks else { continue }
            // One credit per THING per term, so a term repeated inside one
            // title can't outweigh the same term carried by several things
            // (the `dominantTopic` lesson).
            for term in Set(entry.terms.map { $0.lowercased() })
            where term.count >= 3 && !nonSubject.contains(term) {
                buckets[term, default: Array(repeating: 0, count: weeks)][index] += 1
            }
        }
        var bands: [AgentPanel.RiverBand] = []
        for (term, counts) in buckets {
            let live = counts.reduce(0) { $1 > 0 ? $0 + 1 : $0 }
            guard live >= minWeeks else { continue }
            // A theme confined to the newest weeks is a BURST, not drift, and
            // a river drawn from one is a flat line that flares at the right
            // edge — technically true, and it claims a trend that isn't there
            // (seen on the sim). It has to reach back past the halfway mark
            // to count as movement.
            let reachesBack = counts.prefix(counts.count / 2).contains { $0 > 0 }
            guard reachesBack else { continue }
            bands.append(AgentPanel.RiverBand(label: term, weeks: counts))
        }
        bands.sort { a, b in
            a.total == b.total ? a.label < b.label : a.total > b.total
        }
        return Array(bands.prefix(maxBands))
    }

    /// Words that name a SHAPE or a KIND, never a subject.
    ///
    /// `Thing.tags` carries the importers' facet tags (Post / Reply / Liked /
    /// Shorts / …) beside real topics, and `ocrTopics` carries the kind words
    /// the rooms file things under. Drawn as river bands they read as themes,
    /// and the first real run produced exactly that: "link", "shorts",
    /// "screenshot" flowing as if they were what the person cared about.
    /// §313's ruling in a new figure — a container is not a subject.
    static let nonSubject: Set<String> = [
        "post", "posts", "reply", "replies", "liked", "saved", "save",
        "comment", "comments", "conversation", "memory", "thread", "threads",
        "shorts", "video", "videos", "review", "reviews", "release", "build",
        "gone", "link", "links", "note", "notes", "screenshot", "screenshots",
        "photo", "photos", "image", "images", "event", "chat", "chats",
        "mail", "voice", "product", "transaction", "reminder", "file", "files",
        "message", "messages", "untitled", "document", "documents",
    ]

    // MARK: - 3 · The semantic map

    /// The corpus projected into the unit square by embedding similarity.
    ///
    /// **A DETERMINISTIC projection, and that constraint picked the method.**
    /// t-SNE and UMAP give prettier separation and are both randomised — they
    /// would rearrange the map between two opens over identical data, which is
    /// the exact failure `AgentPanel.rank`'s total ordering exists to prevent,
    /// and far more glaring here since the whole picture moves. So: PCA onto
    /// its own first two components, computed by power iteration with a FIXED
    /// seed vector and a fixed iteration count. Same corpus in, same picture
    /// out, on every device.
    ///
    /// Cheap enough to run on open at this size (two components over a few
    /// hundred capped vectors is a handful of passes), and the caller caches
    /// the result beside the vectors anyway.
    static func scatter(_ entries: [Entry], cap: Int = 300)
        -> (dots: [AgentPanel.Dot], clusters: [AgentPanel.DotCluster]) {
        let usable = entries.compactMap { e -> (Entry, [Double])? in
            guard let v = e.vector, !v.isEmpty else { return nil }
            return (e, v)
        }
        guard usable.count >= 12 else { return ([], []) }
        // Newest first so a capped corpus maps what's current.
        let sample = usable.sorted { $0.0.at > $1.0.at }.prefix(cap).map { $0 }
        let dim = sample.map(\.1.count).min() ?? 0
        guard dim >= 2 else { return ([], []) }
        let vectors = sample.map { Array($0.1.prefix(dim)) }

        // Centre.
        var mean = Array(repeating: 0.0, count: dim)
        for v in vectors { for i in 0..<dim { mean[i] += v[i] } }
        for i in 0..<dim { mean[i] /= Double(vectors.count) }
        let centred = vectors.map { v in (0..<dim).map { v[$0] - mean[$0] } }

        let a1 = principalAxis(centred, dim: dim)
        // Deflate, then take the second axis out of what's left.
        let deflated = centred.map { v -> [Double] in
            let p = dot(v, a1)
            return (0..<dim).map { v[$0] - p * a1[$0] }
        }
        let a2 = principalAxis(deflated, dim: dim)

        var xs = [Double](), ys = [Double]()
        for v in centred { xs.append(dot(v, a1)); ys.append(dot(v, a2)) }
        let nx = unit(xs), ny = unit(ys)

        var dots: [AgentPanel.Dot] = []
        for (i, entry) in sample.enumerated() {
            dots.append(AgentPanel.Dot(x: nx[i], y: ny[i], source: entry.0.source))
        }

        // Clusters are NAMED BY THE TERMS THAT ARE ACTUALLY THERE — a cell
        // label in a treemap is a word from the data, and this is the same
        // rule: the map asserts nothing about why things sit together, it just
        // says which word the neighbourhood shares. A cluster with no shared
        // term goes unlabelled rather than getting an invented one.
        var byTerm: [String: [Int]] = [:]
        for (i, entry) in sample.enumerated() {
            for term in Set(entry.0.terms.map { $0.lowercased() })
            where term.count >= 3 && !nonSubject.contains(term) {
                byTerm[term, default: []].append(i)
            }
        }
        var clusters: [AgentPanel.DotCluster] = []
        for (term, idx) in byTerm {
            guard idx.count >= 3 else { continue }
            var sx = 0.0, sy = 0.0
            for i in idx { sx += nx[i]; sy += ny[i] }
            let cx = sx / Double(idx.count)
            let cy = sy / Double(idx.count)
            var spread = 0.0
            for i in idx {
                let dx = nx[i] - cx, dy = ny[i] - cy
                spread = max(spread, (dx * dx + dy * dy).squareRoot())
            }
            clusters.append(AgentPanel.DotCluster(label: term, x: cx, y: cy, radius: spread))
        }
        // Tightest first — a tight cluster is a real neighbourhood, a wide one
        // is a common word smeared across the map.
        clusters.sort { a, b in
            a.radius == b.radius ? a.label < b.label : a.radius < b.radius
        }
        return (dots, Array(clusters.prefix(4)))
    }

    // MARK: - Shared arithmetic

    /// Power iteration with a FIXED start — no randomness anywhere, so the
    /// same corpus projects identically on every device and every open.
    private static func principalAxis(_ rows: [[Double]], dim: Int,
                                      iterations: Int = 24) -> [Double] {
        // A fixed, non-degenerate seed. All-ones would be orthogonal to any
        // axis whose components sum to zero — which mean-centred data can
        // easily produce — so the seed alternates sign instead.
        var axis = (0..<dim).map { $0 % 2 == 0 ? 1.0 : -1.0 }
        axis = normalize(axis)
        for _ in 0..<iterations {
            var next = Array(repeating: 0.0, count: dim)
            for row in rows {
                let p = dot(row, axis)
                for i in 0..<dim { next[i] += p * row[i] }
            }
            let n = normalize(next)
            guard n.contains(where: { $0 != 0 }) else { break }
            axis = n
        }
        return axis
    }

    private static func dot(_ a: [Double], _ b: [Double]) -> Double {
        var out = 0.0
        for i in 0..<min(a.count, b.count) { out += a[i] * b[i] }
        return out
    }

    private static func normalize(_ v: [Double]) -> [Double] {
        let mag = dot(v, v).squareRoot()
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }

    /// Map a series into 0…1. A degenerate axis (every value identical)
    /// returns 0.5 for all — the flat-curve rule: drawing it against the edge
    /// would claim a spread that isn't there.
    static func unit(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max() else { return [] }
        guard hi > lo else { return values.map { _ in 0.5 } }
        return values.map { ($0 - lo) / (hi - lo) }
    }
}
