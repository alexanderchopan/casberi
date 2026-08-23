import SwiftUI
import SwiftData
import Photos
import LinkPresentation
import AVFoundation
import AVKit

/// Prose with the URLs inside it live (2026-08-12, user ruling).
///
/// Until now exactly one body of text in the app had tappable links — a social
/// post's own words (`ThingSheetView.linkedWords`, which now calls this) — and
/// every other prose surface printed a URL as inert characters: a vault note's
/// links, an imported ChatGPT transcript, a release's notes, a feed item's
/// summary. The rule is the same one that ruling already stated, applied
/// everywhere prose is drawn instead of in one place.
///
/// `Capture` is compiled into the extension targets and can't see the design
/// tokens, so it attaches `.link` and nothing else; painting the runs is the
/// app's job. ONE definition, because there are a dozen prose renderers now
/// and a second copy is how one of them quietly stops matching the rest.
/// Colour is the whole signal — no underline, which would be a hairline
/// through running text (design law).
///
/// **SHEET ONLY.** A feed row is a read with ONE gesture (ruling 2026-07-16),
/// so a live link inside a row competes with the tap that opens the thing —
/// the same half-open trap the sibling-`.sheet` bug was. That is a property of
/// where this is CALLED, not of this function: `ThingContentView` is presented
/// by `ThingSheetView` and nowhere else, which is what makes it safe to use
/// throughout that view. Don't reach for it from a row.
///
/// **Never for text a stranger wrote into a security frame.** An approval's
/// command (`CommandCard`) and a spoofed token's "name" are attacker-authored
/// — this codebase already carries a real phishing example ("4,672 USDT
/// Staked • gitos.org") — and making that domain tappable right beside the
/// warning calling it out would arm the very thing the warning exists for.
enum ProseLinks {
    static func rendered(_ text: String) -> AttributedString {
        var attributed = Capture.linkified(text)
        // Collect first, then paint: mutating `attributed` inside its own
        // `runs` iteration walks a collection while it's being rebuilt.
        let ranges = attributed.runs.compactMap { $0.link == nil ? nil : $0.range }
        for range in ranges { attributed[range].foregroundColor = DS.tint }
        return attributed
    }
}

/// Which chart a thing LEADS with, decided once (2026-07-27).
///
/// Three places needed this answer — `ThingContentView.kindContent` (what to
/// draw), `ThingContentView.showsLinkPreview` (whether the sheet's Site row
/// would be a duplicate), and `ThingSheetView`'s detent (a chart is tall, so
/// it opens full-height) — and each had hand-written its own chain of
/// `route(from:)` calls. They had already drifted: the detent check listed
/// Token and Stock but not Kalshi, so a Kalshi market opened half-height with
/// its verbs below the fold. Adding PostHog would have been a fourth clause in
/// three places; it's one case here instead.
enum ThingChart {
    case token(chain: String, address: String)
    case kalshi(series: String, event: String)
    case stock(ticker: String)
    case postHogMetric(event: String)
    case polymarket(conditionId: String)
    /// A watched token with NO resolvable Dexscreener route but a real
    /// `TokenPulse` entry already in memory (2026-08-11) — currently only
    /// reachable in demo mode, where `DemoSeedAll.rooms()` deliberately omits
    /// the content URL (P4, 2026-08-07: a fabricated route would hand
    /// `TokenChartContent` a bogus chain/address to actually FETCH on sheet
    /// open) while `TokenPulse.seedDemo` still gives the row's sparkline real
    /// numbers. Draws from that SAME cached pulse, locally, so the sheet
    /// isn't empty under the one row that has data but no address to fetch
    /// it by.
    case watchedPulse(ref: String)

    /// Charts are a `.link` affordance only — a `.product` previews its page
    /// even when the URL would otherwise parse.
    ///
    /// `@MainActor` (2026-08-11): the `.watchedPulse` fallback reads
    /// `TokenPulse.shared`, itself `@MainActor` — every real call site is
    /// already a SwiftUI view body, so this costs nothing new, it just
    /// states what was already true.
    @MainActor
    static func kind(for thing: Thing) -> ThingChart? {
        guard thing.kind == .link else { return nil }
        if let route = TokenChart.route(from: thing.content) {
            return .token(chain: route.chain, address: route.address)
        }
        if let route = KalshiMarket.route(from: thing.content) {
            return .kalshi(series: route.series, event: route.event)
        }
        if let ticker = StockChart.route(from: thing.content) {
            return .stock(ticker: ticker)
        }
        // PostHog can't ride `route(from:)`: a watched metric's content is a
        // plain project URL, shared verbatim by its annotation, milestone and
        // silence things — the ref is what separates them.
        if thing.source == "PostHog", let event = PostHogWatch.event(from: thing) {
            return .postHogMetric(event: event)
        }
        // Same reasoning as PostHog above: a Polymarket event's URL alone
        // can't identify which of its outcome-markets this row watches
        // (a multi-candidate event shares one page across many markets), so
        // the condition id comes off the sourceRef instead.
        if thing.source == "Polymarket", let id = PolymarketBridge.conditionId(from: thing) {
            return .polymarket(conditionId: id)
        }
        // The demo-only fallback above's own reasoning: only reached once
        // every real route has already failed to match, so a genuine
        // Tokens row with a real Dexscreener content URL always takes the
        // `.token` branch above and never this one.
        if thing.source == "Tokens", let ref = thing.sourceRef,
           TokenPulse.shared.pulse(for: thing) != nil {
            return .watchedPulse(ref: ref)
        }
        return nil
    }
}

/// Content by kind (S19) — the thing shows AS what it is: a screenshot is the
/// image, a link is its preview, a chat reads as a conversation, voice leads
/// with its waveform. Everything here renders only what the record actually
/// holds; nothing is fabricated.
struct ThingContentView: View {
    let thing: Thing

    /// The conversation reading, when the sheet decided this row is one (prd
    /// §367). Passed IN rather than recomputed: parsing a 16,000-character
    /// transcript twice per body evaluation is waste, and — the reason that
    /// matters — a head and a body that each derive their own reading are two
    /// places that can disagree about how many turns a chat had.
    var agent: AgentSheet.Conversation? = nil

