import SwiftUI

/// The one icon system for things: an SF Symbol per kind on a quiet squircle.
/// One weight, one fill, everywhere — consistency is what reads as finished.
/// A row's icon says what the thing IS; the tag pill and place words say where
/// it came from. Brand marks return only with real assets (Apps catalog, M5).
struct KindGlyph: View {
    let kind: ThingKind
    var size: CGFloat = 28
    /// Override color; nil wears the kind's own hue (ruling 2026-07-05 —
    /// identity color: the shape says what it is, the hue agrees).
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let base = tint ?? kind.hue
        // Light mode deepens the hue and the fill — cyan/yellow glyphs were
        // washing out against light cards.
        let color = scheme == .light ? base.mix(with: .black, by: 0.3) : base
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
            .fill(base.opacity(scheme == .light ? 0.22 : 0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.5,
                                  weight: scheme == .light ? .semibold : .medium))
                    .foregroundStyle(color)
            )
    }
}

extension ThingKind {
    var symbol: String {
        switch self {
        case .note:       return "note.text"
        case .screenshot: return "photo"
        case .chat:       return "bubble.left"
        case .event:      return "calendar"
        case .link:       return "link"
        case .reminder:   return "checklist"
        case .mail:       return "envelope"
        case .file:       return "doc"
        case .voice:      return "waveform"
        case .job:        return "gearshape"
        case .run:        return "play"
        case .output:     return "shippingbox"
        case .skill:      return "sparkles"
        case .approval:   return "hand.raised"
        case .transaction: return "arrow.left.arrow.right"
        case .contact:    return "person.crop.circle"
        case .product:    return "bag"
        case .accessory:  return "homekit"
        }
    }

    /// Lookup from a type-tag string (the gen UI document carries tags, not
    /// kinds). Unknown tags get the generic mark.
    static func from(typeTag: String) -> ThingKind? {
        allCases.first { $0.typeTag.caseInsensitiveCompare(typeTag) == .orderedSame }
    }
}

/// Kind glyph for gen UI rows/chips, resolved from the document's tag string.
struct TagGlyph: View {
    let tag: String
    var size: CGFloat = 24
    var tint: Color? = nil

    var body: some View {
        if let kind = ThingKind.from(typeTag: tag) {
            KindGlyph(kind: kind, size: size, tint: tint)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
                .fill(DS.fillFaint)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "circle.dashed")
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(DS.textSecondary)
                )
        }
    }
}

/// Bridge category symbol — what the connection reaches, not a brand mark.
/// Identity rides COLOR (legal everywhere); artwork waits on the M5 catalog.
enum BridgeGlyph {
    static func color(for name: String) -> Color {
        DS.brandColor(for: name)
    }

    /// The marks whose identity is the GLYPH's color, not the tile's —
    /// Tokens is a green chart on ink (user ruling 2026-07-17). Nil for
    /// every tile-colored mark. Fixed like every brand hex: the Tokens tile
    /// is black in both modes, so the vivid dark-scheme green always holds.
    /// Surfaces that paint the brand color as the SIGNAL (the settings
    /// seat chips) substitute this where non-nil, since a near-black hue
    /// carries no light of its own.
    static func glyphTint(for name: String) -> Color? {
        switch name.lowercased() {
        // DS.confirm's dark value — re-typed fixed because the mark must not
        // shift per scheme; keep in step if the confirm green is ever tuned.
        case "tokens": return Color.fixed("#30d158")
        default:       return nil
        }
    }

    /// The color that SAYS this brand on any surface — the glyph tint where
    /// the identity is the glyph's (Tokens' green), the tile hue everywhere
    /// else. Use this wherever the brand color is painted as a signal or
    /// payoff (seat chips, the connect bloom, inline icons): a near-black
    /// tile hue carries no light of its own there.
    static func signalColor(for name: String) -> Color {
        glyphTint(for: name) ?? color(for: name)
    }

