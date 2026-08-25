import SwiftUI

/// THE KEY TRAY — which keys are in which permission category (user,
/// 2026-08-25: *"on the All page the key card should open to a list of keys
/// and permissions that show which keys are in which category"*, prd §468).
///
/// **The chevron this makes honest.** `VibenetRoomCard.keysAggregateSection`
/// (deleted 2026-08-25, prd §469 — its content is `keysCard`/`keysBody`, the
/// only surface left that draws the room's key summary) carried a comment
/// since 2026-08-24 saying it withholds the chevron the design draws because
/// "it points at a key tray that does not exist in this build, and a chevron
/// that opens nothing is the dead control §83 bans. The surface is the part
/// that carries the meaning; the affordance can arrive with the screen it
/// would open." This is that screen, and the chevron arrives with it.
///
/// **Why a card of counts needed one.** "Send anywhere 4" is the one shape of
/// fact you cannot act on: it does not say WHICH four, on which account, or
/// when any of them lapses — and this is the room a person opens to find out
/// who can spend their account. The counts stay on the card, because a card is
/// a summary; the members live here.
///
/// **Grouping mirrors `VibenetPolicyAggregation.compose` exactly** — see
/// `VibenetKeyTray`, which is the one derivation both read, so a card that
/// says 4 can never open a list of 3.
///
/// **A key appears under EVERY permission it holds**, which is the whole
/// question being asked and is why the footnote says so: without that sentence
/// a tray with fourteen rows over eight keys reads as a contradiction of the
/// card above it.
///
/// Value types throughout (`[VibenetAccountItem]`, handed in by
/// `FeedSheetRoute` rather than re-read at present time), so there is no
/// `Thing`, no liveness question, and no renumbering under an open tray.
struct VibenetKeyTraySheet: View {
    let items: [VibenetAccountItem]
    /// Tapping a key SCOPES THE ROOM to the account it belongs to (prd §470).
    ///
    /// The tray answers "which keys can send anywhere" and, before this,
    /// dead-ended on the answer: you found the key, read that it sits on
    /// `…0b1c`, and then had to dismiss the tray, find that face in the rail
    /// and tap it — three gestures to follow up the one you came for.
    ///
    /// The CALLER dismisses and scopes, in that order, because the tray does
    /// not own its own presentation (`FeedSheetRoute` does) and a sheet that
    /// dismissed itself while the room re-composed behind it is the
    /// half-open-then-close class this room has already paid for. nil where
    /// there is nothing to scope, so the rows stay plain rather than
    /// pretending at a door.
    var onPick: ((String) -> Void)? = nil
    /// The permission this tray opens scrolled to, or nil for the top
    /// (prd §471). SCROLLED, never filtered: the tray's whole claim is that
    /// its grouping mirrors the card's census exactly, and a reader can only
    /// check that against a list showing every section. Unknown labels are
    /// harmless — `scrollTo` on an id nothing carries is a no-op.
    var focus: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sections: [VibenetTraySection] { VibenetKeyTray.sections(items) }

