import Foundation
import SwiftData

/// The Dodo Payments room head's reading half (2026-09-01, prd §558) — landed
/// rows turned into the card's own value, with every judgement left to
/// `DodoPaymentsRoom`.
///
/// The split is `GnosisPayRoomSource`'s, for its reason: everything that could
/// be wrong in a way that still renders perfectly — currencies summed into one
/// figure, a payment with no readable amount counted as zero, a window-on-window
/// claim made against a window the room never observed, an unsettled refund
/// subtracted from revenue — lives on the other side of that line, in a file the
/// harness compiles WHOLE.
enum DodoPaymentsRoomSource {

    /// The bridge's own source name, taken from the bridge rather than spelled
    /// again — `GnosisPayRoomSource.source`'s rule.
    static let source = DodoPaymentsAccount.source

    /// The head, or nil when there is nothing worth drawing.
    @MainActor
    static func compose(things: [Thing] = [], now: Date = .now) -> DodoPaymentsRoom? {
        // Live at the BOUNDARY, before any stored property is read
        // (corollary 4) — the caller's array may be a debounced snapshot.
        let rows = things.live.filter { $0.source == source }
        guard !rows.isEmpty else { return nil }
        let room = DodoPaymentsRoom.compose(sightings: sightings(rows),
                                            disputes: openDisputes(rows),
                                            retries: retries(rows, now: now),
                                            now: now)
        return room.isEmpty ? nil : room
    }

    // MARK: - Reading the rows

    /// The money rows — payments and refunds — reduced to what the head reads.
    /// The ONLY place a `Thing`'s stored money fields are touched.
    ///
    /// `priceValue`/`priceCurrency` are read as DATA, never the title, which is
    /// prose the bridge composed (`GnosisPayRoomSource`'s rule, and
    /// `StripeRoom`'s reason for having no figure at all).
    @MainActor
    private static func sightings(_ rows: [Thing]) -> [DodoPaymentsRoom.Sighting] {
        rows.compactMap { thing in
            guard thing.kind == .transaction else { return nil }
            let isRefund = thing.tags.contains("Refund")
            guard isRefund || thing.tags.contains("Payment") else { return nil }
            return DodoPaymentsRoom.Sighting(
                amount: thing.priceValue,
                currency: thing.priceCurrency,
                at: thing.capturedAt,
                isRefund: isRefund,
                settled: isRefund ? refundSettled(thing) : true)
        }
    }

    /// Did this refund actually move money back?
    ///
    /// `DodoPaymentsShape.refund` lands a refund at every status and facets the
    /// ones that are not `succeeded` — so a settled refund's tags are exactly
    /// `["Refund"]` and an unsettled one carries a status facet beside it. The
    /// test is therefore "no facet other than the tag" rather than a list of
    /// known-bad statuses: an unrecognised status must read as NOT settled, or a
    /// refund Dodo invents a new word for would silently subtract from revenue
    /// the day it appears.
    @MainActor
    private static func refundSettled(_ thing: Thing) -> Bool {
        thing.tags.allSatisfy { $0 == "Refund" }
    }

    /// Disputes this room has seen opened and never seen closed.
    ///
    /// Joined on the DISPUTE ID carried inside the ref rather than on anything
    /// in the title: `DodoPaymentsIngest` lands the two halves as
    /// `dodopayments:dispute:<id>:opened` and `…:closed`, so the id is already
    /// on both rows and no field needs adding to `Thing`.
    ///
    /// A dispute whose opening this app never saw — one that predated the
    /// connection, which the bridge deliberately seeds in silence — has no
    /// `opened` row, so it can never appear here. That is correct rather than a
    /// gap: this card says what is open THAT WE WATCHED OPEN, and inventing the
    /// rest from a closed row's absence would be a claim about disputes we have
    /// no record of.
    @MainActor
    private static func openDisputes(_ rows: [Thing]) -> [DodoPaymentsRoom.Dispute] {
        var opened: [String: DodoPaymentsRoom.Dispute] = [:]
        var closed: Set<String> = []
        for thing in rows {
            guard let ref = thing.sourceRef, let id = disputeID(ref) else { continue }
            if ref.hasSuffix(":closed") {
                closed.insert(id)
            } else if ref.hasSuffix(":opened") {
                opened[id] = DodoPaymentsRoom.Dispute(id: id,
                                                      amount: thing.priceValue,
                                                      currency: thing.priceCurrency,
                                                      at: thing.capturedAt)
            }
        }
        return opened.filter { !closed.contains($0.key) }.map(\.value)
    }

    /// `dodopayments:dispute:<id>:opened` → `<id>`. Nil for any other ref.
    ///
    /// Built by dropping the fixed prefix and the fixed suffix rather than by
    /// splitting on ":" — a Dodo object id containing a colon would otherwise
    /// join the two halves of one dispute under different keys, which renders
    /// as a dispute that never closes.
    static func disputeID(_ ref: String) -> String? {
        let prefix = "dodopayments:dispute:"
        guard ref.hasPrefix(prefix) else { return nil }
        let rest = String(ref.dropFirst(prefix.count))
        for suffix in [":opened", ":closed"] where rest.hasSuffix(suffix) {
            let id = String(rest.dropLast(suffix.count))
            return id.isEmpty ? nil : id
        }
        return nil
    }

    /// Subscriptions with a next attempt on the clock. The bridge stamps `dueAt`
    /// only while a subscription is still RECOVERABLE, so every one of these can
    /// still be saved — which is what makes them worth a rail rather than a
    /// list of things that already ended.
    @MainActor
    private static func retries(_ rows: [Thing], now: Date) -> [DodoPaymentsRoom.Retry] {
        rows.compactMap { thing in
            guard thing.kind == .reminder, thing.tags.contains("Subscription"),
                  let due = thing.dueAt else { return nil }
            return DodoPaymentsRoom.Retry(id: thing.sourceRef ?? thing.id.uuidString,
                                          name: thing.title,
                                          due: due,
                                          days: DodoPaymentsRoom.days(from: now, to: due))
        }
    }