    /// True when the `.link` branch below resolves to the LinkPreviewCard,
    /// whose footer already names the host — ThingSheetView's Site row keys
    /// off this exact fact (not a lookalike condition) so the two views
    /// can't drift: a token/Kalshi link renders a chart with no host line,
    /// and its Site row must stay.
    static func showsLinkPreview(_ thing: Thing) -> Bool {
        // A product previews its page the same way a link does, so it dedups
        // the Site row identically — else the host shows twice.
        (thing.kind == .link || thing.kind == .product)
            && ThingChart.kind(for: thing) == nil
            && Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) != nil
    }

    /// A transaction whose whole body is its explorer permalink — plumbing,
    /// not prose (2026-08-12, user: "we don't need to show the url if we have
    /// the button").
    ///
    /// The feed already ruled this way: `ExcerptRow.excerpt` refuses a
    /// bare-URL body with the same test, because a permalink read as 66
    /// characters of hex is noise wherever it is printed. The SHEET never got
    /// that rule, so a mint or a card spend rendered its link as its body.
    /// The `.transaction` kind derives an Explorer disc from that exact same
    /// `Capture.detectURL` read (`VerbDerivation`), so the door is always
    /// there when the text goes.
    ///
    /// Whitespace anywhere means prose that happens to carry a URL — that
    /// still shows. Scoped to `.transaction` rather than applied to every
    /// kind: the kinds whose body is legitimately a bare link (`.link`,
    /// `.product`) draw it as a preview card, and the ones that have no
    /// open-verb of their own would be left with no door at all.
    static func bareLinkBody(_ thing: Thing) -> Bool {
        guard thing.kind == .transaction else { return false }
        let body = thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !body.contains(where: \.isWhitespace) && Capture.detectURL(in: body) != nil
    }

    /// A product's stated price, formatted in its own currency — nil (never
    /// a guess) when the record doesn't carry one.
    static func productPrice(_ thing: Thing) -> String? {
        guard let value = thing.priceValue else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = thing.priceCurrency ?? "USD"
        return formatter.string(from: NSNumber(value: value))
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
        // The kind's own media, then the source's own words (2026-07-22).
        // spacing 0 — every branch below already pads its own bottom, and the
        // summary block pads its own top.
        VStack(alignment: .leading, spacing: 0) {
            kindContent
            summaryBlock
        }
        // Mac polish (2026-07-28): `.textSelection` is an environment value,
        // so ONE modifier here covers every kind's prose — the summary
        // block and every `Text` inside `kindContent`'s nested views,
        // however deep — without touching each call site. Selecting and
        // copying a passage is reflex on Mac; SwiftUI `Text` isn't
        // selectable by default.
        .textSelection(.enabled)
    }

    /// The source's own abstract — a feed item's summary, a task's notes, a
    /// Linear issue's body, the rest of a clamped Readwise highlight. Follows
    /// the media, the way a screenshot's caption follows its image. Skipped
    /// when it would only repeat what's already on screen.
    @ViewBuilder private var summaryBlock: some View {
        let text = (thing.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let dupe = text == thing.title.trimmingCharacters(in: .whitespacesAndNewlines)
            || text == thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, !dupe {
            Text(ProseLinks.rendered(text))
                .dsText(.callout15)
                .foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s3)
        }
    }

    @ViewBuilder private var kindContent: some View {
        // A POST is a post whatever kind it landed as (prd §363). X files its
        // own posts as `.note` and its liked posts as `.link`; Instagram and
        // TikTok file captions and comments as `.note`. Every one of them used
        // to fall through to the branches below — the bare-text default and
        // `LinkPreviewCard` — and so drew either the words a second time under
        // the clamped title, or a preview card of a page that will not
        // describe itself. Routed on the RECORD's shape, ahead of the kind
        // switch, so a source that files a post under some third kind
        // tomorrow is covered the day it lands.
        if SocialSheetSource.shape(for: thing) == .post {
            SocialPostContent(thing: thing)
        } else {
            kindSwitch
        }
    }

    @ViewBuilder private var kindSwitch: some View {
        switch thing.kind {
        case .screenshot:
            ScreenshotContent(assetID: thing.sourceRef, stored: thing.previewImageData)
        case .link:
            // A charted link leads with its curve (the chart is the link's
            // "media", like a screenshot leads with its image); everything
            // else previews.
            if let chart = ThingChart.kind(for: thing) {
                switch chart {
                case .token(let chain, let address):
                    TokenChartContent(thing: thing, chain: chain, address: address)
                case .kalshi(let series, let event):
                    KalshiMarketContent(series: series, event: event)
                case .stock(let ticker):
                    StockChartContent(thing: thing, ticker: ticker)
                case .postHogMetric(let event):
                    // A watched metric leads with its own curve, and the
                    // project's annotations land on it as marks, so a spike
                    // sits beside the deploy that caused it.
                    PostHogMetricContent(thing: thing, event: event)
                case .polymarket(let conditionId):
                    PolymarketMarketContent(conditionId: conditionId, url: thing.content)
                case .watchedPulse(let ref):
                    TokenPulseChartContent(thing: thing, ref: ref)
                }
            } else if thing.source == X402Ingest.source {
                if let url = Capture.detectURL(in: thing.content) {
                    LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
                }
                // A seller leads with its own page, then the catalog it sells:
                // endpoints with their per-call prices, the chains they settle
                // on, and a door to their docs. See `X402SellerContent` — this
                // branch exists because the first attempt put the same idea in
                // the `default:` case below, which these `.link` rows never
                // reach, so it was dead code that a grep-based guard passed.
                X402SellerContent(thing: thing)
            } else if thing.source == "GitHub", thing.sourceRef?.hasPrefix("gh:release:") == true {
                // A release leads with its preview, then its own notes —
                // read live, since `enrichedText` is retrieval-only.
                GitHubReleaseContent(thing: thing)
            } else if thing.source == "GitHub", thing.starCount != nil || thing.repoLanguage != nil {
                // A starred / watched repo leads with its preview, then the
                // language dot and the "since you starred" line.
                GitHubStarContent(thing: thing)
            } else if FeedArticleText.sources.contains(thing.source),
                      FeedArticleText.hasBody(thing)
                        || FeedArticleText.readableURL(for: thing) != nil {
                // THE ARTICLE, AT LAST (2026-08-21). `FeedArticleText` has
                // fetched the readable body of every RSS and Substack link since
                // it shipped, and NO VIEW HAS EVER DRAWN IT: the row showed a
                // headline, the sheet showed a preview card, and the words sat
                // in the store reachable only by asking a question about them.
                //
                // This is the Obsidian exception (§320) for the same reason and
                // with the same shape — `enrichedText` stays retrieval-only as
                // the rule, and this is the fourth NAMED carve-out, not a
                // reversal. There the vault bridge read somebody's notes,
                // indexed them, and showed nobody the note; here the feed
                // bridge reads somebody's articles, indexes them, and shows
                // nobody the article. A reader that already paid for the fetch
                // and then withholds it is the strangest possible outcome.
                //
                // Membership is `FeedArticleText.sources` itself, never a
                // literal pair: the fetcher's own list decides who has a body
                // to draw, so a third source added there is drawn here the same
                // day rather than fetched into silence.
                //
                // The preview card stays ABOVE it — the article's own art and
                // its door out to the site are not replaced by its text.
                if let url = Capture.detectURL(
                    in: thing.content.isEmpty ? thing.title : thing.content) {
                    LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
                }
                // THE BODY IS FETCHED ON OPEN NOW (2026-08-23, prd §455), so
                // this branch is entered for a row that has one OR could get
                // one — see `ArticleBody`, which owns the fetch, the "reading
                // the article" line and the Listen control. The gate above
                // reuses `readableURL`, the fetcher's own eligibility rule, so
                // a row this view offers to read is exactly a row the fetcher
                // will read: a podcast's audio enclosure and a story whose
                // publisher already shipped the whole piece in its summary
                // both fall through to the generic preview below, as before.
                ArticleBody(thing: thing)
            } else if let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            } else if let art = thing.previewImageURL, !art.isEmpty {
                // A link with stored art but no openable URL — an Apple Music
                // LIBRARY play comes back from MusicKit with no song.url, so
                // the thing's content is empty and detectURL finds nothing,
                // yet the record still carries its mzstatic cover. Lead with
                // that art instead of a blank sheet (fix 2026-07-12: every
                // music item opened to an empty sheet).
                StoredArtContent(urlString: art)
            }
        case .product:
            // NOTE (prd §368): the thing SHEET no longer reaches this branch.
            // `PurchaseStage` gives every `.product` a watch reading, and
            // `ThingSheetView` turns `contentShown` off for one — the card
            // above it already leads with this art at size and states the
            // price from the stored pair, so drawing here would print both
            // twice, the second time as a link preview re-scraping the page.
            // Kept as the fallback it has always been: if `watch` ever learns
            // to decline a row, this is what that row falls back to.
            //
            // A product leads with its page preview and photo — the store/deal
            // page in `content`, the product image in `previewImageURL` — the
            // same treatment a link gets, so a product never renders as a bare URL.
            let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content)
            let art = thing.previewImageURL
            if let url {
                LinkPreviewCard(url: url, storedImageURL: art)
            } else if let art, !art.isEmpty {
                StoredArtContent(urlString: art)
            }
            // The price the record holds — a fact of its own, shown beside
            // whatever media rendered above (or, when neither URL nor stored
            // art exist, doing the work of not leaving the sheet blank).
            if let price = Self.productPrice(thing) {
                Text(price)
                    .dsText(.heading17).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            } else if url == nil, (art ?? "").isEmpty, !thing.content.isEmpty {
                // No URL, no art, no price — the sheet used to render nothing
                // here at all. The record's own words are the honest fallback,
                // same as every other kind's default case.
                Text(ProseLinks.rendered(thing.content))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(6)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        case .chat:
            // Only a real TRANSCRIPT reaches here now (prd §363) — the imports
            // (ChatGPT, Claude, Snapchat's saved chats, a DM thread) whose
            // content genuinely is a conversation. A post-kind `.chat` — a
            // cast, a skeet, a note — is caught by the shape branch above,
            // which is where the 2026-07-16 ruling moved to: a post is one
            // person's words, its pictures and what it quotes, never bubbles
            // around its own permalink.
            if let agent {
                // THE CONVERSATION (prd §367). It was on `enrichedText` the
                // whole time — speaker-prefixed, up to 8,000 characters — and
                // this branch drew `content`, which is the opening ask and
                // nothing else. So the sheet you opened to read a chat showed
                // one line of it, and that line was already clamped into the
                // title above.
                //
                // The `enrichedText` exception is the Obsidian one, stated
                // there and true here for the same reason: this is not a
                // payoff fact carved out of a discarded read, it is the thing
                // itself, clamped further out than the row excerpt.
                if !agent.turns.isEmpty {
                    AgentTurnsView(turns: agent.turns, cut: agent.cut,
                                   oneSided: agent.oneSided, source: thing.source)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.bottom, DS.Space.s3)
                } else if !thing.content.isEmpty,
                          thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            != agent.hero {
                    // No readable transcript — a chat landed before the
                    // importers wrote one, or a source whose speaker labels we
                    // do not know. The ask is what we have, and it is drawn
                    // once: the hero test is what stops it appearing directly
                    // under itself on a row whose title IS its ask.
                    ChatBubbles(text: thing.content)
                }
            } else if !thing.content.isEmpty {
                ChatBubbles(text: thing.content)
            }
        case .voice:
            VoiceContent(transcript: thing.content, sourceRef: thing.sourceRef,
                         audio: thing.audio)
        case .file, .output:
            // A folder-picked image carries its own bytes (2026-07-27, the
            // Files heal pass) — lead with the picture, the same way a
            // screenshot leads with ScreenshotContent, instead of a chip
            // naming a file whose whole point IS what's in it.
            // VIDEO IS TESTED FIRST, and the order is load-bearing since the
            // poster heal landed (2026-08-17): a video now carries
            // `previewImageData` like any picture, so the branch below would
            // claim it and draw the file as a still nothing could play.
            if let ref = thing.sourceRef, FilesIngest.isVideoRef(ref) {
                FileVideoContent(ref: ref, name: thing.title, note: thing.content,
                                 poster: thing.previewImageData.flatMap(UIImage.init(data:)))
            } else if let data = thing.previewImageData, let image = UIImage(data: data) {
                FilePictureContent(image: image)
                // The name, size and folder BENEATH the picture (prd §365) —
                // the delivery anatomy. Before this an image file drew its
                // pixels and nothing else, so the one row in the corpus that
                // could say where a file came from said nothing; a non-image
                // file drew this chip alone, repeating the title verbatim
                // under the title.
                FileChip(name: thing.title, note: thing.content, compact: true)
            } else if let ref = thing.sourceRef, FilesIngest.isAudioRef(ref) {
                // Audio leads with its transport, on the same anatomy as the
                // picture above it: the thing itself first, the name and size
                // beneath as the quiet line.
                FileAudioContent(ref: ref, name: thing.title, note: thing.content)
            } else {
                FileChip(name: thing.title, note: thing.content)
            }
        case .event:
            // A moment with a clock (prd §365). A WORKOUT leads with what it
            // measured and puts the clock beneath — a run is its distance
            // first — while an event or a booking leads with when it is. Both
            // are the same stub; only the order differs, because for one of
            // them the time is the headline and for the other it is context.
            let metrics = thing.factList.filter { $0.action == .metric }
            if !metrics.isEmpty { MetricBand(metrics: metrics) }
            MomentStub(start: thing.capturedAt, end: thing.endAt,
                       facts: thing.factList.filter { $0.action != .metric })
        case .contact:
            // Was `default:` — grey prose (prd §365).
            PersonCard(name: thing.title, facts: thing.factList,
                       photo: thing.previewImageData)
        case .accessory:
            // Was `default:` — grey prose, identical whether the accessory was
            // reachable or not (prd §365).
            AccessoryCard(title: thing.title, facts: thing.factList)
        case .mail:
            // Real inbox mail (MailBridge) carries no body — `content` is
            // just "From <sender>" — so its content-area anatomy is the
            // sender, with the same initial-circle identity the feed row
            // already draws, instead of that raw string in a bare text
            // bubble. Demo/sample mail things DO carry real body text with
            // no sender field at all — MailContentView shows whichever facts
            // the record actually has, never both when they'd say the same
            // thing.
            MailContentView(thing: thing)
        case .reminder:
            if let due = thing.dueAt {
                // The same stub an event gets (prd §365), keeping the one
                // thing `ReminderDueRow` did that nothing else did: an overdue
                // deadline READS as overdue rather than as a date with a red
                // word after it.
                MomentStub(start: due, overdue: due < .now, facts: thing.factList)
            } else if !thing.content.isEmpty {
                // No structured due date (a Todoist task, or a Reminders item
                // with none set) — the same bare-text fallback every kind
                // without a dedicated anatomy gets.
                Text(ProseLinks.rendered(thing.content))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(12)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        case .approval:
            if !thing.content.isEmpty { CommandCard(text: thing.content) }
        default:
            // Privacy Pools deposits carry their anonymity-set cover on
            // `enrichedText` (prd §228). The global rule keeps `enrichedText`
            // retrieval-only, but here it IS the payoff — how much privacy the
            // deposit has — so this one source shows it, above the receipt URL.
            // Only deposits set it; alerts and ragequits leave it nil.
            // Peer fills carry the same idea (prd §237): what you actually
            // paid vs. market, decoded off the fill's own IntentSignaled event
            // and otherwise thrown away. Same exception, same reasoning.
            // Railgun unshields carry the same shape (prd §268): the sender is
            // private BY DESIGN, so the row can't say who paid — and that one
            // sentence is the fact a reader most needs and would otherwise get
            // wrong, which is exactly the bar this exception was written for.
            // Only unshields set it; shields leave it nil.
            // Circle x402 is NOT in this list, deliberately: its rows are
            // `.link`, which never reaches this `default:` branch, so naming it
            // here was dead code for a whole pass. Its catalog is drawn by
            // `X402SellerContent` on the `.link` route above.
            if (thing.source == "Privacy Pools" || thing.source == "Peer"
                || thing.source == "Railgun"),
               let cover = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !cover.isEmpty {
                Text(cover)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
            // Obsidian notes get the same exception, for a different reason
            // (2026-08-09): `enrichedText` here isn't a payoff fact carved out
            // of an otherwise-discarded read, it's the note's own words, just
            // clamped further out (8,000 chars vs. the 300-char row excerpt on
            // `content`). Until now the vault bridge read a person's notes,
            // indexed them for search, and showed nobody the note — you could
            // ask about it but never open it and actually read it back.
            // `enrichedText` is a strict prefix-superset of `content` here
            // (both come off the same parsed body), so when it's present it
            // REPLACES the excerpt below rather than repeating its first 300
            // characters twice. A note not yet re-read by the current reader
            // (or still an evicted iCloud placeholder) has no `enrichedText`
            // yet and falls through to the excerpt, same as before.
            if thing.source == "Obsidian",
               let body = thing.enrichedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !body.isEmpty {
                Text(ProseLinks.rendered(body))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            } else if !thing.content.isEmpty, !Self.bareLinkBody(thing) {
                // FOLDED AT A BLOCK, NOT CLAMPED AT TWELVE LINES (2026-08-21).
                // §366 gave the note category a real disclosure and left every
                // OTHER source on the silent cut — so a Reddit save, a Slack
                // message, a Linear description and a Notion block all still
                // ended mid-sentence with no "more" and nothing to scroll, in
                // the branch that catches every source without an anatomy of
                // its own. This is that fix, for the rooms nobody went back for.
                //
                // `markdown: false` deliberately: whether a body is markdown is
                // a per-source FACT (`NoteSheetSource.markdownSources`) and this
                // branch is reached by every source that has no anatomy, so
                // there is no source here to make the claim about. `prose()`
                // falls through to exactly the `ProseLinks.rendered` this line
                // used to call, so link rendering is unchanged.
                //
                // Tier and ink are pinned to what this branch has always drawn.
                // Borrowing the fold must not re-rank the category's type: here
                // the body really is an annotation under a fact, which is the
                // case §366 carved the note sources OUT of.
                NoteProse(text: thing.content,
                          markdown: false,
                          tier: .callout15,
                          ink: DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
        }
    }
}

/// The screenshot itself, from the person's library. Reads only — no prompt
/// lives here; without a grant (or for demo rows with no asset) the frame
/// states what it is instead of pretending.
private struct ScreenshotContent: View {
    let assetID: String?
    /// The corpus's own healed copy (`ScreenshotIngest.heal` since 2026-07-10).
    /// Added 2026-08-02: this loader was the ONLY one of the four that skipped
    /// this rung, so with Photos access denied or limited-out — or the original
    /// deleted — the sheet painted the "In your photos" placeholder while the
    /// feed row it opened from happily drew the stored thumbnail.
    let stored: Data?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(height: 140)
                    .overlay(
                        VStack(spacing: DS.Space.s1) {
                            Image(systemName: "photo")
                                .accessibilityHidden(true)
                                .dsGlyph(22, weight: .regular)
                                .foregroundStyle(DS.textTertiary)
                            Text(Self.absenceLine())
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, DS.Space.s3)
                        }
                    )
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await load() }
    }

    /// WHY THE PICTURE ISN'T HERE, said accurately (prd §365, F5).
    ///
    /// This box used to read **"In your photos"** for all four of its causes —
    /// access denied, access limited and this shot not among the shared ones,
    /// the original deleted from the library with no healed copy stored, or a
    /// demo row with no asset behind it. For the deleted case that sentence is
    /// simply FALSE: it is not in your photos, and telling somebody to go look
    /// for it there is worse than saying nothing. The two recoverable causes
    /// are one tap from fixed and deserve to say so.
    ///
    /// The authorization status is the only one of the four this view can tell
    /// apart cheaply and reliably (the deleted and demo cases are both "the
    /// grant is fine and there are no pixels"), so the copy splits exactly
    /// where the knowledge does and claims nothing beyond it.
    static func absenceLine() -> String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .denied, .restricted:
            return String(localized: "Photos access is off — the words below were read before it changed")
        case .limited:
            return String(localized: "Photos access is limited and this one isn't shared")
        case .notDetermined:
            return String(localized: "Photos hasn't been connected on this device")
        default:
            // Authorized, and still nothing: the original is gone from the
            // library and no copy was stored before it went. Never "in your
            // photos" — it demonstrably is not.
            return String(localized: "This picture is no longer in your library")
        }
    }

    private func load() async {
        // Demo sample refs load their bundled image (the sheet leads with
        // media — a placeholder box on a sample thing reads as broken).
        if let assetID, assetID.hasPrefix("sample:") {
            image = UIImage.demoSample(for: assetID)
            return
        }
        // The corpus's own copy first — instant, and it outlives both the
        // Photos original and the grant. Same order as `PhotoWell` and
        // `ThingShareLink`; this loader is no longer the odd one out.
        if let stored, let saved = UIImage(data: stored) { image = saved }
        guard let assetID,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
                || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited,
              let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [assetID.replacingOccurrences(of: "phasset:", with: "")],
                options: nil).firstObject
        else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true   // iCloud-optimized originals
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 800, height: 800),
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            // Waiting past a network asset's degraded placeholder so the real
            // download isn't discarded — and, now that a stored copy may
            // already be on screen, so a blurry stand-in never REPLACES it
            // (the fix PhotoWell / ThingShareLink / GenCover each carry).
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded { return }
            if let result { image = result }
        }
    }
}

