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
    /// How often an open conversation asks for what is new.
    static let pollSeconds: Double = 4
    let convo: String
    let title: String
    @State private var messages: [LogosObserverWire.ChatMessage]?
    @State private var failed = false
    /// What the name being typed is kept under: a person's address, or the
    /// conversation's own key when nobody in it is known yet.
    @State private var naming: Naming?
    @State private var draft = ""

    private struct Naming: Identifiable {
        let key: String
        let person: Bool
        var id: String { key }
    }

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
            // **Live while open (prd §1368):** every few seconds ask the
            // Observer for what is newer than the newest message held
            // (`since_ms`), and fold it in once. A read that failed is
            // retried whole. Cancelled with the tray.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
                guard !Task.isCancelled else { return }
                guard let held = messages else {
                    messages = await LogosObserver.shared.messages(in: convo)
                    failed = messages == nil
                    continue
                }
                guard let fresh = await LogosObserver.shared.messages(
                    in: convo, sinceMs: LogosObserverWire.since(held)) else { continue }
                let merged = LogosObserverWire.merge(held, fresh)
                if merged.count != held.count { messages = merged }
            }
        }
        .alert(naming?.person == false ? String(localized: "Name this conversation")
                                       : String(localized: "Name this person"),
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }),
               presenting: naming) { pick in
            TextField(String(localized: "Name"), text: $draft)
            Button(String(localized: "Save")) { names.set(draft, for: pick.key) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { pick in
            Text(pick.person
                 ? String(localized: "Only on this phone. Their address changes when they restart Basecamp.")
                 : String(localized: "Only on this phone. Once they write, a name you give them takes over."))
        }
    }

    /// A direct conversation's person — the address under a given name, and
    /// the verb that names them; otherwise a group's people, and the verb
    /// that names the conversation itself, so no conversation is left with
    /// a name nobody can change.
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
                nameButton(given == nil ? String(localized: "Name this person") : String(localized: "Rename")) {
                    draft = given ?? ""
                    naming = Naming(key: peer, person: true)
                }
            }
            .padding(.bottom, DS.Space.s2)
        } else if let known {
            let given = names.name(known.nameKey)
            HStack(spacing: DS.Space.s2) {
                if let people = known.people(names: names.name) {
                    Text(people)
                        .dsText(.subhead12)
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer(minLength: 0)
                nameButton(given == nil ? String(localized: "Name this conversation") : String(localized: "Rename")) {
                    draft = given ?? ""
                    naming = Naming(key: known.nameKey, person: false)
                }
            }
            .padding(.bottom, DS.Space.s2)
        }
    }

    private func nameButton(_ words: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .frame(minHeight: 44)
        }
        .buttonStyle(RowPress())
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
            // A message that arrives while the tray is open slides into view.
            .onChange(of: lines.last?.id) { _, newest in
                guard let newest else { return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(newest, anchor: .bottom) }
            }
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
