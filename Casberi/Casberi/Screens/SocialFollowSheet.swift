import SwiftUI
import SwiftData

/// SOCIAL'S FOLLOW (prd §1086), Markets' Add carried over: a tray with the
/// field at the bottom on glass (prd §752).
///
/// Before you type, the people already near you that you follow nowhere on
/// that network (`SocialToYou.suggestions`): who followed you or replied to
/// you, newest first, then who your feed keeps naming. As you type, people on
/// Bluesky, through the keyless typeahead the setup screens
/// already ride (`UserSearch`). A follow is a private watch — the app never
/// writes to a network (§801) — and the sheet stays open, so you can keep
/// several.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct SocialFollowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome: ShellChrome?

    /// A person a row can follow, with the face the app already holds.
    struct Candidate: Identifiable {
        let source: String
        let handle: String
        let name: String?
        let avatarURL: String?
        let line: String
        var id: String { source + ":" + handle }
    }

    @State private var query = ""
    @State private var near: [Candidate] = []
    @State private var found: [Candidate] = []
    @State private var searching = false
    @State private var watched: [String: Set<String>] = [:]
    @State private var justFollowed: String? = nil
    @FocusState private var fieldFocused: Bool

    var body: some View {
        DSTray(title: String(localized: "Follow"), height: 640, detents: [.large]) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty { before } else { results }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { field }
        }
        .task { load() }
        .task(id: query) { await search() }
        .onAppear { fieldFocused = true }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var field: some View {
        DSTraySearchField(placeholder: String(localized: "A name or a handle"),
                          text: $query, focus: $fieldFocused, searching: searching)
    }

    @ViewBuilder private var before: some View {
        if near.isEmpty {
            footnote
        } else {
            DSTrayHead(String(localized: "Near you"))
            ForEach(near) { person in row(person) }
        }
    }

    @ViewBuilder private var results: some View {
        if !found.isEmpty {
            ForEach(["Bluesky"], id: \.self) { network in
                let people = found.filter { $0.source == network }
                if !people.isEmpty {
                    DSTrayHead(network)
                    ForEach(people) { person in row(person) }
                }
            }
        }
        if DemoMode.isActive || (!searching && found.isEmpty) { footnote }
    }

    private var footnote: some View {
        let text: Text = if DemoMode.isActive && !trimmed.isEmpty {
            Text("Search works once you leave the demo.")
        } else if trimmed.isEmpty {
            Text("Search Bluesky by name. People who reply to you show here.")
        } else {
            Text("Nobody by that name on Bluesky.")
        }
        return DSFootnote(text)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }

    private func row(_ person: Candidate) -> some View {
        let on = (watched[person.source] ?? []).contains(SocialToYou.normalized(person.handle))
        return HStack(spacing: DS.Space.s3) {
            WatchFace(url: person.avatarURL, lettered: person.name ?? person.handle)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: person.name ?? "@\(person.handle)").dsText(.body17)
                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: on ? String(localized: "Following") : person.line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Button {
                follow(person)
            } label: {
                Image(systemName: on ? "checkmark" : "plus")
                    .dsGlyph(.title, weight: .regular)
                    .foregroundStyle(on ? DS.textTertiary : DS.tint)
                    .symbolEffect(.bounce, value: justFollowed == person.id)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressSpring())
            .disabled(on)
            .accessibilityLabel(Text(on ? String(localized: "Following \(person.handle)")
                                        : String(localized: "Follow \(person.handle) on \(person.source)")))
        }
        .frame(minHeight: 64)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Following

    private func follow(_ person: Candidate) {
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Following works once you leave the demo."))
            return
        }
        let profile = SocialProfile(source: person.source, handle: person.handle,
                                    displayName: person.name, bio: nil,
                                    avatarURL: person.avatarURL)
        guard SocialPeople.watch(profile) else { return }
        watched[person.source, default: []].insert(SocialToYou.normalized(person.handle))
        justFollowed = person.id
        chrome?.flash(String(localized: "Following \(person.name ?? person.handle)"), tone: .success)
        let context = modelContext
        Task { await SocialPeople.sync(source: person.source, context: context) }
    }

    // MARK: - Reading

    private func search() async {
        let q = trimmed
        guard !q.isEmpty, !DemoMode.isActive else {
            found = []; searching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        let bsky = await UserSearch.bluesky(q)
        guard !Task.isCancelled else { return }
        found = bsky.map { Candidate(source: "Bluesky", handle: $0.handle, name: $0.displayName,
                                     avatarURL: $0.avatarURL, line: "@\($0.handle)") }
        searching = false
    }

    private func load() {
        watched = [
            "Bluesky": Set(SocialPeople.watchedHandles(source: "Bluesky").map(SocialToYou.normalized)),
        ]
        var mine = Set<String>()
        for a in BlueskyStore.shared.accounts where a.mine { mine.insert(SocialToYou.normalized(a.handle)) }
        let members = RoomAccounts.roomSources(RoomAccounts.socialRoom)
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> { members.contains($0.source) },
                                       sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 800
        let rows = ((try? modelContext.fetch(d)) ?? []).filter(\.isLive)
        // Faces and names the app already holds, by network and handle.
        var faces: [String: (name: String?, avatar: String?)] = [:]
        var talkers: [(source: String, handle: String, at: Date)] = []
        var posts: [(source: String, text: String, at: Date)] = []
        for thing in rows where SocialToYou.followable.contains(thing.source) {
            if let handle = thing.authorHandle {
                let key = thing.source + ":" + SocialToYou.normalized(handle)
                if faces[key] == nil { faces[key] = (nil, thing.authorAvatarURL) }
                if thing.socialContext == "reply" || thing.socialContext == "follow" {
                    talkers.append((thing.source, handle, thing.capturedAt))
                }
            }
            posts.append((thing.source, thing.postText ?? thing.title, thing.capturedAt))
        }
        near = SocialToYou.suggestions(talkers: talkers, posts: posts, watched: watched,
                                       mine: mine, now: .now).map { person in
            let face = faces[person.source + ":" + person.handle]
            let line: String = switch person.why {
            case .talksToYou: String(localized: "Talks to you · \(person.source)")
            case .mentioned(let n): String(localized: "In \(n) posts you saw · \(person.source)")
            }
            return Candidate(source: person.source, handle: person.handle, name: face?.name,
                             avatarURL: face?.avatar, line: line)
        }
    }
}
