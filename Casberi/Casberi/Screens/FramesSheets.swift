import SwiftUI

/// THE FRAMES DEVNET'S SHEETS (prd §548 ninth follow-up) — the four documents
/// under the room's four scopes.
///
/// **Every list in this room was already a `Button` wired to nothing.**
/// `FramesRoomList` has built its rows as `Button { onOpenMove(move) }` since
/// the room shipped, and `FeedScreen` passed `onOpenMove: { _ in }` — so a tap
/// on any row in Activity, Frames or Sponsors highlighted and did nothing.
/// That is §83's dead control multiplied by every transaction on screen, in the
/// room whose entire content is those rows.
///
/// ## THE PRESENTATION RULE, INHERITED RATHER THAN REDISCOVERED
///
/// None of these sheets presents itself. They are raised by
/// `FeedScreen`'s ONE `.sheet(item:)`, because the cards that open them live
/// inside that screen's `List` — a `.sheet` attached to a view inside a List
/// row resolves to the same presenting controller and rises part way before
/// closing again (paid for three times: 2026-07-28, then Hegotá twice).
///
/// ## AND THE READING RULE, WHICH IS THIS SEAT'S OWN
///
/// **A frame's STATUS is about execution; only its EFFECT says what it did.**
/// Every verdict, tick and tone below comes from `FramesMove.verdict` and
/// `FramesFrameRow.valueLanded`, never from `succeeded` alone — measured on
/// this chain, a frame reports `status: 0x1` after being rolled back and a
/// transaction reports `status: 0x0` having moved money. A sheet is where
/// somebody goes to check what really happened, so it is the last place that
/// distinction may be dropped.

// MARK: - Naming

/// An address as a person rather than as a hex string.
///
/// The view half of `FramesParty`, which is Foundation-only so the harness can
/// compile the rule; this is the part that reaches the watch list and the
/// address book for a name somebody gave.
enum FramesName {
    /// The room's own vocabulary. **"you" is lower case on purpose** — it sits
    /// inside sentences ("you paid the gas", "you → 0x333e…3a0d") far more
    /// often than it leads one.
    static func of(_ address: String, mine: String?, watched: [String]) -> String {
        switch FramesParty.of(address, mine: mine, watched: watched) {
        case .you:
            return String(localized: "you")
        case .watched(let match):
            return FramesWatch.shared.name(for: match) ?? WalletStore.shortAddress(match)
        case .stranger(let match):
            // A stranger may still have a name in the address book — it is one
            // ledger across every chain (§169), and naming is free where
            // watching is capped, so an address named on the Wallet screen is
            // named here too.
            return FramesWatch.shared.name(for: match) ?? WalletStore.shortAddress(match)
        }
    }

    /// The same, capitalised for the start of a sentence or a tray title.
    static func leading(_ address: String, mine: String?, watched: [String]) -> String {
        let name = of(address, mine: mine, watched: watched)
        return name == String(localized: "you") ? String(localized: "You") : name
    }

    /// The addresses this room knows are yours: the key, plus the watch list.
    @MainActor static var watched: [String] { FramesWatch.shared.addresses }
    @MainActor static var mine: String? { FramesKey.address() }
}

/// A frame mode's ink and glyph.
///
/// **The hues MIRROR `FramesSequenceCanvas` exactly** — VERIFY reads lighter
/// than SENDER there because the first authorises and the second acts — and
/// they must, or the strip at the top of a sheet colours a step differently
/// from the row three lines below it describing the same step.
enum FramesModeStyle {
    static func hue(_ mode: UInt64) -> Color { mode == 1 ? DS.textTertiary : DS.tint }

    static func glyph(_ mode: UInt64) -> String {
        switch mode {
        case 1:  return "checkmark.shield"
        case 2:  return "arrow.up.right"
        case 0:  return "arrow.turn.down.right"
        default: return "square.dashed"
        }
    }

    /// What the step is FOR, in words. A mode name means nothing to somebody
    /// who has not read EIP-8141, and the sheet is where it gets learned —
    /// `FramesSection.label`'s ruling, one level down.
    static func meaning(_ mode: UInt64) -> String {
        switch mode {
        case 1:
            return String(localized: "Authorises the transaction — without one there is no payer.")
        case 2:
            return String(localized: "Acts as the sender. This is where the value moves.")
        case 0:
            return String(localized: "The entry point calls it.")
        default:
            return String(localized: "A mode this build doesn't know.")
        }
    }
}

// MARK: - One transaction

/// A frame transaction as a receipt.
///
/// **The reading this seat exists for, at document size.** Every other
/// activity sheet in this app can say a transaction succeeded; a type-`0x06`
/// receipt reports per FRAME, so this one says which steps ran, what each
/// carried, where it went, what it cost and who paid — and, on the one case
/// that matters most, that the transaction failed and the money moved anyway.
struct FramesMoveSheet: View {
    let move: FramesMove
    /// The address whose read produced this move. In an unscoped room nothing
    /// else can say whose transaction it is, and a sheet that cannot answer
    /// "whose?" is a sheet about a stranger's money.
    var owner: String = ""
    var onOpenFrame: ((Int) -> Void)? = nil

    @Environment(BridgeStore.self) private var store

    private var mine: String? { FramesName.mine }
    private var watched: [String] { FramesName.watched }

