import SwiftUI
import SwiftData

/// An app's product page — the App-Store move: tap an app in the catalog and
/// see what it is, what lands in your feed, and a Connect button, before you
/// commit. Identity rides the brand COLOR (legal everywhere); the honest
/// availability state is stated plainly, never faked.
struct AppDetailScreen: View {
    @Environment(ShellChrome.self) private var chrome
    let offer: BridgeCatalog.Offer
    // This window's stack (per-window since `SceneState`).
    @Environment(HomeRoute.self) private var route
    @Environment(BridgeStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @State private var previewStream = GenStream()
    /// The connect payoff (delight, 2026-07-12): bumping this blooms the app's
    /// hue over the page via the shared `.connectBloom` — "connect ends in
    /// proof", the ruling turned into a moment.
    @State private var connectToken = 0
    /// True while THIS page raised the connect form — so the payoff below
    /// fires on the page that made the promise, and not on some other product
    /// page that happens to be mounted under the same shared sheet.
    @State private var raisedForm = false

    private var bridge: BridgeApp? {
        store.bridges.first { $0.name == offer.name }
    }
    private var connected: Bool {
        bridge != nil && bridge?.status != .paused
    }
    /// Connected AND healthy — the moment the raised form has finished its
    /// job, so it can get out of the way. Distinct from `connected`, which an
    /// `.attention` bridge also satisfies: the Fix path opens the same sheet,
    /// and it should close when the connection is actually working again.
    private var liveConnected: Bool { bridge?.status == .connected }
    // signalColor, not the tile hue: this paints the inline feed icon, where
    // Tokens' near-black tile would vanish on the dark page (its identity
    // there is the glyph's green). The wash keeps asking DS.washHue itself.
    private var brand: Color { BridgeGlyph.signalColor(for: offer.name) }

    /// The page's own top, washed down from it — INK since 2026-08-29
    /// (`DS.pourInk`, whose doc carries the ruling).
    ///
    /// **This was the loudest colour in the app** and it is the one the ink
    /// pass most changes: `DS.washHue(for:)` at FULL strength for the first
    /// 30% of 360pt, so a product page opened on a slab of the app's brand
    /// (user ruling 2026-07-13: "bold, not a film" — the page opens on its
    /// color). It is also the one where the argument for colour was
    /// strongest, and it still lost on the ruling's own terms: the brand is
    /// stated by the tile at the top of this page, at full saturation, in the
    /// one element that IS the app's identity. The wash was the same fact
    /// again, forty times larger, and next to a catalogue of sixty apps it is
    /// what made moving between two of them read as changing skins.
    ///
    /// **Two things were deleted with the colour, deliberately.** The nil arm
    /// (a hueless app got no wash at all, so ChatGPT and X pages had no top
    /// while Stripe's had a purple one — that asymmetry cannot exist once the
    /// wash makes no claim), and the 0.3 hold, which existed to make a
    /// saturated hue read as a band rather than a fade. Ink needs no hold.
    ///
    /// The `connectBloom` below is UNTOUCHED and still blooms the app's real
    /// colour: that is a moment, not a background — the same line
    /// `AddressBookViews` drew when its own pour went to ink and the face
    /// reveal kept its hue.
    private var brandWash: some View {
        LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 360)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
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
        // its near-black tile (signalColor's whole point). An app with no
        // honest color at all blooms neutral, not blue (2026-08-10).
        .connectBloom(hue: BridgeGlyph.glyphTint(for: offer.name)
                          ?? DS.brandHue(for: offer.name) ?? DS.neutralBadge,
                      token: connectToken)
        // (The glyph rain that fell through the bloom retired 2026-08-11,
        // user ruling: berry rain is pull-to-refresh's payoff alone.)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle(offer.name)
        .navigationBarTitleDisplayMode(.inline)
        // The form's job is done the moment the connection goes live, so it
        // leaves — and the payoff lands HERE, on the page that made the
        // promise (prd §218): the hue blooms, the haptic fires, and Connect
        // has already become Open behind it.
        .onChange(of: liveConnected) { _, isLive in
            guard isLive, raisedForm else { return }
            raisedForm = false
            route.connectForm = nil
            connectToken += 1
            DSHaptic.success()
            chrome.flash(BridgeConnect.landingMessage(offer.name), tone: .success)
        }
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
            BridgeIcon(name: offer.name, size: DS.Mark.hero)
                // The mark coin-flips as its page opens — the same greeting the
                // thing-sheet and feed-switch icons give (delight, 2026-07-12).
                .coinFlip(trigger: offer.name)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(LocalizedStringKey(offer.group))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Text(offer.name).dsText(.heading22).foregroundStyle(DS.textPrimary)
                Text(LocalizedStringKey(offer.tagline)).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                actionButton.padding(.top, DS.Space.s2)
                walletSeatStanding
            }
            Spacer(minLength: 0)
        }
    }

    /// The product page's action — the SAME honest capsule verbs as the Apps
    /// chart (shared `VerbCapsule`): Fix / Connect / Watch / Automatic / Open /
    /// Soon.
    @ViewBuilder
    private var actionButton: some View {
        if bridge?.status == .attention {
            VerbCapsule(verb: .fix) {
                // A broken setup bridge (mail/wallet/token) is fixed by redoing
                // its setup, not the one-tap connect path.
                if offer.needsSetup {
                    openSetup()
                } else {
                    doConnect()
                }
            }
        } else if connected {
            VerbCapsule(verb: .open) {
                // Through the shared door: a wallet-riding seat with no screen
                // of its own opens the ROOM its rows land in rather than the
                // wallet manager, so this page's Open and the catalog's agree.
                if let id = bridge?.id {
                    BridgeRouter.open(seatID: id, route: route, chrome: chrome)
                }
            }
        } else if offer.connectable {
            if offer.needsSetup {
                // A WALLET-RIDING seat says `Watch` / `Automatic`, never
                // Connect (prd §515) — there is nothing to connect, and the
                // sentence under it says what the app has already looked for.
                VerbCapsule(verb: walletSeatVerb ?? .connect) { openSetup() }
            } else {
                VerbCapsule(verb: .connect) {
                    doConnect()
                }
            }
        } else {
            VerbCapsule(verb: .soon)
        }
    }

    /// This seat's `BridgeStore` id, when it has one.
    private var seatID: String? { BridgeRouter.id(forOffer: offer.name) }

    /// The verb a wallet-riding seat wears while it is dark — nil for every
    /// ordinary bridge, which keeps Connect.
    private var walletSeatVerb: CapsuleVerb? {
        guard let id = seatID, WalletSeatStanding.rides(id: id) else { return nil }
        return CapsuleVerb(WalletSeatStanding.verb(
            watched: WalletStore.shared.addresses.count))
    }

    /// What a wallet-riding seat has actually found, said out loud (prd §515).
    ///
    /// THIS IS THE ANSWER TO THE QUESTION THE PAGE USED TO RAISE. The app reads
    /// every one of these protocols for every watched address already, and knew
    /// perfectly well whether it had seen yours — it just never said so
    /// anywhere, so tapping Connect and landing on a roster of addresses was
    /// the whole of the reply. It renders in both states: dark, it says what is
    /// missing; connected, it says where it was found, which is the receipt the
    /// seat's own status line only half gives.
    @ViewBuilder private var walletSeatStanding: some View {
        if let id = seatID,
           let line = WalletSeatStanding.line(
               id: id,
               watched: WalletStore.shared.addresses.count,
               seen: store.walletSeatCount(id: id) ?? 0) {
            // `Text(line)`, not `LocalizedStringKey(line)` — the sentence is
            // already localized and composed; handing it back as a key would
            // look up a string nobody wrote and fall through to the literal,
            // which works by accident and stops working in any language.
            Text(line)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)
        }
    }

    /// Where Connect goes for a setup bridge (prd §218, 2026-07-25). A FORM
    /// rises as a sheet over this page: the reading stays behind it, there's
    /// no back-stack to walk, and the promise gets redeemed on the page where
    /// it was made. A MANAGER still pushes — a watch list isn't finished when
    /// you connect it, so it deserves to be somewhere you can return to. The
    /// decision (and the sheet) live on `HomeRoute`, shared with every other
    /// Connect in the app.
    private func openSetup() {
        // Only a sheet that LEAVES on its own hands the payoff back to this
        // page. A watch list keeps its sheet up and reports its own proof
        // there ("3 posts in", with its own success haptic) — firing a toast
        // and a bloom underneath it would be the same news told twice, once
        // where it can't be seen.
        let dest = BridgeRouter.destination(forOffer: offer.name)
        // `finishesOnConnect` ALONE, since 2026-08-20. It used to also demand
        // `raisedByConnect`, which was exactly equivalent on touch — no
        // destination is `finishesOnConnect` and pushed there — and became
        // wrong the day Mac started pushing every connect form: this flag means
        // "the form will leave on its own and hand the payoff back to me", and
        // on Mac it leaves by popping (`ConnectPushWatcher`) rather than by
        // dismissing. Asking how it leaves was never the question.
        raisedForm = dest?.finishesOnConnect == true
        route.openSetup(forOffer: offer.name)
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
            Text(LocalizedStringKey(offer.effectiveSummary))
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
                //
                // 2026-07-31: the single line was "Lands in your feed the
                // moment you connect", which under a header reading "What
                // lands in your feed" answered with its own question — and
                // was FALSE for a file import, which has no connect moment:
                // you hand over an export and the whole of it lands at once,
                // each thing dated to when it happened rather than to today.
                // That date behaviour is the fact worth stating, and it's the
                // one a person is actually surprised by.
                Text(BridgeRouter.destination(forOffer: offer.name)?.isFileImport == true
                     ? "Your whole export lands in one pass — each thing dated to when it happened, not to today."
                     : "New things arrive on their own, as they happen.")
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
            }
        }
    }
}
