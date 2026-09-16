import SwiftUI
import SwiftData
import PhotosUI

/// Settings — the small stuff behind the avatar in the Apps nav bar: your
/// photo, Data, Theme. One parcel of rows in the feed's own grammar (ruling
/// 2026-07-21, supersedes the tile grid: seven one-fact entries couldn't fill
/// uniform tiles, and every neighboring surface — the feed, the Apps page,
/// this screen's own detail trays — already speaks rows). Pushed from Apps,
/// not a tab of its own (2026-07-06 restructure).
struct SettingsScreen: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(BridgeStore.self) private var bridgeStore
    @Environment(HomeRoute.self) private var route
    @Environment(\.scenePhase) private var scenePhase
    /// Drives the Data tile's badge: a green lock on device, a blue cloud once
    /// the person turns iCloud sync on.
    @AppStorage("icloud.sync") private var icloudSync = false
    /// The highest round number the corpus has been congratulated for, so a
    /// crossing is celebrated once and never re-celebrated on the next open.
    @AppStorage("settings.thingsRung") private var celebratedRung = 0
    @State private var rungBounce = 0
    @State private var diagnosticsOpen = false
    @State private var languageOpen = false
    @State private var chipOrderOpen = false
    @State private var detail: AccountDetail?

    /// What the Notifications row says without being opened (prd §770): the
    /// digest's cadence, and the categories switched off by name, because
    /// "3 of 9" tells you nothing about whether your wallet reaches you.
    private var notifySummary: String {
        let s = Notifications.settings
        guard s.anyOn else { return String(localized: "Off") }
        let off = Notifications.Settings.categories.filter { s.off.contains($0) }
        return off.isEmpty
            ? String(localized: "Each evening")
            : String(localized: "Each evening, not \(ListFormatter.localizedString(byJoining: off))")
    }
    @State private var avatarPickerOpen = false
    @State private var avatarDialogOpen = false
    @State private var avatarSelection: PhotosPickerItem?
    @State private var nameEditorOpen = false
    @State private var nameDraft = ""

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // One parcel, no group headers — every row in one A–Z
                    // field. (A big avatar hero lived here for an hour on
                    // 2026-07-10 and was rejected: personalization paints your
                    // SPACE — it never builds a profile of you.)
                    DSScreenHead(title: Text("Settings"))
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.bottom, DS.Space.s2)
                    rowList(allRows)
                    colophon
                }
                .padding(.top, ShellMetrics.topInset)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
            .scrollIndicators(.hidden)
        .minimizesChrome(chrome)
        .dsSoftScrollEdges()
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            // Name in the content, the way back in the dock's seat (prd §767).
            .navigationTitle(Text("Settings"))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { readCounts(); markMilestone() }
            // The count is re-read when the app comes back to this screen —
            // a sweep may have landed things while it was away — and never
            // in between: one COUNT per return, not one per bridge landing.
            .onChange(of: scenePhase) { _, phase in if phase == .active { readCounts() } }
            // `dsNavSheet` rather than `dsPageSheet` (prd §560) — the nav-sheet
            // family's own chassis, which adds the presented corner these
            // three were missing along with the sizing they already had.
            .sheet(isPresented: $diagnosticsOpen) {
                NavigationStack { DiagnosticsScreen() }.dsNavSheet()
            }
            .sheet(item: $detail) { AccountDetailSheet(detail: $0) }
            .sheet(isPresented: $languageOpen) { LanguagePickerSheet() }
            .sheet(isPresented: $chipOrderOpen) {
                NavigationStack { CategoryOrderSheet() }.dsNavSheet()
            }
            .photosPicker(isPresented: $avatarPickerOpen,
                          selection: $avatarSelection, matching: .images)
            // A set photo can come off, not just be replaced — every setting
            // can be undone.
            .confirmationDialog("Your photo", isPresented: $avatarDialogOpen) {
                Button("Change photo") { avatarPickerOpen = true }
                Button("Remove photo", role: .destructive) {
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) { ProfileStore.shared.avatar = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            // The name, in the same grammar as the photo above it — one field,
            // one Save, and a Remove that only exists once there is something
            // to remove (§83: a control that can't do anything isn't offered).
            // An alert rather than a tray: this is the address-book rename's
            // exact shape, for the same reason it's used there — one short
            // string, typed once, with nothing else on the screen to decide.
            .alert("Your name", isPresented: $nameEditorOpen) {
                TextField(String(localized: "Name"), text: $nameDraft)
                    .textInputAutocapitalization(.words)
                    .textContentType(.givenName)
                Button(String(localized: "Save")) {
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) {
                        ProfileStore.shared.name = ProfileStore.preparedName(nameDraft)
                    }
                }
                if ProfileStore.shared.name != nil {
                    Button(String(localized: "Remove"), role: .destructive) {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ProfileStore.shared.name = nil }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                // The honest fact, where it's asked for rather than in a
                // privacy screen nobody opens while typing.
                Text("Only used to greet you. It stays on this iPhone.")
            }
            .onChange(of: avatarSelection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        ProfileStore.shared.avatar = ProfileStore.prepared(image)
                    }
                    avatarSelection = nil
                }
            }
            #if DEBUG
            // Debug hook: `simctl launch ... -deeplink casberi://account
            // -accountDetail data` opens that detail sheet for screenshots.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openDiagnostics") {
                    diagnosticsOpen = true
                }
                if UserDefaults.standard.bool(forKey: "openChipOrder") {
                    chipOrderOpen = true
                }
                if let raw = UserDefaults.standard.string(forKey: "accountDetail"),
                   let which = AccountDetail(rawValue: raw) {
                    detail = which
                }
            }
            #endif
        .tint(DS.tint)
    }

    private struct RowSpec {
        let title: String
        let value: String
        /// What the row's end promises (prd §767).
        var trail: AccountRow.Trail = .opens
        var avatar: UIImage? = nil
        /// The Avatar row always shows the photo seat — the photo once set,
        /// the Casberi mark before (it marks where the photo lands).
        var avatarSeat = false
        /// The row's leading glyph-in-a-squircle (the Data row's trust mark) —
        /// the same colored mark the Apps page speaks, at row size.
        var badge: (symbol: String, color: Color)? = nil
        /// The trailing fact leads with a live number worth watching arrive —
        /// it rolls up from zero instead of simply being there.
        var countsUp = false
        /// Bump to make the badge give one bounce (a milestone crossing).
        var bounce = 0
        var action: () -> Void = {}
    }

    /// The Data row's count — read ONCE per appearance, never per body
    /// evaluation (prd §628, 2026-09-06).
    ///
    /// This was a computed property running `fetchCount` — a SQL `COUNT` over
    /// the whole store — and it was reached from `primaryRows`, i.e. from the
    /// body. Build 525's CPU-resource report on a real phone put this exact
    /// chain (`SettingsScreen.body` → `allRows` → `primaryRows` → SwiftData →
    /// CoreData) at 21 of the main thread's 31 samples while the app burned
    /// 90 seconds of CPU in 131: the person was sitting on the Diagnostics
    /// sheet, a foreground sweep was landing bridges underneath, every landing
    /// invalidated this body through the stores it observes, and every
    /// evaluation counted the corpus again. Two watchdog kills sat on top of
    /// the same evenings' sweeps. A settings row does not need a live count;
    /// it needs the count when the screen opens, and again when the app comes
    /// back to it.
    @State private var thingCount = 0
    /// Same rule for the Keychain: `AgentKey.active` is a `SecItemCopyMatching`
    /// round trip to securityd, and `secondaryRows` read it per evaluation.
    @State private var keyedAgent: AgentProvider?
    /// Whether "Your key" is drawn at all (prd §718). With the ask off, a key
    /// on a phone that runs the on-device model does NOTHING: the librarian
    /// only spends a key where the device cannot organize for itself. A row
    /// that opens a paste field for a key that would sit unused is §83's dead
    /// control. It stays for anyone who already saved one (so they can remove
    /// it), on a device without the model, and on the Mac, where the same
    /// sheet holds the MCP listener that App Review was pointed at.
    @State private var keyRowShown = true

    private func readCounts() {
        thingCount = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
        keyedAgent = AgentKey.active
        #if targetEnvironment(macCatalyst)
        keyRowShown = true
        #else
        keyRowShown = AskSurface.enabled || keyedAgent != nil
            || !AgentLibrarian.deviceCanDoIt
        #endif
    }

    /// A corpus passing a round number is a real crossing, and this is the one
    /// screen that states the count — so the lock gives one bounce the first
    /// time we can say it, then never again for that rung. The ladder is
    /// `PostHogMilestone`'s (1-2-5 × powers of ten from 100), reused rather
    /// than reinvented for the same reason it exists there: "every 1,000" is
    /// noise for a large corpus and unreachable for a new one. Nothing is
    /// claimed if nothing was crossed — an open with no new rung is silent.
    private func markMilestone() {
        let rung = PostHogMilestone.reached(thingCount)
        guard rung > celebratedRung else { return }
        celebratedRung = rung
        rungBounce += 1
    }

    /// Group one — your things and their state. A–Z.
    private var primaryRows: [RowSpec] {
        [
            RowSpec(title: "Avatar",
                    // Set, the photo IS the fact — no words needed. It also
                    // rides the Apps nav bar as the settings entry.
                    value: "",
                    avatar: ProfileStore.shared.avatar,
                    avatarSeat: true,
                    action: {
                        if ProfileStore.shared.avatar == nil { avatarPickerOpen = true }
                        else { avatarDialogOpen = true }
                    }),
            // Your name (2026-08-29) — the greeting's second half. Sits beside
            // the photo rather than inside it: the A–Z field is one fact per
            // row, and "who am I to you" is two facts, a face and a name.
            // Unset, the value is empty (prd §784): the row itself is the door,
            // and no name is a complete state ("Good afternoon" is a whole sentence).
            RowSpec(title: "Name",
                    value: ProfileStore.shared.name ?? "",
                    badge: ("signature", DS.textPrimary),
                    action: {
                        // The draft opens on what's stored, so Save on an
                        // untouched field is a no-op rather than a wipe.
                        nameDraft = ProfileStore.shared.name ?? ""
                        nameEditorOpen = true
                    }),
            // "Data" (user ruling 2026-08-24, reversing the 2026-07-24 ruling
            // that made it "Privacy") — still the ONE home for all of it: where
            // your things live (on device / iCloud + ADP), what leaves this
            // iPhone ("What this app reaches"), previews, and the two deletes.
            // Nothing about the row's CONTENT changed; only its name. The
            // internal case has been `.data` throughout, so the label now
            // matches what the code has always called it. The badge still
            // previews sync STATE — a green on-device lock or the blue cloud —
            // which is itself the privacy fact at a glance.
            RowSpec(title: "Data", value: String(localized: "\(thingCount) things · on device"),
                    badge: icloudSync ? ("icloud.fill", DS.textPrimary) : ("lock.iphone", DS.textPrimary),
                    countsUp: true,
                    bounce: rungBounce,
                    action: { detail = .data }),
        ].sorted { $0.title < $1.title }
    }

    /// Group two — the app itself: housekeeping, rarely visited. A–Z.
    private var secondaryRows: [RowSpec] {
        // Read once per appearance into `keyedAgent` (see `readCounts`) —
        // this used to be a Keychain round trip per body evaluation.
        let keyed = keyedAgent != nil
        return [
            // The category chips' order (prd §533) — the ONE thing about the
            // source strip that was never earned by anything the person did.
            // The categories sat in a hand-authored constant, so this hands
            // that constant over. The trailing fact previews the setting the
            // way Theme's and Color's do — the first three chips, in the order
            // they will actually appear.
            //
            // "DOCK ORDER", not "chip order" (user, 2026-09-06): the strip is
            // the dock, it is the app's signature object and it has a name.
            // Naming the setting after the part rather than the thing made a
            // person map "chip" onto "dock" before they could act on it. And
            // the seats no longer learn (prd §634), so this screen is the ONLY
            // thing deciding order — which is the other half of why it should
            // be named after what it governs.
            RowSpec(title: "Dock order",
                    value: CategoryOrder.current.prefix(3).joined(separator: ", "),
                    badge: ("arrow.up.arrow.down", DS.textPrimary),
                    action: { chipOrderOpen = true }),
            // A binary choice earns a tap, not a tray with one empty screen's
            // worth of nothing below two chips (report 2026-07-09) — the row
            // itself flips, and the icon states which way.
            RowSpec(title: "Theme",
                    value: ThemeStore.shared.summary,
                    trail: .flips,
                    badge: (ThemeStore.shared.isLight ? "sun.max.fill" : "moon.fill", DS.textPrimary),
                    action: {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ThemeStore.shared.isLight.toggle() }
                    }),
            // "Color" is GONE (prd §635, 2026-09-06). It picked the crown
            // pour's hue from six swatches and defaulted to Ink, which pours
            // nothing — a settings row whose whole job was to switch on a wash
            // §524 had already ruled against. Theme (light/dark) stays; the
            // app has ONE accent and it means "you selected this".
            // Notifications (prd §306) — three classes, not a per-bridge list.
            // The trailing fact names what is actually on, so the row answers
            // "will this thing interrupt me" without opening it.
            RowSpec(title: "Notifications",
                    value: notifySummary,
                    // A fixed accent regardless of what's actually on — the
                    // badge previews no state here, so it takes the neutral
                    // tone (2026-08-10, was DS.tint).
                    badge: ("bell.badge.fill", DS.textPrimary),
                    action: { detail = .notifications }),
            // The app's own language — an override that switches Casberi live,
            // on top of the device language (LanguageStore). One tap opens the
            // tray; the trailing fact states the language in force.
            RowSpec(title: "Language",
                    value: LanguageStore.shared.summary,
                    badge: ("globe", DS.textPrimary),
                    action: { languageOpen = true }),
            // Your key (prd §67) — the BYO escape hatch: on-device by default,
            // your own agent key adds a per-answer "Try with your key".
            // Ruling 2026-07-14: it's an AGENT key — name the agents, never
            // "the Anthropic key". Keyed, the fact earns the badge's green —
            // a live connection states itself in the connected color.
            // The unkeyed value used to name all six providers, which broke
            // twice over (2026-07-31): it TRUNCATED at row width — and it had
            // already gone stale, since Grok made seven and this string still
            // said six. Naming them is the detail sheet's job (it lists every
            // provider, with state); this row only has to invite. §243 fixed
            // the same hand-listing in the key card's console line by deriving
            // it — here the honest fix is to stop listing at all.
            RowSpec(title: "Your key",
                    // With the ask off (prd §697b) a key answers nothing, so
                    // the keyed fact is just whose key it is (prd §718).
                    value: keyedAgent.map {
                       AskSurface.enabled
                           ? String.localizedStringWithFormat(
                               String(localized: "%@ answers on tap"), $0.agent)
                           : $0.agent
                    } ?? String(localized: "Bring your own agent"),
                    badge: ("key.fill", DS.textPrimary),
                    action: { detail = .key }),
            // "What you can do" (2026-07-11 as "How it works") sat here until
            // 2026-09-10 — a sheet holding one sentence, reached from a row
            // saying "New here? Start here". Deleted with the sheet (user: "it's
            // not helpful", prd §672): the intro cover says the sentence over
            // the demo on first launch, and a settings row is not the place to
            // say it again.
            // Dev-facing on purpose: TestFlight reports become a screenshot
            // of on-device facts instead of a description (2026-07-09).
            RowSpec(title: "Diagnostics",
                    value: "",
                    // The instrument, not the trace — the ECG line is the
                    // Feed tab's glyph (ruled 2026-07-10: Feed keeps it).
                    badge: ("stethoscope", DS.textPrimary),
                    action: { diagnosticsOpen = true }),
            // Support returns (2026-07-28) now that a real channel exists
            // behind it — privacy@casberi.app is a monitored inbox, not the
            // unread mailbox the 2026-07-05 removal ruling objected to. One
            // tap, one honest action: it opens Mail, nothing more (no sheet,
            // no version restated — that's Updates' job).
            RowSpec(title: "Support",
                    value: "privacy@casberi.app",
                    trail: .leaves,
                    badge: ("envelope", DS.textPrimary),
                    action: {
                        DSHaptic.tap()
                        if let url = URL(string: "mailto:privacy@casberi.app?subject=Casberi%20feedback") {
                            openURL(url)
                        }
                    }),
        ]
        .filter { $0.title != "Your key" || keyRowShown }
        .sorted { $0.title < $1.title }
    }

    /// Whether "See the demo" belongs on screen — the demo mode's re-entry
    /// door (2026-08-07, prd §217 amendment). `hasSeen` makes the fork's own
    /// demo card hide itself forever after one entry, which was correct for
    /// the fork (offering a tour of the room you just walked out of is a
    /// dead end) but left the demo enterable EXACTLY ONCE per install — the
    /// wrong shape for its actual audience, someone showing the app to other
    /// people, repeatedly, on a real phone.
    ///
    /// Gated on a DEMO-CLEAN corpus, and the gate is load-bearing, not
    /// decorative: `seedBridgeState` writes PostHog metrics named
    /// `signed_up`/`answer_asked`, and `DemoMode.exit` FORGETS those by
    /// name — on a lived-in install with a real PostHog connection, exiting
    /// a re-entered demo would destroy that person's real readings. A watched
    /// real wallet fails the same way through the seeded balance curve. So
    /// this reads true only when every connected bridge is a demo seat (by
    /// NAME) and no wallet is watched. After a clean exit `bridgeStore.bridges`
    /// is `[]`, which satisfies this trivially — re-entry is available the
    /// moment the last one ends.
    ///
    /// **Checks against `BridgeApp.demo` WHOLE, not `DemoSeedAll.seats` alone
    /// (fixed 2026-08-08, reported "I don't see the Settings row").**
    /// `BridgeApp.demo` is `[Gmail, Calendar, ChatGPT, Reminders, Photos,
    /// Claude, Wallet, Tokens] + DemoSeedAll.seats` — eight OLDER static
    /// entries that predate `DemoMode` and seed automatically on every DEBUG
    /// install that's been through onboarding (`BridgeStore.init`,
    /// `DemoState.seedsDemoData`), independent of whether `DemoMode.begin`
    /// was ever called. The first cut here only excused `DemoSeedAll.seats`,
    /// so on the ordinary case — any dev/debug install, which is EVERY
    /// install this got tested on — those eight static names failed
    /// `allSatisfy` and the row never appeared. Reading the same array
    /// `DemoMode.begin` actually writes (`store.bridges = BridgeApp.demo`)
    /// is also the more honest source of truth: this gate can never drift
    /// from what "a demo seat" means somewhere else again.
    private var demoReentryAvailable: Bool {
        guard !DemoMode.isActive else { return false }
        guard WalletStore.shared.addresses.isEmpty else { return false }
        let demoNames = Set(BridgeApp.demo.map(\.name))
        return bridgeStore.bridges.allSatisfy { demoNames.contains($0.name) }
    }

    /// A single-row group, present only when `demoReentryAvailable` — kept
    /// separate from `secondaryRows` rather than folded in with an `if`
    /// inline, since `secondaryRows`' A–Z sort would otherwise need to run
    /// twice (once to build the base list, once after a conditional insert)
    /// for one row.
    private var demoRow: [RowSpec] {
        guard demoReentryAvailable else { return [] }
        return [RowSpec(
            title: "See the demo",
            value: String(localized: "Sample data from every source"),
            badge: ("eye", DS.textPrimary),
            action: {
                DSHaptic.tap()
                DemoMode.begin(store: bridgeStore)
                // Land on the feed BEFORE the pour starts, the same split
                // the fork card and the greeting's CTA both use — a feed
                // revealed already full reads as a screenshot, watched
                // filling it reads as what the app does.
                route.path = []
                Task { @MainActor in
                    await DemoMode.pourIfNeeded(context: modelContext)
                }
            })]
    }

    /// Every row in one A–Z field — the You/App groups are retired.
    private var allRows: [RowSpec] {
        (primaryRows + secondaryRows + demoRow).sorted { $0.title < $1.title }
    }

    /// The colophon — mark, name, build — at the very foot of Settings, below
    /// the last row rather than inside a group, because it is a signature and
    /// not a setting.
    ///
    /// It is deliberately NOT a control. §83 bans dead controls, and this is
    /// the distinction that keeps it honest: a control carries an affordance
    /// (a tile surface, a chevron, a tap target) and must then do something.
    /// This carries none, so nothing about it offers to be pressed. The one
    /// place a logo may sit doing nothing is the bottom of Settings, where the
    /// question it answers — what is this, and which build am I on — is real.
    ///
    /// The name is set in the app's own ramp rather than the brand face. The
    /// wordmark is Figtree SemiBold on the website (`docs/brand.md`), and
    /// bundling a display face to render seven letters once would cost Dynamic
    /// Type's optical sizing, break for the four localizations Figtree has no
    /// glyphs for, and need the heavier app-embedding licence — for a string
    /// nobody reads twice. Semibold lowercase in the brand hue lands within a
    /// hair of it and stays inside §8.
    ///
    /// That claim was FALSE until 2026-08-28: this drew `.system(size: 17,
    /// weight: .semibold)` and `.footnote` — a frozen size that is not even a
    /// rung (`heading17` has been 18 since the reading-band pass) and the app's
    /// only semantic system style. Both were invisible at the default text
    /// size and neither grew with it, which is the whole reason `dsText`
    /// exists. The paragraph above described the fix for eleven weeks before
    /// anything did it; the ramp audit could not see it, because it scopes
    /// itself to glyphs and marks.
    private var colophon: some View {
        VStack(spacing: DS.Space.s2) {
            CasberiMark(size: 36)
            Text(verbatim: "casberi")
                .dsText(.heading17)
                .foregroundStyle(CasberiMark.pink)
            Text(buildLine)
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s6)
        // One label, so VoiceOver reads a signature instead of three orphans.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Casberi, \(buildLine)"))
    }

    /// Marketing version and build, the pair a bug report needs. Both are read
    /// from the bundle rather than typed, so a shipped build can never claim a
    /// number it isn't.
    private var buildLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(localized: "Version \(v) (\(b))")
    }

    private func rowList(_ rows: [RowSpec]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.title) { row in
                Button(action: row.action) {
                    AccountRow(title: row.title, value: row.value,
                               trail: row.trail,
                               avatar: row.avatar,
                               avatarSeat: row.avatarSeat,
                               badge: row.badge,
                               countsUp: row.countsUp,
                               bounce: row.bounce)
                }
                .buttonStyle(DSTileButtonStyle())
            }
        }
        .padding(.vertical, DS.Space.s2)
        .padding(.horizontal, DS.Space.s4)
    }
}

