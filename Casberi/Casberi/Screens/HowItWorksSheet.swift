import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Re-ruled
/// 2026-07-16: the evergreen abstractions ("Keep tabs", "Make it yours") left
/// a real tester not knowing what to do — now it teaches the ONE loop that
/// matters, as four numbered steps: open the store → connect → pin → ask. Still no
/// gesture-by-gesture manual; it names the store's place and glyph because
/// that door is the whole game. Reached from the Settings tile to revisit any
/// time, and wired into the onboarding tail so a new person meets it once.
/// Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // Four numbered steps (ruling 2026-07-16, replacing the four abstract
    // beats): a new person must leave knowing exactly (1) where the store is,
    // (2) that connecting fills the feed by itself, (3) what pinning is FOR,
    // (4) that the composer answers questions about what they've saved.
    // Step 1 wears the REAL Apps-door glyph (TopDoors' square.grid.2x2) so
    // they recognize it in the shell later. Step 3's line closes the loop
    // explicitly — "the feed always has everything" — because "keep in sight"
    // phrasing read as if unpinned things vanish (user, 2026-07-16).
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "1. Open the store",
              line: "Top right of your feed. Apps, people, wallets, stocks — everything you can add lives there."),
        Point(glyph: "checkmark.circle.fill", hue: .green,
              title: "2. Connect things",
              line: "Everything you connect lands in your feed, automatically."),
        Point(glyph: "pin.fill", hue: .pink,
              title: "3. Pin your favorites",
              line: "Home is built from what you pin. The feed always has everything."),
        // Wears the composer FAB's real glyph (a plain plus), same reason
        // step 1 wears the store's grid.
        Point(glyph: "plus", hue: .purple,
              title: "4. Ask",
              line: "Tap the + button and ask questions about anything you've saved."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text("Everything you care about, from every app, in one place that's yours.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .padding(.top, DS.Space.s2)

                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        ForEach(points) { point in
                            HStack(alignment: .top, spacing: DS.Space.s4) {
                                Image(systemName: point.glyph)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(point.hue)
                                    .frame(width: 44, height: 44)
                                    .background(point.hue.opacity(0.16),
                                                in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                                     style: .continuous))
                                VStack(alignment: .leading, spacing: DS.Space.s1) {
                                    Text(point.title)
                                        .dsText(.heading17)
                                        .foregroundStyle(DS.textPrimary)
                                    Text(point.line)
                                        .dsText(.callout15)
                                        .foregroundStyle(DS.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .dsPageBackground()
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(DS.tint)
                }
            }
        }
        .tint(DS.tint)
    }
}
