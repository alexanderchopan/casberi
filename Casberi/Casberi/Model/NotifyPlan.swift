import Foundation

/// What a notification IS, before anything schedules it (prd §306).
///
/// Foundation-only and pure by contract — no `UserNotifications`, no UIKit, no
/// store. Everything that decides *whether* something fires, *when* it may be
/// delivered, and *what it says* lives here, so `scripts/notify-selftest.sh`
/// can compile this file WHOLE and check the judgement against fixtures. The
/// impure half (permission, attachments, `UNNotificationRequest`) is
/// `Notifications.swift`, and it makes no decisions.
///
/// The split earns itself the same way `StripeRoom`/`PostHogRoom` do: every
/// failure in this file is a SILENT WRONG NOTIFICATION — a 3am buzz that
/// should have waited for morning, a dispute that never fired, the same like
/// announced eleven times. None of those can be seen in a build, and the
/// simulator never runs a background task at all, so a harness is the only
/// proof these rules hold.

// MARK: - Classes

/// The three classes, and there is no fourth (§306). A class decides
/// interruption, batching and whether quiet hours may hold it.
enum NotifyClass: String, Sendable, CaseIterable {
    /// Something needs you.
    case alarm
    /// Something landed FOR you — money in, attention in.
    case arrival
    /// The once-a-day line, at a time the person picked.
    case whisper
}

/// Every event that may ever notify. The list is CLOSED on purpose: adding a
/// case is the moment to re-read §306's never-fires list, and the harness
/// asserts every case routes to a class and carries a severity.
enum NotifyKind: String, Sendable, CaseIterable {
    // — alarm
    case disputeOpened
    case deadlineNear
    /// A leveraged/borrowed position crossed close to liquidation — Aave,
    /// Morpho and Hyperliquid all land this shape (`WalletDeFi.sync`/
    /// `MorphoDeFi.sync`/`HyperliquidDeFi`'s risk-crossing bucket), and share
    /// ONE kind here because the news is the same regardless of which
    /// protocol: your collateral is close to being sold. (2026-08-09 —
    /// these landed as Things since 2026-07-24/07-30 but were never wired
    /// into `NotifySweep.classify`, so none of them ever reached a lock
    /// screen.)
    case positionAtRisk
    case approvalGranted
    case poolProofNeeded
    case poolCleared
    case paymentsSilent
    case priceRose
    /// App Store Connect turned your release down (2026-08-06, prd §324).
    /// Only the ALARMING verdicts reach here — an approval is welcome news you
    /// will see the moment you open anything, and it already rains in-app.
    case appRejected
    /// A Cursor cloud agent run finished with an ERROR (2026-08-09) — not
    /// Expired/Cancelled, which are administrative outcomes rather than
    /// something having gone wrong. Same wiring gap as `positionAtRisk`: the
    /// row has landed with a "Failed" tag since the bridge shipped, and
    /// nothing ever turned that into a notification.
    case agentRunFailed
    /// A key/balance/quota crossed under its own "about to stop working"
    /// floor — OpenRouter credits, a Bitrefill balance, a Stripe payout
    /// runway, a GitHub API rate limit (2026-08-09). One kind for all four:
    /// each is a different NUMBER but the same shape of news ("do something
    /// before this becomes a problem"), and none of them carries a real
    /// clock the way a Stripe dispute's evidence deadline does.
    case runningLow
    /// A Safe transaction is pending and specifically waiting on the watched
    /// signer's OWN signature (2026-08-11) — tagged "Your turn" at landing
    /// time (`SafeBridge.sync`), never parsed from the title. The clearest
    /// "needs YOU" shape this app has: money is stuck behind a decision only
    /// you can make, and a co-signer's own app has no way to page you.
    /// `approvalGranted` covers a Safe MODULE being enabled instead of a new
    /// kind — that's structurally the same "something new can move your
    /// funds" news an ERC-20 approval carries.
    case safeSignatureNeeded
    /// Walletbeat published a HIGH or CRITICAL security incident that is still
    /// open and names a wallet app the person told us they use (2026-08-20,
    /// prd §422). Every other alarm here is about money that has already moved
    /// or is about to; this one is about the SOFTWARE HOLDING IT, which is the
    /// only alarm in this file nobody else can send — a wallet vendor
    /// disclosing its own vulnerability does not push you a notification, and
    /// the wallet you are about to open is the last place you would look.
    case walletIncident
    /// A DEVNET THIS APP WATCHES WAS RESET (2026-08-29, prd §522).
    ///
    /// Both experimental chains here are relaunched from genesis as a matter
    /// of course, and when it happens every reading the room holds describes a
    /// chain that no longer exists — while the seat renders perfectly, because
    /// all three hosts answer quickly and with nothing. §515a is the user's own
    /// account of finding out: the room read "nothing has landed here", and the
    /// real answer was that the chain had been wiped overnight and every
    /// account needed topping up to redeploy.
    ///
    /// ONE kind for both seats, because the news reads the same whichever chain
    /// it was — the `runningLow` ruling, where four different numbers share a
    /// kind for exactly that reason. The body names the chain; the plan carries
    /// its source, so the right-hand slot carries its mark.
    case chainReset
    /// A vibenet account whose timelock the person ASKED to track has finished
    /// unlocking (2026-08-29, prd §522).
    ///
    /// §473 built the countdown as a Live Activity and stopped there: its
    /// `staleDate` IS the unlock instant, so the tile greys out at exactly the
    /// moment it becomes worth knowing about and nothing ever says the window
    /// opened. The consent is already given — this fires only for an address
    /// somebody turned tracking on for, never for one they merely watch, which
    /// is §473's own ruling carried forward rather than reopened.
    case unlockReady
    // — arrival
    case moneyIn
    case payoutPaid
    case likesReceived
    case repliesReceived
    case followersGained
    // — whisper
    case whisper

