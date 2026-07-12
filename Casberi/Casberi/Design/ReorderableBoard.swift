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

/// A single-column board of drag-reorderable cards (prd 58, Goal 1). Long-
/// press lifts a card — the mocked drag state (scale up, slight turn, a
/// shadow lands under it) — then drag reorders live against its neighbors;
/// releasing settles it and hands the new order to `onReorder`. Nobody who
/// never drags sees any of this: with no gesture in flight every card sits
/// exactly where a plain VStack would put it.
struct ReorderableBoard<ID: Hashable, Content: View>: View {
    @Binding var order: [ID]
    @ViewBuilder let content: (ID) -> Content
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
    /// The dragged card's frame AT THE MOMENT it lifted — the fixed origin
    /// `dragTranslation` moves it from. `frames[id]` keeps updating live
    /// (via `.onGeometryChange`) for the SAME view this offset is applied
    /// to, so once a drag starts it already reflects the offset in flight;
    /// reading it again in `reorderIfNeeded` would double the displacement.
    @State private var liftFrame: CGRect?

    var body: some View {
        VStack(spacing: 0) {
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
                    // The actual drag tracker — attached ONLY to the ONE
                    // card currently lifted. Every other card carries zero
                    // extra touch-competing recognizers, which is the part
                    // that actually frees up the scroll.
                    .ifTrue(draggingID == id) {
                        $0.gesture(dragGesture(for: id))
                    }
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
        liftFrame = frames[id]
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
                dragTranslation = drag.translation
                lastTranslation = drag.translation
                lastFingerY = drag.location.y
                // Keep the cumulative auto-scroll current (0 when disabled or
                // un-scrolled) so offset and reorder read one consistent value.
                autoScrollDelta = (scrollProbe?.y ?? 0) - scrollYAtLift
                refreshAutoScroll()
                reorderIfNeeded(id: id, translation: drag.translation)
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
    /// card's live position is `liftFrame` (its frame BEFORE the drag started)
    /// plus the pure translation — not `frames[id]`, which tracks the same
    /// offset view and would double-count it — plus however far the board has
    /// auto-scrolled since lift (frames are in the fixed content space, so a
    /// stationary finger over scrolling content still crosses the right slots).
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

private extension View {
    /// Applies a modifier only when `condition` holds — the standard,
    /// guaranteed-correct way to attach a gesture (or anything else)
    /// conditionally in SwiftUI, since `.gesture` has no built-in "off" state.
    @ViewBuilder
    func ifTrue(_ condition: Bool, _ transform: (Self) -> some View) -> some View {
        if condition { transform(self) } else { self }
    }
}
