import Foundation

/// What the Ethrex Privacy room DRAWS (prd §593b).
///
/// Foundation-only by design so `scripts/privacy-selftest.sh` compiles it WHOLE
/// and unmodified. `PrivacyDevnetFigures.swift` is the SwiftUI half; every
/// arithmetic decision lives here, for the reason every room in this family
/// splits the same way — nothing on this host can make a proof age out, a frame
/// halt or a pool grow, so a harness is the only proof these numbers are right.
///
/// ## Why the room needed this
///
/// The room shipped with ONE drawing (a 6pt meter on Home, over the freshest
/// root alone) and six text lists. That is not a shortage of taste, it is a
/// shortage of shape: every reading here is a count of events or a position in
/// a ring, so there is nothing to plot in the ordinary sense and the easy
/// answer is a sentence. The answer taken instead is that the ring itself is
/// the picture, and that a transaction has an ANATOMY — frames, spend keys,
/// snapshots — which is the same fact the scopes already split apart.
///
/// ## The rules this file encodes
///
/// - **NOTHING HERE IS MONEY.** Test ETH has no market, so no figure is a
///   price, a total or a share of a total. Every number below is a count of
///   events or a number of SLOTS.
/// - **No colour carries state**, inherited from `PrivacyDevnetRoomCard`'s own
///   ruling: a proof whose snapshot has left the ring was valid when it landed
///   and its transaction is settled, so there is nothing red about it. Identity
///   is carried by SHAPE (a bar is a frame, a disc is a spend key, a diamond is
///   a snapshot), which is also what keeps the drawing legible to a reader who
///   cannot separate the hues.
/// - **A truncated list SAYS SO.** Every cap below reports its overflow, since
///   a list cut at the slot's edge and a complete one look identical, which is
///   this repo's oldest recurring defect (§307, §309).
/// - **Nil is never zero.** An address the chain did not answer for draws no
///   tally at all rather than a row of empty pips, and a frame with no budget
///   read draws an equal share rather than a guessed one.
enum PrivacyDevnetFigure {

    // MARK: - The track

    /// One referenced snapshot, placed on the chain's memory.
    ///
    /// `position` is a fraction of the 8,192-slot ring where **1 is NOW** and 0
    /// is the far edge, so a mark travels leftward as the chain advances — the
    /// direction the window actually drains. It is nil for a reference that has
    /// left the ring, which the view draws hollow just past the edge; `agedBy`
    /// then carries how long ago it went.
    struct Mark: Equatable, Sendable, Identifiable {
        var slot: UInt64
        var position: Double?
        var agedBy: UInt64?
        /// How many references collapsed onto this point. Two proofs against
        /// the same snapshot are one mark, because they are one point on the
        /// ring and drawing them twice paints a diamond nobody can count.
        var count: Int
        /// Whether the view should print this mark's own reading beside it.
        /// Decided HERE rather than in the view, because it is a spacing rule
        /// with a number in it and therefore something a harness can pin.
        var labelled: Bool
        /// Which source's set this snapshot belongs to, 0-based, in
        /// `PrivacyDevnetRoots.bySource`'s own total order. **The collapse is
        /// by (set, slot) and not by slot alone (prd §598)**: two sources may
        /// register a root in the same slot, and folding those into one mark
        /// draws two different anonymity sets as one point — which is the
        /// error the ring exists to make visible, committed by the ring.
        var set: Int
        var id: String { "\(set):\(slot)" }
    }

    /// The closest two labels may sit, as a fraction of the track's width.
    ///
    /// **Measured against the drawing, not chosen**: at the room's width a
    /// slot-count label is ~62pt against a ~330pt track, so two labels inside
    /// 0.18 of each other overlap. This is the rule that stops the commonest
    /// arrangement there is — several proofs against snapshots minutes apart —
    /// from rendering as one illegible smear.
    static let labelGap: Double = 0.18

    /// How many marks may carry a label at all, before the track is just text.
    static let labelCap = 3

