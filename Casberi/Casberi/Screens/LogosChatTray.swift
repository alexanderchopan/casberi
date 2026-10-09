import SwiftUI

/// One Logos conversation (prd §1155, drawn as Messages since §1213): its
/// messages, oldest first, read live from the paired Observer when the tray
/// rises and never kept — they leave with the tray. Read-only: there is no
/// field and no send, because Casberi never writes to Logos chat, and the
/// foot says where to reply.
///
/// A person is their short chat address until you name them here
/// (`LogosChatNames`). chat_module 0.3.0 gives a person a new address at
/// every Basecamp launch, so a name holds until they restart Basecamp.
struct LogosChatTray: View {
    let convo: String
    let title: String
    @State private var messages: [LogosObserverWire.ChatMessage]?
    @State private var failed = false
    @State private var naming = false
    @State private var draft = ""

    private var names: LogosChatNames { LogosChatNames.shared }

    /// The conversation as the list knows it, with what these messages say.
    private var conversation: LogosObserverWire.Conversation? {
        guard case .ready(let convos) = LogosObserver.shared.chat,
              let found = convos.first(where: { $0.id == convo }) else { return nil }
        return messages.map { found.enriched(with: $0) } ?? found
    }

    var body: some View {
        let known = conversation
        DSTray(title: known?.title(names: names.name) ?? title, height: 640,
               detents: [.height(640), .large]) {
            VStack(spacing: 0) {
                header(known)
                Group {
                    if let messages, !messages.isEmpty {
                        thread(messages, group: known.map { !$0.direct } ?? false)
                    } else if messages != nil || failed {
                        DSFootnote(prose: failed
                                   ? String(localized: "Couldn't read this conversation from your Observer.")
                                   : String(localized: "No messages in this conversation yet."))
                    } else {
                        DSSpinner()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text("Reply in Logos Basecamp on your computer")
                    .dsText(.subhead12)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Space.s3)
            }
        }
        .task {
            messages = await LogosObserver.shared.messages(in: convo)
            failed = messages == nil
        }
        .alert(String(localized: "Name this person"), isPresented: $naming) {
            TextField(String(localized: "Name"), text: $draft)
            Button(String(localized: "Save")) {
                if let peer = known?.peer { names.set(draft, for: peer) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Only on this phone. Their address changes when they restart Basecamp.")
        }
    }

    /// A direct conversation's person — the address under a given name, and
    /// the verb that names them; a group's people.
    @ViewBuilder private func header(_ known: LogosObserverWire.Conversation?) -> some View {
        if let known, known.direct, let peer = known.peer {
            let given = names.name(peer)
            HStack(spacing: DS.Space.s2) {
                if given != nil {
                    Text(verbatim: LogosWire.short(peer))
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                        .monospaced()
                }
                Spacer(minLength: 0)
                Button {
                    draft = given ?? ""
                    naming = true
                } label: {
                    Text(given == nil ? String(localized: "Name this person") : String(localized: "Rename"))
                        .dsText(.body17)
                        .foregroundStyle(DS.brandInk)
                        .frame(minHeight: 44)
                }
                .buttonStyle(RowPress())
            }
            .padding(.bottom, DS.Space.s2)
        } else if let known, let people = known.people(names: names.name) {
            Text(people)
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s2)
        }
    }

    private func thread(_ messages: [LogosObserverWire.ChatMessage], group: Bool) -> some View {
        let lines = LogosObserverWire.lines(messages, group: group, names: names.name)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s1) {
                    ForEach(lines) { line in
                        row(line).id(line.id)
                    }
                }
            }
            .onAppear { if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }

    @ViewBuilder private func row(_ line: LogosObserverWire.ChatLine) -> some View {
        switch line {
        case .time(let date):
            Text(Self.when(date))
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.top, DS.Space.s3)
                .padding(.bottom, DS.Space.s1)
        case .author(let name, _):
            Text(name)
                .dsText(.subhead12)
                .foregroundStyle(DS.textSecondary)
                .padding(.leading, DS.Space.s3)
                .padding(.top, DS.Space.s2)
        case .message(let m):
            VStack(alignment: .trailing, spacing: 2) {
                DSChatBubble(text: m.content, fromSelf: m.fromSelf,
                             faded: m.fromSelf && (m.delivery == .pending || m.delivery == .failed))
                // Only what the Observer said: no word for a message it
                // reported nothing about (prd §1213).
                if m.fromSelf, let word = Self.deliveryWord(m.delivery) {
                    Text(word)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.attentionInk)
                }
            }
        }
    }

    static func deliveryWord(_ delivery: LogosObserverWire.ChatMessage.Delivery?) -> String? {
        switch delivery {
        case .pending: return String(localized: "Not delivered yet")
        case .failed:  return String(localized: "Not delivered")
        case .sent, nil: return nil
        }
    }

    /// "Today 9:12", "Yesterday 18:40", "Oct 3 9:12".
    static func when(_ date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today \(time)") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday \(time)") }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
