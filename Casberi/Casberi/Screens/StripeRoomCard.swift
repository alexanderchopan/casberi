import SwiftUI

/// THE STRIPE ROOM'S HEAD (2026-08-04, prd §298) — what the money is doing, and
/// what needs you by when.
///
/// The anatomy is `CloudflareRunwayCard`'s, which took it from
/// `WalletApprovalExposureCard`, which is where these rulings were made: a
/// kicker in the card's one hue, a heavy headline stating the whole finding as
/// a sentence, one axis drawn once, ranked rows, and a chip for the single fact
/// that changes what you'd do. What was ruled OUT there is out here too — no
/// coloured rail down the side of a row, no bar per row (user: "it is too AI"),
/// and **no green/red anywhere**, which matters more on this card than on
/// either of its ancestors: money arriving and money challenged are the two
/// registers §250 spent a whole ruling separating, and painting a balance green
/// would put a value judgement on the one number people check most.
///
/// ## The quiet card is the point, again
///
/// Cloudflare's lesson transfers exactly: most accounts are fine most of the
/// time, and the Stripe room's failure was that a healthy account and a broken
/// connection both rendered as a list of old rows. So a quiet account gets the
/// SAME body — same rail, same chrome — saying "Nothing needs you" over its
/// balance, rather than a second card or no card.
///
/// ## The one hue, and where it isn't spent
///
/// Stripe's indigo, from the brand table (never inlined — `DS.brandHue`'s own
/// rule). It marks the kicker and the chip on a dispute, and nothing else. An
/// outage does NOT get a colour: `stopped` is already the headline, and the
/// room's own §250 ruling is that challenged money never celebrates and never
/// alarms in colour — it states itself in words.
///
/// ## Liveness
///
/// Stores no `Thing` — only value types out of `StripeRoom`, which
/// `StripeRoomSource` filtered at the boundary. Corollary 5 has nothing to
/// guard here; the lookup happens at the tap, in the section that owns the
/// sheet.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
struct StripeRoomCard: View {
    let room: StripeRoom
    /// Hands back the ITEM, not a `Thing` — the card never holds one.
    var onOpen: (StripeRoom.Item) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let mark = DS.brandHue(for: "Stripe") ?? Color.fixed("#635bff")
    private static let dot: CGFloat = 11
    private static let leadDot: CGFloat = 15
    /// Room under the axis for its two end labels.
    private static let tickRoom: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The source-name eyebrow retired here 2026-08-22 (prd §452). A room
            // head renders only inside its own source's room, under a chip strip
            // where that source's chip is the lit one — so the card introduced
            // itself with a word already on screen, one row up.
            Text(StripeRoom.headline(room))
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(StripeRoom.note(room))
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            // The axis is drawn only where it has something to place. Unlike
            // Cloudflare's — whose quiet state IS "the runway is clear", a
            // statement worth a picture — a Stripe account with no deadline is
            // the ordinary case, and an empty axis under a balance would be
            // decoration claiming to be a reading.
            if !room.items.isEmpty {
                rail
                    .padding(.top, DS.Space.s4)

                ForEach(Array(room.items.enumerated()), id: \.element.id) { index, item in
                    row(item, lead: index == 0)
                        .chartArrival(index: index, reduceMotion: reduceMotion)
                }
                .padding(.top, DS.Space.s1)
            }

            notes
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    // MARK: - The rail

    /// One axis for the whole card, revealed left to right — time, moving, in
    /// the direction the deadlines approach. Marks are placed against the axis
    /// width MINUS one mark, so the furthest sits inside the rail instead of
    /// hanging off its end.
    private var rail: some View {
        // Hoisted out of the GeometryReader: these change only when the
        // deadlines do, and the closure re-runs on every layout pass.
        let span = StripeRoom.span(days: room.items.map(\.days))
        let items = room.items
        return GeometryReader { geo in
            let travel = max(geo.size.width - Self.leadDot, 1)
            ZStack(alignment: .topLeading) {
                mark(Capsule(), width: geo.size.width, height: 2,
                     fill: DS.fillLine, at: 0, travel: 0)

                ForEach(items) { item in
                    let lead = item.id == items.first?.id
                    let size = lead ? Self.leadDot : Self.dot
                    mark(Circle(), width: size, height: size,
                         fill: lead ? Self.mark : DS.fillStrong,
                         at: StripeRoom.position(days: item.days, span: span),
                         travel: travel)
                }
            }
            .frame(height: Self.leadDot)
            .overlay(alignment: .bottomLeading) { tick(String(localized: "Today")) }
            .overlay(alignment: .bottomTrailing) { tick(StripeRoom.spanLabel(span: span)) }
        }
        .frame(height: Self.leadDot + Self.tickRoom)
        .chartWipe(reduceMotion: reduceMotion)
        // Hidden from VoiceOver, deliberately: every mark on this axis is a row
        // below it, and those rows carry the name, the kind and the days. A
        // spoken rail would be the same facts a second time, in a worse order
        // (the `ShareBar`/`UniswapRangeBar` rule). Contrast `WalletFlowBand`,
        // whose diagram is the ONLY statement of its facts and so gets a
        // sentence.
        .accessibilityHidden(true)
    }

    /// One thing on the axis, centred on the track at `position`.
    private func mark<S: Shape>(_ shape: S, width: CGFloat, height: CGFloat,
                                fill: Color, at position: Double, travel: CGFloat) -> some View {
        shape
            .fill(fill)
            .frame(width: width, height: height)
            .frame(width: max(width, Self.leadDot), height: Self.leadDot)
            .offset(x: position * travel)
    }

    private func tick(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .monospacedDigit()
            .offset(y: Self.tickRoom)
    }

    // MARK: - Rows

    /// One deadline. The whole row is the tap target — a row is a read with ONE
    /// gesture (ruling 2026-07-16) — and it carries no presentation of its own
    /// (the half-open-then-close lesson, 2026-07-28).
    private func row(_ item: StripeRoom.Item, lead: Bool) -> some View {
        Button {
            DSHaptic.selection()
            onOpen(item)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .dsText(.heading17)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    metaLine(item)
                }
                Spacer(minLength: DS.Space.s2)
                Text(StripeRoom.value(days: item.days))
                    .dsText(.price16)
                    .foregroundStyle(item.days < 0 ? DS.textPrimary : DS.textSecondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    @ViewBuilder
    private func metaLine(_ item: StripeRoom.Item) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            if let chip = StripeRoom.chip(item) {
                Text(chip)
                    .dsText(.label11).fontWeight(.bold)
                    .foregroundStyle(Color.fixed("#ffffff"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            Text(StripeRoom.kindLine(item))
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
        }
    }

    /// What the card can't see, and how old what it can see is.
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let coverage = StripeRoom.coverageNote(room) {
                note(coverage)
            }
            if let stale = StripeRoom.staleNote(asOf: room.asOf) {
                note(stale)
            }
        }
        .padding(.top, DS.Space.s3)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .dsText(.label11)
            .foregroundStyle(DS.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
