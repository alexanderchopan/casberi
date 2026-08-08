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

    /// One side-lane of the flow band — `WalletFlow.Lane`, flattened.
    struct FlowLane: Equatable {
        var name: String
        var usd: Double
        /// Legs folded into this lane; the view says "×3" when > 1.
        var count: Int
    }

    /// One mark on the day dial — a thing at its hour, with how recent it is.
    struct DialMark: Equatable {
        /// 0…24, fractional. Hour of day is the whole point: the heatmaps
        /// answer WHICH DAYS and nothing in the app answers which hours.
        var hour: Double
        /// 0 (oldest in window) … 1 (today) — drives the radius, so today
        /// rides the rim and the week fades inward.
        var recency: Double
        /// The room, for hue.
        var source: String
    }

    /// One band of the theme river — a theme's weekly volume, oldest first.
    struct RiverBand: Equatable {
        var label: String
        var weeks: [Int]
        /// Total across the window, for ordering and for the caption.
        var total: Int { weeks.reduce(0, +) }
    }

    /// One dot on the semantic map — a thing already projected into the unit
    /// square. The PROJECTION happens upstream (`SemanticProjection`), never
    /// here: this file stays arithmetic, and the projection has to be cached
    /// anyway or the map would reshuffle between opens.
    struct Dot: Equatable {
        var x: Double
        var y: Double
        var source: String
    }

    /// A named cluster on the semantic map — its centre and its own top term.
    struct DotCluster: Equatable {
        var label: String
        var x: Double
        var y: Double
        var radius: Double
    }

    /// One deadline on a runway — where it sits on the axis and how close it is.
    struct RunwayMark: Equatable {
        /// 0…1 along the axis. Overdue pins to 0 rather than running off the
        /// left edge, which is `StripeRoom.position`'s own rule: the deadline
        /// you most need to see is the one you already missed.
        var position: Double
        var overdue: Bool
        /// Inside three days — the mark ramps toward the warn colour, because
        /// urgency is STATE and state is allowed colour.
        var urgent: Bool
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
        /// The money's sankey — inflows, the spine, outflows (§240's band).
        /// Always a FULL-WIDTH cell: the inventory that sized this panel is
        /// explicit that three columns of labelled lanes cannot survive half
        /// width, and the user's ask was the diagram, not a thumbnail of one.
        case flow(inLanes: [FlowLane], outLanes: [FlowLane])

        /// The day dial (prd §337) — a week of things on a 24-hour clock.
        /// Radially symmetric, so it is the ONE new figure that reads at every
        /// size including the 118pt small cell: no labels to clip, hue carries
        /// identity, and the shape itself is the reading.
        case dial([DialMark])
        /// The theme river (prd §337) — attention as movement rather than
        /// snapshot. A band figure: ten weeks of bands need horizontal run.
        case river([RiverBand])
        /// The semantic map (prd §337) — the corpus arranged by meaning.
        /// Hero or band only: at 118pt the clusters merge into one smudge and
        /// their labels collide, which turns the app's one visible claim about
        /// its own intelligence into noise.
        case scatter(dots: [Dot], clusters: [DotCluster])
        /// A time rail with deadlines on it (prd §338) — Stripe's disputes and
        /// dunning, Cloudflare's certificates. Both rooms already draw exactly
        /// this and both were left out of §337 because their FULL cards are
        /// mostly rows; the rail alone is the half that draws, and it survives
        /// the small cell precisely because it is one axis with no labels.
        case runway(marks: [RunwayMark], span: String)

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
            // One side alone is a bar chart pretending to be a flow —
            // `WalletFlow.band` already declines those windows, and this
            // re-states it so a future caller can't hand one in.
            case .flow(let inL, let outL): return inL.isEmpty || outL.isEmpty
            // A dial of three marks is three dots on a circle, not a rhythm —
            // and rhythm is the only thing it claims.
            case .dial(let m):    return m.count < 12
            // A river needs at least two themes to be a river and enough weeks
            // to show drift; one band over ten weeks is an area chart.
            case .river(let b):   return b.count < 2 || (b.first?.weeks.count ?? 0) < 4
            // A map with no named cluster is a spray of dots asserting nothing.
            case .scatter(let d, let c): return d.count < 12 || c.isEmpty
            // One dot on an axis is a dot. A runway's claim is the SPREAD —
            // what is close versus what is far — and one deadline has none.
            case .runway(let m, _): return m.count < 2
            }
        }
    }

    /// The whole surface — the figures, and nothing else.
    ///
    /// §334's first cut led with a `Notice` card (a model-written claim with
    /// evidence chips). It lasted a day: the user's ruling is "one intro
    /// sentence and the rest ONLY visualizations", and the greeting already is
    /// that sentence — so the lead card was text synthesis wearing a hero
    /// slot, and it is gone rather than demoted. The composed line still
    /// exists where it always lived (`HomeInsightStore`, the brief, the
    /// Noticed chip); this surface just stopped being one of its homes.
    struct Composition: Equatable {
        var cards: [Card] = []

        /// Nothing to show — the caller falls back to the greeting-and-chips
        /// rest screen, which remains right for a new install.
        var isEmpty: Bool { cards.isEmpty }
    }

    /// Where a figure is legible.
    ///
    /// Bento means slots differ in SHAPE, not just scale — so this is a real
    /// constraint rather than a hint. A figure routed to a slot it can't hold
    /// doesn't shrink gracefully; it clips, collides, or turns to mush, and
    /// all three render as a perfectly good-looking tile.
    enum Fit: Equatable {
        /// Reads anywhere, including the 118pt small cell.
        case any
        /// Needs the hero's double height or a full-width band.
        case large
        /// Full width only — labelled columns on both sides.
        case bandOnly
    }

    static func fit(_ figure: Figure) -> Fit {
        switch figure {
        // Radially symmetric with no labels — the one new figure that holds
        // at every size.
        case .dial:    return .any
        case .runway:  return .any
        case .flow:    return .bandOnly
        case .river:   return .bandOnly
        // FULL WIDTH ONLY (§339). It was `.large`, which permits the tall
        // column — and half width is exactly where its cluster labels began
        // colliding into gibberish ("techchstartupsdisrupt"). A map of a
        // corpus is a wide figure or it is mush.
        case .scatter: return .bandOnly
        default:       return .any
        }
    }

    // MARK: - Cards

    struct Card: Equatable {
        /// The room this reading belongs to — the TAP target.
        var source: String
        /// The dedupe identity, distinct from `source` since 2026-08-07's flow
        /// amendment: the Wallet is the one room with two panel-worthy figures
        /// (its balance curve and its sankey), so the one-tile-per-room rule
        /// keys on this instead. Every other caller passes the source itself.
        var key: String
        /// The room's OWN hero title ("What your screenshots say"), never a
        /// title invented here: the panel is a window onto the room, and being
        /// able to recognise the card when you get there is the whole point.
        var title: String
        /// The room's own subtitle, clamped.
        var caption: String
        var figure: Figure
        /// `ChipMemory`'s decaying tap weight for this source.
        var affinity: Int
        /// The ONE reading the hero carries under its figure — "$12,480 ·
        /// +1.8%". A sentence the room already says about itself, not a tally:
        /// §213 bans counting things, and a balance with its delta is a
        /// reading, not a count. nil everywhere but the hero, and nil for any
        /// room with no honest one-liner.
        var reading: String?
        /// Direction, when the figure has one — drives green/red on the curve
        /// and the money bands. `nil` where direction is meaningless, and
        /// deliberately nil for a move that rounds to zero (§83's flat rule:
        /// a change with no direction gets no sign and no colour).
        var rising: Bool?
    }

    /// A ranked card's SLOT in the bento (prd §334 amendment, layout B).
    ///
    /// Derived from position, never stored: the hero is simply the top-ranked
    /// card, which `rank` already puts first — so "your most-visited room gets
    /// the big cell" costs no new signal. The pattern is fixed (hero, then a
    /// tall beside two smalls, then pairs) because a layout that re-derives
    /// itself from content measurements re-shuffles when a figure changes
    /// shape, and a panel that rearranges between opens reads as broken —
    /// the same total-order reasoning `rank` itself carries.
    enum Slot: Equatable {
        /// Full width, double height — the top-ranked room.
        case hero
        /// One column, double height — sits beside two smalls.
        case tall
        /// One column, single height.
        case small
        /// Full width, band height — the flow figure's slot, taken by SHAPE
        /// rather than rank: a sankey's three labelled columns cannot survive
        /// half width, so the grid routes every `.flow` here regardless of
        /// where it ranked.
        case band

        static func at(_ index: Int) -> Slot {
            switch index {
            case 0:  return .hero
            case 1:  return .tall
            default: return .small
            }
        }
    }

    /// How many tiles the panel shows.
    ///
    /// Twelve is three screens of a two-column grid, which is past the point
    /// where "at a glance" is true — but the cap is not really about screen
    /// space: every tile below the fold is a figure nobody asked to compute.
    /// Eight is two full screens and the honest edge of a glance.
    /// Raised from 8 (user, 2026-08-07: "its fine if the agent displays even
    /// more than ten, really if we have a visualization in the app that is
    /// active some form of it should by and large be in the agent"). The cap
    /// is now a runaway guard rather than an editorial choice — every live
    /// figure earns a slot, and scrolling is the honest cost of having a lot
    /// connected.
    static let maxCards = 20

    /// What a figure is WORTH leading with (prd §336, user: "nobody cares about
    /// your capture year or your chat year tho, those are superfluous metrics",
    /// and "topic maps > capture year or chat year").
    ///
    /// A contribution wall answers WHEN — the weakest thing a room can say,
    /// and the same ruling `FeedScreen.shapedSections` already made when it
    /// moved the heatmap LAST in the hero chain on 2026-07-31. The panel
    /// inherited the wrong half of that: the per-room chain preferred a topic
    /// map correctly, but `rank` then sorted PULSES from term-poor rooms above
    /// real figures from richer ones, so the open led with "Your capture year"
    /// over four live days. Grade beats affinity now — a wall shows only when
    /// nothing better exists, and can never take the hero cell.
    ///
    /// Everything above `.pulse` is deliberately FLAT: a treemap, a
    /// leaderboard and a flow all answer WHAT or WHO, and ranking them against
    /// each other would be a quality judgment this file has no basis to make.
    /// Affinity — the room you actually open — decides among them.
    static func grade(_ figure: Figure) -> Int {
        switch figure {
        case .pulse: return 0
        // The cross-source figures (prd §337) outrank a room's own reading:
        // they are the only things on this surface that no room can show, and
        // "something you don't see on All" was the panel's whole brief.
        case .dial, .river, .scatter: return 2
        default:     return 1
        }
    }

    /// Rooms that always hold a slot when they have anything to draw (user:
    /// "the wallet should always be on the visualizations"). Pinned ahead of
    /// affinity, because affinity is a TAP counter and the wallet is the one
    /// room whose figure you want without having gone looking for it.
    static let pinnedSources: Set<String> = ["Wallet"]

    /// Rank and cap.
    ///
    /// Order is PINNED first, then GRADE, then AFFINITY — `ChipMemory`'s
    /// tap-learned, decaying weight,
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
                let (pa, pb) = (pinnedSources.contains(a.source),
                                pinnedSources.contains(b.source))
                if pa != pb { return pa }
                let (ga, gb) = (grade(a.figure), grade(b.figure))
                if ga != gb { return ga > gb }
                if a.affinity != b.affinity { return a.affinity > b.affinity }
                let (ra, rb) = (richness(a.figure), richness(b.figure))
                if ra != rb { return ra > rb }
                return a.source < b.source
            }
            .reduce(into: [Card]()) { out, card in
                // One card per KEY. A room can qualify for several registry
                // figures (Instagram has both a treemap and a year) and the
                // room itself picks one, so a double-registered room must not
                // take two tiles — but the key is not the source, because the
                // Wallet legitimately holds two (curve and flow) under keys of
                // their own.
                guard !out.contains(where: { $0.key == card.key }) else { return }
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
        case .flow(let inL, let outL): return inL.count + outL.count
        // Live HOURS, not marks: a hundred things all landing at 9am says less
        // about a day's shape than twenty spread across it.
        case .dial(let m):    return Set(m.map { Int($0.hour) }).count
        case .river(let b):   return b.count
        case .scatter(_, let c): return c.count
        case .runway(let m, _): return m.count
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

    /// Money, compact — the ONE formatter the panel uses (prd §341).
    ///
    /// The tiers mirror `WalletIngest.HoldingsGroup.subline`, which is what the
    /// Wallet room itself prints, because the panel is a window onto that room
    /// and the two must never disagree about the same number. They did: the
    /// panel's own formatter stopped at K, so a watched wallet holding $7.26M
    /// rendered "$7258k" on the hero while the room three taps away said
    /// "$7.0M". `TodayBrief.compactUSD` had the identical ceiling and the
    /// identical bug.
    ///
    /// A B tier exists because the app watches whoever you point it at, and
    /// "$7258k" is exactly what a missing tier looks like one order up.
    static func compactUSD(_ usd: Double) -> String {
        let v = abs(usd)
        if v >= 1_000_000_000 { return String(format: "$%.1fB", usd / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "$%.1fM", usd / 1_000_000) }
        if v >= 10_000        { return String(format: "$%.0fK", usd / 1_000) }
        if v >= 1_000         { return String(format: "$%.1fK", usd / 1_000) }
        return String(format: "$%.0f", usd)
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
