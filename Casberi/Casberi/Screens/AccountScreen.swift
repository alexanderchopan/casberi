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
    /// Drives the Data tile's badge: a green lock on device, a blue cloud once
    /// the person turns iCloud sync on.
    @AppStorage("icloud.sync") private var icloudSync = false
    /// The highest round number the corpus has been congratulated for, so a
    /// crossing is celebrated once and never re-celebrated on the next open.
    @AppStorage("settings.thingsRung") private var celebratedRung = 0
    @State private var rungBounce = 0
    @State private var diagnosticsOpen = false
    @State private var languageOpen = false
    @State private var howItWorksOpen = false
    @State private var detail: AccountDetail?

    /// What the Notifications row says without being opened. Names the classes
    /// that are ON rather than a count — "2 of 3" tells you nothing about
    /// whether a dispute would reach you.
    private var notifySummary: String {
        let s = Notifications.settings
        var on: [String] = []
        if s.alarms { on.append(String(localized: "Alarms")) }
        if s.arrivals { on.append(String(localized: "Arrivals")) }
        if s.whisper { on.append(String(localized: "Whisper")) }
        return on.isEmpty ? String(localized: "Off") : on.joined(separator: ", ")
    }
    @State private var avatarPickerOpen = false
    @State private var avatarDialogOpen = false
    @State private var avatarSelection: PhotosPickerItem?

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // One parcel, no group headers — every row in one A–Z
                    // field. (A big avatar hero lived here for an hour on
                    // 2026-07-10 and was rejected: personalization paints your
                    // SPACE — it never builds a profile of you.)
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
            .dsScreenTitle("Settings")
            .onAppear { markMilestone() }
            .sheet(isPresented: $diagnosticsOpen) {
                NavigationStack { DiagnosticsScreen() }.dsMacPageSheet()
            }
            .sheet(item: $detail) { AccountDetailSheet(detail: $0) }
            .sheet(isPresented: $languageOpen) { LanguagePickerSheet() }
            .sheet(isPresented: $howItWorksOpen) { HowItWorksSheet().dsMacPageSheet() }
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
                if UserDefaults.standard.bool(forKey: "openHowItWorks") {
                    howItWorksOpen = true
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
        var valueColor: Color = DS.textTertiary
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

    /// Live count for the Data row — the number that leads its story.
    private var thingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
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
                    value: ProfileStore.shared.avatar == nil ? String(localized: "Add your photo") : "",
                    avatar: ProfileStore.shared.avatar,
                    avatarSeat: true,
                    action: {
                        if ProfileStore.shared.avatar == nil { avatarPickerOpen = true }
                        else { avatarDialogOpen = true }
                    }),
            // "Privacy", not "Data" (user, 2026-07-24) — the ONE privacy home:
            // where your things live (on device / iCloud + ADP), what leaves
            // this iPhone ("What this app reaches"), previews, and the two
            // deletes. A privacy-curious person has one obvious place to tap,
            // and there's no second privacy-ish row to compete with it. The
            // badge still previews sync STATE — a green on-device lock or the
            // blue cloud — which is itself the privacy fact at a glance.
            RowSpec(title: "Privacy", value: String(localized: "\(thingCount) things · on device"),
                    badge: icloudSync ? ("icloud.fill", DS.tint) : ("lock.iphone", DS.confirm),
                    countsUp: true,
                    bounce: rungBounce,
                    action: { detail = .data }),
        ].sorted { $0.title < $1.title }
    }

    /// Group two — the app itself: housekeeping, rarely visited. A–Z.
    private var secondaryRows: [RowSpec] {
        // One Keychain read per render, not two (the row needs it twice).
        let keyedAgent = AgentKey.active
        let keyed = keyedAgent != nil
        return [
            // A binary choice earns a tap, not a tray with one empty screen's
            // worth of nothing below two chips (report 2026-07-09) — the row
            // itself flips, and the icon states which way.
            RowSpec(title: "Theme",
                    value: ThemeStore.shared.summary,
                    badge: (ThemeStore.shared.isLight ? "sun.max.fill" : "moon.fill", DS.textSecondary),
                    action: {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ThemeStore.shared.isLight.toggle() }
                    }),
            // The crown pour's color (prd §204) — six curated, and OFF by
            // default (Ink). The badge wears the CHOSEN color itself (not a
            // fixed secondary gray like Theme's sun/moon), so the row
            // previews its own setting the way Data's icloud badge previews
            // sync state. `bleedMark`, not `bleed`: Ink is the no-pour option
            // (2026-08-04) and drawing its black here would be an invisible
            // badge, so it falls back to Theme's own secondary gray.
            RowSpec(title: "Color",
                    value: ThemeStore.shared.bleed.name,
                    badge: ("paintbrush.pointed.fill", DS.bleedMark),
                    action: { detail = .color }),
            // Notifications (prd §306) — three classes, not a per-bridge list.
            // The trailing fact names what is actually on, so the row answers
            // "will this thing interrupt me" without opening it.
            RowSpec(title: "Notifications",
                    value: notifySummary,
                    // A fixed accent regardless of what's actually on — the
                    // badge previews no state here, so it takes the neutral
                    // tone (2026-08-10, was DS.tint).
                    badge: ("bell.badge.fill", DS.neutralBadge),
                    action: { detail = .notifications }),
            // The app's own language — an override that switches Casberi live,
            // on top of the device language (LanguageStore). One tap opens the
            // tray; the trailing fact states the language in force.
            RowSpec(title: "Language",
                    value: LanguageStore.shared.summary,
                    badge: ("globe", DS.textSecondary),
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
                    value: keyedAgent.map {
                       String.localizedStringWithFormat(
                           String(localized: "%@ answers on tap"), $0.agent)
                    } ?? String(localized: "Bring your own agent"),
                    valueColor: keyed ? DS.confirm : DS.textTertiary,
                    badge: ("key.fill", keyed ? DS.confirm : DS.textSecondary),
                    action: { detail = .key }),
            // The one persistent explainer of the model (2026-07-11) — for
            // a new person after the coach lines retire. "How it works", not
            // "About" (About reads as version/legal).
            RowSpec(title: "How it works",
                    value: String(localized: "New here? Start here"),
                    badge: ("questionmark.circle", DS.textSecondary),
                    action: { howItWorksOpen = true }),
            // Dev-facing on purpose: TestFlight reports become a screenshot
            // of on-device facts instead of a description (2026-07-09).
            RowSpec(title: "Diagnostics",
                    value: String(localized: "Test and report"),
                    // The instrument, not the trace — the ECG line is the
                    // Feed tab's glyph (ruled 2026-07-10: Feed keeps it).
                    badge: ("stethoscope", DS.textSecondary),
                    action: { diagnosticsOpen = true }),
            // Support returns (2026-07-28) now that a real channel exists
            // behind it — privacy@casberi.app is a monitored inbox, not the
            // unread mailbox the 2026-07-05 removal ruling objected to. One
            // tap, one honest action: it opens Mail, nothing more (no sheet,
            // no version restated — that's Updates' job).
            RowSpec(title: "Support",
                    value: String(localized: "Email us"),
                    badge: ("envelope", DS.textSecondary),
                    action: {
                        DSHaptic.tap()
                        if let url = URL(string: "mailto:privacy@casberi.app?subject=Casberi%20feedback") {
                            openURL(url)
                        }
                    }),
        ].sorted { $0.title < $1.title }
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
            badge: ("sparkles", .orange),
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
    private var colophon: some View {
        VStack(spacing: DS.Space.s2) {
            CasberiMark(size: 36)
            Text(verbatim: "casberi")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CasberiMark.pink)
            Text(buildLine)
                .font(.footnote)
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
                               valueColor: row.valueColor,
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
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
    }
}

