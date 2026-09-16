import SwiftUI

/// The setup screen's door into `StarterPackImportSheet` — its own tiny view
/// so its `.sheet(isPresented:)` never stacks onto a host screen's existing
/// `.sheet` modifier (the class of bug `FeedScreen`'s `FeedSheetRoute`
/// consolidation fixed once already; isolating a second sheet's presentation
/// in its own subview sidesteps it instead of re-risking it).
struct StarterPacksDoor: View {
    var onImport: (Int) -> Void
    @State private var open = false

    var body: some View {
        DSPushRow(title: Text("Follow a starter pack"),
                  subtitle: Text("Someone's curated list, in one tap"),
                  action: { open = true }) {
            BridgeIcon(name: "Bluesky", size: DS.Mark.list, circular: false)
        }
        .dsListRow()
        .sheet(isPresented: $open) {
            StarterPackImportSheet(onImport: onImport)
        }
    }
}

/// Bluesky starter packs (item 4 of the 2026-07-27 social pass) — search a
/// pack, see who's in it, follow the whole set in one tap. The honest fix to
/// `FollowImportSheet`'s own problem: a real follow graph runs to thousands
/// of people, too many to picker through one checkbox at a time; a pack is
/// someone else's taste, already curated to a few dozen.
///
/// Two states in one sheet, the same shape prd §186 ruled for setup screens
/// generally: search is the form, a selected pack is the manager. Nothing
/// here watches automatically — picking a pack and tapping Follow is the
/// same explicit consent every other import path in this app asks for.
struct StarterPackImportSheet: View {
    /// Fired after a follow lands, so the setup screen resyncs.
    var onImport: (Int) -> Void

    @State private var query = ""
    @State private var packs: [BlueskyStarterPacks.Pack]?
    @State private var searching = false
    @State private var selected: BlueskyStarterPacks.Pack?
    @State private var members: [BlueskyStarterPacks.Member] = []
    @State private var loadingMembers = false
    @State private var followed: Int?

    var body: some View {
        DSTray(title: selected?.name ?? "Follow a starter pack", height: 620) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                if let selected {
                    packDetail(selected)
                } else {
                    searchField
                    results
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        DSSlabField(placeholder: String(localized: "Search starter packs"),
                    text: $query, actionLabel: "",
                    glyph: "magnifyingglass", clearable: true, busy: searching,
                    size: .compact, submitLabel: .search,
                    action: { Task { await search() } })
    }

    @ViewBuilder private var results: some View {
        if let packs {
            if packs.isEmpty {
                Text("Nobody's built a pack matching “\(query)” yet.")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.s4) {
                        ForEach(packs) { pack in
                            packRow(pack)
                        }
                    }
                    .padding(.vertical, DS.Space.s1)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    /// A push row on nothing; the list's air separates packs (prd §782).
    private func packRow(_ pack: BlueskyStarterPacks.Pack) -> some View {
        DSPushRow(title: Text(verbatim: pack.name),
                  subtitle: Text(pack.creatorHandle.isEmpty ? "Bluesky" : "by @\(pack.creatorHandle)"),
                  action: {
                      selected = pack
                      Task { await loadMembers(pack) }
                  }) {
            if let avatar = pack.creatorAvatarURL, !avatar.isEmpty {
                RemoteThumb(urlString: avatar, size: DS.Face.list, fallback: "Bluesky", circular: true)
            } else {
                BridgeIcon(name: "Bluesky", size: DS.Face.list, circular: true)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func packDetail(_ pack: BlueskyStarterPacks.Pack) -> some View {
        HStack(spacing: DS.Space.s2) {
            Button {
                self.selected = nil
                members = []
                followed = nil
            } label: {
                Image(systemName: "chevron.left")
                    .dsGlyph(.subhead)
                    .foregroundStyle(DS.textSecondary)
                    .dsTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back to the pack list"))
            Text(pack.creatorHandle.isEmpty ? "Bluesky" : "by @\(pack.creatorHandle)")
                .dsText(.subhead12).foregroundStyle(DS.textTertiary)
        }
        if let description = pack.description {
            Text(description).dsText(.body17).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if loadingMembers {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text("Reading who's in this pack…")
                    .dsText(.body17).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s3)
        } else if members.isEmpty {
            Text("Couldn't read this pack just now.")
                .dsText(.body17).foregroundStyle(DS.textTertiary)
        } else {
            faceGrid
            followButton(pack)
        }
    }

    private var faceGrid: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s2) {
                ForEach(members) { member in
                    HStack(spacing: DS.Space.s3) {
                        if let avatar = member.avatarURL, !avatar.isEmpty {
                            RemoteThumb(urlString: avatar, size: DS.Face.list, fallback: "Bluesky", circular: true)
                        } else {
                            BridgeIcon(name: "Bluesky", size: DS.Face.list, circular: true)
                        }
                        Text(member.displayName?.isEmpty == false ? member.displayName! : member.handle)
                            .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("@\(SocialThread.shortHandle(member.handle))")
                            .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, DS.Space.s1)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func followButton(_ pack: BlueskyStarterPacks.Pack) -> some View {
        DSSlabButton(title: followed.map { "Followed \($0)" } ?? "Follow all \(members.count)",
                     enabled: followed == nil) {
            DSHaptic.tap()
            let n = BlueskyStarterPacks.followAll(members)
            followed = n
            onImport(n)
        }
    }

    // MARK: - Loads

    private func search() async {
        searching = true
        packs = await BlueskyStarterPacks.search(query)
        searching = false
    }

    private func loadMembers(_ pack: BlueskyStarterPacks.Pack) async {
        loadingMembers = true
        members = await BlueskyStarterPacks.members(of: pack)
        loadingMembers = false
    }
}
