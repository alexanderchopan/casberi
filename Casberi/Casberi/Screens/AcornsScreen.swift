import SwiftUI
import SwiftData

/// Acorns' setup — `SpotifyScreen`'s shape, because it is the same kind of
/// seat: a sign-in run inside a `WKWebView` we control, then reads made as the
/// person. What lands: your accounts and their balances. Read-only — every path
/// in `AcornsLive` is a GET, and there is no endpoint in it that could accept a
/// write.
///
/// **This page has one job `SpotifyScreen` does not have, and it is the reason
/// the seat could be promoted ahead of its evidence (prd §780b).** No
/// authenticated Acorns response has ever been seen from this repo, so the read
/// may come back in a shape `LooseJSON` cannot make a row out of. The page says
/// which of the three things happened — rows landed, the account is empty, or
/// the shape was not readable — and in the last case it names the keys it saw.
/// A seat that said "Synced just now" over an unreadable body would be §83's
/// fake status, and this one is one TestFlight screenshot away from being
/// fixable instead.
struct AcornsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connecting = false
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var cancelled = false
    @State private var showLogin = false
    @State private var harvestedThisCover = false
    @State private var reading = AcornsIngest.lastReading

    /// The page's one presentation (`AccountPage.sheet`). The login web view
    /// rises through its own `fullScreenCover`, so the two never collide.
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Acorns", seatID: "acorns", source: "Acorns",
            state: AccountPageState.of(name: "Acorns", seatID: "acorns",
                                       connected: AcornsAuth.connected, store: store),
            mode: .signIn,
            teardown: { AcornsAuth.clear() },
            sheet: $sheet,
            act: {
                if AcornsAuth.connected { connectedBlock } else { connectBlock }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .fullScreenCover(isPresented: $showLogin,
                         onDismiss: { cancelled = !harvestedThisCover }) {
            AcornsLoginWebView(onCaptured: harvested)
        }
        .onAppear {
            reading = AcornsIngest.lastReading
            if AcornsAuth.connected { Task { await sync() } }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        if connecting {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text("Reading your Acorns…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s1)
        } else {
            DSSlabButton(title: "Connect Acorns",
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
                             syncingLine: String(localized: "Reading your Acorns…"),
                             proof: result)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.tint)
            Text("Signed in")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }
        BridgeSyncStatusRows(syncing: syncing || connecting,
                             syncingLine: String(localized: "Reading your Acorns…"),
                             proof: result,
                             retry: { Task { await sync() } })
        unreadableBlock
        DSSlabNote(text: "Your accounts and balances land in your feed. Read-only — Acorns is never asked to move money.",
                   plain: true)
    }

    /// The honest half. Drawn ONLY when a read came back that this could not
    /// make a row out of — never as a permanent disclaimer, which would be
    /// furniture on a seat that is working.
    @ViewBuilder private var unreadableBlock: some View {
        if !reading.unreadable.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Acorns answered, but Casberi didn't recognise the shape.")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                ForEach(reading.unreadable.keys.sorted(), id: \.self) { path in
                    Text("\(path) — \((reading.unreadable[path] ?? []).joined(separator: ", "))")
                        .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let canLines = ["Reads your accounts and balances.",
                                   "Read-only — never moves money or changes anything."]

    private func register(proof: String) {
        store.registerConnected(id: "acorns", name: "Acorns", proof: proof,
                                can: Self.canLines)
    }

    /// The web view handed back a session. Register on the SESSION, not on the
    /// first sync's success — `SpotifyScreen`'s 2026-09-12 ruling: an account
    /// with nothing in it would otherwise leave a signed-in person looking at
    /// an app that had never heard of Acorns.
    private func harvested() {
        harvestedThisCover = true
        cancelled = false
        result = nil
        connecting = true
        Task {
            register(proof: String(localized: "Signed in"))
            connecting = false
            DSHaptic.success()
            await sync()
        }
    }

    private func sync() async {
        guard !syncing, AcornsAuth.connected else { return }
        syncing = true
        let added = await AcornsIngest.refresh(context: modelContext)
        syncing = false
        reading = AcornsIngest.lastReading

        guard let added else {
            if reading.refused {
                result = .failed(String(localized: "Acorns signed you out — connect again."))
            } else {
                result = .failed(String(localized: "Couldn't reach Acorns — try again in a moment."))
            }
            return
        }
        // Landed nothing AND understood nothing is not "Up to date" (§83).
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
