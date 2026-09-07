import SwiftUI
import SwiftData

/// An app's product page — tap an app in the catalog and see what it is, what
/// lands in your feed, and the verb, before you commit.
///
/// **ON THE ACCOUNT PAGE'S ANATOMY SINCE §639c (2026-09-06).** User ruling:
/// *"it needs to be every page in the catalogue has the DNA."* §639b put all
/// 55 setup screens on `AccountPage`; this page is the one every one of them
/// is reached THROUGH, and it was still wearing the App Store product-page
/// shape it was built with — a left-aligned hero mark beside a stack of
/// eyebrow, name, tagline and button, over `label12` section captions in a
/// `ScrollView`. Two pages one tap apart, agreeing about nothing a person
/// reads first.
///
/// So the head is the chassis's head — one centred mark, the name, a dot and
/// a state line — and the body is a plain `List` of rows on the page's own
/// ground. **What is NOT copied is the point of the split**: the product page
/// carries the PITCH (what it does, what lands, the verb) and the account page
/// carries the ACT, which is why every migrated screen's `intro` is written as
/// action rather than a re-pitch — "you reach this from the product page,
/// which has just said what it is". Collapsing the two would have made those
/// 52 sentences wrong.
///
/// Three consequences worth naming:
///
/// - **The state line comes from `AccountPageState.of`, the one derivation**,
///   so this page's dot, the account page's dot and the catalog row's cannot
///   disagree. It is drawn only for a CONNECTABLE offer: a "Soon" app is not
///   a seat you failed to connect, and its capsule already says so.
/// - **The group takes the meta slot** — the account page's own `label12`
///   tertiary line under the state — rather than an eyebrow above the name.
///   Same anatomy, this page's own fact in it.
/// - **The wash is `bridgeSetupWash`**, not a second copy of the recipe. This
///   page's own `brandWash` was 360pt where that one is 300, so the handoff
///   the setup wash exists for ("arriving from the product page's bold wash
///   must not drop to a bare gray form") was between two washes that did not
///   match. One definition now; the ink ruling (§524) is unchanged.
///
/// The `connectBloom` is untouched and still blooms the app's real colour —
/// that is a moment, not a background.
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
    var body: some View {
        List {
            header
            actSection
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
            // The floating agent bar sits over the last row otherwise. The
            // account page has no equivalent because its last row is an exit
            // nobody scrolls past; this page's is a streamed preview.
            Color.clear
                .frame(height: ShellMetrics.bottomInset)
                .plainAccountRow()
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        // THE SAME TOP THE ACCOUNT PAGE POURS (§524: every pour is ink), from
        // the same definition — see this file's own doc for why it is no
        // longer a second copy of the recipe.
        .bridgeSetupWash(name: offer.name)
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
        // The header IS the title — the chassis's rule, and it was already
        // true here: a nav title said the name one line above the name.
        .navigationTitle("")
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

    // MARK: - 1. Header (the chassis's head, §639c)

    /// One centred mark, the name, a dot and a state line, the group, the
    /// tagline. The same six-element head `AccountPage` draws, with this
    /// page's own facts in the meta and intro slots.
    private var header: some View {
        VStack(spacing: DS.Space.s2) {
            BridgeIcon(name: offer.name, size: DS.Mark.account)
                // The mark settles in as its page opens — the chassis's own
                // greeting, replacing this page's coin flip so the two pages
                // do not announce themselves differently.
                .settleIn()
            Text(offer.name)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            // A "Soon" app is not a seat somebody failed to connect, and its
            // capsule already says what it is. Drawing "Not connected" over
            // it would be a status about a connection that does not exist.
            if offer.connectable {
                HStack(spacing: DS.Space.s2) {
                    Circle().fill(stateTone).frame(width: 8, height: 8)
                    Text(AccountPageShape.stateLine(state))
                        .dsText(.subhead13).fontWeight(.medium)
                        .foregroundStyle(stateTone)
                }
                .accessibilityElement(children: .combine)
            }
            Text(LocalizedStringKey(offer.group))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(offer.tagline))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .plainAccountRow()
    }

    /// ONE derivation with the account page and the catalog row (§639c) — the
    /// three cannot disagree about a seat's dot.
    private var state: AccountPageShape.State {
        guard let seatID else { return .notConnected }
        // `bridge != nil`, NOT this page's `connected` — that one excludes a
        // paused seat, which is what the Connect capsule wants and the exact
        // opposite of what the line wants: a paused seat is set up, and the
        // whole point of the state line is to say "Paused" rather than
        // "Not connected".
        return AccountPageState.of(name: offer.name, seatID: seatID,
                                   connected: bridge != nil, store: store)
    }

    private var stateTone: Color {
        switch state {
        case .reading:           DS.tint
        case .needsReconnecting: DS.attention
        case .notConnected, .paused: DS.textTertiary
        }
    }

    // MARK: - 2. The act

    /// The verb, and what a wallet-riding seat has already found under it —
    /// the chassis's act slot, first block after the head.
    private var actSection: some View {
        VStack(spacing: DS.Space.s2) {
            actionButton
            walletSeatStanding
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s2)
        .plainAccountRow()
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
                .multilineTextAlignment(.center)
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
            // subhead13 tertiary — the caption grammar every block on the
            // account page uses ("Who may read it", "Watching · 5").
            Text("What it does")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
        .padding(.vertical, DS.Space.s3)
        .plainAccountRow()
    }

    /// Pre-connect only (the caller gates on `!connected`) — once real things
    /// land, the section retires rather than keeping a stale teaser on screen.
    private var whatLands: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("What lands in your feed")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
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
        .padding(.vertical, DS.Space.s3)
        .plainAccountRow()
    }
}
