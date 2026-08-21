import Foundation
import SwiftData

/// Reads the corpus and says what deserves a notification (prd §306).
///
/// **Why a sweep rather than a hook in every bridge.** Every event §306 names
/// already lands as a `Thing` — the bridges do that work and this feature adds
/// nothing to it. So the classification lives in ONE file that reads what
/// landed, rather than a call site scattered across eight bridges that each
/// have to remember the rules. The bridges stay unaware notifications exist,
/// which is also what keeps the never-fires list enforceable: this file is the
/// only place that can decide something fires, so the whole decision is
/// reviewable in one screen.
///
/// **Classification is by `sourceRef` PREFIX, never by title.** A title is
/// display copy — several are `String(localized:)`, so matching one would work
/// in English and silently stop classifying anything on a Spanish device, which
/// is a notification that never arrives and no error anywhere. A `sourceRef` is
/// a stable machine key each bridge already builds to dedupe on.
@MainActor
enum NotifySweep {

    /// How far back a landed row may be and still be news. A background pass
    /// that has not run for two days must not announce two days of history at
    /// once — the alerts-are-news doctrine every bridge here already follows
    /// (`SocialInbound.newsWindow`, Privacy Pools §228).
    static let newsWindow: TimeInterval = 36 * 3600

    /// Everything worth telling someone about, given the corpus as it stands.
    /// Pure over its inputs and side-effect free — it does not consult the
    /// ledger and does not schedule; `Notifications.submit` does both, so this
    /// stays trivially re-runnable (which is what `-notifyProbe` needs).
    ///
    /// Returns the plans plus the real photo bytes for any plan whose art is a
    /// `.thing` — resolved here because this is where the models are in hand.
    static func plans(things: [Thing], now: Date = Date()) -> (plans: [NotifyPlan],
                                                               photos: [String: Data]) {
        // Liveness at the boundary (corollary 4): this walks stored properties
        // off every row, and a sweep can run while a bridge heal is deleting.
        let live = things.filter(\.isLive)
        var out: [NotifyPlan] = []
        var photos: [String: Data] = [:]
        let fresh = live.filter { $0.capturedAt > now.addingTimeInterval(-newsWindow) }
        // The wallet apps the person said they use (prd §422). Derived from the
        // corpus rather than passed in, and that is §419's design paying off:
        // the Walletbeat watch IS a `Thing`, so the rows this sweep already
        // holds carry the whole list — no store to read, no parameter to thread
        // down from a caller, and nothing that can be out of date with what the
        // feed is showing.
        let watchedWallets = Set(live.compactMap { WalletbeatWatch.walletID(from: $0) })

        for thing in fresh {
            guard let kind = classify(thing, now: now, watchedWallets: watchedWallets) else { continue }
            guard let id = thing.sourceRef else { continue }
            out.append(NotifyPlan(
                id: "row:" + id,
                kind: kind,
                title: headline(kind),
                body: thing.title,
                link: "casberi://thing/\(thing.id.uuidString)",
                occurredAt: thing.capturedAt,
                deadline: thing.dueAt,
                source: thing.source,
                art: art(for: thing)))
        }

        // Deadlines are a WINDOW scan, not a landing scan — the row that
        // carries a deadline landed whenever it landed, and the news is the
        // clock reaching three days out, which happens on some later day with
        // nothing arriving at all. So this reads the whole live corpus rather
        // than `fresh`, and it is the one class that can fire about an old row.
        for thing in live {
            guard let due = thing.dueAt,
                  NotifyRules.deadlineIsNear(due, now: now) else { continue }
            // The row's OWN id when it carries no `sourceRef`, which is the
            // normal case for anything the person created rather than a bridge
            // landed — a reminder, a calendar event, a note with a date.
            // Requiring a `sourceRef` here (as the landing scan above must,
            // since that is its classification key) silently excluded exactly
            // the rows most likely to carry a real deadline. Caught by
            // `-notifyProbe` reporting `insideDeadlineWindow=1` beside
            // `planned=0` — a bare zero would have looked correct.
            let ref = thing.sourceRef ?? thing.id.uuidString
            // A dispute already alarmed on the day it opened, wearing its own
            // deadline. Alarming again as a generic deadline would be the same
            // news twice in two voices.
            guard classify(thing, now: now, watchedWallets: watchedWallets) != .disputeOpened else { continue }
            let phrase = NotifyRules.deadlinePhrase(due, now: now, calendar: .current)
            out.append(NotifyPlan(
                id: "due:" + ref,
                kind: .deadlineNear,
                title: headline(.deadlineNear),
                body: "\(thing.title) — due \(phrase).",
                link: "casberi://thing/\(thing.id.uuidString)",
                occurredAt: thing.capturedAt,
                deadline: due,
                source: thing.source,
                art: art(for: thing)))
        }

        for plan in out where plan.art != .none {
            if case .thing(let id) = plan.art,
               let match = live.first(where: { $0.id.uuidString == id }),
               let data = match.previewImageData {
                photos[plan.id] = data
            }
        }
        return (out, photos)
    }

