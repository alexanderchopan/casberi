import SwiftUI

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

    @State private var draggingID: ID?
    @State private var dragTranslation: CGSize = .zero
    @State private var frames: [ID: CGRect] = [:]
    @State private var orderAtDragStart: [ID] = []
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
                    .offset(draggingID == id ? dragTranslation : .zero)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            draggingID = id
        }
    }

    private func dragGesture(for id: ID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("homeBoard"))
            .onChanged { drag in
                guard draggingID == id else { return }
                dragTranslation = drag.translation
                reorderIfNeeded(id: id, translation: drag.translation)
            }
            .onEnded { _ in
                guard draggingID == id else { return }
                settle(id)
            }
    }

    private func settle(_ id: ID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            draggingID = nil
            dragTranslation = .zero
        }
        liftFrame = nil
        if order != orderAtDragStart {
            DSHaptic.tap()
            onReorder(order)
        }
    }

    /// As the lifted card's center crosses a neighbor's frame, swap it into
    /// that slot — the classic drag-reorder feel (others slide, the lifted
    /// card keeps following the finger via `dragTranslation`). The dragged
    /// card's live position is `liftFrame` (its frame BEFORE the drag
    /// started) plus the pure translation — not `frames[id]`, which tracks
    /// the same offset view and would double-count it.
    private func reorderIfNeeded(id: ID, translation: CGSize) {
        guard let liftFrame, let fromIndex = order.firstIndex(of: id) else { return }
        let draggedMidY = liftFrame.midY + translation.height
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