    var body: some View {
        // SCROLLABLE AND DRAG-PAST (prd §560). The height below is a guess at
        // real text metrics, and a guess that runs short CLIPS the last block —
        // here the explorer link, on the sheet most likely to raise a question
        // this app cannot answer.
        DSTray(title: title, height: trayHeight, ink: true,
               detents: [.height(trayHeight), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    steps
                    facts
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

    private var trayHeight: CGFloat {
        // The head block's own chrome — the term the Hegotá sheets' first
        // arithmetic had no line for, and a deficit CLIPS.
        // Was `60` for the receipt paper's own `s6` top and `s6`-plus-a-tooth
        // bottom. §583 removed the paper; `dsSheetHeadBlock` pads `s4` top and
        // `s6` bottom, so the head is ~19pt shorter. Kept as a named term
        // rather than folded into the base, because a deficit CLIPS and the
        // next person to change the head's padding needs a line to change.
        let paper: CGFloat = 41
        let crossing: CGFloat = 76
        let sponsored: CGFloat = move.sponsored ? 46 : 0
        let watch: CGFloat = watchable == nil ? 0 : 34
        // **MEASURED OFF A DEVICE, NOT ESTIMATED** (user, 2026-09-02: *"the
        // verify and the move sheet were clipped at bottom"*). The first sum
        // had no term for the facts table or the explorer link and ran ~90pt
        // short on a four-frame transaction, which put the one door out of
        // this sheet below its own edge. The `.large` detent made it
        // reachable and nothing said so — a sheet that must be dragged to
        // finish reading is a sheet that looks broken.
        let facts: CGFloat = hasFacts ? 80 : 0
        let explorer: CGFloat = 40
        return min(920, 400 + paper + crossing + sponsored + watch + facts + explorer
                        + CGFloat(move.rows.count) * 56)
    }

    /// **THE DIRECTION NAMES THE SHEET.** Nil or zero gets the neutral noun:
    /// a delta that could not be read is not a transaction that moved nothing,
    /// and calling it "Money out" would be a claim built on a failed read.
    private var title: String {
        guard let delta = move.deltaWei, delta != 0 else {
            return String(localized: "Transaction")
        }
        return delta > 0 ? String(localized: "Money in") : String(localized: "Money out")
    }

    // MARK: The head

    /// **THE HEAD IS AN OBJECT, NOT A RUN OF TEXT** (prd §495) — the receipt
    /// paper Wallet and both devnet rooms already share, so this room cannot
    /// drift into a fifth kind of receipt.
    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                Text(FramesFormat.stamp(move.timestamp, block: move.blockNumber))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                DSStamp(word: move.verdict.word, weight: stampWeight)
            }
            amount.padding(.top, 2)
            crossing.padding(.top, DS.Space.s4)
            if let sponsorship {
                Text(sponsorship)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            }
        }
        .dsSheetHeadBlock()
    }

    /// `DSStamp.Weight` has no failure rung by design, so trouble wears
    /// `urgent` (attention) rather than a destructive colour — the frame
    /// sheet's own mapping, and Hegotá's before it.
    private var stampWeight: DSStamp.Weight {
        move.verdict.isTrouble ? .urgent : .good
    }

