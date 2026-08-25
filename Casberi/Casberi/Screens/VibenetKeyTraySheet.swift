import SwiftUI

/// THE KEY TRAY — which keys are in which permission category (user,
/// 2026-08-25: *"on the All page the key card should open to a list of keys
/// and permissions that show which keys are in which category"*, prd §468).
///
/// **The chevron this makes honest.** `VibenetRoomCard.keysAggregateSection`
/// has carried a comment since 2026-08-24 saying it withholds the chevron the
/// design draws because "it points at a key tray that does not exist in this
/// build, and a chevron that opens nothing is the dead control §83 bans. The
/// surface is the part that carries the meaning; the affordance can arrive
/// with the screen it would open." This is that screen, and the chevron
/// arrives with it.
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
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    if sections.isEmpty {
                        // Never an empty tray: the card that opens this is
                        // itself silent with no keys, so this is only
                        // reachable if every key holds nothing nameable.
                        Text(String(localized: "No key on a watched account holds a permission this build can name."))
                            .dsText(.body17)
                            .foregroundStyle(DS.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    if let note = VibenetKeyTray.footnote(items) {
                        Text(note)
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DS.Space.s4)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: VibenetTraySection) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                Text(section.label)
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Space.s2)
                // The same number the card states, from the same derivation —
                // so a reader can check the card against this list and find
                // them agreeing, which is most of what a tray is FOR.
                Text("\(section.count)")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .monospacedDigit()
            }
            ForEach(Array(section.keys.enumerated()), id: \.element.id) { index, key in
                row(key, in: section)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }

    /// One key. The ACCOUNT leads with its face because this list is
    /// room-wide: a key title alone ("Passkey") is the same words on four
    /// different accounts, and which account a key can act for is the fact
    /// that makes the row worth reading.
    private func row(_ key: VibenetTrayKey, in section: VibenetTraySection) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            WalletFace(address: key.address, size: DS.Face.row, circular: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(key.actor.kind.plainTitle)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(Self.accountName(key.address))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                if let also = VibenetKeyTray.alsoLine(key, besides: section.label) {
                    Text(also)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.s2)
            // The clock, in the row's own words rather than a shared one:
            // "Never expires" is a real answer here and drawing nothing in its
            // place would leave a reader unable to tell it from unknown.
            Text(key.actor.expiryLabel(now: .now))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The account's own name if it has one, else its short address — the
    /// same fallback `VibenetRoomCard.displayName` makes, so this tray can
    /// never name an account differently from the room that opened it.
    private static func accountName(_ address: String) -> String {
        VibenetWatch.shared.name(for: address) ?? VibenetRoom.shortAddress(address)
    }
}
