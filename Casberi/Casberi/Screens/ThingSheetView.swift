import SwiftUI
import SwiftData
import Translation

/// The thing sheet (M4, redesigned 2026-07-07 — "Ink with Gallery grafted
/// in", user's pick): ink-black ground, no cards. The source's hue washes
/// down from the top (2026-07-10 ruling — wash + icon, the dot died), an
/// eyebrow (source icon · kind · age), the title large, the thing's media,
/// then a quiet spec table (WHEN/SITE/BY/FROM/TAGS — labels change per
/// kind). Verbs are text rows (derived, cap three; writes confirm), plus
/// Pin and Share. The tag editor keeps all its power behind a tap on the
/// TAGS row. Related streams last. Spacing does the separating — no
/// hairlines.
struct ThingSheetView: View {
    @Bindable var thing: Thing
    /// True when the Tag swipe opened the sheet — it lands scrolled to the
    /// Tags field (one sheet for everything; the swipe is just a shortcut).
    var focusTags: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var tagDraft = ""
    @State private var confirmingVerb: Verb?
    @State private var verbResult: String?
    /// A bridge's no must READ as a no — green success styling on a failure
    /// would claim a write that didn't happen (honesty rule).
    @State private var verbResultIsError = false
    @State private var relatedStream = GenStream()
    /// "Related" for tag overlap; "In your things" when a watched token's
    /// shelf holds the corpus things that mention it (2026-07-14).
    @State private var relatedTitle = "Related"
    @State private var renameTarget: String?
    @State private var renameDraft = ""
    @State private var deleteTarget: String?
    /// Naming a wallet transaction's counterparty (2026-07-15) — the address
    /// being named, and the draft. The label enriches every FUTURE transfer
    /// with that counterparty (CounterpartyLabels).
    @State private var counterpartyTarget: String?
    @State private var counterpartyDraft = ""
    /// The TAGS row opens the full editor (chips, rename, delete) in place.
    @State private var editingTags = false
    /// The hue wash pours in on open (delight 2026-07-13) — once per sheet.
    @State private var washPoured = false
    /// A post/cast's thread (2026-07-14) — fetched live from the source's
    /// public API when the sheet opens a social thing (Bluesky or Farcaster);
    /// the section renders only when replies exist (no dead section, no
    /// spinner theater).
    @State private var replies: [SocialReply] = []
    /// Walking the thread in-app (2026-07-16) — the parent this post answers,
    /// opened as a post sheet rather than kicked out to the browser.
    @State private var walkingTo: SocialCard?
    /// The person behind a tapped face — the profile card.
    @State private var profileTarget: SocialProfile?
    /// An approval thing's prepare card (prd §112) — the grant's LIVE state,
    /// the fee to revoke, the doors out. Fetched on open like replies; the
    /// section renders only when the check answered.
    @State private var approvalCheck: WalletPrepare.Check?
    /// Translate verb (2026-07-17): the system Translation sheet, shown over
    /// the thing's own words — no custom UI, Apple's picker does the rest.
    @State private var showTranslate = false
    @State private var translateText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seeded by the record's shape (2026-07-13 polish): a TALL thing (media
    /// or a long body) still opens FULL-height so its verbs never start
    /// below the fold — the original `.large` ruling, kept for the case that
    /// earned it. A short record opens `.medium` instead of one card of
    /// content over a screen of black. Both detents stay a drag away.
    @State private var detent: PresentationDetent

