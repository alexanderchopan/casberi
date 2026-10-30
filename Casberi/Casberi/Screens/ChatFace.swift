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
    /// A conversation with people, not an AI chat or a note.
    static func isPersonChat(_ thing: Thing) -> Bool {
        thing.kind == .chat && SocialRoom.facts(for: thing.source) != nil
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
