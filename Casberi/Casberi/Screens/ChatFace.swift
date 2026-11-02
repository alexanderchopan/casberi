import SwiftUI
import UIKit

/// WHO A CHAT IS WITH, as Messages draws it (prd §1615, user: "the chats i
/// think we could make the design nicer"). A conversation on a social network
/// (`SocialRoom`'s sources, kind `.chat`) leads with the person, or the
/// group's initial, never the network's logo: every chat in a room wore the
/// same Telegram mark and read "Chat with Ada". The row and the sheet's head
/// both ask here, so the two cannot disagree about who it is.
///
/// Liveness: every member takes a `Thing` the caller has already guarded.
enum ChatFace {
    /// A conversation with people, not an AI chat or a note. A post or a
    /// notice is `.chat` too on X and Bluesky, but it carries its words in
    /// `postText` or why it's here in `socialContext`, which no conversation
    /// sets: read as a chat, a followed post's "last message" was its link.
    /// A post with no words (a picture alone) sets neither, so a content
    /// that is one bare link is a post too: a transcript never is.
    static func isPersonChat(_ thing: Thing) -> Bool {
        thing.kind == .chat && SocialRoom.facts(for: thing.source) != nil
            && (thing.postText ?? "").isEmpty && (thing.socialContext ?? "").isEmpty
            && !isBareLink(thing.content)
    }

    /// One URL and nothing else: a post's permalink, never a transcript.
    static func isBareLink(_ content: String) -> Bool {
        let s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("http") && !s.contains(where: \.isWhitespace)
    }

    /// "Ada", out of "Chat with Ada" or "Messages with Ada"; "Climbing", out
    /// of "Messages in Climbing" (prd §1660).
    static func name(_ thing: Thing) -> String {
        ThingSheetView.chatName(thing.title)
    }

    /// The chat's last message when it is a photo (prd §1660): whether it
    /// was yours, who sent it in a group, and its caption. Read off the
    /// line's words, never the stored bytes; the row asks `StoredPixels`
    /// whether the picture itself is here.
    struct LastPhoto: Equatable {
        var mine: Bool
        var sender: String?
        var caption: String?
        /// What stands under the picture: "Bo: the view", "Bo", "the view".
        var words: String? {
            let parts = [sender, caption].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ": ")
        }
    }

    static func lastPhoto(_ thing: Thing) -> LastPhoto? {
        guard let last = thing.content.split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }),
              let message = PersonChatBubbles.messages(last).last,
              message.media == String(localized: "Photo") else { return nil }
        return LastPhoto(mine: message.mine, sender: message.name,
                         caption: PersonChatBubbles.media(message.words)?.caption)
    }

    /// The face the chat carries: the one its read stamped, else a live
    /// Telegram one-to-one's public photo by username. Nil draws the initial.
    static func url(_ thing: Thing) -> String? {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty { return avatar }
        if thing.sourceRef?.hasPrefix(TelegramMessages.refPrefix) == true,
           let handle = thing.authorHandle, !handle.isEmpty, !handle.contains(" ") {
            return TelegramMessages.face(handle: handle)
        }
        return nil
    }

    /// The conversation's last message, as Messages' list shows it: "You: "
    /// on yours, the sender's name in a group, the words alone from the
    /// person the chat is with.
    static func lastLine(_ thing: Thing) -> String? {
        let messages = thing.content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = messages.last else { return nil }
        let said = ChatBubbles.speaker(of: last)
        guard let name = said.name else { return last }
        if ChatBubbles.isMine(name) { return String(localized: "You: \(said.words)") }
        let others = Set(messages.compactMap { line -> String? in
            guard let n = ChatBubbles.speaker(of: line).name, !ChatBubbles.isMine(n) else { return nil }
            return n
        })
        return others.count > 1 ? last : said.words
    }

    /// The last message as the Feed's bubble holds it (prd §1642): your own
    /// words alone in the tint, theirs as `lastLine` gives them, so a group
    /// keeps who said it inside the bubble. Nil when the transcript is empty.
    static func lastMessage(_ thing: Thing) -> (text: String, mine: Bool)? {
        guard let last = thing.content.split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .last(where: { !$0.isEmpty }) else { return nil }
        let said = ChatBubbles.speaker(of: last)
        if let name = said.name, ChatBubbles.isMine(name) { return (said.words, true) }
        return (lastLine(thing) ?? last, false)
    }

    /// **THE FEED SAYS WHAT WAS SAID (prd §1641, user, 2026-11-01: "the
    /// most important part of social is seeing the message", "rn for
    /// telegram messages it just says the generic thing").** The Feed's one
    /// line for a chat with people: who sent the last message and what —
    /// "Mia: Perfect. I'll bring the rope.", "You: Yes, 10am at the wall.",
    /// "Jo in Climbing crew: Friday at 7 then?" — never "Chat with Mia".
    /// Nil when the transcript is empty, and the title stands.
    static func sentence(_ thing: Thing) -> String? {
        let messages = thing.content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = messages.last else { return nil }
        let chat = name(thing)
        let said = ChatBubbles.speaker(of: last)
        guard let speaker = said.name else { return String(localized: "\(chat): \(last)") }
        let who = ChatBubbles.isMine(speaker) ? String(localized: "You") : speaker
        let others = Set(messages.compactMap { line -> String? in
            guard let n = ChatBubbles.speaker(of: line).name, !ChatBubbles.isMine(n) else { return nil }
            return n
        })
        return others.count > 1
            ? String(localized: "\(who) in \(chat): \(said.words)")
            : String(localized: "\(who): \(said.words)")
    }
}

