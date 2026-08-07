import Foundation

/// The agent's instrument panel (prd §334, 2026-08-07) — every connected
/// room's own hero visualization, gathered onto one surface.
///
/// The idea, in the user's words: "what if the agent shows a lead like it does,
/// but then the rest is all / only visualizations from source feeds… show
/// something they don't see on All and give the most info at a glance."
///
/// It answers a real structural gap rather than adding decoration. Every source
/// room computes a hero — a treemap of what your screenshots say, a leaderboard
/// of who writes you, a mood split, a year of capture — and **all of it is
/// invisible unless you tap into that room one at a time.** The All feed can't
/// show them: `FeedInsight`'s registries are pure over ONE room's things by
/// contract, and a chart of everything at once would be a chart of nothing. So
/// the readings existed, were already computed, and had nowhere to be seen
/// together. This is that place.
///
/// **Only figures, by ruling.** A card here earns its slot by DRAWING
/// something. A room whose hero is a sentence or a row of text has one
/// perfectly good home already (the room), and text tiles are what made the
/// previous open read as a list; the panel is the half a list can't do.
///
/// **Costs nothing new.** Every figure below is composed from things already in
/// memory (the same corpus walk the composer pays for) or from bridge state
/// already in UserDefaults. No request, no model, no new `Thing` field, no
/// CloudKit deploy — the panel is a second reading of data the app has already
/// paid for, which is exactly why it can render synchronously on open.
///
/// **Foundation-only by design**: it holds no `Thing` and no
/// SwiftUI, so `scripts/agent-panel-selftest.sh` compiles it WHOLE with no
/// stubs, and the liveness-corollary family cannot reach it.
enum AgentPanel {

    // MARK: - Figures

    /// One weighted cell of a treemap — the shape `UnitTreemap` already draws
    /// for receipts and x402, reused here at tile scale.
    struct Cell: Equatable {
        var label: String
        var weight: Int
    }

    /// One ranked bar. `detail` is the room's own right-aligned display
    /// ("23", "3.4h") — never recomputed here, so the panel and the room can
    /// never disagree about a number.
    struct Bar: Equatable {
        var label: String
        var value: Int
        var detail: String
    }

    /// One slice of a proportion rail. `share` is 0…1 of the whole.
    struct Segment: Equatable {
        var label: String
        var share: Double
        /// The room's own tone index — 0 neutral, 1 positive, 2 negative — kept
        /// as an Int so this file stays free of SwiftUI's Color.
        var tone: Int
    }

    /// What a card draws.
    ///
    /// Every case is a SHAPE, never a sentence. Adding a `.text` case is the
    /// tripwire for this whole feature: the moment a card can be words, the
    /// panel becomes the list it replaced.
    enum Figure: Equatable {
        /// Proportional blocks — "what this room is mostly about".
        case treemap([Cell])
        /// Ranked bars — "who or what leads here".
        case bars([Bar])
        /// A proportion rail — "how this room splits".
        case rail([Segment])
        /// Per-day counts, oldest first — "the rhythm of this room".
        case pulse([Int])
        /// A value curve — "where this is heading".
        case curve([Double])
        /// A thumbnail wall — for rooms whose content IS pictures.
        case wall([String])

        /// A figure with nothing in it draws nothing, and a tile that draws
        /// nothing is a tile that shouldn't exist. Checked at composition, so
        /// an empty room can never mint a blank card.
        var isEmpty: Bool {
            switch self {
            case .treemap(let c): return c.count < 2
            case .bars(let b):    return b.isEmpty
            case .rail(let s):    return s.count < 2
            // A pulse needs a real span AND at least one live day, or it is a
            // row of empty boxes claiming to be a year.
            case .pulse(let p):   return p.count < 7 || !p.contains { $0 > 0 }
            // Two points is a line between two dots, not a curve — and with a
            // flat pair it renders as a rule across the tile, which reads as a
            // divider rather than data.
            case .curve(let v):   return v.count < 3
            case .wall(let u):    return u.count < 4
            }
        }
    }

    // MARK: - The lead

    /// One flat thing, for the lead's evidence chips. Holds no `Thing`.
    struct Item: Equatable {
        var id: String
        var title: String
        var source: String
    }

    /// The claim at the top, and the things it is a claim ABOUT.
    ///
    /// The panel below answers "what do my rooms look like right now"; this
    /// answers "what should I know". It survived the §334 rewrite unchanged
    /// because it is the one thing on this surface that is not a figure and
    /// should not be: a connection across your things is a sentence, and
    /// drawing it would be decoration.
    ///
    /// `evidence` may be empty — the model can return a line with no usable
    /// picks — and the claim still stands, just unverifiable by tapping.
    struct Notice: Equatable {
        var claim: String
        var evidence: [Item]
        /// True when a deterministic join stood in for the model's line. The
        /// card's kicker changes wording on it: "noticed overnight" claims a
        /// model looked, and saying that where none exists is §83's fake
        /// status.
        var deterministic: Bool
    }

    /// The whole surface.
    struct Composition: Equatable {
        var notice: Notice?
        var cards: [Card] = []

