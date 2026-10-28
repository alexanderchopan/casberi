import SwiftUI
import SwiftData

/// Your chats, on Telegram's page (prd §1575): the sign-in while signed out,
/// then the X and Instagram pages' switch (§1244) — a decision, so a switch,
/// off until you make it — and the way out. Followed channels and the export
/// stay where they were; this is the page's third door.
///
/// The sign-in itself is the page's one presentation, raised by `onSignIn`
/// through `AccountPage.sheet`, so this block carries no `.sheet` of its own.
struct TelegramMessagesBlock: View {
    var onSignIn: () -> Void
    @Environment(\.modelContext) private var modelContext
    @AppStorage(TelegramClient.signedInKey) private var signedIn = false
    @AppStorage(LiveMessages.Seat.telegram.defaultsKey) private var readsMessages = false
    @State private var syncing = false
    @State private var result: BridgeProof?

    var body: some View {
        // A build made without the app id cannot sign in; it draws no door
        // rather than one that fails (§83).
        if TelegramClient.configured {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if signedIn {
                    DSToggleRow(title: Text("Read your messages"),
                                detail: Text("Each conversation lands as one thing. Off keeps what came."),
                                isOn: $readsMessages)
                        .onChange(of: readsMessages) { _, on in
                            if on { Task { await sync() } }
                        }
                    DSDoorRow(icon: "rectangle.portrait.and.arrow.right",
                              label: "Sign out of Telegram", role: .destructive) {
                        Task {
                            await TelegramClient.shared.signOut()
                            readsMessages = false
                            result = nil
                        }
                    }
                } else {
                    DSSlabButton(tile: .signIn, title: String(localized: "Sign in"),
                                 detail: String(localized: "Your chats"),
                                 systemImage: "bubble.left.and.bubble.right",
                                 action: onSignIn)
                }
                BridgeSyncStatusRows(syncing: syncing,
                                     syncingLine: String(localized: "Reading your chats…"),
                                     proof: result)
            }
            .task { if signedIn, readsMessages { await sync() } }
        }
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let landed = await TelegramMessagesRead.refresh(context: modelContext)
        result = switch landed {
        case nil: .failed(String(localized: "Couldn't reach Telegram"))
        case 0?: .upToDate
        case let n?: .landed(n)
        }
    }
}
