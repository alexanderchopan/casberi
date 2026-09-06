import SwiftUI

/// "What you can do" (2026-07-11 as "How it works") — the one persistent
/// place that says what the app is, reached from the Settings row of the same
/// name.
///
/// **It is a REFERENCE PAGE now, not onboarding (2026-09-05).** From 2026-07-16
/// this sheet WAS the first screen — the rain of every connectable app, the
/// sentence, and one door forward that went through four rewrites ("Browse
/// the catalog" → "Try it" → the fork → "Try a demo" beside "Connect my
/// apps"). All of that moved to `IntroCover`, which rides on the demo itself:
/// a fresh install pours the furnished feed at once and the greeting is a
/// translucent slab over it that any tap or drag lifts. There is no CTA
/// anywhere in the first minute, so there is nothing for this page to fire.
///
/// What stays here is what somebody revisiting from Settings needs: the
/// sentence, and Done. No rain — a second rain would be a fake first time —
/// and no mark, which on this route was rendered at opacity 0 for a month
/// (its landing was keyed to the onboarding tail) and only ever cost 150pt
/// of empty space.
///
/// Naming (user, 2026-07-16): user-facing copy never says "store" for this
/// surface — it's "the catalog" ("store" reads as a place you pay). "What you
/// can do", not "How it works" (user, 2026-08-29), one name used here and on
/// the Settings row that opens it. Text literals auto-localize.
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("Everything you need, in one place.")
                            .dsText(.heading34)
                            .foregroundStyle(DS.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        // Says what "one feed, or many" never did (user: "isn't
                        // clear that you can view as one feed, or separately as
                        // many"). The agent is named in the same breath rather
                        // than taking a line of its own.
                        Text("Read it all together, or one app at a time. Ask your agents about any of it.")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.s2)
                    }
                    .padding(.top, DS.Space.s2)
                    .opacity(arrived || reduceMotion ? 1 : 0)
                    .offset(y: arrived || reduceMotion ? 0 : 10)
                    .animation(reduceMotion ? nil : DS.Motion.standard.delay(0.1), value: arrived)
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(DS.tint)
                }
            }
        }
        .tint(DS.tint)
        .onAppear { arrived = true }
    }
}
