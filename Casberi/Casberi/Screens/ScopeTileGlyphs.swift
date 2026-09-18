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
        }
    }
}

/// Privacy Pools' three scopes as tiles (prd §763). Conformed here for the
/// reason `DSSectionScope` is conformed in `MainSurface`: the enum stays
/// Foundation-only so the harness compiles it whole.
extension PrivyHomeFeed.Section: DSTileScope {
    var glyph: String {
        switch self {
        case .apps:     return ScopeTileGlyph.frames
        case .activity: return ScopeTileGlyph.activity
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
