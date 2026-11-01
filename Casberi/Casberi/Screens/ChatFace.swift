import SwiftUI

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

    /// "Ada", out of "Chat with Ada"; a group's own name stands.
    static func name(_ thing: Thing) -> String {
        ThingSheetView.chatName(thing.title)
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

    var body: some View {
        if thing.isLive {
            face
                .frame(width: size, height: size)
                .overlay(alignment: .bottomTrailing) {
                    if badge {
                        BridgeIcon(name: thing.source, size: DS.Face.badge, circular: true)
                            .background(Circle().fill(DS.surfaceSheet).padding(-2))
                            .offset(x: 2, y: 2)
                    }
                }
        }
    }

    @ViewBuilder private var face: some View {
        if let url = ChatFace.url(thing) {
            RemoteThumb(urlString: url, size: size, fallback: thing.source, circular: true)
        } else {
            SenderInitial(sender: ChatFace.name(thing), size: size)
        }
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
