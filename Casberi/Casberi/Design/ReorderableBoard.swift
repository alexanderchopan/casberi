import SwiftUI

/// Live scroll state the board reads mid-drag, shared with the enclosing
/// surface as a PLAIN class on purpose: it's written on every scroll frame,
/// and an @Observable/@State here would repaint the whole board each tick.
/// The board only reads `y` while a drag is in flight (reorder math) — no
/// view depends on it, so no observation is wanted.
final class BoardScrollProbe {
    /// The ScrollView's current contentOffset.y (surface keeps it fresh).
    var y: CGFloat = 0
    /// The scroll viewport's global top/bottom — the bands the finger enters
    /// to trigger auto-scroll (surface measures them).
    var viewportTop: CGFloat = 0
    var viewportBottom: CGFloat = 0
}

/// Arranges board modules in the magazine rhythm (prd 58f) — a compact media
/// tile packs 2-up, everything else spans full width — OR a single linear
/// column when a drag is in flight (prd 58h: linearize so the drop target is
/// one unambiguous sequence, re-pack on release). The subviews are a FLAT
/// list, one per module, so a module keeps the SAME view — and its in-flight
/// drag gesture — as it moves between a pair and the column. A row-of-HStacks
/// structure couldn't: pulling a tile out of a pair would restructure the
/// tree and tear the lifted card (and its touch) down mid-drag.
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

/// A board of drag-reorderable module cards (prd 58 Goal 1, prd 58h free
/// drag). Long-press lifts a card — the mocked drag state (scale up, slight
/// turn, a shadow lands under it) — the board linearizes to one full-width
/// column so the drop is unambiguous, drag reorders live against its
/// neighbors, and releasing settles it and re-packs the magazine. Nobody who
/// never drags sees any of this: with no gesture in flight the board is the
/// plain magazine `Layout`.
struct ReorderableBoard<ID: Hashable, Content: View>: View {
    /// The FLAT module order (prd 58h) — a single module is the drag unit, so
    /// a tile paired into a 2-up row can be pulled out and dropped anywhere.
    @Binding var order: [ID]
    @ViewBuilder let content: (ID) -> Content
    /// Whether a module is a compact media tile (packs 2-up, wears the inset)
    /// vs a full-width module. Read fresh each layout so growing/shrinking a
    /// card (which flips its size) re-packs the board.
    var isMagazine: (ID) -> Bool = { _ in false }
    /// Fires once per drag that actually changes the order — the caller
    /// persists it (a drag that snaps back to its start fires nothing).
    let onReorder: ([ID]) -> Void
    /// Shared scroll state so a drag near the viewport edge can auto-scroll a
    /// board taller than the screen — nil keeps the old no-auto-scroll board.
    var scrollProbe: BoardScrollProbe? = nil
    /// Nudges the enclosing ScrollView by `dy` points — the board calls it on
    /// its own loop while a drag sits in an edge band. nil disables auto-scroll.
    var scrollBy: ((CGFloat) -> Void)? = nil

    @State private var draggingID: ID?
    @State private var dragTranslation: CGSize = .zero
    @State private var frames: [ID: CGRect] = [:]
    @State private var orderAtDragStart: [ID] = []
    /// The scroll offset when the drag lifted, and how far the board has
    /// auto-scrolled since (cumulative). Reorder AND the dragged card's offset
    /// both add this, so a stationary finger over auto-scrolling content keeps
    /// the card under the finger and crossing the right slots.
    @State private var scrollYAtLift: CGFloat = 0
    @State private var autoScrollDelta: CGFloat = 0
    /// The last drag sample — the auto-scroll loop re-runs reorder with these
    /// as content slides, since a stationary finger sends no new drag events.
    @State private var lastTranslation: CGSize = .zero
    @State private var lastFingerY: CGFloat = 0
    @State private var autoScrollDir = 0
    @State private var autoScrollTask: Task<Void, Never>?
    /// The dragged card's frame at the moment the DRAG began (not the lift):
    /// lifting linearizes the board, so a paired tile's frame moves out from
    /// under the finger before the first drag sample. Captured on the first
    /// `onChanged`, when the column has settled — the fixed origin
    /// `dragTranslation` moves it from. `frames[id]` keeps updating live for
    /// the SAME view this offset is applied to, so reading it again in
    /// `reorderIfNeeded` would double the displacement.
    @State private var liftFrame: CGRect?
    /// The board relinearizes on lift, so the START frame can't be read until
    /// the first drag sample lands (below). `dragStarted` gates that one-time
    /// capture; `dragBaseline` is the finger's translation at that instant, so
    /// the card's own linear slot — not the paired one — is the zero point.
    @State private var dragStarted = false
    @State private var dragBaseline: CGSize = .zero

