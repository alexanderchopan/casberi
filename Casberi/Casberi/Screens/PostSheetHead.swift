import SwiftUI

/// A post's sheet leads with the PERSON (prd §884) — the post's form of the
/// article head (§882), so a post and an article open the same way: who, the
/// day in the divider's pink, then the words at the size the sheet's ladder
/// gives them.
///
/// The eyebrow it replaces put a 20pt face and "@handle · in /design · 2h ago"
/// in one tertiary line, so the person who said it was the smallest thing on
/// the screen. Here the face is `DS.Face.shelf`, the handle is the name, and
/// the line under it says where (the network, and the channel when there is
/// one). The handle stands as the name because a post does not store a
/// display name; the row and the room cover name the person the same way.
///
/// **The day is the divider's word** (`FeedScreen.dayWord`, §882), never an
/// age, and it is the head's only brand ink (`day-divider-audit.py` check 5).
/// The face stays the door to the person's profile card where the network has
/// one (`onFace`).
struct PostSheetHead: View {
    let thing: Thing
    /// The face's door to the profile card — nil where the source has none.
    var onFace: (() -> Void)? = nil

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            face
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Text(verbatim: handle)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s2)
                    Text(FeedScreen.dayWord(thing.capturedAt))
                        .dsText(.label12)
                        .foregroundStyle(DS.brandInk)
                        .lineLimit(1)
                }
                Text(verbatim: whereLine)
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handle: String {
        SocialThread.shortHandle(thing.authorHandle ?? "")
    }

    /// "Farcaster · in /design" — the network, and why the post is here when
    /// there is a reason worth stating (`SocialThread.contextPhrase`, the
    /// eyebrow's own vocabulary, so the two can never disagree).
    private var whereLine: String {
        [thing.source, SocialThread.contextPhrase(for: thing)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    @ViewBuilder private var face: some View {
        if let onFace {
            Button {
                DSHaptic.tap()
                onFace()
            } label: {
                faceMark
            }
            .buttonStyle(.plain)
            .dsHover()
            .accessibilityLabel(Text("Open profile"))
            .dsTooltip(String(localized: "Open profile"))
        } else {
            faceMark
        }
    }

    @ViewBuilder private var faceMark: some View {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: DS.Face.shelf,
                        fallback: thing.source, circular: true)
                .coinFlip(trigger: thing.id)
        } else {
            BridgeIcon(name: thing.source, size: DS.Face.shelf, circular: true)
                .coinFlip(trigger: thing.id)
        }
    }
}
