import SwiftUI

/// The Ethrex Privacy room's sheets (prd §596).
///
/// **This seat lands no `Thing`, so nothing here can ride the thing sheet** —
/// which is why, until this file, not one list in the room opened anything:
/// every row was `WalletRow`'s deliberately-terminal form, next to three
/// sibling devnets whose every row is a door. Both sheets follow the family's
/// shapes (`FramesMoveSheet`, `FramesAccountSheet`) so the fourth devnet stops
/// reading as a different app.
///
/// **The naming rule (§593):** nothing on this chain hides the sender, and the
/// copy below never implies otherwise — what a proof hides is which earlier
/// deposit it is spending, and the spend-key block says exactly that and no
/// more.

// MARK: - The room's own vocabulary

enum PrivacyDevnetName {
    /// "you" is lower case on purpose — it sits mid-sentence in labels.
    /// A watched address gets its book name; a stranger its short hex.
    @MainActor
    static func of(_ address: String) -> String {
        let short = WalletStore.shortAddress(address)
        guard !address.isEmpty else { return String(localized: "unknown") }
        if isMine(address) { return String(localized: "This phone") }
        return PrivacyDevnetWatch.shared.name(for: address) ?? short
    }

    /// Whether this is the account this phone's own key controls.
    ///
    /// **The key's address is watched from §602, so without this it appears in
    /// the roster, the rail and every sheet as an anonymous `0x1f…3c91`** —
    /// a stranger's address, in the room that made it. "This phone" is
    /// vibenet's own word for the same fact, and it beats a book name for the
    /// same reason a face beats a hex string: it says whose.
    ///
    /// Compared case-insensitively, because a stored address and a derived one
    /// disagree on EIP-55 checksum case and a raw `==` would silently never
    /// match (the wallet family's standing trap).
    @MainActor
    static func isMine(_ address: String) -> Bool {
        guard let mine = PrivacyDevnetKey.address(), !address.isEmpty else { return false }
        return mine.caseInsensitiveCompare(address) == .orderedSame
    }

    /// **ONE SHORTENER FOR THIS SEAT (prd §598).** It was written twice —
    /// `PrivacyDevnetRoomCard.shortHex` over `Data` for keys and roots, and a
    /// private `shortHash` over `String` for a transaction hash — with
    /// different head and tail lengths, so a key and the transaction that
    /// spent it were elided differently on the same sheet. Two spellings of
    /// one operation is how `DSSpecRow`'s three column widths happened.
    ///
    /// `WalletStore.shortAddress` is deliberately NOT reused: an address is
    /// checksummed and is shortened for recognition, and these are opaque
    /// hashes shortened for width.
    static func shortHex(_ hex: String) -> String {
        let body = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard body.count > 16 else { return "0x" + body }
        return "0x" + body.prefix(8) + "…" + body.suffix(6)
    }

    static func shortHex(_ d: Data) -> String {
        shortHex(d.map { String(format: "%02x", $0) }.joined())
    }

    /// A frame's mode, in a word. **Mode 2 is SENDER — measured, not read
    /// from a sibling** (§593c: "non-zero value only allowed in SENDER mode",
    /// in the node's own words); 1 and 0 carry the fork's shared vocabulary.
    /// An unfamiliar mode is named by NUMBER rather than given a word it may
    /// not mean — a wrong verb on a step is §83 where somebody reads it as
    /// what their transaction did.
    static func mode(_ mode: UInt64?) -> String? {
        switch mode {
        case nil: return nil
        case 2:   return String(localized: "Send")
        case 1:   return String(localized: "Verify")
        case 0:   return String(localized: "Call")
        case .some(let other): return String(localized: "Mode \(String(other))")
        }
    }
}

// MARK: - One transaction