        /// Nothing to show — the caller falls back to the greeting-and-chips
        /// rest screen, which remains right for a new install. A lead with no
        /// panel is still a surface worth drawing; a panel with no lead is too.
        var isEmpty: Bool { notice == nil && cards.isEmpty }
    }

    // MARK: - Cards

    struct Card: Equatable {
        /// The room this reading belongs to — also the tap target.
        var source: String
        /// The room's OWN hero title ("What your screenshots say"), never a
        /// title invented here: the panel is a window onto the room, and being
        /// able to recognise the card when you get there is the whole point.
        var title: String
        /// The room's own subtitle, clamped.
        var caption: String
        var figure: Figure
        /// `ChipMemory`'s decaying tap weight for this source.
        var affinity: Int
    }

    /// How many tiles the panel shows.
    ///
    /// Twelve is three screens of a two-column grid, which is past the point
    /// where "at a glance" is true — but the cap is not really about screen
    /// space: every tile below the fold is a figure nobody asked to compute.
    /// Eight is two full screens and the honest edge of a glance.
    static let maxCards = 8

    /// Rank and cap.
    ///
    /// Order is AFFINITY first — `ChipMemory`'s tap-learned, decaying weight,
    /// the same signal that already sorts the source strip — so the panel leads
    /// with the rooms you actually open, and a room you never visit drifts to
    /// the tail on its own without an edit surface. Ties break on the figure's
    /// own richness, then on the source NAME, so the order is TOTAL: a panel
    /// that reshuffles between two opens over identical data reads as broken
    /// long before it reads as fresh (§324's ruling, and §332's dictionary bug
    /// one surface over).
    static func rank(_ cards: [Card]) -> [Card] {
        cards
            .filter { !$0.figure.isEmpty }
            .sorted { a, b in
                if a.affinity != b.affinity { return a.affinity > b.affinity }
                let (ra, rb) = (richness(a.figure), richness(b.figure))
                if ra != rb { return ra > rb }
                return a.source < b.source
            }
            .reduce(into: [Card]()) { out, card in
                // One card per room. A room can qualify for several figures
                // (Instagram has both a treemap and a year), and the room
                // itself already picks one — but the composer asks the
                // registries independently, so this is the guard that keeps a
                // double-registered room from taking two tiles.
                guard !out.contains(where: { $0.source == card.source }) else { return }
                guard out.count < maxCards else { return }
                out.append(card)
            }
    }

    /// How much a figure has to say — the tie-break, never the primary sort.
    /// Deliberately crude: it separates a two-cell map from a six-cell one and
    /// nothing finer, because anything cleverer would be a quality judgment
    /// this file has no basis to make.
    static func richness(_ figure: Figure) -> Int {
        switch figure {
        case .treemap(let c): return c.count
        case .bars(let b):    return b.count
        case .rail(let s):    return s.count
        case .curve(let v):   return min(v.count, 8)
        case .wall(let u):    return u.count
        // A pulse is scored on its LIVE days, not its length: every registered
        // grid is 53 columns wide, so raw length would rank every heatmap
        // identically and always above everything else.
        case .pulse(let p):   return p.filter { $0 > 0 }.count
        }
    }

    // MARK: - Normalization

    /// Bars as fractions of the leader, so a tile can draw them without
    /// knowing the room's units. Guards a zero leader — every bar would be
    /// NaN-wide, which SwiftUI renders as a tile of nothing.
    static func normalized(_ bars: [Bar]) -> [Double] {
        guard let top = bars.map(\.value).max(), top > 0 else {
            return Array(repeating: 0, count: bars.count)
        }
        return bars.map { Double($0.value) / Double(top) }
    }

    /// A curve mapped into 0…1 over its own range.
    ///
    /// A FLAT series returns all 0.5 rather than all 0 or a divide-by-zero: a
    /// wallet that hasn't moved is a real state, and drawing it along the floor
    /// reads as "went to zero", which is the most alarming possible way to say
    /// "nothing happened" (§83, in the one place it costs the most).
    static func normalized(_ curve: [Double]) -> [Double] {
        guard let lo = curve.min(), let hi = curve.max() else { return [] }
        guard hi > lo else { return curve.map { _ in 0.5 } }
        return curve.map { ($0 - lo) / (hi - lo) }
    }

    /// Per-day counts bucketed to 0…4 intensity steps, the grammar every
    /// contribution grid uses. Bucketed against the observed MAX rather than
    /// fixed thresholds, so a quiet room still shows its own shape instead of
    /// one uniformly dim wall.
    static func levels(_ pulse: [Int]) -> [Int] {
        guard let top = pulse.max(), top > 0 else {
            return Array(repeating: 0, count: pulse.count)
        }
        return pulse.map { count in
            guard count > 0 else { return 0 }
            let step = Double(count) / Double(top)
            if step > 0.75 { return 4 }
            if step > 0.5  { return 3 }
            if step > 0.25 { return 2 }
            return 1
        }
    }

    /// Trim a room's subtitle to something that fits under a tile title.
    static func clamp(_ s: String, max n: Int = 34) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > n else { return t }
        let head = t.prefix(n)
        if let sp = head.range(of: " ", options: .backwards) {
            return String(head[..<sp.lowerBound]) + "…"
        }
        return String(head) + "…"
    }
}
