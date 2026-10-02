import Foundation

/// ONE GLYPH PER SCOPE NAME, across the wallet family (prd §752).
///
/// Five rooms share most of their scope names (Home, Activity, Holdings,
/// Accounts, Permissions), and a name that wore a different glyph in the
/// next room over would read as a different thing. So the glyph belongs to
/// the NAME, here, and each room's enum only says which name it is.
///
/// Each chosen by the user from three rendered options (2026-09-15).
/// `person.2` is also the People seat's glyph inside Life; kept on purpose.
enum ScopeTileGlyph {
    static let home        = "chart.xyaxis.line"
    static let activity    = "clock.arrow.circlepath"
    static let holdings    = "chart.pie"
    static let accounts    = "person.2"
    static let permissions = "key"
    static let positions   = "building.columns"
    /// The Wallet's Cards tile (prd §1048). Not the bare `creditcard`: the
    /// user reserved that, and `creditcard.fill`, for the Wallet itself
    /// (`room-kind-tiles-selftest`), and a tile inside the Wallet wearing the
    /// Wallet's own mark would read as a second door to the room it is in.
    static let cards       = "creditcard.and.123"
    static let risk        = "shield"
    static let frames      = "square.stack.3d.down.right"
    /// Privy's Apps — "every app that made you a wallet" (user, 2026-09-19:
    /// *"on the privy screen, you're using the same icon for apps that we use
    /// for frames. We need a different icon for apps there"*, prd §831).
    ///
    /// It wore `frames` for a month. A framed transaction and an app that
    /// holds a wallet for you are two meanings, and §815's rule reads both
    /// ways: one meaning is one glyph, so two meanings may not share one.
    ///
    /// A 3x2 grid of squares, which is the one affordance that says "apps"
    /// without argument — and it is free: `square.grid.2x2` is spoken for.
    static let apps        = "square.grid.3x2"
    static let shielded    = "lock.shield"
    static let review      = "checkmark.shield"
    /// The kind tiles of the Safe, GitHub and Stripe rooms (prd §815). All is
    /// the dock's own All glyph, read from its one table rather than retyped.
    static var all: String { CategoryFold.glyph(for: "All") }
    static let queue        = "signature"
    static let pullRequests = "arrow.triangle.pull"
    static let issues       = "smallcircle.filled.circle"
    static let releases     = "tag"
    /// GitHub's Watch verb (prd §1031) — the app's watch glyph wherever a
    /// person follows something privately (Follow address, the address
    /// book's Watch, Markets' Watchlist).
    static let watch        = "eye"
    static let payments     = "dollarsign.circle"
    static let payouts      = "banknote"
    static let disputes     = "exclamationmark.triangle"
    /// App Store Connect's and Hugging Face's kind tiles (prd §816). Each a
    /// meaning no tile or dock seat had yet, so each a symbol none wears.
    static let versions     = "app.badge"
    static let reviews      = "star.bubble"
    static let builds       = "hammer"
    static let models       = "cpu"
    static let datasets     = "cylinder.split.1x2"
    static let papers       = "doc.text"
    /// PostHog's, L2BEAT's and Walletbeat's (prd §816). News and Revisions
    /// are one meaning in both rating rooms, so one glyph each.
    static let metrics      = "gauge.with.dots.needle.33percent"
    static let annotations  = "text.bubble"
    static let milestones   = "flag"
    static let chains       = "point.3.connected.trianglepath.dotted"
    static let wallets      = "wallet.bifold"
    static let news         = "newspaper"
    static let revisions    = "arrow.triangle.2.circlepath"
    /// The agent rooms' live half (prd §840) — the tile that turns the room
    /// from the conversations you have HAD into the one you are having.
    ///
    /// **The bubble family here differs by what sits INSIDE the bubble**, and
    /// that is what makes this free rather than a fifth generic one: a star is
    /// a review, a line of text an annotation, a character Duolingo, an
    /// exclamation Sentry — so an ellipsis is "it is answering". The plain
    /// bubbles were all spoken for: `bubble.left` is the chat KIND and the
    /// ChatGPT/Claude/Gemini seats, `bubble.left.and.bubble.right` is the
    /// Social category chip and Stocktwits (user, 2026-09-19).
    ///
    /// `square.and.pencil` — Apple's own compose — was proposed and REFUSED
    /// by the user, though it was free as a tile glyph and its five other uses
    /// all mean compose. Do not re-propose it.
    static let chat         = "ellipsis.bubble"
    /// The twelve rooms that grew tiles in prd §911, each a meaning no tile or
    /// dock seat wore. A merge request and a patch ARE pull requests, so those
    /// two cases wear `pullRequests` as declared aliases (the harness's
    /// `ALIASES`), never a second glyph for one meaning. `cart` is Shopping's,
    /// so a sale is a bag; `creditcard` is the wallet's, so a cost is a bar chart.
    static let sales        = "bag"
    static let subscriptions = "repeat"
    static let errors       = "ladybug"
    static let regressions  = "arrow.counterclockwise"
    static let deploys      = "shippingbox"
    static let failed       = "xmark.octagon"
    static let alarms       = "bell"
    static let costs        = "chart.bar"
    static let incidents    = "light.beacon.max"
    static let resolved     = "checkmark.circle"
    static let deprecations = "archivebox"
    static let workouts     = "figure.run"
    static let sleep        = "bed.double"
    static let mood         = "face.smiling"
    /// Logos' Node scope (prd §991) — the node you run.
    static let node         = "server.rack"
    /// Logos' Rewards scope (prd §1016) — what that node earns. The app's own
    /// symbol (`DSSymbol`): SF Symbols has no coin without a currency sign.
    static let rewards      = "coins.stack"
    /// The Notes room's tiles (prd §969). Pin is the dial's own pin glyph —
    /// the same meaning, so the same symbol; New is the bare plus, a verb in
    /// the tile row and the one tile that never lights. (`square.and.pencil`
    /// was refused for Chat above and is not re-proposed here either.)
    /// Folders is the bare `folder`, back with folders behind it (prd §980).
    static let pinned       = "pin"
    static let folders      = "folder"
    static let new          = "plus"
    /// The Reminders room's date scope (prd §993), Apple's own Today.
    /// Not `calendar`: that is the event kind's glyph and the Calendar seat's.
    static let today        = "sun.max"
    /// The Calendar room's spans (prd §994); Today is Reminders' `today`
    /// above. Month is a grid of days, not `calendar`: that is the dock's
    /// Life glyph, and one glyph carries one meaning (prd §999).
    static let week         = "calendar.day.timeline.left"
    static let month        = "tablecells"
    /// The mail rooms' Attachments (prd §1019). The note sheet's attach tool
    /// wears the same clip for the same meaning; no tile or dock seat does.
    static let attachments  = "paperclip"
    /// The Frames room's three VERB tiles (prd §1039) — the glyphs their rows
    /// wore in the Actions block, so the act keeps its face as it becomes a
    /// tile. `create` is not `new`'s plus: a new account is not a new note.
    static let send         = "arrow.up.right"
    static let topUp        = "drop"
    static let create       = "plus.rectangle.on.rectangle"
    /// The Wallet's Coming up (prd §1041): a calendar with a clock — what
    /// is still ahead. NOT the bare `calendar`, which is the dock's Life glyph
    /// and the event kind's: one glyph carries one meaning (prd §999).
    static let comingUp     = "calendar.badge.clock"
    /// Logos' Explorer verb tile (prd §1039): it opens the testnet's explorer
    /// in the browser, and Safari's compass is the app's "opens a page" mark
    /// (the reading sheet's Open in Safari).
    static let explorer     = "safari"
}