/// A Settings row in the feed's grammar: glyph seat leading, title, the live
/// fact trailing. The avatar row seats the photo — identity earns the image.
struct AccountRow: View {
    /// What the tap does, said at the row's end (prd §767): a door takes the
    /// chevron, a trip out of the app takes the arrow, a flip in place takes
    /// nothing — the glyph swapping is the answer.
    enum Trail { case opens, flips, leaves }

    let title: String
    let value: String
    var trail: Trail = .opens
    var avatar: UIImage? = nil
    var avatarSeat = false
    var badge: (symbol: String, color: Color)? = nil
    var countsUp = false
    var bounce = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// THE PUSH ROW'S ANATOMY (prd §764, §767): a 26pt lead, a regular 17pt
    /// title, the fact at 12pt in the tertiary tier, then the trail. It was a
    /// 34pt tinted squircle, an 18pt title and a 17pt fact — the only rows in
    /// the app on those three numbers — with three lead species (a seal, a
    /// green lock, gray squares) and a green fact for a saved key.
    var body: some View {
        HStack(spacing: DS.Space.s3) {
            lead
                .frame(width: DS.Mark.row, height: DS.Mark.row)
            // The title doubles as its own catalog key — localized at render
            // so the stored English still drives sort/id.
            Text(LocalizedStringKey(title))
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if !value.isEmpty {
                // A fact that leads with a live number arrives by counting to
                // it (CountUpText renders any other shape plainly).
                Group {
                    if countsUp, !reduceMotion { CountUpText(text: value) }
                    else { Text(value) }
                }
                .dsText(.subhead12)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            }
            switch trail {
            case .opens:  DSPushRowTrail()
            case .leaves: DSPushRowTrail(glyph: "arrow.up.right")
            case .flips:  EmptyView()
            }
        }
        .padding(.vertical, DS.Space.s3)
        .contentShape(Rectangle())
    }

