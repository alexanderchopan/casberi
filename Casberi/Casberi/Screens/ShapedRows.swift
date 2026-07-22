import SwiftUI
import Photos

/// Shaped Feed rows (docs/handoff-shaped-feeds.md) — when one source is in
/// force the feed takes that source's native shape; "All" renders kind-aware
/// rows that borrow a whisper of their source's shape. These are the row
/// views; FeedScreen dispatches them and keeps day groups, swipes, pins, the
/// sheet, and the write-confirm ruling intact around them.
///
/// Discipline (the doc's rule 2): rows keep height and rhythm. Only
/// `.approval` breaks rhythm — the consent card.

// MARK: - The band row (B2b ruling 2026-07-06)

/// THE feed row: one line on a field of its kind's color. The icon says
/// where it came from, the wash says what it is, the right stack carries
/// time over the project name — plain tinted text, never a chip (a chip
/// means tappable; this is a label). Every kind, same anatomy.
struct BandRow: View {
    let thing: Thing
    var emphasized: Bool = false
    /// A perishable thing that is live RIGHT NOW (a Twitch stream) — the
    /// right stack carries a green dot + "Live" instead of a timestamp.
    /// Honest by construction: the caller derives it from the source's own
    /// current-live set, never from the row's age.
    var live: Bool = false
    /// The wallet room's ledger reading (prd §158, 2026-07-21): the moved
    /// amount leaves the sentence and becomes a right-aligned figure, so a
    /// stream of transactions scans as a column of magnitudes instead of a
    /// column of prose. Opt-in — only the Wallet shape asks for it.
    ///
    /// The figure is the ASSET amount ("+0.4 ETH"), never a dollar value:
    /// nothing on a landed transfer records what it was worth at the time, and
    /// pricing a past transfer at today's rate would be a number the record
    /// can't support. It's the same fact the title used to carry, moved — not
    /// a second fact invented for the column.
    var moneyColumn: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var done: Bool { thing.mark == .done }

    /// The signed amount for the money column, when this row has one. Only
    /// directional transfers qualify: a swap and a self-move have two legs and
    /// no single signed number, so they keep their full sentence and no column
    /// (`transferDirection` is nil for both, by the field's own contract).
    private var moneyAmount: (text: String, received: Bool)? {
        guard moneyColumn, let direction = thing.transferDirection,
              let amount = thing.transferAmount, !amount.isEmpty,
              direction == "received" || direction == "sent" else { return nil }
        let received = direction == "received"
        return ("\(received ? "+" : "−")\(amount)", received)
    }

