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
        /// How many references collapsed onto this slot. Two proofs against the
        /// same snapshot are one mark, because they are one point on the ring
        /// and drawing them twice paints a diamond nobody can count.
        var count: Int
        /// Whether the view should print this mark's own reading beside it.
        /// Decided HERE rather than in the view, because it is a spacing rule
        /// with a number in it and therefore something a harness can pin.
        var labelled: Bool
        var id: UInt64 { slot }
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
        var bySlot: [UInt64: Int] = [:]
        for r in references { bySlot[r.slot, default: 0] += 1 }

        var out: [Mark] = bySlot.keys.map { slot in
            let ref = PrivacyDevnetRoots.Reference(sourceID: Data(), slot: slot, root: Data())
            switch PrivacyDevnetRoots.standing(of: ref, headSlot: headSlot) {
            case .live(let remaining):
                return Mark(slot: slot,
                            position: Double(remaining) / Double(PrivacyDevnetRoots.windowSlots),
                            agedBy: nil, count: bySlot[slot] ?? 1, labelled: false)
            case .aged(let by):
                return Mark(slot: slot, position: nil, agedBy: by,
                            count: bySlot[slot] ?? 1, labelled: false)
            case .ahead:
                return Mark(slot: slot, position: 1, agedBy: nil,
                            count: bySlot[slot] ?? 1, labelled: false)
            }
        }
        // Newest first, and TOTAL — the slot is unique after the collapse, so
        // there is nothing left to tie on and the track cannot reshuffle
        // between opens.
        out.sort { $0.slot > $1.slot }

        // Labels are spent newest-first, which is the order somebody reads the
        // ring in, and an aged mark always gets one: it is the only mark whose
        // position says nothing, so without its own words it is a hollow shape
        // with no reading at all.
        var spent = 0
        var lastLabelled: Double?
        for i in out.indices {
            guard spent < labelCap else { break }
            guard let p = out[i].position else {
                out[i].labelled = true
                spent += 1
                continue
            }
            if let last = lastLabelled, abs(last - p) < labelGap { continue }
            out[i].labelled = true
            lastLabelled = p
            spent += 1
        }
        return out
    }

    /// The lanes the Roots scope draws — one per source, each its own ring.
    ///
    /// Sources are ordered by `PrivacyDevnetRoots.bySource`, which is already
    /// total, so this adds placement and nothing else.
    struct Lane: Equatable, Sendable, Identifiable {
        var source: Data
        var marks: [Mark]
        var id: String { source.map { String(format: "%02x", $0) }.joined() }
    }

    static func lanes(_ references: [PrivacyDevnetRoots.Reference],
                      headSlot: UInt64, cap: Int) -> (lanes: [Lane], overflow: Int) {
        var bySource: [Data: [PrivacyDevnetRoots.Reference]] = [:]
        for r in references { bySource[r.sourceID, default: []].append(r) }
        let ordered = PrivacyDevnetRoots.bySource(references)
        let all = ordered.map { group in
            Lane(source: group.source,
                 marks: marks(bySource[group.source] ?? [], headSlot: headSlot))
        }
        guard all.count > cap else { return (all, 0) }
        return (Array(all.prefix(cap)), all.count - cap)
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

    // MARK: - The tally

    /// What one address has done, as three counts.
    ///
    /// **Counts, never magnitudes.** The address's BALANCE stays text: test ETH
    /// has no price, so a proportional bar across addresses would rank them by
    /// faucet luck and invite a comparison that means nothing.
    struct Tally: Equatable, Sendable {
        var frames: Int
        var keys: Int
        var roots: Int
    }

    /// How many pips a row draws before it counts instead.
    static let pipCap = 8

    /// A count, as pips plus whatever would not fit.
    ///
    /// Zero returns ONE empty pip rather than nothing, so every drawn row has
    /// the same height and the column reads as a comparison. An address the
    /// chain did not answer for must not reach here at all — the caller draws
    /// its sentence and no tally, because a row of empty pips is a claim that
    /// the address has done nothing (§515a).
    static func pips(_ count: Int) -> (filled: Int, empty: Int, overflow: Int) {
        let n = max(0, count)
        if n == 0 { return (0, 1, 0) }
        if n <= pipCap { return (n, 0, 0) }
        return (pipCap, 0, n - pipCap)
    }

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

    /// How many moves Home shows under the track.
    ///
    /// The Home scope's own summary promises "the line, and the last few moves"
    /// and the room drew none of them, which is the copy-vs-drawing gap §83
    /// bans in its mildest form: nothing is dead, but the room says it will
    /// show you something and does not.
    ///
    /// Two with a track and four without, because the track and its end
    /// captions are the taller object and the sentence above them is the head.
    /// `DSRoomChassis.visualSlot`, spelled here because this file is
    /// Foundation-only and cannot import the design layer. Guarded against
    /// drift in `privacy-selftest.sh`.
    static let DSRoomChassisSlot = 300

    static func homeMoves(hasTrack: Bool, box: Double) -> Int {
        // **FOUR lines, not three — measured on a device, where three clipped.**
        // The estimate was written against the relaunch notice as the worst
        // case, and the ORDINARY rootLive sentence is longer: "A proof here
        // still names a snapshot the chain remembers, for another 4,096 slots."
        // wraps to four lines at `heading22` on an iPhone 17 Pro, which is the
        // commonest state this scope has. Three lines' worth of chrome left one
        // row too many and the last one was cut mid-line by the slab below.
        //
        // A fixed estimate is a FLOOR, not a guarantee: a longer wording, a
        // narrower device or a larger Dynamic Type size can each overrun it
        // again. It is kept because `DSRoomSlot` reserves a fixed visual slot by
        // design, so the alternative is measuring at draw time — and the cost of
        // being wrong here is one row hidden, never one row clipped, as long as
        // the estimate errs HIGH.
        // **WITH A TRACK, HOME DRAWS NO MOVES AT ALL**, and that is a ruling
        // rather than a bigger estimate. Two successive estimates (154, then
        // 232) both left one row that fitted the arithmetic and was CLIPPED
        // mid-line on a device — the third guess would have been another
        // arithmetic answer to a layout question. The track plus a four-line
        // sentence plus the facts row is what the slot holds, and the moves are
        // one chip away in Activity, which is the scope for them.
        //
        // The no-track case keeps its budget: 112 (4 × 28) + s3 + facts 45 + s3
        // is 186, and there the rows are the only content the scope has.
        // **`minimum: 0` — Home is the ONE list allowed to vanish**, and it is
        // what makes this future-proof rather than a number to revisit: when
        // the send panel lands on this scope the caller passes the box it has
        // left, the rows stop fitting, and they disappear on their own. Every
        // other scope draws at least one row, because a scope whose whole
        // content is a list must not render empty.
        let fits = rowCap(box: box, rowHeight: 34, spacing: 6,
                          chrome: hasTrack ? Double(DSRoomChassisSlot) : 186, minimum: 0)
        // **"A few" is three.** The scope's own summary says "the last few
        // moves", and past three this stops being a lede and becomes the
        // Activity scope one chip away — two readings of one list, which is the
        // duplication §555 removed from the Accounts scope next door.
        return min(fits, 3)
    }
}
