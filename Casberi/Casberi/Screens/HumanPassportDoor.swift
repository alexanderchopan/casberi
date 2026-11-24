import SwiftUI

/// **HUMAN PASSPORT, WHEREVER ITS SCORE IS NAMED (prd §1962, user: "telling a
/// user they need a passport score without giving them the link seems bad").**
/// One link for every door to it, so a move of Passport's site is one change
/// (`live-integrations.sh` asks it nightly).
enum HumanPassport {
    static let site = URL(string: "https://app.passport.xyz")!
}

/// The door: "Human Passport ›" in Aztec's ink, a row under the line that
/// names the score. Never "Raise your score": a score of 20 is rarely quick.
struct HumanPassportDoor: View {
    let act: () -> Void

    var body: some View {
        Button {
            DSHaptic.selection()
            act()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: "Human Passport").dsText(.heading17).foregroundStyle(DS.aztecInk)
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right").dsGlyph(.caption, weight: .semibold)
                    .foregroundStyle(DS.aztecInk)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DSFeed.headHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
        .accessibilityHint(Text("Opens Human Passport"))
    }
}
