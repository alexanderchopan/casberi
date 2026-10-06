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
    /// The Wallet's Security tile (prd §1107): approvals, delegations, Safe
    /// signatures and the transfers made to fool you. It took Permissions'
    /// and Risk's tiles; neither of their glyphs (`key`, `shield`) is its own.
    static let security    = "lock.shield"
    static let frames      = "square.stack.3d.down.right"
    /// Privy's Apps — "every app that made you a wallet" (user, 2026-09-19:
    /// *"on the privy screen, you're using the same icon for apps that we use
    /// for frames. We need a different icon for apps there"*, prd §831).
    ///
    /// It wore `frames` for a month. A framed transaction and an app that
    /// holds a wallet for you are two meanings, and §815's rule reads both
    /// ways: one meaning is one glyph, so two meanings may not share one.
    ///
    /// A 2x2 grid of squares, the one affordance that says "apps" without
    /// argument (user, 2026-10-05: the You tray's Apps "should have four
    /// squares not six"). It was `square.grid.3x2` while `square.grid.2x2`
    /// read as spoken for, but its only other wearers are doors to the same
    /// catalogue (the empty feed's) and rows that are no tile, and
    /// `CategoryFold.glyph(for:)`'s fallback is never drawn
    /// (`category-fold-selftest.sh`).
    static let apps        = "square.grid.2x2"
    /// Every room's All (prd §815): the dock's own All glyph, read from its
    /// one table rather than retyped.
    static var all: String { CategoryFold.glyph(for: "All") }
    /// Work's Watch verb (prd §1031, §1057) — the app's watch glyph wherever a
    /// person follows something privately (Follow address, the address
    /// book's Watch, Markets' Watchlist).
    static let watch        = "eye"
    /// Markets' Alerts (prd §1081): the system's bell, the bell a note's
    /// reminder already wears for "tell me".
    static let alerts       = "bell"
    /// Markets' Search verb (prd §1082): the system's magnifier, the app's
    /// search glyph wherever a field searches.
    static let search       = "magnifyingglass"
    /// Logos' Node scope (prd §991) — the node you run.
    static let node         = "server.rack"
    /// Logos' Rewards scope (prd §1016) — what that node earns. The app's own
    /// symbol (`DSSymbol`): SF Symbols has no coin without a currency sign.
    static let rewards      = "coins.stack"
    /// The Notes room's tiles (prd §969). Pin is the dial's own pin glyph —
    /// the same meaning, so the same symbol; New is the bare plus, a verb in
    /// the tile row and the one tile that never lights. (`square.and.pencil`,
    /// Apple's compose, was refused by the user for an agent's Chat tile
    /// (2026-09-19) and is not re-proposed here either.)
    /// Folders is the bare `folder`, back with folders behind it (prd §980).
    static let folders      = "folder"
    /// Notes' Voice (prd §1127): the voice note's own row mark.
    static let voice        = "waveform"
    static let new          = "plus"
    /// The Wallet's Coming up (prd §1041): a calendar with a clock — what
    /// is still ahead. NOT the bare `calendar`, which is the dock's Life glyph
    /// and the event kind's: one glyph carries one meaning (prd §999).
    static let comingUp     = "calendar.badge.clock"
    /// Subscriptions (prd §1105, a tile again since §1111): two arrows
    /// chasing each other, what comes round again. The Wallet's and Day's
    /// tiles share it, because they are one idea in two rooms.
    static let subscriptions = "arrow.triangle.2.circlepath"
    /// Reading's Highlights (prd §1085): the system's highlighter, the pen a
    /// passage is kept with.
    static let highlights   = "highlighter"
    /// Social's To you (prd §1086): what is addressed to you — the system's
    /// one person, never `person.2` (Accounts, a list of people).
    static let toYou        = "person"
    /// You's Home (prd §1136): the house the tray's Home door wears — the
    /// feed, not the wallet family's Home (`home`, a line chart).
    static let feed         = "house"
    /// You's Notes place (prd §1136): the tray's Notes door.
    static let notes        = "note.text"
    /// You's Sources place (prd §1136, renamed from Settings the same day:
    /// "lets call 'settings' 'sources' i think sources makes more sense
    /// now"): everything your things come from, linked to you.
    static let sources      = "link"
    /// Sources' People (prd §1136 item 5): the people behind your accounts.
    static let people       = "person.crop.circle"
    /// Sources' Calendars (prd §1136e, §1137): the calendars you subscribe to.
    static let calendars    = "calendar"
    /// Sources' Feeds (prd §1136e): sites, channels and repos you follow.
    static let feeds        = "dot.radiowaves.up.forward"
    /// Sources' Newsletters (prd §1136e): the lists that write to your mail.
    static let newsletters  = "newspaper"
}

