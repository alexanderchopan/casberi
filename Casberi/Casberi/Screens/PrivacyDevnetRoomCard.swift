import SwiftUI

// The switcher's protocol is declared HERE, not on the enum, so
// `PrivacyDevnetSection` stays Foundation-only and the harness can compile it
// whole. Both sibling seats do exactly this and for the same reason — putting
// the conformance on the type broke `privacy-selftest` the moment the room
// gained a switcher.
extension PrivacyDevnetSection: DSSectionScope {}

/// The Ethrex Privacy room's drawing (prd §593, reshaped §596).
///
/// **The window meter is the one thing this room has that nothing else in the
/// app does**, so it leads when there is one — and it is drawn only over a
/// LIVE root. An aged root gets the sentence and no meter, because a bar
/// reading near-empty and a bar with nothing to measure are different claims
/// (`PrivacyDevnetRoots.fraction` returns nil rather than zero for exactly
/// this reason, and the harness pins it).
///
/// **No colour carries state here.** The meter is the tint at one opacity and
/// the track is `DS.fillFaint`; nothing is red for aged or green for live,
/// because neither is good or bad — a proof whose snapshot has left the ring
/// was valid when it landed and its transaction is settled. Colour would say
/// something the chain does not.
///
/// **THE SCOPE HEADLINE IS A COUNT, NEVER A SENTENCE (prd §596).** Every
/// non-home scope drew `section.summary` at `heading22` INSIDE the slot, above
/// its figure — a sentence standing on the chart, which no sibling room does.
/// The chassis-reserved `stat24` row now carries a count the way Frames,
/// Hegotá and vibenet's scopes do, and the summary survives where it always
/// belonged: the chip's accessibility label.
struct PrivacyDevnetRoomCard: View {
    let head: PrivacyDevnetRoom.Head
    /// Which scope is showing. **Every chip must change what is drawn** — a
    /// strip whose seven chips all show one card is seven dead controls, which
    /// is worse than no strip at all (§83). Found by opening the room on a
    /// simulator; the scopes were computed correctly and drew the same thing.
    var section: PrivacyDevnetSection = .home
    /// The accounts the scope is showing, for the scopes that list them.
    var accounts: [PrivacyDevnetAccount] = []
    /// The chain's head slot, so a root can say how much window it has left.
    var headSlot: UInt64 = 0
    /// What the last walk could not read (prd §593d). Empty on every pass
    /// today; the room says so the day it is not.
    var walkCut = PrivacyDevnetLiveState.WalkCut()
    /// Opens one transaction's sheet (prd §596). Nil for a preview — and then
    /// the rows draw without a chevron, because a chevron over a tap that does
    /// nothing is §83's dead control.
    var onOpenMove: ((PrivacyDevnetLiveState.Move, String) -> Void)? = nil
    /// Opens one watched address's sheet (prd §596).
    var onOpenAccount: ((PrivacyDevnetAccount) -> Void)? = nil

    /// §299: a drawing sized from data gets an entrance, and the entrance
    /// honours Reduce Motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The spend keys this device had never seen when the scope opened — the
    /// only ones whose ring seals (prd §598). Empty on an install's first read
    /// by construction, so arriving somewhere does not look like forty things
    /// happening.

    var body: some View {
        // Home's sentence IS the crown — a figure that occupies exactly the
        // role a headline plays — so the row is reserved only where the
        // chassis draws one (`DSRoomSlot.reservesHeadline`'s own rule).
        DSRoomSlot(headline: slotHeadline,
                   reservesHeadline: section != .home || !marks.isEmpty) { content }
    }

    /// One `stat24` line per scope, drawn by the CHASSIS (prd §495/§596) —
    /// a count, because the summary sentence it replaces was prose standing on
    /// a chart. Frames' own division: the transaction count belongs to
    /// Activity, the STEP count to Frames, so no two scopes read as one
    /// reading twice.
    private var slotHeadline: String? {
        switch section {
        // **HOME TAKES A HEADLINE WHEN A FIGURE DRAWS (prd §606, user: "isn't
        // it weird to have those sentences at the top of the charts?").**
        //
        // §596 removed the summary sentence from every other scope for exactly
        // this reason — prose standing on a drawing — and exempted Home on the
        // grounds that its sentence IS the crown. Seen on a device, that
        // exemption fails in the one state the room is usually in: three lines
        // of `heading22` saying "Proofs here name 2 snapshots the chain still
        // remembers" directly above a ring drawing two numbered sets and their
        // remaining life. The sentence was the drawing, in words, on top of it.
        //
        // **Only where a figure draws.** Five of the eight ledes have no ring
        // at all — relaunched, unwatched, reading, quiet, spends — and there
        // the sentence is the room's entire content and must stay. This is the
        // conditional, not a deletion: a count when the ring is there, nil
        // when the sentence is all there is. `Frames` leads its Home with a
        // figure through the chassis for the same reason.
        case .home:
            guard !marks.isEmpty else { return nil }
            let n = accounts.reduce(0) { $0 + $1.roots.count }
            guard n > 0 else { return nil }
            return n == 1 ? String(localized: "1 snapshot")
                          : String(localized: "\(String(n)) snapshots")
        case .activity:
            let n = pairs.count
            guard n > 0 else { return section.emptyHeadline }
            return n == 1 ? String(localized: "1 transaction")
                          : String(localized: "\(String(n)) transactions")
        case .accounts:
            let n = accounts.count
            guard n > 0 else { return section.emptyHeadline }
            return n == 1 ? String(localized: "1 address")
                          : String(localized: "\(String(n)) addresses")
        case .frames:
            let steps = moves.reduce(0) { $0 + $1.frameCount }
            guard steps > 0 else { return section.emptyHeadline }
            return steps == 1 ? String(localized: "1 step")
                              : String(localized: "\(String(steps)) steps")
        case .nullifiers:
            let n = accounts.reduce(0) { $0 + $1.nullifiers.count }
            guard n > 0 else { return section.emptyHeadline }
            return n == 1 ? String(localized: "1 spend key")
                          : String(localized: "\(String(n)) spend keys")
        case .roots:
            let n = accounts.reduce(0) { $0 + $1.roots.count }
            guard n > 0 else { return section.emptyHeadline }
            return n == 1 ? String(localized: "1 proof")
                          : String(localized: "\(String(n)) proofs")
        case .sponsors:
            let n = moves.filter(\.sponsored).count
            guard n > 0 else { return section.emptyHeadline }
            return String(localized: "\(String(n)) sponsored")
        }
    }

