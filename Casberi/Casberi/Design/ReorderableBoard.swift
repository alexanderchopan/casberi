import SwiftUI

/// Arranges board modules in the magazine rhythm (prd 58f) — a compact media
/// tile packs 2-up, everything else spans full width — OR a single linear
/// column when a drag is in flight (prd 58h: linearize so the drop target is
/// one unambiguous sequence, re-pack on release). The subviews are a FLAT
/// list, one per module, so a module keeps the SAME view — and its in-flight
/// drag — as it moves between a pair and the column. A row-of-HStacks
/// structure couldn't: pulling a tile out of a pair would restructure the
/// tree and tear the lifted card down mid-drag.
struct MagazineLayout: Layout {
    /// Per subview, parallel to the board's `order`: true if this module is a
    /// compact media tile that packs 2-up and wears the magazine inset; false
    /// spans full width and brings its own padding (structural modules, a
    /// LARGE media module, social posts).
    var magazine: [Bool]
    /// A drag is in flight — ignore pairing, stack every module full-width.
    var linear: Bool
    var hPad: CGFloat
    var pairGap: CGFloat
    var rowGap: CGFloat

    /// Groups subview indices into rows: a non-magazine module (or any module
    /// while linear) takes its own full-width row; consecutive magazine tiles
    /// pack two to a row.
    private func rows(count: Int) -> [[Int]] {
        var result: [[Int]] = []
        var i = 0
        while i < count {
            if isMag(i), !linear {
                if i + 1 < count, isMag(i + 1) { result.append([i, i + 1]); i += 2 }
                else { result.append([i]); i += 1 }
            } else {
                result.append([i]); i += 1
            }
        }
        return result
    }

    private func isMag(_ i: Int) -> Bool { i < magazine.count && magazine[i] }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var y: CGFloat = 0
        for row in rows(count: subviews.count) {
            let m = metrics(row, width: width, subviews: subviews)
            y += m.topGap + m.height
        }
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var y = bounds.minY
        for row in rows(count: subviews.count) {
            let m = metrics(row, width: width, subviews: subviews)
            y += m.topGap
            if row.count == 2 {
                let tileW = pairTileWidth(width)
                // Both tiles fill the row's height (the taller of the pair), so
                // a short small tile sits flush beside a taller one.
                subviews[row[0]].place(
                    at: CGPoint(x: bounds.minX + hPad, y: y),
                    anchor: .topLeading, proposal: .init(width: tileW, height: m.height))
                subviews[row[1]].place(
                    at: CGPoint(x: bounds.minX + hPad + tileW + pairGap, y: y),
                    anchor: .topLeading, proposal: .init(width: tileW, height: m.height))
            } else {
                let i = row[0]
                let inset = isMag(i) ? hPad : 0
                subviews[i].place(
                    at: CGPoint(x: bounds.minX + inset, y: y),
                    anchor: .topLeading, proposal: .init(width: width - 2 * inset, height: nil))
            }
            y += m.height
        }
    }

    /// A row's height and the gap above it. Magazine rows carry the s4 top
    /// inset boardRow used to add; full-width modules bring their own top
    /// padding, so they get none here (matching prd 58f's spacing exactly).
    private func metrics(_ row: [Int], width: CGFloat, subviews: Subviews)
        -> (height: CGFloat, topGap: CGFloat) {
        if row.count == 2 {
            let tileW = pairTileWidth(width)
            let h = max(subviews[row[0]].sizeThatFits(.init(width: tileW, height: nil)).height,
                        subviews[row[1]].sizeThatFits(.init(width: tileW, height: nil)).height)
            return (h, rowGap)
        }
        let i = row[0]
        let inset = isMag(i) ? hPad : 0
        let h = subviews[i].sizeThatFits(.init(width: width - 2 * inset, height: nil)).height
        return (h, isMag(i) ? rowGap : 0)
    }

    /// Half-width for a 2-up pair, floored at 1pt: SwiftUI probes layouts with
    /// tiny/unspecified proposals (the default width is ~10pt), and a raw
    /// `(width - 44)/2` goes negative there — placing tiles with garbage,
    /// overlapping frames for a frame (review 2026-07-12).
    private func pairTileWidth(_ width: CGFloat) -> CGFloat {
        max(1, (width - 2 * hPad - pairGap) / 2)
    }
}