/// A Settings row in the feed's grammar: glyph seat leading, title, the live
/// fact trailing. The avatar row seats the photo — identity earns the image.
struct AccountRow: View {
    let title: String
    let value: String
    var valueColor: Color = DS.textTertiary
    var avatar: UIImage? = nil
    var avatarSeat = false
    var badge: (symbol: String, color: Color)? = nil
    var countsUp = false
    var bounce = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if avatarSeat {
                AvatarSeat(avatar: avatar, size: 34)
            } else if let avatar {
                Image(uiImage: avatar)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else if let badge {
                // The row's trust mark: the same colored-glyph-in-a-squircle
                // the Apps page speaks — `IconChip`'s `.wash` style since
                // 2026-08-10.
                IconChip(tone: badge.color, size: 34, style: .wash) {
                    Image(systemName: badge.symbol)
                        .accessibilityHidden(true)
                        .dsGlyph(16)
                        // Two rows genuinely SWAP their glyph rather than
                        // opening anything — Theme's sun/moon and
                        // Privacy's lock/cloud — and for a setting that
                        // flips in place the swap IS the feedback. A row
                        // whose symbol never changes never transitions,
                        // so this costs the others nothing.
                        .contentTransition(reduceMotion ? .identity
                                           : .symbolEffect(.replace.downUp))
                        .symbolEffect(.bounce, value: bounce)
                }
            }
            // The title doubles as its own catalog key — localized at
            // render so the stored English still drives sort/id.
            Text(LocalizedStringKey(title))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if !value.isEmpty {
                // A fact that leads with a live number arrives by counting to
                // it (CountUpText renders any other shape plainly, including
                // a translation that doesn't lead with the digits).
                Group {
                    if countsUp, !reduceMotion { CountUpText(text: value) }
                    else { Text(value) }
                }
                .dsText(.callout15).foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .contentShape(Rectangle())
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

