import SwiftUI

/// What a bridge screen becomes once it's working (prd §186) — the second
/// half of the two-state setup template.
///
/// The ruling (user, 2026-07-23): the CONNECT form stays exactly as it is —
/// "it's important to know what the steps are" — but the screen must stop
/// being that form forever. The moment a connection verifies, the steps and
/// the credential fields retire behind one door and this takes the screen:
/// **identity leads, proof is live, capabilities are sentences.** A person
/// opening a connected bridge is not there to re-read setup instructions;
/// they're there to see that it's working, and occasionally to replace a key.
///
/// Unified with `BridgeDetailScreen` by construction (the §186 ruling's second
/// half): the proof line and the can-do sentences are read from `BridgeStore`,
/// the same records that screen renders, so a bridge can never tell two
/// different stories about itself on two surfaces.
///
/// **Identity is never invented.** Only some bridges know whose account they
/// hold — Steam its profile, Mail its address, Obsidian its vault name. The
/// eleven keyed bridges, Spotify, and Twitch store no account name at all
/// (measured 2026-07-23: `TokenVault` holds a secret, `twitch.userid` holds an
/// opaque id, Spotify holds only tokens). Those pass `identity: nil` and the
/// header leads with the bridge's own name over a truthful note about HOW it
/// connects — never a display name we'd have to fetch or guess.
struct BridgeConnectedState: View {
    /// The BridgeStore id — the proof line and can-do sentences come from
    /// there, so this view states what the store already knows rather than
    /// re-deriving a second version of the truth.
    let bridgeID: String
    let name: String
    /// The account, address, or vault this connection actually holds — nil
    /// when the bridge stores no such name (see the type note above).
    var identity: String? = nil
    /// How it's connected, in plain words: "Integration key · Keychain",
    /// "App password · Keychain", "Signed in on this iPhone".
    let connectionNote: String
    /// The door's trailing summary, when there's a fact worth putting there.
    var connectionSummary: String = ""
    /// What this bridge can do, for the case where `BridgeStore` holds no
    /// record yet — a credential can be stored before any sync has ever
    /// succeeded, and `registerConnected` only runs on a good sync. Without
    /// this the screen went barren in exactly that state (found live,
    /// 2026-07-23). A capability is a static fact about the bridge, so
    /// stating it early is honest; the PROOF pill still waits for a real
    /// sync, because that one is a claim about what happened.
    var capabilitiesFallback: [String] = []
    /// Opens the credentials door — the steps and fields, unchanged, plus
    /// Disconnect. A sheet rather than a push: this is set-once configuration
    /// reached from a screen that may itself be pushed, and the wallet's §139
    /// amendment already settled that configuration may live behind a door.
    let openConnection: () -> Void

    @Environment(BridgeStore.self) private var store

    private var bridge: BridgeApp? {
        store.bridges.first { $0.id == bridgeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header
            proofPill
            // The store's own sentences when it has them, else the bridge's
            // static ones — never nothing.
            let can = bridge?.can.isEmpty == false ? bridge!.can : capabilitiesFallback
            if !can.isEmpty {
                DSCheckList(lines: can)
            }
            connectionDoor
        }
        .padding(.vertical, DS.Space.s2)
    }

    /// Identity leads — the app's own mark beside whose connection this is.
    private var header: some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: name, size: 54)
            VStack(alignment: .leading, spacing: 2) {
                // The account when we hold one, else the bridge's own name —
                // the honest lead when there's no account to name.
                Text(identity?.isEmpty == false ? identity! : name)
                    .dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(connectionNote)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// The live proof — the store's own status line, wearing the status's
    /// shape as well as its hue (the Differentiate Without Color pass). No
    /// pill at all when a bridge has never reported one: a green capsule with
    /// nothing behind it would be exactly the fake status the honesty rule
    /// forbids.
    @ViewBuilder private var proofPill: some View {
        if let bridge, !bridge.statusLine.isEmpty {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: bridge.status.glyph)
                    .font(.system(size: 9, weight: .bold))
                Text(bridge.statusLine)
                    .dsText(.label12).fontWeight(.semibold)
                    .monospacedDigit()
            }
            .foregroundStyle(bridge.status.color)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, 5)
            .background(bridge.status.color.opacity(0.12),
                        in: Capsule(style: .continuous))
            .accessibilityLabel(Text("\(bridge.status.spoken). \(bridge.statusLine)"))
        }
    }

    /// The one door — everything the connect form was, plus Disconnect. The
    /// shared slab (prd §190), so the connected state of all eighteen keyed
    /// and account bridges wears the same block the Wallet manager does.
    private var connectionDoor: some View {
        DSSlabDoor(title: "Connection", detail: connectionSummary,
                   systemImage: "gearshape", action: openConnection)
    }
}

/// The door's destination — the connect form exactly as it was, presented as
/// a sheet (prd §186). The caller hands over its own existing sections, so
/// each bridge keeps the steps and fields it already had, verbatim: the
/// ruling kept the form, it only moved.
struct BridgeConnectionSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                content()
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .dsPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .dsText(.body17).foregroundStyle(DS.tint)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(DS.surfaceSheet)
        .dsColorScheme()
    }
}
