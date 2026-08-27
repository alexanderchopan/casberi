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
    private static let mark = Color.fixed("#ffd60a")

    var body: some View {
        if !exposure.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "Approvals"))
                    .dsText(.label12).fontWeight(.semibold)
                    .foregroundStyle(Self.mark)

                Text(WalletApprovalExposure.headline(spenders: exposure.spenderCount,
                                                     total: exposure.total))
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s2)

                Text(String(localized: "Revoking is free apart from gas. Start at the top."))
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s1)

                // Enumerated for the entrance stagger only (2026-08-03, prd
                // §297). `exposure.all` is already ranked by what's at stake,
                // so the grant worth revoking first is also the row that lands
                // first — the treemap's largest-first rule, and the exact
                // instruction the subhead above gives ("Start at the top").
                ForEach(Array(exposure.all.enumerated()), id: \.element.id) { index, grant in
                    row(grant)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s3)

                if let target = exposure.oldestWorthReviewing {
                    reviewButton(target)
                }

                if let note = exposure.unpricedNote {
                    Text(note)
                        .dsText(.label11)
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
            .padding(.horizontal, DSRoomChassis.inset)
            .padding(.bottom, DS.Space.s4)
        }
    }

    /// One grant. The whole row is the tap target — a row is a read with ONE
    /// gesture (ruling 2026-07-16), and it carries no presentation of its own
    /// (the half-open-then-close lesson, 2026-07-28).
    private func row(_ grant: WalletApprovalExposure.Grant) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(grant)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.s2) {
                // WHO can spend it (2026-08-04). The spender is what this card
                // ranks and what you go and revoke, and Uniswap, Aave and
                // Morpho all ship marks the row was drawing as bare text.
                AssetMark(name: grant.spender, size: 26)
                    // Optically centred on the title line rather than the
                    // whole two-line block.
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        Text(grant.spender)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: DS.Space.s2)
                        // An unpriceable grant states a dash, never "$0" — the
                        // whole reason it sits outside the total (see the model).
                        Text(grant.usd.map(WalletValue.exactMoney) ?? "—")
                            .dsText(.price16)
                            .foregroundStyle(grant.usd == nil ? DS.textTertiary : DS.textPrimary)
                            .monospacedDigit()
                    }
                    metaLine(grant)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    /// "[Unlimited] USDC · granted Mar 2024". The chip carries the state; the
    /// rest is plain metadata.
    @ViewBuilder
    private func metaLine(_ grant: WalletApprovalExposure.Grant) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            chip(grant)
            Text(detail(grant))
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func chip(_ grant: WalletApprovalExposure.Grant) -> some View {
        if grant.unlimited || grant.forAll {
            chipLabel(grant.forAll ? String(localized: "Manages all")
                                   : String(localized: "Unlimited"),
                      fill: Self.mark, ink: .fixed("#000000"))
        } else {
            chipLabel(String(localized: "Capped"),
                      fill: DS.textPrimary.opacity(0.10), ink: DS.textSecondary)
        }
    }

    private func chipLabel(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text)
            .dsText(.label11).fontWeight(.bold)
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fill, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    /// The token, and the grant's age when a real block timestamp was read.
    /// §253's rule: `grantedAt` is set ONLY from a real block time, so a nil
    /// stays silent rather than dating a years-old grant to today.
    private func detail(_ grant: WalletApprovalExposure.Grant) -> String {
        guard let granted = grant.grantedAt else { return grant.symbol }
        return String(localized: "\(grant.symbol) · granted \(WalletApprovalAge.text(granted))")
    }

    /// The card's one action. It points at the OLDEST grant worth reviewing,
    /// never the biggest — the biggest is already the top row, and a button
    /// pointing at what the eye is on says nothing.
    private func reviewButton(_ target: WalletApprovalExposure.Grant) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(target)
        } label: {
            Text(String(localized: "Review the oldest grant"))
                .dsText(.callout15).fontWeight(.semibold)
                // Inverted against the card, and inverted correctly in BOTH
                // themes: white-on-black in dark, black-on-white in light.
                .foregroundStyle(DS.page)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s3)
                .background(DS.textPrimary,
                            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressSpring())
        .padding(.top, DS.Space.s3)
    }
}

/// How a grant's age reads (2026-08-03) — "6 days ago" while it's recent
/// enough for that to mean something, then the month it was made.
///
/// The switch is at a fortnight on purpose: "granted 47 days ago" is arithmetic
/// the reader has to do, and "granted Mar 2024" is the fact they wanted. A
/// years-old blanket approval is the thing this card exists to surface, and a
/// month-and-year states its age better than any relative phrase.
enum WalletApprovalAge {
    static func text(_ date: Date, now: Date = .now) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days <= 0 { return String(localized: "today") }
        if days == 1 { return String(localized: "yesterday") }
        if days < 14 { return String(localized: "\(days) days ago") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM y")
        return f.string(from: date)
    }
}