/// The mail rooms' tiles (prd §1019). New is the Notes room's plus: the same
/// verb, so the same glyph.
extension MailScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:         return ScopeTileGlyph.all
        case .attachments: return ScopeTileGlyph.attachments
        case .new:         return ScopeTileGlyph.new
        }
    }
}

/// The Calendar room's tiles (prd §994). New is the Notes room's plus: the
/// same verb, so the same glyph.
extension CalendarScope: DSTileScope {
    static var readsInTime: Bool { true }
    var glyph: String {
        switch self {
        case .today: return ScopeTileGlyph.today
        case .week:  return ScopeTileGlyph.week
        case .month: return ScopeTileGlyph.month
        case .new:   return ScopeTileGlyph.new
        }
    }
}

/// The Notes room's tiles (prd §969). Conformed here for the reason every
/// other scope enum is — `NotesScope` stays Foundation-only so a harness can
/// compile it whole.
extension NotesScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:     return ScopeTileGlyph.all
        case .pinned:  return ScopeTileGlyph.pinned
        case .folders: return ScopeTileGlyph.folders
        case .new:     return ScopeTileGlyph.new
        }
    }
}

/// The Reminders room's tiles (prd §993). New is the Notes room's plus: the
/// same verb, so the same glyph.
extension RemindersScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:       return ScopeTileGlyph.all
        case .today:     return ScopeTileGlyph.today
        case .new:       return ScopeTileGlyph.new
        }
    }
}