    /// Place references on the ring, newest first.
    ///
    /// **A mark AHEAD of the head is placed at 1, not off the end.** That state
    /// is real rather than hypothetical (a lagging RPC answers with a head slot
    /// behind a reference we already read), and the honest drawing is "as new as
    /// it gets" — never a mark floating past NOW, which reads as a snapshot from
    /// the future.
    static func marks(_ references: [PrivacyDevnetRoots.Reference],
                      headSlot: UInt64) -> [Mark] {
        // The ordinal every mark wears, off `bySource`'s own total order — so
        // the number a set has on the ring is the number it has in the list
        // below it and in the sheet behind it, which is the whole of what
        // makes an ordinal an identity rather than a decoration.
        let order = PrivacyDevnetRoots.bySource(references)
        var setOf: [Data: Int] = [:]
        for (i, g) in order.enumerated() { setOf[g.source] = i }

        struct Key: Hashable { var set: Int; var slot: UInt64 }
        var counts: [Key: Int] = [:]
        for r in references {
            counts[Key(set: setOf[r.sourceID] ?? 0, slot: r.slot), default: 0] += 1
        }

        var out: [Mark] = counts.keys.map { key in
            let ref = PrivacyDevnetRoots.Reference(sourceID: Data(), slot: key.slot, root: Data())
            let n = counts[key] ?? 1
            switch PrivacyDevnetRoots.standing(of: ref, headSlot: headSlot) {
            case .live(let remaining):
                return Mark(slot: key.slot,
                            position: Double(remaining) / Double(PrivacyDevnetRoots.windowSlots),
                            agedBy: nil, count: n, labelled: false, set: key.set)
            case .aged(let by):
                return Mark(slot: key.slot, position: nil, agedBy: by,
                            count: n, labelled: false, set: key.set)
            case .ahead:
                return Mark(slot: key.slot, position: 1, agedBy: nil,
                            count: n, labelled: false, set: key.set)
            }
        }
        // Newest first, and TOTAL — the set ordinal breaks a slot tie, so
        // nothing is left to tie on and the ring cannot reshuffle between
        // opens over identical data.
        out.sort { $0.slot == $1.slot ? $0.set < $1.set : $0.slot > $1.slot }

        // Labels are spent newest-first, which is the order somebody reads the
        // ring in, and an aged mark always gets one: it is the only mark whose
        // position says nothing, so without its own words it is a hollow shape
        // with no reading at all.
        // **AGED MARKS ARE NOT LABELLED (prd §593d, user report).** An aged
        // mark once printed "gone N ago" beside its hollow shape, and two of
        // them stacked into a double line of tertiary text under the track
        // that read as broken. The hollow diamond just past the leading edge,
        // beside the axis's own "leaves the chain's memory", already says it —
        // and the head sentence carries the count. Only LIVE marks earn a
        // label, spent newest-first, and even then only where they will not
        // collide.
        var spent = 0
        var lastLabelled: Double?
        for i in out.indices {
            guard spent < labelCap else { break }
            guard let p = out[i].position else { continue }
            if let last = lastLabelled, abs(last - p) < labelGap { continue }
            out[i].labelled = true
            lastLabelled = p
            spent += 1
        }
        return out
    }

    // MARK: - The ring (prd §598)

    /// **THE CHAIN'S MEMORY IS A RING, SO IT IS DRAWN AS ONE.**
    ///
    /// EIP-8272's predeploy masks a slot with `0x1fff` — the window is a ring
    /// buffer, literally, and `PrivacyDevnetRoots.ringIndex` already computes
    /// the wrap. It was drawn as a straight bar with a caption at each end
    /// saying which way time ran ("leaves the chain's memory" … "now"), a
    /// caption repeated on Home AND once per lane in the Roots scope. An arc
    /// needs neither: **the gap at the bottom IS the exit**, so a snapshot that
    /// leaves the window falls into it, and the shape says "memory that wraps"
    /// with nothing to read.
    ///
    /// **NOW is at the top and age runs CLOCKWISE**, which is the direction a
    /// clock face already teaches. A mark at `position` 1 sits at NOW; one
    /// about to leave sits at `sweep`, just before the gap.
    ///
    /// The sweep leaves 60° open at the bottom. Wide enough that the two ends
    /// read as two ends rather than a closed circle with a nick in it, narrow
    /// enough that the ring is still a ring.
    static let ringSweep: Double = 300

    /// Where an aged mark sits: inside the gap, past the exit — out of the
    /// ring, which is exactly where it is. Never inside the arc, which would
    /// place it among the live ones at an age it no longer has.
    static let ringAgedAngle: Double = 316

