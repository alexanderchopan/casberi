import SwiftUI
import SwiftData

/// THE WALLET'S FOLLOW (prd §1090), Social's Follow carried over (§1086): a
/// tray with the field at the bottom on glass (§752), raised in the room
/// instead of pushing the account page.
///
/// Before you type, the addresses already near your money that you don't
/// follow (`WalletFollowSuggest`): who you moved money with twice or more in
/// sixty days, then the names in your book. As you type, the address or name
/// the field holds, resolved through the one spelling the account page's
/// field uses (`WalletFollow`), with its lookalike and checksum warnings. A
/// follow is private — nothing is written anywhere — and the tray stays open.
///
/// Optional environment only: on Mac Catalyst a sheet's content is evaluated
/// where the presenter's `.environment` has not reached (prd §872).
struct WalletFollowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ShellChrome.self) private var chrome: ShellChrome?
    @Environment(BridgeStore.self) private var store: BridgeStore?

    @State private var query = ""
    @State private var near: [WalletFollowSuggest.Suggestion] = []
    @State private var preview: WalletFollow.Resolution? = nil
    @State private var previewFor = ""
    @State private var searching = false
    @State private var following: Set<String> = []
    @State private var justFollowed: String? = nil
    /// The account followed last: the Wallet lands on it as the tray
    /// closes, its balance rolling in as the read lands (prd §1587).
    @State private var landOn: String? = nil
    /// Raised from the Wallet: closing lands on the account followed.
    var landsOnClose = false
    /// What a settled WalletConnect session shared, on its way to the picker
    /// (prd §1417): the tray is where you follow, so connecting is here too.
    @State private var shared: [WalletConnectBridge.ConnectedAccount] = []
    @State private var pickerOpen = false
    @State private var connectNote: String? = nil
    @FocusState private var fieldFocused: Bool

    private var book: AddressBook { AddressBook.shared }
    private var wallet: WalletStore { WalletStore.shared }

    var body: some View {
        DSTray(title: String(localized: "Follow an account"), height: 640, detents: [.large], scrollsItself: true) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if trimmed.isEmpty { before } else { typed }
                }
                .padding(.bottom, 96)
            }
            .scrollDismissesKeyboard(.interactively)
            .dsFindField { field }
        }
        .task { load() }
        .onDisappear {
            // Only from the Wallet's own tray: Settings opens it too, and a
            // follow there is not a trip out of Settings.
            guard landsOnClose, let landOn, let chrome else { return }
            chrome.openWallet()
            chrome.walletScope = landOn
        }
        .task(id: trimmed) { await resolve() }
        // A sheet on Catalyst does not inherit the presenter's environment
        // (prd §872), and the picker reads both objects unwrapped.
        .sheet(isPresented: $pickerOpen, onDismiss: load) {
            WalletConnectPickerSheet(shared: shared) { _ in }
            .environment(chrome)
            .environment(store)
        }
        .onAppear {
            // The words the tray's search was holding (prd §1185).
            if let draft = chrome?.searchDraft { query = draft; chrome?.searchDraft = nil }
            fieldFocused = true
        }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var field: some View {
        DSTraySearchField(placeholder: String(localized: "An address or a name"),
                          text: $query, focus: $fieldFocused, searching: searching,
                          submitLabel: .done) {
            // The paste is the common way in: an address is copied, never typed.
            // **THE SYSTEM'S PASTE (prd §1587):** it reads the clipboard with
            // no "Allow Paste" prompt, which a custom button raised each time.
            if UIPasteboard.general.hasStrings {
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { query = s }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .tint(DS.pickInk)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    // MARK: - Before you type

    @ViewBuilder private var before: some View {
        if !wallet.canWatchMore {
            footnote(Text("Following \(WalletStore.watchLimit) of \(WalletStore.watchLimit)."))
        }
        // **Connect a wallet, every time (prd §1417).** §690 kept this to
        // a first run because a card overlapped the page's Connection row,
        // and §1090 moved Follow here without it — so anyone already
        // following a wallet had no way to connect another. The demo reaches
        // nothing (§483), so the row is not drawn there.
        if WalletConnectBridge.isAvailable, wallet.canWatchMore, !DemoMode.isActive {
            ConnectWalletRow(onFound: { found in
                connectNote = nil
                shared = found
                pickerOpen = true
            }, onNote: { text, _ in connectNote = text })
            .padding(.horizontal, DS.Space.s4)
            if let connectNote {
                footnote(Text(verbatim: connectNote))
            }
        }
        if !near.isEmpty {
            // No heading over them (user: "get rid of 'near your money' that
            // is so weird"): each row's line already says why it is here.
            ForEach(near, id: \.address) { s in
                row(address: s.address, name: s.name, line: line(for: s))
            }
        }
    }

    private func line(for s: WalletFollowSuggest.Suggestion) -> String {
        switch s.why {
        case .movedWith(let n):
            return String(localized: "\(n) moves with you in 60 days")
        case .inBook(let provenance):
            return provenance ?? String(localized: "In your addresses")
        }
    }

    // MARK: - As you type

    @ViewBuilder private var typed: some View {
        if let twin = book.lookalikes(of: trimmed).first {
            warning(String(localized: "Looks like \(twin.name) — but it's a different address. Check every character."))
        } else if AddressSafety.checksum(trimmed) == .failed {
            warning(String(localized: "That address fails its own checksum — a character is wrong somewhere."))
        } else if previewFor == trimmed, let preview {
            switch preview {
            case .found(let target):
                let known = book.entry(for: target.address)
                let line = target.address != trimmed
                    ? WalletStore.shortAddress(target.address)
                    : (known != nil ? String(localized: "In your addresses") : String(localized: "New address"))
                row(address: target.address,
                    name: known?.name ?? target.worldAppName ?? (target.label.isEmpty ? nil : target.label),
                    line: line, target: target)
            case .missed(let note):
                footnote(Text(verbatim: note))
            }
        } else if NameResolve.followTarget(of: trimmed) != nil || book.looksLikeAddress(trimmed) {
            // A name or an address being asked about — during the debounce
            // too, so a valid name never reads as nothing (prd §1090).
            HStack(spacing: DS.Space.s2) {
                DSSpinner(size: .mini)
                Text("Looking up \(trimmed)…")
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
        }
    }

    private func footnote(_ text: Text) -> some View {
        DSFootnote(text)
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .dsGlyph(.caption)
                .foregroundStyle(DS.destructive)
            Text(text)
                .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s4)
    }

    private func row(address: String, name: String?, line: String,
                     target: WalletFollow.Target? = nil) -> some View {
        let on = following.contains(WalletFollowSuggest.key(address))
        let title = name ?? WalletStore.shortAddress(address)
        return HStack(spacing: DS.Space.s3) {
            WalletFace(address: address, size: DS.Face.list, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).dsText(.body17)
                    .foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(verbatim: on ? String(localized: "Following") : line)
                    .dsText(.subhead12).foregroundStyle(DS.textTertiary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Button {
                follow(target ?? WalletFollow.Target(address: address, label: name ?? "", chain: nil))
            } label: {
                DSFollowMark(on: on, dimmed: !wallet.canWatchMore,
                             bounce: justFollowed == WalletFollowSuggest.key(address))
            }
            .buttonStyle(PressSpring())
            .disabled(on || !wallet.canWatchMore)
            .accessibilityLabel(Text(on ? String(localized: "Following \(title)")
                                        : String(localized: "Follow \(title)")))
        }
        .frame(minHeight: DSFeed.headHeight)
        .padding(.horizontal, DS.Space.s4)
    }

    // MARK: - Following

    private func follow(_ target: WalletFollow.Target) {
        guard !DemoMode.isActive else {
            chrome?.flash(String(localized: "Following works once you leave the demo."))
            return
        }
        switch WalletFollow.follow(target) {
        case .added:
            // Watching is consent (prd §207): the wallet-riding seats reflect
            // it now, not at the next foreground.
            store?.reconcileWalletSeats()
            following.insert(WalletFollowSuggest.key(target.address))
            justFollowed = WalletFollowSuggest.key(target.address)
            landOn = target.address
            // The success flash carries the one buzz (prd §1587).
            let name = target.label.isEmpty ? WalletStore.shortAddress(target.address) : target.label
            chrome?.flash(String(localized: "Following \(name)"), tone: .success)
            let context = modelContext
            Task { _ = await WalletIngest.refresh(context: context) }
        case .alreadyWatching:
            following.insert(WalletFollowSuggest.key(target.address))
        case .limitReached:
            chrome?.flash(String(localized: "Following \(WalletStore.watchLimit) of \(WalletStore.watchLimit)."))
        case .invalid:
            chrome?.flash(String(localized: "That doesn't look like an address."))
        }
    }

    // MARK: - Reading

    private func resolve() async {
        let q = trimmed
        // Whatever this pass ends on, the spinner is the LAST pass's to set:
        // a cancelled pass hands it to the one that replaced it.
        guard !q.isEmpty else { preview = nil; previewFor = ""; searching = false; return }
        // A name is asked of the network; the demo reaches nothing (§483).
        if NameResolve.followTarget(of: q) != nil {
            guard !DemoMode.isActive else {
                previewFor = q
                preview = .missed(String(localized: "Looking up a name works once you leave the demo."))
                searching = false
                return
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
        }
        searching = true
        let answer = await WalletFollow.resolve(q)
        guard !Task.isCancelled else { return }
        withAnimation(DS.Motion.standard) {
            previewFor = q
            preview = answer
        }
        searching = false
    }

    private func load() {
        following = Set(wallet.addresses.map { WalletFollowSuggest.key(AddressBook.key(for: $0.address)) })
        let source = CategoryFold.walletRoom
        let since = Date.now.addingTimeInterval(-WalletFollowSuggest.window)
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.source == source && $0.capturedAt >= since
        }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        d.fetchLimit = 1500
        // Only the columns the rule reads (prd §722: every one named). iOS
        // 26+ only — a predicated partial fetch drops rows on 18.6 (§623).
        if #available(iOS 26.0, *) {
            d.propertiesToFetch = [\.source, \.capturedAt, \.counterpartyAddress,
                                   \.securityFlag, \.transferVenue]
        }
        // An app in the catalogue is a service by its name ("Coinbase").
        let services = Set(BridgeCatalog.offers.map { $0.name.lowercased() })
        let moves: [WalletFollowSuggest.Move] = ((try? modelContext.fetch(d)) ?? []).compactMap { t in
            guard t.isLive, let other = t.counterpartyAddress, !other.isEmpty else { return nil }
            return .init(counterparty: other, at: t.capturedAt,
                         excluded: t.securityFlag != nil || t.transferVenue != nil
                            || WalletIngest.isKnownContract(other))
        }
        let entries = book.all.map {
            WalletFollowSuggest.BookEntry(address: $0.address, name: $0.name, kind: $0.kind.rawValue,
                                          provenance: $0.provenance, addedAt: $0.addedAt,
                                          isService: services.contains($0.name.lowercased())
                                            || WalletIngest.isKnownContract($0.address))
        }
        near = WalletFollowSuggest.suggestions(moves: moves, book: entries,
                                               following: following,
                                               now: .now)
    }
}