    var cls: NotifyClass {
        switch self {
        case .disputeOpened, .deadlineNear, .positionAtRisk, .approvalGranted,
             .poolProofNeeded, .poolCleared, .paymentsSilent, .priceRose,
             .appRejected, .agentRunFailed, .runningLow, .safeSignatureNeeded,
             .walletIncident, .chainReset, .unlockReady:
            return .alarm
        case .moneyIn, .payoutPaid, .likesReceived, .repliesReceived, .followersGained:
            return .arrival
        case .whisper:
            return .whisper
        }
    }

    /// Higher wins when a single sweep turns up more alarms than we will send.
    /// Money you could still lose outranks money that is merely at risk, which
    /// outranks a status flip you can act on whenever. Deliberately NOT the
    /// declaration order — reordering an enum for display is exactly the kind
    /// of edit that would silently re-rank people's alarms.
    var severity: Int {
        switch self {
        case .disputeOpened:    return 100   // money leaving, with a deadline
        case .deadlineNear:     return 90    // a window closing on you
        // Real risk of loss with NO fixed deadline (it could cross the
        // liquidation line on the next block, or never) — ranked just under
        // `deadlineNear` rather than above it, since `isTimeSensitive` below
        // withholds the Focus-breaking level from exactly this shape of
        // urgency (no clock stated), and severity here is about which alarm
        // wins a BATCH, not about how loudly it should ring.
        case .positionAtRisk:   return 85
        // A serious, unresolved flaw in the software holding your keys.
        // ABOVE `approvalGranted` and below `positionAtRisk`, and both
        // boundaries are the ruling: an approval is ONE contract you granted
        // and can revoke in a minute, while this reaches everything in that
        // wallet and there is nothing to revoke — but a position near
        // liquidation is a definite loss on a live price, where this is a
        // disclosed risk that may never be exploited against you.
        case .walletIncident:   return 82
        case .approvalGranted:  return 80    // something CAN take funds
        // Action required, no clock stated — the exact shape of
        // `poolProofNeeded` below, ranked one above it: a Safe signature
        // blocks a specific, already-decided transaction from a co-signer
        // who is waiting on YOU, where a proof request is a compliance step
        // with no other person on the other end of it.
        case .safeSignatureNeeded: return 71
        case .poolProofNeeded:  return 70    // action required, no clock stated
        // Action required and no clock stated — `poolProofNeeded`'s class,
        // ranked just below it because that one is money that could be lost
        // and this is a release that is merely stopped. Above `paymentsSilent`
        // for the opposite reason: silence is a reading we inferred, a
        // rejection is a decision somebody made about you.
        case .appRejected:      return 65
        case .paymentsSilent:   return 60    // revenue stopped; nothing to click
        // A devnet wiped under you. ABOVE `poolCleared` because something is
        // asked of you (accounts redeploy on their next transaction, and until
        // then every reading is of a chain that is gone) and BELOW
        // `paymentsSilent` because no real money is involved either way — a
        // devnet reset must never win a batch against revenue that stopped.
        case .chainReset:       return 55
        case .poolCleared:      return 50    // good news, act whenever
        // `poolCleared`'s exact shape — funds that were held are available
        // again, act whenever — ranked just under it because that one is real
        // money and this is a devnet's timelock.
        case .unlockReady:      return 48
        case .priceRose:        return 40    // recurring money, already charged
        // Something you asked to run did not finish — worth knowing, not
        // urgent: nothing is moving or at risk, a rerun costs a tap.
        case .agentRunFailed:   return 35
        // The lowest alarm on purpose — "do this soon" rather than "something
        // is wrong right now". Ranked under a price rise (money already
        // left, so at least that one is definite) but still a real severity,
        // never the `default: 0` an unlisted alarm would silently fall to
        // and tie with the arrivals it must always outrank in a batch.
        case .runningLow:       return 20
        default:                return 0     // arrivals/whisper never compete
        }
    }

