import SwiftUI
import SwiftData

/// "What should I start with?" — the onboarding fork (prd §217, 2026-07-25).
///
/// The problem it solves: onboarding was one greeting straight into a catalog
/// of ~40 apps, so a new person had to PICK something, CONNECT it, and WAIT
/// for a sync before the app did anything. Three steps and a wait before any
/// evidence it was worth having — while the brief, the themes map, the wallet
/// hero and the whole continuity memory stayed invisible until a corpus
/// existed.
///
/// **Why three, and why these three.** Casberi has more than one audience, and
/// forcing a single first source means half of new users get a demo of
/// something they didn't come for (user, 2026-07-25: "we have users that are
/// here for crypto wallets, what if they don't care about photos"). So the fork
/// covers the three real ones: your own files (a folder), money (a wallet),
/// reading (someone to follow). Three is a fork you answer in a second; forty
/// is a wall you have to survey.
///
/// **Why a folder, not screenshots (2026-07-28).** The first card used to be
/// "Show me my screenshots" (Photos permission → the screenshot library).
/// Swapped for "Show me my files" — the system folder picker (`Model/
/// FilesBridge.swift`) — because it's a stronger first proof: one tap on a
/// folder like Downloads or an iCloud Drive folder lands real, personally
/// meaningful files (PDFs, docs, whatever's actually in there) rather than
/// just screenshots, and it reads as evidence the app can hold ANYTHING, not
/// one narrow category. Screenshots ingest is unchanged and still reachable
/// from the catalog — this only changes which door onboarding opens first.
///
/// **Why this is not the connect screen that died (prd §96).** That screen was
/// a LIST of sources with toggles — four simultaneous standing asks, all
/// abstract, none of them showing you anything, which is exactly why it read as
/// invasive. These are three VERBS with visible outcomes, phrased in the first
/// person, and one tap produces real rows from your own life. The old screen
/// asked for a relationship; this asks for an outcome. The tripwire, if this is
/// ever redesigned: **the moment a card grows a toggle it is a settings page
/// again** and should be deleted a second time.
///
/// Pick-ONE, not do-any: a screen where you can do three things is a screen you
/// can get stuck on, and the whole point is to be out of onboarding looking at
/// your own things. The escape hatch is "Browse the catalog instead" rather
/// than "Skip" — skip lands you nowhere, this lands you where the old CTA went,
/// so nothing is lost for someone who came to browse.
///
struct StartHereScreen: View {
    /// Ends onboarding. A non-nil node is where to land afterwards (the wallet
    /// manager, the catalog); nil means the feed, which is the right answer
    /// whenever the tap already produced something to look at.
    var onStart: (HomeRoute.Node?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    /// The files card is the one option that does its work HERE rather than
    /// handing off to a screen, so it needs its own in-place state — the
    /// picker plus a folder walk is seconds, not instant, and a card that
    /// looked inert while working would read as a dead control.
    @State private var pickingFolder = false
    @State private var connectingFolder = false
    @State private var showFollow = false
    /// The demo card acts in place like the files card — seeding ~330 rows
    /// and their bridge state is fast but not instant, and a card that looked
    /// inert while working would read as a dead control.
    @State private var enteringDemo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // A question about THEM, not a configuration step — the
                    // difference between this screen and the one that died.
                    Text("What should I start with?")
                        .dsText(.heading34).fontWeight(.heavy)
                        .foregroundStyle(DS.textPrimary)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick one. The rest can wait.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.s2)
                .startArrive(arrived, delay: 0.05)

                card(figure: .treemap, hue: .blue,
                     title: "Show me my files",
                     line: "Pick any folder — Downloads, iCloud Drive, anywhere.",
                     cost: "Opens the Files picker",
                     busy: connectingFolder) {
                    DSHaptic.tap()
                    pickingFolder = true
                }
                .startArrive(arrived, delay: 0.15)