    /// The closest two marks may sit on the arc, in degrees.
    ///
    /// **Measured against the drawing rather than chosen**: an 11pt diamond on
    /// a 120pt-diameter ring subtends ~10.5°, so two marks inside 12° of each
    /// other touch. This is the arc's form of `spaced`'s nudge and it exists
    /// for the same measured reason — the pool address's proofs sit five blocks
    /// apart across ~10,500, so at their true angles they render as one
    /// diamond, which is the figure whose whole job is how many there were.
    static let ringGap: Double = 12

    /// One mark, placed on the arc.
    struct Placement: Equatable, Sendable, Identifiable {
        var mark: Mark
        /// Degrees clockwise from NOW at the top.
        var angle: Double
        var id: String { mark.id }
    }

    /// The angle a position sits at. Aged (nil) goes to the gap.
    static func ringAngle(position: Double?) -> Double {
        guard let position else { return ringAgedAngle }
        let clamped = min(max(position, 0), 1)
        return (1 - clamped) * ringSweep
    }

    /// Place marks on the arc, nudging any that would overlap.
    ///
    /// **ORDER AND AGE ARE EXACT; ONLY CROWDING IS RELIEVED** — `spaced`'s own
    /// contract, on an arc. Marks are swept newest-first pushing any that
    /// would touch its predecessor to exactly `ringGap` away, then swept back
    /// from the exit so nothing is pushed past it into the gap and mistaken
    /// for a snapshot that has left the ring. **Aged marks are never nudged**:
    /// they are all at one place by definition, and spreading them along the
    /// gap would draw a scale where there is none.
    static func ringPlacements(_ marks: [Mark], gap: Double = ringGap) -> [Placement] {
        let live = marks.filter { $0.position != nil }
        let aged = marks.filter { $0.position == nil }
        var angles = live.map { ringAngle(position: $0.position) }
        if angles.count > 1 {
            for i in 1..<angles.count where angles[i] - angles[i - 1] < gap {
                angles[i] = angles[i - 1] + gap
            }
            // The exit sweep: the forward pass can push the oldest mark past
            // the end of the arc, and a live snapshot drawn in the gap reads
            // as one that has already left.
            if let last = angles.last, last > ringSweep {
                angles[angles.count - 1] = ringSweep
                for i in stride(from: angles.count - 2, through: 0, by: -1)
                where angles[i + 1] - angles[i] < gap {
                    angles[i] = angles[i + 1] - gap
                }
            }
        }
        var out = zip(live, angles).map { Placement(mark: $0, angle: min(max($1, 0), ringSweep)) }
        out.append(contentsOf: aged.map { Placement(mark: $0, angle: ringAgedAngle) })
        return out
    }

    // MARK: - The ring is alive (prd §598)

    /// How far a position drifts while nobody is reading the chain.
    ///
    /// **THIS IS AN ESTIMATE AND IT MAY NEVER CROSS THE RIM.** The head slot is
    /// measured once per sweep and the ring drains continuously, so a ring that
    /// only moves when a sweep lands is a clock that ticks every two minutes.
    /// Drifting it between sweeps costs nothing and is the difference between a
    /// diagram and an instrument.
    ///
    /// What makes it honest is the CLAMP, and it is the whole of the safety
    /// argument: the drift may take a mark arbitrarily close to the exit and
    /// **never to it**. Only a real read may say a snapshot has aged out —
    /// which is right twice over, because the seconds-per-slot figure is this
    /// devnet's assumed cadence rather than a measured one, and because the
    /// aged state is the only one on this ring that changes what a row SAYS.
    ///
    /// **The drift also stops.** Past `driftCap` the app is looking at a
    /// reading it can no longer stand behind, and extrapolating an hour of
    /// unobserved chain is inventing an hour of chain. It freezes rather than
    /// running on, which is the same "we stopped being able to say" the pending
    /// rows one seat over already draw.
    static let driftFloor: Double = 0.006
    static let driftCap: TimeInterval = 240

    static func drifted(position: Double, secondsSinceRead: TimeInterval,
                        secondsPerSlot: UInt64 = PrivacyDevnetRoots.secondsPerSlot,
                        windowSlots: UInt64 = PrivacyDevnetRoots.windowSlots) -> Double {
        guard position > 0, secondsSinceRead > 0, secondsPerSlot > 0, windowSlots > 0 else {
            return max(position, 0)
        }
        let elapsed = min(secondsSinceRead, driftCap)
        let slots = elapsed / Double(secondsPerSlot)
        let moved = position - slots / Double(windowSlots)
        // Never to the rim, and never past it: an estimate must not age a
        // snapshot out.
        return max(moved, min(position, driftFloor))
    }