    /// Only a deadline may claim the interruption level that breaks a Focus.
    /// Over-claiming is how a class gets buried by iOS's own summary, so the
    /// two that carry a real clock are the only two that ask —
    /// `positionAtRisk` deliberately withholds it despite the real urgency:
    /// a liquidation proximity has no stated clock, only a live market price.
    var isTimeSensitive: Bool {
        self == .disputeOpened || self == .deadlineNear
    }

    /// The title line — deliberately a small closed set of plain sentences, so
    /// the lock screen reads as one voice rather than eight bridges each
    /// shouting their own noun. The row's own title is the body.
    ///
    /// Lives here rather than in `NotifySweep` (moved 2026-08-29, prd §522) so
    /// there is ONE authority a harness can read: `NotifyDevnet` below composes
    /// whole plans, and a headline it could not reach would have meant a second
    /// copy of three strings in a file no check compiles.
    ///
    /// A headline never repeats what the body already leads with — see
    /// `.appRejected` and `.walletIncident`, both of which say who decided
    /// rather than what was decided.
    var headline: String {
        switch self {
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
        // Names WHAT happened, never which chain — the plan carries its
        // source, so the mark says vibenet or Hegotá, and the body names it in
        // words. One kind, two seats (see `NotifyKind.chainReset`).
        case .chainReset:       return String(localized: "A devnet was reset")
        // THE ROOM'S OWN WORDS ("Ready to unlock" — `VibenetRoom`), not a
        // synonym. A notification that names a state differently from the
        // screen it opens is one you have to translate on arrival.
        case .unlockReady:      return String(localized: "Ready to unlock")
        case .moneyIn:          return String(localized: "Money arrived")
        case .payoutPaid:       return String(localized: "Paid out")
        case .likesReceived:    return String(localized: "Liked your post")
        case .repliesReceived:  return String(localized: "Someone replied")
        case .followersGained:  return String(localized: "New follower")
        case .whisper:          return String(localized: "Your day")
        }
    }
}

// MARK: - A single planned notification

/// One composed, ready-to-schedule notification. Value type, `Sendable`, and
/// deliberately carrying only STRINGS for its imagery — resolving a source
/// name to a bundled asset, or a thing id to stored bytes, is the impure
/// half's job.
struct NotifyPlan: Sendable, Equatable {
    /// Stable and unique per real-world event — this is the dedupe key, and it
    /// is what makes "fires once, ever" true across launches. A Stripe dispute
    /// uses the dispute id; a like batch uses the post's ref, so later likers
    /// REPLACE the pending notification instead of adding to it.
    var id: String
    var kind: NotifyKind
    var title: String
    var body: String
    /// `casberi://…` — where a tap lands. Nil means "just open the app".
    var link: String?
    /// The event's own moment, NOT the delivery moment. Background refresh runs
    /// when iOS feels like it, so the copy must be able to say when a thing
    /// actually happened rather than implying it just did.
    var occurredAt: Date
    /// Set for `deadlineNear`/`disputeOpened` — drives the "3 days" phrasing.
    var deadline: Date?
    /// The source whose mark fills the right-hand slot when no photo can be
    /// had — rung 2 of §306's attachment ladder, and the reason a failed photo
    /// never leaves the slot empty.
    var source: String?
    /// Rung 1: a real photo this thing already holds. `.none` is the normal
    /// case and never a defect — most events have no picture, and §306 forbids
    /// drawing one.
    var art: NotifyArt = .none