/// A folder-picked image's own picture (2026-07-27) — Files things carry
/// their bytes directly on the model (no PHAsset to fetch), so this just
/// draws what's already there; same framing as `ScreenshotContent`'s image
/// branch, minus the load — there's nothing to load.
private struct FilePictureContent: View {
    let image: UIImage
    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: 280)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)
    }
}

/// The universal Share entry (2026-07-13) — text/URL for most kinds, but a
/// screenshot's whole point IS the image, so sharing it as bare title text
/// read as hollow. Loads the same PHAsset ScreenshotContent already shows and
/// shares the real photo instead. One implementation, used by both the thing
/// sheet's Share row and the Feed row's swipe-to-share.
struct ThingShareLink<Label: View>: View {
    let thing: Thing
    @ViewBuilder let label: () -> Label
    @State private var screenshotImage: UIImage?

    private var shareText: String {
        thing.content.isEmpty ? thing.title : thing.content
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
        Group {
            if (thing.kind == .screenshot || thing.kind == .file), let screenshotImage {
                ShareLink(item: Image(uiImage: screenshotImage),
                          preview: SharePreview(thing.title, image: Image(uiImage: screenshotImage))) {
                    label()
                }
            } else if let url = Capture.detectURL(in: shareText) {
                ShareLink(item: url) { label() }
            } else {
                ShareLink(item: shareText, subject: Text(thing.title)) { label() }
            }
        }
        .onAppear { loadScreenshotIfNeeded() }
    }

    /// Mirrors PhotoWell's loader (ShapedRows.swift) rather than reinventing
    /// a third copy: the corpus's own healed copy first (instant, no Photos
    /// round trip), then the PHAsset — waiting past a network asset's
    /// degraded placeholder callback so Share never hands out a blurry
    /// stand-in (same fix as GenCover/PhotoWell).
    private func loadScreenshotIfNeeded() {
        guard thing.kind == .screenshot || thing.kind == .file, screenshotImage == nil,
              let ref = thing.sourceRef else { return }
        if ref.hasPrefix("sample:") {
            screenshotImage = UIImage.demoSample(for: ref)
            return
        }
        if let data = thing.previewImageData, let stored = UIImage(data: data) {
            screenshotImage = stored
            return
        }
        let assetID = ref.replacingOccurrences(of: "phasset:", with: "")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
            .firstObject else { return }
        Task {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            let loaded: UIImage? = await withCheckedContinuation { cont in
                var reported = false
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 1200, height: 1200),
                    contentMode: .aspectFit, options: options
                ) { img, info in
                    let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if degraded { return }
                    guard !reported else { return }
                    reported = true
                    cont.resume(returning: img)
                }
            }
            if let loaded { screenshotImage = loaded }
        }
    }
}

/// A link's preview — title and image fetched through the system's own
/// LinkPresentation metadata. Falls back to the bare host line offline.
/// When the record already holds art (an Apple Music cover, a pin's photo),
/// that leads — instantly, no live fetch to gamble on; LP fills in the title.
private struct LinkPreviewCard: View {
    let url: URL
    var storedImageURL: String? = nil
    @Environment(\.openURL) private var openURL
    @State private var title: String?
    @State private var image: UIImage?

    var body: some View {
        Button {
            openURL(url)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image {
                    // The image fills a fixed banner and never dictates the
                    // card's width — a bare scaledToFill's ideal size would
                    // stretch the whole card past the screen on a wide
                    // banner (the ZStack-expansion gotcha, same fix).
                    Color.clear
                        .frame(height: 140)
                        .overlay(Image(uiImage: image).resizable().scaledToFill())
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(url.host() ?? url.absoluteString)
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                        .lineLimit(1)
                }
                .padding(DS.Space.s3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        }
        .buttonStyle(PressSpring())
        // Hover on the CARD, before the padding — the lift belongs to the
        // card's own silhouette, not the gutter around it.
        .dsHover()
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await fetch() }
    }