                card(figure: .curve, hue: .green,
                     title: "Watch a wallet",
                     line: "Enter an ENS, paste an address, or connect your wallet app.",
                     cost: "No account needed") {
                    // The wallet manager already IS all three doors (§202's
                    // roster and §188's "Connect a wallet app" button), so this
                    // hands off rather than growing a fourth address field.
                    DSHaptic.tap()
                    onStart(.bridge(.wallet))
                }
                .startArrive(arrived, delay: 0.25)

                card(figure: .faces, hue: .purple,
                     title: "Follow someone I read",
                     line: "A Bluesky or Farcaster handle, or a feed.",
                     cost: "No sign-in") {
                    DSHaptic.tap()
                    showFollow = true
                }
                .startArrive(arrived, delay: 0.35)

                // The fourth answer — and it is HIDDEN once the demo has been
                // seen, which is the common case now that it is the greeting's
                // own CTA. This screen's main job since 2026-08-07 is to catch
                // someone LEAVING the demo, and offering to re-enter the thing
                // they just chose to leave is a door back into a room they
                // walked out of.
                if !DemoMode.hasSeen {
                    card(figure: .sparkle, hue: .orange,
                         title: "Just show me what it looks like",
                         line: "Sample data from every source. Leave it any time.",
                         cost: "Nothing to connect",
                         busy: enteringDemo) {
                        DSHaptic.tap()
                        enterDemo()
                    }
                    .startArrive(arrived, delay: 0.45)
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        // The cards scroll UNDER the "See all N apps" link below
        // (`safeAreaInset(edge: .bottom)`), and that link is deliberately bare
        // secondary text rather than a button — so with nothing dissolving the
        // content as it arrives, a card passing beneath put gray text straight
        // on top of a moving tile (2026-08-10). Every other scrolling screen in
        // the app already wears this; this one was simply missed.
        //
        // The fix is the scroll edge and NOT glass on the link: a glass capsule
        // would fix the legibility by promoting the link to button weight,
        // which is exactly what the sibling ruling in `HowItWorksSheet`
        // ("Text, not a second button: two equal buttons is a decision") exists
        // to prevent on this same fork.
        .dsSoftScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showFollow) {
            StartFollowScreen(onStart: onStart)
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { outcome in
            guard case .success(let url) = outcome else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if FilesStore.shared.setFolder(url: url) {
                connectFolder()
            } else {
                chrome.flash("Couldn't keep access to that folder — try again from the catalog")
                onStart(nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Named by what it DOES, not by what it isn't (2026-08-07). It read
            // "Browse the catalog instead", which was written when this link
            // was only an escape hatch from onboarding — it is now also the
            // main route for someone arriving here from the demo who already
            // knows which app they want, and "instead" framed that person's
            // deliberate choice as a way out of the real one.
            //
            // The COUNT is gone again (user, 2026-08-11): "See all 96 apps" made
            // the number the argument, and a number is a claim to survey rather
            // than a destination to go to. This says where the tap lands, in the
            // app's own noun for that surface (the 2026-07-16 naming ruling: it
            // is "the catalog", never a store).
            Button {
                DSHaptic.tap()
                onStart(.apps)
            } label: {
                Text("Browse the catalog")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s2)
        }
        .tint(DS.tint)
        .onAppear {
            if reduceMotion { arrived = true }
            else { withAnimation(DS.Motion.standard) { arrived = true } }
        }
        #if DEBUG
        // `-startPick folder|wallet|follow|catalog` fires one card after a
        // beat, so each arm of the fork verifies headlessly. The folder arm
        // can only OPEN the system picker (`fileImporter`, like every other
        // document-picker/sign-in hop in this app, can't be driven headless)
        // — pair with `-startFolder <path>` below to land files without
        // touching the picker at all.
        .onAppear {
            guard let pick = UserDefaults.standard.string(forKey: "startPick"),
                  !pick.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                NSLog("[Casberi] startPick: %@", pick)
                switch pick {
                case "folder":  pickingFolder = true
                case "wallet":  onStart(.bridge(.wallet))
                case "follow":  showFollow = true
                case "demo":    enterDemo()
                default:        onStart(.apps)
                }
            }
        }
        // `-startFolder <path>` connects a folder by path directly, bypassing
        // the picker entirely — the only way to exercise the landing path
        // (setFolder → FilesIngest.refresh → registerConnected) headlessly.
        .onAppear {
            guard let path = UserDefaults.standard.string(forKey: "startFolder"),
                  !path.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                NSLog("[Casberi] startFolderProbe: %@", path)
                if FilesStore.shared.setFolder(url: URL(fileURLWithPath: path)) {
                    connectFolder()
                } else {
                    NSLog("[Casberi] startFolderProbe: couldn't bookmark %@", path)
                }
            }
        }
        #endif
    }