    init(thing: Thing, focusTags: Bool = false) {
        self.thing = thing
        self.focusTags = focusTags
        let hasMedia = thing.kind == .screenshot
            || !(thing.previewImageURL ?? "").isEmpty
            || TokenChart.route(from: thing.content) != nil
            || StockChart.route(from: thing.content) != nil
            // A quoted post is a card the height of a small paragraph — the
            // same "tall thing" the detent rule was written for, so it opens
            // full-height rather than starting its verbs below the fold.
            || thing.quote != nil
        // A social post's `content` is its permalink — always short — so the
        // length test has to read the POST, else a 900-character cast opened
        // half-height with its own words below the fold (2026-07-16).
        let bodyLength = max(thing.content.count, (thing.postText ?? "").count)
        _detent = State(initialValue:
            hasMedia || bodyLength > 280 ? .large : .medium)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Sequenced entrance (delight 2026-07-14): the sheet composes
                // itself over the pouring wash — eyebrow, then title, then
                // media, then spec — each a beat behind the last, one-shot.
                eyebrow
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn()
                if let parent = thing.parent {
                    replyingToRow(parent)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.04)
                }
                // The stage (B1, 2026-07-16): a wallet transfer or a screenshot
                // leads with a HERO that depicts the thing — parties + signed
                // amount on the wash's seam, or the image in a floating frame —
                // and its verbs become the dial. Everything else keeps the
                // title-led layout.
                let stage = self.stage
                let framedShot = stage == nil && thing.kind == .screenshot
                if let stage {
                    TransferStageView(thing: thing, stage: stage,
                                      onNameCounterparty: nameCounterpartyAction)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.06)
                    VerbDial(thing: thing, verbs: walletVerbs,
                             onVerb: runVerb, onName: nameCounterpartyAction)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.12)
                    dialResult
                } else if framedShot {
                    // The framed exception (B1c): facts stand bare on the wash;
                    // pixels recess into a frame that floats on it — the image
                    // sits IN the source's color without the color ever touching
                    // its pixels. The title drops below at reading size: for a
                    // screenshot the picture is the identity, the words the
                    // caption.
                    ThingContentView(thing: thing)
                        .shadow(color: DS.cardShadow, radius: 18, y: 10)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                    Text(thing.title)
                        .dsText(.heading22).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s2)
                        .settleIn(delay: 0.1)
                    VerbDial(thing: thing, verbs: VerbDerivation.verbs(for: thing),
                             onVerb: runVerb, onName: nil)
                        .padding(.top, DS.Space.s6)
                        .settleIn(delay: 0.14)
                    dialResult
                } else {
                    titleBlock
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.06)
                }
                // Events speak through WHEN below; and when the content is
                // just the title again (a short note with no body beyond its
                // own headline), showing it twice reads as a stutter.
                // A social post always shows content — its pictures, what it
                // quotes, how it landed — and its `content` is a permalink, so
                // the title-stutter test never applied to it anyway.
                let contentShown = stage == nil && !framedShot
                    && (isSocialPost || (thing.kind != .event
                    && thing.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        != thing.title.trimmingCharacters(in: .whitespacesAndNewlines)))
                if contentShown {
                    ThingContentView(thing: thing)
                        .padding(.top, DS.Space.s3)
                        .settleIn(delay: 0.12)
                }
                // The stage already shows the counterparty (with its pencil),
                // so its spec table drops the Who row instead of repeating it.
                specTable(contentShown: contentShown, showsWho: stage == nil)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s6)
                    .settleIn(delay: 0.18)
                if let check = approvalCheck {
                    ApprovalPrepareCard(thing: thing, check: check)
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s3)
                }
                if editingTags {
                    tagsField
                        .padding(.top, DS.Space.s3)
                        .id("tags")
                }
                if stage == nil && !framedShot {
                    actionRows
                        .padding(.top, DS.Space.s6)
                }
                if !replies.isEmpty {
                    // One replies renderer (2026-07-16) — the thing sheet and
                    // the in-app walker show a reply identically, however deep
                    // you are. Here a tap OPENS the walker (this sheet has no
                    // navigation stack of its own); inside the walker the same
                    // tap pushes. The section doesn't know which — it just
                    // reports the card.
                    SocialRepliesSection(replies: replies, source: thing.source,
                                         open: { walkingTo = $0 })
                        .padding(.horizontal, DS.Space.s4)
                        .padding(.top, DS.Space.s4)
                }
                relatedShelf
                    .padding(.top, DS.Space.s4)
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            // The source's hue washes down from the top and fades into the
            // ink (ruling 2026-07-10, user: "it's gorgeous"). One fixed
            // recipe — 45% into clear over 260pt, no per-hue tuning — and
            // it sits UNDER the content as atmosphere: no ink ever depends
            // on it for contrast, which is why this wash lives while the
            // treemap fills and the banner died. Hueless sources (your own
            // notes, unknown apps) stay pure ink: the gray fallback is a
            // fill, not an identity.
            if let hue = DS.washHue(for: thing.source) {
                // Bold, not a film (user ruling 2026-07-13): the crown IS
                // the source's color, flowing into the sheet's ink.
                // A stage sheet uses the SEAM recipe (B1a, 2026-07-16): the
                // solid crown ends sooner and the fade completes early, so the
                // signed amount lands on near-ink — identity (faces) lives on
                // the solid zone, data lives at or below the seam.
                let seam = stage != nil
                LinearGradient(stops: seam ? [
                    .init(color: hue, location: 0),
                    .init(color: hue, location: 0.26),
                    .init(color: hue.opacity(0), location: 0.78),
                ] : [
                    .init(color: hue, location: 0),
                    .init(color: hue, location: 0.3),
                    .init(color: hue.opacity(0), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                    // The pour (delight 2026-07-13): the bleed slides down
                    // into place as the sheet opens — a bleed that literally
                    // bleeds in. Once per open; instant under Reduce Motion.
                    .opacity(washPoured ? 1 : 0)
                    .offset(y: washPoured ? 0 : -140)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // TOP only: the wash bleeds under the notch, but ignoring
                    // the BOTTOM edge too let the scroll content run under the
                    // home indicator, clipping the last actions on hue'd sheets.
                    .ignoresSafeArea(edges: .top)
                    .onAppear {
                        if reduceMotion { washPoured = true } else {
                            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                                washPoured = true
                            }
                        }
                    }
            }
        }
        // Ink: the sheet is black in both modes, like a photo viewer — its
        // controls render dark regardless of the app's theme.
        .presentationBackground(Color.black)
        .colorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.Radius.sheet)
        .onAppear {
            streamRelated()
            Task { replies = await SocialThread.replies(for: thing) }
            // The gate is a string check — non-approval things spend nothing.
            if WalletPrepare.applies(to: thing) {
                Task { approvalCheck = await WalletPrepare.check(for: thing) }
            }
            if focusTags {
                // Land in the tag editor — the swipe's whole point.
                editingTags = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(DS.Motion.standard) {
                        proxy.scrollTo("tags", anchor: .top)
                    }
                }
            }
        }
        }
        // Ask-before-acting: writes confirm, reads pass.
        .confirmationDialog(
            confirmingVerb.map { "\($0.label): \(thing.title)?" } ?? "",
            isPresented: Binding(get: { confirmingVerb != nil },
                                 set: { if !$0 { confirmingVerb = nil } }),
            titleVisibility: .visible
        ) {
            if let verb = confirmingVerb {
                Button(verb.label) { Task { await perform(verb) } }
                Button("Cancel", role: .cancel) { confirmingVerb = nil }
            }
        }
        // Name this counterparty — the name rides every future transfer with it.
        .alert("Name this address",
               isPresented: Binding(get: { counterpartyTarget != nil },
                                    set: { if !$0 { counterpartyTarget = nil } })) {
            TextField("Name (e.g. Mom)", text: $counterpartyDraft)
            Button("Save") { nameCounterparty() }
            Button("Cancel", role: .cancel) { counterpartyTarget = nil }
        } message: {
            Text("Your name for this address rides every future transfer with it. A blank name clears it.")
        }
        // Walking the thread in-app (2026-07-16) — the parent this post
        // answers, or a reply under it. A read: no consent gate, the standing
        // rule for the thread section it grew out of.
        .sheet(item: $walkingTo) { card in
            SocialPostSheet(post: card, source: thing.source)
        }
        // The person behind a tapped face — theirs to watch from here.
        .sheet(item: $profileTarget) { p in
            SocialProfileCard(profile: p)
        }
        // Translate: the system sheet, over the thing's own words.
        .translationPresentation(isPresented: $showTranslate, text: translateText)
    }

    /// Stores (or clears) the person's label for the counterparty address, then
    /// rewrites every already-landed transfer that carries it — so naming an
    /// address updates your whole history with it, not just what comes next.
    /// (Only transfers that stored the counterparty hex can be rewritten — ones
    /// landed before that field existed are left as they are.)
    private func nameCounterparty() {
        guard let address = counterpartyTarget else { return }
        counterpartyTarget = nil
        CounterpartyLabels.shared.setLabel(counterpartyDraft, for: address)
        // The display name after the change: the user's label, else whatever
        // else resolves it (a known contract, a watched handle), else nil —
        // clearing a label reverts the historical titles to that.
        retitleWalletThings(counterparty: address, to: WalletIngest.knownLabel(for: address))
        DSHaptic.success()
    }

    /// Rewrites the counterparty clause of every landed Wallet transfer whose
    /// stored counterparty matches — to `name`, or stripped when `name` is nil.
    /// The clause lives twice, and both writes happen here: the title's words,
    /// and `transferCounterparty` (the structured copy TransferStage reads) —
    /// updating one without the other is how a stage would drift from its row.
    private func retitleWalletThings(counterparty: String, to name: String?) {
        let addr = counterparty.lowercased()
        let all = (try? modelContext.fetch(
            FetchDescriptor<Thing>(predicate: #Predicate { $0.source == "Wallet" }))) ?? []
        var changed = false
        for t in all where t.counterpartyAddress?.lowercased() == addr {
            if let rebuilt = Self.retitled(t.title, to: name), rebuilt != t.title {
                t.title = rebuilt
                changed = true
            }
            if t.transferCounterparty != name {
                t.transferCounterparty = name
                changed = true
            }
        }
        if changed {
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()   // Home/Feed compose a doc, not a live @Query
        }
    }

    /// Swaps (or strips) a transfer title's trailing counterparty clause. The
    /// only " from "/" to "/" on " in a wallet title is that clause — amounts
    /// are numbers and assets are space-less symbols — so the last one is safe
    /// to replace. A nameless title gains a clause from its verb; a "Moved …"
    /// self-transfer (named from watched-wallet labels, not this) is left alone.
    static func retitled(_ title: String, to name: String?) -> String? {
        for delim in [" from ", " to ", " on "] {
            if let r = title.range(of: delim, options: .backwards) {
                if let name { return String(title[..<r.upperBound]) + name }
                return String(title[..<r.lowerBound])   // strip the clause
            }
        }
        guard let name else { return nil }
        if title.hasPrefix("Received") { return title + " from " + name }
        if title.hasPrefix("Sent")     { return title + " to " + name }
        if title.hasPrefix("Swapped")  { return title + " on " + name }
        return nil
    }

    // MARK: - Title (a post's words ARE the title, 2026-07-16)

    /// Everything else leads with a headline. A post leads with the POST: its
    /// full text, in the title's slot, because a cast IS its words — and the
    /// 80-character title is a row's clamp, not the thing itself. Rendering the
    /// clamp here and the full text below would stutter; rendering only the
    /// clamp is what lost the words in the first place.
    ///
    /// The size follows the length, the way every social client's does: a
    /// one-liner gets the full display size and the drama that comes with it,
    /// a paragraph steps down to a size you can actually read a paragraph in.
    /// Both are the type ramp — hierarchy by size, no other trick (design law).
    @ViewBuilder private var titleBlock: some View {
        if isSocialPost {
            let words = postWords
            Text(words)
                .dsText(words.count > 100 ? .heading22 : .heading34)
                .foregroundStyle(DS.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(thing.title)
                .dsText(.heading34).foregroundStyle(DS.textPrimary)
        }
    }

    /// The post's own words — the full text when the record carries it, else
    /// the title (posts landed before `postText` existed, until a refresh heals
    /// them). Never a permalink.
    private var postWords: String {
        let full = (thing.postText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? thing.title : full
    }

    /// The post this one answers — "Replying to @alice", above the words, where
    /// every client puts it. A tap walks into the parent in-app.
    private func replyingToRow(_ parent: SocialCard) -> some View {
        Button {
            walkingTo = parent
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "arrowshape.turn.up.left")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Text("Replying to @\(SocialThread.shortHandle(parent.handle))")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eyebrow (source icon · kind · age)

    private var eyebrow: some View {
        HStack(spacing: DS.Space.s2) {
            // A social post leads with the PERSON who said it — their face and
            // handle, not the network's mark (the hue wash already names the
            // network). The feed rows lead with faces; the sheet should too
            // (2026-07-14). Everything else keeps the source mark + kind tag.
            if isSocialPost, let avatar = thing.authorAvatarURL, !avatar.isEmpty {
                // The face is a door to the person (2026-07-16) — tap it and
                // you can watch them, wherever you met them.
                Button {
                    profileTarget = SocialProfile(
                        source: thing.source, handle: thing.authorHandle ?? "",
                        displayName: nil, bio: nil, avatarURL: avatar)
                } label: {
                    RemoteThumb(urlString: avatar, size: 18, fallback: thing.source, circular: true)
                        .coinFlip(trigger: thing.id)
                }
                .buttonStyle(.plain)
                // WHY this post is here rides the sentence when there's a
                // reason worth stating ("@dwr · in /design · 2h ago") — a
                // liked cast, a channel cast, and your own post used to read
                // identically (2026-07-16).
                Text(eyebrowLine)
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            } else {
                // The source's own mark names the wash above it — the 6px dot
                // died with the hue ruling (2026-07-10). BridgeIcon falls back
                // to the glyph-on-hue circle for sources without a bundled
                // asset, so the seat is never empty.
                BridgeIcon(name: thing.source, size: 18, circular: true)
                    // The mark coin-flips as the sheet opens (delight, 2026-07-12).
                    .coinFlip(trigger: thing.id)
                Text("\(thing.kind.typeTag) · \(shortTime(thing.capturedAt)) ago")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    /// A social post with a known author — the eyebrow and thread treatment
    /// key off this, never a hardcoded source name.
    private var isSocialPost: Bool {
        SocialThread.isSocial(thing.source)
            && !(thing.authorHandle ?? "").isEmpty
    }

    /// The author's handle without Bluesky's ".bsky.social" tail — the name
    /// the person knows.
    private var authorShortHandle: String {
        SocialThread.shortHandle(thing.authorHandle ?? "")
    }

    /// "@dwr · in /design · 2h ago" — who, why (when there's a why), when.
    private var eyebrowLine: String {
        let age = "\(shortTime(thing.capturedAt)) ago"
        guard let why = SocialThread.contextPhrase(for: thing) else {
            return "@\(authorShortHandle) · \(age)"
        }
        return "@\(authorShortHandle) · \(why) · \(age)"
    }

    // MARK: - Spec table (Gallery's graft — labels change per kind)

    private func specTable(contentShown: Bool, showsWho: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if thing.kind == .event, !thing.content.isEmpty {
                specRow("When", thing.content)
            }
            // Tokens' content URL is plumbing (the chart's technical
            // dependency, not a site the person browsed to) — the native
            // TokenChartView above already carries the read; a "Site" row
            // would just leak that dependency's brand under the "Tokens"
            // eyebrow (report 2026-07-13). And when the link preview card is
            // on screen its footer already names the host — repeating it here
            // read as a stutter (2026-07-13 polish). Keyed to the content
            // view's OWN branch fact (a token/Kalshi link renders a chart,
            // no host footer — the Site row must stay for those).
            if thing.kind == .link, thing.source != "Tokens",
               !(contentShown && ThingContentView.showsLinkPreview(thing)),
               let url = Capture.detectURL(in: thing.content.isEmpty ? thing.title : thing.content),
               let host = url.host() {
                specRow("Site", host.replacingOccurrences(of: "www.", with: ""))
            }
            if let agent = thing.provenance.agent {
                specRow("By", "\(agent)\(thing.provenance.machine.map { " on \($0)" } ?? "")")
            }
            specRow("From", PlaceWords.line(for: thing))
            // A wallet transfer's counterparty — the other side of the trade,
            // nameable ("this is Mom"). Only when the hex was captured (native
            // sends have none) (2026-07-15).
            if showsWho, thing.source == "Wallet",
               let cp = thing.counterpartyAddress, !cp.isEmpty {
                counterpartyRow(cp)
            }
            tagsRow
        }
        // One quiet card (2026-07-13 polish): the bare rows floated in the
        // sheet's field; the same faint fill the link preview wears gathers
        // them into one readable spec block.
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.fillFaint,
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private func specRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(LocalizedStringKey(label))
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)
                .frame(width: 80, alignment: .leading)
            // Callout, not body — the values were the loudest type on the
            // sheet ("saved by you" outweighed the title's own facts).
            Text(LocalizedStringKey(value))
                .dsText(.callout15).foregroundStyle(DS.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    /// The counterparty's name (yours if set, else a known contract / watched
    /// handle, else the short hex) with a pencil — tap to name it. What you name
    /// it here rides every future transfer with this address.
    private func counterpartyRow(_ address: String) -> some View {
        Button {
            nameCounterpartyAction?()   // the one entry into the naming flow
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Who")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                    .frame(width: 80, alignment: .leading)
                Text(WalletIngest.knownLabel(for: address) ?? WalletStore.shortAddress(address))
                    .dsText(.callout15).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.leading, DS.Space.s2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tags as a text line — your own tags wear their hue; the "+" opens the
    /// full editor (chips, rename everywhere, delete everywhere) in place.
    private var tagsRow: some View {
        Button {
            withAnimation(DS.Motion.standard) { editingTags.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Tags")
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .frame(width: 80, alignment: .leading)
                tagsLine
                Text(editingTags ? "  −" : "  +")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tagsLine: Text {
        var line = Text("")
        for (i, tag) in thing.tags.enumerated() {
            if i > 0 { line = line + Text(" · ").foregroundStyle(DS.textTertiary) }
            let isType = ThingKind.from(typeTag: tag) != nil
            line = line + Text(tag)
                .foregroundStyle(isType ? DS.textSecondary : ProjectHue.color(for: tag))
        }
        return line.font(.system(size: 15))
    }

    // MARK: - The dial's wiring (stage sheets — B1, 2026-07-16)

    /// The transfer's parsed hero, when this thing earns one — the ONE
    /// decision point both the layout and the wash's seam recipe read.
    private var stage: TransferStage? { TransferStage(thing) }

    /// A wallet transfer's dial verbs: Open (the explorer link, when the
    /// record carries one) and Copy. Name and Share ride the dial's own slots.
    private var walletVerbs: [Verb] {
        var out: [Verb] = []
        if let url = Capture.detectURL(in: thing.content) {
            out.append(Verb(label: "Open", icon: "arrow.up.right", action: .openURL(url)))
        }
        out.append(Verb(label: "Copy link", icon: "doc.on.doc", action: .copyText))
        return out
    }

    /// The one verb gate, both layouts: reads pass, writes confirm.
    private func runVerb(_ verb: Verb) {
        if verb.isWrite {
            confirmingVerb = verb
        } else {
            Task { await perform(verb) }
        }
    }

    /// The naming flow, when there's an address to name — nil keeps the
    /// stage's face plain and the Name disc absent (no dead controls).
    private var nameCounterpartyAction: (() -> Void)? {
        guard let cp = thing.counterpartyAddress, !cp.isEmpty else { return nil }
        return {
            counterpartyDraft = CounterpartyLabels.shared.label(for: cp) ?? ""
            counterpartyTarget = cp
        }
    }

    /// The verb outcome, honesty-styled — ONE text both layouts place, so a
    /// bridge's no reads the same wherever the verb lived.
    @ViewBuilder private var verbOutcome: some View {
        if let verbResult {
            Text(verbResult)
                .dsText(.subhead13)
                .foregroundStyle(verbResultIsError ? DS.attention : DS.confirm)
        }
    }

    /// The outcome under the dial — centered, where the discs are.
    private var dialResult: some View {
        verbOutcome
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s2)
    }

    // MARK: - Actions (quiet text rows — verbs, then Pin, then Share)

    private var actionRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(VerbDerivation.verbs(for: thing)) { verb in
                Button {
                    runVerb(verb)   // reads pass; writes confirm
                } label: {
                    actionRow(icon: verb.icon, label: verb.label)
                }
                .buttonStyle(.plain)
            }
            shareRow
            verbOutcome
                .padding(.horizontal, DS.Space.s4)
                .padding(.top, DS.Space.s2)
        }
    }

    private func actionRow(icon: String, label: String) -> some View {
        HStack(spacing: DS.Space.s4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 26, alignment: .center)
            Text(LocalizedStringKey(label))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s4)
        .contentShape(Rectangle())
    }

    /// The universal out-door: the system share sheet reaches every app with
    /// a share target — the only sanctioned route INTO Apple Notes, for one.
    /// A screenshot shares its actual photo, not just its title (ThingShareLink).
    private var shareRow: some View {
        ThingShareLink(thing: thing) {
            actionRow(icon: "square.and.arrow.up", label: "Share")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tags (one field; active lit, candidates dim)

    private var candidates: [String] {
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        let projectTags = Set(all.flatMap(\.tags)).subtracting(typeTags)
        return projectTags.subtracting(thing.tags).sorted()
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Tags")
                .dsText(.label12)
                .foregroundStyle(DS.textTertiary)

            FlowLayout(spacing: DS.Space.s2) {
                ForEach(thing.tags, id: \.self) { tag in
                    activeTagChip(tag)
                }
                ForEach(candidates, id: \.self) { tag in
                    tagChip(tag, active: false) { add(tag: tag) }
                }
            }

            HStack(spacing: DS.Space.s2) {
                TextField("Add a tag", text: $tagDraft)
                    .dsText(.callout15)
                    .foregroundStyle(DS.textPrimary)
                    .tint(DS.tint)
                    .onSubmit { add(tag: tagDraft); tagDraft = "" }
                Button("Add") { add(tag: tagDraft); tagDraft = "" }
                    .dsText(.label12)
                    .foregroundStyle(tagDraft.isEmpty ? DS.textTertiary : .white)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 28)
                    .background(tagDraft.isEmpty ? DS.gray200 : DS.tint,
                                in: Capsule(style: .continuous))
                    .disabled(tagDraft.isEmpty)
                    .buttonStyle(.plain)
            }
            .padding(.leading, DS.Space.s4)
            .padding(.trailing, DS.Space.s2)
            .frame(height: 40)
            .background(DS.gray100, in: Capsule(style: .continuous))
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s4)
    }

    private func tagChip(_ tag: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        Text(tag)
            .dsText(.label12)
            .foregroundStyle(active ? DS.tint : DS.textSecondary)
            .padding(.horizontal, DS.Space.s3)
            .frame(height: 28)
            .background(active ? DS.tintDim : DS.gray100, in: Capsule(style: .continuous))
            .onTapGesture(perform: onTap)
    }

    /// An active tag: the × makes removal visible; press-and-hold manages the
    /// tag across every thing (fixes typos, merges duplicates). The type tag
    /// is assigned at ingestion and carries no controls.
    @ViewBuilder
    private func activeTagChip(_ tag: String) -> some View {
        let isTypeTag = tag == thing.kind.typeTag
        HStack(spacing: DS.Space.s1) {
            Text(tag).dsText(.label12).foregroundStyle(DS.tint)
            if !isTypeTag {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.tint.opacity(0.6))
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .frame(height: 28)
        .background(DS.tintDim, in: Capsule(style: .continuous))
        .onTapGesture { remove(tag: tag) }
        .contextMenu {
            if !isTypeTag {
                Button("Remove from this thing", systemImage: "xmark.circle") {
                    remove(tag: tag)
                }
                Button("Rename everywhere…", systemImage: "pencil") {
                    renameDraft = tag
                    renameTarget = tag
                }
                Button("Delete everywhere…", systemImage: "trash", role: .destructive) {
                    deleteTarget = tag
                }
            }
        }
        .alert("Rename \"\(renameTarget ?? "")\" everywhere",
               isPresented: Binding(get: { renameTarget == tag },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("New name", text: $renameDraft)
            Button("Rename") { renameEverywhere(tag, to: renameDraft) }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Every thing with this tag gets the new name.")
        }
        .confirmationDialog("Delete \"\(deleteTarget ?? "")\" from every thing?",
                            isPresented: Binding(get: { deleteTarget == tag },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete everywhere", role: .destructive) { deleteEverywhere(tag) }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Things keep their content — only the tag goes.")
        }
    }

    /// Rewrites the tag across the whole corpus; a pinned project keeps its
    /// pin under the new name.
    private func renameEverywhere(_ old: String, to newRaw: String) {
        let new = newRaw.trimmingCharacters(in: .whitespaces)
        renameTarget = nil
        guard !new.isEmpty, new != old else { return }
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for t in all where t.tags.contains(old) {
            t.tags = t.tags.map { $0 == old ? new : $0 }
        }
        modelContext.saveHonestly()
        // A retag changes projectClusters but not things.count — Home composes
        // a doc, not a live @Query, so nudge it to recompose (the same signal
        // HomeScreen already listens on).
        CorpusSignal.shared.bump()
        DSHaptic.success()
    }

    private func deleteEverywhere(_ tag: String) {
        deleteTarget = nil
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for t in all where t.tags.contains(tag) {
            t.tags.removeAll { $0 == tag }
        }
        modelContext.saveHonestly()
        CorpusSignal.shared.bump()
        DSHaptic.success()
    }

    private func add(tag: String) {
        let t = tag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !thing.tags.contains(where: { $0.lowercased() == t.lowercased() }) else { return }
        thing.tags.append(t)
        modelContext.saveHonestly()
        CorpusSignal.shared.bump()
    }

    private func remove(tag: String) {
        // The type tag stays — it's assigned at ingestion, not user-managed.
        guard tag != thing.kind.typeTag else { return }
        thing.tags.removeAll { $0 == tag }
        modelContext.saveHonestly()
        CorpusSignal.shared.bump()
    }

    // MARK: - Related shelf (streams last)

    private var relatedShelf: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !relatedStream.els.isEmpty {
                Text(LocalizedStringKey(relatedTitle))
                    .dsText(.label12)
                    .foregroundStyle(DS.textTertiary)
                    .padding(.horizontal, DS.Space.s4)
            }
            GenRender(id: "root", els: relatedStream.els)
        }
    }

    private func streamRelated() {
        // A thing that can't have related items costs no fetch — the old
        // invariant, kept: only a watched token (mentions) or a tagged thing
        // (overlap) has anything to look for.
        let typeTags = Set(ThingKind.allCases.map(\.typeTag))
        let myTags = Set(thing.tags).subtracting(typeTags)
        let isToken = thing.source == "Tokens"
        guard isToken || !myTags.isEmpty else { return }

        var descriptor = FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300   // relatedness lives in the recent past
        let all = (try? modelContext.fetch(descriptor)) ?? []

        // A watched token's relatedness is MENTION, not tags (2026-07-14) —
        // every watchlist thing shares the Watchlist tag, so tag overlap only
        // ever surfaced the other watched tokens. The saves, chats, and
        // screenshots that name this token answer the question a watchlist
        // can't: why am I watching this? Tag overlap stays as the fallback.
        let mentions = isToken ? tokenMentions(in: all) : []
        let related: [Thing]
        if !mentions.isEmpty {
            relatedTitle = "In your things"
            related = mentions
        } else {
            guard !myTags.isEmpty else { return }
            // Meaning first (2026-07-14): rank the recent corpus by semantic
            // similarity to this thing, so a GitHub PR reaches the Linear
            // ticket, the chat, the note that share NO tag — the cross-source
            // weaving tag overlap can't find (a feed tag like "Stars" only ever
            // reaches other GitHub things). Tag overlap stays the fallback when
            // the on-device embedding is unavailable or this thing isn't
            // embedded yet.
            related = semanticRelated(in: all)
                ?? Array(all.filter { other in
                    other.id != thing.id && !myTags.isDisjoint(with: other.tags)
                }.prefix(6))
        }
        guard !related.isEmpty else { return }

        var doc = ["root = Shelf([\(related.indices.map { "c\($0)" }.joined(separator: ", "))])"]
        for (i, t) in related.enumerated() {
            let title = t.title.replacingOccurrences(of: "\"", with: "")
            doc.append("c\(i) = Chip(\"\(t.source)\", \"\(title)\")")
        }
        relatedStream.stream(doc)
    }

    /// The recent corpus ranked by on-device semantic similarity to this thing
    /// — the meaning-based Related set (EmbeddingIndex, the same vectors the
    /// answer path scores). Cross-source by nature: it scores by meaning, not
    /// source or tag. nil when the model is unavailable, this thing can't be
    /// embedded, or nothing clears the floor — the caller then falls back to
    /// tag overlap. The 0.5 cosine floor keeps it to genuine relations (looser
    /// than the answer path's 0.62 qualify floor — "related", not "answers").
    private func semanticRelated(in all: [Thing]) -> [Thing]? {
        guard EmbeddingIndex.isAvailable,
              let query = EmbeddingIndex.vector(for: EmbeddingIndex.indexText(for: thing))
        else { return nil }
        let qNorm = EmbeddingIndex.norm(query)
        guard qNorm > 0 else { return nil }
        let scored = all.compactMap { other -> (Thing, Double)? in
            guard other.id != thing.id, let data = other.embedding, !data.isEmpty else { return nil }
            let sim = EmbeddingIndex.similarity(query: query, queryNorm: qNorm, packed: data)
            return sim >= 0.5 ? (other, sim) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(6)
        .map(\.0)
        return scored.isEmpty ? nil : Array(scored)
    }

    /// Corpus things that MENTION this watched token — a cashtag ($PEPE,
    /// boundary-checked so $PEPE never claims $PEPEX) or the token's full
    /// name as a whole word when it's distinctive (4+ characters — "Pepe"
    /// matches, a name like "Sol" would false-hit half the corpus). Other
    /// watchlist rows are excluded: they're the watchlist, not context.
    private func tokenMentions(in all: [Thing]) -> [Thing] {
        guard thing.source == "Tokens" else { return [] }
        let symbol = TokensAsk.symbol(of: thing.title)
        let name = thing.title.components(separatedBy: " · $").first ?? ""
        var patterns: [String] = []
        if !symbol.isEmpty {
            patterns.append("\\$\(NSRegularExpression.escapedPattern(for: symbol))\\b")
        }
        if name.count >= 4 {
            patterns.append("\\b\(NSRegularExpression.escapedPattern(for: name))\\b")
        }
        guard !patterns.isEmpty,
              let regex = try? NSRegularExpression(pattern: patterns.joined(separator: "|"),
                                                   options: [.caseInsensitive])
        else { return [] }
        return Array(all.filter { other in
            guard other.id != thing.id, other.source != "Tokens" else { return false }
            let text = "\(other.title) \(other.content)"
            return regex.firstMatch(in: text, options: [],
                                    range: NSRange(text.startIndex..., in: text)) != nil
        }.prefix(6))
    }

    // MARK: - Verb execution

    private func perform(_ verb: Verb) async {
        confirmingVerb = nil
        verbResultIsError = false
        switch verb.action {
        case .openURL(let url):
            openURL(url)
        case .addToCalendar:
            do {
                try await HandOff.addToCalendar(thing)
                verbResult = "On your calendar"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .addToReminders:
            do {
                try await HandOff.addToReminders(thing)
                verbResult = "On your list"
            } catch { verbResult = error.localizedDescription; verbResultIsError = true }
        case .copyText:
            UIPasteboard.general.string = thing.content.isEmpty ? thing.title : thing.content
            verbResult = "Copied"
        case .markDone:
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            verbResult = "Done"
        case .translate:
            verbResult = nil
            translateText = thing.postText ?? thing.content
            showTranslate = true
        case .approve:
            // Demo bridge: the decision lands locally; the gateway wire is M5.
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            DSHaptic.success()
            verbResult = "Approved — sent to your gateway"
        case .deny:
            thing.mark = .done
            modelContext.saveHonestly()
            CorpusSignal.shared.bump()
            verbResult = "Denied — your gateway was told"
        }
    }

    private func shortTime(_ date: Date) -> String {
        let s = Date.now.timeIntervalSince(date)
        if s < 3600 { return "\(max(1, Int(s / 60)))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86_400))d"
    }
}

/// Minimal flow layout for tag chips (wraps like the prototype's flex-wrap).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
