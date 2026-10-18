import SwiftUI
import SwiftData

/// Fileverse's account page (prd §1346). The seat signs in on Fileverse's own
/// page (`FileverseLoginSheet`), keeps each portal's read key on this device,
/// and opens your dDocs here, in Casberi's type. Read-only: nothing on this
/// page can change anything at Fileverse.
struct FileverseScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var connected = FileverseAuth.connected
    @State private var syncing = false
    @State private var result: BridgeProof?
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "Fileverse", seatID: FileverseAuth.seatID, source: FileverseLive.source,
            state: AccountPageState.of(name: "Fileverse", seatID: FileverseAuth.seatID,
                                       connected: connected, store: store),
            mode: .signIn,
            cardSheet: { _ in
                AnyView(FileverseLoginSheet(onCaptured: {
                    connected = true
                    Task { await confirm() }
                }))
            },
            teardown: { FileverseAuth.clear() },
            sheet: $sheet,
            act: {
                if connected { connectedBlock } else { connectBlock }
            },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            connected = FileverseAuth.connected
            if connected, BridgeRefresh.dueForHeal("fileverse") {
                Task { await sync() }
            }
        }
    }

    @ViewBuilder private var connectBlock: some View {
        DSSlabButton(tile: .signIn, title: "Connect Fileverse",
                     systemImage: "doc.text",
                     action: { DSHaptic.tap(); result = nil; sheet = .card(id: "fileverseSignIn") })
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Opening your docs…"),
                             proof: result)
    }

    @ViewBuilder private var connectedBlock: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "doc.text")
                .dsGlyph(.body, weight: .medium)
                .foregroundStyle(DS.brandInk)
            Text(signedInLine)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        BridgeSyncStatusRows(syncing: syncing,
                             syncingLine: String(localized: "Opening your docs…"),
                             proof: result,
                             retry: { Task { await sync() } })
    }

    private var signedInLine: String {
        let n = FileverseAuth.portals.count
        return n == 1 ? String(localized: "Signed in") : String(localized: "Signed in · \(n) workspaces")
    }

    private static let canLines = ["Opens your docs on this phone with your own sign-in.",
                                   "Read-only — can't edit, share or delete anything."]

    private func register(proof: String) {
        store.registerConnected(id: FileverseAuth.seatID, name: "Fileverse", proof: proof,
                                can: Self.canLines)
    }

    /// Registered on the keys, then synced.
    private func confirm() async {
        DSHaptic.success()
        register(proof: String(localized: "Signed in"))
        await sync()
    }

    private func sync() async {
        guard !syncing else { return }
        syncing = true
        let report = await FileverseLive.pass(context: modelContext)
        syncing = false
        connected = FileverseAuth.connected
        guard let report else {
            result = .failed(String(localized: "Couldn't reach Fileverse — try again in a moment."))
            return
        }
        if report.unreadable == report.portals {
            result = .failed(String(localized: "Couldn't read your docs from the chain — try again in a moment."))
        } else if report.failed > 0, report.landed + report.reread == 0 {
            result = .failed(String(localized: "Fileverse changed how it keeps your docs — Casberi can't open them yet."))
        } else {
            result = report.landed > 0 ? .landed(report.landed) : .upToDate
        }
        register(proof: report.landed > 0
                 ? String(localized: "\(report.landed) new")
                 : String(localized: "Synced just now"))
    }
}