    var body: some View {
        MagazineLayout(magazine: order.map(isMagazine),
                       linear: draggingID != nil,
                       hPad: DS.Space.s4, pairGap: DS.Space.s3, rowGap: DS.Space.s4) {
            ForEach(order, id: \.self) { id in
                content(id)
                    .zIndex(draggingID == id ? 1 : 0)
                    .scaleEffect(draggingID == id ? 1.03 : 1)
                    .rotationEffect(.degrees(draggingID == id ? 1.5 : 0))
                    .shadow(color: .black.opacity(draggingID == id ? 0.28 : 0),
                            radius: draggingID == id ? 18 : 0,
                            y: draggingID == id ? 8 : 0)
                    // The lifted card follows the finger (dragTranslation) AND
                    // compensates for any auto-scroll: its base moves with the
                    // scrolling content, so adding autoScrollDelta keeps it
                    // pinned under a stationary finger while the board scrolls.
                    .offset(draggingID == id
                            ? CGSize(width: dragTranslation.width,
                                     height: dragTranslation.height + autoScrollDelta)
                            : .zero)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named("homeBoard"))
                    } action: { frames[id] = $0 }
                    // Detection only — onLongPressGesture is Apple's own
                    // well-behaved recognizer, tuned to coexist with a
                    // ScrollView's pan the way a hand-composed
                    // LongPressGesture.sequenced(before: DragGesture) isn't
                    // (device report, 2026-07-11: scrolling read as
                    // "sticky", every card's own recognizer competing with
                    // the scroll pan for the touch, all the time — not just
                    // the one actually being dragged).
                    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 24) {
                        lift(id)
                    }
                    // The actual drag tracker — attached to EVERY card, all
                    // the time (device report, 2026-07-12: gating this
                    // behind `draggingID == id` meant the recognizer didn't
                    // exist yet when the long-press fired mid-touch, so it
                    // never caught the rest of that same finger-down — the
                    // card visibly lifted but never tracked the drag).
                    // `simultaneousGesture` (not `.gesture`) is what keeps
                    // this from reopening the sticky-scroll bug above: it
                    // coexists with the ScrollView's pan instead of
                    // contesting it, so an idle card's ever-present
                    // recognizer doesn't compete for the touch. The
                    // `guard draggingID == id` inside dragGesture(for:)
                    // keeps it inert everywhere except the lifted card.
                    .simultaneousGesture(dragGesture(for: id))
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
        // A board torn down mid-drag (leaving Home) never sends finger-up —
        // cancel the loop so it can't scroll a gone view.
        .onDisappear { stopAutoScroll() }
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
        orderAtDragStart = order
        // liftFrame is captured on the first drag sample, not here: setting
        // draggingID linearizes the board, so a paired tile's frame is about
        // to move. dragStarted gates that one-shot capture.
        liftFrame = nil
        dragStarted = false
        dragTranslation = .zero
        scrollYAtLift = scrollProbe?.y ?? 0
        autoScrollDelta = 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggingID = id
        }
    }

    private func dragGesture(for id: ID) -> some Gesture {
        // Global space: translation is a DELTA (identical in any space, so the
        // reorder math is unchanged), and `location.y` is the on-SCREEN finger
        // position — what tells us when the finger has entered an edge band and
        // auto-scroll should kick in.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                guard draggingID == id else { return }
                if !dragStarted {
                    dragStarted = true
                    // The board linearized when the card lifted (pairs →
                    // column); its frame settled to a new slot. Capture the
                    // START frame from THAT column, and treat this sample's
                    // translation as the zero point, so the card tracks the
                    // finger from where it now sits.
                    liftFrame = frames[id]
                    dragBaseline = drag.translation
                }
                let t = CGSize(width: drag.translation.width - dragBaseline.width,
                               height: drag.translation.height - dragBaseline.height)
                dragTranslation = t
                lastTranslation = t
                lastFingerY = drag.location.y
                // Keep the cumulative auto-scroll current (0 when disabled or
                // un-scrolled) so offset and reorder read one consistent value.
                autoScrollDelta = (scrollProbe?.y ?? 0) - scrollYAtLift
                refreshAutoScroll()
                reorderIfNeeded(id: id, translation: t)
            }
            .onEnded { _ in
                guard draggingID == id else { return }
                settle(id)
            }
    }

    private func settle(_ id: ID) {
        stopAutoScroll()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            draggingID = nil
            dragTranslation = .zero
        }
        liftFrame = nil
        dragStarted = false
        autoScrollDelta = 0
        if order != orderAtDragStart {
            DSHaptic.tap()
            onReorder(order)
        }
    }

    // MARK: - Edge auto-scroll (a board taller than the screen)

    /// The finger's band (−1 top, +1 bottom, 0 middle) from its screen Y and
    /// the probe's viewport bounds. Off (0) unless auto-scroll is wired.
    private func edgeDirection() -> Int {
        guard let probe = scrollProbe, scrollBy != nil,
              probe.viewportBottom > probe.viewportTop else { return 0 }
        let band: CGFloat = 110
        if lastFingerY < probe.viewportTop + band { return -1 }
        if lastFingerY > probe.viewportBottom - band { return 1 }
        return 0
    }

    /// Starts/stops the nudge loop as the finger enters or leaves an edge band.
    private func refreshAutoScroll() {
        let dir = edgeDirection()
        guard dir != autoScrollDir else { return }
        autoScrollDir = dir
        autoScrollTask?.cancel()
        guard dir != 0 else { autoScrollTask = nil; return }
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled, let id = draggingID {
                scrollBy?(CGFloat(dir) * 22)
                try? await Task.sleep(for: .milliseconds(50))
                // The scroll landed — carry the new offset into the card's
                // position and re-run reorder against the now-scrolled frames
                // (a stationary finger sends no drag events of its own).
                autoScrollDelta = (scrollProbe?.y ?? 0) - scrollYAtLift
                reorderIfNeeded(id: id, translation: lastTranslation)
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollDir = 0
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    /// As the lifted card's center crosses a neighbor's frame, swap it into
    /// that slot — the classic drag-reorder feel (others slide, the lifted
    /// card keeps following the finger via `dragTranslation`). The dragged
    /// card's live position is `liftFrame` (its frame when the drag began, in
    /// the linear column) plus the pure translation — not `frames[id]`, which
    /// tracks the same offset view and would double-count it — plus however
    /// far the board has auto-scrolled since lift (frames are in the fixed
    /// content space, so a stationary finger over scrolling content still
    /// crosses the right slots). During a drag the board is one full-width
    /// column, so a single Y test resolves every slot unambiguously.
    private func reorderIfNeeded(id: ID, translation: CGSize) {
        guard let liftFrame, let fromIndex = order.firstIndex(of: id) else { return }
        let draggedMidY = liftFrame.midY + translation.height + autoScrollDelta
        for (i, otherID) in order.enumerated() where otherID != id {
            guard let otherFrame = frames[otherID], otherFrame.contains(
                CGPoint(x: otherFrame.midX, y: draggedMidY)) else { continue }
            guard i != fromIndex else { continue }
            order.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: i > fromIndex ? i + 1 : i)
            break
        }
    }
}