    // MARK: - The anatomy

    /// One frame, as the figure needs it.
    ///
    /// A plain value rather than the bridge's own type, so this file stays
    /// Foundation-only (`PrivacyDevnetRoom.Account`'s reason). The budget field
    /// names are **this chain's** — `gasLimit` and `stateLimit`, where Hegotá
    /// spells them `executionGasLimit`/`stateGasLimit` and Frames
    /// `gasLimit`/`stateGasLimit` (§593, measured). A reader written for one
    /// chain draws nil budgets on another, which renders as frames that had no
    /// budget at all rather than as an error.
    struct Frame: Equatable, Sendable {
        var gasLimit: UInt64?
        var stateLimit: UInt64?
        var succeeded: Bool?

        init(gasLimit: UInt64? = nil, stateLimit: UInt64? = nil, succeeded: Bool? = nil) {
            self.gasLimit = gasLimit
            self.stateLimit = stateLimit
            self.succeeded = succeeded
        }
    }

    /// What one transaction is made of, in the order it is drawn.
    enum Item: Equatable, Sendable, Identifiable {
        /// A step of the transaction. `share` is its width, summing to 1 across
        /// the strip; `failed` is true ONLY for a frame the receipt said failed,
        /// never for one whose status was unread.
        case frame(share: Double, failed: Bool)
        /// A one-time spend key.
        case key
        /// A snapshot this transaction proved against.
        case root
        /// Somebody else paid.
        case sponsor

        var id: String {
            switch self {
            case .frame(let s, let f): return "f\(s)\(f)"
            case .key: return "k"
            case .root: return "r"
            case .sponsor: return "s"
            }
        }
    }

    /// The narrowest a frame may be drawn, as a share of the strip.
    ///
    /// `HegotaFrameStrip`'s own constant, and for its reason: a frame that used
    /// a thousandth of the gas is still a step that ran, and at its true width
    /// it is a sub-pixel sliver, which reads as four frames where there were
    /// five. The clamp costs proportionality at the bottom of the range and
    /// buys the count being right, which is the fact the strip is for.
    static let minFrameShare: Double = 0.12

