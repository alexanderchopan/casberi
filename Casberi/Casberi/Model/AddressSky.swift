import Foundation

/// THE SKY — your onchain world as one picture (prd §435, 2026-08-21).
///
/// The wallet manager used to render the same graph five times: a shelf of the
/// watched wallets, a connections card of who reaches more than one of them, a
/// chip row (later a section per group) for how they're filed, a book row per
/// address, and a card per person behind a tap. Five sections, one graph —
/// which is why the screen read as a settings page no matter how the sections
/// were reordered. This is three of those five fused into one drawing: the
/// watched wallets on a ring, the people who deal with two or more of them
/// floating between the ones they reach, a line wherever a transfer actually
/// landed, and a group's members named where they cluster.
///
/// ## It asserts nothing §295 didn't already assert
///
/// The connections ruling (2026-08-03, user: *"limit the analysis, it should be
/// factual"*) governs every fact here, and this file keeps all of it: **every
/// link draws the same weight** (a connection exists or it doesn't — scaling
/// one by volume would be a claim about which relationship matters), **no link
/// carries a hue**, and **nothing is ranked** — ring order is your own watch
/// order and a connected body's place is decided by which wallets it reaches,
/// which is the same fact the line already states. A body is not bigger because
/// it matters more; it is bigger because you watch it.
///
/// ## Why the RING is watched-only, and the floating bodies are not
///
/// This looks like the watch cap (§170) reaching into the picture and it is
/// NOT — it is a data limit, and confusing the two is how a future pass
/// "fixes" this by putting named addresses on the ring and draws a ring of
/// bodies that can never have an edge.
///
/// Every edge here comes from a landed `Wallet` transaction, and `WalletIngest`
/// reads the chain **only for addresses you watch**. So a named-but-unwatched
/// address has no history of its own in the corpus at all: it appears solely as
/// the COUNTERPARTY of a watched wallet's transaction. We cannot know who it
/// dealt with otherwise, because we never asked.
///
/// Which is exactly the right split, and it means naming stays unlimited in the
/// picture as well as in the book: **the ring is the five you watch; everybody
/// floating between them is your book**, capped by nothing but
/// `AddressConnections.nodeLimit`. Name forty addresses and any of them can
/// appear the moment it turns out to connect two of your wallets. Raising the
/// watch cap would make the ring bigger; it would not change who is eligible to
/// float.
///
/// ## Positions are DETERMINISTIC, never physics
///
/// The whole layout is a pure function of (watch order, which wallets each
/// address reaches, group membership). No forces, no randomness, no animation
/// settling into place. This is not a preference — a map that reshuffles
/// between two opens over identical data reads as broken, which is the lesson
/// `agent-panel-selftest` already paid for with its tile sort ("tiles
/// reshuffling between opens because the sort stopped being total"). The
/// harness asserts the same input yields byte-identical output.
///
/// Coordinates are NORMALIZED (0…1 on both axes, y down) so the view scales
/// them. Nothing here knows what a point is, or what a face is drawn at.
///
/// PURE AND FOUNDATION-ONLY, like `AddressConnections` and `WalletFlow` and for
/// the same reason: the failure mode is a picture that renders beautifully and
/// says something false — a body sitting between two wallets it never touched,
/// two people stacked on one spot, a group named over a cluster that isn't its
/// own. `scripts/address-sky-selftest.sh` compiles this file AS SHIPPED.
enum AddressSky {

    // MARK: - What goes in

    /// One watched wallet, in watch order.
    struct Wallet: Equatable {
        let key: String
        let address: String
        let name: String
    }

    /// One connected address — an address that reached two or more of your
    /// wallets. Built from `AddressConnections.Node`; see the adapter.
    struct Connected: Equatable {
        let key: String
        let address: String
        let name: String
        /// Which of your wallets it reaches, in your watch order.
        let walletKeys: [String]
        /// Which groups this address is filed under, if any.
        let groups: [String]
        /// First seen since the last time this screen was opened. Drawn last
        /// and dashed until looked at — never sorted differently, never
        /// coloured, never counted separately.
        let isNew: Bool
    }

