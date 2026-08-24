import SwiftUI

/// THE VIBENET ROOM'S HEAD — the anatomy `StripeRoomCard`/
/// `AppStoreConnectRoomCard` established: a heavy headline stating the whole
/// finding as a sentence, a quiet provenance line under it, ranked rows, no
/// coloured rail and no green/red — this room can raise exactly one alarm
/// (a locked account) and it says so in words, the same way a Stripe dispute
/// does.
///
/// There is no external destination to route to (a devnet test account has
/// no thing sheet, no permalink, nothing else in the app that knows about
/// it) — so unlike its Work-group neighbours this card is its OWN detail
/// screen: a row expands in place to show its actor roster rather than
/// pushing anywhere.
///
/// Stores no `Thing` — only value types out of `VibenetRoom`. Corollary 5
/// has nothing to guard here.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount.
struct VibenetRoomCard: View {
    let room: VibenetRoom
    var onRemove: (String) -> Void
    /// Raised by the context menu's "Name this account…" — the alert itself
    /// lives on the SCREEN (a text-entry alert needs `@State` a card
    /// re-composed from a value type shouldn't own), so this just reports
    /// which address was asked for.
    var onRename: (String) -> Void = { _ in }

    /// Which addresses are expanded to show their actor roster. Local to the
    /// card, not persisted — this is a read, not a setting.
    @State private var expanded: Set<String> = []

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over — the `StripeRoom`/
    /// `ASCRoom` cap shape, so a long watch list doesn't turn this into an
    /// unbounded list on a card meant to be a summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    /// Watched faces only — a discovery stranger never earns a slot in the
    /// card's own hero, only in the setup screen's own list. Carries
    /// `alarmed` (R2.4) so the stack itself can flag who's in trouble —
    /// a direct read of `item.alarmed`, no new pure logic to harness.
    private var heroFaces: [(address: String, alarmed: Bool)] {
        room.items.prefix(5).map { ($0.address, $0.alarmed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if heroFaces.count > 1 {
                // A stack, not a row: one glance says "several accounts",
                // which the headline sentence beneath it then makes exact.
                // Overlap follows the house face-stack idiom (StartFigureMark
                // / AddressFlight) — identity is on the FACE, so overlap
                // costs nothing legible.
                HStack(spacing: -10) {
                    ForEach(heroFaces, id: \.address) { face in
                        WalletFace(address: face.address, size: 28, circular: true)
                            .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                // One badge for both locked and unlocking —
                                // the alarm is the alarm; the row's own pill
                                // already carries which of the two words.
                                if face.alarmed {
                                    Circle()
                                        .fill(Self.mark)
                                        .frame(width: 12, height: 12)
                                        .overlay {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(Color.fixed("#ffffff"))
                                        }
                                        .overlay(Circle().strokeBorder(DS.surfaceSheet, lineWidth: 2))
                                }
                            }
                    }
                }
                .padding(.bottom, DS.Space.s2)
            }

            Text(VibenetRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(VibenetRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            // NO PROPORTION BARS HERE, deliberately (2026-08-23, after
            // drawing them and looking): a watch list is a handful of
            // accounts, and a segmented bar over N=4 asks someone to decode
            // an area they could have counted faster by reading the four
            // rows underneath. The aggregate key-kind strip was worse — with
            // one key of each type it rendered five equal segments, a bar of
            // all-1s, which cannot say anything by construction. The
            // headline already carries the status proportion as a sentence.
            // The matrix below is this room's one chart, and it earns the
            // slot because comparing several keys' powers is genuinely hard
            // to do by reading.
            if !room.items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(drawn) { item in
                        row(item)
                    }
                }
                .padding(.top, DS.Space.s3)
            }

            if room.items.count > drawn.count {
                Text(String(localized: "\(room.items.count - drawn.count) more watched"))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, DS.Space.s1)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
    }

    // MARK: - Rows

    /// One watched account. The whole row is the tap target for expanding
    /// its actor roster — a row is a read with ONE gesture; unwatching lives
    /// on the trailing menu, never a second tap target inside the row.
    private func row(_ item: VibenetAccountItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                DSHaptic.selection()
                if expanded.contains(item.address) { expanded.remove(item.address) }
                else { expanded.insert(item.address) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    WalletFace(address: item.address, size: 28, circular: true)
                    VStack(alignment: .leading, spacing: 3) {
                        // A nickname takes the title slot (not monospaced —
                        // it's a name, not hex) and the short address drops
                        // to a small line beneath. Unnamed rows are
                        // unchanged: the address alone, exactly as before.
                        if let name = VibenetWatch.shared.name(for: item.address) {
                            Text(name)
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            Text(VibenetRoom.shortAddress(item.address))
                                .dsText(.label11).monospaced()
                                .foregroundStyle(DS.textTertiary)
                                .lineLimit(1)
                        } else {
                            Text(VibenetRoom.shortAddress(item.address))
                                .dsText(.heading17)
                                .foregroundStyle(DS.textPrimary)
                                .monospaced()
                                .lineLimit(1)
                        }
                        // Hidden once expanded WITH actors to show — the
                        // chips below say the same roster in more detail,
                        // and showing both repeats every kind name twice on
                        // one screen. A row with nothing to expand (no
                        // actors) always keeps its line — there is no chip
                        // view underneath it to hand the sentence off to.
                        if !(expanded.contains(item.address) && !item.actors.isEmpty) {
                            // An account mid-unlock leads with its OWN
                            // countdown rather than its key count — "1 key"
                            // sits right beside a badge already saying
                            // "Unlocking"; the number worth a glance here is
                            // WHEN, which was read at launch and thrown away
                            // until now.
                            if item.hasInitiatedUnlock, let countdown = item.unlockLabel(now: .now) {
                                Text(countdown)
                                    .dsText(.label12)
                                    .foregroundStyle(DS.textPrimary)
                                    .lineLimit(1)
                                // Only when BOTH endpoints are known — a bar
                                // with a guessed start is the fake status
                                // §83 forbids, so this is silent rather than
                                // wrong on a build where the delay never
                                // read. No animation on the fill: a static
                                // capsule needs no Reduce Motion check.
                                if let progress = item.unlockProgress(now: .now) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Self.mark.opacity(0.15))
                                            Capsule().fill(Self.mark)
                                                .frame(width: geo.size.width * progress)
                                        }
                                    }
                                    .frame(height: 4)
                                    .frame(maxWidth: 160)
                                }
                            } else if let urgent = item.urgentLine(now: .now) {
                                // R2.2: a key's own clock outranks the plain
                                // key count on the row that's about to be
                                // affected by it — the time-critical fact
                                // must be the visible one, not the one you
                                // find by expanding. The room's one color
                                // carries urgency here (never bold-white-
                                // on-blue — that grammar stays the lock
                                // pill's alone).
                                Text(urgent)
                                    .dsText(.label12).fontWeight(.semibold)
                                    .foregroundStyle(Self.mark)
                                    .lineLimit(1)
                            } else {
                                Text(VibenetRoom.rowLine(item))
                                    .dsText(.label12)
                                    .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: DS.Space.s2)
                    HStack(spacing: DS.Space.s2) {
                        // The pill states the ALARM; the chevron states
                        // whether there's a roster to open. A locked account
                        // still carries actors worth seeing, and the whole
                        // row is still one Button — without the chevron here
                        // too, that row was tappable with nothing telling you
                        // so, and its roster only ever opened by accident.
                        if item.alarmed {
                            Text(item.hasInitiatedUnlock ? String(localized: "Unlocking") : String(localized: "Locked"))
                                .dsText(.label11).fontWeight(.bold)
                                .foregroundStyle(Color.fixed("#ffffff"))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        // Every row expands now, actors or not — the
                        // explorer door and the sync line in `footer` are
                        // worth reaching from a "Not established yet" row
                        // too, which is exactly the row someone opens to
                        // check whether they watched the address they meant
                        // to.
                        Image(systemName: expanded.contains(item.address) ? "chevron.up" : "chevron.down")
                            .dsGlyph(12)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, DS.Space.s2)
            .contextMenu {
                Button {
                    onRename(item.address)
                } label: {
                    Label(String(localized: "Name this account…"), systemImage: "pencil")
                }
                Button {
                    DSHaptic.tap()
                    UIPasteboard.general.string = item.address
                } label: {
                    Label(String(localized: "Copy address"), systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    onRemove(item.address)
                } label: {
                    Label(String(localized: "Stop watching"), systemImage: "trash")
                }
            }

            if expanded.contains(item.address) {
                VStack(alignment: .leading, spacing: 0) {
                    // ADAPTIVE BY SHAPE, not one form for everything. A
                    // matrix exists to COMPARE, and with a single key there
                    // is nothing to compare against — it drew one column of
                    // six blocks, five of them gray, to say what a
                    // three-word sentence says plainly. Most accounts have
                    // one key, so the grid was optimised for the rare case
                    // and wasteful in the common one. Zero keys draws
                    // neither — the row's own subtitle ("Not established
                    // yet") already said the whole thing.
                    if item.actors.count == 1, let only = item.actors.first {
                        singleKeyLine(only)
                    } else if !item.actors.isEmpty {
                        scopeMatrix(VibenetAccountItem.byReach(item.actors))
                    }
                    keyHistoryStrip(item)
                    footer(item)
                }
                .padding(.bottom, DS.Space.s2)
                .padding(.leading, DS.Space.s1)
            }
        }
    }

    /// The account's key roster as a MATRIX — KEYS as rows, PERMISSIONS as
    /// columns. That way round for a structural reason: the permission set
    /// is FIXED at five (plus a conditional "Other"), so it makes a stable
    /// header somebody learns once, while the number of keys is unbounded
    /// and belongs on the axis that can grow — a table gets longer far more
    /// gracefully than it gets wider. Reading one row answers "what can this
    /// key do", which is the question somebody actually arrives with; the
    /// columns still let you compare keys down a permission.
    ///
    /// EVERY LABEL IS A PLAIN WORD, and getting here took three wrong cuts.
    /// Three-letter column heads ("Snd", "Pol", "Spn") were unreadable. SF
    /// Symbol glyphs for key kinds were worse — a key, a horizontal key, a
    /// face and a link are arbitrary pictures nobody maps back to five
    /// cryptographic schemes. Then the spec's own constant names spelled out
    /// in full ("Sender", "Policy", "Nonce"), which are typographically fine
    /// and still meaningless outside EIP-8130 — "Policy" does not grant a
    /// policy, it restricts sending to one. The columns say what the bits
    /// MEAN. If a future edit needs room, take it from the cells; never from
    /// the words.
    ///
    /// Rows are `byReach`-ordered, so the key that can do the most is read
    /// first rather than whichever scheme the contract happens to declare
    /// earliest.
    private func scopeMatrix(_ actors: [VibenetActor]) -> some View {
        let hasUnknown = actors.contains { $0.scope.unknownCount > 0 }
        let columns = VibenetScope.plainLabels
        // The grid takes its INTRINSIC width and a Spacer eats the rest, so
        // the columns end where the permissions end instead of being
        // justified across the card — the other half of the fixed-cell fix.
        return HStack(spacing: 0) {
            Grid(horizontalSpacing: 4, verticalSpacing: 5) {
                GridRow {
                    Text("")
                    ForEach(columns, id: \.self) { label in
                        // Whole words, two lines allowed, NEVER a break
                        // inside a word — "Pay own / gas" is fine, "secp256
                        // / k1" is what this rule exists to prevent.
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: Self.cellWidth)
                    }
                    if hasUnknown {
                        Text(String(localized: "Other"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: Self.cellWidth)
                    }
                }
                .padding(.bottom, 2)

                ForEach(actors) { actor in
                    GridRow {
                        // The expiry line only shows for a key that actually
                        // HAS one — "Never expires" repeated under every row
                        // of an account where nothing does is the noisy
                        // default this app's own honesty rule argues
                        // against elsewhere; a key that DOES expire is worth
                        // the extra line every time.
                        VStack(alignment: .leading, spacing: 1) {
                            Text(actor.kind.shortLabel)
                                .dsText(.label12)
                                .foregroundStyle(DS.textPrimary)
                                .lineLimit(1)
                            if actor.expiry > 0 {
                                Text(actor.expiryLabel(now: .now))
                                    .font(.system(size: 9))
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .fixedSize()
                        .gridColumnAlignment(.leading)
                        ForEach(Array(actor.scope.grantedFlags.enumerated()), id: \.offset) { _, granted in
                            cell(granted)
                        }
                        // A reserved bit this build can't name gets its own
                        // COLUMN rather than being folded into a named one —
                        // inventing which named permission it belongs under
                        // would be exactly the fake status §83 bans, moved
                        // into a matrix cell instead of a sentence.
                        if hasUnknown {
                            cell(actor.scope.unknownCount > 0)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The one-key case: a plain sentence, which is what this was before a
    /// matrix was ever drawn and what it should always have stayed for a
    /// roster of one. `scope.summary` already words every case honestly,
    /// including "No scope" for a key that can originate nothing yet.
    private func singleKeyLine(_ actor: VibenetActor) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(actor.kind.plainTitle)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            // The technical name plus one honest clause — nil for
            // `.custom`, where there is nothing certain to add.
            if let detail = actor.kind.plainDetail {
                Text(detail)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
            Text(actor.scope.plainSummary)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Same rule as the matrix's rows: silent when there's nothing
            // time-bound to say.
            if actor.expiry > 0 {
                Text(actor.expiryLabel(now: .now))
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// R2.1: the account's own story — every key added or revoked, in
    /// EXACT chronological order. A SEQUENCE strip, deliberately not a
    /// time-proportional axis: several events can share a block, which has
    /// no honest layout on a real clock, so dots are evenly spaced (that
    /// claims ORDER, never elapsed time) and only the two endpoints carry
    /// real dates. ≤1 moment total: a single dot is not a story, so nothing
    /// draws — the summary line alone may still show one moment's own
    /// "1 key added".
    private func keyHistoryStrip(_ item: VibenetAccountItem) -> some View {
        Group {
            if let line = VibenetKeyHistory.summaryLine(item.history) {
                let labels = VibenetKeyHistory.endpointLabels(item.history, now: .now)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    // A single dot is not a story — the summary line alone
                    // stands for one moment; the strip itself needs ≥2.
                    if item.history.count > 1 {
                        HStack(spacing: 8) {
                            if item.history.count > VibenetKeyHistory.cap {
                                // Unreachable today (the read itself is
                                // already bounded to `cap`), kept as the
                                // honest overflow marker if that bound is
                                // ever loosened without this view changing.
                                Text(String(localized: "+\(item.history.count - VibenetKeyHistory.cap) earlier"))
                                    .dsText(.label11)
                                    .foregroundStyle(DS.textTertiary)
                                    .lineLimit(1)
                            }
                            ForEach(item.history) { moment in
                                Circle()
                                    .strokeBorder(Self.mark, lineWidth: moment.authorized ? 0 : 2.5)
                                    .background(Circle().fill(moment.authorized ? Self.mark : .clear))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        HStack {
                            if let oldest = labels.oldest {
                                Text(oldest).dsText(.label11).foregroundStyle(DS.textTertiary)
                                    .lineLimit(1).fixedSize()
                            }
                            Spacer(minLength: DS.Space.s2)
                            if let newest = labels.newest {
                                Text(newest).dsText(.label11).foregroundStyle(DS.textTertiary)
                                    .lineLimit(1).fixedSize()
                            }
                        }
                    }
                }
                .padding(.top, DS.Space.s2)
            }
        }
    }

    /// The account's own sync standing, plus a door out to the real
    /// explorer — both read and both thrown away by every screen before
    /// this one. `changeSequences` is nil only on a failed read, never on a
    /// genuinely-zero standing (`VibenetChangeSequences` carries the zero
    /// itself), so this is silent exactly when there's nothing honest to
    /// report, never when the number is merely small.
    ///
    /// R2.3: the sync standing as number-hero chips, Cash App grammar —
    /// the number is the whole point, the label whispers under it. Replaces
    /// a sentence ("Only one EIP-8130 chain to compare…") that said nothing
    /// about THIS account. `VibenetMultichainSync` stays exactly as shipped
    /// for the day a second live 8130 chain exists — this footer just isn't
    /// its caller anymore.
    private func footer(_ item: VibenetAccountItem) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s2) {
            if let cs = item.changeSequences {
                // Scrolls rather than compresses — two chips plus the
                // Explorer link can genuinely outgrow the card's width at
                // larger Dynamic Type sizes, and the fix is never letting
                // anything WRAP (design law): the Explorer link is the
                // action someone needs to always reach whole, so it's what
                // stays fixed on the trailing edge; the chips are the
                // informational half and scroll instead.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(cs.chips.enumerated()), id: \.offset) { _, chip in
                            HStack(spacing: 3) {
                                Text(chip.value)
                                    .dsText(.label12).fontWeight(.semibold)
                                    .foregroundStyle(DS.textPrimary)
                                Text(chip.label)
                                    .dsText(.label11)
                                    .foregroundStyle(DS.textTertiary)
                            }
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Self.mark.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: DS.Space.s2)
            Link(destination: URL(string: VibenetExplorer.address(item.address))!) {
                HStack(spacing: 3) {
                    Text(String(localized: "Explorer"))
                    Image(systemName: "arrow.up.right")
                }
                .dsText(.label11).fontWeight(.semibold)
                .foregroundStyle(Self.mark)
                .lineLimit(1)
                .fixedSize()
            }
            .layoutPriority(1)
        }
        .padding(.top, DS.Space.s2)
    }

    /// A cell states a YES/NO, so it is a FIXED-SIZE block — never one
    /// stretched to fill the row. Stretching made a one-key account draw five
    /// full-width bars, which reads as a magnitude chart (a bar that long
    /// looks like it is measuring something) for a fact that is just "this
    /// key may do this". Fixed width also means the matrix looks like the
    /// same object whether an account has one key or five: the columns
    /// simply stop, and the row is left-aligned rather than justified.
    ///
    /// 42 is MEASURED against the WORST case now that permissions are the
    /// columns: SIX of them (the five named plus "Other" when a reserved bit
    /// shows up) alongside the longest key name. 58pt for "secp256k1" at
    /// `.label12` + 6×42 + 6×4 of gaps = 334, inside the ~366pt the card
    /// leaves after its own padding. At 52 the sixth column ran off the
    /// edge and dragged the whole card with it.
    private static let cellWidth: CGFloat = 42

    /// A GRANT is drawn; a denial is BLANK. EIP-8130's scopes are near-
    /// exclusive by design (SENDER and POLICY are ungated vs gated
    /// initiation — a key holds one or the other, never both), so a typical
    /// key carries one or two of five bits and the grid is ~75% denials.
    /// Drawing those as gray blocks spent three quarters of the chart's ink
    /// rendering absence, and the marks that matter had to compete with it.
    /// Blank ground, marks on top.
    private func cell(_ granted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(granted ? Self.mark : .clear)
            .frame(width: Self.cellWidth, height: 18)
    }
}
