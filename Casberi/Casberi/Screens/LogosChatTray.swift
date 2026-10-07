import SwiftUI

/// One Logos conversation (prd §1155): its messages, oldest first, read live
/// from the paired Observer when the tray rises and never kept — they leave
/// with the tray. Read-only: there is no field and no send, because Casberi
/// never writes to Logos chat.
///
/// A sender is shown by its short chat address. chat_module 0.3.0 gives a
/// person a new address at every Basecamp launch, so an address is not a
/// name; profile names (λAccounts) come later.
struct LogosChatTray: View {
    let convo: String
    let title: String
    @State private var messages: [LogosObserverWire.ChatMessage]?
    @State private var failed = false

    var body: some View {
        DSTray(title: title, height: 640, detents: [.height(640), .large]) {
            Group {
                if let messages, !messages.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: DS.Space.s3) {
                                ForEach(messages) { message in
                                    bubble(message).id(message.id)
                                }
                            }
                        }
                        .onAppear { if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                } else if messages != nil || failed {
                    DSFootnote(prose: failed
                               ? String(localized: "Couldn't read this conversation from your Observer.")
                               : String(localized: "No messages in this conversation yet."))
                } else {
                    DSSpinner()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            messages = await LogosObserver.shared.messages(in: convo)
            failed = messages == nil
        }
    }

    private func bubble(_ m: LogosObserverWire.ChatMessage) -> some View {
        VStack(alignment: m.fromSelf ? .trailing : .leading, spacing: 2) {
            Text(m.content)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text([m.fromSelf ? String(localized: "You") : m.sender.map(LogosWire.short),
                  m.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())]
                    .compactMap { $0 }.joined(separator: " · "))
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: m.fromSelf ? .trailing : .leading)
    }
}