    /// The trailing label — a project tag normally, or which wallet a
    /// transaction came from when more than one is watched (2026-07-09):
    /// same slot, same voice, so two watched wallets don't read as one
    /// indistinguishable stream.
    private var project: String? {
        if let tag = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) { return tag }
        // Which watched wallet a transaction came from, when more than one is
        // watched — keyed on the FIELD (walletAddress), not the source name,
        // so every wallet-riding seat (Wallet, Peer, the next one) carries
        // the label without joining a case list (review 2026-07-17).
        if let wallet = WalletStore.shared.label(forAddress: thing.walletAddress) {
            return wallet
        }
        switch thing.source {
        // WHY a post is here beats WHO posted it in this slot (2026-07-16): a
        // liked cast, a channel cast, and your own post used to read
        // identically, and the row already leads with the author's FACE — so
        // the word that differentiates is "Liked", "/design", "Mentions you",
        // not the handle a second time. A post with no such reason (an account
        // you watch simply posted) falls through to the handle rule, unchanged.
        case "Bluesky", "Farcaster":
            if let why = SocialThread.contextLabel(for: thing) { return why }
            return thing.source == "Bluesky"
                ? BlueskyStore.shared.rowLabel(for: thing.authorHandle)
                : FarcasterStore.shared.rowLabel(for: thing.authorHandle)
        // The publisher names itself in the trailing slot — BBC News,
        // TechCrunch — the icon's word twin, the way a social row names its
        // account. Empty on rows that landed before the name was captured.
        case "RSS":       let name = thing.authorHandle ?? ""; return name.isEmpty ? nil : name
        // GitHub carries starCount/repoLanguage but rendered as a plain band
        // like any other link — the contribution hero above the feed was the
        // only place either fact showed (2026-07-21 enrichment, matching the
        // grammar RSS/social/Wallet already use in this same slot).
        case "GitHub":
            let language = thing.repoLanguage ?? ""
            let stars = (thing.starCount).map { "★\(GitHubStarContent.compact($0))" } ?? ""
            let parts = [language, stars].filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        // Peer rides the Wallet address (the wallet-label check above already
        // covers the >1-watched-wallet case); with just one wallet watched
        // that slot sits empty, so a single-wallet Peer row instead names the
        // fiat rail — "Cash App", "Venmo" — parsed off the title's own fixed
        // "… with <method> on Peer" template (`PeerBridge.title(for:story:)`
        // is the only place that string is built, so the parse is exact, not
        // a heuristic). No structured field carries the method separately.
        case "Peer":
            guard let start = thing.title.range(of: " with "),
                  let end = thing.title.range(of: " on Peer", range: start.upperBound..<thing.title.endIndex)
            else { return nil }
            return String(thing.title[start.upperBound..<end.lowerBound])
        default:          return nil
        }
    }

    /// A social post leads with its author's avatar — a face is always the
    /// identity, whether you follow one person or ten (2026-07-10, user: "I
    /// thought Farcaster/Bluesky showed the avatar of the person you follow").
    /// Unlike the @handle LABEL (redundant with one account, so it stays gated
    /// to >1), the avatar is never redundant — it's who posted.
    private var identityAvatarURL: String? {
        guard let avatar = thing.authorAvatarURL, !avatar.isEmpty else { return nil }
        return (thing.source == "Bluesky" || thing.source == "Farcaster") ? avatar : nil
    }

    /// An RSS row leads with its PUBLISHER's mark — Reuters, a blog — the way
    /// a social post leads with a face: where it came from, always shown, so
    /// one glance separates the sources in a mixed feed. The article's own
    /// image (previewImageURL) then rides AFTER the title, the "both" pattern
    /// posts already use. The icon URL is stamped onto authorAvatarURL at
    /// ingest (the feed's channel logo, else the site's favicon); a squircle,
    /// not a circle — a logo, not a face. nil (or a dead URL) keeps the RSS
    /// glyph.
    private var publisherIconURL: String? {
        guard thing.source == "RSS", let icon = thing.authorAvatarURL,
              !icon.isEmpty else { return nil }
        return icon
    }

    /// The address a Wallet row draws an identicon for — the visual twin of
    /// the address label, shown only when more than one wallet is watched.
    private var identiconAddress: String? {
        guard thing.source == "Wallet", WalletStore.shared.addresses.count > 1,
              let addr = thing.walletAddress, !addr.isEmpty else { return nil }
        return addr
    }

    /// A mail row's sender — email carries no avatar, so the row leads with
    /// an initial circle instead (2026-07-10; what Mail apps themselves do).
    /// New rows carry the sender in authorHandle; older rows stored it only
    /// as "From …" content, parsed here so they get their circle without a
    /// migration.
    private var mailSender: String? {
        guard thing.kind == .mail else { return nil }
        if let from = thing.authorHandle, !from.isEmpty { return from }
        if thing.content.hasPrefix("From ") {
            let from = String(thing.content.dropFirst("From ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return from.isEmpty ? nil : from
        }
        return nil
    }

    /// Events carry their clock time inline — the left time column died.
    ///
    /// A money-column row drops the amount from its sentence ("Received 0.4
    /// ETH from jesse.eth" → "Received from jesse.eth") because the column now
    /// says it — printing it twice was the first thing that looked wrong on
    /// screen. Display only: `thing.title` is untouched, so search, Spotlight,
    /// and the sheet all still read the full sentence.
    private var titleText: String {
        if thing.kind == .event {
            return "\(thing.title) · \(thing.capturedAt.formatted(date: .omitted, time: .shortened))"
        }
        if moneyAmount != nil, let amount = thing.transferAmount,
           let range = thing.title.range(of: " \(amount)") {
            return thing.title.replacingCharacters(in: range, with: "")
        }
        return thing.title
    }

    /// The project writes in ITS color (V3b): stable per name, same hue on
    /// every surface. Light mode pulls it toward black for contrast.
    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    private var countdown: String? {
        guard emphasized else { return nil }
        let mins = Int(thing.capturedAt.timeIntervalSinceNow / 60)
        guard mins >= 0 else { return nil }
        return mins < 60 ? "in \(max(1, mins)) min" : "in \(mins / 60)h"
    }

    var body: some View {
        // Top-aligned so a wrapping title grows DOWNWARD from the first
        // line — the icon and the time/project stack stay pinned beside
        // that line, not floated to the row's vertical center (ruling
        // 2026-07-09: two lines, never one, never unbounded).
        HStack(alignment: .top, spacing: DS.Space.s3) {
            // A thing with its own image leads with the image, not a glyph —
            // it IS the point of the row (a pin's photo, a screenshot's
            // capture). Same 26pt leading slot, so the row keeps its height
            // and rhythm (shaped-feeds rule 2). Remote pins load from a URL;
            // screenshots from their local PHAsset via PhotoWell. Twitch
            // frames are perishable — they render only while the source's
            // live set says the stream is on (honesty at render: the model
            // may still hold a frame a failed or disconnected sync never
            // saw end).
            Group {
                if let avatar = identityAvatarURL {
                    // Whose post this is, when several accounts are followed.
                    RemoteThumb(urlString: avatar, size: 26, fallback: thing.source,
                                circular: true)
                } else if let addr = identiconAddress {
                    WalletBlockie(address: addr, size: 26)
                } else if let sender = mailSender, SenderInitial.letter(of: sender) != nil {
                    SenderInitial(sender: sender, size: 26)
                } else if let publisher = publisherIconURL {
                    // Where the story is FROM leads the row; its picture rides
                    // after the title (below), like a post's attached image.
                    RemoteThumb(urlString: publisher, size: 26, fallback: thing.source)
                } else if let image = thing.previewImageURL, !image.isEmpty,
                          thing.source != "Twitch" || live {
                    // A token's coin logo is circular in the fat row — keep the
                    // same shape while its pulse hasn't landed yet, so the coin
                    // doesn't morph squircle→circle when the price arrives.
                    RemoteThumb(urlString: image, size: 26, fallback: thing.source,
                                perishable: thing.source == "Twitch",
                                circular: thing.source == "Tokens")
                } else if thing.kind == .screenshot, thing.sourceRef != nil {
                    PhotoWell(thing: thing, size: 26)
                } else {
                    BridgeIcon(name: thing.source, size: 26)
                }
            }
            // Wallet safety warning (2026-07-20; any flag since prd §160,
            // 2026-07-21) — the scam works at exactly this glance (a
            // familiar-looking row, casually trusted), so the flag rides the
            // icon itself, not just the opened sheet (ThingSheetView's
            // `securityWarning`, same glyph and color at a bigger scale). A
            // spoofed symbol earns the badge for the same reason a poisoned
            // address does: the row is where the lie is read.
            .overlay(alignment: .bottomTrailing) {
                if thing.isFlagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DS.destructive)
                        .padding(3)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
            }
            Text(titleText)
                .dsText(.body17)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                // Two lines everywhere (ruling 2026-07-09) — except Kalshi,
                // whose title IS the full market question ("Will the Chiefs
                // win the Super Bowl?"), not a headline, and was clipping
                // mid-word at 2 lines (user, 2026-07-13).
                .lineLimit(thing.source == "Kalshi" ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // A post with a photo shows BOTH (ruling 2026-07-10: "keep faces
            // always but show pictures too"): the avatar keeps the leading
            // slot — who — and the attached image rides here before the
            // time — what. Same 26pt scale, so the band's rhythm holds. An
            // RSS row does the same: publisher mark leads, the story's own
            // image rides here.
            if identityAvatarURL != nil || publisherIconURL != nil,
               let art = thing.previewImageURL, !art.isEmpty {
                RemoteThumb(urlString: art, size: 26, fallback: thing.source)
            }
            VStack(alignment: .trailing, spacing: 1) {
                // The ledger figure leads the trailing stack (prd §158) —
                // rounded and tabular so a run of rows lines up on the decimal.
                // Green only on a receive: money arriving is the one state
                // worth coloring, and a send in red would read as an error.
                // A spoofed symbol (prd §160) keeps its figure — the app never
                // hides what landed — but loses the green. The confirm color
                // is this row's loudest claim, and "money arrived" is exactly
                // the claim a fake USDC is making; celebrating it would make
                // the design a party to the lie. Same corollary as a flat
                // change having no direction: unearned status isn't painted.
                if let money = moneyAmount {
                    Text(money.text)
                        .dsText(.price16)
                        .monospacedDigit()
                        .foregroundStyle(money.received && !thing.hasSecurityFlag("symbol")
                                         ? DS.confirm : DS.textPrimary)
                        .lineLimit(1)
                }
                if live {
                    HStack(spacing: 4) {
                        Circle().fill(DS.confirm).frame(width: 6, height: 6)
                        Text("Live").dsText(.label12).foregroundStyle(DS.confirm)
                    }
                } else if let countdown {
                    Text(countdown).dsText(.label12).foregroundStyle(DS.tint)
                } else {
                    LiveTimeText(date: thing.capturedAt)
                }
                if let project {
                    Text(project)
                        .dsText(.label11)
                        .foregroundStyle(projectInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
        // One row, one element, one sentence — see `ThingVoice`. Without this
        // a single row is five stops: icon, title, thumbnail, time, tag.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThingVoice.rowLabel(for: thing, title: titleText,
                                                project: project, live: live,
                                                countdown: countdown))
    }
}

/// A relative time ("3m", "2h", "5d") that stays true — it re-renders each
/// minute instead of going stale with the row (§9 polish). Moved here from
/// the now-deleted ThingRow.swift (2026-07-21): BandRow is the row every
/// shaped feed actually uses, and this is the clock every one of them reads.
struct LiveTimeText: View {
    let date: Date
    var color: Color = DS.textTertiary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let label = Self.short(date)
            // "2h" → "3h" rolls its digit (the Clock app's grammar) instead
            // of swapping — the change is the moment (motion pass 2026-07-11).
            Text(label)
                .dsText(.subhead13)
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(DS.Motion.standard, value: label)
                .accessibilityLabel(Self.spoken(date))
        }
    }

    static func short(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// The same instant, said out loud. "2h" is a glance; VoiceOver reads the
    /// abbreviation as a bare letter, so the spoken form spells the unit.
    static func spoken(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 {
            let m = max(1, Int(s / 60))
            return m == 1 ? String(localized: "1 minute ago")
                          : String(localized: "\(m) minutes ago")
        }
        if s < 86_400 {
            let h = Int(s / 3600)
            return h == 1 ? String(localized: "1 hour ago")
                          : String(localized: "\(h) hours ago")
        }
        let d = Int(s / 86_400)
        return d == 1 ? String(localized: "1 day ago")
                      : String(localized: "\(d) days ago")
    }
}

/// A row said out loud (2026-07-21).
///
/// A feed row is one thing, so VoiceOver should hear one sentence — kind,
/// title, where it came from, why it's here, when — rather than stepping
/// through an icon, a title, a context word and a "2h" fragment as four
/// unrelated elements. Every shaped row composes its label here so the feed
/// speaks one grammar, and so a fact that is visual-only (the scam flag riding
/// the icon, the strikethrough that means done) still reaches someone who
/// never sees it.
enum ThingVoice {
    static func rowLabel(for thing: Thing, title: String, project: String? = nil,
                         live: Bool = false, countdown: String? = nil) -> String {
        var parts: [String] = [thing.kind.typeTag, title]
        if thing.source != thing.kind.typeTag {
            parts.append(String(localized: "from \(thing.source)"))
        }
        if let project, !project.isEmpty { parts.append(project) }
        // Visual-only facts, spoken. A safety flag is a 9pt glyph on the row
        // icon and it is the whole warning — silent, it does not exist. And
        // the spoofed-symbol case is worse than visual: VoiceOver reads
        // "ÚЅDС" and "USDC" identically, so for that reader the flag is the
        // ONLY difference between the two rows.
        if thing.hasSecurityFlag("poisoning") {
            parts.append(String(localized: "Warning, possible scam address"))
        }
        if thing.hasSecurityFlag("symbol") {
            parts.append(String(localized: "Warning, this token's symbol imitates another"))
        }
        if thing.mark == .done { parts.append(String(localized: "done")) }
        if live { parts.append(String(localized: "live now")) }
        else if let countdown, !countdown.isEmpty { parts.append(countdown) }
        else { parts.append(LiveTimeText.spoken(thing.capturedAt)) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}


/// The fat token row (prd §102, 2026-07-17, approved mock; supersedes Option
/// A's sparkline-in-the-band): the coin leads at 38pt, the name sits over
/// "SYMBOL · $94.1B cap", and the right stack is the live price in the
/// rounded display voice over a solid state pill. The pill carries direction
/// alone, number-first, so color is never the only voice; no timestamp (a
/// watchlist row's "watched N days ago" was already ruled noise, 2026-07-15).
/// Its own struct like MusicRow/CheckRow/ExcerptRow — the caller (FeedScreen's
/// shapedRow) mounts it only when a pulse EXISTS and falls back to the plain
/// band + timestamp until one lands, so this view never fakes a price.
struct TokenRow: View {
    let thing: Thing
    let pulse: TokenPulse.Pulse

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let image = thing.previewImageURL, !image.isEmpty {
                RemoteThumb(urlString: image, size: 38, fallback: thing.source,
                            circular: true)
            } else {
                BridgeIcon(name: thing.source, size: 38)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(tokenName)
                    .dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                if let vitals {
                    Text(vitals)
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(TokenChartStyle.priceText(pulse.price))
                    .dsText(.price16)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TokenDeltaPill(change: pulse.change24h, label: "",
                               compact: true, solid: true)
            }
        }
        .padding(.vertical, DS.Space.s2)
        // One row, one sentence — name, price, and which way it moved.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(tokenName), \(TokenChartStyle.priceText(pulse.price)), \(TokenChartStyle.changeText(pulse.change24h))"))
    }

    /// "Solana" out of "Solana · $SOL" — via the format's one parser
    /// (`TokensAsk.name/symbol`), never re-split here (review 2026-07-17: a
    /// third inline parser had already drifted from the canonical one).
    private var tokenName: String { TokensAsk.name(of: thing.title) }

    /// "SOL · $94.1B cap" — the symbol plus the market size the pulse
    /// carried. FDV stands in, labeled as FDV, when the source reported no
    /// cap; neither reported → the symbol stands alone; no symbol either →
    /// no line (never an invented number).
    private var vitals: String? {
        let parsed = TokensAsk.symbol(of: thing.title)
        let symbol: String? = parsed == thing.title ? nil : parsed
        let size: String? = if let cap = pulse.marketCap {
            "\(TokenStats.compact(cap)) cap"
        } else if let fdv = pulse.fdv {
            "\(TokenStats.compact(fdv)) FDV"
        } else { nil }
        let joined = [symbol, size].compactMap(\.self).joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }
}


/// The 24h price line (Option A, 2026-07-10): 2pt round stroke, no axes, no
/// dots — the signed percent beneath carries the number, the line carries
/// the shape. Green up / red down is state (the color law's third permitted
/// job), matching the confirm/destructive family. Feed rows retired it for
/// the fat token anatomy (TokenRow, 2026-07-17); TokenWatchScreen's
/// management rows still wear it.
struct Sparkline: View {
    let closes: [Double]
    let up: Bool

    var body: some View {
        Canvas { ctx, canvasSize in
            guard closes.count >= 2,
                  let lo = closes.min(), let hi = closes.max() else { return }
            let span = hi - lo
            let inset: CGFloat = 1   // half the stroke, so peaks aren't clipped
            let stepX = (canvasSize.width - inset * 2) / CGFloat(closes.count - 1)
            var path = Path()
            for (i, close) in closes.enumerated() {
                let t = span > 0 ? (close - lo) / span : 0.5
                let point = CGPoint(
                    x: inset + CGFloat(i) * stepX,
                    y: inset + CGFloat(1 - t) * (canvasSize.height - inset * 2))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            // A DASHED stroke when the line is down (2026-07-21): direction
            // was hue alone, and this component is reusable — the one call
            // site that pairs it with a signed number can't vouch for the
            // next. Solid-up / dashed-down survives greyscale.
            ctx.stroke(path, with: .color(up ? DS.confirm : DS.destructive),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round,
                                          dash: up ? [] : [3, 2]))
        }
        .frame(width: 46, height: 14)
        .accessibilityLabel(up ? Text("Price trend, up") : Text("Price trend, down"))
        // A draw-on reveal was built here and REVERTED (review 2026-07-11):
        // row @State resets on List recycling, so the wipe replayed on every
        // scroll pass — motion claiming a data arrival that didn't happen.
        // The draw-in belongs where data actually lands (the Home chart,
        // prd 36q); a row's one arrival animation is RowEntrance's.
    }
}


/// The one remote-image pipeline behind RemoteThumb and PostMedia (extracted
/// 2026-07-13 — the two views had grown twin copies of the same fetch/decode/
/// downsample/cache dance). The loader owns the shared decoded cache and the
/// session dead-URL set; the views stay thin rendering shells that decide
/// what each outcome LOOKS like (glyph fallback vs collapsed block).
@MainActor
enum RemoteImageLoader {
    enum Outcome {
        /// Decoded and downsampled. `fresh` says the bytes just arrived over
        /// the network (fade in — arrival, never a pop) as opposed to a cache
        /// hit the session already knew (assign flat — a known image
        /// re-appearing softly would read as re-loading).
        case image(UIImage, fresh: Bool)
        /// The network failed THIS attempt — an answer for this appearance
        /// only (retry on recycle), never blacklisted.
        case transientFailure
        /// The URL served non-image bytes (a delisted Steam header's 404
        /// page) — dead for the session, so scrolling stops re-fetching it.
        case dead
    }

    /// One decoded-image cache for every remote image, bounded by COST
    /// (decoded bitmap bytes): a card-width post image is ~30× a 26pt thumb,
    /// so no count limit can speak for both — RemoteThumb's old 120-entry
    /// limit was a proxy for the few-MB memory bound that cost accounting
    /// now states directly.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    /// URLs that served non-image bytes. Without this, every scroll pass
    /// over a dead-URL row re-issues the request — the CDN's 404 carries no
    /// cache headers, so URLCache stores nothing. Session-scoped on purpose:
    /// a redeploy can revive art.
    private static var dead: Set<String> = []

    /// The decoded cache keys on URL AND pixel side — one Apple Music cover
    /// renders at 26pt in the All band and 44pt in MusicRow; a URL-only key
    /// served the 78px thumb into the 132px slot, blurry for the session
    /// (review 2026-07-11).
    private static func key(_ urlString: String, _ side: CGFloat) -> NSString {
        "\(Int(side))|\(urlString)" as NSString
    }

    static func isDead(_ urlString: String) -> Bool { dead.contains(urlString) }

    /// The synchronous cache probe — a hit lands in the same render pass, so
    /// a recycled row never flashes its placeholder for an image the session
    /// already holds (an await, however short, is a frame).
    static func cachedImage(urlString: String, targetSide: CGFloat) -> UIImage? {
        cache.object(forKey: key(urlString, targetSide))
    }

    /// Fetch → decode → downsample to `targetSide` pixels. `cached: false`
    /// is the perishable rule (a live-stream frame changes behind its URL):
    /// skip the decoded cache both ways so a second broadcast can't wear the
    /// first broadcast's frame, and never blacklist the URL.
    static func load(urlString: String, targetSide: CGFloat, cached: Bool = true) async -> Outcome {
        if dead.contains(urlString) { return .dead }
        if cached, let hit = cache.object(forKey: key(urlString, targetSide)) {
            return .image(hit, fresh: false)
        }
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else {
            return .transientFailure
        }
        guard !Task.isCancelled else { return .transientFailure }
        guard let full = UIImage(data: data) else {
            if cached { dead.insert(urlString) }
            return .dead
        }
        // Downsample off the main thread — a wall of full-res images would
        // otherwise decode at display size on every scroll pass.
        let thumb: UIImage = await withCheckedContinuation { cont in
            full.prepareThumbnail(of: CGSize(width: targetSide, height: targetSide)) {
                cont.resume(returning: $0 ?? full)
            }
        }
        guard !Task.isCancelled else { return .transientFailure }
        if cached {
            let cost = Int(thumb.size.width * thumb.size.height
                           * thumb.scale * thumb.scale * 4)
            cache.setObject(thumb, forKey: key(urlString, targetSide), cost: cost)
        }
        return .image(thumb, fresh: true)
    }
}


/// A cached remote thumbnail for a feed row — a Pinterest pin's image, loaded
/// from the URL captured at ingest, through RemoteImageLoader (downsampled to
/// the thumbnail size so a wall of full-res pins can't bloat memory). A dead
/// URL falls back to the bridge glyph — what "no image" looks like everywhere
/// else — never a gray hole (2026-07-10: a 404'd Steam header or expired
/// frame must not read worse than having no art at all).
struct RemoteThumb: View {
    let urlString: String
    var size: CGFloat = 26
    /// The bridge whose glyph stands in when the URL turns out dead.
    var fallback: String? = nil
    /// A perishable image (a live-stream frame) changes behind its URL —
    /// RemoteImageLoader's uncached rule: skip the decoded cache and never
    /// blacklist.
    var perishable = false
    /// A circle clip instead of the app-icon squircle — for author avatars.
    var circular = false
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed || RemoteImageLoader.isDead(urlString), let fallback {
                BridgeIcon(name: fallback, size: size)
            } else {
                ZStack {
                    DS.fillFaint
                    Image(systemName: "photo")
                        .accessibilityHidden(true)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(circular
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: DS.Radius.appIcon(size), style: .continuous)))
        .task(id: urlString) { await load() }
    }

    private func load() async {
        if RemoteImageLoader.isDead(urlString) { failed = true; return }
        // Cache hit is instant and also covers a recycled row landing on a new
        // URL (its own key, so a stale pin never shows through) — no fade: an
        // already-known image re-appearing softly would read as re-loading.
        if !perishable,
           let hit = RemoteImageLoader.cachedImage(urlString: urlString, targetSide: size * 3) {
            image = hit; return
        }
        // A recycled row: drop the previous pin before the new one arrives.
        image = nil
        failed = false
        switch await RemoteImageLoader.load(urlString: urlString, targetSide: size * 3,
                                            cached: !perishable) {
        case .image(let thumb, let fresh):
            // A freshly downloaded image fades in over the placeholder —
            // arrival, never a pop (the App Store's grammar; motion pass
            // 2026-07-11). The token motion, not an ad-hoc curve; a pure
            // crossfade, so Reduce Motion needs no gate.
            if fresh { withAnimation(DS.Motion.standard) { image = thumb } }
            else { image = thumb }
        case .transientFailure:
            // Glyph now, retry on recycle. A cancelled task is not a failure
            // — leave the state for the next appearance to reset.
            failed = !Task.isCancelled
        case .dead:
            failed = true
        }
    }
}


/// Apple Music's own shape (2026-07-11): in the music room, art leads at
/// track size — the 26pt band thumb honors All's rhythm, but a source's
/// shaped feed is allowed its native anatomy, and music's native anatomy is
/// the cover. Title over artist (split from the stored "Title — Artist"),
/// time trailing; same card surface, no new colors.
struct MusicRow: View {
    let thing: Thing

    /// The stored "Title — Artist" splits at the LAST separator (the ingest
    /// appends the artist last, so an artist is the final segment). Known
    /// limit: a title that itself contains " — " with NO artist appended
    /// still splits — undetectable without a stored artist field, and
    /// catalog songs always carry an artist.
    private var parts: (title: String, artist: String?) {
        let comps = thing.title.components(separatedBy: " — ")
        guard comps.count > 1, let artist = comps.last else { return (thing.title, nil) }
        return (comps.dropLast().joined(separator: " — "), artist)
    }

    @Environment(\.colorScheme) private var scheme

    private var done: Bool { thing.mark == .done }

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    var body: some View {
        let parts = self.parts   // one split per render, read twice below
        HStack(spacing: DS.Space.s3) {
            if let art = thing.previewImageURL, !art.isEmpty {
                RemoteThumb(urlString: art, size: 44, fallback: thing.source)
            } else {
                BridgeIcon(name: thing.source, size: 44)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.title)
                    .dsText(.body17)
                    .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                    .strikethrough(done, color: DS.textTertiary)
                    .lineLimit(1)
                if let artist = parts.artist {
                    Text(artist)
                        .dsText(.subhead13)
                        .foregroundStyle(done ? DS.textTertiary : DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Rows carry status (principle 6) — the project tag survives the
            // shape switch, same slot as the band. (The pin badge retired
            // 2026-07-12: pinning is per-APP now, not a mark on a thing.)
            VStack(alignment: .trailing, spacing: 1) {
                LiveTimeText(date: thing.capturedAt)
                if let project {
                    Text(project)
                        .dsText(.label11)
                        .foregroundStyle(projectInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}


/// A deterministic identicon for a watched wallet address (2026-07-10) — the
/// visual twin of the address label, so two watched wallets read apart at a
/// glance when neither has an avatar to show. A pure function of the address:
/// no network, no asset. A 5-cell grid mirrored down the middle, one hue on a
/// dark tint of itself, clipped to a circle to match the social avatars.
struct WalletBlockie: View {
    let address: String
    var size: CGFloat = 26

    var body: some View {
        let seed = Self.hash(address)
        let hue = Double(seed % 360) / 360.0
        let fg = Color(hue: hue, saturation: 0.60, brightness: 0.85)
        let bg = Color(hue: hue, saturation: 0.32, brightness: 0.22)
        Canvas { ctx, canvasSize in
            let cells = 5
            let cell = canvasSize.width / CGFloat(cells)
            var r = seed | 1   // never a zero state
            func nextOn() -> Bool { r = r &* 6_364_136_223_846_793_005 &+ 1; return (r >> 33) & 1 == 0 }
            ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(bg))
            for y in 0..<cells {
                for x in 0...(cells / 2) where nextOn() {
                    for col in [x, cells - 1 - x] {
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(y) * cell,
                                          width: cell + 0.5, height: cell + 0.5)
                        ctx.fill(Path(rect), with: .color(fg))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// djb2 over the lowercased address — stable per address, spread enough
    /// that neighbours look different.
    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.lowercased().utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }
}


/// A mail sender's initial in a colored circle (2026-07-10) — email carries
/// no avatar, so the letter is the identity, the way Mail apps themselves
/// draw unknown senders. Hue is a pure function of the sender string (same
/// trick as WalletBlockie): two senders read apart at a glance, the same
/// sender is always the same color. No network, nothing stored.
struct SenderInitial: View {
    let sender: String
    var size: CGFloat = 26

    var body: some View {
        let letter = Self.letter(of: sender) ?? "?"
        let hue = Double(Self.hash(sender) % 360) / 360.0
        Circle()
            .fill(Color(hue: hue, saturation: 0.48, brightness: 0.52))
            .frame(width: size, height: size)
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityLabel("From \(Self.displayName(of: sender))")
    }

    /// "Ana Torres <ana@x.com>" → "A"; "ana@x.com" → "A". nil when the
    /// sender has no letter to give (the row keeps the brand glyph then).
    static func letter(of sender: String) -> String? {
        displayName(of: sender).first { $0.isLetter || $0.isNumber }
            .map { String($0).uppercased() }
    }

    /// The human part of an address: the display name when present,
    /// otherwise the address itself (quotes and brackets stripped).
    static func displayName(of sender: String) -> String {
        var s = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracket = s.firstIndex(of: "<") {
            let name = s[..<bracket].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { s = name } else { s = String(s[s.index(after: bracket)...].dropLast()) }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    /// djb2, matching WalletBlockie — stable per sender. Case-insensitive:
    /// "Ana <a@x>" and "ana <a@x>" are the same person, same hue.
    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.lowercased().utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }
}


// MARK: - Bundle — machine bulk, compressed (ruling 2026-07-09)

/// One row standing for a source's bulk arrivals in a day. Compression,
/// never ranking: the rows still exist, one tap away in the source's own
/// shape (the Reminders "Older" collapse, applied to volume).
///
/// Re-voiced 2026-07-21 (the wallet-look pass, user: "improving the feed
/// look itself"): the count leaves the sentence for the trailing slot in
/// rounded tabular figures — the wallet stream's "amounts join the stream"
/// move, applied to the All feed's own quantities — and a bundle whose
/// members carry pictures leads with a fan of them (what actually arrived)
/// instead of one brand glyph. Facts unchanged: source, count, unit word,
/// newest time — only where each one stands.
struct BundleRow: View {
    let source: String
    let count: Int
    /// The kind's plural when the bundle is uniform ("transactions"),
    /// "things" when mixed.
    let word: String
    let newest: Date
    /// Up to three member preview images, newest first — [] falls back to
    /// the brand glyph.
    var art: [String] = []

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if art.isEmpty {
                BridgeIcon(name: source, size: 26)
            } else {
                // The fan: newest on top, each a step behind — the same 26pt
                // leading seat every band row keeps, grown only by the
                // overlap, so the row's rhythm holds.
                ZStack(alignment: .leading) {
                    ForEach(Array(art.enumerated().reversed()), id: \.offset) { i, url in
                        RemoteThumb(urlString: url, size: 26, fallback: source)
                            .offset(x: CGFloat(i) * 10)
                    }
                }
                .frame(width: 26 + CGFloat(art.count - 1) * 10, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(source)
                    .dsText(.body17)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                LiveTimeText(date: newest)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(count)")
                    .dsText(.price16)
                    .foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                Text(word)
                    .dsText(.label11)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}


// MARK: - All: kind-aware row (now the band, uniformly)


// MARK: - Approval — the consent card (the ONE rhythm-breaker)

/// An agent's ask as a card: provenance eyebrow, the ask, Approve/Deny pills.
/// The card IS the consent surface (S10) — tapping commits, no extra dialog.
struct ApprovalCard: View {
    let thing: Thing
    var onApprove: () -> Void
    var onDeny: () -> Void

    /// WHO is asking leads; the route it came through reads as a route
    /// ("Claude-code · via OpenClaw"), and the machine name stays in the
    /// sheet — three flat brand names explained nothing (ruling 2026-07-06).
    /// Sentence case only — no ALL-CAPS eyebrows (design law, 2026-07-08).
    private var eyebrow: String {
        let asker = thing.provenance.agent ?? thing.provenance.app
        var parts = [asker]
        if thing.provenance.app.lowercased() != asker.lowercased() {
            parts.append("via \(thing.provenance.app)")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? joined : joined.prefix(1).uppercased() + joined.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text(eyebrow)
                .dsText(.label12)
                .foregroundStyle(DS.textSecondary)
            Text(thing.title)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: DS.Space.s2) {
                Button(action: onApprove) {
                    Text("Approve").dsText(.label12).foregroundStyle(.black)
                        .padding(.horizontal, DS.Space.s4).frame(height: 32)
                        .background(DS.confirm, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onDeny) {
                    Text("Deny").dsText(.label12).foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s4).frame(height: 32)
                        .background(DS.fillFaint, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
                LiveTimeText(date: thing.capturedAt)
            }
            .padding(.top, DS.Space.s1)
        }
        .padding(.vertical, DS.Space.s2)
    }
}




// MARK: - Photos: thumb-led row (All) and grid cell (Photos shape)


/// One grid cell (mock P1): the image, title riding the bottom edge over a
/// scrim, day pill on the first photo of each day.
struct PhotoCell: View {
    let thing: Thing
    var dayPill: String?

    var body: some View {
        PhotoWell(thing: thing, size: nil)
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.subhead13).foregroundStyle(.white)
                        .lineLimit(1)
                    if let project = thing.tags.first(where: { ThingKind.from(typeTag: $0) == nil }) {
                        Text(project).dsText(.label12).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(DS.Space.s2)
            }
            .overlay(alignment: .topLeading) {
                if let dayPill {
                    Text(dayPill)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        // Vertical padding, not a pinned 22pt height: the pill
                        // now grows with the label instead of clipping it.
                        .padding(.horizontal, DS.Space.s2).padding(.vertical, 3)
                        .background(Color.black.opacity(0.5), in: Capsule(style: .continuous))
                        .padding(DS.Space.s2)
                }
            }
    }
}

/// Loads the PHAsset behind a screenshot thing; honest fallback is the kind's
/// own hue field (demo things carry no asset).
struct PhotoWell: View {
    let thing: Thing
    var size: CGFloat?   // nil = fill available
    @State private var image: UIImage?

    var body: some View {
        Group {
            if size != nil {
                content
            } else {
                // Fill mode (the Photos grid): `.frame(maxWidth: .infinity)` only
                // caps the SIZE the parent proposes — it doesn't stop a
                // `scaledToFill` image from reporting its own (large) intrinsic
                // size back up, which inflated the grid row's ideal width past
                // the screen and let a screenshot bleed over its neighbor cell
                // (user, 2026-07-13). A `GeometryReader` pins the image to
                // whatever space the row actually allocated, same fix already
                // proven in `GenMediaTile` for the same class of leak.
                GeometryReader { geo in
                    content.frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: size != nil ? DS.Radius.appIcon(size!) : 0,
                                    style: .continuous))
        .task(id: thing.sourceRef) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable().scaledToFill()
        } else {
            ZStack {
                thing.kind.hue.opacity(0.22)
                Image(systemName: "photo")
                    .accessibilityHidden(true)
                    .font(.system(size: (size ?? 100) * 0.34, weight: .medium))
                    .foregroundStyle(thing.kind.hue)
            }
        }
    }

    private func load() async {
        guard image == nil, let ref = thing.sourceRef else { return }
        // Sample things carry the bundled photo — the demo shows a real
        // image, never a gray well.
        if ref.hasPrefix("sample:") {
            image = UIImage.demoSample(for: ref)
            return
        }
        // The corpus's own copy first (saved by ScreenshotIngest.heal since
        // 2026-07-10) — instant, and it outlives the Photos original. No
        // fade: stored bytes are ready before first paint, like a bundle
        // image.
        if let data = thing.previewImageData, let stored = UIImage(data: data) {
            image = stored
            return
        }
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let side = (size ?? 300) * 3
        let loaded: UIImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true   // iCloud-optimized originals
            opts.deliveryMode = .highQualityFormat
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side, height: side),
                contentMode: .aspectFill, options: opts
            ) { img, info in
                // Network-backed assets call back twice: a degraded placeholder
                // first, the real image second — waiting past the placeholder so
                // the real download isn't discarded (same fix as GenCover).
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                guard !reported else { return }
                reported = true
                cont.resume(returning: img)
            }
        }
        // Same arrival grammar as RemoteThumb (one fade for every image
        // loader, review 2026-07-11) — never two grammars in one scroll.
        withAnimation(DS.Motion.standard) { image = loaded }
    }
}

// MARK: - ChatGPT / Claude: the earned takeaway card

/// Pinned or in-motion chats earn a card — the saved synthesis line IS the
/// content. No buttons (verbs live in the sheet and swipes).
struct TakeawayCard: View {
    let thing: Thing

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text((project ?? thing.source))
                    .dsText(.label12)
                    .foregroundStyle(DS.textSecondary)
                Spacer()
                LiveTimeText(date: thing.capturedAt)
            }
            Text(thing.title)
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !thing.content.isEmpty {
                Text(thing.content)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}

// MARK: - Reminders: the check row (the lightest write, consent inline)

struct CheckRow: View {
    let thing: Thing
    var onToggle: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var done: Bool { thing.mark == .done }

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? DS.tint : DS.gray300, lineWidth: 1.5)
                        .background(Circle().fill(done ? DS.tint : .clear))
                        .frame(width: 24, height: 24)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(DS.Space.s1)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark not done" : "Mark done")
            Text(thing.title)
                .dsText(.body17)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                LiveTimeText(date: thing.capturedAt)
                if let project {
                    Text(project)
                        .dsText(.label11)
                        .foregroundStyle(projectInk)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, DS.Space.s1)
    }
}

// MARK: - Notes / chats — the excerpt row (shaped feeds, 2026-07-13)

/// A note's point is its text; a saved conversation's is its opening line.
/// In the notes and chat shapes the row carries an excerpt under the title —
/// same band anatomy (26pt leading slot, time-over-project trailing), the
/// body just breathes below the first line. All keeps the plain band.
struct ExcerptRow: View {
    let thing: Thing
    /// How many excerpt lines this shape affords — notes read deeper (3),
    /// a chat's first line is a snippet (2).
    var lines: Int = 3

    /// The body text worth excerpting — nil when the content is empty, repeats
    /// the title, or is a bare URL (a link permalink is plumbing, not prose).
    /// "Bare URL" = one whitespace-free token the detector recognizes —
    /// comparing absoluteString to the raw text misses every scheme-less or
    /// normalized link (NSDataDetector rewrites what it matches).
    private var excerpt: String? {
        let text = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != thing.title else { return nil }
        if !text.contains(where: \.isWhitespace), Capture.detectURL(in: text) != nil {
            return nil
        }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            BridgeIcon(name: thing.source, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                if let excerpt {
                    Text(excerpt)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(lines)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowTrailingMeta(thing: thing)
        }
        .padding(.vertical, DS.Space.s2)
    }
}


/// The trailing time-over-project stack the shaped rows share — one home for
/// the anatomy instead of a per-row copy (the file already carried five; the
/// new rows use this one).
struct RowTrailingMeta: View {
    let thing: Thing
    @Environment(\.colorScheme) private var scheme

    private var project: String? {
        thing.tags.first { ThingKind.from(typeTag: $0) == nil }
    }

    private var projectInk: Color {
        guard let project else { return DS.textTertiary }
        let base = ProjectHue.color(for: project)
        return scheme == .light ? base.mix(with: .black, by: 0.35) : base
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            LiveTimeText(date: thing.capturedAt)
            if let project {
                Text(project)
                    .dsText(.label11)
                    .foregroundStyle(projectInk)
                    .lineLimit(1)
            }
        }
    }
}


// MARK: - Bluesky / Farcaster — the post card (shaped feeds, 2026-07-13)

/// In its own room a post reads as a post: the author leads (avatar + handle
/// + time), the text sits unclamped (ingest stores one 80-char title line),
/// and an attached image rides at card width — the 26pt thumb is All's
/// rhythm, not the post's. Same card surface; no new colors.
struct PostCard: View {
    let thing: Thing

    /// Empty-string handles exist (an unmigrated Farcaster row) — fall back
    /// to the source name, same guard the avatar line already carries.
    private var author: String {
        if let handle = thing.authorHandle, !handle.isEmpty { return handle }
        return thing.source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if let avatar = thing.authorAvatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: 26, fallback: thing.source,
                                circular: true)
                } else {
                    BridgeIcon(name: thing.source, size: 26)
                }
                Text(author)
                    .dsText(.subhead13).fontWeight(.medium)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer()
                // Rows carry status (principle 6): the mark survived the
                // .chat → .social split as a header label — the takeaway
                // card's content slot would show a post's permalink, so the
                // card keeps its anatomy and wears the state instead.
                if thing.mark == .doing {
                    Text("Doing").dsText(.label12).foregroundStyle(DS.tint)
                }
                LiveTimeText(date: thing.capturedAt)
            }
            Text(thing.title)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let media = thing.previewImageURL, !media.isEmpty {
                PostMedia(urlString: media)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// A post's attached image at card width. RemoteImageLoader's bytes, not
/// RemoteThumb's shell (that's a fixed-size thumb): a dead URL COLLAPSES the
/// block — the card just becomes a text post, never a gray hole (the
/// RemoteThumb honesty rule at a size where a placeholder would dominate the
/// card). The `.task` stays attached in EVERY state (review 2026-07-13):
/// parked inside the non-failed branch, a recycled row that once failed would
/// drop its own retry path and stay text-only for the session. Same reason
/// load() resets the previous URL's image/failure first — RemoteThumb's
/// recycled-row rule, kept here too.
struct PostMedia: View {
    let urlString: String
    var height: CGFloat = 160
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if failed || RemoteImageLoader.isDead(urlString) {
                // Collapsed — the card reads as a text post.
                Color.clear.frame(height: 0)
            } else if let image {
                // The known scaledToFill leak (CLAUDE.md): pin the image
                // inside a GeometryReader so its intrinsic size never
                // inflates the row.
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else {
                DS.fillFaint
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        // A recycled row: drop the previous post's state before the new URL
        // resolves — a transient failure was an answer for THAT appearance.
        image = nil
        failed = false
        if RemoteImageLoader.isDead(urlString) { return }
        // Card width is ~1080px at 3×; 640 was soft at display size.
        if let hit = RemoteImageLoader.cachedImage(urlString: urlString, targetSide: 1080) {
            image = hit; return
        }
        switch await RemoteImageLoader.load(urlString: urlString, targetSide: 1080) {
        case .image(let thumb, let fresh):
            if fresh { withAnimation(DS.Motion.standard) { image = thumb } }
            else { image = thumb }
        case .transientFailure:
            failed = !Task.isCancelled
        case .dead:
            failed = true
        }
    }
}


// MARK: - Safari — the reading row (shaped feeds, 2026-07-13)

/// A saved link's native anatomy: the page's image leads at reading size when
/// it has one, the title reads at two lines, and the DOMAIN sits where a note
/// would put its excerpt — where it's from is what you scan a reading list by.
struct ReadingRow: View {
    let thing: Thing

    /// "www." stripped — the domain is identity, the subdomain is plumbing.
    private var domain: String? {
        let text = thing.content.isEmpty ? thing.title : thing.content
        guard let host = Capture.detectURL(in: text)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            if let art = thing.previewImageURL, !art.isEmpty {
                RemoteThumb(urlString: art, size: 56, fallback: thing.source)
            } else {
                BridgeIcon(name: thing.source, size: 26)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                if let domain {
                    Text(domain)
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RowTrailingMeta(thing: thing)
        }
        .padding(.vertical, DS.Space.s2)
    }
}


// MARK: - Shape ledes (2026-07-13: every shape earns one glanceable block)

/// Music's lede: today's listening — the covers that landed today, lapped
/// like a hand of cards, and the count. Facts only (analytics rule §10):
/// no streaks, no goals.
struct ListeningLede: View {
    let covers: [String]
    let count: Int

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            HStack(spacing: -10) {
                ForEach(Array(covers.prefix(5).enumerated()), id: \.offset) { _, art in
                    RemoteThumb(urlString: art, size: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.appIcon(32), style: .continuous)
                                .strokeBorder(DS.surfaceSheet, lineWidth: 2)
                        )
                }
            }
            Text(count == 1 ? "1 song today" : "\(count) songs today")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// The reading list's lede (2026-07-21): a saved link is a DOOR, not a read,
/// so the shape counts the pile instead of pretending the rows are consumed —
/// how many landed this month, how many are older, and the oldest one still
/// waiting. Facts only (§10): no streaks, no goals, and "still here" not
/// "unopened" (Thing tracks no read state, so the model can't claim it).
struct ReadingLede: View {
    let thisMonth: Int
    let older: Int
    let oldest: Thing?

    private var summary: String {
        var parts: [String] = []
        if thisMonth > 0 {
            parts.append(thisMonth == 1 ? String(localized: "1 saved this month")
                                        : String(localized: "\(thisMonth) saved this month"))
        }
        if older > 0 {
            parts.append(older == 1 ? String(localized: "1 older")
                                    : String(localized: "\(older) older"))
        }
        return parts.joined(separator: " · ")
    }

    /// The oldest save's domain — its identity, the same "www."-stripped host
    /// ReadingRow shows; falls back to the title when there's no URL to read.
    private func label(for thing: Thing) -> String {
        let text = thing.content.isEmpty ? thing.title : thing.content
        guard let host = Capture.detectURL(in: text)?.host() else { return thing.title }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(summary.isEmpty ? String(localized: "Reading list") : summary)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            if let oldest {
                HStack(spacing: DS.Space.s2) {
                    Text("Oldest still here")
                        .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    Text(label(for: oldest))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    LiveTimeText(date: oldest.capturedAt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.s2)
    }
}

/// Bitrefill's lede: the account balance the API last reported, with this
/// month's order count beside it. Facts only — no spend prompts, and no
/// "unused"/"expires" claims the API can't back (BitrefillBridge's ceiling).
struct BitrefillLede: View {
    let balance: String
    let monthCount: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text("Balance")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
            if monthCount > 0 {
                Text(monthCount == 1 ? "1 order this month" : "\(monthCount) orders this month")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Text(balance)
                .dsText(.body17).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// 1Claw's lede: the key's reach — how many vaults its API last reported,
/// with the grant-row count beside it. Facts only: no "secure"/"exposed"
/// judgments, and no claims about grants the key couldn't read.
struct OneClawLede: View {
    let vaults: String
    let grantCount: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text("Access")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
            if grantCount > 0 {
                Text(grantCount == 1 ? "1 grant" : "\(grantCount) grants")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            Text(vaults)
                .dsText(.body17).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// Wallet's lede: the portfolio's own balance line (2026-07-18: "should the
/// wallet source feed show sparkline / balance line? do we have that data?"
/// — yes, `WalletStore.ValueSample` already samples every real holdings
/// fetch). A real chart, not invented: empty until two aligned samples exist,
/// the same honesty floor `combinedValueSamples()` keeps — a freshly-watched
/// wallet shows the treemap alone until its history has a second point.
struct WalletBalanceLede: View {
    let chart: TokenChart
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { TokenChartStyle.accent(change: chart.change, scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text("Balance")
                    .dsText(.body17).foregroundStyle(DS.textPrimary)
                Spacer(minLength: 0)
                Text(TokenChartStyle.priceText(chart.price))
                    .dsText(.body17).fontWeight(.semibold).foregroundStyle(DS.textPrimary)
                TokenDeltaPill(change: chart.change, label: "watched", compact: true)
            }
            TokenChartPlot(chart: chart, accent: accent, height: 40, pulses: false)
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// Tokens' lede: the watchlist's day at a glance — how many are up, how many
/// down, over the same cached 24h pulses the rows themselves wear (honest by
/// construction: one data source, two renders). Green/red is state, the color
/// law's permitted job.
struct WatchlistLede: View {
    let up: Int
    let down: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Text("Watchlist")
                .dsText(.body17).foregroundStyle(DS.textPrimary)
            Spacer(minLength: 0)
            if up > 0 {
                Text("\(up) up")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.confirm)
            }
            if down > 0 {
                Text("\(down) down")
                    .dsText(.subhead13).fontWeight(.semibold)
                    .foregroundStyle(DS.destructive)
            }
            Text("24h")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
        .padding(.vertical, DS.Space.s2)
    }
}

