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
    /// Override SYMBOL; nil wears the kind's own (prd §516, 2026-08-28).
    ///
    /// The one exception to the rule above this struct, and it is narrow: in a
    /// room where every row is the SAME kind, that kind's symbol has stopped
    /// distinguishing anything and is drawn a dozen times in a column. Today
    /// only `WalletActionMark` supplies one, for a wallet's own history — a
    /// send, a receipt, a mint and a grant, which are four different events
    /// wearing one arrow. The HUE stays the kind's, so the column still reads
    /// as one family; only the shape varies (§443's no-verdict-colour rule).
    var symbol: String? = nil

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
                Image(systemName: symbol ?? kind.symbol)
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
        // Hyperliquid's mark is mint on near-black, the Tokens shape exactly:
        // the tile is dark in both modes, so the signal has to come from the
        // glyph. Icon-sampled from the bundled mark.
        case "hyperliquid": return Color.fixed("#97fce4")
        // ether.fi's tile is pure black (the mark's own ground), so the signal
        // has to come from the glyph — the cyan end of the mark's cyan→indigo
        // run, icon-sampled from the bundled asset.
        case "ether.fi":   return Color.fixed("#35a2ed")
        // OpenRouter's mark is a lime glyph on a near-black ground — the same
        // shape again, so the signal comes from the glyph. Icon-sampled from
        // the bundled mark (2026-07-31).
        case "openrouter": return Color.fixed("#c0f000")
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
        // Merge, not braces — GitHub's own glyph is already "curlybraces",
        // and this bridge's whole read is issues AND merge requests, so the
        // fallback should say what's distinct about it rather than repeat
        // GitHub's mark if the bundled asset ever fails to load.
        case "gitlab":    return "arrow.triangle.merge"
        // Peer-to-peer, not braces: GitHub already owns "curlybraces", and the
        // single fact that distinguishes this seat is that there is no central
        // host — repos replicate between nodes, and the seed you name is only
        // one of them. The GitLab reasoning one line up, for the same reason.
        case "radicle":   return "point.3.filled.connected.trianglepath.dotted"
        // A KEY, plainly — this is the one seat in the catalog whose whole
        // subject is signing credentials, so the literal symbol is the right
        // one and any cleverer choice would say less. "key.horizontal" rather
        // than "lock": nothing here is locked or unlocked, and a padlock would
        // imply a control this seat deliberately doesn't have (§112).
        case "altana":    return "key.horizontal"
        case "linear":    return "list.bullet.rectangle"
        // The lists ARE the mark — a board read as columns. Both this and the
        // hue exist so a seat whose bundled art ever fails to load still reads
        // as itself rather than as the gray "app" default (report 2026-08-03:
        // Trello had neither, so its tile rendered as a generic gray square on
        // the simulator and on TestFlight).
        case "trello":    return "rectangle.split.3x1"
        // An issue tracker's whole subject is a queue with a status —
        // Linear's own glyph reasoning, one degree more literal: Jira's
        // vocabulary is tickets, not a board of cards.
        case "jira":      return "checklist"
        case "notion":    return "doc.richtext"
        case "x", "twitter": return "bookmark"
        case "instagram": return "camera"
        case "tiktok":    return "music.note"
        case "reddit":    return "text.bubble"
        case "youtube":   return "play.rectangle"
        case "substack":  return "doc.text.image"
        case "podcasts":  return "mic"
        case "contacts":  return "person.crop.circle"
        case "kindle":    return "book.pages"
        case "apple music": return "music.note"
        case "spotify":   return "music.note.list"
        case "wallet":    return "wallet.bifold"
        // The folded Markets chip's own glyph (2026-08-11) — the same generic
        // treatment Wallet already wears, and the same symbol/color the
        // catalog's Markets category chip uses via its Kalshi exemplar
        // (`BridgeCatalog.categories`), so the two "Markets" marks in the app
        // agree with each other rather than inventing a third convention.
        case "markets":   return "percent"
        case "peer":      return "arrow.left.arrow.right"
        case "privacy pools", "0xbow privacy pools": return "shield.lefthalf.filled"
        case "gnosis pay": return "creditcard"
        case "apple wallet": return "creditcard.fill"
        // The unstake queue's whole subject is waiting, then collecting — an
        // hourglass says that where a generic coin or chain glyph wouldn't.
        case "ether.fi":  return "hourglass"
        // Same mark as Gnosis Pay: they are the same object (a card that
        // settles onchain), and picking a different glyph for one would say
        // they were different kinds of thing.
        case "ether.fi cash": return "creditcard"
        // A multisig is a signature queue — the same mark `WalletWarning.Kind`
        // already uses for a pending Safe signature, so the catalog tile and
        // the Worth-a-look row can't pick different glyphs for one thing.
        case "safe":      return "signature"
        // A NAME, not a handle — "at" is already spoken for by Farcaster and
        // Bluesky, whose whole subject is a social identity. ENS's is a name
        // that RESOLVES (to an address, and eventually to nothing, once it
        // expires), so the mark says "readable text" rather than "@someone".
        case "ens":       return "textformat.characters"
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
        case "snapchat":  return "camera.fill"
        case "telegram":  return "paperplane.fill"
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
        // Walletbeat GRADES wallets, and plenty of its verdicts are failing
        // ones — so a seal or a shield is wrong here twice over: both read as
        // "approved", which would state a verdict this seat does not hold (§83),
        // and `checkmark.shield`/`lock.shield` are already spoken for. A report
        // card is the neutral shape: it says an assessment exists, not how it
        // came out.
        case "walletbeat": return "list.clipboard"
        // L2BEAT assesses the RAILS, so the glyph is the stack of them. A shield
        // or a seal would read as "approved", which is a verdict this seat does
        // not hold for 76 of the 105 chains it covers (§83); `list.clipboard` is
        // taken by Walletbeat, whose job this most resembles, and reusing it
        // would make two different registries indistinguishable in the strip.
        case "l2beat": return "square.stack.3d.up"
        // The offers sitting unused on your cards — a reward, not a card. The
        // card glyphs are taken by the seats that ARE cards (Privacy, Apple
        // Wallet), and reusing one would file this beside them as a third card.
        case "cardpointers": return "rosette"
        case "coinbase", "kraken", "binance", "gemini exchange": return "building.columns"
        case "eth validators": return "checkmark.shield"
        case "1claw":     return "lock.shield"
        // An issue that came back is the row this seat exists for, and an
        // exclamation inside a bubble is what every crash reporter's own UI
        // uses. Not "ant" (Sentry's own mark is a lantern, which reads as a
        // lamp at 32pt and says nothing about errors).
        // The ONE seat in this table with no bundled mark BY RULING (user,
        // 2026-08-06: "we can't use their icon"): the App Store's own mark is
        // Apple's trademark, so the SF Symbol IS this bridge's face rather
        // than a fallback for art that failed to load.
        //
        // A MONOGRAM, chosen over a pictogram (user: "why not use some version
        // of an A") — which is also the convention half this catalog already
        // follows, since Privacy, Bitrefill and Kalshi all wear a letter.
        // `character` is named for typography UI but RENDERS a plain capital
        // A, verified by rendering it; that is the whole reason it is here, so
        // don't "fix" it to a more semantically-named symbol without looking
        // at what that one draws. `a.square` also draws an A and was rejected:
        // the tile is already a rounded square, so it reads as a square inside
        // a square.
        case "app store connect": return "character"
        case "sentry":    return "exclamationmark.bubble"
        // The mark is a triangle; `triangle.fill` is the closest SF Symbol and
        // is what a Vercel deploy reads as anywhere it's drawn small.
        case "vercel":    return "triangle.fill"
        case "pagerduty": return "bell.badge"
        // A package is a package on both registries — but they must not share
        // a glyph, or two seats sitting side by side in the same Work group
        // read as one thing listed twice (the ether.fi/Gnosis Pay rule, in
        // reverse: those two ARE the same object, these two are not).
        case "npm":       return "shippingbox.fill"
        case "pypi":      return "shippingbox"
        case "homekit":   return "homekit"
        case "stripe":       return "banknote"
        // The three payment seats must not share `banknote` with Stripe or
        // with each other: they sit in the same Work group, and a group where
        // three tiles wear one mark reads as one thing listed three times
        // (the npm/PyPI rule above). Each takes what its OWN room leads with
        // — Polar's is recurring revenue (§537's sales and the MRR head),
        // Dodo's is every payment as it succeeds, so a card rather than a
        // cycle.
        case "polar":        return "arrow.trianglehead.2.clockwise.rotate.90"
        case "dodo payments": return "creditcard"
        // A cloud that BILLS you, deliberately not `cloud.fill` — Cloudflare
        // already holds that, and the two are not the same kind of thing.
        case "aws":          return "server.rack"
        case "posthog":      return "chart.bar.xaxis"
        case "cloudflare":   return "cloud.fill"
        case "cursor":       return "cursorarrow"
        // A session transcript is a terminal recording, not a chat — the
        // "claude"/"chatgpt"/"gemini" bubble is the wrong claim here (those
        // are message-shaped imports; this one imports what a CLI wrote).
        case "claude code":  return "terminal"
        case "stocktwits":   return "bubble.left.and.bubble.right"
        case "hugging face": return "face.smiling"
        case "circle x402":  return "dollarsign.circle"
        // DeFi protocols the wallet rides — each a distinct glyph even where
        // the shape (lending, a lock, a swap) rhymes, the ether.fi/Gnosis Pay
        // rule in reverse: these are genuinely different objects and must not
        // read as one thing listed twice.
        case "aave":         return "a.circle"
        case "morpho":       return "building.2"
        case "uniswap":      return "arrow.triangle.2.circlepath"
        case "hyperliquid":  return "waveform.path.ecg"
        case "aerodrome":    return "lock.rotation"
        // Railgun shields the same way Privacy Pools does, but the two are
        // separate protocols — `shield.lefthalf.filled` is already taken.
        case "railgun":      return "eye.slash"
        case "polymarket":   return "questionmark.circle"
        // A BYOK provider, not a chat import — Venice/Bankr/OpenRouter each
        // already wear their own mark, so Grok gets one rather than folding
        // into ChatGPT/Claude/Gemini's shared "bubble.left" (those three
        // really are one shape: "import your chats"; a BYOK key is not).
        case "grok":         return "bolt.circle"
        case "openrouter":   return "arrow.triangle.branch"
        // Base's own real mark is bundled now (`brand-base-vibenet`), so
        // `BridgeIcon` never reaches this fallback in practice — kept
        // defensive, in the neutral-letterform shape (the App Store Connect
        // precedent) rather than an invented theme icon, in case the asset
        // ever fails to load.
        case "base vibenet": return "character"
        // Hegotá bundles its own mark too (`brand-ethrex-hegota`), so this is
        // the same defensive fallback for the same reason — and the same
        // ANSWER: a neutral letterform rather than an invented theme icon.
        // A frame or a vault glyph would name one of the chain's readings and
        // silently rank it above the others, which is a claim a fallback has
        // no business making. The literal carries the accent in the catalog's
        // own normalization: Swift compares canonically, the harness does not.
        case "ethrex hegotá": return "character"
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
