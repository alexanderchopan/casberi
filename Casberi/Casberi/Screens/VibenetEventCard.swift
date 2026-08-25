import SwiftUI

/// A vibenet key event, as its own anatomy (prd §467, 2026-08-25).
///
/// **What it replaces.** These events opened to a title, a Share disc and a
/// one-row table reading "From — on vibenet" — the title's own last two words
/// wearing a field label. Everything a person opens a key event to learn was
/// already in the corpus or one lookup away and no view asked for it.
///
/// The anatomy is the design's: what happened, what that key may do, and the
/// three facts a key event has — the ACCOUNT (a door, since the account's own
/// card is where the rest of the story is), how many keys it carries now, and
/// when this one dies.
///
/// **Every block is silent when it has nothing**, which here is not politeness
/// but the point: `VibenetEventFacts` refuses to name a key's permissions
/// unless exactly one key on the account matches the event's expiry, so most
/// of these draw no chips at all. See that type for why a plausible guess is
/// worse than a gap on this particular card.
struct VibenetEventCard: View {
    let facts: VibenetEventFacts
    /// The event's own words, minus the address the account row already shows
    /// — `Thing.summary`, which every landed event stamps for this purpose.
    let lead: String?
    /// Opens the account's own card. A closure, never a `.sheet` of this
    /// card's own: a presentation attached to a view inside a presented sheet
    /// resolves to the same controller and tears itself down (CLAUDE.md, "one
    /// screen, one `.sheet`", paid three times).
    var onAccount: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lead, !lead.isEmpty {
                Text(lead)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // WHAT THIS KEY MAY DO — chips, the shape the design settled on
            // after a grid was drawn and refused ("the chips look better, the
            // grid is just really bad"). Drawn only on a provable match.
            if !facts.permissions.isEmpty {
                VibenetPermissionChips(names: facts.permissions,
                                       reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s3)
            }
            // THE ACCOUNT — a row, not a spec value, because it is the one
            // thing on this card worth walking into and a face is what makes
            // that legible before the words are read.
            Button {
                onAccount(facts.account)
            } label: {
                HStack(spacing: DS.Space.s3) {
                    WalletFace(address: facts.account, size: DS.Face.row, circular: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Account"))
                            .dsText(.label12)
                            .foregroundStyle(DS.textTertiary)
                        Text(facts.accountName)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DS.Space.s2)
                    Image(systemName: "chevron.right")
                        .accessibilityHidden(true)
                        .dsGlyph(12, weight: .semibold)
                        .foregroundStyle(DS.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsHover()
            .padding(.top, DS.Space.s4)

            // The two remaining facts, each silent when unknown. "Keys now" is
            // deliberately present-tense: it is the account's live roster, not
            // a count anybody recorded at the time this happened.
            if facts.keysNow != nil || facts.expires != nil {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if let keys = facts.keysNow {
                        factRow(String(localized: "Keys now"), "\(keys)", tinted: false)
                    }
                    if let expires = facts.expires {
                        factRow(String(localized: "Expires"),
                                Self.expiryWords(expires),
                                tinted: expires.timeIntervalSinceNow < Self.soon)
                    }
                }
                .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    /// Under a week is worth the brand hue — the same threshold the room's own
    /// soonest-expiry callout uses, so a key reading "urgent" here reads
    /// urgent there too.
    private static let soon: TimeInterval = 7 * 24 * 3600

    private func factRow(_ label: String, _ value: String, tinted: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(label)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .dsText(.callout15)
                .fontWeight(tinted ? .semibold : .regular)
                .foregroundStyle(tinted ? Self.mark : DS.textPrimary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// A date, or a countdown when one is close enough to act on. The room
    /// already speaks in days for a near expiry and there is no reason this
    /// card should make a reader convert a calendar date in their head.
    static func expiryWords(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return String(localized: "Expired") }
        if seconds < soon {
            let days = max(1, Int((seconds / 86_400).rounded(.up)))
            return days == 1
                ? String(localized: "Tomorrow")
                : String(localized: "In \(days) days")
        }
        return date.formatted(.dateTime.day().month().year())
    }
}

/// The permission chips — one per thing a key may do.
///
/// A CHIP and not a grid cell, which is a ruling rather than a style: a matrix
/// of every key against every permission was drawn, reviewed and refused
/// ("the grid is just really bad"), because comparing keys is not what anybody
/// opens one key to do. Chips read as what this key IS allowed, which is the
/// question.
struct VibenetPermissionChips: View {
    let names: [String]
    var reduceMotion: Bool = false

    var body: some View {
        // Wraps rather than scrolls: a key carries at most five of these and a
        // permission that runs off the edge of a card is a permission nobody
        // reads.
        FlowLayout(spacing: DS.Space.s2) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .dsText(.subhead13).fontWeight(.medium)
                    .foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, 6)
                    .background(DS.fillStrong, in: Capsule())
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
        }
    }
}
