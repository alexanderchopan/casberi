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
    @State private var openBridge: BridgeRouter.Destination?
    @State private var previewStream = GenStream()

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
        .onAppear {
            // The preview streams in like every generated surface.
            if !connected, let doc = StorePreview.doc(for: offer.name) {
                previewStream.stream(doc)
            }
        }
        .sheet(isPresented: $pairing) { PairClientSheet() }
        .navigationDestination(item: $openBridge) { dest in
            BridgeDestinationView(destination: dest)
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
                // A broken setup bridge (mail/wallet/token) is fixed by redoing
                // its setup, not the one-tap connect path.
                if offer.needsSetup {
                    openBridge = BridgeRouter.destination(forOffer: offer.name)
                } else {
                    BridgeConnect.connect(offer, store: store, context: modelContext)
                }
            }
        } else if connected {
            VerbCapsule(verb: .open) {
                if let id = bridge?.id { openBridge = BridgeRouter.destination(forID: id) }
            }
        } else if offer.name == "Claude" {
            VerbCapsule(verb: .pair) { pairing = true }
        } else if offer.connectable {
            if offer.needsSetup {
                VerbCapsule(verb: .connect) { openBridge = BridgeRouter.destination(forOffer: offer.name) }
            } else {
                VerbCapsule(verb: .connect) {
                    BridgeConnect.connect(offer, store: store, context: modelContext)
                }
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
            // The preview (option 4): the app's shape, streamed through the
            // real engine — the App Store screenshot, generated. Inert; the
            // real thing arrives when the bridge does. Connectable apps skip
            // it: their feed shows real things instead.
            if !connected, StorePreview.doc(for: offer.name) != nil {
                GenRender(id: "root", els: previewStream.els)
                    .padding(.horizontal, -DS.Space.s4)
                    .allowsHitTesting(false)
            } else {
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
            }
            if !connected, StorePreview.doc(for: offer.name) != nil {
                Text(offer.connectable
                     ? "A preview — your real things replace it when you connect."
                     : "A preview — this bridge arrives with the connected apps update.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
            }
        }
    }
}
