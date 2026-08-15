import SwiftUI
import SwiftData

/// The long-press peek on a source chip (2026-08-14, prd §384): the room's
/// head floats up WITHOUT navigating — press to wonder, release to stay,
/// tap through to commit. The strip is the app's whole navigation, so this is
/// the one place "what's in there?" can be answered for free.
///
/// Rides `.contextMenu(menuItems:preview:)` — the `AppsScreen.PeekPreview`
/// pattern, with both of its recorded lessons kept: the menu is non-empty on
/// purpose (an empty menu can suppress the preview entirely), and the whole
/// modifier is gated by `enabled` so "All" — whose room is the entire feed —
/// never grows a peek that would have to preview everything.
///
/// WHAT THE PREVIEW SHOWS, in order of what the app already knows:
///   1. The room's own figure, composed on demand by `RoomFigure` — the same
///      function the agent panel used before §386p deleted it, so the peek
///      still shows what the room itself leads with.
///   2. Otherwise the room's three newest things by title — real content,
///      fetched at peek time (the preview builder is lazy), value-extracted
///      immediately so no `Thing` is ever HELD by this view (the liveness
///      rule's cheapest possible form: don't store the model at all).
///
/// The label resolves to its landing seat through `CategoryFold.landing`,
/// exactly as `MainSurface.go(to:)` resolves a tap — a folded "Markets" chip
/// previews the room it would OPEN, not an aggregate that doesn't exist.
struct ChipPeekModifier: ViewModifier {
    let label: String
    let venues: [String]
    let enabled: Bool
    let onOpen: () -> Void

    private var landing: String? {
        if CategoryFold.isCategory(label) {
            return CategoryFold.landing(category: label, present: venues)
        }
        return label
    }

    func body(content: Content) -> some View {
        if enabled, let landing {
            content.contextMenu {
                Button {
                    onOpen()
                } label: {
                    Label(String(localized: "Open \(landing)"), systemImage: "arrow.right")
                }
            } preview: {
                ChipPeek(label: label, landing: landing)
            }
        } else {
            content
        }
    }
}

/// The peek card itself. ~300pt wide; the system sizes the preview window to
/// fit. Not interactive — the system's preview layer swallows touches, so
/// nothing here may look pressable (`allowsHitTesting(false)` on the figure
/// well, the AppsScreen precedent).
private struct ChipPeek: View {
    let label: String
    let landing: String

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Titles + times only — value-extracted at fetch, never held `Thing`s.
    @State private var recent: [(id: UUID, title: String, when: Date)] = []

    /// Composed ON DEMAND for this one room (prd §386p). It used to read the
    /// agent panel's cached board, and the panel is gone — but the per-room
    /// function it used survives as `RoomFigure`, so the peek composes exactly
    /// the figure it needs instead of reading one of forty somebody else
    /// built. Cheaper than the cache it replaces, and it can never be stale.
    @State private var card: AgentPanel.Card?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: landing, size: DS.Face.row, circular: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(landing)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    // A folded chip names both halves — the word you pressed
                    // and the seat it opens — so the peek explains the fold
                    // instead of silently swapping subjects.
                    if label != landing {
                        Text(label)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let card {
                if !card.title.isEmpty {
                    Text(card.title)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
                ZStack {
                    FigureView(figure: card.figure,
                               slot: AgentPanel.fit(card.figure) == .bandOnly ? .band : .tall,
                               hue: AgentPanelGrid.panelHue(for: card.source),
                               rising: card.rising,
                               reduceMotion: reduceMotion)
                        .padding(DS.Space.s2)
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(DS.surfaceWell,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
                .allowsHitTesting(false)
                if let reading = card.reading {
                    Text(reading)
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
            } else if !recent.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(recent, id: \.id) { row in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                            Text(row.title.isEmpty ? String(localized: "Untitled") : row.title)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(row.when.formatted(.relative(presentation: .named)))
                                .dsText(.label12)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                }
            } else {
                // A room with nothing landed yet is a true state, not a broken
                // peek — say so rather than showing an empty frame.
                Text(String(localized: "Nothing here yet."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(DS.Space.s4)
        .frame(width: 300, alignment: .leading)
        .background(DS.surfaceSheet)
        .onAppear { loadFigure() }
    }

    /// The room's own figure, then its newest rows as the fallback. Both read
    /// the same bounded fetch, so a peek is one query however it draws.
    private func loadFigure() {
        let source = landing
        var fd = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        fd.fetchLimit = 400
        let rows = (try? context.fetch(fd))?.filter { $0.isLive } ?? []
        card = RoomFigure.roomFigure(source: source, things: rows)
        if card == nil {
            // Value-extracted immediately — no `Thing` survives this call.
            recent = rows.prefix(3).map { ($0.id, $0.title, $0.capturedAt) }
        }
    }

}