/// A type-`0x6` transaction as a document: the anatomy, the steps, the
/// one-time keys it spent, the snapshot it proved against, and who paid.
struct PrivacyDevnetMoveSheet: View {
    let move: PrivacyDevnetLiveState.Move
    /// The address whose read produced this move. In an unscoped room nothing
    /// else can say whose transaction it is (Hegotá's rule).
    var owner: String = ""

    @Environment(BridgeStore.self) private var store

    var body: some View {
        // SCROLLABLE AND DRAG-PAST (prd §560): the height is a guess at real
        // text metrics, and a guess that runs short CLIPS the last block.
        DSTray(title: title, height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    steps
                    keys
                    snapshots
                    watchDoor
                    explorer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var title: String {
        PrivacyDevnetRoomCard.moveTitle(move)
    }

    private var trayHeight: CGFloat {
        // Measured off the Frames sheet's own arithmetic (its comment: a
        // deficit CLIPS, and the `.large` detent hides the shortfall).
        let keysBlock: CGFloat = move.nullifiers.isEmpty ? 0
            : CGFloat(move.nullifiers.count) * 46 + 50
        let rootsBlock: CGFloat = move.roots.isEmpty ? 0
            : CGFloat(move.roots.count) * 46 + 30
        let sponsor: CGFloat = move.sponsored ? 30 : 0
        let watch: CGFloat = watchable == nil ? 0 : 34
        return min(920, 270 + CGFloat(max(1, move.frames.count)) * 52
                        + keysBlock + rootsBlock + sponsor + 40)
            + watch
    }

    // MARK: The head

    /// **THE ANATOMY JOINS THE CROWN** (§593's `row(crown, tail)` rule,
    /// generalised in §593b): the shapes lead, the sentence beside them reads
    /// them out, the hash keeps the tail with its block.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            PrivacyDevnetAnatomy(
                items: PrivacyDevnetFigure.anatomy(
                    frames: move.frames.map {
                        PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit,
                                                  stateLimit: $0.stateLimit,
                                                  succeeded: $0.succeeded)
                    },
                    keys: move.nullifierCount, roots: move.rootCount,
                    sponsored: move.sponsored),
                stripWidth: 150, barHeight: 12, reduceMotion: true)
            // **THE TAIL IS A SPEC TABLE, NOT THREE STACKED LINES (prd
            // §598).** `DSSpecTable`/`DSSpecRow` is the app's own run of
            // label/value facts under a thing — the Frames sheets a person
            // reaches from the chip beside this one use it ten times over,
            // and this seat's sheets used it nowhere, hand-rolling a `VStack`
            // of tertiary sentences that carried their labels inside the
            // value ("From 0x1f…", "Block 13347"). The component exists
            // BECAUSE that shape was written three times at three column
            // widths; writing it a fourth is how the fourth width happens.
            DSSpecTable {
                DSSpecRow(label: Text(String(localized: "From")),
                          value: Text(PrivacyDevnetName.of(owner)))
                if let block = move.block {
                    DSSpecRow(label: Text(String(localized: "Block")),
                              value: Text(String(block)))
                }
                DSSpecRow(label: Text(String(localized: "Transaction")),
                          value: Text(PrivacyDevnetName.shortHex(move.hash)))
                // **WHAT IT COST, beside what it was allowed (prd §602).** The
                // room could state every transaction's budget and no
                // transaction's spend, over a receipt the walk had already
                // fetched. Stated only when BOTH halves are real: an unread
                // total says nothing, and an allowance summed over frames that
                // did not all carry one would be a denominator invented here.
                if let gas = gasLine {
                    DSSpecRow(label: Text(String(localized: "Gas")), value: Text(gas))
                }
            }
            if let sponsorship {
                Text(sponsorship)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dsSheetHeadBlock()
    }

    /// Who paid, NAMED — the walk keeps the receipt's own `payer` beside the
    /// Bool now (prd §596), so the sentence stops saying "somebody".
    private var sponsorship: String? {
        guard move.sponsored else { return nil }
        guard let payer = move.payer, !payer.isEmpty else {
            return String(localized: "Somebody else paid the gas.")
        }
        return String(localized: "\(PrivacyDevnetName.of(payer)) paid the gas.")
    }