    /// Why rows did NOT become plans — for `-notifyProbe` only.
    ///
    /// `planned=0` is the normal, healthy answer for most corpora, and it has
    /// at least four causes: nothing landed inside the news window, nothing
    /// classified, every candidate was dust, or the deadline scan found no row
    /// with a clock. Only one of those is a bug, and a bare zero cannot tell
    /// them apart — the same reason `-kalshiBookProbe` and `-cursorProbe` exist.
    static func skipCensus(things: [Thing], now: Date = Date()) -> [String] {
        let live = things.filter(\.isLive)
        let fresh = live.filter { $0.capturedAt > now.addingTimeInterval(-newsWindow) }
        let received = live.filter { $0.transferDirection == "received" }
        let dusted = received.filter { thing in
            if thing.isFlagged { return true }
            if let usd = thing.transferUSD, usd < WalletIngest.holdingFloor { return true }
            return false
        }
        let dated = live.filter { $0.dueAt != nil }
        // Walletbeat's four gates, counted separately (prd §422). A serious
        // incident that does not alarm is the HEALTHY answer for almost every
        // corpus — most people watch a wallet nothing has happened to — and it
        // has four causes that render as the same silence: nothing watched, the
        // incident names a wallet you do not use, it is resolved, or Walletbeat
        // graded it below high. Only a missing BOOK entry is a bug, so that one
        // is counted apart from the rest.
        let watched = Set(live.compactMap { WalletbeatWatch.walletID(from: $0) })
        let incidents = live.filter { WalletbeatWatch.isNewsRef($0.sourceRef) }
        let booked = incidents.filter { WalletbeatIncidentBook.facts(ref: $0.sourceRef) != nil }
        let serious = booked.filter {
            guard let severity = WalletbeatIncidentBook.facts(ref: $0.sourceRef)?.severity
            else { return false }
            return severity >= .high
        }
        return [
            "live=\(live.count) inNewsWindow=\(fresh.count) (window=\(Int(newsWindow / 3600))h)",
            "walletbeatWatched=\(watched.count) incidents=\(incidents.count) "
                + "withFacts=\(booked.count) highOrCritical=\(serious.count) "
                + "stillOpen=\(booked.filter { WalletbeatIncidentBook.facts(ref: $0.sourceRef)?.status.isOpen == true }.count) "
                + "namingAWatchedWallet=\(booked.filter { t in WalletbeatIncidentBook.facts(ref: t.sourceRef)?.wallets.contains(where: { watched.contains($0) }) == true }.count)",
            "received=\(received.count) filteredAsDust=\(dusted.count) "
                + "(flagged=\(received.filter(\.isFlagged).count) "
                + "belowFloor=\(received.filter { ($0.transferUSD ?? .infinity) < WalletIngest.holdingFloor }.count) "
                + "unpriced=\(received.filter { $0.transferUSD == nil }.count))",
            "withDueAt=\(dated.count) insideDeadlineWindow="
                + "\(dated.filter { NotifyRules.deadlineIsNear($0.dueAt!, now: now) }.count)",
        ]
    }

