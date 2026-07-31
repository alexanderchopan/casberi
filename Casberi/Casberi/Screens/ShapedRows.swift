import SwiftUI
import Photos
import CryptoKit

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
    /// Where this row sits in its run, for the naming RIPPLE (prd §171,
    /// 2026-07-22): renaming a counterparty rewrites every landed transfer
    /// with that address, and the rewrite used to happen invisibly. Now each
    /// row crossfades its title as the change reaches it, a beat behind the
    /// row above — you type one word and watch it travel back through months
    /// of your own history. Modulo'd so a long feed still finishes the sweep
    /// quickly.
    var rippleIndex: Int = 0
    /// A screenshot Vision found NO words in (prd §218, 2026-07-25). Such a row
    /// used to wear the dead label "Screenshot"; it now drops the title
    /// entirely and gives the picture the room the words would have had —
    /// because the picture IS the content, and it's the only row you have to
    /// look at to know what it is. Opt-in from the feed, which owns the
    /// minority gate: past half a day's rows these fall back to the ordinary
    /// band, or the All feed would quietly become the Photos grid.
    var imageOnly: Bool = false

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

    /// The trailing label — which wallet a transaction came from when more
    /// than one is watched, or a source-specific fact (2026-07-09; the tag
    /// lookup that used to lead this dropped 2026-07-23 — a thing's own
    /// project tag no longer surfaces on the row. Tags aren't always
    /// accurate for a glance (a bridge-assigned literal like "Watchlist" or
    /// "NFT" sits on EVERY row from that source, so it stopped being a
    /// distinguishing fact and started being noise) or necessary (the agent
    /// and the Themes treemap still read `thing.tags` in full — this is a
    /// display choice, not a data one). Same slot, same voice, so two
    /// watched wallets don't read as one indistinguishable stream.
    private var project: String? {
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
        case "Bluesky", "Farcaster", "Nostr":
            if let why = SocialThread.contextLabel(for: thing) { return why }
            switch thing.source {
            case "Bluesky":   return BlueskyStore.shared.rowLabel(for: thing.authorHandle)
            case "Farcaster": return FarcasterStore.shared.rowLabel(for: thing.authorHandle)
            default:          return NostrStore.shared.rowLabel(for: thing.authorHandle)
            }
        // Slack carries a context label too (every landed thing IS a mention,
        // so this always resolves) but stays out of the `isSocial` set above —
        // no watched-account roster to fall back to, no thread reader, no
        // profile card. Just the one line `contextLabel` already knows how to
        // say (`Model/SocialBridge.swift`).
        case "Slack":
            return SocialThread.contextLabel(for: thing)
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

    /// The trailing label's ink — the tertiary ramp, for every word this slot
    /// can carry (2026-07-30).
    ///
    /// It ran through `ProjectHue` until now: a hash-picked hue, from the days
    /// this slot held the person's own PROJECT TAG, where the color was real
    /// identity ("Lisbon trip" wearing one hue everywhere). That tag was
    /// dropped from the row on 2026-07-23 — but the coloring wasn't, so the
    /// hash kept firing on whatever moved in behind it: "Liked", "/design",
    /// "Mentions you", "BBC News", "★1.2k · Swift", "Cash App". A stable color
    /// per arbitrary string is not identity, it's decoration with a memory —
    /// exactly what §8's color law rules out ("identity, state, or magnitude,
    /// never decoration").
    ///
    /// It also failed the contrast pass this app already made everywhere else:
    /// at `label11`, light mode mixed the palette only 0.35 toward black, which
    /// puts the yellow rung near 3.4:1 — under the 4.5:1 bar `DS.textTertiary`
    /// was raised to meet on 2026-07-21, on the smallest text in the row.
    ///
    /// Nothing is lost where identity actually mattered: a multi-wallet row
    /// already leads with that wallet's own `WalletBlockie` (see
    /// `identiconAddress`), which is the identity, in the slot built for it.
    private var labelInk: Color { DS.textTertiary }

    private var countdown: String? {
        guard emphasized else { return nil }
        let mins = Int(thing.capturedAt.timeIntervalSinceNow / 60)
        guard mins >= 0 else { return nil }
        return mins < 60 ? "in \(max(1, mins)) min" : "in \(mins / 60)h"
    }

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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
                } else if thing.previewImageData != nil {
                    // A folder-picked image (Files, 2026-07-27) carries its
                    // own bytes with no PHAsset behind it — PhotoWell already
                    // reads `previewImageData` before ever touching Photos,
                    // so this just needs the gate widened past `.screenshot`.
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
            if imageOnly {
                // No title at all — deliberately not an empty Text, so nothing
                // reserves a line for words that don't exist. 104×58: double a
                // thumbnail's height, enough to actually read the shot, short
                // of the tile that would dominate the scroll.
                PhotoWell(thing: thing)
                    .frame(width: 104, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control,
                                                style: .continuous))
                Spacer(minLength: 0)
            } else {
            Text(titleText)
                .dsText(.body17)
                // The ripple (prd §171): the title dissolves into its new
                // wording rather than swapping. Keyed on the string, so this
                // fires ONLY on a real retitle — never on scroll, never on a
                // first appearance.
                .contentTransition(.opacity)
                .animation(DS.Motion.standard.delay(Double(rippleIndex % 8) * 0.045),
                           value: titleText)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                .strikethrough(done, color: DS.textTertiary)
                // Two lines everywhere (ruling 2026-07-09) — except Kalshi,
                // whose title IS the full market question ("Will the Chiefs
                // win the Super Bowl?"), not a headline, and was clipping
                // mid-word at 2 lines (user, 2026-07-13).
                .lineLimit(thing.source == "Kalshi" ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                        .foregroundStyle(labelInk)
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

/// ONE minute tick for the whole app (2026-07-30) — the clock every relative
/// timestamp reads.
///
/// `LiveTimeText` wrapped itself in `TimelineView(.periodic(by: 60))`, which
/// meant one independently scheduled timeline PER ROW: every row of the active
/// feed, plus both mounted pager neighbours, each waking the main thread on its
/// own 60s cadence — including the rows reading "5d", whose label cannot change
/// for another 19 hours. One shared source costs one timer and lets a row opt
/// out of the subscription entirely (see `LiveTimeText.body`).
@MainActor @Observable
final class MinuteClock {
    static let shared = MinuteClock()
    /// Bumped every 60s. Reading it in a body is what subscribes that body.
    private(set) var minute = 0
    private var timer: Timer?

    private init() {
        // `.common` mode so the tick survives a scroll — the default run-loop
        // mode is suspended while a scroll view tracks, which is exactly when
        // these labels are being looked at.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.minute &+= 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// A relative time ("3m", "2h", "5d") that stays true — it re-renders each
/// minute instead of going stale with the row (§9 polish). Moved here from
/// the now-deleted ThingRow.swift (2026-07-21): BandRow is the row every
/// shaped feed actually uses, and this is the clock every one of them reads.
struct LiveTimeText: View {
    let date: Date
    var color: Color = DS.textTertiary
    private let clock = MinuteClock.shared

    /// Whether this row's label can still move within a session. Under a day,
    /// it reads minutes then hours and has to keep up; past a day it reads
    /// whole days, and the next change is up to 24 hours out — nothing a
    /// minute tick can usefully deliver. Future stamps (an event, a dated
    /// reminder) count the same distance the other way, hence `abs`.
    private var ticking: Bool { abs(date.timeIntervalSinceNow) < 86_400 }

    var body: some View {
        // The subscription IS this read: touching `clock.minute` registers
        // this body with the shared clock's observation, and skipping it
        // leaves a day-old row genuinely unsubscribed rather than merely
        // re-rendering to the same string once a minute.
        let _ = ticking ? clock.minute : 0
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

    /// A stamp AHEAD is not an age (2026-07-27, the calendar-room pass): an
    /// event two days out ran the same arithmetic on a negative interval, hit
    /// the `max(1, …)` clamp and rendered "1m" — a row that hadn't happened
    /// yet wearing "a minute ago". Anything in the future says when it IS.
    /// Only the perishable kinds (events, dated reminders) ever carry a future
    /// `capturedAt`, so this branch is unreachable for a landed capture.
    static func short(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        return s < 0 ? String(localized: "in \(units(-s))") : units(s)
    }

    private static func units(_ s: TimeInterval) -> String {
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }

    /// The same instant, said out loud. "2h" is a glance; VoiceOver reads the
    /// abbreviation as a bare letter, so the spoken form spells the unit.
    static func spoken(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        guard s >= 0 else { return String(localized: "in \(spokenUnits(-s))") }
        return String(localized: "\(spokenUnits(s)) ago")
    }

    private static func spokenUnits(_ s: TimeInterval) -> String {
        if s < 3600 {
            let m = max(1, Int(s / 60))
            return m == 1 ? String(localized: "1 minute") : String(localized: "\(m) minutes")
        }
        if s < 86_400 {
            let h = Int(s / 3600)
            return h == 1 ? String(localized: "1 hour") : String(localized: "\(h) hours")
        }
        let d = Int(s / 86_400)
        return d == 1 ? String(localized: "1 day") : String(localized: "\(d) days")
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
/// Its own struct like MusicRow/ExcerptRow — the caller (FeedScreen's
/// shapedRow) mounts it only when a pulse EXISTS and falls back to the plain
/// band + timestamp until one lands, so this view never fakes a price.
struct TokenRow: View {
    let thing: Thing
    let pulse: TokenPulse.Pulse

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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


/// The fat prediction-market row (2026-07-28) — TokenRow's sibling for a
/// watched Kalshi/Polymarket market, and the fix for a real gap: the pulse
/// was being fetched every foreground and rendered NOWHERE, so a market row
/// was a title and a timestamp until you opened its sheet.
///
/// The right stack is the odds, then what's happened to them. Which delta it
/// shows is deliberate: NOT a 24h change (a market's day is meaningless — it
/// moves when the world does) but the move since YOU started watching, the
/// anchor no market site can show you (`watchPriceUsd`, set at watch time).
/// In POINTS, never percent — see `TokenDeltaPill.points`.
///
/// Three states, and the row never bluffs past what it knows: a SETTLED
/// market shows its answer instead of a stale probability; a THIN book says
/// so rather than printing a confident number it can't stand behind (prd §83
/// ②); everything else shows the odds and the delta. Mounted only when a
/// pulse EXISTS, so it can never invent one.
struct PredictionRow: View {
    let thing: Thing
    let pulse: PredictionPulse.Pulse

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        HStack(spacing: DS.Space.s3) {
            BridgeIcon(name: thing.source, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(thing.title)
                    .dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(2)
                if let sub = subtitle {
                    Text(sub)
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                if let won = resolvedYes {
                    // Settled: the answer IS the number now.
                    Text(won ? "Yes" : "No")
                        .dsText(.price16).fontWeight(.bold)
                        .foregroundStyle(DS.textPrimary)
                    Text("Resolved")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                } else {
                    Text("\(Int((pulse.probability * 100).rounded()))%")
                        .dsText(.price16)
                        .foregroundStyle(DS.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                    if let move = pulse.sinceWatched {
                        TokenDeltaPill(change: move, label: "", compact: true,
                                       solid: true, points: true)
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
    }

    /// A settled market reads its answer off the thing itself (stamped once
    /// by `PredictionPulse`), not off the pulse — the stamp survives a
    /// relaunch that empties the in-memory cache.
    private var resolvedYes: Bool? { thing.marketResolvedYes ?? (pulse.resolved ? pulse.yesWon : nil) }

    /// The market's own side ("Kansas City") when it has one, the thin-book
    /// caveat when it applies, and — once settled — the RECEIPT: the odds
    /// the day you followed it (prd §235).
    ///
    /// The receipt is the payoff of the whole feature and it used to render
    /// nowhere except a section on a connect page. It reports your
    /// ATTENTION and nothing else: no payout, no stake, no "you'd have
    /// won" — that sentence belongs to a betting app, not this one (the 5.3
    /// line, `PredictionMoments`' own header).
    private var subtitle: String? {
        if resolvedYes != nil {
            guard let at = thing.watchPriceUsd else { return nil }
            return String(localized: "You followed at \(Int((at * 100).rounded()))%")
        }
        if pulse.thin { return String(localized: "Thinly traded — odds move easily") }
        return nil
    }

    private var spokenLabel: String {
        if let won = resolvedYes {
            return String(localized: "\(thing.title), resolved \(won ? "yes" : "no")")
        }
        return String(localized: "\(thing.title), \(Int((pulse.probability * 100).rounded())) percent")
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

    // MARK: Disk cache (survives cold launch — 2026-07-24)

    /// The in-memory `cache` above is the hot path but dies with the process,
    /// so every relaunch re-downloaded every thumbnail on the first scroll.
    /// This is the backstop: downsampled thumbnails, keyed by the SAME
    /// url+pixel-side identity, written under Caches (the OS may evict it
    /// under storage pressure, which is correct for a cache) and read on a
    /// memory miss before the network. Bounded by a throttled trim.
    private static let diskDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("RemoteImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let diskBudget = 80 * 1024 * 1024   // ~80MB of thumbnails

    private static func diskURL(_ urlString: String, _ side: CGFloat) -> URL? {
        guard let dir = diskDir else { return nil }
        // A hash of the memory key — URLs carry slashes/query and can be long,
        // so a fixed-width digest is the only safe filename. Collision-free in
        // practice (SHA-256), so a hit is never the wrong image.
        let digest = SHA256.hash(data: Data(String(key(urlString, side)).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(name).appendingPathExtension("img")
    }

    /// Decoded downsampled image from disk, or nil. Off the main actor (this
    /// enum is nonisolated), so the file read never blocks a frame.
    private static func diskImage(_ urlString: String, _ side: CGFloat) -> UIImage? {
        guard let durl = diskURL(urlString, side),
              let data = try? Data(contentsOf: durl),
              let img = UIImage(data: data) else { return nil }
        return img
    }

    /// Persist an already-downsampled thumb. PNG when the image carries alpha
    /// (logos/icons — a JPEG would flatten transparency to black), JPEG
    /// otherwise (photos — far smaller). Best-effort; a write failure just
    /// means a future re-download.
    private static func writeDisk(_ image: UIImage, _ urlString: String, _ side: CGFloat) {
        guard let durl = diskURL(urlString, side) else { return }
        let hasAlpha: Bool = {
            guard let info = image.cgImage?.alphaInfo else { return true }
            switch info {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }()
        guard let data = hasAlpha ? image.pngData() : image.jpegData(compressionQuality: 0.8)
        else { return }
        try? data.write(to: durl, options: .atomic)
        trimDiskIfNeeded()
    }

    private static let trimLock = NSLock()
    nonisolated(unsafe) private static var lastTrim = Date.distantPast
    /// Trim the disk cache to budget, oldest-first — throttled to at most once
    /// every few minutes and run detached so a write never waits on it.
    private static func trimDiskIfNeeded() {
        trimLock.lock()
        let due = Date.now.timeIntervalSince(lastTrim) > 300
        if due { lastTrim = .now }
        trimLock.unlock()
        guard due, let dir = diskDir else { return }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys) else { return }
            var entries = files.compactMap { url -> (URL, Date, Int)? in
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                return (url, v.contentModificationDate ?? .distantPast, v.fileSize ?? 0)
            }
            var total = entries.reduce(0) { $0 + $1.2 }
            guard total > diskBudget else { return }
            entries.sort { $0.1 < $1.1 }               // oldest first
            let target = diskBudget * 8 / 10           // trim down to 80%
            for (url, _, size) in entries where total > target {
                try? fm.removeItem(at: url)
                total -= size
            }
        }
    }

    /// The synchronous cache probe — a hit lands in the same render pass, so
    /// a recycled row never flashes its placeholder for an image the session
    /// already holds (an await, however short, is a frame).
    static func cachedImage(urlString: String, targetSide: CGFloat) -> UIImage? {
        cache.object(forKey: key(urlString, targetSide))
    }

    /// The average color of an already-loaded image — what a media head's
    /// wash is drawn from (prd §219). Costs one 1×1 redraw of a thumbnail
    /// this view already downloaded, so the tint never adds a request.
    ///
    /// Deliberately the AVERAGE, not a "dominant"/quantized pick: a k-means
    /// palette pass would be a real cost per card and, for the muddy composite
    /// of a video still, lands somewhere close to this anyway. Saturation is
    /// pushed up and lightness pulled toward the middle before it's returned,
    /// because a raw average trends grey — a wash of grey is just dirt on the
    /// card. Returns nil for an image with no drawable bitmap.
    static func averageColor(of image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let raw = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                          blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard raw.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return raw }
        // A nearly colorless average has no hue worth trusting — let the caller
        // fall back to no wash rather than smearing grey over the card.
        guard s > 0.08 else { return nil }
        return UIColor(hue: h, saturation: min(1, s * 1.6),
                       brightness: min(0.85, max(0.4, b * 1.1)), alpha: 1)
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
        // Disk backstop (2026-07-24): a relaunch's first scroll paints from
        // disk instead of re-downloading. Already downsampled to `targetSide`,
        // so no re-decode-at-size cost. `fresh: false` — a known image, so it
        // assigns flat rather than fading in like a network arrival.
        if cached, let onDisk = diskImage(urlString, targetSide) {
            let cost = Int(onDisk.size.width * onDisk.size.height
                           * onDisk.scale * onDisk.scale * 4)
            cache.setObject(onDisk, forKey: key(urlString, targetSide), cost: cost)
            return .image(onDisk, fresh: false)
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
            writeDisk(thumb, urlString, targetSide)   // survive cold launch
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


/// A remote image drawn at the MEDIUM's own proportions (prd §219, 2026-07-25)
/// rather than squeezed into `RemoteThumb`'s square. Same loader, same cache,
/// same dead-URL fallback — the only difference is that width and height are
/// given separately, so a 16:9 frame arrives as a frame.
///
/// `freshness` is the decay wash (`MediaShape.freshness`): art drains of color
/// as it ages down the feed. 1 is a no-op, so a caller that doesn't opt in
/// pays nothing.
struct RemoteArt: View {
    let urlString: String
    let width: CGFloat
    let height: CGFloat
    /// The bridge whose glyph stands in when the URL turns out dead.
    var fallback: String? = nil
    /// A perishable image (a live-stream frame) changes behind its URL.
    var perishable = false
    var freshness: Double = 1
    var cornerRadius: CGFloat = DS.Radius.control
    @State private var image: UIImage?
    @State private var failed = false

    /// Downsample target — the LONG side, so a wide frame isn't decoded to
    /// its height and then upscaled across.
    private var targetSide: CGFloat { max(width, height) * 3 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed || RemoteImageLoader.isDead(urlString), let fallback {
                ZStack {
                    DS.fillFaint
                    BridgeIcon(name: fallback, size: min(width, height) * 0.62)
                }
            } else {
                ZStack {
                    DS.fillFaint
                    Image(systemName: "photo")
                        .accessibilityHidden(true)
                        .font(.system(size: min(width, height) * 0.34, weight: .medium))
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .saturation(freshness)
        .task(id: urlString) { await load() }
    }

    private func load() async {
        if RemoteImageLoader.isDead(urlString) { failed = true; return }
        if !perishable,
           let hit = RemoteImageLoader.cachedImage(urlString: urlString, targetSide: targetSide) {
            image = hit; return
        }
        image = nil
        failed = false
        switch await RemoteImageLoader.load(urlString: urlString, targetSide: targetSide,
                                            cached: !perishable) {
        case .image(let art, let fresh):
            if fresh { withAnimation(DS.Motion.standard) { image = art } }
            else { image = art }
        case .transientFailure:
            failed = !Task.isCancelled
        case .dead:
            failed = true
        }
    }
}


/// The media row (prd §219, 2026-07-25) — a media source's native anatomy, the
/// same permission `MusicRow` has had since 2026-07-11: in its own room the art
/// leads at the medium's real proportions instead of the All feed's 26pt
/// square. A YouTube still arrives 85×48, a Steam header 103×48, a podcast
/// cover 48×48, a Pinterest pin 32×48 — one row height, so the feed keeps a
/// single rhythm while each medium keeps its shape.
///
/// The art also carries the AGE, as saturation (`MediaShape.freshness`): the
/// top of the feed is in full color and drains as you scroll back. That's the
/// "am I behind?" read with no digit in it, and it claims nothing the record
/// can't support — it charts the item's own age, which the timestamp beside it
/// already says out loud. A live row never decays.
struct MediaRow: View {
    let thing: Thing
    let art: MediaShape.Art
    /// Live RIGHT NOW, from the source's own live set — same honesty contract
    /// as `BandRow.live`: derived from the source, never from the row's age.
    var live: Bool = false

    private var done: Bool { thing.mark == .done }

    /// The channel, show, or publication — stamped into `authorHandle` at
    /// ingest by every feed-follow bridge. Nil on a source that names nothing
    /// there (Steam: the game IS the title), and then the row simply has no
    /// subtitle rather than inventing one.
    private var byline: String? {
        guard let handle = thing.authorHandle?.trimmingCharacters(in: .whitespaces),
              !handle.isEmpty, handle != thing.title else { return nil }
        return handle
    }

    private var freshness: Double {
        live ? 1 : MediaShape.freshness(of: thing.capturedAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Group {
                if let url = thing.previewImageURL, !url.isEmpty,
                   // A Twitch frame is perishable: it renders only while the
                   // live set says the stream is on, or a dead frame would
                   // claim a broadcast that ended (the same rule BandRow
                   // applies to its 26pt slot).
                   thing.source != "Twitch" || live {
                    RemoteArt(urlString: url,
                              width: MediaShape.rowArtWidth(art),
                              height: MediaShape.rowArtHeight,
                              fallback: thing.source,
                              perishable: thing.source == "Twitch",
                              freshness: freshness)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(DS.fillFaint)
                        BridgeIcon(name: thing.source, size: 26)
                    }
                    .frame(width: MediaShape.rowArtWidth(art), height: MediaShape.rowArtHeight)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(thing.title)
                    .dsText(.body17)
                    .foregroundStyle(done ? DS.textTertiary : DS.textPrimary)
                    .strikethrough(done, color: DS.textTertiary)
                    .lineLimit(2)
                if let byline {
                    Text(byline)
                        .dsText(.subhead13)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                if live {
                    HStack(spacing: 4) {
                        Circle().fill(DS.confirm).frame(width: 6, height: 6)
                        Text("Live").dsText(.label12).foregroundStyle(DS.confirm)
                    }
                } else {
                    LiveTimeText(date: thing.capturedAt)
                }
            }
        }
        .padding(.vertical, DS.Space.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ThingVoice.rowLabel(for: thing, title: thing.title,
                                                project: byline, live: live))
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

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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
            // The project tag trailed here until 2026-07-23 (dropped across
            // every shaped row — see BandRow.project's doc for why).
            LiveTimeText(date: thing.capturedAt)
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

    /// WHO is asking leads; when it arrived through a different app that app
    /// reads as a route after it ("the agent · via the app"), and the machine
    /// name stays in the sheet — three flat brand names explained nothing
    /// (ruling 2026-07-06). Sentence case only — no ALL-CAPS eyebrows (design
    /// law, 2026-07-08).
    private var eyebrow: String {
        let asker = thing.provenance.agent ?? thing.provenance.app
        var parts = [asker]
        if thing.provenance.app.lowercased() != asker.lowercased() {
            parts.append("via \(thing.provenance.app)")
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? joined : joined.prefix(1).uppercased() + joined.dropFirst()
    }

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        PhotoWell(thing: thing, size: nil)
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .allowsHitTesting(false)
                Text(thing.title)
                    .dsText(.subhead13).foregroundStyle(.white)
                    .lineLimit(1)
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
    /// The shell redacts itself on background (`RootShell.redactNow`, driven by
    /// privacy.hidePreviews) so the app-switcher snapshot doesn't leak the
    /// corpus. SwiftUI's `.redacted(.placeholder)` blanks Text and shapes but
    /// NOT Image — so until 2026-07-25 every screenshot thumbnail survived into
    /// that snapshot with the setting ON. Nothing in the app read this
    /// environment value. A screenshot is the most sensitive thing this app
    /// holds (a bank balance, a private message), so it opts out by hand.
    @Environment(\.redactionReasons) private var redaction

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        Group {
            if !redaction.isEmpty {
                // A plain well, the same shape and size the image would be —
                // the layout never shifts, the picture simply isn't there.
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(DS.fillFaint)
            } else if size != nil {
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

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text(thing.source)
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

// Reminders retired their own check row (ruling 2026-07-25): the integration
// is read-only, so a reminder renders as the plain band like everything else —
// struck through when done, its state carried by the section it's grouped under
// (FeedScreen's reminders shape), never a check circle that writes nothing.

// MARK: - Notes / chats — the excerpt row (shaped feeds, 2026-07-13)

/// A note's point is its text; a saved conversation's is its opening line.
/// In the notes and chat shapes the row carries an excerpt under the title —
/// same band anatomy (26pt leading slot, time trailing), the body just
/// breathes below the first line. All keeps the plain band.
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

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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
            LiveTimeText(date: thing.capturedAt)
        }
        .padding(.vertical, DS.Space.s2)
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
    /// to the source name, same guard the avatar line already carries. A
    /// Nostr `authorHandle` is the raw hex pubkey (the stable matching key,
    /// not a display string — see `NostrIngest.land`), so it alone routes
    /// through `shortHandle` for a short npub; Farcaster/Bluesky already
    /// store a real handle and stay exactly as they render today.
    private var author: String {
        guard let handle = thing.authorHandle, !handle.isEmpty else { return thing.source }
        return thing.source == "Nostr" ? SocialThread.shortHandle(handle) : handle
    }

    /// The words themselves (2026-07-27, the room's own catch-up with the
    /// sheet's 2026-07-16 ruling): `postText` is the FULL post; `title` is
    /// only ever `titleLine()`'s 80-character clamp, built for a row that
    /// has no room, in a room whose entire content IS the words. Falls back
    /// to `title` for a post landed before `postText` existed (a heal fills
    /// it in on the next sync) — never a permalink.
    private var words: String {
        let full = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? thing.title : full
    }

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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
                // WHY it's here (2026-07-27) — the same `contextLabel` the
                // All feed's `BandRow` already wears in its trailing slot,
                // finally reaching the post's own room: "Liked", "/design",
                // "Mentions you". Tinted the network's own `brandHue` — color
                // lives in the tag, same place V3b already put a project's
                // hue, never in the card itself.
                if let why = SocialThread.contextLabel(for: thing) {
                    Text(why)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.washHue(for: thing.source) ?? DS.tint)
                        .lineLimit(1)
                }
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
            // The post this one answers, above the words, where every client
            // puts it (2026-07-27) — `ThingSheetView`'s own `replyingToRow`
            // already earned this line in the sheet; the room never had it,
            // so a reply to someone else read as a contextless non sequitur.
            if let parent = thing.parent {
                ReplyingToRow(parent: parent)
            }
            Text(words)
                .dsText(.body17).foregroundStyle(DS.textPrimary)
                // A row still has a floor: six lines reads as prose, not a
                // wall — the tap already opens the sheet for the rest, the
                // same convention `ExcerptRow`'s clamp keeps.
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            // The post this one QUOTES (2026-07-27) — `SocialQuoteCard`
            // already rendered in the sheet since 2026-07-16; a quote-post in
            // the room itself read as a bare, contextless line until now.
            if let quote = thing.quote {
                // Context in a row, a door in the sheet — see
                // `SocialQuoteCard.walkable`. A row must not carry a
                // presentation of its own.
                SocialQuoteCard(card: quote, source: thing.source, walkable: false)
            }
            // Every attached image shows, not just the first (item 7 of the
            // 2026-07-27 social pass) — `imageURLs` has held all of them
            // since 2026-07-16, but this row used to draw the row thumbnail
            // (`previewImageURL`) alone. A single image keeps `PostMedia`'s
            // dead-URL collapse; two or more switch to the grid.
            if thing.imageURLs.count > 1 {
                PostImageGrid(urls: thing.imageURLs)
            } else if let media = thing.previewImageURL, !media.isEmpty {
                PostMedia(urlString: media)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }
}

/// The post THIS one answers — "Replying to @alice", above the words
/// (2026-07-27). The room's own copy of `ThingSheetView`'s private
/// `replyingToRow`, with one deliberate difference: **in a row it is a
/// LABEL, not a door.**
///
/// It shipped as a `Button` carrying its own `.sheet(isPresented:)` — a
/// second presentation anchored INSIDE a `List` row, competing with
/// `FeedScreen`'s single `.sheet(item: $feedSheet)` for the same presenting
/// controller. Tapping the row then started the thing sheet and the row's
/// own sheet modifier tore it back down mid-transition: the sheet rose part
/// way and closed again ("opening fc feed items doesn't work — it opens half
/// way and closes", 2026-07-28). Farcaster wore it worst because nearly every
/// cast it lands has a parent (channel casts, mentions, and likes are mostly
/// replies), so nearly every fc row grew the extra sheet.
///
/// `FeedSheetRoute`'s doc comment already recorded this exact failure once —
/// five sibling `.sheet` modifiers on this screen made the first tap silently
/// self-dismiss, which is why the screen has exactly ONE. A row is not the
/// place to reopen that: rows keep one gesture with one meaning (ruling
/// 2026-07-16) — TAP opens the thing sheet — and walking into the parent
/// lives in that sheet, where `ThingSheetView.replyingToRow` routes through
/// the sheet's own single `walkingTo` presentation and works today.
struct ReplyingToRow: View {
    let parent: SocialCard

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: "arrowshape.turn.up.left")
                .accessibilityHidden(true)
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            Text("Replying to @\(SocialThread.shortHandle(parent.handle))")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
            Spacer(minLength: 0)
        }
        // Context, not a control: the row's own tap owns the whole card, and
        // a nested tap target here would beat it on the line it covers.
        .allowsHitTesting(false)
    }
}

/// A post's attached images at card width, when there's more than one —
/// `PostMedia` above handles the single-image case. A 2×2 grid, capped
/// visually at four cells with a "+N" overlay on the last one when there
/// are more (mirrors `ImageMosaicHero`'s tiling, at post-card scale).
struct PostImageGrid: View {
    let urls: [String]
    var height: CGFloat = 160

    private var shown: [String] { Array(urls.prefix(4)) }
    private var overflow: Int { max(0, urls.count - 4) }

    var body: some View {
        let columns = shown.count == 1 ? 1 : 2
        let rows = max(1, Int(ceil(Double(shown.count) / Double(columns))))
        GeometryReader { geo in
            let gap: CGFloat = 4
            let cellW = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellH = (geo.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { c in
                            let idx = r * columns + c
                            if idx < shown.count {
                                ZStack {
                                    RemoteArt(urlString: shown[idx], width: cellW, height: cellH,
                                              cornerRadius: DS.Radius.card)
                                    if idx == 3, overflow > 0 {
                                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                            .fill(.black.opacity(0.45))
                                        Text("+\(overflow)")
                                            .dsText(.heading17).fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                }
                            } else {
                                Color.clear.frame(width: cellW, height: cellH)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// The social room's head (item 5, 2026-07-27) — the room's own roster, the
/// same manager-pattern anatomy `HandleSetupScreen`'s roster wears (prd
/// §184), with one addition: a ring on anyone who posted since this room was
/// last opened. Every other shaped feed already earns a head off
/// `FeedHeatmap`/`FeedInsight`; the social room never has, because none of
/// those aggregate reads (a habit grid, a leaderboard, a distribution bar)
/// says anything worth knowing about a chat-shaped list of posts. Faces do.
struct SocialRosterHero: View {
    let source: String
    let accounts: [SocialAccount]
    /// Watched-account keys with a post landed after this room's own
    /// last-visit stamp — the ring criterion.
    let freshHandles: Set<String>
    let onTap: (SocialAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s3) {
                    ForEach(accounts) { account in
                        faceSlot(account)
                    }
                }
                .padding(.horizontal, DS.Space.s4)
                .padding(.vertical, DS.Space.s1)
            }
            Text(accounts.count == 1
                 ? String(localized: "Watching 1 · tap a face for their room")
                 : String(localized: "Watching \(accounts.count) · tap a face for their room"))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s1)
    }

    private func faceSlot(_ account: SocialAccount) -> some View {
        let fresh = freshHandles.contains(account.key)
        return VStack(spacing: 6) {
            Group {
                if let avatar = account.avatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: 52, fallback: source, circular: true)
                } else {
                    BridgeIcon(name: source, size: 52, circular: true)
                }
            }
            .overlay(
                Circle().strokeBorder(DS.tint, lineWidth: fresh ? 2 : 0)
                    .padding(-3)
            )
            Text(account.title)
                .dsText(.label12).fontWeight(.semibold)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
        }
        .frame(width: 60)
        .contentShape(Rectangle())
        .onTapGesture {
            DSHaptic.tap()
            onTap(account)
        }
    }
}

/// A person's own consecutive replies, read top-to-bottom as one thought
/// (item 6 of the 2026-07-27 social pass) — `ThreadFold.replies` groups a
/// chain of self-replies under its root `Thing`; this is that chain's card.
/// The header (face, name, time) is the root's, same anatomy as `PostCard`;
/// each reply is a plain line under a connecting rule, oldest to newest —
/// the order the person actually wrote it in, not the feed's newest-first.
struct SocialThreadCard: View {
    let head: Thing
    /// Handed down plain from `FeedScreen`'s fold, same render pass — wrapped
    /// into `.keyed` right below for the `ForEach`, so identity diffing never
    /// re-reads a stored property off a model a heal might have deleted
    /// between the fold and this body evaluating (`ThingRowKeying`'s rule).
    let replies: [Thing]

    /// Same Nostr-hex-vs-real-handle split as `PostCard.author` above.
    private var author: String {
        guard let handle = head.authorHandle, !handle.isEmpty else { return head.source }
        return head.source == "Nostr" ? SocialThread.shortHandle(handle) : handle
    }

    /// Same catch-up as `PostCard.words` (2026-07-27) — the full post, not
    /// the row's 80-char `title`.
    private func words(_ thing: Thing) -> String {
        let full = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? thing.title : full
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if let avatar = head.authorAvatarURL, !avatar.isEmpty {
                    RemoteThumb(urlString: avatar, size: 26, fallback: head.source,
                                circular: true)
                } else {
                    BridgeIcon(name: head.source, size: 26)
                }
                Text(author)
                    .dsText(.subhead13).fontWeight(.medium)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                if let why = SocialThread.contextLabel(for: head) {
                    Text(why)
                        .dsText(.label12).fontWeight(.semibold)
                        .foregroundStyle(DS.washHue(for: head.source) ?? DS.tint)
                        .lineLimit(1)
                }
                Spacer()
                LiveTimeText(date: head.capturedAt)
            }
            if let parent = head.parent {
                ReplyingToRow(parent: parent)
            }
            HStack(alignment: .top, spacing: DS.Space.s3) {
                Rectangle()
                    .fill(DS.fillFaint)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(words(head))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(replies.keyed) { item in
                        if item.thing.isLive {
                            Text(words(item.thing))
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            // The root's own images only — folding every reply's pictures
            // into the same grid would misattribute whose picture is whose.
            if head.imageURLs.count > 1 {
                PostImageGrid(urls: head.imageURLs)
            } else if let media = head.previewImageURL, !media.isEmpty {
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

    /// Liveness guard (build 188 — see `ThingRowKeying.swift`). SwiftUI
    /// re-evaluates a LEAF view's body on the model's own observation,
    /// independent of the parent that made it, so a guard in the parent's
    /// `ForEach` closure cannot protect a row already in the tree. The
    /// original body moved to `liveBody`; everything it reads now sits behind
    /// this check.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
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
            LiveTimeText(date: thing.capturedAt)
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