    // MARK: The steps

    /// **EVERY FIELD HERE IS THE WIRE'S OR ABSENT.** Mode, target and value
    /// ride the same `eth_getTransactionByHash` payload the budgets come from
    /// (§596); a frame the wire described thinly draws its budgets alone. No
    /// per-frame outcome exists on this chain (measured, §593a), so no step is
    /// ever drawn as failed.
    @ViewBuilder private var steps: some View {
        if !move.frames.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(move.frames.count == 1 ? String(localized: "1 step")
                                            : String(localized: "\(String(move.frames.count)) steps"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                ForEach(Array(move.frames.enumerated()), id: \.offset) { index, frame in
                    stepRow(index: index, frame: frame)
                }
            }
        }
    }

    @ViewBuilder private func stepRow(index: Int,
                                      frame: PrivacyDevnetLiveState.Frame) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Circle()
                .fill(DS.tint)
                .frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(stepTitle(index: index, frame: frame))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                if let target = frame.target, !target.isEmpty {
                    Text(PrivacyDevnetName.of(target))
                        .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                if let hex = frame.valueWeiHex,
                   let wei = PrivacyDevnetRPC.hexWei(hex), wei > 0 {
                    Text(PrivacyDevnetMoney.line(wei: wei))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                if let budget = budgetLine(frame) {
                    Text(budget)
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .monospacedDigit().lineLimit(1)
                }
            }
        }
    }

    private func stepTitle(index: Int,
                           frame: PrivacyDevnetLiveState.Frame) -> String {
        guard let word = PrivacyDevnetName.mode(frame.mode) else {
            return String(localized: "\(String(index + 1)). Step")
        }
        return "\(index + 1). \(word)"
    }

    /// The budgets, as the chain spells them — `gasLimit`/`stateLimit`, this
    /// chain's own names (§593). Nil draws nothing rather than a zero.
    private func budgetLine(_ frame: PrivacyDevnetLiveState.Frame) -> String? {
        var parts: [String] = []
        if let gas = frame.gasLimit {
            parts.append(String(localized: "\(DSCount.grouped(gas)) gas"))
        }
        if let state = frame.stateLimit, state > 0 {
            parts.append(String(localized: "\(DSCount.grouped(state)) state"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The keys

    /// **THE EXPLAINER LIVES HERE NOW, beside the keys it explains** — it led
    /// the room's list as a paragraph over a column of rows (the jam §596 was
    /// reported for), and a sheet is the document a paragraph belongs in. The
    /// wording keeps §593's honesty line whole: it does not hide who sent it.
    @ViewBuilder private var keys: some View {
        if !move.nullifiers.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(move.nullifiers.count == 1 ? String(localized: "1 spend key")
                                                : String(localized: "\(String(move.nullifiers.count)) spend keys"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                // **THE APP'S OWN ROW, AND THE APP'S OWN STAMP (prd §598).**
                // These were an `HStack` with a hand-placed trailing word,
                // which is `WalletRow`'s terminal form plus `DSStamp` spelled
                // out — and `DSStamp` exists precisely because that word was
                // drawn twice at two weights before anyone noticed.
                //
                // `.quiet` is not a shrug: this room spends NO colour on
                // state (§593b), and a spent key is neither good nor bad.
                ForEach(Array(move.nullifiers.enumerated()), id: \.offset) { _, key in
                    WalletRow(mark: .symbol("key.fill", tint: DS.tint),
                              title: PrivacyDevnetName.shortHex(key)) {
                        DSStamp(word: String(localized: "used once"))
                    }
                }
                Text(String(localized: "Spent once, never again — it doesn't hide who sent it."))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The snapshot

    @ViewBuilder private var snapshots: some View {
        if !move.roots.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(move.roots.count == 1 ? String(localized: "1 snapshot")
                                           : String(localized: "\(String(move.roots.count)) snapshots"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                // The room's own row again, wearing the SET'S ORDINAL — the
                // same number the ring draws and the Snapshots rows carry, so
                // one identity survives from a figure to a list to this sheet
                // (prd §598). The bytes stay as the subtitle, which is where
                // an identifier belongs.
                ForEach(Array(move.roots.enumerated()), id: \.offset) { _, root in
                    WalletRow(terminal: PrivacyDevnetRoomCard.setMark(setIndex(of: root),
                                                                      of: setCount),
                              title: PrivacyDevnetRoots.setLabel(setIndex(of: root),
                                                                 of: setCount),
                              subtitle: PrivacyDevnetName.shortHex(root.root))
                }
            }
        }
    }

    /// Used of allowed, or just used, or nothing.
    ///
    /// **Three states and no fourth.** A transfer has no frames and therefore
    /// no allowance, so it states its spend alone rather than inventing a
    /// denominator; a receipt the walk could not read states nothing rather
    /// than a zero. Grouped by locale, because these are counts somebody reads
    /// rather than hex the chain speaks.
    private var gasLine: String? {
        guard let used = move.gasUsed else { return nil }
        let usedText = DSCount.grouped(used)
        let figureFrames = move.frames.map {
            PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit, stateLimit: $0.stateLimit,
                                      succeeded: $0.succeeded)
        }
        guard let allowed = PrivacyDevnetFigure.allowance(figureFrames) else {
            return String(localized: "\(usedText) used")
        }
        return String(localized: "\(usedText) of \(DSCount.grouped(allowed))")
    }

    /// How many sets this transaction proved against.
    ///
    /// **Scoped to the MOVE, not the room** — a sheet is about one
    /// transaction, and numbering its references against every set the whole
    /// room has seen would print "Set 3" on a sheet showing one row.
    private var setCount: Int {
        PrivacyDevnetRoots.bySource(move.roots).count
    }

    private func setIndex(of reference: PrivacyDevnetRoots.Reference) -> Int {
        PrivacyDevnetRoots.setIndex(of: reference.sourceID, in: move.roots) ?? 0
    }

    // MARK: The doors

    /// A step's target worth watching — the Frames rule verbatim: on a chain
    /// of eighteen addresses, the ones you meet in your own transactions are
    /// very nearly the only ones worth watching. One door, recipient first.
    /// **NEVER IN THE DEMO** (§549's class): the demo's accounts are a
    /// fixture, and this door writes to the REAL watch list, which survives
    /// the demo's own teardown.
    private var watchable: String? {
        let mine = Set(([owner] + PrivacyDevnetWatch.shared.addresses).map { $0.lowercased() })
        return move.frames.compactMap(\.target).first {
            !$0.isEmpty && !mine.contains($0.lowercased())
        }
    }

    @ViewBuilder private var watchDoor: some View {
        if let address = watchable, !DemoMode.isActive {
            Button {
                DSHaptic.selection()
                if PrivacyDevnetWatch.shared.add(address) {
                    PrivacyDevnetBridge.registerBridge(store: store)
                    Task { await PrivacyDevnetLiveState.shared.refresh() }
                }
            } label: {
                Text(String(localized: "Watch \(WalletStore.shortAddress(address))"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
            .buttonStyle(.plain)
        }
    }

    /// The chain's own explorer — opened in the person's OWN browser, which is
    /// why the host is in the reach audit's non-reach denylist rather than in
    /// `NetworkReach` (Frames' rule; `dora.privacy.ethrex.xyz` answered 200 on
    /// 2026-09-04).
    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(PrivacyDevnetIdentity.explorer)/tx/\(move.hash)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }
}

// MARK: - One address

/// One watched address, and its facts as DOORS — `FramesAccountSheet`'s
/// dispatch: tapping a fact scopes the room to this address and opens the
/// scope the fact names, so the sheet never dead-ends on a reading the room
/// can already draw.
struct PrivacyDevnetAccountSheet: View {
    let account: PrivacyDevnetAccount
    /// Scope the room and open a section. The CALLER dismisses and writes the
    /// scope, so this sheet never re-derives chrome state.
    var onPick: ((PrivacyDevnetSection) -> Void)? = nil

    @State private var copied = false

    var body: some View {
        DSTray(title: PrivacyDevnetName.of(account.address),
               height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    facts
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var trayHeight: CGFloat {
        min(720, 330 + CGFloat(doorCount) * 34)
    }

    private var doorCount: Int {
        [account.moves.isEmpty ? 0 : 1,
         account.frameCount > 0 ? 1 : 0,
         account.nullifiers.isEmpty ? 0 : 1,
         account.roots.isEmpty ? 0 : 1].reduce(0, +)
    }

    /// **THE FAMILY'S HEAD, NOT A THIRD ONE (prd §605).** `FramesAccountSheet`
    /// and `HegotaAccountSheet` lead with the face at shelf size, the short
    /// address as a copy button, the balance at `price40` and one line for
    /// what the account has done; this sheet led with a list-size face, the
    /// balance, and then the WHOLE address in mono beneath — a different
    /// anatomy for the same document, one chip over.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                WalletFace(address: account.address, size: DS.Face.shelf, circular: true)
                Spacer(minLength: 0)
                Button {
                    DSHaptic.selection()
                    DSPasteboard.copySensitive(account.address)
                    copied = true
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Text(WalletStore.shortAddress(account.address))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .dsGlyph(13)
                            .foregroundStyle(copied ? DS.confirm : DS.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // **Nil is not zero** (§515a) — an unread balance is not an empty
            // account, and this is the largest type on the sheet.
            if account.reached, let wei = account.balanceWei {
                Text(PrivacyDevnetMoney.line(wei: wei))
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, DS.Space.s3)
            } else {
                Text(account.reached
                     ? String(localized: "Balance unread")
                     : String(localized: "The chain didn't answer"))
                    .dsText(.reading20).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
            Text(sendLine)
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s4)
        }
        .dsSheetHeadBlock()
    }

    /// The nonce IS the count — incremented per transaction the account signs
    /// — so this is a fact off the chain, not a tally of what the walk read.
    private var sendLine: String {
        guard let nonce = account.nonce else {
            return String(localized: "Sends couldn't be read")
        }
        switch nonce {
        case 0:  return String(localized: "Nothing sent from here yet")
        case 1:  return String(localized: "1 sent from here")
        default: return String(localized: "\(String(nonce)) sent from here")
        }
    }

    /// **FACTS AS DOORS, in the family's row.** Each names a count the walk
    /// found and opens the scope that draws it — `FramesAccountSheet`'s spec
    /// rows, where this sheet drew `WalletRow`s with a glyph and Hegotá's
    /// hand-rolled a third shape. A count of zero has no row — a door onto an
    /// empty scope is the dead control §83 bans — and a row with nobody to
    /// dispatch to draws no chevron.
    @ViewBuilder private var facts: some View {
        DSSpecTable {
            row(Text("Transactions"), count: account.moves.count, section: .activity)
            row(Text("Steps run"), count: account.frameCount, section: .frames)
            row(Text("Spend keys"), count: account.nullifiers.count, section: .nullifiers)
            row(Text("Snapshot proofs"), count: account.roots.count, section: .roots)
        }
    }

    @ViewBuilder private func row(_ label: Text, count: Int,
                                  section: PrivacyDevnetSection) -> some View {
        if count > 0 {
            let opens = onPick != nil
            DSSpecRow(label: label, value: Text(verbatim: String(count)),
                      tint: opens ? DS.tint : DS.textPrimary,
                      glyph: opens ? "chevron.right" : nil,
                      action: onPick.map { pick in { DSHaptic.selection(); pick(section) } })
        }
    }
}
