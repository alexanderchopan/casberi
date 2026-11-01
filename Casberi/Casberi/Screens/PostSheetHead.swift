import SwiftUI

/// A post's sheet leads with the POST (prd §1636, amends §1397 for a post):
/// the person on one line at the rows' column, then the words, the pictures,
/// the quote, how it landed, and only then the tiles. The centred head put
/// the tiles between who said it and what they said, so the post was the
/// fourth thing on the screen it was opened to read.
///
/// The face is `DS.Face.seat`, the name is the author's own (else the handle,
/// `PostSheetBox.title`), and the line under it is the handle and when — the
/// day in the divider's word (`FeedScreen.dayWord`, §882) with the clock
/// beside it, the head's only `DS.headInk` (`day-divider-audit.py` check 5).
/// The network is the face's mark, never a word in the line. The face is the
/// door to the person's profile card where the network has one (`onFace`).
struct PostSheetHead: View {
    let thing: Thing
    let name: String
    /// The face's door to the profile card — nil where the source has none.
    var onFace: (() -> Void)? = nil

    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            face
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                    if !handle.isEmpty, handle != name {
                        Text(verbatim: "@\(handle) ·")
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Text(FeedScreen.dayWord(thing.capturedAt))
                        .dsText(.body17)
                        .foregroundStyle(DS.headInk)
                    Text(verbatim: thing.capturedAt.formatted(date: .omitted, time: .shortened))
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DSRoomChassis.leadInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var handle: String {
        // A Telegram channel's handle is in its ref; `authorHandle` holds the
        // channel's display name (prd §1637).
        if TelegramPost.isChannelPost(thing) { return TelegramPost.handle(thing) ?? "" }
        return SocialThread.shortHandle(thing.authorHandle ?? "")
    }

    @ViewBuilder private var face: some View {
        if let onFace {
            Button {
                DSHaptic.tap()
                onFace()
            } label: {
                faceMark
            }
            .buttonStyle(PressSpring())
            .dsHover()
            .accessibilityLabel(Text("Open profile"))
            .dsTooltip(String(localized: "Open profile"))
        } else {
            faceMark
        }
    }

    @ViewBuilder private var faceMark: some View {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
            RemoteThumb(urlString: avatar, size: DS.Face.seat,
                        fallback: thing.source, circular: true)
        } else {
            BridgeIcon(name: thing.source, size: DS.Face.seat, circular: true)
        }
    }
}