    /// The widths of a transaction's frames.
    ///
    /// **Weighted ONLY when every frame carries a budget.** A strip where three
    /// frames are measured and one is not would draw the unmeasured one at
    /// whatever the arithmetic happened to leave over, and present it as its
    /// budget — a number invented by the drawing. All-or-nothing, so a partial
    /// read falls back to equal widths, which claims nothing.
    ///
    /// **The budget, not the gas used**: the strip is what the transaction was
    /// ALLOWED, which is the field the envelope carries for every frame; usage
    /// is on the receipt and is not read per frame today.
    static func shares(_ frames: [Frame]) -> [Double] {
        guard !frames.isEmpty else { return [] }
        let equal = Array(repeating: 1.0 / Double(frames.count), count: frames.count)
        let budgets = frames.map(\.gasLimit)
        guard !budgets.contains(where: { $0 == nil }) else { return equal }
        let values = budgets.map { Double($0 ?? 0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return equal }
        // Past this many frames the floor cannot be honoured at all, so the
        // strip stops pretending and draws equal widths — which is the honest
        // reading of "these are too many to compare".
        guard Double(frames.count) * minFrameShare <= 1 else { return equal }

        // **RESERVE, then share out the remainder — do NOT clamp and
        // renormalise.** Renormalising after a clamp pushes the clamped frame
        // back BELOW its floor (measured: budgets 900 and 1 give 0.107 against
        // a 0.12 floor), so the guarantee the floor exists for is silently
        // broken by the step meant to preserve the total. Here a floored frame
        // keeps exactly `minFrameShare` and everything above the floor divides
        // what is left, so the strip fills its track AND the smallest step is
        // always visible. Iterated, because giving one frame the floor can push
        // the next below it.
        var share = values.map { $0 / total }
        var floored = Array(repeating: false, count: frames.count)
        while true {
            let below = share.indices.filter { !floored[$0] && share[$0] < minFrameShare }
            if below.isEmpty { break }
            for i in below { floored[i] = true; share[i] = minFrameShare }
            let reserved = Double(floored.filter { $0 }.count) * minFrameShare
            let free = share.indices.filter { !floored[$0] }
            let freeTotal = free.reduce(0.0) { $0 + values[$1] }
            guard freeTotal > 0, !free.isEmpty else { return equal }
            for i in free { share[i] = (values[i] / freeTotal) * (1 - reserved) }
        }
        return share
    }

    /// One transaction's row.
    ///
    /// **Order is a ruling**: frames first (what it DID), then spend keys and
    /// snapshots (what it proved), then who paid. It reads left to right as the
    /// sentence the room already speaks, and it is the same order in every
    /// scope that draws it — so the mapping is learned once, which is
    /// `HegotaModeStyle`'s reasoning applied to a shape vocabulary instead of a
    /// hue one.
    static func anatomy(frames: [Frame], keys: Int, roots: Int,
                        sponsored: Bool) -> [Item] {
        var out: [Item] = []
        let widths = shares(frames)
        for (i, frame) in frames.enumerated() {
            out.append(.frame(share: widths[i], failed: frame.succeeded == false))
        }
        out.append(contentsOf: Array(repeating: Item.key, count: max(0, keys)))
        out.append(contentsOf: Array(repeating: Item.root, count: max(0, roots)))
        if sponsored { out.append(.sponsor) }
        return out
    }

    // MARK: - What it was allowed, and what it spent (prd §602)

    /// The whole budget a transaction's steps were given, or nil.
    ///
    /// **ALL-OR-NOTHING, `shares`' own rule.** A sum over the frames that
    /// happened to carry a budget, presented as the transaction's total, is a
    /// denominator invented by the drawing — and it is the WORST kind of
    /// invented number, because "used 21,000 of 30,000" reads as measured on
    /// both sides. One unread budget and there is no total to state.
    ///
    /// A transfer has no frames and therefore no allowance: nil, never zero,
    /// or every plain transfer reads as having spent infinitely more than it
    /// was allowed.
    static func allowance(_ frames: [Frame]) -> UInt64? {
        // No empty-list guard: an empty list runs the loop zero times and
        // leaves `total` at 0, which the zero test below already answers with
        // nil. The guard was written anyway and a mutation SURVIVED against
        // it — two guards for one case means neither can be shown to matter,
        // so the second one goes rather than the test being made cleverer.
        var total: UInt64 = 0
        for frame in frames {
            guard let gas = frame.gasLimit else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(gas)
            // A budget wide enough to overflow 64 bits is not a budget this
            // room can state, and wrapping would print a small honest-looking
            // number for an enormous one.
            if overflow { return nil }
            total = sum
        }
        return total > 0 ? total : nil
    }

    /// How much of the allowance was actually spent, 0…1, or nil when either
    /// half is unknown.
    ///
    /// **CLAMPED AT 1, and the clamp is a real case rather than defensive
    /// habit.** The receipt's total covers the whole transaction while the
    /// allowance is the sum of the FRAME budgets, and nothing guarantees the
    /// first sits inside the second — an intrinsic cost the envelope charges
    /// outside any frame would push the ratio past 1, and a bar drawn past its
    /// own track reads as a broken bar rather than as a big number. The exact
    /// figures are stated in words beside it, which is where an overrun can be
    /// read honestly.
    static func usedShare(gasUsed: UInt64?, frames: [Frame]) -> Double? {
        guard let gasUsed, let allowed = allowance(frames), allowed > 0 else { return nil }
        return min(1, Double(gasUsed) / Double(allowed))
    }

    // MARK: - What this room's transactions ARE (prd §606)

    /// The three things a transaction on this chain can be.
    ///
    /// **THIS IS THE AXIS THE ACTIVITY FIGURE ALWAYS NEEDED.** It drew a column
    /// per transaction whose HEIGHT was the frame count — and nearly every
    /// transaction here runs exactly two frames, so the height axis was
    /// constant and the figure was a row of identical bars at nudged
    /// positions. Reported as "wtf does it even mean", and the answer is that
    /// it meant nothing: it encoded the one number that does not vary.
    ///
    /// What DOES vary, on the demo and on the live chain, is what a
    /// transaction is FOR. Derived from fields the walk already has, so it
    /// costs no request and no new `Thing` field.
    enum Kind: String, Equatable, Sendable, CaseIterable {
        /// It spent one-time keys: a pool spend, the thing this chain is for.
        case poolSpend
        /// It ran steps but spent no key — an ordinary framed call.
        case framed
        /// No frames at all. The faucet pays out this way.
        case transfer
    }

    /// What one transaction is.
    ///
    /// **Keys first, and the order is the ruling.** A pool spend runs frames
    /// too, so testing frames first would file every spend as a framed call
    /// and the pool — the room's entire subject — would never appear in its
    /// own figure.
    static func kind(frames: Int, keys: Int) -> Kind {
        if keys > 0 { return .poolSpend }
        return frames > 0 ? .framed : .transfer
    }

    /// The room's transactions by kind, biggest first, zeroes dropped.
    ///
    /// **A share is only drawn when there is something to share BETWEEN.** One
    /// kind is not a breakdown, it is a sentence with a bar behind it — and on
    /// a young room every transaction is the same kind, so this returns a
    /// single entry and the view states it in words rather than drawing a
    /// full-width bar that says "100%".
    ///
    /// Ties break on the case's own order so the figure cannot reshuffle
    /// between opens over identical data.
    static func kindMix(_ kinds: [Kind]) -> [(kind: Kind, count: Int)] {
        var counts: [Kind: Int] = [:]
        for k in kinds { counts[k, default: 0] += 1 }
        return Kind.allCases.compactMap { k in
            guard let n = counts[k], n > 0 else { return nil }
            return (kind: k, count: n)
        }
        .sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return (Kind.allCases.firstIndex(of: a.kind) ?? 0)
                 < (Kind.allCases.firstIndex(of: b.kind) ?? 0)
        }
    }

