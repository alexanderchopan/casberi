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
    static let nfts        = "photo.on.rectangle.angled"
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
    /// without argument — and it is free: `square.grid.2x2` is spoken for,
    /// and `circle.grid.3x3` is Hegota's UTXOs, circles rather than squares
    /// and a different count.
    static let apps        = "square.grid.3x2"
    static let utxos       = "circle.grid.3x3"
    static let snapshots   = "camera.viewfinder"
    static let shielded    = "lock.shield"
    static let review      = "checkmark.shield"
    /// The kind tiles of the Safe, GitHub and Stripe rooms (prd §815). All is
    /// the dock's own All glyph, read from its one table rather than retyped.
    static var all: String { CategoryFold.glyph(for: "All") }
    static let queue        = "signature"
    static let pullRequests = "arrow.triangle.pull"
    static let issues       = "smallcircle.filled.circle"
    static let releases     = "tag"
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
        case .chat: return ScopeTileGlyph.chat
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

extension WalletSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .activity:    return ScopeTileGlyph.activity
        case .holdings:    return ScopeTileGlyph.holdings
        case .accounts:    return ScopeTileGlyph.accounts
        case .positions:   return ScopeTileGlyph.positions
        case .nfts:        return ScopeTileGlyph.nfts
        case .risk:        return ScopeTileGlyph.risk
        case .permissions: return ScopeTileGlyph.permissions
        }
    }
}

extension FramesSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .activity:    return ScopeTileGlyph.activity
        case .holdings:    return ScopeTileGlyph.holdings
        case .accounts:    return ScopeTileGlyph.accounts
        case .frames:      return ScopeTileGlyph.frames
        case .permissions: return ScopeTileGlyph.permissions
        }
    }
}

extension HegotaSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .activity:    return ScopeTileGlyph.activity
        case .holdings:    return ScopeTileGlyph.holdings
        case .accounts:    return ScopeTileGlyph.accounts
        case .frames:      return ScopeTileGlyph.frames
        case .coins:       return ScopeTileGlyph.utxos
        case .permissions: return ScopeTileGlyph.permissions
        }
    }
}

extension PrivacyDevnetSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .activity:    return ScopeTileGlyph.activity
        case .holdings:    return ScopeTileGlyph.holdings
        case .accounts:    return ScopeTileGlyph.accounts
        case .frames:      return ScopeTileGlyph.frames
        case .permissions: return ScopeTileGlyph.permissions
        case .roots:       return ScopeTileGlyph.snapshots
        }
    }
}

extension VibenetSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:        return ScopeTileGlyph.home
        case .activity:    return ScopeTileGlyph.activity
        case .holdings:    return ScopeTileGlyph.holdings
        case .accounts:    return ScopeTileGlyph.accounts
        case .permissions: return ScopeTileGlyph.permissions
        }
    }
}
