import SwiftUI
import SwiftData

/// An app's product page — the App-Store move: tap an app in the catalog and
/// see what it is, what lands in your feed, and a Connect button, before you
/// commit. Identity rides the brand COLOR (legal everywhere); the honest
/// availability state is stated plainly, never faked.
struct AppDetailScreen: View {
    @Environment(ShellChrome.self) private var chrome
    let offer: BridgeCatalog.Offer
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var openBridge: BridgeRouter.Destination?
    @State private var previewStream = GenStream()
    /// The connect payoff (delight, 2026-07-12): eases 1 → 0 when a connect
    /// lands, blooming the app's hue over the page — "connect ends in proof",
    /// the ruling turned into a moment.
    @State private var connectPulse: CGFloat = 0

    private var bridge: BridgeApp? {
        store.bridges.first { $0.name == offer.name }
    }
    private var connected: Bool {
        bridge != nil && bridge?.status != .paused
    }
    private var brand: Color { BridgeGlyph.color(for: offer.name) }

    /// The app's identity hue washed down from the top — nil for a hueless
    /// app (the gray fallback is a fill, not an identity: same ruling the
    /// thing-sheet wash follows), so those pages stay pure page.
    @ViewBuilder private var brandWash: some View {
        if let hue = DS.washHue(for: offer.name) {
            // Bold, not a film (user ruling 2026-07-13): the app's page
            // opens on its color, flowing into the page.
            LinearGradient(stops: [
                .init(color: hue, location: 0),
                .init(color: hue, location: 0.3),
                .init(color: hue.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
    }

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
        // The app's hue washes down from the top — the same atmosphere the
        // thing sheet and a source feed wear, so opening a product page reads
        // as stepping into that app's world (delight, 2026-07-12). One fixed
        // recipe, under the content; hueless apps stay pure page, honestly.
        .background(alignment: .top) { brandWash }
        // The connect payoff blooms over the content, then recedes.
        .overlay(alignment: .top) { connectBloom }
        .dsPageBackground()
        .navigationTitle(offer.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The preview streams in like every generated surface.
            if !connected, let doc = StorePreview.doc(for: offer.name) {
                previewStream.stream(doc)
            }
        }
        .navigationDestination(item: $openBridge) { dest in
            BridgeDestinationView(destination: dest)
        }
    }

    // MARK: - Header (big icon + name + action, App Store product-page shape)

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.s4) {
            BridgeIcon(name: offer.name, size: 72)
                // The mark coin-flips as its page opens — the same greeting the
                // thing-sheet and feed-switch icons give (delight, 2026-07-12).
                .coinFlip(trigger: offer.name)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(LocalizedStringKey(offer.group))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Text(offer.name).dsText(.heading22).foregroundStyle(DS.textPrimary)
                Text(LocalizedStringKey(offer.tagline)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                actionButton.padding(.top, DS.Space.s2)
            }
            Spacer(minLength: 0)
        }
    }

    /// The product page's action — the SAME honest capsule verbs as the Apps
    /// chart (shared `VerbCapsule`): Fix / Connect / Open / Soon.
    @ViewBuilder
    private var actionButton: some View {
        if bridge?.status == .attention {
            VerbCapsule(verb: .fix) {
                // A broken setup bridge (mail/wallet/token) is fixed by redoing
                // its setup, not the one-tap connect path.
                if offer.needsSetup {
                    openBridge = BridgeRouter.destination(forOffer: offer.name)
                } else {
                    doConnect()
                }
            }
        } else if connected {
            VerbCapsule(verb: .open) {
                if let id = bridge?.id { openBridge = BridgeRouter.destination(forID: id) }
            }
        } else if offer.connectable {
            if offer.needsSetup {
                VerbCapsule(verb: .connect) { openBridge = BridgeRouter.destination(forOffer: offer.name) }
            } else {
                VerbCapsule(verb: .connect) {
                    doConnect()
                }
            }
        } else {
            VerbCapsule(verb: .soon)
        }
    }

    /// Fires the connect and turns success into a moment (delight): the app's
    /// hue blooms over the page, a success haptic lands, and the toast names
    /// what's now happening — real things landing in the feed. Failure stays a
    /// plain flash. `connected` (VerbCapsule → Open) recomputes when the bridge
    /// reaches the store, so the button flips to Open on its own.
    private func doConnect() {
        BridgeConnect.connect(offer, store: store, context: modelContext) { ok in
            guard ok else { chrome.flash("Couldn't connect \(offer.name)."); return }
            DSHaptic.success()
            connectPulse = 1
            withAnimation(.easeOut(duration: 0.75)) { connectPulse = 0 }
            chrome.flash("Connected — your \(offer.name) things are landing.")
        }
    }

    /// The connect bloom — the app's hue flooding the page as the connection
    /// lands, then receding. The proof itself arrives in the feed; this is the
    /// beat that says it worked. A hueless app blooms on the tint so it still
    /// gets a payoff.
    @ViewBuilder private var connectBloom: some View {
        if connectPulse > 0.001 {
            let hue = DS.brandHue(for: offer.name) ?? DS.tint
            LinearGradient(colors: [hue.opacity(0.5), hue.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(connectPulse)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Sections

    private var whatItDoes: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("What it does")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            Text(LocalizedStringKey(offer.summary))
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whatLands: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("What lands in your feed")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
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
                    Text(LocalizedStringKey(offer.tagline)).dsText(.body17).foregroundStyle(DS.textPrimary)
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
