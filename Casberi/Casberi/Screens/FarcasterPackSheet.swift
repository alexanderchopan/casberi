import SwiftUI

/// The Farcaster setup screen's door into `FarcasterPackSheet` — its own
/// tiny view so its `.sheet(isPresented:)` never stacks onto a host screen's
/// existing `.sheet` modifier, the same isolation `StarterPacksDoor` uses
/// for Bluesky's pack sheet (see that file's doc comment for the class of
/// bug this sidesteps).
struct FarcasterPackDoor: View {
    var onImport: (Int) -> Void
    /// Fired after the sheet is actually gone, and only when a follow really
    /// happened — a caller that needs to navigate away (onboarding ending
    /// the fork) waits for this instead of `onImport`, so the transition
    /// never fights a still-presented sheet. Optional and unused by every
    /// other caller (e.g. the setup screen just resyncs on `onImport`).
    var onDismissAfterFollow: (() -> Void)? = nil
    @State private var open = false
    @State private var didFollow = false

    var body: some View {
        Button {
            DSHaptic.tap()
            open = true
        } label: {
            HStack(spacing: DS.Space.s3) {
                BridgeIcon(name: "Farcaster", size: DS.Mark.list, circular: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow a starter pack").dsText(.body17).foregroundStyle(DS.textPrimary)
                    Text("A hand-picked list, in one tap").dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .dsGlyph(13)
                    .foregroundStyle(DS.textTertiary)
            }
            .dsListCardRow()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open, onDismiss: {
            if didFollow { onDismissAfterFollow?() }
        }) {
            FarcasterPackSheet(onImport: { n in
                didFollow = true
                onImport(n)
            })
        }
    }
}

/// Farcaster's starter pack (2026-08-08) — `FarcasterStarterPack`'s pinned
/// list, followed in one tap. Simpler than `StarterPackImportSheet`'s two
/// states (search, then a selected pack's detail): there's exactly one pack
/// here, since Farcaster's client API has no keyless browse/search for real
/// ones (see `FarcasterStarterPack`'s doc comment), so this sheet opens
/// straight to the face grid.
struct FarcasterPackSheet: View {
    /// Fired after a follow lands, so the setup screen resyncs.
    var onImport: (Int) -> Void

    @State private var members: [FarcasterStarterPack.Member] = []
    @State private var loading = true
    @State private var followed: Int?

    var body: some View {
        DSTray(title: "Follow a starter pack", height: 620) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("A hand-picked set of people worth reading — follow all of them in one tap.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if loading {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reading the pack…")
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
        }
        .task {
            members = await FarcasterStarterPack.members()
            loading = false
        }
    }

    private var faceGrid: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s2) {
                ForEach(members) { member in
                    HStack(spacing: DS.Space.s3) {
                        if let avatar = member.avatarURL, !avatar.isEmpty {
                            RemoteThumb(urlString: avatar, size: DS.Face.list, fallback: "Farcaster", circular: true)
                        } else {
                            BridgeIcon(name: "Farcaster", size: DS.Face.list, circular: true)
                        }
                        Text(member.displayName?.isEmpty == false ? member.displayName! : member.username)
                            .dsText(.body17).foregroundStyle(DS.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("@\(member.username)")
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
            let n = FarcasterStarterPack.followAll()
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
}