    var cls: NotifyClass { kind.cls }
    var isTimeSensitive: Bool { kind.isTimeSensitive }
}

/// Where rung 1's photo comes from, if anywhere. Both cases are REFERENCES, not
/// bytes: this type crosses into the harness, and a plan that carried image
/// data would make every fixture unreadable.
enum NotifyArt: Sendable, Equatable {
    /// A `Thing`'s own `previewImageData` — a screenshot's stored thumbnail.
    case thing(String)
    /// A remote avatar the inbound read already hydrated. Best effort: it is
    /// fetched with a short budget and falls to the source mark if it misses,
    /// because a notification that waits on the network is a notification that
    /// arrives late for no gain.
    case remote(String)
    case none
}

// MARK: - The rules

enum NotifyRules {
    /// A deadline notifies once it is inside three days AND still ahead of us.
    /// Both halves are load-bearing: without the upper bound every dated row in
    /// the corpus alarms at once on first run, and without the `> now` check a
    /// deadline that has already passed alarms forever, which is the worst
    /// possible time to be told about it.
    static let deadlineWindow: TimeInterval = 72 * 3600

    static func deadlineIsNear(_ due: Date, now: Date) -> Bool {
        let delta = due.timeIntervalSince(now)
        return delta > 0 && delta <= deadlineWindow
    }

    /// How many alarms one sweep may actually send. The rest are counted, never
    /// dropped silently — see `collapse`.
    static let alarmsPerSweep = 1

    /// Default quiet window, overridable in settings. Stored as minutes from
    /// midnight so it survives a timezone change without meaning something
    /// different.
    struct Quiet: Sendable, Equatable {
        var startMinute: Int   // 22:00
        var endMinute: Int     // 08:00
        var enabled: Bool

        static let `default` = Quiet(startMinute: 22 * 60, endMinute: 8 * 60, enabled: true)

        /// True while the clock is inside the window. Handles the wrap across
        /// midnight, which is the normal case — a window that does NOT wrap
        /// (say 09:00–17:00) is the unusual one and still has to work.
        func contains(minute: Int) -> Bool {
            guard enabled else { return false }
            if startMinute == endMinute { return false }
            if startMinute < endMinute {           // 09:00 → 17:00, same day
                return minute >= startMinute && minute < endMinute
            }
            return minute >= startMinute || minute < endMinute   // 22:00 → 08:00
        }
    }

    /// When a plan may be delivered. Nil means "now".
    ///
    /// A time-sensitive alarm is never held — that is the entire point of the
    /// level, and iOS's Focus rules already govern it. Everything else that
    /// lands in quiet hours is HELD UNTIL MORNING rather than dropped: the news
    /// keeps, and a like you are told about at 08:00 is still worth having,
    /// while one that wakes you is worth less than nothing.
    static func holdUntil(plan: NotifyPlan, now: Date, quiet: Quiet, calendar: Calendar) -> Date? {
        guard !plan.isTimeSensitive else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard quiet.contains(minute: minute) else { return nil }
        // The next time the clock reads `endMinute`. Adding a day first and
        // then setting the time would land wrong on the morning side of the
        // window (00:30 must wait until 08:00 TODAY, not tomorrow).
        let endHour = quiet.endMinute / 60, endMin = quiet.endMinute % 60
        guard let today = calendar.date(bySettingHour: endHour, minute: endMin, second: 0, of: now) else {
            return nil
        }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// The batching rule (§306), and the reason the feature stays likeable.
    ///
    /// Two groups collapse, for two different reasons. **Alarms** are ranked and
    /// only the worst is sent, with the rest COUNTED into its body: eleven
    /// separate alarms is the thing that makes a person switch notifications
    /// off, and the eleventh is never the one that mattered. **Money arrivals**
    /// collapse too — a wallet can receive several transfers in one window, and
    /// four buzzes for four transfers is the same failure wearing better news.
    /// (Money is also the one place the module doctrine allows a count, because
    /// there the count IS the event.)
    ///
    /// Likes, replies and followers pass through: each already carries a
    /// per-post or per-person id, so a second liker REPLACES that request rather
    /// than joining a queue, and two different people are two different events.
    ///
    /// Ties break on `occurredAt` (newer first) and then on `id`, so the same
    /// sweep always yields the same choice — a sweep that picked differently on
    /// each run would be untestable.
    static func collapse(_ plans: [NotifyPlan]) -> [NotifyPlan] {
        collapseGroup(plans, matching: { $0.cls == .alarm },
                      more: { $0 == 1 ? " And 1 more needs you." : " And \($0) more need you." })
            .pipe { collapseGroup($0, matching: { $0.kind == .moneyIn },
                                  more: { $0 == 1 ? " And 1 more transfer." : " And \($0) more transfers." }) }
    }

    private static func collapseGroup(_ plans: [NotifyPlan],
                                      matching: (NotifyPlan) -> Bool,
                                      more: (Int) -> String) -> [NotifyPlan] {
        let group = plans.filter(matching)
        guard group.count > alarmsPerSweep else { return plans }
        let rest = plans.filter { !matching($0) }
        let ranked = group.sorted { a, b in
            if a.kind.severity != b.kind.severity { return a.kind.severity > b.kind.severity }
            if a.occurredAt != b.occurredAt { return a.occurredAt > b.occurredAt }
            return a.id < b.id
        }
        var lead = ranked[0]
        lead.body += more(ranked.count - 1)
        return [lead] + rest
    }

    /// Plain-words time-to-deadline for the body. Never "in 71 hours".
    static func deadlinePhrase(_ due: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0:  return "overdue"
        case 0:     return "today"
        case 1:     return "tomorrow"
        default:    return "in \(days) days"
        }
    }
}