/// The per-frame drag values the LIFTED card renders from (2026-07-12 perf
/// pass) — @Observable, so mutating them repaints only the one view that
/// reads them (the dragged card), never the board that merely owns the
/// reference. Parking translation here instead of in the board's @State is
/// what stops a ~120 Hz drag from re-evaluating the whole board body — and
/// every module's view value — on every finger sample.
@Observable final class DragMotion {
    var translation: CGSize = .zero
    var autoScrollDelta: CGFloat = 0
    /// How far the dragged card's LAYOUT slot has moved since lift (each
    /// live reorder re-slots it). Subtracted from the rendered offset so the
    /// card stays glued under the finger instead of leading it by one slot
    /// per swap — the layout moves the slot, the offset compensates.
    var slotShift: CGFloat = 0
}

/// The card frames only the hit-test and reorder MATH read — never a view
/// body. A plain class: writing them on every layout tick repaints nothing,
/// which is exactly what the reorder loop wants.
final class DragScratch<ID: Hashable> {
    var frames: [ID: CGRect] = [:]
}

/// A board of drag-reorderable module cards (prd 58 Goal 1, prd 58h free
/// drag). Long-press lifts a card — the mocked drag state (scale up, slight
/// turn, a shadow lands under it) — the board linearizes to one full-width
/// column so the drop is unambiguous, drag reorders live against its
/// neighbors, and releasing settles it and re-packs the magazine. Nobody who
/// never drags sees any of this: with no gesture in flight the board is the
/// plain magazine `Layout`.
///
/// Input rides `BoardDragDriver` — ONE UIKit long-press on the enclosing
/// UIScrollView (2026-07-13), not per-card SwiftUI gestures. See the driver's
/// header for why: guaranteed cancellation (no leaked drags, no locked
/// board), and the scroll pan dies for the duration of a drag (the card gets
/// every point of finger travel).
struct ReorderableBoard<ID: Hashable, Content: View>: View {
    /// The FLAT module order (prd 58h) — a single module is the drag unit, so
    /// a tile paired into a 2-up row can be pulled out and dropped anywhere.
    @Binding var order: [ID]
    /// Edit mode (2026-07-12): the Home Screen model. A long-press enters it —
    /// every tile jiggles and STAYS jiggling, and a light press grabs any tile
    /// to drag without the full hold, so you rearrange freely until you tap
    /// Done. The persistent wobble is the discoverability tell: it's how a
    /// person learns the board is rearrangeable at all. The owner (Home) reads
    /// this to show the Done button; the board sets it true on the first lift.
    @Binding var editing: Bool
    @ViewBuilder let content: (ID) -> Content
    /// Whether a module is a compact media tile (packs 2-up, wears the inset)
    /// vs a full-width module. Read fresh each layout so growing/shrinking a
    /// card (which flips its size) re-packs the board.
    var isMagazine: (ID) -> Bool = { _ in false }
    /// Fires once per drag that actually changes the order — the caller
    /// persists it (a drag that snaps back to its start fires nothing).
    let onReorder: ([ID]) -> Void

