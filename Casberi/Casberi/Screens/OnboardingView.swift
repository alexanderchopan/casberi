import SwiftUI

/// Onboarding — three value cards, each one tap, each skippable; skip-all
/// leaves the composer working (brief §7). No permission asks here — grants
/// arrive in context later (S5: value before permission). Bob's words only.
struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0
    @State private var stream = GenStream()

    private struct Card {
        let symbol: String
        let title: String
        let line: String
        /// The card's composition — the engine streams it in (the product
        /// states what it does by showing it, from the first ten seconds).
        var doc: [String] {
            var lines = ["hero = Hero(\"Casberi\", \"\(title)\", \"\(line)\")"]
            var refs = ["hero"]
            if symbol == "square.grid.2x2" {   // card one demos things landing
                lines.append("w = Widget(\"Landing\", null, [r0, r1])")
                lines.append("r0 = Row(\"Trip plan: Lisbon\", \"Chat\", \"ChatGPT\", \"now\")")
                lines.append("r1 = Row(\"Workout plan\", \"Screenshot\", \"Photos\", \"now\")")
                refs.append("w")
            }
            lines.insert("root = Stack([\(refs.joined(separator: ", "))])", at: 0)
            return lines
        }
    }

    private let cards: [Card] = [
        Card(symbol: "square.grid.2x2",
             title: "Add your apps",
             line: "Connect Photos, Calendar, your agents — everything lands in one feed."),
        Card(symbol: "waveform.path.ecg",
             title: "See it all in one feed",
             line: "Everything you're doing, together — no jumping app to app to app."),
        Card(symbol: "arrow.up.right",
             title: "Take action",
             line: "A note becomes a reminder. An agent's ask waits for your tap."),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DS.page.ignoresSafeArea()

            VStack(spacing: DS.Space.s6) {
                Spacer()

                let card = cards[page]
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Image(systemName: card.symbol)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(DS.tint)
                        .padding(.leading, DS.Space.s4)
                    GenRender(id: "root", els: stream.els)
                }
                .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                .padding(.vertical, DS.Space.s4)
                .background(DS.surfaceSheet,
                            in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
                .padding(.horizontal, DS.Space.s4)
                .contentShape(Rectangle())
                .onTapGesture { advance() }   // each card: one tap
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))

                // Page dots — position, not decoration.
                HStack(spacing: DS.Space.s2) {
                    ForEach(cards.indices, id: \.self) { i in
                        Circle()
                            .fill(i == page ? DS.tint : DS.gray300)
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                Button(action: advance) {
                    Text(page == cards.count - 1 ? "Start" : "Next")
                        .dsText(.body17)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .dsGlassProminent(tint: DS.tint, cornerRadius: DS.Radius.pill)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s6)
            }

            // Skip-all leaves the composer working.
            Button("Skip") { onDone() }
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .padding(DS.Space.s4)
        }
        .animation(DS.Motion.standard, value: page)
        .onAppear { stream.stream(cards[page].doc) }
        .onChange(of: page) { _, new in stream.stream(cards[new].doc) }
    }

    private func advance() {
        if page < cards.count - 1 {
            page += 1
        } else {
            onDone()
        }
    }
}
