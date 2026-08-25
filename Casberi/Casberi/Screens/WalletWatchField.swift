import SwiftUI
import SwiftData

/// A resolved ENS/SNS name, tied to the draft that asked for it — keyed so a
/// slow answer for "vitalik.eth" can never paint itself under a draft that
/// has since become something else.
private struct WalletResolvedDraft: Equatable {
    let input: String
    let address: String
}

/// The ONE way to watch a wallet (prd §466, 2026-08-24) — paste an address,
/// resolve an ENS/SNS name, connect a wallet app, or peek at an example.
///
/// **Why this is a shared view now.** §461 put this field on `WalletScreen`
/// alone; §466 moved the roster it fed into `AddressBookScreen`, which means
/// two screens now need to be able to watch — `WalletScreen`, for the FIRST
/// wallet (setup's one act), and the book's own roster section, for the
/// second through fifth (a repeatedly). Copied, the two would answer the
/// same paste with two different sentences within a release —
/// `AddressBookScreen`'s own ruling ("copy the structure, not the type") is
/// about a screen's LAYOUT, and this is one control appearing twice.
///
/// **`showsPeekChip` is the one thing that differs by host.** The peek chip
/// exists so the whole feature demos in three seconds on a truly empty
/// install — `WalletScreen`'s job, not the roster's, where offering "peek at
/// vitalik" to somebody who already watches two wallets reads as a demo
/// prompt rather than what to do next.
struct WalletWatchField: View {
    @Environment(BridgeStore.self) private var store

    /// Called after an address was really ADDED — never after a duplicate,
    /// an error, or a cap hit. The caller decides what happens next: the
    /// setup screen routes into the room, the roster refreshes in place.
    var onWatched: () -> Void
    var showsPeekChip: Bool = false
    /// The connect handshake's picker is a `.sheet(item:)` this field does
    /// NOT own — `FeedScreen`'s single-presentation rule (a `.sheet` inside a
    /// row tears down whatever presented it), and this field is embedded in
    /// a `List` row on both of its hosts, each of which already carries its
    /// own `AddressBookSheetRoute` presentation. So the field hands the
    /// found accounts UP; the host decides where they land.
    var onConnectFound: ([WalletConnectBridge.ConnectedAccount]) -> Void

    @Bindable private var wallet = WalletStore.shared
    @Bindable private var book = AddressBook.shared
    @Environment(\.modelContext) private var modelContext