    /// The one card that acts in place. A folder that can't be read is NOT a
    /// dead end — the person still leaves onboarding (into the feed, where
    /// the catalog door is), and the flash says what happened rather than
    /// leaving the tap unexplained.
    private func connectFolder() {
        guard !connectingFolder else { return }
        connectingFolder = true
        Task { @MainActor in
            let added = await FilesIngest.refresh(context: modelContext)
            connectingFolder = false
            NSLog("[Casberi] startFolder: %@", added.map { "\($0) in" } ?? "unreadable")
            guard let added else {
                FilesStore.shared.disconnect()
                chrome.flash("Couldn't read that folder — try again from the catalog")
                onStart(nil)
                return
            }
            let proof = added > 0
            ? String(localized: "\(added) files in")
            : String(localized: "Synced just now")
            _ = store.registerConnected(id: "files", name: "Files", proof: proof,
                                        can: ["Reads the folder you picked.",
                                              "Read-only — never edits a file."])
            onStart(nil)
        }
    }

    /// Furnish the app and land in the feed.
    ///
    /// `onStart(nil)` rather than a node: the tap has already produced
    /// something to look at, which is exactly the case the nil arm exists for.
    private func enterDemo() {
        guard !enteringDemo else { return }
        enteringDemo = true
        DemoMode.begin(store: store)
        // Claim the mode, hand back, and let the pour happen where it can be
        // SEEN — same split as the greeting's CTA, and the reason is the same:
        // a feed revealed already full reads as a screenshot.
        onStart(nil)
    }

    /// One shape for all three, so the fork reads as one decision rather than
    /// three offers of different weight. No chevron and no toggle: each of
    /// these is a button that DOES something (see the tripwire above).
    /// `cost` is the three-word answer to "what will this ask of me?" — a
    /// picker, a paste, a sign-in. It exists because the cards were four
    /// identically-weighted offers with no way to tell which one wanted a
    /// system permission and which wanted nothing, and that ambiguity is
    /// exactly what makes someone back out to the previous screen rather than
    /// tap. It is a FACT about the next tap, never a reassurance.
    private func card(figure: StartFigure, hue: Color, title: LocalizedStringKey,
                      line: LocalizedStringKey, cost: LocalizedStringKey? = nil,
                      busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: DS.Space.s4) {
                ZStack {
                    if busy {
                        ProgressView().tint(hue)
                    } else {
                        StartFigureMark(figure: figure, hue: hue)
                    }
                }
                .frame(width: 54, height: 54)
                .background(hue.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dsText(.heading22)
                        .foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(line)
                        .dsText(.callout15)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let cost {
                        Text(cost)
                            .dsText(.subhead13)
                            .foregroundStyle(hue)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsWidgetSurface()
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget,
                                           style: .continuous))
        }
        .buttonStyle(PressSpring())
        .disabled(busy)
    }
}

/// What a card's tap PRODUCES, drawn as the figure that room will wear.
enum StartFigure { case treemap, curve, faces, sparkle }

