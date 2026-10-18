import SwiftUI

/// **THE PANE'S HEADER ROW (prd §1404).** The verbs a thing open in the pane
/// published (`ShellChrome.paneVerbs`), as 28pt pills on one line: the
/// thing's own act in the pick's ink, the rest grey (§1385), each a `Chip`
/// so the pane's toolbar and the app's one choice pill are one drawing.
/// Mail's and Notes' shape: the acts beside the reading, never thumb discs
/// floating over it, and no chevron at the top (§752; Escape or the open
/// row again returns to the box, §1403).
struct PaneVerbBar: View {
    @Environment(ShellChrome.self) private var chrome

    var body: some View {
        if !chrome.paneVerbs.isEmpty {
            HStack(spacing: DS.Space.s2) {
                Spacer(minLength: 0)
                ForEach(chrome.paneVerbs) { verb in
                    Button {
                        DSHaptic.tap()
                        verb.run()
                    } label: {
                        Chip(text: verb.label, glyph: verb.glyph, hit: 28,
                             ink: verb.primary ? DS.pickInk : DS.textSecondary)
                    }
                    .buttonStyle(PressSpring())
                    .accessibilityLabel(Text(verbatim: verb.label))
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s3)
            .padding(.bottom, DS.Space.s1)
            .animation(DS.Motion.standard, value: chrome.paneVerbs.map(\.id))
        }
    }
}
