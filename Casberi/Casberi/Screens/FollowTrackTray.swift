import SwiftUI
import SwiftData

/// **THE VERB OF A FOLLOW LIST, IN ITS ROOM (prd §1118).** Media's Track a
/// subscription and Work's Watch something: pick the app, type the name, and
/// it joins the list the tray closes onto. Each app follows through the add
/// and the read its own page already has (`HandleBridge`, `PackageStore`,
/// `HuggingFaceStore`, `RadicleStore`), so the page and the tray never
/// disagree about what a follow is. GitHub keeps its own tray (§1030),
/// which can resolve a repo with the account's token.
///
/// The field sits at the bottom on glass, where the thumb is (prd §752).
/// Optional environment only (prd §872).
struct FollowTrackTray: View {
    enum Target: String, CaseIterable, Identifiable {
        case youtube = "YouTube", podcasts = "Podcasts", pinterest = "Pinterest"
        case github = "GitHub", npm = "npm", pypi = "PyPI", huggingFace = "Hugging Face", radicle = "Radicle"

        var id: String { rawValue }

        static func of(_ room: Following.Room) -> [Target] {
            switch room {
            case .reading: []
            case .media:   [.youtube, .podcasts, .pinterest]
            case .work:    [.github, .npm, .pypi, .huggingFace, .radicle]
            }
        }

        var handle: HandleBridge? { HandleBridge(rawValue: rawValue) }
        var registry: PackageRegistry? {
            switch self {
            case .npm:  .npm
            case .pypi: .pypi
            default:    nil
            }
        }

        var placeholder: String {
            switch self {
            case .youtube:     String(localized: "@handle or channel link")
            case .podcasts:    String(localized: "Search a show")
            case .pinterest:   String(localized: "A username or board link")
            case .github:      String(localized: "owner/repo or a person")
            case .npm:         String(localized: "A package on npm")
            case .pypi:        String(localized: "A package on PyPI")
            case .huggingFace: String(localized: "An author on Hugging Face")
            case .radicle:     String(localized: "A Radicle repo id")
            }
        }
    }

    let room: Following.Room
    /// GitHub's own tray, raised by the room once this one has closed.
    var onGitHub: (() -> Void)? = nil
    /// After a follow landed and the tray closed: Apps takes the person to
    /// the room that now lists it (prd §1119); a room is already there.
    var onTracked: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(BridgeStore.self) private var store: BridgeStore?

    @State private var target: Target
    @State private var query = ""
    @State private var hits: [UserSearch.Hit] = []
    @State private var busy = false
    @State private var failure: String?
    @FocusState private var fieldFocused: Bool

    init(room: Following.Room, seat: String? = nil, onGitHub: (() -> Void)? = nil,
         onTracked: (() -> Void)? = nil) {
        self.room = room
        self.onGitHub = onGitHub
        self.onTracked = onTracked
        let picked = seat.flatMap(Target.init(rawValue:)).flatMap { Target.of(room).contains($0) ? $0 : nil }
        _target = State(initialValue: picked ?? Target.of(room).first(where: { $0 != .github }) ?? .youtube)
    }

    var body: some View {
        DSTray(title: room.verb, height: 520, detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    picker
                    if target == .podcasts, !hits.isEmpty {
                        ForEach(hits) { hit in hitRow(hit) }
                    }
                    if let failure {
                        DSFootnote(Text(verbatim: failure))
                            .padding(.horizontal, DS.Space.s4)
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                DSTraySearchField(placeholder: target.placeholder, text: $query, focus: $fieldFocused,
                                  searching: busy, keyboard: target == .podcasts ? .default : .URL,
                                  submitLabel: target == .podcasts ? .search : .go,
                                  onSubmit: { Task { await submit() } })
            }
        }
        .onAppear { fieldFocused = true }
        .task(id: target == .podcasts ? query : "") {
            guard target == .podcasts else { return }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.count >= 2 else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            hits = Array(await HandleBridge.podcasts.search(q).prefix(8))
        }
    }