    // MARK: - When each transaction landed (prd §610)

    /// **ONE MARK PER TRANSACTION, PLACED ON THE BLOCK AXIS.**
    ///
    /// The Activity scope drew `kindMix`, which is the right figure for a room
    /// whose transactions differ in kind and says nothing at all in a room
    /// where they do not: on the reported device all 60 were plain transfers,
    /// so the mix correctly suppressed its bar and left one legend line —
    /// *60 plain transfers* — under a chassis headline already reading *60
    /// transactions*. The slot restated the headline and left 230pt empty.
    ///
    /// WHEN is the question the room can always answer and no headline states.
    /// This bins the walked block range into equal columns and reports what
    /// landed in each, so the view can draw a mark per transaction (each one
    /// its own door) or, when a column holds more marks than there is height
    /// for, fall back to a bar per column from the same numbers. **One
    /// reading, two renderings** — the fallback can never disagree with the
    /// figure it replaces, because it is computed from the same columns.
    struct Spine: Equatable, Sendable {
        /// One transaction. Ids rather than moves so this file stays
        /// Foundation-only and the harness can build a spine with no
        /// `ModelContext` and no chain.
        struct Mark: Equatable, Sendable {
            var id: String
            /// Whether somebody else paid — the room's `sponsors` reading,
            /// carried per mark rather than as a per-column tally, so the view
            /// knows WHICH one to draw hollow rather than only how many.
            var sponsored: Bool
        }
        struct Column: Equatable, Sendable {
            /// Oldest first, so a column reads the same way the axis does.
            var marks: [Mark] = []
            var count: Int { marks.count }
            var sponsored: Int { marks.filter(\.sponsored).count }
        }
        var columns: [Column]
        var fromBlock: UInt64
        var toBlock: UInt64
        /// **COUNTED, NEVER PLACED.** A move whose read carried no block has no
        /// position on this axis, and giving it one puts a real transaction at
        /// the beginning of time — `Move.block` is Optional for exactly that
        /// reason. The view says how many are missing rather than drawing them
        /// somewhere convenient.
        var undated: Int
        var tallest: Int { columns.map(\.count).max() ?? 0 }
        var placed: Int { columns.reduce(0) { $0 + $1.count } }
        var total: Int { placed + undated }
        var sponsored: Int { columns.reduce(0) { $0 + $1.sponsored } }
    }

