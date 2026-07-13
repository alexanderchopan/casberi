import SwiftUI

/// "How it works" (2026-07-11) — the one persistent place that explains the
/// model, for a new person after the retiring coach lines are gone. Deliberately
/// EVERGREEN: principles in Casberi's voice, not a gesture-by-gesture manual
/// (the exact taps change; three did in one day). Reached from the Settings
/// tile to revisit any time, and wired into the onboarding tail so a new person
/// meets it once. Text literals auto-localize (LocalizedStringKey).
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Point: Identifiable {
        let glyph: String
        let hue: Color
        let title: LocalizedStringKey
        let line: LocalizedStringKey
        var id: String { glyph }
    }

    // The four beats mirror the docs' four feature sections (2026-07-13):
    // Just connect → Keep tabs → Take action → Make it yours. One line each —
    // the essence of the section, never the full card list.
    private let points: [Point] = [
        Point(glyph: "square.grid.2x2.fill", hue: .blue,
              title: "Just connect",
              line: "No account. Your apps, in one feed."),
        Point(glyph: "pin.fill", hue: .pink,
              title: "Keep tabs",
              line: "Pin, share, tag, and act on your things."),
        Point(glyph: "sparkles", hue: .purple,
              title: "Take action",
              line: "Ask, organize, or jump to a tool."),
        Point(glyph: "slider.horizontal.3", hue: .orange,
              title: "Make it yours",
              line: "Your avatar, background, language, data."),
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