/// The chat's face: the person's picture, else the name's initial, with the
/// network's mark as a badge on the sheet's head (iOS's communication
/// notification), none on a row, whose room already says it.
struct ChatFaceMark: View {
    let thing: Thing
    var size: CGFloat = DS.Face.rowCircle
    var badge = false

    @Environment(\.dsGround) private var ground

    var body: some View {
        if thing.isLive {
            face
                .frame(width: size, height: size)
                .overlay(alignment: .bottomTrailing) {
                    if badge {
                        BridgeIcon(name: thing.source, size: DS.Face.badge, circular: true)
                            .background(Circle().fill(ground).padding(-2))
                            .offset(x: 2, y: 2)
                    }
                }
        }
    }

    @ViewBuilder private var face: some View {
        if let url = ChatFace.url(thing) {
            RemoteThumb(urlString: url, size: size, fallback: thing.source, circular: true)
        } else {
            ChatStoredFace(thing: thing, size: size)
        }
    }
}

/// A face kept as bytes (`Thing.authorAvatarData`, prd §1660): a private
/// Telegram group's photo. The initial draws until the bytes are decoded,
/// off the main thread and once per row, and stays when there are none.
struct ChatStoredFace: View {
    let thing: Thing
    let size: CGFloat
    @State private var image: UIImage?

    init(thing: Thing, size: CGFloat) {
        self.thing = thing
        self.size = size
        _image = State(initialValue: thing.isLive ? ChatFaceBytes.cached(thing.id) : nil)
    }

    /// Liveness guard (build 188): this leaf re-evaluates on the model's
    /// own observation, so the guard is here.
    var body: some View {
        if thing.isLive {
            SenderInitial(sender: ChatFace.name(thing), size: size)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .transition(.opacity)
                    }
                }
                // A new message is when a read re-stamps the face, so the
                // newest line's time is the key; the bytes are read here,
                // never in the body (an external-storage file).
                .task(id: thing.capturedAt) { await load() }
        }
    }

    private func load() async {
        guard thing.isLive else { return }
        guard let data = thing.authorAvatarData else {
            image = nil
            return
        }
        let id = thing.id
        let decoded = await ChatFaceBytes.image(id, data: data)
        guard decoded !== image else { return }
        withAnimation(DS.Motion.standard) { image = decoded }
    }
}

/// The decoded faces, by row, each remembered with its byte count so a new
/// face replaces the old. A handful of chats, 160px each.
@MainActor
enum ChatFaceBytes {
    private static var memo: [UUID: (count: Int, image: UIImage)] = [:]

    static func cached(_ id: UUID) -> UIImage? { memo[id]?.image }

    static func image(_ id: UUID, data: Data) async -> UIImage? {
        if let hit = memo[id], hit.count == data.count { return hit.image }
        let decoded = await Task.detached(priority: .utility) {
            UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
        }.value
        if let decoded { memo[id] = (data.count, decoded) }
        return decoded
    }
}

/// A photo as a chat bubble (prd §1660): the last message's picture in the
/// bubble's shape and fill, with who sent it and its caption under the
/// picture inside the same bubble. The Feed's row stands it on the rows'
/// text edge (§1642); the sheet puts yours on the trailing edge.
struct ChatPhotoBubble: View {
    let thing: Thing
    /// The stored picture's pixel size (`StoredPixels.probe`).
    let pixels: CGSize
    let photo: ChatFace.LastPhoto
    /// The sheet names a group's sender over the bubble, so its bubble
    /// carries the caption alone; the Feed's row has no name over it.
    var namesSender = true
    var onTextEdge = true

    static let width: CGFloat = 200

    /// Liveness guard (build 188): this leaf re-evaluates on the model's
    /// own observation, so the guard is here.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        let width = Self.width
        let aspect = pixels.width > 0 ? pixels.height / pixels.width : 1
        let height = min(max(width * aspect, 120), 260)
        VStack(alignment: .leading, spacing: 0) {
            StoredPicture(thing, size: pixels) { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: width, height: height)
            .clipped()
            if let words = namesSender ? photo.words : photo.caption {
                Text(words)
                    .dsText(.body17)
                    .foregroundStyle(photo.mine ? Color.white : DS.textPrimary)
                    .lineLimit(onTextEdge ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .frame(width: width, alignment: .leading)
            }
        }
        .background(DSChatBubble.fill(fromSelf: photo.mine))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: photo.mine && !onTextEdge ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(photo.words.map { String(localized: "Photo: \($0)") }
                                 ?? String(localized: "Photo")))
    }
}

/// A chat's way on (prd §1635): one glass capsule over the sheet's foot,
/// "Reply in Telegram", which opens the conversation in the app it lives in.
/// Casberi reads chats and never writes one, so the reply is the network's.
struct ChatReplyPill: View {
    let network: String
    let action: () -> Void

    var body: some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "paperplane").dsGlyph(.subhead)
                Text("Reply in \(network)").dsText(.heading17)
            }
            .foregroundStyle(DS.textPrimary)
            .padding(.horizontal, DS.Space.s6)
            .frame(minHeight: 48)
            .dsGlass(cornerRadius: 24)
        }
        .buttonStyle(PressSpring())
        .dsHover()
        .frame(maxWidth: .infinity)
        .padding(.bottom, DS.Space.s3)
    }
}
