import SwiftUI

/// The two pieces the vibenet SETUP screen and the vibenet ADDRESS BOOK
/// both need (prd §465, 2026-08-24) — the paste field and the discovery
/// list — extracted so the two screens cannot drift.
///
/// **Why they are shared rather than copied.** §465 splits what was one
/// screen in two: `VibenetScreen` keeps the connect act (the FIRST
/// address) and `VibenetAddressBookScreen` takes the list you manage
/// afterwards. Both have to be able to watch an address, and both have to
/// help somebody who arrives holding none — nobody has a devnet address
/// in their clipboard. Copied, the two would answer the same paste with
/// two different sentences within a release or two; `AddressBookScreen`'s
/// own ruling ("copy the structure, not the type") is about a screen's
/// LAYOUT, and this is one control appearing twice.

// MARK: - The paste field

/// Paste an address, watch it. Owns its own draft, its own focus and its
/// own result line, so a screen embedding it holds no state of its own for
/// the act — it just says what to do once an address really landed.
struct VibenetWatchField: View {
    @Environment(BridgeStore.self) private var store

    /// Called after an address was really ADDED — never after a duplicate
    /// or a rejected paste. The caller re-reads the chain (`load()`) and,
    /// on the setup screen, walks you to the room.
    var onWatched: () -> Void
    /// Whether the embedding screen has a read in flight, so the status
    /// rows can say so. The field itself never reads the chain.
    var syncing: Bool = false
    /// The line under the field while nothing has been typed and nothing
    /// has failed — nil on the book, where the roster below already says
    /// what is watched.
    var idleNote: String? = nil

    @State private var addressField = ""
    @FocusState private var fieldFocused: Bool
    @State private var addResult: String?
    @State private var addResultIsError = false
    @Bindable private var watch = VibenetWatch.shared

    /// The typed address, trimmed once — kept separate from
    /// `watchTyped()`'s own trim so the preview below reads cleanly, not
    /// because the two must ever disagree.
    private var draft: String {
        addressField.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the preview is about, or nil while the field holds
    /// nothing that's already a valid one. Unlike `WalletScreen`'s own
    /// version there is no name to resolve here — vibenet has no ENS/SNS
    /// registrar of its own (`VibenetWatch.isValidAddress`'s own doc: a
    /// pasted name that isn't already hex simply is not a vibenet
    /// address) — so this is a plain validity check, not a debounced
    /// network round-trip.
    private var previewAddress: String? {
        VibenetWatch.isValidAddress(draft) ? draft : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSlabField(
                placeholder: String(localized: "0x… devnet address"),
                text: $addressField,
                actionLabel: String(localized: "Watch"),
                focus: $fieldFocused,
                isArmed: VibenetWatch.isValidAddress(draft),
                action: watchTyped)

            // What you're about to watch, before you watch it — the
            // `WalletScreen.addressPreview` shape, so both setup screens
            // answer the same question the same way while you're
            // mid-paste. Keyed on `previewAddress` so the spring runs when
            // the FACE arrives, not on every keystroke that doesn't yet
            // resolve to one.
            addressPreview
                .animation(DS.Motion.standard, value: previewAddress)

            BridgeSyncStatusRows(
                syncing: syncing,
                syncingLine: String(localized: "Reading vibenet…"),
                result: addResult ?? (previewAddress == nil ? idleNote : nil),
                resultIsError: addResult == nil ? false : addResultIsError)
        }
    }

    /// What the typed address resolves to, RIGHT NOW. The face costs
    /// NOTHING (`WalletFace`'s identicon is deterministic from the
    /// address, so this is the exact same face the row will wear, drawn a
    /// second early) and `watch.isWatching` is a plain array scan — no
    /// balance, no live chain read, and no name resolution: any of those
    /// would be a metered call fired on every keystroke, and a live fact
    /// about an account nobody has agreed to watch is a claim this screen
    /// hasn't earned yet.
    @ViewBuilder
    private var addressPreview: some View {
        if let address = previewAddress {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: address, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watch.name(for: address) ?? VibenetRoom.shortAddress(address))
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(watch.isWatching(address) ? String(localized: "Already watching")
                                                   : String(localized: "New address"))
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .dsWell()
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
    }

    private func watchTyped() {
        let address = draft
        guard VibenetWatch.isValidAddress(address) else {
            addResult = String(localized: "That doesn't look like a devnet address — it needs to be 0x followed by 40 hex characters.")
            addResultIsError = true
            return
        }
        DSHaptic.tap()
        guard watch.add(address) else {
            addResult = String(localized: "Already watching that address.")
            addResultIsError = false
            addressField = ""
            return
        }
        addressField = ""
        addResult = nil
        VibenetBridge.registerBridge(store: store)
        onWatched()
    }
}

// MARK: - The discovery list

