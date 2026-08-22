import Foundation

/// THE SKY — your onchain world as one picture (prd §435, 2026-08-21).
///
/// The wallet manager used to render the same graph five times: a shelf of the
/// watched wallets, a connections card of who reaches more than one of them, a
/// chip row (later a section per group) for how they're filed, a book row per
/// address, and a card per person behind a tap. Five sections, one graph —
/// which is why the screen read as a settings page no matter how the sections
/// were reordered. This is three of those five fused into one drawing: the
/// watched wallets on a ring, the people who deal with two or more of them on
/// their own ring inside it at the angle between the wallets they reach, a
/// straight line wherever a transfer actually landed, and a group's members
/// named where they cluster.
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
/// ## Why the OUTER ring is watched-only, and the inner one is not
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
/// picture as well as in the book: **the outer ring is the five you watch; the
/// inner ring is your book**, capped by nothing but
/// `AddressConnections.nodeLimit`. Name forty addresses and any of them can
/// appear the moment it turns out to connect two of your wallets. Raising the
/// watch cap would make the outer ring busier; it would not change who is
/// eligible to sit on the inner one.
///
/// The two rings are also what keeps the drawing legible without an assertion
/// to defend it (prd §437): a connected body and a watched wallet sit at
/// different radii, so however close their angles run they can never stack on
/// one spot, and a link between them is a straight line from one ring to the
/// other — long and crossing the middle when the wallets are far apart, short
/// when they are neighbours.
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
    /// These are the `DS.Face` ramp over the FIELD, and the field is
    /// `WalletScreen.skyHeight` minus the view's inset on each side — which is
    /// the fact that was wrong (prd §437). 0.165 and 0.105 are 56/340 and
    /// 36/340, so they have always described a 340pt field; the screen handed
    /// the drawing `skyHeight` 340 and the view insets 30 a side, leaving 280.
    /// Every clearance argument in this file and its harness is made in these
    /// units, so a fifth of the room they all assumed did not exist: a body
    /// directly inside a wallet cleared it by 39pt where two faces need 46.
    /// Nothing here changed — `skyHeight` did, to 400, so the field really is
    /// the 340 these numbers describe. A drift guard now ties all four
    /// together, because this is not a fact any of them can state alone.
    static let watchedDiameter = 0.165
    static let connectedDiameter = 0.105

    /// The radius the CONNECTED bodies sit at — their own ring, inside the
    /// watched one (prd §437, 2026-08-22).
    ///
    /// It was a pull toward the centre from the midpoint of the wallets a body
    /// reached (`inwardPull`, 0.62), which put every body at a different
    /// distance from the middle and, for two wallets facing each other, put it
    /// exactly ON the centre. That is where the drawing lost its subject: with
    /// the links bowed toward the middle as well, a connection read as a short
    /// arc hugging the interior, and the whole picture read as rings inside
    /// rings rather than as anybody reaching anybody.
    ///
    /// A body sits at its own ring at the ANGLE of the wallets it reaches
    /// instead, which buys three things at once. Its two links are straight
    /// lines to two points on the outer ring, so a body reaching wallets on
    /// opposite sides draws a line CROSSING the middle — the reading the
    /// drawing exists for. It can never collide with a wallet however close
    /// their angles run, because they are on different rings — the "two people
    /// stacked on one spot" failure, made impossible by construction rather
    /// than by an assertion. And twins spread along an ARC, which is bounded
    /// by the ring itself (see `spread`).
    ///
    /// Far enough inside `ringRadius` that a `connectedDiameter` body clears a
    /// `watchedDiameter` one RADIALLY — which is the binding case rather than a
    /// corner one: a body reaching two wallets with a third between them takes
    /// that third one's bearing exactly, so it sits directly under a face, and
    /// with five watched that shape is reachable several ways. 0.33 − 0.19 =
    /// 0.14, against the two half-diameters summing to 0.135.
    ///
    /// It is also bounded from BELOW, which is the constraint that decides it:
    /// two wallets 120° apart put the midpoint of their chord at 0.33·cos60° =
    /// 0.165, and a body sitting there lies ON its own two links and swallows
    /// them (the §435 ruling the harness still asserts). So this has to clear
    /// the chord from outside while clearing a face from inside — a window
    /// that only exists at all because the field is 340 (see the diameters).
    static let connectedRadius = 0.19

    /// How far apart two NEIGHBOURING bodies of a twin cluster sit — the chord
    /// between adjacent bodies along the connected ring (see `spread`). Bodies
    /// reaching the SAME set of wallets share an angle exactly, so without this
    /// they draw on top of each other and two people read as one. Just above
    /// `connectedDiameter`, so neighbours clear each other without the cluster
    /// swallowing the ring. On the 340pt field this is 39pt against two
    /// `list` faces needing 36 — it clears, which on the 280pt field the
    /// drawing was actually given it did not (32pt against 36), so the cluster
    /// this constant exists to un-stack was itself overlapping (prd §437).
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
        // The wallet's ANGLE is kept beside its point: a connected body's place
        // is now an angle on its own ring, so the midpoint that decides it has
        // to be taken around the circle rather than across it.
        var walletAngle: [String: Double] = [:]
        for (index, wallet) in watched.enumerated() {
            let angle = ringAngle(index: index, of: ringCount)
            let point = ringPoint(angle: angle, radius: ringRadius, around: centre)
            walletAt[wallet.key] = point
            walletAngle[wallet.key] = angle
            bodies.append(Body(id: wallet.key, address: wallet.address,
                               name: wallet.name, kind: .watched,
                               at: point))
        }
        if canWatchMore {
            bodies.append(Body(id: openSlotID, address: "", name: "",
                               kind: .openSlot,
                               at: ringPoint(angle: ringAngle(index: watched.count,
                                                              of: ringCount),
                                             radius: ringRadius, around: centre)))
        }

        // Every connected body sits on its OWN ring, at the angle between the
        // wallets it reaches. That is not a judgement about it — it is the same
        // fact its links already draw, made legible before you trace them:
        // somebody who deals with two of your wallets sits between those two.
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

        // Every bearing the outer ring already occupies — wallets AND the
        // invitation, since a body tucked under the open slot reads exactly as
        // badly as one tucked under a wallet.
        let ringAngles = (0..<ringCount).map { ringAngle(index: $0, of: ringCount) }

        // Where each body WANTS to be: the angle between the wallets it
        // reaches. Collisions are resolved afterwards, over the whole set at
        // once — see `resolveBearings`.
        let wanted = placeable.map {
            meanAngle(of: $0.keys.compactMap { walletAngle[$0] }, avoiding: ringAngles)
        }
        let bearings = resolveBearings(wanted)

        var links: [Link] = []
        var placed: [String: Point] = [:]
        for (offset, item) in placeable.enumerated() {
            let point = ringPoint(angle: bearings[offset], radius: connectedRadius,
                                  around: centre)
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

    /// The angle of slot `index` of `total`. Starts at the TOP and goes
    /// clockwise, which is the reading order of a clock face and therefore the
    /// order somebody will assume; anything else makes "first watched" a fact
    /// you have to be told.
    private static func ringAngle(index: Int, of total: Int) -> Double {
        guard total > 0 else { return -Double.pi / 2 }
        return -Double.pi / 2 + (2 * Double.pi * Double(index) / Double(total))
    }

    /// A point at `angle` on a ring of `radius`. Both rings — the watched one
    /// and the connected one — are placed through here, so they can never drift
    /// out of concentric.
    private static func ringPoint(angle: Double, radius: Double,
                                  around centre: Point) -> Point {
        Point(x: centre.x + radius * cos(angle),
              y: centre.y + radius * sin(angle))
    }

    /// The angle BETWEEN a set of wallets, taken around the circle.
    ///
    /// A plain average of angles is wrong on a circle — the mean of 350° and
    /// 10° is 180°, the far side — so this is the standard circular mean:
    /// average the unit vectors and read the direction back. For two wallets
    /// that lands exactly on the midpoint of the SHORTER arc, which is what
    /// "between them" means to somebody looking at the drawing.
    ///
    /// Two wallets facing each other across the ring have no midpoint: both
    /// arcs are equal and the vectors cancel to zero. That is not an edge case
    /// to be tolerated but the MINIMUM case to be expected — two watched
    /// wallets and no open slot puts them exactly opposite — so it resolves
    /// deterministically to a quarter turn clockwise of the LOWEST angle,
    /// rather than to whatever `atan2(0, 0)` happens to return.
    ///
    /// The lowest and not the first, which is the whole of its correctness:
    /// the fallback has to be a function of the SET, exactly as the vector
    /// mean above it is. Reading `angles.first` made the answer depend on the
    /// order the wallet keys arrived in, so "reaches A and B" and "reaches B
    /// and A" — one relationship, two spellings — landed a quarter of the ring
    /// apart, and the twin cluster that is supposed to hold them together
    /// never formed. Caught by the harness's own order-insensitivity mutation
    /// on the day this was written (prd §437).
    ///
    /// Which bearing it takes is not cosmetic, and the answer is "the emptiest
    /// one". Measured on the first real dump of the shipped arithmetic — three
    /// wallets plus the invitation, a body reaching the top and bottom ones —
    /// the naive perpendicular put that body on the same bearing as the wallet
    /// to the east, 0.14 away, which the model's own diameters pass (they need
    /// 0.135) and a NARROW SCREEN does not: the view draws faces at fixed
    /// points, so on a 280pt-wide field 0.14 is 39pt between centres where a
    /// `shelf` and a `list` face need 46. A body tucked radially under
    /// somebody else's face is exactly the reading this whole pass exists to
    /// end, and it would have shipped looking fine on the device it was
    /// checked on.
    ///
    /// Taking the OTHER perpendicular does not save it — with four ring slots
    /// both perpendiculars are occupied — and it does not have to, because for
    /// two wallets facing each other the two arcs are equal and **every**
    /// bearing lies between them. So the candidates are the midpoints of the
    /// gaps in the occupied ring, and the winner is the one furthest from
    /// anything already there, ties going to the lowest bearing so the choice
    /// stays a pure function of the set.
    private static func meanAngle(of angles: [Double],
                                  avoiding others: [Double]) -> Double {
        guard let lowest = angles.min() else { return -Double.pi / 2 }
        let x = angles.reduce(0) { $0 + cos($1) }
        let y = angles.reduce(0) { $0 + sin($1) }
        guard (x * x + y * y).squareRoot() > 0.0001 else {
            return emptiestBearing(fallback: lowest + Double.pi / 2, among: others)
        }
        return atan2(y, x)
    }

    /// The midpoint of the widest gap in an occupied ring — where a body can
    /// stand without sitting under anybody. Falls back to the caller's own
    /// bearing when there is nothing to avoid.
    private static func emptiestBearing(fallback: Double, among others: [Double]) -> Double {
        guard others.count > 1 else { return fallback }
        let sorted = others.sorted()
        var best = fallback
        var bestClearance = clearance(of: fallback, from: others)
        for (index, angle) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1] : sorted[0] + 2 * Double.pi
            let candidate = (angle + next) / 2
            let gap = clearance(of: candidate, from: others)
            // Strictly greater, so a tie keeps the earlier — and the ring is
            // walked in sorted order, which makes "earlier" the lowest bearing
            // rather than whichever the caller happened to hand over first.
            if gap > bestClearance + 0.0001 {
                best = candidate
                bestClearance = gap
            }
        }
        return best
    }

    /// How far `angle` is from the nearest of `others`, around the circle.
    private static func clearance(of angle: Double, from others: [Double]) -> Double {
        others.reduce(Double.pi) { best, other in
            var gap = abs((angle - other).truncatingRemainder(dividingBy: 2 * Double.pi))
            if gap > Double.pi { gap = 2 * Double.pi - gap }
            return min(best, gap)
        }
    }

    private static func midpoint(of points: [Point]) -> Point {
        guard !points.isEmpty else { return Point(x: 0.5, y: 0.5) }
        let n = Double(points.count)
        return Point(x: points.reduce(0) { $0 + $1.x } / n,
                     y: points.reduce(0) { $0 + $1.y } / n)
    }

    /// Pushes bodies apart until no two are closer than `twinSpread`, over the
    /// WHOLE set at once, and returns each one's final bearing in the order it
    /// was handed over.
    ///
    /// This replaces a per-cluster spread that grouped bodies by the set of
    /// wallets they reached (prd §436) and then, briefly, by their exact
    /// bearing (§437). Both were too narrow, and the second only looked
    /// sufficient: two bodies collide when their bearings are CLOSE, not when
    /// they are equal, and a set of five watched wallets produces plenty of
    /// pairs a fraction of a step apart. Measured across every shape the
    /// layout allows, grouping by exact bearing still left two faces 0.017
    /// apart where they need 0.105 — bodies visibly overlapping, in a file
    /// whose header names "two people stacked on one spot" as the failure it
    /// exists to prevent. Separation is a property of the whole ring, so it is
    /// computed over the whole ring.
    ///
    /// Sorted by bearing and then by ORIGINAL POSITION, never by hash order:
    /// the sort has to be total or two bodies swap places between opens over
    /// identical data, which is the `agent-panel-selftest` lesson this file
    /// already cites. Then the standard one-dimensional relaxation — walk in
    /// order, push each body to at least a step past the one before — and a
    /// final shift by the MEAN displacement, so a cluster ends up centred on
    /// what it asked for rather than pushed off to one side. A group of twins
    /// that all wanted one bearing therefore lands symmetrically around it,
    /// exactly as §436's small ring did.
    ///
    /// When the bodies cannot all fit (`count · step` past a full turn) they
    /// are spaced evenly instead: at the cap of six that never happens, so it
    /// is a guarantee rather than a behaviour anybody will see.
    private static func resolveBearings(_ wanted: [Double]) -> [Double] {
        guard wanted.count > 1 else { return wanted }
        let step = 2 * asin(min(1, twinSpread / (2 * connectedRadius)))
        var order = Array(wanted.indices)
        order.sort { wanted[$0] == wanted[$1] ? $0 < $1 : wanted[$0] < wanted[$1] }

        var placed = order.map { wanted[$0] }
        if Double(placed.count) * step >= 2 * Double.pi {
            let even = 2 * Double.pi / Double(placed.count)
            for i in placed.indices { placed[i] = placed[0] + Double(i) * even }
        } else {
            for i in 1..<placed.count {
                placed[i] = max(placed[i], placed[i - 1] + step)
            }
            // The wrap: the last body must also clear the first, going round.
            let overlap = (placed[0] + 2 * Double.pi) - (placed[placed.count - 1] + step)
            if overlap < 0 {
                let even = 2 * Double.pi / Double(placed.count)
                for i in placed.indices { placed[i] = placed[0] + Double(i) * even }
            }
        }
        // Centre the result on what was asked for, so nothing drifts forward.
        let shift = zip(placed, order).reduce(0.0) { $0 + ($1.0 - wanted[$1.1]) }
            / Double(placed.count)

        var out = wanted
        for (slot, index) in order.enumerated() { out[index] = placed[slot] - shift }
        return out
    }
}