    static func symbol(for name: String) -> String {
        switch name.lowercased() {
        case "calendar":  return "calendar"
        case "gmail", "mail": return "envelope"
        case "icloud mail": return "envelope.badge"
        case "chatgpt", "claude", "gemini": return "bubble.left"
        case "reminders": return "checklist"
        case "photos":    return "photo"
        case "notes", "apple notes": return "note.text"
        case "apple journal": return "book.closed"
        case "day one":   return "1.circle"
        case "bookmarks": return "bookmark.fill"
        case "safari":    return "globe"
        case "github":    return "curlybraces"
        case "linear":    return "list.bullet.rectangle"
        case "notion":    return "doc.richtext"
        case "x", "twitter": return "bookmark"
        case "reddit":    return "text.bubble"
        case "youtube":   return "play.rectangle"
        case "substack":  return "doc.text.image"
        case "podcasts":  return "mic"
        case "contacts":  return "person.crop.circle"
        case "kindle":    return "book.pages"
        case "apple music": return "music.note"
        case "spotify":   return "music.note.list"
        case "wallet":    return "wallet.bifold"
        case "peer":      return "arrow.left.arrow.right"
        case "privacy pools", "0xbow privacy pools": return "shield.lefthalf.filled"
        case "gnosis pay": return "creditcard"
        case "kalshi":    return "percent"
        case "opensea":   return "sailboat.fill"
        case "geckoterminal": return "flame.fill"
        case "tokens":    return "chart.line.uptrend.xyaxis"
        case "venice":    return "wand.and.stars"
        case "bankr":     return "brain.head.profile"
        case "voice":     return "waveform"
        case "you":       return "person"
        case "apple health": return "heart"
        case "strava":    return "figure.run"
        case "todoist":   return "checklist"
        case "slack":     return "number"
        case "raindrop":  return "drop"
        case "readwise":  return "book"
        case "rss":       return "dot.radiowaves.up.forward"
        case "farcaster": return "at"
        case "pinterest": return "pin"
        case "bluesky":   return "at"
        case "nostr":     return "bird"
        case "cal.com", "calendly": return "calendar"
        case "steam":     return "gamecontroller"
        case "obsidian":  return "text.book.closed"
        case "files":     return "icloud"
        case "dropbox":   return "folder"
        case "twitch":    return "tv"
        case "shopify":   return "bag"
        case "deals":     return "tag.fill"
        case "open food facts": return "barcode.viewfinder"
        case "bitrefill": return "gift"
        case "privacy":   return "creditcard"
        case "coinbase", "kraken": return "building.columns"
        case "1claw":     return "lock.shield"
        case "homekit":   return "homekit"
        default:          return "app"
        }
    }
}


/// Kind hues (ruling 2026-07-05): each kind of thing carries its own color —
/// identity, which the color law permits. The person's accent keeps
/// selection and interaction; kinds keep who-they-are. iOS system palette,
/// so every hue is native in both modes. Rare agent kinds may share a
/// family; the daily kinds are all distinct.
extension ThingKind {
    var hue: Color {
        switch self {
        case .note:       return Color(hex: "#ffd60a")   // yellow — notes
        case .link:       return Color(hex: "#0a84ff")   // blue — the web
        case .screenshot: return Color(hex: "#30d158")   // green — captures
        case .chat:       return Color(hex: "#bf5af2")   // purple — conversation
        case .event:      return Color(hex: "#ff453a")   // red — calendar
        case .reminder:   return Color(hex: "#ff9f0a")   // orange — reminders
        case .mail:       return Color(hex: "#64d2ff")   // cyan — mail
        case .file:       return Color(hex: "#ac8e68")   // brown — documents
        case .voice:      return Color(hex: "#ff375f")   // pink — the voice
        case .job:        return Color(hex: "#5e5ce6")   // indigo — agent work
        case .run:        return Color(hex: "#63e6e2")   // mint — runs
        case .output:     return Color(hex: "#ac8e68")   // brown — artifacts, like files
        case .skill:      return Color(hex: "#ffd60a")   // gold — banked craft
        case .approval:   return Color(hex: "#ff375f")   // crimson — needs your call
        case .transaction: return Color(hex: "#f7931a")  // amber — onchain (a vertical kind, may share the warm family)
        case .contact:    return Color(hex: "#34c759")   // green — people
        case .product:    return Color(hex: "#30b0c7")   // teal — shopping
        case .accessory:  return Color(hex: "#8e8e93")   // gray — home hardware
        }
    }
}
