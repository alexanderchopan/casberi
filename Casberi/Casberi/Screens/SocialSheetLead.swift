import SwiftUI

/// A POST'S WORDS TAKE THE SIZE THEIR LENGTH EARNS (prd §1651): a short post
/// — a line or two, no break — is set at `heading28` in the semibold, the way
/// the post reads on its own; anything longer stays at `reading17`, the
/// reading rung. One threshold, so the ladder never guesses.
enum PostWords {
    static let displayLimit = 100

    static func isDisplay(_ words: String) -> Bool {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= displayLimit && !trimmed.contains("\n")
    }
}

/// The person who followed you (prd §1651, amends §1397's centred head for a
/// follow): their face on the rows' column, their name, one line — the
/// handle and when they followed — and then their own words about
/// themselves, the bio the profile carried (`summary`, §912). The face opens
/// their profile card.
struct PersonSheetHead: View {
    let thing: Thing
    var onFace: (() -> Void)? = nil

    /// "Uma (@uma) started following you" names them; the handle when not.
    private var name: String {
        if let cut = thing.title.range(of: " (@") {
            let name = String(thing.title[..<cut.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return "@\(handle)"
    }

    private var handle: String { SocialThread.shortHandle(thing.authorHandle ?? "") }

    private var bio: String? {
        let words = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? nil : words
    }

    var body: some View {
        if thing.isLive {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                face
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name)
                        .dsText(.heading24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                        if name != "@\(handle)" {
                            Text(verbatim: "@\(handle) ·")
                                .foregroundStyle(DS.textSecondary)
                                .layoutPriority(-1)
                        }
                        Text("Followed you")
                            .foregroundStyle(DS.textSecondary)
                        Text(FeedScreen.dayWord(thing.capturedAt))
                            .foregroundStyle(DS.headInk)
                    }
                    .dsText(.body17)
                    .lineLimit(1)
                }
                if let bio {
                    Text(ProseLinks.rendered(bio))
                        .dsText(.reading17)
                        .foregroundStyle(DS.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSRoomChassis.leadInset)
        }
    }

    @ViewBuilder private var face: some View {
        let mark = PostSheetBox.face(thing)
        if let onFace {
            Button {
                DSHaptic.tap()
                onFace()
            } label: { mark }
                .buttonStyle(PressSpring())
                .accessibilityLabel(Text("Open profile"))
        } else {
            mark
        }
    }
}
