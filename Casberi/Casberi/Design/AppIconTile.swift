import SwiftUI

/// Squircle app-icon stand-in. Gap list §9.6: letter/brand tiles stand in until
/// real app-icon assets ship per store guidelines. Radius follows the 22.37%
/// app-icon ratio. Brand colors are identity (color rule allows identity), and
/// they live here in the design layer — components never inline the hex.
struct AppIconTile: View {
    let source: String
    var size: CGFloat = 40

    private var brand: Color { DS.brandColor(for: source) }
    private var letter: String { String(source.prefix(1)).uppercased() }

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
            .fill(brand)
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 1)
            )
    }
}

extension DS {
    /// Brand-color table for the icon stand-ins. Identity color, kept out of the
    /// component. Unknown sources fall back to the neutral gray fill.
    static func brandColor(for source: String) -> Color {
        brandHue(for: source) ?? DS.gray300
    }

    /// The hue itself, nil when the source has none — the gray fallback is
    /// a fill, not an identity, so surfaces that WEAR the hue (the thing
    /// sheet's wash) ask this and stay pure ink on nil (ruling 2026-07-10).
    static func brandHue(for source: String) -> Color? {
        switch source.lowercased() {
        case "calendar":            return Color.fixed("#ff3b30")
        case "gmail", "mail":       return Color.fixed("#ea4335")
        case "icloud mail":         return Color.fixed("#3693f3")
        case "chatgpt":             return Color.fixed("#ffffff")
        case "claude":              return Color.fixed("#d97757")
        case "gemini":              return Color.fixed("#4285f4")   // the sparkle's blue end
        case "reminders":           return Color.fixed("#ff9500")
        case "photos":              return Color.fixed("#5e9ee6")
        case "x", "twitter":        return Color.fixed("#000000")
        case "notes", "apple notes": return Color.fixed("#ffcc00")
        case "apple journal":       return Color.fixed("#a06ee1")   // Journal's lavender
        case "day one":             return Color.fixed("#44c0ff")   // Day One blue
        case "bookmarks":           return Color.fixed("#8d6e63")   // a neutral bookmark-ribbon brown — no single brand here (Safari + Chrome, one file format)
        case "safari":              return Color.fixed("#1d9bf6")
        case "wallet":              return Color.fixed("#2461ff")
        case "peer":                return Color.fixed("#4b47f6")   // an indigo in their family — approximate; re-sample when bundling the official mark
        case "gnosis pay":          return Color.fixed("#4830c0")   // the owl's indigo (icon-sampled from the bundled mark)
        case "safe":                return Color.fixed("#12ff80")   // Safe{Wallet}'s green (icon-sampled from the bundled mark)
        case "privacy pools", "0xbow privacy pools":
                                    return Color.fixed("#ffffff")   // 0xBow's mark is black on white (bundled) — the white field is the identity, like ChatGPT's; zero saturation means washHue nils, so the page stays pure ink on purpose
        // The five DeFi protocols the wallet already reads, seated in the
        // catalog 2026-07-30. Every one is icon-sampled from the mark bundled
        // beside it in the asset catalog, so tile and hue can't drift.
        case "aave":                return Color.fixed("#9391f7")   // the ghost's lavender
        case "morpho":              return Color.fixed("#2a73ff")   // the butterfly's blue field
        case "aerodrome":           return Color.fixed("#0434ff")   // the swoosh's electric blue — its cream FIELD is the most common pixel, but a near-white hue carries no signal (the 0xBow case), so the identity is the mark itself
        case "uniswap":             return Color.fixed("#ff007a")   // their documented brand pink; the bundled mark's gradient samples a shade off it
        case "hyperliquid":         return Color.fixed("#0e3333")   // the dark field IS the mark's ground — near-zero saturation on purpose, so the mint below carries the signal (the Tokens rule)
        // ether.fi's two seats (2026-07-31). The mark IS bundled beside this
        // (brand-etherfi), so the hue is icon-sampled like its neighbours: the
        // ground is pure black and the isometric blocks run cyan→indigo, which
        // is the Hyperliquid/Tokens case exactly — a near-zero-saturation tile,
        // with the signal carried by `glyphTint` below.
        case "ether.fi":            return Color.fixed("#000000")   // the mark's own ground
        // Cash wears no bundled mark on purpose: it's an ether.fi product, so
        // its logo IS the one above, and two identical tiles sitting together
        // in the Wallet shelf would read as one app listed twice. The card
        // glyph says what it is; the field is a dark relative of the mark.
        case "ether.fi cash":       return Color.fixed("#12233f")
        case "kalshi":              return Color.fixed("#4fae7b")   // their green (matches the bundled logo)
        case "polymarket":          return Color.fixed("#1652f0")   // their official blue (the site's own mask-icon color, matching the bundled mark)
        case "opensea":             return Color.fixed("#2081e2")   // OpenSea's marine blue
        case "geckoterminal":       return Color.fixed("#7556f6")   // the gecko's purple (sampled from the bundled icon)
        case "tokens":              return Color.fixed("#0b0b0b")   // ink — the mark is a green chart on black (user ruling 2026-07-17; the near-zero saturation makes washHue nil, so the token sheet is pure ink ON PURPOSE — a gold/green wash fought the chart's own red)
        case "venice":              return Color.fixed("#0e2942")   // sampled from their deep-blue mark
        case "bankr":               return Color.fixed("#a78bfa")   // the terminal's lavender field (sampled from the bundled icon)
        case "voice":               return Color.fixed("#ff375f")   // the voice kind's own pink
        case "apple health":        return Color.fixed("#ff2d55")
        case "strava":              return Color.fixed("#fc4c02")
        case "todoist":             return Color.fixed("#e44332")
        case "slack":               return Color.fixed("#4a154b")
        case "raindrop":            return Color.fixed("#0db4e7")
        case "readwise":            return Color.fixed("#087bff")
        case "rss":                 return Color.fixed("#f26522")
        case "farcaster":           return Color.fixed("#855dcd")
        case "pinterest":           return Color.fixed("#e60023")
        case "spotify":             return Color.fixed("#1db954")   // their brand green — missing until now, so Spotify's icon tile and rain wash both fell back to gray/default blue
        case "apple music":         return Color.fixed("#fc3c44")   // Apple Music's coral-red mark
        case "bluesky":             return Color.fixed("#0285ff")
        case "snapchat":            return Color.fixed("#fffc00")   // their yellow — the field IS the mark (a white ghost sits on it), so the SF fallback's white glyph reads thin until the official icon is bundled at brand-snapchat
        case "nostr":               return Color.fixed("#9543dc")   // their purple (icon-sampled from the bundled mark)
        // The five newest seats, all with marks already bundled beside this and
        // none of them named here until now — so Stripe, PostHog, Grok,
        // OpenRouter and Linear fell to the default gray on every wash surface
        // (audit, 2026-07-31). Each is icon-sampled from its own bundled mark.
        case "stripe":              return Color.fixed("#635bff")   // their documented indigo; the bundled mark samples #6050f0 against it
        // PostHog's mark is the hedgehog on a white field, but unlike ChatGPT's
        // white-IS-the-identity case this is a logo-on-white lockup — the brand
        // is the orange. Their documented primary; the mark's own saturated
        // pixels sample #e03000–#f0b000 across the hedgehog.
        case "posthog":             return Color.fixed("#f54e00")
        case "cloudflare":          return Color.fixed("#f6821f")   // the cloud's orange (their documented brand orange; the bundled mark samples it)
        case "trello":              return Color.fixed("#1169df")   // the mark's own gradient at its midpoint, icon-sampled from the bundled asset (#2381fd → #0054c2)
        // Cursor's own brand page gives #000000, and the mark really is
        // monochrome — the Grok/X case, not a logo-on-black lockup. washHue
        // nils pure black, so the Cursor screens stay pure ink on purpose and
        // this only stops the tile falling back to gray.
        case "cursor":              return Color.fixed("#000000")
        // Sentry's documented purple. Their mark is the lantern in this
        // colour on white — the PostHog/Hugging Face shape (a logo-on-white
        // lockup where the brand is the mark), not the ChatGPT one where the
        // white field IS the identity.
        case "sentry":              return Color.fixed("#362d59")
        // Vercel is pure black by their own brand guidance, and the triangle
        // really is monochrome — the Cursor/Grok/X case, not a lockup.
        // washHue nils pure black, so the Vercel screens stay ink on purpose
        // and this only stops the tile falling back to gray.
        case "vercel":              return Color.fixed("#000000")
        case "pagerduty":           return Color.fixed("#04ac38")   // icon-sampled from the bundled mark's own field
        // npm's documented red. PyPI's blue is deliberately DIFFERENT rather
        // than a shared "package" colour — the two seats sit together in the
        // Work group, and a shared field plus a near-shared glyph would read
        // as one app listed twice.
        case "npm":                 return Color.fixed("#cb3837")
        case "pypi":                return Color.fixed("#3775a9")   // the python.org blue PyPI's own header uses
        // Grok's mark is pure black with ZERO saturated pixels — the X case
        // exactly (and xAI is X). washHue nils this, so the Grok screens stay
        // pure ink ON PURPOSE; the tile just stops falling back to gray.
        case "grok":                return Color.fixed("#000000")
        // OpenRouter is the Hyperliquid/ether.fi shape: a near-black ground
        // with one vivid accent. The ground is the tile (sampled), and the lime
        // carries the signal from `glyphTint`.
        case "openrouter":          return Color.fixed("#000010")
        case "linear":              return Color.fixed("#5e6ad2")   // their documented indigo; the bundled mark samples #5060d0
        // Hugging Face is the PostHog shape, not the ChatGPT one: a mark on a
        // white field where the brand is the mark's own colour, not the field.
        // Their documented yellow, which is also the single most common
        // saturated pixel in the bundled icon (86k of them) — sampled and
        // documented agreeing exactly, which is rare enough to note.
        case "hugging face":        return Color.fixed("#ffd21e")
        case "cal.com":             return Color.fixed("#292929")
        case "calendly":            return Color.fixed("#006bff")
        case "steam":               return Color.fixed("#1b2838")   // their dark navy
        case "obsidian":            return Color.fixed("#7c3aed")   // vault purple
        case "files":               return Color.fixed("#4aa8f0")   // iCloud blue — any iCloud-reachable folder
        case "dropbox":             return Color.fixed("#0061ff")   // their brand blue
        case "twitch":              return Color.fixed("#9146ff")
        // Instagram's mark is a gradient, and a flat fill has to pick one
        // point on it — the magenta reads as Instagram where the orange end
        // reads as any warm brand. Moot once `brand-instagram` is bundled;
        // this is what the SF fallback wears until then.
        case "instagram":           return Color.fixed("#e1306c")
        // TikTok's mark is two offset inks (cyan/magenta) over black, and a
        // flat fill has to pick one. The magenta carries the brand where the
        // cyan reads as any tech blue. Moot once `brand-tiktok` is bundled.
        case "tiktok":              return Color.fixed("#ee1d52")
        case "reddit":              return Color.fixed("#ff4500")
        case "youtube":             return Color.fixed("#ff0000")
        case "substack":            return Color.fixed("#ff6719")
        case "podcasts":            return Color.fixed("#8a2be2")   // Apple Podcasts purple
        case "contacts":            return Color.fixed("#34c759")   // Contacts green
        case "kindle":              return Color.fixed("#f2a900")   // Amazon/Kindle amber
        case "shopify":             return Color.fixed("#5e8e3e")   // Shopify's green
        case "deals":               return Color.fixed("#e0245e")   // a sale-tag crimson
        case "open food facts":     return Color.fixed("#7cb342")   // a fresh grocery green
        case "stocktwits":          return Color.fixed("#008fff")   // their azure (icon-sampled)
        case "bitrefill":           return Color.fixed("#002b28")   // their dark teal (icon-sampled)
        case "privacy":             return Color.fixed("#232320")   // their near-black (icon-sampled)
        case "coinbase":            return Color.fixed("#0052ff")   // their official brand blue
        case "kraken":              return Color.fixed("#773bf5")   // their mascot's purple (icon-sampled)
        case "binance":             return Color.fixed("#0b0e11")   // their near-black app-icon field
        case "gemini exchange":     return Color.fixed("#ff6511")   // their orange (sampled from the official app icon)
        case "eth validators":      return Color.fixed("#627eea")   // Ethereum's own brand blue-purple
        case "1claw":               return Color.fixed("#990029")   // their crimson (docs-sampled)
        case "homekit":             return Color.fixed("#8e8e93")   // the accessory kind's own gray (KindGlyph.swift)
        default:                    return nil
        }
    }