// MARK: - Fires once, ever

/// The ledger that makes a notification a one-time event.
///
/// Every fire site is inside a sweep that re-reads the same window, so without
/// this a dispute alarms on every background run for as long as it is open.
/// Bounded rather than unbounded: a set that only grows is a set that is one
/// day the reason a launch is slow, and an id old enough to fall off the end is
/// an id whose event is long past re-notifying.
/// Not `Sendable`: it holds a `UserDefaults`, which isn't, and every caller is
/// already `@MainActor`. Conforming would be a Swift 6 error and a claim about
/// thread safety nothing here needs.
struct NotifyLedger {
    static let cap = 500
    private static let key = "notify.fired"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// Ordered oldest→newest, so the prune drops the oldest.
    private var fired: [String] {
        get { defaults.stringArray(forKey: Self.key) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    func hasFired(_ id: String) -> Bool { fired.contains(id) }

    /// Records ids and returns only those NOT seen before, so a caller can
    /// mark-and-filter in one pass without a read/write race between them.
    @discardableResult
    func claim(_ ids: [String]) -> [String] {
        var seen = Set(fired)
        var order = fired
        var fresh: [String] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id); order.append(id); fresh.append(id)
        }
        guard !fresh.isEmpty else { return [] }
        if order.count > Self.cap { order.removeFirst(order.count - Self.cap) }
        fired = order
        return fresh
    }

    /// A batching id must be able to fire AGAIN when its contents change — five
    /// likes then eight likes is new news about the same post. So the ledger is
    /// keyed on id+contents for those, and `release` exists for the one caller
    /// that legitimately re-arms: see `Notifications.likes(...)`.
    func release(_ id: String) {
        fired = fired.filter { $0 != id }
    }

    func reset() { defaults.removeObject(forKey: Self.key) }
}


// MARK: - The two devnets (prd §522)