    /// One app at a time, the room's apps in the catalogue's words.
    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(Target.of(room)) { t in
                    Button {
                        if t == .github, let onGitHub {
                            dismiss()
                            onGitHub()
                            return
                        }
                        withAnimation(DS.Motion.standard) {
                            target = t
                            failure = nil
                            hits = []
                        }
                    } label: {
                        Chip(text: t.rawValue, selected: target == t)
                    }
                    .buttonStyle(PressSpring())
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s2)
    }

    private func hitRow(_ hit: UserSearch.Hit) -> some View {
        HStack(spacing: DS.Space.s3) {
            WatchFace(url: hit.avatarURL, lettered: hit.displayName)
            Text(verbatim: hit.displayName).dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            Button {
                Task { await track(hit: hit) }
            } label: {
                Image(systemName: "plus")
                    .dsGlyph(.title, weight: .regular).foregroundStyle(DS.tint)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .accessibilityLabel(Text("Track \(hit.displayName)"))
        }
        .frame(minHeight: 60)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Tracking

    private func submit() async {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !busy else { return }
        if target == .podcasts {
            if let first = hits.first { await track(hit: first) }
            return
        }
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Following works once you leave the demo."))
            return
        }
        busy = true
        defer { busy = false }
        failure = nil
        let name: String
        let added: Int?
        if let bridge = target.handle {
            name = bridge.normalize(raw)
            guard !name.isEmpty else { return }
            bridge.addName(name)
            added = await bridge.refresh(context: modelContext)
            if added == nil, bridge.feedKind?.store.entries
                .first(where: { $0.input.caseInsensitiveCompare(name) == .orderedSame })?.feedURL.isEmpty ?? true {
                bridge.removeName(name, context: modelContext)
                failure = String(localized: "Couldn't find that on \(bridge.rawValue)")
                return
            }
            store?.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                     proof: String(localized: "Synced just now"), can: [bridge.canLine])
        } else if let registry = target.registry {
            name = registry.normalize(raw)
            guard !name.isEmpty, PackageStore.shared.add(registry, name) else {
                failure = String(localized: "Already following \(raw)")
                return
            }
            added = await PackageIngest.refresh(registry, context: modelContext)
            store?.registerConnected(
                id: registry.bridgeID, name: registry.displayName, proof: String(localized: "Synced just now"),
                can: ["Reads the current version of the packages you follow.",
                      "Read-only — it never installs, publishes, or signs in."])
        } else if target == .huggingFace {
            name = HuggingFaceStore.normalize(raw)
            guard !name.isEmpty, HuggingFaceStore.shared.add(name) else {
                failure = String(localized: "Already following \(raw)")
                return
            }
            added = await HuggingFaceIngest.refresh(context: modelContext)
            store?.registerConnected(id: "huggingface", name: "Hugging Face", proof: String(localized: "Synced just now"),
                                     can: ["Reads new models, datasets and Spaces from the authors you follow.",
                                           "Read-only — never publishes, stars, or downloads weights."])
        } else if target == .radicle {
            guard let rid = RadicleWire.normalizeRID(raw) else {
                failure = String(localized: "That isn't a Radicle repo id.")
                return
            }
            guard RadicleStore.shared.add(rid) else {
                failure = String(localized: "Already following that repo.")
                return
            }
            name = RadicleStore.shared.name(for: rid) ?? rid
            added = await RadicleIngest.refresh(context: modelContext)
            store?.registerConnected(
                id: "radicle", name: "Radicle", proof: String(localized: "Synced just now"),
                can: ["Reads patches and issues from the repos you follow, on the seed you name.",
                      "Read-only — the gateway has no credential and no way to write."])
        } else {
            return
        }
        _ = added
        landed(name)
    }

    private func track(hit: UserSearch.Hit) async {
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Following works once you leave the demo."))
            return
        }
        busy = true
        defer { busy = false }
        let bridge = HandleBridge.podcasts
        bridge.add(hit: hit)
        _ = await bridge.refresh(context: modelContext)
        store?.registerConnected(id: bridge.bridgeID, name: bridge.rawValue,
                                 proof: String(localized: "Synced just now"), can: [bridge.canLine])
        landed(hit.displayName)
    }

    /// Says so, and closes onto the list the follow joined.
    private func landed(_ name: String) {
        DSHaptic.success()
        chrome?.flash(room == .work ? String(localized: "Following \(name)")
                                    : String(localized: "Following \(name)"), tone: .success)
        dismiss()
        onTracked?()
    }
}
