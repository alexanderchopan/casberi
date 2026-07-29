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
                    Text("Pick one. You can add the rest any time.")
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.s2)
                .startArrive(arrived, delay: 0.05)

                card(glyph: "folder.badge.plus", hue: .blue,
                     title: "Show me my files",
                     line: "Pick any folder — Downloads, iCloud Drive, anywhere.",
                     busy: connectingFolder) {
                    DSHaptic.tap()
                    pickingFolder = true
                }
                .startArrive(arrived, delay: 0.15)

                card(glyph: "wallet.bifold.fill", hue: .green,
                     title: "Watch a wallet",
                     line: "Enter an ENS, paste an address, or connect your wallet app.") {
                    // The wallet manager already IS all three doors (§202's
                    // roster and §188's "Connect a wallet app" button), so this
                    // hands off rather than growing a fourth address field.
                    DSHaptic.tap()
                    onStart(.bridge(.wallet))
                }
                .startArrive(arrived, delay: 0.25)

                card(glyph: "at", hue: .purple,
                     title: "Follow someone I read",
                     line: "A Bluesky or Farcaster handle, or a feed.") {
                    DSHaptic.tap()
                    showFollow = true
                }
                .startArrive(arrived, delay: 0.35)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
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
            // Not "Skip": this lands where the old CTA went, so someone who
            // came to browse loses nothing.
            Button {
                DSHaptic.tap()
                onStart(.apps)
            } label: {
                Text("Browse the catalog instead")
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
            let proof = added > 0 ? "\(added) files in" : "Synced just now"
            _ = store.registerConnected(id: "files", name: "Files", proof: proof,
                                        can: ["Reads the folder you picked.",
                                              "Read-only — never edits a file."])
            onStart(nil)
        }
    }

    /// One shape for all three, so the fork reads as one decision rather than
    /// three offers of different weight. No chevron and no toggle: each of
    /// these is a button that DOES something (see the tripwire above).
    private func card(glyph: String, hue: Color, title: LocalizedStringKey,
                      line: LocalizedStringKey, busy: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: DS.Space.s4) {
                ZStack {
                    if busy {
                        ProgressView().tint(hue)
                    } else {
                        Image(systemName: glyph)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(hue)
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
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .dsAdaptiveContentWidth()
        .dsPageBackground()
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