/// The Work room's tiles (prd §1057).
extension WorkScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:      return ScopeTileGlyph.all
        case .comingUp: return ScopeTileGlyph.comingUp
        case .watch:    return ScopeTileGlyph.watch
        }
    }
}

/// The Media room's tiles (prd §1118).
extension MediaScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:           return ScopeTileGlyph.all
        case .subscriptions: return ScopeTileGlyph.subscriptions
        }
    }
}

/// The Reading room's tiles (prd §1085). Subscriptions wears the Wallet's
/// and Day's glyph (§1118): one idea in every room that lists it.
extension ReadingScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:        return ScopeTileGlyph.all
        case .highlights: return ScopeTileGlyph.highlights
        case .subscriptions: return ScopeTileGlyph.subscriptions
        case .search:     return ScopeTileGlyph.search
        }
    }
}

/// The Social room's tiles (prd §1086). Follow wears Watch's eye, as
/// Reading's and the Wallet's do: following a person is watching them
/// privately (§801's "never write through a session").
extension SocialScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all:    return ScopeTileGlyph.all
        case .toYou:  return ScopeTileGlyph.toYou
        case .follow: return ScopeTileGlyph.watch
        }
    }
}

/// The Day room's tiles (prd §1056; Subscriptions, §1111).
extension DayScope: DSTileScope {
    var glyph: String {
        switch self {
        case .all: return ScopeTileGlyph.all
        case .comingUp: return ScopeTileGlyph.comingUp
        case .subscriptions: return ScopeTileGlyph.subscriptions
        case .new: return ScopeTileGlyph.new
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
        case .folders: return ScopeTileGlyph.folders
        case .voice:   return ScopeTileGlyph.voice
        case .new:     return ScopeTileGlyph.new
        case .search:  return ScopeTileGlyph.search
        }
    }
}

/// Privy's two scopes as tiles. Conformed here so the enum stays
/// Foundation-only and a harness compiles it whole.
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

/// The Wallet's four (prd §1107; Coming up became Subscriptions, §1111).
/// Watch is not a tile any more: it is the first row of the Accounts pill's
/// list.
extension WalletSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:     return ScopeTileGlyph.home
        case .holdings: return ScopeTileGlyph.holdings
        case .subscriptions: return ScopeTileGlyph.subscriptions
        case .security: return ScopeTileGlyph.security
        }
    }
}

/// Logos' scopes (prd §991): the family's Home glyph, a rack for the node you
/// run, and a coin stack for what it earns (§1016). No verb is a tile (§1108).
extension LogosSection: DSTileScope {
    var glyph: String {
        switch self {
        case .home:     return ScopeTileGlyph.home
        case .holdings: return ScopeTileGlyph.holdings
        case .node:     return ScopeTileGlyph.node
        case .rewards:  return ScopeTileGlyph.rewards
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
        }
    }
}

/// You's four places as tiles (prd §1136). Markets wears the dock's own
/// category glyph, the one its door has always worn.
extension YouTile: DSTileScope {
    var glyph: String {
        switch self {
        case .feed:     return ScopeTileGlyph.feed
        case .markets:  return CategoryFold.glyph(for: HomeScope.markets)
        case .notes:    return ScopeTileGlyph.notes
        case .sources:  return ScopeTileGlyph.sources
        }
    }
}

/// Sources' own filters (prd §1136 item 5). Subs wears Subscriptions' arrows,
/// its own name; Add is the bare plus every New wears.
extension SettingsScope: DSTileScope {
    var glyph: String {
        switch self {
        case .apps:          return ScopeTileGlyph.apps
        case .calendars:     return ScopeTileGlyph.calendars
        case .feeds:         return ScopeTileGlyph.feeds
        case .newsletters:   return ScopeTileGlyph.newsletters
        case .people:        return ScopeTileGlyph.people
        case .subscriptions: return ScopeTileGlyph.subscriptions
        case .new:           return ScopeTileGlyph.new
        case .search:        return ScopeTileGlyph.search
        }
    }
}