    /// One mark per transaction, binned into `columns` equal stretches of the
    /// walked block range.
    ///
    /// Nil when nothing is dated — there is no axis to draw, and an axis with
    /// invented ends is worse than no figure.
    static func spine(_ marks: [(block: UInt64?, sponsored: Bool, id: String)],
                      columns: Int) -> Spine? {
        let n = max(1, columns)
        let dated = marks.compactMap { m -> (UInt64, Bool, String)? in
            guard let b = m.block else { return nil }
            return (b, m.sponsored, m.id)
        }
        let undated = marks.count - dated.count
        guard let from = dated.map(\.0).min(), let to = dated.map(\.0).max() else { return nil }
        var cols = [Spine.Column](repeating: Spine.Column(), count: n)
        // **SORTED FIRST, so a column's contents cannot reshuffle between opens
        // over identical data** — the ranking rule every figure in this room
        // keeps. Block, then id, so the order is total.
        for (block, sponsored, id) in dated.sorted(by: { $0.0 == $1.0 ? $0.2 < $1.2 : $0.0 < $1.0 }) {
            // **THE SPAN CAN BE ZERO**, and it is on any room whose walk saw a
            // single block — the common case on a young address. A naive
            // division there is a crash, and a naive index for the NEWEST block
            // is `n`, one past the end, which drops the newest transaction.
            let span = to - from
            let idx = span == 0 ? 0 : min(n - 1, Int((block - from) * UInt64(n) / span))
            cols[idx].marks.append(Spine.Mark(id: id, sponsored: sponsored))
        }
        return Spine(columns: cols, fromBlock: from, toBlock: to, undated: undated)
    }

    // MARK: - What the room asked the chain for (prd §606)

    /// The two budgets a frame transaction carries, summed across the room.
    ///
    /// **EIP-8141 gives a frame TWO allowances and the room drew neither.** The
    /// Frames scope drew one strip per transaction, weighted by execution
    /// budget — six identical bar-pairs, because most frames here carry the
    /// same 320,000. Reported as "it says twelve steps who cares".
    ///
    /// The reading that is not in the headline is the SPLIT: execution gas is
    /// what a step is allowed to compute, state gas is what it is allowed to
    /// GROW — and on this chain state is the one that varies (measured: most
    /// frames carry 0, a pool spend's second frame carries 550,000). That
    /// split is what a frame transaction IS, and it is one bar rather than N.
    ///
    /// **All-or-nothing per column** (`allowance`'s rule): a sum over the
    /// frames that happened to carry a figure, presented as the room's total,
    /// is a number invented by the drawing. Either side may be nil
    /// independently — a room whose state budgets are all unread still has a
    /// real execution total.
    struct Budgets: Equatable, Sendable {
        var execution: UInt64?
        var state: UInt64?
        /// What the chain actually charged, where the receipts were read.
        /// Nil unless EVERY transaction reported one — a partial sum drawn
        /// against a complete allowance understates the spend and reads as
        /// headroom nobody has.
        var used: UInt64?

        /// Whether there is a bar to draw at all — a room whose every budget
        /// read came back nil, or came back zero, has no proportion to show.
        var hasAnything: Bool { (execution ?? 0) > 0 || (state ?? 0) > 0 }
    }

    static func budgets(frames: [Frame], gasUsed: [UInt64?]) -> Budgets {
        func total(_ values: [UInt64?]) -> UInt64? {
            guard !values.isEmpty else { return nil }
            var sum: UInt64 = 0
            for value in values {
                guard let value else { return nil }
                let (next, overflow) = sum.addingReportingOverflow(value)
                if overflow { return nil }
                sum = next
            }
            // **ZERO IS A READING, NIL IS AN ABSENCE, and conflating them
            // here would be the §515a error on the field that shows it most.**
            // Most frames on this chain carry `stateLimit` 0 — they asked to
            // grow no state, which is a fact — while an unread budget is us
            // not knowing. Both draw no segment; only one of them can be said
            // out loud.
            return sum
        }
        return Budgets(execution: total(frames.map(\.gasLimit)),
                       state: total(frames.map(\.stateLimit)),
                       used: total(gasUsed))
    }

    // **THE TALLY IS GONE (prd §606).** `Tally`, `pipCap` and `pips` fed one
    // figure — three pip columns per address — and a count drawn as N
    // identical shapes is the number restated, not a reading. The Accounts
    // scope draws no figure now; its headline states the count and its rows
    // carry the detail.

    // MARK: - What fits

    /// How many rows fit in the slot.
    ///
    /// **Derived, never a constant** — `DSRoomChassis.figureSlot` is 256 today
    /// and was 166 before §588, and every hand-tuned row count in this app has
    /// been wrong within a release of the box changing. The caller passes the
    /// box it really has and the chrome it really spends.
    ///
    /// Returns at least 1: a slot too small for a single row draws one and
    /// reports the rest as overflow, which is legible, where drawing nothing is
    /// indistinguishable from having nothing.
    static func rowCap(box: Double, rowHeight: Double, spacing: Double,
                       chrome: Double, minimum: Int = 1) -> Int {
        let usable = box - chrome
        guard rowHeight > 0 else { return minimum }
        let n = Int(((usable + spacing) / (rowHeight + spacing)).rounded(.down))
        return max(minimum, n)
    }

