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
///   1. The agent panel's cached card for the landing seat
///      (`AgentOpenCache.shared.board`) — the room's own figure through the
///      SAME `FigureView` the panel draws, so the peek can never disagree
///      with the tile. Cached is honest here: the panel's own doc calls one
///      arrival behind "a different thing from being wrong".
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

    private var card: AgentPanel.Card? {
        AgentOpenCache.shared.board.cards.first { $0.source == landing }
    }

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
        .onAppear { if card == nil { loadRecent() } }
    }

    /// The three newest things in the landing room, value-extracted in the
    /// same synchronous pass that fetched them — no `Thing` survives this
    /// function, so no liveness guard is ever needed here.
    private func loadRecent() {
        let source = landing
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate<Thing> { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 3
        guard let rows = try? context.fetch(descriptor) else { return }
        recent = rows.map { ($0.id, $0.title, $0.capturedAt) }
    }
}
