import SwiftUI

/// What one connect handshake found, as a PICKER (2026-08-13, prd §376).
///
/// The handshake used to end in a silent bulk-add: every account the session
/// shared was watched at once, unnamed, and anything past the watch cap was
/// dropped without a word (see `WalletConnectPlan` for the full account of
/// what was wrong). This is that moment given a screen.
///
/// It is `FollowImportSheet`'s shape on purpose — §87 ruled that door a picker
/// rather than a mirror, and the reasoning transfers exactly: these are
/// addresses, each one costs a sync job on every foreground forever and a slot
/// against a cap of five, so handing the list over and letting the person tap
/// is the honest gesture. The one divergence is preselection. §87 preselects
/// nothing because a follow graph is 1,800 strangers we went and fetched;
/// here the shared accounts arrive already chosen — the person picked them in
/// their own wallet's approval screen seconds ago — so re-asking would be
/// making them do the same work twice. What we went and FOUND (Safes) is never
/// pre-ticked, which is what keeps the two sections meaningfully different.
struct WalletConnectPickerSheet: View {
    /// Everything the settled session handed over, in the order
    /// `WalletConnectBridge.accounts(from:)` produced it.
    let shared: [WalletConnectBridge.ConnectedAccount]
    /// Fired after the watch lands, with how many were added, so the screen
    /// behind can resync.
    var onWatch: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var store
    @Bindable private var wallet = WalletStore.shared

    /// The Safe lookup's whole answer, nil until it settles — kept as the
    /// lookup rather than a bare array so "couldn't look" survives to the
    /// copy (§85). `.reachable == false` and `safes.isEmpty` are two different
    /// sentences and this sheet says both.
    @State private var lookup: SafeBridge.SignerLookup?
    /// Reverse-ENS names, keyed the plan's way. A connected address with a
    /// primary name lands NAMED — which is the whole gap the old silent add
    /// left: typing `vitalik.eth` into the field beside this produced a named
    /// row while the richer door produced `0x…`.
    @State private var names: [String: String] = [:]
    @State private var picked: Set<String> = []