    @State private var newAddress = ""
    @FocusState private var addressFieldFocused: Bool
    @State private var result: String?
    @State private var resultIsError = false
    @State private var resolvedDraft: WalletResolvedDraft?
    /// Set when a watch would exceed the cap — an honest modal, since the
    /// field cannot show "already full" from inside itself while it is
    /// still on screen at the cap (2026-07-24, carried from `WalletScreen`).
    @State private var watchCapHit = false

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            DSSlabField(placeholder: String(localized: "Paste an address, or an ENS name"),
                        text: $newAddress,
                        actionLabel: String(localized: "Watch"),
                        focus: $addressFieldFocused,
                        isArmed: book.looksLikeAddress(draft)
                                 || SNS.looksLikeName(draft)
                                 || ENS.looksLikeName(draft),
                        action: watch)
            fieldNotice
            addressPreview
                .animation(DS.Motion.standard, value: previewAddress)
            if let result {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    Image(systemName: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .dsGlyph(12)
                        .foregroundStyle(resultIsError ? DS.destructive : DS.confirm)
                    Text(result)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.s1)
                .transition(.opacity)
            }
            // The automatic way in. It steps aside the moment you type (prd
            // §440): it is only relevant on an empty field, so leaving it
            // under the preview would stack two ways to add one address on
            // top of each other.
            if WalletConnectBridge.isAvailable, draft.isEmpty, wallet.canWatchMore {
                ConnectWalletRow(onFound: { showConnectPicker($0) },
                                 onNote: { message, isError in
                                     result = message
                                     resultIsError = isError
                                 })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if showsPeekChip, wallet.addresses.isEmpty, draft.isEmpty {
                peekChip
            }
        }
        .animation(DS.Motion.standard, value: draft.isEmpty)
        .task(id: draft) { await resolvePreview() }
        .alert("Watching \(WalletStore.watchLimit) already", isPresented: $watchCapHit) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Watching \(WalletStore.watchLimit) — the cap. Remove one first; its name stays in your book.")
        }
    }

    // MARK: - The preview

    private var draft: String {
        newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewAddress: String? {
        if book.looksLikeAddress(draft) { return draft }
        if let resolvedDraft, resolvedDraft.input == draft { return resolvedDraft.address }
        return nil
    }

    private var resolving: Bool {
        (SNS.looksLikeName(draft) || ENS.looksLikeName(draft)) && previewAddress == nil
    }

    private var draftIsUnsafe: Bool {
        !book.lookalikes(of: draft).isEmpty || AddressSafety.checksum(draft) == .failed
    }

    @ViewBuilder
    private var fieldNotice: some View {
        if let twin = book.lookalikes(of: draft).first {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "Looks like \(twin.name) — but it's a different address. Check every character."))
        } else if AddressSafety.checksum(draft) == .failed {
            noticeLine("exclamationmark.triangle.fill", DS.destructive,
                       String(localized: "That address fails its own checksum — a character is wrong somewhere."))
        }
    }

    private func noticeLine(_ glyph: String, _ tone: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: glyph)
                .dsGlyph(12)
                .foregroundStyle(tone)
            Text(text)
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s1)
        .transition(.opacity)
    }

    @ViewBuilder
    private var addressPreview: some View {
        if !draft.isEmpty, !draftIsUnsafe {
            if let address = previewAddress {
                let known = book.entry(for: address)
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(known?.name ?? draft)
                            .dsText(.callout15).fontWeight(.semibold)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(previewFact(address: address, known: known))
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.s2)
                .padding(.horizontal, DS.Space.s3)
                .background(DS.fillFaint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else if resolving {
                HStack(spacing: DS.Space.s2) {
                    ProgressView().controlSize(.mini)
                    Text("Looking up \(draft)…")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.s1)
            }
        }
    }

    private func previewFact(address: String, known: AddressBook.Entry?) -> String {
        if let known, isWatched(known) { return String(localized: "Already watching") }
        var parts: [String] = []
        if address != draft { parts.append(WalletStore.shortAddress(address)) }
        if known != nil { parts.append(String(localized: "already in your book")) }
        if let label = known?.kind.label { parts.append(label) }
        else if let script = BitcoinAddress.scriptKind(address) { parts.append(script) }
        return parts.isEmpty
            ? String(localized: "New address")
            : parts.joined(separator: " · ")
    }

    private func isWatched(_ entry: AddressBook.Entry) -> Bool {
        wallet.addresses.contains { wallet.scopeMatches(entry.address, scope: $0.address) }
    }

    private func resolvePreview() async {
        let asked = draft
        guard SNS.looksLikeName(asked) || ENS.looksLikeName(asked) else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        let hit = SNS.looksLikeName(asked)
            ? await SNS.resolve(asked) : await ENS.resolve(asked)
        guard !Task.isCancelled, let hit else { return }
        withAnimation(DS.Motion.standard) {
            resolvedDraft = WalletResolvedDraft(input: asked, address: hit)
        }
    }

    // MARK: - Watching

    private var peekChip: some View {
        Button {
            DSHaptic.tap()
            newAddress = "vitalik.eth"
            watch()
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "sparkles")
                    .dsGlyph(12)
                Text("Peek at vitalik.eth")
                    .dsText(.subhead13).fontWeight(.medium)
            }
            .foregroundStyle(DS.tint)
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .background(DS.tint.opacity(0.12), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressSpring())
    }

    private func watch() {
        let input = draft
        guard !input.isEmpty else { return }
        if SNS.looksLikeName(input) {
            Task {
                guard let address = await SNS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name, or paste the address.")
                    return
                }
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
                addWatched(address: address, label: input)
            }
        } else if ENS.looksLikeName(input) {
            Task {
                guard let hex = await ENS.resolve(input) else {
                    resultIsError = true
                    result = String(localized: "Couldn't resolve \(input) — check the name or paste a 0x address.")
                    return
                }
                addWatched(address: hex, label: input)
            }
        } else {
            // A legacy/P2SH Bitcoin address is base58-shaped too, the same
            // band Solana pubkeys occupy — check the checksum-verified kind
            // FIRST, or a pasted BTC address flips Solana on by mistake.
            if SNS.isAddress(input), !BitcoinAddress.isAddress(input) {
                WalletChainStore.shared.ensureEnabled("solana-mainnet")
            }
            addWatched(address: input, label: "")
        }
    }

    private func addWatched(address: String, label: String) {
        switch wallet.outcome(ofAdding: address, label: label) {
        case .added:
            // Watching is consent (prd §207): the wallet-riding seats reflect
            // it immediately, not only at the next foreground.
            store.reconcileWalletSeats()
        case .alreadyWatching:
            resultIsError = true
            result = String(localized: "Already watching that address.")
            return
        case .limitReached:
            watchCapHit = true
            return
        case .invalid:
            resultIsError = true
            result = String(localized: "That doesn't look like an address.")
            return
        }
        newAddress = ""
        addressFieldFocused = false
        resultIsError = false
        result = nil
        DSHaptic.success()
        // An eager, unblocking read — the same immediate feedback `sync()`
        // gave before the roster moved off this screen. No status is shown
        // for it here: the caller (the room, or the roster section) is
        // where the outcome belongs, since that's where the reader is
        // about to look.
        Task { _ = await WalletIngest.refresh(context: modelContext) }
        onWatched()
    }

    private func showConnectPicker(_ found: [WalletConnectBridge.ConnectedAccount]) {
        guard !found.isEmpty else {
            resultIsError = true
            result = String(localized: "Your wallet approved but shared no address — paste it instead.")
            return
        }
        resultIsError = false
        onConnectFound(found)
    }
}