    var body: some View {
        DSTray(title: String(localized: "Keys and permissions"),
               height: 660,
               // Draggable past its natural size: the row count is a function
               // of how many accounts somebody watches and how many bits each
               // key holds, which has no ceiling worth guessing at — the
               // `detents` escape hatch this type documents for exactly this.
               detents: [.height(660), .large]) {
            ScrollViewReader { proxy in
                ScrollView {
                    // s6 BETWEEN SECTIONS (prd §471), where it was s4. A
                    // permission and its keys are one object; at s4 the gap
                    // between two sections was barely wider than the gap
                    // inside one, so eight rows over three permissions read
                    // as one undifferentiated run.
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        if sections.isEmpty {
                            // Never an empty tray: the card that opens this is
                            // itself silent with no keys, so this is only
                            // reachable if every key holds nothing nameable.
                            Text(String(localized: "No key on a watched account holds a permission this build can name."))
                                .dsText(.body17)
                                .foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // THE FOOTNOTE LEADS NOW. It explains why the row
                        // count exceeds the key count, which is a thing a
                        // reader wonders on the FIRST section rather than
                        // after scrolling past the last one.
                        if let note = VibenetKeyTray.footnote(items) {
                            Text(note)
                                .dsText(.label11)
                                .foregroundStyle(DS.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(sections) { section in
                            sectionView(section).id(section.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Space.s4)
                }
                .scrollIndicators(.hidden)
                // NO ANIMATION: this is where the tray OPENS, not a move it
                // makes while somebody watches. Animating it would slide the
                // list under a sheet that is itself still presenting.
                .onAppear {
                    guard let focus else { return }
                    proxy.scrollTo(focus, anchor: .top)
                }
            }
        }
    }

    /// One permission and its members. The rows sit on a single `fillFaint`
    /// group (prd §471) rather than loose under the heading, which fixes two
    /// things at once: a permission now reads as a container holding keys,
    /// and the heading finally has an edge to sit against — before this the
    /// heading started at x=0 while every row's text started at 40pt (a 26pt
    /// face plus its gap), so a section and its own rows shared no left edge
    /// anywhere on the screen.
    @ViewBuilder
    private func sectionView(_ section: VibenetTraySection) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(section.label)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // The same number the card states, from the same derivation —
                // so a reader can check the card against this list and find
                // them agreeing, which is most of what a tray is FOR.
                //
                // A PILL BESIDE ITS NAME, not a right-aligned figure: pushed
                // to the trailing edge it shared a column with every row's
                // expiry text below it, so a count of keys and a date read as
                // the same kind of value stacked down one side.
                Text("\(section.count)")
                    .dsText(.label11).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(DS.fillFaint))
                Spacer(minLength: DS.Space.s2)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(section.keys.enumerated()), id: \.element.id) { index, key in
                    row(key, in: section, isLast: index == section.keys.count - 1)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.fillFaint))
        }
    }

    /// One key. The ACCOUNT leads with its face because this list is
    /// room-wide: a key title alone ("Passkey") is the same words on four
    /// different accounts, and which account a key can act for is the fact
    /// that makes the row worth reading.
    @ViewBuilder
    private func row(_ key: VibenetTrayKey, in section: VibenetTraySection,
                     isLast: Bool) -> some View {
        if let onPick {
            Button {
                DSHaptic.selection()
                onPick(key.address)
            } label: {
                rowBody(key, in: section, door: true, isLast: isLast)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            .contextMenu { copyItems(key) }
        } else {
            rowBody(key, in: section, door: false, isLast: isLast)
                .contextMenu { copyItems(key) }
        }
    }

    /// The same copy actions the account detail's own key rows carry
    /// (prd §470), so a key hands over its id from wherever you found it —
    /// and one definition, since two would drift into two different sets of
    /// verbs for one object.
    @ViewBuilder
    private func copyItems(_ key: VibenetTrayKey) -> some View {
        Button {
            DSHaptic.tap()
            DSPasteboard.copySensitive(key.actor.actorId)
        } label: {
            Label(String(localized: "Copy key id"), systemImage: "doc.on.doc")
        }
        // Gated for `VibenetKeyIdentity.signerAddress`'s own reason: only an
        // address-shaped actorId has a signer to name.
        if let signer = VibenetKeyIdentity.signerAddress(key.actor) {
            Button {
                DSHaptic.tap()
                DSPasteboard.copySensitive(signer)
            } label: {
                Label(String(localized: "Copy signer address"), systemImage: "person.crop.circle")
            }
        }
        Button {
            DSHaptic.tap()
            DSPasteboard.copySensitive(key.address)
        } label: {
            Label(String(localized: "Copy account address"), systemImage: "wallet.pass")
        }
    }

    private func rowBody(_ key: VibenetTrayKey, in section: VibenetTraySection,
                         door: Bool, isLast: Bool) -> some View {
        // CENTRE-ALIGNED and vertically padded (prd §471). The rows carried no
        // padding of their own at all, so a section was three blocks of text
        // 14pt apart with a top-aligned face beside each — the "tightly packed
        // together" reading. `s2` gives every row real height, and a face at
        // `rowCircle` has something to sit against.
        HStack(alignment: .center, spacing: DS.Space.s3) {
            WalletFace(address: key.address, size: DS.Face.rowCircle, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.actor.kind.plainTitle)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: DS.Space.s2) {
                    Text(Self.accountName(key.address))
                        .dsText(.label11)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                    // WHICH KEY (prd §470) — the same noun-less monospaced
                    // tail the detail's rows carry. It matters more here than
                    // anywhere: this list groups BY PERMISSION, so two keys of
                    // one kind on one account land as adjacent rows reading
                    // identically end to end.
                    Text(VibenetKeyIdentity.short(key.actor.actorId))
                        .dsText(.label11).monospaced()
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    if let also = VibenetKeyTray.alsoLine(key, besides: section.label) {
                        Text(also)
                            .dsText(.label11)
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: DS.Space.s2)
            // The clock, in the row's own words rather than a shared one:
            // "Never expires" is a real answer here and drawing nothing in its
            // place would leave a reader unable to tell it from unknown.
            //
            // `label11` TERTIARY, down from `label12`: it was the same rung as
            // the account name and heavier than the id beside it, so the least
            // specific fact in the row read as its loudest. Urgency still gets
            // the mark, which is now the only colour in the block.
            let urgent = key.actor.expiryStanding(now: .now) == .soon
            Text(key.actor.expiryLabel(now: .now))
                .dsText(.label11)
                .fontWeight(urgent ? .semibold : .regular)
                .foregroundStyle(urgent ? Self.mark : DS.textTertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            if door {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s2)
        // A separator between rows and never under the last one — a FILL at
        // the faintest rung, which is what this design system draws instead of
        // a hairline (§8: nothing strokes a line).
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(DS.fillFaint).frame(height: 1)
            }
        }
    }

    /// The room's own mark, for the one fact in this tray that earns a colour.
    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// The account's own name if it has one, else its short address — the
    /// same fallback `VibenetRoomCard.displayName` makes, so this tray can
    /// never name an account differently from the room that opened it.
    private static func accountName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
