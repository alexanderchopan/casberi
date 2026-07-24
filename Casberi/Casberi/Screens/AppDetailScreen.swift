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
    @State private var previewStream = GenStream()
    /// The connect payoff (delight, 2026-07-12): bumping this blooms the app's
    /// hue over the page via the shared `.connectBloom` — "connect ends in
    /// proof", the ruling turned into a moment.
    @State private var connectToken = 0

    private var bridge: BridgeApp? {
        store.bridges.first { $0.name == offer.name }
    }
    private var connected: Bool {
        bridge != nil && bridge?.status != .paused
    }
    // signalColor, not the tile hue: this paints the inline feed icon, where
    // Tokens' near-black tile would vanish on the dark page (its identity
    // there is the glyph's green). The wash keeps asking DS.washHue itself.
    private var brand: Color { BridgeGlyph.signalColor(for: offer.name) }

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
                // Retires once connected (2026-07-23) — found live: the old
                // code kept a static "what lands" teaser row on screen even
                // after connecting, the same defect §189 fixed on the manage
                // pages (a form that never changes state). The promise is
                // redeemed the moment Open replaces Connect; the real feed
                // answers the question this section exists to ask.
                if !connected {
                    whatLands
                }
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
        // The payoff must carry light — Tokens blooms its glyph green, not
        // its near-black tile (signalColor's whole point).
        .connectBloom(hue: BridgeGlyph.glyphTint(for: offer.name)
                          ?? DS.brandHue(for: offer.name) ?? DS.tint,
                      token: connectToken)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(offer.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The preview streams in like every generated surface.
            if !connected, let doc = StorePreview.doc(for: offer.name) {
                previewStream.stream(doc)
            }
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
                    HomeRoute.shared.pushBridge(BridgeRouter.destination(forOffer: offer.name))
                } else {
                    doConnect()
                }
            }
        } else if connected {
            VerbCapsule(verb: .open) {
                if let id = bridge?.id { HomeRoute.shared.pushBridge(BridgeRouter.destination(forID: id)) }
            }
        } else if offer.connectable {
            if offer.needsSetup {
                VerbCapsule(verb: .connect) { HomeRoute.shared.pushBridge(BridgeRouter.destination(forOffer: offer.name)) }
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
            guard ok else {
                chrome.flash("Couldn't connect \(offer.name).", tone: .failure)
                return
            }
            connectToken += 1
            chrome.flash(BridgeConnect.landingMessage(offer.name), tone: .success)
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
            // The differentiated extras, scannable rather than crammed into
            // the hook (prd §192) — the same DSCheckList grammar the
            // CONNECTED state renders, so nothing changes visually the
            // moment Connect flips to Open.
            if !offer.features.isEmpty {
                DSCheckList(lines: offer.features)
                    .padding(.top, DS.Space.s1)
            }
        }
    }

    /// Pre-connect only (the caller gates on `!connected`) — once real things
    /// land, the section retires rather than keeping a stale teaser on screen.
    private var whatLands: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("What lands in your feed")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            // The preview (option 4): the app's shape, streamed through the
            // real engine — the App Store screenshot, generated. Inert; the
            // real thing arrives when the bridge does.
            if StorePreview.doc(for: offer.name) != nil {
                GenRender(id: "root", els: previewStream.els)
                    .padding(.horizontal, -DS.Space.s4)
                    .allowsHitTesting(false)
                Text(offer.connectable
                     ? "A preview — your real things replace it when you connect."
                     : "A preview — this bridge arrives with the connected apps update.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
            } else {
                // No authored preview to stream (2026-07-23, found live: this
                // row used to repeat `offer.tagline` — the exact sentence
                // already read one line above, under the icon). One honest
                // line that adds a fact instead of echoing one: WHEN, since
                // "What it does" already covers what. Left-aligned, matching
                // every other line of body copy on this page — DSSlabNote's
                // centering belongs to a slab stack, not this layout.
                Text("Lands in your feed the moment you connect.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        }
    }
}
