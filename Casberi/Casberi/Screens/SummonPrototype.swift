import SwiftUI

/// THROWAWAY PROTOTYPE (2026-07-19) — the agent shell, ruled in
/// docs/agent-brief.md. Read that file before touching this one; it is the
/// durable record of WHY each piece below looks the way it does.
///
/// Reach it with `-summonProto YES`. Nothing else in the app is touched —
/// this is a full swap of the real shell, scenery included, so nothing here
/// leaks into or depends on the shipping app.
///
/// The loop (rulings 1-3, 6-9):
///   1. CONTENT — a stand-in feed. The app opens on things, not the agent
///      (ruling 2: content-first). The bar rides over it, the berry mark
///      breathing while an unseen signal changed (ruling 6 — no badges,
///      ever; the mark reuses Composer.swift's `.breathing()` idiom).
///   2. RISE — tapping the bar raises the agent full screen (ruling 3 — no
///      sheet/tray). One transition. This is the thing to FEEL, not just see.
///   3. REST (risen) — greeting, kept-ask chips wearing one-line signals
///      (ruling 4-5), the bar now editable.
///   4. STACK — an answer is a pushed screen; tapping content inside it
///      pushes a generative thing-view; "Open in app ↗" is the only way an
///      answer's content can eject you (ruling 8-9: staying is the default).
///   5. LOWER — ⌄ in the bar or ✕ top-right drops back to CONTENT, exactly
///      where you were (ruling 7 — both exits, on trial).
///
/// Every kept-ask doc is HAND-AUTHORED and deterministic — no model runs.
/// That is the point: the kept asks compose exactly the way `HomeComposition`
/// composes Home today, so the spine never depends on the on-device LLM
/// being clever. Only free text would route through it (not built here).
struct SummonPrototype: View {

    /// A kept ask — what a chip IS: a saved question plus the deterministic
    /// composer that answers it. `changed`/`delta` are the signal (ruling 5):
    /// changed is a diff against a stored last-seen (here: hardcoded, since
    /// there is no real corpus in the prototype); delta is that diff stated
    /// in words. Never a model judgment.
    struct KeptAsk: Identifiable, Equatable {
        let id: String
        let title: String
        let terms: [String]
        var changed = false
        var delta: String = ""
        let doc: [String]

        static func == (a: KeptAsk, b: KeptAsk) -> Bool { a.id == b.id }
    }

    /// Whether ANY kept ask still carries an unseen changed signal — what the
    /// bar's pulse and the whisper key off. Reset the moment the agent rises
    /// (ruling 6: "seeing = raised this launch"), not per-chip — a real build
    /// would clear per-chip on view, but the prototype only needs to prove the
    /// pulse turns off once you've looked.
    @State private var seenSignals = false
    @State private var risen = false

    @Namespace private var glassNS