/// The judgement behind three notifications neither devnet seat could send.
///
/// **WHY THIS IS NOT IN `NotifySweep`.** That file is the one place a LANDED
/// ROW becomes a notification and its own doc says so — but both of these
/// seats fail that premise, from opposite directions. Hegotá lands no `Thing`
/// at all by design (§500: its subject is chain state, not news), so nothing
/// it learns could ever have reached a lock screen and no audit here could
/// report that as a gap. vibenet lands rows, but its two chain-wide facts — a
/// timelock ending, the chain itself being wiped — belong to no row, so the
/// corpus sweep cannot see them either. `Notifications.likes` is the standing
/// precedent for a notification with nothing behind it in the corpus; this is
/// the second, with the same reasoning one gathering step further out.
///
/// **§500 RULED THAT HEGOTÁ DOES NO NOTIFICATIONS, and it is amended in exactly
/// one place.** That rule is about the room's CONTENT — no balance, coin, lane
/// or move is urgent, because the asset is test ETH and nothing can move
/// against you — and it stands whole, attention dots included. A RELAUNCH is
/// not content: it is the statement that every reading the room holds describes
/// a chain that no longer exists, and §515a (two days after §500, so
/// unavailable to it) is a person losing an evening to exactly that on the
/// sibling devnet.
///
/// **A REVERTED FRAME WAS BUILT AND THEN CUT, and the reason generalises.** It
/// is the one thing this chain publishes that no receipt elsewhere can say, so
/// it looks like the strongest case here and is the weakest: §306's own "did
/// you already know?" test settles it, because somebody who just sent a frame
/// transaction on an experimental devnet IS the person building against it —
/// at the desk, in the tooling, probably watching the explorer. Both
/// notifications above have the opposite property: a chain wipe and a timelock
/// ending happen without you and while you are elsewhere. It also could not be
/// acted on (which frame, which mode, what gas — all of that is in the room a
/// notification would only redirect to) and it runs the wrong way on volume,
/// since batching collapses within ONE sweep and a developer's reverts arrive
/// across many.
///
/// **PURE, and in THIS file rather than beside the bridges**, so
/// `scripts/notify-selftest.sh` compiles it WHOLE. Every rule below is a
/// silent wrong notification if it drifts, and nothing in this repo can make
/// a devnet reset, a timelock elapse or a frame revert on demand — so the
/// harness is not the best proof these rules hold, it is the only one.
///
/// **STATED CEILING: none of this reaches the network.** All three read state
/// a FOREGROUND pass already wrote, so the announcement rides the next notify
/// sweep after the seat's own read observed the fact — not the background task,
/// which deliberately drives no bridge refresh (`WalletBackgroundRefresh`'s own
/// budget note). Adding two keyless chain reads to a task measured in seconds
/// would risk the throttle that governs every other alarm in the app, and the
/// facts here keep: a reset stays sayable for a week, a timelock for 36 hours.
enum NotifyDevnet {

    /// The seats, closed. Each carries its own copy so the words live where
    /// the harness can read them.
    ///
    /// **Ethrex Privacy joined in §593d and Ethrex Frames deliberately did
    /// not.** A relaunch is only news about a chain somebody has state on, and
    /// the Privacy seat now makes a key, claims from a faucet and sends — so a
    /// relaunch there really does take something that was somebody's. Frames
    /// has the same claim and no reset detection of its own to feed this, which
    /// is a gap worth closing and not one to close by inventing a signal here.
    enum Seat: String, Sendable, CaseIterable {
        case vibenet, hegota, privacy

        /// **MUST equal `VibenetIdentity.source` / `HegotaIdentity.source` /
        /// `PrivacyDevnetIdentity.source`.**
        /// It routes the deep link and picks the brand mark for the right-hand
        /// slot, and a wrong string fails at neither — the notification arrives
        /// with a blank slot and opens the All feed. Tied to both constants by
        /// a drift guard in `notify-selftest.sh`.
        var source: String {
            switch self {
            case .vibenet: return "Base Vibenet"
            case .hegota:  return "Ethrex Hegotá"
            case .privacy: return "Ethrex Privacy"
            }
        }

        /// `casberi://feed/source/…`, percent-encoded: both names carry a space
        /// and one carries an accent, and an unencoded string is one
        /// `URL(string:)` hands back as nil — a tap that opens the app on
        /// whatever room it was already showing, which reads as the
        /// notification being broken rather than as a bad link.
        var link: String {
            let path = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
            return "casberi://feed/source/" + path
        }
    }

    /// How long after a reset it is still the reason anything looks wrong.
    /// The same week `VibenetSeenChain.sayItFor` keeps saying it in the room —
    /// a notification that outlived that sentence would land somebody in a room
    /// that no longer explains itself.
    static let resetWindow: TimeInterval = 7 * 86_400

    /// How fresh a chain event must be to be news — the same 36 hours
    /// `NotifySweep.newsWindow` gives every landed row, restated because this
    /// file is Foundation-only and that one is not. The harness asserts the two
    /// agree.
    static let newsWindow: TimeInterval = 36 * 3600

    // MARK: A devnet was reset

    struct Reset: Sendable, Equatable {
        var seat: Seat
        /// Unique to THIS reset, so a second relaunch is new news and the same
        /// one is never announced twice. **Never a bare timestamp**: the sticky
        /// record is re-read on every sweep, so a key that moved with the clock
        /// would fire on every pass forever.
        var key: String
        /// When THIS DEVICE observed it — never when the chain restarted, which
        /// we cannot know and must not imply.
        var observedAt: Date
        /// How many addresses are watched on that seat.
        var watching: Int
    }

