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
        Button {
            DSHaptic.tap()
            open = true
        } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: "Bluesky", size: 32, circular: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow a starter pack").dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text("Someone's curated list, in one tap").dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .dsListCardRow()
        }
        .buttonStyle(.plain)
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
                    Text("Someone else's curated list of people — follow all of them in one tap.")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    searchField
                    results
                }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.textTertiary)
            TextField("Search starter packs", text: $query)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await search() } }
            if searching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(minHeight: 44)
        .background(DS.surfaceWell,
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }

    @ViewBuilder private var results: some View {
        if let packs {
            if packs.isEmpty {
                Text("Nobody's built a pack matching “\(query)” yet.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.s2) {
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

    private func packRow(_ pack: BlueskyStarterPacks.Pack) -> some View {
        Button {
            DSHaptic.tap()
            selected = pack
            Task { await loadMembers(pack) }
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let avatar = pack.creatorAvatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: 36, fallback: "Bluesky", circular: true)
                } else {
                    BridgeIcon(name: "Bluesky", size: 36, circular: true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(pack.name).dsText(.heading17).foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(pack.creatorHandle.isEmpty ? "Bluesky" : "by @\(pack.creatorHandle)")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fillFaint, in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        }
        .buttonStyle(DSTileButtonStyle())
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
            }
            .buttonStyle(.plain)
            Text(pack.creatorHandle.isEmpty ? "Bluesky" : "by @\(pack.creatorHandle)")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        if let description = pack.description {
            Text(description).dsText(.callout15).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if loadingMembers {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text("Reading who's in this pack…")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .padding(.vertical, DS.Space.s3)
        } else if members.isEmpty {
            Text("Couldn't read this pack just now.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        } else {
            faceGrid
            followButton
        }
    }

    private var faceGrid: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s2) {
                ForEach(members) { member in
                    HStack(spacing: DS.Space.s3) {
                        if let avatar = member.avatarURL, !avatar.isEmpty {
                            RemoteThumb(urlString: avatar, size: 32, fallback: "Bluesky", circular: true)
                        } else {
                            BridgeIcon(name: "Bluesky", size: 32, circular: true)
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

    private var followButton: some View {
        Button {
            DSHaptic.tap()
            let n = BlueskyStarterPacks.followAll(members)
            followed = n
            onImport(n)
        } label: {
            Text(followed.map { "Followed \($0)" } ?? "Follow all \(members.count)")
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(followed != nil ? DS.textTertiary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(followed != nil ? DS.gray100 : DS.tint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(followed != nil)
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
