import SwiftUI

/// **WATCHING ANOTHER ACCOUNT IS A SHEET NOW, NOT AN UNFOLD (prd §517,
/// 2026-08-29).**
///
/// Reported: *"when you click find another account it opens inline and all
/// different font sizes. presumably the watched account would be at top.
/// this whole thing is gross."*
///
/// The unfold was the direct cause of both halves of that. `VibenetDiscovery
/// Section` expanded IN PLACE, between the paste field and the roster — so
/// eight strangers' addresses appeared ABOVE the one account you actually
/// watch, and the page ended up carrying two type systems at once: the
/// field's own label rung, the discovery heading, each row's address and
/// its "created 9 hours ago", the roster card's heading tier, and the verb
/// run's 12pt chips. Five sizes, three positions, one screen.
///
/// A sheet fixes the ordering problem by construction — your accounts can
/// never be pushed down by a lookup that is no longer on the screen — and
/// it fixes the type problem by giving the lookup a surface of its own,
/// where it is the subject and can be set at one scale.
///
/// **It is deliberately the SAME two controls, moved.** `VibenetWatchField`
/// and `VibenetDiscoverySection` are unchanged and still shared with
/// `VibenetScreen` (§465's own reason: copied, the two screens would answer
/// the same paste with two different sentences within a release). What
/// changed is where they are and what surrounds them.
///
/// **Ink, and no cards** (user ruling, 2026-08-29). `dsInk()` rather than a
/// sheet surface, and nothing here is boxed: the rows sit on the ground and
/// the rhythm separates them. The one filled shape is the address field,
/// which is a control.
struct VibenetWatchSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called after an address was really added. The book re-reads the chain
    /// and, since the roster it returns to is the reason this sheet exists,
    /// closes.
    var onWatched: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        VibenetWatchField(onWatched: {
                            onWatched()
                            dismiss()
                        })
                        // ONE sentence, at one size, and it is here rather
                        // than on the book for a reason worth keeping: it
                        // answers a question you asked by opening this. On
                        // the book it was fine print nobody had asked for,
                        // competing with the roster.
                        Text("Paste an address, or pick one that was just created below. Watching is free and reads only.")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VibenetDiscoverySection(onWatched: {
                        onWatched()
                        dismiss()
                    })
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s4)
                .padding(.bottom, DS.Space.s6)
            }
            .scrollContentBackground(.hidden)
            .dsAdaptiveContentWidth()
            .dsScreenTitle("Watch an account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .dsInk()
    }
}