    /// **THE CARD SLOT HOLDS THE CHART, THE LIST GOES BELOW THE RAIL (prd
    /// §593d/§593e, user ruling: "the chart should be ABOVE the rail, and the
    /// list should be BELOW the rail").** `FramesRoomCard`'s structure exactly:
    /// the figure fills the clipped slot, `PrivacyDevnetRoomList` draws the
    /// rows below the switcher.
    ///
    /// **Every drawing ends at the gear's x** — Frames' own rule, applied here
    /// once rather than per chart: the settings gear floats over the slot's
    /// top-right, and a chart that runs under it reads as a chart that was
    /// clipped by chrome.
    @ViewBuilder private var content: some View {
        Group {
            switch section {
            case .home:
                home
            // **THE EMPTY STATE IS IN THE SLOT, NOT UNDER THE RAIL (prd
            // §610).** It used to be drawn by `scopeList`, so a scoped room
            // with nothing in it was 300 blank points of card with the one
            // sentence that explained them pushed below the switcher — and on
            // a phone, below the fold. Reported from a device as "nothing from
            // this address on the chain is below the fold".
            case _ where isEmpty(section):
                emptyState
            default:
                figure(for: section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
            }
        }
        .padding(.trailing, DSRoomChassis.gearColumn)
    }

    /// Every shown move with the address whose read produced it — Hegotá's
    /// signature, and for its reason: in an unscoped room nothing else can say
    /// which of the shown addresses a transaction belonged to, and a sheet
    /// that cannot answer "whose?" is a sheet about a stranger's money. The
    /// flat `moves` list is derived FROM this rather than beside it, so the
    /// two orderings can never differ.
    var pairs: [(move: PrivacyDevnetLiveState.Move, owner: String)] {
        accounts
            .flatMap { account in account.moves.map { (move: $0, owner: account.address) } }
            .sorted { ($0.move.block ?? 0) > ($1.move.block ?? 0) }
    }

    var moves: [PrivacyDevnetLiveState.Move] { pairs.map(\.move) }

    @ViewBuilder private var home: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // The sentence stands only where there is no figure under it
            // (prd §606) — see `slotHeadline`. Where the ring draws, it was
            // the drawing restated in three lines of heading type above it.
            if marks.isEmpty {
                Text(PrivacyDevnetRoom.sentence(head))
                    .dsText(.heading22)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // **THE RING, AND ITS CAPTION IS GONE WITH THE BAR (prd §598).**
            // The straight track needed eight words at its ends to say which
            // way time ran, and the same eight words were printed again under
            // every lane in the Snapshots scope. An arc needs none: the gap at
            // the bottom is the exit, so a snapshot that leaves the window
            // falls into it.
            // **THE RING OWNS THE REST OF THE SLOT (prd §602).** Seen on a
            // device for the first time, it sat against the leading edge with
            // the whole right half of the card empty and ~200pt of dead air
            // between it and the rail — the "tiny and top justified" defect
            // §588 fixed for Frames and §596 for this room's other figures,
            // arriving a third time in a new shape because a `VStack` hugs its
            // top and a trailing `Spacer` pins its content left.
            //
            // Centred, and given the leftover height so the air is distributed
            // rather than dumped underneath.
            if !marks.isEmpty {
                PrivacyDevnetRing(marks: marks, sets: setCount,
                                  remaining: freshestRemaining,
                                  readAt: readAt, diameter: Self.homeRingDiameter,
                                  reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // **THE TALLIES ARE GONE (prd §596).** Home carried a row of
            // spend-key / frame / sponsored counts, and every one is now
            // another scope's HEADLINE one chip away — Frames' own §588
            // argument for stripping its Home scope: a fact another scope
            // leads with, repeated here in smaller type, makes two scopes
            // look like one reading twice.

            // **THE MOVES ARE BELOW THE RAIL NOW (prd §602)**, with every
            // other scope's rows. They were drawn in here, budgeted against a
            // 300pt box that CLIPS — and after two estimates each cut a row
            // mid-line on a device, the ruling became "with a figure, draw
            // none", which is every time a proof is live. So this scope's own
            // summary promised "the last few moves" and showed none for as
            // long as the room has had anything to say.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// How big Home's ring is.
    ///
    /// **Bigger than the Snapshots scope's, not smaller**, because Home's
    /// sentence takes the top of the slot and whatever is left is the ring's
    /// alone — measured on a device at 128, where it read as a small object in
    /// a large empty card.
    /// **Derived from the slot, never a constant** (`PrivacyDevnetFigure
    /// .rowCap`'s reason). Home reserves a headline row now, so what is left
    /// is `figureSlot` and the ring should own it — measured on a device at
    /// 156, where it still sat in noticeable air.
    static var homeRingDiameter: CGFloat {
        min(max(DSRoomChassis.figureSlot - 56, 120), 200)
    }

    /// Every snapshot this address has proved against, placed on the ring.
    ///
    /// **Not just the freshest, which is what the meter could draw.**
    /// `head.windowFraction` carries ONE root by construction, so the bar it
    /// fed showed the reference with the most window left and a room with three
    /// proofs said nothing about the other two — including any that had already
    /// aged out, which had no picture at all, only a sentence.
    private var marks: [PrivacyDevnetFigure.Mark] {
        PrivacyDevnetFigure.marks(accounts.flatMap(\.roots), headSlot: headSlot)
    }

    /// How many distinct sets are on the ring. One wears no ordinals — a
    /// number implies a second (`PrivacyDevnetRoots.setLabel`'s rule).
    var setCount: Int {
        PrivacyDevnetRoots.bySource(accounts.flatMap(\.roots)).count
    }

    /// The freshest live reference's remaining slots — the ring's own reading,
    /// and the same reference `PrivacyDevnetRoom.head` ranked, so the sentence
    /// above and the number inside the ring can never describe two different
    /// snapshots.
    var freshestRemaining: UInt64? {
        accounts.flatMap(\.roots)
            .compactMap { PrivacyDevnetRoots.remaining($0, headSlot: headSlot) }
            .max()
    }

    /// When the chain was last really read. The ring drifts from here and
    /// freezes at `PrivacyDevnetFigure.driftCap`; nil in a preview and in the
    /// demo, where a moving estimate over a fixture would be motion with
    /// nothing behind it.
    var readAt: Date? { DemoMode.isActive ? nil : PrivacyDevnetLiveState.shared.readAt }

    /// The few moves Home lists below the rail. Nothing clips there, so this
    /// is a stated cap rather than a budget against a box (prd §602).
    var homeMoveCount: Int {
        min(pairs.count, PrivacyDevnetFigure.homeMoveCap)
    }
}

// MARK: - The scopes

extension PrivacyDevnetRoomCard {

    /// Whether the scope on screen has anything to draw.
    ///
    /// **The gate `present()` used to be (prd §610).** Every chip is reachable
    /// now, so this decides what the slot shows rather than which chips exist
    /// — and it is spelled from the same evidence the old gate read, so a scope
    /// that would have been hidden is exactly a scope that now says why.
    ///
    /// Home is never empty: its sentence is its content, which is the rule the
    /// whole file is built on.
    func isEmpty(_ section: PrivacyDevnetSection) -> Bool {
        switch section {
        case .home:       return false
        case .activity:   return pairs.isEmpty
        case .accounts:   return accounts.isEmpty
        case .frames:     return moves.allSatisfy { $0.frameCount == 0 }
        case .nullifiers: return keyRows.isEmpty
        case .roots:      return accounts.allSatisfy { $0.roots.isEmpty }
        case .sponsors:   return !moves.contains(where: \.sponsored)
        }
    }

    /// **A SCOPE WITH NOTHING IN IT TEACHES WHAT IT WOULD HOLD (prd §610).**
    ///
    /// Two tiers and no more: the chassis' reserved row carries the short
    /// state (`emptyHeadline`) and this carries one paragraph saying what the
    /// scope is about and why this room has none. A lead line between them
    /// would be a third register of text in a box with no drawing in it.
    ///
    /// **No door.** Top up and Send are Home's, by ruling — a scope's empty
    /// state states a fact and stops.
    ///
    /// Centred rather than pinned to the top: a paragraph hugging the top of a
    /// 258pt box is the dead-air shape §602 and §596 each fixed once already.
    @ViewBuilder var emptyState: some View {
        if let words = section.emptyBody {
            Text(words)
                .dsText(.body17)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// The seat's own hue for a leading symbol mark — the console is chrome
    /// around the brand, never a new colour.
    private static let tint = DS.brandHue(for: PrivacyDevnetIdentity.source) ?? DS.tint

    /// The scope's own rows, drawn by `PrivacyDevnetRoomList` OUTSIDE the
    /// clipped slot (prd §593d). Internal rather than private for exactly that
    /// reason — the two are one room split across two feed sections, so the
    /// rows and the figure above them are computed from the same inputs and
    /// cannot disagree about which scope is showing.
    @ViewBuilder var scopeList: some View {
        switch section {
        // **HOME'S OWN FEW MOVES, at last (prd §602).** They used to be drawn
        // inside the clipped slot and then, after two clipping reports, not at
        // all — so the scope's summary promised them and the scope had none.
        // Here they cannot clip, and they cannot double up either: the slot
        // above draws the sentence and the ring, and nothing else.
        case .home:       list(Array(pairs.prefix(homeMoveCount)), showsCeiling: false)
        case .activity:   list(pairs)
        case .accounts:   roster
        case .frames:     list(pairs.filter { $0.move.frameCount > 0 })
        case .nullifiers: nullifierScope
        case .roots:      rootScope
        // **THE SPONSORSHIP CLAUSE IS DROPPED IN ITS OWN SCOPE** — Frames'
        // ruling: every row here is sponsored by definition, so the word
        // separates nothing and costs the line its remaining width.
        case .sponsors:   list(pairs.filter(\.move.sponsored), showsSponsorship: false)
        }
    }

    @ViewBuilder func list(_ shown: [(move: PrivacyDevnetLiveState.Move, owner: String)],
                           showsSponsorship: Bool = true,
                           showsCeiling: Bool = true) -> some View {
        // **NOTHING HERE WHEN THERE IS NOTHING (prd §610)** — the slot above
        // the rail carries the empty state now, and a second copy under the
        // switcher is one sentence in two places at two sizes.
        if shown.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(shown, id: \.move.id) { pair in
                    moveRow(pair.move, owner: pair.owner,
                            showsSponsorship: showsSponsorship)
                }
                if showsCeiling { walkCeiling }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **WHAT THIS LIST DOES NOT CONTAIN (prd §593d).**
    ///
    /// Three sentences, and only ever the ones that are true. A truncated room
    /// and a complete one look IDENTICAL from outside, which is this repo's
    /// oldest recurring defect (§307, §309) and one the figures were already
    /// guarding against while the walk feeding them cut silently.
    ///
    /// The standing ceiling is said EVERY time and the two cuts only when they
    /// bit, because they are different kinds of fact: the first is how this
    /// room works and stays true forever, the other two are what happened on
    /// this pass. Neither cut is ever attributed to an address — the cap drops
    /// the oldest candidates chain-wide, and which of them were whose is
    /// exactly what reading them would have told us.
    /// **SPLIT BY WHAT KIND OF FACT IT IS (prd §602).** All three sentences
    /// printed under every list that drew rows — Activity, Frames and Sponsors
    /// — so the room's own explanation of itself appeared three times on one
    /// screen in the quietest ink it has, which is the §315 fine-print failure
    /// in a room head's clothing.
    ///
    /// They were never the same kind of fact, which is what decides where each
    /// goes. The standing ceiling is HOW THIS ROOM WORKS and is true forever,
    /// so it is said once, on Home, where the room introduces itself. The two
    /// CUTS are what happened on THIS PASS, so they stay with the rows they
    /// truncated — and they are already drawn only when they really bit, which
    /// on every measured pass so far is never.
    @ViewBuilder var walkCeiling: some View {
        if walkCut.scannedTo != nil || walkCut.unread > 0 {
            VStack(alignment: .leading, spacing: 2) {
                if let stopped = walkCut.scannedTo {
                    Text(String(localized: "This chain is long enough that the search stopped at block \(String(stopped)) — anything before that wasn't looked at."))
                }
                if walkCut.unread > 0 {
                    Text(walkCut.unread == 1
                         ? String(localized: "One older transaction on this chain wasn't read.")
                         : String(localized: "\(walkCut.unread) older transactions on this chain weren't read."))
                }
            }
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// How this room finds anything at all — said ONCE, on Home.
    ///
    /// It is the walk's real floor and it never stops being true: a
    /// transaction that emitted no log is invisible to this seat, so every
    /// count in every scope is a floor rather than a total.
    @ViewBuilder var walkFloor: some View {
        Text(String(localized: "Found by following the chain's logs, so a transaction that emitted none isn't here."))
            .dsText(.subhead13)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One transaction, on the app's ONE row shape (`WalletRow`, prd
    /// §212/§588), OPENING ITS OWN SHEET (prd §596) — every row here was the
    /// deliberately-terminal form because there was nothing to open, and the
    /// user's report ("none of the lists open thing sheets") is exactly right:
    /// this seat lands no `Thing`, so the sheet had to be built, the way
    /// Frames and Hegotá built theirs.
    ///
    /// **THE TITLE IS A NOUN AND THE CLAUSES MOVED TO THE META LINE** — the
    /// old title joined up to four clauses ("2 frames · 2 spend keys · named a
    /// snapshot · somebody else paid") into `heading17`, which is the jammed
    /// line the pass was reported for. The hash moved to the sheet, which is
    /// where Frames keeps it; the block stays, because it is the only clock
    /// this walk has.
    @ViewBuilder func moveRow(_ move: PrivacyDevnetLiveState.Move, owner: String,
                              showsSponsorship: Bool = true) -> some View {
        if let onOpenMove {
            Button {
                DSHaptic.selection()
                onOpenMove(move, owner)
            } label: {
                WalletRow(mark: Self.mark(for: move),
                          title: Self.moveTitle(move),
                          subtitleText: Self.moveMeta(move, showsSponsorship: showsSponsorship)) {
                    WalletRowChevron()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            // A preview has no sheet to open, so no chevron and no button —
            // a chevron over a dead tap is §83's fake promise.
            WalletRow(mark: Self.mark(for: move),
                      title: Self.moveTitle(move),
                      subtitleText: Self.moveMeta(move, showsSponsorship: showsSponsorship)) {
                EmptyView()
            }
        }
    }

    /// The mark says what the transaction WAS: a pool spend wears the key, a
    /// framed transaction the stack, a plain transfer the arrows.
    static func mark(for move: PrivacyDevnetLiveState.Move) -> WalletRowMark {
        if move.nullifierCount > 0 { return .symbol("key.fill", tint: tint) }
        return move.frameCount == 0
            ? .symbol("arrow.left.arrow.right", tint: DS.textSecondary)
            : .symbol("square.stack.3d.up.fill", tint: tint)
    }

    /// **AN ORDINARY TRANSACTION IS NOT "0 FRAMES"** — Frames' own rule; this
    /// chain's faucet pays out as a plain transfer that emits an EIP-7708 log,
    /// so the walk can carry both.
    static func moveTitle(_ m: PrivacyDevnetLiveState.Move) -> String {
        guard m.frameCount > 0 else { return String(localized: "Transfer") }
        return m.frameCount == 1 ? String(localized: "1 frame")
                                 : String(localized: "\(String(m.frameCount)) frames")
    }

    /// The metadata clauses, as ONE concatenated `Text` (`WalletRow
    /// .subtitleText`'s reason: SwiftUI squeezes an over-committed HStack by
    /// wrapping one clause into a one-word column; a run wraps as a sentence
    /// and is capped at a line).
    static func moveMeta(_ m: PrivacyDevnetLiveState.Move,
                         showsSponsorship: Bool = true) -> Text? {
        var out: Text?
        func add(_ piece: Text) {
            out = out.map { $0 + Text(verbatim: " · ") + piece } ?? piece
        }
        if m.nullifierCount > 0 {
            add(Text(m.nullifierCount == 1
                     ? String(localized: "1 spend key")
                     : String(localized: "\(String(m.nullifierCount)) spend keys")))
        }
        if m.rootCount > 0 { add(Text(String(localized: "named a snapshot"))) }
        if m.sponsored, showsSponsorship {
            add(Text(String(localized: "Sponsored")))
        }
        if let block = m.block {
            add(Text(String(localized: "block \(String(block))")))
        }
        return out
    }

    /// What one transaction did, in the room's own vocabulary — the SHEET's
    /// lead sentence now rather than a row title (prd §596).
    static func moveLine(_ m: PrivacyDevnetLiveState.Move) -> String {
        var parts: [String] = []
        parts.append(m.frameCount == 1 ? String(localized: "1 frame")
                                       : String(localized: "\(m.frameCount) frames"))
        if m.nullifierCount > 0 {
            parts.append(m.nullifierCount == 1 ? String(localized: "1 spend key")
                                               : String(localized: "\(m.nullifierCount) spend keys"))
        }
        if m.rootCount > 0 { parts.append(String(localized: "named a snapshot")) }
        if m.sponsored { parts.append(String(localized: "somebody else paid")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder var roster: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(accounts) { account in
                // A wallet is a FACE in this app (`WalletRowMark.face`): the
                // watched address leads with its own, title its name, subtitle
                // its balance — the per-address row every wallet room draws.
                // **Nil is not zero** (§515a): a failed read says so.
                // One naming for the whole seat (`PrivacyDevnetName.of`), so
                // this phone's own account reads as "This phone" here, on the
                // rail and in every sheet rather than as a stranger's hex in
                // the room that created it (prd §602).
                let title = PrivacyDevnetName.of(account.address)
                let line = account.reached
                    ? (Self.eth(account.balanceWei) ?? String(localized: "Balance unread"))
                    : String(localized: "The chain didn't answer")
                if let onOpenAccount {
                    Button {
                        DSHaptic.selection()
                        onOpenAccount(account)
                    } label: {
                        WalletRow(mark: .face(account.address),
                                  title: title, subtitle: line)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    WalletRow(terminal: .face(account.address),
                              title: title, subtitle: line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func eth(_ wei: Decimal?) -> String? {
        guard let wei else { return nil }
        return PrivacyDevnetMoney.line(wei: wei)
    }

    /// **EVERY KEY OPENS THE TRANSACTION THAT SPENT IT (prd §596).** The
    /// explainer paragraph that led this list moved into the move sheet, where
    /// it sits beside the keys it explains instead of over a column of rows.
    @ViewBuilder var nullifierScope: some View {
        let rows = keyRows
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let title = String(localized: "Spent once")
                    if let onOpenMove {
                        Button {
                            DSHaptic.selection()
                            onOpenMove(row.move, row.owner)
                        } label: {
                            WalletRow(mark: .symbol("key.fill", tint: Self.tint),
                                      title: title, subtitle: Self.shortHex(row.key))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Spend key \(i + 1), used once. Opens its transaction."))
                    } else {
                        WalletRow(terminal: .symbol("key.fill", tint: Self.tint),
                                  title: title, subtitle: Self.shortHex(row.key))
                            .accessibilityLabel(String(localized: "Spend key \(i + 1), used once"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Each spent key with the move that spent it, so a key row can open its
    /// own transaction. Keys the walk saw outside any move (a union the
    /// account carries without the transaction) fall back to no move and draw
    /// terminal.
    var keyRows: [(key: Data, move: PrivacyDevnetLiveState.Move, owner: String)] {
        pairs.flatMap { pair in
            pair.move.nullifiers.map { (key: $0, move: pair.move, owner: pair.owner) }
        }
    }

    /// **THE ROW IS THE SET, AND IT WEARS THE SET'S OWN NUMBER (prd §598).**
    ///
    /// The row led with a clock glyph and a title reading "4,096 slots left in
    /// the chain's memory · 2 proofs" over a subtitle of root bytes — a unit
    /// nobody can size, a count and an identifier, in three registers. It is
    /// the app's own row now: the MARK carries the same ordinal the ring above
    /// draws (`WalletRowMark.monogram`, so figure and list are one identity),
    /// the title names the set, and the reading runs as one concatenated meta
    /// line — the estimate first because it is what a person can act on, the
    /// measured slot count beside it because nothing observed may be replaced
    /// by something assumed.
    @ViewBuilder var rootScope: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            EmptyView()
        } else {
            let groups = PrivacyDevnetRoots.bySource(refs)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(Array(groups.enumerated()), id: \.element.source) { index, group in
                    // The row opens the newest transaction that proved
                    // against this source — the object the group is ABOUT.
                    let pair = pairs.first { p in
                        p.move.roots.contains { $0.sourceID == group.source }
                    }
                    let title = PrivacyDevnetRoots.setLabel(index, of: groups.count)
                    let mark = Self.setMark(index, of: groups.count)
                    if let pair, let onOpenMove {
                        Button {
                            DSHaptic.selection()
                            onOpenMove(pair.move, pair.owner)
                        } label: {
                            // The memberwise form, because the meta line is a
                            // `Text` run rather than a String: `subtitleText`
                            // exists so one clause can carry its own ink, and
                            // the convenience inits take a plain subtitle.
                            WalletRow(mark: mark, title: title,
                                      subtitleText: Self.standingMeta(group.newest,
                                                                      headSlot: headSlot,
                                                                      count: group.count)) {
                                WalletRowChevron()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        WalletRow(mark: mark, title: title,
                                  subtitleText: Self.standingMeta(group.newest,
                                                                  headSlot: headSlot,
                                                                  count: group.count)) {
                            EmptyView()
                        }
                    }
                }
                Text(Self.windowNote)
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A set's mark: its own number where there are several, the standing
    /// clock where there is only one. **A monogram reading "1" beside no other
    /// number is a label for a series that does not exist** — the same reason
    /// `setLabel` says "The set" rather than "Set 1".
    static func setMark(_ index: Int, of total: Int) -> WalletRowMark {
        total > 1 ? .monogram(String(index + 1), tint: tint)
                  : .symbol("clock.fill", tint: tint)
    }

    /// **HOW BIG THE WINDOW IS, ONCE, HEDGED (prd §593d).**
    ///
    /// Every line above counts in SLOTS and that ruling stands where it was
    /// made: the slot count is measured and the seconds are an assumption
    /// about this devnet's slot time, so the measured number is never dropped.
    /// §598 amends only WHERE the conversion may lead — beside the clock, in
    /// the ring's own reading and in a row's meta line — and this sentence is
    /// still what names the assumption out loud, once, at the bottom.
    static var windowNote: String {
        let hours = Int((PrivacyDevnetRoots.duration(slots: PrivacyDevnetRoots.windowSlots) / 3600)
                        .rounded())
        return String(localized: "The chain remembers \(String(PrivacyDevnetRoots.windowSlots)) slots — about \(hours) hours, if this devnet keeps to \(String(PrivacyDevnetRoots.secondsPerSlot)) seconds a slot.")
    }

    /// Where one reference stands, as the row's one meta line.
    ///
    /// **The estimate and the measurement travel together** (§598's rule): the
    /// phrase a person can act on leads, the slot count that was actually
    /// observed sits right beside it, and the word "about" carries the hedge
    /// every time. An aged reference states the slots alone — there is no
    /// clock left to convert, and "about 3 hours ago" would dress a settled
    /// fact as a countdown.
    static func standingMeta(_ r: PrivacyDevnetRoots.Reference,
                             headSlot: UInt64, count: Int) -> Text {
        let proofs = count == 1 ? String(localized: "1 proof")
                                : String(localized: "\(String(count)) proofs")
        let sep = Text(verbatim: " · ")
        switch PrivacyDevnetRoots.standing(of: r, headSlot: headSlot) {
        case .live(let left):
            return Text(String(localized: "\(PrivacyDevnetRoots.approximate(slots: left)) left"))
                + sep + Text(String(localized: "\(String(left)) slots"))
                + sep + Text(proofs)
        case .aged(let by):
            return Text(String(localized: "Left the chain's memory \(String(by)) slots ago"))
                + sep + Text(proofs)
        case .ahead:
            // The head is behind the reference — a lagging node, not freshness.
            return Text(String(localized: "Waiting for the chain to catch up"))
                + sep + Text(proofs)
        }
    }

    /// One spelling, and it lives with the seat's other naming
    /// (`PrivacyDevnetName.shortHex`, prd §598) — this was the second of two
    /// hex shorteners in one seat, eliding at a different length from the
    /// sheet's, so a key and the transaction that spent it were cut
    /// differently on the same screen.
    static func shortHex(_ d: Data) -> String { PrivacyDevnetName.shortHex(d) }
}

// MARK: - The figures

/// A figure for every scope (user, 2026-09-04: *"we need them for each scope"*
/// — and, same day, *"we need better charts too"*).
///
/// **Each says something a list of the same rows cannot**, which is the bar a
/// figure has to clear here — the room draws the list underneath either way, so
/// a chart that merely restates it costs a slot and earns nothing.
///
///   • Activity — WHEN and HOW BIG at once: a column per transaction at its
///     block position, height carrying its frame count, ornamented with the
///     room's own shapes when it spent keys or named a snapshot.
///   • Accounts — WHO (the face) and what each has done, countable.
///   • Frames — how the budget was DIVIDED between the steps.
///   • Nullifiers — one ring per key, spent. The visual IS the claim.
///   • Roots — every snapshot's remaining window at once.
///
/// **EVERY FIGURE FILLS THE SLOT (prd §596).** They were pinned to an 84pt
/// band centred in the 300pt box — the exact "why is it so tiny and top
/// justified" defect §588 fixed on Frames, mirrored — so the room's drawings
/// were the smallest things on the card while the box around them was mostly
/// void. Caps are derived from `DSRoomChassis.figureSlot`, never constants.
///
/// **No colour carries state anywhere below.** Every fill is the one tint, and
/// nothing is red or green — a spent key is not bad and an aged root is not a
/// failure. Scale is the only encoding.
extension PrivacyDevnetRoomCard {

    @ViewBuilder func figure(for section: PrivacyDevnetSection) -> some View {
        switch section {
        case .activity:   activityFigure
        case .frames:     budgetBar(moves.filter { $0.frameCount > 0 })
        // **NO FIGURE (prd §606).** These two drew a count as N identical
        // shapes — eight rings for eight keys, a row of pips per address —
        // over data with nothing to compare. "We can count; what does that
        // do." The chassis headline states the number and the rows below the
        // rail carry the detail, which is strictly more than the shapes said.
        case .accounts:   EmptyView()
        case .nullifiers: EmptyView()
        case .roots:      windows
        case .sponsors:   budgetBar(moves.filter(\.sponsored))
        case .home:       EmptyView()
        }
    }

    /// **WHEN EACH TRANSACTION LANDED, and what they were only when that
    /// differs (prd §610).**
    ///
    /// The scope drew `kindMix` alone, which on the reported device was one
    /// legend line — *60 plain transfers* — under a chassis headline already
    /// reading *60 transactions*: the slot restated its own headline and left
    /// the rest empty. The mix is not wrong, it is the right figure for a room
    /// whose transactions differ in kind, and here they almost never do.
    ///
    /// So the spine leads and the mix becomes its caption, drawn **only when
    /// there is more than one kind** — which is exactly when it stops being the
    /// headline said twice.
    @ViewBuilder private var activityFigure: some View {
        // ONE definition of what is dated, shared with the drawing: the axis
        // ends and the spine's own bins come from the same function, so the
        // labels can never name a range the marks are not inside.
        let marks = pairs.map { (block: $0.move.block, sponsored: $0.move.sponsored,
                                 id: $0.move.id) }
        let axis = PrivacyDevnetFigure.spine(marks, columns: 1)
        let mix = PrivacyDevnetFigure.kindMix(moves.map {
            PrivacyDevnetFigure.kind(frames: $0.frameCount, keys: $0.nullifierCount)
        })
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            PrivacyDevnetMoveSpine(marks: marks,
                                   open: onOpenMove == nil ? nil : { id in
                                       guard let pair = pairs.first(where: { $0.move.id == id })
                                       else { return }
                                       onOpenMove?(pair.move, pair.owner)
                                   },
                                   reduceMotion: reduceMotion)
            if let axis {
                HStack {
                    Text(String(localized: "block \(String(axis.fromBlock))"))
                    Spacer(minLength: DS.Space.s2)
                    Text(String(axis.toBlock))
                }
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                // Every mark in one block is a real reading and a range of one
                // is not: an axis printing the same number at both ends reads
                // as a broken chart rather than as a busy minute.
                .opacity(axis.fromBlock == axis.toBlock ? 0 : 1)
            }
            if mix.count > 1 {
                Text(mix.map { PrivacyDevnetKindMix.words($0.kind, count: $0.count) }
                        .joined(separator: " · "))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            // **COUNTED, NEVER PLACED.** A transaction whose read carried no
            // block has no position on this axis; saying so is the difference
            // between a figure that is incomplete and one that is wrong.
            if let axis, axis.undated > 0 {
                Text(axis.undated == 1
                     ? String(localized: "1 more, with no block on it.")
                     : String(localized: "\(String(axis.undated)) more, with no block on them."))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// WHAT THESE STEPS WERE ALLOWED, and what they cost — one bar for the
    /// room rather than one strip per transaction (prd §606).
    @ViewBuilder private func budgetBar(_ moves: [PrivacyDevnetLiveState.Move]) -> some View {
        let frames = moves.flatMap(\.frames).map {
            PrivacyDevnetFigure.Frame(gasLimit: $0.gasLimit, stateLimit: $0.stateLimit,
                                      succeeded: $0.succeeded)
        }
        let b = PrivacyDevnetFigure.budgets(frames: frames, gasUsed: moves.map(\.gasUsed))
        if b.hasAnything {
            PrivacyDevnetBudgetBar(budgets: b, reduceMotion: reduceMotion)
        } else {
            EmptyView()
        }
    }

    /// Every referenced snapshot on the ring, one lane per source.
    ///
    /// On the ring an aged root is a HOLLOW mark just outside the leading
    /// edge: out of the window, which is exactly where it is, and visibly a
    /// thing rather than an absence.
    ///
    /// **No colour separates the lanes.** They are the same reading over
    /// different sources, and a hue per source would say the sources differ in
    /// kind, which they do not — the label says which is which.
    /// **ONE RING, EVERY SNAPSHOT ON IT (prd §598).**
    ///
    /// This was a STACK of lanes, one per source, each a straight track with
    /// an 84pt column of `0x1f4a…3c91` beside it and the same eight-word axis
    /// caption underneath — bytes that name nothing, a scale repeated per row,
    /// and a drawing that got shorter as the reading got richer.
    ///
    /// The ring carries every reference at its own age, each wearing its set's
    /// ORDINAL, which is the same number the rows below and the sheet behind
    /// them wear. **No colour separates the sets**, unchanged: they are the
    /// same reading over different sources, and a hue per source would say the
    /// sources differ in kind, which they do not.
    @ViewBuilder private var windows: some View {
        let refs = accounts.flatMap(\.roots)
        if refs.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: DS.Space.s4) {
                Spacer(minLength: 0)
                PrivacyDevnetRing(marks: marks, sets: setCount,
                                  remaining: freshestRemaining,
                                  readAt: readAt,
                                  diameter: Self.ringDiameter,
                                  reduceMotion: reduceMotion)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// How big the ring may be. **Derived from the figure's own box, never a
    /// constant** (`PrivacyDevnetFigure.rowCap`'s reason): the slot was 166
    /// before §588 and is 256 today, and a hand-tuned diameter is one release
    /// from being clipped or lost in air.
    static var ringDiameter: CGFloat {
        min(max(DSRoomChassis.figureSlot - 24, 96), 240)
    }
}

// MARK: - The quiet state's door (prd §593d)

/// Two rows offering the addresses that have something to show.
///
/// **Not a re-pitch and not a list of every address on the chain** — the two
/// measured examples, each named for the READING it makes possible, which is
/// the same claim the connect screen's own rows make and in the same words. The
/// pool participant leads because it is the only one of the two whose
/// transactions reference a root, so it is the only way to see the Roots scope
/// at all without waiting for somebody else to use the chain.
///
/// A DOOR, never a claim: tapping watches the address, which is a read.
struct PrivacyDevnetExampleDoors: View {
    let onWatch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(String(localized: "Or watch one that has something to show"))
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
            ForEach(PrivacyDevnetExample.all) { example in
                Button { onWatch(example.address) } label: {
                    HStack(spacing: DS.Space.s3) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(example.title)
                                .dsText(.body17)
                                .foregroundStyle(DS.textPrimary)
                            Text(example.detail)
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                        Spacer(minLength: DS.Space.s3)
                        Image(systemName: "plus.circle")
                            .foregroundStyle(DS.textTertiary)
                    }
                    .frame(minHeight: DS.Hit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - The rows, outside the box (prd §593d)

/// Every scope's LIST, as its own feed section.
///
/// **This exists because `DSRoomSlot` clips at 300pt.** The card above draws
/// the figure into that box; these rows scroll with the feed, which is the
/// split `FramesRoomList` has had since the Frames room shipped and this room
/// did not take. Reported as "lists weren't showing in the privacy room", and
/// they were not — they were drawn, and cut off the bottom of a fixed box.
///
/// The acts live here too rather than in the card, for the same reason and more
/// sharply: the send panel is two 146pt tiles and a gap, so inside the slot it
/// would have been clipped out of existence.
struct PrivacyDevnetRoomList: View {
    let head: PrivacyDevnetRoom.Head
    var section: PrivacyDevnetSection = .home
    var accounts: [PrivacyDevnetAccount] = []
    var headSlot: UInt64 = 0
    var walkCut = PrivacyDevnetLiveState.WalkCut()
    /// Raise the send form. Nil for a preview and for the demo's own card.
    var onSend: (() -> Void)?
    /// Watch one of the measured example addresses from the quiet state.
    var onWatchExample: ((String) -> Void)?
    /// Open one transaction's sheet (prd §596).
    var onOpenMove: ((PrivacyDevnetLiveState.Move, String) -> Void)?
    /// Open one watched address's sheet (prd §596).
    var onOpenAccount: ((PrivacyDevnetAccount) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ShellChrome.self) private var chrome

    private var card: PrivacyDevnetRoomCard {
        PrivacyDevnetRoomCard(head: head, section: section, accounts: accounts,
                              headSlot: headSlot, walkCut: walkCut,
                              onOpenMove: onOpenMove, onOpenAccount: onOpenAccount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            card.scopeList

            // **THE ACTS ARE LAST.** The reading is what the room is for and
            // the panel is what you came to do — §594 put vibenet's acts on
            // Home without moving its readings off it, and the same order
            // holds: the sentence and the ring above, the two tiles under.
            //
            // On HOME only. A send panel repeated under every scope is the same
            // control four times, and §594's own line is that an act belongs
            // where you land rather than everywhere you look.
            if section == .home, let onSend {
                // **SIZED BY THE PANEL, NOT BY THIS SECTION** — the shape
                // `FramesRoomList` already has.
                PrivacyDevnetSendCard(onSend: onSend)
            }

            // **THE QUIET STATE HAD NO DOOR.** Somebody who pasted their own
            // address landed on "Nothing on this chain from the address you
            // watch, yet." with no next step anywhere on screen — and the two
            // addresses that DO have something to show lived only on the
            // connect screen, which you reach this room by leaving. Offered
            // only where it is really the answer: not while a relaunch is being
            // announced (which outranks everything), and not once there is
            // something to read.
            if section == .home, let onWatchExample, showsExamples {
                PrivacyDevnetExampleDoors(onWatch: onWatchExample)
            }

            // The room's standing ceiling, once (prd §602) — under the acts,
            // where fine print belongs, rather than three times in three
            // scopes above the fold.
            if section == .home, head.watching > 0 { card.walkFloor }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PrivacyDevnetMomentsTask())
        // **THE SWEEP IS TOLD THIS PHONE'S ADDRESS; IT NEVER LOOKS IT UP.**
        // `PrivacyDevnetBridge` is driven on a timer with no tap behind it, and
        // the harness fails the build if that file names `PrivacyDevnetKey` at
        // all — so the view that mounts with the room publishes it, the way
        // the send card and the feed already read it here (prd §598).
        .task { PrivacyDevnetLiveState.shared.setMine(PrivacyDevnetKey.address()) }
    }

    private var showsExamples: Bool {
        switch head.lede {
        case .quiet, .unwatched: return true
        // **`moved` is on the FALSE side (prd §610).** The doors exist for a
        // room with nothing to read; an address with transactions has rows
        // under the rail, and offering somebody else's example address over
        // them is an answer to a question this room is no longer asking.
        case .reading, .relaunched, .rootLive, .rootsAged, .spends, .moved: return false
        }
    }
}


// MARK: - The two moments (prd §598)

/// **THIS ROOM MARKED NOTHING, EVER.**
///
/// Frames says "Your first transaction landed" the first time a send this
/// phone signed turns out to be real; Hegotá and vibenet flash their own
/// writes. This seat had not one `chrome.flash` and not one first-sight
/// animation — in the room whose subject is the rarest thing on any of the
/// four chains. It read as a very careful instrument that never once said
/// "look at this".
///
/// **A SENTENCE, NEVER A SHOWER.** `BerryRain`'s one-gesture-one-shower ruling
/// forbids a second pour over the send sheet's own, and neither of these
/// follows a gesture at all — they follow a sweep. A toast carrying the seat's
/// mark is the register this app already uses for "your first X", and
/// `chrome.flash(tone:)` is what fires the single haptic, so nothing here
/// buzzes on its own.
///
/// **The two are worded apart on purpose.** The settle is YOURS and is
/// congratulated; the pool sighting is a stranger's transaction that your
/// watching revealed, so it states what appeared and claims no authorship —
/// this phone cannot spend a one-time key on this chain and never will,
/// because the pool's ABI is not something this project has (§593).
///
/// A modifier rather than two `.task`s inline, so the room's body stays the
/// room and this stays testable as one object.
private struct PrivacyDevnetMomentsTask: ViewModifier {
    @Environment(ShellChrome.self) private var chrome

    func body(content: Content) -> some View {
        content
            .task(id: PrivacyDevnetLiveState.shared.firstSettleReady) {
                guard PrivacyDevnetLiveState.shared.firstSettleReady else { return }
                PrivacyDevnetLiveState.shared.spendFirstSettle()
                chrome.flash(String(localized: "Your first transaction landed"),
                             tone: .success,
                             mark: PrivacyDevnetIdentity.source,
                             seconds: 3)
            }
            .task(id: PrivacyDevnetLiveState.shared.poolSightReady) {
                guard PrivacyDevnetLiveState.shared.poolSightReady else { return }
                PrivacyDevnetLiveState.shared.spendPoolSight()
                // What it IS, not well done: somebody else spent the key.
                chrome.flash(String(localized: "An address you watch used the pool — its spend keys are below"),
                             mark: PrivacyDevnetIdentity.source,
                             seconds: 4)
            }
    }
}