    // MARK: - Probe

    /// The probe's lines — driven by `-dodoPaymentsRoomProbe`, calling the REAL
    /// `compose` (`CloudflareRunwaySource.probeLines`'s rule: a probe must not
    /// be able to disagree with the card it explains).
    ///
    /// It exists because a thin or empty head has SIX causes that render as one
    /// silence, and only the last two are bugs:
    ///
    ///   1. not connected, so no row has ever landed;
    ///   2. connected onto an account that took no payment in the window — a
    ///      real answer the card states out loud, and the everyday one for the
    ///      occasional-payment accounts this bridge targets;
    ///   3. the room is younger than two windows, so `prior` is nil throughout
    ///      and no comparison is claimed — correct, and easily misread as a
    ///      missing feature;
    ///   4. every open dispute predates the connection, so the bridge seeded it
    ///      silently and there is no `opened` row to join against;
    ///   5. `priceValue` or `priceCurrency` missing, which drops a payment from
    ///      every total while its row still draws perfectly;
    ///   6. every refund reading as UNSETTLED, which would silently stop the
    ///      net being a net.
    @MainActor
    static func probeLines(context: ModelContext, now: Date = .now) -> [String] {
        let source = self.source
        let rows = ((try? context.fetch(FetchDescriptor<Thing>(
            predicate: #Predicate { $0.source == source },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []).live
        var out: [String] = [
            "dodoRoom| connected=\(TokenBridge.dodoPayments.connected) rows=\(rows.count)"
                + " windowDays=\(DodoPaymentsRoom.windowDays)"
                + " bridgeWindowDays=\(DodoPaymentsAccount.windowDays)"
                + " windowFrom=\(DodoPaymentsRoom.windowStart(now, back: 1).formatted(.iso8601))"
                + " priorFrom=\(DodoPaymentsRoom.windowStart(now, back: 2).formatted(.iso8601))",
        ]
        // Every money row as data, newest first — the amount/currency PAIRING
        // and the settled flag are the tells, since either one missing removes
        // the row from the total while the row itself renders correctly.
        for sight in sightings(rows).sorted(by: { $0.at > $1.at }) {
            let window = sight.at >= DodoPaymentsRoom.windowStart(now, back: 1) ? "window"
                : (sight.at >= DodoPaymentsRoom.windowStart(now, back: 2) ? "prior" : "older")
            out.append("dodoMoney| \(sight.isRefund ? "refund" : "payment")"
                       + " amount=\(sight.amount.map { String($0) } ?? "UNREADABLE")"
                       + " currency=\(sight.currency ?? "NONE")"
                       + " settled=\(sight.settled ? "yes" : "NO — subtracts nothing")"
                       + " in=\(window)"
                       + " at=\(sight.at.formatted(.iso8601))")
        }
        for dispute in openDisputes(rows) {
            out.append("dodoDispute| open id=\(dispute.id)"
                       + " amount=\(dispute.amount.map { String($0) } ?? "unpriced")"
                       + " currency=\(dispute.currency ?? "NONE")"
                       + " at=\(dispute.at.formatted(.iso8601))")
        }
        guard let room = compose(things: rows, now: now) else {
            out.append("compose=nil — no card (not connected, or nothing has ever landed)")
            return out
        }
        out.append("headline=\(DodoPaymentsRoom.headline(room))")
        out.append("note=\(DodoPaymentsRoom.note(room))")
        out.append("refundNote=\(DodoPaymentsRoom.refundNote(room) ?? "none")")
        out.append("coverage=\(DodoPaymentsRoom.coverageNote(room) ?? "none")")
        out.append("footnote=\(DodoPaymentsRoom.footnote(room, now: now) ?? "none")")
        out.append("totals| currencies=\(room.currencies.count) payments=\(room.payments)"
                   + " unpriced=\(room.unpriced) unmatchedRefunds=\(room.unmatchedRefunds)"
                   + " allTime=\(room.allTime) disputesOpen=\(room.disputes.count)"
                   + " retries=\(room.retryTotal)"
                   + " oldest=\(room.oldest?.formatted(.iso8601) ?? "none")"
                   + " knowsPrior=\(DodoPaymentsRoom.knowsPriorWindow(oldest: room.oldest, now: now) ? "YES" : "no — no comparison will be claimed")")
        let top = room.lead?.payments ?? 0
        for currency in room.currencies {
            out.append("dodoCurrency| \(currency.code)"
                       + " · \(DodoPaymentsRoom.currencyLine(currency))"
                       + " · gross=\(currency.gross) refunded=\(currency.refunded)"
                       + " · prior=\(currency.prior.map { String($0) } ?? "unknown")"
                       + " · delta=\(DodoPaymentsRoom.deltaLabel(currency) ?? "none")"
                       + " · share=\(String(format: "%.2f", DodoPaymentsRoom.share(payments: currency.payments, of: top)))")
        }
        let span = DodoPaymentsRoom.span(days: room.retries.map(\.days))
        for retry in room.retries {
            out.append("dodoRetry| \(retry.name) · days=\(retry.days)"
                       + " · \(DodoPaymentsRoom.value(days: retry.days))"
                       + " · chip=\(DodoPaymentsRoom.retryChip(retry))"
                       + " · pos=" + String(format: "%.2f", DodoPaymentsRoom.position(days: retry.days, span: span)))
        }
        return out
    }
}
