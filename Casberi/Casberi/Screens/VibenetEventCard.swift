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
    /// THE EVENT'S OWN WORDS, and since §495 this card's HEAD rather than a
    /// line under one — `Thing.summary`, which every landed event stamps as
    /// its title minus the address.
    ///
    /// **It beats anything this card could derive, and the reason is WHEN it
    /// was written.** The landing resolves the key's kind from a live read at
    /// the moment the event arrived (`VibenetEventKind.phrase(keyLabel:)`),
    /// so `summary` says "New passkey authorized" even for a key that has
    /// since been revoked — while the expiry join below runs against the
    /// account's CURRENT roster and can only name a key that is still there.
    /// Deriving the head would silently downgrade every event whose key is
    /// gone to "A key", which is most revocations.
    let lead: String?
    /// When it happened. The event's own `capturedAt`, which is a real block
    /// time rather than when we looked.
    var happenedAt: Date? = nil
    /// Opens the account's own card. A closure, never a `.sheet` of this
    /// card's own: a presentation attached to a view inside a presented sheet
    /// resolves to the same controller and tears itself down (CLAUDE.md, "one
    /// screen, one `.sheet`", paid three times).
    var onAccount: (String) -> Void
    /// Opens the transaction on a block explorer. nil where the ref could not
    /// be read as a hash, and then no door is drawn at all — §83: no verb
    /// beats a verb that lands somewhere else.
    var onTransaction: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let mark = DS.brandHue(for: "Base Vibenet") ?? Color.fixed("#0052ff")

    /// Whether the consequence sentence is inside its clock window (prd §501).
    ///
    /// **Gated hard, and only on the one kind that has a clock at all.** A
    /// revocation, a lock and an unlock all state a fact with no deadline in
    /// it, so ticking them would spend a per-minute redraw on a sentence that
    /// cannot change. An authorization whose expiry is further out than
    /// `ticksWithin` is in the same position.
    private var consequenceTicks: Bool {
        guard facts.kind == .authorized, let expires = facts.expires else { return false }
        let seconds = expires.timeIntervalSinceNow
        return seconds > 0 && seconds < Self.ticksWithin
    }

    var body: some View {
        // BY THE MINUTE, NEVER BY THE SECOND. The finest thing this sentence
        // says is minutes, so a per-second tick would redraw the head sixty
        // times to change nothing — and the head is where the account's face
        // and the sheet's stamp live. A minute is the resolution of the claim.
        if consequenceTicks {
            TimelineView(.periodic(from: .now, by: 60)) { tick in
                card(now: tick.date)
            }
        } else {
            card(now: .now)
        }
    }

    @ViewBuilder
    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // **WALLET'S RECEIPT ANATOMY** (prd §495, user: *"the sheet for
            // activity should look in some way like the design we have for
            // wallet activity"*, and then the same for the account and
            // permissions sheets).
            //
            // `DSSheetHead` is `MoneyReceiptCard`'s head (§363) with the money
            // taken out: subject disc and state stamp on one row, then when,
            // then the thing's own words, then one supporting line, then one
            // sentence saying what it means now. Every part answers a question
            // an EVENT has, which is why this sheet had been inventing a worse
            // version of the same shape.
            //
            // The disc is the ACCOUNT's face — the event's subject — matching
            // the receipt, where the disc is the counterparty and is a door.
            DSSheetHead(disc: {
                Button { onAccount(facts.account) } label: {
                    WalletFace(address: facts.account, size: DS.Face.shelf, circular: true)
                }
                .buttonStyle(.plain)
                .dsHover()
            },
                        stamp: verbStamp,
                        stampInk: facts.kind == .locked ? DS.attention : DS.textSecondary,
                        lead: happenedAt.map {
                            $0.formatted(.dateTime.day().month().hour().minute())
                        },
                        title: title,
                        secondary: subtitle,
                        sentence: consequence(now: now),
                        // The room's own hue pours behind the paper, the way
                        // a money receipt takes the transaction's.
                        hue: Self.mark)

            // WHAT THIS KEY MAY DO — chips, the shape the design settled on
            // after a grid was drawn and refused ("the chips look better, the
            // grid is just really bad"). Drawn only on a provable match, so on
            // most events there is nothing here and that is correct — see
            // `VibenetEventFacts` for why a guess is worse than a gap.
            if !facts.permissions.isEmpty {
                VibenetPermissionChips(names: facts.permissions,
                                       reduceMotion: reduceMotion)
                    .padding(.top, DS.Space.s3)
            }

            // **NO ACCOUNT ROW** (prd §495). The head's disc IS the account
            // and is already a door, so a row naming it again below is §366's
            // read-it-twice with a face and a chevron attached. The receipt
            // this anatomy comes from makes the same call: its subject disc is
            // the counterparty, and it draws no counterparty row.

            // THE TRANSACTION — the one verb this sheet can honestly offer,
            // and it was missing entirely: until §495 the only control here
            // was Share, while every event has carried its own hash inside
            // its `sourceRef` since the room shipped.
            if let hash = facts.txHash, let onTransaction {
                Button {
                    onTransaction(hash)
                } label: {
                    walkRow(mark: {
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.fillFaint)
                            .frame(width: DS.Face.row, height: DS.Face.row)
                            .overlay {
                                Image(systemName: "arrow.up.forward")
                                    .accessibilityHidden(true)
                                    .dsGlyph(11, weight: .semibold)
                                    .foregroundStyle(DS.textTertiary)
                            }
                    },
                    label: String(localized: "Transaction"),
                    value: Self.shortHash(hash))
                }
                .buttonStyle(.plain)
                .dsHover()
                .padding(.top, DS.Space.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// **NO CARD** (user, 2026-08-26: *"Lets do headers no cards"*, and §483's
    /// own "we don't do cards"). It drew on a `fillFaint` slab, which put a
    /// second surface inside a presented sheet — a card on a card.
    @ViewBuilder
    private func walkRow<Mark: View>(@ViewBuilder mark: () -> Mark,
                                     label: String,
                                     value: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            mark()
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                Text(value)
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

    /// The state word the head stamps, top-right — the receipt's own stamp
    /// slot. A verb rather than a noun, because what a key event records is
    /// something that HAPPENED to the account.
    private var verbStamp: String {
        switch facts.kind {
        case .authorized: String(localized: "Authorized")
        case .revoked:    String(localized: "Revoked")
        case .locked:     String(localized: "Locked")
        case .unlocking:  String(localized: "Unlocking")
        }
    }

    /// WHEN IT HAPPENED, above the title.
    ///
    /// The DATE and not the verb: `lead` is a whole sentence carrying the
    /// verb already ("New passkey authorized"), so an eyebrow reading
    /// "Authorized" is §366's read-its-first-line-twice one word at a time.
    /// A lock takes the attention hue here — the one kind whose eyebrow is
    /// worth a colour, because it is the one where the standing state changed
    /// rather than the roster.
    @ViewBuilder
    private var eyebrow: some View {
        if let happenedAt {
            Text(happenedAt.formatted(.dateTime.day().month().hour().minute()))
                .dsText(.label12)
                .foregroundStyle(facts.kind == .locked ? DS.attention : DS.textTertiary)
                .lineLimit(1)
                .padding(.bottom, 2)
        }
    }

    /// THE SUBJECT.
    ///
    /// The event's own words where it has them (see `lead`). The fallbacks
    /// below are for a row landed before `summary` was stamped: on a key
    /// event the KEY where the join could name it, else the honest generic;
    /// on a lock or an unlock the ACCOUNT, because that is what the event is
    /// about.
    private var title: String {
        if let lead, !lead.isEmpty { return lead }
        if let key = facts.key { return key.title }
        switch facts.kind {
        case .authorized: return String(localized: "A new key")
        case .revoked:    return String(localized: "A key")
        case .locked:     return String(localized: "This account is locked")
        case .unlocking:  return String(localized: "This account is unlocking")
        }
    }

    /// The key's own clause plus its short id, so the sheet names the same
    /// key the Permissions list does. Silent on a lock — there is no key.
    private var subtitle: String? {
        guard let key = facts.key else { return nil }
        guard let detail = key.detail else { return key.shortID }
        return "\(key.shortID) · \(detail)"
    }

    /// WHAT IT MEANS NOW — one sentence, assembled from stamped facts and
    /// never parsed out of a title.
    private func consequence(now: Date) -> String? {
        switch facts.kind {
        case .authorized:
            guard let expires = facts.expires else {
                return facts.key == nil
                    ? nil
                    : String(localized: "It does not expire.")
            }
            return expires.timeIntervalSince(now) <= 0
                ? String(localized: "It has since expired.")
                : Self.expiryClause(expires, now: now)
        case .revoked:
            return String(localized: "It can no longer act for this account.")
        case .locked:
            return String(localized: "No key can act for this account until it is unlocked.")
        case .unlocking:
            return String(localized: "When the timelock elapses, this account can be spent from again.")
        }
    }

    /// How close an expiry has to be before the consequence sentence becomes
    /// a CLOCK rather than a statement (prd §501). Two days, which is the
    /// span over which "tomorrow" stops being a useful answer and a person
    /// might reasonably still be deciding whether to act.
    static let ticksWithin: TimeInterval = 48 * 3600

    /// Under a week is worth the brand hue — the same threshold the room's own
    /// soonest-expiry callout uses, so a key reading "urgent" here reads
    /// urgent there too.
    private static let soon: TimeInterval = 7 * 24 * 3600

    /// A transaction hash, short enough for a row. Head AND tail, unlike an
    /// address: a hash has no checksum case and no ENS name, so the head is
    /// the only part anybody recognises when comparing against an explorer.
    static func shortHash(_ hash: String) -> String {
        guard hash.count > 14 else { return hash }
        return hash.prefix(8) + "…" + hash.suffix(4)
    }

    /// The expiry as a SENTENCE.
    ///
    /// Spelled out rather than lowercasing `expiryWords`, which was the first
    /// cut and shipped "It expires dec 31, 2099." — the month's own capital
    /// eaten by a blanket `.lowercased()`. A near expiry reads "tomorrow" or
    /// "in 3 days" and a far one takes "on" before its date, which is the
    /// clause the countdown forms deliberately do not want.
    static func expiryClause(_ date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        // THE LAST TWO DAYS ARE A CLOCK (prd §501). Rounding up to days is
        // right for a key with a week left and wrong for one with four hours:
        // it reads "It expires tomorrow." for the whole of the last day, which
        // is the sentence a sheet left open for an hour goes on saying after
        // it has stopped being the useful answer.
        //
        // Outside this window the clause is unchanged, deliberately — a
        // seconds counter on a key with three weeks left is theatre, and the
        // card would be spending a per-minute redraw on it.
        if seconds < ticksWithin {
            let hours = Int(seconds / 3600)
            if hours >= 1 {
                return hours == 1
                    ? String(localized: "It expires in 1 hour.")
                    : String(localized: "It expires in \(hours) hours.")
            }
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            return minutes == 1
                ? String(localized: "It expires in 1 minute.")
                : String(localized: "It expires in \(minutes) minutes.")
        }
        if seconds < soon {
            let days = max(1, Int((seconds / 86_400).rounded(.up)))
            return days == 1
                ? String(localized: "It expires tomorrow.")
                : String(localized: "It expires in \(days) days.")
        }
        return String(localized: "It expires on \(date.formatted(.dateTime.day().month().year())).")
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