    var body: some View {
        ZStack {
            standInContent

            if risen {
                AgentSurface(
                    onLower: { lower() }
                )
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .animation(DS.Motion.standard, value: risen)
        // `-summonStage rest|risen|answer|thing` jumps straight to a stage for
        // headless verification (computer-use typing trips the sim's accent
        // picker — CLAUDE.md). NSLogs the stage it lands on.
        .onAppear { applyStageHook() }
    }

    // MARK: - Stand-in content (scenery only — NOT the real MainSurface)

    private var standInContent: some View {
        ZStack(alignment: .bottom) {
            DS.page.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sourceChips
                    ForEach(Self.feedRows) { row in
                        feedRow(row)
                    }
                    // Room for the bar, which floats over the scroll.
                    Color.clear.frame(height: 120)
                }
            }

            if let whisper = Self.asks.first(where: { $0.changed && !seenSignals }) {
                whisperCapsule(whisper)
            }

            barOverContent
        }
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s2) {
                ForEach(["All", "Farcaster", "Wallet", "Peer", "1Claw", "Photos"], id: \.self) { name in
                    Text(name)
                        .dsText(.subhead13)
                        .foregroundStyle(name == "All" ? DS.textPrimary : DS.textTertiary)
                        .padding(.horizontal, DS.Space.s3)
                        .padding(.vertical, DS.Space.s2)
                        .background(name == "All" ? DS.fillStrong : DS.fillFaint,
                                    in: Capsule())
                }
            }
            .padding(.horizontal, DS.Space.s4)
        }
        .padding(.top, DS.Space.s3)
        .padding(.bottom, DS.Space.s2)
    }

    struct FeedRow: Identifiable {
        let id: String
        let glyph: String
        let glyphBg: Color
        let glyphFg: Color
        let eyebrow: String
        let hero: String
    }

    /// The user's own scroll-beats-ask examples (this session's argument for
    /// content-first) — a Peer fill and a 1Claw grant lead the stand-in feed.
    static let feedRows: [FeedRow] = [
        FeedRow(id: "peer", glyph: "P", glyphBg: Color(hex: "#132018"), glyphFg: Color(hex: "#34c77b"),
                eyebrow: "Peer · 2h", hero: "Bought 25 USDC with Venmo on Peer"),
        FeedRow(id: "1claw", glyph: "1C", glyphBg: Color(hex: "#2c1210"), glyphFg: Color(hex: "#ff8a80"),
                eyebrow: "1Claw · 4h", hero: "Vault grant: agent read · expires Fri"),
        FeedRow(id: "farcaster", glyph: "d", glyphBg: Color(hex: "#3a3120"), glyphFg: Color(hex: "#d8c48e"),
                eyebrow: "Farcaster · 1h", hero: "@dwr replied to your cast on on-device models"),
        FeedRow(id: "you", glyph: "↗", glyphBg: Color(hex: "#1a2330"), glyphFg: Color(hex: "#7fb8d8"),
                eyebrow: "You · Tue", hero: "base.org/airdrop — criteria"),
        FeedRow(id: "tokens", glyph: "Ξ", glyphBg: Color(hex: "#16311f"), glyphFg: Color(hex: "#5fe0a0"),
                eyebrow: "Tokens · now", hero: "ETH · $3,240 · +2.1%"),
        FeedRow(id: "photos", glyph: "◈", glyphBg: DS.fillFaint, glyphFg: DS.textTertiary,
                eyebrow: "Photos · today", hero: "4 new screenshots"),
    ]

    private func feedRow(_ row: FeedRow) -> some View {
        HStack(spacing: DS.Space.s3) {
            RoundedRectangle(cornerRadius: DS.Radius.appIcon(40), style: .continuous)
                .fill(row.glyphBg)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(row.glyph)
                        .dsText(.subhead13)
                        .foregroundStyle(row.glyphFg)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.eyebrow).dsText(.label12).foregroundStyle(DS.textTertiary)
                Text(row.hero).dsText(.callout15).foregroundStyle(DS.textPrimary).lineLimit(2)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s3)
    }

    /// The top changed signal, surfaced above the bar (ruling 6, flag-gated —
    /// built here since it is cheap and it is the clearest proof the agent
    /// "speaks" from the app side without a badge). Tapping it opens the
    /// agent with that ask already summoned.
    private func whisperCapsule(_ ask: KeptAsk) -> some View {
        Button {
            rise()
        } label: {
            HStack(spacing: 7) {
                Circle().fill(DS.tint).frame(width: 6, height: 6)
                Text(ask.title).dsText(.subhead13).foregroundStyle(DS.textPrimary)
                if !ask.delta.isEmpty {
                    Text("· \(ask.delta)").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .padding(.vertical, DS.Space.s2)
            .dsGlass(cornerRadius: DS.Radius.pill)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, 78)
    }

    /// The bar as it sits over CONTENT — a button dressed as the bar, not a
    /// live field (the field only exists once risen; typing into a surface
    /// behind another surface would be a different bug class entirely).
    private var barOverContent: some View {
        HStack(spacing: DS.Space.s3) {
            Text("Ask your things…")
                .dsText(.body17)
                .foregroundStyle(DS.textTertiary)
            Spacer(minLength: 0)
            // The berry, not a system glyph — its own established idiom for
            // "alive" (Composer.swift's `.breathing()`, "the librarian at
            // work"). Here it breathes for the same reason it does mid-answer:
            // something real is waiting, not a spinner standing in for nothing.
            if hasUnseenSignal {
                CasberiMark(size: 20).breathing()
            } else {
                CasberiMark(size: 20)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .dsGlass(cornerRadius: DS.Radius.pill, glassID: "agentbar", in: glassNS)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
        .contentShape(Capsule())
        .onTapGesture { rise() }
        .dsTapCard()
    }

    private var hasUnseenSignal: Bool {
        !seenSignals && Self.asks.contains { $0.changed }
    }

    // MARK: - Rise / lower (ruling 3, 7 — the transition to FEEL)

    private func rise() {
        NSLog("[SummonPrototype] stage: risen")
        seenSignals = true   // "seeing = the agent has been raised this launch"
        risen = true
    }

    private func lower() {
        NSLog("[SummonPrototype] stage: lowered")
        risen = false
    }

    // MARK: - Headless verification hook

    /// `-summonStage rest|risen|answer|thing` — jumps straight to a stage so
    /// every stage screenshots without typing through computer-use (which
    /// trips the sim's accent picker). `AgentSurface` reads the same default
    /// for its own sub-stages (answer/thing) via `initialStage`.
    private func applyStageHook() {
        let stage = UserDefaults.standard.string(forKey: "summonStage") ?? "rest"
        NSLog("[SummonPrototype] summonStage hook: %@", stage)
        guard stage != "rest" else { return }
        risen = true
    }

    /// Read by `AgentSurface.onAppear` to decide whether to auto-drill into an
    /// answer or a thing-view for the headless hook. Kept as a static read
    /// (not passed through State) so `SummonPrototype`'s own body stays simple.
    static var stageHookTarget: String {
        UserDefaults.standard.string(forKey: "summonStage") ?? "rest"
    }
}

// MARK: - The risen agent surface

/// The agent, full screen (ruling 3). Owns its own kept-ask state, its own
/// NavigationStack (ruling 8 — the Stack session model), and its own bar,
/// which is the SAME glass object the content-side bar is (shared glassID
/// would require a shared namespace across the transition; the prototype
/// settles for visual continuity via matched styling since the two bars
/// never coexist on screen at once).
private struct AgentSurface: View {
    let onLower: () -> Void

    @State private var query = ""
    @State private var stream = GenStream()
    @State private var streamed: String?
    @State private var path = NavigationPath()
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Changed-first, then alphabetical — ruling 5.
    private var sortedAsks: [SummonPrototype.KeptAsk] {
        SummonPrototype.asks.sorted { a, b in
            if a.changed != b.changed { return a.changed && !b.changed }
            return a.title < b.title
        }
    }

    private var narrowed: [SummonPrototype.KeptAsk] {
        guard !trimmed.isEmpty else { return sortedAsks }
        return sortedAsks.filter { ask in
            ask.title.lowercased().contains(trimmed)
                || ask.terms.contains { $0.contains(trimmed) }
        }
    }

    private var matched: SummonPrototype.KeptAsk? {
        guard trimmed.count >= 2 else { return nil }
        return narrowed.first
    }

    /// True once ANY answer is showing — the bar's placeholder becomes
    /// "Ask about this…" (ruling 8: follow-ups ground in the current answer).
    private var composing: Bool { matched != nil }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                DS.page.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !composing { greeting }
                        chipWrap
                        answer
                        Color.clear.frame(height: 160)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                // Tapping empty space puts the keyboard away WITHOUT lowering
                // the agent — a separate action from the bar's own ⌄/✕
                // (ruling 7's exits). Without this, the only tap that reached
                // past the keyboard was the one wired to onLower(), so asking
                // something and wanting to just SEE the answer meant leaving
                // the agent entirely to get there. Buttons inside (chips, the
                // drill-down link) still take their own tap first.
                .onTapGesture { focused = false }

                bar
            }
            .navigationDestination(for: ThingRoute.self) { route in
                GenerativeThingView(route: route, onOpenInApp: { onLower() })
            }
            .overlay(alignment: .topTrailing) {
                // ✕ — ruling 7's first exit. Only shown at the root of the
                // stack; a pushed thing-view uses the system back chevron.
                if path.isEmpty {
                    Button {
                        onLower()
                    } label: {
                        Image(systemName: "xmark")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.textSecondary)
                            .padding(10)
                            .background(DS.fillFaint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.Space.s3)
                    .padding(.trailing, DS.Space.s4)
                }
            }
        }
        .dsColorScheme()
        .animation(DS.Motion.standard, value: composing)
        .animation(DS.Motion.standard, value: narrowed)
        .onChange(of: query) { _, _ in retarget() }
        .onAppear { applyStageHook() }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Saturday morning.")
                .dsText(.heading34)
                .foregroundStyle(DS.textPrimary)
            Text("2,481 things, across 14 apps.")
                .dsText(.callout15)
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s8)
        .padding(.bottom, DS.Space.s6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// B1 pill chips (ruling 4), each wearing its signal (ruling 5): a dot
    /// only when changed, one line of delta in secondary ink. They survive
    /// into composing and narrow as filters.
    private var chipWrap: some View {
        FlowRow(spacing: DS.Space.s2) {
            ForEach(narrowed) { ask in
                Button {
                    query = ask.title
                    focused = true
                } label: {
                    HStack(spacing: 6) {
                        if ask.changed {
                            Circle().fill(DS.tint).frame(width: 6, height: 6)
                        }
                        Text(ask.title)
                            .dsText(.subhead13)
                            .foregroundStyle(ask.changed ? DS.textPrimary : DS.textSecondary)
                        if !ask.delta.isEmpty {
                            Text("· \(ask.delta)")
                                .dsText(.subhead13)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                    .padding(.horizontal, DS.Space.s3)
                    .padding(.vertical, DS.Space.s2)
                    .background(DS.fillFaint,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                     style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(ask.id == "recipes" ? 0.55 : 1)   // the decayed example
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, composing ? DS.Space.s4 : 0)
    }

    /// The composed answer — the SAME engine Home uses, rendering a summoned
    /// document instead of one hardcoded composition. Wrapped so a tap on a
    /// tappable row PUSHES a generative thing-view (ruling 8) instead of
    /// opening the real app (ruling 9: staying is the default).
    @ViewBuilder private var answer: some View {
        if let ask = matched {
            GenRender(id: "root", els: stream.els)
                .padding(.top, DS.Space.s4)
                .transition(.opacity)

            // The prototype's one hand-built drill-down (brief step 6): the
            // "While I was away?" answer's mention row pushes a thing-view.
            // Not a new GenRenderer component — plain SwiftUI, scoped to this
            // one ask, because the answer-anatomy work is explicitly deferred.
            if ask.id == "away" {
                Button {
                    path.append(ThingRoute.dwrMention)
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Text("Open the mention")
                            .dsText(.subhead13)
                            .foregroundStyle(DS.tint)
                        Image(systemName: "arrow.up.forward")
                            .dsText(.label12)
                            .foregroundStyle(DS.tint)
                    }
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.top, DS.Space.s2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The bar risen — a live field. Placeholder swaps to "Ask about this…"
    /// while an answer is up (ruling 8). ⌄ is the second exit (ruling 7).
    private var bar: some View {
        HStack(spacing: DS.Space.s3) {
            Button {
                onLower()
            } label: {
                Image(systemName: "chevron.down")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(DS.fillFaint, in: Circle())
            }
            .buttonStyle(.plain)

            TextField(composing ? "Ask about this…" : "Ask your things…", text: $query)
                .textFieldStyle(.plain)
                .dsText(.body17)
                .foregroundStyle(DS.textPrimary)
                .focused($focused)
                .submitLabel(.go)

            if !query.isEmpty {
                Button {
                    query = ""
                    streamed = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.textTertiary)
                        .dsTapTarget(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .dsGlass(cornerRadius: DS.Radius.pill)
        .padding(.horizontal, DS.Space.s4)
        .padding(.bottom, DS.Space.s3)
    }

    // MARK: - Streaming

    /// Streams only on a change of target — re-streaming on every keystroke
    /// would restart the typewriter and the answer would stutter as you type.
    private func retarget() {
        guard let ask = matched else {
            streamed = nil
            return
        }
        guard ask.id != streamed else { return }
        streamed = ask.id
        stream.stream(ask.doc)
    }

    /// `-summonStage risen|answer|thing` — the risen surface auto-fills a
    /// query (answer/thing) or pushes straight to the thing-view (thing).
    private func applyStageHook() {
        let stage = SummonPrototype.stageHookTarget
        switch stage {
        case "answer", "thing":
            query = "away"
            retarget()
            if stage == "thing" {
                path.append(ThingRoute.dwrMention)
            }
        default:
            break
        }
    }
}

/// The one route the prototype's thing-view supports — enough to prove the
/// push works without building a general router.
private enum ThingRoute: Hashable {
    case dwrMention
}

/// A hand-built generative thing-view (brief step 6) — NOT a new GenRenderer
/// component (that's the deferred answer-anatomy work). "Open in app ↗" is
/// the only verb that lowers the agent from inside an answer (ruling 9).
private struct GenerativeThingView: View {
    let route: ThingRoute
    let onOpenInApp: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                HStack(spacing: DS.Space.s3) {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: "#8a6d3b"), Color(hex: "#5c4a28")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dwr").dsText(.heading17).foregroundStyle(DS.textPrimary)
                        Text("Farcaster · 1h ago · replying to you")
                            .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                }

                Text("on-device models are the whole game — the moment retrieval is local, the corpus stops being a product and starts being yours.")
                    .dsText(.heading17)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("14 likes · 3 recasts")
                    .dsText(.subhead13)
                    .foregroundStyle(DS.textTertiary)

                HStack(spacing: DS.Space.s2) {
                    Text("Profile")
                        .dsText(.subhead13).foregroundStyle(DS.textPrimary)
                        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                        .background(DS.fillFaint, in: Capsule())

                    Button {
                        NSLog("[SummonPrototype] stage: opened in app (lowered from thing-view)")
                        onOpenInApp()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Open in app")
                            Image(systemName: "arrow.up.forward")
                        }
                        .dsText(.subhead13)
                        .foregroundStyle(DS.tint)
                        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                        .background(DS.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    Text("Replies").dsText(.label12).foregroundStyle(DS.textTertiary)
                    replyRow(name: "varun", body: "this is why the embedding index matters more than the model size")
                    replyRow(name: "maria.eth", body: "local-first or it doesn't count")
                }
                .padding(.top, DS.Space.s2)
            }
            .padding(DS.Space.s4)
        }
        .background(DS.page)
        .navigationTitle("Cast")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func replyRow(name: String, body: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Circle().fill(DS.fillFaint).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).dsText(.label12).foregroundStyle(DS.textSecondary)
                Text(body).dsText(.subhead13).foregroundStyle(DS.textPrimary)
            }
        }
    }
}

// MARK: - The kept asks (deterministic composers — no model)

extension SummonPrototype {
    static let asks: [KeptAsk] = [
        KeptAsk(
            id: "money",
            title: "How's my money?",
            terms: ["money", "wallet", "balance", "holdings", "worth"],
            delta: "$12,480",
            doc: [
                "root = Stack([hd, map, w])",
                #"hd = Hero("Across 2 wallets", "$12,480", "Up $312 today")"#,
                #"map = TagMap("Holdings", null, [ETH 38, USDC 24, DEGEN 16, SOL 12, Other 10])"#,
                #"w = Widget("Biggest movers", "24 hours", [r1, r2])"#,
                #"r1 = Row("ETH", "+2.1%", "Wallet", "now")"#,
                #"r2 = Row("DEGEN", "-4.4%", "Wallet", "now")"#,
            ]),

        KeptAsk(
            id: "away",
            title: "While I was away?",
            terms: ["away", "while", "missed", "new", "since"],
            changed: true,
            delta: "12 new",
            doc: [
                "root = Stack([i, w])",
                #"i = Insight("12 new while you were away, 3 mentioning you.", "", "", "feed")"#,
                #"w = Widget("Worth a look", "Since yesterday", [r1, r2, r3])"#,
                #"r1 = Row("@dwr replied to your cast on on-device models", "Mention", "Farcaster", "1h")"#,
                #"r2 = Row("2 replies on your Bluesky post", "Mention", "Bluesky", "3h")"#,
                #"r3 = Row("Pushed 4 commits to main", "Repo", "GitHub", "3h")"#,
            ]),

        KeptAsk(
            id: "airdrop",
            title: "Base airdrop",
            terms: ["base", "airdrop", "eligibility", "snapshot"],
            changed: true,
            delta: "snapshot Fri",
            doc: [
                "root = Stack([i, w])",
                #"i = Insight("Three things you saved circle the same drop. The snapshot is Friday.", "", "", "feed")"#,
                #"w = Widget("What you have", "Across 3 apps", [r1, r2, r3])"#,
                #"r1 = Row("eligibility snapshot is Friday", "Cast", "Farcaster", "2h")"#,
                #"r2 = Row("base.org/airdrop - criteria", "Link", "You", "Tue")"#,
                #"r3 = Row("Screenshot - wallet eligibility", "Photo", "Photos", "Mar 4")"#,
            ]),

        KeptAsk(
            id: "overdue",
            title: "What's overdue?",
            terms: ["overdue", "late", "due", "reminders", "todo"],
            delta: "1, 3d late",
            doc: [
                "root = Stack([w])",
                #"w = Widget("Overdue", "One thing, 3 days late", [r1])"#,
                #"r1 = Row("Renew passport", "Overdue", "Reminders", "3d")"#,
            ]),

        KeptAsk(
            id: "week",
            title: "This week",
            terms: ["week", "recent", "recap"],
            delta: "94 things",
            doc: [
                "root = Stack([i, w])",
                #"i = Insight("94 things this week - mostly reading, mostly about Base.", "", "", "feed")"#,
                #"w = Widget("This week", "7 days", [r1, r2])"#,
                #"r1 = Row("41 links saved", "Links", "You", "7d")"#,
                #"r2 = Row("18 casts liked", "Social", "Farcaster", "7d")"#,
            ]),

        KeptAsk(
            id: "dwr",
            title: "dwr",
            terms: ["dwr", "dan", "person"],
            delta: "2 casts today",
            doc: [
                "root = Stack([w])",
                #"w = Widget("dwr", "Farcaster - GitHub", [r1, r2])"#,
                #"r1 = Row("Replied to your cast on on-device models", "Mention", "Farcaster", "1h")"#,
                #"r2 = Row("2 casts today", "Cast", "Farcaster", "5h")"#,
            ]),

        // The one decayed example (ruling 5: ignored asks decay dim).
        KeptAsk(
            id: "recipes",
            title: "Show recipes",
            terms: ["recipes", "food", "cook"],
            doc: [
                "root = Stack([w])",
                #"w = Widget("Recipes", "Untapped for weeks", [r1])"#,
                #"r1 = Row("Weeknight pasta ideas", "Note", "Notes", "3w")"#,
            ]),
    ]
}

/// A minimal wrapping row — the chips need to flow onto several lines and
/// SwiftUI has no built-in for it at this deployment target. Prototype-grade.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 {
                x = 0
                y += lineH + spacing
                lineH = 0
            }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineH + spacing
                lineH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
