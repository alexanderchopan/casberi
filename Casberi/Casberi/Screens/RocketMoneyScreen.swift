import SwiftUI
import SwiftData

/// Rocket Money's setup — `AcornsScreen`'s shape exactly, which took one
/// reversal to get to.
///
/// Rocket Money's GraphQL schema is closed, so the seat has no queries until it
/// has watched the real app make some. The first cut surfaced that: it showed a
/// "Teach it your pages" button asking the person to go click through
/// Subscriptions and Recurring so the seat could listen. **That was an
/// implementation detail wearing a control** (user: "wtf is 'teach it your
/// pages' who talks like that"), and the fix was not better words — it was to
/// stop asking. `RocketMoneyLoginWebView` walks those pages itself the moment
/// the sign-in takes, so this page has nothing to explain and no extra state to
/// be in.
///
/// Read-only, structurally: 114 of this app's operations are mutations over
/// linked bank accounts, and a non-read is refused twice in Swift — at capture
/// and again at replay (`RocketMoneyOperations.isRead`).
struct RocketMoneyScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var cancelled = false
    @State private var showLogin = false
    @State private var harvestedThisCover = false
    @State private var reading = RocketMoneyIngest.lastReading

    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Rocket Money", seatID: "rocketmoney", source: "Rocket Money",
            state: AccountPageState.of(name: "Rocket Money", seatID: "rocketmoney",
                                       connected: RocketMoneyAuth.connected, store: store),
            mode: .signIn,
            teardown: { RocketMoneyAuth.clear() },
            sheet: $sheet,
            act: {
                if RocketMoneyAuth.connected { connectedBlock } else { connectBlock }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .fullScreenCover(isPresented: $showLogin,
                         onDismiss: {
                             cancelled = !harvestedThisCover
                             if RocketMoneyAuth.connected { Task { await sync() } }
                         }) {
            RocketMoneyLoginWebView(onCaptured: harvested)
        }
        .onAppear {
            reading = RocketMoneyIngest.lastReading
            if RocketMoneyAuth.connected { Task { await sync() } }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        if connecting {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text("Reading your Rocket Money…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s1)
        } else {
            DSSlabButton(title: "Connect Rocket Money",
                         systemImage: "person.badge.key",
                         action: { DSHaptic.tap(); cancelled = false; result = nil
                                   harvestedThisCover = false; showLogin = true })
            if cancelled {
                Text("Sign-in cancelled — nothing was connected.")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Reading your Rocket Money…"),
                             proof: result)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.tint)
            Text("Signed in")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }

        // No door here, and no instruction: the sign-in view walks the account's
        // own pages itself once the sign-in takes (`RocketMoneyLoginWebView`).
        // A seat asking somebody to go click four pages so it can watch was an
        // implementation detail wearing a control (user: "wtf is 'teach it
        // your pages' who talks like that"). If a walk somehow taught it
        // nothing, the remedy is the ordinary one every seat has — connect
        // again — and the status row below says so in those words.
        BridgeSyncStatusRows(syncing: syncing || connecting,
                             syncingLine: String(localized: "Reading your Rocket Money…"),
                             proof: result,
                             retry: { Task { await sync() } })
        unreadableBlock
        DSSlabNote(text: "Your subscriptions and recurring bills land in your feed.",
                   plain: true)
    }

    @ViewBuilder private var unreadableBlock: some View {
        if !reading.unreadable.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Rocket Money answered, but Casberi didn't recognise the shape.")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                ForEach(reading.unreadable.keys.sorted(), id: \.self) { op in
                    Text("\(op) — \((reading.unreadable[op] ?? []).joined(separator: ", "))")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let canLines = ["Reads your subscriptions and recurring bills.",
                                   "Read-only — never cancels, pays, or changes anything."]

    private func register(proof: String) {
        store.registerConnected(id: "rocketmoney", name: "Rocket Money", proof: proof,
                                can: Self.canLines)
    }

    private func harvested() {
        harvestedThisCover = true
        cancelled = false
        result = nil
        Task {
            register(proof: String(localized: "Signed in"))
            DSHaptic.success()
            await sync()
        }
    }

    private func sync() async {
        guard !syncing, RocketMoneyAuth.connected else { return }
        syncing = true
        let added = await RocketMoneyIngest.refresh(context: modelContext)
        syncing = false
        reading = RocketMoneyIngest.lastReading

        guard let added else {
            if reading.refused {
                result = .failed(String(localized: "Rocket Money signed you out — connect again."))
            } else {
                result = .failed(String(localized: "Couldn't reach Rocket Money — try again in a moment."))
            }
            return
        }
        // Signed in and the walk taught it nothing. Now that the walk is
        // automatic this means the pages did not answer, not that the person
        // skipped a step — so the remedy is the ordinary one.
        if reading.taught == 0 {
            result = .says(String(localized: "Signed in, but Rocket Money didn't hand anything back — connect again."))
            register(proof: String(localized: "Signed in"))
            return
        }
        if added == 0, !reading.understoodSomething, !reading.unreadable.isEmpty {
            result = .says(String(localized: "Signed in, but nothing readable came back yet."))
            register(proof: String(localized: "Signed in"))
            return
        }
        result = .landed(added)
        register(proof: added > 0
                 ? String(localized: "\(added) new")
                 : String(localized: "Synced just now"))
    }
}