    @ViewBuilder private var amount: some View {
        if let delta = move.deltaWei {
            Text(FramesMoney.signedETH(wei: delta))
                // `price40` — the app's money-receipt hero (§363/§551), the
                // same rung the Wallet crown and Hegotá's receipts wear, so a
                // devnet figure can never outsize a real one.
                .dsText(.price40)
                .foregroundStyle(delta > 0 ? DS.confirm : DS.textPrimary)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
        } else {
            // **NOT A ZERO.** An unread delta and a transaction that moved
            // nothing must not look alike (§515a), and this is the largest
            // type on the sheet.
            Text(String(localized: "What it moved couldn't be read"))
                .dsText(.reading20).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **WHO, AND WHICH WAY — drawn once instead of said twice.**
    ///
    /// Hegotá's crossing, with this chain's difference: a frame transaction can
    /// pay SEVERAL addresses under one signature, which is the capability the
    /// whole seat is for. Several recipients are stacked and counted rather
    /// than listed — three short addresses on one line is a line nobody reads,
    /// and the strip below names every one of them in order.
    @ViewBuilder private var crossing: some View {
        HStack(spacing: DS.Space.s2) {
            endpoint(sender)
            Image(systemName: "arrow.right")
                .dsGlyph(13).foregroundStyle(DS.textTertiary)
            if move.recipients.isEmpty {
                // A batch of pure calls, or a transaction this room read off
                // the chain that paid nobody. Said rather than drawn as an
                // empty circle.
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(DS.surfaceWell)
                        Image(systemName: "circle.dashed")
                            .dsGlyph(15).foregroundStyle(DS.textTertiary)
                    }
                    .frame(width: DS.Face.list, height: DS.Face.list)
                    Text(String(localized: "nobody paid"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            } else {
                recipients
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sender: String { move.sender.isEmpty ? owner : move.sender }

    /// **SEVERAL RECIPIENTS ARE SEVERAL FACES, NOT ONE WEARING A COUNT.**
    ///
    /// The first cut drew `recipients[0]`'s identicon captioned "3 addresses" —
    /// a portrait of one specific person presented as a group, which is the
    /// `AssetMark` refusal (never let a mark stand for something it is not).
    /// A frame transaction paying three people under one signature is what
    /// this chain is FOR, so the drawing shows them.
    ///
    /// Capped at three and COUNTED past that, never truncated silently: the
    /// caption is the authority on how many there were, and the sheet's frame
    /// rows name every one of them in the order they ran.
    @ViewBuilder private var recipients: some View {
        let people = move.recipients
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                ForEach(Array(people.prefix(3).enumerated()), id: \.offset) { i, address in
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                        // Overlapped rather than spaced: the group is one
                        // endpoint of one crossing, and three faces in a row
                        // would read as three separate transactions.
                        .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                        .offset(x: CGFloat(i) * (DS.Face.list * 0.62))
                }
            }
            .frame(width: DS.Face.list + CGFloat(min(people.count, 3) - 1) * (DS.Face.list * 0.62),
                   height: DS.Face.list)
            Text(String(localized: "\(String(people.count)) addresses"))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func endpoint(_ address: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // An identicon is a function of an ADDRESS, so an empty one
                // would draw a face for nobody — a portrait of a string we do
                // not have (`AssetMark`'s refusal).
                if address.isEmpty {
                    Circle().fill(DS.surfaceWell)
                } else {
                    WalletFace(address: address, size: DS.Face.list, circular: true)
                }
            }
            .frame(width: DS.Face.list, height: DS.Face.list)
            Text(address.isEmpty
                 ? String(localized: "unknown")
                 : FramesName.of(address, mine: mine, watched: watched))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Sponsorship as the head's closing sentence — Hegotá's slot, and this
    /// chain publishes the same `payer` field that makes it sayable at all.
    private var sponsorship: String? {
        guard move.sponsored else { return nil }
        let who = FramesName.of(move.payer, mine: mine, watched: watched)
        if let fee = move.feeWei, let figure = FramesMoney.fee(wei: fee) {
            return String(localized: "\(who) paid the gas — \(figure) ETH.")
        }
        return String(localized: "\(who) paid the gas.")
    }

    // MARK: The steps

    /// **THE SHAPE FIRST, THEN THE DETAIL.**
    ///
    /// The strip is the room's own `FramesSequenceStrip` — the same drawing,
    /// not a copy, so a transaction cannot be pictured one way in the slot and
    /// another way in its sheet. It stays a PICTURE and the rows below are the
    /// doors: a `Canvas` has no per-cell hit testing, and a strip whose cells
    /// are 12pt wide is not a tap target anybody could aim at.
    @ViewBuilder private var steps: some View {
        if !move.rows.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(move.rows.count == 1 ? String(localized: "1 frame")
                                          : String(localized: "\(String(move.rows.count)) frames"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                FramesSequenceStrip(runs: [move.rows]).frame(height: 20)
                ForEach(Array(move.rows.enumerated()), id: \.offset) { index, row in
                    Button {
                        DSHaptic.selection()
                        onOpenFrame?(index)
                    } label: {
                        frameRow(index: index, row: row).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func frameRow(index: Int, row: FramesFrameRow) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            // **THE PIP IS THE EFFECT, NOT THE STATUS.** A rolled-back frame
            // reports success, so filling this from `outcome.succeeded` would
            // draw a green dot beside money that never moved — the §548 trap,
            // in the smallest element on the sheet.
            Circle()
                .fill(pipFill(row))
                .overlay(Circle().strokeBorder(DS.destructive,
                                               lineWidth: row.valueLanded == false ? 1.5 : 0))
                .frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "\(String(index + 1)). \(row.frame.modeName)"))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                if let target = row.frame.target, !target.isEmpty {
                    Text(FramesName.of(target, mine: mine, watched: watched))
                        .dsText(.label12).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                if let hex = row.valueWeiHex, let value = FramesMoney.eth(fromWeiHex: hex, places: 6) {
                    Text(String(localized: "\(value) ETH"))
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                }
                if let gas = row.outcome?.gasUsed {
                    Text(String(localized: "\(DSCount.grouped(gas)) gas"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary).monospacedDigit()
                }
            }
            WalletRowChevron().padding(.top, 3)
        }
    }

    /// Hollow for a rolled-back frame (the strip's own dashed treatment as a
    /// dot), clear for an unread outcome, the mode's hue otherwise.
    private func pipFill(_ row: FramesFrameRow) -> Color {
        if row.valueLanded == false { return .clear }
        guard let outcome = row.outcome else { return DS.textTertiary.opacity(0.4) }
        return outcome.succeeded ? FramesModeStyle.hue(row.frame.mode) : DS.destructive
    }

    // MARK: The facts

    /// **THE FACTS AS A TABLE, NOT AS FOUR SENTENCES** (`DSSpecTable`).
    ///
    /// The date is not here — it is the head's dateline, said once. Nor is the
    /// payer (the head's own sentence names them) nor the recipient count (the
    /// crossing draws the faces and counts them) — both were rows here until
    /// §605, saying on the same document what the block above already said.
    @ViewBuilder private var facts: some View {
        if hasFacts {
            DSSpecTable {
                // Only when the sender really paid it. A "Fee" row under a head
                // whose own last sentence says somebody else paid is the two
                // halves of one document disagreeing.
                // `fee(wei:)`, never `feeLine` — that one wears the noun,
                // and under a label reading "Fee" it renders `0.000595 fee`.
                // Seen on a device.
                if let fee = FramesMoney.fee(wei: move.feeWeiIfSelfPaid) {
                    DSSpecRow(label: Text("Fee"), value: Text(verbatim: fee))
                }
                if let gas = move.gasUsed {
                    // **THE RECEIPT'S OWN, NEVER A SUM OF THE FRAMES.**
                    // Measured on a transaction this app sent: the frames
                    // report 100 and 3,000 against a receipt of 210,790, so a
                    // sum is wrong by two orders of magnitude in the direction
                    // that looks plausible.
                    DSSpecRow(label: Text("Gas"), value: Text(verbatim: DSCount.grouped(gas)))
                }
            }
        }
    }

    /// An empty `DSSpecTable` is a zero-height `Grid` that still costs its
    /// stack a `DS.Space.s6` gap — a hole in the sheet with nothing in it.
    private var hasFacts: Bool {
        move.feeWeiIfSelfPaid != nil || move.gasUsed != nil
    }

    // MARK: The doors

    /// **The address on the other side, watchable from here.**
    ///
    /// The room's own argument, sharper on this chain than on Hegotá's: there
    /// are eighteen addresses on the whole network, so the ones you meet in
    /// your own transactions are very nearly the only ones worth watching —
    /// and watching one otherwise meant memorising forty hex characters,
    /// leaving the room and pasting them into a setup screen.
    ///
    /// **The RECIPIENT before the sender**, and only ever one door: after a
    /// send, the address you just paid is the one you want to follow, and two
    /// buttons reading "Watch 0x…" stacked on each other is a choice with no
    /// way to tell them apart.
    private var watchable: String? {
        let candidates = move.recipients + [sender]
        return candidates.first {
            !$0.isEmpty && FramesParty.of($0, mine: mine, watched: watched).isStranger
        }
    }

    /// **NEVER IN THE DEMO** (§549's class, and it was reachable). The demo's
    /// accounts are a fixture, not this phone's — so this door offered to add
    /// a demo address to the REAL watch list, which survives the demo's own
    /// teardown and is exactly the "hard coded demo stuff … that i did not
    /// add" §549 was reported for.
    @ViewBuilder private var watchDoor: some View {
        if let address = watchable, !DemoMode.isActive {
            Button {
                DSHaptic.selection()
                if FramesWatch.shared.add(address) {
                    FramesBridge.registerBridge(store: store)
                    // Sweeping immediately is the point — a watch that shows
                    // nothing until the next foreground pass reads as a button
                    // that did nothing.
                    Task { await FramesLiveState.shared.refresh() }
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
    /// `NetworkReach`.
    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(FramesIdentity.explorer)/tx/\(move.hash)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }
}

// MARK: - One frame

/// A single step of a frame transaction, as its own document.
///
/// **This is what makes frames first-class rather than a detail**, and on this
/// chain that is the whole product: EIP-8141 is a draft, no wallet can encode
/// one, and the frame is the object the network is named for. It was a row
/// inside another sheet with nowhere to go, wearing a mode name that means
/// nothing to somebody who has not read the spec.
///
/// **AND IT IS THE ONLY PLACE THE PERMISSION CAN BE READ.** `FramesSection`'s
/// own ruling says so: authorisation on this chain is PER-TRANSACTION — a
/// VERIFY frame's `flags` carry the `APPROVE` scope for execution and payment,
/// nothing survives the transaction, and there is no standing grant anywhere
/// to list. So the seat has no Permissions scope, the frames scope "must always
/// say whether a VERIFY frame approved execution, payment or both", and until
/// this sheet existed the only surface in the app that ever said it was the
/// send preview — before the fact, never after.
struct FramesFrameSheet: View {
    let move: FramesMove
    let index: Int
    /// Step-to-step through the ONE sheet, so a neighbour rises where this
    /// step was rather than as a second tray over it.
    var onOpenFrame: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mine: String? { FramesName.mine }
    private var watched: [String] { FramesName.watched }

    private var row: FramesFrameRow? {
        move.rows.indices.contains(index) ? move.rows[index] : nil
    }
    private var total: Int { move.rows.count }

    /// **A SUM WITH A TERM PER BLOCK, because a flat number clipped** (user,
    /// 2026-09-02). It was `total > 1 ? 760 : 660`, which took no account of
    /// the two blocks that only some frames carry — so a VERIFY frame, which
    /// is the one that gains the whole permission section, was the one most
    /// likely to lose its neighbour doors off the bottom.
    private var trayHeight: CGFloat {
        guard let row else { return 420 }
        let permission: CGFloat = row.frame.mode == 1 ? 170 : 0
        let joined: CGFloat = (row.joinedToNext || (index > 0 && move.rows[index - 1].joinedToNext))
            ? 44 : 0
        let neighbours: CGFloat = total > 1 ? 56 : 0
        let value: CGFloat = row.valueWeiHex == nil ? 0 : 56
        // 680 is MEASURED off the device rather than reasoned about, twice:
        // the first sum ran ~90pt short on a VERIFY frame and cut the calldata
        // row and both neighbour doors, which are the sheet's only way onward.
        // The cap is generous on purpose — over-tall rests at a taller sheet,
        // short CLIPS, and only one of those is recoverable by the reader.
        // Down from 680 with the three duplicated fact rows gone — the sheet
        // got shorter rather than the box getting taller.
        return min(940, 560 + permission + joined + neighbours + value)
    }

    var body: some View {
        let height = trayHeight
        DSTray(title: row?.frame.modeName ?? String(localized: "Step"),
               height: height, ink: true, detents: [.height(height), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    if let row {
                        head(row)
                        permission(row)
                        budget(row)
                        evidence(row)
                        join
                        facts(row)
                        neighbours
                    } else {
                        Text(String(localized: "This step is no longer available."))
                            .dsText(.body17).foregroundStyle(DS.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: The head

    @ViewBuilder private func head(_ row: FramesFrameRow) -> some View {
        let tone = FramesModeStyle.hue(row.frame.mode)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(tone.opacity(0.16))
                    Image(systemName: FramesModeStyle.glyph(row.frame.mode))
                        .dsGlyph(24).foregroundStyle(tone)
                }
                .frame(width: DS.Face.shelf, height: DS.Face.shelf)
                Spacer(minLength: 0)
                DSStamp(word: outcomeWord(row), weight: outcomeWeight(row))
            }
            Text(position)
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .padding(.top, DS.Space.s3)
            if let hex = row.valueWeiHex, let value = FramesMoney.eth(fromWeiHex: hex, places: 6) {
                Text(String(localized: "\(value) test ETH"))
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, 2)
                Text(FramesModeStyle.meaning(row.frame.mode))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s4)
            } else {
                // A step that moves nothing leads with what it DOES, at
                // `reading20` — running prose that is the whole point of the
                // surface it sits on, which is that rung's own definition. The
                // mode name is not repeated: the tray title already carries it.
                Text(FramesModeStyle.meaning(row.frame.mode))
                    .dsText(.reading20).foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .dsSheetHeadBlock()
    }

    private var position: String {
        guard total > 1 else { return String(localized: "One step") }
        return String(localized: "Step \(String(index + 1)) of \(String(total))")
    }

    /// **FOUR STATES, and the third is this chain's own.** Hegotá's frame sheet
    /// has three; here a frame can report success AND have been reverted, so
    /// "Ran" over it would be the §548 lie in the slot every sheet in this app
    /// keeps for a state.
    private func outcomeWord(_ row: FramesFrameRow) -> String {
        if row.valueLanded == false { return String(localized: "Rolled back") }
        guard let outcome = row.outcome else { return String(localized: "Outcome unknown") }
        return outcome.succeeded ? String(localized: "Ran") : String(localized: "Reverted")
    }

    /// `quiet` for the unknown, deliberately: it used to be tempting to give it
    /// `attention`, which raises an alarm about a reading we simply do not have
    /// — `DSStamp`'s own doc, that quiet is a real answer rather than an
    /// absence.
    private func outcomeWeight(_ row: FramesFrameRow) -> DSStamp.Weight {
        if row.valueLanded == false { return .urgent }
        guard let outcome = row.outcome else { return .quiet }
        return outcome.succeeded ? .good : .urgent
    }

    // MARK: The permission

    /// **THE PERMISSION, SAID OUT LOUD** — see the type doc. A VERIFY frame
    /// with neither bit leaves the transaction with no payer, which is not
    /// under-permissioned but INVALID, and it is worth saying in those words.
    @ViewBuilder private func permission(_ row: FramesFrameRow) -> some View {
        if row.frame.mode == 1 {
            let execution = row.frame.approvesExecution
            let payment = row.frame.approvesPayment
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(String(localized: "What it approves"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                HStack(spacing: DS.Space.s2) {
                    approval(String(localized: "Running"), granted: execution)
                    approval(String(localized: "Payment"), granted: payment)
                }
                // **THE FOOTNOTE IS TWELVE WORDS AND WAS TWENTY-ONE.** The
                // long form explained that authority here is per-transaction;
                // the short one states the consequence, which is the only part
                // that changes what somebody would DO (§315). The head above
                // already says a VERIFY frame authorises.
                if !execution && !payment {
                    Text(String(localized: "Approves neither, so the transaction has no payer."))
                        .dsText(.subhead13).foregroundStyle(DS.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "Spent inside this transaction — nothing to revoke."))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func approval(_ word: String, granted: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .dsGlyph(14)
                .foregroundStyle(granted ? DS.confirm : DS.textTertiary)
            Text(word).dsText(.callout15)
                .foregroundStyle(granted ? DS.textPrimary : DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s3)
        .padding(.vertical, DS.Space.s2)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.surfaceWell)
        }
    }

    // MARK: The budgets

    /// **WHAT IT WAS GIVEN AGAINST WHAT IT USED**, which is the reading a raw
    /// `36,334 gas` cannot make on its own.
    ///
    /// **NOT a share of the transaction's gas**, which is Hegotá's version of
    /// this figure and would be wrong here: measured on a transaction this app
    /// sent, the frames report 100 and 3,000 against a receipt of 210,790, so
    /// over 98% of the real cost is attributed to no frame at all — a share
    /// would claim a cost breakdown this chain does not publish. A frame's
    /// budget is a fact it carries in its own right.
    /// Nothing at all when the chain reported neither budget — an empty
    /// `VStack` is a REAL view of zero height and still costs its enclosing
    /// stack a `DS.Space.s6` gap, which is a hole in the sheet with nothing in
    /// it (the move sheet's `hasFacts` guard, one sheet over).
    private func hasBudget(_ row: FramesFrameRow) -> Bool {
        if let limit = row.frame.executionGas, limit > 0, row.outcome?.gasUsed != nil { return true }
        if let limit = row.frame.stateGas, limit > 0 { return true }
        return row.outcome.flatMap { FramesRead.starvation(frame: row.frame, outcome: $0) } != nil
    }

    @ViewBuilder private func budget(_ row: FramesFrameRow) -> some View {
        if hasBudget(row) {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let limit = row.frame.executionGas, limit > 0, let used = row.outcome?.gasUsed {
                FramesBudgetBar(caption: String(localized: "Execution"),
                                used: used, limit: limit, tint: DS.tint,
                                reduceMotion: reduceMotion)
            }
            stateReading(row)
        }
        }
    }

    /// **`stateGasUsed` IS ABSENT ON THIS CHAIN AND THAT IS SAID, NOT HIDDEN.**
    ///
    /// Measured 2026-09-01 across every frame on the network, including one
    /// sent to a freshly generated address — which GROWS state, so this is the
    /// field's absence rather than a fixture's omission. Nil means the chain
    /// did not say, which is a different fact from zero, and it is the whole
    /// point: `0x0` is the discriminator that tells a missing STATE budget
    /// apart from a too-small EXECUTION one.
    ///
    /// The budget itself is still worth stating — it is what the sender ASKED
    /// for, and on a devnet it is the number somebody is tuning.
    @ViewBuilder private func stateReading(_ row: FramesFrameRow) -> some View {
        if let used = row.outcome?.stateGasUsed, let limit = row.frame.stateGas, limit > 0 {
            FramesBudgetBar(caption: String(localized: "State"),
                            used: used, limit: limit, tint: DS.confirm,
                            reduceMotion: reduceMotion)
        } else if let limit = row.frame.stateGas, limit > 0 {
            Text(String(localized: "State budget \(DSCount.grouped(limit))"))
                .dsText(.label12).foregroundStyle(DS.textTertiary).monospacedDigit()
        }
        if let starvation = row.outcome.flatMap({ FramesRead.starvation(frame: row.frame, outcome: $0) }) {
            Text(starvation == .state
                 // The one sentence here somebody would ACT on, so it keeps
                 // its full length while everything around it loses a clause.
                 ? String(localized: "It ran out of STATE budget, not execution — raising the execution limit will not help.")
                 : String(localized: "It used its whole execution budget and reverted."))
                .dsText(.subhead13).foregroundStyle(DS.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What actually happened

    /// **THE EVIDENCE, which on this chain is a LOG rather than a status.**
    ///
    /// Every ETH movement here is an EIP-7708 log, so the log IS the effect and
    /// its absence IS the rollback — the third of the three readings §500 says
    /// a devnet like this earns a seat for, and the one that makes a rolled-back
    /// frame distinguishable from a successful one at all.
    @ViewBuilder private func evidence(_ row: FramesFrameRow) -> some View {
        switch row.valueLanded {
        case .some(true):
            note(String(localized: "The money moved."),
                 tone: DS.textSecondary)
        case .some(false):
            note(String(localized: "Reports success — the money did not move."),
                 tone: DS.destructive)
        case .none:
            if row.outcome == nil {
                note(String(localized: "Its receipt couldn't be read."),
                     tone: DS.textTertiary)
            }
        }
    }

    /// **THE JOIN, from this step's own point of view.**
    ///
    /// `flags` bit 2 means "joined to the frame after me" — the node's own
    /// correction, proven by it refusing the flag on a last frame — so a run of
    /// joined frames plus the first unjoined one after them is ONE atomic
    /// group. Said in both directions because a person reading step 3 wants to
    /// know it is roped to step 2, which step 2's own flag is what says.
    ///
    /// The flag reaches this file through `FramesFrameRow.joinedToNext` and
    /// nothing else, which is the same one-door rule `frames-tx-selftest.sh`
    /// pins on the strip.
    @ViewBuilder private var join: some View {
        let joinsNext = row?.joinedToNext == true && index + 1 < total
        let joinsPrev = index > 0 && move.rows[index - 1].joinedToNext
        if joinsNext || joinsPrev {
            let word: String = {
                if joinsNext && joinsPrev {
                    return String(localized: "Roped either side — all or nothing.")
                }
                if joinsNext {
                    return String(localized: "Roped to step \(String(index + 2)) — all or nothing.")
                }
                return String(localized: "Roped to step \(String(index)) — all or nothing.")
            }()
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "link").dsGlyph(13).foregroundStyle(DS.tint)
                Text(word).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The facts

    /// **WHAT IS NOT ALREADY ON THE SCREEN, and that is the whole edit** (user,
    /// 2026-09-02, of this sheet running past the fold).
    ///
    /// It listed five rows and three of them were the SAME FACTS the bar and
    /// the sentence directly above already state: `Execution: 100 of 100000`
    /// is the budget and the used figure, and "It asked for 250000 of state
    /// budget" is the state one. So the sheet said each of them twice, in two
    /// registers, and paid ~130pt for it — which is most of what pushed the
    /// calldata row and both neighbour doors below the fold.
    ///
    /// The answer was never a taller sheet. One fact, one place.
    @ViewBuilder private func facts(_ row: FramesFrameRow) -> some View {
        DSSpecTable {
            // **A VERIFY FRAME TARGETS THE SENDER, ALWAYS**, so naming it here
            // tells you what the mode already told you — and on the one row
            // where a target IS news (a payload frame), the crossing on the
            // move sheet and this sheet's own recipient both carry it. Shown
            // only when it is something other than the sender.
            if let target = row.frame.target, !target.isEmpty,
               target.lowercased() != move.sender.lowercased() {
                DSSpecRow(label: Text("Target"),
                          value: Text(verbatim: FramesName.leading(
                            target, mine: mine, watched: watched)))
            }
            DSSpecRow(label: Text("Calldata"), value: Text(verbatim: calldataLine(row)))
        }
    }

    /// **CALLDATA, WHICH NOTHING ON THIS CHAIN HAS EVER CARRIED.**
    ///
    /// Named rather than assumed absent (§548's own "untested" list): the
    /// envelope has always supported it and no transaction here has used it,
    /// so a row that simply omitted the field would make the day one appears
    /// indistinguishable from every day before it. The selector is the first
    /// four bytes — the only part of a call anybody reads at a glance.
    private func calldataLine(_ row: FramesFrameRow) -> String {
        let raw = row.frame.data ?? ""
        let body = raw.hasPrefix("0x") || raw.hasPrefix("0X") ? String(raw.dropFirst(2)) : raw
        guard !body.isEmpty else { return String(localized: "none") }
        let bytes = body.count / 2
        guard bytes >= 4 else {
            return bytes == 1 ? String(localized: "1 byte")
                              : String(localized: "\(String(bytes)) bytes")
        }
        return String(localized: "0x\(String(body.prefix(8))) · \(String(bytes)) bytes")
    }

    // MARK: The neighbours

    /// The steps either side, as doors.
    ///
    /// Each names the neighbour's MODE rather than saying "Previous", because
    /// what somebody wants to know is what comes next, not that something does.
    @ViewBuilder private var neighbours: some View {
        if total > 1 {
            HStack(spacing: DS.Space.s3) {
                if index > 0 { step(at: index - 1, back: true) }
                Spacer(minLength: 0)
                if index + 1 < total { step(at: index + 1, back: false) }
            }
        }
    }

    @ViewBuilder private func step(at target: Int, back: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onOpenFrame?(target)
        } label: {
            HStack(spacing: DS.Space.s2) {
                if back { Image(systemName: "chevron.left").dsGlyph(12) }
                Text(move.rows[target].frame.modeName).dsText(.callout15)
                if !back { Image(systemName: "chevron.right").dsGlyph(12) }
            }
            .foregroundStyle(DS.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func note(_ text: String, tone: Color) -> some View {
        Text(text).dsText(.callout15).foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One gas budget against what was spent of it.
///
/// **The bar is CLAMPED and the figures are not.** A frame that reverts having
/// used exactly its budget is the state-starvation signature this chain's own
/// guide names, so `used == limit` is a real and important reading; anything
/// above it would be a drawing running off its own track, and the numbers
/// beside it say what really happened either way.
struct FramesBudgetBar: View {
    let caption: String
    let used: UInt64
    let limit: UInt64
    let tint: Color
    let reduceMotion: Bool

    private var share: Double {
        guard limit > 0 else { return 0 }
        return min(1, Double(used) / Double(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fillFaint)
                    Capsule().fill(tint.opacity(0.85))
                        // A FLOOR, so a frame that used 100 of 100,000 draws as
                        // something rather than as a frame that ran for free.
                        .frame(width: max(share > 0 ? 3 : 0, geo.size.width * CGFloat(share)))
                }
            }
            .frame(height: 10)
            // Sized from data, so it earns an entrance (design-motion law) and
            // stands still under Reduce Motion.
            .chartWipe(reduceMotion: reduceMotion)
            Text(String(localized: "\(caption): \(DSCount.grouped(used)) of \(DSCount.grouped(limit))"))
                .dsText(.label12).foregroundStyle(DS.textTertiary).monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "\(caption) budget, \(DSCount.grouped(used)) of \(DSCount.grouped(limit)) used")))
    }
}

// MARK: - One sponsor

/// Somebody who paid for another address's transactions.
///
/// **The reading this chain publishes that no ordinary chain can**, and until
/// now the Sponsors scope drew it as a single split bar with no way to ask who
/// the other half belonged to. A sponsor is also the one stranger on this
/// network genuinely worth watching: they have spent real gas on somebody
/// else's behalf, which is a stronger reason to follow an address than any
/// balance on a chain whose money has no value.
struct FramesPayerSheet: View {
    let payer: FramesPayer
    /// Every move the room is showing, so the sheet can list this payer's own
    /// and state their share. Passed in rather than re-read: the room may be
    /// scoped to one address, and a sheet that quietly widened to every account
    /// would answer a question nobody asked.
    let moves: [FramesMove]
    var onOpenMove: ((FramesMove) -> Void)? = nil

    @Environment(BridgeStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mine: String? { FramesName.mine }
    private var watched: [String] { FramesName.watched }
    private var theirs: [FramesMove] { FramesPayers.moves(of: payer.address, in: moves) }

    var body: some View {
        // **MEASURED, after this sheet clipped its own explorer link** (user,
        // 2026-09-02). The first sum counted the rows and nothing else — not
        // the paper, not the share bar, not the caption, not the two doors —
        // so a one-transaction sponsor, which is every sponsor on this chain
        // today, lost its last line off the bottom.
        let watch = FramesParty.of(payer.address, mine: mine, watched: watched).isStranger
            && !DemoMode.isActive
        let height = min(920, 620 + (watch ? 44 : 0)
                              + CGFloat(min(theirs.count, 6)) * 72)
        DSTray(title: FramesName.leading(payer.address, mine: mine, watched: watched),
               height: height, ink: true, detents: [.height(height), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    share
                    list
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

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                WalletFace(address: payer.address, size: DS.Face.shelf, circular: true)
                Spacer(minLength: 0)
                Text(WalletStore.shortAddress(payer.address))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            }
            // `fee(wei:)` and not `feeLine` — that one appends "fee", which at
            // `price40` renders `0.000402 fee` as the largest thing on the
            // sheet. The sentence under it says what the figure is; the hero
            // says how much.
            if let wei = payer.gasWei, let figure = FramesMoney.fee(wei: wei) {
                Text(String(localized: "\(figure) ETH"))
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, DS.Space.s3)
            } else {
                // **NOT A ZERO.** A total we could not complete is not a
                // sponsor who paid nothing — `FramesPayer.gasWei`'s
                // all-or-nothing rule, and this is the line it exists for.
                Text(String(localized: "The total couldn't be read"))
                    .dsText(.reading20).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
            Text(payer.count == 1
                 ? String(localized: "Paid for 1 transaction")
                 : String(localized: "Paid for \(String(payer.count)) transactions"))
                .dsText(.callout15).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s4)
        }
        .dsSheetHeadBlock()
    }

    /// Their share of every fee this room can see.
    ///
    /// **Drawn only when EVERY fee in the room read.** A share whose
    /// denominator is missing a term overstates the numerator, which here means
    /// telling somebody a sponsor covered more of their gas than they did.
    @ViewBuilder private var share: some View {
        // **GAS, THE SAME BASIS THE ROOM'S OWN SPLIT BAR USES.** It was built
        // on `feeWei`, which needs the receipt's gas PRICE as well as its gas
        // — and this chain's faucet payments carry no price, so one of them
        // anywhere in the room made the whole share decline while the bar in
        // the slot two taps away happily drew 23%. Two surfaces answering one
        // question, one of them silent.
        //
        // The all-or-nothing rule is unchanged and still load-bearing: a
        // denominator missing a term overstates the numerator, which here
        // means crediting a sponsor with more than they covered.
        let all = moves.map(\.gasUsed)
        let mineGas = theirs.compactMap(\.gasUsed).map(Double.init).reduce(0, +)
        if !all.contains(where: { $0 == nil }), theirs.allSatisfy({ $0.gasUsed != nil }) {
            let total = all.compactMap { $0 }.map(Double.init).reduce(0, +)
            if total > 0 {
                let fraction = mineGas / total
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fillFaint)
                            Capsule().fill(DS.tint)
                                .frame(width: max(3, geo.size.width * CGFloat(min(1, fraction))))
                        }
                    }
                    .frame(height: 10)
                    .chartWipe(reduceMotion: reduceMotion)
                    Text(String(localized: "\(String(Int((fraction * 100).rounded())))% of the room's gas"))
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        if !theirs.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(String(localized: "What they paid for"))
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                VStack(spacing: DS.Space.s2) {
                    ForEach(theirs) { move in
                        Button {
                            DSHaptic.selection()
                            onOpenMove?(move)
                        } label: {
                            // Every row here was paid for by the person this
                            // sheet is ABOUT, so the word separates nothing —
                            // the room's Sponsors scope drops it for the same
                            // reason one level up.
                            FramesMoveRow(move: move, showsSponsorship: false)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Never in the demo — see `FramesMoveSheet.watchDoor`.
    @ViewBuilder private var watchDoor: some View {
        if FramesParty.of(payer.address, mine: mine, watched: watched).isStranger,
           !DemoMode.isActive {
            Button {
                DSHaptic.selection()
                if FramesWatch.shared.add(payer.address) {
                    FramesBridge.registerBridge(store: store)
                    Task { await FramesLiveState.shared.refresh() }
                }
            } label: {
                Text(String(localized: "Watch \(WalletStore.shortAddress(payer.address))"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(FramesIdentity.explorer)/address/\(payer.address)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }
}

// MARK: - One account

/// A watched address, or this phone's own.
///
/// **Its facts are DOORS.** Hegotá's account sheet shipped as a summary that
/// named three readings the room can show and offered no way to any of them,
/// which is §83's dead control wearing the shape of a paragraph; that lesson is
/// taken here rather than re-learned. Each count scopes the room to this
/// address and opens the list it names.
struct FramesAccountSheet: View {
    let account: FramesAccount
    /// Scope the room to this address and open a section.
    var onScope: ((FramesSection) -> Void)? = nil

    @Environment(BridgeStore.self) private var store
    @State private var copied = false

    private var mine: String? { FramesName.mine }
    private var watched: [String] { FramesName.watched }
    private var isMine: Bool {
        if case .you = FramesParty.of(account.address, mine: mine, watched: watched) { return true }
        return false
    }

    private var curve: [Double] {
        FramesRoom.curve(balanceWeiHex: account.balanceWeiHex,
                         newestFirst: account.moves.sorted { $0.blockNumber > $1.blockNumber })
    }

    var body: some View {
        let height: CGFloat = 660
        DSTray(title: FramesName.leading(account.address, mine: mine, watched: watched),
               height: height, ink: true, detents: [.height(height), .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    head
                    if curve.count > 1 {
                        FramesBalanceCurve(points: curve)
                            .frame(height: 56).frame(maxWidth: .infinity)
                    }
                    doing
                    manage
                    explorer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                WalletFace(address: account.address, size: DS.Face.shelf, circular: true)
                Spacer(minLength: 0)
                Button {
                    DSHaptic.selection()
                    // SENSITIVE: an address is pasted within seconds or not at
                    // all, and this pasteboard never leaves the device.
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
            if let line = FramesMoney.balanceLine(weiHex: account.balanceWeiHex) {
                Text(line)
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.top, DS.Space.s3)
            } else {
                // NOT a zero — an unreached read is not evidence of an empty
                // account, which on a devnet that may have been reset is the
                // likeliest reading of all (§515a).
                Text(String(localized: "The chain didn't answer"))
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

    /// **The nonce IS the count** — it is incremented per transaction the
    /// account signs, so this is a fact off the chain rather than a tally of
    /// what was read back. Nil is not zero: a nonce that did not read is not an
    /// account that has never sent.
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

    /// What this address has been doing — each row a door into the scope that
    /// draws it.
    @ViewBuilder private var doing: some View {
        let frames = account.moves.filter { $0.rows.count > 1 }.count
        let sponsored = account.moves.filter(\.sponsored).count
        DSSpecTable {
            // A door onto an empty scope is §83's dead control: with no
            // transactions the row states its zero and opens nothing.
            let opens = !account.moves.isEmpty
            DSSpecRow(label: Text("Transactions"),
                      value: Text(verbatim: String(account.moves.count)),
                      tint: opens ? DS.tint : DS.textPrimary,
                      glyph: opens ? "chevron.right" : nil,
                      action: opens ? { onScope?(.activity) } : nil)
            if frames > 0 {
                DSSpecRow(label: Text("Frame transactions"),
                          value: Text(verbatim: String(frames)),
                          tint: DS.tint, glyph: "chevron.right",
                          action: { onScope?(.frames) })
            }
            if sponsored > 0 {
                DSSpecRow(label: Text("Somebody else paid"),
                          value: Text(verbatim: String(sponsored)),
                          tint: DS.tint, glyph: "chevron.right",
                          action: { onScope?(.sponsors) })
            }
            let rolled = account.rolledBack.count
            if rolled > 0 {
                // Never a door: the Frames scope draws these as dashed cells
                // with their own caption, so the door beside "Frame
                // transactions" already goes there. Two rows leading to one
                // place is two controls for one consequence (§190).
                DSSpecRow(label: Text("Rolled back"), value: Text(verbatim: String(rolled)))
            }
        }
    }

    /// **Watching is the verb this sheet owns, and it has exactly one form.**
    ///
    /// Never offered for this phone's own account: the room reads it whether or
    /// not it is watched (`FramesLiveState.refresh` inserts it), so an unwatch
    /// there would be a control whose consequence is invisible — and a watch
    /// button beside an address already on screen is the dead control §83 bans.
    /// Never in the demo — see `FramesMoveSheet.watchDoor`. Seen offering
    /// "Watch this address" over the demo's own fixture account.
    @ViewBuilder private var manage: some View {
        if !isMine, !DemoMode.isActive {
            if FramesWatch.shared.isWatching(account.address) {
                Button {
                    DSHaptic.selection()
                    FramesWatch.shared.remove(account.address)
                    FramesBridge.registerBridge(store: store)
                    Task { await FramesLiveState.shared.refresh() }
                } label: {
                    Text(String(localized: "Stop watching"))
                        .dsText(.callout15).foregroundStyle(DS.textTertiary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    DSHaptic.selection()
                    if FramesWatch.shared.add(account.address) {
                        FramesBridge.registerBridge(store: store)
                        Task { await FramesLiveState.shared.refresh() }
                    }
                } label: {
                    Text(String(localized: "Watch this address"))
                        .dsText(.callout15).foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var explorer: some View {
        if let url = URL(string: "\(FramesIdentity.explorer)/address/\(account.address)") {
            Link(destination: url) {
                Text(String(localized: "Open in the explorer"))
                    .dsText(.callout15).foregroundStyle(DS.tint)
            }
        }
    }
}