    @State private var draggingID: ID?
    @State private var orderAtDragStart: [ID] = []
    /// The per-frame drag values the lifted card renders from — held OUT of
    /// board @State on purpose (perf pass): only the dragged BoardCard reads
    /// `motion`, so a per-frame translation repaints that one card, not the
    /// whole board. See DragMotion.
    @State private var motion = DragMotion()
    /// The card frames the hit-test and reorder math read — a plain holder,
    /// so per-layout writes repaint nothing.
    @State private var scratch = DragScratch<ID>()
    var body: some View {
        MagazineLayout(magazine: order.map(isMagazine),
                       linear: draggingID != nil,
                       hPad: DS.Space.s4, pairGap: DS.Space.s3, rowGap: DS.Space.s6) {
            ForEach(order, id: \.self) { id in
                // The module + its lifted-state transforms + the finger-tracking
                // offset live in BoardCard, which reads `motion` ONLY while it's
                // the lifted card — so a per-frame translation repaints just
                // that one card. Everything that must NOT rebuild per frame
                // (zIndex, the frame probe, a11y) stays out here on the board
                // body, which re-evaluates only on a discrete lift / settle /
                // reorder — never on a plain finger move.
                BoardCard(dragged: draggingID == id,
                          editing: editing,
                          phase: id.hashValue & 3,
                          motion: motion,
                          content: content(id))
                    .zIndex(draggingID == id ? 1 : 0)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("homeBoard"))
                    } action: { scratch.frames[id] = $0 }
                    // Drag is a pointer gesture VoiceOver can't perform, so
                    // reordering was unreachable without sight. Custom actions
                    // (in the rotor) move a card one slot either way — the
                    // same reorder the drag makes, persisted the same way.
                    .accessibilityElement(children: .contain)
                    .accessibilityAction(named: Text("Move up")) { move(id, by: -1) }
                    .accessibilityAction(named: Text("Move down")) { move(id, by: 1) }
            }
        }
        .coordinateSpace(name: "homeBoard")
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: order)
        // The input layer: one UIKit long-press on the enclosing scroll view.
        // The background view fills the layout's bounds, so its coordinate
        // space IS "homeBoard" — card hit-testing reads `scratch.frames`
        // directly. The driver guarantees exactly one end/cancel per lift.
        .background {
            BoardDragDriver<ID>(
                editing: editing,
                cardAt: { point in
                    scratch.frames.first(where: { $0.value.contains(point) })?.key
                },
                onLift: { lift($0) },
                onMove: { translation, autoScrollDelta, finger in
                    guard let id = draggingID else { return }
                    motion.translation = translation
                    motion.autoScrollDelta = autoScrollDelta
                    reorderIfNeeded(id: id, fingerY: finger.y)
                },
                onEnd: {
                    if let id = draggingID { settle(id) }
                })
        }
        // A board torn down mid-drag (leaving Home) never sends finger-up —
        // drop edit mode so returning to Home isn't stuck jiggling with no
        // Done in reach. (The driver's dismantle re-enables the scroll pan.)
        .onDisappear { editing = false }
    }

    /// Moves a card one slot in `order` and persists — the accessible path to
    /// the same reorder the drag performs. Silently no-ops at the ends.
    private func move(_ id: ID, by delta: Int) {
        guard let from = order.firstIndex(of: id) else { return }
        let to = from + delta
        guard order.indices.contains(to) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            order.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
        DSHaptic.selection()
        onReorder(order)
    }

    private func lift(_ id: ID) {
        guard draggingID != id else { return }
        DSHaptic.selection()
        // The first lift arms edit mode; it STAYS armed after this drag
        // settles (persistent — only Done, or leaving Home, clears it), so
        // the board keeps jiggling and the next tile takes only a light press.
        if !editing { editing = true }
        orderAtDragStart = order
        motion.translation = .zero
        motion.autoScrollDelta = 0
        motion.slotShift = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggingID = id
        }
    }

    private func settle(_ id: ID) {
        // Clearing draggingID inside the animation flips this card to its
        // resting state (offset → .zero) and springs it home; the card stops
        // observing `motion` the same instant, so resetting motion after is
        // just housekeeping for the next lift.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            draggingID = nil
        }
        motion.translation = .zero
        motion.autoScrollDelta = 0
        motion.slotShift = 0
        // The drop lands — a soft tap every time a tile settles, reordered or
        // not (2026-07-12: the board only buzzed on a real move, so putting a
        // card back where it started felt dead).
        DSHaptic.tap()
        if order != orderAtDragStart {
            onReorder(order)
        }
    }

    /// As the FINGER enters a neighbor's frame, swap the dragged card into
    /// that slot — the classic drag-reorder feel (others slide, the lifted
    /// card keeps following the finger). The finger arrives in BOARD space
    /// from the driver, so scroll and linearization are already baked in —
    /// no captured frames, no timing assumptions about when the linearize
    /// layout lands (the old liftFrame capture raced it). Keying reorder to
    /// the finger, not the card's center, is also how the system Home Screen
    /// reads a drag. During a drag the board is one full-width column, so a
    /// single Y test resolves every slot unambiguously.
    private func reorderIfNeeded(id: ID, fingerY: CGFloat) {
        guard let fromIndex = order.firstIndex(of: id) else { return }
        for (i, otherID) in order.enumerated() where otherID != id {
            guard let otherFrame = scratch.frames[otherID], otherFrame.contains(
                CGPoint(x: otherFrame.midX, y: fingerY)) else { continue }
            guard i != fromIndex else { continue }
            // The swap moves the dragged card's LAYOUT slot; fold the
            // displacement into slotShift so the rendered offset keeps the
            // card under the finger (see DragMotion.slotShift). The
            // neighbor's midY approximates the new slot's — exact for
            // same-height cards, bounded by their height difference
            // otherwise, and trued up at the drop either way.
            if let currentMid = scratch.frames[id]?.midY {
                motion.slotShift += otherFrame.midY - currentMid
            }
            order.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: i > fromIndex ? i + 1 : i)
            // A tick per slot crossed, not just at lift/drop — the native
            // Home Screen icon-drag feel (2026-07-12): a live drag that never
            // ticks reads as unresponsive even when the reorder itself is
            // working, because the only feedback was at the start and end.
            DSHaptic.selection()
            break
        }
    }
}

