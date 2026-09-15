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
    static let risk        = "exclamationmark.triangle"
    static let frames      = "square.stack.3d.down.right"
    static let utxos       = "circle.grid.3x3"
    static let snapshots   = "camera.viewfinder"
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
