import SwiftUI

/// What the CardPointers room leads with (prd §420): the nearest deadline, then
/// the cards the offers sit on.
///
/// **It states no total value, by ruling.** The obvious card is "$312 waiting
/// for you" and it is false twice — an offer is worth its face value only to
/// somebody who was going to spend there anyway (a CEILING, not a saving), and
/// the values do not share a unit ("$10 back on $50+" beside "20% off"). Their
/// own words for the soonest offer are shown; nothing is added up.
///
/// Holds no `Thing` (liveness corollary 5) — it is handed a value and calls
/// back with a `sourceRef`, so the lookup happens against the live corpus.
struct CardPointersRoomCard: View {
    let room: CardPointers.Room
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(room.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)

            if let soonest = room.soonest {
                Button { onOpen(soonest.id) } label: {
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(soonest.merchant)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                        // Their words, never ours, and never a number we made.
                        if let terms = soonest.terms {
                            Text(terms)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                        }
                        if let expires = soonest.expires {
                            Text("Expires \(expires.formatted(.relative(presentation: .named)))")
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !room.cards.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(room.cards) { card in
                        HStack(spacing: DS.Space.s2) {
                            Text(card.name)
                                .dsText(.callout15)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s2)
                            Text(card.active == 1
                                 ? String(localized: "1 offer")
                                 : String(localized: "\(card.active) offers"))
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                }
            }

            // Named rather than hidden: a head claiming "4 expire this week"
            // over a book where others carry no date at all is quietly wrong
            // about its own completeness.
            if room.undated > 0 {
                Text(room.undated == 1
                     ? String(localized: "1 more offer with no end date")
                     : String(localized: "\(room.undated) more offers with no end date"))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