    /// The brand hue normalized for the WASH surfaces — the app detail page,
    /// the bridge setup header, the token quick sheet (the feed AND the thing
    /// sheet dropped their washes, user ruling 2026-07-18: full ink). Raw
    /// brand hexes aren't a designed ramp: RGB-mixing them toward black
    /// shifted yellows to olive and browns, and left the near-black marks
    /// (Steam, Venice) as colorless smudges (user, 2026-07-13). Still one
    /// formula, no per-hue tables — keep the hue angle, pin saturation into
    /// a vivid band, and let the brand's OWN brightness through (user ruling
    /// 2026-07-13: the old 0.40–0.62 brightness band read as a deep muddy
    /// wash — the bleed should pop like the theme backgrounds' bright
    /// primaries and the app marks it inherits; only a floor for the darkest
    /// saturated marks and a ceiling shy of neon). Near-neutral marks
    /// (X, Cal.com, ChatGPT) return nil: no honest hue, no wash — the same
    /// ruling as `brandHue`'s nil. Identity uses (icons, the connect bloom)
    /// keep the true `brandHue`.
    static func washHue(for source: String) -> Color? {
        guard let brand = brandHue(for: source) else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(brand).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s >= 0.15 else { return nil }
        return Color(hue: h, saturation: max(s, 0.65),
                     brightness: min(max(b, 0.60), 0.95))
    }

    /// A brand hue's perceptual luminance (ITU-R BT.709), 0 (black) to 1
    /// (white) — used to catch hues too dark to read as a filled surface.
    private static func luminance(of color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    /// The brand hue as a CARD fill — a near-black brand mark (X's, #000000)
    /// would render its story card as an empty void, so a too-dark hue lifts
    /// toward the app tint instead of showing raw (design audit fix,
    /// 2026-07-12). A near-WHITE mark (ChatGPT's #ffffff) is the mirror
    /// failure — white card, white text, nothing visible (user report
    /// 2026-07-14) — and a neutral mark has no honest hue to show, so it
    /// takes the tint card outright, same ground the Pair card wears. Icons
    /// and other identity uses keep the true `brandHue`; only this
    /// fill-legibility path substitutes.
    static func legibleCardFill(for source: String) -> Color {
        let hue = brandHue(for: source) ?? DS.tint
        let lum = luminance(of: hue)
        if lum < 0.12 { return hue.mix(with: DS.tint, by: 0.6) }
        if lum > 0.90 { return DS.tint }
        return hue
    }
}
