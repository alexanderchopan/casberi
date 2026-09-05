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
        return PrivacyDevnetWatch.shared.name(for: address) ?? short
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
            : CGFloat(move.nullifiers.count) * 46 + 70
        let rootsBlock: CGFloat = move.roots.isEmpty ? 0
            : CGFloat(move.roots.count) * 46 + 30
        let sponsor: CGFloat = move.sponsored ? 30 : 0
        let watch: CGFloat = watchable == nil ? 0 : 34
        return min(920, 300 + CGFloat(max(1, move.frames.count)) * 52
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
            Text(PrivacyDevnetRoomCard.moveLine(move))
                .dsText(.reading20)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // The tail: whose, which one, where. One line each, quiet.
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "From \(PrivacyDevnetName.of(owner))"))
                if let block = move.block {
                    Text(String(localized: "Block \(String(block))"))
                }
                Text(shortHash)
                    .dsText(.mono12)
            }
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            if let sponsorship {
                Text(sponsorship)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dsSheetHeadBlock()
    }

    private var shortHash: String {
        move.hash.count > 18
            ? "\(move.hash.prefix(10))…\(move.hash.suffix(6))" : move.hash
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
        if move.frames.isEmpty {
            Text(String(localized: "An ordinary transfer — one result, not a step per part."))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
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
            parts.append(String(localized: "\(String(gas)) gas"))
        }
        if let state = frame.stateLimit, state > 0 {
            parts.append(String(localized: "\(String(state)) state"))
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
                ForEach(Array(move.nullifiers.enumerated()), id: \.offset) { _, key in
                    HStack(spacing: DS.Space.s3) {
                        PrivacyDevnetSpentKey(size: 16)
                        Text(PrivacyDevnetRoomCard.shortHex(key))
                            .dsText(.mono12).foregroundStyle(DS.textSecondary)
                        Spacer(minLength: 0)
                        Text(String(localized: "used once"))
                            .dsText(.label12).foregroundStyle(DS.textTertiary)
                    }
                }
                Text(String(localized: "Each key was used once and can never be used again — that is what stops this spend being repeated. It does not hide who sent it."))
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The snapshot

    @ViewBuilder private var snapshots: some View {
        if !move.roots.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(move.roots.count == 1 ? String(localized: "The snapshot it proved against")
                                           : String(localized: "The snapshots it proved against"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                ForEach(Array(move.roots.enumerated()), id: \.offset) { _, root in
                    HStack(spacing: DS.Space.s3) {
                        Rectangle()
                            .fill(DS.tint)
                            .frame(width: 10, height: 10)
                            .rotationEffect(.degrees(45))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(PrivacyDevnetRoomCard.shortHex(root.root))
                                .dsText(.mono12).foregroundStyle(DS.textSecondary)
                            Text(String(localized: "registered at slot \(String(root.slot))"))
                                .dsText(.label12).foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
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
        min(720, 300 + CGFloat(doorCount) * 52)
    }

    private var doorCount: Int {
        [account.moves.isEmpty ? 0 : 1,
         account.frameCount > 0 ? 1 : 0,
         account.nullifiers.isEmpty ? 0 : 1,
         account.roots.isEmpty ? 0 : 1].reduce(0, +)
    }

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                WalletFace(address: account.address, size: DS.Face.list, circular: true)
                VStack(alignment: .leading, spacing: 2) {
                    // **Nil is not zero** (§515a) — an unread balance is not an
                    // empty account, and this is the largest type on the sheet.
                    if account.reached, let wei = account.balanceWei {
                        Text(PrivacyDevnetMoney.line(wei: wei))
                            .dsText(.price40)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                        Text(account.reached
                             ? String(localized: "Balance unread")
                             : String(localized: "The chain didn't answer"))
                            .dsText(.reading20).foregroundStyle(DS.textSecondary)
                    }
                    Text(sendLine)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text(account.address)
                .dsText(.mono12).foregroundStyle(DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
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

    /// **FACTS AS DOORS.** Each row names a count the walk found and opens
    /// the scope that draws it. A count of zero has no row — a door onto an
    /// empty scope is the dead control §83 bans.
    @ViewBuilder private var facts: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !account.moves.isEmpty {
                door(String(localized: account.moves.count == 1
                            ? "1 transaction" : "\(String(account.moves.count)) transactions"),
                     symbol: "arrow.left.arrow.right", section: .activity)
            }
            if account.frameCount > 0 {
                door(String(localized: account.frameCount == 1
                            ? "1 step run" : "\(String(account.frameCount)) steps run"),
                     symbol: "square.stack.3d.up.fill", section: .frames)
            }
            if !account.nullifiers.isEmpty {
                door(String(localized: account.nullifiers.count == 1
                            ? "1 one-time spend key" : "\(String(account.nullifiers.count)) one-time spend keys"),
                     symbol: "key.fill", section: .nullifiers)
            }
            if !account.roots.isEmpty {
                door(String(localized: account.roots.count == 1
                            ? "1 proof against a snapshot" : "\(String(account.roots.count)) proofs against snapshots"),
                     symbol: "clock.fill", section: .roots)
            }
        }
    }

    @ViewBuilder private func door(_ title: String, symbol: String,
                                   section: PrivacyDevnetSection) -> some View {
        if let onPick {
            Button {
                DSHaptic.selection()
                onPick(section)
            } label: {
                WalletRow(mark: .symbol(symbol, tint: DS.tint), title: title)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            WalletRow(terminal: .symbol(symbol, tint: DS.tint), title: title)
        }
    }
}