/// One board card: the module plus its lifted-state transforms. Split out of
/// the board's ForEach (2026-07-12 perf pass) so a per-frame drag offset
/// repaints ONLY the card being dragged. Two things make that hold:
///  • it reads `motion` — the per-frame translation — only inside the
///    `dragged` branch, so an idle card never observes it and is never
///    re-rendered as the finger moves; and
///  • it takes the already-built `content` VALUE (not a rebuilding closure),
///    so even the dragged card diffs its module subtree away — only the
///    CoreAnimation transform (offset/scale/rotate) changes each frame, on
///    the render thread, not a SwiftUI body re-evaluation.
private struct BoardCard<Content: View>: View {
    let dragged: Bool
    /// A drag is in flight SOMEWHERE on the board — the other tiles wobble
    /// (the Home Screen "you're rearranging now" tell). The lifted card
    /// itself doesn't jiggle; it wears the lift transform instead.
    let editing: Bool
    /// A stable 0–3 bucket (from the id's hash) that desyncs this card's
    /// jiggle period, so the board shimmers rather than pulsing in lockstep.
    let phase: Int
    let motion: DragMotion
    let content: Content

    var body: some View {
        ZStack {
            // The slot a lifted card leaves shows a recessed well wearing the
            // mark — the empty place reads "the card lands here" while it's in
            // the air (2026-07-12). The well stays in the slot; only `content`
            // below rides the finger, so this costs no per-frame work. `dragged`
            // is a discrete lift/settle flag, so the ZStack rebuilds twice a
            // drag, never per move.
            if dragged {
                DropWell()
            }
            content
                // A firmer "pick up" pop than the old 1.03 — the lift spring
                // (dampingFraction 0.7) lends a little overshoot, so the tile
                // feels grabbed off the board and floated higher (shadow too).
                .scaleEffect(dragged ? 1.05 : 1)
                .rotationEffect(.degrees(dragged ? 1.5 : 0))
                .shadow(color: .black.opacity(dragged ? 0.30 : 0),
                        radius: dragged ? 22 : 0,
                        y: dragged ? 10 : 0)
                // A separate rotation layer from the lift tilt above, so the two
                // never fight. Runs on the render thread (a repeatForever CA
                // animation), so a jiggling board costs no SwiftUI body work —
                // it starts on the one re-render when `editing` flips at lift and
                // stops on the one at settle, nothing in between.
                .modifier(JiggleEffect(active: editing && !dragged, phase: phase))
                // The lifted card follows the finger AND compensates for any
                // auto-scroll (its base moves with the scrolling content, so
                // adding autoScrollDelta keeps it pinned under a stationary
                // finger) AND for live reorders (each swap moves its layout
                // slot; subtracting slotShift keeps the card glued to the
                // finger instead of leading it by a slot per swap). Reading
                // `motion` here — only when `dragged` — is what scopes the
                // per-frame repaint to this one card. The offset is ALWAYS
                // applied (value .zero when idle), never conditionally
                // added/removed, so the settle springs it home instead of
                // snapping.
                .offset(dragged
                        ? CGSize(width: motion.translation.width,
                                 height: motion.translation.height
                                         + motion.autoScrollDelta
                                         - motion.slotShift)
                        : .zero)
        }
    }
}

/// The faint slot a lifted card leaves behind — a recessed well wearing the
/// Casberi mark, so the empty place says "the card lands here" while it's in
/// the air. One berry, in the target, earned — not a decorative field behind
/// the board (§8: decoration banned; the mark carries meaning here).
private struct DropWell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
            .fill(DS.fillFaint)
            .overlay {
                CasberiBerryShape()
                    .fill(DS.textTertiary)
                    .frame(width: 30, height: 30)
                    .opacity(0.16)
            }
    }
}

/// The Home Screen jiggle — a subtle endless rotation wobble while the board
/// is being rearranged. A single state flip into a `repeatForever(autoreverses:)`
/// animation gives continuous oscillation between the two angle endpoints with
/// no per-frame driving from us; CoreAnimation owns it on the render thread.
/// Off under Reduce Motion, and it springs flat (not snaps) when editing ends.
private struct JiggleEffect: ViewModifier {
    let active: Bool
    let phase: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swung = false

    private var on: Bool { active && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (swung ? 0.9 : -0.9) : 0), anchor: .center)
            .animation(on
                       ? .easeInOut(duration: 0.15 + Double(phase) * 0.012)
                            .repeatForever(autoreverses: true)
                       : .spring(response: 0.28, dampingFraction: 0.72),
                       value: swung)
            .onChange(of: on) { _, now in swung = now }
            .onAppear { if on { swung = true } }
    }
}