    /// How many moves Home lists.
    ///
    /// **A FEW, AND NO LONGER AN ARITHMETIC ANSWER TO A LAYOUT QUESTION (prd
    /// §602).** This used to budget rows against `DSRoomSlot`'s fixed 300pt
    /// box, because Home drew its moves INSIDE the slot — and that box clips.
    /// Two estimates in a row (154, then 232) each left one row that fitted
    /// the arithmetic and was cut mid-line on a device, reported twice with a
    /// screenshot, and the answer taken was to draw NO moves at all whenever
    /// the window figure was present. Which is every time a proof is live —
    /// so the scope's own summary promised "the last few moves" and the scope
    /// showed none, for as long as the room has had anything to say.
    ///
    /// The moves are below the rail now, where `PrivacyDevnetRoomList` draws
    /// every other scope's rows and where nothing clips — the §593d split,
    /// finally applied to the one scope that was exempt from it. So there is
    /// no box to budget against and no third estimate to get wrong.
    ///
    /// **"A few" is three**, unchanged and for its own reason: past three this
    /// stops being a lede and becomes the Activity scope one chip away, which
    /// is two readings of one list.
    static let homeMoveCap = 3

    // MARK: - Keeping marks countable (prd §593d)

    /// Where to draw one mark per value along a track, in points from the left.
    ///
    /// **The problem this solves is real on this chain and not hypothetical.**
    /// The Activity figure placed each transaction at its true fraction of the
    /// block span, which is the honest drawing and collapses here: the pool
    /// address's four transactions sit in two pairs five blocks apart across a
    /// span of ~10,500 blocks, so two of the four marks land 0.05% of the width
    /// from their neighbour and render as one dot. Four transactions drawn as
    /// two, on the figure whose entire job is how many there were.
    ///
    /// **ORDER AND SPAN ARE EXACT; only the crowding is relieved.** Values are
    /// placed at their true fraction, then swept left-to-right pushing any mark
    /// that would overlap its predecessor to exactly one mark-width away, then
    /// swept back from the right so the last mark still ends at the track's end
    /// — so the first and last marks keep their true positions and nothing ever
    /// crosses a neighbour. It is a NUDGE, never a re-ranking: a figure that
    /// reordered marks to fit would be a different and much worse lie than the
    /// one it fixed.
    ///
    /// **A track too narrow for the marks gives up and spreads them evenly**
    /// rather than stacking them all at the right edge, which is what clamping
    /// alone produces. The precision the nudge costs is stated in words beside
    /// the figure (the block range), which is where it belongs — no arrangement
    /// of dots this size was ever going to carry a block number.
    ///
    /// Returns an empty array for an empty input, and a SINGLE value centres,
    /// because a lone dot at the left edge reads as "at the beginning of
    /// something" and there is no something.
    static func spaced(_ values: [UInt64], width: Double, mark: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let usable = max(0, width - mark)
        guard values.count > 1 else { return [usable / 2] }
        guard let lo = values.min(), let hi = values.max() else { return [] }
        let sorted = values.sorted()
        // Every value identical: no span to place them along, so spread them.
        guard hi > lo else {
            return even(count: sorted.count, usable: usable)
        }
        var out = sorted.map { usable * Double($0 - lo) / Double(hi - lo) }
        // Not enough room for one mark each — an even spread is the honest
        // surrender, and it keeps the count readable.
        guard usable >= mark * Double(out.count - 1) else {
            return even(count: out.count, usable: usable)
        }
        for i in 1..<out.count where out[i] - out[i - 1] < mark {
            out[i] = out[i - 1] + mark
        }
        // The right-hand sweep: the forward pass can push the last mark past
        // the end, and a mark drawn off the track is one nobody counts.
        if out[out.count - 1] > usable {
            out[out.count - 1] = usable
            for i in stride(from: out.count - 2, through: 0, by: -1)
            where out[i + 1] - out[i] < mark {
                out[i] = out[i + 1] - mark
            }
        }
        return out.map { min(max($0, 0), usable) }
    }

    private static func even(count: Int, usable: Double) -> [Double] {
        guard count > 1 else { return [usable / 2] }
        let step = usable / Double(count - 1)
        return (0..<count).map { Double($0) * step }
    }

}