    // MARK: - What comes out

    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    enum BodyKind: Equatable {
        /// A wallet you watch — big, on the ring, wearing its own face tint.
        case watched
        /// Somebody who deals with two or more of them — small, inside.
        case connected
        /// The invitation. One only, never one per free slot: see `layout`.
        case openSlot
    }

    struct Body: Identifiable, Equatable {
        let id: String
        /// Empty for `.openSlot`, which stands for no address at all.
        let address: String
        let name: String
        let kind: BodyKind
        let at: Point
    }

    /// A transfer that actually landed between a connected address and one of
    /// your wallets. Carries no weight and no hue by ruling; `isNew` gates
    /// only WHEN it draws itself, not how.
    struct Link: Identifiable, Equatable {
        let id: String
        let from: Point
        let to: Point
        let isNew: Bool
    }

    /// A group, named where its members actually sit.
    ///
    /// Only groups with **two or more** bodies in the sky get one: a label
    /// floating beside a single face is that face's second caption, and a
    /// constellation of one star is not a constellation.
    struct Constellation: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let at: Point
        /// How many of this group's members are drawn — so the view can say
        /// "Family" over two of four without implying it has two.
        let drawn: Int
    }

    struct Sky: Equatable {
        let bodies: [Body]
        let links: [Link]
        let constellations: [Constellation]

        var watchedBodies: [Body] { bodies.filter { $0.kind == .watched } }
        var connectedBodies: [Body] { bodies.filter { $0.kind == .connected } }
        /// True when a link landed since the last look — the view draws those
        /// last so the map is seen GROWING rather than arriving already grown.
        var hasNew: Bool { links.contains(where: \.isNew) }
    }

    // MARK: - The constants, each with the reason it is that number

    /// Below this the sky is not a picture of anything: one wallet has nothing
    /// to be connected TO, and `AddressConnections.map` returns nil at the same
    /// bar for the same reason. The manager falls back to the plain shelf.
    static let minWallets = 2

    /// How far the watched ring sits from the centre. Bounded by the bodies
    /// themselves: a `watchedDiameter` body centred at 0.33 reaches 0.4125,
    /// inside the unit square with room for the caption the view hangs below.
    static let ringRadius = 0.33

    /// The body sizes, as fractions of the drawing — used HERE only to prove
    /// the ring fits its field (see `ringRadius`). The view draws faces at the
    /// `DS.Face` ramp (`shelf` for a watched wallet, `list` for a connected
    /// one), which this file cannot name because it is Foundation-only; the two
    /// are spelled separately and tied together by a drift guard in
    /// `address-sky-selftest.sh`, the same arrangement `NetworkReceiptsInsight`
    /// and `UnitTreemap` already have for their cell cap.
    ///
    /// A watched wallet is the biggest thing in the sky because you CHOSE it,
    /// never because it is worth more: no size, hue or position anywhere in
    /// this file is read off money (user ruling 2026-08-21 — the manager shows
    /// no balances at all, the feed's crown owns that reading).
    static let watchedDiameter = 0.165
    static let connectedDiameter = 0.105

    /// How far in from its wallets' midpoint a connected body sits. At 1.0 it
    /// would sit exactly on the line between them and the link would vanish
    /// under it; pulled toward the centre, both legs of the connection stay
    /// visible as two separate lines, which is the whole reading.
    static let inwardPull = 0.62

    /// How far apart two bodies reaching the SAME set of wallets are spread.
    /// They share a midpoint exactly, so without this they draw on top of each
    /// other and two people read as one.
    static let twinSpread = 0.115

    // MARK: - The layout

    /// Lays out the sky, or nil when there isn't one to draw.
    ///
    /// `watched` arrives in WATCH ORDER and that order is the ring: the first
    /// wallet you watched sits at the top and the rest follow clockwise. It is
    /// not a ranking — it is the one order the person themselves created, and
    /// it is stable, which is what a map needs above all.
    ///
    /// **One open slot, not one per free slot.** The shelf drew a dashed ring
    /// for every unused watch (prd §182 — "the cap stops being a sentence you
    /// hit and becomes a shape you can see"), which works in a row and does not
    /// work here: three dashed circles orbiting alongside two real wallets read
    /// as three unnamed accounts, not as headroom. The invitation is one body;
    /// the cap goes back to being said, in the line under the drawing.
    static func layout(watched: [Wallet],
                       connected: [Connected],
                       canWatchMore: Bool) -> Sky? {
        guard watched.count >= minWallets else { return nil }

        let centre = Point(x: 0.5, y: 0.5)
        // The ring holds the wallets plus, when there's room, the invitation —
        // one ring of slots rather than a ring with something tacked on, so
        // adding a wallet visibly re-spaces the sky it is joining.
        let ringCount = watched.count + (canWatchMore ? 1 : 0)

        var bodies: [Body] = []
        var walletAt: [String: Point] = [:]
        for (index, wallet) in watched.enumerated() {
            let point = ringPoint(index: index, of: ringCount, around: centre)
            walletAt[wallet.key] = point
            bodies.append(Body(id: wallet.key, address: wallet.address,
                               name: wallet.name, kind: .watched,
                               at: point))
        }
        if canWatchMore {
            bodies.append(Body(id: openSlotID, address: "", name: "",
                               kind: .openSlot,
                               at: ringPoint(index: watched.count,
                                             of: ringCount, around: centre)))
        }

        // Every connected body sits at the midpoint of the wallets it reaches,
        // pulled toward the centre. That is not a judgement about it — it is
        // the same fact its links already draw, made legible before you trace
        // them: somebody who deals with two of your wallets sits between those
        // two.
        //
        // Reaching a wallet we no longer watch cannot move anything, so those
        // keys are dropped; a body left reaching fewer than two is not a
        // connection any more and is not drawn.
        var placeable: [(node: Connected, keys: [String])] = []
        for node in connected {
            let keys = node.walletKeys.filter { walletAt[$0] != nil }
            guard keys.count >= 2 else { continue }
            placeable.append((node, keys))
        }

        // Bodies reaching the SAME set of wallets share a midpoint exactly, so
        // they are counted first and then spread along the perpendicular of
        // their own approach to the centre. Grouped by a SORTED signature, so
        // "reaches A and B" and "reaches B and A" are one cluster.
        var twinCount: [String: Int] = [:]
        for item in placeable {
            twinCount[signature(item.keys), default: 0] += 1
        }

        var links: [Link] = []
        var placed: [String: Point] = [:]
        var seenInCluster: [String: Int] = [:]
        for item in placeable {
            let key = signature(item.keys)
            let index = seenInCluster[key, default: 0]
            seenInCluster[key] = index + 1
            let anchor = midpoint(of: item.keys.compactMap { walletAt[$0] })
            var point = lerp(from: centre, to: anchor, by: inwardPull)
            if let total = twinCount[key], total > 1 {
                point = spread(point, around: centre, index: index, of: total)
            }
            placed[item.node.key] = point
            bodies.append(Body(id: item.node.key, address: item.node.address,
                               name: item.node.name, kind: .connected,
                               at: point))
            for walletKey in item.keys {
                guard let to = walletAt[walletKey] else { continue }
                links.append(Link(id: "\(item.node.key)|\(walletKey)",
                                  from: point, to: to, isNew: item.node.isNew))
            }
        }

        return Sky(bodies: bodies, links: links,
                   constellations: constellations(for: placeable.map(\.node),
                                                  placed: placed))
    }

    /// The id the open slot always wears, so the view can key its tap on a
    /// constant rather than on "the body with an empty address".
    static let openSlotID = "\u{0}open"

    // MARK: - Groups, as clusters

    /// Names each group where its own members actually sit.
    ///
    /// This is the whole reason groups stopped being a filter. A group used to
    /// be a chip you selected, which put the book into a mode; then a section,
    /// which is at least a place. Here it is a REGION — the members are already
    /// scattered across the sky by who they deal with, and the ones that happen
    /// to sit near each other get their name written between them. Nothing
    /// moves to make a group tidier: the position is earned by the graph and
    /// the label follows it, never the other way round. A group whose members
    /// are on opposite sides of the sky simply gets its label in the middle,
    /// which is the honest answer — those two people have nothing to do with
    /// each other.
    ///
    /// Alphabetical, so two groups can never swap between passes. Groups are
    /// case-folded to the book's own key, so "family" and "Family" are one
    /// constellation exactly as they are one group.
    private static func constellations(for nodes: [Connected],
                                       placed: [String: Point]) -> [Constellation] {
        var points: [String: [Point]] = [:]
        var spelling: [String: String] = [:]
        for node in nodes {
            guard let point = placed[node.key] else { continue }
            for group in node.groups {
                let folded = group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !folded.isEmpty else { continue }
                // The first SPELLING seen wins, matching how the book itself
                // resolves a group typed twice in two cases.
                if spelling[folded] == nil { spelling[folded] = group }
                points[folded, default: []].append(point)
            }
        }
        return points.compactMap { folded, list -> Constellation? in
            // One member is a caption, not a constellation. See the type doc.
            guard list.count >= 2, let name = spelling[folded] else { return nil }
            return Constellation(name: name, at: midpoint(of: list),
                                 drawn: list.count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Arithmetic

    /// Slot `index` of `total` on the ring. Starts at the TOP and goes
    /// clockwise, which is the reading order of a clock face and therefore the
    /// order somebody will assume; anything else makes "first watched" a fact
    /// you have to be told.
    private static func ringPoint(index: Int, of total: Int, around centre: Point) -> Point {
        guard total > 0 else { return centre }
        let angle = -Double.pi / 2 + (2 * Double.pi * Double(index) / Double(total))
        return Point(x: centre.x + ringRadius * cos(angle),
                     y: centre.y + ringRadius * sin(angle))
    }

    private static func midpoint(of points: [Point]) -> Point {
        guard !points.isEmpty else { return Point(x: 0.5, y: 0.5) }
        let n = Double(points.count)
        return Point(x: points.reduce(0) { $0 + $1.x } / n,
                     y: points.reduce(0) { $0 + $1.y } / n)
    }

    private static func lerp(from a: Point, to b: Point, by t: Double) -> Point {
        Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// Spreads `total` bodies that share one midpoint, along the perpendicular
    /// of the line from the centre out to that midpoint — so a cluster opens
    /// ACROSS its own connection rather than along it, where it would slide
    /// onto the links it belongs to.
    ///
    /// Centred on the shared point: with two bodies they sit half a spread
    /// either side, with three the middle one keeps the exact midpoint. A
    /// degenerate case — a midpoint sitting exactly on the centre, which two
    /// wallets opposite each other on the ring produce — falls back to a
    /// horizontal spread rather than dividing by zero.
    private static func spread(_ point: Point, around centre: Point,
                               index: Int, of total: Int) -> Point {
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let length = (dx * dx + dy * dy).squareRoot()
        let (px, py) = length < 0.0001 ? (1.0, 0.0) : (-dy / length, dx / length)
        let offset = (Double(index) - Double(total - 1) / 2) * twinSpread
        return Point(x: point.x + px * offset, y: point.y + py * offset)
    }

    private static func signature(_ keys: [String]) -> String {
        keys.sorted().joined(separator: "|")
    }
}
