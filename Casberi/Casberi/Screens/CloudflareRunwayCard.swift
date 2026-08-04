import SwiftUI

/// THE RUNWAY — the Cloudflare room's hero (2026-08-03, prd §296, ruled from
/// `design/cloudflare-viz/cloudflare-room-mocks.html`, option A).
///
/// One axis, drawn once, with a mark where each deadline actually falls, and
/// the rows underneath carrying the names. The anatomy is
/// `WalletApprovalExposureCard`'s, which is where these rulings were made: a
/// kicker in the card's one hue, a heavy headline stating the whole finding as
/// a sentence, ranked rows, one chip for the single fact that changes what
/// you'd do. And what was ruled OUT there is out here too — **no coloured rail
/// down the side of a row, no bar per row** (user: "it is too AI"), no
/// green/red anywhere. Nothing on this card is a gain or a loss; it is a
/// reading.
///
/// ## The quiet card is the point
///
/// Most accounts are healthy most of the time, and the room's whole failure
/// was that a healthy account looked identical to a broken connection: a blank
/// screen. So the quiet state is not a fallback, it is the state this card
/// exists for — which is why it is the SAME body with two different sentences
/// rather than a second card: same rail, same coverage note, same chrome, so
/// the two states cannot drift apart.
///
/// ## Liveness
///
/// Stores no `Thing` at all — only value types out of `CloudflareRunway` —
/// so corollary 5 has nothing to guard here. The `Thing` lookup happens at the
/// tap, in the section that owns the sheet.
///
/// FLAT BY LAW like its neighbours: a plain VStack, no generic `Widget`/`Row`
/// mount (the render-depth lesson, paid three times).
struct CloudflareRunwayCard: View {
    let runway: CloudflareRunway
    /// Opens the row's own thing. Hands back the ITEM, not a `Thing` — the
    /// card never holds one (see Liveness) — and not a bare id either, so the
    /// call site can say something sensible if the lookup misses.
    var onOpen: (CloudflareRunway.Item) -> Void

    /// **The runway draws itself** (2026-08-04, prd §298). This card shipped a
    /// day before the entrance grammar and was the only one of its family that
    /// never adopted it — the axis is time, so it reveals along time, and the
    /// rows land soonest-first behind it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The card's one hue: Cloudflare's own orange, read from the brand table
    /// rather than inlined, so the seat's tile, wash and this card can't drift
    /// (`DS.brandHue`'s own rule: components never inline the hex). The
    /// fallback can't fire — the table has the case — and exists only because
    /// the table returns an Optional by design.
    ///
    /// Deliberately NOT `DS.attention` (#ff9f0a) even though they sit close:
    /// this is an identity, not an alarm, and on a healthy account it heads a
    /// card that says everything is fine.
    private static let mark = DS.brandHue(for: "Cloudflare") ?? Color.fixed("#f6821f")

    private static let dot: CGFloat = 11
    private static let leadDot: CGFloat = 15
    /// Room under the axis for its two end labels.
    private static let tickRoom: CGFloat = 18

    var body: some View {
        let words = words
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Cloudflare"))
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(Self.mark)

            Text(words.headline)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s2)

            Text(words.note)
                .dsText(.subhead13)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.s1)

            // The same axis in both states. Drawing it on a quiet card rather
            // than hiding it is what makes them one card: the runway is CLEAR,
            // which is a different statement from "there is no runway".
            rail
                .padding(.top, DS.Space.s4)

            // Empty in the quiet state, so it needs no branch of its own.
            // Enumerated for the entrance stagger only — the items are already
            // soonest-first, so the arrival narrates the order the card made.
            ForEach(Array(runway.items.enumerated()), id: \.element.id) { index, item in
                row(item, lead: index == 0)
                    .chartArrival(index: index, reduceMotion: reduceMotion)
            }
            .padding(.top, DS.Space.s1)

            if let note = CloudflareRunway.coverageNote(uncovered: runway.uncovered,
                                                        zonesSeen: runway.zonesSeen) {
                Text(note)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.s3)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s2)
    }

    /// The card's two sentences — the one place the two states differ. Both
    /// sides are total: `isEmpty` already refused a runway that has neither
    /// deadlines nor a next date, so the card is never built with nothing to
    /// say.
    private var words: (headline: String, note: String) {
        if let head = runway.items.first {
            return (CloudflareRunway.headline(items: runway.items, span: runway.span),
                    CloudflareRunway.note(for: head, alone: runway.items.count == 1))
        }
        guard let next = runway.next else { return ("", "") }
        return (CloudflareRunway.quietHeadline(days: next.days),
                CloudflareRunway.quietNote(next))
    }

    // MARK: - The rail

    /// One axis for the whole card. Marks are placed against the axis width
    /// MINUS one mark, so the furthest sits inside the rail instead of hanging
    /// off its end; each is centred by nesting it in a full-size frame rather
    /// than by a half-difference computed per shape.
    private var rail: some View {
        // Hoisted out of the GeometryReader: these change only when the span
        // does (i.e. on a sync), and the closure below re-runs on every layout
        // pass as well as every body evaluation.
        let span = runway.span
        let grid = CloudflareRunway.gridDays(span: span)
        let items = runway.items
        return GeometryReader { geo in
            let travel = max(geo.size.width - Self.leadDot, 1)
            ZStack(alignment: .topLeading) {
                mark(Capsule(), width: geo.size.width, height: 2,
                     fill: DS.fillLine, at: 0, travel: 0)

                ForEach(grid, id: \.self) { day in
                    mark(Capsule(), width: 2, height: 8, fill: DS.fillStrong,
                         at: CloudflareRunway.position(days: day, span: span), travel: travel)
                }

                ForEach(items) { item in
                    let lead = item.id == items.first?.id
                    let size = lead ? Self.leadDot : Self.dot
                    mark(Circle(), width: size, height: size,
                         fill: lead ? Self.mark : DS.fillStrong,
                         at: CloudflareRunway.position(days: item.days, span: span),
                         travel: travel)
                }
            }
            .frame(height: Self.leadDot)
            .overlay(alignment: .bottomLeading) { tick(String(localized: "Today")) }
            .overlay(alignment: .bottomTrailing) { tick(CloudflareRunway.spanLabel(span: span)) }
        }
        .frame(height: Self.leadDot + Self.tickRoom)
        .chartWipe(reduceMotion: reduceMotion)
        // Hidden from VoiceOver: each mark is a row below, and the rows speak.
        // On the QUIET card there are no rows — but the headline and note
        // already say the whole finding ("nothing needs attention"), so a
        // spoken empty axis would add nothing but confusion.
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

    /// One deadline. The whole row is the tap target — a row is a read with
    /// ONE gesture (ruling 2026-07-16) — and it carries no presentation of its
    /// own (the half-open-then-close lesson, 2026-07-28).
    private func row(_ item: CloudflareRunway.Item, lead: Bool) -> some View {
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
                Text(CloudflareRunway.value(days: item.days))
                    .dsText(.price16)
                    .foregroundStyle(CloudflareRunway.isQuiet(item) ? DS.textTertiary : DS.textPrimary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s2)
    }

    @ViewBuilder
    private func metaLine(_ item: CloudflareRunway.Item) -> some View {
        HStack(spacing: DS.Space.s1 + 2) {
            if let chip = CloudflareRunway.chip(item) {
                Text(chip)
                    .dsText(.label11).fontWeight(.bold)
                    .foregroundStyle(Color.fixed("#000000"))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Self.mark, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            if let kind = CloudflareRunway.kindLine(item) {
                Text(kind)
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