    /// The avatar row seats the photo — identity earns the image. Every other
    /// row leads with the glyph disc the head rows and Readings rows wear.
    @ViewBuilder private var lead: some View {
        if avatarSeat {
            AvatarSeat(avatar: avatar, size: DS.Mark.row)
        } else if let avatar {
            Image(uiImage: avatar)
                .resizable().scaledToFill()
                .frame(width: DS.Mark.row, height: DS.Mark.row)
                .clipShape(Circle())
        } else if let badge {
            DSGlyphLead(glyph: badge.symbol, tint: badge.color, bounce: bounce)
        }
    }
}

/// The photo seat — the app's own face until a photo lands, the photo after.
/// Setting your picture is the most personal act on this screen, so the swap
/// is a card turn rather than a cross-fade: one 3D flip and one success tick,
/// the moment the seal hands the seat over. Only ever on the way IN — removing
/// a photo is an undo, and an undo doesn't get a flourish.
private struct AvatarSeat: View {
    let avatar: UIImage?
    let size: CGFloat
    @State private var spin: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let avatar {
                Image(uiImage: avatar)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                CasberiSeal(size: size)
            }
        }
        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
        .onChange(of: avatar != nil) { _, has in
            guard has else { return }
            DSHaptic.success()
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { spin += 360 }
        }
    }
}

/// Tile press feedback — a slight settle, like the system's.
struct DSTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.standard, value: configuration.isPressed)
    }
}