    /// The one place an event becomes a class. Anything this returns nil for
    /// stays in the feed and waits, which is the normal outcome for the
    /// overwhelming majority of rows.
    /// `watchedWallets` defaults to EMPTY, which means "nothing is watched" and
    /// so declines every Walletbeat incident. That default is deliberate and
    /// fail-safe in the direction that matters: a caller who forgets it gets
    /// silence rather than an alarm about a wallet somebody does not use.
    static func classify(_ thing: Thing, now: Date,
                         watchedWallets: Set<String> = []) -> NotifyKind? {
        guard let ref = thing.sourceRef else { return nil }

        // — Walletbeat: a serious, still-open incident naming a wallet app the
        //   person told us they use (prd §422). Three gates, each load-bearing.
        //
        //   THE FACTS COME FROM THE BOOK, NEVER THE ROW'S TITLE. Severity leads
        //   the title as "Critical · …" / "Serious · …" — both `String(localized:)`,
        //   so matching them would work in English and silently stop alarming on
        //   a Spanish device, which is this file's opening rule. The book holds
        //   Walletbeat's own machine values, and it also holds the FULL wallet
        //   list where the row keeps only `wallets.first` on `authorHandle`, so
        //   an incident naming three wallets is matched against all three.
        //
        //   No book entry means no severity, and that declines: an alarm we
        //   cannot grade is an alarm we have no business sending.
        //
        //   FOLLOWING ALONE NEVER ALARMS. Someone who follows Walletbeat and
        //   watches nothing gets the ecosystem's incidents as feed rows, which
        //   is what they asked for; the right-hand slot is reserved for the
        //   wallet in their own pocket.
        if ref.hasPrefix(WalletbeatNewsParse.refPrefix) {
            guard let facts = WalletbeatIncidentBook.facts(ref: ref),
                  let severity = facts.severity, severity >= .high,
                  facts.status.isOpen,
                  facts.wallets.contains(where: { watchedWallets.contains($0) })
            else { return nil }
            return .walletIncident
        }
        // A rating REVISION never notifies, and this absence is a decision. It
        // is Walletbeat changing its own reading of a wallet — real, worth a
        // row, and not something that happened to you or that asks anything of
        // you. The same test that keeps a card spend quiet.

        // — App Store Connect: a verdict that STOPS a release. The ref carries
        //   the state (`asc:version:<id>:<STATE>` — see `ASCIngest`), so this
        //   reads the decision rather than the title's prose, and only the
        //   alarming ones qualify. An approval deliberately does not notify: it
        //   is welcome news you will see the moment you open anything, it
        //   already rains in-app, and spending the right-hand slot on good news
        //   is what §306 spent a ruling avoiding.
        if ref.hasPrefix("asc:version:") {
            let state = ASCVersionState(rawValue: String(ref.split(separator: ":").last ?? ""))
            return state?.alarming == true ? .appRejected : nil
        }

        // — Wallet: something gained the power to move funds.
        if ref.hasPrefix("wallet:approval:") || ref.hasPrefix("wallet:permit2:") {
            return .approvalGranted
        }
        // — Safe: a pending transaction is specifically waiting on the
        //   watched signer's OWN signature — tagged at landing time
        //   (`SafeBridge.sync`), never parsed from the title. "Waiting on
        //   others" never notifies: nothing is asked of you there.
        if ref.hasPrefix("wallet:safe:"), thing.tags.contains("Your turn") {
            return .safeSignatureNeeded
        }
        // — Safe: a module was enabled that can move this Safe's funds
        //   WITHOUT a signature — the same "something new can move your
        //   funds" news an ERC-20/permit2 approval carries, so it reuses
        //   that kind rather than a near-duplicate. An owner/threshold/guard
        //   change alone doesn't notify (tag absent) — real, but not the
        //   fund-draining-outside-the-threshold shape this file reserves the
        //   right-hand slot for.
        if ref.hasPrefix("wallet:safeconfig:"), thing.tags.contains("Module added") {
            return .approvalGranted
        }
        // — DeFi liquidation proximity (2026-08-09): Aave and Morpho share the
        //   `wallet:defi:` prefix (`WalletDeFi.sync`/`MorphoDeFi.sync`),
        //   Hyperliquid mints its own (`HyperliquidDeFi`'s risk bucket). Both
        //   land ONLY on a fresh crossing already (the bucket-crossing shape
        //   this file's sibling functions use), so nothing here re-filters —
        //   every row landed under either prefix IS the crossing.
        if ref.hasPrefix("wallet:defi:") || ref.hasPrefix("hyperliquid:risk:") {
            return .positionAtRisk
        }
        // — Cursor: a cloud agent run that ended in an ERROR, and only that —
        //   Expired/Cancelled are administrative, not something gone wrong.
        //   Tag-based rather than ref-based (`cursor:agent:<id>` alone can't
        //   say which outcome), the Stripe/Apple-Wallet tag-check shape.
        if ref.hasPrefix("cursor:agent:"), thing.tags.contains("Failed") {
            return .agentRunFailed
        }
        // — Running low: a key/balance/quota crossed under its own floor
        //   (2026-08-09) — OpenRouter credits, a Bitrefill balance, a Stripe
        //   payout runway, a GitHub rate limit. Four different bridges, one
        //   kind, since the news reads the same regardless of which number.
        if ref.hasPrefix("openrouter:credits:low:") || ref.hasPrefix("bitrefill:balance:low:")
            || ref.hasPrefix("stripe:runway:low:") || ref.hasPrefix("github:ratelimit:low:") {
            return .runningLow
        }
        // — Privacy Pools: the two status flips, and only those. A deposit and
        //   a ragequit are things that happened because YOU did them; being
        //   told about your own tap is noise.
        if ref.hasPrefix("privacypools:status:") { return .poolCleared }
        if ref.hasPrefix("privacypools:poi:") { return .poolProofNeeded }

        // — Peer: a FILL is money arriving (2026-08-05, prd §311). You started
        //   the trade, but you did not decide when it settled — an onramp
        //   clears on somebody else's schedule, and "your dollars are now
        //   crypto" is exactly the moment `moneyIn` exists for.
        //
        //   `peer:sell:` is here too and `peer:expired:` deliberately is not:
        //   an expiry means a buyer's payment fell through and your funds went
        //   back where they were — nothing arrived, so nothing is announced,
        //   and the row in the feed is the honest record of it.
        //   ORDER MATTERS: a buy's ref is bare `peer:<intentHash>`, so a
        //   prefix test for it would swallow the other two shapes. Expiry is
        //   ruled out first, by name, and everything else under `peer:` is a
        //   settled trade.
        if ref.hasPrefix("peer:expired:") { return nil }
        if ref.hasPrefix("peer:") { return .moneyIn }

        // — CARD SPENDS ARE NOT NOTIFIED, and this absence is a decision worth
        //   writing down because both card bridges land perfectly good rows
        //   that would fit `moneyIn`'s shape inverted (user's ruling,
        //   2026-08-05). Your bank and your card app already buzz you for
        //   every tap, instantly and reliably. §306's whole discipline is that
        //   the right-hand slot is the only one this app owns, and spending it
        //   to repeat a notification you already get is not service — it is
        //   noise wearing our icon. The spends still land, still rank in the
        //   room's own card-months bars, and still answer an ask.

        // — Social: a named person is an event (the module doctrine's own
        //   phrasing). Likes never reach here — they are counts and never land
        //   as rows; their notification is composed at the read site, where the
        //   NAMES exist. See `Notifications.likes`.
        if thing.socialContext == "follow" { return .followersGained }
        // A reply DOES land as a row (it has words of its own), unlike a like.
        // "recast" and "mention" are deliberately absent: an amplification is
        // not addressed to you, and a mention already reaches the feed as the
        // post it is.
        if thing.socialContext == "reply" { return .repliesReceived }

        // — Apple Wallet, BEFORE the money-in rule below, which would otherwise
        //   claim its refunds.
        //
        //   A refund is stored `transferDirection == "received"` (it is money
        //   coming back) and carries no `transferUSD`, so it takes that rule's
        //   documented "unpriced → notify anyway" path and buzzes "Money
        //   arrived — Refunded · Amazon · $12.00". That rule was written for
        //   wallet transfers, where money received really is news; a refund on
        //   your own card is the reversal of a purchase you already know about,
        //   and §313's ruling that a charge never notifies covers its undoing
        //   for the same reason. So this bridge answers for ALL of its own
        //   rows and never falls through.
        if thing.source == AppleWalletBridge.sourceName {
            // A recurring price that ROSE, and only that. §313's ruling holds
            // and this is its one exception, for the reason the ruling gives:
            // your bank pushed you the charge minutes ago and pushed you
            // nothing about the delta. A subscription quietly costing more
            // every year is money leaving on a decision you never made.
            //
            // Its sibling `Silence` deliberately does NOT fire. A subscription
            // that stopped charging is usually one you cancelled yourself, so
            // announcing it fails the same "did you already know?" test that
            // keeps charges quiet; it lands as a row, which is where a fact you
            // might have forgotten belongs.
            return thing.tags.contains("Price rise") ? .priceRose : nil
        }

        // — Money in. `transferDirection` is the bridge's own stored answer, so
        //   this needs no re-derivation from addresses.
        //
        //   DUST IS NOT NEWS, and this is not a nicety — it is what the feature
        //   is for. `-notifyProbe` on a real corpus planned four separate
        //   "Money arrived" notifications on its first run, for 0.0000 ETH,
        //   0.0010 ETH, 0.0010 USDT0 and 0.0001 USDC.e: dusting, which is a
        //   thing STRANGERS DO TO YOUR WALLET, so an unfiltered rule hands any
        //   passer-by the power to buzz your phone at will. Two gates, and the
        //   flag one matters most: a duster is usually also a spoofed symbol,
        //   and the corpus already knows.
        if thing.transferDirection == "received" {
            if thing.isFlagged { return nil }
            // Priced: the wallet's own dust line, reused rather than invented.
            // Unpriced: fall through and notify — `transferUSD` is nil for
            // every transfer landed before the field existed and whenever
            // Zerion is unreachable, and staying silent about real money
            // because we couldn't price it is the worse failure.
            if let usd = thing.transferUSD, usd < WalletIngest.holdingFloor { return nil }
            return .moneyIn
        }

        // — Stripe. Tags, because `StripeShape` assigns exactly one per event
        //   and they are machine values rather than sentences.
        if thing.source == StripeWatch.source {
            if thing.tags.contains("Silence") { return .paymentsSilent }
            // Opened carries the evidence deadline; closed does not. That is
            // the only persisted difference between the two halves of a
            // dispute, and it is a reliable one — a dispute without a deadline
            // is one Stripe already settled.
            if thing.tags.contains("Dispute") && thing.dueAt != nil { return .disputeOpened }
            // NOT WIRED, deliberately: `payout.paid` and `payout.failed` share
            // the tag "Payout" and differ only in `StripeShape.celebrates`,
            // which is not persisted on the thing — so nothing here can tell an
            // arrival from an alarm, and guessing from the title would be the
            // localized-string trap this file exists to avoid. A payout
            // announced as good news when it FAILED is exactly the §83 fake
            // status, so neither fires until the shape carries a marker.
        }
        return nil
    }