    static func plan(reset r: Reset, now: Date) -> NotifyPlan? {
        // NOBODY WATCHING, NOTHING TO SAY — a reset is only news about someone
        // who had something on that chain. `VibenetQuiet.emptyRoomNote`'s first
        // guard, for the same reason.
        guard r.watching > 0 else { return nil }
        // Never announce an observation from the future (a clock that moved
        // under us), and never one the room has stopped explaining.
        let age = now.timeIntervalSince(r.observedAt)
        guard age >= 0, age <= resetWindow else { return nil }
        let body: String
        switch r.seat {
        case .vibenet:
            // The half that is easy to get wrong, and the user's own account of
            // it (§515a): the ADDRESS survives. An EIP-8130 account is
            // counterfactual, so it comes back the moment it transacts.
            body = String(localized: "vibenet was reset since you last looked, so its history starts again from here. Your accounts keep their addresses.")
        case .hegota:
            body = String(localized: "Ethrex Hegotá was relaunched from genesis, so everything it held is gone. The addresses you watch are still yours.")
        case .privacy:
            // **THE ROOM'S OWN SENTENCE, WORD FOR WORD.** `PrivacyDevnetRoom
            // .sentence(.relaunched)` says exactly this, and a notification
            // that words it differently lands somebody in a room that appears
            // to be talking about something else.
            body = String(localized: "This devnet was relaunched from genesis, so everything it held is gone. The addresses you watch are still yours.")
        }
        return NotifyPlan(id: "devnet:reset:\(r.seat.rawValue):\(r.key)",
                          kind: .chainReset,
                          title: NotifyKind.chainReset.headline,
                          body: body,
                          link: r.seat.link,
                          occurredAt: r.observedAt,
                          source: r.seat.source)
    }

    // MARK: A timelock finished

    struct Unlock: Sendable, Equatable {
        var address: String
        /// The name the person gave it, or its short form — resolved by the
        /// caller, because a name is app state and this file holds none.
        var name: String
        var unlocksAt: Date
        /// Did somebody turn tracking ON for this address (§473's control)?
        ///
        /// **A FIELD, not an assumption about the caller.** §473's whole ruling
        /// is that an unlock is a thing that happened on the chain, possibly to
        /// an account somebody merely watches, so putting it on their lock
        /// screen because we noticed would be spending the most personal
        /// surface the OS has on something nobody asked about. A caller that
        /// forgot to filter would be indistinguishable from one that did; this
        /// way the rule is asserted rather than trusted.
        var tracked: Bool
    }

    static func plan(unlock u: Unlock, now: Date) -> NotifyPlan? {
        guard u.tracked else { return nil }
        let since = now.timeIntervalSince(u.unlocksAt)
        // Not yet — the Live Activity is still counting, and saying so.
        guard since >= 0 else { return nil }
        // Stale news is not news: a pass that has not run for days must not
        // announce a window that opened last week.
        guard since <= newsWindow else { return nil }
        // The instant is IN THE ID, so a re-locked account that starts a second
        // unlock is announced again while one already told about is not.
        let stamp = Int(u.unlocksAt.timeIntervalSince1970)
        return NotifyPlan(id: "vibenet:unlock:\(u.address.lowercased()):\(stamp)",
                          kind: .unlockReady,
                          title: NotifyKind.unlockReady.headline,
                          // The room's own reading, in its own words.
                          body: String(localized: "\(u.name) finished its timelock on vibenet."),
                          link: Seat.vibenet.link,
                          occurredAt: u.unlocksAt,
                          source: Seat.vibenet.source)
    }

    /// Everything the two devnets have to say, given what their last read left
    /// behind. Order is stable (resets, then unlocks) so a sweep that has to
    /// collapse always collapses the same way; `NotifyRules
    /// .collapse` then keeps the worst alarm and counts the rest, which is what
    /// stops a chain reset that touched four watched addresses being four
    /// buzzes.
    static func plans(resets: [Reset] = [], unlocks: [Unlock] = [],
                      now: Date = Date()) -> [NotifyPlan] {
        resets.compactMap { plan(reset: $0, now: now) }
            + unlocks.compactMap { plan(unlock: $0, now: now) }
    }
}


private extension Array {
    /// Left-to-right chaining, so `collapse` reads as the two passes it is
    /// rather than a nested call that has to be read inside-out.
    func pipe<T>(_ transform: (Self) -> T) -> T { transform(self) }
}