    private func fetch() async {
        // The demo's bundled art, and its wall (2026-08-12). Two separate
        // problems, one branch: a `sample:` ref is a real `URL` with a scheme
        // `URLSession` can't serve, so it fell through to the scrape below
        // and the card came back blank — the same miss `StoredArtContent`
        // already carries its own branch for. And `LPMetadataProvider`
        // SCRAPES THE PAGE, so opening a demo sheet reached the network,
        // which `BridgeRefresh`'s demo gate never sees (the per-view fetch
        // class — see `PredictionDemoBook`). Returning before it also means
        // the demo can never draw a title read off somebody's live site.
        #if DEBUG
        if let stored = storedImageURL, stored.hasPrefix("sample:"),
           let bundled = UIImage.demoSample(for: stored) {
            image = await bundled.dsDownsampled(maxSide: 280)
            return
        }
        #endif
        if DemoMode.isActive { return }
        // Stored art first: it's the record's own media and one cached CDN
        // request away, where LPMetadataProvider re-scrapes the whole page
        // and often comes back with nothing (music.apple.com especially).
        if let stored = storedImageURL, let storedURL = URL(string: stored),
           let (data, _) = try? await URLSession.shared.data(from: storedURL),
           let art = UIImage(data: data) {
            // The card only ever paints this into a 140pt banner — downsample
            // off-main so a full-resolution CDN image doesn't sit decoded in
            // memory for a fraction of its rendered size.
            image = await art.dsDownsampled(maxSide: 280)
        }
        let provider = LPMetadataProvider()
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return }
        title = metadata.title
        guard image == nil, let imageProvider = metadata.imageProvider else { return }
        let fetched: UIImage? = await withCheckedContinuation { continuation in
            _ = imageProvider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
        if let fetched {
            image = await fetched.dsDownsampled(maxSide: 280)
        }
    }
}

/// A record that carries stored art but no openable URL — an Apple Music
/// library play (MusicKit returns no song.url, so the link's content is
/// empty) still holds its mzstatic cover. The sheet leads with that art,
/// square, instead of rendering nothing.
private struct StoredArtContent: View {
    let urlString: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.fillFaint)
                    .frame(height: 140)
                    .overlay(
                        Image(systemName: "music.note")
                            .accessibilityHidden(true)
                            .dsGlyph(22, weight: .regular)
                            .foregroundStyle(DS.textTertiary)
                    )
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task(id: urlString) { await load() }
    }

    private func load() async {
        #if DEBUG
        // Bundled demo art resolves locally, exactly as the row renderer
        // already did (`ShapedRows`' own `sample:` branch) — this view only
        // ever FETCHED, so a `sample:` ref fell through to `URLSession`, came
        // back nothing, and left the placeholder. That made every demo
        // `.product` sheet blank, which is the one case this file's own
        // `.product` comment says the image exists to prevent ("doing the
        // work of not leaving the sheet blank"). Debug only: nothing ships a
        // `sample:` url, so a release build cannot reach this.
        if urlString.hasPrefix("sample:"), let bundled = UIImage.demoSample(for: urlString) {
            image = await bundled.dsDownsampled(maxSide: 560)
            return
        }
        #endif
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ui = UIImage(data: data) else { return }
        // Rendered at most 280pt tall (`frame(maxHeight: 280)` above); no
        // reason to hold a full-resolution decode for that.
        image = await ui.dsDownsampled(maxSide: 560)
    }
}

private extension UIImage {
    /// Off-main downsample to fit within `maxSide` pixels — the same
    /// technique `RemoteImageLoader` uses for remote images (ShapedRows.swift),
    /// applied here to locally-decoded bytes so a detail sheet doesn't hold a
    /// full-resolution bitmap just to paint a small fixed-size banner/card.
    func dsDownsampled(maxSide: CGFloat) async -> UIImage {
        guard size.width > maxSide || size.height > maxSide else { return self }
        return await withCheckedContinuation { cont in
            prepareThumbnail(of: CGSize(width: maxSide, height: maxSide)) {
                cont.resume(returning: $0 ?? self)
            }
        }
    }
}

/// Chat content reads as a conversation — one bubble per paragraph. No
/// speakers are invented; the record holds text, the shape says chat.
///
/// A long imported transcript (ChatGPT, Claude) used to hard-cut at 6
/// paragraphs with no sign anything was missing — a silent truncation, the
/// same class of dishonesty the app polices everywhere else (a cut needs a
/// seam). "Show more" names what's hidden and lets it in.
private struct ChatBubbles: View {
    let text: String
    @State private var expanded = false

    private var paragraphs: [Substring] { text.split(separator: "\n") }
    private static let collapsedCount = 6

