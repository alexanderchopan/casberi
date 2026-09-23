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

/// The two classes, and there is no third (§306; the once-a-day whisper was
/// the third until prd §706 cut it — its tap had led nowhere since §697b, and
/// a line about a day you already scrolled says nothing). A class decides
/// interruption and batching.
enum NotifyClass: String, Sendable, CaseIterable {
    /// Something needs you.
    case alarm
    /// Something landed FOR you — money in, attention in.
    case arrival
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
    /// An app made you a new wallet through Privy (prd §803c). Arrival, not
    /// alarm: usually you just signed in somewhere — and if you did not, the
    /// daily digest is where you notice a wallet you never made.
    case appWalletMade
    /// The one notification a category's news becomes (prd §770): what arrived
    /// for a category that is switched on, delivered once a day.
    /// `NotifySweep.classify` never returns it; only `NotifyDigest.plan`
    /// composes it, and only when the queue holds more than one thing.
    case digest

    var cls: NotifyClass {
        switch self {
        case .disputeOpened, .deadlineNear, .positionAtRisk, .approvalGranted,
             .poolProofNeeded, .poolCleared, .paymentsSilent, .priceRose,
             .appRejected, .agentRunFailed, .runningLow, .safeSignatureNeeded,
             .walletIncident, .chainReset, .unlockReady:
            return .alarm
        case .moneyIn, .payoutPaid, .likesReceived, .repliesReceived, .followersGained, .appWalletMade, .digest:
            return .arrival
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
        default:                return 0     // arrivals never compete
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

    /// The exceptions to the digest (user ruling, prd §770: "time sensitive
    /// can be exceptions"). Everything else waits for the next digest slot, so
    /// these are the four kinds where hours of waiting can cost something the
    /// person cannot get back: money challenged with an evidence clock, a
    /// window closing, collateral close to being sold, and a co-signer blocked
    /// on this person's signature.
    ///
    /// WIDER than `isTimeSensitive` on purpose. That property decides whether
    /// a Focus is pierced, and only a stated clock earns it; this one decides
    /// only whether the news may wait until the evening. A liquidation and a
    /// Safe signature have no clock, but neither keeps until then.
    var standsAlone: Bool {
        switch self {
        case .disputeOpened, .deadlineNear, .positionAtRisk, .safeSignatureNeeded:
            return true
        default:
            return false
        }
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
        case .appWalletMade:    return String(localized: "New app wallet")
        case .digest:           return String(localized: "From your apps")
        }
    }

    /// The kind after a digest title's colon ("Work: App Review said no"),
    /// short enough to follow any place name on one line (prd §881). Like the
    /// headline it says what the row cannot, never the row's own verdict word.
    var brief: String {
        switch self {
        case .disputeOpened:       return String(localized: "money challenged")
        case .deadlineNear:        return String(localized: "due soon")
        case .positionAtRisk:      return String(localized: "near liquidation")
        case .approvalGranted:     return String(localized: "new approval")
        case .safeSignatureNeeded: return String(localized: "sign to continue")
        case .walletIncident:      return String(localized: "security problem")
        case .poolProofNeeded:     return String(localized: "needs a response")
        case .poolCleared:         return String(localized: "clear to withdraw")
        case .paymentsSilent:      return String(localized: "payments went quiet")
        case .priceRose:           return String(localized: "a price went up")
        case .appRejected:         return String(localized: "App Review said no")
        case .agentRunFailed:      return String(localized: "an agent run failed")
        case .runningLow:          return String(localized: "running low")
        case .chainReset:          return String(localized: "devnet reset")
        case .unlockReady:         return String(localized: "ready to unlock")
        case .moneyIn:             return String(localized: "money arrived")
        case .payoutPaid:          return String(localized: "paid out")
        case .likesReceived:       return String(localized: "new likes")
        case .repliesReceived:     return String(localized: "new replies")
        case .followersGained:     return String(localized: "new followers")
        case .appWalletMade:       return String(localized: "new app wallet")
        case .digest:              return String(localized: "updates")
        }
    }

    /// Where a digest holding this kind sits in a scheduled summary. An alarm
    /// keeps its `severity`; an arrival, which `severity` scores 0 so it never
    /// wins an alarm's batch, gets a small rank of its own, every one of them
    /// below the lowest alarm (`runningLow`, 20): money you received before
    /// a new app wallet, before a person answering you, before a like.
    var digestRank: Int {
        if severity > 0 { return severity }
        switch self {
        case .moneyIn, .payoutPaid: return 15
        case .appWalletMade:        return 10
        case .repliesReceived:      return 8
        case .followersGained:      return 5
        case .likesReceived:        return 3
        default:                    return 0
        }
    }

    /// The kind as a counted noun for a digest's title ("5 replies"). Both
    /// forms are spelled out: Foundation's automatic agreement inflects only
    /// the last word it is given, so "2 liked post" is what a runtime noun
    /// gets back (measured, 2026-09-17).
    func counted(_ n: Int) -> String {
        let (one, many): (String, String)
        switch self {
        case .disputeOpened:       (one, many) = (String(localized: "dispute"), String(localized: "disputes"))
        case .deadlineNear:        (one, many) = (String(localized: "deadline"), String(localized: "deadlines"))
        case .positionAtRisk:      (one, many) = (String(localized: "position at risk"), String(localized: "positions at risk"))
        case .approvalGranted:     (one, many) = (String(localized: "approval"), String(localized: "approvals"))
        case .safeSignatureNeeded: (one, many) = (String(localized: "signature needed"), String(localized: "signatures needed"))
        case .walletIncident:      (one, many) = (String(localized: "wallet incident"), String(localized: "wallet incidents"))
        case .poolProofNeeded:     (one, many) = (String(localized: "proof needed"), String(localized: "proofs needed"))
        case .poolCleared:         (one, many) = (String(localized: "withdrawal ready"), String(localized: "withdrawals ready"))
        case .paymentsSilent:      (one, many) = (String(localized: "quiet account"), String(localized: "quiet accounts"))
        case .priceRose:           (one, many) = (String(localized: "price rise"), String(localized: "price rises"))
        case .appRejected:         (one, many) = (String(localized: "rejection"), String(localized: "rejections"))
        case .agentRunFailed:      (one, many) = (String(localized: "failed run"), String(localized: "failed runs"))
        case .runningLow:          (one, many) = (String(localized: "running low"), String(localized: "running low"))
        case .chainReset:          (one, many) = (String(localized: "reset"), String(localized: "resets"))
        case .unlockReady:         (one, many) = (String(localized: "unlock ready"), String(localized: "unlocks ready"))
        case .moneyIn:             (one, many) = (String(localized: "transfer in"), String(localized: "transfers in"))
        case .payoutPaid:          (one, many) = (String(localized: "payout"), String(localized: "payouts"))
        case .likesReceived:       (one, many) = (String(localized: "liked post"), String(localized: "liked posts"))
        case .repliesReceived:     (one, many) = (String(localized: "reply"), String(localized: "replies"))
        case .followersGained:     (one, many) = (String(localized: "new follower"), String(localized: "new followers"))
        case .appWalletMade:       (one, many) = (String(localized: "app wallet"), String(localized: "app wallets"))
        case .digest:              (one, many) = (String(localized: "update"), String(localized: "updates"))
        }
        return n.formatted() + " " + (n == 1 ? one : many)
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
    /// WHERE it happened, in words — the source, or "Your post on X". Drawn as
    /// the notification's subtitle (prd §713), the one slot that stood empty on
    /// every notification for five weeks. Nil is honest and draws nothing.
    var place: String? = nil
    /// The most SPECIFIC bundled mark this event has — a token symbol
    /// ("USDC"), a protocol ("Morpho"), a Safe — resolved through `AssetMark`
    /// ahead of the source's own mark (prd §714). A name with no bundled
    /// asset falls straight through to the source, never to a blank.
    var mark: String? = nil
    /// Who acted and how many dollars moved, when the row knows — carried
    /// into the digest so it can say "linda and 3 more replied" and "+$1,240"
    /// in a line that fits (prd §809).
    var who: String? = nil
    var usd: Double? = nil
    /// The amount as the row says it ("500 USDC"), so a digest can name what
    /// moved without re-parsing a title (prd §881).
    var amount: String? = nil
    /// How many a batched plan counts — everyone who liked a post, named or
    /// not — so a digest can say "45 likes" rather than "3 liked posts".
    var tally: Int? = nil

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

    /// The batching rule (§306), and the reason the feature stays likeable.
    ///
    /// **Alarms** are ranked and only the worst is sent, with the rest COUNTED
    /// into its body: eleven separate alarms is the thing that makes a person
    /// switch notifications off, and the eleventh is never the one that
    /// mattered.
    ///
    /// Since prd §770 only the plans that STAND ALONE reach this (the four
    /// kinds in `NotifyKind.standsAlone`); everything else goes to
    /// `NotifyDigest`. Money arrivals used to collapse here as a second group,
    /// and that group is deleted with the path that fed it, rather than kept
    /// as a rule nothing can reach (§723).
    ///
    /// Ties break on `occurredAt` (newer first) and then on `id`, so the same
    /// sweep always yields the same choice — a sweep that picked differently on
    /// each run would be untestable.
    static func collapse(_ plans: [NotifyPlan]) -> [NotifyPlan] {
        collapseGroup(plans, matching: { $0.cls == .alarm },
                      more: { $0 == 1 ? " And 1 more needs you." : " And \($0) more need you." })
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

    /// The event's own time, in words, for the subtitle — and ONLY when
    /// delivery lags it (prd §713). iOS stamps every banner with the moment it
    /// was delivered, and **iOS decides when the background task runs**, so an
    /// event found hours late reads "now" — and the settings footer had promised
    /// for five weeks that "each says when the thing happened, not when it
    /// arrived" while nothing rendered `occurredAt` at all. Inside an hour the OS's own stamp is close
    /// enough and this is nil; past a week the hour is noise and only the date
    /// is said. Composed from twelve-hour numerals and a period word so it
    /// reads the same in a 24-hour locale without an AM/PM it never shows.
    static let datelineLag: TimeInterval = 3600

    static func datelinePhrase(occurredAt: Date, deliveredAt: Date, calendar: Calendar) -> String? {
        guard deliveredAt.timeIntervalSince(occurredAt) >= datelineLag else { return nil }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: occurredAt),
                                           to: calendar.startOfDay(for: deliveredAt)).day ?? 0
        let c = calendar.dateComponents([.hour, .minute], from: occurredAt)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        let clock = "\((hour + 11) % 12 + 1):" + String(format: "%02d", minute)
        let period: String
        switch hour {
        case ..<12: period = String(localized: "morning")
        case ..<17: period = String(localized: "afternoon")
        case ..<21: period = String(localized: "evening")
        default:    period = String(localized: "night")
        }
        switch days {
        case 0:
            return hour >= 21
                ? String(localized: "tonight at \(clock)")
                : String(localized: "this \(period) at \(clock)")
        case 1:
            return hour >= 21
                ? String(localized: "last night at \(clock)")
                : String(localized: "yesterday \(period) at \(clock)")
        case 2...6:
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = calendar.locale ?? .current
            f.dateFormat = "EEEE"
            let weekday = f.string(from: occurredAt)
            return String(localized: "\(weekday) \(period) at \(clock)")
        default:
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = calendar.locale ?? .current
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: occurredAt)
        }
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
    /// **Ethrex Privacy joined in §593d, and Hegotá Frames in §728.** A
    /// relaunch is only news about a chain somebody has state on, and both
    /// seats make a key, claim from a faucet and send — so a relaunch there
    /// really does take something that was somebody's. Frames waited until it
    /// had reset detection of its own to feed this (a stored genesis baseline,
    /// `FramesChainWatch.verdict`), rather than a signal invented here.
    ///
    /// **A STALL IS NOT ANNOUNCED.** It takes nothing, it ends by itself, and
    /// nothing a notification could lead to would change it — §306's "can it
    /// be acted on", failed. The room says it instead.
    enum Seat: String, Sendable, CaseIterable {
        case vibenet, hegota, privacy, frames

        /// **MUST equal `VibenetIdentity.source` / `HegotaIdentity.source` /
        /// `PrivacyDevnetIdentity.source`.**
        /// It routes the deep link and picks the brand mark for the right-hand
        /// slot, and a wrong string fails at neither — the notification arrives
        /// with a blank slot and opens the All feed. Tied to both constants by
        /// a drift guard in `notify-selftest.sh`.
        var source: String {
            switch self {
            case .vibenet: return "Base Vibenet"
            case .hegota:  return "Hegotá UTXO"
            case .privacy: return "Hegotá Privacy"
            case .frames:  return "Hegotá Frames"
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
            body = String(localized: "Hegotá UTXO was relaunched from genesis, so everything it held is gone. The addresses you watch are still yours.")
        case .privacy:
            // **THE ROOM'S OWN SENTENCE, WORD FOR WORD.** `PrivacyDevnetRoom
            // .sentence(.relaunched)` says exactly this, and a notification
            // that words it differently lands somebody in a room that appears
            // to be talking about something else.
            body = String(localized: "This devnet was relaunched from genesis, so everything it held is gone. The addresses you watch are still yours.")
        case .frames:
            body = String(localized: "Hegotá Frames was relaunched from genesis, so everything it held is gone. Your key and the addresses you watch are still yours.")
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
    /// collapse always collapses the same way. Neither kind stands alone
    /// (prd §770), so both wait for the digest, which is what stops a chain
    /// reset that touched four watched addresses being four buzzes.
    static func plans(resets: [Reset] = [], unlocks: [Unlock] = [],
                      now: Date = Date()) -> [NotifyPlan] {
        resets.compactMap { plan(reset: $0, now: now) }
            + unlocks.compactMap { plan(unlock: $0, now: now) }
    }
}


// MARK: - The digest (prd §770)

/// Everything that does not stand alone arrives as ONE notification per
/// category, once a day, all at the same slot (user ruling, prd §770: "we
/// aren't trying to be someone's notification app, we are for them reading the
/// app, and their notifications are really the problem for users today";
/// amended the same day to "one per category a day"). Arriving together, they
/// are one moment and one stack in Notification Center.
///
/// **Counts and app names, never a summary.** The daily whisper (§706) was cut
/// because its line summarised a day and said nothing; this says only which
/// apps have something and how much, which nothing can get wrong.
///
/// **Fixed slots, not a timer.** A local notification's content is frozen when
/// it is scheduled and the background task runs when iOS decides, so the
/// digest is one pending request per slot that every sweep REWRITES with the
/// queue as it stands. Whatever reached the queue before the last sweep ahead
/// of a slot is in that slot's notification. Once the slot has passed, iOS has
/// delivered it, so the next sweep starts an empty queue. Nothing here needs
/// the app to be running at 18:00.
///
/// Pure, like the rest of this file, so `notify-selftest.sh` drives the slot
/// choice, the queue's lifecycle and the words.
enum NotifyDigest {

    /// One thing waiting for the next slot. Carries strings only, the way
    /// `NotifyPlan` does, because it is stored between sweeps.
    struct Item: Codable, Sendable, Equatable {
        /// The plan's own id, so a like that grows REPLACES its queued item.
        var id: String
        /// The catalog seat, resolved by the caller through
        /// `BridgeCatalog.seatName(forSource:)`: what groups items into apps
        /// and what `hasOwnApp` is keyed on.
        var seat: String
        /// The words a person reads for that app, the landed source.
        var name: String
        /// The catalog category, for the per-category switch.
        var category: String
        /// `NotifyKind.rawValue`, so a lone item keeps its own kind.
        var kind: String
        var title: String
        var body: String
        var link: String?
        var occurredAt: Date
        var source: String?
        /// The picture the plan carried (`NotifyArt.remote`): a person's face
        /// on a reply or a like, a cover on a link. Optional with a default,
        /// so a queue stored before it decodes unchanged.
        var picture: String? = nil
        /// The plan's own bundled mark (`NotifyPlan.mark`): USDC on a
        /// transfer, Morpho on a position.
        var mark: String? = nil
        /// Who acted, when the row names a person (`Thing.authorHandle`): the
        /// replier, the new follower, the lead liker. What lets a digest say
        /// "linda, jesse and 3 more replied" in one line instead of pasting
        /// three replies that each run past the edge.
        var who: String? = nil
        /// The money a transfer moved, in dollars, when the row knows it
        /// (`Thing.transferUSD`). A digest sums it only when EVERY money item
        /// carries one; a partial sum would state a total that is not.
        var usd: Double? = nil
        /// `NotifyPlan.amount` and `.tally` (prd §881). Optional with a
        /// default, so a queue stored before them decodes unchanged.
        var amount: String? = nil
        var tally: Int? = nil

        /// The words this item adds to a digest's list. A row the sweep landed
        /// carries its KIND's fixed headline as its title ("Someone replied")
        /// and the actual news in its body, so a list of titles read "Someone
        /// replied" three times and never said who or what. A title the plan
        /// wrote itself ("Liked by linda and 4 others") is the news, and stays.
        var line: String {
            let generic = NotifyKind(rawValue: kind).map { $0.headline == title } ?? false
            return generic && !body.isEmpty ? body : title
        }
    }

    /// One square in a category digest's thumbnail: a picture (usually a
    /// face), or a bundled mark. They mix (user, 2026-09-15: "mixed together
    /// is fine avatars and faces").
    enum Tile: Sendable, Equatable {
        case picture(url: String, source: String?)
        case mark(String)
    }

    /// Four tiles fill the thumbnail's 2×2 grid; a fifth would be too small to
    /// read at the size iOS draws it.
    static let tileCap = 4

    /// What a category's digest draws, newest first: each item's picture when
    /// it has one, otherwise its own mark, otherwise its app's. The same
    /// picture or mark is drawn once, so three Stripe payouts are ONE Stripe
    /// tile and leave room for the rest.
    static func tiles(_ group: [Item]) -> [Tile] {
        var seen = Set<String>(), out: [Tile] = []
        for item in newestFirst(group) {
            let tile: Tile, key: String
            if let picture = item.picture, !picture.isEmpty {
                tile = .picture(url: picture, source: item.source); key = picture
            } else {
                let mark = item.mark ?? item.seat
                tile = .mark(mark); key = "mark:" + mark
            }
            guard seen.insert(key).inserted else { continue }
            out.append(tile)
            if out.count == tileCap { break }
        }
        return out
    }

    // MARK: - Words that fit (prd §809)

    /// What fits on one line without iOS cutting it with an ellipsis, in
    /// characters (user, 2026-09-17: "no truncation ellipsis in the title or
    /// the bodies"). Measured against the lock screen's own geometry: a
    /// 390pt phone leaves about 228pt for a title at 15pt semibold beside the
    /// icon, the time and the thumbnail, and about 240pt for a body line.
    /// Characters are an ESTIMATE of width, so both are set below the
    /// average: a line of wide letters can still reach the edge.
    static let titleBudget = 28
    static let lineBudget = 32
    /// The unlocked banner shows two body lines, Notification Center four;
    /// two is the count that is whole on both.
    static let bodyLineCap = 2

    /// The first candidate that fits, or the last one, which every caller
    /// makes short enough to fit on its own.
    static func fitted(_ candidates: [String?], budget: Int) -> String {
        let present = candidates.compactMap { $0 }.filter { !$0.isEmpty }
        return present.first { $0.count <= budget } ?? present.last ?? ""
    }

    /// The dollars that arrived, when every money item says how much. Nil
    /// if any one does not: a sum of the ones we know is not the total.
    static func moneyTotal(_ items: [Item]) -> Double? {
        let money = items.filter { $0.kind == NotifyKind.moneyIn.rawValue || $0.kind == NotifyKind.payoutPaid.rawValue }
        guard !money.isEmpty, money.allSatisfy({ $0.usd != nil }) else { return nil }
        let total = money.reduce(0) { $0 + ($1.usd ?? 0) }
        return total > 0 ? total : nil
    }

    static func dollars(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD").precision(.fractionLength(usd >= 100 ? 0 : 2)))
    }

    // MARK: - What a digest says, most urgent first (prd §881)

    /// One thing a digest can state. A digest used to rank what it said by
    /// how MANY of each kind arrived, so an App Review rejection sat behind
    /// "And 2 more" under a payout, an approval that can move your funds sat
    /// under the money total, and a reply asking you a question sat under
    /// nine like counts — each line restating its kind's verb ("Liked by",
    /// "Received") beneath a title that had already said it (user,
    /// 2026-09-22: "they repeat words like 'wallet' or 'liked'").
    ///
    /// Now a digest reads in three tiers, by `NotifyKind.digestRank`: what
    /// needs you (every alarm that waits for the evening, each one its own
    /// fact, never folded into a count), the money that moved (one fact: the
    /// total and WHO sent it), then people (a reply keeps its words because
    /// you may answer it; follows name the people; likes are one number).
    /// The title is the lead fact; the body is what the title left out, then
    /// the next facts; no line repeats the title's verb.
    struct Fact: Sendable, Equatable {
        var kind: NotifyKind
        var items: [Item]
        var rank: Int
        /// What follows "Place: " when this fact is the title, best first.
        var leads: [String]
        /// What that title leaves out: the specifics under it. Nil when the
        /// title already says it all.
        var detail: String?
        /// The fact on a body line of its own, best first.
        var lines: [String]
        /// The fact as one clause of a shared line ("45 likes").
        var brief: String
    }

    /// What arrived, grouped by kind, most first; ties by kind name so the
    /// order never depends on a dictionary's.
    static func byKind(_ items: [Item]) -> [(kind: NotifyKind, items: [Item])] {
        var groups: [String: [Item]] = [:]
        for item in newestFirst(items) { groups[item.kind, default: []].append(item) }
        return groups
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { (NotifyKind(rawValue: $0.key) ?? .digest, $0.value) }
    }

    private static func isMoney(_ kind: NotifyKind) -> Bool { kind == .moneyIn || kind == .payoutPaid }

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// "linda, jesse and 43 more", shrinking the names until one is left.
    /// `total` counts everyone, named or not, so a like tally of 45 with two
    /// names on hand says "and 43 more", never "and 0 more".
    static func listed(_ people: [String], total: Int) -> [String] {
        guard !people.isEmpty else { return [] }
        return (1...min(3, people.count)).reversed().map { k in
            let shown = Array(people.prefix(k)), rest = max(total, people.count) - k
            return rest > 0
                ? shown.joined(separator: ", ") + " " + String(localized: "and \(rest) more")
                : ListFormatter.localizedString(byJoining: shown)
        }
    }

    /// "linda, jesse and 3 more replied", shrinking the names until it fits.
    static func named(_ people: [String], verb: String) -> [String] {
        listed(people, total: people.count).map { $0 + " " + verb }
    }

    /// Everyone who acted, newest first, each once.
    private static func people(_ items: [Item]) -> [String] {
        var out: [String] = []
        for who in newestFirst(items).compactMap(\.who) where !out.contains(who) { out.append(who) }
        return out
    }

    /// "45 likes": what `NotifyPlan.tally` counted, or one per item without it.
    private static func likes(_ n: Int) -> String {
        n.formatted() + " " + (n == 1 ? String(localized: "like") : String(localized: "likes"))
    }

    /// Every fact the items state, most urgent first: by `digestRank`, then an
    /// app with no lock screen of its own ahead of one that has, then the
    /// newest. `multi` is a digest of several apps, where money with no
    /// sender says which app paid it.
    static func facts(_ items: [Item]) -> [Fact] {
        let order = apps(items)
        let multi = order.count > 1
        var out: [Fact] = []
        var money: [Item] = []
        for group in byKind(items) {
            let kind = group.kind, all = group.items
            if isMoney(kind) { money += all; continue }
            let n = all.count, counted = kind.counted(n)
            switch kind {
            case _ where kind.cls == .alarm:
                // Each thing that needs you is its own fact: two approvals are
                // two decisions, and a count would hide which.
                for item in all {
                    out.append(Fact(kind: kind, items: [item], rank: kind.digestRank,
                                    leads: [kind.brief], detail: item.line,
                                    lines: [item.line, capitalized(kind.brief)], brief: capitalized(kind.brief)))
                }
            case .repliesReceived:
                // A question waits on you; of several replies, one asking
                // something is the one worth the line.
                let pick = all.first { $0.line.contains("?") } ?? all[0]
                let who = people(all)
                let said = pick.who.map { $0 + ": " + pick.line }
                let one = n == 1 ? pick.who.map { $0 + " " + String(localized: "replied") } : nil
                out.append(Fact(kind: kind, items: all, rank: kind.digestRank,
                                leads: [one, counted].compactMap { $0 },
                                detail: fitted(n == 1 ? [pick.line] : [said] + listed(who, total: n).map {
                                    String(localized: "From \($0)") }, budget: lineBudget),
                                lines: [said].compactMap { $0 } + named(who, verb: String(localized: "replied"))
                                    + [capitalized(counted)],
                                brief: one ?? capitalized(counted)))
            case .followersGained:
                let who = people(all)
                let named = named(who, verb: String(localized: "followed you"))
                out.append(Fact(kind: kind, items: all, rank: kind.digestRank,
                                leads: n == 1 ? named + [counted] : [counted],
                                detail: n == 1 ? nil : listed(who, total: n).first { $0.count <= lineBudget },
                                lines: named + [capitalized(counted)],
                                brief: n == 1 ? (named.first ?? capitalized(counted)) : capitalized(counted)))
            case .likesReceived:
                let tally = all.reduce(0) { $0 + max($1.tally ?? 1, 1) }
                let who = people(all)
                let verb = n == 1 ? String(localized: "liked your post") : String(localized: "liked your posts")
                out.append(Fact(kind: kind, items: all, rank: kind.digestRank,
                                leads: [likes(tally)],
                                detail: listed(who, total: tally).map { String(localized: "From \($0)") }
                                    .first { $0.count <= lineBudget },
                                lines: listed(who, total: tally).map { $0 + " " + verb } + [capitalized(likes(tally))],
                                brief: capitalized(likes(tally))))
            default:
                let lone = n == 1 && all[0].line != kind.headline ? all[0].line : nil
                out.append(Fact(kind: kind, items: all, rank: kind.digestRank,
                                leads: n == 1 && kind == .appWalletMade
                                    ? [String(localized: "new app wallet"), counted] : [counted],
                                detail: n == 1 ? lone : nil,
                                lines: [lone.map { n == 1 && kind == .appWalletMade
                                    ? String(localized: "New app wallet: \($0)") : $0 }, lone,
                                        capitalized(counted)].compactMap { $0 },
                                brief: capitalized(counted)))
            }
        }
        let appRank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        if !money.isEmpty { out.append(moneyFact(money, multi: multi, appRank: appRank)) }
        func appOf(_ f: Fact) -> Int { f.items.map { appRank[$0.name] ?? .max }.min() ?? .max }
        func newest(_ f: Fact) -> Date { f.items.map(\.occurredAt).max() ?? .distantPast }
        return out.sorted { a, b in
            if a.rank != b.rank { return a.rank > b.rank }
            if appOf(a) != appOf(b) { return appOf(a) < appOf(b) }
            if newest(a) != newest(b) { return newest(a) > newest(b) }
            return a.kind.rawValue < b.kind.rawValue
        }
    }

    /// The money that moved, as one fact: the total when every transfer is
    /// priced, and who sent it, largest first. The sender is the news; "3
    /// transfers in" under "+$1,240" said nothing the title had not.
    private static func moneyFact(_ items: [Item], multi: Bool, appRank: [String: Int]) -> Fact {
        // Largest first; between equals, an app with no lock screen of its own
        // first, then the newest.
        let sorted = items.sorted { a, b in
            if (a.usd ?? -1) != (b.usd ?? -1) { return (a.usd ?? -1) > (b.usd ?? -1) }
            let ra = appRank[a.name] ?? .max, rb = appRank[b.name] ?? .max
            if ra != rb { return ra < rb }
            return (a.occurredAt, a.id) > (b.occurredAt, b.id)
        }
        let kind: NotifyKind = sorted.allSatisfy { $0.kind == NotifyKind.payoutPaid.rawValue } ? .payoutPaid : .moneyIn
        let counted = kind.counted(items.count)
        let total = moneyTotal(items).map { "+" + dollars($0) }
        // Who sent it: the counterparty, or — in a digest of several apps —
        // the app that paid, so "+$1,820" never stands without a source.
        let sender: (Item) -> String? = { $0.who ?? (multi ? $0.name : nil) }
        var senders: [String] = []
        for s in sorted.compactMap(sender) where !senders.contains(s) { senders.append(s) }
        let from: [String] = senders.isEmpty ? [] : (1...min(3, senders.count)).reversed().map { k in
            let shown = Array(senders.prefix(k))
            let rest = sorted.filter { !shown.contains(sender($0) ?? "") }.count
            return rest > 0
                ? shown.joined(separator: ", ") + " " + String(localized: "and \(rest) more")
                : ListFormatter.localizedString(byJoining: shown)
        }
        // With no sender, the amounts themselves, largest first.
        let amounts = sorted.compactMap(\.amount)
        let moved: [String] = amounts.count == sorted.count && !amounts.isEmpty
            ? (1...min(3, amounts.count)).reversed().map { k in
                let rest = amounts.count - k
                return amounts.prefix(k).joined(separator: ", ")
                    + (rest > 0 ? " " + String(localized: "and \(rest) more") : "")
            } : []
        let detail = fitted(from.map { String(localized: "From \($0)") } + moved + [nil], budget: lineBudget)
        let lines: [String] = total.map { t in
            from.map { t + " " + String(localized: "from \($0)") } + (items.count > 1 ? [t + " · " + counted] : []) + [t]
        }
            ?? (from.map { capitalized(counted) + " " + String(localized: "from \($0)") } + [capitalized(counted)])
        return Fact(kind: kind, items: sorted, rank: kind.digestRank,
                    leads: [total, counted].compactMap { $0 },
                    detail: detail.isEmpty || detail.count > lineBudget ? nil : detail,
                    lines: lines, brief: total ?? capitalized(counted))
    }

    /// The title of a digest of several things: the place, a colon, and its
    /// most urgent fact (`facts`).
    static func title(place: String, _ items: [Item]) -> String {
        let leads = facts(items).first?.leads ?? []
        return fitted(leads.map { place + ": " + $0 } + [place + ": " + String(localized: "\(items.count) new")],
                      budget: titleBudget)
    }

    /// A fact's own body line. In a digest of several apps a line names its
    /// app when it fits, so "+$1,820" says Stripe paid it.
    private static func line(_ fact: Fact, multi: Bool) -> String {
        let apps = Set(fact.items.map(\.name))
        guard multi, apps.count == 1, let app = apps.first else { return fitted(fact.lines, budget: lineBudget) }
        // Each line with its app when it does not already say it, then bare.
        let named = fact.lines.map { $0.contains(app) || $0.contains(": ") ? $0 : app + ": " + $0 }
        return fitted(zip(named, fact.lines).flatMap { [$0, $1] }, budget: lineBudget)
    }

    /// The body of a digest of several things, never more than `bodyLineCap`
    /// lines and never one that runs past the edge: what the title left out,
    /// then the next facts, most urgent first. Facts past the cap share the
    /// last line as clauses ("vitalik followed you · 45 likes"), and whatever
    /// even that cannot hold is counted.
    static func body(_ items: [Item]) -> String {
        let all = facts(items)
        guard let lead = all.first else { return "" }
        let multi = apps(items).count > 1
        var lines: [String] = []
        if let detail = lead.detail, detail.count <= lineBudget,
           !lead.leads.contains(where: { $0 == detail }) {
            lines.append(detail)
        }
        let rest = Array(all.dropFirst())
        // A lead with nothing to add and nothing after it: its things' own
        // words, when each fits, otherwise the newest and how many more.
        if lines.isEmpty, rest.isEmpty {
            // `items` is already the fact's order: newest first, and money
            // largest first, so its first line is the one worth keeping.
            let own = lead.items.map(\.line)
            if own.count <= bodyLineCap, own.allSatisfy({ $0.count <= lineBudget }) {
                return own.joined(separator: "\n")
            }
            let first = own.first ?? ""
            return fitted([first + " " + String(localized: "and \(own.count - 1) more"),
                           isMoney(lead.kind) ? String(localized: "Largest: \(first)") : nil, ""],
                          budget: lineBudget)
        }
        let room = bodyLineCap - lines.count
        guard rest.count > room else { return (lines + rest.map { line($0, multi: multi) }).joined(separator: "\n") }
        lines += rest.prefix(room - 1).map { line($0, multi: multi) }
        let left = Array(rest.dropFirst(room - 1))
        let shared: [String] = (1...left.count).reversed().map { k in
            let unsaid = left.dropFirst(k).reduce(0) { $0 + $1.items.count }
            return left.prefix(k).map(\.brief).joined(separator: " · ")
                + (unsaid > 0 ? " · " + String(localized: "\(unsaid) more") : "")
        }
        let unsaid = left.reduce(0) { $0 + $1.items.count }
        lines.append(fitted(shared + [String(localized: "And \(unsaid) more")], budget: lineBudget))
        return lines.joined(separator: "\n")
    }

    // MARK: - The card (prd §809, §881)

    /// How many rows the long press draws. The banner shows two lines; the
    /// card is where the rest of the day is read.
    static let cardRowCap = 8

    /// The card's rows and the item whose face leads each, in the banner's
    /// order: a row per thing that needs you, per transfer (who sent it, then
    /// how much, largest first) and per reply (who, then the words); ONE row
    /// for the day's follows and ONE for its likes, because a row per liked
    /// post read "Liked by linda and 4 others" down the card and said
    /// nothing the banner had not (prd §881).
    static func cardEntries(_ group: [Item]) -> [(item: Item, row: NotifyCard.Row)] {
        var out: [(item: Item, row: NotifyCard.Row)] = []
        func row(_ item: Item, who: String?, line: String) -> NotifyCard.Row {
            NotifyCard.Row(app: item.name, who: who, line: line, at: item.occurredAt, link: item.link,
                           face: nil, round: !(item.picture ?? "").isEmpty)
        }
        for fact in facts(group) {
            switch fact.kind {
            case .likesReceived:
                // The app leads, not a liker: "linda — 45 likes" would read as
                // linda's doing. Her face stays out for the same reason.
                var lead = fact.items[0]; lead.picture = nil
                let posts = fact.items.count
                let tally = fact.items.reduce(0) { $0 + max($1.tally ?? 1, 1) }
                let on = posts == 1 ? String(localized: "on your post") : String(localized: "on \(posts) posts")
                let who = listed(people(fact.items), total: tally).first
                out.append((lead, row(lead, who: nil, line: likes(tally) + " " + on + (who.map { " · " + $0 } ?? ""))))
            case .followersGained:
                let who = people(fact.items)
                let lead = fact.items.first { $0.who == who.first } ?? fact.items[0]
                let line = who.count > 1
                    ? String(localized: "and \(fact.items.count - 1) more followed you")
                    : String(localized: "followed you")
                out.append((lead, row(lead, who: who.first, line: line)))
            case .moneyIn, .payoutPaid:
                for item in fact.items {
                    let worth = item.usd.map(dollars)
                    let line = item.who == nil ? item.line
                        : [item.amount, worth].compactMap { $0 }.joined(separator: " · ")
                    out.append((item, row(item, who: item.who, line: line.isEmpty ? item.line : line)))
                }
            default:
                for item in fact.items { out.append((item, row(item, who: item.who, line: item.line))) }
            }
        }
        return Array(out.prefix(cardRowCap))
    }

    /// The long press's card for a digest of several things. Nil for one
    /// thing: a lone item's long press is its own picture, as before. Faces
    /// and the head are left nil here; the scheduler writes the files.
    static func card(_ group: [Item]) -> NotifyCard? {
        guard group.count > 1, let plan = plan(group) else { return nil }
        return NotifyCard(title: plan.title, head: nil, rows: cardEntries(group).map(\.row))
    }

    /// The digest's rank among the day's notifications, for the scheduled
    /// summary: the most urgent thing it holds, not the digest kind's own
    /// flat score, so a Wallet digest with a transfer leads a Social one with
    /// a like.
    static func relevance(_ group: [Item]) -> Double {
        let top = group.compactMap { NotifyKind(rawValue: $0.kind)?.digestRank }.max() ?? 0
        return Double(top) / 100
    }

    // MARK: - The reading hour

    /// The evening the slot may move within. Every settings string says "each
    /// evening", so the learned hour never leaves it.
    static let readingWindow = (17 * 60)...(21 * 60)

    /// How far back an open counts, and how many evenings it takes to trust a
    /// habit. Fewer and a single late night would move the digest.
    static let readingLookback: TimeInterval = 14 * 86_400
    static let readingDaysNeeded = 3

    /// The slot the digest is scheduled for: half an hour before the person
    /// usually first opens the app in the evening, so it is waiting when they
    /// look, rounded down to the quarter hour and kept inside
    /// `readingWindow`. Each evening counts once, by its FIRST open, because a
    /// person who opens the app five times after dinner has one reading hour,
    /// not five. Too few evenings, and the fixed `slots` stand.
    static func readingSlots(opens: [Date], now: Date, calendar: Calendar) -> [Int] {
        var firstByDay: [Date: Int] = [:]
        for open in opens where open <= now && now.timeIntervalSince(open) <= readingLookback {
            let parts = calendar.dateComponents([.hour, .minute], from: open)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            guard (16 * 60)..<(22 * 60) ~= minute else { continue }
            let day = calendar.startOfDay(for: open)
            firstByDay[day] = min(firstByDay[day] ?? .max, minute)
        }
        guard firstByDay.count >= readingDaysNeeded else { return slots }
        let sorted = firstByDay.values.sorted()
        let median = sorted[sorted.count / 2]
        let slot = ((median - 30) / 15) * 15
        return [min(max(slot, readingWindow.lowerBound), readingWindow.upperBound)]
    }

    /// Newest first, ties by id, so neither the rows nor the lines depend on
    /// the queue's stored order.
    private static func newestFirst(_ items: [Item]) -> [Item] {
        items.sorted { $0.occurredAt != $1.occurredAt ? $0.occurredAt > $1.occurredAt : $0.id < $1.id }
    }

    /// What survives between sweeps: the queue, and the slot it is scheduled
    /// for. A nil slot means nothing is pending.
    struct State: Codable, Sendable, Equatable {
        var queue: [Item] = []
        var slot: Date?
    }

    /// Minutes from midnight. One, and the count is the ruling ("one per
    /// category a day"): an evening read, once the day's news is in. Every
    /// slot this file can choose lives inside `readingWindow` (17:00 to
    /// 21:00), so a digest can never land at night — which is why the app
    /// needs no night rule of its own (prd §870).
    static let slots = [18 * 60]

    /// A bound on the queue, oldest dropped first. One slot a day and a
    /// ledger that fires each id once keep it far below this; it exists so a
    /// week without a sweep cannot grow a stored array without limit.
    static let cap = 200

    /// Seats whose own iOS app already pushes the person about what Casberi
    /// reads from them. They are named AFTER the seats that have no lock
    /// screen of their own (a watched wallet, a feed, a devnet), because that
    /// is news the person cannot get anywhere else. Ordering only: nothing is
    /// dropped for being here. Every name must be a catalog seat, which
    /// `notify-selftest.sh` checks against `BridgeCatalog.swift`.
    static let hasOwnApp: Set<String> = [
        "Gmail", "iCloud Mail", "Calendar", "Reminders",
        "ChatGPT", "Claude", "Gemini", "Grok",
        "Coinbase", "Kraken", "Binance", "Gemini Exchange", "Gnosis Pay",
        "Apple Wallet", "Safe", "ether.fi",
        "GitHub", "GitLab", "Linear", "Notion", "Slack", "Trello", "Jira",
        "Sentry", "Vercel", "PagerDuty", "Cloudflare", "App Store Connect", "Stripe",
        "Shopify", "Reddit", "YouTube", "Spotify", "Strava", "Garmin",
        "Todoist", "Pinterest", "Day One", "Duolingo",
        "Farcaster", "Telegram", "Bluesky", "Instagram", "Snapchat", "TikTok", "X",
        "Steam", "Dropbox", "Twitch", "Substack", "Stocktwits",
    ]

    /// The id every slot's requests share a prefix with. The category and the
    /// slot's own instant are appended by the scheduler, so no category's
    /// digest replaces another's, nor yesterday's still in Notification Center.
    static let requestPrefix = "digest:"

    /// The next slot strictly after `now`.
    ///
    /// Walks forward day by day rather than assuming today has one left, so an
    /// evening sweep lands on tomorrow's slot instead of a time already past.
    ///
    /// With any slot at all the walk always lands on day 0 or day 1, so the
    /// three-day bound and the fallback below are only reachable through an
    /// EMPTY `slots`, which nothing can hand in today (`readingSlots` returns
    /// the fixed one or a learned one). It waits a day anyway rather than
    /// returning `now`: the caller schedules on `slot - now`, so a `now` here
    /// would buzz the digest out immediately — the loudest possible answer to
    /// "I could not work out when this should go".
    static func nextSlot(after now: Date, calendar: Calendar, slots: [Int] = slots) -> Date {
        let today = calendar.startOfDay(for: now)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for minute in slots.sorted() {
                guard let when = calendar.date(bySettingHour: minute / 60, minute: minute % 60,
                                               second: 0, of: day), when > now else { continue }
                return when
            }
        }
        return calendar.date(byAdding: .day, value: 1, to: now) ?? now
    }

    /// One sweep's step: forget what a passed slot delivered, fold the new
    /// items in, drop whatever a switch now excludes, and choose the slot.
    ///
    /// The order is the rule. Clearing FIRST is what makes a delivered item
    /// impossible to announce twice; upserting by id is what lets a growing
    /// like count replace itself; filtering LAST is what makes a category
    /// switched off take its queued items with it on the very next sweep.
    static func advance(_ state: State, adding new: [Item], allowed: (Item) -> Bool,
                        now: Date, calendar: Calendar,
                        slots: [Int] = slots) -> State {
        var queue = state.queue
        if let slot = state.slot, slot <= now { queue = [] }
        for item in new {
            if let i = queue.firstIndex(where: { $0.id == item.id }) { queue[i] = item } else { queue.append(item) }
        }
        queue = queue.filter(allowed)
        if queue.count > cap { queue.removeFirst(queue.count - cap) }
        guard !queue.isEmpty else { return State(queue: [], slot: nil) }
        // Keep a slot still ahead of us: the queue grew, but the evening it is
        // waiting for did not move.
        if let slot = state.slot, slot > now { return State(queue: queue, slot: slot) }
        return State(queue: queue, slot: nextSlot(after: now, calendar: calendar, slots: slots))
    }

    /// The apps in the order the body names them: seats with no lock screen of
    /// their own first, then the app with the newest item, then by name so the
    /// order never depends on a dictionary. Each app is named by its newest
    /// item's source.
    static func apps(_ queue: [Item]) -> [String] {
        var newest: [String: Item] = [:]
        for item in queue where (newest[item.seat]?.occurredAt ?? .distantPast) <= item.occurredAt {
            newest[item.seat] = item
        }
        return newest.values.sorted { a, b in
            let aOwn = hasOwnApp.contains(a.seat), bOwn = hasOwnApp.contains(b.seat)
            if aOwn != bOwn { return !aOwn }
            if a.occurredAt != b.occurredAt { return a.occurredAt > b.occurredAt }
            return a.seat < b.seat
        }.map(\.name)
    }

    /// The queue split by category, in a fixed order (by name) so the stack
    /// never depends on a dictionary's.
    static func groups(_ queue: [Item]) -> [[Item]] {
        Dictionary(grouping: queue, by: \.category)
            .sorted { $0.key < $1.key }.map(\.value)
    }

    /// The notifications a queue becomes: one per category with something in it.
    static func plans(_ queue: [Item]) -> [NotifyPlan] {
        groups(queue).compactMap(plan)
    }

    /// The notification ONE category's queue becomes. Nil for an empty queue.
    ///
    /// One item is simply that item: its own headline, words and door, so a
    /// quiet day with one arrival reads like any notification.
    ///
    /// Several items are written to FIT (user, 2026-09-17: "no truncation
    /// ellipsis in the title or the bodies", "not repeat 'wallet:'
    /// 'wallet:'"): a title that is the place and its most telling number
    /// (`title`), and at most two body lines built from short facts — the
    /// people who acted, a count, a sum — rather than pasted titles that run
    /// past the edge (`body`). The whole of the day is the long press's.
    static func plan(_ queue: [Item]) -> NotifyPlan? {
        guard let newest = queue.max(by: { $0.occurredAt < $1.occurredAt }) else { return nil }
        if queue.count == 1 {
            return NotifyPlan(id: requestPrefix + newest.id,
                              kind: NotifyKind(rawValue: newest.kind) ?? .digest,
                              title: newest.title, body: newest.body, link: newest.link,
                              occurredAt: newest.occurredAt, source: newest.source,
                              place: newest.name)
        }
        let names = apps(queue)
        if names.count == 1 {
            let path = newest.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? newest.name
            return NotifyPlan(id: requestPrefix + newest.category + ":app", kind: .digest,
                              title: title(place: names[0], queue),
                              body: body(queue),
                              link: "casberi://feed/source/" + path,
                              occurredAt: newest.occurredAt, source: newest.source)
        }
        return NotifyPlan(id: requestPrefix + newest.category + ":apps", kind: .digest,
                          title: title(place: newest.category, queue),
                          body: body(queue),
                          link: "casberi://feed",
                          occurredAt: newest.occurredAt)
    }
}
