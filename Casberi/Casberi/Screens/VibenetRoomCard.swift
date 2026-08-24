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

    /// Which addresses are expanded to show their actor roster. Local to the
    /// card, not persisted — this is a read, not a setting.
    @State private var expanded: Set<String> = []

    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")
    /// The most rows drawn before the footnote takes over — the `StripeRoom`/
    /// `ASCRoom` cap shape, so a long watch list doesn't turn this into an
    /// unbounded list on a card meant to be a summary.
    private static let rowCap = 8

    private var drawn: [VibenetAccountItem] { Array(room.items.prefix(Self.rowCap)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(VibenetRoom.shortAddress(item.address))
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .monospaced()
                            .lineLimit(1)
                        // Hidden once expanded WITH actors to show — the
                        // chips below say the same roster in more detail,
                        // and showing both repeats every kind name twice on
                        // one screen. A row with nothing to expand (no
                        // actors) always keeps its line — there is no chip
                        // view underneath it to hand the sentence off to.
                        if !(expanded.contains(item.address) && !item.actors.isEmpty) {
                            Text(VibenetRoom.rowLine(item))
                                .dsText(.label12)
                                .foregroundStyle(item.alarmed ? DS.textPrimary : DS.textSecondary)
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
                        if !item.actors.isEmpty {
                            Image(systemName: expanded.contains(item.address) ? "chevron.up" : "chevron.down")
                                .dsGlyph(12)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, DS.Space.s2)
            .contextMenu {
                Button(role: .destructive) {
                    onRemove(item.address)
                } label: {
                    Label(String(localized: "Stop watching"), systemImage: "trash")
                }
            }

            if expanded.contains(item.address), !item.actors.isEmpty {
                // ADAPTIVE BY SHAPE, not one form for everything. A matrix
                // exists to COMPARE, and with a single key there is nothing
                // to compare against — it drew one column of six blocks,
                // five of them gray, to say what a three-word sentence says
                // plainly. Most accounts have one key, so the grid was
                // optimised for the rare case and wasteful in the common
                // one.
                Group {
                    if item.actors.count == 1, let only = item.actors.first {
                        singleKeyLine(only)
                    } else {
                        scopeMatrix(VibenetAccountItem.byReach(item.actors))
                    }
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
                        Text(actor.kind.shortLabel)
                            .dsText(.label12)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
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
            Text(actor.kind.label)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
            Text(actor.scope.plainSummary)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
