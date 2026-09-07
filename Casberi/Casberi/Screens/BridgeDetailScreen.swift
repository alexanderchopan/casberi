import SwiftUI
import SwiftData
import Photos

/// A bridge's detail — the app, what it can do (sentences), and its
/// controls: Reconnect when broken, Pause, Disconnect with keep-or-purge. No "ask before acting" switch, and the reason has narrowed
/// rather than gone away (2026-08-29): no bridge writes back to a SOURCE, so a
/// per-bridge writes toggle would still be a dead control. The one write this
/// app can make — Safe's co-signature (prd §425/§426) — is not governed by a
/// standing switch by design: it is asked for per transaction, on the sheet,
/// behind Face ID, which is a stronger consent than a toggle set once and
/// forgotten. A writes toggle returns only if a bridge ever gains a write that
/// runs unattended.
struct BridgeDetailScreen: View {
    let bridgeID: String
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    /// The page's one presentation (`AccountPage.sheet`).
    @State private var sheet: AccountPageSheet?

    private var bridge: BridgeApp? {
        store.bridges.first { $0.id == bridgeID }
    }

    /// ON THE ACCOUNT PAGE since prd §639 (2026-09-06). This was the one
    /// manage screen off the chassis, and the one that said "Remove" where
    /// every other screen says "Disconnect". The "Last delivered" receipt is
    /// the Activity row now; the keep-or-purge dialog is
    /// `BridgeDisconnectSection`'s, not a second copy; Pause is the exit row.
    /// What stays is what only this screen knows: the seat's own capability
    /// sentences, and the Photos-on-limited-access remedy.
    var body: some View {
        if let bridge {
            AccountPage(
                name: bridge.name, seatID: bridge.id, source: bridge.name,
                state: AccountPageState.of(name: bridge.name, seatID: bridge.id,
                                           connected: true, store: store),
                // A seat with no dedicated screen holds no store of its own
                // to clear — the seat IS the connection.
                teardown: {},
                sheet: $sheet,
                act: { actBlock(bridge) },
                more: { EmptyView() },
                keySheet: { EmptyView() }
            )
        }
    }

    /// The act slot. A seat needing attention leads with its remedy; a
    /// healthy one, which has nothing to add, leads with what it reads —
    /// sentences, not scopes, the store's own.
    @ViewBuilder private func actBlock(_ bridge: BridgeApp) -> some View {
        if bridge.status == .attention {
            // Photos on LIMITED access isn't broken and can't be
            // reconnected out of — the app is seeing exactly the
            // photos it was given. The remedy is the system's own
            // picker (widen the set) or Settings (full access), so
            // that is what this button does instead of a Reconnect
            // that would change nothing (honesty rule: no control
            // that doesn't do what it says).
            if bridge.id == "pho", ScreenshotIngest.accessIsLimited {
                photosLimitedRemedy
            } else {
                // The component, not a glass pill (prd §613). This
                // is a manage page's one verb, which is what §190
                // made the slab FOR — and glass is the floating
                // layer's material by §8, never content's.
                DSSlabButton(title: String(localized: "Reconnect"),
                             systemImage: "arrow.triangle.2.circlepath") {
                    store.reconnect(bridge.id)
                    DSHaptic.success()
                }
            }
        } else if !bridge.can.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                ForEach(Array(bridge.can.enumerated()), id: \.element) { i, sentence in
                    Text(sentence)
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .staggerIn(index: i)
                }
            }
        }
    }

    /// Both ways out of limited access, stated plainly: widen the picked set
    /// here, or hand Photos full access in Settings.
    @ViewBuilder
    private var photosLimitedRemedy: some View {
        VStack(spacing: DS.Space.s2) {
            Text("Only the photos you picked are visible, so new screenshots don't arrive on their own.")
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The remedy is one verb and one door, so it is one slab and one
            // door slab (prd §613) — the pair the rest of this screen already
            // wears, where before it was two hand-rolled capsules in two
            // different materials.
            DSSlabButton(title: String(localized: "Choose more photos"),
                         systemImage: "photo") {
                DSHaptic.tap()
                presentLimitedPicker()
            }
            // Verb over address (the 2026-08-14 door anatomy) — the route rides
            // `detail:`, which is also what keeps the big words inside §315's
            // own door budget. This page left that budget's reach until §639
            // put it on the same chassis as every other seat's.
            DSSlabDoor(title: String(localized: "Allow all photos"),
                       detail: String(localized: "Settings"),
                       systemImage: "gearshape") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.plain)
        }
    }

    /// The system's own "select more photos" sheet. Needs a presenting
    /// controller, which SwiftUI doesn't hand out — the key window's root is
    /// the same anchor `RedditBridge`/`SpotifyBridge` use for their web auth.
    private func presentLimitedPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in
                // Photos just widened what we can see — anything newly visible
                // is OLDER than the walk's cursor, and the walk may already
                // have reported itself finished. Start it over so the newly
                // picked screenshots actually land.
                ScreenshotIngest.resetBackfill()
                _ = ScreenshotIngest.ingest(context: modelContext)
                ScreenshotIngest.backfill(context: modelContext)
            }
        }
    }
}