/// The rooms' kind tiles (prd §815, §816). Activity and Permissions are the
/// wallet family's own glyphs, because they are the same meaning; every new
/// kind wears a glyph no other tile or dock seat wears, and a meaning two rooms
/// share (News, Revisions) is one case, so one glyph.
extension RoomKindTile: DSTileScope {
    var glyph: String {
        switch self {
        case .all:          return ScopeTileGlyph.all
        case .queue:        return ScopeTileGlyph.queue
        case .activity:     return ScopeTileGlyph.activity
        case .permissions:  return ScopeTileGlyph.permissions
        case .pullRequests: return ScopeTileGlyph.pullRequests
        case .issues:       return ScopeTileGlyph.issues
        case .releases:     return ScopeTileGlyph.releases
        case .watch:        return ScopeTileGlyph.watch
        case .payments:     return ScopeTileGlyph.payments
        case .payouts:      return ScopeTileGlyph.payouts
        case .disputes:     return ScopeTileGlyph.disputes
        case .versions:     return ScopeTileGlyph.versions
        case .reviews:      return ScopeTileGlyph.reviews
        case .builds:       return ScopeTileGlyph.builds
        case .models:       return ScopeTileGlyph.models
        case .datasets:     return ScopeTileGlyph.datasets
        case .papers:       return ScopeTileGlyph.papers
        case .metrics:      return ScopeTileGlyph.metrics
        case .annotations:  return ScopeTileGlyph.annotations
        case .milestones:   return ScopeTileGlyph.milestones
        case .chains:       return ScopeTileGlyph.chains
        case .wallets:      return ScopeTileGlyph.wallets
        case .news:         return ScopeTileGlyph.news
        case .revisions:    return ScopeTileGlyph.revisions
        // Splits' accounts are the wallet family's Accounts by name, so they
        // wear its glyph rather than a second one (prd §820).
        case .accounts:     return ScopeTileGlyph.accounts
        case .sales:         return ScopeTileGlyph.sales
        case .subscriptions: return ScopeTileGlyph.subscriptions
        // GitLab's and Radicle's words for a pull request (prd §911).
        case .mergeRequests: return ScopeTileGlyph.pullRequests
        case .patches:       return ScopeTileGlyph.pullRequests
        case .errors:        return ScopeTileGlyph.errors
        case .regressions:   return ScopeTileGlyph.regressions
        case .deploys:       return ScopeTileGlyph.deploys
        case .failed:        return ScopeTileGlyph.failed
        case .alarms:        return ScopeTileGlyph.alarms
        case .costs:         return ScopeTileGlyph.costs
        case .incidents:     return ScopeTileGlyph.incidents
        case .resolved:      return ScopeTileGlyph.resolved
        case .deprecations:  return ScopeTileGlyph.deprecations
        case .workouts:      return ScopeTileGlyph.workouts
        case .sleep:         return ScopeTileGlyph.sleep
        case .mood:          return ScopeTileGlyph.mood
        }
    }
}

/// Privacy Pools' three scopes as tiles (prd §763). Conformed here for the
/// reason `DSSectionScope` is conformed in `MainSurface`: the enum stays
/// Foundation-only so the harness compiles it whole.
extension PrivyHomeFeed.Section: DSTileScope {
    var glyph: String {
        switch self {
        case .apps:     return ScopeTileGlyph.apps
        case .activity: return ScopeTileGlyph.activity
        }
    }
}

/// The agent rooms' two halves (prd §840). Conformed here for the reason every
/// other scope enum is — `AgentRoomScope` stays Foundation-only so a harness
/// can compile it whole.
extension AgentRoomScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:  return ScopeTileGlyph.all
        case .new:  return ScopeTileGlyph.new
        }
    }
}

extension PrivacyPoolsSection: DSTileScope {
    var glyph: String {
        switch self {
        case .activity: return ScopeTileGlyph.activity
        case .shielded: return ScopeTileGlyph.shielded
        case .review:   return ScopeTileGlyph.review
        }
    }
}

/// Follow wears Watch's eye (prd §1039): following an address privately IS
/// watching it (`ScopeTileGlyph.watch` names Follow address among its uses),
/// so one meaning, one glyph — a declared alias in `room-kind-tiles-selftest`.
extension WalletSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .holdings:    return ScopeTileGlyph.holdings
        case .comingUp:    return ScopeTileGlyph.comingUp
        case .positions:   return ScopeTileGlyph.positions
        case .cards:       return ScopeTileGlyph.cards
        case .risk:        return ScopeTileGlyph.risk
        case .permissions: return ScopeTileGlyph.permissions
        case .follow:      return ScopeTileGlyph.watch
        }
    }
}

/// Logos' scopes (prd §991): the family's Home glyph, a rack for the node you
/// run, a coin stack for what it earns (§1016), and the explorer verb.
extension LogosSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:     return ScopeTileGlyph.home
        case .node:     return ScopeTileGlyph.node
        case .rewards:  return ScopeTileGlyph.rewards
        case .explorer: return ScopeTileGlyph.explorer
        }
    }
}

extension FramesSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .holdings:    return ScopeTileGlyph.holdings
        case .frames:      return ScopeTileGlyph.frames
        case .permissions: return ScopeTileGlyph.permissions
        case .create:      return ScopeTileGlyph.create
        case .send:        return ScopeTileGlyph.send
        case .topUp:       return ScopeTileGlyph.topUp
        }
    }
}

