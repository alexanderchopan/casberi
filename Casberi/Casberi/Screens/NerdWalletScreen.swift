import SwiftUI
import SwiftData

/// NerdWallet, connected — the publisher's own feed in Casberi. One switch and
/// nothing else, because there is nothing else that honestly exists: the
/// publisher ships a single RSS document and no per-topic feeds (measured; see
/// `NerdWalletBridge`). Turning it on lands new articles on every visit and app
/// foreground. No account, no token, read-only public feed.
///
/// The act slot is `DealsScreen`'s shape with one row instead of several —
/// picking IS connecting here, so the switch is the act rather than a control
/// underneath a Connect button that would do the same thing twice.
struct NerdWalletScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var following = NerdWalletBridge.following
    @State private var syncing = false
    @State private var lastResult: String?

    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    var body: some View {
        AccountPage(
            name: "NerdWallet", seatID: "nerdwallet", source: "NerdWallet",
            state: AccountPageState.of(name: "NerdWallet", seatID: "nerdwallet",
                                       connected: following, store: store),
            mode: .noAccount,
            teardown: {
                NerdWalletBridge.stopFollowing()
                following = false
            },
            sheet: $sheet,
            act: { actBlock },
            more: { EmptyView() },
            keySheet: { EmptyView() }
        )
        .onAppear {
            following = NerdWalletBridge.following
            if following { Task { await sync() } }
        }
    }

    @ViewBuilder private var actBlock: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: DS.Space.s3) {
                Text("Follow NerdWallet")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Spacer()
                if following {
                    Image(systemName: "checkmark")
                        .dsText(.body17).foregroundStyle(DS.tint)
                }
            }
            .frame(minHeight: AccountFactRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if syncing {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text("Reading NerdWallet…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
        } else if let lastResult {
            Text(lastResult)
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
        }
        // The one sentence this page is allowed (§748), and it earns its place
        // by saying the thing the switch cannot: what this seat is NOT. The
        // name says "wallet" and the catalog shelf it sits on is Reading, so
        // "this does not reach an account" is the fact a person actually needs
        // before tapping — not a restatement of the control above it.
        DSSlabNote(text: "Articles only — NerdWallet's public feed. No sign-in, and nothing here reads your money.",
                   plain: true)
    }

    private func toggle() {
        if following {
            NerdWalletBridge.stopFollowing()
            following = false
            // The articles leave with the follow (prd §286), the way a removed
            // Deals publisher's rows do — they landed because of this seat and
            // nothing else stamps them.
            FollowPrune.remove(source: NerdWalletBridge.source, context: modelContext) { _ in true }
            store.remove("nerdwallet")
            lastResult = nil
        } else {
            NerdWalletBridge.following = true
            following = true
            Task { await sync() }
        }
        DSHaptic.tap()
    }

    private func sync() async {
        guard following else {
            store.remove("nerdwallet")
            return
        }
        if syncing { return }
        syncing = true
        let added = await NerdWalletIngest.refresh(context: modelContext)
        syncing = false
        // The switch may have gone off while the fetch was in flight.
        guard following else {
            store.remove("nerdwallet")
            return
        }
        guard let added else {
            lastResult = String(localized: "Couldn't reach NerdWallet — check your connection.")
            return
        }
        lastResult = added > 0 ? String(localized: "\(added) new") : String(localized: "Up to date")
        let proof = added > 0
            ? String(localized: "\(added) articles in")
            : String(localized: "Synced just now")
        store.registerConnected(id: "nerdwallet", name: "NerdWallet", proof: proof,
                                can: ["Reads NerdWallet's public feed.",
                                      "No account — nothing here reads your money."])
    }
}