    var body: some View {
        let shown = expanded ? paragraphs : Array(paragraphs.prefix(Self.collapsedCount))
        let hiddenCount = paragraphs.count - shown.count
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                Text(ProseLinks.rendered(String(line)))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if hiddenCount > 0 {
                Button {
                    withAnimation(DS.Motion.standard) { expanded = true }
                } label: {
                    Text("Show \(hiddenCount) more")
                        .dsText(.subhead13).foregroundStyle(DS.tint)
                }
                .buttonStyle(.plain)
                .dsHover()
                .padding(.horizontal, DS.Space.s3)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// Voice leads with its waveform — and plays, when the thing keeps its audio
/// file (things captured by the mic do; demo rows don't). The transcript
/// follows when one exists.
///
/// Two callers now (2026-08-17). A `.voice` thing hands its own `sourceRef`
/// and lets this find the recording in `VoiceCapture`'s directory; an audio
/// file in a connected FOLDER hands a `fileURL` it resolved itself, because
/// that file is somewhere only a fresh walk of the folder can say (see
/// `FilesIngest.audio(for:)`). Everything below the transport — the decoded
/// envelope, the transport itself, the session category — is the same for
/// both, which is why this took a parameter rather than a second copy.
private struct VoiceContent: View {
    let transcript: String
    var sourceRef: String? = nil
    var audio: Data? = nil
    /// A file the caller already resolved and holds access to. Wins over
    /// `sourceRef`, and is NOT existence-checked the way the voice directory
    /// is — it came from a walk of the folder moments ago, and re-statting it
    /// here would only add a disk read that can block on iCloud.
    var fileURL: URL? = nil

    @State private var player: AVAudioPlayer?
    @State private var playing = false
    /// The real amplitude envelope, read off the audio file itself — nil
    /// until decoded, or forever when there's no audio to read one from. Was
    /// a hardcoded bar-height array before 2026-07-21 (pure decoration, in an
    /// app that otherwise polices fake status hard); a flat, even bar shape
    /// is the honest placeholder while this hasn't loaded, never invented
    /// peaks and valleys.
    @State private var envelope: [CGFloat]?

    private var audioURL: URL? {
        if let fileURL { return fileURL }
        return sourceRef.flatMap(VoiceCapture.audioURL(for:))
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    private var hasAudio: Bool { audio != nil || audioURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                if hasAudio {
                    Button {
                        toggle()
                    } label: {
                        Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                            .dsSymbolSwap(playing)
                            .dsGlyph(28, weight: .regular)
                            .foregroundStyle(DS.tint)
                            .dsTapTarget(Circle())
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                    .accessibilityLabel(playing ? "Pause" : "Play")
                    // A bare transport glyph — it says the same word to a
                    // cursor as it does to VoiceOver, and follows the state.
                    .dsTooltip(playing ? String(localized: "Pause")
                                       : String(localized: "Play"))
                }
                HStack(spacing: 2) {
                    ForEach(Array((envelope ?? Self.flatBars).enumerated()), id: \.offset) { _, h in
                        Capsule().fill(DS.tint).frame(width: 3, height: h)
                            .opacity(playing ? 1 : 0.7)
                    }
                }
                Spacer()
            }
            if !transcript.isEmpty {
                Text(ProseLinks.rendered(transcript))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(8)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .onDisappear { player?.stop() }
        .task { envelope = await Self.readEnvelope(url: audioURL, data: audio) }
    }

    /// The flat placeholder — 15 bars, all the same height, drawn while the
    /// real envelope hasn't loaded (or never will). Even, not shaped: it
    /// says "audio" without claiming to depict this recording's peaks.
    private static let flatBars = [CGFloat](repeating: 10, count: 15)

    /// Peak amplitude per bar, read straight off the file's PCM samples — 15
    /// bars, normalized so the loudest bar in THIS recording always reaches
    /// full height (there's no absolute loudness to compare against, only
    /// this clip's own shape).
    private static func readEnvelope(url: URL?, data: Data?) async -> [CGFloat]? {
        await Task.detached(priority: .utility) {
            var tempURL: URL?
            defer { tempURL.map { try? FileManager.default.removeItem(at: $0) } }
            let fileURL: URL
            if let url {
                fileURL = url
            } else if let data {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".m4a")
                guard (try? data.write(to: tmp)) != nil else { return nil }
                tempURL = tmp
                fileURL = tmp
            } else {
                return nil
            }
            guard let file = try? AVAudioFile(forReading: fileURL) else { return nil }
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: frameCount),
                  (try? file.read(into: buffer)) != nil,
                  let channelData = buffer.floatChannelData
            else { return nil }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            let bars = 15
            guard frames > 0, channels > 0 else { return nil }
            let samplesPerBar = max(1, frames / bars)
            var peaks = [Float](repeating: 0, count: bars)
            for bar in 0..<bars {
                let start = bar * samplesPerBar
                let end = min(start + samplesPerBar, frames)
                guard start < end else { continue }
                var peak: Float = 0
                for ch in 0..<channels {
                    let samples = channelData[ch]
                    for i in start..<end { peak = max(peak, abs(samples[i])) }
                }
                peaks[bar] = peak
            }
            guard let maxPeak = peaks.max(), maxPeak > 0 else { return nil }
            // 6...22pt, the same range the old hardcoded bars drew in.
            return peaks.map { 6 + CGFloat($0 / maxPeak) * 16 }
        }.value
    }

    private func toggle() {
        if playing {
            player?.pause()
            playing = false
            return
        }
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            if let audio {
                player = try? AVAudioPlayer(data: audio)
            } else if let url = audioURL {
                player = try? AVAudioPlayer(contentsOf: url)
            }
        }
        player?.play()
        playing = player?.isPlaying ?? false
    }
}

/// A video file sitting in the connected folder, with a player (2026-08-17).
///
/// The audio sibling below, one medium over, and it reuses that whole resolve:
/// the fresh-walk lookup, the four-case answer and the handle that holds the
/// folder's security scope open for the player's lifetime. Only the surface
/// differs, because a waveform is the wrong picture of a video — this draws
/// the frames.
///
/// It leads with the POSTER while the resolve is in flight rather than an
/// empty box, so the sheet opens on the same pixels the row was showing a
/// moment ago and the player takes their place. `VideoPlayer` renders its own
/// transport, so there is no play button of ours to keep honest here — until
/// it exists there is simply a still, which claims nothing.
///
/// VALUES, never the `Thing`, for the same two reasons `FileAudioContent`
/// gives: no held model to guard, and nothing to trap on when the folder's
/// prune deletes this row with the sheet open.
private struct FileVideoContent: View {
    let ref: String
    let name: String
    let note: String
    let poster: UIImage?

    @State private var handle: FilesMediaHandle?
    @State private var player: AVPlayer?
    @State private var status: Status = .resolving

    private enum Status { case resolving, ready, notDownloaded, missing, unreachable }

    private var line: String? {
        switch status {
        case .resolving, .ready: return nil
        case .notDownloaded: return String(localized: "Still downloading from iCloud — it'll play once the file is here.")
        case .missing: return String(localized: "This file isn't in the folder anymore.")
        case .unreachable: return String(localized: "Can't reach the folder right now.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                } else if let poster {
                    // The frame the grid already drew — the sheet opens on it
                    // rather than on a hole, and the player replaces it in
                    // place.
                    Image(uiImage: poster)
                        .resizable().scaledToFit()
                } else {
                    // No poster and no player: a video whose heal hasn't run
                    // yet, or one AVFoundation couldn't read a frame from.
                    // Nothing is drawn — an empty frame with a glyph in it
                    // would be a picture of a video we do not have.
                    Color.clear.frame(height: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)

            if let line {
                Text(line)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
            FileChip(name: name, note: note, compact: true)
        }
        .task(id: ref) { await resolve() }
        .onDisappear {
            // Order matters: the player stops reading the file BEFORE the
            // scope that made it readable is given back.
            player?.pause()
            player = nil
            handle?.release()
            handle = nil
        }
    }

    private func resolve() async {
        switch await FilesIngest.media(for: ref) {
        case .ready(let resolved):
            handle?.release()
            handle = resolved
            player = AVPlayer(url: resolved.url)
            status = .ready
        case .notDownloaded: status = .notDownloaded
        case .missing: status = .missing
        case .unreachable: status = .unreachable
        }
    }
}

/// An audio file sitting in the connected folder, with a transport
/// (2026-08-17).
///
/// A folder's m4a landed as `kind: .file` like everything else and drew a chip
/// naming a file nothing could open — while the app has had a working player
/// the whole time, gated to `kind == .voice` and to `VoiceCapture`'s own
/// directory. This is that same transport pointed at a file the person
/// already has, and it adds no new stored field, no request and no copy.
///
/// The player lives HERE and not on the feed row on purpose: a row is a read
/// with ONE gesture (ruling 2026-07-16), and a second control inside a row is
/// the half-opening-sheet class this codebase has already paid for.
///
/// VALUES, never the `Thing` — so there is no held model to guard (the
/// build-188 leaf rule) and nothing here can trap on a row the folder's own
/// prune deletes while this sheet is open.
private struct FileAudioContent: View {
    let ref: String
    let name: String
    let note: String

    /// Kept apart from `status` because the handle outlives the frame that
    /// made it: it holds the folder's security scope open for as long as the
    /// transport can be used, and `onDisappear` is what balances that.
    @State private var handle: FilesMediaHandle?
    @State private var status: Status = .resolving

    private enum Status { case resolving, ready, notDownloaded, missing, unreachable }

    /// What a non-playable file says. Four outcomes reach here and three of
    /// them are not errors, so each gets its own sentence rather than one
    /// silence over all of them — the honesty rule's no-fake-status half, on
    /// the screen where the only alternative is a play button that does
    /// nothing.
    private var line: String? {
        switch status {
        case .resolving, .ready: return nil
        case .notDownloaded: return String(localized: "Still downloading from iCloud — it'll play once the file is here.")
        case .missing: return String(localized: "This file isn't in the folder anymore.")
        case .unreachable: return String(localized: "Can't reach the folder right now.")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if case .ready = status, let handle {
                // No transcript: a file from a folder carries no words of its
                // own, and this app does not transcribe what it did not
                // record. The waveform and the transport are the content.
                VoiceContent(transcript: "", fileURL: handle.url)
            }
            if let line {
                Text(line)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.bottom, DS.Space.s3)
            }
            // Compact in every state, not just the playable one — the chip
            // must not restyle itself when the resolve lands, or opening the
            // sheet reads as the layout jumping.
            FileChip(name: name, note: note, compact: true)
        }
        .task(id: ref) { await resolve() }
        .onDisappear {
            handle?.release()
            handle = nil
        }
    }

    private func resolve() async {
        switch await FilesIngest.media(for: ref) {
        case .ready(let resolved):
            // A `.task(id:)` re-run releases the previous window rather than
            // leaking it — nested scopes are refcounted, so an unbalanced
            // start is a real leak and not a no-op.
            handle?.release()
            handle = resolved
            status = .ready
        case .notDownloaded: status = .notDownloaded
        case .missing: status = .missing
        case .unreachable: status = .unreachable
        }
    }
}

/// A file is a document chip — name, extension badge, and its note when the
/// record carries one.
private struct FileChip: View {
    let name: String
    let note: String
    /// Under a picture (prd §365): the glyph goes, because the pixels above
    /// have already said what this is far better than a `doc` icon can, and the
    /// note becomes the quiet line rather than the payload.
    var compact = false

    private var ext: String? {
        let parts = name.split(separator: ".")
        return parts.count > 1 ? parts.last.map { String($0).uppercased() } : nil
    }

    /// The note's first line, unless it is just the name over again.
    private var metadata: String? {
        let first = note.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !first.isEmpty, first != name else { return nil }
        return first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s3) {
                if !compact {
                    Image(systemName: "doc")
                        .accessibilityHidden(true)
                        .dsGlyph(17, weight: .medium)
                        .foregroundStyle(DS.tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .dsText(.callout15).foregroundStyle(DS.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                    // Under a picture the note is the quiet metadata line
                    // (size, folder) rather than the payload, so it sits with
                    // the name instead of below the whole chip.
                    // Never the name again. Several bridges open a file's
                    // `content` with its own title (the Files heal writes the
                    // OCR'd name first), and repeating it here would be the
                    // exact stutter this chip moved under the picture to stop.
                    if compact, let metadata {
                        Text(metadata)
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if let ext {
                    Text(ext)
                        .dsText(.label12).foregroundStyle(DS.textSecondary)
                        .padding(.horizontal, DS.Space.s2).frame(minHeight: 22)
                        .background(DS.gray100, in: Capsule(style: .continuous))
                }
                Spacer()
            }
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            if !compact, !note.isEmpty {
                Text(ProseLinks.rendered(note))
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A mail thing's content-area anatomy: the sender, in the same
/// initial-circle identity the feed row draws (SenderInitial, ShapedRows.swift),
/// plus whatever body text the record actually carries. `MailBridge` stores
/// no body (`content` is just "From <sender>"), so real inbox mail shows only
/// the sender row; demo/sample mail carries real body text with no sender
/// field, and shows only that — never a duplicate "From …" line next to the
/// same fact restated.
private struct MailContentView: View {
    let thing: Thing

    /// New rows carry the sender in `authorHandle`; older rows stored it only
    /// as the content's "From …" prefix — the same fallback the feed row uses,
    /// so a mail thing never loses its sender to a schema gap.
    private var sender: String? {
        if let from = thing.authorHandle, !from.isEmpty { return from }
        if thing.content.hasPrefix("From ") {
            let from = String(thing.content.dropFirst("From ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return from.isEmpty ? nil : from
        }
        return nil
    }

    private var isFromLine: Bool { thing.content.hasPrefix("From ") }

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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let sender {
                HStack(spacing: DS.Space.s3) {
                    SenderInitial(sender: sender, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SenderInitial.displayName(of: sender))
                            .dsText(.heading17).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        // The address itself, under the display name, when the
                        // two really differ — the name is what you recognize,
                        // the address is what tells you it's really them.
                        if sender != SenderInitial.displayName(of: sender) {
                            Text(sender)
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if !isFromLine, !thing.content.isEmpty {
                Text(ProseLinks.rendered(thing.content))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(10)
            }
            // WHY THE SHEET STOPS HERE (prd §365). `MailBridge` stores no body
            // — `content` is literally "From <sender>" — so this anatomy was a
            // sender chip on an otherwise blank page, with nothing saying
            // whether the message was empty or merely absent. It is absent, and
            // that is a real property of the bridge worth stating once: the
            // header is here so the mail is findable, and the message is where
            // it always was. Gated on there being no body, so a demo/sample
            // mail thing that DOES carry text never claims otherwise.
            if isFromLine || thing.content.isEmpty {
                Text("The header only — open it in Mail to read the message.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A reminder's structured deadline — read straight off `dueAt`, the same
/// field the "Coming up" lane already reads (KeptAskComposers.swift), so the
/// sheet finally shows the date the app is quietly tracking for you rather
/// than only the free-text title.
private struct ReminderDueRow: View {
    let due: Date

    private var overdue: Bool { due < .now }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
                .dsGlyph(15, weight: .medium)
                .foregroundStyle(overdue ? DS.destructive : DS.tint)
            Text(due.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .dsText(.body17)
                .foregroundStyle(overdue ? DS.destructive : DS.textPrimary)
            if overdue {
                Text("Overdue")
                    .dsText(.label12).foregroundStyle(DS.destructive)
            }
            Spacer()
        }
        .padding(DS.Space.s3)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// What the agent wants to run — the exact ask, monospaced, nothing
/// paraphrased. The verbs below it are the answer.
private struct CommandCard: View {
    let text: String

    var body: some View {
        Text(text)
            .dsText(.mono13)
            .foregroundStyle(DS.textPrimary)
            .lineLimit(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s3)
            .background(DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(.horizontal, DS.Space.s4)
            .padding(.bottom, DS.Space.s3)
    }
}

// MARK: - The stub: a moment with a clock (2026-08-12, prd §365)

/// A moment, drawn as a ticket stub rather than a formatted string in a label
/// column — an event, a booking, a workout, a reminder.
///
/// It replaces `ScheduleCard` (a clock glyph beside `content`, verbatim) and
/// `ReminderDueRow`, and it also retires the spec table's "When" and "Due"
/// rows: those existed only because the content anatomy was too thin to carry
/// the fact, so a calendar event printed its one string twice on one screen.
///
/// **Everything here is read from a real Date.** `ScheduleIngest` formatted the
/// start into `content` at ingest and left the reader nothing to compute from,
/// which is why the sheet could never say "Thursday" or "in 2 hours". The start
/// has always been `capturedAt`; the end is `endAt` (new, and the one field
/// this pass had to add).
///
/// NO PERFORATION, despite the stub idea: build brief §8 bans hairlines with
/// zero exceptions, and a dashed rule is a line. The two halves separate the
/// way everything else in this app separates — a slightly stronger fill on the
/// clock band than on the facts below it.
private struct MomentStub: View {
    let start: Date
    /// nil when no end is really known — an all-day event, or a kind that has
    /// no duration. A range is shown ONLY when this is present; a start plus a
    /// guessed length would be the §83 fake status.
    var end: Date?
    /// A reminder past its due date. Colours the block and replaces the clock
    /// with the word, because "Overdue" IS the reading — the date beneath it is
    /// the detail.
    var overdue = false
    var facts: [ThingFact] = []

    private var sameDay: Bool {
        guard let end else { return true }
        return Calendar.current.isDate(start, inSameDayAs: end)
    }

    /// "14:00 – 15:00", or just the start when there is no known end. An end on
    /// another day states its date too rather than implying it finishes an hour
    /// after it began.
    /// An all-day event, declared by its own fact rather than inferred from a
    /// midnight start — see `ThingFact.Action.allDay` for why the signal has to
    /// be explicit.
    private var allDay: Bool { facts.contains { $0.action == .allDay } }

    private var clockLine: String {
        if allDay { return String(localized: "All day") }
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return from }
        let to = sameDay
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .shortened)
        return "\(from) – \(to)"
    }

    /// "in 2 hours · 1 hr". The relative half is localized by Foundation; the
    /// duration half appears only when there is a real end to measure.
    private var relativeLine: String {
        let relative = start.formatted(.relative(presentation: .named))
        guard let end, end > start else { return relative }
        return "\(relative) · \(Self.duration(from: start, to: end))"
    }

    /// "45 min" / "1 hr" / "1 hr 30 min". Minutes only under an hour; whole
    /// hours drop the minutes rather than reading "2 hr 0 min".
    static func duration(from: Date, to: Date) -> String {
        let minutes = max(1, Int((to.timeIntervalSince(from) / 60).rounded()))
        let (h, m) = (minutes / 60, minutes % 60)
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            clockBand
            // The all-day marker is CONSUMED by the clock band above, so it
            // never also draws as a row saying the same thing one line down.
            let rows = facts.filter { $0.action != .allDay }
            if !rows.isEmpty {
                FactRows(facts: rows)
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.bottom, DS.Space.s2)
            }
        }
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    private var clockBand: some View {
        HStack(spacing: DS.Space.s3) {
            dayBlock
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(overdue ? String(localized: "Overdue") : clockLine)
                    .dsText(.stat24)
                    .foregroundStyle(overdue ? DS.destructive : DS.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(relativeLine)
                    .dsText(.subhead13)
                    .foregroundStyle(overdue ? DS.destructive : DS.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
    }

    /// The date, as a block you read at a glance. Weekday abbreviated by
    /// Foundation — NOT uppercased, which §8 bans.
    private var dayBlock: some View {
        VStack(spacing: 0) {
            Text(start.formatted(.dateTime.weekday(.abbreviated)))
                .dsText(.label11)
                .foregroundStyle(overdue ? DS.destructive : DS.tint)
            Text(start.formatted(.dateTime.day()))
                .dsText(.stat24)
                .foregroundStyle(overdue ? DS.destructive : DS.textPrimary)
            Text(start.formatted(.dateTime.month(.abbreviated)))
                .dsText(.label11)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(width: 56)
        .padding(.vertical, DS.Space.s2)
        .background(overdue ? DS.destructive.opacity(0.12) : DS.gray100.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}

// MARK: - Fact rows: the un-joined parts, shared by every Life anatomy

/// The rows a `ThingFact` list draws — a label, its value, and (when the value
/// really is reachable) a tap that hands it off.
///
/// EVERY ACTION IS GATED on `canOpenURL` (prd §275). An unclaimed scheme is
/// refused asynchronously by LaunchServices and neither `UIApplication.open`'s
/// completion nor SwiftUI's `openURL` reports the refusal — which is exactly
/// how "Open in Photos" could be a disc that did nothing, invisibly, for weeks.
/// `tel:` is claimed on an iPhone and on nothing else, so a phone number on a
/// Mac or an iPad renders as a fact rather than as a control that swallows the
/// tap. A fact is never worse for being unactionable; a dead control is.
///
/// No dividers between rows: §8 bans hairlines outright, so rows separate by
/// their own spacing.
private struct FactRows: View {
    let facts: [ThingFact]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(facts) { fact in
                if let url = Self.destination(for: fact),
                   UIApplication.shared.canOpenURL(url) {
                    Button { openURL(url) } label: { row(fact, actionable: true) }
                        .buttonStyle(.plain)
                        .dsHover()
                } else {
                    row(fact, actionable: false)
                }
            }
        }
    }

    private func row(_ fact: ThingFact, actionable: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Text(fact.label)
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 72, alignment: .leading)
            Text(fact.value)
                .dsText(.callout15)
                .foregroundStyle(actionable ? DS.tint : DS.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if actionable {
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
                    .dsGlyph(11, weight: .semibold)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, DS.Space.s1)
        .contentShape(Rectangle())
    }

    /// Where a fact's tap lands, or nil when it isn't a hand-off.
    ///
    /// A phone number is stripped to what a dialler accepts — Contacts stores
    /// "+385 91 234 5678" for humans and `tel:` wants no spaces — keeping the
    /// leading `+` and digits and nothing else, so a number that arrives with
    /// letters in it (a vanity line) yields no URL rather than a wrong one.
    static func destination(for fact: ThingFact) -> URL? {
        switch fact.action {
        case .call:
            let dialable = fact.value.filter { $0.isNumber || $0 == "+" }
            guard dialable.count >= 3 else { return nil }
            return URL(string: "tel:\(dialable)")
        case .mail:
            guard fact.value.contains("@") else { return nil }
            return URL(string: "mailto:\(fact.value)")
        case .map:
            guard let q = fact.value.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) else { return nil }
            return URL(string: "https://maps.apple.com/?q=\(q)")
        case .web:
            guard let url = URL(string: fact.value),
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            return url
        case .none, .metric, .state, .allDay:
            return nil
        }
    }
}

/// The numbers a workout actually recorded, side by side — what the run WAS,
/// where the sheet used to show a calendar clock beside the word "Workout".
///
/// Labels are sentence case ("Duration", "Pace / km"), never the ALL-CAPS
/// eyebrows §8 bans. Units carry their own case ("km" is a unit, not a word).
private struct MetricBand: View {
    let metrics: [ThingFact]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(metrics) { metric in
                VStack(spacing: DS.Space.s1) {
                    Text(metric.value)
                        .dsText(.stat24)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metric.label)
                        .dsText(.label11)
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, DS.Space.s3)
        .padding(.horizontal, DS.Space.s2)
        .frame(maxWidth: .infinity)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

// MARK: - The card: something that persists (2026-08-12, prd §365)

/// A person, drawn as an identity rather than a sentence.
///
/// `.contact` had NO case in `kindSwitch` at all — it fell to `default:` and
/// rendered `ContactsIngest.line(for:)`'s output as grey prose
/// ("Designer · Studio · ana@studio.com"), a database row printed as a sentence
/// with not one character of it tappable. The facts behind that string are now
/// kept as parts, so the ways to reach somebody are the things you tap.
///
/// Takes values, not the `Thing` — so it stores no model and the build-188
/// leaf-liveness rule has nothing to catch here (see `ThingRowKeying.swift`).
/// Its caller is inside `ThingContentView.liveBody`, which is already guarded.
private struct PersonCard: View {
    let name: String
    let facts: [ThingFact]
    /// The contact's own photo, landed by `ContactsIngest.healPhotos`. nil for
    /// most people, and for everyone until that bounded pass reaches them —
    /// the initials circle below is the fallback, not a placeholder to be
    /// ashamed of.
    var photo: Data?

    /// The role line under the name — the two facts that describe rather than
    /// dial. Joined here rather than drawn as rows because "Designer" and
    /// "Studio" are one idea, and two label columns for them is the shape this
    /// anatomy exists to get away from.
    private var subtitle: String? {
        let parts = facts.filter { $0.label == "Role" || $0.label == "Company" }
            .map(\.value)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var reachable: [ThingFact] {
        facts.filter { $0.action == .call || $0.action == .mail }
    }

    /// Everything that isn't a way to reach them and isn't already the
    /// subtitle — the address, the birthday, the website (2026-08-14).
    ///
    /// This card used to draw `reachable` and NOTHING ELSE, so a fact whose
    /// action was neither `.call` nor `.mail` was stored and invisible. That
    /// made the whole widening of the Contacts fetch pointless on its own: an
    /// address would have landed, been indexed, been searchable, and never once
    /// appeared on the screen about that person. Written as a leftover rather
    /// than a second allowlist, so the next fact kind added shows up by default
    /// instead of silently vanishing.
    private var standing: [ThingFact] {
        facts.filter {
            $0.action != .call && $0.action != .mail
                && $0.label != "Role" && $0.label != "Company"
        }
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Pinned BEFORE the clip: a bare resizable image in a stack
                    // expands the stack to the image's own size (the gotcha
                    // this codebase has already paid for).
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .accessibilityLabel(name)
            } else {
                Text(initials)
                    .dsText(.heading22)
                    .foregroundStyle(DS.textPrimary)
                    .frame(width: 76, height: 76)
                    .background(DS.gray100, in: Circle())
            }
            Text(name)
                .dsText(.heading22)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }
            // ONE slab, both groups — the ways to reach them first, because
            // that is what the sheet is opened for, then what is true about
            // them. Two slabs would draw a divider by whitespace where §8 bans
            // one by line.
            let rows = reachable + standing
            if !rows.isEmpty {
                FactRows(facts: rows)
                    .padding(DS.Space.s3)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                     style: .continuous))
                    .padding(.top, DS.Space.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A HomeKit accessory — the app's only pure LIVE-STATE row, finally drawn as
/// one.
///
/// `.accessory` had no case either, so a reachable lock and an unreachable one
/// rendered identically in the same grey prose — and which of the two it is
/// happens to be the entire reason to open the sheet. The state leads, in its
/// own tone; everything else is a quiet fact beneath it.
///
/// It states what it CAN'T say, too: HomeKit exposes no historical event query
/// and this bridge reads no per-service characteristics, so "Reachable" is a
/// claim about the connection, never about whether the door is locked. Saying
/// so is cheaper than letting somebody infer the stronger reading.
private struct AccessoryCard: View {
    let title: String
    let facts: [ThingFact]

    private var state: ThingFact? { facts.first { $0.action == .state } }
    private var rest: [ThingFact] { facts.filter { $0.action != .state } }
    private var reachable: Bool { state?.value == "Reachable" }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let state {
                HStack(spacing: DS.Space.s3) {
                    Circle()
                        .fill(reachable ? DS.confirm : DS.destructive)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.value)
                            .dsText(.heading17)
                            .foregroundStyle(DS.textPrimary)
                        Text(state.label)
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((reachable ? DS.confirm : DS.destructive).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                 style: .continuous))
            }
            if !rest.isEmpty {
                FactRows(facts: rest)
                    .padding(DS.Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: DS.Radius.card,
                                                     style: .continuous))
            }
            // The ceiling, said out loud. Reachability is about the
            // connection; nothing here reads a lock's bolt.
            Text("Read-only — the Home app controls it.")
                .dsText(.subhead13)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title), \(state?.value ?? "")"))
    }
}

/// A token's price, drawn natively — the full TokenChartView read (prd 51):
/// price, the delta pill, range chips, the scrubbable line, and (2026-07-14)
/// the since-you-watched anchor plus a market-structure strip (liquidity,
/// 24h volume, FDV, market cap — the Dexscreener pair payload that resolved
/// the token; a stat the pair doesn't report simply isn't shown).
/// Illiquid/dead tokens have no pool anywhere, so it falls back to the
/// plain link, never an empty chart.
///
/// A token discovered elsewhere — GeckoTerminal trending, a pasted
/// Dexscreener link — draws the exact same chart (trending is discovery,
/// watching stays the Tokens bridge's explicit tap), so it also carries the
/// one-verb Watch row (2026-07-15) — the same door TokenQuickSheet already
/// offers a held-but-unwatched wallet holding, here for any token thing.
private struct TokenChartContent: View {
    let thing: Thing
    let chain: String
    let address: String
    @State private var stats: TokenStats?
    @Environment(\.modelContext) private var modelContext
    // Optional on purpose (2026-07-17): this content mounts from sheet
    // chains that don't all carry the store (the deep-link/-openThing sheet
    // hangs outside RootShell's `.environment(bridges)`), and the REQUIRED
    // form is a mount-time fatal — the sheet crashed the app before the
    // first frame. Missing store only skips bridge registration on Watch.
    @Environment(BridgeStore.self) private var store: BridgeStore?
    @State private var resolved: TokenWatch.Resolved?
    @State private var watchedTitle: String?

    /// The watch-time anchor — only when the record really carries one
    /// (tokens watched before the field stay anchorless, honestly).
    private var since: (price: Double, date: Date)? {
        guard thing.source == "Tokens", let p = thing.watchPriceUsd, p > 0
        else { return nil }
        return (p, thing.capturedAt)
    }

    /// This IS the watchlist's own thing — the row below already says so via
    /// its "since you watched" anchor, so a second Watch verb would be a
    /// dead control on the one place it can never apply.
    private var offersWatch: Bool { thing.source != "Tokens" }

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
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            TokenChartView(chain: chain, address: address, since: since,
                           hero: true,
                           // The price as one object (prd §369 amendment). The
                           // sheet's own title stands down for a charted row,
                           // so this card carries the identity.
                           object: PriceObjectSource.identity(
                               title: thing.title,
                               authorHandle: thing.authorHandle)) {
                // No pool (dead/illiquid) — the plain link, honestly.
                if let url = URL(string: "https://dexscreener.com/\(chain)/\(address)") {
                    LinkPreviewCard(url: url)
                }
            }
            statStrip
            if offersWatch { watchRow }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { stats = await TokenStats.fetch(chain: chain, address: address) }
        .task {
            guard offersWatch else { return }
            let route = TokenQuickRoute(chain: chain, address: address)
            if let already = route.watchedThing(in: modelContext) {
                watchedTitle = already.title
            } else {
                resolved = await TokenWatch.search(address).first { $0.id == route.id }
            }
        }
    }

    /// One real verb: Watch — the same one-tap door TokenQuickSheet offers a
    /// held-but-unwatched holding, styled to sit inline among this content's
    /// other quiet cards rather than as a full sheet row.
    @ViewBuilder private var watchRow: some View {
        if let watchedTitle {
            // The settled state wears the same full-width capsule the verb
            // did — quiet fill, confirm check — so watching doesn't snap the
            // layout, and it stays a label, not a control.
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                    .dsGlyph(15, weight: .bold)
                    .foregroundStyle(DS.confirm)
                Text("Watching \(watchedTitle)")
                    .dsText(.callout15).fontWeight(.semibold)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(DS.fillFaint, in: Capsule(style: .continuous))
        } else if let resolved {
            // The one verb, at full Cash-App weight (Big money, 2026-07-17):
            // a tint-filled capsule spanning the sheet.
            Button {
                DSHaptic.tap()
                if let watched = TokenWatch.add(resolved, context: modelContext) {
                    DSHaptic.success()
                    watchedTitle = watched.title
                    if let store {
                        TokenWatch.registerBridge(store: store, context: modelContext)
                    }
                } else {
                    watchedTitle = "\(resolved.name) · $\(resolved.symbol)"
                }
            } label: {
                Text("Watch this token")
                    .dsText(.body17).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.tint, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PressSpring())
            .dsHover()
        }
    }

    /// The market's shape, re-ranked (Big money, 2026-07-17): the two
    /// biggest facts — market cap and 24h volume, in rank order — lead as
    /// bold cards; whatever else the pair reported follows in the SAME
    /// two-column grid as smaller cards (user checkpoint 2026-07-17: the
    /// free-floating chips broke the block's cohesion — demotion is scale,
    /// not a different anatomy). Still cells only for stats actually
    /// reported: a token with no cap leads with what it HAS (FDV honestly
    /// labeled FDV), never an invented number.
    @ViewBuilder private var statStrip: some View {
        if let stats {
            let cells: [(String, Double)] = [
                ("Market cap", stats.marketCap), ("24h volume", stats.volume24h),
                ("FDV", stats.fdv), ("Liquidity", stats.liquidityUsd),
            ].compactMap { label, value in value.map { (label, $0) } }
            let lead = cells.prefix(2)
            let rest = cells.dropFirst(2)
            VStack(spacing: DS.Space.s2) {
                if !lead.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(lead, id: \.0) { label, value in
                            statCard(label: label, value: value, lead: true)
                        }
                        // A lone cell keeps its half-width column — three
                        // reported stats must not turn the grid ragged.
                        if lead.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
                if !rest.isEmpty {
                    HStack(alignment: .top, spacing: DS.Space.s2) {
                        ForEach(rest, id: \.0) { label, value in
                            statCard(label: label, value: value, lead: false)
                        }
                        if rest.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                    }
                }
            }
        }
    }

    /// One card anatomy for every stat — the tile radius, a full s4 pad, the
    /// value in the rounded money voice. Lead wears stat24; the rest demote
    /// to price16 in the same seat.
    private func statCard(label: String, value: Double, lead: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .lineLimit(1)
            Text(TokenStats.compact(value))
                .dsText(lead ? .stat24 : .price16)
                .foregroundStyle(DS.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s4)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget,
                                         style: .continuous))
    }
}

/// A watched token with a `TokenPulse` entry but no fetchable route
/// (`ThingChart.watchedPulse`, 2026-08-11) — currently the demo's own case
/// only (see that case's doc). Draws the SAME `TokenChartView` every real
/// token chart uses, but its `fetch` closure reads the already-cached pulse
/// locally via `TokenChart.from(closes:)` and never calls `TokenChart.fetch`
/// — no network, ever, regardless of which range chip is tapped, since a
/// synthetic pulse carries exactly one window's worth of closes. No stat
/// strip (liquidity/volume/FDV are real Dexscreener pair facts this thing
/// was never given) and no Watch row (this IS the watchlist's own thing,
/// `TokenChartContent`'s own `offersWatch` reasoning).
private struct TokenPulseChartContent: View {
    let thing: Thing
    let ref: String

    private var since: (price: Double, date: Date)? {
        guard let p = thing.watchPriceUsd, p > 0 else { return nil }
        return (p, thing.capturedAt)
    }

    var body: some View {
        if thing.isLive, let pulse = TokenPulse.shared.pulse(for: thing) {
            // EmptyView, not a link fallback: `TokenChart.from(closes:)` only
            // returns nil under 2 points, which a seeded 24-point pulse never
            // is — the `.dead` phase this would cover is unreachable here.
            TokenChartView<TokenRange, EmptyView>(
                memoryKey: "pulse.\(ref)",
                fetch: { _ in TokenChart.from(closes: pulse.closes) },
                since: since, hero: true) { EmptyView() }
                .padding(.horizontal, DS.Space.s4)
                .padding(.bottom, DS.Space.s3)
        }
    }
}

/// A watched stock's price, drawn natively — the equity dose of the same
/// anatomy (StockChart/Yahoo behind the shared TokenChartView). No
/// market-structure strip: those stats ride the Dexscreener pair payload,
/// a token fact — Yahoo's chart JSON carries none we'd stand behind.
/// Yahoo unreachable → the plain Stocktwits link, never a broken chart.
private struct StockChartContent: View {
    let thing: Thing
    let ticker: String

    /// The watch-time anchor — only when the record really carries one.
    private var since: (price: Double, date: Date)? {
        guard thing.source == "Stocktwits", let p = thing.watchPriceUsd, p > 0
        else { return nil }
        return (p, thing.capturedAt)
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
        TokenChartView(memoryKey: "stock.range.\(ticker)",
                       fetch: { (range: StockRange) in
                           await StockChart.fetch(ticker: ticker, range: range)
                       },
                       since: since,
                       // One grammar with tokens (prd §369 amendment). The two
                       // wore different type ramps for the same fact purely by
                       // accident — `hero:` was simply never passed here — so a
                       // watched stock got a 22pt left-aligned price where a
                       // token got a 40pt centred one. Same object now.
                       hero: true,
                       object: PriceObjectSource.identity(
                           title: thing.title,
                           authorHandle: thing.authorHandle)) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A watched PostHog metric: its 30-day curve with the project's annotations
/// marked on it, the milestone it's chasing, and the ring's own progress.
///
/// The milestone line is the one place this bridge lets a COUNT be the
/// headline, and it earns it by being a moment rather than a tally — so it
/// rolls (`CountUpText`) instead of just appearing, the same acknowledgement
/// the app gives every other number that took work to reach. Tapping a mark
/// names the annotation it belongs to; nothing is drawn that isn't read.
private struct PostHogMetricContent: View {
    let thing: Thing
    let event: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var reading = PostHogState.Metric()
    /// The annotations already in the corpus — the refresh landed them as
    /// Things minutes ago, so re-fetching them over the network on every sheet
    /// open bought a round trip and a chance to disagree with the feed.
    @State private var annotations: [(date: Date, title: String)] = []
    @State private var tappedMark: String?

    /// The series as a chart. Counts are not prices, but the shape is the
    /// same fact — one value per sample — so it draws through the plot every
    /// other curve in the app uses rather than growing a second chart stack.
    /// A counts series legitimately starts at zero, which `TokenChart.from`
    /// rejects (a price that starts at 0 has no meaningful change), so the
    /// zero-start case falls back to a flat change rather than no chart.
    private var chart: TokenChart? {
        let closes = reading.series.map(Double.init)
        guard closes.count >= 2, let last = closes.last else { return nil }
        return TokenChart.from(closes: closes)
            ?? TokenChart(closes: closes, price: last, change: 0)
    }

    /// Annotations that fall inside the drawn window, placed at their own day.
    /// Ids are STABLE across body evaluations — a fresh `UUID()` each time made
    /// `TokenChartPlot`'s `ForEach` tear down and replay every mark's landing
    /// animation on each re-render (review, 2026-07-27). Capped like the
    /// wallet's own mark set, so a busy timeline can't stipple the curve.
    private var marks: [TokenChartMark] {
        let days = reading.series.count
        guard days >= 2 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return annotations.prefix(10).compactMap { note in
            let back = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: note.date), to: today).day ?? 0
            guard back >= 0, back < days else { return nil }
            return TokenChartMark(id: markID(note.title, back), x: Double(days - 1 - back),
                                  label: note.title)
        }
    }

    /// A stable id per (note, day) pair — derived, not minted.
    private func markID(_ title: String, _ back: Int) -> UUID {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(back)
        let value = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(uuid: (UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
                           UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24),
                           UInt8(truncatingIfNeeded: value >> 32), UInt8(truncatingIfNeeded: value >> 40),
                           UInt8(truncatingIfNeeded: value >> 48), UInt8(truncatingIfNeeded: value >> 56),
                           0, 0, 0, 0, 0, 0, 0, 0))
    }

    private var accent: Color {
        TokenChartStyle.accent(change: chart?.change ?? 0, scheme: scheme)
    }

    // Corollary 5, which this view was missing (2026-08-14) — the only
    // `Thing`-holding leaf in this file without it, while every sibling chart
    // view (`TokenChartContent`, `TokenPulseChartContent`, `StockChartContent`)
    // has carried one since build 188. SwiftUI re-evaluates a leaf's body on
    // the MODEL'S OWN observation, through this view's own attribute node, so
    // no guard in the parent that built it can protect a row already in the
    // tree.
    //
    // It slipped the liveness audit's check 5 rather than being exempted:
    // that check clears a struct when `isLive`/`.live` appears anywhere
    // inside it, and this struct carries a `.filter(\.isLive)` on its
    // ANNOTATIONS fetch — an unrelated collection. A guard on one array
    // reading as a guard on the stored model is the same shape as the
    // per-identifier tightening the held-Thing check already needed.
    var body: some View {
        if thing.isLive { liveBody }
    }

    @ViewBuilder private var liveBody: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            header
            if let chart {
                TokenChartPlot(chart: chart, accent: accent, marks: marks,
                               onTapMark: { tappedMark = $0.label })
            }
            if let tappedMark {
                Text(tappedMark)
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
            }
            milestoneLine
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The window's own total, not the all-time one — the number the
            // curve above it actually draws.
            Text(PostHogIngest.formatted(reading.series.suffix(7).reduce(0, +)))
                .dsText(.stat24).monospacedDigit()
                .foregroundStyle(DS.textPrimary)
            Text("\(event) · last 7 days")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
        }
    }

    /// "728 of 1,000" — where this metric stands on the ladder. Absent until a
    /// total is read: an unread total is a fact we don't have, and a ring at
    /// zero would claim one.
    @ViewBuilder private var milestoneLine: some View {
        if reading.total > 0 {
            let next = PostHogMilestone.next(after: reading.total)
            HStack(spacing: DS.Space.s2) {
                MetricDisc(series: reading.series,
                           progress: PostHogMilestone.progress(reading.total),
                           change: chart?.change, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    CountUpText(text: PostHogIngest.formatted(reading.total))
                        .dsText(.body17).monospacedDigit()
                        .foregroundStyle(DS.textPrimary)
                    Text("all time · next \(PostHogIngest.formatted(next))")
                        .dsText(.label12).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Everything here is already on device — the reading from the bridge's
    /// own state, the annotations from the corpus the refresh landed them in.
    /// No network, so the sheet paints immediately and can never show a
    /// different timeline than the feed behind it.
    private func load() {
        reading = PostHogState.get(event)
        let prefix = "posthog:annotation:"
        var descriptor = FetchDescriptor<Thing>(
            predicate: #Predicate {
                $0.source == "PostHog" && ($0.sourceRef?.starts(with: prefix) ?? false)
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 25
        annotations = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.isLive)
            .map { (date: $0.capturedAt, title: $0.title) }
    }
}

/// A starred (or watched) repo: its link preview, then the language dot and —
/// for stars — "since you starred", the stargazer count the day you saved it
/// against where it is now. The anchor is stored at ingest; the current count
/// is fetched live (and simply omitted if the fetch can't reach it).
/// Not private (2026-07-21): `compact(_:)` and `languageColor(_:)` are also
/// what the GitHub feed row's trailing star/language enrichment reuses
/// (ShapedRows.swift) — one star-formatting and one Linguist-color table, not
/// two copies drifting apart.
struct GitHubStarContent: View {
    let thing: Thing
    @State private var currentStars: Int?

    /// The star-time anchor — only when the record really carries one.
    private var since: (stars: Int, date: Date)? {
        guard let c = thing.starCount, c > 0 else { return nil }
        return (c, thing.capturedAt)
    }

    /// "owner/repo" parsed from the repo's html_url.
    private var repoPath: String? {
        GitHubFeedFetch.repoPath(fromWebURL: thing.content)
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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            }
            metaRow
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await loadCurrent() }
    }

    @ViewBuilder private var metaRow: some View {
        let language = thing.repoLanguage
        if (language?.isEmpty == false) || since != nil {
            HStack(spacing: DS.Space.s3) {
                if let language, !language.isEmpty {
                    HStack(spacing: 5) {
                        Circle().fill(Self.languageColor(language))
                            .frame(width: 9, height: 9)
                        Text(language)
                            .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                sinceLine
            }
        }
    }

    @ViewBuilder private var sinceLine: some View {
        if let since {
            HStack(spacing: 5) {
                Image(systemName: "star.fill")
                    .accessibilityHidden(true)
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                if let now = currentStars, now != since.stars {
                    let delta = now - since.stars
                    Text("\(Self.compact(since.stars)) → \(Self.compact(now))")
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary).monospacedDigit()
                    Text(delta > 0 ? "+\(Self.compact(delta)) since you starred"
                                   : "since you starred")
                        .dsText(.label12)
                        .foregroundStyle(delta > 0 ? DS.confirm : DS.textTertiary)
                } else {
                    Text("\(Self.compact(since.stars)) when you starred")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).monospacedDigit()
                }
            }
        }
    }

    private func loadCurrent() async {
        guard since != nil, let path = repoPath,
              let token = TokenVault.get(TokenBridge.github.tokenKey) else { return }
        currentStars = await GitHubFeedFetch.repoStars(path: path, token: token)
    }

    /// "8.4k", "1.2M" — GitHub's own compact star form.
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    /// GitHub Linguist's canonical language colors; a neutral dot for the rest.
    static func languageColor(_ language: String) -> Color {
        colors[language] ?? DS.textTertiary
    }
    private static let colors: [String: Color] = [
        "Swift": Color(hex: "#F05138"),       "JavaScript": Color(hex: "#F1E05A"),
        "TypeScript": Color(hex: "#3178C6"),  "Python": Color(hex: "#3572A5"),
        "Rust": Color(hex: "#DEA584"),        "Go": Color(hex: "#00ADD8"),
        "Ruby": Color(hex: "#701516"),        "Java": Color(hex: "#B07219"),
        "Kotlin": Color(hex: "#A97BFF"),      "C": Color(hex: "#555555"),
        "C++": Color(hex: "#F34B7D"),         "C#": Color(hex: "#178600"),
        "Objective-C": Color(hex: "#438EFF"), "Shell": Color(hex: "#89E051"),
        "HTML": Color(hex: "#E34C26"),        "CSS": Color(hex: "#563D7C"),
        "PHP": Color(hex: "#4F5D95"),         "Dart": Color(hex: "#00B4AB"),
        "Scala": Color(hex: "#C22D40"),       "Elixir": Color(hex: "#6E4A7E"),
        "Haskell": Color(hex: "#5E5086"),     "Lua": Color(hex: "#000080"),
        "Vue": Color(hex: "#41B883"),         "Zig": Color(hex: "#EC915C"),
        "Solidity": Color(hex: "#AA6746"),    "Nix": Color(hex: "#7E7EFF"),
    ]
}

/// A release: its link preview, then its own notes — read fresh when the
/// sheet opens (2026-07-16), the `enrichedText`-is-retrieval-only rule means
/// this can't be stored, so it follows the star-count/social-engagement
/// precedent instead: live, and simply absent if the fetch can't reach it.
private struct GitHubReleaseContent: View {
    let thing: Thing
    @State private var notes: String?

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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if let url = URL(string: thing.content) {
                LinkPreviewCard(url: url, storedImageURL: thing.previewImageURL)
            }
            if let notes {
                Text(ProseLinks.rendered(notes))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .task { await load() }
    }

    private func load() async {
        guard let token = TokenVault.get(TokenBridge.github.tokenKey) else { return }
        notes = await GitHubFeedFetch.releaseBody(thing: thing, token: token)
    }
}

/// A Kalshi market's odds, drawn natively — the KalshiMarketView read: a
/// live probability, a delta pill, honest about active vs settled. A market
/// Kalshi no longer resolves (rare — expired far past close) falls back to
/// the plain link, never a blank read.
private struct KalshiMarketContent: View {
    let series: String
    let event: String

    var body: some View {
        KalshiMarketView(series: series, event: event) {
            if let url = URL(string: "https://kalshi.com/markets/\(series)/\(event)") {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}

/// A Polymarket market's odds and real price curve, drawn natively — see
/// `PolymarketMarketView`. A market Polymarket's Gamma API no longer
/// resolves (rare) falls back to the plain link, never a blank read.
private struct PolymarketMarketContent: View {
    let conditionId: String
    let url: String

    var body: some View {
        PolymarketMarketView(conditionId: conditionId) {
            if let url = URL(string: url) {
                LinkPreviewCard(url: url)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }
}