/// The mark on a fork card — the figure the source becomes, not a glyph for
/// the category it belongs to.
///
/// **Why it changed (2026-08-07).** Four cards wearing four tinted SF Symbols
/// read as four equal-weight menu items: the glyph names the KIND of thing
/// ("a folder", "a wallet") and says nothing about what you get. That was
/// tolerable while the fork ran before anyone had seen the app. It is wasteful
/// now that the fork runs AFTER the demo, because the person arriving here has
/// just watched a treemap tile itself, a balance curve draw and a roster fill —
/// so a card can answer "how do I get that?" by simply showing the figure
/// again, at card scale, in the card's own hue.
///
/// **Two rules, both load-bearing.**
///
/// The figures are GENERIC SHAPE ONLY — no number, no label, no plausible
/// data. A mark that carried "$12,480" or a real-looking file name would be a
/// claim about what YOUR wallet holds or what YOUR folder contains, made on
/// the screen where trust is being established and before a single thing has
/// been read. That is §83 at its most expensive. A rising line says "this
/// becomes a curve"; it must never say "your curve rises".
///
/// And they have NO ENTRANCE OF THEIR OWN. The cards already arrive on
/// `startArrive`'s stagger, so an animated figure would be a second entrance
/// on the same element — which the design-motion audit would flag, and would
/// be right to.
struct StartFigureMark: View {
    let figure: StartFigure
    let hue: Color

    var body: some View {
        switch figure {
        case .treemap:
            // The Files room's own hero, at card scale: one dominant cell and
            // a smaller tail, which is what a real folder's treemap looks like.
            HStack(spacing: 2.5) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(hue)
                    .frame(width: 16, height: 27)
                VStack(spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(hue.opacity(0.62))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(hue.opacity(0.36))
                }
                .frame(width: 10, height: 27)
            }
        case .curve:
            // The balance line, with its endpoint emphasised the way the real
            // sparkline emphasises the latest sample.
            StartCurveShape()
                .stroke(hue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                                lineJoin: .round))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(hue).frame(width: 6.5, height: 6.5)
                        .offset(x: 1.5, y: -1.5)
                }
                .frame(width: 30, height: 24)
        case .faces:
            // A roster: people, overlapping, the way every follow room draws
            // them. The ring is the CARD's fill, so the stack reads as lifted
            // off the surface rather than as three flat discs.
            HStack(spacing: -5) {
                ForEach(Array([1.0, 0.72, 0.46].enumerated()), id: \.offset) { _, dose in
                    Circle()
                        .fill(hue.opacity(dose))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(DS.surfaceSheet, lineWidth: 2.5))
                }
            }
        case .sparkle:
            // The demo is not one figure — it is all of them — so it keeps a
            // glyph rather than pretending to preview a single room.
            Image(systemName: "sparkles")
                .dsGlyph(24)
                .foregroundStyle(hue)
        }
    }
}

/// A rising line with one dip, normalised to its rect. Hand-placed rather than
/// random: a figure that reshuffles between launches reads as data.
private struct StartCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            CGPoint(x: 0.00, y: 0.82), CGPoint(x: 0.19, y: 0.58),
            CGPoint(x: 0.35, y: 0.68), CGPoint(x: 0.52, y: 0.30),
            CGPoint(x: 0.68, y: 0.44), CGPoint(x: 0.85, y: 0.12),
            CGPoint(x: 1.00, y: 0.20),
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: rect.minX + point.x * rect.width,
                                 y: rect.minY + point.y * rect.height)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        return path
    }
}

/// The third card's form. A segmented picker over one field rather than a
/// network sniffer: `alice.bsky.social`, `dwr` and an RSS URL are genuinely
/// ambiguous, and guessing wrong on the very first thing someone types is a
/// worse first impression than asking. §186's ruling applies — a connect screen
/// is allowed to be a form, because knowing the steps is the point.
struct StartFollowScreen: View {
    var onStart: (HomeRoute.Node?) -> Void

