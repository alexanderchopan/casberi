import SwiftUI

/// WHAT SOMEONE ELSE CAN STILL MOVE — the wallet room's approvals card
/// (2026-08-03, prd §292, ruled from `design/wallet-viz/approval-exposure-mocks.html`).
///
/// The room has listed approvals since §196, as rows in the stream and as a
/// tray line counting them. This is the first surface that ORDERS them, by the
/// only measure that orders them honestly: what each spender can move right
/// now (`WalletApprovalExposure`). A count says four things are true; this says
/// which one to look at.
///
/// ## The form, and what survived the rulings
///
/// Uber's receipt anatomy, ruled in over Cash App's and Apple's: a heavy
/// two-line headline that states the whole finding as a sentence, rows ranked
/// by money, and ONE full-width action. Three things were then ruled OUT of
/// the mock in review and are not to be reinstated without a new ruling:
///
/// - **No coloured rail down the side of each row** (user: "it is too AI"). It
///   was also redundant — the state word sat two millimetres away.
/// - **No hue on the amounts, and no green/red anywhere.** Nothing here is a
///   gain or a loss; it's a reading.
/// - **One hue on the whole card**, and it is YELLOW (user ruling): the card's
///   own name, and the word `Unlimited`. Everything else is the text ramp.
///
/// ## Why unlimited is the one thing worth marking
///
/// It's the only fact on a row that changes what you'd do about it. A capped
/// grant can only ever reach its cap; an unlimited one reaches whatever you
/// hold, today and every day after, including tokens you haven't bought yet.
/// The chip is deliberately NOT an alarm colour — an unlimited approval to
/// Uniswap is ordinary, nearly every wallet with history has several, and a
/// card that painted them all red would be ignored inside a week (and would
/// leave nothing louder for the day something is genuinely wrong).
///
/// ## Not black
///
/// The mock's card is pure black, which is Uber's field and not this app's.
/// The card uses the room's own surface like every sibling — a card that
/// hard-coded black would be unreadable in light mode, which is the exact bug
/// the cover's white ink shipped as once already. What was chosen here is the
/// ANATOMY; the theme still owns the page.
///
/// FLAT BY LAW like its neighbours — a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
///
/// Liveness: this view stores no `Thing` at all, only value types out of
/// `WalletApprovalExposure`, so corollary 5 has nothing to guard here. The
/// `Thing` lookup happens at the tap, in the section that owns the sheet.
struct WalletApprovalExposureCard: View {
    let exposure: WalletApprovalExposure
    /// Opens a grant's own prepare card (live allowance, revoke calldata, fee
    /// quote, Revoke.cash door). Reads and previews only — prd §112.
    var onOpen: (WalletApprovalExposure.Grant) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The card's one hue (user ruling, 2026-08-03). `#ffd60a` already exists
    /// in the tree as `KindGlyph`'s note yellow rather than being a new colour
    /// in the system, and it is NOT `DS.attention` (#ff9f0a): that orange was
    /// tried first and read as an alarm on a state that isn't one.
    ///
    /// Fixed rather than adaptive because it always carries black text on
    /// itself — the chip is a filled block in both themes, and the pair
    /// measures far past the 4.5:1 bar either way.
    var body: some View {
        if !exposure.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Enumerated for the entrance stagger only (2026-08-03, prd
                // §297). `exposure.all` is already ranked by what's at stake,
                // so the grant worth revoking first is also the row that lands
                // first — the treemap's largest-first rule, and the exact
                // instruction the subhead above gives ("Start at the top").
                ForEach(Array(exposure.all.enumerated()), id: \.element.id) { index, grant in
                    row(grant)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }

                if let target = exposure.oldestWorthReviewing {
                    reviewButton(target)
                }

                // The one footnote (prd §748): what a revoke costs.
                DSFootnote(prose: String(localized: "Revoking is free apart from gas."))
                    .padding(.top, DS.Space.s3)

                if let note = exposure.unpricedNote {
                    Text(note)
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s2)
                }
            }
            // **HEADERS, NO CARD (user ruling, prd §493: "Lets do headers no
            // cards").** Applied to EVERY scope list in both rooms, not to this
            // one section — the ask was consistency, and a single de-carded
            // list beside two carded ones is the drift it was meant to end.
            //
            // The reasoning, since "what would Apple do" was the question:
            // Apple uses cards where each is a DIFFERENT KIND of reading you
            // might act on separately (Health, Fitness). Its MONEY screens —
            // Wallet transactions, Stocks — are plain rows under section
            // headers. A scope's list is groups of ONE kind of thing, so it
            // takes the money-screen treatment.
            //
            // It is also what the room already did everywhere else: every
            // scope's drawing is bare (§483), Holdings' list is bare,
            // Permissions' list is bare. These were the last three surfaces
            // disagreeing with their own room.
            .padding(.bottom, DS.Space.s4)
        }
    }

    /// One grant. The whole row is the tap target — a row is a read with ONE
    /// gesture (ruling 2026-07-16), and it carries no presentation of its own
    /// (the half-open-then-close lesson, 2026-07-28).
    /// **ONE ROW, THE WALLET LIST'S ANATOMY (prd §944).** Mark, name, one
    /// line — the grant's word, red only when it has no limit, then the token
    /// — and the amount at stake trailing, before the chevron that says this
    /// row is a door (the delegations above have none). An unpriced grant
    /// states no amount at all; the note under the list says why it is not
    /// in the total.
    private func row(_ grant: WalletApprovalExposure.Grant) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(grant)
        } label: {
            HStack(spacing: DS.Space.s3) {
                AssetMark(name: grant.spender, size: DS.Face.list)
                VStack(alignment: .leading, spacing: 1) {
                    Text(grant.spender)
                        .dsText(.body17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    line(grant)
                        .dsText(.subhead12)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.s2)
                if let usd = grant.usd {
                    Text(WalletValue.exactMoney(usd))
                        .dsText(.price17)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                }
                DSChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    /// "No limit · USDC", "Capped · USDT", "All Field Notes".
    private func line(_ grant: WalletApprovalExposure.Grant) -> Text {
        if grant.forAll {
            return Text(String(localized: "All")).foregroundStyle(DS.destructive)
                + Text(" \(grant.symbol)").foregroundStyle(DS.textTertiary)
        }
        if grant.unlimited {
            return Text(String(localized: "No limit")).foregroundStyle(DS.destructive)
                + Text(" · \(grant.symbol)").foregroundStyle(DS.textTertiary)
        }
        return Text(String(localized: "Capped · \(grant.symbol)")).foregroundStyle(DS.textTertiary)
    }

    /// The oldest grant worth a look, as a row — a verb is a row (prd §746),
    /// never an inverted slab.
    private func reviewButton(_ target: WalletApprovalExposure.Grant) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(target)
        } label: {
            HStack(spacing: DS.Space.s3) {
                ZStack {
                    Circle().fill(DS.fillFaint)
                    Image(systemName: "clock")
                        .dsGlyph(.subhead, weight: .semibold)
                        .foregroundStyle(DS.tint)
                        .accessibilityHidden(true)
                }
                .frame(width: DS.Face.list, height: DS.Face.list)
                Text(String(localized: "Review the oldest grant"))
                    .dsText(.body17)
                    .foregroundStyle(DS.tint)
                Spacer(minLength: 0)
                DSChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }
}

enum WalletApprovalAge {
    static func text(_ date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "yesterday") }
        if days < 14 { return String(localized: "\(days) days ago") }
        return monthYear.string(from: date)
    }

    /// ONE formatter, not one per call (PERF, prd §628): this is read from the
    /// card's own `detail(_:)`, so it ran per approval per render.
    /// Thread-safe for formatting since iOS 7, never mutated after this.
    private static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM y")
        return f
    }()
}