    /// The title line — deliberately a small closed set of plain sentences, so
    /// the lock screen reads as one voice rather than eight bridges each
    /// shouting their own noun. The row's own title is the body.
    static func headline(_ kind: NotifyKind) -> String {
        switch kind {
        case .disputeOpened:    return String(localized: "Money challenged")
        case .deadlineNear:     return String(localized: "Due soon")
        case .positionAtRisk:   return String(localized: "Close to liquidation")
        case .approvalGranted:  return String(localized: "Something new can move your funds")
        case .safeSignatureNeeded: return String(localized: "Your signature is needed")
        // Says the fact the row cannot: that this is YOUR wallet. The body
        // already leads with Walletbeat's own severity word and the incident's
        // own title, so repeating either here would say one thing twice.
        case .walletIncident:   return String(localized: "Security problem in a wallet you use")
        case .poolProofNeeded:  return String(localized: "Privacy Pools needs a response")
        case .poolCleared:      return String(localized: "Clear to withdraw")
        case .paymentsSilent:   return String(localized: "Payments went quiet")
        case .priceRose:        return String(localized: "A subscription went up")
        // Deliberately not "Rejected": the ROW's title already leads with the
        // exact verdict ("Metadata rejected · Casberi 1.4") and rides in the
        // body, so a headline repeating it would say one word twice. This says
        // who decided, which the row doesn't.
        case .appRejected:      return String(localized: "App Review turned it down")
        case .agentRunFailed:   return String(localized: "A Cursor agent run failed")
        case .runningLow:       return String(localized: "Running low")
        case .moneyIn:          return String(localized: "Money arrived")
        case .payoutPaid:       return String(localized: "Paid out")
        case .likesReceived:    return String(localized: "Liked your post")
        case .repliesReceived:  return String(localized: "Someone replied")
        case .followersGained:  return String(localized: "New follower")
        case .whisper:          return String(localized: "Your day")
        }
    }

    /// Rung 1 of the attachment ladder, and it asks only for what a row really
    /// holds. A social row's avatar is remote and already hydrated; a
    /// screenshot's thumbnail is bytes we stored. Everything else declines, and
    /// `Notifications` falls to the source mark.
    private static func art(for thing: Thing) -> NotifyArt {
        if let avatar = thing.authorAvatarURL, !avatar.isEmpty { return .remote(avatar) }
        if thing.previewImageData != nil { return .thing(thing.id.uuidString) }
        return .none
    }
}