    /// The three keyless follow paths — no account, no key, no permission, so
    /// this whole screen can produce real rows without asking for anything.
    private enum Network: String, CaseIterable, Identifiable {
        case bluesky = "Bluesky", farcaster = "Farcaster", feed = "Feed"
        var id: String { rawValue }
        var noun: String {
            switch self {
            case .bluesky:   "handle"
            case .farcaster: "username"
            case .feed:      "feed URL"
            }
        }
        var example: String {
            switch self {
            case .bluesky:   "alice.bsky.social"
            case .farcaster: "alice"
            case .feed:      "https://example.com/feed.xml"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome
    @State private var network: Network = .bluesky
    @State private var name = ""
    @State private var working = false
    @FocusState private var fieldFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Who do you read?")
                    .dsText(.heading34).fontWeight(.heavy)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.top, DS.Space.s2)
                Text("Their posts land in your feed. No account, no password — a public name is all this takes.")
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Network", selection: $network) {
                    ForEach(Network.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("Their \(network.noun)")
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                BridgeFieldRow(placeholder: network.example,
                               text: $name,
                               buttonLabel: "Follow",
                               focus: $fieldFocused,
                               action: follow)
                // Farcaster's pack (2026-08-08) — this screen otherwise
                // requires already knowing a name, which is exactly the
                // wall a starter pack exists to route around. Shown only
                // for Farcaster: Bluesky's own pack lives one screen later,
                // on its setup screen, once connected.
                if network == .farcaster {
                    Text("or")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    // Syncs the moment the follow lands (sheet still open,
                    // "Followed N" showing) but only ENDS onboarding once
                    // the tray actually closes — calling `onStart` while the
                    // sheet is still presented would tear down this screen
                    // out from under it, the dismiss-during-transition class
                    // of bug this codebase's SwiftData liveness corollaries
                    // exist to avoid (see CLAUDE.md's build-142 note).
                    FarcasterPackDoor(
                        onImport: { _ in
                            Task { @MainActor in _ = await FarcasterIngest.refresh(context: modelContext) }
                        },
                        onDismissAfterFollow: { onStart(nil) }
                    )
                }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        // The follow form's own scroll, same treatment — it has no bottom
        // inset of its own, but it does sit under the shell's agent bar like
        // every other screen, which is the pairing this modifier was widened
        // for in 2026-07-23.
        .dsSoftScrollEdges()
        .navigationBarTitleDisplayMode(.inline)
        .tint(DS.tint)
        .onAppear { fieldFocused = true }
        #if DEBUG
        // `-startFollow "<Bluesky|Farcaster|Feed>:<name>"` runs this arm
        // headlessly — splits on the FIRST colon so a feed URL keeps its own.
        .onAppear {
            guard let spec = UserDefaults.standard.string(forKey: "startFollow"),
                  let cut = spec.firstIndex(of: ":") else { return }
            let net = String(spec[spec.startIndex..<cut])
            name = String(spec[spec.index(after: cut)...])
            network = Network.allCases.first { $0.rawValue.lowercased() == net.lowercased() } ?? .bluesky
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                follow()
            }
        }
        #endif
    }

    /// Follows, syncs, and leaves — landing in the feed, where what just
    /// arrived is the thing to look at. A failure still ends onboarding and
    /// says so: stranding someone on a form is worse than an honest miss.
    private func follow() {
        let handle = trimmed
        guard !handle.isEmpty, !working else { return }
        working = true
        DSHaptic.tap()
        Task { @MainActor in
            let landed: Int?
            switch network {
            case .bluesky:
                BlueskyStore.shared.add(handle)
                landed = await BlueskyIngest.refresh(context: modelContext)
            case .farcaster:
                FarcasterStore.shared.add(handle)
                landed = await FarcasterIngest.refresh(context: modelContext)
            case .feed:
                RSSStore.shared.add(handle)
                landed = await RSSIngest.refresh(context: modelContext)
            }
            working = false
            NSLog("[Casberi] startFollow: %@ %@ → %@", network.rawValue, handle,
                  landed.map { "\($0) in" } ?? "FAILED")
            if landed == nil {
                chrome.flash("Couldn't reach \(network.rawValue) — try again from the catalog")
            }
            onStart(nil)
        }
    }
}

private extension View {
    /// The fork's entrance — the same one-curve stagger the greeting's steps
    /// use, so the two screens read as one arc.
    func startArrive(_ on: Bool, delay: Double) -> some View {
        modifier(StartArrive(on: on, delay: delay))
    }
}

private struct StartArrive: ViewModifier {
    let on: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on || reduceMotion ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : DS.Motion.standard.delay(delay), value: on)
    }
}