    var body: some View {
        DSTray(title: "Choose what to watch", height: 660) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(blurb).dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Above the list, never below it, and never silent: the cap is
                // the fact this whole sheet exists to stop swallowing.
                if let line = capLine {
                    note(line)
                }
                list
                addButton
            }
        }
        .task { await load() }
    }

    // MARK: - The plan

    /// Rebuilt on every body pass, which is cheap (a handful of rows) and is
    /// what keeps the sheet honest while the watch list changes underneath it
    /// — `wallet` is `@Bindable`, so unwatching something elsewhere reopens a
    /// slot here rather than leaving a stale ceiling.
    private var plan: WalletConnectPlan.Plan {
        WalletConnectPlan.make(
            shared: shared.map { (address: $0.address, namespace: $0.namespace) },
            safes: lookup?.safes ?? [],
            watched: wallet.addresses.map(\.address),
            limit: WalletStore.watchLimit)
    }

    private var blurb: String {
        let n = shared.count
        return n == 1
            ? String(localized: "Your wallet shared 1 address. Watching is read-only — it can never trade or move funds.")
            : String(localized: "Your wallet shared \(n) addresses. Watching is read-only — it can never trade or move funds.")
    }

    /// The cap, in words, whenever it constrains anything. Nil the rest of the
    /// time — a note that always shows is a note nobody reads.
    private var capLine: String? {
        let plan = self.plan
        if plan.roomLeft == 0 {
            return String(localized: "You're watching \(WalletStore.watchLimit) already — the cap. Unwatch one first; naming an address stays free.")
        }
        if plan.overflow > 0 {
            return String(localized: "Room for \(plan.roomLeft) more — \(plan.overflow) of these can't be watched until you unwatch something.")
        }
        return nil
    }

    private func note(_ text: String) -> some View {
        Text(text).dsText(.callout15).foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The list

    private var list: some View {
        let plan = self.plan
        let sharedRows = plan.rows.filter { $0.origin.isShared }
        let foundRows = plan.rows.filter { !$0.origin.isShared }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(sharedRows) { row(_: $0, plan: plan) }

                // The found half only appears once there is something to say
                // about it — including "we couldn't look", which is a fact and
                // not the same as finding nothing.
                if !foundRows.isEmpty || lookupHasNews {
                    Text("Also found")
                        .dsText(.heading17).foregroundStyle(DS.textPrimary)
                        .padding(.top, DS.Space.s3)
                    if let line = foundNote { note(line) }
                    ForEach(foundRows) { row(_: $0, plan: plan) }
                }
            }
            .padding(.vertical, DS.Space.s1)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// Whether the Safe read produced something worth a heading even with no
    /// rows — an unreachable lookup, or a truncated one.
    private var lookupHasNews: Bool {
        guard let lookup else { return false }
        return !lookup.reachable || lookup.truncated
    }

    private var foundNote: String? {
        guard let lookup else { return nil }
        if !lookup.reachable {
            return String(localized: "Couldn't check whether you sign on any Safes just now.")
        }
        if lookup.truncated {
            return String(localized: "This address is named as an owner on more Safes than we checked — these are the ones confirmed live.")
        }
        return nil
    }

    private func row(_ row: WalletConnectPlan.Row, plan: WalletConnectPlan.Plan) -> some View {
        let on = picked.contains(row.key)
        // Three states, three treatments, no dead controls (§83): already
        // watched says so and can't be tapped; a row that can't fit says why
        // and can't be tapped; everything else is a real toggle.
        let blocked = !row.alreadyWatching && !on && !plan.canPick(picked)
        let inert = row.alreadyWatching || blocked
        return Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) {
                if on { picked.remove(row.key) } else { picked.insert(row.key) }
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: row.address, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: row)).dsText(.heading17)
                        .foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text(subtitle(for: row))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if row.alreadyWatching {
                    Text("Watching").dsText(.label12).foregroundStyle(DS.textTertiary)
                } else if blocked {
                    Text("No room").dsText(.label12).foregroundStyle(DS.textTertiary)
                } else {
                    Image(systemName: "checkmark")
                        .dsGlyph(16, weight: .bold)
                        .foregroundStyle(DS.tint)
                        .opacity(on ? 1 : 0)
                }
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? DS.tintDim : DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .opacity(inert ? 0.5 : 1)
        }
        .buttonStyle(DSTileButtonStyle())
        .disabled(inert)
        .accessibilityLabel(title(for: row))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The name if the address published one, the short form otherwise —
    /// never an invented label.
    private func title(for row: WalletConnectPlan.Row) -> String {
        names[row.key] ?? WalletStore.shortAddress(row.address)
    }

    /// Where the row came from, stated plainly. A found Safe names the address
    /// that reaches it, because "we found this" with no reason attached is the
    /// kind of claim §295 rules out.
    private func subtitle(for row: WalletConnectPlan.Row) -> String {
        switch row.origin {
        case .shared:
            // The address is worth showing whenever the title ISN'T it —
            // an ENS name is a label, and the address is the identity.
            return names[row.key] == nil
                ? String(localized: "From your wallet")
                : String(localized: "From your wallet · \(WalletStore.shortAddress(row.address))")
        case .safe(let via, let chain):
            let owner = names[WalletConnectPlan.matchKey(via)] ?? WalletStore.shortAddress(via)
            return String(localized: "Safe on \(chain) · \(owner) signs on it")
        }
    }

    // MARK: - Acting

    private var addButton: some View {
        let plan = self.plan
        let n = picked.count
        // With no room at all there is nothing to add, so the button stops
        // pretending to be one rather than sitting there permanently inert.
        let closing = plan.selectionCeiling == 0
        return Button {
            if closing { dismiss() } else { watchPicked() }
        } label: {
            Text(closing ? String(localized: "Done")
                         : (n == 0 ? String(localized: "Pick what to watch")
                                   : String(localized: "Watch \(n)")))
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(n == 0 && !closing ? DS.textTertiary : .white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                // A hand-rolled button paints its own background, and
                // `.disabled` dims a label, not a fill — so the fill swaps
                // itself or an inert button reads live (§83).
                .background(n == 0 && !closing ? DS.gray100 : DS.tint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
        }
        .buttonStyle(PressSpring())
        .armedPop(n > 0 || closing)
        .disabled(n == 0 && !closing)
    }

    private func watchPicked() {
        let chosen = plan.rows.filter { picked.contains($0.key) }
        var added = 0
        var refused = 0
        for row in chosen {
            // Solana accounts need their chain switched on to be readable at
            // all — the same `ensureEnabled` the old silent path did, kept
            // because a watched address nothing can read is a dead row. Tested
            // against the Solana namespace rather than "not EVM", so a third
            // namespace arriving can never silently switch Solana on.
            if row.namespace == WalletConnectBridge.solanaNamespace {
                WalletChainStore.shared.ensureEnabled(WalletConnectBridge.solanaNetworkID)
            }
            switch wallet.outcome(ofAdding: row.address, label: names[row.key] ?? "") {
            case .added: added += 1
            // The cap is checked before a tap is allowed, so reaching this is
            // a race (another screen watched something while this sheet was
            // open) rather than the silent truncation this sheet replaced —
            // counted either way, because the one thing that must never
            // happen again is a refusal nobody hears about.
            case .limitReached, .invalid, .alreadyWatching: refused += 1
            }
        }
        if added > 0 {
            // Watching is consent (§207): the wallet-riding seats are on the
            // moment a wallet is — reflect it now, not at the next foreground.
            store.reconcileWalletSeats()
            DSHaptic.success()
        }
        chrome.flash(outcomeLine(added: added, refused: refused),
                     tone: added > 0 ? .success : .failure)
        onWatch(added)
        dismiss()
    }

    /// 0 gets its own sentence — the plural branch would report a watch that
    /// didn't happen ("Watching 0 more wallets").
    private func outcomeLine(added: Int, refused: Int) -> String {
        if added == 0 {
            return String(localized: "Nothing was added.")
        }
        let core = added == 1
            ? String(localized: "Watching 1 more wallet.")
            : String(localized: "Watching \(added) more wallets.")
        guard refused > 0 else { return core }
        return core + " " + String(localized: "\(refused) wouldn't fit.")
    }

    // MARK: - Loading

    private func load() async {
        picked = plan.preselected
        // Names first: they're one cached read per address and they change
        // what every row SAYS, while the Safe walk is a bounded network crawl
        // that only adds rows at the bottom.
        var found: [String: String] = [:]
        for account in shared where ENS.isHexAddress(account.address) {
            if let name = await ENS.reverseName(for: account.address) {
                found[WalletConnectPlan.matchKey(account.address)] = name
            }
        }
        names = found

        let result = await SafeBridge.signerSafes(for: shared.map(\.address))
        withAnimation(DS.Motion.standard) { lookup = result }
        // A newly-found Safe never joins the selection — `preselected` is
        // computed from the shared half alone, and re-running it here would
        // tick boxes under the person's hands after they'd already chosen.
        for safe in result.safes where ENS.isHexAddress(safe.address) {
            if let name = await ENS.reverseName(for: safe.address) {
                names[WalletConnectPlan.matchKey(safe.address)] = name
            }
        }
    }
}
