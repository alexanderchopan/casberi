import SwiftUI

// `AppIconTile` lived here until 2026-08-26 — a squircle that drew the source's
// FIRST LETTER on a brand fill, unconditionally, with a hairline border. It had
// no call sites left (`BridgeIcon` has drawn the real bundled asset since the
// catalog shipped, falling back to an SF glyph rather than a letter), so it was
// a letter-glyph stand-in nothing could reach and a hairline the design law
// forbids. The colour table below is what was actually being used — `KindGlyph`
// reads it — so it stays.

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
        // Anthropic's one brand rust — Claude Code is the same company's mark
        // in a terminal, not a separate identity (found missing auditing the
        // pour rules, 2026-08-24: its setup screen called `bridgeSetupWash`
        // and got nothing, the exact "eight seats furnish nothing" shape of
        // bug this file's own registry checks exist to catch elsewhere).
        case "claude code":         return Color.fixed("#d97757")
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
        case "markets":             return Color.fixed("#4fae7b")   // Kalshi's green — matches the catalog's own Markets-category glyph (its Kalshi exemplar), so the folded chip and the category chip agree
        case "peer":                return Color.fixed("#4b47f6")   // an indigo in their family — approximate; re-sample when bundling the official mark
        case "gnosis pay":          return Color.fixed("#4830c0")   // the owl's indigo (icon-sampled from the bundled mark)
        case "apple wallet":        return Color.fixed("#1d1d1f")   // Apple Card graphite — the titanium card's own near-black
        case "safe":                return Color.fixed("#12ff80")   // Safe{Wallet}'s green (icon-sampled from the bundled mark)
        case "privacy pools", "0xbow privacy pools":
                                    return Color.fixed("#ffffff")   // 0xBow's mark is black on white (bundled) — the white field is the identity, like ChatGPT's; zero saturation means washHue nils, so the page stays pure ink on purpose
        // Railgun's bundled mark sits on a near-black field with the barest
        // blue tint (measured 2026-08-24: max saturation ~0.23 at very low
        // brightness) — near-zero saturation, so `washHue` nils it the same
        // way Hyperliquid's dark ground does; the true field still beats a
        // fallback gray for `brandHue`'s other consumers (icon tile, card
        // fill). Fittingly near-neutral for the one bridge whose whole point
        // is hiding an identity (§268).
        case "railgun":             return Color.fixed("#1a1a24")
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
        case "telegram":            return Color.fixed("#229ed9")   // their blue, and the tile behind the bundled brand-telegram mark
        case "nostr":               return Color.fixed("#9543dc")   // their purple (icon-sampled from the bundled mark)
        // The five newest seats, all with marks already bundled beside this and
        // none of them named here until now — so Stripe, PostHog, Grok,
        // OpenRouter and Linear fell to the default gray on every wash surface
        // (audit, 2026-07-31). Each is icon-sampled from its own bundled mark.
        case "stripe":              return Color.fixed("#635bff")   // their documented indigo; the bundled mark samples #6050f0 against it
        case "polar":               return Color.fixed("#3619cc")   // "Ether" — polar.sh/brand's one accent in an otherwise monochrome system
        // PostHog's mark is the hedgehog on a white field, but unlike ChatGPT's
        // white-IS-the-identity case this is a logo-on-white lockup — the brand
        // is the orange. Their documented primary; the mark's own saturated
        // pixels sample #e03000–#f0b000 across the hedgehog.
        case "posthog":             return Color.fixed("#f54e00")
        case "cloudflare":          return Color.fixed("#f6821f")   // the cloud's orange (their documented brand orange; the bundled mark samples it)
        // Walletbeat's own coral, taken from their brand SVGs
        // (`resources/branding/icon_dark.svg`, `#f96681`; their wordmark lockup
        // samples `#fa6682`). The bundled mark is their real icon — a wallet
        // with a heart and a flower — rather than the invented pulse line this
        // seat shipped with for an afternoon, and the hue is theirs rather than
        // a purple picked to look distinct from the Wallet group's blue.
        case "walletbeat":          return Color.fixed("#f96681")
        // L2BEAT's own heart, taken from their site icon (`static/icon.svg`,
        // `.heart { fill: #f9347b }`; their dark-mode variant is `#bd114f`).
        // Uncomfortably close to Walletbeat's coral above and kept anyway: both
        // are the registry's REAL brand colour, and picking a different hue to
        // separate two seats is the invented-brand-colour move `AssetMark`
        // refuses. They never sit adjacent — one is a Wallet venue and this is a
        // Markets one — and the marks themselves are nothing alike.
        case "l2beat":              return Color.fixed("#f9347b")

        // Circle's mark is a logo-on-white lockup (the PostHog/Hugging Face
        // shape), so the brand is the mark, not the field — and the mark is a
        // gradient running teal → blue → periwinkle, so a flat fill has to pick
        // one point on it (Trello's case). The midpoint blue, icon-sampled: the
        // teal end reads as any mint brand and the periwinkle end as any purple.
        case "circle x402":         return Color.fixed("#60b0f0")
        case "trello":              return Color.fixed("#1169df")   // the mark's own gradient at its midpoint, icon-sampled from the bundled asset (#2381fd → #0054c2)
        // Cursor's own brand page gives #000000, and the mark really is
        // monochrome — the Grok/X case, not a logo-on-black lockup. washHue
        // nils pure black, so the Cursor screens stay pure ink on purpose and
        // this only stops the tile falling back to gray.
        // iOS system blue — NOT the App Store icon's blue, and the difference
        // is the point (user, 2026-08-06: "we can't use their icon"). This
        // seat carries no bundled mark at all, so the hue and the glyph
        // together are its whole identity; borrowing the store icon's exact
        // gradient would be imitating the mark by other means. The system
        // accent says "Apple platform" without standing in for a trademark.
        case "app store connect":   return Color.fixed("#0a84ff")
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
        // Atlassian's documented Jira blue — no bundled mark yet, so the hue
        // and the glyph together are this seat's whole identity until one
        // lands (the App Store Connect/Cursor case: a real color even without
        // an asset, rather than falling to the gray default).
        case "jira":                return Color.fixed("#0052cc")
        // npm's documented red. PyPI's blue is deliberately DIFFERENT rather
        // than a shared "package" colour — the two seats sit together in the
        // Work group, and a shared field plus a near-shared glyph would read
        // as one app listed twice.
        // GitLab's own documented orange — their bundled fox mark's tail runs
        // orange into red, and this is the primary end of it (icon-sampled).
        // Missing until now, found auditing the pour rules 2026-08-24: its
        // catalog offer sits right beside GitHub in the Work group and had no
        // wash where GitHub's correctly nils (below) — the two read as one
        // rule until you actually connect one.
        case "gitlab":              return Color.fixed("#fc6d26")
        // GitHub's mark is the Octocat on a near-BLACK field — measured
        // (2026-08-24): zero saturated pixels, dominant sample near-black —
        // the Vercel/Grok/Cursor case exactly (a real ground colour, not a
        // logo-on-white lockup). `washHue` nils this on purpose; `brandHue`
        // still wants the true field so a fallback-gray tile isn't invented
        // for an app that has a real one.
        case "github":              return Color.fixed("#000000")
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
        // Notion's mark is a black "N" block on a near-WHITE field — measured
        // (2026-08-24): dominant sample near-white, the ChatGPT/0xBow case
        // (the white field IS the identity, not a logo-on-white lockup).
        // `washHue` nils this on purpose; `brandHue` still wants the true
        // field so a fallback-gray tile isn't invented for an app with one.
        case "notion":              return Color.fixed("#ffffff")
        // Hugging Face is the PostHog shape, not the ChatGPT one: a mark on a
        // white field where the brand is the mark's own colour, not the field.
        // Their documented yellow, which is also the single most common
        // saturated pixel in the bundled icon (86k of them) — sampled and
        // documented agreeing exactly, which is rare enough to note.
        case "hugging face":        return Color.fixed("#ffd21e")
        // Radicle's own blue, taken from its mark (prd §400). The bundled
        // artwork sits on a near-black field, so the HUE is the blue rather
        // than the background — a gray "app" default here would read as a
        // seat whose art failed to load (report 2026-08-03).
        case "radicle":             return Color.fixed("#5555ff")
        // Altana's own blue, sampled from its mark (prd §403). The mark is
        // three fields — blue, yellow, orange — and the BLUE is the largest
        // and the one that reads as the brand at chip size; picking the
        // orange would make the seat read as an alert, which is precisely
        // the wrong thing for a room about keys.
        case "altana":              return Color.fixed("#3565e3")
        // Base's own documented blue — no bundled mark (the App Store
        // Connect/Cursor/Jira case: a real colour even without an asset).
        // vibenet is Base's own devnet, so the hue says whose network this
        // is rather than inventing an "experimental" colour of its own.
        case "base vibenet":        return Color.fixed("#0052ff")
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
        // CardPointers' own violet, icon-sampled from the bundled mark
        // (found missing auditing the pour rules, 2026-08-24 — its product
        // and setup pages both called for a wash and got the gray default).
        case "cardpointers":        return Color.fixed("#9d4eec")
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
    /// toward a neutral instead of showing raw (design audit fix,
    /// 2026-07-12). A near-WHITE mark (ChatGPT's #ffffff) is the mirror
    /// failure — white card, white text, nothing visible (user report
    /// 2026-07-14) — and a neutral mark has no honest hue to show, so it
    /// takes a plain neutral card outright. Was the app tint until
    /// 2026-08-10: a card with no honest brand color to show fell back to
    /// blue as if THAT were the brand, the same fake-identity problem
    /// `TokenHue` had for an unknown token — now it falls back to the same
    /// neutral gray the app's other illustrative fills use (`GenVoiceTile`'s
    /// waveform, `GenPhotoTile`'s placeholders), which reads as "we don't
    /// know" rather than "this app is blue." Icons and other identity uses
    /// keep the true `brandHue`; only this fill-legibility path substitutes.
    static func legibleCardFill(for source: String) -> Color {
        guard let hue = brandHue(for: source) else { return DS.gray200 }
        let lum = luminance(of: hue)
        if lum < 0.12 { return hue.mix(with: DS.gray200, by: 0.6) }
        if lum > 0.90 { return DS.gray200 }
        return hue
    }

    /// A feed row's card, in its source's own colour (2026-08-15, user ruling:
    /// "what if each row was a colored card from its source").
    ///
    /// THE INK COMES WITH THE FILL, and that pairing is the whole reason this
    /// is one type rather than two calls. A saturated card decides what can be
    /// read on it: Farcaster's purple needs the white ramp, Hugging Face's
    /// yellow and Snapchat's need the black one, and a caller that fetched the
    /// fill and forgot the ink would render white-on-yellow — legible in the
    /// simulator's dark theme, invisible in the light one, and caught by
    /// nothing (a contrast failure renders perfectly, `legibleInk`'s own
    /// lesson).
    ///
    /// `ink` is nil for the neutral fallback ON PURPOSE. `legibleCardFill`
    /// answers `DS.gray200` for a source with no honest hue, and that token is
    /// already adaptive — so the page's own ramp is correct on it in both
    /// themes, and pinning a scheme there would be the one row that ignores
    /// the theme.
    struct RowSkin {
        let fill: Color
        /// The ramp that reads on `fill`; nil keeps the ambient one.
        let ink: ColorScheme?
    }

    /// Cached per source — `brandHue` is a switch over 85 cases and the ink
    /// decision costs a `UIColor` round trip, both of which a feed body pass
    /// would otherwise pay once per visible row, every pass. That is the
    /// 2026-08-13 latency lesson exactly (the source rail resolving its chips
    /// four to five times per body pass), paid before it is measured this time.
    /// Main-actor because the feed is, and because a static cache with no
    /// isolation is the other kind of bug.
    @MainActor private static var rowSkinCache: [String: RowSkin] = [:]

    @MainActor
    static func rowSkin(for source: String) -> RowSkin {
        if let hit = rowSkinCache[source] { return hit }
        let skin = computeRowSkin(for: source)
        rowSkinCache[source] = skin
        return skin
    }

    /// A WASH, NOT A FILL (2026-08-15, the night's third and final form —
    /// user, seeing the bright version live: "it all looks vibecoded now").
    ///
    /// The arc, kept so nobody walks it again: raw brand hexes first (read as
    /// different intensities — `washHue`'s own "raw brand hexes aren't a
    /// designed ramp" lesson, relearned), then one solved luminance register
    /// (uniform, and uniformly LOUD — a wall of equally-weighted colour
    /// slabs in which provenance shouted from every row and colour stopped
    /// being information anywhere). What ships is the option my own feed
    /// mockups recommended as "the livable version": the source's hue at
    /// ~14% as the card's ground, the source NAME in the hue's bright form
    /// (`legibleInk`, already on every row header), and the words on the
    /// page's own ink ramp. Provenance still reads at arm's length; the row
    /// is content again; and the full-strength register survives where one
    /// bright object earns it (the wallet hero, the brief's lede card) via
    /// `deckFill` below.
    ///
    /// `washHue` and not the raw brand: it pins saturation into the vivid
    /// band and lets the brand's own brightness through, so the washes stay
    /// even with each other — the 14% is doing the quieting, the solver is
    /// doing the evenness. No pinned ink ever again: a 14% ground changes no
    /// contrast decision, so the ambient ramp is correct on every card in
    /// both themes, and the neutral marks (X, ChatGPT — `washHue`'s nil)
    /// take the faint neutral fill so the grammar stays one-card-per-row.
    private static func computeRowSkin(for source: String) -> RowSkin {
        guard let wash = brandHue(for: source).flatMap({ washHue2($0) }) else {
            return RowSkin(fill: DS.fillFaint, ink: nil)
        }
        return RowSkin(fill: wash.opacity(0.14), ink: nil)
    }

    /// `washHue`'s normalization for a hue already in hand — split out so the
    /// row skin and the by-source `washHue` share one formula.
    private static func washHue2(_ brand: Color) -> Color? {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(brand).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s >= 0.15 else { return nil }
        return Color(hue: h, saturation: max(s, 0.65),
                     brightness: min(max(b, 0.60), 0.95))
    }

    /// The register itself, callable for ANY identity hue — the feed's row
    /// cards and the brief's section cards go through this one solver, so the
    /// two surfaces can never drift to different weights (2026-08-15). Nil for
    /// a near-neutral hue (`washHue`'s own s < 0.15 bar): no honest colour, no
    /// card, and the caller falls back to its neutral surface. The result is
    /// always the DARK register, so a caller painting it pins `.dark` on the
    /// subtree's `colorScheme` — the fill and the ink are one decision.
    static func deckFill(for hue: Color) -> Color? {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hue).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s >= 0.15 else { return nil }

        let sat = min(max(Double(s), 0.60), 0.85)
        // THE ONE DIAL for how loud the whole surface is. 0.12 puts every card
        // at ~6.2:1 under white ink — deeper than the 0.15 first cut, which
        // the user still read as "a bit too bright" (2026-08-15). Increase
        // Contrast takes it to 0.10 (~7.0:1), the same figure `textTertiary`
        // climbs to under that setting, so the person who asked for contrast
        // gets it from the ground as well as the ink.
        let target = ContrastStore.shared.increased ? 0.10 : 0.12
        var lo = 0.08, hi = 1.0
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            let (r, g, bl) = rgbComponents(hue: Double(h), saturation: sat, brightness: mid)
            if wcagLuminance(r, g, bl) < target { lo = mid } else { hi = mid }
        }
        return Color(hue: Double(h), saturation: sat, brightness: (lo + hi) / 2)
    }

    /// WCAG relative luminance — sRGB channels gamma-LINEARIZED, which is the
    /// only form a contrast ratio may be computed from.
    ///
    /// Deliberately NOT the same function as `luminance(of:)` above, and the
    /// two must not be unified: that one is a plain weighted sum over
    /// gamma-ENCODED channels, and `legibleCardFill`'s 0.12/0.90 thresholds
    /// were tuned against its numbers — linearizing it would silently re-tune
    /// a shipped card rule while every call site still compiled. This one is
    /// read only by `legibleInk`, where 4.5:1 is a real WCAG figure and has to
    /// be arrived at the way WCAG defines it.
    private static func wcagLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// HSB → RGB in plain arithmetic. `Color(hue:saturation:brightness:)` would
    /// mean a `UIColor` round-trip per probe, and `legibleInk` probes up to ten
    /// times per row — this keeps the solve to float math on the feed's hot
    /// path (the 2026-08-13 latency lesson: the source rail resolving chips
    /// several times per body pass).
    private static func rgbComponents(hue h: Double, saturation s: Double,
                                      brightness v: Double) -> (Double, Double, Double) {
        let c = v * s
        let hp = (h * 6).truncatingRemainder(dividingBy: 6)
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let base: (Double, Double, Double)
        switch hp {
        case ..<1: base = (c, x, 0)
        case ..<2: base = (x, c, 0)
        case ..<3: base = (0, c, x)
        case ..<4: base = (0, x, c)
        case ..<5: base = (x, 0, c)
        default:   base = (c, 0, x)
        }
        return (base.0 + m, base.1 + m, base.2 + m)
    }

    /// A brand hue as INK ON THE PAGE — the source's own color, moved until it
    /// clears the contrast bar the text ramp already meets, or nil when it
    /// can't. `nil` means "no honest tint here", and every caller falls back to
    /// the neutral ramp.
    ///
    /// WHY THIS ISN'T `washHue` (2026-08-14). `washHue` is built for a WASH —
    /// a field behind content — so it floors brightness at 0.60, which as INK
    /// is unreadable on a light page: measured across the 85 hues that have
    /// one, raw `washHue` clears 4.5:1 for 29 of them on the light Default page
    /// and 51 on the dark one. Snapchat's yellow lands at 1.1:1. Painting the
    /// row's smallest text in it would re-commit the exact failure that took
    /// the color OUT of this slot on 2026-07-30 (`BandRow.labelInk` records it:
    /// the old `ProjectHue` ink measured ~3.4:1 at `label11`).
    ///
    /// THE ONE RULE: move away from the page until the ratio is met, and show
    /// nothing if it can't be. On a dark page the ink brightens and lets
    /// saturation fall toward white — a deep hue can't get bright on its own,
    /// since pure blue tops out at 0.07 luminance no matter how bright. On a
    /// light page it darkens at full saturation, which deepens the hue instead
    /// of washing it out. Both stop at an IDENTITY FLOOR (saturation 0.25,
    /// brightness 0.35): past it the result is gray-with-a-tinge rather than
    /// the brand, and painting that would be the decoration §8's color law
    /// forbids — so it returns nil and the caller stays neutral.
    ///
    /// Vivid themes need no special case and get none. Measured at 4.5:1: the
    /// Default page tints all 85, while the saturated dark backgrounds tint
    /// 0–60 and fall to the neutral ramp for the rest — which is the same
    /// answer `DS.textTertiary`'s own `vividBackground` branch already gives
    /// ("the quiet ramp washes out against loud color"), arrived at by
    /// measurement rather than by a second hand-maintained rule.
    ///
    /// Increase Contrast raises the bar to 7.0:1, the figure `textTertiary`
    /// climbs to, so the tint can never be the one thing that ignores the ask.
    static func legibleInk(for source: String) -> Color? {
        // A photograph has no single luminance, so no ratio can be promised
        // against it — and its scrim is a gradient, so even a sampled one
        // would be true at one end of the screen only.
        guard ThemeStore.shared.backgroundPhoto == nil else { return nil }
        guard let brand = brandHue(for: source) else { return nil }

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(brand).getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0, pa: CGFloat = 0
        UIColor(DS.themedPage).getRed(&pr, green: &pg, blue: &pb, alpha: &pa)

        guard let ink = solveInk(hue: Double(h), saturation: Double(s), brightness: Double(b),
                                 pageLuminance: wcagLuminance(Double(pr), Double(pg), Double(pb)),
                                 bar: ContrastStore.shared.increased ? 7.0 : 4.5)
        else { return nil }
        return Color(hue: ink.hue, saturation: ink.saturation, brightness: ink.brightness)
    }

    /// `legibleInk`'s arithmetic, with every environment read lifted out — the
    /// theme, the contrast setting and the brand table are the caller's job, so
    /// what remains is a pure function of five Doubles and can be compiled and
    /// checked without a simulator (`scripts/legible-ink-selftest.sh`). That
    /// split is the point: a contrast failure renders perfectly, so a build and
    /// a screenshot both pass it, which is precisely how the ink this replaces
    /// shipped at ~3.4:1 and stayed there until somebody measured it.
    static func solveInk(hue: Double, saturation: Double, brightness: Double,
                         pageLuminance: Double,
                         bar: Double) -> (hue: Double, saturation: Double, brightness: Double)? {
        // No honest hue, no tint — `washHue`'s own bar, so a near-neutral mark
        // (X's black, ChatGPT's white) is neutral everywhere it is read.
        guard saturation >= 0.15 else { return nil }

        func meets(_ sat: Double, _ bright: Double) -> Bool {
            let (r, g, b) = rgbComponents(hue: hue, saturation: sat, brightness: bright)
            let lum = wcagLuminance(r, g, b)
            return (max(lum, pageLuminance) + 0.05) / (min(lum, pageLuminance) + 0.05) >= bar
        }

        let satFloor = 0.25, brightFloor = 0.35
        let startSat = max(saturation, 0.65)               // washHue's saturation floor
        let startBright = min(max(brightness, 0.60), 0.95) // washHue's brightness clamp

        // Brighten (a dark page): brightness pinned, saturation is what moves.
        if meets(startSat, 1) { return (hue, startSat, 1) }
        if meets(satFloor, 1) {
            var pass = satFloor, fail = startSat
            for _ in 0..<8 {
                let mid = (pass + fail) / 2
                if meets(mid, 1) { pass = mid } else { fail = mid }
            }
            return (hue, pass, 1)
        }
        // Darken (a light page): saturation held, brightness is what moves.
        if meets(startSat, startBright) { return (hue, startSat, startBright) }
        if meets(startSat, brightFloor) {
            var pass = brightFloor, fail = startBright
            for _ in 0..<8 {
                let mid = (pass + fail) / 2
                if meets(startSat, mid) { pass = mid } else { fail = mid }
            }
            return (hue, startSat, pass)
        }
        return nil
    }
}
