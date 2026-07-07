import SwiftUI
import SwiftData

/// An app's product page — the App-Store move: tap an app in the catalog and
/// see what it is, what lands in your feed, and a Connect button, before you
/// commit. Identity rides the brand COLOR (legal everywhere); the honest
/// availability state is stated plainly, never faked.
struct AppDetailScreen: View {
    let offer: BridgeCatalog.Offer
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var pairing = false
    @State private var openBridge: OpenRoute?
    private struct OpenRoute: Identifiable, Hashable { let id: String }

    private var bridge: BridgeApp? {
        store.bridges.first { $0.name == offer.name }
    }
    private var connected: Bool {
        bridge != nil && bridge?.status != .paused
    }
    private var brand: Color { BridgeGlyph.color(for: offer.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                header
                whatItDoes
                whatLands
            }
            .padding(DS.Space.s4)
            .padding(.bottom, ShellMetrics.bottomInset)
        }
        .scrollIndicators(.hidden)
        .dsPageBackground()
        .navigationTitle(offer.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pairing) { PairClientSheet() }
        .navigationDestination(item: $openBridge) { route in
            if route.id == "zerion" { ZerionScreen() } else { BridgeDetailScreen(bridgeID: route.id) }
        }
    }

    // MARK: - Header (big icon + name + action, App Store product-page shape)

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.s4) {
            BridgeIcon(name: offer.name, size: 72)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(offer.group.uppercased())
                    .dsText(.label12).kerning(0.7).foregroundStyle(DS.textTertiary)
                Text(offer.name).dsText(.heading22).foregroundStyle(DS.textPrimary)
                Text(offer.tagline).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                actionButton.padding(.top, DS.Space.s2)
            }
            Spacer(minLength: 0)
        }
    }

    /// The product page's action — the SAME honest capsule verbs as the Apps
    /// chart (shared `VerbCapsule`): Fix / Pair / Connect / Open / Soon.
    @ViewBuilder
    private var actionButton: some View {
        if bridge?.status == .attention {
            VerbCapsule(verb: .fix) {
                BridgeConnect.connect(offer, store: store, context: modelContext)
            }
        } else if connected {
            VerbCapsule(verb: .open) {
                if let id = bridge?.id { openBridge = OpenRoute(id: id) }
            }
        } else if offer.name == "Claude" {
            VerbCapsule(verb: .pair) { pairing = true }
        } else if offer.connectable {
            VerbCapsule(verb: .connect) {
                BridgeConnect.connect(offer, store: store, context: modelContext)
            }
        } else {
            VerbCapsule(verb: .soon)
        }
    }

    // MARK: - Sections

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("WHAT IT DOES")
                .dsText(.label12).kerning(0.7).foregroundStyle(DS.textTertiary)
            Text(offer.summary)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whatLands: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("WHAT LANDS IN YOUR FEED")
                .dsText(.label12).kerning(0.7).foregroundStyle(DS.textTertiary)
            HStack(spacing: DS.Space.s3) {
                RoundedRectangle(cornerRadius: DS.Radius.appIcon(36), style: .continuous)
                    .fill(brand.opacity(0.16))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(brand)
                    )
                Text(offer.tagline).dsText(.body17).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
            }
            if !offer.connectable && !connected {
                Text("This bridge isn't available yet — it arrives with the connected apps update.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
            }
        }
    }
}
