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
                    .simultaneousGesture(liftAndDrag(for: id))
            }
        }
        .coordinateSpace(name: "homeBoard")
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: order)
    }

    /// Long-press to lift, sequenced into a drag — the standard "hold then
    /// carry" gesture. `.simultaneousGesture` (not `.gesture`) so it never
    /// steals a plain tap from a card's own buttons/rows underneath; a
    /// quick tap ends before the long-press threshold and this recognizer's
    /// first phase just never succeeds.
    private func liftAndDrag(for id: ID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(coordinateSpace: .named("homeBoard")))
            .onChanged { phase in
                switch phase {
                case .second(true, let drag):
                    if draggingID != id {
                        DSHaptic.selection()
                        orderAtDragStart = order
                        liftFrame = frames[id]
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draggingID = id
                        }
                    }
                    guard let drag else { return }
                    dragTranslation = drag.translation
                    reorderIfNeeded(id: id, translation: drag.translation)
                default:
                    break
                }
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