/// Real, recently-created vibenet accounts, one tap to watch. This is
/// STILL a read, not a connection — `AccountCreated` names no owner, so
/// nothing about looking at this list is different from opening the setup
/// screen at all; watching only happens on the explicit tap, exactly like
/// pasting an address by hand.
///
/// It exists because of the empty state's own problem: **nobody arrives at
/// a devnet already holding an address for it.**
///
/// **A ROW SAYS WHETHER YOU ALREADY TOOK IT (user ruling, 2026-08-28).**
/// The list used to draw every row identically, trailing "Watch", however
/// many of them you had watched — and `add` refuses a duplicate, so a second
/// tap on a row you already took did precisely nothing: the dead control §83
/// bans, and half of the report *"after you follow one address you can't
/// choose any of the others"*, since the only feedback for a tap that worked
/// and a tap that did nothing was the same row, unchanged. Picking several is
/// the act this list is for, so the list has to show the picking.
struct VibenetDiscoverySection: View {
    @Environment(BridgeStore.self) private var store
    /// Observed, not read once — a row's trailing word is a fact about the
    /// watch list, so it has to redraw when the list does. Watching from the
    /// paste field above marks its row here too, for the same reason.
    @Bindable private var watch = VibenetWatch.shared

    var onWatched: () -> Void

    @State private var discovered: [VibenetDiscoveredAccount] = []
    @State private var discoveryLoading = false
    @State private var discoveryAttempted = false

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// A fixed, always-available account to peek at — a fallback for the
    /// empty state's own fix, useful especially when live discovery can't
    /// reach the chain at all (the `Couldn't reach vibenet…` branch below,
    /// which otherwise leaves a new user with nothing to tap). Watched
    /// exactly like any pasted or discovered address; nothing about
    /// tapping it is different from typing it in by hand.
    private static let peekAddress = "0x777804FDCc280c082Db9788EAE5BEca0Fc2BeD9b"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if discoveryLoading {
                BridgeSyncStatusRows(
                    syncing: true, syncingLine: String(localized: "Looking for accounts on vibenet…"),
                    result: nil, resultIsError: false)
            } else if discovered.isEmpty {
                if discoveryAttempted {
                    Text("Couldn't reach vibenet to find an account to suggest — paste an address above, peek at an example, or open the explorer to find one.")
                        .dsText(.label12)
                        .foregroundStyle(DS.textSecondary)
                }
            } else {
                Text(String(localized: "Recently created on vibenet"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                ForEach(discovered) { account in
                    discoveryRow(address: account.address, subtitle: account.createdAt.map {
                        String(localized: "Created \($0.formatted(.relative(presentation: .named)))")
                    })
                }
            }
            // Always offered, live discovery or not — a real address,
            // always watchable, so a new user is never stuck with nothing
            // to tap while waiting on (or after losing) a network read.
            discoveryRow(address: Self.peekAddress, subtitle: String(localized: "Peek at an example account"))
        }
        .onAppear {
            if !discoveryAttempted { Task { await load() } }
        }
    }

    /// One row, shared by a discovered account and the fixed peek address —
    /// same face, same short-address line, same trailing verb, so the peek
    /// option reads as one more real account rather than a visually distinct
    /// special case.
    ///
    /// A row you have taken says so and stops being tappable. `.disabled` is
    /// enough here and would not be on a button that painted its own
    /// background (§83's own corollary — that dims the LABEL, not a
    /// background you drew): the whole control is text, and the text changes.
    private func discoveryRow(address: String, subtitle: String?) -> some View {
        let watching = watch.isWatching(address)
        return Button {
            DSHaptic.tap()
            guard VibenetWatch.shared.add(address) else { return }
            // Registered HERE, in the control, not left to each embedder:
            // three screens draw this list and a seat that forgot to register
            // reads perfectly right up until the catalog disagrees with it.
            VibenetBridge.registerBridge(store: store)
            onWatched()
        } label: {
            HStack(spacing: DS.Space.s2) {
                WalletFace(address: address, size: DS.Face.row, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(VibenetRoom.shortAddress(address))
                        .dsText(.label12).monospaced()
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    // Omitted rather than guessed when the block-time
                    // lookup failed — the same rule `expiryLabel` follows
                    // for its own clock fact.
                    if let subtitle {
                        Text(subtitle)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s2)
                if watching {
                    Label(String(localized: "Watching"), systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Text(String(localized: "Watch"))
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(Self.mark)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(watching)
        .animation(DS.Motion.standard, value: watching)
    }

    /// Once per appearance — never re-run by the embedding screen's own
    /// `load()`, which is about WATCHED addresses, a different question.
    /// Silent on failure: `discovered` simply stays empty and the section
    /// says so, the same honest-nothing shape every other empty state here
    /// already uses.
    private func load() async {
        discoveryLoading = true
        defer { discoveryLoading = false; discoveryAttempted = true }
        guard let contracts = await VibenetConfig.current() else { return }
        // THE CONFIG'S OWN REFERENCE ACCOUNTS LEAD (prd §507) — they cost no
        // request, they are the two accounts vibenet itself points at, and
        // they are here the instant the config is. The log walk still runs and
        // still fills the rest; what changes is that a slow or failed walk
        // now leaves a real empty state instead of an empty one.
        let reference = VibenetDiscovery.reference(contracts)
        discovered = reference
        let recent = await VibenetDiscovery.recentAccounts(keystore: contracts.keystore)
        let known = Set(reference.map { $0.address.lowercased() })
        discovered = reference + recent.filter { !known.contains($0.address.lowercased()) }
    }
}
